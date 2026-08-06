--@ module=true

local contracts = reqscript('dwarfuicore/service_provider/contracts')

local PROCESS_SLOT = 'service_provider_runtime'
local STATE_FIELDS = {
    generation=true,
    status=true,
    initializing=true,
    services=true,
    facades=true,
}
local SERVICE_FIELDS = {generation=true, health=true, value=true}

---Private process-owned DwarfUICore runtime state.
---@class dwarfuicore.ServiceProviderRuntimeState
---@field generation integer
---@field status dwarfuicore.RuntimeStatus
---@field initializing table<dwarfuicore.ServiceKind, boolean>
---@field services table<dwarfuicore.ServiceKind, table>
---@field facades table<dwarfuicore.ServiceKind, table>

---Returns whether a value is a known service kind.
---@param value any
---@return boolean valid
local function is_service_kind(value)
    return value == contracts.ServiceKind.TOOLTIP or
        value == contracts.ServiceKind.CONTEXT_MENU or
        value == contracts.ServiceKind.USER_PROMPT or
        value == contracts.ServiceKind.INPUT_EVENT
end

---Returns whether a value is a known runtime status.
---@param value any
---@return boolean valid
local function is_runtime_status(value)
    for _, status in pairs(contracts.RuntimeStatus) do
        if value == status then return true end
    end
    return false
end

---Returns whether a value is a known service-health state.
---@param value any
---@return boolean valid
local function is_service_health(value)
    for _, health in pairs(contracts.ServiceHealth) do
        if value == health then return true end
    end
    return false
end

---Validates a plain table against one exact field set.
---@param value any
---@param fields table<string, boolean>
---@param label string
---@return table value
local function validate_exact_table(value, fields, label)
    assert(type(value) == 'table' and getmetatable(value) == nil,
        ('DwarfUICore %s must be a plain table.'):format(label))
    for key in next, value do
        assert(fields[key],
            ('DwarfUICore %s contains an unknown field.'):format(label))
    end
    return value
end

---Validates one service-kind-keyed table without mutating it.
---@param value any
---@param label string
---@return table value
local function validate_service_map(value, label)
    assert(type(value) == 'table' and getmetatable(value) == nil,
        ('DwarfUICore %s must be a plain table.'):format(label))
    for key in next, value do
        assert(is_service_kind(key),
            ('DwarfUICore %s contains an invalid service kind.'):format(label))
    end
    return value
end

---Validates one cached service record without mutating it.
---@param record any
---@param generation integer
---@return table record
local function validate_service_record(record, generation)
    validate_exact_table(record, SERVICE_FIELDS, 'service record')
    assert(rawget(record, 'generation') == generation,
        'DwarfUICore service record belongs to another runtime generation.')
    assert(is_service_health(rawget(record, 'health')),
        'DwarfUICore service record health is invalid.')
    assert(type(rawget(record, 'value')) == 'table',
        'DwarfUICore service record value must be a table.')
    return record
end

---Returns the current process slot without creating or repairing it.
---@return any state
local function read_process_state()
    if type(dfhack) ~= 'table' or type(dfhack.dwarfuicore) ~= 'table' then
        return nil
    end
    return dfhack.dwarfuicore[PROCESS_SLOT]
end

---Validates and returns current runtime state without side effects.
---@param expected_generation? integer
---@return dwarfuicore.ServiceProviderRuntimeState state
function validate(expected_generation)
    local state = read_process_state()
    assert(state ~= nil, 'DwarfUICore runtime state is missing.')
    validate_exact_table(state, STATE_FIELDS, 'runtime state')
    local generation = rawget(state, 'generation')
    assert(math.type(generation) == 'integer' and generation > 0,
        'DwarfUICore runtime generation must be a positive integer.')
    if expected_generation ~= nil then
        assert(generation == expected_generation,
            'DwarfUICore runtime generation does not match.')
    end
    assert(is_runtime_status(rawget(state, 'status')),
        'DwarfUICore runtime status is invalid.')
    local initializing = rawget(state, 'initializing')
    local services = rawget(state, 'services')
    local facades = rawget(state, 'facades')
    validate_service_map(initializing, 'initialization markers')
    validate_service_map(services, 'service cache')
    validate_service_map(facades, 'facade cache')
    for kind, marker in next, initializing do
        assert(marker == true,
            'DwarfUICore initialization marker must be true or absent.')
        assert(is_service_kind(kind),
            'DwarfUICore initialization marker service kind is invalid.')
    end
    for _, record in next, services do
        validate_service_record(record, generation)
    end
    for _, cache in next, facades do
        assert(type(cache) == 'table' and getmetatable(cache) == nil,
            'DwarfUICore service facade cache must be a plain table.')
    end
    return state
end

