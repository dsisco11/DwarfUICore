local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, immutable_enum = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')

describe('immutable enum utilities', function()
    it('defines immutable numeric enum members', function()
        local example = immutable_enum.define({
            FIRST=1,
            SECOND=2,
        }, 'ExampleKind')

        assert.equals(1, example.FIRST)
        assert.equals(2, example.SECOND)
        assert.same({FIRST=1, SECOND=2}, (function()
            local values = {}
            for name, value in pairs(example) do values[name] = value end
            return values
        end)())
        assert.has_error(function()
            example.FIRST = 3
        end, 'DwarfUICore ExampleKind is immutable.')
    end)

    it('rejects invalid names, values, and duplicates', function()
        assert.has_error(function()
            immutable_enum.define({FIRST=1, SECOND=1}, 'ExampleKind')
        end, 'DwarfUICore ExampleKind contains duplicate value 1.')
        for _, values in ipairs{
            {[1]=1},
            {FIRST='1'},
            {FIRST=0/0},
        } do
            assert.has_error(function()
                immutable_enum.define(values)
            end, 'DwarfUICore enum names must be strings and values must be numbers.')
        end
    end)
end)
