local addonName, addon = ...
local L, T = ProjectEbonhold.L, ProjectEbonhold.T

------------------------------------------------------------
-- ORB OF LOST MEMORIES
------------------------------------------------------------
-- A charge that forgets ONE stack of an Echo you own and offers a fresh Echo choice in its
-- place. Flow:
--   bubble on the echo panel -> click -> mauve alert arms a selection -> click one of your
--   echoes -> the server removes a stack, spends the charge and pushes the usual Echo choice.
--
-- Nothing here decides anything. The charge count, "do you own this echo", "is it locked" and
-- the replacement roll all live server-side (PerksHandler::ConsumeOrbOnPerk); the addon sends
-- one spell id and renders whatever comes back. Locked/permanent echoes are not even in this
-- grid - they have their own slot row - and the server refuses them regardless.
--
-- A spend can also carry EXTRA orbs: one stack is forgotten whatever the count, and each orb
-- adds a point of chance at the BEST quality the draw pool holds - 100 orbs make it certain.
-- Nothing is fetched to display that: the bonus is additive, so the count IS the number, and
-- PerksHandler::ApplyOrbQualityBoost adds the same points when it rolls.
--
-- Protocol:
--   CS.REQUEST_ORB_CHARGES         (1220)  body: ""
--   CS.REQUEST_ORB_CONSUME         (1221)  body: "<orbCount>|<perkSpellId>[,<perkSpellId>...]"
--   CS.REQUEST_ORB_REROLL          (1222)  body: "<orbCount>" (empty = 1)
--   CS.REQUEST_ORB_UPGRADE         (1223)  body: "<perkSpellId>" - one stack to its next quality
--   SS.SEND_ORB_CHARGES            (1220)  body: "<charges>,<appliedDelta>,<pendingOffers>"

ProjectEbonhold = ProjectEbonhold or {}

local OrbService = {}
ProjectEbonhold.OrbService = OrbService

local ORB_ICON = "Interface\\Icons\\inv_112_arcane_orb"
local BUBBLE_SIZE = 30
-- Display only. The real ceiling is PerksHandler::ORB_MAX_CHARGES, enforced server-side in
-- ModifyOrbCharges; the two must be retuned together.
local MAX_CHARGES = 5000

-- nil until the server answers. 0 and "unknown" must stay distinguishable: the bubble is
-- hidden in both cases, but only a known 0 may disarm a selection.
local charges = nil
local armed = false
-- How many Orb replacements are still owed. A COUNT, not a flag: spending an orb while a
-- choice is already on the table queues an extra draw instead of replacing that choice, so two
-- orbs in a row owe two protected draws. A boolean was cleared by the first pick and left the
-- second draw showing reroll/banish/freeze - which the server then genuinely accepted.
-- The server is authoritative (third field of SEND_ORB_CHARGES); the local bump in ConfirmSpend
-- is optimistic and gets corrected by the next push, including when a consume is refused.
local pendingOffers = 0

-- Right-click batch: echoes queued to be forgotten together, one orb each. Left-click stays
-- the one-shot path, so the common case costs no extra step. Keyed by spell id; `markedOrder`
-- keeps the click order so the batch is spent in the order the player built it.
local marked = {}
local markedOrder = {}

local bubble = nil
local alert = nil

------------------------------------------------------------
-- ACCESSORS
------------------------------------------------------------

function OrbService.GetCharges()
  return charges or 0
end

function OrbService.IsStateKnown()
  return charges ~= nil
end

--- True while the player is picking which Echo to forget. Read by the echo grid's OnClick.
function OrbService.IsArmed()
  return armed == true
end

--- True if @p perkSpellId is queued in the right-click batch. Read by the grid for its marker.
function OrbService.IsMarked(perkSpellId)
  return marked[perkSpellId] == true
end

function OrbService.GetMarkedCount()
  return #markedOrder
end

--- Adds or removes an echo from the batch. Returns true if it is now marked.
function OrbService.ToggleMark(perkSpellId)
  if not perkSpellId then return false end

  if marked[perkSpellId] then
    marked[perkSpellId] = nil
    for i, id in ipairs(markedOrder) do
      if id == perkSpellId then table.remove(markedOrder, i) break end
    end
  else
    -- One orb per marked echo, so the batch can never exceed what the player holds.
    if #markedOrder >= (charges or 0) then
      UIErrorsFrame:AddMessage(T("You only have {count} Orb(s) of Lost Memories.", { count = charges or 0 }), 1, 0.1, 0.1)
      return false
    end
    marked[perkSpellId] = true
    table.insert(markedOrder, perkSpellId)
  end

  OrbService.RefreshAlert()
  return marked[perkSpellId] == true
end

function OrbService.ClearMarks()
  if #markedOrder == 0 then return end
  marked = {}
  markedOrder = {}
  OrbService.RefreshAlert()
end

--- True while at least one Orb offer is awaiting its pick. Read by the echo choice UI to
--- disable reroll, banish and freeze, mirroring what the server enforces.
function OrbService.IsOfferPending()
  return (pendingOffers or 0) > 0
end

--- Called when the player picks an echo: settles ONE owed offer, not all of them.
function OrbService.ClearOffer()
  pendingOffers = (pendingOffers or 0) - 1
  if pendingOffers < 0 then pendingOffers = 0 end
end

------------------------------------------------------------
-- CLIENT -> SERVER
------------------------------------------------------------

function OrbService.RequestCharges()
  ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ORB_CHARGES, "")
end

--- True when the offer on the table is one an orb paid for AND another orb is in hand: the two
--- conditions the Echo choice's Reroll button turns into "spend one more" instead of hiding
--- itself. The server re-checks both (PerksHandler::OnOrbRerollRequested); this is only what the
--- button reads to paint itself.
function OrbService.CanRerollOffer()
  return OrbService.IsOfferPending() and (charges or 0) > 0
end

-- Orbs spent on EACH reroll click of an orb offer, set by the player (the small button next to
-- Reroll). Above one orb, each orb adds one point of chance at the best quality, exactly like
-- the forget dialog's slider (PerksHandler::OnOrbRerollRequested -> ApplyOrbQualityBoost), so a
-- boosted session no longer drops back to plain 1-orb redraws after its first draw. Saved
-- account-wide; the server clamps it to [1, ORB_BOOST_MAX_ORBS] and to what the player holds.
local REROLL_SPEND_MAX = 100 -- = ORB_BOOST_MAX_ORBS, declared below for the spend dialog

