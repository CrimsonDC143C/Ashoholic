local addon, Addon = ...

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.LevelUpUI = {}


local FADE_DURATION = 0.3
local DISPLAY_DURATION = 3.0


local levelUpFrame = nil
local currentQueue = {}
local isAnimating = false
local TEXTURE_PATH = "Interface\\AddOns\\ProjectEbonhold\\assets\\levelupui"

local function CreateLevelUpFrame()
    if levelUpFrame then return levelUpFrame end
    levelUpFrame = CreateFrame("Frame", "ProjectEbonholdLevelUpFrame", UIParent)
    levelUpFrame:SetSize(500, 200)
    levelUpFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
    levelUpFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    levelUpFrame:SetFrameLevel(1000)
    levelUpFrame:EnableMouse(true)
    levelUpFrame:SetAlpha(0)

    local content = CreateFrame("Frame", nil, levelUpFrame)
    content:SetSize(450, 90)
    content:SetPoint("CENTER")
    levelUpFrame.content = content

    local topLine = content:CreateTexture(nil, "ARTWORK")
    topLine:SetTexture(TEXTURE_PATH)
    topLine:SetTexCoord(0.482422, 0.920898, 0.208984, 0.232422)
    topLine:SetSize(450, 20)
    topLine:SetPoint("TOP", content, "TOP", 0, 0)
    levelUpFrame.topLine = topLine


    local boxShadow = content:CreateTexture(nil, "BACKGROUND")
    boxShadow:SetTexture(TEXTURE_PATH)
    boxShadow:SetTexCoord(0.277344, 0.625977, -0.001953, 0.203125)
    boxShadow:SetSize(350, 40)
    boxShadow:SetPoint("CENTER", content, "CENTER", 0, -14)
    boxShadow:SetVertexColor(0.1, 0.1, 0.1, 0.8)
    levelUpFrame.boxShadow = boxShadow


    local bottomLine = content:CreateTexture(nil, "ARTWORK")
    bottomLine:SetTexture(TEXTURE_PATH)
    bottomLine:SetTexCoord(0.482422, 0.920898, 0.208984, 0.232422)
    bottomLine:SetSize(450, 20)
    bottomLine:SetPoint("BOTTOM", content, "BOTTOM", 0, 0)
    levelUpFrame.bottomLine = bottomLine


    local reachedText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reachedText:SetPoint("CENTER", content, "CENTER", 0, 15)
    reachedText:SetTextColor(1, 1, 1)
    reachedText:SetText("You have reached:")
    reachedText:SetFont("Fonts\\FRIZQT__.TTF", 16)
    levelUpFrame.reachedText = reachedText


    local levelText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    levelText:SetPoint("CENTER", content, "CENTER", 0, -10)
    levelText:SetTextColor(1, 0.82, 0)
    levelText:SetFont("Fonts\\FRIZQT__.TTF", 38, "OUTLINE")
    levelUpFrame.levelText = levelText


    local spellContainer = CreateFrame("Frame", nil, content)
    spellContainer:SetPoint("CENTER", content, "CENTER", 80, 10)
    spellContainer:SetSize(400, 60)
    spellContainer:Hide()
    levelUpFrame.spellContainer = spellContainer


    local spellIcon = spellContainer:CreateTexture(nil, "ARTWORK")
    spellIcon:SetSize(36, 36)
    spellIcon:SetPoint("LEFT", spellContainer, "CENTER", -180, -10)
    spellContainer.spellIcon = spellIcon


    local unlockIcon = spellContainer:CreateTexture(nil, "OVERLAY")
    unlockIcon:SetTexture(TEXTURE_PATH)
    unlockIcon:SetTexCoord(0.218750, 0.253906, 0.660156, 0.732422)
    unlockIcon:SetSize(28, 28)
    unlockIcon:SetPoint("BOTTOMRIGHT", spellIcon, "BOTTOMRIGHT", 6, -6)
    spellContainer.unlockIcon = unlockIcon


    local unlockedText = spellContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    unlockedText:SetPoint("LEFT", spellIcon, "RIGHT", 15, 6)
    unlockedText:SetTextColor(1, 0.82, 0)
    unlockedText:SetText("New Spell Unlocked")
    unlockedText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    spellContainer.unlockedText = unlockedText


    local spellName = spellContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellName:SetPoint("TOPLEFT", unlockedText, "BOTTOMLEFT", 0, -6)
    spellName:SetTextColor(1, 1, 1)
    spellName:SetWidth(320)
    spellName:SetJustifyH("LEFT")
    spellName:SetFont("Fonts\\FRIZQT__.TTF", 12)
    spellContainer.spellName = spellName


    levelUpFrame:SetScript("OnMouseDown", function(self)
        if isAnimating then
            ProcessNextInQueue()
        end
    end)

    levelUpFrame:Hide()
    return levelUpFrame
end