---Validates a healthy runtime suitable for service acquisition.
---@param expected_generation? integer
---@return dwarfuicore.ServiceProviderRuntimeState state
function validate_acquirable(expected_generation)
    local state = validate(expected_generation)
    assert(state.status == contracts.RuntimeStatus.HEALTHY,
        'DwarfUICore runtime is not healthy for acquisition.')
    return state
end

---Begins cold runtime initialization or reuses a healthy runtime.
---@return dwarfuicore.ServiceProviderRuntimeState state
---@return boolean created
function begin_initialization()
    local existing = read_process_state()
    if existing ~= nil then
        local state = validate()
        assert(state.status == contracts.RuntimeStatus.HEALTHY,
            'DwarfUICore runtime cannot begin initialization in its current state.')
        return state, false
    end
    assert(type(dfhack) == 'table',
        'DwarfUICore runtime initialization requires DFHack process state.')
    if dfhack.dwarfuicore == nil then dfhack.dwarfuicore = {} end
    assert(type(dfhack.dwarfuicore) == 'table',
        'DwarfUICore process namespace must be a table.')
    local state = {generation=1,
        status=contracts.RuntimeStatus.INITIALIZING, initializing={},
        services={}, facades={}}
    dfhack.dwarfuicore[PROCESS_SLOT] = state
    return state, true
end

---Publishes a fully constructed runtime generation as healthy.
---@param expected_generation integer
---@return dwarfuicore.ServiceProviderRuntimeState state
function complete_initialization(expected_generation)
    local state = validate(expected_generation)
    assert(state.status == contracts.RuntimeStatus.INITIALIZING,
        'DwarfUICore runtime is not initializing.')
    assert(next(state.initializing) == nil,
        'DwarfUICore runtime still has active service initialization.')
    state.status = contracts.RuntimeStatus.HEALTHY
    return state
end

---Marks failed construction disabled without publishing healthy services.
---@param expected_generation integer
---@return dwarfuicore.ServiceProviderRuntimeState state
function fail_initialization(expected_generation)
    local state = validate(expected_generation)
    assert(state.status == contracts.RuntimeStatus.INITIALIZING,
        'DwarfUICore runtime is not initializing.')
    state.initializing = {}
    state.services = {}
    state.facades = {}
    state.status = contracts.RuntimeStatus.DISABLED
    return state
end

---Marks a healthy or disabled generation as retiring before explicit teardown.
---@return dwarfuicore.ServiceProviderRuntimeState state
function begin_reload()
    local state = validate()
    assert(state.status == contracts.RuntimeStatus.HEALTHY or
            state.status == contracts.RuntimeStatus.DISABLED,
        'DwarfUICore runtime cannot begin reload in its current state.')
    state.status = contracts.RuntimeStatus.RETIRING
    return state
end

---Retires the old generation and publishes an initializing successor.
---@return dwarfuicore.ServiceProviderRuntimeState state
function begin_reconstruction()
    local old = validate()
    assert(old.status == contracts.RuntimeStatus.RETIRING,
        'DwarfUICore runtime is not retiring.')
    old.status = contracts.RuntimeStatus.RETIRED
    assert(old.generation < math.maxinteger,
        'DwarfUICore runtime generation is exhausted.')
    local state = {generation=old.generation + 1,
        status=contracts.RuntimeStatus.INITIALIZING, initializing={},
        services={}, facades={}}
    dfhack.dwarfuicore[PROCESS_SLOT] = state
    return state
end

---Returns one healthy cached service without compatibility negotiation.
---@param service_kind dwarfuicore.ServiceKind
---@param expected_generation? integer
---@return table|nil service
function get_service(service_kind, expected_generation)
    assert(is_service_kind(service_kind),
        'DwarfUICore service kind is invalid.')
    local state = validate_acquirable(expected_generation)
    local record = state.services[service_kind]
    if not record then return nil end
    validate_service_record(record, state.generation)
    assert(record.health == contracts.ServiceHealth.HEALTHY,
        'DwarfUICore service is not healthy.')
    return record.value
end

---Constructs and atomically publishes one missing service idempotently.
---@param service_kind dwarfuicore.ServiceKind
---@param constructor fun(generation: integer): table
---@return table service
---@return boolean created
function initialize_service(service_kind, constructor)
    assert(is_service_kind(service_kind),
        'DwarfUICore service kind is invalid.')
    assert(type(constructor) == 'function',
        'DwarfUICore service initializer must be a function.')
    local state = validate_acquirable()
    local existing = state.services[service_kind]
    if existing then
        validate_service_record(existing, state.generation)
        assert(existing.health == contracts.ServiceHealth.HEALTHY,
            'DwarfUICore existing service is not healthy.')
        return existing.value, false
    end
    assert(not state.initializing[service_kind],
        'DwarfUICore service initialization is already active.')
    state.initializing[service_kind] = true
    local result = table.pack(xpcall(function()
        return constructor(state.generation)
    end, debug.traceback))
    state.initializing[service_kind] = nil
    if not result[1] then error(result[2], 0) end
    local service = result[2]
    assert(type(service) == 'table',
        'DwarfUICore service initializer must return a table.')
    state.services[service_kind] = {generation=state.generation,
        health=contracts.ServiceHealth.HEALTHY, value=service}
    return service, true
