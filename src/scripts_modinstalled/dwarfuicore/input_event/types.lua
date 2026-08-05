--@ module=true

-- Closed Input Event discriminator sets shared by private runtime foundations.

local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')

---@enum dwarfuicore.InputEventType
InputEventType = immutable_enum.define({
    MAP_CLICK=1,
    RAW_CLICK=2,
}, 'Input Event type')

---@enum dwarfuicore.InputEventDisposition
InputEventDisposition = immutable_enum.define({
    PASS=1,
    CONSUME=2,
}, 'Input Event disposition')

---@enum dwarfuicore.InputDispatchResult
InputDispatchResult = immutable_enum.define({
    PASS=1,
    CONSUME=2,
}, 'Input Event dispatch result')

---@enum dwarfuicore.InputSampleDemandType
InputSampleDemandType = immutable_enum.define({
    SCREEN_POSITION=1,
    MAP_POSITION=2,
    UI_ROOT_RESOLUTION=3,
}, 'Input Event sample demand type')
