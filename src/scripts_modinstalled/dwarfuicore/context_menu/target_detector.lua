--@ module=true

-- Deterministic widget/blocker/map arbitration over one synchronous sample.

local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')
local pointer = reqscript('dwarfuicore/pointer')
local targets = reqscript('dwarfuicore/context_menu/target')
local PointerResultKind = pointer.PointerResultKind
local TargetKind = targets.ContextMenuTargetKind

---@enum dwarfuicore.ContextMenuDetectionKind
ContextMenuDetectionKind = immutable_enum.define({
    TARGET=1,
    BLOCKED=2,
    MISS=3,
}, 'ContextMenuDetectionKind')

---@class dwarfuicore.ContextMenuTargetDetection
---@field kind dwarfuicore.ContextMenuDetectionKind
---@field candidate? dwarfuicore.ContextMenuWidgetCandidate|dwarfuicore.ContextMenuMapCandidate
---@field candidates? table[]
---@field target? dwarfuicore.ContextMenuTargetDescriptor
---@field anchor? dwarfuicore.ContextMenuAnchorDescriptor
---@field root? any
---@field local_x? integer
---@field local_y? integer

---@class dwarfuicore.ContextMenuTargetDetectorOptions
---@field registrations dwarfuicore.ContextMenuRegistrationManager
---@field resolve? fun(root: any, x: integer, y: integer): dwarfuicore.PointerResult

---@class dwarfuicore.ContextMenuTargetDetector
---@field _registrations dwarfuicore.ContextMenuRegistrationManager
---@field _resolve fun(root: any, x: integer, y: integer): dwarfuicore.PointerResult
ContextMenuTargetDetector = {}
ContextMenuTargetDetector.__index = ContextMenuTargetDetector

---Creates one target detection result.
---@param kind dwarfuicore.ContextMenuDetectionKind
---@param values? table
---@return dwarfuicore.ContextMenuTargetDetection
local function detection(kind, values)
    values = values or {}
    values.kind = kind
    return values
end

---Returns the later originally registered widget candidate.
---@param current table|nil
---@param candidate table
---@return table
local function prefer_later(current, candidate)
    if not current or candidate.candidate.sequence >
            current.candidate.sequence then
        return candidate
    end
    return current
end

---Creates a detector over the context-menu registration manager.
---@param options dwarfuicore.ContextMenuTargetDetectorOptions
---@return dwarfuicore.ContextMenuTargetDetector
function ContextMenuTargetDetector.new(options)
    assert(type(options) == 'table',
        'DwarfUICore context-menu target detector requires options.')
    assert(type(options.registrations) == 'table' and
            type(options.registrations.get_detection_roots) == 'function' and
            type(options.registrations.resolve_widget) == 'function' and
            type(options.registrations.detect_map_tile) == 'function',
        'DwarfUICore context-menu target detector requires registrations.')
    assert(options.resolve == nil or type(options.resolve) == 'function',
        'DwarfUICore context-menu pointer resolver must be a function.')
    return setmetatable({
        _registrations=options.registrations,
        _resolve=options.resolve or pointer.PointerDispatcher.resolve,
    }, ContextMenuTargetDetector)
end

---Detects exactly one eligible target, blocker, or miss from one sample.
---@param sample dwarfuicore.ContextMenuInputSample
---@return dwarfuicore.ContextMenuTargetDetection
function ContextMenuTargetDetector:detect(sample)
    assert(type(sample) == 'table',
        'DwarfUICore context-menu target detector requires an input sample.')
    if sample.x == nil or sample.y == nil then
        return detection(ContextMenuDetectionKind.MISS)
    end

    local winner
    local blocked = false
    for root in pairs(self._registrations:get_detection_roots()) do
        local result = self._resolve(root, sample.x, sample.y)
        if result.kind == PointerResultKind.TARGET then
            local candidate =
                self._registrations:resolve_widget(result.target)
            if candidate and candidate.root == root then
                winner = prefer_later(winner, {
                    candidate=candidate,
                    local_x=result.x,
                    local_y=result.y,
                })
            else
                blocked = true
            end
        elseif result.kind == PointerResultKind.BLOCKED then
            blocked = true
        end
    end

    if winner then
        local candidates = self._registrations.resolve_widget_contributions and
            self._registrations:resolve_widget_contributions(
                winner.candidate.source) or {winner.candidate}
        return detection(ContextMenuDetectionKind.TARGET, {
            candidate=winner.candidate,
            candidates=candidates,
            target=targets.ContextMenuTargetDescriptor.new(
                TargetKind.WIDGET, winner.candidate.identity),
            anchor=targets.ContextMenuAnchorDescriptor.screen_position(
                sample.x, sample.y),
            root=winner.candidate.root,
            local_x=winner.local_x,
            local_y=winner.local_y,
        })
    end
    if blocked then
        return detection(ContextMenuDetectionKind.BLOCKED)
    end
    if sample.map_x == nil or sample.map_y == nil or sample.map_z == nil then
        return detection(ContextMenuDetectionKind.MISS)
    end

    local map_position = {
        x=sample.map_x,
        y=sample.map_y,
        z=sample.map_z,
    }
    local candidates = self._registrations.detect_map_contributions and
        self._registrations:detect_map_contributions(map_position) or nil
    local candidate = candidates and candidates[#candidates] or
        self._registrations:detect_map_tile(map_position)
    if not candidate then
        return detection(ContextMenuDetectionKind.MISS)
    end
    if candidates then
        local selected = {}
        for _, value in ipairs(candidates) do
            if value.root == candidate.root then table.insert(selected, value) end
        end
        candidates = selected
    end
    return detection(ContextMenuDetectionKind.TARGET, {
        candidate=candidate,
        candidates=candidates or {candidate},
        target=targets.ContextMenuTargetDescriptor.new(
            TargetKind.MAP_TILE, candidate.identity),
        anchor=targets.ContextMenuAnchorDescriptor.map_tile(
            candidate.pos, sample.x, sample.y),
        root=candidate.root,
    })
end
