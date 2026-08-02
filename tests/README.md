# DwarfUICore tests

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
`*.spec.lua` specs and forwards remaining arguments to Busted.

`tests/run.lua` is a Busted helper that derives test and production paths from
its own location and validates the runner's discovered file list.
Support modules provide isolated DFHack-style module loading. Tests and
`.luarocks/` are outside `src/` and are not included in published packages.

Live product tests are recursively discovered from `*.ds.lua` files beneath
`tests/` and executed by the installed DwarfSpec dependency declared in the
repository rockspec. The tooltip and context-menu tests exercise the systems
owned by DwarfUICore.

```powershell
dwarfspec list
```

The local Busted unit runner does not discover or execute live DwarfSpec files.
