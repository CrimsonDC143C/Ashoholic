local addon, Addon = ...


local playerRunData = {
    countCanSelfRezs = 0,
    countCanClassRezs = 0,
    costNextReset = 100,
    soulPoints = 0,
    soulShards = 0
}


local deathFrame = nil
local isDeathFrameInitialized = false
local resRequest = false
local isPlayerBlocked = false


local DeathTexts = ProjectEbonhold.DeathTexts

local function GetCurrentPlayerRunData()
    return ProjectEbonhold.PlayerRunService.GetCurrentData() or {}
end

function Addon.UpdateData(data)
    if deathFrame and deathFrame:IsVisible() then
        for _, button in pairs(deathFrame.buttons) do
            if button then
                button:SetParent(nil)
                button:Hide()
                button = nil
            end
        end
        deathFrame.buttons = {}


        UpdateDeathFrameButtons()

        deathFrame:Hide()
        deathFrame:Show()
    end
end

local function CreateDeathFrame()
    if isDeathFrameInitialized then return end


    deathFrame = CreateFrame("Frame", "ProjectEbonholdDeathFrame", UIParent)
    deathFrame:SetSize(320, 200)
    deathFrame:SetPoint("CENTER", 0, 0)
    deathFrame:SetFrameStrata("DIALOG")
    deathFrame:SetFrameLevel(100)
    deathFrame:EnableMouse(true)
    deathFrame:SetMovable(true)


    local dynamicBg = utils.CreateDeathFrameBackground(deathFrame, 320, 200)
    dynamicBg:SetPoint("CENTER", deathFrame, "CENTER", 0, 0)
    deathFrame.dynamicBackground = dynamicBg


    local title = deathFrame:CreateFontString(nil, "OVERLAY",
        "GameFontNormalLarge")
    title:SetPoint("TOP", deathFrame, "TOP", 0, -50)
    title:SetText("You are dead")
    title:SetTextColor(1, 0.2, 0.2)
    deathFrame.title = title


    local buttonContainer = CreateFrame("Frame", nil, deathFrame)
    buttonContainer:SetSize(300, 150)
    buttonContainer:SetPoint("TOP", title, "BOTTOM", 0, -10)
    deathFrame.buttonContainer = buttonContainer


    deathFrame.buttons = {}

    -- The recap panel rides along with the death frame. Every confirmation popup and the item
    -- selection frame hide and re-show the death frame, so hooking visibility keeps the two in
    -- sync without touching each of those call sites.
    deathFrame:SetScript("OnShow", function()
        if ProjectEbonhold.DeathRecap then
            ProjectEbonhold.DeathRecap.ShowForDeathFrame()
        end
    end)
    deathFrame:SetScript("OnHide", function()
        if ProjectEbonhold.DeathRecap then
            ProjectEbonhold.DeathRecap.Hide()
        end
    end)

    deathFrame:Hide()
    isDeathFrameInitialized = true
end


local function CreateDeathButton(name, parent, text, onClick)
    local button =
        utils.CreateSimpleCustomButton(parent, text, onClick, 250, 45)
    return button
end


local function ShowConfirmationPopup(title, message, onConfirm)
    if deathFrame then deathFrame:Hide() end
    local popup = CreateFrame("Frame", "ProjectEbonholdConfirmPopup", UIParent)
    popup:SetSize(400, 200)
    popup:SetPoint("CENTER", UIParent, "CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(1000)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

    popup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })


    local popupTitle = popup:CreateFontString(nil, "OVERLAY",
        "GameFontNormalLarge")
    popupTitle:SetPoint("TOP", popup, "TOP", 0, -20)
    popupTitle:SetText(title)
    popupTitle:SetTextColor(1, 1, 0)


    local popupMessage =
        popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popupMessage:SetPoint("TOP", popupTitle, "BOTTOM", 0, -15)
    popupMessage:SetWidth(350)
    popupMessage:SetJustifyH("CENTER")
    popupMessage:SetText(message)
    popupMessage:SetTextColor(1, 1, 1)

    -- Grow with the message so long texts never run under the buttons:
    -- title (20 + its height) + 15 + message + 20 gap + buttons (30) + 25 bottom.
    popup:SetHeight(math.max(200, 20 + popupTitle:GetStringHeight() + 15
        + popupMessage:GetStringHeight() + 20 + 30 + 25))


    local yesButton = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    yesButton:SetSize(100, 30)
    yesButton:SetPoint("BOTTOM", popup, "BOTTOM", -60, 25)
    yesButton:SetText("Yes")
    yesButton:SetFrameStrata("FULLSCREEN_DIALOG")
    yesButton:SetFrameLevel(1100)
    yesButton:SetScript("OnClick", function()
        popup:Hide()

        if deathFrame then deathFrame:Show() end
        onConfirm()
    end)


    local noButton = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    noButton:SetSize(100, 30)
    noButton:SetPoint("BOTTOM", popup, "BOTTOM", 60, 25)
    noButton:SetText("No")
    noButton:SetFrameStrata("FULLSCREEN_DIALOG")
    noButton:SetFrameLevel(1100)
    noButton:SetScript("OnClick", function()
        popup:Hide()

        if deathFrame then deathFrame:Show() end
    end)

    popup:Show()
