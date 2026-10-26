local addonName = ...
local addon = _G[addonName]

--------------------------------------------------------------------------
-- Theme state
--------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD, EMBER, MUTED, SOUL, LOC, DIM =
    "|cFFFFD24A", "|cFFFF8A2B", "|cFF8C867D", "|cFF6FE6DC", "|cFFD6CFC0", "|cFFB8B2A8"

local FONTS = {
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { name = "Skurri",        path = "Fonts\\SKURRI.TTF" },
}
local fontPaths = {}
for _, font in ipairs(FONTS) do fontPaths[font.path] = true end

local media = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
if media then
    for _, name in ipairs(media:List("font") or {}) do
        local path = media:Fetch("font", name)
        if path and not fontPaths[path] then
            FONTS[#FONTS + 1] = { name = name, path = path }
            fontPaths[path] = true
        end
    end
end

local function ResolveFont(path, fallback)
    if path and fontPaths[path] then return path end
    return fallback
end

local function ApplyFont(fs, path, size)
    if not fs.ashBaseFont then
        fs.ashBaseFont, fs.ashBaseSize, fs.ashBaseFlags = fs:GetFont()
    end
    fs:SetFont(ResolveFont(path, fs.ashBaseFont), size or fs.ashBaseSize, fs.ashBaseFlags)
end

local T = addon.Themes:Get(addon.Themes.default)
local C = T
local BUTTON_STYLES = T.btn
local themed = {}

local FLAT_BACKDROP = {
    bgFile = WHITE, edgeFile = WHITE, tile = false, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local ClassColors = {
    MAGE="|cFF69CCF0", WARRIOR="|cFFC79C6E", HUNTER="|cFFABD473",
    ROGUE="|cFFFFF569", WARLOCK="|cFF9482CA", DRUID="|cFFFF7D0A",
    SHAMAN="|cFF2459FF", PALADIN="|cFFF58CBA", PRIEST="|cFFFFFFFF",
    DEATHKNIGHT="|cFFC41F3B",
}
local CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS or {
    WARRIOR={0,0.25,0,0.25}, MAGE={0.25,0.5,0,0.25}, ROGUE={0.5,0.75,0,0.25},
    DRUID={0.75,1,0,0.25}, HUNTER={0,0.25,0.25,0.5}, SHAMAN={0.25,0.5,0.25,0.5},
    PRIEST={0.5,0.75,0.25,0.5}, WARLOCK={0.75,1,0.25,0.5},
    PALADIN={0,0.25,0.5,0.75}, DEATHKNIGHT={0.25,0.5,0.5,0.75},
}

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--------------------------------------------------------------------------
-- Icon options
--------------------------------------------------------------------------
local OK_OPTIONS = {
    { name="Ready-Check Tick",    path="Interface\\RaidFrame\\ReadyCheck-Ready",     size=22 },
    { name="Gold Checkbox",       path="Interface\\Buttons\\UI-CheckBox-Check",      size=26 },
    { name="Green Light",         path="Interface\\Common\\Indicator-Green",         size=18 },
    { name="Green Triangle",      path="Interface\\TargetingFrame\\UI-RaidTargetingIcon_4", size=16 },
    { name="Green Plus",          path="Interface\\Icons\\Spell_ChargePositive",     size=16 },
    { name="Key",                 path="Interface\\Icons\\INV_Misc_Key_03",          size=16 },
}
local NO_OPTIONS = {
    { name="Ready-Check Cross",   path="Interface\\RaidFrame\\ReadyCheck-NotReady",  size=22 },
    { name="Pass X",              path="Interface\\Buttons\\UI-GroupLoot-Pass-Up",    size=20 },
    { name="Red Light",           path="Interface\\Common\\Indicator-Red",           size=18 },
    { name="Red Cross Marker",    path="Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", size=16 },
    { name="Red Minus",           path="Interface\\Icons\\Spell_ChargeNegative",     size=16 },
    { name="Lock",                path="Interface\\Buttons\\LockButton-Locked-Up",   size=20 },
}
local PARTIAL_OPTIONS = {
    { name="Pocket Watch",     path="Interface\\Icons\\INV_Misc_PocketWatch_01",         size=16 },
    { name="Yellow Indicator", path="Interface\\Common\\Indicator-Yellow",                size=18 },
    { name="Yellow Question",  path="Interface\\GossipFrame\\AvailableQuestIcon",         size=16, isUI=true },
    { name="Yellow Dice",      path="Interface\\Buttons\\UI-GroupLoot-Dice-Up",           size=18 },
    { name="Yellow Moon",      path="Interface\\FriendsFrame\\StatusIcon-Away",           size=16, isUI=true },
    { name="Orange Circle",    path="Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",  size=16 },
}
local UNKNOWN_OPTIONS = {
    { name="Ready-Check Waiting", path="Interface\\RaidFrame\\ReadyCheck-Waiting", size=16, isUI=true },
    { name="Silver Quest Mark",   path="Interface\\GossipFrame\\IncompleteQuestIcon", size=16, isUI=true },
    { name="Question Mark",       path="Interface\\Icons\\INV_Misc_QuestionMark",     size=16 },
    { name="Spyglass",            path="Interface\\Icons\\INV_Misc_Spyglass_02",      size=16 },
}

local function PrepIcons(list)
    for _, opt in ipairs(list) do
        opt.crop = not opt.isUI and (string.find(opt.path, "Interface\\Icons\\", 1, true) == 1)
    end
end
PrepIcons(OK_OPTIONS); PrepIcons(NO_OPTIONS); PrepIcons(UNKNOWN_OPTIONS); PrepIcons(PARTIAL_OPTIONS)

local ICON_PAIRS = {
    { name="Ready-Check Ticks & Crosses",     ok=1, no=1 },
    { name="Gold Checkboxes & Pass X",        ok=2, no=2 },
    { name="Green & Red Indicator Lights",    ok=3, no=3 },
    { name="Raid Markers (Triangle / Cross)", ok=4, no=4 },
    { name="Plus & Minus Spells",             ok=5, no=5 },
    { name="Key & Lock Icons",                ok=6, no=6 },
}

local function GetActiveIcons()
    local dbOpts = addon.db and addon.db.global and addon.db.global.options or {}
    return OK_OPTIONS[Clamp(dbOpts.IconStyle_OK or 1, 1, #OK_OPTIONS)],
           NO_OPTIONS[Clamp(dbOpts.IconStyle_NO or 1, 1, #NO_OPTIONS)],
           UNKNOWN_OPTIONS[Clamp(dbOpts.IconStyle_Unknown or 1, 1, #UNKNOWN_OPTIONS)],
           PARTIAL_OPTIONS[Clamp(dbOpts.IconStyle_Partial or 1, 1, #PARTIAL_OPTIONS)]
end

--------------------------------------------------------------------------
-- Column model
--------------------------------------------------------------------------
local COLUMN_DEFS = {
    { key="name",     title="Name",       width=165, field="name",          justify="LEFT",   clip=true },
    { key="level",    title="Level",      width=50,  field="level",         justify="CENTER" },
    { key="wt",       title="10m WT 25m", width=100, field=nil,             justify="CENTER", reset="wt" },
    { key="cost",     title="Reset Cost", width=100, field="raidResetCost", justify="RIGHT",  reset="cost" },
    { key="ash",      title="Soul Ash",   width=100, field="soulAsh",       justify="RIGHT",  reset="ash" },
    { key="money",    title="Money",      width=150, field="money",         justify="RIGHT",  reset="money" },
    { key="location", title="Location",   width=170, field="location",      justify="LEFT",   clip=true, reset="location" },
    { key="lastSeen", title="Last Seen",  width=100, field="lastSeen",      justify="RIGHT",  reset="lastSeen" },
}
local MIN_COL_W = 40

local function BuildActiveColumns()
    local o = addon.db and addon.db.global and addon.db.global.options or {}
    local byKey = {}
    for _, d in ipairs(COLUMN_DEFS) do
        byKey[d.key] = { key=d.key, title=d.title, width=d.width, field=d.field,
                         justify=d.justify, clip=d.clip, reset=d.reset }
    end
    local cols = {}
    if o.columnOrder then
        for _, k in ipairs(o.columnOrder) do
            if byKey[k] then table.insert(cols, byKey[k]); byKey[k] = nil end
        end
    end
    for _, d in ipairs(COLUMN_DEFS) do
        if byKey[d.key] then table.insert(cols, byKey[d.key]) end
    end
    if o.columnWidths then
        for _, c in ipairs(cols) do
            if o.columnWidths[c.key] then c.width = math.max(MIN_COL_W, o.columnWidths[c.key]) end
        end
    end
    return cols
end

local COLUMNS, COLUMN_BY_KEY, COLUMN_X, BASE_WIDTH
local function RebuildColumnMetrics()
    COLUMNS = BuildActiveColumns()
    COLUMN_BY_KEY, COLUMN_X = {}, {}
    BASE_WIDTH = 0
    for _, c in ipairs(COLUMNS) do
        COLUMN_BY_KEY[c.key] = c
        COLUMN_X[c.key] = BASE_WIDTH
        BASE_WIDTH = BASE_WIDTH + c.width
    end
end
RebuildColumnMetrics()

local LEFT_PAD, RIGHT_MARGIN = 20, 34
local PAD = 8
local HEADER_HEIGHT = 24
local VIEW_TOP = 48
local VIEW_BOTTOM = 66
local ROWS_OFFSET = 30
local ROW_HEIGHT, ROW_STEP = 24, 26

local DEFAULT_WIDTH = LEFT_PAD + BASE_WIDTH + RIGHT_MARGIN
local DEFAULT_HEIGHT = 470
local MIN_WIDTH, MIN_HEIGHT = 380, 260

--------------------------------------------------------------------------
-- Theme switching
--------------------------------------------------------------------------
local themeReady = false
local function UseTheme(key)
    themeReady = true
    T = addon.Themes:Get(key)
    C = T; BUTTON_STYLES = T.btn
    GOLD, EMBER, MUTED, SOUL, LOC, DIM =
        T.text.gold, T.text.ember, T.text.muted, T.text.soul, T.text.loc, T.text.dim
    ROW_HEIGHT, ROW_STEP = T.layout.rowHeight, T.layout.rowStep
end
local function EnsureTheme()
    if themeReady then return end
    local o = addon.db and addon.db.global and addon.db.global.options
    UseTheme(o and o.Theme)
end
local function RegisterThemed(fn) themed[#themed + 1] = fn; fn() end
local function Gradient(tex, lo, hi)
    tex:SetGradientAlpha("VERTICAL", lo[1],lo[2],lo[3],lo[4] or 1, hi[1],hi[2],hi[3],hi[4] or 1)
end

-- The first SetFont on a file the client has not loaded yet returns false and
-- clears the string. A second call uses the cached file. Friz is the fallback
-- because the default UI font is already loaded.
local function SetFontSafe(fs, path, size, flags)
    flags = flags or ""
    if type(path) ~= "string" or path == "" then path = "Fonts\\FRIZQT__.TTF" end
    if not fs:SetFont(path, size, flags) then
        fs:SetFont(path, size, flags)
    end
    if not fs:GetFont() then
        fs:SetFont("Fonts\\FRIZQT__.TTF", size, flags)
        fs:SetFont("Fonts\\FRIZQT__.TTF", size, flags)
    end
end

function addon:ApplyTheme(key)
    if not addon.Themes.byKey[key] and
       not (addon.db.global.options.CustomThemes and addon.db.global.options.CustomThemes[key]) then
        key = addon.Themes.default
    end
    local o = addon.db and addon.db.global and addon.db.global.options

    -- Persist the chosen theme (except the transient draft)
    if o and key ~= "draft" then o.Theme = key end

    -- Detect column-width changes so the main frame can rebuild after theme hooks
    local needRebuild = false
    local def = addon.Themes:GetDef(key)
    if o then
        local newWidths = def.columnWidths or {}
        local old = o.columnWidths or {}
        for _, c in ipairs(COLUMN_DEFS) do
            local ov = old[c.key]   or c.width
            local nv = newWidths[c.key] or c.width
            if ov ~= nv then needRebuild = true; break end
        end
        -- Always rebuild o.columnWidths; empty table means "use per-column defaults"
        o.columnWidths = nil
        if next(newWidths) then
            o.columnWidths = {}
            for k, v in pairs(newWidths) do o.columnWidths[k] = v end
        end
    end

    UseTheme(key)
    for _, fn in ipairs(themed) do fn() end

    if AshoholicFrame then
        if needRebuild and AshoholicFrame.Rebuild then
            AshoholicFrame:Rebuild()
        elseif AshoholicFrame.ApplyLayout then
            AshoholicFrame:ApplyLayout()
        end
    end
end

--------------------------------------------------------------------------
-- Column reset
--------------------------------------------------------------------------
local COLUMN_LABELS = {
    wt       = "10m / 25m World Tour lockouts",
    cost     = "Reset Cost",
    ash      = "Soul Ash",
    money    = "Money",
    location = "Location",
    lastSeen = "Last Seen",
}

function addon:ResetColumn(column, allAccounts)
    local chars = addon.db and addon.db.global and addon.db.global.Characters
    if not chars or not COLUMN_LABELS[column] then return end
    for _, charDB in pairs(chars) do
        if allAccounts or addon:IsMyCharacter(charDB) then
            if column == "wt" then
                if charDB.SavedInstance then wipe(charDB.SavedInstance) end
                charDB.wtScanned = false
            elseif column == "cost"     then charDB.RaidResetCost = 50000
            elseif column == "ash"      then
                charDB.SoulAsh=0; charDB.RunSoulAsh=0; charDB.SpendableSoulAsh=0; charDB.CommittedSoulAsh=0
            elseif column == "money"    then charDB.money = 0
            elseif column == "location" then charDB.location = ""
            elseif column == "lastSeen" then charDB.lastSeen = 0
            end
        end
    end
    if addon.Characters then
        addon.Characters:BuildList()
        if addon.Characters.ReapplySort then addon.Characters:ReapplySort() end
        addon.Characters:BuildView()
    end
    if AshoholicFrame and AshoholicFrame.Refresh then AshoholicFrame:Refresh() end
    print("|cFF00FF9AAshoholic:|r " .. COLUMN_LABELS[column] ..
          " has been reset for " .. (allAccounts and "ALL accounts." or "this account."))
end

-- Step 1: pick a scope. Blizzard's StaticPopup_Resize handles the layout
-- for three buttons — never re-anchor them here or you'll break the popup.
-- Button layout per Blizzard convention (left→right): 1 | 3 | 2.
-- So we put Cancel as button2 (rightmost) and ALL Accounts as button3
-- (middle), giving the intuitive visual order:
--     [This Account]  [ALL Accounts]  [Cancel]
StaticPopupDialogs["ASHOHOLIC_RESET_COLUMN_SCOPE"] = {
    text = "Reset |cFFFFD700%s|r for which scope?",
    button1 = "This Account",
    button2 = "Cancel",
    button3 = "ALL Accounts",
    OnAccept = function(self, data)          -- button1: This Account
        if not data or not data.column then return end
        StaticPopup_Show("ASHOHOLIC_RESET_COLUMN_CONFIRM",
            COLUMN_LABELS[data.column], "this account",
            { column = data.column, allAccounts = false })
    end,
    OnCancel = function(self, data)          -- button2: Cancel — do nothing
        -- No-op; popup closes automatically.
    end,
    OnAlt = function(self, data)             -- button3: ALL Accounts
        if not data or not data.column then return end
        StaticPopup_Show("ASHOHOLIC_RESET_COLUMN_CONFIRM",
            COLUMN_LABELS[data.column], "ALL accounts",
            { column = data.column, allAccounts = true })
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Step 2: final Yes/No confirmation before the destructive reset.
StaticPopupDialogs["ASHOHOLIC_RESET_COLUMN_CONFIRM"] = {
    text = "Reset |cFFFFD700%s|r for |cFFFFD700%s|r?\n\nThis cannot be undone.",
    button1 = YES, button2 = NO,
    OnAccept = function(self, data)
        if not data or not data.column then return end
        addon:ResetColumn(data.column, data.allAccounts)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function ShowColumnResetScope(column)
    StaticPopup_Show("ASHOHOLIC_RESET_COLUMN_SCOPE",
        COLUMN_LABELS[column], nil, { column = column })
end
StaticPopupDialogs["ASH_REMOVE_ACCOUNT_CONFIRM"] = {
    text = 'Remove |cFFFFD700%s|r and all its characters from the roster?\n\n' ..
           'This removes them from the roster only — the real WoW characters ' ..
           'are untouched.\n\n' ..
           '|cFFFFD700They will come back on the next sync|r if this account ' ..
           'still exists on your machine.',
    button1 = "Continue", button2 = CANCEL,
    OnAccept = function(self, accountName)
        if not accountName then return end
        StaticPopup_Show("ASH_REMOVE_ACCOUNT_CONFIRM2", accountName, nil, accountName)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["ASH_REMOVE_ACCOUNT_CONFIRM2"] = {
    text = '|cFFFF0000FINAL WARNING|r\n\n' ..
           'Are you really sure you want to remove |cFFFFD700%s|r and ' ..
           '|cFFFFD700ALL|r of its characters from the roster?\n\n' ..
           'This cannot be undone. They will only come back if you sync ' ..
           'again while that account still exists on this machine.',
    button1 = "|cFFFF0000Remove them|r", button2 = "Keep them",
    OnAccept = function(self, accountName)
        if not accountName then return end
        local toDelete = {}
        for key, charDB in pairs(addon.db.global.Characters) do
            if (charDB.account or "Main Account") == accountName then
                toDelete[#toDelete + 1] = key
            end
        end
        for _, key in ipairs(toDelete) do
            addon.db.global.Characters[key] = nil
        end
        if addon.Characters then
            addon.Characters:BuildList()
            if addon.Characters.ReapplySort then addon.Characters:ReapplySort() end
            addon.Characters:BuildView()
        end
        if AshoholicFrame and AshoholicFrame.Refresh then AshoholicFrame:Refresh() end
        print("|c00FF9AAshoholic:|r Removed account '" .. accountName ..
              "' (" .. #toDelete .. " characters).")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["ASHOHOLIC_RESET_ALL_STEP1"] = {
    text="Reset all data (Soul Ash, Gold, and Reset Costs) across ALL characters?\n\nThis will affect your entire roster.",
    button1="Are you sure?", button2=CANCEL,
    OnAccept=function() StaticPopup_Show("ASHOHOLIC_RESET_ALL_STEP2") end,
    timeout=0, whileDead=true, hideOnEscape=true,
}
StaticPopupDialogs["ASHOHOLIC_RESET_ALL_STEP2"] = {
    text="Final Warning: All character data will be permanently wiped back to default values.",
    button1="|cFFFF0000Can't undo this!|r", button2=CANCEL,
    OnAccept=function() addon:ResetAllCharacterData() end,
    timeout=0, whileDead=true, hideOnEscape=true,
}

--------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------
local function FormatNumberPlain(num)
    if not num then return "0" end
    local s = string.format("%.0f", math.floor(num))
    while true do
        local k
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local function smartFmt(x, suffix, sign)
    if x == math.floor(x) then
        return string.format("%s%.0f%s", sign, x, suffix)
    end
    return string.format("%s%.2f%s", sign, x, suffix)
end

local function FormatNumberCompact(n)
    n = n or 0
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    if n < 1000 then return sign .. tostring(math.floor(n)) end
    if n < 1e6 then return smartFmt(n / 1e3, "k", sign) end
    if n < 1e9 then return smartFmt(n / 1e6, " mil", sign) end
    return smartFmt(n / 1e9, "b", sign)
end

local function FormatNum(num, compact)
    if compact then return FormatNumberCompact(num) end
    return FormatNumberPlain(num)
end

-- Kept for MiniMap
local function FormatNumber(num) return FormatNumberPlain(num) end

local ICON_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"
local ICON_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0|t"
local ICON_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0|t"

local function FormatMoney(copper, color)
    copper = copper or 0
    local pre  = color or ""
    local g    = math.floor(copper / 10000)
    local s    = math.floor(math.fmod(copper, 10000) / 100)
    local c    = math.fmod(copper, 100)

    local gStr = T.formatMoney and FormatNumberCompact(g) or FormatNumberPlain(g)

    if T.moneyGoldOnly then
        return pre .. gStr .. ICON_GOLD .. "|r"
    end
    return pre .. gStr .. ICON_GOLD .. " "
                     .. s .. ICON_SILVER .. " "
                     .. c .. ICON_COPPER .. "|r"
end

--------------------------------------------------------------------------
-- Flat button factory
--------------------------------------------------------------------------
local function CreateFlatButton(parent, width, height, label, styleName)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(width); b:SetHeight(height)
    b:SetBackdrop(FLAT_BACKDROP)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    function b:ApplyStyle(hover)
        ApplyFont(self.text, T.layout[styleName == "danger" and "dangerFont" or "buttonFont"])
        local s = BUTTON_STYLES[styleName or "default"]
        if hover then
            self:SetBackdropColor(unpack(s.hoverBg))
            self:SetBackdropBorderColor(unpack(s.hoverBorder))
        else
            self:SetBackdropColor(unpack(s.bg))
            self:SetBackdropBorderColor(unpack(s.border))
        end
        self.text:SetTextColor(unpack(s.text))
    end
    b:SetScript("OnEnter", function(self) self:ApplyStyle(true) end)
    b:SetScript("OnLeave", function(self) self:ApplyStyle(false) end)
    RegisterThemed(function() b:ApplyStyle(false) end)
    return b
end

--------------------------------------------------------------------------
-- Main window
--------------------------------------------------------------------------
function addon:CreateUI()
    if AshoholicFrame then return end
    EnsureTheme()

    local sortField, sortAsc = "name", true
    local rows = {}
    local visibleRows = 11
    local themedLabels, gripTints = {}, {}
    local headerButtons = {}

    local opts = addon.db and addon.db.global and addon.db.global.options
    local maxW = math.max(MIN_WIDTH, math.floor(UIParent:GetWidth()))
    local maxH = math.max(MIN_HEIGHT, math.floor(UIParent:GetHeight()))
    local startW = Clamp((opts and opts.WindowWidth)  or DEFAULT_WIDTH,  MIN_WIDTH,  maxW)
    local startH = Clamp((opts and opts.WindowHeight) or DEFAULT_HEIGHT, MIN_HEIGHT, maxH)

    local frame = CreateFrame("Frame", "AshoholicFrame", UIParent)
    frame:SetWidth(startW); frame:SetHeight(startH)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop(FLAT_BACKDROP)
    frame:SetBackdropColor(unpack(C.panel))
    frame:SetBackdropBorderColor(0,0,0,1)
    frame:EnableMouse(true); frame:EnableMouseWheel(true)
    frame:SetMovable(true); frame:SetResizable(true)
    frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    frame:SetMaxResize(maxW, maxH)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "AshoholicFrame")

    local glow = frame:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(WHITE)
    glow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    glow:SetHeight(110)

    local titleBar = frame:CreateTexture(nil, "BACKGROUND")
    titleBar:SetTexture(WHITE)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    titleBar:SetHeight(36)

    local titleLine = frame:CreateTexture(nil, "BORDER")
    titleLine:SetTexture(WHITE)
    titleLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -40)
    titleLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -40)
    titleLine:SetHeight(1)

    local inner = CreateFrame("Frame", nil, frame)
    inner:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    inner:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\Icons\\inv_soulash")
    logo:SetTexCoord(0.07,0.93,0.07,0.93)
    logo:SetWidth(26); logo:SetHeight(26)
    logo:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -9)

    local windowTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    windowTitle:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    windowTitle:SetJustifyH("LEFT")
    windowTitle:SetJustifyV("MIDDLE")
    if windowTitle.SetWordWrap then windowTitle:SetWordWrap(false) end
    windowTitle:SetText("Ashoholic")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("BOTTOMLEFT", windowTitle, "BOTTOMRIGHT", 10, 2)
    subtitle:SetJustifyH("LEFT")
    if subtitle.SetWordWrap then subtitle:SetWordWrap(false) end
    subtitle:SetText("Ebonhold Roster")

    local closeBtn = CreateFlatButton(frame, 22, 22, "X", "danger")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -11)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local settingsBtn = CreateFlatButton(frame, 22, 22, "*", "default")
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    settingsBtn:SetScript("OnClick", function() addon:ToggleConfigUI() end)
    -- Restored tooltip via HookScript (does not clobber the hover style)
    settingsBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Ashoholic Options", 1, 0.82, 0)
        GameTooltip:AddLine("|cFFFFFFFFClick|r to open settings & theme picker")
        GameTooltip:Show()
    end)
    settingsBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("RIGHT", closeBtn, "LEFT", -40, 0)

    -- Scroll + horizontal scroll content
    local scrollFrame = CreateFrame("ScrollFrame", "AshoholicScrollFrame", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_PAD, -(VIEW_TOP + ROWS_OFFSET))
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -RIGHT_MARGIN, VIEW_BOTTOM)
    scrollFrame:EnableMouseWheel(false)

    local hScroll = CreateFrame("ScrollFrame", nil, frame)
    hScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_PAD, -VIEW_TOP)
    hScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -RIGHT_MARGIN, VIEW_BOTTOM)

    local hContent = CreateFrame("Frame", nil, hScroll)
    hContent:SetWidth(BASE_WIDTH); hContent:SetHeight(300)
    hScroll:SetScrollChild(hContent)

    local hSlider = CreateFrame("Slider", "AshoholicHSlider", frame)
    hSlider:SetOrientation("HORIZONTAL")
    hSlider:SetHeight(12)
    hSlider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_PAD, 50)
    hSlider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -RIGHT_MARGIN, 50)
    hSlider:SetBackdrop(FLAT_BACKDROP)
    hSlider:SetThumbTexture(WHITE)
    local hThumb = hSlider:GetThumbTexture()
    hThumb:SetWidth(60); hThumb:SetHeight(8)
    hSlider:SetMinMaxValues(0, 0)
    hSlider:SetValueStep(1); hSlider:SetValue(0)
    hSlider:Hide()
    hSlider:SetScript("OnValueChanged", function(self, v) hScroll:SetHorizontalScroll(v) end)

    -- Column header bar
    local headerBar = hContent:CreateTexture(nil, "BACKGROUND")
    headerBar:SetTexture(WHITE)
    headerBar:SetPoint("TOPLEFT", hContent, "TOPLEFT", 0, 0)
    headerBar:SetPoint("TOPRIGHT", hContent, "TOPRIGHT", 0, 0)
    headerBar:SetHeight(HEADER_HEIGHT)

    local headerLine = hContent:CreateTexture(nil, "BORDER")
    headerLine:SetTexture(WHITE)
    headerLine:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("TOPRIGHT", headerBar, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)

    --------------------------------------------------------------------------
    -- Column drag / resize system
    --------------------------------------------------------------------------
    local dragState = nil
    local dragTracker

    local function SaveColumnState()
        local o = addon.db.global.options
        local order, widths = {}, {}
        for _, c in ipairs(COLUMNS) do
            table.insert(order, c.key)
            widths[c.key] = c.width
        end
        o.columnOrder = order
        o.columnWidths = widths
    end

    local function AttachHeaderInteractions(btn, col)
        local zone = CreateFrame("Frame", nil, btn)
        zone:SetWidth(5)
        zone:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
        zone:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        zone:EnableMouse(true)
        local hot = zone:CreateTexture(nil, "OVERLAY")
        hot:SetAllPoints(zone); hot:SetTexture(WHITE)
        hot:SetVertexColor(1, 0.75, 0.3, 0)
        zone:SetScript("OnEnter", function()
            if not dragState then hot:SetVertexColor(1,0.75,0.3,0.6) end
        end)
        zone:SetScript("OnLeave", function() hot:SetVertexColor(1,0.75,0.3,0) end)
        zone:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            dragState = {
                mode = "resize",
                colKey = col.key,
                startX = select(1, GetCursorPosition()) / UIParent:GetEffectiveScale(),
                startW = col.width,
            }
            dragTracker:Show()
        end)
    end

    dragTracker = CreateFrame("Frame", "AshoholicDragTracker", UIParent)
    dragTracker:Hide()
    dragTracker:SetScript("OnUpdate", function()
        if not dragState then dragTracker:Hide(); return end
        if not IsMouseButtonDown("LeftButton") then
            SaveColumnState()
            dragState = nil
            dragTracker:Hide()
            return
        end
        local x = select(1, GetCursorPosition()) / UIParent:GetEffectiveScale()

        if dragState.mode == "resize" then
            local delta = x - dragState.startX
            local newW = math.max(MIN_COL_W, dragState.startW + delta)
            addon.db.global.options.columnWidths = addon.db.global.options.columnWidths or {}
            addon.db.global.options.columnWidths[dragState.colKey] = newW
            frame:Rebuild()
        elseif dragState.mode == "drag" then
            local idx = frame:ColumnHitTest(x)
            if idx and idx ~= dragState.targetIdx then
                local order = {}
                for i, c in ipairs(COLUMNS) do
                    if i ~= dragState.srcIdx then table.insert(order, c.key) end
                end
                local insertAt = idx
                if idx > dragState.srcIdx then insertAt = idx end
                table.insert(order, insertAt, dragState.colKey)
                addon.db.global.options.columnOrder = order
                frame:Rebuild()
                for i, c in ipairs(COLUMNS) do
                    if c.key == dragState.colKey then dragState.srcIdx = i; dragState.targetIdx = i; break end
                end
            end
        end
    end)

    local function UpdateSortArrows()
        for _, btn in ipairs(headerButtons) do
            local col = btn.col
            if btn.arrow and col.field and col.field == sortField then
                btn.arrow:SetTexCoord(0, 0.5625, sortAsc and 0 or 1, sortAsc and 1 or 0)
                btn.arrow:Show()
            elseif btn.arrow then
                btn.arrow:Hide()
            end
        end
    end

    local function BuildHeaderButtons()
        wipe(headerButtons)
        wipe(themedLabels)

        for _, col in ipairs(COLUMNS) do
            local btn = CreateFrame("Button", nil, hContent)
            btn.col = col
            btn:SetHeight(HEADER_HEIGHT)
            btn:SetPoint("TOPLEFT", hContent, "TOPLEFT", COLUMN_X[col.key], 0)
            btn:SetWidth(col.width)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            btn:SetHighlightTexture(WHITE)
            local hl = btn:GetHighlightTexture()
            hl:SetVertexColor(1, 0.6, 0.2, 0.14); hl:SetBlendMode("ADD")
            btn.hl = hl

            if col.key == "wt" then
                local function SubLabel(text, fraction, isWT)
                    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    fs:SetPoint("CENTER", btn, "LEFT", col.width * fraction, 0)
                    fs.Retheme = function()
                        fs:SetText(text)
                        local rgb = isWT and T.wtLabelRGB or T.headerRGB
                        if rgb then fs:SetTextColor(unpack(rgb)) end
                    end
                    fs.Retheme()
                    themedLabels[#themedLabels + 1] = fs
                end
                SubLabel("10m", 0.25); SubLabel("WT", 0.50, true); SubLabel("25m", 0.75)
            else
                local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                if col.justify == "LEFT" then label:SetPoint("LEFT", btn, "LEFT", PAD, 0)
                elseif col.justify == "RIGHT" then label:SetPoint("RIGHT", btn, "RIGHT", -PAD, 0)
                else label:SetPoint("CENTER") end
                btn.label = label

                if col.field then
                    local arrow = btn:CreateTexture(nil, "OVERLAY")
                    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
                    arrow:SetWidth(9); arrow:SetHeight(8)
                    if col.justify == "RIGHT" then
                        arrow:SetPoint("RIGHT", label, "LEFT", -4, 0)
                    else
                        arrow:SetPoint("LEFT", label, "RIGHT", 4, 0)
                    end
                    arrow:Hide()
                    btn.arrow = arrow
                end
            end

            btn:SetScript("OnClick", function(self, mb)
                if mb == "RightButton" then
                    if col.reset then
                        ShowColumnResetScope(col.reset)
                    end
                elseif col.field then
                    if sortField == col.field then sortAsc = not sortAsc
                    else sortField = col.field; sortAsc = true end
                    addon.Characters:Sort(col.field)
                    UpdateSortArrows()
                    frame:Refresh()
                end
            end)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(col.title, 1, 0.82, 0)
                if col.field then GameTooltip:AddLine("|cFFFFFFFFLeft-Click|r to sort") end
                if col.reset then
                    GameTooltip:AddLine("|cFFFFFFFFRight-Click|r to reset (choose scope)")
                end
                GameTooltip:AddLine("|cFFFFFFFFDrag|r to reorder  -  |cFFFFFFFFDrag edge|r to resize")
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            btn:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                for i, c in ipairs(COLUMNS) do
                    if c.key == col.key then
                        dragState = {
                            mode = "drag", colKey = col.key,
                            startX = select(1, GetCursorPosition()) / UIParent:GetEffectiveScale(),
                            srcIdx = i, targetIdx = i,
                        }
                        break
                    end
                end
                dragTracker:Show()
            end)

            AttachHeaderInteractions(btn, col)
            table.insert(headerButtons, btn)
        end
        UpdateSortArrows()
    end

    frame._buildHeader = BuildHeaderButtons
    BuildHeaderButtons()

    -- Footer
    local footerLine = frame:CreateTexture(nil, "BORDER")
    footerLine:SetTexture(WHITE)
    footerLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_PAD, 46)
    footerLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 46)
    footerLine:SetHeight(1)

    local resetBtn = CreateFlatButton(frame, 120, 24, "Reset All Data", "danger")
    resetBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_PAD, 14)
    resetBtn:SetScript("OnClick", function() StaticPopup_Show("ASHOHOLIC_RESET_ALL_STEP1") end)
    -- Restored tooltip via HookScript
    resetBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reset Roster Data", 1, 0.82, 0)
        GameTooltip:AddLine("|cFFFFFFFFPermanently wipes for this account:|r")
        GameTooltip:AddLine("|cFFFF7070• Soul Ash (Run, Unspent, Committed)|r")
        GameTooltip:AddLine("|cFFFF7070• Gold|r")
        GameTooltip:AddLine("|cFFFF7070• Raid Reset Cost (back to 50,000)|r")
        GameTooltip:AddLine("|cFFFF7070• 10m / 25m World Tour lockouts|r")
        GameTooltip:AddLine("|cFFFF7070• Location and Last Seen|r")
        GameTooltip:AddLine("|cFFFFFFFFAlso DELETES every other|r")
        GameTooltip:AddLine("|cFFFFFFFFcharacter on this account|r")
        GameTooltip:AddLine("|cFFFFFFFFfrom the roster.|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFFFD700Does not affect other accounts.|r")
        GameTooltip:Show()
    end)
    resetBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local sliderHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sliderHint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 19)
    sliderHint:Hide()
    hSlider:SetScript("OnEnter", function() if hSlider:IsShown() then sliderHint:Show() end end)
    hSlider:SetScript("OnLeave", function() sliderHint:Hide() end)

    ----------------------------------------------------------------------
    -- Rows
    ----------------------------------------------------------------------
    local function CellText(row, key, template)
        local col = COLUMN_BY_KEY[key]
        local fs = row:CreateFontString(nil, "OVERLAY", template)
        fs:SetPoint("LEFT", row, "LEFT", COLUMN_X[key] + PAD, 0)
        if col.flex then fs:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
        else fs:SetWidth(col.width - PAD * 2) end
        fs:SetJustifyH(col.justify)
        if col.clip then
            fs:SetHeight(14)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
        end
        return fs
    end

    local function StyleRow(row, i)
        local L = T.layout
        local y = -(ROWS_OFFSET + (i - 1) * ROW_STEP)
        row:SetHeight(ROW_HEIGHT)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", hContent, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", hContent, "TOPRIGHT", 0, y)
        if L.accentWidth > 0 then row.accent:SetWidth(L.accentWidth); row.accent:Show()
        else row.accent:Hide() end
        local tl, rh = T.rowTopLine, T.rowHover
        row.topLine:SetVertexColor(tl[1], tl[2], tl[3], tl[4] or 1)
        row:GetHighlightTexture():SetVertexColor(rh[1], rh[2], rh[3], rh[4] or 0.10)

        local ltype = row._linetype or 2
        local fsize
        if ltype == 0 then fsize = L.realmFontSize
        elseif ltype == 1 then fsize = L.accountFontSize
        elseif ltype == 3 then fsize = L.totalsFontSize
        else fsize = L.characterFontSize end

        for _, fs in ipairs(row.fonts) do
            local fontKey = ltype == 0 and "realmFont" or
                ltype == 1 and "accountFont" or
                ltype == 3 and "totalsFont" or "characterFont"
            local path = ResolveFont(L[fontKey], fs.basePath)
            if path then fs:SetFont(path, fsize, fs.baseFlags) end
            fs:SetTextColor(T.body[1], T.body[2], T.body[3])
            if fs.baseHeight then fs:SetHeight(fsize + 2) end
        end

        -- Class icon (grows to left of name; pushes name right if necessary)
        local nameOffset = 0
        if T.showClassIcons then
            local sz = L.classIconSize
            row.classIcon:SetSize(sz, sz)
            row.classIcon:SetPoint("LEFT", row, "LEFT", COLUMN_X["name"] + PAD, 0)
            nameOffset = math.max(18, sz + 4)
            row.name:SetPoint("LEFT", row, "LEFT", COLUMN_X["name"] + PAD + nameOffset, 0)
        else
            row.classIcon:SetSize(1, 1)
            row.name:SetPoint("LEFT", row, "LEFT", COLUMN_X["name"] + PAD, 0)
        end

        local swapW = 0
        if row.swapBtn then
            local btnH = Clamp((ROW_HEIGHT or 24) - 6, 14, 22)
            local btnW = math.max(38, math.floor((L.characterFontSize or 12) * 3.2))
            row.swapBtn:SetSize(btnW, btnH)
            row.swapBtn:ClearAllPoints()
            row.swapBtn:SetPoint("RIGHT", row, "LEFT", COLUMN_X["name"] + COLUMN_BY_KEY["name"].width - PAD, 0)
            if row.swapBtn.text and row.swapBtn.text.basePath then
                row.swapBtn.text:SetFont(
                    row.swapBtn.text.basePath,
                    math.max(9, (L.characterFontSize or 12) - 2),
                    row.swapBtn.text.baseFlags
                )
            end
            row.swapBtn:ApplyStyle(false)
            if row.swapBtn:IsShown() then
                swapW = btnW + 4
            end
        end
        row.name:SetWidth(math.max(20, COLUMN_BY_KEY["name"].width - PAD * 2 - nameOffset - swapW))

        for n = 1, 2 do
            row.wtBtn[n]:SetSize(L.wtIconSize, L.wtIconSize)
        end
    end

    local function CreateRow(i)
        local row = CreateFrame("Button", "AshoholicRow" .. i, hContent)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row); row.bg:SetTexture(WHITE)
        row.accent = row:CreateTexture(nil, "ARTWORK")
        row.accent:SetTexture(WHITE); row.accent:SetWidth(3)
        row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.topLine = row:CreateTexture(nil, "ARTWORK")
        row.topLine:SetTexture(WHITE); row.topLine:SetHeight(1)
        row.topLine:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.topLine:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture(WHITE)
        row:GetHighlightTexture():SetBlendMode("ADD")

        local nameCol = COLUMN_BY_KEY["name"]
        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetWidth(14); row.classIcon:SetHeight(14)
        row.classIcon:SetPoint("LEFT", row, "LEFT", COLUMN_X["name"] + PAD, 0)
        row.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        row.classIcon:Hide()

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("LEFT", row, "LEFT", COLUMN_X["name"] + PAD + 18, 0)
        row.name:SetWidth(nameCol.width - PAD * 2 - 18)
        row.name:SetJustifyH("LEFT"); row.name:SetHeight(14)
        if row.name.SetWordWrap then row.name:SetWordWrap(false) end

        -- Mouse target for the instance-lockout panel. FontStrings do not
        -- receive hover, and this stays disabled except on character rows.
        row.nameHit = CreateFrame("Frame", nil, row)
        row.nameHit:EnableMouse(false)
        row.nameHit:SetFrameLevel(row:GetFrameLevel() + 4)

        local swapBtn = CreateFrame("Button", nil, row)
        swapBtn:SetSize(38, 18)
        swapBtn:SetPoint("RIGHT", row, "LEFT", COLUMN_X["name"] + nameCol.width - PAD, 0)
        swapBtn:SetBackdrop(FLAT_BACKDROP)
        swapBtn:RegisterForClicks("LeftButtonUp")
        swapBtn.text = swapBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        swapBtn.text:SetPoint("CENTER", 0, 0)
        swapBtn.text:SetText("Swap")
        swapBtn.text.basePath, swapBtn.text.baseSize, swapBtn.text.baseFlags = swapBtn.text:GetFont()
        function swapBtn:ApplyStyle(hover)
            local s = BUTTON_STYLES and BUTTON_STYLES["default"]
            if not s then return end
            if hover then
                self:SetBackdropColor(unpack(s.hoverBg))
                self:SetBackdropBorderColor(unpack(s.hoverBorder))
            else
                self:SetBackdropColor(unpack(s.bg))
                self:SetBackdropBorderColor(unpack(s.border))
            end
            if self.text and s.text then
                self.text:SetTextColor(unpack(s.text))
            end
        end
        swapBtn:SetScript("OnEnter", function(self)
            self:ApplyStyle(true)
            if self.charName then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("Fast Swap", 1, 0.82, 0)
                local colorCode = (self.class and ClassColors[self.class]) or "|cFFFFFFFF"
                GameTooltip:AddLine("|cFFFFFFFFClick|r to swap to " .. colorCode .. self.charName .. "|r", 0.9, 0.9, 0.9)
                GameTooltip:Show()
            end
        end)
        swapBtn:SetScript("OnLeave", function(self)
            self:ApplyStyle(false)
            GameTooltip:Hide()
        end)
        swapBtn:SetScript("OnClick", function(self)
            if self.charName and self.charName ~= "" then
                if PlaySound then
                    PlaySound("igMainMenuOptionCheckBoxOn")
                end
                if FastSwap_PerformSwap then
                    FastSwap_PerformSwap(self.charName)
                elseif addon.PerformFastSwap then
                    addon:PerformFastSwap(self.charName)
                end
            end
        end)
        swapBtn:Hide()
        row.swapBtn = swapBtn
        swapBtn:SetFrameLevel(row:GetFrameLevel() + 6)

        row.level    = CellText(row, "level",    "GameFontHighlight")
        row.cost     = CellText(row, "cost",     "GameFontHighlight")
        row.ash      = CellText(row, "ash",      "GameFontHighlight")
        row.money    = CellText(row, "money",    "GameFontHighlight")
        row.location = CellText(row, "location", "GameFontHighlight")
        row.lastSeen = CellText(row, "lastSeen", "GameFontHighlight")

        -- Soul Ash tooltip hitbox (only enabled on account rows)
        row.ashHitbox = CreateFrame("Frame", nil, row)
        row.ashHitbox:SetPoint("TOPLEFT", row, "TOPLEFT", COLUMN_X["ash"], 0)
        row.ashHitbox:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", COLUMN_X["ash"], 0)
        row.ashHitbox:SetWidth(COLUMN_BY_KEY["ash"].width)
        row.ashHitbox:EnableMouse(false)

        row.wtIcon, row.wtText, row.wtBtn = {}, {}, {}
        for n = 1, 2 do
            local cx = COLUMN_X.wt + COLUMN_BY_KEY.wt.width * (n == 1 and 0.25 or 0.75)
            local wtBtn = CreateFrame("Button", nil, row)
            wtBtn:SetSize(22, 22)
            wtBtn:SetPoint("CENTER", row, "LEFT", cx, 0)
            local icon = wtBtn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(wtBtn)
            row.wtIcon[n] = icon
            local txt = wtBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            txt:SetPoint("CENTER")
            row.wtText[n] = txt
            row.wtBtn[n] = wtBtn
        end

        row.expand = row:CreateTexture(nil, "ARTWORK")
        row.expand:SetWidth(14); row.expand:SetHeight(14)
        row.expand:SetPoint("LEFT", row, "LEFT", 10, 0)

        row.realmText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.realmText:SetPoint("LEFT", row, "LEFT", 30, 0)
        row.realmText:SetJustifyH("LEFT")

        row.fonts = {
            row.name, row.level, row.cost, row.ash, row.money,
            row.lastSeen, row.location,
            row.realmText, row.wtText[1], row.wtText[2],
        }
        for _, fs in ipairs(row.fonts) do
            fs.basePath, fs.baseSize, fs.baseFlags = fs:GetFont()
        end
        row.name.baseHeight = 14
        row.location.baseHeight = 14
        StyleRow(row, i)
        return row
    end

    local function EnsureRows(count)
        for i = #rows + 1, count do rows[i] = CreateRow(i) end
    end

    local function SetWTCell(row, n, state, lockedRaids, charName, raidType)
        local wtBtn, icon, txt = row.wtBtn[n], row.wtIcon[n], row.wtText[n]
        wtBtn:SetScript("OnEnter", nil)
        wtBtn:SetScript("OnLeave", nil)
        local iconOk, iconNo, iconUnknown, iconPartial = GetActiveIcons()
        if state == "lvl" then
            icon:Hide()
            local hasLockout = lockedRaids and #lockedRaids > 0
            if hasLockout then
                txt:SetText("LVL")
                txt:SetTextColor(unpack(T.wtLvlLockedRGB or {1, 0.33, 0.33}))
                wtBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine((charName or "Character") .. " (" .. raidType .. ")", 1, 0.82, 0)
                    GameTooltip:AddLine(T.text.wtLvlLocked .. "Locked to:|r")
                    for _, r in ipairs(lockedRaids) do GameTooltip:AddLine("- " .. r, 1, 1, 1) end
                    GameTooltip:Show()
                end)
                wtBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            else
                txt:SetText("LVL")
                txt:SetTextColor(unpack(T.wtLvlUnlockedRGB or {0.40, 0.87, 0.40}))
            end
            txt:Show()
        elseif state == "unknown" then
            txt:Hide()
            icon:SetTexture(iconUnknown.path)
            icon:SetWidth(math.min(iconUnknown.size, T.layout.wtIconSize))
            icon:SetHeight(math.min(iconUnknown.size, T.layout.wtIconSize))
            if iconUnknown.crop then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else icon:SetTexCoord(0, 1, 0, 1) end
            icon:Show()
            wtBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("World Tour Status", 1, 0.82, 0)
                GameTooltip:AddLine("|cFF8C867DData not scanned yet.|r")
                GameTooltip:Show()
            end)
            wtBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        elseif state == "partial" then
            txt:Hide()
            icon:SetTexture(iconPartial.path)
            icon:SetWidth(math.min(iconPartial.size, T.layout.wtIconSize))
            icon:SetHeight(math.min(iconPartial.size, T.layout.wtIconSize))
            if iconPartial.crop then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else icon:SetTexCoord(0, 1, 0, 1) end
            icon:Show()
            if lockedRaids and #lockedRaids > 0 then
                wtBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine((charName or "Character") .. " (" .. raidType .. ")", 1, 0.82, 0)
                    GameTooltip:AddLine("|cFFFFCC55Partial lockouts (" .. #lockedRaids .. "/3):|r")
                    for _, r in ipairs(lockedRaids) do GameTooltip:AddLine("- " .. r, 1, 1, 1) end
                    GameTooltip:Show()
                end)
                wtBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        else
            local opt = (state == "ok") and iconOk or iconNo
            txt:Hide()
            icon:SetTexture(opt.path)
            icon:SetWidth(math.min(opt.size, T.layout.wtIconSize))
            icon:SetHeight(math.min(opt.size, T.layout.wtIconSize))
            if opt.crop then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else icon:SetTexCoord(0, 1, 0, 1) end
            icon:Show()
            if state == "no" and lockedRaids and #lockedRaids > 0 then
                wtBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine((charName or "Character") .. " (" .. raidType .. ")", 1, 0.82, 0)
                    GameTooltip:AddLine("|cFFFF5555Locked to:|r")
                    for _, r in ipairs(lockedRaids) do GameTooltip:AddLine("- " .. r, 1, 1, 1) end
                    GameTooltip:Show()
                end)
                wtBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end
    end

    local function ClearRow(row)
        row.name:SetText(""); row.classIcon:Hide(); row.level:SetText("")
        row.cost:SetText(""); row.ash:SetText(""); row.money:SetText("")
        row.lastSeen:SetText("")
        row.location:SetText("")
        if row.swapBtn then
            row.swapBtn:Hide()
            row.swapBtn.charName = nil
            row.swapBtn.class = nil
        end
        for n = 1, 2 do row.wtIcon[n]:Hide(); row.wtText[n]:Hide() end
        row.expand:Hide(); row.realmText:Hide(); row.topLine:Hide()
        row.ashHitbox:EnableMouse(false)
        row.ashHitbox:SetScript("OnEnter", nil)
        row.ashHitbox:SetScript("OnLeave", nil)
        if row.nameHit then
            row.nameHit:EnableMouse(false)
            row.nameHit:SetScript("OnEnter", nil)
            row.nameHit:SetScript("OnLeave", nil)
            row.nameHit:SetScript("OnMouseUp", nil)
            row.nameHit.lockoutData = nil
        end
        row:UnlockHighlight()
        -- The row itself also carries hover handlers on the account branch;
        -- clear them here so they don't bleed into character/realm/totals rows.
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
    end

    ----------------------------------------------------------------------
    -- Instance lockouts. Hovering a character name attaches this panel
    -- to whichever side of the roster has room.
    ----------------------------------------------------------------------
    local PANEL_W, TIME_W = 320, 78
    local PAD_L, PAD_R, COL_GAP = 14, 12, 8
    local NAME_W = PANEL_W - PAD_L - PAD_R - COL_GAP - TIME_W
    local MAX_LINES = 24

    local lockoutPanel
    local lockoutLines = {}
    local hideAfter

    local panel = CreateFrame("Frame", "AshoholicLockoutPanel", UIParent)
    panel:SetWidth(PANEL_W)
    panel:SetHeight(48)
    panel:SetFrameStrata("HIGH")
    panel:SetFrameLevel((frame:GetFrameLevel() or 0) + 30)
    panel:SetBackdrop(FLAT_BACKDROP)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(false)
    panel:Hide()
    lockoutPanel = panel

    local accent = panel:CreateTexture(nil, "ARTWORK")
    accent:SetTexture(WHITE)
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 1, 1)
    panel.accent = accent

    local lockoutTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockoutTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_L, -10)
    lockoutTitle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD_R, -10)
    lockoutTitle:SetJustifyH("LEFT")
    lockoutTitle:SetHeight(16)
    if lockoutTitle.SetWordWrap then lockoutTitle:SetWordWrap(false) end
    panel.title = lockoutTitle

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", lockoutTitle, "BOTTOMLEFT", 0, -2)
    sub:SetWidth(NAME_W)
    sub:SetJustifyH("LEFT")
    sub:SetHeight(13)
    if sub.SetWordWrap then sub:SetWordWrap(false) end
    panel.sub = sub

    local hourCount = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hourCount:SetPoint("TOPRIGHT", lockoutTitle, "BOTTOMRIGHT", 0, -2)
    hourCount:SetWidth(TIME_W)
    hourCount:SetJustifyH("RIGHT")
    hourCount:SetHeight(13)
    if hourCount.SetWordWrap then hourCount:SetWordWrap(false) end
    panel.hourCount = hourCount

    local rule = panel:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(WHITE)
    rule:SetHeight(1)
    panel.rule = rule

    local more = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    more:SetJustifyH("LEFT")
    more:SetHeight(14)
    if more.SetWordWrap then more:SetWordWrap(false) end
    more:Hide()
    panel.more = more

    for i = 1, MAX_LINES do
        local name = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        local timeFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetJustifyH("LEFT")
        timeFs:SetJustifyH("RIGHT")
        if name.SetJustifyV then name:SetJustifyV("MIDDLE") end
        if timeFs.SetJustifyV then timeFs:SetJustifyV("MIDDLE") end
        if name.SetWordWrap then name:SetWordWrap(false) end
        if timeFs.SetWordWrap then timeFs:SetWordWrap(false) end
        name:Hide()
        timeFs:Hide()
        lockoutLines[i] = { name = name, time = timeFs }
    end

    local HOURLY_LINES = 11
    local hourlyLines = {}
    for i = 1, HOURLY_LINES do
        local name = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        local timeFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetJustifyH("LEFT")
        timeFs:SetJustifyH("RIGHT")
        if name.SetJustifyV then name:SetJustifyV("MIDDLE") end
        if timeFs.SetJustifyV then timeFs:SetJustifyV("MIDDLE") end
        if name.SetWordWrap then name:SetWordWrap(false) end
        if timeFs.SetWordWrap then timeFs:SetWordWrap(false) end
        name:Hide()
        timeFs:Hide()
        hourlyLines[i] = { name = name, time = timeFs }
    end

    local function SetFontSize(fs, size)
        local path, current, flags = fs:GetFont()
        if path and current ~= size then fs:SetFont(path, size, flags) end
    end

    local function HeaderMetrics()
        local size = (T.layout and T.layout.characterFontSize) or 12
        local titleH = size + 4
        local subH = math.max(12, size + 1)
        local lineH = math.max(16, size + 4)
        local ruleAt = 10 + titleH + 2 + subH + 6
        return size, titleH, subH, lineH, ruleAt, ruleAt + 7
    end

    local function TextFits(fs, maxWidth, limit, chars)
        local w = fs:GetStringWidth()
        if w and w > 0 then return w <= maxWidth end
        return limit ~= nil and chars <= limit
    end

    -- Hidden font strings report a width of 0 on 3.3.5, so a long name falls
    -- back to a character budget instead of running into the timer.
    local function FitText(fs, text, maxWidth)
        text = text or ""
        fs:SetText(text)
        local size = (T.layout and T.layout.characterFontSize) or 12
        local limit = math.max(8, math.floor(maxWidth / math.max(6, size * 0.56)))
        if TextFits(fs, maxWidth, limit, string.len(text)) then return end
        local best, low, high = "...", 1, string.len(text)
        while low <= high do
            local mid = math.floor((low + high) / 2)
            fs:SetText(string.sub(text, 1, mid) .. "...")
            if TextFits(fs, maxWidth, math.max(1, limit - 3), mid) then
                best = string.sub(text, 1, mid) .. "..."
                low = mid + 1
            else
                high = mid - 1
            end
        end
        fs:SetText(best)
    end

    local function FormatLockoutTime(seconds)
        seconds = math.max(0, math.floor(seconds))
        local days = math.floor(seconds / 86400)
        local hours = math.floor((seconds % 86400) / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        if days > 0 then return string.format("%dd %dh", days, hours) end
        if hours > 0 then return string.format("%dh %dm", hours, minutes) end
        if minutes > 0 then return string.format("%dm", minutes) end
        return "<1m"
    end

    local function FormatHourlyClock(seconds)
        seconds = math.max(0, math.floor(seconds))
        return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
    end

    local function TimeColor(expires)
        if expires < 3600 then return T.wtLvlLockedRGB or { 1, 0.33, 0.33 } end
        if expires < 86400 then return T.emberRGB or { 1, 0.54, 0.17 } end
        return T.goldRGB or { 1, 0.82, 0 }
    end

    local function StyleLockoutPanel()
        if not lockoutPanel then return end
        local size, titleH, subH, lineH = HeaderMetrics()
        lockoutPanel:SetBackdropColor(unpack(C.panel))
        lockoutPanel:SetBackdropBorderColor(unpack(C.border))
        local a = T.accent
        lockoutPanel.accent:SetVertexColor(a[1], a[2], a[3], a[4] or 1)
        local dim = T.accentDim or a
        lockoutPanel.rule:SetVertexColor(dim[1], dim[2], dim[3], dim[4] or 1)
        ApplyFont(lockoutPanel.title, T.layout.characterFont, size)
        SetFontSize(lockoutPanel.sub, math.max(10, size - 1))
        SetFontSize(lockoutPanel.hourCount, math.max(10, size - 1))
        SetFontSize(lockoutPanel.more, math.max(10, size - 1))
        lockoutPanel.title:SetHeight(titleH)
        lockoutPanel.sub:SetHeight(subH)
        lockoutPanel.hourCount:SetHeight(subH)
        lockoutPanel.sub:SetTextColor(unpack(T.mutedRGB or { 0.55, 0.52, 0.49 }))
        lockoutPanel.more:SetTextColor(unpack(T.mutedRGB or { 0.55, 0.52, 0.49 }))
        lockoutPanel.more:SetHeight(lineH)
        for i = 1, MAX_LINES do
            local line = lockoutLines[i]
            SetFontSize(line.name, math.max(10, size - 1))
            SetFontSize(line.time, math.max(10, size - 1))
            line.name:SetHeight(lineH)
            line.time:SetHeight(lineH)
        end
        for i = 1, HOURLY_LINES do
            local line = hourlyLines[i]
            SetFontSize(line.name, math.max(10, size - 1))
            SetFontSize(line.time, math.max(10, size - 1))
            line.name:SetHeight(lineH)
            line.time:SetHeight(lineH)
        end
    end

    local function SideRoom()
        local frameLeft = frame:GetLeft() or 0
        local frameRight = frame:GetRight() or frameLeft
        local roomLeft = frameLeft
        local roomRight = (UIParent:GetWidth() or 0) - frameRight
        local nexus = _G.NexusPanel
        if nexus and nexus.IsShown and nexus:IsShown() and nexus.GetLeft and nexus.GetRight then
            local nL, nR = nexus:GetLeft(), nexus:GetRight()
            if nL and nR then
                if nR <= frameLeft + 1 then
                    roomLeft = math.max(0, frameLeft - nR)
                elseif nL >= frameRight - 1 then
                    roomRight = math.max(0, nL - frameRight)
                end
            end
        end
        return roomLeft, roomRight
    end

    local function PlaceLockoutPanel(row)
        local frameTop = frame:GetTop()
        local frameLeft = frame:GetLeft()
        local frameRight = frame:GetRight()
        if not frameTop or not frameLeft or not frameRight then
            lockoutPanel:ClearAllPoints()
            lockoutPanel:SetPoint("TOPLEFT", frame, "TOPRIGHT", -1, 0)
            return
        end
        local roomLeft, roomRight = SideRoom()
        local need = lockoutPanel:GetWidth() + 8
        local side
        if roomRight >= need and roomLeft >= need then
            side = (roomRight >= roomLeft) and "RIGHT" or "LEFT"
        elseif roomRight >= need then
            side = "RIGHT"
        elseif roomLeft >= need then
            side = "LEFT"
        else
            side = (roomRight >= roomLeft) and "RIGHT" or "LEFT"
        end

        local ph = lockoutPanel:GetHeight()
        local screenH = UIParent:GetHeight() or 0
        local rowTop = (row and row:GetTop()) or frameTop
        local y = (rowTop - frameTop) + 8
        if frameTop + y - ph < 8 then y = 8 + ph - frameTop end
        if frameTop + y > screenH - 8 then y = screenH - 8 - frameTop end

        lockoutPanel:ClearAllPoints()
        if side == "RIGHT" then
            lockoutPanel:SetPoint("TOPLEFT", frame, "TOPRIGHT", -1, y)
        else
            lockoutPanel:SetPoint("TOPRIGHT", frame, "TOPLEFT", 1, y)
        end
        lockoutPanel:SetFrameLevel((frame:GetFrameLevel() or 0) + 30)
    end

    local function BuildLockoutDisplay(locks)
        local display = {}
        local raids, dungeons = 0, 0
        for i = 1, #locks do
            if locks[i].isRaid then raids = raids + 1 else dungeons = dungeons + 1 end
        end
        local mixed = raids > 0 and dungeons > 0
        local labeledRaid, labeledDungeon = false, false
        for i = 1, #locks do
            local lock = locks[i]
            if mixed and lock.isRaid and not labeledRaid then
                display[#display + 1] = { header = "Raids" }
                labeledRaid = true
            elseif mixed and not lock.isRaid and not labeledDungeon then
                display[#display + 1] = { header = "Dungeons" }
                labeledDungeon = true
            end
            display[#display + 1] = lock
        end
        return display
    end

    local function StopHideTimer()
        hideAfter = nil
        if lockoutPanel then lockoutPanel:SetScript("OnUpdate", nil) end
    end

    local function ShowLockoutPanel(row, data)
        if not row or not data or not lockoutPanel then return end
        StopHideTimer()
        StyleLockoutPanel()

        local charDB = data.key and addon.db and addon.db.global
            and addon.db.global.Characters and addon.db.global.Characters[data.key]
        local locks = (addon.Characters and addon.Characters.ActiveLockouts
            and addon.Characters:ActiveLockouts(charDB)) or {}
        local hourly = (addon.Characters and addon.Characters.HourlyLockouts
            and addon.Characters:HourlyLockouts(charDB)) or {
                tracked = false, count = 0, limit = 10, nextFree = 0, entries = {},
            }
        local display = BuildLockoutDisplay(locks)
        if #locks > 0 then
            table.insert(display, 1, { header = "Saved lockouts" })
        end

        local cc = RAID_CLASS_COLORS and data.class and RAID_CLASS_COLORS[data.class]
        if T.classColoredNames and cc then
            local nameA = (T.nameRGB and T.nameRGB[4]) or 1
            lockoutPanel.title:SetTextColor(cc.r, cc.g, cc.b, nameA)
        else
            lockoutPanel.title:SetTextColor(unpack(T.nameRGB or { 1, 1, 1 }))
        end
        lockoutPanel.title:SetText(data.name or "Character")
        lockoutPanel.sub:SetText("Raids this hour")

        local muted = T.mutedRGB or { 0.55, 0.52, 0.49 }
        local gold = T.goldRGB or { 1, 0.82, 0 }
        local body = T.body or { 1, 1, 1 }
        local bad = T.wtLvlLockedRGB or { 1, 0.33, 0.33 }
        local good = T.wtLvlUnlockedRGB or { 0.40, 0.87, 0.40 }
        local countColor = muted
        if hourly.tracked and hourly.count >= hourly.limit then
            countColor = bad
        elseif hourly.tracked and hourly.count == 0 then
            countColor = good
        elseif hourly.tracked then
            countColor = gold
        end
        lockoutPanel.hourCount:SetText(hourly.tracked and (hourly.count .. " / " .. hourly.limit) or "-")
        lockoutPanel.hourCount:SetTextColor(countColor[1], countColor[2], countColor[3], countColor[4] or 1)

        if T.classColoredAccent and cc then
            local classAlpha = (T.characterAccentBar and T.characterAccentBar[4]) or 1
            lockoutPanel.accent:SetVertexColor(cc.r, cc.g, cc.b, classAlpha)
        end

        local _, titleH, subH, lineH = HeaderMetrics()
        local cursor = 10 + titleH + 2 + subH + 4
        local now = time()
        local hourUsed = 0
        local atCap = hourly.tracked and hourly.count >= hourly.limit

        local function AddHourLine(label, timeText, labelColor, timeColor, expiresAt)
            hourUsed = hourUsed + 1
            if hourUsed > HOURLY_LINES then return end
            local line = hourlyLines[hourUsed]
            local y = -cursor
            line.name:ClearAllPoints()
            line.name:SetPoint("TOPLEFT", lockoutPanel, "TOPLEFT", PAD_L, y)
            line.name:SetWidth(timeText and NAME_W or (PANEL_W - PAD_L - PAD_R))
            if timeText then FitText(line.name, label, NAME_W) else line.name:SetText(label) end
            line.name:SetTextColor(labelColor[1], labelColor[2], labelColor[3], labelColor[4] or 1)
            line.name:Show()
            line.time:ClearAllPoints()
            line.time:SetPoint("TOPRIGHT", lockoutPanel, "TOPRIGHT", -PAD_R, y)
            line.time:SetWidth(TIME_W)
            if timeText then
                line.time:SetText(timeText)
                line.time:SetTextColor(timeColor[1], timeColor[2], timeColor[3], timeColor[4] or 1)
                line.time:Show()
                line.expiresAt = expiresAt
            else
                line.time:Hide()
                line.expiresAt = nil
            end
            cursor = cursor + lineH
        end

        if not hourly.tracked then
            AddHourLine("Not tracked yet", nil, muted)
        elseif hourly.count == 0 then
            AddHourLine("No raid entries this hour", nil, muted)
        else
            local nextColor = atCap and bad or gold
            AddHourLine("Next free", FormatHourlyClock(hourly.nextFree), gold, nextColor, now + hourly.nextFree)
            local shownHours = math.min(hourly.count, HOURLY_LINES - 1)
            for i = 1, shownHours do
                local entry = hourly.entries[i]
                local entryColor = (entry.expires < 600) and bad or gold
                AddHourLine(entry.label, FormatHourlyClock(entry.expires), body, entryColor, now + entry.expires)
            end
        end
        for i = hourUsed + 1, HOURLY_LINES do
            hourlyLines[i].name:Hide()
            hourlyLines[i].time:Hide()
            hourlyLines[i].expiresAt = nil
        end

        local count = #locks
        local shown = math.min(#display, MAX_LINES)
        while shown > 0 and display[shown].header do shown = shown - 1 end
        local hidden = 0
        for i = shown + 1, #display do
            if not display[i].header then hidden = hidden + 1 end
        end

        if count == 0 then
            lockoutPanel.rule:Hide()
            lockoutPanel.more:Hide()
            for i = 1, MAX_LINES do
                lockoutLines[i].name:Hide()
                lockoutLines[i].time:Hide()
                lockoutLines[i].expiresAt = nil
            end
            lockoutPanel:SetHeight(cursor + 10)
        else
            local ruleAt = cursor + 4
            local contentAt = ruleAt + 7
            lockoutPanel.rule:ClearAllPoints()
            lockoutPanel.rule:SetPoint("TOPLEFT", lockoutPanel, "TOPLEFT", 10, -ruleAt)
            lockoutPanel.rule:SetPoint("TOPRIGHT", lockoutPanel, "TOPRIGHT", -10, -ruleAt)
            lockoutPanel.rule:Show()

            for i = 1, MAX_LINES do
                local line = lockoutLines[i]
                local entry = display[i]
                if i <= shown and entry then
                    local y = -(contentAt + (i - 1) * lineH)
                    line.name:ClearAllPoints()
                    line.name:SetPoint("TOPLEFT", lockoutPanel, "TOPLEFT", PAD_L, y)
                    line.time:ClearAllPoints()
                    line.time:SetPoint("TOPRIGHT", lockoutPanel, "TOPRIGHT", -PAD_R, y)
                    line.time:SetWidth(TIME_W)
                    if entry.header then
                        line.name:SetWidth(PANEL_W - PAD_L - PAD_R)
                        line.name:SetText(entry.header)
                        line.name:SetTextColor(unpack(gold))
                        line.time:Hide()
                        line.expiresAt = nil
                    else
                        line.name:SetWidth(NAME_W)
                        FitText(line.name, entry.label, NAME_W)
                        line.name:SetTextColor(body[1], body[2], body[3], body[4] or 1)
                        line.time:SetText(FormatLockoutTime(entry.expires))
                        local c = TimeColor(entry.expires)
                        line.time:SetTextColor(c[1], c[2], c[3], c[4] or 1)
                        line.time:Show()
                        line.expiresAt = now + entry.expires
                    end
                    line.name:Show()
                else
                    line.name:Hide()
                    line.time:Hide()
                    line.expiresAt = nil
                end
            end

            local bodyLines = shown
            if hidden > 0 then
                local y = -(contentAt + shown * lineH)
                lockoutPanel.more:ClearAllPoints()
                lockoutPanel.more:SetPoint("TOPLEFT", lockoutPanel, "TOPLEFT", PAD_L, y)
                lockoutPanel.more:SetText("+" .. hidden .. " more")
                lockoutPanel.more:Show()
                bodyLines = shown + 1
            else
                lockoutPanel.more:Hide()
            end
            lockoutPanel:SetHeight(contentAt + bodyLines * lineH + 10)
        end

        lockoutPanel.hoverRow = row
        lockoutPanel.hoverData = data
        PlaceLockoutPanel(row)
        lockoutPanel:Show()
    end

    local function RefreshLockoutClocks()
        if hideAfter or not lockoutPanel or not lockoutPanel:IsShown() then return end
        local now = time()
        local function stale(line)
            return line.expiresAt and line.time:IsShown() and line.expiresAt <= now
        end
        for i = 1, HOURLY_LINES do if stale(hourlyLines[i]) then
            if lockoutPanel.hoverRow and lockoutPanel.hoverData then
                ShowLockoutPanel(lockoutPanel.hoverRow, lockoutPanel.hoverData)
            end
            return
        end end
        for i = 1, MAX_LINES do if stale(lockoutLines[i]) then
            if lockoutPanel.hoverRow and lockoutPanel.hoverData then
                ShowLockoutPanel(lockoutPanel.hoverRow, lockoutPanel.hoverData)
            end
            return
        end end
        for i = 1, HOURLY_LINES do
            local line = hourlyLines[i]
            if line.expiresAt and line.time:IsShown() then
                line.time:SetText(FormatHourlyClock(line.expiresAt - now))
            end
        end
        for i = 1, MAX_LINES do
            local line = lockoutLines[i]
            if line.expiresAt and line.time:IsShown() then
                line.time:SetText(FormatLockoutTime(line.expiresAt - now))
            end
        end
    end

    local clockTicker = CreateFrame("Frame")
    clockTicker.elapsed = 0
    clockTicker:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 1 then return end
        self.elapsed = 0
        RefreshLockoutClocks()
    end)
    lockoutPanel:SetScript("OnHide", function(self)
        self.hoverRow = nil
        self.hoverData = nil
    end)

    local function LockoutUnderCursor()
        for i = 1, #rows do
            local row = rows[i]
            if row:IsShown() and row.nameHit and row.nameHit.lockoutData and MouseIsOver(row.nameHit) then
                return row
            end
        end
    end

    local function RequestHideLockout()
        if not lockoutPanel or not lockoutPanel:IsShown() then return end
        hideAfter = GetTime() + 0.08
        lockoutPanel:SetScript("OnUpdate", function(self)
            if not hideAfter or GetTime() < hideAfter then return end
            hideAfter = nil
            self:SetScript("OnUpdate", nil)
            local hovered = LockoutUnderCursor()
            if hovered and hovered.nameHit and hovered.nameHit.lockoutData then
                hovered:LockHighlight()
                ShowLockoutPanel(hovered, hovered.nameHit.lockoutData)
            else
                self:Hide()
            end
        end)
    end

    local function SyncLockoutHover()
        local hovered = LockoutUnderCursor()
        for i = 1, #rows do
            if rows[i] ~= hovered then rows[i]:UnlockHighlight() end
        end
        if hovered and hovered.nameHit and hovered.nameHit.lockoutData then
            hovered:LockHighlight()
            ShowLockoutPanel(hovered, hovered.nameHit.lockoutData)
        else
            StopHideTimer()
            if lockoutPanel then lockoutPanel:Hide() end
        end
    end

    local function LayoutNameHit(row)
        local hit = row.nameHit
        if not hit then return end
        hit:ClearAllPoints()
        hit:SetHeight(ROW_HEIGHT)
        hit:SetPoint("LEFT", row, "LEFT", COLUMN_X["name"] or 0, 0)
        hit:SetPoint("RIGHT", row.name, "RIGHT", 0, 0)
        hit:SetFrameLevel(row:GetFrameLevel() + 4)
        if row.swapBtn then row.swapBtn:SetFrameLevel(row:GetFrameLevel() + 6) end
    end

    local function PaintRow(row, data, idx)
        ClearRow(row)
        local oldLtype = row._linetype
        row._linetype = data.linetype
        if oldLtype ~= data.linetype then
            StyleRow(row, row._rowIndex or 1)
        end
        if data.linetype == 0 then -- Realm
            row.bg:SetVertexColor(unpack(C.rowRealm))
            row.accent:SetVertexColor(unpack(T.realmAccentBar))
            row.expand:SetTexture(data.isCollapsed and "Interface\\Buttons\\UI-PlusButton-Up"
                                                  or "Interface\\Buttons\\UI-MinusButton-Up")
            row.expand:Show()
            row.realmText:SetText(data.realm)
            row.realmText:SetTextColor(unpack(T.emberRGB or {1, 0.54, 0.17}))
            row.realmText:Show()
            row:SetScript("OnClick", function()
                addon.Characters:ToggleRealm(data.realm)
                data.isCollapsed = not data.isCollapsed
                frame:Refresh()
            end)

        elseif data.linetype == 1 then -- Account
            row.bg:SetVertexColor(unpack(C.rowAccount))
            row.accent:SetVertexColor(unpack(T.accountAccentBar))
            row.expand:SetTexture(data.isCollapsed and "Interface\\Buttons\\UI-PlusButton-Up"
                                                  or "Interface\\Buttons\\UI-MinusButton-Up")
            row.expand:Show()
            row.realmText:SetPoint("LEFT", row, "LEFT", 30, 0)
            row.realmText:SetText(data.account)
            row.realmText:SetTextColor(unpack(T.accountNameRGB or {1, 0.54, 0.17}))
            row.realmText:Show()
            row.ash:SetText(FormatNum(data.soulAsh or 0, T.formatSoulAsh))
            row.ash:SetTextColor(unpack(T.soulRGB))
            row.money:SetText(FormatMoney(data.money or 0, ""))
            row.money:SetTextColor(unpack(T.moneyRGB or {1, 1, 1}))

            -- Soul Ash breakdown tooltip (over the ash column)
            row.ashHitbox:EnableMouse(true)
            row.ashHitbox:SetScript("OnEnter", function(self)
                local committed = data.committedAsh or 0
                local spendable = data.spendableAsh or 0
                local runAsh    = (data.soulAsh or 0) - spendable - committed
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(data.account .. " — Soul Ash", 1, 0.82, 0)
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Soul Ash This Run:",
                    FormatNum(runAsh, T.formatSoulAsh), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine("Unspent (shared pool):",
                    FormatNum(spendable, T.formatSoulAsh), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine("Committed (shared pool):",
                    FormatNum(committed, T.formatSoulAsh), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Total:",
                    FormatNum(data.soulAsh or 0, T.formatSoulAsh), 1, 0.82, 0, 1, 1, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFF8C867DThis Run = sum of every character's|r")
                GameTooltip:AddLine("|cFF8C867Dpersonal soul ash.|r")
                GameTooltip:AddLine("|cFF8C867DUnspent + Committed are account-wide|r")
                GameTooltip:AddLine("|cFF8C867Dpools shared by all characters.|r")
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFFFFFFFFShift+Right-Click|r to remove this account.")
                GameTooltip:Show()
            end)
            row.ashHitbox:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Row-wide tooltip (only fires when mouse is NOT over the ash
            -- column, so it never fights the ash breakdown above)
            row:SetScript("OnEnter", function(self)
                local cx = GetCursorPosition()
                local scale = self:GetEffectiveScale()
                local relX = (cx / scale) - self:GetLeft()
                local ashStart = COLUMN_X["ash"]
                local ashEnd   = ashStart + COLUMN_BY_KEY["ash"].width
                if relX >= ashStart and relX < ashEnd then
                    return  -- ash tooltip handles it
                end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(data.account, 1, 0.82, 0)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFFFFFFFFLeft-Click|r to collapse / expand.")
                GameTooltip:AddLine("|cFFFFFFFFRight-Click|r to rename this account.")
                GameTooltip:AddLine("|cFFFFFFFFShift+Right-Click|r to remove this " ..
                                    "account and all its characters.")
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFF8C867DShift+Right-Click on a character row to|r")
                GameTooltip:AddLine("|cFF8C867Dremove just that character.|r")
                GameTooltip:AddLine("|cFF8C867DRemoved accounts come back on next sync.|r")
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            row:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if IsShiftKeyDown() then
                        StaticPopup_Show("ASH_REMOVE_ACCOUNT_CONFIRM",
                                         data.account, nil, data.account)
                    else
                        addon:ShowAccountRename(data.accKey, data.account)
                    end
                else
                    addon.Characters:ToggleAccount(data.accKey)
                    data.isCollapsed = not data.isCollapsed
                    frame:Refresh()
                end
            end)

        elseif data.linetype == 3 then -- Totals
            row.bg:SetVertexColor(unpack(C.rowTotal))
            row.accent:SetVertexColor(unpack(T.totalsAccentBar))
            row.topLine:Show()
            row.name:SetText("Totals")
            row.name:SetTextColor(unpack(T.totalsRGB or {1, 0.82, 0}))
            row.ash:SetText(FormatNum(data.soulAsh, T.formatSoulAsh))
            row.ash:SetTextColor(unpack(T.soulRGB))
            row.money:SetText(FormatMoney(data.money or 0, ""))
            row.money:SetTextColor(unpack(T.moneyRGB or {1, 1, 1}))
            row:SetScript("OnClick", nil)

        else -- Character
            row.bg:SetVertexColor(unpack((T.layout.stripes and idx % 2 == 0) and C.rowA or C.rowB))
            local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
            if T.classColoredAccent and rc then
                -- Use the Character-accent color's alpha for the class
                -- accent bar, so the opacity slider still applies.
                local classAlpha = T.characterAccentBar[4] or 1
                row.accent:SetVertexColor(rc.r, rc.g, rc.b, classAlpha)
            else
                row.accent:SetVertexColor(unpack(T.characterAccentBar))
            end
            local coords = T.showClassIcons and CLASS_ICON_TCOORDS[data.class]
            if coords then row.classIcon:SetTexCoord(unpack(coords)); row.classIcon:Show()
            else row.classIcon:Hide() end

            if T.classColoredNames and ClassColors[data.class] then
                row.name:SetText(data.name)
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
                if cc then
                    -- Class colour only carries RGB. Borrow the alpha from the
                    -- "Name (custom)" colour so the picker still acts as an
                    -- opacity slider even with class-coloured names on.
                    local nameA = (T.nameRGB and T.nameRGB[4]) or 1
                    row.name:SetTextColor(cc.r, cc.g, cc.b, nameA)
                else
                    row.name:SetTextColor(unpack(T.nameRGB or {1, 1, 1}))
                end
            else
                row.name:SetText(data.name)
                row.name:SetTextColor(unpack(T.nameRGB or {1, 1, 1}))
            end

            -- FastSwap button: show for alts, hide for the currently logged-in character
            local currentPlayer = UnitName and UnitName("player")
            local isCurrentChar = currentPlayer and data.name and (string.lower(currentPlayer) == string.lower(data.name))
            local nameOffset = T.showClassIcons and math.max(18, (T.layout.classIconSize or 14) + 4) or 0
            if row.swapBtn then
                if not isCurrentChar and data.name and data.name ~= "" then
                    row.swapBtn.charName = data.name
                    row.swapBtn.class = data.class
                    row.swapBtn:ApplyStyle(false)
                    row.swapBtn:Show()
                    local swapW = row.swapBtn:GetWidth() + 4
                    row.name:SetWidth(math.max(20, COLUMN_BY_KEY["name"].width - PAD * 2 - nameOffset - swapW))
                else
                    row.swapBtn:Hide()
                    row.swapBtn.charName = nil
                    row.swapBtn.class = nil
                    row.name:SetWidth(math.max(20, COLUMN_BY_KEY["name"].width - PAD * 2 - nameOffset))
                end
            end

            if data.level >= 80 then
                row.level:SetText(tostring(data.level))
                row.level:SetTextColor(unpack(T.levelRGB or {1, 0.82, 0}))
            else
                row.level:SetText(tostring(data.level))
                row.level:SetTextColor(unpack(T.dimRGB or {0.72, 0.70, 0.66}))
            end

            local WT_TOTAL = 3
            local count10 = data.lockedCount10 or (data.isLocked10 and WT_TOTAL or 0)
            local count25 = data.lockedCount25 or (data.isLocked25 and WT_TOTAL or 0)

            local s10 = "ok"
            if data.level < 80 then s10 = "lvl"
            elseif not data.wtScanned then s10 = "unknown"
            elseif count10 >= WT_TOTAL then s10 = "no"
            elseif count10 > 0 then s10 = "partial"
            end

            local s25 = "ok"
            if data.level < 80 then s25 = "lvl"
            elseif not data.wtScanned then s25 = "unknown"
            elseif count25 >= WT_TOTAL then s25 = "no"
            elseif count25 > 0 then s25 = "partial"
            end
            SetWTCell(row, 1, s10, data.lockedRaids10, data.name, "10 - Man")
            SetWTCell(row, 2, s25, data.lockedRaids25, data.name, "25 - Man")

            row.cost:SetText(FormatNum(data.raidResetCost, T.formatResetCost))
            row.cost:SetTextColor(unpack(T.costRGB or {1, 0.82, 0}))
            row.ash:SetText(FormatNum(data.soulAsh, T.formatSoulAsh))
            row.ash:SetTextColor(unpack(T.soulRGB))
            row.money:SetText(FormatMoney(data.money or 0, ""))
            row.money:SetTextColor(unpack(T.moneyRGB or {1, 1, 1}))

            -- Last seen
            local seen = data.lastSeen or 0
            if seen > 0 then
                local delta = time() - seen
                local text
                if delta < 60 then text = "just now"
                elseif delta < 3600 then text = string.format("%dm ago", math.floor(delta/60))
                elseif delta < 86400 then text = string.format("%dh ago", math.floor(delta/3600))
                else text = string.format("%dd ago", math.floor(delta/86400)) end
                row.lastSeen:SetText(text)
            else
                row.lastSeen:SetText("Never")
            end
            row.lastSeen:SetTextColor(unpack(T.mutedRGB or {0.55, 0.52, 0.49}))

            if data.location and data.location ~= "" then
                row.location:SetText(data.location)
                row.location:SetTextColor(unpack(T.locRGB or {0.84, 0.81, 0.75}))
            else
                row.location:SetText("Unknown")
                row.location:SetTextColor(unpack(T.mutedRGB or {0.55, 0.52, 0.49}))
            end

            LayoutNameHit(row)
            row.nameHit.lockoutData = data
            row.nameHit:EnableMouse(true)
            row.nameHit:SetScript("OnEnter", function(self)
                row:LockHighlight()
                ShowLockoutPanel(row, self.lockoutData)
            end)
            row.nameHit:SetScript("OnLeave", function()
                local hovered = LockoutUnderCursor()
                if hovered and hovered ~= row and hovered.nameHit.lockoutData then
                    for i = 1, #rows do
                        if rows[i] ~= hovered then rows[i]:UnlockHighlight() end
                    end
                    hovered:LockHighlight()
                    ShowLockoutPanel(hovered, hovered.nameHit.lockoutData)
                    return
                end
                row:UnlockHighlight()
                RequestHideLockout()
            end)
            row.nameHit:SetScript("OnMouseUp", function(_, button)
                local fn = row:GetScript("OnClick")
                if fn then fn(row, button) end
            end)

            row:SetScript("OnClick", function(self, button)
                if button == "RightButton" and IsShiftKeyDown() then
                    StaticPopupDialogs["ASHOHOLIC_REMOVE_CHAR"] =
                        StaticPopupDialogs["ASHOHOLIC_REMOVE_CHAR"] or {
                        text = 'Remove |cFFFFD700%s|r from the roster?\n\n' ..
                               'Only affects the addon; the real WoW character is ' ..
                               'untouched, and it will come back on the next sync.',
                        button1 = YES, button2 = NO,
                        OnAccept = function(_, key)
                            addon.db.global.Characters[key] = nil
                            addon.Characters:BuildList()
                            if addon.Characters.ReapplySort then addon.Characters:ReapplySort() end
                            addon.Characters:BuildView()
                            if AshoholicFrame then AshoholicFrame:Refresh() end
                        end,
                        timeout = 0, whileDead = true, hideOnEscape = true,
                    }
                    StaticPopup_Show("ASHOHOLIC_REMOVE_CHAR", data.name, nil, data.key)
                end
            end)
        end
    end

    function frame:Refresh()
        addon.Characters:BuildView()
        local n = addon.Characters:GetNum()
        FauxScrollFrame_Update(scrollFrame, n, visibleRows, ROW_STEP)
        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        for i = 1, #rows do
            local row = rows[i]
            local idx = offset + i
            row._rowIndex = i
            if i <= visibleRows and idx <= n then
                PaintRow(row, addon.Characters:Get(idx), idx)
                row:Show()
            else
                row:Hide()
            end
        end
        SyncLockoutHover()
    end

    local function ApplyLayout()
        local fw, fh = frame:GetWidth(), frame:GetHeight()
        local vw = fw - LEFT_PAD - RIGHT_MARGIN
        local vh = fh - VIEW_TOP - VIEW_BOTTOM
        local cw = math.max(BASE_WIDTH, vw)
        hContent:SetWidth(cw)
        hContent:SetHeight(math.max(vh, 1))
        local maxScroll = math.floor(cw - vw + 0.5)
        if maxScroll > 0 then
            hSlider:SetMinMaxValues(0, maxScroll)
            if hSlider:GetValue() > maxScroll then hSlider:SetValue(maxScroll) end
            hSlider:Show()
        else
            hSlider:SetMinMaxValues(0, 0); hSlider:SetValue(0)
            hSlider:Hide(); hScroll:SetHorizontalScroll(0); sliderHint:Hide()
        end
        visibleRows = math.max(1, math.floor((vh - ROWS_OFFSET + (ROW_STEP - ROW_HEIGHT)) / ROW_STEP))
        EnsureRows(visibleRows)
        local prevScroll = scrollFrame:GetVerticalScroll()
        frame:Refresh()
        scrollFrame:SetVerticalScroll(prevScroll)
    end
    frame.ApplyLayout = ApplyLayout

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_STEP, function() frame:Refresh() end)
    end)

    frame:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown() then
            if hSlider:IsShown() then hSlider:SetValue(hSlider:GetValue() - delta * 60) end
        else
            local bar = _G["AshoholicScrollFrameScrollBar"]
            if bar then bar:SetValue(bar:GetValue() - delta * ROW_STEP) end
        end
    end)

    local function SaveSize()
        local o = addon.db and addon.db.global and addon.db.global.options
        if o then
            o.WindowWidth  = math.floor(frame:GetWidth() + 0.5)
            o.WindowHeight = math.floor(frame:GetHeight() + 0.5)
        end
    end
    local function ResetSize()
        local o = addon.db and addon.db.global and addon.db.global.options
        if o then o.WindowWidth = nil; o.WindowHeight = nil end
        frame:SetWidth(Clamp(DEFAULT_WIDTH, MIN_WIDTH, maxW))
        frame:SetHeight(Clamp(DEFAULT_HEIGHT, MIN_HEIGHT, maxH))
    end
    for _, point in ipairs({"TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT"}) do
        local grip = CreateFrame("Button", nil, frame)
        grip:SetWidth(14); grip:SetHeight(14)
        grip:SetPoint(point, frame, point, 0, 0)
        grip:SetFrameLevel(frame:GetFrameLevel() + 20)
        local dx = point:find("LEFT") and 1 or -1
        local dy = point:find("TOP") and -1 or 1
        local barH = grip:CreateTexture(nil, "OVERLAY")
        barH:SetTexture(WHITE); barH:SetWidth(9); barH:SetHeight(2)
        barH:SetPoint(point, grip, point, 5*dx, 5*dy)
        local barV = grip:CreateTexture(nil, "OVERLAY")
        barV:SetTexture(WHITE); barV:SetWidth(2); barV:SetHeight(9)
        barV:SetPoint(point, grip, point, 5*dx, 5*dy)
        local function Tint(a)
            local c = T.accent
            barH:SetVertexColor(c[1],c[2],c[3],a); barV:SetVertexColor(c[1],c[2],c[3],a)
        end
        Tint(0.45)
        gripTints[#gripTints + 1] = function() Tint(0.45) end
        grip:SetScript("OnEnter", function(self)
            Tint(1)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:AddLine("Resize", 1, 0.82, 0)
            GameTooltip:AddLine("|cFFFFFFFFLeft-drag|r to resize")
            GameTooltip:AddLine("|cFFFFFFFFRight-click|r to reset size")
            GameTooltip:Show()
        end)
        grip:SetScript("OnLeave", function() Tint(0.45); GameTooltip:Hide() end)
        grip:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then GameTooltip:Hide(); frame:StartSizing(point) end
        end)
        grip:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then frame:StopMovingOrSizing(); SaveSize()
            elseif button == "RightButton" then ResetSize() end
        end)
    end

    RegisterThemed(function()
        local L, a, g = T.layout, T.accent, T.glow
        frame:SetBackdropColor(unpack(C.panel))
        frame:SetBackdropBorderColor(unpack(C.border))
        glow:SetGradientAlpha("VERTICAL", g[1],g[2],g[3],g[4], g[1],g[2],g[3],0)
        if g[4] > 0 then glow:Show() else glow:Hide() end
        Gradient(titleBar, T.titleLo, T.titleHi)
        titleLine:SetVertexColor(a[1],a[2],a[3], a[4] or 0.9)
        inner:SetBackdropBorderColor(unpack(C.bronze))
        if L.innerBorder then inner:Show() else inner:Hide() end
        if T.outerBorder then
            frame:SetBackdropBorderColor(unpack(C.border))
        else
            frame:SetBackdropBorderColor(0, 0, 0, 0)
        end
        local _, _, titleFlags = windowTitle:GetFont()
        SetFontSafe(windowTitle, L.titleFont, L.titleSize, titleFlags)
        windowTitle:SetText("Ashoholic")
        windowTitle:SetTextColor(unpack(T.titleRGB))
        subtitle:SetText("Ebonhold Roster")
        ApplyFont(subtitle, L.mutedFont)
        if T.mutedRGB then subtitle:SetTextColor(unpack(T.mutedRGB)) end
        version:SetText(addon.Version or "")
        ApplyFont(version, L.mutedFont)
        if T.mutedRGB then version:SetTextColor(unpack(T.mutedRGB)) end
        sliderHint:SetText("Shift+scroll to pan columns")
        ApplyFont(sliderHint, L.mutedFont)
        if T.mutedRGB then sliderHint:SetTextColor(unpack(T.mutedRGB)) end
        hSlider:SetBackdropColor(unpack(T.sliderBg))
        hSlider:SetBackdropBorderColor(unpack(T.sliderBorder))
        hThumb:SetVertexColor(a[1],a[2],a[3], a[4] or 1)
        Gradient(headerBar, T.titleLo, T.titleHi)
        headerLine:SetVertexColor(T.accentDim[1], T.accentDim[2], T.accentDim[3], T.accentDim[4] or 1)
        footerLine:SetVertexColor(C.bronze[1], C.bronze[2], C.bronze[3], C.bronze[4] or 0.6)
        local br = T.accentBright
        for _, btn in ipairs(headerButtons) do
            if btn.hl then btn.hl:SetVertexColor(br[1], br[2], br[3], br[4] or 0.14) end
            if btn.label then
                ApplyFont(btn.label, L.headerFont, L.headerFontSize)
                btn.label:SetText(btn.col.title)
                btn.label:SetTextColor(unpack(T.headerRGB or {1, 0.82, 0}))
            end
            if btn.arrow then
                local sa = T.sortArrow
                btn.arrow:SetVertexColor(sa[1], sa[2], sa[3], sa[4] or 1)
            end
        end
        for _, fs in ipairs(themedLabels) do
            ApplyFont(fs, L.headerFont, L.headerFontSize)
        end
        for _, fs in ipairs(themedLabels) do fs.Retheme() end
        for _, tint in ipairs(gripTints) do tint() end
        for i, row in ipairs(rows) do StyleRow(row, i) end
        StyleLockoutPanel()
    end)

    frame:SetScript("OnSizeChanged", function() ApplyLayout() end)
    frame:SetScript("OnShow", function()
        -- SetFont during creation runs while the frame is hidden, which leaves
        -- the title at zero width. Apply it again once the frame is shown.
        local L = T.layout
        local _, _, titleFlags = windowTitle:GetFont()
        SetFontSafe(windowTitle, L.titleFont, L.titleSize, titleFlags)
        windowTitle:SetText("Ashoholic")
        if T.titleRGB then windowTitle:SetTextColor(unpack(T.titleRGB)) end
        subtitle:SetText("Ebonhold Roster")
        ApplyLayout()
    end)
    frame:SetScript("OnHide", function()
        StopHideTimer()
        if lockoutPanel then lockoutPanel:Hide() end
        for i = 1, #rows do rows[i]:UnlockHighlight() end
    end)

    function frame:ColumnHitTest(cursorX)
        local contentX = cursorX - hContent:GetLeft()
        local acc = 0
        for i, c in ipairs(COLUMNS) do
            acc = acc + c.width
            if contentX < acc then return i end
        end
        return #COLUMNS
    end

    function frame:Rebuild()
        RebuildColumnMetrics()
        for _, btn in ipairs(headerButtons) do btn:Hide(); btn:SetParent(nil) end
        wipe(headerButtons); wipe(themedLabels)
        for _, row in ipairs(rows) do row:Hide(); row:SetParent(nil) end
        wipe(rows)
        BuildHeaderButtons()
        for _, fn in ipairs(themed) do fn() end
        ApplyLayout()
    end

    ApplyLayout()
end

--------------------------------------------------------------------------
-- Config window  (3 tabs, grow-right-down)
--------------------------------------------------------------------------
local CFG_WIDTH = 540
local PAGE_TOP = 70

function addon:ToggleConfigUI()
    EnsureTheme()
    if AshoholicConfigFrame then
        if AshoholicConfigFrame:IsVisible() then
            -- Hide now goes through the confirmation override (see below).
            AshoholicConfigFrame:Hide()
        else
            -- Always land on the Icons tab per user preference.
            if AshoholicConfigFrame._selectTab then
                AshoholicConfigFrame._selectTab(1)
            end
            AshoholicConfigFrame:Show()
        end
        return
    end

    local cfg = CreateFrame("Frame", "AshoholicConfigFrame", UIParent)
    cfg:SetWidth(CFG_WIDTH)
    cfg:SetHeight(300)
    local sW, sH = UIParent:GetWidth(), UIParent:GetHeight()
    cfg:SetPoint("TOPLEFT", UIParent, "TOPLEFT", math.floor((sW - CFG_WIDTH)/2), -(math.floor((sH - 300)/2) + 60))
    cfg:SetFrameStrata("DIALOG")
    cfg:SetClampedToScreen(true)
    cfg:SetBackdrop(FLAT_BACKDROP)
    cfg:EnableMouse(true)
    cfg:SetMovable(true)
    cfg:RegisterForDrag("LeftButton")
    cfg:SetScript("OnDragStart", cfg.StartMoving)
    cfg:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Re-anchor to TOPLEFT so SetHeight always grows downward
        local left, top = self:GetLeft(), self:GetTop()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end)
    tinsert(UISpecialFrames, "AshoholicConfigFrame")

    -- Immediately style the frame with the current theme so that even if
    -- something downstream errors, the window at least looks correct.
    cfg:SetBackdropColor(unpack(C.panel))
    if T.outerBorder then
        cfg:SetBackdropBorderColor(unpack(C.border))
    else
        cfg:SetBackdropBorderColor(0, 0, 0, 0)
    end

    cfg:SetScript("OnHide", function(self)
        if addon.customizeDirty then
            self:Show()
            StaticPopup_Show("ASH_CONFIRM_CLOSE")
            return
        end
        if addon.customDraft then addon:CancelDraft() end
    end)

    -- Confirmation popup + Hide override: whenever the user closes the
    -- window (X button, ESC, or toggling the * button) with unsaved
    -- Customize changes, prompt first. Tab switching is unaffected.
    StaticPopupDialogs["ASH_CONFIRM_CLOSE"] = {
        text = "You have unsaved Customize changes.\n\n" ..
               "Close the settings window anyway and discard them?",
        button1 = "Discard & Close",
        button2 = "Keep Editing",
        OnAccept = function()
            addon.customizeDirty = false
            if AshoholicConfigFrame then AshoholicConfigFrame:Hide() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }

    local _origCfgHide = cfg.Hide
    cfg.Hide = function(self)
        if addon.customizeDirty then
            StaticPopup_Show("ASH_CONFIRM_CLOSE")
            return
        end
        _origCfgHide(self)
    end

    local titleBar = cfg:CreateTexture(nil, "BACKGROUND")
    titleBar:SetTexture(WHITE)
    titleBar:SetPoint("TOPLEFT", cfg, "TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -4, -4)
    titleBar:SetHeight(32)
    Gradient(titleBar, T.titleLo, T.titleHi)

    local title = cfg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    title:SetText(GOLD .. "Ashoholic Settings|r")

    local closeBtn = CreateFlatButton(cfg, 20, 20, "X", "danger")
    closeBtn:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -10, -10)
    closeBtn:SetScript("OnClick", function() cfg:Hide() end)

    local inner = CreateFrame("Frame", nil, cfg)
    inner:SetPoint("TOPLEFT", cfg, "TOPLEFT", 3, -3)
    inner:SetPoint("BOTTOMRIGHT", cfg, "BOTTOMRIGHT", -3, 3)
    inner:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    inner:SetBackdropBorderColor(unpack(C.bronze))

    local tabLine = cfg:CreateTexture(nil, "BORDER")
    tabLine:SetTexture(WHITE)
    tabLine:SetPoint("TOPLEFT", cfg, "TOPLEFT", 4, -(PAGE_TOP - 4))
    tabLine:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -4, -(PAGE_TOP - 4))
    tabLine:SetHeight(1)
    tabLine:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.9)

    local texts = {}
    local function Themed(fs, kind, text)
        texts[#texts + 1] = function()
            fs:SetText(text)
            if kind == "muted" then ApplyFont(fs, T.layout.mutedFont) end
            local rgb = (kind == "muted") and T.mutedRGB or T.sectionHeaderRGB
            if rgb then fs:SetTextColor(unpack(rgb)) end
        end
        texts[#texts]()
        return fs
    end

    local pages, pageHeights, tabs = {}, {}, {}
    local activeTab = 1
    local refreshCustomTab, refreshCustomizeTab

    local function StyleTab(tab)
        ApplyFont(tab.text, T.layout.tabFont)
        if tab.hovered then
            tab:SetBackdropColor(unpack(T.tabHoverBg))
            tab:SetBackdropBorderColor(unpack(T.tabHoverBorder))
            tab.text:SetTextColor(unpack(T.tabHoverText))
        elseif tab.index == activeTab then
            tab:SetBackdropColor(unpack(T.tabActiveBg))
            tab:SetBackdropBorderColor(unpack(T.tabActiveBorder))
            tab.text:SetTextColor(unpack(T.tabActiveText))
        else
            tab:SetBackdropColor(unpack(T.tabBg))
            tab:SetBackdropBorderColor(unpack(T.tabBorder))
            tab.text:SetTextColor(unpack(T.tabText))
        end
    end

    local function SelectTab(n)
        activeTab = n
        for i, p in ipairs(pages) do
            if i == n then p:Show() else p:Hide() end
        end
        cfg:SetHeight(pageHeights[n] or 300)
        for _, t in ipairs(tabs) do StyleTab(t) end
        if n == 2 and refreshCustomTab then refreshCustomTab() end
        if n == 3 and refreshCustomizeTab then
            -- Only rebuild the draft if it doesn't exist or is for a different theme.
            -- This preserves edits when switching tabs back and forth.
            local currentTheme = addon.db.global.options.Theme
            local draftValid = addon.customDraft and addon.customDraft.originalKey == currentTheme
            if addon.customDraft and not draftValid then
                addon.Themes.byKey["draft"] = nil
                addon.Themes:Invalidate("draft")
                addon.customDraft = nil
                addon.previousTheme = nil
            end
            refreshCustomizeTab()
        end
    end
    cfg._selectTab = SelectTab

    local function NewPage()
        local p = CreateFrame("Frame", nil, cfg)
        p:SetPoint("TOPLEFT", cfg, "TOPLEFT", 0, -PAGE_TOP)
        p:SetPoint("BOTTOMRIGHT", cfg, "BOTTOMRIGHT", 0, 0)
        p:Hide()
        return p
    end

    local function CreateTab(i, label, x)
        local tab = CreateFrame("Button", nil, cfg)
        tab.index = i
        tab:SetWidth(100); tab:SetHeight(24)
        tab:SetPoint("TOPLEFT", cfg, "TOPLEFT", x, -42)
        tab:SetBackdrop(FLAT_BACKDROP)
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tab.text:SetPoint("CENTER"); tab.text:SetText(label)
        tab:SetScript("OnClick", function(self) SelectTab(self.index) end)
        tab:SetScript("OnEnter", function(self)
            self.hovered = true
            StyleTab(self)
        end)
        tab:SetScript("OnLeave", function(self)
            self.hovered = false
            StyleTab(self)
        end)
        tabs[i] = tab
        StyleTab(tab)
        return tab
    end

    CreateTab(1, "Icons",     14)
    CreateTab(2, "Themes",   118)
    CreateTab(3, "Customize",222)
    CreateTab(4, "Sync",     326)

    ----------------------------------------------------------------------
    -- TAB 1 — Icons
    ----------------------------------------------------------------------
    local page1 = NewPage()
    pages[1] = page1
    pageHeights[1] = 530

    local p1Title = Themed(page1:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "gold", "Icon Pairs")
    p1Title:SetPoint("TOPLEFT", 20, -10)

    local p1Desc = Themed(page1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "muted",
                         "One-click presets that set both OK and NO icons.")
    p1Desc:SetPoint("TOPLEFT", p1Title, "BOTTOMLEFT", 0, -4)

    local y = -50
    for _, pair in ipairs(ICON_PAIRS) do
        local btn = CreateFlatButton(page1, 400, 24, pair.name, "default")
        btn:SetPoint("TOPLEFT", 20, y)
        btn:SetScript("OnClick", function()
            addon.db.global.options.IconStyle_OK = pair.ok
            addon.db.global.options.IconStyle_NO = pair.no
            if AshoholicFrame and AshoholicFrame:IsVisible() then AshoholicFrame:Refresh() end
            if page1._refreshDD then page1._refreshDD() end
        end)
        y = y - 28
    end

    ----------------------------------------------------------------------
    -- Custom icon dropdown
    ----------------------------------------------------------------------
    local iconMenu, iconMenuScroll, iconMenuChild, iconMenuButtons, iconMenuBar
    local iconMenuChoices, iconMenuSelect, iconMenuOwner

    page1:HookScript("OnHide", function()
        if iconMenu then iconMenu:Hide() end
    end)

    local function EnsureIconMenu()
        if iconMenu then return end

        iconMenu = CreateFrame("Frame", nil, page1)
        iconMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        iconMenu:SetFrameLevel(100)
        iconMenu:SetClampedToScreen(true)
        iconMenu:EnableMouse(true)
        iconMenu:SetWidth(360)
        iconMenu:SetBackdrop(FLAT_BACKDROP)
        iconMenu:SetBackdropColor(unpack(T.panel))
        iconMenu:SetBackdropBorderColor(unpack(T.border))

        iconMenuScroll = CreateFrame("ScrollFrame", nil, iconMenu)
        iconMenuScroll:SetPoint("TOPLEFT", 4, -4)
        iconMenuScroll:SetPoint("BOTTOMRIGHT", -26, 4)

        iconMenuBar = CreateFrame("Slider", nil, iconMenu)
        iconMenuBar:SetOrientation("VERTICAL")
        iconMenuBar:SetPoint("TOPRIGHT", -6, -4)
        iconMenuBar:SetPoint("BOTTOMRIGHT", -6, 4)
        iconMenuBar:SetWidth(12)
        iconMenuBar:SetBackdrop(FLAT_BACKDROP)
        iconMenuBar:SetBackdropColor(unpack(T.sliderBg))
        iconMenuBar:SetBackdropBorderColor(unpack(T.sliderBorder))
        iconMenuBar:SetMinMaxValues(0, 0)
        iconMenuBar:SetValueStep(1)
        iconMenuBar:SetThumbTexture(WHITE)
        local thumb = iconMenuBar:GetThumbTexture()
        thumb:SetWidth(12); thumb:SetHeight(24)
        thumb:SetVertexColor(unpack(T.accent))
        iconMenuBar:SetScript("OnValueChanged", function(self, value)
            iconMenuScroll:SetVerticalScroll(value)
        end)

        iconMenuScroll:SetScript("OnVerticalScroll", function(self, value)
            if iconMenuBar:GetValue() ~= value then iconMenuBar:SetValue(value) end
        end)
        iconMenuScroll:EnableMouseWheel(true)
        iconMenuScroll:SetScript("OnMouseWheel", function(self, delta)
            local _, maxScroll = iconMenuBar:GetMinMaxValues()
            iconMenuBar:SetValue(Clamp(self:GetVerticalScroll() - delta * 44, 0, maxScroll))
        end)

        iconMenuChild = CreateFrame("Frame", nil, iconMenuScroll)
        iconMenuChild:SetWidth(328)
        iconMenuScroll:SetScrollChild(iconMenuChild)

        iconMenuButtons = {}
        for i = 1, 24 do
            local button = CreateFrame("Button", nil, iconMenuChild)
            button:SetSize(326, 24)
            button:SetBackdrop(FLAT_BACKDROP)

            button.icon = button:CreateTexture(nil, "OVERLAY")
            button.icon:SetSize(16, 16)
            button.icon:SetPoint("LEFT", 8, 0)

            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetPoint("LEFT", button.icon, "RIGHT", 8, 0)
            button.text:SetPoint("RIGHT", button, "RIGHT", -26, 0)
            button.text:SetJustifyH("LEFT")

            button.check = button:CreateTexture(nil, "OVERLAY")
            button.check:SetSize(14, 14)
            button.check:SetPoint("RIGHT", -8, 0)
            button.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

            button:SetScript("OnEnter", function(self)
                local style = BUTTON_STYLES.default
                self:SetBackdropColor(unpack(style.hoverBg))
                self:SetBackdropBorderColor(unpack(style.hoverBorder))
                self.text:SetTextColor(unpack(style.text))
            end)
            button:SetScript("OnLeave", function(self)
                local style = BUTTON_STYLES.default
                self:SetBackdropColor(unpack(style.bg))
                self:SetBackdropBorderColor(unpack(style.border))
                self.text:SetTextColor(unpack(style.text))
            end)
            button:SetScript("OnClick", function(self)
                local choice = iconMenuChoices and iconMenuChoices[self.choiceIndex]
                if choice and iconMenuSelect then iconMenuSelect(choice) end
                iconMenu:Hide()
            end)

            iconMenuButtons[i] = button
        end

        iconMenu:SetScript("OnHide", function()
            iconMenuSelect  = nil
            iconMenuChoices = nil
            iconMenuOwner   = nil
        end)
    end

    local ddRefreshers = {}
    local function AddDropdown(yOff, labelText, options, dbKey)
        local l = Themed(page1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), "gold", labelText)
        l:SetPoint("TOPLEFT", 20, yOff)

        local dd = CreateFlatButton(page1, 340, 22, "", "default")
        dd:SetPoint("TOPLEFT", 20, yOff - 18)
        dd.text:ClearAllPoints()
        dd.text:SetPoint("LEFT",  dd, "LEFT",  26, 0)
        dd.text:SetPoint("RIGHT", dd, "RIGHT", -26, 0)
        dd.text:SetJustifyH("LEFT")

        -- Currently selected icon, shown on the closed button
        local selIcon = dd:CreateTexture(nil, "OVERLAY")
        selIcon:SetSize(16, 16)
        selIcon:SetPoint("LEFT", dd, "LEFT", 6, 0)

        -- Down-pointing triangle made from a font character
        local arrow = dd:CreateFontString(nil, "OVERLAY")
        arrow:SetPoint("RIGHT", -8, 0)
        arrow:SetFont("Fonts\\ARIALN.TTF", 10, "")
        arrow:SetText("▼")

        local function CurrentIdx()
            return Clamp(addon.db.global.options[dbKey] or 1, 1, #options)
        end

        local function Refresh()
            if T.accent then
                arrow:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
            end
            local opt = options[CurrentIdx()]
            dd.text:SetText(opt.name)
            selIcon:SetTexture(opt.path)
            if opt.crop then selIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else             selIcon:SetTexCoord(0, 1, 0, 1) end
        end
        ddRefreshers[#ddRefreshers + 1] = Refresh
        Refresh()

        local function ShowIconMenu()
            EnsureIconMenu()
            iconMenuOwner   = dd
            iconMenuChoices = options
            iconMenuSelect = function(choice)
                for i, opt in ipairs(options) do
                    if opt == choice then
                        addon.db.global.options[dbKey] = i
                        Refresh()
                        if AshoholicFrame and AshoholicFrame:IsVisible() then
                            AshoholicFrame:Refresh()
                        end
                        break
                    end
                end
            end

            local rowHeight     = 24
            local contentHeight = #options * rowHeight
            local visibleHeight = math.min(contentHeight, 260)
            iconMenu:SetHeight(visibleHeight + 8)
            iconMenuChild:SetHeight(contentHeight)
            iconMenuBar:SetMinMaxValues(0, math.max(0, contentHeight - visibleHeight))
            iconMenuBar:GetThumbTexture():SetHeight(
                math.max(24, visibleHeight * visibleHeight / contentHeight))
            iconMenuBar:SetValue(0)
            iconMenuScroll:SetVerticalScroll(0)

            local cur = CurrentIdx()
            for i, button in ipairs(iconMenuButtons) do
                local opt = options[i]
                if opt then
                    button.choiceIndex = i
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", iconMenuChild, "TOPLEFT", 0, -((i - 1) * rowHeight))
                    button.text:SetText(opt.name)
                    button.icon:SetTexture(opt.path)
                    if opt.crop then button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    else             button.icon:SetTexCoord(0, 1, 0, 1) end
                    if i == cur then button.check:Show() else button.check:Hide() end
                    button:Show()
                    button:GetScript("OnLeave")(button)
                else
                    button:Hide()
                end
            end

            iconMenu:ClearAllPoints()
            if dd:GetBottom() and dd:GetBottom() < visibleHeight + 20 then
                iconMenu:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 0, 2)
            else
                iconMenu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
            end
            iconMenu:Show()
        end

        dd:SetScript("OnClick", function()
            if iconMenu and iconMenu:IsShown() and iconMenuOwner == dd then
                iconMenu:Hide()
            else
                ShowIconMenu()
            end
        end)
    end

    AddDropdown(-230, "Completed / Ready (OK):", OK_OPTIONS, "IconStyle_OK")
    AddDropdown(-290, "Locked / Missing (NO):",   NO_OPTIONS, "IconStyle_NO")
    AddDropdown(-350, "Partially Locked (1-2/3):", PARTIAL_OPTIONS, "IconStyle_Partial")
    AddDropdown(-410, "Unscanned / Pending:",     UNKNOWN_OPTIONS, "IconStyle_Unknown")


    page1._refreshDD = function() for _, fn in ipairs(ddRefreshers) do fn() end end

    ----------------------------------------------------------------------
    -- TAB 2 — Themes
    ----------------------------------------------------------------------
    local page2 = NewPage()
    pages[2] = page2
    local CARD_W, CARD_H, CARD_GAP, CARD_STEP = 200, 42, 10, 48
    local trashFrame = CreateFrame("Frame", nil, UIParent)
    trashFrame:Hide()
    local cards = {}
    local dynHeader = {}

    local function BuildCard(def, isCustom, y, x)
        local P = addon.Themes:Get(def.key)
        local card = CreateFrame("Button", nil, page2)
        card.key, card.palette, card.isCustom = def.key, P, isCustom
        card:SetSize(CARD_W, CARD_H)
        card:SetPoint("TOPLEFT", x, y)
        card:SetBackdrop(FLAT_BACKDROP)
        card:SetBackdropColor(unpack(P.panel))

        local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        name:SetText(def.name or def.key or "Unnamed")
        name:SetTextColor(unpack(P.goldRGB))

        local swatches = { P.accent, P.accent2, P.goldRGB, P.soulRGB, P.accentDim }
        for n, c in ipairs(swatches) do
            local sw = card:CreateTexture(nil, "ARTWORK")
            sw:SetTexture(WHITE); sw:SetSize(18, 7)
            sw:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8 + (n-1)*20, 6)
            sw:SetVertexColor(c[1], c[2], c[3], 1)
        end

        card.accentBar = card:CreateTexture(nil, "OVERLAY")
        card.accentBar:SetTexture(WHITE)
        card.accentBar:SetWidth(4)
        card.accentBar:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        card.accentBar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        card.accentBar:Hide()

        card:SetScript("OnClick", function(self)
            addon:ApplyTheme(self.key)
            -- Drop the old draft silently; it'll be rebuilt from the new theme on tab 3
            if addon.customDraft then
                addon.Themes.byKey["draft"] = nil
                addon.Themes:Invalidate("draft")
                addon.customDraft = nil
                addon.previousTheme = nil
                addon.customizeDirty = false
            end
            if refreshCustomTab then refreshCustomTab() end
        end)
        card:SetScript("OnEnter", function(self)
            local a = self.palette.accent
            self:SetBackdropBorderColor(a[1], a[2], a[3], 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.palette.name, 1, 0.82, 0)
            if self.palette.desc then GameTooltip:AddLine(self.palette.desc, 1,1,1,true) end
            GameTooltip:AddLine("|cFFFFFFFFClick|r to apply")
            GameTooltip:Show()
        end)
        card:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            -- Restore the correct border: accentBright if this card is
            -- the currently-applied theme, otherwise the default bronze.
            local current = addon.db.global.options.Theme
            if self.key == current then
                local b = self.palette.accentBright
                self:SetBackdropBorderColor(b[1], b[2], b[3], 1)
            else
                self:SetBackdropBorderColor(unpack(self.palette.bronze))
            end
        end)

        if isCustom then
            local function miniBtn(label, xOff, tip, handler, texture, dim)
                local b = CreateFlatButton(card, 18, 18, label or "", "default")
                b:SetPoint("RIGHT", card, "RIGHT", xOff, 8)
                if texture then
                    local tex = b:CreateTexture(nil, "OVERLAY")
                    tex:SetSize(14, 14)
                    tex:SetPoint("CENTER")
                    tex:SetTexture(texture)
                    if dim then
                        tex:SetVertexColor(0.35, 0.35, 0.35, 0.7)
                    else
                        tex:SetVertexColor(1, 1, 1, 1)
                    end
                end
                b:SetScript("OnClick", handler)
                b:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine(tip, 1, 0.82, 0); GameTooltip:Show()
                end)
                b:HookScript("OnLeave", function() GameTooltip:Hide() end)
            end
            local function defer(fn)
                if C_Timer and C_Timer.After then C_Timer.After(0, fn)
                else local f = CreateFrame("Frame")
                     f:SetScript("OnUpdate", function(s)
                         s:SetScript("OnUpdate", nil); fn()
                     end) end
            end
            miniBtn("", -66, "Star / unstar", function()
                addon.Themes:ToggleStar(def.key)
                defer(refreshCustomTab)
            end, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", not def.starred)
            miniBtn("E", -46, "Edit in Customize tab", function()
                local editKey = def.key or card.key
                addon:CancelDraft()
                addon:BeginDraft(editKey)
                SelectTab(3)
            end)
            miniBtn("R", -26, "Rename", function()
                StaticPopupDialogs["ASH_REN_CUSTOM"] = StaticPopupDialogs["ASH_REN_CUSTOM"] or {
                    text = "Rename custom theme:",
                    button1 = OKAY, button2 = CANCEL, hasEditBox = true,
                    OnShow = function(self)
                        self.editBox:SetText(def.name)
                        self.editBox:HighlightText(); self.editBox:SetFocus()
                    end,
                    OnAccept = function(self)
                        local txt = self.editBox:GetText()
                        if txt and txt ~= "" then
                            addon.Themes:RenameCustom(def.key, txt); refreshCustomTab()
                        end
                    end,
                    timeout = 0, whileDead = true, hideOnEscape = true,
                }
                StaticPopup_Show("ASH_REN_CUSTOM")
            end)
            miniBtn("X", -6, "Delete", function()
                StaticPopupDialogs["ASH_DEL_CUSTOM"] = StaticPopupDialogs["ASH_DEL_CUSTOM"] or {
                    text = 'Delete custom theme "%s"?',
                    button1 = YES, button2 = NO,
                    OnAccept = function(self, data)
                        addon.Themes:DeleteCustom(data); refreshCustomTab()
                    end,
                    timeout = 0, whileDead = true, hideOnEscape = true,
                }
                StaticPopup_Show("ASH_DEL_CUSTOM", def.name, nil, def.key)
            end)
        end

        cards[#cards + 1] = card
        return card
    end

    refreshCustomTab = function()
        for _, c in ipairs(cards) do
            c:Hide()
            c:ClearAllPoints()
            c:SetParent(trashFrame)
            c:Hide()
        end
        wipe(cards)
        for _, h in ipairs(dynHeader) do
            h:Hide()
            h:ClearAllPoints()
            h:SetParent(trashFrame)
            h:Hide()
        end
        wipe(dynHeader)

        local current = addon.db.global.options.Theme
        local y = -50

        local dHdr = Themed(page2:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "gold", "Default Presets")
        dHdr:SetPoint("TOPLEFT", 20, y)
        dynHeader[#dynHeader + 1] = dHdr
        y = y - 20

        local defaultList = addon.Themes.list
        for i, def in ipairs(defaultList) do
            local x = 20 + ((i-1) % 2) * (CARD_W + CARD_GAP)
            local yy = y - math.floor((i-1)/2) * CARD_STEP
            BuildCard(def, false, yy, x)
        end
        y = y - math.ceil(#defaultList / 2) * CARD_STEP - 20

        local cHdr = Themed(page2:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "gold", "Custom Presets")
        cHdr:SetPoint("TOPLEFT", 20, y)
        dynHeader[#dynHeader + 1] = cHdr
        y = y - 20

        local customs = addon.Themes:ListCustoms()
        if #customs == 0 then
            local empty = Themed(page2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "muted",
                                 "No custom presets yet. Open Customize to create one.")
            empty:SetPoint("TOPLEFT", 20, y)
            dynHeader[#dynHeader + 1] = empty
            y = y - 20
        end
        for i, def in ipairs(customs) do
            local x = 20 + ((i-1) % 2) * (CARD_W + CARD_GAP)
            local yy = y - math.floor((i-1)/2) * CARD_STEP
            BuildCard(def, true, yy, x)
        end
        y = y - math.ceil(math.max(1, #customs) / 2) * CARD_STEP - 10

        for _, card in ipairs(cards) do
            if card.key == current then
                local b = card.palette.accentBright
                card:SetBackdropBorderColor(b[1], b[2], b[3], 1)
                card.accentBar:SetVertexColor(unpack(card.palette.accent))
                card.accentBar:Show()
            else
                card:SetBackdropBorderColor(unpack(card.palette.bronze))
                card.accentBar:Hide()
            end
        end

        pageHeights[2] = math.max(300, 70 - y)
        if activeTab == 2 then cfg:SetHeight(pageHeights[2]) end
    end

    ----------------------------------------------------------------------
    -- TAB 3 — Customize (all widget callbacks null-safe)
    ----------------------------------------------------------------------
    local page3 = NewPage()
    pages[3] = page3
    pageHeights[3] = 540

    local scroll = CreateFrame("ScrollFrame", "AshoholicCustomizeScroll", page3, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -12)
    scroll:SetPoint("BOTTOMRIGHT", -32, 62)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(Clamp(cur - delta * 30, 0, max))
    end)

    local body = CreateFrame("Frame", nil, scroll)
    body:SetWidth(CFG_WIDTH - 70)
    body:SetHeight(10)             -- grows at the end
    scroll:SetScrollChild(body)

    local widgetY = 0
    local widgets = {}
    local function nextY(h) widgetY = widgetY - (h or 24); return widgetY end

    local function sectionTitle(txt)
        local yPos = nextY(24)
        local fs = Themed(body:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "gold", txt)
        fs:SetPoint("TOPLEFT", 0, yPos)
        return fs
    end

    local function parseHex(h)
        if type(h) ~= "string" or #h < 6 then return 1, 1, 1, 1 end
        local r = tonumber(h:sub(1,2),16)/255
        local g = tonumber(h:sub(3,4),16)/255
        local b = tonumber(h:sub(5,6),16)/255
        local a = 1
        if #h >= 8 then a = tonumber(h:sub(7,8),16)/255 end
        return r, g, b, a
    end
    local function toHex(r, g, b, a)
        a = a or 1
        if a >= 0.99 then
            return string.format("%02X%02X%02X",
                math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5))
        end
        return string.format("%02X%02X%02X%02X",
            math.floor(r*255+0.5), math.floor(g*255+0.5),
            math.floor(b*255+0.5), math.floor(a*255+0.5))
    end

    -- per-key whitelist of fields where alpha is meaningful
    local ALPHA_KEYS = {
        bg=true, panel=true, border=true, bronze=true,
        rowA=true, rowB=true, rowRealm=true, rowAccount=true, rowTotal=true,
        rowHover=true, rowTopLine=true, sortArrow=true,
        titleLo=true, titleHi=true,
        realmAccentBar=true, accountAccentBar=true, totalsAccentBar=true, characterAccentBar=true,
        tabBg=true, tabBorder=true, tabActiveBg=true, tabActiveBorder=true,
        tabHoverBg=true, tabHoverBorder=true,
        btnBg=true, btnBorder=true, btnHoverBg=true, btnHoverBorder=true,
        dangerBg=true, dangerBorder=true, dangerHoverBg=true, dangerHoverBorder=true,
        sliderBg=true, sliderBorder=true,
        glow=true, panelAlpha=true,
    }

    local function defaultHexFor(key)
        local Def = addon.Themes:GetDef(addon.Themes.default)
        local P   = addon.Themes:Get(addon.Themes.default)
        if Def[key] then
            local v = Def[key]
            if type(v) == "string" then return v end
        end
        if P[key] and type(P[key]) == "table" then
            return toHex(P[key][1], P[key][2], P[key][3])
        end
        if P.text and P.text[key] then
            local aa, rgb = P.text[key]:match("|c(%x%x)(%x%x%x%x%x%x)")
            if aa and rgb then return rgb .. aa end
        end
        if P.btn then
            local b = P.btn.default
            local map = {
                btnBg = "bg", btnBorder = "border",
                btnHoverBg = "hoverBg", btnHoverBorder = "hoverBorder",
                btnText = "text",
            }
            if map[key] and b[map[key]] then
                local c = b[map[key]]
                return toHex(c[1], c[2], c[3])
            end
            local d = P.btn.danger
            local dmap = {
                dangerBg = "bg", dangerBorder = "border",
                dangerHoverBg = "hoverBg", dangerHoverBorder = "hoverBorder",
                dangerText = "text",
            }
            if dmap[key] and d[dmap[key]] then
                local c = d[dmap[key]]
                return toHex(c[1], c[2], c[3])
            end
        end
        return nil
    end

    local function effectiveHex(draft, key)
        if draft[key] ~= nil then return draft[key] end
        local P = addon.Themes:Get("draft")
        -- "bg" has no direct palette field; derive from applied panel color.
        -- Pass P.panel[4] so we don't lose the alpha the user set in the
        -- picker when the draft hasn't stored bg explicitly yet.
        if key == "bg" and P.panel then
            return toHex(P.panel[1], P.panel[2], P.panel[3], P.panel[4])
        end
        if type(P[key]) == "table" then
            return toHex(P[key][1], P[key][2], P[key][3], P[key][4])
        end
        if P.text and P.text[key] then
            local aa, rgb = P.text[key]:match("|c(%x%x)(%x%x%x%x%x%x)")
            if aa and rgb then return rgb .. aa end
        end

        -- Buttons (default style) — derive from built palette
        local btnMap = {
            btnBg="bg", btnBorder="border",
            btnHoverBg="hoverBg", btnHoverBorder="hoverBorder",
        }
        if btnMap[key] and P.btn and P.btn.default then
            local c = P.btn.default[btnMap[key]]
            if c then return toHex(c[1], c[2], c[3]) end
        end

        -- Danger buttons — derive from built palette
        local dangerMap = {
            dangerBg="bg", dangerBorder="border",
            dangerHoverBg="hoverBg", dangerHoverBorder="hoverBorder",
        }
        if dangerMap[key] and P.btn and P.btn.danger then
            local c = P.btn.danger[dangerMap[key]]
            if c then return toHex(c[1], c[2], c[3]) end
        end

        if key == "tabText"           then return toHex(unpack(P.tabText))           end
        if key == "tabActiveText"     then return toHex(unpack(P.tabActiveText))     end
        if key == "tabHoverText"      then return toHex(unpack(P.tabHoverText))      end
        if key == "titleText"         then return toHex(unpack(P.titleRGB))          end
        if key == "settingsTitleText" then return toHex(unpack(P.settingsTitleRGB))  end
        if key == "btnText"           then return toHex(unpack(P.btn.default.text))  end
        if key == "dangerText"        then return toHex(unpack(P.btn.danger.text))   end
        return "FFFFFF"
    end

    local function addColor(label, key)
        local yPos = nextY(22)
        local l = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", 0, yPos)
        l:SetWidth(185)
        l:SetJustifyH("LEFT")
        l:SetText(label)
        local swatch = CreateFrame("Button", nil, body)
        swatch:SetSize(60, 18)
        swatch:SetPoint("TOPLEFT", 200, yPos + 3)
        swatch:SetBackdrop(FLAT_BACKDROP)

        if not swatch.alphaText then
            swatch.alphaText = swatch:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            swatch.alphaText:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
            swatch.alphaText:SetWidth(50)
            swatch.alphaText:SetJustifyH("LEFT")
        end

        local function Refresh()
            local draft = addon.customDraft
            if not draft then return end
            local hex = effectiveHex(draft, key)
            local r, g, b, a = parseHex(hex)
            swatch:SetBackdropColor(r, g, b, 1)
            swatch:SetBackdropBorderColor(1, 1, 1, 0.4)
            if a < 1 and swatch.alphaOverlay == nil then
                swatch.alphaOverlay = swatch:CreateTexture(nil, "OVERLAY")
                swatch.alphaOverlay:SetAllPoints()
                swatch.alphaOverlay:SetTexture(WHITE)
            end
            if swatch.alphaOverlay then
                swatch.alphaOverlay:SetVertexColor(0, 0, 0, 1 - a)
            end
            if a < 0.99 then
                swatch.alphaText:SetText(string.format("%d%%", math.floor(a * 100 + 0.5)))
                swatch.alphaText:Show()
            else
                swatch.alphaText:Hide()
            end
            swatch.hex = hex
        end
        Refresh()

        swatch:SetScript("OnClick", function()
            if not addon.customDraft then return end
            local r, g, b, a = parseHex(swatch.hex or "FFFFFF")
            if not a then a = 1 end
            if a < 0 then a = 0 elseif a > 1 then a = 1 end

            local originalHex = swatch.hex
            local defHex = defaultHexFor(key)

            -- Find the opacity slider. Try the global name first, then walk
            -- the ColorPickerFrame's descendants (some forks rename it).
            local function findOpacitySlider()
                local s = _G["ColorPickerFrameOpacitySlider"]
                if s and s.GetValue then return s end
                local function walk(f, depth)
                    if not f or not f.GetNumChildren or depth > 5 then return nil end
                    for i = 1, f:GetNumChildren() do
                        local c = select(i, f:GetChildren())
                        if c and c.GetObjectType then
                            if c:GetObjectType() == "Slider" then return c end
                            local found = walk(c, depth + 1)
                            if found then return found end
                        end
                    end
                    return nil
                end
                return walk(ColorPickerFrame, 0)
            end

            -- Read the CURRENT alpha from the visible slider value.
            -- This is the ONLY source of truth on 3.3.5 forks —
            -- ColorPickerFrame.opacity is never updated when the user
            -- drags the thumb (the built-in handler never fires).
            local function readSliderAlpha()
                local s = ColorPickerFrame._ashOpSlider
                if s and s.GetValue then
                    local v = s:GetValue()
                    local minV, maxV = s:GetMinMaxValues()
                    if not minV then minV = 0 end
                    if not maxV or maxV <= minV then maxV = minV + 1 end
                    local range = maxV - minV
                    if range > 0 then
                        local norm = (v - minV) / range
                        if norm < 0 then norm = 0 elseif norm > 1 then norm = 1 end
                        return norm
                    end
                end
                return ColorPickerFrame.opacity or 1
            end

            local function apply()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = readSliderAlpha()
                if na < 0 then na = 0 elseif na > 1 then na = 1 end
                addon.customDraft[key] = toHex(nr, ng, nb, na)
                addon:ApplyDraft()
                Refresh()
            end

            -- Register callbacks (they may or may not fire on this fork —
            -- the OnUpdate monitor below is the real mechanism).
            ColorPickerFrame._ashApply   = apply
            ColorPickerFrame._ashInitial = a
            ColorPickerFrame.func        = apply
            ColorPickerFrame.opacityFunc = apply
            if ColorPickerFrame.swatchFunc then
                ColorPickerFrame.swatchFunc = apply
            end
            ColorPickerFrame.cancelFunc = function()
                if not addon.customDraft then return end
                addon.customDraft[key] = originalHex
                addon:ApplyDraft()
                Refresh()
            end

            ColorPickerFrame.hasOpacity = true
            ColorPickerFrame.opacity    = a

            if defHex then
                ColorPickerFrame.hasDefault   = 1
                ColorPickerFrame.defaultColor = { parseHex(defHex) }
                ColorPickerFrame.defaultFunc  = function()
                    if not addon.customDraft then return end
                    addon.customDraft[key] = nil
                    addon:ApplyDraft()
                    Refresh()
                    ColorPickerFrame:Hide()
                end
            else
                ColorPickerFrame.hasDefault   = nil
                ColorPickerFrame.defaultFunc  = nil
            end

            -- Cache the slider before Show().
            ColorPickerFrame._ashOpSlider = findOpacitySlider()

            -- Reset force-frame state BEFORE Show(). This fixes two bugs:
            --   * The very first open, when the OnShow hook wasn't yet
            --     installed at the moment Show() fired.
            --   * Switching swatches while the picker is already open —
            --     Show() is a no-op then and OnShow never fires.
            ColorPickerFrame._ashForceFrames     = 8
            ColorPickerFrame._ashLastSliderValue = nil
            ColorPickerFrame._ashLastApplyTime   = 0

            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame:Show()

            -- Install the monitor ONCE. It lives on ColorPickerFrame
            -- (not on the slider) and fires every frame while the picker
            -- is shown. It:
            --   * re-finds the slider if the global was missing,
            --   * overrides Show()'s opacity=0 reset for the first few
            --     frames so the picker opens at the saved alpha,
            --   * watches GetValue() directly and applies live changes
            --     to the draft immediately.
            if not ColorPickerFrame._ashMonitorInstalled then
                ColorPickerFrame._ashMonitorInstalled = true

                ColorPickerFrame:HookScript("OnShow", function(self)
                    self._ashForceFrames     = 8
                    self._ashLastSliderValue = nil
                end)

                ColorPickerFrame:HookScript("OnHide", function(self)
                    self._ashForceFrames     = 0
                    self._ashLastSliderValue = nil
                    self._ashLastApplyTime   = nil
                    -- Do NOT apply here: some 3.3.5 builds reset the slider
                    -- value to 0 BEFORE OnHide fires, which would overwrite
                    -- the user's saved alpha with 0. The guaranteed final
                    -- apply happens on the slider's OnMouseUp instead.
                end)

                ColorPickerFrame:HookScript("OnUpdate", function(self)
                    if not self._ashApply then return end

                    local s = self._ashOpSlider
                    if not s or not s.GetValue then
                        s = findOpacitySlider()
                        self._ashOpSlider = s
                    end
                    if not s or not s.GetValue then return end

                    -- Guaranteed final-apply on mouse-up: the throttle skips
                    -- frames during fast drags, and Show() can reset opacity
                    -- on close, so we can't rely on OnHide. OnMouseUp fires
                    -- at the exact moment the user lets go, before anything
                    -- resets the slider.
                    if not s._ashMouseUpHooked then
                        s._ashMouseUpHooked = true
                        s:HookScript("OnMouseUp", function()
                            if ColorPickerFrame._ashApply then
                                ColorPickerFrame._ashApply()
                            end
                        end)
                    end

                    -- (1) Force the initial value for the first ~8 frames.
                    -- Show() and SetColorRGB reset opacity AFTER our
                    -- pre-Show assignment, and the reset runs a frame or
                    -- two late. Keep forcing so the thumb lands at the
                    -- saved alpha and the "A" textbox shows it too.
                    if self._ashForceFrames and self._ashForceFrames > 0 then
                        self._ashForceFrames = self._ashForceFrames - 1
                        local alpha = self._ashInitial or 1
                        local minV, maxV = s:GetMinMaxValues()
                        if not minV then minV = 0 end
                        if not maxV or maxV <= minV then maxV = minV + 1 end
                        local range = maxV - minV
                        if range > 0 then
                            s:SetValue(minV + alpha * range)
                        end
                        self.opacity = alpha
                        self._ashLastSliderValue = s:GetValue()
                        return
                    end

                    -- (2) Watch for user movement. If GetValue() changed
                    -- since the last frame, the user is dragging the thumb
                    -- or clicked somewhere on the slider — apply it live.
                    local v = s:GetValue()
                    if self._ashLastSliderValue == nil then
                        self._ashLastSliderValue = v
                        return
                    end
                    if v ~= self._ashLastSliderValue then
                        self._ashLastSliderValue = v
                        local minV, maxV = s:GetMinMaxValues()
                        if not minV then minV = 0 end
                        if not maxV or maxV <= minV then maxV = minV + 1 end
                        local range = maxV - minV
                        if range > 0 then
                            local norm = (v - minV) / range
                            if norm < 0 then norm = 0 elseif norm > 1 then norm = 1 end
                            self.opacity = norm

                            -- Throttle the heavy ApplyTheme to ~12/sec so the
                            -- drag feels smooth. ApplyTheme rebuilds every
                            -- themed widget, which is expensive at 60 fps.
                            local now = GetTime()
                            if (now - (self._ashLastApplyTime or 0)) >= 0.08 then
                                self._ashLastApplyTime = now
                                self._ashApply()
                            end
                        end
                    end
                end)
            end
        end)

        widgets[#widgets + 1] = Refresh
    end

    -- SLIDER --------------------------------------------------------------
    local function addSlider(label, key, minVal, maxVal, inLayout)
        local yPos = nextY(30)
        local l = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", 0, yPos)
        l:SetWidth(185)
        l:SetJustifyH("LEFT")
        l:SetText(label)
        local s = CreateFrame("Slider", nil, body)
        s:SetOrientation("HORIZONTAL")
        s:SetSize(200, 16)
        s:SetPoint("TOPLEFT", 200, yPos + 3)
        s:SetBackdrop(FLAT_BACKDROP)
        s:SetMinMaxValues(minVal, maxVal)
        s:SetValueStep(1)
        s:SetThumbTexture(WHITE)
        local thumb = s:GetThumbTexture()
        thumb:SetWidth(10); thumb:SetHeight(16)
        s:SetBackdropColor(unpack(T.sliderBg))
        s:SetBackdropBorderColor(unpack(T.sliderBorder))
        thumb:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
        s:SetHitRectInsets(0, 0, 0, 0)
        local val = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("LEFT", s, "RIGHT", 6, 0)

        local function Get()
            local d = addon.customDraft
            if not d then return minVal end
            local v = inLayout and d.layout and d.layout[key] or d[key]
            return v or minVal
        end
        local refreshing = false
        local function Set(v)
            local d = addon.customDraft
            if not d then return end
            if inLayout then d.layout[key] = v else d[key] = v end
            addon:ApplyDraft()
        end
        s:SetScript("OnValueChanged", function(self, v)
            if refreshing then return end
            v = math.floor(v + 0.5)
            val:SetText(tostring(v))
            Set(v)
        end)
        local function Refresh()
            refreshing = true
            local v = Clamp(Get(), minVal, maxVal)
            s:SetValue(v)
            val:SetText(tostring(math.floor(v)))
            refreshing = false
        end
        Refresh()
        widgets[#widgets + 1] = Refresh
    end

    -- TOGGLE --------------------------------------------------------------
    local function addToggle(label, key, inLayout)
        local yPos = nextY(22)
        local l = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", 0, yPos)
        l:SetWidth(185)
        l:SetJustifyH("LEFT")
        l:SetText(label)
        local cb = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 200, yPos)
        cb:SetSize(20, 20)
        cb:SetScript("OnClick", function(self)
            local d = addon.customDraft
            if not d then return end
            if inLayout then d.layout[key] = self:GetChecked() and true or false
            else d[key] = self:GetChecked() and true or false end
            addon:ApplyDraft()
        end)
        local function Refresh()
            local d = addon.customDraft
            if not d then cb:SetChecked(false); return end
            local v
            if inLayout then
                v = d.layout and d.layout[key]
            else
                v = d[key]
            end
            cb:SetChecked(v == true)
        end
        Refresh()
        widgets[#widgets + 1] = Refresh
    end

    -- FONT ----------------------------------------------------------------
    local fontMenu, fontMenuScroll, fontMenuChild, fontMenuButtons, fontMenuBar
    local fontMenuChoices, fontMenuSelect, fontMenuOwner

    page3:HookScript("OnHide", function()
        if fontMenu then fontMenu:Hide() end
    end)

    local function EnsureFontMenu()
        if fontMenu then return end
        fontMenu = CreateFrame("Frame", nil, page3)
        fontMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        fontMenu:SetFrameLevel(100)
        fontMenu:SetClampedToScreen(true)
        fontMenu:EnableMouse(true)
        fontMenu:SetWidth(230)
        fontMenu:SetBackdrop(FLAT_BACKDROP)
        fontMenu:SetBackdropColor(unpack(T.panel))
        fontMenu:SetBackdropBorderColor(unpack(T.border))

        fontMenuScroll = CreateFrame("ScrollFrame", nil, fontMenu)
        fontMenuScroll:SetPoint("TOPLEFT", 4, -4)
        fontMenuScroll:SetPoint("BOTTOMRIGHT", -26, 4)
        fontMenuBar = CreateFrame("Slider", nil, fontMenu)
        fontMenuBar:SetOrientation("VERTICAL")
        fontMenuBar:SetPoint("TOPRIGHT", -6, -4)
        fontMenuBar:SetPoint("BOTTOMRIGHT", -6, 4)
        fontMenuBar:SetWidth(12)
        fontMenuBar:SetBackdrop(FLAT_BACKDROP)
        fontMenuBar:SetBackdropColor(unpack(T.sliderBg))
        fontMenuBar:SetBackdropBorderColor(unpack(T.sliderBorder))
        fontMenuBar:SetMinMaxValues(0, 0)
        fontMenuBar:SetValueStep(1)
        fontMenuBar:SetThumbTexture(WHITE)
        local thumb = fontMenuBar:GetThumbTexture()
        thumb:SetWidth(12)
        thumb:SetHeight(24)
        thumb:SetVertexColor(unpack(T.accent))
        fontMenuBar:SetScript("OnValueChanged", function(self, value)
            fontMenuScroll:SetVerticalScroll(value)
        end)
        fontMenuScroll:SetScript("OnVerticalScroll", function(self, value)
            if fontMenuBar:GetValue() ~= value then fontMenuBar:SetValue(value) end
        end)
        fontMenuScroll:EnableMouseWheel(true)
        fontMenuScroll:SetScript("OnMouseWheel", function(self, delta)
            local _, maxScroll = fontMenuBar:GetMinMaxValues()
            fontMenuBar:SetValue(Clamp(self:GetVerticalScroll() - delta * 44, 0, maxScroll))
        end)

        fontMenuChild = CreateFrame("Frame", nil, fontMenuScroll)
        fontMenuChild:SetWidth(198)
        fontMenuScroll:SetScrollChild(fontMenuChild)

        fontMenuButtons = {}
        for i = 1, #FONTS + 1 do
            local button = CreateFrame("Button", nil, fontMenuChild)
            button:SetSize(196, 22)
            button:SetBackdrop(FLAT_BACKDROP)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetPoint("LEFT", 6, 0)
            button.text:SetJustifyH("LEFT")
            button:SetScript("OnEnter", function(self)
                local style = BUTTON_STYLES.default
                self:SetBackdropColor(unpack(style.hoverBg))
                self:SetBackdropBorderColor(unpack(style.hoverBorder))
                self.text:SetTextColor(unpack(style.text))
            end)
            button:SetScript("OnLeave", function(self)
                local style = BUTTON_STYLES.default
                self:SetBackdropColor(unpack(style.bg))
                self:SetBackdropBorderColor(unpack(style.border))
                self.text:SetTextColor(unpack(style.text))
            end)
            button:SetScript("OnClick", function(self)
                local choice = fontMenuChoices and fontMenuChoices[self.choiceIndex]
                if choice and fontMenuSelect then fontMenuSelect(choice) end
                fontMenu:Hide()
            end)
            fontMenuButtons[i] = button
        end

        fontMenu:SetScript("OnHide", function()
            fontMenuSelect = nil
            fontMenuChoices = nil
            fontMenuOwner = nil
        end)
    end

    local function addFont(label, key, inLayout, allowDefault)
        local yPos = nextY(32)
        local l = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", 0, yPos)
        l:SetText(label)
        local dd = CreateFlatButton(body, 180, 22, "", "default")
        dd:SetPoint("TOPLEFT", 200, yPos + 2)
        dd.text:ClearAllPoints()
        dd.text:SetPoint("LEFT", dd, "LEFT", 8, 0)
        dd.text:SetPoint("RIGHT", dd, "RIGHT", -26, 0)
        dd.text:SetJustifyH("LEFT")
        local arrow = dd:CreateFontString(nil, "OVERLAY")
        arrow:SetPoint("RIGHT", -8, 0)
        arrow:SetFont("Fonts\\ARIALN.TTF", 10, "")
        arrow:SetText("▼")
        if T.accent then
            arrow:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
        end

        local function ShowFontMenu()
            EnsureFontMenu()
            fontMenuOwner = dd
            local choices = {}
            if allowDefault then choices[#choices + 1] = { name = "Game default", path = nil } end
            for _, font in ipairs(FONTS) do choices[#choices + 1] = font end
            fontMenuChoices = choices
            fontMenuSelect = function(choice)
                if not addon.customDraft then return end
                addon.customDraft.layout[key] = choice.path
                addon:ApplyDraft()
                dd.text:SetText(choice.name)
            end

            local rowHeight = 22
            local contentHeight = #choices * rowHeight
            local visibleHeight = math.min(contentHeight, 220)
            fontMenu:SetHeight(visibleHeight + 8)
            fontMenuChild:SetHeight(contentHeight)
            fontMenuBar:SetMinMaxValues(0, math.max(0, contentHeight - visibleHeight))
            fontMenuBar:GetThumbTexture():SetHeight(math.max(24, visibleHeight * visibleHeight / contentHeight))
            fontMenuBar:SetValue(0)
            fontMenuScroll:SetVerticalScroll(0)
            for i, button in ipairs(fontMenuButtons) do
                local choice = choices[i]
                if choice then
                    button.choiceIndex = i
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", fontMenuChild, "TOPLEFT", 0, -((i - 1) * rowHeight))
                    button.text:SetText(choice.name)
                    button:Show()
                    button:GetScript("OnLeave")(button)
                else
                    button:Hide()
                end
            end

            fontMenu:ClearAllPoints()
            if dd:GetBottom() and dd:GetBottom() < visibleHeight + 20 then
                fontMenu:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 0, 2)
            else
                fontMenu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
            end
            fontMenu:Show()
        end

        dd:SetScript("OnClick", function()
            if fontMenu and fontMenu:IsShown() and fontMenuOwner == dd then
                fontMenu:Hide()
            else
                ShowFontMenu()
            end
        end)

        local function Refresh()
            if T.accent then
                arrow:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
            end
            local d = addon.customDraft
            local choices = {}
            if allowDefault then choices[#choices + 1] = { name = "Game default", path = nil } end
            for _, font in ipairs(FONTS) do choices[#choices + 1] = font end
            if not d then dd.text:SetText(choices[1].name); return end
            local path = d.layout[key]
            local cur = choices[1]
            for _, font in ipairs(choices) do
                if font.path == path then cur = font; break end
            end
            dd.text:SetText(cur.name)
        end
        Refresh()
        widgets[#widgets + 1] = Refresh
    end

    local function addColumnSlider(label, colKey, minVal, maxVal)
        local yPos = nextY(30)
        local l = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", 0, yPos)
        l:SetText(label .. " width")
        local s = CreateFrame("Slider", nil, body)
        s:SetOrientation("HORIZONTAL")
        s:SetSize(200, 16)
        s:SetPoint("TOPLEFT", 200, yPos + 3)
        s:SetBackdrop(FLAT_BACKDROP)
        s:SetBackdropColor(unpack(T.sliderBg))
        s:SetBackdropBorderColor(unpack(T.sliderBorder))
        s:SetMinMaxValues(minVal, maxVal)
        s:SetValueStep(1)
        s:SetThumbTexture(WHITE)
        local th = s:GetThumbTexture()
        th:SetWidth(10); th:SetHeight(16)
        th:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
        local val = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("LEFT", s, "RIGHT", 6, 0)

        local function GetW()
            local d = addon.customDraft
            if not d then return 130 end
            if d.columnWidths and d.columnWidths[colKey] then return d.columnWidths[colKey] end
            -- Fall back to the widths actually applied to the live window
            local o = addon.db.global.options
            if o.columnWidths and o.columnWidths[colKey] then return o.columnWidths[colKey] end
            for _, c in ipairs(COLUMN_DEFS) do
                if c.key == colKey then return c.width end
            end
            return 130
        end
        local function SetW(v)
            local d = addon.customDraft
            if not d then return end
            d.columnWidths = d.columnWidths or {}
            d.columnWidths[colKey] = v
            addon.db.global.options.columnWidths = addon.db.global.options.columnWidths or {}
            addon.db.global.options.columnWidths[colKey] = v
            if AshoholicFrame and AshoholicFrame.Rebuild then AshoholicFrame:Rebuild() end
            addon:ApplyDraft()
        end
        local refreshing = false
        s:SetScript("OnValueChanged", function(_, v)
            if refreshing then return end
            v = math.floor(v + 0.5)
            val:SetText(tostring(v))
            SetW(v)
        end)
        local function Refresh()
            refreshing = true
            local v = Clamp(GetW(), minVal, maxVal)
            s:SetValue(v)
            val:SetText(tostring(math.floor(v)))
            refreshing = false
        end
        Refresh()
        widgets[#widgets + 1] = Refresh
    end

    ------------------------------------------------------------------------
    -- Widget builders for the new option types
    ------------------------------------------------------------------------
    local function addColorTogglePair(colorKey, toggleKey, label, toggleLabel, inLayout)
        -- A colour swatch + a paired toggle (used for "Class names" / colour)
        addColor(label, colorKey)
        addToggle(toggleLabel, toggleKey, inLayout)
    end

    sectionTitle("Window")
    addColor("Background",       "bg")
    addSlider("Glow strength %", "glow",       0, 50)
    addColor("Outer border",     "border")
    addToggle("Show outer border", "outerBorder")
    addColor("Inner border",     "bronze")
    addToggle("Show inner border", "innerBorder", true)

    sectionTitle("Title Bar")
    addColor("Main title text",     "titleText")
    addColor("Settings title text", "settingsTitleText")
    addColor("Gradient bottom",  "titleLo")
    addColor("Gradient top",     "titleHi")
    addFont("Title font", "titleFont", true, false)
    addSlider("Title size",      "titleSize", 10, 32, true)

    sectionTitle("Column Headers")
    addColor("Underline",        "accentDim")
    addColor("Header text",      "headerText")
    addColor("Hover glow",       "accentBright")
    addColor("Sort arrow",       "sortArrow")
    addFont("Header font",       "headerFont", true, true)
    addSlider("Header font size","headerFontSize", 8, 22, true)

    sectionTitle("Columns")
    for _, c in ipairs(COLUMN_DEFS) do
        addColumnSlider(c.title, c.key, 40, 300)
    end

    sectionTitle("Rows · Backgrounds")
    addColor("Row 1 (odd)",      "rowA")
    addColor("Row 2 (even)",     "rowB")
    addColor("Realm row",        "rowRealm")
    addColor("Account row",      "rowAccount")
    addColor("Totals row",       "rowTotal")
    addColor("Row hover",        "rowHover")
    addColor("Row top-line",     "rowTopLine")

    sectionTitle("Rows · Sizing")
    addSlider("Row height",        "rowHeight", 16, 44, true)
    addSlider("Row spacing",       "rowStep",   17, 52, true)
    addSlider("Realm font size",   "realmFontSize",     8, 22, true)
    addFont("Realm font",          "realmFont", true, true)
    addSlider("Account font size", "accountFontSize",   8, 22, true)
    addFont("Account font",        "accountFont", true, true)
    addSlider("Character font size","characterFontSize", 8, 22, true)
    addFont("Character font",      "characterFont", true, true)
    addSlider("Totals font size",  "totalsFontSize",    8, 22, true)
    addFont("Totals font",         "totalsFont", true, true)
    addToggle("Alternating stripes","stripes", true)

    sectionTitle("Accent Bars")
    addColor("Realm accent",       "realmAccentBar")
    addColor("Account accent",     "accountAccentBar")
    addColor("Totals accent",      "totalsAccentBar")
    addColor("Character accent",   "characterAccentBar")
    addToggle("Class-colored character accents", "classColoredAccent")
    addSlider("Accent bar width",  "accentWidth", 0, 8, true)

    sectionTitle("Text · Rows")
    addColor("Realm name",       "ember")
    addColor("Account name",     "accountName")
    addColor("Totals text",      "totalsText")
    addColor("Soul Ash",         "soul")
    addColor("Location",         "loc")
    addColor("Low-level number", "dim")
    addColor("Level 80+",        "levelColor")
    addColor("LVL text — locked",   "wtLvlLocked")
    addColor("LVL text — unlocked", "wtLvlUnlocked")
    addColor("Reset Cost",       "costColor")
    addColor("Money",            "moneyColor")
    addColor("WT label",         "wtLabel")
    addColor("Name (custom)",    "nameColor")
    addToggle("Class-colored names", "classColoredNames")

    sectionTitle("Text · Window")
    addColor("Section headers",     "sectionHeaderText")
    addColor("Muted / hints",       "muted")
    addFont("Muted hints font",      "mutedFont", true, true)

    sectionTitle("Icons")
    addToggle("Show class icons", "showClassIcons")
    addSlider("Class icon size", "classIconSize", 10, 24, true)
    addSlider("WT icon size",    "wtIconSize",   14, 32, true)

    sectionTitle("Number Format")
    addToggle("Compact Reset Cost",     "formatResetCost")
    addToggle("Compact Soul Ash",       "formatSoulAsh")
    addToggle("Compact Money",          "formatMoney")
    addToggle("Money: gold only",       "moneyGoldOnly")

    sectionTitle("Tabs")
    addFont("Tabs text font",       "tabFont", true, true)
    addColor("Tab background",       "tabBg")
    addColor("Tab border",           "tabBorder")
    addColor("Tab text",             "tabText")
    addColor("Active tab background","tabActiveBg")
    addColor("Active tab border",    "tabActiveBorder")
    addColor("Active tab text",      "tabActiveText")
    addColor("Hover tab background", "tabHoverBg")
    addColor("Hover tab border",     "tabHoverBorder")
    addColor("Hover tab text",       "tabHoverText")

    sectionTitle("Buttons")
    addFont("Buttons text font", "buttonFont", true, true)
    addColor("Background",       "btnBg")
    addColor("Border",           "btnBorder")
    addColor("Hover bg",         "btnHoverBg")
    addColor("Hover border",     "btnHoverBorder")
    addColor("Text",             "btnText")

    sectionTitle("Danger Buttons (Reset / Close)")
    addFont("Danger buttons font", "dangerFont", true, true)
    addColor("Background",       "dangerBg")
    addColor("Border",           "dangerBorder")
    addColor("Hover bg",         "dangerHoverBg")
    addColor("Hover border",     "dangerHoverBorder")
    addColor("Text",             "dangerText")

    body:SetHeight(math.max(1, -widgetY + 20))

    -- Bottom action bar ----------------------------------------------------
    local saveNewBtn = CreateFlatButton(page3, 160, 26, "Save as New Custom", "default")
    saveNewBtn:SetPoint("BOTTOMLEFT", page3, "BOTTOMLEFT", 20, 20)
    saveNewBtn:SetScript("OnClick", function()
        if not addon.customDraft then return end
        local defaultName = addon.Themes:NextDefaultName()
        StaticPopupDialogs["ASH_SAVE_THEME"] = StaticPopupDialogs["ASH_SAVE_THEME"] or {
            text = "Name this custom theme:",
            button1 = OKAY, button2 = CANCEL, hasEditBox = true,
            OnShow = function(self, data)
                self.editBox:SetText(data or "Custom1")
                self.editBox:HighlightText(); self.editBox:SetFocus()
            end,
            OnAccept = function(self)
                local txt = self.editBox:GetText()
                if txt and txt ~= "" then
                    addon:SaveDraftAsNew(txt)
                    refreshCustomTab()
                    SelectTab(2)
                end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("ASH_SAVE_THEME", nil, nil, defaultName)
    end)

    local updateBtn = CreateFlatButton(page3, 140, 26, "Update Current", "default")
    updateBtn:SetPoint("BOTTOMLEFT", page3, "BOTTOMLEFT", 190, 20)
    updateBtn:SetScript("OnClick", function()
        local prev = addon.previousTheme
        local customs = addon.db.global.options.CustomThemes or {}
        if prev and customs[prev] then
            StaticPopupDialogs["ASH_UPD_CUSTOM"] = {
                text = 'Update custom theme "%s"?',
                button1 = OKAY, button2 = CANCEL,
                OnAccept = function(self, data)
                    addon:SaveDraftToExisting(data)
                    if refreshCustomTab then refreshCustomTab() end
                    -- SaveDraftToExisting wipes the draft; re-enter edit mode on
                    -- the freshly saved theme so the buttons & widgets keep
                    -- working while the user stays on this tab.
                    if refreshCustomizeTab then refreshCustomizeTab() end
                end,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("ASH_UPD_CUSTOM", customs[prev].name or prev, nil, prev)
        end
    end)

    StaticPopupDialogs["ASH_RESET_DRAFT_CONFIRM"] = {
        text = "Reset the current draft?\n\nAll unsaved changes made in the Customize tab will be lost.",
        button1 = YES, button2 = NO,
        OnAccept = function()
            local prev = addon.previousTheme
            addon:CancelDraft()
            addon:BeginDraft(prev)
            if addon.refreshCustomizeTab then addon.refreshCustomizeTab() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }

    local resetBtn = CreateFlatButton(page3, 120, 26, "Reset Draft", "danger")
    resetBtn:SetPoint("BOTTOMRIGHT", page3, "BOTTOMRIGHT", -20, 20)
    resetBtn:SetScript("OnClick", function()
        if not addon.customDraft then return end
        StaticPopup_Show("ASH_RESET_DRAFT_CONFIRM")
    end)
    resetBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset Draft", 1, 0.82, 0)
        GameTooltip:AddLine("|cFFFFFFFFDiscards all unsaved changes|r")
        GameTooltip:AddLine("|cFFFFFFFFmade in the Customize tab and|r")
        GameTooltip:AddLine("|cFFFFFFFFrestores the last saved version|r")
        GameTooltip:AddLine("|cFFFFFFFFof this theme.|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFF8C867DA confirmation prompt will appear.|r")
        GameTooltip:Show()
    end)
    resetBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    refreshCustomizeTab = function()
        if not addon.customDraft then addon:BeginDraft() end
        if not addon.customDraft then return end
        for _, refresh in ipairs(widgets) do refresh() end
        local prev = addon.previousTheme
        local isCustom = prev and addon.db.global.options.CustomThemes and addon.db.global.options.CustomThemes[prev]
        if isCustom then updateBtn:Enable(); updateBtn:Show()
        else updateBtn:Disable(); updateBtn:Hide() end
    end
    addon.refreshCustomizeTab = refreshCustomizeTab

    ----------------------------------------------------------------------
    -- Theme hook for the window itself
    ----------------------------------------------------------------------
    RegisterThemed(function()
        local a = T.accent
        cfg:SetBackdropColor(unpack(C.panel))
        if T.outerBorder then
            cfg:SetBackdropBorderColor(unpack(C.border))
        else
            cfg:SetBackdropBorderColor(0, 0, 0, 0)
        end
        Gradient(titleBar, T.titleLo, T.titleHi)
        title:SetText("Ashoholic Settings")
        title:SetTextColor(unpack(T.settingsTitleRGB))
        inner:SetBackdropBorderColor(unpack(C.bronze))
        if T.layout.innerBorder then inner:Show() else inner:Hide() end
        tabLine:SetVertexColor(a[1], a[2], a[3], 0.9)
        for _, fn in ipairs(texts) do fn() end
        for _, tab in ipairs(tabs) do StyleTab(tab) end
        if page1._refreshDD then page1._refreshDD() end
        if refreshCustomTab then refreshCustomTab() end
    end)

    refreshCustomTab()
    SelectTab(1)
    cfg:Show()

    ----------------------------------------------------------------------
    -- TAB 4 — Sync instructions
    ----------------------------------------------------------------------
    local page4 = NewPage()
    pages[4] = page4
    pageHeights[4] = 540

    local p4Scroll = CreateFrame("ScrollFrame", nil, page4)
    p4Scroll:SetPoint("TOPLEFT", 20, -12)
    p4Scroll:SetPoint("BOTTOMRIGHT", -20, 12)
    p4Scroll:EnableMouseWheel(true)
    p4Scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(Clamp(cur - delta * 30, 0, max))
    end)

    local p4Body = CreateFrame("Frame", nil, p4Scroll)
    p4Body:SetWidth(CFG_WIDTH - 60)
    p4Body:SetHeight(10)
    p4Scroll:SetScrollChild(p4Body)

    local p4y = 0
    local function syncLine(text, kind)
        p4y = p4y - 18
        local fs = p4Body:CreateFontString(nil, "OVERLAY",
            kind == "title" and "GameFontNormal" or "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 0, p4y)
        local wrap = fs:GetParent()
        Themed(fs, kind == "title" and "gold" or "muted", text)
        return fs
    end

    syncLine("FastSwap Setup", "title")
    syncLine("Launch Ebonhold with Ashoholic.bat at least once to install", "muted")
    syncLine("the character-selection hook. FastSwap will not switch until", "muted")
    syncLine("the hook is synced. Use the launcher again after game updates.", "muted")
    syncLine(" ")
    syncLine("Multi-Account Sync Setup", "title")
    syncLine(" ")
    syncLine("By default, the addon only shows characters from the account you are", "muted")
    syncLine("currently logged into. To see every account's characters in one roster,", "muted")
    syncLine("follow the steps below.", "muted")
    syncLine(" ")
    syncLine("1) Log into each account once, play briefly.", "title")
    syncLine("Each WoW account has its own folder in WTF\\Account\\. After logging", "muted")
    syncLine("into each account once with the addon installed, you'll have:", "muted")
    syncLine("  WTF\\Account\\<AccountName>\\SavedVariables\\Ashoholic.lua", "gold")
    syncLine(" ")
    syncLine("2) Rename your account group in the roster, then log out.", "title")
    syncLine("Right-click the header above your characters and give it a unique", "muted")
    syncLine("name (e.g. \"Main\" or \"Boxes\"). Do this on EACH account.", "muted")
    syncLine("You only need to do this step ONCE, but you can rename an", "muted")
    syncLine("account as many times as you want.", "muted")
    syncLine(" ")
    syncLine("3) Launch WoW with Ashoholic.bat.", "title")
    syncLine("Double-click Ashoholic.bat in this addon folder. It:", "muted")
    syncLine("  - reads every account's Ashoholic.lua", "muted")
    syncLine("  - merges the character lists", "muted")
    syncLine("  - launches the game", "muted")
    syncLine(" ")
    syncLine("4) Done.", "title")
    syncLine("Log into any account. All characters from all accounts appear in", "muted")
    syncLine("the roster, grouped under their own account headers.", "muted")
    syncLine(" ")
    syncLine("Notes:", "title")
    syncLine("- Deletions: shift+right-click a character row to remove it from THIS", "muted")
    syncLine("  account's file. To remove it from ALL accounts, repeat for each.", "muted")
    syncLine("- Backup: each Ashoholic.lua is copied to .lua.bak before merging.", "muted")
    syncLine("- Re-running: launch via Ashoholic.bat any time to sync again.", "muted")

    p4Body:SetHeight(math.max(1, -p4y + 20))
end