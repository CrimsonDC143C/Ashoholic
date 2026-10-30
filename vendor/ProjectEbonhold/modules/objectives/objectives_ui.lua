local addon, Addon = ...

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.ObjectivesUI = {}

-- Quest type icon mappings
local QUEST_TYPE_ICONS = {
    [1] = { icon = "Interface\\Icons\\INV_Misc_Map_01", name = "Open World" },
    [2] = { icon = "Interface\\Icons\\INV_Misc_Key_04", name = "Dungeon" },
    [3] = { icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", name = "Raid" },
    [4] = { icon = "Interface\\Icons\\INV_Misc_Gear_01", name = "Profession" },
}

-- Difficulty mode labels and colors for reward tooltips
local DIFFICULTY_MODES = {
    { xpKey = "normalXp", soulAshKey = "normalSoulAshes", label = "Normal",       color = { 1.00, 1.00, 1.00 } },
    { xpKey = "hc1Xp",    soulAshKey = "hc1SoulAshes",    label = "Hardcore I",   color = { 1.00, 0.73, 0.73 } },
    { xpKey = "hc2Xp",    soulAshKey = "hc2SoulAshes",    label = "Hardcore II",  color = { 1.00, 0.47, 0.47 } },
    { xpKey = "hc3Xp",    soulAshKey = "hc3SoulAshes",    label = "Hardcore III", color = { 1.00, 0.20, 0.20 } },
    { xpKey = "hc4Xp",    soulAshKey = "hc4SoulAshes",    label = "Hardcore IV",  color = { 0.80, 0.00, 0.00 } },
    { xpKey = "hc5Xp",    soulAshKey = "hc5SoulAshes",    label = "Hardcore V",   color = { 0.60, 0.00, 0.00 } },
}

local function ShowRewardTooltip(owner, objective)
    if not objective then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")

    local isProfession = (objective.questType or 1) == 4

    if isProfession then
        GameTooltip:AddLine("Rewards", 1, 0.82, 0)
        GameTooltip:AddLine(" ", 1, 1, 1, true)

        -- Show only the normal reward inline (no label)
        local rewardParts = {}
        local playerLevel = UnitLevel("player") or 80
        local xpAmount = objective.normalXp or 0
        if playerLevel >= 80 then
            local goldAmount = math.floor(xpAmount * 6 / 10)
            table.insert(rewardParts, GetCoinTextureString(goldAmount))
        else
            if xpAmount > 0 then
                table.insert(rewardParts, xpAmount .. " XP")
            end
        end
        local soulAshAmount = objective.normalSoulAshes or 0
        if soulAshAmount > 0 then
            table.insert(rewardParts,
                "|cFF9966FF" ..
                soulAshAmount .. "|r |TInterface\\AddOns\\ProjectEbonhold\\assets\\inv_soulash:14:14|t")
        end
        if #rewardParts > 0 then
            GameTooltip:AddLine(table.concat(rewardParts, "  "), 1, 1, 1)
        end
    else
        GameTooltip:AddLine("Rewards by Difficulty", 1, 0.82, 0)
        GameTooltip:AddLine("Completing the objective on higher difficulties grants better rewards.", 1, 1, 1, true)
        GameTooltip:AddLine(" ", 1, 1, 1, true)

        for _, mode in ipairs(DIFFICULTY_MODES) do
            local xpAmount = objective[mode.xpKey] or 0
            local soulAshAmount = objective[mode.soulAshKey] or 0
            if xpAmount > 0 or soulAshAmount > 0 then
                local rewardParts = {}
                local playerLevel = UnitLevel("player") or 80
                if playerLevel >= 80 then
                    local goldAmount = math.floor(xpAmount * 6 / 10)
                    table.insert(rewardParts, GetCoinTextureString(goldAmount))
                else
                    if xpAmount > 0 then
                        table.insert(rewardParts, xpAmount .. " XP")
                    end
                end
                if soulAshAmount > 0 then
                    table.insert(rewardParts,
                        "|cFF9966FF" ..
                        soulAshAmount .. "|r |TInterface\\AddOns\\ProjectEbonhold\\assets\\inv_soulash:14:14|t")
                end
                if #rewardParts > 0 then
                    GameTooltip:AddDoubleLine(mode.label, table.concat(rewardParts, "  "), mode.color[1], mode.color[2],
                        mode.color[3], 1, 1, 1)
                end
            end
        end
    end

    GameTooltip:Show()
end

-- Confirmation popup
StaticPopupDialogs["EBONHOLD_CONFIRM_REROLL"] = {
    text = "Reroll selection?",
    button1 = "Confirm",
    button2 = "Cancel",
    OnShow = function(self)
        if ProjectEbonhold.ObjectivesService and ProjectEbonhold.ObjectivesService.GetRerollCost then
            local cost = ProjectEbonhold.ObjectivesService.GetRerollCost()
            self.text:SetText("Reroll selection for " .. GetCoinTextureString(cost) .. "?")
        end
    end,
    OnAccept = function()
        if ProjectEbonhold.ObjectivesService and ProjectEbonhold.ObjectivesService.RequestRerollObjectives then
            ProjectEbonhold.ObjectivesService.RequestRerollObjectives()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local COLUMNS = 3
local OBJECTIVE_FRAME_WIDTH = 250
local OBJECTIVE_FRAME_HEIGHT = 320
local PADDING = 10
local FRAME_MARGIN = 20

local mainFrame = nil
local objectiveFrames = {}
local isInObjectivesGossip = false

local function CreateObjectiveFrame(parent, index)
    local frame = CreateFrame("Frame", "ObjectiveFrame" .. index, parent)
    frame:SetSize(OBJECTIVE_FRAME_WIDTH, OBJECTIVE_FRAME_HEIGHT)

    -- Determine position: 3 columns, stacked vertically
    local col = ((index - 1) % COLUMNS)
    local row = math.floor((index - 1) / COLUMNS)

    local xOffset = col * (OBJECTIVE_FRAME_WIDTH + PADDING)
    local yOffset = -row * (OBJECTIVE_FRAME_HEIGHT + PADDING)

    -- Calculate total width of all objectives
    local totalWidth = COLUMNS * OBJECTIVE_FRAME_WIDTH + (COLUMNS - 1) * PADDING
    local startX = -totalWidth / 2 + OBJECTIVE_FRAME_WIDTH / 2

    frame:SetPoint("CENTER", parent, "CENTER", startX + xOffset, yOffset - 45)

    -- Background texture for objective
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\adventureguide")
    bg:SetTexCoord(0, 0.664062, 0.320312, 1)
    frame.bg = bg

    -- Title (Quest name)
    local titleText = frame:CreateFontString(nil, "OVERLAY")
    titleText:SetFont("Fonts\\MORPHEUS.TTF", 16)
    titleText:SetPoint("TOP", frame, "TOP", 0, -70)
    titleText:SetSize(OBJECTIVE_FRAME_WIDTH - 40, 28)
    titleText:SetWordWrap(false)
    titleText:SetJustifyH("CENTER")
    titleText:SetTextColor(0, 0, 0)
    titleText:SetShadowOffset(1, -1)
    titleText:SetShadowColor(0, 0, 0, 0.25)
    frame.titleText = titleText

    -- Objective text
    local objectiveText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    objectiveText:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -95)
    objectiveText:SetSize(OBJECTIVE_FRAME_WIDTH - 40, 80)
    objectiveText:SetWordWrap(true)
    objectiveText:SetTextColor(0.12, 0.12, 0.12)
    objectiveText:SetShadowOffset(0, 0)
    frame.objectiveText = objectiveText

    -- Select button
    local selectBtn = utils.CreateSimpleCustomButton(frame, "Select", nil, 150, 38)
    selectBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 30)
    frame.selectBtn = selectBtn

    -- Reward bag icon (top-left)
    local bagSize = 24
    local rewardBagFrame = CreateFrame("Frame", nil, frame)
    rewardBagFrame:SetSize(bagSize + 8, bagSize + 8)
    rewardBagFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -10)
    rewardBagFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
    rewardBagFrame:EnableMouse(true)

    local bagIcon = rewardBagFrame:CreateTexture(nil, "ARTWORK")
    bagIcon:SetSize(bagSize, bagSize)
    bagIcon:SetPoint("CENTER", rewardBagFrame, "CENTER", 0, 0)
    SetPortraitToTexture(bagIcon, "Interface\\Icons\\INV_Misc_Bag_07")

    local bagBorder = rewardBagFrame:CreateTexture(nil, "OVERLAY")
    bagBorder:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder")
    bagBorder:SetSize(bagSize + 26, bagSize + 26)
    bagBorder:SetPoint("CENTER", bagIcon, "CENTER", 0, 0)

    rewardBagFrame:SetScript("OnEnter", function(self)
        ShowRewardTooltip(self, self.objectiveData)
    end)
    rewardBagFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    rewardBagFrame.icon = bagIcon
    frame.rewardBagFrame = rewardBagFrame

    -- Quest type icon (top-right corner)
    local typeSize = 20
    local typeFrame = CreateFrame("Frame", nil, frame)
    typeFrame:SetSize(typeSize + 8, typeSize + 8)
    typeFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -10)
    typeFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
    typeFrame:EnableMouse(true)

    local typeIcon = typeFrame:CreateTexture(nil, "ARTWORK")
    typeIcon:SetSize(typeSize, typeSize)
    typeIcon:SetPoint("CENTER", typeFrame, "CENTER", 0, 0)
    SetPortraitToTexture(typeIcon, "Interface\\Icons\\INV_Misc_Map_01")

    local typeBorder = typeFrame:CreateTexture(nil, "OVERLAY")
    typeBorder:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder")
    typeBorder:SetSize(typeSize + 26, typeSize + 26)
    typeBorder:SetPoint("CENTER", typeIcon, "CENTER", 0, 0)

    typeFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(self.typeName or "Unknown", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    typeFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    typeFrame.icon = typeIcon
    frame.typeFrame = typeFrame

    -- Selected text (shown when this objective is active)
    local selectedText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    selectedText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 45)
    selectedText:SetText("Current Objective")
    selectedText:SetTextColor(0.3, 0.9, 0.3)
    selectedText:Hide()
    frame.selectedText = selectedText

    return frame
