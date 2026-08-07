--@ module=true

-- Canonical immutable input and pointer snapshots for the Input Event runtime.

local identities = reqscript('dwarfuicore/service_provider/identity')
local types = reqscript('dwarfuicore/input_event/types')

local PROCESS_SLOT = 'input_event_snapshot_factory'
local STATE_VERSION = 1
local demand_values = {
    [types.InputSampleDemandType.SCREEN_POSITION]=true,
    [types.InputSampleDemandType.MAP_POSITION]=true,
    [types.InputSampleDemandType.UI_ROOT_RESOLUTION]=true,
}

---@class dwarfuicore.MouseInput
---@field key string

---@class dwarfuicore.InputSnapshot
---@field sequence integer
---@field mouse_inputs dwarfuicore.MouseInput[]
---@field screen_position dwarfuicore.Position2D|nil
---@field map_position dwarfuicore.Position3D|nil

---@class dwarfuicore.PointerSample
---@field sequence integer
---@field screen_position dwarfuicore.Position2D|nil
---@field map_position dwarfuicore.Position3D|nil

---@class dwarfuicore.InputSnapshotDemand
---@field screen_position boolean
---@field map_position boolean
---@field ui_root_resolution boolean

---@class dwarfuicore.InputSampleDemandHandle

---@class dwarfuicore.InputDemandTracker
---@field _counts table<dwarfuicore.InputSampleDemandType, integer>
---@field _handles table<dwarfuicore.InputSampleDemandHandle, dwarfuicore.InputSampleDemandType>
---@field _next_identity integer
InputDemandTracker = {}
InputDemandTracker.__index = InputDemandTracker

---@alias dwarfuicore.InputEventPointerSampler fun(): integer|nil, integer|nil
---@alias dwarfuicore.InputEventMapSampler fun(): {x: integer, y: integer, z: integer}|nil
---@alias dwarfuicore.HostMouseInputClassifier fun(key: string): boolean

---@class dwarfuicore.SnapshotFactoryOptions
---@field sample_screen_position? dwarfuicore.InputEventPointerSampler
---@field sample_map_position? dwarfuicore.InputEventMapSampler
---@field is_mouse_input dwarfuicore.HostMouseInputClassifier

---@class dwarfuicore.SnapshotFactory
---@field _state table
---@field _sample_screen_position dwarfuicore.InputEventPointerSampler
---@field _sample_map_position dwarfuicore.InputEventMapSampler
---@field _is_mouse_input dwarfuicore.HostMouseInputClassifier
SnapshotFactory = {}
SnapshotFactory.__index = SnapshotFactory

---Returns the reload-stable process sequence state.
---@return table state
local function get_process_state()
    dfhack.dwarfuicore = dfhack.dwarfuicore or {}
    local state = dfhack.dwarfuicore[PROCESS_SLOT]
    if type(state) ~= 'table' or state.version ~= STATE_VERSION or
            math.type(state.next_sequence) ~= 'integer' or
            state.next_sequence < 1 then
        state = {version=STATE_VERSION, next_sequence=1}
        dfhack.dwarfuicore[PROCESS_SLOT] = state
    end
    return state
end

---Builds an immutable proxy over copied values.
---@param values table
---@param label string
---@param length? integer
---@return table
local function immutable_value(values, label, length)
    return setmetatable({}, {
        __index=values,
        __newindex=function()
            error(('DwarfUICore %s are immutable.'):format(label), 2)
        end,
        __pairs=function()
            return next, values, nil
        end,
        __len=function()
            return length or 0
        end,
        __metatable=false,
    })
end

---Copies one valid screen position or normalizes it to nil.
---@param x any
---@param y any
---@return dwarfuicore.Position2D|nil
local function copy_screen_position(x, y)
    local ok, position = pcall(identities.Position2D.new, {x=x, y=y})
    return ok and position or nil
end

---Copies one valid map position or normalizes it to nil.
---@param value any
---@return dwarfuicore.Position3D|nil
local function copy_map_position(value)
    local ok, position = pcall(identities.Position3D.new, value)
    return ok and position or nil
end

---Returns one immutable demand snapshot from current tracker counts.
---@param counts table<dwarfuicore.InputSampleDemandType, integer>
---@return dwarfuicore.InputSnapshotDemand
local function demand_snapshot(counts)
    return immutable_value({
        screen_position=counts[types.InputSampleDemandType.SCREEN_POSITION] > 0,
        map_position=counts[types.InputSampleDemandType.MAP_POSITION] > 0,
        ui_root_resolution=
            counts[types.InputSampleDemandType.UI_ROOT_RESOLUTION] > 0,
    }, 'Input Event snapshot demand')
end

---Creates independently countable synchronous input-sampling demand.
---@return dwarfuicore.InputDemandTracker
function InputDemandTracker.new()
    return setmetatable({
        _counts={
            [types.InputSampleDemandType.SCREEN_POSITION]=0,
            [types.InputSampleDemandType.MAP_POSITION]=0,
            [types.InputSampleDemandType.UI_ROOT_RESOLUTION]=0,
        },
        _handles={},
        _next_identity=1,
    }, InputDemandTracker)
end