local function ClampRerollSpend(n)
  n = math.floor(tonumber(n) or 1)
  if n < 1 then n = 1 end
  if n > REROLL_SPEND_MAX then n = REROLL_SPEND_MAX end
  return n
end

function OrbService.GetRerollSpend()
  local db = ProjectEbonholdDB
  return ClampRerollSpend(db and db.orbRerollSpend or 1)
end

function OrbService.SetRerollSpend(n)
  ProjectEbonholdDB = ProjectEbonholdDB or {}
  ProjectEbonholdDB.orbRerollSpend = ClampRerollSpend(n)
  if OrbService.refreshSpendPopup then OrbService.refreshSpendPopup() end
  if OrbService.onRerollSpendChanged then OrbService.onRerollSpendChanged() end
end

--- What the next reroll click actually costs: the setting, cut to what is held (never below 1).
--- Cutting rather than refusing keeps the one-click promise when the stock runs low.
function OrbService.GetEffectiveRerollSpend()
  local n = OrbService.GetRerollSpend()
  local held = charges or 0
  if held < n then n = held end
  if n < 1 then n = 1 end
  return n
end

--- Spends the player's per-reroll orb count to redraw the offer on the table. Nothing is
--- forgotten and nothing extra is owed - the stack is already gone and the draw is already owed,
--- this only re-rolls what it produced - so `pendingOffers` is deliberately left alone and the
--- redraw stays orb-final.
---
--- No confirmation popup: the whole point is that a player who likes none of the three can say so
--- in one click. The button carries the cost in its own label instead.
function OrbService.RerollOffer()
  if not OrbService.CanRerollOffer() then return end

  local spend = OrbService.GetEffectiveRerollSpend()

  if ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.MarkOrbReroll then
    ProjectEbonhold.PerkService.MarkOrbReroll()
  end
  ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ORB_REROLL, tostring(spend))

  -- Optimistic, same reason as SendSpend: the count is only ever written from SEND_ORB_CHARGES,
  -- and until that push lands the button would keep offering a charge that is already gone.
  if charges then
    charges = math.max(0, charges - spend)
    OrbService.EnsureUI()
  end

  -- Then ask for the truth. The spend answers with a charge push of its own, but a request the
  -- server DROPPED answers with nothing at all: Comms.ThrottleRules holds 1222 to one spend per
  -- 100ms and discards the rest silently, which would leave the optimistic decrement above
  -- standing on a charge that was never taken. This request is not throttled.
  OrbService.RequestCharges()
end

-- Confirmation before the charge is spent. Forgetting an echo is destructive and the orb is
-- consumed either way, so a misclick on a 32px icon must not be enough to trigger it.
-- Every rarity of an echo shares one spell NAME, so the confirmation has to spell out which copy
-- is about to go: "Rend the Weak" alone reads the same whether it takes the common or the rare.
-- Hexes mirror echo_journal's qualityColors.
local QUALITY_LABELS = {
  [0] = L["|cffFFFFFFCommon|r"],
  [1] = L["|cff1AFF1AUncommon|r"],
  [2] = L["|cff0066FFRare|r"],
  [3] = L["|cffCC66FFEpic|r"],
  [4] = L["|cffFF8000Legendary|r"],
}

local function QualityLabel(perkSpellId)
  local db = ProjectEbonhold.PerkDatabase
  local data = db and db[perkSpellId]
  return (data and QUALITY_LABELS[data.quality or 0]) or L["this rarity"]
end

------------------------------------------------------------
-- UPGRADE (one stack to its next quality)
------------------------------------------------------------
-- Every quality of an echo is its own spell, tied to the others by groupId. Only the stat echoes
-- exist in Common / Uncommon / Rare; class echoes and Epics have one quality and no upgrade.
-- Prices keyed by the TARGET quality; they mirror PerksHandler::ORB_UPGRADE_COST_TO_*.
local UPGRADE_COST = { [1] = 250, [2] = 500 }

--- The next-quality version of @p perkSpellId usable by this character, or nil.
local function GetUpgradeTarget(perkSpellId)
  local db = ProjectEbonhold.PerkDatabase
  local data = db and db[perkSpellId]
  if not data or not data.groupId then return nil end
  local quality = data.quality or 0
  if quality >= 2 then return nil end -- Rare is the top of a stat echo

  local playerClassMask = 2 ^ ((select(3, UnitClass("player")) or 1) - 1)
  local level = UnitLevel("player") or 1
  for spellId, other in pairs(db) do
    if other.groupId == data.groupId and (other.quality or 0) == quality + 1 then
      local mask = other.classMask or 0
      if bit.band(mask, playerClassMask) ~= 0 and level >= (other.minLevel or 1) then
        return spellId, other
      end
    end
  end
  return nil
end

--- Stacks of @p spellId the character holds this run, and whether it is a locked (permanent) one.
local function HeldStacks(spellId)
  local perks = addon and addon.Perks
  if not perks then return 0, false end
  for _, entry in ipairs(perks.lockedPerks or {}) do
    if entry.spellId == spellId then return entry.stack or 0, true end
  end
  local n = 0
  for _, list in pairs(perks.grantedPerks or {}) do
    for _, entry in ipairs(list) do
      if entry.spellId == spellId then n = n + (entry.stack or 1) end
    end
  end
  return n, false
end

StaticPopupDialogs["EBONHOLD_ORB_CONFIRM_MULTI"] = {
  text = L["Forget one stack of |cffFFD100%d Echoes|r?\n\nEach one is removed and a new Echo choice is offered in its place. You can banish or freeze its cards; your run's reroll does not apply, one more Orb redraws them.\n\nThis spends |cffFFD100%d Orbs of Lost Memories|r."],
  button1 = YES or L["Yes"],
  button2 = NO or L["No"],
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  preferredIndex = 3,
  OnAccept = function() OrbService.ConfirmSpendMarked() end,
}