end

local function SelectObjective(index)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SELECT_OBJECTIVE, tostring(index))
end

local function UpdateObjectiveFrame(frame, objective, index)
    if not frame or not objective then return end

    -- Update title
    frame.titleText:SetText(objective.title or "")
    frame.titleText:SetTextColor(0, 0, 0)

    -- Update objective text
    frame.objectiveText:SetText(objective.objectiveText or "No objectives")
    frame.objectiveText:SetTextColor(0.12, 0.12, 0.12)

    -- Update reward bag
    if frame.rewardBagFrame then
        frame.rewardBagFrame.objectiveData = objective
        local hasReward = (objective.normalSoulAshes or 0) > 0 or (objective.normalXp or 0) > 0
        if hasReward then
            frame.rewardBagFrame:Show()
        else
            frame.rewardBagFrame:Hide()
        end
    end

    -- Update quest type icon
    if frame.typeFrame then
        local questType = objective.questType or 1
        local typeInfo = QUEST_TYPE_ICONS[questType] or QUEST_TYPE_ICONS[1]
        SetPortraitToTexture(frame.typeFrame.icon, typeInfo.icon)
        frame.typeFrame.typeName = typeInfo.name
        frame.typeFrame:Show()
    end

    -- Setup Select button
    if frame.selectBtn then
        frame.selectBtn:SetScript("OnClick", function()
            SelectObjective(index)
            -- Close properly like the X button
            -- First reset GossipFrame completely before anything else
            if GossipFrame then
                GossipFrame:SetAlpha(1)
                GossipFrame:EnableMouse(true)
                GossipFrame:ClearAllPoints()
                GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
            end
            isInObjectivesGossip = false
            -- Use the close button click to properly close gossip
            if GossipFrameCloseButton then
                GossipFrameCloseButton:Click()
            end
            if mainFrame then
                mainFrame:Hide()
            end
        end)
    end

    frame:Show()
