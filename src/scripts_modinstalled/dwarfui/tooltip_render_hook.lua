--@ module=true

-- Reload-safe render trampolines for presenting a tooltip after either the
-- native overlay pipeline or one selected Lua screen has finished rendering.

local API_VERSION = 1
local STATE_SLOT = 'tooltip_render_hook'
local OVERLAY_RENDER_METHOD = 'render_viewscreen_widgets'
local SCREEN_RENDER_METHOD = 'onRender'

---@enum dwarfui.TooltipRenderTransport
TooltipRenderTransport = {
    OVERLAY=1,
    SCREEN=2,
}

dfhack.dwarfui = dfhack.dwarfui or {}
local process_state = dfhack.dwarfui[STATE_SLOT]

if process_state and process_state.api_version ~= API_VERSION then
    error(('Conflicting DwarfUI tooltip render-hook versions: ' ..
        'process has %s, requested %s.'):format(
            tostring(process_state.api_version), tostring(API_VERSION)))
end
if not process_state then
    process_state = {
        api_version=API_VERSION,
        overlay_module=nil,
        overlay_hook=nil,
        screen_hooks=setmetatable({}, {__mode='k'}),
        presenter=nil,
        generation=0,
        render_count=0,
        last_rendered_revision=nil,
        last_transport=nil,
        last_error=nil,
        disabled_generation=nil,
        current_intent_revision=nil,
        failure_count=0,
        last_failure=nil,
        overlay_module_replacement_count=0,
        overlay_method_replacement_count=0,
        reorderable_wrappers=setmetatable({}, {__mode='k'}),
        selected_transport=nil,
        selected_owner=nil,
    }
    dfhack.dwarfui[STATE_SLOT] = process_state
end
process_state.failure_count = process_state.failure_count or 0
process_state.overlay_module_replacement_count =
    process_state.overlay_module_replacement_count or 0
process_state.overlay_method_replacement_count =
    process_state.overlay_method_replacement_count or 0
process_state.reorderable_wrappers =
    process_state.reorderable_wrappers or
        setmetatable({}, {__mode='k'})

---@class dwarfui.TooltipRenderHookRecord
---@field transport dwarfui.TooltipRenderTransport
---@field owner table|nil
---@field owner_ref table|nil weak-value reference for a screen owner
---@field active_trampoline function
---@field predecessor function
---@field predecessor_had_raw_method boolean|nil
---@field predecessor_raw_method function|nil
---@field owner_had_raw_method boolean|nil
---@field owner_raw_method function|nil
---@field generation integer
---@field repair_count integer
---@field chained boolean
---@field module_replaced boolean|nil
---@field method_replaced boolean
---@field method_replacement_count integer

---@class dwarfui.TooltipRenderHookState
---@field api_version integer
---@field overlay_module table|nil
---@field overlay_hook dwarfui.TooltipRenderHookRecord|nil
---@field screen_hooks table<table, dwarfui.TooltipRenderHookRecord>
---@field presenter function|nil
---@field generation integer
---@field render_count integer
---@field last_rendered_revision integer|nil
---@field last_transport dwarfui.TooltipRenderTransport|nil
---@field last_error string|nil
---@field disabled_generation integer|nil
---@field current_intent_revision integer|nil
---@field failure_count integer
---@field last_failure table|nil
---@field overlay_module_replacement_count integer
---@field overlay_method_replacement_count integer
---@field reorderable_wrappers table<function, boolean>
---@field selected_transport dwarfui.TooltipRenderTransport|nil
---@field selected_owner table|nil

---@class dwarfui.TooltipRenderHookDiagnostics
---@field api_version integer
---@field generation integer
---@field presenter_installed boolean
---@field disabled_generation integer|nil
---@field disabled boolean
---@field current_intent_revision integer|nil
---@field failure_count integer
---@field last_failure table|nil
---@field inactive_intent boolean
---@field selected_transport dwarfui.TooltipRenderTransport|nil
---@field selected_owner table|nil
---@field render_count integer
---@field last_rendered_revision integer|nil
---@field last_transport dwarfui.TooltipRenderTransport|nil
---@field last_error string|nil
---@field overlay table
---@field screens table[]
---@field selected_screen table|nil
---@field screen_hook_count integer

