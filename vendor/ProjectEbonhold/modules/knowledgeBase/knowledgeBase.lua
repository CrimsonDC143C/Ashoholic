local ADDON_NAME = "ProjectEbonhold"


local customKBFrame
local itemRecoveryFrame


StaticPopupDialogs["CONFIRM_GM_TICKET"] = {
    text =
    "|cFFFF0000WARNING:|r If you encountered a bug, please report it on our Discord or website.\n\nDo you really want to contact a GM?",
    button1 = "Yes, contact a GM",
    button2 = "Cancel",
    OnAccept = function()
        if HelpFrame_ShowFrame then
            HelpFrame_ShowFrame("OpenTicket")
        elseif HelpFrame then
            ShowUIPanel(HelpFrame)
            if HelpFrameOpenTicket then
                HelpFrameOpenTicket:Show()
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}


local haveTicket = false
local haveResponse = false
local ticketQueueActive = true

local function HasActiveTicket(category)
    return category ~= nil and category ~= "" and category ~= 0 and category ~= "0"
end

local function IsQueueEnabled(status)
    local statusNum = tonumber(status)
    local enabledNum = tonumber(GMTICKET_QUEUE_STATUS_ENABLED)

    if status == GMTICKET_QUEUE_STATUS_ENABLED or (statusNum and enabledNum and statusNum == enabledNum) then
        return true
    end

    if statusNum == 0 then
        return false
    end

    return true
end


local itemRows = {}
local searchText = ""

local function HideBlizzardKnowledgeBase()
    if KnowledgeBaseFrame then
        KnowledgeBaseFrame:Hide()
        KnowledgeBaseFrame:SetScript("OnShow", function(self)
            self:Hide()
            ShowCustomKnowledgeBase()
        end)
    end
    if KnowledgeBaseErrorFrame then
        KnowledgeBaseErrorFrame:Hide()
    end
end