end

local function CreateMainFrame()
    if mainFrame then return mainFrame end

    mainFrame = CreateFrame("Frame", "ObjectivesMainFrame", UIParent)
    mainFrame:SetSize(800, 450)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetFrameLevel(100)
    mainFrame:EnableMouse(true)
    mainFrame:SetClampedToScreen(true)

    -- Background texture
    local bgTexture = mainFrame:CreateTexture(nil, "BACKGROUND")
    bgTexture:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -4)
    bgTexture:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)
    bgTexture:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\dungeonjournaltierbackgrounds5")
    bgTexture:SetTexCoord(0, 0.767578, 0, 0.417969)

    -- Background
    mainFrame:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title
    local titleStr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleStr:SetPoint("TOP", mainFrame, "TOP", 0, -25)
    titleStr:SetText("OBJECTIVES")
    titleStr:SetTextColor(1, 0.82, 0)
    mainFrame.titleStr = titleStr

    -- Reroll button with gold cost
    local rerollCost = 0
    if ProjectEbonhold.ObjectivesService and ProjectEbonhold.ObjectivesService.GetRerollCost then
        rerollCost = ProjectEbonhold.ObjectivesService.GetRerollCost()
    end
    local rerollBtn = utils.CreateSimpleCustomButton(mainFrame,
        "Reroll Selection  " .. GetCoinTextureString(rerollCost, 10),
        function()
            if ProjectEbonhold.ObjectivesService and
                ProjectEbonhold.ObjectivesService.CanAffordReroll and
                not ProjectEbonhold.ObjectivesService.CanAffordReroll() then
                return
            end
            StaticPopup_Show("EBONHOLD_CONFIRM_REROLL")
        end, 220, 36)
    rerollBtn:SetPoint("TOP", titleStr, "BOTTOM", 0, -14)

    rerollBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Reroll Selection")
        local cost = 0
        if ProjectEbonhold.ObjectivesService and ProjectEbonhold.ObjectivesService.GetRerollCost then
            cost = ProjectEbonhold.ObjectivesService.GetRerollCost()
        end
        GameTooltip:AddLine("Cost: " .. GetCoinTextureString(cost), 1, 0.82, 0)
        if GetMoney() < cost then
            GameTooltip:AddLine("Not enough gold!", 1, 0.2, 0.2)
        end
        GameTooltip:Show()
    end)
    rerollBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    mainFrame.rerollBtn = rerollBtn

    -- Close button
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -5, -5)
    mainFrame.closeBtn = closeBtn

    -- Add to UISpecialFrames for ESC key handling
    tinsert(UISpecialFrames, "ObjectivesMainFrame")

    mainFrame:SetScript("OnHide", function()
        -- Only reset gossip state if we were actually in objectives gossip mode
        if isInObjectivesGossip then
            isInObjectivesGossip = false
            if GossipFrame then
                GossipFrame:SetAlpha(1)
                GossipFrame:EnableMouse(true)
                GossipFrame:ClearAllPoints()
                GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
            end
            -- Use the close button click to properly close gossip
            if GossipFrameCloseButton then
                GossipFrameCloseButton:Click()
            end
        end
    end)

    return mainFrame
