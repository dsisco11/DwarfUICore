--@ module=true

-- Process-wide continuous pointer sampling for private Input Event consumers.

local snapshot_factory_module =
    reqscript('dwarfuicore/input_event/snapshot_factory')

---@class dwarfuicore.PointerDemandHandle

---@class dwarfuicore.PointerDemandTracker
---@field _screen_count integer
---@field _map_count integer
---@field _handles table<dwarfuicore.PointerDemandHandle, boolean>
---@field _next_identity integer
PointerDemandTracker = {}
PointerDemandTracker.__index = PointerDemandTracker

---Reconciles counts after weak private owners have been collected.
function PointerDemandTracker:_refresh_counts()
    local screen_count, map_count = 0, 0
    for _, requires_map_position in pairs(self._handles) do
        screen_count = screen_count + 1
        if requires_map_position then map_count = map_count + 1 end
    end
    self._screen_count, self._map_count = screen_count, map_count
end

---@class dwarfuicore.InputEventPointerPollerOptions
---@field observer fun(sample: dwarfuicore.PointerSample)
---@field scheduler? fun(callback: function)
---@field snapshot_factory? dwarfuicore.SnapshotFactory
---@field demand_tracker? dwarfuicore.PointerDemandTracker

---@class dwarfuicore.PointerPoller
---@field _observer fun(sample: dwarfuicore.PointerSample)
---@field _scheduler fun(callback: function)
---@field _snapshot_factory dwarfuicore.SnapshotFactory
---@field _demand_tracker dwarfuicore.PointerDemandTracker
---@field _runtime_generation integer
---@field _generation integer
---@field _running boolean
---@field _scheduled boolean
---@field _last_sequence integer
PointerPoller = {}
PointerPoller.__index = PointerPoller

---Creates one immutable private continuous-pointer demand handle.
---@param requires_map_position boolean
---@return dwarfuicore.PointerDemandHandle handle
function PointerDemandTracker:acquire(requires_map_position)
    assert(type(requires_map_position) == 'boolean',
        'DwarfUICore pointer map demand must be a boolean.')
    local values = {local_identity=self._next_identity,
        requires_map_position=requires_map_position}
    local handle = setmetatable({}, {
        __index=values,
        __newindex=function()
            error('DwarfUICore pointer demand handles are immutable.', 2)
        end,
        __metatable=false,
    })
    self._next_identity = self._next_identity + 1
    self._handles[handle] = requires_map_position
    self._screen_count = self._screen_count + 1
    if requires_map_position then self._map_count = self._map_count + 1 end
    return handle
end

---Releases one active private continuous-pointer demand handle.
---@param handle dwarfuicore.PointerDemandHandle
---@return boolean released
function PointerDemandTracker:release(handle)
    local requires_map_position = self._handles[handle]
    if requires_map_position == nil then return false end
    self._handles[handle] = nil
    self._screen_count = self._screen_count - 1
    if requires_map_position then self._map_count = self._map_count - 1 end
    return true
end

---Returns whether any private continuous consumer requires screen samples.
---@return boolean
function PointerDemandTracker:has_screen_demand()
    self:_refresh_counts()
    return self._screen_count > 0
end

---Returns whether any private continuous consumer requires map samples.
---@return boolean
function PointerDemandTracker:has_map_demand()
    self:_refresh_counts()
    return self._map_count > 0
end

---Returns demand diagnostics without exposing private handles.
---@return table diagnostics
function PointerDemandTracker:get_diagnostics()
    self:_refresh_counts()
    return {screen_pointer_demand=self._screen_count,
        map_pointer_demand=self._map_count}
end

---Creates independently countable continuous pointer demand.
---@return dwarfuicore.PointerDemandTracker
function PointerDemandTracker.new()
    return setmetatable({_screen_count=0, _map_count=0,
        _handles=setmetatable({}, {__mode='k'}),
        _next_identity=1}, PointerDemandTracker)
end

---Queues one callback for the next process frame.
---@param callback function
local function default_scheduler(callback)
    dfhack.timeout(1, 'frames', callback)
