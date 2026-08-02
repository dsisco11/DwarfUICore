--@ module=true

-- Weak widget/map registration lifecycle and attachment-root discovery.

local definitions = reqscript('dwarfuicore/context_menu/definition')
local map_targets = reqscript('dwarfuicore/context_menu/map_target')
local root_discovery = reqscript('dwarfuicore/context_menu/root_discovery')
local targets = reqscript('dwarfuicore/context_menu/target')
local contracts = reqscript('dwarfuicore/service_provider/contracts')
local identities = reqscript('dwarfuicore/service_provider/identity')
local namespaces = reqscript('dwarfuicore/service_provider/namespace')
local WidgetTargetStore =
    reqscript('dwarfuicore/service_provider/weak_store').WidgetTargetStore
local ViewRootResolver =
    reqscript('dwarfuicore/view_root_resolver').ViewRootResolver

local MODULE_GENERATION_SLOT = 'context_menu_registration_generation'
local MANAGER_SLOT = 'context_menu_registration_manager'
local DEFAULT_NAMESPACE = 'dwarfuicore'
local DEFAULT_CONTRACT_MAJOR = 1

dfhack.dwarfuicore = dfhack.dwarfuicore or {}
local existing_manager = dfhack.dwarfuicore[MANAGER_SLOT]
local runtime_state = dfhack.dwarfuicore.service_provider_runtime
local runtime_generation = runtime_state and runtime_state.generation or 0
if existing_manager and runtime_generation > 0 then
    assert(existing_manager._runtime_generation == runtime_generation,
        'DwarfUICore context-menu registrations belong to another runtime generation.')
end
if not existing_manager then
    dfhack.dwarfuicore[MODULE_GENERATION_SLOT] =
        (dfhack.dwarfuicore[MODULE_GENERATION_SLOT] or 0) + 1
end
local module_generation = dfhack.dwarfuicore[MODULE_GENERATION_SLOT]

---Validates one namespace-bound context-menu ownership domain.
---@param consumer_namespace any
---@param contract_major? any
---@return string consumer_namespace
---@return integer contract_major
local function validate_domain(consumer_namespace, contract_major)
    namespaces.validate(consumer_namespace)
    contract_major = contract_major or DEFAULT_CONTRACT_MAJOR
    assert(math.type(contract_major) == 'integer' and contract_major > 0,
        'DwarfUICore context-menu contract major must be positive.')
    return consumer_namespace, contract_major
end

---@class dwarfuicore.ContextMenuWidgetCandidate
---@field identity table
---@field sequence integer
---@field source any
---@field root any
---@field _definition dwarfuicore.ContextMenuDefinitionSlot
ContextMenuWidgetCandidate = {}
ContextMenuWidgetCandidate.__index = ContextMenuWidgetCandidate

---@class dwarfuicore.ContextMenuRegistrationManagerOptions
---@field root_resolver? dwarfuicore.ViewRootResolver
---@field scheduler? fun(callback: function)
---@field printer? fun(message: string)
---@field on_roots_changed? fun(roots: table<any, boolean>)
---@field on_failure? fun(message: string)
---@field is_menu_open? fun(): boolean

---@class dwarfuicore.ContextMenuRegistrationManager
---@field _module_generation integer
---@field _runtime_generation integer
---@field _root_resolver dwarfuicore.ViewRootResolver
---@field _allocator dwarfuicore.ProcessIdentityAllocator
---@field _widget_store dwarfuicore.WidgetTargetStore
---@field _map_targets dwarfuicore.ContextMenuMapTargetRegistry
---@field _root_discovery dwarfuicore.ContextMenuRootDiscovery
---@field _root_observer fun(roots: table<any, boolean>)|nil
---@field _failure_observer fun(message: string)|nil
---@field _removal_observer fun(identity: table)|nil
---@field _menu_open_predicate fun(): boolean
---@field _disabled boolean
---@field _failure string|nil
---@field _retired boolean
ContextMenuRegistrationManager = {}
ContextMenuRegistrationManager.__index = ContextMenuRegistrationManager

