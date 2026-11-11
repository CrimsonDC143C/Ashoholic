local addon, Addon = ...
LoadAddOn("Blizzard_TalentUI")
CreateFrame("Button", "SkillTreeMicroButton", MainMenuBarArtFrame, "MainMenuBarMicroButton")


LoadMicroButtonTextures(SkillTreeMicroButton, "Help")


local buttonTexture = [[Interface\AddOns\ProjectEbonhold\assets\inv_soulash]]


local function setupButton()
    SkillTreeMicroButton:SetNormalTexture([[Interface\AddOns\ProjectEbonhold\assets\ui-microbuttonstreamdl-up]])
    SkillTreeMicroButton:SetPushedTexture([[Interface\AddOns\ProjectEbonhold\assets\ui-microbuttonstreamdl-down]])
    SkillTreeMicroButton:SetHighlightTexture([[Interface\Buttons\UI-MicroButton-Hilight]])

    SkillTreeMicroButton.tooltipText = "Skill Tree"
    SkillTreeMicroButton.newbieText = "Open your Skill Tree."

    -- Deliberately NOT shown: the unified Character Progression micro button
    -- (EchoJournalMicroButton) covers the Skill Tree tab now.
    UpdateMicroButtons()
end


-- PvP micro button removed: the Character Progression button (a.k.a.
-- EchoJournalMicroButton) takes its spot. The Skill Tree button is no
-- longer on the bar either -- its tab lives inside the same unified
-- Collections window that button opens.
local function getCoreMicroButtons()
    local ordered = {}
    local function addButton(b)
        if b then table.insert(ordered, b) end
    end
    addButton(CharacterMicroButton)
    addButton(SpellbookMicroButton)
    addButton(TalentMicroButton)
    addButton(AchievementMicroButton)
    addButton(QuestLogMicroButton)
    addButton(SocialsMicroButton)
    addButton(EchoJournalMicroButton) -- created in modules/perks/echo_journal.lua
    addButton(LFDMicroButton)
    addButton(ToolbeltMicroButton) -- created in modules/toolbelt/toolbelt.lua
    addButton(MainMenuMicroButton)
    addButton(HelpMicroButton)
    return ordered
end


local function positionButtons()
    if Dominos and Dominos.MenuBar then
        local buttons = getCoreMicroButtons()

        function Dominos.MenuBar:NumButtons()
            return #buttons
        end

        function Dominos.MenuBar:AddButton(i)
            local b = buttons[i]
            if b then
                b:SetParent(self.header)
                b:Show()
                self.buttons[i] = b
            end
        end

        local menuBar = Dominos.Frame:Get("menu")
        if menuBar and not InCombatLockdown() then
            menuBar.buttons = buttons
            menuBar:LoadButtons()
            menuBar:Layout()
        end
        return
    end

    if Bartender4 then
        -- Wait for Bartender4 to fully initialize
        C_Timer.After(0.5, function()
            local microMenuModule = Bartender4:GetModule("MicroMenu", true)
            if microMenuModule and microMenuModule.bar then
                local buttons = getCoreMicroButtons()
                -- Hook into Bartender4's button creation
                microMenuModule.bar.buttons = {}

                for i, button in ipairs(buttons) do
                    button:ClearAllPoints()
                    button:SetParent(microMenuModule.bar)
                    button:Show()
                    button:SetFrameLevel(microMenuModule.bar:GetFrameLevel() + 1)
                    microMenuModule.bar.buttons[i] = button
                end

                microMenuModule.button_count = #buttons

                -- Force reposition
                if microMenuModule.bar.LayoutButtons then
                    microMenuModule.bar:LayoutButtons()
                elseif microMenuModule.bar.Layout then
                    microMenuModule.bar:Layout()
                end

                -- Manually position if layout didn't work
                for i, button in ipairs(buttons) do
                    if i == 1 then
                        button:SetPoint("BOTTOMLEFT", microMenuModule.bar, "BOTTOMLEFT", -5, -5)
                    else
                        button:SetPoint("LEFT", buttons[i - 1], "RIGHT", -5, -5)
                    end
                end
            end
        end)
        return
    end

    if UnitHasVehicleUI("player") then
        return
    end

    local buttons = getCoreMicroButtons()

    for i, button in ipairs(buttons) do
        button:ClearAllPoints()
        if i == 1 then
            button:SetPoint("BOTTOMLEFT", MainMenuBarArtFrame, "BOTTOMLEFT", 545, 2)
        else
            button:SetPoint("BOTTOMLEFT", buttons[i - 1], "BOTTOMRIGHT", -4, 0)
        end
        button:Show()
    end

    if PVPMicroButton then
        PVPMicroButton:Hide()
    end
