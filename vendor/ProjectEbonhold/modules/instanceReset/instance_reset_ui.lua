local addonName, addon = ...

-- Reference to our module
local InstanceReset = addon.InstanceReset

local resetButton
local infoFrame
local isInitialized = false

-- Initialize the button once RaidFrameNotInRaid is available
local function InitializeButton()
    if isInitialized or not RaidFrameNotInRaid then
        return
    end
    
    -- Hide the raid browser button
    if RaidFrameNotInRaidRaidBrowserButton then
        RaidFrameNotInRaidRaidBrowserButton:Hide()
    end
    
    -- Hide the "Find a Raid Group or Assemble a Raid" text
    for i = 1, RaidFrameNotInRaid:GetNumRegions() do
        local region = select(i, RaidFrameNotInRaid:GetRegions())
        if region and region:GetObjectType() == "FontString" then
            local text = region:GetText()
            if text and text:match("Find a Raid") then
                region:Hide()
            end
        end
    end
    
    -- Create information frame to show reset details
    infoFrame = CreateFrame("Frame", nil, RaidFrameNotInRaid)
    infoFrame:SetSize(340, 100)
    infoFrame:SetPoint("CENTER", RaidFrameNotInRaid, "CENTER", -15, -80)
    
    -- Title
    local titleText = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", infoFrame, "TOP", 0, 0)
    titleText:SetText("|cffFFFFFFClear Instance IDs|r")
    infoFrame.titleText = titleText
    
    -- Description
    local descText = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descText:SetPoint("TOP", titleText, "BOTTOM", 0, -5)
    descText:SetWidth(320)
    descText:SetJustifyH("CENTER")
    descText:SetText("|cffFFCC00Removes all your current dungeons and raids lockouts\nusing Soul Ashes accumulated in your current run|r")
    infoFrame.descText = descText
    
    -- Create the reset button
    resetButton = utils.CreateSimpleCustomButton(RaidFrameNotInRaid, "Clear IDs", nil, 266, 38)
    resetButton:SetPoint("TOP", descText, "BOTTOM", 0, -10)
    resetButton:Hide()
    
    -- Center the button text (offset left to account for cost+icon on right)
    resetButton.text:ClearAllPoints()
    resetButton.text:SetPoint("CENTER", resetButton, "CENTER", -35, 0)
    
    -- Create cost text on the button (to the right of text)
    local costTextBtn = resetButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    costTextBtn:SetPoint("LEFT", resetButton.text, "RIGHT", 4, 0)
    costTextBtn:SetTextColor(1, 0.82, 0)
    resetButton.costText = costTextBtn
    
    -- Create soul ash icon on the button (to the right of cost)
    local soulAshIcon = resetButton:CreateTexture(nil, "OVERLAY")
    soulAshIcon:SetTexture("Interface\\Icons\\inv_soulash")
    soulAshIcon:SetSize(14, 14)
    soulAshIcon:SetPoint("LEFT", costTextBtn, "RIGHT", 3, 0)
    resetButton.soulAshIcon = soulAshIcon
    
    -- Next reset time (below button)
    local resetTimeText = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetTimeText:SetPoint("TOP", resetButton, "BOTTOM", 0, -8)
    resetTimeText:SetWidth(320)
    resetTimeText:SetJustifyH("CENTER")
    resetTimeText:SetTextColor(0.9, 0.9, 0.9)
    infoFrame.resetTimeText = resetTimeText
    
    -- Cost multiplier info (below reset time)
    local multiplierText = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    multiplierText:SetPoint("TOP", resetTimeText, "BOTTOM", 0, -3)
    multiplierText:SetWidth(320)
    multiplierText:SetJustifyH("CENTER")
    multiplierText:SetTextColor(0.5, 0.5, 0.5)
    multiplierText:SetText("Each reset increases the cost by 5x")
    infoFrame.multiplierText = multiplierText
    

    -- Button click handler
    resetButton:SetScript("OnClick", function(self)
        local cost = InstanceReset.actionData.cost
        local formattedCost = InstanceReset.FormatNumber(cost)
        
        StaticPopupDialogs["PROJECTEBONHOLD_CONFIRM_INSTANCE_RESET"] = {
            text = "Clear Instance IDs?\n\nThis will unbind all the current dungeons and raids lockouts on your character\n\nCost: |cffFFD700" .. formattedCost .. "|r Soul Ashes accumulated in your current run",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                InstanceReset.RequestInstanceResetAll()
            end,
            timeout = 0,
            whileDead = false,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("PROJECTEBONHOLD_CONFIRM_INSTANCE_RESET")
    end)
    
    isInitialized = true
end

-- Update button to show current cost
function InstanceReset.UpdateUI()
    if not infoFrame or not resetButton then
        return
    end
    
    local data = InstanceReset.actionData
    local cost = data.cost
    local formattedCost = InstanceReset.FormatNumber(cost)
    
    -- Update button cost text
    if resetButton.costText then
        resetButton.costText:SetText(formattedCost)
    end
    
    -- Update next reset time
    if infoFrame.resetTimeText then
        local timeRemaining = InstanceReset.FormatTimeRemaining(data.nextResetTime)
        infoFrame.resetTimeText:SetText("Next cost reset: " .. timeRemaining)
    end
    
    -- Check if button should be enabled
    local shouldEnable = true
    
    -- Check if player has enough soul ashes
    local playerRunFrame = _G["ProjectEbonholdPlayerRunFrame"]
    local currentSoulPoints = 0
    if playerRunFrame and playerRunFrame.currentSoulPoints then
        currentSoulPoints = playerRunFrame.currentSoulPoints
    end
    
    if currentSoulPoints < cost then
        shouldEnable = false
    end
    
    -- Check if player is in an instance
    local inInstance = IsInInstance()
    if inInstance then
        shouldEnable = false
    end
    
    -- Enable or disable button
    if shouldEnable then
        resetButton:Enable()
        resetButton:SetAlpha(1.0)
    else
        resetButton:Disable()
        resetButton:SetAlpha(0.5)
    end
end

-- Format large numbers with spaces as thousand separators
function InstanceReset.FormatNumber(num)
    local str = tostring(num)
    local formatted = ""
    local count = 0
    
    -- Iterate from right to left, adding spaces every 3 digits
    for i = #str, 1, -1 do
        if count == 3 then
            formatted = " " .. formatted
            count = 0
        end
        formatted = str:sub(i, i) .. formatted
        count = count + 1
    end
    
    return formatted
end

-- Show button when Raid social tab is opened
local function UpdateButtonVisibility()
    InitializeButton()
    
    if not resetButton or not infoFrame then
        return
    end
    
    -- Show button when the Raid social tab is visible (when not in a raid)
    if RaidFrameNotInRaid and RaidFrameNotInRaid:IsVisible() then
        resetButton:Show()
        infoFrame:Show()
        InstanceReset.RequestActionTrackerInfo()
        InstanceReset.UpdateUI()
    else
        resetButton:Hide()
        infoFrame:Hide()
    end
end

-- Set up hooks when frames are available
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Hook into Raid frame updates
        if RaidFrameNotInRaid then
            RaidFrameNotInRaid:HookScript("OnShow", UpdateButtonVisibility)
            RaidFrameNotInRaid:HookScript("OnHide", UpdateButtonVisibility)
        end
        
        -- Update UI every second to check soul points and instance status
        C_Timer.NewTicker(1, function()
            if resetButton and resetButton:IsVisible() then
                InstanceReset.UpdateUI()
            end
        end)
        
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Update when entering/leaving instances
        if resetButton and resetButton:IsVisible() then
            InstanceReset.UpdateUI()
        end
    end
end)

