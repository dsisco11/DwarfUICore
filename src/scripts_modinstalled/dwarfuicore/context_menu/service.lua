--@ module=true

-- Process-wide context-menu session authority and opening-input mediation.

local input_hooks = reqscript('dwarfuicore/context_menu/input_hook')
local input_samples = reqscript('dwarfuicore/context_menu/input_sample')
local registrations = reqscript('dwarfuicore/context_menu/registration')
local target_detectors = reqscript('dwarfuicore/context_menu/target_detector')
local targets = reqscript('dwarfuicore/context_menu/target')
local numbers = reqscript('dwarfuicore/utils/numbers')

local DetectionKind = target_detectors.ContextMenuDetectionKind
local TargetKind = targets.ContextMenuTargetKind

local API_VERSION = 1
local SERVICE_SLOT = 'context_menu_service'
local STATE_CHANGE_SLOT = 'dwarfuicore_context_menu'

dfhack.dwarfuicore = dfhack.dwarfuicore or {}

---@class dwarfuicore.ContextMenuPresentationController
---@field show fun(self: dwarfuicore.ContextMenuPresentationController)
---@field close fun(self: dwarfuicore.ContextMenuPresentationController)

---@class dwarfuicore.ContextMenuPresentationActions
---@field close fun(): boolean
---@field select fun(entry_index: integer): boolean
---@field session_is_valid fun(): boolean
---@field fail fun(stage: string, failure: any)

---Creates a hidden controller; visible side effects begin only in `show()`.
---@alias dwarfuicore.ContextMenuPresentationFactory fun(session: dwarfuicore.ContextMenuOpenSession, actions: dwarfuicore.ContextMenuPresentationActions): dwarfuicore.ContextMenuPresentationController

---@class dwarfuicore.ContextMenuServiceOptions
---@field registrations dwarfuicore.ContextMenuRegistrationManager
---@field detector dwarfuicore.ContextMenuTargetDetector
---@field sampler dwarfuicore.ContextMenuInputSampler
---@field input_hook dwarfuicore.ContextMenuInputHookManager
---@field presentation_factory dwarfuicore.ContextMenuPresentationFactory
---@field printer? fun(message: string)

---@class dwarfuicore.ContextMenuServiceState
---@field api_version integer
---@field generation integer
---@field runtime_generation integer
---@field session dwarfuicore.ContextMenuOpenSession|nil
---@field presentation dwarfuicore.ContextMenuPresentationController|nil
---@field disabled_generation integer|nil
---@field last_error string|nil
---@field last_failure table|nil
---@field failure_count integer
---@field last_handler_error string|nil
---@field last_invalid_reason string|nil
---@field last_close_reason string|nil
---@field handler_failure_count integer
---@field open_count integer
---@field close_count integer
---@field selection_count integer
---@field service? dwarfuicore.ContextMenuService

---@class dwarfuicore.ContextMenuService
---@field _state dwarfuicore.ContextMenuServiceState
---@field _registrations dwarfuicore.ContextMenuRegistrationManager
---@field _detector dwarfuicore.ContextMenuTargetDetector
---@field _sampler dwarfuicore.ContextMenuInputSampler
---@field _input_hook dwarfuicore.ContextMenuInputHookManager
---@field _presentation_factory dwarfuicore.ContextMenuPresentationFactory
---@field _printer fun(message: string)
---@field _started boolean
---@field _state_change_callback? function
ContextMenuService = {}
ContextMenuService.__index = ContextMenuService

---Prints a contained service or consumer-handler failure.
---@param message string
local function default_printer(message)
    if dfhack.printerr then
        dfhack.printerr(message)
    else
        print(message)
    end
end

