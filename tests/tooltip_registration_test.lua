local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local REGISTRATION_PATH =
    'src/scripts_modinstalled/dwarfui/tooltip_registration.lua'

---Creates the minimal painter surface required by the tooltip renderer.
---@param state table
---@return table painter
local function painter(state)
    return {
        fill=function()
            state.fill_count = (state.fill_count or 0) + 1
        end,
    }
end

---Builds isolated DFHack collaborators for singleton-service probes.
---@param state? table
---@return table environment
local function load_environment(state)
    state = state or {}
    state.width = state.width or 40
    state.height = state.height or 20
    state.events = state.events or {}
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{visible=true, active=true}

    ---@class tests.SingletonTooltipZScreen
    local ZScreen = widget_harness.defclass(nil, widgets.Widget)
    ZScreen.ATTRS{
        defocusable=true,
        initial_pause=false,
        pass_mouse_clicks=true,
        pass_movement_keys=false,
    }

    ---Shows and lays out this controlled screen.
    ---@return table self
    function ZScreen:show()
        self.shown = true
        self:updateLayout(widget_harness.rect(
            0, 0, state.width, state.height))
        state.current_screen = self
        table.insert(state.events, 'show')
        return self
    end

    ---Returns whether this controlled screen is active.
    ---@return boolean
    function ZScreen:isActive()
        return self.shown == true
    end

    ---Returns whether this screen currently owns z-order focus.
    ---@return boolean
    function ZScreen:hasFocus()
        return state.current_screen == self
    end

    ---Renders the simulated parent stack.
    function ZScreen:renderParent()
        table.insert(state.events, 'parent-render')
    end

    ---Forwards input into the simulated parent screen.
    ---@param keys table
    function ZScreen:sendInputToParent(keys)
        state.forwarded_keys = keys
    end

    ---Advances the simulated parent screen logic.
    function ZScreen:onIdle()
        state.parent_idle_count = (state.parent_idle_count or 0) + 1
    end

    ---Raises this screen over a newly opened child screen.
    ---@return table self
    function ZScreen:raise()
        state.raise_count = (state.raise_count or 0) + 1
        state.current_screen = self
        return self
    end

    ---Dismisses and notifies this controlled screen.
    function ZScreen:dismiss()
        if not self.shown then return end
        self.shown = false
        table.insert(state.events, 'dismiss')
        if self.onDismiss then self:onDismiss() end
    end

    ---@class tests.SingletonTooltipOverlay
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    local overlay_state = {config={}, db={}}
    local overlay = {
        OverlayWidget=OverlayWidget,
        get_state=function() return overlay_state end,
        isOverlayEnabled=function(name)
            local config = overlay_state.config[name]
            return config and config.enabled or false
        end,
        normalize_list=function(value)
            return type(value) == 'table' and value or {value}
        end,
        simplify_viewscreen_name=function(value)
            return value
        end,
    }

    local dfhack = {
        dwarfui={},
        gui={
            getDFViewscreen=function() return {focus=state.focus or 'dwarfmode'} end,
            matchFocusString=function(focus, viewscreen)
                return focus == viewscreen.focus
            end,
        },
        pen={parse=function(value) return value end},
        timeout=function(_, _, callback)
            state.timeout_count = (state.timeout_count or 0) + 1
            callback()
        end,
        screen={
            getMousePos=function() return state.mouse_x, state.mouse_y end,
            getWindowSize=function() return state.width, state.height end,
        },
    }
    local gui = {
        ZScreen=ZScreen,
        FRAME_INTERIOR='interior',
        Painter={new=function() return painter(state) end},
        paint_frame=function() end,
    }
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
    local loader_options = {
        globals={defclass=widget_harness.defclass, dfhack=dfhack},
        require_modules={gui=gui, ['plugins.overlay']=overlay},
        reqscript={
            ['dwarfui/pointer']=pointer,
            ['dwarfui/tooltip']=tooltip,
        },
    }

    ---Loads a fresh module generation against the shared process state.
    ---@return table registration
    local function load_registration()
        local _, registration = module_loader.load(
            repo_root, REGISTRATION_PATH, loader_options)
        return registration
    end

    return {
        dfhack=dfhack,
        load_registration=load_registration,
        overlay=overlay,
        OverlayWidget=OverlayWidget,
        tooltip=tooltip,
        state=state,
        widgets=widgets,
    }
end

---Lays out a root against the controlled screen rectangle.
---@param root table
---@param state table
local function layout(root, state)
    root:updateLayout(widget_harness.rect(
        0, 0, state.width, state.height))
end

