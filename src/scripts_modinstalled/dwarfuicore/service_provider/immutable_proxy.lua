--@ module=true

---A private factory for one family of immutable opaque objects.
---@class dwarfuicore.ImmutableProxyFactory
---@field create fun(self: dwarfuicore.ImmutableProxyFactory, backing: table): table
---@field get_backing fun(self: dwarfuicore.ImmutableProxyFactory, value: any): table|nil
---@field is_instance fun(self: dwarfuicore.ImmutableProxyFactory, value: any): boolean

---Creates an isolated immutable-object family with private backing storage.
---@param label string
---@param methods? table<string, function>
---@return dwarfuicore.ImmutableProxyFactory factory
function new_factory(label, methods)
    assert(type(label) == 'string' and label ~= '',
        'DwarfUICore immutable proxy label must be a non-empty string.')
    methods = methods or {}
    assert(type(methods) == 'table',
        'DwarfUICore immutable proxy methods must be a table.')
    local backing_by_proxy = setmetatable({}, {__mode='k'})
    local method_data = {}
    for name, method in pairs(methods) do
        assert(type(name) == 'string' and type(method) == 'function',
            'DwarfUICore immutable proxy methods must be named functions.')
        method_data[name] = method
    end
    local factory = {}

    ---Creates an immutable empty proxy over a private backing record.
    ---@param backing table
    ---@return table proxy
    function factory:create(backing)
        assert(type(backing) == 'table',
            'DwarfUICore immutable proxy backing must be a table.')
        local proxy = {}
        backing_by_proxy[proxy] = backing
        return setmetatable(proxy, {
            __index=method_data,
            __newindex=function()
                error(('DwarfUICore %s is immutable.'):format(label), 2)
            end,
            __pairs=function() return next, {}, nil end,
            __metatable=false,
        })
    end

    ---Returns private backing only for an object from this factory.
    ---@param value any
    ---@return table|nil backing
    function factory:get_backing(value)
        return type(value) == 'table' and backing_by_proxy[value] or nil
    end

    ---Returns whether a value belongs to this immutable-object family.
    ---@param value any
    ---@return boolean is_instance
    function factory:is_instance(value)
        return self:get_backing(value) ~= nil
    end
    return factory
end