---Creates a fresh service state for the active runtime generation.
---@param generation integer
---@param runtime_generation integer
---@return dwarfuicore.ContextMenuServiceState
local function new_state(generation, runtime_generation)
    return {
        api_version=API_VERSION,
        generation=generation,
        runtime_generation=runtime_generation,
        session=nil,
        presentation=nil,
        disabled_generation=nil,
        last_error=nil,
        last_failure=nil,
        failure_count=0,
        last_handler_error=nil,
        last_invalid_reason=nil,
        last_close_reason=nil,
        handler_failure_count=0,
        open_count=0,
        close_count=0,
        selection_count=0,
    }
end

---Creates one process-wide session authority from explicit collaborators.
---@param state dwarfuicore.ContextMenuServiceState
---@param options dwarfuicore.ContextMenuServiceOptions
---@return dwarfuicore.ContextMenuService
function ContextMenuService.new(state, options)
    assert(type(state) == 'table',
        'DwarfUICore context-menu service requires process state.')
    assert(type(options) == 'table',
        'DwarfUICore context-menu service requires options.')
    for _, name in ipairs{
            'registrations', 'detector', 'sampler', 'input_hook',
            'presentation_factory',
        } do
        assert(options[name] ~= nil,
            'DwarfUICore context-menu service requires ' .. name .. '.')
    end
    assert(type(options.presentation_factory) == 'function',
        'DwarfUICore context-menu presentation factory must be a function.')
    assert(options.printer == nil or type(options.printer) == 'function',
        'DwarfUICore context-menu service printer must be a function.')
    return setmetatable({
        _state=state,
        _registrations=options.registrations,
        _detector=options.detector,
        _sampler=options.sampler,
        _input_hook=options.input_hook,
        _presentation_factory=options.presentation_factory,
        _printer=options.printer or default_printer,
        _started=false,
    }, ContextMenuService)
end

---Returns whether one menu session is currently authoritative.
---@return boolean
function ContextMenuService:is_open()
    return self._state.session ~= nil
end

---Returns whether an internal failure disabled this service generation.
---@return boolean
function ContextMenuService:is_disabled()
    return self._state.disabled_generation == self._state.generation
end

---Installs the concrete factory before production opening is started.
---@param factory dwarfuicore.ContextMenuPresentationFactory
function ContextMenuService:set_presentation_factory(factory)
    assert(type(factory) == 'function',
        'DwarfUICore context-menu presentation factory must be a function.')
    assert(not self._started and not self:is_open(),
        'DwarfUICore context-menu presentation cannot change while active.')
    self._presentation_factory = factory
end

---Closes authoritative state before invoking presentation cleanup.
---@return boolean changed
function ContextMenuService:_close_unprotected(reason)
    local state = self._state
    local session = state.session
    local presentation = state.presentation
    if not session and not presentation then return false end
    state.session = nil
    state.presentation = nil
    state.last_close_reason = reason
    local failures = {}
    if presentation then
        local ok, failure = xpcall(function()
            presentation:close()
        end, debug.traceback)
        if not ok then table.insert(failures, tostring(failure)) end
    end
    if session then
        state.last_invalid_reason = session.get_invalid_reason and
            session:get_invalid_reason() or nil
        local ok, failure = xpcall(function()
            session:close()
        end, debug.traceback)
        if not ok then table.insert(failures, tostring(failure)) end
    end
    state.close_count = state.close_count + 1
    if #failures > 0 then error(table.concat(failures, '\n')) end
    return true
end

