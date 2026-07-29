--@ module=true

local gui = require('gui')
local widgets = require('gui.widgets')
reqscript('dwarfui/widget_extensions')
local pointer = reqscript('dwarfui/pointer')
local text_helpers = reqscript('dwarfui/text')
local tooltip_service_module = reqscript('dwarfui/tooltip_service')
local render_hook_module = reqscript('dwarfui/tooltip_render_hook')

local BACKGROUND = dfhack.pen.parse{
    ch=32,
    fg=COLOR_BLACK,
    bg=COLOR_BLACK,
}
local TEXT = dfhack.pen.parse{fg=COLOR_WHITE, bg=COLOR_BLACK}

-- A moving tooltip is presentation layered over a host, not a Panel or Window.
-- Keeping it a plain Widget avoids their global layout/redraw lifecycle inside
-- the host's render pass.
---@class dwarfui.TooltipRenderer: gui.widgets.Widget
TooltipRenderer = defclass(nil, widgets.Widget)
TooltipRenderer.ATTRS{
    frame={l=0, t=0, w=1, h=3},
    frame_style=gui.FRAME_INTERIOR,
    frame_background=BACKGROUND,
    frame_inset=1,
    draggable=false,
    no_force_pause_badge=true,
    pointer_policy='none',
    visible=false,
}

---Constructs the hidden renderer and its text label.
function TooltipRenderer:init()
    self.visible = false
    self.tooltip_text = nil
    self.mouse_x = nil
    self.mouse_y = nil
    self.label = widgets.Label{
        frame={l=0, t=0, w=1, h=1},
        auto_height=false,
        text_pen=TEXT,
        text='',
        pointer_policy='none',
    }
    self:addviews{self.label}
end

