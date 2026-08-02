--@ module=true

-- Weak exact-coordinate map-tooltip registration and target detection.

local ViewRootResolver =
    reqscript('dwarfuicore/view_root_resolver').ViewRootResolver
local target_types = reqscript('dwarfuicore/tooltip/target')
local ObservationKind = target_types.TooltipPointerObservationKind
local contracts = reqscript('dwarfuicore/service_provider/contracts')
local identity = reqscript('dwarfuicore/service_provider/identity')
local namespaces = reqscript('dwarfuicore/service_provider/namespace')
local allocator = identity.get_process_allocator()

API_VERSION = 2
local REGISTRY_SLOT = 'tooltip_map_target_registry'
local DEFAULT_NAMESPACE = 'dwarfuicore'
local DEFAULT_CONTRACT_MAJOR = 1
local COORDINATE_MIN = -0x8000
local COORDINATE_MAX = 0x7fff
local COORDINATE_MASK = 0xffff

dfhack.dwarfuicore = dfhack.dwarfuicore or {}

---Creates a weak-key table.
---@return table
local function weak_keys()
    return setmetatable({}, {__mode='k'})
end

---Creates a weak-value table.
---@return table
local function weak_values()
    return setmetatable({}, {__mode='v'})
end

---@class dwarfuicore.TooltipMapTargetProcessState
---@field api_version integer
---@field runtime_generation integer
---@field registrations table
---@field coordinate_index table
---@field registration_sequence integer
---@field generation integer
---@field registry? dwarfuicore.TooltipMapTargetRegistry

---Creates empty runtime-owned process state.
---@param runtime_generation integer
---@return table
local function new_process_state(runtime_generation)
    return {
        api_version=API_VERSION,
        runtime_generation=runtime_generation,
        registrations=weak_keys(),
        coordinate_index=weak_values(),
        registration_sequence=0,
        generation=1,
    }
end

local process_state = dfhack.dwarfuicore[REGISTRY_SLOT]
local runtime_state = dfhack.dwarfuicore.service_provider_runtime
local runtime_generation = runtime_state and runtime_state.generation or 1
local publish_process_state = false
if process_state and (type(process_state) ~= 'table' or
        process_state.api_version ~= API_VERSION) then
    error(('Conflicting DwarfUICore tooltip map-target versions: process ' ..
        'has %s, requested %s.'):format(
            tostring(type(process_state) == 'table' and
                process_state.api_version or nil), tostring(API_VERSION)))
end
if process_state and runtime_generation > 0 then
    assert(process_state.runtime_generation == runtime_generation,
        'DwarfUICore tooltip map targets belong to another runtime generation.')
end
if not process_state then
    process_state = new_process_state(runtime_generation)
    publish_process_state = true
end

---@class dwarfuicore.MapTileTargetObservation
---@field sequence integer
---@field kind dwarfuicore.TooltipPointerObservationKind
---@field pointer_x integer|nil
---@field pointer_y integer|nil
---@field map_x integer|nil
---@field map_y integer|nil
---@field map_z integer|nil
---@field target dwarfuicore.MapTileTooltipRegistration|nil
---@field identity table|nil
---@field target_kind dwarfuicore.TooltipTargetKind|nil
---@field root gui.View|nil
---@field source_root gui.View|nil
---@field registration_sequence integer|nil
---@field tooltip string|nil

---@class dwarfuicore.TooltipMapTargetRegistryOptions
---@field state table
---@field root_resolver dwarfuicore.ViewRootResolver

---@class dwarfuicore.TooltipMapTargetRegistry
---@field _state table
---@field _root_resolver dwarfuicore.ViewRootResolver
---@field _runtime_generation integer
TooltipMapTargetRegistry = {}
TooltipMapTargetRegistry.__index = TooltipMapTargetRegistry

---Returns whether a number is an exact integer.
---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == 'number' and value % 1 == 0
end

---Returns whether a value fits one signed DF coordinate component.
---@param value any
---@return boolean
local function is_signed_16(value)
    return is_integer(value) and
        value >= COORDINATE_MIN and
        value <= COORDINATE_MAX
