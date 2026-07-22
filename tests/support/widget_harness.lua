local M = {}
local DEFAULT_NIL = {}

local function getval(value)
    if type(value) == 'function' then return value() end
    return value
end

---@return table rectangle
function M.rect(x, y, width, height, clip)
    clip = clip or {
        x1=x,
        y1=y,
        x2=x + width - 1,
        y2=y + height - 1,
    }
    return {
        x1=x,
        y1=y,
        x2=x + width - 1,
        y2=y + height - 1,
        width=width,
        height=height,
        clip_x1=clip.x1,
        clip_y1=clip.y1,
        clip_x2=clip.x2,
        clip_y2=clip.y2,
        inClipGlobalXY=function(self, px, py)
            return px >= self.clip_x1 and px <= self.clip_x2 and
                py >= self.clip_y1 and py <= self.clip_y2
        end,
        localXY=function(self, px, py)
            return px - self.x1, py - self.y1
        end,
    }
end

local function addviews(self, views)
    self.subviews = self.subviews or {}
    for _, view in ipairs(views or {}) do
        view.parent_view = self
        table.insert(self.subviews, view)
        if view.view_id and self.subviews[view.view_id] == nil then
            self.subviews[view.view_id] = view
        end
    end
end

local function inset_edges(inset)
    if type(inset) == 'number' then return inset, inset, inset, inset end
    inset = inset or {}
    return inset.l or inset.x or 0,
        inset.t or inset.y or 0,
        inset.r or inset.x or 0,
        inset.b or inset.y or 0
end

local function compute_frame(self, parent_rect)
    local frame = self.frame or {}
    local width = frame.w or math.max(0,
        parent_rect.width - (frame.l or 0) - (frame.r or 0))
    local height = frame.h or math.max(0,
        parent_rect.height - (frame.t or 0) - (frame.b or 0))
    local frame_x = frame.l or 0
    local frame_y = frame.t or 0
    local global_x = parent_rect.x1 + frame_x
    local global_y = parent_rect.y1 + frame_y
    local inset_l, inset_t, inset_r, inset_b = inset_edges(self.frame_inset)
    local body_x = global_x + inset_l
    local body_y = global_y + inset_t
    local body_width = math.max(0, width - inset_l - inset_r)
    local body_height = math.max(0, height - inset_t - inset_b)
    return M.rect(frame_x, frame_y, width, height), M.rect(
        body_x,
        body_y,
        body_width,
        body_height,
        {
            x1=math.max(parent_rect.clip_x1 or parent_rect.x1, body_x),
            y1=math.max(parent_rect.clip_y1 or parent_rect.y1, body_y),
            x2=math.min(parent_rect.clip_x2 or parent_rect.x2,
                body_x + body_width - 1),
            y2=math.min(parent_rect.clip_y2 or parent_rect.y2,
                body_y + body_height - 1),
        })
end

local BASE_METHODS = {}

BASE_METHODS.addviews = addviews

function BASE_METHODS:updateLayout(parent_rect)
    parent_rect = parent_rect or self.frame_parent_rect
    assert(parent_rect, 'widget layout requires a parent rectangle')
    self.frame_parent_rect = parent_rect
    self.frame_rect, self.frame_body = compute_frame(self, parent_rect)
    self.layout_update_count = (self.layout_update_count or 0) + 1
    for _, child in ipairs(self.subviews or {}) do
        child:updateLayout(self.frame_body)
    end
end

function BASE_METHODS:render(dc)
    if not getval(self.visible) then return end
    self.render_count = (self.render_count or 0) + 1
    if self.onRenderFrame then self:onRenderFrame(dc, self.frame_rect) end
    if self.onRenderBody then self:onRenderBody(dc) end
    for _, child in ipairs(self.subviews or {}) do child:render(dc) end
end

function BASE_METHODS:invalidate()
    self.invalidation_count = (self.invalidation_count or 0) + 1
end

function BASE_METHODS:setText(value)
    self.text = value
end

local function apply_attributes(instance, class, info, default_nil)
    local chain = {}
    local current = class
    while current do
        table.insert(chain, 1, current)
        current = rawget(current, 'super')
    end
    for _, ancestor in ipairs(chain) do
        for key, value in pairs(rawget(ancestor, 'ATTRS') or {}) do
            if info[key] == nil and value ~= default_nil then
                instance[key] = value
            end
        end
    end
    for key, value in pairs(info) do
        if key ~= 'subviews' then instance[key] = value end
    end
end

local function merge_methods(base, overrides)
    local result = {}
    for key, value in pairs(base or {}) do result[key] = value end
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function class(kind, parent, default_nil, methods)
    local attributes = {}
    local result = {widget_kind=kind, super=parent}
    result.ATTRS = setmetatable(attributes, {
        __call=function(_, additions)
            for key, value in pairs(additions) do attributes[key] = value end
        end,
    })
    for key, value in pairs(methods or {}) do result[key] = value end

    return setmetatable(result, {
        __index=parent,
        __call=function(class_table, info)
            info = info or {}
            local instance = {subviews={}}
            apply_attributes(instance, class_table, info, default_nil)
            setmetatable(instance, {__index=class_table})
            if info.subviews then instance:addviews(info.subviews) end
            if class_table.init then class_table.init(instance, info) end
            return instance
        end,
    })
end

---Returns the minimal DFHack widget class surface needed by the tooltip port.
---@param overrides? table<string, table>
---@param default_nil? table
---@return table widgets
function M.widgets(overrides, default_nil)
    default_nil = default_nil or DEFAULT_NIL
    overrides = overrides or {}

    local widgets = {}
    widgets.Widget = class(
        'Widget', nil, default_nil, merge_methods(BASE_METHODS, overrides.Widget))
    widgets.Panel = class('Panel', widgets.Widget, default_nil, overrides.Panel)
    widgets.Window = class('Window', widgets.Panel, default_nil, overrides.Window)
    widgets.Label = class('Label', widgets.Widget, default_nil, overrides.Label)
    widgets.List = class('List', widgets.Widget, default_nil, overrides.List)
    ---Replaces the harness list's choices with the supplied rows.
    ---@param choices table[]|nil
    function widgets.List:setChoices(choices)
        self.choices = choices or {}
    end
    widgets.TextButton = class(
        'TextButton', widgets.Panel, default_nil, overrides.TextButton)
    return widgets
end

---Creates a DFHack-like subclass constructor for production module tests.
---@param _ table|nil global_slot
---@param parent table
---@return table class
function M.defclass(_, parent)
    assert(parent, 'defclass requires a parent class')
    return class('defclass', parent, DEFAULT_NIL)
end

function M.default_nil()
    return DEFAULT_NIL
end

function M.set_frame(view, x, y, width, height, body)
    view.frame_parent_rect = M.rect(0, 0,
        math.max(x + width, 1), math.max(y + height, 1))
    view.frame_rect = M.rect(x, y, width, height)
    view.frame_body = body or M.rect(x, y, width, height)
    return view
end

return M