end

local function DisplayObjectives(objectives)
    -- Don't show if player is interacting with taxi/flight path
    if TaxiFrame and TaxiFrame:IsShown() then
        return
    end

    -- Only allow showing if player is in objectives gossip
    if not isInObjectivesGossip then
        return
    end

    if not objectives or #objectives == 0 then
        if mainFrame then
            mainFrame:Hide()
        end
        return
    end

    -- Create main frame if needed
    if not mainFrame then
        CreateMainFrame()
    end

    -- Create/update objective frames
    for i = 1, #objectives do
        if not objectiveFrames[i] then
            objectiveFrames[i] = CreateObjectiveFrame(mainFrame, i)
        end
        UpdateObjectiveFrame(objectiveFrames[i], objectives[i], i - 1)
    end

    -- Hide extra frames
    for i = #objectives + 1, #objectiveFrames do
        objectiveFrames[i]:Hide()
    end

    -- Close QuestLogDetailFrame if open
    if QuestLogDetailFrame and QuestLogDetailFrame:IsShown() then
        HideUIPanel(QuestLogDetailFrame)
    end

    -- Check if player already has an active objective
    local activeObjective = nil
    if ProjectEbonhold.ObjectivesService and ProjectEbonhold.ObjectivesService.GetActiveObjective then
        activeObjective = ProjectEbonhold.ObjectivesService.GetActiveObjective()
    end

    -- Hide button and show "Selected" text for selected objective, disable buttons for others
    for i = 1, #objectives do
        if activeObjective and objectives[i].questId == activeObjective.questId then
            -- Selected objective: hide button, show "Selected" text
            if objectiveFrames[i].selectBtn then
                objectiveFrames[i].selectBtn:Hide()
            end
            if objectiveFrames[i].selectedText then
                objectiveFrames[i].selectedText:Show()
            end
        elseif activeObjective then
            -- Other objectives when one is active: disable buttons
            if objectiveFrames[i].selectBtn then
                objectiveFrames[i].selectBtn:Show()
                objectiveFrames[i].selectBtn:Disable()
            end
            if objectiveFrames[i].selectedText then
                objectiveFrames[i].selectedText:Hide()
            end
        else
            -- No active objective: enable all buttons
            if objectiveFrames[i].selectBtn then
                objectiveFrames[i].selectBtn:Show()
                objectiveFrames[i].selectBtn:Enable()
            end
            if objectiveFrames[i].selectedText then
                objectiveFrames[i].selectedText:Hide()
            end
        end
    end

    -- Enable/disable reroll button based on gold and update cost text
    if mainFrame.rerollBtn then
        local rerollCost = 0
        if ProjectEbonhold.ObjectivesService and ProjectEbonhold.ObjectivesService.GetRerollCost then
            rerollCost = ProjectEbonhold.ObjectivesService.GetRerollCost()
        end
        mainFrame.rerollBtn:SetText("Reroll Selection  " .. GetCoinTextureString(rerollCost, 10))

        local canAfford = not (ProjectEbonhold.ObjectivesService and
            ProjectEbonhold.ObjectivesService.CanAffordReroll and
            not ProjectEbonhold.ObjectivesService.CanAffordReroll())
        if canAfford then
            mainFrame.rerollBtn:Enable()
        else
            mainFrame.rerollBtn:Disable()
        end
    end

    mainFrame:Show()
