--@ module=true

local widgets = require('gui.widgets')
local pointer = reqscript('dwarfui/pointer')
local PointerPolicy = pointer.PointerPolicy

local STATE_KEY = 'widget_extensions'

---@class dwarfui.SharedAttributeReplacement
---@field class_name string
---@field attribute_name string
---@field prior_value any
---@field prior_value_present boolean
---@field canonical_value any

---@class dwarfui.SharedAttributeOwnershipState
---@field generation integer
---@field replacement_count integer
---@field replacements dwarfui.SharedAttributeReplacement[]
---@field report_attempted boolean
---@field announcement_error string|nil
---@field console_error string|nil

if type(dfhack.dwarfui) ~= 'table' then dfhack.dwarfui = {} end
local previous_state = dfhack.dwarfui[STATE_KEY]
---@type dwarfui.SharedAttributeOwnershipState
local process_state = type(previous_state) == 'table' and previous_state or {
    generation=0,
    replacement_count=0,
    replacements={},
    report_attempted=false,
}
if type(process_state.generation) ~= 'number' then
    process_state.generation = 0
end
if type(process_state.replacements) ~= 'table' then
    process_state.replacements = {}
end
process_state.generation = process_state.generation + 1
process_state.replacement_count = #process_state.replacements
process_state.report_attempted = process_state.report_attempted == true
dfhack.dwarfui[STATE_KEY] = process_state

---Converts a diagnostic value to text without trusting its metamethods.
---@param value any
---@return string
local function diagnostic_value(value)
    if value == nil then return '<absent>' end
    local ok, rendered = pcall(tostring, value)
    return ok and rendered or '<unprintable>'
end

---Records one class-level contract replacement in process diagnostics.
---@param class_name string
---@param attribute_name string
---@param prior_value any
---@param canonical_value any
local function record_replacement(
        class_name, attribute_name, prior_value, canonical_value)
    process_state.replacement_count = process_state.replacement_count + 1
    table.insert(process_state.replacements, {
        class_name=class_name,
        attribute_name=attribute_name,
        prior_value=prior_value,
        prior_value_present=prior_value ~= nil,
        canonical_value=canonical_value,
    })
end

---Installs one authoritative attribute default on a DFHack widget class.
---@param class table
---@param name string
---@param default any
---@param description string
---@return boolean changed
local function install_attribute(class, name, default, description)
    local attrs = assert(class and class.ATTRS,
        'DwarfUI requires ' .. description .. '.ATTRS.')
    local existing = rawget(attrs, name)
    if existing == default then return false end

    attrs{[name]=default}
    if existing ~= nil then
        record_replacement(description, name, existing, default)
    end
    return true
end

---Installs the declarative tooltip attribute on all DFHack widgets.
---@return boolean changed
function install_tooltip_attribute()
    local widget = assert(widgets.Widget,
        'DwarfUI requires gui.widgets.Widget for tooltip attributes.')
    return install_attribute(widget, 'tooltip', DEFAULT_NIL,
        'gui.widgets.Widget')
end

---Installs pointer policies and callbacks on the relevant widget classes.
---@return boolean changed
function install_pointer_attributes()
    local changed = false
    local widget = assert(widgets.Widget,
        'DwarfUI requires gui.widgets.Widget for pointer attributes.')
    local panel = assert(widgets.Panel,
        'DwarfUI requires gui.widgets.Panel for pointer attributes.')
    local window = assert(widgets.Window,
        'DwarfUI requires gui.widgets.Window for pointer attributes.')
    local text_button = assert(widgets.TextButton,
        'DwarfUI requires gui.widgets.TextButton for pointer attributes.')

    changed = install_attribute(widget, 'pointer_policy', PointerPolicy.TARGET,
        'gui.widgets.Widget') or changed
    changed = install_attribute(widget, 'on_pointer_enter', DEFAULT_NIL,
        'gui.widgets.Widget') or changed
    changed = install_attribute(widget, 'on_pointer_update', DEFAULT_NIL,
        'gui.widgets.Widget') or changed
    changed = install_attribute(widget, 'on_pointer_leave', DEFAULT_NIL,
        'gui.widgets.Widget') or changed
    changed = install_attribute(panel, 'pointer_policy', PointerPolicy.PASS,
        'gui.widgets.Panel') or changed
    changed = install_attribute(window, 'pointer_policy', PointerPolicy.BLOCK,
        'gui.widgets.Window') or changed
    -- TextButton is a Panel that delegates input to an internal HotkeyLabel.
    -- The public control owns its hit region and declared tooltip.
    changed = install_attribute(
        text_button, 'pointer_policy', PointerPolicy.TARGET,
        'gui.widgets.TextButton') or changed
    return changed
end

---Builds the detailed ownership-replacement report.
---@param replacements dwarfui.SharedAttributeReplacement[]
---@return string
local function build_report(replacements)
    local lines = {
        ('DwarfUI replaced %d shared gui.widgets attribute contract(s):')
            :format(#replacements),
    }
    for _, replacement in ipairs(replacements) do
        table.insert(lines, ('- %s.ATTRS.%s: %s -> %s'):format(
            replacement.class_name,
            replacement.attribute_name,
            diagnostic_value(replacement.prior_value),
            diagnostic_value(replacement.canonical_value)))
    end
    return table.concat(lines, '\n')
end

---Reports the first replacement batch once per DFHack process.
---@param replacements dwarfui.SharedAttributeReplacement[]
local function report_replacements(replacements)
    if #replacements == 0 or process_state.report_attempted then return end
    process_state.report_attempted = true

    local message = build_report(replacements)
    local announcement_ok, announcement_error = pcall(function()
        dfhack.gui.showAnnouncement(
            'DwarfUI corrected conflicting shared UI attributes. See DFHack console.',
            COLOR_RED,
            true)
    end)
    if not announcement_ok then
        process_state.announcement_error = diagnostic_value(announcement_error)
    end

    local console_ok, console_error = pcall(function()
        dfhack.printerr(message)
    end)
    if not console_ok then
        process_state.console_error = diagnostic_value(console_error)
    end
end

---Installs every DwarfUI-owned shared widget attribute contract.
---@return integer replacement_count
function install_all()
    local first_replacement = #process_state.replacements + 1
    install_tooltip_attribute()
    install_pointer_attributes()

    local replacements = {}
    for index = first_replacement, #process_state.replacements do
        table.insert(replacements, process_state.replacements[index])
    end
    report_replacements(replacements)
    return #replacements
end

---Returns reload-safe shared-attribute ownership diagnostics.
---@return dwarfui.SharedAttributeOwnershipState diagnostics
function get_diagnostics()
    return process_state
end

install_all()
