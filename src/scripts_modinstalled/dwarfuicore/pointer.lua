--@ module=true

-- Generic pointer targeting deliberately has no tooltip dependency.

local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')
local identities = reqscript('dwarfuicore/service_provider/identity')

---@enum dwarfuicore.PointerPolicy
PointerPolicy = immutable_enum.define({
    TARGET=1,
    PASS=2,
    BLOCK=3,
    NONE=4,
}, 'PointerPolicy')

---@enum dwarfuicore.PointerClassificationKind
PointerClassificationKind = immutable_enum.define({
    TARGET=1,
    BLOCKED=2,
    MISS=3,
    UNKNOWN=4,
}, 'PointerClassificationKind')

---Returns a read-only pointer-classification payload.
---@param values table
---@return dwarfuicore.PointerClassification result
local function immutable_result(values)
    return setmetatable(values, {
        __newindex=function()
            error('DwarfUICore pointer classifications are immutable.', 2)
        end,
        __pairs=function()
            return next, values, nil
        end,
        __metatable=false,
    })
end

---Creates one pointer classification payload and validates required fields.
---@param kind dwarfuicore.PointerClassificationKind
---@param subject any
---@param local_position dwarfuicore.Position2D|nil
---@return dwarfuicore.PointerClassification result
local function classification(kind, subject, local_position)
    assert(kind == PointerClassificationKind.TARGET or
            kind == PointerClassificationKind.BLOCKED or
            kind == PointerClassificationKind.MISS or
            kind == PointerClassificationKind.UNKNOWN,
        'DwarfUICore pointer classification kind is invalid.')
    if kind == PointerClassificationKind.TARGET then
        assert(subject ~= nil,
            'DwarfUICore pointer target classifications require a subject.')
        assert(local_position ~= nil and
                local_position.x ~= nil and local_position.y ~= nil and
                math.type(local_position.x) == 'integer' and
                math.type(local_position.y) == 'integer',
            'DwarfUICore pointer target classifications require local_position.')
        return immutable_result({
            kind=kind,
            subject=subject,
            local_position=local_position,
        })
    end
    if kind == PointerClassificationKind.BLOCKED then
        assert(subject ~= nil,
            'DwarfUICore pointer-blocked classifications require a subject.')
        assert(local_position == nil,
            'DwarfUICore pointer-blocked classifications forbid local_position.')
        return immutable_result({
            kind=kind,
            subject=subject,
            local_position=nil,
        })
    end
    assert(subject == nil,
        'DwarfUICore miss and unknown classifications require no subject.')
    assert(local_position == nil,
        'DwarfUICore miss and unknown classifications require no local_position.')
    return immutable_result({
        kind=kind,
        subject=nil,
        local_position=nil,
    })
end

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

---Returns a pointer miss classification.
---@return dwarfuicore.PointerClassification
local function miss()
    return classification(PointerClassificationKind.MISS)
end

---Returns a pointer blocked classification.
---@param view gui.View
---@return dwarfuicore.PointerClassification
local function blocked(view)
    return classification(PointerClassificationKind.BLOCKED, view)
end

---Returns a pointer target classification with target-local coordinates.
---@param view gui.View
---@param x integer
---@param y integer
---@return dwarfuicore.PointerClassification
local function targeted(view, x, y)
    local local_x, local_y = view.frame_body:localXY(x, y)
    local local_position = identities.Position2D.new({
        x=local_x,
        y=local_y,
    })
    return classification(PointerClassificationKind.TARGET, view, local_position)
end

---Resolves one eligible view and its descendants at a screen coordinate.
---@param view gui.View
---@param x integer
---@param y integer
---@return dwarfuicore.PointerClassification
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
        'DwarfUICore invalid pointer_policy ' .. tostring(policy) ..
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
            if result.kind ~= PointerClassificationKind.MISS then return result end
        end
    end

    if policy == PointerPolicy.BLOCK and inside_frame then
        return blocked(view)
    end
    return miss()
end

---@class dwarfuicore.PointerContext
---@field root gui.View
---@field target gui.View|nil
---@field result dwarfuicore.PointerClassification
PointerContext = {}
PointerContext.__index = PointerContext

---@class dwarfuicore.PointerClassification
---@field kind dwarfuicore.PointerClassificationKind
---@field subject? any
---@field local_position? dwarfuicore.Position2D

---@param root gui.View
---@return dwarfuicore.PointerContext
function PointerContext.new(root)
    assert(root, 'DwarfUICore PointerContext requires a root view.')
    return setmetatable({root=root, target=nil, result=miss()}, PointerContext)
end

---@class dwarfuicore.PointerDispatcher
PointerDispatcher = {}

---@param root gui.View
---@param x integer
---@param y integer
---@return dwarfuicore.PointerClassification
function PointerDispatcher.resolve(root, x, y)
    if not is_eligible(root) or not body_contains(root, x, y) then
        return miss()
    end
    for index = #(root.subviews or {}), 1, -1 do
        local result = resolve_view(root.subviews[index], x, y)
        if result.kind ~= PointerClassificationKind.MISS then return result end
    end
    return miss()
end

---@param context table
---@param ... integer Optional x and y coordinates. When omitted, samples once.
---@return dwarfuicore.PointerClassification
function PointerDispatcher.sample(context, ...)
    assert(context and context.root,
        'DwarfUICore PointerDispatcher.sample requires a PointerContext.')
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
    local target = result.kind == PointerClassificationKind.TARGET and
        result.subject or nil
    local local_position = result.local_position

    if previous ~= target then
        if previous and previous.on_pointer_leave then
            previous.on_pointer_leave(previous)
        end
        if target and target.on_pointer_enter then
            target.on_pointer_enter(target,
                local_position and local_position.x, local_position and local_position.y)
        end
    end
    if target and target.on_pointer_update then
        target.on_pointer_update(target,
            local_position and local_position.x, local_position and local_position.y)
    end

    context.target = target
    context.result = result
    return result
end

-- Backward-compatible migration support.
PointerResultKind = PointerClassificationKind
