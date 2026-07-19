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
local mouse_x, mouse_y = dfhack.screen.getMousePos()
expect(mouse_x ~= nil and mouse_y ~= nil,
    'live mouse coordinates are unavailable')
widget.frame = {
    l=math.max(0, mouse_x - 1),
    t=math.max(0, mouse_y - 1),
    w=8,
    h=4,
}
widget:updateLayout()

local diagnostics = registration.get_diagnostics()
expect(diagnostics.renderer_count == 1,
    'overlay registration did not reuse the singleton renderer')
diagnostics.screen:onRender()
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

print(('DwarfUI Phase 9 overlay probe: PASS widget=%s'):format(widget_name))
