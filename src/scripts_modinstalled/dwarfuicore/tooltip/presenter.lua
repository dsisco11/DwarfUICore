--@ module=true

local class_helpers = reqscript('dwarfuicore/class')

---@class dwarfuicore.TooltipPresenterOptions
---@field service dwarfuicore.TooltipService
---@field hook_manager dwarfuicore.TooltipRenderHookManager
---@field renderer dwarfuicore.TooltipRenderer
---@field transport table
---@field screen_class table
---@field get_overlay_module fun(): table
---@field get_df_viewscreen fun(): table|nil
---@field get_cur_viewscreen fun(): table|nil
---@field get_window_size fun(): integer, integer
---@field new_painter fun(width: integer, height: integer): gui.Painter
---@field invalidate fun()
---@field runtime_generation? integer

---@class dwarfuicore.TooltipPresenterDiagnostics
---@field generation integer
---@field runtime_generation integer
---@field active boolean
---@field current_intent_revision integer|nil
---@field current_source_identity table|nil
---@field service_revision integer
---@field selected_transport dwarfuicore.TooltipRenderTransport|nil
---@field selected_owner table|nil
---@field supported_surface boolean
---@field surface_reason string
---@field last_rendered_revision integer|nil
---@field last_screen_width integer|nil
---@field last_screen_height integer|nil
---@field render_count integer
---@field redraw_count integer
---@field authoritative_intent_prepared boolean
---@field authoritative_intent_active boolean
---@field tooltip_suppressed boolean
---@field authoritative_revision integer|nil
---@field authoritative_transport dwarfuicore.TooltipRenderTransport|nil
---@field authoritative_owner table|nil
---@field authoritative_render_count integer
---@field last_authoritative_cleanup_error string|nil

---@class dwarfuicore.PreparedAuthoritativePresentationIntent
---@field source_root table
---@field transport dwarfuicore.TooltipRenderTransport
---@field owner table
---@field present fun(painter: gui.Painter, transport: dwarfuicore.TooltipRenderTransport, owner: table)
---@field revision integer
---@field active boolean
---@field released boolean

---@class dwarfuicore.TooltipPresenter
---@field _service dwarfuicore.TooltipService
---@field _hook_manager dwarfuicore.TooltipRenderHookManager
---@field _renderer dwarfuicore.TooltipRenderer
---@field _transport table
---@field _screen_class table
---@field _get_overlay_module fun(): table
---@field _get_df_viewscreen fun(): table|nil
---@field _get_cur_viewscreen fun(): table|nil
---@field _get_window_size fun(): integer, integer
---@field _new_painter fun(width: integer, height: integer): gui.Painter
---@field _invalidate fun()
---@field _generation integer
---@field _runtime_generation integer
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
---@field _prepared_authoritative_intent dwarfuicore.PreparedAuthoritativePresentationIntent|nil
---@field _authoritative_intent dwarfuicore.PreparedAuthoritativePresentationIntent|nil
---@field _authoritative_revision integer
---@field _authoritative_render_count integer
---@field _tooltip_suppressed boolean
---@field _last_authoritative_cleanup_error string|nil
TooltipPresenter = {}
TooltipPresenter.__index = TooltipPresenter

---Creates an intent-driven presentation adapter with explicit dependencies.
---@param options dwarfuicore.TooltipPresenterOptions
---@return dwarfuicore.TooltipPresenter
function TooltipPresenter.new(options)
    assert(type(options) == 'table',
        'DwarfUICore TooltipPresenter requires dependency options.')
    for _, name in ipairs({
            'service', 'hook_manager', 'renderer', 'transport',
            'screen_class', 'get_overlay_module',
            'get_df_viewscreen', 'get_cur_viewscreen', 'get_window_size',
            'new_painter', 'invalidate',
        }) do
        assert(options[name] ~= nil,
            'DwarfUICore TooltipPresenter requires ' .. name .. '.')
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
        _runtime_generation=options.runtime_generation or 0,
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
        _prepared_authoritative_intent=nil,
        _authoritative_intent=nil,
        _authoritative_revision=0,
        _authoritative_render_count=0,
        _tooltip_suppressed=false,
        _last_authoritative_cleanup_error=nil,
    }, TooltipPresenter)
