local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.CheckpointUI = {}

local CheckpointUI = ProjectEbonhold.CheckpointUI

local checkpointTooltip = CreateFrame("GameTooltip", "ProjectEbonholdCheckpointTooltip", nil, "GameTooltipTemplate")
checkpointTooltip:SetFrameStrata("TOOLTIP")
checkpointTooltip:SetClampedToScreen(true)

local worldMapRects = {
    [31]  = { left = 1535.41663, right = -1935.41663, top = -7939.583, bottom = -10254.166 },
    [15]  = { left = 18171.97, right = -22569.21, top = 11176.3438, bottom = -15973.3438 },
    [14]  = { left = 17066.6, right = -19733.21, top = 12799.9, bottom = -11733.3 },
    [5]   = { left = -1962.5, right = -7250.0, top = 1808.333, bottom = -1716.667 },
    [10]  = { left = 2047.917, right = -3089.583, top = -272.9167, bottom = -3697.917 },
    [12]  = { left = 2622.917, right = -7510.417, top = 1612.5, bottom = -5143.75 },
    [16]  = { left = 783.3333, right = -2016.667, top = 1500.0, bottom = -366.6667 },
    [17]  = { left = -866.6666, right = -4466.667, top = -133.3333, bottom = -2533.333 },
    [18]  = { left = -2079.167, right = -4566.667, top = -5889.583, bottom = -7547.917 },
    [20]  = { left = -1241.667, right = -4591.667, top = -10566.67, bottom = -12800.0 },
    [21]  = { left = 3033.333, right = -1485.417, top = 3837.5, bottom = 824.9999 },
    [22]  = { left = 3450.0, right = -750.0, top = 1666.667, bottom = -1133.333 },
    [23]  = { left = 416.6667, right = -3883.333, top = 3366.667, bottom = 500.0 },
    [24]  = { left = -2287.5, right = -6318.75, top = 3704.167, bottom = 1016.667 },
    [25]  = { left = 1066.667, right = -2133.333, top = 400.0, bottom = -1733.333 },
    [27]  = { left = -1575.0, right = -5425.0, top = 1466.667, bottom = -1100.0 },
    [28]  = { left = 1802.083, right = -3122.917, top = -3877.083, bottom = -7150.417 },
    [29]  = { left = -322.9167, right = -2554.167, top = -6100.0, bottom = -7587.5 },
    [30]  = { left = -266.6667, right = -3195.833, top = -7031.25, bottom = -8983.333 },
    [33]  = { left = -833.3333, right = -3333.333, top = -9866.666, bottom = -11533.33 },
    [35]  = { left = 833.3333, right = -1866.667, top = -9716.666, bottom = -11516.67 },
    [36]  = { left = -1993.75, right = -4752.083, top = -4487.5, bottom = -6327.083 },
    [37]  = { left = -1570.833, right = -3741.667, top = -8575.0, bottom = -10022.92 },
    [38]  = { left = 2220.833, right = -4150.417, top = -11168.75, bottom = -15422.92 },
    [39]  = { left = -2222.917, right = -4516.667, top = -9620.833, bottom = -11150.0 },
    [40]  = { left = 3016.667, right = -483.3333, top = -9400.0, bottom = -11733.33 },
    [41]  = { left = -389.5833, right = -4525.0, top = -2147.917, bottom = -4904.167 },
    [42]  = { left = 3814.583, right = -1277.083, top = 11831.25, bottom = 8437.5 },
    [43]  = { left = 2941.667, right = -3508.333, top = 8333.333, bottom = 3966.667 },
    [44]  = { left = 1700.0, right = -4066.667, top = 4672.917, bottom = 829.1666 },
    [62]  = { left = -433.3333, right = -4833.333, top = -3966.667, bottom = -6900.0 },
    [82]  = { left = 3245.833, right = -1637.5, top = 2916.667, bottom = -339.5833 },
    [102] = { left = 4233.333, right = -262.5, top = 452.0833, bottom = -2545.833 },
    [122] = { left = 5441.667, right = -1508.333, top = -2366.667, bottom = -7000.0 },
    [142] = { left = -974.9999, right = -6225.0, top = -2033.333, bottom = -5533.333 },
    [162] = { left = -218.75, right = -7118.75, top = -5875.0, bottom = -10475.0 },
    [182] = { left = -3277.083, right = -8347.916, top = 5341.667, bottom = 1950.417 },
    [183] = { left = 1501.667, right = -4108.333, top = 7133.333, bottom = 3300.0 },
    [202] = { left = 533.3333, right = -3166.667, top = -5966.667, bottom = -8433.333 },
    [242] = { left = -1381.25, right = -3689.583, top = 8491.666, bottom = 6952.083 },
    [262] = { left = 2537.5, right = -945.834, top = -5958.334, bottom = -8281.25 },
    [282] = { left = -316.6667, right = -7416.667, top = 8533.333, bottom = 3800.0 },
    [302] = { left = 1722.917, right = -14.58333, top = -7995.833, bottom = -9154.166 },
    [322] = { left = -3680.501, right = -5083.206, top = 2273.877, bottom = 1338.461 },
    [342] = { left = -713.5914, right = -1504.216, top = -4569.241, bottom = -5096.846 },
    [363] = { left = 516.6666, right = -527.0833, top = -849.9999, bottom = -1545.833 },
    [382] = { left = 2938.363, right = 1880.03, top = 10238.32, bottom = 9532.587 },
    [383] = { left = 873.1926, right = -86.1824, top = 1877.945, bottom = 1237.841 },

    -- Alterac Valley
    [402] = { left = 1781.25, right = -2456.25, top = 1085.417, bottom = -1739.583 },

    -- Outland (continent + zones, MapID=530)
    [463] = { left = -4487.5, right = -9412.5, top = 11041.67, bottom = 7758.333 },
    [464] = { left = -5283.333, right = -8583.333, top = 8266.666, bottom = 6066.667 },
    [465] = { left = -10500, right = -14570.83, top = -2793.75, bottom = -5508.333 },
    [466] = { left = 5539.583, right = 375, top = 1481.25, bottom = -1962.5 },
    [467] = { left = 12996.04, right = -4468.039, top = 5821.359, bottom = -5821.359 },
    [468] = { left = 9475, right = 4447.917, top = 1935.417, bottom = -1416.667 },
    [472] = { left = -11066.37, right = -12123.14, top = -3609.683, bottom = -4314.371 },
    [474] = { left = 4225, right = -1275, top = -1947.917, bottom = -5614.583 },
    [476] = { left = 8845.833, right = 3420.833, top = 4408.333, bottom = 791.6666 },
    [477] = { left = -10075, right = -13337.5, top = -758.3333, bottom = -2933.333 },
    [478] = { left = 10295.83, right = 4770.833, top = 41.66666, bottom = -3641.667 },
    [479] = { left = 7083.333, right = 1683.333, top = -999.9999, bottom = -4600 },
    [480] = { left = 5483.333, right = -91.66666, top = 5456.25, bottom = 1739.583 },
    [481] = { left = -6400.75, right = -7612.208, top = 10153.71, bottom = 9346.938 },
    [482] = { left = 6135.259, right = 4829.009, top = -1473.954, bottom = -2344.788 },
    [500] = { left = -5302.083, right = -8629.166, top = 13568.75, bottom = 11350 },

    -- Northrend (continent + zones, MapID=571)
    [486] = { left = 9217.152, right = -8534.246, top = 10593.38, bottom = -1240.89 },
    [487] = { left = 8570.833, right = 2806.25, top = 4897.917, bottom = 1054.167 },
    [489] = { left = 3627.083, right = -1981.25, top = 5575, bottom = 1835.417 },
    [491] = { left = -1110.417, right = -6360.417, top = 5516.667, bottom = 2016.667 },
    [492] = { left = -1397.917, right = -7443.75, top = 3116.667, bottom = -914.5833 },
    [493] = { left = 5443.75, right = -827.0833, top = 9427.083, bottom = 5245.833 },
    [494] = { left = 6929.167, right = 2572.917, top = 7287.5, bottom = 4383.333 },
    [496] = { left = 1841.667, right = -5270.833, top = 10197.92, bottom = 5456.25 },
    [497] = { left = -600, right = -5593.75, top = 7668.75, bottom = 4339.583 },
    [502] = { left = 4329.167, right = 1354.167, top = 5716.667, bottom = 3733.333 },
    [511] = { left = 1443.75, right = -1279.167, top = 6502.083, bottom = 4687.5 },
    [542] = { left = 2797.917, right = -879.1666, top = 10781.25, bottom = 8329.166 },
}

