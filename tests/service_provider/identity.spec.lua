local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, immutable_proxy = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')
local _, identity = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/identity.lua', {
        reqscript={
            ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
        },
    })

describe('service-provider identity primitives', function()
    it('allocates unique composite identities and independent sequences', function()
        local process_state = {}
        local allocator = identity.get_process_allocator(process_state)
        assert.equals(allocator, identity.get_process_allocator(process_state))
        local first = allocator:allocate_identity(1, 1, 1, 'alpha')
        local second = allocator:allocate_identity(1, 1, 1, 'alpha')
        local cross_domain = allocator:allocate_identity(2, 2, 3, 'beta')
        assert.equals(1, first.local_identity)
        assert.equals(2, second.local_identity)
        assert.equals(3, cross_domain.local_identity)
        assert.same({runtime_generation=2, service_kind=2, contract_major=3,
            namespace='beta', local_identity=3}, cross_domain)
        assert.equals(1, allocator:allocate_sequence())
        assert.equals(2, allocator:allocate_sequence())
        assert.same({next_identity=3, next_sequence=2}, allocator:snapshot())
    end)

    it('creates opaque immutable handles with external backing storage', function()
        local allocator = identity.IdentityAllocator.new()
        local private = allocator:allocate_identity(7, 2, 1, 'plugin')
        local handle = identity.create_map_handle(private)
        assert.is_true(identity.is_map_handle(handle))
        assert.equals(private, identity.get_map_handle_identity(handle))
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
        assert.is_false(identity.is_map_handle({}))
    end)

    it('isolates immutable families and does not retain collected proxies', function()
        local first = immutable_proxy.new_factory('first', {ping=function()
            return 'pong'
        end})
        local second = immutable_proxy.new_factory('second')
        local backing = {secret=true}
        local object = first:create(backing)
        backing.owner = object
        assert.equals('pong', object:ping())
        assert.is_true(first:is_instance(object))
        assert.is_false(second:is_instance(object))
        local weak = setmetatable({object}, {__mode='v'})
        object = nil
        backing = nil
        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_nil(weak[1])
    end)
end)
