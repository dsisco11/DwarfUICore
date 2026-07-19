local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local extension_path =
    'src/scripts_modinstalled/dwarfui/widget_extensions.lua'
local pointer_path = 'src/scripts_modinstalled/dwarfui/pointer.lua'
local text_path = 'src/scripts_modinstalled/dwarfui/text.lua'
local tooltip_path = 'src/scripts_modinstalled/dwarfui/tooltip.lua'

local function load_tooltip(state)
    state.width = state.width or 80
    state.height = state.height or 25
    state.mouse_samples = state.mouse_samples or 0
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
            getMousePos=function()
                state.mouse_samples = state.mouse_samples + 1
                return state.mouse_x, state.mouse_y
            end,
            getWindowSize=function()
                state.window_samples = (state.window_samples or 0) + 1
                return state.width, state.height
            end,
        },
    }
    local gui = {
        FRAME_INTERIOR='interior',
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
    local _, pointer = module_loader.load(repo_root, pointer_path, {
        globals={dfhack=dfhack},
    })
    local _, tooltip = module_loader.load(repo_root, tooltip_path, {
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
    return tooltip, widgets, pointer
end

local function target(x, y, tooltip)
    local result = {
        visible=true,
        active=true,
        pointer_policy='target',
        tooltip=tooltip,
        subviews={},
    }
    return widget_harness.set_frame(result, x, y, 4, 4)
end

local function root(children)
    local result = {
        visible=true,
        active=true,
        pointer_policy='target',
        subviews=children or {},
    }
    return widget_harness.set_frame(result, 0, 0, 20, 20)
end

local function renderer_spy()
    return {
        calls={},
        set_tooltip=function(self, text, x, y, parent_rect)
            table.insert(self.calls, {
                text=text,
                x=x,
                y=y,
                parent_rect=parent_rect,
            })
            self.text = text
        end,
    }
end

describe('DwarfUI tooltip renderer', function()
    it('is a hidden plain Widget with the required pens and exclusion policy', function()
        local state = {}
        local tooltip, widgets, pointer = load_tooltip(state)
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

        local behind = target(0, 0, 'Behind renderer')
        renderer.visible = true
        widget_harness.set_frame(renderer, 0, 0, 4, 4)
        local result = pointer.PointerDispatcher.resolve(
            root({behind, renderer}), 2, 2)
        assert.is.equal(behind, result.target)
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
end)

describe('DwarfUI tooltip agent', function()
    it('owns one root, context, and renderer', function()
        local state = {mouse_x=2, mouse_y=2}
        local tooltip = load_tooltip(state)
        local view = root({})
        local renderer = renderer_spy()
        local agent = tooltip.TooltipAgent.new(view, renderer)

        assert.is.equal(view, agent.root)
        assert.is.equal(view, agent.pointer_context.root)
        assert.is.equal(renderer, agent.renderer)
        assert.is_nil(agent.pointer_context.target)
    end)

    it('reads static and currently mutated text and clears both empty forms', function()
        local state = {mouse_x=2, mouse_y=2}
        local tooltip = load_tooltip(state)
        local control = target(1, 1, 'Initial')
        local renderer = renderer_spy()
        local agent = tooltip.TooltipAgent.new(root({control}), renderer)

        agent:update()
        assert.equals('Initial', renderer.text)
        control.tooltip = 'Updated'
        agent:update()
        assert.equals('Updated', renderer.text)
        control.tooltip = ''
        agent:update()
        assert.is_nil(renderer.text)
        control.tooltip = nil
        agent:update()
        assert.is_nil(renderer.text)
        assert.equals(4, state.mouse_samples)
    end)

    it('targets native widget declarations with static text', function()
        local state = {mouse_x=2, mouse_y=2}
        local tooltip, widgets = load_tooltip(state)
        local button = widgets.TextButton{tooltip='Native static tooltip'}
        widget_harness.set_frame(button, 1, 1, 4, 4)
        local renderer = renderer_spy()
        local agent = tooltip.TooltipAgent.new(root({button}), renderer)

        local result = agent:update()
        assert.equals('target', result.kind)
        assert.is.equal(button, agent.pointer_context.target)
        assert.equals('Native static tooltip', renderer.text)
    end)

    it('dispatches dynamic pointer updates before reading tooltip text', function()
        local state = {mouse_x=3, mouse_y=4}
        local tooltip = load_tooltip(state)
        local control = target(1, 1, nil)
        control.on_pointer_update = function(target_view, x, y)
            target_view.tooltip = ('Local %d,%d'):format(x, y)
        end
        local renderer = renderer_spy()
        local agent = tooltip.TooltipAgent.new(root({control}), renderer)

        agent:update()
        assert.equals('Local 2,3', renderer.text)
    end)

    it('does not fall back through blockers, exclusions, or ancestors', function()
        local state = {mouse_x=2, mouse_y=2}
        local tooltip = load_tooltip(state)
        local child = target(1, 1, nil)
        local parent = target(1, 1, 'Parent must not be used')
        parent.pointer_policy = 'pass'
        parent.subviews = {child}
        local renderer = renderer_spy()
        local agent = tooltip.TooltipAgent.new(root({parent}), renderer)

        local result = agent:update()
        assert.equals('target', result.kind)
        assert.is.equal(child, result.target)
        assert.is_nil(renderer.text)

        parent.pointer_policy = 'block'
        parent.subviews = {}
        result = agent:update()
        assert.equals('blocked', result.kind)
        assert.is_nil(renderer.text)

        parent.pointer_policy = 'none'
        result = agent:update()
        assert.equals('miss', result.kind)
        assert.is_nil(renderer.text)
    end)

    it('rejects invalid tooltip types without invoking providers', function()
        local state = {mouse_x=2, mouse_y=2}
        local tooltip = load_tooltip(state)
        local invoked = 0
        local provider = function()
            invoked = invoked + 1
            return 'must not run'
        end
        local control = target(1, 1, provider)
        local renderer = renderer_spy()
        local agent = tooltip.TooltipAgent.new(root({control}), renderer)

        local ok, err = pcall(function() agent:update() end)
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find(
            'DwarfUI tooltip must be a string', 1, true))
        assert.equals(0, invoked)
        assert.equals(0, #renderer.calls)

        control.tooltip = 42
        ok, err = pcall(function() agent:update() end)
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find('got number', 1, true))
    end)

    it('reads the mouse exactly once even when coordinates are missing', function()
        local state = {mouse_x=2, mouse_y=2}
        local tooltip = load_tooltip(state)
        local renderer = renderer_spy()
        local agent = tooltip.TooltipAgent.new(
            root({target(1, 1, 'Tip')}), renderer)

        agent:update()
        assert.equals(1, state.mouse_samples)
        assert.equals('Tip', renderer.text)
        assert.equals(2, renderer.calls[1].x)
        assert.equals(2, renderer.calls[1].y)
        state.mouse_x, state.mouse_y = nil, nil
        local result = agent:update()
        assert.equals(2, state.mouse_samples)
        assert.equals('miss', result.kind)
        assert.is_nil(renderer.text)
        assert.is_nil(renderer.calls[2].x)
        assert.is_nil(renderer.calls[2].y)
    end)

    it('forwards the host layout parent rectangle to its renderer', function()
        local state = {mouse_x=2, mouse_y=2}
        local tooltip = load_tooltip(state)
        local renderer = renderer_spy()
        local view = root({target(1, 1, 'Tip')})
        local parent_rect = widget_harness.rect(7, 4, 20, 20,
            {x1=8, y1=5, x2=20, y2=18})
        view.frame_parent_rect = parent_rect

        tooltip.TooltipAgent.new(view, renderer):update()
        assert.is.equal(parent_rect, renderer.calls[1].parent_rect)
    end)

    it('keeps target and presentation state isolated between roots', function()
        local state = {mouse_x=2, mouse_y=2}
        local tooltip = load_tooltip(state)
        local first_target = target(1, 1, 'First root')
        local second_target = target(1, 1, 'Second root')
        local first_root = root({first_target})
        local second_root = root({second_target})
        local first_renderer = renderer_spy()
        local second_renderer = renderer_spy()
        local first = tooltip.TooltipAgent.new(first_root, first_renderer)
        local second = tooltip.TooltipAgent.new(second_root, second_renderer)

        first:update()
        second:update()
        assert.is.equal(first_target, first.pointer_context.target)
        assert.is.equal(second_target, second.pointer_context.target)
        assert.equals('First root', first_renderer.text)
        assert.equals('Second root', second_renderer.text)

        first_root.subviews = {}
        first:update()
        assert.is_nil(first.pointer_context.target)
        assert.is_nil(first_renderer.text)
        assert.is.equal(second_target, second.pointer_context.target)
        assert.equals('Second root', second_renderer.text)
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
