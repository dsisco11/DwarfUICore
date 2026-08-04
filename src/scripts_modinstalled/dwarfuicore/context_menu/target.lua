--@ module=true

-- Stable target identity, copied anchors, and weak open-session ownership.

local definitions = reqscript('dwarfuicore/context_menu/definition')
local identities = reqscript('dwarfuicore/service_provider/identity')
local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')
local numbers = reqscript('dwarfuicore/utils/numbers')

---@enum dwarfuicore.ContextMenuTargetKind
ContextMenuTargetKind = immutable_enum.define({
    WIDGET=1,
    MAP_TILE=2,
}, 'ContextMenuTargetKind')

---@enum dwarfuicore.ContextMenuAnchorKind
ContextMenuAnchorKind = immutable_enum.define({
    SCREEN_POSITION=1,
    MAP_TILE=2,
}, 'ContextMenuAnchorKind')

---@enum dwarfuicore.ContextMenuSessionState
ContextMenuSessionState = immutable_enum.define({
    OPEN=1,
    CLOSED=2,
}, 'ContextMenuSessionState')

---@class dwarfuicore.ContextMenuTargetDescriptor
---@field kind dwarfuicore.ContextMenuTargetKind
---@field registration_identity table
ContextMenuTargetDescriptor = {}
ContextMenuTargetDescriptor.__index = ContextMenuTargetDescriptor

---@class dwarfuicore.ContextMenuAnchorDescriptor
---@field kind dwarfuicore.ContextMenuAnchorKind
---@field screen_position {x: integer, y: integer}
---@field map_position? {x: integer, y: integer, z: integer}
ContextMenuAnchorDescriptor = {}
ContextMenuAnchorDescriptor.__index = ContextMenuAnchorDescriptor

---@class dwarfuicore.ContextMenuOpenSessionOptions
---@field definition dwarfuicore.ContextMenuDefinitionSnapshot
---@field target dwarfuicore.ContextMenuTargetDescriptor
---@field anchor dwarfuicore.ContextMenuAnchorDescriptor
---@field source any
---@field source_root any
---@field owner? any
---@field contributions? table[]

---@class dwarfuicore.ContextMenuOpenSession
---@field _definition dwarfuicore.ContextMenuDefinitionSnapshot
---@field _target dwarfuicore.ContextMenuTargetDescriptor
---@field _anchor dwarfuicore.ContextMenuAnchorDescriptor
---@field _state dwarfuicore.ContextMenuSessionState
---@field _weak_sources table
---@field _contributions table[]
---@field _invalid_reason string|nil
---@field _requires_owner boolean
ContextMenuOpenSession = {}
ContextMenuOpenSession.__index = ContextMenuOpenSession

---Validates one screen-space coordinate pair.
---@param x any
---@param y any
---@param label string
---Creates a target descriptor or copies an existing descriptor instance.
---@param kind dwarfuicore.ContextMenuTargetKind|dwarfuicore.ContextMenuTargetDescriptor
---@param registration_identity? table
---@return dwarfuicore.ContextMenuTargetDescriptor
function ContextMenuTargetDescriptor.new(kind, registration_identity)
    if getmetatable(kind) == ContextMenuTargetDescriptor then
        assert(registration_identity == nil,
            'DwarfUICore target-descriptor copies do not accept an identity.')
        registration_identity = kind.registration_identity
        kind = kind.kind
    end
    assert(kind == ContextMenuTargetKind.WIDGET or
            kind == ContextMenuTargetKind.MAP_TILE,
        'DwarfUICore context-menu target kind must be a ContextMenuTargetKind.')
    registration_identity = identities.CompositeIdentity.new(
        registration_identity)
    return setmetatable({
        kind=kind,
        registration_identity=registration_identity,
    }, ContextMenuTargetDescriptor)
end

