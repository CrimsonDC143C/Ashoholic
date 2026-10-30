local addonName, addon = ...






local currentRunData = {}

local previousRunData = {}


local currentIntensityData = {
    intensity = 0,
    areaNameReaper = "0",
    zoneNameReaper = "0"
}


_G["EbonholdPlayerRunData"] = currentRunData
_G["EbonholdIntensityData"] = currentIntensityData


local animationQueue = {}
local animationFrame = nil


local function ShowChangeAnimation(text, isPositive, yOffset, anchorFrame,
                                   anchorPoint)
    local animFrame = CreateFrame("Frame", nil, UIParent)


    if anchorFrame then
        animFrame:SetSize(150, 20)
    else
        animFrame:SetSize(300, 40)
    end

    animFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    animFrame:SetFrameLevel(2000)


    if anchorFrame and anchorFrame:IsVisible() then
        local point = anchorPoint or "RIGHT"
        if point == "RIGHT" then
            animFrame:SetPoint("LEFT", anchorFrame, "RIGHT", 10, 0)
        elseif point == "LEFT" then
            animFrame:SetPoint("RIGHT", anchorFrame, "LEFT", -10, 0)
        elseif point == "TOP" then
            animFrame:SetPoint("BOTTOM", anchorFrame, "TOP", 0, 5)
        elseif point == "BOTTOM" then
            animFrame:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -5)
        end
    else
        animFrame:SetPoint("CENTER", UIParent, "CENTER", 0, yOffset or 0)
    end


    local fontString = anchorFrame and "GameFontNormal" or "GameFontNormalHuge"
    local animText = animFrame:CreateFontString(nil, "OVERLAY", fontString)
    animText:SetPoint("CENTER")
    animText:SetText(text)


    if isPositive then
        animText:SetTextColor(0, 1, 0, 1)
    else
        animText:SetTextColor(1, 0, 0, 1)
    end


    local startTime = GetTime()
    local duration = anchorFrame and 2 or 3
    local moveDistance = anchorFrame and 30 or 100

    local initialX, initialY = animFrame:GetCenter()
    if not initialX then initialX, initialY = 0, 0 end

    animFrame:SetScript("OnUpdate", function(self)
        if ProjectEbonhold_IsClosing then
            self:Hide()
            return
        end
        local elapsed = GetTime() - startTime
        local progress = elapsed / duration

        if progress >= 1 then
            self:Hide()
            self:SetParent(nil)
            return
        end


        local alpha = 1 - progress
        local yMovement = progress * moveDistance

        animText:SetAlpha(alpha)

        if anchorFrame and anchorFrame:IsVisible() then
            local point = anchorPoint or "RIGHT"
            if point == "RIGHT" then
                self:SetPoint("LEFT", anchorFrame, "RIGHT", 10, yMovement)
            elseif point == "LEFT" then
                self:SetPoint("RIGHT", anchorFrame, "LEFT", -10, yMovement)
            elseif point == "TOP" then
                self:SetPoint("BOTTOM", anchorFrame, "TOP", 0, 5 + yMovement)
            elseif point == "BOTTOM" then
                self:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -5 + yMovement)
            end
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 0,
                (yOffset or 0) + yMovement)
        end
    end)

    animFrame:Show()
end


