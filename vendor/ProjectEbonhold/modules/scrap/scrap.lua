local L, T = ProjectEbonhold.L, ProjectEbonhold.T
local Addon = select(2, ...)
local ScrapButton = CreateFrame("Button", "ProjectEbonholdScrapButton", MerchantFrame)
local function GetJunkValue()
  if ScrapService and ScrapService.GetSellableValue then
    return ScrapService.GetSellableValue()
  end
  return 0
end

local function SellJunk()
  if ScrapService and ScrapService.SellJunk then
    ScrapService.SellJunk()
  end
end

-- ── Config gear button + popup panel ─────────────────────────────────────────
local ConfigButton = CreateFrame("Button", "ProjectEbonholdScrapConfigButton", ScrapButton)
local ConfigPanel

local function CreateConfigPanel()
  local panel = CreateFrame("Frame", "ProjectEbonholdScrapConfigPanel", MerchantFrame)
  panel:SetSize(280, 292)
  panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", -34, -64)
  panel:SetFrameStrata("DIALOG")
  panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  panel:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
  panel:SetBackdropBorderColor(0.6, 0.55, 0.45, 1)
  panel:EnableMouse(true)
  panel:Hide()

  local function AddTooltip(widget, tipTitle, tipText)
    widget:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(tipTitle, 1, 1, 1)
      GameTooltip:AddLine(tipText, 0.85, 0.85, 0.85, true)
      GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  local function AddDivider(yOffset)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 12, yOffset)
    line:SetPoint("TOPRIGHT", -12, yOffset)
    line:SetTexture(1, 1, 1, 0.1)
  end

  local function AddSectionLabel(text, yOffset)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 14, yOffset)
    label:SetText(text)
    label:SetTextColor(1, 0.82, 0)
  end

  local function MakeCheck(name, label, x, y, settingKey, tipTitle, tipText)
    local cb = CreateFrame("CheckButton", "ProjectEbonholdScrap" .. name .. "Check", panel, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", x, y)
    local text = _G[cb:GetName() .. "Text"]
    text:SetFontObject(GameFontHighlightSmall)
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
      if ProjectEbonholdOptionsService then
        ProjectEbonholdOptionsService:SetSetting(settingKey, self:GetChecked() == 1)
      end
      ScrapButton:UpdateState()
    end)
    AddTooltip(cb, tipTitle, tipText)
    return cb
  end

  -- ── Header ──
  local headerIcon = panel:CreateTexture(nil, "ARTWORK")
  headerIcon:SetSize(16, 16)
  headerIcon:SetPoint("TOPLEFT", 12, -11)
  headerIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
  headerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("LEFT", headerIcon, "RIGHT", 6, 0)
  title:SetText(L["Junk Selling"])

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScale(0.8)
  close:SetScript("OnClick", function() panel:Hide() end)

  AddDivider(-34)

  -- ── Auto-sell ──
  local autoSell = MakeCheck("AutoSell", L["Auto-sell when visiting a merchant"], 12, -40, "autoSellJunk",
    "Auto-sell", L["Automatically sells everything matching your filters as soon as you open a merchant window."])
  panel.autoSell = autoSell

  AddDivider(-68)

  -- ── Qualities ──
  AddSectionLabel(L["Qualities"], -76)

  local QUALITIES = {
    { key = "sellQualityPoor",     label = L["|cff9d9d9dPoor|r"],
      tip = L["All poor quality (junk) items are sold, whatever their type."] },
    { key = "sellQualityCommon",   label = L["|cffffffffCommon|r"],
      tip = L["Common items are sold when their item type is also enabled."] },
    { key = "sellQualityUncommon", label = L["|cff1eff00Uncommon|r"],
      tip = L["Uncommon items are sold when their item type is also enabled."] },
    { key = "sellQualityRare",     label = L["|cff0070ddRare|r"],
      tip = L["Rare items are sold when their item type is also enabled."] },
  }
  panel.qualityChecks = {}
  for i, q in ipairs(QUALITIES) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    panel.qualityChecks[q.key] = MakeCheck("Quality" .. i, q.label,
      12 + col * 128, -90 - row * 22, q.key, T("Sell {label}", { label = q.label }), q.tip)
  end

  -- ── Item types ──
  AddSectionLabel(L["Item Types"], -140)

  local weapon, armor, _, consumable, glyph, tradeGoods, _, _, recipe, gem, misc = GetAuctionItemClasses()
  local ITEM_TYPES = {
    { key = "sellTypeWeapon",     label = weapon or L["Weapon"] },
    { key = "sellTypeArmor",      label = armor or L["Armor"] },
    { key = "sellTypeConsumable", label = consumable or L["Consumable"] },
    { key = "sellTypeTradeGoods", label = tradeGoods or L["Trade Goods"] },
    { key = "sellTypeRecipe",     label = recipe or L["Recipe"] },
    { key = "sellTypeGem",        label = gem or L["Gem"] },
    { key = "sellTypeGlyph",      label = glyph or L["Glyph"] },
    { key = "sellTypeMisc",       label = misc or L["Miscellaneous"] },
  }
  panel.typeChecks = {}
  for i, t in ipairs(ITEM_TYPES) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    panel.typeChecks[t.key] = MakeCheck("Type" .. i, t.label,
      12 + col * 128, -154 - row * 22, t.key, T("Sell {label}", { label = t.label }),
      L["Applies to Common, Uncommon and Rare items of this type."])
  end

  AddDivider(-248)

  -- ── Sell everything ──
  local sellAll = MakeCheck("SellAll", L["|cffff3333Sell EVERYTHING|r"], 12, -254, "sellEverything",
    L["|cffff3333Sell EVERYTHING|r"],
    L["Sells every sellable item in your bags, ignoring the quality and type filters. Legendary items and items protected with Alt-click are never sold."])
  sellAll:SetScript("OnClick", function(self)
    if self:GetChecked() == 1 then
      StaticPopupDialogs["PROJECTEBONHOLD_SELL_EVERYTHING"] = {
        text = L["|cffff2020Warning:|r this will sell EVERY sellable item in your bags, ignoring the quality and type filters. Only legendary items and items protected with Alt-click are kept.\n\nEnable anyway?"],
        button1 = YES,
        button2 = NO,
        OnAccept = function()
          if ProjectEbonholdOptionsService then
            ProjectEbonholdOptionsService:SetSetting("sellEverything", true)
          end
          ScrapButton:UpdateState()
        end,
        OnCancel = function()
          sellAll:SetChecked(false)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
      }
      StaticPopup_Show("PROJECTEBONHOLD_SELL_EVERYTHING")
    else
      if ProjectEbonholdOptionsService then
        ProjectEbonholdOptionsService:SetSetting("sellEverything", false)
      end
      ScrapButton:UpdateState()
    end
  end)
  panel.sellAll = sellAll

  panel.Refresh = function()
    local svc = ProjectEbonholdOptionsService
    if not svc then return end
    autoSell:SetChecked(svc:GetSetting("autoSellJunk"))
    for _, q in ipairs(QUALITIES) do
      panel.qualityChecks[q.key]:SetChecked(svc:GetSetting(q.key))
    end
    for _, t in ipairs(ITEM_TYPES) do
      panel.typeChecks[t.key]:SetChecked(svc:GetSetting(t.key))
    end
    sellAll:SetChecked(svc:GetSetting("sellEverything"))
  end

  panel:SetScript("OnShow", function() panel.Refresh() end)

  return panel
