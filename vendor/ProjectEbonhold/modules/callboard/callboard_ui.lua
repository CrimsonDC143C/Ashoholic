-- callboard_ui.lua -- Hero's Call Board window.
--
-- Opened by interacting with the summoned board (GO 600600, gossip name "Hero's
-- Call Board"): the Blizzard gossip frame is hidden and this window takes its
-- place. Layout (his pick of 2026-10-08, after Ascension's "Path to Ascension" window),
-- built from stock 3.3.5 art only:
--   * the quest log's chrome stretched to 900 x 560 (portrait ring, title bar, band,
--     bottom bar); the cache bar sits in the middle of the band, the cache figures on
--     its left, the daily / weekly resets on its right;
--   * on the left, one big button per contract of the selected category, grouped Today /
--     This Week / Once Per Account: a round icon (the instance's Dungeon Finder icon, the
--     profession, the continent) with a state badge (! to take, ? in progress, green check
--     ready to claim), the title and the counter;
--   * on the right, the selected contract: the instance's loading screen in a gold frame,
--     title, quest text, then Objectives / Rewards and the red action button;
--   * one character-sheet tab per category under the window; "Claim All" and "Close" in
--     the bottom bar.
-- A card done for its period, or a one-shot already completed, is not shown (his rule of
-- 2026-09-14). Everything shown comes from ProjectEbonhold.Callboard (the last server
-- payload); clicks only send requests, the server answers with a fresh board.

local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
local Callboard = ProjectEbonhold.Callboard
local UI = {}
ProjectEbonhold.CallboardUI = UI

local BOARD_GOSSIP_NAME = "Hero's Call Board"
-- The client caches gameobject names (Cache\WDB): a client that saw the board under its old
-- name keeps showing "Objectives Board" in the gossip frame until the cache is refreshed.
-- Both names open the window.
local BOARD_GOSSIP_NAMES = { [BOARD_GOSSIP_NAME] = true, ["Objectives Board"] = true }

local FRAME_NAME         = "EbonholdCallboardFrame"
local FRAME_W, FRAME_H   = 900, 560
local LIST_W, LIST_H     = 300, 444
local ROW_W, ROW_H       = 292, 46
local ROW_GAP            = 4
local GROUP_H            = 20
local PANEL_W, PANEL_H   = 546, 448
local ART_W, ART_H       = 502, 176
-- a zone map is 1002 x 668 px of 4 x 3 tiles of 256, drawn at the picture's width
local MAP_TILE           = 256 * ART_W / 1002
local MAP_H              = 668 * ART_W / 1002
local STRIP_H            = 134
local MAX_OBJECTIVES     = 4
local MAX_REWARDS        = 7
local REWARD_STEP        = 42
local TAB_TEXT_MAX_W     = 120

local FONT               = "Fonts\\FRIZQT__.TTF"
local ASSETS             = "Interface\\AddOns\\ProjectEbonhold\\assets\\"
local LOADSCREENS        = "Interface\\Glues\\LoadingScreens\\"
local LFGICONS           = "Interface\\LFGFrame\\LFGIcon-"
local ICON_ASH           = ASSETS .. "inv_soulash"
local ICON_ARTISAN       = "Interface\\Icons\\ability_argus_soulbombdebufflarge"
local ICON_XP            = "Interface\\Icons\\XP_Icon"
local ICON_ORB           = "Interface\\Icons\\inv_112_arcane_orb"                 -- same icon as the Orb of Lost Memories
local ICON_SHARD         = "Interface\\Icons\\inv_10_jewelcrafting3_soulcage_frost" -- same icon as the run HUD
local ICON_BOARD         = "Interface\\Icons\\INV_Misc_Note_01"

local C_META    = { 0.73, 0.68, 0.56 }
local C_SUB     = { 0.66, 0.62, 0.53 }

-- ------------------------------------------------------------------ art ----

-- Loading screens are square textures shown at 4:3; the picture of the panel is a
-- 0.47-high slice of one. BANDED screens carry the logo in a brown band at the top (picture
-- from 0.31), WIDE ones are full-bleed with the logo over the art (picture from 0.42).
local BANDED, WIDE = 0.31, 0.42
local ART_SLICE = 0.47

-- Instance name as the contracts write it ("Slay X in <name>.") -> loading screen, Dungeon
-- Finder icon. Matched longest name first, so "Tempest Keep: The Arcatraz" wins over
-- "Tempest Keep" and "Ahn'Qiraj Temple" over "Ruins of Ahn'Qiraj".
local INSTANCES = {
    -- Northrend
    ["Utgarde Keep"]                          = { "LOADSCREENUTGARDE", "Utgarde" },
    ["Utgarde Pinnacle"]                      = { "LoadScreenUtgardePinnecle", "UtgardePinnacle" },
    ["The Nexus"]                             = { "LoadScreenNexus70", "TheNexus" },
    ["The Oculus"]                            = { "LoadScreenNexus80", "TheOculus" },
    ["Azjol-Nerub"]                           = { "LoadScreenAzjolNerub76", "AzjolNerub" },
    ["Ahn'kahet: The Old Kingdom"]            = { "LoadScreenAzjolUpperCity", "Ahnkalet" },
    ["Drak'Tharon Keep"]                      = { "LoadScreenDrakTharon", "DrakTharon" },
    ["Violet Hold"]                           = { "LoadScreenDalaranPrison", "TheVioletHold" },
    ["Gundrak"]                               = { "LoadScreenGunDrak", "Gundrak" },
    ["Halls of Stone"]                        = { "LoadScreenUlduar77", "HallsofStone" },
    ["Halls of Lightning"]                    = { "LoadScreenUlduar80", "HallsofLightning" },
    ["The Culling of Stratholme"]             = { "LoadScreenOldStrathome", "OldStratholme" },
    ["Trial of the Champion"]                 = { "LoadScreenArgentDungeon", "ArgentDungeon" },
    ["The Forge of Souls"]                    = { "LoadScreenIcecrown5man", "TheForgeofSouls" },
    ["Pit of Saron"]                          = { "LoadScreenPitofSaron", "PitofSaron" },
    ["Halls of Reflection"]                   = { "LoadScreenHallsofReflection", "HallsofReflection" },
    ["Naxxramas"]                             = { "LoadScreenNaxxramas", "Naxxramas" },
    ["The Obsidian Sanctum"]                  = { "LoadScreenChamberBlack", "ChamberOfAspects" },
    ["The Eye of Eternity"]                   = { "LoadScreenMalygos", "Malygos" },
    ["Ulduar"]                                = { "LoadScreenUlduarRaid", "UlduarRaid" },
    ["Trial of the Crusader"]                 = { "LoadScreenArgentRaid", "ArgentRaid" },
    ["Onyxia's Lair"]                         = { "LoadScreenRaid", "OnyxiaEncounter" },
    ["Icecrown Citadel"]                      = { "LoadScreenIcecrownCitadel", "IcecrownCitadel" },
    ["The Ruby Sanctum"]                      = { "LoadScreenRubySanctum", "RubySanctum" },
    ["Vault of Archavon"]                     = { "LoadScreenWintergrasp", "VaultOfArchavon" },
    -- Outland
    ["Hellfire Citadel: Ramparts"]            = { "LOADSCREENHELLFIRECITADEL5MAN", "HELLFIRECITADEL5MAN" },
    ["Hellfire Citadel: The Blood Furnace"]   = { "LOADSCREENHELLFIRECITADEL5MAN", "HELLFIRECITADEL5MAN" },
    ["Hellfire Citadel: The Shattered Halls"] = { "LOADSCREENHELLFIRECITADEL5MAN", "HELLFIRECITADEL5MAN" },
    ["Coilfang: The Slave Pens"]              = { "LOADSCREENCOILFANG", "COILFANG" },
    ["Coilfang: The Underbog"]                = { "LOADSCREENCOILFANG", "COILFANG" },
    ["Coilfang: The Steamvault"]              = { "LOADSCREENCOILFANG", "COILFANG" },
    ["Auchindoun: Mana-Tombs"]                = { "LOADSCREENAUCHINDOUN", "AUCHINDOUN" },
    ["Auchindoun: Auchenai Crypts"]           = { "LOADSCREENAUCHINDOUN", "AUCHINDOUN" },
    ["Auchindoun: Sethekk Halls"]             = { "LOADSCREENAUCHINDOUN", "AUCHINDOUN" },
    ["Auchindoun: Shadow Labyrinth"]          = { "LOADSCREENAUCHINDOUN", "AUCHINDOUN" },
    ["Tempest Keep: The Mechanar"]            = { "LOADSCREENTEMPESTKEEP", "TEMPESTKEEP" },
    ["Tempest Keep: The Botanica"]            = { "LOADSCREENTEMPESTKEEP", "TEMPESTKEEP" },
    ["Tempest Keep: The Arcatraz"]            = { "LOADSCREENTEMPESTKEEP", "TEMPESTKEEP" },
    ["The Escape From Durnholde"]             = { "LOADSCREENCAVERNSTIME", "CAVERNSOFTIME" },
    ["Opening of the Dark Portal"]            = { "LOADSCREENCAVERNSTIME", "CAVERNSOFTIME" },
    ["Magister's Terrace"]                    = { "LoadScreenSunwell5Man", "MAGISTERSTERRACE" },
    ["Karazhan"]                              = { "LoadScreenKarazhan", "KARAZHAN" },
    ["Gruul's Lair"]                          = { "LOADSCREENGRUULSLAIR", "GRUULSLAIR" },
    ["Magtheridon's Lair"]                    = { "LOADSCREENHELLFIRECITADELRAID", "HELLFIRECITADELRAID" },
    ["Coilfang: Serpentshrine Cavern"]        = { "LOADSCREENCOILFANG", "SERPENTSHRINECAVERN" },
    ["Tempest Keep"]                          = { "LOADSCREENTEMPESTKEEP", "TEMPESTKEEP" },
    ["Zul'Aman"]                              = { "LOADSCREENZULAMAN", "ZULAMAN" },
    ["The Battle for Mount Hyjal"]            = { "LoadScreenHyjal", "HYJALPAST" },
    ["Black Temple"]                          = { "LoadScreenBlackTemple", "BLACKTEMPLE" },
    ["The Sunwell"]                           = { "LOADSCREENSUNWELL", "SUNWELL" },
    -- Classic
    ["Ragefire Chasm"]                        = { "LoadScreenRagefireChasm", "RAGEFIRECHASM" },
    ["Wailing Caverns"]                       = { "LoadScreenWailingCaverns", "WAILINGCAVERNS" },
    ["Deadmines"]                             = { "LoadScreenDeadmines", "DEADMINES" },
    ["Shadowfang Keep"]                       = { "LoadScreenShadowFangKeep", "SHADOWFANGKEEP" },
    ["Blackfathom Deeps"]                     = { "LoadScreenBlackFathomDeeps", "BLACKFATHOMDEEPS" },
    ["Stormwind Stockade"]                    = { "LoadScreenStormwindStockade", "STORMWINDSTOCKADES" },
    ["Gnomeregan"]                            = { "LoadScreenGnomeregan", "GNOMEREGAN" },
    ["Razorfen Kraul"]                        = { "LoadScreenRazorfenKraul", "RAZORFENKRAUL" },
    ["Scarlet Monastery"]                     = { "LoadScreenMonastery", "SCARLETMONASTERY" },
    ["Razorfen Downs"]                        = { "LoadScreenRazorfenDowns", "RAZORFENDOWNS" },
    ["Uldaman"]                               = { "LOADSCREENULDAMAN", "ULDAMAN" },
    ["Zul'Farrak"]                            = { "LoadScreenZulFarrak", "ZULFARAK" },
    ["Maraudon"]                              = { "LoadScreenMaraudon", "MARAUDON" },
    ["Sunken Temple"]                         = { "LoadScreenSunkenTemple", "SUNKENTEMPLE" },
    ["Blackrock Depths"]                      = { "LoadScreenBlackrockDepths", "BLACKROCKDEPTHS" },
    ["Blackrock Spire"]                       = { "LoadScreenBlackrockSpire", "BLACKROCKSPIRE" },
    ["Dire Maul"]                             = { "LoadScreenDireMaul", "DIREMAUL" },
    ["Scholomance"]                           = { "LoadScreenScholomance", "SCHOLOMANCE" },
    ["Stratholme"]                            = { "LoadScreenStrathome", "STRATHOLME" },
    ["Molten Core"]                           = { "LoadScreenMoltenCore", "MOLTENCORE" },
    ["Blackwing Lair"]                        = { "LoadScreenBlackWingLair", "BLACKWINGLAIR" },
    ["Zul'Gurub"]                             = { "LoadScreenZulGurub", "ZULGURUB" },
    ["Ruins of Ahn'Qiraj"]                    = { "LoadScreenAhnQiraj20man", "AQRUINS" },
    ["Ahn'Qiraj Temple"]                      = { "LoadScreenAhnQiraj40man", "AQTEMPLE" },
}
local INSTANCE_NAMES = {}
for name in pairs(INSTANCES) do table.insert(INSTANCE_NAMES, name) end
table.sort(INSTANCE_NAMES, function(a, b) return #a > #b end)

-- Open-world contracts end on "in <zone>."; the zone's continent picks the picture.
local CONTINENT_ART = {
    [1] = { "LoadScreenKalimdorWide", WIDE, "Interface\\LFGFrame\\LFGICON-KALIMDOR" },
    [2] = { "LoadScreenEasternKingdomWide", WIDE, "Interface\\LFGFrame\\LFGICON-EASTERNKINGDOMS" },
    [3] = { "LoadScreenOutlandWide", WIDE, "Interface\\LFGFrame\\LFGICON-OUTLAND" },
    [4] = { "LoadScreenWintergrasp", BANDED, "Interface\\LFGFrame\\LFGICON-ZONE" },
}

-- Category fallbacks: picture, its slice, row icon.
local CATEGORY_ART = {
    [1] = { "LoadScreenDungeon", BANDED, "Interface\\LFGFrame\\LFGICON-DUNGEON" },
    [2] = { "LoadScreenRaid", BANDED, "Interface\\LFGFrame\\LFGICON-RAID" },
    [3] = { "LoadScreenWintergrasp", BANDED, "Interface\\LFGFrame\\LFGICON-ZONE" },
    [4] = { "LoadScreenDalaranPrison", BANDED, "Interface\\Icons\\INV_Misc_Gear_01" },
    [6] = { "LoadScreenNorthrendWide", WIDE, ICON_BOARD },
    [7] = { "LoadScreenRaid", BANDED, "Interface\\Icons\\Spell_Shadow_SoulLeech_3" },
}

-- Profession contracts name their guild ("The tailoring guild of the capital...").
local PROFESSION_ICONS = {
    { "tailoring",      "Interface\\Icons\\Trade_Tailoring" },
    { "leatherworking", "Interface\\Icons\\Trade_LeatherWorking" },
    { "blacksmithing",  "Interface\\Icons\\Trade_BlackSmithing" },
    { "alchemy",        "Interface\\Icons\\Trade_Alchemy" },
    { "enchanting",     "Interface\\Icons\\Trade_Engraving" },
    { "engineering",    "Interface\\Icons\\Trade_Engineering" },
    { "inscription",    "Interface\\Icons\\INV_Inscription_Tradeskill01" },
    { "jewelcrafting",  "Interface\\Icons\\INV_Misc_Gem_01" },
    { "cooking",        "Interface\\Icons\\INV_Misc_Food_15" },
}

local function ZoneOf(q)
    return string.match(q.objectives or "", " in (.-)%.?%s*$")
end

local zoneContinent
local function ContinentOfZone(zone)
    if not zoneContinent then
        zoneContinent = {}
        for c = 1, 4 do
            for _, name in ipairs({ GetMapZones(c) }) do zoneContinent[name] = c end
        end
    end
    return zoneContinent[zone]
end

-- Picture (file, slice start) and row icon of a contract, worked out once per quest.
local artCache = {}
local function ArtOf(q)
    local hit = artCache[q.questId]
    if hit then return hit end
    local text = (q.title or "") .. " " .. (q.objectives or "")
    local fallback = CATEGORY_ART[q.category] or CATEGORY_ART[1]
    local art = { file = LOADSCREENS .. fallback[1], v0 = fallback[2], icon = fallback[3] }
    if q.category == Callboard.CATEGORY.OPEN_WORLD then
        local zone = ZoneOf(q)
        local cont = CONTINENT_ART[zone and ContinentOfZone(zone) or 0]
        if cont then art.file, art.v0, art.icon = LOADSCREENS .. cont[1], cont[2], cont[3] end
    elseif q.category == Callboard.CATEGORY.PROFESSION then
        local lower = string.lower((q.description or "") .. " " .. text)
        for _, p in ipairs(PROFESSION_ICONS) do
            if string.find(lower, p[1], 1, true) then art.icon = p[2]; break end
        end
    else
        for _, name in ipairs(INSTANCE_NAMES) do
            if string.find(text, name, 1, true) then
                local inst = INSTANCES[name]
                art.file, art.v0 = LOADSCREENS .. inst[1], BANDED
                -- a Torment one-shot keeps its category's icon; only the picture is the instance's
                if q.category ~= Callboard.CATEGORY.TORMENT then art.icon = LFGICONS .. inst[2] end
                break
            end
        end
    end
    artCache[q.questId] = art
    return art
end

-- ------------------------------------------------------------- helpers ----

local mainFrame
local isInBoardGossip = false
local selectedCategory = Callboard.CATEGORY.OPEN_WORLD   -- the first tab
local selectedQuest = {}      -- category -> questId shown in the panel
local rows, groups = {}, {}
local tabs = {}

local function FormatThousands(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(n)
    local out = ""
    while #s > 3 do
        out = "," .. string.sub(s, -3) .. out
        s = string.sub(s, 1, -4)
    end
    return s .. out
end

-- Count on a 34 px reward icon: 65400 -> 65.4k, 218000 -> 218k.
local function ShortCount(n)
    n = math.floor(tonumber(n) or 0)
    if n >= 100000 then return math.floor(n / 1000 + 0.5) .. "k" end
    if n >= 1000 then
        local s = string.format("%.1f", n / 1000)
        return (string.gsub(s, "%.0$", "")) .. "k"
    end
    return tostring(n)
end

local function FormatDuration(seconds)
    seconds = math.floor(math.max(0, seconds or 0))
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if d > 0 then
        return string.format("%dd %02d:%02d:%02d", d, h, m, s)
    end
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function SetFont(fs, size)
    fs:SetFont(FONT, size)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
end

-- SetPortraitToTexture builds a new round texture on every call: only a changed icon is redrawn.
local function SetRoundIcon(tex, path)
    if tex._path == path then return end
    tex._path = path
    SetPortraitToTexture(tex, path)
end

-- Nine-slice of the pixel box (x0, y0)-(x1, y1) of a texture file, corners s px.
-- Each piece: column, row, then its anchors (point, x, y) in units of s.
local NINE = {
    { 1, 1, { "TOPLEFT", 0, 0 } },
    { 2, 1, { "TOPLEFT", 1, 0 }, { "TOPRIGHT", -1, 0 } },
    { 3, 1, { "TOPRIGHT", 0, 0 } },
    { 1, 2, { "TOPLEFT", 0, -1 }, { "BOTTOMLEFT", 0, 1 } },
    { 2, 2, { "TOPLEFT", 1, -1 }, { "BOTTOMRIGHT", -1, 1 } },
    { 3, 2, { "TOPRIGHT", 0, -1 }, { "BOTTOMRIGHT", 0, 1 } },
    { 1, 3, { "BOTTOMLEFT", 0, 0 } },
    { 2, 3, { "BOTTOMLEFT", 1, 0 }, { "BOTTOMRIGHT", -1, 0 } },
    { 3, 3, { "BOTTOMRIGHT", 0, 0 } },
}
local function NineSlice(parent, file, fileW, fileH, x0, y0, x1, y1, s, layer, noCenter)
    local xs = { x0, x0 + s, x1 - s, x1 }
    local ys = { y0, y0 + s, y1 - s, y1 }
    local pieces = {}
    for _, p in ipairs(NINE) do
        local col, row = p[1], p[2]
        if not (noCenter and col == 2 and row == 2) then
            local t = parent:CreateTexture(nil, layer or "BACKGROUND")
            t:SetTexture(file)
            t:SetTexCoord(xs[col] / fileW, xs[col + 1] / fileW, ys[row] / fileH, ys[row + 1] / fileH)
            if col ~= 2 then t:SetWidth(s) end
            if row ~= 2 then t:SetHeight(s) end
            for i = 3, #p do
                local a = p[i]
                t:SetPoint(a[1], parent, a[1], a[2] * s, a[3] * s)
            end
            table.insert(pieces, t)
        end
    end
    return pieces
end

-- A rectangle of 1 px lines, inset px inside parent.
local function Outline(parent, inset, r, g, b, a, layer)
    local lines = {}
    for i = 1, 4 do
        local t = parent:CreateTexture(nil, layer or "BORDER")
        t:SetTexture(r, g, b, a)
        lines[i] = t
    end
    lines[1]:SetHeight(1)
    lines[1]:SetPoint("TOPLEFT", inset, -inset); lines[1]:SetPoint("TOPRIGHT", -inset, -inset)
    lines[2]:SetHeight(1)
    lines[2]:SetPoint("BOTTOMLEFT", inset, inset); lines[2]:SetPoint("BOTTOMRIGHT", -inset, inset)
    lines[3]:SetWidth(1)
    lines[3]:SetPoint("TOPLEFT", inset, -inset); lines[3]:SetPoint("BOTTOMLEFT", inset, inset)
    lines[4]:SetWidth(1)
    lines[4]:SetPoint("TOPRIGHT", -inset, -inset); lines[4]:SetPoint("BOTTOMRIGHT", -inset, inset)
    return lines
end

-- The quest log's dual-pane frame (682 x 445, two files) stretched to w x h: the portrait,
-- the title bar and the corners keep their size, the middle column and row stretch.
local CHROME_L = "Interface\\QuestFrame\\UI-QuestLogDualPane-Left"
local CHROME_R = "Interface\\QuestFrame\\UI-QuestLogDualPane-RIGHT"
local function CreateChrome(frame, w, h)
    -- source columns: width, file, first pixel, end pixel, file width, stretches
    local cols = {
        { 420, CHROME_L, 0, 420, 512, false },
        { 91,  CHROME_L, 420, 511, 512, true },   -- the left file's last column is a dark seam: skipped
        { 49,  CHROME_R, 0, 49, 256, true },
        { 122, CHROME_R, 49, 171, 256, false },
    }
    local rowsSrc = { { 0, 150, false }, { 150, 300, true }, { 300, 445, false } }
    local stretchW = (w - 542) / 140
    local stretchH = h - 295
    local y = 0
    for _, r in ipairs(rowsSrc) do
        local rh = r[3] and stretchH or (r[2] - r[1])
        local x = 0
        for _, c in ipairs(cols) do
            local cw = c[6] and (c[1] * stretchW) or c[1]
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetTexture(c[2])
            t:SetTexCoord(c[3] / c[5], c[4] / c[5], r[1] / 512, r[2] / 512)
            t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
            t:SetWidth(cw)
            t:SetHeight(rh)
            x = x + cw
        end
        y = y + rh
    end
end

local function ResetGossipFrame()
    if GossipFrame then
        GossipFrame:SetAlpha(1)
        GossipFrame:EnableMouse(true)
        GossipFrame:ClearAllPoints()
        GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    end
end

local function CloseBoard()
    local wasInGossip = isInBoardGossip
    isInBoardGossip = false
    if wasInGossip then
        ResetGossipFrame()
        if GossipFrameCloseButton then
            GossipFrameCloseButton:Click()
        end
    end
    if mainFrame then
        mainFrame:Hide()
    end
end

-- A card done for its period, or a one-shot already completed, leaves the board.
local function IsShown(q)
    return q.state ~= Callboard.STATE.EXHAUSTED
end

local function VisibleQuests(category)
    local out = {}
    local board = Callboard.board
    for _, q in ipairs(board and board.byCategory[category] or {}) do
        if IsShown(q) then table.insert(out, q) end
    end
    return out
end

local function CategoryOf(id)
    for _, cat in ipairs(Callboard.CATEGORIES) do
        if cat.id == id then return cat end
    end
    return Callboard.CATEGORIES[1]
end

-- The objectives as the quest log tracks them ("Wrathbone Laborer slain: 4/6"), when the
-- contract is in the log (and not under a collapsed header).
local function LogObjectives(questId)
    for i = 1, GetNumQuestLogEntries() do
        local _, _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
        if not isHeader and id == questId then
            local out = {}
            for j = 1, GetNumQuestLeaderBoards(i) do
                local text, _, finished = GetQuestLogLeaderBoard(j, i)
                if text and text ~= "" then table.insert(out, { text = text, done = finished }) end
            end
            return out
        end
    end
    return nil
end

-- Same words as the Skill Tree's currency bar (ProjectEbonhold.CurrencyHelp).
local REWARD_HELP = {
    ash     = { "Soul Ashes", "ash", "The currency of the Soul Ash Tree: every ordinary node, the flat stats, the mechanics and the infinite wells." },
    shard   = { "Soul Shards", "shard", "The Milestones of the tree: the percentage bonuses on the stats of your gear." },
    artisan = { "Artisan Soul", "artisan", "The Professions sector of the tree: gathering, crafting and the Torment recipes." },
    orb     = { "Orb of Lost Memories", nil, "Spent in the Echo Journal: forget one stack of an Echo and draw a new choice in its place." },
    xp      = { "experience", nil, "Experience for your character, as a quest would give." },
}

-- ---------------------------------------------------------------- rows ----

-- A section header folds its cards away, like a quest log header (+ / -). A click only flips
-- sectionOpen[key] for the session; RefreshList lays the list out again.
local sectionOpen = {}        -- section key -> true / false once clicked; nil = the default

local function CreateGroupHeader(parent)
    local g = CreateFrame("Button", nil, parent)
    g:SetWidth(ROW_W)
    g:SetHeight(GROUP_H)
    local toggle = g:CreateTexture(nil, "OVERLAY")
    toggle:SetWidth(14)
    toggle:SetHeight(14)
    toggle:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 2, 2)
    g.toggle = toggle
    local text = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", toggle, "RIGHT", 3, 0)
    g.text = text
    g:SetScript("OnClick", function(self)
        if not self.key then return end
        PlaySound(self.open and "igMainMenuOptionCheckBoxOff" or "igMainMenuOptionCheckBoxOn")
        sectionOpen[self.key] = not self.open
        UI.Refresh()
    end)
    g:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
    g:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) end)
    local line = g:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", text, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", g, "RIGHT", -4, 0)
    line:SetTexture(1, 1, 1, 1)
    line:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.45, 1, 0.82, 0, 0)
    g:Hide()
    return g