end

---Classifies one opaque source root without consulting the input system.
---@param root table
---@return dwarfuicore.TooltipRenderTransport|nil
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
    local authoritative = self._authoritative_intent
    if authoritative then
        self._selected_revision = authoritative.revision
        self._hook_manager:set_current_intent_revision(
            authoritative.revision)
        self._layout_revision = nil
        self._supported_surface = true
        self._surface_reason = 'authoritative-intent'
        self._hook_manager:select_owner(
            authoritative.transport, authoritative.owner)
        return
    end

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

---Prepares one supported authoritative intent without publishing it.
---@param source_root table
---@param present fun(painter: gui.Painter, transport: dwarfuicore.TooltipRenderTransport, owner: table)
---@return dwarfuicore.PreparedAuthoritativePresentationIntent prepared
function TooltipPresenter:prepare_authoritative_intent(source_root, present)
    assert(self._authoritative_intent == nil and
            self._prepared_authoritative_intent == nil,
        'DwarfUICore authoritative presentation intent is already prepared or active.')
    assert(type(present) == 'function',
        'DwarfUICore authoritative presentation intent requires present().')
    local transport, owner = self:_classify_root(source_root)
    assert(transport ~= nil,
        'DwarfUICore authoritative presentation root is unsupported.')
    if transport == self._transport.OVERLAY then
        self._hook_manager:ensure_overlay(false)
    else
        self._hook_manager:ensure_screen(owner, false)
    end
    self._authoritative_revision = self._authoritative_revision - 1
    local prepared = {
        source_root=source_root,
        transport=transport,
        owner=owner,
        present=present,
        revision=self._authoritative_revision,
        active=false,
        released=false,
    }
    self._prepared_authoritative_intent = prepared
    return prepared
end

---Publishes one exact prepared intent and suppresses ordinary tooltips.
---@param prepared any
---@return boolean activated
function TooltipPresenter:activate_authoritative_intent(prepared)
    if self._prepared_authoritative_intent ~= prepared or
            type(prepared) ~= 'table' or prepared.released or prepared.active or
            self._authoritative_intent ~= nil then return false end
    self._prepared_authoritative_intent = nil
    self._authoritative_intent = prepared
    self._tooltip_suppressed = true
    prepared.active = true
    self._selected_revision = prepared.revision
    self._supported_surface = true
    self._surface_reason = 'authoritative-intent'
    self._hook_manager:set_current_intent_revision(prepared.revision)
    self._hook_manager:select_owner(prepared.transport, prepared.owner)
    return true
end

---Releases one prepared or active intent before best-effort tooltip recovery.
---@param prepared any
---@return boolean changed
function TooltipPresenter:release_authoritative_intent(prepared)
    if type(prepared) ~= 'table' then return false end
    local changed = false
    if self._prepared_authoritative_intent == prepared then
        self._prepared_authoritative_intent = nil
        changed = true
    end
    if self._authoritative_intent == prepared then
        self._authoritative_intent = nil
        self._tooltip_suppressed = false
        changed = true
    end
    if not changed then return false end
    prepared.active = false
    prepared.released = true
    local ok, failure = xpcall(function()
        self:_select_current_intent()
    end, debug.traceback)
    if not ok then
        self._last_authoritative_cleanup_error = tostring(failure)
        self._hook_manager:clear_selection()
        if dfhack.printerr then
            pcall(dfhack.printerr,
                'DwarfUICore authoritative presentation cleanup failed:\n' ..
                    tostring(failure))
        end
    end
    return true
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
    self._generation = self._hook_manager:get_diagnostics().generation
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
---@param transport dwarfuicore.TooltipRenderTransport
---@param owner table
---@return integer|nil rendered_revision
function TooltipPresenter:present(transport, owner)
    if not self._active then return nil end
    local authoritative = self._authoritative_intent
    if authoritative then
        if authoritative.revision ~= self._selected_revision or
                authoritative.transport ~= transport or
                authoritative.owner ~= owner then
            self._surface_reason = 'authoritative-owner-mismatch'
            return nil
        end
        if transport == self._transport.SCREEN and
                (authoritative.source_root ~= owner or
                    self._get_cur_viewscreen() ~= owner._native) then
            self._surface_reason = 'screen-not-current'
            return nil
        end
        local width, height = self._get_window_size()
        local painter = self._new_painter(width, height)
        authoritative.present(painter, transport, owner)
        self._supported_surface = true
        self._surface_reason = 'authoritative-intent'
        self._last_rendered_revision = authoritative.revision
        self._last_screen_width = width
        self._last_screen_height = height
        self._render_count = self._render_count + 1
        self._authoritative_render_count =
            self._authoritative_render_count + 1
        return authoritative.revision
    end
    if self._tooltip_suppressed then
        self._surface_reason = 'tooltip-suppressed'
        return nil
    end
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

