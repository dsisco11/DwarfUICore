--@ module=true

local contracts = reqscript('dwarfuicore/service_provider/contracts')
local namespace = reqscript('dwarfuicore/service_provider/namespace')
local immutable_proxy = reqscript('dwarfuicore/service_provider/immutable_proxy')

local PROCESS_SLOT = 'service_provider_identity'
local STATE_VERSION = 1
local IDENTITY_FIELDS = {
    runtime_generation=true,
    service_kind=true,
    contract_major=true,
    namespace=true,
    local_identity=true,
}

---Plain reload-stable process identity counter state.
---@class dwarfuicore.ProcessIdentityState
---@field version integer
---@field next_identity integer
---@field next_sequence integer

---Stateless facade over the process-owned identity counters.
---@class dwarfuicore.ProcessIdentityAllocator
ProcessIdentityAllocator = {}

local allocated_identity_snapshots = setmetatable({}, {__mode='k'})

---Returns whether a value is a positive integer.
---@param value any
---@return boolean valid
local function is_positive_integer(value)
    return math.type(value) == 'integer' and value > 0
end

---Returns whether a value is a recognized service kind.
---@param value any
---@return boolean valid
local function is_service_kind(value)
    return value == contracts.ServiceKind.TOOLTIP or
        value == contracts.ServiceKind.CONTEXT_MENU
end

---Validates the exact reload-stable counter state shape.
---@param state any
---@return dwarfuicore.ProcessIdentityState state
local function validate_process_state(state)
    assert(type(state) == 'table',
        'DwarfUICore process identity state must be a table.')
    assert(getmetatable(state) == nil,
        'DwarfUICore process identity state must be plain data.')
    local expected = {version=true, next_identity=true, next_sequence=true}
    for key in next, state do
        assert(expected[key],
            'DwarfUICore process identity state contains an unknown field.')
    end
    assert(rawget(state, 'version') == STATE_VERSION,
        'DwarfUICore process identity state version is unsupported.')
    assert(math.type(rawget(state, 'next_identity')) == 'integer' and
            rawget(state, 'next_identity') >= 0,
        'DwarfUICore next identity must be a non-negative integer.')
    assert(math.type(rawget(state, 'next_sequence')) == 'integer' and
            rawget(state, 'next_sequence') >= 0,
        'DwarfUICore next sequence must be a non-negative integer.')
    return state
end

---Returns the one process-owned counter state, creating it when absent.
---@return dwarfuicore.ProcessIdentityState state
local function get_process_state()
    assert(type(dfhack) == 'table',
        'DwarfUICore identity allocation requires DFHack process state.')
    if dfhack.dwarfuicore == nil then dfhack.dwarfuicore = {} end
    assert(type(dfhack.dwarfuicore) == 'table',
        'DwarfUICore process namespace must be a table.')
    local state = dfhack.dwarfuicore[PROCESS_SLOT]
    if state == nil then
        state = {version=STATE_VERSION, next_identity=0, next_sequence=0}
        dfhack.dwarfuicore[PROCESS_SLOT] = state
    end
    return validate_process_state(state)
end

---Copies and validates one complete composite identity.
---@param value any
---@return table identity
local function copy_identity(value)
    assert(type(value) == 'table',
        'DwarfUICore map handle identity must be a table.')
    for key in next, value do
        assert(IDENTITY_FIELDS[key],
            'DwarfUICore map handle identity contains an unknown field.')
    end
    local runtime_generation = rawget(value, 'runtime_generation')
    local service_kind = rawget(value, 'service_kind')
    local contract_major = rawget(value, 'contract_major')
    local consumer_namespace = rawget(value, 'namespace')
    local local_identity = rawget(value, 'local_identity')
    assert(is_positive_integer(runtime_generation),
        'DwarfUICore runtime generation must be a positive integer.')
    assert(is_service_kind(service_kind),
        'DwarfUICore service kind is invalid.')
    assert(is_positive_integer(contract_major),
        'DwarfUICore contract major must be a positive integer.')
    namespace.validate(consumer_namespace)
    assert(is_positive_integer(local_identity),
        'DwarfUICore local identity must be a positive integer.')
    return {runtime_generation=runtime_generation, service_kind=service_kind,
        contract_major=contract_major, namespace=consumer_namespace,
        local_identity=local_identity}
end

---Allocates one internal composite registration identity.
---@param runtime_generation integer
---@param service_kind dwarfuicore.ServiceKind
---@param contract_major integer
---@param consumer_namespace string
---@return table identity
function ProcessIdentityAllocator:allocate_identity(runtime_generation,
        service_kind, contract_major, consumer_namespace)
    assert(is_positive_integer(runtime_generation),
        'DwarfUICore runtime generation must be a positive integer.')
    assert(is_service_kind(service_kind),
        'DwarfUICore service kind is invalid.')
    assert(is_positive_integer(contract_major),
        'DwarfUICore contract major must be a positive integer.')
    namespace.validate(consumer_namespace)
    local state = get_process_state()
    assert(state.next_identity < math.maxinteger,
        'DwarfUICore process identity counter is exhausted.')
    state.next_identity = state.next_identity + 1
    local identity = copy_identity({runtime_generation=runtime_generation,
        service_kind=service_kind, contract_major=contract_major,
        namespace=consumer_namespace, local_identity=state.next_identity})
    allocated_identity_snapshots[identity] = copy_identity(identity)
    return identity
end

---Allocates one process-wide ordering sequence.
---@return integer sequence
function ProcessIdentityAllocator:allocate_sequence()
    local state = get_process_state()
    assert(state.next_sequence < math.maxinteger,
        'DwarfUICore process sequence counter is exhausted.')
    state.next_sequence = state.next_sequence + 1
    return state.next_sequence
end

---Copies the current process counters for private diagnostics.
---@return dwarfuicore.ProcessIdentityState state
function ProcessIdentityAllocator:snapshot()
    local state = get_process_state()
    return {version=state.version, next_identity=state.next_identity,
        next_sequence=state.next_sequence}
end

---Returns the stateless facade over the one process allocator authority.
---@return dwarfuicore.ProcessIdentityAllocator allocator
function get_process_allocator()
    return ProcessIdentityAllocator
end

local handle_factory = immutable_proxy.new_factory('map registration handle')

---Creates an opaque immutable map-registration handle from copied identity.
---@param identity table
---@return table handle
function create_map_handle(identity)
    local current = copy_identity(identity)
    local allocated = allocated_identity_snapshots[identity]
    assert(allocated,
        'DwarfUICore map handle identity was not allocated by this runtime.')
    for field in pairs(IDENTITY_FIELDS) do
        assert(current[field] == allocated[field],
            'DwarfUICore allocated map handle identity was modified.')
    end
    allocated_identity_snapshots[identity] = nil
    return handle_factory:create(copy_identity(allocated))
end

---Returns a copy of a recognized map handle's private identity.
---@param handle any
---@return table|nil identity
function get_map_handle_identity(handle)
    local value = handle_factory:get_backing(handle)
    return value and copy_identity(value) or nil
end

---Returns whether a value is a recognized map-registration handle.
---@param handle any
---@return boolean recognized
function is_map_handle(handle)
    return handle_factory:is_instance(handle)
end
