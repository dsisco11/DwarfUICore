local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads one runtime assembly over a controlled state-machine service.
---@param generation? integer
---@return table runtime_module
---@return table state
local function load_runtime(generation)
    local state = {generation=generation or 7, retire_causes={}}
    local service = {
        start=function() end,
        cancel=function() end,
        is_active=function() end,
        clear_namespace=function() end,
        get_diagnostics=function()
            return {runtime_generation=state.generation}
        end,
        cancel_active=function(_, cause)
            table.insert(state.retire_causes, cause)
            return true
        end,
        has_active_prompt=function() return false end,
        complete=function() return true end,
        configure_runtime=function(_, cleanup, activation)
            state.cleanup = cleanup
            state.activation = activation
        end,
    }
    local service_module = {
        service=service,
        UserPromptTerminalCause={CORE_RELOAD=10},
    }
    local context_service = {
        close=function() return false end,
        get_open_source_root=function() return nil end,
        set_opening_guard=function(_, guard) state.opening_guard = guard end,
    }
    local input_manager = {
        resolve_current_surface=function() return {} end,
        prepare_priority_consumer=function() return {} end,
        release_priority_consumer=function() return true end,
        activate_priority_consumer=function() return true end,
    }
    local presenter = {
        prepare_authoritative_intent=function() return {} end,
        release_authoritative_intent=function() return true end,
        activate_authoritative_intent=function() return true end,
        invalidate_authoritative_intent=function() return true end,
        release_authoritative_render=function() return true end,
        release_tooltip_suppression=function() return true end,
    }
    local renderer_class = setmetatable({}, {__call=function()
        return {set_prompt=function() end, render=function() end}
    end})
    local _, runtime_module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/runtime.lua', {
            globals={dfhack={
                isMapLoaded=function() return true end,
                gui={getMousePos=function() return nil end},
                screen={getMousePos=function() return nil end,
                    invalidate=function() end},
            }},
            reqscript={
                ['dwarfuicore/context_menu/service']={service=context_service},
                ['dwarfuicore/context_menu/screen']={},
                ['dwarfuicore/context_menu/input_hook']={manager=input_manager},
                ['dwarfuicore/user_prompt/indicator']={
                    NativeIndicatorAdapter={new=function()
                        return {prepare=function() end,
                            commit_prepared=function() return true end,
                            update=function() end,
                            release=function() return true end}
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
                ['dwarfuicore/user_prompt/service']=service_module,
                ['dwarfuicore/tooltip/runtime']={presenter=presenter},
            },
        })
    state.service = service
    return runtime_module, state
end

