--@ module=true

-- Reload-safe prompt-first input dispatch for native and Lua screens.

local function_chain = reqscript('dwarfuicore/utils/function_chain')
local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')

local API_VERSION = 2
local STATE_SLOT = 'context_menu_input_hook'
local NATIVE_METHOD = 'feed_viewscreen_widgets'
local SCREEN_METHOD = 'onInput'

---@enum dwarfuicore.ContextMenuInputTransport
ContextMenuInputTransport = immutable_enum.define({
    NATIVE=1,
    SCREEN=2,
}, 'ContextMenuInputTransport')

---@enum dwarfuicore.InputConsumerKind
InputConsumerKind = immutable_enum.define({
    PRIORITY=1,
    CONTEXT_MENU=2,
}, 'InputConsumerKind')

local PRIORITY_CONSUMER_FIELDS = {
    owns=true,
    handle=true,
    on_failure=true,
}

dfhack.dwarfuicore = dfhack.dwarfuicore or {}
local process_state = dfhack.dwarfuicore[STATE_SLOT]
local publish_process_state = false
local runtime_state = dfhack.dwarfuicore.service_provider_runtime
local runtime_generation = runtime_state and runtime_state.generation or 0
if process_state and process_state.api_version ~= API_VERSION then
    error(('Conflicting DwarfUICore context-menu input-hook versions: ' ..
        'process has %s, requested %s.'):format(
            tostring(process_state.api_version), tostring(API_VERSION)))
end
if process_state and runtime_generation > 0 then
    assert(process_state.runtime_generation == runtime_generation,
        'DwarfUICore context-menu input hook belongs to another runtime generation.')
end
if not process_state then
    process_state = {
        api_version=API_VERSION,
        runtime_generation=runtime_generation,
        generation=1,
        context_handler=nil,
        context_failure_handler=nil,
        prepared_consumer=nil,
        priority_consumer=nil,
        context_roots=setmetatable({}, {__mode='k'}),
        native_module=nil,
        native_hook=nil,
        screen_hooks=setmetatable({}, {__mode='k'}),
        retired_hooks={},
        dispatch_count=0,
        handled_count=0,
        delegated_count=0,
        failure_count=0,
        priority_dispatch_count=0,
        priority_handled_count=0,
        priority_delegated_count=0,
        priority_failure_count=0,
        last_error=nil,
        last_failure=nil,
        last_cleanup_error=nil,
        disabled_generation=nil,
    }
    publish_process_state = true
end

---@class dwarfuicore.ContextMenuInputHookRecord
---@field transport dwarfuicore.ContextMenuInputTransport
---@field owner table|nil
---@field owner_ref table|nil
---@field active_trampoline function
---@field predecessor function
---@field predecessor_had_raw_method boolean|nil
---@field predecessor_raw_method function|nil
---@field generation integer
---@field active boolean
---@field foreign_outer_wrapper boolean

---@class dwarfuicore.ContextMenuInputHookState
---@field api_version integer
---@field runtime_generation integer
---@field generation integer
---@field context_handler function|nil
---@field context_failure_handler function|nil
---@field prepared_consumer dwarfuicore.PreparedPriorityInputConsumer|nil
---@field priority_consumer dwarfuicore.PreparedPriorityInputConsumer|nil
---@field context_roots table<any, boolean>
---@field native_module table|nil
---@field native_hook dwarfuicore.ContextMenuInputHookRecord|nil
---@field screen_hooks table<table, dwarfuicore.ContextMenuInputHookRecord>
---@field retired_hooks dwarfuicore.ContextMenuInputHookRecord[]
---@field dispatch_count integer
---@field handled_count integer
---@field delegated_count integer
---@field failure_count integer
---@field priority_dispatch_count integer
---@field priority_handled_count integer
---@field priority_delegated_count integer
---@field priority_failure_count integer
---@field last_error string|nil
---@field last_failure table|nil
---@field last_cleanup_error string|nil
---@field disabled_generation integer|nil
---@field manager? dwarfuicore.ContextMenuInputHookManager

---@class dwarfuicore.PriorityInputConsumer
---@field owns fun(keys: table, transport: dwarfuicore.ContextMenuInputTransport, owner: table): boolean
---@field handle fun(keys: table, transport: dwarfuicore.ContextMenuInputTransport, owner: table): boolean
---@field on_failure? fun(message: string)

