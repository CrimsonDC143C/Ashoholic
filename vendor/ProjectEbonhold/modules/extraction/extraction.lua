local addonName, addon = ...

ExtractionUI = ExtractionUI or {}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function FormatCopperSmall(copperAmount)
    if not copperAmount or copperAmount == 0 then return GetCoinTextureString(0, 10) end
    return GetCoinTextureString(copperAmount, 10)
end

-- The affix carried by an item link: its random property id (8th link field) IS the
-- ItemRandomProperties id the server sent with the affix list.
local function FindItemAffix(link)
    if not link then return nil end
    local randomProp = select(8, strsplit(":", link))
    randomProp = randomProp and tonumber(randomProp)
    if not randomProp or randomProp <= 0 then return nil end
    return ExtractionService.affixByEnchant and ExtractionService.affixByEnchant[randomProp] or nil
end

------------------------------------------------------------
-- Slot rules (mirror of world.affix_slot_category - the server enforces them)
------------------------------------------------------------
local CATEGORY_OFF, CATEGORY_DEF, CATEGORY_RES, CATEGORY_UTI, CATEGORY_MOB = 1, 2, 3, 4, 5
local SLOT_CATEGORIES = {
    INVTYPE_HEAD           = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_SHOULDER       = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_CHEST          = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_ROBE           = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_LEGS           = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_HAND           = { [CATEGORY_OFF] = true, [CATEGORY_UTI] = true },
    INVTYPE_TRINKET        = { [CATEGORY_OFF] = true, [CATEGORY_DEF] = true, [CATEGORY_RES] = true, [CATEGORY_UTI] = true, [CATEGORY_MOB] = true },
    INVTYPE_FINGER         = { [CATEGORY_OFF] = true, [CATEGORY_RES] = true },
    INVTYPE_NECK           = { [CATEGORY_OFF] = true, [CATEGORY_RES] = true },
    INVTYPE_CLOAK          = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_WRIST          = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_WAIST          = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_FEET           = { [CATEGORY_DEF] = true, [CATEGORY_MOB] = true },
    INVTYPE_WEAPON         = { [CATEGORY_OFF] = true },
    INVTYPE_WEAPONMAINHAND = { [CATEGORY_OFF] = true },
    INVTYPE_WEAPONOFFHAND  = { [CATEGORY_OFF] = true },
    INVTYPE_2HWEAPON       = { [CATEGORY_OFF] = true },
    INVTYPE_SHIELD         = { [CATEGORY_OFF] = true },
    INVTYPE_HOLDABLE       = { [CATEGORY_OFF] = true },
    INVTYPE_RANGED         = { [CATEGORY_OFF] = true },
    INVTYPE_RANGEDRIGHT    = { [CATEGORY_OFF] = true },   -- guns / crossbows ; wands are excluded below
    INVTYPE_THROWN         = { [CATEGORY_OFF] = true },
}
local WAND_SUBTYPE = "Wands"

-- Human labels for the slot list shown in the affix tooltip; every weapon-type
-- equipLoc collapses into one "Weapons" entry so the line stays short.
local SLOT_LABELS = {
    INVTYPE_HEAD = "Head", INVTYPE_SHOULDER = "Shoulders", INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest",
    INVTYPE_LEGS = "Legs", INVTYPE_HAND = "Hands", INVTYPE_TRINKET = "Trinkets", INVTYPE_FINGER = "Rings",
    INVTYPE_NECK = "Neck", INVTYPE_CLOAK = "Back", INVTYPE_WRIST = "Wrists", INVTYPE_WAIST = "Waist",
    INVTYPE_FEET = "Feet",
    INVTYPE_WEAPON = "Weapons", INVTYPE_WEAPONMAINHAND = "Weapons", INVTYPE_WEAPONOFFHAND = "Weapons",
    INVTYPE_2HWEAPON = "Weapons", INVTYPE_SHIELD = "Weapons", INVTYPE_HOLDABLE = "Weapons",
    INVTYPE_RANGED = "Weapons", INVTYPE_RANGEDRIGHT = "Weapons", INVTYPE_THROWN = "Weapons",
}
local SLOT_LABEL_ORDER = { "Head", "Neck", "Shoulders", "Back", "Chest", "Wrists", "Hands", "Waist", "Legs", "Feet",
                           "Rings", "Trinkets", "Weapons" }

-- category -> "Head, Chest, ..." built once from SLOT_CATEGORIES
local CATEGORY_SLOT_TEXT = {}
for cat = CATEGORY_OFF, CATEGORY_MOB do
    local seen, parts = {}, {}
    for equipLoc, cats in pairs(SLOT_CATEGORIES) do
        if cats[cat] then seen[SLOT_LABELS[equipLoc]] = true end
    end
    for _, label in ipairs(SLOT_LABEL_ORDER) do
        if seen[label] then parts[#parts + 1] = label end
    end
    CATEGORY_SLOT_TEXT[cat] = table.concat(parts, ", ")
end

-- Returns the category set an item link may carry (nil = no affix on this slot), and its rank cap
local function GetItemAffixRules(link)
    if not link then return nil, 1 end
    local _, _, quality, _, _, _, subType, _, equipLoc = GetItemInfo(link)
    if not equipLoc or (quality or 0) <= 2 then return nil, 1 end
    if subType == WAND_SUBTYPE then return nil, 1 end
    local cats = SLOT_CATEGORIES[equipLoc]
    if not cats then return nil, 1 end
    -- Every rank fits on every item that takes affixes (no item-level cap)
    return cats, 5
end

-- Why GetItemAffixRules said no, in the player's words
local function NoAffixReason(link)
    local _, _, quality, _, _, _, subType = GetItemInfo(link)
    if (quality or 0) <= 2 then return "Only rare or better items can carry an affix." end
    if subType == WAND_SUBTYPE then return "Wands cannot carry an affix." end
    return "This slot cannot carry an affix."
end

------------------------------------------------------------
-- Confirmation dialog
------------------------------------------------------------

StaticPopupDialogs["EBONHOLD_CONFIRM_LEGENDARY_UPGRADE"] = {
    text = "Raise this item to %s?\n\nIt will consume %d Marks of Torment. Enchantments and gems are kept.",
    button1 = "Upgrade",
    button2 = "Cancel",
    OnAccept = function()
        if ExtractionUI.pendingBag and ExtractionUI.pendingSlot then
            ExtractionService.RequestLegendaryUpgrade(ExtractionUI.pendingBag, ExtractionUI.pendingSlot)
        end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EBONHOLD_CONFIRM_EXTRACTION"]  = {
    text = "This will destroy the item and extract its affix.\n\nContinue?",
    button1 = "Confirm",
    button2 = "Cancel",
    OnAccept = function()
        if ExtractionUI.pendingBag and ExtractionUI.pendingSlot then
            ExtractionService.RequestExtraction(ExtractionUI.pendingBag, ExtractionUI.pendingSlot)
        end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EBONHOLD_CONFIRM_APPLY_AFFIX"] = {
    text = "Apply the selected affix to this item?\n\nContinue?",
    button1 = "Confirm",
    button2 = "Cancel",
    OnAccept = function()
        if ExtractionUI.pendingBag and ExtractionUI.pendingSlot and ExtractionUI.selectedAffixId then
            ExtractionService.RequestApplyAffix(ExtractionUI.selectedAffixId, ExtractionUI.pendingBag,
                ExtractionUI.pendingSlot)
        end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------
-- Main Frame
------------------------------------------------------------

local FRAME_WIDTH                                  = 300
local FRAME_HEIGHT                                 = 300
local SLOT_SIZE                                    = 42
local TITLE_BAR_HEIGHT                             = 24
local BOTTOM_BAR_HEIGHT                            = 30

local isInExtractionGossip                         = false

local frame                                        = CreateFrame("Frame", "EbonholdExtractionFrame", UIParent)
frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
frame:SetToplevel(true)
frame:SetFrameLevel(100)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

-- ESC to close
table.insert(UISpecialFrames, "EbonholdExtractionFrame")

------------------------------------------------------------
-- Background & border
------------------------------------------------------------

frame.bgBlack = frame:CreateTexture(nil, "BACKGROUND")
frame.bgBlack:SetTexture(0, 0, 0, 1)
frame.bgBlack:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
frame.bgBlack:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

frame.bgForge = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
frame.bgForge:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\obliterumforge")
frame.bgForge:SetTexCoord(0.000000, 0.632812, 0.000000, 0.628906)
frame.bgForge:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(56 + TITLE_BAR_HEIGHT))
frame.bgForge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 56 + BOTTOM_BAR_HEIGHT)