---Creates a tooltip-bearing label.
---@param widgets table
---@param frame table
---@param text string
---@return table target
local function target(widgets, frame, text)
    return widgets.Label{frame=frame, tooltip=text}
end

describe('singleton tooltip registration', function()
    it('uses one screen renderer for every registered control', function()
        local env = load_environment{mouse_x=2, mouse_y=2}
        local registration = env.load_registration()
        local first = target(env.widgets,
            {l=1, t=1, w=6, h=3}, 'First tooltip')
        local second = target(env.widgets,
            {l=10, t=1, w=6, h=3}, 'Second tooltip')
        local root = env.widgets.Panel{subviews={first, second}}
        layout(root, env.state)

        assert.is_true(registration.register(first))
        assert.is_true(registration.register(second))
        assert.is_false(registration.register(first))
        local diagnostics = registration.get_diagnostics()
        assert.equals(2, diagnostics.registration_count)
        assert.equals(1, diagnostics.renderer_count)

        diagnostics.screen:onRender()
        assert.is.equal(first, registration.get_diagnostics().target)
        assert.equals('First tooltip', diagnostics.screen.renderer.tooltip_text)
        assert.same({'show', 'parent-render'}, env.state.events)

        env.state.mouse_x = 11
        diagnostics.screen:onRender()
        assert.is.equal(second, registration.get_diagnostics().target)
        assert.equals('Second tooltip', diagnostics.screen.renderer.tooltip_text)
        assert.equals(1, registration.get_diagnostics().renderer_count)
    end)

    it('uses native traversal within a root and registration order across roots', function()
        local env = load_environment{mouse_x=2, mouse_y=2}
        local registration = env.load_registration()
        local behind = target(env.widgets,
            {l=1, t=1, w=8, h=4}, 'Behind')
        local front = target(env.widgets,
            {l=1, t=1, w=8, h=4}, 'Front')
        local other = target(env.widgets,
            {l=1, t=1, w=8, h=4}, 'Other root')
        local first_root = env.widgets.Panel{subviews={behind, front}}
        local second_root = env.widgets.Panel{subviews={other}}
        layout(first_root, env.state)
        layout(second_root, env.state)

        registration.register(front)
        registration.register(behind)
        local screen = registration.get_diagnostics().screen
        screen:onRender()
        assert.is.equal(front, registration.get_diagnostics().target)

        registration.register(other)
        screen:onRender()
        assert.is.equal(other, registration.get_diagnostics().target)
        assert.equals('Other root', screen.renderer.tooltip_text)
    end)

    it('excludes registered controls below the current native screen', function()
        local env = load_environment{mouse_x=2, mouse_y=2}
        local registration = env.load_registration()
        local current = target(env.widgets,
            {l=1, t=1, w=6, h=3}, 'Current screen')
        local covered = target(env.widgets,
            {l=1, t=1, w=6, h=3}, 'Covered screen')
        local current_root = env.widgets.Panel{subviews={current}}
        local covered_root = env.widgets.Panel{subviews={covered}}
        current_root._native = {name='current'}
        covered_root._native = {name='covered'}
        layout(current_root, env.state)
        layout(covered_root, env.state)
        registration.register(current)
        registration.register(covered)
        local screen = registration.get_diagnostics().screen
        screen._native = {parent=current_root._native}

        screen:onRender()

        assert.is.equal(current, registration.get_diagnostics().target)
        assert.equals('Current screen', screen.renderer.tooltip_text)
    end)

    it('honors modal blocking in the registered control root', function()
        local env = load_environment{mouse_x=3, mouse_y=3}
        local registration = env.load_registration()
        local behind = target(env.widgets,
            {l=0, t=0, w=20, h=10}, 'Behind modal')
        local modal = env.widgets.Window{
            frame={l=2, t=2, w=8, h=5},
            frame_inset=1,
        }
        local root = env.widgets.Panel{subviews={behind, modal}}
        layout(root, env.state)
        registration.register(behind)
        local screen = registration.get_diagnostics().screen

        screen:onRender()
        assert.is_nil(registration.get_diagnostics().target)
        assert.is_false(screen.renderer.visible)

        env.state.mouse_x, env.state.mouse_y = 15, 8
        screen:onRender()
        assert.is.equal(behind, registration.get_diagnostics().target)
    end)

    it('follows attachment and reparenting without changing registration', function()
        local env = load_environment{mouse_x=2, mouse_y=2}
        local registration = env.load_registration()
        local child = target(env.widgets,
            {l=1, t=1, w=6, h=3}, 'Reparented')
        assert.is_true(registration.register(child))
        local screen = registration.get_diagnostics().screen

        screen:onRender()
        assert.is_nil(registration.get_diagnostics().target)

        local first_root = env.widgets.Panel{subviews={child}}
        layout(first_root, env.state)
        screen:onRender()
        assert.is.equal(child, registration.get_diagnostics().target)

        first_root.subviews = {}
        local second_root = env.widgets.Panel{}
        second_root:addviews{child}
        layout(second_root, env.state)
        screen:onRender()
        assert.is.equal(child, registration.get_diagnostics().target)

        second_root.subviews = {}
        screen:onRender()
        assert.is_nil(registration.get_diagnostics().target)
        assert.is_false(screen.renderer.visible)
    end)

    it('skips hidden ancestors and clears dynamic pointer ownership', function()
        local env = load_environment{mouse_x=2, mouse_y=2}
        local registration = env.load_registration()
        local leave_count = 0
        local child = target(env.widgets,
            {l=1, t=1, w=6, h=3}, 'Visible')
        child.on_pointer_leave = function()
            leave_count = leave_count + 1
        end
        local parent = env.widgets.Panel{subviews={child}}
        local root = env.widgets.Panel{subviews={parent}}
        layout(root, env.state)
        registration.register(child)
        local screen = registration.get_diagnostics().screen
        screen:onRender()
        assert.is.equal(child, registration.get_diagnostics().target)

        parent.visible = false
        screen:onRender()
        assert.is_nil(registration.get_diagnostics().target)
        assert.equals(1, leave_count)
        assert.is_false(screen.renderer.visible)
    end)

    it('escapes an independently clipped root through screen layout', function()
        local env = load_environment{
            mouse_x=12,
            mouse_y=6,
            width=50,
            height=20,
        }
        local registration = env.load_registration()
        local child = target(env.widgets,
            {l=1, t=1, w=4, h=1},
            'A long singleton tooltip that extends beyond the overlay panel.')
        local clipped_root = env.widgets.Panel{
            frame={l=10, t=5, w=7, h=4},
            subviews={child},
        }
        layout(clipped_root, env.state)
        registration.register(child)
        local screen = registration.get_diagnostics().screen

        screen:onRender()

        assert.is_true(screen.renderer.visible)
        assert.is.equal(screen.frame_parent_rect,
            screen.renderer.frame_parent_rect)
        assert.is_true(screen.renderer.frame.l +
            screen.renderer.frame.w - 1 > clipped_root.frame_body.clip_x2)
    end)

    it('excludes disabled and replaced overlay roots', function()
        local env = load_environment{mouse_x=2, mouse_y=2}
        local registration = env.load_registration()
        local child = target(env.widgets,
            {l=1, t=1, w=5, h=2}, 'Overlay')
        local root = env.OverlayWidget{
            name='test-overlay',
            viewscreens='dwarfmode',
            subviews={child},
        }
        layout(root, env.state)
        local overlay_state = env.overlay.get_state()
        overlay_state.config[root.name] = {enabled=true}
        overlay_state.db[root.name] = {widget=root}
        registration.register(child)
        local screen = registration.get_diagnostics().screen

        screen:onRender()
        assert.is.equal(child, registration.get_diagnostics().target)

        overlay_state.config[root.name].enabled = false
        screen:onRender()
        assert.is_nil(registration.get_diagnostics().target)

        overlay_state.config[root.name].enabled = true
        overlay_state.db[root.name] = {widget=env.OverlayWidget{name=root.name}}
        screen:onRender()
        assert.is_nil(registration.get_diagnostics().target)

        overlay_state.db[root.name] = {widget=root}
        env.state.focus = 'title'
        screen:onRender()
        assert.is_nil(registration.get_diagnostics().target)
    end)

    it('forwards all input and raises itself over newly opened screens', function()
        local env = load_environment()
        local registration = env.load_registration()
        local child = target(env.widgets,
            {l=1, t=1, w=4, h=2}, 'Input')
        registration.register(child)
        local screen = registration.get_diagnostics().screen
        local keys = {LEAVESCREEN=true, _MOUSE_L=true, CUSTOM=true}

        assert.is_true(screen:onInput(keys))
        assert.is.equal(keys, env.state.forwarded_keys)
        assert.is_false(screen:isMouseOver())

        env.state.current_screen = {newer=true}
        screen:onIdle()
        assert.equals(1, env.state.parent_idle_count)
        assert.equals(1, env.state.raise_count)
        assert.is.equal(screen, env.state.current_screen)
    end)

    it('replaces the singleton screen on reload and rejects version conflicts', function()
        local env = load_environment()
        local first_module = env.load_registration()
        local child = target(env.widgets,
            {l=1, t=1, w=4, h=2}, 'Reload')
        first_module.register(child)
        local first_screen = first_module.get_diagnostics().screen

        local second_module = env.load_registration()
        local second_diagnostics = second_module.get_diagnostics()
        assert.equals(1, second_diagnostics.registration_count)
        assert.equals(1, second_diagnostics.renderer_count)
        assert.is_not.equal(first_screen, second_diagnostics.screen)
        assert.is_false(first_screen:isActive())
        assert.equals(1, second_module.API_VERSION)

        env.dfhack.dwarfui.tooltip_service.api_version = 999
        assert.has_error(function() env.load_registration() end,
            'Conflicting DwarfUI tooltip service versions: ' ..
            'process has 999, requested 1.')
    end)

    it('recreates an externally dismissed service while registrations remain', function()
        local env = load_environment()
        local registration = env.load_registration()
        local child = target(env.widgets,
            {l=1, t=1, w=4, h=2}, 'Persistent')
        registration.register(child)
        local first_screen = registration.get_diagnostics().screen

        first_screen:dismiss()

        local replacement = registration.get_diagnostics().screen
        assert.is_not.equal(first_screen, replacement)
        assert.is_true(replacement:isActive())
        assert.equals(1, env.state.timeout_count)
        assert.equals(1, registration.get_diagnostics().renderer_count)
    end)

    it('matches explicit-agent dynamic targeting and removal behavior', function()
        local explicit_env = load_environment{mouse_x=2, mouse_y=2}
        local explicit_target = target(explicit_env.widgets,
            {l=1, t=1, w=6, h=3}, nil)
        ---Updates explicit tooltip text from pointer-local coordinates.
        explicit_target.on_pointer_update = function(self, x, y)
            self.tooltip = ('Dynamic %d,%d'):format(x, y)
        end
        local explicit_root = explicit_env.widgets.Panel{
            subviews={explicit_target},
        }
        layout(explicit_root, explicit_env.state)
        local explicit_renderer = explicit_env.tooltip.TooltipRenderer{}
        local explicit_agent = explicit_env.tooltip.TooltipAgent.new(
            explicit_root, explicit_renderer)
        explicit_agent:update()
        local expected_text = explicit_renderer.tooltip_text
        explicit_root.subviews = {}
        explicit_agent:update()
        assert.is_false(explicit_renderer.visible)

        local automatic_env = load_environment{mouse_x=2, mouse_y=2}
        local registration = automatic_env.load_registration()
        local automatic_target = target(automatic_env.widgets,
            {l=1, t=1, w=6, h=3}, nil)
        ---Updates automatic tooltip text from pointer-local coordinates.
        automatic_target.on_pointer_update = function(self, x, y)
            self.tooltip = ('Dynamic %d,%d'):format(x, y)
        end
        local automatic_root = automatic_env.widgets.Panel{
            subviews={automatic_target},
        }
        layout(automatic_root, automatic_env.state)
        registration.register(automatic_target)
        local screen = registration.get_diagnostics().screen
        screen:onRender()
        assert.equals(expected_text, screen.renderer.tooltip_text)
        automatic_root.subviews = {}
        screen:onRender()
        assert.is_false(screen.renderer.visible)
    end)

    it('dismisses after explicit removal and weakly releases dead controls', function()
        local env = load_environment()
        local registration = env.load_registration()
        local first = target(env.widgets,
            {l=1, t=1, w=4, h=2}, 'First')
        local second = target(env.widgets,
            {l=6, t=1, w=4, h=2}, 'Second')
        registration.register(first)
        registration.register(second)
        local screen = registration.get_diagnostics().screen

        assert.is_true(registration.unregister(first))
        assert.is_false(registration.unregister(first))
        assert.is_true(screen:isActive())
        assert.is_true(registration.unregister(second))
        assert.is_false(screen:isActive())
        assert.equals(0, registration.get_diagnostics().renderer_count)

        local weak_widget = setmetatable({}, {__mode='v'})
        do
            local transient = target(env.widgets,
                {l=1, t=1, w=4, h=2}, 'Transient')
            weak_widget[1] = transient
            registration.register(transient)
        end
        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_nil(weak_widget[1])
        assert.equals(0, registration.get_diagnostics().registration_count)
        local transient_screen = registration.get_diagnostics().screen
        transient_screen:onRender()
        assert.is_false(transient_screen:isActive())
        assert.equals(0, registration.get_diagnostics().renderer_count)
    end)
end)
