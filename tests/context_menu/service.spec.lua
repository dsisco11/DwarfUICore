local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local SERVICE_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/service.lua'

---Creates fresh service state matching the production state contract.
---@param generation? integer
---@return table
local function service_state(generation)
    return {
        api_version=1,
        generation=generation or 1,
        session=nil,
        presentation=nil,
        disabled_generation=nil,
        last_error=nil,
        last_failure=nil,
        failure_count=0,
        last_handler_error=nil,
        handler_failure_count=0,
        open_count=0,
        close_count=0,
        selection_count=0,
    }
end

---Creates a fully observable registration-manager double.
---@return table
local function registration_double()
    local manager = {
        disabled=false,
        clear_count=0,
        shutdown_count=0,
    }

    ---Stores the open-session demand predicate.
    ---@param callback function
    function manager:set_menu_open_predicate(callback)
        self.open_predicate = callback
    end

    ---Stores the attachment-root observer.
    ---@param callback function|nil
    function manager:set_root_observer(callback)
        self.root_observer = callback
    end

    ---Stores the discovery-failure observer.
    ---@param callback function|nil
    function manager:set_failure_observer(callback)
        self.failure_observer = callback
    end

    ---Disables registration and discovery for this generation.
    ---@param message string
    ---@return boolean
    function manager:disable(message)
        self.disabled = true
        self.failure = message
        return true
    end

    ---Records one non-retiring registration clear.
    ---@return boolean
    function manager:clear()
        self.clear_count = self.clear_count + 1
        return true
    end

    ---Records destructive registration shutdown.
    ---@return boolean
    function manager:shutdown()
        self.shutdown_count = self.shutdown_count + 1
        return true
    end

    ---Returns controlled registration diagnostics.
    ---@return table
    function manager:get_diagnostics()
        return {disabled=self.disabled}
    end

    ---Returns the controlled map registration count.
    ---@return integer
    function manager:map_registration_count()
        return 0
    end

    ---Resolves the controlled open map registration.
    ---@return table|nil
    function manager:resolve_open_map_identity()
        return self.open_map_candidate
    end

    return manager
end

---Creates a fully observable input-hook manager double.
---@return table
local function hook_double()
    local manager = {root_sets={}, shutdown_count=0}

    ---Stores the opening handler.
    ---@param callback function|nil
    function manager:set_handler(callback)
        self.handler = callback
    end

    ---Stores the hook-failure handler.
    ---@param callback function|nil
    function manager:set_failure_handler(callback)
        self.failure_handler = callback
    end

    ---Records one root-set reconciliation.
    ---@param roots table
    ---@return boolean
    function manager:reconcile_roots(roots)
        table.insert(self.root_sets, roots)
        return true
    end

    ---Records hook shutdown.
    ---@return boolean
    function manager:shutdown()
        self.shutdown_count = self.shutdown_count + 1
        return true
    end

    ---Returns controlled hook diagnostics.
    ---@return table
    function manager:get_diagnostics()
        return {shutdown_count=self.shutdown_count}
    end

    return manager
end

