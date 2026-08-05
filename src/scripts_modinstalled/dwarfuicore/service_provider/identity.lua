--@ module=true

local contracts = reqscript('dwarfuicore/service_provider/contracts')
local namespace = reqscript('dwarfuicore/service_provider/namespace')
local immutable_proxy = reqscript('dwarfuicore/service_provider/immutable_proxy')

local PROCESS_SLOT = 'service_provider_identity'
local HANDLE_IDENTITY_SLOT = 'service_provider_map_handle_identities'
local PROMPT_HANDLE_IDENTITY_SLOT =
    'service_provider_prompt_handle_identities'
local STATE_VERSION = 1
local SEPARATED_HANDLE_STATE_VERSION = 2
local IDENTITY_FIELDS = {
    runtime_generation=true,
    service_kind=true,
    contract_major=true,
    namespace=true,
    local_identity=true,
}
local PROCESS_STATE_FIELDS = {
    version=true,
    next_identity=true,
    next_sequence=true,
}
local SEPARATED_HANDLE_STATE_FIELDS = {
    version=true,
    next_identity=true,
    next_sequence=true,
    map_handle_identities=true,
}
local MAP_COORDINATE_MIN = -0x8000
local MAP_COORDINATE_MAX = 0x7fff
local position_values = setmetatable({}, {__mode='k'})

---Plain reload-stable process identity counter state.
---@class dwarfuicore.ProcessIdentityState
---@field version integer
---@field next_identity integer
---@field next_sequence integer

---Stateless facade over the process-owned identity counters.
---@class dwarfuicore.ProcessIdentityAllocator
ProcessIdentityAllocator = {}

---@class dwarfuicore.CompositeIdentity
---@field runtime_generation integer
---@field service_kind dwarfuicore.ServiceKind
---@field contract_major integer
---@field namespace string
---@field local_identity integer
CompositeIdentity = {}

---@class dwarfuicore.MapTilePosition
---@field x integer
---@field y integer
---@field z integer
MapTilePosition = {}
MapTilePosition.__index = function(position, key)
    local values = position_values[position]
    return values and values[key] or nil
end
MapTilePosition.__newindex = function()
    error('DwarfUICore map tile positions are immutable.', 2)
end
MapTilePosition.__pairs = function(position)
    return next, position_values[position] or {}, nil
end
MapTilePosition.__metatable = false

---@class dwarfuicore.ScreenPosition
---@field x integer
---@field y integer
ScreenPosition = {}
ScreenPosition.__index = function(position, key)
    local values = position_values[position]
    return values and values[key] or nil
end
ScreenPosition.__newindex = function()
    error('DwarfUICore screen positions are immutable.', 2)
end
ScreenPosition.__pairs = function(position)
    return next, position_values[position] or {}, nil
end
ScreenPosition.__metatable = false

---@class dwarfuicore.ContextMenuSelectionContext
---@field screen_position dwarfuicore.ScreenPosition
---@field map_position? dwarfuicore.MapTilePosition
---@field source gui.View|dwarfuicore.ContextMenuMapRegistration
---@field source_root dwarfuicore.PresentationOwner
---@field owner? dwarfuicore.PresentationOwner
ContextMenuSelectionContext = {}
ContextMenuSelectionContext.__index = ContextMenuSelectionContext

local allocated_identity_snapshots = setmetatable({}, {__mode='k'})

---Returns whether a value is a positive integer.
---@param value any
---@return boolean valid
local function is_positive_integer(value)
    return math.type(value) == 'integer' and value > 0
end

---Copy-constructs and validates one exact fortress-map position.
---@param value any
---@return dwarfuicore.MapTilePosition position
function MapTilePosition.new(value)
    local value_type = type(value)
    assert(value_type == 'table' or value_type == 'userdata',
        'DwarfUICore map tile position must be a table or userdata.')
    assert(math.type(value.x) == 'integer' and value.x >= MAP_COORDINATE_MIN and
            value.x <= MAP_COORDINATE_MAX and math.type(value.y) == 'integer' and
            value.y >= MAP_COORDINATE_MIN and value.y <= MAP_COORDINATE_MAX and
            math.type(value.z) == 'integer' and value.z >= MAP_COORDINATE_MIN and
            value.z <= MAP_COORDINATE_MAX,
        'DwarfUICore map tile position requires signed 16-bit x, y, and z.')
    local position = setmetatable({}, MapTilePosition)
    position_values[position] = {x=value.x, y=value.y, z=value.z}
    return position
end

---Copy-constructs and validates one exact interface-cell position.
---@param value any
---@return dwarfuicore.ScreenPosition position
function ScreenPosition.new(value)
    assert(type(value) == 'table' and math.type(value.x) == 'integer' and
            math.type(value.y) == 'integer',
        'DwarfUICore screen position requires integer x and y.')
    local position = setmetatable({}, ScreenPosition)
    position_values[position] = {x=value.x, y=value.y}
    return position
end

