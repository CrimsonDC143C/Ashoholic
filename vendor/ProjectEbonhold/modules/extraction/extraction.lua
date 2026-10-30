local addonName, addon = ...

ExtractionUI = ExtractionUI or {}

------------------------------------------------------------
-- Extractable item whitelist (only these items can be extracted)
------------------------------------------------------------

local EXTRACTABLE_ITEM_IDS_LIST = {
    12528, 12796, 11608, 28441, 28442, 6904, 13198, 13393, 4446, 4449,
    5752, 1726, 13035, 17002, 899, 5426, 6472, 13183, 1265, 17738,
    12582, 13983, 15853, 7959, 9425, 10628, 9475, 17075, 9485, 13204,
    13286, 11607, 12798, 9608, 7954, 12791, 13016, 12463, 6738, 8224,
    5616, 15814, 809, 10772, 7753, 13057, 13399, 17730, 13285, 9386,
    12243, 10797, 12992, 2915, 12792, 2299, 17193, 810, 10623, 10761,
    1481, 1482, 2256, 6831, 12250, 1318, 12974, 11121, 1387, 2912,
    3822, 28164, 2163, 3194, 17752, 19910, 1982, 13053, 19170, 13051,
    2205, 6220, 18671, 9419, 1728, 11803, 14555, 18816, 12531, 8006,
    9446, 9486, 2263, 11902, 811, 9651, 15418, 19100, 19901, 20578,
    21679, 6909, 11635, 9511, 13054, 8190, 9478, 11603, 13060, 11744,
    12583, 1986, 2164, 19918, 28573, 17766, 19324, 8225, 13032, 10803,
    14576, 934, 13401, 14024, 9423, 17112, 28437, 28438, 28439, 18203,
    27901, 29348, 31318, 2243, 11817, 29962, 12621, 11920, 19852, 31193,
    21856, 28311, 28774, 10804, 17074, 50415, 50709, 17704, 5182, 7730,
    13984, 14487, 5756, 19099, 13148, 5815, 647, 19334, 12790, 23541,
    11684, 871, 17705, 31332, 17733, 17943, 31322, 8223, 18348, 6622,
    28367, 12592, 10847, 29996, 30090, 32471, 46017, 34334, 19019, 19169,
    17182, 29182, 18410, 13246, 754, 6660, 2824, 2825, 6469, 7717, 9412, 10567, 11809, 17753
}

-- Build a fast lookup set from the array
local EXTRACTABLE_ITEM_IDS = {}
for _, id in ipairs(EXTRACTABLE_ITEM_IDS_LIST) do
    EXTRACTABLE_ITEM_IDS[id] = true
end

local function GetItemIdFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id)
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function FormatCopperSmall(copperAmount)
    if not copperAmount or copperAmount == 0 then return GetCoinTextureString(0, 10) end
    return GetCoinTextureString(copperAmount, 10)
end

-- Returns true if the item link has a random property suffix (affix / corruption)
local function HasRandomProperty(link)
    if not link then return false end
    -- Full link: |cff...|Hitem:id:enchant:gem1:gem2:gem3:gem4:suffixId:uniqueId:level:...|h[Name]|h|r
    -- strsplit(":") field 1 = "|cff...|Hitem", field 2 = id, ..., field 8 = suffixId
    local randomProp = select(8, strsplit(":", link))
    if randomProp then
        randomProp = tonumber(randomProp)
        if randomProp and randomProp ~= 0 then
            return true
        end
    end
    return false
end

-- Hidden tooltip for scanning equipped item affix text
local scanTooltip = CreateFrame("GameTooltip", "EbonholdAffixScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")


-- Find the learned affix on the given item link by scanning its tooltip
local function FindItemAffix(link)
    if not link or not HasRandomProperty(link) then return nil end
    local affixes = ExtractionService.learnedAffixes or {}
    if #affixes == 0 then return nil end

    local nameToAffix = {}
    for _, affix in ipairs(affixes) do
        if affix.name then
            nameToAffix[affix.name:lower()] = affix
        end
    end

    scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTooltip:ClearLines()
    scanTooltip:SetHyperlink(link)
    for j = 1, scanTooltip:NumLines() do
        local lineObj = _G["EbonholdAffixScanTooltipTextLeft" .. j]
        if lineObj then
            local text = lineObj:GetText()
            if text then
                local lower = text:lower()
                for name, affix in pairs(nameToAffix) do
                    local startPos, endPos = lower:find(name, 1, true)
                    if startPos then
                        local before = startPos > 1 and lower:sub(startPos - 1, startPos - 1) or ""
                        local after = lower:sub(endPos + 1, endPos + 1)
                        if (before == "" or not before:match("%w")) and (after == "" or not after:match("%w")) then
                            return affix
                        end
                    end
                end
            end
        end
    end
    return nil
