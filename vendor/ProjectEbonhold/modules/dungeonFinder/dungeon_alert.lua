local addonName, addon = ...

-- ── Level 15: yellow alert bubble on the Dungeon Finder button ───────────────
-- Same GlowBox bubble as talent_alert.lua. It tells a character reaching level 15 that
-- dungeons are open. Once per character: closing it, clicking it or opening the Dungeon
-- Finder ends it. The bubbles of the bar take turns (GuidedTour.BarAlerts): a level brings
-- talent points, so its turn can come past level 15 and the state is kept until then.

if not LFDMicroButton then return end

local ALERT_LEVEL = 15

local Alert = CreateFrame("Frame", "EbonholdDungeonAlert", UIParent, "GlowBoxTemplate")
Alert:SetSize(220, 85)
Alert:SetFrameStrata("DIALOG")
Alert:SetFrameLevel(30)
Alert:SetClampedToScreen(true)
Alert:EnableMouse(true)
Alert:Hide()
ProjectEbonhold.GuidedTour.BarAlerts.Add(Alert, 4)

Alert.Text = Alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
Alert.Text:SetJustifyV("TOP")
Alert.Text:SetSize(188, 0)
Alert.Text:SetPoint("TOPLEFT", 16, -24)

Alert.CloseButton = CreateFrame("Button", nil, Alert, "UIPanelCloseButton")
Alert.CloseButton:SetPoint("TOPRIGHT", 6, 6)

Alert.Arrow = CreateFrame("Frame", nil, Alert, "GlowBoxArrowTemplate")
Alert.Arrow:SetPoint("TOP", Alert, "BOTTOM", 0, 4)

local function CharKey()
    return (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
end

-- per character: nil = level 15 not reached here, "pending" = its turn is due, true = done
local function State()
    return ProjectEbonholdDB and ProjectEbonholdDB.dungeonAlertSeen
        and ProjectEbonholdDB.dungeonAlertSeen[CharKey()]
end

local function SetState(state)
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.dungeonAlertSeen = ProjectEbonholdDB.dungeonAlertSeen or {}
    ProjectEbonholdDB.dungeonAlertSeen[CharKey()] = state
end

local function Silence()
    SetState(true)
    Alert:Hide()
end

local function Refresh(level)
    if (level or UnitLevel("player")) == ALERT_LEVEL and not State() then SetState("pending") end
    if State() ~= "pending" then
        Alert:Hide()
        return
    end
    local onButton = LFDMicroButton:IsVisible()
    Alert.Text:SetText(onButton
        and "You can now join dungeons! Click this button to open the Dungeon Finder."
        or "You can now join dungeons! Click here to open the Dungeon Finder.")
    Alert:SetHeight(math.max(85, Alert.Text:GetStringHeight() + 40))

    -- A UI addon can hide the micro bar: no button to point at, top of the screen, no arrow.
    Alert:ClearAllPoints()
    if onButton then
        Alert:SetPoint("BOTTOM", LFDMicroButton, "TOP", 0, 10)
        Alert.Arrow:Show()
    else
        Alert:SetPoint("TOP", UIParent, "TOP", 0, -140)
        Alert.Arrow:Hide()
    end
    Alert:Show()
end

Alert.CloseButton:SetScript("OnClick", Silence)

-- Clicking the bubble opens the Dungeon Finder, like the button it points at.
Alert:SetScript("OnMouseUp", function()
    Silence()
    if not (LFDParentFrame and LFDParentFrame:IsShown()) then LFDMicroButton:Click() end
end)

LFDMicroButton:HookScript("OnClick", Silence)
if LFDParentFrame then LFDParentFrame:HookScript("OnShow", Silence) end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(_, event, level)
    -- at PLAYER_LEVEL_UP UnitLevel still gives the old level
    Refresh(event == "PLAYER_LEVEL_UP" and level or nil)
end)
