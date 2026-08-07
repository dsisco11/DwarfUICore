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

---Returns one immutable copy of a diagnostic record.
---@param kind string
---@param message string|nil
---@return table
local function new_diagnostic(kind, message)
    return setmetatable({
        kind = kind,
        message = message,
    }, {
        __newindex=function()
            error('DwarfUICore pointer diagnostics are immutable.', 2)
        end,
        __metatable=false,
    })
end

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

---@class dwarfuicore.PointerObstructionClassifier
PointerObstructionClassifier = {}
PointerObstructionClassifier.__index = PointerObstructionClassifier

---Returns true when a value is an integer number.
---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == 'number' and math.type(value) == 'integer'
end

---Copies an immutable diagnostic object to this classifier instance.
---@param self dwarfuicore.PointerObstructionClassifier
---@param message table|nil
local function set_diagnostic(self, message)
    self._diagnostic = message
end

---Normalizes and validates one classifier result as canonical classification output.
---@param result any
---@return dwarfuicore.PointerClassification|nil result
---@return string|nil reason
local function normalize_result(result)
    if type(result) ~= 'table' then
        return nil, 'classifier returned non-table result'
    end
    local ok, normalized = pcall(classification, result.kind,
        result.subject, result.local_position)
    if not ok then
        return nil, tostring(normalized)
    end
    return normalized, nil
end

---Returns a non-throwing, validated classifier invocation.
---@param self dwarfuicore.PointerObstructionClassifier
---@param root table|userdata
---@param screen_position dwarfuicore.Position2D
---@return dwarfuicore.PointerClassification
function PointerObstructionClassifier.invoke(self, root, screen_position)
    if type(self) ~= 'table' then
        return classification(PointerClassificationKind.UNKNOWN)
    end

    if type(root) ~= 'table' and type(root) ~= 'userdata' then
        set_diagnostic(self, new_diagnostic(
            'validation', 'invalid root'))
        return classification(PointerClassificationKind.UNKNOWN)
    end

    if type(screen_position) ~= 'table' or
            not is_integer(screen_position.x) or
            not is_integer(screen_position.y) then
        set_diagnostic(self, new_diagnostic(
            'validation', 'invalid screen_position'))
        return classification(PointerClassificationKind.UNKNOWN)
    end

    if type(self._classify) ~= 'function' then
        set_diagnostic(self, new_diagnostic(
            'validation', 'classifier implementation is missing _classify'))
        return classification(PointerClassificationKind.UNKNOWN)
    end

    set_diagnostic(self, nil)
    local ok, result = pcall(self._classify, self, root, screen_position)
    if not ok then
        set_diagnostic(self, new_diagnostic('invocation', tostring(result)))
        return classification(PointerClassificationKind.UNKNOWN)
    end

    local normalized, reason = normalize_result(result)
    if not normalized then
        set_diagnostic(self, new_diagnostic('malformed', reason))
        return classification(PointerClassificationKind.UNKNOWN)
    end

    set_diagnostic(self, nil)
    return normalized
end

---Returns the latest immutable diagnostic for this classifier.
---@param self dwarfuicore.PointerObstructionClassifier
---@return table|nil
function PointerObstructionClassifier.get_diagnostic(self)
    return type(self) == 'table' and self._diagnostic or nil
end

local function getval(value)
    if type(value) == 'function' then return value() end
    return value
end

---@class dwarfuicore.GuiViewPointerObstructionClassifier : dwarfuicore.PointerObstructionClassifier
---@field _classify fun(self: dwarfuicore.GuiViewPointerObstructionClassifier, root: table|userdata, screen_position: dwarfuicore.Position2D): dwarfuicore.PointerClassification
GuiViewPointerObstructionClassifier = {}
setmetatable(GuiViewPointerObstructionClassifier, {__index = PointerObstructionClassifier})
GuiViewPointerObstructionClassifier.__index = GuiViewPointerObstructionClassifier

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

