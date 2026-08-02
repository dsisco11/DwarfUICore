-- Live DwarfUICore reload-generation and process-owner acceptance.

local widgets = require('gui.widgets')

---Asserts one stable public API error category.
---@param callback function
---@param category string
local function assert_api_category(callback, category)
    local ok, failure = pcall(callback)
    assert.is_false(ok)
    assert.equals(('DwarfUICore ContextMenuServiceApi: [%s] '):format(category),
        tostring(failure):sub(1,
            #('DwarfUICore ContextMenuServiceApi: [%s] '):format(category)))
end

describe('live context-menu runtime reload', function()
    it('reconstructs one clean authoritative generation', function()
        local services = reqscript('dwarfuicore/services')
        local api = services.ContextMenuServiceProvider:new(1,
            'runtime-reload-live')
        local handle = api:register_map_tile{
            owner=widgets.Panel{}, pos={x=0, y=0, z=0},
            definition={entries={{label='Reload probe', on_select=function() end}}},
        }

        dfhack.run_command('dwarfuicore', 'reload')
        ds.wait_frames(2)

        local service =
            reqscript('dwarfuicore/context_menu/service').service
        local registrations =
            reqscript('dwarfuicore/context_menu/registration').manager
        local diagnostics = service:get_diagnostics()
        assert.is_true(diagnostics.started)
        assert.is_false(diagnostics.disabled)
        assert.is_false(diagnostics.open)
        assert.equals(0,
            diagnostics.registrations.widget_registration_count)
        assert.equals(0,
            diagnostics.registrations.map_registration_count)
        assert.is_true(registrations:_module_is_current())
        assert.is_function(
            dfhack.onStateChange.dwarfuicore_context_menu)

        assert_api_category(function() api:clear_namespace() end, 'STALE_API')
        local fresh = reqscript('dwarfuicore/services')
            .ContextMenuServiceProvider:new(1, 'runtime-reload-live')
        assert_api_category(function()
            fresh:unregister_map_tile(handle)
        end, 'STALE_HANDLE')
    end)
end)
