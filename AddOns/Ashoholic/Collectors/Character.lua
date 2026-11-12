--[[
================================================================================
 Collectors/Character.lua - COLLECT BASIC FACTS ABOUT THE LOGGED-IN CHARACTER
================================================================================

 This file listens for ordinary WoW events that can change a character's
 basics. It reads the live values from WoW and hands a small snapshot to
 addon.Data. It never writes AshoholicDB directly.

 Stage 2 stores only these basics: character GUID, class, level, gold, zone,
 and the time the character was last seen. Run, raid, currency, and other
 ProjectEbonhold information are later stages.
]]

local addonName = ...
local addon = _G[addonName]
local Data = addon.Data

if not Data then
    error("Ashoholic Collectors/Character.lua loaded before Data/Store.lua.")
end

local CharacterCollector = {}
addon.Collectors = addon.Collectors or {}
addon.Collectors.Character = CharacterCollector

-- The WoW APIs can briefly return incomplete values while the world is
-- loading. In that case, wait for the next event instead of saving a partial
-- character under an empty or incorrect identity.
function CharacterCollector.Collect()
    local characterName = UnitName("player")
    local realmName = GetRealmName()
    local guid = UnitGUID("player")

    if type(characterName) ~= "string" or characterName == ""
        or type(realmName) ~= "string" or realmName == ""
        or type(guid) ~= "string" or guid == "" then
        return
    end

    local _, classToken = UnitClass("player")
    local level = UnitLevel("player")
    local gold = GetMoney()
    local location = GetRealZoneText()

    -- Wait until the game has supplied every Stage 2 field. This avoids
    -- replacing a previously complete snapshot with temporary loading values.
    if type(classToken) ~= "string" or classToken == ""
        or type(level) ~= "number" or level <= 0
        or type(gold) ~= "number"
        or type(location) ~= "string" or location == "" then
        return
    end

    Data.SaveCharacterBasics(realmName, characterName, {
        guid = guid,
        class = classToken,
        level = level,
        gold = gold,
        location = location,
    })
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(_, event, loadedAddonName)
    if event == "ADDON_LOADED" then
        if loadedAddonName ~= addonName then
            return
        end

        -- SavedVariables are ready by this event. Set up the database before
        -- registering the events that will collect character information.
        Data.Initialize()
        frame:UnregisterEvent("ADDON_LOADED")

        frame:RegisterEvent("PLAYER_LOGIN")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("PLAYER_LEVEL_UP")
        frame:RegisterEvent("PLAYER_MONEY")
        frame:RegisterEvent("ZONE_CHANGED")
        frame:RegisterEvent("ZONE_CHANGED_INDOORS")
        frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frame:RegisterEvent("PLAYER_LOGOUT")
        return
    end

    CharacterCollector.Collect()
end)
