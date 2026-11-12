--[[
================================================================================
 UI/Roster.lua - THE FIRST LIVE ASHOHOLIC WINDOW
================================================================================

 The roster asks Data/Store.lua for a read-only copy of saved character
 basics, run currencies and account currencies. It never reads AshoholicDB
 directly or collects character information; the Collectors layer owns those
 observations. When the window opens, it only asks the currency collector to
 fetch account balances if this session has none yet.

 The visual style is deliberately based on the approved PreviewUI design,
 while this first live screen keeps its job focused: summary cards for the
 spendable account-wide currencies and gold, then the saved characters grouped by
 account, with Unknown for any field that has not been collected.
]]

local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local CurrencyCollector = addon.Collectors and addon.Collectors.Currencies

if not Data or not CurrencyCollector then
    error("Ashoholic UI/Roster.lua loaded before Data/Store.lua or Collectors/Currencies.lua.")
end

local UI = addon.UI or {}
addon.UI = UI

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local GOLD_COLOR = { 1, 0.79, 0.39, 1 }
local TEAL_COLOR = { 0.40, 0.86, 0.78, 1 }
local TEXT_COLOR = { 0.88, 0.88, 0.90, 1 }
local MUTED_COLOR = { 0.58, 0.61, 0.67, 1 }
local PANEL_COLOR = { 0.075, 0.083, 0.105, 0.99 }
local BORDER_COLOR = { 0.19, 0.21, 0.26, 1 }
local ROW_COLOR = { 0.10, 0.115, 0.145, 1 }
local ALT_ROW_COLOR = { 0.12, 0.135, 0.165, 1 }
local UNKNOWN_TEXT = "Unknown"
local ROW_HEIGHT = 36
local ACCOUNT_HEADER_HEIGHT = 28
local ROW_GAP = 3
local FRAME_WIDTH = 1040
-- Taller than before by the cards' height plus spacing, so the character list
-- keeps the same visible height under the new summary cards.
local FRAME_HEIGHT = 632
local CARD_TOP = 72
local CARD_HEIGHT = 50
local CARD_GAP = 18
local COLUMN_HEADER_TOP = CARD_TOP + CARD_HEIGHT + 12

-- The account currency cards use the preview's titles and icons. "field" is the
-- start of the saved names, for example "ash" for ashBanked and ashSpendable.
local CURRENCY_CARDS = {
    {
        field = "ash",
        title = "SOUL ASH",
        icon = "inv_soulash",
        tooltipTitle = "Account Soul Ash",
        note = "Run Soul Ash is shown on characters and is not included here.",
    },
    {
        field = "shard",
        title = "SOUL SHARDS",
        icon = "inv_10_jewelcrafting3_soulcage_frost",
        tooltipTitle = "Account Soul Shards",
        note = "Run Soul Shards are shown on characters and are not included here.",
    },
    {
        field = "essence",
        title = "SOUL ESSENCE",
        icon = "inv_misc_supersoulash",
        tooltipTitle = "Account Soul Essence",
        note = "Persistent Prestige currency.",
    },
    {
        field = "artisan",
        title = "ARTISAN SOUL",
        icon = "ability_argus_soulbombdebufflarge",
        tooltipTitle = "Account Artisan Soul",
        note = "Persistent profession currency.",
    },
}
local GOLD_CARD_ICON = "INV_Misc_Coin_02"
local SUMMARY_CARD_COUNT = #CURRENCY_CARDS + 1

local frame
local rosterDirty = false

Data.OnRosterChanged(function()
    -- Several observations can arrive together. Redraw once on the next
    -- visible frame rather than rebuilding the roster inside a server callback.
    rosterDirty = true
end)

local function SetFontString(fontString, size, color)
    fontString:SetFont("Fonts\\FRIZQT__.TTF", size)
    fontString:SetTextColor(unpack(color))
    fontString:SetJustifyV("MIDDLE")
end

