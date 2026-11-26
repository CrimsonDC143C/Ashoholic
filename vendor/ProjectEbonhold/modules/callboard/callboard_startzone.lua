-- callboard_startzone.lua -- "Choose Your Starting Zone", the Call Board's Starting Zone tab.
--
-- The create screen's zone step (ebonhold.dll, ebonhold_glue.lua step 11), in game: the same eight
-- valleys and paintings, a radio and the name under each, the picked zone's painting behind. The
-- board always shows the tab (owner 2026-11-09: a tab, not a button); the grid takes the place of
-- the list and the panel. Travel works only in a start valley (board header field 8): elsewhere it
-- is greyed and a red line says so.
-- Travel sends REQUEST_CALLBOARD_START_ZONE and the server moves the character there, binds the
-- hearthstone there and keeps the choice for run resets (Ashendor::StartZone::Choose).
-- Ids = the server's StartZone ids.

local L, T = ProjectEbonhold.L, ProjectEbonhold.T
ProjectEbonhold = ProjectEbonhold or {}
local Callboard = ProjectEbonhold.Callboard
local Picker = {}
ProjectEbonhold.CallboardStartZone = Picker

-- art = credits painting (Interface\Glues\Credits\<art>1..8), 256-px tiles in 2 rows of `cols`.
-- Northshire, Coldridge and Sunstrider are stand-ins: the client has no painting of them.
local ZONES = {
    { name = "Northshire Valley", sub = "Elwynn Forest",   art = "ZulAman",          cols = 4 },
    { name = "Coldridge Valley",  sub = "Dun Morogh",      art = "GrizzlyHills2TGA", cols = 4 },
    { name = "Shadowglen",        sub = "Teldrassil",      art = "Darnasis",         cols = 3 },
    { name = "Ammen Vale",        sub = "Azuremyst Isle",  art = "Ddraenei_Start",   cols = 4 },
    { name = "Valley of Trials",  sub = "Durotar",         art = "Orccamp",          cols = 3 },
    { name = "Camp Narache",      sub = "Mulgore",         art = "Thunderbluff",     cols = 3 },
    { name = "Deathknell",        sub = "Tirisfal Glades", art = "TirisfallGlades",  cols = 3 },
    { name = "Sunstrider Isle",   sub = "Eversong Woods",  art = "Blood_Elf_One",    cols = 4 },
}
Picker.ZONES = ZONES

-- the board's content area (list + panel): 862 x 448 at (19, -74) of the board
local W, H = 862, 448
local CW, CH, STEP_X, STEP_Y, TOP = 190, 118, 206, 160, 46
local FONT = "Fonts\\FRIZQT__.TTF"
-- same assets and text style as the create screen (ebonhold_glue.lua CC_ASSETS / CCFont / RedButton)
local ASSETS = "Interface\\AddOns\\ProjectEbonhold\\assets\\"
local RED_BTN = ASSETS .. "128redbutton9sliced"
local TC_N, TC_P, TC_D = { 0.006, 0.916, 0.514, 0.756 }, { 0.006, 0.916, 0.260, 0.502 }, { 0.006, 0.916, 0.006, 0.248 }

local function Font(fs, size, r, g, b)
    fs:SetFont(FONT, size)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(r or 1, g or 1, b or 1)
end

local frame, cards, paintBackground, footer, travel, warning
local zsel, here = 1, 0

-- a credits painting cropped to cover a w x h box ("cover", centred) at (x0, y0) of `parent`
local function Painting(parent, layer)
    local tex = {}
    for i = 1, 8 do tex[i] = parent:CreateTexture(nil, layer) end
    return function(z, w, h, x0, y0)
        local s = math.max(w / (z.cols * 256), h / 512)
        local ox, oy, sz, n = (w - z.cols * 256 * s) / 2, (h - 512 * s) / 2, 256 * s, 0
        for r = 0, 1 do
            for c = 0, z.cols - 1 do
                n = n + 1
                local t, tx, ty = tex[n], ox + c * sz, oy + r * sz
                local vx0, vy0 = math.max(tx, 0), math.max(ty, 0)
                local vx1, vy1 = math.min(tx + sz, w), math.min(ty + sz, h)
                if vx1 - vx0 < 0.5 or vy1 - vy0 < 0.5 then
                    t:Hide()
                else
                    t:SetTexture("Interface\\Glues\\Credits\\" .. z.art .. n)
                    t:SetTexCoord((vx0 - tx) / sz, (vx1 - tx) / sz, (vy0 - ty) / sz, (vy1 - ty) / sz)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x0 + vx0, -(y0 + vy0))
                    t:SetWidth(vx1 - vx0)
                    t:SetHeight(vy1 - vy0)
                    t:Show()
                end
            end
        end
        for i = n + 1, 8 do tex[i]:Hide() end
    end
