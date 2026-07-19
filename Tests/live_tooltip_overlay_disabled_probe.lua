-- Live DFHack Phase 9 probe for a disabled registered overlay.

local overlay = require('plugins.overlay')
local registration = reqscript('dwarfui/tooltip_registration')

---Fails the disabled-overlay probe with a named expectation.
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
expect(not overlay.isOverlayEnabled(widget_name),
    'temporary Phase 9 overlay remained enabled')

local widget = entry.widget
local mouse_x = widget.tooltip_target.frame_body.x1
local mouse_y = widget.tooltip_target.frame_body.y1
local diagnostics = registration.get_diagnostics()
local original_get_mouse_pos = dfhack.screen.getMousePos
dfhack.screen.getMousePos = function() return mouse_x, mouse_y end
local render_ok, render_error = xpcall(function()
    diagnostics.screen:onRender()
end, debug.traceback)
dfhack.screen.getMousePos = original_get_mouse_pos
expect(render_ok, render_error)
expect(registration.get_diagnostics().target == nil,
    'disabled overlay control remained eligible')
expect(not diagnostics.screen.renderer.visible,
    'disabled overlay tooltip remained visible')

print(('DwarfUI Phase 9 disabled overlay probe: PASS widget=%s')
    :format(widget_name))
