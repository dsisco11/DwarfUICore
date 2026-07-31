--@ module=true

-- Weak exact-coordinate map-tooltip registration and target detection.

local ViewRootResolver =
    reqscript('dwarfui/view_root_resolver').ViewRootResolver
local target_types = reqscript('dwarfui/tooltip/target')
local ObservationKind = target_types.TooltipPointerObservationKind

API_VERSION = 1
local REGISTRY_SLOT = 'tooltip_map_target_registry'
local COORDINATE_MIN = -0x8000
local COORDINATE_MAX = 0x7fff
local COORDINATE_MASK = 0xffff

dfhack.dwarfui = dfhack.dwarfui or {}

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

---Creates empty reload-safe process state.
---@return table
local function new_process_state()
    return {
        api_version=API_VERSION,
        registrations=weak_keys(),
        coordinate_index=weak_values(),
        registration_sequence=0,
        generation=0,
    }
end

local process_state = dfhack.dwarfui[REGISTRY_SLOT]
if type(process_state) ~= 'table' or
        process_state.api_version ~= API_VERSION then
    process_state = new_process_state()
    dfhack.dwarfui[REGISTRY_SLOT] = process_state
end
process_state.generation = process_state.generation + 1

---@class dwarfui.MapTileTargetObservation
---@field sequence integer
---@field kind dwarfui.TooltipPointerObservationKind
---@field pointer_x integer|nil
---@field pointer_y integer|nil
---@field map_x integer|nil
---@field map_y integer|nil
---@field map_z integer|nil
---@field target dwarfui.MapTileTooltipRegistration|nil
---@field identity dwarfui.MapTileTooltipRegistration|nil
---@field target_kind dwarfui.TooltipTargetKind|nil
---@field root gui.View|nil
---@field source_root gui.View|nil
---@field registration_sequence integer|nil
---@field tooltip string|nil

---@class dwarfui.TooltipMapTargetRegistryOptions
---@field state table
---@field root_resolver dwarfui.ViewRootResolver

---@class dwarfui.TooltipMapTargetRegistry
---@field _state table
---@field _root_resolver dwarfui.ViewRootResolver
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
        ('DwarfUI %s must be a table.'):format(label))
    local pos = options.pos
    local pos_type = type(pos)
    assert(pos_type == 'table' or pos_type == 'userdata',
        ('DwarfUI %s requires an exact map position.'):format(label))
    assert(is_signed_16(pos.x) and is_signed_16(pos.y) and is_signed_16(pos.z),
        ('DwarfUI %s position requires signed 16-bit integer x, y, and z.'):format(label))
    assert(options.tooltip == nil or type(options.tooltip) == 'string',
        ('DwarfUI %s tooltip must be a string or nil.'):format(label))
    return pos.x, pos.y, pos.z, options.tooltip
end

---Builds one presentation-neutral miss observation.
---@param sample dwarfui.PointerSample
---@return dwarfui.MapTileTargetObservation
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
---@param options dwarfui.TooltipMapTargetRegistryOptions
---@return dwarfui.TooltipMapTargetRegistry
function TooltipMapTargetRegistry.new(options)
    assert(type(options) == 'table',
        'DwarfUI map target registry requires options.')
    assert(type(options.state) == 'table',
        'DwarfUI map target registry requires process state.')
    assert(type(options.root_resolver) == 'table' and
            type(options.root_resolver.resolve) == 'function',
        'DwarfUI map target registry requires a root resolver.')
    return setmetatable({
        _state=options.state,
        _root_resolver=options.root_resolver,
    }, TooltipMapTargetRegistry)
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
---@param handle dwarfui.MapTileTooltipRegistration
---@param record table
function TooltipMapTargetRegistry:_remove_from_bucket(handle, record)
    local bucket = record.bucket
    bucket[handle] = nil
    if next(bucket) == nil then
        self._state.coordinate_index[record.coordinate_key] = nil
    end
end

---Registers one caller-owned exact map-tile tooltip handle.
---@param options dwarfui.MapTileTooltipRegistrationOptions
---@return dwarfui.MapTileTooltipRegistration
function TooltipMapTargetRegistry:register(options)
    assert(type(options) == 'table',
        'DwarfUI map-tile registration options must be a table.')
    assert(type(options.owner) == 'table',
        'DwarfUI map-tile registration requires an owner view.')
    local x, y, z, tooltip =
        copy_mutable_state(options, 'map-tile registration')
    local state = self._state
    state.registration_sequence = state.registration_sequence + 1
    local key = coordinate_key(x, y, z)
    local bucket = self:_get_or_create_bucket(key)
    local handle = setmetatable({}, {__metatable=false})
    local record = {
        owner=options.owner,
        x=x,
        y=y,
        z=z,
        tooltip=tooltip,
        sequence=state.registration_sequence,
        coordinate_key=key,
        bucket=bucket,
    }
    state.registrations[handle] = record
    bucket[handle] = record
    return handle
end

---Atomically replaces one handle's exact position and tooltip text.
---@param handle dwarfui.MapTileTooltipRegistration
---@param update dwarfui.MapTileTooltipUpdate
---@return boolean updated
function TooltipMapTargetRegistry:update(handle, update)
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
---@param handle dwarfui.MapTileTooltipRegistration
---@return boolean removed
function TooltipMapTargetRegistry:unregister(handle)
    local record = self._state.registrations[handle]
    if not record then return false end
    self:_remove_from_bucket(handle, record)
    self._state.registrations[handle] = nil
    return true
end

---Counts live weak registrations without retaining their handles.
---@return integer
function TooltipMapTargetRegistry:registration_count()
    local count = 0
    for _ in pairs(self._state.registrations) do count = count + 1 end
    return count
end

---Returns whether one opaque handle remains registered.
---@param handle dwarfui.MapTileTooltipRegistration
---@return boolean
function TooltipMapTargetRegistry:contains(handle)
    return self._state.registrations[handle] ~= nil
end

---Returns one handle's current tooltip value without exposing its record.
---@param handle dwarfui.MapTileTooltipRegistration
---@return string|nil
function TooltipMapTargetRegistry:get_tooltip(handle)
    local record = self._state.registrations[handle]
    return record and record.tooltip or nil
end

---Builds the current presented owner-root set for screen-space occlusion.
---@return table<gui.View, integer>
function TooltipMapTargetRegistry:get_owner_roots()
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
---@param sample dwarfui.PointerSample
---@return dwarfui.MapTileTargetObservation
function TooltipMapTargetRegistry:detect(sample)
    assert(type(sample) == 'table',
        'DwarfUI map target detector requires a pointer sample.')
    assert(type(sample.sequence) == 'number',
        'DwarfUI map target sample sequence must be a number.')
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
        identity=winner.handle,
        target_kind=target_types.TooltipTargetKind.MAP_TILE,
        root=winner.root,
        source_root=winner.root,
        registration_sequence=winner.record.sequence,
        tooltip=winner.record.tooltip,
    }
end

---Returns reload, registration, and exact-index diagnostics.
---@return table diagnostics
function TooltipMapTargetRegistry:get_diagnostics()
    local bucket_count = 0
    for _ in pairs(self._state.coordinate_index) do
        bucket_count = bucket_count + 1
    end
    return {
        api_version=self._state.api_version,
        generation=self._state.generation,
        registration_count=self:registration_count(),
        coordinate_bucket_count=bucket_count,
        registration_sequence=self._state.registration_sequence,
    }
end

registry = TooltipMapTargetRegistry.new{
    state=process_state,
    root_resolver=ViewRootResolver.new(),
}
