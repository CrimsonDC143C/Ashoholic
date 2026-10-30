local addon, Addon         = ...

------------------------------------------------------------
-- HARDCORE DIFFICULTY PANEL  (UI)
--
-- All tier data is hardcoded client-side.
-- Server only stores / returns the current tier number.
-- Slider goes 1 (Normal) → 5 (max Hardcore).
------------------------------------------------------------

-- Colours
local COLOR_GOLD           = { 1.00, 0.82, 0.00 }
local COLOR_GREEN          = { 0.10, 1.00, 0.10 }
local COLOR_RED            = { 1.00, 0.20, 0.20 }
local COLOR_BLUE           = { 0.20, 0.50, 1.00 }
local COLOR_GREY           = { 0.50, 0.50, 0.50 }
local COLOR_WHITE          = { 1.00, 1.00, 1.00 }
local COLOR_ORANGE         = { 1.00, 0.55, 0.00 }

local SECTION_INSET        = 15
local SECTION_WIDTH        = 350
local PANEL_WIDTH          = 400
local PANEL_MIN_H          = 460

-- Reward icons (standard WoW texture paths)
local ICON_GOLD            = "Interface\\Icons\\INV_Misc_Coin_01"
local ICON_QUEST_XP        = "Interface\\Icons\\INV_Misc_Book_07"
local ICON_KILL_XP         = "Interface\\Icons\\Ability_DualWield"
local ICON_SOUL_ASH        = "Interface\\AddOns\\ProjectEbonhold\\assets\\inv_soulash"
local ICON_REAGENT         = "Interface\\Icons\\INV_Misc_Herb_07"
local ICON_LOOT            = "Interface\\Icons\\INV_Misc_Bag_10"

------------------------------------------------------------
-- HARDCODED TIER DATA  (1 = Normal, 2-5 = Hardcore)
------------------------------------------------------------

local TIER_DATA            = {
  [1] = {
    name       = "Normal",
    scaling    = {
      hp_multiplier    = 1.0,
      melee_multiplier = 1.0,
      spell_multiplier = 1.0,
    },
    -- Sample auras that creatures can gain (spellIds)
    auras      = {},
    rewards    = {
      gold_multiplier        = 1.0,
      quest_xp_multiplier    = 1.0,
      creature_xp_multiplier = 1.0,
      soul_ash_multiplier    = 1.0,
      reagent_multiplier     = 1.0,
    },
    debuffs    = {},
    bonusAuras = {},
    extraLoot  = {},
  },

  [2] = {
    name       = "Hardcore I",
    scaling    = {
      hp_multiplier          = 2.7,
      melee_multiplier       = 3.5,
      spell_multiplier       = 3.5,
      aura_max               = 1,
      dungeon_boss_hp_mul    = 3.5,
      dungeon_boss_melee_mul = 2.75,
      dungeon_boss_spell_mul = 3.1,
      raid_boss_hp_mul       = 4.25,
      raid_boss_melee_mul    = 2.75,
      raid_boss_spell_mul    = 3.5,
      dungeon_add_hp_mul     = 3.5,
      dungeon_add_melee_mul  = 3.5,
      dungeon_add_spell_mul  = 2.7,
      raid_add_hp_mul        = 3.5,
      raid_add_melee_mul     = 2.75,
      raid_add_spell_mul     = 3.5,
    },
    auras      = {
      { spellId = 900905 }, -- Tier 1 Creature Empowerment
      { spellId = 900914 }, -- Tier 2 Creature Empowerment
      { spellId = 900913 }, -- Tier 2 Creature Empowerment
    },
    rewards    = {
      gold_multiplier        = 1.25,
      quest_xp_multiplier    = 1.25,
      creature_xp_multiplier = 1.15,
      soul_ash_multiplier    = 1.25,
      reagent_multiplier     = 1.25,
      affix_chance_tier      = 1,
      extra_loot_count       = 1,
    },
    debuffs    = {
      { spellId = 900900 }, -- Tier 2 Debuff Players
    },
    bonusAuras = {
      { spellId = 900922 }, -- Tier 2 Bonus Aura
    },
    extraLoot  = {
      { bagType = "dungeon" },
    },
  },

  [3] = {
    name       = "Hardcore II",
    scaling    = {
      hp_multiplier          = 4.1,
      melee_multiplier       = 6.25,
      spell_multiplier       = 6.25,
      aura_max               = 3,
      dungeon_boss_hp_mul    = 4.1,
      dungeon_boss_melee_mul = 3.0,
      dungeon_boss_spell_mul = 4.0,
      raid_boss_hp_mul       = 6.25,
      raid_boss_melee_mul    = 3.0,
      raid_boss_spell_mul    = 4.0,
      dungeon_add_hp_mul     = 6.25,
      dungeon_add_melee_mul  = 3.1,
      dungeon_add_spell_mul  = 3.1,
      raid_add_hp_mul        = 4.1,
      raid_add_melee_mul     = 3.0,
      raid_add_spell_mul     = 4.0,
    },
    auras      = {
      { spellId = 900905 }, -- Tier 1 Creature Empowerment
      { spellId = 900906 }, -- Tier 2 Creature Empowerment
      { spellId = 900907 }, -- Tier 3 Possible Aura
      { spellId = 900914 }, -- Tier 2 Creature Empowerment
      { spellId = 900913 }, -- Tier 2 Creature Empowerment
    },
    rewards    = {
      gold_multiplier        = 1.5,
      quest_xp_multiplier    = 1.5,
      creature_xp_multiplier = 1.3,
      soul_ash_multiplier    = 1.5,
      reagent_multiplier     = 1.5,
      affix_chance_tier      = 2,
      extra_loot_count       = 2,
    },
    debuffs    = {
      { spellId = 900900 }, -- Tier 2 Debuff Players
      { spellId = 900908 }, -- Tier 3 Debuff Players
    },
    extraLoot  = {
      { bagType = "dungeon" },
      { bagType = "raid" },
    },
  },

  [4] = {
    name       = "Hardcore III",
    scaling    = {
      hp_multiplier          = 6.7,
      melee_multiplier       = 8.0,
      spell_multiplier       = 8.0,
      aura_max               = 4,
      dungeon_boss_hp_mul    = 8.0,
      dungeon_boss_melee_mul = 3.5,
      dungeon_boss_spell_mul = 4.5,
      raid_boss_hp_mul       = 8.25,
      raid_boss_melee_mul    = 3.5,
      raid_boss_spell_mul    = 4.5,
      dungeon_add_hp_mul     = 8.0,
      dungeon_add_melee_mul  = 8.0,
      dungeon_add_spell_mul  = 6.7,
      raid_add_hp_mul        = 8.0,
      raid_add_melee_mul     = 3.5,
      raid_add_spell_mul     = 4.5,
    },
    auras      = {
      { spellId = 900905 }, -- Tier 1 Creature Empowerment
      { spellId = 900906 }, -- Tier 2 Creature Empowerment
      { spellId = 900907 }, -- Tier 3 Possible Aura
      { spellId = 900904 }, -- Tier 3 Creature Empowerment
      { spellId = 900914 }, -- Tier 2 Creature Empowerment
      { spellId = 900913 }, -- Tier 2 Creature Empowerment
    },
    rewards    = {
      gold_multiplier        = 2.0,
      quest_xp_multiplier    = 2.0,
      creature_xp_multiplier = 1.75,
      soul_ash_multiplier    = 2.0,
      reagent_multiplier     = 1.75,
      affix_chance_tier      = 3,
      extra_loot_count       = 3,
    },
    debuffs    = {
      { spellId = 900900 }, -- Tier 2 Debuff Players
      { spellId = 900908 }, -- Tier 3 Debuff Players
      { spellId = 900901 }, -- Tier 4 Debuff Players
    },
    extraLoot  = {
      { bagType = "dungeon" },
      { bagType = "raid" },
    },
  },

  [5] = {
    name       = "Hardcore IV",
    scaling    = {
      hp_multiplier          = 7.0,
      melee_multiplier       = 8.5,
      spell_multiplier       = 8.5,
      aura_max               = 5,
      dungeon_boss_hp_mul    = 8.5,
      dungeon_boss_melee_mul = 4.0,
      dungeon_boss_spell_mul = 5.0,
      raid_boss_hp_mul       = 8.5,
      raid_boss_melee_mul    = 4.0,
      raid_boss_spell_mul    = 5.0,
      dungeon_add_hp_mul     = 8.25,
      dungeon_add_melee_mul  = 8.25,
      dungeon_add_spell_mul  = 7.5,
      raid_add_hp_mul        = 8.25,
      raid_add_melee_mul     = 4.5,
      raid_add_spell_mul     = 5.0,
    },
    auras      = {
      { spellId = 900905 }, -- Tier 1 Creature Empowerment
      { spellId = 900906 }, -- Tier 2 Creature Empowerment
      { spellId = 900907 }, -- Tier 3 Possible Aura
      { spellId = 900904 }, -- Tier 3 Creature Empowerment
      { spellId = 900914 }, -- Tier 2 Creature Empowerment
      { spellId = 900913 }, -- Tier 2 Creature Empowerment
    },
    rewards    = {
      gold_multiplier        = 2.5,
      quest_xp_multiplier    = 2.5,
      creature_xp_multiplier = 2.0,
      soul_ash_multiplier    = 2.5,
      reagent_multiplier     = 2.0,
      affix_chance_tier      = 4,
      extra_loot_count       = 4,
    },
    debuffs    = {
      { spellId = 900900 }, -- Tier 2 Debuff Players
      { spellId = 900908 }, -- Tier 3 Debuff Players
      { spellId = 900901 }, -- Tier 4 Debuff Players
    },
    extraLoot  = {
      { bagType = "dungeon" },
      { bagType = "raid" },
    },
  },

  [6] = {
    name       = "Hardcore V",
    scaling    = {
      hp_multiplier          = 14.0,
      melee_multiplier       = 16.0,
      spell_multiplier       = 16.0,
      aura_max               = 5,
      dungeon_boss_hp_mul    = 14.0,
      dungeon_boss_melee_mul = 8.0,
      dungeon_boss_spell_mul = 10.0,
      raid_boss_hp_mul       = 16.0,
      raid_boss_melee_mul    = 8.0,
      raid_boss_spell_mul    = 10.0,
      dungeon_add_hp_mul     = 16.0,
      dungeon_add_melee_mul  = 16.0,
      dungeon_add_spell_mul  = 14.0,
      raid_add_hp_mul        = 16.0,
      raid_add_melee_mul     = 8.0,
      raid_add_spell_mul     = 10.0,
    },
    auras      = {
      { spellId = 900905 }, -- Tier 1 Creature Empowerment
      { spellId = 900906 }, -- Tier 2 Creature Empowerment
      { spellId = 900907 }, -- Tier 3 Possible Aura
      { spellId = 900904 }, -- Tier 3 Creature Empowerment
      { spellId = 900914 }, -- Tier 2 Creature Empowerment
      { spellId = 900913 }, -- Tier 2 Creature Empowerment
    },
    rewards    = {
      gold_multiplier        = 3.0,
      quest_xp_multiplier    = 3.0,
      creature_xp_multiplier = 2.5,
      soul_ash_multiplier    = 3.0,
      reagent_multiplier     = 3.0,
      affix_chance_tier      = 5,
      icc_affixes            = true,
      extra_loot_count       = 4,
    },
    debuffs    = {
      { spellId = 900900 }, -- Tier 2 Debuff Players
      { spellId = 900908 }, -- Tier 3 Debuff Players
      { spellId = 900901 }, -- Tier 4 Debuff Players
    },
    extraLoot  = {
      { bagType = "dungeon" },
      { bagType = "raid" },
    },
  },
}

