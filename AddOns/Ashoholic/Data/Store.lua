--[[
================================================================================
 Data/Store.lua - THE SAVED DATA ACCESS POINT
================================================================================

 This is the only file allowed to create and change AshoholicDB records.
 Collectors read information from WoW, then call functions here to save it.
 Later, Sync will use the same functions when importing another account.

 The ADDON_LOADED event is important: WoW loads the SavedVariables file before
 it sends this event, so AshoholicDB is ready to read and update here.
]]

local addonName = ...
local addon = _G[addonName]
local Schema = addon.Schema

if not Schema then
    error("Ashoholic Data/Store.lua loaded before Data/Schema.lua.")
end

local Data = {}
addon.Data = Data

local database
local progressionRules
local encounterCatalog
local rosterListeners = {}
-- Each of these Ebonhold currencies has a spendable and a banked balance.
-- Soul Ash is listed separately because every balance update includes it.
local POOL_CURRENCIES = { "shard", "essence", "artisan" }
local PRESTIGE_FIELDS = { "count", "gateProgress", "pendingShards", "pendingEssence", "updatedAt" }
local CONTRACT_FIELDS = { "offeringBonusPct", "offeringsUsed", "offeringsMax", "anchorState", "anchorPlace", "updatedAt" }
local ECHO_BUILD_FIELDS = { "enabled", "slot", "name", "updatedAt" }
local ROSTER_ANCHOR_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

-- Returns a useful error rather than silently replacing unexpected saved data.
local function RequireTable(value, description)
    if type(value) ~= "table" then
        error("Ashoholic cannot use saved " .. description .. ": expected a table.")
    end
    return value
end

local function IsNonNegativeNumber(value)
    return type(value) == "number" and value >= 0
        and value < math.huge
end

local function IsNonNegativeInteger(value)
    return IsNonNegativeNumber(value) and value == math.floor(value)
end

local function RequireObservation(snapshot, description)
    RequireTable(snapshot, description .. " snapshot")
    if not IsNonNegativeInteger(snapshot.updatedAt) or snapshot.updatedAt == 0 then
        error("Ashoholic " .. description .. " needs an observation time.")
    end
end

local function CopyFields(source, fields)
    local copy = {}
    for _, field in ipairs(fields) do
        copy[field] = source[field]
    end
    return copy
end

local function CopyTree(value, copies)
    if type(value) ~= "table" then
        return value
    end
    copies = copies or {}
    if copies[value] then
        return copies[value]
    end
    local copy = {}
    copies[value] = copy
    for key, child in pairs(value) do
        copy[key] = CopyTree(child, copies)
    end
    return copy
end

local function CopyOptionalGroup(record, name, fields)
    if record[name] == nil then
        return nil
    end
    return CopyFields(RequireTable(record[name], name), fields)
end

-- Consumers subscribe once and redraw from GetRoster, never from saved tables.
-- Account and character groups share this notification; every live page reads
-- the same display-safe model.
function Data.OnRosterChanged(listener)
    if type(listener) ~= "function" then
        error("Ashoholic roster listeners must be functions.")
    end
    table.insert(rosterListeners, listener)
end

-- These are companion display rules, not character observations. Keep them
-- only for this session so a companion update cannot leave stale saved names
-- or thresholds. Collectors supply them; UI code never calls the companion.
function Data.SetProgressionRules(snapshot)
    RequireTable(snapshot, "progression rules")
    local names = RequireTable(snapshot.tierNames, "Torment tier names")
    if not IsNonNegativeInteger(snapshot.prestigeGate) or snapshot.prestigeGate == 0
        or not IsNonNegativeInteger(snapshot.tormentLadderTop)
        or snapshot.tormentLadderTop < 2 or snapshot.tormentLadderTop > #names then
        error("Ashoholic received invalid Prestige or Torment display rules.")
    end

    local copiedNames = {}
    for tier, name in ipairs(names) do
        if type(name) ~= "string" or name == "" then
            error("Ashoholic received an invalid Torment tier name.")
        end
        copiedNames[tier] = name
    end
    progressionRules = {
        prestigeGate = snapshot.prestigeGate,
        tormentLadderTop = snapshot.tormentLadderTop,
        tierNames = copiedNames,
    }