end

function ConfigButton:CreateButton()
  -- Small badge overlaid on the corner of the scrap button so the merchant
  -- button row never grows wider than it originally was.
  self:SetSize(14, 14)
  self:SetFrameStrata("HIGH")
  self:SetFrameLevel(ScrapButton:GetFrameLevel() + 2)
  self:SetPoint("TOPRIGHT", ScrapButton, "TOPRIGHT", 3, 3)

  local bg = self:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(0, 0, 0, 0.8)

  local icon = self:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", -1, 1)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  self:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  self:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

  self:RegisterForClicks("LeftButtonUp")
  self:SetScript("OnClick", function()
    if not ConfigPanel then
      ConfigPanel = CreateConfigPanel()
    end
    if ConfigPanel:IsShown() then
      ConfigPanel:Hide()
    else
      ConfigPanel:Show()
    end
  end)

  self:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Junk selling options"], 1, 1, 1)
    GameTooltip:AddLine(L["Configure auto-sell and selling rules."], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["|cFF888888Alt-click a bag item:|r protect it / always sell it"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  self:SetScript("OnLeave", function() GameTooltip:Hide() end)
end





function ScrapButton:CreateButton()
  self:SetSize(37, 37)
  self:SetFrameStrata("HIGH")
  
  
  local bg = self:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(27, 27)
  bg:SetPoint("CENTER", -0.5, -1.2)
  bg:SetTexture(0, 0, 0, 0.5)
  
  
  local icon = self:CreateTexture(nil, "ARTWORK")
  icon:SetSize(33, 33)
  icon:SetPoint("CENTER")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10_Green")
  self.icon = icon
  
  
  
  self:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  self:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  
  
  self:RegisterForClicks("LeftButtonUp")
  self:SetScript("OnClick", self.OnClick)
  self:SetScript("OnEnter", self.OnEnter)
  self:SetScript("OnLeave", self.OnLeave)
  
  
  self:UpdatePosition()
  
  
  hooksecurefunc("MerchantFrame_UpdateRepairButtons", function()
    self:UpdatePosition()
  end)
  
  
  hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function()
    self:UpdateState()
  end)
  
  hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
    self:UpdateState()
  end)
