--@ module=true

local MAX_BYTES = 64

---Returns whether a consumer namespace satisfies the version 1 byte grammar.
---@param value any
---@return boolean valid
function is_valid(value)
    if type(value) ~= 'string' or #value < 1 or #value > MAX_BYTES then
        return false
    end
    if not value:match('^[a-z]') or not value:match('^[a-z0-9._-]+$') then
        return false
    end
    return value:sub(-1) ~= '.' and not value:find('..', 1, true)
end

---Validates and returns a consumer namespace without normalization.
---@param value any
---@return string namespace
function validate(value)
    assert(is_valid(value), 'DwarfUICore consumer namespace is invalid.')
    return value
end
