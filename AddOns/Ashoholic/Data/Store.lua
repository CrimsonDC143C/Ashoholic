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

    return character.basics
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
                        table.insert(accountEntry.characters, {
                            name = characterName,
                            realm = realmName,
                            guid = basics.guid,
                            class = basics.class,
                            level = basics.level,
                            gold = basics.gold,
                            location = basics.location,
                            lastSeen = basics.updatedAt,
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