local function AddLabel(parent, text, x, y, width, height, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetHeight(height)
    label:SetJustifyH("LEFT")
    SetFontString(label, size, color)
    label:SetText(text or "")
    return label
end

local function AddTextButton(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button:SetNormalTexture(WHITE_TEXTURE)
    button:SetHighlightTexture(WHITE_TEXTURE, "ADD")
    button:GetNormalTexture():SetVertexColor(0.10, 0.115, 0.145, 1)

    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    SetFontString(label, 11, TEXT_COLOR)
    label:SetText(text)

    button:SetScript("OnClick", onClick)
    return button
end

local function FormatNumber(value)
    if type(value) ~= "number" then
        return UNKNOWN_TEXT
    end

    local text = tostring(math.floor(value))
    local groups = {}
    while #text > 3 do
        table.insert(groups, 1, string.sub(text, -3))
        text = string.sub(text, 1, -4)
    end
    table.insert(groups, 1, text)
    return table.concat(groups, ",")
end

local function FormatCopper(copper)
    if type(copper) ~= "number" then
        return UNKNOWN_TEXT
    end

    local gold = FormatNumber(math.floor(copper / 10000))
    local silver = math.floor((copper % 10000) / 100)
    local remainingCopper = copper % 100
    return gold .. "g " .. silver .. "s " .. remainingCopper .. "c"
end

local function FormatLastSeen(timestamp)
    if type(timestamp) ~= "number" then
        return UNKNOWN_TEXT
    end

    local elapsed = time() - timestamp
    if elapsed < 60 then
        return "Just now"
    elseif elapsed < 3600 then
        return math.floor(elapsed / 60) .. " min ago"
    elseif elapsed < 86400 then
        return math.floor(elapsed / 3600) .. " hr ago"
    end
    return math.floor(elapsed / 86400) .. " days ago"
end

-- Tooltip lines are prepared during each refresh and stored on the card.
-- A line with "right" text is shown as two columns.
local function AddTooltipLine(lines, left, right, color)
    table.insert(lines, { left = left, right = right, color = color or TEXT_COLOR })
end

local function ShowCardTooltip(card)
    GameTooltip:SetOwner(card, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(card.tooltipTitle, GOLD_COLOR[1], GOLD_COLOR[2], GOLD_COLOR[3])
    for _, line in ipairs(card.tooltipLines) do
        local r, g, b = line.color[1], line.color[2], line.color[3]
        if line.right then
            GameTooltip:AddDoubleLine(line.left, line.right, r, g, b, r, g, b)
        else
            GameTooltip:AddLine(line.left, r, g, b, true)
        end
    end
    GameTooltip:Show()
end

local function CreateSummaryCard(parent, index, title, icon, valueColor)
    local contentWidth = FRAME_WIDTH - 40
    local width = (contentWidth - (SUMMARY_CARD_COUNT - 1) * CARD_GAP) / SUMMARY_CARD_COUNT

    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, CARD_HEIGHT)
    card:SetPoint("TOPLEFT", 20 + (index - 1) * (width + CARD_GAP), -CARD_TOP)
    card:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    card:SetBackdropColor(unpack(ROW_COLOR))
    card:SetBackdropBorderColor(unpack(BORDER_COLOR))

    AddLabel(card, "|TInterface\\Icons\\" .. icon .. ":16|t " .. title, 12, -5, width - 24, 16, 9, MUTED_COLOR)
    card.value = AddLabel(card, UNKNOWN_TEXT, 12, -23, width - 24, 20, 16, valueColor)
    card.tooltipTitle = title
    card.tooltipLines = {}

    card:EnableMouse(true)
    card:SetScript("OnEnter", ShowCardTooltip)
    card:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return card
end

local function AccountLabel(account)
    local name = account.name or "Unknown account"
    if account.isCurrent then
        return name .. " (this account)"
    end
    return name
end

-- Totals are calculated for display only (schema Rule 7). Each account counts
-- once, no matter how many characters it has.
local function RefreshCurrencyCard(card, definition, roster)
    local bankedField = definition.field .. "Banked"
    local spendableField = definition.field .. "Spendable"
    local bankedTotal, spendableTotal = 0, 0
    local knownAccounts, unknownAccounts = 0, 0
    local accountLines = {}

    for _, account in ipairs(roster) do
        local currencies = account.currencies
        local banked = currencies and currencies[bankedField]
        local spendable = currencies and currencies[spendableField]

        if type(banked) == "number" and type(spendable) == "number" then
            knownAccounts = knownAccounts + 1
            bankedTotal = bankedTotal + banked
            spendableTotal = spendableTotal + spendable
            AddTooltipLine(accountLines, AccountLabel(account), nil, GOLD_COLOR)
            AddTooltipLine(accountLines, "  Spendable", FormatNumber(spendable))
            AddTooltipLine(accountLines, "  Banked", FormatNumber(banked))
            AddTooltipLine(accountLines, "  Updated", FormatLastSeen(currencies.updatedAt), MUTED_COLOR)
        else
            unknownAccounts = unknownAccounts + 1
            AddTooltipLine(accountLines, AccountLabel(account), UNKNOWN_TEXT, MUTED_COLOR)
        end
    end

    local lines = {}
    if knownAccounts == 0 then
        card.value:SetText(UNKNOWN_TEXT)
        AddTooltipLine(lines, "Spendable total", UNKNOWN_TEXT)
        AddTooltipLine(lines, "Banked total", UNKNOWN_TEXT)
    else
        card.value:SetText(FormatNumber(spendableTotal))
        AddTooltipLine(lines, "Spendable total", FormatNumber(spendableTotal))
        AddTooltipLine(lines, "Banked total", FormatNumber(bankedTotal))
    end
    AddTooltipLine(lines, " ")
    for _, line in ipairs(accountLines) do
        table.insert(lines, line)
    end
    AddTooltipLine(lines, " ")
    if knownAccounts > 0 and unknownAccounts > 0 then
        AddTooltipLine(lines, "Totals include only accounts whose balances are known.", nil, MUTED_COLOR)
    end
    if knownAccounts == 0 then
        AddTooltipLine(lines, "Not received from Ebonhold yet. Unknown is not zero.", nil, MUTED_COLOR)
    end
    AddTooltipLine(lines, definition.note, nil, MUTED_COLOR)

    card.tooltipTitle = definition.tooltipTitle
    card.tooltipLines = lines
end

-- Gold is each character's own money (the "pockets"). Warband gold stays
-- unknown because ProjectEbonhold keeps it private, so it is never counted.
local function RefreshGoldCard(card, roster)
    local pocketsTotal = 0
    local knownCharacters, unknownCharacters = 0, 0
    local accountLines = {}

    for _, account in ipairs(roster) do
        local accountGold = 0
        local accountKnown = 0
        for _, character in ipairs(account.characters) do
            if type(character.gold) == "number" then
                accountGold = accountGold + character.gold
                accountKnown = accountKnown + 1
            else
                unknownCharacters = unknownCharacters + 1
            end
        end
        pocketsTotal = pocketsTotal + accountGold
        knownCharacters = knownCharacters + accountKnown

        if accountKnown > 0 then
            AddTooltipLine(accountLines, AccountLabel(account), FormatCopper(accountGold))
        else
            AddTooltipLine(accountLines, AccountLabel(account), UNKNOWN_TEXT, MUTED_COLOR)
        end
    end

    local lines = {}
    if knownCharacters == 0 then
        card.value:SetText(UNKNOWN_TEXT)
        AddTooltipLine(lines, "Character pockets", UNKNOWN_TEXT)
    else
        card.value:SetText(FormatNumber(math.floor(pocketsTotal / 10000)) .. "g")
        AddTooltipLine(lines, "Character pockets", FormatCopper(pocketsTotal))
    end
    AddTooltipLine(lines, "Warband bank", UNKNOWN_TEXT, MUTED_COLOR)
    AddTooltipLine(lines, " ")
    for _, line in ipairs(accountLines) do
        table.insert(lines, line)
    end
    AddTooltipLine(lines, " ")
    if unknownCharacters > 0 then
        AddTooltipLine(lines, unknownCharacters .. " saved character(s) have unknown gold and are not counted.", nil, MUTED_COLOR)
    end
    AddTooltipLine(
        lines,
        "The card counts character pockets only. Warband gold stays Unknown because ProjectEbonhold does not share it with other addons.",
        nil,
        MUTED_COLOR
    )

    card.tooltipTitle = "Gold breakdown"
    card.tooltipLines = lines
end

local function RefreshSummaryCards(roster)
    for index, definition in ipairs(CURRENCY_CARDS) do
        RefreshCurrencyCard(frame.currencyCards[index], definition, roster)
    end
    RefreshGoldCard(frame.goldCard, roster)

    -- Keep an open tooltip in step with new data or age labels.
    for _, card in ipairs(frame.currencyCards) do
        if GameTooltip:IsOwned(card) then
            ShowCardTooltip(card)
        end
    end
    if GameTooltip:IsOwned(frame.goldCard) then
        ShowCardTooltip(frame.goldCard)
    end
end

local function CreateRosterFrame()
    local rosterFrame = CreateFrame("Frame", "AshoholicRosterFrame", UIParent)
    rosterFrame:Hide()
    rosterFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    rosterFrame:SetPoint("CENTER")
    rosterFrame:SetFrameStrata("DIALOG")
    rosterFrame:SetClampedToScreen(true)
    rosterFrame:SetMovable(true)
    rosterFrame:EnableMouse(true)
    rosterFrame:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    rosterFrame:SetBackdropColor(unpack(PANEL_COLOR))
    rosterFrame:SetBackdropBorderColor(unpack(BORDER_COLOR))

    local titleBar = CreateFrame("Frame", nil, rosterFrame)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(58)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        rosterFrame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        rosterFrame:StopMovingOrSizing()
        local point, _, _, x, y = rosterFrame:GetPoint(1)
        if not point or x == nil or y == nil then
            error("Ashoholic could not read the roster window's position.")
        end
        Data.SaveRosterPosition(point, x, y)
    end)

    AddLabel(titleBar, "ASHOHOLIC", 22, -13, 230, 25, 18, GOLD_COLOR)
    AddLabel(titleBar, "Your saved character roster", 24, -36, 360, 16, 11, MUTED_COLOR)

    local refreshButton = AddTextButton(rosterFrame, "Refresh", 84, 27, function()
        UI.RefreshRoster()
    end)
    refreshButton:SetPoint("TOPRIGHT", -54, -16)

    local closeButton = AddTextButton(rosterFrame, "X", 28, 27, function()
        rosterFrame:Hide()
    end)
    closeButton:SetPoint("TOPRIGHT", -16, -16)

    local divider = rosterFrame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(WHITE_TEXTURE)
    divider:SetVertexColor(unpack(BORDER_COLOR))
    divider:SetPoint("TOPLEFT", 20, -59)
    divider:SetPoint("TOPRIGHT", -20, -59)
    divider:SetHeight(1)

    rosterFrame.currencyCards = {}
    for index, definition in ipairs(CURRENCY_CARDS) do
        rosterFrame.currencyCards[index] = CreateSummaryCard(
            rosterFrame,
            index,
            definition.title,
            definition.icon,
            TEAL_COLOR
        )
    end
    rosterFrame.goldCard = CreateSummaryCard(
        rosterFrame,
        SUMMARY_CARD_COUNT,
        "TOTAL GOLD",
        GOLD_CARD_ICON,
        GOLD_COLOR
    )

    local header = CreateFrame("Frame", nil, rosterFrame)
    header:SetPoint("TOPLEFT", 20, -COLUMN_HEADER_TOP)
    header:SetPoint("TOPRIGHT", -38, -COLUMN_HEADER_TOP)
    header:SetHeight(24)
    AddLabel(header, "CHARACTER", 12, 0, 208, 20, 10, MUTED_COLOR)
    AddLabel(header, "LEVEL", 230, 0, 48, 20, 10, MUTED_COLOR)
    AddLabel(header, "RUN ASH", 295, 0, 108, 20, 10, MUTED_COLOR)
    AddLabel(header, "RUN SHARDS", 415, 0, 103, 20, 10, MUTED_COLOR)
    AddLabel(header, "GOLD", 530, 0, 150, 20, 10, MUTED_COLOR)
    AddLabel(header, "LOCATION", 695, 0, 155, 20, 10, MUTED_COLOR)
    AddLabel(header, "LAST SEEN", 865, 0, 112, 20, 10, MUTED_COLOR)

    local scroll = CreateFrame("ScrollFrame", "AshoholicRosterScroll", rosterFrame)
    scroll:SetPoint("TOPLEFT", 20, -(COLUMN_HEADER_TOP + 29))
    scroll:SetPoint("BOTTOMRIGHT", -30, 43)
    scroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(990)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maximum = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maximum, current - delta * 70)))
    end)

    local status = AddLabel(rosterFrame, "", 24, -(FRAME_HEIGHT - 44), 980, 16, 10, MUTED_COLOR)
    tinsert(UISpecialFrames, "AshoholicRosterFrame")

    rosterFrame.content = content
    rosterFrame.scroll = scroll
    rosterFrame.status = status
    rosterFrame.headingPool = {}
    rosterFrame.characterPool = {}
    rosterFrame.messagePool = {}
    local ageRefreshElapsed = 0
    rosterFrame:SetScript("OnUpdate", function(_, elapsed)
        ageRefreshElapsed = ageRefreshElapsed + elapsed
        -- Tick the age labels even while no new server data arrives. Redrawing
        -- reads snapshots; it never changes their saved observation times.
        if rosterDirty or ageRefreshElapsed >= 30 then
            ageRefreshElapsed = 0
            UI.RefreshRoster()
        end
    end)

    local savedPosition = Data.GetRosterPosition()
    if savedPosition then
        rosterFrame:ClearAllPoints()
        rosterFrame:SetPoint(
            savedPosition.point,
            UIParent,
            savedPosition.point,
            savedPosition.x,
            savedPosition.y
        )
    end

    return rosterFrame