end

-- ── DragonUI's sell button runs our selling (owner, 2026-11-15) ─────────────
-- With DragonUI's merchant window, its "sell all junk" button replaces ours: our button stays
-- hidden (its frame still carries the events and the auto-sell), and DragonUI's runs our sale
-- (ScrapService rules: qualities, types, Alt-click protection; no confirmation popup), our
-- tooltip, our junk estimate on the icon, and carries the options gear. DragonUI places it
-- with its repair buttons (merchant_frame.lua), so ours no longer moves them.
local adopted

local function AdoptDragonButton()
  if adopted then return adopted end
  local dui = _G.DragonUI_MerchantSellAllJunkButton
  if not dui then return nil end
  adopted = dui

  dui:UnregisterAllEvents()
  dui:SetScript("OnEvent", nil)
  dui:RegisterForClicks("LeftButtonUp")
  dui:SetScript("OnClick", function(b, button)
    if button == "LeftButton" then
      GameTooltip:Hide()
      SellJunk()
      ScrapButton:UpdateState()
    end
  end)
  dui:SetScript("OnEnter", function(b) ScrapButton.OnEnter(b) end)
  dui:SetScript("OnLeave", function() GameTooltip:Hide() end)
  dui:SetScript("OnShow", function() ScrapButton.scanSoon:Show() end)

  ConfigButton:SetParent(dui)
  ConfigButton:ClearAllPoints()
  ConfigButton:SetPoint("TOPRIGHT", dui, "TOPRIGHT", 3, 3)
  ConfigButton:SetFrameLevel(dui:GetFrameLevel() + 2)

  ScrapButton:Hide()
  -- DragonUI may still have its own junk check queued for this frame: ours paints after it.
  C_Timer.After(0.05, function() ScrapButton.scanSoon:Show() end)
  return dui
end

function ScrapButton:UpdatePosition()
  if AdoptDragonButton() then return end
  self:ClearAllPoints()

  if CanMerchantRepair() then
    self:SetScale(1)

    -- Blizzard re-anchors MerchantRepairAllButton on every
    -- MerchantFrame_UpdateRepairButtons call — (115, 89) with guild repair,
    -- (172, 91) without — and the other repair buttons hang off it. This runs
    -- right after that, shifting the whole repair row right so the full-size
    -- scrap button fits at its left, starting at x=24 like the item column.
    if CanGuildBankRepair() then
      MerchantRepairAllButton:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMLEFT", 139, 89)
    else
      MerchantRepairAllButton:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMLEFT", 137, 91)
    end

    self:SetPoint("RIGHT", MerchantRepairItemButton, "LEFT", -2, 0)
  else
    self:SetPoint("RIGHT", MerchantBuyBackItemItemButton, "LEFT", -17, 0.5)
    self:SetScale(1.1)
  end