---@class dwarfuicore.NativeUiPointerObstructionClassifier : dwarfuicore.PointerObstructionClassifier
---@field _classify fun(self: dwarfuicore.NativeUiPointerObstructionClassifier, root: table|userdata, screen_position: dwarfuicore.Position2D): dwarfuicore.PointerClassification
NativeUiPointerObstructionClassifier = {}
setmetatable(NativeUiPointerObstructionClassifier, {__index=PointerObstructionClassifier})
NativeUiPointerObstructionClassifier.__index = NativeUiPointerObstructionClassifier

local NATIVE_WIDGET_POLICIES = immutable_result({
    ['widget_better_button']=PointerPolicy.TARGET,
    ['widget_interface_main_button']=PointerPolicy.TARGET,
    ['widget_interface_pets_livestock_button']=PointerPolicy.TARGET,
    ['widget_interface_small_button']=PointerPolicy.TARGET,
    ['widget_item_sheet_button']=PointerPolicy.TARGET,
    ['widget_job_details_button']=PointerPolicy.TARGET,
    ['widget_recenter_button']=PointerPolicy.TARGET,
    ['widget_sheet_button']=PointerPolicy.TARGET,
    ['widget_unit_sheet_button']=PointerPolicy.TARGET,
    ['widget_dropdown']=PointerPolicy.TARGET,
    ['widget_filter']=PointerPolicy.TARGET,
    ['widget_folder']=PointerPolicy.TARGET,
    ['widget_menu']=PointerPolicy.TARGET,
    ['widget_radio_rows']=PointerPolicy.TARGET,
    ['widget_scroll_rows']=PointerPolicy.TARGET,
    ['widget_sort_widget']=PointerPolicy.TARGET,
    ['widget_table']=PointerPolicy.TARGET,
    ['widget_tabs']=PointerPolicy.TARGET,
    ['widget_textbox']=PointerPolicy.TARGET,
    ['widget_unit_list']=PointerPolicy.TARGET,
    ['widget_unit_sort_widget']=PointerPolicy.TARGET,
    ['widget_container']=PointerPolicy.PASS,
    ['widget_columns_container']=PointerPolicy.PASS,
    ['widget_params_container']=PointerPolicy.PASS,
    ['widget_rows_container']=PointerPolicy.PASS,
    ['widget_stack']=PointerPolicy.PASS,
    ['widget']=PointerPolicy.NONE,
    ['widget_anchored_tile']=PointerPolicy.NONE,
    ['widget_character']=PointerPolicy.NONE,
    ['widget_creature_portrait']=PointerPolicy.NONE,
    ['widget_graphics_switcher']=PointerPolicy.NONE,
    ['widget_item_name']=PointerPolicy.NONE,
    ['widget_item_portrait']=PointerPolicy.NONE,
    ['widget_keybinding_display']=PointerPolicy.NONE,
    ['widget_nineslice']=PointerPolicy.NONE,
    ['widget_nineslice_horizontal']=PointerPolicy.NONE,
    ['widget_text']=PointerPolicy.NONE,
    ['widget_text_multiline']=PointerPolicy.NONE,
    ['widget_text_truncated']=PointerPolicy.NONE,
    ['widget_unit_name']=PointerPolicy.NONE,
    ['widget_unit_portrait']=PointerPolicy.NONE,
})

---@param widget any
---@return boolean|nil value
---@return string|nil reason
local function read_boolean(widget, field)
    local value = read_field(widget, field)
    if value == nil then return true, nil end
    if type(value) == 'function' then value = value(widget) end
    if type(value) == 'boolean' then return value, nil end
    return nil, 'non-boolean ' .. field
end

---@param widget any
---@param field string
---@return any
local function read_field(widget, field)
    local value = widget[field]
    if type(value) == 'function' then value = value(widget) end
    return value
end

local function is_global_positioning(widget)
    local flags = read_field(widget, 'flag') or read_field(widget, 'flags')
    if type(flags) == 'table' and flags.GLOBAL_POSITIONING ~= nil then
        return flags.GLOBAL_POSITIONING == true
    end
    return false
end

