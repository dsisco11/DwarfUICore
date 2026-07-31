--@ module=true

-- Weak widget/map registration lifecycle and attachment-root discovery.

local definitions = reqscript('dwarfui/context_menu/definition')
local map_targets = reqscript('dwarfui/context_menu/map_target')
local root_discovery = reqscript('dwarfui/context_menu/root_discovery')
local targets = reqscript('dwarfui/context_menu/target')
local TooltipRootResolver =
    reqscript('dwarfui/tooltip_root_resolver').TooltipRootResolver

local MODULE_GENERATION_SLOT = 'context_menu_registration_generation'
local MANAGER_SLOT = 'context_menu_registration_manager'

dfhack.dwarfui = dfhack.dwarfui or {}
dfhack.dwarfui[MODULE_GENERATION_SLOT] =
    (dfhack.dwarfui[MODULE_GENERATION_SLOT] or 0) + 1
local module_generation = dfhack.dwarfui[MODULE_GENERATION_SLOT]

---@class dwarfui.ContextMenuWidgetCandidate
---@field identity integer
---@field sequence integer
---@field source any
---@field root any
---@field _definition dwarfui.ContextMenuDefinitionSlot
ContextMenuWidgetCandidate = {}
ContextMenuWidgetCandidate.__index = ContextMenuWidgetCandidate

---@class dwarfui.ContextMenuRegistrationManagerOptions
---@field root_resolver? dwarfui.TooltipRootResolver
---@field scheduler? fun(callback: function)
---@field printer? fun(message: string)
---@field on_roots_changed? fun(roots: table<any, boolean>)
---@field on_failure? fun(message: string)
---@field is_menu_open? fun(): boolean

---@class dwarfui.ContextMenuRegistrationManager
---@field _module_generation integer
---@field _root_resolver dwarfui.TooltipRootResolver
---@field _identity_allocator dwarfui.ContextMenuRegistrationIdentityAllocator
---@field _widget_registrations table<any, table>
---@field _widget_registration_sequence integer
---@field _map_targets dwarfui.ContextMenuMapTargetRegistry
---@field _root_discovery dwarfui.ContextMenuRootDiscovery
---@field _root_observer fun(roots: table<any, boolean>)|nil
---@field _failure_observer fun(message: string)|nil
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
---@return dwarfui.ContextMenuDefinitionSnapshot
function ContextMenuWidgetCandidate:get_definition_snapshot()
    return self._definition:snapshot()
end

