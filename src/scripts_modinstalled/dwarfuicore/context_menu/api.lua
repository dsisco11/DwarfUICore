--@ module=true

-- Public registration-driven context-menu facade.

local registrations = reqscript('dwarfuicore/context_menu/registration')
reqscript('dwarfuicore/context_menu/screen')

---Registers or re-registers one UI widget context menu.
---@param widget table
---@param definition dwarfuicore.ContextMenuDefinition
---@return boolean created
function register(widget, definition)
    return registrations.register(widget, definition)
end

---Updates one existing widget context-menu definition.
---@param widget table
---@param definition dwarfuicore.ContextMenuDefinition
---@return boolean updated
function update(widget, definition)
    return registrations.update(widget, definition)
end

---Unregisters one widget context menu.
---@param widget table
---@return boolean removed
function unregister(widget)
    return registrations.unregister(widget)
end

---Registers one exact map-tile context menu.
---@param options table
---@return dwarfuicore.ContextMenuMapRegistrationHandle
function register_map_tile(options)
    return registrations.register_map_tile(options)
end

---Atomically updates one exact map-tile registration.
---@param handle dwarfuicore.ContextMenuMapRegistrationHandle
---@param update_options table
---@return boolean updated
function update_map_tile(handle, update_options)
    return registrations.update_map_tile(handle, update_options)
end

---Unregisters one exact map-tile context menu.
---@param handle dwarfuicore.ContextMenuMapRegistrationHandle
---@return boolean removed
function unregister_map_tile(handle)
    return registrations.unregister_map_tile(handle)
end
