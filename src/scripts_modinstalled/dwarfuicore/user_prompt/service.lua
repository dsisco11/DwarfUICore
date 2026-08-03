--@ module=true

-- Process-wide prompt state and callback ordering. Concrete input, rendering,
-- tooltip, indicator, and invalidation adapters are injected by the runtime.

local contracts = reqscript('dwarfuicore/service_provider/contracts')
local identities = reqscript('dwarfuicore/service_provider/identity')
local namespaces = reqscript('dwarfuicore/service_provider/namespace')
local values = reqscript('dwarfuicore/user_prompt/value')
local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')

API_VERSION = 1
local SERVICE_SLOT = 'user_prompt_service'
local CLEANUP_ORDER = {
    'input',
    'render',
    'tooltip_suppression',
    'indicator',
    'invalidation',
}

---@enum dwarfuicore.UserPromptState
UserPromptState = immutable_enum.define({
    IDLE=1,
    ACTIVATING=2,
    ACTIVE=3,
    TERMINATING=4,
}, 'UserPromptState')

---@enum dwarfuicore.UserPromptAvailability
UserPromptAvailability = immutable_enum.define({
    AVAILABLE=1,
    TRANSIENT_UNAVAILABLE=2,
    DISABLED=3,
    RETIRED=4,
}, 'UserPromptAvailability')

---@enum dwarfuicore.UserPromptTerminalCause
UserPromptTerminalCause = immutable_enum.define({
    LEFT_RELEASE=1,
    RIGHT_RELEASE=2,
    ESCAPE=3,
    API_CANCEL=4,
    NAMESPACE_CLEAR=5,
    INPUT_ROOT_LOSS=6,
    PRESENTATION_ROOT_LOSS=7,
    WORLD_UNLOAD=8,
    INTERNAL_FAILURE=9,
    CORE_RELOAD=10,
}, 'UserPromptTerminalCause')

---@class dwarfuicore.UserPromptCleanupPorts
---@field input fun(identity: dwarfuicore.CompositeIdentity, request: table, cause: dwarfuicore.UserPromptTerminalCause, resources: table)
---@field render fun(identity: dwarfuicore.CompositeIdentity, request: table, cause: dwarfuicore.UserPromptTerminalCause, resources: table)
---@field tooltip_suppression fun(identity: dwarfuicore.CompositeIdentity, request: table, cause: dwarfuicore.UserPromptTerminalCause, resources: table)
---@field indicator fun(identity: dwarfuicore.CompositeIdentity, request: table, cause: dwarfuicore.UserPromptTerminalCause, resources: table)
---@field invalidation fun(identity: dwarfuicore.CompositeIdentity, request: table, cause: dwarfuicore.UserPromptTerminalCause, resources: table)

---@class dwarfuicore.UserPromptPendingRequest
---@field identity dwarfuicore.CompositeIdentity
---@field request table
---@field resources table

---@class dwarfuicore.UserPromptActivationPorts
---@field resolve_surface fun(): table|nil
---@field prepare_input fun(surface: table): any
---@field prepare_render fun(surface: table, request: table): any
---@field prepare_indicator fun(surface: table, request: table, resources: table): any
---@field rollback_input fun(prepared: any)
---@field rollback_render fun(prepared: any)
---@field rollback_indicator fun(prepared: any)
---@field close_menu fun()
---@field commit fun(resources: table)
---@field invalidate fun(resources: table)

---@class dwarfuicore.UserPromptServiceState
---@field api_version integer
---@field runtime_generation integer
---@field status dwarfuicore.UserPromptState
---@field availability dwarfuicore.UserPromptAvailability
---@field unavailable_cause dwarfuicore.UserPromptTerminalCause|nil
---@field pending dwarfuicore.UserPromptPendingRequest|nil
---@field blocked_namespace string|nil
---@field admitted_count integer
---@field busy_rejection_count integer
---@field terminal_count integer
---@field completion_count integer
---@field cancellation_count integer
---@field callback_failure_count integer
---@field cleanup_failure_count integer
---@field internal_failure_count integer
---@field terminal_cause_counts table<dwarfuicore.UserPromptTerminalCause, integer>
---@field last_terminal_cause dwarfuicore.UserPromptTerminalCause|nil
---@field last_terminal_identity dwarfuicore.CompositeIdentity|nil
---@field last_callback_error string|nil
---@field last_internal_error string|nil
---@field last_cleanup_failures table[]
---@field service? dwarfuicore.UserPromptService

