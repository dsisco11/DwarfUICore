local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local POLLER_PATH =
    'src/scripts_modinstalled/dwarfuicore/pointer_poller.lua'

---Creates a controlled scheduler and an isolated poller module generation.
---@param state table|nil
---@return table harness
local function load_harness(state)
    state = state or {}
    state.callbacks = state.callbacks or {}
    state.dwarfuicore = state.dwarfuicore or {}
    state.mouse_reads = state.mouse_reads or 0
    state.map_reads = state.map_reads or 0
    state.notifications = state.notifications or {}
    if state.demand == nil then state.demand = true end
    if state.map_demand == nil then state.map_demand = false end
    local dfhack = state.dfhack or {
        dwarfuicore=state.dwarfuicore,
        gui={
            getMousePos=function()
                state.map_reads = state.map_reads + 1
                return state.map_pos
            end,
        },
        screen={
            getMousePos=function()
                state.mouse_reads = state.mouse_reads + 1
                return state.mouse_x, state.mouse_y
            end,
        },
        timeout=function(delay, mode, callback)
            state.default_schedule = {delay=delay, mode=mode}
            table.insert(state.callbacks, callback)
        end,
    }
    state.dfhack = dfhack

    local _, module = module_loader.load(repo_root, POLLER_PATH, {
        globals={dfhack=dfhack},
    })

    ---Queues one controlled callback without executing it synchronously.
    ---@param callback function
    local function schedule(callback)
        state.schedule_count = (state.schedule_count or 0) + 1
        table.insert(state.callbacks, callback)
    end

    local options = {
        observer=function(sample)
            table.insert(state.notifications, sample)
            if state.observer_error then
                error(state.observer_error)
            end
            if state.lose_demand_in_observer then
                state.demand = false
            end
        end,
        has_demand=function()
            state.demand_checks = (state.demand_checks or 0) + 1
            return state.demand
        end,
        has_map_demand=function()
            state.map_demand_checks = (state.map_demand_checks or 0) + 1
            return state.map_demand
        end,
    }
    if not state.use_defaults then
        options.scheduler = schedule
        options.sample_pointer = function()
            state.mouse_reads = state.mouse_reads + 1
            return state.mouse_x, state.mouse_y
        end
        options.sample_map_pointer = function()
            state.map_reads = state.map_reads + 1
            return state.map_pos
        end
    end

    ---Runs the oldest controlled callback.
    ---@return boolean
    ---@return any
    local function run_next()
        local callback = table.remove(state.callbacks, 1)
        assert.is_function(callback)
        return pcall(callback)
    end

    return {
        module=module,
        new_poller=function()
            return module.PointerPoller.new(options)
        end,
        run_next=run_next,
        state=state,
    }
end

