local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local function screen_dc(kind)
    return {
        kind=kind or 'screen',
        fill=function(self)
            self.fill_count = (self.fill_count or 0) + 1
        end,
    }
end

local function load_environment(state)
    state.width = state.width or 40
    state.height = state.height or 20
    state.events = state.events or {}
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{visible=true, active=true}

    local ZScreen = widget_harness.defclass(nil, widgets.Widget)
    function ZScreen:onRender()
        self:render(self.screen_dc)
    end

    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    function OverlayWidget:onRenderFrame() end
    function OverlayWidget:onRenderBody() end
    function OverlayWidget:render(dc)
        self:onRenderFrame(dc, self.frame_rect)
        local clipped_dc = {
            kind='overlay-clipped',
            parent=dc,
            clip=self.frame_body,
            fill=dc.fill,
        }
        self:onRenderBody(clipped_dc)
        for _, child in ipairs(self.subviews or {}) do
            child:render(clipped_dc)
        end
    end

    local dfhack = {
        pen={parse=function(value) return value end},
        screen={
            getMousePos=function()
                state.mouse_samples = (state.mouse_samples or 0) + 1
                return state.mouse_x, state.mouse_y
            end,
            getWindowSize=function() return state.width, state.height end,
        },
    }
    local gui = {
        ZScreen=ZScreen,
        FRAME_INTERIOR='interior',
        paint_frame=function() end,
    }
    local overlay = {OverlayWidget=OverlayWidget}

    local _, extensions = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/widget_extensions.lua', {
            globals={DEFAULT_NIL=default_nil},
            require_modules={['gui.widgets']=widgets},
        })
    local _, text = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/text.lua')
    local _, pointer = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/pointer.lua', {
            globals={dfhack=dfhack},
        })
    local _, tooltip = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/tooltip.lua', {
            globals={
                COLOR_BLACK='black',
                COLOR_WHITE='white',
                DEFAULT_NIL=default_nil,
                defclass=widget_harness.defclass,
                dfhack=dfhack,
            },
            require_modules={gui=gui, ['gui.widgets']=widgets},
            reqscript={
                ['dwarfui/widget_extensions']=extensions,
                ['dwarfui/pointer']=pointer,
                ['dwarfui/text']=text,
            },
        })
    return {
        gui=gui,
        overlay=overlay,
        widgets=widgets,
        tooltip=tooltip,
    }
end

local function record_render(view, events, name)
    local base_render = view.render
    view.render = function(self, dc)
        table.insert(events, name)
        self.host_dc = dc
        return base_render(self, dc)
    end
    return view
end

local function define_hosts(environment)
    local gui = environment.gui
    local overlay = environment.overlay
    local tooltip = environment.tooltip

    local TooltipScreenHost =
        widget_harness.defclass(nil, gui.ZScreen)
    function TooltipScreenHost:init()
        self.tooltip_renderer = tooltip.TooltipRenderer{}
        self:addviews{self.content, self.tooltip_renderer}
        self.tooltip_agent = tooltip.TooltipAgent.new(
            self, self.tooltip_renderer)
        record_render(
            self.tooltip_renderer, self.events, 'screen-tooltip')
    end
    function TooltipScreenHost:onRender()
        table.insert(self.events, 'screen-agent')
        self.tooltip_agent:update()
        TooltipScreenHost.super.onRender(self)
    end

    local TooltipOverlayHost =
        widget_harness.defclass(nil, overlay.OverlayWidget)
    function TooltipOverlayHost:init()
        self.tooltip_renderer = tooltip.TooltipRenderer{}
        self:addviews{self.content}
        -- Keep the renderer outside the overlay's clipped subview pass.
        self.tooltip_renderer.parent_view = self
        self.tooltip_agent = tooltip.TooltipAgent.new(
            self, self.tooltip_renderer)
        record_render(
            self.tooltip_renderer, self.events, 'overlay-tooltip')
    end
    function TooltipOverlayHost:onRenderFrame(dc, rect)
        table.insert(self.events, 'overlay-agent')
        self.tooltip_agent:update()
        TooltipOverlayHost.super.onRenderFrame(self, dc, rect)
    end
    function TooltipOverlayHost:render(dc)
        TooltipOverlayHost.super.render(self, dc)
        if self.tooltip_renderer.visible then
            self.tooltip_renderer:render(dc)
        end
    end

    return TooltipScreenHost, TooltipOverlayHost
