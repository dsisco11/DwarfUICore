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
`dwarfuicore >= 0.2.0`. A dependent package must install a compatible
DwarfUICore package first; it must not bundle a second copy of DwarfUICore's
scripts. The integration setup tool verifies the installed root script against
the source package before it installs DwarfUI.

## Public service APIs

Import the public services module and construct a typed, namespace-bound API
with the exact supported contract major. DwarfUICore currently supports major
`1` for tooltip and context-menu services.

```lua
local services = reqscript('dwarfuicore/services')
local tooltip = services.TooltipServiceProvider:new(1, 'my-plugin')
local context_menu = services.ContextMenuServiceProvider:new(1, 'my-plugin')
```

The namespace is an ownership boundary, not a security principal. Use one
stable identifier for a plugin across its entrypoints, saves, and releases.
APIs using the same namespace share that namespace's registrations; other
namespaces use the same process-wide runtime but cannot operate on those
registrations. Each API object is immutable and non-owning. Call
`clear_namespace()` explicitly at a consumer-controlled reload, disable, or
teardown boundary when registrations must be removed.

`register()`, `update()`, and `unregister()` return `false` for ordinary
same-namespace absence. Invalid arguments, stale APIs or handles, foreign
handles, service health failures, and construction failures raise ordinary Lua
errors with stable prefixes and category tokens. Use `pcall` around provider
construction or API calls only when the consumer wants to recover from those
errors.

Tooltip collisions select the latest eligible contribution. Context-menu
contributions compose in registration order. Map registration handles are
opaque and only accept mutation through their creating service, namespace, and
contract major. The complete versioned data schema, callback contexts, error
categories, collision behavior, reload rules, and compatibility policy are in
[the service-provider contract](Docs/service-provider-api-proposal.md).

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

## Compatibility and updates

The services module and its two provider names are public compatibility
contracts. Internal implementation paths, registry order, private diagnostics,
and handle representation are not. Compatible changes retain the same contract
major; incompatible method, data, ownership, collision, handle, or error
semantics require a new major.

One DwarfUICore installation must resolve in a running DFHack process. Verify
package contents offline, then start a fresh process or run the explicit
development command `dwarfuicore reload` after an update. Replacing a subset
of files or switching script paths while a generation is active is unsupported.

The release intentionally has no compatibility adapter or compatibility
namespace for the replaced direct APIs. Provider-consuming DwarfUI requires
DwarfUICore 0.2.0 or later, and older DwarfUI is not compatible with this
provider-bearing release. Migrating independent consumer plugins remains
separate work.
