--@ module=true

-- Process-wide tooltip semantics. The exported service object owns
-- registrations, pointer transitions, and immutable presentation intent, but
-- has no presentation implementation or UI-host dependency.

local target_adapters = reqscript('dwarfuicore/tooltip/target')
local identities = reqscript('dwarfuicore/service_provider/identity')
local ObservationKind = target_adapters.TooltipPointerObservationKind

API_VERSION = 2
local SERVICE_SLOT = 'tooltip_service'

dfhack.dwarfuicore = dfhack.dwarfuicore or {}
local process_state = dfhack.dwarfuicore[SERVICE_SLOT]
local publish_process_state = false
local runtime_state = dfhack.dwarfuicore.service_provider_runtime
local runtime_generation = runtime_state and runtime_state.generation or 0

if process_state and process_state.api_version ~= API_VERSION then
    error(('Conflicting DwarfUICore tooltip service versions: process has ' ..
        '%s, requested %s.'):format(tostring(process_state.api_version),
            tostring(API_VERSION)))
end
if not process_state then
    process_state = {
        api_version=API_VERSION,
        registrations=setmetatable({}, {__mode='k'}),
        registration_sequence=0,
        target=nil,
        target_adapter=nil,
        intent=nil,
        revision=0,
        last_sequence=0,
        intent_observer=nil,
        generation=1,
        runtime_generation=runtime_generation,
    }
    publish_process_state = true
elseif runtime_generation > 0 then
    assert(process_state.runtime_generation == runtime_generation,
        'DwarfUICore tooltip service belongs to another runtime generation.')
end

---@class dwarfuicore.TooltipIntent
---@field revision integer
---@field source_sequence integer
---@field text string
---@field anchor_x integer
---@field anchor_y integer
---@field coordinate_space '"screen-cells"'
---@field source_root gui.View
---@field source_identity table

---Receives each changed immutable intent, or nil when intent is cleared.
---@alias dwarfuicore.TooltipIntentObserver fun(intent: dwarfuicore.TooltipIntent|nil, revision: integer)

---@class dwarfuicore.TooltipServiceState
---@field api_version integer
---@field registrations table<gui.View, table>
---@field registration_sequence integer
---@field target any|nil
---@field target_adapter dwarfuicore.TooltipTargetAdapter|nil
---@field intent dwarfuicore.TooltipIntent|nil
---@field revision integer
---@field last_sequence integer
---@field intent_observer dwarfuicore.TooltipIntentObserver|nil
---@field generation integer
---@field runtime_generation integer
---@field service? dwarfuicore.TooltipService

---@class dwarfuicore.TooltipService
---@field _state dwarfuicore.TooltipServiceState
TooltipService = {}
TooltipService.__index = TooltipService

---Creates a service object over process-owned reload-safe state.
---@param state dwarfuicore.TooltipServiceState
---@return dwarfuicore.TooltipService
function TooltipService.new(state)
    assert(type(state) == 'table',
        'DwarfUICore TooltipService requires process-owned state.')
    return setmetatable({_state=state}, TooltipService)
end

---Returns validated tooltip text after pointer callbacks have run.
---@param target dwarfuicore.TooltipTargetAdapter|nil
---@return string|nil
local function get_tooltip(target)
    if not target then return nil end
    local value = target:get_tooltip()
    if value == nil or value == '' then return nil end
    assert(type(value) == 'string',
        'DwarfUICore tooltip must be a string, nil, or an empty string; got ' ..
        type(value) .. '.')
    return value
end

---Creates an immutable copy of a composite identity for published intent.
---@param value any
---@return any
local function snapshot_identity(value)
    local copied
    local recognized = pcall(function()
        copied = identities.CompositeIdentity.new(value)
    end)
    if not recognized then return value end
    return setmetatable({}, {
        __index=copied,
        __newindex=function()
            error('DwarfUICore tooltip source identities are immutable.', 2)
        end,
        __pairs=function()
            return next, copied, nil
        end,
        __metatable=false,
    })
end

---Returns whether two opaque or composite target identities are equivalent.
---@param left any
---@param right any
---@return boolean
local function identities_equal(left, right)
    if left == right then return true end
    return identities.CompositeIdentity.equals(left, right)
end

---Creates one immutable tooltip-intent snapshot.
---@param observation dwarfuicore.TooltipPointerObservation
---@param text string
---@param revision integer
---@return dwarfuicore.TooltipIntent
local function make_intent(observation, text, revision)
    local values = {
        revision=revision,
        source_sequence=observation.sequence,
        text=text,
        anchor_x=observation.pointer_x,
        anchor_y=observation.pointer_y,
        coordinate_space='screen-cells',
        source_root=observation.root,
        source_identity=snapshot_identity(observation.identity),
    }
    return setmetatable({}, {
        __index=values,
        __newindex=function()
            error('DwarfUICore tooltip intents are immutable.', 2)
        end,
        __pairs=function()
            return next, values, nil
        end,
        __metatable=false,
    })
end

---Notifies this service's optional presentation-neutral intent observer.
---@param intent dwarfuicore.TooltipIntent|nil
function TooltipService:_notify_intent_observer(intent)
    local state = self._state
    if state.intent_observer then
        state.intent_observer(intent, state.revision)
    end
end

---Clears this service's published intent exactly once.
---@return boolean changed
function TooltipService:_clear_intent()
    local state = self._state
    if state.intent == nil then return false end
    state.revision = state.revision + 1
    state.intent = nil
    self:_notify_intent_observer(nil)
    return true
