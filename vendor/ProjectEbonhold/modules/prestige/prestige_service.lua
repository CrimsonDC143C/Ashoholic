-- ============================================================================
-- Prestige service: client state + server communication.
--
-- Protocol (IDs documented in projectebonhold.lua):
--   CS.REQUEST_PRESTIGE_DATA (1200)  body: ""
--   CS.REQUEST_DO_PRESTIGE   (1201)  body: ""
--   SS.SEND_PRESTIGE_DATA    (1200)  body: "<totalPrestiges>;<committedSoulAshes>;<prestigeBonusPct>"
--   SS.SEND_PRESTIGE_RESULT  (1201)  body: "OK,<totalPrestiges>" or "FAIL,<reason>"
--
-- Prestiging is a FULL character reset (the Accept Death flow: back to level
-- 1, ALL echoes cleared - permanent/locked ones included - gear stored, new
-- run) plus a skill tree wipe in which permanent and INFINITE nodes survive
-- (their ranks grandfathered as free), and the
-- committed Soul Ashes pool is consumed entirely (back to zero). The gate:
-- the committed pool must reach Constants.PRESTIGE_GATE_SOUL_ASHES. The
-- client-side gate mirrors that rule for UI purposes only, using the
-- server-sent committed value; the server re-verifies on REQUEST_DO_PRESTIGE.
--
-- Mount previews: the client can only render a mount model if the creature
-- is in its local creature cache (creaturecache.wdb). The server seeds the
-- cache for ALL mount/companion creatures at login (see
-- project_ebonhold_creature_cache_scripts.cpp in the server repo and the
-- "Mount model previews" section of modules\collections\PROTOCOL.md); the
-- UI additionally retries the model load for ~1s as a safety net.
-- ============================================================================

local addonName, addon = ...

local PrestigeService = {}
ProjectEbonhold.PrestigeService = PrestigeService

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local totalPrestiges = 0
-- Soul Ashes committed since the last prestige, as reported by the server
-- (nil until the first SEND_PRESTIGE_DATA arrives)
local gateProgress = nil
-- Soul Ash bonus already earned through prestiging, as a fraction (0.5 = +50%).
-- Comes from the server: it can no longer be derived from the prestige count,
-- since each prestige grants a bonus proportional to the pool it destroyed.
local prestigeBonusPct = 0

------------------------------------------------------------
-- ACCESSORS
------------------------------------------------------------

function PrestigeService.GetTotalPrestiges()
  return totalPrestiges
end

--- Current prestige rank (highest milestone reached, 0..14)
function PrestigeService.GetRank()
  return ProjectEbonhold.PrestigeData.GetRank(totalPrestiges)
end

--- Committed Soul Ashes required before prestiging is allowed: a fixed
--- threshold (constants.lua), independent from the skill tree's own
--- SoulAshesMilestones progression.
function PrestigeService.GetGateThreshold()
  return ProjectEbonhold.Constants.PRESTIGE_GATE_SOUL_ASHES or 0
end

--- Committed skill tree Soul Ashes as last reported by the server
--- (exposed by skillTree.lua when loadout data arrives)
function PrestigeService.GetCommittedSoulAshes()
  return ProjectEbonhold.totalCommittedSoulAshes or 0
end

--- The value the gate compares against the threshold: the committed Soul
--- Ashes pool as sent by the server in SEND_PRESTIGE_DATA; falls back to the
--- skill tree's committed total until the first data packet arrives.
function PrestigeService.GetGateProgress()
  return gateProgress or PrestigeService.GetCommittedSoulAshes()
end

--- Soul Ash bonus already earned through prestiging, as a fraction.
function PrestigeService.GetPrestigeBonusPct()
  return prestigeBonusPct or 0
end

--- What a prestige RIGHT NOW would destroy, and what it would grant for it:
--- returns destroyedSoulAshes, bonusPct (0, 0 when the gate is not reached).
--- The committed pool is destroyed in full and the bonus scales with it, so
--- waiting longer burns more and buys more.
function PrestigeService.GetPendingPrestigeGain()
  local destroyed = PrestigeService.GetGateProgress() or 0
  if destroyed < PrestigeService.GetGateThreshold() then return 0, 0 end

  local gain = ProjectEbonhold.PrestigeData.ComputeBonusPct(destroyed)

  -- The server clamps the TOTAL prestige bonus to PRESTIGE_BONUS_MAX_TOTAL when it computes
  -- rewards, so an account near the ceiling receives less than the raw formula grants - and
  -- at the ceiling, nothing. Show what will actually apply rather than what the row says.
  local cap = ProjectEbonhold.Constants.PRESTIGE_SOUL_ASH_BONUS_MAX_TOTAL or 0
  if cap > 0 then
    local room = cap - (prestigeBonusPct or 0)
    if room < 0 then room = 0 end
    if gain > room then gain = room end
  end

  return destroyed, gain