end

function Data.GetProgressionRules()
    if not progressionRules then
        error("Ashoholic progression rules were requested before collection.")
    end
    local names = {}
    for tier, name in ipairs(progressionRules.tierNames) do
        names[tier] = name
    end
    return {
        prestigeGate = progressionRules.prestigeGate,
        tormentLadderTop = progressionRules.tormentLadderTop,
        tierNames = names,
    }
end

-- The catalogue is display data for this session, not a character snapshot.
-- The collector supplies the companion's raids; the shared catalogue adds the
-- preview's dungeon names without treating them as server encounters.
function Data.SetEncounterCatalog(raids)
    if not addon.EncounterCatalog then
        error("Ashoholic cannot build encounters before Data/Encounters.lua is loaded.")
    end
    encounterCatalog = addon.EncounterCatalog.Build(raids)
end

function Data.GetEncounterCatalog()
    if not encounterCatalog then
        error("Ashoholic encounter catalogue was requested before collection.")
    end
    return CopyTree(encounterCatalog)
end

local function NotifyRosterChanged()
    for _, listener in ipairs(rosterListeners) do
        listener()
    end
end

-- WoW has no account-ID API. Keep a generated ID in SavedVariables so it stays
-- the same on every character of this WoW account. math.random is used only
-- when creating an ID; we deliberately do not reseed WoW's shared random
-- number generator.
local function NewAccountId()
    return string.format(
        "%d-%08x-%08x",
        time(),
        math.random(0, 2147483647),
        math.random(0, 2147483647)
    )
end

-- The alias is just a display name. It can be renamed later in Settings.
local function InitialAccountName()
    local name = GetCVar and GetCVar("accountName")
    if type(name) == "string" then
        name = string.gsub(name, "^%s*(.-)%s*$", "%1")
        if name ~= "" then
            return name
        end
    end

    return "Account 1"
end

-- Call this once when WoW tells us Ashoholic's SavedVariables are loaded.
function Data.Initialize()
    if AshoholicDB == nil then
        AshoholicDB = Schema.NewDatabase()
    end

    database = RequireTable(AshoholicDB, "AshoholicDB")

    -- Older AceDB saves have no Ashoholic schema version. They are handled as
    -- fresh data because the user chose not to import the old layout.
    if database.schemaVersion == nil then
        database.schemaVersion = Schema.VERSION
    else
        Schema.Migrate(database)
    end

    -- Remove the old AceDB layout. The user chose to start fresh, so these
    -- legacy records are intentionally not imported into the new structure.
    for _, key in ipairs(Schema.OLD_ACEDB_KEYS) do
        database[key] = nil
    end

    database.schemaVersion = Schema.VERSION
    if database.accounts == nil then
        database.accounts = {}
    end
    if database.settings == nil then
        database.settings = {}
    end
    RequireTable(database.accounts, "accounts")
    RequireTable(database.settings, "settings")

    if type(database.myAccountId) ~= "string" or database.myAccountId == "" then
        database.myAccountId = NewAccountId()
    end

    local account = database.accounts[database.myAccountId]
    if account == nil then
        account = Schema.NewAccount(InitialAccountName())
        database.accounts[database.myAccountId] = account
    end
    RequireTable(account, "current account")

    if type(account.name) ~= "string" or account.name == "" then
        account.name = InitialAccountName()
    end
    if account.realms == nil then
        account.realms = {}
    end
    RequireTable(account.realms, "current account realms")
end

