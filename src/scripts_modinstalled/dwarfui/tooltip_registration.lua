--@ module=true

-- Process-wide singleton tooltip registration. At most one tooltip is visible,
-- regardless of how many controls or independently rendered roots register.

local gui = require('gui')
local tooltip = reqscript('dwarfui/tooltip')
local target_detector = reqscript('dwarfui/tooltip_target_detector')

API_VERSION = 1
local SERVICE_SLOT = 'tooltip_service'
local STATE_CHANGE_KEY = 'dwarfui_tooltip_service'

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
        legacy_sample_sequence=0,
        screen=nil,
        target=nil,
    }
    dfhack.dwarfui[SERVICE_SLOT] = service
end

local TooltipServiceScreen
local ensure_screen
service.legacy_sample_sequence = service.legacy_sample_sequence or 0
local detector = target_detector.TooltipTargetDetector.new{
    registrations=service.registrations,
}

---Returns whether the legacy tooltip ZScreen is currently safe to create.
---@return boolean
local function map_is_loaded()
    return dfhack.isMapLoaded()
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

---Samples the pointer once and presents the single winning tooltip.
---@return table result
local function update_service()
    local mouse_x, mouse_y = dfhack.screen.getMousePos()
    if mouse_x == nil or mouse_y == nil then
        mouse_x, mouse_y = nil, nil
    end
    service.legacy_sample_sequence = service.legacy_sample_sequence + 1
    local observation = detector:detect{
        sequence=service.legacy_sample_sequence,
        x=mouse_x,
        y=mouse_y,
        coordinate_space='screen-cells',
    }
    local target = observation.kind == 'target' and
        observation.target or nil

    local previous = service.target
    if previous ~= target then
        if previous and previous.on_pointer_leave then
            previous.on_pointer_leave(previous)
        end
        if target and target.on_pointer_enter then
            target.on_pointer_enter(
                target, observation.local_x, observation.local_y)
        end
    end
    if target and target.on_pointer_update then
        target.on_pointer_update(
            target, observation.local_x, observation.local_y)
    end
    service.target = target

    local tooltip_text = get_tooltip(target)
    service.screen.renderer:set_tooltip(
        tooltip_text,
        tooltip_text and mouse_x or nil,
        tooltip_text and mouse_y or nil,
        service.screen.frame_parent_rect)
    return observation
end

---@class dwarfui.TooltipServiceScreen: gui.ZScreen
---@field renderer table
TooltipServiceScreen = defclass(TooltipServiceScreen, gui.ZScreen)
TooltipServiceScreen.ATTRS{
    defocusable=true,
    defocused=true,
    initial_pause=false,
    pass_mouse_clicks=true,
    pass_movement_keys=true,
}

---Keeps the service above newly opened screens without taking focus from them.
---@param screen dwarfui.TooltipServiceScreen
local function restore_screen_position(screen)
    if not screen:isActive() then return end
    if dfhack.gui.getCurViewscreen(true) ~= screen._native then
        screen:raise()
    end
    screen.defocused = true
end

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
    restore_screen_position(self)
    return true
end

---Advances parent logic and uses the supported ZScreen raise operation when a
---new screen has been placed above the tooltip service.
function TooltipServiceScreen:onIdle()
    TooltipServiceScreen.super.onIdle(self)
    restore_screen_position(self)
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
        if registration_count() > 0 and map_is_loaded() then
            dfhack.timeout(1, 'frames', function()
                if not service.screen and registration_count() > 0 and
                        map_is_loaded() then
                    ensure_screen()
                end
            end)
        end
    end
end

---Creates and shows the singleton screen when registrations require it.
---@return table|nil screen
ensure_screen = function()
    if not map_is_loaded() then return nil end
    if service.screen and service.screen:isActive() then
        return service.screen
    end
    service.screen = TooltipServiceScreen{}
    service.screen:show()
    return service.screen
end

---Dismisses the legacy tooltip screen without scheduling its replacement.
local function dismiss_screen()
    if not service.screen then return end
    clear_target()
    local screen = service.screen
    service.screen = nil
    if screen:isActive() then screen:dismiss() end
end

---Dismisses the service screen after the final registration disappears.
local function dismiss_if_unused()
    if registration_count() ~= 0 or not service.screen then return end
    dismiss_screen()
end

---Temporarily confines the legacy ZScreen host to loaded fortress maps.
---@param code integer
local function on_state_change(code)
    if code == SC_MAP_LOADED then
        if registration_count() > 0 then ensure_screen() end
    elseif code == SC_MAP_UNLOADED or code == SC_WORLD_UNLOADED then
        dismiss_screen()
    end
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

-- TEMPORARY: the legacy renderer owns a ZScreen. Keep that screen out of
-- title/load views until the planned render-hook cutover removes it entirely.
dfhack.onStateChange[STATE_CHANGE_KEY] = on_state_change

-- Same-version reload keeps weak registrations but replaces the screen class
-- and renderer so no live object retains closures from the previous module.
if service.screen then dismiss_screen() end
if registration_count() > 0 then ensure_screen() end
