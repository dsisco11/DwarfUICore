local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local DEFINITION_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/definition.lua'
local IMMUTABLE_ENUM_PATH =
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua'
local NUMBERS_PATH =
    'src/scripts_modinstalled/dwarfuicore/utils/numbers.lua'
local TARGET_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/target.lua'

local _, numbers = module_loader.load(repo_root, NUMBERS_PATH)
local _, immutable_enum =
    module_loader.load(repo_root, IMMUTABLE_ENUM_PATH)
local _, definitions = module_loader.load(repo_root, DEFINITION_PATH, {
    reqscript={
        ['dwarfuicore/utils/numbers']=numbers,
    },
})
local _, immutable_proxy = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')
local _, contracts = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })
local _, namespaces = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')
local _, identities = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/identity.lua', {
        globals={dfhack={}},
        reqscript={
            ['dwarfuicore/service_provider/contracts']=contracts,
            ['dwarfuicore/service_provider/namespace']=namespaces,
            ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
        },
    })
local _, targets = module_loader.load(repo_root, TARGET_PATH, {
    reqscript={
        ['dwarfuicore/context_menu/definition']=definitions,
        ['dwarfuicore/service_provider/identity']=identities,
        ['dwarfuicore/utils/immutable_enum']=immutable_enum,
        ['dwarfuicore/utils/numbers']=numbers,
    },
})

---Creates one complete test-only composite context-menu identity.
---@param local_identity integer
---@return table
local function identity(local_identity)
    return {runtime_generation=1, service_kind=2, contract_major=1,
        namespace='tests', local_identity=local_identity}
end

---Returns one validated definition with a caller-supplied handler.
---@param handler fun(context: table)
---@return table
local function definition(handler)
    return definitions.validate{
        title='Actions',
        entries={{
            label='Select',
            on_select=handler,
        }},
    }
end

---Creates one map-target open session.
---@param handler fun(context: table)
---@param source table
---@param root table
---@param owner? table
---@return dwarfui.ContextMenuOpenSession
local function map_session(handler, source, root, owner)
    return targets.ContextMenuOpenSession.new{
        definition=definition(handler),
        target=targets.ContextMenuTargetDescriptor.new(
            targets.ContextMenuTargetKind.MAP_TILE, identity(7)),
        anchor=targets.ContextMenuAnchorDescriptor.map_tile(
            {x=10, y=20, z=30}, 4, 5),
        source=source,
        source_root=root,
        owner=owner,
    }
end

