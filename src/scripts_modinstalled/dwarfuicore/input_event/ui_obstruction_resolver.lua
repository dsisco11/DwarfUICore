--@ module=true

-- Conservative generic proof that a screen point is unobstructed by UI.

local pointer = reqscript('dwarfuicore/pointer')

---@class dwarfuicore.InputEventUiObstructionResolver
InputEventUiObstructionResolver = {}

---Returns whether every supplied root can be inspected and none owns the point.
---@param roots table[]|nil
---@param screen_position dwarfuicore.Position2D|nil
---@return boolean unobstructed
function InputEventUiObstructionResolver.is_unobstructed(roots, screen_position)
    if type(roots) ~= 'table' or type(screen_position) ~= 'table' then
        return false
    end
    for _, root in ipairs(roots) do
        if type(root) ~= 'table' and type(root) ~= 'userdata' then return false end
        local ok, result = pcall(pointer.PointerDispatcher.resolve, root,
            screen_position.x, screen_position.y)
        if not ok or type(result) ~= 'table' then return false end
        if result.kind ~= pointer.PointerClassificationKind.MISS then return false end
    end
    return true
end
