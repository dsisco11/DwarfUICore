--@ module=true

-- Shared text and Premium world-tile to interface-cell projection.

local guidm = require('gui.dwarfmode')

---@class dwarfui.MapProjectionResult
---@field x integer
---@field y integer
---@field z integer

---Returns whether a fortress world is currently available.
---@return boolean
function is_world_loaded()
    return type(dfhack.isWorldLoaded) ~= 'function' or
        dfhack.isWorldLoaded()
end

---Returns the active dwarfmode viewport and its interface-cell origin.
---@return gui.dwarfmode.Viewport|nil
---@return {x: integer, y: integer}|nil
function get_active_viewport()
    if not is_world_loaded() then return nil end
    local ok, layout = pcall(guidm.getPanelLayout)
    if not ok or not layout or not layout.map then return nil end
    local viewport_ok, viewport = pcall(guidm.Viewport.get, layout)
    if not viewport_ok then return nil end
    return viewport, {x=layout.map.x1 or 0, y=layout.map.y1 or 0}
end

---Projects one world coordinate into the active interface-cell space.
---The caller owns visibility and z-level policy.
---@param pos {x: integer, y: integer, z: integer}
---@param viewport gui.dwarfmode.Viewport
---@return dwarfui.MapProjectionResult|nil
function world_to_interface(pos, viewport)
    if not pos or not viewport then return nil end
    if not dfhack.screen.inGraphicsMode() then
        return viewport:tileToScreen(pos)
    end

    local gps = df.global.gps
    local world = df.global.world
    local native_viewport = world and world.viewport
    local corner = native_viewport and native_viewport.corner
    local zoom = gps and gps.viewport_zoom_factor
    if not corner or type(zoom) ~= 'number' or zoom <= 0 or
            type(gps.tile_pixel_x) ~= 'number' or gps.tile_pixel_x <= 0 or
            type(gps.tile_pixel_y) ~= 'number' or gps.tile_pixel_y <= 0 then
        return nil
    end

    local map_tile_pixels = zoom // 4
    if map_tile_pixels <= 0 then return nil end
    return {
        x=math.ceil(map_tile_pixels * (pos.x - corner.x) /
            gps.tile_pixel_x),
        y=math.ceil(map_tile_pixels * (pos.y - corner.y) /
            gps.tile_pixel_y),
        z=pos.z - corner.z,
    }
end

---Projects an exact tile only when it is visible on the displayed z-level.
---@param pos {x: integer, y: integer, z: integer}
---@param viewport? gui.dwarfmode.Viewport
---@return dwarfui.MapProjectionResult|nil
function project_visible(pos, viewport)
    local origin = {x=0, y=0}
    if not viewport then viewport, origin = get_active_viewport() end
    if not viewport or not is_world_loaded() then return nil end
    local projected = world_to_interface(pos, viewport)
    if not projected then return nil end

    if not dfhack.screen.inGraphicsMode() then
        if not viewport:isVisible(pos) then return nil end
    elseif projected.z ~= 0 or projected.x < 0 or projected.y < 0 or
            projected.x >= viewport.width or
            projected.y >= viewport.height then
        return nil
    end
    return {
        x=projected.x + origin.x,
        y=projected.y + origin.y,
        z=projected.z,
    }
end