end

function ScrapButton:UpdateState()
  
  if MerchantFrame.selectedTab == 2 then
    self:Hide()
    if ConfigPanel then
      ConfigPanel:Hide()
    end
    return
  elseif not AdoptDragonButton() then
    self:Show()
  end

  -- The bag scan waits for the next frame: a sale raises BAG_UPDATE once per bag
  -- plus the two merchant hooks, each of which used to rescan every bag.
  self.scanSoon:Show()
end

function ScrapButton:RefreshJunkIcon()
  local value = GetJunkValue()
  local hasJunk = value > 0

  -- The server decides what actually sells, so the button stays clickable
  -- even when the client-side estimate is empty; the icon only hints at it.
  local button = adopted or self
  local icon = adopted and adopted.Icon or self.icon
  icon:SetDesaturated(not hasJunk)
  icon:SetAlpha(hasJunk and 1 or 0.5)
  button:Enable()
end

ScrapButton.scanSoon = CreateFrame("Frame")
ScrapButton.scanSoon:Hide()
ScrapButton.scanSoon:SetScript("OnUpdate", function(self)
  self:Hide()
  if (adopted or ScrapButton):IsVisible() then ScrapButton:RefreshJunkIcon() end
end)

function ScrapButton:OnClick(button)
  if button == "LeftButton" then
    SellJunk()
    self:UpdateState()
  end
end

function ScrapButton:OnEnter()
  local value = GetJunkValue()
  
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  
  if value > 0 then
    GameTooltip:SetText(L["|cFFFFD700Sell Junk|r"], 1, 1, 1)
    
    
    local gold = floor(value / 10000)
    local silver = floor((value % 10000) / 100)
    local copper = value % 100
    
    local moneyString = ""
    if gold > 0 then
      moneyString = format("%d|cFFFFD700g|r ", gold)
    end
    if silver > 0 or gold > 0 then
      moneyString = moneyString .. format("%d|cFFC7C7CFs|r ", silver)
    end
    moneyString = moneyString .. format("%d|cFFEDA55Fc|r", copper)
    
    GameTooltip:AddLine(T("Value: {moneyString}", { moneyString = moneyString }), 1, 1, 1)
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine(L["|cFF888888Left-click:|r Sell all junk"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["|cFF888888Alt-click a bag item:|r protect it / always sell it"], 0.8, 0.8, 0.8)
  else
    GameTooltip:SetText(L["|cFF888888No junk to sell|r"], 1, 1, 1)
    GameTooltip:AddLine(L["|cFF888888Alt-click a bag item:|r protect it / always sell it"], 0.8, 0.8, 0.8)
  end
  
  GameTooltip:Show()
end

function ScrapButton:OnLeave()
  GameTooltip:Hide()
end





ScrapButton:RegisterEvent("MERCHANT_SHOW")
ScrapButton:RegisterEvent("MERCHANT_CLOSED")
ScrapButton:RegisterEvent("BAG_UPDATE")

-- A list sent again to an open window fires MERCHANT_SHOW again: auto-sell only once per visit,
-- or every refresh wrote to the server (anti-flood kick).
local merchantVisitOpen = false

ScrapButton:SetScript("OnEvent", function(self, event, ...)
  if event == "MERCHANT_SHOW" then
    if not AdoptDragonButton() then self:Show() end
    self:UpdatePosition()
    self:UpdateState()

    local firstShow = not merchantVisitOpen
    merchantVisitOpen = true
    if firstShow and ProjectEbonholdOptionsService and ProjectEbonholdOptionsService:GetSetting("autoSellJunk") then

      C_Timer.After(0.2, function()
        if MerchantFrame:IsShown() then
          SellJunk()
          self:UpdateState()
        end
      end)
    end
    
  elseif event == "MERCHANT_CLOSED" then
    merchantVisitOpen = false
    self:Hide()
    
  elseif event == "BAG_UPDATE" then
    if MerchantFrame:IsShown() then
      self:UpdateState()
    end
  end
end)





ScrapButton:CreateButton()
ConfigButton:CreateButton()
ScrapButton:Hide()


if MerchantRepairText then
  MerchantRepairText:SetAlpha(0)
end