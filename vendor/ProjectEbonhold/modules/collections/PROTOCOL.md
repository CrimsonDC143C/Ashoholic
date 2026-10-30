# Collections data protocol

How the visual shell gets its data, over the ProjectEbonhold addon-message
protocol (`ProjectEbonhold.sendToServer(CS.*, body)` /
`ProjectEbonhold.onEventReceived(SS.*, fn)`).

## Data split

| Data | Source |
|---|---|
| Full mount / pet / appearance catalogs | **Client static** (`data/`, generated from the world DB) |
| Which mounts/pets are owned | **Native** (`GetCompanionInfo`, = `character_spell`) + server set |
| Which appearances are collected | **Server** (`SEND_COLLECTED_APPEARANCES`) |
| Current transmog per slot | **Server** (`SEND_TRANSMOG_SLOTS`) |
| Equipped items (base look) | **Native** (`GetInventoryItemID`) |

## Identifier model

- mount = **mount spell id**  · pet = **companion spell id**
- appearance **visual = item displayid** (what the server's collection stores);
  a catalog visual is collected iff its displayid is in the sent set. Source
  items (itemIDs sharing a displayid) are catalog-only, for tooltips.
- transmog = **slot id → applied item entry**.

## Opcodes (see `projectebonhold.lua`)

**Client → server**

| `CS.*` | # | Body |
|---|---|---|
| `REQUEST_COLLECTIONS` | 1100 | `""` (all) or `mounts`/`pets`/`appearances`/`transmog` |
| `REQUEST_SUMMON_MOUNT` | 1110 | `spellId` (phase 2) |
| `REQUEST_SUMMON_PET` | 1111 | `spellId` (phase 2) |
| `REQUEST_APPLY_TRANSMOG` | 1112 | `slot:item slot:item …` (phase 2) |
| `REQUEST_CLEAR_TRANSMOG` | 1113 | `slot` or `""` (phase 2) |

**Server → client**

| `SS.*` | # | Body | Kind |
|---|---|---|---|
| `SEND_COLLECTED_MOUNTS` | 1100 | `spellId spellId …` | snapshot |
| `SEND_COLLECTED_PETS` | 1101 | `spellId spellId …` | snapshot |
| `SEND_COLLECTED_APPEARANCES` | 1102 | `itemId itemId …` | snapshot |
| `SEND_TRANSMOG_SLOTS` | 1103 | `slot:item[:illusion] …` (item `0`=hidden) | snapshot |
| `SEND_MOUNT_LEARNED` | 1104 | `spellId` | delta |
| `SEND_PET_LEARNED` | 1105 | `spellId` | delta |
| `SEND_APPEARANCE_LEARNED` | 1106 | `itemId` | delta |
| `SEND_TRANSMOG_SLOT_UPDATE` | 1107 | `slot:item[:illusion]` (item `-1`=cleared) | delta |

Snapshots replace the whole set; deltas mutate one entry. Bodies are space-
separated decimals; records use `:`. Large bodies auto-chunk in transport.

## Server responsibilities

On `REQUEST_COLLECTIONS`, run the SELECTs in `server/collections.sql` and push
the four snapshots. Push the matching delta whenever a mount/pet/appearance is
learned or a slot is re-transmogged. IDs must match the client catalog keys.

## Client flow

`core/collections_service.lua` fills the `ezCollections` helper surface the
mount/pet shims need, receives the `SS.*` messages into `ezCollections.Collections`
/ `ezCollections.TransmogSlots`, and `RaiseEvent`s so the painters refresh. It
requests a full pull on `PLAYER_LOGIN` and on first journal open.

## Server bridge

`src/server/scripts/Custom/Ashendor/ProjectEbonhold/project_ebonhold_collections_scripts.cpp`
answers `REQUEST_COLLECTIONS` (and pushes on login) with `SEND_TRANSMOG_SLOTS`
(from `GetSlotTransmog`) and `SEND_COLLECTED_APPEARANCES` (from
`transmogrification_appearances`). Opcodes added to `Comms.h`; registered in
`custom_script_loader.cpp`. No new tables. Needs a CMake reconfigure + rebuild.

## Mount model previews (creature cache seeding)

`SetCreature(creatureID)` on this client takes the CREATURE entry (what
`GetCompanionInfo("MOUNT", i)` returns; the journals' "displayID" variables
actually carry creature ids) and resolves its display through the LOCAL
creature cache (`creaturecache.wdb`): a mount model only renders if the client
has already cached that creature. On a fresh cache the
Mount Journal shows an empty model pane — and so does the Prestige tab's
reward preview (modules\prestige), which reuses the same call path — until
the player happens to encounter the creature in the world.

Fix (server): pre-seed the cache by pushing one creature-query response per
mount/companion creature on login; the client caches whatever it receives.
Implemented in the server repo at
`src/server/scripts/Custom/Ashendor/ProjectEbonhold/project_ebonhold_creature_cache_scripts.cpp`
(registered in `custom_script_loader.cpp`): it scans the spell store once for
`SPELL_AURA_MOUNTED` / companion-summon (SummonProperties 67) effects — their
`MiscValue` IS the creature entry, so no data files or tables — then on each
login sends `CreatureTemplate::BuildQueryData(locale)` for every entry, the
same packet the core's own query handler builds. Needs a CMake reconfigure +
worldserver rebuild.

Roughly 900 creatures means ~120 KB of packets once per session, and the
client persists the cache across sessions. Seeding on login rather than on
journal open means the Prestige previews work even before the journal was
ever opened. The prestige addon side re-checks `GetModel()` for about a
second and retries, so responses landing just after the UI opened are picked
up automatically.

## Status

- **Server** — done; build + run. Sends current transmog + collected visuals.
- **Mounts / Pets** — catalogs + shims restored; render owned (native) + all
  (catalog). Server sets stored and supplemental.
- **Mount model cache seeding** — done on both sides; server script lives in
  the server repo (section above) and is registered in the loader. Needs a
  CMake reconfigure + worldserver rebuild to go live. Until that build ships,
  mount models render only for creatures already in the local cache.
- **Appearances / Transmog** — protocol + server + client data-sync done; the
  data lands in `ezCollections.Collections.Appearances` (displayIDs) and
  `ezCollections.TransmogSlots`. Still TODO to make the wardrobe *render* it:
  (a) generate the appearance catalog (`server/collections.sql` §1), and
  (b) write the `C_TransmogCollection` / `C_Transmog` backing (list catalog
  visuals per category, mark collected via `IsVisualCollected`, current slot
  from `TransmogSlots`).
