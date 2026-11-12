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
   Stage 2 loads this file after Core.lua. Data/Store.lua follows it and
   prepares AshoholicDB; Collectors/Character.lua then saves the current
   character's basic information through that Data layer.

================================================================================
 1. THE SHAPE OF AshoholicDB
================================================================================

 WoW saves AshoholicDB in
     WTF\Account\<ACCOUNT>\SavedVariables\Ashoholic.lua
 so every WoW account has its own copy. Each copy holds its own account and,
 later, copies of your other accounts received through syncing or importing.
 Text in <angle brackets> below is an example, not a real key.

 AshoholicDB = {
     schemaVersion = 4,              -- which version of this blueprint the data uses
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
                         contracts  = { ... },   -- GROUP: offerings and Soul Anchor
                         echoBuild  = { ... },   -- GROUP: active live Echo loadout
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
     c) hooksecurefunc on its public functions (runs after them safely),
     d) Ashoholic's own CHAT_MSG_ADDON listener, which reads a server reply
        that ProjectEbonhold also receives but handles privately. Reading
        never replaces a handler. Only Integrations/ProjectEbonhold.lua does
        this, and it ignores any message whose layout it does not recognize.
     e) Text that ProjectEbonhold shows in its own named frames, read only
        at a moment when its meaning is certain (the Soul Ash tree's bottom
        bar right after a successful Apply). Any unexpected text is ignored.
   Ashoholic observes and does not send server requests, with one exception:
   Integrations/ProjectEbonhold.lua may ask for the Soul Ash tree's loadout
   reply once per UI session, only before the tree has asked for it (see the
   currencies group below).

 Rule 6 - Daily and weekly data saves its reset time.
   Groups with daily or weekly counts save when they reset (resetAt, a time()
   value). Once that time has passed, the UI shows the data as reset instead
   of showing old counts as if they were current.

 Rule 7 - Calculated values are not saved.
   Totals (gold including all characters, currency totals across accounts),
   stale flags, countdowns, the highest unlocked Torment tier and
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
   Stage 5's second slice collects this group, except warbandGold.
   The server sends no balances at login (confirmed in-game). They reach
   Ashoholic in three ways:
     1) A server balance update after a balance changes (banking a run,
        buying a class node). Hook
        ProjectEbonhold.SkillTree.UpdateTotalSoulPoints(spendable,
        committed, pools) with hooksecurefunc.
     2) The Soul Ash tree's loadout reply. The tree asks for it when it first
        opens and handles it in a private function, so Ashoholic reads only
        its balance header with its own CHAT_MSG_ADDON listener (Rule 5 d).
        Replies are read only within 30 seconds of a loadout request.
     3) A successful Apply in the Soul Ash tree. Its server reply only says
        "success" (confirmed in-game: the cards did not change until
        /reload). Hook ProjectEbonhold.SkillTree.OnApplyChangesResult; on
        success, read the four spendable amounts from the tree's bottom bar
        (Rule 5 e). Spending never changes banked balances, so those are
        copied from the latest server balances of this session. Nothing is
        saved if no server balances arrived this session or any amount
        cannot be read. The bar is never read while choices are unapplied,
        because it then subtracts them from the real balances.
   When /ash opens and no balances arrived in this UI session, Ashoholic asks
   for the loadout reply itself, but only if no loadout request has happened
   yet in this session. The reply also resets ProjectEbonhold's tree display
   and clears unapplied tree choices; before the tree's own first request,
   the tree has never been opened, so there is nothing to lose. A /reload
   starts a new session for both addons.
   Collectors/Currencies.lua starts watching when Ashoholic loads, keeps an
   early update pending until the database is ready, and saves each update as
   a fresh observation. Saved balances stay visible with their old age until a
   new update arrives. A decrease after spending replaces the old balance.
   Older servers send only the Soul Ash pair: the other pairs then stay nil.
   Each pair is saved complete (both values) or not at all.
   The live currency cards show spendable totals; their tooltips show both
   spendable and banked balances. These are not added together.
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
                               that other addons cannot read.
     updatedAt         time    when the balance update was observed

 prestige
   Source: the complete SEND_PRESTIGE_DATA reply that feeds PrestigeService.
   The integration observes this small reply passively (Rule 5 d), rather
   than treating every PrestigeUI.Refresh as fresh data. Refresh also follows
   a Prestige result that changes only the count, leaving the old gate and
   reward until the next complete reply. Saving that mixture would be wrong.
   The companion requests data on login/reload and when its Prestige panel
   opens; Ashoholic sends no additional request. Old saved values retain
   their age until another reply arrives.
     count             number  Prestiges done so far
     gateProgress      number  committed Soul Ash counted toward the gate
     pendingShards     number  banked Shards reported in this Prestige reply
     pendingEssence    number  exact Soul Essence reward reported by the server
     updatedAt         time
   Older two/three-field replies omit both pending values; these stay nil,
   not the placeholder zero returned by GetPendingEssence before those
   fields arrive. A result message alone never changes this group.
   The gate (currently 10,771,440 Soul Ash), tier names and Torment ladder
   size are read through the integration into Data's session-only rules.
   They are not saved. The UI shows currency requirements, not a promise that
   a Prestige is allowed while dead, in combat, or under other server rules.

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
   Source: PlayerRunService.GetCurrentData(), observed after the companion's
           PlayerRunUI.UpdateData via hooksecurefunc. The empty login table
           is not data. A new parsed run table marks a new observation; HUD
           refreshes of the same table do not advance updatedAt.
   Collectors/Run.lua waits for matching character basics before saving and
   preserves the observation time if loading delays that save. An existing
   saved run stays visible with its old age until a fresh observation arrives.
   All counts, including zero or a decrease after a run ends, replace the old
   balances. They are never summed with banked account currencies.
     soulAsh           number  Soul Ash in the current run
                               (PlayerRunService.GetCurrentData().soulPoints)
     soulShards        number  Soul Shards in the current run
                               (PlayerRunService.GetCurrentData().soulShards)
     updatedAt         time    when the run currencies were observed, not when
                               the roster was opened or a cached value reread

 contracts
   Source: ProjectEbonhold.Contracts, only after received is true. Its parser
   replaces Contracts.list before calling PlayerRunUI.UpdateBracket, even
   when the Spirit Healer window is hidden. Observe that public function,
   and use the new list's identity to distinguish a reply from HUD redraws.
   Offerings and Soul Anchor arrive together, but separately from run
   currencies; neither group is allowed to refresh the other's timestamp.
   The companion requests this data on entering the world. Ashoholic does
   not open the Spirit Healer window or send contract actions.
     offeringBonusPct  number  offering bonus in percent (Contracts.gauge)
     offeringsUsed     number  offerings used this run (Contracts.used)
     offeringsMax      number  offerings allowed this run (Contracts.max)
                               Remaining is max(0, max - used), not a weekly
                               counter from the older player-run protocol.
     anchorState       number  soul anchor: 0 none, 1 at the Spirit Healer you
                               were talking to, 2 elsewhere
                               (Contracts.anchorState)
     anchorPlace       string  where the soul anchor is (Contracts.anchorPlace)
     updatedAt         time
   "Here" is relative to that healer, not the character's current location.
   Offline displays show the saved place, or "Set (place unknown)", never
   claim the anchor is at the character's current position.

 echoBuild
   Source: PerkService.GetServerBuildSlots / GetServerActiveSlot. Observe
   PerkUI.RefreshLoadoutHighlights after server updates. A new slots table,
   changed active slot or changed availability is a new observation; a
   cosmetic redraw or highlighted wishlist is not.
   The companion's active-slot login push requests the slots if needed.
   Wait for the selected slot's live row instead of assuming slot 1 exists.
     enabled           boolean whether server-side loadouts are available
     slot              number  active live loadout slot (not a wishlist ID)
     name              string  its name; "" means a known, unnamed loadout
     updatedAt         time
   A missing group means unknown. A server reply with enabled=false clears
   the old slot/name and is shown as unavailable, not a guessed empty build.

 torment
   Source: ProjectEbonhold.HardmodeService.
   ProjectEbonhold checks Torment unlocks PER CHARACTER (through achievements).
   Wait for IsDifficultyKnown, and for the committed pool if any tier has an
   Ash gate. Observe HardmodeUI.Refresh and ACHIEVEMENT_EARNED. Repainting
   unchanged cached values does not advance the timestamp.
     currentTier       number  selected Torment difficulty
                               (GetCurrentDifficulty), NOT a party's temporary
                               instance difficulty. 1 = Normal; 2 = Torment I.
     unlockedTiers     table   { [tier] = true } for each IsTierUnlocked result
     updatedAt         time
   The highest unlocked tier is calculated for display. Keep the actual set:
   one unlocked tier does not prove that every lower achievement was earned.
   The progression view groups characters by account without claiming that
   their unlocks are shared. Its ladder follows TormentLadderTop; higher,
   instance-only tiers still retain their real names and selected values.

 raids
   Source: a complete SEND_RAID_LOOT_LOCKOUTS reply, also read by the
           companion's RaidLockout service. The reply lists each looted boss
           and its remaining lock time. Ashoholic observes it without
           replacing the companion's handler or requesting data itself.
     lockedUntil       table   { [bossId] = time } for each reported lock
     updatedAt         time
   The group is nil until a complete reply arrives. Only then does an absent
   or expired lock mean Available in that snapshot. Individual end times are
   retained instead of assuming every server-provided timer is identical.
   Dungeon names are a watchlist only; dungeon status remains Unknown.

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
   Stage 4 starts with the live roster window's saved position. Stage 6 adds
   the encounter watchlist. The PreviewUI settings remain sample-only and are
   not copied into these saved settings.
     ui.roster.position { point, x, y }
       point             string  anchor on the screen, e.g. "CENTER"
       x, y              number  offsets from the matching UIParent anchor
     ui.raids.watched    table   { [stable encounter key] = true }
                               raid keys use real encounter IDs; dungeon keys
                               use their names, not invented server IDs
   If this position is absent, the roster opens in the center of the screen.