local function CreateCustomKnowledgeBase()
    customKBFrame = CreateFrame("Frame", "CustomKnowledgeBaseFrame", UIParent)
    customKBFrame:SetSize(500, 320)
    customKBFrame:SetPoint("CENTER")
    customKBFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    customKBFrame:SetBackdropColor(0, 0, 0, 0.95)
    customKBFrame:EnableMouse(true)
    customKBFrame:SetMovable(true)
    customKBFrame:RegisterForDrag("LeftButton")
    customKBFrame:SetScript("OnDragStart", customKBFrame.StartMoving)
    customKBFrame:SetScript("OnDragStop", customKBFrame.StopMovingOrSizing)
    customKBFrame:SetFrameStrata("HIGH")
    customKBFrame:Hide()


    customKBFrame:RegisterEvent("UPDATE_TICKET")
    customKBFrame:RegisterEvent("GMRESPONSE_RECEIVED")
    customKBFrame:RegisterEvent("UPDATE_GM_STATUS")
    customKBFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    customKBFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "UPDATE_TICKET" then
            local category = ...
            if HasActiveTicket(category) then
                haveTicket = true
                haveResponse = false
                UpdateKnowledgeBaseButtons()
            else
                haveTicket = false
                haveResponse = false
                UpdateKnowledgeBaseButtons()
            end
        elseif event == "GMRESPONSE_RECEIVED" then
            haveResponse = true
            haveTicket = false
            UpdateKnowledgeBaseButtons()
        elseif event == "UPDATE_GM_STATUS" then
            local status = ...
            ticketQueueActive = IsQueueEnabled(status)
            UpdateKnowledgeBaseButtons()
        elseif event == "PLAYER_ENTERING_WORLD" then
            GetGMTicket()
        end
    end)


    table.insert(UISpecialFrames, "CustomKnowledgeBaseFrame")


    local closeBtn = CreateFrame("Button", nil, customKBFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", customKBFrame, "TOPRIGHT", -5, -5)


    local title = customKBFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", customKBFrame, "TOP", 0, -24)
    title:SetText("Help & Support")
    title:SetTextColor(1, 0.82, 0)


    local contentFrame = CreateFrame("Frame", nil, customKBFrame)
    contentFrame:SetPoint("TOPLEFT", customKBFrame, "TOPLEFT", 40, -70)
    contentFrame:SetPoint("BOTTOMRIGHT", customKBFrame, "BOTTOMRIGHT", -40, 40)


    local instructionText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructionText:SetPoint("TOP", contentFrame, "TOP", 0, 0)
    instructionText:SetWidth(420)
    instructionText:SetJustifyH("CENTER")
    instructionText:SetSpacing(5)
    instructionText:SetText(
        "If you are experiencing any issue in-game, such as bugs, problems with classes or spells, or items not working properly, please visit our website and report it through the bug tracker.\n\nOnly use the button below if you specifically need to speak with a GM.")
    instructionText:SetTextColor(1, 1, 1, 1)


    local buttonContainer = CreateFrame("Frame", nil, contentFrame)
    buttonContainer:SetSize(240, 120)
    buttonContainer:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 0)
    customKBFrame.buttonContainer = buttonContainer


    local openTicketButton = utils.CreateSimpleCustomButton(buttonContainer, "Open GM Ticket", function()
        if haveResponse then
            customKBFrame:Hide()
            StaticPopup_Show("GM_RESPONSE_MUST_RESOLVE_RESPONSE")
            return
        end


        customKBFrame:Hide()
        StaticPopup_Show("CONFIRM_GM_TICKET")
    end, 240, 45)
    openTicketButton:SetPoint("BOTTOM", buttonContainer, "BOTTOM", 0, 0)
    customKBFrame.openTicketButton = openTicketButton


    local editTicketButton = utils.CreateSimpleCustomButton(buttonContainer, "Edit Ticket", function()
        customKBFrame:Hide()
        if HelpFrame_ShowFrame then
            HelpFrame_ShowFrame("OpenTicket")
        elseif HelpFrame then
            ShowUIPanel(HelpFrame)
            if HelpFrameOpenTicket then
                HelpFrameOpenTicket:Show()
            end
        end
    end, 240, 45)
    editTicketButton:SetPoint("BOTTOM", buttonContainer, "BOTTOM", 0, 55)
    editTicketButton:Hide()
    customKBFrame.editTicketButton = editTicketButton


    local abandonTicketButton = utils.CreateSimpleCustomButton(buttonContainer, "Abandon Ticket", function()
        StaticPopup_Show("HELP_TICKET_ABANDON_CONFIRM")
        customKBFrame:Hide()
    end, 240, 45)
    abandonTicketButton:SetPoint("BOTTOM", buttonContainer, "BOTTOM", 0, 0)
    abandonTicketButton:Hide()
    customKBFrame.abandonTicketButton = abandonTicketButton


    local viewResponseButton = utils.CreateSimpleCustomButton(buttonContainer, "View GM Response", function()
        customKBFrame:Hide()
        if HelpFrame_ShowFrame then
            HelpFrame_ShowFrame("GMResponse")
        elseif HelpFrameViewResponse then
            HelpFrameViewResponse:Show()
        end
    end, 240, 45)
    viewResponseButton:SetPoint("BOTTOM", buttonContainer, "BOTTOM", 0, 0)
    viewResponseButton:Hide()
    customKBFrame.viewResponseButton = viewResponseButton


    local itemRecoveryButton = utils.CreateSimpleCustomButton(buttonContainer, "Item Recovery", function()
        ShowItemRecoveryFrame()
    end, 240, 45)
    itemRecoveryButton:SetPoint("BOTTOM", buttonContainer, "BOTTOM", 0, 55)
    customKBFrame.itemRecoveryButton = itemRecoveryButton


    local unlockButton = CreateFrame("Button", nil, customKBFrame)
    unlockButton:SetSize(32, 32)
    unlockButton:SetPoint("BOTTOMRIGHT", customKBFrame, "BOTTOMRIGHT", -15, 15)
    unlockButton:RegisterForClicks("LeftButtonUp")
    unlockButton:EnableMouse(true)

    unlockButton:SetNormalTexture("Interface\\Icons\\Trade_Engineering")
    unlockButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    unlockButton:SetPushedTexture("Interface\\Icons\\Trade_Engineering")
    unlockButton:GetPushedTexture():SetVertexColor(0.6, 0.6, 0.6)

    unlockButton:SetScript("OnClick", function()
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_UNLOCK_PLAYER, "")
        customKBFrame:Hide()
    end)

    unlockButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Unstuck", 1, 1, 1)
        GameTooltip:AddLine("Click to unstuck your character.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Only works if you are stuck below the map or as a ghost.", 1, 0.5, 0, true)
        GameTooltip:Show()
    end)

    unlockButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    customKBFrame.unlockButton = unlockButton

    return customKBFrame
