-- Live capability and control-tree baseline for DwarfUI's native UI tests.

local overlay = require('plugins.overlay')
local gui = require('gui')
local mood_overlay = reqscript('dwarfui-mood-popover')

local MINECART_OVERLAY =
    'dwarfui-minecart-route-markers.minecart_route_markers'
local MOOD_OVERLAY = 'dwarfui-mood-popover.mood_popover'

---Returns the canonical registered widget for one exact overlay name.
---@param name string
---@return plugins.overlay.OverlayWidget
local function registered_widget(name)
    local entry = assert(overlay.get_state().db[name],
        ('registered overlay is unavailable: %s'):format(name))
    return assert(entry.widget,
        ('registered overlay has no widget: %s'):format(name))
end

---Returns whether the borrowed game screen currently displays Hauling.
---@return boolean
local function hauling_is_open()
    local screen = dfhack.gui.getDFViewscreen(true)
    return screen ~= nil and dfhack.gui.matchFocusString(
        'dwarfmode/Hauling', screen)
end

---Returns the first real registry name created by staged overlay registration.
---@param staged table
---@return string
local function staged_overlay_name(staged)
    assert.is_true(#staged.registered_names > 0,
        'staged tooltip registration did not create an overlay')
    return staged.registered_names[1]
end

---Reattaches DwarfSpec after native input replaces the DF viewscreen.
---@return boolean
local function remount_native_screen()
    ds.unmount()
    ds.mountNativeScreen()
    return true
end

---Verifies the procedural Hauling rows and their production-derived geometry.
---@param widget dwarfui.MinecartRouteMarkersOverlay
local function assert_hauling_row_geometry(widget)
    local hauling = assert(df.global.plotinfo.hauling,
        'plotinfo does not expose Hauling menu state')
    assert.is_truthy(hauling.view_routes,
        'Hauling menu state has no flattened route rows')
    assert.is_truthy(hauling.view_stops,
        'Hauling menu state has no flattened stop rows')
    assert.is_number(hauling.scroll_position,
        'Hauling menu state has no scroll position')

    local layout = assert(widget.layout,
        'registered minecart overlay has no production menu layout')
    local bounds = assert(layout.bounds,
        'production layout did not cache the native Hauling panel bounds')
    assert.is_true(bounds.x1 <= bounds.x2 and bounds.y1 <= bounds.y2,
        'native Hauling panel bounds are invalid')
    assert.equals(bounds.x1, layout.list_x1)
    assert.equals(bounds.x2, layout.list_x2)
    assert.equals(bounds.y1 + 6, layout.first_row_top)
    assert.equals(3, layout.row_height)
    assert.is_true(layout.first_row_top <= bounds.y2,
        'native Hauling route rows begin outside the panel')
end

describe('native DwarfSpec command baseline', function()
    it('captures the live native and registered-overlay control trees', function()
        assert.is_function(ds.mountNativeScreen)
        assert.is_function(ds.get)
        assert.is_function(ds.move_pointer)
        assert.is_function(ds.inspect)
        assert.is_function(ds.capture_view_tree)
        assert.is_function(ds.capture_screen)

        local initially_open = hauling_is_open()
        local mounted = false
        local ok, failure = xpcall(function()
            ds.mountNativeScreen()
            mounted = true

            local pointer_x, pointer_y = ds.move_pointer(0, 0)
            assert.equals(0, pointer_x)
            assert.equals(0, pointer_y)
            assert.is_table(ds.inspect())
            assert.is_table(ds.capture_screen('native_fortress_screen'))
            local fortress_tree = ds.capture_view_tree('native_fortress_tree')
            assert.is_table(fortress_tree)

            -- The seven native top-bar moodlets are procedural screen-cell
            -- regions, so their production layout is the stable selector.
            local moodlets = assert(mood_overlay.TopBarMoodDisplay{}:find_layout(),
                'native fortress top bar has no moodlet screen-cell regions')
            assert.equals(7, #moodlets)
            for _, rect in ipairs(moodlets) do
                assert.is_true(rect.x1 <= rect.x2 and rect.y1 <= rect.y2,
                    'native moodlet region has invalid screen-cell bounds')
            end

            if not initially_open then
                ds.input('D_HAULING')
                remount_native_screen()
                ds.await('native Hauling menu opens', hauling_is_open)
            end
            local hauling_tree = ds.capture_view_tree('native_hauling_tree')
            assert.is_table(hauling_tree)
            assert.is_table(ds.capture_screen('native_hauling_screen'))

            dfhack.run_command('dwarfui reload')
            ds.await('DwarfUI registered overlays are available', function()
                local db = overlay.get_state().db
                return db[MINECART_OVERLAY] and db[MOOD_OVERLAY]
            end)
            ds.redraw()
            ds.await('native Hauling panel bounds are cached', function()
                local widget = registered_widget(MINECART_OVERLAY)
                return widget.layout and widget.layout.bounds
            end)
            assert_hauling_row_geometry(registered_widget(MINECART_OVERLAY))

            local minecart_tree = ds.capture_view_tree('minecart_overlay_tree', {
                source='overlay', overlay=MINECART_OVERLAY,
            })
            assert.is_table(minecart_tree)

            -- Stable registered minecart paths:
            -- stop_action_rail
            -- stop_action_rail/surface/recenter
            local rail = ds.get('stop_action_rail', {
                source='overlay', overlay=MINECART_OVERLAY,
            })
            assert.is_table(rail:inspect())
            local zoom = ds.get('stop_action_rail/surface/recenter', {
                source='overlay', overlay=MINECART_OVERLAY,
            })
            assert.is_table(zoom:inspect())
            local mood_tree = ds.capture_view_tree('mood_overlay_tree', {
                source='overlay', overlay=MOOD_OVERLAY,
            })
            assert.is_table(mood_tree)

            -- Stable registered mood-popover paths:
            -- mood_popover/list
            -- mood_popover/header
            local mood_list = ds.get('mood_popover/list', {
                source='overlay', overlay=MOOD_OVERLAY,
            })
            assert.is_table(mood_list:inspect())
            assert.is_table(mood_list:getFocusList())
            local mood_header = ds.get('mood_popover/header', {
                source='overlay', overlay=MOOD_OVERLAY,
            })
            assert.is_string(mood_header:text())

            -- Real overlay registration rescans replace the borrowed native
            -- viewscreen, so this is the final observation on the mount.
            local staged = ds.stage_overlay_registration(
                'tests/tooltip/support/tooltip_overlay_registration.lua',
                'tooltip_probe')
            local staged_name = staged_overlay_name(staged)
            local tooltip_tree = ds.capture_view_tree('tooltip_overlay_tree', {
                source='overlay', overlay=staged_name,
            })
            assert.is_table(tooltip_tree)

            -- Stable staged tooltip path: tooltip_target.
            local tooltip_target = ds.get('tooltip_target', {
                source='overlay', overlay=staged_name,
            })
            assert.is_table(tooltip_target)
        end, debug.traceback)

        if not initially_open and hauling_is_open() then
            -- Opening Hauling replaces the borrowed native screen. Cleanup
            -- closes that underlying screen directly before releasing the
            -- stale attachment, without introducing a test-owned host.
            gui.simulateInput(dfhack.gui.getDFViewscreen(true), 'LEAVESCREEN')
            ds.wait_frames(1)
            assert.is_false(hauling_is_open(),
                'cleanup did not restore the original native screen')
        end
        if mounted then ds.unmount() end
        assert.is_true(ok, failure)
    end)
end)