-- Save the basic facts about one character. The collector does not get the
-- SavedVariables table itself; it passes a snapshot through this function.
function Data.SaveCharacterBasics(realmName, characterName, snapshot)
    if not database then
        error("Ashoholic data was saved before Data.Initialize().")
    end
    if type(realmName) ~= "string" or realmName == "" then
        error("Ashoholic cannot save character basics without a realm name.")
    end
    if type(characterName) ~= "string" or characterName == "" then
        error("Ashoholic cannot save character basics without a character name.")
    end
    if type(snapshot) ~= "table" then
        error("Ashoholic character basics must be supplied as a table.")
    end

    local account = database.accounts[database.myAccountId]
    local realm = account.realms[realmName]
    if realm == nil then
        realm = {}
        account.realms[realmName] = realm
    end
    RequireTable(realm, "character records for realm " .. realmName)

    local character = realm[characterName]
    if character == nil then
        character = Schema.NewCharacter()
        realm[characterName] = character
    end
    RequireTable(character, "character " .. characterName)

    local oldBasics = character.basics
    if oldBasics ~= nil then
        RequireTable(oldBasics, "basics for " .. characterName)
    end

    -- A name can be reused after a character is deleted. A different GUID
    -- means this is a new character, so do not attach the old character's
    -- later data groups to it.
    if oldBasics and oldBasics.guid and snapshot.guid
        and oldBasics.guid ~= snapshot.guid then
        character = Schema.NewCharacter()
        realm[characterName] = character
    end

    -- Copy only fields defined by the basics contract. This prevents a caller
    -- from accidentally saving temporary or unrelated values.
    character.basics = {
        guid      = snapshot.guid,
        class     = snapshot.class,
        level     = snapshot.level,
        gold      = snapshot.gold,
        location  = snapshot.location,
        updatedAt = time(),
    }

    NotifyRosterChanged()
    return character.basics
end

-- Every character-specific collector must attach its data to matching basics,
-- including the GUID check for a deleted/recreated character with the same name.
local function RequireCharacter(realmName, characterName, guid, description)
    if not database then
        error("Ashoholic " .. description .. " was saved before Data.Initialize().")
    end
    if type(realmName) ~= "string" or realmName == ""
        or type(characterName) ~= "string" or characterName == ""
        or type(guid) ~= "string" or guid == "" then
        error("Ashoholic cannot save " .. description .. " without a complete character identity.")
    end

    local account = database.accounts[database.myAccountId]
    local realm = account.realms[realmName]
    local character = realm and realm[characterName]
    if not character or not character.basics or character.basics.guid ~= guid then
        error("Ashoholic must collect matching character basics before saving " .. description .. ".")
    end
    return character
end

-- Local observations replace the run's balances even when they decrease or
-- reach zero. Do not add them to the banked account currencies or to older runs.
function Data.SaveCharacterRun(realmName, characterName, guid, snapshot)
    local character = RequireCharacter(realmName, characterName, guid, "run data")
    RequireObservation(snapshot, "run data")
    if not IsNonNegativeInteger(snapshot.soulAsh)
        or not IsNonNegativeInteger(snapshot.soulShards) then
        error("Ashoholic run data needs non-negative currency counts.")
    end

    character.run = {
        soulAsh = snapshot.soulAsh,
        soulShards = snapshot.soulShards,
        updatedAt = snapshot.updatedAt,
    }
    NotifyRosterChanged()
end

function Data.SaveAccountPrestige(snapshot)
    if not database then
        error("Ashoholic Prestige data was saved before Data.Initialize().")
    end
    RequireObservation(snapshot, "Prestige data")
    if not IsNonNegativeInteger(snapshot.count)
        or not IsNonNegativeInteger(snapshot.gateProgress) then
        error("Ashoholic Prestige data needs a count and gate progress.")
    end
    local bothUnknown = snapshot.pendingShards == nil and snapshot.pendingEssence == nil
    local bothKnown = IsNonNegativeInteger(snapshot.pendingShards)
        and IsNonNegativeInteger(snapshot.pendingEssence)
    if not bothUnknown and not bothKnown then
        error("Ashoholic received an incomplete Prestige reward.")
    end

    database.accounts[database.myAccountId].prestige = CopyFields(snapshot, PRESTIGE_FIELDS)
    NotifyRosterChanged()
end

function Data.SaveCharacterContracts(realmName, characterName, guid, snapshot)
    local character = RequireCharacter(realmName, characterName, guid, "contract data")
    RequireObservation(snapshot, "contract data")
    if not IsNonNegativeNumber(snapshot.offeringBonusPct)
        or not IsNonNegativeInteger(snapshot.offeringsUsed)
        or not IsNonNegativeInteger(snapshot.offeringsMax)
        or not IsNonNegativeInteger(snapshot.anchorState) or snapshot.anchorState > 2
        or type(snapshot.anchorPlace) ~= "string" then
        error("Ashoholic received invalid offerings or Soul Anchor data.")
    end

    character.contracts = CopyFields(snapshot, CONTRACT_FIELDS)
    NotifyRosterChanged()
