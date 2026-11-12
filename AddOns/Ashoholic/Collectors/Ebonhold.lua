-- The remaining Ebonhold groups share startup/identity handling, but not data
-- or timestamps. Each observer hands over an independent snapshot; this file
-- only routes it to the matching Data writer.
local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local Character = addon.Collectors and addon.Collectors.Character
local Integration = addon.Integrations and addon.Integrations.ProjectEbonhold

if not Data or not Character or not Integration then
    error("Ashoholic Collectors/Ebonhold.lua loaded before its data, character or integration modules.")
end

local pending = {}
local databaseReady = false
local CHARACTER_WRITERS = {
    torment = Data.SaveCharacterTorment,
    contracts = Data.SaveCharacterContracts,
    echoBuild = Data.SaveCharacterEchoBuild,
}

local function SavePendingSnapshots()
    if not databaseReady then
        return
    end
    if pending.prestige then
        local snapshot = pending.prestige
        pending.prestige = nil
        Data.SaveAccountPrestige(snapshot)
    end
    if not pending.torment and not pending.contracts and not pending.echoBuild then
        return
    end

    -- Basics handles recreated characters before any of these groups attach.
    -- Leave early replies pending until the world provides a complete identity.
    local realmName, characterName, guid = Character.Collect()
    if not realmName then
        return
    end
    for group, save in pairs(CHARACTER_WRITERS) do
        if pending[group] then
            local snapshot = pending[group]
            pending[group] = nil
            save(realmName, characterName, guid, snapshot)
        end
    end
end

local function Receive(group)
    return function(snapshot)
        pending[group] = snapshot
        SavePendingSnapshots()
    end
end

Data.SetProgressionRules(Integration.GetProgressionRules())
-- Start observing before login replies arrive. Saving waits until every
-- ADDON_LOADED handler, including database initialization, has completed.
Integration.WatchPrestige(Receive("prestige"))
Integration.WatchTorment(Receive("torment"))
Integration.WatchContracts(Receive("contracts"))
Integration.WatchEchoBuild(Receive("echoBuild"))

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        databaseReady = true
        frame:UnregisterEvent("PLAYER_LOGIN")
    end
    SavePendingSnapshots()
end)