end

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(ROW_W)
    row:SetHeight(ROW_H)

    -- the achievement window's category bar, as a nine-slice
    row.bg = NineSlice(row, "Interface\\AchievementFrame\\UI-Achievement-Category-Background", 256, 32, 2, 1, 165, 27, 9, "BACKGROUND")

    local glow = row:CreateTexture(nil, "BORDER")
    glow:SetPoint("TOPLEFT", 4, -4)
    glow:SetPoint("BOTTOMRIGHT", -4, 4)
    glow:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.75, 0.2)
    glow:Hide()
    row.glow = glow
    row.edge = Outline(row, 1, 1, 0.82, 0, 0.9, "OVERLAY")
    for _, l in ipairs(row.edge) do l:Hide() end

    local icon = row:CreateTexture(nil, "BORDER")
    icon:SetWidth(30)
    icon:SetHeight(30)
    icon:SetPoint("LEFT", row, "LEFT", 9, 0)
    row.icon = icon
    local ring = row:CreateTexture(nil, "ARTWORK")
    ring:SetWidth(40)
    ring:SetHeight(40)
    ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
    ring:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-REWARDRING")
    ring:SetTexCoord(0, 40 / 64, 0, 40 / 64)
    local badge = row:CreateTexture(nil, "OVERLAY")
    badge:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -6, -1)
    row.badge = badge

    local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", row, "TOPLEFT", 49, -10)
    title:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    row.title = title
    local sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    sub:SetTextColor(unpack(C_SUB))
    row.sub = sub

    row:SetScript("OnEnter", function(self) if not self.selected then self.glow:SetAlpha(0.5); self.glow:Show() end end)
    row:SetScript("OnLeave", function(self) if not self.selected then self.glow:Hide() end end)
    row:SetScript("OnClick", function(self)
        if not self.quest then return end
        PlaySound("igMainMenuOptionCheckBoxOn")
        selectedQuest[selectedCategory] = self.quest.questId
        UI.Refresh()
    end)
    row:Hide()
    return row