end

function Data.SaveCharacterEchoBuild(realmName, characterName, guid, snapshot)
    local character = RequireCharacter(realmName, characterName, guid, "Echo build")
    RequireObservation(snapshot, "Echo build")
    if type(snapshot.enabled) ~= "boolean" then
        error("Ashoholic Echo build availability must be known.")
    end
    if snapshot.enabled then
        if not IsNonNegativeInteger(snapshot.slot) or snapshot.slot == 0
            or type(snapshot.name) ~= "string" then
            error("Ashoholic received an invalid active Echo loadout.")
        end
    elseif snapshot.slot ~= nil or snapshot.name ~= nil then
        error("Ashoholic cannot save an active slot when Echo loadouts are unavailable.")
    end

    character.echoBuild = CopyFields(snapshot, ECHO_BUILD_FIELDS)
    NotifyRosterChanged()
end

function Data.SaveCharacterTorment(realmName, characterName, guid, snapshot)
    local character = RequireCharacter(realmName, characterName, guid, "Torment data")
    RequireObservation(snapshot, "Torment data")
    if not progressionRules then
        error("Ashoholic needs Torment display rules before saving tiers.")
    end
    local tierCount = #progressionRules.tierNames
    if not IsNonNegativeInteger(snapshot.currentTier)
        or snapshot.currentTier < 1 or snapshot.currentTier > tierCount then
        error("Ashoholic received an invalid selected Torment tier.")
    end

    local unlocked = RequireTable(snapshot.unlockedTiers, "Torment unlocks")
    local copiedUnlocks = {}
    for tier, value in pairs(unlocked) do
        if not IsNonNegativeInteger(tier) or tier < 1 or tier > tierCount or value ~= true then
            error("Ashoholic received invalid Torment unlocks.")
        end
        copiedUnlocks[tier] = true
    end
    if not copiedUnlocks[1] then
        error("Ashoholic Torment data must include Normal access.")
    end

    character.torment = {
        currentTier = snapshot.currentTier,
        unlockedTiers = copiedUnlocks,
        updatedAt = snapshot.updatedAt,
    }
    NotifyRosterChanged()
end

local function CopyRaidLocks(lockedUntil)
    RequireTable(lockedUntil, "raid loot locks")
    local copy = {}
    for bossId, endsAt in pairs(lockedUntil) do
        if not IsNonNegativeInteger(bossId) or bossId == 0
            or not IsNonNegativeInteger(endsAt) or endsAt == 0 then
            error("Ashoholic received an invalid raid loot lock.")
        end
        copy[bossId] = endsAt
    end
    return copy
end

-- A complete reply replaces the old group, including an empty reply. A missing
-- group is different: no server observation has been received yet.
function Data.SaveCharacterRaids(realmName, characterName, guid, snapshot)
    local character = RequireCharacter(realmName, characterName, guid, "raid data")
    RequireObservation(snapshot, "raid data")
    character.raids = {
        lockedUntil = CopyRaidLocks(snapshot.lockedUntil),
        updatedAt = snapshot.updatedAt,
    }
    NotifyRosterChanged()
end