local function ShowIntensityAnimation(oldValue, newValue)
    if ProjectEbonholdOptionsService and not ProjectEbonholdOptionsService:GetSetting("showFloatingText") then
        return
    end
    local difference = newValue - oldValue
    if difference == 0 then return end

    local isPositive = difference > 0
    local text =
        isPositive and ("|cffA020F0+" .. difference .. "|r Intensity") or
        ("|cffA020F0" .. difference .. "|r Intensity")


    local animFrame = CreateFrame("Frame", nil, UIParent)
    animFrame:SetSize(300, 40)
    animFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    animFrame:SetFrameLevel(2000)
    animFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    local animText = animFrame:CreateFontString(nil, "OVERLAY",
        "GameFontNormalHuge")
    animText:SetPoint("CENTER")
    animText:SetText(text)
    animText:SetTextColor(0.63, 0.13, 0.94, 1)

    local startTime = GetTime()
    local duration = 3
    local moveDistance = 100

    animFrame:SetScript("OnUpdate", function(self)
        if ProjectEbonhold_IsClosing then
            self:Hide()
            return
        end
        local elapsed = GetTime() - startTime
        local progress = elapsed / duration

        if progress >= 1 then
            self:Hide()
            self:SetParent(nil)
            return
        end

        local alpha = 1 - progress
        local yMovement = progress * moveDistance

        animText:SetAlpha(alpha)
        self:SetPoint("CENTER", UIParent, "CENTER", 0, yMovement)
    end)

    animFrame:Show()
end


local function CheckIntensityThresholds(oldValue, newValue)
    if ProjectEbonholdOptionsService and not ProjectEbonholdOptionsService:GetSetting("showFloatingText") then
        return
    end
    local thresholds = {
        { level = 1, value = ProjectEbonhold.Constants.INTENSITY_LEVEL_1, name = "Intensity Level 1" },
        { level = 2, value = ProjectEbonhold.Constants.INTENSITY_LEVEL_2, name = "Intensity Level 2" },
        { level = 3, value = ProjectEbonhold.Constants.INTENSITY_LEVEL_3, name = "Intensity Level 3" },
        { level = 4, value = ProjectEbonhold.Constants.INTENSITY_LEVEL_4, name = "Intensity Level 4" },
        { level = 5, value = ProjectEbonhold.Constants.INTENSITY_LEVEL_5, name = "Intensity Level 5" },
    }

    for _, threshold in ipairs(thresholds) do
        if (oldValue < threshold.value and newValue >= threshold.value) then
            local text = "|cffA020F0" .. threshold.name .. " Reached!|r"
            ShowChangeAnimation(text, true, 150, nil, nil)
        elseif (oldValue >= threshold.value and newValue < threshold.value) then
            local text = "|cffA020F0" .. threshold.name .. " Lost!|r"
            ShowChangeAnimation(text, false, 150, nil, nil)
        end
    end
end