---Returns whether a parent still contains one child by identity.
---@param parent any
---@param child any
---@return boolean
local function parent_contains_child(parent, child)
    for _, candidate in ipairs(parent.subviews or {}) do
        if candidate == child then return true end
    end
    return false
end

---Finds the structurally attached root without applying target eligibility.
---This intentionally ignores visibility, activity, overlay enablement, current
---presentation, and layout so an owning screen can keep its reversible input
---wrapper while a registration is temporarily ineligible.
---@param owner any
---@param allow_owner_root boolean|nil
---@return any|nil
function find_attachment_root(owner, allow_owner_root)
    if type(owner) ~= 'table' then return nil end
    local current = owner
    local seen = {}
    local attached = false
    while current and not seen[current] do
        seen[current] = true
        local parent = current.parent_view
        if not parent then
            return (attached or allow_owner_root) and current or nil
        end
        if not parent_contains_child(parent, current) then return nil end
        attached = true
        current = parent
    end
    return nil
end

---Returns an isolated opening definition for this widget candidate.
---@return dwarfuicore.ContextMenuDefinitionSnapshot
function ContextMenuWidgetCandidate:get_definition_snapshot()
    return self._definition:snapshot()
end

---Creates one weak registration manager for the active runtime generation.
---@param options? dwarfuicore.ContextMenuRegistrationManagerOptions
---@return dwarfuicore.ContextMenuRegistrationManager
function ContextMenuRegistrationManager.new(options)
    options = options or {}
    assert(type(options) == 'table',
        'DwarfUICore context-menu registration options must be a table.')
    assert(options.root_resolver == nil or
            type(options.root_resolver.resolve) == 'function',
        'DwarfUICore context-menu root resolver must resolve owners.')
    assert(options.on_roots_changed == nil or
            type(options.on_roots_changed) == 'function',
        'DwarfUICore context-menu root observer must be a function.')
    assert(options.on_failure == nil or
            type(options.on_failure) == 'function',
        'DwarfUICore context-menu failure observer must be a function.')
    assert(options.is_menu_open == nil or
            type(options.is_menu_open) == 'function',
        'DwarfUICore context-menu open predicate must be a function.')

    local allocator = identities.get_process_allocator()
    local resolver = options.root_resolver or ViewRootResolver.new()
    local manager = setmetatable({
        _module_generation=module_generation,
        _runtime_generation=runtime_generation,
        _root_resolver=resolver,
        _allocator=allocator,
        _widget_store=WidgetTargetStore.new(allocator),
        _root_observer=options.on_roots_changed,
        _failure_observer=options.on_failure,
        _removal_observer=nil,
        _menu_open_predicate=options.is_menu_open or function() return false end,
        _disabled=false,
        _failure=nil,
        _retired=false,
    }, ContextMenuRegistrationManager)
    manager._map_targets = map_targets.ContextMenuMapTargetRegistry.new{
        allocator=allocator,
        runtime_generation=runtime_generation > 0 and runtime_generation or 1,
        root_resolver=resolver,
        find_attachment_root=find_attachment_root,
    }
    manager._root_discovery =
        root_discovery.ContextMenuRootDiscovery.new{
            has_demand=function() return manager:_has_discovery_demand() end,
            discover=function() return manager:_discover_attachment_roots() end,
            on_roots_changed=function(roots)
                manager:_publish_attachment_roots(roots)
            end,
            on_failure=function(message)
                manager:_handle_discovery_failure(message)
            end,
            scheduler=options.scheduler,
            printer=options.printer,
        }
    return manager
end

---Returns whether this manager is the active registration module generation.
---@return boolean
function ContextMenuRegistrationManager:_module_is_current()
    local current = self._module_generation ==
        dfhack.dwarfuicore[MODULE_GENERATION_SLOT]
    if not current and not self._retired then self:_retire_stale() end
    return current and not self._retired
end

---Destructively retires registrations held by a stale manager reference.
function ContextMenuRegistrationManager:_retire_stale()
    if self._retired then return end
    self:clear()
    self._root_observer = nil
    self._failure_observer = nil
    self._menu_open_predicate = function() return false end
    self._retired = true
end

