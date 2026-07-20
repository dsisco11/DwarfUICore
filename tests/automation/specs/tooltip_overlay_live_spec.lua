-- Live product contracts for one runner-staged tooltip overlay.

local registration = reqscript('dwarfui/tooltip_registration')
local tooltip = reqscript('dwarfui/tooltip')
local overlay = require('plugins.overlay')

---Returns the exact tooltip overlay staged by the active automation run.
---@return string|nil, table|nil
local function find_staged_overlay()
    for name, entry in pairs(overlay.get_state().db) do
        if name:find('dwarfui_automation_', 1, true) and
                name:find('tooltip_probe', 1, true) then
            return name, entry
        end
    end
    return nil, nil
end

local overlay_name, overlay_entry = find_staged_overlay()
local active_run = assert(dfhack.dwarfui.automation.active_run)
if not overlay_entry then
    if active_run.options.spec == 'tooltip_overlay_live_spec.lua' then
        error('tooltip overlay spec requires -OverlayFixture tooltip_probe')
    end
    return
end

---Returns whether an overlay accepts the live underlying DF viewscreen.
---@param widget table
---@return boolean
local function matches_live_viewscreen(widget)
    local current = dfhack.gui.getDFViewscreen(true)
    if not current then return false end
    for _, focus in ipairs(overlay.normalize_list(widget.viewscreens)) do
        if focus == 'all' or dfhack.gui.matchFocusString(
                overlay.simplify_viewscreen_name(focus), current) then
            return true
        end
    end
    return false
end

---Creates a genuine screen-stack transition so the service renders naturally.
local function refresh_tooltip_service()
    local cover = ds.show_fixture('cover_screen')
    ds.wait_frames(2)
    ds.dismiss(cover)
end

describe('live singleton tooltip overlay eligibility', function()
    local widget = overlay_entry.widget
    local target = widget.tooltip_target
    local original_viewscreens
    local screen

    before_each(function()
        original_viewscreens = widget.viewscreens
        screen = ds.show_fixture('cover_screen')
    end)

    after_each(function()
        widget.viewscreens = original_viewscreens
        overlay.get_state().config[overlay_name].enabled = true
        tooltip.unregister(target)
        if screen and screen:isActive() then ds.dismiss(screen) end
        ds.wait_frames(2)
    end)

    it('uses enabled overlays and rejects focus-mismatched and disabled roots',
            function()
        assert.is_true(overlay.isOverlayEnabled(overlay_name))
        assert.equals(widget, overlay.get_state().db[overlay_name].widget)
        assert.is_true(matches_live_viewscreen(widget))
        ds.wait_until('staged overlay layout', function()
            return target.frame_body and target.frame_body.height > 0
        end)
        ds.move_pointer_to(target, 'top_left')
        tooltip.unregister(target)
        assert.is_true(tooltip.register(target))
        ds.wait_frames(2)

        local diagnostics = registration.get_diagnostics()
        assert.equals(target, diagnostics.target)
        assert.is_true(diagnostics.screen.renderer.visible)
        assert.is_true(diagnostics.screen.renderer.frame.l +
            diagnostics.screen.renderer.frame.w - 1 >
            widget.frame_body.clip_x2)

        widget.viewscreens = 'title'
        refresh_tooltip_service()
        assert.is_nil(registration.get_diagnostics().target)
        assert.is_false(diagnostics.screen.renderer.visible)

        widget.viewscreens = original_viewscreens
        overlay.get_state().config[overlay_name].enabled = false
        refresh_tooltip_service()
        assert.is_nil(registration.get_diagnostics().target)
        assert.is_false(diagnostics.screen.renderer.visible)
    end)
end)
