-- Live DwarfUI reload isolation from the DwarfUICore service runtime.

local widgets = require('gui.widgets')

---Returns the current DwarfUICore service-runtime generation.
---@return integer generation
local function get_core_generation()
    return reqscript('dwarfuicore/service_provider/runtime').validate().generation
end

describe('live DwarfUI reload isolation', function()
    it('preserves an independent Core namespace and generation', function()
        local namespace = 'dwarfui-reload-isolation-live'
        local api = reqscript('dwarfuicore/services')
            .ContextMenuServiceProvider:new(1, namespace)
        local handle = api:register_map_tile{
            owner=widgets.Panel{}, pos={x=0, y=0, z=0},
            definition={entries={{label='Independent reload probe',
                on_select=function() end}}},
        }
        local generation = get_core_generation()

        local ok, failure = xpcall(function()
            dfhack.run_command('dwarfui', 'reload')
            ds.wait_frames(2)

            assert.equals(generation, get_core_generation())
            assert.is_true(api:unregister_map_tile(handle))
            handle = nil
        end, debug.traceback)

        if handle then api:unregister_map_tile(handle) end
        assert.is_true(ok, failure)
    end)
end)
