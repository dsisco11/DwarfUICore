--@ module=true

-- Weak exact-coordinate map-tile context-menu registrations.

local definitions = reqscript('dwarfuicore/context_menu/definition')
local targets = reqscript('dwarfuicore/context_menu/target')
local contracts = reqscript('dwarfuicore/service_provider/contracts')
local identities = reqscript('dwarfuicore/service_provider/identity')
local namespaces = reqscript('dwarfuicore/service_provider/namespace')
local ViewRootResolver =
    reqscript('dwarfuicore/view_root_resolver').ViewRootResolver

local COORDINATE_MASK = 0xffff
local DEFAULT_NAMESPACE = 'dwarfuicore'
local DEFAULT_CONTRACT_MAJOR = 1

---@class dwarfuicore.ContextMenuMapRegistrationOptions
---@field owner any
---@field pos {x: integer, y: integer, z: integer}
---@field definition dwarfuicore.ContextMenuDefinition

---@class dwarfuicore.ContextMenuMapRegistrationUpdate
---@field pos {x: integer, y: integer, z: integer}
---@field definition dwarfuicore.ContextMenuDefinition

---@class dwarfuicore.ContextMenuMapCandidate
---@field identity table
---@field namespace string
---@field contract_major integer
---@field sequence integer
---@field source any
---@field owner any
---@field root any
---@field pos {x: integer, y: integer, z: integer}
---@field _definition dwarfuicore.ContextMenuDefinitionSlot
ContextMenuMapCandidate = {}
ContextMenuMapCandidate.__index = ContextMenuMapCandidate

---@class dwarfuicore.ContextMenuMapTargetRegistryOptions
---@field allocator? dwarfuicore.ProcessIdentityAllocator
---@field runtime_generation? integer
---@field root_resolver? dwarfuicore.ViewRootResolver
---@field find_attachment_root? fun(owner: any, allow_owner_root: boolean): any|nil

---@class dwarfuicore.ContextMenuMapTargetRegistry
---@field _allocator dwarfuicore.ProcessIdentityAllocator
---@field _runtime_generation integer
---@field _root_resolver dwarfuicore.ViewRootResolver
---@field _find_attachment_root fun(owner: any, allow_owner_root: boolean): any|nil
---@field _registrations table<any, table>
---@field _coordinate_index table<integer, table<any, table>>
---@field _registration_sequence integer
ContextMenuMapTargetRegistry = {}
ContextMenuMapTargetRegistry.__index = ContextMenuMapTargetRegistry

local REGISTRATION_FIELDS = {
    owner=true,
    pos=true,
    definition=true,
}
local UPDATE_FIELDS = {
    pos=true,
    definition=true,
}

---Rejects fields outside one exact map-registration shape.
---@param value table
---@param fields table<string, boolean>
---@param label string
local function validate_fields(value, fields, label)
    for field in pairs(value) do
        assert(type(field) == 'string' and fields[field],
            ('DwarfUICore %s contains unsupported field %s.'):format(
                label, tostring(field)))
    end
end

---Packs one signed-16-bit DF coordinate into a collision-free 48-bit key.
---@param position {x: integer, y: integer, z: integer}
---@return integer
local function pack_coordinate(position)
    return ((position.x & COORDINATE_MASK) << 32) |
        ((position.y & COORDINATE_MASK) << 16) |
        (position.z & COORDINATE_MASK)
end

---Creates a weak-value owner reference.
---@param owner any
---@return table
local function weak_owner(owner)
    return setmetatable({owner=owner}, {__mode='v'})
end

---Creates a weak-key registration bucket.
---@return table<any, table>
local function weak_bucket()
    return setmetatable({}, {__mode='k'})
end

---Validates one namespace-bound context-menu ownership domain.
---@param consumer_namespace any
---@param contract_major? any
---@return string consumer_namespace
---@return integer contract_major
local function validate_domain(consumer_namespace, contract_major)
    namespaces.validate(consumer_namespace)
    contract_major = contract_major or DEFAULT_CONTRACT_MAJOR
    assert(math.type(contract_major) == 'integer' and contract_major > 0,
        'DwarfUICore context-menu contract major must be positive.')
    return consumer_namespace, contract_major
end

---Validates that an opaque handle belongs to the requested active domain.
---@param handle any
---@param consumer_namespace string
---@param contract_major integer
---@param runtime_generation integer
---@return table identity
local function validate_handle(handle, consumer_namespace, contract_major,
        runtime_generation)
    local identity = identities.get_map_handle_identity(handle)
    assert(identity ~= nil,
        'DwarfUICore context-menu map handle is invalid.')
    assert(identity.runtime_generation == runtime_generation,
        'DwarfUICore context-menu map handle is stale.')
    assert(identity.service_kind == contracts.ServiceKind.CONTEXT_MENU and
            identity.contract_major == contract_major and
            identity.namespace == consumer_namespace,
        'DwarfUICore context-menu map handle belongs to another service domain.')
    return identity
