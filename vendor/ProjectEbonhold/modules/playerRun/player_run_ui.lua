local addonName, addon = ...

local UITexts = ProjectEbonhold.UITexts

local function IsTransparentDesign()
    return ProjectEbonholdOptionsService and ProjectEbonholdOptionsService:GetSetting("transparentDesign")
end

local playerRunFrame = nil
local empowermentFrame = nil
local currentData = {}
local isCollapsed = false
local isEmpowermentCollapsed = false
local intensityButton = nil

local qualityInfo =
{
    [0] = { name = "Common", color = { 1, 1, 1 }, border = 0 },
    [1] = { name = "Uncommon", color = { 0.1, 1.0, 0.1 }, border = 1 },
    [2] = { name = "Rare", color = { 0.0, 0.4, 1.0 }, border = 2 },
    [3] = { name = "Epic", color = { 0.6, 0.2, 1.0 }, border = 3 },
    [4] = { name = "Legendary", color = { 1.0, 0.5, 0.0 }, border = 4 }
}

local SNAP_GAP = 6
local SNAP_THRESHOLD = 25

local function SavePlayerRunUIPosition()
    if not playerRunFrame then return end
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    local left, top = playerRunFrame:GetLeft(), playerRunFrame:GetTop()
    if left and top then
        ProjectEbonholdDB.playerRunUIPosition = { left = left, top = top }
    end
end

local function RestorePlayerRunUIPosition()
    if not playerRunFrame then return end
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    local pos = ProjectEbonholdDB.playerRunUIPosition
    if pos and type(pos.left) == "number" and type(pos.top) == "number" then
        playerRunFrame:ClearAllPoints()
        playerRunFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.top)
    end
end

local function SaveEmpowermentUIPosition()
    if not empowermentFrame then return end
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    local left, top = empowermentFrame:GetLeft(), empowermentFrame:GetTop()
    if left and top then
        ProjectEbonholdDB.empowermentUIPosition = { left = left, top = top }
    end
end

local function RestoreEmpowermentUIPosition()
    if not empowermentFrame then return end
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    local pos = ProjectEbonholdDB.empowermentUIPosition
    if pos and type(pos.left) == "number" and type(pos.top) == "number" then
        empowermentFrame:ClearAllPoints()
        empowermentFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.top)
    end
end

local function GetEchoesSnapSide()
    if not playerRunFrame or not playerRunFrame:IsShown() or not empowermentFrame then return nil end
    local ml, mr = playerRunFrame:GetLeft(), playerRunFrame:GetRight()
    local el, er = empowermentFrame:GetLeft(), empowermentFrame:GetRight()
    if math.abs(er - ml) <= SNAP_THRESHOLD then return "left" end
    if math.abs(el - mr) <= SNAP_THRESHOLD then return "right" end
    return nil
end

local function RepositionEchoesWithMain(sideOverride)
    if not playerRunFrame or not empowermentFrame then return end
    local side = sideOverride or GetEchoesSnapSide()
    if not side then return end
    local main = playerRunFrame
    local ml, mr = main:GetLeft(), main:GetRight()
    local et = empowermentFrame:GetTop()

    empowermentFrame:ClearAllPoints()
    if side == "left" then
        empowermentFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", ml - SNAP_GAP, et)
    elseif side == "right" then
        empowermentFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mr + SNAP_GAP, et)
    end
    SaveEmpowermentUIPosition()
end

local function TrySnapFrames(draggedFrame)
    if not playerRunFrame or not playerRunFrame:IsShown() then return end
    if not empowermentFrame then return end
    local main = playerRunFrame
    local echoes = empowermentFrame
    local ml, mr = main:GetLeft(), main:GetRight()
    local el, er = echoes:GetLeft(), echoes:GetRight()

    if draggedFrame == main then
        local mt = main:GetTop()
        if math.abs(ml - er) <= SNAP_THRESHOLD then
            main:ClearAllPoints()
            main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", er + SNAP_GAP, mt)
            SavePlayerRunUIPosition()
            return
        elseif math.abs(mr - el) <= SNAP_THRESHOLD then
            main:ClearAllPoints()
            main:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", el - SNAP_GAP, mt)
            SavePlayerRunUIPosition()
            return
        end
    else
        local et = echoes:GetTop()
        if math.abs(er - ml) <= SNAP_THRESHOLD then
            echoes:ClearAllPoints()
            echoes:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", ml - SNAP_GAP, et)
            SaveEmpowermentUIPosition()
            return
        elseif math.abs(el - mr) <= SNAP_THRESHOLD then
            echoes:ClearAllPoints()
            echoes:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mr + SNAP_GAP, et)
            SaveEmpowermentUIPosition()
            return
        end
    end
end

-- Re-anchors the quest tracker, because Blizzard code moves it back.
--
-- This used to call SetPoint EVERY RENDERED FRAME, unconditionally. SetPoint
-- dirties the frame and everything anchored under it, so that was a full layout
-- invalidation of WatchFrame and all its quest lines, 60 times a second, to
-- rewrite a position that had not changed. Now it looks first and only writes
-- when the anchor is actually wrong, at 4Hz instead of 60Hz -- and reading
-- GetPoint costs nothing next to a layout pass.
--
-- Still an OnUpdate, which is not the pattern we want: the correct fix is to
-- hook whatever moves it. That was left alone deliberately -- an unhooked mover
-- would silently park the tracker in the wrong place, and this is a UI position,
-- not something worth a visible regression. The cost is now ~4 comparisons a
-- second, which is not what needed fixing.
local WATCH_X, WATCH_Y = -90, -420
local watchSince = 0
WatchFrame:SetScript("OnUpdate", function(self, elapsed)
    if ProjectEbonhold_IsClosing then return end
    watchSince = watchSince + (elapsed or 0)
    if watchSince < 0.25 then return end
    watchSince = 0
    if not UIParent:IsShown() then return end
    local point, rel, relPoint, x, y = self:GetPoint(1)
    if point == "TOPRIGHT" and rel == UIParent and relPoint == "TOPRIGHT"
       and x == WATCH_X and y == WATCH_Y then
        return
    end
    self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", WATCH_X, WATCH_Y)
end)

