local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local MODULE_PATH =
    'src/scripts_modinstalled/dwarfuicore/input_event/input_hook.lua'

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
            ['dwarfuicore/input_event/types']={InputDispatchResult={PASS=1, CONSUME=2}, InputSampleDemandType={SCREEN_POSITION=1, MAP_POSITION=2}},
            ['dwarfuicore/input_event/snapshot_factory']={
                SnapshotFactory={new=function() return {capture_input=function(_, _, _) return {screen_position=nil, map_position=nil} end} end},
                InputDemandTracker={new=function() return {
                    _counts={},
                    acquire=function(self, demand_type)
                        self._counts[demand_type] = (self._counts[demand_type] or 0) + 1
                        return {demand_type=demand_type}
                    end,
                    release=function(self, handle)
                        self._counts[handle.demand_type] = self._counts[handle.demand_type] - 1
                        return true
                    end,
                    get_snapshot=function() return {screen_position=false, map_position=false} end,
                    get_count=function(self, demand_type)
                        return self._counts[demand_type] or 0
                    end,
                } end},
            },
        },
        require_modules={['plugins.overlay']=overlay},
    })
    return module
end

describe('context-menu input hook', function()
    it('passes one snapshot to the private consumer and consumes explicitly',
            function()
        local predecessor_count = 0
        local overlay = {feed_viewscreen_widgets=function()
            predecessor_count = predecessor_count + 1
            return 'base'
        end}
        local module = load_hook({dwarfuicore={}}, overlay)
        local keys = {_MOUSE_R=true}
        local observed_snapshot
        module.manager:set_private_context_consumer(function(input, snapshot)
            assert.is_equal(keys, input)
            observed_snapshot = snapshot
            return 2
        end)
        module.manager:ensure_native()

        assert.is_true(overlay.feed_viewscreen_widgets('dwarfmode', {}, keys))
        assert.is_not_nil(observed_snapshot)
        assert.equals(0, predecessor_count)
    end)

    it('acquires and releases context snapshot demand with its lifecycle',
            function()
        local module = load_hook({dwarfuicore={}}, {
            feed_viewscreen_widgets=function() end,
        })
        module.manager:set_private_context_consumer(function()
            return 1
        end)
        local active = module.manager:get_diagnostics()
        assert.equals(1, active.screen_snapshot_demand)
        assert.equals(1, active.map_snapshot_demand)

        module.manager:set_private_context_consumer(nil)
        local inactive = module.manager:get_diagnostics()
        assert.equals(0, inactive.screen_snapshot_demand)
        assert.equals(0, inactive.map_snapshot_demand)
    end)

    it('re-exports the Input Event manager through the compatibility module',
            function()
        local hook = load_hook({dwarfuicore={}}, {
            feed_viewscreen_widgets=function() end,
        })
        local _, compatibility = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfuicore/context_menu/input_hook.lua', {
                reqscript={
                    ['dwarfuicore/input_event/input_hook']=hook,
                },
            })

        assert.is_equal(hook.manager, compatibility.manager)
    end)

    it('adopts the legacy process state under Input Event ownership', function()
        local legacy_state = {api_version=2, runtime_generation=0}
        local process = {dwarfuicore={
            context_menu_input_hook=legacy_state,
        }}

        load_hook(process, {feed_viewscreen_widgets=function() end})

        assert.is_equal(legacy_state,
            process.dwarfuicore.input_event_input_hook)
    end)

    it('dispatches before native delegation with exact boundary values',
            function()
        local events = {}
        local viewscreen = {}
        local keys = {CUSTOM=true}
        local overlay = {
            feed_viewscreen_widgets=function(name, owner, input, marker)
                table.insert(events, 'predecessor')
                assert.equals('dwarfmode', name)
                assert.is_equal(viewscreen, owner)
                assert.is_equal(keys, input)
                assert.equals('marker', marker)
                return 'first', nil, 'third'
            end,
        }
        local module = load_hook({dwarfuicore={}}, overlay)
        module.manager:set_context_consumer(function(input, transport, owner)
            table.insert(events, 'handler')
            assert.is_equal(keys, input)
            assert.equals(
                module.ContextMenuInputTransport.NATIVE, transport)
            assert.is_equal(overlay, owner)
            return false
        end)
        module.manager:ensure_native()

        local result = table.pack(overlay.feed_viewscreen_widgets(
            'dwarfmode', viewscreen, keys, 'marker'))

        assert.same({'handler', 'predecessor'}, events)
        assert.equals(3, result.n)
        assert.equals('first', result[1])
        assert.is_nil(result[2])
        assert.equals('third', result[3])
    end)

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
        module.manager:set_context_consumer(function(keys)
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
        module.manager:set_context_consumer(function(keys)
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

    it('resolves the exact current tracked screen or native widget root',
            function()
        local native_root = io.stdout
        local native_viewscreen = {widgets=native_root}
        local current = native_viewscreen
        local process = {
            dwarfuicore={},
            gui={
                getCurViewscreen=function() return current end,
                getDFViewscreen=function() return native_viewscreen end,
            },
        }
        local overlay = {feed_viewscreen_widgets=function() end}
        local module = load_hook(process, overlay)

        assert.is_equal(native_root,
            module.manager:resolve_current_surface())
        local prepared = module.manager:prepare_priority_consumer(
            native_root, {
                owns=function() return false end,
                handle=function() return false end,
            })
        assert.is_true(module.manager:release_priority_consumer(prepared))

        local screen_native = {}
        local screen = {_native=screen_native, onInput=function() end}
        module.manager:ensure_screen(screen)
        current = screen_native
        assert.is_equal(screen, module.manager:resolve_current_surface())

        current = {}
        assert.is_nil(module.manager:resolve_current_surface())
    end)

    it('preserves its compatible owner and trampolines across module reload',
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
        assert.is_equal(first.manager, second.manager)
        assert.is_equal(trampoline, overlay.feed_viewscreen_widgets)
        assert.equals(0, second.manager:get_diagnostics().dispatch_count)
        second.manager:set_context_consumer(function() return true end)
        assert.is_false(second.manager:ensure_native())
        assert.is_equal(trampoline, overlay.feed_viewscreen_widgets)
        assert.is_true(overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {_MOUSE_R=true}))
        assert.equals(0, predecessor_count)
    end)

    it('preserves a foreign outer wrapper and leaves its old trampoline inert',
            function()
        local overlay = {feed_viewscreen_widgets=function() return 'base' end}
        local module = load_hook({dwarfuicore={}}, overlay)
        module.manager:set_context_consumer(function() return true end)
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
        module.manager:set_context_consumer(function() return true end)
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

    it('dispatches one prepared priority consumer before context and base',
            function()
        local events = {}
        local overlay = {
            feed_viewscreen_widgets=function()
                table.insert(events, 'predecessor')
                return 'first', nil, 'third'
            end,
        }
        local module = load_hook({dwarfuicore={}}, overlay)
        module.manager:set_context_consumer(function(keys)
            table.insert(events, 'context')
            return keys.CONTEXT == true
        end)
        local prepared = module.manager:prepare_priority_consumer({}, {
            owns=function(keys)
                table.insert(events, 'owns')
                return keys.OWNED == true
            end,
            handle=function(keys)
                table.insert(events, 'priority')
                return keys.HANDLED == true
            end,
        })
        local trampoline = overlay.feed_viewscreen_widgets
        assert.is_true(module.manager:activate_priority_consumer(prepared))
        assert.is_equal(trampoline, overlay.feed_viewscreen_widgets)

        assert.is_true(overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {OWNED=true, HANDLED=true}))
        assert.same({'owns', 'priority'}, events)

        events = {}
        assert.is_true(overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {OWNED=true, CONTEXT=true}))
        assert.same({'owns', 'priority', 'context'}, events)

        events = {}
        local result = table.pack(overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {CUSTOM=true}))
        assert.same({'owns', 'context', 'predecessor'}, events)
        assert.equals(3, result.n)
        assert.equals('first', result[1])
        assert.is_nil(result[2])
        assert.equals('third', result[3])
        assert.same({
            module.InputConsumerKind.PRIORITY,
            module.InputConsumerKind.CONTEXT_MENU,
        }, module.manager:get_diagnostics().consumer_order)
    end)

    it('dispatches the same priority contract through a Lua screen', function()
        local predecessor_count = 0
        local overlay = {feed_viewscreen_widgets=function() end}
        local module = load_hook({dwarfuicore={}}, overlay)
        local screen = {
            _native={},
            onInput=function()
                predecessor_count = predecessor_count + 1
                return 'screen-base'
            end,
        }
        local original = screen.onInput
        module.manager:set_context_consumer(function() return false end)
        local prepared = module.manager:prepare_priority_consumer(screen, {
            owns=function(keys) return keys.OWNED == true end,
            handle=function() return true end,
        })
        assert.is_true(module.manager:activate_priority_consumer(prepared))

        assert.is_true(screen:onInput({OWNED=true}))
        assert.equals(0, predecessor_count)
        assert.equals('screen-base', screen:onInput({CUSTOM=true}))
        assert.equals(1, predecessor_count)
        assert.is_true(module.manager:release_priority_consumer(prepared))
        assert.is_equal(original, screen.onInput)
    end)

    it('consumes an identified owned failure and notifies only its owner',
            function()
        local predecessor_count = 0
        local context_count = 0
        local observed
        local overlay = {
            feed_viewscreen_widgets=function()
                predecessor_count = predecessor_count + 1
                return 'base'
            end,
        }
        local module = load_hook({dwarfuicore={}}, overlay)
        module.manager:set_context_consumer(function()
            context_count = context_count + 1
            return false
        end)
        local prepared = module.manager:prepare_priority_consumer({}, {
            owns=function(keys) return keys.OWNED == true end,
            handle=function() error('priority exploded') end,
            on_failure=function(message) observed = message end,
        })
        assert.is_true(module.manager:activate_priority_consumer(prepared))

        assert.is_true(overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {OWNED=true}))
        assert.equals(0, context_count)
        assert.equals(0, predecessor_count)
        assert.is_truthy(observed:find('priority exploded', 1, true))
        local diagnostics = module.manager:get_diagnostics()
        assert.is_false(diagnostics.priority_consumer_active)
        assert.equals(1, diagnostics.priority_failure_count)
        assert.equals(module.InputConsumerKind.PRIORITY,
            diagnostics.last_failure.consumer_kind)
        assert.is_true(diagnostics.last_failure.owned)
        assert.is_true(module.manager:release_priority_consumer(prepared))
    end)

    it('delegates a failure before ownership is identified', function()
        local predecessor_count = 0
        local context_count = 0
        local observed
        local overlay = {
            feed_viewscreen_widgets=function()
                predecessor_count = predecessor_count + 1
                return 'base'
            end,
        }
        local module = load_hook({dwarfuicore={}}, overlay)
        module.manager:set_context_consumer(function()
            context_count = context_count + 1
            return false
        end)
        local prepared = module.manager:prepare_priority_consumer({}, {
            owns=function() error('ownership exploded') end,
            handle=function() return true end,
            on_failure=function(message) observed = message end,
        })
        assert.is_true(module.manager:activate_priority_consumer(prepared))

        assert.equals('base', overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {CUSTOM=true}))
        assert.equals(1, context_count)
        assert.equals(1, predecessor_count)
        assert.is_truthy(observed:find('ownership exploded', 1, true))
        local diagnostics = module.manager:get_diagnostics()
        assert.is_false(diagnostics.last_failure.owned)
        assert.is_false(diagnostics.priority_consumer_active)
    end)

    it('requires explicit results from private consumers', function()
        local predecessor_count = 0
        local priority_failure
        local context_failure
        local overlay = {
            feed_viewscreen_widgets=function()
                predecessor_count = predecessor_count + 1
                return 'base'
            end,
        }
        local module = load_hook({dwarfuicore={}}, overlay)
        module.manager:set_context_consumer(
            function() return 'truthy' end,
            function(message) context_failure = message end)
        local prepared = module.manager:prepare_priority_consumer({}, {
            owns=function() return true end,
            handle=function() return 'truthy' end,
            on_failure=function(message) priority_failure = message end,
        })
        assert.is_true(module.manager:activate_priority_consumer(prepared))

        assert.is_true(overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {OWNED=true}))
        assert.equals(0, predecessor_count)
        assert.is_truthy(priority_failure:find(
            'must return a boolean', 1, true))

        assert.equals('base', overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {CUSTOM=true}))
        assert.equals(1, predecessor_count)
        assert.is_nil(context_failure)
    end)

    it('prepares fallibly, activates without rewrapping, and rolls back roots',
            function()
        local overlay = {feed_viewscreen_widgets=function() return 'base' end}
        local module = load_hook({dwarfuicore={}}, overlay)
        local screen = {_native={}, onInput=function() return 'screen' end}
        module.manager:reconcile_roots({[screen]=true})
        local original_native = overlay.feed_viewscreen_widgets

        assert.has_error(function()
            module.manager:prepare_priority_consumer({}, {
                owns=function() return false end,
                handle=function() return false end,
                unknown=true,
            })
        end, 'DwarfUICore priority input consumer contains an unknown field.')
        assert.is_equal(original_native, overlay.feed_viewscreen_widgets)

        local prepared = module.manager:prepare_priority_consumer({}, {
            owns=function() return false end,
            handle=function() return false end,
        })
        assert.is_false(module.manager:activate_priority_consumer({}))
        assert.has_error(function()
            module.manager:prepare_priority_consumer({}, {
                owns=function() return false end,
                handle=function() return false end,
            })
        end, 'DwarfUICore priority input consumer is already prepared or active.')
        local prepared_native = overlay.feed_viewscreen_widgets
        assert.is_not_equal(original_native, prepared_native)
        assert.is_true(module.manager:release_priority_consumer(prepared))
        assert.is_equal(original_native, overlay.feed_viewscreen_widgets)

        prepared = module.manager:prepare_priority_consumer({}, {
            owns=function() return false end,
            handle=function() return false end,
        })
        prepared_native = overlay.feed_viewscreen_widgets
        module.manager:reconcile_roots({[screen]=true})
        assert.is_equal(prepared_native, overlay.feed_viewscreen_widgets)
        assert.equals('base', overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {CUSTOM=true}))
        assert.is_true(module.manager:activate_priority_consumer(prepared))
        assert.is_equal(prepared_native, overlay.feed_viewscreen_widgets)
        assert.is_true(module.manager:release_priority_consumer(prepared))
        assert.is_equal(original_native, overlay.feed_viewscreen_widgets)
        assert.is_not_nil(rawget(screen, 'onInput'))
        assert.is_false(module.manager:release_priority_consumer(prepared))
    end)

    it('adopts one priority trampoline and dispatches once after module reload',
            function()
        local process = {dwarfuicore={}}
        local overlay = {feed_viewscreen_widgets=function() return 'base' end}
        local first = load_hook(process, overlay)
        local dispatch_count = 0
        local prepared = first.manager:prepare_priority_consumer({}, {
            owns=function() return true end,
            handle=function()
                dispatch_count = dispatch_count + 1
                return true
            end,
        })
        assert.is_true(first.manager:activate_priority_consumer(prepared))
        local trampoline = overlay.feed_viewscreen_widgets

        local second = load_hook(process, overlay)
        assert.is_equal(first.manager, second.manager)
        assert.is_false(second.manager:ensure_native())
        assert.is_equal(trampoline, overlay.feed_viewscreen_widgets)
        assert.is_true(overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {OWNED=true}))
        assert.equals(1, dispatch_count)
        assert.equals(1,
            second.manager:get_diagnostics().priority_dispatch_count)
    end)

    it('contains unexpected private-consumer failures and delegates',
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
        module.manager:set_private_context_consumer(
            function() error('hook exploded') end,
            function(message) observed = message end)
        module.manager:ensure_native()

        assert.equals('delegated',
            overlay.feed_viewscreen_widgets(
                'dwarfmode', {}, {_MOUSE_R=true}))
        assert.equals(1, predecessor_count)
        assert.is_nil(observed)
        assert.equals(0, #printed)
        assert.is_false(module.manager:get_diagnostics().disabled)
        assert.equals('delegated',
            overlay.feed_viewscreen_widgets(
                'dwarfmode', {}, {_MOUSE_R=true}))
        assert.equals(2, predecessor_count)

        local prepared = module.manager:prepare_priority_consumer({}, {
            owns=function(keys) return keys.OWNED == true end,
            handle=function() return true end,
        })
        assert.is_true(module.manager:activate_priority_consumer(prepared))
        assert.is_true(overlay.feed_viewscreen_widgets(
            'dwarfmode', {}, {OWNED=true}))
        assert.equals(2, predecessor_count)
    end)
end)
