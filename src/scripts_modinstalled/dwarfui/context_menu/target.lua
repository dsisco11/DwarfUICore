--@ module=true

-- Stable target identity, copied anchors, and weak open-session ownership.

local definitions = reqscript('dwarfui/context_menu/definition')
local immutable_enum = reqscript('dwarfui/utils/immutable_enum')
local numbers = reqscript('dwarfui/utils/numbers')

---@enum dwarfui.ContextMenuTargetKind
ContextMenuTargetKind = immutable_enum.define({
    WIDGET=1,
    MAP_TILE=2,
}, 'ContextMenuTargetKind')

---@enum dwarfui.ContextMenuAnchorKind
ContextMenuAnchorKind = immutable_enum.define({
    SCREEN_POSITION=1,
    MAP_TILE=2,
}, 'ContextMenuAnchorKind')

---@enum dwarfui.ContextMenuSessionState
ContextMenuSessionState = immutable_enum.define({
    OPEN=1,
    CLOSED=2,
}, 'ContextMenuSessionState')

---@class dwarfui.ContextMenuRegistrationIdentityAllocator
---@field _next integer
ContextMenuRegistrationIdentityAllocator = {}
ContextMenuRegistrationIdentityAllocator.__index =
    ContextMenuRegistrationIdentityAllocator

---@class dwarfui.ContextMenuTargetDescriptor
---@field kind dwarfui.ContextMenuTargetKind
---@field registration_identity integer
ContextMenuTargetDescriptor = {}
ContextMenuTargetDescriptor.__index = ContextMenuTargetDescriptor

---@class dwarfui.ContextMenuAnchorDescriptor
---@field kind dwarfui.ContextMenuAnchorKind
---@field screen_position {x: integer, y: integer}
---@field map_position? {x: integer, y: integer, z: integer}
ContextMenuAnchorDescriptor = {}
ContextMenuAnchorDescriptor.__index = ContextMenuAnchorDescriptor

---@class dwarfui.ContextMenuSelectionContext
---@field target_kind dwarfui.ContextMenuTargetKind
---@field anchor_kind dwarfui.ContextMenuAnchorKind
---@field registration_identity integer
---@field screen_position {x: integer, y: integer}
---@field map_position? {x: integer, y: integer, z: integer}
---@field source any
---@field source_root any
---@field owner? any

---@class dwarfui.ContextMenuOpenSessionOptions
---@field definition dwarfui.ContextMenuDefinitionSnapshot
---@field target dwarfui.ContextMenuTargetDescriptor
---@field anchor dwarfui.ContextMenuAnchorDescriptor
---@field source any
---@field source_root any
---@field owner? any

---@class dwarfui.ContextMenuOpenSession
---@field _definition dwarfui.ContextMenuDefinitionSnapshot
---@field _target dwarfui.ContextMenuTargetDescriptor
---@field _anchor dwarfui.ContextMenuAnchorDescriptor
---@field _state dwarfui.ContextMenuSessionState
---@field _weak_sources table
---@field _requires_owner boolean
ContextMenuOpenSession = {}
ContextMenuOpenSession.__index = ContextMenuOpenSession

---Validates one screen-space coordinate pair.
---@param x any
---@param y any
---@param label string
local function validate_screen_position(x, y, label)
    assert(numbers.is_integer(x) and numbers.is_integer(y),
        ('DwarfUI %s requires integer x and y.'):format(label))
end

---Validates one exact map coordinate.
---@param position any
---@param label string
local function validate_map_position(position, label)
    local position_type = type(position)
    assert(position_type == 'table' or position_type == 'userdata',
        ('DwarfUI %s requires an exact map position.'):format(label))
    assert(numbers.is_integer(position.x) and
            numbers.is_integer(position.y) and
            numbers.is_integer(position.z),
        ('DwarfUI %s requires integer x, y, and z.'):format(label))
end

---Creates a fresh monotonically increasing identity allocator.
---@return dwarfui.ContextMenuRegistrationIdentityAllocator
function ContextMenuRegistrationIdentityAllocator.new()
    return setmetatable({_next=0},
        ContextMenuRegistrationIdentityAllocator)
end

---Allocates one new positive registration identity.
---@return integer
function ContextMenuRegistrationIdentityAllocator:allocate()
    self._next = self._next + 1
    return self._next
end

---Creates a target descriptor or copies an existing descriptor instance.
---@param kind dwarfui.ContextMenuTargetKind|dwarfui.ContextMenuTargetDescriptor
---@param registration_identity? integer
---@return dwarfui.ContextMenuTargetDescriptor
function ContextMenuTargetDescriptor.new(kind, registration_identity)
    if getmetatable(kind) == ContextMenuTargetDescriptor then
        assert(registration_identity == nil,
            'DwarfUI target-descriptor copies do not accept an identity.')
        registration_identity = kind.registration_identity
        kind = kind.kind
    end
    assert(kind == ContextMenuTargetKind.WIDGET or
            kind == ContextMenuTargetKind.MAP_TILE,
        'DwarfUI context-menu target kind must be a ContextMenuTargetKind.')
    assert(numbers.is_integer(registration_identity) and
            registration_identity > 0,
        'DwarfUI context-menu registration identity must be a positive integer.')
    return setmetatable({
        kind=kind,
        registration_identity=registration_identity,
    }, ContextMenuTargetDescriptor)
end