end

---Publishes one immutable intent snapshot from this service.
---@param observation dwarfuicore.TooltipPointerObservation
---@param text string
function TooltipService:_publish_intent(observation, text)
    local state = self._state
    state.revision = state.revision + 1
    state.intent = make_intent(observation, text, state.revision)
    self:_notify_intent_observer(state.intent)
end

---Clears this service's current target and any published intent.
---@return boolean changed
function TooltipService:_clear_target()
    local state = self._state
    local previous = state.target_adapter
    if previous then previous:on_pointer_leave() end
    state.target = nil
    state.target_adapter = nil
    local intent_changed = self:_clear_intent()
    return previous ~= nil or intent_changed
end

---Counts this service's live weak registrations without retaining widgets.
---@return integer
function TooltipService:registration_count()
    local count = 0
    for _ in pairs(self._state.registrations) do count = count + 1 end
    return count
end

---Returns this service's weak registration set for target detection.
---@return table<gui.View, table>
function TooltipService:get_registrations()
    return self._state.registrations
end

---Returns the authoritative immutable presentation intent, if any.
---@return dwarfuicore.TooltipIntent|nil
function TooltipService:get_intent()
    return self._state.intent
end

---Registers one tooltip target with deterministic cross-root sequence.
---@param widget gui.View
---@param target_sequence? integer
---@return boolean created
function TooltipService:register(widget, target_sequence)
    assert(type(widget) == 'table',
        'DwarfUICore tooltip registration requires a widget table.')
    local state = self._state
    if state.registrations[widget] then return false end
    if target_sequence == nil then
        state.registration_sequence = state.registration_sequence + 1
        target_sequence = state.registration_sequence
    else
        assert(math.type(target_sequence) == 'integer' and target_sequence > 0,
            'DwarfUICore tooltip target sequence must be a positive integer.')
        state.registration_sequence = math.max(
            state.registration_sequence, target_sequence)
    end
    state.registrations[widget] = {
        sequence=target_sequence,
    }
    return true
end

---Removes one registration and immediately releases active target state.
---@param widget gui.View
---@return boolean removed
function TooltipService:unregister(widget)
    local state = self._state
    if not state.registrations[widget] then return false end
    state.registrations[widget] = nil
    if state.target == widget then self:_clear_target() end
    return true
end

---Immediately releases an active target identity from any hit domain.
---@param identity any
---@return boolean changed
function TooltipService:release_target(identity)
    if not identities_equal(self._state.target, identity) then return false end
    return self:_clear_target()
end

---Replaces or removes this service's presentation-neutral intent observer.
---Replacement never replays intent or synthesizes pointer callbacks.
---@param observer dwarfuicore.TooltipIntentObserver|nil
function TooltipService:set_intent_observer(observer)
    assert(observer == nil or type(observer) == 'function',
        'DwarfUICore tooltip intent observer must be a function or nil.')
    self._state.intent_observer = observer
end

---Accepts one ordered detector observation and mediates tooltip semantics.
---@param observation dwarfuicore.TooltipPointerObservation
---@return boolean accepted
function TooltipService:accept_pointer_observation(observation)
    assert(type(observation) == 'table',
        'DwarfUICore tooltip service requires a pointer observation.')
    assert(type(observation.sequence) == 'number',
        'DwarfUICore tooltip observation sequence must be a number.')
    assert(observation.kind == ObservationKind.TARGET or
        observation.kind == ObservationKind.BLOCKED or
        observation.kind == ObservationKind.MISS,
        'DwarfUICore tooltip observation kind must be target, blocked, or miss.')
    local state = self._state
    if observation.sequence <= state.last_sequence then return false end
    state.last_sequence = observation.sequence

    local target = observation.kind == ObservationKind.TARGET and
        observation.target or nil
    if target and not target_adapters.is_adapter(target) then
        if state.registrations[target] then
            target = target_adapters.adapt_widget(
                target, observation.root, state.registrations)
        else
            target = nil
        end
    end
    if target and not target:is_current() then target = nil end

    local identity = target and target:get_identity() or nil
    observation.identity = identity
    local previous_identity = state.target
    local previous_adapter = state.target_adapter
    if previous_identity ~= identity then
        if previous_adapter then previous_adapter:on_pointer_leave() end
        local local_position = observation.local_position
        if target then
            target:on_pointer_enter(
                local_position and local_position.x,
                local_position and local_position.y)
        end
    end
    if target then
        local local_position = observation.local_position
        target:on_pointer_update(
            local_position and local_position.x,
            local_position and local_position.y)
    end
    state.target = identity
    state.target_adapter = target

    local text = get_tooltip(target)
    if text then
        observation.root = target:get_source_root()
        self:_publish_intent(observation, text)
    else
        self:_clear_intent()
    end
    return true
end

---Clears target and intent state for deliberate service shutdown.
---@return boolean changed
function TooltipService:shutdown()
    self._state.last_sequence = 0
    return self:_clear_target()
end

---Returns presentation-neutral diagnostics for this service.
---@return table diagnostics
function TooltipService:get_diagnostics()
    local state = self._state
    return {
        api_version=API_VERSION,
        generation=state.generation,
        registration_count=self:registration_count(),
        target=state.target,
        intent=state.intent,
        revision=state.revision,
        last_sequence=state.last_sequence,
    }
end

service = process_state.service or TooltipService.new(process_state)
process_state.service = service
if publish_process_state then
    dfhack.dwarfuicore[SERVICE_SLOT] = process_state
end
