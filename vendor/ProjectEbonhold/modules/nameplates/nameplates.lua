-- nameplates.lua -- WoW-style nameplate reskin, retroported to 3.3.5.
--
-- The stock 3.3.5 nameplate (name + a bare health bar, small grey text, no
-- health value) is hard to read at a glance. This reskins it to look closer
-- to modern WoW: a bold name, an exact "12,345  68%" health readout, a level
-- badge (off by default) colored by difficulty, and a cast bar with the
-- spell's icon -- while staying readable at any UI scale, since every fill
-- AND border is a solid-color WHITE8X8 tint (see WHITE8X8 below and
-- BuildFlatBorderStrips) rather than a texture -- a textured border was
-- tried and shimmered visibly on a moving plate (sub-pixel sampling of
-- detail that isn't there in a flat color), confirmed live across multiple
-- textures and position fixes; not revisited.
--
-- Structure (verified against this exact client via ElvUI's WotLK nameplate
-- port, modules/Nameplates/Nameplates.lua:573-574 -- this is the real,
-- long-standing Blizzard NamePlateTemplate layout, not something specific to
-- this server):
--   plate:GetChildren() -> Health (StatusBar), CastBar (StatusBar)
--   plate:GetRegions()  -> Threat, Border, CastBarBorder, CastBarShield,
--                          CastBarIcon, Highlight, Name, Level, BossIcon,
--                          RaidIcon, EliteIcon
-- This client additionally sets plate.unit to a real resolvable unit token
-- (verified live, e.g. "nameplate1") -- not documented/expected for stock
-- 3.3.5, but present here, so UnitClass/UnitClassification/UnitCastingInfo/
-- UnitChannelInfo work for ANY plate, not just target/mouseover. The cast bar
-- is built from UnitCastingInfo/UnitChannelInfo(unit) rather than the native
-- CastBar widget -- nothing proves the engine drives that widget's value for
-- units other than target/mouseover (see GetUnitCastData). All Unit API
-- reads are wrapped in SafeCall and degrade gracefully if a specific plate's
-- token isn't resolvable at a given moment (e.g. right after creation).

local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
local NP = {}
ProjectEbonhold.Nameplates = NP

-- -------------------------------------------------------------- tunables ----
local WHITE8X8  = "Interface\\Buttons\\WHITE8X8"   -- flat 1px texture, tinted via
                                                     -- VertexColor -- crisp fill at
                                                     -- any scale, nothing to blur
local SKULL_TEX = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
-- New-plate discovery only (values refresh every frame regardless). Was
-- dropped to 0.1s under the theory that fast detection was only needed to
-- avoid a friendly-plate-hidden flash (a feature since removed) -- wrong:
-- ANY freshly created plate sits fully native/unsuppressed (no overlay, no
-- alpha suppression -- RegisterPlate hasn't run yet) for the entire gap
-- between scans, regardless of that removed feature. At 0.1s that's up to
-- 100ms of the plain native nameplate visibly flashing before the reskin
-- snaps in -- reported live, reverted back to 0. The freeze this project
-- was chasing came from the per-EXISTING-plate cost in UpdatePlate's own
-- loop (which scales with plate count, matching what was actually
-- reported), not from this scan -- see SetNativeAlpha/health-value-change-
-- guard comments for those fixes, which stay in place.
-- =========================================================== KILL SWITCH ====
-- The nameplate reskin is OFF while the in-combat freeze reports are being
-- worked through. It shipped on 2026-08-07, in the same rollout as the client
-- DLL swap, which is why "it started with the new DLLs" and "it started with
-- the new nameplates" describe the same day -- so it has to be ruled in or out
-- separately from the DLL fixes, not alongside them.
--
-- Turning it off here rather than through the saved setting is deliberate:
-- ProjectEbonholdDB.nameplatesEnabled is already persisted as true on every
-- account that has logged in since, so flipping the DEFAULT would change
-- nothing for the players actually reporting the freezes. With this true, the
-- driver never starts: no WorldFrame scan, no overlays, no per-frame work at
-- all, and the client's own nameplates are left completely untouched.
--
-- To re-enable: set this to false. The optimisations below (throttled scan,
-- per-tick cached settings, allocation-free name path) stay in place either way.
local MODULE_DISABLED = true

-- Stays 0 (every frame) for the reason documented directly above -- any delay
-- here is a window in which a brand-new plate is visibly un-reskinned. The
-- scan's per-frame COST is dealt with in ScanForNewPlates instead, which now
-- does no work at all on the frames where nothing new can exist.
local SCAN_INTERVAL = 0

-- ----------------------------------------------------------------- state ----
local plates = {}   -- [nativePlateFrame] = plate data

-- Refreshed ONCE per driver tick (see StartDriver), read by UpdatePlate for
-- every plate. These were previously recomputed per plate per frame: four
-- Setting() lookups (each a global fetch + a service method call) and a
-- pcall'd UnitGUID("target"), multiplied by however many plates are on screen.
-- With 30-40 plates up in a fight that is well over a thousand redundant calls
-- every single frame, all of them producing the same answer.
local tickEnabled    = true
local tickCastBar    = true
local tickClassColor = true
local tickShowLevel  = false
local tickTargetGUID = nil

local function Setting(key, default)
    local svc = _G.ProjectEbonholdOptionsService
    if svc and svc.GetSetting then
        local v = svc:GetSetting(key)
        if v ~= nil then return v end
    end
    return default
end

-- ============================================================= formatting ---
local function FormatNumber(n)
    n = math.floor((n or 0) + 0.5)
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000    then return string.format("%dK",  math.floor(n / 1000)) end
    return tostring(n)
end

local function FormatHealthText(cur, maxv)
    local mode = Setting("nameplatesHealthFormat", "BOTH")
    if mode == "OFF" or not cur or not maxv or maxv <= 0 then return "" end
    local pct = math.floor(cur / maxv * 100 + 0.5)
    if mode == "PERCENT" then return pct .. "%" end
    if mode == "VALUE"   then return FormatNumber(cur) end
    return FormatNumber(cur) .. "  " .. pct .. "%"
end

-- Truncates `text` to "..." once it no longer fits `maxWidth`, measured with
-- the fontString's own GetStringWidth() (binary search over the cut point --
-- same measuring technique already proven reliable in this client by the
-- MOTD banner's word-wrap code in ebonhold_glue.lua). Without this, a long
-- name runs straight into the health text on the right with no gap.
local function TruncateToWidth(fontString, text, maxWidth)
    fontString:SetText(text)
    if not maxWidth or maxWidth <= 0 or fontString:GetStringWidth() <= maxWidth then return end
    local lo, hi, best = 1, #text, ""
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local candidate = text:sub(1, mid) .. "..."
        fontString:SetText(candidate)
        if fontString:GetStringWidth() <= maxWidth then
            best = candidate
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    fontString:SetText(best)
end

-- Wraps a WoW API call in pcall so a signature mismatch or missing function
-- degrades to "no data" instead of an OnUpdate error (this client's exact
-- Unit API surface for plate.unit is new ground -- see file header).
local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h, i
end

-- Difficulty color vs the player's level, using the client's own classifier
-- when available; a manual fallback covers builds where the signature differs.
local function GetLevelColor(level)
    local a, b, c = SafeCall(GetCreatureDifficultyColor, level)
    if a then
        if type(a) == "table" then return a.r, a.g, a.b end
        if b then return a, b, c end
    end
    local diff = level - (UnitLevel("player") or level)
    if     diff <= -5 then return 0.5, 0.5, 0.5
    elseif diff <= -3 then return 0.25, 0.75, 0.25
    elseif diff <=  2 then return 1, 1, 0
    elseif diff <=  4 then return 1, 0.5, 0
    else                   return 1, 0.1, 0.1 end
end

-- Preferred path: plate.unit resolves for ANY plate on this client (see file
-- header), so a normal UnitClass() works everywhere, not only target/mouseover.
local function GetUnitClassColor(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    local _, class = SafeCall(UnitClass, unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return nil
end

-- Fallback for when plate.unit isn't resolvable: only works when a real unit
-- token happens to point at the same name (target/mouseover).
local function FindClassColorByName(name)
    if not name then return nil end
    for _, token in ipairs({ "target", "mouseover" }) do
        if UnitExists(token) and UnitIsPlayer(token) and UnitName(token) == name then
            local _, class = UnitClass(token)
            local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if c then return c.r, c.g, c.b end
        end
    end
    return nil
end

-- Cast/channel data straight from the unit token (plate.unit resolves for
-- ANY plate on this client -- see file header). This turned out to be more
-- reliable than reading the native CastBar widget: nothing actually proves
-- the engine drives that widget's value for units other than target/
-- mouseover (ElvUI's own WotLK port builds its cast bar the same way, from
-- UnitCastingInfo/UnitChannelInfo, rather than trusting the native widget).
-- name/rank/text/texture/startTime/endTime/isTradeSkill/castID/notInterruptible
-- has been the stable UnitCastingInfo shape since Vanilla; UnitChannelInfo is
-- the same minus castID. startTime/endTime are milliseconds.
-- Verified live (crash log): position 3 is "text" (often a copy of name),
-- NOT texture -- skipping only one field before texture shifted everything
-- one slot over (endTime silently received the real startTime, a number, so
-- it didn't error there; startTime received the icon PATH, a string, which
-- is what actually crashed the duration subtraction below).
local function GetUnitCastData(unit)
    if not unit or not UnitExists(unit) then return nil end
    local name, _, _, texture, startTime, endTime, _, _, notInterruptible = SafeCall(UnitCastingInfo, unit)
    if name then return name, texture, startTime, endTime, notInterruptible end
    name, _, _, texture, startTime, endTime, _, notInterruptible = SafeCall(UnitChannelInfo, unit)
    if name then return name, texture, startTime, endTime, notInterruptible end
    return nil
end

-- Joins every native name/title FontString's current text into one display
-- string (a unit can have a name + a separate sub-name/title region -- see
-- ClassifyPlate). Re-reads text live each call rather than caching, since
-- the same pooled plate frame gets reused for different units over time.
-- Called for every plate every frame, and its result is compared against a
-- cached copy -- so on the overwhelmingly common single-FontString plate the
-- old unconditional {} + table.concat allocated a table and a string per plate
-- per frame purely to rebuild a value that had not changed. Fast-path it.
local function CombinedName(nameFSList)
    if not nameFSList or #nameFSList == 0 then return nil end
    if #nameFSList == 1 then
        local only = nameFSList[1]:GetText()
        if not only or only == "" then return nil end
        return only
    end
    local parts = {}
    for i = 1, #nameFSList do
        local text = nameFSList[i]:GetText()
        if text and text ~= "" then parts[#parts + 1] = text end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

-- ============================================================ backdrop border
-- Still used for innerRing/levelBadge (ApplyBackdropFilled below) -- their
-- edge is thin and mostly hidden under other layers, never reported as
-- shimmering. UI-Tooltip-Border's art is a soft rounded shape.
--
-- w.border/w.castBorder do NOT use a textured edge -- every texture tried
-- there shimmered/crawled on a moving plate (a detailed edge sampled at a
-- continuously shifting sub-pixel offset): UI-Tooltip-Border first, then
-- Common-Input-Border (a plainer texture, on the theory that less detail
-- would alias less -- it didn't, and looked worse). Ruled out separately:
-- Z-order/frame-level oscillation (confirmed absent via a live debug print)
-- and sub-pixel position itself (pixel-snapping w.overlay's anchor -- tried,
-- removed, and re-confirmed live afterward that plain UI-Tooltip-Border
-- STILL shimmers with the snap gone, so the snap was never the cause). The
-- only thing that renders cleanly with no shimmer is a FLAT color -- see
-- BuildFlatBorderStrips below -- because a flat color has no internal
-- detail for sub-pixel sampling to reveal in the first place, regardless of
-- texture choice. Confirmed live across multiple textures and position
-- fixes; settled, not revisiting again.
local BORDER_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"

-- Same, plus a tintable solid fill (for the level badge, which needs a
-- difficulty-colored background rather than just an outline).
local function ApplyBackdropFilled(frame, edgeSize)
    frame:SetBackdrop({
        bgFile = WHITE8X8,
        edgeFile = BORDER_EDGE,
        edgeSize = edgeSize,
        insets = { left = edgeSize / 3, right = edgeSize / 3, top = edgeSize / 3, bottom = edgeSize / 3 },
    })
end

-- Flat-color border built from 4 thin WHITE8X8 strips instead of a textured
-- edge -- see the comment above for why. Sharp corners, not rounded; that
-- trade was confirmed acceptable (the alternative, textured borders, all
-- shimmered on movement -- rejected outright, not just aesthetically).
local function BuildFlatBorderStrips(parent)
    local strips = {}
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do
        local tex = parent:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(WHITE8X8)
        strips[key] = tex
    end
    return strips
end

local function LayoutFlatBorderStrips(strips, frame, thickness)
    strips.top:ClearAllPoints()
    strips.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    strips.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    strips.top:SetHeight(thickness)

    strips.bottom:ClearAllPoints()
    strips.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    strips.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    strips.bottom:SetHeight(thickness)

    strips.left:ClearAllPoints()
    strips.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    strips.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    strips.left:SetWidth(thickness)

    strips.right:ClearAllPoints()
    strips.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    strips.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    strips.right:SetWidth(thickness)
end

local function SetFlatBorderColor(strips, r, g, b, a)
    a = a or 1
    strips.top:SetVertexColor(r, g, b, a)
    strips.bottom:SetVertexColor(r, g, b, a)
    strips.left:SetVertexColor(r, g, b, a)
    strips.right:SetVertexColor(r, g, b, a)
end

-- Glossy horizontal shading (darker left, lighter right) instead of a flat
-- tint, matching the reference image's bars instead of a solid block color.
-- Native reaction colors are near-fully saturated (e.g. solid yellow for
-- neutral). The bar fill is WHITE8X8 -- a FLAT texture with no shading of
-- its own (see WHITE8X8's own comment) -- so painting that color at full
-- intensity reads as a solid neon block; the stock bar looks softer at the
-- SAME underlying color because its art asset has shading baked into the
-- texture itself, which a flat tint has no equivalent of. Dampening overall
-- intensity (not just declining to boost it, which still left it reading as
-- flashy) is what actually closes that gap while keeping the same hue.
local function ApplyGradient(statusBar, r, g, b)
    local bright, dark = 0.7, 0.4
    local rightR, rightG, rightB = r * bright, g * bright, b * bright
    local leftR, leftG, leftB = r * dark, g * dark, b * dark
    statusBar:GetStatusBarTexture():SetGradientAlpha("HORIZONTAL", leftR, leftG, leftB, 1, rightR, rightG, rightB, 1)
end

-- ======================================================= plate detection ---
local function IsLikelyNamePlate(frame)
    if frame:GetName() then return false end
    if frame:GetObjectType() ~= "Frame" then return false end
    local child1 = select(1, frame:GetChildren())
    return child1 ~= nil and child1.GetObjectType and child1:GetObjectType() == "StatusBar"
end

local function ClassifyPlate(plate)
    local healthBar, castBar = plate:GetChildren()
    if not healthBar or healthBar:GetObjectType() ~= "StatusBar" then return nil end

    local regions = { plate:GetRegions() }
    -- Positional (verified structure -- see file header): 1 threat, 2 border,
    -- 3 castBarBorder, 4 castBarShield, 5 castBarIcon, 6 highlight, 7 name,
    -- 8 level, 9 bossIcon, 10 raidIcon, 11 eliteIcon. Kept for the texture
    -- regions, which have no content to classify by.
    local castBarShield, castBarIcon, highlight = regions[4], regions[5], regions[6]
    local bossIcon, eliteIcon = regions[9], regions[11]

    -- Name/title can be split across MORE than one native FontString (a name
    -- + a sub-name/title) -- the positional "slot 7" alone was silently
    -- dropping whichever one didn't land there. Collect every non-empty,
    -- non-numeric FontString found ANYWHERE in the region list instead, so
    -- nothing vanishes with no replacement once SetNativeAlpha blanks every
    -- native region.
    local levelFS
    local nameFSList = {}
    for i = 1, #regions do
        local region = regions[i]
        if region:GetObjectType() == "FontString" then
            local text = region:GetText()
            if text and (text:match("^%d+%+?$") or text == "??") then
                levelFS = levelFS or region
            elseif text and text ~= "" then
                nameFSList[#nameFSList + 1] = region
            end
        end
    end

    return {
        healthBar = healthBar, castBar = castBar,
        castBarShield = castBarShield, castBarIcon = castBarIcon,
        nameFSList = nameFSList, levelFS = levelFS,
        bossIcon = bossIcon, eliteIcon = eliteIcon, highlight = highlight,
    }
end

-- Hides EVERY native child frame + region unconditionally (rather than a
-- curated subset) so nothing native can ever show through the overlay,
-- regardless of plate type (player/NPC nameplates have been seen to differ
-- slightly in which regions are populated). Our own overlay is ALSO a child
-- of plate (CreateFrame(..., plate) in BuildOverlay), so plate:GetChildren()
-- would include and hide it too -- it's excluded once, at cache time (see
-- RegisterPlate), not filtered here every call.
--
-- Must run EVERY tick, not just once on the hide transition: at least the
-- "Threat" region (native aggro glow) and "Highlight" (native mouseover
-- glow) are DRIVEN LIVE by the client -- it shows/re-alphas them itself in
-- response to combat/threat state and mouseover, independent of anything
-- this addon does. A one-time SetAlpha(0) gets silently overridden the next
-- time the engine touches those regions, bleeding a native orange threat
-- glow (or mouseover highlight) around the reskin. Continuously reasserting
-- alpha=0 is what keeps them suppressed.
--
-- The lists themselves ARE static per-plate (a template-based native frame
-- never gains/loses children or regions at runtime, only their Shown/alpha/
-- text state changes) -- data.nativeChildren/nativeRegions are captured
-- ONCE in RegisterPlate, so this only re-touches known objects every tick
-- instead of re-querying GetChildren()/GetRegions() (each of which builds a
-- fresh table on the C-API side) every frame for every plate.
local function SetNativeAlpha(data, a)
    local children = data.nativeChildren
    if children then
        for i = 1, #children do children[i]:SetAlpha(a) end
    else
        local overlay = data.widgets and data.widgets.overlay
        local liveChildren = { data.plate:GetChildren() }
        for i = 1, #liveChildren do
            if liveChildren[i] ~= overlay then liveChildren[i]:SetAlpha(a) end
        end
    end
    local regions = data.nativeRegions
    if regions then
        for i = 1, #regions do regions[i]:SetAlpha(a) end
    else
        local liveRegions = { data.plate:GetRegions() }
        for i = 1, #liveRegions do liveRegions[i]:SetAlpha(a) end
    end
end

-- ================================================================ overlay ---
local function BuildOverlay(plate)
    local overlay = CreateFrame("Frame", nil, plate)
    overlay:SetFrameLevel(math.min(plate:GetFrameLevel() + 5, 120))

    -- health row. The border itself toggles between dim grey (not selected)
    -- and gold (targeted/moused) -- see UpdatePlate.
    local border = CreateFrame("Frame", nil, overlay)
    border:SetFrameLevel(overlay:GetFrameLevel() + 1)
    border.flatBorder = BuildFlatBorderStrips(border)

    -- A StatusBar's fill can't itself be corner-masked (no texture masking in
    -- this client), so it always has sharp corners -- but a rounded frame
    -- directly behind it, inset from `border` by only 1-2px, keeps those
    -- corners tucked in tight without needing a big gap. Matters most at
    -- low health%, where the unfilled remainder is this rounded bg, not the
    -- (still sharp-cornered) fill.
    local innerRing = CreateFrame("Frame", nil, overlay)
    innerRing:SetFrameLevel(overlay:GetFrameLevel() + 2)

    local bar = CreateFrame("StatusBar", nil, overlay)
    bar:SetFrameLevel(overlay:GetFrameLevel() + 3)
    bar:SetStatusBarTexture(WHITE8X8)
    -- anchor points set in ApplyLayout, once the actual border inset is known

    local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", bar, "LEFT", 3, 0)
    nameText:SetJustifyH("LEFT")

    local healthText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    healthText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    healthText:SetJustifyH("RIGHT")

    local levelBadge = CreateFrame("Frame", nil, overlay)
    levelBadge:SetFrameLevel(overlay:GetFrameLevel() + 1)
    local levelText = levelBadge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelText:SetAllPoints(levelBadge)
    levelText:SetJustifyH("CENTER")
    levelText:SetJustifyV("MIDDLE")
    local skullIcon = levelBadge:CreateTexture(nil, "OVERLAY")
    skullIcon:SetTexture(SKULL_TEX)
    skullIcon:SetAllPoints(levelBadge)
    skullIcon:Hide()

    -- cast row (below the health row) -- mirrors the native CastBar child,
    -- which the client drives for any visible casting unit, not just your
    -- target (same as health -- see file header).
    local castBorder = CreateFrame("Frame", nil, overlay)
    castBorder:SetFrameLevel(overlay:GetFrameLevel() + 1)
    castBorder.flatBorder = BuildFlatBorderStrips(castBorder)

    local castBarWidget = CreateFrame("StatusBar", nil, overlay)
    castBarWidget:SetFrameLevel(overlay:GetFrameLevel() + 2)
    castBarWidget:SetStatusBarTexture(WHITE8X8)
    -- anchor points set in ApplyLayout, once the actual border inset is known
    castBarWidget:SetStatusBarColor(1, 0.7, 0)

    local castBg = castBarWidget:CreateTexture(nil, "BACKGROUND")
    castBg:SetAllPoints(castBarWidget)
    castBg:SetTexture(WHITE8X8)
    castBg:SetVertexColor(0.08, 0.08, 0.08, 0.9)

    local castText = castBarWidget:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    castText:SetPoint("LEFT", castBarWidget, "LEFT", 2, 0)
    castText:SetJustifyH("LEFT")

    local castIcon = overlay:CreateTexture(nil, "ARTWORK")
    castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim the default icon border

    return {
        overlay = overlay, border = border, innerRing = innerRing, bar = bar,
        nameText = nameText, healthText = healthText,
        levelBadge = levelBadge, levelText = levelText, skullIcon = skullIcon,
        castBorder = castBorder, castBar = castBarWidget, castText = castText, castIcon = castIcon,
    }
end

-- (Re)apply size/font settings -- cheap SetPoint/SetFont calls, safe to call
-- on registration and whenever an option changes (see NP.ReapplyAll). Anchors
-- are set ONCE here (not every frame) -- a live SetPoint relationship tracks
-- the native frame's position automatically as the engine moves it. Anchored
-- to the NAME region's top (not the health bar's) so the reskinned block
-- keeps the same overall top edge as the native plate did -- the native name
-- sits above its bar, but this reskin draws the name INSIDE the bar, so
-- anchoring to the bar alone would sit the whole block noticeably lower,
-- down toward the unit's model.
local function ApplyLayout(data)
    local w = data.widgets
    local barWidth   = Setting("nameplatesBarWidth", 130)
    local barHeight  = Setting("nameplatesBarHeight", 14)
    local fontSize   = Setting("nameplatesFontSize", 12)
    local castHeight = math.max(9, math.floor(barHeight * 0.85))

    w.border:ClearAllPoints()
    w.border:SetPoint("TOP", w.overlay, "TOP", 0, 0)
    w.border:SetWidth(barWidth + 6)
    w.border:SetHeight(barHeight + 6)
    -- Strip thickness is fixed (no longer changes on select) -- the border
    -- itself becomes the highlight -- not a second ring drawn on top -- so
    -- the color swing has to be big enough to read clearly on its own (see
    -- UpdatePlate: dim grey <-> white). data.borderEdgeBase is kept as the
    -- overall reference scale (used below for innerRing/ring inset too);
    -- the actual visible strip is a third of that, matching the apparent
    -- thickness a 9-sliced edge would render at.
    data.borderEdgeBase = math.min(math.floor((barHeight + 6) / 2) - 1, math.max(6, math.floor((barHeight + 6) * 0.35)))
    local borderThickness = math.max(2, math.floor(data.borderEdgeBase / 3))
    LayoutFlatBorderStrips(w.border.flatBorder, w.border, borderThickness)
    SetFlatBorderColor(w.border.flatBorder, 0.4, 0.4, 0.4, 1)   -- dim grey by default; turns white when targeted (see UpdatePlate)

    -- innerRing starts exactly where the flat border strip ends.
    local ringInset = borderThickness
    w.innerRing:ClearAllPoints()
    w.innerRing:SetPoint("TOPLEFT", w.border, "TOPLEFT", ringInset, -ringInset)
    w.innerRing:SetPoint("BOTTOMRIGHT", w.border, "BOTTOMRIGHT", -ringInset, ringInset)
    ApplyBackdropFilled(w.innerRing, math.max(4, math.floor(ringInset)))
    w.innerRing:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    w.innerRing:SetBackdropBorderColor(0.08, 0.08, 0.08, 0.9)

    w.bar:ClearAllPoints()
    w.bar:SetPoint("TOPLEFT", w.innerRing, "TOPLEFT", 1, -1)
    w.bar:SetPoint("BOTTOMRIGHT", w.innerRing, "BOTTOMRIGHT", -1, 1)

    w.castBorder:ClearAllPoints()
    w.castBorder:SetPoint("TOP", w.border, "BOTTOM", 0, -2)
    w.castBorder:SetWidth(barWidth + 4)
    w.castBorder:SetHeight(castHeight + 4)
    local castEdge = math.min(math.floor((castHeight + 4) / 2) - 1, math.max(6, math.floor((castHeight + 4) * 0.35)))
    local castThickness = math.max(2, math.floor(castEdge / 3))
    LayoutFlatBorderStrips(w.castBorder.flatBorder, w.castBorder, castThickness)
    SetFlatBorderColor(w.castBorder.flatBorder, 1, 1, 1, 1)

    local castInset = castThickness
    w.castBar:ClearAllPoints()
    w.castBar:SetPoint("TOPLEFT", w.castBorder, "TOPLEFT", castInset, -castInset)
    w.castBar:SetPoint("BOTTOMRIGHT", w.castBorder, "BOTTOMRIGHT", -castInset, castInset)

    w.castIcon:ClearAllPoints()
    w.castIcon:SetPoint("RIGHT", w.castBorder, "LEFT", -2, 0)
    w.castIcon:SetWidth(castHeight + 4)
    w.castIcon:SetHeight(castHeight + 4)

    w.overlay:SetWidth(barWidth + 6)
    w.overlay:SetHeight(barHeight + 6 + 2 + castHeight + 4)
    w.overlay:ClearAllPoints()
    local topAnchor = (data.nameFSList and data.nameFSList[1]) or data.healthBar
    w.overlay:SetPoint("TOP", topAnchor, "TOP", 0, 4)

    -- GameFontNormal's default color is WoW's gold/yellow UI text color, not
    -- white -- it was only chosen (over GameFontHighlight) for its drop
    -- shadow instead of a hard black outline. Force white explicitly here;
    -- nameText overrides this dynamically for class color (see UpdatePlate).
    w.nameText:SetFont(STANDARD_TEXT_FONT, fontSize)
    w.nameText:SetWidth(math.max(20, barWidth * 0.6))
    w.nameText:SetTextColor(1, 1, 1)
    w.healthText:SetFont(STANDARD_TEXT_FONT, math.max(8, fontSize - 2))
    w.healthText:SetTextColor(1, 1, 1)
    w.castText:SetFont(STANDARD_TEXT_FONT, math.max(8, fontSize - 3))
    w.castText:SetTextColor(1, 1, 1)

    -- Wider than tall: a plain square is too cramped for 3-character content
    -- like "80+" (elite suffix) once the backdrop's own edge insets eat into
    -- the available space.
    local badgeHeight = barHeight + 8
    local badgeWidth  = badgeHeight + 10
    w.levelBadge:SetWidth(badgeWidth)
    w.levelBadge:SetHeight(badgeHeight)
    w.levelBadge:ClearAllPoints()
    w.levelBadge:SetPoint("RIGHT", w.border, "LEFT", -8, 0)
    ApplyBackdropFilled(w.levelBadge, 7)
    w.levelBadge:SetBackdropBorderColor(0, 0, 0, 1)
    w.levelText:SetFont(STANDARD_TEXT_FONT, math.max(8, fontSize - 2))
    w.levelText:SetTextColor(1, 1, 1)
end

local function RegisterPlate(plate)
    local c = ClassifyPlate(plate)
    if not c then return end   -- not fully built yet; retry next scan
    c.plate = plate
    c.widgets = BuildOverlay(plate)
    -- Cache the native child/region lists ONCE, right after the overlay is
    -- added as a child (so the overlay is already excluded here, permanently
    -- -- see SetNativeAlpha). A template-based native frame never gains or
    -- loses children/regions at runtime, so this list is valid for the
    -- plate's whole lifetime.
    local overlay = c.widgets.overlay
    c.nativeChildren = {}
    local children = { plate:GetChildren() }
    for i = 1, #children do
        if children[i] ~= overlay then c.nativeChildren[#c.nativeChildren + 1] = children[i] end
    end
    c.nativeRegions = { plate:GetRegions() }
    plates[plate] = c
    ApplyLayout(c)
end

-- Runs every frame (SCAN_INTERVAL = 0), so it must cost nothing on the frames
-- where there is nothing to find -- and that is almost all of them.
--
-- It used to unconditionally build `{ WorldFrame:GetChildren() }`: a fresh Lua
-- table holding every child WorldFrame has, rebuilt 60 times a second, growing
-- with the number of plates alive -- i.e. worst exactly during a fight. Then,
-- for each frame not yet registered, another GetChildren() call inside
-- IsLikelyNamePlate. That allocation rate is what feeds the Lua GC the garbage
-- it eventually has to stop the world to collect, which is what a player
-- experiences as the client freezing at random in combat.
--
-- GetNumChildren() is a plain integer read that allocates nothing. The client
-- creates each nameplate as a NEW child of WorldFrame and then pools and
-- reuses it for the rest of the session, so "the child count changed" is
-- precisely "a frame exists that was never seen before" -- and while it has
-- not changed, there is provably nothing here to discover. Detection stays
-- instant; the cost on a steady-state frame drops to one integer compare.
local lastWorldChildCount = -1
local rescanPending       = false
local function ScanForNewPlates()
    local n = WorldFrame:GetNumChildren()
    if n == lastWorldChildCount and not rescanPending then return end
    lastWorldChildCount = n
    rescanPending = false

    local children = { WorldFrame:GetChildren() }
    for i = 1, #children do
        local frame = children[i]
        if not plates[frame] and IsLikelyNamePlate(frame) then
            RegisterPlate(frame)
            -- RegisterPlate bails out when the client has not finished
            -- building the plate yet ("retry next scan"). Without re-arming
            -- here, the count-unchanged fast path above would never look at
            -- that frame again and it would stay un-reskinned forever.
            if not plates[frame] then rescanPending = true end
        end
    end
end

-- =========================================================== per-frame update
local function RestoreNative(data)
    SetNativeAlpha(data, 1)
    data.widgets.overlay:Hide()
    -- Plates are pooled/reused by the client for different units over time.
    -- Clear the change-detection caches so the next UpdatePlate always
    -- treats it as a fresh paint instead of possibly comparing the NEW
    -- unit's values against the PREVIOUS occupant's and skipping a real
    -- change because the numbers happened to coincide (e.g. both at 100%).
    data.lastHealthCur, data.lastHealthMax, data.lastHealthMin = nil, nil, nil
    data.lastIsFriendly, data.lastIsSelected = nil, nil
end

local function UpdateCastBar(data, unit, unitOk)
    local w = data.widgets
    if not tickCastBar or not unitOk then
        w.castBorder:Hide(); w.castBar:Hide(); w.castIcon:Hide()
        return
    end

    local name, texture, startTime, endTime, notInterruptible = GetUnitCastData(unit)
    if not name then
        w.castBorder:Hide(); w.castBar:Hide(); w.castIcon:Hide()
        return
    end
    w.castBorder:Show(); w.castBar:Show()

    -- Defensive: only do arithmetic on values that are actually numbers.
    -- Already got burned once by an off-by-one in this API's field order.
    local progress = 0
    if type(startTime) == "number" and type(endTime) == "number" then
        local duration = endTime - startTime
        if duration > 0 then
            local elapsed = (GetTime() * 1000) - startTime
            progress = math.max(0, math.min(1, elapsed / duration))
        end
    end
    w.castBar:SetMinMaxValues(0, 1)
    w.castBar:SetValue(progress)

    if notInterruptible then
        ApplyGradient(w.castBar, 0.6, 0.6, 0.6)
    else
        ApplyGradient(w.castBar, 1, 0.7, 0)
    end

    if type(texture) == "string" then
        w.castIcon:SetTexture(texture)
        w.castIcon:Show()
    else
        w.castIcon:Hide()
    end

    w.castText:SetText(name)
end

-- Frame LEVEL (unlike position via SetPoint) is a one-time absolute number,
-- not a live relationship -- it was only ever set once, at BuildOverlay time.
-- The client changes a nameplate's own frame level dynamically (raised when
-- targeted/moused, per the native "Nameplate Mouseover/Stacking" behavior),
-- so a level baked in at registration goes stale the moment that happens,
-- desyncing our whole internal stack (border can end up rendering behind
-- something it shouldn't). Cheap to re-sync every tick, unlike SetBackdrop.
local function SyncFrameLevels(data)
    local w = data.widgets
    local base = math.min(data.plate:GetFrameLevel() + 5, 120)
    if w.overlay:GetFrameLevel() == base then return end
    -- Confirmed via a live debug print (since removed) that this level does
    -- NOT oscillate during movement -- ruling out a Z-order/frame-level
    -- cause for the border shimmer; see BORDER_EDGE's comment for what it
    -- actually is.
    w.overlay:SetFrameLevel(base)
    w.border:SetFrameLevel(base + 1)
    w.innerRing:SetFrameLevel(base + 2)
    w.bar:SetFrameLevel(base + 3)
    w.levelBadge:SetFrameLevel(base + 1)
    w.castBorder:SetFrameLevel(base + 1)
    w.castBar:SetFrameLevel(base + 2)
end

local function UpdatePlate(data)
    local plate = data.plate
    if not tickEnabled or not plate:IsShown() then
            RestoreNative(data)
            return
        end
        SyncFrameLevels(data)

        -- The plate can be caught by the scanner a frame or two before the client
        -- finishes populating every region (name/level text in particular) --
        -- retry classification for whatever's still missing instead of being
        -- stuck with nil forever from a registration that ran too early. Capped:
        -- some plate types legitimately never get a level FontString, and
        -- without a cap that plate would re-run ClassifyPlate (a full
        -- GetRegions() walk + pattern match) every single tick forever.
        if (not data.nameFSList or #data.nameFSList == 0 or not data.levelFS) and (data.classifyRetries or 0) < 30 then
            data.classifyRetries = (data.classifyRetries or 0) + 1
            local c = ClassifyPlate(plate)
            if c then
                if not data.nameFSList or #data.nameFSList == 0 then data.nameFSList = c.nameFSList end
                data.levelFS       = data.levelFS       or c.levelFS
                data.castBarShield = data.castBarShield or c.castBarShield
                data.castBarIcon   = data.castBarIcon   or c.castBarIcon
                data.bossIcon      = data.bossIcon      or c.bossIcon
                data.eliteIcon     = data.eliteIcon     or c.eliteIcon
                data.highlight     = data.highlight     or c.highlight
            end
        end

        local w = data.widgets
        local unit = plate.unit
        local unitOk = unit and UnitExists(unit)
        local r, g, b = data.healthBar:GetStatusBarColor()
        -- GetStatusBarColor() can transiently return nil right as a plate is
        -- created/reused, before the client finishes coloring it. An unguarded
        -- `g > r` with a nil operand errors -- and since that happens BEFORE
        -- overlay:Show()/SetNativeAlpha below, a plate that errors here every
        -- tick never becomes visible again (native already hidden from an
        -- earlier successful tick, overlay never shown this one): permanently
        -- invisible, not just miscolored.
        r, g, b = r or 1, g or 0, b or 0
        -- UnitIsUnit(unit, "target") looked like the robust signal (plate.unit
        -- resolves on this client -- see file header), but debug output proved
        -- it matches by something coarser than true object identity: EVERY
        -- plate showing the same NAME as the actual target (e.g. 3 different
        -- "Forest Spider" mobs on screen at once) read as UnitIsUnit(...,
        -- "target") == true simultaneously, not just the one actually targeted.
        -- GUID is the correct unique-identity comparison; SafeCall in case
        -- UnitGUID has its own quirks on this client, same as everything else
        -- touching this client's non-standard Unit API surface (see file header).
        -- The target's own GUID is the same value for every plate on screen,
        -- so it is resolved once per tick in the driver (tickTargetGUID)
        -- instead of being re-fetched -- through a pcall -- once per plate.
        local isTarget = false
        if unitOk and tickTargetGUID then
            local unitGUID = SafeCall(UnitGUID, unit)
            isTarget = unitGUID ~= nil and unitGUID == tickTargetGUID
        end
    local isSelected = isTarget

    -- No addon-side hide/show logic anymore -- only ever reacts to the
    -- native plate's own IsShown() (see top of this function). isFriendly is
    -- kept only for the curated color tint below, not for hiding anything.
    local isFriendly = g > r + 0.15 and g > b + 0.15   -- margin, not a bare >, so near-equal/grey/white colors can't tip into "friendly"

    w.overlay:Show()
    -- Position tracking is the plain live SetPoint set once in ApplyLayout
    -- (WoW's own layout engine follows the moving native plate automatically
    -- from there -- no per-tick repositioning needed). A pixel-rounding
    -- correction was tried here to fight border texture shimmer, but with
    -- the border now a flat color (see BORDER_EDGE's comment -- flat colors
    -- can't shimmer regardless of position, so the rounding no longer buys
    -- anything) it turned out to be the wrong tradeoff on its own: snapping
    -- to whole pixels every tick introduced a visible judder/vibration as
    -- the rounded value flipped between two adjacent pixels whenever the
    -- true position hovered near a rounding boundary. Reported live; removed.
    -- Must run every tick -- see SetNativeAlpha's comment (native "Threat"/
    -- "Highlight" regions are live-driven by the client and need continuous
    -- suppression, not a one-time hide). Cheap now: iterates a cached list
    -- instead of re-querying GetChildren()/GetRegions() every tick.
    SetNativeAlpha(data, 0)

    local minv, maxv = data.healthBar:GetMinMaxValues()
    local cur = data.healthBar:GetValue()
    -- StatusBar value/color/text only actually change when the unit takes
    -- damage or heals -- most plates sit unchanged for many consecutive
    -- ticks. Skip SetValue/gradient recompute/text formatting entirely when
    -- nothing moved since last tick instead of redoing it 60x/sec per plate.
    if data.lastHealthCur ~= cur or data.lastHealthMax ~= maxv or data.lastHealthMin ~= minv or data.lastIsFriendly ~= isFriendly then
        data.lastHealthCur, data.lastHealthMax, data.lastHealthMin = cur, maxv, minv
        data.lastIsFriendly = isFriendly
        w.bar:SetMinMaxValues(minv or 0, maxv or 1)
        w.bar:SetValue(cur or 0)
        -- A curated shade for friendly (rather than the raw native green,
        -- which reads as too neon/flashy even after the general desaturation
        -- below).
        if isFriendly then
            ApplyGradient(w.bar, 0.08, 0.55, 0.12)
        else
            ApplyGradient(w.bar, r or 1, g or 0, b or 0)
        end
        w.healthText:SetText(FormatHealthText(cur, maxv))
    end

    local plateName = CombinedName(data.nameFSList)
    if plateName then
        if data.lastNameRaw ~= plateName then
            data.lastNameRaw = plateName
            TruncateToWidth(w.nameText, plateName, w.nameText:GetWidth())
        end
        local cr, cg, cb
        if tickClassColor then
            if unitOk then cr, cg, cb = GetUnitClassColor(unit) end
            -- Bare name only (nameFSList[1]) for this lookup -- UnitName()
            -- returns just the name, never the name+subtitle combo shown in
            -- plateName, so matching against the combined string would never hit.
            if not cr and data.nameFSList and data.nameFSList[1] then
                cr, cg, cb = FindClassColorByName(data.nameFSList[1]:GetText())
            end
        end
        w.nameText:SetTextColor(cr or 1, cg or 1, cb or 1)
    end

    -- isSelected (target-only, see above) was already computed earlier
    -- (needed for the friendly-hide check before this point). The border is
    -- always visible; targeting recolors THAT SAME border (dim grey ->
    -- white) -- not a second ring drawn on top of it. Thickness stays fixed
    -- either way.
    -- Selected-state (targeted/moused) rarely flips tick-to-tick -- gate the
    -- whole recolor+refade behind an actual change instead of reapplying the
    -- same border color and 4 SetAlpha calls every frame for every plate.
    if data.lastIsSelected ~= isSelected then
        data.lastIsSelected = isSelected
        if isSelected then
            SetFlatBorderColor(w.border.flatBorder, 1, 1, 1, 1)   -- white: big enough a swing from dim grey to read clearly
        else
            SetFlatBorderColor(w.border.flatBorder, 0.4, 0.4, 0.4, 1)
        end

        -- Fade every plate's HEALTH ROW that isn't the focused one (target or
        -- mouseover) -- dim is the default baseline, not conditional on having
        -- an actual target, so the same contrast applies with or without one.
        -- Cast bar is deliberately excluded: an enemy casting something worth
        -- interrupting matters regardless of whether it's your current target,
        -- so it stays fully visible (SetAlpha on `overlay` would have dimmed it
        -- too, since it's a child -- alpha compounds down the frame tree).
        local healthAlpha = isSelected and 1 or 0.45
        w.border:SetAlpha(healthAlpha)
        w.innerRing:SetAlpha(healthAlpha)
        w.bar:SetAlpha(healthAlpha)
        w.levelBadge:SetAlpha(healthAlpha)
    end

    if tickShowLevel and data.levelFS then
        local levelStr = data.levelFS:GetText() or ""
        local levelNum = tonumber(levelStr:match("%d+")) or UnitLevel("player") or 1
        local classification = unitOk and SafeCall(UnitClassification, unit)
        local isBoss, isElite
        if classification then
            isBoss  = classification == "worldboss"
            isElite = classification == "elite" or classification == "rareelite"
        else
            isBoss  = data.bossIcon  and data.bossIcon:IsShown()
            isElite = data.eliteIcon and data.eliteIcon:IsShown()
        end
        w.levelBadge:Show()
        if isBoss then
            w.levelText:Hide(); w.skullIcon:Show()
            w.levelBadge:SetBackdropColor(0.55, 0, 0, 0.95)
        else
            w.skullIcon:Hide(); w.levelText:Show()
            w.levelText:SetText(isElite and (levelStr .. "+") or levelStr)
            local lr, lg, lb = GetLevelColor(levelNum)
            w.levelBadge:SetBackdropColor(lr, lg, lb, 0.95)
        end
    else
        w.levelBadge:Hide()
    end

    UpdateCastBar(data, unit, unitOk)
end

-- ============================================================ public API ----
-- Called from the options panel when width/height/font-size sliders change --
-- those are baked into each plate's widgets at registration time (not re-read
-- every frame, to avoid churning SetFont/SetWidth on every plate every tick).
function NP.ReapplyAll()
    for _, data in pairs(plates) do ApplyLayout(data) end
end

-- Enable/disable takes effect on the very next tick anyway (UpdatePlate reads
-- the live setting), so this just exists for symmetry with the options
-- checkbox pattern used by other modules (see QT.ApplyEnabled).
function NP.ApplyEnabled() end

-- ===================================================================== boot -
local driver
local function StartDriver()
    if MODULE_DISABLED then
        if EbonholdLog then
            EbonholdLog("nameplates: module disabled (MODULE_DISABLED), driver not started")
        end
        return
    end
    if driver then return end
    driver = CreateFrame("Frame")
    local sinceScan = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        sinceScan = sinceScan + (elapsed or 0)
        if sinceScan >= SCAN_INTERVAL then
            sinceScan = 0
            ScanForNewPlates()
        end
        -- Resolve everything that is per-TICK rather than per-PLATE exactly
        -- once, right here, before the loop below reads it N times.
        tickEnabled    = Setting("nameplatesEnabled", true)
        if not tickEnabled and not next(plates) then return end
        tickCastBar    = Setting("nameplatesCastBar", true)
        tickClassColor = Setting("nameplatesClassColor", true)
        tickShowLevel  = Setting("nameplatesShowLevel", false)
        tickTargetGUID = UnitExists("target") and SafeCall(UnitGUID, "target") or nil
        for _, data in pairs(plates) do UpdatePlate(data) end
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        StartDriver()
    end
end)