---Returns the count of currently live weak widget registrations.
---@return integer
function ContextMenuRegistrationManager:widget_registration_count()
    return self._widget_store:contribution_count()
end

---Returns the count of all currently live widget and map registrations.
---@return integer
function ContextMenuRegistrationManager:registration_count()
    return self:widget_registration_count() +
        self._map_targets:registration_count()
end

---Returns the count of currently live weak map registrations.
---@return integer
function ContextMenuRegistrationManager:map_registration_count()
    return self._map_targets:registration_count()
end

---Returns whether discovery must remain alive for registrations or a menu.
---@return boolean
function ContextMenuRegistrationManager:_has_discovery_demand()
    if self._disabled or not self:_module_is_current() then return false end
    return self:registration_count() > 0 or
        not not self._menu_open_predicate()
end

---Discovers only roots reachable from live registered widgets and map owners.
---@return table<any, boolean>
function ContextMenuRegistrationManager:_discover_attachment_roots()
    local roots = setmetatable({}, {__mode='k'})
    self._widget_store:for_each_contribution(function(widget)
        local root = find_attachment_root(widget, false)
        if root then roots[root] = true end
    end)
    for root in pairs(self._map_targets:get_attachment_roots()) do
        roots[root] = true
    end
    return roots
end

---Publishes current attachment roots to the reversible-hook collaborator.
---@param roots table<any, boolean>
function ContextMenuRegistrationManager:_publish_attachment_roots(roots)
    if self._root_observer then self._root_observer(roots) end
end

---Disables this manager generation after a contained discovery failure.
---@param message string
function ContextMenuRegistrationManager:_handle_discovery_failure(message)
    self._disabled = true
    self._failure = message
    if self._failure_observer then self._failure_observer(message) end
end

---Disables registration discovery for this generation without dropping data.
---The service uses this after a contained internal failure so no callback
---chain survives while input handling is transparent.
---@param message? string
---@return boolean changed
function ContextMenuRegistrationManager:disable(message)
    local changed = not self._disabled
    self._disabled = true
    self._failure = message or self._failure
    changed = self._root_discovery:stop() or changed
    return changed
end

---Starts or stops discovery after registration demand changes.
function ContextMenuRegistrationManager:_refresh_discovery()
    self._root_discovery:reconcile()
end

---Creates an eligible widget candidate without storing its source strongly.
---@param widget any
---@param record table
---@param root any
---@return dwarfuicore.ContextMenuWidgetCandidate
function ContextMenuRegistrationManager:_widget_candidate(
        widget, record, root, target_sequence, contribution_sequence)
    return setmetatable({
        identity=record.identity,
        sequence=target_sequence,
        contribution_sequence=contribution_sequence,
        source=widget,
        root=root,
        _definition=record.definition,
    }, ContextMenuWidgetCandidate)
end

---Registers or re-registers one weakly owned widget.
---Re-registration validates first, replaces only the definition, and retains
---the original identity and sequence.
---@param widget any
---@param definition dwarfuicore.ContextMenuDefinition
---@return boolean created
function ContextMenuRegistrationManager:register(consumer_namespace, widget,
        definition, contract_major)
    if definition == nil and type(consumer_namespace) == 'table' then
        definition, widget, consumer_namespace = widget, consumer_namespace,
            DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    assert(self:_module_is_current(),
        'DwarfUICore context-menu registration manager is stale.')
    assert(type(widget) == 'table',
        'DwarfUICore context-menu widget registration requires a widget.')
    local replacement =
        definitions.ContextMenuDefinitionSlot.new(definition)
    local existing = self._widget_store:get_contribution(
        widget, consumer_namespace)
    if existing then
        assert(existing.contract_major == contract_major,
            'DwarfUICore context-menu widget belongs to another contract major.')
        existing.definition = replacement
        self:_refresh_discovery()
        return false
    end

    local identity = self._allocator:allocate_identity(
        self._runtime_generation > 0 and self._runtime_generation or 1,
        contracts.ServiceKind.CONTEXT_MENU, contract_major, consumer_namespace)
    local _, contribution_sequence, created = self._widget_store:register(
        widget, consumer_namespace, {identity=identity,
            namespace=consumer_namespace, contract_major=contract_major,
            definition=replacement})
    assert(created, 'DwarfUICore context-menu widget publication conflicted.')
    local record = self._widget_store:get_contribution(widget,
        consumer_namespace)
    record.contribution_sequence = contribution_sequence
    self:_refresh_discovery()
    return true
