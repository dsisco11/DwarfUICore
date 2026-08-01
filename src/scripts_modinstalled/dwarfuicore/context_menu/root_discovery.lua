--@ module=true

-- Runtime-bound, registration-gated attachment-root discovery.

dfhack.dwarfuicore = dfhack.dwarfuicore or {}
local runtime_state = dfhack.dwarfuicore.service_provider_runtime
local runtime_generation = runtime_state and runtime_state.generation or 0

---@class dwarfuicore.ContextMenuRootDiscoveryOptions
---@field has_demand fun(): boolean
---@field discover fun(): table<any, boolean>
---@field on_roots_changed? fun(roots: table<any, boolean>)
---@field on_idle? fun()
---@field on_failure? fun(message: string)
---@field scheduler? fun(callback: function)
---@field printer? fun(message: string)

---@class dwarfuicore.ContextMenuRootDiscovery
---@field _has_demand fun(): boolean
---@field _discover fun(): table<any, boolean>
---@field _on_roots_changed fun(roots: table<any, boolean>)|nil
---@field _on_idle fun()|nil
---@field _on_failure fun(message: string)|nil
---@field _scheduler fun(callback: function)
---@field _printer fun(message: string)
---@field _runtime_generation integer
---@field _generation integer
---@field _running boolean
---@field _scheduled boolean
---@field _failed boolean
---@field _failure string|nil
---@field _roots table<any, boolean>
ContextMenuRootDiscovery = {}
ContextMenuRootDiscovery.__index = ContextMenuRootDiscovery

---Schedules one callback for the next DFHack frame.
---@param callback function
local function default_scheduler(callback)
    dfhack.timeout(1, 'frames', callback)
end

---Prints one discovery failure through the DFHack error channel.
---@param message string
local function default_printer(message)
    if dfhack.printerr then
        dfhack.printerr(message)
    else
        print(message)
    end
end

---Creates a weak-key root set without retaining consumer roots.
---@param roots? table<any, boolean>
---@return table<any, boolean>
local function weak_root_set(roots)
    local result = setmetatable({}, {__mode='k'})
    for root, present in pairs(roots or {}) do
        if present then result[root] = true end
    end
    return result
end

---Returns whether two root sets contain the same live identities.
---@param first table<any, boolean>
---@param second table<any, boolean>
---@return boolean
local function same_roots(first, second)
    for root in pairs(first) do
        if not second[root] then return false end
    end
    for root in pairs(second) do
        if not first[root] then return false end
    end
    return true
end

---Creates one guarded root-discovery callback chain.
---@param options dwarfuicore.ContextMenuRootDiscoveryOptions
---@return dwarfuicore.ContextMenuRootDiscovery
function ContextMenuRootDiscovery.new(options)
    assert(type(options) == 'table',
        'DwarfUICore context-menu root discovery requires options.')
    assert(type(options.has_demand) == 'function',
        'DwarfUICore context-menu root discovery requires a demand predicate.')
    assert(type(options.discover) == 'function',
        'DwarfUICore context-menu root discovery requires a discovery callback.')
    assert(options.on_roots_changed == nil or
            type(options.on_roots_changed) == 'function',
        'DwarfUICore context-menu root observer must be a function.')
    assert(options.on_idle == nil or type(options.on_idle) == 'function',
        'DwarfUICore context-menu idle callback must be a function.')
    assert(options.on_failure == nil or
            type(options.on_failure) == 'function',
        'DwarfUICore context-menu failure callback must be a function.')
    assert(options.scheduler == nil or type(options.scheduler) == 'function',
        'DwarfUICore context-menu discovery scheduler must be a function.')
    assert(options.printer == nil or type(options.printer) == 'function',
        'DwarfUICore context-menu discovery printer must be a function.')
    return setmetatable({
        _has_demand=options.has_demand,
        _discover=options.discover,
        _on_roots_changed=options.on_roots_changed,
        _on_idle=options.on_idle,
        _on_failure=options.on_failure,
        _scheduler=options.scheduler or default_scheduler,
        _printer=options.printer or default_printer,
        _runtime_generation=runtime_generation,
        _generation=0,
        _running=false,
        _scheduled=false,
        _failed=false,
        _failure=nil,
        _roots=weak_root_set(),
    }, ContextMenuRootDiscovery)
end

---Returns whether this instance belongs to the active runtime generation.
---@return boolean
function ContextMenuRootDiscovery:_module_is_current()
    local current = dfhack.dwarfuicore.service_provider_runtime
    local generation = current and current.generation or 0
    return self._runtime_generation == generation
end

---Invokes one discovery collaborator under a traceback boundary.
---@param label string
---@param callback function
---@return boolean
---@return any
function ContextMenuRootDiscovery:_call(label, callback)
    local packed
    local ok, failure = xpcall(function()
        packed = table.pack(callback())
    end, debug.traceback)
    if ok then return true, table.unpack(packed, 1, packed.n) end
    self:_fail(('DwarfUICore context-menu %s failed:\n%s'):format(
        label, tostring(failure)))
    return false
end

