--@ module=true

-- Test-owned registered overlay for native context-menu interaction coverage.

local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')
local PointerPolicy =
    reqscript('dwarfuicore/pointer').PointerPolicy

local PROCESS_STATE_SLOT = 'context_menu_component_probe'

---@class tests.ContextMenuRegistrationOverlay: plugins.overlay.OverlayWidget
local ContextMenuRegistrationOverlay =
    defclass(nil, overlay.OverlayWidget)
ContextMenuRegistrationOverlay.ATTRS{
    default_enabled=true,
    default_pos={x=1, y=6},
    desc='DwarfUICore context-menu registration probe',
    frame={w=24, h=6},
    viewscreens='dwarfmode',
}

---Returns the process-persistent observation state for this probe.
---@return table
local function process_state()
    dfhack.dwarfuicore[PROCESS_STATE_SLOT] =
        dfhack.dwarfuicore[PROCESS_STATE_SLOT] or {
            inputs={},
            selection_count=0,
            selection_context=nil,
        }
    return dfhack.dwarfuicore[PROCESS_STATE_SLOT]
end

---Builds and registers the rendered context-menu target.
function ContextMenuRegistrationOverlay:init()
    self.context_target = widgets.Panel{
        view_id='context_target',
        pointer_policy=PointerPolicy.TARGET,
        frame={l=1, t=1, w=18, h=3},
        subviews={
            widgets.Label{
                frame={l=1, t=1},
                text='Context target',
            },
        },
    }
    self:addviews{self.context_target}
    self.definition = {
        title='Native actions',
        fg=COLOR_LIGHTCYAN,
        bg=COLOR_BLUE,
        entries={
            {
                label='Primary action',
                on_select=function(context)
                    local state = process_state()
                    state.selection_count = state.selection_count + 1
                    state.selection_context = context
                end,
            },
            {
                label='Colored action',
                fg=COLOR_LIGHTRED,
                bg=COLOR_BLACK,
                on_select=function(context)
                    local state = process_state()
                    state.selection_count = state.selection_count + 1
                    state.selection_context = context
                end,
            },
        },
    }
    local state = process_state()
    state.context_target = self.context_target
end

---Records every input table that reaches the backing overlay.
---@param keys table
---@return boolean
function ContextMenuRegistrationOverlay:onInput(keys)
    local copied = {}
    for key, value in pairs(keys) do copied[key] = value end
    table.insert(process_state().inputs, copied)
    return false
end

---Drops the test-owned registration before overlay teardown.
function ContextMenuRegistrationOverlay.overlay_ondisable()
    local state = process_state()
    if state.context_target then
        reqscript('dwarfuicore').services.ContextMenuServiceProvider:new(
            1, 'test-context-overlay'):unregister(state.context_target)
        state.context_target = nil
    end
end

OVERLAY_WIDGETS = {
    context_menu_probe=ContextMenuRegistrationOverlay,
}

return _ENV