end

local function Refresh()
    if not frame then return end
    for i, b in ipairs(cards) do
        if i == zsel then
            b:SetInset(1, 0.82, 0, 0.8)
            b.radio:SetTexCoord(0.5, 1, 0, 1)
        else
            b:SetInset(0, 0, 0, 0.85)
            b.radio:SetTexCoord(0, 0.5, 0, 1)
        end
    end
    local z = ZONES[zsel]
    paintBackground(z, W, H, 0, 0)
    footer:SetText(T("You will start in |cffffd100{zone}|r, {sub}. Your hearthstone will be bound there.", { zone = L[z.name], sub = L[z.sub] })) -- zone names: display only
    if here > 0 then
        travel:Enable()
        warning:Hide()
    else
        travel:Disable()
        warning:Show()
    end
end

local function Create(board)
    if frame then return end
    frame = CreateFrame("Frame", nil, board)
    frame:SetWidth(W)
    frame:SetHeight(H)
    frame:SetPoint("TOPLEFT", board, "TOPLEFT", 19, -74)
    frame:EnableMouse(true)

    paintBackground = Painting(frame, "BACKGROUND")
    local dim = frame:CreateTexture(nil, "BORDER")
    dim:SetAllPoints(frame)
    dim:SetTexture(0, 0, 0, 0.65)

    local title = frame:CreateFontString(nil, "OVERLAY")
    Font(title, 22, 1, 0.82, 0)
    title:SetText(L["Choose Your Starting Zone"])
    title:SetPoint("TOP", frame, "TOP", 0, -12)

    footer = frame:CreateFontString(nil, "OVERLAY")
    Font(footer, 12)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 18)

    -- the tab is always there; outside a start valley it only shows where the player can use it
    warning = frame:CreateFontString(nil, "OVERLAY")
    Font(warning, 13, 1, 0.25, 0.25)
    warning:SetText(L["You can only change your starting zone while you are in a starting zone."])
    warning:SetPoint("BOTTOM", frame, "BOTTOM", 0, 44)

    cards = {}
    for i, z in ipairs(ZONES) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local b = CreateFrame("Button", nil, frame)
        b:SetWidth(CW)
        b:SetHeight(CH + 40)
        b:SetPoint("TOPLEFT", frame, "TOP", -(2 * STEP_X - (STEP_X - CW) / 2) + col * STEP_X, -(TOP + row * STEP_Y))
        Painting(b, "ARTWORK")(z, CW, CH, 0, 0)
        -- inset border: a soft shadow fading inward from each edge of the painting, plus a 1 px line
        b.inset = {}
        local function Edge(orient, a1, a2)
            local t = b:CreateTexture(nil, "OVERLAY")
            t:SetTexture(1, 1, 1, 1)
            t.orient, t.a1, t.a2 = orient, a1, a2
            b.inset[#b.inset + 1] = t
            return t
        end
        local IW = 14
        local e1 = Edge("VERTICAL", 0, 1)
        e1:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); e1:SetWidth(CW); e1:SetHeight(IW)
        local e2 = Edge("VERTICAL", 1, 0)
        e2:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -(CH - IW)); e2:SetWidth(CW); e2:SetHeight(IW)
        local e3 = Edge("HORIZONTAL", 1, 0)
        e3:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); e3:SetWidth(IW); e3:SetHeight(CH)
        local e4 = Edge("HORIZONTAL", 0, 1)
        e4:SetPoint("TOPLEFT", b, "TOPLEFT", CW - IW, 0); e4:SetWidth(IW); e4:SetHeight(CH)
        b.lines = {}
        for _, l in ipairs({ { 0, 0, CW, 1 }, { 0, -(CH - 1), CW, 1 }, { 0, 0, 1, CH }, { CW - 1, 0, 1, CH } }) do
            local t = b:CreateTexture(nil, "OVERLAY")
            t:SetPoint("TOPLEFT", b, "TOPLEFT", l[1], l[2])
            t:SetWidth(l[3])
            t:SetHeight(l[4])
            b.lines[#b.lines + 1] = t
        end
        function b:SetInset(r, g, bl, a)
            for _, t in ipairs(self.inset) do
                t:SetGradientAlpha(t.orient, r, g, bl, a * t.a1, r, g, bl, a * t.a2)
            end
            for _, t in ipairs(self.lines) do t:SetTexture(r * 0.6, g * 0.6, bl * 0.6, 0.95) end
        end
        b.radio = b:CreateTexture(nil, "OVERLAY")
        b.radio:SetTexture(ASSETS .. "charcreate_radio")
        b.radio:SetWidth(20)
        b.radio:SetHeight(20)
        b.label = b:CreateFontString(nil, "OVERLAY")
        Font(b.label, 13)
        b.label:SetJustifyH("LEFT")
        b.label:SetText(L[z.name]) -- display only
        b.sub = b:CreateFontString(nil, "OVERLAY")
        Font(b.sub, 10, 0.75, 0.75, 0.75)
        b.sub:SetJustifyH("LEFT")
        b.sub:SetText(L[z.sub]) -- display only
        local gw = 20 + 6 + math.max(b.label:GetStringWidth(), b.sub:GetStringWidth())
        b.radio:SetPoint("TOPLEFT", b, "TOPLEFT", (CW - gw) / 2, -(CH + 8))
        b.label:SetPoint("TOPLEFT", b.radio, "TOPRIGHT", 6, 1)
        b.sub:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -2)
        b:SetScript("OnClick", function()
            PlaySound("igMainMenuOptionCheckBoxOn")
            zsel = i
            Refresh()
        end)
        b:SetScript("OnEnter", function(self) if zsel ~= i then self:SetInset(0.35, 0.35, 0.4, 0.75) end end)
        b:SetScript("OnLeave", function() Refresh() end)
        cards[i] = b
    end

    -- the create screen's red button (its "Finish")
    travel = CreateFrame("Button", nil, frame)
    travel:SetWidth(140)
    travel:SetHeight(30)
    travel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 10)
    travel:SetNormalTexture(RED_BTN);   travel:GetNormalTexture():SetTexCoord(unpack(TC_N))
    travel:SetPushedTexture(RED_BTN);   travel:GetPushedTexture():SetTexCoord(unpack(TC_P))
    travel:SetDisabledTexture(RED_BTN); travel:GetDisabledTexture():SetTexCoord(unpack(TC_D))
    travel:SetHighlightTexture(RED_BTN)
    local hl = travel:GetHighlightTexture()
    hl:SetTexCoord(unpack(TC_N)); hl:SetBlendMode("BLEND"); hl:SetAlpha(0.3)
    local tfs = travel:CreateFontString(nil, "OVERLAY")
    Font(tfs, 13, 1, 0.82, 0)
    travel:SetFontString(tfs)
    tfs:ClearAllPoints(); tfs:SetPoint("CENTER", travel, "CENTER", 0, -1)
    travel:SetText(L["Travel"])
    travel:SetScript("OnClick", function() Callboard.ChooseStartZone(zsel) end)
    travel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Travel there now. It becomes your starting zone: your hearthstone is bound there and a new run starts you there."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    travel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:Hide()
