local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, immutable_enum = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
local _, contracts = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })
local _, namespaces = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')

---Creates one exact healthy runtime state.
---@param generation? integer
---@return table state
local function healthy_state(generation)
    return {
        generation=generation or 1,
        status=contracts.RuntimeStatus.HEALTHY,
        initializing={},
        services={},
        facades={},
    }
end

---Copies one acyclic test value for mutation-detection assertions.
---@param value any
---@return any copy
local function deep_copy(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for key, item in pairs(value) do
        copy[deep_copy(key)] = deep_copy(item)
    end
    return copy
end

---Loads the acquisition stack over one controlled process.
---@param process table
---@return table acquisition
---@return table runtime
local function load_acquisition(process)
    local _, runtime = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/runtime.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
            },
        })
    local _, acquisition = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/acquisition.lua', {
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/namespace']=namespaces,
                ['dwarfuicore/service_provider/runtime']=runtime,
            },
        })
    return acquisition, runtime
end

---Creates a complete controlled provider adapter.
---@param service_kind? dwarfuicore.ServiceKind
---@return table adapter
---@return table calls
local function complete_adapter(service_kind)
    local calls = {initialize=0, validate_service=0, build=0,
        validate_facade=0}
    local adapter = {
        service_kind=service_kind or contracts.ServiceKind.TOOLTIP,
        contract_major=1,
        initialize_service=function(generation)
            calls.initialize = calls.initialize + 1
            return {generation=generation, backend='service'}
        end,
        validate_service=function(service, generation)
            calls.validate_service = calls.validate_service + 1
            assert.equals(generation, service.generation)
        end,
        build_facade=function(service, generation)
            calls.build = calls.build + 1
            return {service=service, generation=generation, operation=function() end}
        end,
        validate_facade=function(facade, major)
            calls.validate_facade = calls.validate_facade + 1
            assert.equals(1, major)
            assert.is_function(facade.operation)
        end,
    }
    return adapter, calls
end

---Returns one acquisition error for exact stable-prefix assertions.
---@param acquisition table
---@param adapter table
---@param version any
---@param namespace any
---@return string failure
local function acquire_failure(acquisition, adapter, version, namespace)
    local ok, failure = pcall(acquisition.acquire,
        adapter.service_kind, adapter.contract_major,
        function() return adapter end, version, namespace)
    assert.is_false(ok)
    return tostring(failure)
end