---Disables the complete generation after one contained internal failure.
---@param stage string
---@param failure any
---@param report boolean
function ContextMenuService:_disable(stage, failure, report)
    local state = self._state
    local message = tostring(failure)
    if not self:is_disabled() then
        state.failure_count = state.failure_count + 1
        state.last_error = message
        state.last_failure = {
            generation=state.generation,
            stage=stage,
            error=message,
        }
    end
    state.disabled_generation = state.generation
    local close_ok, close_failure =
        xpcall(function() self:_close_unprotected() end, debug.traceback)
    if not close_ok then
        message = message .. '\nCleanup failure:\n' ..
            tostring(close_failure)
        state.last_error = message
        state.last_failure.error = message
    end
    local registrations_ok, registrations_failure =
        pcall(self._registrations.disable, self._registrations, message)
    if not registrations_ok then
        message = message .. '\nRegistration shutdown failure:\n' ..
            tostring(registrations_failure)
    end
    local hook_ok, hook_failure =
        pcall(self._input_hook.shutdown, self._input_hook)
    if not hook_ok then
        message = message .. '\nInput-hook shutdown failure:\n' ..
            tostring(hook_failure)
    end
    state.last_error = message
    state.last_failure.error = message
    if report then
        self._printer(('DwarfUICore context-menu %s failed:\n%s'):format(
            stage, message))
    end
end

---Builds and presents one session after its target was validated.
---@param detection dwarfuicore.ContextMenuTargetDetection
---@return boolean opened
function ContextMenuService:_open_unprotected(detection)
    local state = self._state
    if self:is_disabled() or state.session ~= nil then return false end
    local candidate = detection.candidate
    local contributions = {}
    for index, value in ipairs(detection.candidates or {candidate}) do
        contributions[index] = {
            identity=value.identity,
            definition=value:get_definition_snapshot(),
            source=value.source,
            owner=detection.target.kind == TargetKind.MAP_TILE and
                value.owner or nil,
        }
    end
    local session = targets.ContextMenuOpenSession.new{
        definition=candidate:get_definition_snapshot(),
        target=detection.target,
        anchor=detection.anchor,
        source=candidate.source,
        source_root=detection.root,
        owner=detection.target.kind == TargetKind.MAP_TILE and
            candidate.owner or nil,
        contributions=contributions,
    }
    state.session = session
    local function session_is_valid()
        if session.is_valid and not session:is_valid() then
            self:close()
            return false
        end
        local target = session:get_target_descriptor()
        if target.kind == TargetKind.WIDGET then return true end
        if self._registrations.validate_open_session then
            if self._registrations:validate_open_session(session) then return true end
            self:close()
            return false
        end
        local root = session:get_source_root()
        local anchor = session:get_anchor_descriptor()
        local current = root and self._registrations:resolve_open_map_identity(
            target.registration_identity, root)
        local pos = current and current.pos
        local expected = anchor.map_position
        return pos ~= nil and expected ~= nil and pos.x == expected.x and
            pos.y == expected.y and pos.z == expected.z
    end
    local actions = {
        close=function(reason) return self:close(reason) end,
        select=function(entry_index) return self:select(entry_index) end,
        session_is_valid=session_is_valid,
        map_session_is_valid=session_is_valid,
        fail=function(stage, failure)
            self:_disable(stage, failure, true)
        end,
    }
    local presentation = self._presentation_factory(session, actions)
    assert(type(presentation) == 'table' and
            type(presentation.show) == 'function' and
            type(presentation.close) == 'function',
        'DwarfUICore context-menu presentation must provide show() and close().')
    state.presentation = presentation
    presentation:show()
    state.open_count = state.open_count + 1
    return true
end

---Opens one target atomically through the sole service transition.
---@param detection dwarfuicore.ContextMenuTargetDetection
---@return boolean opened
function ContextMenuService:open(detection)
    assert(type(detection) == 'table' and
            detection.kind == DetectionKind.TARGET and
            detection.candidate ~= nil and detection.target ~= nil and
            detection.anchor ~= nil and detection.root ~= nil,
        'DwarfUICore context-menu opening requires a target detection.')
    local ok, opened = xpcall(function()
        return self:_open_unprotected(detection)
    end, debug.traceback)
    if not ok then
        self:_disable('presentation', opened, true)
        return false
    end
    return opened
end

