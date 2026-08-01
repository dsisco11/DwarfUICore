-- Live characterization for process-wide pointer timeout feasibility.

local gui = require('gui')

---@class tests.TooltipPointerSchedulerScreen: gui.ZScreen
local TooltipPointerSchedulerScreen = defclass(nil, gui.ZScreen)
TooltipPointerSchedulerScreen.ATTRS{
    initial_pause=false,
    pass_mouse_clicks=true,
}

---Records and consumes left-click input.
---@param keys table
---@return boolean
function TooltipPointerSchedulerScreen:onInput(keys)
    if keys._MOUSE_L then
        self.consumed_mouse_inputs =
            (self.consumed_mouse_inputs or 0) + 1
        return true
    end
    return TooltipPointerSchedulerScreen.super.onInput(self, keys)
end

---Copies an array without retaining its source table.
---@param values any[]
---@return any[]
local function copy_array(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    return result
end

---Waits until a requested number of global frame callbacks have elapsed.
---@param count integer
local function await_frames(count)
    local elapsed = 0
    local function advance()
        elapsed = elapsed + 1
        if elapsed < count then
            dfhack.timeout(1, 'frames', advance)
        end
    end
    dfhack.timeout(1, 'frames', advance)
    ds.await(('global timeout advances %d frames'):format(count), function()
        return elapsed == count
    end)
end

describe('tooltip pointer scheduler feasibility', function()
    it('identifies the presented native DwarfSpec root without a renderer',
            function()
        local root = ds.mountNativeScreen()
        local native = assert(dfhack.gui.getDFViewscreen(true),
            'native DF viewscreen is unavailable')

        assert.is_equal(native.widgets, root:raw())
        assert.is_equal(native, dfhack.gui.getDFViewscreen(true))

    end)

    it('samples independently of pause and consumed mouse input', function()
        local root
        local screen
        local running = true
        local callback_count = 0
        local samples = {}
        local ok, failure = xpcall(function()
            root = ds.mount(TooltipPointerSchedulerScreen, {
                initial_pause=true,
            })
            screen = root:raw()
            assert.is_true(df.global.pause_state)

            local function sample_pointer()
                if not running then return end
                callback_count = callback_count + 1
                local x, y = dfhack.screen.getMousePos()
                samples[callback_count] = {x=x, y=y}
                dfhack.timeout(1, 'frames', sample_pointer)
            end
            dfhack.timeout(1, 'frames', sample_pointer)

            ds.await('recurring global pointer callback starts', function()
                return callback_count >= 2
            end)

            local focus_before = copy_array(root:getFocusList())
            local viewscreen_before = dfhack.gui.getCurViewscreen(true)
            local pause_before = df.global.pause_state
            local count_before_move = callback_count

            local expected_x, expected_y = ds.move_pointer(7, 5)
            ds.await('paused callback observes pointer movement', function()
                local sample = samples[callback_count]
                return callback_count > count_before_move and sample and
                    sample.x == expected_x and sample.y == expected_y
            end)

            local count_before_input = callback_count
            ds.mouseInput(ds.EMouseButton.LEFT)
            assert.equals(1, screen.consumed_mouse_inputs)
            ds.await('callback continues after consumed mouse input',
                function()
                    return callback_count > count_before_input
                end)

            assert.same(focus_before, root:getFocusList())
            assert.is_equal(viewscreen_before,
                dfhack.gui.getCurViewscreen(true))
            assert.equals(pause_before, df.global.pause_state)

            running = false
            local stopped_at = callback_count
            await_frames(3)
            assert.equals(stopped_at, callback_count)
        end, debug.traceback)

        running = false
        assert.is_true(ok, failure)
    end)
end)
