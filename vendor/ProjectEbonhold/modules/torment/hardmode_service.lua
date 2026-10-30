local addonName, addon = ...

------------------------------------------------------------

local HardmodeService = {}
ProjectEbonhold.HardmodeService = HardmodeService

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local currentDifficulty = 1   -- 1 = Normal, 2-5 = Hardmode tiers

-- The tier above is only a placeholder. A /reload is not a login, so nothing pushes the real
-- tier back on its own and this stays Normal until the server answers RequestHardmodeData.
-- Consumers that gate Hardcore restrictions must fail closed while this is false.
local difficultyKnown = false

ProjectEbonhold.currentHardmodeTier = currentDifficulty

------------------------------------------------------------
-- REWARDS TABLE
------------------------------------------------------------

-- Indexed by difficulty tier (1 = Normal, 2-5 = Hardmode tiers)
local HARDMODE_REWARDS = {
  -- [difficulty] = { context_type, gold_multiplier, extra_loot_chance, extra_loot_count, quest_xp_multiplier, creature_xp_multiplier, soul_ash_multiplier, reagent_multiplier }
  [1] = { context_type = 0, gold_multiplier = 1,    extra_loot_chance = 0,  extra_loot_count = 0, quest_xp_multiplier = 1,    creature_xp_multiplier = 1,    soul_ash_multiplier = 1,    reagent_multiplier = 1    },
  [2] = { context_type = 0, gold_multiplier = 1.25, extra_loot_chance = 5,  extra_loot_count = 1, quest_xp_multiplier = 1.25, creature_xp_multiplier = 1.15, soul_ash_multiplier = 1.25, reagent_multiplier = 1.25 },
  [3] = { context_type = 0, gold_multiplier = 1.5,  extra_loot_chance = 10, extra_loot_count = 2, quest_xp_multiplier = 1.5,  creature_xp_multiplier = 1.3,  soul_ash_multiplier = 1.5,  reagent_multiplier = 1.5  },
  [4] = { context_type = 0, gold_multiplier = 2,    extra_loot_chance = 15, extra_loot_count = 3, quest_xp_multiplier = 2,    creature_xp_multiplier = 1.75, soul_ash_multiplier = 2,    reagent_multiplier = 1.75 },
  [5] = { context_type = 0, gold_multiplier = 2.5,  extra_loot_chance = 20, extra_loot_count = 4, quest_xp_multiplier = 2.5,  creature_xp_multiplier = 2,    soul_ash_multiplier = 2.5,  reagent_multiplier = 2    },
  [6] = { context_type = 0, gold_multiplier = 3,    extra_loot_chance = 25, extra_loot_count = 4, quest_xp_multiplier = 3,    creature_xp_multiplier = 2.5,  soul_ash_multiplier = 3,    reagent_multiplier = 3    },
}
HardmodeService.HARDMODE_REWARDS = HARDMODE_REWARDS

------------------------------------------------------------
-- ACCESSORS
------------------------------------------------------------

function HardmodeService.GetCurrentDifficulty()
  return currentDifficulty
end

function HardmodeService.IsHardmodeActive()
  return currentDifficulty > 1
end

--- True once the server has confirmed the tier for this UI session (false right after a /reload)
function HardmodeService.IsDifficultyKnown()
  return difficultyKnown
end

--- The account's committed Soul Ashes: the pool the Hardcore gate is compared against, and
--- the exact value the server compares (SoulPointsHandler::GetCommittedSoulPoints).
--- Read from the prestige service, which already receives it in SEND_PRESTIGE_DATA - pushed
--- unprompted on login - and falls back to the skill tree's committed total. No dedicated
--- packet is needed for the gate.
function HardmodeService.GetCommittedSoulAshes()
  local prestige = ProjectEbonhold.PrestigeService
  if prestige and prestige.GetGateProgress then
    return prestige.GetGateProgress() or 0
  end
  return ProjectEbonhold.totalCommittedSoulAshes or 0
end

--- True once the committed Soul Ash pool is known for this UI session. The gate thresholds
--- themselves are hardcoded and therefore always known; the POOL is not, and a /reload leaves
--- it at 0 - which is indistinguishable from a genuinely empty pool. Callers fail closed.
function HardmodeService.IsCommittedSoulAshesKnown()
  local prestige = ProjectEbonhold.PrestigeService
  if prestige and prestige.IsGateProgressKnown then
    return prestige.IsGateProgressKnown()
  end
  return ProjectEbonhold.totalCommittedSoulAshes ~= nil
