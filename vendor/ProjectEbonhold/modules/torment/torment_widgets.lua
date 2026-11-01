-- ==============================================================================
-- Building blocks shared by the Torment frame and the Dungeon Finder panel: the title
-- banner, the validate button, the ladder rung, a section header (gold title, grey context, a
-- thin gold rule fading at both ends), a character-sheet stat row (icon, white label, green
-- value, striped background, tooltip) and a reward row (36 px icon with its count, name
-- plate, grey note).
--
-- The validate buttons and the arrows are the client's own (UIPanelButtonTemplate,
-- UI-SpellbookIcon-*Page), so they follow whatever art pack is installed; the banner, the
-- ladder rungs, the reward plate and the glow are the addon's (assets/torment_*.tga, drawn
-- by tools/torment_assets.py from the mockup).
-- ==============================================================================
local W = {}
ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.TormentWidgets = W

local ART = "Interface\\AddOns\\ProjectEbonhold\\assets\\"
local FONT_SERIF = "Fonts\\FRIZQT__.TTF"

W.HEADER_H = 30      -- title line + rule
W.STAT_H   = 20
W.ITEM_H   = 38
W.BANNER_H = 32
W.ICON_INSET = { 0.07, 0.93, 0.07, 0.93 }

local C_GOLD     = { 1.0, 0.82, 0.0 }
local C_RULE     = { 0.72, 0.58, 0.25 }
local C_VALUE    = { 0.1, 1.0, 0.1 }
local C_INACTIVE = { 0.5, 0.5, 0.5 }

--- Title pill: dark gradient with gold / black / brown rings. banner.text is the label
--- (FRIZQT, gold by default); the caller recolours it per tier.
function W.CreateBanner(parent, width, fontSize)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(math.min(width, 256), W.BANNER_H)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  f.tex:SetTexture(ART .. "torment_banner")
  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetFont(FONT_SERIF, fontSize or 14)
  f.text:SetShadowColor(0, 0, 0, 1)
  f.text:SetShadowOffset(0, -1)
  f.text:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
  f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.text:SetWidth(f:GetWidth() - 32)
  f.text:SetJustifyH("CENTER")
  f.text:SetWordWrap(false)
  return f
end

--- The validate button (Apply, Accept, Cancel, Got it): the client's own
--- UIPanelButtonTemplate, so it is exactly the button of every other panel of this install.
function W.CreateBlizzardButton(parent, name, width, height, text)
  local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  btn:SetSize(width, height or 22)
  if text then btn:SetText(text) end
  return btn
end

--- Ladder rung: the addon's gold-bevelled face (torment_btn_*, 32 px with 3 px corners),
--- 3-sliced with 8 px ends so it reads the same at any width. The caller pins the face
--- ("Up", "Down" or "Disabled") through btn:SetRestingFace; the mouse only borrows the Down
--- face while pressed, and a locked rung keeps taking the mouse (tooltip, "look at it").
local SLICE = 8
local FACE_TEX = {
  Up       = ART .. "torment_btn_up",
  Down     = ART .. "torment_btn_down",
  Disabled = ART .. "torment_btn_disabled",
}

function W.CreateRungButton(parent, width, height)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(width, height or 22)
  local ends = math.min(SLICE, math.floor(width / 2))
  local l = btn:CreateTexture(nil, "BACKGROUND")
  l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(ends)
  l:SetTexCoord(0, 0.25, 0, 1)
  local r = btn:CreateTexture(nil, "BACKGROUND")
  r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); r:SetWidth(ends)
  r:SetTexCoord(0.75, 1, 0, 1)
  local m = btn:CreateTexture(nil, "BACKGROUND")
  m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  m:SetTexCoord(0.25, 0.75, 0, 1)
  btn.slices = { l, m, r }

  local hl = btn:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
  hl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 2)
  hl:SetTexture(1, 1, 1, 0.12)

  local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("CENTER", btn, "CENTER", 0, 1)
  btn:SetFontString(fs)
  btn:SetNormalFontObject(GameFontNormalSmall)
  btn:SetHighlightFontObject(GameFontHighlightSmall)
  btn:SetDisabledFontObject(GameFontDisableSmall)
  btn:SetPushedTextOffset(1, -1)

  local function Paint(face)
    local tex = FACE_TEX[face] or FACE_TEX.Up
    for _, t in ipairs(btn.slices) do t:SetTexture(tex) end
  end
  btn.restingFace = "Up"
  function btn:SetRestingFace(face)
    self.restingFace = face
    Paint(self:IsEnabled() and face or "Disabled")
  end
  btn:SetScript("OnMouseDown", function(self) if self:IsEnabled() then Paint("Down") end end)
  btn:SetScript("OnMouseUp", function(self) if self:IsEnabled() then Paint(self.restingFace) end end)
  btn:SetScript("OnEnable", function(self) Paint(self.restingFace) end)
  btn:SetScript("OnDisable", function() Paint("Disabled") end)
  Paint("Up")
  return btn
