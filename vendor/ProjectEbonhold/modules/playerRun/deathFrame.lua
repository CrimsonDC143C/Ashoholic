local addon, Addon = ...


local playerRunData = {
    countCanSelfRezs = 0,
    countCanClassRezs = 0,
    costNextReset = 100,
    soulPoints = 0
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
    popupMessage:SetText(message)
    popupMessage:SetTextColor(1, 1, 1)
    popupMessage:SetWidth(350)
    popupMessage:SetJustifyH("CENTER")


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

    frame:Hide()
    itemSelectionFrame = frame
    return frame
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


function UpdateDeathFrameButtons()
    if not deathFrame then return end

    for _, button in pairs(deathFrame.buttons) do button:Hide() end
    deathFrame.buttons = {}
    deathFrame.buttonContainer:Show()

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

        local acceptDeathButton = CreateDeathButton("accepteDeath",
            deathFrame.buttonContainer,
            DeathTexts.buttons
            .acceptDeath(
                soulPointsGain),
            function()
                local freeSlots, hasSpace = HasEnoughInventorySpace()

                if not hasSpace then
                    local playerItems = GetAllPlayerItems()

                    if #playerItems == 0 then
                        ShowConfirmationPopup(DeathTexts.confirmations.acceptDeath.title,
                            DeathTexts.confirmations.acceptDeath.message(soulPointsGain),
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
                                DeathTexts.confirmations.acceptDeath.message(soulPointsGain),
                                function()
                                    ProjectEbonhold.PlayerRunService.AcceptDeath(itemData)
                                    ResetEchoesDisplay()
                                    deathFrame:Hide()
                                end)
                        end)
                    end
                else
                    ShowConfirmationPopup(DeathTexts.confirmations.acceptDeath.title,
                        DeathTexts.confirmations.acceptDeath.message(soulPointsGain),
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
                soulPointsGain), 0, 1, 0, true)
            GameTooltip:AddLine(DeathTexts.tooltips.acceptDeath.line2, 1, 1, 1,
                true)
            GameTooltip:Show()
        end)
        acceptDeathButton:SetScript("OnLeave",
            function(self) GameTooltip:Hide() end)

        acceptDeathButton:SetPoint("TOP", 0, yOffset)
        table.insert(deathFrame.buttons, acceptDeathButton)
        yOffset = yOffset - buttonHeight

        -- Fail closed: HardmodeService resets to Normal on every UI load and only learns the
        -- real tier from an async server reply, so an unconfirmed tier is treated as Hardcore.
        -- Otherwise a /reload while dead draws resurrection options the server will refuse.
        local hardmodeService = ProjectEbonhold.HardmodeService
        local isHardmode = not hardmodeService
            or not hardmodeService.IsDifficultyKnown
            or not hardmodeService.IsDifficultyKnown()
            or hardmodeService.GetCurrentDifficulty() > 1

        if not isHardmode then
            if currentData.countCanAcceptedRezs and currentData.countCanAcceptedRezs >
                0 and resRequest then
                local playerRezButton = CreateDeathButton("acceptPlayerRez",
                    deathFrame.buttonContainer,
                    DeathTexts.buttons
                    .acceptPlayerRez(
                        currentData.countCanAcceptedRezs),
                    function()
                        ShowConfirmationPopup(DeathTexts.confirmations.acceptPlayerRez
                            .title,
                            DeathTexts.confirmations.acceptPlayerRez
                            .message(
                                currentData.countCanAcceptedRezs),
                            function()
                                AcceptResurrect()
                                resRequest = false;
                                -- Never hide optimistically: the server refuses the rez in
                                -- Hardcore and once the run's budget is spent, and a hidden
                                -- frame leaves the corpse with no options at all. PLAYER_ALIVE
                                -- hides it when a resurrection actually goes through.
                            end)
                    end)


                playerRezButton:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(DeathTexts.tooltips.acceptPlayerRez.title)
                    GameTooltip:AddLine(DeathTexts.tooltips.acceptPlayerRez.line1,
                        0, 1, 0, true)
                    GameTooltip:AddLine(DeathTexts.tooltips.acceptPlayerRez.line2(
                            currentData.countCanAcceptedRezs), 1, 1,
                        1, true)
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


            if currentData.countCanSelfRezs and currentData.countCanSelfRezs > 0 then
                local reviveButton = CreateDeathButton("selfRezs",
                    deathFrame.buttonContainer,
                    DeathTexts.buttons
                    .selfRezAvailable(
                        currentData.countCanSelfRezs),
                    function()
                        ShowConfirmationPopup(DeathTexts.confirmations.selfRez.title,
                            DeathTexts.confirmations.selfRez
                            .message(currentData.countCanSelfRezs),
                            function()
                                ProjectEbonhold.PlayerRunService
                                    .AvoidResetFreeResurrection();
                                -- PLAYER_ALIVE hides the frame; the server can still refuse
                                -- this (see acceptPlayerRez).
                            end)
                    end)


                reviveButton:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(DeathTexts.tooltips.selfRez.title)
                    GameTooltip:AddLine(DeathTexts.tooltips.selfRez.line1, 0, 1, 0,
                        true)
                    GameTooltip:AddLine(DeathTexts.tooltips.selfRez.line2(
                            currentData.countCanSelfRezs), 1, 1, 1,
                        true)
                    GameTooltip:Show()
                end)
                reviveButton:SetScript("OnLeave",
                    function(self) GameTooltip:Hide() end)

                reviveButton:SetPoint("TOP", 0, yOffset)
                table.insert(deathFrame.buttons, reviveButton)
                yOffset = yOffset - buttonHeight
            end
            local playerLevel = UnitLevel("player")
            local costRez = math.max(playerLevel, currentData.costNextReset or 0)
            local currentSoulPoints = currentData.soulPoints or 0
            local canAfford = currentSoulPoints >= costRez

            local soulRezButton = CreateDeathButton("reviveWithSoulPoints",
                deathFrame.buttonContainer,
                DeathTexts.buttons
                .soulPointsAffordable(
                    costRez), function()
                    if canAfford then
                        ShowConfirmationPopup(DeathTexts.confirmations.soulPointsRez
                            .title,
                            DeathTexts.confirmations.soulPointsRez
                            .message(costRez,
                                currentSoulPoints - costRez),
                            function()
                                ProjectEbonhold.PlayerRunService.AvoidResetWithSoulPoints()
                                -- PLAYER_ALIVE hides the frame; the server can still refuse
                                -- this (see acceptPlayerRez).
                            end)
                    else
                        DEFAULT_CHAT_FRAME:AddMessage(DeathTexts.messages
                            .notEnoughSoulPoints)
                    end
                end)


            soulRezButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(DeathTexts.tooltips.soulPointsRez.title)
                if canAfford then
                    GameTooltip:AddLine(DeathTexts.tooltips.soulPointsRez.canAfford
                        .line1(costRez), 0, 1, 0, true)
                    GameTooltip:AddLine(DeathTexts.tooltips.soulPointsRez.canAfford
                        .line2, 1, 1, 1, true)
                    GameTooltip:AddLine(DeathTexts.tooltips.soulPointsRez.canAfford
                        .line3(currentSoulPoints - costRez), 1,
                        1, 0, true)
                else
                    GameTooltip:AddLine(
                        DeathTexts.tooltips.soulPointsRez.cantAfford.line1(costRez),
                        1, 0, 0, true)
                    GameTooltip:AddLine(
                        DeathTexts.tooltips.soulPointsRez.cantAfford.line2(
                            currentSoulPoints), 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            soulRezButton:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)

            soulRezButton:SetPoint("TOP", 0, yOffset)

            if not canAfford then soulRezButton:Disable() end

            table.insert(deathFrame.buttons, soulRezButton)
            yOffset = yOffset - buttonHeight

            if HasSoulstone() and currentData.countCanClassRezs and
                currentData.countCanClassRezs > 0 then
                local text = HasSoulstone();
                local soulstoneButton = CreateDeathButton("soulstone",
                    deathFrame.buttonContainer,
                    DeathTexts.buttons
                    .useSoulstone(text,
                        currentData.countCanClassRezs),
                    function()
                        ShowConfirmationPopup(DeathTexts.confirmations.soulstone.title(
                                text), DeathTexts.confirmations
                            .soulstone
                            .message(text,
                                currentData.countCanClassRezs),
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
                    GameTooltip:AddLine(DeathTexts.tooltips.soulstone.line2(
                            currentData.countCanClassRezs), 1, 1, 1,
                        true)
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
    local totalHeight = baseHeight + (#deathFrame.buttons * buttonSpacing)
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