---Clears authoritative state without selecting another presentation owner.
---@return boolean changed
function TooltipPresenter:_clear_authoritative_intent()
    local changed = self._authoritative_intent ~= nil or
        self._prepared_authoritative_intent ~= nil or
        self._tooltip_suppressed
    if self._authoritative_intent then
        self._authoritative_intent.active = false
        self._authoritative_intent.released = true
    end
    if self._prepared_authoritative_intent then
        self._prepared_authoritative_intent.released = true
    end
    self._authoritative_intent = nil
    self._prepared_authoritative_intent = nil
    self._tooltip_suppressed = false
    return changed
end

---Unsubscribes, clears the renderer, and safely retires this generation.
---@return boolean changed
function TooltipPresenter:shutdown()
    if not self._active then return false end
    self._active = false
    self:_clear_authoritative_intent()
    self._service:set_intent_observer(nil)
    self._hook_manager:set_current_intent_revision(nil)
    self._renderer:set_tooltip(nil, nil, nil, nil)
    self._hook_manager:shutdown()
    self._redraw_count = self._redraw_count + 1
    self._invalidate()
    return true
end

---Retires presentation while retaining inert reload-safe render trampolines.
---@return boolean changed
function TooltipPresenter:retire_for_reload()
    if not self._active then return false end
    self._active = false
    self:_clear_authoritative_intent()
    self._service:set_intent_observer(nil)
    self._hook_manager:set_current_intent_revision(nil)
    self._renderer:set_tooltip(nil, nil, nil, nil)
    self._hook_manager:set_presenter(nil)
    self._hook_manager:clear_selection()
    self._redraw_count = self._redraw_count + 1
    self._invalidate()
    return true
end

---Returns presentation, selection, layout, redraw, and render diagnostics.
---@return dwarfuicore.TooltipPresenterDiagnostics
function TooltipPresenter:get_diagnostics()
    local intent = self._service:get_intent()
    local authoritative = self._authoritative_intent or
        self._prepared_authoritative_intent
    local service_diagnostics = self._service:get_diagnostics()
    local hook_diagnostics = self._hook_manager:get_diagnostics()
    return {
        generation=self._generation,
        runtime_generation=self._runtime_generation,
        active=self._active,
        current_intent_revision=intent and intent.revision or nil,
        current_source_identity=intent and intent.source_identity or nil,
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
        authoritative_intent_prepared=
            self._prepared_authoritative_intent ~= nil,
        authoritative_intent_active=self._authoritative_intent ~= nil,
        tooltip_suppressed=self._tooltip_suppressed,
        authoritative_revision=authoritative and
            authoritative.revision or nil,
        authoritative_transport=authoritative and
            authoritative.transport or nil,
        authoritative_owner=authoritative and
            authoritative.owner or nil,
        authoritative_render_count=self._authoritative_render_count,
        last_authoritative_cleanup_error=
            self._last_authoritative_cleanup_error,
    }
end
