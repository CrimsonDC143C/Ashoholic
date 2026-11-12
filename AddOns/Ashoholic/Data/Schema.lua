--[[
================================================================================
 Data/Schema.lua - THE DATA CONTRACT
================================================================================

 WHAT IS THIS FILE?
   This is the blueprint for everything Ashoholic saves. It describes:
     - the shape of the saved table (AshoholicDB),
     - where every value comes from (WoW, ProjectEbonhold, or a calculation),
     - which values belong to the whole account and which to one character,
     - the rules every other file must follow.
   At the bottom are small helper functions that create new, empty records in
   the right shape, so no other file has to build them by hand.

 WHO USES IT?
   Only the Data layer (the files in Data/) reads and writes saved data:

       Game -> Collectors -> Data (follows this blueprint) -> UI

   - Collectors read WoW and ProjectEbonhold, then hand values to Data/.
   - Sync (imports and in-game sharing) also hands values to Data/.
   - The UI only asks Data/ for values. It never reads AshoholicDB itself.

 WHEN IS IT LOADED?
   Not yet. Stage 2 adds it to Ashoholic.toc, right after Core.lua.
   Until then this file is documentation that nothing loads in-game.

================================================================================
 1. THE SHAPE OF AshoholicDB
================================================================================

 WoW saves AshoholicDB in
     WTF\Account\<ACCOUNT>\SavedVariables\Ashoholic.lua
 so every WoW account has its own copy. Each copy holds its own account and,
 later, copies of your other accounts received through syncing or importing.
 Text in <angle brackets> below is an example, not a real key.

 AshoholicDB = {
     schemaVersion = 1,              -- which version of this blueprint the data uses
     myAccountId   = "<random ID>",  -- the account this copy of the file belongs to

     accounts = {
         ["<random ID>"] = {         -- one entry per WoW account we know about
             name       = "<alias>", -- the name shown in the UI; you can rename it
             currencies = { ... },   -- GROUP: account-wide currencies
             prestige   = { ... },   -- GROUP: account-wide Prestige progress
             realms = {
                 ["<realm name>"] = {
                     ["<character name>"] = {
                         basics     = { ... },   -- GROUP
                         run        = { ... },   -- GROUP
                         torment    = { ... },   -- GROUP
                         raids      = { ... },   -- GROUP
                         activities = { ... },   -- GROUP
                         trials = {
                             champion = { ... }, -- GROUP
                             crusader = { ... }, -- GROUP
                         },
                     },
                 },
             },
         },
     },

     settings = { ... },             -- your UI preferences; never synced
 }

================================================================================
 2. THE RULES
================================================================================

 Rule 1 - Unknown is nil, never 0.
   If we do not know a value, we leave it out (nil). We never write 0 as a
   guess, because 0 is a real amount and would lie to you.
   Example: right after /reload, ProjectEbonhold reports Prestige values as 0
   until the server answers. We wait until it says the value is known.

 Rule 2 - Data lives in "groups", and every group has updatedAt.
   A group is a small table of values that arrive from the same place at about
   the same time (for example "basics" or "run"). Every group has:
       updatedAt = time()   -- when the values were read from the game
   A group is missing (nil) until we have received it at least once.

   IMPORTANT: never save GetTime(). GetTime() counts seconds since the computer
   started, so it means nothing after a restart. time() is the real clock in
   seconds, which works across sessions and accounts. If ProjectEbonhold gives
   a "seconds left" value, convert it: resetAt = time() + secondsLeft.

 Rule 3 - When merging, the newer group wins, one group at a time.
   When data from another account or an imported file arrives, compare each
   group's updatedAt. Keep whichever is newer. Never replace a whole character
   at once. A copied group keeps its original updatedAt, so the UI always shows
   how old the information really is.

 Rule 4 - Only Data/ writes AshoholicDB.
   Everything else hands values to Data/. This keeps all saving in one place.

 Rule 5 - Never call ProjectEbonhold.onEventReceived.
   ProjectEbonhold keeps exactly ONE handler per server message
   (vendor/ProjectEbonhold/projectebonhold.lua, line 351). If Ashoholic
   registered a handler for a message, it would silently REPLACE
   ProjectEbonhold's own handler and break that part of ProjectEbonhold.
   Instead, Collectors use, in order of preference:
     a) ProjectEbonhold's public state and functions (e.g. PrestigeService),
     b) its listener APIs (Callboard.OnChanged, Trials.OnChanged),
     c) hooksecurefunc on its public functions (runs after them safely).

 Rule 6 - Daily and weekly data saves its reset time.
   Groups with daily or weekly counts save when they reset (resetAt, a time()
   value). Once that time has passed, the UI shows the data as reset instead
   of showing old counts as if they were current.

 Rule 7 - Calculated values are not saved.
   Totals (gold including all characters, currency totals across accounts),
   stale flags, countdowns, the Prestige Essence projection and
   "offerings remaining" are worked out when the UI needs them. Saving them
   would create copies that can disagree with the real values.

 Rule 8 - How accounts and characters are identified.
   ACCOUNT: WoW 3.3.5 has no account ID, so Data/ creates a random ID once
   and keeps it forever in myAccountId. The alias (name) starts as your login
   account name if WoW provides it (GetCVar("accountName")), otherwise a plain
   default name, and you can rename it in Settings > Accounts.
   CHARACTER: keyed by name (UnitName("player")) under its realm
   (GetRealmName()). The GUID is saved in basics. If a character with the same
   name has a different GUID, the old one was deleted and a new one created
   with that name, so the old record is replaced.

