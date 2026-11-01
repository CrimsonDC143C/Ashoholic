-- trials_ui.lua -- The Trials: the arena HUD, the result card, the standings.
--
-- Three frames, all driven by trials_service.lua events:
--   HUD      top-centre while in the arena. Trial of the Champion: countdown (prep or run), damage,
--            mistake pips. Trial of the Crusader: run time, wave being fought, waves cleared,
--            living players / team size, and the "you are down" state. Ticks locally from the
--            last server state.
--   Result   centre card once an attempt ends: score, rank, top %, personal best; Retry / Leave.
--   Board    the season's standings (Herald Beluus at the Argent Tournament): Trial tabs, season
--            buttons, a class selector for the per-class Trial of the Champion board, a scrolled
--            list of class-coloured score bars and the season reward in the footer.

local addonName, addon = ...
local Trials = ProjectEbonhold.Trials

-- The stock class icon sheet; CLASS_ICON_TCOORDS from FrameXML when present, these otherwise.
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_TCOORDS = {
    WARRIOR     = { 0, 0.25, 0, 0.25 },
    MAGE        = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE       = { 0.49609375, 0.7421875, 0, 0.25 },
    DRUID       = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER      = { 0, 0.25, 0.25, 0.5 },
    SHAMAN      = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST      = { 0.49609375, 0.7421875, 0.25, 0.5 },
    WARLOCK     = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN     = { 0, 0.25, 0.5, 0.75 },
    DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 },
}

local function ClassColor(classId)
    local c = RAID_CLASS_COLORS[Trials.CLASS_TOKEN[classId] or ""]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

local function ClassText(classId, text)
    local r, g, b = ClassColor(classId)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text or "")
end

-- The Echo Journal's dressing: the dark dialog parchment, the 32 px dialog border and the
-- banner header carrying the title (echo_journal.lua).
local function Backdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        tile = true, tileSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
end

local function Header(frame, text)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    -- Stretched to the frame: the stock banner is narrow and a long title spills past it.
    tex:SetSize(frame:GetWidth() - 16, 64)
    tex:SetPoint("TOP", frame, "TOP", 0, 12)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOP", tex, "TOP", 0, -14)
    fs:SetText(text or "")
    return fs
end

local function Text(parent, font, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font or "Fonts\\FRIZQT__.TTF", size or 12, flags or "")
    fs:SetShadowOffset(1, -1)
    return fs
end

local function Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 90, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function TeamText(teamSize)
    teamSize = tonumber(teamSize) or 0
    if teamSize <= 1 then return "Solo" end
    return "Team of " .. teamSize
end

-- ======================================================================= HUD

local hud = CreateFrame("Frame", "ProjectEbonholdTrialHUD", UIParent)
hud:SetSize(320, 150)
hud:SetPoint("TOP", UIParent, "TOP", 0, -40)
hud:SetFrameStrata("MEDIUM")
-- No backdrop: the countdown floats over the arena as plain outlined text.
hud:Hide()

hud.title = Text(hud, nil, 12, "OUTLINE")
hud.title:SetPoint("TOP", hud, "TOP", 0, -8)
hud.title:SetTextColor(0.95, 0.75, 0.40)

hud.clock = Text(hud, "Fonts\\MORPHEUS.TTF", 30, "OUTLINE")
hud.clock:SetPoint("TOP", hud.title, "BOTTOM", 0, -2)

hud.sub = Text(hud, nil, 12)
hud.sub:SetPoint("TOP", hud.clock, "BOTTOM", 0, -2)
hud.sub:SetTextColor(0.85, 0.82, 0.78)

-- Trial of the Crusader: living players / team size.
hud.team = Text(hud, nil, 12)
hud.team:SetPoint("TOP", hud.sub, "BOTTOM", 0, -3)

-- Trial of the Crusader: this player is down until the next boss wave is cleared.
hud.down = Text(hud, nil, 15, "OUTLINE")
hud.down:SetPoint("TOP", hud.team, "BOTTOM", 0, -6)
hud.down:SetTextColor(1.0, 0.30, 0.25)
hud.down:SetText("You are down")
hud.down:Hide()

hud.downSub = Text(hud, nil, 12, "OUTLINE")
hud.downSub:SetPoint("TOP", hud.down, "BOTTOM", 0, -2)
hud.downSub:SetTextColor(1.0, 0.82, 0.70)
hud.downSub:Hide()

-- Mistake pips (Trial of the Champion): one per allowed error, lit red once spent.
hud.pips = {}
for i = 1, 5 do
    local pip = hud:CreateTexture(nil, "ARTWORK")
    pip:SetSize(12, 12)
    pip:SetTexture("Interface\\Buttons\\UI-RadioButton")
    pip:SetTexCoord(0.25, 0.5, 0, 1)
    pip:Hide()
    hud.pips[i] = pip
end

