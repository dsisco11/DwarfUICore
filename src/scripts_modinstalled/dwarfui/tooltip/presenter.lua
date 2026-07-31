--@ module=true

local class_helpers = reqscript('dwarfui/class')

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
    if class_helpers.is_instance_of(root, self._screen_class) then
        if root._native ~= nil and type(root.onRender) == 'function' then
            return self._transport.SCREEN, root, 'lua-screen'
        end
        return nil, nil, 'undisplayed-or-unrenderable-screen'
    end
    local overlay_module = self._get_overlay_module()
    if type(overlay_module.OverlayWidget) == 'table' and
            class_helpers.is_instance_of(
                root, overlay_module.OverlayWidget) then
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
    self._hook_manager:set_current_intent_revision(
        self._selected_revision)
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
    self._hook_manager:set_current_intent_revision(nil)
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