end

---Packs one signed-16-bit DF coordinate into a collision-free 48-bit key.
---@param x integer
---@param y integer
---@param z integer
---@return integer
local function coordinate_key(x, y, z)
    return ((x & COORDINATE_MASK) << 32) |
        ((y & COORDINATE_MASK) << 16) |
        (z & COORDINATE_MASK)
end

---Validates and copies complete mutable registration state.
---@param options table
---@param label string
---@return integer x
---@return integer y
---@return integer z
---@return string|nil tooltip
local function copy_mutable_state(options, label)
    assert(type(options) == 'table',
        ('DwarfUICore %s must be a table.'):format(label))
    local pos = options.pos
    local pos_type = type(pos)
    assert(pos_type == 'table' or pos_type == 'userdata',
        ('DwarfUICore %s requires an exact map position.'):format(label))
    assert(is_signed_16(pos.x) and is_signed_16(pos.y) and is_signed_16(pos.z),
        ('DwarfUICore %s position requires signed 16-bit integer x, y, and z.'):format(label))
    assert(options.tooltip == nil or type(options.tooltip) == 'string',
        ('DwarfUICore %s tooltip must be a string or nil.'):format(label))
    return pos.x, pos.y, pos.z, options.tooltip
end

---Validates one private tooltip registration ownership domain.
---@param consumer_namespace any
---@param contract_major any
---@return string consumer_namespace
---@return integer contract_major
local function validate_domain(consumer_namespace, contract_major)
    namespaces.validate(consumer_namespace)
    assert(math.type(contract_major) == 'integer' and contract_major > 0,
        'DwarfUICore tooltip contract major must be a positive integer.')
    return consumer_namespace, contract_major
end

---Normalizes the temporary legacy direct-registry registration signature.
---@param namespace_or_options any
---@param options_or_major any
---@param contract_major any
---@return string consumer_namespace
---@return integer contract_major
---@return table options
local function normalize_registration(namespace_or_options, options_or_major,
        contract_major)
    if type(namespace_or_options) == 'table' and options_or_major == nil then
        return DEFAULT_NAMESPACE, DEFAULT_CONTRACT_MAJOR, namespace_or_options
    end
    local consumer_namespace = namespace_or_options
    local options = options_or_major
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major or DEFAULT_CONTRACT_MAJOR)
    return consumer_namespace, contract_major, options
end

---Returns and validates one recognized handle's composite ownership identity.
---@param handle any
---@param consumer_namespace string
---@param contract_major integer
---@return table handle_identity
local function validate_handle_domain(handle, consumer_namespace,
        contract_major)
    validate_domain(consumer_namespace, contract_major)
    local handle_identity = identity.get_map_handle_identity(handle)
    assert(handle_identity,
        'DwarfUICore tooltip map handle is not recognized.')
    assert(handle_identity.runtime_generation == runtime_generation,
        'DwarfUICore tooltip map handle belongs to another runtime generation.')
    assert(handle_identity.service_kind == contracts.ServiceKind.TOOLTIP and
            handle_identity.contract_major == contract_major and
            handle_identity.namespace == consumer_namespace,
        'DwarfUICore tooltip map handle belongs to another service domain.')
    return handle_identity
end

---Builds one presentation-neutral miss observation.
---@param sample dwarfuicore.PointerSample
---@return dwarfuicore.MapTileTargetObservation
local function miss(sample)
    return {
        sequence=sample.sequence,
        kind=ObservationKind.MISS,
        pointer_x=sample.x,
        pointer_y=sample.y,
        map_x=sample.map_x,
        map_y=sample.map_y,
        map_z=sample.map_z,
    }
end

