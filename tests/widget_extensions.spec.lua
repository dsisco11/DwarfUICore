local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local module_path =
    'src/scripts_modinstalled/dwarfuicore/widget_extensions.lua'
local pointer_path = 'src/scripts_modinstalled/dwarfuicore/pointer.lua'
local enum_path =
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua'

---Creates a DFHack reporting and process-state test double.
---@param options? table
---@return table dfhack
local function make_dfhack(options)
    options = options or {}
    local announcements = {}
    local console_errors = {}
    return {
        dwarfuicore=options.dwarfuicore,
        gui={
            showAnnouncement=options.show_announcement or function(...)
                table.insert(announcements, {...})
            end,
        },
        printerr=options.printerr or function(message)
            table.insert(console_errors, message)
        end,
        announcements=announcements,
        console_errors=console_errors,
    }
end

---Loads the production pointer module and its immutable enum dependency.
---@return table pointer
local function load_pointer()
    local _, immutable_enum = module_loader.load(repo_root, enum_path)
    local _, pointer = module_loader.load(repo_root, pointer_path, {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })
    return pointer
end

---Loads the production widget extension with controlled shared classes.
---@param widgets table
---@param default_nil any
---@param dfhack? table
---@param pointer? table
---@return table extension
---@return table pointer
local function load_extension(widgets, default_nil, dfhack, pointer)
    pointer = pointer or load_pointer()
    local _, extension = module_loader.load(repo_root, module_path, {
        globals={
            DEFAULT_NIL=default_nil,
            COLOR_RED=4,
            dfhack=dfhack or make_dfhack(),
        },
        require_modules={['gui.widgets']=widgets},
        reqscript={['dwarfuicore/pointer']=pointer},
    })
    return extension, pointer
end

local function contains(text, expected)
    assert.is_truthy(text:find(expected, 1, true))
end