end

local function SetRowSelected(row, selected)
    row.selected = selected
    -- the bar is drawn a shade darker than its art; the selected one at full light
    local shade = selected and 1 or 0.8
    for _, t in ipairs(row.bg) do t:SetVertexColor(shade, shade, shade) end
    for _, l in ipairs(row.edge) do if selected then l:Show() else l:Hide() end end
    if selected then
        row.glow:SetAlpha(0.45)
        row.glow:Show()
        row.title:SetTextColor(1, 0.82, 0)
    else
        row.glow:Hide()
        row.title:SetTextColor(1, 1, 1)
    end
end

-- Past the top of its level window a contract still turns in, for less the later it comes
-- (server rule, x0.8 per level): the card shows the XP it still gives, nothing more (his call).
-- A server older than 2026-10-11 paid nothing there, and says so.
local function OutleveledText(q)
    if q.paysNothing then
        return string.format("|cffff4040Pays nothing: you are above level %d|r", q.outleveledAbove)
    end
    return string.format("|cffffd100%s XP|r", FormatThousands(q.xp or 0))
end

-- The contract's level (server field 22; -1 = the player's own level), nil from an older server.
local function LevelOf(q)
    if not q.level then return nil end
    return q.level > 0 and q.level or UnitLevel("player")
end