end

--- Committed Soul Ashes required to run the given difficulty tier (0 = no requirement).
--- Hardcoded client-side (constants.lua); the server enforces its own copy of the same
--- thresholds, so this is display data only.
function HardmodeService.GetSoulAshRequirement(tier)
  return ProjectEbonhold.GetHardcoreSoulAshGate and ProjectEbonhold.GetHardcoreSoulAshGate(tier) or 0
end

--- Achievement required to run the given difficulty tier (0 = no requirement).
--- "Ahead of the Curve" I-V; hardcoded client-side (constants.lua) like the Soul Ash gate.
function HardmodeService.GetAchievementRequirement(tier)
  return ProjectEbonhold.GetHardcoreAchievementGate and ProjectEbonhold.GetHardcoreAchievementGate(tier) or 0
end

--- True when this CHARACTER has earned the achievement gating the given tier.
--- Unlike the Soul Ash pool, achievement state needs no server push: the client already holds
--- it, so there is no "not known yet" case to fail closed on.
function HardmodeService.IsAchievementEarned(tier)
  local required = HardmodeService.GetAchievementRequirement(tier)
  if required <= 0 then return true end

  local _, _, _, completed = GetAchievementInfo(required)
  return completed and true or false
end

--- Name of the achievement gating the given tier, for the lock text ("" when none / unknown).
function HardmodeService.GetAchievementName(tier)
  local required = HardmodeService.GetAchievementRequirement(tier)
  if required <= 0 then return "" end

  local _, name = GetAchievementInfo(required)
  return name or ""
end

--- Clickable achievement link for the tier's gate ("" when none, or when the client does not
--- know the achievement yet - which is what a client running without the patched
--- Achievement.dbc looks like). Preferred over the bare name everywhere it is shown: it renders
--- with the achievement colouring and can be shift-clicked like any other link.
function HardmodeService.GetAchievementLink(tier)
  local required = HardmodeService.GetAchievementRequirement(tier)
  if required <= 0 then return "" end

  return GetAchievementLink and GetAchievementLink(required) or ""
end

--- True when this character may run the given tier. The "Ahead of the Curve" achievement for
--- that tier always applies; the committed Soul Ash floor only where one is still configured,
--- and since 2026-08-14 no tier has one (HARDCORE_SOUL_ASH_GATES is empty), so in practice the
--- achievement alone unlocks a tier.
--- The server is the authority on the Soul Ash half (HardmodeMgr::MeetsSoulAshGate, config
--- Ashendor.Hardmode.SoulAshGates); this mirrors it so the UI can explain the lock. Exactly ON
--- the threshold counts as unlocked, like the server.
function HardmodeService.IsTierUnlocked(tier)
  if not HardmodeService.IsAchievementEarned(tier) then return false end

  local required = HardmodeService.GetSoulAshRequirement(tier)
  if required <= 0 then return true end
  return HardmodeService.GetCommittedSoulAshes() >= required
end

--- Soul Ashes still missing before the given tier unlocks (0 when already unlocked).
function HardmodeService.GetSoulAshesMissingFor(tier)
  local required = HardmodeService.GetSoulAshRequirement(tier)
  local committed = HardmodeService.GetCommittedSoulAshes()
  if required <= 0 or committed >= required then return 0 end
  return required - committed
end

--- Returns the reward multipliers for the given difficulty tier (defaults to current)
function HardmodeService.GetRewardsForDifficulty(tier)
  tier = tier or currentDifficulty
  return HARDMODE_REWARDS[tier] or HARDMODE_REWARDS[1]
end

------------------------------------------------------------
-- CLIENT → SERVER
------------------------------------------------------------

--- Ask the server what tier the player is on
function HardmodeService.RequestHardmodeData()
  ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_HARDMODE_DATA, "")
end

--- Tell the server to change difficulty (1 = Normal). The Soul Ash gate is re-checked
--- server-side on every switch path, so sending a locked tier simply comes back as a FAIL.
function HardmodeService.SetDifficulty(tier)
  tier = math.max(1, math.min(tier, 6))
  ProjectEbonhold.sendToServer(
    ProjectEbonhold.CS.REQUEST_HARDMODE_SET_DIFFICULTY,
    tostring(tier)
  )
