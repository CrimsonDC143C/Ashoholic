local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.WorldChannelUI = {}

local channels = ProjectEbonhold.WorldChannelService.Channels

-- Create the popup frame
local popup = CreateFrame("Frame", "WorldChannelPopupFrame", UIParent)
popup:SetWidth(440)
popup:SetHeight(360)
popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
popup:SetFrameStrata("DIALOG")
popup:SetFrameLevel(100)
popup:Hide()

-- Background
popup.bg = popup:CreateTexture(nil, "BACKGROUND")
popup.bg:SetPoint("TOPLEFT", popup, "TOPLEFT", 11, -12)
popup.bg:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -12, 11)
popup.bg:SetTexture(0, 0, 0, 0.9)

-- Border
popup.border = CreateFrame("Frame", nil, popup)
popup.border:SetAllPoints()
popup.border:SetBackdrop({
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})

-- Title
popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
popup.title:SetPoint("TOP", popup, "TOP", 0, -20)
popup.title:SetText("|cff00ff00Join Community Channels|r")

-- Message
popup.message = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
popup.message:SetPoint("TOP", popup.title, "BOTTOM", 0, -14)
popup.message:SetWidth(390)
popup.message:SetJustifyH("CENTER")
popup.message:SetText("Choose the chat channel(s) you would like to join to talk with the community")

-- Support note: support is English-only and handled through the GM ticket
-- system, not these chat channels.
popup.note = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
popup.note:SetPoint("TOP", popup.message, "BOTTOM", 0, -10)
popup.note:SetWidth(390)
popup.note:SetJustifyH("CENTER")
popup.note:SetText("|cffffd100Note:|r Staff help is available in English only, via the in-game GM ticket system, not through these channels.")

-- One checkbox per channel. Create them first so we can measure the widest
-- row, then lay them out as a left-aligned column that is centered as a block
-- within the popup.
popup.checkboxes = {}
local checkboxList = {}
local maxRowWidth = 0
for i, ch in ipairs(channels) do
    local cb = CreateFrame("CheckButton", "WorldChannelPopupCheck" .. i, popup, "InterfaceOptionsCheckButtonTemplate")
    local text = _G[cb:GetName() .. "Text"]
    text:SetText(ch.label)
    local rowWidth = cb:GetWidth() + 2 + text:GetStringWidth()
    if rowWidth > maxRowWidth then maxRowWidth = rowWidth end
    popup.checkboxes[ch.name] = cb
    checkboxList[i] = cb
end

-- Shared left edge that centers the widest row within the popup; every row
-- uses it, so the column stays left-aligned while the block is centered.
local noteLeft = (popup:GetWidth() - popup.note:GetWidth()) / 2
local columnLeftFromNote = (popup:GetWidth() - maxRowWidth) / 2 - noteLeft
local anchor = popup.note
local anchorOffset = -30 -- gap below the note text; matches the footer gap (desiredGap)
for i, cb in ipairs(checkboxList) do
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (i == 1) and columnLeftFromNote or 0, anchorOffset)
    anchor = cb
    anchorOffset = -4
end

-- Apply Button: joins checked channels and leaves unchecked ones.
popup.joinButton = utils.CreateSimpleCustomButton(
    popup,
    "Apply",
    function()
        PlaySound("igMainMenuOption")
        local selected = {}
        for _, ch in ipairs(channels) do
            local cb = popup.checkboxes[ch.name]
            if cb and cb:GetChecked() then
                table.insert(selected, ch.name)
            end
        end
        if ProjectEbonhold.WorldChannelService then
            ProjectEbonhold.WorldChannelService.ApplySelection(selected)
        end
        popup:Hide()
    end,
    150,
    36
)
popup.joinButton:SetPoint("BOTTOM", popup, "BOTTOM", -80, 20)

popup.joinButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Join the channels you checked and leave the ones you unchecked", 1, 1, 1)
    GameTooltip:Show()
end)
popup.joinButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

-- Close Button
popup.closeButton = utils.CreateSimpleCustomButton(
    popup,
    "Close",
    function()
        PlaySound("igMainMenuOptionCheckBoxOn")
        if ProjectEbonhold.WorldChannelService then
            ProjectEbonhold.WorldChannelService.Decline()
        end
        popup:Hide()
    end,
    150,
    36
)
popup.closeButton:SetPoint("BOTTOM", popup, "BOTTOM", 80, 20)

popup.closeButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("You can always join later with /join <channel> (e.g. /join world)", 1, 1, 1)
    GameTooltip:Show()
end)
popup.closeButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

-- Slash-command hint: tells players how to reopen this window later.
popup.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
popup.hint:SetPoint("BOTTOM", popup, "BOTTOM", 0, 62)
popup.hint:SetWidth(390)
popup.hint:SetJustifyH("CENTER")
popup.hint:SetText("Reopen this window anytime with |cff00ff00/worldchannel|r to join or leave.")

-- The footer (hint + buttons) is anchored to the popup's bottom edge, so the
-- fixed height leaves a gap between the last checkbox and the footer. On show,
-- trim that gap to a fixed target. Self-stabilizing: once trimmed, later shows
-- see the target gap and leave the height alone.
popup:SetScript("OnShow", function(self)
    local lastCb = checkboxList[#checkboxList]
    if not lastCb then return end
    local cbBottom, hintTop = lastCb:GetBottom(), popup.hint:GetTop()
    if not cbBottom or not hintTop then return end
    local desiredGap = 30
    local actualGap = cbBottom - hintTop
    if actualGap > desiredGap then
        self:SetHeight(self:GetHeight() - (actualGap - desiredGap))
    end
end)

-- Function to show the prompt. Pre-checks the English default and any channel
-- the player is already in, so existing members see their state reflected.
function ProjectEbonhold.WorldChannelUI.ShowPrompt()
    for _, ch in ipairs(channels) do
        local cb = popup.checkboxes[ch.name]
        if cb then
            local alreadyJoined = ProjectEbonhold.WorldChannelService.IsInChannel(ch.name)
            cb:SetChecked(ch.default or alreadyJoined)
        end
    end
    popup:Show()
    PlaySound("igQuestListOpen")
end

-- ESC key handler
tinsert(UISpecialFrames, "WorldChannelPopupFrame")
