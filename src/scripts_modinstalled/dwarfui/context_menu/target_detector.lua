--@ module=true

-- Deterministic widget/blocker/map arbitration over one synchronous sample.

local immutable_enum = reqscript('dwarfui/utils/immutable_enum')
local pointer = reqscript('dwarfui/pointer')
local targets = reqscript('dwarfui/context_menu/target')
local PointerResultKind = pointer.PointerResultKind
local TargetKind = targets.ContextMenuTargetKind

---@enum dwarfui.ContextMenuDetectionKind
ContextMenuDetectionKind = immutable_enum.define({
    TARGET=1,
    BLOCKED=2,
    MISS=3,
}, 'ContextMenuDetectionKind')

---@class dwarfui.ContextMenuTargetDetection
---@field kind dwarfui.ContextMenuDetectionKind
---@field candidate? dwarfui.ContextMenuWidgetCandidate|dwarfui.ContextMenuMapCandidate
---@field target? dwarfui.ContextMenuTargetDescriptor
---@field anchor? dwarfui.ContextMenuAnchorDescriptor
---@field root? any
---@field local_x? integer
---@field local_y? integer

---@class dwarfui.ContextMenuTargetDetectorOptions
---@field registrations dwarfui.ContextMenuRegistrationManager
---@field resolve? fun(root: any, x: integer, y: integer): dwarfui.PointerResult

---@class dwarfui.ContextMenuTargetDetector
---@field _registrations dwarfui.ContextMenuRegistrationManager
---@field _resolve fun(root: any, x: integer, y: integer): dwarfui.PointerResult
ContextMenuTargetDetector = {}
ContextMenuTargetDetector.__index = ContextMenuTargetDetector

---Creates one target detection result.
---@param kind dwarfui.ContextMenuDetectionKind
---@param values? table
---@return dwarfui.ContextMenuTargetDetection
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
---@param options dwarfui.ContextMenuTargetDetectorOptions
---@return dwarfui.ContextMenuTargetDetector
function ContextMenuTargetDetector.new(options)
    assert(type(options) == 'table',
        'DwarfUI context-menu target detector requires options.')
    assert(type(options.registrations) == 'table' and
            type(options.registrations.get_detection_roots) == 'function' and
            type(options.registrations.resolve_widget) == 'function' and
            type(options.registrations.detect_map_tile) == 'function',
        'DwarfUI context-menu target detector requires registrations.')
    assert(options.resolve == nil or type(options.resolve) == 'function',
        'DwarfUI context-menu pointer resolver must be a function.')
    return setmetatable({
        _registrations=options.registrations,
        _resolve=options.resolve or pointer.PointerDispatcher.resolve,
    }, ContextMenuTargetDetector)
end

---Detects exactly one eligible target, blocker, or miss from one sample.
---@param sample dwarfui.ContextMenuInputSample
---@return dwarfui.ContextMenuTargetDetection
function ContextMenuTargetDetector:detect(sample)
    assert(type(sample) == 'table',
        'DwarfUI context-menu target detector requires an input sample.')
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
        return detection(ContextMenuDetectionKind.TARGET, {
            candidate=winner.candidate,
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

    local candidate = self._registrations:detect_map_tile{
        x=sample.map_x,
        y=sample.map_y,
        z=sample.map_z,
    }
    if not candidate then
        return detection(ContextMenuDetectionKind.MISS)
    end
    return detection(ContextMenuDetectionKind.TARGET, {
        candidate=candidate,
        target=targets.ContextMenuTargetDescriptor.new(
            TargetKind.MAP_TILE, candidate.identity),
        anchor=targets.ContextMenuAnchorDescriptor.map_tile(
            candidate.pos, sample.x, sample.y),
        root=candidate.root,
    })
end
