local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

describe('dwarfuicore module registry', function()
    it('starts with no extracted modules registered', function()
        local _, registry = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfuicore/module_registry.lua')

        assert.same({}, registry.MODULES)
        assert.same({'dwarfuicore/module_registry'}, registry.get_script_names())
    end)
end)