-- State
local hardmodeFrame        = nil
local confirmPopup         = nil
local selectedTier         = 1

local SLIDER_MIN           = 1
local function GetSliderMax()
  return 6
end

-- Expose UI handle for service callbacks
ProjectEbonhold.HardmodeUI = ProjectEbonhold.HardmodeUI or {}

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

local function Fmt(v, decimals)
  decimals = decimals or 1
  return string.format("%." .. decimals .. "f", v)
end
-- Convert a multiplier (e.g. 1.5) to a percentage string (e.g. "+50%")
local function Pct(multiplier)
  local pct = math.floor((multiplier - 1) * 100 + 0.5)
  if pct >= 0 then return "+" .. pct .. "%" end
  return pct .. "%"
end
local function ColorText(text, r, g, b)
  return string.format("|cff%02x%02x%02x%s|r",
    math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), text)
end

-- Padlock shown on locked Hardcore tiers. Inline texture escape so it can sit inside a
-- FontString; the .blp ships with the addon (assets\lock) and is the same one the run HUD
-- already stamps on locked perk icons, so the two read as the same "locked" language.
-- Shown once, on the tier label: the lock-reason line under Apply already spells the
-- requirement out in words, so repeating the padlock there just adds noise.
-- Size and vertical offset are the two numbers to touch: the offset has to grow (more
-- negative) with the size, otherwise the padlock rides above the text baseline.
local LOCK_ICON = "|TInterface\\AddOns\\ProjectEbonhold\\assets\\lock:28:28:0:-8|t"

-- What each tier's "Ahead of the Curve" achievement actually asks for: a raid final boss
-- killed while the world runs at the tier BELOW the one it unlocks. Mirrored from the server's
-- own definition (tools/achievements/ahead_of_the_curve.yaml, enforced by
-- AheadOfTheCurveCriteriaScript) - if that ladder is ever re-cut, this table moves with it.
--
-- Kept here rather than read back from the client's Achievement.dbc description, because a
-- client without the patched DBC has no description to show, and the lock line under the
-- slider is exactly where a player asks "so what do I actually have to do?".
-- Every rung is 25-PLAYER ONLY, enforced server-side by AheadOfTheCurveCriteriaScript
-- (Map::Is25ManRaid). A 10-player kill is silently ignored, so the raid size is spelled out on
-- each line rather than left as a footnote.
local ACHIEVEMENT_HINTS = {
  [2] = { name = "Ahead of the Curve I",   task = "Defeat Kel'Thuzad in Naxxramas (25-player).",                      difficulty = "Normal",
          note = "Normal only: a kill on a Hardcore tier does not count for this one." },
  [3] = { name = "Ahead of the Curve II",  task = "Defeat Yogg-Saron in Ulduar (25-player).",                         difficulty = "Hardcore I or higher" },
  [4] = { name = "Ahead of the Curve III", task = "Defeat Anub'arak in the Trial of the Crusader (25-player).",       difficulty = "Hardcore II or higher" },
  [5] = { name = "Ahead of the Curve IV",  task = "Defeat the Lich King in Icecrown Citadel (25-player).",            difficulty = "Hardcore III or higher" },
  [6] = { name = "Ahead of the Curve V",   task = "Defeat Halion in the Ruby Sanctum (25-player).",                   difficulty = "Hardcore IV or higher" },
}

local function GetTierColor(tier)
  if tier <= 1 then return 1, 1, 1 end
  local progress = (tier - 1) / (GetSliderMax() - 1)
  return 1.0, 1.0 - progress * 0.8, 1.0 - progress * 0.8
end

--- Build a display-data table for a given tier from the hardcoded table
local function GetTierDisplayData(tier)
  return TIER_DATA[tier] or TIER_DATA[1]
end

--- Returns true when the player is allowed to change difficulty
local function CanApply()
  local playerLevel = UnitLevel("player")
  -- Disallow changing difficulty in combat
  if UnitAffectingCombat and UnitAffectingCombat("player") then
    return false
  end
  return playerLevel <= 10 or IsResting()
end

