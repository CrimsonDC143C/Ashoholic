# Repository Guide

## Project

Ashoholic is a World of Warcraft addon for Project Ebonhold on WotLK 3.3.5. Its addon manifest targets interface version 30300, so keep addon Lua compatible with Lua 5.1.

## Start Here

- `Ashoholic.toc` is the Ashoholic load manifest and shows the main Lua load order.
- `Core.lua` owns addon initialization, saved variables, events, chat commands, character tracking, and integrations such as raid resets and hourly entries.
- `Characters.lua` builds and organizes the character roster data.
- `UI.lua` creates the roster window and configuration interface.
- `Themes.lua` defines built-in and custom themes.
- `RaidData.lua` contains raid and lockout metadata; `HourlyWidget.lua` handles the hourly-entry widget.
- `Minimap.lua` and `NexusDock.lua` integrate with the minimap and optional Nexus panel.
- `FastSwap/` is a separate addon and character-selection hook. `AshoholicSync.ps1` and `AshoholicMerge.ps1` handle local multi-account data syncing.

## ProjectEbonhold Dependency

`vendor/ProjectEbonhold/` is source for the companion in-game addon, not the Ebonhold server backend. Ashoholic calls into its client-side APIs and server request protocol. Work in Ashoholic's own call sites first; inspect the companion source only when an issue depends on an API or protocol detail that cannot be established locally. Do not modify the companion source unless the task explicitly asks for it.

## Validation

- `python tools/check_lua.py` parses tracked Ashoholic Lua files with a Lua 5.1 compiler, excluding vendored companion source. It checks syntax, not runtime behavior, and requires `luac5.1` or a Lua 5.1 `luac` on PATH.
- `python tools/check_package.py` checks tracked addon manifests, referenced files, and package contents.

When changing load behavior, check the relevant `.toc` file and preserve its ordering and referenced paths.
