--@ module=true

local MODULE_REGISTRY_SCRIPT = 'dwarfuicore/module_registry'
local SERVICE_RUNTIME_SCRIPT = 'dwarfuicore/service_provider/runtime'
local TOOLTIP_RUNTIME_SCRIPT = 'dwarfuicore/tooltip/runtime'
local TOOLTIP_RENDER_HOOK_SCRIPT = 'dwarfuicore/tooltip/render_hook'
local CONTEXT_MENU_SERVICE_SCRIPT = 'dwarfuicore/context_menu/service'
local CONTEXT_MENU_REGISTRATION_SCRIPT =
    'dwarfuicore/context_menu/registration'
local CONTEXT_MENU_INPUT_HOOK_SCRIPT =
    'dwarfuicore/context_menu/input_hook'
local USER_PROMPT_SERVICE_SCRIPT = 'dwarfuicore/user_prompt/service'
local USER_PROMPT_RUNTIME_SCRIPT = 'dwarfuicore/user_prompt/runtime'
local PROCESS_OWNER_SLOTS = {'tooltip_map_target_registry', 'tooltip_service',
    'tooltip_namespace_registry', 'tooltip_registration_runtime', 'tooltip_runtime',
    'context_menu_registration_manager', 'context_menu_input_hook',
    'context_menu_service', 'user_prompt_service'}

---Returns a loaded script environment without loading an absent script.
---@param script_name string
---@return table|nil environment
local function find_loaded_script_environment(script_name)
    local path = dfhack.findScript(script_name)
    if not path or not dfhack.internal.scripts[path] then return nil end
    return reqscript(script_name)
end

---Loads the DwarfUICore module registry.
---@return table registry
local function load_module_registry()
    return reqscript(MODULE_REGISTRY_SCRIPT)
end

---Loads the private process runtime lifecycle owner.
---@return table runtime
local function load_service_runtime()
    return reqscript(SERVICE_RUNTIME_SCRIPT)
end

---Returns one surviving process-owned field without loading its script.
---@param slot string
---@param field string
---@return any value
local function get_process_owner_field(slot, field)
    if type(dfhack.dwarfuicore) ~= 'table' then return nil end
    local state = dfhack.dwarfuicore[slot]
    if type(state) ~= 'table' then return nil end
    return state[field]
end

---Returns whether a process owner predates the current runtime generation.
---@param slot string
---@return boolean stale
local function is_stale_process_owner(slot)
    if type(dfhack.dwarfuicore) ~= 'table' then return false end
    local runtime = dfhack.dwarfuicore.service_provider_runtime
    local owner = dfhack.dwarfuicore[slot]
    if type(runtime) ~= 'table' or type(owner) ~= 'table' then return false end
    local generation = runtime.generation
    return math.type(generation) == 'integer' and generation > 0 and
        owner.runtime_generation ~= generation
end

---Clears retired owner records only during explicit Core reload.
local function clear_process_owner_slots()
    if type(dfhack.dwarfuicore) ~= 'table' then return end
    for _, slot in ipairs(PROCESS_OWNER_SLOTS) do dfhack.dwarfuicore[slot] = nil end
end

---Clears script environments only for scripts currently loaded by DFHack.
---@param script_names string[]
local function clear_script_environments(script_names)
    local loaded_names = {}
    for _, name in ipairs(script_names) do
        local path = dfhack.findScript(name)
        if path and dfhack.internal.scripts[path] then table.insert(loaded_names, name) end
    end
    if #loaded_names > 0 then
        dfhack.run_command('devel/clear-script-env', table.unpack(loaded_names))
    end
end

---Runs one named module and adds Core-specific reconstruction context.
---@param script_name string
local function run_module_script(script_name)
    local ok, failure = xpcall(function() dfhack.run_script(script_name) end,
        debug.traceback)
    assert(ok, ('DwarfUICore reload failed while loading %s:\n%s'):format(
        script_name, tostring(failure)))
end

---Retires the current tooltip presenter or partial render-hook owner.
local function retire_tooltip()
    local presenter = get_process_owner_field('tooltip_runtime', 'presenter')
    if presenter and type(presenter.retire_for_reload) == 'function' then
        presenter:retire_for_reload()
        return
    end
    if is_stale_process_owner('tooltip_runtime') or
            is_stale_process_owner('tooltip_service') then
        return
    end
    local runtime = find_loaded_script_environment(TOOLTIP_RUNTIME_SCRIPT)
    if runtime and runtime.presenter and type(runtime.presenter.retire_for_reload) == 'function' then
        runtime.presenter:retire_for_reload()
        return
    end
    local hook = find_loaded_script_environment(TOOLTIP_RENDER_HOOK_SCRIPT)
    if hook and hook.manager and type(hook.manager.shutdown) == 'function' then hook.manager:shutdown() end
