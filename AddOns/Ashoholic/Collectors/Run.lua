-- Ebonhold run currencies belong to the logged-in character, not the account.
-- Keep an early server snapshot pending until WoW can identify that character.
-- The original observation time is preserved even if saving has to wait.
local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local Character = addon.Collectors.Character
local Integration = addon.Integrations.ProjectEbonhold

local pendingSnapshot

local function SavePendingSnapshot()
    if not pendingSnapshot then
        return
    end

    -- This also handles a deleted/recreated character before attaching run data.
    -- It returns no identity while the world is still loading.
    local realmName, characterName, guid = Character.Collect()
    if not realmName then
        return
    end

    Data.SaveCharacterRun(realmName, characterName, guid, pendingSnapshot)
    pendingSnapshot = nil
end

local frame = CreateFrame("Frame")
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
