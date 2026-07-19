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
        text='',
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

---Dismisses every live object created by this probe.
local function cleanup()
    if registered and probe then
        tooltip.unregister(probe.target)
        registered = false
    end
    if cover and cover:isActive() then cover:dismiss() end
    if probe and probe:isActive() then probe:dismiss() end
end

local ok, err = xpcall(function()
    probe = LiveTooltipProbeScreen{}
    probe:show()
    expect(tooltip.register(probe.target),
        'first public tooltip.register() call was not created')
    registered = true

    local diagnostics = registration.get_diagnostics()
    expect(diagnostics.registration_count == 1,
        'singleton registry did not contain exactly one control')
    expect(diagnostics.renderer_count == 1,
        'singleton service did not contain exactly one renderer')
    diagnostics.screen:onRender()
    diagnostics = registration.get_diagnostics()
    expect(diagnostics.target == probe.target,
        'live screen target was not selected')
    expect(diagnostics.screen.renderer.visible,
        'live screen tooltip renderer did not become visible')
    expect(diagnostics.screen.renderer.tooltip_text:match(
        '^Live dynamic tooltip %d+,%d+$') ~= nil,
        'live dynamic pointer mutation was not presented immediately')

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
    expect(registration.get_diagnostics().renderer_count == 0,
        'service renderer survived final unregistration')
end, debug.traceback)

cleanup()
if not ok then error(err, 0) end
print('DwarfUI Phase 9 screen probe: PASS')