---Asserts one exact provider prefix and stable category token.
---@param failure string
---@param provider string
---@param token string
local function assert_category(failure, provider, token)
    local expected = ('DwarfUICore %sServiceProvider: [%s] ')
        :format(provider, token)
    assert.equals(expected, failure:sub(1, #expected))
end

describe('service-provider atomic acquisition', function()
    it('maps constructor rejection conditions to stable categories', function()
        local cases = {
            {name='missing version', version=nil, namespace='consumer',
                token='INVALID_VERSION'},
            {name='fractional version', version=1.5, namespace='consumer',
                token='INVALID_VERSION'},
            {name='zero version', version=0, namespace='consumer',
                token='INVALID_VERSION'},
            {name='missing namespace', version=1, namespace=nil,
                token='INVALID_NAMESPACE'},
            {name='malformed namespace', version=1, namespace='Bad',
                token='INVALID_NAMESPACE'},
            {name='unsupported version', version=2, namespace='consumer',
                token='UNSUPPORTED_VERSION'},
        }
        for _, case in ipairs(cases) do
            local state = healthy_state()
            local process = {dwarfuicore={service_provider_runtime=state}}
            local acquisition = load_acquisition(process)
            local adapter, calls = complete_adapter()
            local failure = acquire_failure(acquisition, adapter,
                case.version, case.namespace)
            assert_category(failure, 'Tooltip', case.token)
            assert.equals(0, calls.initialize, case.name)
            assert.is_nil(state.initializing[contracts.ServiceKind.TOOLTIP])
            assert.is_nil(state.services[contracts.ServiceKind.TOOLTIP])
            assert.is_nil(state.facades[contracts.ServiceKind.TOOLTIP])
        end
    end)

    it('uses the context-menu provider prefix for its service kind', function()
        local state = healthy_state()
        local process = {dwarfuicore={service_provider_runtime=state}}
        local acquisition = load_acquisition(process)
        local adapter = complete_adapter(contracts.ServiceKind.CONTEXT_MENU)
        local failure = acquire_failure(acquisition, adapter, 0, 'consumer')
        assert_category(failure, 'ContextMenu', 'INVALID_VERSION')
    end)

    it('validates public arguments before a missing private implementation',
            function()
        local process = {dwarfuicore={}}
        local acquisition = load_acquisition(process)
        local ok, failure = pcall(acquisition.acquire,
            contracts.ServiceKind.TOOLTIP, 1, nil, 0, nil)
        assert.is_false(ok)
        assert_category(tostring(failure), 'Tooltip', 'INVALID_VERSION')

        ok, failure = pcall(acquisition.acquire,
            contracts.ServiceKind.TOOLTIP, 1, nil, 1, 'consumer')
        assert.is_false(ok)
        assert_category(tostring(failure),
            'Tooltip', 'INITIALIZATION_FAILED')
    end)

    it('loads private implementations only after argument validation',
            function()
        local state = healthy_state()
        local process = {dwarfuicore={service_provider_runtime=state}}
        local acquisition = load_acquisition(process)
        local load_count = 0
        local function failing_loader()
            load_count = load_count + 1
            error('implementation module is missing')
        end
        local ok, failure = pcall(acquisition.acquire,
            contracts.ServiceKind.TOOLTIP, 1, failing_loader, 0, 'consumer')
        assert.is_false(ok)
        assert_category(tostring(failure), 'Tooltip', 'INVALID_VERSION')
        assert.equals(0, load_count)

        ok, failure = pcall(acquisition.acquire,
            contracts.ServiceKind.TOOLTIP, 1, failing_loader, 1, 'consumer')
        assert.is_false(ok)
        assert_category(tostring(failure),
            'Tooltip', 'INITIALIZATION_FAILED')
        assert.equals(1, load_count)
    end)

    it('rejects malformed runtime and service state without repair', function()
        local cases = {
            {state=nil},
            {state={}},
            {state={generation=1, status=contracts.RuntimeStatus.DISABLED,
                initializing={}, services={}, facades={}}},
            {state={generation=1, status=contracts.RuntimeStatus.INITIALIZING,
                initializing={}, services={}, facades={}}},
            {state={generation=1, status=contracts.RuntimeStatus.RETIRING,
                initializing={}, services={}, facades={}}},
            {state={generation=1, status=contracts.RuntimeStatus.RETIRED,
                initializing={}, services={}, facades={}}},
            {state={generation=2, status=contracts.RuntimeStatus.HEALTHY,
                initializing={}, services={
                    [contracts.ServiceKind.TOOLTIP]={generation=1,
                        health=contracts.ServiceHealth.HEALTHY, value={}},
                }, facades={}}},
            {state={generation=1, status=contracts.RuntimeStatus.HEALTHY,
                initializing={}, services={}, facades={
                    [contracts.ServiceKind.TOOLTIP]={[1]={}},
                }}},
            {state={generation=1, status=contracts.RuntimeStatus.HEALTHY,
                initializing={}, services={}, facades={
                    [contracts.ServiceKind.TOOLTIP]={[2]={}},
                }}},
            {state={generation=1, status=contracts.RuntimeStatus.HEALTHY,
                initializing={}, services={
                    [contracts.ServiceKind.TOOLTIP]={generation=1,
                        health=contracts.ServiceHealth.HEALTHY,
                        value={generation=1, malformed=true}},
                }, facades={}}, configure_adapter=function(adapter)
                    adapter.validate_service = function()
                        error('cached service contract is malformed')
                    end
                end},
        }
        for _, health in ipairs({
                contracts.ServiceHealth.MISSING,
                contracts.ServiceHealth.INITIALIZING,
                contracts.ServiceHealth.UNHEALTHY,
                contracts.ServiceHealth.DISABLED,
            }) do
            table.insert(cases, {state={generation=1,
                status=contracts.RuntimeStatus.HEALTHY, initializing={},
                services={[contracts.ServiceKind.TOOLTIP]={generation=1,
                    health=health, value={}}}, facades={}}})
        end
        for _, case in ipairs(cases) do
            local state = case.state
            local snapshot = deep_copy(state)
            local process = {dwarfuicore={service_provider_runtime=state}}
            local acquisition = load_acquisition(process)
            local adapter, calls = complete_adapter()
            if case.configure_adapter then case.configure_adapter(adapter) end
            local failure = acquire_failure(
                acquisition, adapter, 1, 'consumer')
            assert_category(failure, 'Tooltip', 'SERVICE_UNHEALTHY')
            assert.equals(0, calls.initialize)
            assert.same(snapshot, state)
            assert.equals(state,
                process.dwarfuicore.service_provider_runtime)
        end
    end)

    it('rejects active per-service initialization as busy', function()
        local state = healthy_state()
        state.initializing[contracts.ServiceKind.TOOLTIP] = true
        local process = {dwarfuicore={service_provider_runtime=state}}
        local acquisition = load_acquisition(process)
        local adapter = complete_adapter()
        local failure = acquire_failure(acquisition, adapter, 1, 'consumer')
        assert_category(failure, 'Tooltip', 'INITIALIZATION_BUSY')
        assert.is_true(state.initializing[contracts.ServiceKind.TOOLTIP])
    end)

    it('maps incomplete adapters and every construction boundary to failure',
            function()
        local stages = {
            function(adapter) adapter.initialize_service = nil end,
            function(adapter)
                adapter.initialize_service = function()
                    error('missing prerequisite')
                end
            end,
            function(adapter)
                adapter.initialize_service = function() return false end
            end,
            function(adapter)
                adapter.validate_service = function()
                    error('invalid service contract')
                end
            end,
            function(adapter)
                adapter.build_facade = function()
                    error('facade construction failed')
                end
            end,
            function(adapter)
                adapter.build_facade = function() return false end
            end,
            function(adapter)
                adapter.validate_facade = function()
                    error('incomplete facade')
                end
            end,
        }
        for _, inject in ipairs(stages) do
            local state = healthy_state()
            local process = {dwarfuicore={service_provider_runtime=state}}
            local acquisition = load_acquisition(process)
            local adapter = complete_adapter()
            inject(adapter)
            local failure = acquire_failure(
                acquisition, adapter, 1, 'consumer')
            assert_category(failure, 'Tooltip', 'INITIALIZATION_FAILED')
            assert.is_nil(state.initializing[contracts.ServiceKind.TOOLTIP])
            assert.is_nil(state.services[contracts.ServiceKind.TOOLTIP])
            assert.is_nil(state.facades[contracts.ServiceKind.TOOLTIP])
        end
    end)

    it('propagates recursive acquisition as initialization busy', function()
        local state = healthy_state()
        local process = {dwarfuicore={service_provider_runtime=state}}
        local acquisition = load_acquisition(process)
        local adapter = complete_adapter()
        adapter.initialize_service = function()
            return acquisition.acquire(adapter.service_kind,
                adapter.contract_major, function() return adapter end,
                1, 'recursive')
        end
        local failure = acquire_failure(
            acquisition, adapter, 1, 'consumer')
        assert_category(failure, 'Tooltip', 'INITIALIZATION_BUSY')
        assert.is_nil(state.initializing[contracts.ServiceKind.TOOLTIP])
        assert.is_nil(state.services[contracts.ServiceKind.TOOLTIP])
        assert.is_nil(state.facades[contracts.ServiceKind.TOOLTIP])
    end)

    it('guards validation of an existing facade against recursion', function()
        local state = healthy_state()
        local process = {dwarfuicore={service_provider_runtime=state}}
        local acquisition = load_acquisition(process)
        local adapter = complete_adapter()
        acquisition.acquire(adapter.service_kind, adapter.contract_major,
            function() return adapter end, 1, 'first')
        adapter.validate_facade = function()
            acquisition.acquire(adapter.service_kind,
                adapter.contract_major, function() return adapter end,
                1, 'recursive')
        end
        local failure = acquire_failure(
            acquisition, adapter, 1, 'consumer')
        assert_category(failure, 'Tooltip', 'INITIALIZATION_BUSY')
        assert.is_nil(state.initializing[contracts.ServiceKind.TOOLTIP])
        assert.is_table(state.services[contracts.ServiceKind.TOOLTIP])
        assert.is_table(state.facades[contracts.ServiceKind.TOOLTIP][1])
    end)

    it('leaves a replacement generation untouched after publication failure',
            function()
        local old_state = healthy_state(1)
        local process = {dwarfuicore={service_provider_runtime=old_state}}
        local acquisition = load_acquisition(process)
        local adapter = complete_adapter()
        local replacement = healthy_state(2)
        adapter.validate_facade = function(facade)
            assert.is_function(facade.operation)
            process.dwarfuicore.service_provider_runtime = replacement
        end
        local failure = acquire_failure(
            acquisition, adapter, 1, 'consumer')
        assert_category(failure, 'Tooltip', 'INITIALIZATION_FAILED')
        assert.equals(replacement,
            process.dwarfuicore.service_provider_runtime)
        assert.is_nil(replacement.initializing[contracts.ServiceKind.TOOLTIP])
        assert.is_nil(replacement.services[contracts.ServiceKind.TOOLTIP])
        assert.is_nil(replacement.facades[contracts.ServiceKind.TOOLTIP])
    end)

    it('publishes only after full validation and permits corrected retry',
            function()
        local state = healthy_state(7)
        local process = {dwarfuicore={service_provider_runtime=state}}
        local acquisition = load_acquisition(process)
        local adapter, calls = complete_adapter()
        local fail_validation = true
        adapter.validate_facade = function(facade)
            calls.validate_facade = calls.validate_facade + 1
            if fail_validation then error('not complete yet') end
            assert.is_function(facade.operation)
        end
        local failure = acquire_failure(
            acquisition, adapter, 1, 'consumer')
        assert_category(failure, 'Tooltip', 'INITIALIZATION_FAILED')
        assert.is_nil(state.services[contracts.ServiceKind.TOOLTIP])
        assert.is_nil(state.facades[contracts.ServiceKind.TOOLTIP])

        fail_validation = false
        local metadata = acquisition.acquire(adapter.service_kind,
            adapter.contract_major, function() return adapter end,
            1, 'consumer')
        assert.equals(7, metadata.generation)
        assert.equals(1, metadata.contract_major)
        assert.equals('consumer', metadata.namespace)
        assert.equals(contracts.ServiceKind.TOOLTIP, metadata.service_kind)
        assert.is_table(metadata.facade)
        assert.equals(metadata.facade,
            state.facades[contracts.ServiceKind.TOOLTIP][1])
        assert.equals(metadata.facade.service,
            state.services[contracts.ServiceKind.TOOLTIP].value)
        assert.equals(contracts.ServiceHealth.HEALTHY,
            state.services[contracts.ServiceKind.TOOLTIP].health)
    end)

    it('reuses services and facades across repeated and cross-service calls',
            function()
        local state = healthy_state()
        local process = {dwarfuicore={service_provider_runtime=state}}
        local acquisition = load_acquisition(process)
        local tooltip, tooltip_calls = complete_adapter()
        local context, context_calls =
            complete_adapter(contracts.ServiceKind.CONTEXT_MENU)

        local first = acquisition.acquire(tooltip.service_kind,
            tooltip.contract_major, function() return tooltip end, 1, 'first')
        local second = acquisition.acquire(tooltip.service_kind,
            tooltip.contract_major, function() return tooltip end, 1, 'second')
        local context_result = acquisition.acquire(context.service_kind,
            context.contract_major, function() return context end, 1, 'context')
        assert.is_not_equal(first, second)
        assert.equals(first.facade, second.facade)
        assert.equals(1, tooltip_calls.initialize)
        assert.equals(1, tooltip_calls.build)
        assert.equals(1, context_calls.initialize)
        assert.equals(1, context_calls.build)
        assert.is_not_equal(first.facade, context_result.facade)
        assert.is_nil(state.initializing[contracts.ServiceKind.TOOLTIP])
        assert.is_nil(state.initializing[contracts.ServiceKind.CONTEXT_MENU])
    end)

    it('does not invoke teardown, reload, clearing, or overlay rescans',
            function()
        local state = healthy_state()
        local process = {dwarfuicore={service_provider_runtime=state}}
        local acquisition = load_acquisition(process)
        local adapter = complete_adapter()
        acquisition.acquire(adapter.service_kind, adapter.contract_major,
            function() return adapter end, 1, 'consumer')
        assert.is_nil(process.teardown_count)
        assert.is_nil(process.reload_count)
        assert.is_nil(process.cleared_environments)
        assert.is_nil(process.overlay_rescan_count)
    end)
end)