local function CreatePlayerRunFrame()
    if playerRunFrame then return playerRunFrame end

    playerRunFrame = CreateFrame("Frame", "ProjectEbonholdPlayerRunFrame", UIParent)
    local contentW, headerH, intensityH, gap, echoesH, pad, edgeInset
    if IsTransparentDesign() then
        contentW, headerH, intensityH, gap, echoesH, pad = 220, 74, 44, 32, 36, 16
        edgeInset = 12
        playerRunFrame:SetSize(contentW + pad, headerH + intensityH + gap + pad)
    else
        contentW, headerH, intensityH, gap, echoesH, pad = 220, 70, 50, 0, 50, 0
        edgeInset = 0
        playerRunFrame:SetSize(250, 150)
    end
    playerRunFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -200)
    playerRunFrame:SetFrameStrata("MEDIUM")
    playerRunFrame:SetMovable(true)
    playerRunFrame:EnableMouse(true)
    playerRunFrame:SetClampedToScreen(true)
    playerRunFrame:RegisterForDrag("LeftButton")

    local function mainFrameDragStart()
        playerRunFrame._echoesSnapSide = GetEchoesSnapSide()
        if playerRunFrame._echoesSnapSide then
            playerRunFrame:SetScript("OnUpdate", function(frame)
                if frame._echoesSnapSide then
                    RepositionEchoesWithMain(frame._echoesSnapSide)
                end
            end)
        end
        playerRunFrame:StartMoving()
    end
    local function mainFrameDragStop()
        playerRunFrame:SetScript("OnUpdate", nil)
        playerRunFrame:StopMovingOrSizing()
        TrySnapFrames(playerRunFrame)
        SavePlayerRunUIPosition()
        if playerRunFrame._echoesSnapSide then
            RepositionEchoesWithMain(playerRunFrame._echoesSnapSide)
            playerRunFrame._echoesSnapSide = nil
        end
    end

    playerRunFrame:SetScript("OnDragStart", mainFrameDragStart)
    playerRunFrame:SetScript("OnDragStop", mainFrameDragStop)
    RestorePlayerRunUIPosition()
    C_Timer.After(0.5, RestorePlayerRunUIPosition)

    if IsTransparentDesign() then
        if playerRunFrame.SetBackdrop then
            playerRunFrame:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                tile = true,
                tileSize = 16,
                edgeSize = 4,
                insets = { left = 4, right = 4, top = 4, bottom = 4 }
            })
            playerRunFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
            playerRunFrame:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end

    local collapseBtn = CreateFrame("Button", nil, playerRunFrame)
    collapseBtn:SetSize(24, 24)
    collapseBtn:ClearAllPoints()
    collapseBtn:SetPoint("TOPLEFT", playerRunFrame, "TOPLEFT", 0, 0)
    collapseBtn:SetFrameLevel(playerRunFrame:GetFrameLevel() + 4)
    if IsTransparentDesign() and collapseBtn.SetBackdrop then
        collapseBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            tile = true,
            tileSize = 16,
            edgeSize = 2,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        collapseBtn:SetBackdropColor(0.2, 0.5, 0.2, 0.95)
        collapseBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    end
    local collapseIcon = collapseBtn:CreateTexture(nil, "OVERLAY")
    collapseIcon:SetSize(16, 16)
    collapseIcon:SetPoint("CENTER", collapseBtn, "CENTER", 0, 0)
    collapseIcon:Hide()
    collapseBtn:SetScript("OnClick", function()
        if ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.Toggle then
            ProjectEbonhold.PlayerRunUI.Toggle()
        end
    end)
    collapseBtn:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.3, 0.65, 0.3, 0.98) end
    end)
    collapseBtn:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.2, 0.5, 0.2, 0.95) end
    end)
    playerRunFrame.collapseBtn = collapseBtn
    collapseBtn:Hide()

    local headerFrame = CreateFrame("Frame", nil, playerRunFrame)
    headerFrame:SetSize(contentW, headerH)
    if IsTransparentDesign() then
        headerFrame:SetPoint("TOPLEFT", playerRunFrame, "TOPLEFT", edgeInset, -edgeInset)
    else
        headerFrame:SetPoint("TOP", playerRunFrame, "TOP", 0, 0)
    end

    if not IsTransparentDesign() then
        local headerTexture = headerFrame:CreateTexture(nil, "BACKGROUND")
        headerTexture:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\texture_ui")
        headerTexture:SetTexCoord(0.023438, 0.960938, 0.015625, 0.304688)
        headerTexture:SetAllPoints(headerFrame)
        headerFrame.headerTexture = headerTexture
    end

    -- Hardmode tier indicator
    local hardmodeButton = CreateFrame("Button", nil, headerFrame)
    if IsTransparentDesign() then
        hardmodeButton:SetSize(80, 16)
        hardmodeButton:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 0, 0)
    else
        hardmodeButton:SetSize(80, 20)
        hardmodeButton:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 6, -8)
    end

    local hardmodeSkullIcon = hardmodeButton:CreateTexture(nil, "ARTWORK")
    if IsTransparentDesign() then
        hardmodeSkullIcon:SetSize(14, 14)
    else
        hardmodeSkullIcon:SetSize(18, 18)
    end
    hardmodeSkullIcon:SetPoint("LEFT", hardmodeButton, "LEFT", 0, 0)
    hardmodeSkullIcon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

    local hardmodeTierText = hardmodeButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hardmodeTierText:SetPoint("LEFT", hardmodeSkullIcon, "RIGHT", 3, 0)
    hardmodeTierText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    hardmodeTierText:SetText("|cffAAAAAANormal|r")
    hardmodeButton.tierText = hardmodeTierText
    playerRunFrame.hardmodeTierText = hardmodeTierText

    hardmodeButton:SetScript("OnEnter", function(self)
        if IsTransparentDesign() then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local svc = ProjectEbonhold.HardmodeService
            if svc and svc.GetCurrentDifficulty then
                local diff = svc.GetCurrentDifficulty()
                if diff <= 1 then
                    GameTooltip:SetText("Normal Mode", 0.7, 0.7, 0.7)
                    GameTooltip:AddLine("No hardcore modifiers active.", 1, 1, 1, true)
                else
                    GameTooltip:SetText("Hardcore Mode " .. (diff - 1), 1, 0.3, 0.3)
                    GameTooltip:AddLine("Increased difficulty and rewards.", 1, 1, 1, true)
                end
            else
                GameTooltip:SetText("Normal Mode", 0.7, 0.7, 0.7)
            end
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local svc = ProjectEbonhold.HardmodeService
            local tier = svc and svc.GetCurrentDifficulty() or 1
            local isHardcore = tier > 1
            if isHardcore then
                GameTooltip:SetText("|cffFF2020Hardcore " .. (tier - 1) .. "|r", 1, 0.2, 0.2)
            else
                GameTooltip:SetText("Hardcore", 0.8, 0.8, 0.8)
            end
            GameTooltip:AddLine("Click to open the Hardcore difficulty panel.", nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    hardmodeButton:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    -- Exposed so the Hardcore unlock alert can anchor to this very icon (modules/torment).
    playerRunFrame.hardmodeButton = hardmodeButton
    ProjectEbonhold.HardmodeButton = hardmodeButton

    hardmodeButton:SetScript("OnClick", function()
        if addon.ToggleHardmodeFrame then
            addon.ToggleHardmodeFrame()
        end
    end)

    local soulAshIcon = headerFrame:CreateTexture(nil, "OVERLAY")
    soulAshIcon:SetSize(16, 16)
    soulAshIcon:SetTexture("Interface\\Icons\\inv_soulash")
    if IsTransparentDesign() then
        soulAshIcon:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 0, -18)
    else
        soulAshIcon:SetPoint("CENTER", headerFrame, "CENTER", -90, -15)
    end
    playerRunFrame.soulAshIcon = soulAshIcon

    local soulPointsText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    soulPointsText:SetPoint("LEFT", soulAshIcon, "RIGHT", 8, 0)
    soulPointsText:SetText("0")
    playerRunFrame.soulPointsText = soulPointsText

    local multiplierText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if IsTransparentDesign() then
        multiplierText:SetPoint("LEFT", soulPointsText, "RIGHT", 14, 0)
    else
        multiplierText:SetPoint("LEFT", headerFrame, "LEFT", 110, -15)
    end
    multiplierText:SetText("|cff00ff00+0%|r")
    playerRunFrame.multiplierText = multiplierText

    local spHitbox = CreateFrame("Button", nil, headerFrame)
    spHitbox:SetPoint("LEFT", soulAshIcon, "LEFT", -5, 0)
    spHitbox:SetPoint("RIGHT", soulPointsText, "RIGHT", 5, 0)
    spHitbox:SetHeight(30)
    spHitbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local sp = playerRunFrame.currentSoulPoints or 0
        GameTooltip:SetText(UITexts.tooltips.soulPoints.title(sp), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(UITexts.tooltips.soulPoints.line, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    spHitbox:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

    local multiplierHitbox = CreateFrame("Button", nil, headerFrame)
    multiplierHitbox:SetPoint("LEFT", multiplierText, "LEFT", -5, 0)
    multiplierHitbox:SetPoint("RIGHT", multiplierText, "RIGHT", 5, 0)
    multiplierHitbox:SetHeight(30)
    multiplierHitbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local multiplier = playerRunFrame.currentMultiplier or 0
        GameTooltip:SetText(UITexts.tooltips.multiplier.title(multiplier), 0, 1, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(UITexts.tooltips.multiplier.line, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    multiplierHitbox:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

    -- Catchup multiplier display
    local catchupText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catchupText:SetPoint("LEFT", multiplierText, "RIGHT", 6, 0)
    catchupText:SetText("")
    playerRunFrame.catchupText = catchupText

    local catchupHitbox = CreateFrame("Button", nil, headerFrame)
    catchupHitbox:SetPoint("LEFT", catchupText, "LEFT", -3, 0)
    catchupHitbox:SetPoint("RIGHT", catchupText, "RIGHT", 3, 0)
    catchupHitbox:SetHeight(30)
    catchupHitbox:SetScript("OnEnter", function(self)
        if not (playerRunFrame.currentCatchupPct and playerRunFrame.currentCatchupPct > 0) then return end
        GameTooltip:SetOwner(self, IsTransparentDesign() and "ANCHOR_TOP" or "ANCHOR_RIGHT")
        GameTooltip:SetText("|cffffcc00Catch-Up Bonus|r", 1, 0.8, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("You are behind the progression curve. A " ..
            (playerRunFrame.currentCatchupPct or 0) ..
            "% bonus is applied on top of all other multipliers until you reach the previous patches' total Soul Ashes cap.",
            nil, nil, nil, true)
        GameTooltip:Show()
    end)
    catchupHitbox:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    playerRunFrame.catchupHitbox = catchupHitbox

    local headerRight
    local reaperParent, hearthParent
    if IsTransparentDesign() then
        headerRight = CreateFrame("Frame", nil, playerRunFrame)
        headerRight:SetSize(60, headerH)
        headerRight:SetPoint("TOPRIGHT", playerRunFrame, "TOPRIGHT", -edgeInset, -edgeInset)
        headerRight:SetFrameLevel(playerRunFrame:GetFrameLevel() + 20)
        reaperParent = headerRight
        hearthParent = headerRight
    else
        reaperParent = headerFrame
        hearthParent = headerFrame
    end

    local reaperIcon = reaperParent:CreateTexture(nil, "OVERLAY")
    reaperIcon:SetSize(24, 24)
    reaperIcon:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\texture_ui")
    reaperIcon:SetTexCoord(0.121094, 0.214844, 0.898438, 0.996094)
    if IsTransparentDesign() then
        reaperIcon:SetPoint("TOPRIGHT", headerRight, "TOPRIGHT", 0, 0)
    else
        reaperIcon:SetPoint("TOPRIGHT", headerFrame, "TOPRIGHT", -10, -10)
    end
    playerRunFrame.reaperIcon = reaperIcon

    local reaperHitbox = CreateFrame("Button", nil, reaperParent)
    reaperHitbox:SetPoint("CENTER", reaperIcon, "CENTER", 0, 0)
    reaperHitbox:SetSize(25, 25)
    reaperHitbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local data
        if IsTransparentDesign() then
            data = ProjectEbonhold.PlayerRunService.GetIntensityData()
        else
            data = _G["EbonholdIntensityData"] or {}
        end
        local areaName = data.areaNameReaper or "0"
        GameTooltip:SetText(UITexts.tooltips.reaper.title, 1, 0.5, 0.5)
        GameTooltip:AddLine(" ")
        if areaName ~= "0" then
            GameTooltip:AddLine(UITexts.tooltips.reaper.spawned(areaName), 1, 1, 1, true)
        else
            GameTooltip:AddLine(UITexts.tooltips.reaper.notSpawned, 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    reaperHitbox:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    playerRunFrame.reaperHitbox = reaperHitbox

    local hearthIcon = hearthParent:CreateTexture(nil, "OVERLAY")
    hearthIcon:SetSize(22, 24)
    hearthIcon:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\texture_ui")
    hearthIcon:SetTexCoord(0.316406, 0.398438, 0.898438, 0.988281)
    hearthIcon:SetPoint("TOPRIGHT", reaperIcon, "TOPLEFT", -5, 0)
    playerRunFrame.hearthIcon = hearthIcon

    local hearthHitbox = CreateFrame("Button", nil, hearthParent)
    hearthHitbox:SetPoint("CENTER", hearthIcon, "CENTER", 0, 0)
    hearthHitbox:SetSize(25, 25)
    hearthHitbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local data = playerRunFrame.currentData or {}
        local playerLevel = UnitLevel("player")
        GameTooltip:SetText(UITexts.tooltips.survival.title, 1, 1, 0.5)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(UITexts.tooltips.survival.playerRezs .. (data.countCanAcceptedRezs or 0), 1, 1, 1)
        GameTooltip:AddLine(UITexts.tooltips.survival.freeRezs .. (data.countCanSelfRezs or 0), 1, 1, 1)
        GameTooltip:AddLine(UITexts.tooltips.survival.classRezs .. (data.countCanClassRezs or 0), 1, 1, 1)
        GameTooltip:AddLine(UITexts.tooltips.survival.cheatDeath .. (data.countCanAvoidFatalAttacks or 0), 1, 1, 1)
        GameTooltip:AddLine(
        UITexts.tooltips.survival.nextRezCost ..
        (math.max(playerLevel, data.costNextReset or 0)) .. UITexts.tooltips.survival.nextCost, 1, 1, 1)
        GameTooltip:Show()
    end)
    hearthHitbox:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    playerRunFrame.hearthHitbox = hearthHitbox

    local intensityFrame = CreateFrame("Frame", nil, playerRunFrame)
    intensityFrame:SetSize(contentW, intensityH)
    if IsTransparentDesign() then
        intensityFrame:SetPoint("TOP", headerFrame, "BOTTOM", -20, 5)
    else
        intensityFrame:SetPoint("TOP", headerFrame, "BOTTOM", 0, 0)
    end

    local intensityFill = intensityFrame:CreateTexture(nil, "BACKGROUND")
    intensityFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    if IsTransparentDesign() then
        intensityFill:SetPoint("LEFT", intensityFrame, "LEFT", 40, 0)
        intensityFill:SetHeight(14)
    else
        intensityFill:SetPoint("LEFT", intensityFrame, "LEFT", 20, -8)
        intensityFill:SetHeight(18)
    end
    intensityFill:SetVertexColor(0.8, 0.1, 0.1, 0.8)
    playerRunFrame.intensityFill = intensityFill

    if not IsTransparentDesign() then
        local intensityBg = intensityFrame:CreateTexture(nil, "BORDER")
        intensityBg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\texture_ui")
        intensityBg:SetTexCoord(0.019531, 0.964844, 0.312500, 0.515625)
        intensityBg:SetAllPoints(intensityFrame)
    end

    local intensityIndicator
    if IsTransparentDesign() then
        intensityIndicator = CreateFrame("Frame", nil, intensityFrame)
        intensityIndicator:SetSize(24, 24)
        intensityIndicator:SetPoint("LEFT", intensityFrame, "LEFT", 12, 0)
        intensityIndicator:SetPoint("TOP", intensityFrame, "CENTER", 0, 0)
        intensityIndicator:SetPoint("BOTTOM", intensityFrame, "CENTER", 0, 0)
    else
        intensityIndicator = intensityFrame:CreateTexture(nil, "OVERLAY")
        intensityIndicator:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\texture_ui")
        intensityIndicator:SetTexCoord(0.023438, 0.109375, 0.890625, 0.992188)
        intensityIndicator:SetSize(25, 30)
        intensityIndicator:SetPoint("LEFT", intensityFrame, "LEFT", 10, 0)
    end
    playerRunFrame.intensityIndicator = intensityIndicator

    local intensityLevelCircle = CreateFrame("Frame", nil, intensityFrame)
    intensityLevelCircle:SetSize(20, 20)
    if IsTransparentDesign() then
        intensityLevelCircle:SetPoint("CENTER", intensityIndicator, "CENTER", 0, 0)
    else
        intensityLevelCircle:SetPoint("CENTER", intensityIndicator, "CENTER", 0, 10)
    end
    intensityLevelCircle:SetFrameLevel(intensityFrame:GetFrameLevel() + 2)

    if not IsTransparentDesign() then
        local circleBg = intensityLevelCircle:CreateTexture(nil, "BACKGROUND")
        circleBg:SetAllPoints()
        circleBg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder")
        circleBg:SetVertexColor(0.1, 0.1, 0.1, 0.9)
    end

    local levelText = intensityLevelCircle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelText:SetPoint("CENTER", intensityLevelCircle, "CENTER", 0, 0)
    levelText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    levelText:SetTextColor(1, 0.2, 0.2)
    levelText:SetText("0")

    playerRunFrame.intensityLevelCircle = intensityLevelCircle
    playerRunFrame.intensityLevelText = levelText

    local intensityFillFlash = intensityFrame:CreateTexture(nil, "OVERLAY")
    intensityFillFlash:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    if IsTransparentDesign() then
        intensityFillFlash:SetPoint("LEFT", intensityFrame, "LEFT", 40, 0)
        intensityFillFlash:SetHeight(14)
    else
        intensityFillFlash:SetPoint("LEFT", intensityFrame, "LEFT", 20, -8)
        intensityFillFlash:SetHeight(18)
    end
    intensityFillFlash:SetVertexColor(1, 0.5, 0.5, 1)
    intensityFillFlash:SetBlendMode("ADD")
    intensityFillFlash:SetAlpha(0)
    playerRunFrame.intensityFillFlash = intensityFillFlash

    local ag = intensityFillFlash:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetChange(0.8)
    a1:SetDuration(0.1)
    a1:SetOrder(1)
    a1:SetSmoothing("OUT")
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetChange(-0.8)
    a2:SetDuration(0.3)
    a2:SetOrder(2)
    a2:SetSmoothing("IN")
    playerRunFrame.intensityFillFlashAnim = ag
    playerRunFrame.intensityFrame = intensityFrame

    intensityFrame:EnableMouse(true)
    intensityFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local intensityData = ProjectEbonhold.PlayerRunService.GetIntensityData()
        local intensity = intensityData.intensity or 0
        GameTooltip:SetText(UITexts.tooltips.intensity.title(intensity), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(UITexts.tooltips.intensity.description1, nil, nil, nil, true)
        GameTooltip:AddLine(UITexts.tooltips.intensity.description2, nil, nil, nil, true)
        GameTooltip:AddLine(UITexts.tooltips.intensity.description3, nil, nil, nil, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(UITexts.tooltips.intensity.warning, 1, 0, 0, true)
        GameTooltip:Show()
    end)
    intensityFrame:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

    local intensityEffects = ProjectEbonhold.IntensityEffects or {}
    local iconSize = 32
    local iconSpacing, maxIcons, startX

    if IsTransparentDesign() then
        local frameW = contentW + pad
        local totalIconsW = iconSize * 5
        local gapTotal = frameW - (2 * edgeInset) - totalIconsW
        iconSpacing = (gapTotal > 0 and gapTotal / 4) or 0
        maxIcons = 5
    else
        maxIcons = 5
        iconSpacing = 8
        local totalIconsWidth = (iconSize * maxIcons) + (iconSpacing * (maxIcons - 1))
        startX = (220 - totalIconsWidth) / 2
    end

    playerRunFrame.intensityIcons = {}

    for i = 1, maxIcons do
        local effectData = intensityEffects[i]
        local iconFrame = CreateFrame("Button", nil, playerRunFrame)
        iconFrame:SetSize(iconSize, iconSize)
        if IsTransparentDesign() then
            local x = edgeInset + (i - 1) * (iconSize + iconSpacing)
            iconFrame:SetPoint("BOTTOMLEFT", playerRunFrame, "BOTTOMLEFT", x, edgeInset)
        else
            iconFrame:SetPoint("TOPLEFT", intensityFrame, "BOTTOMLEFT", startX + ((i - 1) * (iconSize + iconSpacing)), -8)

            local borderFrame = CreateFrame("Frame", nil, iconFrame)
            borderFrame:SetAllPoints()
            borderFrame:SetBackdrop({
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                edgeSize = 6,
                insets = { left = 11, right = 12, top = 12, bottom = 11 }
            })
            borderFrame:SetBackdropBorderColor(1, 0, 0, 1)
            iconFrame.borderFrame = borderFrame
        end

        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize - 4, iconSize - 4)
        icon:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        if effectData and effectData.icon then
            icon:SetTexture(effectData.icon)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        iconFrame.icon = icon

        if not IsTransparentDesign() then
            local lockOverlay = iconFrame:CreateTexture(nil, "OVERLAY", nil, 2)
            lockOverlay:SetSize(14, 14)
            lockOverlay:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
            lockOverlay:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\lock")
            lockOverlay:SetAlpha(0.8)
            lockOverlay:Hide()
            iconFrame.lockOverlay = lockOverlay
        end

        local glow = iconFrame:CreateTexture(nil, "OVERLAY")
        glow:SetSize(iconSize * 1.5, iconSize * 1.5)
        glow:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        glow:SetTexture("Interface\\Cooldown\\star4")
        glow:SetVertexColor(1, 0.3, 0, 1)
        glow:SetBlendMode("ADD")
        glow:SetAlpha(0)
        iconFrame.glow = glow

        local glowAnim = glow:CreateAnimationGroup()
        local ga1 = glowAnim:CreateAnimation("Alpha")
        ga1:SetChange(0.8)
        ga1:SetDuration(0.3)
        ga1:SetOrder(1)
        ga1:SetSmoothing("OUT")
        local ga2 = glowAnim:CreateAnimation("Alpha")
        ga2:SetChange(-0.8)
        ga2:SetDuration(0.5)
        ga2:SetOrder(2)
        ga2:SetSmoothing("IN")
        iconFrame.glowAnim = glowAnim

        icon:SetDesaturated(true)
        iconFrame.level = i
        iconFrame.effectData = effectData
        iconFrame.wasActive = false

        iconFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local isActive = self.icon and not self.icon:IsDesaturated()
            if self.effectData then
                if isActive then
                    GameTooltip:SetText(self.effectData.name, 1, 0.2, 0.2)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(self.effectData.description, 1, 1, 1, true)
                else
                    GameTooltip:SetText(self.effectData.name, 0.5, 0.5, 0.5)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(self.effectData.description, 0.6, 0.6, 0.6, true)
                end
            else
                GameTooltip:SetText("Intensity " .. self.level, 1, 0.2, 0.2)
            end
            GameTooltip:Show()
        end)
        iconFrame:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

        table.insert(playerRunFrame.intensityIcons, iconFrame)
    end

    local function registerDragForward(frame)
        if not frame then return end
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", mainFrameDragStart)
        frame:SetScript("OnDragStop", mainFrameDragStop)
    end
    registerDragForward(headerFrame)
    registerDragForward(spHitbox)
    registerDragForward(multiplierHitbox)
    registerDragForward(catchupHitbox)
    registerDragForward(hardmodeButton)
    registerDragForward(intensityFrame)
    for _, iconFrame in ipairs(playerRunFrame.intensityIcons) do
        registerDragForward(iconFrame)
    end
    registerDragForward(playerRunFrame.reaperHitbox)
    registerDragForward(playerRunFrame.hearthHitbox)
    registerDragForward(collapseBtn)
    registerDragForward(headerRight)

    playerRunFrame:Show()

    return playerRunFrame
end


local SEARCH_ALIASES = {
    ["health"]   = { "heal", "health", "regenerat", "absorb", "life" },
    ["heal"]     = { "heal", "health", "regenerat", "absorb" },
    ["speed"]    = { "speed", "movement", "haste", "slow", "swift" },
    ["damage"]   = { "damage", "deal", "strike", "attack", "hit" },
    ["fire"]     = { "fire", "flame", "burn", "ignite", "ember" },
    ["nature"]   = { "nature", "poison", "bleed", "thorn" },
    ["frost"]    = { "frost", "freeze", "chill", "ice" },
    ["shadow"]   = { "shadow", "dark", "void", "curse" },
    ["holy"]     = { "holy", "divine", "light", "sacred" },
    ["armor"]    = { "armor", "defence", "shield", "absorb" },
    ["crit"]     = { "critical", "crit" },
    ["mana"]     = { "mana", "energy", "resource", "cost" },
    ["cooldown"] = { "cooldown", "recharge" },
    ["aoe"]      = { "area", "nearby", "surround", "splash" },
    ["stamina"]  = { "stamina", "health", "endur" },
}

local function ApplySearchFilter(text)
    if not empowermentFrame then return end
    local query = (text or ""):lower()
    query = query:match("^%s*(.-)%s*$") or query

    local terms = {}
    if query ~= "" then
        terms[#terms + 1] = query
        if SEARCH_ALIASES[query] then
            for _, alias in ipairs(SEARCH_ALIASES[query]) do
                terms[#terms + 1] = alias
            end
        end
    end

    for _, iconFrame in ipairs(empowermentFrame.perkIcons or {}) do
        if not iconFrame._perkData then
        elseif query == "" then
            iconFrame:SetAlpha(1)
            if iconFrame._badge then iconFrame._badge:SetAlpha(1) end
        else
            local pd = iconFrame._perkData
            local name = (pd.spellName or ""):lower()
            if not iconFrame._descCache then
                local desc = ""
                if pd.spellId and utils and utils.GetSpellDescription then
                    local ok, d = pcall(utils.GetSpellDescription, utils, pd.spellId, 500, 1)
                    if ok and d then desc = d:lower() end
                end
                iconFrame._descCache = desc
            end
            local desc = iconFrame._descCache

            local matched = false
            for _, term in ipairs(terms) do
                if term ~= "" and (name:find(term, 1, true) or desc:find(term, 1, true)) then
                    matched = true
                    break
                end
            end

            if matched then
                iconFrame:SetAlpha(1)
                if iconFrame._badge then iconFrame._badge:SetAlpha(1) end
            else
                iconFrame:SetAlpha(0.15)
                if iconFrame._badge then iconFrame._badge:SetAlpha(0.15) end
            end
        end
    end
end

local function CreateEmpowermentFrame()
    if empowermentFrame then return empowermentFrame end

    empowermentFrame = CreateFrame("Frame", "ProjectEbonholdEmpowermentFrame", UIParent)
    -- Exposed so the Orb of Lost Memories bubble can anchor to the echo panel it acts on
    -- (modules/perks/orb_of_lost_memories.lua).
    ProjectEbonhold.EmpowermentFrame = empowermentFrame
    empowermentFrame:SetSize(240, 530)
    empowermentFrame:SetPoint("TOPRIGHT", playerRunFrame, "TOPLEFT", -10, 0)
    empowermentFrame:SetFrameStrata("DIALOG")
    empowermentFrame:SetMovable(true)
    empowermentFrame:EnableMouse(true)
    empowermentFrame:SetClampedToScreen(true)
    empowermentFrame:RegisterForDrag("LeftButton")
    empowermentFrame:SetScript("OnDragStart", empowermentFrame.StartMoving)
    empowermentFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TrySnapFrames(empowermentFrame)
        SaveEmpowermentUIPosition()
    end)
    RestoreEmpowermentUIPosition()

    if IsTransparentDesign() then
        empowermentFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            tile = true,
            tileSize = 16,
            edgeSize = 4,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        empowermentFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
        empowermentFrame:SetBackdropBorderColor(0, 0, 0, 1)
    else
        empowermentFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        empowermentFrame:SetBackdropColor(0, 0, 0, 0.9)
    end

    local titleFrame = CreateFrame("Frame", nil, empowermentFrame)
    titleFrame:SetHeight(20)
    titleFrame:SetPoint("TOPLEFT", empowermentFrame, "TOPLEFT", 15, -15)
    titleFrame:SetPoint("TOPRIGHT", empowermentFrame, "TOPRIGHT", -15, -15)

    local title = titleFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", titleFrame, "CENTER", 5, 5)
    title:SetText("Echoes")
    empowermentFrame.title = title
    -- Exposed so the Orb of Lost Memories counter can sit in this bar, level with the echoes it
    -- acts on, mirroring the browser button on the other side.
    empowermentFrame.titleFrame = titleFrame

    -- Button to open the Echoes Browser
    local browserButton = CreateFrame("Button", nil, titleFrame)
    browserButton:SetSize(20, 20)
    browserButton:SetPoint("RIGHT", titleFrame, "RIGHT", 5, 5)

    local browserIcon = browserButton:CreateTexture(nil, "ARTWORK")
    browserIcon:SetAllPoints()
    browserIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
    browserIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    browserButton:SetScript("OnEnter", function(self)
        browserIcon:SetVertexColor(1.2, 1.2, 1.2)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Echo Journal", 1, 1, 1)
        GameTooltip:AddLine("Your run, your collection and all existing echoes", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    browserButton:SetScript("OnLeave", function(self)
        browserIcon:SetVertexColor(1, 1, 1)
        GameTooltip:Hide()
    end)
    browserButton:SetScript("OnClick", function()
        if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.Toggle then
            ProjectEbonhold.EchoJournal.Toggle(1)
        end
    end)
    empowermentFrame.browserButton = browserButton

    -- Search box at the bottom
    local searchFrame = CreateFrame("Frame", nil, empowermentFrame)
    searchFrame:SetHeight(24)
    searchFrame:SetPoint("BOTTOMLEFT", empowermentFrame, "BOTTOMLEFT", 15, 10)
    searchFrame:SetPoint("BOTTOMRIGHT", empowermentFrame, "BOTTOMRIGHT", -15, 10)
    if searchFrame.SetBackdrop then
        if IsTransparentDesign() then
            searchFrame:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                tile = true,
                tileSize = 16,
                edgeSize = 2,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            searchFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
            searchFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        else
            searchFrame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            searchFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
            searchFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end
    end

    local searchBox = CreateFrame("EditBox", "ShieldTrackerSearchBox", searchFrame)
    searchBox:SetSize(186, 20)
    searchBox:SetPoint("LEFT", searchFrame, "LEFT", 4, 0)
    searchBox:SetFontObject("GameFontNormalSmall")
    searchBox:SetTextColor(1, 1, 1)
    searchBox:SetMaxLetters(64)
    searchBox:SetAutoFocus(false)
    searchBox:EnableMouse(true)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        ApplySearchFilter("")
    end)
    searchBox:SetScript("OnTextChanged", function(self)
        ApplySearchFilter(self:GetText())
    end)
    searchBox:SetScript("OnEditFocusGained", function(self)
        if searchFrame.SetBackdropBorderColor then
            searchFrame:SetBackdropBorderColor(0.5, 0.7, 1.0, 1)
        end
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if searchFrame.SetBackdropBorderColor then
            searchFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end
    end)
    empowermentFrame.searchBox = searchBox

    -- Placeholder text
    local searchPlaceholder = searchFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchPlaceholder:SetPoint("LEFT", searchFrame, "LEFT", 6, 0)
    searchPlaceholder:SetText("Search echoes...")
    searchPlaceholder:SetTextColor(0.4, 0.4, 0.4)
    empowermentFrame.searchPlaceholder = searchPlaceholder

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, searchFrame)
    clearBtn:SetSize(16, 16)
    clearBtn:SetPoint("RIGHT", searchFrame, "RIGHT", -3, 0)
    local clearTex = clearBtn:CreateTexture(nil, "ARTWORK")
    clearTex:SetAllPoints()
    clearTex:SetTexture("Interface\\Buttons\\UI-StopButton")
    clearTex:SetVertexColor(0.6, 0.6, 0.6)
    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
        ApplySearchFilter("")
    end)
    clearBtn:SetScript("OnEnter", function() clearTex:SetVertexColor(1, 0.4, 0.4) end)
    clearBtn:SetScript("OnLeave", function() clearTex:SetVertexColor(0.6, 0.6, 0.6) end)

    -- Show/hide placeholder based on text
    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            searchPlaceholder:Hide()
        else
            searchPlaceholder:Show()
        end
        ApplySearchFilter(text)
    end)

    local gridContainer = CreateFrame("Frame", nil, empowermentFrame)
    gridContainer:SetHeight(350)
    gridContainer:SetPoint("TOPLEFT", titleFrame, "BOTTOMLEFT", 0, -10)
    gridContainer:SetPoint("TOPRIGHT", titleFrame, "BOTTOMRIGHT", 0, -10)
    empowermentFrame.gridContainer = gridContainer
    empowermentFrame.perkIcons = {}

    isEmpowermentCollapsed = true
    empowermentFrame:Hide()

    table.insert(UISpecialFrames, "ProjectEbonholdEmpowermentFrame")

    empowermentFrame:SetScript("OnHide", function()
        isEmpowermentCollapsed = true
        if playerRunFrame and playerRunFrame.empowermentHeader and playerRunFrame.empowermentHeader.SetBackdropColor then
            playerRunFrame.empowermentHeader:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
        end
    end)

    return empowermentFrame
end


function ToggleEmpowermentPanel()
    if not empowermentFrame then CreateEmpowermentFrame() end

    isEmpowermentCollapsed = not isEmpowermentCollapsed

    if isEmpowermentCollapsed then
        empowermentFrame:Hide()
        if playerRunFrame.empowermentHeader and playerRunFrame.empowermentHeader.SetBackdropColor then
            playerRunFrame.empowermentHeader:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
        end
    else
        empowermentFrame:Show()
        if playerRunFrame.empowermentHeader and playerRunFrame.empowermentHeader.SetBackdropColor then
            playerRunFrame.empowermentHeader:SetBackdropColor(0.14, 0.14, 0.16, 0.95)
        end
    end
end

local perkSelectorFrame = nil
local function ShowPerkSelectorForLocking(perksData, slotIndex)
    if perkSelectorFrame and perkSelectorFrame:IsShown() then return end

    local availablePerks = {}
    local uniquePerks = {}

    for spellName, instances in pairs(perksData or {}) do
        for _, instance in ipairs(instances) do
            local uniqueKey = instance.spellId .. "_" .. instance.quality
            if not uniquePerks[uniqueKey] then
                uniquePerks[uniqueKey] = true
                table.insert(availablePerks, {
                    spellName = spellName,
                    spellId = instance.spellId,
                    quality = instance.quality
                })
            end
        end
    end

    if #availablePerks == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF0000You don't have any echoes to lock!|r")
        return
    end

    table.sort(availablePerks, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.spellName < b.spellName
    end)

    if perkSelectorFrame then
        local children = { perkSelectorFrame:GetChildren() }
        for _, child in ipairs(children) do
            child:Hide()
            child:SetParent(nil)
        end
        perkSelectorFrame:Hide()
        perkSelectorFrame:SetParent(nil)
        perkSelectorFrame = nil
    end

    perkSelectorFrame = CreateFrame("Frame", nil, UIParent)
    local selectorFrame = perkSelectorFrame
    selectorFrame:SetSize(300, 400)
    selectorFrame:SetPoint("CENTER")
    selectorFrame:SetFrameStrata("DIALOG")
    if IsTransparentDesign() then
        selectorFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            tile = true,
            tileSize = 16,
            edgeSize = 4,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        selectorFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
        selectorFrame:SetBackdropBorderColor(0, 0, 0, 1)
    else
        selectorFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        selectorFrame:SetBackdropColor(0, 0, 0, 0.9)
    end
    selectorFrame:EnableMouse(true)
    selectorFrame:SetMovable(true)
    selectorFrame:RegisterForDrag("LeftButton")
    selectorFrame:SetScript("OnDragStart", selectorFrame.StartMoving)
    selectorFrame:SetScript("OnDragStop", selectorFrame.StopMovingOrSizing)

    selectorFrame.title = selectorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    selectorFrame.title:SetPoint("TOP", selectorFrame, "TOP", 0, -20)
    selectorFrame.title:SetText("Select Echo to Make Permanent")

    local closeButton = CreateFrame("Button", nil, selectorFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", selectorFrame, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() selectorFrame:Hide() end)

    local uniqueName = "PerkSelectorScrollFrame" .. math.random(1, 999999)
    local scrollFrame = CreateFrame("ScrollFrame", uniqueName, selectorFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", selectorFrame, "TOPLEFT", 10, -45)
    scrollFrame:SetPoint("BOTTOMRIGHT", selectorFrame, "BOTTOMRIGHT", -30, 10)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(260, math.max(#availablePerks * 40, 1))
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:SetVerticalScroll(0)
    scrollFrame:UpdateScrollChildRect()

    for i, perkInfo in ipairs(availablePerks) do
        local btn = CreateFrame("Button", nil, scrollChild)
        btn:SetSize(260, 36)
        btn:SetPoint("TOP", scrollChild, "TOP", 0, -(i - 1) * 40)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0.1, 0.1, 0.1, 0.5)

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(0.3, 0.3, 0.3, 0.5)

        local qualityData = qualityInfo[perkInfo.quality] or qualityInfo[0]
        local qualityBg = btn:CreateTexture(nil, "BORDER")
        qualityBg:SetSize(36, 36)
        qualityBg:SetPoint("LEFT", btn, "LEFT", 2, 0)
        qualityBg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perk_quality_" .. qualityData.border)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(25, 25)
        icon:SetPoint("CENTER", qualityBg, "CENTER", 0, 0)
        local spellName, _, spellIcon = GetSpellInfo(perkInfo.spellId)
        if spellIcon then SetPortraitToTexture(icon, spellIcon) end

        local qualityBorder = btn:CreateTexture(nil, "OVERLAY")
        qualityBorder:SetSize(110, 110)
        qualityBorder:SetPoint("CENTER", qualityBg, "CENTER", 0, 1)
        qualityBorder:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perk_border_quality_" .. qualityData
        .border)

        local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", qualityBg, "RIGHT", 8, 0)
        nameText:SetText(perkInfo.spellName)
        nameText:SetTextColor(unpack(qualityData.color))

        btn:SetScript("OnClick", function()
            if perkInfo.spellId and ProjectEbonhold.PerkService.LockPerk(perkInfo.spellId, 1) then
                selectorFrame:Hide()
                C_Timer.After(0.5, function()
                    if ProjectEbonhold.PerkService.RequestGrantedPerks then
                        ProjectEbonhold.PerkService.RequestGrantedPerks()
                    end
                end)
            end
        end)
    end
end


-- ── Empowerment display pools ──────────────────────────────────────────────
-- WoW 3.3.5: CreateFrame objects are permanent in the C++ engine.
-- SetParent(nil) does NOT free them; they accumulate forever.
-- These pools create each frame type exactly once and reuse them on every
-- UpdateEmpowermentDisplay call, eliminating the ~1,000 object leak per perk grant.

local iconFramePool = {}   -- reusable icon+badge frames
local slotFramePool = {}   -- reusable permanent-slot frames

local function AcquireIconFrame(grid)
    for _, f in ipairs(iconFramePool) do
        if not f._inUse then
            f._inUse = true
            f:SetParent(grid)
            f:Show()
            return f
        end
    end
    -- Create a new one only when pool is exhausted (first ~80 calls total ever).
    local iconFrame = CreateFrame("Button", nil, grid)
    iconFrame:SetSize(32, 32)

    local iconBase = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBase:SetSize(32 * 1.2, 32 * 1.2)
    iconBase:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    iconFrame._iconBase = iconBase

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32 * 0.8, 32 * 0.8)
    icon:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    iconFrame._icon = icon

    local border = iconFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    border:SetSize(110, 110)
    border:SetPoint("CENTER", iconFrame, "CENTER", 0, 2)
    iconFrame._border = border

    -- Single badge at top anchor showing highest owned rarity count.
    local badgeSize = 26
    local badgeFrame = CreateFrame("Frame", nil, grid)
    badgeFrame:SetSize(badgeSize, badgeSize)
    badgeFrame:EnableMouse(false)

    local bgTex = badgeFrame:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(badgeFrame)
    bgTex:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\background_count")

    local txt = badgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetSize(badgeSize, badgeSize)
    txt:SetPoint("CENTER", badgeFrame, "CENTER", 0, 0)
    txt:SetJustifyH("CENTER")
    txt:SetJustifyV("MIDDLE")
    txt:SetNonSpaceWrap(false)
    txt:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    badgeFrame._txt = txt
    badgeFrame:Hide()
    iconFrame._badge = badgeFrame

    iconFrame:EnableMouse(true)
    iconFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    iconFrame._inUse = true
    table.insert(iconFramePool, iconFrame)
    return iconFrame
end

local function AcquireSlotFrame(grid)
    for _, f in ipairs(slotFramePool) do
        if not f._inUse then
            f._inUse = true
            f:SetParent(grid)
            -- Restart looping animations that were stopped on release.
            if f._animGroups then
                for _, ag in ipairs(f._animGroups) do ag:Play() end
            end
            f:Show()
            return f
        end
    end
    -- Create once only.
    local size = 52
    local slotFrame = CreateFrame("Button", nil, grid)
    slotFrame:SetSize(size, size)
    slotFrame._animGroups = {}

    local bg = slotFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(size * 1.6, size * 1.6)
    bg:SetPoint("CENTER", slotFrame, "CENTER", 0, -1)
    bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perm_background_texture")

    local swirl = slotFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    swirl:SetSize(size * 2.0, size * 2.0)
    swirl:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
    swirl:SetTexture("Interface\\Cooldown\\star4")
    swirl:SetBlendMode("ADD")
    slotFrame._swirl = swirl
    local swirlAnim = swirl:CreateAnimationGroup()
    swirlAnim:SetLooping("REPEAT")
    local rotS = swirlAnim:CreateAnimation("Rotation")
    rotS:SetDuration(4)
    rotS:SetDegrees(360)
    rotS:SetOrigin("CENTER", 0, 0)
    swirlAnim:Play()
    table.insert(slotFrame._animGroups, swirlAnim)

    local swirl2 = slotFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
    swirl2:SetSize(size * 1.75, size * 1.75)
    swirl2:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
    swirl2:SetTexture("Interface\\Cooldown\\star4")
    swirl2:SetVertexColor(1, 1, 1, 0.4)
    swirl2:SetBlendMode("ADD")
    local swirl2Anim = swirl2:CreateAnimationGroup()
    swirl2Anim:SetLooping("REPEAT")
    local rotS2 = swirl2Anim:CreateAnimation("Rotation")
    rotS2:SetDuration(5)
    rotS2:SetDegrees(-360)
    rotS2:SetOrigin("CENTER", 0, 0)
    swirl2Anim:Play()
    table.insert(slotFrame._animGroups, swirl2Anim)

    local rotatingTex = slotFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    rotatingTex:SetSize(size * 1.9, size * 1.9)
    rotatingTex:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
    rotatingTex:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\rotating_perm_texture")
    rotatingTex:SetBlendMode("ADD")
    slotFrame._rotatingTex = rotatingTex
    local rotAnim = rotatingTex:CreateAnimationGroup()
    rotAnim:SetLooping("REPEAT")
    local rot = rotAnim:CreateAnimation("Rotation")
    rot:SetDegrees(-360)
    rot:SetDuration(6)
    rot:SetOrigin("CENTER", 0, 0)
    rotAnim:Play()
    table.insert(slotFrame._animGroups, rotAnim)

    local iconBase = slotFrame:CreateTexture(nil, "BORDER")
    iconBase:SetSize(size * 1.2, size * 1.2)
    iconBase:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
    slotFrame._iconBase = iconBase

    local icon = slotFrame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size * 0.8, size * 0.8)
    icon:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
    slotFrame._icon = icon

    local border = slotFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    border:SetSize(110 * size / 32, 110 * size / 32)
    border:SetPoint("CENTER", slotFrame, "CENTER", 0, 2)
    slotFrame._border = border

    -- Stack count badge for locked slot
    local lockedBadgeSize = 26
    local lockedBadge = CreateFrame("Frame", nil, grid)
    lockedBadge:SetSize(lockedBadgeSize, lockedBadgeSize)
    lockedBadge:EnableMouse(false)

    local lockedBadgeBg = lockedBadge:CreateTexture(nil, "BACKGROUND")
    lockedBadgeBg:SetAllPoints(lockedBadge)
    lockedBadgeBg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\background_count")

    local lockedBadgeTxt = lockedBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockedBadgeTxt:SetSize(lockedBadgeSize, lockedBadgeSize)
    lockedBadgeTxt:SetPoint("CENTER", lockedBadge, "CENTER", 0, 0)
    lockedBadgeTxt:SetJustifyH("CENTER")
    lockedBadgeTxt:SetJustifyV("MIDDLE")
    lockedBadgeTxt:SetNonSpaceWrap(false)
    lockedBadgeTxt:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    lockedBadge._txt = lockedBadgeTxt
    slotFrame._lockedBadge = lockedBadge
    lockedBadge:Hide()

    slotFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    slotFrame._inUse = true
    table.insert(slotFramePool, slotFrame)
    return slotFrame
end

local function ReleaseIconFrame(f)
    f._inUse = false
    f:Hide()
    f:SetScript("OnEnter", nil)
    f:SetScript("OnLeave", nil)
    f:SetScript("OnClick", nil)
    f:ClearAllPoints()
    if f._badge then
        f._badge:Hide()
        f._badge:ClearAllPoints()
    end
end

local function ReleaseSlotFrame(f)
    f._inUse = false
    f:Hide()
    f:SetScript("OnEnter", nil)
    f:SetScript("OnLeave", nil)
    f:SetScript("OnClick", nil)
    f:ClearAllPoints()
    if f._animGroups then
        for _, ag in ipairs(f._animGroups) do ag:Stop() end
    end
    if f._lockedBadge then
        f._lockedBadge:Hide()
        f._lockedBadge:ClearAllPoints()
    end
end

-- ── UpdateEmpowermentDisplay (pool-based, zero new frame allocations after warmup) ──
local function UpdateEmpowermentDisplay(perksData)
    if not empowermentFrame then CreateEmpowermentFrame() end

    -- Release all currently active frames back to pool instead of destroying them.
    if empowermentFrame.permanentSlots then
        for _, slot in ipairs(empowermentFrame.permanentSlots) do
            ReleaseSlotFrame(slot)
        end
    end
    empowermentFrame.permanentSlots = {}

    for _, iconFrame in ipairs(empowermentFrame.perkIcons) do
        ReleaseIconFrame(iconFrame)
    end
    empowermentFrame.perkIcons = {}

    local perkCount = 0
    local totalEchoes = 0
    local perkList = {}
    for spellName, instances in pairs(perksData or {}) do
        perkCount = perkCount + 1
        local groupTotalStacks = 0
        local highestQuality = 0
        local primarySpellId = nil
        for _, instance in ipairs(instances) do
            groupTotalStacks = groupTotalStacks + (instance.stack or 1)
            if instance.quality > highestQuality then
                highestQuality = instance.quality
                primarySpellId = instance.spellId
            end
        end
        totalEchoes = totalEchoes + groupTotalStacks
        table.insert(perkList, {
            spellName = spellName,
            spellId = primarySpellId or instances[1].spellId,
            instances = instances,
            totalStacks = groupTotalStacks,
            quality = highestQuality
        })
    end

    -- Persist owned counts to DB so PerkUI cards can show correct counts after reload/logout
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.cachedPerkCounts = {}
    for _, perk in ipairs(perkList) do
        if perk.spellName then
            ProjectEbonholdDB.cachedPerkCounts[perk.spellName] = perk.totalStacks
        end
    end

    if empowermentFrame.title then
        empowermentFrame.title:SetText("Echoes")
    end

    empowermentFrame.gridContainer:Show()

    table.sort(perkList, function(a, b)
        if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
        local stacksA = a.totalStacks or 0
        local stacksB = b.totalStacks or 0
        if stacksA ~= stacksB then return stacksA > stacksB end
        return a.spellId < b.spellId
    end)

    local lockedPerks = ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetLockedPerks() or {}
    local maxSlots = ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetMaximumPermanentEchoes() or 0

    -- Auto-size panel width based on permanent slots vs echo grid
    local slotSize = 52
    local slotSpacing = 8
    local slotsWidth = maxSlots > 0 and ((maxSlots * slotSize) + ((maxSlots - 1) * slotSpacing)) or 0
    local echoGridWidth = (5 * 32) + (4 * 11) -- 5 columns, 32px icons, 11px spacing
    local contentWidth = math.max(slotsWidth, echoGridWidth) + 30
    local panelWidth = math.max(240, contentWidth)
    empowermentFrame:SetWidth(panelWidth)
    empowermentFrame.gridContainer:SetWidth(panelWidth - 30)
    local gridW = empowermentFrame.gridContainer:GetWidth()

    local permanentSlotsStartY = 12
    if maxSlots > 0 then
        local totalWidth = (maxSlots * slotSize) + ((maxSlots - 1) * slotSpacing)
        local startX = math.floor((gridW - totalWidth) / 2)

        for i = 1, maxSlots do
            local xOffset = startX + ((i - 1) * (slotSize + slotSpacing))

            -- Acquire from pool (creates once, reuses forever).
            local slotFrame = AcquireSlotFrame(empowermentFrame.gridContainer)
            slotFrame:SetPoint("TOPLEFT", empowermentFrame.gridContainer, "TOPLEFT", xOffset, permanentSlotsStartY)
            slotFrame.slotIndex = i

            local slotPerk = nil
            local slotIndex = 1
            for spellId, perkData in pairs(lockedPerks) do
                if slotIndex == i then
                    slotPerk = perkData
                    break
                end
                slotIndex = slotIndex + 1
            end

            local qualityData = qualityInfo[slotPerk and (slotPerk.quality or 0) or 0] or qualityInfo[0]

            -- Update swirl color for quality.
            if slotFrame._swirl then
                slotFrame._swirl:SetVertexColor(qualityData.color[1], qualityData.color[2], qualityData.color[3], 0.55)
            end
            slotFrame._iconBase:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perk_quality_" ..
            qualityData.border)
            slotFrame._border:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perk_border_quality_" ..
            qualityData.border)

            local icon = slotFrame._icon
            if slotPerk then
                local spellName, _, spellIcon = GetSpellInfo(slotPerk.spellId)
                if spellIcon then
                    SetPortraitToTexture(icon, spellIcon)
                else
                    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
                icon:SetAlpha(1)
                slotFrame.lockedPerkId = slotPerk.spellId
                slotFrame.lockedPerkData = slotPerk

                -- Look up owned counts from granted perks
                local grantedPerks = ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetGrantedPerks and
                ProjectEbonhold.PerkService.GetGrantedPerks() or {}
                local instances = spellName and grantedPerks[spellName] or {}
                local cC, cU, cR, cE, cL = 0, 0, 0, 0, 0
                for _, inst in ipairs(instances) do
                    local q = inst.quality or 0
                    local s = inst.stack or 1
                    if q == 0 then
                        cC = cC + s
                    elseif q == 1 then
                        cU = cU + s
                    elseif q == 2 then
                        cR = cR + s
                    elseif q == 3 then
                        cE = cE + s
                    elseif q == 4 then
                        cL = cL + s
                    end
                end
                -- Include the locked perk itself (removed from granted pool when locked)
                local lq = slotPerk.quality or 0
                local ls = slotPerk.stack or 1
                if lq == 0 then
                    cC = cC + ls
                elseif lq == 1 then
                    cU = cU + ls
                elseif lq == 2 then
                    cR = cR + ls
                elseif lq == 3 then
                    cE = cE + ls
                elseif lq == 4 then
                    cL = cL + ls
                end
                slotFrame._countCommon = cC
                slotFrame._countUncommon = cU
                slotFrame._countRare = cR
                slotFrame._countEpic = cE
                slotFrame._countLegendary = cL
            else
                icon:SetAlpha(0)
                slotFrame.lockedPerkId = nil
                slotFrame.lockedPerkData = nil
                slotFrame._countCommon = 0
                slotFrame._countUncommon = 0
                slotFrame._countRare = 0
                slotFrame._countEpic = 0
                slotFrame._countLegendary = 0
            end

            -- Stack count badge
            local badge = slotFrame._lockedBadge
            if badge then
                if slotPerk and (slotPerk.stack or 1) > 0 then
                    badge:SetParent(empowermentFrame.gridContainer)
                    badge:ClearAllPoints()
                    badge:SetPoint("TOP", slotFrame, "TOP", 0, 10)
                    badge:SetFrameLevel(slotFrame:GetFrameLevel() + 5)
                    badge._txt:SetText(tostring(slotPerk.stack or 1))
                    badge._txt:SetTextColor(qualityData.color[1], qualityData.color[2], qualityData.color[3])
                    badge:Show()
                else
                    badge:Hide()
                end
            end

            slotFrame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.lockedPerkData then
                    local qData = qualityInfo[self.lockedPerkData.quality or 0] or qualityInfo[0]
                    local spellName = GetSpellInfo(self.lockedPerkId)
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(spellName or ("Spell " .. self.lockedPerkId), qData.color[1], qData.color[2],
                        qData.color[3])
                    GameTooltip:AddLine(qData.name, 0.5, 0.5, 0.5)
                    local lockedPerkDb = ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[self.lockedPerkId]
                    local familyLine = lockedPerkDb and utils.FormatPerkFamilies(lockedPerkDb.families)
                    if familyLine then
                        GameTooltip:AddLine(familyLine, 1, 1, 1)
                    end
                    GameTooltip:AddLine(" ")
                    local description = utils.GetSpellDescription(self.lockedPerkId, 500, self.lockedPerkData.stack or 1)
                    GameTooltip:AddLine(description, 1, 0.82, 0, true)
                    -- Show all owned rarity counts
                    local cl = self._countLegendary or 0
                    local ce = self._countEpic or 0
                    local cr = self._countRare or 0
                    local cu = self._countUncommon or 0
                    local cc = self._countCommon or 0
                    if cl > 0 or ce > 0 or cr > 0 or cu > 0 or cc > 0 then
                        GameTooltip:AddLine(" ")
                        if cl > 0 then GameTooltip:AddLine("Legendary: " .. cl, 1.0, 0.5, 0.0) end
                        if ce > 0 then GameTooltip:AddLine("Epic: " .. ce, 0.6, 0.2, 1.0) end
                        if cr > 0 then GameTooltip:AddLine("Rare: " .. cr, 0.0, 0.4, 1.0) end
                        if cu > 0 then GameTooltip:AddLine("Uncommon: " .. cu, 0.1, 1.0, 0.1) end
                        if cc > 0 then GameTooltip:AddLine("Common: " .. cc, 1, 1, 1) end
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cffFFD700Right-click to unlock|r", 1, 1, 0.5, true)
                else
                    GameTooltip:SetText("Permanent Echo Slot", 1, 0.82, 0)
                    GameTooltip:AddLine(
                    "Click to select an Echo to carry into your next run at maximum of stack 1. This echo is in addition to all the Echoes you'll unlock during that run.",
                        1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            slotFrame:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
            slotFrame:SetScript("OnClick", function(self, button)
                if IsShiftKeyDown() and button == "RightButton" and self.lockedPerkId then
                    local link = GetSpellLink(self.lockedPerkId)
                    if not link then
                        local name = GetSpellInfo(self.lockedPerkId)
                        if name then link = ("|cff71d5ff|Hspell:%d|h[%s]|h|r"):format(self.lockedPerkId, name) end
                    end
                    if link then
                        if not ChatEdit_GetActiveWindow() then ChatEdit_ActivateChat(ChatEdit_ChooseBoxForSend()) end
                        ChatEdit_InsertLink(link)
                    end
                    return
                end
                if button == "RightButton" and not IsShiftKeyDown() and self.lockedPerkId then
                    StaticPopupDialogs["UNLOCK_PERK_CONFIRM"] = {
                        text = "Unlock this echo from the permanent slot?",
                        button1 = "Yes",
                        button2 = "No",
                        OnAccept = function()
                            if ProjectEbonhold.PerkService.UnlockPerk(self.lockedPerkId) then
                                C_Timer.After(0.5, function()
                                    if ProjectEbonhold.PerkService.RequestGrantedPerks then
                                        ProjectEbonhold.PerkService.RequestGrantedPerks()
                                    end
                                end)
                            end
                        end,
                        timeout = 0,
                        whileDead = true,
                        hideOnEscape = true,
                    }
                    StaticPopup_Show("UNLOCK_PERK_CONFIRM")
                elseif button == "LeftButton" and not self.lockedPerkId then
                    ShowPerkSelectorForLocking(perksData, self.slotIndex)
                end
            end)

            table.insert(empowermentFrame.permanentSlots, slotFrame)
        end

        permanentSlotsStartY = permanentSlotsStartY - slotSize
    end

    local iconSize = 32
    local iconSpacing = 11
    local verticalSpacing = 14
    local columns = 5
    local totalGridWidth = (columns * iconSize) + ((columns - 1) * iconSpacing)
    local startX = math.floor((gridW - totalGridWidth) / 2)
    local startY = permanentSlotsStartY - 10
    if maxSlots > 0 then startY = startY - 10 end

    for i, perkData in ipairs(perkList) do
        if i > 80 then break end

        local row = math.floor((i - 1) / columns)
        local col = (i - 1) % columns
        local xOffset = startX + (col * (iconSize + iconSpacing))
        local yOffset = startY - (row * (iconSize + verticalSpacing))

        -- Acquire from pool (creates once, reuses forever).
        local iconFrame = AcquireIconFrame(empowermentFrame.gridContainer)
        iconFrame:SetSize(iconSize, iconSize)
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("TOPLEFT", empowermentFrame.gridContainer, "TOPLEFT", xOffset, yOffset)
        iconFrame:SetFrameLevel(empowermentFrame.gridContainer:GetFrameLevel() + 10)

        local qualityData = qualityInfo[perkData.quality] or qualityInfo[0]
        iconFrame._iconBase:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perk_quality_" .. qualityData.border)
        iconFrame._border:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perk_border_quality_" ..
        qualityData.border)

        local spellName, _, spellIcon = GetSpellInfo(perkData.spellId)
        if spellIcon then
            SetPortraitToTexture(iconFrame._icon, spellIcon)
        else
            iconFrame._icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        -- Determine highest owned rarity and its count, store all counts on frame
        local countCommon, countUncommon, countRare, countEpic, countLegendary = 0, 0, 0, 0, 0
        for _, inst in ipairs(perkData.instances or {}) do
            local q = inst.quality or 0
            local s = inst.stack or 1
            if q == 0 then
                countCommon = countCommon + s
            elseif q == 1 then
                countUncommon = countUncommon + s
            elseif q == 2 then
                countRare = countRare + s
            elseif q == 3 then
                countEpic = countEpic + s
            elseif q == 4 then
                countLegendary = countLegendary + s
            end
        end
        iconFrame._countLegendary = countLegendary
        iconFrame._countEpic      = countEpic
        iconFrame._countRare      = countRare
        iconFrame._countUncommon  = countUncommon
        iconFrame._countCommon    = countCommon

        -- Single badge: show only highest owned rarity
        local badge               = iconFrame._badge
        local badgeCount, badgeR, badgeG, badgeB
        if countLegendary > 0 then
            badgeCount, badgeR, badgeG, badgeB = countLegendary, 1.0, 0.5, 0.0
        elseif countEpic > 0 then
            badgeCount, badgeR, badgeG, badgeB = countEpic, 0.6, 0.2, 1.0
        elseif countRare > 0 then
            badgeCount, badgeR, badgeG, badgeB = countRare, 0.0, 0.4, 1.0
        elseif countUncommon > 0 then
            badgeCount, badgeR, badgeG, badgeB = countUncommon, 0.1, 1.0, 0.1
        elseif countCommon > 0 then
            badgeCount, badgeR, badgeG, badgeB = countCommon, 1, 1, 1
        end
        if badgeCount then
            badge:SetParent(empowermentFrame.gridContainer)
            badge:ClearAllPoints()
            badge:SetPoint("TOP", iconFrame, "TOP", 0, 10)
            badge:SetFrameLevel(iconFrame:GetFrameLevel() + 5)
            badge._txt:SetText(tostring(badgeCount))
            badge._txt:SetTextColor(badgeR, badgeG, badgeB)
            badge:Show()
        else
            badge:Hide()
            badge:ClearAllPoints()
        end

        -- Store perkData on frame for use in handlers (no closure capture).
        iconFrame._perkData = perkData
        iconFrame._descCache = nil -- clear so ApplySearchFilter rebuilds on next search

        iconFrame:SetScript("OnClick", function(self, button)
            -- Orb of Lost Memories: while an orb is armed, a left-click on an owned echo spends
            -- it on that echo. Checked FIRST so the dev-realm stack bindings below cannot fire
            -- during a selection. This grid only ever holds UNLOCKED echoes (permanent ones live
            -- in their own slot row, see Perks.lockedPerks), and the server re-validates
            -- ownership, lock state and the charge regardless.
            local orb = ProjectEbonhold.OrbService
            if orb and orb.IsArmed() and button == "LeftButton" and self._perkData then
                orb.SpendOn(self._perkData.spellId)
                return
            end

            if IsShiftKeyDown() and button == "RightButton" and self._perkData then
                local sid = self._perkData.spellId
                if not sid then return end
                local link = GetSpellLink(sid)
                if not link then
                    local name = GetSpellInfo(sid)
                    if name then link = ("|cff71d5ff|Hspell:%d|h[%s]|h|r"):format(sid, name) end
                end
                if link then
                    if not ChatEdit_GetActiveWindow() then ChatEdit_ActivateChat(ChatEdit_ChooseBoxForSend()) end
                    ChatEdit_InsertLink(link)
                end
            elseif utils.IsDevRealm() and self._perkData and self._perkData.spellId then
                if button == "LeftButton" then
                    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_DEV_ADD_PERK_STACK, tostring(self._perkData.spellId))
                elseif button == "RightButton" then
                    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_DEV_REMOVE_PERK_STACK, tostring(self._perkData.spellId))
                end
            end
        end)
        iconFrame:SetScript("OnEnter", function(self)
            if not self._perkData then return end
            local pd = self._perkData
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local qData = qualityInfo[pd.quality] or qualityInfo[0]
            GameTooltip:AddLine(pd.spellName or ("Spell " .. pd.spellId), qData.color[1], qData.color[2], qData.color[3])
            GameTooltip:AddLine(qData.name, 0.5, 0.5, 0.5)
            local perkDb = ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[pd.spellId]
            local familyLine = perkDb and utils.FormatPerkFamilies(perkDb.families)
            if familyLine then
                GameTooltip:AddLine(familyLine, 1, 1, 1)
            end
            GameTooltip:AddLine(" ")
            local description
            if #pd.instances > 1 then
                local spellInstances = {}
                for _, inst in ipairs(pd.instances) do
                    table.insert(spellInstances, { spellId = inst.spellId, stacks = inst.stack })
                end
                description = utils.GetStackedSpellDescription(spellInstances, 500)
            else
                local inst = pd.instances[1]
                description = utils.GetSpellDescription(inst.spellId, 500, inst.stack)
            end
            GameTooltip:AddLine(description, 1, 0.82, 0, true)
            -- Show all owned rarity counts
            local cl = self._countLegendary or 0
            local ce = self._countEpic or 0
            local cr = self._countRare or 0
            local cu = self._countUncommon or 0
            local cc = self._countCommon or 0
            if cl > 0 or ce > 0 or cr > 0 or cu > 0 or cc > 0 then
                GameTooltip:AddLine(" ")
                if cl > 0 then
                    GameTooltip:AddLine("Legendary: " .. cl, 1.0, 0.5, 0.0)
                end
                if ce > 0 then
                    GameTooltip:AddLine("Epic: " .. ce, 0.6, 0.2, 1.0)
                end
                if cr > 0 then
                    GameTooltip:AddLine("Rare: " .. cr, 0.0, 0.4, 1.0)
                end
                if cu > 0 then
                    GameTooltip:AddLine("Uncommon: " .. cu, 0.1, 1.0, 0.1)
                end
                if cc > 0 then
                    GameTooltip:AddLine("Common: " .. cc, 1, 1, 1)
                end
            end
            if utils.IsDevRealm() then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffFF6600[DEV] Left-click to add stack|r", 1, 1, 1, true)
                GameTooltip:AddLine("|cffFF6600[DEV] Right-click to remove stack|r", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        iconFrame:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

        table.insert(empowermentFrame.perkIcons, iconFrame)
    end

    -- Resize empowerment frame to fit all echo rows
    local numIcons = math.min(#perkList, 80)
    local totalRows = math.ceil(numIcons / columns)
    local gridBottom = math.abs(startY) + (totalRows * (iconSize + verticalSpacing))
    -- titleFrame(20) + topPad(15) + titleGap(10) + gridContent + searchBar(24) + bottomPad(15)
    local neededH = 20 + 15 + 10 + gridBottom + 24 + 15
    empowermentFrame:SetHeight(math.max(200, neededH))
    empowermentFrame.gridContainer:SetHeight(math.max(100, gridBottom + 20))

    -- Reapply any active search filter after icons are rebuilt
    if empowermentFrame.searchBox then
        ApplySearchFilter(empowermentFrame.searchBox:GetText())
    end
end


function ToggleCollapse()
    if not playerRunFrame then return end
end

local function CreateIntensityButton()
    if intensityButton then return intensityButton end

    intensityButton = CreateFrame("Button", "ProjectEbonholdIntensityButton", UIParent)
    intensityButton:SetSize(128, 100)
    intensityButton:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 250)
    intensityButton:SetFrameStrata("HIGH")
    intensityButton:Hide()

    local soulSwapBg = intensityButton:CreateTexture(nil, "BACKGROUND")
    soulSwapBg:SetSize(156, 90)
    soulSwapBg:SetPoint("CENTER", intensityButton, "CENTER", 0, 0)
    soulSwapBg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\soulswap")
    intensityButton.soulSwapBg = soulSwapBg

    local spellIcon = intensityButton:CreateTexture(nil, "BORDER")
    spellIcon:SetSize(28, 28)
    spellIcon:SetPoint("CENTER", intensityButton, "CENTER", 0, 0)
    local spellName, _, spellIconPath = GetSpellInfo(95078)
    if spellIconPath then
        spellIcon:SetTexture(spellIconPath)
        spellIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    intensityButton.spellIcon = spellIcon

    local highlight = intensityButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(128, 100)
    highlight:SetPoint("CENTER", intensityButton, "CENTER", 0, 0)
    highlight:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\soulswap")
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.3)

    intensityButton:SetScript("OnClick", function(self)
        if ProjectEbonhold and ProjectEbonhold.sendToServer and ProjectEbonhold.CS then
            ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ACCEPT_HIGHER_INTENSITY, "")
        end
        local intensityData = ProjectEbonhold.PlayerRunService.GetIntensityData()
        if intensityData then intensityData.onCooldown = false end
        self:Hide()
    end)

    intensityButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetHyperlink('spell:95078')
        GameTooltip:Show()
    end)
    intensityButton:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

    return intensityButton