end

---Creates one process-wide demand-driven private pointer poller.
---@param options dwarfuicore.InputEventPointerPollerOptions
---@return dwarfuicore.PointerPoller
function PointerPoller.new(options)
    assert(type(options) == 'table',
        'DwarfUICore Input Event pointer poller requires dependency options.')
    assert(type(options.observer) == 'function',
        'DwarfUICore Input Event pointer poller observer must be a function.')
    assert(options.scheduler == nil or type(options.scheduler) == 'function',
        'DwarfUICore Input Event pointer poller scheduler must be a function.')
    local snapshot_factory = options.snapshot_factory or
        snapshot_factory_module.SnapshotFactory.new{
            is_mouse_input=function() return false end,
        }
    local demand_tracker = options.demand_tracker or PointerDemandTracker.new()
    assert(type(snapshot_factory.capture_pointer) == 'function',
        'DwarfUICore Input Event pointer poller requires a snapshot factory.')
    assert(type(demand_tracker.has_screen_demand) == 'function' and
            type(demand_tracker.has_map_demand) == 'function',
        'DwarfUICore Input Event pointer poller requires a demand tracker.')
    local runtime = dfhack.dwarfuicore.service_provider_runtime
    return setmetatable({_observer=options.observer,
        _scheduler=options.scheduler or default_scheduler,
        _snapshot_factory=snapshot_factory, _demand_tracker=demand_tracker,
        _runtime_generation=runtime and runtime.generation or 0,
        _generation=0, _running=false, _scheduled=false, _last_sequence=0},
        PointerPoller)
end

---Returns whether this instance belongs to the active runtime generation.
---@return boolean
function PointerPoller:_is_current()
    local runtime = dfhack.dwarfuicore.service_provider_runtime
    return self._runtime_generation == (runtime and runtime.generation or 0)
end

---Stops logical ownership of the active callback chain.
function PointerPoller:_halt()
    self._running = false
    self._scheduled = false
    self._generation = self._generation + 1
end

---Queues the sole callback for the active poller generation.
function PointerPoller:_schedule_next()
    local generation = self._generation
    self._scheduled = true
    self._scheduler(function() self:_tick(generation) end)
end

---Samples once, observes once, and conditionally queues the successor.
---@param expected_generation integer
function PointerPoller:_tick(expected_generation)
    if expected_generation ~= self._generation or not self._running or
            not self:_is_current() then
        self._running = false
        self._scheduled = false
        return
    end
    self._scheduled = false
    if not self._demand_tracker:has_screen_demand() then
        self:_halt()
        return
    end
    local sample = self._snapshot_factory:capture_pointer({
        screen_position=true,
        map_position=self._demand_tracker:has_map_demand(),
        ui_root_resolution=false,
    })
    self._last_sequence = sample.sequence
    self._observer(sample)
    if expected_generation == self._generation and self._running and
            self:_is_current() and
            self._demand_tracker:has_screen_demand() then
        self:_schedule_next()
    end
end

---Starts the polling chain only while a private continuous consumer exists.
---@return boolean started
function PointerPoller:start()
    if self._running or not self:_is_current() or
            not self._demand_tracker:has_screen_demand() then return false end
    self._generation = self._generation + 1
    self._running = true
    self:_schedule_next()
    return true
end

---Invalidates pending samples and stops the active polling chain.
---@return boolean stopped
function PointerPoller:stop()
    if not self._running and not self._scheduled then return false end
    self:_halt()
    return true
end

---Returns polling and demand diagnostics without exposing private consumers.
---@return table diagnostics
function PointerPoller:get_diagnostics()
    local demand = self._demand_tracker:get_diagnostics()
    return {runtime_generation=self._runtime_generation,
        generation=self._generation, running=self._running,
        scheduled=self._scheduled, sample_sequence=self._last_sequence,
        current=self:_is_current(), screen_pointer_demand=
            demand.screen_pointer_demand, map_pointer_demand=
            demand.map_pointer_demand}
end
