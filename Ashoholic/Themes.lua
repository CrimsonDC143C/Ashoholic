local addonName = ...
local addon = _G[addonName]

local LAYOUT_DEFAULTS = {
    rowHeight = 24, rowStep = 26, accentWidth = 3,
    innerBorder = true, stripes = true,
    fontSize = 12, headerFontSize = 12,
    realmFontSize = 12, accountFontSize = 12,
    characterFontSize = 12, totalsFontSize = 12,
    classIconSize = 14, wtIconSize = 22,
    titleFont = "Fonts\\MORPHEUS.TTF", titleSize = 20,
}

local DEFS = {
    { key="ember",      name="Ember & Ash",     desc="Warm bronze on charcoal.",        bg="0E0D0FFA", accent="D98529", accent2="FFD24A", gold="FFD24A", ember="FF8A2B", muted="8C867D", soul="6FE6DC", loc="D6CFC0", wtLvlLocked="FF5555", wtLvlUnlocked="88DD55" },
    { key="frost",      name="Frostbound",      desc="Icy blue steel.",                 bg="0A0E14FA", accent="4FB4E8", accent2="BFE9FF", gold="9FDCFF", ember="5CC8FF", muted="7F8FA0", soul="8CF0E6", loc="C9D6E2", wtLvlLocked="FF6666", wtLvlUnlocked="70E0A0" },
    { key="fel",        name="Fel Fire",        desc="Toxic green glow.",               bg="0A100AFA", accent="5CD630", accent2="B6FF5C", gold="B6FF5C", ember="7CE34A", muted="7F9078", soul="7DFFD0", loc="C8D8C0", glow=16, wtLvlLocked="FF5555", wtLvlUnlocked="7CE34A" },
    { key="void",       name="Void Walker",     desc="Deep purple shadows.",            bg="0D0A12FA", accent="9B5DE5", accent2="D8A8FF", gold="D8A8FF", ember="B27CFF", muted="8A7F99", soul="7FE6F0", loc="D2C8E0", wtLvlLocked="FF6B8A", wtLvlUnlocked="7FE8D0" },
    { key="blood",      name="Blood Crimson",   desc="Death Knight red.",               bg="100808FA", accent="D12E3A", accent2="FF8A7A", gold="FF9C8A", ember="FF4D4D", muted="947F7F", soul="6FE6DC", loc="E0C8C8", wtLvlLocked="FF4D4D", wtLvlUnlocked="6FE6DC" },
    { key="sunwell",    name="Sunwell",         desc="Gold and violet.",                bg="0F0B14FA", accent="E8B923", accent2="FFE680", gold="FFE680", ember="FFC53D", muted="9A8FA0", soul="8FE8FF", loc="E6DCC8", wtLvlLocked="FF6666", wtLvlUnlocked="B8F4A0" },
    { key="tide",       name="Tidecaller",      desc="Deep sea teal.",                  bg="08121AFA", accent="1FB5B0", accent2="7FF0E8", gold="7FF0E8", ember="33D0C8", muted="7B9399", soul="B8F4FF", loc="C5DCDD", wtLvlLocked="FF6666", wtLvlUnlocked="7FF0E8" },
    { key="grove",      name="Druid Grove",     desc="Mossy forest greens.",            bg="0C100AFA", accent="8FAF3C", accent2="D8E88A", gold="E3D98A", ember="B9CC4E", muted="8A9078", soul="7CE6C0", loc="D0D6BE", wtLvlLocked="E04A4A", wtLvlUnlocked="8FAF3C" },
    { key="slate",      name="Slate",           desc="Neutral grey, almost no glow.",   bg="101214FA", accent="8E9AA8", accent2="E0E6EC", gold="E6EBF0", ember="B5C0CC", muted="7C858F", soul="8FE0D8", loc="CDD3D9", glow=4, wtLvlLocked="E05555", wtLvlUnlocked="8FC99F" },
    { key="rose",       name="Rose Quartz",     desc="Soft pink on plum.",              bg="120A10FA", accent="E86BA6", accent2="FFB3D4", gold="FFB8D8", ember="FF7DB5", muted="9A7F8E", soul="8FF0E8", loc="EAD0DC", wtLvlLocked="FF7090", wtLvlUnlocked="9FE0A0" },
    { key="parchment",  name="Old Parchment",   desc="Aged leather and ink.",           bg="1A140DFA", accent="B8894A", accent2="F0D9A0", gold="F0D9A0", ember="D9A55B", muted="A08F72", soul="8FD8C8", loc="E8DCC0", body="F2E8D0", layout={ titleFont="Fonts\\FRIZQT__.TTF", titleSize=18 }, wtLvlLocked="C05050", wtLvlUnlocked="6EAA5E" },
    { key="magma",      name="Magma",           desc="Molten orange, thick accents.",   bg="120806FA", accent="FF5A1F", accent2="FFB347", gold="FFB347", ember="FF6A2B", muted="9A8070", soul="6FE6DC", loc="E8D4C0", glow=22, layout={ accentWidth=5 }, wtLvlLocked="FF5555", wtLvlUnlocked="88DD55" },
    { key="large",      name="Large Print",     desc="Bigger text, roomy rows.",        bg="0E0E10FA", accent="FFB000", accent2="FFD866", gold="FFD866", ember="FFB000", muted="9A9A9A", soul="6FE6DC", loc="E6E6E6", layout={ rowHeight=30, rowStep=33, fontSize=14, headerFontSize=14, accentWidth=4, realmFontSize=14, accountFontSize=14, characterFontSize=14, totalsFontSize=14 }, columnWidths={ name=180, level=60, wt=120, cost=130, ash=120, money=180, location=200 }, wtLvlLocked="FF5555", wtLvlUnlocked="88DD55" },
    { key="terminal",   name="Terminal",        desc="Green phosphor. Flat.",           bg="000000FA", accent="33FF66", accent2="33FF66", gold="33FF66", ember="22CC55", muted="1F8F3F", soul="66FFAA", loc="88FFAA", body="AAFFBB", glow=0, layout={ rowHeight=20, rowStep=21, accentWidth=1, innerBorder=false, stripes=false, titleFont="Fonts\\ARIALN.TTF", titleSize=18, fontSize=11, headerFontSize=11 }, wtLvlLocked="FF5555", wtLvlUnlocked="33FF66" },
    { key="midnight",   name="Midnight",        desc="Near-black, electric blue.",      bg="05070DFA", accent="3D6BFF", accent2="9DB5FF", gold="A8BCFF", ember="6F8FFF", muted="7A83A0", soul="6FE6DC", loc="C8D0E6", layout={ rowHeight=21, rowStep=22 }, wtLvlLocked="FF6B6B", wtLvlUnlocked="6FE6A0" },
    { key="ledger",     name="Ledger",          desc="Dense, tidy, thin accents.",      bg="0B0D10FA", accent="6FA8DC", accent2="FFD966", gold="CFE2F3", ember="6FA8DC", muted="7F8C99", soul="76D7C4", loc="C9D3DC", layout={ rowHeight=20, rowStep=21, accentWidth=2, stripes=false }, wtLvlLocked="CC5555", wtLvlUnlocked="76D7C4" },
}