---Creates a registry over reload-safe state and shared root eligibility.
---@param options dwarfuicore.TooltipMapTargetRegistryOptions
---@return dwarfuicore.TooltipMapTargetRegistry
function TooltipMapTargetRegistry.new(options)
    assert(type(options) == 'table',
        'DwarfUICore map target registry requires options.')
    assert(type(options.state) == 'table',
        'DwarfUICore map target registry requires process state.')
    assert(type(options.root_resolver) == 'table' and
            type(options.root_resolver.resolve) == 'function',
        'DwarfUICore map target registry requires a root resolver.')
    return setmetatable({
        _state=options.state,
        _root_resolver=options.root_resolver,
        _runtime_generation=options.state.runtime_generation or 0,
    }, TooltipMapTargetRegistry)
end

---Rejects use after the owning core runtime generation changes.
function TooltipMapTargetRegistry:_assert_current()
    local current = dfhack.dwarfuicore.service_provider_runtime
    local generation = current and current.generation or 1
    assert(self._runtime_generation == generation,
        'DwarfUICore tooltip map targets belong to another runtime generation.')
end

---Returns or creates the weak bucket for one exact coordinate.
---@param key integer
---@return table
function TooltipMapTargetRegistry:_get_or_create_bucket(key)
    local index = self._state.coordinate_index
    local bucket = index[key]
    if bucket then return bucket end
    bucket = weak_keys()
    index[key] = bucket
    return bucket
end

---Removes one handle from its current bucket and drops an empty bucket.
---@param handle dwarfuicore.MapTileTooltipRegistration
---@param record table
function TooltipMapTargetRegistry:_remove_from_bucket(handle, record)
    local bucket = record.bucket
    bucket[handle] = nil
    if next(bucket) == nil then
        self._state.coordinate_index[record.coordinate_key] = nil
    end
end

---Registers one caller-owned exact map-tile tooltip handle.
---@param namespace_or_options string|dwarfuicore.MapTileTooltipRegistrationOptions
---@param options_or_major? dwarfuicore.MapTileTooltipRegistrationOptions
---@param contract_major? integer
---@return dwarfuicore.MapTileTooltipRegistration
function TooltipMapTargetRegistry:register(namespace_or_options,
        options_or_major, contract_major)
    self:_assert_current()
    local consumer_namespace, resolved_major, options =
        normalize_registration(namespace_or_options, options_or_major,
            contract_major)
    assert(type(options) == 'table',
        'DwarfUICore map-tile registration options must be a table.')
    assert(type(options.owner) == 'table',
        'DwarfUICore map-tile registration requires an owner view.')
    local x, y, z, tooltip =
        copy_mutable_state(options, 'map-tile registration')
    local state = self._state
    local private_identity = allocator:allocate_identity(runtime_generation,
        contracts.ServiceKind.TOOLTIP, resolved_major, consumer_namespace)
    local handle = identity.create_map_handle(private_identity)
    local contribution_sequence = allocator:allocate_sequence()
    state.registration_sequence = contribution_sequence
    local key = coordinate_key(x, y, z)
    local bucket = self:_get_or_create_bucket(key)
    local record = {
        identity=private_identity,
        namespace=consumer_namespace,
        contract_major=resolved_major,
        owner=options.owner,
        x=x,
        y=y,
        z=z,
        tooltip=tooltip,
        sequence=contribution_sequence,
        coordinate_key=key,
        bucket=bucket,
    }
    state.registrations[handle] = record
    bucket[handle] = record
    return handle
end

