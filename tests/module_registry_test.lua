local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, registry = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/module_registry.lua')

describe('DwarfUI module registry', function()
    it('loads registered contracts in dependency order', function()
        local calls = {}
        local loaded = registry.load_all(function(name)
            table.insert(calls, name)
            for _, spec in ipairs(registry.MODULES) do
                if spec.name == name then
                    local value = spec.contract_type == 'table' and {} or
                        function() end
                    return {[spec.contract]=value}
                end
            end
        end)

        assert.equals(#registry.MODULES, #calls)
        assert.equals('dwarfui/text', calls[1])
        assert.equals('dwarfui/tooltip_registration', calls[#calls])
        assert.equals('table', type(loaded['dwarfui/tooltip']))
    end)

    it('rejects a module that does not implement its contract', function()
        local ok, err = pcall(registry.load_all, function()
            return {}
        end)

        assert.is_false(ok)
        assert.is_truthy(tostring(err):find(
            'DwarfUI module dwarfui/text is missing wrap_text()', 1, true))
    end)

    it('clears consumers before their dependencies', function()
        local names = registry.get_script_names()

        assert.equals(#registry.MODULES + 1, #names)
        assert.equals('dwarfui/module_registry', names[1])
        assert.equals('dwarfui/tooltip_registration', names[2])
        assert.equals('dwarfui/text', names[#names])
    end)
end)
