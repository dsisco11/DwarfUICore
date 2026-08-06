local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads an isolated Input Event subscription-service harness.
---@return table context
local function load_context()
    local dfhack = {dwarfuicore={}}
    local _, enum = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local _, contracts = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
            reqscript={['dwarfuicore/utils/immutable_enum']=enum}})
    local _, namespaces = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')
    local _, proxy = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')
    local _, identity = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/identity.lua', {
            globals={dfhack=dfhack}, reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/namespace']=namespaces,
                ['dwarfuicore/service_provider/immutable_proxy']=proxy}})
    local _, types = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/input_event/types.lua', {
            reqscript={['dwarfuicore/utils/immutable_enum']=enum}})
    local _, service_module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/input_event/service.lua', {
            globals={dfhack=dfhack}, reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/identity']=identity,
                ['dwarfuicore/input_event/types']=types,
                ['dwarfuicore/input_event/event_deriver']={
                    InputEventDeriver={derive=function() return {} end}},
                ['dwarfuicore/input_event/ui_obstruction_resolver']={
                    InputEventUiObstructionResolver={is_unobstructed=function()
                        return false
                    end}},
                ['dwarfuicore/input_event/ui_root_collector']={
                    InputEventUiRootCollector={collect=function() return {} end}}}})
    local demands = {}
    local manager = {acquire_subscription_demand=function(_, screen, map, ui)
            local handle = {screen=screen, map=map, ui=ui}
            table.insert(demands, handle)
            return handle
        end,
        release_subscription_demand=function(_, handle)
            handle.released = true
            return true
        end,
        set_public_deriver=function(self, callback)
            self.deriver = callback
        end,
        get_additional_ui_roots=function() return {} end}
    return {contracts=contracts, demands=demands, manager=manager,
        service=service_module.InputEventService.new(1, manager), types=types}
end