local WHITE = { 1, 1, 1 }
local function RGB(hex)
    local r = tonumber(hex:sub(1,2),16)/255
    local g = tonumber(hex:sub(3,4),16)/255
    local b = tonumber(hex:sub(5,6),16)/255
    if #hex >= 8 then
        return { r, g, b, tonumber(hex:sub(7,8),16)/255 }
    end
    return { r, g, b }
end
local function Mix(a, b, t) return { a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t, a[3]+(b[3]-a[3])*t } end
local function WithAlpha(c, a) return { c[1], c[2], c[3], a or 1 } end
local function Code(hex)
    if not hex then return "|cFFFFFFFF" end
    if #hex >= 8 then
        -- Input is RRGGBBAA, output |cAARRGGBB so the alpha byte survives.
        return "|c" .. hex:sub(7,8) .. hex:sub(1,6)
    end
    return "|cFF" .. hex
end

-- HexOr now supports 8-char hex (RRGGBBAA) for alpha
local function HexOr(hex, default, alpha)
    if not hex then return default end
    if type(hex) == "table" then return hex end
    if #hex >= 8 then
        local c = RGB(hex:sub(1,6))
        local a = tonumber(hex:sub(7,8), 16) / 255
        return { c[1], c[2], c[3], a }
    end
    local c = RGB(hex)
    return { c[1], c[2], c[3], alpha or 1 }
end

local function AsPercent(v, fallback)
    if v == nil then return fallback end
    if v <= 1 then return v * 100 end
    return v
end

