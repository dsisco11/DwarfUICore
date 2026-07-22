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
    local descriptors = {
        [100]={hover_value=100, label='Ecstatic'},
        [101]={hover_value=101, label='Happy'},
    }
    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui-mood-popover.lua', {
            globals={
                defclass=widget_harness.defclass,
                df={global={world={}}},
                dfhack={
                    gui={
                        getDFViewscreen=function() return state.viewscreen end,
                        matchFocusString=function(focus, viewscreen)
                            state.matched_focus = focus
                            state.matched_viewscreen = viewscreen
                            return state.focus_matches
                        end,
                    },
                    screen={getMousePos=function() return nil, nil end},
                },
            },
            require_modules={['plugins.overlay']={OverlayWidget=OverlayWidget}},
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
        snapshot_provider=function(descriptor)
            state.snapshot_count = (state.snapshot_count or 0) + 1
            return {{name=descriptor.label .. ' unit'}}
        end,
        active_provider=function() return state.active end,
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
end)
