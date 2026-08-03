--@ module=true

-- Generation-bound assembly for the process-wide UserPrompt state machine.

local service_module = reqscript('dwarfuicore/user_prompt/service')

---@class dwarfuicore.UserPromptRuntime
---@field generation integer
---@field service dwarfuicore.UserPromptService

local diagnostics = service_module.service:get_diagnostics()

---@type dwarfuicore.UserPromptRuntime
runtime = {
    generation=diagnostics.runtime_generation,
    service=service_module.service,
}

---Validates one runtime assembly against the expected Core generation.
---@param value any
---@param expected_generation integer
---@return dwarfuicore.UserPromptRuntime runtime
function validate(value, expected_generation)
    local service = type(value) == 'table' and value.service or nil
    local current = type(service) == 'table' and
        type(service.get_diagnostics) == 'function' and
        service:get_diagnostics() or nil
    assert(type(value) == 'table' and
        value.generation == expected_generation and
        type(service) == 'table' and
        type(service.start) == 'function' and
        type(service.cancel) == 'function' and
        type(service.is_active) == 'function' and
        type(service.clear_namespace) == 'function' and
        type(current) == 'table' and
        current.runtime_generation == expected_generation,
        'DwarfUICore UserPrompt runtime is incomplete or stale.')
    return value
end

---Returns the one validated runtime assembly for this module generation.
---@param expected_generation integer
---@return dwarfuicore.UserPromptRuntime runtime
function get(expected_generation)
    return validate(runtime, expected_generation)
end

---Cancels the active prompt before shared owners retire during Core reload.
---@return boolean changed
function retire_for_reload()
    return runtime.service:cancel_active(
        service_module.UserPromptTerminalCause.CORE_RELOAD)
end

