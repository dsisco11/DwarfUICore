local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, adapters = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/tooltip_target.lua')

describe('DwarfUI normalized tooltip targets', function()
    it('exports distinct numeric target and observation enums', function()
        assert.equals('number',
            type(adapters.TooltipTargetKind.WIDGET))
        assert.equals('number',
            type(adapters.TooltipTargetKind.MAP_TILE))
        assert.is_not_equal(adapters.TooltipTargetKind.WIDGET,
            adapters.TooltipTargetKind.MAP_TILE)
        assert.equals('number',
            type(adapters.TooltipPointerObservationKind.TARGET))
        assert.equals('number',
            type(adapters.TooltipPointerObservationKind.BLOCKED))
        assert.equals('number',
            type(adapters.TooltipPointerObservationKind.MISS))
        assert.is_not_equal(
            adapters.TooltipPointerObservationKind.TARGET,
            adapters.TooltipPointerObservationKind.BLOCKED)
        assert.is_not_equal(
            adapters.TooltipPointerObservationKind.TARGET,
            adapters.TooltipPointerObservationKind.MISS)
        assert.is_not_equal(
            adapters.TooltipPointerObservationKind.BLOCKED,
            adapters.TooltipPointerObservationKind.MISS)
    end)

    it('adapts widgets with stable identity and unchanged callback order',
            function()
        local events = {}
        local registrations = {}
        local root = {}
        local widget = {
            tooltip='Widget',
            on_pointer_enter=function(_, x, y)
                table.insert(events, ('enter:%d,%d'):format(x, y))
            end,
            on_pointer_update=function(_, x, y)
                table.insert(events, ('update:%d,%d'):format(x, y))
            end,
            on_pointer_leave=function()
                table.insert(events, 'leave')
            end,
        }
        registrations[widget] = {sequence=1}

        local target = adapters.adapt_widget(
            widget, root, registrations)
        target:on_pointer_enter(2, 3)
        target:on_pointer_update(4, 5)
        target:on_pointer_leave()

        assert.is_true(adapters.is_adapter(target))
        assert.is_equal(widget, target:get_identity())
        assert.equals(adapters.TooltipTargetKind.WIDGET,
            target:get_kind())
        assert.is_equal(root, target:get_source_root())
        assert.equals('Widget', target:get_tooltip())
        assert.same({'enter:2,3', 'update:4,5', 'leave'}, events)
        registrations[widget] = nil
        assert.is_false(target:is_current())
    end)

    it('adapts map handles without adding widget fields or callbacks',
            function()
        local root = {}
        local handle = {}
        local current = true
        local text = 'Map'
        local registry = {
            contains=function(_, candidate)
                return current and candidate == handle
            end,
            get_tooltip=function(_, candidate)
                return candidate == handle and text or nil
            end,
        }
        local target = adapters.adapt_map_tile({
            kind=adapters.TooltipPointerObservationKind.TARGET,
            identity=handle,
            source_root=root,
        }, registry)

        assert.is_equal(handle, target:get_identity())
        assert.equals(adapters.TooltipTargetKind.MAP_TILE,
            target:get_kind())
        assert.is_equal(root, target:get_source_root())
        assert.equals('Map', target:get_tooltip())
        assert.is_nil(handle.tooltip)
        assert.is_nil(handle.on_pointer_enter)
        text = 'Updated'
        assert.equals('Updated', target:get_tooltip())
        target:on_pointer_enter(nil, nil)
        target:on_pointer_update(nil, nil)
        target:on_pointer_leave()
        current = false
        assert.is_false(target:is_current())
    end)
end)