---Creates one weak, destructive-reload registration manager.
---@param options? dwarfui.ContextMenuRegistrationManagerOptions
---@return dwarfui.ContextMenuRegistrationManager
function ContextMenuRegistrationManager.new(options)
    options = options or {}
    assert(type(options) == 'table',
        'DwarfUI context-menu registration options must be a table.')
    assert(options.root_resolver == nil or
            type(options.root_resolver.resolve) == 'function',
        'DwarfUI context-menu root resolver must resolve owners.')
    assert(options.on_roots_changed == nil or
            type(options.on_roots_changed) == 'function',
        'DwarfUI context-menu root observer must be a function.')
    assert(options.on_failure == nil or
            type(options.on_failure) == 'function',
        'DwarfUI context-menu failure observer must be a function.')
    assert(options.is_menu_open == nil or
            type(options.is_menu_open) == 'function',
        'DwarfUI context-menu open predicate must be a function.')

    local identity_allocator =
        targets.ContextMenuRegistrationIdentityAllocator.new()
    local resolver = options.root_resolver or TooltipRootResolver.new()
    local manager = setmetatable({
        _module_generation=module_generation,
        _root_resolver=resolver,
        _identity_allocator=identity_allocator,
        _widget_registrations=setmetatable({}, {__mode='k'}),
        _widget_registration_sequence=0,
        _root_observer=options.on_roots_changed,
        _failure_observer=options.on_failure,
        _menu_open_predicate=options.is_menu_open or function() return false end,
        _disabled=false,
        _failure=nil,
        _retired=false,
    }, ContextMenuRegistrationManager)
    manager._map_targets = map_targets.ContextMenuMapTargetRegistry.new{
        identity_allocator=identity_allocator,
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
        dfhack.dwarfui[MODULE_GENERATION_SLOT]
    if not current and not self._retired then self:_retire_stale() end
    return current and not self._retired
end

---Destructively retires registrations held by a stale manager reference.
function ContextMenuRegistrationManager:_retire_stale()
    if self._retired then return end
    self._retired = true
    self._widget_registrations = setmetatable({}, {__mode='k'})
    self._map_targets:clear()
    self._root_discovery:stop()
end

---Returns the count of currently live weak widget registrations.
---@return integer
function ContextMenuRegistrationManager:widget_registration_count()
    local count = 0
    for _ in pairs(self._widget_registrations) do count = count + 1 end
    return count
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
    for widget in pairs(self._widget_registrations) do
        local root = find_attachment_root(widget, false)
        if root then roots[root] = true end
    end
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

---Starts or stops discovery after registration demand changes.
function ContextMenuRegistrationManager:_refresh_discovery()
    self._root_discovery:reconcile()
end

---Creates an eligible widget candidate without storing its source strongly.
---@param widget any
---@param record table
---@param root any
---@return dwarfui.ContextMenuWidgetCandidate
function ContextMenuRegistrationManager:_widget_candidate(
        widget, record, root)
    return setmetatable({
        identity=record.identity,
        sequence=record.sequence,
        source=widget,
        root=root,
        _definition=record.definition,
    }, ContextMenuWidgetCandidate)
end

---Registers or re-registers one weakly owned widget.
---Re-registration validates first, replaces only the definition, and retains
---the original identity and sequence.
---@param widget any
---@param definition dwarfui.ContextMenuDefinition
---@return boolean created
function ContextMenuRegistrationManager:register(widget, definition)
    assert(self:_module_is_current(),
        'DwarfUI context-menu registration manager is stale.')
    assert(type(widget) == 'table',
        'DwarfUI context-menu widget registration requires a widget.')
    local replacement =
        definitions.ContextMenuDefinitionSlot.new(definition)
    local existing = self._widget_registrations[widget]
    if existing then
        existing.definition = replacement
        self:_refresh_discovery()
        return false
    end

    self._widget_registration_sequence =
        self._widget_registration_sequence + 1
    self._widget_registrations[widget] = {
        identity=self._identity_allocator:allocate(),
        sequence=self._widget_registration_sequence,
        definition=replacement,
    }
    self:_refresh_discovery()
    return true
end

---Atomically updates one known widget definition.
---@param widget any
---@param definition dwarfui.ContextMenuDefinition
---@return boolean updated
function ContextMenuRegistrationManager:update(widget, definition)
    assert(self:_module_is_current(),
        'DwarfUI context-menu registration manager is stale.')
    local record = self._widget_registrations[widget]
    if not record then return false end
    local replacement =
        definitions.ContextMenuDefinitionSlot.new(definition)
    record.definition = replacement
    return true
end

---Explicitly unregisters one widget and updates discovery demand.
---@param widget any
---@return boolean removed
function ContextMenuRegistrationManager:unregister(widget)
    assert(self:_module_is_current(),
        'DwarfUI context-menu registration manager is stale.')
    if not self._widget_registrations[widget] then return false end
    self._widget_registrations[widget] = nil
    self:_refresh_discovery()
    return true
end

---Resolves one widget through strict current target eligibility.
---@param widget any
---@return dwarfui.ContextMenuWidgetCandidate|nil
function ContextMenuRegistrationManager:resolve_widget(widget)
    if self._disabled or not self:_module_is_current() then return nil end
    local record = self._widget_registrations[widget]
    if not record then return nil end
    local root = self._root_resolver:resolve(widget, false)
    if not root then return nil end
    return self:_widget_candidate(widget, record, root)
end

---Resolves one numeric widget identity through strict current eligibility.
---@param identity integer
---@return dwarfui.ContextMenuWidgetCandidate|nil
function ContextMenuRegistrationManager:resolve_widget_identity(identity)
    if self._disabled or not self:_module_is_current() then return nil end
    for widget, record in pairs(self._widget_registrations) do
        if record.identity == identity then
            local root = self._root_resolver:resolve(widget, false)
            if root then
                return self:_widget_candidate(widget, record, root)
            end
            return nil
        end
    end
    return nil
end

---Registers one exact map tile and refreshes shared discovery demand.
---@param options dwarfui.ContextMenuMapRegistrationOptions
---@return any handle
function ContextMenuRegistrationManager:register_map_tile(options)
    assert(self:_module_is_current(),
        'DwarfUI context-menu registration manager is stale.')
    local handle = self._map_targets:register(options)
    self:_refresh_discovery()
    return handle
end

---Atomically updates one known map handle.
---@param handle any
---@param update dwarfui.ContextMenuMapRegistrationUpdate
---@return boolean updated
function ContextMenuRegistrationManager:update_map_tile(handle, update)
    assert(self:_module_is_current(),
        'DwarfUI context-menu registration manager is stale.')
    return self._map_targets:update(handle, update)
end

---Explicitly unregisters one map handle and updates discovery demand.
---@param handle any
---@return boolean removed
function ContextMenuRegistrationManager:unregister_map_tile(handle)
    assert(self:_module_is_current(),
        'DwarfUI context-menu registration manager is stale.')
    local removed = self._map_targets:unregister(handle)
    if removed then self:_refresh_discovery() end
    return removed
end

---Resolves one map handle through strict current target eligibility.
---@param handle any
---@return dwarfui.ContextMenuMapCandidate|nil
function ContextMenuRegistrationManager:resolve_map_tile(handle)
    if self._disabled or not self:_module_is_current() then return nil end
    return self._map_targets:resolve(handle)
end

---Resolves one numeric map identity through strict current eligibility.
---@param identity integer
---@return dwarfui.ContextMenuMapCandidate|nil
function ContextMenuRegistrationManager:resolve_map_identity(identity)
    if self._disabled or not self:_module_is_current() then return nil end
    return self._map_targets:resolve_identity(identity)
end

---Selects the latest eligible registration at one exact map position.
---@param position {x: integer, y: integer, z: integer}
---@return dwarfui.ContextMenuMapCandidate|nil
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
    for widget in pairs(self._widget_registrations) do
        local root = self._root_resolver:resolve(widget, false)
        if root then roots[root] = true end
    end
    for root in pairs(self._map_targets:get_eligible_roots()) do
        roots[root] = true
    end
    return roots
end

---Replaces the later service-owned root observer.
---@param observer fun(roots: table<any, boolean>)|nil
function ContextMenuRegistrationManager:set_root_observer(observer)
    assert(observer == nil or type(observer) == 'function',
        'DwarfUI context-menu root observer must be a function.')
    self._root_observer = observer
    if observer then self._root_discovery:republish() end
end

---Replaces the later service-owned failure observer.
---@param observer fun(message: string)|nil
function ContextMenuRegistrationManager:set_failure_observer(observer)
    assert(observer == nil or type(observer) == 'function',
        'DwarfUI context-menu failure observer must be a function.')
    self._failure_observer = observer
end

---Replaces the predicate that keeps discovery alive for an open menu.
---@param predicate fun(): boolean
function ContextMenuRegistrationManager:set_menu_open_predicate(predicate)
    assert(type(predicate) == 'function',
        'DwarfUI context-menu open predicate must be a function.')
    self._menu_open_predicate = predicate
    self:_refresh_discovery()
end

---Destructively clears registrations and owned discovery for this generation.
---@return boolean changed
function ContextMenuRegistrationManager:shutdown()
    local changed = self:registration_count() > 0
    self._retired = true
    self._widget_registrations = setmetatable({}, {__mode='k'})
    changed = self._map_targets:clear() or changed
    changed = self._root_discovery:stop() or changed
    return changed
end

---Returns registration, discovery, reload, and failure diagnostics.
---@return table
function ContextMenuRegistrationManager:get_diagnostics()
    return {
        module_generation=self._module_generation,
        current=self:_module_is_current(),
        disabled=self._disabled,
        failure=self._failure,
        widget_registration_count=self:widget_registration_count(),
        map_registration_count=self._map_targets:registration_count(),
        widget_registration_sequence=self._widget_registration_sequence,
        map=self._map_targets:get_diagnostics(),
        discovery=self._root_discovery:get_diagnostics(),
    }
end

local previous_manager = dfhack.dwarfui[MANAGER_SLOT]
if previous_manager and type(previous_manager.shutdown) == 'function' then
    previous_manager:shutdown()
end
manager = ContextMenuRegistrationManager.new()
dfhack.dwarfui[MANAGER_SLOT] = manager

---Registers or re-registers one widget through the process singleton.
---@param widget any
---@param definition dwarfui.ContextMenuDefinition
---@return boolean created
function register(widget, definition)
    return manager:register(widget, definition)
end

---Updates one singleton widget registration.
---@param widget any
---@param definition dwarfui.ContextMenuDefinition
---@return boolean updated
function update(widget, definition)
    return manager:update(widget, definition)
end

---Unregisters one singleton widget registration.
---@param widget any
---@return boolean removed
function unregister(widget)
    return manager:unregister(widget)
end

---Registers one singleton exact map-tile target.
---@param options dwarfui.ContextMenuMapRegistrationOptions
---@return any handle
function register_map_tile(options)
    return manager:register_map_tile(options)
end

---Updates one singleton exact map-tile target.
---@param handle any
---@param update dwarfui.ContextMenuMapRegistrationUpdate
---@return boolean updated
function update_map_tile(handle, update)
    return manager:update_map_tile(handle, update)
end

---Unregisters one singleton exact map-tile target.
---@param handle any
---@return boolean removed
function unregister_map_tile(handle)
    return manager:unregister_map_tile(handle)
end