end

---Atomically updates one known widget definition.
---@param widget any
---@param definition dwarfuicore.ContextMenuDefinition
---@return boolean updated
function ContextMenuRegistrationManager:update(consumer_namespace, widget,
        definition, contract_major)
    if definition == nil and type(consumer_namespace) == 'table' then
        definition, widget, consumer_namespace = widget, consumer_namespace,
            DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    assert(self:_module_is_current(),
        'DwarfUICore context-menu registration manager is stale.')
    local record = self._widget_store:get_contribution(widget,
        consumer_namespace)
    if not record or record.contract_major ~= contract_major then return false end
    local replacement =
        definitions.ContextMenuDefinitionSlot.new(definition)
    record.definition = replacement
    return true
end

---Explicitly unregisters one widget and updates discovery demand.
---@param widget any
---@return boolean removed
function ContextMenuRegistrationManager:unregister(consumer_namespace, widget,
        contract_major)
    if widget == nil and type(consumer_namespace) == 'table' then
        widget, consumer_namespace = consumer_namespace, DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    assert(self:_module_is_current(),
        'DwarfUICore context-menu registration manager is stale.')
    local record = self._widget_store:get_contribution(widget,
        consumer_namespace)
    if not record or record.contract_major ~= contract_major then return false end
    self._widget_store:remove(widget, consumer_namespace)
    if self._removal_observer then self._removal_observer(record.identity) end
    self:_refresh_discovery()
    return true
end

---Resolves one widget through strict current target eligibility.
---@param widget any
---@return dwarfuicore.ContextMenuWidgetCandidate|nil
function ContextMenuRegistrationManager:resolve_widget(widget)
    if self._disabled or not self:_module_is_current() then return nil end
    local record, contribution_sequence = self._widget_store:get_winner(widget)
    if not record then return nil end
    local root = self._root_resolver:resolve(widget, false)
    if not root then return nil end
    local target_sequence = self._widget_store:get_sequences(widget,
        record.namespace)
    return self:_widget_candidate(widget, record, root, target_sequence,
        contribution_sequence)
end

---Returns all eligible namespace contributions for one physical widget target.
---@param widget any
---@return dwarfuicore.ContextMenuWidgetCandidate[] candidates
function ContextMenuRegistrationManager:resolve_widget_contributions(widget)
    if self._disabled or not self:_module_is_current() then return {} end
    local root = self._root_resolver:resolve(widget, false)
    if not root then return {} end
    local candidates = {}
    self._widget_store:for_each_contribution(function(candidate_widget,
            _, record, target_sequence, contribution_sequence)
        if candidate_widget == widget then
            table.insert(candidates, self:_widget_candidate(candidate_widget,
                record, root, target_sequence, contribution_sequence))
        end
    end)
    table.sort(candidates, function(left, right)
        return left.contribution_sequence < right.contribution_sequence
    end)
    return candidates
end

---Resolves one composite widget identity through strict current eligibility.
---@param identity table
---@return dwarfuicore.ContextMenuWidgetCandidate|nil
function ContextMenuRegistrationManager:resolve_widget_identity(identity)
    if self._disabled or not self:_module_is_current() then return nil end
    local resolved
    self._widget_store:for_each_contribution(function(widget, _, record)
        if resolved == nil and identities.CompositeIdentity.equals(
                record.identity, identity) then
            local root = self._root_resolver:resolve(widget, false)
            if root then
                local target_sequence, contribution_sequence =
                    self._widget_store:get_sequences(widget, record.namespace)
                resolved = self:_widget_candidate(widget, record, root,
                    target_sequence, contribution_sequence)
            end
        end
    end)
    return resolved
end

