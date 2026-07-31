--@ module=true

-- Short-lived interactive ZScreen presentation for one open menu session.

local gui = require('gui')
local map_projection = reqscript('dwarfui/map_projection')
local renderers = reqscript('dwarfui/context_menu/renderer')
local services = reqscript('dwarfui/context_menu/service')
local targets = reqscript('dwarfui/context_menu/target')

local AnchorKind = targets.ContextMenuAnchorKind

local WHEEL_KEYS = {
    STANDARDSCROLL_UP=true,
    STANDARDSCROLL_DOWN=true,
    STANDARDSCROLL_PAGEUP=true,
    STANDARDSCROLL_PAGEDOWN=true,
    CONTEXT_SCROLL_UP=true,
    CONTEXT_SCROLL_DOWN=true,
    CONTEXT_SCROLL_PAGEUP=true,
    CONTEXT_SCROLL_PAGEDOWN=true,
}

---@class dwarfui.ContextMenuScreen: gui.ZScreen
---@field super gui.ZScreen
---@field session dwarfui.ContextMenuOpenSession
---@field actions dwarfui.ContextMenuPresentationActions
---@field menu_window dwarfui.ContextMenuWindow
---@field anchor dwarfui.ContextMenuAnchorDescriptor
---@field _presentation_closed boolean
ContextMenuScreen = defclass(ContextMenuScreen, gui.ZScreen)
ContextMenuScreen.ATTRS{
    focus_path='dwarfui/context-menu',
    initial_pause=false,
    force_pause=false,
    pass_pause=false,
    pass_movement_keys=false,
    pass_mouse_clicks=false,
    defocusable=false,
}

---Returns whether an event table contains wheel input.
---@param keys table
---@return boolean
local function has_wheel_input(keys)
    for key in pairs(WHEEL_KEYS) do
        if keys[key] then return true end
    end
    return false
end

---Constructs one menu screen without showing it.
---@param info {session: dwarfui.ContextMenuOpenSession, actions: dwarfui.ContextMenuPresentationActions}
function ContextMenuScreen:init(info)
    self.session = info.session
    self.actions = info.actions
    self._presentation_closed = false
    local definition = self.session:get_definition_snapshot()
    self.anchor = self.session:get_anchor_descriptor()
    self.menu_window = renderers.ContextMenuWindow{
        definition=definition,
        anchor=self.anchor.screen_position,
        on_select=function(index) self.actions.select(index) end,
    }
    self:addviews{self.menu_window}
end

---Returns whether the opening root remains in this screen's native parent chain.
---@param root any
---@return boolean
function ContextMenuScreen:source_root_is_presented(root)
    if not root then return false end
    if not self._native then return true end
    local root_native = rawget(root, '_native')
    local current = self._native.parent
    while current do
        if current == root_native or current.widgets == root then return true end
        current = current.parent
    end
    return root_native == nil
end

---Resolves the current placement anchor without mutating native map state.
---@return {x: integer, y: integer}|nil
function ContextMenuScreen:resolve_anchor()
    if self.anchor.kind == AnchorKind.SCREEN_POSITION then
        return self.anchor.screen_position
    end
    local root = self.session:get_source_root()
    if not self.actions.map_session_is_valid() or
            not self:source_root_is_presented(root) then
        return nil
    end
    local projected = map_projection.project_visible(
        self.anchor.map_position)
    return projected and {x=projected.x, y=projected.y} or nil
end

---Returns whether the current pointer lies in the complete Window frame.
---@return boolean
function ContextMenuScreen:is_pointer_inside()
    local x, y = dfhack.screen.getMousePos()
    local rect = self.menu_window.frame_rect
    if x == nil or y == nil or rect == nil then return false end
    return x >= rect.x1 and x <= rect.x2 and
        y >= rect.y1 and y <= rect.y2
end

---Relayouts the Window from the current full interface dimensions.
function ContextMenuScreen:relayout()
    local body = self.frame_body
    local anchor = self:resolve_anchor()
    if not anchor then return false end
    self.menu_window:set_anchor(anchor)
    self.menu_window:relayout(body.width, body.height)
    return true
