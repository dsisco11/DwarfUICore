local widgets = require('gui.widgets')

---Returns every enumerable key from one public proxy.
---@param value table
---@return string[] keys
local function keys(value)
    local result = {}
    for key in pairs(value) do table.insert(result, key) end
    return result
end

---Asserts one public API error category without relying on diagnostic detail.
---@param callback function
---@param category string
local function assert_context_category(callback, category)
    local ok, failure = pcall(callback)
    assert.is_false(ok)
    assert.equals(('DwarfUICore ContextMenuServiceApi: [%s] '):format(category),
        tostring(failure):sub(1,
            #('DwarfUICore ContextMenuServiceApi: [%s] '):format(category)))
end

---Asserts the exact visible methods on one immutable API proxy.
---@param api table
---@param names string[]
local function assert_methods(api, names)
    for _, name in ipairs(names) do assert.is_function(api[name]) end
    for _, name in ipairs({'close', 'release', 'get_diagnostics', 'get'}) do
        assert.is_nil(api[name])
    end
end

describe('live service-provider contract', function()
    it('constructs distinct immutable namespace APIs over shared backends',
            function()
        local core = reqscript('dwarfuicore')
        assert.same({}, keys(core.services))
        assert.is_nil(core.services.get_diagnostics)

        local tooltip_provider = core.services.TooltipServiceProvider
        local context_provider = core.services.ContextMenuServiceProvider
        assert.same({}, keys(tooltip_provider))
        assert.same({}, keys(context_provider))

        local tooltip_first = tooltip_provider:new(1, 'provider-live')
        local tooltip_second = tooltip_provider:new(1, 'provider-live')
        local context = context_provider:new(1, 'provider-live')
        assert.is_true(tooltip_first ~= tooltip_second)
        assert.equals(1, tooltip_first:get_contract_version())
        assert.equals('provider-live', tooltip_first:get_namespace())
        assert.equals(1, context:get_contract_version())
        assert.equals('provider-live', context:get_namespace())
        assert.is_nil(tooltip_first.get_diagnostics)
        assert.is_nil(context.close)
        assert_methods(tooltip_first, {'get_contract_version', 'get_namespace',
            'register', 'unregister', 'register_map_tile', 'update_map_tile',
            'unregister_map_tile', 'clear_namespace'})
        assert_methods(context, {'get_contract_version', 'get_namespace',
            'register', 'update', 'unregister', 'register_map_tile',
            'update_map_tile', 'unregister_map_tile', 'clear_namespace'})
        assert.is_false(tooltip_first:clear_namespace())
        assert.is_false(context:clear_namespace())
    end)

    it('keeps registrations alive after an API object is collected', function()
        local core = reqscript('dwarfuicore')
        local provider = core.services.ContextMenuServiceProvider
        local namespace = 'provider-api-collection'
        local api = provider:new(1, namespace)
        local widget = widgets.Panel{}
        local registration = reqscript('dwarfuicore/context_menu/registration')

        local initial = registration.manager:get_diagnostics()
        assert_context_category(function()
            api:register({}, {entries={{label='Invalid', on_select=function() end}}})
        end, 'INVALID_ARGUMENT')
        assert.is_false(api:update(widget, {entries={{label='Absent',
            on_select=function() end}}}))
        assert.is_true(api:register(widget, {entries={{label='Keep',
            on_select=function() end}}}))
        assert.is_false(api:register(widget, {entries={{label='Repeat',
            on_select=function() end}}}))
        local tooltip = core.services.TooltipServiceProvider:new(1, namespace)
        assert.is_true(tooltip:register(widget))
        local before = registration.manager:get_diagnostics()
        assert.equals(initial.widget_registration_count + 1,
            before.widget_registration_count)
        api = nil
        collectgarbage('collect')
        collectgarbage('collect')

        local after = registration.manager:get_diagnostics()
        assert.equals(before.widget_registration_count,
            after.widget_registration_count)
        assert.equals(before.map_registration_count,
            after.map_registration_count)
        local replacement = provider:new(1, namespace)
        assert.is_true(replacement:unregister(widget))
        assert.is_false(replacement:unregister(widget))
        assert.is_true(tooltip:unregister(widget))
    end)
end)
