local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads one isolated UserPrompt model stack over controlled process state.
---@return table context
local function load_context()
    local process = {dwarfuicore={service_provider_runtime={generation=7}}}
    local _, immutable_enum = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local _, contracts = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
            },
        })
    local _, namespace = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')
    local _, immutable_proxy = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')
    local _, identity = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/identity.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/namespace']=namespace,
                ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
            },
        })
    local _, value = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/value.lua', {
            reqscript={
                ['dwarfuicore/service_provider/namespace']=namespace,
            },
        })
    local _, service = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/service.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/identity']=identity,
                ['dwarfuicore/service_provider/namespace']=namespace,
                ['dwarfuicore/user_prompt/value']=value,
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
            },
        })
    return {process=process, contracts=contracts, identity=identity,
        value=value, module=service}
end

---Creates one request snapshot with test callbacks.
---@param context table
---@param namespace? string
---@param on_select? function
---@param on_cancel? function
---@return dwarfuicore.MapLocationPromptRequest request
local function request(context, namespace, on_select, on_cancel)
    return context.value.MapLocationPromptRequest.new(namespace or 'owner', {
        title='Title',
        message='Message',
        on_select=on_select or function() end,
        on_cancel=on_cancel,
    })
end

---Creates cleanup stand-ins that append their names to one event log.
---@param events table
---@param callback? fun(name: string)
---@return dwarfuicore.UserPromptCleanupPorts cleanup
local function cleanup_ports(events, callback)
    local cleanup = {}
    for _, name in ipairs{
            'input', 'render', 'tooltip_suppression', 'indicator',
            'invalidation'} do
        cleanup[name] = function()
            table.insert(events, name)
            if callback then callback(name) end
        end
    end
    return cleanup
end

---Asserts one stable internal error category without depending on detail text.
---@param callback function
---@param category string
local function assert_category(callback, category)
    local ok, failure = pcall(callback)
    assert.is_false(ok)
    assert.is_truthy(tostring(failure):find(
        ('[%s]'):format(category), 1, true), tostring(failure))
end

