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
local _, weak_store = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/weak_store.lua')

describe('service-provider weak registration storage', function()
    it('does not retain keys through cyclic callbacks or identity indexes', function()
        local store = weak_store.WeakRegistrationStore.new()
        local key = {}
        local environment = {key=key}
        environment.callback = function() return environment.key end
        store:set(key, 1, {local_identity=1, callback=environment.callback})
        assert.equals(1, store:count())
        assert.is_table(store:get_by_identity(1))
        local weak = setmetatable({key}, {__mode='v'})
        key = nil
        environment = nil
        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_nil(weak[1])
        assert.equals(0, store:count())
        assert.is_nil(store:get_by_identity(1))
    end)

    it('does not let a live API-like object own a map handle', function()
        local store = weak_store.WeakRegistrationStore.new()
        local allocator = identity.IdentityAllocator.new()
        local handle = identity.create_map_handle(
            allocator:allocate_identity(1, 1, 1, 'plugin'))
        local environment = {handle=handle}
        environment.callback = function() return environment.handle end
        store:set(handle, 1, {callback=environment.callback})
        local api = immutable_proxy.new_factory('api'):create({store=store})
        local weak = setmetatable({handle}, {__mode='v'})
        handle = nil
        environment = nil
        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_table(api)
        assert.is_nil(weak[1])
        assert.equals(0, store:count())
    end)

    it('keeps target and contribution sequences stable and independent', function()
        local allocator = identity.IdentityAllocator.new()
        local store = weak_store.WidgetTargetStore.new(allocator)
        local widget = {}
        local target, alpha, created = store:register(widget, 'alpha', {})
        assert.is_true(created)
        assert.equals(1, target)
        assert.equals(2, alpha)
        local same_target, same_alpha, replaced =
            store:register(widget, 'alpha', {replacement=true})
        assert.is_false(replaced)
        assert.equals(target, same_target)
        assert.equals(alpha, same_alpha)
        local beta_target, beta = store:register(widget, 'beta', {})
        assert.equals(target, beta_target)
        assert.equals(3, beta)
        assert.is_true(store:remove(widget, 'alpha'))
        assert.same({target, beta}, {store:get_sequences(widget, 'beta')})
        assert.is_true(store:remove(widget, 'beta'))
        local new_target, new_alpha = store:register(widget, 'alpha', {})
        assert.equals(4, new_target)
        assert.equals(5, new_alpha)
    end)

    it('does not retain a widget through its contribution callback graph', function()
        local allocator = identity.IdentityAllocator.new()
        local store = weak_store.WidgetTargetStore.new(allocator)
        local widget = {}
        local environment = {widget=widget}
        environment.callback = function() return environment.widget end
        store:register(widget, 'plugin', {callback=environment.callback})
        local weak = setmetatable({widget}, {__mode='v'})
        widget = nil
        environment = nil
        collectgarbage('collect')
        collectgarbage('collect')
        assert.is_nil(weak[1])
    end)
end)