--- Returns a red lock-reason string if the given tier cannot be applied due
--- to account-level requirements, or nil when no lock applies. When the lock is the
--- achievement gate, the tier is returned as a second value so the caller can hang the
--- "what do I have to do" tooltip off the line.
--- Mirrors what the server enforces on every difficulty-switch path
--- (MapInstanced::SwitchPlayerToDifficulty): reaching max level once, then the Hardcore
--- Soul Ash gate. This is presentation only - sending a locked tier is refused server-side.
local function GetHardmodeLockReason(tier)
  if tier <= 1 then return nil end

  local data = _G["EbonholdPlayerRunData"]
  local hasMax = data and data.hasReachedMaxLevel == true
  if not hasMax then
    return "Reach the level 80 to activate"
  end

  local svc = ProjectEbonhold.HardmodeService
  if not svc then return nil end

  -- The achievement is the first gate and the one that actually paces progression, so it is
  -- named first and alone: telling a player they are short on Soul Ashes when what they really
  -- need is to go kill a boss reads as a grind wall, which is exactly what this replaced.
  if not svc.IsAchievementEarned(tier) then
    -- Prefer the real achievement link (coloured, shift-clickable). It comes back empty on a
    -- client whose Achievement.dbc has not been patched yet, so fall back to the plain name,
    -- then to nothing at all rather than to a sentence that says nothing.
    local label = svc.GetAchievementLink and svc.GetAchievementLink(tier) or ""
    if label == "" then
      local name = svc.GetAchievementName(tier)
      if name ~= "" then label = "|cffFFD100" .. name .. "|r" end
    end

    if label == "" then
      return "Requires this tier's Hardcore achievement", tier
    end
    return "Requires " .. label, tier
  end

  -- Hardcore 1 is the only tier that still has a Soul Ash floor; every tier above it stops at
  -- the achievement, so it must not be held back by a pool it no longer cares about.
  local required = svc.GetSoulAshRequirement(tier)
  if required <= 0 then return nil end

  -- The threshold is hardcoded, but the committed pool it is compared against is not: a
  -- /reload leaves it at 0 until the server's next push. Fail closed rather than advertise the
  -- tier as available on a value we do not have yet.
  if not svc.IsCommittedSoulAshesKnown() then
    return "Loading Hardcore requirements..."
  end

  if not svc.IsTierUnlocked(tier) then
    local fmt = ProjectEbonhold.FormatThousands
    local missing = svc.GetSoulAshesMissingFor(tier)
    return "Requires " .. fmt(required) .. " committed Soul Ashes\n"
      .. "You have " .. fmt(svc.GetCommittedSoulAshes())
      .. " (" .. fmt(missing) .. " to go)"
  end

  return nil
end

--- Update Apply button / hint / lock-text visibility for the given selection.
local function RefreshApplyState(selTier, curTier)
  if not (hardmodeFrame and hardmodeFrame.applyBtn) then return end
  local applyBtn = hardmodeFrame.applyBtn
  local applyHint = hardmodeFrame.applyHint
  local applyLockText = hardmodeFrame.applyLockText
  local applyLockHover = hardmodeFrame.applyLockHover

  local function hideHint() if applyHint then applyHint:Hide() end end
  local function hideLock()
    if applyLockText then applyLockText:Hide() end
    if applyLockHover then applyLockHover:Hide() end
  end

  local lockReason, lockAchievementTier = GetHardmodeLockReason(selTier)
  if lockReason then
    applyBtn:Hide()
    hideHint()
    if applyLockText then
      applyLockText:SetText(lockReason)
      applyLockText:Show()
    end
    -- Only the achievement gate gets a tooltip: the Soul Ash line already prints its own
    -- numbers, but "Requires Ahead of the Curve II" says nothing about which boss to go kill.
    if applyLockHover then
      applyLockHover.tier = lockAchievementTier
      if lockAchievementTier then applyLockHover:Show() else applyLockHover:Hide() end
    end
    return
  end

  hideLock()

  if not CanApply() then
    applyBtn:Hide()
    if applyHint then applyHint:Show() end
    return
  end

  hideHint()
  applyBtn:Show()
  if selTier == curTier then
    applyBtn:Disable()
  else
    applyBtn:Enable()
  end
end

------------------------------------------------------------
-- SECTION BUILDER: bordered sub-panel inside the scroll
------------------------------------------------------------
local function CreateSection(parent, title, yOffset, width)
  local w = width or SECTION_WIDTH
  local section = CreateFrame("Frame", nil, parent)
  section:SetSize(w, 10)
  section:SetPoint("TOP", parent, "TOP", 0, yOffset)

  local header = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOP", section, "TOP", 0, -2)
  header:SetText(ColorText(title, COLOR_GOLD[1], COLOR_GOLD[2], COLOR_GOLD[3]))
  section.header = header

  section.contentTop = -18
  section.sectionWidth = w
  section.lines = {}
  section.iconRows = {}

  return section
end

local function AddLine(section, text, yOff)
  local y = yOff or (section.contentTop - (#section.lines * 16))
  local line = section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  line:SetPoint("TOP", section, "TOP", 0, y)
  line:SetWidth(SECTION_WIDTH - 24)
  line:SetJustifyH("CENTER")
  line:SetWordWrap(true)
  line:SetText(text)
  table.insert(section.lines, line)
  return line
end

local function FinaliseSection(section, bottomPadding)
  bottomPadding = bottomPadding or 4
  local lowest = section.contentTop
  for _, line in ipairs(section.lines) do
    local _, _, _, _, y = line:GetPoint(1)
    if y then
      local h = line:GetStringHeight() or 14
      local bottom = y - h
      if bottom < lowest then lowest = bottom end
    end
  end
  for _, row in ipairs(section.iconRows) do
    local _, _, _, _, y = row:GetPoint(1)
    if y then
      local h = row:GetHeight() or 20
      local bottom = y - h
      if bottom < lowest then lowest = bottom end
    end
  end
  local totalH = math.abs(lowest) + bottomPadding
  section:SetHeight(totalH)
  return totalH
end

------------------------------------------------------------
-- ICON ROW
------------------------------------------------------------

local TOOLTIP_SCALE = 0.85

local function AddIconRow(section, icon, text, yOff, tooltipTitle, tooltipBody)
  local row = CreateFrame("Frame", nil, section)
  row:SetSize(SECTION_WIDTH - 24, 18)
  row:SetPoint("TOPLEFT", section, "TOPLEFT", 12, yOff)

  local tex = row:CreateTexture(nil, "ARTWORK")
  tex:SetTexture(icon)
  tex:SetSize(14, 14)
  tex:SetPoint("LEFT", row, "LEFT", 0, 0)
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", tex, "RIGHT", 6, 0)
  label:SetWidth(SECTION_WIDTH - 60)
  label:SetJustifyH("LEFT")
  label:SetText(text)

  if tooltipTitle then
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetScale(TOOLTIP_SCALE)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(tooltipTitle, 1, 0.82, 0)
      if tooltipBody then
        GameTooltip:AddLine(tooltipBody, 1, 1, 1, true)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:SetScale(1); GameTooltip:Hide()
    end)
  end

  table.insert(section.iconRows, row)
  return row
end

-- --------------------------------------------------------
-- Horizontal icon strip helper
--   items = { { icon, tooltipTitle, tooltipBody }, ... }
--   Returns the strip frame (caller must store/cleanup)
-- --------------------------------------------------------
local HSTRIP_ICON   = 26
local HSTRIP_GAP    = 4
local HSTRIP_BORDER = 4 -- extra px for border frame around icon

local function CreateHIconStrip(parent, items, yOff)
  local strip = CreateFrame("Frame", nil, parent)
  local cellSize = HSTRIP_ICON + HSTRIP_BORDER
  strip:SetHeight(cellSize)
  local totalW = #items * cellSize + math.max(0, #items - 1) * HSTRIP_GAP
  strip:SetWidth(totalW)
  strip:SetPoint("TOP", parent, "TOP", 0, yOff)

  for i, entry in ipairs(items) do
    -- Border frame (like perk browser)
    local borderFrame = CreateFrame("Frame", nil, strip)
    borderFrame:SetSize(cellSize, cellSize)
    borderFrame:SetPoint("LEFT", strip, "LEFT", (i - 1) * (cellSize + HSTRIP_GAP), 0)
    borderFrame:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    if entry.borderColor then
      borderFrame:SetBackdropBorderColor(entry.borderColor[1], entry.borderColor[2], entry.borderColor[3],
        entry.borderColor[4] or 1)
    else
      borderFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end

    -- Icon centred inside border
    local tex = borderFrame:CreateTexture(nil, "ARTWORK")
    tex:SetSize(HSTRIP_ICON, HSTRIP_ICON)
    tex:SetPoint("CENTER", borderFrame, "CENTER", 0, 0)
    tex:SetTexture(entry.icon)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Desaturated (inactive) state
    if entry.desaturated then
      tex:SetDesaturated(true)
      tex:SetAlpha(0.45)
      borderFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.6)
    end

    -- Value text overlay (bottom line; shrink to 7 when a second line is also shown)
    if entry.value and not entry.desaturated then
      local valText = borderFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      valText:SetPoint("BOTTOM", borderFrame, "BOTTOM", 0, 1)
      valText:SetFont(valText:GetFont(), entry.value2 and 7 or 8, "OUTLINE")
      valText:SetText(entry.value)
      valText:SetTextColor(1, 1, 1, 1)
    end
    -- Second value text overlay (stacked above the first)
    if entry.value2 and not entry.desaturated then
      local val2Text = borderFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      val2Text:SetPoint("BOTTOM", borderFrame, "BOTTOM", 0, 10)
      val2Text:SetFont(val2Text:GetFont(), 7, "OUTLINE")
      val2Text:SetText(entry.value2)
      val2Text:SetTextColor(1, 0.85, 0.2, 1)
    end

    -- Tooltip
    borderFrame:EnableMouse(true)
    local tt = entry.tooltipTitle
    local tb = entry.tooltipBody
    local sid = entry.spellId
    borderFrame:SetScript("OnEnter", function(self)
      GameTooltip:SetScale(TOOLTIP_SCALE)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if sid then
        GameTooltip:SetHyperlink('spell:' .. sid)
      else
        GameTooltip:SetText(tt, 1, 0.82, 0)
        if tb then GameTooltip:AddLine(tb, 1, 1, 1, true) end
      end
      GameTooltip:Show()
    end)
    borderFrame:SetScript("OnLeave", function()
      GameTooltip:SetScale(1); GameTooltip:Hide()
    end)
  end

  return strip