================================================================================
 4. UPGRADING OLD DATA (MIGRATIONS)
================================================================================

 - The old Ashoholic saved its data through the AceDB library, which left keys
   such as "global" and "profiles" at the top of AshoholicDB. As you chose,
   Stage 2 removes those old keys (listed in Schema.OLD_ACEDB_KEYS below) when
   the new addon initializes. This cleanup is safe to repeat and becomes a
   no-op after the first time. The new addon does not use AceDB for saved data.
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
Schema.VERSION = 4

-- The group names, so Data/ and Sync/ can loop over them instead of repeating
-- the lists. A "group" is a small table with its own updatedAt (Rule 2).
Schema.ACCOUNT_GROUPS = { "currencies", "prestige" }
Schema.CHARACTER_GROUPS = { "basics", "run", "contracts", "echoBuild", "torment", "raids", "activities" }
-- These two groups live one level deeper, inside character.trials.
Schema.TRIAL_GROUPS = { "champion", "crusader" }

-- Keys that the old AceDB-based Ashoholic could leave at the top of
-- AshoholicDB. Stage 2 removes them because you chose to start fresh.
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

-- Version 3 documented a single weekly reset even though the feature had no
-- live writer yet. If a database already contains that documented shape,
-- preserve each lock using its former shared reset time.
local function MigrateRaidSnapshots(database)
    if database.accounts == nil then
        return
    end
    if type(database.accounts) ~= "table" then
        error("Ashoholic cannot migrate invalid accounts.")
    end
    local migrations = {}
    for _, account in pairs(database.accounts) do
        if type(account) ~= "table" then
            error("Ashoholic cannot migrate an invalid account.")
        end
        if account.realms ~= nil then
            if type(account.realms) ~= "table" then
                error("Ashoholic cannot migrate invalid realms.")
            end
            for _, realm in pairs(account.realms) do
                if type(realm) ~= "table" then
                    error("Ashoholic cannot migrate invalid character records.")
                end
                for _, character in pairs(realm) do
                    if type(character) ~= "table" then
                        error("Ashoholic cannot migrate an invalid character.")
                    end
                    local raids = character.raids
                    if raids ~= nil then
                        if type(raids) ~= "table" then
                            error("Ashoholic cannot migrate invalid raid data.")
                        end
                        if raids.looted ~= nil then
                            if type(raids.looted) ~= "table" or raids.lockedUntil ~= nil
                                or type(raids.resetAt) ~= "number"
                                or raids.resetAt <= 0 or raids.resetAt >= math.huge
                                or raids.resetAt ~= math.floor(raids.resetAt) then
                                error("Ashoholic cannot migrate an invalid raid snapshot.")
                            end
                            local lockedUntil = {}
                            for bossId, looted in pairs(raids.looted) do
                                if type(bossId) ~= "number" or bossId <= 0
                                    or bossId >= math.huge or bossId ~= math.floor(bossId)
                                    or looted ~= true then
                                    error("Ashoholic cannot migrate an invalid raid encounter.")
                                end
                                lockedUntil[bossId] = raids.resetAt
                            end
                            migrations[#migrations + 1] = { raids = raids, lockedUntil = lockedUntil }
                        end
                    end
                    for _, migration in ipairs(migrations) do
                        migration.raids.lockedUntil = migration.lockedUntil
                        migration.raids.looted = nil
                        migration.raids.resetAt = nil
                    end
                end
            end
        end
    end
end

-- Convert older saved databases one version at a time, keeping characters,
-- currencies and settings. Optional groups remain nil until observed.
function Schema.Migrate(database)
    local version = database.schemaVersion
    if type(version) ~= "number" then
        error("Ashoholic cannot migrate saved data with an invalid schema version.")
    end
    if version > Schema.VERSION then
        error(
            "Ashoholic saved data uses newer schema version "
                .. tostring(version)
                .. "; this addon supports version "
                .. tostring(Schema.VERSION)
                .. "."
        )
    end

    while version < Schema.VERSION do
        if version == 1 then
            -- Version 2 adds settings.ui.roster.position when the window is
            -- first moved. Keeping it absent preserves the centered default.
            version = 2
        elseif version == 2 then
            -- Version 2 collected only currencies in run. Its reserved
            -- offerings/anchor/build fields and torment were never written.
            -- Version 3 gives the new sources independent groups and saves
            -- actual tier unlocks. No existing observations need moving.
            version = 3
        elseif version == 3 then
            MigrateRaidSnapshots(database)
            -- Missing raid groups and watchlists remain missing until used.
            version = 4
        else
            error("Ashoholic has no migration for saved schema version " .. tostring(version) .. ".")
        end
        database.schemaVersion = version
    end
end
