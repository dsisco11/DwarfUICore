# DwarfUICore

DwarfUICore is the reusable, process-wide UI infrastructure for DFHack Lua
plugins. It owns the generic tooltip, context-menu, pointer, registration, and
presentation systems that were extracted from DwarfUI.

## Current ownership

DwarfUICore owns reusable UI behavior that is not specific to a DwarfUI
feature. This includes tooltip and context-menu rendering, pointer polling and
dispatch, map projection, shared classes and utilities, widget extensions, and
the associated registration and presentation infrastructure.

DwarfUI is a feature and component library that depends on this project. It
continues to own its feature-specific overlays, widgets, commands, and user
workflows.

## Installation and compatibility

Install DwarfUICore as its own DFHack mod package before installing DwarfUI or
another dependent plugin. The package identifier is `dwarfuicore`.

The current DwarfUI package declares a runtime dependency of
`dwarfuicore >= 0.1.0`. A dependent package must install a compatible
DwarfUICore package first; it must not bundle a second copy of DwarfUICore's
scripts. The integration setup tool verifies the installed root script against
the source package before it installs DwarfUI.

## Current module entrypoints

The extracted tooltip and context-menu APIs remain available through these
current compatibility entrypoints:

```lua
local tooltip = reqscript('dwarfuicore/tooltip/api')
local context_menu = reqscript('dwarfuicore/context_menu/api')
```

These facades load their prerequisites and preserve the extracted runtime
state. They are not the proposed service-provider interface.

Running `dwarfuicore` validates the installed package. Running
`dwarfuicore reload` is the explicit development-only reload command. Ordinary
`reqscript` loading never reloads DwarfUICore or clears script environments.
DwarfUI's reload command reloads only DwarfUI-owned modules; it does not reload
DwarfUICore.

## Development and integration checks

Run project checks from this repository root:

```powershell
.\tools\Run-UnitTests.ps1
.\tools\Check-LuaSyntax.ps1 -IncludeTests
.\tools\Publish.ps1
```

To run DwarfUI feature tests against this checkout, provide the source root
explicitly:

```powershell
..\DwarfUI\tools\Run-UnitTests.ps1 -DwarfUICoreSource .
```

The environment alternative is `DWARFUICORE_SOURCE`. Package integration can
be checked from DwarfUI with `tools/Setup-CoreIntegration.ps1`, which installs
DwarfUICore before DwarfUI into an isolated mod tree.

## Future public service-provider contract

[The service-provider proposal](Docs/service-provider-api-proposal.md) is
owned and maintained in this repository. It is a proposed, unimplemented
architecture: no provider classes, consumer namespaces, composite identities,
exact contract-version negotiation, immutable service handles, or new
collision rules exist yet. Do not create a service-provider task list or
migrate independent consumer plugins until that contract is approved.

Migrating independent consumer plugins remains separate future work.