================================================================================
 3. EVERY GROUP, FIELD BY FIELD
================================================================================

 Units: "copper" = money in copper (1 gold = 10000 copper).
        "time"   = a time() value (real clock, seconds).

 ------------------------------------------------------------------------------
 ACCOUNT GROUPS (counted once per account, shared by all its characters)
 ------------------------------------------------------------------------------

 currencies
   Source: ProjectEbonhold's Soul Ash tree update. Hook
           ProjectEbonhold.SkillTree.UpdateTotalSoulPoints(spendable,
           committed, pools) with hooksecurefunc. It runs at login and on
           every change.
     ashSpendable      number  Soul Ash you can spend on the tree right now
     ashBanked         number  Soul Ash banked (committed) on the account
     shardSpendable    number  Soul Shards you can spend
     shardBanked       number  Soul Shards banked (run shards NOT included)
     essenceSpendable  number  Soul Essence you can spend
     essenceBanked     number  Soul Essence banked
     artisanSpendable  number  Artisan Soul you can spend
     artisanBanked     number  Artisan Soul banked
     warbandGold       copper  Warband bank gold. ALWAYS nil for now:
                               ProjectEbonhold keeps it in a private variable
                               that other addons cannot read. Revisit in Stage 5.
     updatedAt         time

 prestige
   Source: ProjectEbonhold.PrestigeService. Only save when
           PrestigeService.IsGateProgressKnown() is true (see Rule 1).
     count             number  Prestiges done so far (GetTotalPrestiges)
     gateProgress      number  committed Soul Ash counted toward the Prestige
                               gate (GetGateProgress)
     pendingEssence    number  Soul Essence the next Prestige would give
                               (second value returned by GetPendingEssence)
     updatedAt         time
   The gate itself (10,771,440 Soul Ash) is a fixed number in
   ProjectEbonhold, so it is not saved.

 ------------------------------------------------------------------------------
 CHARACTER GROUPS (one set per character)
 ------------------------------------------------------------------------------

 basics
   Source: WoW. Collected at login, on level-up, gold changes, zone changes
           and at logout.
     guid              string  UnitGUID("player"); detects a recreated character
     class             string  class token such as "MAGE", the same in every
                               game language (second value of UnitClass)
     level             number  UnitLevel("player")
     gold              copper  GetMoney()
     location          string  GetRealZoneText()
     itemLevel         number  equipped item level. The source is decided later:
                               the Call Board's equipped item level or a
                               calculation from worn gear. nil until then.
     updatedAt         time    also the roster's "Last seen", because basics
                               are only collected while the character is online

 run   (the "parked run" in the detail panel)
   Source: three ProjectEbonhold modules, all refreshed by ProjectEbonhold
           itself shortly after login.
     soulAsh           number  Soul Ash in the current run
                               (PlayerRunService.GetCurrentData().soulPoints)
     soulShards        number  Soul Shards in the current run
                               (PlayerRunService.GetCurrentData().soulShards)
     offeringBonusPct  number  offering bonus in percent. Exact source is
                               confirmed in-game in Stage 5 (Contracts.gauge
                               or the run data's soulShardsBonusPct).
     offeringsUsed     number  offerings used. Confirmed in Stage 5
                               (Contracts.used or run data banksUsedWeek).
     offeringsMax      number  offerings allowed (Contracts.max or
                               banksMaxWeek). "Remaining" is calculated.
     anchorState       number  soul anchor: 0 none, 1 at the Spirit Healer you
                               were talking to, 2 elsewhere
                               (Contracts.anchorState; meaning checked in Stage 5)
     anchorPlace       string  where the soul anchor is (Contracts.anchorPlace)
     echoBuild         string  name of the active Echo loadout
                               (Perks.serverBuildSlots[Perks.serverActiveSlot].name)
     updatedAt         time

 torment
   Source: ProjectEbonhold.HardmodeService.
   ProjectEbonhold checks Torment unlocks PER CHARACTER (through achievements).
   The preview's per-account ladder becomes a calculated view built from these
   values. Confirm this in-game.
     currentTier       number  selected Torment difficulty
                               (GetCurrentDifficulty, only when IsDifficultyKnown)
     highestUnlocked   number  highest tier this character may run
                               (checked with IsTierUnlocked for each tier)
     updatedAt         time

 raids
   Source: ProjectEbonhold.RaidLockout.IsLooted(bossId), asked for every boss
           in ProjectEbonhold.RaidLockoutData.
     looted            table   { [bossId] = true } for bosses looted this week
     resetAt           time    the weekly reset (Tuesday 03:00 UTC); after it,
                               every boss is available again
     updatedAt         time
   Dungeon lockouts have no source, so they are not saved and the UI shows
   them as Unknown.

 activities   (Hero's Call Board)
   Source: ProjectEbonhold.Callboard.OnChanged("board") and Callboard.board.
           Only arrives after ProjectEbonhold receives the board (when the Call
           Board is opened). Whether Ashoholic asks for it is decided in Stage 6.
     cacheProgress     number  cache bar progress
     cacheRequired     number  progress needed for the next cache
     cachesOpened      number  caches opened
     quests            table   { [questId] = {
                                   title       = string,
                                   cadence     = "daily", "weekly" or "once",
                                   done        = number,
                                   max         = number,
                                   state       = number (ProjectEbonhold's
                                                 Callboard.STATE value),
                                   accountWide = true or false,
                               } }
     dailyResetAt      time    when daily quests reset
     weeklyResetAt     time    when weekly quests reset
     updatedAt         time

 trials.champion   (Trial of the Champion, damage, ranked per class)
   Source: ProjectEbonhold.Trials.OnChanged("board" or "result"). Only arrives
           after a Trials leaderboard is viewed or a Trial is finished.
     best              number  best score (damage)
     rank              number  your rank within your class
     total             number  how many players are ranked
     season            number  season number
     seasonName        string  season name
     updatedAt         time

 trials.crusader   (Trial of the Crusader, survival waves)
   Same source as trials.champion.
     best              number  best score in ProjectEbonhold's packed form;
                               Trials.DecodeCrusader turns it into waves + time
     teamSize          number  players in the best run
     rank              number  your rank
     total             number  how many players are ranked
     season            number  season number
     seasonName        string  season name
     updatedAt         time

 ------------------------------------------------------------------------------
 SETTINGS (not a group; never synced)
 ------------------------------------------------------------------------------

 settings
   Filled in Stage 4. It will hold the UI preferences from the preview: theme,
   fonts, sizes, roster columns, tabs, alerts, account colors, collapsed
   accounts and watched raid bosses.

================================================================================
 4. UPGRADING OLD DATA (MIGRATIONS)
================================================================================

 - The old Ashoholic saved its data through the AceDB library, which left keys
   such as "global" and "profiles" at the top of AshoholicDB. As you chose,
   Stage 2 deletes those old keys (listed in Schema.OLD_ACEDB_KEYS below) the
   first time the new addon loads. The new addon does not use AceDB for its
   saved data.
 - Whenever this blueprint changes later, raise Schema.VERSION and add an
   upgrade step, so saved data is converted instead of lost.

================================================================================
]]

