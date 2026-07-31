--@ module=true

local widgets = require('gui.widgets')
local pointer = reqscript('dwarfui/pointer')
local PointerPolicy = pointer.PointerPolicy

---Installs one compatible attribute default on a DFHack widget class.
---@param class table
---@param name string
---@param default any
---@param description string
---@return boolean changed
local function install_attribute(class, name, default, description)
    local attrs = assert(class and class.ATTRS,
        'DwarfUI requires ' .. description .. '.ATTRS.')
    local existing = rawget(attrs, name)
    if existing == nil then
        attrs{[name]=default}
        return true
    end
    assert(existing == default,
        description .. '.ATTRS.' .. name .. ' has an incompatible contract; ' ..
        'DwarfUI requires ' .. name .. '=' .. tostring(default) .. '.')
    return false
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

install_tooltip_attribute()
install_pointer_attributes()
