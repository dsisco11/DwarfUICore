local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local RENDERER_PATH =
    'src/scripts_modinstalled/dwarfuicore/user_prompt/renderer.lua'

---Loads prompt values and the renderer with observable widget doubles.
---@param state table
---@return table renderer
---@return table values
---@return table context
local function load_renderer(state)
    state.width, state.height = state.width or 80, state.height or 25
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{visible=true, active=true}
    local _, namespace = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')
    local _, values = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/value.lua', {
            reqscript={
                ['dwarfuicore/service_provider/namespace']=namespace,
            },
        })
    local _, immutable_enum = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local _, pointer = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/pointer.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
            },
        })
    local gui = {
        FRAME_INTERIOR='interior',
        paint_frame=function(_, rect, style, title)
            state.paint = {rect=rect, style=style, title=title}
            state.title_x = rect.x1 + math.max(0,
                math.floor((rect.width - 4 - #title) / 2))
        end,
    }
    local _, renderer = module_loader.load(repo_root, RENDERER_PATH, {
        globals={
            COLOR_BLACK='black',
            COLOR_WHITE='white',
            COLOR_YELLOW='yellow',
            DEFAULT_NIL=default_nil,
            defclass=widget_harness.defclass,
            dfhack={
                pen={parse=function(value) return value end},
                screen={getWindowSize=function()
                    return state.width, state.height
                end},
            },
        },
        require_modules={gui=gui, ['gui.widgets']=widgets},
        reqscript={
            ['dwarfuicore/pointer']=pointer,
            ['dwarfuicore/user_prompt/value']=values,
        },
    })
    return renderer, values, {widgets=widgets, pointer=pointer}
end

---Creates one immutable request with exact supplied presentation text.
---@param values table
---@param namespace string
---@param title string
---@param message string
---@return table request
local function request(values, namespace, title, message)
    return values.MapLocationPromptRequest.new(namespace, {
        title=title,
        message=message,
        on_select=function() end,
    })
end

describe('UserPrompt renderer', function()
    it('keeps namespace, title, and message in distinct visual roles', function()
        local state = {width=40, height=12}
        local renderer_module, values, context = load_renderer(state)
        local prompt = request(values, 'owner.plugin', 'Choose tile',
            'Select a destination.')
        local renderer = renderer_module.UserPromptRenderer{}

        renderer:set_prompt(prompt, 2, 3,
            widget_harness.rect(0, 0, 40, 12))
        renderer:render({fill=function() end})

        assert.equals(context.widgets.Widget,
            renderer_module.UserPromptRenderer.super)
        assert.equals(context.pointer.PointerPolicy.NONE,
            renderer.pointer_policy)
        assert.equals(context.pointer.PointerPolicy.NONE,
            renderer.title_label.pointer_policy)
        assert.equals(context.pointer.PointerPolicy.NONE,
            renderer.message_label.pointer_policy)
        assert.equals(1, renderer.frame_inset)
        assert.is_nil(renderer.onInput)
        assert.equals('owner.plugin', renderer.namespace)
        assert.equals('Choose tile', renderer.title)
        assert.equals('Select a destination.', renderer.message)
        assert.equals('Choose tile', renderer.title_label.text)
        assert.equals('Select a destination.', renderer.message_label.text)
        assert.equals('yellow', renderer.title_label.text_pen.fg)
        assert.equals('white', renderer.message_label.text_pen.fg)
        assert.equals('owner.plugin', state.paint.title)
        assert.equals('interior', state.paint.style)
    end)

    it('preserves empty strings, explicit newlines, and copied request state',
            function()
        local state = {width=30, height=12}
        local renderer_module, values = load_renderer(state)
        local options = {
            title='', message='first\n\nsecond', on_select=function() end,
        }
        local prompt = values.MapLocationPromptRequest.new(
            'exact.owner', options)
        options.title, options.message = 'changed', 'changed'
        local renderer = renderer_module.UserPromptRenderer{}

        renderer:set_prompt(prompt, 1, 1,
            widget_harness.rect(0, 0, 30, 12))

        assert.equals('', renderer.title)
        assert.equals('first\n\nsecond', renderer.message)
        assert.equals('', renderer.title_label.text)
        assert.equals('first\n\nsecond', renderer.message_label.text)
        assert.is.equal(prompt, renderer.request)
        assert.equals('exact.owner', renderer.request.namespace)
    end)

    it('wraps text and prefers placement below the pointer', function()
        local state = {width=30, height=12}
        local renderer_module, values = load_renderer(state)
        local prompt = request(values, 'owner',
            'A title that wraps', 'A message that also wraps safely')
        local layout = renderer_module.calculate_layout(
            prompt, 1, 1, 30, 12)

        assert.equals(3, layout.frame.l)
        assert.equals(2, layout.frame.t)
        for _, lines in ipairs({layout.title_lines, layout.message_lines}) do
            for _, line in ipairs(lines) do
                assert.is_true(#line <= layout.content_width)
            end
        end
    end)

    it('reserves distinct visible regions in a constrained-height viewport',
            function()
        local state = {width=18, height=4}
        local renderer_module, values = load_renderer(state)
        local prompt = request(values, 'owner',
            'A title that wraps across several lines', 'Visible message')
        local renderer = renderer_module.UserPromptRenderer{}

        renderer:set_prompt(prompt, 0, 0,
            widget_harness.rect(0, 0, 18, 4))

        assert.equals(4, renderer.frame.h)
        assert.equals(1, renderer.title_label.frame.h)
        assert.equals(1, renderer.message_label.frame.h)
        assert.equals(renderer.title_label.frame.t +
            renderer.title_label.frame.h, renderer.message_label.frame.t)
        assert.is_true(renderer.message_label.frame.t +
            renderer.message_label.frame.h <= renderer.frame.h - 2)
    end)

    it('clamps against every edge and recomputes on motion and resize', function()
        local state = {width=20, height=8}
        local renderer_module, values = load_renderer(state)
        local renderer = renderer_module.UserPromptRenderer{}
        local owner = {invalidate=function(self)
            self.count = (self.count or 0) + 1
        end}
        renderer.parent_view = owner
        local prompt = request(values, 'owner', 'Title', 'Message')

        renderer:set_prompt(prompt, -10, -10,
            widget_harness.rect(0, 0, 20, 8))
        assert.equals(0, renderer.frame.l)
        assert.equals(0, renderer.frame.t)
        local first = renderer.frame
        renderer:set_prompt(prompt, 19, 7,
            widget_harness.rect(0, 0, 20, 8))
        assert.equals(20 - renderer.frame.w, renderer.frame.l)
        assert.equals(8 - renderer.frame.h, renderer.frame.t)
        assert.not_same(first, renderer.frame)
        renderer:set_prompt(prompt, 19, 7,
            widget_harness.rect(0, 0, 10, 5))
        assert.is_true(renderer.frame.l + renderer.frame.w <= 10)
        assert.is_true(renderer.frame.t + renderer.frame.h <= 5)
        assert.equals(3, owner.count)
        assert.equals(3, renderer.layout_update_count)
    end)

    it('invalidates changed content but not an identical presentation',
            function()
        local state = {width=30, height=10}
        local renderer_module, values = load_renderer(state)
        local renderer = renderer_module.UserPromptRenderer{}
        local owner = {invalidate=function(self)
            self.count = (self.count or 0) + 1
        end}
        renderer.parent_view = owner
        local first = request(values, 'owner', 'First', 'Message')
        local second = request(values, 'owner', 'Second', 'Changed message')
        local rect = widget_harness.rect(0, 0, 30, 10)

        renderer:set_prompt(first, 2, 2, rect)
        renderer:set_prompt(first, 2, 2, rect)
        assert.equals(1, owner.count)
        renderer:set_prompt(second, 2, 2, rect)

        assert.equals(2, owner.count)
        assert.equals('Second', renderer.title_label.text)
        assert.equals('Changed message', renderer.message_label.text)
    end)

    it('hides without ending request state when screen pointer is absent',
            function()
        local state = {width=24, height=8}
        local renderer_module, values = load_renderer(state)
        local renderer = renderer_module.UserPromptRenderer{}
        local owner = {invalidate=function(self)
            self.count = (self.count or 0) + 1
        end}
        renderer.parent_view = owner
        local prompt = request(values, 'owner', 'Title', 'Message')
        local rect = widget_harness.rect(0, 0, 24, 8)

        renderer:set_prompt(prompt, 2, 2, rect)
        renderer:render({fill=function() end})
        renderer:set_prompt(prompt, nil, nil, rect)
        assert.is_false(renderer.visible)
        assert.is.equal(prompt, renderer.request)
        assert.equals('', renderer.title_label.text)
        assert.equals('', renderer.message_label.text)
        renderer:render({fill=function() end})
        assert.equals(1, renderer.render_count)

        renderer:set_prompt(prompt, 3, 3, rect)
        assert.is_true(renderer.visible)
        assert.equals('Title', renderer.title_label.text)
        assert.equals(3, owner.count)
    end)

    it('sizes for the namespace and passes the centered label unchanged',
            function()
        local state = {width=40, height=8}
        local renderer_module, values = load_renderer(state)
        local namespace = 'long.namespace.owner'
        local prompt = request(values, namespace, '', '')
        local renderer = renderer_module.UserPromptRenderer{}

        renderer:set_prompt(prompt, 0, 0,
            widget_harness.rect(0, 0, 40, 8))
        assert.equals(#namespace + 6, renderer.frame.w)
        renderer:render({fill=function() end})
        assert.equals(namespace, state.paint.title)
        assert.equals(renderer.frame_rect.x1 + 1, state.title_x)
    end)

    it('covers ellipsis, narrow-prefix, empty-capacity, and exact-fit branches',
            function()
        local renderer_module = load_renderer({})
        assert.equals('abc...',
            renderer_module.truncate_namespace('abcdefgh', 6))
        assert.equals('ab',
            renderer_module.truncate_namespace('abcdefgh', 2))
        assert.equals('',
            renderer_module.truncate_namespace('abcdefgh', 0))
        assert.equals('abc',
            renderer_module.truncate_namespace('abc', 3))
    end)

    it('retains the full namespace in narrow viewports with no override path',
            function()
        local state = {width=8, height=5}
        local renderer_module, values = load_renderer(state)
        local prompt = request(values, 'consumer.namespace', 'Title', 'Body')
        local renderer = renderer_module.UserPromptRenderer{}

        renderer:set_prompt(prompt, 7, 4,
            widget_harness.rect(0, 0, 8, 5))

        assert.equals(8, renderer.frame.w)
        assert.equals('co', renderer.namespace_label)
        assert.equals('consumer.namespace', renderer.namespace)
        assert.equals('consumer.namespace', renderer.request.namespace)
        assert.has_error(function()
            renderer:set_prompt({namespace='spoofed'}, 0, 0)
        end)
    end)
end)