---Stops this generation after one contained callback failure.
---@param message string
function ContextMenuRootDiscovery:_fail(message)
    if self._failed then return end
    self._failed = true
    self._failure = message
    self._running = false
    self._scheduled = false
    self._generation = self._generation + 1
    self._printer(message)
    if self._on_failure then
        local ok, failure = xpcall(function()
            self._on_failure(message)
        end, debug.traceback)
        if not ok then
            self._printer(
                'DwarfUICore context-menu failure callback failed:\n' ..
                tostring(failure))
        end
    end
end

---Publishes a changed weak root set to the hook-management collaborator.
---@param roots table<any, boolean>
---@return boolean
function ContextMenuRootDiscovery:_publish_roots(roots)
    roots = weak_root_set(roots)
    if same_roots(self._roots, roots) then return true end
    self._roots = roots
    if not self._on_roots_changed then return true end
    return self:_call('root observer', function()
        self._on_roots_changed(roots)
    end)
end

---Releases discovered roots and notifies the idle collaborator.
function ContextMenuRootDiscovery:_publish_idle()
    if not self:_publish_roots({}) then return end
    if self._on_idle then
        self:_call('idle callback', self._on_idle)
    end
end

---Queues the sole callback for this instance generation.
function ContextMenuRootDiscovery:_schedule_next()
    local expected_generation = self._generation
    local expected_runtime_generation = self._runtime_generation
    self._scheduled = true
    local ok = self:_call('scheduler', function()
        self._scheduler(function()
            self:_tick(expected_generation, expected_runtime_generation)
        end)
    end)
    if not ok then self._scheduled = false end
end

---Executes one guarded discovery pass and queues its successor.
---@param expected_generation integer
---@param expected_runtime_generation integer
function ContextMenuRootDiscovery:_tick(
        expected_generation, expected_runtime_generation)
    local current_runtime = dfhack.dwarfuicore.service_provider_runtime
    local current_runtime_generation =
        current_runtime and current_runtime.generation or 0
    if expected_runtime_generation ~= current_runtime_generation then
        self._running = false
        self._scheduled = false
        return
    end
    if expected_generation ~= self._generation or
            not self._running or self._failed then
        return
    end
    self._scheduled = false

    local demand_ok, demand = self:_call(
        'demand predicate', self._has_demand)
    if not demand_ok then return end
    if not demand then
        self._running = false
        self._generation = self._generation + 1
        self:_publish_idle()
        return
    end

    local discover_ok, roots = self:_call('root discovery', self._discover)
    if not discover_ok then return end
    if type(roots) ~= 'table' then
        self:_fail(
            'DwarfUICore context-menu root discovery must return a root set.')
        return
    end
    if not self:_publish_roots(roots) then return end

    local current_ok, still_needed = self:_call(
        'demand predicate', self._has_demand)
    if not current_ok then return end
    if expected_generation ~= self._generation or
            not self._running or not still_needed then
        if self._running then
            self._running = false
            self._generation = self._generation + 1
            self:_publish_idle()
        end
        return
    end
    self:_schedule_next()
end

---Starts discovery when at least one registration or open menu needs it.
---@return boolean started
function ContextMenuRootDiscovery:start()
    if self._running or self._failed or
            not self:_module_is_current() then
        return false
    end
    local demand_ok, demand = self:_call(
        'demand predicate', self._has_demand)
    if not demand_ok or not demand then return false end
    self._generation = self._generation + 1
    self._running = true
    self:_schedule_next()
    return self._running
end

---Invalidates the active callback chain and releases discovered roots.
---@return boolean stopped
function ContextMenuRootDiscovery:stop()
    local changed = self._running or self._scheduled or
        next(self._roots) ~= nil
    self._running = false
    self._scheduled = false
    self._generation = self._generation + 1
    if changed then self:_publish_idle() end
    return changed
end

---Retries a stopped non-failed chain after demand changes.
---@return boolean started
function ContextMenuRootDiscovery:refresh()
    if self._failed then return false end
    if self._running then return false end
    return self:start()
end

---Reconciles running state with the protected current demand predicate.
---@return boolean running
function ContextMenuRootDiscovery:reconcile()
    if self._failed or not self:_module_is_current() then return false end
    local demand_ok, demand = self:_call(
        'demand predicate', self._has_demand)
    if not demand_ok then return false end
    if demand then
        if not self._running then self:start() end
    else
        self:stop()
    end
    return self._running
end

---Replays the current root set to a newly installed protected observer.
---@return boolean published
function ContextMenuRootDiscovery:republish()
    if self._failed or not self._on_roots_changed then return false end
    return self:_call('root observer', function()
        self._on_roots_changed(self._roots)
    end)
end

---Returns reload, scheduling, root, and failure diagnostics.
---@return table
function ContextMenuRootDiscovery:get_diagnostics()
    local root_count = 0
    for _ in pairs(self._roots) do root_count = root_count + 1 end
    return {
        runtime_generation=self._runtime_generation,
        generation=self._generation,
        current=self:_module_is_current(),
        running=self._running,
        scheduled=self._scheduled,
        failed=self._failed,
        failure=self._failure,
        root_count=root_count,
    }
end
