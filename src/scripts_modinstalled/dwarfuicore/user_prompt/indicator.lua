--@ module=true

-- Cooperative ownership adapter for the native map-tile selection indicator.

local INACTIVE_VALUE = {x=-30000, y=-30000, z=-30000}

---@class dwarfuicore.NativeIndicatorPort
---@field read fun(): table
---@field write fun(value: table)

---@class dwarfuicore.NativeIndicatorAdapter
---@field private _port dwarfuicore.NativeIndicatorPort
---@field private _snapshot table|nil
---@field private _last_written table|nil
---@field private _prepared boolean
---@field private _acquired boolean
---@field private _owns boolean
---@field private _external_takeover boolean
NativeIndicatorAdapter = {}
NativeIndicatorAdapter.__index = NativeIndicatorAdapter

---Copies one coordinate into detached Lua storage.
---@param value table
---@return {x: integer, y: integer, z: integer}
local function copy_coord(value)
    assert(type(value) == 'table' or type(value) == 'userdata',
        'DwarfUICore native indicator coordinate is unavailable.')
    assert(math.type(value.x) == 'integer' and
        math.type(value.y) == 'integer' and
        math.type(value.z) == 'integer',
        'DwarfUICore native indicator coordinate is invalid.')
    return {x=value.x, y=value.y, z=value.z}
end

---Returns whether two coordinates contain identical values.
---@param left table
---@param right table
---@return boolean equal
local function coord_equals(left, right)
    return left.x == right.x and left.y == right.y and left.z == right.z
end

---Creates the production port over the native indicator field.
---@return dwarfuicore.NativeIndicatorPort port
function native_port()
    return {
        read=function()
            return df.global.game.main_interface.recenter_indicator_m
        end,
        write=function(value)
            local native = df.global.game.main_interface.recenter_indicator_m
            native.x, native.y, native.z = value.x, value.y, value.z
        end,
    }
end

---Creates an adapter over an injected or production native field port.
---@param port? dwarfuicore.NativeIndicatorPort
---@return dwarfuicore.NativeIndicatorAdapter adapter
function NativeIndicatorAdapter.new(port)
    port = port or native_port()
    assert(type(port) == 'table' and type(port.read) == 'function' and
        type(port.write) == 'function',
        'DwarfUICore native indicator port is invalid.')
    return setmetatable({
        _port=port,
        _snapshot=nil,
        _last_written=nil,
        _prepared=false,
        _acquired=false,
        _owns=false,
        _external_takeover=false,
    }, NativeIndicatorAdapter)
end

---Prepares the fallible detached snapshot without taking ownership.
function NativeIndicatorAdapter:prepare()
    assert(not self._prepared,
        'DwarfUICore native indicator adapter is already prepared.')
    self._snapshot = copy_coord(self._port.read())
    self._prepared = true
end

---Takes prompt ownership using only local assignments after preparation.
function NativeIndicatorAdapter:acquire()
    if not self._prepared then self:prepare() end
    assert(not self._acquired,
        'DwarfUICore native indicator adapter is already acquired.')
    self._acquired = true
    self._owns = true
end

---Commits an already prepared snapshot using only non-throwing assignments.
---@return boolean acquired
function NativeIndicatorAdapter:commit_prepared()
    if not self._prepared or self._acquired then return false end
    self._acquired = true
    self._owns = true
    return true
end

---Relinquishes ownership when the native field differs from the last write.
---@return boolean owns
function NativeIndicatorAdapter:_verify_ownership()
    if not self._owns then return false end
    if self._last_written and not coord_equals(
            copy_coord(self._port.read()), self._last_written) then
        self._owns = false
        self._external_takeover = true
    end
    return self._owns
end

---Writes the visual hover coordinate or inactive sentinel while still owned.
---@param map_position? table
---@return boolean written
function NativeIndicatorAdapter:update(map_position)
    if not self._acquired then self:acquire() end
    if not self:_verify_ownership() then return false end
    local desired = map_position and copy_coord(map_position) or
        copy_coord(INACTIVE_VALUE)
    if self._last_written and coord_equals(desired, self._last_written) then
        return false
    end
    self._port.write(desired)
    self._last_written = copy_coord(desired)
    return true
end

---Ends the adapter invocation and restores only still-owned native state.
---@return boolean restored
function NativeIndicatorAdapter:release()
    if not self._acquired then return false end
    local restore = self._last_written ~= nil and self:_verify_ownership()
    if restore then self._port.write(copy_coord(self._snapshot)) end
    self._owns = false
    return restore
end

---Returns detached ownership diagnostics without exposing mutable cache state.
---@return table diagnostics
function NativeIndicatorAdapter:get_diagnostics()
    return {
        prepared=self._prepared,
        acquired=self._acquired,
        owns=self._owns,
        external_takeover=self._external_takeover,
        snapshot=self._snapshot and copy_coord(self._snapshot) or nil,
        last_written=self._last_written and copy_coord(self._last_written) or nil,
    }
end

inactive_value = copy_coord(INACTIVE_VALUE)
