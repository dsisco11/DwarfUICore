--@ module=true

local classifier_module = reqscript(
    'dwarfuicore/input_event/pointer_obstruction_classifier')
local identities = reqscript('dwarfuicore/service_provider/identity')

local PointerObstructionClassifier = classifier_module.PointerObstructionClassifier
local PointerPolicy = classifier_module.PointerPolicy
local PointerClassificationKind = classifier_module.PointerClassificationKind
local classification = classifier_module.classification
local is_integer = classifier_module.is_integer

local function blocked(view)
    return classification(PointerClassificationKind.BLOCKED, view)
end

local NATIVE_WIDGET_POLICIES = classifier_module.immutable_result({
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

---@param widget table
---@param field string
---@return any
local function read_field(widget, field)
    local value = widget[field]
    if type(value) == 'function' then value = value(widget) end
    return value
end

---@param widget table
---@param field string
---@return boolean|nil value
---@return string|nil reason
local function read_boolean(widget, field)
    local value = read_field(widget, field)
    if value == nil then return true, nil end
    if type(value) == 'function' then value = value(widget) end
    if type(value) == 'boolean' then return value, nil end
    return nil, 'non-boolean ' .. field
end

local function is_global_positioning(widget)
    local flags = read_field(widget, 'flag') or read_field(widget, 'flags')
    if type(flags) == 'table' and flags.GLOBAL_POSITIONING ~= nil then
        return flags.GLOBAL_POSITIONING == true
    end
    return false
end

---@param widget table
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
    local raw_clip = raw.clip or raw.clip_rect
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

---@param value table|nil
---@param x integer
---@param y integer
---@return boolean
local function inside(value, x, y)
    if value == nil then return false end
    if x < value.x1 or x > value.x2 or y < value.y1 or y > value.y2 then
        return false
    end
    if value.clip == nil then return true end
    return x >= value.clip.x1 and x <= value.clip.x2 and
        y >= value.clip.y1 and y <= value.clip.y2
end

---@param widget table
---@return string|nil
local function get_type_name(widget)
    return read_field(widget, 'type') or read_field(widget, '_type') or
        read_field(widget, 'get_type')
end

local function is_interactive_policy(policy)
    return policy == PointerPolicy.TARGET or policy == PointerPolicy.BLOCK
end

---@param widget table
---@return table[]|nil
local function get_children(widget)
    local children = read_field(widget, 'children') or
        read_field(widget, 'subviews') or
        read_field(widget, 'widgets')
    if type(children) == 'function' then
        children = children(widget)
    end
    return type(children) == 'table' and children or nil
end

---@param self dwarfuicore.NativeUiPointerObstructionClassifier
---@param widget table
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

---@class dwarfuicore.NativeUiPointerObstructionClassifier : dwarfuicore.PointerObstructionClassifier
---@field _classify fun(self: dwarfuicore.NativeUiPointerObstructionClassifier, root: table|userdata, screen_position: dwarfuicore.Position2D): dwarfuicore.PointerClassification
NativeUiPointerObstructionClassifier = {}
setmetatable(NativeUiPointerObstructionClassifier, {__index=PointerObstructionClassifier})
NativeUiPointerObstructionClassifier.__index = NativeUiPointerObstructionClassifier

---Returns the resolver policy for one native type name.
---@param widget table
---@param type_name string|nil
---@return dwarfuicore.PointerPolicy|nil
function NativeUiPointerObstructionClassifier._policy_for_type(widget, type_name)
    local policy = NATIVE_WIDGET_POLICIES[type_name]
    if policy ~= nil then
        return policy
    end
    return has_key_activate(widget) and PointerPolicy.TARGET or nil
end

---@param widget table
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
        return classification(PointerClassificationKind.MISS)
    end
    if not ancestor_visible or not ancestor_active or not active or not visible then
        return classification(PointerClassificationKind.MISS)
    end

    local rect = resolve_rect(widget, ancestor_origin)
    if policy == nil then
        if rect == nil then return classification(PointerClassificationKind.MISS) end
        if not inside(rect, x, y) then return classification(PointerClassificationKind.MISS) end
        local child_result = classify_native_children(self, widget, screen_position,
            {x=rect.x1, y=rect.y1}, true, true)
        if child_result ~= nil then return child_result end
        return classification(PointerClassificationKind.MISS)
    end

    if rect == nil then
        if is_interactive_policy(policy) then
            return classification(PointerClassificationKind.UNKNOWN)
        end
        return classification(PointerClassificationKind.MISS)
    end

    local origin = {x=rect.x1, y=rect.y1}
    if policy == PointerPolicy.NONE then
        return classification(PointerClassificationKind.MISS)
    end
    if policy == PointerPolicy.TARGET then
        if inside(rect, x, y) then
            return classification(PointerClassificationKind.TARGET, widget,
                identities.Position2D.new({x = x - rect.x1, y = y - rect.y1}))
        end
        return classification(PointerClassificationKind.MISS)
    end
    if policy == PointerPolicy.BLOCK then
        local child_result = classify_native_children(self, widget, screen_position,
            origin, true, true)
        if child_result ~= nil then return child_result end
        if inside(rect, x, y) then
            return blocked(widget)
        end
        return classification(PointerClassificationKind.MISS)
    end
    if policy == PointerPolicy.PASS then
        if not inside(rect, x, y) then return classification(PointerClassificationKind.MISS) end
        local child_result = classify_native_children(self, widget, screen_position,
            origin, true, true)
        if child_result ~= nil then return child_result end
        return classification(PointerClassificationKind.MISS)
    end
    return classification(PointerClassificationKind.MISS)
end

return {
    NativeUiPointerObstructionClassifier=NativeUiPointerObstructionClassifier,
    NATIVE_WIDGET_POLICIES=NATIVE_WIDGET_POLICIES,
    _policy_for_type=NativeUiPointerObstructionClassifier._policy_for_type,
}