local function LayoutPips(count, used)
    local shown = math.min(count, #hud.pips)
    local width = shown * 14
    for i, pip in ipairs(hud.pips) do
        if i <= shown then
            pip:ClearAllPoints()
            pip:SetPoint("TOPLEFT", hud.sub, "BOTTOM", -width / 2 + (i - 1) * 14, -4)
            if i <= used then
                pip:SetVertexColor(1.0, 0.25, 0.20)
            else
                pip:SetVertexColor(0.35, 0.35, 0.35)
            end
            pip:Show()
        else
            pip:Hide()
        end
    end
end

local function ShowDowned(downed, wave)
    if downed then
        -- The next boss wave (every 5th): the one being fought when it is a boss wave.
        local nextBoss = math.max(5, math.ceil((wave or 0) / 5) * 5)
        hud.downSub:SetText("You come back when the next boss falls (wave " .. nextBoss .. ").")
        hud.down:Show()
        hud.downSub:Show()
    else
        hud.down:Hide()
        hud.downSub:Hide()
    end
end

local function RefreshChampionHUD(st)
    hud.team:SetText("")
    ShowDowned(false)
    local remaining = Trials.GetRemainingMs()
    if st.phase == Trials.PHASE.PREP then
        hud.clock:SetTextColor(0.55, 0.80, 1.0)
        hud.clock:SetText(Trials.FormatClock(remaining))
        hud.sub:SetText("Prepare yourself. The trial begins soon.")
        LayoutPips(0, 0)
    else
        local warn = remaining <= 10000
        hud.clock:SetTextColor(1.0, warn and 0.35 or 0.92, warn and 0.30 or 0.70)
        hud.clock:SetText(Trials.FormatClock(remaining))
        hud.sub:SetText("Damage: " .. Trials.FormatNumber(st.score))
        LayoutPips(st.maxErrors or 0, st.errors or 0)
    end
end

local function RefreshCrusaderHUD(st)
    LayoutPips(0, 0)
    local team = math.max(st.teamSize or 0, 1)
    if st.phase == Trials.PHASE.PREP then
        hud.clock:SetTextColor(0.55, 0.80, 1.0)
        hud.clock:SetText(Trials.FormatClock(Trials.GetRemainingMs()))
        if team > 1 then
            hud.sub:SetText("Your team of " .. team .. " stands ready. The trial begins soon.")
        else
            hud.sub:SetText("Prepare yourself. The trial begins soon.")
        end
        hud.team:SetText("")
        ShowDowned(false)
        return
    end

    if st.downed then
        hud.clock:SetTextColor(0.60, 0.60, 0.60)
    else
        hud.clock:SetTextColor(1.0, 0.92, 0.70)
    end
    hud.clock:SetText(Trials.FormatClock(Trials.GetElapsedMs()))

    local wave = st.wave or 0
    local start = st.startWave or 1
    local waveText
    if wave > 0 then
        waveText = "Wave " .. wave .. (wave % 5 == 0 and " |cffff8040(boss)|r" or "")
    elseif start > 1 then
        waveText = "Wave " .. start .. " approaches"
    else
        waveText = "The first wave approaches"
    end
    if start > 1 then
        -- A practice run from a checkpoint: not ranked.
        waveText = "|cff80c0ffPractice|r  " .. waveText
    end
    hud.sub:SetText(waveText .. "   |cffaaaaaaCleared: " .. (st.wavesCleared or 0) .. "|r")

    local alive = math.max(st.alive or 0, 0)
    if alive < team then
        hud.team:SetTextColor(1.0, 0.65, 0.30)
    else
        hud.team:SetTextColor(0.55, 0.95, 0.55)
    end
    hud.team:SetText("Standing: " .. alive .. " / " .. team)

    ShowDowned(st.downed, wave)
end

local function RefreshHUD()
    local st = Trials.state
    if not st or st.phase < Trials.PHASE.PREP or st.phase == Trials.PHASE.RESULT then
        hud:Hide()
        return
    end
    hud:Show()
    hud.title:SetText(Trials.NAMES[st.trial] or "Trial")
    if st.trial == Trials.TYPE.CRUSADER then
        RefreshCrusaderHUD(st)
    else
        RefreshChampionHUD(st)
    end
end

hud:SetScript("OnUpdate", function(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc < 0.1 then return end
    self.acc = 0
    RefreshHUD()
end)

-- ==================================================================== result

local card = CreateFrame("Frame", "ProjectEbonholdTrialResult", UIParent)
card:SetSize(360, 230)
card:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
card:SetFrameStrata("DIALOG")
card:SetMovable(true)
card:EnableMouse(true)
card:RegisterForDrag("LeftButton")
card:SetScript("OnDragStart", card.StartMoving)
card:SetScript("OnDragStop", card.StopMovingOrSizing)
Backdrop(card)
card:Hide()

card.title = Header(card, "Trial")

card.reason = Text(card, nil, 11)
card.reason:SetPoint("TOP", card, "TOP", 0, -34)
card.reason:SetTextColor(0.70, 0.66, 0.60)

card.score = Text(card, "Fonts\\MORPHEUS.TTF", 28, "OUTLINE")
card.score:SetPoint("TOP", card.reason, "BOTTOM", 0, -6)

-- Champion: the class standings the rank is in. Crusader: run time and team size.
card.detail = Text(card, nil, 12)
card.detail:SetPoint("TOP", card.score, "BOTTOM", 0, -4)
card.detail:SetTextColor(0.85, 0.82, 0.78)

card.rank = Text(card, nil, 13)
card.rank:SetPoint("TOP", card.detail, "BOTTOM", 0, -6)
card.rank:SetTextColor(0.90, 0.88, 0.84)

card.pb = Text(card, nil, 12)
card.pb:SetPoint("TOP", card.rank, "BOTTOM", 0, -4)

card.retry = Button(card, "Try again", 110, function() card:Hide(); Trials.Retry() end)
card.retry:SetPoint("BOTTOMLEFT", card, "BOTTOM", -118, 18)
card.leave = Button(card, "Leave the arena", 120, function() card:Hide(); Trials.Leave() end)
card.leave:SetPoint("BOTTOMLEFT", card, "BOTTOM", 4, 18)

local function ReasonText(trial, reason, teamSize)
    if reason == Trials.REASON.DEATH then
        if trial == Trials.TYPE.CRUSADER and (teamSize or 0) > 1 then
            return "Your whole team fell."
        end
        return "You fell."
    elseif reason == Trials.REASON.ABANDON then
        return "Attempt abandoned."
    end
    return "Time is up."
end

-- Crusader headline + detail from a score (waves cleared, run time) and a team size.
local function CrusaderLines(score, wavesCleared, teamSize)
    local waves, ds = Trials.DecodeCrusader(score)
    if wavesCleared and wavesCleared > waves then waves = wavesCleared end
    local detail = TeamText(teamSize)
    if waves > 0 then
        detail = "Time " .. Trials.FormatTenths(ds) .. "  -  " .. detail
    end
    return Trials.FormatWaves(waves) .. " cleared", detail
end

-- Crusader practice run (from a checkpoint, not ranked): the waves it covered.
local function PracticeLines(startWave, wavesCleared, teamSize)
    local headline
    if (wavesCleared or 0) >= startWave then
        headline = "Waves " .. startWave .. " to " .. wavesCleared .. " cleared"
    else
        headline = "Wave " .. startWave .. " not cleared"
    end
    return headline, "Practice  -  " .. TeamText(teamSize)
end

local function ShowResult(r)
    if not r or r.trial == 0 then return end
    card.title:SetText(Trials.NAMES[r.trial] or "Trial")
    card.reason:SetText("Complete. " .. ReasonText(r.trial, r.reason, r.teamSize))
    card.score:SetTextColor(1.0, 0.92, 0.70)

    if r.trial == Trials.TYPE.CRUSADER and (r.startWave or 1) > 1 then
        local headline, detail = PracticeLines(r.startWave, r.wavesCleared, r.teamSize)
        card.score:SetText(headline)
        card.detail:SetText(detail)
    elseif r.trial == Trials.TYPE.CRUSADER then
        local headline, detail = CrusaderLines(r.score, r.wavesCleared, r.teamSize)
        card.score:SetText(headline)
        card.detail:SetText(detail)
    else
        card.score:SetText(Trials.FormatNumber(r.score))
        local className = Trials.CLASS_NAME[r.classId]
        card.detail:SetText(className and ClassText(r.classId, className .. " standings") or "")
    end

    if r.rank > 0 and r.total > 0 then
        card.rank:SetText(string.format("Rank #%d of %d  -  Top %.2f%%", r.rank, r.total, r.topPct))
    elseif (r.startWave or 1) > 1 then
        card.rank:SetText("Practice run - not ranked")
    else
        card.rank:SetText("")
    end

    if r.personalBest then
        card.pb:SetTextColor(0.40, 1.0, 0.45)
        card.pb:SetText("New personal best!")
        PlaySound("LEVELUPSOUND")
    elseif r.previousBest > 0 then
        card.pb:SetTextColor(0.70, 0.66, 0.60)
        card.pb:SetText("Personal best: " .. Trials.FormatScore(r.trial, r.previousBest))
    else
        card.pb:SetText("")
    end
    card:Show()
end

-- ===================================================================== board
--
-- The look approved on 2026-10-17 (artifact MF5VVZjLqeKYdn4SapQspL): the dark dialog panel, the
-- Trial tabs on its top edge, a gold title, two small season buttons, the ten class icons (Trial
-- of the Champion), then one row per player - rank, class icon, name, a bar in the class colour
-- (score / best of the board; Crusader: waves / best waves), the value and a grey detail - in a
-- list scrolled by the wheel or a thin bar, 12 rows in view. The player's row is gold-edged; when
-- the server adds it below the top, a "N more" separator comes first. Footer: the player's rank and
-- the top 1% season reward.

local ARIALN = "Fonts\\ARIALN.TTF"
local BOARD_W = 420
local LIST_ROWS = 12
local ROW_H = 26
local LIST_W = BOARD_W - 44

-- Season 1 rewards of the top 1% (docs/tournament/CONTRACT.md section 3, not on the wire):
-- title 229 / 230 (shown as the Unrivaled / the Undying), one Argent Laurel by mail, traded at Lady Isolde for the season mount.
local REWARD = {
    [1] = { title = "the Unrivaled", scope = "each class board" },
    [3] = { title = "the Undying", scope = "the board" },
    laurel = 690000, laurelName = "Argent Laurel",
    mount = 681200, mountName = "Ashen Charger", mountFull = "Reins of the Ashen Charger",
}

local TOOLTIP_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local SMALL_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = TOOLTIP_EDGE,
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local EDGE_BACKDROP = { edgeFile = TOOLTIP_EDGE, edgeSize = 12 }

-- 59903732870 -> "59.9 B", 4287020 -> "4.29 M".
local function ShortNumber(n)
    n = tonumber(n) or 0
    for _, u in ipairs({ { 1e9, " B" }, { 1e6, " M" }, { 1e3, " K" } }) do
        if n >= u[1] then
            local x = n / u[1]
            local f = (x >= 100 and "%.0f") or (x >= 10 and "%.1f") or "%.2f"
            return string.format(f, x) .. u[2]
        end
    end
    return tostring(math.floor(n))
end

local function Percent(rank, total)
    if not total or total <= 0 then return "0" end
    return (string.format("%.1f", 100 * rank / total):gsub("%.0$", ""))
end

local function TopCut(total)
    return math.max(1, math.ceil((total or 0) / 100))
end

local function SmallTeam(teamSize)
    teamSize = tonumber(teamSize) or 0
    return teamSize <= 1 and "solo" or ("team of " .. teamSize)
end

local function SetClassIcon(tex, classId)
    local token = Trials.CLASS_TOKEN[classId]
    local tc = token and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]) or CLASS_TCOORDS[token])
    if tc then
        tex:SetTexture(CLASS_ICONS)
        tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- An icon with a 1 px black frame, as the mock's class and reward icons.