-- "[7-16] " (the full-reward window, "[12] " without one) in the quest log's colour for the
-- contract's level (grey, green, yellow, orange, red).
local function LevelTag(q)
    local level = LevelOf(q)
    if not level then return "" end
    local c = GetQuestDifficultyColor(level)
    local text = (q.minLevel and q.maxLevel) and string.format("%d-%d", q.minLevel, q.maxLevel) or tostring(level)
    return string.format("|cff%02x%02x%02x[%s]|r ", c.r * 255, c.g * 255, c.b * 255, text)
end

local function RowSubText(q)
    local count = string.format("%s %d/%d", q.cadence == Callboard.CADENCE.WEEKLY and "Weekly" or "Daily", q.done, q.max)
    -- outleveled: the XP it still gives in place of the counter; no XP left (level 80) = the usual line
    if (q.outleveledAbove or 0) > 0 and (q.paysNothing or (q.xp or 0) > 0) then
        local state = q.state == Callboard.STATE.COMPLETE and "|cff1eff00Ready to claim|r  -  "
            or q.state == Callboard.STATE.ACCEPTED and "|cff6fa8ffIn progress|r  -  " or ""
        return state .. OutleveledText(q)
    end
    if q.state == Callboard.STATE.COMPLETE then return "|cff1eff00Ready to claim|r" end
    if q.state == Callboard.STATE.ACCEPTED then
        return "|cff6fa8ffIn progress|r" .. (q.cadence == Callboard.CADENCE.ONCE and "" or ("  -  " .. count))
    end
    if q.cadence == Callboard.CADENCE.ONCE then return "Once per account" end
    return count .. (q.accountWide and "  -  account" or "")
end

local function RefreshRow(row, q)
    row.quest = q
    SetRoundIcon(row.icon, ArtOf(q).icon)
    -- ! to take (blue = daily), ? in progress, green check ready to claim
    local badge = row.badge
    badge:SetDesaturated(false)
    if q.state == Callboard.STATE.COMPLETE then
        badge:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Criteria-Check")
        badge:SetTexCoord(0, 0.5625, 0, 1)
        badge:SetWidth(18)
        badge:SetHeight(16)
    else
        local daily = q.cadence == Callboard.CADENCE.DAILY
        badge:SetTexCoord(0, 1, 0, 1)
        badge:SetWidth(16)
        badge:SetHeight(16)
        if q.state == Callboard.STATE.ACCEPTED then
            badge:SetTexture(daily and "Interface\\GossipFrame\\DailyActiveQuestIcon" or "Interface\\GossipFrame\\ActiveQuestIcon")
            badge:SetDesaturated(true)
        else
            badge:SetTexture(daily and "Interface\\GossipFrame\\DailyQuestIcon" or "Interface\\GossipFrame\\AvailableQuestIcon")
        end
    end
    row.title:SetText(LevelTag(q) .. q.title)
    row.sub:SetText(RowSubText(q))
end

-- ------------------------------------------------------------- the frame ----