------------------------------------------------------------
-- SPEND DIALOG
------------------------------------------------------------
-- One echo, as many orbs as the player cares to put on it. ONE STACK is forgotten whatever the
-- count; each orb ADDS a point of chance at the best quality the pool holds - Epic where the
-- player has Epics in reach, Rare where they do not, which is why the copy says "higher quality"
-- rather than naming a tier. 20 orbs are +20%, and at 100 the total clears certainty.
--
-- Nothing is fetched to show that: the bonus is additive, so the count IS the number to print
-- and the dialog needs to know nothing about the player's draw pool. The server adds the same
-- points when it rolls (PerksHandler::ApplyOrbQualityBoost), so the two can only drift if
-- ORB_BOOST_MAX_ORBS is changed on one side - the single thing to keep in step here.
local ORB_BOOST_MAX_ORBS = 100

local spendDialog = nil

--- True while an Echo choice is already on the table. The server refuses a multi-orb spend in
--- that state (the bonus applies to a draw made right now, and the generation queue has
--- nowhere to carry it), so the slider is held at one orb rather than letting the player build a
--- bounces straight back.
local function IsChoiceOnTable()
  if OrbService.IsOfferPending() then return true end
  return (addon and addon.Perks and addon.Perks.currentChoice) ~= nil
end

local function MaxSpendableOrbs()
  if IsChoiceOnTable() then return 1 end

  local ceiling = ORB_BOOST_MAX_ORBS
  local held = charges or 0
  if held < ceiling then ceiling = held end
  if ceiling < 1 then ceiling = 1 end
  return ceiling
end

local ICON_SIZE, ICON_GAP = 32, 10

--- Centres the icon+name pair as ONE block. Anchoring the icon to the left edge left the row
--- hanging off-centre under a centred title and a centred slider; anchoring the text to the
--- frame centre instead would swing the icon around as names change length. Measuring the text
--- and offsetting the pair by half its total width keeps the whole dialog on one axis.
--- Call after SetText: GetStringWidth reads the CURRENT string.
local function LayoutHeader(f)
  local total = ICON_SIZE + ICON_GAP + (f.echoName:GetStringWidth() or 0)
  f.icon:ClearAllPoints()
  f.icon:SetPoint("TOPLEFT", f, "TOP", -total / 2, -44)
end

local function RefreshSpendDialog()
  if not spendDialog or not spendDialog:IsShown() then return end

  local orbCount = spendDialog.orbCount or 1
  local held = charges or 0

  -- One point per orb, added to the pool's own rate for the BEST quality it holds - not Epic
  -- specifically, which is why the wording is "higher quality": on a pool that tops out at Rare
  -- the orbs promote Rare. The count IS the bonus, so nothing is computed and nothing is fetched.
  if IsChoiceOnTable() then
    spendDialog.effect:SetText(L["|cffFF8080Claim your current Echo choice first to spend more.|r"])
  elseif orbCount >= ORB_BOOST_MAX_ORBS then
    spendDialog.effect:SetText(L["|cffCC66FFGuaranteed higher quality|r"])
  else
    spendDialog.effect:SetText(T("Chance of a higher quality |cffCC66FF+{bonus}%|r", { bonus = orbCount }))
  end

  spendDialog.costText:SetText(T("Leaves you |cffFFD100{count}|r", { count = math.max(0, held - orbCount) }))
end

-- Repaints a plate for its state: dim at rest, bright and lifted under the mouse, grey disabled.
local function PaintOrbPlate(btn, hot)
  local c = btn._plateColor
  if not btn:IsEnabled() then
    btn._plateStock:SetVertexColor(0.30, 0.30, 0.30)
    btn._plateRim:SetVertexColor(0.42, 0.42, 0.42, 0.8)
    btn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
    return
  end
  local k, w = hot and 1 or 0.72, hot and 0.45 or 0.25
  btn._plateStock:SetVertexColor(c[1] * k, c[2] * k, c[3] * k)
  -- The rim is the colour pulled towards white, or it melts into the stone
  btn._plateRim:SetVertexColor(c[1] + (1 - c[1]) * w, c[2] + (1 - c[2]) * w, c[3] + (1 - c[3]) * w, hot and 1 or 0.85)
  btn:GetFontString():SetTextColor(1, 1, 1)
end

-- A UIPanelButtonTemplate button dressed as an echo plate (same art as perks.lua MakePlate).
local function DressOrbPlate(btn, color, height)
  for _, t in ipairs({ btn:GetNormalTexture(), btn:GetPushedTexture(),
                       btn:GetHighlightTexture(), btn:GetDisabledTexture() }) do
    if t then t:Hide(); t:SetTexture(nil) end
  end
  btn:SetHeight(height)
  local ART = "Interface\\AddOns\\ProjectEbonhold\\assets\\echo_plate_"
  local stock = btn:CreateTexture(nil, "BORDER")
  stock:SetTexture(ART .. "stock")
  stock:SetAllPoints(btn)
  local rim = btn:CreateTexture(nil, "ARTWORK")
  rim:SetTexture(ART .. "rim")
  rim:SetAllPoints(btn)
  btn._plateStock, btn._plateRim, btn._plateColor = stock, rim, color
  local fs = btn:GetFontString()
  fs:SetFont("Fonts\\FRIZQT__.TTF", 11)
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
  btn:HookScript("OnEnter", function(self) PaintOrbPlate(self, true) end)
  btn:HookScript("OnLeave", function(self) PaintOrbPlate(self, false) end)
  hooksecurefunc(btn, "Enable", function(self) PaintOrbPlate(self, GetMouseFocus() == self) end)
  hooksecurefunc(btn, "Disable", function(self) PaintOrbPlate(self, false) end)
  PaintOrbPlate(btn, false)
end