local function FadeIn(frame, duration, callback)
    local elapsed = 0
    local startAlpha = frame:GetAlpha()

    frame:SetScript("OnUpdate", function(self, delta)
        if ProjectEbonhold_IsClosing then self:SetScript("OnUpdate", nil) return end
        delta = math.min(delta, 0.1) -- Cap delta to prevent freeze after alt-tab
        elapsed = elapsed + delta
        local progress = math.min(elapsed / duration, 1)
        self:SetAlpha(startAlpha + (1 - startAlpha) * progress)

        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            if callback then callback() end
        end
    end)
end

local function FadeOut(frame, duration, callback)
    local elapsed = 0
    local startAlpha = frame:GetAlpha()

    frame:SetScript("OnUpdate", function(self, delta)
        if ProjectEbonhold_IsClosing then self:SetScript("OnUpdate", nil) return end
        delta = math.min(delta, 0.1) -- Cap delta to prevent freeze after alt-tab
        elapsed = elapsed + delta
        local progress = math.min(elapsed / duration, 1)
        self:SetAlpha(startAlpha * (1 - progress))

        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            if callback then callback() end
        end
    end)
end

local function ShowLevel(level)
    local frame = CreateLevelUpFrame()
    frame.reachedText:Show()
    frame.levelText:Show()
    frame.levelText:SetText("Level " .. level)
    frame.spellContainer:Hide()
    frame:Show()
    FadeIn(frame, FADE_DURATION, function()
        C_Timer.After(DISPLAY_DURATION, function()
            FadeOut(frame, FADE_DURATION, function()
                ProcessNextInQueue()
            end)
        end)
    end)
end

local function ShowSpell(spellId, rank)
    local frame = CreateLevelUpFrame()

    rank = rank or 1
    local spellName, spellIcon, unlockedText


    if spellId == -1 then
        spellName = "New talent points available"
        spellIcon = "Interface\\Icons\\Ability_Marksmanship"
        unlockedText = "Talent Tree"

        frame.spellContainer.unlockIcon:SetTexCoord(0.218750, 0.253906, 0.660156, 0.732422)
    elseif spellId == -2 then
        spellName = "Dungeon Finder"
        spellIcon = "Interface\\LFGFRAME\\UI-LFG-ICON-PORTRAITRAID"
        unlockedText = "New Feature Unlocked"

        frame.spellContainer.unlockIcon:SetTexCoord(0.218750, 0.253906, 0.660156, 0.732422)
    else
        spellName, _, spellIcon = GetSpellInfo(spellId)


        if rank > 1 then
            unlockedText = "New Rank Unlocked"

            frame.spellContainer.unlockIcon:SetTexCoord(0.219727, 0.252930, 0.734375, 0.800781)
        else
            unlockedText = "New Spell Unlocked"

            frame.spellContainer.unlockIcon:SetTexCoord(0.218750, 0.253906, 0.660156, 0.732422)
        end

        if not spellName then
            ProcessNextInQueue()
            return
        end
    end


    frame.reachedText:Hide()
    frame.levelText:Hide()
    frame.spellContainer:Show()

    frame.spellContainer.spellIcon:SetTexture(spellIcon)
    frame.spellContainer.spellName:SetText(spellName)
    frame.spellContainer.unlockedText:SetText(unlockedText)

    frame:Show()
    frame:SetAlpha(0)


    FadeIn(frame, FADE_DURATION, function()
        C_Timer.After(DISPLAY_DURATION, function()
            FadeOut(frame, FADE_DURATION, function()
                ProcessNextInQueue()
            end)
        end)
    end)
end




function ProcessNextInQueue()
    if #currentQueue == 0 then
        isAnimating = false
        if levelUpFrame then
            levelUpFrame:Hide()
            levelUpFrame:SetAlpha(0)
        end
        return
    end

    local next = table.remove(currentQueue, 1)

    if next.type == "level" then
        ShowLevel(next.level)
    elseif next.type == "spell" then
        ShowSpell(next.spellId, next.rank)
    end
end

function ProjectEbonhold.LevelUpUI.Show(level, spellIds)
    if ProjectEbonholdOptionsService and ProjectEbonholdOptionsService:GetSetting("hideLevelUpFrame") then
        return
    end

    currentQueue = {}


    table.insert(currentQueue, { type = "level", level = level })


    if spellIds and #spellIds > 0 then
        for _, spellId in ipairs(spellIds) do
            table.insert(currentQueue, { type = "spell", spellId = spellId, rank = 1 })
        end
    end

    if not isAnimating then
        isAnimating = true
        ProcessNextInQueue()
    end
end

function ProjectEbonhold.LevelUpUI.AddSpells(spellData)
    if ProjectEbonholdOptionsService and ProjectEbonholdOptionsService:GetSetting("hideLevelUpFrame") then
        return
    end

    if spellData and #spellData > 0 then
        for _, data in ipairs(spellData) do
            local spellId = data.spellId or data
            local rank = data.rank or 1

            table.insert(currentQueue, { type = "spell", spellId = spellId, rank = rank })
        end
    end


    if not isAnimating then
        isAnimating = true
        ProcessNextInQueue()
    end
end