local function Build(def)
    -- Parse "bg" as a full hex string so an 8-char RRGGBBAA value carries
    -- its alpha through. 6-char hex values behave exactly as before
    -- (bgAlpha = 1), preserving existing themes' visuals.
    local bgParsed = HexOr(def.bg or "0E0D0F")
    local bg = { bgParsed[1], bgParsed[2], bgParsed[3] }
    local bgAlpha = bgParsed[4] or 1
    local accent = RGB(def.accent or "D98529")
    local accent2 = RGB(def.accent2 or def.accent or "FFD24A")

    local T = { key = def.key, name = def.name, desc = def.desc, isCustom = def.isCustom }

    -- Surface. "bg"'s own alpha (from the color picker) multiplies with the
    -- Panel-opacity slider, so both controls contribute.
    -- Background color's own alpha is the sole source of truth for panel
    -- transparency. Legacy panelAlpha no longer multiplies in, so a
    -- slider value of 40 really means 40% (not 39.2%), and 100 really
    -- means fully opaque.
    T.panel    = WithAlpha(bg, bgAlpha)
    T.rowA     = HexOr(def.rowA,     WithAlpha(Mix(bg, WHITE, 0.085)))
    T.rowB     = HexOr(def.rowB,     WithAlpha(Mix(bg, WHITE, 0.010)))
    T.rowRealm = HexOr(def.rowRealm, WithAlpha(Mix(bg, accent, 0.14)))
    T.rowAccount = HexOr(def.rowAccount, WithAlpha(Mix(bg, accent, 0.08)))
    T.rowTotal = HexOr(def.rowTotal, WithAlpha(Mix(bg, accent2, 0.075)))
    T.border   = HexOr(def.border,   { 0, 0, 0, 1 })
    T.bronze   = HexOr(def.bronze,   WithAlpha(Mix(bg, accent, 0.55)))

    T.accent       = accent
    T.accent2      = accent2
    T.accentDim    = HexOr(def.accentDim,    Mix(bg, accent, 0.70))
    T.accentBright = HexOr(def.accentBright, WithAlpha(Mix(accent, WHITE, 0.25), 0.10))

    T.rowHover   = HexOr(def.rowHover,   WithAlpha(Mix(accent, WHITE, 0.25), 0.06))
    T.rowTopLine = HexOr(def.rowTopLine, Mix(bg, accent, 0.70))
    T.sortArrow  = HexOr(def.sortArrow or def.accentBright, WithAlpha(Mix(accent, WHITE, 0.25), 1))

    -- Per-row-type accent bars (item 10, 22)
    T.realmAccentBar     = HexOr(def.realmAccentBar,     accent)
    T.accountAccentBar   = HexOr(def.accountAccentBar,   accent2)
    T.totalsAccentBar    = HexOr(def.totalsAccentBar,    accent2)
    T.characterAccentBar = HexOr(def.characterAccentBar, accent)
    T.classColoredAccent = def.classColoredAccent ~= false

    T.titleLo      = HexOr(def.titleLo,      WithAlpha(Mix(bg, accent, 0.06)))
    T.titleHi      = HexOr(def.titleHi,      WithAlpha(Mix(bg, accent, 0.20)))
    T.sliderBg     = HexOr(def.sliderBg,     WithAlpha(Mix(bg, WHITE, 0.04)))
    T.sliderBorder = HexOr(def.sliderBorder, WithAlpha(Mix(bg, accent, 0.30)))

    local glowPct = AsPercent(def.glow, 13) / 100
    T.glow = { accent[1], accent[2], accent[3], glowPct }

    local gold = def.gold or "FFD24A"
    T.goldRGB         = RGB(gold)
    T.titleRGB        = RGB(def.titleText        or gold)
    T.settingsTitleRGB = RGB(def.settingsTitleText or gold)
    T.soulRGB         = RGB(def.soul or "6FE6DC")
    T.body            = RGB(def.body or "FFFFFF")

    T.text = {
        gold         = Code(gold),
        titleText    = Code(def.titleText        or gold),
        settingsTitleText = Code(def.settingsTitleText or gold),
        headerText   = Code(def.headerText       or gold),   -- ONLY column headers
        sectionHeaderText = Code(def.sectionHeaderText or def.headerText or gold),  -- Customize section titles
        totalsText   = Code(def.totalsText       or gold),
        ember        = Code(def.ember            or "FF8A2B"),
        muted        = Code(def.muted            or "8C867D"),
        soul         = Code(def.soul             or "6FE6DC"),
        loc          = Code(def.loc              or "D6CFC0"),
        dim          = Code(def.dim              or "B8B2A8"),
        nameColor    = Code(def.nameColor        or "FFFFFF"),
        levelColor   = Code(def.levelColor       or gold),
        costColor    = Code(def.costColor        or gold),
        moneyColor   = Code(def.moneyColor       or def.body or "FFFFFF"),
        wtLabel      = Code(def.wtLabel          or "FF8A2B"),
        accountName  = Code(def.accountName      or "FF8A2B"),
        wtLvlLocked  = Code(def.wtLvlLocked      or "FF5555"),
        wtLvlUnlocked = Code(def.wtLvlUnlocked   or "66DD66"),
    }

    -- RGB(A) tables for SetTextColor — carry alpha through to the widget.
    T.emberRGB         = RGB(def.ember or "FF8A2B")
    T.mutedRGB         = RGB(def.muted or "8C867D")
    T.locRGB           = RGB(def.loc or "D6CFC0")
    T.dimRGB           = RGB(def.dim or "B8B2A8")
    T.headerRGB        = RGB(def.headerText or gold)
    T.sectionHeaderRGB = RGB(def.sectionHeaderText or def.headerText or gold)
    T.totalsRGB        = RGB(def.totalsText or gold)
    T.nameRGB          = RGB(def.nameColor or "FFFFFF")
    T.levelRGB         = RGB(def.levelColor or gold)
    T.costRGB          = RGB(def.costColor or gold)
    T.moneyRGB         = RGB(def.moneyColor or def.body or "FFFFFF")
    T.wtLabelRGB       = RGB(def.wtLabel or "FF8A2B")
    T.accountNameRGB   = RGB(def.accountName or "FF8A2B")
    T.wtLvlLockedRGB   = RGB(def.wtLvlLocked or "FF5555")
    T.wtLvlUnlockedRGB = RGB(def.wtLvlUnlocked or "66DD66")


    T.btn = {
        default = {
            bg          = HexOr(def.btnBg,          WithAlpha(Mix(bg, accent, 0.12))),
            border      = HexOr(def.btnBorder,      WithAlpha(Mix(bg, accent, 0.45))),
            hoverBg     = HexOr(def.btnHoverBg,     WithAlpha(Mix(bg, accent, 0.25))),
            hoverBorder = HexOr(def.btnHoverBorder, WithAlpha(accent)),
            text        = def.btnText and RGB(def.btnText) or Mix(T.goldRGB, WHITE, 0.15),
        },
        danger = {
            bg          = HexOr(def.dangerBg,          { 0.18, 0.07, 0.07, 1 }),
            border      = HexOr(def.dangerBorder,      { 0.50, 0.15, 0.15, 1 }),
            hoverBg     = HexOr(def.dangerHoverBg,     { 0.32, 0.09, 0.09, 1 }),
            hoverBorder = HexOr(def.dangerHoverBorder, { 0.90, 0.25, 0.20, 1 }),
            text        = def.dangerText and RGB(def.dangerText) or { 1.00, 0.60, 0.55 },
        },
    }

    T.tabBg           = HexOr(def.tabBg,           WithAlpha(Mix(bg, accent, 0.12)))
    T.tabBorder       = HexOr(def.tabBorder,       WithAlpha(Mix(bg, accent, 0.45)))
    T.tabActiveBg     = HexOr(def.tabActiveBg,     WithAlpha(Mix(bg, accent, 0.25)))
    T.tabActiveBorder = HexOr(def.tabActiveBorder, WithAlpha(accent))
    T.tabText         = RGB(def.tabText       or "E6E0D0")
    T.tabActiveText   = RGB(def.tabActiveText or "FFFFFF")
    -- NEW: hover state (item 11)
    T.tabHoverBg      = HexOr(def.tabHoverBg,      WithAlpha(Mix(bg, accent, 0.18)))
    T.tabHoverBorder  = HexOr(def.tabHoverBorder,  WithAlpha(Mix(accent, WHITE, 0.30)))
    T.tabHoverText    = RGB(def.tabHoverText or "FFFFFF")

    T.outerBorder = def.outerBorder ~= false  -- item 23

    -- Number format toggles (item 8)
    T.formatResetCost = def.formatResetCost or false
    T.formatSoulAsh   = def.formatSoulAsh   or false
    T.formatMoney     = def.formatMoney     or false
    T.moneyGoldOnly   = def.moneyGoldOnly   or false

    T.classColoredNames = def.classColoredNames ~= false
    T.showClassIcons    = def.showClassIcons    ~= false

    T.layout = {}
    for k, v in pairs(LAYOUT_DEFAULTS) do T.layout[k] = v end
    if def.layout then for k, v in pairs(def.layout) do T.layout[k] = v end end
    if def.layout and def.layout.fontDelta and not def.layout.fontSize then
        T.layout.fontSize = 12 + def.layout.fontDelta
    end
    -- Backwards compat: old single fontSize -> all four new ones
    if def.layout and def.layout.fontSize and
       not (def.layout.realmFontSize or def.layout.accountFontSize or
            def.layout.characterFontSize or def.layout.totalsFontSize) then
        T.layout.realmFontSize     = T.layout.fontSize
        T.layout.accountFontSize   = T.layout.fontSize
        T.layout.characterFontSize = T.layout.fontSize
        T.layout.totalsFontSize    = T.layout.fontSize
    end

    T.numberFormat = T.formatSoulAsh  -- legacy alias
    T.columnWidths = def.columnWidths  -- optional per-theme column widths

    return T
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------
local Themes = { list = DEFS, byKey = {}, default = "ember" }
addon.Themes = Themes
for _, def in ipairs(DEFS) do Themes.byKey[def.key] = def end