---@class dwarfuicore.PreparedPriorityInputConsumer: dwarfuicore.PriorityInputConsumer
---@field root any
---@field active boolean
---@field released boolean

---@class dwarfuicore.ContextMenuInputHookManager
---@field _state dwarfuicore.ContextMenuInputHookState
ContextMenuInputHookManager = {}
ContextMenuInputHookManager.__index = ContextMenuInputHookManager

---Returns the authoritative process state for trampoline adoption.
---@return dwarfuicore.ContextMenuInputHookState|nil
local function get_process_state()
    return dfhack.dwarfuicore and dfhack.dwarfuicore[STATE_SLOT] or nil
end

---Preserves every predecessor return, including trailing nil values.
---@param packed table
---@return ...
local function unpack_returns(packed)
    return table.unpack(packed, 1, packed.n)
end

---Records one context-menu failure before delegating unchanged.
---@param state dwarfuicore.ContextMenuInputHookState
---@param transport dwarfuicore.ContextMenuInputTransport
---@param owner table
---@param failure any
local function fail_dispatch(state, transport, owner, failure)
    local rendered = tostring(failure)
    state.failure_count = state.failure_count + 1
    state.last_error = rendered
    state.last_failure = {
        generation=state.generation,
        consumer_kind=InputConsumerKind.CONTEXT_MENU,
        owned=false,
        transport=transport,
        owner=transport == ContextMenuInputTransport.NATIVE and owner or nil,
        owner_ref=transport == ContextMenuInputTransport.SCREEN and
            setmetatable({owner}, {__mode='v'}) or nil,
        error=rendered,
    }
    state.disabled_generation = state.generation
    local callback = state.context_failure_handler
    state.context_handler = nil
    if dfhack.printerr then
        pcall(dfhack.printerr,
            'DwarfUICore context-menu input hook failed:\n' .. rendered)
    end
    if callback then
        pcall(callback, rendered)
    end
end

---Records an injected-consumer failure and notifies its owner.
---@param state dwarfuicore.ContextMenuInputHookState
---@param consumer dwarfuicore.PreparedPriorityInputConsumer
---@param transport dwarfuicore.ContextMenuInputTransport
---@param owner table
---@param failure any
---@param owned boolean
local function fail_priority_dispatch(state, consumer, transport, owner,
        failure, owned)
    local rendered = tostring(failure)
    state.priority_failure_count = state.priority_failure_count + 1
    state.last_error = rendered
    state.last_failure = {
        generation=state.generation,
        consumer_kind=InputConsumerKind.PRIORITY,
        owned=owned,
        transport=transport,
        owner=transport == ContextMenuInputTransport.NATIVE and owner or nil,
        owner_ref=transport == ContextMenuInputTransport.SCREEN and
            setmetatable({owner}, {__mode='v'}) or nil,
        error=rendered,
    }
    if state.priority_consumer == consumer then
        state.priority_consumer = nil
        consumer.active = false
    end
    if dfhack.printerr then
        pcall(dfhack.printerr,
            'DwarfUICore priority input consumer failed:\n' .. rendered)
    end
    if consumer.on_failure then pcall(consumer.on_failure, rendered) end
end

---Runs one callback and requires an exact boolean result.
---@param callback function
---@param message string
---@param keys table
---@param transport dwarfuicore.ContextMenuInputTransport
---@param owner table
---@return boolean ok
---@return boolean|string result
local function call_boolean(callback, message, keys, transport, owner)
    return xpcall(function()
        local result = callback(keys, transport, owner)
        assert(type(result) == 'boolean', message)
        return result
    end, debug.traceback)
end

