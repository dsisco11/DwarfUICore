--@ module=true

-- Public registration-driven tooltip facade.

local registration = reqscript('dwarfui/tooltip/registration')
local runtime = reqscript('dwarfui/tooltip/runtime')

---An exact fortress-map tile used only for map-target hit detection.
---@class dwarfui.MapTilePosition
---@field x integer
---@field y integer
---@field z integer

---Options for registering one exact map tile as a tooltip target.
---The owner is not the hit target. Its ancestor root supplies presentation
---transport and lifecycle eligibility independently from exact tile matching.
---Registration is valid before attachment, but cannot become eligible until
---the owner resolves to a currently presented root.
---@class dwarfui.MapTileTooltipRegistrationOptions
---@field owner gui.View
---@field pos dwarfui.MapTilePosition
---@field tooltip string|nil

---Complete replacement state for an existing map-tile registration.
---The owner and handle identity are immutable. Position and text change
---atomically so detection cannot observe values from different updates.
---@class dwarfui.MapTileTooltipUpdate
---@field pos dwarfui.MapTilePosition
---@field tooltip string|nil

---Opaque stable identity for one map-tile tooltip registration.
---This handle is not a gui.View and has no layout, render, focus, or input
---role. Every registration call returns a distinct handle, including calls for
---the same exact tile. Registration order resolves duplicate-tile precedence.
---`update_map_tile()` replaces the complete mutable state and returns false
---for an unknown or removed handle. `unregister_map_tile()` deactivates the
---handle immediately, returns true exactly once, and returns false thereafter.
---The process registry must not keep an otherwise abandoned handle alive;
---explicit unregistration remains available for immediate removal.
---@class dwarfui.MapTileTooltipRegistration

---Registers a widget with the process-wide singleton tooltip service.
---@param widget table
---@return boolean created
function register(widget)
    return registration.register(widget)
end

---Explicitly unregisters a widget; weak lifetime cleanup makes this optional.
---@param widget table
---@return boolean removed
function unregister(widget)
    return registration.unregister(widget)
end

---Registers one exact map tile with owner-scoped tooltip eligibility.
---@param options dwarfui.MapTileTooltipRegistrationOptions
---@return dwarfui.MapTileTooltipRegistration
function register_map_tile(options)
    return registration.register_map_tile(options)
end

---Atomically replaces one map registration's exact position and tooltip.
---@param handle dwarfui.MapTileTooltipRegistration
---@param update dwarfui.MapTileTooltipUpdate
---@return boolean updated
function update_map_tile(handle, update)
    return registration.update_map_tile(handle, update)
end

---Explicitly removes one exact map-tile registration.
---@param handle dwarfui.MapTileTooltipRegistration
---@return boolean removed
function unregister_map_tile(handle)
    return registration.unregister_map_tile(handle)
end

---Returns registration, mediation, and presentation diagnostics.
---@return table diagnostics
function get_diagnostics()
    local diagnostics = registration.get_diagnostics()
    diagnostics.presentation = runtime.presenter:get_diagnostics()
    return diagnostics
end
