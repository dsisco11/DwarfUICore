--@ module=true

-- Weak exact-coordinate map-tile context-menu registrations.

local definitions = reqscript('dwarfui/context_menu/definition')
local targets = reqscript('dwarfui/context_menu/target')
local numbers = reqscript('dwarfui/utils/numbers')
local TooltipRootResolver =
    reqscript('dwarfui/tooltip_root_resolver').TooltipRootResolver

local COORDINATE_MIN = -0x8000
local COORDINATE_MAX = 0x7fff
local COORDINATE_MASK = 0xffff

---@class dwarfui.ContextMenuMapRegistrationOptions
---@field owner any
---@field pos {x: integer, y: integer, z: integer}
---@field definition dwarfui.ContextMenuDefinition

---@class dwarfui.ContextMenuMapRegistrationUpdate
---@field pos {x: integer, y: integer, z: integer}
---@field definition dwarfui.ContextMenuDefinition

---@class dwarfui.ContextMenuMapCandidate
---@field identity integer
---@field sequence integer
---@field source any
---@field owner any
---@field root any
---@field pos {x: integer, y: integer, z: integer}
---@field _definition dwarfui.ContextMenuDefinitionSlot
ContextMenuMapCandidate = {}
ContextMenuMapCandidate.__index = ContextMenuMapCandidate

---@class dwarfui.ContextMenuMapTargetRegistryOptions
---@field identity_allocator? dwarfui.ContextMenuRegistrationIdentityAllocator
---@field root_resolver? dwarfui.TooltipRootResolver
---@field find_attachment_root? fun(owner: any, allow_owner_root: boolean): any|nil

---@class dwarfui.ContextMenuMapTargetRegistry
---@field _identity_allocator dwarfui.ContextMenuRegistrationIdentityAllocator
---@field _root_resolver dwarfui.TooltipRootResolver
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
            ('DwarfUI %s contains unsupported field %s.'):format(
                label, tostring(field)))
    end
end

---Copies and validates one exact map position.
---@param position any
---@param label string
---@return {x: integer, y: integer, z: integer}
local function copy_position(position, label)
    local position_type = type(position)
    assert(position_type == 'table' or position_type == 'userdata',
        ('DwarfUI %s requires an exact map position.'):format(label))
    assert(numbers.is_integer(position.x) and
            position.x >= COORDINATE_MIN and
            position.x <= COORDINATE_MAX and
            numbers.is_integer(position.y) and
            position.y >= COORDINATE_MIN and
            position.y <= COORDINATE_MAX and
            numbers.is_integer(position.z) and
            position.z >= COORDINATE_MIN and
            position.z <= COORDINATE_MAX,
        ('DwarfUI %s requires signed 16-bit integer x, y, and z.'):format(
            label))
    return {x=position.x, y=position.y, z=position.z}
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

---Returns an isolated opening definition for this candidate.
---@return dwarfui.ContextMenuDefinitionSnapshot
function ContextMenuMapCandidate:get_definition_snapshot()
    return self._definition:snapshot()
end

