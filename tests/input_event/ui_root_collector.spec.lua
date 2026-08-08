local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads the root collector against one controllable host surface.
---@param state? table
---@return table collector
local function load_collector(state)
    state = state or {}
    local globals = {dfhack={gui={getDFViewscreen=function()
                return state.native
            end, matchFocusString=function(focus, current)
                local current_focus = current and current.focus or
                    state.overlay_focus
                return focus == current_focus
            end}}}
    local overlay = {get_state=function() return state.overlay_state end,
        isOverlayEnabled=function(name) return state.enabled[name] end,
        normalize_list=function(values)
            if type(values) == 'string' then return {values} end
            if type(values) == 'table' then return values end
            return {}
        end,
        simplify_viewscreen_name=function(value) return value end}
    local _, overlay_compatibility = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/input_event/overlay_feed_compatibility.lua', {
            globals=globals,
            require_modules={['plugins.overlay']=overlay},
            reqscript={},
        })
    local _, collector_module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/input_event/ui_root_collector.lua', {
            globals=globals,
            require_modules={['plugins.overlay']=overlay},
            reqscript={['dwarfuicore/input_event/overlay_feed_compatibility']=
                overlay_compatibility}})
    return collector_module.InputEventUiRootCollector
end

describe('Input Event UI root collection', function()
    it('deduplicates native, current, overlay, and Core roots', function()
        local native, overlay_root, current, extra = {}, {}, {}, {}
        local collector = load_collector({
            native={widgets=native},
            enabled={one=true},
            overlay_state={db={one={widget=overlay_root,
                viewscreens={'all'}}}},
        })
        local roots = collector.collect(current, {overlay_root, extra, current,
            extra})
        assert.equals(4, #roots)
        assert.equals(collector.NATIVE_WIDGET_TREE_KIND, roots[1].kind)
        assert.equals(collector.LUA_VIEW_KIND, roots[2].kind)
        assert.equals(collector.OVERLAY_VIEW_KIND, roots[3].kind)
        assert.equals(collector.CORE_REGISTERED_VIEW_KIND, roots[4].kind)
        assert.same({native, current, overlay_root, extra},
            {roots[1].root, roots[2].root, roots[3].root, roots[4].root})
    end)

    it('deduplicates generic roots by declared-kind precedence', function()
        local native, shared = {}, {}
        local collector = load_collector({
            native={widgets=native},
            enabled={overlay=true},
            overlay_state={db={overlay={widget=shared, viewscreens={'all'}}}},
        })
        local roots = collector.collect(shared, {shared})
        assert.equals(2, #roots)
        assert.equals(collector.OVERLAY_VIEW_KIND, roots[2].kind)
        assert.equals(shared, roots[2].root)
    end)

    it('fails closed for incompatible native and Lua duplicate kinds', function()
        local current = {}
        local collector = load_collector({native={widgets=current},
            enabled={}, overlay_state={db={}}})
        assert.is_nil(collector.collect(current, {}))
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
        local malformed_overlay_roots = collector.collect({}, {})
        assert.equals(2, #malformed_overlay_roots)
    end)

    it('skips disabled overlay roots', function()
        local native, current, enabled_root, disabled_root = {}, {}, {}, {}
        local collector = load_collector({native={widgets=native},
            enabled={enabled=true, disabled=false}, overlay_state={db={
                enabled={widget=enabled_root, viewscreens={'all'}},
                disabled={widget=disabled_root, viewscreens={'all'}},
            }}})
        local roots = collector.collect(current, {})
        assert.equals(3, #roots)
        assert.equals(enabled_root, roots[3].root)
    end)

    it('collects only applicable overlays for current focus context', function()
        local native, current, applicable, excluded = {}, {}, {}, {}
        local state = {
            native={widgets=native},
            overlay_focus='target',
            enabled={applicable=true, excluded=true},
            overlay_state={db={
                applicable={widget=applicable, viewscreens={'target'}},
                excluded={widget=excluded, viewscreens={'other'}},
            }}}
        local collector = load_collector(state)
        local roots = collector.collect(current, {})
        assert.equals(3, #roots)
        assert.equals(applicable, roots[3].root)
        state.overlay_focus = 'other'
        roots = collector.collect(current, {})
        assert.equals(3, #roots)
        assert.equals(excluded, roots[3].root)
    end)

    it('skips malformed overlay entries while collecting other overlays', function()
        local native, current, good_overlay, malformed_overlay = {}, {}, {}, {}
        local collector = load_collector({
            native={widgets=native},
            enabled={good=true, malformed=true},
            overlay_focus='target',
            overlay_state={db={
                good={widget=good_overlay, viewscreens={'target'}},
                malformed={widget=malformed_overlay, viewscreens=7},
            }},
        })
        local roots = collector.collect(current, {})
        assert.equals(3, #roots)
        assert.equals(good_overlay, roots[3].root)
    end)
end)
