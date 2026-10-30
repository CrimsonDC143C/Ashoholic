local addon, Addon = ...


Addon.LastReachedMilestone = 0



local function parseLoadoutData(dataString)
  if not dataString or dataString == "" then
    return nil
  end


  local globalPart, loadoutsPart = dataString:match("([^_]+)_?(.*)")

  if not globalPart then
    return nil
  end


  local selectedLoadoutId, spendableSoulPoints, totalCommitedSoulPoints, maximumPermanentEchoes = globalPart:match(
    "(%d+),(%d+),(%d+),(%d+)")
  selectedLoadoutId = tonumber(selectedLoadoutId)
  spendableSoulPoints = tonumber(spendableSoulPoints)
  totalCommitedSoulPoints = tonumber(totalCommitedSoulPoints)
  maximumPermanentEchoes = tonumber(maximumPermanentEchoes)

  if not spendableSoulPoints then
    return nil
  end

  local result = {
    selectedLoadoutId = selectedLoadoutId,
    spendableSoulPoints = spendableSoulPoints,
    totalCommitedSoulPoints = totalCommitedSoulPoints or 0,
    maximumPermanentEchoes = maximumPermanentEchoes,
    loadouts = {}
  }
  if loadoutsPart and loadoutsPart ~= "" then
    for loadoutString in string.gmatch(loadoutsPart, "([^;]+)") do
      local parts = {}
      for part in string.gmatch(loadoutString, "([^,]+)") do
        table.insert(parts, part)
      end

      if #parts >= 3 then
        local loadoutId = tonumber(parts[1])
        local name = parts[2]
        local spendablePoints = tonumber(parts[3])

        local loadout = {
          id = loadoutId,
          name = name,
          spendablePoints = spendablePoints,
          nodeRanks = {},
          totalNodes = 0,
          totalRanks = 0
        }


        for i = 4, #parts do
          local nodeId, rank = parts[i]:match("(%d+):(%d+)")
          if nodeId and rank then
            nodeId = tonumber(nodeId)
            rank = tonumber(rank)
            loadout.nodeRanks[nodeId] = rank
            loadout.totalNodes = loadout.totalNodes + 1
            loadout.totalRanks = loadout.totalRanks + rank
          end
        end

        table.insert(result.loadouts, loadout)
      end
    end
  end
  return result
end



local function encodeLoadoutData(loadoutData)
  if not loadoutData or not loadoutData.nodeRanks then
    return nil
  end

  local nodeParts = {}

  for nodeId, rank in pairs(loadoutData.nodeRanks) do
    if rank > 0 then
      table.insert(nodeParts, nodeId .. ":" .. rank)
    end
  end

  local loadoutId = loadoutData.id or "0"
  local name = loadoutData.name or "Unnamed"
  local nodesString = table.concat(nodeParts, ",")

  local encoded = loadoutId .. "|" .. name .. "|" .. nodesString
  return encoded
end


function Addon.SendLoadoutToServer(loadoutData)
  local encoded = encodeLoadoutData(loadoutData)
  if not encoded then
    return false
  end
  ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_LOADOUT_UPDATE, encoded)
  return true
end

function Addon.RequestLoadoutFromServer()
  ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_LOADOUTS, "")
  return true
end

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_LOADOUTS, function(body)
  local parsedData = parseLoadoutData(body)
  if parsedData and Addon.ApplyLoadoutsFromServer then
    Addon.ApplyLoadoutsFromServer(parsedData)
  end
end)

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_UPDATED_LOADOUT, function(body)

end)

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_CREATED_LOADOUT, function(body)
end)


ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_SKILL_TREE_UPDATE_SPELL_CAST_RESULT,
  function(body, dist, sender, id)
    local result = body:match("^([01])$")
    if not result then
      if ProjectEbonhold and ProjectEbonhold.SkillTree and ProjectEbonhold.SkillTree.OnApplyChangesResult then
        ProjectEbonhold.SkillTree.OnApplyChangesResult(nil, false)
      else
      end
      return
    end
    local success = tonumber(result) == 1

    if ProjectEbonhold and ProjectEbonhold.SkillTree and ProjectEbonhold.SkillTree.OnApplyChangesResult then
      ProjectEbonhold.SkillTree.OnApplyChangesResult(nil, success)
    else
    end
  end)


ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_UPDATED_COMMITTED_SOUL_POINTS, function(body)
  -- Parse les deux valeurs: totalSpendable,totalCommitted
  local spendable, committed = body:match("(%d+),(%d+)")
  local totalSpendable = tonumber(spendable)
  local totalCommitted = tonumber(committed)

  if not totalSpendable or not totalCommitted then
    return
  end

  if ProjectEbonhold and ProjectEbonhold.SkillTree and ProjectEbonhold.SkillTree.UpdateTotalSoulPoints then
    ProjectEbonhold.SkillTree.UpdateTotalSoulPoints(totalSpendable, totalCommitted)
  else
  end


  if SkillTreeMicroButton_StartFlashing then
    SkillTreeMicroButton_StartFlashing()
  end
  if SkillTreeMicroButton_ShowAlert then
    SkillTreeMicroButton_ShowAlert()
  end
end)


ProjectEbonhold.SendLoadoutToServer = Addon.SendLoadoutToServer
ProjectEbonhold.RequestLoadoutFromServer = Addon.RequestLoadoutFromServer