---Runs the priority consumer before the context-menu opening adapter.
---@param transport dwarfuicore.ContextMenuInputTransport
---@param owner table
---@param keys table
---@return boolean handled
local function dispatch(transport, owner, keys)
    local state = get_process_state()
    if not state then return false end

    local consumer = state.priority_consumer
    if consumer then
        state.priority_dispatch_count = state.priority_dispatch_count + 1
        local owns_ok, owned = call_boolean(consumer.owns,
            'DwarfUICore priority input ownership must return a boolean.',
            keys, transport, owner)
        if not owns_ok then
            state.priority_delegated_count =
                state.priority_delegated_count + 1
            fail_priority_dispatch(
                state, consumer, transport, owner, owned, false)
        elseif owned then
            local handled_ok, handled = call_boolean(consumer.handle,
                'DwarfUICore priority input handler must return a boolean.',
                keys, transport, owner)
            if not handled_ok then
                fail_priority_dispatch(
                    state, consumer, transport, owner, handled, true)
                return true
            end
            if handled then
                state.priority_handled_count =
                    state.priority_handled_count + 1
                return true
            end
            state.priority_delegated_count =
                state.priority_delegated_count + 1
        else
            state.priority_delegated_count =
                state.priority_delegated_count + 1
        end
    end

    if state.disabled_generation == state.generation or
            type(state.context_handler) ~= 'function' then return false end
    state.dispatch_count = state.dispatch_count + 1
    local ok, handled = call_boolean(state.context_handler,
        'DwarfUICore context-menu input handler must return a boolean.',
        keys, transport, owner)
    if not ok then
        fail_dispatch(state, transport, owner, handled)
        return false
    end
    if handled then
        state.handled_count = state.handled_count + 1
    else
        state.delegated_count = state.delegated_count + 1
    end
    return handled
end

---Builds the native pre-delegation input trampoline.
---@param owner table
---@param predecessor function
---@return function
local function make_native_trampoline(owner, predecessor)
    local trampoline
    trampoline = function(viewscreen_name, viewscreen, keys, ...)
        local state = get_process_state()
        local record = state and state.native_hook
        if record and record.active and
                record.active_trampoline == trampoline and
                dispatch(ContextMenuInputTransport.NATIVE, owner, keys) then
            return true
        end
        return unpack_returns(table.pack(
            predecessor(viewscreen_name, viewscreen, keys, ...)))
    end
    return trampoline
end

---Builds one Lua-screen pre-delegation input trampoline.
---@param owner_ref table
---@param predecessor function
---@return function
local function make_screen_trampoline(owner_ref, predecessor)
    local trampoline
    trampoline = function(self, keys, ...)
        local owner = owner_ref[1]
        local state = get_process_state()
        local record = state and owner and state.screen_hooks[owner]
        if record and record.active and
                record.active_trampoline == trampoline and
                dispatch(ContextMenuInputTransport.SCREEN, owner, keys) then
            return true
        end
        return unpack_returns(table.pack(predecessor(self, keys, ...)))
    end
    return trampoline
end

---Creates a manager facade over the process-owned input-hook state.
---@param state dwarfuicore.ContextMenuInputHookState
---@return dwarfuicore.ContextMenuInputHookManager
function ContextMenuInputHookManager.new(state)
    assert(type(state) == 'table' and state.api_version == API_VERSION,
        'DwarfUICore context-menu input-hook state has an incompatible version.')
    return setmetatable({_state=state}, ContextMenuInputHookManager)
end

---Installs the context-menu consumer adapter and its failure observer.
---@param handler function|nil
---@param failure_handler? fun(message: string)
function ContextMenuInputHookManager:set_context_consumer(
        handler, failure_handler)
    assert(handler == nil or type(handler) == 'function',
        'DwarfUICore context-menu input handler must be a function.')
    assert(failure_handler == nil or type(failure_handler) == 'function',
        'DwarfUICore context-menu hook failure handler must be a function.')
    self._state.context_handler = handler
    self._state.context_failure_handler = failure_handler
end

---Ensures the input seam required by one supported root.
---@param root any
---@return boolean changed
function ContextMenuInputHookManager:_ensure_root(root)
    local root_type = type(root)
    assert(root_type == 'table' or root_type == 'userdata',
        'DwarfUICore priority input root must be a table or native widget container.')
    if root_type == 'table' and root._native ~= nil then
        assert(type(root[SCREEN_METHOD]) == 'function',
            'DwarfUICore priority screen root must provide onInput.')
        return self:ensure_screen(root)
    end
    return self:ensure_native()
end

---Resolves the exact current root that can share the existing input seam.
---A tracked Lua screen wins; otherwise the current native map viewscreen lends
---its widget root to the native overlay transport.
---@return any|nil root
function ContextMenuInputHookManager:resolve_current_surface()
    local gui_api = dfhack.gui
    if type(gui_api) ~= 'table' or
            type(gui_api.getCurViewscreen) ~= 'function' or
            type(gui_api.getDFViewscreen) ~= 'function' then
        return nil
    end
    local current = gui_api.getCurViewscreen(true)
    for owner, record in pairs(self._state.screen_hooks) do
        if record.active and owner._native == current and
                type(owner.onInput) == 'function' then
            return owner
        end
    end
    for root in pairs(self._state.context_roots) do
        if type(root) == 'table' and root._native == current and
                type(root.onInput) == 'function' then
            return root
        end
    end
    local native = gui_api.getDFViewscreen(true)
    if native ~= nil and current == native and native.widgets ~= nil then
        return native.widgets
    end
    return nil
