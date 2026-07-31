--@ module=true

-- Native Window/List composition and deterministic context-menu painting.

local gui = require('gui')
local widgets = require('gui.widgets')

local FRAME_CELLS = 2
local TITLE_DECORATION_CELLS = 6
local MIN_CONTENT_WIDTH = 1

---@class dwarfui.ContextMenuLayout
---@field frame {l: integer, t: integer, w: integer, h: integer}
---@field content_width integer
---@field title? string
---@field choices table[]

---@class dwarfui.ContextMenuList: widgets.List
---@field super widgets.List
ContextMenuList = defclass(ContextMenuList, widgets.List)

---@class dwarfui.ContextMenuWindow: widgets.Window
---@field super widgets.Window
---@field definition dwarfui.ContextMenuDefinitionSnapshot
---@field anchor {x: integer, y: integer}
---@field menu_list dwarfui.ContextMenuList
ContextMenuWindow = defclass(ContextMenuWindow, widgets.Window)

---Returns text clipped to a deterministic interface-cell width.
---@param value string
---@param width integer
---@return string
function truncate_text(value, width)
    if width <= 0 then return '' end
    if #value <= width then return value end
    if width >= 4 then
        return value:sub(1, width - 3) .. '...'
    end
    return value:sub(1, width)
end

---Creates a copied pen while preserving the source glyph and tile.
---@param source any
---@param foreground integer
---@param background integer
---@return any
local function recolor_pen(source, foreground, background)
    return dfhack.pen.parse(source, foreground, background)
end

---Creates one isolated native frame style for a menu.
---@param foreground integer
---@param background integer
---@return table
function create_frame_style(foreground, background)
    local style = gui.FRAME_INTERIOR()
    for field, value in pairs(style) do
        if field:match('_pen$') and value ~= false then
            style[field] = recolor_pen(value, foreground, background)
        end
    end
    style.frame_pen = recolor_pen(
        style.frame_pen or {}, foreground, background)
    style.title_pen = recolor_pen(
        style.title_pen or style.frame_pen, foreground, background)
    return style
end

---Creates the normal pen for one resolved entry.
---@param entry dwarfui.ContextMenuResolvedEntry
---@return any
local function normal_pen(entry)
    return dfhack.pen.parse{ch=' ', fg=entry.fg, bg=entry.bg}
end

---Creates a readable selected or hovered pen for one resolved entry.
---@param entry dwarfui.ContextMenuResolvedEntry
---@return any
local function active_pen(entry)
    if entry.fg ~= entry.bg then
        return dfhack.pen.parse{ch=' ', fg=entry.bg, bg=entry.fg}
    end
    local foreground = entry.bg < 8 and 15 or 0
    return dfhack.pen.parse{ch=' ', fg=foreground, bg=entry.bg}
end

---Paints complete rows while retaining native List selection and scrolling.
---@param dc gui.Painter
function ContextMenuList:onRenderBody(dc)
    local first = self.page_top
    local last = math.min(#self.choices, first + self.page_size - 1)
    local hovered = self:getIdxUnderMouse()
    for index = first, last do
        local choice = self.choices[index]
        local is_active = index == self.selected or index == hovered
        local pen = is_active and choice.active_pen or choice.normal_pen
        local y = index - first
        dc:fill(0, y, dc.width - 1, y, pen)
        dc:seek(0, y):string(choice.text, pen)
    end
end

---Measures and clamps the menu against the current interface rectangle.
---@param definition dwarfui.ContextMenuDefinitionSnapshot
---@param anchor {x: integer, y: integer}
---@param screen_width integer
---@param screen_height integer
---@return dwarfui.ContextMenuLayout
function calculate_layout(definition, anchor, screen_width, screen_height)
    assert(screen_width >= 1 and screen_height >= 1,
        'DwarfUI context-menu layout requires a non-empty interface.')
    local preferred_width = definition.title and
        #definition.title + TITLE_DECORATION_CELLS or 0
    for _, entry in ipairs(definition.entries) do
        preferred_width = math.max(
            preferred_width, #entry.label + FRAME_CELLS)
    end
    local frame_width = math.min(screen_width,
        math.max(FRAME_CELLS + MIN_CONTENT_WIDTH, preferred_width))
    local frame_height = math.min(screen_height,
        #definition.entries + FRAME_CELLS)
    local content_width = math.max(
        MIN_CONTENT_WIDTH, frame_width - FRAME_CELLS)
    local left = math.max(0,
        math.min(anchor.x, screen_width - frame_width))
    local top = math.max(0,
        math.min(anchor.y, screen_height - frame_height))
    local choices = {}
    for index, entry in ipairs(definition.entries) do
        choices[index] = {
            text=truncate_text(entry.label, content_width),
            normal_pen=normal_pen(entry),
            active_pen=active_pen(entry),
            entry_index=index,
        }
    end
    return {
        frame={l=left, t=top, w=frame_width, h=frame_height},
        content_width=content_width,
        title=definition.title and
            truncate_text(definition.title,
                math.max(0, frame_width - TITLE_DECORATION_CELLS)) or nil,
        choices=choices,
    }
end

---@class dwarfui.ContextMenuWindowOptions
---@field definition dwarfui.ContextMenuDefinitionSnapshot
---@field anchor {x: integer, y: integer}
---@field on_select fun(entry_index: integer)

---Constructs a native non-draggable Window containing one selectable List.
---@param info dwarfui.ContextMenuWindowOptions
function ContextMenuWindow:init(info)
    self.definition = info.definition
    self.anchor = {x=info.anchor.x, y=info.anchor.y}
    self.frame_style = create_frame_style(
        info.definition.fg, info.definition.bg)
    self.frame_background = dfhack.pen.parse{
        ch=' ',
        fg=info.definition.fg,
        bg=info.definition.bg,
    }
    self.draggable = false
    self.resizable = false
    self.frame_inset = 0
    self.menu_list = ContextMenuList{
        view_id='menu_list',
        frame={l=0, t=0, r=0, b=0},
        on_submit=function(_, choice)
            if choice then info.on_select(choice.entry_index) end
        end,
    }
    self:addviews{self.menu_list}
end

---Recomputes dimensions, truncation, and edge clamping after a resize.
---@param screen_width integer
---@param screen_height integer
function ContextMenuWindow:relayout(screen_width, screen_height)
    local layout = calculate_layout(
        self.definition, self.anchor, screen_width, screen_height)
    self.frame = layout.frame
    self.frame_title = layout.title
    self.menu_list:setChoices(layout.choices)
    self:updateLayout()
end