---Registers one exact map tile and refreshes shared discovery demand.
---@param options dwarfuicore.ContextMenuMapRegistrationOptions
---@return any handle
function ContextMenuRegistrationManager:register_map_tile(consumer_namespace,
        options, contract_major)
    if options == nil and type(consumer_namespace) == 'table' then
        options, consumer_namespace = consumer_namespace, DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    assert(self:_module_is_current(),
        'DwarfUICore context-menu registration manager is stale.')
    local handle = self._map_targets:register(
        consumer_namespace, options, contract_major)
    self:_refresh_discovery()
    return handle
end

---Atomically updates one known map handle.
---@param handle any
---@param update dwarfuicore.ContextMenuMapRegistrationUpdate
---@return boolean updated
function ContextMenuRegistrationManager:update_map_tile(consumer_namespace,
        handle, update, contract_major)
    if identities.is_map_handle(consumer_namespace) then
        update, handle, consumer_namespace = handle, consumer_namespace,
            DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    assert(self:_module_is_current(),
        'DwarfUICore context-menu registration manager is stale.')
    return self._map_targets:update(consumer_namespace, handle, update,
        contract_major)
end

---Explicitly unregisters one map handle and updates discovery demand.
---@param handle any
---@return boolean removed
function ContextMenuRegistrationManager:unregister_map_tile(consumer_namespace,
        handle, contract_major)
    if identities.is_map_handle(consumer_namespace) then
        handle, consumer_namespace = consumer_namespace, DEFAULT_NAMESPACE
    end
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    assert(self:_module_is_current(),
        'DwarfUICore context-menu registration manager is stale.')
    local identity = self._map_targets:get_identity(handle)
    local removed = self._map_targets:unregister(consumer_namespace, handle,
        contract_major)
    if removed then
        if self._removal_observer and identity then
            self._removal_observer(identity)
        end
        self:_refresh_discovery()
    end
    return removed
end

---Resolves one widget identity while requiring its original attached root.
---This deliberately omits only the current-presentation check because an
---open context-menu screen temporarily covers a valid Lua-screen source.
---@param identity table
---@param expected_root any
---@return dwarfuicore.ContextMenuWidgetCandidate|nil
function ContextMenuRegistrationManager:resolve_widget_identity_attached(
        identity, expected_root)
    if self._disabled or not self:_module_is_current() then return nil end
    local resolved
    self._widget_store:for_each_contribution(function(widget, _, record,
            target_sequence, contribution_sequence)
        if resolved == nil and identities.CompositeIdentity.equals(
                record.identity, identity) then
            local root = find_attachment_root(widget, false)
            if root == expected_root then
                resolved = self:_widget_candidate(widget, record, root,
                    target_sequence, contribution_sequence)
            end
        end
    end)
    return resolved
end

---Removes every widget and map contribution owned by one namespace.
---@param consumer_namespace string
---@param contract_major? integer
---@return boolean changed
function ContextMenuRegistrationManager:clear_namespace(consumer_namespace,
        contract_major)
    consumer_namespace, contract_major = validate_domain(
        consumer_namespace, contract_major)
    local removals = {}
    self._widget_store:for_each_contribution(function(widget, namespace,
            record)
        if namespace == consumer_namespace and
                record.contract_major == contract_major then
            table.insert(removals, widget)
        end
    end)
    local changed = false
    for _, widget in ipairs(removals) do
        local record = self._widget_store:get_contribution(widget,
            consumer_namespace)
        local removed = self._widget_store:remove(widget, consumer_namespace)
        if removed and record and self._removal_observer then
            self._removal_observer(record.identity)
        end
        changed = removed or changed
    end
    local maps = self._map_targets:clear_namespace(consumer_namespace,
        contract_major)
    changed = #maps > 0 or changed
    if self._removal_observer then
        for _, record in ipairs(maps) do self._removal_observer(record.identity) end
    end
    if changed then self:_refresh_discovery() end
    return changed
end

---Resolves one map handle through strict current target eligibility.
---@param handle any
---@return dwarfuicore.ContextMenuMapCandidate|nil
function ContextMenuRegistrationManager:resolve_map_tile(handle)
    if self._disabled or not self:_module_is_current() then return nil end
    return self._map_targets:resolve(handle)
end

