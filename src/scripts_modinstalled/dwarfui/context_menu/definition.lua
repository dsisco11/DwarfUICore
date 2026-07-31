--@ module=true

-- Validation and snapshot ownership for context-menu definitions.

local numbers = reqscript('dwarfui/utils/numbers')

local SYSTEM_FOREGROUND = 15
local SYSTEM_BACKGROUND = 0

---@class dwarfui.ContextMenuEntry
---@field label string
---@field on_select fun(context: dwarfui.ContextMenuSelectionContext)
---@field fg? integer
---@field bg? integer

---@class dwarfui.ContextMenuDefinition
---@field title? string
---@field fg? integer
---@field bg? integer
---@field entries dwarfui.ContextMenuEntry[]

---@class dwarfui.ContextMenuResolvedPen
---@field fg integer
---@field bg integer
ContextMenuResolvedPen = {}
ContextMenuResolvedPen.__index = ContextMenuResolvedPen

---@class dwarfui.ContextMenuResolvedEntry
---@field label string
---@field on_select fun(context: dwarfui.ContextMenuSelectionContext)
---@field fg integer
---@field bg integer
---@field pen dwarfui.ContextMenuResolvedPen
ContextMenuResolvedEntry = {}
ContextMenuResolvedEntry.__index = ContextMenuResolvedEntry

---@class dwarfui.ContextMenuDefinitionSnapshot
---@field title? string
---@field fg integer
---@field bg integer
---@field pen dwarfui.ContextMenuResolvedPen
---@field entries dwarfui.ContextMenuResolvedEntry[]
ContextMenuDefinitionSnapshot = {}
ContextMenuDefinitionSnapshot.__index = ContextMenuDefinitionSnapshot

---@class dwarfui.ContextMenuDefinitionSlot
---@field _definition dwarfui.ContextMenuDefinitionSnapshot
ContextMenuDefinitionSlot = {}
ContextMenuDefinitionSlot.__index = ContextMenuDefinitionSlot

local DEFINITION_FIELDS = {
    title=true,
    fg=true,
    bg=true,
    entries=true,
}
local ENTRY_FIELDS = {
    label=true,
    on_select=true,
    fg=true,
    bg=true,
}

---Rejects fields outside one explicitly supported object shape.
---@param value table
---@param fields table<string, boolean>
---@param label string
local function validate_fields(value, fields, label)
    for field in pairs(value) do
        assert(type(field) == 'string' and fields[field],
            ('DwarfUI %s contains unsupported field %s.'):format(
                label, tostring(field)))
    end
end

---Validates one optional context-menu display color.
---@param value any
---@param label string
---@return integer|nil
local function validate_color(value, label)
    if value == nil then return nil end
    assert(numbers.is_integer(value) and
            value >= SYSTEM_BACKGROUND and value <= SYSTEM_FOREGROUND,
        ('DwarfUI %s must be an integer display color from ' ..
            'COLOR_BLACK through COLOR_WHITE.'):format(label))
    return value
end

---Validates one required non-empty string.
---@param value any
---@param label string
---@return string
local function validate_nonempty_string(value, label)
    assert(type(value) == 'string' and #value > 0,
        ('DwarfUI %s must be a non-empty string.'):format(label))
    return value
end

---Returns the length of a strict, non-empty array.
---@param values any
---@param label string
---@return integer
local function validate_array(values, label)
    assert(type(values) == 'table',
        ('DwarfUI %s must be a non-empty array.'):format(label))
    local count, highest = 0, 0
    for index in pairs(values) do
        assert(numbers.is_integer(index) and index >= 1,
            ('DwarfUI %s contains unsupported field %s.'):format(
                label, tostring(index)))
        count = count + 1
        highest = math.max(highest, index)
    end
    assert(count > 0,
        ('DwarfUI %s must be a non-empty array.'):format(label))
    assert(count == highest,
        ('DwarfUI %s must not contain missing entries.'):format(label))
    return count
end

---Creates a resolved pen or copies an existing resolved-pen instance.
---@param foreground integer|dwarfui.ContextMenuResolvedPen
---@param background? integer
---@return dwarfui.ContextMenuResolvedPen
function ContextMenuResolvedPen.new(foreground, background)
    if getmetatable(foreground) == ContextMenuResolvedPen then
        assert(background == nil,
            'DwarfUI resolved-pen copies do not accept a background.')
        background = foreground.bg
        foreground = foreground.fg
    end
    assert(numbers.is_integer(foreground) and
            numbers.is_integer(background),
        'DwarfUI resolved pens require integer fg and bg colors.')
    return setmetatable({
        fg=foreground,
        bg=background,
    }, ContextMenuResolvedPen)