end

local function CreateAccountHeading(parent, text)
    local heading = CreateFrame("Frame", nil, parent)
    heading:SetHeight(ACCOUNT_HEADER_HEIGHT)

    local background = heading:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(WHITE_TEXTURE)
    background:SetVertexColor(0.075, 0.083, 0.105, 1)
    background:SetAllPoints()

    local label = AddLabel(heading, text, 12, -2, 940, 24, 12, GOLD_COLOR)
    heading.label = label
    return heading
end

local function CreateCharacterRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetTexture(WHITE_TEXTURE)
    row.background:SetAllPoints()

    row.name = AddLabel(row, "", 12, -2, 208, 18, 12, TEXT_COLOR)
    row.realm = AddLabel(row, "", 12, -19, 208, 12, 9, MUTED_COLOR)
    row.level = AddLabel(row, "", 230, -2, 48, 32, 11, TEXT_COLOR)
    row.runAsh = AddLabel(row, "", 295, -2, 108, 32, 11, TEXT_COLOR)
    row.runShards = AddLabel(row, "", 415, -2, 103, 32, 11, TEXT_COLOR)
    row.gold = AddLabel(row, "", 530, -2, 150, 32, 11, TEXT_COLOR)
    row.location = AddLabel(row, "", 695, -2, 155, 32, 11, TEXT_COLOR)
    row.lastSeen = AddLabel(row, "", 865, -2, 112, 18, 11, TEXT_COLOR)
    row.runSeen = AddLabel(row, "", 865, -19, 112, 12, 9, MUTED_COLOR)
    return row
