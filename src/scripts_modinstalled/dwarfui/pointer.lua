--@ module=true

-- Generic pointer targeting deliberately has no tooltip dependency.

local immutable_enum = reqscript('dwarfui/utils/immutable_enum')

---@enum dwarfui.PointerPolicy
PointerPolicy = immutable_enum.define({
    TARGET=1,
    PASS=2,
    BLOCK=3,
    NONE=4,
}, 'PointerPolicy')

---@enum dwarfui.PointerResultKind
PointerResultKind = immutable_enum.define({
    TARGET=1,
    BLOCKED=2,
    MISS=3,
}, 'PointerResultKind')

local function getval(value)
    if type(value) == 'function' then return value() end
    return value
end

local function is_eligible(view)
    return view and getval(view.visible) and getval(view.active)
end

local function body_contains(view, x, y)
    local body = view.frame_body
    return body and body:inClipGlobalXY(x, y)
end

local function frame_contains(view, x, y)
    local frame = view.frame_rect
    local parent = view.frame_parent_rect
    if frame and parent then
        local x1 = frame.x1 + parent.x1
        local y1 = frame.y1 + parent.y1
        return x >= x1 and x <= x1 + frame.width - 1 and
            y >= y1 and y <= y1 + frame.height - 1
    end
    return body_contains(view, x, y)
end

---Returns a pointer miss result.
---@return dwarfui.PointerResult
local function miss()
    return {kind=PointerResultKind.MISS}
end

---Returns a pointer blocker result.
---@param view gui.View
---@return dwarfui.PointerResult
local function blocked(view)
    return {kind=PointerResultKind.BLOCKED, blocker=view}
end

---Returns a pointer target result with target-local coordinates.
---@param view gui.View
---@param x integer
---@param y integer
---@return dwarfui.PointerResult
local function targeted(view, x, y)
    local local_x, local_y = view.frame_body:localXY(x, y)
    return {
        kind=PointerResultKind.TARGET,
        target=view,
        x=local_x,
        y=local_y,
    }
end

---Resolves one eligible view and its descendants at a screen coordinate.
---@param view gui.View
---@param x integer
---@param y integer
---@return dwarfui.PointerResult
local function resolve_view(view, x, y)
    if not is_eligible(view) then return miss() end
    local inside_body = body_contains(view, x, y)
    local inside_frame = frame_contains(view, x, y)
    if not inside_body and not inside_frame then return miss() end

    local policy = view.pointer_policy or PointerPolicy.TARGET
    assert(policy == PointerPolicy.TARGET or
            policy == PointerPolicy.PASS or
            policy == PointerPolicy.BLOCK or
            policy == PointerPolicy.NONE,
        'DwarfUI invalid pointer_policy ' .. tostring(policy) ..
        '; expected a PointerPolicy member.')
    if policy == PointerPolicy.NONE then return miss() end

    -- Terminal controls own their complete public hit region. Implementation
    -- subviews therefore cannot steal pointer ownership from a TextButton or
    -- another composite target.
    if policy == PointerPolicy.TARGET and inside_body then
        return targeted(view, x, y)
    end

    if inside_body then
        local subviews = view.subviews or {}
        for index = #subviews, 1, -1 do
            local result = resolve_view(subviews[index], x, y)
            if result.kind ~= PointerResultKind.MISS then return result end
        end
    end

    if policy == PointerPolicy.BLOCK and inside_frame then
        return blocked(view)
    end
    return miss()
end

---@class dwarfui.PointerContext
---@field root gui.View
---@field target gui.View|nil
---@field result table
PointerContext = {}
PointerContext.__index = PointerContext

---@class dwarfui.PointerResult
---@field kind dwarfui.PointerResultKind
---@field target? gui.View
---@field blocker? gui.View
---@field x? integer
---@field y? integer

---@param root gui.View
---@return table
function PointerContext.new(root)
    assert(root, 'DwarfUI PointerContext requires a root view.')
    return setmetatable({root=root, target=nil, result=miss()}, PointerContext)
end

---@class dwarfui.PointerDispatcher
PointerDispatcher = {}

---@param root gui.View
---@param x integer
---@param y integer
---@return table
function PointerDispatcher.resolve(root, x, y)
    if not is_eligible(root) or not body_contains(root, x, y) then
        return miss()
    end
    for index = #(root.subviews or {}), 1, -1 do
        local result = resolve_view(root.subviews[index], x, y)
        if result.kind ~= PointerResultKind.MISS then return result end
    end
    return miss()
end

---@param context table
---@param ... integer Optional x and y coordinates. When omitted, samples once.
---@return table
function PointerDispatcher.sample(context, ...)
    assert(context and context.root,
        'DwarfUI PointerDispatcher.sample requires a PointerContext.')
    local coordinate_count = select('#', ...)
    local x, y = ...
    if coordinate_count == 0 then
        x, y = dfhack.screen.getMousePos()
    end
    if x == nil or y == nil then
        x, y = nil, nil
    end

    local result = x and y and
        PointerDispatcher.resolve(context.root, x, y) or miss()
    local previous = context.target
    local target = result.kind == PointerResultKind.TARGET and
        result.target or nil

    if previous ~= target then
        if previous and previous.on_pointer_leave then
            previous.on_pointer_leave(previous)
        end
        if target and target.on_pointer_enter then
            target.on_pointer_enter(target, result.x, result.y)
        end
    end
    if target and target.on_pointer_update then
        target.on_pointer_update(target, result.x, result.y)
    end

    context.target = target
    context.result = result
    return result
end
