-- Live final-render, tooltip suppression, and native indicator integration.

local guidm = require('gui.dwarfmode')

local TOOLTIP_SOURCE =
    'tests/tooltip/support/tooltip_overlay_registration.lua'

---Copies one native coordinate into detached Lua values.
---@param value df.coord
---@return {x: integer, y: integer, z: integer}
local function copy_coord(value)
    return {x=value.x, y=value.y, z=value.z}
end

---Returns the character currently rendered in one screen cell.
---@param x integer
---@param y integer
---@return string
local function read_character(x, y)
    local pen = dfhack.screen.readTile(x, y)
    if not pen or pen.ch == nil then return '' end
    if type(pen.ch) == 'number' then return string.char(pen.ch) end
    return pen.ch
end

---Reads one rendered rectangle as one string per row.
---@param frame {l: integer, t: integer, w: integer, h: integer}
---@return string[] rows
local function read_rows(frame)
    local rows = {}
    for y=frame.t,frame.t + frame.h - 1 do
        local chars = {}
        for x=frame.l,frame.l + frame.w - 1 do
            table.insert(chars, read_character(x, y))
        end
        table.insert(rows, table.concat(chars))
    end
    return rows
end

---Returns whether any row contains one literal text fragment.
---@param rows string[]
---@param expected string
---@return boolean found
local function rows_contain(rows, expected)
    for _, row in ipairs(rows) do
        if row:find(expected, 1, true) then return true end
    end
    return false
end

---Moves the pointer to a visible map tile and returns that coordinate.
---@return {x: integer, y: integer, z: integer}
local function visible_map_tile()
    local layout = assert(guidm.getPanelLayout(),
        'dwarfmode panel layout is unavailable')
    local viewport = assert(guidm.Viewport.get(layout),
        'dwarfmode viewport is unavailable')
    local map = assert(layout.map, 'dwarfmode map panel is unavailable')
    ds.move_pointer(
        map.x1 + math.floor(viewport.width * 2 / 3),
        map.y1 + math.floor(viewport.height / 2))
    ds.redraw()
    return copy_coord(assert(dfhack.gui.getMousePos(true),
        'map-panel pointer did not resolve a visible tile'))
end

---Moves the pointer to one visible screen cell outside the map panel.
local function move_pointer_off_map()
    local layout = assert(guidm.getPanelLayout(),
        'dwarfmode panel layout is unavailable')
    local viewport = assert(guidm.Viewport.get(layout),
        'dwarfmode viewport is unavailable')
    local map = assert(layout.map, 'dwarfmode map panel is unavailable')
    local width, height = dfhack.screen.getWindowSize()
    for _, candidate in ipairs{
            {x=0, y=0},
            {x=width - 1, y=0},
            {x=0, y=height - 1},
            {x=width - 1, y=height - 1},
        } do
        if candidate.x < map.x1 or
                candidate.x >= map.x1 + viewport.width or
                candidate.y < map.y1 or
                candidate.y >= map.y1 + viewport.height then
            ds.move_pointer(candidate.x, candidate.y)
            ds.redraw()
            return
        end
    end
    error('dwarfmode map panel leaves no screen cell for off-map coverage')
end