---Atomically replaces one handle's exact position and tooltip text.
---@param namespace_or_handle string|dwarfuicore.MapTileTooltipRegistration
---@param handle_or_update dwarfuicore.MapTileTooltipRegistration|dwarfuicore.MapTileTooltipUpdate
---@param update_or_major? dwarfuicore.MapTileTooltipUpdate
---@param contract_major? integer
---@return boolean updated
function TooltipMapTargetRegistry:update(namespace_or_handle, handle_or_update,
        update_or_major, contract_major)
    self:_assert_current()
    local consumer_namespace, handle, update
    if identity.is_map_handle(namespace_or_handle) then
        consumer_namespace, contract_major, handle, update =
            DEFAULT_NAMESPACE, DEFAULT_CONTRACT_MAJOR,
            namespace_or_handle, handle_or_update
    else
        consumer_namespace, handle, update = namespace_or_handle,
            handle_or_update, update_or_major
        contract_major = contract_major or DEFAULT_CONTRACT_MAJOR
    end
    validate_handle_domain(handle, consumer_namespace, contract_major)
    local record = self._state.registrations[handle]
    if not record then return false end
    local x, y, z, tooltip =
        copy_mutable_state(update, 'map-tile update')
    local key = coordinate_key(x, y, z)
    if key ~= record.coordinate_key then
        self:_remove_from_bucket(handle, record)
        local bucket = self:_get_or_create_bucket(key)
        record.coordinate_key = key
        record.bucket = bucket
        bucket[handle] = record
    end
    record.x, record.y, record.z = x, y, z
    record.tooltip = tooltip
    return true
end

---Explicitly removes one handle and its empty exact-coordinate bucket.
---@param namespace_or_handle string|dwarfuicore.MapTileTooltipRegistration
---@param handle_or_major? dwarfuicore.MapTileTooltipRegistration
---@param contract_major? integer
---@return boolean removed
function TooltipMapTargetRegistry:unregister(namespace_or_handle,
        handle_or_major, contract_major)
    self:_assert_current()
    local consumer_namespace, handle
    if identity.is_map_handle(namespace_or_handle) then
        consumer_namespace, contract_major, handle =
            DEFAULT_NAMESPACE, DEFAULT_CONTRACT_MAJOR, namespace_or_handle
    else
        consumer_namespace, handle = namespace_or_handle, handle_or_major
        contract_major = contract_major or DEFAULT_CONTRACT_MAJOR
    end
    validate_handle_domain(handle, consumer_namespace, contract_major)
    local record = self._state.registrations[handle]
    if not record then return false end
    self:_remove_from_bucket(handle, record)
    self._state.registrations[handle] = nil
    return true
end

---Counts live weak registrations without retaining their handles.
---@param consumer_namespace? string
---@return integer
function TooltipMapTargetRegistry:registration_count(consumer_namespace)
    self:_assert_current()
    local count = 0
    for _, record in pairs(self._state.registrations) do
        if consumer_namespace == nil or
                record.namespace == consumer_namespace then
            count = count + 1
        end
    end
    return count
end

---Returns whether one opaque handle remains registered.
---@param handle dwarfuicore.MapTileTooltipRegistration
---@return boolean
function TooltipMapTargetRegistry:contains(handle)
    self:_assert_current()
    return self._state.registrations[handle] ~= nil
end

---Returns whether a handle still owns the exact composite identity.
---@param handle dwarfuicore.MapTileTooltipRegistration
---@param expected_identity table
---@return boolean current
function TooltipMapTargetRegistry:contains_identity(handle, expected_identity)
    self:_assert_current()
    local record = self._state.registrations[handle]
    return record ~= nil and record.identity == expected_identity
end

---Returns a snapshot of one live handle's composite identity.
---@param handle dwarfuicore.MapTileTooltipRegistration
---@return table|nil composite_identity
function TooltipMapTargetRegistry:get_identity(handle)
    self:_assert_current()
    local record = self._state.registrations[handle]
    return record and identity.CompositeIdentity.new(record.identity) or nil
end

---Returns one handle's current tooltip value without exposing its record.
---@param handle dwarfuicore.MapTileTooltipRegistration
---@return string|nil
function TooltipMapTargetRegistry:get_tooltip(handle)
    self:_assert_current()
    local record = self._state.registrations[handle]
    return record and record.tooltip or nil
end