-- Blizzard tab look without PanelTemplates_SelectTab (same as the talent window's tabs).
local function SetTabSelected(t, selected)
    local n = t:GetName()
    for _, part in ipairs({ "Left", "Middle", "Right" }) do
        if selected then
            _G[n .. part]:Hide(); _G[n .. part .. "Disabled"]:Show()
        else
            _G[n .. part]:Show(); _G[n .. part .. "Disabled"]:Hide()
        end
    end
    t:SetNormalFontObject(selected and GameFontHighlightSmall or GameFontNormalSmall)
end

-- Tab width from its text: 20 px caps around a middle piece (PanelTemplates_TabResize is
-- replaced by the collections module with its retail version).
local function ResizeTab(t)
    local n = t:GetName()
    local text = _G[n .. "Text"]
    local textW = text:GetStringWidth()
    text:SetWidth(textW > TAB_TEXT_MAX_W and TAB_TEXT_MAX_W or 0)
    local w = math.max(40, math.min(TAB_TEXT_MAX_W, textW) + 20)
    _G[n .. "Middle"]:SetWidth(w)
    _G[n .. "MiddleDisabled"]:SetWidth(w)
    t:SetWidth(w + 40)
end

local function CreateTab(index, cat)
    local t = CreateFrame("Button", FRAME_NAME .. "Tab" .. index, mainFrame, "CharacterFrameTabButtonTemplate")
    if index == 1 then
        t:SetPoint("TOPLEFT", mainFrame, "BOTTOMLEFT", 14, 6)
    else
        t:SetPoint("LEFT", tabs[index - 1], "RIGHT", -16, 0)
    end
    t:SetHeight(32)
    -- the template's OnShow / OnEvent resize through CharacterFrame helpers: ours instead
    t:SetScript("OnShow", function(self) ResizeTab(self) end)
    t:SetScript("OnEvent", function(self) ResizeTab(self) end)
    t:SetScript("OnClick", function()
        PlaySound("igCharacterInfoTab")
        selectedCategory = cat.id
        UI.Refresh()
    end)
    t:SetScript("OnEnter", function(self)
        local list = VisibleQuests(cat.id)
        local ready = 0
        for _, q in ipairs(list) do if q.state == Callboard.STATE.COMPLETE then ready = ready + 1 end end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(cat.name, 1, 1, 1)
        GameTooltip:AddLine(#list .. " contract" .. (#list == 1 and "" or "s") .. " posted", 0.8, 0.8, 0.8)
        if ready > 0 then GameTooltip:AddLine(ready .. " ready to claim", 0.12, 1, 0) end
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return t
end

local function CreateRewardSlot(strip, index)
    local b = CreateFrame("Frame", nil, strip)
    b:SetWidth(34)
    b:SetHeight(34)
    b:SetPoint("TOPLEFT", strip, "TOPLEFT", 24 + (index - 1) * REWARD_STEP, -92)
    b:EnableMouse(true)
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetAllPoints()
    b.icon = ic
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetWidth(56)
    border:SetHeight(56)
    border:SetPoint("CENTER", b, "CENTER", 0, 0)
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.count = count
    b:SetScript("OnEnter", function(self)
        if not self.kind then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.kind == "item" then
            GameTooltip:SetHyperlink("item:" .. self.amount)
        else
            local h = REWARD_HELP[self.kind]
            local help = ProjectEbonhold.CurrencyHelp or {}
            local text = h[2] and help[h[2]] and help[h[2]].buys or h[3]
            GameTooltip:AddLine(FormatThousands(self.amount) .. " " .. h[1], 1, 0.82, 0)
            GameTooltip:AddLine(text, 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Paid at the board when you claim the contract.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

local function CreatePanel()
    local panel = CreateFrame("Frame", nil, mainFrame)
    panel:SetWidth(PANEL_W)
    panel:SetHeight(PANEL_H)
    panel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 347, -74)

    -- the Dungeon Finder's dark quest paper (its picture is the left 326 px of the file)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\LFGFrame\\UI-LFG-BACKGROUND-QUESTPAPER")
    bg:SetTexCoord(0, 326 / 512, 0, 1)
    Outline(panel, 0, 0.16, 0.11, 0.06, 1)
    Outline(panel, 1, 0.16, 0.11, 0.06, 1)
    Outline(panel, 2, 0.42, 0.32, 0.20, 1)

    local art = panel:CreateTexture(nil, "ARTWORK")
    art:SetWidth(ART_W)
    art:SetHeight(ART_H)
    art:SetPoint("TOP", panel, "TOP", 0, -18)
    panel.art = art

    -- The zone map in place of the picture (2026-10-11): the 4 x 3 tiles of the world map's zone
    -- art in a clipping scroll frame showing the band around the camp; pins for the camp, the
    -- player and the zone's Spirit Healers.
    local map = CreateFrame("ScrollFrame", nil, panel)
    map:SetWidth(ART_W)
    map:SetHeight(ART_H)
    map:SetPoint("TOP", panel, "TOP", 0, -18)
    local child = CreateFrame("Frame", nil, map)
    child:SetWidth(ART_W)
    child:SetHeight(MAP_H)
    map:SetScrollChild(child)
    map.child = child
    map.tiles = {}
    for i = 1, 12 do
        local t = child:CreateTexture(nil, "ARTWORK")
        t:SetWidth(MAP_TILE)
        t:SetHeight(MAP_TILE)
        t:SetPoint("TOPLEFT", child, "TOPLEFT", ((i - 1) % 4) * MAP_TILE, -math.floor((i - 1) / 4) * MAP_TILE)
        map.tiles[i] = t
    end
    local function Pin(size, tip)
        local b = CreateFrame("Button", nil, child)
        b:SetWidth(size)
        b:SetHeight(size)
        b:SetFrameLevel(child:GetFrameLevel() + 2)
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetAllPoints()
        b.tip = tip
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        return b
    end
    map.Pin = Pin
    -- the camp: a soft yellow disc, as the quest log draws an objective area, with a ! on it
    local camp = Pin(22, "Camp")
    camp:SetFrameLevel(child:GetFrameLevel() + 3)
    camp.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    local blob = camp:CreateTexture(nil, "ARTWORK")
    blob:SetWidth(48)
    blob:SetHeight(48)
    blob:SetPoint("CENTER")
    blob:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    blob:SetVertexColor(1, 0.82, 0, 0.35)
    map.camp = camp
    local player = Pin(16, "You are here")
    player:SetFrameLevel(child:GetFrameLevel() + 4)
    player.icon:SetTexture("Interface\\WorldMap\\WorldMapPartyIcon")
    player.icon:SetVertexColor(0.3, 1, 0.3)
    map.player = player
    map.healers = {}
    local label = map:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", 8, 6)
    map.label = label
    map:Hide()
    panel.map = map

    -- the achievement icon's gold frame around the picture
    local frameBox = CreateFrame("Frame", nil, panel)
    frameBox:SetFrameLevel(map:GetFrameLevel() + 6)   -- over the map's pins too
    frameBox:SetWidth(ART_W + 20)
    frameBox:SetHeight(ART_H + 20)
    frameBox:SetPoint("CENTER", art, "CENTER", 0, 0)
    NineSlice(frameBox, "Interface\\AchievementFrame\\UI-Achievement-IconFrame", 128, 128, 3, 3, 69, 69, 14, "OVERLAY", true)

    local title = panel:CreateFontString(nil, "OVERLAY")
    SetFont(title, 19)
    title:SetPoint("TOP", panel, "TOP", 0, -212)
    title:SetWidth(PANEL_W - 40)
    title:SetWordWrap(false)
    title:SetTextColor(1, 1, 1)
    panel.title = title

    local desc = panel:CreateFontString(nil, "OVERLAY")
    SetFont(desc, 13)
    desc:SetPoint("TOP", panel, "TOP", 0, -240)
    desc:SetWidth(PANEL_W - 80)
    desc:SetJustifyH("CENTER")
    desc:SetSpacing(2)
    desc:SetTextColor(1, 1, 1)
    panel.desc = desc

    local meta = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    meta:SetPoint("TOP", desc, "BOTTOM", 0, -6)
    meta:SetWidth(PANEL_W - 40)
    meta:SetTextColor(unpack(C_META))
    panel.meta = meta

    -- Objectives / Rewards strip
    local strip = CreateFrame("Frame", nil, panel)
    strip:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 3, 3)
    strip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
    strip:SetHeight(STRIP_H)
    local shade = strip:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetTexture(0, 0, 0, 1)
    shade:SetGradientAlpha("VERTICAL", 0, 0, 0, 0.55, 0, 0, 0, 0.25)
    local rule = strip:CreateTexture(nil, "BORDER")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")
    rule:SetTexture(0.84, 0.67, 0.35, 0.35)
    panel.strip = strip

    local objHead = strip:CreateFontString(nil, "OVERLAY")
    SetFont(objHead, 15)
    objHead:SetPoint("TOPLEFT", strip, "TOPLEFT", 24, -8)
    objHead:SetText("Objectives")
    objHead:SetTextColor(1, 1, 1)

    panel.objectives = {}
    for i = 1, MAX_OBJECTIVES do
        local fs = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        if i == 1 then
            fs:SetPoint("TOPLEFT", strip, "TOPLEFT", 30, -30)
        else
            fs:SetPoint("TOPLEFT", panel.objectives[i - 1], "BOTTOMLEFT", 0, -2)
        end
        fs:SetWidth(300)
        fs:SetJustifyH("LEFT")
        panel.objectives[i] = fs
    end

    local rewHead = strip:CreateFontString(nil, "OVERLAY")
    SetFont(rewHead, 15)
    rewHead:SetPoint("TOPLEFT", strip, "TOPLEFT", 24, -70)
    rewHead:SetText("Rewards")
    rewHead:SetTextColor(1, 1, 1)

    panel.rewards = {}
    for i = 1, MAX_REWARDS do
        panel.rewards[i] = CreateRewardSlot(strip, i)
    end
    panel.money = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    local action = CreateFrame("Button", nil, strip, "UIPanelButtonTemplate")
    action:SetWidth(190)
    action:SetHeight(30)
    action:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -20, 18)
    action:SetText("Accept")
    panel.action = action

    -- Travel to the waystone nearest to the contract's camp (Callboard.GetWaystone), above the action button.
    -- Usable away from the board; greyed while the waystone is not discovered.
    local travel = CreateFrame("Button", nil, strip, "UIPanelButtonTemplate")
    travel:SetWidth(190)
    travel:SetHeight(24)
    travel:SetPoint("BOTTOM", action, "TOP", 0, 6)
    travel:SetText("Travel to Waystone")
    -- the Toolbelt's Waystones icon, on the left; the label moves right to make room
    local travelIcon = travel:CreateTexture(nil, "OVERLAY")
    travelIcon:SetWidth(18)
    travelIcon:SetHeight(18)
    travelIcon:SetPoint("LEFT", travel, "LEFT", 8, 0)
    travelIcon:SetTexture("Interface\\Icons\\Spell_Arcane_PortalDalaran")
    travelIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    travel.icon = travelIcon
    travel:GetFontString():ClearAllPoints()
    travel:GetFontString():SetPoint("CENTER", travel, "CENTER", 11, 1)
    travel:SetScript("OnEnter", function(self)
        if not self.name then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Waystone: " .. self.name, 1, 0.82, 0)
        if self.known then
            GameTooltip:AddLine("Travel to the waystone nearest to this contract.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Undiscovered. Walk onto this waystone to discover it.", 1, 0.35, 0.35, true)
        end
        GameTooltip:Show()
    end)
    travel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    travel:Hide()
    panel.travel = travel

    return panel
end

local function CreateMainFrame()
    if mainFrame then return mainFrame end

    mainFrame = CreateFrame("Frame", FRAME_NAME, UIParent)
    mainFrame:SetWidth(FRAME_W)
    mainFrame:SetHeight(FRAME_H)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetFrameLevel(100)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

    -- portrait under the chrome: the ring of the frame is a hole
    local portrait = mainFrame:CreateTexture(nil, "BACKGROUND")
    portrait:SetWidth(60)
    portrait:SetHeight(60)
    portrait:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 7, -6)
    SetPortraitToTexture(portrait, ICON_BOARD)
    CreateChrome(mainFrame, FRAME_W, FRAME_H)

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", mainFrame, "TOP", 20, -15)
    title:SetText(BOARD_GOSSIP_NAME)

    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, -8)

    -- ---- the cache bar, in the middle of the band
    local bar = CreateFrame("StatusBar", nil, mainFrame)
    bar:SetWidth(314)
    bar:SetHeight(12)
    bar:SetPoint("TOP", mainFrame, "TOP", 0, -47)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.07, 0.71, 0.11)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture(0, 0, 0, 0.7)
    local border = bar:CreateTexture(nil, "OVERLAY")
    border:SetWidth(330)
    border:SetHeight(26)
    border:SetPoint("CENTER", bar, "CENTER", 0, 0)
    border:SetTexture("Interface\\AchievementFrame\\UI-Achievement-ProgressBar-Border")
    border:SetTexCoord(2 / 256, 222 / 256, 2 / 32, 23 / 32)
    local barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    barText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text = barText
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        local b = Callboard.board
        if not b then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Hero's Call Cache", 1, 0.82, 0)
        GameTooltip:AddLine("Every claimed contract counts toward a cache. When the bar fills you receive a Hero's Call Cache: open it to take one piece of gear for your class and spec, above the item level you wear at that moment.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Highest item level reached", tostring(b.highestIlvl), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Equipped item level", tostring(b.equippedIlvl), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Contracts per cache", tostring(b.cacheRequired), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Caches opened", tostring(b.cachesOpened), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("The higher the item level you have ever worn, the more contracts a cache asks for.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.cacheBar = bar

    local cacheInfo = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cacheInfo:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 82, -41)
    cacheInfo:SetJustifyH("LEFT")
    mainFrame.cacheInfo = cacheInfo

    local resets = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resets:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -34, -41)
    resets:SetJustifyH("RIGHT")
    mainFrame.resets = resets

    -- ---- the list
    local scroll = CreateFrame("ScrollFrame", FRAME_NAME .. "Scroll", mainFrame, "UIPanelScrollFrameTemplate")
    scroll:SetWidth(LIST_W)
    scroll:SetHeight(LIST_H)
    scroll:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 19, -76)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(LIST_W)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    mainFrame.scroll = scroll
    mainFrame.content = content

    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("TOP", content, "TOP", 0, -30)
    empty:SetWidth(LIST_W - 30)
    empty:Hide()
    mainFrame.emptyText = empty

    mainFrame.panel = CreatePanel()

    -- ---- bottom bar
    -- across the whole left of the bottom bar, over its three slots (his call, 2026-10-08)
    local claimAll = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    claimAll:SetWidth(302)
    claimAll:SetHeight(24)
    claimAll:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 19, 12)
    claimAll:SetText("Claim All")
    claimAll:SetScript("OnClick", function() Callboard.ClaimAll() end)
    claimAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Claim every finished contract of the board, in every tab.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    claimAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.claimAll = claimAll

    local close = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    close:SetWidth(80)
    close:SetHeight(22)
    close:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -6, 14)
    close:SetText("Close")
    close:SetScript("OnClick", CloseBoard)

    -- ---- tabs under the window
    for i, cat in ipairs(Callboard.CATEGORIES) do
        tabs[i] = CreateTab(i, cat)
    end

    -- Countdown tick.
    local acc = 0
    mainFrame:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.5 then return end
        acc = 0
        UI.RefreshTimers()
    end)

    tinsert(UISpecialFrames, FRAME_NAME)
    mainFrame:SetScript("OnHide", function()
        if isInBoardGossip then
            isInBoardGossip = false
            ResetGossipFrame()
            if GossipFrameCloseButton then
                GossipFrameCloseButton:Click()
            end
        end
    end)

    return mainFrame