---Creates an anchor descriptor or copies an existing descriptor instance.
---@param kind dwarfuicore.ContextMenuAnchorKind|dwarfuicore.ContextMenuAnchorDescriptor
---@param options? {screen_position: {x: integer, y: integer}, map_position?: {x: integer, y: integer, z: integer}}
---@return dwarfuicore.ContextMenuAnchorDescriptor
function ContextMenuAnchorDescriptor.new(kind, options)
    if getmetatable(kind) == ContextMenuAnchorDescriptor then
        assert(options == nil,
            'DwarfUICore anchor-descriptor copies do not accept options.')
        options = kind
        kind = kind.kind
    end
    assert(kind == ContextMenuAnchorKind.SCREEN_POSITION or
            kind == ContextMenuAnchorKind.MAP_TILE,
        'DwarfUICore context-menu anchor kind must be a ContextMenuAnchorKind.')
    assert(type(options) == 'table' and
            type(options.screen_position) == 'table',
        'DwarfUICore context-menu anchor requires a screen position.')
    local screen_position = identities.ScreenPosition.new(
        options.screen_position)
    local descriptor = {
        kind=kind,
        screen_position=screen_position,
    }
    if kind == ContextMenuAnchorKind.MAP_TILE then
        descriptor.map_position = identities.MapTilePosition.new(
            options.map_position)
    else
        assert(options.map_position == nil,
            'DwarfUICore screen-position anchors cannot contain a map position.')
    end
    return setmetatable(descriptor, ContextMenuAnchorDescriptor)
end

---Creates a fixed screen-position anchor.
---@param x integer
---@param y integer
---@return dwarfuicore.ContextMenuAnchorDescriptor
function ContextMenuAnchorDescriptor.screen_position(x, y)
    return ContextMenuAnchorDescriptor.new(
        ContextMenuAnchorKind.SCREEN_POSITION, {
        screen_position={x=x, y=y},
    })
end

---Creates a copied map-tile anchor with its captured opening position.
---@param position {x: integer, y: integer, z: integer}
---@param screen_x integer
---@param screen_y integer
---@return dwarfuicore.ContextMenuAnchorDescriptor
function ContextMenuAnchorDescriptor.map_tile(position, screen_x, screen_y)
    return ContextMenuAnchorDescriptor.new(
        ContextMenuAnchorKind.MAP_TILE, {
        screen_position={x=screen_x, y=screen_y},
        map_position=identities.MapTilePosition.new(position),
    })
end

---Creates one open session with copied stable state and weak live sources.
---@param options dwarfuicore.ContextMenuOpenSessionOptions
---@return dwarfuicore.ContextMenuOpenSession
function ContextMenuOpenSession.new(options)
    assert(type(options) == 'table',
        'DwarfUICore context-menu open session requires options.')
    assert(options.source ~= nil,
        'DwarfUICore context-menu open session requires a source.')
    assert(options.source_root ~= nil,
        'DwarfUICore context-menu open session requires a source root.')
    local supplied = options.contributions or {{
        identity=options.target.registration_identity,
        definition=options.definition,
        source=options.source,
        owner=options.owner,
    }}
    assert(type(supplied) == 'table' and #supplied > 0,
        'DwarfUICore context-menu session requires contributions.')
    local entries = {}
    local contributions = {}
    local first_definition
    local weak_sources = {
        source_root=setmetatable({value=options.source_root}, {__mode='v'}),
    }
    for contribution_index, contribution in ipairs(supplied) do
        assert(type(contribution) == 'table' and contribution.source ~= nil and
                contribution.definition ~= nil,
            'DwarfUICore context-menu session contribution is invalid.')
        local definition = definitions.ContextMenuDefinitionSnapshot.new(
            contribution.definition)
        first_definition = first_definition or definition
        weak_sources[contribution_index] = setmetatable({
            source=contribution.source, owner=contribution.owner,
        }, {__mode='v'})
        contributions[contribution_index] = {
            identity=identities.CompositeIdentity.new(contribution.identity),
            definition=definition,
            requires_owner=contribution.owner ~= nil,
            entry_first=#entries + 1,
            entry_last=#entries + #definition.entries,
        }
        for _, entry in ipairs(definition.entries) do
            table.insert(entries, definitions.ContextMenuResolvedEntry.new(entry))
        end
    end
    local combined = definitions.ContextMenuDefinitionSnapshot.new{
        title=first_definition.title,
        fg=first_definition.fg,
        bg=first_definition.bg,
        pen=first_definition.pen,
        entries=entries,
    }
    return setmetatable({
        _definition=combined,
        _target=ContextMenuTargetDescriptor.new(options.target),
        _anchor=ContextMenuAnchorDescriptor.new(options.anchor),
        _state=ContextMenuSessionState.OPEN,
        _weak_sources=weak_sources,
        _contributions=contributions,
        _invalid_reason=nil,
    }, ContextMenuOpenSession)
