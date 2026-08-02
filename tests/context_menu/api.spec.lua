local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local API_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/api.lua'

---Loads the public facade with an observable registration module.
---@return table
---@return table
local function load_api()
    local calls = {}
    local registration = {}
    for _, name in ipairs{
            'register', 'update', 'unregister', 'register_map_tile',
            'update_map_tile', 'unregister_map_tile',
        } do
        registration[name] = function(...)
            calls[#calls + 1] = {name=name, arguments={...}}
            return name
        end
    end
    local service = {
        get_diagnostics=function() return {started=true} end,
    }
    local _, api = module_loader.load(repo_root, API_PATH, {
        reqscript={
            ['dwarfuicore/context_menu/registration']=registration,
            ['dwarfuicore/context_menu/screen']={},
            ['dwarfuicore/context_menu/service']={service=service},
        },
    })
    return api, calls
end

describe('DwarfUICore context-menu public API', function()
    it('forwards the complete registration-driven surface', function()
        local api, calls = load_api()
        local widget, definition, handle = {}, {}, {}

        assert.equals('register', api.register(widget, definition))
        assert.equals('update', api.update(widget, definition))
        assert.equals('unregister', api.unregister(widget))
        assert.equals('register_map_tile',
            api.register_map_tile{owner=widget})
        assert.equals('update_map_tile',
            api.update_map_tile(handle, {definition=definition}))
        assert.equals('unregister_map_tile',
            api.unregister_map_tile(handle))

        assert.equals(6, #calls)
        assert.equals(widget, calls[1].arguments[1])
        assert.equals(handle, calls[6].arguments[1])
    end)

    it('exposes started service diagnostics without an open API', function()
        local api = load_api()

        assert.is_true(api.get_diagnostics().started)
        assert.is_nil(api.open)
        assert.is_nil(api.replace)
    end)
end)
