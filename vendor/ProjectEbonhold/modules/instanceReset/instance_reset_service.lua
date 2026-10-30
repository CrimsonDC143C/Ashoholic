local addonName, addon = ...

-- Initialize module namespace
if not addon.InstanceReset then
    addon.InstanceReset = {}
end

-- Cached action data
addon.InstanceReset.actionData = {
    actionId = ProjectEbonhold.ActionTypes.INSTANCE_RESET,
    count = 0,
    nextResetTime = 0,
    cost = 0,
}

-- Request action tracker info from server
function addon.InstanceReset.RequestActionTrackerInfo()
    local actionId = ProjectEbonhold.ActionTypes.INSTANCE_RESET
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ACTION_TRACKER_INFO, tostring(actionId))
end

-- Request instance reset
function addon.InstanceReset.RequestInstanceResetAll()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_INSTANCE_RESET_ALL, "")
end

-- Calculate display cost based on current count
function addon.InstanceReset.CalculateCost(count)
    local cost = ProjectEbonhold.InstanceResetConfig.BASE_COST
    for i = 1, count do
        cost = cost * ProjectEbonhold.InstanceResetConfig.COST_MULTIPLIER
        if cost > 2147483647 then
            return 2147483647
        end
    end
    return cost
end

-- Format time remaining until reset
function addon.InstanceReset.FormatTimeRemaining(nextResetTime)
    if nextResetTime == 0 then
        return "Not configured"
    end
    
    local currentTime = time()
    local secondsRemaining = nextResetTime - currentTime
    
    -- If time has passed, the server should have recalculated on next login
    -- Just show the time until next reset (negative will wrap to next week)
    if secondsRemaining < 0 then
        secondsRemaining = 0
    end
    
    local days = math.floor(secondsRemaining / 86400)
    local hours = math.floor((secondsRemaining % 86400) / 3600)
    local minutes = math.floor((secondsRemaining % 3600) / 60)
    
    if days > 0 then
        return string.format("%dd %dh %dm", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm", minutes)
    else
        return "less than a minute"
    end
end

-- Event: Received action tracker info from server
-- Body format: "actionId,count,nextResetTime"
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_ACTION_TRACKER_INFO, function(body)
    local actionId, count, nextResetTime = string.match(body, "^(%d+),(%d+),(%d+)$")
    
    if not actionId then
        print("|cffFF0000[Instance Reset] Failed to parse action tracker info|r")
        return
    end
    
    actionId = tonumber(actionId)
    count = tonumber(count)
    nextResetTime = tonumber(nextResetTime)
    
    if actionId ~= ProjectEbonhold.ActionTypes.INSTANCE_RESET then
        return
    end
    
    -- Update cached data
    addon.InstanceReset.actionData.count = count
    addon.InstanceReset.actionData.nextResetTime = nextResetTime
    addon.InstanceReset.actionData.cost = addon.InstanceReset.CalculateCost(count)
    
    -- Update UI if frame exists
    if addon.InstanceReset.UpdateUI then
        addon.InstanceReset.UpdateUI()
    end
end)

-- Event: Received instance reset result from server
-- Body format: "resultCode,cost"
-- Result codes: 0=Success, 1=In dungeon, 2=No lockouts, 3=Insufficient currency, 4=Unknown error, 5=In combat, 6=In group
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_INSTANCE_RESET_RESULT, function(body)
    local resultCode, cost = string.match(body, "^(%d+),(%d+)$")
    
    if not resultCode then
        print("|cffFF0000[Instance Reset] Failed to parse reset result|r")
        return
    end
    
    resultCode = tonumber(resultCode)
    cost = tonumber(cost)
    
    if resultCode == 0 then
        -- Success - server already sent chat message
        -- Increment local count to update UI immediately
        addon.InstanceReset.actionData.count = addon.InstanceReset.actionData.count + 1
        addon.InstanceReset.actionData.cost = addon.InstanceReset.CalculateCost(addon.InstanceReset.actionData.count)
        
        -- Update UI
        if addon.InstanceReset.UpdateUI then
            addon.InstanceReset.UpdateUI()
        end
        
        -- Close the social frame after a brief delay so the UI refreshes properly
        C_Timer.After(0.1, function()
            if FriendsFrame and FriendsFrame:IsVisible() then
                HideUIPanel(FriendsFrame)
            end
        end)
    elseif resultCode == 1 then
        print("|cffFF0000[Instance Reset] You must leave the dungeon or raid first!|r")
    elseif resultCode == 2 then
        print("|cffFF0000[Instance Reset] You have no instance lockouts to reset.|r")
    elseif resultCode == 3 then
        print("|cffFF0000[Instance Reset] Insufficient Soul Ashes! Cost: " .. cost .. "|r")
    elseif resultCode == 5 then
        print("|cffFF0000[Instance Reset] You cannot reset instances while in combat!|r")
    elseif resultCode == 6 then
        print("|cffFF0000[Instance Reset] You cannot reset instances while in a group!|r")
    else
        print("|cffFF0000[Instance Reset] Unknown error occurred.|r")
    end
end)

-- Request initial data on login
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Delay request by 2 seconds to ensure server is ready
        C_Timer.After(2, function()
            addon.InstanceReset.RequestActionTrackerInfo()
        end)
    end
end)