frame:SetBackdrop({
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})

------------------------------------------------------------
-- Title bar
------------------------------------------------------------

frame.titleBar = frame:CreateTexture(nil, "ARTWORK")
frame.titleBar:SetTexture(0, 0, 0, 0.6)
frame.titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
frame.titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
frame.titleBar:SetHeight(TITLE_BAR_HEIGHT)

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.title:SetPoint("CENTER", frame.titleBar, "CENTER", 0, -16)
frame.title:SetText("Enchanted Anvil")

------------------------------------------------------------
-- Close button
------------------------------------------------------------

frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
frame.closeButton:SetPoint("TOPRIGHT", -2, -2)
frame.closeButton:SetScript("OnClick", function() frame:Hide() end)

------------------------------------------------------------
-- Item slot (drop target) - centered in the background area
------------------------------------------------------------

local slot = CreateFrame("Button", "EbonholdExtractionSlot", frame)
slot:SetSize(SLOT_SIZE, SLOT_SIZE)
slot:SetPoint("CENTER", frame, "CENTER", 0, 5)

slot.bg = slot:CreateTexture(nil, "BACKGROUND")
slot.bg:SetAllPoints()

slot.icon = slot:CreateTexture(nil, "ARTWORK")
slot.icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 3, -3)
slot.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -3, 3)
slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
slot.icon:Hide()

slot.highlight = slot:CreateTexture(nil, "HIGHLIGHT")
slot.highlight:SetAllPoints()
slot.highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
slot.highlight:SetBlendMode("ADD")

-- Hint label under the slot
frame.hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.hintText:SetPoint("TOP", slot, "BOTTOM", 0, -28)
frame.hintText:SetText("|cff888888Drop an item here to extract its affixes or apply any affixes you already know.|r")
frame.hintText:SetWidth(FRAME_WIDTH - 40)
frame.hintText:SetJustifyH("CENTER")

------------------------------------------------------------
-- Bottom bar: cost on the left, extract button on the right
------------------------------------------------------------

frame.bottomBar = frame:CreateTexture(nil, "ARTWORK")
frame.bottomBar:SetTexture(0, 0, 0, 0.6)
frame.bottomBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
frame.bottomBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
frame.bottomBar:SetHeight(BOTTOM_BAR_HEIGHT)

local extractBtn = utils.CreateCustomButton(nil, frame, { width = 120, height = 34 }, "Extract", nil)
extractBtn:SetPoint("LEFT", frame.bottomBar, "LEFT", 14, 30)
extractBtn:Disable()
extractBtn:Hide()
if extractBtn.text then extractBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 10) end

local applyBtn = utils.CreateCustomButton(nil, frame, { width = 120, height = 34 }, "Choose an Affix", nil)
applyBtn:SetPoint("RIGHT", frame.bottomBar, "RIGHT", -14, 30)
applyBtn:Disable()
applyBtn:Hide()
if applyBtn.text then applyBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 10) end

-- Legendary Torment upgrade: shown only when the server quotes a recipe for the item
local upgradeBtn = utils.CreateCustomButton(nil, frame, { width = 250, height = 44 }, "Upgrade Torment", nil)
upgradeBtn:SetPoint("CENTER", frame.bottomBar, "CENTER", 0, 30)
upgradeBtn:Disable()
upgradeBtn:Hide()
upgradeBtn:SetMotionScriptsWhileDisabled(true)   -- tooltip must work while the button is greyed out
if upgradeBtn.text then upgradeBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 10) end

frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.statusText:SetPoint("BOTTOM", frame.bottomBar, "BOTTOM", 0, 7)
frame.statusText:SetText("")
frame.statusText:SetWidth(FRAME_WIDTH - 30)
frame.statusText:SetJustifyH("CENTER")
frame.statusText:SetWordWrap(true)

ExtractionUI.pendingBag      = nil
ExtractionUI.pendingSlot     = nil
ExtractionUI.pendingLink     = nil
ExtractionUI.selectedAffixId = nil

local function HideSidePanel()
    if frame.sidePanel then
        frame.sidePanel:Hide()
    end
    ExtractionUI.selectedAffixId = nil
end

local function ClearSlot()
    ExtractionUI.pendingBag      = nil
    ExtractionUI.pendingSlot     = nil
    ExtractionUI.pendingLink     = nil
    ExtractionUI.selectedAffixId = nil

    slot.icon:Hide()
    frame.hintText:SetText("|cff888888Drop an item here to extract its affixes or apply any affixes you already know.|r")
    frame.hintText:ClearAllPoints()
    frame.hintText:SetPoint("TOP", slot, "BOTTOM", 0, -28)
    extractBtn:SetText("Extract")
    extractBtn:Disable()
    extractBtn:Hide()
    applyBtn:SetText("Choose an Affix")
    applyBtn:Disable()
    applyBtn:Hide()
    upgradeBtn:Hide()
    ExtractionService.upgradeInfo = nil
    if ExtractionUI.noAffixMessage and frame.statusText:GetText() == ExtractionUI.noAffixMessage then
        frame.statusText:SetText("")
    end
    ExtractionUI.noAffixMessage = nil
    HideSidePanel()
end

-- A token the client has never held has no name yet: a hidden tooltip asks the server for it,
-- and tokenRetry re-draws the button until the answer lands (3.3.5 has no event for it).
local tokenScanTip
local tokenRetry = CreateFrame("Frame")
tokenRetry:Hide()

