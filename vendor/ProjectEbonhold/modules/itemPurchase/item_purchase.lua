--[[
Item Purchase Popup - Custom popup with affix selection
--]]

local Addon = select(2, ...)

------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------

-- Liste des affixes disponibles (exemple - à adapter selon votre serveur)
local AVAILABLE_AFFIXES = {
    { id = 1, name = "Plague Blessing", description = "Your attacks have a chance to infect the target, dealing Shadow damage every 3 sec for 15 sec. If the target dies before the effect expires, the infection spreads to a nearby enemy, retaining its remaining duration.", color = "|cffFF4500" },
}

------------------------------------------------------------
-- POPUP FRAME
------------------------------------------------------------

local PurchasePopup = CreateFrame("Frame", "ItemPurchasePopup", UIParent)
PurchasePopup:SetSize(420, 260)
PurchasePopup:SetPoint("CENTER")
PurchasePopup:SetFrameStrata("DIALOG")
PurchasePopup:EnableMouse(true)
PurchasePopup:SetMovable(true)
PurchasePopup:RegisterForDrag("LeftButton")
PurchasePopup:SetScript("OnDragStart", PurchasePopup.StartMoving)
PurchasePopup:SetScript("OnDragStop", PurchasePopup.StopMovingOrSizing)
PurchasePopup:Hide()

-- Background flat
PurchasePopup:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
PurchasePopup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
PurchasePopup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

-- Title (simple)
local title = PurchasePopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", PurchasePopup, "TOP", 0, -12)
title:SetText("Confirm Purchase")

-- Item Icon avec bordure simple et tooltip
local iconBorder = CreateFrame("Button", nil, PurchasePopup)
iconBorder:SetSize(48, 48)
iconBorder:SetPoint("TOPLEFT", PurchasePopup, "TOPLEFT", 20, -45)
iconBorder:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
})
iconBorder:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

local itemIcon = iconBorder:CreateTexture(nil, "ARTWORK")
itemIcon:SetSize(44, 44)
itemIcon:SetPoint("CENTER")
itemIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
PurchasePopup.itemIcon = itemIcon
PurchasePopup.iconBorder = iconBorder

-- Scripts pour le tooltip
iconBorder:SetScript("OnEnter", function(self)
    if PurchasePopup.itemLink then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(PurchasePopup.itemLink)
        GameTooltip:Show()
    end
end)
iconBorder:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

-- Item Name
local itemName = PurchasePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
itemName:SetPoint("LEFT", iconBorder, "RIGHT", 10, 10)
itemName:SetJustifyH("LEFT")
itemName:SetWidth(320)
PurchasePopup.itemName = itemName

-- Cost Info
local costInfo = PurchasePopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
costInfo:SetPoint("TOPLEFT", iconBorder, "RIGHT", 10, -10)
costInfo:SetJustifyH("LEFT")
costInfo:SetWidth(320)
PurchasePopup.costInfo = costInfo

-- Ligne séparatrice
local separator = PurchasePopup:CreateTexture(nil, "ARTWORK")
separator:SetTexture(1, 1, 1, 0.2)
separator:SetSize(380, 1)
separator:SetPoint("TOPLEFT", iconBorder, "BOTTOMLEFT", 0, -20)

-- Affix Selection Label
local affixLabel = PurchasePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
affixLabel:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 0, -15)
affixLabel:SetText("Select Affix:")

-- Dropdown pour les affixes
local affixDropdown = CreateFrame("Frame", "ItemPurchaseAffixDropdown", PurchasePopup, "UIDropDownMenuTemplate")
affixDropdown:SetPoint("LEFT", affixLabel, "RIGHT", -15, -3)
PurchasePopup.affixDropdown = affixDropdown

-- Description de l'affixe sélectionné
local affixDescription = PurchasePopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
affixDescription:SetPoint("TOPLEFT", affixLabel, "BOTTOMLEFT", 0, -15)
affixDescription:SetJustifyH("LEFT")
affixDescription:SetWidth(360)
affixDescription:SetTextColor(0.7, 0.7, 0.7, 1)
affixDescription:SetText("No additional effects")
PurchasePopup.affixDescription = affixDescription