local cache = {}
function Themes:Invalidate(key) if key then cache[key] = nil else cache = {} end end

function Themes:GetDef(key)
    if not key then key = self.default end
    if self.byKey[key] then return self.byKey[key] end
    local o = addon.db and addon.db.global and addon.db.global.options
    local customs = o and o.CustomThemes
    if customs and customs[key] then return customs[key] end
    return self.byKey[self.default]
end

function Themes:Get(key)
    local def = self:GetDef(key)
    local ck = def.key or key or self.default
    if not cache[ck] then cache[ck] = Build(def) end
    return cache[ck]
end

function addon:GetTheme()
    local o = addon.db and addon.db.global and addon.db.global.options
    return Themes:Get(o and o.Theme)
end

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = DeepCopy(v) end
    return out
end
Themes.DeepCopy = DeepCopy

function Themes:EnsureLayout(def)
    def.layout = def.layout or {}
    for k, v in pairs(LAYOUT_DEFAULTS) do
        if def.layout[k] == nil then def.layout[k] = v end
    end
    return def.layout
end

function Themes:GetCustoms()
    local o = addon.db and addon.db.global and addon.db.global.options
    local customs = (o and o.CustomThemes) or {}
    for key, def in pairs(customs) do
        local dirty = false
        if not def.key or def.key ~= key then
            def.key = key
            dirty = true
        end
        if not def.name or def.name == "" then
            local num = key:match("^custom_(%d+)$")
            def.name = num and ("Custom" .. num) or ("Custom " .. key)
            dirty = true
        end

        -- Normalize booleans/numbers so BeginDraft always reads non-nil values.
        -- We derive from the CURRENT built palette so the migration preserves
        -- whatever the user was actually seeing (no visual regression).
        local built = Build(def)
        if def.classColoredNames  == nil then def.classColoredNames  = built.classColoredNames;  dirty = true end
        if def.showClassIcons     == nil then def.showClassIcons     = built.showClassIcons;     dirty = true end
        if def.classColoredAccent == nil then def.classColoredAccent = built.classColoredAccent; dirty = true end
        if def.outerBorder        == nil then def.outerBorder        = built.outerBorder;        dirty = true end
        if def.formatResetCost    == nil then def.formatResetCost    = built.formatResetCost;    dirty = true end
        if def.formatSoulAsh      == nil then def.formatSoulAsh      = built.formatSoulAsh;      dirty = true end
        if def.formatMoney        == nil then def.formatMoney        = built.formatMoney;        dirty = true end
        if def.moneyGoldOnly      == nil then def.moneyGoldOnly      = built.moneyGoldOnly;      dirty = true end
        if def.panelAlpha ~= 100 then def.panelAlpha = 100; dirty = true end
        if def.glow == nil then def.glow = 13; dirty = true
        elseif def.glow > 0 and def.glow < 1 then def.glow = def.glow * 100; dirty = true end
        if def.layout and def.layout.stripes     == nil then def.layout.stripes     = built.layout.stripes;     dirty = true end
        if def.layout and def.layout.innerBorder == nil then def.layout.innerBorder = built.layout.innerBorder; dirty = true end
        if def.wtLvlLocked   == nil then def.wtLvlLocked   = "FF5555"; dirty = true end
        if def.wtLvlUnlocked == nil then def.wtLvlUnlocked = "66DD66"; dirty = true end

        if dirty then
            self.byKey[key] = def
            self:Invalidate(key)
        end
    end
    return customs
