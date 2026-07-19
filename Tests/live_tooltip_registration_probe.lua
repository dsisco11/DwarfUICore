-- Live DFHack Phase 9 probe for the singleton screen service.

local gui = require('gui')
local widgets = require('gui.widgets')
local tooltip = reqscript('dwarfui/tooltip')
local registration = reqscript('dwarfui/tooltip_registration')

---@class tests.LiveTooltipProbeScreen: gui.ZScreen
local LiveTooltipProbeScreen = defclass(nil, gui.ZScreen)
LiveTooltipProbeScreen.ATTRS{
    initial_pause=false,
    pass_mouse_clicks=true,
}

---Builds one full-screen dynamic tooltip target.
function LiveTooltipProbeScreen:init()
    self.target = widgets.Label{
        frame={l=0, t=0, r=0, b=0},
        text='Live tooltip target',
        tooltip='Live static tooltip',
    }
    ---Updates live tooltip text from pointer-local coordinates.
    self.target.on_pointer_update = function(target, x, y)
        target.tooltip = ('Live dynamic tooltip %d,%d'):format(x, y)
    end
    self:addviews{self.target}
end

---@class tests.LiveTooltipCoverScreen: gui.ZScreen
local LiveTooltipCoverScreen = defclass(nil, gui.ZScreen)
LiveTooltipCoverScreen.ATTRS{
    initial_pause=false,
    pass_mouse_clicks=true,
}

---Fails the live probe with a named expectation.
---@param condition boolean
---@param message string
local function expect(condition, message)
    if not condition then error(message, 2) end
end

local probe
local cover
local registered = false
local original_get_mouse_pos

---Dismisses every live object created by this probe.
local function cleanup()
    if original_get_mouse_pos then
        dfhack.screen.getMousePos = original_get_mouse_pos
        original_get_mouse_pos = nil
    end
    if registered and probe then
        tooltip.unregister(probe.target)
        registered = false
    end
    if cover and cover:isActive() then cover:dismiss() end
    if probe and probe:isActive() then probe:dismiss() end
end

local ok, err = xpcall(function()
    local initial_registration_count =
        registration.get_diagnostics().registration_count
    probe = LiveTooltipProbeScreen{}
    probe:show()
    expect(tooltip.register(probe.target),
        'first public tooltip.register() call was not created')
    registered = true

    local diagnostics = registration.get_diagnostics()
    expect(diagnostics.registration_count == initial_registration_count + 1,
        'singleton registry did not add exactly one control')
    expect(diagnostics.renderer_count == 1,
        'singleton service did not contain exactly one renderer')
    local probe_x = probe.target.frame_body.x1
    local probe_y = probe.target.frame_body.y1
    diagnostics.screen:onIdle()
    expect(diagnostics.screen:hasFocus(),
        'existing service screen did not raise above the new probe screen')
    original_get_mouse_pos = dfhack.screen.getMousePos
    dfhack.screen.getMousePos = function() return probe_x, probe_y end
    diagnostics.screen:onRender()
    dfhack.screen.getMousePos = original_get_mouse_pos
    original_get_mouse_pos = nil
    diagnostics = registration.get_diagnostics()
    expect(diagnostics.target == probe.target,
        'live screen target was not selected')
    expect(diagnostics.screen.renderer.visible,
        'live screen tooltip renderer did not become visible')
    expect(diagnostics.screen.renderer.tooltip_text:match(
        '^Live dynamic tooltip %d+,%d+$') ~= nil,
        'live dynamic pointer mutation was not presented immediately')

    local blocker = widgets.Window{
        frame={l=probe_x, t=probe_y, w=12, h=3},
        title='Modal probe',
    }
    probe:addviews{blocker}
    probe:updateLayout()
    original_get_mouse_pos = dfhack.screen.getMousePos
    dfhack.screen.getMousePos = function() return probe_x, probe_y end
    diagnostics.screen:onRender()
    dfhack.screen.getMousePos = original_get_mouse_pos
    original_get_mouse_pos = nil
    expect(registration.get_diagnostics().target == nil,
        'live modal window did not block the underlying tooltip target')
    expect(not diagnostics.screen.renderer.visible,
        'live modal blocker left the underlying tooltip visible')
    blocker.visible = false

    local forwarded
    local original_forward = diagnostics.screen.sendInputToParent
    ---Captures input without delivering the synthetic probe key.
    diagnostics.screen.sendInputToParent = function(_, keys)
        forwarded = keys
    end
    local keys = {_DWARFUI_PHASE9_PROBE=true}
    diagnostics.screen:onInput(keys)
    diagnostics.screen.sendInputToParent = original_forward
    expect(forwarded == keys, 'service screen did not forward input unchanged')
    expect(not diagnostics.screen:isMouseOver(),
        'service screen claimed a mouse hit')

    cover = LiveTooltipCoverScreen{}
    cover:show()
    diagnostics.screen:onIdle()
    expect(diagnostics.screen:hasFocus(),
        'service screen did not raise above a newly opened screen')

    expect(tooltip.unregister(probe.target),
        'public tooltip.unregister() did not remove the control')
    registered = false
    local final_diagnostics = registration.get_diagnostics()
    expect(final_diagnostics.registration_count == initial_registration_count,
        'screen probe registration survived explicit unregistration')
    expect(final_diagnostics.renderer_count ==
        (initial_registration_count > 0 and 1 or 0),
        'service renderer lifecycle did not match remaining registrations')
end, debug.traceback)

cleanup()
if not ok then error(err, 0) end
print('DwarfUI Phase 9 screen probe: PASS')
