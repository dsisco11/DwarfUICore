local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local api_path = 'src/scripts_modinstalled/dwarfuicore/tooltip/api.lua'

---Loads the public API with isolated registration and runtime collaborators.
---@return table api
---@return table state
local function load_api()
    local state = {}
    local registration = {
        register=function(widget)
            state.registered = widget
            return true
        end,
        unregister=function(widget)
            state.unregistered = widget
            return true
        end,
        register_map_tile=function(options)
            state.map_registration = options
            return state.handle
        end,
        update_map_tile=function(handle, update)
            state.map_update_handle = handle
            state.map_update = update
            return true
        end,
        unregister_map_tile=function(handle)
            state.map_unregistration = handle
            return true
        end,
        get_diagnostics=function()
            return {registration_count=2}
        end,
    }
    registration.bind=function(namespace, contract_major)
        state.namespace = namespace
        state.contract_major = contract_major
        return {
            register=function(_, widget)
                return registration.register(widget)
            end,
            unregister=function(_, widget)
                return registration.unregister(widget)
            end,
            register_map_tile=function(_, options)
                return registration.register_map_tile(options)
            end,
            update_map_tile=function(_, handle, update)
                return registration.update_map_tile(handle, update)
            end,
            unregister_map_tile=function(_, handle)
                return registration.unregister_map_tile(handle)
            end,
        }
    end
    local runtime = {
        presenter={
            get_diagnostics=function()
                return {active=true}
            end,
        },
    }
    local _, api = module_loader.load(repo_root, api_path, {
        reqscript={
            ['dwarfuicore/tooltip/registration']=registration,
            ['dwarfuicore/tooltip/runtime']=runtime,
        },
    })
    return api, state
end

describe('DwarfUICore tooltip public API', function()
    it('delegates widget registration lifecycle', function()
        local api, state = load_api()
        local widget = {}

        assert.is_true(api.register(widget))
        assert.is_equal(widget, state.registered)
        assert.is_true(api.unregister(widget))
        assert.is_equal(widget, state.unregistered)
        assert.equals('dwarfuicore', state.namespace)
        assert.equals(1, state.contract_major)
    end)

    it('delegates exact map-tile registration lifecycle', function()
        local api, state = load_api()
        local handle = {}
        state.handle = handle
        local options = {
            owner={},
            pos={x=11, y=22, z=3},
            tooltip='Exact tile',
        }
        local update = {
            pos={x=12, y=23, z=4},
            tooltip=nil,
        }

        assert.is_equal(handle, api.register_map_tile(options))
        assert.is_equal(options, state.map_registration)
        assert.is_true(api.update_map_tile(handle, update))
        assert.is_equal(handle, state.map_update_handle)
        assert.is_equal(update, state.map_update)
        assert.is_true(api.unregister_map_tile(handle))
        assert.is_equal(handle, state.map_unregistration)
    end)

    it('combines registration and presentation diagnostics', function()
        local api = load_api()
        assert.same({
            registration_count=2,
            presentation={active=true},
        }, api.get_diagnostics())
    end)
end)
