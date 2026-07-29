local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local ROOT_RESOLVER_PATH =
    'src/scripts_modinstalled/dwarfui/tooltip_root_resolver.lua'
local MAP_TARGET_PATH =
    'src/scripts_modinstalled/dwarfui/tooltip_map_target.lua'

---Builds a reloadable exact-map-target test environment.
---@return table environment
local function load_environment()
    local state = {
        dwarfui={},
        focus='dwarfmode',
        overlay_state={config={}, db={}},
    }
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{visible=true, active=true}

    ---@class tests.TooltipMapOverlay
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    local overlay = {
        OverlayWidget=OverlayWidget,
        get_state=function() return state.overlay_state end,
        isOverlayEnabled=function(name)
            local config = state.overlay_state.config[name]
            return config and config.enabled or false
        end,
        normalize_list=function(value)
            return type(value) == 'table' and value or {value}
        end,
        simplify_viewscreen_name=function(value) return value end,
    }
    local dfhack = {
        dwarfui=state.dwarfui,
        gui={
            getDFViewscreen=function()
                return {focus=state.focus, widgets=state.native_root}
            end,
            getCurViewscreen=function()
                return state.current_viewscreen
            end,
            matchFocusString=function(focus, viewscreen)
                return focus == viewscreen.focus
            end,
        },
    }

    ---Loads one root resolver and registry generation over persistent state.
    ---@return table module
    local function load_generation()
        local _, class_helpers = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui/class.lua')
        local _, root_resolver = module_loader.load(
            repo_root, ROOT_RESOLVER_PATH, {
                globals={dfhack=dfhack},
                require_modules={['plugins.overlay']=overlay},
                reqscript={['dwarfui/class']=class_helpers},
            })
        local _, map_target = module_loader.load(
            repo_root, MAP_TARGET_PATH, {
                globals={dfhack=dfhack},
                reqscript={
                    ['dwarfui/tooltip_root_resolver']=root_resolver,
                },
            })
        return map_target
    end

    return {
        OverlayWidget=OverlayWidget,
        load_generation=load_generation,
        overlay=overlay,
        state=state,
        widgets=widgets,
    }
end

---Lays out and presents a native root.
---@param env table
---@param root gui.View
local function present_native(env, root)
    root:updateLayout(widget_harness.rect(0, 0, 40, 20))
    env.state.native_root = root
end

---Creates one normalized pointer and map-position sample.
---@param sequence integer
---@param x integer|nil
---@param y integer|nil
---@param map_x integer|nil
---@param map_y integer|nil
---@param map_z integer|nil
---@return dwarfui.PointerSample
local function sample(sequence, x, y, map_x, map_y, map_z)
    return {
        sequence=sequence,
        x=x,
        y=y,
        map_x=map_x,
        map_y=map_y,
        map_z=map_z,
        coordinate_space='screen-cells',
    }
end

