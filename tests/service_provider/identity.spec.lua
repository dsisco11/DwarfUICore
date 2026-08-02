local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, immutable_proxy = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')
local _, immutable_enum = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
local _, contracts = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })
local _, namespace = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')

---Loads identity primitives over one test-controlled DFHack process record.
---@param process table
---@return table identity
local function load_identity(process)
    local _, identity = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/identity.lua', {
        globals={dfhack=process},
        reqscript={
            ['dwarfuicore/service_provider/contracts']=contracts,
            ['dwarfuicore/service_provider/namespace']=namespace,
            ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
        },
    })
    return identity
end

describe('service-provider identity primitives', function()
    it('allocates unique composite identities and independent sequences', function()
        local process = {}
        local identity = load_identity(process)
        local allocator = identity.get_process_allocator()
        assert.equals(allocator, identity.get_process_allocator({}))
        local first = allocator:allocate_identity(1,
            contracts.ServiceKind.TOOLTIP, 1, 'alpha')
        local second = allocator:allocate_identity(1,
            contracts.ServiceKind.TOOLTIP, 1, 'alpha')
        local cross_domain = allocator:allocate_identity(2,
            contracts.ServiceKind.CONTEXT_MENU, 3, 'beta')
        assert.equals(1, first.local_identity)
        assert.equals(2, second.local_identity)
        assert.equals(3, cross_domain.local_identity)
        assert.same({runtime_generation=2,
            service_kind=contracts.ServiceKind.CONTEXT_MENU, contract_major=3,
            namespace='beta', local_identity=3}, cross_domain)
        assert.equals(1, allocator:allocate_sequence())
        assert.equals(2, allocator:allocate_sequence())
        assert.same({version=1, next_identity=3, next_sequence=2},
            allocator:snapshot())
        assert.same({version=1, next_identity=3, next_sequence=2},
            process.dwarfuicore.service_provider_identity)
    end)

    it('preserves plain counters across module reconstruction', function()
        local process = {}
        local first = load_identity(process).get_process_allocator()
        first:allocate_identity(1, contracts.ServiceKind.TOOLTIP, 1, 'alpha')
        assert.equals(1, first:allocate_sequence())
        local second = load_identity(process).get_process_allocator()
        local allocated = second:allocate_identity(2,
            contracts.ServiceKind.CONTEXT_MENU, 2, 'beta')
        assert.equals(2, allocated.local_identity)
        assert.equals(2, second:allocate_sequence())
        assert.is_nil(process.dwarfuicore.identity_allocator)
    end)

    it('keeps identities unique across every composite domain dimension', function()
        local allocator = load_identity({}).get_process_allocator()
        local identities = {
            allocator:allocate_identity(1, contracts.ServiceKind.TOOLTIP,
                1, 'alpha'),
            allocator:allocate_identity(2, contracts.ServiceKind.TOOLTIP,
                1, 'alpha'),
            allocator:allocate_identity(1, contracts.ServiceKind.CONTEXT_MENU,
                1, 'alpha'),
            allocator:allocate_identity(1, contracts.ServiceKind.TOOLTIP,
                2, 'alpha'),
            allocator:allocate_identity(1, contracts.ServiceKind.TOOLTIP,
                1, 'beta'),
        }
        local seen = {}
        for _, value in ipairs(identities) do
            assert.is_nil(seen[value.local_identity])
            seen[value.local_identity] = true
        end
        assert.equals(5, #identities)
    end)

    it('copy-constructs and compares composite identities', function()
        local identity = load_identity({})
        local original = {
            runtime_generation=3,
            service_kind=contracts.ServiceKind.CONTEXT_MENU,
            contract_major=2,
            namespace='plugin',
            local_identity=9,
        }
        local copied = identity.CompositeIdentity.new(original)

        assert.same(original, copied)
        assert.is_not_equal(original, copied)
        original.namespace = 'changed'
        assert.equals('plugin', copied.namespace)
        assert.is_true(identity.CompositeIdentity.equals(copied, {
            runtime_generation=3,
            service_kind=contracts.ServiceKind.CONTEXT_MENU,
            contract_major=2,
            namespace='plugin',
            local_identity=9,
        }))
        assert.is_false(identity.CompositeIdentity.equals(copied, {
            runtime_generation=3,
            service_kind=contracts.ServiceKind.CONTEXT_MENU,
            contract_major=2,
            namespace='plugin',
            local_identity=10,
        }))
        assert.is_false(identity.CompositeIdentity.equals(copied, {}))
    end)

    it('rejects malformed state, invalid domains, and counter exhaustion', function()
        local process = {dwarfuicore={service_provider_identity={
            version=1, next_identity=math.maxinteger, next_sequence=0}}}
        local allocator = load_identity(process).get_process_allocator()
        assert.has_error(function()
            allocator:allocate_identity(1, contracts.ServiceKind.TOOLTIP,
                1, 'plugin')
        end, 'DwarfUICore process identity counter is exhausted.')
        process.dwarfuicore.service_provider_identity.next_identity = 0
        process.dwarfuicore.service_provider_identity.next_sequence =
            math.maxinteger
        assert.has_error(function() allocator:allocate_sequence() end,
            'DwarfUICore process sequence counter is exhausted.')
        process.dwarfuicore.service_provider_identity = {
            version=1, next_identity=0, next_sequence=0, unexpected=true}
        assert.has_error(function() allocator:allocate_sequence() end,
            'DwarfUICore process identity state contains an unknown field.')
        process.dwarfuicore.service_provider_identity = setmetatable({
            version=1, next_identity=0, next_sequence=0}, {__index={}})
        assert.has_error(function() allocator:allocate_sequence() end,
            'DwarfUICore process identity state must be plain data.')
        process.dwarfuicore.service_provider_identity = nil
        assert.has_error(function()
            allocator:allocate_identity(0, contracts.ServiceKind.TOOLTIP,
                1, 'plugin')
        end, 'DwarfUICore runtime generation must be a positive integer.')
        assert.has_error(function()
            allocator:allocate_identity(1, 999, 1, 'plugin')
        end, 'DwarfUICore service kind is invalid.')
    end)

    it('creates opaque immutable handles with external backing storage', function()
        local identity = load_identity({})
        local allocator = identity.get_process_allocator()
        local private = allocator:allocate_identity(7,
            contracts.ServiceKind.CONTEXT_MENU, 1, 'plugin')
        local handle = identity.create_map_handle(private)
        assert.is_true(identity.is_map_handle(handle))
        assert.same(private, identity.get_map_handle_identity(handle))
        assert.same({}, (function()
            local exposed = {}
            for key, value in pairs(handle) do exposed[key] = value end
            return exposed
        end)())
        assert.is_false(getmetatable(handle))
        assert.is_nil(handle.namespace)
        assert.has_error(function() handle.namespace = 'other' end,
            'DwarfUICore map registration handle is immutable.')
        assert.has_error(function() handle.update = function() end end,
            'DwarfUICore map registration handle is immutable.')
        private.namespace = 'changed'
        assert.equals('plugin',
            identity.get_map_handle_identity(handle).namespace)
        local inspected = identity.get_map_handle_identity(handle)
        inspected.namespace = 'changed-again'
        assert.equals('plugin',
            identity.get_map_handle_identity(handle).namespace)
        rawset(handle, 'namespace', 'self-sabotage')
        assert.equals('self-sabotage', handle.namespace)
        assert.equals('plugin',
            identity.get_map_handle_identity(handle).namespace)
        assert.is_false(identity.is_map_handle({}))
    end)

    it('rejects malformed and incomplete handle identities', function()
        local identity = load_identity({})
        for _, malformed in ipairs({
                {},
                {runtime_generation=1, service_kind=1, contract_major=1,
                    namespace='plugin', local_identity=0},
                {runtime_generation=1, service_kind=999, contract_major=1,
                    namespace='plugin', local_identity=1},
                {runtime_generation=1, service_kind=1, contract_major=1,
                    namespace='Plugin', local_identity=1},
                {runtime_generation=1, service_kind=1, contract_major=1,
                    namespace='plugin', local_identity=1, extra=true},
                setmetatable({}, {__index={runtime_generation=1,
                    service_kind=1, contract_major=1, namespace='plugin',
                    local_identity=1}, __pairs=function()
                    return next, {}, nil
                end}),
            }) do
            assert.has_error(function() identity.create_map_handle(malformed) end)
        end
        local fabricated = {runtime_generation=1,
            service_kind=contracts.ServiceKind.TOOLTIP, contract_major=1,
            namespace='plugin', local_identity=1}
        assert.has_error(function() identity.create_map_handle(fabricated) end,
            'DwarfUICore map handle identity was not allocated by this runtime.')
        local allocated = identity.get_process_allocator():allocate_identity(
            1, contracts.ServiceKind.TOOLTIP, 1, 'plugin')
        allocated.namespace = 'other'
        assert.has_error(function() identity.create_map_handle(allocated) end,
            'DwarfUICore allocated map handle identity was modified.')
        allocated.namespace = 'plugin'
        local handle = identity.create_map_handle(allocated)
        assert.has_error(function() identity.create_map_handle(allocated) end,
            'DwarfUICore map handle identity was not allocated by this runtime.')
        assert.is_true(identity.is_map_handle(handle))
    end)

    it('isolates immutable families and does not retain collected proxies', function()
        local first
        first = immutable_proxy.new_factory('first', {
            ping=function(self)
                return first:get_backing(self).secret
            end,
        })
        local second = immutable_proxy.new_factory('second')
        local backing = {secret='original'}
        local object = first:create(backing)
        local other = first:create({secret='other'})
        backing.owner = object
        assert.equals('original', object:ping())
        assert.is_true(first:is_instance(object))
        assert.is_false(second:is_instance(object))
        assert.has_error(function() object.ping = function() end end,
            'DwarfUICore first is immutable.')
        assert.has_error(function() setmetatable(object, {}) end)
        rawset(object, 'ping', function() return 'self-sabotage' end)
        assert.equals('self-sabotage', object:ping())
        assert.equals('original', first:get_backing(object).secret)
        assert.equals('other', other:ping())
        debug.setmetatable(object, {})
        assert.equals('original', first:get_backing(object).secret)
        assert.equals('other', other:ping())
        local weak = setmetatable({object}, {__mode='v'})
        object = nil
        backing = nil
        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_nil(weak[1])
    end)
end)
