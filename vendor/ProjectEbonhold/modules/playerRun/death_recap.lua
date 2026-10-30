local addonName, Addon = ...

ProjectEbonhold = ProjectEbonhold or {}

local Texts = ProjectEbonhold.DeathRecapTexts

-- Ten events are kept and scrolled through five at a time, so the panel stays short enough to
-- sit above the death frame without covering it.
local MAX_EVENTS = 10
local VISIBLE_ROWS = 5
local ROW_HEIGHT = 36

local FRAME_WIDTH = 360
local CONTENT_LEFT = 18
-- Right-hand gutter left free for the scroll bar.
local SCROLLBAR_RESERVE = 30
local ROW_WIDTH = FRAME_WIDTH - CONTENT_LEFT - SCROLLBAR_RESERVE

local HEADER_HEIGHT = 92
local FOOTER_HEIGHT = 22

local ICON_SIZE = 28
local ICON_GAP = 8
-- The numbers column has a fixed width so the source line can never run underneath it.
local NUMBER_COLUMN = 86

local CAPTURE_WINDOW = 30
local BUFFER_SIZE = 60

local MELEE_ICON = "Interface\\Icons\\INV_Sword_04"
local INSTAKILL_ICON = "Interface\\Icons\\Spell_Shadow_DeathCoil"

local ENVIRONMENT_INFO = {
    DROWNING = { name = "Drowning", icon = "Interface\\Icons\\Spell_Shadow_DemonBreath" },
    FALLING  = { name = "Falling", icon = "Interface\\Icons\\Ability_Rogue_QuickRecovery" },
    FATIGUE  = { name = "Fatigue", icon = "Interface\\Icons\\Spell_Shadow_Haunting" },
    FIRE     = { name = "Fire", icon = "Interface\\Icons\\Spell_Fire_Fire" },
    LAVA     = { name = "Lava", icon = "Interface\\Icons\\Spell_Fire_Volcano" },
    SLIME    = { name = "Slime", icon = "Interface\\Icons\\INV_Misc_Slime_01" }
}

-- Spell school bitmask -> tint used on the amount text.
local SCHOOL_COLORS = {
    [1]  = { 1.00, 1.00, 0.60 },
    [2]  = { 1.00, 0.90, 0.60 },
    [4]  = { 1.00, 0.60, 0.30 },
    [8]  = { 0.50, 1.00, 0.50 },
    [16] = { 0.60, 1.00, 1.00 },
    [32] = { 0.75, 0.65, 1.00 },
    [64] = { 1.00, 0.65, 1.00 }
}

-- "spell" events all put spellId, spellName, spellSchool ahead of the damage payload, so they
-- share one parser; swings and environmental damage each need their own offset.
local DAMAGE_EVENTS = {
    SWING_DAMAGE = "swing",
    RANGE_DAMAGE = "spell",
    SPELL_DAMAGE = "spell",
    SPELL_PERIODIC_DAMAGE = "spell",
    SPELL_BUILDING_DAMAGE = "spell",
    DAMAGE_SHIELD = "spell",
    DAMAGE_SPLIT = "spell",
    ENVIRONMENTAL_DAMAGE = "environmental"
}

local HEAL_EVENTS = {
    SPELL_HEAL = true,
    SPELL_PERIODIC_HEAL = true
}


local buffer = {}
local pushCount = 0

local lastRecap = nil
local lastSnapshotTime = 0
local playerGUID = nil

local recapFrame = nil
-- The panel is opt-in: it only appears once the player clicks the death frame button. The flag
-- survives the frame being hidden so the confirmation popups, which hide and re-show the death
-- frame, do not close a panel the player deliberately opened.
local panelRequested = false


local function GetSchoolColor(school)
    local color = SCHOOL_COLORS[school or 1]
    if color then return color[1], color[2], color[3] end
    return 1, 1, 1
end


-- Hits and health pools in this expansion stay well under six digits, and the exact number is
-- the point of a recap, so only abbreviate once a value would no longer fit the row.
local ABBREVIATE_ABOVE = 100000

local function FormatAmount(amount, forceAbbreviate)
    amount = amount or 0
    if amount >= 1000000 then
        return string.format("%.1fm", amount / 1000000)
    elseif forceAbbreviate or amount >= ABBREVIATE_ABOVE then
        return string.format("%.1fk", amount / 1000)
    end
    return tostring(amount)