end

------------------------------------------------------------
-- CONFIRMATION POPUP
------------------------------------------------------------

local function HidePopup()
  if confirmPopup then
    confirmPopup:Hide()
    confirmPopup.overlay:Hide()
    confirmPopup.blockFrame:Hide()
  end
end

local function ShowConfirmationPopup(tier)
  if not confirmPopup then
    local blockFrame = CreateFrame("Frame", "HardmodeBlockFrame", UIParent)
    blockFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    blockFrame:SetFrameLevel(999)
    blockFrame:SetAllPoints(UIParent)
    blockFrame:EnableMouse(true)
    blockFrame:SetScript("OnMouseDown", function() end)
    blockFrame:Hide()

    confirmPopup = CreateFrame("Frame", "HardmodeConfirmPopup", UIParent)
    confirmPopup:SetSize(380, 260)
    confirmPopup:SetPoint("CENTER")
    confirmPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    confirmPopup:SetFrameLevel(1000)
    confirmPopup.blockFrame = blockFrame

    local bg = confirmPopup:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\UI-Background-Rock")
    bg:SetPoint("TOPLEFT", 8, -8)
    bg:SetPoint("BOTTOMRIGHT", -8, 8)
    bg:SetHorizTile(true)
    bg:SetVertTile(true)

    confirmPopup:SetBackdrop({
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local overlay = confirmPopup:CreateTexture(nil, "BACKGROUND")
    overlay:SetTexture(0, 0, 0, 0.85)
    overlay:SetAllPoints(UIParent)
    confirmPopup.overlay = overlay

    confirmPopup:EnableMouse(true)
    confirmPopup:SetScript("OnMouseDown", function() end)

    confirmPopup.title = confirmPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    confirmPopup.title:SetPoint("TOP", 0, -20)
    confirmPopup.title:SetDrawLayer("OVERLAY", 7)

    confirmPopup.desc = confirmPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    confirmPopup.desc:SetPoint("TOP", confirmPopup.title, "BOTTOM", 0, -12)
    confirmPopup.desc:SetWidth(340)
    confirmPopup.desc:SetJustifyH("CENTER")
    confirmPopup.desc:SetWordWrap(true)
    confirmPopup.desc:SetDrawLayer("OVERLAY", 7)

    confirmPopup.acceptBtn = CreateFrame("Button", nil, confirmPopup, "UIPanelButtonTemplate")
    confirmPopup.acceptBtn:SetSize(120, 30)
    confirmPopup.acceptBtn:SetPoint("BOTTOM", confirmPopup, "BOTTOM", -65, 20)
    confirmPopup.acceptBtn:SetText("Accept")
    confirmPopup.acceptBtn:SetFrameLevel(confirmPopup:GetFrameLevel() + 10)

    confirmPopup.cancelBtn = CreateFrame("Button", nil, confirmPopup, "UIPanelButtonTemplate")
    confirmPopup.cancelBtn:SetSize(120, 30)
    confirmPopup.cancelBtn:SetPoint("BOTTOM", confirmPopup, "BOTTOM", 65, 20)
    confirmPopup.cancelBtn:SetText("Cancel")
    confirmPopup.cancelBtn:SetFrameLevel(confirmPopup:GetFrameLevel() + 10)
    confirmPopup.cancelBtn:SetScript("OnClick", HidePopup)
  end

  local tr, tg, tb = GetTierColor(tier)
  confirmPopup.title:SetText("|cffFFD100Change Difficulty|r")

  local msg
  if tier == 1 then
    msg = "Return to |cffFFFFFFNormal|r difficulty?\nAll hardcore effects will be removed."
  else
    local tierName = (TIER_DATA[tier] or TIER_DATA[1]).name
    local tierStr = ColorText(tierName, tr, tg, tb)
    msg = "Activate " ..
        tierStr ..
        " difficulty?\nEnemies will become significantly stronger\nand you will receive increased rewards.\n\n|cffFF4444Warning:|r Dying in Hardcore is |cffFF4444definitive|r: you cannot use any auto-resurrection mechanic. You are forced to commit your Soul Ashes in your Skill Tree to continue progressing. However, your character remains playable.\n\n|cffFFCC00Dungeon/Raid IDs are shared across all Hardcore and normal tiers.|r"
  end
  confirmPopup.desc:SetText(msg)

  confirmPopup.acceptBtn:SetScript("OnClick", function()
    HidePopup()
    if ProjectEbonhold.HardmodeService then
      ProjectEbonhold.HardmodeService.SetDifficulty(tier)
    end
  end)

  confirmPopup.blockFrame:Show()
  confirmPopup.overlay:Show()
  confirmPopup:Show()
end

------------------------------------------------------------
-- TIER SLIDER  (1 – 4)
------------------------------------------------------------

local function CreateTierSlider(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(220, 44)

  local slider = CreateFrame("Slider", "HardmodeTierSlider", frame, "OptionsSliderTemplate")
  slider:SetWidth(180)
  slider:SetHeight(17)
  slider:SetPoint("TOP", frame, "TOP", 0, -4)
  slider:SetMinMaxValues(SLIDER_MIN, GetSliderMax())
  slider:SetValueStep(1)

  _G[slider:GetName() .. "Low"]:SetText(SLIDER_MIN)
  _G[slider:GetName() .. "High"]:SetText(GetSliderMax())
  _G[slider:GetName() .. "Text"]:SetText("")

  frame.valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)

  local function UpdateLabel(tier)
    local r, g, b = GetTierColor(tier)
    local td = TIER_DATA[tier] or TIER_DATA[1]
    if tier == 1 then
      frame.valueText:SetText("|cffFFFFFFNormal|r")
      return
    end

    -- A locked tier stays selectable so the player can read what it costs and what it gives;
    -- the padlock plus the requirement under the Apply button is what tells them why they
    -- cannot switch to it. (The server refuses it regardless.)
    local label = ColorText(td.name, r, g, b)
    local svc = ProjectEbonhold.HardmodeService
    -- The pool-known guard only applies to a tier that still has a Soul Ash floor: without it,
    -- an achievement-locked tier would drop its padlock after a /reload for no reason.
    if svc and not svc.IsTierUnlocked(tier)
        and (svc.GetSoulAshRequirement(tier) <= 0 or svc.IsCommittedSoulAshesKnown()) then
      label = label .. " " .. LOCK_ICON
    end
    frame.valueText:SetText(label)
  end

  function frame:SetValue(tier)
    selectedTier = tier
    slider:SetValue(tier)
    UpdateLabel(tier)
  end

  function frame:GetValue()
    return selectedTier
  end

  slider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value + 0.5)
    if value == selectedTier then return end
    selectedTier = value
    UpdateLabel(value)
    -- Instantly refresh info sections from hardcoded data
    if hardmodeFrame and hardmodeFrame:IsShown() and hardmodeFrame.canvas then
      BuildInfoSections(hardmodeFrame.canvas, GetTierDisplayData(value), INFO_SECTIONS_Y)
    end
    -- Refresh Apply visibility/state on slider change
    if hardmodeFrame and hardmodeFrame.applyBtn then
      local svc = ProjectEbonhold.HardmodeService
      local curTier = svc and svc.GetCurrentDifficulty() or 1
      RefreshApplyState(value, curTier)
    end
  end)

  return frame