local mapPins = {}

-- Icon per checkpoint "kind". MEETINGSTONE checkpoints (summon stones, both
-- dungeon and raid) use the custom wo_icon_raid texture instead of the flight
-- master icon. The custom asset and the default flight master texture need no
-- crop (0..1).
local PIN_ICONS = {
    DEFAULT = { texture = "Interface\\Minimap\\Tracking\\FlightMaster", coords = { 0, 1, 0, 1 } },
    MEETINGSTONE = { texture = "Interface\\AddOns\\ProjectEbonhold\\assets\\wo_icon_raid", coords = { 0, 1, 0, 1 } },
    MEETINGSTONE_RAID = { texture = "Interface\\AddOns\\ProjectEbonhold\\assets\\wo_icon_raid", coords = { 0, 1, 0, 1 } },
}

-- Base pin dimensions. Meeting-stone summon pins render 50% larger so the
-- custom icon stands out from the flight-path pins.
local PIN_SIZE = 28
local PIN_RING_SIZE = 36
local MEETINGSTONE_SCALE = 1.5

-- Glow-ring size for the larger meeting-stone pins. The flight-master icon sits
-- inside its texture with padding, so the default ring/icon ratio (36/28) reads
-- as a snug halo. The custom raid/dungeon icon fills its texture edge-to-edge,
-- so scaling that same ratio up makes the glow look oversized. Use a tighter
-- absolute ring that just hugs the scaled icon (PIN_SIZE * MEETINGSTONE_SCALE = 42).
local MEETINGSTONE_RING_SIZE = 46

