--@ module=true

-- Generic process-wide pointer sampling with reload-safe callback invalidation.

local MODULE_GENERATION_SLOT = 'pointer_poller_module_generation'

dfhack.dwarfui = dfhack.dwarfui or {}
dfhack.dwarfui[MODULE_GENERATION_SLOT] =
    (dfhack.dwarfui[MODULE_GENERATION_SLOT] or 0) + 1
local module_generation = dfhack.dwarfui[MODULE_GENERATION_SLOT]

---@class dwarfui.PointerSample
---@field sequence integer
---@field x integer|nil
---@field y integer|nil
---@field map_x integer|nil
---@field map_y integer|nil
---@field map_z integer|nil
---@field coordinate_space '"screen-cells"'

---Queues one callback for later execution without invoking it synchronously.
---@alias dwarfui.PointerPollerScheduler fun(callback: function)

---Returns one pointer position in screen-cell coordinates.
---@alias dwarfui.PointerPollerSampler fun(): integer|nil, integer|nil

---Returns the exact map tile under the pointer, or nil outside the map.
---@alias dwarfui.PointerPollerMapSampler fun(): {x: integer, y: integer, z: integer}|nil

---Accepts one immutable sample and must not retain mutable poller state.
---@alias dwarfui.PointerPollerObserver fun(sample: dwarfui.PointerSample)

---Returns whether another pointer sample is currently required.
---@alias dwarfui.PointerPollerDemand fun(): boolean

---@class dwarfui.PointerPollerOptions
---@field scheduler dwarfui.PointerPollerScheduler|nil
---@field sample_pointer dwarfui.PointerPollerSampler|nil
---@field sample_map_pointer dwarfui.PointerPollerMapSampler|nil
---@field observer dwarfui.PointerPollerObserver
---@field has_demand dwarfui.PointerPollerDemand
---@field has_map_demand dwarfui.PointerPollerDemand|nil

---@class dwarfui.PointerPoller
---@field _scheduler dwarfui.PointerPollerScheduler
---@field _sample_pointer dwarfui.PointerPollerSampler
---@field _sample_map_pointer dwarfui.PointerPollerMapSampler
---@field _observer dwarfui.PointerPollerObserver
---@field _has_demand dwarfui.PointerPollerDemand
---@field _has_map_demand dwarfui.PointerPollerDemand
---@field _module_generation integer
---@field _generation integer
---@field _sequence integer
---@field _running boolean
---@field _scheduled boolean
PointerPoller = {}
PointerPoller.__index = PointerPoller

---Queues one callback for the next process frame.
---@param callback function
local function default_scheduler(callback)
    dfhack.timeout(1, 'frames', callback)
end

---Reads the current pointer position exactly once.
---@return integer|nil
---@return integer|nil
local function default_sampler()
    return dfhack.screen.getMousePos()
end

---Reads the current exact map tile exactly once.
---@return {x: integer, y: integer, z: integer}|nil
local function default_map_sampler()
    return dfhack.gui.getMousePos()
end

---Reports that no map-coordinate consumer currently requires sampling.
---@return boolean
local function no_map_demand()
    return false
end

---Creates one read-only pointer sample.
---@param sequence integer
---@param x integer|nil
---@param y integer|nil
---@param map_x integer|nil
---@param map_y integer|nil
---@param map_z integer|nil
---@return dwarfui.PointerSample
local function make_sample(sequence, x, y, map_x, map_y, map_z)
    local values = {
        sequence=sequence,
        x=x,
        y=y,
        map_x=map_x,
        map_y=map_y,
        map_z=map_z,
        coordinate_space='screen-cells',
    }
    return setmetatable({}, {
        __index=values,
        __newindex=function()
            error('DwarfUI pointer samples are immutable.', 2)
        end,
        __pairs=function()
            return next, values, nil
        end,
        __metatable=false,
    })
end

---Creates a pointer poller with explicit observation and demand boundaries.
---@param options dwarfui.PointerPollerOptions
---@return dwarfui.PointerPoller
function PointerPoller.new(options)
    assert(type(options) == 'table',
        'DwarfUI pointer poller requires dependency options.')
    assert(options.scheduler == nil or type(options.scheduler) == 'function',
        'DwarfUI pointer poller scheduler must be a function.')
    assert(options.sample_pointer == nil or
        type(options.sample_pointer) == 'function',
        'DwarfUI pointer poller sampler must be a function.')
    assert(options.sample_map_pointer == nil or
        type(options.sample_map_pointer) == 'function',
        'DwarfUI map pointer sampler must be a function.')
    assert(type(options.observer) == 'function',
        'DwarfUI pointer poller observer must be a function.')
    assert(type(options.has_demand) == 'function',
        'DwarfUI pointer poller demand predicate must be a function.')
    assert(options.has_map_demand == nil or
        type(options.has_map_demand) == 'function',
        'DwarfUI map pointer demand predicate must be a function.')
    return setmetatable({
        _scheduler=options.scheduler or default_scheduler,
        _sample_pointer=options.sample_pointer or default_sampler,
        _sample_map_pointer=options.sample_map_pointer or default_map_sampler,
        _observer=options.observer,
        _has_demand=options.has_demand,
        _has_map_demand=options.has_map_demand or no_map_demand,
        _module_generation=module_generation,
        _generation=0,
        _sequence=0,
        _running=false,
        _scheduled=false,
    }, PointerPoller)
