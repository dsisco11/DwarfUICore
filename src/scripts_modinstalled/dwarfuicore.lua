--@ module=true

-- Public DwarfUICore provider root and explicit development command entrypoint.

local command = reqscript('dwarfuicore/command')
local immutable_proxy = reqscript('dwarfuicore/service_provider/immutable_proxy')
local tooltip_provider = reqscript('dwarfuicore/service_provider/tooltip_provider')
local context_menu_provider = reqscript(
    'dwarfuicore/service_provider/context_menu_provider')

---Public closed provider namespace. Its backing storage remains private.
---@class dwarfuicore.ServiceProviders
services = immutable_proxy.new_factory('services', {}, {
    TooltipServiceProvider=tooltip_provider.get_provider(),
    ContextMenuServiceProvider=context_menu_provider.get_provider(),
}):create({})

if not dfhack_flags.module then command.main(...) end
