--@ module=true

-- Input-transparent presentation for one active map-location prompt.

local gui = require('gui')
local widgets = require('gui.widgets')
local PointerPolicy = reqscript('dwarfuicore/pointer').PointerPolicy
local values = reqscript('dwarfuicore/user_prompt/value')

local FRAME_CELLS = 2
local NAMESPACE_DECORATION_CELLS = 6
local MAX_CONTENT_WIDTH = 60
local BACKGROUND = dfhack.pen.parse{ch=32, fg=COLOR_BLACK, bg=COLOR_BLACK}
local TITLE_TEXT = dfhack.pen.parse{fg=COLOR_YELLOW, bg=COLOR_BLACK}
local MESSAGE_TEXT = dfhack.pen.parse{fg=COLOR_WHITE, bg=COLOR_BLACK}

---@class dwarfuicore.UserPromptLayout
---@field frame {l: integer, t: integer, w: integer, h: integer}
---@field namespace_label string
---@field content_width integer
---@field title_lines string[]
---@field message_lines string[]

---Returns text clipped to the namespace-label capacity.
---@param value string
---@param width integer
---@return string
function truncate_namespace(value, width)
    if width <= 0 then return '' end
    if #value <= width then return value end
    if width >= 4 then return value:sub(1, width - 3) .. '...' end
    return value:sub(1, width)
end

