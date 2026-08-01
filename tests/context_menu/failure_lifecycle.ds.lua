-- Live failure containment, reload reset, and retained-owner inspection.

local gui = require('gui')

local OVERLAY_SOURCE =
    'tests/context_menu/support/context_menu_overlay_registration.lua'
local PROCESS_STATE_SLOT = 'context_menu_component_probe'

---Returns the current-generation public API.
---@return table
local function api()
    return reqscript('dwarfuicore/context_menu/api')
end

---Returns the current-generation service.
---@return dwarfui.ContextMenuService
local function service()
    return reqscript('dwarfuicore/context_menu/service').service
end

---Returns the current-generation registration manager.
---@return dwarfui.ContextMenuRegistrationManager
local function registrations()
    return reqscript('dwarfuicore/context_menu/registration').manager
end

---Returns a simple definition used after destructive reload.
---@return table
local function definition()
    return {
        entries={{
            label='Failure probe',
            on_select=function() end,
        }},
    }
end

---Returns the test-owned backing-input state.
---@return table
local function probe()
    return assert(dfhack.dwarfuicore[PROCESS_STATE_SLOT],
        'context-menu failure probe state is unavailable')
end

---Reloads the complete DwarfUICore generation and returns its unregistered target.
---@return any
local function reload_clean()
    dfhack.run_command('dwarfuicore', 'reload')
    ds.wait_frames(2)
    local diagnostics = service():get_diagnostics()
    assert.is_true(
        diagnostics.started and not diagnostics.disabled and
            not diagnostics.open and
            diagnostics.registrations.widget_registration_count == 0 and
            diagnostics.registrations.map_registration_count == 0,
        ('reload was not clean: started=%s disabled=%s open=%s ' ..
            'widgets=%s maps=%s error=%s'):format(
                tostring(diagnostics.started),
                tostring(diagnostics.disabled),
                tostring(diagnostics.open),
                tostring(diagnostics.registrations
                    .widget_registration_count),
                tostring(diagnostics.registrations
                    .map_registration_count),
                tostring(diagnostics.last_error)))
    return assert(probe().context_target,
        'reload did not recreate the failure probe target')
end

