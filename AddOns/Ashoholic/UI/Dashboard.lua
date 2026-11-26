-- Coordinate live data updates, reminders and window lifecycle.
local addonName = ...
local addon = _G[addonName]
local UI, Data = addon.UI, addon.Data
local ready, started, elapsed = false, false, 0

local function RefreshData()
    if not started then return end
    UI.ReadModel()
    UI.UpdateAlerts()
    UI.Refresh()
    UI.RefreshSettings()
end

-- Wait until the character collector has identified the player, so a
-- character-specific profile is selected correctly after login.
local function Start()
    if started or not ready or not Data.GetCurrentCharacterKey() then return end
    started = true
    UI.LoadSettings()
    UI.ReadModel()
    UI.UpdateAlerts()
    if UI.state.window.openLogin then addon:ShowRosterUI() end
end

Data.OnRosterChanged(function()
    UI.MarkModelDirty()
    UI.NextFrame(Start)
    UI.NextFrame(RefreshData)
end)

function addon:ToggleRosterUI()
    addon.Collectors.Currencies.RequestBalancesIfNeeded()
    UI.ToggleWindow()
end

function addon:ShowRosterUI()
    addon.Collectors.Currencies.RequestBalancesIfNeeded()
    return UI.ShowWindow()
end

function UI.RefreshRoster()
    UI.MarkModelDirty()
    UI.NextFrame(RefreshData)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ready = true
        UI.NextFrame(Start)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if started and UI.state.window.combatHide and UI.frame and UI.frame:IsShown() then
            UI.hidingForCombat = true
            UI.frame:Hide()
            UI.hidingForCombat = false
        end
    elseif event == "PLAYER_LOGOUT" then
        UI.SaveSettings()
    end
end)
events:SetScript("OnUpdate", function(_, delta)
    if not started then return end
    elapsed = elapsed + delta
    if elapsed < 30 then return end
    elapsed = 0
    UI.ReadModel(true)
    UI.ArmAlerts()
    UI.UpdateAlerts()
    UI.Refresh()
end)