end

---Creates a resolved entry or copies an existing resolved-entry instance.
---@param entry dwarfui.ContextMenuResolvedEntry
---@return dwarfui.ContextMenuResolvedEntry
function ContextMenuResolvedEntry.new(entry)
    assert(type(entry) == 'table' and type(entry.label) == 'string' and
            type(entry.on_select) == 'function',
        'DwarfUI resolved entries require a label and on_select function.')
    return setmetatable({
        label=entry.label,
        on_select=entry.on_select,
        fg=entry.fg,
        bg=entry.bg,
        pen=ContextMenuResolvedPen.new(entry.pen),
    }, ContextMenuResolvedEntry)
end

---Creates a definition snapshot or copies an existing snapshot instance.
---@param definition dwarfui.ContextMenuDefinitionSnapshot
---@return dwarfui.ContextMenuDefinitionSnapshot
function ContextMenuDefinitionSnapshot.new(definition)
    assert(type(definition) == 'table' and
            type(definition.entries) == 'table',
        'DwarfUI context-menu snapshot must be a validated definition.')
    local entries = {}
    for index, entry in ipairs(definition.entries) do
        entries[index] = ContextMenuResolvedEntry.new(entry)
    end
    return setmetatable({
        title=definition.title,
        fg=definition.fg,
        bg=definition.bg,
        pen=ContextMenuResolvedPen.new(definition.pen),
        entries=entries,
    }, ContextMenuDefinitionSnapshot)
end

---Validates and copies one caller-owned context-menu definition.
---@param definition dwarfui.ContextMenuDefinition
---@return dwarfui.ContextMenuDefinitionSnapshot
function validate(definition)
    assert(type(definition) == 'table',
        'DwarfUI context-menu definition must be a table.')
    validate_fields(definition, DEFINITION_FIELDS, 'context-menu definition')

    local title
    if definition.title ~= nil then
        title = validate_nonempty_string(
            definition.title, 'context-menu definition title')
    end
    local foreground = validate_color(
        definition.fg, 'context-menu definition fg') or SYSTEM_FOREGROUND
    local background = validate_color(
        definition.bg, 'context-menu definition bg') or SYSTEM_BACKGROUND
    local entry_count = validate_array(
        definition.entries, 'context-menu definition entries')
    local entries = {}

    for index = 1, entry_count do
        local entry = definition.entries[index]
        local entry_label = ('context-menu entry %d'):format(index)
        assert(type(entry) == 'table',
            ('DwarfUI %s must be a table.'):format(entry_label))
        validate_fields(entry, ENTRY_FIELDS, entry_label)
        local label = validate_nonempty_string(
            entry.label, entry_label .. ' label')
        assert(type(entry.on_select) == 'function',
            ('DwarfUI %s on_select must be a Lua function.'):format(
                entry_label))
        local entry_foreground =
            validate_color(entry.fg, entry_label .. ' fg') or foreground
        local entry_background =
            validate_color(entry.bg, entry_label .. ' bg') or background
        entries[index] = ContextMenuResolvedEntry.new{
            label=label,
            on_select=entry.on_select,
            fg=entry_foreground,
            bg=entry_background,
            pen=ContextMenuResolvedPen.new(
                entry_foreground, entry_background),
        }
    end

    return ContextMenuDefinitionSnapshot.new{
        title=title,
        fg=foreground,
        bg=background,
        pen=ContextMenuResolvedPen.new(foreground, background),
        entries=entries,
    }
end

---Creates registration-owned validated definition storage.
---@param definition dwarfui.ContextMenuDefinition
---@return dwarfui.ContextMenuDefinitionSlot
function ContextMenuDefinitionSlot.new(definition)
    return setmetatable({
        _definition=validate(definition),
    }, ContextMenuDefinitionSlot)
end

---Atomically replaces the stored definition after complete validation.
---@param definition dwarfui.ContextMenuDefinition
function ContextMenuDefinitionSlot:replace(definition)
    local replacement = validate(definition)
    self._definition = replacement
end

---Creates an isolated definition snapshot for one opening.
---@return dwarfui.ContextMenuDefinitionSnapshot
function ContextMenuDefinitionSlot:snapshot()
    return ContextMenuDefinitionSnapshot.new(self._definition)
end

---Returns the system foreground display color.
---@return integer
function get_system_foreground()
    return SYSTEM_FOREGROUND
end

---Returns the system background display color.
---@return integer
function get_system_background()
    return SYSTEM_BACKGROUND
end