end

-- Shows the grid inside the board `board` (its content area), on the valley the player stands
-- in (`valley`, a StartZone id) the first time it opens.
function Picker.Show(board, valley)
    local fresh = not frame
    Create(board)
    here = valley or 0
    if fresh or not frame:IsShown() then
        zsel = (here > 0 and here) or zsel
    end
    frame:Show()
    Refresh()
end

function Picker.Hide()
    if frame then frame:Hide() end
end

local FAIL_TEXT = {
    notvalley = L["You can only change your starting zone inside a starting zone."],
    combat    = L["You cannot do that while in combat."],
    dead      = L["You cannot do that while dead."],
    unknown   = L["Unknown starting zone."],
    cannot    = L["You cannot travel there right now."],
}

Callboard.OnChanged(function(event, payload)
    if event ~= "result" or payload.op ~= "startzone" then return end
    if not payload.ok then
        UIErrorsFrame:AddMessage(FAIL_TEXT[payload.reason] or T("Starting zone: {reason}", { reason = tostring(payload.reason) }), 1.0, 0.3, 0.3, 1.0)
        return
    end
    local z = ZONES[payload.zone]
    DEFAULT_CHAT_FRAME:AddMessage(T("|cFF66CCFF[Call Board]|r Your starting zone is now |cffffd100{zone}|r. Your hearthstone is bound there.", { zone = z and L[z.name] or "?" })) -- zone name: display only
    if ProjectEbonhold.CallboardUI and ProjectEbonhold.CallboardUI.Hide then
        ProjectEbonhold.CallboardUI.Hide()
    end
end)