end

------------------------------------------------------------
-- INFO SECTIONS: built from a tier-data table
------------------------------------------------------------

local infoSectionFrames = {}

local function ClearInfoSections()
  for _, f in ipairs(infoSectionFrames) do
    if f.Hide then f:Hide() end
    if f.SetParent and f:GetObjectType() ~= "FontString" then
      f:SetParent(nil)
    end
  end
  infoSectionFrames = {}
end

-- forward-declared; assigned after definition
BuildInfoSections = nil

BuildInfoSections = function(canvas, displayData, startY)
  ClearInfoSections()

  local y = startY

  -- Tier 0: just show a centred "Normal difficulty" label
  if displayData.name == "Normal" then
    local label = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("TOP", canvas, "TOP", 0, y - 40)
    label:SetText("Normal difficulty")
    label:SetAlpha(0.75)
    table.insert(infoSectionFrames, label)
    canvas:SetHeight(math.abs(y) + 100)
    return y
  end

  --------------------------------------------------------
  -- Creature Modifiers  (single Open World row, full breakdown in tooltip)
  --------------------------------------------------------
  local s          = displayData.scaling

  local ICON_HP    = "Interface\\Icons\\PetBattle_Health"
  local ICON_MELEE = "Interface\\Icons\\Ability_MeleeDamage"
  local ICON_SPELL = "Interface\\Icons\\Spell_Ice_MagicDamage"

  local dualRow    = CreateFrame("Frame", nil, canvas)
  dualRow:SetSize(SECTION_WIDTH, 10) -- height set below
  dualRow:SetPoint("TOP", canvas, "TOP", 0, y)
  table.insert(infoSectionFrames, dualRow)

  local modTitle = dualRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  modTitle:SetPoint("TOP", dualRow, "TOP", 0, -2)
  modTitle:SetText(ColorText("Creature Modifiers", COLOR_GOLD[1], COLOR_GOLD[2], COLOR_GOLD[3]))

  local scalingItems = {
    {
      icon         = ICON_HP,
      value        = Pct(s.hp_multiplier),
      tooltipTitle = "Health  " .. Pct(s.hp_multiplier),
      tooltipBody  = "Open World: x" .. Fmt(s.hp_multiplier)
          .. "\nDungeon Boss: x" .. Fmt(s.dungeon_boss_hp_mul)
          .. "\nRaid Boss: x" .. Fmt(s.raid_boss_hp_mul)
          .. "\nDungeon Adds: x" .. Fmt(s.dungeon_add_hp_mul)
          .. "\nRaid Adds: x" .. Fmt(s.raid_add_hp_mul),
    },
    {
      icon         = ICON_MELEE,
      value        = Pct(s.melee_multiplier),
      tooltipTitle = "Melee  " .. Pct(s.melee_multiplier),
      tooltipBody  = "Open World: x" .. Fmt(s.melee_multiplier)
          .. "\nDungeon Boss: x" .. Fmt(s.dungeon_boss_melee_mul)
          .. "\nRaid Boss: x" .. Fmt(s.raid_boss_melee_mul)
          .. "\nDungeon Adds: x" .. Fmt(s.dungeon_add_melee_mul)
          .. "\nRaid Adds: x" .. Fmt(s.raid_add_melee_mul),
    },
    {
      icon         = ICON_SPELL,
      value        = Pct(s.spell_multiplier),
      tooltipTitle = "Spell  " .. Pct(s.spell_multiplier),
      tooltipBody  = "Open World: x" .. Fmt(s.spell_multiplier)
          .. "\nDungeon Boss: x" .. Fmt(s.dungeon_boss_spell_mul)
          .. "\nRaid Boss: x" .. Fmt(s.raid_boss_spell_mul)
          .. "\nDungeon Adds: x" .. Fmt(s.dungeon_add_spell_mul)
          .. "\nRaid Adds: x" .. Fmt(s.raid_add_spell_mul),
    },
  }
  local scalingStrip = CreateHIconStrip(dualRow, scalingItems, 0)
  scalingStrip:ClearAllPoints()
  scalingStrip:SetPoint("TOP", modTitle, "BOTTOM", 0, -4)
  table.insert(infoSectionFrames, scalingStrip)

  -- title(2+14) + gap(4) + row(30) + padding(6)
  local dualRowH = 2 + 14 + 4 + (HSTRIP_ICON + HSTRIP_BORDER) + 6
  dualRow:SetHeight(dualRowH)
  y = y - dualRowH - 6

  --------------------------------------------------------
  -- Bonuses & Creature Empowerments (single section, full width)
  --------------------------------------------------------
  local rewardSec = CreateSection(canvas, "Bonuses", y)
  table.insert(infoSectionFrames, rewardSec)

  local rw           = displayData.rewards
  local rwY          = rewardSec.contentTop

  local GREEN_BORDER = { 0.1, 1, 0.1, 0.8 }
  local GREY_BORDER  = { 0.35, 0.35, 0.35, 0.6 }

  local function RewardIcon(icon, multiplier, label)
    local active = multiplier > 1.0
    return {
      icon         = icon,
      value        = Pct(multiplier),
      borderColor  = active and GREEN_BORDER or GREY_BORDER,
      desaturated  = not active,
      tooltipTitle = label .. "  " .. Pct(multiplier),
      tooltipBody  = active
          and (label .. " increased by " .. Pct(multiplier))
          or (label .. ", no bonus at this tier"),
    }
  end

  local xpActive = rw.quest_xp_multiplier > 1.0 or rw.creature_xp_multiplier > 1.0
  local extraLootCount = rw.extra_loot_count or 0
  local extraLootActive = extraLootCount > 0
  local rewardItems = {
    RewardIcon(ICON_GOLD, rw.gold_multiplier, "Gold"),
    {
      icon         = "Interface\\AddOns\\ProjectEbonhold\\assets\\xp_icon",
      value        = Pct(rw.quest_xp_multiplier),
      value2       = Pct(rw.creature_xp_multiplier),
      borderColor  = xpActive and GREEN_BORDER or GREY_BORDER,
      desaturated  = not xpActive,
      tooltipTitle = "Experience",
      tooltipBody  = "Quest XP: " .. Pct(rw.quest_xp_multiplier) .. "\nKill XP:  " .. Pct(rw.creature_xp_multiplier),
    },
    RewardIcon(ICON_SOUL_ASH, rw.soul_ash_multiplier, "Soul Ash"),
    RewardIcon(ICON_REAGENT, rw.reagent_multiplier, "Reagents"),
    {
      icon         = ICON_LOOT,
      value        = extraLootActive and ("+" .. extraLootCount) or nil,
      borderColor  = extraLootActive and GREEN_BORDER or GREY_BORDER,
      desaturated  = not extraLootActive,
      tooltipTitle = extraLootActive and ("Extra Loot  +" .. extraLootCount) or "Extra Loot",
      tooltipBody  = extraLootActive
          and ("Creatures and bosses drop +" .. extraLootCount .. " additional loot item(s) on top of their normal drops.")
          or "Not active at this tier.",
    },
  }

  local affixTier = rw.affix_chance_tier or 0
  local affixDescs = {
    [1] =
    "Equipment looted in the open world, dungeons and raids has a small chance to drop corrupted with a random stat modifier.\n\nExtract affixes from corrupted gear to learn them, then apply them to clean items.",
    [2] =
    "Equipment looted in the open world, dungeons and raids has an increased chance to drop corrupted.\n\nMore corruption types become available and roll chances scale higher than Tier 1.",
    [3] =
    "Equipment looted in the open world, dungeons and raids has a high chance to drop corrupted with powerful modifiers.\n\nAll corruption types are unlocked and roll at maximum probability.",
    [4] =
    "Tier 4 affixes drop only from raid equipment, with powerful modifiers and a high chance to roll.\n\nLower-tier affixes (Tier 1-3) can still drop from open world, dungeons and raids as before.\n\nAll corruption types are unlocked and roll at maximum probability.",
    [5] =
    "Tier 5 affixes drop from raid equipment with the most powerful modifiers and the highest chance to roll.\n\nLower-tier affixes (Tier 1-4) can still drop from open world, dungeons and raids as before.\n\nAll corruption types are unlocked and roll at maximum probability.",

  }
  table.insert(rewardItems, {
    icon         = "Interface\\Icons\\Inv_enchant_formulasuperior_01",
    borderColor  = affixTier > 0 and GREEN_BORDER or GREY_BORDER,
    desaturated  = affixTier == 0,
    tooltipTitle = affixTier > 0 and ("Predefined Affixes : Tier " .. affixTier) or "Predefined Affixes",
    tooltipBody  = affixTier > 0
        and affixDescs[affixTier]
        or "Not active at this tier.",
  })

  local iccActive = rw.icc_affixes == true
  table.insert(rewardItems, {
    icon         = "Interface\\Icons\\Achievement_Zone_Icecrown_01",
    borderColor  = iccActive and GREEN_BORDER or GREY_BORDER,
    desaturated  = not iccActive,
    tooltipTitle = iccActive and "ICC Affixes : Tier VI" or "ICC Affixes",
    tooltipBody  = iccActive
        and
        "Unleashes Tier VI affixes, the most powerful corruptions in the game.\n\nEquipment looted inside Icecrown Citadel has a chance to drop corrupted with these devastating modifiers, found nowhere else."
        or "Not active at this tier.",
  })

  local rewardStrip = CreateHIconStrip(rewardSec, rewardItems, rwY)
  table.insert(rewardSec.iconRows, rewardStrip)
  table.insert(infoSectionFrames, rewardStrip)
  rwY = rwY - HSTRIP_ICON - 4

  -- Creature Empowerments sub-row (replaces Curses)
  do
    -- Build ordered unique aura list: sorted by first unlock tier (lowest → highest)
    local orderedAuras = {}
    local seenAura = {}
    for tier = 2, GetSliderMax() do
      for _, aura in ipairs(TIER_DATA[tier].auras or {}) do
        if not seenAura[aura.spellId] then
          seenAura[aura.spellId] = true
          table.insert(orderedAuras, { spellId = aura.spellId, unlockTier = tier })
        end
      end
    end

    if #orderedAuras > 0 then
      rwY = rwY - 8 -- extra gap between reward icons and Creature Empowerments

      local auraMaxLabel = (s.aura_max and s.aura_max > 0) and ("  (Max " .. s.aura_max .. ")") or ""
      local empLabel = rewardSec:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      empLabel:SetPoint("TOP", rewardSec, "TOP", 0, rwY)
      empLabel:SetText(ColorText("Creature Empowerments" .. auraMaxLabel,
        COLOR_GOLD[1], COLOR_GOLD[2], COLOR_GOLD[3]))
      table.insert(rewardSec.lines, empLabel)
      rwY = rwY - 16

      local activeAuras = {}
      for _, aura in ipairs(displayData.auras or {}) do
        activeAuras[aura.spellId] = true
      end

      local auraItems = {}
      for _, aura in ipairs(orderedAuras) do
        local sid = aura.spellId
        local isActive = activeAuras[sid] or false
        local auraName, _, auraIcon = GetSpellInfo(sid)
        auraName = auraName or ("Spell " .. sid)
        auraIcon = auraIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
        table.insert(auraItems, {
          icon         = auraIcon,
          borderColor  = isActive and { 1, 0.2, 0.2, 0.8 } or nil,
          desaturated  = not isActive,
          spellId      = sid,
          tooltipTitle = auraName,
          tooltipBody  = isActive
              and ("Unlocked at Tier " .. aura.unlockTier .. ", creatures can gain this aura")
              or ("Unlocked at Tier " .. aura.unlockTier .. ", not active at this difficulty"),
        })
      end

      local auraStrip = CreateHIconStrip(rewardSec, auraItems, rwY)
      table.insert(rewardSec.iconRows, auraStrip)
      table.insert(infoSectionFrames, auraStrip)
    end
  end

  local rewardH = FinaliseSection(rewardSec)
  y = y - rewardH - 6

  --------------------------------------------------------
  -- Extra Loot
  --------------------------------------------------------
  local extraLoot = displayData.extraLoot or {}
  local maxExtraLoot = TIER_DATA[GetSliderMax()].extraLoot or {}
  if #maxExtraLoot > 0 then
    local activeBags = {}
    for _, item in ipairs(extraLoot) do
      activeBags[item.bagType] = true
    end

    local lootSec = CreateSection(canvas, "Bonus Loot", y)
    table.insert(infoSectionFrames, lootSec)
    local lY = lootSec.contentTop
    local lootItems = {}
    for _, item in ipairs(maxExtraLoot) do
      local isActive = activeBags[item.bagType] or false
      if item.bagType == "dungeon" then
        table.insert(lootItems, {
          icon         = "Interface\\Icons\\garrison_bluearmor",
          borderColor  = isActive and GREEN_BORDER or GREY_BORDER,
          desaturated  = not isActive,
          tooltipTitle = "Blue Loot",
          tooltipBody  = isActive
              and
              "Grants a chance to obtain a blue-quality item upon defeating enemies. The item’s level matches that of the defeated creature and it drops without any affixes"
              or "Not available at this tier.",
        })
      elseif item.bagType == "raid" then
        table.insert(lootItems, {
          icon         = "Interface\\Icons\\garrison_purplearmor",
          borderColor  = isActive and GREEN_BORDER or GREY_BORDER,
          desaturated  = not isActive,
          tooltipTitle = "Epic Loot",
          tooltipBody  = isActive
              and
              "Grants a chance to obtain an epic-quality item upon defeating enemies. The item’s level matches that of the defeated creature and it drops without any affixes"
              or "Not available at this tier.",
        })
      end
    end
    local lootStrip = CreateHIconStrip(lootSec, lootItems, lY)
    table.insert(lootSec.iconRows, lootStrip)
    table.insert(infoSectionFrames, lootStrip)
    lY = lY - HSTRIP_ICON - 4
    local lootH = FinaliseSection(lootSec)
    y = y - lootH - 6
  end

  local contentH = math.abs(y) + 20
  canvas:SetHeight(contentH)
  return y