end

local function UpdatePlayerRunData(data)
    if not playerRunFrame then CreatePlayerRunFrame() end

    playerRunFrame.currentData = data

    if playerRunFrame.soulPointsText and data.soulPoints ~= nil then
        playerRunFrame.currentSoulPoints = data.soulPoints
        playerRunFrame.soulPointsText:SetText(string.format("|cffffffff%s|r",
            ProjectEbonhold.FormatThousands(data.soulPoints)))
    end

    if playerRunFrame.multiplierText and data.soulPointsMultiplier ~= nil then
        playerRunFrame.currentMultiplier = data.soulPointsMultiplier
        playerRunFrame.multiplierText:SetText(string.format("|cff00ff00+%.0f%%|r", data.soulPointsMultiplier * 100))
    end

    if playerRunFrame.catchupText then
        local pct = data.catchupMultiplierPct or 0
        playerRunFrame.currentCatchupPct = pct
        if pct > 0 then
            playerRunFrame.catchupText:SetText(string.format("|cffffcc00+%d%%|r", pct))
        else
            playerRunFrame.catchupText:SetText("")
        end
    end

    if playerRunFrame.hardmodeTierText then
        local svc = ProjectEbonhold.HardmodeService
        if svc and svc.GetCurrentDifficulty then
            local diff = svc.GetCurrentDifficulty()
            if diff <= 1 then
                playerRunFrame.hardmodeTierText:SetText("|cffAAAAAANormal|r")
            else
                playerRunFrame.hardmodeTierText:SetText("|cffFF4444Hardcore " .. (diff - 1) .. "|r")
            end
        end
    end

    if playerRunFrame.intensityIndicator then
        local intensityData = ProjectEbonhold.PlayerRunService.GetIntensityData()
        local intensity = intensityData.intensity or 0
        playerRunFrame.currentIntensity = intensity
        local maxIntensity = ProjectEbonhold.Constants.MAX_INTENSITY
        intensity = math.min(intensity, maxIntensity)
        local progress = math.min(math.max(intensity / maxIntensity, 0), 1)
        local startOffset = IsTransparentDesign() and 40 or 20
        local barWidth = 160
        local indicatorWidth = 24
        local xPos = startOffset + (barWidth * progress) - (indicatorWidth / 2)
        if playerRunFrame.intensityFill then
            playerRunFrame.intensityFill:SetWidth(math.max(barWidth * progress, 1))
        end
        playerRunFrame.intensityIndicator:SetPoint("LEFT", playerRunFrame.intensityFrame, "LEFT", xPos, 0)
    end
