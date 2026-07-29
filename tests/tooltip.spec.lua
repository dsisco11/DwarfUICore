local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local extension_path =
    'src/scripts_modinstalled/dwarfui/widget_extensions.lua'
local text_path = 'src/scripts_modinstalled/dwarfui/text.lua'
local tooltip_path = 'src/scripts_modinstalled/dwarfui/tooltip.lua'

local function load_tooltip(state)
    state.width = state.width or 80
    state.height = state.height or 25
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{visible=true, active=true}

    local dfhack = {
        pen={parse=function(value)
            state.parsed_pens = state.parsed_pens or {}
            table.insert(state.parsed_pens, value)
            return value
        end},
        screen={
            getWindowSize=function()
                state.window_samples = (state.window_samples or 0) + 1
                return state.width, state.height
            end,
        },
    }
    local gui = {
        Screen={},
        FRAME_INTERIOR='interior',
        Painter={new=function()
            return widget_harness.rect(0, 0, state.width, state.height)
        end},
        paint_frame=function(_, rect, style)
            state.frame_paints = (state.frame_paints or 0) + 1
            state.painted_rect = rect
            state.painted_style = style
        end,
    }

    local _, extensions = module_loader.load(repo_root, extension_path, {
        globals={DEFAULT_NIL=default_nil},
        require_modules={['gui.widgets']=widgets},
    })
    local _, text = module_loader.load(repo_root, text_path)
    local registration = state.registration_service or {
        register=function() return true end,
        unregister=function() return true end,
    }
    local service = {
        intent=nil,
        revision=0,
        get_intent=function(self) return self.intent end,
        get_diagnostics=function(self)
            return {revision=self.revision}
        end,
        set_intent_observer=function(self, observer)
            self.observer = observer
        end,
    }
    local transport = {OVERLAY=1, SCREEN=2}
    local overlay = {OverlayWidget={}}
    local hook_manager = {
        generation=1,
        get_diagnostics=function(self)
            return {
                generation=self.generation,
                selected_transport=self.selected_transport,
                selected_owner=self.selected_owner,
            }
        end,
        set_presenter=function(self, presenter)
            self.presenter = presenter
        end,
        ensure_overlay=function(self)
            self.selected_transport = transport.OVERLAY
            self.selected_owner = overlay
        end,
        ensure_screen=function(self, owner)
            self.selected_transport = transport.SCREEN
            self.selected_owner = owner
        end,
        clear_selection=function(self)
            self.selected_transport = nil
            self.selected_owner = nil
        end,
        set_current_intent_revision=function(self, revision)
            self.current_intent_revision = revision
        end,
        shutdown=function() end,
    }
    local _, tooltip = module_loader.load(repo_root, tooltip_path, {
        globals={
            COLOR_BLACK='black',
            COLOR_WHITE='white',
            DEFAULT_NIL=default_nil,
            defclass=widget_harness.defclass,
            dfhack={
                pen=dfhack.pen,
                gui={
                    getDFViewscreen=function() return nil end,
                    getCurViewscreen=function() return nil end,
                },
                screen={
                    getWindowSize=dfhack.screen.getWindowSize,
                    invalidate=function() end,
                },
            },
        },
        require_modules={
            gui=gui,
            ['gui.widgets']=widgets,
            ['plugins.overlay']=overlay,
        },
        reqscript={
            ['dwarfui/widget_extensions']=extensions,
            ['dwarfui/tooltip_registration']=registration,
            ['dwarfui/tooltip_service']={service=service},
            ['dwarfui/tooltip_render_hook']={
                manager=hook_manager,
                TooltipRenderTransport=transport,
            },
            ['dwarfui/text']=text,
        },
    })
    return tooltip, widgets
end

