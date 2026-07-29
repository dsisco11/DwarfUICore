local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local MODULE_PATH =
    'src/scripts_modinstalled/dwarfui/tooltip_render_hook.lua'

local function load_hook(process, overlay_provider)
    local _, module = module_loader.load(repo_root, MODULE_PATH, {
        globals={dfhack=process},
        require_modules=setmetatable({}, {
            __index=function(_, name)
                assert.equals('plugins.overlay', name)
                return overlay_provider()
            end,
        }),
    })
    return module
end

local function overlay_with(renderer)
    return {render_viewscreen_widgets=renderer}
end

describe('DwarfUI tooltip render-hook manager', function()
    it('calls the overlay predecessor first and preserves all returns',
            function()
        local events = {}
        local overlay = overlay_with(function(first, second)
            table.insert(events, 'predecessor:' .. first .. second)
            return 'result', nil, 3
        end)
        local module = load_hook({dwarfui={}}, function() return overlay end)
        module.manager:set_presenter(function(transport, owner)
            assert.equals(
                module.TooltipRenderTransport.OVERLAY, transport)
            assert.is_equal(overlay, owner)
            table.insert(events, 'presenter')
        end)

        assert.is_true(module.manager:ensure_overlay())
        local packed = table.pack(
            overlay.render_viewscreen_widgets('a', 'b'))

        assert.same({'predecessor:ab', 'presenter'}, events)
        assert.equals(3, packed.n)
        assert.equals('result', packed[1])
        assert.is_nil(packed[2])
        assert.equals(3, packed[3])
        assert.equals(1, module.manager:get_diagnostics().render_count)
    end)

    it('installs idempotently and adopts its hook on module reload',
            function()
        local process = {dwarfui={}}
        local calls = 0
        local overlay = overlay_with(function() end)
        local first = load_hook(process, function() return overlay end)
        first.manager:set_presenter(function() calls = calls + 1 end)
        assert.is_true(first.manager:ensure_overlay())
        local trampoline = overlay.render_viewscreen_widgets
        local first_generation = first.manager:get_diagnostics().generation
        assert.is_false(first.manager:ensure_overlay())

        local second = load_hook(process, function() return overlay end)
        assert.equals(first_generation + 1,
            second.manager:get_diagnostics().generation)
        second.manager:set_presenter(function() calls = calls + 1 end)
        assert.is_false(second.manager:ensure_overlay())
        assert.is_equal(trampoline, overlay.render_viewscreen_widgets)

        overlay.render_viewscreen_widgets()
        assert.equals(1, calls)
    end)

    it('adopts a screen hook on reload without double presentation',
            function()
        local process = {dwarfui={}}
        local screen = {onRender=function() end}
        local calls = 0
        local provider = function()
            return overlay_with(function() end)
        end
        local first = load_hook(process, provider)
        first.manager:set_presenter(function() calls = calls + 1 end)
        assert.is_true(first.manager:ensure_screen(screen))
        local trampoline = screen.onRender
        local first_generation = first.manager:get_diagnostics().generation

        local second = load_hook(process, provider)
        second.manager:set_presenter(function() calls = calls + 1 end)
        assert.is_false(second.manager:ensure_screen(screen))
        assert.is_equal(trampoline, screen.onRender)
        assert.equals(first_generation + 1,
            second.manager:get_diagnostics().generation)

        screen:onRender()
        assert.equals(1, calls)
    end)

    it('repairs around external overlay wrappers and module replacement',
            function()
        local events = {}
        local original = function() table.insert(events, 'original') end
        local first_overlay = overlay_with(original)
        local current_overlay = first_overlay
        local module = load_hook({dwarfui={}},
            function() return current_overlay end)
        module.manager:set_presenter(
            function() table.insert(events, 'presenter') end)
        module.manager:ensure_overlay()

        local dwarfui_inner = first_overlay.render_viewscreen_widgets
        first_overlay.render_viewscreen_widgets = function(...)
            table.insert(events, 'foreign')
            return dwarfui_inner(...)
        end
        assert.is_true(module.manager:ensure_overlay())
        first_overlay.render_viewscreen_widgets()
        assert.same({'foreign', 'original', 'presenter'}, events)
        assert.equals(1,
            module.manager:get_diagnostics().overlay.repair_count)

        events = {}
        current_overlay = overlay_with(
            function() table.insert(events, 'replacement') end)
        assert.is_true(module.manager:ensure_overlay())
        current_overlay.render_viewscreen_widgets()
        assert.same({'replacement', 'presenter'}, events)
        assert.is_equal(current_overlay,
            module.manager:get_diagnostics().overlay.owner)
    end)

    it('wraps, repairs, and conditionally restores a screen method',
            function()
        local events = {}
        local class = {
            onRender=function(self, value)
                table.insert(events, 'inherited:' .. value)
                return 'screen-result', nil
            end,
        }
        local screen = setmetatable({}, {__index=class})
        local module = load_hook({dwarfui={}},
            function() return overlay_with(function() end) end)
        module.manager:set_presenter(function(transport, owner)
            assert.equals(
                module.TooltipRenderTransport.SCREEN, transport)
            assert.is_equal(screen, owner)
            table.insert(events, 'presenter')
        end)

        assert.is_true(module.manager:ensure_screen(screen))
        assert.is_false(module.manager:ensure_screen(screen))
        local returns = table.pack(screen:onRender('one'))
        assert.same({'inherited:one', 'presenter'}, events)
        assert.equals(2, returns.n)
        assert.equals('screen-result', returns[1])
        assert.is_nil(returns[2])

        local dwarfui_inner = rawget(screen, 'onRender')
        rawset(screen, 'onRender', function(...)
            table.insert(events, 'foreign')
            return dwarfui_inner(...)
        end)
        assert.is_true(module.manager:ensure_screen(screen))
        events = {}
        screen:onRender('two')
        assert.same({'foreign', 'inherited:two', 'presenter'}, events)
        assert.is_false(module.manager:get_diagnostics().
            selected_screen.owner_had_raw_method)

        assert.is_true(module.manager:shutdown())
        assert.is_not_nil(rawget(screen, 'onRender'))
        events = {}
        screen:onRender('three')
        assert.same({'foreign', 'inherited:three'}, events)
    end)

    it('clears an initially inherited method on shutdown', function()
        local inherited = function() return 'inherited' end
        local screen = setmetatable({}, {__index={onRender=inherited}})
        local module = load_hook({dwarfui={}},
            function() return overlay_with(function() end) end)

        module.manager:ensure_screen(screen)
        assert.is_true(module.manager:shutdown())
        assert.is_nil(rawget(screen, 'onRender'))
        assert.is_equal(inherited, screen.onRender)
    end)

    it('restores an initially raw method exactly on shutdown', function()
        local raw_method = function() return 'raw' end
        local screen = {onRender=raw_method}
        local module = load_hook({dwarfui={}},
            function() return overlay_with(function() end) end)

        module.manager:ensure_screen(screen)
        assert.is_true(module.manager:shutdown())
        assert.is_equal(raw_method, rawget(screen, 'onRender'))
    end)

    it('restores the overlay predecessor when still outermost', function()
        local predecessor = function() return 'overlay' end
        local overlay = overlay_with(predecessor)
        local module = load_hook({dwarfui={}}, function() return overlay end)

        module.manager:ensure_overlay()
        assert.is_true(module.manager:shutdown())
        assert.is_equal(
            predecessor, overlay.render_viewscreen_widgets)
    end)

    it('allows only the selected owner active trampoline to present',
            function()
        local calls = {}
        local first = {onRender=function() end}
        local second = {onRender=function() end}
        local module = load_hook({dwarfui={}},
            function() return overlay_with(function() end) end)
        module.manager:set_presenter(function(_, owner)
            table.insert(calls, owner)
        end)

        module.manager:ensure_screen(first)
        local first_hook = first.onRender
        module.manager:ensure_screen(second)
        first_hook()
        second.onRender()
        assert.same({second}, calls)
    end)

    it('does not overwrite foreign outer wrappers during shutdown',
            function()
        local original = function() return 'original' end
        local overlay = overlay_with(original)
        local screen = {onRender=original}
        local module = load_hook({dwarfui={}}, function() return overlay end)
        module.manager:ensure_overlay()
        local overlay_hook = overlay.render_viewscreen_widgets
        overlay.render_viewscreen_widgets =
            function(...) return overlay_hook(...) end
        module.manager:ensure_screen(screen)
        local screen_hook = screen.onRender
        screen.onRender = function(...) return screen_hook(...) end
        local foreign_overlay = overlay.render_viewscreen_widgets
        local foreign_screen = screen.onRender

        assert.is_false(module.manager:shutdown())
        assert.is_equal(foreign_overlay, overlay.render_viewscreen_widgets)
        assert.is_equal(foreign_screen, screen.onRender)
    end)

    it('reports transport ownership, generation, outermost, and repairs',
            function()
        local overlay = overlay_with(function() end)
        local module = load_hook({dwarfui={}}, function() return overlay end)
        module.manager:set_presenter(function() end)
        module.manager:ensure_overlay()
        local diagnostics = module.manager:get_diagnostics()
        assert.equals(1, diagnostics.api_version)
        assert.equals(module.TooltipRenderTransport.OVERLAY,
            diagnostics.selected_transport)
        assert.is_equal(overlay, diagnostics.selected_owner)
        assert.is_true(diagnostics.presenter_installed)
        assert.is_true(diagnostics.overlay.installed)
        assert.is_true(diagnostics.overlay.outermost)
        assert.equals(diagnostics.generation,
            diagnostics.overlay.generation)
        assert.equals(0, diagnostics.overlay.repair_count)

        local inner = overlay.render_viewscreen_widgets
        overlay.render_viewscreen_widgets = function(...)
            return inner(...)
        end
        diagnostics = module.manager:get_diagnostics()
        assert.is_false(diagnostics.overlay.outermost)
        module.manager:ensure_overlay()
        diagnostics = module.manager:get_diagnostics()
        assert.is_true(diagnostics.overlay.outermost)
        assert.equals(1, diagnostics.overlay.repair_count)
    end)

    it('reports every retained screen hook after selection transfer',
            function()
        local first = {onRender=function() end}
        local second = {onRender=function() end}
        local module = load_hook({dwarfui={}},
            function() return overlay_with(function() end) end)
        module.manager:ensure_screen(first)
        module.manager:ensure_screen(second)

        local diagnostics = module.manager:get_diagnostics()
        assert.equals(2, diagnostics.screen_hook_count)
        assert.equals(2, #diagnostics.screens)
        local by_owner = {}
        for _, screen in ipairs(diagnostics.screens) do
            by_owner[screen.owner] = screen
        end
        assert.is_false(by_owner[first].selected)
        assert.is_true(by_owner[first].outermost)
        assert.equals(0, by_owner[first].repair_count)
        assert.is_true(by_owner[second].selected)
        assert.is_equal(by_owner[second], diagnostics.selected_screen)

        module.manager:clear_selection()
        diagnostics = module.manager:get_diagnostics()
        assert.is_nil(diagnostics.selected_screen)
        assert.equals(2, #diagnostics.screens)
    end)

    it('does not retain dismissed screen owners in weak diagnostics',
            function()
        local process = {dwarfui={}}
        local module = load_hook(process,
            function() return overlay_with(function() end) end)
        module.manager:set_presenter(function() end)
        local weak_owner = setmetatable({}, {__mode='v'})
        do
            local screen = {onRender=function() end}
            weak_owner[1] = screen
            module.manager:ensure_screen(screen)
            screen:onRender()
        end
        module.manager:clear_selection()

        collectgarbage('collect')
        collectgarbage('collect')

        assert.is_nil(weak_owner[1])
        assert.equals(0,
            module.manager:get_diagnostics().screen_hook_count)
    end)

    it('rejects incompatible process state versions', function()
        local process = {
            dwarfui={
                tooltip_render_hook={api_version=999},
            },
        }
        assert.has_error(function()
            load_hook(process,
                function() return overlay_with(function() end) end)
        end, 'Conflicting DwarfUI tooltip render-hook versions: ' ..
            'process has 999, requested 1.')
    end)
end)
