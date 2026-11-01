-- ==============================================================================
-- Torment tier selector, shared by the Torment frame (hardmode.lua) and the Dungeon
-- Finder (dungeon_finder.lua).
--
-- Drawn with the addon's own art (assets/torment_*.tga, see tools/torment_assets.py):
--   * the tier name sits on the title pill (torment_banner),
--   * the stepper arrows are the client's page-flip buttons (UI-SpellbookIcon-PrevPage / NextPage),
--   * the ladder is one gold-bevelled rung (torment_btn_*) per tier (N, I..X, plus an "XI+" rung when the caller
--     asks for the cosmetic tiers): the rung being looked at is pushed in, a locked rung wears
--     the disabled face and the addon's padlock, the rung that is in
--     force wears a green frame.
--
-- Contract: frame:SetValue(tier) / frame:GetValue() / frame:Redraw(). Everything the widget
-- needs to know about a tier comes from the cfg callbacks, so the two callers keep their own
-- notion of "locked" and "current" (achievement gate vs. server-held queue tier).
-- ==============================================================================
local TS = {}
ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.TierSelector = TS

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
  "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX",
  "XXI", "XXII", "XXIII", "XXIV", "XXV", "XXVI", "XXVII", "XXVIII", "XXIX", "XXX" }

--- "N" for Normal, the roman numeral of the Torment otherwise.
function TS.ShortName(tier)
  if tier <= 1 then return "N" end
  return ROMAN[tier - 1] or tostring(tier - 1)
end

local ART      = "Interface\\AddOns\\ProjectEbonhold\\assets\\"
local TEX_LOCK = ART .. "lock"   -- the padlock the rest of the addon uses

local ARROW    = 32   -- the page-flip buttons are 32 px art
local RUNG_H   = 22
local RUNG_GAP = 3
local BANNER_Y = -4
local LADDER_Y = -48
TS.HEIGHT = -LADDER_Y + RUNG_H
TS.STEPPER_HEIGHT = -BANNER_Y + 32   -- arrows + banner only
TS.RUNG_HEIGHT = RUNG_H

-- Frame around the rung of the tier in force.
local CURRENT_EDGE = 2
local CURRENT_PAD  = 1
local CURRENT_R, CURRENT_G, CURRENT_B = 0.2, 1, 0.2

-- 8 pt variant of GameFontNormalSmall for the five-glyph numerals (XVIII) of the cosmetic
-- rung; created once, on first use.
local tinyFonts
local function TinyFont(which)
  if not tinyFonts then
    tinyFonts = {}
    local bases = { normal = GameFontNormalSmall, highlight = GameFontHighlightSmall, disable = GameFontDisableSmall }
    for key, base in pairs(bases) do
      local f = CreateFont("ProjectEbonholdTierRungTiny" .. key)
      f:SetFontObject(base)
      local path, _, flags = base:GetFont()
      f:SetFont(path, 8, flags)
      tinyFonts[key] = f
    end
  end
  return tinyFonts[which]
end

local function CreateArrow(parent, dir)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(ARROW, ARROW)
  -- The client's own page-flip buttons (spellbook, quest log), so they match the rest of
  -- the UI whatever art pack is installed.
  local base = dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
  btn:SetNormalTexture(base .. "Up")
  btn:SetPushedTexture(base .. "Down")
  btn:SetDisabledTexture(base .. "Disabled")
  btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  btn.SetEnabledLook = function(self, enabled)
    if enabled then self:Enable() else self:Disable() end
  end
  return btn
end

