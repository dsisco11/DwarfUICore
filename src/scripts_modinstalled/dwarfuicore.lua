--@ module=true

-- DwarfUICore validation and explicit development reload command.

local MODULE_REGISTRY_SCRIPT = 'dwarfuicore/module_registry'

---Loads and validates the current DwarfUICore module generation.
---@return table<string, table>
function initialize()
    return reqscript(MODULE_REGISTRY_SCRIPT).load_all(reqscript)
end

---Rebuilds the DwarfUICore module generation for explicit development use.
---@return table<string, table>
function reload()
    local registry = reqscript(MODULE_REGISTRY_SCRIPT)
    local names = registry.get_script_names()
    dfhack.run_command('devel/clear-script-env', table.unpack(names))
    dfhack.run_script(MODULE_REGISTRY_SCRIPT)
    return reqscript(MODULE_REGISTRY_SCRIPT).load_all(reqscript)
end

---Runs DwarfUICore validation or its explicit development reload command.
---@param ... string
function main(...)
    local arguments = {...}
    if #arguments == 0 then
        initialize()
    elseif #arguments == 1 and arguments[1] == 'reload' then
        reload()
    else
        qerror('Usage: dwarfuicore [reload]')
    end
end

if not dfhack_flags.module then main(...) end