local function CreateSpendDialog()
  if spendDialog then return spendDialog end

  local f = CreateFrame("Frame", "ProjectEbonholdOrbSpendDialog", UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:SetSize(340, 200)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)

  -- Dressed like an echo card, in the orb's mauve: the card's dark stone with cut corners and its
  -- frame (assets/echo_dialog_*, tools/perks/gen_echo_card_art.py panel()), a soft glow behind.
  -- Opaque textures the addon owns and no backdrop: the journal grid sits right behind and a UI
  -- skin (ElvUI) restyles backdrops it recognises into translucent ones.
  local ART = "Interface\\AddOns\\ProjectEbonhold\\assets\\"
  local glow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
  glow:SetBlendMode("ADD")
  glow:SetPoint("TOPLEFT", f, "TOPLEFT", -45, 40)
  glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 45, -40)
  glow:SetVertexColor(0.58, 0.28, 0.92, 0.35)
  local stock = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  stock:SetTexture(ART .. "echo_dialog_stock")
  stock:SetAllPoints(f)
  local rim = f:CreateTexture(nil, "BORDER")
  rim:SetTexture(ART .. "echo_dialog_rim")
  rim:SetAllPoints(f)
  rim:SetVertexColor(0.72, 0.36, 1, 1)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -18)
  title:SetText(L["Orb of Lost Memories"])

  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  f.icon = icon

  -- Name and rarity on ONE line: they name the same thing, and every rarity of an echo shares
  -- the spell name, so the rarity is what actually tells the player which copy goes. Left-aligned
  -- against the icon, but the PAIR is centred as a unit by LayoutHeader - no fixed width here,
  -- so the text hugs its content and the measurement below is the real one.
  local echoName = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  echoName:SetPoint("LEFT", icon, "RIGHT", ICON_GAP, 0)
  echoName:SetJustifyH("LEFT")
  f.echoName = echoName

  local slider = CreateFrame("Slider", "$parentOrbSlider", f, "OptionsSliderTemplate")
  slider:SetPoint("TOP", f, "TOP", 0, -100)
  slider:SetWidth(270)
  slider:SetMinMaxValues(1, 1)
  slider:SetValueStep(1)
  slider:SetValue(1)
  _G[slider:GetName() .. "Low"]:SetText("1")
  _G[slider:GetName() .. "Text"]:SetText("1 orb")
  f.slider = slider

  slider:SetScript("OnValueChanged", function(self, value)
    local orbCount = math.floor(value + 0.5)
    if orbCount < 1 then orbCount = 1 end
    f.orbCount = orbCount
    _G[self:GetName() .. "Text"]:SetText(orbCount .. (orbCount > 1 and " orbs" or " orb"))
    RefreshSpendDialog()
  end)

  local effect = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  effect:SetPoint("TOP", f, "TOP", 0, -128)
  effect:SetWidth(290)
  effect:SetJustifyH("CENTER")
  f.effect = effect

  local costText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  costText:SetPoint("TOP", effect, "BOTTOM", 0, -4)
  costText:SetJustifyH("CENTER")
  f.costText = costText

  local confirm = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  confirm:SetSize(120, 22)
  confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 18)
  confirm:SetText(L["Forget"])
  confirm:SetScript("OnClick", function()
    local perkSpellId, orbCount = f.perkSpellId, f.orbCount or 1
    f:Hide()
    OrbService.ConfirmSpend(perkSpellId, orbCount)
  end)

  local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  cancel:SetSize(120, 22)
  cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 18)
  cancel:SetText(CANCEL or L["Cancel"])
  cancel:SetScript("OnClick", function() f:Hide() end)

  -- Upgrade one stack to its next quality. Shown only on an echo that has one (stat echoes,
  -- Common and Uncommon); the dialog grows by one row for it.
  local upgrade = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  upgrade:SetSize(250, 22)
  upgrade:SetPoint("BOTTOM", f, "BOTTOM", 0, 46)
  if upgrade.SetMotionScriptsWhileDisabled then upgrade:SetMotionScriptsWhileDisabled(true) end
  upgrade:SetScript("OnClick", function()
    local perkSpellId = f.perkSpellId
    f:Hide()
    OrbService.ConfirmUpgrade(perkSpellId)
  end)
  upgrade:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Turns one stack of this Echo into one stack of its next quality. No new choice is offered."], 1, 1, 1, true)
    if self.reason then GameTooltip:AddLine(self.reason, 1, 0.5, 0.5, true) end
    GameTooltip:Show()
  end)
  upgrade:SetScript("OnLeave", function() GameTooltip:Hide() end)
  upgrade:Hide()
  f.upgrade = upgrade

  -- The red panel buttons become the echo screen's stone plates (assets/echo_plate_*, the art of
  -- the Reroll / Use Orbs button), Forget and Upgrade in the orb's mauve, Cancel in grey.
  local PLATE_MAUVE, PLATE_GREY = { 0.58, 0.28, 0.92 }, { 0.50, 0.47, 0.43 }
  DressOrbPlate(confirm, PLATE_MAUVE, 26)
  DressOrbPlate(cancel, PLATE_GREY, 26)
  DressOrbPlate(upgrade, PLATE_MAUVE, 26)
  upgrade:SetPoint("BOTTOM", f, "BOTTOM", 0, 50)

  spendDialog = f
  return f
end

--- Shows (or hides) the upgrade row of the spend dialog for @p perkSpellId.
local function RefreshUpgradeButton(f, perkSpellId)
  local targetId, target = GetUpgradeTarget(perkSpellId)
  local cost = target and UPGRADE_COST[target.quality or 0]
  if not targetId or not cost then
    f.upgrade:Hide()
    f:SetHeight(200)
    return
  end

  f:SetHeight(240)
  f.upgrade:SetText(T("Upgrade to {quality} - {cost} orbs", { quality = QUALITY_LABELS[target.quality], cost = cost }))
  local held, targetLocked = HeldStacks(targetId)
  local reason = nil
  if (charges or 0) < cost then
    reason = T("You need {cost} Orbs of Lost Memories.", { cost = cost })
  elseif targetLocked or (target.maxStack and target.maxStack > 0 and held >= target.maxStack) then
    reason = L["That version is already at its maximum stacks."]
  end
  f.upgrade.reason = reason
  if reason then f.upgrade:Disable() else f.upgrade:Enable() end
  f.upgrade:Show()
end

--- Spends the upgrade price to turn one stack of @p perkSpellId into its next quality. No draw
--- follows, so the journal stays open and the orb stays armed for the next one.
function OrbService.ConfirmUpgrade(perkSpellId)
  local _, target = GetUpgradeTarget(perkSpellId)
  local cost = target and UPGRADE_COST[target.quality or 0]
  if not cost then return end

  ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ORB_UPGRADE, tostring(perkSpellId))
  -- Optimistic, like a forget: the SEND_ORB_CHARGES push overwrites it, a refusal included.
  if charges then
    charges = math.max(0, charges - cost)
    OrbService.EnsureUI()
  end
  OrbService.RequestCharges()
