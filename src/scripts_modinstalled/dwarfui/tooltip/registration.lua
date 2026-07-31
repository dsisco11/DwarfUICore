--@ module=true

-- Process-wide tooltip input wiring. Registrations demand pointer polling;
-- samples flow through target detection into presentation-neutral intent.

local input_service = reqscript('dwarfui/tooltip/service').service
local PointerPoller =
    reqscript('dwarfui/pointer_poller').PointerPoller
local TooltipTargetDetector =
    reqscript('dwarfui/tooltip/target_detector').TooltipTargetDetector
local map_targets =
    reqscript('dwarfui/tooltip/map_target').registry
local target_adapters = reqscript('dwarfui/tooltip/target')
local ObservationKind = target_adapters.TooltipPointerObservationKind

API_VERSION = 1

local detector = TooltipTargetDetector.new{
    registrations=input_service:get_registrations(),
    additional_roots=function()
        return map_targets:get_owner_roots()
    end,
}
local poller

---Counts live weak widget registrations without retaining their views.
---@return integer
local function widget_registration_count()
    return input_service:registration_count()
end

---Counts live weak map registrations without retaining their handles.
---@return integer
local function map_registration_count()
    return map_targets:registration_count()
end

---Counts all live tooltip registrations across both target domains.
---@return integer
local function registration_count()
    return widget_registration_count() + map_registration_count()
end

---Returns whether tooltip registrations still require pointer samples.
---@return boolean
local function has_polling_demand()
    local has_demand = registration_count() > 0
    if not has_demand then input_service:shutdown() end
    return has_demand
end

---Returns whether a live map registration requires exact map sampling.
---@return boolean
local function has_map_sampling_demand()
    return map_registration_count() > 0
end

---Detects and mediates one presentation-independent pointer sample.
---@param sample dwarfui.PointerSample
local function observe_pointer(sample)
    local screen_observation = detector:detect(sample)
    if screen_observation.kind == ObservationKind.TARGET then
        screen_observation.target = target_adapters.adapt_widget(
            screen_observation.target,
            screen_observation.root,
            input_service:get_registrations())
        input_service:accept_pointer_observation(screen_observation)
        return
    end
    if screen_observation.kind == ObservationKind.BLOCKED then
        input_service:accept_pointer_observation(screen_observation)
        return
    end
    local map_observation = map_targets:detect(sample)
    if map_observation.kind == ObservationKind.TARGET then
        map_observation.target =
            target_adapters.adapt_map_tile(map_observation, map_targets)
    end
    input_service:accept_pointer_observation(map_observation)
end

poller = PointerPoller.new{
    observer=observe_pointer,
    has_demand=has_polling_demand,
    has_map_demand=has_map_sampling_demand,
}

---Registers any widget for process-wide singleton tooltip targeting.
---Registration is valid before attachment; detached widgets are simply skipped.
---@param widget gui.View
---@return boolean created
function register(widget)
    local created = input_service:register(widget)
    if created then poller:start() end
    return created
end

---Explicitly removes a registration; weak cleanup makes this optional.
---@param widget gui.View
---@return boolean removed
function unregister(widget)
    local removed = input_service:unregister(widget)
    if not removed then return false end
    if registration_count() == 0 then
        poller:stop()
        input_service:shutdown()
    end
    return true
end

---Registers one exact map tile with an independent owner and opaque handle.
---@param options dwarfui.MapTileTooltipRegistrationOptions
---@return dwarfui.MapTileTooltipRegistration
function register_map_tile(options)
    local handle = map_targets:register(options)
    poller:start()
    return handle
end

---Atomically replaces one map registration's exact position and text.
---@param handle dwarfui.MapTileTooltipRegistration
---@param update dwarfui.MapTileTooltipUpdate
---@return boolean updated
function update_map_tile(handle, update)
    return map_targets:update(handle, update)
end

---Explicitly removes one map registration and releases idle polling.
---@param handle dwarfui.MapTileTooltipRegistration
---@return boolean removed
function unregister_map_tile(handle)
    local removed = map_targets:unregister(handle)
    if not removed then return false end
    input_service:release_target(handle)
    if registration_count() == 0 then
        poller:stop()
        input_service:shutdown()
    end
    return true
end

---Returns presentation-neutral input and mediation diagnostics.
---@return table diagnostics
function get_diagnostics()
    local service_diagnostics = input_service:get_diagnostics()
    local poller_diagnostics = poller:get_diagnostics()
    local map_diagnostics = map_targets:get_diagnostics()
    return {
        api_version=service_diagnostics.api_version,
        generation=service_diagnostics.generation,
        registration_count=registration_count(),
        widget_registration_count=widget_registration_count(),
        map_registration_count=map_registration_count(),
        map_registry_generation=map_diagnostics.generation,
        map_coordinate_bucket_count=
            map_diagnostics.coordinate_bucket_count,
        target=service_diagnostics.target,
        intent=service_diagnostics.intent,
        revision=service_diagnostics.revision,
        last_sequence=service_diagnostics.last_sequence,
        poller_module_generation=poller_diagnostics.module_generation,
        poller_generation=poller_diagnostics.generation,
        poller_running=poller_diagnostics.running,
        poller_scheduled=poller_diagnostics.scheduled,
        poller_current=poller_diagnostics.current,
        sample_sequence=poller_diagnostics.sample_sequence,
    }
end

-- A coherent reload constructs a new poller generation after the poller
-- module invalidates every callback from the previous generation.
if registration_count() > 0 then
    poller:start()
else
    input_service:shutdown()
end