---@class dwarfuicore.UserPromptService
---@field private _state dwarfuicore.UserPromptServiceState
---@field private _cleanup dwarfuicore.UserPromptCleanupPorts
---@field private _activation dwarfuicore.UserPromptActivationPorts
UserPromptService = {}
UserPromptService.__index = UserPromptService

---Does nothing for a not-yet-integrated cleanup boundary.
local function no_op()
end

---Creates the stand-in cleanup ports used before runtime adapter assembly.
---@return dwarfuicore.UserPromptCleanupPorts ports
local function stand_in_cleanup_ports()
    return {
        input=no_op,
        render=no_op,
        tooltip_suppression=no_op,
        indicator=no_op,
        invalidation=no_op,
    }
end

---Creates behaviorally inert activation ports for isolated state-model tests.
---@return dwarfuicore.UserPromptActivationPorts ports
local function stand_in_activation_ports()
    return {
        resolve_surface=function() return {} end,
        prepare_input=function() return {} end,
        prepare_render=function() return {} end,
        prepare_indicator=function() return {} end,
        rollback_input=no_op,
        rollback_render=no_op,
        rollback_indicator=no_op,
        close_menu=no_op,
        commit=no_op,
        invalidate=no_op,
    }
end

---Returns whether a value belongs to one immutable numeric enum.
---@param enumeration table
---@param value any
---@return boolean recognized
local function enum_contains(enumeration, value)
    for _, member in pairs(enumeration) do
        if value == member then return true end
    end
    return false
end

---Copies a composite identity for retained state or diagnostics.
---@param value dwarfuicore.CompositeIdentity|nil
---@return dwarfuicore.CompositeIdentity|nil identity
local function copy_identity(value)
    return value and identities.CompositeIdentity.new(value) or nil
end

---Creates empty process-owned state for one runtime generation.
---@param runtime_generation integer
---@return dwarfuicore.UserPromptServiceState state
function new_state(runtime_generation)
    assert(math.type(runtime_generation) == 'integer' and
            runtime_generation > 0,
        'DwarfUICore UserPrompt runtime generation must be positive.')
    return {
        api_version=API_VERSION,
        runtime_generation=runtime_generation,
        status=UserPromptState.IDLE,
        availability=UserPromptAvailability.AVAILABLE,
        unavailable_cause=nil,
        pending=nil,
        blocked_namespace=nil,
        admitted_count=0,
        busy_rejection_count=0,
        terminal_count=0,
        completion_count=0,
        cancellation_count=0,
        callback_failure_count=0,
        cleanup_failure_count=0,
        internal_failure_count=0,
        terminal_cause_counts={},
        last_terminal_cause=nil,
        last_terminal_identity=nil,
        last_callback_error=nil,
        last_internal_error=nil,
        last_cleanup_failures={},
    }
end

---Validates one complete cleanup-port set.
---@param cleanup any
---@return dwarfuicore.UserPromptCleanupPorts cleanup
local function validate_cleanup_ports(cleanup)
    assert(type(cleanup) == 'table',
        'DwarfUICore UserPrompt cleanup ports must be a table.')
    for _, name in ipairs(CLEANUP_ORDER) do
        assert(type(cleanup[name]) == 'function',
            ('DwarfUICore UserPrompt cleanup port %s must be a function.')
                :format(name))
    end
    return cleanup
end

---Validates one complete activation-port set.
---@param activation any
---@return dwarfuicore.UserPromptActivationPorts activation
local function validate_activation_ports(activation)
    assert(type(activation) == 'table',
        'DwarfUICore UserPrompt activation ports must be a table.')
    for _, name in ipairs{
            'resolve_surface', 'prepare_input', 'prepare_render',
            'prepare_indicator', 'rollback_input', 'rollback_render',
            'rollback_indicator', 'close_menu', 'commit', 'invalidate',
        } do
        assert(type(activation[name]) == 'function',
            ('DwarfUICore UserPrompt activation port %s must be a function.')
                :format(name))
    end
    return activation
end

