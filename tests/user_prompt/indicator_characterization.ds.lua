-- Installed-runtime characterization for the native map selection indicator.

---Copies one native coordinate into plain Lua values.
---@param value df.coord
---@return {x: integer, y: integer, z: integer}
local function copy_coord(value)
    return {x=value.x, y=value.y, z=value.z}
end

---Captures view and follow state that direct indicator assignment must preserve.
---@return table
local function capture_view_state()
    local plotinfo = df.global.plotinfo
    return {
        window_x=df.global.window_x,
        window_y=df.global.window_y,
        window_z=df.global.window_z,
        follow_unit=plotinfo and plotinfo.follow_unit or nil,
        follow_item=plotinfo and plotinfo.follow_item or nil,
    }
end

describe('native recenter indicator characterization', function()
    it('uses the coord sentinel and direct assignment changes only the indicator',
            function()
        assert.is_not_nil(df.global.world,
            'characterization requires a loaded world')
        local main_interface = assert(df.global.game.main_interface,
            'main interface is unavailable')
        local indicator = assert(main_interface.recenter_indicator_m,
            'native recenter indicator is unavailable')
        local original = copy_coord(indicator)
        local view_before = capture_view_state()

        local ok, failure = xpcall(function()
            local inactive = df.coord:new()
            assert.same({x=-30000, y=-30000, z=-30000},
                copy_coord(inactive))

            indicator.x = 101
            indicator.y = 202
            indicator.z = 3
            assert.same({x=101, y=202, z=3}, copy_coord(indicator))
            assert.same(view_before, capture_view_state())

            indicator.x = inactive.x
            indicator.y = inactive.y
            indicator.z = inactive.z
            assert.same({x=-30000, y=-30000, z=-30000},
                copy_coord(indicator))
            assert.same(view_before, capture_view_state())
        end, debug.traceback)

        indicator.x = original.x
        indicator.y = original.y
        indicator.z = original.z
        assert.same(original, copy_coord(indicator),
            'characterization must restore the prior indicator')
        assert.same(view_before, capture_view_state(),
            'characterization must preserve view and follow state')
        assert.is_true(ok, failure)
    end)
end)
