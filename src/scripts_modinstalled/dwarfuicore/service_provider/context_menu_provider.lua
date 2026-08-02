--@ module=true

local acquisition = reqscript('dwarfuicore/service_provider/acquisition')
local api = reqscript('dwarfuicore/service_provider/api')
local contracts = reqscript('dwarfuicore/service_provider/contracts')
local immutable_proxy = reqscript('dwarfuicore/service_provider/immutable_proxy')

local API_FACTORY = api.new_factory(contracts.ServiceKind.CONTEXT_MENU,
    'ContextMenuServiceApi', {'register', 'update', 'unregister',
        'register_map_tile', 'update_map_tile', 'unregister_map_tile',
        'clear_namespace'})

---Creates namespace-bound context-menu APIs for exact supported contracts.
---@class dwarfuicore.ContextMenuServiceProvider
---@field new fun(self: dwarfuicore.ContextMenuServiceProvider, contract_version: integer, consumer_namespace: string): dwarfuicore.ContextMenuServiceApi

---Loads the private context-menu adapter only after constructor validation.
---@return dwarfuicore.ServiceAcquisitionAdapter adapter
local function load_adapter()
    return reqscript('dwarfuicore/service_provider/context_menu_adapter_v1')
end

local provider_factory
local methods = {}

---Creates a distinct immutable context-menu API for one exact namespace contract.
---@param self table
---@param contract_version integer
---@param consumer_namespace string
---@return dwarfuicore.ContextMenuServiceApi
function methods:new(contract_version, consumer_namespace)
    assert(provider_factory:is_instance(self),
        'DwarfUICore ContextMenuServiceProvider receiver is invalid.')
    local metadata = acquisition.acquire(contracts.ServiceKind.CONTEXT_MENU, 1,
        load_adapter, contract_version, consumer_namespace, true)
    return API_FACTORY:create(metadata)
end

provider_factory = immutable_proxy.new_factory('ContextMenuServiceProvider', methods)

---Returns the one immutable public context-menu provider export.
---@return table provider
function get_provider()
    return provider_factory:create({})
end
