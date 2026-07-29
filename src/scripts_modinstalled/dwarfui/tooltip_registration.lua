--@ module=true

-- Process-wide tooltip input wiring. Registrations demand pointer polling;
-- samples flow through target detection into presentation-neutral intent.

local input_service = reqscript('dwarfui/tooltip_service').service
local PointerPoller =
    reqscript('dwarfui/pointer_poller').PointerPoller
local TooltipTargetDetector =
    reqscript('dwarfui/tooltip_target_detector').TooltipTargetDetector

API_VERSION = 1

local detector = TooltipTargetDetector.new{
    registrations=input_service:get_registrations(),
}
local poller

---Counts live weak registrations without retaining their widgets.
---@return integer
local function registration_count()
    return input_service:registration_count()
end

---Returns whether tooltip registrations still require pointer samples.
---@return boolean
local function has_polling_demand()
    local has_demand = registration_count() > 0
    if not has_demand then input_service:shutdown() end
    return has_demand
end

---Detects and mediates one presentation-independent pointer sample.
---@param sample dwarfui.PointerSample
local function observe_pointer(sample)
    input_service:accept_pointer_observation(detector:detect(sample))
end

poller = PointerPoller.new{
    observer=observe_pointer,
    has_demand=has_polling_demand,
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

---Returns presentation-neutral input and mediation diagnostics.
---@return table diagnostics
function get_diagnostics()
    local service_diagnostics = input_service:get_diagnostics()
    local poller_diagnostics = poller:get_diagnostics()
    return {
        api_version=service_diagnostics.api_version,
        generation=service_diagnostics.generation,
        registration_count=service_diagnostics.registration_count,
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