end


local function GetAllPlayerItems()
    local items = {}

    local slotNames = {
        [1] = "Head",
        [2] = "Neck",
        [3] = "Shoulder",
        [5] = "Chest",
        [6] = "Waist",
        [7] = "Legs",
        [8] = "Feet",
        [9] = "Wrist",
        [10] = "Hands",
        [11] = "Finger 1",
        [12] = "Finger 2",
        [13] = "Trinket 1",
        [14] = "Trinket 2",
        [15] = "Back",
        [16] = "Main Hand",
        [17] = "Off Hand",
        [18] = "Ranged",
        [19] = "Tabard"
    }

    for slot = 0, 19 do
        local itemLink = GetInventoryItemLink("player", slot)
        if itemLink then
            local itemTexture = GetInventoryItemTexture("player", slot)
            local itemName, _, itemRarity, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemLink)


            local itemEntry = itemLink:match("item:(%d+)")
            itemEntry = tonumber(itemEntry) or 0

            if itemName and itemEntry > 0 then
                local isLowQuality = (itemRarity or 0) <= 1
                local hasNoSellValue = (sellPrice or 0) == 1

                if not (isLowQuality and hasNoSellValue) then
                    table.insert(items, {
                        link = itemLink,
                        name = itemName,
                        count = 1,
                        texture = itemTexture,
                        rarity = itemRarity or 0,
                        slot = slot,
                        slotName = slotNames[slot] or "Slot " .. slot,
                        itemEntry = itemEntry
                    })
                end
            end
        end
    end
    return items
end


local function HasEnoughInventorySpace()
    local freeSlots = 0
    for bag = 0, 4 do
        local numFreeSlots = GetContainerNumFreeSlots(bag)
        freeSlots = freeSlots + (numFreeSlots or 0)
    end

    -- Compter le nombre d'items équipés qui vont être récupérés
    local equippedItems = GetAllPlayerItems()
    local neededSlots = #equippedItems

    -- On a assez d'espace si le nombre de slots libres >= nombre d'items équipés
    local hasSpace = freeSlots >= neededSlots

    return freeSlots, hasSpace
end


local function ResetEchoesDisplay()
    if ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks then
        ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks(true)
    end
end


local itemSelectionFrame = nil


