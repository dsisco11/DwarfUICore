--@ module=true

-- Bounded function-upvalue inspection for reversible wrapper ownership.

---Returns whether an upvalue graph retains the requested predecessor.
---@param value any
---@param predecessor function
---@param visited table<any, boolean>
---@param budget {remaining: integer}
---@return boolean
local function value_wraps(value, predecessor, visited, budget)
    if value == predecessor then return true end
    local value_type = type(value)
    if value_type ~= 'function' and value_type ~= 'table' then
        return false
    end
    if visited[value] or budget.remaining <= 0 then return false end
    visited[value] = true
    budget.remaining = budget.remaining - 1
    if value_type == 'function' then
        local index = 1
        while true do
            local name, upvalue = debug.getupvalue(value, index)
            if name == nil then return false end
            if name ~= '_ENV' and
                    value_wraps(
                        upvalue, predecessor, visited, budget) then
                return true
            end
            index = index + 1
        end
    end
    for key, field in next, value do
        if value_wraps(key, predecessor, visited, budget) or
                value_wraps(field, predecessor, visited, budget) then
            return true
        end
    end
    return false
end

---Returns whether a wrapper closure retains the requested predecessor.
---@param wrapper function
---@param predecessor function
---@param budget? integer
---@return boolean
function wraps(wrapper, predecessor, budget)
    assert(type(wrapper) == 'function',
        'DwarfUI function-chain wrapper must be a function.')
    assert(type(predecessor) == 'function',
        'DwarfUI function-chain predecessor must be a function.')
    return value_wraps(
        wrapper, predecessor, {}, {remaining=budget or 256})
end