end


local function UpdateIntensity(intensityData)
    if not playerRunFrame then return end

    local intensity = intensityData.intensity or 0
    playerRunFrame.currentIntensity = intensity
    local maxIntensity = ProjectEbonhold.Constants.MAX_INTENSITY
    intensity = math.min(intensity, maxIntensity)
    local progress = math.min(math.max(intensity / maxIntensity, 0), 1)
    local startOffset = IsTransparentDesign() and 40 or 20
    local barWidth = 160
    local indicatorWidth = 24
    local xPos = startOffset + (barWidth * progress) - (indicatorWidth / 2)

    if playerRunFrame.intensityFill then
        playerRunFrame.intensityFill:SetWidth(math.max(barWidth * progress, 1))
        playerRunFrame.intensityFill:SetVertexColor(0.8, 0.1, 0.1, 0.8)
    end

    if playerRunFrame.intensityFillFlash then
        playerRunFrame.intensityFillFlash:SetWidth(math.max(barWidth * progress, 1))
    end

    if playerRunFrame.intensityIndicator then
        playerRunFrame.intensityIndicator:SetPoint("LEFT", playerRunFrame.intensityFrame, "LEFT", xPos, 0)
    end

    if playerRunFrame.intensityLevelCircle and playerRunFrame.intensityLevelText then
        playerRunFrame.intensityLevelCircle:SetPoint("CENTER", playerRunFrame.intensityIndicator, "CENTER", 0, 0)
        local constants = ProjectEbonhold.Constants
        local tier = ""
        if intensity >= constants.INTENSITY_LEVEL_5 then
            tier = "5"
        elseif intensity >= constants.INTENSITY_LEVEL_4 then
            tier = "4"
        elseif intensity >= constants.INTENSITY_LEVEL_3 then
            tier = "3"
        elseif intensity >= constants.INTENSITY_LEVEL_2 then
            tier = "2"
        elseif intensity >= constants.INTENSITY_LEVEL_1 then
            tier = "1"
        end
        playerRunFrame.intensityLevelText:SetText(tier)
        if tier == "" then
            playerRunFrame.intensityLevelCircle:Hide()
        else
            playerRunFrame.intensityLevelCircle:Show()
        end
    end

    if playerRunFrame.intensityIcons then
        local constants = ProjectEbonhold.Constants
        local levels = {
            constants.INTENSITY_LEVEL_1,
            constants.INTENSITY_LEVEL_2,
            constants.INTENSITY_LEVEL_3,
            constants.INTENSITY_LEVEL_4,
            constants.INTENSITY_LEVEL_5
        }
        for i, iconFrame in ipairs(playerRunFrame.intensityIcons) do
            local isActive = intensity >= levels[i]
            if isActive then
                iconFrame.icon:SetDesaturated(false)
                if not iconFrame.wasActive and iconFrame.glowAnim then
                    iconFrame.glowAnim:Play()
                end
            else
                iconFrame.icon:SetDesaturated(true)
            end
            iconFrame.wasActive = isActive
        end
    end

    if playerRunFrame.reaperIcon then
        local areaName = intensityData.areaNameReaper or "0"
        if areaName ~= "0" then
            playerRunFrame.reaperIcon:SetTexCoord(0.214844, 0.312500, 0.894531, 0.996094)
        else
            playerRunFrame.reaperIcon:SetTexCoord(0.121094, 0.214844, 0.898438, 0.996094)
        end
    end

    local oldIntensity = playerRunFrame.lastIntensity or 0
    if playerRunFrame.intensityFillFlashAnim and intensity > oldIntensity then
        playerRunFrame.intensityFillFlashAnim:Stop()
        playerRunFrame.intensityFillFlashAnim:Play()
    end
    playerRunFrame.lastIntensity = intensity

    if not intensityButton then CreateIntensityButton() end
    local threshold = ProjectEbonhold.Constants and ProjectEbonhold.Constants.INTENSITY_LEVEL_3 or 300
    local canTrigger = intensityData.onCooldown == false
    if intensity >= threshold and canTrigger then
        intensityButton:Show()
    else
        intensityButton:Hide()
    end