local function IsMeetingStone(kind)
    return kind == "MEETINGSTONE" or kind == "MEETINGSTONE_RAID"
end

local function GetPinScale(kind)
    return IsMeetingStone(kind) and MEETINGSTONE_SCALE or 1
end

local function GetPinRingSize(kind)
    return IsMeetingStone(kind) and MEETINGSTONE_RING_SIZE or PIN_RING_SIZE
end

local function GetPinIcon(kind)
    return PIN_ICONS[kind or "DEFAULT"] or PIN_ICONS.DEFAULT
end

local function ConvertToContinentCoords(mapId, x, y)
    local rect = worldMapRects[mapId]
    if not rect then
        return nil, nil
    end

    local absX = rect.left + (rect.right - rect.left) * x
    local absY = rect.top + (rect.bottom - rect.top) * y
    return absX, absY
end

local function ConvertToMapRelativeCoords(targetMapId, absX, absY)
    local rect = worldMapRects[targetMapId]
    if not rect then
        return nil, nil
    end

    local x = (absX - rect.left) / (rect.right - rect.left)
    local y = (absY - rect.top) / (rect.bottom - rect.top)
    return x, y
end

local function IsInsideRect(mapId, absX, absY)
    local rect = worldMapRects[mapId]
    if not rect then
        return false
    end

    local minX = math.min(rect.left, rect.right)
    local maxX = math.max(rect.left, rect.right)
    local minY = math.min(rect.top, rect.bottom)
    local maxY = math.max(rect.top, rect.bottom)

    return absX >= minX and absX <= maxX and absY >= minY and absY <= maxY
end

