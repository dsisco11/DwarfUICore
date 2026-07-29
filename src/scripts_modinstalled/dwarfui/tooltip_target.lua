--@ module=true

-- Normalized tooltip targets bridge heterogeneous hit domains into the
-- process-wide tooltip service without making map registrations imitate views.

---@enum dwarfui.TooltipTargetKind
TooltipTargetKind = {
    WIDGET=1,
    MAP_TILE=2,
}

---@enum dwarfui.TooltipPointerObservationKind
TooltipPointerObservationKind = {
    TARGET=1,
    BLOCKED=2,
    MISS=3,
}

---@class dwarfui.TooltipTargetAdapterOptions
---@field identity any
---@field kind dwarfui.TooltipTargetKind
---@field source_root gui.View
---@field is_current fun(): boolean
---@field get_tooltip fun(): any
---@field on_pointer_enter fun(x: integer|nil, y: integer|nil)|nil
---@field on_pointer_update fun(x: integer|nil, y: integer|nil)|nil
---@field on_pointer_leave fun()|nil

---@class dwarfui.TooltipTargetAdapter
---@field _identity any
---@field _kind dwarfui.TooltipTargetKind
---@field _source_root gui.View
---@field _is_current fun(): boolean
---@field _get_tooltip fun(): any
---@field _on_pointer_enter fun(x: integer|nil, y: integer|nil)|nil
---@field _on_pointer_update fun(x: integer|nil, y: integer|nil)|nil
---@field _on_pointer_leave fun()|nil
TooltipTargetAdapter = {}
TooltipTargetAdapter.__index = TooltipTargetAdapter

---Creates one normalized tooltip target over caller-owned accessors.
---@param options dwarfui.TooltipTargetAdapterOptions
---@return dwarfui.TooltipTargetAdapter
function TooltipTargetAdapter.new(options)
    assert(type(options) == 'table',
        'DwarfUI tooltip target adapter requires options.')
    assert(options.identity ~= nil,
        'DwarfUI tooltip target adapter requires stable identity.')
    assert(options.kind == TooltipTargetKind.WIDGET or
            options.kind == TooltipTargetKind.MAP_TILE,
        'DwarfUI tooltip target adapter kind must be a TooltipTargetKind.')
    assert(type(options.source_root) == 'table',
        'DwarfUI tooltip target adapter requires a source root.')
    assert(type(options.is_current) == 'function',
        'DwarfUI tooltip target adapter requires a current-state accessor.')
    assert(type(options.get_tooltip) == 'function',
        'DwarfUI tooltip target adapter requires a tooltip accessor.')
    return setmetatable({
        _identity=options.identity,
        _kind=options.kind,
        _source_root=options.source_root,
        _is_current=options.is_current,
        _get_tooltip=options.get_tooltip,
        _on_pointer_enter=options.on_pointer_enter,
        _on_pointer_update=options.on_pointer_update,
        _on_pointer_leave=options.on_pointer_leave,
    }, TooltipTargetAdapter)
end

---Returns this adapter's stable target identity.
---@return any
function TooltipTargetAdapter:get_identity()
    return self._identity
end

---Returns this adapter's hit-domain kind.
---@return dwarfui.TooltipTargetKind
function TooltipTargetAdapter:get_kind()
    return self._kind
end

---Returns the eligible root that owns presentation transport.
---@return gui.View
function TooltipTargetAdapter:get_source_root()
    return self._source_root
end

---Returns whether the underlying registration still exists.
---@return boolean
function TooltipTargetAdapter:is_current()
    return self._is_current()
end

---Returns the underlying target's current unvalidated tooltip value.
---@return any
function TooltipTargetAdapter:get_tooltip()
    return self._get_tooltip()
end

---Delivers an optional pointer-enter transition.
---@param x integer|nil
---@param y integer|nil
function TooltipTargetAdapter:on_pointer_enter(x, y)
    if self._on_pointer_enter then self._on_pointer_enter(x, y) end
end

---Delivers an optional pointer-update transition.
---@param x integer|nil
---@param y integer|nil
function TooltipTargetAdapter:on_pointer_update(x, y)
    if self._on_pointer_update then self._on_pointer_update(x, y) end
end

---Delivers an optional pointer-leave transition.
function TooltipTargetAdapter:on_pointer_leave()
    if self._on_pointer_leave then self._on_pointer_leave() end
end

---Returns whether a value is a normalized tooltip target adapter.
---@param value any
---@return boolean
function is_adapter(value)
    return getmetatable(value) == TooltipTargetAdapter
end

---Adapts a registered widget while preserving its callback receiver semantics.
---@param widget gui.View
---@param source_root gui.View
---@param registrations table<gui.View, table>
---@return dwarfui.TooltipTargetAdapter
function adapt_widget(widget, source_root, registrations)
    assert(type(widget) == 'table',
        'DwarfUI widget tooltip adapter requires a widget.')
    assert(type(registrations) == 'table',
        'DwarfUI widget tooltip adapter requires registrations.')
    return TooltipTargetAdapter.new{
        identity=widget,
        kind=TooltipTargetKind.WIDGET,
        source_root=source_root,
        is_current=function()
            return registrations[widget] ~= nil
        end,
        get_tooltip=function()
            return widget.tooltip
        end,
        on_pointer_enter=widget.on_pointer_enter and function(x, y)
            widget.on_pointer_enter(widget, x, y)
        end or nil,
        on_pointer_update=widget.on_pointer_update and function(x, y)
            widget.on_pointer_update(widget, x, y)
        end or nil,
        on_pointer_leave=widget.on_pointer_leave and function()
            widget.on_pointer_leave(widget)
        end or nil,
    }
end

---Adapts an exact map candidate without adding view behavior to its handle.
---@param candidate dwarfui.MapTileTargetObservation
---@param registry dwarfui.TooltipMapTargetRegistry
---@return dwarfui.TooltipTargetAdapter
function adapt_map_tile(candidate, registry)
    assert(type(candidate) == 'table' and
            candidate.kind == TooltipPointerObservationKind.TARGET,
        'DwarfUI map tooltip adapter requires a target candidate.')
    assert(type(registry) == 'table',
        'DwarfUI map tooltip adapter requires a registry.')
    local handle = candidate.identity
    return TooltipTargetAdapter.new{
        identity=handle,
        kind=TooltipTargetKind.MAP_TILE,
        source_root=candidate.source_root,
        is_current=function()
            return registry:contains(handle)
        end,
        get_tooltip=function()
            return registry:get_tooltip(handle)
        end,
    }
end