end

-- Y offset where info sections start (below the top bar)
INFO_SECTIONS_Y = -105

--- Tooltip for the achievement gate under the slider. The lock line only names the
--- achievement; this spells out the boss, the raid and the world difficulty it has to die at.
local function ShowAchievementGateTooltip(owner, tier)
  local hint = ACHIEVEMENT_HINTS[tier]
  if not hint then return end

  local svc = ProjectEbonhold.HardmodeService
  -- Prefer the client's own name so a renamed achievement never drifts from the tooltip;
  -- the hardcoded one covers a client without the patched Achievement.dbc.
  local name = svc and svc.GetAchievementName(tier) or ""
  if name == "" then name = hint.name end

  GameTooltip:SetScale(TOOLTIP_SCALE)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(name, 1, 0.82, 0)
  GameTooltip:AddLine(hint.task, 1, 1, 1, true)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("World difficulty: " .. hint.difficulty, 0.4, 0.9, 0.4, true)
  if hint.note then
    GameTooltip:AddLine(hint.note, 0.7, 0.7, 0.7, true)
  end
  GameTooltip:Show()
end

------------------------------------------------------------
-- BUILD THE MAIN PANEL
------------------------------------------------------------

local function BuildContent(canvas, currentTier)
  -- Wipe previous children
  local children = { canvas:GetChildren() }
  for _, c in ipairs(children) do
    c:Hide(); c:SetParent(nil)
  end
  local regions = { canvas:GetRegions() }
  for _, r in ipairs(regions) do
    if r and r.Hide then r:Hide() end
  end
  infoSectionFrames = {}

  --------------------------------------------------------
  -- TOP BAR
  --------------------------------------------------------
  local topBar = CreateFrame("Frame", nil, canvas)
  topBar:SetSize(SECTION_WIDTH, 70)
  topBar:SetPoint("TOP", canvas, "TOP", 0, 0)

  -- Slider – centred horizontally, 40 px below top
  local slider = CreateTierSlider(topBar)
  slider:SetPoint("TOP", topBar, "TOP", 0, -18)
  slider:SetValue(currentTier)

  -- Apply button – centred, below the slider
  local applyBtn = utils.CreateSimpleCustomButton(topBar,
    "Apply",
    function()
      local playerLevel = UnitLevel("player")
      if UnitAffectingCombat and UnitAffectingCombat("player") then
        DEFAULT_CHAT_FRAME:AddMessage(
          "|cffFF0000[Hardcore] You cannot change difficulty while in combat.|r")
        return
      end
      if playerLevel > 10 and not IsResting() then
        DEFAULT_CHAT_FRAME:AddMessage(
          "|cffFF0000[Hardcore] You must be level 10 or below, or rested (in an inn or capital city) to change difficulty.|r")
        return
      end
      local svc = ProjectEbonhold.HardmodeService
      local curTier = svc and svc.GetCurrentDifficulty() or 1
      if selectedTier ~= curTier then
        ShowConfirmationPopup(selectedTier)
      end
    end,
    120, 30)
  applyBtn:SetPoint("TOP", slider, "BOTTOM", 0, -4)

  -- Disable Apply if already at the current tier
  hardmodeFrame.applyBtn = applyBtn

  -- Hint shown when Apply is hidden (not in a rested area)
  local applyHint = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  applyHint:SetPoint("TOP", slider, "BOTTOM", 0, -6)
  applyHint:SetWidth(280)
  applyHint:SetJustifyH("CENTER")
  applyHint:SetWordWrap(true)
  applyHint:SetText(
    "|cffFF6666You must be level 10, rested (inn or capital city), and not in combat to change difficulty.|r")
  hardmodeFrame.applyHint = applyHint

  -- Red lock-reason text shown in place of Apply when hardcore is gated
  local applyLockText = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  applyLockText:SetPoint("TOP", slider, "BOTTOM", 0, -8)
  applyLockText:SetWidth(320)
  applyLockText:SetJustifyH("CENTER")
  applyLockText:SetWordWrap(true)
  applyLockText:SetTextColor(1, 0.2, 0.2)
  applyLockText:Hide()
  hardmodeFrame.applyLockText = applyLockText

  -- A FontString cannot take mouse input, so a transparent frame is pinned over its rect
  -- purely to own the tooltip. Anchored to both corners so it follows the line as it wraps.
  -- RefreshApplyState shows it (and stamps .tier) only on the achievement gate.
  local applyLockHover = CreateFrame("Frame", nil, topBar)
  applyLockHover:SetPoint("TOPLEFT", applyLockText, "TOPLEFT", 0, 0)
  applyLockHover:SetPoint("BOTTOMRIGHT", applyLockText, "BOTTOMRIGHT", 0, 0)
  applyLockHover:EnableMouse(true)
  applyLockHover:Hide()
  applyLockHover:SetScript("OnEnter", function(self)
    ShowAchievementGateTooltip(self, self.tier)
  end)
  applyLockHover:SetScript("OnLeave", function()
    GameTooltip:SetScale(1); GameTooltip:Hide()
  end)
  hardmodeFrame.applyLockHover = applyLockHover

  RefreshApplyState(selectedTier, currentTier)
  BuildInfoSections(canvas, GetTierDisplayData(currentTier), INFO_SECTIONS_Y)