---@class dwarfui.TooltipRenderHookManager
---@field _state dwarfui.TooltipRenderHookState
TooltipRenderHookManager = {}
TooltipRenderHookManager.__index = TooltipRenderHookManager

---Returns the authoritative process slot instead of module-generation state.
---@return dwarfui.TooltipRenderHookState|nil
local function get_process_state()
    return dfhack.dwarfui and dfhack.dwarfui[STATE_SLOT] or nil
end

---Preserves every return value, including embedded and trailing nil values.
---@param packed table
---@return ...
local function unpack_returns(packed)
    return table.unpack(packed, 1, packed.n)
end

---Returns whether an upvalue graph retains the requested predecessor.
---The bounded traversal skips `_ENV` but follows functions and plain table
---records, which covers direct predecessor captures and wrapper records.
---@param value any
---@param predecessor function
---@param visited table<any, boolean>
---@param budget {remaining: integer}
---@return boolean
local function value_wraps(value, predecessor, visited, budget)
    if value == predecessor then return true end
    local value_type = type(value)
    if value_type ~= 'function' and value_type ~= 'table' then
        return false
    end
    if visited[value] or budget.remaining <= 0 then return false end
    visited[value] = true
    budget.remaining = budget.remaining - 1
    if value_type == 'function' then
        local index = 1
        while true do
            local name, upvalue = debug.getupvalue(value, index)
            if name == nil then return false end
            if name ~= '_ENV' and
                    value_wraps(
                        upvalue, predecessor, visited, budget) then
                return true
            end
            index = index + 1
        end
    end
    for key, field in next, value do
        if value_wraps(key, predecessor, visited, budget) or
                value_wraps(field, predecessor, visited, budget) then
            return true
        end
    end
    return false
end

---Returns whether a wrapper closure retains the requested predecessor.
---@param wrapper function
---@param predecessor function
---@return boolean
local function function_wraps(wrapper, predecessor)
    return value_wraps(
        wrapper, predecessor, {}, {remaining=256})
end

---Invokes the current presenter only for the selected active trampoline.
---@param state dwarfui.TooltipRenderHookState
---@param transport dwarfui.TooltipRenderTransport
---@param owner table
local function present(state, transport, owner)
    if state.selected_transport ~= transport or
            state.selected_owner ~= owner or
            state.disabled_generation == state.generation or
            type(state.presenter) ~= 'function' then
        return
    end
    local ok, rendered_revision = xpcall(
        function() return state.presenter(transport, owner) end,
        debug.traceback)
    if not ok then
        state.last_error = rendered_revision
        state.disabled_generation = state.generation
        state.failure_count = state.failure_count + 1
        local owner_ref = transport == TooltipRenderTransport.SCREEN and
            setmetatable({owner}, {__mode='v'}) or nil
        state.last_failure = {
            generation=state.generation,
            revision=state.current_intent_revision,
            transport=transport,
            owner=transport == TooltipRenderTransport.OVERLAY and
                owner or nil,
            owner_ref=owner_ref,
            error=rendered_revision,
        }
        if dfhack.printerr then
            pcall(dfhack.printerr,
                'DwarfUI tooltip presenter failed:\n' ..
                    tostring(rendered_revision))
        end
        return
    end
    if rendered_revision == nil then return end
    state.render_count = state.render_count + 1
    state.last_rendered_revision = rendered_revision
    state.last_transport = transport
end

---Builds a trampoline that always calls its predecessor before presentation.
---The callback re-reads process state and runs only while this exact function
---is the designated active trampoline for its transport owner.
---@param transport dwarfui.TooltipRenderTransport
---@param owner_or_ref table overlay owner or weak screen-owner reference
---@param predecessor function
---@return function
local function make_trampoline(transport, owner_or_ref, predecessor)
    local trampoline
    trampoline = function(...)
        local returns = table.pack(predecessor(...))
        local state = get_process_state()
        if state then
            local owner =
                transport == TooltipRenderTransport.SCREEN and
                owner_or_ref[1] or owner_or_ref
            if not owner then return unpack_returns(returns) end
            local record =
                transport == TooltipRenderTransport.OVERLAY and
                state.overlay_hook or state.screen_hooks[owner]
            if record and
                    (transport ~= TooltipRenderTransport.OVERLAY or
                        record.owner == owner) and
                    record.active_trampoline == trampoline then
                present(state, transport, owner)
            end
        end
        return unpack_returns(returns)
    end
    return trampoline
