local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local POINTER_POLLER_PATH =
    'src/scripts_modinstalled/dwarfui/pointer_poller.lua'
local TARGET_DETECTOR_PATH =
    'src/scripts_modinstalled/dwarfui/tooltip_target_detector.lua'
local SERVICE_PATH =
    'src/scripts_modinstalled/dwarfui/tooltip_service.lua'
local REGISTRATION_PATH =
    'src/scripts_modinstalled/dwarfui/tooltip_registration.lua'

---Builds isolated collaborators for polling-lifecycle integration probes.
---@param state? table
---@return table environment
local function load_environment(state)
    state = state or {}
    state.width = state.width or 40
    state.height = state.height or 20
    state.callbacks = state.callbacks or {}
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{visible=true, active=true}

    ---@class tests.TooltipPollingOverlay
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    local overlay_state = {config={}, db={}}
    local overlay = {
        OverlayWidget=OverlayWidget,
        get_state=function() return overlay_state end,
        isOverlayEnabled=function(name)
            local config = overlay_state.config[name]
            return config and config.enabled or false
        end,
        normalize_list=function(value)
            return type(value) == 'table' and value or {value}
        end,
        simplify_viewscreen_name=function(value)
            return value
        end,
    }
    local dfhack = {
        dwarfui=state.dwarfui or {},
        gui={
            getDFViewscreen=function()
                return {
                    focus=state.focus or 'dwarfmode',
                    widgets=state.native_root,
                }
            end,
            matchFocusString=function(focus, viewscreen)
                return focus == viewscreen.focus
            end,
        },
        screen={
            getMousePos=function()
                state.mouse_reads = (state.mouse_reads or 0) + 1
                return state.mouse_x, state.mouse_y
            end,
        },
        timeout=function(_, _, callback)
            table.insert(state.callbacks, callback)
        end,
    }
    state.dwarfui = dfhack.dwarfui

    local _, pointer = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/pointer.lua', {
            globals={dfhack=dfhack},
        })

    ---Loads one coherent poller, detector, service, and registration generation.
    ---@return table registration
    local function load_generation()
        local _, pointer_poller = module_loader.load(
            repo_root, POINTER_POLLER_PATH, {globals={dfhack=dfhack}})
        local _, target_detector = module_loader.load(
            repo_root, TARGET_DETECTOR_PATH, {
                globals={dfhack=dfhack},
                require_modules={['plugins.overlay']=overlay},
                reqscript={['dwarfui/pointer']=pointer},
            })
        local _, service = module_loader.load(repo_root, SERVICE_PATH, {
            globals={dfhack=dfhack},
        })
        local _, registration = module_loader.load(
            repo_root, REGISTRATION_PATH, {
                globals={dfhack=dfhack},
                require_modules={},
                reqscript={
                    ['dwarfui/pointer_poller']=pointer_poller,
                    ['dwarfui/tooltip_target_detector']=target_detector,
                    ['dwarfui/tooltip_service']=service,
                },
            })
        return registration
    end

    ---Executes the oldest queued timeout callback.
    ---@return boolean executed
    local function run_next()
        local callback = table.remove(state.callbacks, 1)
        if not callback then return false end
        callback()
        return true
    end

    return {
        dfhack=dfhack,
        load_generation=load_generation,
        overlay=overlay,
        OverlayWidget=OverlayWidget,
        run_next=run_next,
        state=state,
        widgets=widgets,
    }
end

---Lays out a root against the controlled screen rectangle.
---@param root gui.View
---@param state table
local function layout(root, state)
    root:updateLayout(widget_harness.rect(
        0, 0, state.width, state.height))
end

---Creates a tooltip-bearing label.
---@param widgets table
---@param frame table
---@param text string|nil
---@return gui.View target
local function target(widgets, frame, text)
    return widgets.Label{frame=frame, tooltip=text}
end