---Creates one prompt state machine over process-owned state and cleanup ports.
---@param state dwarfuicore.UserPromptServiceState
---@param cleanup? dwarfuicore.UserPromptCleanupPorts
---@param activation? dwarfuicore.UserPromptActivationPorts
---@return dwarfuicore.UserPromptService service
function UserPromptService.new(state, cleanup, activation)
    assert(type(state) == 'table' and state.api_version == API_VERSION,
        'DwarfUICore UserPrompt service requires compatible process state.')
    assert(math.type(state.runtime_generation) == 'integer' and
            state.runtime_generation > 0,
        'DwarfUICore UserPrompt runtime generation must be positive.')
    assert(enum_contains(UserPromptState, state.status),
        'DwarfUICore UserPrompt state is invalid.')
    assert(enum_contains(UserPromptAvailability, state.availability),
        'DwarfUICore UserPrompt availability is invalid.')
    return setmetatable({
        _state=state,
        _cleanup=validate_cleanup_ports(cleanup or stand_in_cleanup_ports()),
        _activation=validate_activation_ports(
            activation or stand_in_activation_ports()),
    }, UserPromptService)
end

---Installs the concrete runtime adapters before any prompt can be admitted.
---@param cleanup dwarfuicore.UserPromptCleanupPorts
---@param activation dwarfuicore.UserPromptActivationPorts
function UserPromptService:configure_runtime(cleanup, activation)
    assert(self._state.status == UserPromptState.IDLE and
            self._state.pending == nil,
        'DwarfUICore UserPrompt runtime cannot change while active.')
    self._cleanup = validate_cleanup_ports(cleanup)
    self._activation = validate_activation_ports(activation)
end

---Raises one stable-category internal service failure.
---@param category dwarfuicore.ErrorCategory
---@param detail string
local function fail(category, detail)
    error(('DwarfUICore UserPromptService: [%s] %s'):format(
        contracts.get_error_token(category), detail), 0)
end

---Returns whether an authoritative request is active.
---@return boolean active
function UserPromptService:has_active_prompt()
    return self._state.pending ~= nil and
        self._state.status == UserPromptState.ACTIVE
end

---Validates one handle using the required malformed, stale, foreign order.
---@param handle any
---@param consumer_namespace string
---@param contract_major integer
---@return dwarfuicore.CompositeIdentity identity
function UserPromptService:_validate_handle(handle, consumer_namespace,
        contract_major)
    local identity, category = identities.classify_prompt_handle(handle,
        self._state.runtime_generation, contract_major, consumer_namespace)
    if category then
        local detail = category == contracts.ErrorCategory.INVALID_ARGUMENT and
            'Map-location prompt handle is malformed.' or
            category == contracts.ErrorCategory.STALE_HANDLE and
            'Map-location prompt handle belongs to another runtime generation.' or
            'Map-location prompt handle belongs to another service domain.'
        fail(category, detail)
    end
    return identity
end

---Rolls back detached preparation without publishing prompt ownership.
---@param resources table
function UserPromptService:_rollback_preparation(resources)
    local activation = self._activation
    if resources.indicator ~= nil then
        pcall(activation.rollback_indicator, resources.indicator)
    end
    if resources.render ~= nil then
        pcall(activation.rollback_render, resources.render)
    end
    if resources.input ~= nil then
        pcall(activation.rollback_input, resources.input)
    end
end

