--@ module=true

local contracts = reqscript('dwarfuicore/service_provider/contracts')
local namespaces = reqscript('dwarfuicore/service_provider/namespace')
local runtime = reqscript('dwarfuicore/service_provider/runtime')

local PREFIX_BY_SERVICE_KIND = {
    [contracts.ServiceKind.TOOLTIP]='DwarfUICore TooltipServiceProvider:',
    [contracts.ServiceKind.CONTEXT_MENU]=
        'DwarfUICore ContextMenuServiceProvider:',
}

---@class dwarfuicore.ServiceAcquisitionAdapter
---@field initialize_service fun(generation: integer): table
---@field validate_service fun(service: table, generation: integer)
---@field build_facade fun(service: table, generation: integer): table
---@field validate_facade fun(facade: table, contract_major: integer)

---@alias dwarfuicore.ServiceAcquisitionAdapterLoader fun(): dwarfuicore.ServiceAcquisitionAdapter

---@class dwarfuicore.ServiceAcquisitionMetadata
---@field facade table
---@field contract_major integer
---@field namespace string
---@field generation integer
---@field service_kind dwarfuicore.ServiceKind

---Raises one provider-prefixed stable-category error.
---@param service_kind dwarfuicore.ServiceKind
---@param category dwarfuicore.ErrorCategory
---@param detail string
local function fail(service_kind, category, detail)
    local prefix = PREFIX_BY_SERVICE_KIND[service_kind]
    assert(prefix, 'DwarfUICore acquisition service kind is invalid.')
    error(('%s [%s] %s'):format(
        prefix, contracts.get_error_token(category), detail), 0)
end

---Returns whether a failure already has a stable provider prefix.
---@param failure any
---@return boolean
local function is_provider_failure(failure)
    return type(failure) == 'string' and
        failure:match('^DwarfUICore [A-Za-z]+ServiceProvider: %[[_A-Z]+%]') ~= nil
end

---Validates the private adapter after public arguments are accepted.
---@param adapter any
local function validate_adapter(adapter)
    assert(type(adapter) == 'table',
        'private provider adapter is missing')
    for _, field in ipairs{
            'initialize_service', 'validate_service', 'build_facade',
            'validate_facade',
        } do
        assert(type(adapter[field]) == 'function',
            ('private provider adapter is missing %s'):format(field))
    end
end

---Runs one private acquisition stage and renders contained failures.
---@param service_kind dwarfuicore.ServiceKind
---@param label string
---@param callback function
---@return ...
local function run_initialization_stage(service_kind, label, callback)
    local result = table.pack(pcall(callback))
    if result[1] then
        return table.unpack(result, 2, result.n)
    end
    if is_provider_failure(result[2]) then error(result[2], 0) end
    fail(service_kind, contracts.ErrorCategory.INITIALIZATION_FAILED,
        ('%s failed: %s Correct the provider implementation and retry; ' ..
            'use an explicit DwarfUICore reload if process-owned state changed.')
            :format(label, tostring(result[2])))
end

---Validates a service and distinguishes cached corruption from new failure.
---@param service_kind dwarfuicore.ServiceKind
---@param service_was_cached boolean
---@param callback function
---@return ...
local function run_service_validation_stage(service_kind, service_was_cached,
        callback)
    local result = table.pack(pcall(callback))
    if result[1] then
        return table.unpack(result, 2, result.n)
    end
    if is_provider_failure(result[2]) then error(result[2], 0) end
    if service_was_cached then
        fail(service_kind, contracts.ErrorCategory.SERVICE_UNHEALTHY,
            ('Published service contract is malformed: %s Acquisition will ' ..
                'not repair or replace it; restart the process or perform an ' ..
                'explicit DwarfUICore reload.'):format(tostring(result[2])))
    end
    fail(service_kind, contracts.ErrorCategory.INITIALIZATION_FAILED,
        ('Service contract validation failed: %s Correct the provider ' ..
            'implementation and retry; use an explicit DwarfUICore reload ' ..
            'if process-owned state changed.'):format(tostring(result[2])))
end

---Validates runtime state and renders it through the provider boundary.
---@param service_kind dwarfuicore.ServiceKind
---@return dwarfuicore.ServiceProviderRuntimeState state
local function validate_runtime(service_kind)
    local result = table.pack(pcall(runtime.validate))
    if not result[1] then
        fail(service_kind, contracts.ErrorCategory.SERVICE_UNHEALTHY,
            ('Runtime state is unavailable or malformed: %s Restart the ' ..
                'process or perform an explicit DwarfUICore reload.')
                :format(tostring(result[2])))
    end
    local state = result[2]
    if state.status ~= contracts.RuntimeStatus.HEALTHY then
        fail(service_kind, contracts.ErrorCategory.SERVICE_UNHEALTHY,
            'Runtime state is not healthy. Restart the process or perform ' ..
                'an explicit DwarfUICore reload.')
    end
    return state
