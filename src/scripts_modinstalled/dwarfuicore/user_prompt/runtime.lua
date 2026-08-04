--@ module=true

-- Generation-bound assembly for the process-wide UserPrompt interaction.

local guidm = require('gui.dwarfmode')
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
local view_root_resolver =
    reqscript('dwarfuicore/view_root_resolver').resolver

local prompt_service = service_module.service
local input_manager = input_hook_module.manager
local presenter = tooltip_runtime.presenter
local context_service = context_service_module.service
local renderer = renderer_module.UserPromptRenderer{}
local causes = service_module.UserPromptTerminalCause
local STATE_CHANGE_SLOT = 'dwarfuicore_user_prompt'
local active_surface = nil
local state_change_callback = nil

---@type dwarfuicore.UserPromptInputConsumer
local input_consumer = input_consumer_module.UserPromptInputConsumer.new{
    is_active=function() return prompt_service:has_active_prompt() end,
    get_map_position=function() return dfhack.gui.getMousePos() end,
    complete=function(position) return prompt_service:complete(position) end,
    cancel=function(cause) return prompt_service:cancel_active(cause) end,
    on_failure=function(message)
        prompt_service:fail_active(message)
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

---Cancels an active prompt when its selected map surface is no longer usable.
---@param root_loss_cause dwarfuicore.UserPromptTerminalCause
---@return boolean current
local function ensure_active_surface(root_loss_cause)
    if not prompt_service:has_active_prompt() then return true end
    if type(dfhack.isMapLoaded) ~= 'function' or
            not dfhack.isMapLoaded() then
        prompt_service:cancel_active(causes.WORLD_UNLOAD)
        return false
    end
    local ok, presented = xpcall(function()
        return view_root_resolver:is_presented(active_surface)
    end, debug.traceback)
    if not ok then
        prompt_service:fail_active(presented)
        return false
    end
    if not presented then
        prompt_service:cancel_active(root_loss_cause)
        return false
    end
    return true
end

local input_callbacks = input_consumer:callbacks()

---Samples a map tile only while the screen pointer is inside the map panel.
---@param pointer_x integer|nil
---@param pointer_y integer|nil
---@return df.coord|nil position
local function sample_indicator_position(pointer_x, pointer_y)
    if pointer_x == nil or pointer_y == nil then return nil end
    local layout = guidm.getPanelLayout()
    local viewport = layout and guidm.Viewport.get(layout) or nil
    local map = layout and layout.map or nil
    if not viewport or not map or
            pointer_x < map.x1 or pointer_x >= map.x1 + viewport.width or
            pointer_y < map.y1 or pointer_y >= map.y1 + viewport.height then
        return nil
    end
    return dfhack.gui.getMousePos()
end

---@type dwarfuicore.PriorityInputConsumer
local guarded_input_callbacks = {
    owns=function(keys, transport, owner)
        local owned = input_callbacks.owns(keys, transport, owner)
        if not ensure_active_surface(causes.INPUT_ROOT_LOSS) then return owned end
        return owned
    end,
    handle=input_callbacks.handle,
    on_failure=input_callbacks.on_failure,
}

---Builds the authoritative completed-render callback for one request.
---@param request dwarfuicore.MapLocationPromptRequest
---@param indicator dwarfuicore.NativeIndicatorAdapter
---@param surface table
---@return function present
local function build_presenter(request, indicator, surface)
    return function(painter)
        if active_surface ~= surface or
                not ensure_active_surface(causes.PRESENTATION_ROOT_LOSS) then
            return
        end
        local ok, failure = xpcall(function()
            local pointer_x, pointer_y = dfhack.screen.getMousePos()
            local map_position =
                sample_indicator_position(pointer_x, pointer_y)
            indicator:update(map_position)
            renderer:set_prompt(request, pointer_x, pointer_y, painter)
            renderer:render(painter)
        end, debug.traceback)
        if not ok then
            prompt_service:fail_active(failure)
            if dfhack.printerr then
                pcall(dfhack.printerr,
                    'DwarfUICore UserPrompt presentation failed:\n' ..
                        tostring(failure))
            end
        end
    end
end

---@type dwarfuicore.UserPromptActivationPorts
local activation = {
    resolve_surface=resolve_surface,
    prepare_input=function(surface)
        return input_manager:prepare_priority_consumer(
            surface, guarded_input_callbacks)
    end,
    prepare_render=function(surface, request)
        local indicator = indicator_module.NativeIndicatorAdapter.new()
        return {
            intent=presenter:prepare_authoritative_intent(
                surface, build_presenter(request, indicator, surface)),
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
        active_surface = resources.surface
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

---Runs every sub-operation of one cleanup boundary before reporting failure.
---@param name string
---@param operations function[]
local function run_cleanup_operations(name, operations)
    local failures = {}
    for _, operation in ipairs(operations) do
        local ok, failure = xpcall(operation, debug.traceback)
        if not ok then table.insert(failures, tostring(failure)) end
    end
    if #failures > 0 then
        error(('DwarfUICore UserPrompt %s cleanup failed:\n%s'):format(
            name, table.concat(failures, '\n')), 0)
    end
end

---@type dwarfuicore.UserPromptCleanupPorts
local cleanup = {
    input=function(_, _, _, resources)
        active_surface = nil
        input_manager:release_priority_consumer(resources.input)
    end,
    render=function(_, _, _, resources)
        run_cleanup_operations('render', {
            function()
                presenter:release_authoritative_render(resources.render.intent)
            end,
            function() renderer:set_prompt(nil, nil, nil, nil) end,
        })
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

---Cancels the prompt when DFHack announces that the world has unloaded.
---@param code integer
local function handle_state_change(code)
    if code == SC_WORLD_UNLOADED then
        prompt_service:cancel_active(causes.WORLD_UNLOAD)
    end
end

---Installs the generation-owned world lifecycle callback when available.
local function install_state_change_callback()
    if dfhack.onStateChange == nil then return end
    state_change_callback = handle_state_change
    dfhack.onStateChange[STATE_CHANGE_SLOT] = state_change_callback
end

---Removes only the world lifecycle callback still owned by this generation.
local function remove_state_change_callback()
    if dfhack.onStateChange ~= nil and
            dfhack.onStateChange[STATE_CHANGE_SLOT] == state_change_callback then
        dfhack.onStateChange[STATE_CHANGE_SLOT] = nil
    end
    state_change_callback = nil
end

install_state_change_callback()

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
        type(service.cancel_active) == 'function' and
        type(service.fail_active) == 'function' and
        type(service.retire_for_reload) == 'function' and
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
    remove_state_change_callback()
    return runtime.service:retire_for_reload()
end