-- Variable pour stocker l'affixe sélectionné
PurchasePopup.selectedAffix = 0

-- Fonction pour mettre à jour la description de l'affixe
local function UpdateAffixDescription(affixId)
    for _, affix in ipairs(AVAILABLE_AFFIXES) do
        if affix.id == affixId then
            PurchasePopup.affixDescription:SetText(affix.description or "")
            return
        end
    end
    PurchasePopup.affixDescription:SetText("")
end

-- Fonction pour initialiser le dropdown
local function InitializeAffixDropdown(self, level)
    local info = UIDropDownMenu_CreateInfo()

    for _, affix in ipairs(AVAILABLE_AFFIXES) do
        info.text = affix.color .. affix.name .. "|r"
        info.value = affix.id
        info.func = function(button)
            PurchasePopup.selectedAffix = button.value
            UIDropDownMenu_SetSelectedValue(affixDropdown, button.value)
            UIDropDownMenu_SetText(affixDropdown, affix.name)
            UpdateAffixDescription(button.value)
        end
        info.checked = (PurchasePopup.selectedAffix == affix.id)
        UIDropDownMenu_AddButton(info, level)
    end
end

UIDropDownMenu_Initialize(affixDropdown, InitializeAffixDropdown)
UIDropDownMenu_SetWidth(affixDropdown, 200)
UIDropDownMenu_SetSelectedValue(affixDropdown, 0)
UIDropDownMenu_SetText(affixDropdown, AVAILABLE_AFFIXES[1].name)
PurchasePopup.selectedAffix = 0 -- S'assurer que la valeur par défaut est bien définie

-- Confirm Button
local confirmBtn = CreateFrame("Button", nil, PurchasePopup, "UIPanelButtonTemplate")
confirmBtn:SetSize(120, 25)
confirmBtn:SetPoint("BOTTOM", PurchasePopup, "BOTTOM", -65, 15)
confirmBtn:SetText("Confirm")
confirmBtn:SetScript("OnClick", function()
    -- Appeler la fonction d'achat avec l'affixe sélectionné
    if PurchasePopup.onConfirm then
        PurchasePopup.onConfirm(PurchasePopup.selectedAffix)
    end
    PurchasePopup:Hide()
end)

-- Cancel Button
local cancelBtn = CreateFrame("Button", nil, PurchasePopup, "UIPanelButtonTemplate")
cancelBtn:SetSize(120, 25)
cancelBtn:SetPoint("BOTTOM", PurchasePopup, "BOTTOM", 65, 15)
cancelBtn:SetText("Cancel")
cancelBtn:SetScript("OnClick", function()
    PurchasePopup:Hide()
end)

