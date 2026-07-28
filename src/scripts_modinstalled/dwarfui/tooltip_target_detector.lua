--@ module=true

-- Tooltip target detection is intentionally presentation-independent. It
-- consumes pointer samples and weak registrations, but never creates or
-- queries a tooltip renderer, screen, or overlay host.

local overlay = require('plugins.overlay')
local pointer = reqscript('dwarfui/pointer')

---@class dwarfui.TooltipPointerObservation
---@field sequence integer
---@field kind '"target"'|'"blocked"'|'"miss"'
---@field pointer_x integer|nil
---@field pointer_y integer|nil
---@field target gui.View|nil
---@field local_x integer|nil
---@field local_y integer|nil
---@field root gui.View|nil

---@alias dwarfui.TooltipRootPresentationPredicate fun(root: gui.View): boolean

---@class dwarfui.TooltipTargetDetectorOptions
---@field registrations table<gui.View, table>
---@field resolve fun(root: gui.View, x: integer, y: integer): table|nil
---@field is_non_overlay_root_presented dwarfui.TooltipRootPresentationPredicate|nil

---@class dwarfui.TooltipTargetCandidate
---@field target gui.View
---@field root gui.View
---@field local_x integer
---@field local_y integer
---@field sequence integer

---@class dwarfui.TooltipBlockedCandidate
---@field root gui.View
---@field sequence integer

---@class dwarfui.TooltipTargetDetector
---@field _registrations table<gui.View, table>
---@field _resolve fun(root: gui.View, x: integer, y: integer): table
---@field _is_non_overlay_root_presented dwarfui.TooltipRootPresentationPredicate
TooltipTargetDetector = {}
TooltipTargetDetector.__index = TooltipTargetDetector

---Returns the DFHack class table for an instance in production or tests.
---@param instance table
---@return table|nil
local function get_instance_class(instance)
    local class = getmetatable(instance)
    if class and rawget(class, 'super') == nil and
            type(rawget(class, '__index')) == 'table' then
        class = rawget(class, '__index')
    end
    return class
end

---Returns whether an instance inherits from the requested DFHack class.
---@param instance table
---@param expected table
---@return boolean
local function is_instance(instance, expected)
    local class = get_instance_class(instance)
    while class do
        if class == expected then return true end
        class = rawget(class, 'super')
    end
    return false
end

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

---Returns an eligible attached root for a registered control.
---@param widget gui.View
---@return gui.View|nil
local function find_eligible_root(widget)
    local current = widget
    local seen = {}
    local attached = false
    while current and not seen[current] do
        seen[current] = true
        if not getval(current.visible) or not getval(current.active) then
            return nil
        end
        local parent = current.parent_view
        if not parent then return attached and current or nil end
        if not parent_contains_child(parent, current) then return nil end
        attached = true
        current = parent
    end
    return nil
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

---Recognizes the root borrowed by the current native DF viewscreen.
---@param root gui.View
---@return boolean
local function default_non_overlay_root_is_presented(root)
    local current = dfhack.gui.getDFViewscreen(true)
    if not current then return false end
    -- Older/custom hosts do not always expose widgets. They retain the
    -- established attached-root behavior, while native DwarfSpec roots use
    -- the authoritative widgets identity characterized by the live probe.
    return current.widgets == nil or current.widgets == root
end

---Returns whether a discovered root has current layout and presentation state.
---@param detector dwarfui.TooltipTargetDetector
---@param root gui.View
---@return boolean
local function root_is_eligible(detector, root)
    if not root.frame_body then return false end
    if is_instance(root, overlay.OverlayWidget) then
        return overlay_root_is_presented(root)
    end
    return detector._is_non_overlay_root_presented(root)
end

---Builds a presentation-neutral observation.
---@param sample dwarfui.PointerSample
---@param kind '"target"'|'"blocked"'|'"miss"'
---@param candidate dwarfui.TooltipTargetCandidate|dwarfui.TooltipBlockedCandidate|nil
---@return dwarfui.TooltipPointerObservation
local function observation(sample, kind, candidate)
    candidate = candidate or {}
    return {
        sequence=sample.sequence,
        kind=kind,
        pointer_x=sample.x,
        pointer_y=sample.y,
        target=candidate.target,
        local_x=candidate.local_x,
        local_y=candidate.local_y,
        root=candidate.root,
    }
end

---Selects the later registered candidate for deterministic cross-root order.
---@generic T: dwarfui.TooltipTargetCandidate|dwarfui.TooltipBlockedCandidate
---@param current T|nil
---@param candidate T
---@return T
function TooltipTargetDetector.prefer_later_registration(current, candidate)
    if not current or candidate.sequence > current.sequence then
        return candidate
    end
    return current
end

---Creates a detector over a caller-owned weak registration table.
---@param options dwarfui.TooltipTargetDetectorOptions
---@return dwarfui.TooltipTargetDetector
function TooltipTargetDetector.new(options)
    assert(type(options) == 'table',
        'DwarfUI tooltip target detector requires dependency options.')
    assert(type(options.registrations) == 'table',
        'DwarfUI tooltip target detector requires registrations.')
    assert(options.resolve == nil or type(options.resolve) == 'function',
        'DwarfUI tooltip target detector resolver must be a function.')
    assert(options.is_non_overlay_root_presented == nil or
        type(options.is_non_overlay_root_presented) == 'function',
        'DwarfUI non-overlay root predicate must be a function.')
    return setmetatable({
        _registrations=options.registrations,
        _resolve=options.resolve or pointer.PointerDispatcher.resolve,
        _is_non_overlay_root_presented=
            options.is_non_overlay_root_presented or
            default_non_overlay_root_is_presented,
    }, TooltipTargetDetector)
end

---Detects exactly one target, blocked region, or miss for one pointer sample.
---@param sample dwarfui.PointerSample
---@return dwarfui.TooltipPointerObservation
function TooltipTargetDetector:detect(sample)
    assert(type(sample) == 'table',
        'DwarfUI tooltip target detector requires a pointer sample.')
    assert(type(sample.sequence) == 'number',
        'DwarfUI pointer sample sequence must be a number.')
    if sample.x == nil or sample.y == nil then
        return observation(sample, 'miss')
    end

    local roots = {}
    for widget, registration in pairs(self._registrations) do
        local root = find_eligible_root(widget)
        if root and root_is_eligible(self, root) then
            local sequence = registration.sequence
            local existing = roots[root]
            if not existing or sequence > existing then
                roots[root] = sequence
            end
        end
    end

    local winner
    local blocked
    for root, root_sequence in pairs(roots) do
        local result = self._resolve(root, sample.x, sample.y)
        if result.kind == 'target' then
            local registration = self._registrations[result.target]
            if registration then
                winner = TooltipTargetDetector.prefer_later_registration(
                    winner, {
                        target=result.target,
                        root=root,
                        local_x=result.x,
                        local_y=result.y,
                        sequence=registration.sequence,
                    })
            end
        elseif result.kind == 'blocked' then
            blocked = TooltipTargetDetector.prefer_later_registration(
                blocked, {root=root, sequence=root_sequence})
        end
    end

    if winner then return observation(sample, 'target', winner) end
    if blocked then return observation(sample, 'blocked', blocked) end
    return observation(sample, 'miss')
end