end

local function target(widgets, frame, tooltip, events, event_name)
    local result = widgets.Label{frame=frame, tooltip=tooltip}
    if events and event_name then
        record_render(result, events, event_name)
    end
    return result
end

local function layout(view, width, height)
    view:updateLayout(widget_harness.rect(0, 0, width, height))
end

describe('DwarfUI tooltip host integration', function()
    it('updates a ZScreen agent before rendering content and tooltip last', function()
        local state = {mouse_x=3, mouse_y=2, events={}}
        local env = load_environment(state)
        local ScreenHost = define_hosts(env)
        local content = target(env.widgets,
            {l=1, t=1, w=8, h=3}, 'Screen tooltip',
            state.events, 'screen-content')
        local host = ScreenHost{
            content=content,
            events=state.events,
            screen_dc=screen_dc(),
        }
        layout(host, state.width, state.height)

        host:onRender()

        assert.same({
            'screen-agent', 'screen-content', 'screen-tooltip',
        }, state.events)
        assert.equals('Screen tooltip', host.tooltip_renderer.label.text)
        assert.is.equal(content, host.tooltip_agent.pointer_context.target)
        assert.is.equal(host.screen_dc, host.tooltip_renderer.host_dc)
    end)

    it('renders an offset clipped overlay tooltip through the parent painter', function()
        local state = {mouse_x=12, mouse_y=6, events={}, width=40, height=20}
        local env = load_environment(state)
        local _, OverlayHost = define_hosts(env)
        local content = target(env.widgets,
            {l=1, t=1, w=5, h=1},
            'An overlay tooltip that extends beyond its narrow panel.',
            state.events, 'overlay-content')
        local host = OverlayHost{
            frame={l=10, t=5, w=8, h=4},
            content=content,
            events=state.events,
        }
        layout(host, state.width, state.height)
        local parent_dc = screen_dc('overlay-parent')

        host:render(parent_dc)

        assert.same({
            'overlay-agent', 'overlay-content', 'overlay-tooltip',
        }, state.events)
        assert.equals('overlay-clipped', content.host_dc.kind)
        assert.is.equal(parent_dc, host.tooltip_renderer.host_dc)
        assert.is_true(host.tooltip_renderer.frame.l +
            host.tooltip_renderer.frame.w - 1 > host.frame_body.clip_x2)
        assert.is.equal(host.frame_parent_rect,
            host.tooltip_renderer.frame_parent_rect)
    end)

    it('isolates a screen and two overlay instances', function()
        local state = {mouse_x=2, mouse_y=2, events={}}
        local env = load_environment(state)
        local ScreenHost, OverlayHost = define_hosts(env)
        local screen_content = target(
            env.widgets, {l=1, t=1, w=4, h=4}, 'Screen')
        local first_content = target(
            env.widgets, {l=1, t=1, w=4, h=4}, 'First overlay')
        local second_content = target(
            env.widgets, {l=1, t=1, w=4, h=4}, 'Second overlay')
        local screen = ScreenHost{
            content=screen_content,
            events={},
            screen_dc=screen_dc(),
        }
        local first = OverlayHost{
            frame={l=0, t=0, w=8, h=8},
            content=first_content,
            events={},
        }
        local second = OverlayHost{
            frame={l=0, t=0, w=8, h=8},
            content=second_content,
            events={},
        }
        layout(screen, state.width, state.height)
        layout(first, state.width, state.height)
        layout(second, state.width, state.height)

        screen:onRender()
        first:render(screen_dc())
        second:render(screen_dc())
        assert.equals('Screen', screen.tooltip_renderer.label.text)
        assert.equals('First overlay', first.tooltip_renderer.label.text)
        assert.equals('Second overlay', second.tooltip_renderer.label.text)
        assert.is.equal(screen_content, screen.tooltip_agent.pointer_context.target)
        assert.is.equal(first_content, first.tooltip_agent.pointer_context.target)
        assert.is.equal(second_content, second.tooltip_agent.pointer_context.target)

        first.subviews = {}
        first:render(screen_dc())
        assert.equals('', first.tooltip_renderer.label.text)
        assert.is_nil(first.tooltip_agent.pointer_context.target)
        assert.equals('Screen', screen.tooltip_renderer.label.text)
        assert.equals('Second overlay', second.tooltip_renderer.label.text)
        assert.is.equal(screen_content, screen.tooltip_agent.pointer_context.target)
        assert.is.equal(second_content, second.tooltip_agent.pointer_context.target)
    end)

    it('blocks underlying screen targets only inside nested window frames', function()
        local state = {mouse_x=6, mouse_y=6, events={}, width=20, height=20}
        local env = load_environment(state)
        local ScreenHost = define_hosts(env)
        local behind = target(env.widgets,
            {l=0, t=0, w=20, h=20}, 'Underlying target')
        local inner = env.widgets.Window{
            frame={l=2, t=2, w=4, h=4},
            frame_inset=1,
        }
        local outer = env.widgets.Window{
            frame={l=2, t=2, w=10, h=10},
            frame_inset=1,
            subviews={inner},
        }
        local content = env.widgets.Panel{
            frame={l=0, t=0, w=20, h=20},
            subviews={behind, outer},
        }
        local host = ScreenHost{
            content=content,
            events={},
            screen_dc=screen_dc(),
        }
        layout(host, state.width, state.height)

        local result = host.tooltip_agent:update()
        assert.equals('blocked', result.kind)
        assert.is.equal(inner, result.blocker)
        state.mouse_x, state.mouse_y = 3, 3
        result = host.tooltip_agent:update()
        assert.equals('blocked', result.kind)
        assert.is.equal(outer, result.blocker)
        state.mouse_x, state.mouse_y = 15, 15
        result = host.tooltip_agent:update()
        assert.equals('target', result.kind)
        assert.is.equal(behind, result.target)
        assert.equals('Underlying target', host.tooltip_renderer.label.text)
    end)

    it('clears dynamic row text over padding, separators, blanks, and removal', function()
        local state = {mouse_x=3, mouse_y=1, events={}, width=20, height=10}
        local env = load_environment(state)
        local ScreenHost = define_hosts(env)
        local rows = target(env.widgets,
            {l=1, t=1, w=10, h=6}, nil)
        rows.records = {[0]='First record', [2]='Second record'}
        rows.on_pointer_update = function(self, x, y)
            local record = x >= 1 and x <= 6 and self.records[y] or nil
            self.tooltip = record and ('Record: ' .. record) or nil
        end
        local host = ScreenHost{
            content=rows,
            events={},
            screen_dc=screen_dc(),
        }
        layout(host, state.width, state.height)

        host.tooltip_agent:update()
        assert.equals('Record: First record',
            host.tooltip_renderer.tooltip_text)
        state.mouse_x = 10 -- right-side padding
        host.tooltip_agent:update()
        assert.equals('', host.tooltip_renderer.label.text)
        state.mouse_x, state.mouse_y = 3, 2 -- separator row
        host.tooltip_agent:update()
        assert.equals('', host.tooltip_renderer.label.text)
        state.mouse_y = 4 -- blank row
        host.tooltip_agent:update()
        assert.equals('', host.tooltip_renderer.label.text)
        state.mouse_y = 3 -- second record row
        host.tooltip_agent:update()
        assert.equals('Record: Second record',
            host.tooltip_renderer.tooltip_text)
        rows.records[2] = nil
        host.tooltip_agent:update()
        assert.equals('', host.tooltip_renderer.label.text)
    end)

    it('keeps both explicit host recipes in the README', function()
        local file = assert(io.open(repo_root .. '/README.md', 'rb'))
        local source = file:read('*a')
        file:close()
        for _, expected in ipairs({
                'gui.ZScreen',
                'overlay.OverlayWidget',
                'tooltip.TooltipRenderer',
                'tooltip.TooltipAgent',
                'function TooltipScreen:onRender()',
                'function TooltipOverlay:onRenderFrame(dc, rect)',
                'function TooltipOverlay:render(dc)',
            }) do
            assert.is_truthy(source:find(expected, 1, true), expected)
        end
    end)
end)
