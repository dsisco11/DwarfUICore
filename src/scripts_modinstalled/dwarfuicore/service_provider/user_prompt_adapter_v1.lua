--@ module=true

-- Private version 1 facade over the process-wide UserPrompt state machine.

local values = reqscript('dwarfuicore/user_prompt/value')
local prompt_runtime = reqscript('dwarfuicore/user_prompt/runtime')

---Creates the private UserPrompt service record during provider acquisition.
---@param generation integer
---@return table service
function initialize_service(generation)
    return prompt_runtime.get(generation)
end

---Validates the private UserPrompt service record without replacing it.
---@param service table
---@param generation integer
function validate_service(service, generation)
    prompt_runtime.validate(service, generation)
end

---Builds the exact version 1 private UserPrompt facade.
---@param service table
---@param generation integer
---@return table facade
function build_facade(service, generation)
    local prompt_service = service.service
    return {
        prompt_map_location=function(namespace, major, options)
            local copied_options = values.MapLocationPromptOptions.new(options)
            local request = values.MapLocationPromptRequest.new(
                namespace, copied_options)
            return prompt_service:start(request, major)
        end,
        cancel=function(namespace, major, handle)
            return prompt_service:cancel(handle, namespace, major)
        end,
        is_active=function(namespace, major, handle)
            return prompt_service:is_active(handle, namespace, major)
        end,
        clear_namespace=function(namespace, major)
            return prompt_service:clear_namespace(namespace, major)
        end,
    }
end

---Validates the exact version 1 private UserPrompt facade shape.
---@param facade table
---@param contract_major integer
function validate_facade(facade, contract_major)
    assert(contract_major == 1 and type(facade) == 'table',
        'DwarfUICore UserPrompt facade contract is invalid.')
    for _, name in ipairs({'prompt_map_location', 'cancel', 'is_active',
            'clear_namespace'}) do
        assert(type(facade[name]) == 'function',
            'DwarfUICore UserPrompt facade is incomplete.')
    end
end
