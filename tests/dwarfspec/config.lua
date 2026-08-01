-- DwarfUICore tooltip live-test settings and diagnostic commands.

---Copies one screen-hook diagnostic without exposing its owner instance.
---@param screen table
---@return table
local function snapshot_screen_hook(screen)
    return {
        tracked=screen.tracked,
        installed=screen.installed,
        outermost=screen.outermost,
        generation=screen.generation,
        repair_count=screen.repair_count,
        chained=screen.chained,
        replaced_method=screen.replaced_method,
        method_replacement_pending=screen.method_replacement_pending,
        method_replacement_count=screen.method_replacement_count,
        owner_had_raw_method=screen.owner_had_raw_method,
        selected=screen.selected,
        owner_present=screen.owner ~= nil,
    }
end

---Copies render-hook diagnostics without returning mutable owner/module tables.
---@param diagnostics table
---@return table
local function snapshot_render_hook(diagnostics)
    local screens = {}
    for index, screen in ipairs(diagnostics.screens or {}) do
        screens[index] = snapshot_screen_hook(screen)
    end
    local overlay = diagnostics.overlay or {}
    local failure = diagnostics.last_failure
    return {
        api_version=diagnostics.api_version,
        generation=diagnostics.generation,
        presenter_installed=diagnostics.presenter_installed,
        disabled_generation=diagnostics.disabled_generation,
        disabled=diagnostics.disabled,
        current_intent_revision=diagnostics.current_intent_revision,
        failure_count=diagnostics.failure_count,
        last_failure=failure and {
            generation=failure.generation,
            revision=failure.revision,
            transport=failure.transport,
            owner_present=failure.owner ~= nil,
            error=failure.error,
        } or nil,
        inactive_intent=diagnostics.inactive_intent,
        selected_transport=diagnostics.selected_transport,
        selected_owner_present=diagnostics.selected_owner ~= nil,
        render_count=diagnostics.render_count,
        last_rendered_revision=diagnostics.last_rendered_revision,
        last_transport=diagnostics.last_transport,
        last_error=diagnostics.last_error,
        overlay={
            owner_present=overlay.owner ~= nil,
            tracked=overlay.tracked,
            installed=overlay.installed,
            outermost=overlay.outermost,
            generation=overlay.generation,
            repair_count=overlay.repair_count,
            chained=overlay.chained,
            replaced_module=overlay.replaced_module,
            module_replacement_pending=overlay.module_replacement_pending,
            module_replacement_count=overlay.module_replacement_count,
            replaced_method=overlay.replaced_method,
            method_replacement_pending=overlay.method_replacement_pending,
            method_replacement_count=overlay.method_replacement_count,
        },
        screens=screens,
        screen_hook_count=diagnostics.screen_hook_count,
    }
end

---Copies presenter diagnostics without returning its selected owner instance.
---@param diagnostics table
---@return table
local function snapshot_presenter(diagnostics)
    return {
        generation=diagnostics.generation,
        active=diagnostics.active,
        current_intent_revision=diagnostics.current_intent_revision,
        service_revision=diagnostics.service_revision,
        selected_transport=diagnostics.selected_transport,
        selected_owner_present=diagnostics.selected_owner ~= nil,
        supported_surface=diagnostics.supported_surface,
        surface_reason=diagnostics.surface_reason,
        last_rendered_revision=diagnostics.last_rendered_revision,
        last_screen_width=diagnostics.last_screen_width,
        last_screen_height=diagnostics.last_screen_height,
        render_count=diagnostics.render_count,
        redraw_count=diagnostics.redraw_count,
    }
end

---Returns current input, presenter, and sanitized render-hook diagnostics.
---@return table
local function tooltip_diagnostics()
    local tooltip = reqscript('dwarfuicore/tooltip/api')
    local render_hook = reqscript('dwarfuicore/tooltip/render_hook')
    local result = tooltip.get_diagnostics()
    result.presenter = snapshot_presenter(result.presentation)
    result.presentation = nil
    result.render_hook = snapshot_render_hook(
        render_hook.manager:get_diagnostics())
    return result
end

return {
    settings={wait={frame_budget=300, timeout_ms=10000}},
    commands={tooltip_state=tooltip_diagnostics},
}