---Closes the active session through the sole service transition.
---@return boolean changed
function ContextMenuService:close(reason)
    if self:is_disabled() then return false end
    local ok, changed = xpcall(function()
        return self:_close_unprotected(reason)
    end, debug.traceback)
    if not ok then
        self:_disable('close transition', changed, true)
        return false
    end
    return changed
end

---Closes before invoking one entry handler through a protected boundary.
---@param entry_index integer
---@return boolean invoked
function ContextMenuService:select(entry_index)
    local state = self._state
    if self:is_disabled() or not state.session then return false end
    local session = state.session
    local definition = session:get_definition_snapshot()
    assert(numbers.is_integer(entry_index) and
            definition.entries[entry_index] ~= nil,
        'DwarfUICore context-menu selection requires a valid entry index.')
    if self._registrations.validate_open_session and
            not self._registrations:validate_open_session(session) then
        self:close()
        return false
    end
    local context = session:create_selection_context(entry_index)
    if not context then
        self:close()
        return false
    end
    local handler = definition.entries[entry_index].on_select
    if not self:close() then return false end
    state.selection_count = state.selection_count + 1
    local ok, failure = xpcall(function()
        handler(context)
    end, debug.traceback)
    if not ok then
        state.handler_failure_count = state.handler_failure_count + 1
        state.last_handler_error = tostring(failure)
        self._printer('DwarfUICore context-menu on_select failed:\n' ..
            tostring(failure))
    end
    return true
end

---Processes only actionable opening input from an installed trampoline.
---@param keys table
---@param transport dwarfuicore.ContextMenuInputTransport
---@param owner table
---@return boolean handled
function ContextMenuService:handle_opening_input(keys, transport, owner)
    if self:is_disabled() or self._state.session or
            type(keys) ~= 'table' or not keys._MOUSE_R then
        return false
    end

    local detection
    local resolved, failure = xpcall(function()
        local sample = self._sampler:capture()
        detection = self._detector:detect(sample)
        assert(type(detection) == 'table' and
                (detection.kind == DetectionKind.TARGET or
                    detection.kind == DetectionKind.BLOCKED or
                    detection.kind == DetectionKind.MISS),
            'DwarfUICore context-menu detector returned an invalid result.')
    end, debug.traceback)
    if not resolved then
        self:_disable('opening resolution', failure, true)
        return false
    end
    if detection.kind ~= DetectionKind.TARGET then return false end

    local opened = self:open(detection)
    if self:is_disabled() then return true end
    return opened
end

---Closes the menu and clears all registrations after a world unload.
---@return boolean changed
function ContextMenuService:clear_world_state()
    local changed = self:close()
    local ok, cleared = xpcall(function()
        return self._registrations:clear()
    end, debug.traceback)
    if not ok then
        self:_disable('world unload cleanup', cleared, true)
        return changed
    end
    return cleared or changed
end

---Installs one owned world-unload cleanup callback when DFHack exposes the seam.
function ContextMenuService:_install_state_change_callback()
    if dfhack.onStateChange == nil then return end
    local callback = function(code)
        if code == SC_WORLD_UNLOADED then self:clear_world_state() end
    end
    self._state_change_callback = callback
    dfhack.onStateChange[STATE_CHANGE_SLOT] = callback
end

---Removes only the state-change callback still owned by this service.
function ContextMenuService:_remove_state_change_callback()
    if dfhack.onStateChange ~= nil and
            dfhack.onStateChange[STATE_CHANGE_SLOT] ==
                self._state_change_callback then
        dfhack.onStateChange[STATE_CHANGE_SLOT] = nil
    end
    self._state_change_callback = nil
end

