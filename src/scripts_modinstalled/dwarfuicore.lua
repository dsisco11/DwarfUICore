--@ module=true

-- DwarfUICore validation and explicit development command entrypoint.

local command = reqscript('dwarfuicore/command')

-- Remove the retired provider export when this command is re-executed in a
-- script environment created by an earlier DwarfUICore version.
services = nil

if not dfhack_flags.module then command.main(...) end