end

------------------------------------------------------------
-- Confirmation dialog
------------------------------------------------------------

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
    extractBtn:SetText("Extract")
    extractBtn:Disable()
    extractBtn:Hide()
    applyBtn:SetText("Choose an Affix")
    applyBtn:Disable()
    applyBtn:Hide()
    HideSidePanel()
end

local function UpdateButtonVisibility()
    if not ExtractionUI.pendingLink then
        extractBtn:Hide()
        applyBtn:Hide()
        return
    end

    local hasAffix = HasRandomProperty(ExtractionUI.pendingLink)
    local placedItemId = GetItemIdFromLink(ExtractionUI.pendingLink)
    local isWhitelisted = placedItemId and EXTRACTABLE_ITEM_IDS[placedItemId]

    -- Apply is allowed for any equipable item placed in the slot
    local canApply = true

    -- Extract: whitelisted items or any item with an affix can be extracted
    local itemAffix = hasAffix and FindItemAffix(ExtractionUI.pendingLink) or nil
    local alreadyLearned = itemAffix and itemAffix.learned
    local canExtract = isWhitelisted or hasAffix

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

    -- Position buttons side by side or centered
    extractBtn:ClearAllPoints()
    applyBtn:ClearAllPoints()
    if canExtract and canApply then
        extractBtn:SetPoint("LEFT", frame.bottomBar, "LEFT", 14, 30)
        applyBtn:SetPoint("RIGHT", frame.bottomBar, "RIGHT", -14, 30)
    elseif canExtract then
        extractBtn:SetPoint("CENTER", frame.bottomBar, "CENTER", 0, 30)
    elseif canApply then
        applyBtn:SetPoint("CENTER", frame.bottomBar, "CENTER", 0, 30)
    end
end

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
    local placedId = GetItemIdFromLink(ExtractionUI.pendingLink)
    local isWhitelisted = placedId and EXTRACTABLE_ITEM_IDS[placedId]
    local hasAffixOnItem = HasRandomProperty(ExtractionUI.pendingLink)
    if ExtractionUI.pendingLink and (isWhitelisted or hasAffixOnItem) then
        extractBtn:SetText("Extract  " .. extractCoinStr)
    else
        extractBtn:SetText("Extract")
    end

    -- Update Apply button text: if affix selected, show "Apply Affix" + per-affix cost
    local itemHasAffix = HasRandomProperty(ExtractionUI.pendingLink)
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

    ExtractionService.RequestExtractionInfo(bag, slotIdx)
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
------------------------------------------------------------

local SIDE_PANEL_WIDTH = 260
local AFFIX_ROW_HEIGHT = 28
local AFFIX_ROW_SPACING = 6

