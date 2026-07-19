# DwarfUI LuaUnit tests

Run the test suites from the repository root with:

```powershell
.\Tools\Run-UnitTests.ps1
```

Lua and LuaRocks must be available on `PATH`. The runner pins LuaUnit `3.5-1`
in the ignored repository-local `.luarocks/` tree, installing it through
LuaRocks when absent. It deterministically discovers `test_*.lua` and
`*_test.lua` suites and forwards remaining arguments to LuaUnit.

`Tests/run.lua` derives test and production paths from its own location.
Support modules provide isolated DFHack-style module loading and only the
widget behavior required by the tooltip port. Tests and `.luarocks/` are
outside `src/` and are not included in published packages.
