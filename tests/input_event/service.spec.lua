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
                ['dwarfuicore/input_event/types']=types}})
    local demands = {}
    local manager = {acquire_subscription_demand=function(_, screen, map, ui)
            local handle = {screen=screen, map=map, ui=ui}
            table.insert(demands, handle)
            return handle
        end,
        release_subscription_demand=function(_, handle)
            handle.released = true
            return true
        end}
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
end)
