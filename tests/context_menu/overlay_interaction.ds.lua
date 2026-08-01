-- Native registered-overlay context-menu interaction acceptance.

local gui = require('gui')
local context_menu = reqscript('dwarfuicore/context_menu/api')
local services = reqscript('dwarfuicore/context_menu/service')

local OVERLAY_SOURCE =
    'tests/context_menu/support/context_menu_overlay_registration.lua'
local PROCESS_STATE_SLOT = 'context_menu_component_probe'

---Returns the live context-menu service.
---@return dwarfui.ContextMenuService
local function service()
    return services.service
end

---Returns the test-owned process observation state.
---@return table
local function probe_state()
    return assert(dfhack.dwarfuicore[PROCESS_STATE_SLOT],
        'context-menu overlay probe state is unavailable')
end

---Returns the active production context-menu screen.
---@return dwarfui.ContextMenuScreen
local function menu_screen()
    local presentation = assert(service()._state.presentation,
        'context-menu presentation is unavailable')
    return assert(presentation.screen,
        'context-menu presentation has no screen')
end

---Feeds one table through the current production viewscreen.
---@param keys table
local function feed_current(keys)
    ds.input(keys)
end

---Returns whether the most recent backing-overlay input contains a key.
---@param key string
---@return boolean
local function last_backing_input_has(key)
    local inputs = probe_state().inputs
    local last = inputs[#inputs]
    return last ~= nil and not not last[key]
end

---Returns the logical DF color encoded by one normalized pen.
---@param pen dfhack.pen
---@return integer
local function pen_foreground(pen)
    return pen.fg + (pen.bold and 8 or 0)
end

---Returns the stable visual properties of one native pen.
---@param pen dfhack.pen
---@return table
local function pen_signature(pen)
    return {
        ch=pen.ch,
        fg=pen_foreground(pen),
        bg=pen.bg,
    }
end

---Returns a comparable snapshot of a native Window frame style.
---@param style table
---@return table
local function frame_style_signature(style)
    return {
        frame=pen_signature(style.frame_pen),
        title=pen_signature(style.title_pen),
        top=pen_signature(style.t_frame_pen),
        left=pen_signature(style.l_frame_pen),
        signature_pen=style.signature_pen,
    }
end

---Opens the widget menu through the native overlay input boundary.
---@param x integer
---@param y integer
---@param keys? table
local function open_widget_menu(x, y, keys)
    assert.is_false(service():is_open())
    ds.await('previous context-menu presentation is dismissed', function()
        return not ds.hasFocus('dfhack/lua/dwarfuicore/context-menu')
    end)
    ds.move_pointer(x, y)
    ds.input(keys or {_MOUSE_R=true})
    ds.await('registered overlay context menu opens', function()
        return service():is_open()
    end)
    ds.await('registered overlay context-menu presentation is current',
        function()
            return ds.hasFocus('dfhack/lua/dwarfuicore/context-menu')
        end)
    ds.await('registered overlay context-menu layout is ready', function()
        local screen = menu_screen()
        return screen.menu_window.frame_rect ~= nil and
            screen.menu_window.menu_list.frame_body ~= nil and
            screen.menu_window.menu_list.choices[1] ~= nil
    end)
end

describe('native registered-overlay context menu', function()
    it('owns actionable tables and delegates unrelated input', function()
        local native_subject
        local target
        local overlay_widget
        local initially_hauling_open
        local initial_pause
        local ok, failure = xpcall(function()
            ds.mountSaveGame('TestWorld 01')
            service():clear_world_state()
            native_subject = ds.mountNativeScreen()
            initially_hauling_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_hauling_open then
                ds.input('LEAVESCREEN')
                ds.await('Hauling closes for context-menu coverage',
                    function() return ds.hasFocus('dwarfmode/Default') end)
            end
            initial_pause = ds.isGamePaused()

            local staged = ds.stage_overlay_registration(
                OVERLAY_SOURCE, 'context_menu_native')
            local overlay_name = assert(staged.registered_names[1],
                'context-menu probe overlay was not registered')
            ds.redraw()
            target = ds.get('context_target', {
                source='overlay',
                overlay=overlay_name,
            }):raw()
            overlay_widget = assert(target.parent_view,
                'context-menu target has no overlay parent')
            assert.is_true(context_menu.register(
                target, overlay_widget.definition))
            ds.await('native context-menu input hook is ready', function()
                local diagnostics = service():get_diagnostics()
                return diagnostics.registrations
                        .widget_registration_count == 1 and
                    diagnostics.hook.native_tracked and
                    diagnostics.hook.handler_installed
            end)
            local body = assert(target.frame_body,
                'context-menu target has no rendered body')
            local target_x = math.floor((body.x1 + body.x2) / 2)
            local target_y = math.floor((body.y1 + body.y2) / 2)
            local state = probe_state()
            state.inputs = {}
            state.selection_count = 0
            state.selection_context = nil

            ds.move_pointer(target_x, target_y)
            ds.input({_MOUSE_R_DOWN=true})
            assert.is_false(service():is_open())
            assert.is_true(last_backing_input_has('_MOUSE_R_DOWN'),
                'down-only input did not remain transparent')

            local opening_sample = service()._sampler:capture()
            local opening_detection =
                service()._detector:detect(opening_sample)
            assert.is_not_nil(opening_detection.candidate,
                ('registered overlay target was not detectable: ' ..
                    'pointer=(%s,%s) expected=(%s,%s) policy=%s')
                    :format(
                        tostring(opening_sample.x),
                        tostring(opening_sample.y),
                        tostring(target_x),
                        tostring(target_y),
                        tostring(target.pointer_policy)))

            local backing_before_open = #state.inputs
            local hook_before_open =
                service():get_diagnostics().hook.dispatch_count
            local shared_style_before =
                frame_style_signature(gui.FRAME_INTERIOR())
            ds.input({_MOUSE_R=true, D_PAUSE=true})
            local opening_diagnostics = service():get_diagnostics()
            assert.is_true(
                opening_diagnostics.hook.dispatch_count > hook_before_open,
                'native opening input did not reach the context-menu hook')
            assert.is_false(opening_diagnostics.disabled,
                opening_diagnostics.last_error)
            ds.await('mixed native right-click opens menu', function()
                return service():is_open()
            end)
            assert.equals(backing_before_open, #state.inputs,
                'owned opening table reached the backing overlay')
            assert.equals(initial_pause, ds.isGamePaused(),
                'coalesced pause escaped an owned opening table')
            local first_menu = menu_screen()
            assert.same({x=target_x, y=target_y},
                first_menu.anchor.screen_position)
            assert.is_equal(target,
                first_menu.session:create_selection_context().source)

            local first_window = first_menu.menu_window
            assert.equals(COLOR_LIGHTCYAN,
                pen_foreground(first_window.frame_style.frame_pen))
            assert.equals(COLOR_BLUE,
                first_window.frame_style.frame_pen.bg)
            assert.equals(COLOR_LIGHTCYAN,
                pen_foreground(first_window.frame_style.title_pen))
            assert.equals(COLOR_BLUE,
                first_window.frame_background.bg)
            assert.equals(COLOR_LIGHTCYAN,
                pen_foreground(
                    first_window.menu_list.choices[1].normal_pen))
            assert.equals(COLOR_BLUE,
                first_window.menu_list.choices[1].normal_pen.bg)
            assert.equals(COLOR_LIGHTRED,
                pen_foreground(
                    first_window.menu_list.choices[2].normal_pen))
            assert.equals(COLOR_BLACK,
                first_window.menu_list.choices[2].normal_pen.bg)
            local shared_style_after =
                frame_style_signature(gui.FRAME_INTERIOR())
            assert.same(shared_style_before, shared_style_after,
                'context-menu colors mutated the shared Window frame style')

            local selection_before = first_window.menu_list.selected
            feed_current{LEAVESCREEN=true, KEYBOARD_CURSOR_DOWN=true}
            assert.is_false(service():is_open())
            assert.equals(selection_before, first_window.menu_list.selected,
                'Escape did not win mixed relevant-key priority')
            assert.equals(0, state.selection_count)

            open_widget_menu(target_x, target_y)
            local second_menu = menu_screen()
            local list = second_menu.menu_window.menu_list
            local backing_before_navigation = #state.inputs
            feed_current{KEYBOARD_CURSOR_DOWN=true}
            assert.equals(2, list.selected)
            assert.equals(backing_before_navigation, #state.inputs,
                'owned list navigation table reached backing UI')
            feed_current{SELECT=true, LEAVESCREEN=true}
            assert.is_false(service():is_open())
            assert.equals(0, state.selection_count,
                'Escape-plus-selection invoked an entry')

            open_widget_menu(target_x, target_y)
            local backing_before_outside = #state.inputs
            ds.move_pointer(0, 0)
            feed_current{_MOUSE_L=true, SELECT=true}
            assert.is_false(service():is_open())
            assert.equals(0, state.selection_count,
                'outside click did not win over coalesced selection')
            assert.equals(backing_before_outside, #state.inputs,
                'outside close reached backing UI')

            open_widget_menu(target_x, target_y)
            local backing_before_second_right = #state.inputs
            feed_current{_MOUSE_R=true, D_PAUSE=true}
            assert.is_false(service():is_open())
            assert.equals(backing_before_second_right, #state.inputs,
                'second right-click reached backing UI')

            open_widget_menu(target_x, target_y)
            local fourth_menu = menu_screen()
            local row = fourth_menu.menu_window.menu_list.frame_body
            ds.move_pointer(
                math.floor((row.clip_x1 + row.clip_x2) / 2),
                row.clip_y1)
            local pointer_x, pointer_y = dfhack.screen.getMousePos()
            local list_x, list_y =
                fourth_menu.menu_window.menu_list:getMousePos()
            assert.is_not_nil(list_x,
                ('pointer (%s, %s) did not enter List clip ' ..
                    '(%s, %s)-(%s, %s)'):format(
                    tostring(pointer_x), tostring(pointer_y),
                    tostring(row.clip_x1), tostring(row.clip_y1),
                    tostring(row.clip_x2), tostring(row.clip_y2)))
            assert.equals(0, list_y)
            local backing_before_select = #state.inputs
            ds.mouseInput(ds.EMouseButton.LEFT)
            assert.is_false(service():is_open())
            assert.equals(1, state.selection_count)
            assert.is_equal(target, state.selection_context.source)
            assert.is_not_nil(state.selection_context.source_root)
            assert.equals(backing_before_select, #state.inputs,
                'mouse selection reached backing UI')

            open_widget_menu(target_x, target_y)
            local backing_before_keyboard = #state.inputs
            feed_current{SELECT=true}
            assert.is_false(service():is_open())
            assert.equals(2, state.selection_count)
            assert.is_equal(target, state.selection_context.source)
            assert.is_not_nil(state.selection_context.source_root)
            assert.equals(backing_before_keyboard, #state.inputs,
                'keyboard selection reached backing UI')

            open_widget_menu(target_x, target_y)
            ds.move_pointer(0, 0)
            local backing_before_wheel = #state.inputs
            feed_current{CONTEXT_SCROLL_DOWN=true}
            assert.is_true(service():is_open())
            assert.equals(backing_before_wheel + 1, #state.inputs)
            assert.is_true(last_backing_input_has('CONTEXT_SCROLL_DOWN'))

            local pause_before = ds.isGamePaused()
            feed_current{D_PAUSE=true}
            assert.is_true(service():is_open())
            assert.equals(not pause_before, ds.isGamePaused(),
                'pause-only input did not pass through')
            assert.is_true(last_backing_input_has('D_PAUSE'))
            feed_current{D_PAUSE=true}
            assert.equals(pause_before, ds.isGamePaused())
            service():close()
            target.visible = false
            ds.redraw()
            local backing_before_hidden = #state.inputs
            ds.move_pointer(target_x, target_y)
            ds.input({_MOUSE_R=true})
            assert.is_false(service():is_open())
            assert.is_true(#state.inputs > backing_before_hidden,
                'hidden target did not delegate its right-click miss')
            target.visible = true
            ds.redraw()
            open_widget_menu(target_x, target_y)
            service():close()
        end, debug.traceback)

        if service():is_open() then service():close() end
        if target then context_menu.unregister(target) end
        service():clear_world_state()
        if initial_pause ~= nil and ds.isGamePaused() ~= initial_pause then
            ds.input('D_PAUSE')
            ds.await('original pause state returns',
                function() return ds.isGamePaused() == initial_pause end)
        end
        if native_subject and initially_hauling_open and
                not ds.hasFocus('dwarfmode/Hauling') then
            ds.input('D_HAULING')
            ds.await('original Hauling screen returns',
                function() return ds.hasFocus('dwarfmode/Hauling') end)
        end
        assert.is_true(ok, failure)
    end)
end)
