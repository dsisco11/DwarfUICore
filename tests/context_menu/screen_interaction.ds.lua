-- Lua-screen input-hook, lifecycle, and screen-stack context-menu acceptance.

local gui = require('gui')
local widgets = require('gui.widgets')
local context_menu = reqscript('dwarfuicore/context_menu/api')
local services = reqscript('dwarfuicore/context_menu/service')
local PointerPolicy =
    reqscript('dwarfuicore/pointer').PointerPolicy

---@class tests.ContextMenuSourceScreen: gui.ZScreen
local ContextMenuSourceScreen = defclass(nil, gui.ZScreen)
ContextMenuSourceScreen.ATTRS{
    focus_path='dwarfspec/context-menu-source',
    initial_pause=false,
}

---Builds the registered source widget and input observations.
function ContextMenuSourceScreen:init()
    self.input_events = {}
    self.context_target = widgets.Panel{
        view_id='context_target',
        pointer_policy=PointerPolicy.TARGET,
        frame={l=8, t=6, w=18, h=3},
        subviews={
            widgets.Label{
                frame={l=1, t=1},
                text='Lua target',
            },
        },
    }
    self:addviews{self.context_target}
end

---Records input that passes through the context-menu opening hook.
---@param keys table
---@return boolean
function ContextMenuSourceScreen:onInput(keys)
    local copied = {}
    for key, value in pairs(keys) do copied[key] = value end
    table.insert(self.input_events, copied)
    self:sendInputToParent(keys)
    return true
end

---@class tests.ContextMenuUpperScreen: gui.ZScreen
local ContextMenuUpperScreen = defclass(nil, gui.ZScreen)
ContextMenuUpperScreen.ATTRS{
    focus_path='dwarfspec/context-menu-upper',
    initial_pause=false,
}

---Initializes input observations for the upper screen.
function ContextMenuUpperScreen:init()
    self.input_count = 0
end

---Consumes input as the naturally current upper screen.
---@param _keys table
---@return boolean
function ContextMenuUpperScreen:onInput(_keys)
    self.input_count = self.input_count + 1
    return true
end

---Returns the active production context-menu screen.
---@return dwarfui.ContextMenuScreen
local function menu_screen()
    return assert(services.service._state.presentation.screen,
        'context-menu screen is unavailable')
end

---Feeds one input table through the current viewscreen.
---@param keys table
local function feed_current(keys)
    gui.simulateInput(dfhack.gui.getCurViewscreen(), keys)
    ds.redraw()
end

---Returns one immutable definition for the Lua source target.
---@param handler function
---@return table
local function definition(handler)
    return {
        title='Lua actions',
        entries={{
            label='Invoke',
            on_select=handler,
        }},
    }
end

