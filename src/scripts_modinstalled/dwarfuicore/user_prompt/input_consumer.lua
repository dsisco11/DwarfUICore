--@ module=true

-- Prompt-owned input classification and exact terminal dispatch.

local input_types = reqscript('dwarfuicore/input_event/types')

local InputDispatchResult = input_types.InputDispatchResult

---@class dwarfuicore.UserPromptInputConsumerOptions
---@field is_active fun(): boolean
---@field complete fun(position: table|nil): boolean
---@field cancel fun(cause: dwarfuicore.UserPromptTerminalCause): boolean
---@field on_failure fun(message: string)
---@field causes table

---@class dwarfuicore.UserPromptInputConsumer
---@field private _is_active fun(): boolean
---@field private _complete fun(position: table|nil): boolean
---@field private _cancel fun(cause: dwarfuicore.UserPromptTerminalCause): boolean
---@field private _on_failure fun(message: string)
---@field private _causes table
UserPromptInputConsumer = {}
UserPromptInputConsumer.__index = UserPromptInputConsumer

---Creates the one prompt-first consumer installed in the shared dispatcher.
---@param options dwarfuicore.UserPromptInputConsumerOptions
---@return dwarfuicore.UserPromptInputConsumer consumer
function UserPromptInputConsumer.new(options)
    assert(type(options) == 'table',
        'DwarfUICore UserPrompt input consumer requires options.')
    for _, name in ipairs{
            'is_active', 'complete', 'cancel',
            'on_failure',
        } do
        assert(type(options[name]) == 'function',
            'DwarfUICore UserPrompt input consumer requires ' .. name .. '().')
    end
    assert(type(options.causes) == 'table' and
            options.causes.RIGHT_RELEASE ~= nil and
            options.causes.ESCAPE ~= nil and
            options.causes.INTERNAL_FAILURE ~= nil,
        'DwarfUICore UserPrompt input consumer requires terminal causes.')
    return setmetatable({
        _is_active=options.is_active,
        _complete=options.complete,
        _cancel=options.cancel,
        _on_failure=options.on_failure,
        _causes=options.causes,
    }, UserPromptInputConsumer)
end

---Returns whether the active prompt owns at least one boundary in this table.
---@param keys table
---@return boolean owned
function UserPromptInputConsumer:owns(keys)
    return self._is_active() and type(keys) == 'table' and
        (not not (keys.LEAVESCREEN or keys._MOUSE_R or keys._MOUSE_L or
            keys._MOUSE_L_DOWN or keys._MOUSE_R_DOWN))
end

---Consumes one owned table using cancellation-before-completion precedence.
---@param keys table
---@param snapshot dwarfuicore.InputSnapshot
---@return dwarfuicore.InputDispatchResult result
function UserPromptInputConsumer:consume(keys, snapshot)
    if keys.LEAVESCREEN then
        self._cancel(self._causes.ESCAPE)
        return InputDispatchResult.CONSUME
    end
    if keys._MOUSE_R then
        self._cancel(self._causes.RIGHT_RELEASE)
        return InputDispatchResult.CONSUME
    end
    if keys._MOUSE_L then
        self._complete(snapshot.map_position)
        return InputDispatchResult.CONSUME
    end
    if keys._MOUSE_L_DOWN or keys._MOUSE_R_DOWN then
        return InputDispatchResult.CONSUME
    end
    return InputDispatchResult.PASS
end

---Cancels a prompt after protected dispatcher failure consumed its event.
---@param message string
function UserPromptInputConsumer:on_failure(message)
    self._on_failure(message)
end

---Builds the plain callback table accepted by the shared input owner.
---@return dwarfuicore.PriorityInputConsumer callbacks
function UserPromptInputConsumer:callbacks()
    return {
        consume=function(keys, snapshot) return self:consume(keys, snapshot) end,
        on_failure=function(message) self:on_failure(message) end,
    }
end

