--@ module=true

-- Process-wide tooltip semantics. The exported service object owns
-- registrations, pointer transitions, and immutable presentation intent, but
-- has no presentation implementation or UI-host dependency.

API_VERSION = 1
local SERVICE_SLOT = 'tooltip_service'
local LEGACY_HOST_SLOT = 'tooltip_legacy_host'

dfhack.dwarfui = dfhack.dwarfui or {}
local process_state = dfhack.dwarfui[SERVICE_SLOT]

-- TEMPORARY: migrate the pre-mediation service shape without importing or
-- manipulating its presentation objects. The legacy registration module
-- retires the moved host after this input service has loaded.
if process_state and process_state.screen ~= nil then
    dfhack.dwarfui[LEGACY_HOST_SLOT] = process_state
    process_state = {
        api_version=API_VERSION,
        registrations=process_state.registrations,
        registration_sequence=process_state.sequence or 0,
        target=process_state.target,
        intent=nil,
        revision=0,
        last_sequence=0,
        intent_observer=nil,
        generation=0,
    }
    dfhack.dwarfui[SERVICE_SLOT] = process_state
end

if process_state and process_state.api_version ~= API_VERSION then
    error(('Conflicting DwarfUI tooltip service versions: ' ..
        'process has %s, requested %s.'):format(
            tostring(process_state.api_version), tostring(API_VERSION)))
end
if not process_state then
    process_state = {
        api_version=API_VERSION,
        registrations=setmetatable({}, {__mode='k'}),
        registration_sequence=0,
        target=nil,
        intent=nil,
        revision=0,
        last_sequence=0,
        intent_observer=nil,
        generation=0,
    }
    dfhack.dwarfui[SERVICE_SLOT] = process_state
end

---@class dwarfui.TooltipIntent
---@field revision integer
---@field source_sequence integer
---@field text string
---@field anchor_x integer
---@field anchor_y integer
---@field coordinate_space '"screen-cells"'
---@field source_root gui.View

---Receives each changed immutable intent, or nil when intent is cleared.
---@alias dwarfui.TooltipIntentObserver fun(intent: dwarfui.TooltipIntent|nil, revision: integer)

---@class dwarfui.TooltipServiceState
---@field api_version integer
---@field registrations table<gui.View, table>
---@field registration_sequence integer
---@field target gui.View|nil
---@field intent dwarfui.TooltipIntent|nil
---@field revision integer
---@field last_sequence integer
---@field intent_observer dwarfui.TooltipIntentObserver|nil
---@field generation integer

---@class dwarfui.TooltipService
---@field _state dwarfui.TooltipServiceState
TooltipService = {}
TooltipService.__index = TooltipService

---Creates a service object over process-owned reload-safe state.
---@param state dwarfui.TooltipServiceState
---@return dwarfui.TooltipService
function TooltipService.new(state)
    assert(type(state) == 'table',
        'DwarfUI TooltipService requires process-owned state.')
    return setmetatable({_state=state}, TooltipService)
end

---Returns validated tooltip text after pointer callbacks have run.
---@param target gui.View|nil
---@return string|nil
local function get_tooltip(target)
    if not target then return nil end
    local value = target.tooltip
    if value == nil or value == '' then return nil end
    assert(type(value) == 'string',
        'DwarfUI tooltip must be a string, nil, or an empty string; got ' ..
        type(value) .. '.')
    return value
end

---Creates one immutable tooltip-intent snapshot.
---@param observation dwarfui.TooltipPointerObservation
---@param text string
---@param revision integer
---@return dwarfui.TooltipIntent
local function make_intent(observation, text, revision)
    local values = {
        revision=revision,
        source_sequence=observation.sequence,
        text=text,
        anchor_x=observation.pointer_x,
        anchor_y=observation.pointer_y,
        coordinate_space='screen-cells',
        source_root=observation.root,
    }
    return setmetatable({}, {
        __index=values,
        __newindex=function()
            error('DwarfUI tooltip intents are immutable.', 2)
        end,
        __pairs=function()
            return next, values, nil
        end,
        __metatable=false,
    })
end

---Notifies this service's optional presentation-neutral intent observer.
---@param intent dwarfui.TooltipIntent|nil
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
---@param observation dwarfui.TooltipPointerObservation
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
    local previous = state.target
    if previous and previous.on_pointer_leave then
        previous.on_pointer_leave(previous)
    end
    state.target = nil
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

---Registers one tooltip target with deterministic cross-root sequence.
---@param widget gui.View
---@return boolean created
function TooltipService:register(widget)
    assert(type(widget) == 'table',
        'DwarfUI tooltip registration requires a widget table.')
    local state = self._state
    if state.registrations[widget] then return false end
    state.registration_sequence = state.registration_sequence + 1
    state.registrations[widget] = {
        sequence=state.registration_sequence,
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

---Replaces or removes this service's presentation-neutral intent observer.
---Replacement never replays intent or synthesizes pointer callbacks.
---@param observer dwarfui.TooltipIntentObserver|nil
function TooltipService:set_intent_observer(observer)
    assert(observer == nil or type(observer) == 'function',
        'DwarfUI tooltip intent observer must be a function or nil.')
    self._state.intent_observer = observer
end

---Accepts one ordered detector observation and mediates tooltip semantics.
---@param observation dwarfui.TooltipPointerObservation
---@return boolean accepted
function TooltipService:accept_pointer_observation(observation)
    assert(type(observation) == 'table',
        'DwarfUI tooltip service requires a pointer observation.')
    assert(type(observation.sequence) == 'number',
        'DwarfUI tooltip observation sequence must be a number.')
    assert(observation.kind == 'target' or
        observation.kind == 'blocked' or observation.kind == 'miss',
        'DwarfUI tooltip observation kind must be target, blocked, or miss.')
    local state = self._state
    if observation.sequence <= state.last_sequence then return false end
    state.last_sequence = observation.sequence

    local target = observation.kind == 'target' and
        observation.target or nil
    if target and not state.registrations[target] then target = nil end

    local previous = state.target
    if previous ~= target then
        if previous and previous.on_pointer_leave then
            previous.on_pointer_leave(previous)
        end
        if target and target.on_pointer_enter then
            target.on_pointer_enter(
                target, observation.local_x, observation.local_y)
        end
    end
    if target and target.on_pointer_update then
        target.on_pointer_update(
            target, observation.local_x, observation.local_y)
    end
    state.target = target

    local text = get_tooltip(target)
    if text then
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

service = TooltipService.new(process_state)

-- A same-version module reload preserves weak registrations but retires every
-- target, intent, observer closure, and sequence from the previous generation.
if process_state.generation > 0 or process_state.target or process_state.intent then
    service:shutdown()
end
process_state.intent_observer = nil
process_state.last_sequence = 0
process_state.generation = process_state.generation + 1
