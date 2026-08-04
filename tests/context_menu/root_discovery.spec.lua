local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local ROOT_DISCOVERY_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/root_discovery.lua'

---Loads one root-discovery generation over caller-owned process state.
---@param state? table
---@return table harness
local function load_harness(state)
    state = state or {}
    state.dwarfuicore = state.dwarfuicore or {}
    state.callbacks = state.callbacks or {}
    state.printed = state.printed or {}
    state.failures = state.failures or {}
    state.notifications = state.notifications or {}
    if state.demand == nil then state.demand = true end
    local dfhack = {
        dwarfuicore=state.dwarfuicore,
        timeout=function(_, _, callback)
            table.insert(state.callbacks, callback)
        end,
    }
    local _, module = module_loader.load(
        repo_root, ROOT_DISCOVERY_PATH, {
            globals={dfhack=dfhack},
        })

    ---Queues one controlled discovery callback.
    ---@param callback function
    local function scheduler(callback)
        if state.scheduler_error then error(state.scheduler_error) end
        table.insert(state.callbacks, callback)
    end

    ---Runs the oldest controlled callback.
    ---@return boolean
    ---@return any
    local function run_next()
        local callback = table.remove(state.callbacks, 1)
        assert.is_function(callback)
        return pcall(callback)
    end

    ---Creates one discovery instance over the controlled state.
    ---@return dwarfui.ContextMenuRootDiscovery
    local function create()
        return module.ContextMenuRootDiscovery.new{
            has_demand=function()
                if state.demand_error then error(state.demand_error) end
                return state.demand
            end,
            discover=function()
                state.discovery_count = (state.discovery_count or 0) + 1
                if state.discovery_error then
                    error(state.discovery_error)
                end
                return state.roots or {}
            end,
            on_roots_changed=function(roots)
                if state.observer_error then error(state.observer_error) end
                local copy = {}
                for root in pairs(roots) do copy[root] = true end
                table.insert(state.notifications, copy)
            end,
            on_idle=function()
                state.idle_count = (state.idle_count or 0) + 1
            end,
            on_failure=function(message)
                table.insert(state.failures, message)
            end,
            scheduler=scheduler,
            printer=function(message)
                table.insert(state.printed, message)
            end,
        }
    end

    return {
        create=create,
        module=module,
        run_next=run_next,
        state=state,
    }
end

describe('context-menu root discovery', function()
    it('runs one registration-gated chain and publishes only root changes',
            function()
        local first, second = {}, {}
        local harness = load_harness{roots={[first]=true}}
        local discovery = harness.create()

        assert.is_true(discovery:start())
        assert.is_false(discovery:start())
        assert.equals(1, #harness.state.callbacks)
        assert.is_true(harness.run_next())
        assert.equals(1, harness.state.discovery_count)
        assert.same({[first]=true}, harness.state.notifications[1])
        assert.equals(1, #harness.state.callbacks)

        assert.is_true(harness.run_next())
        assert.equals(2, harness.state.discovery_count)
        assert.equals(1, #harness.state.notifications)

        harness.state.roots = {[second]=true}
        assert.is_true(harness.run_next())
        assert.equals(2, #harness.state.notifications)
        assert.same({[second]=true}, harness.state.notifications[2])
        assert.equals(1, #harness.state.callbacks)
    end)

    it('stops and releases roots after final demand disappears', function()
        local root = {}
        local harness = load_harness{roots={[root]=true}}
        local discovery = harness.create()
        discovery:start()
        harness.run_next()

        harness.state.demand = false
        assert.is_true(harness.run_next())

        local diagnostics = discovery:get_diagnostics()
        assert.is_false(diagnostics.running)
        assert.is_false(diagnostics.scheduled)
        assert.equals(0, diagnostics.root_count)
        assert.equals(2, #harness.state.notifications)
        assert.same({}, harness.state.notifications[2])
        assert.equals(1, harness.state.idle_count)
        assert.equals(0, #harness.state.callbacks)
    end)

    it('contains every discovery collaborator failure for the generation',
            function()
        for _, field in ipairs{
            'demand_error',
            'discovery_error',
            'observer_error',
            'scheduler_error',
        } do
            local root = {}
            local state = {roots={[root]=true}}
            state[field] = field
            local harness = load_harness(state)
            local discovery = harness.create()
            if field == 'scheduler_error' or field == 'demand_error' then
                assert.is_false(discovery:start())
            else
                discovery:start()
                assert.is_true(harness.run_next())
            end
            local diagnostics = discovery:get_diagnostics()
            assert.is_true(diagnostics.failed)
            assert.is_false(diagnostics.running)
            assert.is_false(diagnostics.scheduled)
            assert.equals(1, #state.failures)
            assert.equals(1, #state.printed)
            assert.is_truthy(state.failures[1]:find(field, 1, true))
            assert.is_false(discovery:refresh())
            assert.equals(0, #state.callbacks)
        end
    end)

    it('contains invalid discovery results instead of escaping the frame',
            function()
        local harness = load_harness()
        local discovery = harness.module.ContextMenuRootDiscovery.new{
            has_demand=function() return true end,
            discover=function() return 'not a root set' end,
            scheduler=function(callback)
                table.insert(harness.state.callbacks, callback)
            end,
            on_failure=function(message)
                table.insert(harness.state.failures, message)
            end,
            printer=function(message)
                table.insert(harness.state.printed, message)
            end,
        }
        discovery:start()

        assert.is_true(harness.run_next())
        assert.is_true(discovery:get_diagnostics().failed)
        assert.is_truthy(harness.state.failures[1]:find(
            'must return a root set', 1, true))
    end)

    it('invalidates scheduled callbacks from an older runtime generation',
            function()
        local state = {}
        state.dwarfuicore = {
            service_provider_runtime={generation=1},
        }
        local first = load_harness(state)
        local stale = first.create()
        stale:start()
        assert.equals(1, #state.callbacks)

        state.dwarfuicore.service_provider_runtime = {generation=2}
        local second = load_harness(state)
        local current = second.create()
        assert.is_true(first.run_next())
        assert.equals(0, state.discovery_count or 0)
        assert.is_false(stale:get_diagnostics().current)
        assert.is_false(stale:get_diagnostics().running)

        assert.is_true(current:start())
        assert.is_true(second.run_next())
        assert.equals(1, state.discovery_count)
        assert.is_true(current:get_diagnostics().current)
    end)

    it('does not retain a discovered root after external ownership ends',
            function()
        local harness = load_harness()
        local root = {}
        harness.state.roots = {[root]=true}
        local discovery = harness.create()
        discovery:start()
        harness.run_next()
        local weak = setmetatable({root}, {__mode='v'})

        harness.state.roots = {}
        harness.state.notifications = {}
        root = nil
        collectgarbage('collect')
        collectgarbage('collect')

        assert.is_nil(weak[1])
        assert.equals(0, discovery:get_diagnostics().root_count)
    end)
end)
