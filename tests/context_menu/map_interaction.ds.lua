-- Real visible-map-tile context-menu projection and routing acceptance.

local gui = require('gui')
local guidm = require('gui.dwarfmode')
local context_menu = reqscript('dwarfuicore/context_menu/api')
local map_projection = reqscript('dwarfuicore/map_projection')
local services = reqscript('dwarfuicore/context_menu/service')
local DetectionKind =
    reqscript('dwarfuicore/context_menu/target_detector').
        ContextMenuDetectionKind

local OVERLAY_SOURCE =
    'tests/context_menu/support/context_menu_overlay_registration.lua'
local PROCESS_STATE_SLOT = 'context_menu_component_probe'

---Returns the active production context-menu screen.
---@return dwarfui.ContextMenuScreen
local function menu_screen()
    return assert(services.service._state.presentation.screen,
        'context-menu screen is unavailable')
end

---Feeds one input table through the current viewscreen.
---@param keys table
local function feed_current(keys)
    gui.simulateInput(dfhack.gui.getCurViewscreen(), keys)
    ds.redraw()
end

---Copies one exact coordinate.
---@param pos {x: integer, y: integer, z: integer}
---@return {x: integer, y: integer, z: integer}
local function copy_pos(pos)
    return {x=pos.x, y=pos.y, z=pos.z}
end

---Returns the logical DF color encoded by one normalized pen.
---@param pen dfhack.pen
---@return integer
local function pen_foreground(pen)
    return pen.fg + (pen.bold and 8 or 0)
end

---Resolves the world tile beneath a real pointer position in the map panel.
---@return {x: integer, y: integer, z: integer}
local function visible_map_tile()
    local layout = assert(guidm.getPanelLayout(),
        'dwarfmode panel layout is unavailable')
    local viewport = assert(guidm.Viewport.get(layout),
        'dwarfmode viewport is unavailable')
    local map = assert(layout.map, 'dwarfmode map panel is unavailable')
    ds.move_pointer(
        map.x1 + math.floor(viewport.width * 3 / 4),
        map.y1 + math.floor(viewport.height / 2))
    ds.redraw()
    return copy_pos(assert(dfhack.gui.getMousePos(true),
        'map-panel pointer did not resolve a visible world tile'))
end

---Returns one long definition with deterministic color fallback.
---@param callback function
---@return table
local function long_definition(callback)
    local entries = {}
    local _, screen_height = dfhack.screen.getWindowSize()
    for index=1,screen_height + 8 do
        entries[index] = {
            label=('Map action %02d with a deliberately long label'):format(
                index),
            on_select=callback,
        }
    end
    entries[2].fg = COLOR_LIGHTGREEN
    entries[2].bg = COLOR_RED
    return {
        title='Visible map tile actions with a long title',
        fg=COLOR_YELLOW,
        bg=COLOR_BLUE,
        entries=entries,
    }
end

---Opens the current map registration at its real world tile.
---@param pos {x: integer, y: integer, z: integer}
local function open_map_menu(pos)
    assert.is_false(services.service:is_open())
    ds.move_pointer(pos, ds.EPointerSpace.WORLD_TILE, {recenter=false})
    ds.input({_MOUSE_R=true})
    ds.await('exact map-tile context menu opens', function()
        return services.service:is_open()
    end)
end

