local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

---Creates a minimal popover double that records overlay interactions.
---@return table
local function make_popover()
    return setmetatable({}, {__call=function(_, attributes)
        local popover = {visible=false, set_calls={}, input_result=nil}
        for key, value in pairs(attributes or {}) do popover[key] = value end
        ---Records a heading and row refresh from the overlay.
        function popover:set_content(title, rows, reset_scroll)
            self.title, self.rows = title, rows
            table.insert(self.set_calls, {title=title, rows=rows,
                reset_scroll=reset_scroll})
        end
        ---Records the fixed anchor supplied by a new mood selection.
        function popover:show_at(x, y, parent_rect)
            self.visible, self.anchor_x, self.anchor_y = true, x, y
            self.parent_rect = parent_rect
        end
        ---Marks the test double as hidden.
        function popover:hide() self.visible = false end
        ---Returns whether a point is inside the configured retained panel.
        function popover:contains_point(x, y)
            return self.visible and self.inside and self.inside(x, y)
        end
        ---Returns whether a point is inside the configured retained region.
        function popover:contains_retention_point(x, y)
            return self:contains_point(x, y)
        end
        ---Records and returns the configured input decision.
        function popover:onInput(keys)
            self.input_keys = keys
            return self.input_result
        end
        ---Records that the overlay rendered its child popover.
        function popover:render()
            self.render_count = (self.render_count or 0) + 1
        end
        return popover
    end})
end

---Loads the registration script against isolated overlay dependencies.
---@param state table
---@return table
local function load_overlay(state)
    local widgets = widget_harness.widgets()
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    ---Creates plain test classes and overlay subclasses with one harness API.
    ---@param global_slot table|nil
    ---@param parent table|nil
    ---@return table
    local function test_defclass(global_slot, parent)
        return widget_harness.defclass(global_slot, parent or widgets.Widget)
    end
    local hover_instructions = {
        INFO_STRESSED_0=100,
        INFO_STRESSED_1=101,
        INFO_STRESSED_2=102,
        INFO_STRESSED_3=103,
        INFO_STRESSED_4=104,
        INFO_STRESSED_5=105,
        INFO_STRESSED_6=106,
    }
    local descriptors = {
        [100]={hover_value=100, label='Ecstatic'},
        [101]={hover_value=101, label='Happy'},
    }
    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui-mood-popover.lua', {
            globals={
                defclass=test_defclass,
                df={
                    global={world={}, gps={dimx=state.width or 80,
                        dimy=state.height or 25}},
                    main_hover_instruction=hover_instructions,
                },
                dfhack={
                    gui={
                        getDFViewscreen=function() return state.viewscreen end,
                        matchFocusString=function(focus, viewscreen)
                            state.matched_focus = focus
                            state.matched_viewscreen = viewscreen
                            return state.focus_matches
                        end,
                    },
                    screen={
                        getMousePos=function()
                            return state.mouse_x, state.mouse_y
                        end,
                        readTile=function(x, y)
                            return state.tiles and state.tiles[y] and
                                state.tiles[y][x] or {ch=0, tile=0}
                        end,
                    },
                },
            },
            require_modules={
                ['plugins.overlay']={OverlayWidget=OverlayWidget},
                gui={FRAME_INTERIOR='interior'},
            },
            reqscript={
                ['dwarfui/mood_popover']={MoodPopoverModel=function()
                    return {resolve_hover=function(_, value)
                        return descriptors[value]
                    end}
                end},
                ['dwarfui/popover']={Popover=make_popover()},
            },
        })
    state.descriptors = descriptors
    return module.MoodPopoverOverlay, module
end

---Creates an overlay with deterministic interactive providers.
---@param state table
---@return table
local function overlay_with(state)
    local Overlay = load_overlay(state)
    local instance = Overlay{
        hover_provider=function() return state.hover end,
        mouse_provider=function() return state.mouse_x, state.mouse_y end,
        anchor_provider=function(x, y) return x, y end,
        snapshot_provider=function(descriptor)
            state.snapshot_count = (state.snapshot_count or 0) + 1
            return {{name=descriptor.label .. ' unit'}}
        end,
        active_provider=function() return state.active end,
        unit_opener=function(unit)
            state.opened_unit = unit
            return state.open_result ~= false
        end,
        refresh_interval=2,
    }
    instance.frame_parent_rect = widget_harness.rect(0, 0, 80, 25)
    return instance
end

