local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, numbers = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/numbers.lua')

describe('numeric utilities', function()
    it('classifies integers without coercing other values', function()
        for _, value in ipairs{-3, 0, 4, 4.0} do
            assert.is_true(numbers.is_integer(value))
        end
        for _, value in ipairs{1.5, math.huge, '4', false, {}} do
            assert.is_false(numbers.is_integer(value))
        end
    end)
end)