describe('DwarfUICore pointer poller', function()
    it('publishes one immutable sample per controlled active tick', function()
        local harness = load_harness{mouse_x=12, mouse_y=7}
        local poller = harness.new_poller()

        assert.is_true(poller:start())
        assert.equals(1, #harness.state.callbacks)
        assert.is_true(harness.run_next())

        assert.equals(1, harness.state.mouse_reads)
        assert.equals(1, #harness.state.notifications)
        local sample = harness.state.notifications[1]
        assert.equals(1, sample.sequence)
        assert.equals(12, sample.x)
        assert.equals(7, sample.y)
        assert.is_nil(sample.map_x)
        assert.is_nil(sample.map_y)
        assert.is_nil(sample.map_z)
        assert.equals('screen-cells', sample.coordinate_space)
        assert.has_error(function() sample.x = 99 end,
            'DwarfUICore pointer samples are immutable.')
        assert.equals(1, #harness.state.callbacks)
    end)

    it('publishes one coherent copied screen and exact-map snapshot', function()
        local map_pos = {x=101, y=202, z=7}
        local harness = load_harness{
            mouse_x=12,
            mouse_y=7,
            map_demand=true,
            map_pos=map_pos,
        }
        local poller = harness.new_poller()

        assert.is_true(poller:start())
        assert.is_true(harness.run_next())

        assert.equals(1, harness.state.mouse_reads)
        assert.equals(1, harness.state.map_reads)
        assert.equals(1, #harness.state.notifications)
        local sample = harness.state.notifications[1]
        assert.equals(1, sample.sequence)
        assert.same({12, 7, 101, 202, 7}, {
            sample.x,
            sample.y,
            sample.map_x,
            sample.map_y,
            sample.map_z,
        })

        map_pos.x, map_pos.y, map_pos.z = 301, 302, 8
        assert.same({101, 202, 7}, {
            sample.map_x,
            sample.map_y,
            sample.map_z,
        })
        assert.has_error(function() sample.map_x = 999 end,
            'DwarfUICore pointer samples are immutable.')
    end)

    it('keeps valid screen coordinates when exact map position is missing',
            function()
        local harness = load_harness{
            mouse_x=4,
            mouse_y=8,
            map_demand=true,
            map_pos=nil,
        }
        local poller = harness.new_poller()
        poller:start()

        assert.is_true(harness.run_next())
        local missing = harness.state.notifications[1]
        assert.same({4, 8}, {missing.x, missing.y})
        assert.is_nil(missing.map_x)
        assert.is_nil(missing.map_y)
        assert.is_nil(missing.map_z)

        harness.state.map_pos = {x=10, y=20, z=3}
        assert.is_true(harness.run_next())
        local present = harness.state.notifications[2]
        assert.same({4, 8}, {present.x, present.y})
        assert.same({10, 20, 3}, {
            present.map_x,
            present.map_y,
            present.map_z,
        })

        harness.state.map_pos = {x=10, y=nil, z=3}
        assert.is_true(harness.run_next())
        local partial = harness.state.notifications[3]
        assert.same({4, 8}, {partial.x, partial.y})
        assert.is_nil(partial.map_x)
        assert.is_nil(partial.map_y)
        assert.is_nil(partial.map_z)
        assert.equals(3, harness.state.mouse_reads)
        assert.equals(3, harness.state.map_reads)
    end)

    it('samples map coordinates only while explicit map demand exists',
            function()
        local harness = load_harness{
            mouse_x=6,
            mouse_y=9,
            map_pos={x=16, y=19, z=4},
        }
        local poller = harness.new_poller()
        poller:start()

        assert.is_true(harness.run_next())
        assert.equals(1, harness.state.mouse_reads)
        assert.equals(0, harness.state.map_reads)
        assert.is_nil(harness.state.notifications[1].map_x)

        harness.state.map_demand = true
        assert.is_true(harness.run_next())
        assert.equals(2, harness.state.mouse_reads)
        assert.equals(1, harness.state.map_reads)
        assert.same({16, 19, 4}, {
            harness.state.notifications[2].map_x,
            harness.state.notifications[2].map_y,
            harness.state.notifications[2].map_z,
        })

        harness.state.map_demand = false
        assert.is_true(harness.run_next())
        assert.equals(3, harness.state.mouse_reads)
        assert.equals(1, harness.state.map_reads)
        assert.is_nil(harness.state.notifications[3].map_x)

        harness.state.demand = false
        assert.is_true(harness.run_next())
        assert.equals(3, harness.state.mouse_reads)
        assert.equals(1, harness.state.map_reads)
        assert.equals(3, #harness.state.notifications)
        assert.equals(0, #harness.state.callbacks)
    end)

    it('does not create a second callback chain on duplicate start', function()
        local harness = load_harness()
        local poller = harness.new_poller()

        assert.is_true(poller:start())
        assert.is_false(poller:start())
        assert.equals(1, harness.state.schedule_count)
        assert.equals(1, #harness.state.callbacks)

        assert.is_true(harness.run_next())
        assert.equals(2, harness.state.schedule_count)
        assert.equals(1, #harness.state.callbacks)
    end)

    it('normalizes partial and complete missing positions', function()
        local harness = load_harness{mouse_x=4, mouse_y=nil}
        local poller = harness.new_poller()
        poller:start()

        assert.is_true(harness.run_next())
        assert.is_nil(harness.state.notifications[1].x)
        assert.is_nil(harness.state.notifications[1].y)

        harness.state.mouse_x, harness.state.mouse_y = nil, 8
        assert.is_true(harness.run_next())
        assert.is_nil(harness.state.notifications[2].x)
        assert.is_nil(harness.state.notifications[2].y)

        harness.state.mouse_x, harness.state.mouse_y = nil, nil
        assert.is_true(harness.run_next())
        assert.is_nil(harness.state.notifications[3].x)
        assert.is_nil(harness.state.notifications[3].y)
        assert.equals(3, harness.state.mouse_reads)
    end)

    it('assigns monotonically increasing sequences across restart', function()
        local harness = load_harness{mouse_x=1, mouse_y=2}
        local poller = harness.new_poller()
        poller:start()
        harness.run_next()
        assert.is_true(poller:stop())

        assert.is_true(poller:start())
        assert.is_true(harness.run_next())
        assert.is_true(harness.run_next())

        assert.equals(1, harness.state.notifications[1].sequence)
        assert.equals(2, harness.state.notifications[2].sequence)
    end)

    it('makes stop idempotent and every old callback inert', function()
        local harness = load_harness{mouse_x=2, mouse_y=3}
        local poller = harness.new_poller()
        poller:start()

        assert.is_true(poller:stop())
        assert.is_false(poller:stop())
        assert.is_true(harness.run_next())
        assert.equals(0, harness.state.mouse_reads)
        assert.equals(0, #harness.state.notifications)
        assert.equals(0, #harness.state.callbacks)
    end)

    it('does not let a stale callback stop a restarted chain', function()
        local harness = load_harness{
            mouse_x=5,
            mouse_y=6,
            map_demand=true,
            map_pos={x=15, y=16, z=2},
        }
        local poller = harness.new_poller()
        poller:start()
        poller:stop()
        poller:start()
        assert.equals(2, #harness.state.callbacks)

        assert.is_true(harness.run_next())
        assert.equals(0, harness.state.mouse_reads)
        assert.equals(0, harness.state.map_reads)
        assert.equals(1, #harness.state.callbacks)

        assert.is_true(harness.run_next())
        assert.equals(1, harness.state.mouse_reads)
        assert.equals(1, harness.state.map_reads)
        assert.equals(1, #harness.state.notifications)
        assert.same({15, 16, 2}, {
            harness.state.notifications[1].map_x,
            harness.state.notifications[1].map_y,
            harness.state.notifications[1].map_z,
        })
        assert.equals(1, #harness.state.callbacks)
    end)

    it('checks demand before sampling and before rescheduling', function()
        local before_sample = load_harness{mouse_x=1, mouse_y=1}
        local first = before_sample.new_poller()
        first:start()
        before_sample.state.demand = false
        assert.is_true(before_sample.run_next())
        assert.equals(0, before_sample.state.mouse_reads)
        assert.equals(0, #before_sample.state.notifications)
        assert.equals(0, #before_sample.state.callbacks)

        local after_observer = load_harness{
            mouse_x=1,
            mouse_y=1,
            lose_demand_in_observer=true,
        }
        local second = after_observer.new_poller()
        second:start()
        assert.is_true(after_observer.run_next())
        assert.equals(1, after_observer.state.mouse_reads)
        assert.equals(1, #after_observer.state.notifications)
        assert.equals(0, #after_observer.state.callbacks)
    end)

    it('surfaces observer failure and permits a deliberate restart', function()
        local harness = load_harness{
            mouse_x=9,
            mouse_y=4,
            observer_error='controlled observer failure',
        }
        local poller = harness.new_poller()
        poller:start()

        local ok, failure = harness.run_next()
        assert.is_false(ok)
        assert.is_truthy(tostring(failure):find(
            'DwarfUICore pointer poller observer failed:', 1, true))
        assert.is_truthy(tostring(failure):find(
            'controlled observer failure', 1, true))
        assert.equals(0, #harness.state.callbacks)

        harness.state.observer_error = nil
        assert.is_true(poller:start())
        assert.is_true(harness.run_next())
        assert.equals(2, harness.state.notifications[2].sequence)
        assert.equals(1, #harness.state.callbacks)
    end)

    it('makes callbacks from an older runtime generation inert', function()
        local state = {
            mouse_x=3,
            mouse_y=8,
            map_demand=true,
            map_pos={x=13, y=18, z=2},
            dwarfuicore={
                service_provider_runtime={generation=1},
            },
        }
        local old_harness = load_harness(state)
        local old_poller = old_harness.new_poller()
        old_poller:start()

        state.dwarfuicore.service_provider_runtime = {generation=2}
        local new_harness = load_harness(state)
        local new_poller = new_harness.new_poller()
        assert.is_false(old_poller:start())
        assert.is_true(new_poller:start())
        assert.equals(2, #state.callbacks)

        assert.is_true(old_harness.run_next())
        assert.equals(0, state.mouse_reads)
        assert.equals(0, state.map_reads)
        assert.equals(1, #state.callbacks)

        assert.is_true(new_harness.run_next())
        assert.equals(1, state.mouse_reads)
        assert.equals(1, state.map_reads)
        assert.equals(1, #state.notifications)
        assert.same({13, 18, 2}, {
            state.notifications[1].map_x,
            state.notifications[1].map_y,
            state.notifications[1].map_z,
        })
    end)

    it('reports generation, scheduling, and sample lifecycle', function()
        local harness = load_harness{mouse_x=3, mouse_y=8}
        local poller = harness.new_poller()
        local initial = poller:get_diagnostics()
        assert.equals(0, initial.generation)
        assert.equals(0, initial.sample_sequence)
        assert.is_false(initial.running)
        assert.is_false(initial.scheduled)
        assert.is_true(initial.current)

        poller:start()
        local started = poller:get_diagnostics()
        assert.equals(1, started.generation)
        assert.is_true(started.running)
        assert.is_true(started.scheduled)

        harness.run_next()
        local sampled = poller:get_diagnostics()
        assert.equals(1, sampled.sample_sequence)
        assert.is_true(sampled.running)
        assert.is_true(sampled.scheduled)

        poller:stop()
        local stopped = poller:get_diagnostics()
        assert.equals(2, stopped.generation)
        assert.is_false(stopped.running)
        assert.is_false(stopped.scheduled)
    end)

    it('uses one production pointer read and one-frame scheduling', function()
        local harness = load_harness{
            use_defaults=true,
            mouse_x=14,
            mouse_y=10,
            map_demand=true,
            map_pos={x=24, y=20, z=6},
        }
        local poller = harness.new_poller()

        assert.is_true(poller:start())
        assert.same({delay=1, mode='frames'},
            harness.state.default_schedule)
        assert.is_true(harness.run_next())
        assert.equals(1, harness.state.mouse_reads)
        assert.equals(1, harness.state.map_reads)
        assert.equals(1, #harness.state.notifications)
        assert.same({14, 10, 24, 20, 6}, {
            harness.state.notifications[1].x,
            harness.state.notifications[1].y,
            harness.state.notifications[1].map_x,
            harness.state.notifications[1].map_y,
            harness.state.notifications[1].map_z,
        })
    end)

    it('loads without GUI, overlay, tooltip, or renderer modules', function()
        local dfhack = {
            dwarfuicore={},
            screen={getMousePos=function() return nil, nil end},
            timeout=function() end,
        }
        local _, module = module_loader.load(repo_root, POLLER_PATH, {
            globals={dfhack=dfhack},
            require_modules={},
            reqscript={},
        })

        assert.equals('table', type(module.PointerPoller))
        local poller = module.PointerPoller.new{
            observer=function() end,
            has_demand=function() return false end,
        }
        assert.is_false(poller:start())
    end)
end)
