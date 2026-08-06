local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, enum = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
local _, types = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/input_event/types.lua', {
        reqscript={['dwarfuicore/utils/immutable_enum']=enum}})
local _, deriver = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/input_event/event_deriver.lua', {
        reqscript={['dwarfuicore/input_event/types']=types}})

---Builds a complete immutable-shape input snapshot fixture.
---@param options? table
---@return table
local function snapshot(options)
    options = options or {}
    local map_position = options.map_position == false and nil or {x=10, y=20, z=3}
    local screen_position = options.screen_position == false and nil or {x=4, y=5}
    if options.map_position == false then map_position = nil end
    if options.screen_position == false then screen_position = nil end
    return {sequence=41, mouse_inputs=options.mouse_inputs or {{key='_MOUSE_L'},
        {key='_MOUSE_WHEEL_UP'}}, map_position=map_position,
        screen_position=screen_position}
end

describe('Input Event derivation', function()
    it('derives paired events from every qualifying mouse input collection',
            function()
        local input = snapshot()
        local result = deriver.InputEventDeriver.derive(input, true, true)
        assert.equals(types.InputEventType.RAW_CLICK, result.raw.type)
        assert.equals(types.InputEventType.MAP_CLICK, result.map.type)
        assert.is_equal(input.mouse_inputs, result.raw.mouse_inputs)
        assert.is_equal(input.mouse_inputs, result.map.mouse_inputs)
        assert.is_equal(input.map_position, result.raw.map_position)
        assert.is_equal(input.map_position, result.map.map_position)
        assert.equals(input.sequence, result.raw.sequence)
        assert.equals(input.sequence, result.map.sequence)
        assert.has_error(function() result.raw.sequence = 1 end,
            'DwarfUICore Input Events are immutable.')
    end)

    it('keeps raw eligibility independent from screen and semantic proof',
            function()
        local result = deriver.InputEventDeriver.derive(
            snapshot{screen_position=false}, true, false)
        assert.is_not_nil(result.raw)
        assert.is_nil(result.raw.screen_position)
        assert.is_nil(result.map)
    end)

    it('suppresses both channels for non-mouse, off-map, and unsupported input',
            function()
        for _, input in ipairs({snapshot{mouse_inputs={}},
                snapshot{map_position=false}}) do
            local result = deriver.InputEventDeriver.derive(input, true, true)
            assert.is_nil(result.raw)
            assert.is_nil(result.map)
        end
        local result = deriver.InputEventDeriver.derive(snapshot(), false, true)
        assert.is_nil(result.raw)
        assert.is_nil(result.map)
    end)
end)
