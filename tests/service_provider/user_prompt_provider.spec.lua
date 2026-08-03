local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads the complete UserPrompt provider stack over one controlled process.
---@return table context
local function load_context()
    local process = {dwarfuicore={}}
    local _, immutable_enum = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local _, contracts = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
            },
        })
    local _, namespaces = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')
    local _, immutable_proxy = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')
    local _, identity = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/identity.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/namespace']=namespaces,
                ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
            },
        })
    local _, runtime = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/runtime.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
            },
        })
    local state = runtime.begin_initialization()
    runtime.complete_initialization(state.generation)
    local _, acquisition = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/acquisition.lua', {
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/namespace']=namespaces,
                ['dwarfuicore/service_provider/runtime']=runtime,
            },
        })
    local _, api = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/api.lua', {
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/identity']=identity,
                ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
                ['dwarfuicore/service_provider/runtime']=runtime,
            },
        })
    local _, values = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/value.lua', {
            reqscript={
                ['dwarfuicore/service_provider/namespace']=namespaces,
            },
        })
    local _, service = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/service.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/identity']=identity,
                ['dwarfuicore/service_provider/namespace']=namespaces,
                ['dwarfuicore/user_prompt/value']=values,
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
            },
        })
    local _, prompt_runtime = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/runtime.lua', {
            reqscript={
                ['dwarfuicore/user_prompt/service']=service,
            },
        })
    local _, adapter = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/user_prompt_adapter_v1.lua', {
            reqscript={
                ['dwarfuicore/user_prompt/value']=values,
                ['dwarfuicore/user_prompt/runtime']=prompt_runtime,
            },
        })
    local _, provider = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/user_prompt_provider.lua', {
            reqscript={
                ['dwarfuicore/service_provider/acquisition']=acquisition,
                ['dwarfuicore/service_provider/api']=api,
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
                ['dwarfuicore/service_provider/user_prompt_adapter_v1']=adapter,
            },
        })
    return {process=process, contracts=contracts, runtime=runtime,
        state=state, identity=identity, values=values, service=service,
        adapter=adapter, prompt_runtime=prompt_runtime,
        provider=provider.get_provider()}
end