end

--- Gold title on the left, optional grey context on the right, a 1 px gold rule fading out
--- at both ends under them (two gradient textures, no art).
function W.CreateSectionHeader(parent, width, title, context)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, W.HEADER_H)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -2)
  f.title:SetText(title)
  f.context = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.context:SetPoint("BOTTOMRIGHT", f.title, "BOTTOMRIGHT", 0, 0)
  f.context:SetPoint("RIGHT", f, "RIGHT", -4, 0)
  f.context:SetJustifyH("RIGHT")
  f.context:SetText(context or "")
  local half = width / 2
  local left = f:CreateTexture(nil, "ARTWORK")
  left:SetSize(half, 1)
  left:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", -4, -5)
  left:SetTexture(1, 1, 1, 1)
  left:SetGradientAlpha("HORIZONTAL", C_RULE[1], C_RULE[2], C_RULE[3], 0, C_RULE[1], C_RULE[2], C_RULE[3], 1)
  local right = f:CreateTexture(nil, "ARTWORK")
  right:SetSize(half, 1)
  right:SetPoint("LEFT", left, "RIGHT", 0, 0)
  right:SetTexture(1, 1, 1, 1)
  right:SetGradientAlpha("HORIZONTAL", C_RULE[1], C_RULE[2], C_RULE[3], 1, C_RULE[1], C_RULE[2], C_RULE[3], 0)
  f.rule = { left, right }
  return f
end

--- One line of a stat block: icon, label (optional grey sub-label after it), value on the
--- right. row:SetActive(false) greys the icon and the value. row.tooltip(self) fills the
--- GameTooltip when set; the whole row is the hover target.
function W.CreateStatRow(parent, width, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(width, W.STAT_H)
  if index % 2 == 1 then
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(1, 1, 1, 0.05)
  end
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
  row.icon:SetTexCoord(unpack(W.ICON_INSET))
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.sub:SetPoint("LEFT", row.label, "RIGHT", 5, 0)
  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.value:SetJustifyH("RIGHT")

  function row:Set(icon, label, value, sub)
    self.icon:SetTexture(icon)
    self.label:SetText(label or "")
    self.sub:SetText(sub or "")
    self.value:SetText(value or "")
  end

  function row:SetActive(active)
    if active then
      self.icon:SetDesaturated(false)
      self.icon:SetAlpha(1)
      self.value:SetTextColor(C_VALUE[1], C_VALUE[2], C_VALUE[3])
    else
      self.icon:SetDesaturated(true)
      self.icon:SetAlpha(0.5)
      self.value:SetTextColor(C_INACTIVE[1], C_INACTIVE[2], C_INACTIVE[3])
    end
  end
  row:SetActive(true)

  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    if not self.tooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    self.tooltip(self)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:SetScale(1); GameTooltip:Hide() end)
  return row
end

--- A reward line: icon with the count in its corner, name plate with the item name and a
--- grey note on the right. row:SetClaimed(true) greys it out the way a daily already done
--- reads.
function W.CreateItemRow(parent, width)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(width, W.ITEM_H)

  local iconFrame = CreateFrame("Frame", nil, row)
  iconFrame:SetSize(36, 36)
  iconFrame:SetPoint("LEFT", row, "LEFT", 2, 0)
  local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
  iconBg:SetAllPoints()
  iconBg:SetTexture(0, 0, 0, 1)
  row.icon = iconFrame:CreateTexture(nil, "ARTWORK")
  row.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
  row.icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
  row.icon:SetTexCoord(unpack(W.ICON_INSET))
  row.count = iconFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  row.count:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -3, 3)
  row.count:SetJustifyH("RIGHT")
  row.iconFrame = iconFrame

  -- The plate tucks 4 px under the icon so the two read as one object.
  row.plate = row:CreateTexture(nil, "BORDER")
  row.plate:SetTexture(ART .. "torment_plate")
  row.plate:SetPoint("LEFT", iconFrame, "RIGHT", -4, 0)
  row.plate:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.plate:SetHeight(32)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.note:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  row.note:SetJustifyH("RIGHT")
  row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)

  function row:Set(icon, count, name, note)
    self.icon:SetTexture(icon)
    self.count:SetText(count and tostring(count) or "")
    self.name:SetText(name or "")
    self.note:SetText(note or "")
  end

  function row:SetClaimed(claimed)
    if claimed then
      self.icon:SetDesaturated(true)
      self.icon:SetAlpha(0.5)
      self.name:SetTextColor(0.5, 0.5, 0.5)
      self.count:SetTextColor(0.6, 0.6, 0.6)
    else
      self.icon:SetDesaturated(false)
      self.icon:SetAlpha(1)
      self.name:SetTextColor(1, 1, 1)
      self.count:SetTextColor(1, 1, 1)
    end
  end
  row:SetClaimed(false)

  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    if not self.tooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    self.tooltip(self)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end