end

---Prepares every fallible dependency for one priority consumer.
---The returned value is inactive until activate_priority_consumer() commits it.
---@param root any
---@param consumer dwarfuicore.PriorityInputConsumer
---@return dwarfuicore.PreparedPriorityInputConsumer prepared
function ContextMenuInputHookManager:prepare_priority_consumer(root, consumer)
    assert(self._state.priority_consumer == nil and
            self._state.prepared_consumer == nil,
        'DwarfUICore priority input consumer is already prepared or active.')
    assert(type(consumer) == 'table' and getmetatable(consumer) == nil,
        'DwarfUICore priority input consumer must be a plain table.')
    for key in pairs(consumer) do
        assert(PRIORITY_CONSUMER_FIELDS[key],
            'DwarfUICore priority input consumer contains an unknown field.')
    end
    assert(type(consumer.owns) == 'function',
        'DwarfUICore priority input consumer requires owns().')
    assert(type(consumer.handle) == 'function',
        'DwarfUICore priority input consumer requires handle().')
    assert(consumer.on_failure == nil or
            type(consumer.on_failure) == 'function',
        'DwarfUICore priority input consumer on_failure must be a function.')
    self:_ensure_root(root)
    local prepared = {
        root=root,
        owns=consumer.owns,
        handle=consumer.handle,
        on_failure=consumer.on_failure,
        active=false,
        released=false,
    }
    self._state.prepared_consumer = prepared
    return prepared
end

---Activates one prepared consumer using only non-throwing assignments.
---@param prepared any
---@return boolean activated
function ContextMenuInputHookManager:activate_priority_consumer(prepared)
    if self._state.prepared_consumer ~= prepared or
            type(prepared) ~= 'table' or prepared.released or prepared.active or
            self._state.priority_consumer ~= nil then return false end
    self._state.prepared_consumer = nil
    self._state.priority_consumer = prepared
    prepared.active = true
    return true
end

---Releases an active or merely prepared consumer as idempotent rollback.
---Hook cleanup is best effort so ownership always clears even if repair fails.
---@param prepared any
---@return boolean changed
function ContextMenuInputHookManager:release_priority_consumer(prepared)
    if type(prepared) ~= 'table' then return false end
    local changed = false
    if self._state.prepared_consumer == prepared then
        self._state.prepared_consumer = nil
        changed = true
    end
    if self._state.priority_consumer == prepared then
        self._state.priority_consumer = nil
        changed = true
    end
    prepared.active = false
    if prepared.released then return changed end
    prepared.released = true
    local ok, reconciled = xpcall(function()
        return self:_reconcile_effective_roots()
    end, debug.traceback)
    if ok then return reconciled or changed end
    self._state.last_cleanup_error = tostring(reconciled)
    if dfhack.printerr then
        pcall(dfhack.printerr,
            'DwarfUICore priority input cleanup failed:\n' ..
                tostring(reconciled))
    end
    return changed
end

---Installs or adopts the native overlay input seam.
---@return boolean changed
function ContextMenuInputHookManager:ensure_native()
    local state = self._state
    local overlay = require('plugins.overlay')
    local current = overlay[NATIVE_METHOD]
    assert(type(current) == 'function',
        'plugins.overlay.feed_viewscreen_widgets must be a function.')
    local previous = state.native_hook
    if state.native_module == overlay and previous and
            current == previous.active_trampoline then
        previous.active = true
        previous.generation = state.generation
        return false
    end
    if state.native_module == overlay and previous and
            function_chain.wraps(current, previous.active_trampoline) then
        previous.active = true
        previous.foreign_outer_wrapper = true
        previous.generation = state.generation
        return false
    end
    if previous then
        previous.active = false
    end
    local trampoline = make_native_trampoline(overlay, current)
    state.native_module = overlay
    state.native_hook = {
        transport=ContextMenuInputTransport.NATIVE,
        owner=overlay,
        active_trampoline=trampoline,
        predecessor=current,
        generation=state.generation,
        active=true,
        foreign_outer_wrapper=false,
    }
    overlay[NATIVE_METHOD] = trampoline
    return true