local function TokenLabel(tokenId)
    local name = GetItemInfo(tokenId)
    if not name then
        if not tokenScanTip then
            tokenScanTip = CreateFrame("GameTooltip", "ProjectEbonholdExtractionScan", nil, "GameTooltipTemplate")
        end
        tokenScanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        tokenScanTip:SetHyperlink("item:" .. tokenId)
        tokenScanTip:Hide()
        if not tokenRetry:IsShown() then
            tokenRetry.elapsed, tokenRetry.total = 0, 0
            tokenRetry:Show()
        end
        name = GetItemInfo(tokenId)
    end
    local icon = GetItemIcon(tokenId)
    local label = name or "Mark of Torment"
    if icon then label = "|T" .. icon .. ":16:16:0:0|t " .. label end
    return label, name ~= nil
end

local function UpdateButtonVisibility()
    if not ExtractionUI.pendingLink then
        extractBtn:Hide()
        applyBtn:Hide()
        return
    end

    local up = ExtractionService.upgradeInfo
    if up then
        local color = (up.held >= up.needed) and "|cff00ff00" or "|cffff4040"
        local tokenName = TokenLabel(up.tokenId)
        upgradeBtn:SetText(string.format("Upgrade  %s%d/%d|r %s", color, up.held, up.needed, tokenName))
        upgradeBtn:Show()
        if up.held >= up.needed then upgradeBtn:Enable() else upgradeBtn:Disable() end
    else
        upgradeBtn:Hide()
    end

    local itemAffix = FindItemAffix(ExtractionUI.pendingLink)
    local hasAffix = itemAffix ~= nil

    -- Apply is allowed on any slot that supports at least one category
    local allowedCats = GetItemAffixRules(ExtractionUI.pendingLink)
    local canApply = allowedCats ~= nil

    -- Extract: only an item carrying one of our affixes
    local alreadyLearned = itemAffix and itemAffix.learned
    local canExtract = hasAffix

    if canExtract then
        extractBtn:Show()
        if alreadyLearned then
            extractBtn:Disable()
        else
            extractBtn:Enable()
        end
    else
        extractBtn:Hide()
    end

    -- Apply: allowed for any equipable item placed in the slot
    if canApply then
        applyBtn:Show()
        applyBtn:Enable()
    else
        applyBtn:Hide()
    end

    -- A tier piece can be upgraded AND engraved: the upgrade keeps the bottom row (made slimmer),
    -- the affix buttons move one row up and the item name moves up under the slot to make room.
    -- Nothing to do with this item here: say why instead of an empty window. Only our own
    -- message is cleared, never a result line (applied, extracted, upgraded).
    if not up and not canExtract and not canApply then
        ExtractionUI.noAffixMessage = "|cffff8040" .. NoAffixReason(ExtractionUI.pendingLink) .. "|r"
        frame.statusText:SetText(ExtractionUI.noAffixMessage)
    elseif ExtractionUI.noAffixMessage then
        if frame.statusText:GetText() == ExtractionUI.noAffixMessage then frame.statusText:SetText("") end
        ExtractionUI.noAffixMessage = nil
    end

    local stacked = up and (canExtract or canApply)
    local rowY = stacked and 70 or 30
    upgradeBtn:SetHeight(stacked and 34 or 44)
    frame.hintText:ClearAllPoints()
    frame.hintText:SetPoint("TOP", slot, "BOTTOM", 0, stacked and -6 or -28)

    -- Position buttons side by side or centered
    extractBtn:ClearAllPoints()
    applyBtn:ClearAllPoints()
    if canExtract and canApply then
        extractBtn:SetPoint("LEFT", frame.bottomBar, "LEFT", 14, rowY)
        applyBtn:SetPoint("RIGHT", frame.bottomBar, "RIGHT", -14, rowY)
    elseif canExtract then
        extractBtn:SetPoint("CENTER", frame.bottomBar, "CENTER", 0, rowY)
    elseif canApply then
        applyBtn:SetPoint("CENTER", frame.bottomBar, "CENTER", 0, rowY)
    end
end

-- Poll a few times a second for the token's name, give up after 5 s (an id the server does not know)
tokenRetry:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    self.total = self.total + dt
    if self.elapsed < 0.25 then return end
    self.elapsed = 0
    local up = ExtractionService.upgradeInfo
    if not up or not frame:IsShown() or self.total > 5 then
        self:Hide()
        return
    end
    if GetItemInfo(up.tokenId) then
        self:Hide()
        UpdateButtonVisibility()
    end
end)

local function UpdateCostDisplay()
    -- Try to get extract cost from the affix on the placed item
    local extractCost = nil
    if ExtractionUI.pendingLink then
        local itemAffix = FindItemAffix(ExtractionUI.pendingLink)
        if itemAffix then
            extractCost = itemAffix.extractCost
        end
    end
    -- Fall back to server-provided cost
    if not extractCost then
        extractCost = ExtractionService.currentCost
    end
    local extractCoinStr = extractCost and FormatCopperSmall(extractCost) or ""

    -- Update Extract button text with extraction cost
    local hasAffixOnItem = FindItemAffix(ExtractionUI.pendingLink) ~= nil
    if ExtractionUI.pendingLink and hasAffixOnItem then
        extractBtn:SetText("Extract  " .. extractCoinStr)
    else
        extractBtn:SetText("Extract")
    end

    -- Update Apply button text: if affix selected, show "Apply Affix" + per-affix cost
    local itemHasAffix = hasAffixOnItem
    if ExtractionUI.selectedAffixId then
        local applyCost = ExtractionService.applyCost
        local applyCoinStr = applyCost and FormatCopperSmall(applyCost) or ""
        local label = itemHasAffix and "Change Affix  " or "Apply Affix  "
        applyBtn:SetText(label .. applyCoinStr)
    else
        applyBtn:SetText(itemHasAffix and "Change the Affix" or "Choose an Affix")
    end

    UpdateButtonVisibility()
end

local function SetSlotItem(bag, slotIdx, link, texture)
    ExtractionUI.pendingBag      = bag
    ExtractionUI.pendingSlot     = slotIdx
    ExtractionUI.pendingLink     = link
    ExtractionUI.selectedAffixId = nil

    slot.icon:SetTexture(texture)
    slot.icon:Show()

    local itemName = GetItemInfo(link)
    frame.hintText:SetText(link or itemName or "")
    frame.statusText:SetText("")

    -- Reset side panel selection and re-filter for the new item
    if frame.sidePanel and frame.sidePanel:IsShown() then
        ExtractionUI.PopulateSidePanel()
    end

    ExtractionService.upgradeInfo = nil
    ExtractionService.RequestExtractionInfo(bag, slotIdx)
    ExtractionService.RequestLegendaryUpgradeInfo(bag, slotIdx)
    UpdateCostDisplay()
end

------------------------------------------------------------
-- Slot click / drop handling
------------------------------------------------------------

slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")

