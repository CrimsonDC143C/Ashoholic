--[[
================================================================================
 UI/Roster.lua - THE FIRST LIVE ASHOHOLIC WINDOW
================================================================================

 The roster asks Data/Store.lua for a read-only copy of saved character
 basics. It never reads AshoholicDB directly and never calls WoW APIs to
 collect character information; Collectors/Character.lua owns collection.

 The visual style is deliberately based on the approved PreviewUI design,
 while this first live screen keeps its job focused: show the saved characters
 grouped by account, with Unknown for any field that has not been collected.
]]

local addonName = ...
local addon = _G[addonName]
local Data = addon.Data

if not Data then
    error("Ashoholic UI/Roster.lua loaded before Data/Store.lua.")
end

local UI = addon.UI or {}
addon.UI = UI

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local GOLD_COLOR = { 1, 0.79, 0.39, 1 }
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

local frame

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

local function FormatCopper(copper)
    if type(copper) ~= "number" then
        return UNKNOWN_TEXT
    end

    local goldText = tostring(math.floor(copper / 10000))
    local silver = math.floor((copper % 10000) / 100)
    local remainingCopper = copper % 100
    local goldGroups = {}
    while #goldText > 3 do
        table.insert(goldGroups, 1, string.sub(goldText, -3))
        goldText = string.sub(goldText, 1, -4)
    end
    table.insert(goldGroups, 1, goldText)

    return table.concat(goldGroups, ",") .. "g " .. silver .. "s " .. remainingCopper .. "c"
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

local function CreateRosterFrame()
    local rosterFrame = CreateFrame("Frame", "AshoholicRosterFrame", UIParent)
    rosterFrame:SetSize(1040, 570)
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

    local header = CreateFrame("Frame", nil, rosterFrame)
    header:SetPoint("TOPLEFT", 24, -72)
    header:SetPoint("TOPRIGHT", -38, -72)
    header:SetHeight(24)
    AddLabel(header, "CHARACTER", 12, 0, 230, 20, 10, MUTED_COLOR)
    AddLabel(header, "LEVEL", 260, 0, 65, 20, 10, MUTED_COLOR)
    AddLabel(header, "GOLD", 340, 0, 145, 20, 10, MUTED_COLOR)
    AddLabel(header, "LOCATION", 500, 0, 210, 20, 10, MUTED_COLOR)
    AddLabel(header, "LAST SEEN", 735, 0, 180, 20, 10, MUTED_COLOR)

    local scroll = CreateFrame("ScrollFrame", "AshoholicRosterScroll", rosterFrame)
    scroll:SetPoint("TOPLEFT", 20, -101)
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

    local status = AddLabel(rosterFrame, "", 24, -526, 980, 16, 10, MUTED_COLOR)
    tinsert(UISpecialFrames, "AshoholicRosterFrame")

    rosterFrame.content = content
    rosterFrame.scroll = scroll
    rosterFrame.status = status
    rosterFrame.headingPool = {}
    rosterFrame.characterPool = {}
    rosterFrame.messagePool = {}
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

    row.name = AddLabel(row, "", 12, -2, 230, 18, 12, TEXT_COLOR)
    row.realm = AddLabel(row, "", 12, -19, 230, 12, 9, MUTED_COLOR)
    row.level = AddLabel(row, "", 260, -2, 65, 32, 11, TEXT_COLOR)
    row.gold = AddLabel(row, "", 340, -2, 145, 32, 11, TEXT_COLOR)
    row.location = AddLabel(row, "", 500, -2, 210, 32, 11, TEXT_COLOR)
    row.lastSeen = AddLabel(row, "", 735, -2, 180, 32, 11, TEXT_COLOR)
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
    row.gold:SetText(FormatCopper(character.gold))
    row.location:SetText(character.location or UNKNOWN_TEXT)
    row.lastSeen:SetText(FormatLastSeen(character.lastSeen))
    row:Show()
end

function UI.RefreshRoster()
    if not frame then
        return
    end

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
    frame.scroll:SetVerticalScroll(0)
    frame.status:SetText(
        characterCount .. " saved character"
            .. (characterCount == 1 and "" or "s")
            .. "  |  Last seen is when Ashoholic last collected that character's basics."
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
end
