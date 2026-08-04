-- Real overlay-discovery integration contracts for tooltip input intent.

local tooltip = reqscript('dwarfuicore/services').TooltipServiceProvider:new(
    1, 'test-tooltip-overlay')
local overlay = require('plugins.overlay')

---Returns the product diagnostics registered in tests/dwarfspec/config.lua.
---@return table
local function diagnostics()
    return ds.tooltip_state()
end

---Returns whether diagnostics carry one coherent default service identity.
---@param state table
---@return boolean
local function has_default_identity(state)
    local target_identity = state.target
    local intent_identity = state.intent and state.intent.source_identity
    return target_identity ~= nil and intent_identity ~= nil and
        target_identity.namespace == 'test-tooltip-overlay' and
        intent_identity.namespace == target_identity.namespace and
        intent_identity.local_identity == target_identity.local_identity
end

describe('live tooltip input overlay registration', function()
    local native_subject
    local borrowed_screen
    local overlay_name
    local target_subject
    local widget
    local target
    local original_viewscreens
    local initially_hauling_open

    before_each(function()
        native_subject, borrowed_screen, overlay_name = nil, nil, nil
        target_subject, widget, target, original_viewscreens =
            nil, nil, nil, nil
        initially_hauling_open = nil
        borrowed_screen = assert(dfhack.gui.getDFViewscreen(true),
            'native fortress viewscreen is unavailable')
        native_subject = ds.mountNativeScreen()
        initially_hauling_open = ds.hasFocus('dwarfmode/Hauling')
        if initially_hauling_open then
            ds.input('LEAVESCREEN')
            ds.await('native Hauling menu closes for tooltip coverage',
                function()
                    return ds.hasFocus('dwarfmode/Default')
                end)
        end
        ds.await('prior test-owned tooltip screens release focus', function()
            return ds.hasFocus('dwarfmode/Default')
        end)
        assert.is_true(ds.hasFocus('dwarfmode/Default'))

        local staged = ds.stage_overlay_registration(
            'tests/tooltip/support/tooltip_overlay_registration.lua',
            'tooltip_probe')
        overlay_name = assert(staged.registered_names[1],
            'staged tooltip overlay was not registered')
        ds.redraw()

        target_subject = ds.get('tooltip_target', {
            source='overlay',
            overlay=overlay_name,
        })
        target = target_subject:raw()
        widget = assert(target.parent_view,
            'staged tooltip target has no registered overlay parent')
        original_viewscreens = widget.viewscreens
    end)

    after_each(function()
        if widget then widget.viewscreens = original_viewscreens end
        if target then
            assert.is_true(tooltip:unregister(target))
        end
        if native_subject then
            ds.redraw()
            if target then
                assert.is_nil(diagnostics().target)
            end
        end
        if native_subject and initially_hauling_open then
            ds.input('D_HAULING')
            ds.await('original Hauling menu reopens after tooltip coverage',
                function()
                    return ds.hasFocus('dwarfmode/Hauling')
                end)
        end
    end)

    it('honors real discovery, enablement, and focus eligibility', function()
        assert.is_true(overlay.isOverlayEnabled(overlay_name))
        local target_state = target_subject:inspect()
        assert.is_true(target_state.visible)
        assert.is_true(target_state.active)
        assert.equals('Automation overlay tooltip outside its narrow root.',
            target_state.tooltip)
        local body = assert(target_state.body,
            'registered tooltip target has no rendered bounds')
        local target_x = math.floor((body.x1 + body.x2) / 2)
        local target_y = math.floor((body.y1 + body.y2) / 2)

        -- Exact native-screen pointer placement and a completed redraw prove
        -- selection through the staged registry-owned overlay.
        ds.move_pointer(target_x, target_y)
        ds.redraw()
        ds.await('registered overlay tooltip target selected', function()
            local state = diagnostics()
            return has_default_identity(state) and
                state.intent.text ==
                    'Automation overlay tooltip outside its narrow root.'
        end)

        local state = diagnostics()
        assert.is_nil(state.screen)
        assert.is_nil(state.renderer)
        assert.is_nil(state.overlay)

        -- The staged overlay becomes ineligible solely through its viewscreen
        -- contract while its borrowed backing screen remains unchanged.
        widget.viewscreens = 'title'
        ds.redraw()
        assert.is_equal(borrowed_screen, dfhack.gui.getDFViewscreen(true))
        local ineligible_state = target_subject:inspect()
        assert.equals(target_state.tooltip, ineligible_state.tooltip)
        assert.is_nil(diagnostics().target)
        assert.is_nil(diagnostics().intent)

        widget.viewscreens = original_viewscreens
        ds.redraw()
        ds.move_pointer(target_x, target_y)
        ds.redraw()
        ds.await('focus-eligible tooltip target selected again', function()
            local selected = diagnostics()
            return has_default_identity(selected) and
                selected.intent.text == target_state.tooltip
        end)

        assert.is_true(overlay.overlay_command(
            {'disable', overlay_name}, true))
        ds.redraw()
        assert.is_false(overlay.isOverlayEnabled(overlay_name))
        assert.is_nil(diagnostics().target)
        assert.is_nil(diagnostics().intent)
        assert.is_equal(borrowed_screen, dfhack.gui.getDFViewscreen(true),
            'tooltip overlay dismissed or replaced the native game screen')
    end)
end)