-- Account currencies are shared by every character on this WoW account, so
-- they need no character identity. A new server update replaces the whole
-- group, including decreases after spending. Run currencies are never added
-- here, and Warband gold stays unknown because it has no readable source.
function Data.SaveAccountCurrencies(snapshot)
    if not database then
        error("Ashoholic account currencies were saved before Data.Initialize().")
    end
    RequireTable(snapshot, "account currency snapshot")
    if not IsNonNegativeInteger(snapshot.ashSpendable)
        or not IsNonNegativeInteger(snapshot.ashBanked)
        or not IsNonNegativeInteger(snapshot.updatedAt) or snapshot.updatedAt == 0 then
        error("Ashoholic account currencies need Soul Ash balances and an observation time.")
    end

    -- The other currencies arrive as spendable/banked pairs. Both values must
    -- be known, or both stay unknown (nil); half of a pair is rejected.
    for _, currency in ipairs(POOL_CURRENCIES) do
        local spendable = snapshot[currency .. "Spendable"]
        local banked = snapshot[currency .. "Banked"]
        local bothUnknown = spendable == nil and banked == nil
        local bothKnown = IsNonNegativeInteger(spendable) and IsNonNegativeInteger(banked)
        if not bothUnknown and not bothKnown then
            error("Ashoholic received an incomplete " .. currency .. " balance.")
        end
    end

    local account = RequireTable(database.accounts[database.myAccountId], "current account")
    account.currencies = {
        ashSpendable = snapshot.ashSpendable,
        ashBanked = snapshot.ashBanked,
        shardSpendable = snapshot.shardSpendable,
        shardBanked = snapshot.shardBanked,
        essenceSpendable = snapshot.essenceSpendable,
        essenceBanked = snapshot.essenceBanked,
        artisanSpendable = snapshot.artisanSpendable,
        artisanBanked = snapshot.artisanBanked,
        updatedAt = snapshot.updatedAt,
    }
    NotifyRosterChanged()
end

-- Copy an account's saved currencies for the UI, or return nil when they have
-- not been received yet.
local function CopyAccountCurrencies(account, accountId)
    local currencies = account.currencies
    if currencies == nil then
        return nil
    end
    RequireTable(currencies, "currencies for account " .. tostring(accountId))

    return {
        ashSpendable = currencies.ashSpendable,
        ashBanked = currencies.ashBanked,
        shardSpendable = currencies.shardSpendable,
        shardBanked = currencies.shardBanked,
        essenceSpendable = currencies.essenceSpendable,
        essenceBanked = currencies.essenceBanked,
        artisanSpendable = currencies.artisanSpendable,
        artisanBanked = currencies.artisanBanked,
        updatedAt = currencies.updatedAt,
    }
end

local function CopyTorment(character)
    if character.torment == nil then
        return nil
    end
    local source = RequireTable(character.torment, "Torment data")
    local unlocked = RequireTable(source.unlockedTiers, "Torment unlocks")
    local copy = {
        currentTier = source.currentTier,
        updatedAt = source.updatedAt,
        unlockedTiers = {},
    }
    for tier in pairs(unlocked) do
        copy.unlockedTiers[tier] = true
        if not copy.highestUnlocked or tier > copy.highestUnlocked then
            copy.highestUnlocked = tier
        end
    end
    return copy
end

local function CopyRaids(character)
    if character.raids == nil then
        return nil
    end
    local raids = RequireTable(character.raids, "raid data")
    RequireObservation(raids, "raid data")
    return {
        lockedUntil = CopyRaidLocks(raids.lockedUntil),
        updatedAt = raids.updatedAt,
    }
end

-- Return a display-safe copy of the saved roster.
-- The UI receives only the fields it needs and cannot change AshoholicDB by
-- editing the tables returned here.
function Data.GetRoster()
    if not database then
        error("Ashoholic roster was requested before Data.Initialize().")
    end

    local roster = {}
    for accountId, account in pairs(database.accounts) do
        RequireTable(account, "account " .. tostring(accountId))

        local accountEntry = {
            id = accountId,
            name = account.name,
            isCurrent = accountId == database.myAccountId,
            currencies = CopyAccountCurrencies(account, accountId),
            prestige = CopyOptionalGroup(account, "prestige", PRESTIGE_FIELDS),
            characters = {},
        }
        local realms = account.realms
        if realms ~= nil then
            RequireTable(realms, "realms for account " .. tostring(accountId))

            for realmName, characters in pairs(realms) do
                RequireTable(characters, "characters on realm " .. tostring(realmName))

                for characterName, character in pairs(characters) do
                    RequireTable(character, "character " .. tostring(characterName))

                    if character.basics ~= nil then
                        local basics = RequireTable(
                            character.basics,
                            "basics for " .. tostring(characterName)
                        )
                        local run = character.run
                        if run ~= nil then
                            RequireTable(run, "run data for " .. tostring(characterName))
                        end
                        table.insert(accountEntry.characters, {
                            name = characterName,
                            realm = realmName,
                            guid = basics.guid,
                            class = basics.class,
                            level = basics.level,
                            gold = basics.gold,
                            location = basics.location,
                            lastSeen = basics.updatedAt,
                            runAsh = run and run.soulAsh,
                            runShards = run and run.soulShards,
                            runUpdatedAt = run and run.updatedAt,
                            contracts = CopyOptionalGroup(character, "contracts", CONTRACT_FIELDS),
                            echoBuild = CopyOptionalGroup(character, "echoBuild", ECHO_BUILD_FIELDS),
                            torment = CopyTorment(character),
                            raids = CopyRaids(character),
                        })
                    end
                end
            end
        end

        table.sort(accountEntry.characters, function(left, right)
            if left.realm ~= right.realm then
                return left.realm < right.realm
            end
            return left.name < right.name
        end)
        table.insert(roster, accountEntry)
    end

    table.sort(roster, function(left, right)
        local leftName = left.name or left.id
        local rightName = right.name or right.id
        if leftName ~= rightName then
            return leftName < rightName
        end
        return left.id < right.id
    end)

    return roster
