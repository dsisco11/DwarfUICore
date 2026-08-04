--@ module=true

-- Process-wide tooltip input wiring. Registrations demand pointer polling;
-- samples flow through target detection into presentation-neutral intent.

local input_service = reqscript('dwarfuicore/tooltip/service').service
local PointerPoller =
    reqscript('dwarfuicore/pointer_poller').PointerPoller
local TooltipTargetDetector =
    reqscript('dwarfuicore/tooltip/target_detector').TooltipTargetDetector
local map_targets =
    reqscript('dwarfuicore/tooltip/map_target').registry
local target_adapters = reqscript('dwarfuicore/tooltip/target')
local ObservationKind = target_adapters.TooltipPointerObservationKind
local contracts = reqscript('dwarfuicore/service_provider/contracts')
local identity = reqscript('dwarfuicore/service_provider/identity')
local namespaces = reqscript('dwarfuicore/service_provider/namespace')
local WidgetTargetStore =
    reqscript('dwarfuicore/service_provider/weak_store').WidgetTargetStore
local allocator = identity.get_process_allocator()

API_VERSION = 2
local RUNTIME_SLOT = 'tooltip_registration_runtime'
local NAMESPACE_SLOT = 'tooltip_namespace_registry'
local DEFAULT_NAMESPACE = 'dwarfuicore'
local DEFAULT_CONTRACT_MAJOR = 1

dfhack.dwarfuicore = dfhack.dwarfuicore or {}
local runtime_state = dfhack.dwarfuicore.service_provider_runtime
local runtime_generation = runtime_state and runtime_state.generation or 1
local namespace_state = dfhack.dwarfuicore[NAMESPACE_SLOT]
local migrated_namespace_state = false
if namespace_state then
    assert(type(namespace_state) == 'table' and
            namespace_state.api_version == API_VERSION and
            type(namespace_state.widget_store) == 'table',
        'DwarfUICore tooltip namespace registry is incompatible.')
    assert(namespace_state.runtime_generation <= runtime_generation,
        'DwarfUICore tooltip namespace registry belongs to a future runtime.')
    if namespace_state.runtime_generation < runtime_generation then
        namespace_state.widget_store:for_each_contribution(
            function(_, consumer_namespace, record)
                record.identity = allocator:allocate_identity(
                    runtime_generation, contracts.ServiceKind.TOOLTIP,
                    record.contract_major, consumer_namespace)
            end)
        namespace_state.runtime_generation = runtime_generation
        migrated_namespace_state = true
    end
else
    namespace_state = {api_version=API_VERSION,
        runtime_generation=runtime_generation,
        widget_store=WidgetTargetStore.new(allocator)}
    dfhack.dwarfuicore[NAMESPACE_SLOT] = namespace_state
end
local widget_store = namespace_state.widget_store
local process_state = dfhack.dwarfuicore[RUNTIME_SLOT]
if process_state and runtime_generation > 0 then
    assert(process_state.runtime_generation == runtime_generation,
        'DwarfUICore tooltip polling belongs to another runtime generation.')
end
local detector = process_state and process_state.detector or nil
local poller = process_state and process_state.poller or nil

---Validates one internal namespace-bound tooltip domain.
---@param consumer_namespace any
---@param contract_major? any
---@return string consumer_namespace
---@return integer contract_major
local function validate_domain(consumer_namespace, contract_major)
    namespaces.validate(consumer_namespace)
    contract_major = contract_major or DEFAULT_CONTRACT_MAJOR
    assert(math.type(contract_major) == 'integer' and contract_major > 0,
        'DwarfUICore tooltip contract major must be a positive integer.')
    return consumer_namespace, contract_major
end

---Counts live weak widget registrations without retaining their views.
---@return integer
local function widget_registration_count()
    return widget_store:contribution_count()
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
---@param sample dwarfuicore.PointerSample
local function observe_pointer(sample)
    local screen_observation = detector:detect(sample)
    if screen_observation.kind == ObservationKind.TARGET then
        local widget = screen_observation.target
        local contribution = widget_store:get_winner(widget)
        if contribution then
            local composite_identity = contribution.identity
            screen_observation.identity = composite_identity
            screen_observation.target = target_adapters.adapt_widget(
                widget, screen_observation.root,
                input_service:get_registrations(), composite_identity,
                function()
                    local current = widget_store:get_contribution(
                        widget, contribution.namespace)
                    return current ~= nil and
                        current.identity == composite_identity
                end)
        else
            screen_observation.kind = ObservationKind.MISS
            screen_observation.target = nil
        end
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

---Stops idle polling and presentation only after all namespaces lose demand.
local function release_idle_runtime()
    if registration_count() ~= 0 then return end
    poller:stop()
    input_service:shutdown()
end