end

function Themes:GetCustomOrder()
    local o = addon.db and addon.db.global and addon.db.global.options
    local order = o and o.CustomThemeOrder
    if not order then
        order = {}
        for k in pairs(self:GetCustoms()) do table.insert(order, k) end
        table.sort(order)
        if o then o.CustomThemeOrder = order end
    end
    return order
end

function Themes:ListCustoms()
    local customs = self:GetCustoms()
    local order = self:GetCustomOrder()
    local starred, unstarred, seen = {}, {}, {}
    for _, k in ipairs(order) do
        local d = customs[k]
        if d and not seen[k] then
            seen[k] = true
            if d.starred then table.insert(starred, d) else table.insert(unstarred, d) end
        end
    end
    for k, d in pairs(customs) do
        if not seen[k] then table.insert(unstarred, d) end
    end
    local out = {}
    for _, d in ipairs(starred) do table.insert(out, d) end
    for _, d in ipairs(unstarred) do table.insert(out, d) end
    return out
end
function Themes:SaveCustom(key, def)
    local o = addon.db.global.options
    o.CustomThemes = o.CustomThemes or {}
    o.CustomThemeOrder = o.CustomThemeOrder or {}
    self:EnsureLayout(def)
    def.key = key; def.isCustom = true

    -- Normalize booleans so BeginDraft can inherit them reliably
    if def.classColoredNames  == nil then def.classColoredNames  = true  end
    if def.showClassIcons     == nil then def.showClassIcons     = true  end
    if def.classColoredAccent == nil then def.classColoredAccent = true  end
    if def.outerBorder        == nil then def.outerBorder        = true  end
    if def.formatResetCost    == nil then def.formatResetCost    = false end
    if def.formatSoulAsh      == nil then def.formatSoulAsh      = false end
    if def.formatMoney        == nil then def.formatMoney        = false end
    if def.moneyGoldOnly      == nil then def.moneyGoldOnly      = false end
    def.panelAlpha = 100
    if def.glow == nil then def.glow = 13
    elseif def.glow > 0 and def.glow < 1 then def.glow = def.glow * 100 end
    if def.layout and def.layout.stripes     == nil then def.layout.stripes     = true end
    if def.layout and def.layout.innerBorder == nil then def.layout.innerBorder = true end
    if def.wtLvlLocked   == nil then def.wtLvlLocked   = "FF5555" end
    if def.wtLvlUnlocked == nil then def.wtLvlUnlocked = "66DD66" end

    if not def.name or def.name == "" then
        local num = key:match("^custom_(%d+)$")
        def.name = num and ("Custom" .. num) or ("Custom " .. key)
    end
    o.CustomThemes[key] = def
    self.byKey[key] = def
    local found = false
    for _, k in ipairs(o.CustomThemeOrder) do if k == key then found = true break end end
    if not found then table.insert(o.CustomThemeOrder, key) end
    self:Invalidate(key)
