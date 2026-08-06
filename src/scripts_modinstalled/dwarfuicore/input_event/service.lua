--@ module=true

-- Private retained subscription registry for the public Input Event contract.

local contracts = reqscript('dwarfuicore/service_provider/contracts')
local identity = reqscript('dwarfuicore/service_provider/identity')
local types = reqscript('dwarfuicore/input_event/types')

---@class dwarfuicore.InputEventSubscription

---@class dwarfuicore.InputEventService
---@field _generation integer
---@field _input_manager dwarfuicore.ContextMenuInputHookManager
---@field _subscriptions table<dwarfuicore.InputEventSubscription, table>
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
    return setmetatable({_generation=generation, _input_manager=input_manager,
        _subscriptions={}}, InputEventService)
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
        channel=channel, callback=callback, demand=
            self._input_manager:acquire_subscription_demand(semantic, true,
                semantic)}
    return handle
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
