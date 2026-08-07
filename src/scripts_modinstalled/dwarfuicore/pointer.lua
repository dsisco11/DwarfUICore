--@ module=true

local classifier_module = reqscript(
    'dwarfuicore/input_event/pointer_obstruction_classifier')
local gui_view_pointer_obstruction_classifier = reqscript(
    'dwarfuicore/input_event/gui_view_pointer_obstruction_classifier')
local native_ui_pointer_obstruction_classifier = reqscript(
    'dwarfuicore/input_event/native_ui_pointer_obstruction_classifier')

---@enum dwarfuicore.PointerPolicy
PointerPolicy = classifier_module.PointerPolicy

---@enum dwarfuicore.PointerClassificationKind
PointerClassificationKind = classifier_module.PointerClassificationKind

---@class dwarfuicore.PointerObstructionClassifier
PointerObstructionClassifier = classifier_module.PointerObstructionClassifier

---@class dwarfuicore.GuiViewPointerObstructionClassifier
GuiViewPointerObstructionClassifier =
    gui_view_pointer_obstruction_classifier.GuiViewPointerObstructionClassifier

---@class dwarfuicore.NativeUiPointerObstructionClassifier
NativeUiPointerObstructionClassifier =
    native_ui_pointer_obstruction_classifier.NativeUiPointerObstructionClassifier

---@return dwarfuicore.PointerClassification
local function miss()
    return classifier_module.classification(PointerClassificationKind.MISS)
end

---@class dwarfuicore.PointerContext
---@field root gui.View
---@field target gui.View|nil
---@field result dwarfuicore.PointerClassification
PointerContext = {}
PointerContext.__index = PointerContext

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
    local classifier = GuiViewPointerObstructionClassifier
    if type(root) == 'userdata' then
        classifier = NativeUiPointerObstructionClassifier
    end

    return classifier_module.PointerObstructionClassifier.invoke({
        _classify=classifier._classify,
    }, root, {x=x, y=y})
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

    local result = x and y and PointerDispatcher.resolve(context.root, x, y) or miss()
    local previous = context.target

    if result.kind == PointerClassificationKind.UNKNOWN then
        context.result = result
        return result
    end

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