end

---Returns an isolated opening definition for this candidate.
---@return dwarfuicore.ContextMenuDefinitionSnapshot
function ContextMenuMapCandidate:get_definition_snapshot()
    return self._definition:snapshot()
end

---Creates a weak exact-coordinate registry.
---@param options? dwarfuicore.ContextMenuMapTargetRegistryOptions
---@return dwarfuicore.ContextMenuMapTargetRegistry
function ContextMenuMapTargetRegistry.new(options)
    options = options or {}
    assert(type(options) == 'table',
        'DwarfUICore map-target registry options must be a table.')
    assert(options.allocator == nil or
            type(options.allocator.allocate_identity) == 'function',
        'DwarfUICore map-target allocator must allocate identities.')
    assert(options.runtime_generation == nil or
            (math.type(options.runtime_generation) == 'integer' and
                options.runtime_generation > 0),
        'DwarfUICore map-target runtime generation must be positive.')
    assert(options.root_resolver == nil or
            type(options.root_resolver.resolve) == 'function',
        'DwarfUICore map-target root resolver must resolve owners.')
    assert(options.find_attachment_root == nil or
            type(options.find_attachment_root) == 'function',
        'DwarfUICore map-target attachment resolver must be a function.')
    return setmetatable({
        _allocator=options.allocator or identities.get_process_allocator(),
        _runtime_generation=options.runtime_generation or 1,
        _root_resolver=options.root_resolver or ViewRootResolver.new(),
        _find_attachment_root=options.find_attachment_root or
            function() return nil end,
        _registrations=setmetatable({}, {__mode='k'}),
        _coordinate_index={},
        _registration_sequence=0,
    }, ContextMenuMapTargetRegistry)
end

---Returns or creates the weak registration bucket for one coordinate.
---@param key integer
---@return table<any, table>
function ContextMenuMapTargetRegistry:_get_or_create_bucket(key)
    local bucket = self._coordinate_index[key]
    if bucket then return bucket end
    bucket = weak_bucket()
    self._coordinate_index[key] = bucket
    return bucket
end

---Removes one record from its coordinate bucket.
---@param handle any
---@param record table
function ContextMenuMapTargetRegistry:_remove_from_bucket(handle, record)
    local bucket = self._coordinate_index[record.packed_coordinate]
    if not bucket then return end
    bucket[handle] = nil
    if next(bucket) == nil then
        self._coordinate_index[record.packed_coordinate] = nil
    end
end

---Drops dead-owner records and empty weak coordinate buckets.
function ContextMenuMapTargetRegistry:_prune()
    for handle, record in pairs(self._registrations) do
        if record.owner_ref.owner == nil then
            self:_remove_from_bucket(handle, record)
            self._registrations[handle] = nil
        end
    end
    for key, bucket in pairs(self._coordinate_index) do
        if next(bucket) == nil then self._coordinate_index[key] = nil end
    end
end

---Registers one weak-owner exact map tile and returns its opaque handle.
---@param consumer_namespace string|dwarfuicore.ContextMenuMapRegistrationOptions
---@param options? dwarfuicore.ContextMenuMapRegistrationOptions
---@param contract_major? integer
---@return any handle
function ContextMenuMapTargetRegistry:register(consumer_namespace, options,
        contract_major)
    if options == nil and type(consumer_namespace) == 'table' then
        options, consumer_namespace = consumer_namespace, DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    assert(type(options) == 'table',
        'DwarfUICore map-tile registration options must be a table.')
    validate_fields(options, REGISTRATION_FIELDS, 'map-tile registration')
    assert(type(options.owner) == 'table',
        'DwarfUICore map-tile registration requires an owner.')
    local position = identities.Position3D.new(options.pos)
    local definition = definitions.ContextMenuDefinitionSlot.new(
        options.definition)

    local key = pack_coordinate(position)
    local registration_identity = self._allocator:allocate_identity(
        self._runtime_generation, contracts.ServiceKind.CONTEXT_MENU,
        contract_major, consumer_namespace)
    local handle = identities.create_map_handle(registration_identity)
    local record = {
        identity=registration_identity,
        namespace=consumer_namespace,
        contract_major=contract_major,
        sequence=self._allocator:allocate_sequence(),
        owner_ref=weak_owner(options.owner),
        pos=position,
        packed_coordinate=key,
        definition=definition,
    }
    self._registrations[handle] = record
    self:_get_or_create_bucket(key)[handle] = record
    return handle
end

