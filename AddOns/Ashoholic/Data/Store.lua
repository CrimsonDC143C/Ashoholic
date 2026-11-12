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

-- Returns a useful error rather than silently replacing unexpected saved data.
local function RequireTable(value, description)
    if type(value) ~= "table" then
        error("Ashoholic cannot use saved " .. description .. ": expected a table.")
    end
    return value
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

    -- Do not guess how a future or unknown schema should be converted.
    -- A real migration must be written before changing the saved layout.
    if database.schemaVersion ~= nil and database.schemaVersion ~= Schema.VERSION then
        error(
            "Ashoholic saved data uses schema version "
                .. tostring(database.schemaVersion)
                .. ", but this addon supports version "
                .. tostring(Schema.VERSION)
                .. ". A migration is required."
        )
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

    return character.basics
end