end

-- ------------------------------------------------------------- refresh ----

function UI.RefreshTimers()
    if not mainFrame or not mainFrame:IsShown() then return end
    local daily, weekly = Callboard.GetResetTimers()
    mainFrame.resets:SetText(string.format("Daily reset |cffffffff%s|r\nWeekly reset |cffffffff%s|r",
        FormatDuration(daily), FormatDuration(weekly)))
end

local function RefreshHeader(board)
    local bar = mainFrame.cacheBar
    if not board then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar.text:SetText(Callboard.enabled and "Loading..." or "Board disabled")
        mainFrame.cacheInfo:SetText("")
        return
    end
    local required = math.max(1, board.cacheRequired)
    local progress = math.min(board.cacheProgress, required)
    bar:SetMinMaxValues(0, required)
    bar:SetValue(progress)
    bar.text:SetText(string.format("Hero's Call Cache  %d / %d", progress, required))
    mainFrame.cacheInfo:SetText(string.format("Equipped item level |cffffffff%d|r\nCaches opened |cffffffff%d|r",
        board.equippedIlvl or 0, board.cachesOpened or 0))
end

local function RefreshTabs()
    for i, t in ipairs(tabs) do
        local cat = Callboard.CATEGORIES[i]
        local ready = 0
        for _, q in ipairs(VisibleQuests(cat.id)) do
            if q.state == Callboard.STATE.COMPLETE then ready = ready + 1 end
        end
        t:SetText(cat.name .. (ready > 0 and (" |cff1eff00(" .. ready .. ")|r") or ""))
        ResizeTab(t)
        SetTabSelected(t, cat.id == selectedCategory)
    end
end

local GROUPS = {
    { cadence = 0, label = "Today" },
    { cadence = 1, label = "This Week" },
    { cadence = 2, label = "Once Per Account" },
}

-- Lays out the list; returns the quest the panel shows.
local function RefreshList()
    local list = VisibleQuests(selectedCategory)
    local content = mainFrame.content
    local y = 0
    local nRows, nGroups = 0, 0
    local wanted = selectedQuest[selectedCategory]
    local shown, first

    -- One header per group; the open-world dailies get one per zone instead (no zone of the
    -- day since 08/10: every zone of the player's level is on the board), lowest level first,
    -- each with its level range. Only the zone the player stands in is open (2026-11-05).
    local sections = {}
    local here = GetRealZoneText()
    for _, g in ipairs(GROUPS) do
        local mine = {}
        for _, q in ipairs(list) do
            if q.cadence == g.cadence then table.insert(mine, q) end
        end
        if selectedCategory == Callboard.CATEGORY.OPEN_WORLD and g.cadence == 0 and #mine > 0 then
            local byZone, zones = {}, {}
            for _, q in ipairs(mine) do
                local zone = ZoneOf(q) or ""
                if not byZone[zone] then
                    byZone[zone] = { quests = {}, open = zone == here }
                    table.insert(zones, zone)
                end
                local z = byZone[zone]
                table.insert(z.quests, q)
                local level = LevelOf(q)
                if level then
                    z.lo = math.min(z.lo or level, level)
                    z.hi = math.max(z.hi or level, level)
                end
            end
            table.sort(zones, function(a, b)
                local la, lb = byZone[a].lo or 0, byZone[b].lo or 0
                if la ~= lb then return la < lb end
                return a < b
            end)
            for _, zone in ipairs(zones) do
                local z = byZone[zone]
                local label = zone ~= "" and zone or g.label
                if z.lo then
                    label = label .. (z.lo == z.hi and string.format(" (%d)", z.lo) or string.format(" (%d-%d)", z.lo, z.hi))
                end
                table.insert(sections, { key = g.cadence .. ":" .. zone, label = label, quests = z.quests, open = z.open })
            end
        else
            table.insert(sections, { key = tostring(g.cadence), label = g.label, quests = mine, open = true })
        end
    end

    -- the panel keeps the selected card while it is on view, else the first card on view
    local wantedAnywhere, firstAnywhere
    for _, section in ipairs(sections) do
        local mine = section.quests
        if #mine > 0 then
            local key = selectedCategory .. ":" .. section.key
            local open = sectionOpen[key]
            if open == nil then open = section.open end
            nGroups = nGroups + 1
            if not groups[nGroups] then groups[nGroups] = CreateGroupHeader(content) end
            local header = groups[nGroups]
            header.key, header.open = key, open
            header.toggle:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            header.text:SetText(section.label)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 3, -y)
            header:Show()
            y = y + GROUP_H
            for _, q in ipairs(mine) do
                firstAnywhere = firstAnywhere or q
                if q.questId == wanted then wantedAnywhere = q end
                if open then
                    nRows = nRows + 1
                    if not rows[nRows] then rows[nRows] = CreateRow(content) end
                    local row = rows[nRows]
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", content, "TOPLEFT", 3, -(y + ROW_GAP))
                    RefreshRow(row, q)
                    first = first or q
                    if q.questId == wanted then shown = q end
                    row:Show()
                    y = y + ROW_H + ROW_GAP
                end
            end
            y = y + 4
        end
    end
    for i = nRows + 1, #rows do rows[i]:Hide() end
    for i = nGroups + 1, #groups do groups[i]:Hide() end
    content:SetHeight(math.max(1, y))

    shown = shown or first or wantedAnywhere or firstAnywhere
    selectedQuest[selectedCategory] = shown and shown.questId or nil
    for i = 1, nRows do SetRowSelected(rows[i], shown ~= nil and rows[i].quest == shown) end

    if #list == 0 then
        local catName = CategoryOf(selectedCategory).name
        local board = Callboard.board
        if not board then
            mainFrame.emptyText:SetText("")     -- still loading: the bar says so
        elseif #(board.byCategory[selectedCategory] or {}) > 0 then
            mainFrame.emptyText:SetText("Every " .. catName .. " contract is done for now.\nCome back after the reset.")
        else
            mainFrame.emptyText:SetText("No " .. catName .. " contracts posted for your level right now.")
        end
        mainFrame.emptyText:Show()
    else
        mainFrame.emptyText:Hide()
    end
    return shown
