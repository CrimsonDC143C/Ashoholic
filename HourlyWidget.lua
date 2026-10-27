local addonName = ...
local addon = _G[addonName]

-- Compact on-screen readout of this character's raids-per-hour counter.
-- Stays up while the roster is closed. Drag to move; /ash widget toggles it.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE = 15

local frame

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function CurrentCharacter()
    if not addon.db or not addon.db.global or not addon.db.global.Characters then return end
    local player = UnitName("player")
    if not player or player == "" or player == UNKNOWN then return end
    local key = format("%s.%s", GetRealmName() or "", player)
    return addon.db.global.Characters[key], player
end

local function Hourly()
    local charDB = CurrentCharacter()
    if addon.Characters and addon.Characters.HourlyLockouts then
        return addon.Characters:HourlyLockouts(charDB)
    end
    return { tracked = false, count = 0, limit = 10, nextFree = 0, entries = {} }
end

local function ApplyPosition()
    if not frame then return end
    local o = addon.db and addon.db.global and addon.db.global.options
    local pos = o and o.HourlyWidgetPos
    frame:ClearAllPoints()
    if type(pos) == "table" and type(pos.point) == "string" and type(pos.x) == "number" and type(pos.y) == "number" then
        frame:SetPoint(pos.point, UIParent, pos.rel or pos.point, pos.x, pos.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -36)
    end
end

local function SavePosition()
    if not frame or not addon.db or not addon.db.global then return end
    local point, _, rel, x, y = frame:GetPoint()
    if not point or not x or not y then return end
    addon.db.global.options.HourlyWidgetPos = {
        point = point,
        rel = rel or point,
        x = x,
        y = y,
    }
end

local function Style()
    if not frame then return end
    local theme = addon.GetTheme and addon:GetTheme()
    local panel = (theme and theme.panel) or { 0.05, 0.05, 0.06, 0.92 }
    local border = (theme and theme.border) or { 0, 0, 0, 1 }
    frame:SetBackdropColor(panel[1], panel[2], panel[3], panel[4] or 0.92)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function addon:RefreshHourlyWidget()
    if not frame then return end
    Style()
    local hourly = Hourly()
    local count = hourly.count or 0
    local limit = hourly.limit or 10
    frame.count:SetText(count .. " / " .. limit)

    local theme = addon.GetTheme and addon:GetTheme()
    local bad = (theme and theme.wtLvlLockedRGB) or { 1, 0.33, 0.33 }
    local body = (theme and theme.body) or { 1, 1, 1 }
    if hourly.tracked and count >= limit then
        frame.count:SetTextColor(bad[1], bad[2], bad[3], 1)
        frame.time:SetTextColor(bad[1], bad[2], bad[3], 1)
    else
        frame.count:SetTextColor(body[1], body[2], body[3], 1)
        frame.time:SetTextColor(body[1], body[2], body[3], 1)
    end

    if hourly.tracked and count > 0 and (hourly.nextFree or 0) > 0 then
        frame.time:SetText(Clock(hourly.nextFree))
    else
        frame.time:SetText("--:--")
    end

    local shown = not (addon.db and addon.db.global and addon.db.global.options
        and addon.db.global.options.ShowHourlyWidget == 0)
    if shown then
        if not frame:IsShown() then frame:Show() end
    elseif frame:IsShown() then
        frame:Hide()
    end
end

function addon:ToggleHourlyWidget()
    if not addon.db or not addon.db.global then return end
    local o = addon.db.global.options
    local show = o.ShowHourlyWidget == 0
    o.ShowHourlyWidget = show and 1 or 0
    addon:RefreshHourlyWidget()
    if show then
        print("|cFF00FF9AAshoholic:|r Raid hour widget shown. Drag it to move.")
    else
        print("|cFF00FF9AAshoholic:|r Raid hour widget hidden. /ash widget to show it again.")
    end
end

function addon:InitHourlyWidget()
    if frame then
        ApplyPosition()
        addon:RefreshHourlyWidget()
        return
    end

    frame = CreateFrame("Frame", "AshoholicHourlyWidget", UIParent)
    frame:SetWidth(156)
    frame:SetHeight(30)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    local count = frame:CreateFontString(nil, "OVERLAY")
    count:SetFont(FONT, FONT_SIZE, "")
    count:SetPoint("LEFT", frame, "LEFT", 12, 0)
    count:SetJustifyH("LEFT")
    if count.SetJustifyV then count:SetJustifyV("MIDDLE") end
    if count.SetWordWrap then count:SetWordWrap(false) end
    frame.count = count

    local timeFs = frame:CreateFontString(nil, "OVERLAY")
    timeFs:SetFont(FONT, FONT_SIZE, "")
    timeFs:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    timeFs:SetJustifyH("RIGHT")
    if timeFs.SetJustifyV then timeFs:SetJustifyV("MIDDLE") end
    if timeFs.SetWordWrap then timeFs:SetWordWrap(false) end
    frame.time = timeFs

    frame:SetScript("OnDragStart", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    frame:SetScript("OnEnter", function(self)
        local _, player = CurrentCharacter()
        local hourly = Hourly()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(player or "Raids this hour", 1, 0.82, 0)
        if not hourly.tracked then
            GameTooltip:AddLine("Not tracked yet", 0.7, 0.7, 0.7)
        elseif hourly.count == 0 then
            GameTooltip:AddLine("No raid entries this hour", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Next slot frees in " .. Clock(hourly.nextFree), 0.85, 0.85, 0.85)
            local shown = math.min(hourly.count, 10)
            for i = 1, shown do
                local entry = hourly.entries[i]
                GameTooltip:AddDoubleLine(entry.label, Clock(entry.expires), 1, 1, 1, 1, 0.82, 0)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag to move.  /ash widget to hide.", 0.55, 0.52, 0.49)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)

    frame.elapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.5 then return end
        self.elapsed = 0
        addon:RefreshHourlyWidget()
    end)

    ApplyPosition()
    addon:RefreshHourlyWidget()
end
