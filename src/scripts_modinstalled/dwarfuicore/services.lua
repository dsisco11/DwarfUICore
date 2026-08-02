--@ module=true

local immutable_proxy = reqscript('dwarfuicore/service_provider/immutable_proxy')

---Creates a public provider that resolves the current private implementation
---only when a consumer constructs a service API.
---@param label string
---@param script_name string
---@return table provider
local function create_provider(label, script_name)
    local provider_factory
    local methods = {}

    ---Constructs a namespace-bound API through the current provider module.
    ---@param self table
    ---@param contract_version integer
    ---@param consumer_namespace string
    ---@return table api
    function methods:new(contract_version, consumer_namespace)
        assert(provider_factory:is_instance(self),
            ('DwarfUICore %s receiver is invalid.'):format(label))
        return reqscript(script_name).get_provider():new(
            contract_version, consumer_namespace)
    end

    provider_factory = immutable_proxy.new_factory(label, methods)
    return provider_factory:create({})
end

---Typed public tooltip service provider.
---@type dwarfuicore.TooltipServiceProvider
TooltipServiceProvider = create_provider('TooltipServiceProvider',
    'dwarfuicore/service_provider/tooltip_provider')

---Typed public context-menu service provider.
---@type dwarfuicore.ContextMenuServiceProvider
ContextMenuServiceProvider = create_provider('ContextMenuServiceProvider',
    'dwarfuicore/service_provider/context_menu_provider')
