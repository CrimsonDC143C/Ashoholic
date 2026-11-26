-- Collect the current character's raid loot observations. The companion
-- requests and receives the data; this collector only listens and saves it.
local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local Character = addon.Collectors and addon.Collectors.Character
local Integration = addon.Integrations and addon.Integrations.ProjectEbonhold

if not Data or not Character or not Integration then
    error("Ashoholic Collectors/Raids.lua loaded before its data, character or integration modules.")
end

-- This catalogue is shared by all characters and is not saved as a snapshot.
Data.SetEncounterCatalog(Integration.GetRaidCatalog())

local pendingSnapshot
local databaseReady = false
local retryElapsed = 0
local frame = CreateFrame("Frame")
local RetryWhilePending

local function StopRetrying()
    frame:SetScript("OnUpdate", nil)
    retryElapsed = 0
end

local function SavePendingSnapshot()
    if not pendingSnapshot then
        StopRetrying()
        return
    end
    if not databaseReady then
        return
    end

    -- Login replies may arrive before the character's zone and GUID are ready.
    -- Keep their original observation time while waiting for a full identity.
    local realmName, characterName, guid = Character.Collect()
    if not realmName then
        frame:SetScript("OnUpdate", RetryWhilePending)
        return
    end

    local snapshot = pendingSnapshot
    pendingSnapshot = nil
    StopRetrying()
    Data.SaveCharacterRaids(realmName, characterName, guid, snapshot)
end

RetryWhilePending = function(_, elapsed)
    retryElapsed = retryElapsed + elapsed
    if retryElapsed >= 1 then
        retryElapsed = 0
        SavePendingSnapshot()
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        databaseReady = true
        frame:UnregisterEvent("PLAYER_LOGIN")
    end
    SavePendingSnapshot()
end)

-- Listen during addon loading, before the server's normal login update.
Integration.WatchRaidLoot(function(snapshot)
    pendingSnapshot = snapshot
    SavePendingSnapshot()
end)
