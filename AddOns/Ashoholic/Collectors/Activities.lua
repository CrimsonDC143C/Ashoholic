-- Route independent Call Board and Trial observations to the Data layer.
-- Early replies wait for SavedVariables and a complete character identity.
local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local Character = addon.Collectors and addon.Collectors.Character
local Integration = addon.Integrations and addon.Integrations.ProjectEbonhold

if not Data or not Character or not Integration then
    error("Ashoholic Collectors/Activities.lua loaded before its dependencies.")
end

local pending = {}
local ready = false
local elapsed = 0
local frame = CreateFrame("Frame")
local RetryWhilePending

local function HasPending()
    return pending.activities or pending.champion or pending.crusader
end

local function SavePending()
    if not HasPending() then
        frame:SetScript("OnUpdate", nil)
        elapsed = 0
        return
    end
    if not ready then return end

    -- Character.Collect handles deleted/recreated characters before any
    -- observation attaches to their record.
    local realm, name, guid = Character.Collect()
    if not realm then
        frame:SetScript("OnUpdate", RetryWhilePending)
        return
    end
    if pending.activities then
        local snapshot = pending.activities
        pending.activities = nil
        Data.SaveCharacterActivities(realm, name, guid, snapshot)
    end
    for _, group in ipairs({ "champion", "crusader" }) do
        if pending[group] then
            local snapshot = pending[group]
            pending[group] = nil
            Data.SaveCharacterTrial(realm, name, guid, group, snapshot)
        end
    end
    frame:SetScript("OnUpdate", nil)
    elapsed = 0
end

RetryWhilePending = function(_, delta)
    elapsed = elapsed + delta
    if elapsed >= 1 then
        elapsed = 0
        SavePending()
    end
end

Integration.WatchActivities(function(snapshot)
    pending.activities = snapshot
    SavePending()
end)
Integration.WatchTrials(function(group, snapshot)
    pending[group] = snapshot
    SavePending()
end)

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ready = true
        frame:UnregisterEvent("PLAYER_LOGIN")
    end
    SavePending()
end)