describe('context-menu targets and sessions', function()
    it('exports distinct immutable numeric enums', function()
        assert.equals('number', type(targets.ContextMenuTargetKind.WIDGET))
        assert.equals('number', type(targets.ContextMenuTargetKind.MAP_TILE))
        assert.is_not_equal(targets.ContextMenuTargetKind.WIDGET,
            targets.ContextMenuTargetKind.MAP_TILE)
        assert.equals('number',
            type(targets.ContextMenuAnchorKind.SCREEN_POSITION))
        assert.equals('number',
            type(targets.ContextMenuAnchorKind.MAP_TILE))
        assert.equals('number', type(targets.ContextMenuSessionState.OPEN))
        assert.equals('number', type(targets.ContextMenuSessionState.CLOSED))

        assert.has_error(function()
            targets.ContextMenuTargetKind.WIDGET = 99
        end)
        assert.has_error(function()
            targets.ContextMenuAnchorKind.NEW_KIND = 99
        end)
        assert.has_error(function()
            targets.ContextMenuSessionState.OPEN = 99
        end)
    end)

    it('copies target and both anchor descriptor kinds', function()
        local target = targets.ContextMenuTargetDescriptor.new(
            targets.ContextMenuTargetKind.WIDGET, identity(3))
        local screen =
            targets.ContextMenuAnchorDescriptor.screen_position(8, 9)
        local map_position = {x=1, y=2, z=3}
        local map =
            targets.ContextMenuAnchorDescriptor.map_tile(map_position, 8, 9)
        map_position.x = 99

        assert.same({
            kind=targets.ContextMenuTargetKind.WIDGET,
            registration_identity=identity(3),
        }, target)
        assert.same({x=8, y=9}, screen.screen_position)
        assert.same({x=1, y=2, z=3}, map.map_position)
        assert.is_nil(target.source)
        assert.is_nil(target.owner)
        assert.is_nil(target.handle)
    end)

    it('uses descriptor constructors as copy constructors', function()
        local target = targets.ContextMenuTargetDescriptor.new(
            targets.ContextMenuTargetKind.MAP_TILE, identity(8))
        local anchor = targets.ContextMenuAnchorDescriptor.map_tile(
            {x=1, y=2, z=3}, 4, 5)
        local target_copy =
            targets.ContextMenuTargetDescriptor.new(target)
        local anchor_copy =
            targets.ContextMenuAnchorDescriptor.new(anchor)

        target.registration_identity = identity(9)
        assert.has_error(function() anchor.screen_position.x = 9 end)
        assert.has_error(function() anchor.map_position.x = 9 end)
        assert.equals(8, target_copy.registration_identity.local_identity)
        assert.same({x=4, y=5}, anchor_copy.screen_position)
        assert.same({x=1, y=2, z=3}, anchor_copy.map_position)
    end)

    it('isolates definition, target, anchor, and returned context copies',
            function()
        local source, root, owner = {}, {}, {}
        local captured
        local validated = definition(function(context)
            captured = context
        end)
        local target = targets.ContextMenuTargetDescriptor.new(
            targets.ContextMenuTargetKind.MAP_TILE, identity(7))
        local position = {x=10, y=20, z=30}
        local anchor = targets.ContextMenuAnchorDescriptor.map_tile(
            position, 4, 5)
        local session = targets.ContextMenuOpenSession.new{
            definition=validated,
            target=target,
            anchor=anchor,
            source=source,
            source_root=root,
            owner=owner,
        }

        validated.title = 'Mutated'
        validated.entries[1].label = 'Mutated'
        target.registration_identity = identity(99)
        assert.has_error(function() anchor.screen_position.x = 99 end)
        assert.has_error(function() anchor.map_position.x = 99 end)
        position.x = 99

        local session_definition = session:get_definition_snapshot()
        local session_target = session:get_target_descriptor()
        local session_anchor = session:get_anchor_descriptor()
        assert.equals('Actions', session_definition.title)
        assert.equals('Select', session_definition.entries[1].label)
        assert.equals(7, session_target.registration_identity.local_identity)
        assert.same({x=4, y=5}, session_anchor.screen_position)
        assert.same({x=10, y=20, z=30}, session_anchor.map_position)

        session_definition.title = 'External mutation'
        session_target.registration_identity = identity(100)
        assert.has_error(function() session_anchor.map_position.x = 100 end)
        assert.equals('Actions', session:get_definition_snapshot().title)
        assert.equals(7,
            session:get_target_descriptor().registration_identity.local_identity)
        assert.equals(10,
            session:get_anchor_descriptor().map_position.x)

        local context = assert(session:create_selection_context())
        assert.has_error(function() context.screen_position.x = 200 end)
        assert.has_error(function() context.map_position.x = 200 end)
        assert.equals(4,
            session:create_selection_context().screen_position.x)
        assert.equals(10,
            session:create_selection_context().map_position.x)
        assert.is_nil(captured)
    end)

    it('closes before invoking once with a complete live context', function()
        local source, root, owner = {}, {}, {}
        local session
        local calls = {}
        session = map_session(function(context)
            table.insert(calls, context)
            assert.equals(targets.ContextMenuSessionState.CLOSED,
                session:get_state())
        end, source, root, owner)

        local isolated = session:create_selection_context()
        assert.has_error(function() isolated.screen_position.x = 99 end)
        assert.has_error(function() isolated.map_position.x = 99 end)
        assert.is_true(session:select(1))
        assert.is_false(session:select(1))
        assert.equals(1, #calls)
        local context = calls[1]
        assert.same({x=4, y=5}, context.screen_position)
        assert.same({x=10, y=20, z=30}, context.map_position)
        assert.is_equal(source, context.source)
        assert.is_equal(root, context.source_root)
        assert.is_equal(owner, context.owner)
        assert.is_nil(context.registration_identity)
        assert.is_nil(context.target_kind)
        assert.is_nil(context.anchor_kind)
    end)

    it('retains ordinary handler closure semantics', function()
        local external = {count=0}
        local source, root = {}, {}
        local session = map_session(function()
            external.count = external.count + 1
        end, source, root)

        external.count = 10
        assert.is_true(session:select(1))
        assert.equals(11, external.count)
    end)

    it('combines ordered contributions and dispatches each entry to its source',
            function()
        local first_source, second_source, root = {}, {}, {}
        local calls = {}
        local first = definition(function(context)
            table.insert(calls, {'first', context.source})
        end)
        local second = definition(function(context)
            table.insert(calls, {'second', context.source})
        end)
        local session = targets.ContextMenuOpenSession.new{
            definition=first,
            target=targets.ContextMenuTargetDescriptor.new(
                targets.ContextMenuTargetKind.WIDGET, identity(1)),
            anchor=targets.ContextMenuAnchorDescriptor.screen_position(4, 5),
            source=first_source,
            source_root=root,
            contributions={{identity=identity(1), definition=first,
                source=first_source}, {identity=identity(2), definition=second,
                source=second_source}},
        }

        assert.equals(2, #session:get_definition_snapshot().entries)
        assert.is_true(session:select(2))
        assert.same({'second', second_source}, calls[1])
    end)

    it('remains closed when a selected handler raises', function()
        local source, root = {}, {}
        local session = map_session(function()
            error('handler failed')
        end, source, root)

        assert.has_error(function() session:select(1) end, 'handler failed')
        assert.equals(targets.ContextMenuSessionState.CLOSED,
            session:get_state())
    end)

    it('weakly owns source widgets, map owners, and source roots', function()
        for _, lost_reference in ipairs{'source', 'owner', 'source_root'} do
            local calls = 0

            ---Creates a session while retaining every source except one.
            ---@return dwarfui.ContextMenuOpenSession
            ---@return table
            local function create_with_one_lost_reference()
                local source, root, owner = {}, {}, {}
                local session = map_session(function()
                    calls = calls + 1
                end, source, root, owner)
                local retained = {}
                if lost_reference ~= 'source' then retained.source = source end
                if lost_reference ~= 'source_root' then
                    retained.source_root = root
                end
                if lost_reference ~= 'owner' then retained.owner = owner end
                return session, retained
            end

            local session, retained = create_with_one_lost_reference()
            collectgarbage('collect')
            collectgarbage('collect')

            assert.is_false(session:select(1), lost_reference)
            assert.equals(0, calls)
            assert.equals(targets.ContextMenuSessionState.CLOSED,
                session:get_state())
            assert.is_nil(session:create_selection_context())
            assert.is_truthy(retained)
        end
    end)
end)
