--@ module=true

local contracts = reqscript('dwarfuicore/service_provider/contracts')
local identities = reqscript('dwarfuicore/service_provider/identity')
local immutable_proxy = reqscript('dwarfuicore/service_provider/immutable_proxy')
local runtime = reqscript('dwarfuicore/service_provider/runtime')

local PREFIX_BY_SERVICE_KIND = {
    [contracts.ServiceKind.TOOLTIP]='DwarfUICore TooltipServiceApi:',
    [contracts.ServiceKind.CONTEXT_MENU]='DwarfUICore ContextMenuServiceApi:',
    [contracts.ServiceKind.USER_PROMPT]='DwarfUICore UserPromptServiceApi:',
}

---Provides namespace-scoped access to the shared tooltip runtime.
---@class dwarfuicore.TooltipServiceApi
---@field get_contract_version fun(self: dwarfuicore.TooltipServiceApi): integer
---@field get_namespace fun(self: dwarfuicore.TooltipServiceApi): string
---@field register fun(self: dwarfuicore.TooltipServiceApi, widget: gui.View): boolean created
---@field unregister fun(self: dwarfuicore.TooltipServiceApi, widget: gui.View): boolean removed
---@field register_map_tile fun(self: dwarfuicore.TooltipServiceApi, options: dwarfuicore.MapTileTooltipRegistrationOptions): dwarfuicore.MapTileTooltipRegistration
---@field update_map_tile fun(self: dwarfuicore.TooltipServiceApi, handle: dwarfuicore.MapTileTooltipRegistration, update: dwarfuicore.MapTileTooltipUpdate): boolean updated
---@field unregister_map_tile fun(self: dwarfuicore.TooltipServiceApi, handle: dwarfuicore.MapTileTooltipRegistration): boolean removed
---@field clear_namespace fun(self: dwarfuicore.TooltipServiceApi): boolean changed

---Provides namespace-scoped access to the shared context-menu runtime.
---@class dwarfuicore.ContextMenuServiceApi
---@field get_contract_version fun(self: dwarfuicore.ContextMenuServiceApi): integer
---@field get_namespace fun(self: dwarfuicore.ContextMenuServiceApi): string
---@field register fun(self: dwarfuicore.ContextMenuServiceApi, widget: gui.View, definition: dwarfuicore.ContextMenuDefinition): boolean created
---@field update fun(self: dwarfuicore.ContextMenuServiceApi, widget: gui.View, definition: dwarfuicore.ContextMenuDefinition): boolean updated
---@field unregister fun(self: dwarfuicore.ContextMenuServiceApi, widget: gui.View): boolean removed
---@field register_map_tile fun(self: dwarfuicore.ContextMenuServiceApi, options: dwarfuicore.ContextMenuMapRegistrationOptions): dwarfuicore.ContextMenuMapRegistration
---@field update_map_tile fun(self: dwarfuicore.ContextMenuServiceApi, handle: dwarfuicore.ContextMenuMapRegistration, update: dwarfuicore.ContextMenuMapRegistrationUpdate): boolean updated
---@field unregister_map_tile fun(self: dwarfuicore.ContextMenuServiceApi, handle: dwarfuicore.ContextMenuMapRegistration): boolean removed
---@field clear_namespace fun(self: dwarfuicore.ContextMenuServiceApi): boolean changed

---An exact fortress-map coordinate copied at an API boundary.
---@class dwarfuicore.MapTilePosition
---@field x integer
---@field y integer
---@field z integer

---A captured interface-cell coordinate copied for callback dispatch.
---@class dwarfuicore.ScreenPosition
---@field x integer
---@field y integer

---A presentation owner that can resolve to a currently presented root.
---@alias dwarfuicore.PresentationOwner gui.View|gui.ZScreen

---Options for one exact map-tile tooltip registration.
---@class dwarfuicore.MapTileTooltipRegistrationOptions
---@field owner dwarfuicore.PresentationOwner
---@field pos dwarfuicore.MapTilePosition
---@field tooltip? string

---Complete mutable replacement state for a map-tile tooltip registration.
---@class dwarfuicore.MapTileTooltipUpdate
---@field pos dwarfuicore.MapTilePosition
---@field tooltip? string

---Opaque identity and lifetime handle for one map-tile tooltip registration.
---@class dwarfuicore.MapTileTooltipRegistration

---One selectable context-menu entry.
---@class dwarfuicore.ContextMenuEntry
---@field label string
---@field on_select fun(context: dwarfuicore.ContextMenuSelectionContext)
---@field fg? integer
---@field bg? integer

---One validated context-menu contribution.
---@class dwarfuicore.ContextMenuDefinition
---@field title? string
---@field fg? integer
---@field bg? integer
---@field entries dwarfuicore.ContextMenuEntry[]

---Options for one exact map-tile context-menu contribution.
---@class dwarfuicore.ContextMenuMapRegistrationOptions
---@field owner dwarfuicore.PresentationOwner
---@field pos dwarfuicore.MapTilePosition
---@field definition dwarfuicore.ContextMenuDefinition

---Complete mutable replacement state for a map-tile menu contribution.
---@class dwarfuicore.ContextMenuMapRegistrationUpdate
---@field pos dwarfuicore.MapTilePosition
---@field definition dwarfuicore.ContextMenuDefinition

---Opaque identity and lifetime handle for one map-tile menu contribution.
---@class dwarfuicore.ContextMenuMapRegistration