---Atomically replaces one owned handle's copied position and definition.
---@param consumer_namespace string|any
---@param handle any|dwarfuicore.ContextMenuMapRegistrationUpdate
---@param update? dwarfuicore.ContextMenuMapRegistrationUpdate
---@param contract_major? integer
---@return boolean updated
function ContextMenuMapTargetRegistry:update(consumer_namespace, handle, update,
        contract_major)
    if identities.is_map_handle(consumer_namespace) then
        update, handle, consumer_namespace = handle, consumer_namespace,
            DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    local handle_identity = validate_handle(handle, consumer_namespace,
        contract_major, self._runtime_generation)
    local record = self._registrations[handle]
    if not record or record.owner_ref.owner == nil then
        if record then
            self:_remove_from_bucket(handle, record)
            self._registrations[handle] = nil
        end
        return false
    end
    assert(record.identity.local_identity == handle_identity.local_identity,
        'DwarfUICore context-menu map handle identity is inconsistent.')
    assert(type(update) == 'table',
        'DwarfUICore map-tile update must be a table.')
    validate_fields(update, UPDATE_FIELDS, 'map-tile update')
    local position = identities.Position3D.new(update.pos)
    local definition = definitions.ContextMenuDefinitionSlot.new(
        update.definition)

    local key = pack_coordinate(position)
    if key ~= record.packed_coordinate then
        self:_remove_from_bucket(handle, record)
        record.packed_coordinate = key
        self:_get_or_create_bucket(key)[handle] = record
    end
    record.pos = position
    record.definition = definition
    return true
end

---Explicitly unregisters one live owned map handle.
---@param consumer_namespace string|any
---@param handle? any
---@param contract_major? integer
---@return boolean removed
function ContextMenuMapTargetRegistry:unregister(consumer_namespace, handle,
        contract_major)
    if identities.is_map_handle(consumer_namespace) then
        handle, consumer_namespace = consumer_namespace, DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    local handle_identity = validate_handle(handle, consumer_namespace,
        contract_major, self._runtime_generation)
    local record = self._registrations[handle]
    if not record then return false end
    assert(record.identity.local_identity == handle_identity.local_identity,
        'DwarfUICore context-menu map handle identity is inconsistent.')
    self:_remove_from_bucket(handle, record)
    self._registrations[handle] = nil
    return true
end

---Returns the number of live handle-and-owner registrations.
---@return integer
function ContextMenuMapTargetRegistry:registration_count()
    self:_prune()
    local count = 0
    for _ in pairs(self._registrations) do count = count + 1 end
    return count
end

---Returns whether one disposable handle remains registered.
---@param handle any
---@return boolean
function ContextMenuMapTargetRegistry:contains(handle)
    self:_prune()
    return self._registrations[handle] ~= nil
end

---Returns whether a handle still owns one exact composite identity.
---@param handle any
---@param expected_identity table
---@return boolean current
function ContextMenuMapTargetRegistry:contains_identity(handle, expected_identity)
    self:_prune()
    local record = self._registrations[handle]
    return record ~= nil and identities.CompositeIdentity.equals(
        record.identity, expected_identity)
end

---Returns a copied identity snapshot for one currently live handle.
---@param handle any
---@return table|nil identity
function ContextMenuMapTargetRegistry:get_identity(handle)
    self:_prune()
    local record = self._registrations[handle]
    if not record then return nil end
    return identities.CompositeIdentity.new(record.identity)
end

---Builds one eligible candidate without retaining it in registry state.
---@param handle any
---@param record table
---@param owner any
---@param root any
---@return dwarfuicore.ContextMenuMapCandidate
function ContextMenuMapTargetRegistry:_candidate(
        handle, record, owner, root)
    return setmetatable({
        identity=record.identity,
        sequence=record.sequence,
        source=handle,
        owner=owner,
        root=root,
        pos={
            x=record.pos.x,
            y=record.pos.y,
            z=record.pos.z,
        },
        _definition=record.definition,
    }, ContextMenuMapCandidate)
end

---Resolves one handle through current strict root eligibility.
---@param handle any
---@return dwarfuicore.ContextMenuMapCandidate|nil
function ContextMenuMapTargetRegistry:resolve(handle)
    self:_prune()
    local record = self._registrations[handle]
    if not record then return nil end
    local owner = record.owner_ref.owner
    if not owner then return nil end
    local root = self._root_resolver:resolve(owner, true)
    if not root then return nil end
    return self:_candidate(handle, record, owner, root)
end

---Resolves one composite registration identity through current eligibility.
---@param identity table
---@return dwarfuicore.ContextMenuMapCandidate|nil
function ContextMenuMapTargetRegistry:resolve_identity(identity)
    self:_prune()
    for handle, record in pairs(self._registrations) do
        if identities.CompositeIdentity.equals(record.identity, identity) then
            local owner = record.owner_ref.owner
            local root = owner and self._root_resolver:resolve(owner, true)
            if root then
                return self:_candidate(handle, record, owner, root)
            end
            return nil
        end
    end
    return nil