end

---Creates a manager facade over the process-owned hook state.
---@param state dwarfui.TooltipRenderHookState
---@return dwarfui.TooltipRenderHookManager
function TooltipRenderHookManager.new(state)
    assert(type(state) == 'table',
        'DwarfUI TooltipRenderHookManager requires process-owned state.')
    return setmetatable({_state=state}, TooltipRenderHookManager)
end

---Installs the presenter for this module generation.
---@param presenter function|nil
function TooltipRenderHookManager:set_presenter(presenter)
    assert(presenter == nil or type(presenter) == 'function',
        'DwarfUI tooltip presenter must be a function or nil.')
    local state = self._state
    if presenter ~= nil and
            (state.disabled_generation == state.generation or
                (state.presenter ~= nil and state.presenter ~= presenter)) then
        state.generation = state.generation + 1
        if state.overlay_hook then
            state.overlay_hook.generation = state.generation
        end
        for _, record in pairs(state.screen_hooks) do
            record.generation = state.generation
        end
    end
    state.presenter = presenter
    state.disabled_generation = nil
    state.last_error = nil
end

---Records the authoritative intent revision for failure diagnostics.
---@param revision integer|nil
function TooltipRenderHookManager:set_current_intent_revision(revision)
    assert(revision == nil or type(revision) == 'number',
        'DwarfUI tooltip intent revision must be a number or nil.')
    self._state.current_intent_revision = revision
end

---Allows one outer wrapper to be placed beneath a later DwarfUI trampoline.
---Wrapper owners must opt in because reordering changes the function identity
---in the exported slot and can invalidate exact-identity cleanup contracts.
---@param wrapper function
---@return boolean changed
function TooltipRenderHookManager:mark_wrapper_reorderable(wrapper)
    assert(type(wrapper) == 'function',
        'DwarfUI reorderable render wrapper must be a function.')
    local wrappers = self._state.reorderable_wrappers
    if wrappers[wrapper] then return false end
    wrappers[wrapper] = true
    return true
end

---Selects and idempotently repairs the exported native-overlay render seam.
---@return boolean changed
function TooltipRenderHookManager:ensure_overlay()
    local state = self._state
    local overlay = require('plugins.overlay')
    local current = overlay[OVERLAY_RENDER_METHOD]
    assert(type(current) == 'function',
        'plugins.overlay.render_viewscreen_widgets must be a function.')

    state.selected_transport = TooltipRenderTransport.OVERLAY
    state.selected_owner = overlay
    local previous = state.overlay_hook
    if state.overlay_module == overlay and previous and
            current == previous.active_trampoline then
        previous.generation = state.generation
        return false
    end
    if state.overlay_module == overlay and previous and
            function_wraps(current, previous.active_trampoline) and
            not state.reorderable_wrappers[current] then
        -- The other extension still owns the exported slot and DwarfUI is
        -- already in its predecessor chain. Replacing that wrapper would
        -- invalidate exact-identity cleanup contracts.
        previous.generation = state.generation
        return false
    end

    local module_replaced =
        state.overlay_module ~= nil and state.overlay_module ~= overlay
    local method_replaced =
        state.overlay_module == overlay and previous ~= nil and
            current ~= previous.active_trampoline
    if module_replaced then
        state.overlay_module_replacement_count =
            state.overlay_module_replacement_count + 1
    end
    if method_replaced then
        state.overlay_method_replacement_count =
            state.overlay_method_replacement_count + 1
    end
    local repair_count = previous and previous.repair_count + 1 or 0
    local trampoline = make_trampoline(
        TooltipRenderTransport.OVERLAY, overlay, current)
    local record = {
        transport=TooltipRenderTransport.OVERLAY,
        owner=overlay,
        active_trampoline=trampoline,
        predecessor=current,
        generation=state.generation,
        repair_count=repair_count,
        chained=true,
        module_replaced=module_replaced,
        method_replaced=method_replaced,
        method_replacement_count=
            state.overlay_method_replacement_count,
    }
    state.overlay_module = overlay
    state.overlay_hook = record
    overlay[OVERLAY_RENDER_METHOD] = trampoline
    return true
end

