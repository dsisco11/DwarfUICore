--@ module=true

local class_helper = reqscript('dwarfuicore/class')
local gui = require('gui')

---Validates one public widget argument without retaining it.
---@param widget any
---@return gui.View widget
local function validate_widget(widget)
    assert(class_helper.is_instance_of(widget, gui.View),
        'DwarfUICore context-menu widget must be a gui.View.')
    return widget
end

---Validates the owner field before public map registration delegation.
---@param options any
---@return table options
local function validate_map_options(options)
    assert(type(options) == 'table' and
            (class_helper.is_instance_of(options.owner, gui.View) or
            class_helper.is_instance_of(options.owner, gui.ZScreen)),
        'DwarfUICore context-menu map owner must be a gui.View or gui.ZScreen.')
    return options
end

---Creates the private context-menu service record only during acquisition.
---@param generation integer
---@return table service
function initialize_service(generation)
    reqscript('dwarfuicore/context_menu/screen')
    local registration = reqscript('dwarfuicore/context_menu/registration')
    local service_module = reqscript('dwarfuicore/context_menu/service')
    return {generation=generation, registration=registration,
        service=service_module.service}
end

---Validates the private context-menu service record.
---@param service table
---@param generation integer
function validate_service(service, generation)
    assert(type(service) == 'table' and service.generation == generation and
        type(service.registration) == 'table' and type(service.service) == 'table' and
        type(service.registration.register) == 'function',
        'DwarfUICore context-menu private service is incomplete.')
end

---Builds the version 1 private context-menu facade.
---@param service table
---@param generation integer
---@return table facade
function build_facade(service, generation)
    local registration = service.registration
    return {
        register=function(namespace, major, widget, definition)
            return registration.register(namespace, validate_widget(widget),
                definition, major)
        end,
        update=function(namespace, major, widget, definition)
            return registration.update(namespace, validate_widget(widget),
                definition, major)
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

---Validates the exact version 1 private context-menu facade shape.
---@param facade table
---@param contract_major integer
function validate_facade(facade, contract_major)
    assert(contract_major == 1 and type(facade) == 'table',
        'DwarfUICore context-menu facade contract is invalid.')
    for _, name in ipairs({'register', 'update', 'unregister',
            'register_map_tile', 'update_map_tile', 'unregister_map_tile',
            'clear_namespace'}) do
        assert(type(facade[name]) == 'function',
            'DwarfUICore context-menu facade is incomplete.')
    end
end
