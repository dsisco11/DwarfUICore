local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, immutable_enum = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
local _, contracts = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })
local _, immutable_proxy = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')

---Creates one healthy private runtime seam and state controls.
---@return table runtime
---@return table state
local function runtime_stub()
    local state = {generation=7, status=contracts.RuntimeStatus.HEALTHY}
    local runtime = {
        validate=function()
            assert.is_true(state.valid ~= false)
            return state
        end,
        get_service=function(_, generation)
            assert.equals(state.generation, generation)
            assert.is_true(state.service_healthy ~= false)
            return {}
        end,
    }
    return runtime, state
end

---Loads the public API factory over controlled runtime and handle seams.
---@param runtime table
---@param identities table
---@return table api
local function load_api(runtime, identities)
    local _, api = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/api.lua', {
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/identity']=identities,
                ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
                ['dwarfuicore/service_provider/runtime']=runtime,
            },
        })
    return api
end

---Asserts one stable public API failure category.
---@param callback function
---@param service_name string
---@param category string
local function assert_category(callback, service_name, category)
    local ok, failure = pcall(callback)
    assert.is_false(ok)
    assert.equals(('DwarfUICore %sServiceApi: [%s] '):format(
        service_name, category), tostring(failure):sub(1,
        #('DwarfUICore %sServiceApi: [%s] '):format(service_name, category)))
end

describe('namespace-bound service API proxy', function()
    it('binds private metadata, exposes only approved methods, and delegates',
            function()
        local runtime, state = runtime_stub()
        local api = load_api(runtime, {get_map_handle_identity=function() end})
        local calls = {}
        local factory = api.new_factory(contracts.ServiceKind.TOOLTIP,
            'TooltipServiceApi', {'register', 'clear_namespace'})
        local object = factory:create({facade={
            register=function(namespace, major, widget)
                table.insert(calls, {namespace, major, widget})
                return true
            end,
            clear_namespace=function(namespace, major)
                table.insert(calls, {namespace, major})
                return false
            end,
        }, contract_major=1, namespace='consumer', generation=7,
            service_kind=contracts.ServiceKind.TOOLTIP})

        assert.equals(1, object:get_contract_version())
        assert.equals('consumer', object:get_namespace())
        assert.is_true(object:register('widget'))
        assert.is_false(object:clear_namespace())
        assert.same({{'consumer', 1, 'widget'}, {'consumer', 1}}, calls)
        assert.is_nil(rawget(object, 'facade'))
        assert.is_nil(object.get_diagnostics)
        assert.same({}, (function()
            local keys = {}
            for key in pairs(object) do table.insert(keys, key) end
            return keys
        end)())
        assert.has_error(function() object.other = true end,
            'DwarfUICore TooltipServiceApi is immutable.')
        assert.has_error(function() object.register = function() end end,
            'DwarfUICore TooltipServiceApi is immutable.')
        assert.has_error(function() setmetatable(object, {}) end)
    end)

    it('reports retired APIs and unhealthy service state before delegation',
            function()
        local runtime, state = runtime_stub()
        local calls = 0
        local api = load_api(runtime, {get_map_handle_identity=function() end})
        local factory = api.new_factory(contracts.ServiceKind.CONTEXT_MENU,
            'ContextMenuServiceApi', {'clear_namespace'})
        local object = factory:create({facade={clear_namespace=function()
            calls = calls + 1
            return true
        end}, contract_major=1, namespace='consumer', generation=7,
            service_kind=contracts.ServiceKind.CONTEXT_MENU})

        state.generation = 8
        assert_category(function() object:clear_namespace() end,
            'ContextMenu', 'STALE_API')
        state.generation = 7
        state.service_healthy = false
        assert_category(function() object:clear_namespace() end,
            'ContextMenu', 'SERVICE_UNHEALTHY')
        assert.equals(0, calls)
    end)

    it('checks handle shape, generation, and ownership before mutation',
            function()
        local runtime = runtime_stub()
        local identities = {get_map_handle_identity=function(handle)
            return handle.identity
        end}
        local api = load_api(runtime, identities)
        local calls = 0
        local factory = api.new_factory(contracts.ServiceKind.TOOLTIP,
            'TooltipServiceApi', {'update_map_tile', 'unregister_map_tile'})
        local object = factory:create({facade={
            update_map_tile=function() calls = calls + 1 return true end,
            unregister_map_tile=function() calls = calls + 1 return true end,
        }, contract_major=1, namespace='consumer', generation=7,
            service_kind=contracts.ServiceKind.TOOLTIP})
        local function handle(identity) return {identity=identity} end

        assert_category(function() object:update_map_tile({}, {}) end,
            'Tooltip', 'INVALID_ARGUMENT')
        assert_category(function() object:update_map_tile(handle({
            runtime_generation=6, service_kind=contracts.ServiceKind.TOOLTIP,
            contract_major=1, namespace='consumer'}), {}) end,
            'Tooltip', 'STALE_HANDLE')
        assert_category(function() object:unregister_map_tile(handle({
            runtime_generation=7,
            service_kind=contracts.ServiceKind.CONTEXT_MENU,
            contract_major=1, namespace='consumer'})) end,
            'Tooltip', 'FOREIGN_HANDLE')
        assert.is_true(object:update_map_tile(handle({runtime_generation=7,
            service_kind=contracts.ServiceKind.TOOLTIP, contract_major=1,
            namespace='consumer'}), {}))
        assert.equals(1, calls)
    end)

    it('maps delegate input failures to ordinary invalid-argument errors',
            function()
        local runtime = runtime_stub()
        local api = load_api(runtime, {get_map_handle_identity=function() end})
        local factory = api.new_factory(contracts.ServiceKind.TOOLTIP,
            'TooltipServiceApi', {'register'})
        local object = factory:create({facade={register=function()
            error('widget is malformed')
        end}, contract_major=1, namespace='consumer', generation=7,
            service_kind=contracts.ServiceKind.TOOLTIP})
        assert_category(function() object:register(false) end,
            'Tooltip', 'INVALID_ARGUMENT')
    end)

    it('uses the approved UserPrompt API prefix', function()
        local runtime, state = runtime_stub()
        local api = load_api(runtime, {
            get_map_handle_identity=function() end,
        })
        local factory = api.new_factory(
            contracts.ServiceKind.USER_PROMPT,
            'UserPromptServiceApi', {'clear_namespace'})
        local object = factory:create({
            facade={clear_namespace=function() return false end},
            contract_major=1,
            namespace='consumer',
            generation=7,
            service_kind=contracts.ServiceKind.USER_PROMPT,
        })
        state.generation = 8

        assert_category(function() object:clear_namespace() end,
            'UserPrompt', 'STALE_API')
    end)

    it('validates prompt handles in malformed, stale, foreign order',
            function()
        local runtime, state = runtime_stub()
        local identities = {get_prompt_handle_identity=function(handle)
            return handle.identity
        end}
        local api = load_api(runtime, identities)
        local calls = 0
        local factory = api.new_factory(contracts.ServiceKind.USER_PROMPT,
            'UserPromptServiceApi', {'cancel', 'is_active'})
        local object = factory:create({facade={
            cancel=function() calls = calls + 1 return true end,
            is_active=function() calls = calls + 1 return true end,
        }, contract_major=1, namespace='consumer', generation=7,
            service_kind=contracts.ServiceKind.USER_PROMPT})
        local function handle(identity) return {identity=identity} end

        state.generation = 8
        assert_category(function() object:cancel({}) end,
            'UserPrompt', 'STALE_API')
        state.generation = 7
        state.service_healthy = false
        assert_category(function() object:cancel({}) end,
            'UserPrompt', 'SERVICE_UNHEALTHY')
        state.service_healthy = true
        assert_category(function() object:cancel({}) end,
            'UserPrompt', 'INVALID_ARGUMENT')
        assert_category(function() object:is_active(handle({
            runtime_generation=6,
            service_kind=contracts.ServiceKind.USER_PROMPT,
            contract_major=1, namespace='consumer'})) end,
            'UserPrompt', 'STALE_HANDLE')
        assert_category(function() object:cancel(handle({
            runtime_generation=7,
            service_kind=contracts.ServiceKind.USER_PROMPT,
            contract_major=1, namespace='other'})) end,
            'UserPrompt', 'FOREIGN_HANDLE')
        assert.is_true(object:is_active(handle({runtime_generation=7,
            service_kind=contracts.ServiceKind.USER_PROMPT,
            contract_major=1, namespace='consumer'})))
        assert.equals(1, calls)
    end)

    it('preserves the stable UserPrompt busy category from delegation',
            function()
        local runtime = runtime_stub()
        local api = load_api(runtime, {
            get_prompt_handle_identity=function() end,
        })
        local factory = api.new_factory(contracts.ServiceKind.USER_PROMPT,
            'UserPromptServiceApi', {'prompt_map_location'})
        local object = factory:create({facade={
            prompt_map_location=function()
                error('DwarfUICore UserPromptService: [SERVICE_BUSY] active', 0)
            end,
        }, contract_major=1, namespace='consumer', generation=7,
            service_kind=contracts.ServiceKind.USER_PROMPT})

        assert_category(function() object:prompt_map_location({}) end,
            'UserPrompt', 'SERVICE_BUSY')
    end)

    it('uses the complete API failure precedence matrix without delegation',
            function()
        local cases = {
            {name='retired API', category='STALE_API',
                prepare=function(state) state.generation = 8 end,
                invoke=function(object) object:clear_namespace() end},
            {name='unhealthy runtime', category='SERVICE_UNHEALTHY',
                prepare=function(state)
                    state.status = contracts.RuntimeStatus.DISABLED
                end,
                invoke=function(object) object:clear_namespace() end},
            {name='malformed handle', category='INVALID_ARGUMENT',
                invoke=function(object) object:update_map_tile({}, {}) end},
            {name='old-generation handle', category='STALE_HANDLE',
                invoke=function(object)
                    object:update_map_tile({identity={runtime_generation=6,
                        service_kind=contracts.ServiceKind.TOOLTIP,
                        contract_major=1, namespace='consumer'}}, {})
                end},
            {name='foreign current handle', category='FOREIGN_HANDLE',
                invoke=function(object)
                    object:update_map_tile({identity={runtime_generation=7,
                        service_kind=contracts.ServiceKind.CONTEXT_MENU,
                        contract_major=1, namespace='consumer'}}, {})
                end},
        }
        for _, case in ipairs(cases) do
            local runtime, state = runtime_stub()
            local api = load_api(runtime, {get_map_handle_identity=function(handle)
                return handle.identity
            end})
            local calls = 0
            local factory = api.new_factory(contracts.ServiceKind.TOOLTIP,
                'TooltipServiceApi', {'clear_namespace', 'update_map_tile'})
            local object = factory:create({facade={
                clear_namespace=function() calls = calls + 1 return false end,
                update_map_tile=function() calls = calls + 1 return false end,
            }, contract_major=1, namespace='consumer', generation=7,
                service_kind=contracts.ServiceKind.TOOLTIP})
            if case.prepare then case.prepare(state) end
            assert_category(function() case.invoke(object) end,
                'Tooltip', case.category)
            assert.equals(0, calls, case.name .. ' invoked the facade')
        end
    end)
end)
