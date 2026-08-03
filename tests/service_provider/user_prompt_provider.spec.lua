local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads the complete UserPrompt provider stack over one controlled process.
---@param settings? table
---@return table context
local function load_context(settings)
    settings = settings or {}
    local process = settings.process or {dwarfuicore={}}
    local ui = settings.ui or {root={}}
    process.onStateChange = process.onStateChange or {}
    process.isMapLoaded = function() return true end
    process.gui = {getMousePos=function() return nil end}
    process.screen = {
        getMousePos=function() return nil end,
        invalidate=function()
            ui.invalidation_count = (ui.invalidation_count or 0) + 1
        end,
    }
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
    local state
    if process.dwarfuicore.service_provider_runtime == nil then
        state = runtime.begin_initialization()
    else
        state = runtime.validate()
    end
    if state.status == contracts.RuntimeStatus.INITIALIZING then
        runtime.complete_initialization(state.generation)
    end
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
    local context_service = {
        close=function() return false end,
        get_open_source_root=function() return nil end,
        set_opening_guard=function(_, guard) ui.opening_guard = guard end,
    }
    local input_manager = settings.input_manager or {
        resolve_current_surface=function() return ui.root end,
        prepare_priority_consumer=function(_, _, callbacks)
            ui.prepared_input = {callbacks=callbacks}
            return ui.prepared_input
        end,
        release_priority_consumer=function(_, prepared)
            if ui.prepared_input == prepared then ui.prepared_input = nil end
            if ui.active_input == prepared then ui.active_input = nil end
            return true
        end,
        activate_priority_consumer=function(_, prepared)
            ui.prepared_input = nil
            ui.active_input = prepared
            return true
        end,
    }
    local presenter = settings.presenter or {
        prepare_authoritative_intent=function(_, _, present)
            ui.prepared_render = {present=present}
            return ui.prepared_render
        end,
        release_authoritative_intent=function(_, prepared)
            if ui.prepared_render == prepared then ui.prepared_render = nil end
            return true
        end,
        activate_authoritative_intent=function(_, prepared)
            ui.prepared_render = nil
            ui.active_render = prepared
            ui.tooltip_suppressed = true
            return true
        end,
        invalidate_authoritative_intent=function() return true end,
        release_authoritative_render=function(_, prepared)
            if ui.active_render == prepared then ui.active_render = nil end
            return true
        end,
        release_tooltip_suppression=function()
            ui.tooltip_suppressed = false
            return true
        end,
    }
    local renderer_class = setmetatable({}, {__call=function()
        return {set_prompt=function(_, request)
            ui.rendered_request = request
        end, render=function() end}
    end})
    local _, prompt_runtime = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/runtime.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/context_menu/service']={service=context_service},
                ['dwarfuicore/context_menu/screen']={},
                ['dwarfuicore/context_menu/input_hook']={manager=input_manager},
                ['dwarfuicore/user_prompt/indicator']={
                    NativeIndicatorAdapter={new=function()
                        local indicator = {released=false}
                        ui.indicator = indicator
                        return {prepare=function() end,
                            commit_prepared=function()
                                indicator.acquired = true
                                return true
                            end,
                            update=function() end,
                            release=function()
                                indicator.acquired = false
                                indicator.released = true
                                return true
                            end}
                    end},
                },
                ['dwarfuicore/user_prompt/input_consumer']={
                    UserPromptInputConsumer={new=function()
                        return {callbacks=function() return {} end}
                    end},
                },
                ['dwarfuicore/user_prompt/renderer']={
                    UserPromptRenderer=renderer_class,
                },
                ['dwarfuicore/user_prompt/service']=service,
                ['dwarfuicore/tooltip/runtime']={presenter=presenter},
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
    return {process=process, ui=ui, input_manager=input_manager,
        presenter=presenter, contracts=contracts, runtime=runtime,
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

    it('reports contained service failure without damaging other providers',
            function()
        local context = load_context()
        local tooltip_service = {name='tooltip'}
        local menu_service = {name='context-menu'}
        context.runtime.initialize_service(
            context.contracts.ServiceKind.TOOLTIP,
            function() return tooltip_service end)
        context.runtime.initialize_service(
            context.contracts.ServiceKind.CONTEXT_MENU,
            function() return menu_service end)
        local api = context.provider:new(1, 'consumer')
        local callback_failure
        api:prompt_map_location(options(nil, function()
            local ok, failure = pcall(function()
                api:prompt_map_location(options())
            end)
            assert.is_false(ok)
            callback_failure = tostring(failure)
        end))

        assert.is_true(context.service.service:cancel_active(
            context.service.UserPromptTerminalCause.INTERNAL_FAILURE))
        assert.is_truthy(callback_failure:find(
            'DwarfUICore UserPromptServiceApi: [SERVICE_UNHEALTHY] ',
            1, true))
        assert.equals(context.contracts.ServiceHealth.UNHEALTHY,
            context.state.services[
                context.contracts.ServiceKind.USER_PROMPT].health)
        assert_category(function() api:prompt_map_location(options()) end,
            'ServiceApi', 'SERVICE_UNHEALTHY')
        assert_category(function() api:get_contract_version() end,
            'ServiceApi', 'SERVICE_UNHEALTHY')
        assert_category(function() context.provider:new(1, 'other') end,
            'ServiceProvider', 'SERVICE_UNHEALTHY')
        assert.is_equal(tooltip_service, context.runtime.get_service(
            context.contracts.ServiceKind.TOOLTIP))
        assert.is_equal(menu_service, context.runtime.get_service(
            context.contracts.ServiceKind.CONTEXT_MENU))
    end)

    it('reconstructs one clean generation and invalidates old APIs and handles',
            function()
        local first = load_context()
        local old_api = first.provider:new(1, 'consumer')
        local old_handle = old_api:prompt_map_location(options())
        local old_indicator = first.ui.indicator
        local old_state_callback = first.process.onStateChange[
            'dwarfuicore-user-prompt']
        assert.is_not_nil(first.ui.active_input)
        assert.is_not_nil(first.ui.active_render)
        assert.is_true(first.ui.tooltip_suppressed)
        assert.is_true(old_indicator.acquired)

        first.runtime.begin_reload()
        assert.is_true(first.prompt_runtime.retire_for_reload())
        assert.is_nil(first.process.onStateChange[
            'dwarfuicore-user-prompt'])
        assert.is_nil(first.ui.active_input)
        assert.is_nil(first.ui.active_render)
        assert.is_false(first.ui.tooltip_suppressed)
        assert.is_nil(first.ui.rendered_request)
        assert.is_false(old_indicator.acquired)
        assert.is_true(old_indicator.released)

        local successor = first.runtime.begin_reconstruction()
        first.process.dwarfuicore.user_prompt_service = nil
        local second = load_context({
            process=first.process,
            ui=first.ui,
            input_manager=first.input_manager,
            presenter=first.presenter,
        })
        assert.equals(successor.generation, second.state.generation)
        assert_category(function() old_api:get_contract_version() end,
            'ServiceApi', 'STALE_API')
        local fresh_api = second.provider:new(1, 'consumer')
        assert_category(function() fresh_api:is_active(old_handle) end,
            'ServiceApi', 'STALE_HANDLE')
        local new_callback = second.process.onStateChange[
            'dwarfuicore-user-prompt']
        assert.is_not_nil(new_callback)
        assert.is_not_equal(old_state_callback, new_callback)
        local callback_count = 0
        for key, callback in pairs(second.process.onStateChange) do
            if key == 'dwarfuicore-user-prompt' and callback ~= nil then
                callback_count = callback_count + 1
            end
        end
        assert.equals(1, callback_count)

        local fresh_handle = fresh_api:prompt_map_location(options())
        assert.is_true(fresh_api:is_active(fresh_handle))
        assert.is_not_nil(second.ui.active_input)
        assert.is_not_nil(second.ui.active_render)
        assert.is_true(second.ui.tooltip_suppressed)
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
