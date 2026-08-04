-- Live UserPrompt generation retirement and clean reconstruction.

---Asserts one stable public UserPrompt API error category.
---@param callback function
---@param category string
local function assert_api_category(callback, category)
    local ok, failure = pcall(callback)
    assert.is_false(ok)
    local prefix = ('DwarfUICore UserPromptServiceApi: [%s] ')
        :format(category)
    assert.equals(prefix, tostring(failure):sub(1, #prefix))
end

describe('live UserPrompt runtime reload', function()
    it('retires active ownership and reconstructs one clean generation',
            function()
        local native_subject
        local old_api
        local old_handle
        local fresh_handle
        local indicator
        local original_indicator
        local callback_count = 0
        local callback_failure
        local ok, failure = xpcall(function()
            ds.mountSaveGame('TestWorld 01')
            native_subject = ds.mountNativeScreen()
            dfhack.run_command('dwarfuicore', 'reload')
            ds.wait_frames(2)
            indicator = assert(
                df.global.game.main_interface.recenter_indicator_m,
                'native recenter indicator is unavailable')
            original_indicator = {
                x=indicator.x, y=indicator.y, z=indicator.z,
            }

            old_api = reqscript('dwarfuicore/services')
                .UserPromptServiceProvider:new(
                    1, 'test-user-prompt-reload')
            old_handle = old_api:prompt_map_location{
                title='Reload',
                message='Retire this request',
                on_select=function() end,
                on_cancel=function()
                    callback_count = callback_count + 1
                    local admitted, rejection = pcall(function()
                        old_api:prompt_map_location{
                            title='Invalid reentry',
                            message='Runtime is retiring',
                            on_select=function() end,
                        }
                    end)
                    assert.is_false(admitted)
                    callback_failure = rejection
                end,
            }
            ds.redraw()
            ds.await('prompt is active before reload', function()
                return reqscript('dwarfuicore/user_prompt/service').service
                    :has_active_prompt()
            end)

            dfhack.run_command('dwarfuicore', 'reload')
            ds.wait_frames(2)

            assert.equals(1, callback_count)
            assert_api_category(function() error(callback_failure, 0) end,
                'SERVICE_UNHEALTHY')
            assert_api_category(function()
                old_api:get_contract_version()
            end, 'STALE_API')

            local fresh_api = reqscript('dwarfuicore/services')
                .UserPromptServiceProvider:new(
                    1, 'test-user-prompt-reload')
            assert_api_category(function()
                fresh_api:is_active(old_handle)
            end, 'STALE_HANDLE')
            old_handle = nil

            local service =
                reqscript('dwarfuicore/user_prompt/service').service
            local presenter =
                reqscript('dwarfuicore/tooltip/runtime').presenter
            local input_manager =
                reqscript('dwarfuicore/context_menu/input_hook').manager
            assert.is_false(service:get_diagnostics().active)
            assert.is_false(input_manager:get_diagnostics()
                .priority_consumer_active)
            assert.is_false(presenter:get_diagnostics()
                .authoritative_intent_active)
            assert.is_false(presenter:get_diagnostics().tooltip_suppressed)
            assert.same(original_indicator, {
                x=indicator.x, y=indicator.y, z=indicator.z,
            })
            assert.is_function(
                dfhack.onStateChange.dwarfuicore_user_prompt)

            local hook = input_manager:get_diagnostics()
            assert.is_true(hook.context_consumer_installed)
            assert.is_false(hook.priority_consumer_prepared)
            fresh_handle = fresh_api:prompt_map_location{
                title='Fresh generation',
                message='New prompt remains usable',
                on_select=function() end,
            }
            assert.is_true(fresh_api:is_active(fresh_handle))
            assert.is_true(fresh_api:cancel(fresh_handle))
            fresh_handle = nil
        end, debug.traceback)

        if fresh_handle then pcall(function()
            local api = reqscript('dwarfuicore/services')
                .UserPromptServiceProvider:new(
                    1, 'test-user-prompt-reload')
            api:cancel(fresh_handle)
        end) end
        if old_handle and old_api then
            pcall(function() old_api:cancel(old_handle) end)
        end
        if indicator and original_indicator then
            indicator.x = original_indicator.x
            indicator.y = original_indicator.y
            indicator.z = original_indicator.z
        end
        assert.is_true(ok, failure)
    end)
end)