slot:SetScript("OnReceiveDrag", function(self)
    if not CursorHasItem() then return end

    local infoType, itemId, itemLink = GetCursorInfo()
    if infoType ~= "item" then
        ClearCursor()
        return
    end

    -- Find bag/slot by scanning containers
    local foundBag, foundSlot
    for b = 0, 4 do
        for s = 1, GetContainerNumSlots(b) do
            local containerLink = GetContainerItemLink(b, s)
            if containerLink and containerLink == itemLink then
                foundBag  = b
                foundSlot = s
                break
            end
        end
        if foundBag then break end
    end

    ClearCursor()

    if not foundBag then
        frame.statusText:SetText("|cffff0000Could not locate the item in your bags.|r")
        return
    end

    -- Validate: must be equipable and at least green (uncommon) quality
    local _, _, itemQuality, itemLevel, _, _, _, _, itemEquipLoc, texture = GetItemInfo(itemLink)
    if not itemEquipLoc or itemEquipLoc == "" or itemEquipLoc == "INVTYPE_NON_EQUIP" then
        frame.statusText:SetText("|cffff0000Only equipable items can be placed here.|r")
        return
    end
    if not itemQuality or itemQuality < 2 then
        frame.statusText:SetText("|cffff0000Only items of uncommon (green) quality or higher.|r")
        return
    end
    -- Convert Lua bag/slot to TrinityCore GetItemByPos(bag, slot) format:
    -- Backpack: bag 0 → 255, slot 1-based → absolute index (INVENTORY_SLOT_ITEM_START + slot - 1 = 22 + slot)
    -- Bags 1-4: bag N → equipped bag slot (18 + N), slot 1-based → 0-based (slot - 1)
    local serverBag, serverSlot
    if foundBag == 0 then
        serverBag  = 255
        serverSlot = 22 + foundSlot -- INVENTORY_SLOT_ITEM_START (23) + foundSlot - 1
    else
        serverBag  = 18 + foundBag  -- INVENTORY_SLOT_BAG_START (19) + foundBag - 1
        serverSlot = foundSlot - 1  -- 0-based within the bag
    end
    SetSlotItem(serverBag, serverSlot, itemLink, texture)
end)

slot:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        ClearSlot()
        return
    end

    -- LeftButton: accept drop from cursor
    if CursorHasItem() then
        self:GetScript("OnReceiveDrag")(self)
    end
end)

