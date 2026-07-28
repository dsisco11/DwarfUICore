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
---@field coordinate_space '"screen-cells"'

---Queues one callback for later execution without invoking it synchronously.
---@alias dwarfui.PointerPollerScheduler fun(callback: function)

---Returns one pointer position in screen-cell coordinates.
---@alias dwarfui.PointerPollerSampler fun(): integer|nil, integer|nil

---Accepts one immutable sample and must not retain mutable poller state.
---@alias dwarfui.PointerPollerObserver fun(sample: dwarfui.PointerSample)

---Returns whether another pointer sample is currently required.
---@alias dwarfui.PointerPollerDemand fun(): boolean

---@class dwarfui.PointerPollerOptions
---@field scheduler dwarfui.PointerPollerScheduler|nil
---@field sample_pointer dwarfui.PointerPollerSampler|nil
---@field observer dwarfui.PointerPollerObserver
---@field has_demand dwarfui.PointerPollerDemand

---@class dwarfui.PointerPoller
---@field _scheduler dwarfui.PointerPollerScheduler
---@field _sample_pointer dwarfui.PointerPollerSampler
---@field _observer dwarfui.PointerPollerObserver
---@field _has_demand dwarfui.PointerPollerDemand
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

---Creates one read-only pointer sample.
---@param sequence integer
---@param x integer|nil
---@param y integer|nil
---@return dwarfui.PointerSample
local function make_sample(sequence, x, y)
    local values = {
        sequence=sequence,
        x=x,
        y=y,
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
    assert(type(options.observer) == 'function',
        'DwarfUI pointer poller observer must be a function.')
    assert(type(options.has_demand) == 'function',
        'DwarfUI pointer poller demand predicate must be a function.')
    return setmetatable({
        _scheduler=options.scheduler or default_scheduler,
        _sample_pointer=options.sample_pointer or default_sampler,
        _observer=options.observer,
        _has_demand=options.has_demand,
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

    local _, x, y = self:_call('pointer sampler', self._sample_pointer)
    if x == nil or y == nil then
        x, y = nil, nil
    end
    self._sequence = self._sequence + 1
    local sample = make_sample(self._sequence, x, y)
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
