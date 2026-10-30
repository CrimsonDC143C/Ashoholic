


local addonName, addon = ...

AchievementBonusUI = {}
AchievementBonusUI.frames = {}
AchievementBonusUI.isHooked = false


local BONUS_ICON = "Interface\\AddOns\\ProjectEbonhold\\assets\\xp_icon"

function AchievementBonusUI:Initialize()
    
    self:HookAchievementFrame()
end

function AchievementBonusUI:HookAchievementFrame()
    if self.isHooked then return end

    
    if not AchievementFrame then
        C_Timer.After(1, function() self:HookAchievementFrame() end)
        return
    end

    
    hooksecurefunc("AchievementButton_DisplayAchievement", function(button)
        self:UpdateAchievementButton(button)
    end)

    
    AchievementFrame:HookScript("OnShow", function()
        self:RefreshAllAchievements()
    end)

    self.isHooked = true
end

function AchievementBonusUI:UpdateAchievementButton(button)
    if not button or not button.id then return end

    local achievementId = button.id
    local bonus = AchievementBonusService:GetBonus(achievementId)

    if bonus then
        self:AddBonusIndicator(button, bonus)
    else
        self:RemoveBonusIndicator(button)
    end
end

function AchievementBonusUI:AddBonusIndicator(button, bonus)
    local frameName = button:GetName() .. "_BonusFrame"
    local bonusFrame = self.frames[frameName]

    if not bonusFrame then
        
        bonusFrame = CreateFrame("Frame", frameName, button)
        bonusFrame:SetSize(40, 40)
        bonusFrame:SetPoint("TOPLEFT", button, "TOPLEFT", 5, -5)
        bonusFrame:SetFrameLevel(button:GetFrameLevel() + 10)

        
        local iconSize = 26
        local icon = bonusFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("CENTER", bonusFrame, "CENTER", 0, 0)
        icon:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\inv_soulash")
        bonusFrame.icon = icon

        
        local lightTexture = bonusFrame:CreateTexture(nil, "ARTWORK")
        lightTexture:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\progression_bar")
        lightTexture:SetTexCoord(0.023438, 0.210938, 0.283203, 0.478516)
        lightTexture:SetSize(iconSize + 32, iconSize + 32)
        lightTexture:SetPoint("CENTER", bonusFrame, "CENTER", 0, 0)
        lightTexture:SetBlendMode("ADD")
        bonusFrame.lightTexture = lightTexture

        
        local borderRound = bonusFrame:CreateTexture(nil, "OVERLAY")
        borderRound:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\progression_bar")
        borderRound:SetTexCoord(0.214844, 0.322266, 0.314453, 0.427734)
        borderRound:SetSize(iconSize + 16, iconSize + 16)
        borderRound:SetPoint("CENTER", bonusFrame, "CENTER", 0, 0)
        bonusFrame.borderRound = borderRound

        
        local text = bonusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", bonusFrame, "CENTER", 0, 0)
        text:SetTextColor(0, 1, 0, 1)
        text:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        bonusFrame.text = text

        
        local animGroup = lightTexture:CreateAnimationGroup()
        local rotation = animGroup:CreateAnimation("Rotation")
        rotation:SetDegrees(360)
        rotation:SetDuration(8)
        animGroup:SetLooping("REPEAT")
        animGroup:Play()
        bonusFrame.animGroup = animGroup

        
        bonusFrame:EnableMouse(true)
        bonusFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Bonus Soul Ashes Multiplier", 1, 0.82, 0)
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Complete this achievement to get a", 1, 1, 1)
            GameTooltip:AddLine("permanent soul ashes multiplier for", 1, 1, 1)
            GameTooltip:AddLine("your entire account.", 1, 1, 1)
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine(string.format("+%.0f%% Soul Ashes", (self.bonus - 1) * 100), 0, 1, 0)
            GameTooltip:Show()
        end)

        bonusFrame:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        self.frames[frameName] = bonusFrame
    end


    bonusFrame.bonus = bonus
    local bonusPercent = (bonus - 1) * 100
    bonusFrame.text:SetText(string.format("+%.0f%%", bonusPercent))
    bonusFrame:Show()
end

function AchievementBonusUI:RemoveBonusIndicator(button)
    local frameName = button:GetName() .. "_BonusFrame"
    local bonusFrame = self.frames[frameName]

    if bonusFrame then
        bonusFrame:Hide()
    end
end

function AchievementBonusUI:RefreshAllAchievements()
    
    for i = 1, 20 do
        local button = _G["AchievementFrameAchievementsContainerButton" .. i]
        if button and button:IsVisible() then
            self:UpdateAchievementButton(button)
        end
    end
end


local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == "ProjectEbonhold" then
        AchievementBonusUI:Initialize()
    end
end)
