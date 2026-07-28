--@ module=true

-- Process-wide singleton tooltip registration. At most one tooltip is visible,
-- regardless of how many controls or independently rendered roots register.

local gui = require('gui')
local tooltip = reqscript('dwarfui/tooltip')
local input_service = reqscript('dwarfui/tooltip_service').service
local target_detector = reqscript('dwarfui/tooltip_target_detector')

API_VERSION = 1
local LEGACY_HOST_SLOT = 'tooltip_legacy_host'
local STATE_CHANGE_KEY = 'dwarfui_tooltip_service'

dfhack.dwarfui = dfhack.dwarfui or {}
local host = dfhack.dwarfui[LEGACY_HOST_SLOT]
if host and host.api_version ~= API_VERSION then
    error(('Conflicting DwarfUI tooltip legacy-host versions: ' ..
        'process has %s, requested %s.'):format(
            tostring(host.api_version), tostring(API_VERSION)))
end
if not host then
    host = {
        api_version=API_VERSION,
        sample_sequence=0,
        screen=nil,
    }
    dfhack.dwarfui[LEGACY_HOST_SLOT] = host
end

local TooltipServiceScreen
local ensure_screen
host.sample_sequence = host.sample_sequence or host.legacy_sample_sequence or 0
-- Retire data retained only by the pre-mediation host. Its old onDismiss
-- closure can then release the migrated screen without repeating target
-- callbacks or scheduling a replacement.
host.target = nil
host.registrations = setmetatable({}, {__mode='k'})
host.sequence = nil
host.legacy_sample_sequence = nil
local detector = target_detector.TooltipTargetDetector.new{
    registrations=input_service:get_registrations(),
}

---Returns whether the legacy tooltip ZScreen is currently safe to create.
---@return boolean
local function map_is_loaded()
    return dfhack.isMapLoaded()
end

---Counts weak registrations without retaining their widgets.
---@return integer
local function registration_count()
    return input_service:registration_count()
end

---Clears process-wide pointer and tooltip-intent state.
local function clear_target()
    input_service:shutdown()
end

---Samples the pointer once and publishes one detector observation.
---@return table result
local function update_service()
    local mouse_x, mouse_y = dfhack.screen.getMousePos()
    if mouse_x == nil or mouse_y == nil then
        mouse_x, mouse_y = nil, nil
    end
    host.sample_sequence = host.sample_sequence + 1
    local observation = detector:detect{
        sequence=host.sample_sequence,
        x=mouse_x,
        y=mouse_y,
        coordinate_space='screen-cells',
    }
    input_service:accept_pointer_observation(observation)
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
    input_service:set_intent_observer(function(intent)
        self.renderer:set_tooltip(
            intent and intent.text or nil,
            intent and intent.anchor_x or nil,
            intent and intent.anchor_y or nil,
            self.frame_parent_rect)
    end)
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
    if host.screen == self then
        clear_target()
        input_service:set_intent_observer(nil)
        host.screen = nil
        if registration_count() > 0 and map_is_loaded() then
            dfhack.timeout(1, 'frames', function()
                if not host.screen and registration_count() > 0 and
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
    if host.screen and host.screen:isActive() then
        return host.screen
    end
    host.screen = TooltipServiceScreen{}
    host.screen:show()
    return host.screen
end

---Dismisses the legacy tooltip screen without scheduling its replacement.
local function dismiss_screen()
    if not host.screen then return end
    clear_target()
    input_service:set_intent_observer(nil)
    local screen = host.screen
    host.screen = nil
    if screen:isActive() then screen:dismiss() end
end

---Dismisses the service screen after the final registration disappears.
local function dismiss_if_unused()
    if registration_count() ~= 0 or not host.screen then return end
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
    local created = input_service:register(widget)
    ensure_screen()
    return created
end

---Explicitly removes a registration; weak cleanup makes this optional.
---@param widget table
---@return boolean removed
function unregister(widget)
    local removed = input_service:unregister(widget)
    if not removed then return false end
    dismiss_if_unused()
    return true
end

---Returns observable singleton state for lifecycle probes.
---@return table diagnostics
function get_diagnostics()
    local diagnostics = input_service:get_diagnostics()
    -- TEMPORARY: presentation compatibility fields remain until the legacy
    -- ZScreen consumer is replaced by the rendering plan.
    diagnostics.renderer_count = host.screen and 1 or 0
    diagnostics.screen = host.screen
    return {
        api_version=diagnostics.api_version,
        generation=diagnostics.generation,
        registration_count=diagnostics.registration_count,
        target=diagnostics.target,
        intent=diagnostics.intent,
        revision=diagnostics.revision,
        last_sequence=diagnostics.last_sequence,
        renderer_count=diagnostics.renderer_count,
        screen=diagnostics.screen,
    }
end

-- TEMPORARY: the legacy renderer owns a ZScreen. Keep that screen out of
-- title/load views until the planned render-hook cutover removes it entirely.
dfhack.onStateChange[STATE_CHANGE_KEY] = on_state_change

-- Same-version reload keeps weak registrations but replaces the screen class
-- and renderer so no live object retains closures from the previous module.
if host.screen then dismiss_screen() end
if registration_count() > 0 then ensure_screen() end
