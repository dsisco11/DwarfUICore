local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

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
        dwarfui={},
        pen={parse=function(value) return value end},
        gui={
            getDFViewscreen=function() return state.df_viewscreen end,
            getCurViewscreen=function() return state.cur_viewscreen end,
        },
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

    local _, extensions = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/widget_extensions.lua', {
            globals={DEFAULT_NIL=default_nil},
            require_modules={['gui.widgets']=widgets},
        })
    local _, text = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/text.lua')
    local _, class_helpers = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/class.lua')
    local _, pointer = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/pointer.lua', {
            globals={dfhack=process},
        })
    local _, service_module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/tooltip_service.lua', {
            globals={dfhack=process},
        })
    local function load_hook_generation()
        local _, result = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui/tooltip_render_hook.lua', {
                globals={dfhack=process},
                require_modules={['plugins.overlay']=overlay},
            })
        return result
    end
    local function load_tooltip_generation(hook)
        local _, result = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui/tooltip.lua', {
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
                    ['dwarfui/class']=class_helpers,
                    ['dwarfui/widget_extensions']=extensions,
                    ['dwarfui/pointer']=pointer,
                    ['dwarfui/text']=text,
                    ['dwarfui/tooltip_service']=service_module,
                    ['dwarfui/tooltip_render_hook']=hook,
                    ['dwarfui/tooltip_registration']={
                        register=function() end,
                        unregister=function() end,
                    },
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
        kind=target_widget and 'target' or 'miss',
        pointer_x=x,
        pointer_y=y,
        target=target_widget,
        local_x=0,
        local_y=0,
        root=root,
    }
end

describe('DwarfUI intent-driven tooltip presenter', function()
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

    it('reloads presenter and renderer while adopting one active trampoline',
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
        assert.is_not_equal(first_presenter, next_tooltip.presenter)
        assert.is_not_equal(first_renderer,
            next_tooltip.presenter._renderer)
        assert.is_equal(trampoline,
            env.overlay.render_viewscreen_widgets)
        assert.equals(first_generation + 1, diagnostics.generation)
        assert.equals(diagnostics.generation,
            diagnostics.overlay.generation)
        assert.is_true(diagnostics.overlay.outermost)

        env.overlay.render_viewscreen_widgets()
        assert.equals(1, first_presenter:get_diagnostics().render_count)
        assert.equals(1,
            next_tooltip.presenter:get_diagnostics().render_count)
        assert.equals(2,
            next_hook.manager:get_diagnostics().render_count)
    end)
end)
