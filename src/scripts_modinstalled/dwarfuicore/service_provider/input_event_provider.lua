--@ module=true

local acquisition = reqscript('dwarfuicore/service_provider/acquisition')
local api = reqscript('dwarfuicore/service_provider/api')
local contracts = reqscript('dwarfuicore/service_provider/contracts')
local immutable_proxy = reqscript('dwarfuicore/service_provider/immutable_proxy')
local types = reqscript('dwarfuicore/input_event/types')

local API_FACTORY = api.new_factory(contracts.ServiceKind.INPUT_EVENT,
    'InputEventServiceApi', {'observe', 'intercept', 'unsubscribe',
        'is_subscribed', 'clear_namespace'}, {EventType=types.InputEventType,
        Disposition=types.InputEventDisposition})

---@class dwarfuicore.InputEventServiceProvider
---@field new fun(self: dwarfuicore.InputEventServiceProvider, contract_version: integer, consumer_namespace: string): dwarfuicore.InputEventServiceApi

---Loads the private Input Event adapter after public constructor validation.
---@return dwarfuicore.ServiceAcquisitionAdapter
local function load_adapter()
    return reqscript('dwarfuicore/service_provider/input_event_adapter_v1')
end

local provider_factory
local methods = {}

---Creates one immutable namespace-bound Input Event API.
---@param self table
---@param contract_version integer
---@param consumer_namespace string
---@return table api
function methods:new(contract_version, consumer_namespace)
    assert(provider_factory:is_instance(self),
        'DwarfUICore InputEventServiceProvider receiver is invalid.')
    return API_FACTORY:create(acquisition.acquire(
        contracts.ServiceKind.INPUT_EVENT, 1, load_adapter, contract_version,
        consumer_namespace, true))
end

provider_factory = immutable_proxy.new_factory('InputEventServiceProvider', methods)

---Returns the immutable Input Event provider export.
---@return table provider
function get_provider()
    return provider_factory:create({})
end
