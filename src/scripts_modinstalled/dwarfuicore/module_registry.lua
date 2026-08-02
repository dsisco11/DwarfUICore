--@ module=true

---Describes one reload-managed DwarfUICore module contract.
---@class dwarfuicore.ModuleSpec
---@field name string
---@field contract string
---@field contract_type string|nil

---@type dwarfuicore.ModuleSpec[]
MODULES = {
    {name='dwarfuicore/utils/immutable_enum', contract='define'},
    {name='dwarfuicore/utils/function_chain', contract='wraps'},
    {name='dwarfuicore/utils/numbers', contract='is_integer'},
    {name='dwarfuicore/service_provider/contracts', contract='get_error_token'},
    {name='dwarfuicore/service_provider/namespace', contract='validate'},
    {name='dwarfuicore/service_provider/immutable_proxy', contract='new_factory'},
    {name='dwarfuicore/service_provider/identity', contract='get_process_allocator'},
    {name='dwarfuicore/service_provider/runtime', contract='validate'},
    {name='dwarfuicore/service_provider/acquisition', contract='acquire'},
    {name='dwarfuicore/service_provider/api', contract='new_factory'},
    {name='dwarfuicore/service_provider/tooltip_adapter_v1', contract='build_facade'},
    {name='dwarfuicore/service_provider/context_menu_adapter_v1', contract='build_facade'},
    {name='dwarfuicore/service_provider/tooltip_provider', contract='get_provider'},
    {name='dwarfuicore/service_provider/context_menu_provider', contract='get_provider'},
    {name='dwarfuicore/services', contract='TooltipServiceProvider', contract_type='table'},
    {name='dwarfuicore/service_provider/weak_store', contract='WeakRegistrationStore', contract_type='table'},
    {name='dwarfuicore/class', contract='is_instance_of'},
    {name='dwarfuicore/map_projection', contract='project_visible'},
    {name='dwarfuicore/pointer_poller', contract='PointerPoller', contract_type='table'},
    {name='dwarfuicore/pointer', contract='PointerContext', contract_type='table'},
    {name='dwarfuicore/text', contract='wrap_text'},
    {name='dwarfuicore/view_root_resolver', contract='ViewRootResolver', contract_type='table'},
    {name='dwarfuicore/widget_extensions', contract='install_all'},
    {name='dwarfuicore/tooltip/target', contract='TooltipTargetAdapter', contract_type='table'},
    {name='dwarfuicore/tooltip/map_target', contract='registry', contract_type='table'},
    {name='dwarfuicore/tooltip/service', contract='service', contract_type='table'},
    {name='dwarfuicore/tooltip/target_detector', contract='TooltipTargetDetector', contract_type='table'},
    {name='dwarfuicore/tooltip/registration', contract='register'},
    {name='dwarfuicore/tooltip/renderer', contract='TooltipRenderer', contract_type='table'},
    {name='dwarfuicore/tooltip/render_hook', contract='manager', contract_type='table'},
    {name='dwarfuicore/tooltip/presenter', contract='TooltipPresenter', contract_type='table'},
    {name='dwarfuicore/tooltip/runtime', contract='presenter', contract_type='table'},
    {name='dwarfuicore/tooltip/api', contract='register'},
    {name='dwarfuicore/context_menu/definition', contract='ContextMenuDefinitionSnapshot', contract_type='table'},
    {name='dwarfuicore/context_menu/target', contract='ContextMenuOpenSession', contract_type='table'},
    {name='dwarfuicore/context_menu/input_sample', contract='ContextMenuInputSampler', contract_type='table'},
    {name='dwarfuicore/context_menu/root_discovery', contract='ContextMenuRootDiscovery', contract_type='table'},
    {name='dwarfuicore/context_menu/map_target', contract='ContextMenuMapTargetRegistry', contract_type='table'},
    {name='dwarfuicore/context_menu/registration', contract='manager', contract_type='table'},
    {name='dwarfuicore/context_menu/target_detector', contract='ContextMenuTargetDetector', contract_type='table'},
    {name='dwarfuicore/context_menu/input_hook', contract='manager', contract_type='table'},
    {name='dwarfuicore/context_menu/renderer', contract='ContextMenuWindow', contract_type='table'},
    {name='dwarfuicore/context_menu/service', contract='service', contract_type='table'},
    {name='dwarfuicore/context_menu/screen', contract='ContextMenuScreen', contract_type='table'},
    {name='dwarfuicore/context_menu/api', contract='register'},
}

local REGISTRY_SCRIPT = 'dwarfuicore/module_registry'

---Loads and validates every registered DwarfUICore module.
---@param loader fun(name: string): table
---@return table<string, table>
function load_all(loader)
    local loaded = {}
    for _, spec in ipairs(MODULES) do
        local module = loader(spec.name)
        local expected_type = spec.contract_type or 'function'
        assert(type(module[spec.contract]) == expected_type,
            ('DwarfUICore module %s is missing %s'):format(
                spec.name, spec.contract))
        loaded[spec.name] = module
    end
    return loaded
end

---Returns registry and module script names in safe environment-clear order.
---@return string[]
function get_script_names()
    local names = {REGISTRY_SCRIPT}
    for index = #MODULES, 1, -1 do
        table.insert(names, MODULES[index].name)
    end
    return names
end
