--@ module=true

-- Shared helpers for DFHack's Lua class representation.

---Returns whether a table is an instance of an expected DFHack Lua class.
---DFHack instances use their class directly as their metatable, and classes
---link to their parent through the raw `super` field.
---@param value any
---@param expected_class table
---@return boolean
function is_instance_of(value, expected_class)
    if type(value) ~= 'table' or type(expected_class) ~= 'table' then
        return false
    end
    local class = getmetatable(value)
    local seen = {}
    while type(class) == 'table' and not seen[class] do
        if class == expected_class then return true end
        seen[class] = true
        class = rawget(class, 'super')
    end
    return false
end