-- Close Button
local closeBtn = CreateFrame("Button", nil, PurchasePopup, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", PurchasePopup, "TOPRIGHT", -5, -5)

------------------------------------------------------------
-- API PUBLIQUE
------------------------------------------------------------

-- Fonction pour afficher la popup
function PurchasePopup:ShowPurchase(itemButton, quantity)
    local index = itemButton:GetID()

    -- Récupérer les infos de l'item depuis le merchant
    local itemName, itemTexture, price, quantity_avail, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(index)
    local link = GetMerchantItemLink(index)

    -- Si pas de lien, essayer depuis le bouton
    if not link then
        link = itemButton.link
    end
    if not itemTexture then
        itemTexture = itemButton.texture
    end

    -- Récupérer les infos de l'item
    local itemNameText, _, itemQuality = GetItemInfo(link)
    if not itemNameText then
        itemNameText = itemName -- Fallback sur le nom du merchant
    end
    local r, g, b = GetItemQualityColor(itemQuality or 1)

    -- Afficher l'icône et le nom
    self.itemIcon:SetTexture(itemTexture)
    self.itemName:SetText(format("|c%02x%02x%02x%02x%s|r", 255, r * 255, g * 255, b * 255, itemNameText or "Unknown Item"))

    -- Colorer la bordure de l'icône selon la qualité
    self.iconBorder:SetBackdropBorderColor(r, g, b, 1)

    -- Stocker le lien pour le tooltip
    self.itemLink = link

    -- Afficher le coût
    local honorPoints, arenaPoints, itemCount = GetMerchantItemCostInfo(index)
    local costString = ""

    if honorPoints and honorPoints > 0 then
        costString = costString ..
        format("|TInterface\\PVPFrame\\PVP-Currency-Alliance:0:0:0:-1|t %d Honor", honorPoints * quantity)
    end

    if arenaPoints and arenaPoints > 0 then
        if costString ~= "" then costString = costString .. "\n" end
        costString = costString ..
        format("|TInterface\\PVPFrame\\PVP-ArenaPoints-Icon:0:0:0:-1|t %d Arena Points", arenaPoints * quantity)
    end

    -- Items requis
    for i = 1, MAX_ITEM_COST do
        local itemTexture, itemCountReq, itemLink = GetMerchantItemCostItem(index, i)
        if itemLink then
            if costString ~= "" then costString = costString .. "\n" end
            costString = costString .. format("%dx %s", itemCountReq * quantity, itemLink)
        end
    end

    if quantity > 1 then
        costString = "Quantity: " .. quantity .. "\n" .. costString
    end

    self.costInfo:SetText(costString)

    -- Réinitialiser la sélection d'affixe
    self.selectedAffix = 0
    UIDropDownMenu_SetSelectedValue(affixDropdown, 0)
    UIDropDownMenu_SetText(affixDropdown, AVAILABLE_AFFIXES[1].name)
    UpdateAffixDescription(0)

    -- Stocker les données pour l'achat
    self.itemButton = itemButton
    self.quantity = quantity

    -- Callback pour l'achat
    self.onConfirm = function(affixId)
        -- TODO: Envoyer au serveur l'affixe sélectionné avec l'achat
        print("|cff00FF00[Purchase]|r Buying item with affix ID: " .. affixId)
        BuyMerchantItem(index, quantity)

        -- Vous pouvez envoyer l'affixe au serveur ici si nécessaire
        -- ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SHOP_PURCHASE_WITH_AFFIX, index .. "|" .. quantity .. "|" .. affixId)
    end

    -- Afficher la popup
    getmetatable(self).__index.Show(self)
end

------------------------------------------------------------
-- HOOK DE LA FONCTION ORIGINALE
------------------------------------------------------------

-- Sauvegarder la fonction originale
local OriginalMerchantFrame_ConfirmExtendedItemCost = MerchantFrame_ConfirmExtendedItemCost

-- Remplacer par notre version
function MerchantFrame_ConfirmExtendedItemCost(itemButton, quantity)
    quantity = (quantity or 1)
    local index = itemButton:GetID()
    local honorPoints, arenaPoints, itemCount = GetMerchantItemCostInfo(index)

    -- Si pas de coût spécial, acheter directement
    if (honorPoints == 0) and (arenaPoints == 0) and (itemCount == 0) then
        BuyMerchantItem(index, quantity)
        return
    end

    -- Vérifier la qualité maximale des items requis
    local maxQuality = 0
    for i = 1, MAX_ITEM_COST do
        local itemTexture, itemCountReq, itemLink = GetMerchantItemCostItem(index, i)
        if itemLink then
            local _, _, itemQuality = GetItemInfo(itemLink)
            maxQuality = math.max(itemQuality or 0, maxQuality)
        end
    end

    -- Si coût simple (pas d'honor/arena et qualité basse), acheter directement
    if honorPoints == 0 and arenaPoints == 0 and maxQuality <= ITEM_QUALITY_UNCOMMON then
        BuyMerchantItem(index, quantity)
        return
    end


    -- Sinon, afficher notre popup custom
    PurchasePopup:ShowPurchase(itemButton, quantity)
end

print("|cff00FF00[ProjectEbonhold]|r Item Purchase with Affix Selection loaded.")
