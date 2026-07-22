local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

---Creates a painter double that records each task-detail row draw.
---@return table
local function make_painter()
    local painter = {calls={}}
    ---Records the draw cursor position.
    ---@param self table
    ---@param x integer
    ---@param y integer
    ---@return table
    function painter:seek(x, y)
        self.x, self.y = x, y
        return self
    end
    ---Records one text draw request.
    ---@param self table
    ---@param text string
    ---@param pen any
    function painter:string(text, pen)
        table.insert(self.calls, {x=self.x, y=self.y, text=text, pen=pen})
    end
    return painter
end

---Loads the task-details overlay with deterministic task text and pointer state.
---@param state table
---@return table
local function load_overlay(state)
    local widgets = widget_harness.widgets()
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    ---Creates an overlay-compatible class with the widget harness.
    ---@param global_slot table|nil
    ---@param parent table|nil
    ---@return table
    local function test_defclass(global_slot, parent)
        return widget_harness.defclass(global_slot, parent or widgets.Widget)
    end
    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui-unit-card-task-details.lua', {
            globals={
                defclass=test_defclass,
                COLOR_YELLOW='yellow',
                COLOR_LIGHTCYAN='cyan',
                dfhack={
                    gui={getSelectedUnit=function() return state.unit end},
                    screen={getMousePos=function()
                        return state.mouse_x, state.mouse_y
                    end},
                },
            },
            require_modules={
                ['plugins.overlay']={OverlayWidget=OverlayWidget},
            },
            reqscript={
                ['dwarfui/unit_card_task']={
                    get_grab_item_text=function() return state.grab_text end,
                    get_haul_destination_text=function()
                        return state.destination_text
                    end,
                    truncate_panel_text=function(text, width)
                        return text and text:sub(1, width) or nil
                    end,
                    is_panel_text_truncated=function(text, width)
                        return text ~= nil and #text > width
                    end,
                },
            },
        })
    return module.UnitCardTaskDetailsOverlay{}
end

describe('DwarfUI unit-card task overlay', function()
    it('caps long rows while the pointer is outside the task panel', function()
        local state = {
            mouse_x=166,
            mouse_y=31,
            grab_text='Grab: an exceptionally long record title',
            destination_text='Destination: an exceptionally long stockpile',
        }
        local overlay = load_overlay(state)
        local painter = make_painter()

        overlay:render(painter)

        assert.equals(29, #painter.calls[1].text)
        assert.equals(29, #painter.calls[2].text)
    end)

    it('overdraws the complete hovered task row without expanding others',
            function()
        local state = {
            mouse_x=180,
            mouse_y=31,
            grab_text='Grab: an exceptionally long record title',
            destination_text='Destination: an exceptionally long stockpile',
        }
        local overlay = load_overlay(state)
        local painter = make_painter()

        overlay:render(painter)

        assert.equals(state.grab_text, painter.calls[1].text)
        assert.equals(29, #painter.calls[2].text)
        assert.equals('yellow', painter.calls[1].pen)
    end)

    it('overdraws the complete destination row when it is hovered', function()
        local state = {
            mouse_x=180,
            mouse_y=32,
            grab_text='Grab: an exceptionally long record title',
            destination_text='Destination: an exceptionally long stockpile',
        }
        local overlay = load_overlay(state)
        local painter = make_painter()

        overlay:render(painter)

        assert.equals(29, #painter.calls[1].text)
        assert.equals(state.destination_text, painter.calls[2].text)
        assert.equals('cyan', painter.calls[2].pen)
    end)
end)
