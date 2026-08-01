--@ module=true

local immutable_proxy = reqscript('dwarfuicore/service_provider/immutable_proxy')

---Monotonic registration identity and ordering allocator.
---@class dwarfuicore.IdentityAllocator
---@field private _next_identity integer
---@field private _next_sequence integer
IdentityAllocator = {}
IdentityAllocator.__index = IdentityAllocator

---Creates an allocator from optional persisted counters.
---@param state? {next_identity?: integer, next_sequence?: integer}
---@return dwarfuicore.IdentityAllocator allocator
function IdentityAllocator.new(state)
    state = state or {}
    local next_identity = state.next_identity or 0
    local next_sequence = state.next_sequence or 0
    assert(math.type(next_identity) == 'integer' and next_identity >= 0,
        'DwarfUICore next identity must be a non-negative integer.')
    assert(math.type(next_sequence) == 'integer' and next_sequence >= 0,
        'DwarfUICore next sequence must be a non-negative integer.')
    return setmetatable({_next_identity=next_identity,
        _next_sequence=next_sequence}, IdentityAllocator)
end

---Allocates one internal composite registration identity.
---@param runtime_generation integer
---@param service_kind integer
---@param contract_major integer
---@param namespace string
---@return table identity
function IdentityAllocator:allocate_identity(runtime_generation, service_kind,
        contract_major, namespace)
    self._next_identity = self._next_identity + 1
    return {runtime_generation=runtime_generation, service_kind=service_kind,
        contract_major=contract_major, namespace=namespace,
        local_identity=self._next_identity}
end

---Allocates one process-wide ordering sequence.
---@return integer sequence
function IdentityAllocator:allocate_sequence()
    self._next_sequence = self._next_sequence + 1
    return self._next_sequence
end

---Copies allocator counters for later process-state publication.
---@return {next_identity: integer, next_sequence: integer} state
function IdentityAllocator:snapshot()
    return {next_identity=self._next_identity,
        next_sequence=self._next_sequence}
end

---Returns the one allocator retained by a private process-state record.
---@param process_state table
---@return dwarfuicore.IdentityAllocator allocator
function get_process_allocator(process_state)
    assert(type(process_state) == 'table',
        'DwarfUICore process state must be a table.')
    local allocator = process_state.identity_allocator
    if allocator then
        assert(getmetatable(allocator) == IdentityAllocator,
            'DwarfUICore process identity allocator is malformed.')
        return allocator
    end
    allocator = IdentityAllocator.new(process_state.identity_counters)
    process_state.identity_allocator = allocator
    return allocator
end

local handle_factory = immutable_proxy.new_factory('map registration handle')

---Creates an opaque immutable map-registration handle.
---@param identity table
---@return table handle
function create_map_handle(identity)
    assert(type(identity) == 'table',
        'DwarfUICore map handle identity must be a table.')
    return handle_factory:create(identity)
end

---Returns the private identity for a recognized map-registration handle.
---@param handle any
---@return table|nil identity
function get_map_handle_identity(handle)
    return handle_factory:get_backing(handle)
end

---Returns whether a value is a recognized map-registration handle.
---@param handle any
---@return boolean recognized
function is_map_handle(handle)
    return handle_factory:is_instance(handle)
end