-- Tooltip
slot:SetScript("OnEnter", function(self)
    if ExtractionUI.pendingLink then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(ExtractionUI.pendingLink)
        GameTooltip:Show()
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("|cffffd700Affix Extraction|r")
        GameTooltip:AddLine("Drop an item with a random property (affix) here\nto extract its corruption.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888888Right-click to clear the slot|r", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end
end)

slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------
-- Extract button handler
------------------------------------------------------------

extractBtn:SetScript("OnClick", function()
    if not ExtractionUI.pendingBag or not ExtractionUI.pendingSlot then return end
    StaticPopup_Show("EBONHOLD_CONFIRM_EXTRACTION")
end)

applyBtn:SetScript("OnClick", function()
    if not ExtractionUI.pendingBag or not ExtractionUI.pendingSlot then return end
    -- Toggle side panel
    if frame.sidePanel and frame.sidePanel:IsShown() then
        HideSidePanel()
    else
        ExtractionUI.ShowSidePanel()
    end
end)

-- Target tier and token live in the tooltip so the button stays short
upgradeBtn:SetScript("OnEnter", function(self)
    local up = ExtractionService.upgradeInfo
    if not up then return end
    local tokenName = TokenLabel(up.tokenId)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Upgrade to " .. up.label)
    GameTooltip:AddLine(string.format("%d/%d %s", up.held, up.needed, tokenName), 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
upgradeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
upgradeBtn:SetScript("OnClick", function()
    local up = ExtractionService.upgradeInfo
    if not up or not ExtractionUI.pendingBag or not ExtractionUI.pendingSlot then return end
    StaticPopup_Show("EBONHOLD_CONFIRM_LEGENDARY_UPGRADE", up.label, up.needed)
end)

function ExtractionUI.OnUpgradeInfoReceived(info)
    if not frame:IsShown() then return end
    UpdateCostDisplay()
end

function ExtractionUI.OnUpgradeSuccess(newEntry)
    if not frame:IsShown() then return end
    frame.statusText:SetText("|cff00ff00Your legendary has been raised.|r")
    -- The item in the slot is a new object now: re-read it so a second upgrade quotes the next bracket.
    local bag, slotIdx = ExtractionUI.pendingBag, ExtractionUI.pendingSlot
    ClearSlot()
    if bag and slotIdx then
        local luaBag, luaSlot
        if bag == 255 then luaBag, luaSlot = 0, slotIdx - 22 else luaBag, luaSlot = bag - 18, slotIdx + 1 end
        local link = GetContainerItemLink(luaBag, luaSlot)
        local texture = GetContainerItemInfo(luaBag, luaSlot)
        if link then SetSlotItem(bag, slotIdx, link, texture) end
    end
    UpdateCostDisplay()
end

function ExtractionUI.OnUpgradeFail(reason)
    if not frame:IsShown() then return end
    frame.statusText:SetText("|cffff0000" .. (reason or "Upgrade failed.") .. "|r")
end

function ExtractionUI.OnCostReceived(cost)
    if not frame:IsShown() then return end
    UpdateCostDisplay()
end

function ExtractionUI.OnExtractionSuccess()
    if not frame:IsShown() then return end
    frame.statusText:SetText("|cff00ff00Affix extracted successfully!|r")
    ClearSlot()
    UpdateCostDisplay()
end

function ExtractionUI.OnExtractionFail(reason)
    if not frame:IsShown() then return end
    frame.statusText:SetText("|cffff0000" .. (reason or "Extraction failed.") .. "|r")
end

function ExtractionUI.OnApplySuccess()
    if not frame:IsShown() then return end
    frame.statusText:SetText("|cff00ff00Affix applied successfully!|r")
    HideSidePanel()
    ClearSlot()
    UpdateCostDisplay()
end

function ExtractionUI.OnApplyFail(reason)
    if not frame:IsShown() then return end
    frame.statusText:SetText("|cffff0000" .. (reason or "Apply failed.") .. "|r")
end

function ExtractionUI.OnApplyCostReceived(cost)
    if not frame:IsShown() then return end
    UpdateCostDisplay()
    -- Update confirm button with cost
    if frame.sidePanel and frame.sidePanel.confirmBtn and ExtractionUI.selectedAffixId then
        local coinStr = cost and FormatCopperSmall(cost) or ""
        frame.sidePanel.confirmBtn:SetText("Confirm  " .. coinStr)
    end
end

function ExtractionUI.OnLearnedAffixesReceived()
    if frame.sidePanel and frame.sidePanel:IsShown() then
        ExtractionUI.PopulateSidePanel()
    end
end

------------------------------------------------------------
-- OnHide cleanup
------------------------------------------------------------

frame:SetScript("OnHide", function()
    ClearSlot()
    frame.statusText:SetText("")
    HideSidePanel()
    if isInExtractionGossip then
        isInExtractionGossip = false
        if GossipFrame then
            GossipFrame:SetAlpha(1)
            GossipFrame:EnableMouse(true)
            GossipFrame:ClearAllPoints()
            GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
        if GossipFrameCloseButton then
            GossipFrameCloseButton:Click()
        end
    end
end)

------------------------------------------------------------
-- Side panel (Affix Book)
--   Search box, slot dropdown and a "Learned only" toggle
--   above a list grouped by category. Each family is one row: icon, name
--   and apply cost. Rows the placed
--   item cannot carry (wrong slot category, or a rank above its cap) stay
--   visible but dimmed and unselectable, so the book doubles as a catalogue.
------------------------------------------------------------

local SIDE_PANEL_WIDTH    = 340
local SIDE_PANEL_HEIGHT   = 380
local SIDE_PANEL_MIN_H    = 300
local SIDE_PANEL_MAX_H    = 900
local PANEL_INSET         = 18     -- content margin inside the dialog border
local SCROLLBAR_WIDTH     = 22
local AFFIX_ROW_HEIGHT    = 30
local AFFIX_ROW_SPACING   = 3
local GROUP_HEADER_HEIGHT = 22

local CATEGORY_ORDER  = { CATEGORY_OFF, CATEGORY_DEF, CATEGORY_RES, CATEGORY_UTI, CATEGORY_MOB }
local CATEGORY_COLORS = {
    [CATEGORY_OFF] = { 1.00, 0.36, 0.36, hex = "ff5c5c" },
    [CATEGORY_DEF] = { 0.36, 0.61, 1.00, hex = "5c9cff" },
    [CATEGORY_RES] = { 0.36, 1.00, 0.54, hex = "5cff8a" },
    [CATEGORY_UTI] = { 1.00, 0.83, 0.36, hex = "ffd45c" },
    [CATEGORY_MOB] = { 0.36, 0.94, 1.00, hex = "5cf0ff" },
}
local ALL_COLOR  = { 1.00, 0.82, 0.00, hex = "ffd100" }

-- slot label -> categories it allows (union of the equipLocs sharing the label)
local SLOT_LABEL_CATEGORIES = {}
for equipLoc, cats in pairs(SLOT_CATEGORIES) do
    local label = SLOT_LABELS[equipLoc]
    SLOT_LABEL_CATEGORIES[label] = SLOT_LABEL_CATEGORIES[label] or {}
    for cat in pairs(cats) do SLOT_LABEL_CATEGORIES[label][cat] = true end
end

local function CreateSidePanel()
    local panel = CreateFrame("Frame", "EbonholdAffixBookPanel", frame)
    panel:SetSize(SIDE_PANEL_WIDTH, SIDE_PANEL_HEIGHT)
    panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", -2, 0)
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:SetFrameLevel(frame:GetFrameLevel() + 1)
    panel:EnableMouse(true)
    panel:SetResizable(true)
    panel:SetMinResize(SIDE_PANEL_WIDTH, SIDE_PANEL_MIN_H)
    panel:SetMaxResize(SIDE_PANEL_WIDTH, SIDE_PANEL_MAX_H)
    panel:Hide()

    panel.filterSlot     = nil   -- nil = every slot, else a SLOT_LABELS value
    panel.autoSlotLink   = nil   -- item link the slot filter was last auto-set from

    -- Resize grip at the bottom
    local resizeGrip = CreateFrame("Frame", nil, panel)
    resizeGrip:SetHeight(8)
    resizeGrip:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    resizeGrip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    resizeGrip:EnableMouse(true)
    resizeGrip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            panel:StartSizing("BOTTOM")
        end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        panel:StopMovingOrSizing()
    end)

    -- Visual indicator for the grip (three horizontal lines)
    for k = -1, 1 do
        local line = resizeGrip:CreateTexture(nil, "OVERLAY")
        line:SetPoint("LEFT", resizeGrip, "LEFT", 4, k * 3)
        line:SetPoint("RIGHT", resizeGrip, "RIGHT", -4, k * 3)
        line:SetHeight(1)
        line:SetTexture(1, 1, 1, 0.3)
    end

    panel.bgTexture = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    panel.bgTexture:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\UI-Background-Rock")
    panel.bgTexture:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    panel.bgTexture:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)

    panel:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOP", panel, "TOP", 0, -20)
    panel.title:SetText("Affix Book")

    -- Row 1: search box + "Learned only"
    local searchBox = CreateFrame("EditBox", "EbonholdAffixSearchBox", panel, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_INSET + 6, -48)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetTextInsets(4, 16, 0, 0)

    searchBox.placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchBox.placeholder:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    searchBox.placeholder:SetText("Search affixes...")

    local clearBtn = CreateFrame("Button", nil, searchBox)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", searchBox, "RIGHT", -2, 0)
    clearBtn:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    clearBtn:SetHighlightTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    clearBtn:Hide()
    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
    end)
    searchBox.clearBtn = clearBtn

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            searchBox.placeholder:Hide()
            clearBtn:Show()
        else
            searchBox.placeholder:Show()
            clearBtn:Hide()
        end
        ExtractionUI.PopulateSidePanel()
    end)
    searchBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "" then
            searchBox.placeholder:Hide()
        end
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            searchBox.placeholder:Show()
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    panel.searchBox = searchBox

    local learnedCB = CreateFrame("CheckButton", "EbonholdAffixLearnedCheck", panel, "ChatConfigCheckButtonTemplate")
    learnedCB:SetSize(24, 24)
    learnedCB:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    learnedCB:SetChecked(true)
    _G[learnedCB:GetName() .. "Text"]:SetText("Learned only")
    _G[learnedCB:GetName() .. "Text"]:SetFontObject("GameFontNormalSmall")
    learnedCB:SetScript("OnClick", function()
        ExtractionUI.PopulateSidePanel()
    end)
    panel.learnedCB = learnedCB

    -- Row 2: slot dropdown
    local innerWidth = SIDE_PANEL_WIDTH - 2 * PANEL_INSET

    local slotDD = CreateFrame("Frame", "EbonholdAffixSlotDropDown", panel, "UIDropDownMenuTemplate")
    slotDD:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_INSET - 16, -74)
    UIDropDownMenu_SetWidth(slotDD, 90)
    local function SetSlotFilter(label)
        panel.filterSlot = label
        UIDropDownMenu_SetText(slotDD, label or "All slots")
    end
    UIDropDownMenu_Initialize(slotDD, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All slots"
        info.checked = panel.filterSlot == nil
        info.func = function()
            SetSlotFilter(nil)
            ExtractionUI.PopulateSidePanel()
        end
        UIDropDownMenu_AddButton(info, level)
        for _, label in ipairs(SLOT_LABEL_ORDER) do
            info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.checked = panel.filterSlot == label
            info.func = function()
                SetSlotFilter(label)
                ExtractionUI.PopulateSidePanel()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(slotDD, "All slots")
    panel.slotDD = slotDD
    panel.SetSlotFilter = SetSlotFilter

    panel.counterText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.counterText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_INSET - 2, -25)
    panel.counterText:SetJustifyH("RIGHT")
    panel.counterText:SetText("")

    -- Separator under the filters
    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_INSET, -108)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_INSET, -108)
    sep:SetHeight(1)
    sep:SetTexture(1, 1, 1, 0.15)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "EbonholdAffixBookScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_INSET, -114)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PANEL_INSET - SCROLLBAR_WIDTH, 66)
    panel.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(innerWidth - SCROLLBAR_WIDTH)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    panel.scrollChild = scrollChild

    -- Empty text
    panel.emptyText = scrollFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.emptyText:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
    panel.emptyText:SetWidth(innerWidth - 60)
    panel.emptyText:SetJustifyH("CENTER")
    panel.emptyText:Hide()

    -- Confirm button at bottom of side panel
    panel.confirmBtn = utils.CreateCustomButton(nil, panel, { width = 200, height = 32 }, "Confirm Apply", function()
        if ExtractionUI.pendingBag and ExtractionUI.pendingSlot and ExtractionUI.selectedAffixId then
            StaticPopup_Show("EBONHOLD_CONFIRM_APPLY_AFFIX")
        end
    end)
    panel.confirmBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 24)
    panel.confirmBtn:Disable()
    if panel.confirmBtn.text then panel.confirmBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 10) end

    panel.affixRows = {}
    panel._recycledRows = {}
    panel.headerRows = {}
    panel._recycledHeaders = {}
    return panel
