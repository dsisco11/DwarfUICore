local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads the root collector against one controllable host surface.
---@param state? table
---@return table collector
---@return table state
local function load_collector(state)
    state = state or {}
    local overlay = {get_state=function() return state.overlay_state end,
        isOverlayEnabled=function(name) return state.enabled[name] end}
    local _, collector = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/input_event/ui_root_collector.lua', {
            globals={dfhack={gui={getDFViewscreen=function()
                    return state.native
                end}}}, require_modules={['plugins.overlay']=overlay},
            reqscript={}})
    return collector.InputEventUiRootCollector, state
end

describe('Input Event UI root collection', function()
    it('deduplicates native, current, overlay, and Core roots', function()
        local native, overlay_root, current, extra = {}, {}, {}, {}
        local collector = load_collector({native={widgets=native},
            enabled={one=true}, overlay_state={db={one={widget=overlay_root}}}})
        local roots = collector.collect(current, {native, overlay_root, extra,
            current, extra})
        assert.same({native, current, overlay_root, extra}, roots)
    end)

    it('fails closed for unavailable native or malformed overlay state', function()
        local collector = load_collector({native=nil, enabled={},
            overlay_state={db={}}})
        assert.is_nil(collector.collect({}, {}))
        collector = load_collector({native={widgets={}}, enabled={},
            overlay_state=nil})
        assert.is_nil(collector.collect({}, {}))
        collector = load_collector({native={widgets={}}, enabled={bad=true},
            overlay_state={db={bad={}}}})
        assert.is_nil(collector.collect({}, {}))
    end)

    it('skips disabled overlay roots', function()
        local native, current, enabled_root, disabled_root = {}, {}, {}, {}
        local collector = load_collector({native={widgets=native},
            enabled={enabled=true, disabled=false}, overlay_state={db={
                enabled={widget=enabled_root},
                disabled={widget=disabled_root},
            }}})
        assert.same({native, current, enabled_root},
            collector.collect(current, {}))
    end)

end)