end

--- Ask before spending: the actual send happens in ConfirmSpend.
function OrbService.SpendOn(perkSpellId)
  if not armed or not perkSpellId then return end

  local f = CreateSpendDialog()
  local name, _, icon = GetSpellInfo(perkSpellId)

  f.perkSpellId = perkSpellId
  f.orbCount = 1
  f.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  f.echoName:SetText(T("{name}  {quality}", { name = name or L["this Echo"], quality = QualityLabel(perkSpellId) }))
  LayoutHeader(f)

  local maxOrbs = MaxSpendableOrbs()
  f.slider:SetMinMaxValues(1, maxOrbs)
  _G[f.slider:GetName() .. "High"]:SetText(tostring(maxOrbs))
  if maxOrbs <= 1 then f.slider:Disable() else f.slider:Enable() end
  -- Set AFTER the range: a value outside the old range is clamped on the way in, and
  -- OnValueChanged is what paints the dialog, so this is also what fills it in.
  f.slider:SetValue(1)
  -- ...except when the slider was ALREADY at 1 (a reopen, or a one-orb ceiling): SetValue fires
  -- nothing when the value does not change, so the label would still read the last spend's count.
  _G[f.slider:GetName() .. "Text"]:SetText("1 orb")

  RefreshUpgradeButton(f, perkSpellId)
  f:Show()
  RefreshSpendDialog()
end

------------------------------------------------------------
-- PER-REROLL SPEND POPUP
------------------------------------------------------------
-- Opened by the small button next to Reroll on an orb offer. A slider and a number box set how
-- many orbs EACH reroll click spends (OrbService.SetRerollSpend); the change is saved at once,
-- there is no confirm button. Slider and box drive each other; `syncing` stops the echo.
local spendPopup = nil

local function RefreshSpendPopup()
  local f = spendPopup
  if not f then return end
  local n = OrbService.GetRerollSpend()
  f.syncing = true
  f.slider:SetValue(n)
  _G[f.slider:GetName() .. "Text"]:SetText(n .. (n > 1 and " orbs" or " orb"))
  if not f.box:HasFocus() then f.box:SetText(tostring(n)) end
  f.syncing = false
  if n >= ORB_BOOST_MAX_ORBS then
    f.effect:SetText(L["|cffCC66FFGuaranteed higher quality|r"])
  elseif n > 1 then
    f.effect:SetText(T("Chance of a higher quality |cffCC66FF+{bonus}%|r", { bonus = n }))
  else
    f.effect:SetText(L["No quality bonus"])
  end
end
OrbService.refreshSpendPopup = RefreshSpendPopup

local function CreateSpendPopup()
  if spendPopup then return spendPopup end

  local f = CreateFrame("Frame", "ProjectEbonholdOrbRerollSpendPopup", UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:SetSize(270, 112)
  -- Dressed like an echo card, in the orb's mauve: the card's dark stone with cut corners and
  -- its frame (assets/echo_panel_*, tools/perks/gen_echo_card_art.py panel()), a soft glow
  -- behind. Textures the addon owns, no backdrop, so a UI skin cannot restyle it.
  local ART = "Interface\\AddOns\\ProjectEbonhold\\assets\\"
  local glow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
  glow:SetBlendMode("ADD")
  glow:SetPoint("CENTER", f, "CENTER", 0, 0)
  glow:SetSize(270 + 90, 112 + 80)
  glow:SetVertexColor(0.58, 0.28, 0.92, 0.35)
  local stock = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  stock:SetTexture(ART .. "echo_panel_stock")
  stock:SetAllPoints(f)
  local rim = f:CreateTexture(nil, "BORDER")
  rim:SetTexture(ART .. "echo_panel_rim")
  rim:SetAllPoints(f)
  rim:SetVertexColor(0.72, 0.36, 1, 1)
  f:EnableMouse(true)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -14)
  title:SetShadowColor(0, 0, 0, 1)
  title:SetShadowOffset(1, -1)
  title:SetText(L["Orbs per reroll"])

  local slider = CreateFrame("Slider", "$parentSlider", f, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -46)
  slider:SetWidth(166)
  slider:SetMinMaxValues(1, ORB_BOOST_MAX_ORBS)
  slider:SetValueStep(1)
  _G[slider:GetName() .. "Low"]:SetText("1")
  _G[slider:GetName() .. "High"]:SetText(tostring(ORB_BOOST_MAX_ORBS))
  f.slider = slider
  slider:SetScript("OnValueChanged", function(_, value)
    if f.syncing then return end
    OrbService.SetRerollSpend(math.floor(value + 0.5))
  end)

  local box = CreateFrame("EditBox", "$parentBox", f, "InputBoxTemplate")
  box:SetSize(44, 20)
  box:SetPoint("LEFT", slider, "RIGHT", 16, 0)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(3)
  f.box = box
  local function commit(self)
    OrbService.SetRerollSpend(self:GetNumber())
    self:ClearFocus()
    RefreshSpendPopup()
  end
  box:SetScript("OnEnterPressed", commit)
  box:SetScript("OnEditFocusLost", function(self) OrbService.SetRerollSpend(self:GetNumber()); RefreshSpendPopup() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); RefreshSpendPopup() end)

  local effect = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  effect:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  effect:SetWidth(250)
  effect:SetJustifyH("CENTER")
  f.effect = effect

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetScale(0.8)
  -- Inside the frame's inner hairline, not over the rim
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

  spendPopup = f
  return f
end

--- Opens (or closes) the per-reroll spend popup above @p anchor.
function OrbService.ToggleRerollSpendPopup(anchor)
  local f = CreateSpendPopup()
  if f:IsShown() then f:Hide() return end
  f:ClearAllPoints()
  if anchor then
    f:SetPoint("BOTTOM", anchor, "TOP", 0, 10)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  end
  f:Show()
  RefreshSpendPopup()
end

function OrbService.HideRerollSpendPopup()
  if spendPopup then spendPopup:Hide() end
end

