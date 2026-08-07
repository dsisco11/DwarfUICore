--@ module=true

-- Collects the current UI roots as immutable descriptors with explicit kind.

local overlay = require('plugins.overlay')
local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')
local overlay_compatibility = reqscript(
    'dwarfuicore/input_event/overlay_feed_compatibility')

---@class dwarfuicore.InputEventUiRootCollector
InputEventUiRootCollector = {}

---@enum dwarfuicore.UiRootKind
UiRootKind = immutable_enum.define({
    NATIVE_WIDGET_TREE=1,
    LUA_VIEW=2,
    OVERLAY_VIEW=3,
    CORE_REGISTERED_VIEW=4,
}, 'UiRootKind')

---@class dwarfuicore.UiRootDescriptor
---@field kind dwarfuicore.UiRootKind
---@field root table|userdata
---@field identity string|nil

local function immutable_result(values)
    return setmetatable(values, {
        __newindex=function()
            error('DwarfUICore UI root descriptors are immutable.', 2)
        end,
        __pairs=function()
            return next, values, nil
        end,
        __metatable=false,
    })
end

---@return table|nil
local function descriptor(kind, root, identity)
    return immutable_result({
        kind=kind,
        root=root,
        identity=identity,
    })
end

local function is_generic_lua_kind(kind)
    return kind == UiRootKind.OVERLAY_VIEW or
        kind == UiRootKind.LUA_VIEW or
        kind == UiRootKind.CORE_REGISTERED_VIEW
end

local function is_collection_failure_root(root)
    local root_type = type(root)
    return root_type ~= 'table' and root_type ~= 'userdata'
end

local function native_root_kind(root)
    if type(root) == 'userdata' then return UiRootKind.NATIVE_WIDGET_TREE end
    return UiRootKind.LUA_VIEW
end

local function precedence(kind)
    if kind == UiRootKind.OVERLAY_VIEW then return 3 end
    if kind == UiRootKind.LUA_VIEW then return 2 end
    if kind == UiRootKind.CORE_REGISTERED_VIEW then return 1 end
    return 0
end

---@class dwarfuicore.InputEventUiRootCollector
InputEventUiRootCollector._diagnostic = nil

---@param message string
---@param kind string
---@param root any
local function set_diagnostic(message, kind, root)
    InputEventUiRootCollector._diagnostic = immutable_result({
        kind=kind,
        message=message,
        root=root,
    })
end

---Returns deduplicated current native, overlay, and explicitly supplied roots.
---@param current_root any
---@param additional_roots? table
---@return table[]|nil roots
function InputEventUiRootCollector.collect(current_root, additional_roots)
    InputEventUiRootCollector._diagnostic = nil
    local descriptors, seen = {}, {}
    ---@type table<table|userdata,table>
    local seen_positions = {}

    ---@param root table|userdata
    ---@param kind dwarfuicore.UiRootKind
    ---@param identity string|nil
    local function add(root, kind, identity)
        if root == nil then return true end
        if is_collection_failure_root(root) then
            set_diagnostic('unsupported root type in collection', 'collection_failure', root)
            return false
        end

        local existing = seen[root]
        local existing_position = seen_positions[root]
        if existing == nil then
            local item = descriptor(kind, root, identity)
            seen[root] = item
            seen_positions[root] = #descriptors + 1
            table.insert(descriptors, item)
            return true
        end

        if existing.kind == kind then return true end
        if is_generic_lua_kind(existing.kind) and is_generic_lua_kind(kind) then
            if precedence(kind) > precedence(existing.kind) then
                descriptors[existing_position] = descriptor(kind, root, identity)
                seen[root] = descriptors[existing_position]
            end
            return true
        end

        if existing.kind ~= UiRootKind.NATIVE_WIDGET_TREE and
                kind == UiRootKind.NATIVE_WIDGET_TREE then
            set_diagnostic('incompatible duplicate root kinds discovered',
                'unsupported_root_kind', root)
            return false
        end
        if existing.kind == UiRootKind.NATIVE_WIDGET_TREE and
                is_generic_lua_kind(kind) then
            set_diagnostic('incompatible duplicate root kinds discovered',
                'unsupported_root_kind', root)
            return false
        end
        return true
    end

    local gui = dfhack and dfhack.gui or nil
    if type(gui) ~= 'table' or type(gui.getDFViewscreen) ~= 'function' then
        set_diagnostic('root collection requires gui.getDFViewscreen',
            'collection_failure', nil)
        return nil
    end
    local native = gui.getDFViewscreen(true)
    if native == nil then
        set_diagnostic('current native viewscreen root is unavailable',
            'collection_failure', nil)
        return nil
    end
    if is_collection_failure_root(native.widgets) then
        set_diagnostic('native root is malformed', 'collection_failure', native.widgets)
        return nil
    end
    if not add(native.widgets, UiRootKind.NATIVE_WIDGET_TREE, 'native') then
        return nil
    end

    if current_root ~= nil then
        local current_kind = native_root_kind(current_root)
        if not add(current_root, current_kind, nil) then return nil end
    end

    local state = overlay.get_state()
    if type(state) ~= 'table' or type(state.db) ~= 'table' then
        set_diagnostic('overlay state is unavailable', 'collection_failure', nil)
        return nil
    end
    for name, entry in pairs(state.db) do
        if type(entry) ~= 'table' or entry.widget == nil then
            set_diagnostic('overlay state entry is malformed',
                'collection_failure', entry)
            return nil
        end
        if overlay.isOverlayEnabled(name) and
                overlay_compatibility.is_applicable_overlay_root(name,
                    entry.widget) then
            if add(entry.widget, UiRootKind.OVERLAY_VIEW, name) == false then
                return nil
            end
        end
    end
    if additional_roots ~= nil and type(additional_roots) ~= 'table' then
        set_diagnostic('additional roots must be a table when provided',
            'collection_failure', additional_roots)
        return nil
    end
    for _, root in ipairs(additional_roots or {}) do
        if not add(root, UiRootKind.CORE_REGISTERED_VIEW, nil) then
            return nil
        end
    end
    return descriptors
end

---@return table|nil
function InputEventUiRootCollector.get_diagnostic()
    return InputEventUiRootCollector._diagnostic
end

return {
    UiRootKind=UiRootKind,
    InputEventUiRootCollector=InputEventUiRootCollector,
    NATIVE_WIDGET_TREE_KIND=UiRootKind.NATIVE_WIDGET_TREE,
    LUA_VIEW_KIND=UiRootKind.LUA_VIEW,
    OVERLAY_VIEW_KIND=UiRootKind.OVERLAY_VIEW,
    CORE_REGISTERED_VIEW_KIND=UiRootKind.CORE_REGISTERED_VIEW,
}
