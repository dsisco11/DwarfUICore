local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local CLASS_PATH = 'src/scripts_modinstalled/dwarfuicore/class.lua'
local DEFINITION_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/definition.lua'
local IMMUTABLE_ENUM_PATH =
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua'
local MAP_TARGET_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/map_target.lua'
local NUMBERS_PATH =
    'src/scripts_modinstalled/dwarfuicore/utils/numbers.lua'
local REGISTRATION_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/registration.lua'
local ROOT_DISCOVERY_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/root_discovery.lua'
local ROOT_RESOLVER_PATH =
    'src/scripts_modinstalled/dwarfuicore/view_root_resolver.lua'
local TARGET_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/target.lua'

---Returns one caller-owned definition with a recognizable label.
---@param label? string
---@return table
local function definition(label)
    return {
        title='Actions',
        entries={{
            label=label or 'Select',
            on_select=function() end,
        }},
    }
end

---Builds a reloadable registration environment over controlled DFHack state.
---@return table harness
local function load_harness()
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{visible=true, active=true}
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    local state = {
        callbacks={},
        dwarfuicore={},
        focus='dwarfmode',
        native={focus='dwarfmode'},
        overlay_state={config={}, db={}},
        root_notifications={},
        failures={},
        printed={},
    }
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
        dwarfuicore=state.dwarfuicore,
        gui={
            getDFViewscreen=function()
                state.native.focus = state.focus
                state.native.widgets = state.native_root
                return state.native
            end,
            getCurViewscreen=function()
                return state.current_viewscreen or state.native
            end,
            matchFocusString=function(focus, viewscreen)
                return focus == viewscreen.focus
            end,
        },
        timeout=function(_, _, callback)
            table.insert(state.callbacks, callback)
        end,
    }

    ---Loads one destructive registration generation.
    ---@return table module
    local function load_generation()
        local _, numbers = module_loader.load(repo_root, NUMBERS_PATH)
        local _, immutable_enum =
            module_loader.load(repo_root, IMMUTABLE_ENUM_PATH)
        local _, definitions = module_loader.load(
            repo_root, DEFINITION_PATH, {
                reqscript={['dwarfuicore/utils/numbers']=numbers},
            })
        local _, targets = module_loader.load(repo_root, TARGET_PATH, {
            reqscript={
                ['dwarfuicore/context_menu/definition']=definitions,
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfuicore/utils/numbers']=numbers,
            },
        })
        local _, class_helpers =
            module_loader.load(repo_root, CLASS_PATH)
        local _, resolver_module = module_loader.load(
            repo_root, ROOT_RESOLVER_PATH, {
                globals={dfhack=dfhack},
                require_modules={['plugins.overlay']=overlay},
                reqscript={['dwarfuicore/class']=class_helpers},
            })
        local _, discovery_module = module_loader.load(
            repo_root, ROOT_DISCOVERY_PATH, {
                globals={dfhack=dfhack},
            })
        local _, map_module = module_loader.load(
            repo_root, MAP_TARGET_PATH, {
                reqscript={
                    ['dwarfuicore/context_menu/definition']=definitions,
                    ['dwarfuicore/context_menu/target']=targets,
                    ['dwarfuicore/utils/numbers']=numbers,
                    ['dwarfuicore/view_root_resolver']=resolver_module,
                },
            })
        local _, registration_module = module_loader.load(
            repo_root, REGISTRATION_PATH, {
                globals={dfhack=dfhack},
                reqscript={
                    ['dwarfuicore/context_menu/definition']=definitions,
                    ['dwarfuicore/context_menu/map_target']=map_module,
                    ['dwarfuicore/context_menu/root_discovery']=discovery_module,
                    ['dwarfuicore/context_menu/target']=targets,
                    ['dwarfuicore/view_root_resolver']=resolver_module,
                },
            })
        return {
            definitions=definitions,
            module=registration_module,
            resolver=resolver_module.ViewRootResolver.new(),
            targets=targets,
        }
    end

    ---Creates a controlled manager from one loaded generation.
    ---@param generation table
    ---@return dwarfui.ContextMenuRegistrationManager
    local function create_manager(generation)
        return generation.module.ContextMenuRegistrationManager.new{
            root_resolver=generation.resolver,
            scheduler=function(callback)
                table.insert(state.callbacks, callback)
            end,
            printer=function(message)
                table.insert(state.printed, message)
            end,
            on_roots_changed=function(roots)
                local copy = {}
                for root in pairs(roots) do copy[root] = true end
                table.insert(state.root_notifications, copy)
            end,
            on_failure=function(message)
                table.insert(state.failures, message)
            end,
            is_menu_open=function() return state.menu_open or false end,
        }
    end

    ---Lays out and presents one ordinary native root.
    ---@param root table
    local function present_native(root)
        root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        state.native_root = root
        state.current_viewscreen = state.native
    end

    ---Lays out and enables one overlay root.
    ---@param root table
    local function present_overlay(root)
        root:updateLayout(widget_harness.rect(0, 0, 40, 20))
        state.overlay_state.config[root.name] = {enabled=true}
        state.overlay_state.db[root.name] = {widget=root}
    end

    ---Runs the oldest controlled discovery callback.
    ---@return boolean
    ---@return any
    local function run_next()
        local callback = table.remove(state.callbacks, 1)
        assert.is_function(callback)
        return pcall(callback)
    end

    return {
        OverlayWidget=OverlayWidget,
        create_manager=create_manager,
        load_generation=load_generation,
        overlay=overlay,
        present_native=present_native,
        present_overlay=present_overlay,
        run_next=run_next,
        state=state,
        widgets=widgets,
    }