-- Sends one spend request. Covers both shapes the player can build: a single echo carrying any
-- number of orbs (left-click) and a batch of echoes carrying one each (right-click). The ids are
-- captured before Disarm, which clears the batch. Disarming immediately is deliberate: what
-- confirms the spend is the reply (a new charge count, a refreshed echo grid and an Echo choice),
-- not this call.
local function SendSpend(perkSpellIds, orbCount)
  if not perkSpellIds or #perkSpellIds == 0 then return end

  orbCount = math.floor(tonumber(orbCount) or 1)
  if orbCount < 1 then orbCount = 1 end
  -- A batch is one orb per entry by definition. The server forces this too; doing it here keeps
  -- the optimistic charge maths below honest rather than letting it undercount.
  if #perkSpellIds > 1 then orbCount = 1 end

  -- One replacement draw is owed per ECHO, never per orb: extra orbs bought Epic odds on that
  -- single draw, not more draws.
  local draws = #perkSpellIds
  local spent = draws * orbCount

  OrbService.Disarm()
  pendingOffers = (pendingOffers or 0) + draws
  ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ORB_CONSUME,
    tostring(orbCount) .. "|" .. table.concat(perkSpellIds, ","))

  -- Spend the charges locally right away. The count next to the bubble is only ever written
  -- from SEND_ORB_CHARGES, so until that push lands it kept advertising orbs that are already
  -- gone - and a player who batches again on that stale number is told they hold more than
  -- they do. The server's push overwrites this the moment it arrives, and the request below
  -- makes sure one arrives even on a build that only answers when asked.
  if charges then
    charges = math.max(0, charges - spent)
    OrbService.EnsureUI()
  end
  OrbService.RequestCharges()

  -- Get out of the way: the reply is an Echo choice, and the journal covers the whole screen.
  -- Leaving it open would put the draw behind it.
  OrbService.CloseJournal()
end

--- Spends @p orbCount orbs on a single echo (the left-click path). One stack is forgotten
--- whatever the count; each orb adds a point of chance at the best quality the pool holds.
function OrbService.ConfirmSpend(perkSpellId, orbCount)
  if not perkSpellId then return end
  SendSpend({ perkSpellId }, orbCount)
end

--- Spends the whole right-click batch, one orb per marked echo.
function OrbService.ConfirmSpendMarked()
  if #markedOrder == 0 then return end

  -- Copied: SendSpend disarms, and Disarm empties markedOrder.
  local ids = {}
  for i, id in ipairs(markedOrder) do ids[i] = id end
  SendSpend(ids, 1)
end

--- Ask before spending the batch.
function OrbService.SpendMarked()
  local count = #markedOrder
  if count == 0 then return end

  local dialog = StaticPopup_Show("EBONHOLD_ORB_CONFIRM_MULTI", count, count)
  if not dialog then
    DEFAULT_CHAT_FRAME:AddMessage(L["|cffFF0000[Orb]|r Close another dialog first."])
  end
end

--- Re-renders the echo grid so the batch markers follow the current selection.
function OrbService.RefreshGrid()
  if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.OnDataChanged then
    ProjectEbonhold.EchoJournal.OnDataChanged()
  end
end

--- Keeps the yellow alert in step with the batch: the confirm button only exists while there
--- is something to confirm, and it carries the count so the cost is never a surprise.
function OrbService.RefreshAlert()
  if not alert or not alert.confirm then return end

  local count = #markedOrder
  if count == 0 then
    alert.confirm:Hide()
    alert:SetHeight(alert.baseHeight or 110)
  else
    alert.confirm.text:SetText(T("Forget {count} Echo{es} ({count} orb{s})", { count = count, es = (count > 1 and "es" or ""), s = (count > 1 and "s" or "") }))
    alert.confirm:Show()
    -- Room for the button plus its own margin, below the text the base height already covers.
    alert:SetHeight((alert.baseHeight or 110) + 48)
  end
end

--- Closes whatever is currently showing the Echo Journal. It normally lives embedded in the
--- Collections window, so that shell is what has to be dismissed; the standalone frame is the
--- fallback for when it is opened on its own.
function OrbService.CloseJournal()
  if CollectionsJournal and CollectionsJournal:IsShown() then
    if HideUIPanel then
      HideUIPanel(CollectionsJournal)
    else
      CollectionsJournal:Hide()
    end
    return
  end

  local journal = _G["ProjectEbonholdEchoJournal"]
  if journal and journal:IsShown() then
    journal:Hide()
  end
end

------------------------------------------------------------
-- SELECTION MODE
------------------------------------------------------------

local function UpdateBubble()
  if not bubble then return end

  -- Always on screen, showing 0 when there is nothing to spend - including before the server
  -- has said anything, which is also the state on a server that predates the mechanic. Hiding
  -- it in that case made the feature look broken rather than empty, and a player who has never
  -- seen the bubble has no way to learn that orbs exist.
  local n = charges or 0

  bubble.count:SetText(tostring(n))
  bubble.icon:SetDesaturated(n <= 0)
  bubble:SetAlpha(n > 0 and 1 or 0.45)
  bubble:Show()
end

function OrbService.Disarm()
  armed = false
  -- The batch only exists while the orb is armed: leaving marks behind would silently re-arm
  -- a selection the player abandoned.
  marked = {}
  markedOrder = {}
  if alert then alert:Hide() end
  if bubble then bubble.glow:Hide() end
  OrbService.RefreshGrid()
end

function OrbService.Arm()
  if not charges or charges <= 0 then return end

  armed = true
  if bubble then bubble.glow:Show() end
  if alert then alert:Show() end

  -- Locking a permanent echo arms a pick on the SAME grid, driven by the same left-click.
  -- Two live modes would make that click ambiguous, so arming the orb ends lock mode - the
  -- mirror of what the permanent slot does to the orb.
  local journal = ProjectEbonhold.EchoJournal
  if journal and journal.CancelLockMode then journal.CancelLockMode() end
end

function OrbService.Toggle()
  if armed then OrbService.Disarm() else OrbService.Arm() end
end

------------------------------------------------------------
-- UI
------------------------------------------------------------

-- Parked immediately right of the LAST permanent echo slot, so it reads as part of that row
-- instead of floating over its first disc. The row is rebuilt (and resized) on every journal
-- refresh, hence re-anchoring rather than a fixed offset.
local function AnchorBubble()
  if not bubble then return end

  local journal = _G["ProjectEbonholdEchoJournal"]
  local lastSlot = ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.lastPermanentSlot

  bubble:ClearAllPoints()
  if lastSlot then
    bubble:SetPoint("LEFT", lastSlot, "RIGHT", 14, 0)
  elseif journal then
    -- Row not built yet: park it where the row starts, the next refresh moves it.
    bubble:SetPoint("TOPLEFT", journal, "TOPLEFT", 14, -46)
  end
