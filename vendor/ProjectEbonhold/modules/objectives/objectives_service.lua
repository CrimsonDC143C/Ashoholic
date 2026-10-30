local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.ObjectivesService = {}

local Objectives = {}
Objectives.currentObjectives = {}
Objectives.activeObjective = nil

local function RequestObjectives()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_OBJECTIVES_PROPOSALS, "")
end

local function GetObjectiveRerollCost(level)
    return level * level * 15 + level * 100
end

local function RequestRerollObjectives()
    local cost = GetObjectiveRerollCost(UnitLevel("player"))
    if GetMoney() < cost then
        print("|cFFFF0000You don't have enough gold to reroll objectives. Cost: " .. GetCoinTextureString(cost) .. "|r")
        return
    end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_REROLL_OBJECTIVES, "")
end

function ProjectEbonhold.ObjectivesService.CanAffordReroll()
    return GetMoney() >= GetObjectiveRerollCost(UnitLevel("player"))
end

function ProjectEbonhold.ObjectivesService.GetRerollCost()
    return GetObjectiveRerollCost(UnitLevel("player"))
end

-- Quest objective types
local QUEST_OBJECTIVE_TYPE_OPEN_WORLD = 1
local QUEST_OBJECTIVE_TYPE_DUNGEON    = 2
local QUEST_OBJECTIVE_TYPE_RAID       = 3
local QUEST_OBJECTIVE_TYPE_PROFESSION = 4

-- Parse a single objective string into an objective table
-- Format: questId,title,objectives,zoneOrSort,questType,
--         normalSoulAshes,hc1SoulAshes,hc2SoulAshes,hc3SoulAshes,hc4SoulAshes,hc5SoulAshes,
--         normalXp,hc1Xp,hc2Xp,hc3Xp,hc4Xp,hc5Xp
local function ParseSingleObjective(objectiveStr)
    if not objectiveStr or objectiveStr == "" then
        return nil
    end

    -- split on commas KEEPING empty fields: an empty field must not shift
    -- the trailing numeric block
    local parts = {}
    for part in string.gmatch(objectiveStr .. ",", "([^,]*),") do
        table.insert(parts, part)
    end

    -- 17 fields with the hc5 tier, or legacy 15 fields without it; the
    -- objectives text (field 3) may contain commas, so the trailing fields
    -- are anchored from the end
    local n = #parts
    if n < 15 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Objectives:|r unparsable proposal ("
            .. n .. " fields): " .. string.sub(objectiveStr, 1, 80))
        return nil
    end
    local tiers    = (n >= 17) and 6 or 5      -- normal + hc1..hc4 [+ hc5]
    local trailing = 2 + tiers * 2             -- zoneOrSort, questType, ashes, xp

    local ashes, xp = {}, {}
    for i = 1, tiers do
        ashes[i] = tonumber(parts[n - 2 * tiers + i]) or 0
        xp[i]    = tonumber(parts[n - tiers + i]) or 0
    end
    local zoneOrSort    = parts[n - trailing + 1]
    local questType     = parts[n - trailing + 2]
    local objectiveText = table.concat(parts, ",", 3, n - trailing)

    return {
        questId          = tonumber(parts[1]) or 0,
        title            = parts[2],
        objectiveText    = objectiveText ~= "UNKNOWN_OBJECTIVE_TEXT" and objectiveText or "",
        zoneOrSort       = tonumber(zoneOrSort) or 0,
        questType        = tonumber(questType) or QUEST_OBJECTIVE_TYPE_OPEN_WORLD,
        normalSoulAshes  = ashes[1],
        hc1SoulAshes     = ashes[2],
        hc2SoulAshes     = ashes[3],
        hc3SoulAshes     = ashes[4],
        hc4SoulAshes     = ashes[5],
        hc5SoulAshes     = ashes[6] or 0,
        normalXp         = xp[1],
        hc1Xp            = xp[2],
        hc2Xp            = xp[3],
        hc3Xp            = xp[4],
        hc4Xp            = xp[5],
        hc5Xp            = xp[6] or 0,
    }
end

-- Parse multiple objectives separated by semicolons
local function ParseObjectiveData(body)
    local objectives = {}

    if not body or body == "" then
        return objectives
    end

    for objectiveStr in string.gmatch(body, "([^;]+)") do
        local objective = ParseSingleObjective(objectiveStr)
        if objective then
            table.insert(objectives, objective)
        end
    end

    return objectives
end

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_OBJECTIVES_PROPOSALS, function(body)
    Objectives.currentObjectives = ParseObjectiveData(body)
    -- Show/refresh the board with the new proposals. DisplayObjectives is a
    -- no-op unless the player is in the Objectives Board gossip, so this also
    -- covers proposals fetched on demand when the board was opened empty.
    if ProjectEbonhold.ObjectivesUI and ProjectEbonhold.ObjectivesUI.DisplayObjectives then
        ProjectEbonhold.ObjectivesUI.DisplayObjectives(Objectives.currentObjectives)
    end
end)

-- Handler for current active objective
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_CURRENT_OBJECTIVE, function(body)
    -- If body is empty, reset active objective and hide tracker
    if not body or body == "" then
        Objectives.activeObjective = nil
        if ProjectEbonhold.ObjectivesUI and ProjectEbonhold.ObjectivesUI.UpdateTracker then
            ProjectEbonhold.ObjectivesUI.UpdateTracker(nil)
        end
        return
    end

    Objectives.activeObjective = ParseSingleObjective(body)

    -- Update the tracker UI
    if ProjectEbonhold.ObjectivesUI and ProjectEbonhold.ObjectivesUI.UpdateTracker then
        ProjectEbonhold.ObjectivesUI.UpdateTracker(Objectives.activeObjective)
    end
end)

-- Initialize on player entering world
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        RequestObjectives()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

-- Export service functions
ProjectEbonhold.ObjectivesService.RequestObjectives = RequestObjectives
ProjectEbonhold.ObjectivesService.RequestRerollObjectives = RequestRerollObjectives
ProjectEbonhold.ObjectivesService.GetCurrentObjectives = function() return Objectives.currentObjectives end
ProjectEbonhold.ObjectivesService.GetActiveObjective = function() return Objectives.activeObjective end
