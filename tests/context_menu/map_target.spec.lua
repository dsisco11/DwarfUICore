local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local DEFINITION_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/definition.lua'
local IMMUTABLE_ENUM_PATH =
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua'
local MAP_TARGET_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/map_target.lua'
local NUMBERS_PATH =
    'src/scripts_modinstalled/dwarfuicore/utils/numbers.lua'
local TARGET_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/target.lua'

---Returns one caller-owned context-menu definition.
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

---Requires an operation to fail with one literal diagnostic fragment.
---@param fragment string
---@param callback function
local function assert_fails_with(fragment, callback)
    local ok, failure = pcall(callback)
    assert.is_false(ok)
    assert.is_truthy(tostring(failure):find(fragment, 1, true), failure)
end

---Loads an isolated exact-map registry with dynamic root eligibility.
---@return table harness
local function load_harness()
    local dfhack = {dwarfuicore={service_provider_runtime={generation=1}}}
    local _, numbers = module_loader.load(repo_root, NUMBERS_PATH)
    local _, immutable_enum =
        module_loader.load(repo_root, IMMUTABLE_ENUM_PATH)
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
            globals={dfhack=dfhack},
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/namespace']=namespaces,
                ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
            },
        })
    local _, definitions = module_loader.load(
        repo_root, DEFINITION_PATH, {
            reqscript={['dwarfuicore/utils/numbers']=numbers},
        })
    local _, targets = module_loader.load(repo_root, TARGET_PATH, {
        reqscript={
            ['dwarfuicore/context_menu/definition']=definitions,
            ['dwarfuicore/service_provider/identity']=identities,
            ['dwarfuicore/utils/immutable_enum']=immutable_enum,
            ['dwarfuicore/utils/numbers']=numbers,
        },
    })
    local state = {
        eligible=setmetatable({}, {__mode='k'}),
        roots=setmetatable({}, {__mode='k'}),
        attachments=setmetatable({}, {__mode='k'}),
    }
    local resolver = {
        resolve=function(_, owner)
            return state.eligible[owner] and state.roots[owner] or nil
        end,
        find_root=function(_, owner)
            return state.attachments[owner]
        end,
    }
    local _, module = module_loader.load(repo_root, MAP_TARGET_PATH, {
        globals={dfhack=dfhack},
        reqscript={
            ['dwarfuicore/context_menu/definition']=definitions,
            ['dwarfuicore/context_menu/target']=targets,
            ['dwarfuicore/utils/numbers']=numbers,
            ['dwarfuicore/service_provider/contracts']=contracts,
            ['dwarfuicore/service_provider/identity']=identities,
            ['dwarfuicore/service_provider/namespace']=namespaces,
            ['dwarfuicore/view_root_resolver']={
                ViewRootResolver={new=function() return resolver end},
            },
        },
    })
    local registry = module.ContextMenuMapTargetRegistry.new{
        allocator=identities.get_process_allocator(),
        runtime_generation=1,
        root_resolver=resolver,
        find_attachment_root=function(owner)
            return state.attachments[owner]
        end,
    }

    ---Makes one owner currently eligible in one root.
    ---@param owner table
    ---@param root table
    local function present(owner, root)
        state.eligible[owner] = true
        state.roots[owner] = root
        state.attachments[owner] = root
    end

    return {
        definitions=definitions,
        module=module,
        present=present,
        registry=registry,
        state=state,
    }
end