end

-- Family name without the trailing rank numeral ("Cold III" -> "Cold")
local function StripRank(name)
    if not name then return nil end
    return (name:gsub("%s+[IVX]+$", ""))
end

-- Why the placed item cannot take this affix (nil when it can)
local function GetUnusableReason(affix, allowedCats, maxRank)
    if not ExtractionUI.pendingLink then return nil end
    if allowedCats == nil then return "No affix on this item" end
    if not allowedCats[affix.category] then return "Wrong slot for this affix" end
    if (affix.rank or 1) > (maxRank or 1) then return "Item below level 80: rank I only" end
    return nil
end

local function SelectAffixRow(panel, row, affix)
    for _, r in ipairs(panel.affixRows) do r.highlight:Hide() end
    row.highlight:Show()
    ExtractionUI.selectedAffixId = affix.id
    local coinStr = affix.applyCost and FormatCopperSmall(affix.applyCost) or ""
    panel.confirmBtn:SetText("Confirm  " .. coinStr)
    -- The same affix already on the item is nothing to apply
    local isSameAffix = false
    if ExtractionUI.pendingLink then
        local currentAffix = FindItemAffix(ExtractionUI.pendingLink)
        if currentAffix and currentAffix.id == affix.id then isSameAffix = true end
    end
    if isSameAffix then panel.confirmBtn:Disable() else panel.confirmBtn:Enable() end
    ExtractionService.applyCost = affix.applyCost
    UpdateCostDisplay()
end

local function AcquireRow(panel)
    local row = table.remove(panel._recycledRows)
    if row then return row end
    row = CreateFrame("Button", nil, panel.scrollChild)
    row:SetSize(panel.scrollChild:GetWidth(), AFFIX_ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture(1, 1, 1, 0.04)

    row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.highlight:SetAllPoints()
    row.highlight:SetTexture(1, 0.82, 0, 0.18)

    row.hoverTex = row:CreateTexture(nil, "HIGHLIGHT")
    row.hoverTex:SetAllPoints()
    row.hoverTex:SetTexture(1, 1, 1, 0.06)

    row.stripe = row:CreateTexture(nil, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.stripe:SetWidth(3)

    local iconSize = AFFIX_ROW_HEIGHT - 6
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)

    row.iconBorder = row:CreateTexture(nil, "OVERLAY")
    row.iconBorder:SetSize(iconSize + 32, iconSize + 32)
    row.iconBorder:SetPoint("CENTER", row.icon, "CENTER")
    row.iconBorder:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder")

    row.metaText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.metaText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.metaText:SetJustifyH("RIGHT")

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.nameText:SetPoint("RIGHT", row.metaText, "LEFT", -8, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function AcquireHeader(panel)
    local header = table.remove(panel._recycledHeaders)
    if header then return header end
    header = CreateFrame("Frame", nil, panel.scrollChild)
    header:SetSize(panel.scrollChild:GetWidth(), GROUP_HEADER_HEIGHT)
    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.text:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 2, 4)
    header.count = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.count:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 4)
    header.count:SetTextColor(0.6, 0.6, 0.6)
    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header.line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    header.line:SetHeight(1)
    return header
end