end

local function ReuseMessage(index, text, yOffset)
    local message = frame.messagePool[index]
    if not message then
        message = AddLabel(frame.content, "", 16, -yOffset, 920, ROW_HEIGHT, 11, MUTED_COLOR)
        frame.messagePool[index] = message
    end

    message:ClearAllPoints()
    message:SetPoint("TOPLEFT", 16, -yOffset)
    message:SetText(text)
    message:Show()
end

local function AddRosterEntry(row, character, yOffset, rowNumber)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", 0, -yOffset)
    row.background:SetVertexColor(unpack(rowNumber % 2 == 0 and ROW_COLOR or ALT_ROW_COLOR))

    local className = character.class or UNKNOWN_TEXT
    row.name:SetText(character.name .. "  |cff939baa" .. className .. "|r")
    row.realm:SetText(character.realm or UNKNOWN_TEXT)
    row.level:SetText(character.level ~= nil and tostring(character.level) or UNKNOWN_TEXT)
    row.runAsh:SetText(FormatNumber(character.runAsh))
    row.runShards:SetText(FormatNumber(character.runShards))
    row.gold:SetText(FormatCopper(character.gold))
    row.location:SetText(character.location or UNKNOWN_TEXT)
    row.lastSeen:SetText(FormatLastSeen(character.lastSeen))
    row.runSeen:SetText("Run: " .. FormatLastSeen(character.runUpdatedAt))
    row:Show()
