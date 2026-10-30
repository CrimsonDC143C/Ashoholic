



local DEBUG_ENABLED = false 


local function DebugPrint(message, ...)
  if DEBUG_ENABLED then
    if select("#", ...) > 0 then
      print("|cffFFFF00[skillTree Debug]|r " .. string.format(message, ...))
    else
      print("|cffFFFF00[skillTree Debug]|r " .. message)
    end
  end
end


function skillTree_DebugConnections(nodeId)
  if not nodeId then
    print("|cffFF0000Usage: skillTree_DebugConnections(nodeId)|r")
    return
  end
  
  print("|cff00FF00=== DEBUGGING NODE " .. nodeId .. " ===|r")
  
  local btn = nodesById[nodeId]
  if not btn then
    print("|cffFF0000Node " .. nodeId .. " not found!|r")
    return
  end
  
  
  print("Node ID: " .. nodeId)
  print("State: " .. (btn.state or "unknown"))
  print("Is Starting Node: " .. tostring(isStartingNode and isStartingNode(nodeId) or "unknown"))
  print("Current Rank: " .. (getNodeRank and getNodeRank(nodeId) or "unknown"))
  print("Is Multiple Choice: " .. tostring(btn.isMultipleChoice or false))
  
  if btn.isMultipleChoice then
    print("Selected Choice: " .. (nodeChoices[nodeId] or 0))
  end
  
  
  if getConnectedNodes then
    local connectedNodes = getConnectedNodes(nodeId)
    print("Connected Nodes (" .. #connectedNodes .. "):")
    for i, connectedId in ipairs(connectedNodes) do
      local connectedBtn = nodesById[connectedId]
      if connectedBtn then
        local status = connectedBtn.state or "unknown"
        local rank = getNodeRank and getNodeRank(connectedId) or 0
        local isTaken = false
        
        if connectedBtn.isMultipleChoice then
          isTaken = (nodeChoices[connectedId] or 0) ~= 0
        else
          isTaken = rank > 0
        end
        
        print("  - Node " .. connectedId .. ": " .. status .. " (Rank: " .. rank .. ", Taken: " .. tostring(isTaken) .. ")")
      else
        print("  - Node " .. connectedId .. ": NOT FOUND")
      end
    end
  else
    print("getConnectedNodes function not available")
  end
  
  
  if canUpgradeNode then
    print("Can Upgrade: " .. tostring(canUpgradeNode(nodeId)))
  end
  if canDowngradeNode then
    print("Can Downgrade: " .. tostring(canDowngradeNode(nodeId)))
  end
  if canAffordTalent then
    print("Can Afford: " .. tostring(canAffordTalent(nodeId)))
  end
  
  print("|cff00FF00=== END DEBUG ===|r")
end


function skillTree_DebugTree()
  print("|cff00FF00=== TREE STATE DEBUG ===|r")
  
  
  local totalNodes = 0
  local activeNodes = 0
  local readyNodes = 0
  local lockedNodes = 0
  local startingNodes = 0
  
  for nodeId, btn in pairs(nodesById or {}) do
    totalNodes = totalNodes + 1
    
    if btn.state == "active" then
      activeNodes = activeNodes + 1
    elseif btn.state == "ready" or btn.state == "nopoints" then
      readyNodes = readyNodes + 1
    else
      lockedNodes = lockedNodes + 1
    end
    
    if isStartingNode and isStartingNode(nodeId) then
      startingNodes = startingNodes + 1
    end
  end
  
  print("Total Nodes: " .. totalNodes)
  print("Active Nodes: " .. activeNodes)
  print("Ready Nodes: " .. readyNodes)
  print("Locked Nodes: " .. lockedNodes)
  print("Starting Nodes: " .. startingNodes)
  
  
  if TALENT_POINTS_TOTAL then
    print("Soul Ashes Available: " .. TALENT_POINTS_TOTAL)
  end
  
  
  if currentClass then
    print("Current Class: " .. currentClass)
  end
  
  print("|cff00FF00=== END TREE DEBUG ===|r")
end


function skillTree_DebugStartingNodes()
  if not isStartingNode then
    print("|cffFF0000isStartingNode function not available|r")
    return
  end
  
  local startingNodesList = {}
  for nodeId, btn in pairs(nodesById or {}) do
    if isStartingNode(nodeId) then
      table.insert(startingNodesList, nodeId)
    end
  end
  
  table.sort(startingNodesList)
  
  print("Starting Nodes Found: " .. #startingNodesList)
  for _, nodeId in ipairs(startingNodesList) do
    local btn = nodesById[nodeId]
    local state = btn and btn.state or "unknown"
    local rank = getNodeRank and getNodeRank(nodeId) or 0
    print("  - Node " .. nodeId .. ": " .. state .. " (Rank: " .. rank .. ")")
  end
  
  print("|cff00FF00=== END STARTING NODES DEBUG ===|r")
end


function skillTree_DebugAllConnections()
  print("|cff00FF00=== ALL CONNECTIONS DEBUG ===|r")
  
  if not getConnectedNodes then
    print("|cffFF0000getConnectedNodes function not available|r")
    return
  end
  
  local nodeIds = {}
  for nodeId, _ in pairs(nodesById or {}) do
    table.insert(nodeIds, nodeId)
  end
  table.sort(nodeIds)
  
  for _, nodeId in ipairs(nodeIds) do
    local connectedNodes = getConnectedNodes(nodeId)
    if #connectedNodes > 0 then
      print("Node " .. nodeId .. " connected to: " .. table.concat(connectedNodes, ", "))
    else
      print("Node " .. nodeId .. " has no connections")
    end
  end
  
  print("|cff00FF00=== END ALL CONNECTIONS DEBUG ===|r")
end


function skillTree_DebugLoadouts()
  print("|cff00FF00=== LOADOUTS DEBUG ===|r")
  
  if not savedLoadouts then
    print("|cffFF0000savedLoadouts not available|r")
    return
  end
  
  local count = 0
  for name, loadout in pairs(savedLoadouts) do
    count = count + 1
    print("Loadout: " .. name)
    print("  Class: " .. (loadout.class or "unknown"))
    print("  Talents: " .. (loadout.talents and #loadout.talents or "0"))
    print("  Ranks: " .. (loadout.ranks and "available" or "not available"))
    print("  Choices: " .. (loadout.choices and "available" or "not available"))
  end
  
  if count == 0 then
    print("No saved loadouts found")
  end
  
  print("Current Loadout: " .. (currentLoadoutName or "none"))
  print("|cff00FF00=== END LOADOUTS DEBUG ===|r")
end


function skillTree_ToggleDebug()
  DEBUG_ENABLED = not DEBUG_ENABLED
  print("|cff00FF00skillTree Debug: " .. (DEBUG_ENABLED and "ENABLED" or "DISABLED") .. "|r")
  return DEBUG_ENABLED
end


function skillTree_DebugHelp()
  print("|cff00FF00=== skillTree DEBUG COMMANDS ===|r")
  print("/script skillTree_DebugConnections(nodeId) - Debug specific node connections")
  print("/script skillTree_DebugTree() - Debug overall tree state")
  print("/script skillTree_DebugStartingNodes() - List all starting nodes")
  print("/script skillTree_DebugAllConnections() - Show all node connections")
  print("/script skillTree_DebugLoadouts() - Debug saved loadouts")
  print("/script skillTree_ToggleDebug() - Enable/disable debug messages")
  print("/script skillTree_DebugHelp() - Show this help")
  print("|cffFFFFFFExample: /script skillTree_DebugConnections(30)|r")
  print("|cff00FF00=== END DEBUG HELP ===|r")
end


skillTree_Debug = {
  DebugPrint = DebugPrint,
  IsEnabled = function() return DEBUG_ENABLED end,
  SetEnabled = function(enabled) DEBUG_ENABLED = enabled end
}