local function CreateItemSelectionFrame()
    if itemSelectionFrame then return itemSelectionFrame end

    local frame = CreateFrame("Frame", "ProjectEbonholdItemSelectionFrame", UIParent)
    frame:SetSize(320, 450)
    frame:SetPoint("CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(101)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)


    local dynamicBg = utils.CreateDeathFrameBackground(frame, 320, 450)
    dynamicBg:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.dynamicBackground = dynamicBg


    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -50)
    title:SetText("You don't have enough space")
    title:SetTextColor(1, 0.2, 0.2)
    frame.title = title


    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -10)
    subtitle:SetText("Please select which item you want to keep,\nor make space in your bag")
    subtitle:SetTextColor(1, 1, 1, 0.7)
    subtitle:SetJustifyH("CENTER")
    frame.subtitle = subtitle


    local scrollFrame = CreateFrame("ScrollFrame", "ProjectEbonholdItemScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -110)
    scrollFrame:SetPoint("BOTTOMRIGHT", -40, 120)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(400, 1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild


    local buttonFrame = CreateFrame("Frame", nil, frame)
    buttonFrame:SetSize(300, 100)
    buttonFrame:SetPoint("BOTTOM", 0, 10)


    local confirmBtn = utils.CreateSimpleCustomButton(buttonFrame, "Confirm Selection", nil, 250, 45)
    confirmBtn:SetPoint("TOP", 0, 0)
    frame.confirmButton = confirmBtn


    local cancelBtn = utils.CreateSimpleCustomButton(buttonFrame, "Cancel", function()
        frame:Hide()
        if deathFrame then deathFrame:Show() end
    end, 250, 45)
    cancelBtn:SetPoint("TOP", confirmBtn, "BOTTOM", 0, -5)

    frame.itemRows = {}


    for i = 1, 20 do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetSize(420, 30)


        local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        checkbox:SetSize(24, 24)
        checkbox:SetPoint("LEFT", 5, 0)
        row.checkbox = checkbox


        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
        row.icon = icon


        local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        row.name = name


        row:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)


        row:EnableMouse(true)
        row:SetScript("OnMouseDown", function(self)
            self.checkbox:SetChecked(not self.checkbox:GetChecked())
        end)

        row:Hide()
        table.insert(frame.itemRows, row)
    end

    -- A dead player cannot reach a vendor: this opens the list of bag items he can sell from here.
    local sellBtn = utils.CreateSimpleCustomButton(frame, "Sell bag items", function()
        if ProjectEbonhold.DeathSellFrame then ProjectEbonhold.DeathSellFrame.Toggle(frame) end
    end, 150, 26)
    sellBtn:SetPoint("TOP", frame, "TOP", 0, -18)
    frame.sellButton = sellBtn

    frame:SetScript("OnHide", function()
        if ProjectEbonhold.DeathSellFrame then ProjectEbonhold.DeathSellFrame.Hide() end
    end)

    frame:Hide()
    itemSelectionFrame = frame
    return frame
end


-- Selling while dead (owner, 2026-10-22): at accept death the worn gear goes to the bags, and a
-- full bag means losing pieces. The player is a corpse and cannot walk to a vendor, so the bag
-- items with a vendor price are listed here and sold one click at a time (server:
-- ItemsManager::SellBagItemWhileDead, dead players only). Selling only, no buying or repair.
do
    local ROW_HEIGHT = 26
    local sellFrame

    local function CollectSellableItems()
        local list = {}
        for bag = 0, 4 do
            for slot = 1, (GetContainerNumSlots(bag) or 0) do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local texture, count, locked = GetContainerItemInfo(bag, slot)
                    local name, _, rarity, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link)
                    local entry = tonumber(link:match("item:(%d+)")) or 0
                    if name and entry > 0 and (sellPrice or 0) > 0 and not locked then
                        table.insert(list, {
                            bag = bag, slot = slot, entry = entry, link = link, name = name,
                            texture = texture, count = count or 1, rarity = rarity or 1,
                            price = sellPrice * (count or 1),
                        })
                    end
                end
            end
        end
        table.sort(list, function(a, b) return a.price < b.price end)
        return list
    end

    local function CreateRow(parent, index)
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(250, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 2, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.name:SetWidth(120)
        row.name:SetJustifyH("LEFT")

        row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.price:SetPoint("RIGHT", -2, 0)
        row.price:SetJustifyH("RIGHT")

        row:SetScript("OnEnter", function(self)
            if self.item then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.item.link)
                GameTooltip:AddLine("Click to sell.", 0.4, 1, 0.4)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            local item = self.item
            if not item or not UnitIsDeadOrGhost("player") then return end
            ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_DEATH_SELL_ITEM,
                item.bag .. "," .. item.slot .. "," .. item.entry)
            self:Disable()
            self:SetAlpha(0.4)
        end)
        return row
    end

    local function Refresh()
        if not sellFrame or not sellFrame:IsShown() then return end
        local items = CollectSellableItems()
        for i, item in ipairs(items) do
            local row = sellFrame.rows[i] or CreateRow(sellFrame.scrollChild, i)
            sellFrame.rows[i] = row
            row.item = item
            row.icon:SetTexture(item.texture)
            local label = item.count > 1 and (item.name .. " x" .. item.count) or item.name
            row.name:SetText(label)
            local r, g, b = GetItemQualityColor(item.rarity)
            row.name:SetTextColor(r, g, b)
            row.price:SetText(GetCoinTextureString(item.price))
            row:Enable()
            row:SetAlpha(1)
            row:Show()
        end
        for i = #items + 1, #sellFrame.rows do
            sellFrame.rows[i].item = nil
            sellFrame.rows[i]:Hide()
        end
        sellFrame.scrollChild:SetHeight(math.max(1, #items * ROW_HEIGHT))
        if #items == 0 then sellFrame.empty:Show() else sellFrame.empty:Hide() end
    end

    local function Create()
        local f = CreateFrame("Frame", "ProjectEbonholdDeathSellFrame", UIParent)
        f:SetSize(300, 450)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(101)
        f:EnableMouse(true)

        local bg = utils.CreateDeathFrameBackground(f, 300, 450)
        bg:SetPoint("CENTER", f, "CENTER", 0, 0)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", f, "TOP", 0, -50)
        title:SetText("Sell bag items")

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
        hint:SetWidth(240)
        hint:SetText("Click an item to sell it at its vendor price.")
        hint:SetTextColor(1, 1, 1, 0.7)

        local scroll = CreateFrame("ScrollFrame", "ProjectEbonholdDeathSellScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -100)
        scroll:SetPoint("BOTTOMRIGHT", -40, 70)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(250, 1)
        scroll:SetScrollChild(child)
        f.scrollChild = child
        f.rows = {}

        f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        f.empty:SetPoint("TOP", scroll, "TOP", 0, -20)
        f.empty:SetText("Nothing to sell.")

        local close = utils.CreateSimpleCustomButton(f, "Close", function() f:Hide() end, 200, 40)
        close:SetPoint("BOTTOM", 0, 20)

        f:RegisterEvent("BAG_UPDATE")
        f:SetScript("OnEvent", Refresh)
        f:SetScript("OnShow", Refresh)
        f:Hide()
        return f
    end

    ProjectEbonhold.DeathSellFrame = {
        Toggle = function(anchor)
            sellFrame = sellFrame or Create()
            if sellFrame:IsShown() then
                sellFrame:Hide()
                return
            end
            sellFrame:ClearAllPoints()
            sellFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
            sellFrame:Show()
        end,
        Hide = function()
            if sellFrame then sellFrame:Hide() end
        end,
    }
end


local function ShowItemSelectionFrame(items, freeSlots, onConfirm)
    local frame = CreateItemSelectionFrame()


    local function UpdateConfirmButton()
        local currentFreeSlots = 0
        for i = 0, 4 do
            currentFreeSlots = currentFreeSlots + (GetContainerNumFreeSlots(i) or 0)
        end

        local selectedCount = 0
        for i = 1, #items do
            local row = frame.itemRows[i]
            if row and row:IsShown() and row.checkbox:GetChecked() then
                selectedCount = selectedCount + 1
            end
        end


        if selectedCount > currentFreeSlots then
            frame.confirmButton:Disable()
            frame.confirmButton:SetAlpha(0.5)
        else
            frame.confirmButton:Enable()
            frame.confirmButton:SetAlpha(1.0)
        end
    end


    frame:SetScript("OnUpdate", function(self, elapsed)
        if ProjectEbonhold_IsClosing then return end
        elapsed = math.min(elapsed, 0.1) -- Cap elapsed to prevent freeze after alt-tab
        self.timeSinceLastUpdate = (self.timeSinceLastUpdate or 0) + elapsed
        if self.timeSinceLastUpdate >= 0.5 then
            self.timeSinceLastUpdate = 0
            UpdateConfirmButton()
        end
    end)


    for _, row in ipairs(frame.itemRows) do
        row:Hide()
    end

    local yOffset = -10
    for i, item in ipairs(items) do
        local row = frame.itemRows[i]
        if row then
            row:SetPoint("TOPLEFT", 5, yOffset)
            row.checkbox:SetChecked(true)
            row.icon:SetTexture(item.texture)
            row.name:SetText("[" .. item.slotName .. "] " .. item.name)


            local r, g, b = GetItemQualityColor(item.rarity)
            row.name:SetTextColor(r, g, b)


            row.checkbox:SetScript("OnClick", UpdateConfirmButton)

            row.item = item
            row.itemLink = item.link
            row:Show()
            yOffset = yOffset - 32
        end
    end


    frame.scrollChild:SetHeight(math.max(1, #items * 32 + 20))


    UpdateConfirmButton()


    frame.confirmButton:SetScript("OnClick", function()
        local selectedItems = {}
        for i = 1, #items do
            local row = frame.itemRows[i]
            if row and row:IsShown() and row.checkbox:GetChecked() then
                table.insert(selectedItems, row.item)
            end
        end
        frame:Hide()
        onConfirm(selectedItems)
    end)

    frame:Show()
    if deathFrame then deathFrame:Hide() end
end


-- Kept out of deathFrame.buttons on purpose: that list is wiped and its entries re-parented to
-- nil on every refresh, and this button needs to outlive that.
local recapButton = nil

local function UpdateRecapButton()
    local recap = ProjectEbonhold.DeathRecap
    if not recap or not recap.HasRecap() then
        if recapButton then recapButton:Hide() end
        return 0
    end

    if not recapButton then
        -- Same 250x45 as the stacked options: a shorter button next to them just read as broken.
        recapButton = utils.CreateSimpleCustomButton(deathFrame.buttonContainer,
            ProjectEbonhold.DeathRecapTexts.button, function()
                ProjectEbonhold.DeathRecap.Toggle()
            end, 250, 45)

        -- CreateCustomButton centres its label, so the label is nudged right by half the skull
        -- and gap to keep the icon and text centred as a pair.
        local skullSize, skullGap = 22, 6
        recapButton.text:ClearAllPoints()
        recapButton.text:SetPoint("CENTER", recapButton, "CENTER",
            (skullSize + skullGap) / 2, 0)

        local skull = recapButton:CreateTexture(nil, "OVERLAY")
        skull:SetSize(skullSize, skullSize)
        skull:SetPoint("RIGHT", recapButton.text, "LEFT", -skullGap, 0)
        skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        recapButton.skull = skull
    end

    recapButton:ClearAllPoints()
    recapButton:SetPoint("TOP", 0, -10 - (#deathFrame.buttons * 50))
    recapButton:Show()
    return 50
end


function UpdateDeathFrameButtons()
    if not deathFrame then return end

    for _, button in pairs(deathFrame.buttons) do button:Hide() end
    deathFrame.buttons = {}
    deathFrame.buttonContainer:Show()
    if recapButton then recapButton:Hide() end

    -- Blocked / stuck state: replace all options with a single Unstuck button
    if isPlayerBlocked then
        deathFrame.title:SetText("|cFFFF4500You are stuck!|r")

        local unstuckButton = CreateDeathButton("unstuck", deathFrame.buttonContainer,
            "Unstuck", function()
                ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_UNLOCK_PLAYER, "")
                deathFrame:Hide()
            end)
        unstuckButton:SetPoint("TOP", 0, -10)
        table.insert(deathFrame.buttons, unstuckButton)

        local baseHeight = 120
        local finalHeight = math.max(200, baseHeight + 50)
        deathFrame:SetHeight(finalHeight)
        if deathFrame.dynamicBackground then
            deathFrame.dynamicBackground:Resize(320, finalHeight)
        end
        return
    end

    local currentData = GetCurrentPlayerRunData()

    deathFrame.buttonContainer:Show()

    local yOffset = -10
    local buttonHeight = 50


    local isArena = IsActiveBattlefieldArena and IsActiveBattlefieldArena() or
        false
    local inBattleground = UnitInBattleground("player") ~= nil

    if isArena or inBattleground then
        if isArena then
            deathFrame.title:SetText(DeathTexts.frame.arenaTitle)
        else
            deathFrame.title:SetText(DeathTexts.frame.battlegroundTitle or
                "You are dead")
        end

        local releaseButton = CreateDeathButton("pvp_release",
            deathFrame.buttonContainer,
            DeathTexts.buttons.releaseSpirit,
            function()
                if isArena then
                    local info = ChatTypeInfo["SYSTEM"]
                    DEFAULT_CHAT_FRAME:AddMessage(
                        DeathTexts.messages.arenaSpectator(), info.r, info.g,
                        info.b, info.id)
                end
                RepopMe()
                deathFrame:Hide()
            end)
        releaseButton:SetPoint("TOP", 0, yOffset)
        table.insert(deathFrame.buttons, releaseButton)
    else
        deathFrame.title:SetText(DeathTexts.frame.title)


        local soulPointsGain = currentData.soulPoints or 0
        -- Run Soul Shards are banked with the ashes on accept death (same life cycle)
        local soulShardsGain = currentData.soulShards or 0

        local acceptDeathButton = CreateDeathButton("accepteDeath",
            deathFrame.buttonContainer,
            DeathTexts.buttons
            .acceptDeath(
                soulPointsGain, soulShardsGain),
            function()
                local freeSlots, hasSpace = HasEnoughInventorySpace()

                if not hasSpace then
                    local playerItems = GetAllPlayerItems()

                    if #playerItems == 0 then
                        ShowConfirmationPopup(DeathTexts.confirmations.acceptDeath.title,
                            DeathTexts.confirmations.acceptDeath.message(soulPointsGain, soulShardsGain),
                            function()
                                ProjectEbonhold.PlayerRunService.AcceptDeath("")
                                ResetEchoesDisplay()
                                deathFrame:Hide()
                            end)
                    else
                        ShowItemSelectionFrame(playerItems, freeSlots, function(selectedItems)
                            local itemEntries = {}
                            for _, item in ipairs(selectedItems) do
                                if item.itemEntry then
                                    table.insert(itemEntries, tostring(item.itemEntry))
                                end
                            end

                            local itemData = table.concat(itemEntries, ",")

                            ShowConfirmationPopup(DeathTexts.confirmations.acceptDeath.title,
                                DeathTexts.confirmations.acceptDeath.message(soulPointsGain, soulShardsGain),
                                function()
                                    ProjectEbonhold.PlayerRunService.AcceptDeath(itemData)
                                    ResetEchoesDisplay()
                                    deathFrame:Hide()
                                end)
                        end)
                    end
                else
                    ShowConfirmationPopup(DeathTexts.confirmations.acceptDeath.title,
                        DeathTexts.confirmations.acceptDeath.message(soulPointsGain, soulShardsGain),
                        function()
                            ProjectEbonhold.PlayerRunService.AcceptDeath("")
                            ResetEchoesDisplay()
                            deathFrame:Hide()
                        end)
                end
            end)


        acceptDeathButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(DeathTexts.tooltips.acceptDeath.title)
            GameTooltip:AddLine(DeathTexts.tooltips.acceptDeath.line1(
                soulPointsGain, soulShardsGain), 0, 1, 0, true)
            GameTooltip:AddLine(DeathTexts.tooltips.acceptDeath.line2, 1, 1, 1,
                true)
            GameTooltip:Show()
        end)
        acceptDeathButton:SetScript("OnLeave",
            function(self) GameTooltip:Hide() end)

        acceptDeathButton:SetPoint("TOP", 0, yOffset)
        table.insert(deathFrame.buttons, acceptDeathButton)
        yOffset = yOffset - buttonHeight

        -- Hardcore no longer refuses resurrections (server side, 2026-09-06): the
        -- resurrection buttons are drawn on every tier, the run budget alone decides.
        local isHardmode = false

        if not isHardmode then
            -- Free, castable by anyone (no group constraint since 2026-09-17), but the run
            -- only accepts one (countCanAcceptedRezs): a pending request and a charge left
            -- are the two conditions; the server has the last word on the accept.
            if resRequest and (currentData.countCanAcceptedRezs or 0) > 0 then
                local playerRezButton = CreateDeathButton("acceptPlayerRez",
                    deathFrame.buttonContainer,
                    DeathTexts.buttons.acceptPlayerRez(currentData.countCanAcceptedRezs,
                        (currentData.countCanAcceptedRezs or 0) + (tonumber(currentData.acceptedRezsUsed) or 0)),
                    function()
                        ShowConfirmationPopup(DeathTexts.confirmations.acceptPlayerRez
                            .title,
                            DeathTexts.confirmations.acceptPlayerRez.message(),
                            function()
                                AcceptResurrect()
                                resRequest = false;
                                -- Never hide optimistically: the server can still refuse
                                -- the rez, and a hidden frame leaves the corpse with no
                                -- options at all. PLAYER_ALIVE hides it when a
                                -- resurrection actually goes through.
                            end)
                    end)


                playerRezButton:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(DeathTexts.tooltips.acceptPlayerRez.title)
                    GameTooltip:AddLine(DeathTexts.tooltips.acceptPlayerRez.line1,
                        0, 1, 0, true)
                    GameTooltip:AddLine(DeathTexts.tooltips.acceptPlayerRez.line2,
                        1, 1, 1, true)
                    GameTooltip:Show()
                end)
                playerRezButton:SetScript("OnLeave",
                    function(self)
                        GameTooltip:Hide()
                    end)

                playerRezButton:SetPoint("TOP", 0, yOffset)
                table.insert(deathFrame.buttons, playerRezButton)
                yOffset = yOffset - buttonHeight
            end


            -- The paid resurrection (2026-09-17): unlimited while the run can pay. The server
            -- prices the next one in run Soul Ashes and Soul Shards (costNextReset /
            -- costNextResetShards) and says whether it is affordable (paidRezAvailable).
            do
                local affordable = currentData.paidRezAvailable and true or false
                local ashesCost = currentData.costNextReset or 0
                local shardsCost = currentData.costNextResetShards or 0
                local ashesLeft = math.max(0, (currentData.soulPoints or 0) - ashesCost)
                local shardsLeft = math.max(0, (currentData.soulShards or 0) - shardsCost)
                local paidButton = CreateDeathButton("paidRez",
                    deathFrame.buttonContainer,
                    DeathTexts.buttons.soulPointsAffordable(ashesCost, shardsCost),
                    function()
                        if not affordable then return end
                        ShowConfirmationPopup(DeathTexts.confirmations.soulPointsRez.title,
                            DeathTexts.confirmations.soulPointsRez
                            .message(ashesCost, shardsCost, ashesLeft, shardsLeft),
                            function()
                                ProjectEbonhold.PlayerRunService.AvoidResetWithSoulPoints();
                                -- PLAYER_ALIVE hides the frame; the server can still refuse
                                -- this (see acceptPlayerRez).
                            end)
                    end)

                paidButton:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(DeathTexts.tooltips.soulPointsRez.title)
                    GameTooltip:AddLine(DeathTexts.tooltips.soulPointsRez.line1(ashesCost, shardsCost),
                        0, 1, 0, true)
                    GameTooltip:AddLine(DeathTexts.tooltips.soulPointsRez.line2, 1, 1, 1, true)
                    GameTooltip:AddLine(DeathTexts.tooltips.soulPointsRez.line3(
                            currentData.paidRezsUsed or 0), 1, 1, 1,
                        true)
                    if not affordable then
                        GameTooltip:AddLine(DeathTexts.tooltips.soulPointsRez.tooPoor, 1, 0.35, 0.35, true)
                    end
                    GameTooltip:Show()
                end)
                paidButton:SetScript("OnLeave",
                    function(self) GameTooltip:Hide() end)

                -- Same button, disabled (grey texture + grey text) when the run cannot pay: the
                -- price stays visible, and the tooltip still says why (3.3.5 buttons keep their
                -- OnEnter while disabled).
                if affordable then
                    paidButton:Enable()
                else
                    paidButton:Disable()
                    paidButton:SetTextColor(0.5, 0.5, 0.5)
                end
                paidButton:SetPoint("TOP", 0, yOffset)
                table.insert(deathFrame.buttons, paidButton)
                yOffset = yOffset - buttonHeight
            end

            -- Unlimited since 2026-09-07, like the player rez above: owning the
            -- soulstone / reincarnation is the only condition.
            if HasSoulstone() then
                local text = HasSoulstone();
                local soulstoneButton = CreateDeathButton("soulstone",
                    deathFrame.buttonContainer,
                    DeathTexts.buttons.useSoulstone(text),
                    function()
                        ShowConfirmationPopup(DeathTexts.confirmations.soulstone.title(
                                text), DeathTexts.confirmations
                            .soulstone
                            .message(text),
                            function()
                                UseSoulstone()
                            end)
                    end)


                soulstoneButton:SetScript("OnEnter", function(self)
                    local text = HasSoulstone();
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(DeathTexts.tooltips.soulstone.title(text))
                    GameTooltip:AddLine(DeathTexts.tooltips.soulstone.line1(text),
                        0, 1, 0, true)
                    GameTooltip:AddLine(DeathTexts.tooltips.soulstone.line2,
                        1, 1, 1, true)
                    GameTooltip:Show()
                end)
                soulstoneButton:SetScript("OnLeave",
                    function(self)
                        GameTooltip:Hide()
                    end)

                soulstoneButton:SetPoint("TOP", 0, yOffset)
                table.insert(deathFrame.buttons, soulstoneButton)
                yOffset = yOffset - buttonHeight
            end
        end -- if not isHardmode
    end


    local baseHeight = 120
    local buttonSpacing = 50
    local totalHeight = baseHeight + (#deathFrame.buttons * buttonSpacing) + UpdateRecapButton()
    local finalHeight = math.max(200, totalHeight)


    deathFrame:SetHeight(finalHeight)


    if deathFrame.dynamicBackground then
        deathFrame.dynamicBackground:Resize(320, finalHeight)
    end
end

local function ShowDeathFrame()
    CreateDeathFrame()

    if ProjectEbonhold and ProjectEbonhold.PlayerRunService and
        ProjectEbonhold.PlayerRunService.RequestData then
        ProjectEbonhold.PlayerRunService.RequestData()
    end

    -- Ask for the tier too: it is reset to Normal by every UI load, and only the reply lets
    -- UpdateDeathFrameButtons stop treating the player as Hardcore.
    if ProjectEbonhold and ProjectEbonhold.HardmodeService and
        ProjectEbonhold.HardmodeService.RequestHardmodeData then
        ProjectEbonhold.HardmodeService.RequestHardmodeData()
    end

    UpdateDeathFrameButtons()
    deathFrame:Show()
end


local function HideDeathFrame() if deathFrame then deathFrame:Hide() end end

StaticPopupDialogs["RESURRECT"] = {
    text = "",
    OnShow = function(self)
        self:Hide()
        ShowDeathFrame()
    end,
    timeout = 0,
    whileDead = 1,
    cancels = "DEATH",
    interruptCinematic = 1,
    notClosableByLogout = 1,
    hideOnEscape = 1,
    noCancelOnReuse = 1
};

StaticPopupDialogs["DEATH"] = {
    text = "",
    OnShow = function(self)
        self:Hide()
        ShowDeathFrame()
    end,
    timeout = 0,
    whileDead = 1,
    interruptCinematic = 1,
    notClosableByLogout = 1,
    cancels = "RECOVER_CORPSE"
};


local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("RESURRECT_REQUEST")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_DEAD" then
        ProjectEbonhold.PerkUI.Hide();
        ShowDeathFrame()
    elseif event == "PLAYER_ALIVE" then
        isPlayerBlocked = false
        HideDeathFrame()

        if ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetCurrentChoice then
            local currentChoice = ProjectEbonhold.PerkService.GetCurrentChoice()
            if currentChoice and ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.Show then
                ProjectEbonhold.PerkUI.Show(currentChoice)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if UnitIsDead("player") then ShowDeathFrame() end
    elseif event == "RESURRECT_REQUEST" then
        if deathFrame and deathFrame:IsVisible() then
            resRequest = true;
            UpdateDeathFrameButtons()
        end
    elseif event == "BAG_UPDATE" then
        if deathFrame and deathFrame:IsVisible() and UnitIsDead("player") then
            UpdateDeathFrameButtons()
        end
    end
end)


ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.DeathFrame = {}
ProjectEbonhold.DeathFrame.UpdateData = Addon.UpdateData

-- Rebuild the visible frame from current state (run data + hardmode tier). Called by
-- HardmodeService once the server confirms the difficulty, which lands after the frame is drawn.
ProjectEbonhold.DeathFrame.Refresh = function()
    if deathFrame and deathFrame:IsVisible() then
        UpdateDeathFrameButtons()
    end
end

-- Handler: server signals the player is stuck/blocked while dead
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_IS_BLOCKED, function(body)
    isPlayerBlocked = true
    ShowDeathFrame()
end)