---Creates an anchor descriptor or copies an existing descriptor instance.
---@param kind dwarfui.ContextMenuAnchorKind|dwarfui.ContextMenuAnchorDescriptor
---@param options? {screen_position: {x: integer, y: integer}, map_position?: {x: integer, y: integer, z: integer}}
---@return dwarfui.ContextMenuAnchorDescriptor
function ContextMenuAnchorDescriptor.new(kind, options)
    if getmetatable(kind) == ContextMenuAnchorDescriptor then
        assert(options == nil,
            'DwarfUI anchor-descriptor copies do not accept options.')
        options = kind
        kind = kind.kind
    end
    assert(kind == ContextMenuAnchorKind.SCREEN_POSITION or
            kind == ContextMenuAnchorKind.MAP_TILE,
        'DwarfUI context-menu anchor kind must be a ContextMenuAnchorKind.')
    assert(type(options) == 'table' and
            type(options.screen_position) == 'table',
        'DwarfUI context-menu anchor requires a screen position.')
    local screen_position = options.screen_position
    validate_screen_position(
        screen_position.x, screen_position.y, 'context-menu anchor')
    local descriptor = {
        kind=kind,
        screen_position={x=screen_position.x, y=screen_position.y},
    }
    if kind == ContextMenuAnchorKind.MAP_TILE then
        validate_map_position(options.map_position, 'map-tile anchor')
        descriptor.map_position = {
            x=options.map_position.x,
            y=options.map_position.y,
            z=options.map_position.z,
        }
    else
        assert(options.map_position == nil,
            'DwarfUI screen-position anchors cannot contain a map position.')
    end
    return setmetatable(descriptor, ContextMenuAnchorDescriptor)
end

---Creates a fixed screen-position anchor.
---@param x integer
---@param y integer
---@return dwarfui.ContextMenuAnchorDescriptor
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
---@return dwarfui.ContextMenuAnchorDescriptor
function ContextMenuAnchorDescriptor.map_tile(position, screen_x, screen_y)
    return ContextMenuAnchorDescriptor.new(
        ContextMenuAnchorKind.MAP_TILE, {
        screen_position={x=screen_x, y=screen_y},
        map_position={x=position.x, y=position.y, z=position.z},
    })
end

---Creates one open session with copied stable state and weak live sources.
---@param options dwarfui.ContextMenuOpenSessionOptions
---@return dwarfui.ContextMenuOpenSession
function ContextMenuOpenSession.new(options)
    assert(type(options) == 'table',
        'DwarfUI context-menu open session requires options.')
    assert(options.source ~= nil,
        'DwarfUI context-menu open session requires a source.')
    assert(options.source_root ~= nil,
        'DwarfUI context-menu open session requires a source root.')
    return setmetatable({
        _definition=definitions.ContextMenuDefinitionSnapshot.new(
            options.definition),
        _target=ContextMenuTargetDescriptor.new(options.target),
        _anchor=ContextMenuAnchorDescriptor.new(options.anchor),
        _state=ContextMenuSessionState.OPEN,
        _weak_sources=setmetatable({
            source=options.source,
            source_root=options.source_root,
            owner=options.owner,
        }, {__mode='v'}),
        _requires_owner=options.owner ~= nil,
    }, ContextMenuOpenSession)
end

---Returns the current lifecycle state.
---@return dwarfui.ContextMenuSessionState
function ContextMenuOpenSession:get_state()
    return self._state
end

---Returns an isolated copy of the session's definition snapshot.
---@return dwarfui.ContextMenuDefinitionSnapshot
function ContextMenuOpenSession:get_definition_snapshot()
    return definitions.ContextMenuDefinitionSnapshot.new(self._definition)
end

---Returns an isolated copy of the stable target descriptor.
---@return dwarfui.ContextMenuTargetDescriptor
function ContextMenuOpenSession:get_target_descriptor()
    return ContextMenuTargetDescriptor.new(self._target)
end

---Returns an isolated copy of the anchor descriptor.
---@return dwarfui.ContextMenuAnchorDescriptor
function ContextMenuOpenSession:get_anchor_descriptor()
    return ContextMenuAnchorDescriptor.new(self._anchor)
end

---Returns whether the session remains open and all required sources are live.
---@return boolean
function ContextMenuOpenSession:is_valid()
    if self._state ~= ContextMenuSessionState.OPEN then return false end
    local sources = self._weak_sources
    if sources.source == nil or sources.source_root == nil or
            (self._requires_owner and sources.owner == nil) then
        self:close()
        return false
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
---@return dwarfui.ContextMenuSelectionContext|nil
function ContextMenuOpenSession:create_selection_context()
    if not self:is_valid() then return nil end
    local anchor = self._anchor
    local sources = self._weak_sources
    local context = {
        target_kind=self._target.kind,
        anchor_kind=anchor.kind,
        registration_identity=self._target.registration_identity,
        screen_position={
            x=anchor.screen_position.x,
            y=anchor.screen_position.y,
        },
        source=sources.source,
        source_root=sources.source_root,
        owner=sources.owner,
    }
    if anchor.map_position then
        context.map_position = {
            x=anchor.map_position.x,
            y=anchor.map_position.y,
            z=anchor.map_position.z,
        }
    end
    return context
end

---Closes and invokes one selected entry exactly once when its source is live.
---@param entry_index integer
---@return boolean invoked
function ContextMenuOpenSession:select(entry_index)
    assert(numbers.is_integer(entry_index) and
            self._definition.entries[entry_index] ~= nil,
        'DwarfUI context-menu selection requires a valid entry index.')
    local context = self:create_selection_context()
    if not context then return false end
    local handler = self._definition.entries[entry_index].on_select
    self:close()
    handler(context)
    return true
end
