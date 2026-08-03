--@ module=true

-- Generation-bound assembly for the process-wide UserPrompt interaction.

local context_service_module =
    reqscript('dwarfuicore/context_menu/service')
reqscript('dwarfuicore/context_menu/screen')
local input_hook_module = reqscript('dwarfuicore/context_menu/input_hook')
local indicator_module = reqscript('dwarfuicore/user_prompt/indicator')
local input_consumer_module =
    reqscript('dwarfuicore/user_prompt/input_consumer')
local renderer_module = reqscript('dwarfuicore/user_prompt/renderer')
local service_module = reqscript('dwarfuicore/user_prompt/service')
local tooltip_runtime = reqscript('dwarfuicore/tooltip/runtime')

local prompt_service = service_module.service
local input_manager = input_hook_module.manager
local presenter = tooltip_runtime.presenter
local context_service = context_service_module.service
local renderer = renderer_module.UserPromptRenderer{}
local causes = service_module.UserPromptTerminalCause

---@type dwarfuicore.UserPromptInputConsumer
local input_consumer = input_consumer_module.UserPromptInputConsumer.new{
    is_active=function() return prompt_service:has_active_prompt() end,
    get_map_position=function() return dfhack.gui.getMousePos() end,
    complete=function(position) return prompt_service:complete(position) end,
    cancel=function(cause) return prompt_service:cancel_active(cause) end,
    on_failure=function()
        prompt_service:cancel_active(causes.INTERNAL_FAILURE)
    end,
    causes=causes,
}

---Returns the current map-capable root shared by input and presentation.
---@return table|nil root
local function resolve_surface()
    if type(dfhack.isMapLoaded) ~= 'function' or
            not dfhack.isMapLoaded() then return nil end
    local menu_root = context_service:get_open_source_root()
    if menu_root ~= nil then return menu_root end
    return input_manager:resolve_current_surface()
end

---Builds the authoritative completed-render callback for one request.
---@param request dwarfuicore.MapLocationPromptRequest
---@param indicator dwarfuicore.NativeIndicatorAdapter
---@return function present
local function build_presenter(request, indicator)
    return function(painter)
        local pointer_x, pointer_y = dfhack.screen.getMousePos()
        local map_position = nil
        if pointer_x ~= nil and pointer_y ~= nil then
            map_position = dfhack.gui.getMousePos()
        end
        indicator:update(map_position)
        renderer:set_prompt(request, pointer_x, pointer_y, painter)
        renderer:render(painter)
    end
end

---@type dwarfuicore.UserPromptActivationPorts
local activation = {
    resolve_surface=resolve_surface,
    prepare_input=function(surface)
        return input_manager:prepare_priority_consumer(
            surface, input_consumer:callbacks())
    end,
    prepare_render=function(surface, request)
        local indicator = indicator_module.NativeIndicatorAdapter.new()
        return {
            intent=presenter:prepare_authoritative_intent(
                surface, build_presenter(request, indicator)),
            indicator=indicator,
        }
    end,
    prepare_indicator=function(_, _, resources)
        local prepared = resources.render
        assert(type(prepared) == 'table' and
                type(prepared.indicator) == 'table',
            'DwarfUICore prompt indicator preparation has no render intent.')
        prepared.indicator:prepare()
        return prepared.indicator
    end,
    rollback_input=function(prepared)
        input_manager:release_priority_consumer(prepared)
    end,
    rollback_render=function(prepared)
        presenter:release_authoritative_intent(prepared.intent)
    end,
    rollback_indicator=function()
        -- A detached snapshot has no native ownership to release.
    end,
    close_menu=function()
        context_service:close('user-prompt-activation')
    end,
    commit=function(resources)
        input_manager:activate_priority_consumer(resources.input)
        resources.indicator:commit_prepared()
        presenter:activate_authoritative_intent(resources.render.intent)
    end,
    invalidate=function(resources)
        assert(presenter:invalidate_authoritative_intent(
                resources.render.intent),
            'DwarfUICore prompt presentation owner was not committed.')
    end,
}

---@type dwarfuicore.UserPromptCleanupPorts
local cleanup = {
    input=function(_, _, _, resources)
        input_manager:release_priority_consumer(resources.input)
    end,
    render=function(_, _, _, resources)
        renderer:set_prompt(nil, nil, nil, nil)
        presenter:release_authoritative_render(resources.render.intent)
    end,
    tooltip_suppression=function(_, _, _, resources)
        presenter:release_tooltip_suppression(resources.render.intent)
    end,
    indicator=function(_, _, _, resources)
        resources.indicator:release()
    end,
    invalidation=function()
        dfhack.screen.invalidate()
    end,
}

prompt_service:configure_runtime(cleanup, activation)
context_service:set_opening_guard(function()
    return prompt_service:has_active_prompt()
end)

---@class dwarfuicore.UserPromptRuntime
---@field generation integer
---@field service dwarfuicore.UserPromptService

local diagnostics = service_module.service:get_diagnostics()

---@type dwarfuicore.UserPromptRuntime
runtime = {
    generation=diagnostics.runtime_generation,
    service=prompt_service,
    input_consumer=input_consumer,
    renderer=renderer,
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