local function AcquirePin(index, parentFrame)
    local pinParent = WorldMapButton or parentFrame or WorldMapDetailFrame
    local pin = mapPins[index]
    if pin then
        if pinParent and pin:GetParent() ~= pinParent then
            pin:SetParent(pinParent)
        end
        if parentFrame then
            pin:SetFrameLevel(parentFrame:GetFrameLevel() + 20)
        end
        return pin
    end

    pin = CreateFrame("Button", nil, pinParent)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:EnableMouse(true)
    pin:SetFrameStrata("FULLSCREEN_DIALOG")
    pin:SetHitRectInsets(-10, -10, -10, -10)
    pin:SetToplevel(true)
    if parentFrame then
        pin:SetFrameLevel(parentFrame:GetFrameLevel() + 20)
    end

    pin.rotatingTex = pin:CreateTexture(nil, "BACKGROUND")
    pin.rotatingTex:SetSize(PIN_RING_SIZE, PIN_RING_SIZE)
    pin.rotatingTex:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.rotatingTex:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\progression_bar")
    pin.rotatingTex:SetTexCoord(0.023438, 0.210938, 0.283203, 0.478516)
    pin.rotatingTex:SetBlendMode("ADD")
    pin.rotatingTex:Hide()
    local rotAnim = pin.rotatingTex:CreateAnimationGroup()
    rotAnim:SetLooping("REPEAT")
    local rot = rotAnim:CreateAnimation("Rotation")
    rot:SetDegrees(360)
    rot:SetDuration(8)
    pin.rotAnim = rotAnim

    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints(pin)
    pin.icon:SetTexture("Interface\\Minimap\\Tracking\\FlightMaster")

    pin.highlight = pin:CreateTexture(nil, "HIGHLIGHT")
    pin.highlight:SetAllPoints(pin)
    pin.highlight:SetTexture("Interface\\Minimap\\Tracking\\FlightMaster")
    pin.highlight:SetBlendMode("ADD")
    pin.highlight:SetAlpha(0.4)

    pin:SetScript("OnEnter", function(self)
        checkpointTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        checkpointTooltip:ClearLines()
        checkpointTooltip:AddLine(self.nodeName or "Flight Path", 1, 0.82, 0)
        if self.isUnlocked then
            checkpointTooltip:AddLine("Click to travel to this checkpoint.", 1, 1, 1, true)
        elseif self.kind == "MEETINGSTONE" or self.kind == "MEETINGSTONE_RAID" then
            checkpointTooltip:AddLine("Not yet unlocked, visit the meeting stone to unlock this checkpoint and gain the ability to teleport.", 1, 0.35, 0.35,
                true)
        else
            checkpointTooltip:AddLine("Not yet unlocked, speak to the flight master to unlock it and gain the ability to teleport.", 1, 0.35, 0.35,
                true)
        end
        checkpointTooltip:Show()
    end)

    pin:SetScript("OnLeave", function()
        checkpointTooltip:Hide()
    end)

    pin:SetScript("OnClick", function(self)
        if self.isFactionAllowed == false then
            return
        end

        if not self.isUnlocked then
            return
        end

        if ProjectEbonhold.CheckpointService and ProjectEbonhold.CheckpointService.UseCheckpoint then
            ProjectEbonhold.CheckpointService.UseCheckpoint(self.checkpointId)
        end

        if WorldMapFrame and WorldMapFrame:IsShown() then
            HideUIPanel(WorldMapFrame)
        end
    end)

    mapPins[index] = pin
    return pin
end

local function HideUnusedPins(startIndex)
    for index = startIndex, #mapPins do
        mapPins[index]:Hide()
    end
end

