--@ module=true

-- Collects every inspectable active Core and host UI root conservatively.

local overlay = require('plugins.overlay')

---@class dwarfuicore.InputEventUiRootCollector
InputEventUiRootCollector = {}

---Returns deduplicated current native, overlay, and explicitly supplied roots.
---@param current_root any
---@param additional_roots? table
---@return table[]|nil roots
function InputEventUiRootCollector.collect(current_root, additional_roots)
    local roots, seen = {}, {}
    local function add(root)
        if root == nil or seen[root] then return end
        seen[root] = true
        table.insert(roots, root)
    end
    local gui = dfhack.gui
    if type(gui) ~= 'table' or type(gui.getDFViewscreen) ~= 'function' then
        return nil
    end
    local native = gui.getDFViewscreen(true)
    if native == nil then return nil end
    add(native.widgets)
    add(current_root)
    local state = overlay.get_state()
    if type(state) ~= 'table' or type(state.db) ~= 'table' then return nil end
    for name, entry in pairs(state.db) do
        if type(entry) ~= 'table' or entry.widget == nil then return nil end
        if overlay.isOverlayEnabled(name) then
            add(entry.widget)
        end
    end
    for _, root in ipairs(additional_roots or {}) do add(root) end
    return roots
end