end

---Acquires one validated versioned facade without constructing a public API.
---Public constructor arguments are validated before any adapter callback runs.
---@param service_kind dwarfuicore.ServiceKind
---@param contract_major integer
---@param load_adapter dwarfuicore.ServiceAcquisitionAdapterLoader
---@param requested_major any
---@param consumer_namespace any
---@return dwarfuicore.ServiceAcquisitionMetadata metadata
function acquire(service_kind, contract_major, load_adapter, requested_major,
        consumer_namespace)
    assert(PREFIX_BY_SERVICE_KIND[service_kind],
        'DwarfUICore acquisition service kind is invalid.')
    if math.type(requested_major) ~= 'integer' or requested_major <= 0 then
        fail(service_kind, contracts.ErrorCategory.INVALID_VERSION,
            'Contract major must be a positive integer.')
    end
    if not namespaces.is_valid(consumer_namespace) then
        fail(service_kind, contracts.ErrorCategory.INVALID_NAMESPACE,
            'Consumer namespace is missing or invalid.')
    end
    if math.type(contract_major) ~= 'integer' or contract_major <= 0 then
        fail(service_kind, contracts.ErrorCategory.INITIALIZATION_FAILED,
            'Private provider contract major is invalid. Correct the installation.')
    end
    if requested_major ~= contract_major then
        fail(service_kind, contracts.ErrorCategory.UNSUPPORTED_VERSION,
            ('Contract major %d is not implemented completely.')
                :format(requested_major))
    end
    if type(load_adapter) ~= 'function' then
        fail(service_kind, contracts.ErrorCategory.INITIALIZATION_FAILED,
            'Private provider implementation loader is missing. Correct the ' ..
                'installation or perform an explicit DwarfUICore reload.')
    end
    local adapter = run_initialization_stage(service_kind,
        'Private provider implementation loading', load_adapter)
    local adapter_ok, adapter_failure = pcall(validate_adapter, adapter)
    if not adapter_ok then
        fail(service_kind, contracts.ErrorCategory.INITIALIZATION_FAILED,
            ('Private provider implementation is incomplete: %s Correct the ' ..
                'installation or perform an explicit DwarfUICore reload.')
                :format(tostring(adapter_failure)))
    end
    local state = validate_runtime(service_kind)
    if state.initializing[service_kind] then
        fail(service_kind, contracts.ErrorCategory.INITIALIZATION_BUSY,
            'Service initialization is already active for this generation.')
    end
    local begin_result = table.pack(pcall(runtime.begin_service_acquisition,
        service_kind, contract_major))
    if not begin_result[1] then
        fail(service_kind, contracts.ErrorCategory.SERVICE_UNHEALTHY,
            ('Service state is malformed or unhealthy: %s Restart the ' ..
                'process or perform an explicit DwarfUICore reload.')
                :format(tostring(begin_result[2])))
    end
    state = begin_result[2]
    local generation = state.generation
    local service = begin_result[3]
    local facade = begin_result[4]
    local service_was_cached = service ~= nil
    local transaction_active = state.initializing[service_kind] == true
    local publication_required = facade == nil

    local result = table.pack(pcall(function()
        if not service then
            service = run_initialization_stage(service_kind,
                'Service prerequisite initialization', function()
                    return adapter.initialize_service(generation)
                end)
        end
        run_service_validation_stage(service_kind, service_was_cached,
            function()
                assert(type(service) == 'table',
                    'service initializer did not return a table')
                adapter.validate_service(service, generation)
            end)
        if not facade then
            facade = run_initialization_stage(service_kind,
                'Facade construction', function()
                    return adapter.build_facade(service, generation)
                end)
        end
        run_initialization_stage(service_kind, 'Facade contract validation',
            function()
                assert(type(facade) == 'table',
                    'facade constructor did not return a table')
                adapter.validate_facade(facade, contract_major)
            end)
        if transaction_active and publication_required then
            run_initialization_stage(service_kind, 'Facade publication',
                function()
                    runtime.publish_service_acquisition(service_kind,
                        contract_major, generation, service, facade)
                end)
        elseif transaction_active then
            runtime.cancel_service_acquisition(service_kind, generation)
        end
    end))
    if not result[1] then
        if transaction_active then
            runtime.cancel_service_acquisition(service_kind, generation)
        end
        error(result[2], 0)
    end

    return {
        facade=facade,
        contract_major=contract_major,
        namespace=consumer_namespace,
        generation=generation,
        service_kind=service_kind,
    }
end
