--@ module=true

-- Conservative generic proof that a screen point is unobstructed by UI.

local pointer = reqscript('dwarfuicore/pointer')
local gui_view_pointer_obstruction_classifier = reqscript(
    'dwarfuicore/input_event/gui_view_pointer_obstruction_classifier')
local native_ui_pointer_obstruction_classifier = reqscript(
    'dwarfuicore/input_event/native_ui_pointer_obstruction_classifier')
local ui_root_collector = reqscript('dwarfuicore/input_event/ui_root_collector')

local PointerObstructionClassifier = pointer.PointerObstructionClassifier
local PointerClassificationKind = pointer.PointerClassificationKind
local GuiViewPointerObstructionClassifier =
    gui_view_pointer_obstruction_classifier.GuiViewPointerObstructionClassifier
local NativeUiPointerObstructionClassifier =
    native_ui_pointer_obstruction_classifier.NativeUiPointerObstructionClassifier
local UiRootKind = ui_root_collector.UiRootKind

---@class dwarfuicore.InputEventUiObstructionResolver
InputEventUiObstructionResolver = {}
InputEventUiObstructionResolver._diagnostic = nil

local gui_classifier = setmetatable({}, {__index=GuiViewPointerObstructionClassifier})
local native_classifier = setmetatable({}, {__index=NativeUiPointerObstructionClassifier})

---@param message string
---@param kind string
---@param detail any
local function set_diagnostic(message, kind, detail)
    InputEventUiObstructionResolver._diagnostic = {
        kind=kind,
        message=message,
        detail=detail,
    }
end

---@param descriptor table
---@param screen_position dwarfuicore.Position2D
---@return dwarfuicore.PointerClassification
local function resolve_descriptor(descriptor, screen_position)
    if type(descriptor) ~= 'table' then
        set_diagnostic('root descriptor is invalid', 'unsupported_kind', nil)
        return {kind=PointerClassificationKind.UNKNOWN}
    end
    local classifier
    if descriptor.kind == UiRootKind.NATIVE_WIDGET_TREE then
        classifier = native_classifier
    elseif descriptor.kind == UiRootKind.LUA_VIEW or
            descriptor.kind == UiRootKind.OVERLAY_VIEW or
            descriptor.kind == UiRootKind.CORE_REGISTERED_VIEW then
        classifier = gui_classifier
    else
        set_diagnostic('root descriptor has unsupported kind', 'unsupported_kind',
            descriptor.kind)
        return {kind=PointerClassificationKind.UNKNOWN}
    end
    return PointerObstructionClassifier.invoke(classifier,
        descriptor.root, screen_position)
end

---Returns whether every supplied root can be inspected and none owns the point.
---@param roots table[]|nil
---@param screen_position dwarfuicore.Position2D|nil
---@return boolean unobstructed
function InputEventUiObstructionResolver.is_unobstructed(roots, screen_position)
    if type(roots) ~= 'table' or type(screen_position) ~= 'table' then
        return false
    end
    local unobstructed = true
    for _, descriptor in ipairs(roots) do
        local result = resolve_descriptor(descriptor, screen_position)
        if type(result) ~= 'table' then
            set_diagnostic('root classification produced malformed result',
                'classifier_traversal_failure', descriptor)
            return false
        end
        if result.kind == PointerClassificationKind.TARGET or
                result.kind == PointerClassificationKind.BLOCKED then
            set_diagnostic('target root blocked pointer resolution',
                'positive_obstruction', descriptor)
            return false
        end
        if result.kind == PointerClassificationKind.UNKNOWN then
            unobstructed = false
        end
    end
    return unobstructed
end

---@return table|nil
function InputEventUiObstructionResolver.get_diagnostic()
    return InputEventUiObstructionResolver._diagnostic
end
