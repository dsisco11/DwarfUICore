--@ module=true

local namespaces = reqscript('dwarfuicore/service_provider/namespace')

local OPTION_FIELDS = {
    title=true,
    message=true,
    on_select=true,
    on_cancel=true,
}

---@class dwarfuicore.MapLocationPromptOptions
---@field title string
---@field message string
---@field on_select fun(position: dwarfuicore.MapTilePosition|nil)
---@field on_cancel? fun()
MapLocationPromptOptions = {}

---@class dwarfuicore.MapLocationPromptRequest
---@field namespace string
---@field title string
---@field message string
---@field on_select fun(position: dwarfuicore.MapTilePosition|nil)
---@field on_cancel? fun()
MapLocationPromptRequest = {}

local option_backing = setmetatable({}, {__mode='k'})
local request_backing = setmetatable({}, {__mode='k'})

---Creates one read-only property snapshot with hidden backing storage.
---@param label string
---@param values table
---@param registry table<table, table>
---@return table snapshot
local function make_snapshot(label, values, registry)
    local snapshot = {}
    registry[snapshot] = values
    return setmetatable(snapshot, {
        __index=values,
        __newindex=function()
            error(('DwarfUICore %s is immutable.'):format(label), 2)
        end,
        __pairs=function()
            return next, values, nil
        end,
        __metatable=false,
    })
end

---Validates an exact raw field set without accepting inherited fields.
---@param value any
---@param allowed table<string, boolean>
---@param label string
local function validate_fields(value, allowed, label)
    assert(type(value) == 'table',
        ('DwarfUICore %s must be a table.'):format(label))
    for key in next, value do
        assert(type(key) == 'string' and allowed[key],
            ('DwarfUICore %s contains unsupported field %s.')
                :format(label, tostring(key)))
    end
end

---Copies one validated map-location prompt option record.
---@param value any
---@return dwarfuicore.MapLocationPromptOptions options
function MapLocationPromptOptions.new(value)
    validate_fields(value, OPTION_FIELDS, 'map-location prompt options')
    local title = rawget(value, 'title')
    local message = rawget(value, 'message')
    local on_select = rawget(value, 'on_select')
    local on_cancel = rawget(value, 'on_cancel')
    assert(type(title) == 'string',
        'DwarfUICore map-location prompt title must be a string.')
    assert(type(message) == 'string',
        'DwarfUICore map-location prompt message must be a string.')
    assert(type(on_select) == 'function',
        'DwarfUICore map-location prompt on_select must be a function.')
    assert(on_cancel == nil or type(on_cancel) == 'function',
        'DwarfUICore map-location prompt on_cancel must be a function or nil.')
    return make_snapshot('map-location prompt options', {
        title=title,
        message=message,
        on_select=on_select,
        on_cancel=on_cancel,
    }, option_backing)
end

---Returns whether a value is an options snapshot from this module instance.
---@param value any
---@return boolean recognized
function MapLocationPromptOptions.is_instance(value)
    return type(value) == 'table' and option_backing[value] ~= nil
end

---Copies the API-bound namespace and validated options into one request.
---@param consumer_namespace any
---@param options any
---@return dwarfuicore.MapLocationPromptRequest request
function MapLocationPromptRequest.new(consumer_namespace, options)
    namespaces.validate(consumer_namespace)
    local values = option_backing[options]
    if values == nil then
        local copied_options = MapLocationPromptOptions.new(options)
        values = option_backing[copied_options]
    end
    return make_snapshot('map-location prompt request', {
        namespace=consumer_namespace,
        title=values.title,
        message=values.message,
        on_select=values.on_select,
        on_cancel=values.on_cancel,
    }, request_backing)
end

---Returns whether a value is a request snapshot from this module instance.
---@param value any
---@return boolean recognized
function MapLocationPromptRequest.is_instance(value)
    return type(value) == 'table' and request_backing[value] ~= nil
end

---Returns a detached private copy of a recognized request snapshot.
---@param request any
---@return table values
function MapLocationPromptRequest.copy(request)
    local values = request_backing[request]
    assert(values,
        'DwarfUICore map-location prompt request is not recognized.')
    return {
        namespace=values.namespace,
        title=values.title,
        message=values.message,
        on_select=values.on_select,
        on_cancel=values.on_cancel,
    }
end
