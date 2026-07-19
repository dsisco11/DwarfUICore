--@ module=true

-- Process-wide singleton tooltip registration. At most one tooltip is visible,
-- regardless of how many controls or independently rendered roots register.

local gui = require('gui')
local overlay = require('plugins.overlay')
local pointer = reqscript('dwarfui/pointer')
local tooltip = reqscript('dwarfui/tooltip')

API_VERSION = 1
local SERVICE_SLOT = 'tooltip_service'

dfhack.dwarfui = dfhack.dwarfui or {}
local service = dfhack.dwarfui[SERVICE_SLOT]
if service and service.api_version ~= API_VERSION then
    error(('Conflicting DwarfUI tooltip service versions: ' ..
        'process has %s, requested %s.'):format(
            tostring(service.api_version), tostring(API_VERSION)))
end
if not service then
    service = {
        api_version=API_VERSION,
        registrations=setmetatable({}, {__mode='k'}),
        sequence=0,
        screen=nil,
        target=nil,
    }
    dfhack.dwarfui[SERVICE_SLOT] = service
end

local TooltipServiceScreen
local ensure_screen

---Returns the DFHack class table for an instance in production or the tests.
---@param instance table
---@return table|nil
local function get_instance_class(instance)
    local class = getmetatable(instance)
    if class and rawget(class, 'super') == nil and
            type(rawget(class, '__index')) == 'table' then
        class = rawget(class, '__index')
    end
    return class
end

---Returns whether an instance inherits from the requested DFHack class.
---@param instance table
---@param expected table
---@return boolean
local function is_instance(instance, expected)
    local class = get_instance_class(instance)
    while class do
        if class == expected then return true end
        class = rawget(class, 'super')
    end
    return false
end

---Evaluates a DFHack boolean or boolean callback.
---@param value boolean|function|nil
---@return boolean
local function getval(value)
    if type(value) == 'function' then return value() end
    return not not value
end

---Returns the current top-level view for an attached widget.
---@param widget table
---@return table root
local function find_root(widget)
    local current = widget
    local seen = {}
    while current and current.parent_view and not seen[current] do
        seen[current] = true
        current = current.parent_view
    end
    return current
end

---Returns whether a widget and every attached ancestor are eligible.
---@param widget table
---@return boolean
local function ancestors_are_eligible(widget)
    local current = widget
    local seen = {}
    while current and not seen[current] do
        seen[current] = true
        if not getval(current.visible) or not getval(current.active) then
            return false
        end
        current = current.parent_view
    end
    return true
end

---Returns whether an overlay declares the current underlying viewscreen.
---@param root table
---@return boolean
local function overlay_matches_current_viewscreen(root)
    local current = dfhack.gui.getDFViewscreen(true)
    if not current then return false end
    for _, focus in ipairs(overlay.normalize_list(root.viewscreens)) do
        if focus == 'all' or dfhack.gui.matchFocusString(
                overlay.simplify_viewscreen_name(focus), current) then
            return true
        end
    end
    return false
end

---Returns whether a root is currently owned by an active rendering framework.
---@param root table
---@return boolean
local function root_is_presented(root)
    if is_instance(root, overlay.OverlayWidget) then
        if not root.name or not overlay.isOverlayEnabled(root.name) then
            return false
        end
        local overlay_state = overlay.get_state()
        local entry = overlay_state.db[root.name]
        return entry ~= nil and entry.widget == root and
            overlay_matches_current_viewscreen(root)
    end
    if root._native and service.screen and service.screen._native then
        return root._native == service.screen._native.parent
    end
    return true
end

---Reads validated tooltip text after pointer callbacks have run.
---@param target table|nil
---@return string|nil
local function get_tooltip(target)
    if not target then return nil end
    local value = target.tooltip
    if value == nil or value == '' then return nil end
    assert(type(value) == 'string',
        'DwarfUI tooltip must be a string, nil, or an empty string; got ' ..
        type(value) .. '.')
    return value
end

---Counts weak registrations without retaining their widgets.
---@return integer
local function registration_count()
    local count = 0
    for _ in pairs(service.registrations) do count = count + 1 end
    return count
end

---Clears the process-wide target and visible tooltip.
local function clear_target()
    local previous = service.target
    if previous and previous.on_pointer_leave then
        previous.on_pointer_leave(previous)
    end
    service.target = nil
    if service.screen and service.screen.renderer then
        service.screen.renderer:set_tooltip(nil, nil, nil,
            service.screen.frame_parent_rect)
    end
end

---Chooses one registered target across all currently attached roots.
---Within a root, native reverse-subview traversal decides. Across independent
---roots, the most recently registered winning target has deterministic priority.
---@param mouse_x integer
---@param mouse_y integer
---@return table|nil target
---@return table|nil pointer_result
local function resolve_target(mouse_x, mouse_y)
    local roots = {}
    for widget in pairs(service.registrations) do
        if ancestors_are_eligible(widget) then
            local root = find_root(widget)
            if root and root ~= service.screen and root.frame_body and
                    root_is_presented(root) then
                roots[root] = true
            end
        end
    end

    local best_target, best_result, best_sequence
    for root in pairs(roots) do
        local result = pointer.PointerDispatcher.resolve(
            root, mouse_x, mouse_y)
        local target = result.kind == 'target' and result.target or nil
        local registration = target and service.registrations[target] or nil
        if registration and
                (not best_sequence or registration.sequence > best_sequence) then
            best_target = target
            best_result = result
            best_sequence = registration.sequence
        end
    end
    return best_target, best_result