describe('singleton tooltip registration polling', function()
    it('drives one chain across zero-to-one-to-many-to-zero demand',
            function()
        local env = load_environment()
        local registration = env.load_generation()
        local first = target(env.widgets, {l=1, t=1, w=4, h=2}, 'First')
        local second = target(env.widgets, {l=6, t=1, w=4, h=2}, 'Second')

        local initial = registration.get_diagnostics()
        assert.equals(0, initial.registration_count)
        assert.is_false(initial.poller_running)
        assert.is_false(initial.poller_scheduled)
        assert.is_nil(initial.screen)
        assert.is_nil(initial.renderer)
        assert.is_nil(initial.renderer_count)
        assert.is_nil(initial.input_owner)
        assert.is_nil(initial.input_handler)
        assert.is_nil(initial.viewscreen)
        assert.equals(0, #env.state.callbacks)

        assert.is_true(registration.register(first))
        assert.is_false(registration.register(first))
        assert.equals(1, #env.state.callbacks)
        assert.is_true(registration.get_diagnostics().poller_running)
        assert.is_true(registration.get_diagnostics().poller_scheduled)

        assert.is_true(registration.register(second))
        assert.equals(2, registration.get_diagnostics().registration_count)
        assert.equals(1, #env.state.callbacks)
        assert.is_true(registration.unregister(first))
        assert.is_true(registration.get_diagnostics().poller_running)
        assert.is_false(registration.unregister(first))

        assert.is_true(registration.unregister(second))
        local final = registration.get_diagnostics()
        assert.equals(0, final.registration_count)
        assert.is_false(final.poller_running)
        assert.is_false(final.poller_scheduled)
        assert.is_false(env.run_next() and
            registration.get_diagnostics().poller_running)
        assert.equals(0, #env.state.callbacks)
    end)

    it('owns opaque exact-tile handles independently of gui views ' ..
            '#map_tile_contract', function()
        local env = load_environment()
        local registration = env.load_generation()
        local owner = env.widgets.Panel{}
        local pos = {x=10, y=20, z=3}

        assert.equals('function', type(registration.register_map_tile))
        assert.equals('function', type(registration.update_map_tile))
        assert.equals('function', type(registration.unregister_map_tile))

        local first = registration.register_map_tile{
            owner=owner,
            pos=pos,
            tooltip='First',
        }
        local second = registration.register_map_tile{
            owner=owner,
            pos=pos,
            tooltip='Second',
        }

        assert.is_not_nil(first)
        assert.is_not_nil(second)
        assert.is_not_equal(first, second)
        assert.is_not_equal(owner, first)
        assert.is_nil(first.updateLayout)
        assert.is_nil(first.render)

        local diagnostics = registration.get_diagnostics()
        assert.equals(0, diagnostics.widget_registration_count)
        assert.equals(2, diagnostics.map_registration_count)
        assert.equals(2, diagnostics.registration_count)

        assert.is_true(registration.update_map_tile(first, {
            pos={x=11, y=21, z=4},
            tooltip=nil,
        }))
        assert.is_false(registration.update_map_tile({}, {
            pos={x=11, y=21, z=4},
            tooltip='Unknown',
        }))

        assert.is_true(registration.unregister_map_tile(first))
        assert.is_false(registration.unregister_map_tile(first))
        assert.is_false(registration.update_map_tile(first, {
            pos={x=12, y=22, z=5},
            tooltip='Removed',
        }))
        assert.is_true(registration.unregister_map_tile(second))

        diagnostics = registration.get_diagnostics()
        assert.equals(0, diagnostics.map_registration_count)
        assert.equals(0, diagnostics.registration_count)
    end)

    it('requires an owner and exact integer tile coordinates ' ..
            '#map_tile_contract', function()
        local env = load_environment()
        local registration = env.load_generation()
        local owner = env.widgets.Panel{}

        assert.equals('function', type(registration.register_map_tile))
        for _, options in ipairs({
                {pos={x=1, y=2, z=3}, tooltip='Missing owner'},
                {owner=owner, tooltip='Missing position'},
                {owner=owner, pos={x=1, y=2}, tooltip='Missing z'},
                {owner=owner, pos={x=1.5, y=2, z=3}, tooltip='Fractional x'},
                {owner=owner, pos={x='1', y=2, z=3}, tooltip='String x'},
                {owner=owner, pos={x=1, y=2, z=3}, tooltip=42},
            }) do
            assert.has_error(function()
                registration.register_map_tile(options)
            end)
        end

        local handle = registration.register_map_tile{
            owner=owner,
            pos={x=1, y=2, z=3},
            tooltip=nil,
        }
        assert.is_not_nil(handle)
        assert.is_true(registration.unregister_map_tile(handle))
    end)

    it('does not retain an abandoned map-tile registration handle ' ..
            '#map_tile_contract', function()
        local env = load_environment()
        local registration = env.load_generation()
        local owner = env.widgets.Panel{}
        local weak_handle = setmetatable({}, {__mode='v'})

        assert.equals('function', type(registration.register_map_tile))
        do
            local handle = registration.register_map_tile{
                owner=owner,
                pos={x=1, y=2, z=3},
                tooltip='Transient',
            }
            weak_handle[1] = handle
        end

        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_nil(weak_handle[1])

        local diagnostics = registration.get_diagnostics()
        assert.equals(0, diagnostics.map_registration_count)
        assert.equals(0, diagnostics.registration_count)
    end)

    it('polls through detector and service without a presentation host',
            function()
        local env = load_environment{mouse_x=3, mouse_y=2}
        local registration = env.load_generation()
        local child = target(env.widgets,
            {l=1, t=1, w=6, h=3}, nil)
        child.on_pointer_update = function(self, x, y)
            self.tooltip = ('Dynamic %d,%d'):format(x, y)
        end
        local root = env.widgets.Panel{subviews={child}}
        layout(root, env.state)

        registration.register(child)
        assert.is_true(env.run_next())

        local diagnostics = registration.get_diagnostics()
        assert.is_equal(child, diagnostics.target)
        assert.equals('Dynamic 2,1', diagnostics.intent.text)
        assert.equals(3, diagnostics.intent.anchor_x)
        assert.equals(2, diagnostics.intent.anchor_y)
        assert.equals(1, diagnostics.sample_sequence)
        assert.equals(1, diagnostics.last_sequence)
        assert.equals(1, env.state.mouse_reads)
    end)

    it('keeps polling while every registered root is ineligible', function()
        local env = load_environment{mouse_x=2, mouse_y=2}
        local registration = env.load_generation()
        local child = target(env.widgets,
            {l=1, t=1, w=5, h=2}, 'Detached')

        registration.register(child)
        assert.is_true(env.run_next())

        local diagnostics = registration.get_diagnostics()
        assert.equals(1, diagnostics.registration_count)
        assert.is_nil(diagnostics.target)
        assert.is_true(diagnostics.poller_running)
        assert.is_true(diagnostics.poller_scheduled)
        assert.equals(1, #env.state.callbacks)
    end)

    it('does not inspect disabled or failed presentation state', function()
        local failed_hook = setmetatable({}, {
            __index=function()
                error('input service inspected render-hook state')
            end,
        })
        local env = load_environment{
            mouse_x=2,
            mouse_y=2,
            dwarfui={tooltip_render_hook=failed_hook},
        }
        local registration = env.load_generation()
        local child = target(env.widgets,
            {l=1, t=1, w=5, h=2}, 'Independent')
        local root = env.widgets.Panel{subviews={child}}
        layout(root, env.state)

        registration.register(child)
        assert.is_true(env.run_next())

        local diagnostics = registration.get_diagnostics()
        assert.is_equal(child, diagnostics.target)
        assert.equals('Independent', diagnostics.intent.text)
        assert.is_true(diagnostics.poller_running)
        assert.equals(1, diagnostics.sample_sequence)
    end)

    it('stops after collection of the final weak registration', function()
        local env = load_environment()
        local registration = env.load_generation()
        local weak_widget = setmetatable({}, {__mode='v'})
        do
            local transient = target(env.widgets,
                {l=1, t=1, w=4, h=2}, 'Transient')
            weak_widget[1] = transient
            registration.register(transient)
        end

        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_nil(weak_widget[1])
        assert.equals(0, registration.get_diagnostics().registration_count)
        assert.is_true(env.run_next())

        local diagnostics = registration.get_diagnostics()
        assert.is_false(diagnostics.poller_running)
        assert.is_false(diagnostics.poller_scheduled)
        assert.equals(0, diagnostics.sample_sequence)
        assert.equals(0, #env.state.callbacks)
    end)

    it('leaves no resuming chain after a no-registration reload', function()
        local env = load_environment()
        local first = env.load_generation()
        local child = target(env.widgets,
            {l=1, t=1, w=4, h=2}, 'Removed')
        first.register(child)
        first.unregister(child)
        assert.equals(1, #env.state.callbacks)

        local second = env.load_generation()
        local diagnostics = second.get_diagnostics()
        assert.equals(0, diagnostics.registration_count)
        assert.is_false(diagnostics.poller_running)
        assert.is_false(diagnostics.poller_scheduled)

        assert.is_true(env.run_next())
        assert.equals(0, #env.state.callbacks)
        assert.equals(0, env.state.mouse_reads or 0)
    end)

    it('retires old callbacks and starts one new chain on repeated reload',
            function()
        local env = load_environment{mouse_x=2, mouse_y=2}
        local first = env.load_generation()
        local child = target(env.widgets,
            {l=1, t=1, w=4, h=2}, 'Reloaded')
        local root = env.widgets.Panel{subviews={child}}
        layout(root, env.state)
        first.register(child)
        local first_generation =
            first.get_diagnostics().poller_module_generation

        local second = env.load_generation()
        local second_generation =
            second.get_diagnostics().poller_module_generation
        assert.equals(first_generation + 1, second_generation)
        assert.equals(2, #env.state.callbacks)

        assert.is_true(env.run_next())
        assert.equals(0, env.state.mouse_reads or 0)
        assert.equals(1, #env.state.callbacks)
        assert.is_true(env.run_next())
        assert.equals(1, env.state.mouse_reads)
        assert.equals(1, #env.state.callbacks)

        local third = env.load_generation()
        assert.equals(second_generation + 1,
            third.get_diagnostics().poller_module_generation)
        assert.equals(2, #env.state.callbacks)
        assert.is_true(env.run_next())
        assert.equals(1, env.state.mouse_reads)
        assert.is_true(env.run_next())
        assert.equals(2, env.state.mouse_reads)
        assert.equals(1, #env.state.callbacks)
        assert.is_true(third.get_diagnostics().poller_current)
        assert.is_true(third.get_diagnostics().poller_running)
    end)

end)
