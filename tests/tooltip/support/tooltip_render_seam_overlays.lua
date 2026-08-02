--@ module=true

-- Test-owned overlays for characterizing the native final-render seam.

local gui = require('gui')
local overlay = require('plugins.overlay')

local PROBE_X = 2
local PROBE_Y = 2
local PROCESS_STATE_SLOT = 'tooltip_final_render_probe'

---Paints one screen-global sentinel during an overlay render.
---@param _dc gui.Painter
---@param character string
---@param background integer
local function paint_sentinel(_dc, character, background)
local process = dfhack.dwarfuicore and
    dfhack.dwarfuicore[PROCESS_STATE_SLOT] or nil
    if process and process.enabled == false then return end
    local x = process and process.x or PROBE_X
    local y = process and process.y or PROBE_Y
    gui.Painter.new():seek(x, y):char(character, {
        fg=COLOR_WHITE,
        bg=background,
    })
    if process then
        process.overlay_paint_order =
            process.overlay_paint_order or {}
        table.insert(process.overlay_paint_order, character)
    end
end

---@class tests.TooltipRenderViewscreenOverlay:
---    plugins.overlay.OverlayWidget
local TooltipRenderViewscreenOverlay =
    defclass(nil, overlay.OverlayWidget)
TooltipRenderViewscreenOverlay.ATTRS{
    default_enabled=true,
    desc='DwarfUICore tooltip viewscreen render-seam probe',
    fullscreen=true,
    viewscreens='dwarfmode',
}

---Records and paints one viewscreen-specific overlay render.
---@param dc gui.Painter
function TooltipRenderViewscreenOverlay:onRenderBody(dc)
    self.render_count = (self.render_count or 0) + 1
    paint_sentinel(dc, 'V', COLOR_RED)
end

---@class tests.TooltipRenderAllOverlay: plugins.overlay.OverlayWidget
local TooltipRenderAllOverlay = defclass(nil, overlay.OverlayWidget)
TooltipRenderAllOverlay.ATTRS{
    default_enabled=true,
    desc='DwarfUICore tooltip all-viewscreens render-seam probe',
    fullscreen=true,
    viewscreens='all',
}

---Records and paints one all-viewscreens overlay render.
---@param dc gui.Painter
function TooltipRenderAllOverlay:onRenderBody(dc)
    self.render_count = (self.render_count or 0) + 1
    paint_sentinel(dc, 'A', COLOR_BLUE)
end

OVERLAY_WIDGETS = {
    viewscreen_probe=TooltipRenderViewscreenOverlay,
    all_probe=TooltipRenderAllOverlay,
}

return _ENV
