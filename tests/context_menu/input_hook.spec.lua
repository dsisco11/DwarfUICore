local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local MODULE_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/input_hook.lua'

---Loads one hook generation over a shared process and overlay.
---@param process table
---@param overlay table
---@return table
local function load_hook(process, overlay)
    local _, immutable_enum = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
    local _, function_chain = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/utils/function_chain.lua')
    local _, module = module_loader.load(repo_root, MODULE_PATH, {
        globals={dfhack=process},
        reqscript={
            ['dwarfuicore/utils/function_chain']=function_chain,
            ['dwarfuicore/utils/immutable_enum']=immutable_enum,
        },
        require_modules={['plugins.overlay']=overlay},
    })
    return module
end

describe('context-menu input hook', function()
    it('consumes a handled native table and preserves miss returns exactly',
            function()
        local calls = {}
        local overlay = {
            feed_viewscreen_widgets=function(viewscreen_name, viewscreen,
                    keys, marker)
                table.insert(calls, {
                    viewscreen_name=viewscreen_name,
                    viewscreen=viewscreen,
                    keys=keys,
                    marker=marker,
                })
                return 'first', nil, 'third'
            end,
        }
        local module = load_hook({dwarfuicore={}}, overlay)
        module.manager:set_handler(function(keys)
            return keys._MOUSE_R
        end)
        module.manager:ensure_native()

        local viewscreen = {}
        local handled = {_MOUSE_R=true, CUSTOM=true}
        assert.is_true(overlay.feed_viewscreen_widgets(
            'dwarfmode', viewscreen, handled, 'handled marker'))
        assert.equals(0, #calls)
        local missed = {CUSTOM=true}
        local first, second, third =
            overlay.feed_viewscreen_widgets(
                'dwarfmode', viewscreen, missed, 'miss marker')
        assert.equals('first', first)
        assert.is_nil(second)
        assert.equals('third', third)
        assert.same({
            viewscreen_name='dwarfmode',
            viewscreen=viewscreen,
            keys=missed,
            marker='miss marker',
        }, calls[1])
    end)

    it('wraps Lua screens reversibly and leaves inherited methods inherited',
            function()
        local overlay = {feed_viewscreen_widgets=function() end}
        local module = load_hook({dwarfuicore={}}, overlay)
        local class = {
            onInput=function(_, keys)
                return 'delegate', keys
            end,
        }
        class.__index = class
        local screen = setmetatable({_native={}}, class)
        module.manager:set_handler(function(keys)
            return keys._MOUSE_R
        end)
        assert.is_true(module.manager:ensure_screen(screen))
        assert.is_not_nil(rawget(screen, 'onInput'))
        assert.is_true(screen:onInput({_MOUSE_R=true}))
        local delegated, keys = screen:onInput({CUSTOM=true})
        assert.equals('delegate', delegated)
        assert.is_true(keys.CUSTOM)

        assert.is_true(module.manager:shutdown())
        assert.is_nil(rawget(screen, 'onInput'))
        assert.equals('delegate', screen:onInput({CUSTOM=true}))
    end)

    it('reconciles native and Lua roots without target-eligibility filtering',
            function()
        local overlay = {feed_viewscreen_widgets=function() end}
        local module = load_hook({dwarfuicore={}}, overlay)
        local screen = {_native={}, onInput=function() return false end}
        local overlay_root = {}

        assert.is_true(module.manager:reconcile_roots({
            [screen]=true,
            [overlay_root]=true,
        }))
        local diagnostics = module.manager:get_diagnostics()
        assert.is_true(diagnostics.native_tracked)
        assert.equals(1, diagnostics.screen_hook_count)

        assert.is_true(module.manager:reconcile_roots({}))
        diagnostics = module.manager:get_diagnostics()
        assert.is_false(diagnostics.native_tracked)
        assert.equals(0, diagnostics.screen_hook_count)
    end)

    it('destructively replaces owned trampolines across module reload',
            function()
        local process = {dwarfuicore={}}
        local predecessor_count = 0
        local overlay = {
            feed_viewscreen_widgets=function()
                predecessor_count = predecessor_count + 1
            end,
        }
        local first = load_hook(process, overlay)
        first.manager:ensure_native()
        local trampoline = overlay.feed_viewscreen_widgets

        local second = load_hook(process, overlay)
        assert.is_not_equal(trampoline, overlay.feed_viewscreen_widgets)
        assert.equals(0, second.manager:get_diagnostics().dispatch_count)
        second.manager:set_handler(function() return true end)
        assert.is_true(second.manager:ensure_native())
        assert.is_not_equal(trampoline, overlay.feed_viewscreen_widgets)
        assert.is_true(overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {_MOUSE_R=true}))
        assert.equals(0, predecessor_count)
    end)

    it('preserves a foreign outer wrapper and leaves its old trampoline inert',
            function()
        local overlay = {feed_viewscreen_widgets=function() return 'base' end}
        local module = load_hook({dwarfuicore={}}, overlay)
        module.manager:set_handler(function() return true end)
        module.manager:ensure_native()
        local dwarfui_trampoline = overlay.feed_viewscreen_widgets
        overlay.feed_viewscreen_widgets=function(...)
            return dwarfui_trampoline(...)
        end
        local foreign = overlay.feed_viewscreen_widgets

        assert.is_false(module.manager:shutdown())
        assert.is_equal(foreign, overlay.feed_viewscreen_widgets)
        assert.equals('base', overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {_MOUSE_R=true}))
        assert.equals(1,
            module.manager:get_diagnostics().inert_superseded_hook_count)
    end)

    it('preserves a foreign screen wrapper during retirement', function()
        local overlay = {feed_viewscreen_widgets=function() end}
        local module = load_hook({dwarfuicore={}}, overlay)
        local screen = {
            _native={},
            onInput=function() return 'base' end,
        }
        module.manager:set_handler(function() return true end)
        module.manager:ensure_screen(screen)
        local dwarfui_trampoline = screen.onInput
        screen.onInput=function(...)
            return dwarfui_trampoline(...)
        end
        local foreign = screen.onInput

        assert.is_false(module.manager:reconcile_roots({}))
        assert.is_equal(foreign, screen.onInput)
        assert.equals('base', screen:onInput({_MOUSE_R=true}))
        assert.equals(1,
            module.manager:get_diagnostics().inert_superseded_hook_count)
    end)

    it('contains unexpected handler failures and becomes transparent',
            function()
        local predecessor_count = 0
        local printed = {}
        local process = {
            dwarfuicore={},
            printerr=function(message) table.insert(printed, message) end,
        }
        local overlay = {
            feed_viewscreen_widgets=function()
                predecessor_count = predecessor_count + 1
                return 'delegated'
            end,
        }
        local module = load_hook(process, overlay)
        local observed
        module.manager:set_failure_handler(function(message)
            observed = message
        end)
        module.manager:set_handler(function() error('hook exploded') end)
        module.manager:ensure_native()

        assert.equals('delegated',
            overlay.feed_viewscreen_widgets(
                'dwarfmode', {}, {_MOUSE_R=true}))
        assert.equals(1, predecessor_count)
        assert.is_truthy(observed:find('hook exploded', 1, true))
        assert.equals(1, #printed)
        assert.is_true(module.manager:get_diagnostics().disabled)
        assert.equals('delegated',
            overlay.feed_viewscreen_widgets(
                'dwarfmode', {}, {_MOUSE_R=true}))
        assert.equals(2, predecessor_count)
    end)
end)