---Selects and idempotently repairs one Lua screen's effective render seam.
---@param owner table
---@return boolean changed
function TooltipRenderHookManager:ensure_screen(owner)
    assert(type(owner) == 'table',
        'DwarfUI tooltip screen-hook owner must be a table.')
    local current = owner[SCREEN_RENDER_METHOD]
    assert(type(current) == 'function',
        'DwarfUI tooltip screen owner onRender must be a function.')

    local state = self._state
    state.selected_transport = TooltipRenderTransport.SCREEN
    state.selected_owner = owner
    local previous = state.screen_hooks[owner]
    if previous and current == previous.active_trampoline then
        previous.generation = state.generation
        return false
    end
    if previous and function_wraps(
            current, previous.active_trampoline) and
            not state.reorderable_wrappers[current] then
        -- Preserve another owner's raw instance method while the active
        -- DwarfUI trampoline remains reachable through its wrapper.
        previous.generation = state.generation
        return false
    end

    local method_replaced =
        previous ~= nil and current ~= previous.active_trampoline
    local raw_method = rawget(owner, SCREEN_RENDER_METHOD)
    local had_raw_method = raw_method ~= nil
    local original_had_raw_method = had_raw_method
    local original_raw_method = raw_method
    if previous then
        original_had_raw_method = previous.owner_had_raw_method
        original_raw_method = previous.owner_raw_method
    end
    -- Neither the record nor its trampoline may strongly reference the weak
    -- key. Otherwise the process slot would keep dismissed screens alive.
    local owner_ref = setmetatable({owner}, {__mode='v'})
    local trampoline = make_trampoline(
        TooltipRenderTransport.SCREEN, owner_ref, current)
    local record = {
        transport=TooltipRenderTransport.SCREEN,
        owner_ref=owner_ref,
        active_trampoline=trampoline,
        predecessor=current,
        predecessor_had_raw_method=had_raw_method,
        predecessor_raw_method=raw_method,
        owner_had_raw_method=original_had_raw_method,
        owner_raw_method=original_raw_method,
        generation=state.generation,
        repair_count=previous and previous.repair_count + 1 or 0,
        chained=true,
        method_replaced=method_replaced,
        method_replacement_count=previous and
            (previous.method_replacement_count or 0) + 1 or 0,
    }
    state.screen_hooks[owner] = record
    rawset(owner, SCREEN_RENDER_METHOD, trampoline)
    return true
end

---Clears transport selection without removing installed inert trampolines.
function TooltipRenderHookManager:clear_selection()
    self._state.selected_transport = nil
    self._state.selected_owner = nil
end

---Retires presentation and conditionally restores owned outermost wrappers.
---A foreign outer wrapper is never overwritten.
---@return boolean changed
function TooltipRenderHookManager:shutdown()
    local state = self._state
    local changed = false
    state.presenter = nil
    state.selected_transport = nil
    state.selected_owner = nil
    state.disabled_generation = state.generation
    state.current_intent_revision = nil

    local overlay_record = state.overlay_hook
    if overlay_record and
            overlay_record.owner[OVERLAY_RENDER_METHOD] ==
                overlay_record.active_trampoline then
        overlay_record.owner[OVERLAY_RENDER_METHOD] =
            overlay_record.predecessor
        changed = true
    end
    state.overlay_module = nil
    state.overlay_hook = nil

    for owner, record in pairs(state.screen_hooks) do
        if rawget(owner, SCREEN_RENDER_METHOD) ==
                record.active_trampoline then
            if record.predecessor_had_raw_method then
                rawset(owner, SCREEN_RENDER_METHOD,
                    record.predecessor_raw_method)
            else
                rawset(owner, SCREEN_RENDER_METHOD, nil)
            end
            changed = true
        end
    end
    state.screen_hooks = setmetatable({}, {__mode='k'})
    return changed
end