---Creates a weak exact-coordinate registry.
---@param options? dwarfui.ContextMenuMapTargetRegistryOptions
---@return dwarfui.ContextMenuMapTargetRegistry
function ContextMenuMapTargetRegistry.new(options)
    options = options or {}
    assert(type(options) == 'table',
        'DwarfUI map-target registry options must be a table.')
    assert(options.identity_allocator == nil or
            type(options.identity_allocator.allocate) == 'function',
        'DwarfUI map-target identity allocator must allocate identities.')
    assert(options.root_resolver == nil or
            type(options.root_resolver.resolve) == 'function',
        'DwarfUI map-target root resolver must resolve owners.')
    assert(options.find_attachment_root == nil or
            type(options.find_attachment_root) == 'function',
        'DwarfUI map-target attachment resolver must be a function.')
    return setmetatable({
        _identity_allocator=options.identity_allocator or
            targets.ContextMenuRegistrationIdentityAllocator.new(),
        _root_resolver=options.root_resolver or TooltipRootResolver.new(),
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

---Registers one weak-owner exact map tile and returns its disposable handle.
---@param options dwarfui.ContextMenuMapRegistrationOptions
---@return any handle
function ContextMenuMapTargetRegistry:register(options)
    assert(type(options) == 'table',
        'DwarfUI map-tile registration options must be a table.')
    validate_fields(options, REGISTRATION_FIELDS, 'map-tile registration')
    assert(type(options.owner) == 'table',
        'DwarfUI map-tile registration requires an owner.')
    local position = copy_position(options.pos, 'map-tile registration')
    local definition = definitions.ContextMenuDefinitionSlot.new(
        options.definition)

    self._registration_sequence = self._registration_sequence + 1
    local key = pack_coordinate(position)
    local handle = setmetatable({}, {__metatable=false})
    local record = {
        identity=self._identity_allocator:allocate(),
        sequence=self._registration_sequence,
        owner_ref=weak_owner(options.owner),
        pos=position,
        packed_coordinate=key,
        definition=definition,
    }
    self._registrations[handle] = record
    self:_get_or_create_bucket(key)[handle] = record
    return handle
end

---Atomically replaces one handle's copied position and definition.
---@param handle any
---@param update dwarfui.ContextMenuMapRegistrationUpdate
---@return boolean updated
function ContextMenuMapTargetRegistry:update(handle, update)
    local record = self._registrations[handle]
    if not record or record.owner_ref.owner == nil then
        if record then
            self:_remove_from_bucket(handle, record)
            self._registrations[handle] = nil
        end
        return false
    end
    assert(type(update) == 'table',
        'DwarfUI map-tile update must be a table.')
    validate_fields(update, UPDATE_FIELDS, 'map-tile update')
    local position = copy_position(update.pos, 'map-tile update')
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

---Explicitly unregisters one live map handle.
---@param handle any
---@return boolean removed
function ContextMenuMapTargetRegistry:unregister(handle)
    local record = self._registrations[handle]
    if not record then return false end
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

---Builds one eligible candidate without retaining it in registry state.
---@param record table
---@param owner any
---@param root any
---@return dwarfui.ContextMenuMapCandidate
function ContextMenuMapTargetRegistry:_candidate(record, owner, root)
    return setmetatable({
        identity=record.identity,
        sequence=record.sequence,
        source=owner,
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
---@return dwarfui.ContextMenuMapCandidate|nil
function ContextMenuMapTargetRegistry:resolve(handle)
    self:_prune()
    local record = self._registrations[handle]
    if not record then return nil end
    local owner = record.owner_ref.owner
    if not owner then return nil end
    local root = self._root_resolver:resolve(owner, true)
    if not root then return nil end
    return self:_candidate(record, owner, root)
end

---Resolves one numeric registration identity through current eligibility.
---@param identity integer
---@return dwarfui.ContextMenuMapCandidate|nil
function ContextMenuMapTargetRegistry:resolve_identity(identity)
    self:_prune()
    for _, record in pairs(self._registrations) do
        if record.identity == identity then
            local owner = record.owner_ref.owner
            local root = owner and self._root_resolver:resolve(owner, true)
            if root then return self:_candidate(record, owner, root) end
            return nil
        end
    end
    return nil
end

---Selects the latest originally registered eligible handle at one exact tile.
---@param position {x: integer, y: integer, z: integer}
---@return dwarfui.ContextMenuMapCandidate|nil
function ContextMenuMapTargetRegistry:detect(position)
    local copied = copy_position(position, 'map-tile target sample')
    self:_prune()
    local bucket = self._coordinate_index[pack_coordinate(copied)]
    if not bucket then return nil end
    local winner
    for _, record in pairs(bucket) do
        local owner = record.owner_ref.owner
        local root = owner and self._root_resolver:resolve(owner, true)
        if root and (not winner or record.sequence > winner.sequence) then
            winner = self:_candidate(record, owner, root)
        end
    end
    return winner
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

---Drops every registration for destructive development reload or shutdown.
---@return boolean changed
function ContextMenuMapTargetRegistry:clear()
    local changed = next(self._registrations) ~= nil
    self._registrations = setmetatable({}, {__mode='k'})
    self._coordinate_index = {}
    return changed
end

---Returns registration, sequence, and coordinate-index diagnostics.
---@return table
function ContextMenuMapTargetRegistry:get_diagnostics()
    local registrations = self:registration_count()
    local coordinates = 0
    for _ in pairs(self._coordinate_index) do coordinates = coordinates + 1 end
    return {
        registration_count=registrations,
        coordinate_count=coordinates,
        registration_sequence=self._registration_sequence,
    }
end
