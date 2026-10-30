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

if TalentMicroButton then
    TalentMicroButton.minLevel = 1
    TalentMicroButton.disabledTooltip = nil
    -- Neutralize the default UI's level-10 lockout: prevent any future Disable()
    TalentMicroButton.Disable = function() end
    TalentMicroButton:Enable()
    TalentMicroButton:SetScript("OnEvent", nil)

    -- ToggleTalentFrame() early-returns below level 10. Replace the click handler
    -- with one that loads and shows the talent UI directly.
    TalentMicroButton:SetScript("OnClick", function(self)
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
    LFDMicroButton.minLevel = 1
    LFDMicroButton.disabledTooltip = nil
    -- Neutralize the default UI's level-15 lockout: prevent any future Disable()
    LFDMicroButton.Disable = function() end
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

hooksecurefunc("UpdateMicroButtons", function()
    -- Keep the removed PvP micro button hidden (the default UI re-shows it)
    if PVPMicroButton then
        PVPMicroButton:Hide()
    end

    -- Same for the retired Skill Tree button: the unified Character
    -- Progression micro button covers that tab now.
    SkillTreeMicroButton:Hide()

    if TalentMicroButton then
        TalentMicroButton.minLevel = 1
        TalentMicroButton.disabledTooltip = nil
        TalentMicroButton:Enable()
    end

    if LFDMicroButton then
        LFDMicroButton.minLevel = 1
        LFDMicroButton.disabledTooltip = nil
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

SkillTreeMicroButton.Alert.Text = SkillTreeMicroButton.Alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
SkillTreeMicroButton.Alert.Text:SetJustifyV("TOP")
SkillTreeMicroButton.Alert.Text:SetSize(188, 0)
SkillTreeMicroButton.Alert.Text:SetPoint("TOPLEFT", 16, -24)
SkillTreeMicroButton.Alert.Text:SetText(
    "You have unspent Skill Points! Open your Skill Tree to empower yourself with new abilities.")

SkillTreeMicroButton.Alert.CloseButton = CreateFrame("Button", nil, SkillTreeMicroButton.Alert, "UIPanelCloseButton")
SkillTreeMicroButton.Alert.CloseButton:SetPoint("TOPRIGHT", 6, 6)
SkillTreeMicroButton.Alert.CloseButton:SetScript("OnClick", function()
    SkillTreeMicroButton.Alert:Hide()
end)

SkillTreeMicroButton.Alert.Arrow = CreateFrame("Frame", nil, SkillTreeMicroButton.Alert, "GlowBoxArrowTemplate")
SkillTreeMicroButton.Alert.Arrow:SetPoint("TOP", SkillTreeMicroButton.Alert, "BOTTOM", 0, 4)


function SkillTreeMicroButton_ShowAlert()
    if SkillTreeMicroButton.Alert then
        SkillTreeMicroButton.Alert:Show()
    end
end

function SkillTreeMicroButton_HideAlert()
    if SkillTreeMicroButton.Alert then
        SkillTreeMicroButton.Alert:Hide()
    end
end

SkillTreeMicroButton:RegisterEvent("UPDATE_BINDINGS")
SkillTreeMicroButton:RegisterEvent("PLAYER_ENTERING_WORLD")
SkillTreeMicroButton:Hide()
