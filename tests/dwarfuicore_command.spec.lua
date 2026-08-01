local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

describe('dwarfuicore command', function()
    ---Creates the minimum DFHack command surface required by the root module.
    ---@return table
    local function dfhack_stub()
        return {
            run_command=function() end,
            run_script=function() end,
        }
    end

    it('exports validation and explicit reload commands as a module', function()
        local _, module = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfuicore.lua', {
                globals={
                    dfhack=dfhack_stub(),
                    dfhack_flags={module=true},
                    qerror=function(message) error(message, 0) end,
                },
                reqscript={
                    ['dwarfuicore/module_registry']={
                        load_all=function() return {} end,
                        get_script_names=function() return {} end,
                    },
                },
            })

        assert.is_function(module.initialize)
        assert.is_function(module.reload)
        assert.is_function(module.main)
    end)
end)