end

local function ShowReward(panel, index, icon, count, kind, amount)
    local b = panel.rewards[index]
    if not b then return index end
    b.icon:SetTexture(icon)
    b.count:SetText(count)
    b.kind, b.amount = kind, amount
    b:Show()
    return index + 1
end

-- Open-world and dungeon contracts with a camp on the map (server fields 25-27, quest_poi) show
-- that zone map instead of the picture: the band around the camp, the player when in that zone,
-- the zone's Spirit Healers. Returns false when there is nothing to draw (older server, no POI,
-- a map MapAreaData does not know) - the picture stays.
local function ShowMap(panel, q)
    local map = panel.map
    local areas = ProjectEbonhold.CallboardMapAreas
    local area = (q.category == Callboard.CATEGORY.OPEN_WORLD or q.category == Callboard.CATEGORY.DUNGEON)
        and (q.poiArea or 0) > 0 and areas and areas[q.poiArea]
    if not area then
        map:Hide()
        return false
    end
    for i, t in ipairs(map.tiles) do
        t:SetTexture("Interface\\WorldMap\\" .. area.name .. "\\" .. area.name .. i)
    end
    -- world x runs north (top > bottom), world y west (left > right); returns the pin's v, nil off the map
    local function Place(pin, u, v)
        if u < 0 or u > 1 or v < 0 or v > 1 then pin:Hide(); return nil end
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", map.child, "TOPLEFT", u * ART_W, -v * MAP_H)
        pin:Show()
        return v
    end
    local function PlaceWorld(pin, x, y)
        return Place(pin, (area.left - y) / (area.left - area.right), (area.top - x) / (area.top - area.bottom))
    end
    local v = PlaceWorld(map.camp, q.poiX, q.poiY) or 0.5

    -- the zone's Spirit Healers, as the graveyard pins of the world map show them
    local zone = ProjectEbonhold.GraveyardData and ProjectEbonhold.GraveyardData[q.poiArea + 1]
    local myFaction = UnitFactionGroup("player") == "Alliance" and 469 or 67
    local n = 0
    for _, g in ipairs(zone and zone.graveyards or {}) do
        if g.faction == 0 or g.faction == myFaction then
            n = n + 1
            local pin = map.healers[n]
            if not pin then
                pin = map.Pin(18, "Spirit Healer")
                pin.icon:SetTexture("Interface\\WorldMap\\Skull_64Grey")
                map.healers[n] = pin
            end
            PlaceWorld(pin, g.x, g.y)
        end
    end
    for i = n + 1, #map.healers do map.healers[i]:Hide() end

    -- the player, when standing in that zone (GetCurrentMapAreaID = WorldMapArea id + 1)
    map.player:Hide()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then
        SetMapToCurrentZone()
        if GetCurrentMapAreaID() == q.poiArea + 1 then
            local px, py = GetPlayerMapPosition("player")
            if px and (px > 0 or py > 0) then Place(map.player, px, py) end
        end
    end

    map.label:SetText(q.category == Callboard.CATEGORY.OPEN_WORLD and (ZoneOf(q) or "") or "")
    map:UpdateScrollChildRect()
    map:SetVerticalScroll(math.max(0, math.min(MAP_H - ART_H, v * MAP_H - ART_H / 2)))
    map:Show()
    return true
end