end

---Retires the current context-menu service or partial registration owner.
local function retire_context_menu()
    local service = find_loaded_script_environment(CONTEXT_MENU_SERVICE_SCRIPT)
    if service and service.service and type(service.service.shutdown) == 'function' then
        service.service:shutdown()
        return
    end
    local registration = find_loaded_script_environment(CONTEXT_MENU_REGISTRATION_SCRIPT)
    if registration and registration.manager and type(registration.manager.shutdown) == 'function' then
        registration.manager:shutdown()
    end
    local input_hook = find_loaded_script_environment(
        CONTEXT_MENU_INPUT_HOOK_SCRIPT)
    if input_hook and input_hook.manager and
            type(input_hook.manager.shutdown) == 'function' then
        input_hook.manager:shutdown()
    end
end

---Retires an active prompt before shared input and render owners.
local function retire_user_prompt()
    local runtime = find_loaded_script_environment(USER_PROMPT_RUNTIME_SCRIPT)
    if runtime and type(runtime.retire_for_reload) == 'function' then
        runtime.retire_for_reload()
        return
    end
    local module = find_loaded_script_environment(USER_PROMPT_SERVICE_SCRIPT)
    if module and module.service and
            type(module.service.retire_for_reload) == 'function' then
        module.service:retire_for_reload()
    elseif module and module.service and module.UserPromptTerminalCause and
            type(module.service.cancel_active) == 'function' then
        module.service:cancel_active(module.UserPromptTerminalCause.CORE_RELOAD)
    end
end

---Loads and validates the current DwarfUICore module generation.
---@return table<string, table>
function initialize()
    local runtime = load_service_runtime()
    local state, created = runtime.begin_initialization()
    local result = table.pack(xpcall(function()
        return load_module_registry().load_all(reqscript)
    end, debug.traceback))
    if not result[1] then
        if created then pcall(runtime.fail_initialization, state.generation) end
        error(result[2], 0)
    end
    if created then runtime.complete_initialization(state.generation) end
    return result[2]
end

---Retires Core-owned runtime owners before an explicit development reload.
function teardown()
    retire_user_prompt()
    retire_context_menu()
    retire_tooltip()
end

---Rebuilds the DwarfUICore module generation for explicit development use.
---@return table<string, table>
function reload()
    local runtime = load_service_runtime()
    local old_registry = load_module_registry()
    local old_names = old_registry.get_script_names()
    local old_modules = {}
    for _, name in ipairs(old_names) do
        if name ~= MODULE_REGISTRY_SCRIPT then table.insert(old_modules, name) end
    end
    runtime.begin_reload()
    local fresh_state
    local result = table.pack(xpcall(function()
        teardown()
        fresh_state = runtime.begin_reconstruction()
        clear_process_owner_slots()
        clear_script_environments(old_modules)
        dfhack.run_command('devel/clear-script-env', MODULE_REGISTRY_SCRIPT)
        dfhack.run_script(MODULE_REGISTRY_SCRIPT)
        local fresh_registry = load_module_registry()
        local fresh_modules = {}
        for _, spec in ipairs(fresh_registry.MODULES) do table.insert(fresh_modules, spec.name) end
        clear_script_environments(fresh_modules)
        for _, script_name in ipairs(fresh_modules) do run_module_script(script_name) end
        local loaded = fresh_registry.load_all(reqscript)
        load_service_runtime().complete_initialization(fresh_state.generation)
        return loaded
    end, debug.traceback))
    if not result[1] then
        if fresh_state == nil then
            local promoted, state = pcall(runtime.begin_reconstruction)
            if promoted then fresh_state = state end
        end
        if fresh_state then
            pcall(runtime.fail_initialization, fresh_state.generation)
        end
        error(result[2], 0)
    end
    return result[2]
end

---Runs DwarfUICore validation or its explicit development reload command.
---@param ... string
function main(...)
    local arguments = {...}
    if #arguments == 0 then
        initialize()
    elseif #arguments == 1 and arguments[1] == 'reload' then
        reload()
    else
        qerror('Usage: dwarfuicore [reload]')
    end
end