local function CreateSidePanel()
    local panel = CreateFrame("Frame", "EbonholdAffixBookPanel", frame)
    panel:SetSize(SIDE_PANEL_WIDTH, FRAME_HEIGHT)
    panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", -2, 0)
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:SetFrameLevel(frame:GetFrameLevel() + 1)
    panel:EnableMouse(true)
    panel:SetResizable(true)
    panel:SetMinResize(SIDE_PANEL_WIDTH, 200)
    panel:SetMaxResize(SIDE_PANEL_WIDTH, 800)
    panel:Hide()

    -- Resize grip at the bottom
    local resizeGrip = CreateFrame("Frame", nil, panel)
    resizeGrip:SetSize(SIDE_PANEL_WIDTH - 16, 8)
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
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOP", panel, "TOP", 0, -25)
    panel.title:SetText("Affix Book")

    -- Search bar
    local searchBox = CreateFrame("EditBox", "EbonholdAffixSearchBox", panel, "InputBoxTemplate")
    searchBox:SetSize(SIDE_PANEL_WIDTH - 50, 20)
    searchBox:SetPoint("TOP", panel.title, "BOTTOM", 0, -6)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetTextInsets(4, 16, 0, 0)

    -- Placeholder text
    searchBox.placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchBox.placeholder:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    searchBox.placeholder:SetText("Search...")

    -- Clear button
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

    -- "Learned only" checkbox
    local learnedCB = CreateFrame("CheckButton", "EbonholdAffixLearnedCheck", panel, "ChatConfigCheckButtonTemplate")
    learnedCB:SetSize(24, 24)
    learnedCB:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -2, -2)
    learnedCB:SetChecked(true)
    _G[learnedCB:GetName() .. "Text"]:SetText("Learned only")
    _G[learnedCB:GetName() .. "Text"]:SetFontObject("GameFontNormalSmall")
    learnedCB:SetScript("OnClick", function()
        ExtractionUI.PopulateSidePanel()
    end)
    panel.learnedCB = learnedCB

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "EbonholdAffixBookScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", learnedCB, "BOTTOMLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -36, 56)
    panel.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    panel.scrollChild = scrollChild

    -- Empty text
    panel.emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.emptyText:SetPoint("CENTER", scrollChild, "CENTER", 0, -15)
    panel.emptyText:SetText("No Affixes learned.\nTo learn more, extract them\nfrom any piece of gear.")
    panel.emptyText:Hide()

    -- Confirm button at bottom of side panel
    panel.confirmBtn = utils.CreateCustomButton(nil, panel, { width = 190, height = 30 }, "Confirm Apply", function()
        if ExtractionUI.pendingBag and ExtractionUI.pendingSlot and ExtractionUI.selectedAffixId then
            StaticPopup_Show("EBONHOLD_CONFIRM_APPLY_AFFIX")
        end
    end)
    panel.confirmBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 20)
    panel.confirmBtn:Disable()
    if panel.confirmBtn.text then panel.confirmBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 10) end
    panel.affixRows = {}
    panel._recycledRows = {}
    return panel
end