end

---Installs or adopts one Lua screen's effective input method.
---@param owner table
---@return boolean changed
function ContextMenuInputHookManager:ensure_screen(owner)
    assert(type(owner) == 'table',
        'DwarfUICore context-menu screen-hook owner must be a table.')
    local current = owner[SCREEN_METHOD]
    assert(type(current) == 'function',
        'DwarfUICore context-menu screen owner onInput must be a function.')
    local state = self._state
    local previous = state.screen_hooks[owner]
    if previous and current == previous.active_trampoline then
        previous.active = true
        previous.generation = state.generation
        return false
    end
    if previous and
            function_chain.wraps(current, previous.active_trampoline) then
        previous.active = true
        previous.foreign_outer_wrapper = true
        previous.generation = state.generation
        return false
    end
    if previous then
        previous.active = false
    end
    local raw_method = rawget(owner, SCREEN_METHOD)
    local owner_ref = setmetatable({owner}, {__mode='v'})
    local trampoline = make_screen_trampoline(owner_ref, current)
    state.screen_hooks[owner] = {
        transport=ContextMenuInputTransport.SCREEN,
        owner_ref=owner_ref,
        active_trampoline=trampoline,
        predecessor=current,
        predecessor_had_raw_method=raw_method ~= nil,
        predecessor_raw_method=raw_method,
        generation=state.generation,
        active=true,
        foreign_outer_wrapper=false,
    }
    rawset(owner, SCREEN_METHOD, trampoline)
    return true
end

---Retires one screen hook and restores only an outermost owned method.
---@param owner table
---@param record dwarfuicore.ContextMenuInputHookRecord
---@return boolean restored
function ContextMenuInputHookManager:_retire_screen(owner, record)
    record.active = false
    local restored = false
    local current = rawget(owner, SCREEN_METHOD)
    if current == record.active_trampoline then
        if record.predecessor_had_raw_method then
            rawset(owner, SCREEN_METHOD, record.predecessor_raw_method)
        else
            rawset(owner, SCREEN_METHOD, nil)
        end
        restored = true
    else
        record.foreign_outer_wrapper =
            type(current) == 'function' and
            function_chain.wraps(current, record.active_trampoline)
        if record.foreign_outer_wrapper then
            table.insert(self._state.retired_hooks, record)
        end
    end
    self._state.screen_hooks[owner] = nil
    return restored
end

---Stores context-menu roots and reconciles them with priority-consumer demand.
---@param roots table<any, boolean>
---@return boolean changed
function ContextMenuInputHookManager:reconcile_roots(roots)
    assert(type(roots) == 'table',
        'DwarfUICore context-menu hook reconciliation requires a root set.')
    local copied = setmetatable({}, {__mode='k'})
    for root, attached in pairs(roots) do
        assert(attached == true,
            'DwarfUICore context-menu root membership must be true.')
        local root_type = type(root)
        assert(root_type == 'table' or root_type == 'userdata',
            'DwarfUICore context-menu roots must be tables or native widget containers.')
        copied[root] = true
    end
    self._state.context_roots = copied
    return self:_reconcile_effective_roots()
end

---Reconciles the sole hook chain with every current internal root demand.
---@return boolean changed
function ContextMenuInputHookManager:_reconcile_effective_roots()
    local state = self._state
    local roots = setmetatable({}, {__mode='k'})
    for root in pairs(state.context_roots) do roots[root] = true end
    local priority = state.priority_consumer or state.prepared_consumer
    if priority and priority.root then roots[priority.root] = true end
    local screen_roots = setmetatable({}, {__mode='k'})
    local needs_native = false
    for root in pairs(roots) do
        if type(root) == 'table' and root._native ~= nil and
                type(root[SCREEN_METHOD]) == 'function' then
            screen_roots[root] = true
        else
            needs_native = true
        end
    end
    local changed = false
    if needs_native then
        changed = self:ensure_native() or changed
    elseif state.native_hook then
        local record = state.native_hook
        record.active = false
        local owner = record.owner
        if owner[NATIVE_METHOD] == record.active_trampoline then
            owner[NATIVE_METHOD] = record.predecessor
            changed = true
        else
            record.foreign_outer_wrapper =
                type(owner[NATIVE_METHOD]) == 'function' and
                function_chain.wraps(
                    owner[NATIVE_METHOD], record.active_trampoline)
            if record.foreign_outer_wrapper then
                table.insert(state.retired_hooks, record)
            end
        end
        state.native_hook = nil
        state.native_module = nil
    end
    for owner, record in pairs(state.screen_hooks) do
        if not screen_roots[owner] then
            changed = self:_retire_screen(owner, record) or changed
        end
    end
    for owner in pairs(screen_roots) do
        changed = self:ensure_screen(owner) or changed
    end
    return changed
