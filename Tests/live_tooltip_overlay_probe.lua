-- Live DFHack Phase 9 probe for an enabled temporary overlay.

local overlay = require('plugins.overlay')
local registration = reqscript('dwarfui/tooltip_registration')

---Fails the live overlay probe with a named expectation.
---@param condition boolean
---@param message string
local function expect(condition, message)
    if not condition then error(message, 2) end
end

local widget_name
local entry
for name, candidate in pairs(overlay.get_state().db) do
    if name:find('dwarfui_phase9', 1, true) or
            name:find('dwarfui-phase9', 1, true) then
        widget_name = name
        entry = candidate
        break
    end
end
expect(entry ~= nil, 'temporary Phase 9 overlay was not discovered')
expect(overlay.isOverlayEnabled(widget_name),
    'temporary Phase 9 overlay was not enabled')

local widget = entry.widget
widget.frame = {
    l=1,
    t=1,
    w=8,
    h=4,
}
widget:updateLayout()
local mouse_x = widget.tooltip_target.frame_body.x1
local mouse_y = widget.tooltip_target.frame_body.y1

---Runs one service render with a controlled live pointer position.
---@param screen table
local function render_at_target(screen)
    local original_get_mouse_pos = dfhack.screen.getMousePos
    dfhack.screen.getMousePos = function() return mouse_x, mouse_y end
    local render_ok, render_error = xpcall(function()
        screen:onRender()
    end, debug.traceback)
    dfhack.screen.getMousePos = original_get_mouse_pos
    expect(render_ok, render_error)
end

local diagnostics = registration.get_diagnostics()
expect(diagnostics.renderer_count == 1,
    'overlay registration did not reuse the singleton renderer')
render_at_target(diagnostics.screen)
diagnostics = registration.get_diagnostics()
expect(diagnostics.target == widget.tooltip_target,
    'enabled overlay control was not selected')
expect(diagnostics.screen.renderer.visible,
    'overlay tooltip did not become visible')
expect(diagnostics.screen.renderer.frame_parent_rect ==
    diagnostics.screen.frame_parent_rect,
    'overlay tooltip did not use full-screen layout')
expect(diagnostics.screen.renderer.frame.l +
    diagnostics.screen.renderer.frame.w - 1 >
    widget.frame_body.clip_x2,
    'overlay tooltip did not escape the clipped overlay root')

local original_viewscreens = widget.viewscreens
widget.viewscreens = 'title'
render_at_target(diagnostics.screen)
expect(registration.get_diagnostics().target == nil,
    'focus-mismatched overlay remained eligible')
expect(not diagnostics.screen.renderer.visible,
    'focus-mismatched overlay tooltip remained visible')
widget.viewscreens = original_viewscreens
render_at_target(diagnostics.screen)
expect(registration.get_diagnostics().target == widget.tooltip_target,
    'overlay did not retarget after restoring its focus declaration')

print(('DwarfUI Phase 9 overlay probe: PASS widget=%s'):format(widget_name))