end

--- True once the server has reported the committed pool for this UI session. Callers that
--- gate something on the pool must fail closed while this is false: a /reload is not a login,
--- so the local value is 0 until the first SEND_PRESTIGE_DATA lands, and 0 is also a
--- perfectly legitimate pool - the two cannot be told apart from the value alone.
--- Used by the Hardcore panel, whose tier locks read the same pool.
function PrestigeService.IsGateProgressKnown()
  return gateProgress ~= nil
end

function PrestigeService.CanPrestige()
  return PrestigeService.GetGateProgress() >= PrestigeService.GetGateThreshold()
end
------------------------------------------------------------
------------------------------------------------------------
-- CLIENT -> SERVER


function PrestigeService.RequestPrestigeData()
  ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PRESTIGE_DATA, "")
end

function PrestigeService.DoPrestige()
  ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_DO_PRESTIGE, "")
end

------------------------------------------------------------
-- SERVER -> CLIENT
------------------------------------------------------------

local function NotifyUI()
  if ProjectEbonhold.PrestigeUI and ProjectEbonhold.PrestigeUI.Refresh then
    ProjectEbonhold.PrestigeUI.Refresh()
  end
  -- The committed pool this packet carries is also what gates the Hardcore tiers, so the
  -- Hardcore panel has to be told when it lands (it fails closed until then).
  if ProjectEbonhold.HardmodeUI and ProjectEbonhold.HardmodeUI.Refresh then
    ProjectEbonhold.HardmodeUI.Refresh()
  end
end

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PRESTIGE_DATA,
  function(body)
    if not body or body == "" then return end
    local totalStr, progressStr, bonusStr = body:match("^(%d+);(%d+);([%d%.%-]+)$")
    if not totalStr then
      -- Two-field body, from before the bonus was reported
      totalStr, progressStr = body:match("^(%d+);(%d+)$")
    end
    if totalStr then
      totalPrestiges = tonumber(totalStr) or 0
      gateProgress = tonumber(progressStr)
      prestigeBonusPct = tonumber(bonusStr) or prestigeBonusPct
    else
      -- Old single-value body form, kept for compatibility
      totalPrestiges = tonumber(body) or 0
    end
    NotifyUI()
  end
)

-- Failure codes sent by the server (see PrestigeHandler::HandleDoPrestige)
local FAIL_REASONS = {
  gate   = "You have not reached the final Soul Ashes milestone.",
  combat = "You cannot prestige while in combat.",
  dead   = "You cannot prestige while dead.",
}

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PRESTIGE_RESULT,
  function(body)
    if not body or body == "" then return end

    local status, payload = body:match("^(%a+),(.*)$")
    if status == "OK" then
      totalPrestiges = tonumber(payload) or totalPrestiges
      DEFAULT_CHAT_FRAME:AddMessage(
        "|cff00FF00[Prestige] Prestige complete! Total prestiges: " ..
        totalPrestiges .. ".|r")
    else
      DEFAULT_CHAT_FRAME:AddMessage(
        "|cffFF0000[Prestige] Prestige failed: " ..
        (FAIL_REASONS[payload] or tostring(payload)) .. "|r")
    end

    NotifyUI()
  end
)

------------------------------------------------------------
-- AUTO-REQUEST ON LOGIN
------------------------------------------------------------

-- ONCE, and then the listener goes away. PLAYER_ENTERING_WORLD does not mean
-- "logged in": it fires again on every zone change, instance entry, hearth and
-- teleport. This used to re-ask on every single one of them, and each answer
-- ran a full UI refresh (14 bubbles plus a 3D reward model) in the middle of a
-- loading screen. The client hitching every so often on a zone change was this.
--
-- Nothing goes stale by asking once: the count only moves when the player
-- prestiges, and the server pushes SEND_PRESTIGE_DATA when it does. The tab's
-- OnShow and the locked-button click both re-ask on demand as well.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loginFrame:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  self:SetScript("OnEvent", nil)
  PrestigeService.RequestPrestigeData()
end)