end


local function StyleFont(fontString, size, r, g, b)
    local font, _, flags = fontString:GetFont()
    if font then fontString:SetFont(font, size, flags) end
    fontString:SetTextColor(r, g, b)
    -- The frame art is busy and light in places; a hard shadow keeps every line readable on it.
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(1, -1)
end


local function PushEvent(entry)
    pushCount = pushCount + 1
    buffer[(pushCount - 1) % BUFFER_SIZE + 1] = entry
end


-- Newest first, stopping at the first entry older than CAPTURE_WINDOW.
local function CollectEvents(deathTime)
    local events = {}
    local available = math.min(pushCount, BUFFER_SIZE)

    for i = 0, available - 1 do
        local entry = buffer[(pushCount - 1 - i) % BUFFER_SIZE + 1]
        if not entry then break end
        if deathTime - entry.time > CAPTURE_WINDOW then break end
        table.insert(events, entry)
        if #events >= MAX_EVENTS then break end
    end

    return events
end


local function BuildEntry(kind, name, icon, school, sourceName)
    return {
        time = GetTime(),
        kind = kind,
        name = name,
        icon = icon,
        school = school,
        sourceName = sourceName,
        health = UnitHealth("player"),
        healthMax = UnitHealthMax("player")
    }
end


local function HandleCombatLog(timestamp, event, sourceGUID, sourceName, sourceFlags,
                               destGUID, destName, destFlags, ...)
    -- Everything the recap needs happened to the player, so anything aimed elsewhere is dropped
    -- before it costs a table allocation.
    if destGUID ~= playerGUID then return end

    if event == "UNIT_DIED" then
        ProjectEbonhold.DeathRecap.Capture()
        return
    end

    local damageKind = DAMAGE_EVENTS[event]
    if damageKind then
        local entry

        if damageKind == "swing" then
            local amount, overkill, school, resisted, blocked, absorbed, critical = ...
            entry = BuildEntry("damage", Texts.labels.melee, MELEE_ICON, school, sourceName)
            entry.amount = amount
            entry.overkill = overkill
            entry.resisted = resisted
            entry.blocked = blocked
            entry.absorbed = absorbed
            entry.critical = critical
        elseif damageKind == "environmental" then
            local envType, amount, overkill, school, resisted, blocked, absorbed, critical = ...
            local info = ENVIRONMENT_INFO[envType or ""]
            entry = BuildEntry("damage", info and info.name or tostring(envType),
                info and info.icon or MELEE_ICON, school, nil)
            entry.amount = amount
            entry.overkill = overkill
            entry.resisted = resisted
            entry.blocked = blocked
            entry.absorbed = absorbed
            entry.critical = critical
            entry.isEnvironmental = true
        else
            local spellId, spellName, spellSchool, amount, overkill, school,
                  resisted, blocked, absorbed, critical = ...
            local icon = select(3, GetSpellInfo(spellId))
            entry = BuildEntry("damage", spellName, icon or MELEE_ICON,
                school or spellSchool, sourceName)
            entry.amount = amount
            entry.overkill = overkill
            entry.resisted = resisted
            entry.blocked = blocked
            entry.absorbed = absorbed
            entry.critical = critical
            entry.spellId = spellId
        end

        if entry and (entry.amount or 0) > 0 then PushEvent(entry) end
        return
    end

    if HEAL_EVENTS[event] then
        local spellId, spellName, spellSchool, amount, overhealing, absorbed, critical = ...
        local effective = (amount or 0) - (overhealing or 0)
        if effective > 0 then
            local icon = select(3, GetSpellInfo(spellId))
            local entry = BuildEntry("heal", spellName, icon or MELEE_ICON, spellSchool, sourceName)
            entry.amount = effective
            entry.overhealing = overhealing
            entry.critical = critical
            entry.spellId = spellId
            PushEvent(entry)
        end
        return
    end

    if event == "SPELL_INSTAKILL" then
        local spellId, spellName, spellSchool = ...
        local icon = select(3, GetSpellInfo(spellId))
        local entry = BuildEntry("instakill", spellName, icon or INSTAKILL_ICON, spellSchool,
            sourceName)
        entry.amount = 0
        entry.spellId = spellId
        PushEvent(entry)
    end