describe('DwarfUICore widget extensions', function()
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
        local _, pointer = load_extension(widgets, default_nil)
        local Policy = pointer.PointerPolicy

        assert.equals(Policy.TARGET, widgets.Widget.ATTRS.pointer_policy)
        assert.equals(Policy.PASS, widgets.Panel.ATTRS.pointer_policy)
        assert.equals(Policy.BLOCK, widgets.Window.ATTRS.pointer_policy)
        assert.equals(Policy.TARGET, widgets.TextButton.ATTRS.pointer_policy)
        assert.is.equal(default_nil, widgets.Widget.ATTRS.on_pointer_enter)
        assert.is.equal(default_nil, widgets.Widget.ATTRS.on_pointer_update)
        assert.is.equal(default_nil, widgets.Widget.ATTRS.on_pointer_leave)

        assert.equals(Policy.TARGET, widgets.Label{}.pointer_policy)
        assert.equals(Policy.PASS, widgets.Panel{}.pointer_policy)
        assert.equals(Policy.BLOCK, widgets.Window{}.pointer_policy)
        assert.equals(Policy.TARGET, widgets.TextButton{}.pointer_policy)

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
        local dfhack = make_dfhack()
        local first_pointer = load_pointer()
        widgets.Widget.ATTRS{
            tooltip=default_nil,
            pointer_policy=first_pointer.PointerPolicy.TARGET,
            on_pointer_enter=default_nil,
            on_pointer_update=default_nil,
            on_pointer_leave=default_nil,
        }
        widgets.Panel.ATTRS{
            pointer_policy=first_pointer.PointerPolicy.PASS,
        }
        widgets.Window.ATTRS{
            pointer_policy=first_pointer.PointerPolicy.BLOCK,
        }
        widgets.TextButton.ATTRS{
            pointer_policy=first_pointer.PointerPolicy.TARGET,
        }

        local classes = {
            Widget=widgets.Widget,
            Panel=widgets.Panel,
            Window=widgets.Window,
            TextButton=widgets.TextButton,
        }
        local first = load_extension(
            widgets, default_nil, dfhack, first_pointer)
        local second = load_extension(
            widgets, default_nil, dfhack, first_pointer)

        assert.is_false(first.install_tooltip_attribute())
        assert.is_false(first.install_pointer_attributes())
        assert.is_false(second.install_tooltip_attribute())
        assert.is_false(second.install_pointer_attributes())
        for name, class in pairs(classes) do
            assert.is.equal(class, widgets[name])
        end
        assert.is.equal(default_nil, widgets.Widget.ATTRS.tooltip)
        assert.equals(
            first_pointer.PointerPolicy.PASS,
            widgets.Panel.ATTRS.pointer_policy)
        assert.equals(0, second.get_diagnostics().replacement_count)
        assert.equals(0, #dfhack.announcements)
        assert.equals(0, #dfhack.console_errors)
    end)

    it('authoritatively replaces legacy and arbitrary conflicting defaults', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        local pointer = load_pointer()
        local dfhack = make_dfhack()
        widgets.Widget.ATTRS{tooltip=false}
        widgets.Widget.ATTRS.pointer_policy = 'target'
        widgets.Panel.ATTRS.pointer_policy = 'pass'
        widgets.Window.ATTRS.pointer_policy = {}
        widgets.TextButton.ATTRS.pointer_policy = 999

        local extension = load_extension(
            widgets, default_nil, dfhack, pointer)

        assert.is.equal(default_nil, widgets.Widget.ATTRS.tooltip)
        assert.equals(
            pointer.PointerPolicy.TARGET,
            widgets.Widget.ATTRS.pointer_policy)
        assert.equals(
            pointer.PointerPolicy.PASS,
            widgets.Panel.ATTRS.pointer_policy)
        assert.equals(
            pointer.PointerPolicy.BLOCK,
            widgets.Window.ATTRS.pointer_policy)
        assert.equals(
            pointer.PointerPolicy.TARGET,
            widgets.TextButton.ATTRS.pointer_policy)

        local diagnostics = extension.get_diagnostics()
        assert.equals(5, diagnostics.replacement_count)
        assert.equals(5, #diagnostics.replacements)
        assert.equals(1, #dfhack.announcements)
        assert.equals(1, #dfhack.console_errors)
        contains(dfhack.console_errors[1],
            'gui.widgets.Widget.ATTRS.pointer_policy: target ->')
        contains(dfhack.console_errors[1],
            'gui.widgets.Panel.ATTRS.pointer_policy: pass ->')
        contains(dfhack.console_errors[1],
            'gui.widgets.TextButton.ATTRS.pointer_policy: 999 ->')

        local second = load_extension(
            widgets, default_nil, dfhack, pointer)
        assert.equals(2, second.get_diagnostics().generation)
        assert.equals(5, second.get_diagnostics().replacement_count)
        assert.equals(1, #dfhack.announcements)
        assert.equals(1, #dfhack.console_errors)
    end)

    it('installs absent defaults quietly and remains stable across reload', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        local pointer = load_pointer()
        local dfhack = make_dfhack()

        local first = load_extension(
            widgets, default_nil, dfhack, pointer)
        local second = load_extension(
            widgets, default_nil, dfhack, pointer)

        assert.equals(0, first.get_diagnostics().replacement_count)
        assert.equals(0, second.get_diagnostics().replacement_count)
        assert.equals(2, second.get_diagnostics().generation)
        assert.equals(0, #dfhack.announcements)
        assert.equals(0, #dfhack.console_errors)
        assert.equals(0, second.install_all())
        assert.equals(0, #dfhack.announcements)
        assert.equals(0, #dfhack.console_errors)
    end)

    it('does not let reporting failures block authoritative installation', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        widgets.Panel.ATTRS.pointer_policy = 'foreign'
        local dfhack = make_dfhack{
            show_announcement=function() error('announcement failed') end,
            printerr=function() error('console failed') end,
        }

        local extension, pointer = load_extension(
            widgets, default_nil, dfhack)

        assert.equals(
            pointer.PointerPolicy.PASS,
            widgets.Panel.ATTRS.pointer_policy)
        local diagnostics = extension.get_diagnostics()
        assert.is_true(diagnostics.report_attempted)
        contains(diagnostics.announcement_error, 'announcement failed')
        contains(diagnostics.console_error, 'console failed')

        local reloaded = load_extension(
            widgets, default_nil, dfhack, pointer)
        assert.equals(2, reloaded.get_diagnostics().generation)
        assert.equals(1, reloaded.get_diagnostics().replacement_count)
    end)

    it('repairs malformed partial process state before installation', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        widgets.Window.ATTRS.pointer_policy = 'foreign'
        local dfhack = make_dfhack{
            dwarfui={
                widget_extensions={
                    generation='partial',
                    replacement_count='partial',
                    replacements='partial',
                    report_attempted='partial',
                },
            },
        }

        local extension, pointer = load_extension(
            widgets, default_nil, dfhack)

        assert.equals(
            pointer.PointerPolicy.BLOCK,
            widgets.Window.ATTRS.pointer_policy)
        local diagnostics = extension.get_diagnostics()
        assert.equals(1, diagnostics.generation)
        assert.equals(1, diagnostics.replacement_count)
        assert.equals(1, #diagnostics.replacements)
        assert.equals(1, #dfhack.announcements)
        assert.equals(1, #dfhack.console_errors)
    end)
end)