---Loads the concrete prompt service/consumer over observable runtime adapters.
---@return table context
local function load_integrated_runtime()
    local process = {dwarfuicore={service_provider_runtime={generation=7}}}
    local state = {
        events={},
        map_samples={},
        pointer_x=5,
        pointer_y=6,
        menu_open=true,
        menu_close_count=0,
        invalidations=0,
    }
    process.isMapLoaded = function() return true end
    process.gui = {getMousePos=function()
        state.map_sample_count = (state.map_sample_count or 0) + 1
        return table.remove(state.map_samples, 1)
    end}
    process.screen = {
        getMousePos=function() return state.pointer_x, state.pointer_y end,
        invalidate=function() state.invalidations = state.invalidations + 1 end,
    }

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
    local _, values = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/value.lua', {
            reqscript={
                ['dwarfuicore/service_provider/namespace']=namespace,
            },
        })
    local _, service_module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/service.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/identity']=identity,
                ['dwarfuicore/service_provider/namespace']=namespace,
                ['dwarfuicore/user_prompt/value']=values,
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
            },
        })
    local _, consumer_module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/input_consumer.lua')

    local root = {}
    local input_manager = {
        resolve_current_surface=function()
            assert.is_false(state.menu_open,
                'top menu screen must resolve through its source root')
            return root
        end,
        prepare_priority_consumer=function(_, surface, callbacks)
            assert.is_equal(root, surface)
            state.input_prepared = {callbacks=callbacks}
            return state.input_prepared
        end,
        activate_priority_consumer=function(_, prepared)
            state.input_prepared = nil
            state.input_active = prepared
            return true
        end,
        release_priority_consumer=function(_, prepared)
            local changed = state.input_prepared == prepared or
                state.input_active == prepared
            if state.input_prepared == prepared then state.input_prepared = nil end
            if state.input_active == prepared then state.input_active = nil end
            return changed
        end,
    }
    local presenter = {
        prepare_authoritative_intent=function(_, surface, present)
            assert.is_equal(root, surface)
            state.render_prepared = {present=present, active=false}
            return state.render_prepared
        end,
        release_authoritative_intent=function(_, prepared)
            if state.render_prepared == prepared then
                state.render_prepared = nil
                return true
            end
            return false
        end,
        activate_authoritative_intent=function(_, prepared)
            state.render_prepared = nil
            state.render_active = prepared
            state.tooltip_suppressed = true
            prepared.active = true
            return true
        end,
        invalidate_authoritative_intent=function(_, prepared)
            assert.is_equal(state.render_active, prepared)
            state.invalidations = state.invalidations + 1
            return true
        end,
        release_authoritative_render=function(_, prepared)
            if state.render_active ~= prepared then return false end
            state.render_active = nil
            prepared.active = false
            return true
        end,
        release_tooltip_suppression=function()
            state.tooltip_suppressed = false
            return true
        end,
    }
    local context_service = {
        get_open_source_root=function()
            return state.menu_open and root or nil
        end,
        close=function()
            state.menu_close_count = state.menu_close_count + 1
            local changed = state.menu_open
            state.menu_open = false
            return changed
        end,
        set_opening_guard=function(_, guard) state.opening_guard = guard end,
    }
    local indicator_class = {new=function()
        local indicator = {
            prepared=false, acquired=false, updates={}, released=false,
        }
        function indicator:prepare() self.prepared = true end
        function indicator:commit_prepared()
            self.acquired = self.prepared
            return self.acquired
        end
        function indicator:update(position)
            table.insert(self.updates, position == nil and '<nil>' or position)
        end
        function indicator:release()
            self.acquired = false
            self.released = true
            return true
        end
        state.indicator = indicator
        return indicator
    end}
    local renderer_class = setmetatable({}, {__call=function()
        local renderer = {render_count=0}
        function renderer:set_prompt(request, x, y, painter)
            self.request, self.x, self.y, self.painter = request, x, y, painter
        end
        function renderer:render()
            self.render_count = self.render_count + 1
        end
        state.renderer = renderer
        return renderer
    end})
    local _, runtime_module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/runtime.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/context_menu/service']={service=context_service},
                ['dwarfuicore/context_menu/screen']={},
                ['dwarfuicore/context_menu/input_hook']={manager=input_manager},
                ['dwarfuicore/user_prompt/indicator']={
                    NativeIndicatorAdapter=indicator_class,
                },
                ['dwarfuicore/user_prompt/input_consumer']=consumer_module,
                ['dwarfuicore/user_prompt/renderer']={
                    UserPromptRenderer=renderer_class,
                },
                ['dwarfuicore/user_prompt/service']=service_module,
                ['dwarfuicore/tooltip/runtime']={presenter=presenter},
            },
        })
    return {process=process, state=state, values=values,
        service=service_module.service, module=service_module,
        runtime=runtime_module}
end