local function FramedIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.frame = f:CreateTexture(nil, "BACKGROUND")
    f.frame:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.frame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.frame:SetTexture(0, 0, 0, 1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    return f
end

local board = CreateFrame("Frame", "ProjectEbonholdTrialBoard", UIParent)
board:SetSize(BOARD_W, 474)
board:SetPoint("TOP", UIParent, "TOP", 0, -110)
board:SetFrameStrata("DIALOG")
board:SetMovable(true)
board:SetClampedToScreen(true)
board:EnableMouse(true)
board:RegisterForDrag("LeftButton")
board:SetScript("OnDragStart", board.StartMoving)
board:SetScript("OnDragStop", board.StopMovingOrSizing)
Backdrop(board)
board:Hide()
tinsert(UISpecialFrames, "ProjectEbonholdTrialBoard")

-- A warm shade at the top of the panel, fading out downwards.
board.shade = board:CreateTexture(nil, "BORDER")
board.shade:SetPoint("TOPLEFT", board, "TOPLEFT", 11, -12)
board.shade:SetPoint("TOPRIGHT", board, "TOPRIGHT", -12, -12)
board.shade:SetHeight(170)
board.shade:SetTexture(0.16, 0.125, 0.08, 0.35)
board.shade:SetGradientAlpha("VERTICAL", 0.16, 0.125, 0.08, 0, 0.16, 0.125, 0.08, 0.35)

board.close = CreateFrame("Button", nil, board, "UIPanelCloseButton")
board.close:SetPoint("TOPRIGHT", board, "TOPRIGHT", -4, -4)

board.title = Text(board, nil, 15)
board.title:SetPoint("TOP", board, "TOP", 0, -22)
board.title:SetTextColor(1, 0.82, 0)

-- The Champion board remembers the class last viewed, so switching tabs comes back to it.
board.championClass = nil

-- Trial tabs on the top edge: the stock options-frame tabs, driven by PanelTemplates.
board.tabs = {}
do
    local TABS = {
        { trial = Trials.TYPE.CHAMPION, label = "Champion" },
        { trial = Trials.TYPE.CRUSADER, label = "Crusader" },
    }
    for i, tab in ipairs(TABS) do
        local t = CreateFrame("Button", "ProjectEbonholdTrialBoardTab" .. i, board, "OptionsFrameTabButtonTemplate")
        t:SetID(i)
        t:SetText(tab.label)
        PanelTemplates_TabResize(t, 0)
        if i == 1 then
            t:SetPoint("BOTTOMLEFT", board, "TOPLEFT", 18, -8)
        else
            t:SetPoint("LEFT", board.tabs[i - 1], "RIGHT", -16, 0)
        end
        t.trial = tab.trial
        t:SetScript("OnClick", function(self)
            PlaySound("igCharacterInfoTab")
            if self.trial == Trials.TYPE.CHAMPION then
                Trials.RequestBoard(self.trial, board.championClass)
            else
                Trials.RequestBoard(self.trial)
            end
        end)
        board.tabs[i] = t
    end
    PanelTemplates_SetNumTabs(board, #TABS)
end

-- Season buttons: tooltip-edged, the chosen one edged gold.
local function SmallButton(label, width)
    local b = CreateFrame("Button", nil, board)
    b:SetSize(width, 22)
    b:SetBackdrop(SMALL_BACKDROP)
    b:SetBackdropColor(0, 0, 0, 0.8)
    b.text = Text(b, nil, 11)
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text:SetText(label)
    return b
end

-- Only the current season exists on the wire (no season history request): "Season N" is always
-- the one shown, "All seasons" stays greyed with a tooltip saying so.
board.seasonBtn = SmallButton("Season 1", 84)
board.seasonBtn:SetPoint("TOPRIGHT", board, "TOP", -3, -42)
board.seasonBtn:SetBackdropBorderColor(1, 0.82, 0)
board.seasonBtn.text:SetTextColor(1, 0.82, 0)
board.seasonBtn:SetScript("OnEnter", function(self)
    local b = board.data
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText((b and b.seasonName ~= "" and b.seasonName) or self.text:GetText(), 1, 0.82, 0)
    GameTooltip:AddLine("The season being played.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
board.seasonBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

board.allBtn = SmallButton("All seasons", 92)
board.allBtn:SetPoint("TOPLEFT", board, "TOP", 3, -42)
board.allBtn:SetBackdropBorderColor(0.45, 0.45, 0.45)
board.allBtn.text:SetTextColor(0.5, 0.5, 0.5)
board.allBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("All seasons", 1, 0.82, 0)
    GameTooltip:AddLine("Best attempt of every season together.", 1, 1, 1, true)
    GameTooltip:AddLine("Only the current season so far.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
board.allBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Class selector (Trial of the Champion): the ten classes, the chosen one edged gold.
board.classButtons = {}
do
    local STEP = 35
    local left = (BOARD_W - (#Trials.CLASS_ORDER * STEP - 5)) / 2
    for i, classId in ipairs(Trials.CLASS_ORDER) do
        local b = CreateFrame("Button", nil, board)
        b:SetSize(30, 30)
        b:SetPoint("TOPLEFT", board, "TOPLEFT", left + (i - 1) * STEP, -74)
        b:SetBackdrop({ edgeFile = TOOLTIP_EDGE, edgeSize = 10 })
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(22, 22)
        b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
        SetClassIcon(b.icon, classId)
        b.frame = b:CreateTexture(nil, "BORDER")
        b.frame:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -1, 1)
        b.frame:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 1, -1)
        b.frame:SetTexture(0, 0, 0, 1)
        b.classId = classId
        b:SetScript("OnClick", function(self)
            PlaySound("igMainMenuOptionCheckBoxOn")
            Trials.RequestBoard(Trials.TYPE.CHAMPION, self.classId)
        end)
        b:SetScript("OnEnter", function(self)
            self.icon:SetDesaturated(false)
            self.icon:SetVertexColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(Trials.CLASS_NAME[self.classId] or "", ClassColor(self.classId))
            local d = board.data
            if d and d.classFilter == self.classId then
                GameTooltip:AddLine(d.total > 0 and (d.total .. " ranked") or "No attempt recorded yet.", 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("Click to see its standings.", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            board.PaintClassButton(self)
        end)
        b:Hide()
        board.classButtons[i] = b
    end
end

function board.PaintClassButton(b)
    local selected = board.data and board.data.classFilter == b.classId
    if selected then
        b:SetBackdropBorderColor(1, 0.82, 0, 1)
        b.icon:SetDesaturated(false)
        b.icon:SetVertexColor(1, 1, 1)
    else
        b:SetBackdropBorderColor(1, 0.82, 0, 0)
        b.icon:SetDesaturated(true)
        b.icon:SetVertexColor(0.8, 0.8, 0.8)
    end
end

-- Section line: "PRIEST ------------ 13 ranked".
board.sect = Text(board, nil, 10)
board.sect:SetTextColor(1, 0.82, 0)
board.sectInfo = Text(board, ARIALN, 11)
board.sectInfo:SetTextColor(0.56, 0.56, 0.56)
board.sectLine = board:CreateTexture(nil, "ARTWORK")
board.sectLine:SetHeight(1)
board.sectLine:SetTexture(1, 0.82, 0, 0.4)
board.sectLine:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.4, 1, 0.82, 0, 0)
board.sectLine:SetPoint("LEFT", board.sect, "RIGHT", 8, 0)
board.sectLine:SetPoint("RIGHT", board.sectInfo, "LEFT", -8, 0)

-- The list: LIST_ROWS row frames over a virtual list of entries (rows and separators).
board.list = CreateFrame("Frame", nil, board)
board.list:SetSize(LIST_W, LIST_ROWS * ROW_H)
board.entries = {}
board.offset = 0

board.empty = Text(board.list, nil, 12)
board.empty:SetPoint("TOP", board.list, "TOP", 0, -40)
board.empty:SetTextColor(0.65, 0.61, 0.53)

board.scroll = CreateFrame("Slider", nil, board.list)
board.scroll:SetOrientation("VERTICAL")
board.scroll:SetWidth(6)
board.scroll:SetPoint("TOPRIGHT", board.list, "TOPRIGHT", 0, 0)
board.scroll:SetPoint("BOTTOMRIGHT", board.list, "BOTTOMRIGHT", 0, 0)
board.scroll.track = board.scroll:CreateTexture(nil, "BACKGROUND")
board.scroll.track:SetAllPoints(board.scroll)
board.scroll.track:SetTexture(0, 0, 0, 0.4)
board.scroll:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
board.scroll:GetThumbTexture():SetVertexColor(0.42, 0.35, 0.21)
board.scroll:GetThumbTexture():SetSize(6, 36)
board.scroll:SetValueStep(1)
board.scroll:SetMinMaxValues(0, 0)
board.scroll:SetValue(0)
board.scroll:Hide()

local function OnWheel(_, delta)
    if not board.scroll:IsShown() then return end
    board.scroll:SetValue(board.scroll:GetValue() - delta)
end
board.list:EnableMouseWheel(true)
board.list:SetScript("OnMouseWheel", OnWheel)

-- Row tooltip: the exact score.
local function RowOnEnter(self)
    self.hover:Show()
    local entry, b = self.entry, board.data
    if not entry or entry.sep or not b then return end
    local e = entry.row
    local crusader = b.trial == Trials.TYPE.CRUSADER
    local className = Trials.CLASS_NAME[e.class] or "Unknown"
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name .. (entry.mine and " (you)" or ""), ClassColor(e.class))
    GameTooltip:AddLine(crusader and (className .. ", team leader") or className, 0.7, 0.7, 0.7)
    GameTooltip:AddDoubleLine("Rank", string.format("#%d of %d  (top %s%%)", e.rank, b.total, Percent(e.rank, b.total)),
        0.7, 0.7, 0.7, 1, 1, 1)
    if crusader then
        local waves, ds = Trials.DecodeCrusader(e.score)
        GameTooltip:AddDoubleLine("Waves cleared", tostring(waves), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Time", Trials.FormatTenths(ds), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Team", SmallTeam(e.teamSize), 0.7, 0.7, 0.7, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Damage", Trials.FormatNumber(e.score), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    local reward = REWARD[b.trial]
    if reward and e.rank <= TopCut(b.total) then
        GameTooltip:AddLine("Top 1%: " .. reward.title .. " when the season ends.", 0.12, 1, 0)
    end
    GameTooltip:Show()
end

local function RowOnLeave(self)
    self.hover:Hide()
    GameTooltip:Hide()
end

board.rowFrames = {}
for i = 1, LIST_ROWS do
    local row = CreateFrame("Frame", nil, board.list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", board.list, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", board.list, "RIGHT", -10, 0)

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints(row)
    row.stripe:SetTexture(1, 1, 1, 0.025)
    row.mineBg = row:CreateTexture(nil, "BACKGROUND")
    row.mineBg:SetAllPoints(row)
    row.mineBg:SetTexture(1, 0.78, 0.16, 0.07)
    row.mineEdge = CreateFrame("Frame", nil, row)
    row.mineEdge:SetAllPoints(row)
    row.mineEdge:SetBackdrop(EDGE_BACKDROP)
    row.mineEdge:SetBackdropBorderColor(1, 0.82, 0)
    row.hover = row:CreateTexture(nil, "ARTWORK")
    row.hover:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    row.hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
    row.hover:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    row.hover:SetBlendMode("ADD")
    row.hover:SetAlpha(0.35)
    row.hover:Hide()

    row.rank = Text(row, ARIALN, 12)
    row.rank:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.rank:SetWidth(26)
    row.rank:SetJustifyH("RIGHT")
    row.icon = FramedIcon(row, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 36, 0)
    row.name = Text(row, nil, 11)
    row.name:SetPoint("LEFT", row, "LEFT", 62, 0)
    row.name:SetHeight(14)
    row.name:SetJustifyH("LEFT")
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetHeight(8)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetMinMaxValues(0, 1)
    row.bar.track = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.track:SetPoint("TOPLEFT", row.bar, "TOPLEFT", -1, 1)
    row.bar.track:SetPoint("BOTTOMRIGHT", row.bar, "BOTTOMRIGHT", 1, -1)
    row.bar.track:SetTexture(0, 0, 0, 0.65)
    row.val = Text(row, ARIALN, 13)
    row.val:SetJustifyH("RIGHT")
    row.val:SetTextColor(1, 1, 1)
    row.sub = Text(row, ARIALN, 11)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.sub:SetJustifyH("RIGHT")
    row.sub:SetTextColor(0.56, 0.56, 0.56)

    -- Separator: "---- N more ----".
    row.sepText = Text(row, nil, 10)
    row.sepText:SetPoint("CENTER", row, "CENTER", 0, 0)
    row.sepText:SetTextColor(0.56, 0.56, 0.56)
    row.sepL = row:CreateTexture(nil, "ARTWORK")
    row.sepL:SetHeight(1)
    row.sepL:SetTexture(1, 0.82, 0, 0.22)
    row.sepL:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.sepL:SetPoint("RIGHT", row.sepText, "LEFT", -8, 0)
    row.sepR = row:CreateTexture(nil, "ARTWORK")
    row.sepR:SetHeight(1)
    row.sepR:SetTexture(1, 0.82, 0, 0.22)
    row.sepR:SetPoint("LEFT", row.sepText, "RIGHT", 8, 0)
    row.sepR:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", OnWheel)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:Hide()
    board.rowFrames[i] = row
end

-- Column widths per Trial (the mock's): name, value, detail; the bar takes what is left.
local function LayoutColumns(crusader)
    local nameW = crusader and 74 or 82
    local valW = crusader and 54 or 50
    local subW = crusader and 86 or 50
    for _, row in ipairs(board.rowFrames) do
        row.name:SetWidth(nameW)
        row.sub:SetWidth(subW)
        row.val:SetWidth(valW)
        row.val:ClearAllPoints()
        row.val:SetPoint("RIGHT", row, "RIGHT", -(8 + subW + 6), 0)
        row.bar:ClearAllPoints()
        row.bar:SetPoint("LEFT", row, "LEFT", 62 + nameW + 6, 0)
        row.bar:SetPoint("RIGHT", row, "RIGHT", -(8 + subW + 6 + valW + 6), 0)
    end
end

local function SetRowParts(row, show)
    local f = show and "Show" or "Hide"
    row.rank[f](row.rank); row.icon[f](row.icon); row.name[f](row.name); row.bar[f](row.bar)
    row.val[f](row.val); row.sub[f](row.sub)
    local s = show and "Hide" or "Show"
    row.sepText[s](row.sepText); row.sepL[s](row.sepL); row.sepR[s](row.sepR)
end

local function RenderList()
    local b = board.data
    if not b then return end
    local crusader = b.trial == Trials.TYPE.CRUSADER
    local cut = TopCut(b.total)
    for i, row in ipairs(board.rowFrames) do
        local index = board.offset + i
        local entry = board.entries[index]
        row.entry = entry
        if not entry then
            row:Hide()
        elseif entry.sep then
            SetRowParts(row, false)
            row.sepText:SetText(entry.count .. " more")
            row.stripe:Hide(); row.mineBg:Hide(); row.mineEdge:Hide()
            row:Show()
        else
            local e = entry.row
            SetRowParts(row, true)
            row.rank:SetText("#" .. e.rank)
            if e.rank <= cut then
                row.rank:SetTextColor(1, 0.82, 0)
            else
                row.rank:SetTextColor(0.56, 0.56, 0.56)
            end
            SetClassIcon(row.icon.icon, e.class)
            row.name:SetText(e.name)
            row.name:SetTextColor(ClassColor(e.class))
            local r, g, bl = ClassColor(e.class)
            row.bar:SetStatusBarColor(r, g, bl)
            if crusader then
                local waves, ds = Trials.DecodeCrusader(e.score)
                row.bar:SetValue(board.best > 0 and math.max(0.02, waves / board.best) or 0.02)
                row.val:SetText(Trials.FormatWaves(waves))
                row.sub:SetText(Trials.FormatTenths(ds) .. " · " .. SmallTeam(e.teamSize))
            else
                row.bar:SetValue(board.best > 0 and math.max(0.02, e.score / board.best) or 0.02)
                row.val:SetText(ShortNumber(e.score))
                row.sub:SetText("top " .. Percent(e.rank, b.total) .. "%")
            end
            if entry.mine then
                row.stripe:Hide(); row.mineBg:Show(); row.mineEdge:Show()
            else
                row.mineBg:Hide(); row.mineEdge:Hide()
                if index % 2 == 1 then row.stripe:Show() else row.stripe:Hide() end
            end
            row:Show()
        end
    end
end

board.scroll:SetScript("OnValueChanged", function(self, value)
    board.offset = math.floor((value or 0) + 0.5)
    RenderList()
end)

-- Footer: "You #34/57 · top 59.6%" ... "Top 1%: [title] the Unrivaled [laurel] » [mount] Ashen Charger".
board.footLine = board:CreateTexture(nil, "ARTWORK")
board.footLine:SetHeight(1)
board.footLine:SetTexture(1, 0.82, 0, 0.18)

board.you = Text(board, nil, 10)
board.you:SetTextColor(0.79, 0.76, 0.69)

local function RewardIcon(texture, onEnter)
    local f = FramedIcon(board, 16)
    f.icon:SetTexture(texture)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f:EnableMouse(true)
    f:SetScript("OnEnter", onEnter)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

-- The real item tooltip when the client has the item cached, a short text otherwise.
local function ItemTooltip(owner, itemId, name, line)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    if GetItemInfo(itemId) then
        GameTooltip:SetHyperlink("item:" .. itemId)
    else
        GameTooltip:SetText(name, 0.64, 0.21, 0.93)
    end
    GameTooltip:AddLine(line, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

board.mountText = Text(board, nil, 10)
board.mountText:SetTextColor(0.64, 0.21, 0.93)
board.mountText:SetText(REWARD.mountName)
board.mountIcon = RewardIcon("Interface\\Icons\\Ability_Mount_Charger", function(self)
    ItemTooltip(self, REWARD.mount, REWARD.mountFull, "The season mount, traded for one Argent Laurel.")
end)
board.arrow = Text(board, nil, 10)
board.arrow:SetTextColor(1, 0.82, 0)
board.arrow:SetText("»")
board.laurelIcon = RewardIcon("Interface\\Icons\\Achievement_Reputation_ArgentChampion", function(self)
    ItemTooltip(self, REWARD.laurel, REWARD.laurelName,
        "Mailed to each winner. Lady Isolde Brightlance trades it for the season mount.")
end)
board.titleText = Text(board, nil, 10)
board.titleText:SetTextColor(0.79, 0.76, 0.69)
board.titleIcon = RewardIcon("Interface\\Icons\\INV_Scroll_03", function(self)
    local reward = REWARD[board.data and board.data.trial or 1] or REWARD[1]
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Title: " .. (UnitName("player") or "") .. " " .. reward.title, 1, 0.82, 0)
    GameTooltip:AddLine("For the top 1% of " .. reward.scope .. " when the season ends.", 1, 1, 1, true)
    GameTooltip:Show()
end)
board.topLabel = Text(board, nil, 10)
board.topLabel:SetTextColor(1, 0.82, 0)
board.topLabel:SetText("Top 1%:")

-- Right-to-left chain, anchored once; only its vertical place moves (LayoutBoard).
board.mountIcon:SetPoint("RIGHT", board.mountText, "LEFT", -4, 0)
board.arrow:SetPoint("RIGHT", board.mountIcon, "LEFT", -4, 0)
board.laurelIcon:SetPoint("RIGHT", board.arrow, "LEFT", -4, 0)
board.titleText:SetPoint("RIGHT", board.laurelIcon, "LEFT", -5, 0)
board.titleIcon:SetPoint("RIGHT", board.titleText, "LEFT", -4, 0)
board.topLabel:SetPoint("RIGHT", board.titleIcon, "LEFT", -4, 0)

-- The footer is not shown (owner 2026-10-19: "remove everything at the bottom"); the board ends
-- under its list (LayoutBoard). Kept built so ShowBoard's texts need no guard.
for _, region in ipairs({ board.footLine, board.you, board.mountText, board.mountIcon, board.arrow,
    board.laurelIcon, board.titleText, board.titleIcon, board.topLabel }) do
    region:Hide()
end

-- Vertical layout: the Crusader board has no class row, so everything below moves up.
local function LayoutBoard(champion)
    local sectY = champion and -114 or -76
    local listY = sectY - 14
    local footY = listY - LIST_ROWS * ROW_H - 8
    board.sect:ClearAllPoints()
    board.sect:SetPoint("TOPLEFT", board, "TOPLEFT", 24, sectY)
    board.sectInfo:ClearAllPoints()
    board.sectInfo:SetPoint("TOPRIGHT", board, "TOPRIGHT", -24, sectY)
    board.list:ClearAllPoints()
    board.list:SetPoint("TOPLEFT", board, "TOPLEFT", 22, listY)
    board.footLine:ClearAllPoints()
    board.footLine:SetPoint("TOPLEFT", board, "TOPLEFT", 22, footY)
    board.footLine:SetPoint("TOPRIGHT", board, "TOPRIGHT", -22, footY)
    board.you:ClearAllPoints()
    board.you:SetPoint("LEFT", board, "TOPLEFT", 24, footY - 15)
    board.mountText:ClearAllPoints()
    board.mountText:SetPoint("RIGHT", board, "TOPRIGHT", -24, footY - 15)
    board:SetHeight(-footY + 14)
end

local function ShowBoard(b)
    if not b then return end
    board.data = b
    local champion = b.trial == Trials.TYPE.CHAMPION
    local crusader = b.trial == Trials.TYPE.CRUSADER
    local myClass = Trials.MyClassId()

    PanelTemplates_SetTab(board, crusader and 2 or 1)
    board.title:SetText(string.upper(Trials.NAMES[b.trial] or "Trial"))
    board.seasonBtn.text:SetText(b.season > 0 and ("Season " .. b.season) or "Season")
    if champion then board.championClass = b.classFilter end
    for _, cb in ipairs(board.classButtons) do
        if champion then board.PaintClassButton(cb); cb:Show() else cb:Hide() end
    end
    LayoutBoard(champion)
    LayoutColumns(crusader)

    if champion then
        board.sect:SetText(string.upper(Trials.CLASS_NAME[b.classFilter] or "Standings"))
        board.sectInfo:SetText(b.total .. " ranked")
    else
        board.sect:SetText("TEAMS")
        board.sectInfo:SetText(b.total .. " ranked · solo to five")
    end

    -- Entries: the rows, with a separator wherever ranks jump (the player's own row, sent after
    -- the top when he is outside it).
    local entries = board.entries
    wipe(entries)
    local me = UnitName("player")
    local prevRank, mineIndex, best = 0, nil, 0
    for _, e in ipairs(b.rows) do
        if prevRank > 0 and e.rank > prevRank + 1 then
            table.insert(entries, { sep = true, count = e.rank - prevRank - 1 })
        end
        local mine = (b.myRank > 0 and e.rank == b.myRank) or (b.myRank == 0 and e.name == me)
        table.insert(entries, { row = e, mine = mine })
        if mine then mineIndex = #entries end
        prevRank = e.rank
        local value = crusader and (Trials.DecodeCrusader(e.score)) or e.score
        if value > best then best = value end
    end
    board.best = best
    board.empty:SetText(#b.rows == 0 and "No attempt recorded yet this season." or "")

    -- Scroll range; open with the player's row in view.
    local maxOffset = math.max(0, #entries - LIST_ROWS)
    board.offset = 0
    if mineIndex and mineIndex > LIST_ROWS then
        board.offset = math.min(maxOffset, mineIndex - LIST_ROWS)
    end
    board.scroll:SetMinMaxValues(0, maxOffset)
    if maxOffset > 0 then board.scroll:Show() else board.scroll:Hide() end
    board.scroll:SetValue(board.offset)
    RenderList()

    -- Footer.
    if b.myRank > 0 then
        board.you:SetText(string.format("You |cffffffff#%d|r/%d · top |cffffffff%s%%|r",
            b.myRank, b.total, Percent(b.myRank, b.total)))
    elseif champion and b.classFilter ~= myClass and Trials.CLASS_NAME[myClass] then
        board.you:SetText("You play a " .. ClassText(myClass, Trials.CLASS_NAME[myClass]))
    elseif b.myBest > 0 then
        board.you:SetText("Your best: |cffffffff" .. Trials.FormatScore(b.trial, b.myBest) .. "|r")
    else
        board.you:SetText("No attempt of yours yet")
    end
    board.titleText:SetText((REWARD[b.trial] or REWARD[1]).title)

    board:Show()
end

-- ==================================================================== events

-- After a /reload inside the arena the result card is gone but the attempt still stands on the
-- server (phase RESULT): rebuild a card from the state alone so Retry / Leave stay reachable.
-- The rank is not in the state; the full card comes only with SEND_TRIAL_RESULT.
local function ShowResultFromState(st)
    if card:IsShown() then return end
    card.title:SetText(Trials.NAMES[st.trial] or "Trial")
    card.reason:SetText("Complete.")
    card.score:SetTextColor(1.0, 0.92, 0.70)
    if st.trial == Trials.TYPE.CRUSADER and (st.startWave or 1) > 1 then
        local headline, detail = PracticeLines(st.startWave, st.wavesCleared, st.teamSize)
        card.score:SetText(headline)
        card.detail:SetText(detail)
    elseif st.trial == Trials.TYPE.CRUSADER then
        local headline, detail = CrusaderLines(st.score, st.wavesCleared, st.teamSize)
        card.score:SetText(headline)
        card.detail:SetText(detail)
    else
        card.score:SetText(Trials.FormatScore(st.trial, st.score))
        card.detail:SetText("")
    end
    card.rank:SetText("")
    card.pb:SetText("")
    card:Show()
end

Trials.OnChanged(function(event, payload)
    if event == "state" then
        RefreshHUD()
        if payload and payload.phase ~= Trials.PHASE.RESULT then
            card:Hide()
        elseif payload and payload.phase == Trials.PHASE.RESULT then
            ShowResultFromState(payload)
        end
        if payload and payload.phase == Trials.PHASE.PREP and payload.attempt and payload.attempt ~= hud.lastAttempt then
            hud.lastAttempt = payload.attempt
            PlaySound("ReadyCheck")
        end
        -- Trial of the Crusader: a warning sound the moment this player goes down.
        local downed = payload and payload.downed and payload.phase == Trials.PHASE.RUNNING or false
        if downed and not hud.wasDowned then
            PlaySound("RaidWarning")
        end
        hud.wasDowned = downed
    elseif event == "result" then
        ShowResult(payload)
    elseif event == "board" then
        ShowBoard(payload)
    end
end)