end

---Returns the current lifecycle state.
---@return dwarfuicore.ContextMenuSessionState
function ContextMenuOpenSession:get_state()
    return self._state
end

---Returns an isolated copy of the session's definition snapshot.
---@return dwarfuicore.ContextMenuDefinitionSnapshot
function ContextMenuOpenSession:get_definition_snapshot()
    return definitions.ContextMenuDefinitionSnapshot.new(self._definition)
end

---Returns an isolated copy of the stable target descriptor.
---@return dwarfuicore.ContextMenuTargetDescriptor
function ContextMenuOpenSession:get_target_descriptor()
    return ContextMenuTargetDescriptor.new(self._target)
end

---Returns an isolated copy of the anchor descriptor.
---@return dwarfuicore.ContextMenuAnchorDescriptor
function ContextMenuOpenSession:get_anchor_descriptor()
    return ContextMenuAnchorDescriptor.new(self._anchor)
end

---Returns the still-live source root without extending its lifetime.
---@return any|nil
function ContextMenuOpenSession:get_source_root()
    return self._weak_sources.source_root.value
end

---Returns copied identities for every contribution captured by this session.
---@return table[] identities
function ContextMenuOpenSession:get_contribution_identities()
    local values = {}
    for index, contribution in ipairs(self._contributions) do
        values[index] = identities.CompositeIdentity.new(contribution.identity)
    end
    return values
end

---Returns whether this session contains one exact composite contribution.
---@param identity table
---@return boolean contains
function ContextMenuOpenSession:contains_identity(identity)
    for _, contribution in ipairs(self._contributions) do
        local current = contribution.identity
        if current.runtime_generation == identity.runtime_generation and
                current.service_kind == identity.service_kind and
                current.contract_major == identity.contract_major and
                current.namespace == identity.namespace and
                current.local_identity == identity.local_identity then
            return true
        end
    end
    return false
end

---Returns whether the session remains open and all required sources are live.
---@return boolean
function ContextMenuOpenSession:is_valid()
    if self._state ~= ContextMenuSessionState.OPEN then return false end
    local sources = self._weak_sources
    if sources.source_root.value == nil then
        self._invalid_reason = 'source root was collected'
        self:close()
        return false
    end
    for index, contribution in ipairs(self._contributions) do
        local live = sources[index]
        if live == nil or live.source == nil or
                (contribution.requires_owner and live.owner == nil) then
            self._invalid_reason = 'contribution source was collected'
            self:close()
            return false
        end
    end
    return true
end

---Closes the session exactly once.
---@return boolean closed
function ContextMenuOpenSession:close()
    if self._state == ContextMenuSessionState.CLOSED then return false end
    self._state = ContextMenuSessionState.CLOSED
    return true
end

---Builds a callback context only while every required weak source is live.
---@return dwarfuicore.ContextMenuSelectionContext|nil
function ContextMenuOpenSession:create_selection_context(entry_index)
    if not self:is_valid() then return nil end
    entry_index = entry_index or 1
    local contribution
    for index, candidate in ipairs(self._contributions) do
        if entry_index >= candidate.entry_first and
                entry_index <= candidate.entry_last then
            contribution = candidate
            local sources = self._weak_sources[index]
            local anchor = self._anchor
            local context_values = {
                screen_position=anchor.screen_position,
                source=sources.source,
                source_root=self._weak_sources.source_root.value,
                owner=sources.owner,
            }
            if anchor.map_position then
                context_values.map_position = anchor.map_position
            end
            return identities.ContextMenuSelectionContext.new(context_values)
        end
    end
    return nil
end

---Returns the private reason from the latest weak-lifetime invalidation.
---@return string|nil reason
function ContextMenuOpenSession:get_invalid_reason()
    return self._invalid_reason
end

---Closes and invokes one selected entry exactly once when its source is live.
---@param entry_index integer
---@return boolean invoked
function ContextMenuOpenSession:select(entry_index)
    assert(numbers.is_integer(entry_index) and
            self._definition.entries[entry_index] ~= nil,
        'DwarfUICore context-menu selection requires a valid entry index.')
    local context = self:create_selection_context(entry_index)
    if not context then return false end
    local handler = self._definition.entries[entry_index].on_select
    self:close()
    handler(context)
    return true
end
