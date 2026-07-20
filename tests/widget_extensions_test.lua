local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local module_path =
    'src/scripts_modinstalled/dwarfui/widget_extensions.lua'

local function load_extension(widgets, default_nil)
    local _, extension = module_loader.load(repo_root, module_path, {
        globals={DEFAULT_NIL=default_nil},
        require_modules={['gui.widgets']=widgets},
    })
    return extension
end

local function contains(text, expected)
    assert.is_truthy(text:find(expected, 1, true))
end

describe('DwarfUI widget extensions', function()
    it('installs inherited tooltip values that can mutate and clear', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        load_extension(widgets, default_nil)

        assert.is.equal(default_nil, widgets.Widget.ATTRS.tooltip)
        for _, class in ipairs({
                widgets.Panel,
                widgets.Window,
                widgets.Label,
                widgets.TextButton,
            }) do
            local widget = class{tooltip='Initial tooltip'}
            assert.equals('Initial tooltip', widget.tooltip)
            widget.tooltip = 'Updated tooltip'
            assert.equals('Updated tooltip', widget.tooltip)
            widget.tooltip = nil
            assert.is_nil(widget.tooltip)
            widget.tooltip = ''
            assert.equals('', widget.tooltip)
        end
    end)

    it('installs class-specific pointer defaults and callbacks', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        load_extension(widgets, default_nil)

        assert.equals('target', widgets.Widget.ATTRS.pointer_policy)
        assert.equals('pass', widgets.Panel.ATTRS.pointer_policy)
        assert.equals('block', widgets.Window.ATTRS.pointer_policy)
        assert.equals('target', widgets.TextButton.ATTRS.pointer_policy)
        assert.is.equal(default_nil, widgets.Widget.ATTRS.on_pointer_enter)
        assert.is.equal(default_nil, widgets.Widget.ATTRS.on_pointer_update)
        assert.is.equal(default_nil, widgets.Widget.ATTRS.on_pointer_leave)

        assert.equals('target', widgets.Label{}.pointer_policy)
        assert.equals('pass', widgets.Panel{}.pointer_policy)
        assert.equals('block', widgets.Window{}.pointer_policy)
        assert.equals('target', widgets.TextButton{}.pointer_policy)

        local enter = function() end
        local update = function() end
        local leave = function() end
        local widget = widgets.Label{
            on_pointer_enter=enter,
            on_pointer_update=update,
            on_pointer_leave=leave,
        }
        assert.is.equal(enter, widget.on_pointer_enter)
        assert.is.equal(update, widget.on_pointer_update)
        assert.is.equal(leave, widget.on_pointer_leave)
    end)

    it('preserves compatible attributes and reloads without replacing classes', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        widgets.Widget.ATTRS{tooltip=default_nil}
        widgets.Panel.ATTRS{pointer_policy='pass'}

        local classes = {
            Widget=widgets.Widget,
            Panel=widgets.Panel,
            Window=widgets.Window,
            TextButton=widgets.TextButton,
        }
        local first = load_extension(widgets, default_nil)
        local second = load_extension(widgets, default_nil)

        assert.is_false(first.install_tooltip_attribute())
        assert.is_false(first.install_pointer_attributes())
        assert.is_false(second.install_tooltip_attribute())
        assert.is_false(second.install_pointer_attributes())
        for name, class in pairs(classes) do
            assert.is.equal(class, widgets[name])
        end
        assert.is.equal(default_nil, widgets.Widget.ATTRS.tooltip)
        assert.equals('pass', widgets.Panel.ATTRS.pointer_policy)
    end)

    it('rejects an incompatible tooltip default without overwriting it', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        widgets.Widget.ATTRS{tooltip=false}

        local ok, err = pcall(load_extension, widgets, default_nil)
        assert.is_false(ok)
        contains(tostring(err), 'incompatible contract')
        contains(tostring(err), 'DwarfUI requires tooltip=')
        assert.is_false(widgets.Widget.ATTRS.tooltip)
    end)

    it('rejects an incompatible pointer default without overwriting it', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        widgets.Panel.ATTRS{pointer_policy='target'}

        local ok, err = pcall(load_extension, widgets, default_nil)
        assert.is_false(ok)
        contains(tostring(err), 'incompatible contract')
        contains(tostring(err), 'DwarfUI requires pointer_policy=pass')
        assert.equals('target', widgets.Panel.ATTRS.pointer_policy)
    end)
end)
