-- Test-owned normal screen that registers one dynamic tooltip target.

local gui = require('gui')
local widgets = require('gui.widgets')
local tooltip = reqscript('dwarfui/tooltip')

---@class tests.AutomationTooltipScreen: gui.ZScreen
local AutomationTooltipScreen = defclass(nil, gui.ZScreen)
AutomationTooltipScreen.ATTRS{
    initial_pause=false,
    pass_mouse_clicks=true,
}

---Builds a normal-screen target and an optionally visible modal blocker.
---@param options table|nil
function AutomationTooltipScreen:init(options)
    options = options or {}
    self.render_generation = 0
    self.last_key = nil
    self.target = widgets.Label{
        view_id='tooltip_target',
        frame={l=2, t=2, w=24, h=1},
        text='Automation tooltip target',
        tooltip='Automation static tooltip',
    }
    self.target.on_pointer_update = function(target, x, y)
        target.tooltip = ('Automation dynamic tooltip %d,%d'):format(x, y)
    end
    self.blocker = widgets.Window{
        view_id='tooltip_blocker',
        frame={l=1, t=1, w=28, h=4},
        title='Automation blocker',
        visible=options.blocker_visible == true,
    }
    self:addviews{self.target, self.blocker}
end

---Registers the target after the automation driver has shown this screen.
function AutomationTooltipScreen:on_automation_shown()
    tooltip.register(self.target)
end

---Records each real screen render for automation synchronization.
function AutomationTooltipScreen:onRender()
    AutomationTooltipScreen.super.onRender(self)
    self.render_generation = self.render_generation + 1
end

---Records a forwarded synthetic key without consuming unrelated input.
---@param keys table
---@return boolean
function AutomationTooltipScreen:onInput(keys)
    if keys.CUSTOM_A then
        self.last_key = 'CUSTOM_A'
        return true
    end
    return AutomationTooltipScreen.super.onInput(self, keys)
end

---Releases the fixture registration when DFHack dismisses this screen.
function AutomationTooltipScreen:onDismiss()
    tooltip.unregister(self.target)
    AutomationTooltipScreen.super.onDismiss(self)
end

local M = {}

---Creates one test-owned tooltip screen.
---@param options table|nil
---@return table
function M.new(options)
    return AutomationTooltipScreen(options)
end

return M