describe('Lua-screen context menu', function()
    it('uses the instance seam and respects later screen priority', function()
        local source_subject
        local source
        local target
        local upper
        local upper_render_spy
        local ephemeral
        local initial_pause = ds.isGamePaused()
        local selections = 0
        local last_context
        local ok, failure = xpcall(function()
            ds.mountSaveGame('TestWorld 01')
            services.service:clear_world_state()
            source_subject = ds.mount(ContextMenuSourceScreen, {
                initial_pause=false,
            })
            source = source_subject:raw()
            target = source.context_target
            context_menu.register(target, definition(function(context)
                selections = selections + 1
                last_context = context
            end))
            ds.redraw()
            ds.await('Lua-screen input hook is installed', function()
                local diagnostics =
                    services.service:get_diagnostics().hook
                return diagnostics.screen_hook_count == 1
            end)
            local body = target.frame_body
            local x = math.floor((body.x1 + body.x2) / 2)
            local y = math.floor((body.y1 + body.y2) / 2)

            ds.move_pointer(x, y)
            ds.input({_MOUSE_R_DOWN=true}, source_subject)
            assert.is_false(services.service:is_open())
            assert.is_true(
                source.input_events[#source.input_events]._MOUSE_R_DOWN)

            local input_count = #source.input_events
            ds.input({
                _MOUSE_R=true,
                _MOUSE_R_DOWN=true,
            }, source_subject)
            ds.await('Lua-screen context menu opens', function()
                return services.service:is_open()
            end)
            assert.equals(input_count, #source.input_events,
                'owned Lua-screen right-click reached its predecessor')
            local opened = menu_screen()
            local fixed_anchor = {
                x=opened.anchor.screen_position.x,
                y=opened.anchor.screen_position.y,
            }
            assert.same({x=x, y=y}, fixed_anchor)

            upper = ContextMenuUpperScreen{}
            upper:show()
            assert.is_equal(upper._native, dfhack.gui.getCurViewscreen())
            assert.is_equal(opened._native, upper._native.parent,
                'upper screen is not stacked above the context menu')
            upper_render_spy = spy.on(upper, 'render')
            ds.redraw()
            assert.spy(upper_render_spy).was_called()
            upper_render_spy:revert()
            upper_render_spy = nil
            gui.simulateInput(dfhack.gui.getCurViewscreen(), {
                D_PAUSE=true,
            })
            dfhack.screen.invalidate()
            ds.wait_frames(2)
            assert.equals(1, upper.input_count)
            assert.is_true(services.service:is_open(),
                'upper screen dismissed the covered context menu')
            upper:dismiss()
            upper = nil
            ds.wait_frames(1)
            assert.is_equal(opened._native, dfhack.gui.getCurViewscreen())
            assert.same(fixed_anchor, opened.anchor.screen_position)

            feed_current{SELECT=true}
            assert.is_false(services.service:is_open())
            assert.equals(1, selections)
            assert.is_equal(target, last_context.source)
            assert.is_not_nil(last_context.source_root)

            local caller_definition = definition(function(context)
                selections = selections + 1
                last_context = context
            end)
            caller_definition.title = 'Original title'
            caller_definition.entries[1].label = 'Original entry'
            assert.is_true(context_menu.update(target, caller_definition))
            caller_definition.title = 'Mutated title'
            caller_definition.entries[1].label = 'Mutated entry'
            ds.move_pointer(x, y)
            ds.input({_MOUSE_R=true}, source_subject)
            ds.await('snapshot menu opens', function()
                return services.service:is_open()
            end)
            local snapshot_menu = menu_screen()
            assert.equals('Original title',
                snapshot_menu.menu_window.definition.title)
            assert.equals('Original entry',
                snapshot_menu.menu_window.definition.entries[1].label)
            caller_definition.title = 'Mutated while open'
            caller_definition.entries[1].label = 'Mutated while open'
            ds.redraw()
            assert.equals('Original title',
                snapshot_menu.menu_window.definition.title)
            assert.equals('Original entry',
                snapshot_menu.menu_window.definition.entries[1].label)
            feed_current{LEAVESCREEN=true}

            local failing_calls = 0
            local handler_failure_count =
                services.service:get_diagnostics().handler_failure_count
            assert.is_true(context_menu.update(target, definition(
                function()
                    failing_calls = failing_calls + 1
                    error('expected selection failure')
                end)))
            ds.move_pointer(x, y)
            ds.input({_MOUSE_R=true}, source_subject)
            ds.await('handler-failure menu opens', function()
                return services.service:is_open()
            end)
            feed_current{SELECT=true}
            assert.equals(1, failing_calls)
            assert.is_false(services.service:is_open())
            assert.is_false(services.service:is_disabled())
            assert.equals(handler_failure_count + 1,
                services.service:get_diagnostics().handler_failure_count)

            assert.is_true(context_menu.update(target, definition(
                function(context)
                    selections = selections + 1
                    last_context = context
                end)))
            ds.move_pointer(x, y)
            ds.input({_MOUSE_R=true}, source_subject)
            ds.await('menu reopens after handler failure', function()
                return services.service:is_open()
            end)
            feed_current{LEAVESCREEN=true}

            ephemeral = widgets.Panel{
                frame={l=30, t=6, w=8, h=3},
                pointer_policy=PointerPolicy.TARGET,
            }
            source:addviews{ephemeral}
            source:updateLayout()
            local ephemeral_handler_calls = 0
            context_menu.register(ephemeral, {
                entries={{
                    label='Disposable',
                    on_select=function()
                        ephemeral_handler_calls =
                            ephemeral_handler_calls + 1
                    end,
                }},
            })
            ds.redraw()
            local ephemeral_body = ephemeral.frame_body
            local ephemeral_x = math.floor(
                (ephemeral_body.x1 + ephemeral_body.x2) / 2)
            local ephemeral_y = math.floor(
                (ephemeral_body.y1 + ephemeral_body.y2) / 2)
            ds.move_pointer(ephemeral_x, ephemeral_y)
            local open_count =
                services.service:get_diagnostics().open_count
            ds.input({_MOUSE_R=true}, source_subject)
            assert.equals(open_count + 1,
                services.service:get_diagnostics().open_count,
                'disposable target input did not open synchronously')
            ds.await('disposable source menu opens', function()
                return services.service:is_open()
            end)
            for index, view in ipairs(source.subviews) do
                if view == ephemeral then
                    table.remove(source.subviews, index)
                    break
                end
            end
            for index, view in ipairs(source.focus_group) do
                if view == ephemeral then
                    table.remove(source.focus_group, index)
                    break
                end
            end
            ephemeral.parent_view = nil
            ephemeral = nil
            collectgarbage('collect')
            collectgarbage('collect')
            ds.redraw()
            ds.await('weak source invalidation closes menu', function()
                return not services.service:is_open()
            end)
            assert.equals(0, ephemeral_handler_calls)
        end, debug.traceback)

        if upper_render_spy then upper_render_spy:revert() end
        if upper then upper:dismiss() end
        if services.service:is_open() then services.service:close() end
        if target then context_menu.unregister(target) end
        if ephemeral then context_menu.unregister(ephemeral) end
        services.service:clear_world_state()
        if initial_pause ~= ds.isGamePaused() then
            ds.setGamePaused(initial_pause)
        end
        assert.is_true(ok, failure)
    end)
end)