function CheckpointUI.RefreshPins()
    if not WorldMapDetailFrame then
        HideUnusedPins(1)
        return
    end
    if not WorldMapDetailFrame:IsShown() then
        HideUnusedPins(1)
        return
    end

    if not ProjectEbonhold.CheckpointService or not ProjectEbonhold.CheckpointService.GetCheckpoints then
        HideUnusedPins(1)
        return
    end

    local currentMapId = GetCurrentMapAreaID and GetCurrentMapAreaID() or 0
    local mapFrame = WorldMapDetailFrame
    local width = mapFrame:GetWidth()
    local height = mapFrame:GetHeight()
    local visiblePinCount = 0
    local checkpoints = ProjectEbonhold.CheckpointService.GetCheckpoints()

    for _, checkpoint in ipairs(checkpoints) do
        if checkpoint.mapId == currentMapId and checkpoint.factionAllowed ~= false then
            local absX, absY = ConvertToContinentCoords(checkpoint.mapId, checkpoint.x, checkpoint.y)
            if absX and absY and IsInsideRect(currentMapId, absX, absY) then
                local relX, relY = ConvertToMapRelativeCoords(currentMapId, absX, absY)
                if relX and relY then
                    visiblePinCount = visiblePinCount + 1
                    local pin = AcquirePin(visiblePinCount, mapFrame)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", mapFrame, "TOPLEFT", relX * width, -relY * height)
                    pin.checkpointId = checkpoint.id
                    pin.nodeName = checkpoint.name
                    pin.isFactionAllowed = checkpoint.factionAllowed
                    pin.isUnlocked = checkpoint.unlocked
                    pin.kind = checkpoint.kind

                    -- Pins are pooled/reused, so set the icon and size per kind.
                    local scale = GetPinScale(checkpoint.kind)
                    local ringSize = GetPinRingSize(checkpoint.kind)
                    pin:SetSize(PIN_SIZE * scale, PIN_SIZE * scale)
                    pin.rotatingTex:SetSize(ringSize, ringSize)

                    local iconInfo = GetPinIcon(checkpoint.kind)
                    pin.icon:SetTexture(iconInfo.texture)
                    pin.icon:SetTexCoord(unpack(iconInfo.coords))
                    pin.highlight:SetTexture(iconInfo.texture)
                    pin.highlight:SetTexCoord(unpack(iconInfo.coords))

                    if checkpoint.unlocked then
                        pin.icon:SetVertexColor(1, 1, 1, 1)
                        pin.highlight:SetAlpha(0.4)
                        if pin.rotatingTex then
                            pin.rotatingTex:Show()
                            if pin.rotAnim and not pin.rotAnim:IsPlaying() then
                                pin.rotAnim:Play()
                            end
                        end
                    else
                        pin.icon:SetVertexColor(0.45, 0.45, 0.45, 1)
                        pin.highlight:SetAlpha(0.1)
                        if pin.rotatingTex then
                            pin.rotatingTex:Hide()
                            if pin.rotAnim and pin.rotAnim:IsPlaying() then
                                pin.rotAnim:Stop()
                            end
                        end
                    end
                    pin:EnableMouse(true)
                    pin:Show()
                end
            end
        end
    end

    HideUnusedPins(visiblePinCount + 1)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("WORLD_MAP_UPDATE")
eventFrame:RegisterEvent("WORLD_MAP_NAME_UPDATE")
eventFrame:RegisterEvent("TAXIMAP_OPENED")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, function()
            CheckpointUI.RefreshPins()
        end)
    elseif event == "TAXIMAP_OPENED" then
        if TaxiFrame and TaxiFrame:IsShown() then
            HideUIPanel(TaxiFrame)
        end
        CloseTaxiMap()
        if WorldMapFrame and not WorldMapFrame:IsShown() then
            ShowUIPanel(WorldMapFrame)
        end
        CheckpointUI.RefreshPins()
    else
        CheckpointUI.RefreshPins()
    end
end)

if WorldMapDetailFrame then
    WorldMapDetailFrame:HookScript("OnShow", function()
        CheckpointUI.RefreshPins()
        WorldMapDetailFrame:EnableMouse(false)
    end)

    WorldMapDetailFrame:HookScript("OnHide", function()
        WorldMapDetailFrame:EnableMouse(true)
        checkpointTooltip:Hide()
        HideUnusedPins(1)
    end)
end