end




local function CreateItemRecoveryFrame()
    if itemRecoveryFrame then return itemRecoveryFrame end


    itemRecoveryFrame = CreateFrame("Frame", "ItemRecoveryFrame", UIParent)
    itemRecoveryFrame:SetSize(450, 450)
    itemRecoveryFrame:SetPoint("CENTER")
    itemRecoveryFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    itemRecoveryFrame:SetBackdropColor(0, 0, 0, 0.95)
    itemRecoveryFrame:EnableMouse(true)
    itemRecoveryFrame:SetMovable(true)
    itemRecoveryFrame:RegisterForDrag("LeftButton")
    itemRecoveryFrame:SetScript("OnDragStart", itemRecoveryFrame.StartMoving)
    itemRecoveryFrame:SetScript("OnDragStop", itemRecoveryFrame.StopMovingOrSizing)
    itemRecoveryFrame:SetFrameStrata("HIGH")
    itemRecoveryFrame:Hide()

    table.insert(UISpecialFrames, "ItemRecoveryFrame")


    local closeBtn = CreateFrame("Button", nil, itemRecoveryFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", itemRecoveryFrame, "TOPRIGHT", -5, -5)


    local title = itemRecoveryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", itemRecoveryFrame, "TOP", 0, -24)
    title:SetText("Item Recovery")
    title:SetTextColor(1, 0.82, 0)


    local backButton = utils.CreateSimpleCustomButton(itemRecoveryFrame, "Back", function()
        itemRecoveryFrame:Hide()
        ShowCustomKnowledgeBase()
    end, 100, 32)
    backButton:SetPoint("TOPLEFT", itemRecoveryFrame, "TOPLEFT", 20, -20)


    local searchBox = CreateFrame("EditBox", nil, itemRecoveryFrame, "InputBoxTemplate")
    searchBox:SetSize(250, 32)
    searchBox:SetPoint("TOP", title, "BOTTOM", 0, -50)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText():lower()
        UpdateItemList(ProjectEbonhold.KnowledgeBaseService.GetSavedItems())
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)


    local searchLabel = itemRecoveryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("BOTTOM", searchBox, "TOP", 0, 5)
    searchLabel:SetText(
    "View and recover up to 100 items you've previously deleted or sold. Use the search box to filter items by name.")
    searchLabel:SetWidth(400)
    searchLabel:SetTextColor(0.7, 0.7, 0.7)

    local scrollFrame = CreateFrame("ScrollFrame", "ItemRecoveryScrollFrame", itemRecoveryFrame,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -90, -20)
    scrollFrame:SetPoint("BOTTOMRIGHT", itemRecoveryFrame, "BOTTOMRIGHT", -30, 20)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(400, 1)
    scrollFrame:SetScrollChild(scrollChild)
    itemRecoveryFrame.scrollChild = scrollChild

    return itemRecoveryFrame
end




