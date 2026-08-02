local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local SCREEN_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/screen.lua'

---Creates a controlled screen module and one hidden presentation.
---@return table
---@return table
local function screen_fixture()
    local mouse = {x=nil, y=nil}
    local parent_inputs = {}
    local widgets = widget_harness.widgets({
        Window={
            onInput=function(self, keys)
                return self:inputToSubviews(keys)
            end,
        },
        List={
            init=function(self, info)
                self.choices = {}
                self.selected = 1
                self.page_top = 1
                self.page_size = 1
                self.scroll_keys = {
                    KEYBOARD_CURSOR_UP=-1,
                    KEYBOARD_CURSOR_DOWN=1,
                    STANDARDSCROLL_UP=-1,
                    STANDARDSCROLL_DOWN=1,
                }
                self.on_submit = info.on_submit
            end,
            onInput=function(self, keys)
                if keys.SELECT then
                    self.on_submit(self.selected, self.choices[self.selected])
                    return true
                end
                if keys._MOUSE_L and self:getMousePos() then
                    self.on_submit(self.selected, self.choices[self.selected])
                    return true
                end
                for key in pairs(self.scroll_keys) do
                    if keys[key] then return true end
                end
            end,
        },
    })
    local ZScreen = widget_harness.defclass(nil, widgets.Panel)
    ZScreen.ATTRS{
        initial_pause=true,
        force_pause=false,
        pass_pause=true,
        pass_movement_keys=false,
        pass_mouse_clicks=true,
        defocusable=true,
    }

    ---Marks the controlled screen shown.
    function ZScreen:show()
        self.shown = true
    end

    ---Marks the controlled screen dismissed.
    function ZScreen:dismiss()
        self.dismiss_count = (self.dismiss_count or 0) + 1
    end

    ---Records an intact delegated event table.
    ---@param keys table
    function ZScreen:sendInputToParent(keys)
        table.insert(parent_inputs, keys)
    end

    local gui = {
        ZScreen=ZScreen,
        FRAME_INTERIOR=function()
            return {frame_pen={fg=7, bg=0}, signature_pen=false}
        end,
    }
    local pen = {
        parse=function(source, fg, bg)
            local result = type(source) == 'table' and {
                fg=source.fg,
                bg=source.bg,
            } or {}
            result.fg = fg or result.fg
            result.bg = bg or result.bg
            return result
        end,
    }
    local _, renderer = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/context_menu/renderer.lua', {
            globals={
                defclass=widget_harness.defclass,
                dfhack={pen=pen},
            },
            require_modules={
                gui=gui,
                ['gui.widgets']=widgets,
            },
        })
    local service = {
        factory=nil,
        start_count=0,
        set_presentation_factory=function(self, factory)
            self.factory = factory
        end,
        start=function(self)
            self.start_count = self.start_count + 1
        end,
    }
    local projection = {position=nil}
    local ScreenPosition = {}
    ScreenPosition.__index = ScreenPosition
    local identities = {
        ScreenPosition={
            new=function(position)
                assert.equals('number', type(position.x))
                assert.equals('number', type(position.y))
                return setmetatable({x=position.x, y=position.y},
                    ScreenPosition)
            end,
        },
    }
    local dfhack = {
        pen=pen,
        screen={
            getMousePos=function() return mouse.x, mouse.y end,
        },
    }
    local _, screen_module = module_loader.load(repo_root, SCREEN_PATH, {
        globals={
            defclass=widget_harness.defclass,
            dfhack=dfhack,
        },
        reqscript={
            ['dwarfuicore/map_projection']={
                project_visible=function() return projection.position end,
            },
            ['dwarfuicore/context_menu/renderer']=renderer,
            ['dwarfuicore/service_provider/identity']=identities,
            ['dwarfuicore/context_menu/service']={service=service},
            ['dwarfuicore/context_menu/target']={
                ContextMenuAnchorKind={SCREEN_POSITION=1, MAP_TILE=2},
            },
        },
        require_modules={gui=gui},
    })
    local session = {
        valid=true,
        root={},
        anchor={kind=1, screen_position={x=2, y=2}},
        get_definition_snapshot=function()
            return {
                fg=15,
                bg=0,
                entries={{label='Entry', fg=15, bg=0}},
            }
        end,
        get_anchor_descriptor=function(self)
            return self.anchor
        end,
        get_source_root=function(self) return self.root end,
        is_valid=function(self) return self.valid end,
    }
    local calls = {close=0, select=0, fail=0, map_valid=true}
    local actions = {
        close=function() calls.close = calls.close + 1 end,
        select=function() calls.select = calls.select + 1 end,
        map_session_is_valid=function() return calls.map_valid end,
        fail=function() calls.fail = calls.fail + 1 end,
    }
    local controller = service.factory(session, actions)
    local screen = controller.screen
    screen.frame_body = widget_harness.rect(0, 0, 20, 10)
    screen.menu_window.frame_parent_rect = screen.frame_body
    screen:relayout()
    return {
        module=screen_module,
        service=service,
        controller=controller,
        screen=screen,
        session=session,
        calls=calls,
        mouse=mouse,
        parent_inputs=parent_inputs,
        projection=projection,
        ScreenPosition=ScreenPosition,
    }