---Starts root discovery integration and installs the opening callback.
---@return boolean started
function ContextMenuService:start()
    if self._started then return false end
    self._started = true
    self._input_hook:set_context_consumer(
        function(keys, transport, owner)
            return self:handle_opening_input(keys, transport, owner)
        end,
        function(message)
            self:_disable('input hook', message, false)
        end)
    self._registrations:set_failure_observer(function(message)
        self:_disable('root discovery', message, false)
    end)
    if self._registrations.set_removal_observer then
        self._registrations:set_removal_observer(function(identity)
            local session = self._state.session
            if session and session:contains_identity(identity) then self:close() end
        end)
    end
    self._registrations:set_menu_open_predicate(function()
        return self:is_open()
    end)
    self:_install_state_change_callback()
    -- Installing the root observer can immediately replay a discovered set,
    -- so every failure boundary must already be active before this call.
    self._registrations:set_root_observer(function(roots)
        self._input_hook:reconcile_roots(roots)
    end)
    return true
end

---Destructively retires presentation, registrations, discovery, and hooks.
---@return boolean changed
function ContextMenuService:shutdown()
    local changed = false
    local ok, closed = xpcall(function()
        return self:_close_unprotected()
    end, debug.traceback)
    changed = (ok and closed) or changed
    self._registrations:set_root_observer(nil)
    self._registrations:set_failure_observer(nil)
    if self._registrations.set_removal_observer then
        self._registrations:set_removal_observer(nil)
    end
    self._registrations:set_menu_open_predicate(function() return false end)
    changed = self._registrations:shutdown() or changed
    changed = self._input_hook:shutdown() or changed
    self:_remove_state_change_callback()
    self._started = false
    return changed
end

---Returns session, failure, transition, hook, and registration diagnostics.
---@return table
function ContextMenuService:get_diagnostics()
    local state = self._state
    return {
        api_version=state.api_version,
        generation=state.generation,
        started=self._started,
        open=state.session ~= nil,
        disabled=self:is_disabled(),
        disabled_generation=state.disabled_generation,
        last_error=state.last_error,
        last_failure=state.last_failure,
        failure_count=state.failure_count,
        last_handler_error=state.last_handler_error,
        last_invalid_reason=state.last_invalid_reason,
        last_close_reason=state.last_close_reason,
        handler_failure_count=state.handler_failure_count,
        open_count=state.open_count,
        close_count=state.close_count,
        selection_count=state.selection_count,
        hook=self._input_hook:get_diagnostics(),
        registrations=self._registrations:get_diagnostics(),
    }
end

local previous = dfhack.dwarfuicore[SERVICE_SLOT]
local runtime_state = dfhack.dwarfuicore.service_provider_runtime
local runtime_generation = runtime_state and runtime_state.generation or 0
if previous and previous.api_version ~= API_VERSION then
    error(('Conflicting DwarfUICore context-menu service versions: process ' ..
        'has %s, requested %s.'):format(tostring(previous.api_version),
            tostring(API_VERSION)))
end
if previous and runtime_generation > 0 then
    assert(previous.runtime_generation == runtime_generation,
        'DwarfUICore context-menu service belongs to another runtime generation.')
end

---Fails explicitly if invoked before the concrete screen factory is installed.
---@return dwarfuicore.ContextMenuPresentationController
local function unavailable_presentation_factory()
    error('DwarfUICore context-menu presentation is not installed.')
end

if previous then
    assert(type(previous.service) == 'table',
        'DwarfUICore context-menu service state is incomplete.')
    service = previous.service
else
    local state = new_state(1, runtime_generation)
    local registration_manager = registrations.manager
    local input_hook_manager = input_hooks.manager
    local sampler = input_samples.ContextMenuInputSampler.new{
        has_map_demand=function()
            return registration_manager:map_registration_count() > 0
        end,
    }
    local detector = target_detectors.ContextMenuTargetDetector.new{
        registrations=registration_manager,
    }
    local constructed_service = ContextMenuService.new(state, {
        registrations=registration_manager,
        detector=detector,
        sampler=sampler,
        input_hook=input_hook_manager,
        presentation_factory=unavailable_presentation_factory,
    })
    state.service = constructed_service
    dfhack.dwarfuicore[SERVICE_SLOT] = state
    service = constructed_service
end