function UpdateItemList(items)
    if not itemRecoveryFrame then return end

    local scrollChild = itemRecoveryFrame.scrollChild


    for _, row in ipairs(itemRows) do
        row:Hide()
    end

    if not items or #items == 0 then
        return
    end


    local filteredItems = {}
    for _, item in ipairs(items) do
        if searchText == "" or (item.name and item.name:lower():find(searchText, 1, true)) then
            table.insert(filteredItems, item)
        end
    end


    local yOffset = -10
    local rowHeight = 50

    for i, item in ipairs(filteredItems) do
        local row = itemRows[i]

        if not row then
            row = CreateFrame("Frame", nil, scrollChild)
            row:SetSize(400, rowHeight)


            row.iconFrame = CreateFrame("Frame", nil, row)
            row.iconFrame:SetSize(40, 40)
            row.iconFrame:SetPoint("LEFT", row, "LEFT", 10, 0)

            row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
            row.icon:SetAllPoints()


            row.countText = row.iconFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            row.countText:SetPoint("BOTTOMRIGHT", row.iconFrame, "BOTTOMRIGHT", -2, 2)
            row.countText:SetTextColor(1, 1, 1)


            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.nameText:SetPoint("LEFT", row.iconFrame, "RIGHT", 10, 0)
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWidth(150)


            row.costText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.costText:SetPoint("LEFT", row.nameText, "RIGHT", 5, 0)
            row.costText:SetJustifyH("LEFT")
            row.costText:SetWidth(60)


            row.recoveryButton = utils.CreateSimpleCustomButton(row, "Recover", nil, 90, 28)
            row.recoveryButton:SetPoint("RIGHT", row, "RIGHT", -5, 0)

            table.insert(itemRows, row)
        end


        row.icon:SetTexture(item.icon)
        row.nameText:SetText(item.name)
        row.countText:SetText(item.count > 1 and item.count or "")


        local sellPrice = (item.sellPrice or 0) * (item.count or 1)
        local playerGold = GetMoney()
        local hasEnoughGold = playerGold >= sellPrice


        local gold = math.floor(sellPrice / 10000)
        local silver = math.floor((sellPrice % 10000) / 100)
        local copper = sellPrice % 100

        local priceText = ""
        if gold > 0 then
            priceText = priceText .. gold .. "|cFFFFD700g|r "
        end
        if silver > 0 or gold > 0 then
            priceText = priceText .. silver .. "|cFFC7C7CFs|r "
        end
        priceText = priceText .. copper .. "|cFFEDA55Fc|r"

        row.costText:SetText(priceText)


        if not hasEnoughGold then
            row.costText:SetTextColor(1, 0, 0)
        else
            row.costText:SetTextColor(1, 1, 1)
        end


        if hasEnoughGold then
            row.recoveryButton:Enable()
        else
            row.recoveryButton:Disable()
        end


        row.recoveryButton:SetScript("OnClick", function()
            if hasEnoughGold then
                ProjectEbonhold.KnowledgeBaseService.RecoverItem(item.guid)
            end
        end)

        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        row:Show()

        yOffset = yOffset - rowHeight
    end


    scrollChild:SetHeight(math.max(1, #filteredItems * rowHeight + 20))
end

function ShowItemRecoveryFrame()
    if not itemRecoveryFrame then
        CreateItemRecoveryFrame()
    end


    if customKBFrame then
        customKBFrame:Hide()
    end


    if ProjectEbonhold.KnowledgeBaseService then
        ProjectEbonhold.KnowledgeBaseService.RequestSavedItems()
    end

    itemRecoveryFrame:Show()
end

function UpdateKnowledgeBaseButtons()
    if not customKBFrame then return end


    if haveResponse then
        customKBFrame.openTicketButton:Hide()
        customKBFrame.editTicketButton:Hide()
        customKBFrame.abandonTicketButton:Hide()
        customKBFrame.viewResponseButton:Show()
    elseif haveTicket then
        customKBFrame.openTicketButton:Hide()
        customKBFrame.editTicketButton:Show()
        customKBFrame.abandonTicketButton:Show()
        customKBFrame.viewResponseButton:Hide()
    else
        customKBFrame.openTicketButton:Show()
        customKBFrame.editTicketButton:Hide()
        customKBFrame.abandonTicketButton:Hide()
        customKBFrame.viewResponseButton:Hide()

        -- Do not hard-disable ticket creation from client-side queue status.
        -- Status payload semantics can differ by server/update/account type.
        customKBFrame.openTicketButton:Enable()
    end
end

function ToggleCustomKnowledgeBase()
    if not customKBFrame then
        CreateCustomKnowledgeBase()
    end

    if customKBFrame:IsShown() then
        customKBFrame:Hide()
    else
        GetGMTicket()

        UpdateKnowledgeBaseButtons()
        customKBFrame:Show()
    end
end

function ShowCustomKnowledgeBase()
    if not customKBFrame then
        CreateCustomKnowledgeBase()
    end

    GetGMTicket()
    GetGMStatus()  -- refresh ticket system status

    UpdateKnowledgeBaseButtons()
    customKBFrame:Show()
end

function HideCustomKnowledgeBase()
    if customKBFrame then
        customKBFrame:Hide()
    end
end

SLASH_CUSTOMKB1 = "/kb"
SLASH_CUSTOMKB2 = "/knowledgebase"
SlashCmdList["CUSTOMKB"] = function(msg)
    ToggleCustomKnowledgeBase()
end




local function HookHelpButton()
    if HelpMicroButton then
        HelpMicroButton:SetScript("OnClick", function(self)
            ToggleCustomKnowledgeBase()
        end)
    end
end




local function Initialize()
    HideBlizzardKnowledgeBase()
    HookHelpButton()
end


local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        Initialize()
    end
end)
