--@ module=true

-- Tooltip target detection is intentionally presentation-independent. It
-- consumes pointer samples and weak registrations, but never creates or
-- queries a tooltip renderer, screen, or overlay host.

local pointer = reqscript('dwarfui/pointer')
local TooltipRootResolver =
    reqscript('dwarfui/tooltip_root_resolver').TooltipRootResolver

---@class dwarfui.TooltipPointerObservation
---@field sequence integer
---@field kind '"target"'|'"blocked"'|'"miss"'
---@field pointer_x integer|nil
---@field pointer_y integer|nil
---@field target gui.View|nil
---@field local_x integer|nil
---@field local_y integer|nil
---@field root gui.View|nil

---@class dwarfui.TooltipTargetDetectorOptions
---@field registrations table<gui.View, table>
---@field resolve fun(root: gui.View, x: integer, y: integer): table|nil
---@field is_non_overlay_root_presented dwarfui.TooltipRootPresentationPredicate|nil
---@field root_resolver dwarfui.TooltipRootResolver|nil

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
---@field _root_resolver dwarfui.TooltipRootResolver
TooltipTargetDetector = {}
TooltipTargetDetector.__index = TooltipTargetDetector

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
    assert(options.root_resolver == nil or
            type(options.root_resolver) == 'table',
        'DwarfUI tooltip root resolver must be a table.')
    return setmetatable({
        _registrations=options.registrations,
        _resolve=options.resolve or pointer.PointerDispatcher.resolve,
        _root_resolver=options.root_resolver or TooltipRootResolver.new{
            is_non_overlay_root_presented=
                options.is_non_overlay_root_presented,
        },
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
        local root = self._root_resolver:resolve(widget, false)
        if root then
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