if not poller then
    local constructed_detector = TooltipTargetDetector.new{
        registrations=input_service:get_registrations(),
        additional_roots=function()
            return map_targets:get_owner_roots()
        end,
    }
    detector = constructed_detector
    local constructed_poller = PointerPoller.new{
        observer=observe_pointer,
        has_demand=has_polling_demand,
        has_map_demand=has_map_sampling_demand,
    }
    process_state = {
        runtime_generation=runtime_generation,
        detector=constructed_detector,
        poller=constructed_poller,
    }
    dfhack.dwarfuicore[RUNTIME_SLOT] = process_state
    poller = constructed_poller
end

if migrated_namespace_state then
    local published_targets = setmetatable({}, {__mode='k'})
    widget_store:for_each_contribution(function(widget, _, _, target_sequence)
        if not published_targets[widget] then
            assert(input_service:register(widget, target_sequence),
                'DwarfUICore tooltip target migration conflicted.')
            published_targets[widget] = true
        end
    end)
    if widget_store:contribution_count() > 0 then poller:start() end
end

---Registers one namespace contribution for a physical widget target.
---Registration is valid before attachment; detached widgets are simply skipped.
---@param consumer_namespace string
---@param widget gui.View
---@param contract_major? integer
---@return boolean created
function register(consumer_namespace, widget, contract_major)
    if widget == nil and type(consumer_namespace) == 'table' then
        widget, consumer_namespace = consumer_namespace, DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    assert(type(widget) == 'table',
        'DwarfUICore tooltip registration requires a widget table.')
    if widget_store:get_contribution(widget, consumer_namespace) then
        return false
    end
    local composite_identity = allocator:allocate_identity(
        runtime_generation, contracts.ServiceKind.TOOLTIP,
        contract_major, consumer_namespace)
    local had_target = widget_store:contains_target(widget)
    local target_sequence, _, created = widget_store:register(
        widget, consumer_namespace, {identity=composite_identity,
            namespace=consumer_namespace, contract_major=contract_major})
    assert(created,
        'DwarfUICore tooltip contribution publication was not unique.')
    if not had_target then
        assert(input_service:register(widget, target_sequence),
            'DwarfUICore tooltip physical target publication conflicted.')
    end
    poller:start()
    return created
end

---Explicitly removes one namespace's widget contribution.
---@param consumer_namespace string
---@param widget gui.View
---@param contract_major? integer
---@return boolean removed
function unregister(consumer_namespace, widget, contract_major)
    if widget == nil and type(consumer_namespace) == 'table' then
        widget, consumer_namespace = consumer_namespace, DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    local contribution = widget_store:get_contribution(
        widget, consumer_namespace)
    if not contribution or contribution.contract_major ~= contract_major then
        return false
    end
    local removed, record = widget_store:remove(widget, consumer_namespace)
    if not removed then return false end
    input_service:release_target(record.identity)
    if not widget_store:contains_target(widget) then
        input_service:unregister(widget)
    end
    release_idle_runtime()
    return true
end

---Registers one namespaced exact map tile with an opaque composite handle.
---@param consumer_namespace string
---@param options dwarfuicore.MapTileTooltipRegistrationOptions
---@param contract_major? integer
---@return dwarfuicore.MapTileTooltipRegistration
function register_map_tile(consumer_namespace, options, contract_major)
    if options == nil and type(consumer_namespace) == 'table' then
        options, consumer_namespace = consumer_namespace, DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    local handle = map_targets:register(
        consumer_namespace, options, contract_major)
    poller:start()
    return handle
end

---Atomically replaces one owned map registration's exact position and text.
---@param consumer_namespace string
---@param handle dwarfuicore.MapTileTooltipRegistration
---@param update dwarfuicore.MapTileTooltipUpdate
---@param contract_major? integer
---@return boolean updated
function update_map_tile(consumer_namespace, handle, update, contract_major)
    if identity.is_map_handle(consumer_namespace) then
        update, handle, consumer_namespace =
            handle, consumer_namespace, DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    return map_targets:update(
        consumer_namespace, handle, update, contract_major)
end

---Explicitly removes one owned map registration and releases idle polling.
---@param consumer_namespace string
---@param handle dwarfuicore.MapTileTooltipRegistration
---@param contract_major? integer
---@return boolean removed
function unregister_map_tile(consumer_namespace, handle, contract_major)
    if identity.is_map_handle(consumer_namespace) then
        handle, consumer_namespace = consumer_namespace, DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    local composite_identity = map_targets:get_identity(handle)
    local removed = map_targets:unregister(
        consumer_namespace, handle, contract_major)
    if not removed then return false end
    input_service:release_target(composite_identity)
    release_idle_runtime()
    return true
end

---Removes every tooltip contribution owned by one namespace and contract.
---@param consumer_namespace string
---@param contract_major? integer
---@return boolean changed
function clear_namespace(consumer_namespace, contract_major)
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    local widgets = {}
    widget_store:for_each_contribution(function(widget, namespace, record)
        if namespace == consumer_namespace and
                record.contract_major == contract_major then
            table.insert(widgets, widget)
        end
    end)
    local changed = false
    for _, widget in ipairs(widgets) do
        local removed, record = widget_store:remove(
            widget, consumer_namespace)
        if removed then
            changed = true
            input_service:release_target(record.identity)
            if not widget_store:contains_target(widget) then
                input_service:unregister(widget)
            end
        end
    end
    for _, record in ipairs(map_targets:clear_namespace(
            consumer_namespace, contract_major)) do
        changed = true
        input_service:release_target(record.identity)
    end
    release_idle_runtime()
    return changed
