-- nameplate_dots.lua -- the player's own class debuffs above enemy nameplates.
--
-- Each enemy plate shows the debuffs the player put on that unit (DoTs, slows,
-- crowd control), with the time left and the stack count. Permanent debuffs
-- (no duration) are left out, they say nothing about what to refresh. So are
-- debuffs that are not of the player's class (items, racials, family-less echo
-- effects): nameplate_dots_data.lua lists each class's spell ids.
--
-- Which plate is whose: same as champion_marker.lua, the client's AwesomeWotlk
-- library gives each shown plate a unit token ("nameplate1"...) and
-- C_NamePlate.GetNamePlateForUnit(token). All tokens are probed because their
-- numbers can have holes. Without that library the module does nothing.
--
-- Cost: open-world density is 4x and combat is dense, so nothing here runs per
-- frame or per aura event. The plates are looked at 5 times a second, only in
-- combat or while an icon is still up, and a row is only built for a plate that
-- has something to show. A row is a frame with plain textures and font strings,
-- no child frames and no cooldown widgets. It takes no mouse, so clicks still
-- reach the plate.
--
-- On by default. The player turns it off with the "nameplateDotsEnabled" setting,
-- a checkbox of the Project Ebonhold > Nameplates options panel.

local ICON_SIZE = 22
local ICON_GAP = 2
local MAX_ICONS = 6
local TICK = 0.2           -- seconds between two looks at the plates
local MAX_TOKENS = 60      -- nameplate1 .. nameplateN probed per look
local MAX_SCAN = 40        -- aura slots read per unit
local ROW_Y = 2            -- above the plate; its frame already reaches over the name
local ROW_Y_ELVUI = 12     -- ElvUI writes the name above the frame's top edge
local ROW_Y_CHAMPION = 28  -- above the champion icon (24 px, champion_marker.lua)
local URGENT = 3           -- seconds left under which the timer turns red
local WHITE = "Interface\\Buttons\\WHITE8X8"

local rows = {}            -- [plate frame] = row frame
local seen = {}            -- [plate frame] = true for the plates filled in this look
local shownRows = 0
local classDebuffs         -- [spell id] = true, built on the first look

-- Keeps the player's class only and frees the other classes' lists.
local function LoadClassDebuffs()
    local _, class = UnitClass("player")
    local ids = EbonholdClassDebuffs and EbonholdClassDebuffs[class] or {}
    classDebuffs = {}
    for i = 1, #ids do
        classDebuffs[ids[i]] = true
    end
    EbonholdClassDebuffs = nil
end

local function NewIcon(row)
    local icon = {}
    icon.border = row:CreateTexture(nil, "BACKGROUND")
    icon.border:SetTexture(WHITE)
    icon.border:SetVertexColor(0, 0, 0, 1)
    icon.border:SetWidth(ICON_SIZE)
    icon.border:SetHeight(ICON_SIZE)

    icon.tex = row:CreateTexture(nil, "ARTWORK")
    icon.tex:SetPoint("TOPLEFT", icon.border, "TOPLEFT", 1, -1)
    icon.tex:SetPoint("BOTTOMRIGHT", icon.border, "BOTTOMRIGHT", -1, 1)
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    icon.time = row:CreateFontString(nil, "OVERLAY")
    icon.time:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    icon.time:SetPoint("CENTER", icon.border, "CENTER", 0, 0)

    icon.count = row:CreateFontString(nil, "OVERLAY")
    icon.count:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    icon.count:SetPoint("BOTTOMRIGHT", icon.border, "BOTTOMRIGHT", 0, 0)
    return icon
end

local function RowOf(plate)
    local row = rows[plate]
    if row then return row end
    row = CreateFrame("Frame", nil, plate)
    row:SetFrameStrata("HIGH")
    row:SetHeight(ICON_SIZE)
    row:SetWidth(ICON_SIZE)
    row.icons = {}
    row:Hide()
    rows[plate] = row
    return row
end

local function ShowIconState(icon, remaining, count)
    local seconds = math.ceil(remaining)
    if icon.shownSeconds ~= seconds then
        icon.shownSeconds = seconds
        if seconds <= 0 then
            icon.time:SetText("")
        elseif seconds >= 60 then
            icon.time:SetText(math.floor(seconds / 60) .. "m")
        else
            icon.time:SetText(seconds)
        end
        if seconds <= URGENT then
            icon.time:SetTextColor(1, 0.25, 0.2)
        else
            icon.time:SetTextColor(1, 1, 1)
        end
    end
    if icon.shownCount ~= count then
        icon.shownCount = count
        icon.count:SetText(count > 1 and count or "")
    end
end

