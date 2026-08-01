# DwarfUICore

Reusable process-wide UI infrastructure for DFHack Lua plugins.

This repository is being established by extracting the current tooltip,
context-menu, pointer, projection, widget-extension, and shared runtime systems
from DwarfUI. The extraction preserves existing behavior and internal module
contracts. The later public service-provider design is intentionally not yet
implemented.

## Development

Run project checks from the repository root:

```powershell
.\tools\Run-UnitTests.ps1
.\tools\Check-LuaSyntax.ps1 -Includetests
.\tools\Publish.ps1
```

`dwarfuicore reload` is reserved for the explicit development reload command.
Ordinary module loading must never perform development reload or clear script
environments.