end

---Makes all trampolines transparent and restores exact outermost owners.
---@return boolean changed
function ContextMenuInputHookManager:shutdown()
    local state = self._state
    local changed = false
    if state.priority_consumer then
        state.priority_consumer.active = false
        state.priority_consumer.released = true
        state.priority_consumer = nil
        changed = true
    end
    if state.prepared_consumer then
        state.prepared_consumer.released = true
        state.prepared_consumer = nil
        changed = true
    end
    state.context_handler = nil
    state.context_failure_handler = nil
    state.context_roots = setmetatable({}, {__mode='k'})
    state.disabled_generation = state.generation
    if state.native_hook then
        local record = state.native_hook
        record.active = false
        if record.owner[NATIVE_METHOD] == record.active_trampoline then
            record.owner[NATIVE_METHOD] = record.predecessor
            changed = true
        else
            record.foreign_outer_wrapper =
                type(record.owner[NATIVE_METHOD]) == 'function' and
                function_chain.wraps(
                    record.owner[NATIVE_METHOD],
                    record.active_trampoline)
            if record.foreign_outer_wrapper then
                table.insert(state.retired_hooks, record)
            end
        end
    end
    state.native_hook = nil
    state.native_module = nil
    for owner, record in pairs(state.screen_hooks) do
        changed = self:_retire_screen(owner, record) or changed
    end
    state.screen_hooks = setmetatable({}, {__mode='k'})
    return changed
end

---Returns hook ownership, inert-chain, dispatch, and failure diagnostics.
---@return table
function ContextMenuInputHookManager:get_diagnostics()
    local state = self._state
    local screen_count = 0
    for _ in pairs(state.screen_hooks) do screen_count = screen_count + 1 end
    local inert_count = 0
    for _, record in ipairs(state.retired_hooks) do
        if record.foreign_outer_wrapper then inert_count = inert_count + 1 end
    end
    local native = state.native_hook
    return {
        api_version=state.api_version,
        generation=state.generation,
        consumer_order={
            InputConsumerKind.PRIORITY,
            InputConsumerKind.CONTEXT_MENU,
        },
        priority_consumer_active=state.priority_consumer ~= nil,
        priority_consumer_prepared=state.prepared_consumer ~= nil,
        context_consumer_installed=
            type(state.context_handler) == 'function',
        handler_installed=type(state.context_handler) == 'function',
        disabled=state.disabled_generation == state.generation,
        disabled_generation=state.disabled_generation,
        dispatch_count=state.dispatch_count,
        handled_count=state.handled_count,
        delegated_count=state.delegated_count,
        failure_count=state.failure_count,
        priority_dispatch_count=state.priority_dispatch_count,
        priority_handled_count=state.priority_handled_count,
        priority_delegated_count=state.priority_delegated_count,
        priority_failure_count=state.priority_failure_count,
        last_error=state.last_error,
        last_failure=state.last_failure and {
            generation=state.last_failure.generation,
            consumer_kind=state.last_failure.consumer_kind,
            owned=state.last_failure.owned,
            transport=state.last_failure.transport,
            owner=state.last_failure.owner or
                (state.last_failure.owner_ref and
                    state.last_failure.owner_ref[1]) or nil,
            error=state.last_failure.error,
        } or nil,
        last_cleanup_error=state.last_cleanup_error,
        native_tracked=native ~= nil,
        native_outermost=native ~= nil and
            native.owner[NATIVE_METHOD] == native.active_trampoline,
        screen_hook_count=screen_count,
        inert_superseded_hook_count=inert_count,
    }
end

manager = process_state.manager or ContextMenuInputHookManager.new(process_state)
process_state.manager = manager
if publish_process_state then
    dfhack.dwarfuicore[STATE_SLOT] = process_state
end