end


SkillTreeMicroButton:SetScript("OnEvent", function(self, event)
    if event == "UPDATE_BINDINGS" or event == "PLAYER_ENTERING_WORLD" then
        setupButton()
        positionButtons()
    end
end)


SkillTreeMicroButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        SkillTreeMicroButton_StopFlashing()
        SkillTreeMicroButton_HideAlert()
        -- skillTreeFrame is now always a native child of CollectionsJournal's
        -- Skill Tree tab (id 2), so opening/closing it means opening/closing
        -- Collections on that tab, not just Show()/Hide() on the frame itself
        -- (skillTreeFrame:IsShown() alone can't tell if it's actually visible,
        -- since that depends on CollectionsJournal being shown too).
        local isOpenOnSkillTree = CollectionsJournal and CollectionsJournal:IsShown()
            and PanelTemplates_GetSelectedTab(CollectionsJournal) == 2
        if isOpenOnSkillTree then
            SetCollectionsJournalShown(false)
        else
            SetCollectionsJournalShown(true, 2)
        end
    end
end)


SkillTreeMicroButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltipText, 1, 1, 1)
    if self.newbieText then
        GameTooltip:AddLine(self.newbieText, nil, nil, nil, true)
    end
    GameTooltip:Show()
end)

SkillTreeMicroButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)


hooksecurefunc("VehicleMenuBar_MoveMicroButtons", function(skinName)
    if not skinName and not UnitHasVehicleUI("player") then
        positionButtons()
    end
end)

