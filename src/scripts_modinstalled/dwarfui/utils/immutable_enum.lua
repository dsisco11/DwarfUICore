--@ module=true

-- Immutable numeric enum construction for closed DwarfUI discriminator sets.

---Creates an immutable numeric enum and rejects invalid or duplicate values.
---@param values table<string, number>
---@param label? string
---@return table<string, number>
function define(values, label)
    assert(type(values) == 'table',
        'DwarfUI immutable enum values must be a table.')
    label = label or 'enum'
    local data = {}
    local seen = {}
    for name, value in pairs(values) do
        assert(type(name) == 'string' and type(value) == 'number' and
                value == value,
            'DwarfUI enum names must be strings and values must be numbers.')
        assert(not seen[value],
            ('DwarfUI %s contains duplicate value %s.'):format(
                label, tostring(value)))
        data[name] = value
        seen[value] = true
    end
    return setmetatable({}, {
        __index=data,
        __newindex=function()
            error(('DwarfUI %s is immutable.'):format(label), 2)
        end,
        __pairs=function()
            return pairs(data)
        end,
        __metatable=false,
    })
end