local function AnimateDataChanges(newData, oldData, uiElements)
    if not oldData or not newData then return end
    if ProjectEbonholdOptionsService and not ProjectEbonholdOptionsService:GetSetting("showFloatingText") then
        return
    end

    local centerAnimations = {}
    local uiAnimations = {}
    local yOffsetBase = 50
    local yOffsetIncrement = 40


    local stats = {
        {
            key = "soulPoints",
            name = "Soul Ashes",
            short = "Soul Ashe(s)",
            uiKey = "soulPointsText"
        },


    }

    for i, stat in ipairs(stats) do
        local oldValue = oldData[stat.key] or 0
        local newValue = newData[stat.key] or 0
        local difference = newValue - oldValue

        if difference ~= 0 then
            local isPositive = difference > 0
            local anchorFrame = nil
            local anchorPoint = "RIGHT"


            local centerText = isPositive and
                ("|cff00FF00+" .. ProjectEbonhold.FormatThousands(difference) .. "|r " ..
                    stat.short) or
                ("|cffFF0000" .. ProjectEbonhold.FormatThousands(difference) .. "|r " ..
                    stat.short)
            local yOffset = yOffsetBase + (#centerAnimations * yOffsetIncrement)
            table.insert(centerAnimations, {
                text = centerText,
                isPositive = isPositive,
                yOffset = yOffset
            })


            if uiElements and stat.uiKey and uiElements[stat.uiKey] then
                local uiText = isPositive and
                    ("+|cff00FF00" .. difference .. "|r") or
                    ("|cffFF0000" .. difference .. "|r")
                table.insert(uiAnimations, {
                    text = uiText,
                    isPositive = isPositive,
                    anchorFrame = uiElements[stat.uiKey],
                    anchorPoint = anchorPoint
                })
            end
        end
    end


    local totalAnimations = 0


    for i, anim in ipairs(centerAnimations) do
        local delay = totalAnimations * 0.1
        totalAnimations = totalAnimations + 1

        local timerFrame = CreateFrame("Frame")
        local startTime = GetTime()
        timerFrame:SetScript("OnUpdate", function(self)
            if ProjectEbonhold_IsClosing then
                self:SetScript("OnUpdate", nil)
                return
            end
            if GetTime() - startTime >= delay then
                ShowChangeAnimation(anim.text, anim.isPositive, anim.yOffset,
                    nil, nil)
                self:SetScript("OnUpdate", nil)
            end
        end)
    end


    for i, anim in ipairs(uiAnimations) do
        local delay = totalAnimations * 0.1
        totalAnimations = totalAnimations + 1

        local timerFrame = CreateFrame("Frame")
        local startTime = GetTime()
        timerFrame:SetScript("OnUpdate", function(self)
            if ProjectEbonhold_IsClosing then
                self:SetScript("OnUpdate", nil)
                return
            end
            if GetTime() - startTime >= delay then
                ShowChangeAnimation(anim.text, anim.isPositive, nil,
                    anim.anchorFrame, anim.anchorPoint)
                self:SetScript("OnUpdate", nil)
            end
        end)
    end
end


local function ParsePlayerRunData(body)
    -- print("[DEBUG] ParsePlayerRunData called with body: " .. tostring(body))

    local catchupMultiplierPct
    local usedFreezes, totalFreezes
    local hasReachedMaxLevel

    -- Try newest format first (19 fields including hasReachedMaxLevel)
    local soulPoints, soulPointsMax, acceptedRezs, acceptedRezsMax,
    countCanSelfRezs, selfRezsMax, classRezs, classRezsMax,
    avoidedFatalAttacks, avoidedFatalAttacksMax, nbResetAvoided,
    costNextReset, usedRerolls, totalRerolls, remainingBanishes, catchupMultiplierPct, usedFreezes, totalFreezes, hasReachedMaxLevel = body
    :match(
        "^([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)$")

    if not (soulPoints and hasReachedMaxLevel) then
        -- Try 18-field format (freeze counters but no max level flag)
        soulPoints, soulPointsMax, acceptedRezs, acceptedRezsMax,
        countCanSelfRezs, selfRezsMax, classRezs, classRezsMax,
        avoidedFatalAttacks, avoidedFatalAttacksMax, nbResetAvoided,
        costNextReset, usedRerolls, totalRerolls, remainingBanishes, catchupMultiplierPct, usedFreezes, totalFreezes = body
            :match(
                "^([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)$")

        if soulPoints and usedFreezes and totalFreezes then
            hasReachedMaxLevel = "0"
        end
    end

    if not (soulPoints and usedFreezes and totalFreezes) then
        -- Try 16-field format (with catch-up multiplier but no freezes)
        soulPoints, soulPointsMax, acceptedRezs, acceptedRezsMax,
        countCanSelfRezs, selfRezsMax, classRezs, classRezsMax,
        avoidedFatalAttacks, avoidedFatalAttacksMax, nbResetAvoided,
        costNextReset, usedRerolls, totalRerolls, remainingBanishes, catchupMultiplierPct = body:match(
            "^([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)$")

        if soulPoints and catchupMultiplierPct then
            usedFreezes = "0"
            totalFreezes = "0"
            hasReachedMaxLevel = "0"
        end
    end

    if not (soulPoints and soulPointsMax) then
        -- Try 15-field format (banishes but no catch-up)
        soulPoints, soulPointsMax, acceptedRezs, acceptedRezsMax,
        countCanSelfRezs, selfRezsMax, classRezs, classRezsMax,
        avoidedFatalAttacks, avoidedFatalAttacksMax, nbResetAvoided,
        costNextReset, usedRerolls, totalRerolls, remainingBanishes = body:match(
            "^([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)$")

        if soulPoints and remainingBanishes then
            catchupMultiplierPct = "0"
            usedFreezes = "0"
            totalFreezes = "0"
            hasReachedMaxLevel = "0"
        end
    end

    if not (soulPoints and soulPointsMax) then
        -- Try 14-field format for backward compatibility
        soulPoints, soulPointsMax, acceptedRezs, acceptedRezsMax,
        countCanSelfRezs, selfRezsMax, classRezs, classRezsMax,
        avoidedFatalAttacks, avoidedFatalAttacksMax, nbResetAvoided,
        costNextReset, usedRerolls, totalRerolls = body:match(
            "^([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)$")

        if soulPoints and soulPointsMax and acceptedRezs and acceptedRezsMax and
            countCanSelfRezs and selfRezsMax and classRezs and classRezsMax and
            avoidedFatalAttacks and avoidedFatalAttacksMax and nbResetAvoided and
            costNextReset and usedRerolls and totalRerolls then
            remainingBanishes = "1"
            catchupMultiplierPct = "0"
            usedFreezes = "0"
            totalFreezes = "0"
            hasReachedMaxLevel = "0"
        else
            return
        end
    end

    if soulPoints and soulPointsMax and acceptedRezs and acceptedRezsMax and
        countCanSelfRezs and selfRezsMax and classRezs and classRezsMax and
        avoidedFatalAttacks and avoidedFatalAttacksMax and nbResetAvoided and
        costNextReset and usedRerolls and totalRerolls then
        local oldData = {}
        for k, v in pairs(currentRunData) do oldData[k] = v end


        local newData = {
            soulPoints = tonumber(soulPoints) or 0,
            soulPointsMax = tonumber(soulPointsMax) or 0,
            countCanAcceptedRezs = math.max(0, (tonumber(acceptedRezsMax) -
                tonumber(acceptedRezs))),
            countCanSelfRezs = math.max(0, (tonumber(selfRezsMax) -
                tonumber(countCanSelfRezs))),
            countCanClassRezs = math.max(0, (tonumber(classRezsMax) -
                tonumber(classRezs))),
            countCanAvoidFatalAttacks = math.max(0, (tonumber(
                    avoidedFatalAttacksMax) -
                tonumber(
                    avoidedFatalAttacks))),
            nbResetAvoided = tonumber(nbResetAvoided) or 0,
            costNextReset = tonumber(costNextReset) or 0,
            usedRerolls = tonumber(usedRerolls) or 0,
            totalRerolls = tonumber(totalRerolls) or 0,
            remainingBanishes = tonumber(remainingBanishes) or 0,
            catchupMultiplierPct = tonumber(catchupMultiplierPct) or 0,
            usedFreezes = tonumber(usedFreezes) or 0,
            totalFreezes = tonumber(totalFreezes) or 0,
            hasReachedMaxLevel = (tonumber(hasReachedMaxLevel) or 0) == 1,
            -- Carried over, NOT parsed from this packet: the Soul Ash
            -- Multiplier rides its own opcode
            -- (SEND_PLAYER_SOUL_POINTS_MULTIPLIER) and is written straight
            -- onto currentRunData. Since the assignment below REPLACES that
            -- table wholesale, leaving the key out here wiped the multiplier
            -- on every run-data refresh. The run HUD hid the damage (its
            -- update is guarded on ~= nil, so the label kept its last text),
            -- but the prestige tab reads the global fresh, saw nil, and fell
            -- back to the prestige-only share, showing a smaller number than
            -- the HUD.
            soulPointsMultiplier = oldData.soulPointsMultiplier
        }


        if next(currentRunData) ~= nil then
            local uiElements = nil
            if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and
                ProjectEbonhold.PlayerRunUI.GetUIElements then
                uiElements = ProjectEbonhold.PlayerRunUI.GetUIElements()
            end
            AnimateDataChanges(newData, oldData, uiElements)
        end


        currentRunData = newData


        _G["EbonholdPlayerRunData"] = currentRunData
        -- print("[DEBUG] ParsePlayerRunData: Updated global EbonholdPlayerRunData with remainingBanishes: " .. tostring(currentRunData.remainingBanishes))


        if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and
            ProjectEbonhold.PlayerRunUI.UpdateData then
            ProjectEbonhold.PlayerRunUI.UpdateData(currentRunData)
        end


        if ProjectEbonhold and ProjectEbonhold.DeathFrame and
            ProjectEbonhold.DeathFrame.UpdateData then
            ProjectEbonhold.DeathFrame.UpdateData(currentRunData)
        end

        -- Refresh banish UI text if perk selection is visible
        if ProjectEbonhold and ProjectEbonhold.PerkUI and
            ProjectEbonhold.PerkUI.RefreshBanishText then
            ProjectEbonhold.PerkUI.RefreshBanishText()
        end

        return true
    else
        return false
    end
end


local function ParseIntensityData(body)
    local intensity, areaName, cooldown = body:match("^([^;]+);([^;]+);([^;]+)$")
    if intensity and areaName then
        local oldIntensity = currentIntensityData.intensity or 0
        local newIntensity = tonumber(intensity) or 0
        local maxIntensity = ProjectEbonhold.Constants.MAX_INTENSITY
        newIntensity = math.min(newIntensity, maxIntensity)
        currentIntensityData = {
            intensity = newIntensity,
            areaNameReaper = areaName,
            onCooldown = (cooldown == "1") and true or false
        }
        _G["EbonholdIntensityData"] = currentIntensityData

        if oldIntensity ~= newIntensity and oldIntensity > 0 then
            ShowIntensityAnimation(oldIntensity, newIntensity)
            CheckIntensityThresholds(oldIntensity, newIntensity)
        end


        if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and
            ProjectEbonhold.PlayerRunUI.UpdateIntensity then
            ProjectEbonhold.PlayerRunUI.UpdateIntensity(currentIntensityData)
        end

        return true
    else
        return false
    end
end


local function AvoidResetWithSoulPoints()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS
        .REQUEST_AVOID_RESET_WITH_SOUL_POINTS, "")