end

---Closes through the service when the native screen is dismissed externally.
function ContextMenuScreen:onDismiss()
    if self._presentation_closed then return end
    self._presentation_closed = true
    self.actions.close()
end

---Dismisses the native screen exactly once without creating a second close.
function ContextMenuScreen:close_presentation()
    if self._presentation_closed then return end
    self._presentation_closed = true
    self:dismiss()
end

---Runs one owned transition behind the service failure boundary.
---@param stage string
---@param callback function
---@return boolean succeeded
function ContextMenuScreen:dispatch_owned(stage, callback)
    local ok, failure = xpcall(callback, debug.traceback)
    if not ok then self.actions.fail(stage, failure) end
    return ok
end

---Routes only context-menu-relevant input and delegates everything else.
---@param keys table
---@return boolean
function ContextMenuScreen:onInput(keys)
    local wheel = has_wheel_input(keys)
    local dismiss = keys.LEAVESCREEN or keys._MOUSE_R

    if dismiss then
        self:dispatch_owned('screen dismissal',
            function() self.actions.close() end)
        return true
    end
    local inside = false
    if keys._MOUSE_L or wheel then
        local classified, failure = xpcall(function()
            inside = self:is_pointer_inside()
        end, debug.traceback)
        if not classified then
            self:sendInputToParent(keys)
            self.actions.fail('screen input classification', failure)
            return true
        end
    end
    local outside_left = keys._MOUSE_L and not inside
    if outside_left then
        self:dispatch_owned('outside click dismissal',
            function() self.actions.close() end)
        return true
    end

    local list_owned = keys.SELECT or keys.SELECT_ALL
    for key in pairs(self.menu_window.menu_list.scroll_keys or {}) do
        if keys[key] and not WHEEL_KEYS[key] then list_owned = true end
    end
    if wheel and not inside and not list_owned then
        self:sendInputToParent(keys)
        return true
    end

    local handled = false
    local owned = keys._MOUSE_L or (wheel and inside) or list_owned
    local ok, failure = xpcall(function()
        handled = not not self.menu_window:onInput(keys)
    end, debug.traceback)
    if not ok then
        if not owned then self:sendInputToParent(keys) end
        self.actions.fail('screen input', failure)
        return true
    end
    if handled or (keys._MOUSE_L and inside) or
            (wheel and inside) then
        return true
    end
    self:sendInputToParent(keys)
    return true
end

---Renders the parent first and the menu last behind failure containment.
---@param dc gui.Painter
function ContextMenuScreen:render(dc)
    local ok, failure = xpcall(function()
        if not self.session:is_valid() then
            self.actions.close()
            return
        end
        if not self:relayout() then
            self.actions.close()
            return
        end
        ContextMenuScreen.super.render(self, dc)
    end, debug.traceback)
    if not ok then self.actions.fail('screen render', failure) end
end

---@class dwarfui.ContextMenuScreenController: dwarfui.ContextMenuPresentationController
---@field screen dwarfui.ContextMenuScreen
---@field _shown boolean
ContextMenuScreenController = {}
ContextMenuScreenController.__index = ContextMenuScreenController

---Shows the prepared menu screen exactly once.
function ContextMenuScreenController:show()
    assert(not self._shown, 'DwarfUI context-menu screen is already shown.')
    self._shown = true
    self.screen:show()
end

---Dismisses the prepared or visible menu screen exactly once.
function ContextMenuScreenController:close()
    self.screen:close_presentation()
end

---Creates a hidden screen controller for one authoritative session.
---@param session dwarfui.ContextMenuOpenSession
---@param actions dwarfui.ContextMenuPresentationActions
---@return dwarfui.ContextMenuScreenController
function create_presentation(session, actions)
    local screen = ContextMenuScreen{session=session, actions=actions}
    return setmetatable({screen=screen, _shown=false},
        ContextMenuScreenController)
end

services.service:set_presentation_factory(create_presentation)
services.service:start()
