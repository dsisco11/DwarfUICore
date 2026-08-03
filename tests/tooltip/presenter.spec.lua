local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')
local _, target_types = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/tooltip/target.lua')
local ObservationKind = target_types.TooltipPointerObservationKind
local _, immutable_enum = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
local _, immutable_proxy = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')
local _, contracts = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })
local _, namespaces = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')
local _, identities = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/identity.lua', {
        globals={dfhack={}},
        reqscript={
            ['dwarfuicore/service_provider/contracts']=contracts,
            ['dwarfuicore/service_provider/namespace']=namespaces,
            ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
        },
    })

local function load_environment()
    local state = {
        width=40,
        height=20,
        invalidations=0,
        mouse_samples=0,
        window_samples=0,
        frame_paints=0,
        predecessor_calls=0,
        painters={},
    }
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{visible=true, active=true}

    local Screen = widget_harness.defclass(nil, widgets.Panel)
    function Screen:onRender()
        self.predecessor_calls = (self.predecessor_calls or 0) + 1
    end
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    local overlay = {
        OverlayWidget=OverlayWidget,
        render_viewscreen_widgets=function()
            state.predecessor_calls = state.predecessor_calls + 1
        end,
    }
    local gui = {
        Screen=Screen,
        ZScreen=widget_harness.defclass(nil, Screen),
        FRAME_INTERIOR='interior',
        paint_frame=function()
            state.frame_paints = state.frame_paints + 1
        end,
        Painter={new=function()
            local painter =
                widget_harness.rect(0, 0, state.width, state.height)
            painter.fill = function(self, rect, pen)
                self.fill_count = (self.fill_count or 0) + 1
                self.last_rect = rect
                self.last_pen = pen
            end
            table.insert(state.painters, painter)
            return painter
        end},
    }
    local process = {
        dwarfuicore={},
        pen={parse=function(value) return value end},
        gui={
            getDFViewscreen=function() return state.df_viewscreen end,
            getCurViewscreen=function() return state.cur_viewscreen end,
            showAnnouncement=function() end,
        },
        printerr=function() end,
        screen={
            getMousePos=function()
                state.mouse_samples = state.mouse_samples + 1
                return nil, nil
            end,
            getWindowSize=function()
                state.window_samples = state.window_samples + 1
                return state.width, state.height
            end,
            invalidate=function()
                state.invalidations = state.invalidations + 1
            end,
        },
    }

    local _, text = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/text.lua')
    local _, class_helpers = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/class.lua')
    local _, immutable_enum = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local _, pointer = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/pointer.lua', {
            globals={dfhack=process},
            reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
        })
    local _, function_chain = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/utils/function_chain.lua')
    local _, extensions = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/widget_extensions.lua', {
            globals={
                DEFAULT_NIL=default_nil,
                COLOR_RED=4,
                dfhack=process,
            },
            require_modules={['gui.widgets']=widgets},
            reqscript={['dwarfuicore/pointer']=pointer},
        })
    local _, service_module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/tooltip/service.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/tooltip/target']=target_types,
                ['dwarfuicore/service_provider/identity']=identities,
            },
        })
    local function load_hook_generation()
        local _, result = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfuicore/tooltip/render_hook.lua', {
                globals={dfhack=process},
                require_modules={['plugins.overlay']=overlay},
                reqscript={
                    ['dwarfuicore/utils/function_chain']=function_chain,
                    ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                },
            })
        return result
    end
    local function load_tooltip_generation(hook)
        local _, renderer_module = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfuicore/tooltip/renderer.lua', {
                globals={
                    COLOR_BLACK='black',
                    COLOR_WHITE='white',
                    DEFAULT_NIL=default_nil,
                    defclass=widget_harness.defclass,
                    dfhack=process,
                },
                require_modules={
                    gui=gui,
                    ['gui.widgets']=widgets,
                    ['plugins.overlay']=overlay,
                },
                reqscript={
                    ['dwarfuicore/widget_extensions']=extensions,
                    ['dwarfuicore/pointer']=pointer,
                    ['dwarfuicore/text']=text,
                },
            })
        local _, presenter_module = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfuicore/tooltip/presenter.lua', {
                globals={dfhack=process},
                require_modules={gui=gui},
                reqscript={['dwarfuicore/class']=class_helpers},
            })
        local _, result = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfuicore/tooltip/runtime.lua', {
                globals={dfhack=process},
                require_modules={
                    gui=gui,
                    ['plugins.overlay']=overlay,
                },
                reqscript={
                    ['dwarfuicore/tooltip/presenter']=presenter_module,
                    ['dwarfuicore/tooltip/renderer']=renderer_module,
                    ['dwarfuicore/tooltip/service']=service_module,
                    ['dwarfuicore/tooltip/render_hook']=hook,
                },
            })
        return result
    end
    local hook_module = load_hook_generation()
    local tooltip = load_tooltip_generation(hook_module)
    return {
        state=state,
        process=process,
        service=service_module.service,
        target_adapter=target_types,
        hook=hook_module,
        tooltip=tooltip,
        overlay=overlay,
        OverlayWidget=OverlayWidget,
        Screen=Screen,
        ZScreen=gui.ZScreen,
        widgets=widgets,
        load_hook_generation=load_hook_generation,
        load_tooltip_generation=load_tooltip_generation,
    }
