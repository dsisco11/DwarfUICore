--@ module=true

local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')

---@enum dwarfuicore.PointerPolicy
PointerPolicy = immutable_enum.define({
    TARGET=1,
    PASS=2,
    BLOCK=3,
    NONE=4,
}, 'PointerPolicy')

---@enum dwarfuicore.PointerClassificationKind
PointerClassificationKind = immutable_enum.define({
    TARGET=1,
    BLOCKED=2,
    MISS=3,
    UNKNOWN=4,
}, 'PointerClassificationKind')

---Returns one immutable copy of a diagnostic record.
---@param kind string
---@param message string|nil
---@return table
local function new_diagnostic(kind, message)
    return setmetatable({
        kind = kind,
        message = message,
    }, {
        __newindex=function()
            error('DwarfUICore pointer diagnostics are immutable.', 2)
        end,
        __metatable=false,
    })
end

---Returns a read-only pointer-classification payload.
---@param values table
---@return dwarfuicore.PointerClassification result
local function immutable_result(values)
    return setmetatable(values, {
        __newindex=function()
            error('DwarfUICore pointer classifications are immutable.', 2)
        end,
        __pairs=function()
            return next, values, nil
        end,
        __metatable=false,
    })
end

---Creates one pointer classification payload and validates required fields.
---@param kind dwarfuicore.PointerClassificationKind
---@param subject any
---@param local_position dwarfuicore.Position2D|nil
---@return dwarfuicore.PointerClassification result
local function classification(kind, subject, local_position)
    assert(kind == PointerClassificationKind.TARGET or
            kind == PointerClassificationKind.BLOCKED or
            kind == PointerClassificationKind.MISS or
            kind == PointerClassificationKind.UNKNOWN,
        'DwarfUICore pointer classification kind is invalid.')
    if kind == PointerClassificationKind.TARGET then
        assert(subject ~= nil,
            'DwarfUICore pointer target classifications require a subject.')
        assert(local_position ~= nil and
                local_position.x ~= nil and local_position.y ~= nil and
                math.type(local_position.x) == 'integer' and
                math.type(local_position.y) == 'integer',
            'DwarfUICore pointer target classifications require local_position.')
        return immutable_result({
            kind=kind,
            subject=subject,
            local_position=local_position,
        })
    end
    if kind == PointerClassificationKind.BLOCKED then
        assert(subject ~= nil,
            'DwarfUICore pointer-blocked classifications require a subject.')
        assert(local_position == nil,
            'DwarfUICore pointer-blocked classifications forbid local_position.')
        return immutable_result({
            kind=kind,
            subject=subject,
            local_position=nil,
        })
    end
    assert(subject == nil,
        'DwarfUICore miss and unknown classifications require no subject.')
    assert(local_position == nil,
        'DwarfUICore miss and unknown classifications require no local_position.')
    return immutable_result({
        kind=kind,
        subject=nil,
        local_position=nil,
    })
end

---Returns true when a value is an integer number.
---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == 'number' and math.type(value) == 'integer'
end

---@class dwarfuicore.PointerObstructionClassifier
PointerObstructionClassifier = {}
PointerObstructionClassifier.__index = PointerObstructionClassifier

---Copies an immutable diagnostic object to this classifier instance.
---@param self dwarfuicore.PointerObstructionClassifier
---@param message table|nil
local function set_diagnostic(self, message)
    self._diagnostic = message
end

---Normalizes and validates one classifier result as canonical classification output.
---@param result any
---@return dwarfuicore.PointerClassification|nil result
---@return string|nil reason
local function normalize_result(result)
    if type(result) ~= 'table' then
        return nil, 'classifier returned non-table result'
    end
    local ok, normalized = pcall(classification, result.kind,
        result.subject, result.local_position)
    if not ok then
        return nil, tostring(normalized)
    end
    return normalized, nil
end

---Returns a non-throwing, validated classifier invocation.
---@param self dwarfuicore.PointerObstructionClassifier
---@param root table|userdata
---@param screen_position dwarfuicore.Position2D
---@return dwarfuicore.PointerClassification
function PointerObstructionClassifier.invoke(self, root, screen_position)
    if type(self) ~= 'table' then
        return classification(PointerClassificationKind.UNKNOWN)
    end

    if type(root) ~= 'table' and type(root) ~= 'userdata' then
        set_diagnostic(self, new_diagnostic('validation', 'invalid root'))
        return classification(PointerClassificationKind.UNKNOWN)
    end

    if type(screen_position) ~= 'table' or
            not is_integer(screen_position.x) or
            not is_integer(screen_position.y) then
        set_diagnostic(self, new_diagnostic(
            'validation', 'invalid screen_position'))
        return classification(PointerClassificationKind.UNKNOWN)
    end

    if type(self._classify) ~= 'function' then
        set_diagnostic(self, new_diagnostic(
            'validation', 'classifier implementation is missing _classify'))
        return classification(PointerClassificationKind.UNKNOWN)
    end

    set_diagnostic(self, nil)
    local ok, result = pcall(self._classify, self, root, screen_position)
    if not ok then
        set_diagnostic(self, new_diagnostic('invocation', tostring(result)))
        return classification(PointerClassificationKind.UNKNOWN)
    end

    local normalized, reason = normalize_result(result)
    if not normalized then
        set_diagnostic(self, new_diagnostic('malformed', reason))
        return classification(PointerClassificationKind.UNKNOWN)
    end

    set_diagnostic(self, nil)
    return normalized
end

---Returns the latest immutable diagnostic for this classifier.
---@param self dwarfuicore.PointerObstructionClassifier
---@return table|nil
function PointerObstructionClassifier.get_diagnostic(self)
    return type(self) == 'table' and self._diagnostic or nil
end

return {
    PointerPolicy=PointerPolicy,
    PointerClassificationKind=PointerClassificationKind,
    PointerObstructionClassifier=PointerObstructionClassifier,
    classification=classification,
    immutable_result=immutable_result,
    is_integer=is_integer,
}
