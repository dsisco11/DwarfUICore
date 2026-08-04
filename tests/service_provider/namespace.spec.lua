local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, namespace = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')

describe('service-provider namespace validation', function()
    it('accepts the exact version 1 grammar without normalization', function()
        for _, value in ipairs({'a', 'dwarfui', 'author.plugin-name',
                'a_b-2.c', 'a' .. string.rep('0', 63)}) do
            assert.is_true(namespace.is_valid(value), value)
            assert.equals(value, namespace.validate(value))
        end
        assert.is_true(namespace.is_valid('plugin-name'))
        assert.is_true(namespace.is_valid('plugin_name'))
        assert.is_false(namespace.is_valid('PLUGIN.NAME'))
    end)

    it('rejects missing, malformed, and overlong values', function()
        local invalid = {false, 1, {}, '', '0plugin', '_plugin', '-plugin',
            '.plugin', 'plugin.', 'plugin..name', 'Plugin', 'plugin/name',
            'plugin name', 'a' .. string.rep('0', 64), 'plugin\0name'}
        for _, value in ipairs(invalid) do
            assert.is_false(namespace.is_valid(value), tostring(value))
            assert.has_error(function() namespace.validate(value) end,
                'DwarfUICore consumer namespace is invalid.')
        end
    end)

    it('compares valid namespaces byte for byte', function()
        assert.is_false(namespace.validate('plugin-name') ==
            namespace.validate('plugin_name'))
        assert.is_false(namespace.validate('plugin.name') ==
            namespace.validate('plugin-name'))
    end)
end)
