--@ module=true

-- Process-wide tooltip presentation assembly and startup.

local gui = require('gui')
local presenter_module = reqscript('dwarfui/tooltip/presenter')
local renderer_module = reqscript('dwarfui/tooltip/renderer')
local service_module = reqscript('dwarfui/tooltip/service')
local render_hook_module = reqscript('dwarfui/tooltip/render_hook')

---@type dwarfui.TooltipPresenter
presenter = presenter_module.TooltipPresenter.new{
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