describe('DwarfUI tooltip renderer', function()
    it('delegates stable registration through the tooltip facade', function()
        local state = {registration_service={}}
        state.registration_service.register = function(widget)
            state.registered = widget
            return true
        end
        state.registration_service.unregister = function(widget)
            state.unregistered = widget
            return true
        end
        local tooltip = load_tooltip(state)
        local widget = {}

        assert.is_true(tooltip.register(widget))
        assert.is.equal(widget, state.registered)
        assert.is_true(tooltip.unregister(widget))
        assert.is.equal(widget, state.unregistered)
    end)

    it('is a hidden plain Widget with the required pens and exclusion policy', function()
        local state = {}
        local tooltip, widgets = load_tooltip(state)
        local renderer = tooltip.TooltipRenderer{}

        assert.is.equal(widgets.Widget, tooltip.TooltipRenderer.super)
        assert.is_false(renderer.visible)
        assert.equals('none', renderer.pointer_policy)
        assert.equals('none', renderer.label.pointer_policy)
        assert.equals('interior', renderer.frame_style)
        assert.equals(1, renderer.frame_inset)
        assert.same({ch=32, fg='black', bg='black'},
            renderer.frame_background)
        assert.same({fg='white', bg='black'}, renderer.label.text_pen)
        assert.equals('', renderer.label.text)

        renderer:render({})
        assert.is_nil(renderer.render_count)
        assert.is_nil(state.frame_paints)
    end)

    it('displays and wraps current text immediately within available width', function()
        local state = {width=22, height=10}
        local tooltip = load_tooltip(state)
        local renderer = tooltip.TooltipRenderer{}
        local owner = {invalidate=function(self)
            self.invalidations = (self.invalidations or 0) + 1
        end}
        renderer.parent_view = owner
        local layout_parent = widget_harness.rect(0, 0, 22, 10)

        renderer:set_tooltip(
            'Difference from the attribute average.', 1, 1, layout_parent)

        assert.is_true(renderer.visible)
        assert.equals('Difference from the\nattribute average.',
            renderer.label.text)
        assert.same({l=1, t=2, w=21, h=4}, renderer.frame)
        assert.same({l=0, t=0, w=19, h=2}, renderer.label.frame)
        assert.equals(1, renderer.layout_update_count)
        assert.is.equal(layout_parent, renderer.frame_parent_rect)
        assert.equals(1, owner.invalidations)
    end)

    it('limits content wrapping to sixty cells on wide screens', function()
        local state = {width=100, height=20}
        local tooltip = load_tooltip(state)
        local renderer = tooltip.TooltipRenderer{}
        local words = {}
        for _ = 1, 7 do table.insert(words, '1234567890') end
        renderer:set_tooltip(
            table.concat(words, ' '), 1, 1,
            widget_harness.rect(0, 0, 100, 20))

        local lines = {}
        for line in renderer.label.text:gmatch('[^\n]+') do
            table.insert(lines, line)
        end
        assert.equals(2, #lines)
        assert.is_true(#lines[1] <= 60)
        assert.is_true(#lines[2] <= 60)
        assert.equals(56, renderer.frame.w)
    end)

    it('clamps placement against every screen edge', function()
        local state = {width=10, height=5}
        local tooltip = load_tooltip(state)
        local renderer = tooltip.TooltipRenderer{}
        local layout_parent = widget_harness.rect(0, 0, 10, 5)

        renderer:set_tooltip('Tip', 9, 4, layout_parent)
        assert.same({l=5, t=2, w=5, h=3}, renderer.frame)
        renderer:set_tooltip('Tip', -10, -10, layout_parent)
        assert.same({l=0, t=0, w=5, h=3}, renderer.frame)
    end)

    it('updates layout, renders its frame, and forwards the layout parent', function()
        local state = {width=20, height=10}
        local tooltip = load_tooltip(state)
        local renderer = tooltip.TooltipRenderer{}
        local layout_parent = widget_harness.rect(4, 3, 20, 10,
            {x1=5, y1=4, x2=18, y2=10})
        renderer:set_tooltip('Visible', 2, 2, layout_parent)
        local dc = {fill=function(self, rect, pen)
            self.fill_count = (self.fill_count or 0) + 1
            self.rect = rect
            self.pen = pen
        end}

        renderer:render(dc)

        assert.is.equal(layout_parent, renderer.frame_parent_rect)
        assert.equals(1, renderer.layout_update_count)
        assert.equals(1, renderer.render_count)
        assert.equals(1, renderer.label.render_count)
        assert.equals(1, dc.fill_count)
        assert.same(renderer.frame_background, dc.pen)
        assert.equals(1, state.frame_paints)
        assert.equals('interior', state.painted_style)
    end)

    it('invalidates on mutation and clears immediately when hidden', function()
        local state = {width=30, height=10}
        local tooltip = load_tooltip(state)
        local renderer = tooltip.TooltipRenderer{}
        local owner = {invalidate=function(self)
            self.invalidations = (self.invalidations or 0) + 1
        end}
        renderer.parent_view = owner
        local layout_parent = widget_harness.rect(0, 0, 30, 10)

        renderer:set_tooltip('Initial', 1, 1, layout_parent)
        renderer:render({fill=function() end})
        assert.equals(1, renderer.render_count)
        assert.equals(1, owner.invalidations)

        renderer:set_tooltip('Initial', 1, 1, layout_parent)
        assert.equals(1, owner.invalidations)
        renderer:set_tooltip('Updated immediately', 1, 1, layout_parent)
        assert.equals('Updated immediately', renderer.label.text)
        assert.equals(2, owner.invalidations)

        renderer:set_tooltip('', 1, 1, layout_parent)
        assert.is_false(renderer.visible)
        assert.equals('', renderer.label.text)
        assert.equals(3, owner.invalidations)
        renderer:render({fill=function() end})
        assert.equals(1, renderer.render_count)

        renderer:set_tooltip('No pointer', nil, nil, layout_parent)
        assert.is_false(renderer.visible)
        assert.equals('', renderer.label.text)
        assert.equals(4, owner.invalidations)
    end)

    it('contains no SoulSearch diagnostics or logging surface', function()
        local file = assert(io.open(repo_root ..
            '/src/scripts_modinstalled/dwarfui/tooltip.lua', 'rb'))
        local source = file:read('*a')
        file:close()
        local lower = source:lower()

        assert.is_nil(lower:find('soulsearch', 1, true))
        assert.is_nil(lower:find('debug_messages', 1, true))
        assert.is_nil(lower:find('debug_logger', 1, true))
        assert.is_nil(lower:find('find_path', 1, true))
        assert.is_nil(lower:find('print(', 1, true))
    end)
end)