---Wraps copied text while preserving every explicit line boundary.
---@param value string
---@param width integer
---@return string[]
function wrap_text(value, width)
    width = math.max(1, width)
    local result = {}
    local start = 1
    while true do
        local newline = value:find('\n', start, true)
        local logical = value:sub(start, newline and newline - 1 or #value)
        if logical == '' then
            table.insert(result, '')
        else
            local remaining = logical
            while #remaining > width do
                local split = width
                local prefix = remaining:sub(1, width)
                local space = prefix:match('^.*() ')
                if space and space > 1 then split = space - 1 end
                table.insert(result, remaining:sub(1, split))
                remaining = remaining:sub(split + 1):gsub('^ +', '')
            end
            table.insert(result, remaining)
        end
        if not newline then break end
        start = newline + 1
    end
    return result
end

---Measures and clamps one prompt below the current screen pointer.
---@param request dwarfuicore.MapLocationPromptRequest
---@param pointer_x integer
---@param pointer_y integer
---@param screen_width integer
---@param screen_height integer
---@return dwarfuicore.UserPromptLayout
function calculate_layout(request, pointer_x, pointer_y,
        screen_width, screen_height)
    assert(values.MapLocationPromptRequest.is_instance(request),
        'DwarfUICore prompt renderer requires a request snapshot.')
    assert(screen_width >= 1 and screen_height >= 1,
        'DwarfUICore prompt renderer requires a non-empty interface.')
    local wrapped_width = math.max(1,
        math.min(MAX_CONTENT_WIDTH, screen_width - FRAME_CELLS))
    local title_lines = wrap_text(request.title, wrapped_width)
    local message_lines = wrap_text(request.message, wrapped_width)
    local content_requirement = 1
    for _, line in ipairs(title_lines) do
        content_requirement = math.max(content_requirement, #line)
    end
    for _, line in ipairs(message_lines) do
        content_requirement = math.max(content_requirement, #line)
    end
    local frame_width = math.min(screen_width, math.max(
        FRAME_CELLS + content_requirement,
        #request.namespace + NAMESPACE_DECORATION_CELLS))
    local title_height_requirement = request.title ~= '' and
        #title_lines or 0
    local message_height_requirement = request.message ~= '' and
        #message_lines or 0
    local frame_height = math.min(screen_height, FRAME_CELLS +
        title_height_requirement + message_height_requirement)
    local left = math.max(0, math.min(
        pointer_x + 2, screen_width - frame_width))
    local top = math.max(0, math.min(
        pointer_y + 1, screen_height - frame_height))
    return {
        frame={l=left, t=top, w=frame_width, h=frame_height},
        namespace_label=truncate_namespace(request.namespace,
            math.max(0, frame_width - NAMESPACE_DECORATION_CELLS)),
        content_width=math.max(0, frame_width - FRAME_CELLS),
        title_lines=title_lines,
        message_lines=message_lines,
    }
end

---@class dwarfuicore.UserPromptRenderer: gui.widgets.Widget
---@field request dwarfuicore.MapLocationPromptRequest|nil
---@field namespace string|nil
---@field title string|nil
---@field message string|nil
UserPromptRenderer = defclass(nil, widgets.Widget)
UserPromptRenderer.ATTRS{
    frame={l=0, t=0, w=1, h=1},
    frame_style=gui.FRAME_INTERIOR,
    frame_background=BACKGROUND,
    frame_inset=1,
    draggable=false,
    no_force_pause_badge=true,
    pointer_policy=PointerPolicy.NONE,
    visible=false,
}

---Constructs the hidden prompt renderer and its distinct text regions.
function UserPromptRenderer:init()
    self.visible = false
    self.request = nil
    self.namespace = nil
    self.title = nil
    self.message = nil
    self.namespace_label = nil
    self.title_label = widgets.Label{
        frame={l=0, t=0, w=1, h=1},
        auto_height=false,
        text_pen=TITLE_TEXT,
        text='',
        pointer_policy=PointerPolicy.NONE,
    }
    self.message_label = widgets.Label{
        frame={l=0, t=1, w=1, h=1},
        auto_height=false,
        text_pen=MESSAGE_TEXT,
        text='',
        pointer_policy=PointerPolicy.NONE,
    }
    self:addviews{self.title_label, self.message_label}
end

---Invalidates the owner so both the old and new rectangles are repainted.
function UserPromptRenderer:_invalidate_owner()
    if self.parent_view and self.parent_view.invalidate then
        self.parent_view:invalidate()
    end
end

---Updates copied content, placement, visibility, and viewport-dependent layout.
---@param request dwarfuicore.MapLocationPromptRequest|nil
---@param pointer_x integer|nil
---@param pointer_y integer|nil
---@param layout_parent_rect gui.ViewRect|nil
function UserPromptRenderer:set_prompt(request, pointer_x, pointer_y,
        layout_parent_rect)
    assert(request == nil or
        values.MapLocationPromptRequest.is_instance(request),
        'DwarfUICore prompt renderer requires a request snapshot or nil.')
    local has_pointer = pointer_x ~= nil and pointer_y ~= nil
    local visible = request ~= nil and has_pointer
    local screen_width, screen_height
    if layout_parent_rect then
        screen_width, screen_height =
            layout_parent_rect.width, layout_parent_rect.height
    else
        screen_width, screen_height = dfhack.screen.getWindowSize()
    end
    local viewport_key = screen_width .. 'x' .. screen_height
    local changed = self.visible ~= visible or self.request ~= request or
        self.pointer_x ~= pointer_x or self.pointer_y ~= pointer_y or
        self.viewport_key ~= viewport_key

    self.visible = visible
    self.request = request
    self.namespace = request and request.namespace or nil
    self.title = request and request.title or nil
    self.message = request and request.message or nil
    self.pointer_x, self.pointer_y = pointer_x, pointer_y
    self.viewport_key = viewport_key

    if visible then
        local layout = calculate_layout(request, pointer_x, pointer_y,
            screen_width, screen_height)
        self.frame = layout.frame
        self.namespace_label = layout.namespace_label
        local body_height = math.max(0, layout.frame.h - FRAME_CELLS)
        local has_title = request.title ~= ''
        local has_message = request.message ~= ''
        local title_height = 0
        local message_height = 0
        if has_title and has_message and body_height >= 2 then
            title_height = math.min(
                #layout.title_lines, body_height - 1)
            message_height = math.min(
                #layout.message_lines, body_height - title_height)
        elseif has_title then
            title_height = math.min(#layout.title_lines, body_height)
        elseif has_message then
            message_height = math.min(#layout.message_lines, body_height)
        end
        self.title_label.frame = {
            l=0, t=0, w=layout.content_width, h=title_height,
        }
        self.message_label.frame = {
            l=0, t=title_height,
            w=layout.content_width, h=message_height,
        }
        self.title_label:setText(table.concat(layout.title_lines, '\n'))
        self.message_label:setText(table.concat(layout.message_lines, '\n'))
        self:updateLayout(layout_parent_rect)
    else
        self.namespace_label = nil
        self.title_label:setText('')
        self.message_label:setText('')
    end
    if changed then self:_invalidate_owner() end
end

---Renders only while a request and screen-pointer coordinate are available.
---@param dc gui.Painter
function UserPromptRenderer:render(dc)
    if not self.visible then return end
    UserPromptRenderer.super.render(self, dc)
end

---Paints the background, frame, and centered owning namespace attribution.
---@param dc gui.Painter
---@param rect gui.ViewRect
function UserPromptRenderer:onRenderFrame(dc, rect)
    if self.frame_background then dc:fill(rect, self.frame_background) end
    gui.paint_frame(dc, rect, self.frame_style, self.namespace_label)
end