---Copy-constructs one approved public context-menu callback context.
---@param value any
---@return dwarfuicore.ContextMenuSelectionContext context
function ContextMenuSelectionContext.new(value)
    assert(type(value) == 'table',
        'DwarfUICore context-menu selection context must be a table.')
    local allowed = {screen_position=true, map_position=true, source=true,
        source_root=true, owner=true}
    for key in pairs(value) do
        assert(type(key) == 'string' and allowed[key],
            ('DwarfUICore context-menu selection context contains ' ..
                'unsupported field %s.'):format(tostring(key)))
    end
    assert(value.source ~= nil and value.source_root ~= nil,
        'DwarfUICore context-menu selection context requires source and source root.')
    local context = {
        screen_position=ScreenPosition.new(value.screen_position),
        source=value.source,
        source_root=value.source_root,
        owner=value.owner,
    }
    if value.map_position ~= nil then
        context.map_position = MapTilePosition.new(value.map_position)
    end
    return setmetatable(context, ContextMenuSelectionContext)
end

---Returns whether a value is a recognized service kind.
---@param value any
---@return boolean valid
local function is_service_kind(value)
    return value == contracts.ServiceKind.TOOLTIP or
        value == contracts.ServiceKind.CONTEXT_MENU or
        value == contracts.ServiceKind.USER_PROMPT
end

---Validates the exact reload-stable counter state shape.
---@param state any
---@return dwarfuicore.ProcessIdentityState state
local function validate_process_state(state)
    assert(type(state) == 'table',
        'DwarfUICore process identity state must be a table.')
    assert(getmetatable(state) == nil,
        'DwarfUICore process identity state must be plain data.')
    for key in next, state do
        assert(PROCESS_STATE_FIELDS[key],
            ('DwarfUICore process identity state contains an unknown field %s.')
                :format(tostring(key)))
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

---Migrates the transient combined state into two compatible process slots.
---@param state table
local function separate_handle_identity_state(state)
    if rawget(state, 'version') ~= SEPARATED_HANDLE_STATE_VERSION then return end
    for key in next, state do
        assert(SEPARATED_HANDLE_STATE_FIELDS[key],
            'DwarfUICore combined identity state contains an unknown field.')
    end
    local identities = rawget(state, 'map_handle_identities')
    local metatable = type(identities) == 'table' and getmetatable(identities)
    assert(type(identities) == 'table' and type(metatable) == 'table' and
            metatable.__mode == 'k',
        'DwarfUICore combined map handle identity registry must have weak keys.')
    dfhack.dwarfuicore[HANDLE_IDENTITY_SLOT] = identities
    state.map_handle_identities = nil
    state.version = STATE_VERSION
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
    separate_handle_identity_state(state)
    return validate_process_state(state)
end

---Returns the reload-stable weak registry that recognizes opaque map handles.
---@return table<table, dwarfuicore.CompositeIdentity> identities
local function get_map_handle_identities()
    assert(type(dfhack) == 'table',
        'DwarfUICore map handle identity lookup requires DFHack process state.')
    if dfhack.dwarfuicore == nil then dfhack.dwarfuicore = {} end
    assert(type(dfhack.dwarfuicore) == 'table',
        'DwarfUICore process namespace must be a table.')
    local identities = dfhack.dwarfuicore[HANDLE_IDENTITY_SLOT]
    if identities == nil then
        identities = setmetatable({}, {__mode='k'})
        dfhack.dwarfuicore[HANDLE_IDENTITY_SLOT] = identities
    end
    local metatable = type(identities) == 'table' and getmetatable(identities)
    assert(type(identities) == 'table' and type(metatable) == 'table' and
            metatable.__mode == 'k',
        'DwarfUICore map handle identity registry must have weak keys.')
    return identities
end

---Returns the reload-stable weak registry that recognizes prompt handles.
---@return table<table, dwarfuicore.CompositeIdentity> identities
local function get_prompt_handle_identities()
    assert(type(dfhack) == 'table',
        'DwarfUICore prompt handle identity lookup requires DFHack process state.')
    if dfhack.dwarfuicore == nil then dfhack.dwarfuicore = {} end
    assert(type(dfhack.dwarfuicore) == 'table',
        'DwarfUICore process namespace must be a table.')
    local identities = dfhack.dwarfuicore[PROMPT_HANDLE_IDENTITY_SLOT]
    if identities == nil then
        identities = setmetatable({}, {__mode='k'})
        dfhack.dwarfuicore[PROMPT_HANDLE_IDENTITY_SLOT] = identities
    end
    local metatable = type(identities) == 'table' and getmetatable(identities)
    assert(type(identities) == 'table' and type(metatable) == 'table' and
            metatable.__mode == 'k',
        'DwarfUICore prompt handle identity registry must have weak keys.')
    return identities
end

---Copy-constructs and validates one complete composite identity.
---@param value any
---@return dwarfuicore.CompositeIdentity identity
function CompositeIdentity.new(value)
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