end

---@class dwarfuicore.TooltipNamespaceBinding
---@field private _namespace string
---@field private _contract_major integer
local TooltipNamespaceBinding = {}
TooltipNamespaceBinding.__index = TooltipNamespaceBinding

---Registers a widget through this private namespace binding.
---@param widget gui.View
---@return boolean created
function TooltipNamespaceBinding:register(widget)
    return register(self._namespace, widget, self._contract_major)
end

---Unregisters a widget through this private namespace binding.
---@param widget gui.View
---@return boolean removed
function TooltipNamespaceBinding:unregister(widget)
    return unregister(self._namespace, widget, self._contract_major)
end

---Registers one map tile through this private namespace binding.
---@param options dwarfuicore.MapTileTooltipRegistrationOptions
---@return dwarfuicore.MapTileTooltipRegistration handle
function TooltipNamespaceBinding:register_map_tile(options)
    return register_map_tile(
        self._namespace, options, self._contract_major)
end

---Updates one owned map tile through this private namespace binding.
---@param handle dwarfuicore.MapTileTooltipRegistration
---@param update dwarfuicore.MapTileTooltipUpdate
---@return boolean updated
function TooltipNamespaceBinding:update_map_tile(handle, update)
    return update_map_tile(
        self._namespace, handle, update, self._contract_major)
end

---Unregisters one owned map tile through this private namespace binding.
---@param handle dwarfuicore.MapTileTooltipRegistration
---@return boolean removed
function TooltipNamespaceBinding:unregister_map_tile(handle)
    return unregister_map_tile(
        self._namespace, handle, self._contract_major)
end

---Clears every contribution owned by this private namespace binding.
---@return boolean changed
function TooltipNamespaceBinding:clear_namespace()
    return clear_namespace(self._namespace, self._contract_major)
end

---Creates a disposable private binding without owning registration lifetime.
---@param consumer_namespace string
---@param contract_major? integer
---@return dwarfuicore.TooltipNamespaceBinding binding
function bind(consumer_namespace, contract_major)
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    return setmetatable({_namespace=consumer_namespace,
        _contract_major=contract_major}, TooltipNamespaceBinding)
end

---Returns presentation-neutral input and mediation diagnostics.
---@param consumer_namespace? string
---@return table diagnostics
function get_diagnostics(consumer_namespace)
    if consumer_namespace ~= nil then namespaces.validate(consumer_namespace) end
    local service_diagnostics = input_service:get_diagnostics()
    local poller_diagnostics = poller:get_diagnostics()
    local map_diagnostics = map_targets:get_diagnostics(consumer_namespace)
    local widget_count = widget_store:contribution_count(consumer_namespace)
    local target = service_diagnostics.target
    local target_visible = consumer_namespace == nil or target == nil or
        target.namespace == consumer_namespace
    local target_snapshot = nil
    if target_visible and target ~= nil then
        target_snapshot = {runtime_generation=target.runtime_generation,
            service_kind=target.service_kind,
            contract_major=target.contract_major,
            namespace=target.namespace,
            local_identity=target.local_identity}
    end
    local widget_contributions = {}
    widget_store:for_each_contribution(function(_, namespace, record,
            target_sequence, contribution_sequence)
        if consumer_namespace == nil or namespace == consumer_namespace then
            local source = record.identity
            table.insert(widget_contributions, {
                identity={runtime_generation=source.runtime_generation,
                    service_kind=source.service_kind,
                    contract_major=source.contract_major,
                    namespace=source.namespace,
                    local_identity=source.local_identity},
                target_sequence=target_sequence,
                contribution_sequence=contribution_sequence,
            })
        end
    end)
    table.sort(widget_contributions, function(left, right)
        return left.contribution_sequence < right.contribution_sequence
    end)
    return {
        api_version=service_diagnostics.api_version,
        generation=service_diagnostics.generation,
        registration_count=widget_count + map_diagnostics.registration_count,
        widget_registration_count=widget_count,
        map_registration_count=map_diagnostics.registration_count,
        map_registry_generation=map_diagnostics.generation,
        map_coordinate_bucket_count=
            map_diagnostics.coordinate_bucket_count,
        widget_contributions=widget_contributions,
        map_contributions=map_diagnostics.registrations,
        target=target_snapshot,
        intent=target_visible and service_diagnostics.intent or nil,
        revision=service_diagnostics.revision,
        last_sequence=service_diagnostics.last_sequence,
        poller_runtime_generation=poller_diagnostics.runtime_generation,
        poller_generation=poller_diagnostics.generation,
        poller_running=poller_diagnostics.running,
        poller_scheduled=poller_diagnostics.scheduled,
        poller_current=poller_diagnostics.current,
        sample_sequence=poller_diagnostics.sample_sequence,
    }
end