end

local function target(text)
    return {tooltip=text}
end

local function observation(sequence, target_widget, root, x, y)
    return {
        sequence=sequence,
        kind=target_widget and ObservationKind.TARGET or
            ObservationKind.MISS,
        pointer_x=x,
        pointer_y=y,
        target=target_widget,
        local_x=0,
        local_y=0,
        root=root,
    }
end

describe('DwarfUICore intent-driven tooltip presenter', function()
    it('renders a normalized map target through its owner-selected seam',
            function()
        local env = load_environment()
        local root = env.widgets.Panel{}
        root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.df_viewscreen = {widgets=root}
        local handle = {}
        local composite_identity = {namespace='plugin', local_identity=1}
        local registry = {
            contains_identity=function(_, candidate, candidate_identity)
                return candidate == handle and
                    candidate_identity == composite_identity
            end,
            get_tooltip=function(_, candidate)
                return candidate == handle and 'Map tooltip' or nil
            end,
        }
        local map_target = env.target_adapter.adapt_map_tile({
            kind=ObservationKind.TARGET,
            target=handle,
            identity=composite_identity,
            source_root=root,
        }, registry)

        env.service:accept_pointer_observation(
            observation(1, map_target, root, 3, 4))
        local source_identity = env.service:get_intent().source_identity
        assert.equals(composite_identity.namespace,
            source_identity.namespace)
        assert.equals(composite_identity.local_identity,
            source_identity.local_identity)
        env.overlay.render_viewscreen_widgets()

        local diagnostics = env.tooltip.presenter:get_diagnostics()
        assert.is_true(env.tooltip.presenter._renderer.visible)
        assert.equals('Map tooltip',
            env.tooltip.presenter._renderer.label.text)
        assert.equals(1, diagnostics.render_count)
        assert.equals(composite_identity.local_identity,
            diagnostics.current_source_identity.local_identity)
        assert.is_equal(root,
            env.service:get_intent().source_root)
    end)

    it('renders native and overlay-widget intents through one visual contract',
            function()
        local env = load_environment()
        local native_root = env.widgets.Panel{}
        native_root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.df_viewscreen = {widgets=native_root}
        local native_target = target('Shared tooltip')
        env.service:register(native_target)

        env.service:accept_pointer_observation(
            observation(1, native_target, native_root, 3, 4))
        local renderer = env.tooltip.presenter._renderer
        local renderer_identity = renderer
        env.overlay.render_viewscreen_widgets()
        local native_frame = renderer.frame
        assert.equals('Shared tooltip', renderer.label.text)
        local native_painter = env.state.painters[#env.state.painters]
        assert.equals(1, native_painter.fill_count)
        assert.same({
            x1=0, y1=0, x2=39, y2=19,
            clip_x1=0, clip_y1=0, clip_x2=39, clip_y2=19,
            width=40, height=20,
        }, {
            x1=native_painter.x1, y1=native_painter.y1,
            x2=native_painter.x2, y2=native_painter.y2,
            clip_x1=native_painter.clip_x1,
            clip_y1=native_painter.clip_y1,
            clip_x2=native_painter.clip_x2,
            clip_y2=native_painter.clip_y2,
            width=native_painter.width,
            height=native_painter.height,
        })

        local overlay_root = env.OverlayWidget{}
        overlay_root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        local overlay_target = target('Shared tooltip')
        env.service:register(overlay_target)
        env.service:accept_pointer_observation(
            observation(2, overlay_target, overlay_root, 3, 4))
        env.overlay.render_viewscreen_widgets()

        assert.is_equal(renderer_identity, env.tooltip.presenter._renderer)
        assert.same(native_frame, renderer.frame)
        assert.equals('Shared tooltip', renderer.label.text)
        assert.equals(2,
            env.tooltip.presenter:get_diagnostics().render_count)
        assert.equals(2,
            env.hook.manager:get_diagnostics().last_rendered_revision)

        local screen_native = {}
        local screen = env.ZScreen{_native=screen_native}
        screen:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.cur_viewscreen = screen_native
        local screen_target = target('Shared tooltip')
        env.service:register(screen_target)
        env.service:accept_pointer_observation(
            observation(3, screen_target, screen, 3, 4))
        screen:onRender()
        assert.is_equal(renderer_identity, env.tooltip.presenter._renderer)
        assert.same(native_frame, renderer.frame)
        assert.equals(3,
            env.tooltip.presenter:get_diagnostics().render_count)
        assert.equals(3, env.state.window_samples)
        assert.equals(0, env.state.mouse_samples)
    end)

    it('renders only through the exact current Lua screen owner',
            function()
        local env = load_environment()
        local native = {}
        local subviews = {}
        local screen = env.ZScreen{
            _native=native,
            focus_token='unchanged',
            subviews=subviews,
        }
        screen:updateLayout(widget_harness.rect(0, 0, 40, 20))
        local original_subviews = screen.subviews
        env.state.cur_viewscreen = native
        local screen_target = target('Screen tooltip')
        env.service:register(screen_target)

        env.service:accept_pointer_observation(
            observation(1, screen_target, screen, 5, 6))
        local hook_diagnostics = env.hook.manager:get_diagnostics()
        assert.equals(env.hook.TooltipRenderTransport.SCREEN,
            hook_diagnostics.selected_transport)
        assert.is_equal(screen, hook_diagnostics.selected_owner)

        local overlay_renders =
            env.tooltip.presenter:get_diagnostics().render_count
        env.overlay.render_viewscreen_widgets()
        assert.equals(overlay_renders,
            env.tooltip.presenter:get_diagnostics().render_count)
        screen:onRender()
        assert.equals('Screen tooltip',
            env.tooltip.presenter._renderer.label.text)
        assert.equals(1,
            env.tooltip.presenter:get_diagnostics().render_count)
        assert.equals('unchanged', screen.focus_token)
        assert.is_equal(original_subviews, screen.subviews)
        assert.is_equal(native, screen._native)

        env.state.cur_viewscreen = {}
        screen:onRender()
        local diagnostics = env.tooltip.presenter:get_diagnostics()
        assert.equals(1, diagnostics.render_count)
        assert.equals('screen-not-current', diagnostics.surface_reason)

        local second_native = {}
        local second = env.Screen{_native=second_native}
        second:updateLayout(widget_harness.rect(0, 0, 40, 20))
        local second_target = target('Second screen')
        env.service:register(second_target)
        env.state.cur_viewscreen = second_native
        env.service:accept_pointer_observation(
            observation(2, second_target, second, 5, 6))
        screen:onRender()
        assert.equals(1,
            env.tooltip.presenter:get_diagnostics().render_count)
        second:onRender()
        assert.equals(2,
            env.tooltip.presenter:get_diagnostics().render_count)
    end)

    it('resolves the current overlay class when class exports change',
            function()
        local env = load_environment()
        local ReplacementOverlay =
            widget_harness.defclass(nil, env.widgets.Panel)
        env.overlay.OverlayWidget = ReplacementOverlay
        local root = ReplacementOverlay{}
        root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        local widget = target('Replacement overlay')
        env.service:register(widget)

        env.service:accept_pointer_observation(
            observation(1, widget, root, 2, 2))
        env.overlay.render_viewscreen_widgets()

        local diagnostics = env.tooltip.presenter:get_diagnostics()
        assert.is_true(diagnostics.supported_surface)
        assert.equals('overlay-widget', diagnostics.surface_reason)
        assert.equals(1, diagnostics.render_count)
    end)

    it('clears selection and painting on the requested redraw', function()
        local env = load_environment()
        local root = env.widgets.Panel{}
        root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.df_viewscreen = {widgets=root}
        local widget = target('Transient')
        env.service:register(widget)
        env.service:accept_pointer_observation(
            observation(1, widget, root, 2, 2))
        env.overlay.render_viewscreen_widgets()
        assert.is_true(env.tooltip.presenter._renderer.visible)
        local renders =
            env.tooltip.presenter:get_diagnostics().render_count

        env.service:accept_pointer_observation(
            observation(2, nil, nil, nil, nil))
        assert.is_false(env.tooltip.presenter._renderer.visible)
        assert.is_nil(
            env.hook.manager:get_diagnostics().selected_transport)
        assert.equals(2, env.state.invalidations)
        env.overlay.render_viewscreen_widgets()
        assert.equals(renders,
            env.tooltip.presenter:get_diagnostics().render_count)
        assert.equals('inactive-intent',
            env.tooltip.presenter:get_diagnostics().surface_reason)
    end)

    it('rejects unsupported roots without changing service hover state',
            function()
        local env = load_environment()
        local events = {}
        local widget = target('Unsupported')
        widget.on_pointer_enter =
            function() table.insert(events, 'enter') end
        widget.on_pointer_update =
            function() table.insert(events, 'update') end
        widget.on_pointer_leave =
            function() table.insert(events, 'leave') end
        env.service:register(widget)

        local unsupported_root = env.widgets.Panel{}
        unsupported_root:updateLayout(
            widget_harness.rect(0, 0, 40, 20))
        env.state.df_viewscreen = {}
        env.service:accept_pointer_observation(
            observation(1, widget, unsupported_root, 2, 2))
        local diagnostics = env.tooltip.presenter:get_diagnostics()
        assert.is_false(diagnostics.supported_surface)
        assert.equals('unsupported-root', diagnostics.surface_reason)
        assert.is_nil(diagnostics.selected_transport)
        assert.is_equal(widget,
            env.service:get_diagnostics().target)
        assert.same({'enter', 'update'}, events)
        env.overlay.render_viewscreen_widgets()
        assert.equals(0,
            env.tooltip.presenter:get_diagnostics().render_count)
    end)

    it('relayouts only for a new revision or changed screen dimensions',
            function()
        local env = load_environment()
        local root = env.widgets.Panel{}
        root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.df_viewscreen = {widgets=root}
        local widget = target('Resize')
        env.service:register(widget)
        env.service:accept_pointer_observation(
            observation(1, widget, root, 38, 18))

        local renderer = env.tooltip.presenter._renderer
        env.overlay.render_viewscreen_widgets()
        local first_layout_count = renderer.layout_update_count
        env.overlay.render_viewscreen_widgets()
        assert.equals(first_layout_count, renderer.layout_update_count)

        env.state.width = 30
        env.state.height = 15
        env.overlay.render_viewscreen_widgets()
        assert.equals(first_layout_count + 1,
            renderer.layout_update_count)
        local diagnostics = env.tooltip.presenter:get_diagnostics()
        assert.equals(1, diagnostics.current_intent_revision)
        assert.equals(1, diagnostics.last_rendered_revision)
        assert.equals(30, diagnostics.last_screen_width)
        assert.equals(15, diagnostics.last_screen_height)
        assert.equals(3, diagnostics.render_count)
    end)

    it('reads intent from the service instead of caching a second copy',
            function()
        local env = load_environment()
        local presenter = env.tooltip.presenter

        assert.is_nil(rawget(presenter, 'intent'))
        assert.is_nil(rawget(presenter, '_intent'))
        assert.is_nil(rawget(presenter, 'source_root'))
        assert.is_true(presenter:get_diagnostics().active)
        assert.equals('inactive-intent',
            presenter:get_diagnostics().surface_reason)
        assert.is_false(presenter:start())
    end)

    it('can hide presentation without clearing the selected tooltip intent',
            function()
        local env = load_environment()
        local root = env.widgets.Panel{}
        root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.df_viewscreen = {widgets=root}
        local widget = target('Retained tooltip')
        env.service:register(widget)
        env.service:accept_pointer_observation(
            observation(1, widget, root, 2, 2))
        env.overlay.render_viewscreen_widgets()

        local intent = env.service:get_intent()
        local selected_owner =
            env.hook.manager:get_diagnostics().selected_owner
        env.tooltip.presenter._renderer:set_tooltip(nil, nil, nil, nil)

        assert.is_false(env.tooltip.presenter._renderer.visible)
        assert.is_equal(intent, env.service:get_intent())
        assert.is_equal(widget,
            env.service:get_diagnostics().target)
        assert.is_equal(selected_owner,
            env.hook.manager:get_diagnostics().selected_owner)

        env.service:accept_pointer_observation(
            observation(2, widget, root, 3, 2))
        env.overlay.render_viewscreen_widgets()
        assert.is_true(env.tooltip.presenter._renderer.visible)
        assert.equals('Retained tooltip',
            env.tooltip.presenter._renderer.label.text)
        assert.is_equal(widget,
            env.service:get_diagnostics().target)
    end)

    it('suppresses only ordinary tooltip painting for an authoritative intent',
            function()
        local env = load_environment()
        local root = env.widgets.Panel{}
        root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.df_viewscreen = {widgets=root}
        local widget = target('Retained tooltip')
        env.service:register(widget)
        env.service:accept_pointer_observation(
            observation(1, widget, root, 2, 2))
        env.overlay.render_viewscreen_widgets()

        local retained_intent = env.service:get_intent()
        local frame_paints = env.state.frame_paints
        local authoritative_renders = 0
        local prepared =
            env.tooltip.presenter:prepare_authoritative_intent(
                root, function(painter, transport, owner)
                    assert.is_not_nil(painter)
                    assert.equals(env.hook.TooltipRenderTransport.OVERLAY,
                        transport)
                    assert.is_equal(env.overlay, owner)
                    authoritative_renders = authoritative_renders + 1
                end)
        local diagnostics = env.tooltip.presenter:get_diagnostics()
        assert.is_true(diagnostics.authoritative_intent_prepared)
        assert.is_false(diagnostics.authoritative_intent_active)
        assert.is_false(diagnostics.tooltip_suppressed)
        assert.equals(env.hook.TooltipRenderTransport.OVERLAY,
            diagnostics.authoritative_transport)
        assert.is_equal(env.overlay, diagnostics.authoritative_owner)

        env.overlay.render_viewscreen_widgets()
        assert.equals(frame_paints + 1, env.state.frame_paints)
        assert.equals(0, authoritative_renders)
        assert.is_false(
            env.tooltip.presenter:activate_authoritative_intent({}))
        assert.is_true(
            env.tooltip.presenter:activate_authoritative_intent(prepared))
        env.overlay.render_viewscreen_widgets()
        assert.equals(1, authoritative_renders)
        assert.equals(frame_paints + 1, env.state.frame_paints)
        assert.is_equal(retained_intent, env.service:get_intent())
        assert.is_equal(widget, env.service:get_diagnostics().target)
        diagnostics = env.tooltip.presenter:get_diagnostics()
        assert.is_true(diagnostics.authoritative_intent_active)
        assert.is_true(diagnostics.tooltip_suppressed)
        assert.equals(1, diagnostics.authoritative_render_count)

        assert.is_true(
            env.tooltip.presenter:release_authoritative_intent(prepared))
        assert.is_false(
            env.tooltip.presenter:release_authoritative_intent(prepared))
        env.overlay.render_viewscreen_widgets()
        assert.equals(frame_paints + 2, env.state.frame_paints)
        assert.equals('Retained tooltip',
            env.tooltip.presenter._renderer.label.text)
        assert.is_equal(retained_intent, env.service:get_intent())
        diagnostics = env.tooltip.presenter:get_diagnostics()
        assert.is_false(diagnostics.authoritative_intent_prepared)
        assert.is_false(diagnostics.authoritative_intent_active)
        assert.is_false(diagnostics.tooltip_suppressed)
    end)

    it('keeps an authoritative intent on its exact prepared screen root',
            function()
        local env = load_environment()
        local first_native = {}
        local first = env.ZScreen{_native=first_native}
        first:updateLayout(widget_harness.rect(0, 0, 40, 20))
        local second_native = {}
        local second = env.ZScreen{_native=second_native}
        second:updateLayout(widget_harness.rect(0, 0, 40, 20))
        local second_target = target('Second tooltip')
        env.service:register(second_target)
        env.state.cur_viewscreen = second_native
        env.service:accept_pointer_observation(
            observation(1, second_target, second, 3, 4))

        local authoritative_renders = 0
        local prepared =
            env.tooltip.presenter:prepare_authoritative_intent(
                first, function(_, transport, owner)
                    assert.equals(env.hook.TooltipRenderTransport.SCREEN,
                        transport)
                    assert.is_equal(first, owner)
                    authoritative_renders = authoritative_renders + 1
                end)
        local selected = env.hook.manager:get_diagnostics()
        assert.is_equal(second, selected.selected_owner)
        assert.is_true(
            env.tooltip.presenter:activate_authoritative_intent(prepared))
        selected = env.hook.manager:get_diagnostics()
        assert.is_equal(first, selected.selected_owner)

        env.service:accept_pointer_observation(
            observation(2, second_target, second, 4, 5))
        assert.is_equal(first,
            env.hook.manager:get_diagnostics().selected_owner)
        env.state.cur_viewscreen = first_native
        second:onRender()
        env.overlay.render_viewscreen_widgets()
        assert.equals(0, authoritative_renders)
        first:onRender()
        assert.equals(1, authoritative_renders)

        assert.is_true(
            env.tooltip.presenter:release_authoritative_intent(prepared))
        assert.is_equal(second,
            env.hook.manager:get_diagnostics().selected_owner)
        env.state.cur_viewscreen = second_native
        second:onRender()
        assert.equals('Second tooltip',
            env.tooltip.presenter._renderer.label.text)
        assert.equals(1, authoritative_renders)
    end)

    it('rolls back preparation and retires stale intent across Core reload',
            function()
        local env = load_environment()
        local invalid_root = env.widgets.Panel{}
        assert.has_error(function()
            env.tooltip.presenter:prepare_authoritative_intent(
                invalid_root, function() end)
        end, 'DwarfUICore authoritative presentation root is unsupported.')
        assert.has_error(function()
            env.tooltip.presenter:prepare_authoritative_intent(
                {}, 'invalid')
        end, 'DwarfUICore authoritative presentation intent requires present().')

        local native = {}
        local screen = env.ZScreen{_native=native}
        screen:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.cur_viewscreen = native
        local renders = 0
        local prepared =
            env.tooltip.presenter:prepare_authoritative_intent(
                screen, function() renders = renders + 1 end)
        local trampoline = screen.onRender
        assert.is_true(
            env.tooltip.presenter:activate_authoritative_intent(prepared))
        assert.is_equal(trampoline, screen.onRender)
        screen:onRender()
        assert.equals(1, renders)

        local retired = env.tooltip.presenter
        assert.is_true(retired:retire_for_reload())
        assert.is_true(prepared.released)
        assert.is_false(prepared.active)
        assert.is_false(retired:get_diagnostics().tooltip_suppressed)
        screen:onRender()
        assert.equals(1, renders)

        env.process.dwarfuicore.tooltip_runtime = nil
        local next_hook = env.load_hook_generation()
        local next_tooltip = env.load_tooltip_generation(next_hook)
        assert.is_not_equal(retired, next_tooltip.presenter)
        assert.is_equal(trampoline, screen.onRender)
        screen:onRender()
        assert.equals(1, renders)
        assert.is_false(
            next_tooltip.presenter:get_diagnostics().tooltip_suppressed)
        assert.is_false(
            next_tooltip.presenter:get_diagnostics().authoritative_intent_active)
    end)

    it('clears ownership before best-effort tooltip restoration', function()
        local env = load_environment()
        local root = env.widgets.Panel{}
        root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.df_viewscreen = {widgets=root}
        local widget = target('Recovery target')
        env.service:register(widget)
        env.service:accept_pointer_observation(
            observation(1, widget, root, 2, 2))
        local prepared =
            env.tooltip.presenter:prepare_authoritative_intent(
                root, function() end)
        assert.is_true(
            env.tooltip.presenter:activate_authoritative_intent(prepared))

        local trampoline = env.overlay.render_viewscreen_widgets
        env.overlay.render_viewscreen_widgets = nil
        assert.is_true(
            env.tooltip.presenter:release_authoritative_intent(prepared))
        local diagnostics = env.tooltip.presenter:get_diagnostics()
        assert.is_false(diagnostics.authoritative_intent_active)
        assert.is_false(diagnostics.tooltip_suppressed)
        assert.is_truthy(diagnostics.last_authoritative_cleanup_error)
        assert.is_nil(
            env.hook.manager:get_diagnostics().selected_owner)
        env.overlay.render_viewscreen_widgets = trampoline
    end)

    it('preserves presenter, renderer, and trampoline across module loads',
            function()
        local env = load_environment()
        local root = env.widgets.Panel{}
        root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.df_viewscreen = {widgets=root}
        local widget = target('Reloaded')
        env.service:register(widget)
        env.service:accept_pointer_observation(
            observation(1, widget, root, 2, 2))
        env.overlay.render_viewscreen_widgets()

        local first_presenter = env.tooltip.presenter
        local first_renderer = first_presenter._renderer
        local trampoline = env.overlay.render_viewscreen_widgets
        local first_generation =
            env.hook.manager:get_diagnostics().generation

        local next_hook = env.load_hook_generation()
        local next_tooltip = env.load_tooltip_generation(next_hook)
        local diagnostics = next_hook.manager:get_diagnostics()
        assert.is_equal(first_presenter, next_tooltip.presenter)
        assert.is_equal(first_renderer,
            next_tooltip.presenter._renderer)
        assert.is_equal(trampoline,
            env.overlay.render_viewscreen_widgets)
        assert.equals(first_generation, diagnostics.generation)
        assert.equals(diagnostics.generation,
            diagnostics.overlay.generation)
        assert.is_true(diagnostics.overlay.outermost)

        env.overlay.render_viewscreen_widgets()
        assert.equals(2, first_presenter:get_diagnostics().render_count)
        assert.equals(2,
            next_tooltip.presenter:get_diagnostics().render_count)
        assert.equals(2,
            next_hook.manager:get_diagnostics().render_count)
    end)
end)