local function SetIconShown(icon, shown)
    if shown then
        icon.border:Show()
        icon.tex:Show()
        icon.time:Show()
        icon.count:Show()
    else
        icon.border:Hide()
        icon.tex:Hide()
        icon.time:Hide()
        icon.count:Hide()
    end
end

-- Returns true when the plate shows at least one icon.
local function Fill(plate, unit, now)
    local row = rows[plate]
    local shown = 0
    for i = 1, MAX_SCAN do
        local name, _, tex, count, _, duration, expires, _, _, _, spellId = UnitDebuff(unit, i, "PLAYER")
        if not name then break end
        if duration and duration > 0 and expires and classDebuffs[spellId] then
            row = row or RowOf(plate)
            shown = shown + 1
            local icon = row.icons[shown]
            if not icon then
                icon = NewIcon(row)
                row.icons[shown] = icon
                icon.border:SetPoint("LEFT", row, "LEFT", (shown - 1) * (ICON_SIZE + ICON_GAP), 0)
            end
            if icon.shownTex ~= tex then
                icon.shownTex = tex
                icon.tex:SetTexture(tex)
            end
            ShowIconState(icon, expires - now, count or 0)
            if not icon.visible then
                icon.visible = true
                SetIconShown(icon, true)
            end
            if shown >= MAX_ICONS then break end
        end
    end
    if shown == 0 then return false end

    for i = shown + 1, #row.icons do
        local icon = row.icons[i]
        if icon.visible then
            icon.visible = false
            SetIconShown(icon, false)
        end
    end
    if row.shownIcons ~= shown then
        row.shownIcons = shown
        row:SetWidth(shown * ICON_SIZE + (shown - 1) * ICON_GAP)
    end
    local champion = ProjectEbonhold and ProjectEbonhold.IsChampionPlate and ProjectEbonhold.IsChampionPlate(plate)
    local y = champion and ROW_Y_CHAMPION or (IsAddOnLoaded("ElvUI") and ROW_Y_ELVUI or ROW_Y)
    if row.shownY ~= y then
        row.shownY = y
        row:ClearAllPoints()
        row:SetPoint("BOTTOM", plate, "TOP", 0, y)
    end
    row:Show()
    return true
end

local function IsEnabled()
    local svc = ProjectEbonholdOptionsService
    return not svc or svc:GetSetting("nameplateDotsEnabled") ~= false
end

local function HideAllRows()
    for _, row in pairs(rows) do
        if row:IsShown() then row:Hide() end
    end
    shownRows = 0
end

local function Look()
    if not IsEnabled() then
        if shownRows > 0 then HideAllRows() end
        return
    end
    if shownRows == 0 and not UnitAffectingCombat("player") then return end
    if not classDebuffs then LoadClassDebuffs() end
    local now = GetTime()
    for i = 1, MAX_TOKENS do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) then
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            if plate and Fill(plate, unit, now) then
                seen[plate] = true
            end
        end
    end
    shownRows = 0
    for plate, row in pairs(rows) do
        if seen[plate] then
            shownRows = shownRows + 1
            seen[plate] = nil
        elseif row:IsShown() then
            row:Hide()
        end
    end
end

if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
    if EbonholdLog then EbonholdLog("nameplate_dots: no C_NamePlate in this client, nameplate debuffs off") end
    return
end

-- Options checkbox: top right of the Nameplates panel, beside the reskin's own first row.
local function CreateOptionCheckbox()
    local parent = _G.InterfaceOptionsProjectEbonholdPanelNameplatesScrollChild
    local panel = _G.InterfaceOptionsProjectEbonholdPanelNameplates
    if not (parent and panel) then return end

    local cb = CreateFrame("CheckButton", "ProjectEbonholdNameplateDotsCheck", parent,
        "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 250, -10)
    _G[cb:GetName() .. "Text"]:SetText("Show my class debuffs above enemy nameplates")
    cb:SetScript("OnClick", function(self)
        ProjectEbonholdOptionsService:SetSetting("nameplateDotsEnabled", self:GetChecked() and true or false)
    end)

    local function Refresh() cb:SetChecked(IsEnabled()) end
    panel:HookScript("OnShow", Refresh)
    if panel.refresh then hooksecurefunc(panel, "refresh", Refresh) end
    Refresh()
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    CreateOptionCheckbox()
end)

local driver = CreateFrame("Frame")
local since, logged = 0, false
driver:SetScript("OnUpdate", function(_, elapsed)
    since = since + (elapsed or 0)
    if since < TICK then return end
    since = 0
    local ok, err = pcall(Look)
    if not ok and not logged and EbonholdLog then   -- once: a broken look would repeat 5 times a second
        logged = true
        EbonholdLog("nameplate_dots: " .. tostring(err))
    end
end)