describe('context-menu exact map targets', function()
    it('copies position and definition into a weak-owner registration',
            function()
        local harness = load_harness()
        local owner, root = {}, {}
        harness.present(owner, root)
        local position = {x=1, y=2, z=3}
        local caller_definition = definition('Before')
        local handle = harness.registry:register{
            owner=owner,
            pos=position,
            definition=caller_definition,
        }
        position.x = 99
        caller_definition.entries[1].label = 'Mutated'

        local candidate = assert(
            harness.registry:detect{x=1, y=2, z=3})
        assert.equals(1, candidate.identity.local_identity)
        assert.equals(1, candidate.sequence)
        assert.equals(handle, candidate.source)
        assert.equals(owner, candidate.owner)
        assert.equals(root, candidate.root)
        assert.same({x=1, y=2, z=3}, candidate.pos)
        assert.equals('Before',
            candidate:get_definition_snapshot().entries[1].label)
        assert.is_true(harness.registry:contains(handle))
    end)

    it('resolves an open identity only while attached to its opening root',
            function()
        local harness = load_harness()
        local owner, root = {}, {}
        harness.present(owner, root)
        local handle = harness.registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            definition=definition(),
        }
        local identity = assert(harness.registry:resolve(handle)).identity

        assert.equals(root,
            harness.registry:resolve_identity_attached(identity, root).root)
        harness.state.attachments[owner] = {}
        assert.is_nil(
            harness.registry:resolve_identity_attached(identity, root))
        harness.state.attachments[owner] = nil
        assert.is_nil(
            harness.registry:resolve_identity_attached(identity, root))
    end)

    it('packs every signed-16 component into distinct exact integer keys',
            function()
        local harness = load_harness()
        local owner, root = {}, {}
        harness.present(owner, root)
        local positions = {
            {x=-32768, y=-32768, z=-32768},
            {x=32767, y=32767, z=32767},
            {x=-1, y=0, z=0},
            {x=0, y=-1, z=0},
            {x=0, y=0, z=-1},
        }
        local handles = {}
        for index, position in ipairs(positions) do
            handles[index] = harness.registry:register{
                owner=owner,
                pos=position,
                definition=definition(('Position %d'):format(index)),
            }
        end

        for index, position in ipairs(positions) do
            local candidate = assert(harness.registry:detect(position))
            assert.equals(('Position %d'):format(index),
                candidate:get_definition_snapshot().entries[1].label)
        end
        assert.equals(#positions,
            harness.registry:get_diagnostics().coordinate_count)
        assert.equals(#positions, #handles)
    end)

    it('rejects coordinates outside the signed-16 DF coordinate domain',
            function()
        local harness = load_harness()
        local owner, root = {}, {}
        harness.present(owner, root)
        for _, position in ipairs{
            {x=-32769, y=0, z=0},
            {x=32768, y=0, z=0},
            {x=0, y=-32769, z=0},
            {x=0, y=32768, z=0},
            {x=0, y=0, z=-32769},
            {x=0, y=0, z=32768},
        } do
            assert_fails_with(
                'requires signed 16-bit integer x, y, and z', function()
                harness.registry:register{
                    owner=owner,
                    pos=position,
                    definition=definition(),
                }
            end)
            assert_fails_with(
                'requires signed 16-bit integer x, y, and z', function()
                harness.registry:detect(position)
            end)
        end
        assert.equals(0, harness.registry:registration_count())
        assert.equals(0,
            harness.registry:get_diagnostics().registration_sequence)
    end)

    it('uses latest original sequence and preserves it across updates',
            function()
        local harness = load_harness()
        local first_owner, second_owner, root = {}, {}, {}
        harness.present(first_owner, root)
        harness.present(second_owner, root)
        local first = harness.registry:register{
            owner=first_owner,
            pos={x=1, y=1, z=1},
            definition=definition('First'),
        }
        local second = harness.registry:register{
            owner=second_owner,
            pos={x=2, y=2, z=2},
            definition=definition('Second'),
        }
        local first_identity =
            harness.registry:resolve(first).identity
        local second_identity =
            harness.registry:resolve(second).identity

        assert.is_true(harness.registry:update(first, {
            pos={x=2, y=2, z=2},
            definition=definition('First moved'),
        }))
        local winner = assert(
            harness.registry:detect{x=2, y=2, z=2})
        assert.equals(second_identity, winner.identity)
        assert.equals('Second',
            winner:get_definition_snapshot().entries[1].label)
        assert.equals(first_identity,
            harness.registry:resolve(first).identity)
        assert.equals(1, harness.registry:resolve(first).sequence)
        assert.equals(2, harness.registry:resolve(second).sequence)

        harness.state.eligible[second_owner] = false
        winner = assert(harness.registry:detect{x=2, y=2, z=2})
        assert.equals(first_identity, winner.identity)
        assert.equals('First moved',
            winner:get_definition_snapshot().entries[1].label)
    end)

    it('composes same-tile namespaces and clears only the requested one',
            function()
        local harness = load_harness()
        local first_owner, second_owner, root = {}, {}, {}
        harness.present(first_owner, root)
        harness.present(second_owner, root)
        local first = harness.registry:register('alpha', {
            owner=first_owner,
            pos={x=7, y=8, z=9},
            definition=definition('Alpha'),
        }, 1)
        local second = harness.registry:register('beta', {
            owner=second_owner,
            pos={x=7, y=8, z=9},
            definition=definition('Beta'),
        }, 1)

        local contributions = harness.registry:detect_contributions{
            x=7, y=8, z=9}
        assert.equals(2, #contributions)
        assert.equals('alpha', contributions[1].identity.namespace)
        assert.equals('Alpha',
            contributions[1]:get_definition_snapshot().entries[1].label)
        assert.equals('beta', contributions[2].identity.namespace)
        assert.equals('Beta',
            contributions[2]:get_definition_snapshot().entries[1].label)
        assert.has_error(function()
            harness.registry:unregister('alpha', second, 1)
        end, 'DwarfUICore context-menu map handle belongs to another service domain.')

        local removed = harness.registry:clear_namespace('alpha', 1)
        assert.equals(1, #removed)
        assert.is_false(harness.registry:contains(first))
        assert.is_true(harness.registry:contains(second))
        contributions = harness.registry:detect_contributions{x=7, y=8, z=9}
        assert.equals(1, #contributions)
        assert.equals('beta', contributions[1].identity.namespace)
        assert.equals('Beta',
            contributions[1]:get_definition_snapshot().entries[1].label)
    end)

    it('leaves prior state intact after any failed atomic update', function()
        local harness = load_harness()
        local owner, root = {}, {}
        harness.present(owner, root)
        local handle = harness.registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            definition=definition('Before'),
        }
        local identity = harness.registry:resolve(handle).identity

        assert.has_error(function()
            harness.registry:update(handle, {
                pos={x=9, y=9, z=9},
                definition={
                    entries={{label='Invalid'}},
                },
            })
        end)
        assert.has_error(function()
            harness.registry:update(handle, {
                pos={x=9.5, y=9, z=9},
                definition=definition('Invalid position'),
            })
        end)
        assert.has_error(function()
            harness.registry:update(handle, {
                pos={x=32768, y=9, z=9},
                definition=definition('Out-of-range position'),
            })
        end)

        local candidate = assert(
            harness.registry:detect{x=1, y=2, z=3})
        assert.equals(identity, candidate.identity)
        assert.same({x=1, y=2, z=3}, candidate.pos)
        assert.equals('Before',
            candidate:get_definition_snapshot().entries[1].label)
        assert.is_nil(harness.registry:detect{x=9, y=9, z=9})
    end)

    it('evaluates owner-root eligibility dynamically without re-registration',
            function()
        local harness = load_harness()
        local owner, first_root, second_root = {}, {}, {}
        harness.present(owner, first_root)
        local handle = harness.registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            definition=definition(),
        }

        assert.equals(first_root, harness.registry:resolve(handle).root)
        harness.state.eligible[owner] = false
        assert.is_nil(harness.registry:resolve(handle))
        assert.is_nil(harness.registry:detect{x=1, y=2, z=3})
        harness.present(owner, second_root)
        assert.equals(second_root, harness.registry:resolve(handle).root)
        assert.equals(second_root,
            harness.registry:detect{x=1, y=2, z=3}.root)
    end)

    it('collects dead handles and dead owners and prunes their coordinates',
            function()
        local harness = load_harness()
        local owner, root = {}, {}
        harness.present(owner, root)
        local handle = harness.registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            definition=definition(),
        }
        local weak_handle = setmetatable({handle}, {__mode='v'})
        handle = nil
        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_nil(weak_handle[1])
        assert.equals(0, harness.registry:registration_count())
        assert.equals(0,
            harness.registry:get_diagnostics().coordinate_count)

        local second_owner = {}
        harness.present(second_owner, root)
        local live_handle = harness.registry:register{
            owner=second_owner,
            pos={x=4, y=5, z=6},
            definition=definition(),
        }
        local weak_owner = setmetatable({second_owner}, {__mode='v'})
        harness.state.eligible[second_owner] = nil
        harness.state.roots[second_owner] = nil
        harness.state.attachments[second_owner] = nil
        second_owner = nil
        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_nil(weak_owner[1])
        assert.equals(0, harness.registry:registration_count())
        assert.is_false(harness.registry:contains(live_handle))
    end)

    it('supports explicit unregister and unknown update behavior', function()
        local harness = load_harness()
        local owner, root = {}, {}
        harness.present(owner, root)
        local handle = harness.registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            definition=definition(),
        }

        assert.is_true(harness.registry:unregister(handle))
        assert.is_false(harness.registry:unregister(handle))
        assert.is_false(harness.registry:update(handle, {
            pos={x=4, y=5, z=6},
            definition=definition(),
        }))
        assert.equals(0, harness.registry:registration_count())
    end)

    it('clears registrations, coordinate buckets, and precedence sequence',
            function()
        local harness = load_harness()
        local owner, root = {}, {}
        harness.present(owner, root)
        harness.registry:register{
            owner=owner,
            pos={x=1, y=2, z=3},
            definition=definition(),
        }

        assert.equals(1, #harness.registry:clear())
        local diagnostics = harness.registry:get_diagnostics()
        assert.equals(0, diagnostics.registration_count)
        assert.equals(0, diagnostics.coordinate_count)
        assert.equals(0, diagnostics.registration_sequence)
        assert.equals(0, #harness.registry:clear())
    end)
end)
