local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local _, class_helpers = module_loader.load(
    repo_root, 'src/scripts_modinstalled/dwarfuicore/class.lua')

describe('DwarfUICore DFHack Lua class helpers', function()
    it('follows the production instance-metatable and super chain', function()
        local widgets = widget_harness.widgets()
        local label = widgets.Label{}

        assert.is_equal(widgets.Label, getmetatable(label))
        assert.is_equal(widgets.Widget, rawget(widgets.Label, 'super'))
        assert.is_true(class_helpers.is_instance_of(label, widgets.Label))
        assert.is_true(class_helpers.is_instance_of(label, widgets.Widget))
        assert.is_false(class_helpers.is_instance_of(label, widgets.Panel))
    end)

    it('does not reinterpret a wrapper metatable as a DFHack class',
            function()
        local widgets = widget_harness.widgets()
        local wrapped = setmetatable({}, {__index=widgets.Label})

        assert.is_false(class_helpers.is_instance_of(
            wrapped, widgets.Label))
        assert.is_false(class_helpers.is_instance_of(
            wrapped, widgets.Widget))
    end)

    it('rejects invalid values and terminates malformed inheritance cycles',
            function()
        local cyclic = {}
        cyclic.super = cyclic
        local value = setmetatable({}, cyclic)

        assert.is_false(class_helpers.is_instance_of(nil, cyclic))
        assert.is_false(class_helpers.is_instance_of(value, {}))
        assert.is_false(class_helpers.is_instance_of(value, nil))
    end)
end)