end

describe('context-menu registration', function()
    it('re-registers and updates one weak widget without changing identity',
            function()
        local harness = load_harness()
        local generation = harness.load_generation()
        local manager = harness.create_manager(generation)
        local widget = harness.widgets.Panel{}
        local root = harness.widgets.Panel{subviews={widget}}
        harness.present_native(root)

        assert.is_true(manager:register(widget, definition('First')))
        local original = assert(manager:resolve_widget(widget))
        assert.equals('First',
            original:get_definition_snapshot().entries[1].label)
        assert.is_false(manager:register(widget, definition('Second')))
        local reregistered = assert(manager:resolve_widget(widget))
        assert.equals(original.identity, reregistered.identity)
        assert.equals(original.sequence, reregistered.sequence)
        assert.equals('Second',
            reregistered:get_definition_snapshot().entries[1].label)
        assert.equals(1, manager:registration_count())
        assert.equals(1, #harness.state.callbacks)

        assert.is_true(manager:update(widget, definition('Third')))
        local updated = assert(manager:resolve_widget(widget))
        assert.equals(original.identity, updated.identity)
        assert.equals('Third',
            updated:get_definition_snapshot().entries[1].label)
        assert.is_false(manager:update({}, definition('Unknown')))
    end)

    it('validates replacements before mutating the prior registration',
            function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local widget = harness.widgets.Panel{}
        local root = harness.widgets.Panel{subviews={widget}}
        harness.present_native(root)
        manager:register(widget, definition('Before'))
        local identity = manager:resolve_widget(widget).identity
        local invalid = {entries={{label='Missing handler'}}}

        assert.has_error(function()
            manager:register(widget, invalid)
        end)
        assert.has_error(function()
            manager:update(widget, invalid)
        end)

        local candidate = assert(manager:resolve_widget(widget))
        assert.equals(identity, candidate.identity)
        assert.equals('Before',
            candidate:get_definition_snapshot().entries[1].label)
        assert.equals(1, manager:registration_count())
    end)

    it('discovers attachment independently from dynamic eligibility',
            function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local widget = harness.widgets.Panel{visible=false, active=false}
        local root = harness.widgets.Panel{subviews={widget}}
        harness.present_native(root)
        manager:register(widget, definition())

        assert.is_nil(manager:resolve_widget(widget))
        assert.is_true(harness.run_next())
        assert.same({[root]=true},
            harness.state.root_notifications[1])

        widget.visible = true
        widget.active = true
        assert.equals(root, manager:resolve_widget(widget).root)
        widget.parent_view = nil
        assert.is_nil(manager:resolve_widget(widget))
        assert.is_true(harness.run_next())
        assert.same({},
            harness.state.root_notifications[
                #harness.state.root_notifications])
        widget.parent_view = root
        assert.is_true(harness.run_next())
        assert.same({[root]=true},
            harness.state.root_notifications[
                #harness.state.root_notifications])
        assert.equals(root, manager:resolve_widget(widget).root)
    end)

    it('tracks attachment-root changes without duplicating discovery',
            function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local widget = harness.widgets.Panel{}
        local first = harness.widgets.Panel{subviews={widget}}
        local second = harness.widgets.Panel{}
        harness.present_native(first)
        second:updateLayout(widget_harness.rect(0, 0, 40, 20))
        manager:register(widget, definition())
        harness.run_next()
        assert.same({[first]=true},
            harness.state.root_notifications[1])

        first.subviews = {}
        second.subviews = {widget}
        widget.parent_view = second
        harness.present_native(second)
        assert.is_true(harness.run_next())
        assert.same({[second]=true},
            harness.state.root_notifications[2])
        assert.equals(second, manager:resolve_widget(widget).root)
        assert.equals(1, #harness.state.callbacks)
    end)

    it('uses the shared resolver for disabled and wrong-screen overlays',
            function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local widget = harness.widgets.Panel{}
        local overlay = harness.OverlayWidget{
            name='context-test',
            viewscreens={'dwarfmode'},
            subviews={widget},
        }
        harness.present_overlay(overlay)
        manager:register(widget, definition())

        assert.equals(overlay, manager:resolve_widget(widget).root)
        harness.state.overlay_state.config[overlay.name].enabled = false
        assert.is_nil(manager:resolve_widget(widget))
        harness.state.overlay_state.config[overlay.name].enabled = true
        harness.state.focus = 'viewscreen_title'
        assert.is_nil(manager:resolve_widget(widget))
        harness.state.focus = 'dwarfmode'
        assert.equals(overlay, manager:resolve_widget(widget).root)
    end)

    it('shares monotonic identities with map registrations', function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local widget = harness.widgets.Panel{}
        local owner = harness.widgets.Panel{subviews={widget}}
        harness.present_native(owner)
        manager:register(widget, definition())
        local widget_identity =
            manager:resolve_widget(widget).identity
        local handle = manager:register_map_tile{
            owner=owner,
            pos={x=1, y=2, z=3},
            definition=definition('Map'),
        }
        local map_identity =
            manager:resolve_map_tile(handle).identity

        assert.equals(widget_identity + 1, map_identity)
        assert.is_true(manager:update_map_tile(handle, {
            pos={x=4, y=5, z=6},
            definition=definition('Moved'),
        }))
        assert.equals(map_identity,
            manager:resolve_map_tile(handle).identity)
        assert.equals(map_identity,
            manager:resolve_map_identity(map_identity).identity)
        assert.equals(map_identity,
            manager:detect_map_tile{x=4, y=5, z=6}.identity)
    end)

    it('re-evaluates map-owner eligibility through the shared resolver',
            function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local owner = harness.widgets.Panel{}
        harness.present_native(owner)
        local handle = manager:register_map_tile{
            owner=owner,
            pos={x=1, y=2, z=3},
            definition=definition('Map'),
        }
        local identity = manager:resolve_map_tile(handle).identity

        assert.equals(owner, manager:resolve_map_tile(handle).root)
        owner._native = harness.state.native
        harness.state.current_viewscreen = {parent=harness.state.native}
        assert.is_nil(manager:resolve_map_tile(handle))
        assert.equals(owner,
            manager:resolve_open_map_identity(identity, owner).root)
        owner.visible = false
        assert.is_nil(manager:resolve_open_map_identity(identity, owner))
        owner.visible = true
        owner.active = false
        assert.is_nil(manager:resolve_open_map_identity(identity, owner))
        owner.active = true
        harness.state.current_viewscreen = harness.state.native
        owner._native = nil
        harness.state.native_root = harness.widgets.Panel{}
        assert.is_nil(manager:resolve_map_tile(handle))
        harness.present_native(owner)
        assert.equals(owner, manager:resolve_map_tile(handle).root)

        local overlay_owner = harness.OverlayWidget{
            name='map-context-test',
            viewscreens={'dwarfmode'},
        }
        harness.present_overlay(overlay_owner)
        local overlay_handle = manager:register_map_tile{
            owner=overlay_owner,
            pos={x=4, y=5, z=6},
            definition=definition('Overlay map'),
        }
        assert.equals(overlay_owner,
            manager:resolve_map_tile(overlay_handle).root)
        harness.state.overlay_state.config[
            overlay_owner.name].enabled = false
        assert.is_nil(manager:resolve_map_tile(overlay_handle))
        harness.state.overlay_state.config[
            overlay_owner.name].enabled = true
        assert.equals(overlay_owner,
            manager:resolve_map_tile(overlay_handle).root)
    end)

    it('collects weak widgets and stops only after final demand disappears',
            function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local widget = harness.widgets.Panel{}
        local root = harness.widgets.Panel{subviews={widget}}
        harness.present_native(root)
        manager:register(widget, definition())
        harness.run_next()
        local weak = setmetatable({widget}, {__mode='v'})

        root.subviews = {}
        widget.parent_view = nil
        widget = nil
        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_nil(weak[1])
        assert.equals(0, manager:registration_count())
        assert.is_true(harness.run_next())
        local diagnostics = manager:get_diagnostics()
        assert.is_false(diagnostics.discovery.running)
        assert.is_false(diagnostics.discovery.scheduled)
        assert.same({},
            harness.state.root_notifications[
                #harness.state.root_notifications])
    end)

    it('keeps discovery active for an open menu after final unregister',
            function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local widget = harness.widgets.Panel{}
        local root = harness.widgets.Panel{subviews={widget}}
        harness.present_native(root)
        manager:register(widget, definition())
        harness.run_next()
        harness.state.menu_open = true

        assert.is_true(manager:unregister(widget))
        assert.is_true(manager:get_diagnostics().discovery.running)
        harness.state.menu_open = false
        manager:set_menu_open_predicate(function()
            return harness.state.menu_open
        end)
        assert.is_false(manager:get_diagnostics().discovery.running)
    end)

    it('contains discovery failure and disables current target handling',
            function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local widget = harness.widgets.Panel{}
        local root = harness.widgets.Panel{subviews={widget}}
        harness.present_native(root)
        manager:register(widget, definition())
        manager._discover_attachment_roots = function()
            error('discovery exploded')
        end

        assert.is_true(harness.run_next())
        local diagnostics = manager:get_diagnostics()
        assert.is_true(diagnostics.disabled)
        assert.is_true(diagnostics.discovery.failed)
        assert.is_truthy(diagnostics.failure:find(
            'discovery exploded', 1, true))
        assert.equals(1, #harness.state.failures)
        assert.equals(1, #harness.state.printed)
        assert.is_nil(manager:resolve_widget(widget))
    end)

    it('preserves compatible registrations across ordinary module loads',
            function()
        local harness = load_harness()
        local first_generation = harness.load_generation()
        local first = first_generation.module.manager
        local widget = harness.widgets.Panel{}
        local owner = harness.widgets.Panel{subviews={widget}}
        harness.present_native(owner)
        first:register(widget, definition())
        local map_handle = first:register_map_tile{
            owner=owner,
            pos={x=1, y=2, z=3},
            definition=definition('Map'),
        }
        assert.is_not_nil(map_handle)
        assert.equals(2, first:registration_count())

        local second_generation = harness.load_generation()
        local second = second_generation.module.manager
        assert.is_equal(first, second)
        assert.equals(2, second:registration_count())
        assert.equals(2, first:registration_count())
        assert.is_not_nil(first:resolve_widget(widget))
        assert.is_true(first:get_diagnostics().current)
        assert.is_false(first:register(widget, definition('Updated')))
        assert.is_true(harness.run_next())
        assert.is_true(
            first:get_diagnostics().discovery.running)
    end)

    it('explicitly unregisters without mutating consumer presentation',
            function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local widget = harness.widgets.Panel{}
        local root = harness.widgets.Panel{subviews={widget}}
        harness.present_native(root)
        local original_subviews = #root.subviews
        manager:register(widget, definition())

        assert.equals(original_subviews, #root.subviews)
        assert.is_nil(manager.screen)
        assert.is_true(manager:unregister(widget))
        assert.is_false(manager:unregister(widget))
        assert.equals(original_subviews, #root.subviews)
        assert.equals(0, manager:registration_count())
        assert.is_false(manager:get_diagnostics().discovery.running)
    end)

    it('clears world-owned state without retiring the current manager',
            function()
        local harness = load_harness()
        local manager =
            harness.create_manager(harness.load_generation())
        local widget = harness.widgets.Panel{}
        local root = harness.widgets.Panel{subviews={widget}}
        harness.present_native(root)
        manager:register(widget, definition())
        manager:register_map_tile{
            owner=root,
            pos={x=1, y=2, z=3},
            definition=definition('Map'),
        }

        assert.is_true(manager:clear())
        local diagnostics = manager:get_diagnostics()
        assert.equals(0, manager:registration_count())
        assert.equals(0, diagnostics.widget_registration_sequence)
        assert.equals(0, diagnostics.map.registration_sequence)
        assert.is_false(diagnostics.discovery.running)
        assert.is_true(diagnostics.current)
        assert.is_true(manager:register(widget, definition('Again')))
        assert.equals(1, manager:registration_count())
    end)
end)
