--@ module=true

-- Private retained subscription registry for the public Input Event contract.

local contracts = reqscript('dwarfuicore/service_provider/contracts')
local identity = reqscript('dwarfuicore/service_provider/identity')
local types = reqscript('dwarfuicore/input_event/types')
local event_deriver = reqscript('dwarfuicore/input_event/event_deriver')
local obstruction_resolver = reqscript(
    'dwarfuicore/input_event/ui_obstruction_resolver')
local root_collector = reqscript('dwarfuicore/input_event/ui_root_collector')

---@class dwarfuicore.InputEventSubscription

---@class dwarfuicore.InputEventService
---@field _generation integer
---@field _input_manager dwarfuicore.ContextMenuInputHookManager
---@field _subscriptions table<dwarfuicore.InputEventSubscription, table>
---@field _failures table[]
---@field _retired boolean
InputEventService = {}
InputEventService.__index = InputEventService

---Returns whether one value is an exact supported event-type member.
---@param event_type any
---@return boolean
local function is_event_type(event_type)
    return event_type == types.InputEventType.MAP_CLICK or
        event_type == types.InputEventType.RAW_CLICK
end

---Returns whether one channel identifier is supported internally.
---@param channel any
---@return boolean
local function is_channel(channel)
    return channel == 'observe' or channel == 'intercept'
end

---Returns the derived event matching one subscription type.
---@param derivation dwarfuicore.InputEventDerivation
---@param event_type dwarfuicore.InputEventType
---@return dwarfuicore.InputEvent|nil
local function event_for_type(derivation, event_type)
    if event_type == types.InputEventType.RAW_CLICK then return derivation.raw end
    return derivation.map
end

---Captures active eligible records in global registration order.
---@param service dwarfuicore.InputEventService
---@param derivation dwarfuicore.InputEventDerivation
---@param channel string
---@return table[] candidates
local function capture_candidates(service, derivation, channel)
    local candidates = {}
    for handle, record in pairs(service._subscriptions) do
        local event = event_for_type(derivation, record.event_type)
        if record.channel == channel and event ~= nil then
            table.insert(candidates, {handle=handle, record=record, event=event})
        end
    end
    table.sort(candidates, function(left, right)
        return left.record.sequence < right.record.sequence
    end)
    return candidates
end

---Records one public callback failure without affecting later callbacks.
---@param service dwarfuicore.InputEventService
---@param record table
---@param message any
function InputEventService:_record_failure(record, message)
    table.insert(self._failures, {namespace=record.identity.namespace,
        sequence=record.sequence, error=tostring(message)})
end

---Creates one service-bound retained subscription registry.
---@param generation integer
---@param input_manager dwarfuicore.ContextMenuInputHookManager
---@return dwarfuicore.InputEventService
function InputEventService.new(generation, input_manager)
    assert(math.type(generation) == 'integer' and generation > 0,
        'DwarfUICore Input Event service generation is invalid.')
    assert(type(input_manager) == 'table' and
            type(input_manager.acquire_subscription_demand) == 'function',
        'DwarfUICore Input Event service requires the input manager.')
    local service = setmetatable({_generation=generation,
        _input_manager=input_manager, _subscriptions={}, _failures={},
        _retired=false},
        InputEventService)
    input_manager:set_public_deriver(function(snapshot, current_root)
        local derivation = service:derive_current(snapshot, true, current_root,
            input_manager:get_additional_ui_roots())
        local dispatch = service:begin_dispatch(derivation)
        return {derivation=derivation, consumed=dispatch.consumed,
            complete=function() service:complete_dispatch(dispatch) end}
    end)
    dfhack.dwarfuicore.input_event_service = service
    return service
end

---Registers one strongly retained callback and its snapshot-demand contribution.
---@param consumer_namespace string
---@param contract_major integer
---@param event_type dwarfuicore.InputEventType
---@param channel string
---@param callback function
---@return dwarfuicore.InputEventSubscription handle
function InputEventService:subscribe(consumer_namespace, contract_major,
        event_type, channel, callback)
    assert(not self._retired,
        'DwarfUICore Input Event service is retired.')
    assert(is_event_type(event_type), 'DwarfUICore Input Event type is invalid.')
    assert(is_channel(channel), 'DwarfUICore Input Event channel is invalid.')
    assert(type(callback) == 'function',
        'DwarfUICore Input Event callback must be a function.')
    local composite = identity.get_process_allocator():allocate_identity(
        self._generation, contracts.ServiceKind.INPUT_EVENT, contract_major,
        consumer_namespace)
    local handle = identity.create_map_handle(composite)
    local semantic = event_type == types.InputEventType.MAP_CLICK
    self._subscriptions[handle] = {identity=composite, event_type=event_type,
        channel=channel, callback=callback,
        sequence=identity.get_process_allocator():allocate_sequence(), demand=
            self._input_manager:acquire_subscription_demand(semantic, true,
                semantic)}
    return handle
end

---Retires public delivery and releases every public demand contribution.
---@return boolean changed
function InputEventService:retire_for_reload()
    if self._retired then return false end
    self._retired = true
    self._input_manager:set_public_deriver(nil)
    local handles = {}
    for handle in pairs(self._subscriptions) do table.insert(handles, handle) end
    for _, handle in ipairs(handles) do
        local record = self._subscriptions[handle]
        self._subscriptions[handle] = nil
        self._input_manager:release_subscription_demand(record.demand)
    end
    if dfhack.dwarfuicore.input_event_service == self then
        dfhack.dwarfuicore.input_event_service = nil
    end
    return true
