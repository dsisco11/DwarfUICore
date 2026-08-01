--@ module=true

-- Shared numeric classification utilities.

---Returns whether a value is an integer.
---@param value any
---@return boolean
function is_integer(value)
    return type(value) == 'number' and value % 1 == 0
end