describe('live context-menu failure lifecycle', function()
    it('contains failures and reloads to a transparent clean generation',
            function()
        local native_subject
        local target
        local initially_hauling_open
        local sampler
        local original_capture
        local hook_state
        local original_hook_handler
        local original_discover
        local ok, failure = xpcall(function()
            ds.mountSaveGame('TestWorld 01')
            service():clear_world_state()
            native_subject = ds.mountNativeScreen()
            initially_hauling_open = ds.hasFocus('dwarfmode/Hauling')
            if initially_hauling_open then
                ds.input('LEAVESCREEN')
                ds.await('Hauling closes for failure coverage',
                    function() return ds.hasFocus('dwarfmode/Default') end)
            end
            local staged = ds.stage_overlay_registration(
                OVERLAY_SOURCE, 'context_menu_failure')
            local overlay_name = assert(staged.registered_names[1],
                'failure probe overlay was not registered')
            ds.redraw()
            target = ds.get('context_target', {
                source='overlay',
                overlay=overlay_name,
            }):raw()
            assert.is_true(api().register(target, definition()))
            ds.await('failure probe context-menu input hook is ready',
                function()
                    local diagnostics = service():get_diagnostics()
                    return diagnostics.registrations
                            .widget_registration_count == 1 and
                        diagnostics.hook.native_tracked and
                        diagnostics.hook.handler_installed
                end)
            local body = target.frame_body
            local x = math.floor((body.x1 + body.x2) / 2)
            local y = math.floor((body.y1 + body.y2) / 2)
            probe().inputs = {}

            sampler = service()._sampler
            original_capture = sampler.capture
            sampler.capture = function()
                error('expected pre-ownership sample failure')
            end
            ds.move_pointer(x, y)
            local backing_before = #probe().inputs
            ds.input({_MOUSE_R=true, _MOUSE_R_DOWN=true})
            ds.await('pre-ownership failure disables generation', function()
                return service():is_disabled()
            end)
            assert.is_false(service():is_open())
            assert.equals(backing_before + 1, #probe().inputs,
                'pre-ownership failure did not delegate unchanged')
            assert.is_true(probe().inputs[#probe().inputs]._MOUSE_R)
            assert.is_true(
                probe().inputs[#probe().inputs]._MOUSE_R_DOWN)
            assert.equals('opening resolution',
                service():get_diagnostics().last_failure.stage)

            local transparent_before = #probe().inputs
            ds.input({_MOUSE_R=true, _MOUSE_R_DOWN=true})
            assert.equals(transparent_before + 1, #probe().inputs)
            assert.is_true(
                probe().inputs[#probe().inputs]._MOUSE_R_DOWN)
            sampler.capture = original_capture
            original_capture = nil

            target = reload_clean()
            assert.is_true(api().register(target, definition()))
            ds.redraw()
            ds.await('native hook is installed for hook-failure coverage',
                function()
                    return service():get_diagnostics().hook.native_tracked
                end)
            hook_state = service()._input_hook._state
            original_hook_handler = hook_state.handler
            hook_state.handler = function()
                error('expected input-hook dispatch failure')
            end
            local hook_backing_before = #probe().inputs
            ds.input({_MOUSE_R=true, _MOUSE_R_DOWN=true})
            ds.await('input-hook failure disables generation', function()
                return service():is_disabled()
            end)
            assert.equals(hook_backing_before + 1, #probe().inputs,
                'pre-ownership hook failure did not delegate unchanged')
            assert.is_true(probe().inputs[#probe().inputs]._MOUSE_R)
            assert.is_true(
                probe().inputs[#probe().inputs]._MOUSE_R_DOWN)
            assert.equals('input hook',
                service():get_diagnostics().last_failure.stage)
            assert.equals(1,
                service():get_diagnostics().hook.failure_count)
            hook_state.handler = original_hook_handler
            original_hook_handler = nil

            target = reload_clean()
            assert.is_true(api().register(target, definition()))
            ds.redraw()
            ds.move_pointer(x, y)
            ds.input({_MOUSE_R=true})
            ds.await('post-ownership failure menu opens', function()
                return service():is_open()
            end)
            local screen = service()._state.presentation.screen
            local original_on_input = screen.menu_window.onInput
            screen.menu_window.onInput = function()
                error('expected owned screen-input failure')
            end
            local owned_backing_before = #probe().inputs
            gui.simulateInput(dfhack.gui.getCurViewscreen(), {
                SELECT=true,
                D_PAUSE=true,
            })
            ds.redraw()
            assert.is_false(service():is_open())
            assert.is_true(service():is_disabled())
            assert.equals(owned_backing_before, #probe().inputs,
                'post-ownership input failure leaked to backing UI')
            assert.equals('screen input',
                service():get_diagnostics().last_failure.stage)
            screen.menu_window.onInput = original_on_input

            target = reload_clean()
            assert.is_true(api().register(target, definition()))
            ds.redraw()
            ds.move_pointer(x, y)
            ds.input({_MOUSE_R=true})
            ds.await('render-failure menu opens', function()
                return service():is_open()
            end)
            local render_screen =
                service()._state.presentation.screen
            render_screen.relayout = function()
                error('expected screen-render failure')
            end
            ds.redraw()
            ds.await('render failure disables generation', function()
                return service():is_disabled()
            end)
            assert.is_false(service():is_open())
            assert.equals('screen render',
                service():get_diagnostics().last_failure.stage)

            target = reload_clean()
            local manager = registrations()
            original_discover = manager._discover_attachment_roots
            manager._discover_attachment_roots = function()
                error('expected discovery failure')
            end
            assert.is_true(api().register(target, definition()))
            ds.await('discovery failure disables context handling',
                function() return service():is_disabled() end)
            local diagnostics = service():get_diagnostics()
            assert.equals('root discovery',
                diagnostics.last_failure.stage)
            assert.is_true(diagnostics.registrations.discovery.failed)
            assert.is_false(diagnostics.registrations.discovery.running)
            assert.is_false(diagnostics.registrations.discovery.scheduled)
            manager._discover_attachment_roots = original_discover
            original_discover = nil

            target = reload_clean()
            local clean = service():get_diagnostics()
            assert.is_false(clean.open)
            assert.is_false(clean.disabled)
            assert.equals(0,
                clean.registrations.widget_registration_count)
            assert.equals(0,
                clean.registrations.map_registration_count)
            assert.is_false(clean.registrations.discovery.running)
            assert.is_false(clean.registrations.discovery.scheduled)
            assert.is_false(clean.hook.native_tracked)
            assert.equals(0, clean.hook.screen_hook_count)
            assert.is_function(
                dfhack.onStateChange.dwarfuicore_context_menu)
            assert.is_false(
                ds.hasFocus('dfhack/lua/dwarfuicore/context-menu'))
        end, debug.traceback)

        if sampler and original_capture then
            sampler.capture = original_capture
        end
        if hook_state and original_hook_handler then
            hook_state.handler = original_hook_handler
        end
        if original_discover then
            registrations()._discover_attachment_roots =
                original_discover
        end
        if service():is_open() then service():close() end
        service():clear_world_state()
        if native_subject and initially_hauling_open and
                not ds.hasFocus('dwarfmode/Hauling') then
            ds.input('D_HAULING')
            ds.await('original Hauling screen returns',
                function() return ds.hasFocus('dwarfmode/Hauling') end)
        end
        assert.is_true(ok, failure)
    end)
end)