end
function Themes:DeleteCustom(key)
    local o = addon.db.global.options
    if o.CustomThemes then o.CustomThemes[key] = nil end
    if o.CustomThemeOrder then
        for i, k in ipairs(o.CustomThemeOrder) do
            if k == key then table.remove(o.CustomThemeOrder, i) break end
        end
    end
    self.byKey[key] = nil
    self:Invalidate(key)
    if o.Theme == key then addon:ApplyTheme(self.default) end
end
function Themes:RenameCustom(key, newName)
    local o = addon.db.global.options
    if o.CustomThemes and o.CustomThemes[key] then
        o.CustomThemes[key].name = newName
        if self.byKey[key] then self.byKey[key].name = newName end
        self:Invalidate(key)
    end
end
function Themes:ToggleStar(key)
    local o = addon.db.global.options
    if o.CustomThemes and o.CustomThemes[key] then
        o.CustomThemes[key].starred = not o.CustomThemes[key].starred
        if self.byKey[key] then self.byKey[key].starred = o.CustomThemes[key].starred end
    end
end
function Themes:GenerateKey()
    local n = 1
    while self:GetCustoms()["custom_" .. n] or self.byKey["custom_" .. n] do n = n + 1 end
    return "custom_" .. n
end
function Themes:NextDefaultName()
    local customs = self:GetCustoms()
    local n = 1
    while true do
        local name = "Custom" .. n
        local taken = false
        for _, d in pairs(customs) do if d.name == name then taken = true break end end
        if not taken then return name end
        n = n + 1
    end
end