---@param widget any
---@return boolean
local function has_key_activate(widget)
    local flags = read_field(widget, 'flag') or read_field(widget, 'flags')
    if type(flags) == 'table' and flags.CAN_KEY_ACTIVATE ~= nil then
        return flags.CAN_KEY_ACTIVATE == true
    end
    local value = read_field(widget, 'CAN_KEY_ACTIVATE')
    return value == true
end

---@param raw_rect any
---@return table|nil normalized
local function as_rect(raw_rect)
    if type(raw_rect) ~= 'table' then
        return nil
    end
    local x1 = raw_rect.x1
    local y1 = raw_rect.y1
    local x2 = raw_rect.x2
    local y2 = raw_rect.y2
    if type(x1) == 'number' and type(y1) == 'number' then
        if type(x2) == 'number' and type(y2) == 'number' then
            if is_integer(x1) and is_integer(y1) and is_integer(x2) and
                    is_integer(y2) then
                return {
                    x1=x1, y1=y1, x2=x2, y2=y2,
                }
            end
        else
            local width = raw_rect.width
            local height = raw_rect.height
            if type(width) == 'number' and type(height) == 'number' and
                    is_integer(width) and is_integer(height) then
                return {
                    x1=x1, y1=y1, x2=x1 + width - 1, y2=y1 + height - 1,
                }
            end
        end
    end
    if is_integer(raw_rect[1]) and is_integer(raw_rect[2]) and
            is_integer(raw_rect[3]) and is_integer(raw_rect[4]) then
        return {
            x1=raw_rect[1], y1=raw_rect[2],
            x2=raw_rect[3], y2=raw_rect[4],
        }
    end
    return nil
end

---@param raw any
---@return table|nil rect
local function resolve_rect(widget, parent_origin)
    local raw = read_field(widget, 'rect')
    if raw == nil then
        local getter = read_field(widget, 'get_rect')
        if type(getter) == 'function' then
            raw = getter(widget)
        else
            raw = getter
        end
    end
    local resolved = as_rect(raw)
    if not resolved then return nil end

    local is_global = is_global_positioning(widget)
    local origin_x = resolved.x1
    local origin_y = resolved.y1
    if not is_global then
        if parent_origin == nil or not is_integer(parent_origin.x) or
                not is_integer(parent_origin.y) then
            return nil
        end
        origin_x = origin_x + parent_origin.x
        origin_y = origin_y + parent_origin.y
    end
    if not is_integer(resolved.x2) or not is_integer(resolved.y2) then return nil end
    local width = resolved.x2 - resolved.x1
    local height = resolved.y2 - resolved.y1
    if width < 0 or height < 0 then return nil end

    local result = {
        x1=origin_x,
        y1=origin_y,
        x2=origin_x + width,
        y2=origin_y + height,
    }
    local raw_clip = resolved.clip or resolved.clip_rect
    local clip = as_rect(raw_clip)
    if clip then
        if is_global then
            result.clip = clip
        elseif parent_origin ~= nil then
            result.clip = {
                x1 = clip.x1 + parent_origin.x,
                y1 = clip.y1 + parent_origin.y,
                x2 = clip.x2 + parent_origin.x,
                y2 = clip.y2 + parent_origin.y,
            }
        else
            return nil
        end
    end
    return result
end

---@param value any
---@param x integer
---@param y integer
---@return boolean
local function inside(value, x, y)
    if x < value.x1 or x > value.x2 or y < value.y1 or y > value.y2 then
        return false
    end
    if value.clip == nil then return true end
    return x >= value.clip.x1 and x <= value.clip.x2 and
        y >= value.clip.y1 and y <= value.clip.y2
end

local function get_type_name(widget)
    return read_field(widget, 'type') or read_field(widget, '_type') or
        read_field(widget, 'get_type')
end

local function is_interactive_policy(policy)
    return policy == PointerPolicy.TARGET or policy == PointerPolicy.BLOCK
end

---@param widget any
---@return dwarfuicore.PointerPolicy|nil policy
function NativeUiPointerObstructionClassifier._policy_for_type(widget, type_name)
    local policy = NATIVE_WIDGET_POLICIES[type_name]
    if policy ~= nil then
        return policy
    end
    return has_key_activate(widget) and PointerPolicy.TARGET or nil
