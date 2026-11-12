--[[
================================================================================
 UI/Roster.lua - THE LIVE ASHOHOLIC WINDOW
================================================================================

 The roster asks Data/Store.lua for a read-only copy of saved character
 basics, run details and account progression. It never reads AshoholicDB
 directly or collects character information; the Collectors layer owns those
 observations. When the window opens, it only asks the currency collector to
 fetch account balances if this session has none yet.

 The visual style is deliberately based on the approved PreviewUI design,
 with separate character-details and Progression renderers. Only the live
 Roster and Progression pages are enabled; the sample preview stays separate.
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

local Style = UI.Style
local WHITE_TEXTURE = Style.whiteTexture
local GOLD_COLOR = Style.gold
local TEAL_COLOR = Style.teal
local TEXT_COLOR = Style.text
local MUTED_COLOR = Style.muted
local PANEL_COLOR = Style.panel
local BORDER_COLOR = Style.border
local ROW_COLOR = Style.row
local ALT_ROW_COLOR = Style.alternateRow
local SELECTED_ROW_COLOR = { 0.13, 0.24, 0.25, 1 }
local AddLabel = UI.AddLabel
local AddTextButton = UI.AddTextButton
local FormatNumber = UI.FormatNumber
local FormatCopper = UI.FormatCopper
local FormatLastSeen = UI.FormatLastSeen
local AddTooltipLine = UI.AddTooltipLine
local ShowCardTooltip = UI.ShowTooltip
local UNKNOWN_TEXT = "Unknown"
local ROW_HEIGHT = 36
local ACCOUNT_HEADER_HEIGHT = 28
local ROW_GAP = 3
local FRAME_WIDTH = 1320
local FRAME_HEIGHT = 720
local DETAIL_WIDTH = 332
local ROSTER_CONTENT_WIDTH = FRAME_WIDTH - 40 - DETAIL_WIDTH - 20 - 18
local CARD_TOP = 108
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
local activeTab = "Roster"
local selectedCharacter

Data.OnRosterChanged(function()
    -- Several observations can arrive together. Redraw once on the next
    -- visible frame rather than rebuilding the roster inside a server callback.
    rosterDirty = true
end)

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
    UI.AttachTooltip(card)
    card.tooltipTitle = title
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
    rosterFrame:SetScale(math.min(1, (UIParent:GetWidth() - 40) / FRAME_WIDTH, (UIParent:GetHeight() - 40) / FRAME_HEIGHT))
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
    AddLabel(titleBar, "Saved characters and account progression", 24, -36, 460, 16, 11, MUTED_COLOR)

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

    rosterFrame.tabButtons = {}
    for index, name in ipairs({ "Roster", "Progression" }) do
        local tabName = name
        local button = AddTextButton(rosterFrame, name, 148, 30, function()
            UI.ShowLiveTab(tabName)
        end)
        button:SetPoint("TOPLEFT", 20 + (index - 1) * 158, -60)
        rosterFrame.tabButtons[name] = button
    end

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

    local body = CreateFrame("Frame", nil, rosterFrame)
    body:SetPoint("TOPLEFT", 20, -COLUMN_HEADER_TOP)
    body:SetPoint("BOTTOMRIGHT", -20, 43)
    local rosterPage = CreateFrame("Frame", nil, body)
    rosterPage:SetAllPoints()
    rosterFrame.rosterPage = rosterPage
    rosterFrame.progressionPage = UI.CreateProgressionPage(body, FRAME_WIDTH - 40, Data.GetProgressionRules())
    rosterFrame.progressionPage:Hide()
    rosterFrame.details = UI.CreateCharacterDetails(rosterPage, DETAIL_WIDTH)

    local header = CreateFrame("Frame", nil, rosterPage)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetSize(ROSTER_CONTENT_WIDTH, 24)
    AddLabel(header, "CHARACTER", 12, 0, 165, 20, 10, MUTED_COLOR)
    AddLabel(header, "LEVEL", 185, 0, 42, 20, 10, MUTED_COLOR)
    AddLabel(header, "RUN ASH", 238, 0, 100, 20, 10, MUTED_COLOR)
    AddLabel(header, "RUN SHARDS", 350, 0, 95, 20, 10, MUTED_COLOR)
    AddLabel(header, "GOLD", 457, 0, 135, 20, 10, MUTED_COLOR)
    AddLabel(header, "LOCATION", 604, 0, 160, 20, 10, MUTED_COLOR)
    AddLabel(header, "LAST SEEN", 776, 0, 122, 20, 10, MUTED_COLOR)

    local scroll, content = UI.CreateScroll(rosterPage, "AshoholicRosterScroll", ROSTER_CONTENT_WIDTH)
    scroll:SetPoint("TOPLEFT", 0, -29)
    scroll:SetPoint("BOTTOMLEFT", 0, 0)

    local status = AddLabel(rosterFrame, "", 24, -(FRAME_HEIGHT - 44), FRAME_WIDTH - 48, 16, 10, MUTED_COLOR)
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

    local label = AddLabel(heading, text, 12, -2, ROSTER_CONTENT_WIDTH - 24, 24, 12, GOLD_COLOR)
    heading.label = label
    return heading
end

local function CreateCharacterRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture(WHITE_TEXTURE, "ADD")
    row:GetHighlightTexture():SetVertexColor(0.10, 0.10, 0.10, 0.3)

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetTexture(WHITE_TEXTURE)
    row.background:SetAllPoints()

    row.name = AddLabel(row, "", 12, -2, 165, 18, 12, TEXT_COLOR)
    row.realm = AddLabel(row, "", 12, -19, 165, 12, 9, MUTED_COLOR)
    row.level = AddLabel(row, "", 185, -2, 42, 32, 11, TEXT_COLOR)
    row.runAsh = AddLabel(row, "", 238, -2, 100, 32, 11, TEXT_COLOR)
    row.runShards = AddLabel(row, "", 350, -2, 95, 32, 11, TEXT_COLOR)
    row.gold = AddLabel(row, "", 457, -2, 135, 32, 11, TEXT_COLOR)
    row.location = AddLabel(row, "", 604, -2, 160, 32, 11, TEXT_COLOR)
    row.lastSeen = AddLabel(row, "", 776, -2, 122, 18, 11, TEXT_COLOR)
    row.runSeen = AddLabel(row, "", 776, -19, 122, 12, 9, MUTED_COLOR)
    row:SetScript("OnClick", function(self)
        selectedCharacter = {
            accountId = self.accountId,
            realm = self.character.realm,
            name = self.character.name,
            guid = self.character.guid,
        }
        UI.RefreshRoster()
    end)
    return row
end

local function ReuseMessage(index, text, yOffset)
    local message = frame.messagePool[index]
    if not message then
        message = AddLabel(frame.content, "", 16, -yOffset, ROSTER_CONTENT_WIDTH - 32, ROW_HEIGHT, 11, MUTED_COLOR)
        frame.messagePool[index] = message
    end

    message:ClearAllPoints()
    message:SetPoint("TOPLEFT", 16, -yOffset)
    message:SetText(text)
    message:Show()
end

local function IsSelected(accountId, character)
    return selectedCharacter and selectedCharacter.accountId == accountId
        and selectedCharacter.realm == character.realm
        and selectedCharacter.name == character.name
        and selectedCharacter.guid == character.guid
end

local function FindSelectedCharacter(roster)
    local firstAccount, firstCharacter
    for _, account in ipairs(roster) do
        for _, character in ipairs(account.characters) do
            if not firstCharacter then
                firstAccount, firstCharacter = account, character
            end
            if IsSelected(account.id, character) then
                return character
            end
        end
    end
    selectedCharacter = nil
    if firstCharacter then
        selectedCharacter = {
            accountId = firstAccount.id,
            realm = firstCharacter.realm,
            name = firstCharacter.name,
            guid = firstCharacter.guid,
        }
    end
    return firstCharacter
end

local function AddRosterEntry(row, accountId, character, yOffset, rowNumber)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", 0, -yOffset)
    local color = rowNumber % 2 == 0 and ROW_COLOR or ALT_ROW_COLOR
    if IsSelected(accountId, character) then
        color = SELECTED_ROW_COLOR
    end
    row.background:SetVertexColor(unpack(color))
    row.accountId = accountId
    row.character = character

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
    local roster = Data.GetRoster()
    local rules = Data.GetProgressionRules()
    RefreshSummaryCards(roster)
    for name, button in pairs(frame.tabButtons) do
        button.text:SetTextColor(unpack(name == activeTab and TEAL_COLOR or MUTED_COLOR))
        button:GetNormalTexture():SetVertexColor(unpack(name == activeTab and ALT_ROW_COLOR or ROW_COLOR))
    end
    if activeTab == "Progression" then
        frame.rosterPage:Hide()
        frame.progressionPage:Show()
        UI.RefreshProgression(frame.progressionPage, roster, rules)
        frame.status:SetText(
            "Saved snapshots, not account-wide Torment unlocks. Tiers above "
                .. UI.TierName(rules.tormentLadderTop, rules)
                .. " are instance-only. No Prestige or difficulty actions are sent."
        )
        return
    end
    frame.progressionPage:Hide()
    frame.rosterPage:Show()
    local selected = FindSelectedCharacter(roster)
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
                AddRosterEntry(row, account.id, character, yOffset, rowNumber)
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
    UI.RefreshCharacterDetails(frame.details, selected, rules)
    frame.status:SetText(
        characterCount .. " saved character"
            .. (characterCount == 1 and "" or "s")
            .. "  |  Click a character for details. Each source keeps its own update time. Cards show spendable balances."
    )
end

function UI.ShowLiveTab(name)
    if name ~= "Roster" and name ~= "Progression" then
        error("Ashoholic has no live tab named " .. tostring(name) .. ".")
    end
    activeTab = name
    UI.RefreshRoster()
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