end

local function HideObjectives()
    if mainFrame then
        mainFrame:Hide()
    end
end

local function ToggleObjectives()
    if mainFrame and mainFrame:IsShown() then
        HideObjectives()
    else
        if ProjectEbonhold.ObjectivesService then
            local objectives = ProjectEbonhold.ObjectivesService.GetCurrentObjectives()
            DisplayObjectives(objectives)
        end
    end
end

-- Export UI functions
ProjectEbonhold.ObjectivesUI.DisplayObjectives = DisplayObjectives
ProjectEbonhold.ObjectivesUI.HideObjectives = HideObjectives
ProjectEbonhold.ObjectivesUI.ToggleObjectives = ToggleObjectives
ProjectEbonhold.ObjectivesUI.GetMainFrame = function() return mainFrame end

-- ============================================
-- OBJECTIVE TRACKER (displayed next to quest tracker)
-- ============================================
local trackerFrame = nil

local function CreateTrackerFrame()
    if trackerFrame then return trackerFrame end

    local iconSize = 30
    trackerFrame = CreateFrame("Frame", "ObjectiveTrackerFrame", WatchFrame)
    trackerFrame:SetSize(iconSize + 50, iconSize + 50)
    trackerFrame:SetPoint("RIGHT", WatchFrame, "TOPLEFT", 0, 10)
    trackerFrame:SetFrameStrata("HIGH")

    -- Rotating light texture behind the icon (layer 1 - background)
    local lightTexture = trackerFrame:CreateTexture(nil, "BACKGROUND")
    lightTexture:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\progression_bar")
    lightTexture:SetTexCoord(0.023438, 0.210938, 0.283203, 0.478516)
    lightTexture:SetSize(iconSize + 44, iconSize + 44)
    lightTexture:SetPoint("CENTER", trackerFrame, "CENTER", 0, 0)
    lightTexture:SetBlendMode("ADD")
    trackerFrame.lightTexture = lightTexture

    -- Animation for rotation
    local animGroup = lightTexture:CreateAnimationGroup()
    local rotation = animGroup:CreateAnimation("Rotation")
    rotation:SetDegrees(360)
    rotation:SetDuration(8)
    animGroup:SetLooping("REPEAT")
    animGroup:Play()
    trackerFrame.animGroup = animGroup

    -- Reward icon (layer 2 - artwork)
    local rewardIcon = trackerFrame:CreateTexture(nil, "ARTWORK")
    rewardIcon:SetSize(iconSize, iconSize)
    rewardIcon:SetPoint("CENTER", trackerFrame, "CENTER", 0, 0)
    trackerFrame.rewardIcon = rewardIcon

    -- Border around the icon (layer 3 - overlay sublevel 1)
    local border = trackerFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    border:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder")
    border:SetSize(iconSize + 40, iconSize + 40)
    border:SetPoint("CENTER", rewardIcon, "CENTER", 0, 0)
    border:SetVertexColor(0.3, 0.9, 0.3)
    trackerFrame.border = border

    -- Small bonus icon at bottom (layer 4 - overlay sublevel 7)
    local bonusBadge = trackerFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    bonusBadge:SetSize(16, 16)
    bonusBadge:SetPoint("BOTTOMRIGHT", rewardIcon, "BOTTOMRIGHT", 12, -12)
    bonusBadge:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\objecticons")
    bonusBadge:SetTexCoord(0.128906, 0.250000, 0.250000, 0.375000)
    trackerFrame.bonusBadge = bonusBadge

    -- Make frame interactive for tooltip
    trackerFrame:EnableMouse(true)
    trackerFrame:SetScript("OnEnter", function(self)
        if trackerFrame.bonusSpellId and trackerFrame.bonusSpellId > 0 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("spell:" .. trackerFrame.bonusSpellId)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Complete your objective without dying to earn this reward.", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    trackerFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Reward bag icon (below the bonus icon)
    local trackerBagSize = 26
    local trackerBagFrame = CreateFrame("Frame", nil, trackerFrame)
    trackerBagFrame:SetSize(trackerBagSize + 8, trackerBagSize + 8)
    trackerBagFrame:SetPoint("TOP", trackerFrame, "BOTTOM", 0, -4)
    trackerBagFrame:SetFrameStrata("LOW")
    trackerBagFrame:SetFrameLevel(trackerFrame:GetFrameLevel() + 1)
    trackerBagFrame:EnableMouse(true)

    local trackerBagIcon = trackerBagFrame:CreateTexture(nil, "ARTWORK")
    trackerBagIcon:SetSize(trackerBagSize, trackerBagSize)
    trackerBagIcon:SetPoint("CENTER", trackerBagFrame, "CENTER", 0, 0)
    SetPortraitToTexture(trackerBagIcon, "Interface\\Icons\\INV_Misc_Bag_07")

    local trackerBagBorder = trackerBagFrame:CreateTexture(nil, "OVERLAY")
    trackerBagBorder:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder")
    trackerBagBorder:SetSize(trackerBagSize + 30, trackerBagSize + 30)
    trackerBagBorder:SetPoint("CENTER", trackerBagIcon, "CENTER", 0, 0)
    trackerBagBorder:SetVertexColor(0.9, 0.7, 0.2)

    trackerBagFrame:SetScript("OnEnter", function(self)
        ShowRewardTooltip(self, self.objectiveData)
    end)
    trackerBagFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    trackerBagFrame.icon = trackerBagIcon
    trackerBagFrame:Hide()
    trackerFrame.rewardBagFrame = trackerBagFrame

    trackerFrame:Hide()
    return trackerFrame
end

local function UpdateTracker(objective)
    if not trackerFrame then
        CreateTrackerFrame()
    end

    if not objective then
        trackerFrame:Hide()
        return
    end

    -- Update reward
    if objective.bonusSpellId and objective.bonusSpellId > 0 then
        local spellName, _, spellIcon = GetSpellInfo(objective.bonusSpellId)
        SetPortraitToTexture(trackerFrame.rewardIcon, spellIcon)
        trackerFrame.bonusSpellId = objective.bonusSpellId
        trackerFrame.rewardIcon:Show()
        trackerFrame.border:Show()
        trackerFrame.bonusBadge:Show()
        trackerFrame.lightTexture:Show()
    else
        trackerFrame.rewardIcon:Hide()
        trackerFrame.border:Hide()
        trackerFrame.bonusBadge:Hide()
        trackerFrame.lightTexture:Hide()
    end

    -- Update reward bag
    if trackerFrame.rewardBagFrame then
        trackerFrame.rewardBagFrame.objectiveData = objective
        local hasReward = (objective.normalSoulAshes or 0) > 0 or (objective.normalXp or 0) > 0
        if hasReward then
            trackerFrame.rewardBagFrame:Show()
        else
            trackerFrame.rewardBagFrame:Hide()
        end
    end

    trackerFrame:Show()
end

ProjectEbonhold.ObjectivesUI.UpdateTracker = UpdateTracker
ProjectEbonhold.ObjectivesUI.GetTrackerFrame = function() return trackerFrame end

local gossipEventFrame = CreateFrame("Frame")
gossipEventFrame:RegisterEvent("GOSSIP_SHOW")
gossipEventFrame:RegisterEvent("GOSSIP_CLOSED")
gossipEventFrame:SetScript("OnEvent", function(self, event)
    if event == "GOSSIP_SHOW" then
        -- Only process if GossipFrame is actually visible (real gossip interaction)
        if not GossipFrame or not GossipFrame:IsShown() then
            return
        end

        local npcName = GossipFrameNpcNameText and GossipFrameNpcNameText:GetText()
        if npcName == "Objectives Board" then
            isInObjectivesGossip = true
            if GossipFrame then
                GossipFrame:SetAlpha(0)
                GossipFrame:EnableMouse(false)
                GossipFrame:ClearAllPoints()
                GossipFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 1000, -1000)
            end
            if ProjectEbonhold.ObjectivesService then
                local objectives = ProjectEbonhold.ObjectivesService.GetCurrentObjectives()
                if objectives and #objectives > 0 then
                    DisplayObjectives(objectives)
                else
                    -- no cached proposals (login sync failed or never arrived):
                    -- fetch fresh ones; the service displays them on arrival
                    ProjectEbonhold.ObjectivesService.RequestObjectives()
                end
            end
        else
            if isInObjectivesGossip then
                isInObjectivesGossip = false
                HideObjectives()
            end
        end
    elseif event == "GOSSIP_CLOSED" then
        local wasInObjectivesGossip = isInObjectivesGossip
        isInObjectivesGossip = false
        if wasInObjectivesGossip and GossipFrame then
            GossipFrame:SetAlpha(1)
            GossipFrame:EnableMouse(true)
            GossipFrame:ClearAllPoints()
            GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
        if wasInObjectivesGossip then
            HideObjectives()
        end
    end
end)

