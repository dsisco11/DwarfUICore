local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local TYPES_PATH =
    'src/scripts_modinstalled/dwarfuicore/input_event/types.lua'
local FACTORY_PATH =
    'src/scripts_modinstalled/dwarfuicore/input_event/snapshot_factory.lua'

---Loads one isolated Input Event snapshot factory harness.
---@return table
local function load_harness()
    local _, immutable_enum = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local _, contracts = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
            reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
        })
    local _, namespaces = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')
    local _, immutable_proxy = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')
    local dfhack = {dwarfuicore={}}
    local _, identities = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/identity.lua', {
            globals={dfhack=dfhack},
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/namespace']=namespaces,
                ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
            },
        })
    local _, types = module_loader.load(repo_root, TYPES_PATH, {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })
    local _, module = module_loader.load(repo_root, FACTORY_PATH, {
        globals={dfhack=dfhack},
        reqscript={
            ['dwarfuicore/service_provider/identity']=identities,
            ['dwarfuicore/input_event/types']=types,
        },
    })
    return {module=module, types=types}
end

describe('DwarfUICore Input Event snapshot factory', function()
    it('defines immutable numeric closed discriminator sets', function()
        local harness = load_harness()
        assert.same({MAP_CLICK=1, RAW_CLICK=2},
            harness.types.InputEventType)
        assert.same({PASS=1, CONSUME=2},
            harness.types.InputEventDisposition)
        assert.same({PASS=1, CONSUME=2},
            harness.types.InputDispatchResult)
        assert.has_error(function()
            harness.types.InputSampleDemandType.EXTRA = 4
        end, 'DwarfUICore Input Event sample demand type is immutable.')
    end)

    it('copies one immutable input snapshot with sorted mouse inputs', function()
        local harness = load_harness()
        local screen_reads, map_reads = 0, 0
        local map_position = {x=10, y=20, z=3}
        local factory = harness.module.SnapshotFactory.new{
            sample_screen_position=function()
                screen_reads = screen_reads + 1
                return 4, 5
            end,
            sample_map_position=function()
                map_reads = map_reads + 1
                return map_position
            end,
            is_mouse_input=function(key) return key:find('_MOUSE', 1, true) ~= nil end,
        }
        local tracker = harness.module.InputDemandTracker.new()
        tracker:acquire(harness.types.InputSampleDemandType.SCREEN_POSITION)
        tracker:acquire(harness.types.InputSampleDemandType.MAP_POSITION)

        local snapshot = factory:capture_input({
            _MOUSE_R=true,
            A=true,
            _MOUSE_L_DOWN=true,
        }, tracker:get_snapshot())
        map_position.x = 99

        assert.equals(1, screen_reads)
        assert.equals(1, map_reads)
        assert.equals(1, snapshot.sequence)
        assert.same({'_MOUSE_L_DOWN', '_MOUSE_R'}, {
            snapshot.mouse_inputs[1].key,
            snapshot.mouse_inputs[2].key,
        })
        assert.equals(2, #snapshot.mouse_inputs)
        assert.same({x=4, y=5}, snapshot.screen_position)
        assert.same({x=10, y=20, z=3}, snapshot.map_position)
        assert.has_error(function() snapshot.sequence = 2 end)
        assert.has_error(function() snapshot.mouse_inputs[1].key = 'A' end)
        assert.has_error(function() snapshot.screen_position.x = 9 end)
        assert.has_error(function() snapshot.map_position.x = 9 end)
    end)

    it('keeps screen, map, and UI-resolution demand independently countable',
            function()
        local harness = load_harness()
        local screen_reads, map_reads = 0, 0
        local factory = harness.module.SnapshotFactory.new{
            sample_screen_position=function()
                screen_reads = screen_reads + 1
                return 1, 2
            end,
            sample_map_position=function()
                map_reads = map_reads + 1
                return {x=3, y=4, z=5}
            end,
            is_mouse_input=function() return false end,
        }
        local tracker = harness.module.InputDemandTracker.new()
        local roots = tracker:acquire(
            harness.types.InputSampleDemandType.UI_ROOT_RESOLUTION)
        local none = factory:capture_pointer(tracker:get_snapshot())
        assert.is_nil(none.screen_position)
        assert.is_nil(none.map_position)
        assert.equals(0, screen_reads)
        assert.equals(0, map_reads)

        local screen = tracker:acquire(
            harness.types.InputSampleDemandType.SCREEN_POSITION)
        local map = tracker:acquire(
            harness.types.InputSampleDemandType.MAP_POSITION)
        local sampled = factory:capture_pointer(tracker:get_snapshot())
        assert.same({x=1, y=2}, sampled.screen_position)
        assert.same({x=3, y=4, z=5}, sampled.map_position)
        assert.equals(1, screen_reads)
        assert.equals(1, map_reads)
        assert.equals(1, tracker:get_count(
            harness.types.InputSampleDemandType.UI_ROOT_RESOLUTION))
        assert.is_true(tracker:release(screen))
        assert.is_true(tracker:release(map))
        assert.is_true(tracker:release(roots))
        assert.is_false(tracker:release(roots))
    end)

    it('retains active demand until its handle is explicitly released',
            function()
        local harness = load_harness()
        local tracker = harness.module.InputDemandTracker.new()
        local handle = tracker:acquire(
            harness.types.InputSampleDemandType.MAP_POSITION)
        handle = nil
        collectgarbage('collect')

        assert.equals(1, tracker:get_count(
            harness.types.InputSampleDemandType.MAP_POSITION))
        assert.is_true(tracker:get_snapshot().map_position)
    end)

    it('shares one process sequence across input and pointer captures', function()
        local harness = load_harness()
        local factory = harness.module.SnapshotFactory.new{
            is_mouse_input=function() return false end,
        }
        local second_factory = harness.module.SnapshotFactory.new{
            is_mouse_input=function() return false end,
        }
        local demand = harness.module.InputDemandTracker.new():get_snapshot()

        assert.equals(1, factory:capture_pointer(demand).sequence)
        assert.equals(2, second_factory:capture_input({}, demand).sequence)
    end)

    it('preserves an immutable empty collection for non-mouse input', function()
        local harness = load_harness()
        local factory = harness.module.SnapshotFactory.new{
            is_mouse_input=function() return false end,
        }
        local snapshot = factory:capture_input({CUSTOM_SHIFT_A=true},
            harness.module.InputDemandTracker.new():get_snapshot())

        assert.equals(0, #snapshot.mouse_inputs)
        assert.is_nil(snapshot.mouse_inputs[1])
        assert.has_error(function() snapshot.mouse_inputs[1] = {} end)
    end)

    it('normalizes malformed sampled positions without leaking axis fields',
            function()
        local harness = load_harness()
        local factory = harness.module.SnapshotFactory.new{
            sample_screen_position=function() return 1.5, 2 end,
            sample_map_position=function() return {x=1, y='2', z=3} end,
            is_mouse_input=function() return false end,
        }
        local tracker = harness.module.InputDemandTracker.new()
        tracker:acquire(harness.types.InputSampleDemandType.SCREEN_POSITION)
        tracker:acquire(harness.types.InputSampleDemandType.MAP_POSITION)
        local sample = factory:capture_pointer(tracker:get_snapshot())

        assert.is_nil(sample.screen_position)
        assert.is_nil(sample.map_position)
        assert.is_nil(sample.screen_x)
        assert.is_nil(sample.screen_y)
        assert.is_nil(sample.map_x)
        assert.is_nil(sample.map_y)
        assert.is_nil(sample.map_z)
        assert.is_nil(sample.coordinate_space)
    end)

    it('normalizes nil sampled positions without skipping the snapshot',
            function()
        local harness = load_harness()
        local factory = harness.module.SnapshotFactory.new{
            sample_screen_position=function() return nil, nil end,
            sample_map_position=function() return nil end,
            is_mouse_input=function() return false end,
        }
        local tracker = harness.module.InputDemandTracker.new()
        tracker:acquire(harness.types.InputSampleDemandType.SCREEN_POSITION)
        tracker:acquire(harness.types.InputSampleDemandType.MAP_POSITION)
        local sample = factory:capture_pointer(tracker:get_snapshot())

        assert.equals(1, sample.sequence)
        assert.is_nil(sample.screen_position)
        assert.is_nil(sample.map_position)
    end)
end)
