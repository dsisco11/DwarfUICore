local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local BASE = 'src/scripts_modinstalled/dwarfuicore/'

---Creates one valid single-entry menu definition.
---@param label? string
---@return table
local function definition(label)
    return {
        entries={{
            label=label or 'Action',
            on_select=function() end,
        }},
    }
end

---Loads real registration, pointer, target, and detector collaborators.
---@return table
local function load_environment()
    local dfhack = {
        dwarfuicore={},
        timeout=function() end,
        gui={},
        screen={},
    }
    local _, numbers = module_loader.load(
        repo_root, BASE .. 'utils/numbers.lua')
    local _, immutable_enum = module_loader.load(
        repo_root, BASE .. 'utils/immutable_enum.lua')
    local _, definitions = module_loader.load(
        repo_root, BASE .. 'context_menu/definition.lua', {
            reqscript={['dwarfuicore/utils/numbers']=numbers},
        })
    local _, targets = module_loader.load(
        repo_root, BASE .. 'context_menu/target.lua', {
            reqscript={
                ['dwarfuicore/context_menu/definition']=definitions,
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfuicore/utils/numbers']=numbers,
            },
        })
    local _, pointer = module_loader.load(
        repo_root, BASE .. 'pointer.lua', {
            globals={dfhack=dfhack},
            reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
        })
    local state = {
        roots=setmetatable({}, {__mode='k'}),
        eligible=setmetatable({}, {__mode='k'}),
    }
    local resolver = {}

    ---Resolves one test owner through controlled current eligibility.
    ---@param owner any
    ---@return any|nil
    function resolver:resolve(owner)
        if state.eligible[owner] == false then return nil end
        return state.roots[owner]
    end

    local root_resolver = {
        ViewRootResolver={new=function() return resolver end},
    }
    local _, root_discovery = module_loader.load(
        repo_root, BASE .. 'context_menu/root_discovery.lua', {
            globals={dfhack=dfhack},
        })
    local map_dependencies = {
        ['dwarfuicore/context_menu/definition']=definitions,
        ['dwarfuicore/context_menu/target']=targets,
        ['dwarfuicore/utils/numbers']=numbers,
        ['dwarfuicore/view_root_resolver']=root_resolver,
    }
    local _, map_target = module_loader.load(
        repo_root, BASE .. 'context_menu/map_target.lua', {
            reqscript=map_dependencies,
        })
    local _, registration = module_loader.load(
        repo_root, BASE .. 'context_menu/registration.lua', {
            globals={dfhack=dfhack},
            reqscript={
                ['dwarfuicore/context_menu/definition']=definitions,
                ['dwarfuicore/context_menu/map_target']=map_target,
                ['dwarfuicore/context_menu/root_discovery']=root_discovery,
                ['dwarfuicore/context_menu/target']=targets,
                ['dwarfuicore/view_root_resolver']=root_resolver,
            },
        })
    local manager = registration.ContextMenuRegistrationManager.new{
        root_resolver=resolver,
        scheduler=function() end,
    }
    local _, detector_module = module_loader.load(
        repo_root, BASE .. 'context_menu/target_detector.lua', {
            reqscript={
                ['dwarfuicore/utils/immutable_enum']=immutable_enum,
                ['dwarfuicore/pointer']=pointer,
                ['dwarfuicore/context_menu/target']=targets,
            },
        })
    local _, sample_module = module_loader.load(
        repo_root, BASE .. 'context_menu/input_sample.lua', {
            globals={dfhack=dfhack},
            reqscript={['dwarfuicore/utils/numbers']=numbers},
        })
    return {
        DetectionKind=detector_module.ContextMenuDetectionKind,
        AnchorKind=targets.ContextMenuAnchorKind,
        TargetKind=targets.ContextMenuTargetKind,
        Policy=pointer.PointerPolicy,
        detector=detector_module.ContextMenuTargetDetector.new{
            registrations=manager,
        },
        manager=manager,
        samples=sample_module,
        state=state,
    }
end

---Creates a laid-out pointer view.
---@param policy dwarfui.PointerPolicy
---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param children? table[]
---@return table
local function view(policy, x, y, width, height, children)
    local result = {
        pointer_policy=policy,
        visible=true,
        active=true,
        subviews=children or {},
    }
    return widget_harness.set_frame(result, x, y, width, height)
end

---Creates one immutable controlled sample.
---@param env table
---@param x integer
---@param y integer
---@param map_position? table
---@return dwarfui.ContextMenuInputSample
local function sample(env, x, y, map_position)
    return env.samples.ContextMenuInputSampler.new{
        sample_screen_pointer=function() return x, y end,
        sample_map_pointer=function() return map_position end,
        has_map_demand=function() return map_position ~= nil end,
    }:capture()
end

---Makes one consumer eligible in a root.
---@param env table
---@param consumer table
---@param root table
local function present(env, consumer, root)
    env.state.roots[consumer] = root
    env.state.eligible[consumer] = true
end

