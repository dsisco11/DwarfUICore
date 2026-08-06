--@ module=true

local service_module = reqscript('dwarfuicore/input_event/service')
local input_manager = reqscript('dwarfuicore/input_event/input_hook').manager

---Creates the private version-1 Input Event service.
---@param generation integer
---@return table service
function initialize_service(generation)
    return service_module.InputEventService.new(generation, input_manager)
end

---Validates one private Input Event service instance.
---@param service table
---@param generation integer
function validate_service(service, generation)
    assert(type(service) == 'table' and service._generation == generation and
            type(service.subscribe) == 'function',
        'DwarfUICore Input Event service is incomplete or stale.')
end

---Builds the version-1 namespace facade over the private subscription registry.
---@param service table
---@param generation integer
---@return table facade
function build_facade(service, generation)
    return {observe=function(namespace, major, event_type, callback)
            return service:subscribe(namespace, major, event_type, 'observe', callback)
        end,
        intercept=function(namespace, major, event_type, handler)
            return service:subscribe(namespace, major, event_type, 'intercept', handler)
        end,
        unsubscribe=function(namespace, major, handle)
            return service:unsubscribe(namespace, major, handle)
        end,
        is_subscribed=function(namespace, major, handle)
            return service:is_subscribed(namespace, major, handle)
        end,
        clear_namespace=function(namespace, major)
            return service:clear_namespace(namespace, major)
        end}
end

---Validates the version-1 Input Event facade contract.
---@param facade table
---@param contract_major integer
function validate_facade(facade, contract_major)
    assert(contract_major == 1 and type(facade.observe) == 'function' and
            type(facade.intercept) == 'function' and
            type(facade.unsubscribe) == 'function' and
            type(facade.is_subscribed) == 'function' and
            type(facade.clear_namespace) == 'function',
        'DwarfUICore Input Event facade is incomplete.')
end
