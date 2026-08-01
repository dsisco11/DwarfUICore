--@ module=true

---Weak-key registration storage with non-owning identity indexes.
---@class dwarfuicore.WeakRegistrationStore
---@field private _records table
---@field private _keys_by_identity table
WeakRegistrationStore = {}
WeakRegistrationStore.__index = WeakRegistrationStore

---Creates empty weak registration storage.
---@return dwarfuicore.WeakRegistrationStore store
function WeakRegistrationStore.new()
    return setmetatable({_records=setmetatable({}, {__mode='k'}),
        _keys_by_identity=setmetatable({}, {__mode='v'})}, WeakRegistrationStore)
end

---Stores a registration under its weak lifetime key and identity.
---@param key table
---@param identity integer
---@param record table
function WeakRegistrationStore:set(key, identity, record)
    assert(type(key) == 'table' and math.type(identity) == 'integer' and
            type(record) == 'table',
        'DwarfUICore weak registration arguments are invalid.')
    self._records[key] = {identity=identity, record=record}
    self._keys_by_identity[identity] = key
end

---Returns a registration by its lifetime key.
---@param key table
---@return table|nil record
function WeakRegistrationStore:get(key)
    local entry = self._records[key]
    return entry and entry.record or nil
end

---Returns a registration by identity without retaining its lifetime key.
---@param identity integer
---@return table|nil record
function WeakRegistrationStore:get_by_identity(identity)
    local key = self._keys_by_identity[identity]
    return key and self:get(key) or nil
end

---Removes and returns a registration by its lifetime key.
---@param key table
---@return table|nil record
function WeakRegistrationStore:remove(key)
    local entry = self._records[key]
    if not entry then return nil end
    self._records[key] = nil
    self._keys_by_identity[entry.identity] = nil
    return entry.record
end

---Counts currently reachable registrations.
---@return integer count
function WeakRegistrationStore:count()
    local count = 0
    for _ in pairs(self._records) do count = count + 1 end
    return count
end

---Weak physical-widget target and namespace-contribution storage.
---@class dwarfuicore.WidgetTargetStore
---@field private _targets table
---@field private _allocator dwarfuicore.IdentityAllocator
WidgetTargetStore = {}
WidgetTargetStore.__index = WidgetTargetStore

---Creates physical-widget target storage using a shared sequence allocator.
---@param allocator dwarfuicore.IdentityAllocator
---@return dwarfuicore.WidgetTargetStore store
function WidgetTargetStore.new(allocator)
    assert(type(allocator) == 'table' and
            type(allocator.allocate_sequence) == 'function',
        'DwarfUICore widget target store requires an allocator.')
    return setmetatable({_targets=setmetatable({}, {__mode='k'}),
        _allocator=allocator}, WidgetTargetStore)
end

---Adds or idempotently finds one namespace contribution.
---@param widget table
---@param namespace string
---@param record table
---@return integer target_sequence
---@return integer contribution_sequence
---@return boolean created
function WidgetTargetStore:register(widget, namespace, record)
    local target = self._targets[widget]
    if not target then
        target = {target_sequence=self._allocator:allocate_sequence(),
            contributions={}}
        self._targets[widget] = target
    end
    local contribution = target.contributions[namespace]
    if contribution then
        contribution.record = record
        return target.target_sequence, contribution.sequence, false
    end
    contribution = {sequence=self._allocator:allocate_sequence(), record=record}
    target.contributions[namespace] = contribution
    return target.target_sequence, contribution.sequence, true
end

---Removes one namespace contribution and its empty physical target.
---@param widget table
---@param namespace string
---@return boolean removed
function WidgetTargetStore:remove(widget, namespace)
    local target = self._targets[widget]
    if not target or not target.contributions[namespace] then return false end
    target.contributions[namespace] = nil
    if next(target.contributions) == nil then self._targets[widget] = nil end
    return true
end

---Returns physical and contribution sequences for one registration.
---@param widget table
---@param namespace string
---@return integer|nil target_sequence
---@return integer|nil contribution_sequence
function WidgetTargetStore:get_sequences(widget, namespace)
    local target = self._targets[widget]
    local contribution = target and target.contributions[namespace]
    if not contribution then return nil, nil end
    return target.target_sequence, contribution.sequence
end
