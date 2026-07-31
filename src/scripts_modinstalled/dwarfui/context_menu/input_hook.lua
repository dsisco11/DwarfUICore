--@ module=true

-- Reload-safe pre-delegation input trampolines for native and Lua screens.

local function_chain = reqscript('dwarfui/utils/function_chain')
local immutable_enum = reqscript('dwarfui/utils/immutable_enum')

local API_VERSION = 1
local STATE_SLOT = 'context_menu_input_hook'
local NATIVE_METHOD = 'feed_viewscreen_widgets'
local SCREEN_METHOD = 'onInput'

---@enum dwarfui.ContextMenuInputTransport
ContextMenuInputTransport = immutable_enum.define({
    NATIVE=1,
    SCREEN=2,
}, 'ContextMenuInputTransport')

dfhack.dwarfui = dfhack.dwarfui or {}
local process_state = dfhack.dwarfui[STATE_SLOT]
if process_state and process_state.api_version ~= API_VERSION then
    error(('Conflicting DwarfUI context-menu input-hook versions: ' ..
        'process has %s, requested %s.'):format(
            tostring(process_state.api_version), tostring(API_VERSION)))
end
local previous_generation = process_state and process_state.generation or 0
local retired_hooks = {}
if process_state and process_state.manager and
        type(process_state.manager.shutdown) == 'function' then
    pcall(process_state.manager.shutdown, process_state.manager)
    for _, record in ipairs(process_state.retired_hooks or {}) do
        if record.foreign_outer_wrapper then
            table.insert(retired_hooks, record)
        end
    end
end
process_state = {
    api_version=API_VERSION,
    generation=previous_generation + 1,
    handler=nil,
    failure_handler=nil,
    native_module=nil,
    native_hook=nil,
    screen_hooks=setmetatable({}, {__mode='k'}),
    retired_hooks=retired_hooks,
    dispatch_count=0,
    handled_count=0,
    delegated_count=0,
    failure_count=0,
    last_error=nil,
    last_failure=nil,
    disabled_generation=nil,
}
dfhack.dwarfui[STATE_SLOT] = process_state

---@class dwarfui.ContextMenuInputHookRecord
---@field transport dwarfui.ContextMenuInputTransport
---@field owner table|nil
---@field owner_ref table|nil
---@field active_trampoline function
---@field predecessor function
---@field predecessor_had_raw_method boolean|nil
---@field predecessor_raw_method function|nil
---@field generation integer
---@field active boolean
---@field foreign_outer_wrapper boolean

---@class dwarfui.ContextMenuInputHookState
---@field api_version integer
---@field generation integer
---@field handler function|nil
---@field failure_handler function|nil
---@field native_module table|nil
---@field native_hook dwarfui.ContextMenuInputHookRecord|nil
---@field screen_hooks table<table, dwarfui.ContextMenuInputHookRecord>
---@field retired_hooks dwarfui.ContextMenuInputHookRecord[]
---@field dispatch_count integer
---@field handled_count integer
---@field delegated_count integer
---@field failure_count integer
---@field last_error string|nil
---@field last_failure table|nil
---@field disabled_generation integer|nil
---@field manager? dwarfui.ContextMenuInputHookManager

---@class dwarfui.ContextMenuInputHookManager
---@field _state dwarfui.ContextMenuInputHookState
ContextMenuInputHookManager = {}
ContextMenuInputHookManager.__index = ContextMenuInputHookManager

---Returns the authoritative process state for trampoline adoption.
---@return dwarfui.ContextMenuInputHookState|nil
local function get_process_state()
    return dfhack.dwarfui and dfhack.dwarfui[STATE_SLOT] or nil
end

---Preserves every predecessor return, including trailing nil values.
---@param packed table
---@return ...
local function unpack_returns(packed)
    return table.unpack(packed, 1, packed.n)
end

