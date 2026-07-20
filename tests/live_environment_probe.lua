-- Run through `dfhack-run lua -f` to characterize the active live environment.

print(('DFHack=%s world=%s map=%s'):format(
    dfhack.getDFHackVersion(),
    tostring(dfhack.isWorldLoaded()),
    tostring(dfhack.isMapLoaded())))
print('focus=' .. table.concat(dfhack.gui.getCurFocus(true), ','))

local ok, result = pcall(reqscript, 'dwarfui/tooltip')
print(('dwarfui_tooltip=%s result=%s'):format(
    tostring(ok), tostring(result)))
print('dwarfui_tooltip_path=' ..
    tostring(dfhack.findScript('dwarfui/tooltip')))
print('dwarfui_register=' .. tostring(ok and result.register))
print('dwarfui_renderer=' .. tostring(ok and result.TooltipRenderer))
print('dwarfui_agent=' .. tostring(ok and result.TooltipAgent))
