local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local RENDERER_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/renderer.lua'

---Creates a copied pen suitable for isolated renderer tests.
---@param source any
---@param foreground? integer
---@param background? integer
---@return table
local function parse_pen(source, foreground, background)
    local pen = type(source) == 'table' and {
        ch=source.ch,
        tile=source.tile,
        fg=source.fg,
        bg=source.bg,
    } or {}
    if foreground ~= nil then pen.fg = foreground end
    if background ~= nil then pen.bg = background end
    return pen
end

---Loads the renderer with observable native-widget doubles.
---@return table
---@return table
local function load_renderer()
    local widgets = widget_harness.widgets()
    local frame_calls = 0
    local gui = {
        FRAME_INTERIOR=function()
            frame_calls = frame_calls + 1
            return {
                t_frame_pen={ch='-', fg=7, bg=0},
                l_frame_pen={ch='|', fg=7, bg=0},
                signature_pen=false,
            }
        end,
    }
    local _, renderer = module_loader.load(repo_root, RENDERER_PATH, {
        globals={
            defclass=widget_harness.defclass,
            dfhack={pen={parse=parse_pen}},
        },
        require_modules={
            gui=gui,
            ['gui.widgets']=widgets,
        },
    })
    return renderer, {
        widgets=widgets,
        gui=gui,
        frame_calls=function() return frame_calls end,
    }
end

---Creates one resolved definition snapshot for renderer tests.
---@param title? string
---@return table
local function definition(title)
    return {
        title=title,
        fg=15,
        bg=0,
        entries={
            {label='Short', fg=2, bg=4},
            {label='A label that is much too long', fg=7, bg=7},
            {label='Third', fg=15, bg=0},
        },
    }
end

describe('DwarfUICore context-menu renderer', function()
    it('truncates deterministically with ellipsis and narrow clipping',
            function()
        local renderer = load_renderer()
        assert.equals('abc...', renderer.truncate_text('abcdefgh', 6))
        assert.equals('ab', renderer.truncate_text('abcdefgh', 2))
        assert.equals('abc', renderer.truncate_text('abc', 6))
    end)

    it('measures, clamps, truncates, and caps both dimensions', function()
        local renderer = load_renderer()
        local layout = renderer.calculate_layout(
            definition('Long title'), {x=9, y=4}, 10, 4)

        assert.same({l=0, t=0, w=10, h=4}, layout.frame)
        assert.equals(8, layout.content_width)
        assert.equals('L...', layout.title)
        assert.equals('A lab...', layout.choices[2].text)
    end)

    it('supports an absent title and every screen edge', function()
        local renderer = load_renderer()
        local top_left = renderer.calculate_layout(
            definition(nil), {x=-5, y=-2}, 20, 10)
        local bottom_right = renderer.calculate_layout(
            definition(nil), {x=99, y=99}, 20, 10)

        assert.is_nil(top_left.title)
        assert.equals(0, top_left.frame.l)
        assert.equals(0, top_left.frame.t)
        assert.equals(20 - bottom_right.frame.w, bottom_right.frame.l)
        assert.equals(10 - bottom_right.frame.h, bottom_right.frame.t)
    end)

    it('chooses horizontal and vertical fallback independently', function()
        local renderer = load_renderer()
        local definition = {
            fg=15,
            bg=0,
            entries={{label='123456', fg=15, bg=0}},
        }
        assert.same({l=2, t=1, w=8, h=3},
            renderer.calculate_layout(
                definition, {x=10, y=1}, 16, 10).frame)
        assert.same({l=10, t=3, w=8, h=3},
            renderer.calculate_layout(
                definition, {x=10, y=6}, 20, 8).frame)
        assert.same({l=2, t=3, w=8, h=3},
            renderer.calculate_layout(
                definition, {x=10, y=6}, 12, 8).frame)
    end)

    it('creates isolated frame styles and preserves native glyphs', function()
        local renderer, context = load_renderer()
        local first = renderer.create_frame_style(2, 4)
        local second = renderer.create_frame_style(15, 0)

        assert.equals(2, first.t_frame_pen.fg)
        assert.equals(4, first.t_frame_pen.bg)
        assert.equals('-', first.t_frame_pen.ch)
        assert.equals(15, second.t_frame_pen.fg)
        assert.equals(2, context.frame_calls())
        assert.is_false(first.signature_pen)
    end)

    it('composes a fixed Window and native selectable List', function()
        local renderer = load_renderer()
        local selected
        local window = renderer.ContextMenuWindow{
            definition=definition('Title'),
            anchor={x=3, y=2},
            on_select=function(index) selected = index end,
        }
        widget_harness.set_frame(window, 0, 0, 20, 10)
        window:relayout(20, 10)

        assert.is_false(window.draggable)
        assert.is_false(window.resizable)
        assert.equals('Title', window.frame_title)
        assert.equals(3, #window.menu_list.choices)
        window.menu_list.on_submit(2, window.menu_list.choices[2])
        assert.equals(2, selected)
    end)

    it('reclamps and retruncates after interface dimensions change',
            function()
        local renderer = load_renderer()
        local window = renderer.ContextMenuWindow{
            definition=definition('A long native title'),
            anchor={x=15, y=8},
            on_select=function() end,
        }
        widget_harness.set_frame(window, 0, 0, 30, 12)
        window:relayout(30, 12)
        local wide_title = window.frame_title
        window.frame_parent_rect = widget_harness.rect(0, 0, 8, 4)

        window:relayout(8, 4)

        assert.is_true(#window.frame_title < #wide_title)
        assert.equals(0, window.frame.l)
        assert.equals(0, window.frame.t)
        assert.equals(8, window.frame.w)
        assert.equals(4, window.frame.h)
    end)

    it('fills complete rows with normal and readable active pens', function()
        local renderer = load_renderer()
        local list = renderer.ContextMenuList{}
        list.choices = renderer.calculate_layout(
            definition(nil), {x=0, y=0}, 20, 10).choices
        list.page_top = 1
        list.page_size = 3
        list.selected = 1
        list.getIdxUnderMouse = function() return 2 end
        local fills, strings = {}, {}
        local dc = {
            width=18,
            fill=function(_, x1, y1, x2, y2, pen)
                table.insert(fills, {x1, y1, x2, y2, pen.fg, pen.bg})
            end,
            seek=function(self) return self end,
            string=function(self, text, pen)
                table.insert(strings, {text, pen.fg, pen.bg})
                return self
            end,
        }

        list:onRenderBody(dc)

        assert.same({0, 0, 17, 0, 4, 2}, fills[1])
        assert.same({0, 1, 17, 1, 15, 7}, fills[2])
        assert.same({'Short', 4, 2}, strings[1])
    end)
end)