end

describe('DwarfUICore context-menu screen', function()
    it('installs the concrete factory and non-pausing screen attributes',
            function()
        local fixture = screen_fixture()
        local screen = fixture.screen

        assert.equals(1, fixture.service.start_count)
        assert.equals('dwarfuicore/context-menu', screen.focus_path)
        assert.is_false(screen.initial_pause)
        assert.is_false(screen.force_pause)
        assert.is_false(screen.pass_pause)
        assert.is_false(screen.pass_movement_keys)
        assert.is_false(screen.pass_mouse_clicks)
        assert.is_false(screen.defocusable)
    end)

    it('shows and closes one native screen exactly once', function()
        local fixture = screen_fixture()
        fixture.controller:show()
        assert.is_true(fixture.screen.shown)
        fixture.controller:close()
        fixture.controller:close()

        assert.is_true(fixture.screen.shown)
        assert.equals(1, fixture.screen.dismiss_count)
    end)

    it('rejects showing a presentation after it is closed', function()
        local fixture = screen_fixture()
        fixture.controller:close()

        assert.has_error(function() fixture.controller:show() end,
            'DwarfUICore context-menu screen is already closed.')
        assert.is_false(not not fixture.screen.shown)
        assert.equals(1, fixture.screen.dismiss_count)
    end)

    it('gives Escape and right-click priority over coalesced selection',
            function()
        local fixture = screen_fixture()
        fixture.screen:onInput{LEAVESCREEN=true, SELECT=true}
        fixture.screen:onInput{_MOUSE_R=true, SELECT=true}

        assert.equals(2, fixture.calls.close)
        assert.equals(0, fixture.calls.select)
        assert.equals(0, #fixture.parent_inputs)
    end)

    it('closes and consumes an outside left-click', function()
        local fixture = screen_fixture()
        fixture.mouse.x, fixture.mouse.y = 19, 9
        fixture.screen:onInput{_MOUSE_L=true, D_PAUSE=true}

        assert.equals(1, fixture.calls.close)
        assert.equals(0, #fixture.parent_inputs)
    end)

    it('consumes inside chrome clicks even when native widgets do not',
            function()
        local fixture = screen_fixture()
        fixture.mouse.x = fixture.screen.menu_window.frame_rect.x1
        fixture.mouse.y = fixture.screen.menu_window.frame_rect.y1
        fixture.screen.menu_window.menu_list.getMousePos =
            function() return nil, nil end
        fixture.screen:onInput{_MOUSE_L=true}

        assert.equals(0, fixture.calls.close)
        assert.equals(0, #fixture.parent_inputs)
    end)

    it('uses normal child routing for menu-owned input', function()
        local fixture = screen_fixture()
        local routed
        fixture.screen.inputToSubviews = function(_, keys)
            routed = keys
            return true
        end
        fixture.screen.menu_window.onInput = function()
            error('menu dispatch bypassed screen child routing')
        end

        fixture.screen:onInput{SELECT=true}

        assert.same({SELECT=true}, routed)
        assert.equals(0, #fixture.parent_inputs)
    end)

    it('selects an entry from native List left-click handling', function()
        local fixture = screen_fixture()
        fixture.mouse.x = fixture.screen.menu_window.frame_body.x1
        fixture.mouse.y = fixture.screen.menu_window.frame_body.y1
        fixture.screen.menu_window.menu_list.getMousePos =
            function() return 0, 0 end
        fixture.screen:onInput{_MOUSE_L=true, D_PAUSE=true}

        assert.equals(1, fixture.calls.select)
        assert.equals(0, #fixture.parent_inputs)
    end)

    it('consumes wheel input inside the complete Window', function()
        local fixture = screen_fixture()
        fixture.mouse.x = fixture.screen.menu_window.frame_rect.x1
        fixture.mouse.y = fixture.screen.menu_window.frame_rect.y1
        fixture.screen:onInput{STANDARDSCROLL_DOWN=true, D_PAUSE=true}

        assert.equals(0, #fixture.parent_inputs)
    end)

    it('delegates outside wheel and down-only tables unchanged', function()
        local fixture = screen_fixture()
        fixture.mouse.x, fixture.mouse.y = 19, 9
        local wheel = {CONTEXT_SCROLL_DOWN=true}
        local down = {_MOUSE_R_DOWN=true}
        fixture.screen:onInput(wheel)
        fixture.screen:onInput(down)

        assert.equals(wheel, fixture.parent_inputs[1])
        assert.equals(down, fixture.parent_inputs[2])
    end)

    it('lets coalesced selection win over outside wheel delegation',
            function()
        local fixture = screen_fixture()
        fixture.mouse.x, fixture.mouse.y = 19, 9
        fixture.screen:onInput{CONTEXT_SCROLL_DOWN=true, SELECT=true}

        assert.equals(1, fixture.calls.select)
        assert.equals(0, #fixture.parent_inputs)
    end)

    it('delegates pause, movement, and irrelevant keyboard unchanged',
            function()
        local fixture = screen_fixture()
        local pause = {D_PAUSE=true}
        local movement = {CURSOR_UP=true}
        local irrelevant = {CUSTOM_KEY=true}
        fixture.screen:onInput(pause)
        fixture.screen:onInput(movement)
        fixture.screen:onInput(irrelevant)

        assert.same({pause, movement, irrelevant}, fixture.parent_inputs)
    end)

    it('uses native List selection and consumes the complete table',
            function()
        local fixture = screen_fixture()
        fixture.screen:onInput{SELECT=true, D_PAUSE=true}

        assert.equals(1, fixture.calls.select)
        assert.equals(0, #fixture.parent_inputs)
    end)

    it('contains owned dispatch failures without forwarding', function()
        local fixture = screen_fixture()
        fixture.screen.menu_window.onInput = function()
            error('controlled dispatch failure')
        end
        fixture.screen:onInput{SELECT=true, D_PAUSE=true}

        assert.equals(1, fixture.calls.fail)
        assert.equals(0, #fixture.parent_inputs)
    end)

    it('delegates irrelevant dispatch failures before disabling', function()
        local fixture = screen_fixture()
        local input = {CUSTOM_KEY=true}
        fixture.screen.menu_window.onInput = function()
            error('controlled irrelevant dispatch failure')
        end
        fixture.screen:onInput(input)

        assert.equals(input, fixture.parent_inputs[1])
        assert.equals(1, fixture.calls.fail)
    end)

    it('delegates classification failures before ownership is established',
            function()
        local fixture = screen_fixture()
        local input = {_MOUSE_L=true}
        fixture.screen.is_pointer_inside = function()
            error('controlled classification failure')
        end
        fixture.screen:onInput(input)

        assert.equals(input, fixture.parent_inputs[1])
        assert.equals(1, fixture.calls.fail)
    end)

    it('requests close when a weak source becomes invalid', function()
        local fixture = screen_fixture()
        fixture.session.valid = false
        fixture.screen:render({})

        assert.equals(1, fixture.calls.close)
    end)

    it('keeps screen anchors fixed and reprojects map anchors each render',
            function()
        local fixture = screen_fixture()
        fixture.session.anchor = {
            kind=1,
            screen_position={x=17, y=2},
        }
        fixture.screen:render({})
        assert.equals(2, fixture.screen.menu_window.anchor.x)

        fixture.screen.anchor = {
            kind=2,
            screen_position={x=2, y=2},
            map_position={x=10, y=20, z=3},
        }
        fixture.projection.position = {x=7, y=4, z=0}
        fixture.screen:render({})
        assert.same({x=7, y=4}, fixture.screen.menu_window.anchor)
        fixture.projection.position = {x=5, y=3, z=0}
        fixture.screen:render({})
        assert.same({x=5, y=3}, fixture.screen.menu_window.anchor)
    end)

    it('copies projected anchors through the screen-position constructor',
            function()
        local fixture = screen_fixture()
        fixture.screen.anchor = {
            kind=2, screen_position={x=2, y=2},
            map_position={x=10, y=20, z=3},
        }
        fixture.projection.position = {x=7, y=4, z=0}

        local anchor = fixture.screen:resolve_anchor()
        fixture.projection.position.x, fixture.projection.position.y = 9, 8

        assert.equals(fixture.ScreenPosition, getmetatable(anchor))
        assert.same({x=7, y=4}, anchor)
    end)

    it('closes a map menu when projection becomes invalid', function()
        local fixture = screen_fixture()
        fixture.screen.anchor = {
            kind=2,
            screen_position={x=2, y=2},
            map_position={x=10, y=20, z=3},
        }
        fixture.projection.position = nil

        fixture.screen:render({})

        assert.equals(1, fixture.calls.close)
    end)

    it('closes a map menu when its registration becomes invalid', function()
        local fixture = screen_fixture()
        fixture.screen.anchor = {
            kind=2,
            screen_position={x=2, y=2},
            map_position={x=10, y=20, z=3},
        }
        fixture.projection.position = {x=4, y=5, z=0}
        fixture.calls.map_valid = false

        fixture.screen:render({})

        assert.equals(1, fixture.calls.close)
    end)

    it('recognizes only roots in its native parent chain', function()
        local fixture = screen_fixture()
        local root = {_native={}}
        local parent = root._native
        fixture.screen._native={parent=parent}

        assert.is_true(fixture.screen:source_root_is_presented(root))
        fixture.screen._native.parent = {}
        assert.is_false(fixture.screen:source_root_is_presented(root))
        fixture.screen._native.parent = {widgets=root}
        root._native = nil
        assert.is_true(fixture.screen:source_root_is_presented(root))
    end)
end)
