# DwarfUI Busted tests

Run the test suites from the repository root with:

```powershell
.\tools\Run-UnitTests.ps1
```

Lua 5.3 or newer and a matching LuaRocks installation must be available on
`PATH`. The runner follows the active toolchain while Lua 5.3 remains the
required compatibility test for DFHack. The runner pins Busted `2.3.0-1`
and Windows-toolchain-compatible LuaSystem `0.3.0-2` in the ignored repository-
local `.luarocks/` tree, installing them and the remaining dependencies through
LuaRocks when absent. It deterministically discovers `test_*.lua` and
`*_test.lua` specs and forwards remaining arguments to Busted.

`tests/run.lua` is a Busted helper that derives test and production paths from
its own location and validates the runner's discovered file list.
Support modules provide isolated DFHack-style module loading and only the
widget behavior required by the tooltip port. tests and `.luarocks/` are
outside `src/` and are not included in published packages.

Live product tests default to recursively discovered `*.ds.lua` files beneath
`tests/`, executed by the installed DwarfSpec dependency declared in the
repository rockspec. Consumers can replace that discovery glob without
changing the optional selection glob.
DwarfUI owns only its tooltip specs, registration support source,
configuration, and tooltip-state command. Run them with:

```powershell
dwarfspec run tests/tooltip/tooltip_spec.ds.lua
dwarfspec run tests/tooltip/tooltip_overlay_spec.ds.lua
dwarfspec run tests/tooltip/tooltip_overlay_registration_integration_spec.lua
```

The first two commands mount components without installing scripts. The last
command is the separate real overlay discovery and registration integration.

The local Busted unit runner does not discover or execute live DwarfSpec files.