end

function UI.RefreshRoster()
    if not frame then
        return
    end
    rosterDirty = false
    local scrollOffset = frame.scroll:GetVerticalScroll()

    for _, heading in ipairs(frame.headingPool) do
        heading:Hide()
    end
    for _, row in ipairs(frame.characterPool) do
        row:Hide()
    end
    for _, message in ipairs(frame.messagePool) do
        message:Hide()
    end

    local roster = Data.GetRoster()
    RefreshSummaryCards(roster)
    local yOffset = 0
    local rowNumber = 0
    local characterCount = 0
    local headingIndex = 0
    local characterIndex = 0
    local messageIndex = 0

    for _, account in ipairs(roster) do
        local accountName = account.name or "Unknown account"
        local currentLabel = account.isCurrent and "  (this account)" or ""
        headingIndex = headingIndex + 1
        local heading = frame.headingPool[headingIndex]
        if not heading then
            heading = CreateAccountHeading(frame.content, "")
            frame.headingPool[headingIndex] = heading
        end
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", 0, -yOffset)
        heading:SetPoint("TOPRIGHT", 0, -yOffset)
        heading.label:SetText(
            accountName .. currentLabel .. "  -  " .. #account.characters .. " characters"
        )
        heading:Show()
        yOffset = yOffset + ACCOUNT_HEADER_HEIGHT + ROW_GAP

        if #account.characters == 0 then
            messageIndex = messageIndex + 1
            ReuseMessage(
                messageIndex,
                "No character snapshots saved for this account yet.",
                yOffset
            )
            yOffset = yOffset + ROW_HEIGHT + ROW_GAP
        else
            for _, character in ipairs(account.characters) do
                characterIndex = characterIndex + 1
                local row = frame.characterPool[characterIndex]
                if not row then
                    row = CreateCharacterRow(frame.content)
                    frame.characterPool[characterIndex] = row
                end
                AddRosterEntry(row, character, yOffset, rowNumber)
                yOffset = yOffset + ROW_HEIGHT + ROW_GAP
                rowNumber = rowNumber + 1
                characterCount = characterCount + 1
            end
        end

        yOffset = yOffset + ROW_GAP
    end

    if #roster == 0 then
        messageIndex = messageIndex + 1
        ReuseMessage(
            messageIndex,
            "No character snapshots saved yet. Log in to a character, then refresh this roster.",
            12
        )
        yOffset = 60
    end

    frame.content:SetHeight(math.max(1, yOffset))
    frame.scroll:UpdateScrollChildRect()
    frame.scroll:SetVerticalScroll(math.min(scrollOffset, frame.scroll:GetVerticalScrollRange()))
    frame.status:SetText(
        characterCount .. " saved character"
            .. (characterCount == 1 and "" or "s")
            .. "  |  Last seen: character basics. Run: run-data age. Cards: spendable currencies. Hover for banked balances and update times."
    )
end

function UI.ToggleRoster()
    if not frame then
        frame = CreateRosterFrame()
    end

    UI.RefreshRoster()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Slash commands use a stable addon-level entry point and do not need to know
-- how the roster's window is built.
function addon:ToggleRosterUI()
    UI.ToggleRoster()

    -- The window opens at once with the saved values. If this session has no
    -- fresh account balances yet, the collector may ask the server for them;
    -- the reply then updates the open window through Data.OnRosterChanged.
    if frame:IsShown() then
        CurrencyCollector.RequestBalancesIfNeeded()
    end
end
