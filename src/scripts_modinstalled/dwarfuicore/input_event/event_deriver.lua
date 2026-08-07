--@ module=true

-- Pure immutable event derivation from pre-arbitration input facts.

local types = reqscript('dwarfuicore/input_event/types')

---@class dwarfuicore.RawClickEvent
---@field type dwarfuicore.InputEventType
---@field sequence integer
---@field mouse_inputs dwarfuicore.MouseInput[]
---@field map_position dwarfuicore.Position3D
---@field screen_position dwarfuicore.Position2D|nil

---@class dwarfuicore.MapClickedEvent
---@field type dwarfuicore.InputEventType
---@field sequence integer
---@field mouse_inputs dwarfuicore.MouseInput[]
---@field map_position dwarfuicore.Position3D
---@field screen_position dwarfuicore.Position2D

---@alias dwarfuicore.InputEvent dwarfuicore.RawClickEvent|dwarfuicore.MapClickedEvent

---@class dwarfuicore.InputEventDerivation
---@field raw dwarfuicore.RawClickEvent|nil
---@field map dwarfuicore.MapClickedEvent|nil

---Returns one immutable event over already immutable snapshot facts.
---@param values table
---@return table
local function immutable_event(values)
    return setmetatable({}, {__index=values, __newindex=function()
        error('DwarfUICore Input Events are immutable.', 2)
    end, __pairs=function() return next, values, nil end, __metatable=false})
end

---@class dwarfuicore.InputEventDeriver
InputEventDeriver = {}

---Derives coordinate-qualified raw and proven-unobstructed semantic events.
---@param snapshot dwarfuicore.InputSnapshot
---@param hook_supported boolean
---@param ui_unobstructed boolean
---@return dwarfuicore.InputEventDerivation
function InputEventDeriver.derive(snapshot, hook_supported, ui_unobstructed)
    assert(type(snapshot) == 'table' and type(snapshot.sequence) == 'number',
        'DwarfUICore Input Event derivation requires an input snapshot.')
    assert(type(hook_supported) == 'boolean' and type(ui_unobstructed) == 'boolean',
        'DwarfUICore Input Event eligibility must be boolean.')
    if not hook_supported or #snapshot.mouse_inputs == 0 or
            snapshot.map_position == nil then
        return {raw=nil, map=nil}
    end
    local raw = immutable_event({type=types.InputEventType.RAW_CLICK,
        sequence=snapshot.sequence, mouse_inputs=snapshot.mouse_inputs,
        map_position=snapshot.map_position, screen_position=snapshot.screen_position})
    local map = nil
    if ui_unobstructed and snapshot.screen_position ~= nil then
        map = immutable_event({type=types.InputEventType.MAP_CLICK,
            sequence=snapshot.sequence, mouse_inputs=snapshot.mouse_inputs,
            map_position=snapshot.map_position, screen_position=snapshot.screen_position})
    end
    return {raw=raw, map=map}
end
