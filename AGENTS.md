# Repository Guide

## Project

Ashoholic is a World of Warcraft addon for Project Ebonhold on WotLK 3.3.5. Its addon manifest targets interface version 30300, so keep addon Lua compatible with Lua 5.1.

## Start Here

- `AddOns/` contains the active addon sources. `AddOns/Ashoholic/` is the main Ashoholic addon; implement new functionality there.
- `AddOns/Ashoholic/Ashoholic.toc` is the active load manifest and shows the main Lua load order.
- `AddOns/Ashoholic/PreviewUI.lua` contains the sample-data preview, opened with `/ash preview`; it is not live character tracking. `/ash` opens the live window in `UI/Roster.lua`, with `UI/CharacterDetails.lua`, `UI/Progression.lua`, and `UI/Raids.lua` rendering their own views. `UI.lua` supplies shared live widgets and formatting.
- `AddOns/Ashoholic/Data/Schema.lua` defines the approved saved-data contract; `Data/Store.lua` initializes, reads, and writes the new database. `Data/Encounters.lua` shares the dungeon names and expansion mappings between the live and preview watchlists. `Collectors/Character.lua` saves basics, `Collectors/Run.lua` saves run currencies, `Collectors/Currencies.lua` saves account currencies, `Collectors/Ebonhold.lua` routes Prestige, Torment, contracts (offerings/Soul Anchor), and Echo-build snapshots, and `Collectors/Raids.lua` saves complete raid loot updates. All companion access stays in `Integrations/ProjectEbonhold.lua`. Other feature modules remain scaffolding, not the archived addon's full behavior.
- `Archive/` contains the old Ashoholic implementation, including tracking, raid metadata, widgets, Nexus integration, and the offline sync/merge scripts. Use it for reference or inspiration; it is not the active addon.
- `AddOns/FastSwap/` is a separate addon and character-selection hook. Keep its installation helper separate from character-data syncing.
- `AddOns/SharedMedia/` supplies the bundled media addon.

## Live Addon Architecture

Build the live addon from the approved `PreviewUI.lua` design. Keep `AddOns/Ashoholic/` as one addon with one SavedVariables table, `AshoholicDB`; do not split it into DataStore-style addons.

Use these internal layers as files are added or moved:

- `Core/`: startup, events, and slash commands.
- `Data/`: field definitions, saved data, migrations, and the read/write API.
- `Collectors/`: reads WoW and ProjectEbonhold data, then saves it through `Data/`.
- `Sync/`: offline imports and in-game sharing; writes only through `Data/`.
- `UI/`: main window, shared widgets, and one file per tab.
- `Preview/`: the sample-data preview, kept separate from live data.

Data flows Game -> Collectors -> Data -> UI. UI code must not read game data or `AshoholicDB` directly. Collectors and Sync must not write `AshoholicDB` except through `Data/`.

Store character records as Account -> Realm -> Character -> information plus last-updated time, regardless of whether data came from logging in, in-game sharing, or an offline import.

`AddOns/Ashoholic/Data/Schema.lua` is the approved data contract: saved layout, field sources, account vs character scope, and rules. Read it before changing saved data, and update it (raising `Schema.VERSION` with a migration when the layout changes) in the same change. Key rules: unknown values are `nil`, never 0; every data group has its own `updatedAt` from `time()` (never save `GetTime()`); merges keep the newer group, not the whole character.

Run currencies, contracts, Echo builds, and raid loot have independent freshness. Raid snapshots are saved only after a complete companion reply, including all chunks; each lock retains its server-reported end time. Dungeon names are a watchlist, and their character status is Unknown. Torment stores actual per-character unlocks, not an account-wide tier or an assumption that all lower tiers are unlocked. Prestige stores complete server replies, never a mixture of a new result count and an old reward.

Split `PreviewUI.lua` gradually, one tab at a time as it becomes live. Update the `.toc` load order with each move.

## Working Style

- Ask the user before implementing new ideas, features, or design changes that have not already been approved.
- Write beginner-friendly Lua with clear names and many explanatory comments, including file purpose, data flow, WoW event timing, and non-obvious logic. Prioritize correct, working code when readability and correctness conflict.

## ProjectEbonhold Dependency

`vendor/ProjectEbonhold/` is source for the companion in-game addon, not the Ebonhold server backend. Ashoholic calls into its client-side APIs and server request protocol. Work in Ashoholic's own call sites first; inspect the companion source only when an issue depends on an API or protocol detail that cannot be established locally. Do not modify the companion source unless the task explicitly asks for it.

Never call `ProjectEbonhold.onEventReceived` from Ashoholic: it stores one handler per server message ID, so a second registration replaces ProjectEbonhold's own handler. Read its public state and functions, use its `OnChanged` listener APIs, or `hooksecurefunc` its public functions instead. When a needed server reply is handled only privately, `Integrations/ProjectEbonhold.lua` may read it passively with Ashoholic's own `CHAT_MSG_ADDON` listener, ignoring unrecognized layouts. It may also read text shown in ProjectEbonhold's named frames, but only when the meaning is certain (Rule 5 e in `Data/Schema.lua`). Ashoholic does not send server requests, except the documented once-per-session Soul Ash tree loadout request (Rule 5 in `Data/Schema.lua`).
## Versioning and Publishing

- Before pushing a release-bound change or publishing a release, read the current branch and `## Version:` in `AddOns/Ashoholic/Ashoholic.toc`. Raise the version question early enough to include any approved bump in a release-bound commit or PR merge.
- Ask the user whether to bump the addon version and which exact version to use; suggest a branch-appropriate next version. Wait for their answer before proceeding unless they already explicitly chose a version or confirmed no bump for this publication. Do not bump automatically or ask again for an already confirmed publication.
- The manifest version is manual and is not changed automatically by package builds. When handing off a push for the user to perform, include the version reminder if it has not been resolved.
- Before merging development work into `main` for a stable release, confirm the final version and review manifests and package entries for files that are not intended for the release.

## Validation

- The user performs testing in-game by default. After implementing a change, provide concise in-game verification steps and wait for the user's results.
- Ask for explicit permission before running tests or validation checks, including syntax checks, package checks, and ad hoc or mocked test scripts. Do not run them unless the user approves or explicitly requests them.
- Report checks as not run when permission has not been granted; do not imply that in-game behavior has been verified without the user's confirmation.

Available checks, to run only with the user's permission:

- `python tools/check_lua.py` parses tracked Ashoholic Lua files with a Lua 5.1 compiler, excluding vendored companion source. It checks syntax, not runtime behavior, and requires `luac5.1` or a Lua 5.1 `luac` on PATH.
- `python tools/check_package.py` checks tracked addon manifests, referenced files, and package contents.

When changing load behavior, check the relevant `.toc` file and preserve its ordering and referenced paths.
