--@ module=true

local classifier_module = reqscript(
    'dwarfuicore/input_event/pointer_obstruction_classifier')
local identities = reqscript('dwarfuicore/service_provider/identity')

local PointerObstructionClassifier = classifier_module.PointerObstructionClassifier
local PointerPolicy = classifier_module.PointerPolicy
local PointerClassificationKind = classifier_module.PointerClassificationKind
local classification = classifier_module.classification

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

---@class dwarfuicore.GuiViewPointerObstructionClassifier : dwarfuicore.PointerObstructionClassifier
---@field _classify fun(self: dwarfuicore.GuiViewPointerObstructionClassifier, root: table|userdata, screen_position: dwarfuicore.Position2D): dwarfuicore.PointerClassification
GuiViewPointerObstructionClassifier = {}
setmetatable(GuiViewPointerObstructionClassifier, {__index=PointerObstructionClassifier})
GuiViewPointerObstructionClassifier.__index = GuiViewPointerObstructionClassifier

---@param root table|userdata
---@param screen_position dwarfuicore.Position2D
---@return dwarfuicore.PointerClassification
function GuiViewPointerObstructionClassifier._classify(self, root, screen_position)
    local x = screen_position.x
    local y = screen_position.y
    if not is_eligible(root) or not body_contains(root, x, y) then
        return miss()
    end
    for index = #(root.subviews or {}), 1, -1 do
        local result = resolve_view(root.subviews[index], x, y)
        if result.kind ~= PointerClassificationKind.MISS then return result end
    end
    return miss()
end

return {
    GuiViewPointerObstructionClassifier=GuiViewPointerObstructionClassifier,
    miss=miss,
    blocked=blocked,
    targeted=targeted,
    is_eligible=is_eligible,
    resolve_view=resolve_view,
}