end

---Returns whether this instance belongs to the active module generation.
---@return boolean
function PointerPoller:_module_is_current()
    return self._module_generation ==
        dfhack.dwarfui[MODULE_GENERATION_SLOT]
end

---Stops logical ownership of the current callback chain.
function PointerPoller:_halt()
    self._running = false
    self._scheduled = false
    self._generation = self._generation + 1
end

---Runs one collaborator and stops the chain if it raises an error.
---@param label string
---@param callback function
---@return boolean
---@return any
---@return any
function PointerPoller:_call(label, callback)
    local results = table.pack(xpcall(callback, debug.traceback))
    if not results[1] then
        self:_halt()
        error(('DwarfUI pointer poller %s failed: %s'):format(
            label, tostring(results[2])), 0)
    end
    return true, table.unpack(results, 2, results.n)
end

---Returns current demand through the guarded collaborator boundary.
---@return boolean
function PointerPoller:_demand_exists()
    local _, demand = self:_call('demand predicate', self._has_demand)
    return not not demand
end

---Returns current map-sampling demand through the guarded boundary.
---@return boolean
function PointerPoller:_map_demand_exists()
    local _, demand =
        self:_call('map demand predicate', self._has_map_demand)
    return not not demand
end

---Queues the sole callback for the current instance generation.
function PointerPoller:_schedule_next()
    local instance_generation = self._generation
    local expected_module_generation = self._module_generation
    self._scheduled = true
    self:_call('scheduler', function()
        self._scheduler(function()
            self:_tick(instance_generation, expected_module_generation)
        end)
    end)
end

---Executes one current callback and conditionally queues its successor.
---@param expected_generation integer
---@param expected_module_generation integer
function PointerPoller:_tick(expected_generation,
        expected_module_generation)
    if expected_module_generation ~=
            dfhack.dwarfui[MODULE_GENERATION_SLOT] then
        self._running = false
        self._scheduled = false
        return
    end
    if expected_generation ~= self._generation or not self._running then
        return
    end

    self._scheduled = false
    if not self:_demand_exists() then
        self:_halt()
        return
    end

    local map_demand = self:_map_demand_exists()
    local _, x, y = self:_call('pointer sampler', self._sample_pointer)
    if x == nil or y == nil then
        x, y = nil, nil
    end

    local map_x, map_y, map_z
    if map_demand then
        local _, map_pos =
            self:_call('map pointer sampler', self._sample_map_pointer)
        local map_pos_type = type(map_pos)
        if (map_pos_type == 'table' or map_pos_type == 'userdata') and
                map_pos.x ~= nil and map_pos.y ~= nil and
                map_pos.z ~= nil then
            map_x, map_y, map_z = map_pos.x, map_pos.y, map_pos.z
        end
    end

    self._sequence = self._sequence + 1
    local sample = make_sample(
        self._sequence, x, y, map_x, map_y, map_z)
    self:_call('observer', function() self._observer(sample) end)

    if expected_generation ~= self._generation or
            expected_module_generation ~=
                dfhack.dwarfui[MODULE_GENERATION_SLOT] or
            not self._running then
        return
    end
    if not self:_demand_exists() then
        self:_halt()
        return
    end
    self:_schedule_next()
end

---Starts one callback chain when demand exists.
---@return boolean started
function PointerPoller:start()
    if self._running or not self:_module_is_current() then return false end
    if not self:_demand_exists() then return false end
    self._generation = self._generation + 1
    self._running = true
    self:_schedule_next()
    return true
end

---Invalidates the active callback chain without requiring timer cancellation.
---@return boolean stopped
function PointerPoller:stop()
    if not self._running and not self._scheduled then return false end
    self:_halt()
    return true
end

---Returns lifecycle diagnostics without exposing poller collaborators.
---@return table diagnostics
function PointerPoller:get_diagnostics()
    return {
        module_generation=self._module_generation,
        generation=self._generation,
        running=self._running,
        scheduled=self._scheduled,
        sample_sequence=self._sequence,
        current=self:_module_is_current(),
    }
end
