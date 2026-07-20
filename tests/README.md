# DwarfUI Busted tests

Run the test suites from the repository root with:

```powershell
.\tools\Run-Unittests.ps1
```

Lua and LuaRocks must be available on `PATH`. The runner pins Busted `2.3.0-1`
and Windows-toolchain-compatible LuaSystem `0.3.0-2` in the ignored repository-
local `.luarocks/` tree, installing them and the remaining dependencies through
LuaRocks when absent. It deterministically discovers `test_*.lua` and
`*_test.lua` specs and forwards remaining arguments to Busted.

`tests/run.lua` is a Busted helper that derives test and production paths from
its own location and validates the runner's discovered file list.
Support modules provide isolated DFHack-style module loading and only the
widget behavior required by the tooltip port. tests and `.luarocks/` are
outside `src/` and are not included in published packages.
