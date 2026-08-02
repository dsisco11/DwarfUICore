local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, function_chain = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/function_chain.lua')

describe('DwarfUICore function-chain utilities', function()
    it('detects direct and transitive predecessor wrappers', function()
        local original = function() end

        ---Captures the direct predecessor in a wrapper closure.
        ---@return function
        local function direct_wrapper()
            return original
        end
        local container = {direct_wrapper}

        ---Captures a table that transitively retains the predecessor.
        ---@return table
        local function transitive_wrapper()
            return container
        end

        assert.is_true(function_chain.wraps(direct_wrapper, original))
        assert.is_true(function_chain.wraps(transitive_wrapper, original))
        assert.is_false(function_chain.wraps(original, transitive_wrapper))
    end)

    it('terminates cyclic captured tables', function()
        local cycle = {}
        cycle.self = cycle
        local unrelated = function() end

        ---Captures a cyclic table without retaining the requested predecessor.
        ---@return table
        local function wrapper()
            return cycle
        end

        assert.is_false(function_chain.wraps(wrapper, unrelated))
    end)
end)
