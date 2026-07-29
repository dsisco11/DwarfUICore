local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local SERVICE_PATH =
    'src/scripts_modinstalled/dwarfui/tooltip_service.lua'
local TARGET_PATH =
    'src/scripts_modinstalled/dwarfui/tooltip_target.lua'
local _, target_types = module_loader.load(repo_root, TARGET_PATH)
local ObservationKind = target_types.TooltipPointerObservationKind

---Loads one service generation over isolated process-wide state.
---@param process table|nil
---@return table harness
local function load_service(process)
    process = process or {dwarfui={}}
    local dfhack = {dwarfui=process.dwarfui}
    local _, service_module = module_loader.load(repo_root, SERVICE_PATH, {
        globals={dfhack=dfhack},
        require_modules={},
        reqscript={['dwarfui/tooltip_target']=target_types},
    })
    return {
        dfhack=dfhack,
        process=process,
        module=service_module,
        service=service_module.service,
    }
end

---Creates one presentation-neutral detector observation.
---@param sequence integer
---@param kind '"target"'|'"blocked"'|'"miss"'
---@param target table|nil
---@param root table|nil
---@param x integer|nil
---@param y integer|nil
---@return dwarfui.TooltipPointerObservation
local function observation(sequence, kind, target, root, x, y)
    local numeric_kind = ({
        target=ObservationKind.TARGET,
        blocked=ObservationKind.BLOCKED,
        miss=ObservationKind.MISS,
    })[kind]
    assert(numeric_kind, 'unknown test observation kind')
    return {
        sequence=sequence,
        kind=numeric_kind,
        pointer_x=x,
        pointer_y=y,
        target=target,
        local_x=x and x - 10 or nil,
        local_y=y and y - 5 or nil,
        root=root,
    }
end

---Creates a target whose pointer callbacks append ordered event names.
---@param events string[]
---@param tooltip any
---@return table target
local function target(events, tooltip)
    return {
        tooltip=tooltip,
        on_pointer_enter=function()
            table.insert(events, 'enter')
        end,
        on_pointer_update=function()
            table.insert(events, 'update')
        end,
        on_pointer_leave=function()
            table.insert(events, 'leave')
        end,
    }
end

