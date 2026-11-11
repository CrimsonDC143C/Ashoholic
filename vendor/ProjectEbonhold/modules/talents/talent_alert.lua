local addonName, addon = ...

-- ── Unspent talent points: yellow alert bubble ───────────────────────────────
-- Same GlowBox bubble as the Skill Tree's (skillTreeMicroButton.lua), pointing at
-- the Talents micro button while the active spec has points left to spend. Closing
-- it, or opening the talent window, silences it until a new point is earned.
-- The bubbles of the bar take turns (GuidedTour.BarAlerts).

if not TalentMicroButton then return end

local Alert = CreateFrame("Frame", "EbonholdTalentPointsAlert", UIParent, "GlowBoxTemplate")
Alert:SetSize(220, 85)
Alert:SetFrameStrata("DIALOG")
Alert:SetFrameLevel(10)
Alert:EnableMouse(true)
Alert:Hide()
ProjectEbonhold.GuidedTour.BarAlerts.Add(Alert, 2)

Alert.Text = Alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
Alert.Text:SetJustifyV("TOP")
Alert.Text:SetSize(188, 0)
Alert.Text:SetPoint("TOPLEFT", 16, -24)

Alert.CloseButton = CreateFrame("Button", nil, Alert, "UIPanelCloseButton")
Alert.CloseButton:SetPoint("TOPRIGHT", 6, 6)

Alert.Arrow = CreateFrame("Frame", nil, Alert, "GlowBoxArrowTemplate")
Alert.Arrow:SetPoint("TOP", Alert, "BOTTOM", 0, 4)
Alert:SetPoint("BOTTOM", TalentMicroButton, "TOP", 0, 10)

-- Clicking the bubble opens the talents, like the button it points at.
Alert:SetScript("OnMouseUp", function()
    if ProjectEbonhold.TalentFrame and not ProjectEbonhold.TalentFrame.IsShown() then
        ProjectEbonhold.TalentFrame.Toggle()
    end
end)

local silencedAt = 0 -- point count the player already saw; the bubble returns above it

local function UnspentPoints()
    local tg = GetActiveTalentGroup(false, false) or 1
    return GetUnspentTalentPoints(false, false, tg) or 0
end

local function TalentWindowShown()
    return ProjectEbonhold.TalentFrame and ProjectEbonhold.TalentFrame.IsShown()
end

local function Refresh()
    local points = UnspentPoints()
    if points < silencedAt then silencedAt = points end

    if points <= 0 or points <= silencedAt or TalentWindowShown() then
        Alert:Hide()
        return
    end

    Alert.Text:SetText(string.format("You have %d unspent talent point%s! Open your Talents to spend %s.",
        points, points == 1 and "" or "s", points == 1 and "it" or "them"))
    Alert:SetHeight(math.max(85, Alert.Text:GetStringHeight() + 40))
    Alert:Show()
end

local function Silence()
    silencedAt = UnspentPoints()
    Alert:Hide()
end

Alert.CloseButton:SetScript("OnClick", Silence)

if EbonholdTalentFrame then
    EbonholdTalentFrame:HookScript("OnShow", Silence)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:SetScript("OnEvent", Refresh)
