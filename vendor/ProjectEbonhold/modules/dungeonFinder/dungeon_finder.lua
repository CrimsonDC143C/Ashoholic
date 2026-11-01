-- ==============================================================================
-- Dungeon Finder rework (server: LFGQueue / LFGMgr, dungeon_finder_scripts.cpp).
--
-- What changed against the stock finder, and what this file does about it:
--   * Roles do not matter. The role buttons are hidden and every join is sent as damage.
--   * A run starts with 2 players (server: Ashendor.Lfg.MinGroupSize). Each newcomer restarts a
--     soak timer; the eye tooltip shows "N/5 players, invitation in Xs" instead of role slots.
--   * Every queue is a random queue: the "Type" dropdown and the specific list are gone, the
--     server queues the random wrapper of the player's level bracket.
--   * The player picks the Torment of the run, at any level, with the Torment frame's own
--     widget (name + arrows, segmented ladder, creature modifiers of the dungeon) drawn where
--     the role buttons were. Locked tiers can be looked at (padlock, unlock achievement) but
--     not picked; the server re-checks every pick.
--   * The reward is one Orb of Lost Memories per difficulty tier, every run, and ten per tier
--     for the first run of the day - no daily quest. The first run of the day also pays one
--     reward cache at level 80, of the realm's release and of the tier played. The stock
--     random-dungeon text is hidden and a REWARDS band of the panel shows the three lines.
--   * No refill: the "continue with a replacement" panel is hidden.
--   * One "Fill empty spots" box under the Torment ladder, unticked by default. Unticked = Solo
--     on the server: no matching, the invitation comes at once and the run starts with the party
--     as it is (alone, duo, trio...). Ticked = Group: the matcher above fills the run up to 5.
--     Same rewards, same dungeons. In a party the leader's choice counts. (LfgQueueMode.)
--
-- Wire:
--   CS.REQUEST_LFG_TORMENT_DATA (1250) ""       -> SS.SEND_LFG_TORMENT_DATA (1250)
--        "<selected>|<maxQueueable>|<maxTier>|<minGroupSize>|<firstRunDone>|<release>|<mode>"
--   CS.REQUEST_LFG_TORMENT_SET  (1251) "<tier>" -> SS.SEND_LFG_TORMENT_RESULT (1251) "OK,<tier>" / "FAIL,<reason>"
--   CS.REQUEST_LFG_MODE_SET     (1253) "<mode>" -> SS.SEND_LFG_TORMENT_DATA (1250); a refusal comes as RESULT "FAIL,<reason>"
--   SS.SEND_LFG_QUEUE_STATE (1252) "<players>|<secondsLeft>|<min>|<max>|<proposed>|<tier>|<mode>" every queue tick
-- ==============================================================================
local DF = {}
ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.DungeonFinder = DF

local CS = ProjectEbonhold.CS
local SS = ProjectEbonhold.SS

local MAX_LEVEL = 80
-- The lowest random wrapper (LFGDungeons.dbc 258, Random Classic Dungeon) opens at 15. Below
-- that the server sends no wrapper at all and refuses the join (LFGMgr::PickRandomWrapper).
local FINDER_MIN_LEVEL = 15
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
  "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX",
  "XXI", "XXII", "XXIII", "XXIV", "XXV", "XXVI", "XXVII", "XXVIII", "XXIX", "XXX" }