end

local function CreateAlert(anchor)
  -- Deliberately narrow and short: the box hangs directly over the echo grid the player is
  -- being told to click, so every extra line covers the very discs it is pointing at.
  local ALERT_WIDTH = 300
  local TEXT_INSET = 18   -- left/right padding around the paragraph
  local TEXT_TOP = 18     -- gap between the box top and the first line

  local f = CreateFrame("Frame", "EbonholdOrbAlert", UIParent, "GlowBoxTemplate")
  f:SetWidth(ALERT_WIDTH)
  f:SetPoint("BOTTOM", anchor, "TOP", 0, 16)
  f:SetFrameStrata("DIALOG")
  f:SetFrameLevel(30)
  f:EnableMouse(true)
  f:Hide()

  local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
  text:SetJustifyV("TOP")
  -- Height 0 = "as tall as the wrapped text needs", which is what the box is measured from.
  text:SetSize(ALERT_WIDTH - TEXT_INSET * 2, 0)
  text:SetPoint("TOPLEFT", TEXT_INSET, -TEXT_TOP)
  -- Two paragraphs, both about the click that is about to happen. The "worth keeping for
  -- level 80" advice that used to close this box is teaching, and it belongs to the journal's
  -- guided tour: by the time this alert is up the orb is already armed, so advice on WHEN to
  -- spend arrives too late and only pushes the box down over the grid.
  text:SetText(
    L["|cffFFD100Orb of Lost Memories|r\n\n|cffFFD100Left-click|r an Echo to forget a stack, or |cffFFD100right-click|r several to forget them together, one Orb each.\n\nEach draws a new Echo choice. You can |cffFFD100banish|r or |cffFFD100freeze|r its cards; your |cffFF8080reroll|r does not apply, |cffFFD100another Orb|r redraws them."])

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 6, 6)
  close:SetScript("OnClick", function() OrbService.Disarm() end)

  -- Only shown once the right-click batch has something in it: with an empty selection there
  -- is nothing to confirm, and an always-present dead button reads as a broken one.
  local confirm = utils.CreateSimpleCustomButton(f, L["Forget"], nil, 200, 36)
  confirm:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  confirm:SetScript("OnClick", function() OrbService.SpendMarked() end)
  confirm:Hide()
  f.confirm = confirm

  -- Measured, not hard-coded: the copy has grown twice already and a fixed height simply
  -- clipped the last line off the bottom of the box.
  f.baseHeight = math.max(110, math.ceil(text:GetStringHeight()) + TEXT_TOP + 22)
  f:SetHeight(f.baseHeight)

  local arrow = CreateFrame("Frame", nil, f, "GlowBoxArrowTemplate")
  arrow:SetPoint("TOP", f, "BOTTOM", 0, 4)

  return f
end

local function CreateBubble()
  -- The Echo Journal is where the owned echoes are clicked, so that is where the counter goes.
  -- Its frame carries a global name, so nothing has to be exported for this.
  local parent = _G["ProjectEbonholdEchoJournal"]
  if bubble or not parent then return end

  local f = CreateFrame("Button", "EbonholdOrbBubble", parent)
  f:SetSize(BUBBLE_SIZE, BUBBLE_SIZE)
  f:SetFrameLevel(parent:GetFrameLevel() + 20)
  f:Hide()

  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetSize(BUBBLE_SIZE - 6, BUBBLE_SIZE - 6)
  icon:SetPoint("CENTER", f, "CENTER", 0, 0)
  SetPortraitToTexture(icon, ORB_ICON)
  f.icon = icon

  local border = f:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder")
  border:SetSize(BUBBLE_SIZE + 16, BUBBLE_SIZE + 16)
  border:SetPoint("CENTER", icon, "CENTER", 0, 0)

  -- Lit while a selection is armed, so it is obvious the next echo click will consume the orb
  -- rather than do nothing.
  local glow = f:CreateTexture(nil, "OVERLAY", nil, 1)
  glow:SetTexture("Interface\\Cooldown\\star4")
  glow:SetSize(BUBBLE_SIZE * 1.9, BUBBLE_SIZE * 1.9)
  glow:SetPoint("CENTER", icon, "CENTER", 0, 0)
  glow:SetBlendMode("ADD")
  -- Mauve, to match the arcane orb art: the yellow star read as a generic Blizzard
  -- highlight and did not tie back to the icon it sits under.
  glow:SetVertexColor(0.72, 0.36, 1, 0.95)
  glow:Hide()
  f.glow = glow

  local count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  -- Beside the orb rather than on it: the bar is only 20px high, a badge overlapping the
  -- icon at that size is unreadable.
  count:SetPoint("LEFT", f, "RIGHT", 3, 0)
  count:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
  count:SetTextColor(1, 0.85, 0.2)
  f.count = count

  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Orb of Lost Memories"], 1, 0.82, 0)
    -- Mirrors PerksHandler::ORB_MAX_CHARGES: the count is server-sent and already clamped,
    -- this only tells the player where the ceiling is before they bank into it.
    GameTooltip:AddDoubleLine(L["Orbs"], tostring(charges or 0) .. " / " .. tostring(MAX_CHARGES),
      0.9, 0.9, 0.9, 1, 0.85, 0.2)
    GameTooltip:AddLine(" ")
    -- Kept to one short sentence per idea, with no blank rows between them: the bubble is a
    -- 20px icon sitting over the echo bar, and a tall wide box hides the very echoes the
    -- player is about to pick from (and the journal's guided tour box beside it).
    GameTooltip:AddLine(L["Forget one stack of an Echo, and draw a new choice in its place."],
      1, 1, 1, true)
    -- Where to get more, in one line: the full list lives in the journal's guided tour.
    GameTooltip:AddLine(L["More from the |cffFFD100Hero's Call Board|r and the |cffFFD100Dungeon Finder|r."], 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine(" ")
    -- No "what these are worth at 80" paragraph here: that is teaching, and it belongs to the
    -- journal's guided tour (echo_journal's echoesTour, "Orb of Lost Memories" step), which the
    -- player reads once. A hover tooltip is for the state in front of them - what they hold, what
    -- it does, where more come from - and the advice pushed all of that down the box.
    -- At 0 the bubble is still on screen, so the tooltip has to say why clicking does nothing.
    if (charges or 0) <= 0 then
      GameTooltip:AddLine(L["You have no Orb to spend."], 1, 0.4, 0.4, true)
    elseif armed then
      GameTooltip:AddLine(L["Click an Echo below, or click again to cancel."], 0.1, 1, 0.1, true)
    else
      GameTooltip:AddLine(L["Click to choose an Echo to forget."], 0.1, 1, 0.1, true)
    end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f:SetScript("OnClick", function() OrbService.Toggle() end)

  -- The journal closing must not leave a selection armed behind it.
  parent:HookScript("OnHide", function() OrbService.Disarm() end)

  bubble = f
  alert = CreateAlert(f)
  AnchorBubble()
  UpdateBubble()
end

--- Builds the bubble once the echo panel exists. Safe to call repeatedly.
--- Called both from the charge packet and from the echo panel's own refresh, because on a
--- server without the Orb code the packet never arrives and the panel refresh is the only
--- thing that ever runs.
function OrbService.EnsureUI()
  CreateBubble()
  AnchorBubble()
  UpdateBubble()
end

------------------------------------------------------------
-- SERVER -> CLIENT
------------------------------------------------------------

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_ORB_CHARGES,
  function(body)
    if not body or body == "" then return end

    -- "<charges>,<appliedDelta>,<pendingOffers>". The delta is what the server actually applied
    -- after the 80-orb cap, so a grant that overflowed reports 0 and stays silent. Missing
    -- fields parse to nil: no alert, and the pending count is left untouched.
    local countStr, deltaStr, pendingStr = strsplit(",", body)
    charges = tonumber(countStr) or 0
    local gained = tonumber(deltaStr) or 0

    -- Server truth wins over the optimistic bump in ConfirmSpend: a consume the server refused
    -- (echo no longer owned, nothing rollable) resyncs to 0 here instead of leaving the three
    -- buttons hidden on a draw no orb ever paid for.
    if pendingStr then
      pendingOffers = tonumber(pendingStr) or 0
    end

    -- Repaint the choice screen's buttons on EVERY push, not only when the owed count moved: the
    -- Reroll button spends an orb while an offer is pending, so its label is the charge count and
    -- a push that only changed the count still leaves it stale.
    if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.RefreshBanishText then
      ProjectEbonhold.PerkUI.RefreshBanishText()
    end

    OrbService.EnsureUI()

    -- Yellow alert on the Echo Journal micro button, so a gain is visible with the journal
    -- closed - which is the normal case when the source is a quest turn-in or a prestige.
    if gained > 0 and ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.NotifyOrbsGained then
      ProjectEbonhold.EchoJournal.NotifyOrbsGained(gained)
    end

    -- Spending the last orb ends the selection: leaving it armed would swallow the next click
    -- on an echo for nothing.
    if charges <= 0 then
      OrbService.Disarm()
    end
  end
)

