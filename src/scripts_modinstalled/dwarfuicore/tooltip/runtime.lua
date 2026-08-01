--@ module=true

-- Process-wide tooltip presentation assembly and startup.

local gui = require('gui')
local presenter_module = reqscript('dwarfuicore/tooltip/presenter')
local renderer_module = reqscript('dwarfuicore/tooltip/renderer')
local service_module = reqscript('dwarfuicore/tooltip/service')
local render_hook_module = reqscript('dwarfuicore/tooltip/render_hook')

local RUNTIME_SLOT = 'tooltip_runtime'
dfhack.dwarfuicore = dfhack.dwarfuicore or {}
local runtime_state = dfhack.dwarfuicore.service_provider_runtime
local runtime_generation = runtime_state and runtime_state.generation or 0
local process_state = dfhack.dwarfuicore[RUNTIME_SLOT]
if process_state and runtime_generation > 0 then
    assert(process_state.runtime_generation == runtime_generation,
        'DwarfUICore tooltip presenter belongs to another runtime generation.')
end

---@type dwarfuicore.TooltipPresenter
presenter = process_state and process_state.presenter or nil
if not presenter then
    local constructed = presenter_module.TooltipPresenter.new{
        service=service_module.service,
        hook_manager=render_hook_module.manager,
        renderer=renderer_module.TooltipRenderer{},
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
            return gui.Painter.new{x1=0, y1=0, x2=width - 1, y2=height - 1}
        end,
        invalidate=dfhack.screen.invalidate,
    }
    constructed:start()
    process_state = {runtime_generation=runtime_generation,
        presenter=constructed}
    dfhack.dwarfuicore[RUNTIME_SLOT] = process_state
    presenter = constructed
end