describe('UserPrompt state model', function()
    it('defines immutable complete state and terminal-cause sets', function()
        local context = load_context()
        local state = context.module.UserPromptState
        local cause = context.module.UserPromptTerminalCause

        assert.same({IDLE=1, ACTIVATING=2, ACTIVE=3, TERMINATING=4},
            (function()
                local copy = {}
                for key, value in pairs(state) do copy[key] = value end
                return copy
            end)())
        assert.equals(10, (function()
            local count = 0
            for _ in pairs(cause) do count = count + 1 end
            return count
        end)())
        assert.has_error(function() state.OTHER = 99 end)
        assert.has_error(function() cause.OTHER = 99 end)
    end)

    it('rejects a second prompt before cleanup or ownership mutation',
            function()
        local context = load_context()
        local events = {}
        local state = context.module.new_state(7)
        local service = context.module.UserPromptService.new(
            state, cleanup_ports(events))
        local second_view = context.module.UserPromptService.new(
            state, cleanup_ports(events))
        local first = service:start(request(context, 'first'), 1)
        local before = context.identity.get_process_allocator():snapshot()

        assert_category(function()
            second_view:start(request(context, 'second'), 1)
        end, 'SERVICE_BUSY')
        local after = context.identity.get_process_allocator():snapshot()
        assert.same(before, after)
        assert.same({}, events)
        assert.is_true(service:is_active(first, 'first', 1))
        local diagnostics = service:get_diagnostics()
        assert.equals('first', diagnostics.active_namespace)
        assert.equals(1, diagnostics.admitted_count)
        assert.equals(1, diagnostics.busy_rejection_count)
        assert.is_nil(diagnostics.request)
        assert.is_nil(diagnostics.on_select)
        assert.is_nil(diagnostics.on_cancel)
    end)

    it('retains copied request text callbacks and ownership until termination',
            function()
        local context = load_context()
        local source = {
            title='Original title',
            message='Original\nmessage',
            on_select=function() end,
            on_cancel=function() end,
        }
        local snapshot = context.value.MapLocationPromptRequest.new(
            'owner', source)
        local observed
        local cleanup = cleanup_ports({}, function(name)
            if name == 'input' then
                observed = {
                    namespace=snapshot.namespace,
                    title=snapshot.title,
                    message=snapshot.message,
                    on_select=snapshot.on_select,
                    on_cancel=snapshot.on_cancel,
                }
            end
        end)
        local service = context.module.UserPromptService.new(
            context.module.new_state(7), cleanup)
        service:start(snapshot, 1)

        source.title = 'Changed title'
        source.message = 'Changed message'
        source.on_select = function() error('replacement') end
        source.on_cancel = nil
        assert.equals('owner', service:get_diagnostics().active_namespace)
        assert.is_true(service:cancel_active(
            context.module.UserPromptTerminalCause.ESCAPE))
        assert.equals('owner', observed.namespace)
        assert.equals('Original title', observed.title)
        assert.equals('Original\nmessage', observed.message)
        assert.is_not_equal(source.on_select, observed.on_select)
        assert.is_function(observed.on_cancel)
    end)

    it('clears authoritative state before ordered cleanup and callback',
            function()
        local context = load_context()
        local events = {}
        local service
        local cleanup = cleanup_ports(events, function(name)
            local diagnostics = service:get_diagnostics()
            assert.is_false(diagnostics.active, name)
            assert.equals(context.module.UserPromptState.TERMINATING,
                diagnostics.state, name)
        end)
        local callback_position
        service = context.module.UserPromptService.new(
            context.module.new_state(7), cleanup)
        local handle = service:start(request(context, 'owner', function(pos)
            table.insert(events, 'select')
            assert.equals(context.module.UserPromptState.IDLE,
                service:get_diagnostics().state)
            callback_position = pos
            pos.x = 99
        end, function()
            table.insert(events, 'cancel')
        end), 1)
        local sampled = {x=1, y=2, z=3}

        assert.is_true(service:complete(sampled))
        assert.same({'input', 'render', 'tooltip_suppression', 'indicator',
            'invalidation', 'select'}, events)
        assert.same({x=1, y=2, z=3}, sampled)
        assert.equals(99, callback_position.x)
        assert.is_false(service:is_active(handle, 'owner', 1))
        assert.is_false(service:complete({x=4, y=5, z=6}))
        local diagnostics = service:get_diagnostics()
        assert.equals(1, diagnostics.terminal_count)
        assert.equals(1, diagnostics.completion_count)
        assert.equals(0, diagnostics.cancellation_count)
        assert.equals(context.module.UserPromptTerminalCause.LEFT_RELEASE,
            diagnostics.last_terminal_cause)
        assert.equals('owner', diagnostics.last_terminal_identity.namespace)
    end)

    it('covers every terminal cause with mutually exclusive callbacks',
            function()
        local context = load_context()
        local causes = context.module.UserPromptTerminalCause
        for name, cause in pairs(causes) do
            local selected = 0
            local cancelled = 0
            local service = context.module.UserPromptService.new(
                context.module.new_state(7), cleanup_ports({}))
            local handle = service:start(request(context, 'owner', function()
                selected = selected + 1
            end, function()
                cancelled = cancelled + 1
            end), 1)

            local changed
            if cause == causes.LEFT_RELEASE then
                changed = service:complete(nil)
            elseif cause == causes.API_CANCEL then
                changed = service:cancel(handle, 'owner', 1)
            elseif cause == causes.NAMESPACE_CLEAR then
                changed = service:clear_namespace('owner', 1)
            else
                changed = service:cancel_active(cause)
            end
            assert.is_true(changed, name)
            assert.equals(cause,
                service:get_diagnostics().last_terminal_cause, name)
            assert.equals(cause == causes.LEFT_RELEASE and 1 or 0,
                selected, name)
            assert.equals(cause == causes.LEFT_RELEASE and 0 or 1,
                cancelled, name)
            assert.is_false(service:cancel_active(causes.ESCAPE), name)
        end
    end)

    it('contains cleanup and callback failures without skipping work',
            function()
        local context = load_context()
        local events = {}
        local cleanup = cleanup_ports(events, function(name)
            if name == 'render' or name == 'indicator' then
                error(name .. ' failed')
            end
        end)
        local service = context.module.UserPromptService.new(
            context.module.new_state(7), cleanup)
        service:start(request(context, 'owner', nil, function()
            table.insert(events, 'cancel')
            error('callback failed')
        end), 1)

        assert.is_true(service:cancel_active(
            context.module.UserPromptTerminalCause.INTERNAL_FAILURE))
        assert.same({'input', 'render', 'tooltip_suppression', 'indicator',
            'invalidation', 'cancel'}, events)
        local diagnostics = service:get_diagnostics()
        assert.is_false(diagnostics.active)
        assert.equals(context.module.UserPromptState.IDLE, diagnostics.state)
        assert.equals(2, diagnostics.cleanup_failure_count)
        assert.equals('render', diagnostics.last_cleanup_failures[1].port)
        assert.equals('indicator', diagnostics.last_cleanup_failures[2].port)
        assert.equals(1, diagnostics.callback_failure_count)
        assert.is_truthy(diagnostics.last_callback_error:find(
            'callback failed', 1, true))
    end)

    it('preserves malformed, stale, foreign, then terminal precedence',
            function()
        local context = load_context()
        local service = context.module.UserPromptService.new(
            context.module.new_state(7), cleanup_ports({}))
        local current = service:start(request(context, 'owner'), 1)
        local allocator = context.identity.get_process_allocator()
        local stale = context.identity.create_prompt_handle(
            allocator:allocate_identity(6,
                context.contracts.ServiceKind.USER_PROMPT, 1, 'owner'))
        local foreign_namespace = context.identity.create_prompt_handle(
            allocator:allocate_identity(7,
                context.contracts.ServiceKind.USER_PROMPT, 1, 'other'))
        local foreign_contract = context.identity.create_prompt_handle(
            allocator:allocate_identity(7,
                context.contracts.ServiceKind.USER_PROMPT, 2, 'owner'))
        local map_handle = context.identity.create_map_handle(
            allocator:allocate_identity(7,
                context.contracts.ServiceKind.TOOLTIP, 1, 'owner'))

        assert_category(function() service:is_active({}, 'owner', 1) end,
            'INVALID_ARGUMENT')
        assert_category(function()
            service:is_active(map_handle, 'owner', 1)
        end, 'INVALID_ARGUMENT')
        assert_category(function() service:is_active(stale, 'owner', 1) end,
            'STALE_HANDLE')
        assert_category(function()
            service:is_active(foreign_namespace, 'owner', 1)
        end, 'FOREIGN_HANDLE')
        assert_category(function()
            service:is_active(foreign_contract, 'owner', 1)
        end, 'FOREIGN_HANDLE')
        assert.is_true(service:cancel(current, 'owner', 1))
        assert.is_false(service:cancel(current, 'owner', 1))
        assert.is_false(service:is_active(current, 'owner', 1))
    end)

    it('retains active requests when handles are collected', function()
        local context = load_context()
        local selected = 0
        local service = context.module.UserPromptService.new(
            context.module.new_state(7), cleanup_ports({}))
        local handle = service:start(request(context, 'owner', function()
            selected = selected + 1
        end), 1)
        local weak = setmetatable({handle}, {__mode='v'})
        handle = nil
        collectgarbage('collect')
        collectgarbage('collect')

        assert.is_nil(weak[1])
        assert.is_true(service:get_diagnostics().active)
        assert.is_true(service:complete(nil))
        assert.equals(1, selected)
    end)

    it('isolates namespace cleanup and blocks same-namespace callback reentry',
            function()
        local context = load_context()
        local service
        service = context.module.UserPromptService.new(
            context.module.new_state(7), cleanup_ports({}))
        service:start(request(context, 'owner', nil, function()
            service:start(request(context, 'owner'), 1)
        end), 1)

        assert.is_false(service:clear_namespace('other', 1))
        assert.is_true(service:clear_namespace('owner', 1))
        local diagnostics = service:get_diagnostics()
        assert.is_false(diagnostics.active)
        assert.equals(1, diagnostics.callback_failure_count)
        assert.is_truthy(diagnostics.last_callback_error:find(
            '[SERVICE_BUSY]', 1, true))
    end)

    it('allows eligible callbacks to open one replacement without a queue',
            function()
        local context = load_context()
        local service
        local replacement
        service = context.module.UserPromptService.new(
            context.module.new_state(7), cleanup_ports({}))
        service:start(request(context, 'first', function()
            replacement = service:start(request(context, 'second'), 1)
        end), 1)

        assert.is_true(service:complete(nil))
        assert.is_true(service:is_active(replacement, 'second', 1))
        local diagnostics = service:get_diagnostics()
        assert.equals('second', diagnostics.active_namespace)
        assert.equals(2, diagnostics.admitted_count)
        assert.is_nil(diagnostics.queue)
    end)
end)