describe('DwarfUI exact map-tile tooltip targets', function()
    it('returns a presentation-neutral exact candidate with copied state',
            function()
        local env = load_environment()
        local registry = env.load_generation().registry
        local owner = env.widgets.Panel{}
        present_native(env, owner)
        local pos = {x=10, y=20, z=3}
        local handle = registry:register{
            owner=owner,
            pos=pos,
            tooltip='Station',
        }
        pos.x = 99

        local hit = registry:detect(sample(7, 4, 5, 10, 20, 3))
        assert.equals('target', hit.kind)
        assert.equals(7, hit.sequence)
        assert.equals(4, hit.pointer_x)
        assert.equals(5, hit.pointer_y)
        assert.equals(10, hit.map_x)
        assert.equals(20, hit.map_y)
        assert.equals(3, hit.map_z)
        assert.equals('map-tile', hit.target_kind)
        assert.equals(handle, hit.target)
        assert.equals(handle, hit.identity)
        assert.equals(owner, hit.root)
        assert.equals(owner, hit.source_root)
        assert.equals(1, hit.registration_sequence)
        assert.equals('Station', hit.tooltip)
    end)

    it('misses every unequal coordinate and unavailable map sample',
            function()
        local env = load_environment()
        local registry = env.load_generation().registry
        local owner = env.widgets.Panel{}
        present_native(env, owner)
        registry:register{
            owner=owner,
            pos={x=10, y=20, z=3},
            tooltip='Station',
        }
        local misses = {
            sample(1, 4, 5, 11, 20, 3),
            sample(2, 4, 5, 10, 21, 3),
            sample(3, 4, 5, 10, 20, 4),
            sample(4, 4, 5, nil, 20, 3),
            sample(5, 4, 5, 10, nil, 3),
            sample(6, 4, 5, 10, 20, nil),
            sample(7, nil, 5, 10, 20, 3),
            sample(8, 4, nil, 10, 20, 3),
        }
        for _, value in ipairs(misses) do
            assert.equals('miss', registry:detect(value).kind)
        end
        local z_miss = registry:detect(misses[3])
        assert.equals(10, z_miss.map_x)
        assert.equals(20, z_miss.map_y)
        assert.equals(4, z_miss.map_z)
    end)

    it('resolves duplicate coordinates by latest eligible registration',
            function()
        local env = load_environment()
        local registry = env.load_generation().registry
        local first_owner = env.widgets.Panel{}
        local second_owner = env.widgets.Panel{}
        local root = env.widgets.Panel{
            subviews={first_owner, second_owner},
        }
        present_native(env, root)
        local first = registry:register{
            owner=first_owner,
            pos={x=1, y=2, z=3},
            tooltip='First',
        }
        local second = registry:register{
            owner=second_owner,
            pos={x=1, y=2, z=3},
            tooltip='Second',
        }

        local hit = registry:detect(sample(1, 3, 4, 1, 2, 3))
        assert.equals(second, hit.target)
        assert.equals('Second', hit.tooltip)
        second_owner.visible = false
        hit = registry:detect(sample(2, 3, 4, 1, 2, 3))
        assert.equals(first, hit.target)
        assert.equals('First', hit.tooltip)
    end)

    it('atomically reindexes updates and removes empty buckets',
            function()
        local env = load_environment()
        local registry = env.load_generation().registry
        local owner = env.widgets.Panel{}
        present_native(env, owner)
        local handle = registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            tooltip='Before',
        }

        assert.has_error(function()
            registry:update(handle, {
                pos={x=4, y=5},
                tooltip='Invalid',
            })
        end)
        assert.equals(handle,
            registry:detect(sample(1, 1, 1, 1, 2, 3)).target)
        assert.is_true(registry:update(handle, {
            pos={x=4, y=5, z=6},
            tooltip='After',
        }))
        assert.equals('miss',
            registry:detect(sample(2, 1, 1, 1, 2, 3)).kind)
        local hit = registry:detect(sample(3, 1, 1, 4, 5, 6))
        assert.equals(handle, hit.target)
        assert.equals(1, hit.registration_sequence)
        assert.equals('After', hit.tooltip)
        assert.equals(1, registry:get_diagnostics().coordinate_bucket_count)

        assert.is_true(registry:unregister(handle))
        assert.is_false(registry:unregister(handle))
        assert.is_false(registry:update(handle, {
            pos={x=7, y=8, z=9},
        }))
        local diagnostics = registry:get_diagnostics()
        assert.equals(0, diagnostics.registration_count)
        assert.equals(0, diagnostics.coordinate_bucket_count)
    end)

    it('drops abandoned weak handles and their coordinate bucket',
            function()
        local env = load_environment()
        local registry = env.load_generation().registry
        local owner = env.widgets.Panel{}
        present_native(env, owner)
        local handle = registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            tooltip='Temporary',
        }
        assert.is_not_nil(handle)
        handle = nil
        collectgarbage('collect')
        collectgarbage('collect')

        local diagnostics = registry:get_diagnostics()
        assert.equals(0, diagnostics.registration_count)
        assert.equals(0, diagnostics.coordinate_bucket_count)
        assert.equals('miss',
            registry:detect(sample(1, 1, 1, 1, 2, 3)).kind)
    end)

    it('shares attachment, visibility, activity, and native-root eligibility',
            function()
        local env = load_environment()
        local registry = env.load_generation().registry
        local owner = env.widgets.Panel{}
        local root = env.widgets.Panel{subviews={owner}}
        present_native(env, root)
        registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            tooltip='Attached',
        }

        assert.equals('target',
            registry:detect(sample(1, 1, 1, 1, 2, 3)).kind)
        root.active = false
        assert.equals('miss',
            registry:detect(sample(2, 1, 1, 1, 2, 3)).kind)
        root.active = true
        owner.visible = false
        assert.equals('miss',
            registry:detect(sample(3, 1, 1, 1, 2, 3)).kind)
        owner.visible = true
        root.subviews = {}
        assert.equals('miss',
            registry:detect(sample(4, 1, 1, 1, 2, 3)).kind)
        root.subviews = {owner}
        env.state.native_root = env.widgets.Panel{}
        assert.equals('miss',
            registry:detect(sample(5, 1, 1, 1, 2, 3)).kind)
    end)

    it('requires an enabled current registry-owned overlay root', function()
        local env = load_environment()
        local registry = env.load_generation().registry
        local owner = env.OverlayWidget{}
        owner.name = 'route-stops'
        owner.viewscreens = {'dwarfmode'}
        owner:updateLayout(widget_harness.rect(0, 0, 40, 20))
        env.state.overlay_state.config[owner.name] = {enabled=true}
        env.state.overlay_state.db[owner.name] = {widget=owner}
        registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            tooltip='Overlay',
        }

        assert.equals('target',
            registry:detect(sample(1, 1, 1, 1, 2, 3)).kind)
        env.state.overlay_state.config[owner.name].enabled = false
        assert.equals('miss',
            registry:detect(sample(2, 1, 1, 1, 2, 3)).kind)
        env.state.overlay_state.config[owner.name].enabled = true
        env.state.overlay_state.db[owner.name].widget = env.OverlayWidget{}
        assert.equals('miss',
            registry:detect(sample(3, 1, 1, 1, 2, 3)).kind)
        env.state.overlay_state.db[owner.name].widget = owner
        env.state.focus = 'other'
        assert.equals('miss',
            registry:detect(sample(4, 1, 1, 1, 2, 3)).kind)
    end)

    it('preserves live handles and exact indices across module reload',
            function()
        local env = load_environment()
        local first_module = env.load_generation()
        local owner = env.widgets.Panel{}
        present_native(env, owner)
        local handle = first_module.registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            tooltip='Before reload',
        }
        local first_generation =
            first_module.registry:get_diagnostics().generation

        local second_module = env.load_generation()
        local registry = second_module.registry
        assert.equals(first_generation + 1,
            registry:get_diagnostics().generation)
        assert.equals(handle,
            registry:detect(sample(1, 1, 1, 1, 2, 3)).target)
        assert.is_true(registry:update(handle, {
            pos={x=4, y=5, z=6},
            tooltip='After reload',
        }))
        assert.equals(handle,
            registry:detect(sample(2, 1, 1, 4, 5, 6)).target)
        assert.is_true(registry:unregister(handle))
        assert.equals(0,
            registry:get_diagnostics().coordinate_bucket_count)
    end)
end)