describe('DwarfUI tooltip service', function()
    it('publishes immutable initial and repeated dynamic intent snapshots',
            function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local widget = target(events, nil)
        local root = {}
        widget.on_pointer_update = function(self, x, y)
            table.insert(events, ('update:%d,%d'):format(x, y))
            self.tooltip = ('Dynamic %d,%d'):format(x, y)
        end
        service:register(widget)
        local notifications = {}
        service:set_intent_observer(function(intent, revision)
            table.insert(notifications, {intent=intent, revision=revision})
        end)

        assert.is_true(service:accept_pointer_observation(
            observation(1, 'target', widget, root, 13, 9)))
        local first = service:get_diagnostics()
        assert.same({'enter', 'update:3,4'}, events)
        assert.equals('Dynamic 3,4', first.intent.text)
        assert.equals(13, first.intent.anchor_x)
        assert.equals(9, first.intent.anchor_y)
        assert.equals('screen-cells', first.intent.coordinate_space)
        assert.equals(1, first.intent.source_sequence)
        assert.is_equal(root, first.intent.source_root)
        assert.equals(1, first.intent.revision)
        assert.has_error(function() first.intent.text = 'changed' end,
            'DwarfUI tooltip intents are immutable.')

        assert.is_true(service:accept_pointer_observation(
            observation(2, 'target', widget, root, 14, 10)))
        local second = service:get_diagnostics()
        assert.same({
            'enter',
            'update:3,4',
            'update:4,5',
        }, events)
        assert.equals('Dynamic 4,5', second.intent.text)
        assert.equals(2, second.revision)
        assert.equals(2, #notifications)
        assert.is_not.equal(first.intent, second.intent)
    end)

    it('delivers leave before enter when the target changes', function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local first = target(events, 'First')
        local second = target(events, 'Second')
        first.on_pointer_leave = function()
            table.insert(events, 'first-leave')
        end
        second.on_pointer_enter = function()
            table.insert(events, 'second-enter')
        end
        second.on_pointer_update = function()
            table.insert(events, 'second-update')
        end
        service:register(first)
        service:register(second)

        service:accept_pointer_observation(
            observation(1, 'target', first, {}, 11, 6))
        events = {}
        service:accept_pointer_observation(
            observation(2, 'target', second, {}, 12, 7))

        assert.same({
            'first-leave',
            'second-enter',
            'second-update',
        }, events)
        assert.is_equal(second, service:get_diagnostics().target)
        assert.equals('Second', service:get_diagnostics().intent.text)
    end)

    it('clears target and intent exactly once for blocked and miss results',
            function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local widget = target(events, 'Visible')
        service:register(widget)
        local notifications = {}
        service:set_intent_observer(function(intent, revision)
            table.insert(notifications, {intent=intent, revision=revision})
        end)
        service:accept_pointer_observation(
            observation(1, 'target', widget, {}, 11, 6))

        assert.is_true(service:accept_pointer_observation(
            observation(2, 'blocked', nil, {}, 11, 6)))
        assert.is_true(service:accept_pointer_observation(
            observation(3, 'miss', nil, nil, 20, 15)))

        assert.same({'enter', 'update', 'leave'}, events)
        assert.equals(2, #notifications)
        assert.is_nil(notifications[2].intent)
        assert.equals(2, notifications[2].revision)
        local diagnostics = service:get_diagnostics()
        assert.is_nil(diagnostics.target)
        assert.is_nil(diagnostics.intent)
        assert.equals(2, diagnostics.revision)
    end)

    it('keeps hover ownership while nil or empty text clears intent', function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local widget = target(events, 'Visible')
        service:register(widget)

        service:accept_pointer_observation(
            observation(1, 'target', widget, {}, 11, 6))
        assert.is_equal(widget, service:get_diagnostics().target)
        assert.equals('Visible', service:get_diagnostics().intent.text)

        widget.tooltip = nil
        service:accept_pointer_observation(
            observation(2, 'target', widget, {}, 12, 7))
        assert.is_equal(widget, service:get_diagnostics().target)
        assert.is_nil(service:get_diagnostics().intent)
        assert.equals(2, service:get_diagnostics().revision)

        widget.tooltip = ''
        service:accept_pointer_observation(
            observation(3, 'target', widget, {}, 13, 8))
        assert.equals(2, service:get_diagnostics().revision)
        assert.same({'enter', 'update', 'update', 'update'}, events)
    end)

    it('validates tooltip text after callbacks run', function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local widget = target(events, 'initial')
        widget.on_pointer_update = function(self)
            table.insert(events, 'update')
            self.tooltip = 42
        end
        service:register(widget)

        assert.has_error(function()
            service:accept_pointer_observation(
                observation(1, 'target', widget, {}, 11, 6))
        end, 'DwarfUI tooltip must be a string, nil, or an empty string; ' ..
            'got number.')
        assert.same({'enter', 'update'}, events)
        assert.is_equal(widget, service:get_diagnostics().target)
        assert.is_nil(service:get_diagnostics().intent)
    end)

    it('ignores stale and duplicate observations without side effects',
            function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local widget = target(events, 'Fresh')
        service:register(widget)
        service:accept_pointer_observation(
            observation(5, 'target', widget, {}, 11, 6))
        local revision = service:get_diagnostics().revision
        events = {}

        assert.is_false(service:accept_pointer_observation(
            observation(4, 'miss', nil, nil, 20, 15)))
        assert.is_false(service:accept_pointer_observation(
            observation(5, 'miss', nil, nil, 20, 15)))
        assert.same({}, events)
        assert.is_equal(widget, service:get_diagnostics().target)
        assert.equals(revision, service:get_diagnostics().revision)
    end)

    it('unregisters an active target with one immediate leave and clear',
            function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local widget = target(events, 'Registered')
        local clears = 0
        service:set_intent_observer(function(intent)
            if intent == nil then clears = clears + 1 end
        end)
        assert.is_true(service:register(widget))
        assert.is_false(service:register(widget))
        service:accept_pointer_observation(
            observation(1, 'target', widget, {}, 11, 6))

        assert.is_true(service:unregister(widget))
        assert.is_false(service:unregister(widget))
        assert.same({'enter', 'update', 'leave'}, events)
        assert.equals(1, clears)
        assert.is_nil(service:get_diagnostics().target)
        assert.is_nil(service:get_diagnostics().intent)
    end)

    it('treats a collected weak registration as target loss', function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local widget = target(events, 'Weak')
        service:register(widget)
        service:accept_pointer_observation(
            observation(1, 'target', widget, {}, 11, 6))

        -- Removing the weak entry models the state visible after weak-key
        -- collection while retaining a probe reference for callback evidence.
        service:get_registrations()[widget] = nil
        service:accept_pointer_observation(
            observation(2, 'target', widget, {}, 12, 7))

        assert.same({'enter', 'update', 'leave'}, events)
        assert.is_nil(service:get_diagnostics().target)
        assert.is_nil(service:get_diagnostics().intent)
    end)

    it('does not retain inactive registrations through the weak registry',
            function()
        local harness = load_service()
        local service = harness.service
        local weak_widget = setmetatable({}, {__mode='v'})
        do
            local widget = target({}, 'Transient')
            weak_widget[1] = widget
            service:register(widget)
        end

        collectgarbage('collect')
        collectgarbage('collect')

        assert.is_nil(weak_widget[1])
        assert.equals(0, service:registration_count())
    end)

    it('clears detached or ineligible targets through a miss observation',
            function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local widget = target(events, 'Attached')
        service:register(widget)
        service:accept_pointer_observation(
            observation(1, 'target', widget, {}, 11, 6))

        service:accept_pointer_observation(
            observation(2, 'miss', nil, nil, 11, 6))

        assert.same({'enter', 'update', 'leave'}, events)
        assert.is_nil(service:get_diagnostics().intent)
    end)

    it('supports missing, replacement, and removal of intent consumers',
            function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local widget = target(events, 'Consumer-neutral')
        service:register(widget)

        assert.is_true(service:accept_pointer_observation(
            observation(1, 'target', widget, {}, 11, 6)))
        local first_notifications = 0
        local second_notifications = 0
        service:set_intent_observer(function()
            first_notifications = first_notifications + 1
        end)
        service:set_intent_observer(function()
            second_notifications = second_notifications + 1
        end)
        assert.same({'enter', 'update'}, events)

        service:accept_pointer_observation(
            observation(2, 'target', widget, {}, 12, 7))
        service:set_intent_observer(nil)
        service:accept_pointer_observation(
            observation(3, 'target', widget, {}, 13, 8))

        assert.equals(0, first_notifications)
        assert.equals(1, second_notifications)
        assert.same({'enter', 'update', 'update', 'update'}, events)
    end)

    it('shuts down idempotently with one leave and one intent clear', function()
        local harness = load_service()
        local service = harness.service
        local events = {}
        local widget = target(events, 'Shutdown')
        local clears = 0
        service:register(widget)
        service:set_intent_observer(function(intent)
            if intent == nil then clears = clears + 1 end
        end)
        service:accept_pointer_observation(
            observation(1, 'target', widget, {}, 11, 6))

        assert.is_true(service:shutdown())
        assert.is_false(service:shutdown())

        assert.same({'enter', 'update', 'leave'}, events)
        assert.equals(1, clears)
        assert.is_nil(service:get_diagnostics().target)
        assert.is_nil(service:get_diagnostics().intent)
        assert.equals(0, service:get_diagnostics().last_sequence)
    end)

    it('clears target, intent, observer, and ordering state on reload',
            function()
        local process = {dwarfui={}}
        local first = load_service(process).service
        local events = {}
        local widget = target(events, 'Reload')
        local notifications = 0
        first:register(widget)
        first:set_intent_observer(function()
            notifications = notifications + 1
        end)
        first:accept_pointer_observation(
            observation(8, 'target', widget, {}, 11, 6))
        local first_generation = first:get_diagnostics().generation

        local second = load_service(process).service
        local diagnostics = second:get_diagnostics()
        assert.same({'enter', 'update', 'leave'}, events)
        assert.equals(2, notifications)
        assert.equals(first_generation + 1, diagnostics.generation)
        assert.equals(1, diagnostics.registration_count)
        assert.is_nil(diagnostics.target)
        assert.is_nil(diagnostics.intent)
        assert.equals(0, diagnostics.last_sequence)

        assert.is_true(second:accept_pointer_observation(
            observation(1, 'target', widget, {}, 12, 7)))
        assert.equals(2, notifications)
    end)

    it('exposes only presentation-neutral diagnostics and intent fields',
            function()
        local harness = load_service()
        local service = harness.service
        local widget = target({}, 'Fields')
        service:register(widget)
        service:accept_pointer_observation(
            observation(1, 'target', widget, {}, 11, 6))
        local diagnostics = service:get_diagnostics()
        assert.is_equal(diagnostics.intent, service:get_intent())
        local intent_fields = {}
        for key in pairs(diagnostics.intent) do intent_fields[key] = true end

        assert.same({
            anchor_x=true,
            anchor_y=true,
            coordinate_space=true,
            revision=true,
            source_root=true,
            source_sequence=true,
            text=true,
        }, intent_fields)
        local diagnostic_fields = {}
        for key in pairs(diagnostics) do diagnostic_fields[key] = true end
        assert.same({
            api_version=true,
            generation=true,
            intent=true,
            last_sequence=true,
            registration_count=true,
            revision=true,
            target=true,
        }, diagnostic_fields)
    end)

    it('retires incompatible process-wide service versions', function()
        local stale_target = {}
        local stale_intent = {}
        local stale_observer = function() end
        local stale_state = {
            api_version=999,
            registrations={[stale_target]={sequence=1}},
            target=stale_target,
            intent=stale_intent,
            intent_observer=stale_observer,
        }
        local process = {
            dwarfui={
                tooltip_service=stale_state,
            },
        }

        local harness = load_service(process)

        assert.is_not_equal(stale_state,
            process.dwarfui.tooltip_service)
        assert.equals(2, process.dwarfui.tooltip_service.api_version)
        assert.equals(0, harness.service:registration_count())
        assert.is_nil(harness.service:get_intent())
        assert.is_nil(harness.service:get_diagnostics().target)
    end)

    it('loads with no GUI, tooltip renderer, or ZScreen implementation',
            function()
        local harness = load_service()
        assert.is_equal(harness.module.TooltipService,
            getmetatable(harness.service))
        assert.equals('function',
            type(harness.service.accept_pointer_observation))
        assert.equals(0, harness.service:registration_count())
    end)
end)