function ExtractionUI.PopulateSidePanel()
    local panel = frame.sidePanel
    if not panel then return end

    -- Recycle old rows instead of leaking them
    for _, row in ipairs(panel.affixRows) do
        row:Hide()
        row:ClearAllPoints()
        table.insert(panel._recycledRows, row)
    end
    panel.affixRows = {}
    ExtractionUI.selectedAffixId = nil
    panel.confirmBtn:Disable()

    local affixes = ExtractionService.learnedAffixes or {}

    -- Determine if placed item is a weapon
    local isWeapon = false
    if ExtractionUI.pendingLink then
        local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(ExtractionUI.pendingLink)
        if itemEquipLoc then
            isWeapon = itemEquipLoc == "INVTYPE_WEAPON" or itemEquipLoc == "INVTYPE_2HWEAPON"
                or itemEquipLoc == "INVTYPE_WEAPONMAINHAND" or itemEquipLoc == "INVTYPE_WEAPONOFFHAND"
                or itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT"
                or itemEquipLoc == "INVTYPE_THROWN" or itemEquipLoc == "INVTYPE_SHIELD"
                or itemEquipLoc == "INVTYPE_HOLDABLE" or itemEquipLoc == "INVTYPE_RELIC"
        end
    end

    -- Filter by search text, learned checkbox, and weapon-only compatibility
    local searchText = panel.searchBox and panel.searchBox:GetText() or ""
    searchText = searchText:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local learnedOnly = panel.learnedCB and panel.learnedCB:GetChecked()
    local filtered = {}
    for _, affix in ipairs(affixes) do
        local matchesSearch = searchText == "" or (affix.name and affix.name:lower():find(searchText, 1, true))
        local matchesLearned = not learnedOnly or affix.learned
        local matchesSlot = not affix.weaponOnly or isWeapon
        if matchesSearch and matchesLearned and matchesSlot then
            table.insert(filtered, affix)
        end
    end

    local totalRowHeight = AFFIX_ROW_HEIGHT + AFFIX_ROW_SPACING
    local contentHeight = math.max(#filtered * totalRowHeight, 1)
    panel.scrollChild:SetHeight(contentHeight)

    if #filtered == 0 then
        panel.emptyText:Show()
    else
        panel.emptyText:Hide()
    end

    for i, affix in ipairs(filtered) do
        local row = table.remove(panel._recycledRows)
        if not row then
            row = CreateFrame("Button", nil, panel.scrollChild)
            row:SetSize(panel.scrollChild:GetWidth(), AFFIX_ROW_HEIGHT)

            row.highlight = row:CreateTexture(nil, "BACKGROUND")
            row.highlight:SetAllPoints()
            row.highlight:SetTexture(1, 1, 1, 0.15)

            row.hoverTex = row:CreateTexture(nil, "HIGHLIGHT")
            row.hoverTex:SetAllPoints()
            row.hoverTex:SetTexture(1, 1, 1, 0.08)

            local iconSize = AFFIX_ROW_HEIGHT - 4
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(iconSize, iconSize)
            row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

            row.iconBorder = row:CreateTexture(nil, "OVERLAY")
            row.iconBorder:SetSize(iconSize + 32, iconSize + 32)
            row.iconBorder:SetPoint("CENTER", row.icon, "CENTER")
            row.iconBorder:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder")

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.nameText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -(i - 1) * (AFFIX_ROW_HEIGHT + AFFIX_ROW_SPACING))
        row:Show()
        row.highlight:Hide()
        row.affixId = affix.id

        if affix.icon then
            SetPortraitToTexture(row.icon, affix.icon)
        else
            SetPortraitToTexture(row.icon, "Interface\\Icons\\INV_Misc_QuestionMark")
        end

        local displayName = affix.name or ("Affix " .. affix.id)
        if affix.appliedCount and affix.appliedCount > 0 then
            displayName = displayName .. "  |cff00ff00(x" .. affix.appliedCount .. ")|r"
        end
        if affix.weaponOnly then
            displayName = displayName .. "  |cffff8800(H)|r"
        end
        if not affix.learned then
            displayName = "|cff999999" .. (affix.name or ("Affix " .. affix.id)) .. "|r"
        end
        row.nameText:SetText(displayName)

        -- Click to select
        row:SetScript("OnClick", function()
            if not affix.learned then return end
            -- Deselect all
            for _, r in ipairs(panel.affixRows) do
                r.highlight:Hide()
            end
            -- Select this one
            row.highlight:Show()
            ExtractionUI.selectedAffixId = affix.id
            -- Show cost from affix data directly
            local coinStr = affix.applyCost and FormatCopperSmall(affix.applyCost) or ""
            panel.confirmBtn:SetText("Confirm  " .. coinStr)
            -- Check if same affix is already on the item
            local isSameAffix = false
            if ExtractionUI.pendingLink then
                local currentAffix = FindItemAffix(ExtractionUI.pendingLink)
                if currentAffix and currentAffix.id == affix.id then
                    isSameAffix = true
                end
            end
            if isSameAffix then
                panel.confirmBtn:Disable()
            else
                panel.confirmBtn:Enable()
            end
            -- Store apply cost for the main button display
            ExtractionService.applyCost = affix.applyCost
            UpdateCostDisplay()
        end)

        -- Tooltip
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if affix.learned then
                GameTooltip:SetHyperlink("spell:" .. affix.id)
                if affix.appliedCount and affix.appliedCount > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Applied: " .. affix.appliedCount .. " time(s)", 0.7, 0.7, 0.7)
                end
                if affix.weaponOnly then
                    GameTooltip:AddLine("Hands Only", 1.0, 0.53, 0.0)
                end
            else
                GameTooltip:SetHyperlink("spell:" .. affix.id)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Not yet learned", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        panel.affixRows[i] = row
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
    "LFDParentFrame",
    "WorldMapFrame",
    "GameMenuFrame",
}

for _, frameName in ipairs(framesToWatch) do
    local f = _G[frameName]
    if f then
        f:HookScript("OnShow", CloseExtractionIfOpen)
    end
end

------------------------------------------------------------
-- Global tooltip hook: recolor @affix@ lines to purple
------------------------------------------------------------

local AFFIX_TAG = "@affix@"
local AFFIX_COLOR = "|cffb048f8" -- purple

local function ScanAndRecolorAffixLines(tooltip)
    local name = tooltip:GetName()
    for i = 1, tooltip:NumLines() do
        local leftLine = _G[name .. "TextLeft" .. i]
        if leftLine then
            local text = leftLine:GetText()
            if text and text:find(AFFIX_TAG, 1, true) then
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

GameTooltip:HookScript("OnTooltipSetItem", function(self)
    ScanAndRecolorAffixLines(self)
end)

ItemRefTooltip:HookScript("OnTooltipSetItem", function(self)
    ScanAndRecolorAffixLines(self)
end)