---Resolves one composite map identity through strict current eligibility.
---@param identity table
---@return dwarfuicore.ContextMenuMapCandidate|nil
function ContextMenuRegistrationManager:resolve_map_identity(identity)
    if self._disabled or not self:_module_is_current() then return nil end
    return self._map_targets:resolve_identity(identity)
end

---Resolves an open map session against its original still-attached root.
---@param identity table
---@param expected_root any
---@return dwarfuicore.ContextMenuMapCandidate|nil
function ContextMenuRegistrationManager:resolve_open_map_identity(
        identity, expected_root)
    if self._disabled or not self:_module_is_current() then return nil end
    if rawget(expected_root, '_native') == nil then
        local candidate = self._map_targets:resolve_identity(identity)
        return candidate and candidate.root == expected_root and
            candidate or nil
    end
    return self._map_targets:resolve_identity_attached(
        identity, expected_root)
end

---Selects the latest eligible registration at one exact map position.
---@param position {x: integer, y: integer, z: integer}
---@return dwarfuicore.ContextMenuMapCandidate|nil
function ContextMenuRegistrationManager:detect_map_tile(position)
    if self._disabled or not self:_module_is_current() then return nil end
    return self._map_targets:detect(position)
end

---Returns eligible roots that must participate in pointer arbitration.
---Roots owned only by map registrations remain relevant because their
---blocking UI regions suppress map fallback.
---@return table<any, boolean>
function ContextMenuRegistrationManager:get_detection_roots()
    local roots = setmetatable({}, {__mode='k'})
    if self._disabled or not self:_module_is_current() then return roots end
    self._widget_store:for_each_contribution(function(widget)
        local root = self._root_resolver:resolve(widget, false)
        if root then roots[root] = true end
    end)
    for root in pairs(self._map_targets:get_eligible_roots()) do
        roots[root] = true
    end
    return roots
end

---Replaces the later service-owned root observer.
---@param observer fun(roots: table<any, boolean>)|nil
function ContextMenuRegistrationManager:set_root_observer(observer)
    assert(observer == nil or type(observer) == 'function',
        'DwarfUICore context-menu root observer must be a function.')
    self._root_observer = observer
    if observer then self._root_discovery:republish() end
end

---Replaces the later service-owned failure observer.
---@param observer fun(message: string)|nil
function ContextMenuRegistrationManager:set_failure_observer(observer)
    assert(observer == nil or type(observer) == 'function',
        'DwarfUICore context-menu failure observer must be a function.')
    self._failure_observer = observer
end

---Replaces the service observer called before explicit contribution removal.
---@param observer fun(identity: table)|nil
function ContextMenuRegistrationManager:set_removal_observer(observer)
    assert(observer == nil or type(observer) == 'function',
        'DwarfUICore context-menu removal observer must be a function.')
    self._removal_observer = observer
end

---Returns whether an open snapshot still has every contribution at its root.
---@param session dwarfuicore.ContextMenuOpenSession
---@return boolean valid
function ContextMenuRegistrationManager:validate_open_session(session)
    if self._disabled or not self:_module_is_current() or not session:is_valid() then
        return false
    end
    local root = session:get_source_root()
    for _, identity in ipairs(session:get_contribution_identities()) do
        local candidate = self:resolve_widget_identity_attached(identity, root) or
            self:resolve_open_map_identity(identity, root)
        if not candidate or candidate.root ~= root then return false end
    end
    return true
end

---Replaces the predicate that keeps discovery alive for an open menu.
---@param predicate fun(): boolean
function ContextMenuRegistrationManager:set_menu_open_predicate(predicate)
    assert(type(predicate) == 'function',
        'DwarfUICore context-menu open predicate must be a function.')
    self._menu_open_predicate = predicate
    self:_refresh_discovery()
end

---Clears registrations and discovery without retiring this manager.
---@return boolean changed
function ContextMenuRegistrationManager:clear()
    local changed = self:registration_count() > 0
    if self._removal_observer then
        self._widget_store:for_each_contribution(function(_, _, record)
            self._removal_observer(record.identity)
        end)
    end
    self._widget_store = WidgetTargetStore.new(self._allocator)
    local maps = self._map_targets:clear()
    if self._removal_observer then
        for _, record in ipairs(maps or {}) do self._removal_observer(record.identity) end
    end
    changed = #maps > 0 or changed
    changed = self._root_discovery:stop() or changed
    return changed