---Transactionally admits one copied request into the process-wide pending slot.
---@param request dwarfuicore.MapLocationPromptRequest
---@param contract_major integer
---@return dwarfuicore.MapLocationPrompt handle
function UserPromptService:start(request, contract_major)
    assert(values.MapLocationPromptRequest.is_instance(request),
        'DwarfUICore UserPrompt service requires a request snapshot.')
    assert(math.type(contract_major) == 'integer' and contract_major > 0,
        'DwarfUICore UserPrompt contract major must be positive.')
    local copied_request = request
    local state = self._state
    if state.blocked_namespace == copied_request.namespace then
        state.busy_rejection_count = state.busy_rejection_count + 1
        fail(contracts.ErrorCategory.SERVICE_BUSY,
            'Another process-wide prompt is active or terminating.')
    end
    if state.availability ~= UserPromptAvailability.AVAILABLE then
        fail(contracts.ErrorCategory.SERVICE_UNHEALTHY,
            'The UserPrompt runtime is unavailable.')
    end
    if state.status ~= UserPromptState.IDLE or state.pending ~= nil then
        state.busy_rejection_count = state.busy_rejection_count + 1
        fail(contracts.ErrorCategory.SERVICE_BUSY,
            'Another process-wide prompt is active or terminating.')
    end

    state.status = UserPromptState.ACTIVATING
    local activation = self._activation
    local resolved, surface = xpcall(activation.resolve_surface,
        debug.traceback)
    if not resolved then
        state.status = UserPromptState.IDLE
        fail(contracts.ErrorCategory.INVALID_ARGUMENT,
            'Prompt surface resolution failed: ' .. tostring(surface))
    end
    if surface == nil then
        state.status = UserPromptState.IDLE
        fail(contracts.ErrorCategory.INVALID_ARGUMENT,
            'No supported current map surface is available.')
    end

    local resources = {surface=surface}
    local prepared, preparation_failure = xpcall(function()
        resources.input = activation.prepare_input(surface)
        resources.render = activation.prepare_render(surface, copied_request)
        resources.indicator = activation.prepare_indicator(
            surface, copied_request, resources)
    end, debug.traceback)
    if not prepared then
        self:_rollback_preparation(resources)
        state.status = UserPromptState.IDLE
        fail(contracts.ErrorCategory.INVALID_ARGUMENT,
            'Prompt activation preparation failed: ' ..
                tostring(preparation_failure))
    end

    local allocated_ok, allocated, handle = pcall(function()
        local identity = identities.get_process_allocator():allocate_identity(
            state.runtime_generation, contracts.ServiceKind.USER_PROMPT,
            contract_major, copied_request.namespace)
        return identity, identities.create_prompt_handle(identity)
    end)
    if not allocated_ok then
        self:_rollback_preparation(resources)
        state.status = UserPromptState.IDLE
        fail(contracts.ErrorCategory.INVALID_ARGUMENT,
            'Prompt identity preparation failed: ' .. tostring(allocated))
    end
    local pending = {
        identity=identities.CompositeIdentity.new(allocated),
        request=copied_request,
        resources=resources,
    }
    activation.close_menu()
    state.pending = pending
    state.status = UserPromptState.ACTIVE
    activation.commit(resources)
    state.admitted_count = state.admitted_count + 1

    local invalidated, invalidation_failure =
        pcall(activation.invalidate, resources)
    if not invalidated then
        self:fail_active(invalidation_failure)
        fail(contracts.ErrorCategory.INVALID_ARGUMENT,
            'Prompt presentation invalidation failed: ' ..
                tostring(invalidation_failure))
    end
    return handle
end

---Invokes every cleanup port in fixed order and records contained failures.
---@param pending dwarfuicore.UserPromptPendingRequest
---@param cause dwarfuicore.UserPromptTerminalCause
---@return boolean succeeded
function UserPromptService:_run_cleanup(pending, cause)
    local state = self._state
    state.last_cleanup_failures = {}
    for _, name in ipairs(CLEANUP_ORDER) do
        local ok, failure = pcall(self._cleanup[name],
            copy_identity(pending.identity), pending.request, cause,
            pending.resources)
        if not ok then
            state.cleanup_failure_count = state.cleanup_failure_count + 1
            table.insert(state.last_cleanup_failures, {
                port=name,
                error=tostring(failure),
            })
        end
    end
    return #state.last_cleanup_failures == 0
end

---Marks only this published UserPrompt record unhealthy when it still matches.
function UserPromptService:_mark_runtime_record_unhealthy()
    local core = type(dfhack) == 'table' and dfhack.dwarfuicore or nil
    local runtime = type(core) == 'table' and
        core.service_provider_runtime or nil
    local services = type(runtime) == 'table' and runtime.services or nil
    local record = type(services) == 'table' and
        services[contracts.ServiceKind.USER_PROMPT] or nil
    local value = type(record) == 'table' and record.value or nil
    if type(value) == 'table' and value.service == self then
        record.health = contracts.ServiceHealth.UNHEALTHY
    end
end

---Makes callback-time admission unavailable for one lifecycle boundary.
---@param cause dwarfuicore.UserPromptTerminalCause
---@return boolean restore_after_callback
function UserPromptService:_begin_terminal_unavailability(cause)
    local availability = self._state.availability
    if availability == UserPromptAvailability.RETIRED or
            availability == UserPromptAvailability.DISABLED then
        return false
    end
    if cause == UserPromptTerminalCause.INPUT_ROOT_LOSS or
            cause == UserPromptTerminalCause.PRESENTATION_ROOT_LOSS or
            cause == UserPromptTerminalCause.WORLD_UNLOAD then
        self._state.availability =
            UserPromptAvailability.TRANSIENT_UNAVAILABLE
        self._state.unavailable_cause = cause
        return true
    end
    if cause == UserPromptTerminalCause.INTERNAL_FAILURE then
        self._state.availability = UserPromptAvailability.DISABLED
        self._state.unavailable_cause = cause
        self:_mark_runtime_record_unhealthy()
    elseif cause == UserPromptTerminalCause.CORE_RELOAD then
        self._state.availability = UserPromptAvailability.RETIRED
        self._state.unavailable_cause = cause
    end
    return false
