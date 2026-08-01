local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

describe('dwarfuicore module registry', function()
    it('registers shared infrastructure in dependency order', function()
        local _, registry = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfuicore/module_registry.lua')

        assert.same({
            'dwarfuicore/utils/immutable_enum',
            'dwarfuicore/utils/function_chain',
            'dwarfuicore/utils/numbers',
            'dwarfuicore/class',
            'dwarfuicore/map_projection',
            'dwarfuicore/pointer_poller',
            'dwarfuicore/pointer',
            'dwarfuicore/text',
            'dwarfuicore/view_root_resolver',
            'dwarfuicore/widget_extensions',
            'dwarfuicore/tooltip/target',
            'dwarfuicore/tooltip/map_target',
            'dwarfuicore/tooltip/service',
            'dwarfuicore/tooltip/target_detector',
            'dwarfuicore/tooltip/registration',
            'dwarfuicore/tooltip/renderer',
            'dwarfuicore/tooltip/render_hook',
            'dwarfuicore/tooltip/presenter',
            'dwarfuicore/tooltip/runtime',
            'dwarfuicore/tooltip/api',
        }, (function()
            local names = {}
            for _, spec in ipairs(registry.MODULES) do
                table.insert(names, spec.name)
            end
            return names
        end)())
        assert.same({
            'dwarfuicore/module_registry',
            'dwarfuicore/tooltip/api',
            'dwarfuicore/tooltip/runtime',
            'dwarfuicore/tooltip/presenter',
            'dwarfuicore/tooltip/render_hook',
            'dwarfuicore/tooltip/renderer',
            'dwarfuicore/tooltip/registration',
            'dwarfuicore/tooltip/target_detector',
            'dwarfuicore/tooltip/service',
            'dwarfuicore/tooltip/map_target',
            'dwarfuicore/tooltip/target',
            'dwarfuicore/widget_extensions',
            'dwarfuicore/view_root_resolver',
            'dwarfuicore/text',
            'dwarfuicore/pointer',
            'dwarfuicore/pointer_poller',
            'dwarfuicore/map_projection',
            'dwarfuicore/class',
            'dwarfuicore/utils/numbers',
            'dwarfuicore/utils/function_chain',
            'dwarfuicore/utils/immutable_enum',
        }, registry.get_script_names())
    end)
end)