--- cfg:
---   width        widget width (the ladder spans it, arrows sit on its edges)
---   rungs        number of real rungs (11 = Normal, Torment I..X)
---   cosmetic     true adds a twelfth "XI+" rung standing for every tier above `rungs`
---   GetMax()     highest tier the widget may step to
---   GetName(t)   tier name for the banner;  GetColor(t) -> r, g, b
---   IsLocked(t)  rung wears the disabled face + padlock (still browsable)
---   GetCurrent() tier in force (glow), or nil
---   CanStep()    false greys both arrows (optional)
---   ShiftMax()   tier the shift-clicked ">" jumps to (optional, defaults to GetMax)
---   OnSelect(t)  the user picked t (arrow, wheel, rung); the caller decides what to do
---   OnRungEnter(btn, t)  fills GameTooltip for a rung (optional)
function TS.Create(parent, cfg)
  local width = cfg.width
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(width, TS.HEIGHT)
  frame.value = 1

  --------------------------------------------------------
  -- Banner + arrows
  --------------------------------------------------------
  local banner = ProjectEbonhold.TormentWidgets.CreateBanner(frame, width - 2 * (ARROW + 8), 14)
  banner:SetPoint("TOP", frame, "TOP", 0, BANNER_Y)
  frame.banner = banner
  local name = banner.text
  frame.name = name

  local prev = CreateArrow(frame, -1)
  local nxt  = CreateArrow(frame, 1)
  prev:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, BANNER_Y)
  nxt:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, BANNER_Y)
  frame.prev, frame.next = prev, nxt

  local wheel = CreateFrame("Frame", nil, frame)
  wheel:SetPoint("TOPLEFT", prev, "TOPRIGHT", 0, 0)
  wheel:SetPoint("BOTTOMRIGHT", nxt, "BOTTOMLEFT", 0, 0)
  wheel:EnableMouse(true)
  wheel:EnableMouseWheel(true)
  wheel:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Mouse wheel: previous / next Torment", 1, 1, 1)
    GameTooltip:AddLine("Shift-click the arrows: Normal / highest unlocked", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  wheel:SetScript("OnLeave", function() GameTooltip:Hide() end)

  --------------------------------------------------------
  -- Ladder
  --------------------------------------------------------
  -- The rungs sit in their own sub-frame, under the stepper by default; a caller may
  -- re-anchor frame.ladder elsewhere (the Dungeon Finder hangs it from its bottom).
  local ladder = CreateFrame("Frame", nil, frame)
  ladder:SetSize(width, RUNG_H)
  ladder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, LADDER_Y)
  frame.ladder = ladder

  local rungCount = cfg.rungs + (cfg.cosmetic and 1 or 0)
  local rungW = (width - (rungCount - 1) * RUNG_GAP) / rungCount
  local rungs = {}
  for i = 1, rungCount do
    local btn = ProjectEbonhold.TormentWidgets.CreateRungButton(ladder, rungW, RUNG_H)
    btn:SetPoint("TOPLEFT", ladder, "TOPLEFT", (i - 1) * (rungW + RUNG_GAP), 0)
    btn:SetNormalFontObject(GameFontNormalSmall)
    btn:SetHighlightFontObject(GameFontHighlightSmall)
    btn:SetDisabledFontObject(GameFontDisableSmall)
    btn.isCosmetic = cfg.cosmetic and i > cfg.rungs
    btn.tier = btn.isCosmetic and (cfg.rungs + 1) or i

    btn.lock = btn:CreateTexture(nil, "OVERLAY")
    btn.lock:SetSize(12, 12)
    btn.lock:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    btn.lock:SetTexture(TEX_LOCK)
    btn.lock:Hide()

    -- The tier in force wears a solid green frame: the old gold glow melted into the gold
    -- bevel of the rungs and could not be told apart from the viewed rung.
    btn.glow = CreateFrame("Frame", nil, btn)
    btn.glow:SetPoint("TOPLEFT", btn, "TOPLEFT", -CURRENT_PAD, CURRENT_PAD)
    btn.glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", CURRENT_PAD, -CURRENT_PAD)
    btn.glow:SetFrameLevel(btn:GetFrameLevel() + 2)
    local edges = {
      { "TOPLEFT", "TOPRIGHT", nil, CURRENT_EDGE },
      { "BOTTOMLEFT", "BOTTOMRIGHT", nil, CURRENT_EDGE },
      { "TOPLEFT", "BOTTOMLEFT", CURRENT_EDGE, nil },
      { "TOPRIGHT", "BOTTOMRIGHT", CURRENT_EDGE, nil },
    }
    for _, e in ipairs(edges) do
      local t = btn.glow:CreateTexture(nil, "OVERLAY")
      t:SetTexture(CURRENT_R, CURRENT_G, CURRENT_B, 1)
      t:SetPoint(e[1], btn.glow, e[1], 0, 0)
      t:SetPoint(e[2], btn.glow, e[2], 0, 0)
      if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
    end
    btn.glow:Hide()

    rungs[i] = btn
  end
  frame.rungs = rungs

  --------------------------------------------------------
  -- Redraw
  --------------------------------------------------------
  local function RungTier(btn)
    if btn.isCosmetic then
      return frame.value > cfg.rungs and frame.value or (cfg.rungs + 1)
    end
    return btn.tier
  end

  function frame:Redraw()
    local tier = self.value
    local r, g, b = cfg.GetColor(tier)
    name:SetTextColor(r, g, b)
    name:SetText(cfg.GetName(tier))
    local canStep = (not cfg.CanStep) or cfg.CanStep()
    prev:SetEnabledLook(canStep and tier > 1)
    nxt:SetEnabledLook(canStep and tier < cfg.GetMax())

    local current = cfg.GetCurrent and cfg.GetCurrent() or nil
    for _, btn in ipairs(rungs) do
      local rungTier = RungTier(btn)
      local viewed, locked, isCurrent
      if btn.isCosmetic then
        viewed    = tier > cfg.rungs
        isCurrent = current and current > cfg.rungs
        locked    = viewed and cfg.IsLocked(tier)
        local short = viewed and TS.ShortName(tier) or "XI+"
        local tiny = #short > 3
        btn:SetNormalFontObject(tiny and TinyFont("normal") or GameFontNormalSmall)
        btn:SetHighlightFontObject(tiny and TinyFont("highlight") or GameFontHighlightSmall)
        btn:SetDisabledFontObject(tiny and TinyFont("disable") or GameFontDisableSmall)
        btn:SetText(short)
      else
        viewed    = tier == rungTier
        isCurrent = current == rungTier
        locked    = cfg.IsLocked(rungTier)
        btn:SetText(TS.ShortName(rungTier))
      end

      -- Reset to the resting look first, then override it: a font object sticks to the button
      -- until the next set, so a rung browsed once used to keep the white highlight for good.
      local tinyRung = btn.isCosmetic and #btn:GetText() > 3
      btn:SetRestingFace("Up")
      btn:SetNormalFontObject(tinyRung and TinyFont("normal") or GameFontNormalSmall)
      btn.lock:Hide()

      if locked then
        btn:SetRestingFace(viewed and "Down" or "Disabled")
        btn:SetNormalFontObject(tinyRung and TinyFont("disable") or GameFontDisableSmall)
        btn.lock:Show()
      elseif viewed then
        btn:SetRestingFace("Down")
        btn:SetNormalFontObject(tinyRung and TinyFont("highlight") or GameFontHighlightSmall)
      end
      -- A font-object swap only takes on the next text set.
      btn:SetText(btn:GetText())
      if isCurrent then btn.glow:Show() else btn.glow:Hide() end
    end
  end

  function frame:SetValue(tier)
    tier = math.floor((tonumber(tier) or 1) + 0.5)
    self.value = math.max(1, math.min(cfg.GetMax(), tier))
    self:Redraw()
  end

  function frame:GetValue()
    return self.value
  end

  --------------------------------------------------------
  -- Input
  --------------------------------------------------------
  local function Pick(tier)
    tier = math.max(1, math.min(cfg.GetMax(), tier))
    cfg.OnSelect(tier)
  end

  prev:SetScript("OnClick", function() Pick(IsShiftKeyDown() and 1 or frame.value - 1) end)
  nxt:SetScript("OnClick", function()
    Pick(IsShiftKeyDown() and ((cfg.ShiftMax and cfg.ShiftMax()) or cfg.GetMax()) or frame.value + 1)
  end)
  wheel:SetScript("OnMouseWheel", function(_, delta) Pick(frame.value + (delta > 0 and 1 or -1)) end)

  for _, btn in ipairs(rungs) do
    btn:SetScript("OnClick", function(self) Pick(RungTier(self)) end)
    btn:SetScript("OnEnter", function(self)
      if cfg.OnRungEnter then cfg.OnRungEnter(self, RungTier(self)) end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  frame:SetScript("OnShow", function(self) self:Redraw() end)
  return frame
end
