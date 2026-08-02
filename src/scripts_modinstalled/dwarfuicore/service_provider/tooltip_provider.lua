--@ module=true

local acquisition = reqscript('dwarfuicore/service_provider/acquisition')
local api = reqscript('dwarfuicore/service_provider/api')
local contracts = reqscript('dwarfuicore/service_provider/contracts')
local immutable_proxy = reqscript('dwarfuicore/service_provider/immutable_proxy')

local API_FACTORY = api.new_factory(contracts.ServiceKind.TOOLTIP,
    'TooltipServiceApi', {'register', 'unregister', 'register_map_tile',
        'update_map_tile', 'unregister_map_tile', 'clear_namespace'})

---Creates namespace-bound tooltip APIs for exact supported contracts.
---@class dwarfuicore.TooltipServiceProvider
---@field new fun(self: dwarfuicore.TooltipServiceProvider, contract_version: integer, consumer_namespace: string): dwarfuicore.TooltipServiceApi

---Loads the private tooltip adapter only after constructor validation.
---@return dwarfuicore.ServiceAcquisitionAdapter adapter
local function load_adapter()
    return reqscript('dwarfuicore/service_provider/tooltip_adapter_v1')
end

local provider_factory
local methods = {}

---Creates a distinct immutable tooltip API for one exact namespace contract.
---@param self table
---@param contract_version integer
---@param consumer_namespace string
---@return dwarfuicore.TooltipServiceApi
function methods:new(contract_version, consumer_namespace)
    assert(provider_factory:is_instance(self),
        'DwarfUICore TooltipServiceProvider receiver is invalid.')
    local metadata = acquisition.acquire(contracts.ServiceKind.TOOLTIP, 1,
        load_adapter, contract_version, consumer_namespace, true)
    return API_FACTORY:create(metadata)
end

provider_factory = immutable_proxy.new_factory('TooltipServiceProvider', methods)

---Returns the one immutable public tooltip provider export.
---@return table provider
function get_provider()
    return provider_factory:create({})
end