local addonName = ...
local addon = _G[addonName] -- created by Core.lua, which loads first

-- Everything in this file lives in addon.Schema, so other files can write
-- addon.Schema.VERSION, addon.Schema.NewAccount(...) and so on.
local Schema = {}
addon.Schema = Schema

-- Which version of the blueprint this code expects.
-- Raise it by 1 whenever the saved layout changes (see section 4 above).
Schema.VERSION = 1

-- The group names, so Data/ and Sync/ can loop over them instead of repeating
-- the lists. A "group" is a small table with its own updatedAt (Rule 2).
Schema.ACCOUNT_GROUPS = { "currencies", "prestige" }
Schema.CHARACTER_GROUPS = { "basics", "run", "torment", "raids", "activities" }
-- These two groups live one level deeper, inside character.trials.
Schema.TRIAL_GROUPS = { "champion", "crusader" }

-- Keys that the old AceDB-based Ashoholic could leave at the top of
-- AshoholicDB. Stage 2 removes them once because you chose to start fresh.
-- None of these names are used by the new layout above.
Schema.OLD_ACEDB_KEYS = {
    "global", "profiles", "profileKeys", "namespaces",
    "char", "realm", "class", "race", "faction",
    "factionrealm", "factionrealmregion", "locale",
}

-- Creates a brand-new, empty AshoholicDB.
-- Used the first time the addon loads on a WoW account (when there is no
-- saved file yet). myAccountId is filled in by Data/ right after this.
function Schema.NewDatabase()
    return {
        schemaVersion = Schema.VERSION,
        myAccountId   = nil,
        accounts      = {},
        settings      = {},
    }
end

-- Creates an empty account record.
--   name: the alias shown in the UI.
-- The currencies and prestige groups are left out on purpose: they stay nil
-- (unknown) until ProjectEbonhold sends them (Rule 1).
function Schema.NewAccount(name)
    return {
        name   = name,
        realms = {},
    }
end

-- Creates an empty character record.
-- Every group stays nil (unknown) until a Collector or Sync fills it in.
function Schema.NewCharacter()
    return {}
end
