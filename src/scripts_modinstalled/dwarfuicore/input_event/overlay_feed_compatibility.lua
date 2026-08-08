--@ module=true

-- Isolates overlay applicability compatibility checks for UI-root collection.

local overlay = require('plugins.overlay')

---@enum dwarfuicore.OverlayFeedCompatibility

---@class dwarfuicore.OverlayFeedCompatibility
local OverlayFeedCompatibility = {}

---Returns whether an overlay root advertises the current native viewscreen.
---@param root any
---@return boolean
local function overlay_matches_current_viewscreen(root)
    if type(root) ~= 'table' then return false end
    local current = dfhack.gui.getDFViewscreen(true)
    if not current then return false end
    local normalized = overlay.normalize_list(root.viewscreens)
    if type(normalized) ~= 'table' then return false end
    for _, focus in ipairs(normalized) do
        if focus == 'all' then
            return true
        end
        if dfhack.gui.matchFocusString(
                overlay.simplify_viewscreen_name(focus), current) then
            return true
        end
    end
    return false
end

---Returns whether a registry overlay root is currently presented by the feed.
---@param overlay_name any
---@param overlay_root any
---@return boolean
function OverlayFeedCompatibility.is_applicable_overlay_root(
        overlay_name, overlay_root)
    if type(overlay_name) ~= 'string' or
            (type(overlay_root) ~= 'table' and
                type(overlay_root) ~= 'userdata') then
        return false
    end
    if not overlay.isOverlayEnabled(overlay_name) then return false end

    local state = overlay.get_state()
    if type(state) ~= 'table' or type(state.db) ~= 'table' then
        return false
    end
    local entry = state.db[overlay_name]
    return type(entry) == 'table' and entry.widget == overlay_root and
        overlay_matches_current_viewscreen(entry)
end

return {
    is_applicable_overlay_root=
        OverlayFeedCompatibility.is_applicable_overlay_root,
}