describe('Input Event subscription service', function()
    it('retains independent subscriptions and contributes exact demand', function()
        local context = load_context()
        local raw = context.service:subscribe('alpha', 1,
            context.types.InputEventType.RAW_CLICK, 'observe', function() end)
        local map = context.service:subscribe('alpha', 1,
            context.types.InputEventType.MAP_CLICK, 'intercept', function() end)
        assert.is_true(context.service:is_subscribed('alpha', 1, raw))
        assert.is_true(context.service:is_subscribed('alpha', 1, map))
        assert.same({false, true, false}, {context.demands[1].screen,
            context.demands[1].map, context.demands[1].ui})
        assert.same({true, true, true}, {context.demands[2].screen,
            context.demands[2].map, context.demands[2].ui})
        assert.is_true(context.service:unsubscribe('alpha', 1, raw))
        assert.is_true(context.demands[1].released)
        assert.is_false(context.service:unsubscribe('alpha', 1, raw))
        assert.is_true(context.service:clear_namespace('alpha', 1))
        assert.is_true(context.demands[2].released)
    end)

    it('rejects malformed event registrations before mutation', function()
        local context = load_context()
        assert.has_error(function()
            context.service:subscribe('alpha', 1, 'RAW_CLICK', 'observe',
                function() end)
        end, 'DwarfUICore Input Event type is invalid.')
        assert.has_error(function()
            context.service:subscribe('alpha', 1,
                context.types.InputEventType.RAW_CLICK, 'observe', false)
        end, 'DwarfUICore Input Event callback must be a function.')
        assert.equals(0, #context.demands)
    end)

    it('dispatches globally ordered interceptors before retained observers', function()
        local context = load_context()
        local calls = {}
        context.service:subscribe('alpha', 1, context.types.InputEventType.RAW_CLICK,
            'intercept', function(event)
                table.insert(calls, 'first:' .. event.sequence)
                return context.types.InputEventDisposition.PASS
            end)
        context.service:subscribe('alpha', 1, context.types.InputEventType.MAP_CLICK,
            'observe', function(event) table.insert(calls, 'observer:' .. event.sequence) end)
        local dispatch = context.service:begin_dispatch({raw={sequence=7}, map={sequence=7}})
        assert.is_false(dispatch.consumed)
        assert.same({'first:7'}, calls)
        context.service:complete_dispatch(dispatch)
        assert.same({'first:7', 'observer:7'}, calls)
    end)

    it('consumes once, skips removed candidates, and isolates callback failures', function()
        local context = load_context()
        local calls = {}
        local observed
        local removed
        context.service:subscribe('alpha', 1, context.types.InputEventType.RAW_CLICK,
            'intercept', function()
                context.service:unsubscribe('alpha', 1, removed)
                error('failure')
            end)
        removed = context.service:subscribe('alpha', 1,
            context.types.InputEventType.RAW_CLICK, 'intercept', function()
                table.insert(calls, 'removed')
                return context.types.InputEventDisposition.PASS
            end)
        context.service:subscribe('alpha', 1, context.types.InputEventType.RAW_CLICK,
            'intercept', function()
                table.insert(calls, 'consume')
                return context.types.InputEventDisposition.CONSUME
            end)
        context.service:subscribe('alpha', 1, context.types.InputEventType.RAW_CLICK,
            'observe', function(event) observed = event end)
        local dispatch = context.service:begin_dispatch({raw={sequence=8}, map=nil})
        assert.is_true(dispatch.consumed)
        assert.same({'consume'}, calls)
        context.service:complete_dispatch(dispatch)
        assert.equals(8, observed.sequence)
        assert.equals(1, #context.service._failures)
    end)

    it('uses independent snapshots for mutation and recursive dispatch', function()
        local context = load_context()
        local calls, nested = {}, false
        context.service:subscribe('alpha', 1, context.types.InputEventType.RAW_CLICK,
            'intercept', function()
                table.insert(calls, 'raw')
                if not nested then
                    nested = true
                    context.service:subscribe('alpha', 1,
                        context.types.InputEventType.RAW_CLICK, 'intercept',
                        function() table.insert(calls, 'late')
                            return context.types.InputEventDisposition.PASS
                        end)
                    context.service:begin_dispatch({raw={sequence=10}, map={sequence=10}})
                end
                return context.types.InputEventDisposition.PASS
            end)
        context.service:subscribe('alpha', 1, context.types.InputEventType.MAP_CLICK,
            'intercept', function()
                table.insert(calls, 'map')
                return context.types.InputEventDisposition.PASS
            end)
        context.service:begin_dispatch({raw={sequence=9}, map={sequence=9}})
        assert.same({'raw', 'raw', 'map', 'late', 'map'}, calls)
    end)

    it('fails open for invalid interceptor returns and isolates observers', function()
        local context = load_context()
        local calls, first_event, second_event = {}, nil, nil
        context.service:subscribe('alpha', 1, context.types.InputEventType.RAW_CLICK,
            'intercept', function() return true end)
        context.service:subscribe('alpha', 1, context.types.InputEventType.RAW_CLICK,
            'intercept', function()
                table.insert(calls, 'pass')
                return context.types.InputEventDisposition.PASS
            end)
        context.service:subscribe('alpha', 1, context.types.InputEventType.RAW_CLICK,
            'observe', function() return context.types.InputEventDisposition.CONSUME end)
        context.service:subscribe('alpha', 1, context.types.InputEventType.RAW_CLICK,
            'observe', function(event) first_event = event end)
        context.service:subscribe('alpha', 1, context.types.InputEventType.MAP_CLICK,
            'observe', function() error('observer failure') end)
        context.service:subscribe('alpha', 1, context.types.InputEventType.RAW_CLICK,
            'observe', function(event)
                second_event = event
                table.insert(calls, 'observer')
            end)
        local dispatch = context.service:begin_dispatch({raw={sequence=11}, map={sequence=11}})
        assert.is_false(dispatch.consumed)
        context.service:complete_dispatch(dispatch)
        assert.same({'pass', 'observer'}, calls)
        assert.is_equal(first_event, second_event)
        assert.equals(2, #context.service._failures)
    end)
end)