describe('DwarfUI mood popover overlay', function()
    it('registers a default-enabled fullscreen fortress overlay', function()
        local state = {active=true}
        local Overlay, module = load_overlay(state)
        assert.is_true(Overlay.ATTRS.default_enabled)
        assert.same({x=1, y=1}, Overlay.ATTRS.default_pos)
        assert.equals('dwarfmode/Default', Overlay.ATTRS.viewscreens)
        assert.is_true(Overlay.ATTRS.hotspot)
        assert.is_true(Overlay.ATTRS.fullscreen)
        assert.equals(0, Overlay.ATTRS.overlay_onupdate_max_freq_seconds)
        assert.equal(module.MoodPopoverOverlay,
            module.OVERLAY_WIDGETS.mood_popover)
        local instance = Overlay{}
        assert.equals('interior', instance.popover.frame_style)
    end)

    it('fills the screen so the popover can render and receive wheel input',
            function()
        local state = {active=true}
        local overlay = overlay_with(state)
        overlay.frame = {w=1, h=1}
        overlay:preUpdateLayout(widget_harness.rect(0, 0, 120, 40))
        assert.equals(120, overlay.frame.w)
        assert.equals(40, overlay.frame.h)
    end)

    it('uses DFHack viewscreen matching for the production focus check',
            function()
        local viewscreen = {}
        local state = {viewscreen=viewscreen, focus_matches=true}
        local Overlay = load_overlay(state)
        assert.is_true(Overlay.ATTRS.active_provider())
        assert.equals('dwarfmode/Default', state.matched_focus)
        assert.equal(viewscreen, state.matched_viewscreen)

        state.focus_matches = false
        assert.is_false(Overlay.ATTRS.active_provider())
    end)

    it('discovers and hit-tests the rendered top-bar mood icons', function()
        local state = {width=40, height=10, tiles={}}
        for y=0,2 do state.tiles[y] = {} end
        state.tiles[0][5] = {ch=string.byte('P'), tile=0}
        state.tiles[0][6] = {ch=string.byte('o'), tile=0}
        state.tiles[0][7] = {ch=string.byte('p'), tile=0}
        for hover_index=0,6 do
            local icon_x = 9 + hover_index * 3
            state.tiles[0][icon_x - 1] = {ch=0, tile=0}
            for y=0,1 do
                for x=icon_x,icon_x + 1 do
                    state.tiles[y][x] = {ch=0, tile=100 + hover_index}
                end
            end
        end

        local _, module = load_overlay(state)
        local display = module.TopBarMoodDisplay{}
        local rects = assert(display:find_layout())
        assert.equals(7, #rects)
        for index, rect in ipairs(rects) do
            assert.equals(9 + (index - 1) * 3, rect.x1)
            assert.equals(2, rect.y2)
            for y=rect.y1,rect.y2 do
                for x=rect.x1,rect.x2 do
                    assert.equals(99 + index,
                        display:resolve_hover(x, y))
                end
            end
            assert.same({rect.x1, rect.y2 + 1},
                {display:get_popover_anchor(rect.x2, rect.y1)})
        end
    end)

    it('samples native hover during render after DF has updated it', function()
        local state = {active=true, hover=100, mouse_x=12, mouse_y=3}
        local overlay = overlay_with(state)
        overlay.visible = true
        overlay:render({})
        assert.equals('Ecstatic', overlay.selected_descriptor.label)
        assert.is_true(overlay.popover.visible)
        assert.equals(1, overlay.popover.render_count)
    end)

    it('opens for native hover, refreshes on cadence, and keeps its anchor',
            function()
        local state = {active=true, hover=100, mouse_x=12, mouse_y=3}
        local overlay = overlay_with(state)
        overlay:update_popover()
        assert.equals('Ecstatic', overlay.selected_descriptor.label)
        assert.same({12, 3}, {overlay.popover.anchor_x, overlay.popover.anchor_y})
        assert.equals(1, state.snapshot_count)
        assert.is_true(overlay.popover.set_calls[1].reset_scroll)

        state.mouse_x, state.mouse_y = 20, 8
        overlay:update_popover()
        overlay:update_popover()
        assert.equals(2, state.snapshot_count)
        assert.same({12, 3}, {overlay.popover.anchor_x, overlay.popover.anchor_y})
        assert.is_false(overlay.popover.set_calls[2].reset_scroll)
    end)

    it('retains selection inside the panel, switches directly, and clears out',
            function()
        local state = {active=true, hover=100, mouse_x=12, mouse_y=3}
        local overlay = overlay_with(state)
        overlay:update_popover()
        overlay.popover.inside = function(x, y) return x == 14 and y == 5 end

        state.hover, state.mouse_x, state.mouse_y = nil, 14, 5
        overlay:update_popover()
        assert.equals('Ecstatic', overlay.selected_descriptor.label)
        assert.is_true(overlay.popover.visible)

        state.hover, state.mouse_x, state.mouse_y = 101, 30, 4
        overlay:update_popover()
        assert.equals('Happy', overlay.selected_descriptor.label)
        assert.same({30, 4}, {overlay.popover.anchor_x, overlay.popover.anchor_y})
        assert.is_true(overlay.popover.set_calls[#overlay.popover.set_calls].reset_scroll)

        state.hover, state.mouse_x, state.mouse_y = nil, 0, 0
        overlay:update_popover()
        assert.is_nil(overlay.selected_descriptor)
        assert.is_false(overlay.popover.visible)
        assert.same({}, overlay.popover.rows)
    end)

    it('clears safely on null pointers, inactive maps, and disable', function()
        local state = {active=true, hover=100, mouse_x=12, mouse_y=3}
        local overlay = overlay_with(state)
        overlay:update_popover()
        state.mouse_x = nil
        overlay:update_popover()
        assert.is_nil(overlay.selected_descriptor)

        state.mouse_x, state.mouse_y, state.hover = 12, 3, 100
        overlay:update_popover()
        state.active = false
        overlay:overlay_onupdate()
        assert.is_nil(overlay.selected_descriptor)
        overlay:overlay_ondisable()
        assert.is_false(overlay.popover.visible)
    end)

    it('forwards every input decision to the active popover', function()
        local state = {active=true}
        local overlay = overlay_with(state)
        local keys = {CUSTOM=true}
        assert.is_nil(overlay:onInput(keys))
        assert.is.equal(keys, overlay.popover.input_keys)
        overlay.popover.input_result = true
        assert.is_true(overlay:onInput({STANDARDSCROLL_DOWN=true}))
    end)

    it('opens the selected row unit and clears the popover', function()
        local state = {active=true, hover=100, mouse_x=12, mouse_y=3}
        local overlay = overlay_with(state)
        local unit = {id=42}
        overlay:update_popover()

        assert.is_true(overlay:open_row({unit=unit}))
        assert.is.equal(unit, state.opened_unit)
        assert.is_nil(overlay.selected_descriptor)
        assert.is_false(overlay.popover.visible)
    end)
end)