describe('native exact-map-tile context menu', function()
    it('tracks the viewport and preserves map input routing', function()
        local native_subject
        local owner
        local handle
        local initially_hauling_open
        local initial_pause
        local initial_view
        local initial_viewscreens
        local selected = 0
        local selected_context
        local ok, failure = xpcall(function()
            ds.mountSaveGame('TestWorld 01')
            services.service:clear_world_state()
            native_subject = ds.mountNativeScreen()
            initially_hauling_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_hauling_open then
                ds.input('LEAVESCREEN')
                ds.await('Hauling closes for map context-menu coverage',
                    function() return ds.hasFocus('dwarfmode/Default') end)
            end
            initial_pause = ds.isGamePaused()
            initial_view = copy_pos(ds.getViewPos(
                ds.EScreenOrigin.TOP_LEFT))
            local staged = ds.stage_overlay_registration(
                OVERLAY_SOURCE, 'context_menu_map')
            local overlay_name = assert(staged.registered_names[1],
                'context-menu map owner overlay was not registered')
            ds.redraw()
            local target = ds.get('context_target', {
                source='overlay',
                overlay=overlay_name,
            }):raw()
            owner = assert(target.parent_view,
                'map registration owner overlay is unavailable')
            initial_viewscreens = owner.viewscreens
            local probe = assert(dfhack.dwarfuicore[PROCESS_STATE_SLOT])
            probe.inputs = {}

            local pos = visible_map_tile()
            local initial_projection = map_projection.project_visible(pos)
            local initial_pointer_x, initial_pointer_y =
                dfhack.screen.getMousePos()
            assert.is_not_nil(initial_projection,
                ('map-panel pointer resolved offscreen tile ' ..
                    'pos=%s,%s,%s pointer=%s,%s'):format(
                        tostring(pos.x), tostring(pos.y), tostring(pos.z),
                        tostring(initial_pointer_x),
                        tostring(initial_pointer_y)))
            handle = context_menu.register_map_tile{
                owner=owner,
                pos=pos,
                definition=long_definition(function(context)
                    selected = selected + 1
                    selected_context = context
                end),
            }
            ds.await('native map context-menu input hook is ready', function()
                local diagnostics =
                    services.service:get_diagnostics()
                return diagnostics.registrations
                        .map_registration_count == 1 and
                    diagnostics.hook.native_tracked and
                    diagnostics.hook.handler_installed
            end)
            ds.move_pointer(pos, ds.EPointerSpace.WORLD_TILE,
                {recenter=false})
            local screen_x, screen_y = dfhack.screen.getMousePos()
            local sample = services.service._sampler:capture()
            assert.same(pos, {
                x=sample.map_x,
                y=sample.map_y,
                z=sample.map_z,
            }, 'world pointer sampler did not resolve the staged tile')
            local detection = services.service._detector:detect(sample)
            assert.equals(DetectionKind.TARGET, detection.kind,
                'registered map tile did not win pointer arbitration')
            assert.is_equal(handle, detection.candidate.source,
                'registered map handle did not win tile precedence')
            local backing_before_open = #probe.inputs
            local hook_before_open =
                services.service:get_diagnostics().hook
            ds.input({_MOUSE_R=true, _MOUSE_R_DOWN=true})
            local hook_after_open =
                services.service:get_diagnostics().hook
            assert.is_true(
                hook_after_open.dispatch_count >
                    hook_before_open.dispatch_count,
                'native map input did not reach the opening hook')
            assert.equals(
                hook_before_open.handled_count + 1,
                hook_after_open.handled_count,
                'native map opening hook did not own the target')
            local opening = services.service:get_diagnostics()
            assert.is_true(services.service:is_open(),
                ('native map menu did not open synchronously: ' ..
                    'opens=%s closes=%s disabled=%s error=%s'):format(
                        tostring(opening.open_count),
                        tostring(opening.close_count),
                        tostring(opening.disabled),
                        tostring(opening.last_error)))
            assert.equals(backing_before_open, #probe.inputs,
                'owned map right-click reached backing overlay input')
            assert.is_true(
                ds.hasFocus('dfhack/lua/dwarfuicore/context-menu'),
                'opened map menu did not own context-menu focus')
            local first = menu_screen()
            assert.same(pos, first.anchor.map_position)
            assert.same({x=screen_x, y=screen_y},
                first.anchor.screen_position)
            assert.is_equal(handle,
                first.session:create_selection_context().source)
            assert.is_equal(owner,
                first.session:create_selection_context().owner)

            local window = first.menu_window
            assert.equals(COLOR_YELLOW,
                pen_foreground(window.frame_style.frame_pen))
            assert.equals(COLOR_BLUE,
                window.frame_background.bg)
            assert.equals(COLOR_YELLOW,
                pen_foreground(
                    window.menu_list.choices[1].normal_pen))
            assert.equals(COLOR_BLUE,
                window.menu_list.choices[1].normal_pen.bg)
            assert.equals(COLOR_LIGHTGREEN,
                pen_foreground(
                    window.menu_list.choices[2].normal_pen))
            assert.equals(COLOR_RED,
                window.menu_list.choices[2].normal_pen.bg)
            assert.is_true(#window.definition.entries >
                window.menu_list.page_size)

            local anchor_before = assert(first:resolve_anchor(),
                'initial map-menu anchor is unavailable')
            local view_before = copy_pos(ds.getViewPos(
                ds.EScreenOrigin.TOP_LEFT))
            local backing_before_move = #probe.inputs
            feed_current{CURSOR_RIGHT=true}
            ds.await('delegated map movement changes the viewport', function()
                local current = ds.getViewPos(ds.EScreenOrigin.TOP_LEFT)
                return current.x ~= view_before.x or current.y ~= view_before.y
            end)
            assert.is_true(services.service:is_open())
            assert.equals(backing_before_move + 1, #probe.inputs,
                'map movement table did not reach backing overlay once')
            assert.is_true(probe.inputs[#probe.inputs].CURSOR_RIGHT)
            ds.redraw()
            local anchor_after = assert(first:resolve_anchor(),
                'moved map-menu anchor is unavailable')
            assert.is_false(anchor_after.x == anchor_before.x and
                    anchor_after.y == anchor_before.y,
                'map menu anchor did not reproject after camera movement')
            assert.same(anchor_after, window.anchor,
                'map menu window did not adopt its reprojected anchor')

            local backing_before_navigation = #probe.inputs
            local selected_before = window.menu_list.selected
            feed_current{KEYBOARD_CURSOR_DOWN=true, D_PAUSE=true}
            assert.equals(selected_before + 1, window.menu_list.selected)
            assert.equals(backing_before_navigation, #probe.inputs,
                'list navigation leaked to map input')

            local list_body = window.menu_list.frame_body
            ds.move_pointer(list_body.x1 + 1, list_body.y2)
            local page_before = window.menu_list.page_top
            for _=1,window.menu_list.page_size + 2 do
                feed_current{STANDARDSCROLL_DOWN=true}
            end
            assert.is_true(window.menu_list.page_top > page_before,
                'long production List did not scroll')

            ds.move_pointer(0, 0)
            local backing_before_outside_wheel = #probe.inputs
            feed_current{CONTEXT_SCROLL_DOWN=true}
            assert.equals(backing_before_outside_wheel + 1, #probe.inputs)
            assert.is_true(
                probe.inputs[#probe.inputs].CONTEXT_SCROLL_DOWN)
            assert.is_true(services.service:is_open())

            local pause_before = ds.isGamePaused()
            feed_current{D_PAUSE=true}
            assert.equals(not pause_before, ds.isGamePaused())
            assert.is_true(services.service:is_open())
            feed_current{D_PAUSE=true}
            assert.equals(pause_before, ds.isGamePaused())
            local visible_row = window.menu_list.frame_body
            ds.move_pointer(visible_row.x1 + 1, visible_row.y1)
            local backing_before_selection = #probe.inputs
            feed_current{_MOUSE_L=true}
            assert.is_false(services.service:is_open())
            assert.equals(1, selected)
            assert.is_equal(handle, selected_context.source)
            assert.is_equal(owner, selected_context.owner)
            assert.same(pos, selected_context.map_position)
            assert.equals(backing_before_selection, #probe.inputs)

            open_map_menu(pos)
            local z_before = df.global.window_z
            local off_z = z_before + 1 < df.global.world.map.z_count and
                z_before + 1 or z_before - 1
            assert.is_true(off_z >= 0 and off_z ~= z_before,
                'prepared world needs an adjacent z-level')
            ds.setViewPos({
                x=df.global.window_x,
                y=df.global.window_y,
                z=off_z,
            }, ds.EScreenOrigin.TOP_LEFT)
            ds.redraw()
            ds.await('z-level invalidation closes map menu', function()
                return not services.service:is_open()
            end)
            ds.setViewPos({
                x=df.global.window_x,
                y=df.global.window_y,
                z=pos.z,
            }, ds.EScreenOrigin.TOP_LEFT)
            ds.redraw()

            open_map_menu(pos)
            local map = df.global.world.map
            local far_view = {
                x=pos.x < math.floor(map.x_count / 2) and
                    map.x_count - 1 or 0,
                y=pos.y < math.floor(map.y_count / 2) and
                    map.y_count - 1 or 0,
                z=pos.z,
            }
            ds.setViewPos(far_view, ds.EScreenOrigin.TOP_LEFT)
            ds.redraw()
            ds.await('offscreen invalidation closes map menu', function()
                return not services.service:is_open()
            end)
            ds.setViewPos(initial_view, ds.EScreenOrigin.TOP_LEFT)
            ds.redraw()

            owner.visible = false
            ds.move_pointer(pos, ds.EPointerSpace.WORLD_TILE,
                {recenter=false})
            ds.input({_MOUSE_R=true})
            assert.is_false(services.service:is_open())
            owner.visible = true
            owner.active = false
            ds.redraw()
            ds.input({_MOUSE_R=true})
            assert.is_false(services.service:is_open())
            owner.active = true
            owner.viewscreens = 'title'
            ds.redraw()
            ds.input({_MOUSE_R=true})
            assert.is_false(services.service:is_open())
            owner.viewscreens = initial_viewscreens
            ds.redraw()
            open_map_menu(pos)

            owner.visible = false
            ds.redraw()
            ds.await('hidden map owner closes retained menu', function()
                return not services.service:is_open()
            end)
            owner.visible = true
            ds.redraw()
            open_map_menu(pos)
            services.service:close()
        end, debug.traceback)

        if services.service:is_open() then services.service:close() end
        if handle then context_menu.unregister_map_tile(handle) end
        if owner then
            owner.visible = true
            owner.active = true
            owner.viewscreens = initial_viewscreens
        end
        services.service:clear_world_state()
        if initial_view then
            ds.setViewPos(initial_view, ds.EScreenOrigin.TOP_LEFT)
            ds.redraw()
            assert.same(initial_view, copy_pos(ds.getViewPos(
                ds.EScreenOrigin.TOP_LEFT)),
                'map context-menu fixture did not restore its initial viewport')
        end
        if initial_pause ~= nil and ds.isGamePaused() ~= initial_pause then
            ds.setGamePaused(initial_pause)
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