---Returns a read-only snapshot of hook installation and chain diagnostics.
---@return dwarfui.TooltipRenderHookDiagnostics
function TooltipRenderHookManager:get_diagnostics()
    local state = self._state
    local overlay_record = state.overlay_hook
    local overlay_ok, current_overlay =
        pcall(require, 'plugins.overlay')
    if not overlay_ok then current_overlay = nil end
    local overlay_module_current = overlay_record ~= nil and
        current_overlay == overlay_record.owner
    local overlay_outermost = overlay_module_current and
        current_overlay[OVERLAY_RENDER_METHOD] ==
            overlay_record.active_trampoline
    local overlay_in_chain = overlay_module_current and
        type(current_overlay[OVERLAY_RENDER_METHOD]) == 'function' and
        function_wraps(current_overlay[OVERLAY_RENDER_METHOD],
            overlay_record.active_trampoline)
    local overlay_module_replacement_pending =
        overlay_record ~= nil and current_overlay ~= nil and
            not overlay_module_current
    local overlay_method_replacement_pending =
        overlay_module_current and
            (not overlay_in_chain or
                (not overlay_outermost and
                    state.reorderable_wrappers[
                        current_overlay[OVERLAY_RENDER_METHOD]] == true))
    local screen_count = 0
    local screens = {}
    local selected_screen
    for owner, record in pairs(state.screen_hooks) do
        screen_count = screen_count + 1
        local current_method = rawget(owner, SCREEN_RENDER_METHOD)
        local outermost = current_method ==
            record.active_trampoline
        local in_chain = type(current_method) == 'function' and
            function_wraps(current_method, record.active_trampoline)
        local method_replacement_pending = not in_chain or
            (not outermost and
                state.reorderable_wrappers[current_method] == true)
        local screen = {
            owner=owner,
            tracked=true,
            installed=in_chain,
            outermost=outermost,
            generation=record.generation,
            repair_count=record.repair_count,
            chained=in_chain and record.predecessor ~= nil,
            replaced_method=record.method_replaced or not outermost,
            method_replacement_pending=method_replacement_pending,
            method_replacement_count=
                record.method_replacement_count or 0,
            owner_had_raw_method=record.owner_had_raw_method,
            selected=
                state.selected_transport == TooltipRenderTransport.SCREEN and
                state.selected_owner == owner,
        }
        table.insert(screens, screen)
        if screen.selected then selected_screen = screen end
    end
    local failure = state.last_failure
    local failure_owner = failure and
        (failure.owner or
            (failure.owner_ref and failure.owner_ref[1])) or nil
    return {
        api_version=state.api_version,
        generation=state.generation,
        presenter_installed=type(state.presenter) == 'function',
        disabled_generation=state.disabled_generation,
        disabled=state.disabled_generation == state.generation,
        current_intent_revision=state.current_intent_revision,
        failure_count=state.failure_count,
        last_failure=failure and {
            generation=failure.generation,
            revision=failure.revision,
            transport=failure.transport,
            owner=failure_owner,
            error=failure.error,
        } or nil,
        inactive_intent=state.current_intent_revision == nil,
        selected_transport=state.selected_transport,
        selected_owner=state.selected_owner,
        render_count=state.render_count,
        last_rendered_revision=state.last_rendered_revision,
        last_transport=state.last_transport,
        last_error=state.last_error,
        overlay={
            owner=overlay_record and overlay_record.owner or nil,
            tracked=overlay_record ~= nil,
            installed=overlay_in_chain,
            outermost=overlay_outermost,
            generation=overlay_record and overlay_record.generation or nil,
            repair_count=overlay_record and
                overlay_record.repair_count or 0,
            chained=overlay_in_chain and
                overlay_record.predecessor ~= nil,
            replaced_module=overlay_record and
                (overlay_record.module_replaced or
                    overlay_module_replacement_pending) or false,
            module_replacement_pending=
                overlay_module_replacement_pending,
            module_replacement_count=
                state.overlay_module_replacement_count,
            replaced_method=overlay_record and
                (overlay_record.method_replaced or
                    not overlay_outermost) or false,
            method_replacement_pending=
                overlay_method_replacement_pending,
            method_replacement_count=
                state.overlay_method_replacement_count,
        },
        screens=screens,
        selected_screen=selected_screen,
        screen_hook_count=screen_count,
    }
end

-- Loading a same-version module generation retires stale presentation
-- closures while preserving installed trampolines and their predecessor
-- chains. The new generation can adopt them with an idempotent ensure call.
process_state.generation = process_state.generation + 1
process_state.presenter = nil
process_state.selected_transport = nil
process_state.selected_owner = nil
process_state.disabled_generation = nil
process_state.last_error = nil

manager = TooltipRenderHookManager.new(process_state)
