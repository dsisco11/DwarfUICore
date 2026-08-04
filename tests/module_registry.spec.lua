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
            'dwarfuicore/service_provider/contracts',
            'dwarfuicore/service_provider/namespace',
            'dwarfuicore/service_provider/immutable_proxy',
            'dwarfuicore/service_provider/identity',
            'dwarfuicore/service_provider/runtime',
            'dwarfuicore/service_provider/acquisition',
            'dwarfuicore/service_provider/api',
            'dwarfuicore/user_prompt/value',
            'dwarfuicore/user_prompt/indicator',
            'dwarfuicore/user_prompt/service',
            'dwarfuicore/service_provider/weak_store',
            'dwarfuicore/class',
            'dwarfuicore/map_projection',
            'dwarfuicore/pointer_poller',
            'dwarfuicore/pointer',
            'dwarfuicore/text',
            'dwarfuicore/view_root_resolver',
            'dwarfuicore/widget_extensions',
            'dwarfuicore/user_prompt/input_consumer',
            'dwarfuicore/user_prompt/renderer',
            'dwarfuicore/tooltip/target',
            'dwarfuicore/tooltip/map_target',
            'dwarfuicore/tooltip/service',
            'dwarfuicore/tooltip/target_detector',
            'dwarfuicore/tooltip/registration',
            'dwarfuicore/tooltip/renderer',
            'dwarfuicore/tooltip/render_hook',
            'dwarfuicore/tooltip/presenter',
            'dwarfuicore/tooltip/runtime',
            'dwarfuicore/context_menu/definition',
            'dwarfuicore/context_menu/target',
            'dwarfuicore/context_menu/input_sample',
            'dwarfuicore/context_menu/root_discovery',
            'dwarfuicore/context_menu/map_target',
            'dwarfuicore/context_menu/registration',
            'dwarfuicore/context_menu/target_detector',
            'dwarfuicore/context_menu/input_hook',
            'dwarfuicore/context_menu/renderer',
            'dwarfuicore/context_menu/service',
            'dwarfuicore/context_menu/screen',
            'dwarfuicore/user_prompt/runtime',
            'dwarfuicore/service_provider/tooltip_adapter_v1',
            'dwarfuicore/service_provider/context_menu_adapter_v1',
            'dwarfuicore/service_provider/user_prompt_adapter_v1',
            'dwarfuicore/service_provider/tooltip_provider',
            'dwarfuicore/service_provider/context_menu_provider',
            'dwarfuicore/service_provider/user_prompt_provider',
            'dwarfuicore/services',
        }, (function()
            local names = {}
            for _, spec in ipairs(registry.MODULES) do
                table.insert(names, spec.name)
            end
            return names
        end)())
        assert.same({
            'dwarfuicore/module_registry',
            'dwarfuicore/services',
            'dwarfuicore/service_provider/user_prompt_provider',
            'dwarfuicore/service_provider/context_menu_provider',
            'dwarfuicore/service_provider/tooltip_provider',
            'dwarfuicore/service_provider/user_prompt_adapter_v1',
            'dwarfuicore/service_provider/context_menu_adapter_v1',
            'dwarfuicore/service_provider/tooltip_adapter_v1',
            'dwarfuicore/user_prompt/runtime',
            'dwarfuicore/context_menu/screen',
            'dwarfuicore/context_menu/service',
            'dwarfuicore/context_menu/renderer',
            'dwarfuicore/context_menu/input_hook',
            'dwarfuicore/context_menu/target_detector',
            'dwarfuicore/context_menu/registration',
            'dwarfuicore/context_menu/map_target',
            'dwarfuicore/context_menu/root_discovery',
            'dwarfuicore/context_menu/input_sample',
            'dwarfuicore/context_menu/target',
            'dwarfuicore/context_menu/definition',
            'dwarfuicore/tooltip/runtime',
            'dwarfuicore/tooltip/presenter',
            'dwarfuicore/tooltip/render_hook',
            'dwarfuicore/tooltip/renderer',
            'dwarfuicore/tooltip/registration',
            'dwarfuicore/tooltip/target_detector',
            'dwarfuicore/tooltip/service',
            'dwarfuicore/tooltip/map_target',
            'dwarfuicore/tooltip/target',
            'dwarfuicore/user_prompt/renderer',
            'dwarfuicore/user_prompt/input_consumer',
            'dwarfuicore/widget_extensions',
            'dwarfuicore/view_root_resolver',
            'dwarfuicore/text',
            'dwarfuicore/pointer',
            'dwarfuicore/pointer_poller',
            'dwarfuicore/map_projection',
            'dwarfuicore/class',
            'dwarfuicore/service_provider/weak_store',
            'dwarfuicore/user_prompt/service',
            'dwarfuicore/user_prompt/indicator',
            'dwarfuicore/user_prompt/value',
            'dwarfuicore/service_provider/api',
            'dwarfuicore/service_provider/acquisition',
            'dwarfuicore/service_provider/runtime',
            'dwarfuicore/service_provider/identity',
            'dwarfuicore/service_provider/immutable_proxy',
            'dwarfuicore/service_provider/namespace',
            'dwarfuicore/service_provider/contracts',
            'dwarfuicore/utils/numbers',
            'dwarfuicore/utils/function_chain',
            'dwarfuicore/utils/immutable_enum',
        }, registry.get_script_names())
    end)

    it('reports the module and missing contract during validation', function()
        local _, registry = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfuicore/module_registry.lua')

        local ok, failure = pcall(function()
            registry.load_all(function() return {} end)
        end)
        assert.is_false(ok)
        assert.is_truthy(tostring(failure):find(
            'DwarfUICore module dwarfuicore/utils/immutable_enum is ' ..
                'missing define', 1, true))
    end)
end)