end

---Completes one idempotent terminal decision and dispatches one callback.
---@param cause dwarfuicore.UserPromptTerminalCause
---@param position? dwarfuicore.MapTilePosition
---@return boolean changed
function UserPromptService:_terminate(cause, position)
    assert(enum_contains(UserPromptTerminalCause, cause),
        'DwarfUICore UserPrompt terminal cause is invalid.')
    local state = self._state
    local pending = state.pending
    if pending == nil then return false end

    local selected_position = nil
    if cause == UserPromptTerminalCause.LEFT_RELEASE and position ~= nil then
        selected_position = {x=position.x, y=position.y, z=position.z}
    end
    state.pending = nil
    state.status = UserPromptState.TERMINATING
    local restore_availability = self:_begin_terminal_unavailability(cause)
    state.last_terminal_cause = cause
    state.last_terminal_identity = copy_identity(pending.identity)
    state.last_callback_error = nil
    state.terminal_count = state.terminal_count + 1
    state.terminal_cause_counts[cause] =
        (state.terminal_cause_counts[cause] or 0) + 1
    if cause == UserPromptTerminalCause.LEFT_RELEASE then
        state.completion_count = state.completion_count + 1
    else
        state.cancellation_count = state.cancellation_count + 1
    end

    local cleanup_succeeded = self:_run_cleanup(pending, cause)
    if not cleanup_succeeded then
        if state.availability ~= UserPromptAvailability.RETIRED then
            state.availability = UserPromptAvailability.DISABLED
            state.unavailable_cause = UserPromptTerminalCause.INTERNAL_FAILURE
            self:_mark_runtime_record_unhealthy()
        end
        restore_availability = false
    end
    state.status = UserPromptState.IDLE

    local callback = cause == UserPromptTerminalCause.LEFT_RELEASE and
        pending.request.on_select or pending.request.on_cancel
    if callback ~= nil then
        local ok, failure
        if cause == UserPromptTerminalCause.LEFT_RELEASE then
            ok, failure = pcall(callback, selected_position)
        else
            ok, failure = pcall(callback)
        end
        if not ok then
            state.callback_failure_count = state.callback_failure_count + 1
            state.last_callback_error = tostring(failure)
        end
    end
    if restore_availability and
            state.availability ==
                UserPromptAvailability.TRANSIENT_UNAVAILABLE then
        state.availability = UserPromptAvailability.AVAILABLE
        state.unavailable_cause = nil
    end
    return true
end

---Completes the active prompt with one detached map position or nil.
---@param position? dwarfuicore.MapTilePosition
---@return boolean changed
function UserPromptService:complete(position)
    return self:_terminate(UserPromptTerminalCause.LEFT_RELEASE, position)
end

---Cancels the active prompt for one internal terminal cause.
---@param cause dwarfuicore.UserPromptTerminalCause
---@return boolean changed
function UserPromptService:cancel_active(cause)
    assert(cause ~= UserPromptTerminalCause.LEFT_RELEASE,
        'DwarfUICore UserPrompt cancellation cannot use completion cause.')
    if cause == UserPromptTerminalCause.INTERNAL_FAILURE then
        return self:fail_active('Internal prompt failure.')
    end
    return self:_terminate(cause)
end

---Contains one internal failure, records it, and cancels the active prompt.
---@param failure any
---@return boolean changed
function UserPromptService:fail_active(failure)
    if not self:has_active_prompt() then return false end
    self._state.internal_failure_count =
        self._state.internal_failure_count + 1
    self._state.last_internal_error = tostring(failure)
    return self:_terminate(UserPromptTerminalCause.INTERNAL_FAILURE)
end

---Irrevocably retires this generation before dispatching reload cancellation.
---@return boolean changed
function UserPromptService:retire_for_reload()
    self._state.availability = UserPromptAvailability.RETIRED
    self._state.unavailable_cause = UserPromptTerminalCause.CORE_RELOAD
    return self:_terminate(UserPromptTerminalCause.CORE_RELOAD)
