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
    {name='dwarfuicore/class', contract='is_instance_of'},
    {name='dwarfuicore/map_projection', contract='project_visible'},
    {name='dwarfuicore/pointer_poller', contract='PointerPoller', contract_type='table'},
    {name='dwarfuicore/pointer', contract='PointerContext', contract_type='table'},
    {name='dwarfuicore/text', contract='wrap_text'},
    {name='dwarfuicore/view_root_resolver', contract='ViewRootResolver', contract_type='table'},
    {name='dwarfuicore/widget_extensions', contract='install_all'},
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
