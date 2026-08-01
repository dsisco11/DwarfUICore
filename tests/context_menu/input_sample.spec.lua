local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local MODULE_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/input_sample.lua'

---Loads the sampler with its real numeric-validation dependency.
---@return table
local function load_module()
    local _, numbers = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/utils/numbers.lua')
    local _, module = module_loader.load(repo_root, MODULE_PATH, {
        globals={
            dfhack={
                gui={getMousePos=function() return nil end},
                screen={getMousePos=function() return nil, nil end},
            },
        },
        reqscript={['dwarfuicore/utils/numbers']=numbers},
    })
    return module
end

describe('DwarfUICore context-menu synchronous input sample', function()
    it('reads screen coordinates once and skips map sampling without demand',
            function()
        local module = load_module()
        local screen_reads = 0
        local map_reads = 0
        local sampler = module.ContextMenuInputSampler.new{
            sample_screen_pointer=function()
                screen_reads = screen_reads + 1
                return 7, 9
            end,
            sample_map_pointer=function()
                map_reads = map_reads + 1
                return {x=1, y=2, z=3}
            end,
        }

        local sample = sampler:capture()

        assert.equals(1, screen_reads)
        assert.equals(0, map_reads)
        assert.same({7, 9}, {sample.x, sample.y})
        assert.is_nil(sample.map_x)
        assert.is_nil(sample.map_y)
        assert.is_nil(sample.map_z)
    end)

    it('reads an exact map coordinate once and copies every scalar', function()
        local module = load_module()
        local screen_reads = 0
        local map_reads = 0
        local position = {x=11, y=12, z=13}
        local sampler = module.ContextMenuInputSampler.new{
            sample_screen_pointer=function()
                screen_reads = screen_reads + 1
                return 4, 5
            end,
            sample_map_pointer=function()
                map_reads = map_reads + 1
                return position
            end,
            has_map_demand=function() return true end,
        }

        local sample = sampler:capture()
        position.x, position.y, position.z = 21, 22, 23

        assert.equals(1, screen_reads)
        assert.equals(1, map_reads)
        assert.same(
            {4, 5, 11, 12, 13},
            {sample.x, sample.y, sample.map_x, sample.map_y, sample.map_z})
    end)

    it('normalizes invalid coordinates and prevents every mutation', function()
        local module = load_module()
        local sampler = module.ContextMenuInputSampler.new{
            sample_screen_pointer=function() return 1.5, 2 end,
            sample_map_pointer=function() return {x=1, y='2', z=3} end,
            has_map_demand=function() return true end,
        }
        local sample = sampler:capture()

        assert.is_nil(sample.x)
        assert.is_nil(sample.y)
        assert.is_nil(sample.map_x)
        assert.is_nil(sample.map_y)
        assert.is_nil(sample.map_z)
        assert.has_error(function() sample.x = 10 end)
        assert.has_error(function() sample.extra = true end)
    end)
end)
