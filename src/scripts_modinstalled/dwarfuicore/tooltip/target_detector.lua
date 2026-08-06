--@ module=true

-- Tooltip target detection is intentionally presentation-independent. It
-- consumes pointer samples and weak registrations, but never creates or
-- queries a tooltip renderer, screen, or overlay host.

local pointer = reqscript('dwarfuicore/pointer')
local PointerResultKind = pointer.PointerResultKind
local target_types = reqscript('dwarfuicore/tooltip/target')
local ObservationKind = target_types.TooltipPointerObservationKind
local ViewRootResolver =
    reqscript('dwarfuicore/view_root_resolver').ViewRootResolver

---@class dwarfuicore.TooltipPointerObservation
---@field sequence integer
---@field kind dwarfuicore.TooltipPointerObservationKind
---@field pointer_x integer|nil
---@field pointer_y integer|nil
---@field target gui.View|nil
---@field local_x integer|nil
---@field local_y integer|nil
---@field root gui.View|nil

---@class dwarfuicore.TooltipTargetDetectorOptions
---@field registrations table<gui.View, table>
---@field resolve fun(root: gui.View, x: integer, y: integer): table|nil
---@field is_non_overlay_root_presented dwarfuicore.ViewRootPresentationPredicate|nil
---@field root_resolver dwarfuicore.ViewRootResolver|nil
---@field additional_roots fun(): table<gui.View, integer>|nil

---@class dwarfuicore.TooltipTargetCandidate
---@field target gui.View
---@field root gui.View
---@field local_x integer
---@field local_y integer
---@field sequence integer

---@class dwarfuicore.TooltipBlockedCandidate
---@field root gui.View
---@field sequence integer

---@class dwarfuicore.TooltipTargetDetector
---@field _registrations table<gui.View, table>
---@field _resolve fun(root: gui.View, x: integer, y: integer): table
---@field _root_resolver dwarfuicore.ViewRootResolver
---@field _additional_roots fun(): table<gui.View, integer>|nil
TooltipTargetDetector = {}
TooltipTargetDetector.__index = TooltipTargetDetector

---Builds a presentation-neutral observation.
---@param sample dwarfuicore.PointerSample
---@param kind dwarfuicore.TooltipPointerObservationKind
---@param candidate dwarfuicore.TooltipTargetCandidate|dwarfuicore.TooltipBlockedCandidate|nil
---@return dwarfuicore.TooltipPointerObservation
local function observation(sample, kind, candidate)
    candidate = candidate or {}
    return {
        sequence=sample.sequence,
        kind=kind,
        pointer_x=sample.screen_position and sample.screen_position.x,
        pointer_y=sample.screen_position and sample.screen_position.y,
        target=candidate.target,
        local_x=candidate.local_x,
        local_y=candidate.local_y,
        root=candidate.root,
    }
end

---Selects the later registered candidate for deterministic cross-root order.
---@generic T: dwarfuicore.TooltipTargetCandidate|dwarfuicore.TooltipBlockedCandidate
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
---@param options dwarfuicore.TooltipTargetDetectorOptions
---@return dwarfuicore.TooltipTargetDetector
function TooltipTargetDetector.new(options)
    assert(type(options) == 'table',
        'DwarfUICore tooltip target detector requires dependency options.')
    assert(type(options.registrations) == 'table',
        'DwarfUICore tooltip target detector requires registrations.')
    assert(options.resolve == nil or type(options.resolve) == 'function',
        'DwarfUICore tooltip target detector resolver must be a function.')
    assert(options.is_non_overlay_root_presented == nil or
            type(options.is_non_overlay_root_presented) == 'function',
        'DwarfUICore non-overlay root predicate must be a function.')
    assert(options.root_resolver == nil or
            type(options.root_resolver) == 'table',
        'DwarfUICore tooltip root resolver must be a table.')
    assert(options.additional_roots == nil or
            type(options.additional_roots) == 'function',
        'DwarfUICore additional tooltip roots must be provided by a function.')
    return setmetatable({
        _registrations=options.registrations,
        _resolve=options.resolve or pointer.PointerDispatcher.resolve,
        _root_resolver=options.root_resolver or ViewRootResolver.new{
            is_non_overlay_root_presented=
                options.is_non_overlay_root_presented,
        },
        _additional_roots=options.additional_roots,
    }, TooltipTargetDetector)
end

---Detects exactly one target, blocked region, or miss for one pointer sample.
---@param sample dwarfuicore.PointerSample
---@return dwarfuicore.TooltipPointerObservation
function TooltipTargetDetector:detect(sample)
    assert(type(sample) == 'table',
        'DwarfUICore tooltip target detector requires a pointer sample.')
    assert(type(sample.sequence) == 'number',
        'DwarfUICore pointer sample sequence must be a number.')
    local position = sample.screen_position
    if position == nil then
        return observation(sample, ObservationKind.MISS)
    end

    local roots = {}
    for widget, registration in pairs(self._registrations) do
        local root = self._root_resolver:resolve(widget, false)
        if root then
            local sequence = registration.sequence
            local existing = roots[root]
            if not existing or sequence > existing then
                roots[root] = sequence
            end
        end
    end
    if self._additional_roots then
        for root, sequence in pairs(self._additional_roots()) do
            local existing = roots[root]
            if not existing or sequence > existing then
                roots[root] = sequence
            end
        end
    end

    local winner
    local blocked
    for root, root_sequence in pairs(roots) do
        local result = self._resolve(root, position.x, position.y)
        if result.kind == PointerResultKind.TARGET then
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
            else
                blocked = TooltipTargetDetector.prefer_later_registration(
                    blocked, {root=root, sequence=root_sequence})
            end
        elseif result.kind == PointerResultKind.BLOCKED then
            blocked = TooltipTargetDetector.prefer_later_registration(
                blocked, {root=root, sequence=root_sequence})
        end
    end

    if winner then
        return observation(sample, ObservationKind.TARGET, winner)
    end
    if blocked then
        return observation(sample, ObservationKind.BLOCKED, blocked)
    end
    return observation(sample, ObservationKind.MISS)
end
