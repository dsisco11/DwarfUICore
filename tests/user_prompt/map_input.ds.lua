-- Live prompt-first map input, callback, and context-menu exclusion coverage.

local guidm = require('gui.dwarfmode')

local OVERLAY_SOURCE =
    'tests/context_menu/support/context_menu_overlay_registration.lua'
local PROCESS_STATE_SLOT = 'context_menu_component_probe'

---Copies one map coordinate into detached Lua values.
---@param pos {x: integer, y: integer, z: integer}
---@return {x: integer, y: integer, z: integer}
local function copy_pos(pos)
    return {x=pos.x, y=pos.y, z=pos.z}
end

---Moves the pointer to a visible map tile and returns its world coordinate.
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
    return copy_pos(assert(dfhack.gui.getMousePos(true),
        'map-panel pointer did not resolve a visible tile'))
end

---Returns one small context-menu definition for exclusion coverage.
---@return table definition
local function definition()
    return {entries={{label='Must remain closed', on_select=function() end}}}
end

describe('live UserPrompt map input', function()
    it('consumes owned boundaries and excludes context-menu opening', function()
        local native_subject
        local target
        local context_handle
        local active_handle
        local prompts
        local context_menu
        local menu_service
        local initially_hauling_open
        local initial_pause
        local ok, failure = xpcall(function()
            ds.mountSaveGame('TestWorld 01')
            native_subject = ds.mountNativeScreen()
            dfhack.run_command('dwarfuicore', 'reload')
            ds.wait_frames(2)
            local services = reqscript('dwarfuicore/services')
            prompts = services.UserPromptServiceProvider:new(
                1, 'test-user-prompt-input')
            context_menu = services.ContextMenuServiceProvider:new(
                1, 'test-user-prompt-input-menu')
            menu_service =
                reqscript('dwarfuicore/context_menu/service').service
            menu_service:clear_world_state()
            initial_pause = ds.isGamePaused()
            initially_hauling_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_hauling_open then
                ds.input('LEAVESCREEN')
                ds.await('Hauling closes for UserPrompt input coverage',
                    function() return ds.hasFocus('dwarfmode/Default') end)
            end

            local staged = ds.stage_overlay_registration(
                OVERLAY_SOURCE, 'context_menu_map')
            local overlay_name = assert(staged.registered_names[1],
                'input probe overlay was not registered')
            ds.redraw()
            target = ds.get('context_target', {
                source='overlay', overlay=overlay_name,
            }):raw()
            assert(target.parent_view,
                'input probe overlay owner is unavailable')
            context_handle = context_menu:register(target, definition())
            local probe = assert(dfhack.dwarfuicore[PROCESS_STATE_SLOT],
                'backing input probe is unavailable')

            local body = assert(target.frame_body,
                'context target has no rendered bounds')
            ds.move_pointer(
                math.floor((body.x1 + body.x2) / 2),
                math.floor((body.y1 + body.y2) / 2))
            ds.input({_MOUSE_R=true})
            ds.await('preexisting context menu opens', function()
                return menu_service:is_open()
            end)

            local selected = {}
            local cancelled = 0
            active_handle = prompts:prompt_map_location{
                title='Choose tile',
                message='Left release completes.',
                on_select=function(pos) table.insert(selected, pos) end,
                on_cancel=function() cancelled = cancelled + 1 end,
            }
            assert.is_false(menu_service:is_open(),
                'prompt activation did not close the existing menu')
            probe.inputs = {}

            ds.input({_MOUSE_L_DOWN=true})
            assert.is_true(prompts:is_active(active_handle))
            assert.same({}, selected)
            assert.equals(0, cancelled)
            assert.equals(0, #probe.inputs,
                'left down leaked to the backing overlay')

            local expected = visible_map_tile()
            ds.input({_MOUSE_L=true})
            assert.is_false(prompts:is_active(active_handle))
            active_handle = nil
            assert.equals(1, #selected)
            assert.same(expected, selected[1])
            assert.equals(0, cancelled)
            assert.equals(0, #probe.inputs,
                'left release leaked to the backing overlay')

            ds.move_pointer(
                math.floor((body.x1 + body.x2) / 2),
                math.floor((body.y1 + body.y2) / 2))
            active_handle = prompts:prompt_map_location{
                title='Cancel tile', message='Right release cancels.',
                on_select=function() error('unexpected selection') end,
                on_cancel=function() cancelled = cancelled + 1 end,
            }
            ds.input({_MOUSE_R_DOWN=true})
            assert.is_true(prompts:is_active(active_handle))
            assert.equals(0, #probe.inputs,
                'right down leaked to the backing overlay')
            ds.input({_MOUSE_R=true})
            assert.is_false(prompts:is_active(active_handle))
            active_handle = nil
            assert.equals(1, cancelled)
            assert.is_false(menu_service:is_open(),
                'right-click cancellation opened a context menu')
            assert.equals(0, #probe.inputs,
                'right release leaked to the backing overlay')

            active_handle = prompts:prompt_map_location{
                title='Escape tile', message='Escape cancels.',
                on_select=function() error('unexpected selection') end,
                on_cancel=function() cancelled = cancelled + 1 end,
            }
            ds.input('LEAVESCREEN')
            assert.is_false(prompts:is_active(active_handle))
            active_handle = nil
            assert.equals(2, cancelled)
            assert.equals(0, #probe.inputs,
                'Escape leaked to the backing overlay')

            active_handle = prompts:prompt_map_location{
                title='Delegate', message='Other input delegates.',
                on_select=function() end,
                on_cancel=function() cancelled = cancelled + 1 end,
            }
            ds.input('D_PAUSE')
            assert.is_true(prompts:is_active(active_handle))
            assert.equals(1, #probe.inputs,
                'unowned input did not reach the backing overlay once')
            assert.is_true(probe.inputs[1].D_PAUSE)
            assert.is_true(prompts:cancel(active_handle))
            active_handle = nil
            assert.equals(3, cancelled)
        end, debug.traceback)

        if active_handle then pcall(function() prompts:cancel(active_handle) end) end
        if menu_service and menu_service:is_open() then
            menu_service:close('test-cleanup')
        end
        if context_handle and target then pcall(function()
            context_menu:unregister(target)
        end) end
        if menu_service then menu_service:clear_world_state() end
        if initial_pause ~= nil and ds.isGamePaused() ~= initial_pause then
            ds.setGamePaused(initial_pause)
        end
        if native_subject and initially_hauling_open and
                not ds.hasFocus('dwarfmode/Hauling') then
            ds.input('D_HAULING')
            ds.await('Hauling returns after UserPrompt input coverage',
                function() return ds.hasFocus('dwarfmode/Hauling') end)
        end
        assert.is_true(ok, failure)
    end)
end)