-- Note: ObjectivesMainFrame is added to UISpecialFrames in CreateMainFrame()
-- This ensures ESC key handling only applies after the frame exists

-- Close objectives when other UI panels open
local function CloseObjectivesIfOpen()
    if mainFrame and mainFrame:IsShown() then
        -- Reset GossipFrame properly
        if GossipFrame then
            GossipFrame:SetAlpha(1)
            GossipFrame:EnableMouse(true)
            GossipFrame:ClearAllPoints()
            GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
        isInObjectivesGossip = false
        if GossipFrameCloseButton then
            GossipFrameCloseButton:Click()
        end
        mainFrame:Hide()
    end
end

local framesToWatch = {
    "CharacterFrame",
    "TalentFrame",
    "SpellBookFrame",
    "QuestLogFrame",
    "QuestLogDetailFrame",
    "FriendsFrame",
    "PVPFrame",
    "AchievementFrame",
    "GuildFrame",
    "LFGParentFrame",
    "PlayerTalentFrame",
    "LFDParentFrame",
    "WorldMapFrame",
    "GameMenuFrame",
}

for _, frameName in ipairs(framesToWatch) do
    local frame = _G[frameName]
    if frame then
        frame:HookScript("OnShow", CloseObjectivesIfOpen)
    end
end