describe('DwarfUICore context-menu target detector', function()
    it('uses reverse render order and the latest cross-root registration',
            function()
        local env = load_environment()
        local lower = view(env.Policy.TARGET, 1, 1, 8, 5)
        local upper = view(env.Policy.TARGET, 2, 2, 8, 5)
        local first_root = view(
            env.Policy.PASS, 0, 0, 20, 10, {lower, upper})
        local other = view(env.Policy.TARGET, 1, 1, 8, 5)
        local second_root = view(
            env.Policy.PASS, 0, 0, 20, 10, {other})
        present(env, lower, first_root)
        present(env, upper, first_root)
        present(env, other, second_root)
        env.manager:register(lower, definition('Lower'))
        env.manager:register(upper, definition('Upper'))
        env.manager:register(other, definition('Other'))

        local result = env.detector:detect(sample(env, 3, 3))

        assert.equals(env.DetectionKind.TARGET, result.kind)
        assert.is_equal(other, result.candidate.source)
        assert.equals(env.TargetKind.WIDGET, result.target.kind)
        assert.equals(result.candidate.identity,
            result.target.registration_identity)
        assert.equals(env.AnchorKind.SCREEN_POSITION, result.anchor.kind)
        assert.same({3, 3}, {
            result.anchor.screen_position.x,
            result.anchor.screen_position.y,
        })

        assert.is_false(env.manager:register(
            lower, definition('Lower updated')))
        result = env.detector:detect(sample(env, 3, 3))
        assert.is_equal(other, result.candidate.source)

        env.manager:unregister(other)
        result = env.detector:detect(sample(env, 3, 3))
        assert.is_equal(upper, result.candidate.source)
        assert.same({1, 1}, {result.local_x, result.local_y})
    end)

    it('respects clipping and lets a widget target beat another root blocker',
            function()
        local env = load_environment()
        local target = view(env.Policy.TARGET, 1, 1, 8, 5)
        target.frame_body = widget_harness.rect(
            1, 1, 8, 5, {x1=1, y1=1, x2=4, y2=5})
        local target_root = view(
            env.Policy.PASS, 0, 0, 20, 10, {target})
        local blocker = view(env.Policy.BLOCK, 0, 0, 20, 10)
        local blocker_root = view(
            env.Policy.PASS, 0, 0, 20, 10, {blocker})
        present(env, target, target_root)
        env.manager:register(target, definition())
        local map_owner = {}
        present(env, map_owner, blocker_root)
        local map_handle = env.manager:register_map_tile{
            owner=map_owner,
            pos={x=5, y=6, z=7},
            definition=definition('Map'),
        }
        assert.is_not_nil(map_handle)

        local result = env.detector:detect(
            sample(env, 3, 3, {x=5, y=6, z=7}))
        assert.equals(env.DetectionKind.TARGET, result.kind)
        assert.is_equal(target, result.candidate.source)

        result = env.detector:detect(
            sample(env, 6, 3, {x=5, y=6, z=7}))
        assert.equals(env.DetectionKind.BLOCKED, result.kind)
    end)

    it('treats an unregistered resolved control as a map blocker', function()
        local env = load_environment()
        local control = view(env.Policy.TARGET, 1, 1, 8, 5)
        local root = view(env.Policy.PASS, 0, 0, 20, 10, {control})
        local owner = {}
        present(env, owner, root)
        env.manager:register_map_tile{
            owner=owner,
            pos={x=5, y=6, z=7},
            definition=definition(),
        }

        local result = env.detector:detect(
            sample(env, 3, 3, {x=5, y=6, z=7}))

        assert.equals(env.DetectionKind.BLOCKED, result.kind)
        assert.is_nil(result.target)
    end)

    it('resolves only an exact eligible map tile and copies its world anchor',
            function()
        local env = load_environment()
        local owner = {}
        local root = view(env.Policy.PASS, 0, 0, 20, 10)
        present(env, owner, root)
        local handle = env.manager:register_map_tile{
            owner=owner,
            pos={x=5, y=6, z=7},
            definition=definition(),
        }
        local identity = env.manager:resolve_map_tile(handle).identity

        local miss = env.detector:detect(
            sample(env, 3, 3, {x=5, y=6, z=8}))
        assert.equals(env.DetectionKind.MISS, miss.kind)

        local result = env.detector:detect(
            sample(env, 3, 3, {x=5, y=6, z=7}))
        assert.equals(env.DetectionKind.TARGET, result.kind)
        assert.equals(env.TargetKind.MAP_TILE, result.target.kind)
        assert.equals(identity, result.target.registration_identity)
        assert.equals(env.AnchorKind.MAP_TILE, result.anchor.kind)
        assert.same({x=5, y=6, z=7}, result.anchor.map_position)

        result.candidate.pos.x = 99
        assert.same({x=5, y=6, z=7}, result.anchor.map_position)

        env.state.eligible[owner] = false
        assert.equals(env.DetectionKind.MISS,
            env.detector:detect(
                sample(env, 3, 3, {x=5, y=6, z=7})).kind)
    end)

    it('preserves duplicate precedence across atomic coordinate updates',
            function()
        local env = load_environment()
        local root = view(env.Policy.PASS, 0, 0, 20, 10)
        local first_owner, second_owner = {}, {}
        present(env, first_owner, root)
        present(env, second_owner, root)
        local first = env.manager:register_map_tile{
            owner=first_owner,
            pos={x=2, y=2, z=2},
            definition=definition('First'),
        }
        local second = env.manager:register_map_tile{
            owner=second_owner,
            pos={x=2, y=2, z=2},
            definition=definition('Second'),
        }
        local second_identity =
            env.manager:resolve_map_tile(second).identity
        local result = env.detector:detect(
            sample(env, 4, 4, {x=2, y=2, z=2}))
        assert.equals(second_identity, result.target.registration_identity)

        env.manager:update_map_tile(first, {
            pos={x=1, y=1, z=1},
            definition=definition('First moved away'),
        })
        env.manager:update_map_tile(first, {
            pos={x=2, y=2, z=2},
            definition=definition('First moved'),
        })

        result = env.detector:detect(
            sample(env, 4, 4, {x=2, y=2, z=2}))
        assert.equals(second_identity, result.target.registration_identity)

        env.state.eligible[second_owner] = false
        result = env.detector:detect(
            sample(env, 4, 4, {x=2, y=2, z=2}))
        assert.equals(
            env.manager:resolve_map_tile(first).identity,
            result.target.registration_identity)
    end)
end)
