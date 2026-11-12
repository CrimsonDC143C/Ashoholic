-- Ebonhold run currencies belong to the logged-in character, not the account.
-- Keep an early server snapshot pending until WoW can identify that character.
-- The original observation time is preserved even if saving has to wait.
local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local Character = addon.Collectors.Character
local Integration = addon.Integrations.ProjectEbonhold

local pendingSnapshot

-- On a real login, Ebonhold can send run currencies before WoW knows the zone.
-- While a snapshot is waiting, try again once per second until it can be saved.
local RETRY_SECONDS = 1
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

    -- This also handles a deleted/recreated character before attaching run data.
    -- It returns no identity while the world is still loading.
    local realmName, characterName, guid = Character.Collect()
    if not realmName then
        frame:SetScript("OnUpdate", RetryWhilePending)
        return
    end

    -- Clear first, so a rejected snapshot reports one error instead of retrying.
    local snapshot = pendingSnapshot
    pendingSnapshot = nil
    StopRetrying()
    Data.SaveCharacterRun(realmName, characterName, guid, snapshot)
end

RetryWhilePending = function(_, elapsed)
    retryElapsed = retryElapsed + elapsed
    if retryElapsed >= RETRY_SECONDS then
        retryElapsed = 0
        SavePendingSnapshot()
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- All ADDON_LOADED handlers, including database initialization, have
        -- completed by PLAYER_LOGIN. Install one observer for this session.
        frame:UnregisterEvent("PLAYER_LOGIN")
        Integration.WatchRunCurrencies(function(snapshot)
            pendingSnapshot = snapshot
            SavePendingSnapshot()
        end)
    else
        SavePendingSnapshot()
    end
end)