---Removes every live map registration in one namespace and contract.
---@param consumer_namespace string
---@param contract_major? integer
---@return table[] removed
function TooltipMapTargetRegistry:clear_namespace(consumer_namespace,
        contract_major)
    self:_assert_current()
    contract_major = contract_major or DEFAULT_CONTRACT_MAJOR
    validate_domain(consumer_namespace, contract_major)
    local handles = {}
    for handle, record in pairs(self._state.registrations) do
        if record.namespace == consumer_namespace and
                record.contract_major == contract_major then
            table.insert(handles, handle)
        end
    end
    local removed = {}
    for _, handle in ipairs(handles) do
        local record = self._state.registrations[handle]
        if record then
            table.insert(removed, record)
            self:_remove_from_bucket(handle, record)
            self._state.registrations[handle] = nil
        end
    end
    return removed
end

---Builds the current presented owner-root set for screen-space occlusion.
---@return table<gui.View, integer>
function TooltipMapTargetRegistry:get_owner_roots()
    self:_assert_current()
    local roots = {}
    for _, record in pairs(self._state.registrations) do
        local root = self._root_resolver:resolve(record.owner, true)
        if root and (roots[root] == nil or
                record.sequence > roots[root]) then
            roots[root] = record.sequence
        end
    end
    return roots
end

---Detects one deterministic eligible target at the sampled exact map tile.
---@param sample dwarfuicore.PointerSample
---@return dwarfuicore.MapTileTargetObservation
function TooltipMapTargetRegistry:detect(sample)
    self:_assert_current()
    assert(type(sample) == 'table',
        'DwarfUICore map target detector requires a pointer sample.')
    assert(type(sample.sequence) == 'number',
        'DwarfUICore map target sample sequence must be a number.')
    if sample.x == nil or sample.y == nil or
            not is_signed_16(sample.map_x) or
            not is_signed_16(sample.map_y) or
            not is_signed_16(sample.map_z) then
        return miss(sample)
    end

    local key = coordinate_key(sample.map_x, sample.map_y, sample.map_z)
    local bucket = self._state.coordinate_index[key]
    if not bucket then return miss(sample) end

    local winner
    for handle, record in pairs(bucket) do
        if self._state.registrations[handle] == record then
            local root = self._root_resolver:resolve(record.owner, true)
            if root and (not winner or
                    record.sequence > winner.record.sequence) then
                winner = {handle=handle, record=record, root=root}
            end
        end
    end
    if not winner then return miss(sample) end

    return {
        sequence=sample.sequence,
        kind=ObservationKind.TARGET,
        pointer_x=sample.x,
        pointer_y=sample.y,
        map_x=sample.map_x,
        map_y=sample.map_y,
        map_z=sample.map_z,
        target=winner.handle,
        identity=winner.record.identity,
        target_kind=target_types.TooltipTargetKind.MAP_TILE,
        root=winner.root,
        source_root=winner.root,
        registration_sequence=winner.record.sequence,
        tooltip=winner.record.tooltip,
    }
end

---Returns reload, registration, and exact-index diagnostics.
---@param consumer_namespace? string
---@return table diagnostics
function TooltipMapTargetRegistry:get_diagnostics(consumer_namespace)
    self:_assert_current()
    local bucket_count = 0
    for _ in pairs(self._state.coordinate_index) do
        bucket_count = bucket_count + 1
    end
    local registrations = {}
    for _, record in pairs(self._state.registrations) do
        if consumer_namespace == nil or
                record.namespace == consumer_namespace then
            table.insert(registrations, {
                identity=identity.CompositeIdentity.new(record.identity),
                contribution_sequence=record.sequence,
                map_position={x=record.x, y=record.y, z=record.z},
            })
        end
    end
    table.sort(registrations, function(left, right)
        return left.contribution_sequence < right.contribution_sequence
    end)
    return {
        api_version=self._state.api_version,
        generation=self._state.generation,
        registration_count=self:registration_count(consumer_namespace),
        coordinate_bucket_count=bucket_count,
        registration_sequence=self._state.registration_sequence,
        registrations=registrations,
    }
end

registry = process_state.registry
if not registry then
    registry = TooltipMapTargetRegistry.new{
        state=process_state,
        root_resolver=ViewRootResolver.new(),
    }
    process_state.registry = registry
end
if publish_process_state then
    dfhack.dwarfuicore[REGISTRY_SLOT] = process_state
end