---Loads one service generation with controlled singleton dependencies.
---@param state? table
---@return table
local function load_harness(state)
    state = state or {}
    state.process = state.process or {dwarfuicore={}, onStateChange={}}
    state.errors = state.errors or {}
    state.process.printerr = function(message)
        table.insert(state.errors, message)
    end
    state.registrations = registration_double()
    state.hook = hook_double()

    local Session = {}
    Session.__index = Session

    ---Creates one controlled open session.
    ---@param options table
    ---@return table
    function Session.new(options)
        return setmetatable({
            options=options,
            open=true,
            definition=options.definition,
        }, Session)
    end

    ---Closes the controlled session exactly once.
    ---@return boolean
    function Session:close()
        if not self.open then return false end
        self.open = false
        return true
    end

    ---Returns the controlled definition snapshot.
    ---@return table
    function Session:get_definition_snapshot()
        return self.definition
    end

    ---Returns the controlled target descriptor.
    ---@return table
    function Session:get_target_descriptor()
        return self.options.target
    end

    ---Returns the controlled anchor descriptor.
    ---@return table
    function Session:get_anchor_descriptor()
        return self.options.anchor
    end

    ---Returns the controlled source root.
    ---@return table
    function Session:get_source_root()
        return self.options.source_root
    end

    ---Returns one live controlled callback context.
    ---@return table|nil
    function Session:create_selection_context()
        if not self.open then return nil end
        return self.options
    end

    local numbers = {
        is_integer=function(value)
            return type(value) == 'number' and value % 1 == 0
        end,
    }
    local input_samples = {
        ContextMenuInputSampler={
            new=function()
                return {capture=function() return {} end}
            end,
        },
    }
    local target_detectors = {
        ContextMenuDetectionKind={TARGET=1, BLOCKED=2, MISS=3},
        ContextMenuTargetDetector={
            new=function()
                return {detect=function() return {kind=3} end}
            end,
        },
    }
    local _, module = module_loader.load(repo_root, SERVICE_PATH, {
        globals={dfhack=state.process, SC_WORLD_UNLOADED=42},
        reqscript={
            ['dwarfuicore/context_menu/input_hook']={manager=state.hook},
            ['dwarfuicore/context_menu/input_sample']=input_samples,
            ['dwarfuicore/context_menu/registration']={
                manager=state.registrations,
            },
            ['dwarfuicore/context_menu/target_detector']=target_detectors,
            ['dwarfuicore/context_menu/target']={
                ContextMenuOpenSession=Session,
                ContextMenuTargetKind={WIDGET=1, MAP_TILE=2},
            },
            ['dwarfuicore/utils/numbers']=numbers,
        },
    })
    state.module = module
    return state
end

---Creates a detected candidate with one controlled callback.
---@param callback? function
---@return table
local function detection(callback)
    local candidate = {
        source={},
        root={},
        definition={
            entries={{
                label='Action',
                on_select=callback or function() end,
            }},
        },
    }

    ---Returns the candidate's controlled definition snapshot.
    ---@return table
    function candidate:get_definition_snapshot()
        return self.definition
    end

    return {
        kind=1,
        candidate=candidate,
        target={kind=1, registration_identity=7},
        anchor={kind=1, screen_position={x=3, y=4}},
        root=candidate.root,
    }
end

---Creates a hidden presenter factory and observable lifecycle state.
---@return function
---@return table
local function presenter_factory()
    local lifecycle = {shown=0, closed=0}
    local factory = function()
        return {
            show=function()
                lifecycle.shown = lifecycle.shown + 1
            end,
            close=function()
                lifecycle.closed = lifecycle.closed + 1
            end,
        }
    end
    return factory, lifecycle
end

---Creates one service with controlled collaborators.
---@param harness table
---@param options? table
---@return table
local function create_service(harness, options)
    options = options or {}
    return harness.module.ContextMenuService.new(
        service_state(), {
            registrations=options.registrations or registration_double(),
            detector=options.detector or {
                detect=function() return {kind=3} end,
            },
            sampler=options.sampler or {
                capture=function() return {} end,
            },
            input_hook=options.input_hook or hook_double(),
            presentation_factory=options.presentation_factory or
                presenter_factory(),
            printer=options.printer or function(message)
                table.insert(harness.errors, message)
            end,
        })
end