end


local function RequestPlayerRunData()
    if ProjectEbonhold and ProjectEbonhold.sendToServer and ProjectEbonhold.CS then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PLAYER_RUN_DATA, "")
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PLAYER_SOUL_POINTS_ADDITIONAL_PCT, "")
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_INTENSITY_POINTS, "")
    end
end


local function UpdateGrantedPerks(forceEmpty)
    -- The Orb bubble lives on this panel, so it can only be built once the panel exists. The
    -- charge count usually lands before that at login, hence the rebuild attempt here rather
    -- than relying on the packet alone.
    if ProjectEbonhold.OrbService and ProjectEbonhold.OrbService.EnsureUI then
        ProjectEbonhold.OrbService.EnsureUI()
    end

    if forceEmpty then
        UpdateEmpowermentDisplay({})
        return
    end
    if ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetGrantedPerks then
        local perks = ProjectEbonhold.PerkService.GetGrantedPerks()
        UpdateEmpowermentDisplay(perks)
    end
end


-- ── Run HUD guided tour ──────────────────────────────────────────────────────
-- Shown once, shortly after the HUD first appears on a fresh account. Built on
-- the shared GlowBox tour factory (modules/guidedTour). The tour frames are
-- parented to the HUD, so they follow it if the player drags it mid-tour; the
-- GlowBox hangs off the left side since the HUD defaults to the screen's
-- right edge.
local hudTour = ProjectEbonhold.GuidedTour.Create({
    parent = function() return playerRunFrame end,
    dbKey = "seenRunHudTour",
    steps = function()
        return {
            {
                title = "Soul Ashes",
                text = "Soul Ashes earned during this run. When the run ends, " ..
                    "they are added to your |cffffd700Skill Tree|r, where you " ..
                    "spend them on permanent upgrades.",
                zone = function()
                    return playerRunFrame.soulAshIcon, playerRunFrame.soulPointsText
                end,
                boxAnchor = { "TOPRIGHT", "TOPLEFT", -14, 0 },
            },
            {
                title = "Soul Ash Multiplier",
                text = "Your Soul Ash gain multiplier. Increase it by completing " ..
                    "|cffffd700achievements|r and reaching higher " ..
                    "|cffffd700Intensity|r levels.",
                zone = function() return playerRunFrame.multiplierText end,
                boxAnchor = { "TOPRIGHT", "TOPLEFT", -14, 0 },
            },
            {
                title = "Survival",
                text = "Your lifelines: resurrections you can accept from " ..
                    "players, free self-resurrections, class resurrections and " ..
                    "|cffffd700Cheat Death|r charges. Hover the heart for the " ..
                    "full breakdown, including the Soul Ash cost of your next " ..
                    "resurrection.",
                zone = function() return playerRunFrame.hearthIcon end,
                boxAnchor = { "TOPRIGHT", "TOPLEFT", -14, 0 },
            },
            {
                title = "Intensity",
                text = "Defeating enemies quickly raises your Intensity; it " ..
                    "decays while you are out of combat. Higher levels unleash " ..
                    "extra hazards and feed your Soul Ash multiplier. Hover " ..
                    "the bar to see each threshold's effects.",
                zone = function() return playerRunFrame.intensityFrame end,
                boxAnchor = { "TOPRIGHT", "TOPLEFT", -14, 0 },
            },
        }
    end,
})