local state = {
  known = false,          -- SEND_LFG_TORMENT_DATA received this UI session
  selected = 1,           -- tier the server holds for the next run (1 = Normal)
  maxQueueable = 1,       -- highest tier the server lets this character queue at
  maxTier = 11,           -- highest tier the finder queues (Torment X)
  firstRunDone = false,   -- the first (10x) run of the day was already claimed today
  release = 5,            -- the realm's phase (patch + 1, clamped 1..5): picks the cache family
  minGroupSize = 2,
  mode = 1,               -- queue mode for the next run: 0 = Group (fill empty spots), 1 = Solo (as is, the server's default)
  queue = { players = 0, secondsLeft = -1, min = 2, max = 5, proposed = false, tier = 1, mode = 1, receivedAt = 0, valid = false },
}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function TierName(tier)
  tier = tonumber(tier) or 1
  if tier <= 1 then return "Normal" end
  return "Torment " .. (ROMAN[tier - 1] or tostring(tier - 1))
end
DF.TierName = TierName

-- Queue modes (LfgQueueMode): 0 Group = "Fill empty spots" ticked, 1 Solo = unticked.
local MODE_GROUP = 0
local MODE_SOLO = 1

local function InParty()
  return (GetNumPartyMembers() or 0) > 0 or (GetNumRaidMembers() or 0) > 0
end

-- Short name for the status lines: "Solo" alone, "Your party" in a party, "Open group" when filling.
local function ModeName(mode)
  if (tonumber(mode) or MODE_SOLO) == MODE_GROUP then return "Open group" end
  return InParty() and "Your party" or "Solo"
end
DF.ModeName = ModeName

local function AtCap()
  return UnitLevel("player") >= MAX_LEVEL
end

local function Plural(n, word)
  return string.format("%d %s%s", n, word, n > 1 and "s" or "")
end

--- The tier the next run will be at.
local function RunTier()
  return state.selected
end

-- Orbs of Lost Memories per finished run, by tier (1 = Normal .. 11 = Torment X). Static on
-- purpose: display data only. The server pays round(3 x 1.3 ^ Torment) - compounding, see
-- OrbsHandler::DungeonOrbsFor - and ten times that for the first run of the day; retune the
-- two together.
local ORBS_PER_RUN   = { 3, 4, 5, 7, 9, 11, 14, 19, 24, 32, 41 }
local ORBS_FIRST_RUN = { 30, 40, 50, 70, 90, 110, 140, 190, 240, 320, 410 }

local function OrbsFor(tier)
  return ORBS_PER_RUN[tonumber(tier) or 1] or ORBS_PER_RUN[#ORBS_PER_RUN]
end

local function FirstRunOrbsFor(tier)
  return ORBS_FIRST_RUN[tonumber(tier) or 1] or ORBS_FIRST_RUN[#ORBS_FIRST_RUN]
end

-- The reward cache of the first run of the day (level 80 only). Everything below mirrors the
-- server and is display data: CallboardMgr::GetRewardCacheItem for the entry,
-- CACHE_RELEASE_ILVL + CACHE_BRACKET_ILVL for the item level, HardmodeMgr::GetTormentBracket
-- for the tier -> bracket step. Retune the two together.
local CACHE_MIN_LEVEL   = 80
local CACHE_RELEASE_ILVL = { 213, 239, 239, 252, 265 }
local CACHE_BRACKET_ILVL = { 0, 7, 13, 20, 26 }
local CACHE_PHASE_NAME   = { "Adventurer's", "Champion's", "Conqueror's", "Vanquisher's", "Ascendant's" }
local CACHE_BRACKET_NAME = { "", " of Suffering", " of Torment", " of Anguish", " of Damnation" }
local CACHE_ICON = {
  { "INV_Misc_Bag_10", "INV_Misc_Bag_10_Green", "INV_Misc_Bag_10_Blue", "INV_Misc_Bag_10_Red", "INV_Misc_Bag_10_Black" },
  { "INV_Misc_Bag_09", "INV_Misc_Bag_09_Green", "INV_Misc_Bag_09_Blue", "INV_Misc_Bag_09_Red", "INV_Misc_Bag_09_Black" },
  { "INV_Misc_Bag_07", "INV_Misc_Bag_07_Green", "INV_Misc_Bag_07_Blue", "INV_Misc_Bag_07_Red", "INV_Misc_Bag_07_Black" },
  { "INV_Crate_02", "INV_Crate_01", "INV_Crate_03", "INV_Crate_04", "INV_Crate_05" },
  { "INV_Box_01", "INV_Box_02", "INV_Box_03", "INV_Crate_06", "INV_Misc_OrnateBox" },
}

--- Torment bracket of a finder tier (1 = Normal): 0, then 1-3, 4-7, 8-9, 10 and up.
local function BracketFor(tier)
  tier = tonumber(tier) or 1
  if tier <= 1 then return 0 end
  local torment = tier - 1
  if torment <= 3 then return 1 end
  if torment <= 7 then return 2 end
  if torment <= 9 then return 3 end
  return 4
end

--- Name, icon, item level and short name of the cache a run at `tier` pays, on the realm's
--- phase. The short name is what the reward line shows: the full one does not fit next to
--- the note, and the tooltip carries it anyway.
local function CacheFor(tier)
  local phase = math.max(1, math.min(#CACHE_PHASE_NAME, state.release or 5))
  local b = BracketFor(tier)
  return CACHE_PHASE_NAME[phase] .. " Cache" .. CACHE_BRACKET_NAME[b + 1],
         "Interface\\Icons\\" .. CACHE_ICON[phase][b + 1],
         CACHE_RELEASE_ILVL[phase] + CACHE_BRACKET_ILVL[b + 1],
         CACHE_PHASE_NAME[phase] .. " Cache"
end

local function IsQueueBusy()
  local mode = GetLFGMode()
  return mode == "queued" or mode == "proposal" or mode == "rolecheck" or mode == "listed"
end

local function Send(id, body)
  if ProjectEbonhold.sendToServer then
    ProjectEbonhold.sendToServer(id, body or "")
  end
end

------------------------------------------------------------
-- Roles: hidden, always damage
------------------------------------------------------------

local ROLE_BUTTONS = { "LFDQueueFrameRoleButtonTank", "LFDQueueFrameRoleButtonHealer", "LFDQueueFrameRoleButtonDPS", "LFDQueueFrameRoleButtonLeader" }

local function HideRoleButtons()
  for _, name in ipairs(ROLE_BUTTONS) do
    local btn = _G[name]
    if btn then
      btn:Hide()
      -- Anything that re-shows the buttons (a /reload, another addon) is undone on the spot.
      if not btn.ebonholdRoleHooked then
        btn.ebonholdRoleHooked = true
        btn:HookScript("OnShow", function(self) self:Hide() end)
      end
    end
  end
end

local function ForceDamageRole()
  -- The leader flag is meaningless now that the server picks a leader itself.
  if SetLFGRoles then SetLFGRoles(false, false, false, true) end
end

------------------------------------------------------------
-- Torment panel (where the role buttons were)
------------------------------------------------------------
-- The stock random-dungeon panel, in our words: the tier
-- selector shared with the Torment frame (modules/torment/tier_selector.lua: tier name on
-- the dialog banner between the spellbook page arrows, a ladder N / I..X of panel buttons;
-- the finder stops at Torment X), the creature modifiers of the tier as character-sheet
-- rows - here the DUNGEON figures, since that is what the run meets - and the orbs as
-- random-dungeon reward rows. The tier data is the table hardmode.lua exports
-- (ProjectEbonhold.TormentTierData).
local LADDER_TOP = ProjectEbonhold.TormentLadderTop or 11   -- tier 11 = Torment X
local ICON_LOCK  = "Interface\\AddOns\\ProjectEbonhold\\assets\\lock"

local PANEL_X, PANEL_Y, PANEL_W = 32, -66, 300   -- PANEL_Y: the stepper, 20 px below the title bar area
local ICON_ORB   = "Interface\\Icons\\inv_112_arcane_orb"   -- the Orb of Lost Memories icon (modules/perks/orb_of_lost_memories.lua)
local ORB_TOOLTIP = "An Orb of Lost Memories lets you forget one stack of an Echo you own and draw a fresh choice in its place. Spend them from the Echo Journal."

local panel            -- the widget under LFDQueueFrame
local viewTier = 1     -- tier being looked at (may be locked); the server selection is state.selected

local function TierData(tier)
  local data = ProjectEbonhold.TormentTierData
  return data and (data[tier] or data[1]) or nil
end

local function MaxTier()
  local data = ProjectEbonhold.TormentTierData
  return math.min(state.maxTier, LADDER_TOP, data and #data or LADDER_TOP)
end

--- White for Normal, then a ramp to deep red: the same language as the Torment frame.
local function TierColor(tier)
  if tier <= 1 then return 1, 1, 1 end
  local progress = (tier - 1) / (MaxTier() - 1)
  return 1.0, 1.0 - progress * 0.8, 1.0 - progress * 0.8
end

local function IsLocked(tier)
  return tier > state.maxQueueable
end

--- 0 = player, 1 = GM account with .gm off, 2 = .gm on (HardmodeService, server-pushed).
local function GmState()
  local svc = ProjectEbonhold.HardmodeService
  return svc and svc.GetGmState and svc.GetGmState() or 0
end

--- A tier the server opens only because of .gm on: the player's own conditions are not met,
--- so it keeps its padlock and its reason on display, but it can be selected.
local function IsGmPassOnly(tier)
  if tier <= 1 or IsLocked(tier) or GmState() ~= 2 then return false end
  local svc = ProjectEbonhold.HardmodeService
  return svc ~= nil and svc.IsAchievementEarned ~= nil and not svc.IsAchievementEarned(tier)
end


local function Pct(multiplier)
  local pct = math.floor(((multiplier or 1) - 1) * 100 + 0.5)
  if pct >= 0 then return "+" .. pct .. "%" end
  return pct .. "%"
end

local function X(mult)
  return "x" .. string.format("%.1f", mult or 1)
end

local function LockReason(tier)
  local svc = ProjectEbonhold.HardmodeService
  if tier <= 1 then return nil end
  if svc and svc.GetAchievementName then
    local link = (svc.GetAchievementLink and svc.GetAchievementLink(tier)) or ""
    local name = svc.GetAchievementName(tier)
    if link ~= "" then return "Requires " .. link end
    if name ~= "" then return "Requires the achievement |cffFFD100" .. name .. "|r" end
  end
  return "Locked"
end

--- Ask the server for @p tier when it is open; a locked tier is only looked at.
local function Select(tier)
  tier = math.max(1, math.min(MaxTier(), tier))
  viewTier = tier
  if not IsLocked(tier) and tier ~= state.selected then
    if IsQueueBusy() then
      UIErrorsFrame:AddMessage("Leave the queue before changing the difficulty.", 1.0, 0.1, 0.1, 1.0)
      viewTier = state.selected
    else
      Send(CS.REQUEST_LFG_TORMENT_SET, tostring(tier))
    end
  end
  DF.RefreshSelector()
end

--- Ask the server for @p mode (0 Group, 1 Solo). It answers with the full finder state.
function DF.SelectMode(mode)
  if mode == state.mode then return end
  if IsQueueBusy() then
    UIErrorsFrame:AddMessage("Leave the queue before changing Fill empty spots.", 1.0, 0.1, 0.1, 1.0)
    return
  end
  Send(CS.REQUEST_LFG_MODE_SET, tostring(mode))
end

--- Find Group stays off while a locked tier is on display: the run would queue at another
--- tier than the one shown. Same below FINDER_MIN_LEVEL, where nothing can be queued for.
--- Leave Queue (queue busy) is never touched.
local function UpdateFindGroupLock()
  local btn = LFDQueueFrameFindGroupButton
  if not btn then return end
  local tooLow = UnitLevel("player") < FINDER_MIN_LEVEL
  if (IsLocked(viewTier) or tooLow) and not IsQueueBusy() then
    btn:Disable()
    btn.ebonholdLocked = true
  elseif btn.ebonholdLocked then
    btn.ebonholdLocked = false
    -- Give the stock code its say again; its hook comes back here with nothing left to do.
    LFDQueueFrameFindGroupButton_Update()
  end
end

local function CreateTormentSelector()
  if panel or not LFDQueueFrame then return end
  local W  = ProjectEbonhold.TormentWidgets
  local TS = ProjectEbonhold.TierSelector
  panel = CreateFrame("Frame", "ProjectEbonholdLFDTormentPanel", LFDQueueFrame)
  -- Two blocks: the stepper (arrows + tier name) hangs from the top, right under the title
  -- bar; the ladder and the sections hang from the bottom, just above Find Group / Close.
  -- Whatever the frame height, the slack opens between the two.
  panel:SetPoint("TOPLEFT", LFDQueueFrame, "TOPLEFT", PANEL_X, PANEL_Y)
  panel:SetSize(PANEL_W, TS.STEPPER_HEIGHT)

  local body = CreateFrame("Frame", nil, panel)
  body:SetWidth(PANEL_W)
  if LFDQueueFrameFindGroupButton then
    -- Over the button (its art starts lower than its frame), by 1 px plus the height of the
    -- champion line that left Creature Modifiers: the ladder and the sections keep their place.
    body:SetPoint("BOTTOMLEFT", LFDQueueFrameFindGroupButton, "TOPLEFT", PANEL_X - 18, 1 + W.STAT_H)   -- the button sits at x 18
  else
    body:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -12)
  end
  panel.body = body
  local y = 0

  -- Selector: banner + page arrows on the panel, ladder moved down into the body
  panel.selector = TS.Create(panel, {
    width      = PANEL_W,
    rungs      = LADDER_TOP,
    cosmetic   = false,
    GetMax     = MaxTier,
    GetName    = function(tier)
      local name = TierName(tier)
      if IsLocked(tier) or IsGmPassOnly(tier) then name = name .. " |T" .. ICON_LOCK .. ":16:16:0:-1|t" end
      return name
    end,
    GetColor   = TierColor,
    IsLocked   = IsLocked,
    GetCurrent = function() return state.selected end,
    CanStep    = function() return state.known and not IsQueueBusy() end,
    ShiftMax   = function() return state.maxQueueable end,
    OnSelect   = Select,
    OnRungEnter = function(btn, tier)
      GameTooltip:SetOwner(btn, "ANCHOR_TOP")
      GameTooltip:SetText(TierName(tier), TierColor(tier))
      if tier == state.selected then
        GameTooltip:AddLine("Your next run is at this difficulty", 0.1, 1, 0.1)
      elseif IsLocked(tier) then
        GameTooltip:AddLine(LockReason(tier) or "Locked", 1, 0.3, 0.3, true)
        if GmState() == 1 then
          GameTooltip:AddLine("GM: type .gm on to step in", 0.25, 0.78, 0.92, true)
        end
      elseif IsGmPassOnly(tier) then
        GameTooltip:AddLine(LockReason(tier) or "Locked", 1, 0.3, 0.3, true)
        GameTooltip:AddLine("GM (.gm on): you may step in", 0.25, 0.78, 0.92, true)
      end
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine("Reward per run", Plural(OrbsFor(tier), "Orb") .. " of Lost Memories", 1, 0.82, 0, 1, 1, 1)
      GameTooltip:AddDoubleLine("First run of the day", Plural(FirstRunOrbsFor(tier), "Orb"), 1, 0.82, 0, 1, 1, 1)
      GameTooltip:Show()
    end,
  })
  panel.selector:SetPoint("TOP", panel, "TOP", 0, 0)
  panel.selector.ladder:ClearAllPoints()
  panel.selector.ladder:SetPoint("TOP", body, "TOP", 0, y + 20)   -- 20 px above the body, more air before the sections
  y = y - TS.RUNG_HEIGHT - 14

  -- "Fill empty spots": one box in the air between the ladder and the sections, so the frame
  -- keeps its size. Unticked (the default) = the run starts with the party as it is (Solo);
  -- ticked = other players fill the run up to 5 (Group). The client's own check button.
  local fill = CreateFrame("CheckButton", "ProjectEbonholdLFDFillCheck", body, "UICheckButtonTemplate")
  fill:SetSize(24, 24)
  -- On the left edge of the section titles, between the ladder (ends at -2) and the first header.
  fill:SetPoint("LEFT", body, "TOPLEFT", 0, -23)
  fill.label = _G[fill:GetName() .. "Text"]
  fill.label:SetFontObject("GameFontNormal")
  fill.label:SetText("Fill empty spots")
  fill:SetHitRectInsets(0, -fill.label:GetStringWidth() - 4, 0, 0)   -- the label is clickable too
  fill:SetScript("OnClick", function(self)
    local wanted = self:GetChecked() and MODE_GROUP or MODE_SOLO
    -- The box shows the server's value; it changes when the answer comes back.
    self:SetChecked(state.mode == MODE_GROUP)
    DF.SelectMode(wanted)
  end)
  fill:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Fill empty spots", 1, 0.82, 0)
    GameTooltip:AddLine("Unticked: you go in as you are, alone or with your own party only. The invitation comes at once.", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Ticked: other players join you until the run has 5 players. It starts with 2 to 5.", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Same rewards and dungeons either way. In a party, the leader's choice counts.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  fill:SetScript("OnLeave", GameTooltip_Hide)
  panel.mode = fill
  y = y - 5   -- the sections sit 5 px lower, clear of the box

  -- Section: creature modifiers in the dungeon
  local modHeader = W.CreateSectionHeader(body, PANEL_W, "Creature Modifiers", "in the dungeon")
  modHeader:SetPoint("TOP", body, "TOP", 0, y)
  y = y - W.HEADER_H
  panel.rows = {}
  -- Health, melee, spell. The body grows upward from Find Group.
  for i = 1, 3 do
    local row = W.CreateStatRow(body, PANEL_W, i)
    row:SetPoint("TOP", body, "TOP", 0, y)
    y = y - W.STAT_H
    panel.rows[i] = row
  end
  y = y - 3

  -- Section: rewards of the run (Orbs of Lost Memories)
  local rewardHeader = W.CreateSectionHeader(body, PANEL_W, "Rewards")
  rewardHeader:SetPoint("TOP", body, "TOP", 0, y)
  y = y - W.HEADER_H
  -- The three rewards sit side by side: two orb figures and the cache of the day. The band
  -- keeps the height the two stacked rows used to take, so nothing else on the panel moves.
  -- Two full-width lines, the shape the band always had: the orb of every run, then the
  -- reward of the first run of the day - the cache, which brings the orb bonus with it.
  panel.rewardRows = {}
  for i = 1, 2 do
    local row = W.CreateItemRow(body, PANEL_W)
    if i > 1 then y = y - 1 end   -- 1 px between the two rows, none under the last
    row:SetPoint("TOP", body, "TOP", 0, y)
    y = y - W.ITEM_H
    panel.rewardRows[i] = row
  end

  panel.rewardRows[1].tooltip = function()
    GameTooltip:SetText("Orbs of Lost Memories", 1, 0.82, 0)
    GameTooltip:AddLine(ORB_TOOLTIP, 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Every run", Plural(OrbsFor(viewTier), "Orb"), 1, 0.82, 0, 1, 1, 1)
  end
  -- The cache line reads the tier shown on the panel, not the one the run was queued at.
  panel.rewardRows[2].tooltip = function()
    local name, _, ilvl = CacheFor(viewTier)
    GameTooltip:SetText(name, 1, 0.82, 0)
    GameTooltip:AddLine("One piece of equipment for your class, item level " .. ilvl .. ".", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    -- The bonus is always spelled out, whatever the state: greyed when it cannot be had, and
    -- the requirement stated underneath in the game's own words.
    local tooLow = UnitLevel("player") < CACHE_MIN_LEVEL
    if state.firstRunDone then
      GameTooltip:AddDoubleLine("First run of the day", "claimed", 1, 0.82, 0, 0.6, 0.6, 0.6)
    else
      local bonus = Plural(FirstRunOrbsFor(viewTier), "Orb") .. " + the cache"
      if tooLow then
        GameTooltip:AddDoubleLine("First run of the day", bonus, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Requires Level " .. CACHE_MIN_LEVEL, 1, 0.1, 0.1)
      else
        GameTooltip:AddDoubleLine("First run of the day", bonus, 1, 0.82, 0, 0.1, 1, 0.1)
      end
    end
  end

  body:SetHeight(-y)

  -- The stock random-dungeon text ("Using the Dungeon Finder to do a Random Dungeon...") has
  -- nothing left to say: the panel carries the rewards. Keep it hidden.
  if LFDQueueFrameRandomScrollFrame then
    LFDQueueFrameRandomScrollFrame:Hide()
    if not LFDQueueFrameRandomScrollFrame.ebonholdHooked then
      LFDQueueFrameRandomScrollFrame.ebonholdHooked = true
      LFDQueueFrameRandomScrollFrame:HookScript("OnShow", function(self) self:Hide() end)
    end
  end
end

function DF.RefreshSelector()
  if not panel then return end
  panel:Show()
  local tier = viewTier
  local td = TierData(tier)

  -- Name, arrows, ladder: the widget reads the state through its callbacks
  panel.selector:SetValue(tier)
  UpdateFindGroupLock()

  -- Mode: the server's value; frozen while queued (the entry was built with it)
  panel.mode:SetChecked(state.mode == MODE_GROUP)
  if IsQueueBusy() or not state.known then
    panel.mode:Disable()
    panel.mode.label:SetTextColor(0.5, 0.5, 0.5)
  else
    panel.mode:Enable()
    panel.mode.label:SetTextColor(1, 0.82, 0)
  end

  -- Creature modifiers, dungeon context (boss on the row, adds in the tooltip)
  local s = td and td.scaling or {}
  local isNormal = tier <= 1
  local specs = {
    { "Interface\\Icons\\PetBattle_Health", s.dungeon_boss_hp_mul or s.hp_multiplier, "Health",
      { { "Dungeon boss", X(s.dungeon_boss_hp_mul or s.hp_multiplier) }, { "Dungeon adds", X(s.dungeon_add_hp_mul or s.hp_multiplier) } } },
    { "Interface\\Icons\\Ability_MeleeDamage", s.dungeon_boss_melee_mul or s.melee_multiplier, "Melee damage",
      { { "Dungeon boss", X(s.dungeon_boss_melee_mul or s.melee_multiplier) }, { "Dungeon adds", X(s.dungeon_add_melee_mul or s.melee_multiplier) } } },
    { "Interface\\Icons\\Spell_Ice_MagicDamage", s.dungeon_boss_spell_mul or s.spell_multiplier, "Spell damage",
      { { "Dungeon boss", X(s.dungeon_boss_spell_mul or s.spell_multiplier) }, { "Dungeon adds", X(s.dungeon_add_spell_mul or s.spell_multiplier) } } },
  }
  for i, spec in ipairs(specs) do
    local row = panel.rows[i]
    row:Set(spec[1], spec[3], Pct(spec[2]))
    row:SetActive(not isNormal)
    -- The label stays white whatever the tier: only the icon and the figure carry the state.
    row.label:SetTextColor(1, 1, 1)
    row.tooltip = function()
      GameTooltip:SetText(spec[3], 1, 0.82, 0)
      for _, r in ipairs(spec[4]) do
        GameTooltip:AddDoubleLine(r[1], r[2], 0.9, 0.9, 0.9, 0.1, 1, 0.1)
      end
    end
  end

  -- Rewards of the viewed tier
  local orbs, cache = panel.rewardRows[1], panel.rewardRows[2]
  orbs:Set(ICON_ORB, OrbsFor(tier), "Orb of Lost Memories", "per run")

  -- The reward of the first run of the day, on one line: the cache, and the orb bonus that
  -- comes with it. Greyed once taken, and below the level cap where it is out of reach.
  local _, cacheIcon, _, cacheShort = CacheFor(tier)
  local tooLow = UnitLevel("player") < CACHE_MIN_LEVEL
  local note
  if tooLow then
    -- Out of reach: the padlock alone, same art as a locked tier. The tooltip says why.
    note = "|T" .. ICON_LOCK .. ":22:22:0:-3|t"
  elseif state.firstRunDone then
    note = "daily: claimed"
  else
    note = "+" .. FirstRunOrbsFor(tier) .. " orbs · daily"
  end
  cache:Set(cacheIcon, nil, cacheShort, note)
  cache:SetClaimed(tooLow or state.firstRunDone)
  cache.name:SetTextColor(1, 1, 1)   -- the name never greys out, only the icon and the note do
  -- Green while the bonus is there, grey once it is not.
  if tooLow or state.firstRunDone then
    cache.note:SetTextColor(0.5, 0.5, 0.5)
  else
    cache.note:SetTextColor(0.35, 1, 0.35)
  end
end
local RefreshSelector = DF.RefreshSelector

------------------------------------------------------------
-- Always random: no type dropdown, no specific list
------------------------------------------------------------

local function IsJoinable(id)
  return type(id) == "number" and (not IsLFGDungeonJoinable or IsLFGDungeonJoinable(id))
end

--- A random wrapper the client lets SetLFGDungeon take. Which one hardly matters: the server
--- swaps it for the wrapper of the player's level anyway. Nil when the client holds none,
--- which is what makes the stock join fail with "You did not select any valid slots".
local function JoinableRandom()
  local best = GetRandomDungeonBestChoice and GetRandomDungeonBestChoice()
  if IsJoinable(best) then return best end
  for i = 1, (GetNumRandomDungeons and GetNumRandomDungeons() or 0) do
    local id = GetLFGRandomDungeonInfo(i)
    if IsJoinable(id) then return id end
  end
  return nil
end

--- Why no random wrapper is open, in the game's own words when it has them.
local function NoRandomReason()
  if UnitLevel("player") < FINDER_MIN_LEVEL then
    return "The Dungeon Finder opens at level " .. FINDER_MIN_LEVEL .. "."
  end
  local id = GetRandomDungeonBestChoice and GetRandomDungeonBestChoice()
  if not id and GetNumRandomDungeons and GetNumRandomDungeons() > 0 then
    id = GetLFGRandomDungeonInfo(1)
  end
  local reason = id and LFDConstructDeclinedMessage and LFDConstructDeclinedMessage(id)
  return reason or "No dungeon is open to you right now. Try again in a moment."
end

--- The random panel stays shown here even when the stock frame picked "specific", and the stock
--- LFG_UPDATE_RANDOM_INFO handler then feeds "specific" to GetLFGDungeonInfo (a Lua error).
--- Nil is the stock "no info yet" value: the panel skips it and the next random info picks a wrapper.
local function DropSpecificType()
  if LFDQueueFrame and LFDQueueFrame.type == "specific" then
    LFDQueueFrame.type = nil
  end
end

local function ForceRandomType()
  if not LFDQueueFrame then return end
  local best = JoinableRandom()
  if best and LFDQueueFrame.type ~= best then
    LFDQueueFrame.type = best
    UIDropDownMenu_SetSelectedValue(LFDQueueFrameTypeDropDown, best)
  end
  DropSpecificType()
  if LFDQueueFrame.type then
    LFDQueueFrame_SetTypeRandomDungeon()
    LFDQueueFrameRandom_UpdateFrame()
  end
end

local function HideTypeRow()
  if LFDQueueFrameTypeDropDown then
    LFDQueueFrameTypeDropDown:Hide()
    if not LFDQueueFrameTypeDropDown.ebonholdHooked then
      LFDQueueFrameTypeDropDown.ebonholdHooked = true
      LFDQueueFrameTypeDropDown:HookScript("OnShow", function(self) self:Hide() end)
    end
  end
  if LFDQueueFrameTypeDropDownName then LFDQueueFrameTypeDropDownName:Hide() end
end

-- On the first open of a session the client has no random info yet: the stock frame falls back
-- to the specific list (LFDQueueFrame_SetTypeSpecificDungeon), which then sits under the Torment
-- panel, and ForceRandomType has no wrapper to pull it back with. The list is never wanted here.
local function HideSpecificList()
  local list = LFDQueueFrameSpecific
  if not list then return end
  list:Hide()
  DropSpecificType()
  if LFDQueueFrameRandom then LFDQueueFrameRandom:Show() end
  if not list.ebonholdHooked then
    list.ebonholdHooked = true
    list:HookScript("OnShow", function(self)
      self:Hide()
      DropSpecificType()
      if LFDQueueFrameRandom then LFDQueueFrameRandom:Show() end
    end)
  end
end

------------------------------------------------------------
-- Eye tooltip: players instead of roles
------------------------------------------------------------

local SLOTS = { "LFDSearchStatusTank1", "LFDSearchStatusHealer1", "LFDSearchStatusDamage1", "LFDSearchStatusDamage2", "LFDSearchStatusDamage3" }

local function QueueSecondsLeft()
  local q = state.queue
  if not q.valid or q.secondsLeft < 0 then return -1 end
  return math.max(0, q.secondsLeft - (GetTime() - q.receivedAt))
end

local function SearchStatusText()
  local q = state.queue
  if not q.valid then
    return "Looking for players..."
  end
  local head = string.format("%d/%d players", q.players, q.max)
  if q.proposed then
    return head .. " - invitation sent"
  end
  if q.mode == MODE_SOLO then
    return (InParty() and "Your party only" or "Solo run") .. " - invitation on its way"
  end
  if q.players < q.min then
    local missing = q.min - q.players
    return head .. string.format(" - waiting for %d more", missing)
  end
  local left = QueueSecondsLeft()
  if left <= 0 then
    return head .. " - invitation on its way"
  end
  return head .. string.format(" - invitation in %ds unless someone joins", math.ceil(left))
end

local function RefreshSearchStatus()
  if not LFDSearchStatus or not LFDSearchStatus:IsShown() then return end
  local q = state.queue
  for i, name in ipairs(SLOTS) do
    local slot = _G[name]
    if slot and slot.texture then
      slot.texture:SetTexCoord(GetTexCoordsForRole("DAMAGER"))
      local found = q.valid and i <= q.players
      SetDesaturation(slot.texture, not found)
      if found then slot.cover:Hide() else slot.cover:Show() end
    end
  end
  for i = 1, (LFD_NUM_ROLES or 3) do
    local icon = _G["LFDSearchStatusRoleIcon" .. i]
    if icon then icon:Hide() end
  end
  if LFDSearchStatusLookingFor then
    LFDSearchStatusLookingFor:SetText(SearchStatusText())
    LFDSearchStatusLookingFor:SetPoint("BOTTOM", 0, 14)
  end
  if LFDSearchStatus.statistic and q.valid and q.tier then
    LFDSearchStatus.statistic:SetText(TierName(q.tier) .. " · " .. ModeName(q.mode))
    LFDSearchStatus.statistic:Show()
    LFDSearchStatus:SetHeight(170)
  end
end

-- The countdown moves every second while the tooltip is up; the server only ticks every 15 s.
local ticker = CreateFrame("Frame")
ticker.elapsed = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
  self.elapsed = self.elapsed + elapsed
  if self.elapsed < 1 then return end
  self.elapsed = 0
  RefreshSearchStatus()
end)

------------------------------------------------------------
-- Ready dialog: the run's difficulty instead of "your role"
------------------------------------------------------------

local function RefreshReadyDialog()
  -- Ready check: the client always lays out five member slots; with a two-player run the
  -- last three are empty. Hide them and centre the ones that are filled.
  if LFDDungeonReadyStatus and LFDDungeonReadyStatus:IsShown() then
    local shown = {}
    for i = 1, (NUM_LFD_MEMBERS or 5) do
      local slot = _G["LFDDungeonReadyStatusPlayer" .. i]
      local _, _, _, _, _, name = GetLFGProposalMember(i)
      if slot then
        if name then
          shown[#shown + 1] = slot
        else
          slot:Hide()
        end
      end
    end
    local slotW = 55
    local x = 15 + ((NUM_LFD_MEMBERS or 5) - #shown) * slotW / 2
    for i, slot in ipairs(shown) do
      slot:ClearAllPoints()
      if i == 1 then
        slot:SetPoint("LEFT", LFDDungeonReadyStatus, "LEFT", x, -10)
      else
        slot:SetPoint("LEFT", shown[i - 1], "RIGHT", 0, 0)
      end
      slot:Show()
    end
  end

  if not LFDDungeonReadyDialog or not LFDDungeonReadyDialog:IsShown() then return end
  local desc = LFDDungeonReadyDialogYourRoleDescription
  local label = LFDDungeonReadyDialogRoleLabel
  if desc then desc:SetText("Difficulty:") end
  if label then
    local tier = state.queue.valid and state.queue.tier or state.selected
    local mode = state.queue.valid and state.queue.mode or state.mode
    label:SetText(TierName(tier) .. " · " .. ModeName(mode))
  end
end

------------------------------------------------------------
-- Server -> client
------------------------------------------------------------

if ProjectEbonhold.onEventReceived and SS then
  ProjectEbonhold.onEventReceived(SS.SEND_LFG_TORMENT_DATA, function(body)
    if not body or body == "" then return end
    local selected, maxQueueable, maxTier, minSize, firstDone, release, mode = strsplit("|", body)
    state.selected = tonumber(selected) or 1
    state.maxQueueable = tonumber(maxQueueable) or 1
    state.maxTier = tonumber(maxTier) or state.maxTier
    state.minGroupSize = tonumber(minSize) or 2
    state.firstRunDone = firstDone == "1"
    state.release = tonumber(release) or state.release
    state.mode = tonumber(mode) or MODE_SOLO
    state.known = true
    viewTier = state.selected
    RefreshSelector()
  end)

  ProjectEbonhold.onEventReceived(SS.SEND_LFG_TORMENT_RESULT, function(body)
    if not body or body == "" then return end
    local status, payload = body:match("^(%a+),(.*)$")
    -- Our own REQUEST_LFG_TORMENT_SET (same opcode number) is echoed back by the self-whisper:
    -- its body is a bare tier, not a status.
    if not status then return end
    if status == "OK" then
      state.selected = tonumber(payload) or state.selected
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffFF0000[Dungeon Finder]|r " .. tostring(payload))
    end
    viewTier = state.selected
    RefreshSelector()
  end)

  ProjectEbonhold.onEventReceived(SS.SEND_LFG_QUEUE_STATE, function(body)
    if not body or body == "" then return end
    local players, secondsLeft, minSize, maxSize, proposed, tier, mode = strsplit("|", body)
    local q = state.queue
    q.players = tonumber(players) or 0
    q.secondsLeft = tonumber(secondsLeft) or -1
    q.min = tonumber(minSize) or q.min
    q.max = tonumber(maxSize) or q.max
    q.proposed = proposed == "1"
    q.tier = tonumber(tier) or 1
    q.mode = tonumber(mode) or MODE_SOLO
    q.receivedAt = GetTime()
    q.valid = true
    RefreshSearchStatus()
  end)
end

------------------------------------------------------------
-- Hooks into the stock frame
------------------------------------------------------------

local function Install()
  if not LFDQueueFrame or DF.installed then return end
  DF.installed = true

  HideRoleButtons()
  HideTypeRow()
  HideSpecificList()
  CreateTormentSelector()

  -- No role check on Ashendor, so the client can hold no role for a party member and the
  -- ready popup throws "Unknown role: UNKNOWN" on accept. Everyone is damage: draw that.
  local origRoleCoords = GetTexCoordsForRole
  GetTexCoordsForRole = function(role)
    if role ~= "GUIDE" and role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
      role = "DAMAGER"
    end
    return origRoleCoords(role)
  end

  -- GetRandomDungeonBestChoice() answers 0 when no random wrapper is open to the character, and
  -- the stock LFG_UPDATE_RANDOM_INFO handler hands that 0 to the random panel, which errors on
  -- GetLFGDungeonInfo(0) ("attempt to compare number with nil", LFDFrame.lua:815). Skip the draw
  -- until a real wrapper is picked; the next random info or ForceRandomType draws it.
  local origRandomUpdate = LFDQueueFrameRandom_UpdateFrame
  LFDQueueFrameRandom_UpdateFrame = function(...)
    local t = LFDQueueFrame.type
    if type(t) ~= "number" or not GetLFGDungeonInfo(t) then return end
    return origRandomUpdate(...)
  end

  -- Roles are set right before the join packet leaves, whatever the checkboxes held, and the
  -- pick is always the random wrapper (the server enforces the same).
  local origJoin = LFDQueueFrame_Join
  LFDQueueFrame_Join = function(...)
    if IsLocked(viewTier) then
      UIErrorsFrame:AddMessage("This difficulty is locked.", 1.0, 0.1, 0.1, 1.0)
      return
    end
    ForceDamageRole()
    ForceRandomType()
    -- Nothing joinable on the client: the stock join would go out empty and the game would
    -- only say "You did not select any valid slots". Say why instead, and ask for fresh locks.
    if not IsJoinable(LFDQueueFrame.type) then
      UIErrorsFrame:AddMessage(NoRandomReason(), 1.0, 0.1, 0.1, 1.0)
      if RequestLFDPlayerLockInfo then RequestLFDPlayerLockInfo() end
      return
    end
    return origJoin(...)
  end
  -- The stock frame falls back to "specific" when it has no random info yet; pull it back.
  hooksecurefunc("LFDQueueFrame_SetType", function(value)
    if value == "specific" then ForceRandomType() end
  end)

  hooksecurefunc("LFDSearchStatus_Update", RefreshSearchStatus)
  hooksecurefunc("LFDDungeonReadyPopup_Update", RefreshReadyDialog)
  hooksecurefunc("LFDQueueFrameFindGroupButton_Update", RefreshSelector)
  -- No refill on Ashendor: the "continue with a replacement" panel never applies.
  hooksecurefunc("LFDFrame_UpdateBackfill", function()
    if LFDQueueFramePartyBackfill then LFDQueueFramePartyBackfill:Hide() end
  end)
  if LFDQueueFramePartyBackfill then LFDQueueFramePartyBackfill:Hide() end

  if LFDQueueFrame:IsShown() then ForceRandomType() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("LFG_UPDATE")
frame:RegisterEvent("LFG_PROPOSAL_SHOW")
frame:RegisterEvent("LFG_PROPOSAL_FAILED")
frame:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
frame:RegisterEvent("LFG_LOCK_INFO_RECEIVED")
frame:RegisterEvent("LFG_UPDATE_RANDOM_INFO")
frame:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_ENTERING_WORLD" then
    Install()
    ForceDamageRole()
    state.queue.valid = false
    Send(CS.REQUEST_LFG_TORMENT_DATA, "")
  elseif event == "PLAYER_LEVEL_UP" or event == "LFG_UPDATE_RANDOM_INFO" then
    -- The random info may land while the window is open: take the wrapper as soon as it exists.
    if LFDQueueFrame and LFDQueueFrame:IsShown() then ForceRandomType() end
  elseif event == "LFG_UPDATE" then
    if not IsQueueBusy() then state.queue.valid = false end
  end
  RefreshSelector()
end)

-- The reward line and the selector depend on what the server said: ask again whenever the
-- window opens, a /reload leaves both at their placeholders otherwise.
if LFDParentFrame then
  LFDParentFrame:HookScript("OnShow", function()
    Install()
    ForceRandomType()
    Send(CS.REQUEST_LFG_TORMENT_DATA, "")
    RefreshSelector()
  end)
end