end

---Returns private lifecycle and dispatch diagnostics without callbacks.
---@return table diagnostics
function InputEventService:get_diagnostics()
    local subscriptions = {}
    for _, record in pairs(self._subscriptions) do
        table.insert(subscriptions, {namespace=record.identity.namespace,
            contract_major=record.identity.contract_major,
            event_type=record.event_type, channel=record.channel,
            sequence=record.sequence})
    end
    table.sort(subscriptions, function(left, right)
        return left.sequence < right.sequence
    end)
    local failure = self._failures[#self._failures]
    local input = type(self._input_manager.get_diagnostics) == 'function' and
        self._input_manager:get_diagnostics() or nil
    return {generation=self._generation, retired=self._retired,
        subscriptions=subscriptions, failure_count=#self._failures, input=input,
        last_failure=failure and {namespace=failure.namespace,
            sequence=failure.sequence, error=failure.error} or nil}
end

---Captures public candidates and runs eligible interceptors before delegation.
---@param derivation dwarfuicore.InputEventDerivation
---@return table dispatch
function InputEventService:begin_dispatch(derivation)
    assert(type(derivation) == 'table',
        'DwarfUICore Input Event dispatch requires a derivation.')
    local dispatch = {consumed=false,
        interceptors=capture_candidates(self, derivation, 'intercept'),
        observers=capture_candidates(self, derivation, 'observe')}
    for _, candidate in ipairs(dispatch.interceptors) do
        if self._subscriptions[candidate.handle] == candidate.record then
            local ok, result = pcall(candidate.record.callback, candidate.event)
            if not ok then
                self:_record_failure(candidate.record, result)
            elseif result == types.InputEventDisposition.PASS then
                -- Continue through the immutable pre-captured candidate list.
            elseif result == types.InputEventDisposition.CONSUME then
                dispatch.consumed = true
                break
            else
                self:_record_failure(candidate.record,
                    'Input Event interceptor must return Disposition.PASS or Disposition.CONSUME.')
            end
        end
    end
    return dispatch
end

---Runs pre-captured eligible observers after delegation or public consumption.
---@param dispatch table
function InputEventService:complete_dispatch(dispatch)
    assert(type(dispatch) == 'table' and type(dispatch.observers) == 'table',
        'DwarfUICore Input Event dispatch record is invalid.')
    for _, candidate in ipairs(dispatch.observers) do
        if self._subscriptions[candidate.handle] == candidate.record then
            local ok, message = pcall(candidate.record.callback, candidate.event)
            if not ok then self:_record_failure(candidate.record, message) end
        end
    end
end

---Removes one recognized same-domain active subscription.
---@param consumer_namespace string
---@param contract_major integer
---@param handle dwarfuicore.InputEventSubscription
---@return boolean removed
function InputEventService:unsubscribe(consumer_namespace, contract_major, handle)
    local record = self._subscriptions[handle]
    if not record then return false end
    local current = record.identity
    assert(current.namespace == consumer_namespace and
            current.contract_major == contract_major,
        'DwarfUICore Input Event subscription belongs to another domain.')
    self._subscriptions[handle] = nil
    self._input_manager:release_subscription_demand(record.demand)
    return true
end

---Returns whether one recognized same-domain subscription remains active.
---@param consumer_namespace string
---@param contract_major integer
---@param handle dwarfuicore.InputEventSubscription
---@return boolean active
function InputEventService:is_subscribed(consumer_namespace, contract_major,
        handle)
    local record = self._subscriptions[handle]
    if not record then return false end
    local current = record.identity
    assert(current.namespace == consumer_namespace and
            current.contract_major == contract_major,
        'DwarfUICore Input Event subscription belongs to another domain.')
    return true
end

---Removes every active subscription in exactly one namespace contract domain.
---@param consumer_namespace string
---@param contract_major integer
---@return boolean changed
function InputEventService:clear_namespace(consumer_namespace, contract_major)
    local handles = {}
    for handle, record in pairs(self._subscriptions) do
        local current = record.identity
        if current.namespace == consumer_namespace and
                current.contract_major == contract_major then
            table.insert(handles, handle)
        end
    end
    for _, handle in ipairs(handles) do
        self:unsubscribe(consumer_namespace, contract_major, handle)
    end
    return #handles > 0
end

---Derives eligible event facts after private arbitration without dispatching them.
---@param snapshot dwarfuicore.InputSnapshot
---@param hook_supported boolean
---@param roots table[]|nil
---@return dwarfuicore.InputEventDerivation
function InputEventService:derive(snapshot, hook_supported, roots)
    return event_deriver.InputEventDeriver.derive(snapshot, hook_supported,
        obstruction_resolver.InputEventUiObstructionResolver.is_unobstructed(
            roots, snapshot.screen_position))
end

---Collects host and Core roots before deriving semantic event eligibility.
---@param snapshot dwarfuicore.InputSnapshot
---@param hook_supported boolean
---@param current_root any
---@param additional_roots? table
---@return dwarfuicore.InputEventDerivation
function InputEventService:derive_current(snapshot, hook_supported,
        current_root, additional_roots)
    return self:derive(snapshot, hook_supported,
        root_collector.InputEventUiRootCollector.collect(current_root,
            additional_roots))
end