end

------------------------------------------------------------
-- SERVER → CLIENT
------------------------------------------------------------

--- Server sends back the current tier (just a number)
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_HARDMODE_DATA,
  function(body)
    if not body or body == "" then return end
    currentDifficulty = tonumber(body) or 1
    ProjectEbonhold.currentHardmodeTier = currentDifficulty
    difficultyKnown = true

    -- Notify UI
    if ProjectEbonhold.HardmodeUI and ProjectEbonhold.HardmodeUI.Refresh then
      ProjectEbonhold.HardmodeUI.Refresh()
    end
    -- Refresh intensity icons (6th icon depends on hardmode)
    if ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateIntensity then
      local intensityData = _G["EbonholdIntensityData"] or { intensity = 0 }
      ProjectEbonhold.PlayerRunUI.UpdateIntensity(intensityData)
    end
    -- The death frame hides every resurrection option in Hardcore, and it is drawn before this
    -- reply lands on a /reload, so it has to be rebuilt once the tier is known.
    if ProjectEbonhold.DeathFrame and ProjectEbonhold.DeathFrame.Refresh then
      ProjectEbonhold.DeathFrame.Refresh()
    end
  end
)

--- Result of a set-difficulty request: "OK,<tier>" or "FAIL,<reason>"
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_HARDMODE_SET_RESULT,
  function(body)
    if not body or body == "" then return end

    local status, payload = body:match("^(%a+),(.+)$")
    if status == "OK" then
      local newTier = tonumber(payload) or 1
      currentDifficulty = newTier
      ProjectEbonhold.currentHardmodeTier = newTier
      difficultyKnown = true

      if newTier == 1 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00FF00[Hardmode] Returned to Normal difficulty.|r")
      else
        DEFAULT_CHAT_FRAME:AddMessage(
          "|cff00FF00[Hardmode] Difficulty set to Tier " .. newTier .. ".|r"
        )
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage(
        "|cffFF0000[Hardmode] Failed to change difficulty: " .. tostring(payload) .. "|r"
      )
    end

    -- Notify UI
    if ProjectEbonhold.HardmodeUI and ProjectEbonhold.HardmodeUI.Refresh then
      ProjectEbonhold.HardmodeUI.Refresh()
    end
    -- Refresh intensity icons (6th icon depends on hardmode)
    if ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateIntensity then
      local intensityData = _G["EbonholdIntensityData"] or { intensity = 0 }
      ProjectEbonhold.PlayerRunUI.UpdateIntensity(intensityData)
    end
    -- The death frame hides every resurrection option in Hardcore, and it is drawn before this
    -- reply lands on a /reload, so it has to be rebuilt once the tier is known.
    if ProjectEbonhold.DeathFrame and ProjectEbonhold.DeathFrame.Refresh then
      ProjectEbonhold.DeathFrame.Refresh()
    end
  end
)

--- A Hardcore rank was just unlocked by crossing its committed Soul Ash gate. No tier has such
--- a gate anymore, so this now only fires on a realm that put one back from config; tiers
--- unlock with their achievement, which the client already sees on its own.
--- Body: comma-separated ranks, ascending ("1", or "3,4" when one commit crossed several).
--- The server only ever sends this AT the crossing, so there is nothing to de-duplicate here:
--- a relogin or any later Soul Ash update never re-enters that path.
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_HARDCORE_TIER_UNLOCKED,
  function(body)
    if not body or body == "" then return end

    local ranks = {}
    for rank in string.gmatch(body, "%d+") do
      table.insert(ranks, tonumber(rank))
    end
    if #ranks == 0 then return end

    if ProjectEbonhold.HardmodeUI and ProjectEbonhold.HardmodeUI.ShowTierUnlocked then
      ProjectEbonhold.HardmodeUI.ShowTierUnlocked(ranks)
    end
  end
)

------------------------------------------------------------
-- AUTO-REQUEST ON LOGIN
------------------------------------------------------------

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loginFrame:SetScript("OnEvent", function(self, event)
  HardmodeService.RequestHardmodeData()
end)