---Asserts one stable UserPrompt provider or API error category.
---@param callback function
---@param boundary string
---@param category string
local function assert_category(callback, boundary, category)
    local ok, failure = pcall(callback)
    assert.is_false(ok)
    local expected = ('DwarfUICore UserPrompt%s: [%s] '):format(
        boundary, category)
    assert.equals(expected, tostring(failure):sub(1, #expected))
end

---Creates valid prompt options with observable callbacks.
---@param on_select? function
---@param on_cancel? function
---@return table options
local function options(on_select, on_cancel)
    return {title='Title', message='Message',
        on_select=on_select or function() end, on_cancel=on_cancel}
end

describe('UserPrompt provider runtime', function()
    it('constructs distinct immutable APIs over one cached service and facade',
            function()
        local context = load_context()
        local tooltip_service = {name='tooltip'}
        local context_service = {name='context-menu'}
        context.runtime.initialize_service(
            context.contracts.ServiceKind.TOOLTIP,
            function() return tooltip_service end)
        context.runtime.initialize_service(
            context.contracts.ServiceKind.CONTEXT_MENU,
            function() return context_service end)
        local tooltip_facade, context_facade = {}, {}
        context.runtime.publish_facade(
            context.contracts.ServiceKind.TOOLTIP, 1, tooltip_facade)
        context.runtime.publish_facade(
            context.contracts.ServiceKind.CONTEXT_MENU, 1, context_facade)
        local input_owner, render_owner = {}, {}
        context.process.dwarfuicore.context_menu_input_hook = input_owner
        context.process.dwarfuicore.tooltip_runtime = render_owner

        local first = context.provider:new(1, 'consumer')
        local active = first:prompt_map_location(options())
        local cached_service = context.state.services[
            context.contracts.ServiceKind.USER_PROMPT].value
        local cached_facade = context.state.facades[
            context.contracts.ServiceKind.USER_PROMPT][1]
        local second = context.provider:new(1, 'consumer')

        assert.is_not_equal(first, second)
        assert.is_true(second:is_active(active))
        assert.equals(1, first:get_contract_version())
        assert.equals('consumer', first:get_namespace())
        assert.equals(cached_service, context.state.services[
            context.contracts.ServiceKind.USER_PROMPT].value)
        assert.equals(cached_facade, context.state.facades[
            context.contracts.ServiceKind.USER_PROMPT][1])
        assert.equals(tooltip_service, context.state.services[
            context.contracts.ServiceKind.TOOLTIP].value)
        assert.equals(context_service, context.state.services[
            context.contracts.ServiceKind.CONTEXT_MENU].value)
        assert.equals(tooltip_facade, context.state.facades[
            context.contracts.ServiceKind.TOOLTIP][1])
        assert.equals(context_facade, context.state.facades[
            context.contracts.ServiceKind.CONTEXT_MENU][1])
        assert.is_equal(input_owner,
            context.process.dwarfuicore.context_menu_input_hook)
        assert.is_equal(render_owner,
            context.process.dwarfuicore.tooltip_runtime)
        assert.same({}, (function()
            local keys = {}
            for key in pairs(first) do table.insert(keys, key) end
            return keys
        end)())
        assert.has_error(function() first.cancel = function() end end,
            'DwarfUICore UserPromptServiceApi is immutable.')
    end)

    it('validates constructor arguments transactionally with exact prefixes',
            function()
        local context = load_context()
        assert_category(function() context.provider:new(0, 'consumer') end,
            'ServiceProvider', 'INVALID_VERSION')
        assert_category(function() context.provider:new(1, 'Bad Name') end,
            'ServiceProvider', 'INVALID_NAMESPACE')
        assert_category(function() context.provider:new(2, 'consumer') end,
            'ServiceProvider', 'UNSUPPORTED_VERSION')
        assert.is_nil(context.state.services[
            context.contracts.ServiceKind.USER_PROMPT])
        assert.is_nil(context.state.facades[
            context.contracts.ServiceKind.USER_PROMPT])
    end)

    it('rejects a private service from another runtime generation', function()
        local context = load_context()
        assert.has_error(function()
            context.adapter.validate_service({
                generation=2,
                service=context.service.service,
            }, 2)
        end, 'DwarfUICore UserPrompt runtime is incomplete or stale.')
        assert.is_nil(context.state.services[
            context.contracts.ServiceKind.USER_PROMPT])
    end)

    it('copies options, binds namespace, and implements handle operations',
            function()
        local context = load_context()
        local api = context.provider:new(1, 'consumer')
        local source = options()
        source.title = ''
        source.message = 'first\nsecond'
        local handle = api:prompt_map_location(source)
        source.title, source.message = 'changed', 'changed'

        assert.is_true(api:is_active(handle))
        local pending = context.process.dwarfuicore.user_prompt_service.pending
        assert.equals('', pending.request.title)
        assert.equals('first\nsecond', pending.request.message)
        local diagnostics = context.service.service:get_diagnostics()
        assert.equals('consumer', diagnostics.active_namespace)
        assert.is_true(api:cancel(handle))
        assert.is_false(api:is_active(handle))
        assert.is_false(api:cancel(handle))
        assert.is_false(api:clear_namespace())
    end)

    it('preserves busy errors and blocks same-namespace clear reentry',
            function()
        local context = load_context()
        local api = context.provider:new(1, 'consumer')
        local reentry_failure
        api:prompt_map_location(options(nil, function()
            local ok, failure = pcall(function()
                api:prompt_map_location(options())
            end)
            assert.is_false(ok)
            reentry_failure = tostring(failure)
        end))

        assert_category(function()
            api:prompt_map_location(options())
        end, 'ServiceApi', 'SERVICE_BUSY')
        assert.is_true(api:clear_namespace())
        assert.is_truthy(reentry_failure:find(
            'DwarfUICore UserPromptServiceApi: [SERVICE_BUSY] ', 1, true))
        local replacement = api:prompt_map_location(options())
        assert.is_true(api:is_active(replacement))
    end)

    it('enforces malformed, stale, and foreign prompt-handle precedence',
            function()
        local context = load_context()
        local api = context.provider:new(1, 'consumer')
        local other = context.provider:new(1, 'other')
        local handle = api:prompt_map_location(options())

        assert_category(function() api:cancel({}) end,
            'ServiceApi', 'INVALID_ARGUMENT')
        assert.is_false(other:clear_namespace())
        assert.is_true(api:is_active(handle))
        assert_category(function() other:is_active(handle) end,
            'ServiceApi', 'FOREIGN_HANDLE')
        context.process.dwarfuicore.service_provider_runtime = {
            generation=2,
            status=context.contracts.RuntimeStatus.HEALTHY,
            initializing={}, services={}, facades={},
        }
        assert_category(function() api:is_active(handle) end,
            'ServiceApi', 'STALE_API')
    end)

    it('validates and copies every public option before prompt mutation',
            function()
        local context = load_context()
        local api = context.provider:new(1, 'consumer')
        for _, invalid in ipairs({
                {},
                {title='Title', message='Message'},
                {title=false, message='Message', on_select=function() end},
                {title='Title', message=false, on_select=function() end},
                {title='Title', message='Message', on_select=false},
                {title='Title', message='Message', on_select=function() end,
                    namespace='spoofed'},
            }) do
            assert_category(function() api:prompt_map_location(invalid) end,
                'ServiceApi', 'INVALID_ARGUMENT')
            assert.is_false(context.service.service:has_active_prompt())
        end
    end)
end)