end

---Begins one facade acquisition transaction over current runtime state.
---@param service_kind dwarfuicore.ServiceKind
---@param contract_major integer
---@return dwarfuicore.ServiceProviderRuntimeState state
---@return table|nil service
---@return table|nil facade
function begin_service_acquisition(service_kind, contract_major)
    assert(is_service_kind(service_kind),
        'DwarfUICore service kind is invalid.')
    assert(math.type(contract_major) == 'integer' and contract_major > 0,
        'DwarfUICore contract major must be a positive integer.')
    local state = validate_acquirable()
    assert(not state.initializing[service_kind],
        'DwarfUICore service initialization is already active.')
    local service_record = state.services[service_kind]
    assert(service_record == nil or
            service_record.health == contracts.ServiceHealth.HEALTHY,
        'DwarfUICore service is not healthy.')
    local service = service_record and service_record.value or nil
    local facade_cache = state.facades[service_kind]
    assert(service_record ~= nil or facade_cache == nil,
        'DwarfUICore facade cache exists without its service.')
    local facade = facade_cache and facade_cache[contract_major] or nil
    state.initializing[service_kind] = true
    return state, service, facade
end

---Publishes one fully validated service and facade transaction.
---@param service_kind dwarfuicore.ServiceKind
---@param contract_major integer
---@param expected_generation integer
---@param service table
---@param facade table
function publish_service_acquisition(service_kind, contract_major,
        expected_generation, service, facade)
    assert(is_service_kind(service_kind),
        'DwarfUICore service kind is invalid.')
    assert(math.type(contract_major) == 'integer' and contract_major > 0 and
            type(service) == 'table' and type(facade) == 'table',
        'DwarfUICore service acquisition publication is invalid.')
    local state = validate_acquirable(expected_generation)
    assert(state.initializing[service_kind] == true,
        'DwarfUICore service acquisition is not active.')
    local existing_record = state.services[service_kind]
    assert(existing_record == nil or existing_record.value == service,
        'DwarfUICore service acquisition cannot replace a healthy service.')
    local cache = state.facades[service_kind]
    local existing_facade = cache and cache[contract_major] or nil
    assert(existing_facade == nil or existing_facade == facade,
        'DwarfUICore service acquisition cannot replace a facade.')

    local published_services = {}
    for kind, record in next, state.services do
        published_services[kind] = record
    end
    published_services[service_kind] = existing_record or {
        generation=state.generation,
        health=contracts.ServiceHealth.HEALTHY,
        value=service,
    }
    local published_facades = {}
    for kind, existing_cache in next, state.facades do
        published_facades[kind] = existing_cache
    end
    local published_cache = {}
    for major, existing in next, cache or {} do
        published_cache[major] = existing
    end
    published_cache[contract_major] = facade
    published_facades[service_kind] = published_cache

    state.services = published_services
    state.facades = published_facades
    state.initializing[service_kind] = nil
end

---Clears one failed acquisition marker without touching another generation.
---@param service_kind dwarfuicore.ServiceKind
---@param expected_generation integer
function cancel_service_acquisition(service_kind, expected_generation)
    if not is_service_kind(service_kind) then return end
    local state = read_process_state()
    if type(state) ~= 'table' or
            rawget(state, 'generation') ~= expected_generation then
        return
    end
    local initializing = rawget(state, 'initializing')
    if type(initializing) == 'table' then
        initializing[service_kind] = nil
    end
end

---Returns a private facade cached by an adapter-owned opaque key.
---@param service_kind dwarfuicore.ServiceKind
---@param cache_key any
---@return table|nil facade
function get_facade(service_kind, cache_key)
    assert(is_service_kind(service_kind),
        'DwarfUICore service kind is invalid.')
    local state = validate_acquirable()
    local cache = state.facades[service_kind]
    return cache and cache[cache_key] or nil
end

---Caches a validated private facade under an adapter-owned opaque key.
---@param service_kind dwarfuicore.ServiceKind
---@param cache_key any
---@param facade table
function publish_facade(service_kind, cache_key, facade)
    assert(is_service_kind(service_kind) and cache_key ~= nil and
            type(facade) == 'table',
        'DwarfUICore facade publication arguments are invalid.')
    local state = validate_acquirable()
    local cache = state.facades[service_kind]
    if not cache then
        cache = {}
        state.facades[service_kind] = cache
    end
    assert(cache[cache_key] == nil or cache[cache_key] == facade,
        'DwarfUICore facade cache entry cannot be replaced.')
    cache[cache_key] = facade
end