local function RefreshPanel(q)
    local panel = mainFrame.panel
    for _, fs in ipairs(panel.objectives) do fs:SetText(""); fs:Hide() end
    for _, b in ipairs(panel.rewards) do b:Hide(); b.kind = nil end
    panel.money:SetText("")
    local action = panel.action
    action:SetScript("OnClick", nil)
    local travel = panel.travel
    travel:SetScript("OnClick", nil)
    travel.name = nil
    travel:Hide()

    if not q then
        local fallback = CATEGORY_ART[selectedCategory] or CATEGORY_ART[1]
        panel.map:Hide()
        panel.art:Show()
        panel.art:SetTexture(LOADSCREENS .. fallback[1])
        panel.art:SetTexCoord(0, 1, fallback[2], fallback[2] + ART_SLICE)
        panel.title:SetText(Callboard.board and "Nothing to take here" or BOARD_GOSSIP_NAME)
        panel.desc:SetText(Callboard.board and "Come back after the reset for new contracts." or "")
        panel.meta:SetText("")
        action:SetText("Accept")
        action:Disable()
        return
    end

    local art = ArtOf(q)
    panel.art:SetTexture(art.file)
    panel.art:SetTexCoord(0, 1, art.v0, art.v0 + ART_SLICE)
    if ShowMap(panel, q) then panel.art:Hide() else panel.art:Show() end
    panel.title:SetText(LevelTag(q) .. q.title)
    panel.desc:SetText((q.description ~= nil and q.description ~= "") and q.description or q.objectives)

    local meta
    if q.cadence == Callboard.CADENCE.ONCE then
        meta = "Once per account"
    else
        meta = string.format("%s: |cffffd100%d/%d|r claimed", q.cadence == Callboard.CADENCE.WEEKLY and "This week" or "Today", q.done, q.max)
        if q.accountWide then meta = meta .. "  -  one character of your account" end
    end
    if q.paysNothing then
        panel.meta:SetText(string.format("|cffff4040You are above level %d, the top of this contract: claiming it pays nothing.|r", q.outleveledAbove))
    else
        panel.meta:SetText(meta)
    end

    -- objectives: the quest log's tracked lines once taken, else the contract's own sentence
    local lines = (q.state ~= Callboard.STATE.AVAILABLE) and LogObjectives(q.questId) or nil
    if lines and #lines > 0 then
        for i = 1, math.min(#lines, MAX_OBJECTIVES) do
            local fs = panel.objectives[i]
            fs:SetText("- " .. lines[i].text)
            if lines[i].done then fs:SetTextColor(0.62, 0.62, 0.62) else fs:SetTextColor(1, 1, 1) end
            fs:Show()
        end
    else
        local fs = panel.objectives[1]
        fs:SetText("- " .. (q.objectives ~= "" and q.objectives or q.title))
        fs:SetTextColor(1, 1, 1)
        fs:Show()
    end

    -- rewards: one slot per currency, the item, then the gold after them
    local n = 1
    if q.ashes > 0 then n = ShowReward(panel, n, ICON_ASH, ShortCount(q.ashes), "ash", q.ashes) end
    if (q.shards or 0) > 0 then n = ShowReward(panel, n, ICON_SHARD, ShortCount(q.shards), "shard", q.shards) end
    if q.artisan > 0 then n = ShowReward(panel, n, ICON_ARTISAN, ShortCount(q.artisan), "artisan", q.artisan) end
    if (q.orbs or 0) > 0 then n = ShowReward(panel, n, ICON_ORB, ShortCount(q.orbs), "orb", q.orbs) end
    if q.xp > 0 then n = ShowReward(panel, n, ICON_XP, ShortCount(q.xp), "xp", q.xp) end
    if (q.item or 0) > 0 then
        n = ShowReward(panel, n, GetItemIcon(q.item) or "Interface\\Icons\\INV_Misc_QuestionMark",
            (q.itemCount or 1) > 1 and tostring(q.itemCount) or "", "item", q.item)
        if not GetItemInfo(q.item) then
            -- ask the client for the item so its tooltip and icon are known next refresh
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            GameTooltip:SetHyperlink("item:" .. q.item)
            GameTooltip:Hide()
        end
    end
    panel.money:ClearAllPoints()
    panel.money:SetPoint("LEFT", panel.strip, "TOPLEFT", 24 + (n - 1) * REWARD_STEP + (n > 1 and 6 or 0), -109)
    if q.copper > 0 then
        panel.money:SetText(GetCoinTextureString(q.copper))
    elseif n == 1 then
        panel.money:SetText(q.paysNothing and OutleveledText(q) or "|cff888888No reward|r")
    end

    local waystone = Callboard.GetWaystone(q.questId)
    if waystone then
        travel.name = waystone.name
        travel.known = waystone.known
        travel.icon:SetDesaturated(not waystone.known)
        if waystone.known then
            travel:Enable()
            travel:SetScript("OnClick", function() Callboard.Travel(waystone.id) end)
        else
            travel:Disable()
        end
        travel:Show()
    end

    if q.state == Callboard.STATE.COMPLETE then
        action:SetText("Claim Reward")
        action:Enable()
        action:SetScript("OnClick", function() Callboard.Claim(q.questId) end)
    elseif q.state == Callboard.STATE.ACCEPTED then
        action:SetText("Abandon")
        action:Enable()
        action:SetScript("OnClick", function()
            local popup = StaticPopup_Show("EBONHOLD_CALLBOARD_ABANDON", q.title)
            if popup then popup.data = q.questId end
        end)
    else
        action:SetText("Accept")
        action:Enable()
        action:SetScript("OnClick", function() Callboard.Accept(q.questId) end)
    end
end

-- Same words as the quest log's own abandon prompt.
StaticPopupDialogs["EBONHOLD_CALLBOARD_ABANDON"] = {
    text = "Abandon \"%s\"?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data) Callboard.Abandon(data) end,
    timeout = 0,
    whileDead = 1,
    exclusive = 1,
    hideOnEscape = 1,
}

function UI.Refresh()
    if not mainFrame or not mainFrame:IsShown() then return end
    local board = Callboard.board
    RefreshHeader(board)
    RefreshTabs()
    RefreshPanel(RefreshList())
    UI.RefreshTimers()
    local claimable = board and board.claimable or 0
    if claimable > 0 then
        mainFrame.claimAll:SetText("Claim All (" .. claimable .. ")")
        mainFrame.claimAll:Enable()
    else
        mainFrame.claimAll:SetText("Claim All")
        mainFrame.claimAll:Disable()
    end
end

function UI.Show()
    if TaxiFrame and TaxiFrame:IsShown() then return end
    CreateMainFrame()
    mainFrame:Show()
    UI.Refresh()
    Callboard.Request()
end

function UI.Hide()
    CloseBoard()
end

-- -------------------------------------------------------------- results ----

local FAIL_TEXT = {
    far         = "You must stand next to the Call Board.",
    dead        = "You cannot use the Call Board while dead.",
    unknown     = "That contract is not on the board.",
    notoffered  = "That contract is not posted for you right now.",
    inlog       = "You already hold that contract.",
    exhausted   = "You have completed that contract as many times as allowed for now.",
    full        = "Your quest log is full.",
    cannot      = "You cannot take that contract right now.",
    nothing     = "Nothing to claim: finish a contract first.",
    notcomplete = "That contract is not finished yet.",
}

local CHAT_ASH     = "|T" .. ICON_ASH .. ":14:14|t"
local CHAT_ARTISAN = "|T" .. ICON_ARTISAN .. ":14:14|t"
local CHAT_ORB     = "|T" .. ICON_ORB .. ":14:14|t"
local CHAT_SHARD   = "|T" .. ICON_SHARD .. ":14:14|t"

-- A cache is earned as an object (Hero's Call Cache): the gear comes when the player opens it.
local function AnnounceCache(entry)
    local name, link = GetItemInfo(entry)
    if link then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF66CCFF[Call Board]|r You earn a " .. link .. " - open it to take what it holds.")
        local icon = GetItemIcon(entry)
        if icon and UIErrorsFrame then
            UIErrorsFrame:AddMessage("You earn a Hero's Call Cache!", 0.4, 0.8, 1.0, 1.0)
        end
    else
        -- Not in the client cache yet: ask for it and retry once it arrives.
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink("item:" .. entry)
        GameTooltip:Hide()
        local waiter = CreateFrame("Frame")
        local tries = 0
        waiter:SetScript("OnUpdate", function(self, elapsed)
            tries = tries + 1
            local n, l = GetItemInfo(entry)
            if l then
                self:SetScript("OnUpdate", nil)
                DEFAULT_CHAT_FRAME:AddMessage("|cFF66CCFF[Call Board]|r You earn a " .. l .. " - open it to take what it holds.")
            elseif tries > 300 then
                self:SetScript("OnUpdate", nil)
                DEFAULT_CHAT_FRAME:AddMessage("|cFF66CCFF[Call Board]|r You earn a cache - open it to take what it holds.")
            end
        end)
    end
end

Callboard.OnChanged(function(event, payload)
    if event == "board" then
        UI.Refresh()
    elseif event == "result" then
        local r = payload
        if not r.ok then
            local text = FAIL_TEXT[r.reason] or ("Call Board: " .. tostring(r.reason))
            UIErrorsFrame:AddMessage(text, 1.0, 0.3, 0.3, 1.0)
            return
        end
        if r.op == "claim" then
            local parts = {}
            if r.ashes > 0 then table.insert(parts, FormatThousands(r.ashes) .. " Soul Ashes " .. CHAT_ASH) end
            if r.copper > 0 then table.insert(parts, GetCoinTextureString(r.copper)) end
            if r.xp > 0 then table.insert(parts, FormatThousands(r.xp) .. " XP") end
            if r.artisan > 0 then table.insert(parts, r.artisan .. " Artisan Soul" .. (r.artisan > 1 and "s" or "") .. " " .. CHAT_ARTISAN) end
            if (r.orbs or 0) > 0 then table.insert(parts, r.orbs .. " Orb" .. (r.orbs > 1 and "s" or "") .. " of Lost Memories " .. CHAT_ORB) end
            if (r.shards or 0) > 0 then table.insert(parts, FormatThousands(r.shards) .. " Soul Shards " .. CHAT_SHARD) end
            local paid = #parts > 0 and table.concat(parts, "  ") or "no reward"
            -- an outleveled claim (r.outleveled) pays less, with no extra line: the figures say it (his call, 11/10)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF66CCFF[Call Board]|r %d contract%s claimed: %s",
                r.count, r.count > 1 and "s" or "", paid))
            for _, entry in ipairs(r.caches or {}) do
                AnnounceCache(entry)
            end
            for _, it in ipairs(r.items or {}) do
                local _, link = GetItemInfo(it.entry)
                DEFAULT_CHAT_FRAME:AddMessage("|cFF66CCFF[Call Board]|r You receive " .. (link or ("item " .. it.entry)) .. (it.count > 1 and (" x" .. it.count) or "") .. ".")
            end
        end
    end
end)

-- The objectives of the panel follow the quest log while the window is open, the Open World tab
-- the player's zone.
local logWatcher = CreateFrame("Frame")
logWatcher:RegisterEvent("QUEST_LOG_UPDATE")
logWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
logWatcher:SetScript("OnEvent", function()
    if mainFrame and mainFrame:IsShown() then UI.Refresh() end
end)

-- ---------------------------------------------------------------- gossip ----

local gossipEventFrame = CreateFrame("Frame")
gossipEventFrame:RegisterEvent("GOSSIP_SHOW")
gossipEventFrame:RegisterEvent("GOSSIP_CLOSED")
gossipEventFrame:SetScript("OnEvent", function(self, event)
    if event == "GOSSIP_SHOW" then
        if not GossipFrame or not GossipFrame:IsShown() then
            return
        end
        local npcName = GossipFrameNpcNameText and GossipFrameNpcNameText:GetText()
        if npcName and BOARD_GOSSIP_NAMES[npcName] then
            isInBoardGossip = true
            GossipFrame:SetAlpha(0)
            GossipFrame:EnableMouse(false)
            GossipFrame:ClearAllPoints()
            GossipFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 1000, -1000)
            UI.Show()
        elseif mainFrame and mainFrame:IsShown() then
            -- talking to someone else closes the board
            isInBoardGossip = false
            mainFrame:Hide()
        end
    elseif event == "GOSSIP_CLOSED" then
        -- The hidden gossip session ends without the player asking: a step away from the board,
        -- another left-hand panel taking its slot, a claim (the quest-complete packet ends the
        -- interaction). The window used to close with it, "on its own" (2026-10-08); it now stays
        -- until the player closes it. Accept / claim away from the board get the server's
        -- "You must stand next to the Call Board".
        if isInBoardGossip then
            isInBoardGossip = false
            ResetGossipFrame()
        end
    end
end)

-- Close the board when another panel opens, as every custom panel does.
local framesToWatch = {
    "CharacterFrame", "TalentFrame", "SpellBookFrame", "QuestLogFrame", "QuestLogDetailFrame",
    "FriendsFrame", "PVPFrame", "AchievementFrame", "GuildFrame", "LFGParentFrame",
    "PlayerTalentFrame", "LFDParentFrame", "WorldMapFrame", "GameMenuFrame",
    "EbonholdTalentFrame",
}
for _, frameName in ipairs(framesToWatch) do
    local frame = _G[frameName]
    if frame then
        frame:HookScript("OnShow", function(self)
            -- The quest tracker opens the world map at alpha 0 for two frames to read the quest
            -- POIs, ~0.7 s after every accept and every finished objective (super_tracker.lua,
            -- PulseWorldMapForPOIs): that is no panel opening. It closed the board right after
            -- a contract was taken - the "closes on its own" of 2026-10-08.
            if self:GetAlpha() < 0.05 then return end
            if mainFrame and mainFrame:IsShown() then
                CloseBoard()
            end
        end)
    end
end

-- /callboard opens the window read-only (accept/claim still need the board nearby).
SLASH_EBONHOLDCALLBOARD1 = "/callboard"
SlashCmdList["EBONHOLDCALLBOARD"] = function()
    if mainFrame and mainFrame:IsShown() then
        CloseBoard()
    else
        UI.Show()
    end
end