-- The level lockouts of the Talent / Dungeon Finder / Achievement buttons are lifted by
-- re-enabling them after every UpdateMicroButtons (the hooksecurefunc below), NEVER by writing
-- their minLevel / Disable / disabledTooltip. UpdateMicroButtons reads minLevel and calls
-- Disable(): a value or method written by the addon taints that Blizzard call, and
-- SpellBookFrame_OnShow makes it right before rebuilding the spell list. The spell buttons then
-- carry the taint and clicking a spell is refused ("ProjectEbonhold has been blocked from an
-- action only available to the Blizzard UI", 2026-10-13).
if TalentMicroButton then
    TalentMicroButton:Enable()
    TalentMicroButton:SetScript("OnEvent", nil)

    -- ToggleTalentFrame() early-returns below level 10. Replace the click handler
    -- with one that opens the three-tree talent window (talents/talent_frame.lua),
    -- falling back to the stock talent UI if that module is missing.
    TalentMicroButton:SetScript("OnClick", function(self)
        if ProjectEbonhold and ProjectEbonhold.TalentFrame then
            ProjectEbonhold.TalentFrame.Toggle()
            return
        end
        if not PlayerTalentFrame then
            local loaded, reason = LoadAddOn("Blizzard_TalentUI")
            if not loaded and DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[ProjectEbonhold]|r Failed to load Blizzard_TalentUI: " .. tostring(reason))
            end
        end
        if PlayerTalentFrame then
            if PlayerTalentFrame:IsShown() then
                HideUIPanel(PlayerTalentFrame)
            else
                ShowUIPanel(PlayerTalentFrame)
            end
        end
    end)
end

if LFDMicroButton then
    LFDMicroButton:Enable()
    LFDMicroButton:SetScript("OnEvent", nil)

    -- PVEFrame_ToggleFrame() / ToggleLFDParentFrame can early-return below level 15.
    -- Replace the click handler so all dungeon finder tabs are accessible.
    LFDMicroButton:SetScript("OnClick", function(self)
        if PVEFrame_ToggleFrame then
            PVEFrame_ToggleFrame("GroupFinderFrame")
        elseif ToggleLFDParentFrame then
            ToggleLFDParentFrame()
        end
    end)
end

-- The summary page asks GetAchievementInfo for the latest completed achievements; an id the
-- client's Achievement.dbc does not know comes back with nil points and AchievementShield_SetPoints
-- errors on the comparison. Treat missing points as 0 so the window still opens.
local achievementShieldGuarded = false
local function guardAchievementShield()
    if achievementShieldGuarded or not AchievementShield_SetPoints then return end
    achievementShieldGuarded = true
    local orig = AchievementShield_SetPoints
    AchievementShield_SetPoints = function(points, ...)
        return orig(points or 0, ...)
    end

    -- With nothing completed the summary pads itself with stock default ids (6, 503, 1150...).
    -- Ashendor's Achievement.dbc (patch-6) is a custom catalogue of 909 rows that holds none of
    -- them, so GetAchievementInfo returns nil and the page errors. Point the defaults at ids the
    -- catalogue really has: the first achievement of the first categories.
    local defaults = ACHIEVEMENTUI_DEFAULTSUMMARYACHIEVEMENTS
    if defaults and GetCategoryList and GetAchievementInfo then
        local found = {}
        for _, cat in ipairs(GetCategoryList() or {}) do
            local id = GetAchievementInfo(cat, 1)
            if id then found[#found + 1] = id end
            if #found >= 8 then break end
        end
        if #found > 0 then
            for i = #defaults, 1, -1 do defaults[i] = nil end
            for i, id in ipairs(found) do defaults[i] = id end
        end
    end

    -- Safety net: keep the stock behaviour when it works, hide the summary rows when it does not.
    local origSummary = AchievementFrameSummary_UpdateAchievements
    if origSummary then
        AchievementFrameSummary_UpdateAchievements = function(...)
            local ok = pcall(origSummary, ...)
            if not ok then
                for i = 1, 12 do
                    local row = _G["AchievementFrameSummaryAchievement" .. i]
                    if row then row:Hide() end
                end
            end
        end
    end
end

local achievementGuardFrame = CreateFrame("Frame")
achievementGuardFrame:RegisterEvent("ADDON_LOADED")
achievementGuardFrame:SetScript("OnEvent", function(self, event, name)
    if name == "Blizzard_AchievementUI" then
        guardAchievementShield()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
guardAchievementShield()

if AchievementMicroButton then
    AchievementMicroButton:Enable()

    -- Open the achievement window at any level (the stock handler can refuse below 10).
    AchievementMicroButton:SetScript("OnClick", function(self)
        -- Blizzard_AchievementUI is load-on-demand; ToggleAchievementFrame silently
        -- returns when CanShowAchievementUI() is false, so drive the frame directly.
        if not AchievementFrame and AchievementFrame_LoadUI then
            pcall(AchievementFrame_LoadUI)
        end
        if not AchievementFrame then
            pcall(LoadAddOn, "Blizzard_AchievementUI")
        end
        guardAchievementShield()
        -- Open through Blizzard's own toggle: it also selects tab 1, which shows the Summary
        -- subframe. A bare ShowUIPanel left the empty achievement list on screen (rows still
        -- reading the template's "For the Alliance!"), since "summary" is already the selected
        -- category and selecting it again does nothing (2026-11-03).
        if AchievementFrame and AchievementFrame_ToggleAchievementFrame then
            AchievementFrame_ToggleAchievementFrame()
        elseif AchievementFrame then
            if AchievementFrame:IsShown() then
                HideUIPanel(AchievementFrame)
            else
                ShowUIPanel(AchievementFrame)
            end
        elseif DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[ProjectEbonhold]|r Achievement UI failed to load.")
        end
    end)
end

hooksecurefunc("UpdateMicroButtons", function()
    -- Keep the removed PvP micro button hidden (the default UI re-shows it)

    -- Enable() only: see the note above TalentMicroButton (no minLevel / disabledTooltip writes)
    if AchievementMicroButton then
        AchievementMicroButton:Enable()
    end

    if PVPMicroButton then
        PVPMicroButton:Hide()
    end

    -- Same for the retired Skill Tree button: the unified Character
    -- Progression micro button covers that tab now.
    SkillTreeMicroButton:Hide()

    if TalentMicroButton then
        TalentMicroButton:Enable()
    end

    if LFDMicroButton then
        LFDMicroButton:Enable()
    end
end)


-- The Skill Tree button is retired from the bar: unspent-point nudges
-- (flash + alert bubble, triggered from skillTree_service) land on the
-- unified Character Progression micro button instead.
local function GetNudgeTarget()
    return EchoJournalMicroButton or SkillTreeMicroButton
end

local isFlashing = false
local flashFrame = CreateFrame("Frame")
local flashState = false

local function startFlashing()
    if isFlashing then return end
    isFlashing = true
    flashState = false
    flashFrame.timer = 0

    flashFrame:SetScript("OnUpdate", function(self, elapsed)
        if ProjectEbonhold_IsClosing then self:SetScript("OnUpdate", nil) return end
        if not UIParent:IsShown() then return end
        elapsed = math.min(elapsed, 0.1) -- Cap elapsed to prevent freeze after alt-tab
        self.timer = self.timer + elapsed
        if self.timer >= 0.5 then
            self.timer = 0
            flashState = not flashState
            if flashState then
                GetNudgeTarget():LockHighlight()
            else
                GetNudgeTarget():UnlockHighlight()
            end
        end
    end)
end

local function stopFlashing()
    isFlashing = false
    flashFrame:SetScript("OnUpdate", nil)
    GetNudgeTarget():UnlockHighlight()
end


function SkillTreeMicroButton_StartFlashing()
    startFlashing()
end

function SkillTreeMicroButton_StopFlashing()
    stopFlashing()
end

SkillTreeMicroButton.Alert = CreateFrame("Frame", "SkillTreeMicroButtonAlert", UIParent, "GlowBoxTemplate")
SkillTreeMicroButton.Alert:SetSize(220, 85)
-- Anchored above the unified Character Progression button (the Skill Tree
-- button itself is no longer on the bar).
SkillTreeMicroButton.Alert:SetPoint("BOTTOM", GetNudgeTarget(), "TOP", 0, 10)
SkillTreeMicroButton.Alert:SetFrameStrata("DIALOG")
SkillTreeMicroButton.Alert:SetFrameLevel(10)
SkillTreeMicroButton.Alert:EnableMouse(true)
SkillTreeMicroButton.Alert:Hide()
ProjectEbonhold.GuidedTour.BarAlerts.Add(SkillTreeMicroButton.Alert, 3)

SkillTreeMicroButton.Alert.Text = SkillTreeMicroButton.Alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
SkillTreeMicroButton.Alert.Text:SetJustifyV("TOP")
SkillTreeMicroButton.Alert.Text:SetSize(188, 0)
SkillTreeMicroButton.Alert.Text:SetPoint("TOPLEFT", 16, -24)
local DEFAULT_ALERT_TEXT =
    "You have unspent Skill Points! Open your Skill Tree to empower yourself with new abilities."
SkillTreeMicroButton.Alert.Text:SetText(DEFAULT_ALERT_TEXT)

SkillTreeMicroButton.Alert.CloseButton = CreateFrame("Button", nil, SkillTreeMicroButton.Alert, "UIPanelCloseButton")
SkillTreeMicroButton.Alert.CloseButton:SetPoint("TOPRIGHT", 6, 6)
SkillTreeMicroButton.Alert.CloseButton:SetScript("OnClick", function()
    SkillTreeMicroButton_HideAlert()
end)

SkillTreeMicroButton.Alert.Arrow = CreateFrame("Frame", nil, SkillTreeMicroButton.Alert, "GlowBoxArrowTemplate")
SkillTreeMicroButton.Alert.Arrow:SetPoint("TOP", SkillTreeMicroButton.Alert, "BOTTOM", 0, 4)


-- text: optional message (e.g. a class level reached). A message given here stays
-- until the player closes the bubble or opens the window: the plain "unspent points"
-- nudge fires on every currency update and must not overwrite it a second later.
function SkillTreeMicroButton_ShowAlert(text)
    local alert = SkillTreeMicroButton.Alert
    if not alert then return end
    if text then
        alert.pinned = true
        alert.Text:SetText(text)
    elseif not alert.pinned then
        alert.Text:SetText(DEFAULT_ALERT_TEXT)
    end
    alert:SetHeight(math.max(85, alert.Text:GetStringHeight() + 40))
    alert:Show()
end

function SkillTreeMicroButton_HideAlert()
    if SkillTreeMicroButton.Alert then
        SkillTreeMicroButton.Alert.pinned = nil
        SkillTreeMicroButton.Alert:Hide()
    end
end

SkillTreeMicroButton:RegisterEvent("UPDATE_BINDINGS")
SkillTreeMicroButton:RegisterEvent("PLAYER_ENTERING_WORLD")
SkillTreeMicroButton:Hide()
