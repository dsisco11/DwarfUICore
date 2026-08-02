--@ module=true

local class_helper = reqscript('dwarfuicore/class')
local gui = require('gui')

---Validates one public widget argument without retaining it.
---@param widget any
---@return gui.View widget
local function validate_widget(widget)
    assert(class_helper.is_instance_of(widget, gui.View),
        'DwarfUICore tooltip widget must be a gui.View.')
    return widget
end

---Validates the owner field before public map registration delegation.
---@param options any
---@return table options
local function validate_map_options(options)
    assert(type(options) == 'table' and
            (class_helper.is_instance_of(options.owner, gui.View) or
            class_helper.is_instance_of(options.owner, gui.ZScreen)),
        'DwarfUICore tooltip map owner must be a gui.View or gui.ZScreen.')
    return options
end

---Creates the private tooltip service record only during provider acquisition.
---@param generation integer
---@return table service
function initialize_service(generation)
    local tooltip_runtime = reqscript('dwarfuicore/tooltip/runtime')
    local registration = reqscript('dwarfuicore/tooltip/registration')
    return {generation=generation, runtime=tooltip_runtime,
        registration=registration}
end

---Validates the private tooltip service record.
---@param service table
---@param generation integer
function validate_service(service, generation)
    assert(type(service) == 'table' and service.generation == generation and
        type(service.runtime) == 'table' and type(service.registration) == 'table' and
        type(service.registration.register) == 'function',
        'DwarfUICore tooltip private service is incomplete.')
end

---Builds the version 1 private tooltip facade.
---@param service table
---@param generation integer
---@return table facade
function build_facade(service, generation)
    local registration = service.registration
    return {
        register=function(namespace, major, widget)
            return registration.register(namespace, validate_widget(widget), major)
        end,
        unregister=function(namespace, major, widget)
            return registration.unregister(namespace, validate_widget(widget), major)
        end,
        register_map_tile=function(namespace, major, options)
            return registration.register_map_tile(namespace,
                validate_map_options(options), major)
        end,
        update_map_tile=function(namespace, major, handle, update)
            return registration.update_map_tile(namespace, handle, update, major)
        end,
        unregister_map_tile=function(namespace, major, handle)
            return registration.unregister_map_tile(namespace, handle, major)
        end,
        clear_namespace=function(namespace, major)
            return registration.clear_namespace(namespace, major)
        end,
    }
end

---Validates the exact version 1 private tooltip facade shape.
---@param facade table
---@param contract_major integer
function validate_facade(facade, contract_major)
    assert(contract_major == 1 and type(facade) == 'table',
        'DwarfUICore tooltip facade contract is invalid.')
    for _, name in ipairs({'register', 'unregister', 'register_map_tile',
            'update_map_tile', 'unregister_map_tile', 'clear_namespace'}) do
        assert(type(facade[name]) == 'function',
            'DwarfUICore tooltip facade is incomplete.')
    end
end
