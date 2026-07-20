-- Live product contracts for the singleton tooltip service.

local registration = reqscript('dwarfui/tooltip_registration')
local tooltip = reqscript('dwarfui/tooltip')

---Recreates the service in the current UI stack after setting a virtual pointer.
---@param target table
local function restart_service_for_target(target)
    tooltip.unregister(target)
    assert.is_true(tooltip.register(target))
    dy.wait_frames(2)
end

describe('live singleton tooltip service', function()
    local screen

    before_each(function()
        dy.reset()
        screen = dy.show_fixture('tooltip_screen')
    end)

    after_each(function()
        dy.clear_pointer()
        dy.reset()
        dy.wait_frames(2)
    end)

    it('targets normal screens and presents dynamic text after real renders',
            function()
        local target = dy.get(screen, 'tooltip_target')
        local mouse_x, mouse_y = dy.move_pointer_to(target)

        restart_service_for_target(target)

        local diagnostics = registration.get_diagnostics()
        assert.equals(target, diagnostics.target)
        assert.is_true(diagnostics.screen.renderer.visible)
        assert.equals(('Automation dynamic tooltip %d,%d'):format(
            mouse_x - target.frame_body.x1, mouse_y - target.frame_body.y1),
            diagnostics.screen.renderer.tooltip_text)
        assert.equals(diagnostics.screen.frame_parent_rect,
            diagnostics.screen.renderer.frame_parent_rect)
    end)

    it('blocks targets covered by a modal screen through real rendering',
            function()
        dy.dismiss(screen)
        screen = dy.show_fixture('tooltip_screen', {blocker_visible=true})
        local target = dy.get(screen, 'tooltip_target')
        dy.move_pointer_to(target)
        restart_service_for_target(target)
        assert.is_nil(registration.get_diagnostics().target)
        assert.is_false(registration.get_diagnostics().screen.renderer.visible)
    end)

    it('z-order recovery forwards input over a newly opened screen', function()
        local target = dy.get(screen, 'tooltip_target')
        dy.move_pointer_to(target)
        restart_service_for_target(target)
        local diagnostics = registration.get_diagnostics()
        assert.equals(target, diagnostics.target)
        dy.send_input('CUSTOM_A', diagnostics.screen)
        assert.equals('CUSTOM_A', screen.last_key)
        assert.is_false(diagnostics.screen:isMouseOver())

        local cover = dy.show_fixture('cover_screen')
        dy.wait_frames(2)
        assert.is_true(diagnostics.screen:hasFocus())
        dy.dismiss(cover)
    end)
end)