end

---Cancels one current-domain handle or returns false once terminal.
---@param handle dwarfuicore.MapLocationPrompt
---@param consumer_namespace string
---@param contract_major integer
---@return boolean cancelled
function UserPromptService:cancel(handle, consumer_namespace, contract_major)
    local identity = self:_validate_handle(
        handle, consumer_namespace, contract_major)
    local pending = self._state.pending
    if pending == nil or not identities.CompositeIdentity.equals(
            pending.identity, identity) then
        return false
    end
    return self:_terminate(UserPromptTerminalCause.API_CANCEL)
end

---Returns whether one current-domain handle is the active prompt.
---@param handle dwarfuicore.MapLocationPrompt
---@param consumer_namespace string
---@param contract_major integer
---@return boolean active
function UserPromptService:is_active(handle, consumer_namespace, contract_major)
    local identity = self:_validate_handle(
        handle, consumer_namespace, contract_major)
    local pending = self._state.pending
    return pending ~= nil and identities.CompositeIdentity.equals(
        pending.identity, identity)
end

---Cancels only the active prompt owned by one namespace and contract.
---@param consumer_namespace string
---@param contract_major integer
---@return boolean changed
function UserPromptService:clear_namespace(consumer_namespace, contract_major)
    namespaces.validate(consumer_namespace)
    assert(math.type(contract_major) == 'integer' and contract_major > 0,
        'DwarfUICore UserPrompt contract major must be positive.')
    local pending = self._state.pending
    if pending == nil or pending.identity.namespace ~= consumer_namespace or
            pending.identity.contract_major ~= contract_major then
        return false
    end
    self._state.blocked_namespace = consumer_namespace
    local changed = self:_terminate(UserPromptTerminalCause.NAMESPACE_CLEAR)
    self._state.blocked_namespace = nil
    return changed
end

---Returns callback-free prompt state and transition diagnostics.
---@return table diagnostics
function UserPromptService:get_diagnostics()
    local state = self._state
    local pending = state.pending
    local cause_counts = {}
    for cause, count in pairs(state.terminal_cause_counts) do
        cause_counts[cause] = count
    end
    local cleanup_failures = {}
    for index, failure in ipairs(state.last_cleanup_failures) do
        cleanup_failures[index] = {
            port=failure.port,
            error=failure.error,
        }
    end
    return {
        api_version=state.api_version,
        runtime_generation=state.runtime_generation,
        state=state.status,
        availability=state.availability,
        unavailable_cause=state.unavailable_cause,
        active=pending ~= nil,
        active_identity=pending and copy_identity(pending.identity) or nil,
        active_namespace=pending and pending.identity.namespace or nil,
        blocked_namespace=state.blocked_namespace,
        admitted_count=state.admitted_count,
        busy_rejection_count=state.busy_rejection_count,
        terminal_count=state.terminal_count,
        completion_count=state.completion_count,
        cancellation_count=state.cancellation_count,
        callback_failure_count=state.callback_failure_count,
        cleanup_failure_count=state.cleanup_failure_count,
        internal_failure_count=state.internal_failure_count,
        terminal_cause_counts=cause_counts,
        last_terminal_cause=state.last_terminal_cause,
        last_terminal_identity=copy_identity(state.last_terminal_identity),
        last_callback_error=state.last_callback_error,
        last_internal_error=state.last_internal_error,
        last_cleanup_failures=cleanup_failures,
    }
end

dfhack.dwarfuicore = dfhack.dwarfuicore or {}
local runtime_state = dfhack.dwarfuicore.service_provider_runtime
local runtime_generation = runtime_state and runtime_state.generation or 1
local process_state = dfhack.dwarfuicore[SERVICE_SLOT]
if process_state and process_state.api_version ~= API_VERSION then
    error(('Conflicting DwarfUICore UserPrompt service versions: process has ' ..
        '%s, requested %s.'):format(tostring(process_state.api_version),
            tostring(API_VERSION)))
end
if process_state then
    assert(process_state.runtime_generation == runtime_generation,
        'DwarfUICore UserPrompt service belongs to another runtime generation.')
    assert(type(process_state.service) == 'table',
        'DwarfUICore UserPrompt process state is incomplete.')
    service = process_state.service
else
    process_state = new_state(runtime_generation)
    service = UserPromptService.new(process_state)
    process_state.service = service
    dfhack.dwarfuicore[SERVICE_SLOT] = process_state
end
