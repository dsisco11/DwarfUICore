# DwarfUICore instructions

- Never specify the `autoResolutionMs` parameter when calling the request_user_input tool.
- Always add LuaDoc comments for all methods and classes.
- Do not mention "phases" in code or public documentation except planning documents.

## Project conventions

- Start production modules with `--@ module=true` and export through the DFHack module environment.
- Load project modules with `reqscript('path/without/extension')`; use `require()` only for DFHack or external libraries.
- Add reload-managed modules to `dwarfuicore/module_registry.lua` in dependency order and update registry/package tests.
- Use immutable numeric `---@enum` tables for every closed discriminator set.

## Coding Conventions

- Avoid global variables.
- Prefix private members with an underscore.
- Use class-like tables to encapsulate state and behavior.
- Do not create copy-methods for class-like tables. Instead, the classes constructor should accept a table of values to initialize the instance.
- Avoid creating loose functions. Instead, define them as methods on a class-like table.
