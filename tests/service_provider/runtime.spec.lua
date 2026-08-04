local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, immutable_enum = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
local _, contracts = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })

---Loads runtime lifecycle functions over test-controlled process state.
---@param process table
---@return table runtime
local function load_runtime(process)
    local _, runtime = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/runtime.lua', {
        globals={dfhack=process},
        reqscript={
            ['dwarfuicore/service_provider/contracts']=contracts,
        },
    })
    return runtime
end

---Creates one exact healthy runtime state for focused validation.
---@param generation? integer
---@return table state
local function healthy_state(generation)
    return {generation=generation or 1,
        status=contracts.RuntimeStatus.HEALTHY, initializing={}, services={},
        facades={}}
end

describe('service-provider process runtime', function()
    it('publishes exactly one cold generation and reuses it idempotently', function()
        local process = {}
        local runtime = load_runtime(process)
        local state, created = runtime.begin_initialization()
        assert.is_true(created)
        assert.same({generation=1,
            status=contracts.RuntimeStatus.INITIALIZING, initializing={},
            services={}, facades={}}, state)
        runtime.complete_initialization(1)
        local same, recreated = runtime.begin_initialization()
        assert.is_false(recreated)
        assert.equals(state, same)
        assert.same({facades=true, generation=true, initializing=true,
            services=true, status=true}, (function()
            local fields = {}
            for field in pairs(state) do fields[field] = true end
            return fields
        end)())
    end)

    it('performs explicit retiring and successor-generation transitions', function()
        local process = {dwarfuicore={
            service_provider_runtime=healthy_state(4)}}
        local runtime = load_runtime(process)
        local old = runtime.begin_reload()
        assert.equals(contracts.RuntimeStatus.RETIRING, old.status)
        local fresh = runtime.begin_reconstruction()
        assert.equals(contracts.RuntimeStatus.RETIRED, old.status)
        assert.equals(5, fresh.generation)
        assert.equals(contracts.RuntimeStatus.INITIALIZING, fresh.status)
        runtime.complete_initialization(5)
        assert.equals(contracts.RuntimeStatus.HEALTHY, fresh.status)
        assert.has_error(function() runtime.validate(4) end,
            'DwarfUICore runtime generation does not match.')
    end)

    it('allows explicit reconstruction retry after a failed generation',
            function()
        local process = {dwarfuicore={
            service_provider_runtime=healthy_state(4)}}
        local runtime = load_runtime(process)
        runtime.begin_reload()
        local failed = runtime.begin_reconstruction()
        runtime.fail_initialization(failed.generation)

        local retrying = runtime.begin_reload()
        assert.equals(contracts.RuntimeStatus.RETIRING, retrying.status)
        local recovered = runtime.begin_reconstruction()
        runtime.complete_initialization(recovered.generation)

        assert.equals(6, recovered.generation)
        assert.equals(contracts.RuntimeStatus.HEALTHY, recovered.status)
    end)

    it('represents and rejects every non-acquirable runtime status', function()
        for _, status in ipairs({contracts.RuntimeStatus.INITIALIZING,
                contracts.RuntimeStatus.DISABLED,
                contracts.RuntimeStatus.RETIRING,
                contracts.RuntimeStatus.RETIRED}) do
            local process = {dwarfuicore={service_provider_runtime={
                generation=1, status=status, initializing={}, services={},
                facades={}}}}
            local runtime = load_runtime(process)
            assert.has_error(function() runtime.validate_acquirable() end,
                'DwarfUICore runtime is not healthy for acquisition.')
        end
    end)

    it('validates missing, malformed, partial, and wrong-generation state', function()
        local process = {}
        local runtime = load_runtime(process)
        assert.has_error(function() runtime.validate() end,
            'DwarfUICore runtime state is missing.')
        local malformed = {
            {},
            {generation=1, status=contracts.RuntimeStatus.HEALTHY,
                initializing={}, services={}},
            {generation=0, status=contracts.RuntimeStatus.HEALTHY,
                initializing={}, services={}, facades={}},
            {generation=1, status=999, initializing={}, services={}, facades={}},
            {generation=1, status=contracts.RuntimeStatus.HEALTHY,
                initializing={[999]=true}, services={}, facades={}},
            {generation=1, status=contracts.RuntimeStatus.HEALTHY,
                initializing={}, services={}, facades={}, package_version='1'},
        }
        for _, state in ipairs(malformed) do
            process.dwarfuicore = {service_provider_runtime=state}
            assert.has_error(function() runtime.validate() end)
            assert.equals(state, process.dwarfuicore.service_provider_runtime)
        end
        process.dwarfuicore = {service_provider_runtime=healthy_state(2)}
        assert.has_error(function() runtime.validate(1) end,
            'DwarfUICore runtime generation does not match.')
    end)

    it('publishes services only after successful local construction', function()
        local process = {dwarfuicore={
            service_provider_runtime=healthy_state()}}
        local runtime = load_runtime(process)
        local constructions = 0
        local service, created = runtime.initialize_service(
            contracts.ServiceKind.TOOLTIP, function(generation)
                constructions = constructions + 1
                return {generation=generation}
            end)
        assert.is_true(created)
        assert.equals(1, service.generation)
        local same, recreated = runtime.initialize_service(
            contracts.ServiceKind.TOOLTIP, function()
                error('must not reconstruct')
            end)
        assert.is_false(recreated)
        assert.equals(service, same)
        assert.equals(1, constructions)
        assert.equals(service, runtime.get_service(
            contracts.ServiceKind.TOOLTIP, 1))
    end)

    it('accepts UserPrompt in every service-kind-keyed runtime map', function()
        local state = healthy_state()
        local process = {dwarfuicore={service_provider_runtime=state}}
        local runtime = load_runtime(process)
        local service, created = runtime.initialize_service(
            contracts.ServiceKind.USER_PROMPT,
            function(generation) return {generation=generation} end)

        assert.is_true(created)
        assert.equals(service, runtime.get_service(
            contracts.ServiceKind.USER_PROMPT, 1))
        local facade = {}
        runtime.publish_facade(
            contracts.ServiceKind.USER_PROMPT, 1, facade)
        assert.equals(facade, runtime.get_facade(
            contracts.ServiceKind.USER_PROMPT, 1))
    end)

    it('clears failed initialization without facade or healthy publication', function()
        local state = healthy_state()
        local process = {dwarfuicore={service_provider_runtime=state}}
        local runtime = load_runtime(process)
        assert.has_error(function()
            runtime.initialize_service(contracts.ServiceKind.CONTEXT_MENU,
                function() error('construction failed') end)
        end)
        assert.is_nil(state.initializing[contracts.ServiceKind.CONTEXT_MENU])
        assert.is_nil(state.services[contracts.ServiceKind.CONTEXT_MENU])
        assert.is_nil(state.facades[contracts.ServiceKind.CONTEXT_MENU])
        local service = runtime.initialize_service(
            contracts.ServiceKind.CONTEXT_MENU, function() return {} end)
        assert.is_table(service)
    end)

    it('separates unhealthy service state from compatibility-free facade keys', function()
        local state = healthy_state()
        state.services[contracts.ServiceKind.TOOLTIP] = {generation=1,
            health=contracts.ServiceHealth.DISABLED, value={}}
        local process = {dwarfuicore={service_provider_runtime=state}}
        local runtime = load_runtime(process)
        assert.has_error(function()
            runtime.get_service(contracts.ServiceKind.TOOLTIP)
        end, 'DwarfUICore service is not healthy.')
        assert.has_error(function()
            runtime.initialize_service(contracts.ServiceKind.TOOLTIP,
                function() return {} end)
        end, 'DwarfUICore existing service is not healthy.')
        state.services[contracts.ServiceKind.TOOLTIP].health =
            contracts.ServiceHealth.HEALTHY
        local adapter_key = {}
        local facade = {}
        runtime.publish_facade(contracts.ServiceKind.TOOLTIP,
            adapter_key, facade)
        assert.equals(facade, runtime.get_facade(
            contracts.ServiceKind.TOOLTIP, adapter_key))
        assert.is_nil(rawget(state, 'supported_versions'))
        assert.is_nil(rawget(state, 'manifest'))
    end)

    it('validates without teardown, reload, repair, clear, or rescan effects', function()
        local malformed = {generation=1,
            status=contracts.RuntimeStatus.HEALTHY, initializing={},
            services={bad=true}, facades={}}
        local process = {dwarfuicore={service_provider_runtime=malformed}}
        local runtime = load_runtime(process)
        local snapshot = {generation=malformed.generation,
            status=malformed.status, initializing=malformed.initializing,
            services=malformed.services, facades=malformed.facades}
        assert.has_error(function() runtime.validate() end)
        assert.same(snapshot, malformed)
        assert.is_nil(process.cleared_environments)
        assert.is_nil(process.teardown_count)
        assert.is_nil(process.overlay_rescan_count)
    end)

    it('publishes service and facade together and cancels failed work', function()
        local state = healthy_state(3)
        local process = {dwarfuicore={service_provider_runtime=state}}
        local runtime = load_runtime(process)
        local acquired, service, facade =
            runtime.begin_service_acquisition(
                contracts.ServiceKind.TOOLTIP, 1)
        assert.equals(state, acquired)
        assert.is_nil(service)
        assert.is_nil(facade)
        assert.is_true(state.initializing[contracts.ServiceKind.TOOLTIP])
        local new_service = {}
        local new_facade = {}
        runtime.publish_service_acquisition(
            contracts.ServiceKind.TOOLTIP, 1, 3,
            new_service, new_facade)
        assert.equals(new_service,
            state.services[contracts.ServiceKind.TOOLTIP].value)
        assert.equals(new_facade,
            state.facades[contracts.ServiceKind.TOOLTIP][1])
        assert.is_nil(state.initializing[contracts.ServiceKind.TOOLTIP])

        runtime.begin_service_acquisition(
            contracts.ServiceKind.CONTEXT_MENU, 1)
        runtime.cancel_service_acquisition(
            contracts.ServiceKind.CONTEXT_MENU, 2)
        assert.is_true(
            state.initializing[contracts.ServiceKind.CONTEXT_MENU])
        runtime.cancel_service_acquisition(
            contracts.ServiceKind.CONTEXT_MENU, 3)
        assert.is_nil(state.initializing[contracts.ServiceKind.CONTEXT_MENU])
    end)

    it('rejects every facade cache whose service record is absent', function()
        for _, cache in ipairs({{}, {[1]={}}, {[2]={}}}) do
            local state = healthy_state()
            state.facades[contracts.ServiceKind.TOOLTIP] = cache
            local process = {dwarfuicore={service_provider_runtime=state}}
            local runtime = load_runtime(process)
            assert.has_error(function()
                runtime.begin_service_acquisition(
                    contracts.ServiceKind.TOOLTIP, 1)
            end, 'DwarfUICore facade cache exists without its service.')
            assert.equals(cache,
                state.facades[contracts.ServiceKind.TOOLTIP])
            assert.is_nil(state.services[contracts.ServiceKind.TOOLTIP])
            assert.is_nil(state.initializing[contracts.ServiceKind.TOOLTIP])
        end
    end)
end)
