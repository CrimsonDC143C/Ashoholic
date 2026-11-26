-- Ashendor (2026-11-12): the quest log is this map's quest panel (owner: "j'ai l'ancien Quest log, je
-- veux le DragonUI").
--   * The stock log toggle (the L key, the Quests micro button) opens the map on its quest list, or
--     closes the map when it was open. The stock window is shut as it shows, which needs no
--     taint-prone replacement of a Blizzard function. Showing the stock log goes through the UI panel
--     manager, which hides the map just before (a frame earlier) to make room: a map hidden that
--     recently counts as open.
--   * WM.OpenQuestLogTo(index) opens the map on one quest's details; Project Ebonhold's quest tracker
--     calls it on a click (modules\questTracker\quest_tracker.lua).
-- Showing the map is protected in combat: then the stock log is closed and nothing opens.

local addon = DragonUI
local WM = addon.WorldMap

local mapHiddenAt

local function Usable()
    return WM:Enabled() and WM.listFrame ~= nil
end

function WM.OpenQuestLogTo(index)
    if not Usable() or not index or index <= 0 then return false end
    local _, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
    if isHeader then return false end
    if InCombatLockdown() and not WorldMapFrame:IsShown() then return true end
    SelectQuestLogEntry(index)
    if not (questID and WM.OpenToQuest(questID)) and not WorldMapFrame:IsShown() then
        ShowUIPanel(WorldMapFrame)
    end
    if WM.ShowQuestDetail then WM.ShowQuestDetail(index) end
    return true
end

WorldMapFrame:HookScript("OnHide", function() mapHiddenAt = GetTime() end)

QuestLogFrame:HookScript("OnShow", function()
    if not Usable() then return end
    -- the manager hides the map a frame before it shows the stock log (measured: ~10 ms apart)
    local wasOpen = WorldMapFrame:IsShown() or (mapHiddenAt and GetTime() - mapHiddenAt < 0.3)
    HideUIPanel(QuestLogFrame)
    if wasOpen then
        if WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) end
        return
    end
    if InCombatLockdown() then return end
    -- next frame: the panel manager is still placing the stock log in this one
    addon:After(0, function()
        if WorldMapFrame:IsShown() or InCombatLockdown() then return end
        ShowUIPanel(WorldMapFrame)
        if WM.HideQuestDetail then WM.HideQuestDetail() end
    end)
end)