describe('UserPrompt runtime assembly', function()
    it('publishes one generation-bound assembly over the process service',
            function()
        local runtime_module, state = load_runtime(7)
        local runtime = runtime_module.get(7)

        assert.equals(7, runtime.generation)
        assert.is_equal(state.service, runtime.service)
        assert.is_equal(runtime, runtime_module.get(7))
        assert.is_equal(runtime, runtime_module.validate(runtime, 7))
    end)

    it('rejects stale generations and malformed service contracts', function()
        local runtime_module, state = load_runtime(7)

        assert.has_error(function() runtime_module.get(8) end,
            'DwarfUICore UserPrompt runtime is incomplete or stale.')
        state.generation = 8
        assert.has_error(function()
            runtime_module.validate(runtime_module.runtime, 7)
        end, 'DwarfUICore UserPrompt runtime is incomplete or stale.')
        assert.has_error(function()
            runtime_module.validate({generation=8, service={}}, 8)
        end, 'DwarfUICore UserPrompt runtime is incomplete or stale.')
    end)

    it('retires the active prompt with the Core-reload cause', function()
        local runtime_module, state = load_runtime(7)

        assert.is_true(runtime_module.retire_for_reload())
        assert.same({10}, state.retire_causes)
    end)

    it('integrates active input, rendering, suppression, menu, and cleanup',
            function()
        local context = load_integrated_runtime()
        local selected = {}
        local request = context.values.MapLocationPromptRequest.new('owner', {
            title='Title', message='Message',
            on_select=function(position) table.insert(selected, position) end,
        })
        context.state.map_samples = {
            {x=10, y=11, z=12},
            {x=20, y=21, z=22},
        }

        local handle = context.service:start(request, 1)
        assert.is_false(context.state.menu_open)
        assert.equals(1, context.state.menu_close_count)
        assert.is_true(context.state.opening_guard())
        assert.is_not_nil(context.state.input_active)
        assert.is_not_nil(context.state.render_active)
        assert.is_true(context.state.tooltip_suppressed)
        assert.is_true(context.state.indicator.acquired)
        assert.equals(1, context.state.invalidations)
        assert.same({}, selected)

        local painter = {width=80, height=25}
        context.state.render_active.present(painter)
        assert.equals(1, context.state.map_sample_count)
        assert.same({x=10, y=11, z=12},
            context.state.indicator.updates[1])
        assert.is_equal(request, context.state.renderer.request)
        assert.same({5, 6}, {context.state.renderer.x,
            context.state.renderer.y})
        assert.is_equal(painter, context.state.renderer.painter)

        local callbacks = context.state.input_active.callbacks
        assert.is_true(callbacks.owns({_MOUSE_L_DOWN=true}))
        assert.is_true(callbacks.handle({_MOUSE_L_DOWN=true}))
        assert.equals(1, context.state.map_sample_count)
        assert.is_true(context.service:is_active(handle, 'owner', 1))
        assert.is_false(callbacks.owns({D_PAUSE=true}))

        assert.is_true(callbacks.handle({_MOUSE_L=true}))
        assert.equals(2, context.state.map_sample_count)
        assert.same({{x=20, y=21, z=22}}, selected)
        assert.is_false(context.service:is_active(handle, 'owner', 1))
        assert.is_false(context.state.opening_guard())
        assert.is_nil(context.state.input_active)
        assert.is_nil(context.state.render_active)
        assert.is_false(context.state.tooltip_suppressed)
        assert.is_true(context.state.indicator.released)
        assert.is_nil(context.state.renderer.request)
        assert.equals(2, context.state.invalidations)
    end)

    it('integrates composite cancellation and protected failure termination',
            function()
        local context = load_integrated_runtime()
        local cancelled = 0
        local request = context.values.MapLocationPromptRequest.new('owner', {
            title='Title', message='Message', on_select=function() end,
            on_cancel=function() cancelled = cancelled + 1 end,
        })
        context.state.map_samples = {{x=1, y=2, z=3}}
        context.service:start(request, 1)
        local callbacks = context.state.input_active.callbacks

        assert.is_true(callbacks.handle{
            _MOUSE_R=true, _MOUSE_L=true, _MOUSE_L_DOWN=true,
        })
        assert.equals(1, cancelled)
        assert.is_nil(context.state.map_sample_count)
        assert.is_false(context.service:has_active_prompt())

        local replacement = context.service:start(request, 1)
        callbacks = context.state.input_active.callbacks
        callbacks.on_failure('owned handler failed')
        assert.equals(2, cancelled)
        assert.is_false(context.service:is_active(replacement, 'owner', 1))
        assert.equals(context.module.UserPromptTerminalCause.INTERNAL_FAILURE,
            context.service:get_diagnostics().last_terminal_cause)
    end)

    it('clears concrete ownership on right-click and Escape cancellation',
            function()
        for _, example in ipairs{
                {keys={_MOUSE_R=true}, cause='RIGHT_RELEASE'},
                {keys={LEAVESCREEN=true}, cause='ESCAPE'},
            } do
            local context = load_integrated_runtime()
            local cancelled = 0
            local request = context.values.MapLocationPromptRequest.new(
                'owner', {
                    title='Title', message='Message',
                    on_select=function() end,
                    on_cancel=function() cancelled = cancelled + 1 end,
                })
            context.service:start(request, 1)

            assert.is_true(
                context.state.input_active.callbacks.handle(example.keys))
            assert.equals(1, cancelled)
            assert.is_false(context.service:has_active_prompt())
            assert.is_nil(context.state.input_active)
            assert.is_nil(context.state.render_active)
            assert.is_false(context.state.tooltip_suppressed)
            assert.is_true(context.state.indicator.released)
            assert.is_nil(context.state.renderer.request)
            assert.is_false(context.state.opening_guard())
            assert.equals(2, context.state.invalidations)
            assert.equals(context.module.UserPromptTerminalCause[example.cause],
                context.service:get_diagnostics().last_terminal_cause)
        end
    end)

    it('clears concrete presentation ownership on explicit API terminals',
            function()
        local context = load_integrated_runtime()
        local request = context.values.MapLocationPromptRequest.new('owner', {
            title='Title', message='Message', on_select=function() end,
        })

        local handle = context.service:start(request, 1)
        assert.is_true(context.service:cancel(handle, 'owner', 1))
        assert.is_nil(context.state.input_active)
        assert.is_nil(context.state.render_active)
        assert.is_false(context.state.tooltip_suppressed)
        assert.is_true(context.state.indicator.released)
        assert.is_false(context.state.opening_guard())

        context.state.indicator = nil
        context.service:start(request, 1)
        assert.is_true(context.service:clear_namespace('owner', 1))
        assert.is_nil(context.state.input_active)
        assert.is_nil(context.state.render_active)
        assert.is_false(context.state.tooltip_suppressed)
        assert.is_true(context.state.indicator.released)
        assert.is_false(context.state.opening_guard())
        assert.equals(4, context.state.invalidations)
    end)
end)