---Records one unexpected trampoline failure before delegating unchanged.
---@param state dwarfui.ContextMenuInputHookState
---@param transport dwarfui.ContextMenuInputTransport
---@param owner table
---@param failure any
local function fail_dispatch(state, transport, owner, failure)
    local rendered = tostring(failure)
    state.failure_count = state.failure_count + 1
    state.last_error = rendered
    state.last_failure = {
        generation=state.generation,
        transport=transport,
        owner=transport == ContextMenuInputTransport.NATIVE and owner or nil,
        owner_ref=transport == ContextMenuInputTransport.SCREEN and
            setmetatable({owner}, {__mode='v'}) or nil,
        error=rendered,
    }
    state.disabled_generation = state.generation
    local callback = state.failure_handler
    state.handler = nil
    if dfhack.printerr then
        pcall(dfhack.printerr,
            'DwarfUI context-menu input hook failed:\n' .. rendered)
    end
    if callback then
        pcall(callback, rendered)
    end
end

---Runs the current opening handler behind the hook's traceback boundary.
---@param transport dwarfui.ContextMenuInputTransport
---@param owner table
---@param keys table
---@return boolean handled
local function dispatch(transport, owner, keys)
    local state = get_process_state()
    if not state or
            state.disabled_generation == state.generation or
            type(state.handler) ~= 'function' then
        return false
    end
    state.dispatch_count = state.dispatch_count + 1
    local ok, handled = xpcall(function()
        return not not state.handler(keys, transport, owner)
    end, debug.traceback)
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
    trampoline = function(keys, ...)
        local state = get_process_state()
        local record = state and state.native_hook
        if record and record.active and
                record.active_trampoline == trampoline and
                dispatch(ContextMenuInputTransport.NATIVE, owner, keys) then
            return true
        end
        return unpack_returns(table.pack(predecessor(keys, ...)))
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
---@param state dwarfui.ContextMenuInputHookState
---@return dwarfui.ContextMenuInputHookManager
function ContextMenuInputHookManager.new(state)
    assert(type(state) == 'table' and state.api_version == API_VERSION,
        'DwarfUI context-menu input-hook state has an incompatible version.')
    return setmetatable({_state=state}, ContextMenuInputHookManager)
end

---Installs the sole opening handler for this hook generation.
---@param handler function|nil
function ContextMenuInputHookManager:set_handler(handler)
    assert(handler == nil or type(handler) == 'function',
        'DwarfUI context-menu input handler must be a function.')
    self._state.handler = handler
end

---Installs the protected service failure observer.
---@param handler fun(message: string)|nil
function ContextMenuInputHookManager:set_failure_handler(handler)
    assert(handler == nil or type(handler) == 'function',
        'DwarfUI context-menu hook failure handler must be a function.')
    self._state.failure_handler = handler
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
        'DwarfUI context-menu screen-hook owner must be a table.')
    local current = owner[SCREEN_METHOD]
    assert(type(current) == 'function',
        'DwarfUI context-menu screen owner onInput must be a function.')
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
---@param record dwarfui.ContextMenuInputHookRecord
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

---Reconciles native and Lua hooks with structurally attached registration roots.
---@param roots table<any, boolean>
---@return boolean changed
function ContextMenuInputHookManager:reconcile_roots(roots)
    assert(type(roots) == 'table',
        'DwarfUI context-menu hook reconciliation requires a root set.')
    local state = self._state
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
    state.handler = nil
    state.failure_handler = nil
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
        handler_installed=type(state.handler) == 'function',
        disabled=state.disabled_generation == state.generation,
        disabled_generation=state.disabled_generation,
        dispatch_count=state.dispatch_count,
        handled_count=state.handled_count,
        delegated_count=state.delegated_count,
        failure_count=state.failure_count,
        last_error=state.last_error,
        last_failure=state.last_failure and {
            generation=state.last_failure.generation,
            transport=state.last_failure.transport,
            owner=state.last_failure.owner or
                (state.last_failure.owner_ref and
                    state.last_failure.owner_ref[1]) or nil,
            error=state.last_failure.error,
        } or nil,
        native_tracked=native ~= nil,
        native_outermost=native ~= nil and
            native.owner[NATIVE_METHOD] == native.active_trampoline,
        screen_hook_count=screen_count,
        inert_superseded_hook_count=inert_count,
    }
end

manager = ContextMenuInputHookManager.new(process_state)
process_state.manager = manager