function ExtractionUI.PopulateSidePanel()
    local panel = frame.sidePanel
    if not panel then return end

    -- Recycle old rows and headers instead of leaking them
    for _, row in ipairs(panel.affixRows) do
        row:Hide()
        row:ClearAllPoints()
        table.insert(panel._recycledRows, row)
    end
    panel.affixRows = {}
    for _, header in ipairs(panel.headerRows) do
        header:Hide()
        header:ClearAllPoints()
        table.insert(panel._recycledHeaders, header)
    end
    panel.headerRows = {}

    local previousSelection = ExtractionUI.selectedAffixId
    ExtractionUI.selectedAffixId = nil
    panel.confirmBtn:Disable()

    -- Applied counts come from the equipped item links, not from the server: refresh on every redraw
    if ExtractionService.RefreshAppliedCounts then
        ExtractionService.RefreshAppliedCounts()
    end
    local affixes = ExtractionService.learnedAffixes or {}

    -- Slot rules of the placed item: categories it may carry, and its rank cap (V on every item)
    local allowedCats, maxRank = GetItemAffixRules(ExtractionUI.pendingLink)

    -- A newly placed item preselects its slot in the dropdown; the player can still change it
    if ExtractionUI.pendingLink ~= panel.autoSlotLink then
        panel.autoSlotLink = ExtractionUI.pendingLink
        local label
        if ExtractionUI.pendingLink then
            local equipLoc = select(9, GetItemInfo(ExtractionUI.pendingLink))
            label = equipLoc and SLOT_LABELS[equipLoc] or nil
        end
        panel.SetSlotFilter(label)
    end

    -- Fold the per-rank entries into families
    local families, familyOrder = {}, {}
    for _, affix in ipairs(affixes) do
        local key = affix.familyId or affix.id
        local fam = families[key]
        if not fam then
            fam = { ranks = {}, category = affix.category or 0, name = affix.familyName or StripRank(affix.name) }
            families[key] = fam
            familyOrder[#familyOrder + 1] = key
        end
        fam.ranks[#fam.ranks + 1] = affix
        if affix.learned then fam.anyLearned = true end
    end

    -- The row shows the best learned rank the item can take, else the best learned rank,
    -- else the lowest unlearned one
    local function PickRepresentative(fam)
        local bestFitting, bestLearned, lowestUnlearned
        for _, affix in ipairs(fam.ranks) do
            local r = affix.rank or 1
            if affix.learned then
                if not bestLearned or r > (bestLearned.rank or 1) then bestLearned = affix end
                if not GetUnusableReason(affix, allowedCats, maxRank) then
                    if not bestFitting or r > (bestFitting.rank or 1) then bestFitting = affix end
                end
            elseif not lowestUnlearned or r < (lowestUnlearned.rank or 1) then
                lowestUnlearned = affix
            end
        end
        return bestFitting or bestLearned or lowestUnlearned
    end

    -- Learned counter over families (a family counts once its first rank is known)
    local learnedFamilies, totalFamilies = 0, #familyOrder
    local categoryTotals, categoryLearned = {}, {}
    for _, key in ipairs(familyOrder) do
        local fam = families[key]
        categoryTotals[fam.category] = (categoryTotals[fam.category] or 0) + 1
        if fam.anyLearned then
            learnedFamilies = learnedFamilies + 1
            categoryLearned[fam.category] = (categoryLearned[fam.category] or 0) + 1
        end
    end
    panel.counterText:SetText(string.format("|cffffd100%d|r / %d affixes learned", learnedFamilies, totalFamilies))

    -- Filters: search text, learned toggle, slot dropdown
    local searchText = panel.searchBox and panel.searchBox:GetText() or ""
    searchText = searchText:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local learnedOnly = panel.learnedCB and panel.learnedCB:GetChecked()
    local slotCats = panel.filterSlot and SLOT_LABEL_CATEGORIES[panel.filterSlot] or nil

    local listed = {}
    for _, key in ipairs(familyOrder) do
        local fam = families[key]
        local affix = PickRepresentative(fam)
        if affix then
            local matchesSearch = searchText == "" or (fam.name and fam.name:lower():find(searchText, 1, true))
            local matchesLearned = not learnedOnly or fam.anyLearned
            local matchesSlot = slotCats == nil or slotCats[fam.category]
            if matchesSearch and matchesLearned and matchesSlot then
                listed[#listed + 1] = { family = fam, affix = affix }
            end
        end
    end

    -- Category groups in their canonical order, then by name inside a group
    local categoryRank = {}
    for i, cat in ipairs(CATEGORY_ORDER) do categoryRank[cat] = i end
    table.sort(listed, function(a, b)
        local ca, cb = categoryRank[a.family.category] or 99, categoryRank[b.family.category] or 99
        if ca ~= cb then return ca < cb end
        return (a.family.name or "") < (b.family.name or "")
    end)

    if #listed == 0 then
        if #affixes == 0 then
            panel.emptyText:SetText("No Affixes learned.\nTo learn more, extract them from any piece of gear.")
        else
            panel.emptyText:SetText("No affix matches these filters.")
        end
        panel.emptyText:Show()
    else
        panel.emptyText:Hide()
    end

    local currentAffix = ExtractionUI.pendingLink and FindItemAffix(ExtractionUI.pendingLink) or nil
    local y = 0
    local lastCategory = nil
    local selectedRow, selectedAffix

    for _, entry in ipairs(listed) do
        local fam, affix = entry.family, entry.affix
        local color = CATEGORY_COLORS[fam.category] or ALL_COLOR

        if fam.category ~= lastCategory then
            lastCategory = fam.category
            local header = AcquireHeader(panel)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -y)
            header.text:SetText("|cff" .. color.hex .. (ExtractionService.CATEGORY_NAMES[fam.category] or "Other") .. "|r")
            header.count:SetText(string.format("%d / %d learned", categoryLearned[fam.category] or 0, categoryTotals[fam.category] or 0))
            header.line:SetTexture(color[1], color[2], color[3], 0.5)
            header:Show()
            panel.headerRows[#panel.headerRows + 1] = header
            y = y + GROUP_HEADER_HEIGHT + AFFIX_ROW_SPACING
        end

        local row = AcquireRow(panel)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -y)
        row:Show()
        row.highlight:Hide()
        row.affixId = affix.id
        y = y + AFFIX_ROW_HEIGHT + AFFIX_ROW_SPACING

        SetPortraitToTexture(row.icon, affix.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.stripe:SetTexture(color[1], color[2], color[3], affix.learned and 0.9 or 0.3)

        local unusable = affix.learned and GetUnusableReason(affix, allowedCats, maxRank) or nil
        local isCurrent = currentAffix and currentAffix.id == affix.id

        local name = fam.name or ("Affix " .. affix.id)
        if not affix.learned then
            row.nameText:SetText("|cff999999" .. name .. "|r")
        elseif isCurrent then
            row.nameText:SetText(name .. "  |cff00ff00(on this item)|r")
        else
            row.nameText:SetText(name)
        end
        if unusable then
            row.metaText:SetText("|cffff6060" .. unusable .. "|r")
        else
            local meta = {}
            if affix.appliedCount and affix.appliedCount > 0 then
                meta[#meta + 1] = "|cff00ff00x" .. affix.appliedCount .. "|r"
            end
            if affix.learned and affix.applyCost then
                meta[#meta + 1] = FormatCopperSmall(affix.applyCost)
            end
            row.metaText:SetText(table.concat(meta, "  "))
        end

        local selectable = affix.learned and not unusable
        row:SetAlpha((affix.learned and not unusable) and 1 or 0.55)

        row:SetScript("OnClick", function()
            if not selectable then return end
            SelectAffixRow(panel, row, affix)
        end)

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if affix.text then
                -- Static text from affixes_data.lua: no dependency on the client's Spell.dbc
                GameTooltip:SetText(affix.name, 1, 1, 1)
                GameTooltip:AddLine(ExtractionUI.RenderAffixText(affix.text) or affix.text, 1, 0.5, 0, true)
            else
                GameTooltip:SetHyperlink("spell:" .. affix.id)
            end
            GameTooltip:AddLine(" ")
            local slotText = CATEGORY_SLOT_TEXT[affix.category or 0]
            if slotText and slotText ~= "" then
                GameTooltip:AddLine("Slots: " .. slotText, 0.7, 0.7, 0.7, true)
            end
            if affix.appliedCount and affix.appliedCount > 0 then
                GameTooltip:AddLine("Applied: " .. affix.appliedCount .. " time(s)", 0.7, 0.7, 0.7)
            end
            if not affix.learned then
                GameTooltip:AddLine("Not yet learned: extract it from a piece of gear.", 0.6, 0.6, 0.6, true)
            elseif unusable then
                GameTooltip:AddLine(unusable, 1, 0.4, 0.4, true)
            elseif ExtractionUI.pendingLink then
                GameTooltip:AddLine("Click to select, then confirm to apply.", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)

        panel.affixRows[#panel.affixRows + 1] = row
        if selectable and previousSelection == affix.id then
            selectedRow, selectedAffix = row, affix
        end
    end

    panel.scrollChild:SetHeight(math.max(y, 1))

    -- Keep the selection across filter changes while its row is still listed
    if selectedRow then
        SelectAffixRow(panel, selectedRow, selectedAffix)
    end
end

function ExtractionUI.ShowSidePanel()
    if not frame.sidePanel then
        frame.sidePanel = CreateSidePanel()
    end
    ExtractionService.RequestLearnedAffixes()
    ExtractionUI.PopulateSidePanel()
    frame.sidePanel:Show()
end

------------------------------------------------------------
-- Portable Affix-Anvil (the Toolbelt): the same window with no anvil gossip
-- behind it. The server accepts extraction, engraving and the Torment upgrade
-- anywhere for its owners (ToolbeltMgr::IsNearAffixAnvil).
------------------------------------------------------------

function ExtractionUI.Toggle()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

------------------------------------------------------------
-- Gossip-based open/close
------------------------------------------------------------

local gossipEventFrame = CreateFrame("Frame")
gossipEventFrame:RegisterEvent("GOSSIP_SHOW")
gossipEventFrame:RegisterEvent("GOSSIP_CLOSED")
gossipEventFrame:SetScript("OnEvent", function(self, event)
    if event == "GOSSIP_SHOW" then
        -- Only process if GossipFrame is actually visible (real gossip interaction)
        if not GossipFrame or not GossipFrame:IsShown() then
            return
        end

        local npcName = GossipFrameNpcNameText and GossipFrameNpcNameText:GetText()
        if npcName == "Enchanted Anvil" then
            isInExtractionGossip = true
            if GossipFrame then
                GossipFrame:SetAlpha(0)
                GossipFrame:EnableMouse(false)
                GossipFrame:ClearAllPoints()
                GossipFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 1000, -1000)
            end
            frame:Show()
        else
            if isInExtractionGossip then
                isInExtractionGossip = false
                frame:Hide()
            end
        end
    elseif event == "GOSSIP_CLOSED" then
        local wasInExtractionGossip = isInExtractionGossip
        isInExtractionGossip = false
        if wasInExtractionGossip and GossipFrame then
            GossipFrame:SetAlpha(1)
            GossipFrame:EnableMouse(true)
            GossipFrame:ClearAllPoints()
            GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
        if wasInExtractionGossip then
            frame:Hide()
        end
    end
end)

-- Close extraction when other UI panels open
local function CloseExtractionIfOpen()
    if frame and frame:IsShown() then
        -- Reset GossipFrame properly
        if GossipFrame then
            GossipFrame:SetAlpha(1)
            GossipFrame:EnableMouse(true)
            GossipFrame:ClearAllPoints()
            GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
        isInExtractionGossip = false
        if GossipFrameCloseButton then
            GossipFrameCloseButton:Click()
        end
        frame:Hide()
    end
end

local framesToWatch = {
    "CharacterFrame",
    "TalentFrame",
    "SpellBookFrame",
    "QuestLogFrame",
    "QuestLogDetailFrame",
    "FriendsFrame",
    "PVPFrame",
    "AchievementFrame",
    "GuildFrame",
    "LFGParentFrame",
    "PlayerTalentFrame",
    "EbonholdTalentFrame",
    "LFDParentFrame",
    "WorldMapFrame",
    "GameMenuFrame",
}

for _, frameName in ipairs(framesToWatch) do
    local f = _G[frameName]
    if f then
        f:HookScript("OnShow", function(self)
            -- the quest tracker's invisible map pulse (alpha 0, two frames, after every quest
            -- accept / finished objective) is no panel opening: same fix as the Call Board
            if self:GetAlpha() < 0.05 then return end
            CloseExtractionIfOpen()
        end)
    end
end

------------------------------------------------------------
-- Global tooltip hook: affix lines
--   legacy  : @affix@ ... @affix@                      -> purple line
--   affix   : ... @value@3%@value@ @range@[1%-5%]@range@ -> orange line, blue value, grey range
-- On a two-handed weapon the numbers shown are doubled (x2 compensation), unless the
-- viewer has Titan Grip.
------------------------------------------------------------

local AFFIX_TAG = "@affix@"
local AFFIX_COLOR = "|cffb048f8" -- purple
local AFFIX_LINE  = "|cffff8000"    -- orange
local AFFIX_VALUE = "|cff4aa3ff"    -- blue  : the value this item rolled
local AFFIX_RANGE = "|cff9d9d9d"    -- grey  : the family's full range
local TITAN_GRIP_SPELL = 46917

local function ViewerHasTitanGrip()
    return IsSpellKnown and IsSpellKnown(TITAN_GRIP_SPELL) or false
end

local function DoubleNumbers(text)
    return (text:gsub("(%d+)([,%.]?)(%d*)", function(intPart, sep, frac)
        local v = tonumber(intPart .. (frac ~= "" and ("." .. frac) or ""))
        if not v then return intPart .. sep .. frac end
        v = v * 2
        if v == math.floor(v) then return tostring(math.floor(v)) end
        return (tostring(v):gsub("%.", sep ~= "" and sep or ","))
    end))
end

-- Renders one raw affix line. twoHanded doubles the numbers inside the markers.
function ExtractionUI.RenderAffixText(text, twoHanded)
    if not text or not text:find("@value@", 1, true) then return nil end
    -- Any colour code the client (or another addon) already put in the line would override
    -- ours from that point on: strip them, the whole line is repainted below.
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local doubled = twoHanded and not ViewerHasTitanGrip()
    text = text:gsub("@value@(.-)@value@", function(v)
        if doubled then v = DoubleNumbers(v) end
        return AFFIX_VALUE .. v .. "|r" .. AFFIX_LINE
    end)
    text = text:gsub("@range@(.-)@range@", function(r)
        if doubled then r = DoubleNumbers(r) end
        return AFFIX_RANGE .. r .. "|r" .. AFFIX_LINE
    end)
    return AFFIX_LINE .. text .. "|r"
end

local function ScanAndRecolorAffixLines(tooltip, twoHanded)
    local name = tooltip:GetName()
    for i = 1, tooltip:NumLines() do
        local leftLine = _G[name .. "TextLeft" .. i]
        if leftLine then
            local text = leftLine:GetText()
            if text and text:find("@value@", 1, true) then
                local rendered = ExtractionUI.RenderAffixText(text, twoHanded)
                if rendered then
                    leftLine:SetText(rendered)
                    leftLine:SetTextColor(1, 0.5, 0)
                    leftLine:SetWordWrap(true)
                    leftLine:SetWidth(300)
                end
            elseif text and text:find(AFFIX_TAG, 1, true) then
                local before, inner, after = text:match("^(.-)@affix@(.-)@affix@(.*)$")
                if inner then
                    local trimmed = inner:gsub("^%s+", ""):gsub("%s+$", "")
                    leftLine:SetText((before or "") .. AFFIX_COLOR .. trimmed .. "|r" .. (after or ""))
                    leftLine:SetTextColor(0.69, 0.28, 0.97)
                    leftLine:SetWordWrap(true)
                    leftLine:SetWidth(300)
                end
            end
        end
    end
end

local function OnItemTooltip(self)
    local _, link = self:GetItem()
    local twoHanded = false
    if link then
        local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
        twoHanded = equipLoc == "INVTYPE_2HWEAPON"
    end
    ScanAndRecolorAffixLines(self, twoHanded)
end

GameTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
ItemRefTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
-- Shift comparison ("currently equipped") tooltips are separate frames
for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
  local tip = _G[name]
  if tip then tip:HookScript("OnTooltipSetItem", OnItemTooltip) end
end
-- Anvil list and spellbook: the learn spell's description carries the same markers
GameTooltip:HookScript("OnTooltipSetSpell", function(self) ScanAndRecolorAffixLines(self, false) end)
ItemRefTooltip:HookScript("OnTooltipSetSpell", function(self) ScanAndRecolorAffixLines(self, false) end)