---@param text string|nil
---@param mouse_x integer|nil
---@param mouse_y integer|nil
---@param layout_parent_rect gui.ViewRect|nil
function TooltipRenderer:set_tooltip(
        text, mouse_x, mouse_y, layout_parent_rect)
    local has_text = text ~= nil and text ~= ''
    local has_pointer = mouse_x ~= nil and mouse_y ~= nil
    local visible = has_text and has_pointer
    local tooltip_text = visible and text or nil
    local changed = self.visible ~= visible or
        self.tooltip_text ~= tooltip_text or
        self.mouse_x ~= mouse_x or self.mouse_y ~= mouse_y

    self.visible = visible
    self.tooltip_text = tooltip_text
    self.mouse_x = mouse_x
    self.mouse_y = mouse_y

    if self.visible then
        local screen_width, screen_height
        if layout_parent_rect then
            screen_width = layout_parent_rect.width
            screen_height = layout_parent_rect.height
        else
            screen_width, screen_height = dfhack.screen.getWindowSize()
        end
        local content_width = math.max(
            1, math.min(60, screen_width - 2))
        local lines = text_helpers.wrap_text(
            self.tooltip_text, content_width)
        local width = 2
        for _, line in ipairs(lines) do
            width = math.max(width, #line + 2)
        end
        local height = #lines + 2
        self.frame = {
            l=math.max(0, math.min(mouse_x + 2, screen_width - width)),
            t=math.max(0, math.min(mouse_y + 1, screen_height - height)),
            w=width,
            h=height,
        }
        self.label.frame = {l=0, t=0, w=width - 2, h=height - 2}
        self.label:setText(table.concat(lines, '\n'))
        self:updateLayout(layout_parent_rect)
    else
        self.label:setText('')
    end

    -- Visibility and frame changes do not redraw the old screen cells by
    -- themselves. Invalidating the owner makes updates and mouse-out immediate.
    if changed and self.parent_view and self.parent_view.invalidate then
        self.parent_view:invalidate()
    end
end

---Renders only while the renderer owns visible tooltip text.
---@param dc gui.Painter
function TooltipRenderer:render(dc)
    if not self.visible then return end
    TooltipRenderer.super.render(self, dc)
end

---Paints the tooltip background and interior frame.
---@param dc gui.Painter
---@param rect gui.ViewRect
function TooltipRenderer:onRenderFrame(dc, rect)
    if self.frame_background then
        dc:fill(rect, self.frame_background)
    end
    gui.paint_frame(dc, rect, self.frame_style)
end

---Returns the DFHack class table for an instance in production or tests.
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

---@class dwarfui.TooltipPresenterOptions
---@field service dwarfui.TooltipService
---@field hook_manager dwarfui.TooltipRenderHookManager
---@field renderer dwarfui.TooltipRenderer
---@field transport table
---@field screen_class table
---@field get_overlay_module fun(): table
---@field get_df_viewscreen fun(): table|nil
---@field get_cur_viewscreen fun(): table|nil
---@field get_window_size fun(): integer, integer
---@field new_painter fun(width: integer, height: integer): gui.Painter
---@field invalidate fun()

---@class dwarfui.TooltipPresenterDiagnostics
---@field generation integer
---@field active boolean
---@field current_intent_revision integer|nil
---@field service_revision integer
---@field selected_transport dwarfui.TooltipRenderTransport|nil
---@field selected_owner table|nil
---@field supported_surface boolean
---@field surface_reason string
---@field last_rendered_revision integer|nil
---@field last_screen_width integer|nil
---@field last_screen_height integer|nil
---@field render_count integer
---@field redraw_count integer

---@class dwarfui.TooltipPresenter
---@field _service dwarfui.TooltipService
---@field _hook_manager dwarfui.TooltipRenderHookManager
---@field _renderer dwarfui.TooltipRenderer
---@field _transport table
---@field _screen_class table
---@field _get_overlay_module fun(): table
---@field _get_df_viewscreen fun(): table|nil
---@field _get_cur_viewscreen fun(): table|nil
---@field _get_window_size fun(): integer, integer
---@field _new_painter fun(width: integer, height: integer): gui.Painter
---@field _invalidate fun()
---@field _generation integer
---@field _active boolean
---@field _selected_revision integer|nil
---@field _supported_surface boolean
---@field _surface_reason string
---@field _layout_revision integer|nil
---@field _last_rendered_revision integer|nil
---@field _last_screen_width integer|nil
---@field _last_screen_height integer|nil
---@field _render_count integer
---@field _redraw_count integer
TooltipPresenter = {}
TooltipPresenter.__index = TooltipPresenter

---Creates an intent-driven presentation adapter with explicit dependencies.
---@param options dwarfui.TooltipPresenterOptions
---@return dwarfui.TooltipPresenter
function TooltipPresenter.new(options)
    assert(type(options) == 'table',
        'DwarfUI TooltipPresenter requires dependency options.')
    for _, name in ipairs({
            'service', 'hook_manager', 'renderer', 'transport',
            'screen_class', 'get_overlay_module',
            'get_df_viewscreen', 'get_cur_viewscreen', 'get_window_size',
            'new_painter', 'invalidate',
        }) do
        assert(options[name] ~= nil,
            'DwarfUI TooltipPresenter requires ' .. name .. '.')
    end
    return setmetatable({
        _service=options.service,
        _hook_manager=options.hook_manager,
        _renderer=options.renderer,
        _transport=options.transport,
        _screen_class=options.screen_class,
        _get_overlay_module=options.get_overlay_module,
        _get_df_viewscreen=options.get_df_viewscreen,
        _get_cur_viewscreen=options.get_cur_viewscreen,
        _get_window_size=options.get_window_size,
        _new_painter=options.new_painter,
        _invalidate=options.invalidate,
        _generation=options.hook_manager:get_diagnostics().generation,
        _active=false,
        _selected_revision=nil,
        _supported_surface=false,
        _surface_reason='inactive-intent',
        _layout_revision=nil,
        _last_rendered_revision=nil,
        _last_screen_width=nil,
        _last_screen_height=nil,
        _render_count=0,
        _redraw_count=0,
    }, TooltipPresenter)
end

---Classifies one opaque source root without consulting the input system.
---@param root table
---@return dwarfui.TooltipRenderTransport|nil
---@return table|nil owner
---@return string reason
function TooltipPresenter:_classify_root(root)
    if type(root) ~= 'table' then
        return nil, nil, 'unsupported-root'
    end
    if is_instance(root, self._screen_class) then
        if root._native ~= nil and type(root.onRender) == 'function' then
            return self._transport.SCREEN, root, 'lua-screen'
        end
        return nil, nil, 'undisplayed-or-unrenderable-screen'
    end
    local overlay_module = self._get_overlay_module()
    if type(overlay_module.OverlayWidget) == 'table' and
            is_instance(root, overlay_module.OverlayWidget) then
        return self._transport.OVERLAY,
            overlay_module, 'overlay-widget'
    end
    local native = self._get_df_viewscreen()
    if native and native.widgets == root then
        return self._transport.OVERLAY,
            overlay_module, 'native-root'
    end
    return nil, nil, 'unsupported-root'
end

---Selects and repairs exactly one transport for the authoritative intent.
function TooltipPresenter:_select_current_intent()
    local intent = self._service:get_intent()
    self._selected_revision = intent and intent.revision or nil
    self._layout_revision = nil
    if not intent then
        self._supported_surface = false
        self._surface_reason = 'inactive-intent'
        self._hook_manager:clear_selection()
        self._renderer:set_tooltip(nil, nil, nil, nil)
        return
    end

    local transport, owner, reason =
        self:_classify_root(intent.source_root)
    self._supported_surface = transport ~= nil
    self._surface_reason = reason
    if transport == self._transport.OVERLAY then
        self._hook_manager:ensure_overlay()
    elseif transport == self._transport.SCREEN then
        self._hook_manager:ensure_screen(owner)
    else
        self._hook_manager:clear_selection()
        self._renderer:set_tooltip(nil, nil, nil, nil)
    end
end

---Repairs selection and requests one redraw for an intent notification.
function TooltipPresenter:_on_intent_changed()
    self:_select_current_intent()
    self._redraw_count = self._redraw_count + 1
    self._invalidate()
end

---Subscribes this generation and installs the inert global overlay seam.
---@return boolean started
function TooltipPresenter:start()
    if self._active then return false end
    self._active = true
    self._hook_manager:set_presenter(function(transport, owner)
        return self:present(transport, owner)
    end)
    -- Install the native transport at subscription time, then let the current
    -- intent select the one eligible transport owner.
    self._hook_manager:ensure_overlay()
    self._hook_manager:clear_selection()
    self._service:set_intent_observer(function()
        self:_on_intent_changed()
    end)
    self:_select_current_intent()
    return true
end

---Presents the current intent through the selected completed render seam.
---@param transport dwarfui.TooltipRenderTransport
---@param owner table
---@return integer|nil rendered_revision
function TooltipPresenter:present(transport, owner)
    if not self._active then return nil end
    local intent = self._service:get_intent()
    if not intent or intent.revision ~= self._selected_revision then
        self._surface_reason = 'inactive-or-stale-intent'
        return nil
    end
    local expected_transport, expected_owner, reason =
        self:_classify_root(intent.source_root)
    if expected_transport ~= transport or expected_owner ~= owner then
        self._surface_reason = 'transport-owner-mismatch'
        return nil
    end
    if transport == self._transport.SCREEN and
            (intent.source_root ~= owner or
                self._get_cur_viewscreen() ~= owner._native) then
        self._surface_reason = 'screen-not-current'
        return nil
    end

    local width, height = self._get_window_size()
    local painter = self._new_painter(width, height)
    if self._layout_revision ~= intent.revision or
            self._last_screen_width ~= width or
            self._last_screen_height ~= height then
        self._renderer:set_tooltip(
            intent.text, intent.anchor_x, intent.anchor_y, painter)
        self._layout_revision = intent.revision
    end
    self._renderer:render(painter)
    self._supported_surface = true
    self._surface_reason = reason
    self._last_rendered_revision = intent.revision
    self._last_screen_width = width
    self._last_screen_height = height
    self._render_count = self._render_count + 1
    return intent.revision
end

---Unsubscribes, clears the renderer, and safely retires this generation.
---@return boolean changed
function TooltipPresenter:shutdown()
    if not self._active then return false end
    self._active = false
    self._service:set_intent_observer(nil)
    self._renderer:set_tooltip(nil, nil, nil, nil)
    self._hook_manager:shutdown()
    self._redraw_count = self._redraw_count + 1
    self._invalidate()
    return true
end

---Returns presentation, selection, layout, redraw, and render diagnostics.
---@return dwarfui.TooltipPresenterDiagnostics
function TooltipPresenter:get_diagnostics()
    local intent = self._service:get_intent()
    local service_diagnostics = self._service:get_diagnostics()
    local hook_diagnostics = self._hook_manager:get_diagnostics()
    return {
        generation=self._generation,
        active=self._active,
        current_intent_revision=intent and intent.revision or nil,
        service_revision=service_diagnostics.revision,
        selected_transport=hook_diagnostics.selected_transport,
        selected_owner=hook_diagnostics.selected_owner,
        supported_surface=self._supported_surface,
        surface_reason=self._surface_reason,
        last_rendered_revision=self._last_rendered_revision,
        last_screen_width=self._last_screen_width,
        last_screen_height=self._last_screen_height,
        render_count=self._render_count,
        redraw_count=self._redraw_count,
    }
end

---@class dwarfui.TooltipAgent
---@field root gui.View
---@field pointer_context dwarfui.PointerContext
---@field renderer dwarfui.TooltipRenderer
TooltipAgent = {}
TooltipAgent.__index = TooltipAgent

---@param root gui.View
---@param renderer table
---@return table
function TooltipAgent.new(root, renderer)
    assert(root, 'DwarfUI TooltipAgent requires a pointer root.')
    assert(renderer, 'DwarfUI TooltipAgent requires a tooltip renderer.')
    return setmetatable({
        root=root,
        pointer_context=pointer.PointerContext.new(root),
        renderer=renderer,
    }, TooltipAgent)
end

local function get_tooltip(target)
    if not target then return nil end
    local value = target.tooltip
    if value == nil or value == '' then return nil end
    assert(type(value) == 'string',
        'DwarfUI tooltip must be a string, nil, or an empty string; got ' ..
        type(value) .. '.')
    return value
end

---@return table pointer_result
function TooltipAgent:update()
    -- One read feeds dispatch and placement, including the no-pointer case.
    local mouse_x, mouse_y = dfhack.screen.getMousePos()
    local result = pointer.PointerDispatcher.sample(
        self.pointer_context, mouse_x, mouse_y)
    -- Dispatch happens first so a terminal callback can update tooltip text for
    -- these exact local coordinates before presentation reads the current value.
    local tooltip_text = result.kind == 'target' and
        get_tooltip(result.target) or nil
    self.renderer:set_tooltip(
        tooltip_text,
        mouse_x,
        mouse_y,
        self.root.frame_parent_rect)
    return result
end

---Registers a widget with the process-wide singleton tooltip service.
---@param widget table
---@return boolean created
function register(widget)
    return reqscript('dwarfui/tooltip_registration').register(widget)
end

---Explicitly unregisters a widget; weak lifetime cleanup makes this optional.
---@param widget table
---@return boolean removed
function unregister(widget)
    return reqscript('dwarfui/tooltip_registration').unregister(widget)
end

presenter = TooltipPresenter.new{
    service=tooltip_service_module.service,
    hook_manager=render_hook_module.manager,
    renderer=TooltipRenderer{},
    transport=render_hook_module.TooltipRenderTransport,
    screen_class=gui.Screen,
    get_overlay_module=function()
        return require('plugins.overlay')
    end,
    get_df_viewscreen=function()
        return dfhack.gui.getDFViewscreen(true)
    end,
    get_cur_viewscreen=function()
        return dfhack.gui.getCurViewscreen(true)
    end,
    get_window_size=dfhack.screen.getWindowSize,
    new_painter=function(width, height)
        return gui.Painter.new{
            x1=0,
            y1=0,
            x2=width - 1,
            y2=height - 1,
        }
    end,
    invalidate=dfhack.screen.invalidate,
}
presenter:start()
