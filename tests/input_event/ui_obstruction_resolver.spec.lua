local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads the obstruction resolver with deterministic classification results.
---@param outcomes table
---@return table resolver
local function load_resolver(outcomes)
    local pointer = {
        PointerClassificationKind={TARGET=1, BLOCKED=2, MISS=3, UNKNOWN=4},
        PointerObstructionClassifier={
            invoke=function(_, root)
                local result = outcomes[root]
                if result == 'error' then return {kind=4} end
                return {kind=result}
            end,
        },
    }
    local ui_root_collector = {
        UiRootKind={
            NATIVE_WIDGET_TREE=1,
            LUA_VIEW=2,
            OVERLAY_VIEW=3,
            CORE_REGISTERED_VIEW=4,
        },
    }
    local _, resolver = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/input_event/ui_obstruction_resolver.lua', {
            require_modules={['plugins.overlay']={
                get_state=function() return {db={}} end,
                isOverlayEnabled=function() return false end,
                normalize_list=function(value) return value end,
                simplify_viewscreen_name=function(value) return value end,
            }},
            reqscript={
                ['dwarfuicore/pointer']=pointer,
                ['dwarfuicore/input_event/ui_root_collector']=ui_root_collector,
                ['dwarfuicore/input_event/gui_view_pointer_obstruction_classifier']={},
                ['dwarfuicore/input_event/native_ui_pointer_obstruction_classifier']={},
            }})
    return resolver.InputEventUiObstructionResolver
end

local function desc(kind, root)
    return {kind=kind, root=root}
end

describe('Input Event UI obstruction resolution', function()
    local NATIVE = 1
    local LUA = 2
    local OVERLAY = 3
    local CORE = 4

    it('permits MAP input only when every explicit root misses', function()
        local first, second, third, fourth = {}, {}, {}, {}
        local resolver = load_resolver({
            [first]=3,
            [second]=3,
            [third]=3,
            [fourth]=3,
        })
        assert.is_true(resolver.is_unobstructed({
            desc(NATIVE, first),
            desc(LUA, second),
            desc(OVERLAY, third),
            desc(CORE, fourth),
        }, {x=1, y=2}))
    end)

    it('suppresses MAP when native or lua views block, or unknown is reported', function()
        local root = {}
        for _, kind in ipairs({1, 2, 4}) do
            local outcomes = {[root]=kind}
            local resolver = load_resolver(outcomes)
            assert.is_false(resolver.is_unobstructed({desc(1, root)}, {x=1, y=2}),
                'blocked result ' .. tostring(kind))
        end
    end)

    it('suppresses MAP on malformed descriptors and collection failures', function()
        local root = {}
        local resolver = load_resolver({[root]=3})
        assert.is_false(resolver.is_unobstructed(nil, {x=1, y=2}))
        assert.is_false(resolver.is_unobstructed({desc(99, root)}, {x=1, y=2}))
        assert.is_false(resolver.is_unobstructed({desc(LUA, root)}, nil))
    end)

    it('suppresses MAP for native classifier failures', function()
        local first, second = {}, {}
        local resolver = load_resolver({[first]=3, [second]='error'})
        assert.is_false(resolver.is_unobstructed(
            {desc(1, first), desc(1, second)}, {x=1, y=2}))
    end)

end)
