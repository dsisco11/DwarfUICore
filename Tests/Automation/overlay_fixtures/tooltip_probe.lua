--@ module=true

-- Test-owned overlay used only while the automation runner stages this file.

local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')
local tooltip = reqscript('dwarfui/tooltip')

---@class tests.AutomationTooltipOverlay: plugins.overlay.OverlayWidget
local AutomationTooltipOverlay = defclass(nil, overlay.OverlayWidget)
AutomationTooltipOverlay.ATTRS{
    default_enabled=true,
    default_pos={x=1, y=1},
    desc='DwarfUI automation tooltip overlay',
    frame={w=8, h=4},
    viewscreens='dwarfmode',
}

---Builds the registered target inside the intentionally clipped overlay root.
function AutomationTooltipOverlay:init()
    self.tooltip_target = widgets.Label{
        view_id='tooltip_target',
        frame={l=0, t=0, r=0, b=0},
        text=' ',
        tooltip='Automation overlay tooltip outside its narrow root.',
    }
    self:addviews{self.tooltip_target}
    tooltip.register(self.tooltip_target)
end

---Releases the overlay target when the overlay framework disposes it.
function AutomationTooltipOverlay:onDismiss()
    tooltip.unregister(self.tooltip_target)
    AutomationTooltipOverlay.super.onDismiss(self)
end

OVERLAY_WIDGETS = {tooltip_probe=AutomationTooltipOverlay}

return _ENV