---Copied source context passed to exactly one contributing entry callback.
---@class dwarfuicore.ContextMenuSelectionContext
---@field screen_position dwarfuicore.ScreenPosition
---@field map_position? dwarfuicore.MapTilePosition
---@field source gui.View|dwarfuicore.ContextMenuMapRegistration
---@field source_root dwarfuicore.PresentationOwner
---@field owner? dwarfuicore.PresentationOwner

---Raises one namespace-bound API error with its stable public category.
---@param service_kind dwarfuicore.ServiceKind
---@param category dwarfuicore.ErrorCategory
---@param detail string
local function fail(service_kind, category, detail)
    local prefix = assert(PREFIX_BY_SERVICE_KIND[service_kind],
        'DwarfUICore API service kind is invalid.')
    error(('%s [%s] %s'):format(prefix, contracts.get_error_token(category),
        detail), 0)
end

---Creates immutable namespace-bound APIs over one versioned private facade.
---@param service_kind dwarfuicore.ServiceKind
---@param label string
---@param operation_names string[]
---@return dwarfuicore.ImmutableProxyFactory factory
function new_factory(service_kind, label, operation_names)
    assert(PREFIX_BY_SERVICE_KIND[service_kind],
        'DwarfUICore API service kind is invalid.')
    assert(type(label) == 'string' and label ~= '',
        'DwarfUICore API label must be non-empty.')
    assert(type(operation_names) == 'table',
        'DwarfUICore API operations must be an array.')

    ---Validates that an API belongs to the current healthy runtime generation.
    ---@param backing dwarfuicore.ServiceAcquisitionMetadata
    ---@return table facade
    local function validate_api(backing)
        local ok, state = pcall(runtime.validate)
        if not ok then
            fail(service_kind, contracts.ErrorCategory.SERVICE_UNHEALTHY,
                'Runtime state is malformed or unavailable.')
        end
        if state.generation ~= backing.generation then
            fail(service_kind, contracts.ErrorCategory.STALE_API,
                'This API object belongs to a retired runtime generation.')
        end
        if state.status ~= contracts.RuntimeStatus.HEALTHY then
            fail(service_kind, contracts.ErrorCategory.SERVICE_UNHEALTHY,
                'The bound runtime is not healthy.')
        end
        if not pcall(runtime.get_service, service_kind, backing.generation) then
            fail(service_kind, contracts.ErrorCategory.SERVICE_UNHEALTHY,
                'The bound service is not healthy.')
        end
        if type(backing.facade) ~= 'table' then
            fail(service_kind, contracts.ErrorCategory.SERVICE_UNHEALTHY,
                'The bound service facade is malformed.')
        end
        return backing.facade
    end

    ---Classifies a map handle before any delegate can mutate state.
    ---@param backing dwarfuicore.ServiceAcquisitionMetadata
    ---@param handle any
    local function validate_handle(backing, handle)
        local identity = identities.get_map_handle_identity(handle)
        if identity == nil then
            fail(service_kind, contracts.ErrorCategory.INVALID_ARGUMENT,
                'Map registration handle is malformed.')
        end
        if identity.runtime_generation ~= backing.generation then
            fail(service_kind, contracts.ErrorCategory.STALE_HANDLE,
                'Map registration handle belongs to another runtime generation.')
        end
        if identity.service_kind ~= service_kind or
                identity.contract_major ~= backing.contract_major or
                identity.namespace ~= backing.namespace then
            fail(service_kind, contracts.ErrorCategory.FOREIGN_HANDLE,
                'Map registration handle belongs to another service domain.')
        end
    end

    local factory
    local methods = {}

    ---Returns the exact contract major after validating API liveness.
    ---@param self table
    ---@return integer
    function methods:get_contract_version()
        local backing = factory:get_backing(self)
        if not backing then
            fail(service_kind, contracts.ErrorCategory.INVALID_ARGUMENT,
                'API receiver is invalid.')
        end
        validate_api(backing)
        return backing.contract_major
    end

    ---Returns the permanently bound consumer namespace after validation.
    ---@param self table
    ---@return string
    function methods:get_namespace()
        local backing = factory:get_backing(self)
        if not backing then
            fail(service_kind, contracts.ErrorCategory.INVALID_ARGUMENT,
                'API receiver is invalid.')
        end
        validate_api(backing)
        return backing.namespace
    end

    for _, operation_name in ipairs(operation_names) do
        assert(type(operation_name) == 'string' and operation_name ~= '',
            'DwarfUICore API operation name is invalid.')
        local name = operation_name
        methods[name] = function(self, ...)
            local backing = factory:get_backing(self)
            if not backing then
                fail(service_kind, contracts.ErrorCategory.INVALID_ARGUMENT,
                    'API receiver is invalid.')
            end
            local facade = validate_api(backing)
            local operation = facade[name]
            if type(operation) ~= 'function' then
                fail(service_kind, contracts.ErrorCategory.SERVICE_UNHEALTHY,
                    'The bound service facade is incomplete.')
            end
            if name == 'update_map_tile' or name == 'unregister_map_tile' then
                validate_handle(backing, select(1, ...))
            end
            local result = table.pack(pcall(operation, backing.namespace,
                backing.contract_major, ...))
            if not result[1] then
                fail(service_kind, contracts.ErrorCategory.INVALID_ARGUMENT,
                    tostring(result[2]))
            end
            return table.unpack(result, 2, result.n)
        end
    end

    factory = immutable_proxy.new_factory(label, methods)
    return factory
end