end

local function AvoidResetFreeResurrection()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS
        .REQUEST_AVOID_RESET_WITH_SELF_REZ, "")
end

local function AcceptDeath(itemEntries)
    local data = itemEntries or ""
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ACCEPT_DEATH, data)
end

local function GetCurrentRunData() return currentRunData end


ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_RUN_DATA,
    function(body) ParsePlayerRunData(body) end)


ProjectEbonhold.onEventReceived(ProjectEbonhold.SS
    .SEND_PLAYER_SOUL_POINTS_MULTIPLIER,
    function(body)
        if body and body ~= "" then
            currentRunData.soulPointsMultiplier = tonumber(body) or 0

            _G["EbonholdPlayerRunData"] = currentRunData


            if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and
                ProjectEbonhold.PlayerRunUI.UpdateData then
                ProjectEbonhold.PlayerRunUI.UpdateData(currentRunData)
            end


            if ProjectEbonhold and ProjectEbonhold.PlayerRun and
                ProjectEbonhold.PlayerRun.UpdatePlayerRunData then
                ProjectEbonhold.PlayerRun.UpdatePlayerRunData(currentRunData)
            end
        end
    end)


ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_INTENSITY_POINTS,
    function(body) ParseIntensityData(body) end)


ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.PlayerRunService = ProjectEbonhold.PlayerRunService or {}
ProjectEbonhold.PlayerRunService.GetCurrentData = GetCurrentRunData
ProjectEbonhold.PlayerRunService.AvoidResetWithSoulPoints =
    AvoidResetWithSoulPoints
ProjectEbonhold.PlayerRunService.AvoidResetFreeResurrection =
    AvoidResetFreeResurrection
ProjectEbonhold.PlayerRunService.AcceptDeath = AcceptDeath
ProjectEbonhold.PlayerRunService.ShowChangeAnimation = ShowChangeAnimation
ProjectEbonhold.PlayerRunService.GetIntensityData = function()
    return currentIntensityData
end
