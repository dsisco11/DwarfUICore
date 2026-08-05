local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, immutable_enum = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
local _, contracts = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })
local _, namespaces = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')
local _, immutable_proxy = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')
local _, identities = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/identity.lua', {
        globals={dfhack={}},
        reqscript={
            ['dwarfuicore/service_provider/contracts']=contracts,
            ['dwarfuicore/service_provider/namespace']=namespaces,
            ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
        },
    })

describe('service-provider value copy constructors', function()
    it('copies and validates exact map and screen positions', function()
        local map_input = {x=10, y=-20, z=30}
        local screen_input = {x=4, y=5}
        local map = identities.MapTilePosition.new(map_input)
        local screen = identities.ScreenPosition.new(screen_input)
        map_input.x, screen_input.x = 99, 99

        assert.same({x=10, y=-20, z=30}, map)
        assert.same({x=4, y=5}, screen)
        assert.has_error(function()
            identities.MapTilePosition.new{x=32768, y=0, z=0}
        end)
        assert.has_error(function() identities.ScreenPosition.new{x=1.5, y=0} end)
        assert.has_error(function() map.x = 99 end,
            'DwarfUICore map tile positions are immutable.')
        assert.has_error(function() screen.x = 99 end,
            'DwarfUICore screen positions are immutable.')
    end)

    it('copies only the approved public callback-context fields', function()
        local source, root, owner = {}, {}, {}
        local input = {screen_position={x=4, y=5},
            map_position={x=10, y=20, z=30}, source=source,
            source_root=root, owner=owner}
        local context = identities.ContextMenuSelectionContext.new(input)
        input.screen_position.x, input.map_position.x = 99, 99

        assert.same({x=4, y=5}, context.screen_position)
        assert.same({x=10, y=20, z=30}, context.map_position)
        assert.is_equal(source, context.source)
        assert.is_equal(root, context.source_root)
        assert.is_equal(owner, context.owner)
        assert.is_nil(context.registration_identity)
        assert.is_nil(context.target_kind)
        assert.is_nil(context.anchor_kind)
        assert.has_error(function()
            identities.ContextMenuSelectionContext.new{
                screen_position={x=0, y=0}, source=source, source_root=root,
                registration_identity={},
            }
        end)
    end)
end)
