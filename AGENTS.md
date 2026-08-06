# Overview

This is a DFHack Lua plugin project (Wiki: <https://docs.dfhack.org/en/stable/docs/dev/Lua%20API.html>).
All built/test tasks are to be run using the scripts in the `./tools/` directory.

## Coding Conventions

- Adhere to the DRY principle (Don't Repeat Yourself).
- Adhere to the KISS principle (Keep It Stupid Simple), but not at the expense of clarity and good architecture/abstractions.
- Avoid global variables.
- Prefix private members with an underscore.
- Use class-like tables to encapsulate state and behavior.
- Do not create copy-methods for class-like tables. Instead, the classes constructor should accept a table of values to initialize the instance.
- Avoid creating loose functions. Instead, define them as methods on a class-like table.
- Use immutable numeric `---@enum` tables for every closed discriminator set; never use loose strings or magic numbers.
- Always organize LUA code into LUA modules unless it is a test file or a raw script.
- If a LUA source module is part of the DFHack plugin, and if it executes code on load, then it must be a DFHack module (i.e., it must start with `--@ module=true` and export through the DFHack module environment, and it must be imported via `reqscript`).