end

local function CreateHardmodeFrame()
  hardmodeFrame = CreateFrame("Frame", "HardmodeFrame", UIParent)
  hardmodeFrame:SetSize(PANEL_WIDTH, PANEL_MIN_H)
  hardmodeFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  hardmodeFrame:SetFrameStrata("HIGH")

  local bgTexture = hardmodeFrame:CreateTexture(nil, "BACKGROUND")
  bgTexture:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\background-torment")
  bgTexture:SetAllPoints(hardmodeFrame)
  bgTexture:SetTexCoord(0, 0.84375, 0, 0.70703125)

  hardmodeFrame:SetMovable(true)
  hardmodeFrame:EnableMouse(true)
  hardmodeFrame:RegisterForDrag("LeftButton")
  hardmodeFrame:SetScript("OnDragStart", hardmodeFrame.StartMoving)
  hardmodeFrame:SetScript("OnDragStop", hardmodeFrame.StopMovingOrSizing)

  local closeBtn = CreateFrame("Button", nil, hardmodeFrame, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", hardmodeFrame, "TOPRIGHT", -10, -10)

  local canvas = CreateFrame("Frame", "HardmodeCanvas", hardmodeFrame)
  canvas:SetPoint("TOPLEFT", hardmodeFrame, "TOPLEFT", 10, -42)
  canvas:SetPoint("TOPRIGHT", hardmodeFrame, "TOPRIGHT", -10, -42)
  canvas:SetHeight(800)

  hardmodeFrame.canvas = canvas

  -- Lock overlay shown until the account has reached max level once.
  -- Created as a top-level frame on UIParent and anchored over the panel.
  local lockOverlay = CreateFrame("Frame", "HardmodeLockOverlay", UIParent)
  lockOverlay:SetPoint("TOPLEFT", hardmodeFrame, "TOPLEFT", 4, -30)
  lockOverlay:SetPoint("BOTTOMRIGHT", hardmodeFrame, "BOTTOMRIGHT", -4, 4)
  lockOverlay:SetFrameStrata("FULLSCREEN_DIALOG")
  lockOverlay:SetFrameLevel(1000)
  lockOverlay:EnableMouse(true)
  lockOverlay:EnableMouseWheel(true)
  lockOverlay:SetScript("OnMouseDown", function() end)
  lockOverlay:SetScript("OnMouseWheel", function() end)

  lockOverlay:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  lockOverlay:SetBackdropColor(0, 0, 0, 1)

  local lockSkull = lockOverlay:CreateTexture(nil, "OVERLAY")
  lockSkull:SetTexture("Interface\\Icons\\INV_Misc_Bone_Skull_02")
  lockSkull:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  lockSkull:SetSize(56, 56)
  lockSkull:SetPoint("TOP", lockOverlay, "TOP", 0, -20)

  local lockTitle = lockOverlay:CreateFontString(nil, "OVERLAY")
  lockTitle:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
  lockTitle:SetPoint("TOP", lockSkull, "BOTTOM", 0, -8)
  lockTitle:SetTextColor(1, 0, 0)
  lockTitle:SetText("Hardcore")

  local lockMsg = lockOverlay:CreateFontString(nil, "OVERLAY")
  lockMsg:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
  lockMsg:SetPoint("TOP", lockTitle, "BOTTOM", 0, -20)
  lockMsg:SetWidth(PANEL_WIDTH - 50)
  lockMsg:SetJustifyH("CENTER")
  lockMsg:SetWordWrap(true)
  lockMsg:SetNonSpaceWrap(true)
  lockMsg:SetSpacing(4)
  lockMsg:SetTextColor(1, 1, 1)
  lockMsg:SetText(
    "Hardcore mode lets you increase your |cffFFD100rewards|r, at the cost of a much harder challenge.\n\n" ..
    "To unlock Hardcore, you must reach |cffFFD100level 80|r with one of the characters on your account.\n\n" ..
    "|cffFF4444Dying in Hardcore is definitive:|r you cannot use any auto-resurrection mechanic. You are forced to commit your Soul Ashes in your Skill Tree to continue progressing. However, your character remains playable."
  )

  local gotItBtn = utils.CreateSimpleCustomButton(lockOverlay,
    "Got it",
    function()
      lockOverlay:Hide()
    end,
    120, 30)
  gotItBtn:SetPoint("BOTTOM", lockOverlay, "BOTTOM", 0, 20)
  gotItBtn:SetFrameStrata("FULLSCREEN_DIALOG")
  gotItBtn:SetFrameLevel(lockOverlay:GetFrameLevel() + 10)

  hardmodeFrame.lockOverlay = lockOverlay
  lockOverlay:Hide()
  hardmodeFrame:HookScript("OnHide", function()
    lockOverlay:Hide()
  end)
  hardmodeFrame:Hide()
  table.insert(UISpecialFrames, "HardmodeFrame")
end

------------------------------------------------------------
-- HARDCORE RANK UNLOCK ALERT
------------------------------------------------------------
-- Fired by SEND_HARDCORE_TIER_UNLOCKED, which the server sends ONLY at the moment the
-- committed Soul Ash gate is crossed (PlayerRunHandler::RewardPassedMilestones, the same
-- place the meta-progression milestones are granted). Nothing here re-derives the crossing
-- from a Soul Ash update, so relogging or gaining more ashes can never replay an alert.
--
-- Presented as the yellow GlowBox alert anchored on the Hardcore skull icon of the run HUD
-- (the same treatment the Skill Tree uses for unspent points), NOT as a modal popup: the
-- unlock is an invitation to open the Hardcore panel, and it points straight at the button
-- that opens it.

-- A single commit can cross several gates at once (a big Soul Ash payout, or thresholds
-- retuned downward), so unlocks are queued and shown one at a time.
local pendingUnlockRanks = {}
local unlockAlert = nil

local UNLOCK_ALERT_DURATION = 12   -- seconds before the alert fades on its own

local function GetHardcoreAnchor()
  -- The run HUD builds the skull icon; until it exists there is nothing to point at.
  return ProjectEbonhold.HardmodeButton
end

local ShowNextUnlockAlert

-- One-shot retry used while the run HUD has not created the skull icon yet.
local unlockAlertRetryFrame = nil
local function ScheduleUnlockAlertRetry()
  unlockAlertRetryFrame = unlockAlertRetryFrame or CreateFrame("Frame")
  local elapsedTotal = 0
  unlockAlertRetryFrame:SetScript("OnUpdate", function(self, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < 1 then return end
    self:SetScript("OnUpdate", nil)
    if ShowNextUnlockAlert then ShowNextUnlockAlert() end
  end)
end

local function CreateUnlockAlert()
  local anchor = GetHardcoreAnchor()
  if not anchor then return nil end

  local alert = CreateFrame("Frame", "EbonholdHardcoreUnlockAlert", UIParent, "GlowBoxTemplate")
  alert:SetSize(250, 92)
  alert:SetPoint("BOTTOM", anchor, "TOP", 0, 14)
  alert:SetFrameStrata("DIALOG")
  alert:SetFrameLevel(20)
  alert:EnableMouse(true)
  alert:Hide()

  alert.Text = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
  alert.Text:SetJustifyV("TOP")
  alert.Text:SetSize(216, 0)
  alert.Text:SetPoint("TOPLEFT", 16, -20)

  alert.CloseButton = CreateFrame("Button", nil, alert, "UIPanelCloseButton")
  alert.CloseButton:SetPoint("TOPRIGHT", 6, 6)
  alert.CloseButton:SetScript("OnClick", function() alert:Hide() end)

  alert.Arrow = CreateFrame("Frame", nil, alert, "GlowBoxArrowTemplate")
  alert.Arrow:SetPoint("TOP", alert, "BOTTOM", 0, 4)

  -- Clicking the alert opens the panel it is advertising.
  alert:SetScript("OnMouseDown", function()
    alert:Hide()
    if Addon and Addon.ToggleHardmodeFrame then Addon.ToggleHardmodeFrame() end
  end)

  -- Hiding for any reason (timer, close button, click) hands the slot to the next unlock.
  alert:SetScript("OnHide", function()
    -- Stop the auto-dismiss ticker: dismissing by hand must not leave it running for the
    -- alert the queue is about to show.
    if alert.dismissTimer then alert.dismissTimer:SetScript("OnUpdate", nil) end
    if ShowNextUnlockAlert then ShowNextUnlockAlert() end
  end)

  unlockAlert = alert
  return alert
end

ShowNextUnlockAlert = function()
  if unlockAlert and unlockAlert:IsShown() then return end

  local rank = table.remove(pendingUnlockRanks, 1)
  if not rank then return end

  local tier = rank + 1   -- rank R is difficulty tier R+1 (tier 1 is Normal)
  local td = TIER_DATA[tier]
  local tierName = (td and td.name) or ("Hardcore " .. rank)
  local svc = ProjectEbonhold.HardmodeService
  local required = svc and svc.GetSoulAshRequirement(tier) or 0

  -- Link first, plain name as a fallback for a client without the patched Achievement.dbc.
  local achievement = svc and svc.GetAchievementLink and svc.GetAchievementLink(tier) or ""
  if achievement == "" and svc then achievement = svc.GetAchievementName(tier) end

  local text = "|cffFFD100" .. tierName .. " unlocked!|r" .. "\n\n"
  -- The achievement is what the player just did; the Soul Ash floor is only mentioned when the
  -- tier has no achievement of its own, so the alert never credits the wrong thing.
  if achievement ~= "" then
    text = text .. "You earned " .. achievement .. "." .. "\n\n"
  elseif required > 0 then
    text = text .. "You have reached " .. ProjectEbonhold.FormatThousands(required)
      .. " committed Soul Ashes." .. "\n\n"
  end
  text = text .. "Click here to choose your difficulty."

  local alert = unlockAlert or CreateUnlockAlert()
  if not alert then
    -- The run HUD (and with it the skull icon this alert points at) has not been built yet.
    -- Put the rank back at the FRONT of the queue and retry shortly, so an unlock that lands
    -- during loading is shown rather than silently dropped.
    table.insert(pendingUnlockRanks, 1, rank)
    ScheduleUnlockAlertRetry()
  else
    alert.Text:SetText(text)
    alert:Show()

    -- Auto-dismiss so the alert never sits on the HUD forever; OnHide drains the queue.
    if alert.dismissTimer then alert.dismissTimer:SetScript("OnUpdate", nil) end
    alert.dismissTimer = alert.dismissTimer or CreateFrame("Frame", nil, alert)
    local elapsedTotal = 0
    alert.dismissTimer:SetScript("OnUpdate", function(self, elapsed)
      elapsedTotal = elapsedTotal + elapsed
      if elapsedTotal >= UNLOCK_ALERT_DURATION then
        self:SetScript("OnUpdate", nil)
        alert:Hide()
      end
    end)

    -- Chat line and sound ride with the alert that was actually shown, so a retry does not
    -- announce the same unlock twice.
    DEFAULT_CHAT_FRAME:AddMessage("|cffFFD100[Hardcore]|r " .. tierName .. " unlocked!")
    if PlaySound then PlaySound("LEVELUP") end
  end
end

--- Queue the unlock alerts for the given Hardcore ranks (array of numbers).
function ProjectEbonhold.HardmodeUI.ShowTierUnlocked(ranks)
  if type(ranks) ~= "table" then return end
  for _, rank in ipairs(ranks) do
    table.insert(pendingUnlockRanks, rank)
  end
  ShowNextUnlockAlert()
end

local function IsHardmodeUnlocked()
  local data = _G["EbonholdPlayerRunData"]
  return data and data.hasReachedMaxLevel == true
end

local function UpdateLockOverlay(currentTier)
  if not hardmodeFrame or not hardmodeFrame.lockOverlay then return end
  -- Keep the panel interactive when the player is already on Hardcore so they can always switch back to Normal.
  if IsHardmodeUnlocked() or (currentTier and currentTier > 1) then
    hardmodeFrame.lockOverlay:Hide()
  else
    hardmodeFrame.lockOverlay:Show()
  end
end

function ProjectEbonhold.HardmodeUI.Refresh()
  if not hardmodeFrame then return end
  if not hardmodeFrame:IsShown() then return end

  local svc = ProjectEbonhold.HardmodeService
  local tier = svc and svc.GetCurrentDifficulty() or 1
  BuildContent(hardmodeFrame.canvas, tier)
  UpdateLockOverlay(tier)
end

function Addon.ToggleHardmodeFrame()
  if not hardmodeFrame then
    CreateHardmodeFrame()
  end

  if hardmodeFrame:IsShown() then
    hardmodeFrame:Hide()
  else
    -- Ask server for current tier
    if ProjectEbonhold.HardmodeService then
      ProjectEbonhold.HardmodeService.RequestHardmodeData()
    end
    -- And for the committed Soul Ash pool the tier locks read, which arrives with the
    -- prestige packet: after a /reload nothing has pushed it yet and every tier would
    -- otherwise render as locked until the player opens the Prestige tab.
    if ProjectEbonhold.PrestigeService and ProjectEbonhold.PrestigeService.RequestPrestigeData then
      ProjectEbonhold.PrestigeService.RequestPrestigeData()
    end
    hardmodeFrame:Show()

    local svc = ProjectEbonhold.HardmodeService
    local tier = svc and svc.GetCurrentDifficulty() or 1
    BuildContent(hardmodeFrame.canvas, tier)
    UpdateLockOverlay(tier)
  end
end

Addon.ToggleTormentFrame = Addon.ToggleHardmodeFrame
