# Project instructions

## Project overview

This repository contains personal World of Warcraft Retail addons and related standalone tools.

The addons are written in Lua and use the World of Warcraft addon API.

## Repository structure

- `addons/` contains addons loaded by World of Warcraft.
- Each addon has its own directory and `.toc` file.
- `tools/` contains standalone Lua 5.4 command-line tools.
- `docs/` contains project notes and plans.

## World of Warcraft addons

- Target World of Warcraft Retail.
- Do not assume normal Lua 5.4 APIs are available inside WoW.
- Use only Lua functionality supported by the WoW client and documented WoW APIs.
- Preserve the addon folder and `.toc` file naming convention: `RSH_<AddonName>`.
- Ensure every Lua file required by an addon is listed in its `.toc` file.
- Keep SavedVariables names stable unless the task explicitly includes data migration.
- Avoid global variables except those required by WoW, such as SavedVariables and slash-command registrations.
- Prefer local functions and local variables.
- Do not add external Lua libraries unless explicitly requested.

## Standalone tools

- Tools under `tools/` run with Lua 5.4 on Ubuntu.
- They may use the standard Lua 5.4 library.
- Keep command-line error messages clear.
- Preserve support for paths containing spaces.

## Coding style

- Use four spaces for indentation.
- Use descriptive names.
- Keep functions small and focused.
- Prefer straightforward code over unnecessary abstraction.
- Comments should explain why something is needed, not restate obvious code.
- Use English for source code, comments, identifiers, and user-facing addon text.

## Validation

For standalone Lua files, run a syntax check when Lua 5.4 is available:

```bash
lua5.4 -e "assert(loadfile('path/to/file.lua'))"
```

For WoW addon files:

- Check that `.toc` filenames match the actual files.
- Check that SavedVariables declared in `.toc` match the Lua code.
- Explain any parts that can only be tested inside World of Warcraft.

## Change policy

- Make only changes relevant to the requested task.
- Do not rename addons, database variables, slash commands, or files without explicitly noting migration consequences.
- Do not commit generated SavedVariables, logs, backups, or local game data.
- Summarize changed files and validation performed after completing a task.
