-- Live UserPrompt world-lifecycle cancellation and recovery.

---Copies one native coordinate into detached Lua values.
---@param value df.coord
---@return {x: integer, y: integer, z: integer}
local function copy_coord(value)
    return {x=value.x, y=value.y, z=value.z}
end

---Returns whether one failure has the expected public API category.
---@param failure any
---@param category string
---@return boolean matches
local function has_api_category(failure, category)
    local prefix = ('DwarfUICore UserPromptServiceApi: [%s] ')
        :format(category)
    return tostring(failure):sub(1, #prefix) == prefix
end

describe('live UserPrompt lifecycle', function()
    it('cancels before world-unload callbacks and restores availability',
            function()
        local native_subject
        local handle
        local replacement
        local indicator
        local original_indicator
        local callback_count = 0
        local callback_failure
        local prompt_api
        local prompt_service
        local prompt_module
        local input_manager
        local presenter
        local ok, failure = xpcall(function()
            ds.mountSaveGame('TestWorld 01')
            native_subject = ds.mountNativeScreen()
            dfhack.run_command('dwarfuicore', 'reload')
            ds.wait_frames(2)
            prompt_api = reqscript('dwarfuicore/services')
                .UserPromptServiceProvider:new(
                    1, 'test-user-prompt-lifecycle')
            prompt_module = reqscript('dwarfuicore/user_prompt/service')
            prompt_service = prompt_module.service
            input_manager =
                reqscript('dwarfuicore/context_menu/input_hook').manager
            presenter =
                reqscript('dwarfuicore/tooltip/runtime').presenter
            indicator = assert(
                df.global.game.main_interface.recenter_indicator_m,
                'native recenter indicator is unavailable')
            original_indicator = copy_coord(indicator)

            handle = prompt_api:prompt_map_location{
                title='Lifecycle',
                message='Awaiting cancellation',
                on_select=function() end,
                on_cancel=function()
                    callback_count = callback_count + 1
                    local admitted, rejection = pcall(function()
                        prompt_api:prompt_map_location{
                            title='Invalid reentry',
                            message='World transition is still active',
                            on_select=function() end,
                        }
                    end)
                    assert.is_false(admitted)
                    callback_failure = rejection
                end,
            }
            ds.redraw()
            ds.await('prompt owns input and presentation', function()
                return input_manager:get_diagnostics()
                        .priority_consumer_active and
                    presenter:get_diagnostics()
                        .authoritative_intent_active
            end)

            local state_callback = assert(
                dfhack.onStateChange.dwarfuicore_user_prompt,
                'UserPrompt world-lifecycle callback is unavailable')
            state_callback(SC_WORLD_UNLOADED)
            ds.redraw()

            assert.equals(1, callback_count)
            assert.is_true(has_api_category(
                callback_failure, 'SERVICE_UNHEALTHY'))
            assert.is_false(prompt_api:is_active(handle))
            handle = nil
            local diagnostics = prompt_service:get_diagnostics()
            assert.is_false(diagnostics.active)
            assert.equals(prompt_module.UserPromptTerminalCause.WORLD_UNLOAD,
                diagnostics.last_terminal_cause)
            assert.is_false(input_manager:get_diagnostics()
                .priority_consumer_active)
            assert.is_false(presenter:get_diagnostics()
                .authoritative_intent_active)
            assert.is_false(presenter:get_diagnostics().tooltip_suppressed)
            assert.same(original_indicator, copy_coord(indicator))

            replacement = prompt_api:prompt_map_location{
                title='Recovered',
                message='Lifecycle boundary completed',
                on_select=function() end,
            }
            assert.is_true(prompt_api:is_active(replacement))
            assert.is_true(prompt_api:cancel(replacement))
            replacement = nil
        end, debug.traceback)

        if replacement and prompt_api then pcall(function()
            prompt_api:cancel(replacement)
        end) end
        if handle and prompt_api then pcall(function()
            prompt_api:cancel(handle)
        end) end
        if indicator and original_indicator then
            indicator.x = original_indicator.x
            indicator.y = original_indicator.y
            indicator.z = original_indicator.z
        end
        assert.is_true(ok, failure)
    end)
end)
