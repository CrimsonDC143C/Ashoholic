local addon, Addon = ...

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.LevelUpService = {}

local MAX_ACTION_SLOTS = 120
local MAX_REMOVAL_ATTEMPTS = 8
local pendingSpellPlacements = {}
local isProcessingQueuedPlacements = false
local ProcessPendingSpellPlacements

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LEVEL_UP" then
        local newLevel = ...
        local spellIds = {}

        if newLevel >= 10 then
            table.insert(spellIds, -1)
        end

        if newLevel == 15 then
            table.insert(spellIds, -2)
        end

        if ProjectEbonhold.LevelUpUI and ProjectEbonhold.LevelUpUI.Show then
            ProjectEbonhold.LevelUpUI.Show(newLevel, spellIds)
        end
    end
end)


ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_LEARNED_SPELL_ON_LEVEL_UP, function(body)
    local spellData = {}
    if body and body ~= "" then
        for entry in string.gmatch(body, "([^,]+)") do
            local spellId, rank = string.match(entry, "^(%d+);(%d+);(%d+);(.+)$")
            local id = tonumber(spellId)
            local rankNum = tonumber(rank) or 1
            if id then
                table.insert(spellData, {
                    spellId = id,
                    rank = rankNum,
                })
            end
        end
    end

    if ProjectEbonhold.LevelUpUI and ProjectEbonhold.LevelUpUI.AddSpells then
        ProjectEbonhold.LevelUpUI.AddSpells(spellData)
    end
end)