end

---Samples the pointer once and presents the single winning tooltip.
---@return table result
local function update_service()
    local mouse_x, mouse_y = dfhack.screen.getMousePos()
    local target, result
    if mouse_x ~= nil and mouse_y ~= nil then
        target, result = resolve_target(mouse_x, mouse_y)
    end

    local previous = service.target
    if previous ~= target then
        if previous and previous.on_pointer_leave then
            previous.on_pointer_leave(previous)
        end
        if target and target.on_pointer_enter then
            target.on_pointer_enter(target, result.x, result.y)
        end
    end
    if target and target.on_pointer_update then
        target.on_pointer_update(target, result.x, result.y)
    end
    service.target = target

    local tooltip_text = get_tooltip(target)
    service.screen.renderer:set_tooltip(
        tooltip_text,
        tooltip_text and mouse_x or nil,
        tooltip_text and mouse_y or nil,
        service.screen.frame_parent_rect)
    return result or {kind='miss'}
end

---@class dwarfui.ExperimentalTooltipServiceScreen: gui.ZScreen
---@field renderer table
TooltipServiceScreen = defclass(TooltipServiceScreen, gui.ZScreen)
TooltipServiceScreen.ATTRS{
    defocusable=false,
    initial_pause=false,
    pass_mouse_clicks=true,
    pass_movement_keys=true,
}

---Constructs the singleton screen-owned tooltip renderer.
function TooltipServiceScreen:init()
    self.renderer = tooltip.TooltipRenderer{}
    self.renderer.parent_view = self
end

---Renders the complete parent stack, samples once, and draws the tooltip last.
function TooltipServiceScreen:onRender()
    self:renderParent()
    if registration_count() == 0 then
        clear_target()
        self:dismiss()
        return
    end
    update_service()
    if self.renderer.visible then
        self.renderer:render(gui.Painter.new())
    end
end

---Forwards all input to the underlying screen without claiming mouse cells.
---@param keys table
---@return boolean
function TooltipServiceScreen:onInput(keys)
    self:sendInputToParent(keys)
    return true
end

---Advances parent logic and uses the supported ZScreen raise operation when a
---new screen has been placed above the tooltip service.
function TooltipServiceScreen:onIdle()
    TooltipServiceScreen.super.onIdle(self)
    if self:isActive() and not self:hasFocus() then self:raise() end
end

---Keeps the transparent service from ever claiming a mouse hit.
---@return boolean
function TooltipServiceScreen:isMouseOver()
    return false
end

---Releases only this screen generation when DFHack dismisses it.
function TooltipServiceScreen:onDismiss()
    if service.screen == self then
        clear_target()
        service.screen = nil
        if registration_count() > 0 then
            dfhack.timeout(1, 'frames', function()
                if not service.screen and registration_count() > 0 then
                    ensure_screen()
                end
            end)
        end
    end
end

---Creates and shows the singleton screen when registrations require it.
---@return table screen
ensure_screen = function()
    if service.screen and service.screen:isActive() then
        return service.screen
    end
    service.screen = TooltipServiceScreen{}
    service.screen:show()
    return service.screen
end

---Dismisses the service screen after the final registration disappears.
local function dismiss_if_unused()
    if registration_count() ~= 0 or not service.screen then return end
    clear_target()
    local screen = service.screen
    service.screen = nil
    if screen:isActive() then screen:dismiss() end
end

---Registers any widget for process-wide singleton tooltip targeting.
---Registration is valid before attachment; detached widgets are simply skipped.
---@param widget table
---@return boolean created
function register(widget)
    assert(type(widget) == 'table',
        'DwarfUI tooltip registration requires a widget table.')
    if service.registrations[widget] then
        ensure_screen()
        return false
    end
    service.sequence = service.sequence + 1
    service.registrations[widget] = {sequence=service.sequence}
    ensure_screen()
    return true
end

---Explicitly removes a registration; weak cleanup makes this optional.
---@param widget table
---@return boolean removed
function unregister(widget)
    local removed = service.registrations[widget] ~= nil
    if not removed then return false end
    service.registrations[widget] = nil
    if service.target == widget then clear_target() end
    dismiss_if_unused()
    return true
end

---Returns observable singleton state for lifecycle probes.
---@return table diagnostics
function get_diagnostics()
    return {
        api_version=API_VERSION,
        registration_count=registration_count(),
        renderer_count=service.screen and 1 or 0,
        screen=service.screen,
        target=service.target,
    }
end

-- Same-version reload keeps weak registrations but replaces the screen class
-- and renderer so no live object retains closures from the previous module.
if service.screen then
    clear_target()
    local previous_screen = service.screen
    service.screen = nil
    if previous_screen:isActive() then previous_screen:dismiss() end
end
if registration_count() > 0 then ensure_screen() end