end

---@param widget any
---@return any[]|nil
local function get_children(widget)
    local children = read_field(widget, 'children') or read_field(widget, 'subviews') or
        read_field(widget, 'widgets')
    if type(children) == 'function' then
        children = children(widget)
    end
    return type(children) == 'table' and children or nil
end

---@param self dwarfuicore.NativeUiPointerObstructionClassifier
---@param widget any
---@param screen_position dwarfuicore.Position2D
---@param ancestor_origin table|nil
---@param ancestor_visible boolean
---@param ancestor_active boolean
---@return dwarfuicore.PointerClassification|nil
local function classify_native_children(self, widget, screen_position,
    ancestor_origin, ancestor_visible, ancestor_active)
    local children = get_children(widget)
    if children == nil then return nil end
    for index = #children, 1, -1 do
        local result = NativeUiPointerObstructionClassifier._classify(
            self, children[index], screen_position, ancestor_origin,
            ancestor_visible, ancestor_active)
        if result.kind ~= PointerClassificationKind.MISS then
            return result
        end
    end
    return nil
end

---@param widget any
---@param screen_position dwarfuicore.Position2D
---@param ancestor_origin table|nil
---@param ancestor_visible boolean
---@param ancestor_active boolean
---@return dwarfuicore.PointerClassification
function NativeUiPointerObstructionClassifier._classify(self, widget, screen_position,
    ancestor_origin, ancestor_visible, ancestor_active)
    local x = screen_position.x
    local y = screen_position.y
    if ancestor_origin == nil then ancestor_origin = {x=0, y=0} end
    if ancestor_visible == nil then ancestor_visible = true end
    if ancestor_active == nil then ancestor_active = true end

    local type_name = get_type_name(widget)
    local policy = NativeUiPointerObstructionClassifier._policy_for_type(
        widget, type_name)

    local active, active_error = read_boolean(widget, 'active')
    local visible, visible_error = read_boolean(widget, 'visible')
    if active_error ~= nil or visible_error ~= nil then
        if policy ~= nil and is_interactive_policy(policy) then
            return classification(PointerClassificationKind.UNKNOWN)
        end
        return miss()
    end
    if not ancestor_visible or not ancestor_active or not active or not visible then
        return miss()
    end

    local rect = resolve_rect(widget, ancestor_origin)
    if policy == nil then
        if rect == nil then return miss() end
        if not inside(rect, x, y) then return miss() end
        local child_result = classify_native_children(self, widget, screen_position,
            {x=rect.x1, y=rect.y1}, true, true)
        if child_result ~= nil then return child_result end
        return miss()
    end

    if rect == nil then
        if is_interactive_policy(policy) then
            return classification(PointerClassificationKind.UNKNOWN)
        end
        return miss()
    end

    local origin = {x=rect.x1, y=rect.y1}
    if policy == PointerPolicy.NONE then
        return miss()
    end
    if policy == PointerPolicy.TARGET then
        if inside(rect, x, y) then
            return classification(PointerClassificationKind.TARGET, widget,
                identities.Position2D.new({x = x - rect.x1, y = y - rect.y1}))
        end
        return miss()
    end
    if policy == PointerPolicy.BLOCK then
        local child_result = classify_native_children(self, widget, screen_position,
            origin, true, true)
        if child_result ~= nil then return child_result end
        if inside(rect, x, y) then
            return blocked(widget)
        end
        return miss()
    end
    if policy == PointerPolicy.PASS then
        if not inside(rect, x, y) then return miss() end
        local child_result = classify_native_children(self, widget, screen_position,
            origin, true, true)
        if child_result ~= nil then return child_result end
        return miss()
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
    local classifier = GuiViewPointerObstructionClassifier
    if type(root) == 'userdata' then
        classifier = NativeUiPointerObstructionClassifier
    end
    return classifier.invoke({
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

    local result = x and y and
        PointerDispatcher.resolve(context.root, x, y) or miss()
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