describe('context-menu service', function()
    it('keeps the production singleton inactive until presentation wiring',
            function()
        local harness = load_harness()

        assert.is_false(harness.module.service:get_diagnostics().started)
        assert.is_nil(harness.hook.handler)
        assert.is_nil(harness.registrations.root_observer)
    end)

    it('owns the only active session and all open/close transitions', function()
        local harness = load_harness()
        local factory, presentation = presenter_factory()
        local service = create_service(harness, {
            presentation_factory=factory,
        })

        assert.is_true(service:open(detection()))
        assert.is_true(service:is_open())
        assert.is_false(service:open(detection()))
        assert.equals(1, presentation.shown)
        assert.is_true(service:close())
        assert.is_false(service:is_open())
        assert.equals(1, presentation.closed)
        assert.is_false(service:close())
    end)

    it('validates an open map session against identity and copied position',
            function()
        local harness = load_harness()
        local registrations = registration_double()
        registrations.open_map_candidate={pos={x=10, y=20, z=3}}
        local captured_actions
        local service = create_service(harness, {
            registrations=registrations,
            presentation_factory=function(_, actions)
                captured_actions = actions
                return {show=function() end, close=function() end}
            end,
        })
        local target = detection()
        target.target.kind = 2
        target.anchor = {
            kind=2,
            screen_position={x=4, y=5},
            map_position={x=10, y=20, z=3},
        }
        target.candidate.owner = {}

        assert.is_true(service:open(target))
        assert.is_true(captured_actions.map_session_is_valid())
        registrations.open_map_candidate.pos.x = 11
        assert.is_false(captured_actions.map_session_is_valid())
        registrations.open_map_candidate = nil
        assert.is_false(captured_actions.map_session_is_valid())
    end)

    it('opens only actionable right-click targets from one synchronous sample',
            function()
        local harness = load_harness()
        local factory, presentation = presenter_factory()
        local captures, detections = 0, 0
        local current = detection()
        local service = create_service(harness, {
            presentation_factory=factory,
            sampler={capture=function()
                captures = captures + 1
                return {x=1, y=2}
            end},
            detector={detect=function(_, sample)
                assert.same({x=1, y=2}, sample)
                detections = detections + 1
                return current
            end},
        })

        assert.is_false(service:handle_opening_input(
            {_MOUSE_R_DOWN=true}, 1, {}))
        assert.same({0, 0}, {captures, detections})
        assert.is_true(service:handle_opening_input({
            _MOUSE_R=true,
            _MOUSE_R_DOWN=true,
            PAUSE=true,
        }, 1, {}))
        assert.same({1, 1}, {captures, detections})
        assert.equals(1, presentation.shown)
        assert.is_false(service:handle_opening_input(
            {_MOUSE_R=true}, 1, {}))
        assert.same({1, 1}, {captures, detections})
    end)

    it('leaves misses and blockers transparent', function()
        local harness = load_harness()
        local kind = 3
        local service = create_service(harness, {
            detector={detect=function() return {kind=kind} end},
        })

        assert.is_false(service:handle_opening_input(
            {_MOUSE_R=true}, 1, {}))
        kind = 2
        assert.is_false(service:handle_opening_input(
            {_MOUSE_R=true}, 1, {}))
        assert.is_false(service:is_open())
    end)

    it('consumes established targets and rolls back failed presentation',
            function()
        local harness = load_harness()
        local closed = 0
        local service = create_service(harness, {
            presentation_factory=function()
                return {
                    show=function() error('show failed') end,
                    close=function() closed = closed + 1 end,
                }
            end,
            detector={detect=function() return detection() end},
        })

        assert.is_true(service:handle_opening_input(
            {_MOUSE_R=true}, 1, {}))
        assert.is_true(service:is_disabled())
        assert.is_false(service:is_open())
        assert.equals(1, closed)
        assert.equals('presentation',
            service:get_diagnostics().last_failure.stage)
    end)

    it('attempts every cleanup when one close collaborator fails', function()
        local harness = load_harness()
        local factory, presentation = presenter_factory()
        local hook = hook_double()
        local service = create_service(harness, {
            input_hook=hook,
            presentation_factory=factory,
        })
        assert.is_true(service:open(detection()))
        service._state.session.close = function()
            error('session close failed')
        end

        assert.is_false(service:close())
        assert.equals(1, presentation.closed)
        assert.is_false(service:is_open())
        assert.is_true(service:is_disabled())
        assert.equals(1, hook.shutdown_count)
    end)

    it('delegates after pre-target failure and disables all ownership',
            function()
        local harness = load_harness()
        local hook = hook_double()
        local registrations = registration_double()
        local service = create_service(harness, {
            input_hook=hook,
            registrations=registrations,
            sampler={capture=function() error('sample failed') end},
        })

        assert.is_false(service:handle_opening_input(
            {_MOUSE_R=true}, 1, {}))
        assert.is_true(service:is_disabled())
        assert.is_true(registrations.disabled)
        assert.equals(1, hook.shutdown_count)
        assert.equals('opening resolution',
            service:get_diagnostics().last_failure.stage)
    end)

    it('closes before callback and reports errors without disabling', function()
        local harness = load_harness()
        local factory, presentation = presenter_factory()
        local service
        local calls = 0
        service = create_service(harness, {
            presentation_factory=factory,
        })
        assert.is_true(service:open(detection(function()
            calls = calls + 1
            assert.is_false(service:is_open())
            error('consumer failed')
        end)))

        assert.is_true(service:select(1))
        assert.equals(1, calls)
        assert.equals(1, presentation.closed)
        assert.is_false(service:is_open())
        assert.is_false(service:is_disabled())
        assert.equals(1,
            service:get_diagnostics().handler_failure_count)
        assert.is_true(service:open(detection()))
    end)

    it('starts discovery and hook integration through one owner', function()
        local harness = load_harness()
        local hook = hook_double()
        local registrations = registration_double()
        local service = create_service(harness, {
            input_hook=hook,
            registrations=registrations,
        })

        assert.is_true(service:start())
        assert.is_false(service:start())
        local roots = {[{}]=true}
        registrations.root_observer(roots)
        assert.is_equal(roots, hook.root_sets[1])
        assert.is_function(hook.handler)
        assert.is_function(hook.failure_handler)

        registrations.failure_observer('discovery failed')
        assert.is_true(service:is_disabled())
        assert.equals(1, hook.shutdown_count)
        assert.equals('root discovery',
            service:get_diagnostics().last_failure.stage)
    end)

    it('closes and clears registrations on world unload', function()
        local harness = load_harness()
        local factory = presenter_factory()
        local registrations = registration_double()
        local service = create_service(harness, {
            registrations=registrations,
            presentation_factory=factory,
        })
        service:start()
        assert.is_true(service:open(detection()))
        local callback =
            harness.process.onStateChange.dwarfuicore_context_menu

        callback(42)

        assert.is_false(service:is_open())
        assert.equals(1, registrations.clear_count)
        assert.equals(0, registrations.shutdown_count)
        assert.is_function(
            harness.process.onStateChange.dwarfuicore_context_menu)
        service:shutdown()
        assert.equals(1, registrations.shutdown_count)
        assert.is_nil(
            harness.process.onStateChange.dwarfuicore_context_menu)
    end)

    it('releases only its owned world-unload callback', function()
        local harness = load_harness()
        local service = create_service(harness)
        service:start()
        local foreign_callback = function() end
        harness.process.onStateChange.dwarfuicore_context_menu =
            foreign_callback

        service:shutdown()

        assert.is_equal(foreign_callback,
            harness.process.onStateChange.dwarfuicore_context_menu)
    end)

    it('preserves its compatible singleton state on module reload', function()
        local state = load_harness()
        local factory = presenter_factory()
        state.module.service:set_presentation_factory(factory)
        assert.is_true(state.module.service:open(detection()))
        local previous = state.module.service
        local previous_hook = state.hook

        state = load_harness(state)

        assert.is_equal(previous, state.module.service)
        assert.is_true(state.module.service:is_open())
        assert.is_false(state.module.service:is_disabled())
        assert.equals(1, state.module.service:get_diagnostics().open_count)
        assert.is_true(previous:is_open())
        assert.equals(0, previous_hook.shutdown_count)
    end)
end)
