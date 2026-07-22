local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local mouse = {x=nil, y=nil}
local default_nil = widget_harness.default_nil()
local widgets = widget_harness.widgets(nil, default_nil)

local _, popover_module = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/popover.lua', {
        globals={
            defclass=widget_harness.defclass,
            dfhack={screen={
                getMousePos=function() return mouse.x, mouse.y end,
            }},
        },
        require_modules={
            gui={WINDOW_FRAME='window', FRAME_INTERIOR='interior'},
            ['gui.widgets']=widgets,
        },
    })

local Popover = popover_module.Popover

local function rect(width, height)
    return widget_harness.rect(0, 0, width, height)
end

local function rows(count)
    local result = {}
    for index=1,count do
        table.insert(result, {name=('Unit %02d'):format(index)})
    end
    return result
end

describe('DwarfUI Popover', function()
    before_each(function()
        mouse.x, mouse.y = nil, nil
    end)

    it('prefers placement below its anchor and falls back above it', function()
        local parent = rect(80, 25)
        assert.same({x=10, y=6, w=20, h=8},
            Popover.calculate_frame(10, 5, parent, 20, 8, 1))
        assert.same({x=10, y=15, w=20, h=8},
            Popover.calculate_frame(10, 23, parent, 20, 8, 1))
    end)

    it('clamps frames to every screen edge and narrow displays', function()
        local parent = rect(80, 25)
        assert.same({x=1, y=2, w=20, h=8},
            Popover.calculate_frame(0, 1, parent, 20, 8, 1))
        assert.same({x=59, y=2, w=20, h=8},
            Popover.calculate_frame(79, 1, parent, 20, 8, 1))
        assert.same({x=1, y=1, w=8, h=6},
            Popover.calculate_frame(5, 3, rect(10, 8), 20, 12, 1))
    end)

    it('applies configurable content-width and margin bounds', function()
        local popover = Popover{min_width=10, max_width=16, margin=2}
        popover:set_content('A', {})
        assert.equals(10, popover:measure_width())
        popover:set_content('A', {{name='A row that exceeds the maximum'}})
        assert.equals(16, popover:measure_width())
        popover:show_at(0, 0, rect(80, 25))
        assert.same({2, 2},
            {popover.frame_global.x, popover.frame_global.y})
    end)

    it('shows a heading, count, and every configured row through its list',
            function()
        local popover = Popover{}
        popover:set_content('Unhappy', rows(20))
        popover:show_at(10, 5, rect(80, 25))

        assert.is_true(popover.visible)
        assert.equals('Unhappy (20)', popover.header.text)
        assert.equals(20, #popover.list.choices)
        assert.equals('Unit 01', popover.list.choices[1].text)
        assert.equals(12, popover:get_visible_row_count())
        assert.is_true(popover:has_overflow())
    end)

    it('handles empty content without a scrollable list', function()
        local popover = Popover{}
        popover:set_content('Miserable', {})
        popover:show_at(10, 5, rect(80, 25))

        assert.equals('Miserable (0)', popover.header.text)
        assert.is_true(popover.empty.visible)
        assert.is_false(popover.list.visible)
        assert.equals(0, popover:get_visible_row_count())
        assert.is_false(popover:has_overflow())
        assert.is_true(popover:onInput({CONTEXT_SCROLL_DOWN=true}))
        assert.equals(6, popover.frame_global.h)
        assert.equals(2, popover.frame_body.height)
    end)

    it('focuses the scrollbar and forwards wheel input without leaving the anchor',
            function()
        local popover = Popover{}
        popover:set_content('Content', rows(20))
        popover.list.scrollbar = {setFocus=function(scrollbar, value)
            scrollbar.focused = value
        end, on_scroll=function(scroll_spec)
            popover.list.scroll_spec = scroll_spec
        end}
        popover:show_at(10, 5, rect(80, 25))
        mouse.x = 0
        mouse.y = 0

        assert.is_true(popover:onInput({CONTEXT_SCROLL_DOWN=true}))
        assert.is_true(popover.list.scrollbar.focused)
        assert.equals('down_small', popover.list.scroll_spec)
        assert.is_nil(popover:onInput({KEYBOARD_CURSOR_DOWN=true}))
        assert.is_true(popover:onInput({CONTEXT_SCROLL_PAGEDOWN=true}))
        assert.equals('down_large', popover.list.scroll_spec)
    end)

    it('reports visible panel and list hit regions and clears them on hide',
            function()
        local popover = Popover{}
        popover:set_content('Pleased', rows(2))
        popover:show_at(10, 5, rect(80, 25))

        assert.is_true(popover:contains_point(10, 6))
        assert.is_false(popover:contains_point(9, 6))
        assert.is_true(popover:contains_retention_point(12, 5))
        assert.is_false(popover:contains_retention_point(9, 5))
        assert.is_true(popover:contains_list_point(12, 9))
        assert.is_false(popover:contains_list_point(12, 8))
        popover:render({})
        local rendered = popover.render_count
        popover:hide()
        popover:render({})
        assert.equals(rendered, popover.render_count)
        assert.is_false(popover:contains_point(10, 6))
        assert.is_false(popover:contains_list_point(11, 8))
        assert.is_nil(popover:onInput({CONTEXT_SCROLL_DOWN=true}))
    end)

    it('submits the clicked list row', function()
        local submitted_row, submitted_index
        local row = {id=42, name='Clickable Unit'}
        local popover = Popover{on_submit=function(value, index)
            submitted_row, submitted_index = value, index
            return true
        end}
        popover:set_content('Content', {row})
        popover:show_at(10, 5, rect(80, 25))
        popover.list.onInput = function(list, keys)
            if not keys._MOUSE_L then return end
            return list.on_submit(1, list.choices[1])
        end
        mouse.x, mouse.y = 12, 9

        assert.is_true(popover:onInput({_MOUSE_L=true}))
        assert.is.equal(row, submitted_row)
        assert.equals(1, submitted_index)
    end)
end)