---Returns whether two complete composite identities have equal fields.
---@param left any
---@param right any
---@return boolean equal
function CompositeIdentity.equals(left, right)
    local ok_left, copied_left = pcall(CompositeIdentity.new, left)
    local ok_right, copied_right = pcall(CompositeIdentity.new, right)
    return ok_left and ok_right and
        copied_left.runtime_generation == copied_right.runtime_generation and
        copied_left.service_kind == copied_right.service_kind and
        copied_left.contract_major == copied_right.contract_major and
        copied_left.namespace == copied_right.namespace and
        copied_left.local_identity == copied_right.local_identity
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
    local identity = CompositeIdentity.new({runtime_generation=runtime_generation,
        service_kind=service_kind, contract_major=contract_major,
        namespace=consumer_namespace, local_identity=state.next_identity})
    allocated_identity_snapshots[identity] = CompositeIdentity.new(identity)
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
local prompt_handle_factory = immutable_proxy.new_factory(
    'map location prompt handle')

---Creates an opaque immutable map-registration handle from copied identity.
---@param identity table
---@return table handle
function create_map_handle(identity)
    local current = CompositeIdentity.new(identity)
    assert(current.service_kind ~= contracts.ServiceKind.USER_PROMPT,
        'DwarfUICore prompt identities require prompt handles.')
    local allocated = allocated_identity_snapshots[identity]
    assert(allocated,
        'DwarfUICore map handle identity was not allocated by this runtime.')
    for field in pairs(IDENTITY_FIELDS) do
        assert(current[field] == allocated[field],
            'DwarfUICore allocated map handle identity was modified.')
    end
    allocated_identity_snapshots[identity] = nil
    local handle = handle_factory:create(CompositeIdentity.new(allocated))
    get_map_handle_identities()[handle] = CompositeIdentity.new(allocated)
    return handle
end

---Returns a copy of a recognized map handle's private identity.
---@param handle any
---@return table|nil identity
function get_map_handle_identity(handle)
    local value = get_map_handle_identities()[handle] or
        handle_factory:get_backing(handle)
    return value and CompositeIdentity.new(value) or nil
end

---Returns whether a value is a recognized map-registration handle.
---@param handle any
---@return boolean recognized
function is_map_handle(handle)
    return get_map_handle_identities()[handle] ~= nil or
        handle_factory:is_instance(handle)
end

---Creates an opaque immutable map-location prompt handle from copied identity.
---@param identity table
---@return dwarfuicore.MapLocationPrompt handle
function create_prompt_handle(identity)
    local current = CompositeIdentity.new(identity)
    assert(current.service_kind == contracts.ServiceKind.USER_PROMPT,
        'DwarfUICore prompt handles require a UserPrompt identity.')
    local allocated = allocated_identity_snapshots[identity]
    assert(allocated,
        'DwarfUICore prompt handle identity was not allocated by this runtime.')
    for field in pairs(IDENTITY_FIELDS) do
        assert(current[field] == allocated[field],
            'DwarfUICore allocated prompt handle identity was modified.')
    end
    allocated_identity_snapshots[identity] = nil
    local handle = prompt_handle_factory:create(CompositeIdentity.new(allocated))
    get_prompt_handle_identities()[handle] = CompositeIdentity.new(allocated)
    return handle
end

---Returns a copy of a recognized prompt handle's private identity.
---@param handle any
---@return table|nil identity
function get_prompt_handle_identity(handle)
    local value = get_prompt_handle_identities()[handle] or
        prompt_handle_factory:get_backing(handle)
    return value and CompositeIdentity.new(value) or nil
end

---Returns whether a value is a recognized map-location prompt handle.
---@param handle any
---@return boolean recognized
function is_prompt_handle(handle)
    return get_prompt_handle_identities()[handle] ~= nil or
        prompt_handle_factory:is_instance(handle)
end

---Classifies a prompt handle against one current API ownership domain.
---@param handle any
---@param runtime_generation integer
---@param contract_major integer
---@param consumer_namespace string
---@return dwarfuicore.CompositeIdentity|nil identity
---@return dwarfuicore.ErrorCategory|nil error_category
function classify_prompt_handle(handle, runtime_generation, contract_major,
        consumer_namespace)
    assert(is_positive_integer(runtime_generation),
        'DwarfUICore runtime generation must be a positive integer.')
    assert(is_positive_integer(contract_major),
        'DwarfUICore contract major must be a positive integer.')
    namespace.validate(consumer_namespace)
    local identity = get_prompt_handle_identity(handle)
    if identity == nil then
        return nil, contracts.ErrorCategory.INVALID_ARGUMENT
    end
    if identity.runtime_generation ~= runtime_generation then
        return nil, contracts.ErrorCategory.STALE_HANDLE
    end
    if identity.service_kind ~= contracts.ServiceKind.USER_PROMPT or
            identity.contract_major ~= contract_major or
            identity.namespace ~= consumer_namespace then
        return nil, contracts.ErrorCategory.FOREIGN_HANDLE
    end
    return identity, nil
end
