local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local MODULE_PATH = 'src/scripts_modinstalled/dwarfuicore/map_projection.lua'

---Loads projection with mutable text/Premium viewport state.
---@return table
---@return table
local function fixture()
    local state = {
        graphics=false,
        world_loaded=true,
        active_viewport=nil,
        map_origin={x1=0, y1=0},
        gps={
            viewport_zoom_factor=16,
            tile_pixel_x=8,
            tile_pixel_y=16,
        },
        corner={x=100, y=200, z=5},
    }
    local globals = {
        df={
            global={
                gps=state.gps,
                world={
                    viewport={corner=state.corner},
                },
            },
        },
        dfhack={
            isWorldLoaded=function() return state.world_loaded end,
            screen={
                inGraphicsMode=function() return state.graphics end,
            },
        },
    }
    local _, projection = module_loader.load(repo_root, MODULE_PATH, {
        globals=globals,
        require_modules={
            ['gui.dwarfmode']={
                getPanelLayout=function()
                    return {map=state.map_origin}
                end,
                Viewport={
                    get=function() return state.active_viewport end,
                },
            },
        },
    })
    return projection, state
end

---Creates one text viewport double.
---@param x integer
---@param y integer
---@param z integer
---@param width integer
---@param height integer
---@return table
local function viewport(x, y, z, width, height)
    return {
        x1=x,
        y1=y,
        z=z,
        width=width,
        height=height,
        tileToScreen=function(self, pos)
            return {x=pos.x-self.x1, y=pos.y-self.y1, z=pos.z-self.z}
        end,
        isVisible=function(self, pos)
            return pos.z == self.z and pos.x >= self.x1 and
                pos.x < self.x1 + self.width and pos.y >= self.y1 and
                pos.y < self.y1 + self.height
        end,
    }
end

describe('DwarfUICore map projection', function()
    it('copy-constructs projected positions without retaining mutable input', function()
        local projection = fixture()
        local input = {x=4, y=5, z=6}
        local result = projection.MapProjectionResult.new(input)

        input.x, input.y, input.z = 7, 8, 9
        assert.same({x=4, y=5, z=6}, result)
        assert.has_error(function()
            projection.MapProjectionResult.new{x=1.5, y=0, z=0}
        end)
    end)

    it('uses the active text viewport and exact edge visibility', function()
        local projection, state = fixture()
        state.active_viewport = viewport(10, 20, 3, 8, 6)

        assert.same({x=0, y=0, z=0},
            projection.project_visible({x=10, y=20, z=3}))
        assert.same({x=7, y=5, z=0},
            projection.project_visible({x=17, y=25, z=3}))
        state.map_origin.x1, state.map_origin.y1 = 3, 2
        assert.same({x=10, y=7, z=0},
            projection.project_visible({x=17, y=25, z=3}))
        assert.is_nil(projection.project_visible({x=18, y=25, z=3}))
        assert.is_nil(projection.project_visible({x=10, y=20, z=4}))
    end)

    it('uses Premium corner, interface dimensions, and current zoom', function()
        local projection, state = fixture()
        state.graphics = true
        state.active_viewport = viewport(0, 0, 5, 20, 10)

        assert.same({x=2, y=1, z=0},
            projection.project_visible({x=104, y=204, z=5}))
        assert.is_nil(projection.project_visible({x=140, y=204, z=5}))
        state.active_viewport.width = 21
        assert.same({x=20, y=1, z=0},
            projection.project_visible({x=140, y=204, z=5}))
        state.graphics = false
        state.world_loaded = false
        assert.is_nil(projection.project_visible({x=10, y=20, z=3}))
    end)

    it('accepts Premium tiles rendered through the logical map viewport',
            function()
        local projection, state = fixture()
        state.graphics = true
        state.corner.x, state.corner.y, state.corner.z = 13, 34, 132
        state.gps.viewport_zoom_factor = 192
        state.gps.tile_pixel_x, state.gps.tile_pixel_y = 13, 19
        state.active_viewport = viewport(13, 34, 132, 72, 30)

        assert.same({x=133, y=38, z=0},
            projection.project_visible({x=49, y=49, z=132}))
        state.corner.z = 131
        assert.is_nil(projection.project_visible({x=49, y=49, z=132}))
    end)

    it('recomputes after Premium camera and zoom changes', function()
        local projection, state = fixture()
        state.graphics = true
        state.active_viewport = viewport(0, 0, 5, 30, 20)

        assert.same({x=4, y=2, z=0},
            projection.project_visible({x=108, y=208, z=5}))
        state.corner.x = 104
        assert.same({x=2, y=2, z=0},
            projection.project_visible({x=108, y=208, z=5}))
        state.gps.viewport_zoom_factor = 32
        assert.same({x=4, y=4, z=0},
            projection.project_visible({x=108, y=208, z=5}))
    end)
end)
