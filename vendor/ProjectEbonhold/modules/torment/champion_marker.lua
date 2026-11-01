-- champion_marker.lua -- an icon above the nameplate of a Torment champion.
--
-- Some champions read as ordinary monsters until they are pulled (playtest,
-- 2026-10-16): the server marks them with an aura and a size (TormentChampionMgr),
-- and this puts the "Champions" icon of the Torment frame (hardmode.lua) above
-- their nameplate, so their danger reads before the pull.
--
-- How a champion is told apart: its template entry is in 985000-989999
-- (TormentChampionMgr::ENTRY_FIRST/LAST, tools/torment/emit_champions.py) AND it
-- is rare-elite; its escort shares the entry block but not the rank. The entry
-- comes from the GUID (3.3.5 creature GUID: 0xF130, then 6 hex digits of entry,
-- then the counter). Not the aura: the client's UnitAura does not list the marks
-- (checked in game, 2026-10-16).
--
-- Which plate is whose: the client's AwesomeWotlk library gives every shown
-- nameplate a unit token ("nameplate1", "nameplate2"...) and C_NamePlate.
-- GetNamePlateForUnit(token). Without that library there are no tokens and the
-- module does nothing. The tokens are looked at 4 times a second, never every
-- frame; a plate is worked out again only when the unit behind it changes. Works
-- under ElvUI's nameplates and the stock ones alike (the icon is a child of the
-- client's plate frame, which both keep).

local ENTRY_FIRST, ENTRY_LAST = 985000, 989999
local ICON = "Interface\\Icons\\Ability_Warrior_Rampage"
local ICON_SIZE = 24
local TICK = 0.25          -- seconds between two looks at the plates
local MAX_TOKENS = 60      -- nameplate1 .. nameplateN probed per look

local markers = {}         -- [plate frame] = marker frame
local seen = {}            -- [plate frame] = true for the plates matched in this look

local function EntryOf(guid)
    if type(guid) ~= "string" or #guid < 18 then return nil end
    local high = guid:sub(3, 6):upper()
    if high ~= "F130" and high ~= "F150" then return nil end   -- creature, vehicle
    return tonumber(guid:sub(7, 12), 16)
end

local function MarkerOf(plate)
    local m = markers[plate]
    if m then return m end
    m = CreateFrame("Frame", nil, plate)
    m:SetFrameStrata("HIGH")
    m:SetWidth(ICON_SIZE)
    m:SetHeight(ICON_SIZE)
    m:SetPoint("BOTTOM", plate, "TOP", 0, 2)
    local t = m:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(m)
    t:SetTexture(ICON)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    m:Hide()
    markers[plate] = m
    return m
end

local function Look()
    local plates = C_NamePlate.GetNamePlates()
    local n = math.min(MAX_TOKENS, (plates and #plates or 0) + 10)
    for i = 1, n do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            local entry = EntryOf(guid)
            if entry and entry >= ENTRY_FIRST and entry <= ENTRY_LAST then
                local plate = C_NamePlate.GetNamePlateForUnit(unit)
                if plate then
                    local m = MarkerOf(plate)
                    if m.guid ~= guid then
                        m.guid = guid
                        m.champion = UnitClassification(unit) == "rareelite"
                    end
                    if m.champion then
                        seen[plate] = true
                        m:Show()
                    end
                end
            end
        end
    end
    for plate, m in pairs(markers) do
        if not seen[plate] and m:IsShown() then
            m:Hide()
            m.guid = nil
        end
        seen[plate] = nil
    end
end

if not (C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlateForUnit) then
    if EbonholdLog then EbonholdLog("champion_marker: no C_NamePlate in this client, champion icons off") end
    return
end

local driver = CreateFrame("Frame")
local since, logged = 0, false
driver:SetScript("OnUpdate", function(_, elapsed)
    since = since + (elapsed or 0)
    if since < TICK then return end
    since = 0
    local ok, err = pcall(Look)
    if not ok and not logged and EbonholdLog then   -- once: a broken look would repeat 4 times a second
        logged = true
        EbonholdLog("champion_marker: " .. tostring(err))
    end
end)