---Acquires one independently tracked sampling demand contribution.
---@param demand_type dwarfuicore.InputSampleDemandType
---@return dwarfuicore.InputSampleDemandHandle handle
function InputDemandTracker:acquire(demand_type)
    assert(demand_values[demand_type],
        'DwarfUICore Input Event demand type is invalid.')
    local handle = immutable_value({
        demand_type=demand_type,
        local_identity=self._next_identity,
    }, 'Input Event sample demand handle')
    self._next_identity = self._next_identity + 1
    self._handles[handle] = demand_type
    self._counts[demand_type] = self._counts[demand_type] + 1
    return handle
end

---Releases one active demand contribution from this tracker.
---@param handle dwarfuicore.InputSampleDemandHandle
---@return boolean released
function InputDemandTracker:release(handle)
    local demand_type = self._handles[handle]
    if demand_type == nil then return false end
    self._handles[handle] = nil
    self._counts[demand_type] = self._counts[demand_type] - 1
    return true
end

---Returns the current immutable flags for one capture operation.
---@return dwarfuicore.InputSnapshotDemand demand
function InputDemandTracker:get_snapshot()
    return demand_snapshot(self._counts)
end

---Returns the active contribution count for one demand type.
---@param demand_type dwarfuicore.InputSampleDemandType
---@return integer count
function InputDemandTracker:get_count(demand_type)
    assert(demand_values[demand_type],
        'DwarfUICore Input Event demand type is invalid.')
    return self._counts[demand_type]
end

---Reads the current screen position exactly once.
---@return integer|nil
---@return integer|nil
local function default_screen_sampler()
    if type(dfhack.screen) ~= 'table' or
            type(dfhack.screen.getMousePos) ~= 'function' then return nil, nil end
    return dfhack.screen.getMousePos()
end

---Reads the current exact map position exactly once.
---@return {x: integer, y: integer, z: integer}|nil
local function default_map_sampler()
    if type(dfhack.gui) ~= 'table' or
            type(dfhack.gui.getMousePos) ~= 'function' then return nil end
    return dfhack.gui.getMousePos()
end

---Creates one canonical snapshot factory with an injected host mouse classifier.
---@param options dwarfuicore.SnapshotFactoryOptions
---@return dwarfuicore.SnapshotFactory
function SnapshotFactory.new(options)
    assert(type(options) == 'table',
        'DwarfUICore Input Event snapshot factory requires options.')
    assert(type(options.is_mouse_input) == 'function',
        'DwarfUICore Input Event mouse classifier must be a function.')
    assert(options.sample_screen_position == nil or
            type(options.sample_screen_position) == 'function',
        'DwarfUICore Input Event screen sampler must be a function.')
    assert(options.sample_map_position == nil or
            type(options.sample_map_position) == 'function',
        'DwarfUICore Input Event map sampler must be a function.')
    return setmetatable({
        _state=get_process_state(),
        _sample_screen_position=options.sample_screen_position or
            default_screen_sampler,
        _sample_map_position=options.sample_map_position or default_map_sampler,
        _is_mouse_input=options.is_mouse_input,
    }, SnapshotFactory)
end

---Allocates the next process-wide snapshot sequence.
---@return integer sequence
function SnapshotFactory:_next_sequence()
    local sequence = self._state.next_sequence
    self._state.next_sequence = sequence + 1
    return sequence
end

---Copies the positions requested by one immutable demand snapshot.
---@param demand dwarfuicore.InputSnapshotDemand
---@return dwarfuicore.Position2D|nil
---@return dwarfuicore.Position3D|nil
function SnapshotFactory:_capture_positions(demand)
    assert(type(demand) == 'table',
        'DwarfUICore Input Event snapshot demand must be a table.')
    local screen_position
    if demand.screen_position then
        local x, y = self._sample_screen_position()
        screen_position = copy_screen_position(x, y)
    end
    local map_position
    if demand.map_position then
        map_position = copy_map_position(self._sample_map_position())
    end
    return screen_position, map_position
end

---Collects every active host-classified mouse key in deterministic key order.
---@param keys table
---@return dwarfuicore.MouseInput[]
function SnapshotFactory:_collect_mouse_inputs(keys)
    local inputs = {}
    for key, active in pairs(keys) do
        if active and self._is_mouse_input(key) then
            assert(type(key) == 'string',
                'DwarfUICore host mouse input keys must be strings.')
            table.insert(inputs, immutable_value({key=key}, 'Input Event mouse input'))
        end
    end
    table.sort(inputs, function(left, right) return left.key < right.key end)
    return immutable_value(inputs, 'Input Event mouse input collection', #inputs)
end

---Captures one immutable snapshot for an intercepted keys table.
---@param keys table
---@param demand dwarfuicore.InputSnapshotDemand
---@return dwarfuicore.InputSnapshot snapshot
function SnapshotFactory:capture_input(keys, demand)
    assert(type(keys) == 'table',
        'DwarfUICore Input Event keys must be a table.')
    local screen_position, map_position = self:_capture_positions(demand)
    return immutable_value({
        sequence=self:_next_sequence(),
        mouse_inputs=self:_collect_mouse_inputs(keys),
        screen_position=screen_position,
        map_position=map_position,
    }, 'Input Event input snapshot')
end

---Captures one immutable continuous pointer sample.
---@param demand dwarfuicore.InputSnapshotDemand
---@return dwarfuicore.PointerSample sample
function SnapshotFactory:capture_pointer(demand)
    local screen_position, map_position = self:_capture_positions(demand)
    return immutable_value({
        sequence=self:_next_sequence(),
        screen_position=screen_position,
        map_position=map_position,
    }, 'Input Event pointer sample')
end