local isInitialized = false

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not isInitialized then
            CreatePlayerRunFrame()
            CreateEmpowermentFrame()
            if ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.RequestGrantedPerks then
                C_Timer.After(1.0, function()
                    ProjectEbonhold.PerkService.RequestGrantedPerks()
                end)
            end
            C_Timer.After(0.6, function()
                RestorePlayerRunUIPosition()
                RestoreEmpowermentUIPosition()
            end)
            -- After the saved position is restored, so the highlight anchors
            -- to where the HUD actually sits
            C_Timer.After(2.0, function()
                if playerRunFrame and playerRunFrame:IsShown() then
                    hudTour:MaybeStart()
                end
            end)
            isInitialized = true
        end
        RequestPlayerRunData()
    end
end)

local function GetUIElements()
    if not playerRunFrame then return nil end
    return {
        soulPointsText = playerRunFrame.soulPointsText,
        acceptedRezsText = nil,
        selfRezsText = nil,
        classRezsText = nil,
        avoidDeathText = nil,
        empowermentText = nil,
        intensityIndicator = playerRunFrame.intensityIndicator
    }
end

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.PlayerRunUI = ProjectEbonhold.PlayerRunUI or {}
ProjectEbonhold.PlayerRunUI.UpdateData = UpdatePlayerRunData
ProjectEbonhold.PlayerRunUI.Toggle = ToggleCollapse
ProjectEbonhold.PlayerRunUI.ToggleEmpowerment = ToggleEmpowermentPanel
ProjectEbonhold.PlayerRunUI.GetUIElements = GetUIElements
ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks = UpdateGrantedPerks
ProjectEbonhold.PlayerRunUI.UpdateIntensity = UpdateIntensity