end

---Resolves an identity while requiring attachment to one already-presented root.
---This omits only the global presentation test, which an open ZScreen would
---otherwise make self-invalidating for Lua-screen roots.
---@param identity table
---@param expected_root any
---@return dwarfuicore.ContextMenuMapCandidate|nil
function ContextMenuMapTargetRegistry:resolve_identity_attached(
        identity, expected_root)
    self:_prune()
    for handle, record in pairs(self._registrations) do
        if identities.CompositeIdentity.equals(record.identity, identity) then
            local owner = record.owner_ref.owner
            local root = owner and
                self._root_resolver:find_root(owner, true)
            if root == expected_root then
                return self:_candidate(handle, record, owner, root)
            end
            return nil
        end
    end
    return nil
end

---Selects the latest originally registered eligible handle at one exact tile.
---@param position {x: integer, y: integer, z: integer}
---@return dwarfuicore.ContextMenuMapCandidate|nil
function ContextMenuMapTargetRegistry:detect(position)
    local copied = identities.Position3D.new(position)
    self:_prune()
    local bucket = self._coordinate_index[pack_coordinate(copied)]
    if not bucket then return nil end
    local winner
    for handle, record in pairs(bucket) do
        local owner = record.owner_ref.owner
        local root = owner and self._root_resolver:resolve(owner, true)
        if root and (not winner or record.sequence > winner.sequence) then
            winner = self:_candidate(handle, record, owner, root)
        end
    end
    return winner
end

---Returns all eligible contributions at one exact tile in registration order.
---@param position {x: integer, y: integer, z: integer}
---@return dwarfuicore.ContextMenuMapCandidate[] candidates
function ContextMenuMapTargetRegistry:detect_contributions(position)
    local copied = identities.Position3D.new(position)
    self:_prune()
    local bucket = self._coordinate_index[pack_coordinate(copied)]
    local candidates = {}
    if not bucket then return candidates end
    for handle, record in pairs(bucket) do
        local owner = record.owner_ref.owner
        local root = owner and self._root_resolver:resolve(owner, true)
        if root then
            table.insert(candidates, self:_candidate(handle, record, owner, root))
        end
    end
    table.sort(candidates, function(left, right)
        return left.sequence < right.sequence
    end)
    return candidates
end

---Removes every map registration in one namespace and contract major.
---@param consumer_namespace string
---@param contract_major? integer
---@return table[] removed
function ContextMenuMapTargetRegistry:clear_namespace(consumer_namespace,
        contract_major)
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    local removed = {}
    for handle, record in pairs(self._registrations) do
        if record.namespace == consumer_namespace and
                record.contract_major == contract_major then
            self:_remove_from_bucket(handle, record)
            self._registrations[handle] = nil
            table.insert(removed, record)
        end
    end
    return removed
end

---Returns attachment roots without applying visibility or presentation rules.
---@return table<any, boolean>
function ContextMenuMapTargetRegistry:get_attachment_roots()
    self:_prune()
    local roots = setmetatable({}, {__mode='k'})
    for _, record in pairs(self._registrations) do
        local owner = record.owner_ref.owner
        local root = owner and self._find_attachment_root(owner, true)
        if root then roots[root] = true end
    end
    return roots
end

---Returns currently eligible owner roots for pointer blocker traversal.
---@return table<any, boolean>
function ContextMenuMapTargetRegistry:get_eligible_roots()
    self:_prune()
    local roots = setmetatable({}, {__mode='k'})
    for _, record in pairs(self._registrations) do
        local owner = record.owner_ref.owner
        local root = owner and self._root_resolver:resolve(owner, true)
        if root then roots[root] = true end
    end
    return roots
end

---Drops every registration for destructive development reload or shutdown.
---@return table[] removed
function ContextMenuMapTargetRegistry:clear()
    local removed = {}
    for _, record in pairs(self._registrations) do table.insert(removed, record) end
    self._registrations = setmetatable({}, {__mode='k'})
    self._coordinate_index = {}
    self._registration_sequence = 0
    return removed
end

---Returns registration, sequence, and coordinate-index diagnostics.
---@return table
function ContextMenuMapTargetRegistry:get_diagnostics()
    local registrations = self:registration_count()
    local coordinates = 0
    for _ in pairs(self._coordinate_index) do coordinates = coordinates + 1 end
    local contributions = {}
    for _, record in pairs(self._registrations) do
        local identity = record.identity
        table.insert(contributions, {identity=
            identities.CompositeIdentity.new(identity),
            contribution_sequence=record.sequence})
    end
    table.sort(contributions, function(left, right)
        return left.contribution_sequence < right.contribution_sequence
    end)
    return {
        registration_count=registrations,
        coordinate_count=coordinates,
        registration_sequence=self._registration_sequence,
        contributions=contributions,
    }
end