end


local function ShowRowTooltip(row)
    local entry = row.entry
    if not entry then return end

    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(entry.name or Texts.labels.unknownSource)

    if entry.sourceName then
        GameTooltip:AddLine(entry.sourceName, 0.8, 0.8, 0.8)
    end

    if entry.kind == "heal" then
        GameTooltip:AddLine(Texts.tooltip.healReceived(entry.amount or 0), 1, 1, 1)
        if (entry.overhealing or 0) > 0 then
            GameTooltip:AddLine(Texts.tooltip.overhealing(entry.overhealing), 0.8, 0.8, 0.8)
        end
    elseif entry.kind == "instakill" then
        GameTooltip:AddLine(Texts.labels.instakill, 1, 0.25, 0.25)
    else
        GameTooltip:AddLine(Texts.tooltip.damageTaken(entry.amount or 0), 1, 1, 1)
        if (entry.overkill or 0) > 0 then
            GameTooltip:AddLine(Texts.tooltip.overkill(entry.overkill), 1, 0.5, 0.5)
        end
        if (entry.absorbed or 0) > 0 then
            GameTooltip:AddLine(Texts.tooltip.absorbed(entry.absorbed), 0.8, 0.8, 0.8)
        end
        if (entry.resisted or 0) > 0 then
            GameTooltip:AddLine(Texts.tooltip.resisted(entry.resisted), 0.8, 0.8, 0.8)
        end
        if (entry.blocked or 0) > 0 then
            GameTooltip:AddLine(Texts.tooltip.blocked(entry.blocked), 0.8, 0.8, 0.8)
        end
    end

    if entry.critical then
        GameTooltip:AddLine(Texts.tooltip.critical, 1, 0.82, 0)
    end

    local maxHealth = entry.healthMax or 0
    if maxHealth > 0 then
        local health = math.max(0, math.min(entry.health or 0, maxHealth))
        GameTooltip:AddLine(Texts.tooltip.healthAfter(health, maxHealth,
            math.floor(health / maxHealth * 100 + 0.5)), 0.6, 0.8, 1)
    end

    if entry.secondsBefore then
        GameTooltip:AddLine(Texts.labels.secondsBefore(entry.secondsBefore), 0.6, 0.6, 0.6)
    end

    GameTooltip:AddLine(Texts.tooltip.healthNote, 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end


local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:EnableMouse(true)

    -- Alternating dark strips: the panel art behind the rows is light in places, and flat text
    -- on top of it is what made the first version hard to read.
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(row)
    background:SetTexture(0, 0, 0, (index % 2 == 0) and 0.35 or 0.55)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetTexture(1, 1, 1, 0.10)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local iconBorder = row:CreateTexture(nil, "BORDER")
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    iconBorder:SetTexture(0, 0, 0, 1)

    local amount = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    amount:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    amount:SetWidth(NUMBER_COLUMN)
    amount:SetJustifyH("RIGHT")
    StyleFont(amount, 14, 1, 1, 1)
    row.amount = amount

    local health = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    health:SetPoint("TOPRIGHT", amount, "BOTTOMRIGHT", 0, -2)
    health:SetWidth(NUMBER_COLUMN)
    health:SetJustifyH("RIGHT")
    StyleFont(health, 10, 0.65, 0.78, 0.92)
    row.health = health

    local nameWidth = ROW_WIDTH - 4 - ICON_SIZE - ICON_GAP - NUMBER_COLUMN - 8

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", ICON_GAP, -1)
    name:SetWidth(nameWidth)
    name:SetHeight(14)
    name:SetJustifyH("LEFT")
    StyleFont(name, 12, 1, 1, 1)
    row.name = name

    local source = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    source:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    source:SetWidth(nameWidth)
    source:SetHeight(12)
    source:SetJustifyH("LEFT")
    StyleFont(source, 10, 0.72, 0.72, 0.72)
    row.source = source

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:Hide()

    return row
end


local function CreateRecapFrame()
    if recapFrame then return recapFrame end

    local frame = CreateFrame("Frame", "ProjectEbonholdDeathRecapFrame", UIParent)
    frame:SetSize(FRAME_WIDTH, HEADER_HEIGHT + FOOTER_HEIGHT + VISIBLE_ROWS * ROW_HEIGHT)
    frame:SetPoint("CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local dynamicBg = utils.CreateDeathFrameBackground(frame, FRAME_WIDTH, frame:GetHeight())
    dynamicBg:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.dynamicBackground = dynamicBg

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -50)
    title:SetText(Texts.frame.title)
    title:SetTextColor(1, 0.2, 0.2)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(1, -1)
    frame.title = title

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
    subtitle:SetWidth(FRAME_WIDTH - 50)
    subtitle:SetJustifyH("CENTER")
    StyleFont(subtitle, 11, 1, 1, 1)
    frame.subtitle = subtitle

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -32)
    closeButton:SetScript("OnClick", function()
        panelRequested = false
        frame:Hide()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", "ProjectEbonholdDeathRecapScrollFrame",
        frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_LEFT, -HEADER_HEIGHT)
    scrollFrame:SetSize(ROW_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
    frame.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(ROW_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild

    -- Set explicitly rather than relying on the template: one row per wheel click reads better
    -- than the template's half-page jump on a list this short.
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local scrollBar = _G["ProjectEbonholdDeathRecapScrollFrameScrollBar"]
        if not scrollBar then return end
        scrollBar:SetValue(scrollBar:GetValue() - delta * ROW_HEIGHT)
    end)

    frame.rows = {}
    for i = 1, MAX_EVENTS do
        frame.rows[i] = CreateRow(scrollChild, i)
    end

    frame:Hide()
    recapFrame = frame
    return frame
end


-- Sits above the death frame so it never covers the resurrection buttons.
local function AnchorFrame(frame)
    frame:ClearAllPoints()

    local deathFrame = _G["ProjectEbonholdDeathFrame"]
    if deathFrame and deathFrame:IsVisible() then
        frame:SetPoint("BOTTOM", deathFrame, "TOP", 0, 8)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end


local function RenderRecap()
    local frame = CreateRecapFrame()
    local recap = lastRecap

    for _, row in ipairs(frame.rows) do
        row:Hide()
        row.entry = nil
    end

    local events = recap and recap.events or {}

    if #events == 0 then
        frame.subtitle:SetText(Texts.frame.empty)
    else
        local killingBlow
        for _, entry in ipairs(events) do
            if entry.kind ~= "heal" then
                killingBlow = entry
                break
            end
        end

        if killingBlow then
            frame.subtitle:SetText(Texts.frame.killedBy(
                killingBlow.sourceName or killingBlow.name or Texts.labels.unknownSource))
        else
            frame.subtitle:SetText(Texts.frame.killedByUnknown)
        end
    end

    local yOffset = 0
    for i, entry in ipairs(events) do
        local row = frame.rows[i]
        if not row then break end

        entry.secondsBefore = math.max(0, (recap.time or entry.time) - entry.time)

        row.entry = entry
        row.icon:SetTexture(entry.icon or MELEE_ICON)
        row.name:SetText(entry.name or Texts.labels.unknownSource)

        -- The short time sits on the source line; the full wording lives in the tooltip. Keeping
        -- it short is what stops this line colliding with the numbers column.
        local elapsed = "|cff9d9d9d" .. Texts.labels.secondsShort(entry.secondsBefore) .. "|r"
        if entry.isEnvironmental then
            row.source:SetText(elapsed)
        else
            row.source:SetText(elapsed .. "  " .. (entry.sourceName or Texts.labels.unknownSource))
        end

        if entry.kind == "heal" then
            row.amount:SetText("+" .. FormatAmount(entry.amount))
            row.amount:SetTextColor(0.35, 1, 0.35)
        elseif entry.kind == "instakill" then
            row.amount:SetText(Texts.labels.instakill)
            row.amount:SetTextColor(1, 0.3, 0.3)
        else
            row.amount:SetText("-" .. FormatAmount(entry.amount))
            row.amount:SetTextColor(GetSchoolColor(entry.school))
        end

        local maxHealth = entry.healthMax or 0
        if maxHealth > 0 then
            local health = math.max(0, math.min(entry.health or 0, maxHealth))
            -- Both halves share the pool's formatting so the pair never reads as "3200 / 10.0k".
            local abbreviate = maxHealth >= ABBREVIATE_ABOVE
            row.health:SetText(Texts.labels.hpLeft(FormatAmount(health, abbreviate),
                FormatAmount(maxHealth, abbreviate)))
        else
            row.health:SetText("")
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollChild, "TOPLEFT", 0, yOffset)
        row:Show()
        yOffset = yOffset - ROW_HEIGHT
    end

    local rowCount = math.max(1, #events)
    frame.scrollChild:SetHeight(rowCount * ROW_HEIGHT)
    frame.scrollFrame:SetVerticalScroll(0)

    local visibleRows = math.min(rowCount, VISIBLE_ROWS)
    frame.scrollFrame:SetHeight(visibleRows * ROW_HEIGHT)

    -- The template only hides the bar on a scroll-range change, which does not fire when the
    -- list shrinks to fit, so drive it from the row count instead.
    local scrollBar = _G["ProjectEbonholdDeathRecapScrollFrameScrollBar"]
    if scrollBar then
        if rowCount > VISIBLE_ROWS then scrollBar:Show() else scrollBar:Hide() end
    end

    local height = HEADER_HEIGHT + FOOTER_HEIGHT + visibleRows * ROW_HEIGHT
    frame:SetHeight(height)
    if frame.dynamicBackground then
        frame.dynamicBackground:Resize(FRAME_WIDTH, height)
    end
end


ProjectEbonhold.DeathRecap = ProjectEbonhold.DeathRecap or {}


-- Freezes the rolling buffer into the recap shown on the death screen. UNIT_DIED and PLAYER_DEAD
-- both call this because their order is not guaranteed; the later one refreshes rather than being
-- dropped, so a killing blow logged after PLAYER_DEAD still lands.
function ProjectEbonhold.DeathRecap.Capture()
    local now = GetTime()
    lastRecap = { time = now, events = CollectEvents(now) }
    lastSnapshotTime = now

    if recapFrame and recapFrame:IsVisible() then
        RenderRecap()
        return
    end

    -- A recap captured after the death frame is already up needs the frame redrawn, otherwise
    -- its recap button was skipped while there was nothing to show.
    if ProjectEbonhold.DeathFrame and ProjectEbonhold.DeathFrame.Refresh then
        ProjectEbonhold.DeathFrame.Refresh()
    end
end


function ProjectEbonhold.DeathRecap.HasRecap()
    return lastRecap ~= nil and #lastRecap.events > 0
end


function ProjectEbonhold.DeathRecap.Show()
    local frame = CreateRecapFrame()
    RenderRecap()
    AnchorFrame(frame)
    frame:Show()
end


function ProjectEbonhold.DeathRecap.Hide()
    if recapFrame then recapFrame:Hide() end
end


-- Called by the death frame's OnShow. The panel is hidden by default and only comes back here
-- if the player already opened it, so the popups that hide and re-show the death frame do not
-- lose it mid-flow.
function ProjectEbonhold.DeathRecap.ShowForDeathFrame()
    if not panelRequested then return end
    if not ProjectEbonhold.DeathRecap.HasRecap() then return end
    ProjectEbonhold.DeathRecap.Show()
end


function ProjectEbonhold.DeathRecap.Toggle()
    if recapFrame and recapFrame:IsVisible() then
        panelRequested = false
        recapFrame:Hide()
        return
    end

    if not ProjectEbonhold.DeathRecap.HasRecap() then
        DEFAULT_CHAT_FRAME:AddMessage(Texts.slash.noRecap)
        return
    end

    panelRequested = true
    ProjectEbonhold.DeathRecap.Show()
end


local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("PLAYER_UNGHOST")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if playerGUID then HandleCombatLog(...) end
    elseif event == "PLAYER_DEAD" then
        -- UNIT_DIED normally arrives first and has already captured; only take a second
        -- snapshot if it did not, so a stale recap is never shown for a fresh death.
        if GetTime() - lastSnapshotTime > 3 then
            ProjectEbonhold.DeathRecap.Capture()
        end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        panelRequested = false
        ProjectEbonhold.DeathRecap.Hide()
    elseif event == "PLAYER_ENTERING_WORLD" then
        playerGUID = UnitGUID("player")
    end
end)


SLASH_PROJECTEBONHOLDDEATHRECAP1 = "/deathrecap"
SlashCmdList["PROJECTEBONHOLDDEATHRECAP"] = function()
    ProjectEbonhold.DeathRecap.Toggle()
end
