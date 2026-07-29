--@ module=true

-- Shared tooltip-owner root discovery and presentation eligibility.

local overlay = require('plugins.overlay')
local class_helpers = reqscript('dwarfui/class')

---@alias dwarfui.TooltipRootPresentationPredicate fun(root: gui.View): boolean

---@class dwarfui.TooltipRootResolverOptions
---@field is_non_overlay_root_presented dwarfui.TooltipRootPresentationPredicate|nil

---@class dwarfui.TooltipRootResolver
---@field _is_non_overlay_root_presented dwarfui.TooltipRootPresentationPredicate
TooltipRootResolver = {}
TooltipRootResolver.__index = TooltipRootResolver

---Evaluates a DFHack boolean or boolean callback.
---@param value boolean|function|nil
---@return boolean
local function getval(value)
    if type(value) == 'function' then return value() end
    return not not value
end

---Returns whether a parent still contains a child by identity.
---@param parent gui.View
---@param child gui.View
---@return boolean
local function parent_contains_child(parent, child)
    for _, candidate in ipairs(parent.subviews or {}) do
        if candidate == child then return true end
    end
    return false
end

---Returns whether an overlay declares the current native viewscreen.
---@param root gui.View
---@return boolean
local function overlay_matches_current_viewscreen(root)
    local current = dfhack.gui.getDFViewscreen(true)
    if not current then return false end
    for _, focus in ipairs(overlay.normalize_list(root.viewscreens)) do
        if focus == 'all' or dfhack.gui.matchFocusString(
                overlay.simplify_viewscreen_name(focus), current) then
            return true
        end
    end
    return false
end

---Returns whether an overlay is its enabled registry-owned instance.
---@param root gui.View
---@return boolean
local function overlay_root_is_presented(root)
    if not root.name or not overlay.isOverlayEnabled(root.name) then
        return false
    end
    local entry = overlay.get_state().db[root.name]
    return entry ~= nil and entry.widget == root and
        overlay_matches_current_viewscreen(root)
end

---Recognizes a current Lua screen or the root borrowed by the native screen.
---@param root gui.View
---@return boolean
local function default_non_overlay_root_is_presented(root)
    local screen_native = rawget(root, '_native')
    if screen_native ~= nil then
        return dfhack.gui.getCurViewscreen(true) == screen_native
    end
    local native = dfhack.gui.getDFViewscreen(true)
    if not native then return false end
    -- Older/custom hosts do not always expose widgets. They retain the
    -- established attached-root behavior, while native DwarfSpec roots use
    -- the authoritative widgets identity characterized by the live probe.
    return native.widgets == nil or native.widgets == root
end

---Creates a resolver with an injectable non-overlay presentation predicate.
---@param options dwarfui.TooltipRootResolverOptions|nil
---@return dwarfui.TooltipRootResolver
function TooltipRootResolver.new(options)
    options = options or {}
    assert(type(options) == 'table',
        'DwarfUI tooltip root resolver options must be a table.')
    assert(options.is_non_overlay_root_presented == nil or
        type(options.is_non_overlay_root_presented) == 'function',
        'DwarfUI non-overlay root predicate must be a function.')
    return setmetatable({
        _is_non_overlay_root_presented=
            options.is_non_overlay_root_presented or
            default_non_overlay_root_is_presented,
    }, TooltipRootResolver)
end

---Finds a visible and active owner root through authoritative parent links.
---Direct root ownership is accepted only when requested by a non-widget target.
---@param owner gui.View
---@param allow_owner_root boolean|nil
---@return gui.View|nil
function TooltipRootResolver:find_root(owner, allow_owner_root)
    if type(owner) ~= 'table' then return nil end
    local current = owner
    local seen = {}
    local attached = false
    while current and not seen[current] do
        seen[current] = true
        if not getval(current.visible) or not getval(current.active) then
            return nil
        end
        local parent = current.parent_view
        if not parent then
            return (attached or allow_owner_root) and current or nil
        end
        if not parent_contains_child(parent, current) then return nil end
        attached = true
        current = parent
    end
    return nil
end

---Returns whether a discovered root is laid out and currently presented.
---@param root gui.View
---@return boolean
function TooltipRootResolver:is_presented(root)
    if type(root) ~= 'table' or not root.frame_body then return false end
    if class_helpers.is_instance_of(root, overlay.OverlayWidget) then
        return overlay_root_is_presented(root)
    end
    return self._is_non_overlay_root_presented(root)
end

---Resolves one owner to its currently eligible presentation root.
---@param owner gui.View
---@param allow_owner_root boolean|nil
---@return gui.View|nil
function TooltipRootResolver:resolve(owner, allow_owner_root)
    local root = self:find_root(owner, allow_owner_root)
    return root and self:is_presented(root) and root or nil
end

resolver = TooltipRootResolver.new()
