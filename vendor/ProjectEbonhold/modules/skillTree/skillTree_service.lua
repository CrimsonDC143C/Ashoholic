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


  -- Header: selectedId,ashSpendable,ashBanked,permanentEchoes[,shardSpendable,shardBanked,
  -- essenceSpendable,essenceBanked,artisanSpendable,artisanBanked]. The six trailing numbers
  -- are the other currencies (2026-09); an older server simply omits them.
  local nums = {}
  for n in globalPart:gmatch("(%d+)") do table.insert(nums, tonumber(n)) end
  local selectedLoadoutId, spendableSoulPoints, totalCommitedSoulPoints, maximumPermanentEchoes =
    nums[1], nums[2], nums[3], nums[4]

  if not spendableSoulPoints then
    return nil
  end

  local pools = nil
  if nums[10] then
    pools = {
      shard   = { spendable = nums[5], banked = nums[6] },
      essence = { spendable = nums[7], banked = nums[8] },
      artisan = { spendable = nums[9], banked = nums[10] },
    }
  end

  local result = {
    selectedLoadoutId = selectedLoadoutId,
    spendableSoulPoints = spendableSoulPoints,
    totalCommitedSoulPoints = totalCommitedSoulPoints or 0,
    maximumPermanentEchoes = maximumPermanentEchoes,
    pools = pools,
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
  -- "ashSpendable,ashBanked" or, since 2026-09, the four pools as spendable,banked pairs
  -- in currency order (ash, shards, essence, artisan) - eight numbers.
  local nums = {}
  for n in body:gmatch("(%d+)") do table.insert(nums, tonumber(n)) end
  local totalSpendable = nums[1]
  local totalCommitted = nums[2]

  if not totalSpendable or not totalCommitted then
    return
  end

  local pools = nil
  if nums[8] then
    pools = {
      shard   = { spendable = nums[3], banked = nums[4] },
      essence = { spendable = nums[5], banked = nums[6] },
      artisan = { spendable = nums[7], banked = nums[8] },
    }
  end

  -- Texte flottant sur un gain : on compare le BANQUE (ce qui a ete gagne) et pas le
  -- depensable, qui baisse aussi quand on achete un noeud. Rien au premier paquet, sinon
  -- toute la banque defilerait a la connexion.
  if pools then
    local prev = ProjectEbonhold.lastBankedPools
    if prev and ProjectEbonhold.PlayerRunService and ProjectEbonhold.PlayerRunService.ShowChangeAnimation
       and not (ProjectEbonholdOptionsService and not ProjectEbonholdOptionsService:GetSetting("showFloatingText")) then
      local n = 0
      for _, cur in ipairs({ { "shard", "Soul Shard(s)" }, { "essence", "Soul Essence" }, { "artisan", "Artisan Soul" } }) do
        local key, label = cur[1], cur[2]
        local gained = (pools[key].banked or 0) - (prev[key] or 0)
        if gained > 0 then
          ProjectEbonhold.PlayerRunService.ShowChangeAnimation(
            "|cff00FF00+" .. ProjectEbonhold.FormatThousands(gained) .. "|r " .. label, true, 50 + n * 40)
          n = n + 1
        end
      end
    end
    ProjectEbonhold.lastBankedPools = {
      shard = pools.shard.banked, essence = pools.essence.banked, artisan = pools.artisan.banked,
    }
  end

  if ProjectEbonhold and ProjectEbonhold.SkillTree and ProjectEbonhold.SkillTree.UpdateTotalSoulPoints then
    ProjectEbonhold.SkillTree.UpdateTotalSoulPoints(totalSpendable, totalCommitted, pools)
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