describe('live UserPrompt final rendering', function()
    it('renders attribution and content while suppressing tooltips', function()
        local native_subject
        local tooltip_target
        local prompt_handle
        local initially_hauling_open
        local indicator
        local original_indicator
        local tooltip_x
        local tooltip_y
        local prompt_api
        local tooltip_api
        local prompt_service
        local prompt_renderer
        local presenter
        local ok, failure = xpcall(function()
            ds.mountSaveGame('TestWorld 01')
            native_subject = ds.mountNativeScreen()
            dfhack.run_command('dwarfuicore', 'reload')
            ds.wait_frames(2)
            local services = reqscript('dwarfuicore/services')
            prompt_api = services.UserPromptServiceProvider:new(
                1, 'test-user-prompt-render')
            tooltip_api = services.TooltipServiceProvider:new(
                1, 'test-tooltip-overlay')
            prompt_service =
                reqscript('dwarfuicore/user_prompt/service').service
            prompt_renderer =
                reqscript('dwarfuicore/user_prompt/renderer')
            presenter =
                reqscript('dwarfuicore/tooltip/runtime').presenter
            initially_hauling_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_hauling_open then
                ds.input('LEAVESCREEN')
                ds.await('Hauling closes for prompt render coverage',
                    function() return ds.hasFocus('dwarfmode/Default') end)
            end

            indicator = assert(
                df.global.game.main_interface.recenter_indicator_m,
                'native recenter indicator is unavailable')
            original_indicator = copy_coord(indicator)

            local staged = ds.stage_overlay_registration(
                TOOLTIP_SOURCE, 'tooltip_probe')
            local overlay_name = assert(staged.registered_names[1],
                'tooltip probe overlay was not registered')
            ds.redraw()
            tooltip_target = ds.get('tooltip_target', {
                source='overlay', overlay=overlay_name,
            }):raw()
            local body = assert(tooltip_target.frame_body,
                'tooltip target has no rendered bounds')
            tooltip_x = math.floor((body.x1 + body.x2) / 2)
            tooltip_y = math.floor((body.y1 + body.y2) / 2)
            ds.move_pointer(tooltip_x, tooltip_y)
            ds.redraw()
            ds.await('ordinary tooltip intent is selected', function()
                return ds.tooltip_state().intent ~= nil
            end)
            local tooltip_render_before = presenter:get_diagnostics().render_count

            prompt_handle = prompt_api:prompt_map_location{
                title='PromptTitle',
                message='PromptMessage',
                on_select=function() end,
                on_cancel=function() end,
            }
            ds.redraw()
            ds.await('authoritative prompt presentation renders', function()
                local diagnostics = presenter:get_diagnostics()
                return diagnostics.authoritative_intent_active and
                    diagnostics.tooltip_suppressed and
                    diagnostics.authoritative_render_count > 0
            end)
            assert.is_true(prompt_api:is_active(prompt_handle))
            move_pointer_off_map()
            ds.await('off-map pointer hides the native indicator', function()
                return copy_coord(indicator).x == -30000 and
                    copy_coord(indicator).y == -30000 and
                    copy_coord(indicator).z == -30000
            end)
            assert.same({x=-30000, y=-30000, z=-30000},
                copy_coord(indicator),
                'off-map pointer did not hide the native indicator')

            local expected_map = visible_map_tile()
            ds.redraw()
            ds.await('native indicator follows the map pointer', function()
                return copy_coord(indicator).x == expected_map.x and
                    copy_coord(indicator).y == expected_map.y and
                    copy_coord(indicator).z == expected_map.z
            end)

            local pending = assert(prompt_service._state.pending,
                'accepted prompt has no pending request')
            local pointer_x, pointer_y = dfhack.screen.getMousePos()
            local width, height = dfhack.screen.getWindowSize()
            local layout = prompt_renderer.calculate_layout(
                pending.request, pointer_x, pointer_y, width, height)
            local rows = read_rows(layout.frame)
            assert.is_truthy(rows[1]:find(
                'test-user-prompt-render', 1, true),
                'owning namespace was not rendered in the top border: ' ..
                    table.concat(rows, ' | '))
            assert.is_true(rows_contain(rows, 'PromptTitle'),
                'consumer title was not rendered inside the prompt')
            assert.is_true(rows_contain(rows, 'PromptMessage'),
                'consumer message was not rendered inside the prompt')

            ds.move_pointer(tooltip_x, tooltip_y)
            ds.redraw()
            ds.await('ordinary tooltip intent remains selected underneath',
                function()
                    local diagnostics = presenter:get_diagnostics()
                    return ds.tooltip_state().intent ~= nil and
                        diagnostics.authoritative_intent_active and
                        diagnostics.tooltip_suppressed
                end)
            assert.is_true(prompt_api:cancel(prompt_handle))
            prompt_handle = nil
            ds.redraw()
            ds.await('ordinary tooltip presentation resumes', function()
                local diagnostics = presenter:get_diagnostics()
                return not diagnostics.authoritative_intent_active and
                    not diagnostics.tooltip_suppressed and
                    diagnostics.render_count > tooltip_render_before
            end)
            assert.same(original_indicator, copy_coord(indicator),
                'prompt cleanup did not restore the prior indicator')
        end, debug.traceback)

        if prompt_handle and prompt_api then pcall(function()
            prompt_api:cancel(prompt_handle)
        end) end
        if tooltip_target and tooltip_api then pcall(function()
            tooltip_api:unregister(tooltip_target)
        end) end
        if indicator and original_indicator then
            indicator.x = original_indicator.x
            indicator.y = original_indicator.y
            indicator.z = original_indicator.z
        end
        if native_subject and initially_hauling_open and
                not ds.hasFocus('dwarfmode/Hauling') then
            ds.input('D_HAULING')
            ds.await('Hauling returns after prompt render coverage',
                function() return ds.hasFocus('dwarfmode/Hauling') end)
        end
        assert.is_true(ok, failure)
    end)
end)
