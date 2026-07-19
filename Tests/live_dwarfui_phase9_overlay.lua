--@ module=true

-- Temporary live-only overlay copied into hack/scripts for Phase 9 validation.

local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')
local tooltip = reqscript('dwarfui/tooltip')

---@class tests.LivePhase9Overlay: plugins.overlay.OverlayWidget
local LivePhase9Overlay = defclass(nil, overlay.OverlayWidget)
LivePhase9Overlay.ATTRS{
    default_enabled=false,
    default_pos={x=1, y=1},
    desc='Temporary DwarfUI Phase 9 tooltip probe',
    frame={w=8, h=4},
    viewscreens='dwarfmode',
}

---Builds and registers one control that fills the clipped overlay root.
function LivePhase9Overlay:init()
    self.tooltip_target = widgets.Label{
        frame={l=0, t=0, r=0, b=0},
        text='',
        tooltip='Live overlay tooltip that escapes a narrow clipped root.',
    }
    self:addviews{self.tooltip_target}
    tooltip.register(self.tooltip_target)
end

OVERLAY_WIDGETS = {probe=LivePhase9Overlay}

return _ENV
