--@ module=true

local gui = require('gui')
local widgets = require('gui.widgets')
local PointerPolicy = reqscript('dwarfui/pointer').PointerPolicy
reqscript('dwarfui/widget_extensions')
local text_helpers = reqscript('dwarfui/text')

local BACKGROUND = dfhack.pen.parse{
    ch=32,
    fg=COLOR_BLACK,
    bg=COLOR_BLACK,
}
local TEXT = dfhack.pen.parse{fg=COLOR_WHITE, bg=COLOR_BLACK}

-- A moving tooltip is presentation layered over a host, not a Panel or Window.
-- Keeping it a plain Widget avoids their global layout/redraw lifecycle inside
-- the host's render pass.
---@class dwarfui.TooltipRenderer: gui.widgets.Widget
TooltipRenderer = defclass(nil, widgets.Widget)
TooltipRenderer.ATTRS{
    frame={l=0, t=0, w=1, h=3},
    frame_style=gui.FRAME_INTERIOR,
    frame_background=BACKGROUND,
    frame_inset=1,
    draggable=false,
    no_force_pause_badge=true,
    pointer_policy=PointerPolicy.NONE,
    visible=false,
}

---Constructs the hidden renderer and its text label.
function TooltipRenderer:init()
    self.visible = false
    self.tooltip_text = nil
    self.mouse_x = nil
    self.mouse_y = nil
    self.label = widgets.Label{
        frame={l=0, t=0, w=1, h=1},
        auto_height=false,
        text_pen=TEXT,
        text='',
        pointer_policy=PointerPolicy.NONE,
    }
    self:addviews{self.label}
end

---Updates tooltip content, placement, and visibility.
---@param text string|nil
---@param mouse_x integer|nil
---@param mouse_y integer|nil
---@param layout_parent_rect gui.ViewRect|nil
function TooltipRenderer:set_tooltip(
        text, mouse_x, mouse_y, layout_parent_rect)
    local has_text = text ~= nil and text ~= ''
    local has_pointer = mouse_x ~= nil and mouse_y ~= nil
    local visible = has_text and has_pointer
    local tooltip_text = visible and text or nil
    local changed = self.visible ~= visible or
        self.tooltip_text ~= tooltip_text or
        self.mouse_x ~= mouse_x or self.mouse_y ~= mouse_y

    self.visible = visible
    self.tooltip_text = tooltip_text
    self.mouse_x = mouse_x
    self.mouse_y = mouse_y

    if self.visible then
        local screen_width, screen_height
        if layout_parent_rect then
            screen_width = layout_parent_rect.width
            screen_height = layout_parent_rect.height
        else
            screen_width, screen_height = dfhack.screen.getWindowSize()
        end
        local content_width = math.max(
            1, math.min(60, screen_width - 2))
        local lines = text_helpers.wrap_text(
            self.tooltip_text, content_width)
        local width = 2
        for _, line in ipairs(lines) do
            width = math.max(width, #line + 2)
        end
        local height = #lines + 2
        self.frame = {
            l=math.max(0, math.min(mouse_x + 2, screen_width - width)),
            t=math.max(0, math.min(mouse_y + 1, screen_height - height)),
            w=width,
            h=height,
        }
        self.label.frame = {l=0, t=0, w=width - 2, h=height - 2}
        self.label:setText(table.concat(lines, '\n'))
        self:updateLayout(layout_parent_rect)
    else
        self.label:setText('')
    end

    -- Visibility and frame changes do not redraw the old screen cells by
    -- themselves. Invalidating the owner makes updates and mouse-out immediate.
    if changed and self.parent_view and self.parent_view.invalidate then
        self.parent_view:invalidate()
    end
end

---Renders only while the renderer owns visible tooltip text.
---@param dc gui.Painter
function TooltipRenderer:render(dc)
    if not self.visible then return end
    TooltipRenderer.super.render(self, dc)
end

---Paints the tooltip background and interior frame.
---@param dc gui.Painter
---@param rect gui.ViewRect
function TooltipRenderer:onRenderFrame(dc, rect)
    if self.frame_background then
        dc:fill(rect, self.frame_background)
    end
    gui.paint_frame(dc, rect, self.frame_style)
end