------------------------------------------------------------
-- DIAGNOSTIC
------------------------------------------------------------
-- /orbdebug answers the only question that matters when the bubble does not show up: which of
-- the three preconditions failed - the echo panel was never published, the bubble was never
-- built, or it was built somewhere off screen.

SLASH_EBONHOLDORBDEBUG1 = "/orbdebug"
SlashCmdList["EBONHOLDORBDEBUG"] = function()
  local p = DEFAULT_CHAT_FRAME
  local panel = _G["ProjectEbonholdEchoJournal"]

  p:AddMessage("|cffFFD100[Orb]|r charges = " .. tostring(charges) .. "  armed = " .. tostring(armed))
  p:AddMessage("|cffFFD100[Orb]|r EchoJournal = " .. tostring(panel))

  if panel then
    p:AddMessage("|cffFFD100[Orb]|r   panel shown = " .. tostring(panel:IsShown()) ..
      "  visible = " .. tostring(panel:IsVisible()) ..
      "  titleFrame = " .. tostring(panel.titleFrame))
  end

  p:AddMessage("|cffFFD100[Orb]|r bubble = " .. tostring(bubble))
  if bubble then
    local ok, left, bottom, w, h = pcall(function()
      return bubble:GetLeft(), bubble:GetBottom(), bubble:GetWidth(), bubble:GetHeight()
    end)
    p:AddMessage("|cffFFD100[Orb]|r   bubble shown = " .. tostring(bubble:IsShown()) ..
      "  visible = " .. tostring(bubble:IsVisible()) ..
      "  alpha = " .. tostring(bubble:GetAlpha()))
    p:AddMessage("|cffFFD100[Orb]|r   left = " .. tostring(bubble:GetLeft()) ..
      "  bottom = " .. tostring(bubble:GetBottom()) ..
      "  size = " .. tostring(bubble:GetWidth()) .. "x" .. tostring(bubble:GetHeight()) ..
      "  strata = " .. tostring(bubble:GetFrameStrata()))
  end

  -- Last resort: re-anchor to the screen centre so it can be seen at all. Confirms the frame
  -- exists and isolates the problem to the anchor rather than to the creation.
  p:AddMessage("|cffFFD100[Orb]|r type |cff00FF00/orbdebug center|r to park it mid-screen.")
end

SLASH_EBONHOLDORBDEBUG2 = "/orbcenter"
SlashCmdList["EBONHOLDORBDEBUG2"] = function()
  OrbService.EnsureUI()
  if not bubble then
    DEFAULT_CHAT_FRAME:AddMessage("|cffFF0000[Orb]|r no bubble: the echo panel was never published.")
    return
  end
  bubble:SetParent(UIParent)
  bubble:ClearAllPoints()
  bubble:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  bubble:SetFrameStrata("FULLSCREEN_DIALOG")
  bubble:Show()
  DEFAULT_CHAT_FRAME:AddMessage("|cffFFD100[Orb]|r bubble parked at screen centre.")
end

------------------------------------------------------------
-- STATE REQUEST ON LOGIN
------------------------------------------------------------
-- The server pushes the count on login; this covers /reload, which is not a login.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loginFrame:SetScript("OnEvent", function()
  OrbService.RequestCharges()
end)
