local addonName, addon = ...

-- Initialize module namespace
if not addon.InstanceFollowup then
    addon.InstanceFollowup = {}
end

addon.InstanceFollowup.currentDungeonId = nil

-- Event: Player entered a dungeon
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_INSTANCE_ENTERED, function(body)
    local dungeonId = tonumber(body)
    -- Store the dungeon ID
    addon.InstanceFollowup.currentDungeonId = dungeonId
    
    -- Display all bosses to kill in the dungeon
    local dungeonData = addon.INSTANCE_FOLLOWUP_DATA[dungeonId]
    if dungeonData then
        print("|cff00ff00=== Bosses to Kill ===|r")
        for encounterEntry, bossName in pairs(dungeonData) do
            print("  • " .. bossName)
        end
        print("|cff00ff00=====================|r")
    end
end)

-- Event: Player completed encounters (receives comma-separated encounter entries)
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_INSTANCE_ENCOUNTERS_COMPLETED, function(body)
    local currentDungeonId = addon.InstanceFollowup.currentDungeonId
    if not currentDungeonId then
        return
    end
    
    -- Parse the comma-separated encounter entries
    local completedEncounters = {}
    for encounterEntry in string.gmatch(body, "([^,]+)") do
        local encounterId = tonumber(encounterEntry)
        if encounterId then
            completedEncounters[encounterId] = true
        end
    end
    
    -- Display remaining bosses (those not yet completed)
    local dungeonData = addon.INSTANCE_FOLLOWUP_DATA[currentDungeonId]
    if dungeonData then
        local remainingBosses = {}
        local completedBosses = {}
        
        for encounterEntry, bossName in pairs(dungeonData) do
            if completedEncounters[encounterEntry] then
                table.insert(completedBosses, bossName)
            else
                table.insert(remainingBosses, bossName)
            end
        end
        
        -- Display completed bosses
        if #completedBosses > 0 then
            print("|cff888888=== Bosses Killed ===|r")
            for _, bossName in ipairs(completedBosses) do
                print("  |cff888888• " .. bossName .. "|r")
            end
        end
        
        -- Display remaining bosses
        if #remainingBosses > 0 then
            print("|cff00ff00=== Bosses Remaining ===|r")
            for _, bossName in ipairs(remainingBosses) do
                print("  • " .. bossName)
            end
            print("|cff00ff00========================|r")
        else
            print("|cffffd700=== All Bosses Defeated! ===|r")
        end
    end
end)

-- Event: Hide instance encounters
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_INSTANCE_ENCOUNTERS_HIDE, function(body)
    -- Reset current dungeon ID
    addon.InstanceFollowup.currentDungeonId = nil
end)