end

local function CopyWatchlist(watched)
    RequireTable(watched, "encounter watchlist")
    local copy = {}
    for key, selected in pairs(watched) do
        if type(key) ~= "string" or key == "" or selected ~= true then
            error("Ashoholic received an invalid encounter selection.")
        end
        copy[key] = true
    end
    return copy
end

function Data.GetEncounterWatchlist()
    if not database then
        error("Ashoholic encounter watchlist was requested before Data.Initialize().")
    end
    local ui = database.settings.ui
    if ui == nil then
        return {}
    end
    RequireTable(ui, "UI settings")
    local raids = ui.raids
    if raids == nil then
        return {}
    end
    RequireTable(raids, "encounter settings")
    if raids.watched == nil then
        return {}
    end
    return CopyWatchlist(raids.watched)
end

function Data.SaveEncounterWatchlist(watched)
    if not database then
        error("Ashoholic encounter watchlist was saved before Data.Initialize().")
    end
    local copy = CopyWatchlist(watched)
    local settings = database.settings
    if settings.ui == nil then
        settings.ui = {}
    end
    local ui = RequireTable(settings.ui, "UI settings")
    if ui.raids == nil then
        ui.raids = {}
    end
    local raids = RequireTable(ui.raids, "encounter settings")
    raids.watched = copy
end

-- Return a small copy of the saved window position, never the settings table
-- itself. A missing position means the UI should use its default placement.
function Data.GetRosterPosition()
    if not database then
        error("Ashoholic roster position was requested before Data.Initialize().")
    end

    local settings = database.settings
    local ui = settings.ui
    if ui == nil then
        return nil
    end
    RequireTable(ui, "UI settings")

    local roster = ui.roster
    if roster == nil then
        return nil
    end
    RequireTable(roster, "roster settings")

    local position = roster.position
    if position == nil then
        return nil
    end
    RequireTable(position, "roster window position")

    if not ROSTER_ANCHOR_POINTS[position.point]
        or type(position.x) ~= "number"
        or type(position.y) ~= "number" then
        error("Ashoholic saved an invalid roster window position.")
    end

    return {
        point = position.point,
        x = position.x,
        y = position.y,
    }
end

-- Save the draggable roster's position through the Data layer.
function Data.SaveRosterPosition(point, x, y)
    if not database then
        error("Ashoholic roster position was saved before Data.Initialize().")
    end
    if not ROSTER_ANCHOR_POINTS[point]
        or type(x) ~= "number"
        or type(y) ~= "number" then
        error("Ashoholic cannot save an invalid roster window position.")
    end

    local settings = database.settings
    if settings.ui == nil then
        settings.ui = {}
    end
    local ui = RequireTable(settings.ui, "UI settings")

    if ui.roster == nil then
        ui.roster = {}
    end
    local roster = RequireTable(ui.roster, "roster settings")

    roster.position = {
        point = point,
        x = x,
        y = y,
    }
end