end

---Destructively clears registrations and owned discovery for this generation.
---@return boolean changed
function ContextMenuRegistrationManager:shutdown()
    local changed = self:clear()
    self._root_observer = nil
    self._failure_observer = nil
    self._menu_open_predicate = function() return false end
    self._retired = true
    return changed
end

---Returns registration, discovery, reload, and failure diagnostics.
---@return table
function ContextMenuRegistrationManager:get_diagnostics()
    local widget_contributions = {}
    self._widget_store:for_each_contribution(function(_, namespace, record,
            target_sequence, contribution_sequence)
        local identity = record.identity
        table.insert(widget_contributions, {identity={
            runtime_generation=identity.runtime_generation,
            service_kind=identity.service_kind,
            contract_major=identity.contract_major,
            namespace=namespace,
            local_identity=identity.local_identity,
        }, target_sequence=target_sequence,
            contribution_sequence=contribution_sequence})
    end)
    table.sort(widget_contributions, function(left, right)
        return left.contribution_sequence < right.contribution_sequence
    end)
    return {
        module_generation=self._module_generation,
        current=self:_module_is_current(),
        disabled=self._disabled,
        failure=self._failure,
        widget_registration_count=self:widget_registration_count(),
        map_registration_count=self._map_targets:registration_count(),
        widget_registration_sequence=self._allocator:snapshot().next_sequence,
        widget_contributions=widget_contributions,
        map=self._map_targets:get_diagnostics(),
        discovery=self._root_discovery:get_diagnostics(),
    }
end

manager = existing_manager or ContextMenuRegistrationManager.new()
dfhack.dwarfuicore[MANAGER_SLOT] = manager

---Registers or re-registers one widget through the process singleton.
---@param widget any
---@param definition dwarfuicore.ContextMenuDefinition
---@return boolean created
function register(consumer_namespace, widget, definition, contract_major)
    return manager:register(consumer_namespace, widget, definition,
        contract_major)
end

---Updates one singleton widget registration.
---@param widget any
---@param definition dwarfuicore.ContextMenuDefinition
---@return boolean updated
function update(consumer_namespace, widget, definition, contract_major)
    return manager:update(consumer_namespace, widget, definition,
        contract_major)
end

---Unregisters one singleton widget registration.
---@param widget any
---@return boolean removed
function unregister(consumer_namespace, widget, contract_major)
    return manager:unregister(consumer_namespace, widget, contract_major)
end

---Registers one singleton exact map-tile target.
---@param options dwarfuicore.ContextMenuMapRegistrationOptions
---@return any handle
function register_map_tile(consumer_namespace, options, contract_major)
    return manager:register_map_tile(consumer_namespace, options,
        contract_major)
end

---Updates one singleton exact map-tile target.
---@param handle any
---@param update dwarfuicore.ContextMenuMapRegistrationUpdate
---@return boolean updated
function update_map_tile(consumer_namespace, handle, update, contract_major)
    return manager:update_map_tile(consumer_namespace, handle, update,
        contract_major)
end

---Unregisters one singleton exact map-tile target.
---@param handle any
---@return boolean removed
function unregister_map_tile(consumer_namespace, handle, contract_major)
    return manager:unregister_map_tile(consumer_namespace, handle,
        contract_major)
end

---Returns all eligible exact-tile contributions in deterministic order.
---@param position {x: integer, y: integer, z: integer}
---@return dwarfuicore.ContextMenuMapCandidate[] candidates
function ContextMenuRegistrationManager:detect_map_contributions(position)
    if self._disabled or not self:_module_is_current() then return {} end
    return self._map_targets:detect_contributions(position)
end

---Removes every registration owned by one context-menu namespace.
---@param consumer_namespace string
---@param contract_major? integer
---@return boolean changed
function clear_namespace(consumer_namespace, contract_major)
    return manager:clear_namespace(consumer_namespace, contract_major)
end
