-- ==============================================================================
-- Death contracts (server: ContractMgr): the Spirit Healer window.
--
-- A living player who talks to a Spirit Healer gets this window instead of a gossip menu:
-- one contract per content within the character's reach (zones: kill 50, dungeons and raids:
-- every boss, and again without dying) in a scrollable list: take / return, each fulfilled
-- once per run; and the offering (the graveyard bank) with the contract bonus applied. The
-- bonus is the gauge on the run frame; it only pays here.
--
-- Wire:
--   SS.SEND_CONTRACTS (1237): "<gauge>;<used>;<max>;<price copper>;<run ashes>;<run shards>;<open 0/1>;<unused, was taken this week>;<unused, was per week: no weekly limit since 2026-10-18>;<anchor price ashes>;<anchor state>;<anchor place>|<contracts>"
--     anchor state 0 no anchor / 1 anchored at this healer / 2 anchored elsewhere (<anchor place>)
--     contract "<key>~<kind>~<state>~<torment>~<level80 0/1>~<required>~<progress>~<bonus>~<title>~<name>~<map>~<zone>~<level max>
--               ~<level>~<duration s>~<started 0/1>~<remaining s>" joined by ';'
--     level max = top of the content's level window: past it nothing counts (0 = no cap)
--     level = the content's entry level, the "[N]" of the title
--     the hourglass (2026-10-15): a taken contract has <duration> seconds once its first kill
--     counts (started 1, <remaining> left); at zero it is lost, the server says so on the next
--     push, which the addon asks for itself when its own hourglass runs out.
--     kind 1 zone kills / 2 instance clear (every boss dead) / 3 flawless clear ; state 0 available / 1 taken / 2 done
--   CS.REQUEST_CONTRACTS (1237) ""            -> resend
--   CS.REQUEST_CONTRACT_ACTION (1238) "<key>,accept|abandon"
--   CS.REQUEST_SOUL_BANK (1239) ""            -> the offering (12 s channel by the Spirit Healer)
--   CS.REQUEST_SOUL_ANCHOR (1280) "" | "clear" -> the soul anchor: pay the run's ashes so death
--     sends you back to this spirit, wherever you die; "clear" releases it, free.
-- The window opens when the push says so (the gossip); other pushes only refresh it if shown.
-- ==============================================================================
local CT = {}
ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.Contracts = CT

local C_BONUS  = { 1.0, 0.82, 0.0 }      -- the bonus is a gain: gold, never red

local HOURGLASS = "Interface\\AddOns\\ProjectEbonhold\\assets\\hourglass"
local C_SAND   = { 0.93, 0.76, 0.38 }        -- the hourglass bar while time is left
local C_LATE   = { 0.89, 0.23, 0.23 }        -- what it slides to as the time runs out
CT.HOURGLASS = HOURGLASS

local KIND_ICON = {
    [1] = "Interface\\Icons\\Ability_Warrior_Cleave",
    [2] = "Interface\\Icons\\Achievement_Boss_LichKing",
    [3] = "Interface\\Icons\\Spell_Holy_HolyProtection",
}

local MAX_ACTIVE = 1                     -- contracts held at once (ContractMgr::MAX_ACTIVE, one since 2026-10-17)
CT.gauge, CT.used, CT.max, CT.price, CT.ashes, CT.shards = 0, 0, 5, 0, 0, 0
CT.anchorPrice, CT.anchorState, CT.anchorPlace = 0, 0, ""  -- soul anchor: price in ashes, 0 none / 1 here / 2 elsewhere, place
CT.list = {}
CT.received = false
local frame
local cards = {}

local function fmtNumber(n)
    if ProjectEbonhold.FormatNumber then return ProjectEbonhold.FormatNumber(n) end
    local s = tostring(math.floor(n + 0.5))
    while true do
        local k
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

-- 5g 20s -> "5 [gold] 20 [silver]" with the coin icons
local function fmtMoney(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out = ""
    if g > 0 then out = out .. g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t " end
    if s > 0 or g > 0 then out = out .. s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t " end
    if c > 0 or out == "" then out = out .. c .. "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t" end
    return (out:gsub("%s+$", ""))
end

-- One icon per instance: its final boss's achievement icon where 3.3.5 has one, else the
-- instance achievement's art (Achievement.dbc x SpellIcon.dbc, DungeonEncounter.dbc for the boss).
local BOSS_ICON = {
    [389] = "Interface\\Icons\\Spell_Shadow_SummonFelGuard", -- Ragefire Chasm: Taragaman the Hungerer
    [36] = "Interface\\Icons\\Achievement_Boss_EdwinVancleef", -- The Deadmines: Edwin VanCleef
    [43] = "Interface\\Icons\\Achievement_Boss_Mutanus_the_Devourer", -- Wailing Caverns: Mutanus the Devourer
    [33] = "Interface\\Icons\\Achievement_Boss_ArchmageArugal", -- Shadowfang Keep: Archmage Arugal
    [34] = "Interface\\Icons\\Achievement_Boss_Bazil_Thredd", -- The Stockade: Bazil Thredd
    [48] = "Interface\\Icons\\Achievement_Boss_Bazil_Akumai", -- Blackfathom Deeps: Aku'mai
    [90] = "Interface\\Icons\\Achievement_Boss_Mekgineer_Thermaplugg", -- Gnomeregan: Mekgineer Thermaplugg
    [47] = "Interface\\Icons\\Achievement_Boss_CharlgaRazorflank", -- Razorfen Kraul: Death Speaker Jargba
    [189] = "Interface\\Icons\\INV_Helmet_52", -- Scarlet Monastery: High Inquisitor Whitemane
    [129] = "Interface\\Icons\\Achievement_Boss_Amnennar_the_Coldbringer", -- Razorfen Downs: Amnennar the Coldbringer
    [70] = "Interface\\Icons\\Achievement_Boss_Archaedas", -- Uldaman: Archaedas
    [209] = "Interface\\Icons\\Achievement_Boss_ChiefUkorzSandscalp", -- Zul'Farrak: Chief Ukorz Sandscalp
    [349] = "Interface\\Icons\\Achievement_Boss_PrincessTheradras", -- Maraudon: Princess Theradras
    [109] = "Interface\\Icons\\Achievement_Boss_ShadeOfEranikus", -- Sunken Temple: Shade of Eranikus
    [230] = "Interface\\Icons\\Achievement_Boss_EmperorDagranThaurissan", -- Blackrock Depths: Emperor Dagran Thaurissan
    [229] = "Interface\\Icons\\Achievement_Boss_Drakkisath", -- Blackrock Spire: General Drakkisath
    [429] = "Interface\\Icons\\Ability_Warrior_DecisiveStrike", -- Dire Maul: King Gordok
    [289] = "Interface\\Icons\\Spell_Holy_SenseUndead", -- Scholomance: Darkmaster Gandling
    [329] = "Interface\\Icons\\Spell_DeathKnight_ArmyOfTheDead", -- Stratholme: Baron Rivendare
    [543] = "Interface\\Icons\\Achievement_Boss_OmarTheUnscarred_01", -- Hellfire Ramparts: Vazruden the Herald
    [542] = "Interface\\Icons\\Achievement_Boss_KelidanTheBreaker", -- The Blood Furnace: Keli'dan the Breaker
    [540] = "Interface\\Icons\\Achievement_Boss_KargathBladefist_01", -- The Shattered Halls: Warchief Kargath Bladefist
    [547] = "Interface\\Icons\\Achievement_Boss_Quagmirran", -- The Slave Pens: Quagmirran
    [546] = "Interface\\Icons\\Achievement_Boss_theBlackStalker", -- The Underbog: The Black Stalker
    [545] = "Interface\\Icons\\Achievement_Boss_Warlord_Kalithresh", -- The Steamvault: Warlord Kalithresh
    [557] = "Interface\\Icons\\Achievement_Boss_Nexus_Prince_Shaffar", -- Mana-Tombs: Nexus-Prince Shaffar
    [558] = "Interface\\Icons\\Achievement_Boss_Exarch_Maladaar", -- Auchenai Crypts: Exarch Maladaar
    [556] = "Interface\\Icons\\Achievement_Boss_TalonKingIkiss", -- Sethekk Halls: Talon King Ikiss
    [555] = "Interface\\Icons\\Achievement_Boss_Murmur", -- Shadow Labyrinth: Murmur
    [560] = "Interface\\Icons\\Achievement_Boss_EpochHunter", -- Old Hillsbrad Foothills: Epoch Hunter
    [269] = "Interface\\Icons\\Achievement_Boss_Aeonus_01", -- The Black Morass: Aeonus
    [554] = "Interface\\Icons\\Achievement_Boss_PathaleonTheCalculator", -- The Mechanar: Pathaleon the Calculator
    [553] = "Interface\\Icons\\Achievement_Boss_WarpSplinter", -- The Botanica: Warp Splinter
    [552] = "Interface\\Icons\\Achievement_Boss_Harbinger_Skyriss", -- The Arcatraz: Harbinger Skyriss
    [585] = "Interface\\Icons\\Achievement_Boss_Kael'thasSunstrider_01", -- Magisters' Terrace: Kael'thas Sunstrider
    [574] = "Interface\\Icons\\Achievement_Dungeon_UtgardeKeep_Normal", -- Utgarde Keep: Ingvar the Plunderer
    [576] = "Interface\\Icons\\Achievement_Boss_Keristrasza", -- The Nexus: Keristrasza
    [601] = "Interface\\Icons\\Achievement_Boss_Anubarak", -- Azjol-Nerub: Anub'arak
    [619] = "Interface\\Icons\\Achievement_Boss_HeraldVolazj", -- Ahn'kahet: The Old Kingdom: Herald Volazj
    [600] = "Interface\\Icons\\Achievement_Dungeon_Drak'Tharon_Normal", -- Drak'Tharon Keep: The Prophet Tharon'ja
    [608] = "Interface\\Icons\\Achievement_Boss_cyanigosa", -- The Violet Hold: Cyanigosa
    [604] = "Interface\\Icons\\Achievement_Boss_Galdarah", -- Gundrak: Gal'darah
    [599] = "Interface\\Icons\\Achievement_Boss_Sjonnir", -- Halls of Stone: Sjonnir the Ironshaper
    [602] = "Interface\\Icons\\Achievement_Dungeon_Ulduar80_Normal", -- Halls of Lightning: Loken
    [578] = "Interface\\Icons\\Achievement_Boss_Eregos", -- The Oculus: Ley-Guardian Eregos
    [575] = "Interface\\Icons\\Achievement_Boss_KingYmiron", -- Utgarde Pinnacle: King Ymiron
    [595] = "Interface\\Icons\\Achievement_Dungeon_CoTStratholme_Normal", -- The Culling of Stratholme: Mal'ganis
    [650] = "Interface\\Icons\\INV_Spear_05", -- Trial of the Champion: The Black Knight
    [632] = "Interface\\Icons\\achievement_boss_devourerofsouls", -- The Forge of Souls: Devourer of Souls
    [658] = "Interface\\Icons\\achievement_boss_scourgelordtyrannus", -- Pit of Saron: Overlrod Tyrannus
    [668] = "Interface\\Icons\\achievement_dungeon_icecrown_hallsofreflection", -- Halls of Reflection: Escaped from Arthas
    [249] = "Interface\\Icons\\Achievement_Boss_Onyxia", -- Onyxia's Lair: Onyxia
    [309] = "Interface\\Icons\\Achievement_Boss_Hakkar", -- Zul'Gurub: High Priestess Jeklik
    [409] = "Interface\\Icons\\Achievement_Boss_Ragnaros", -- Molten Core: Ragnaros
    [469] = "Interface\\Icons\\Achievement_Boss_Nefarion", -- Blackwing Lair: Nefarian
    [509] = "Interface\\Icons\\Achievement_Boss_OssirianTheUnscarred", -- Ruins of Ahn'Qiraj: Ossirian the Unscarred
    [531] = "Interface\\Icons\\Achievement_Boss_CThun", -- Temple of Ahn'Qiraj: C'thun
    [532] = "Interface\\Icons\\Achievement_Boss_PrinceMalchezaar_02", -- Karazhan: Nightbane
    [565] = "Interface\\Icons\\Achievement_Boss_GruulTheDragonkiller", -- Gruul's Lair: Gruul the Dragonkiller
    [544] = "Interface\\Icons\\Achievement_Boss_Magtheridon", -- Magtheridon's Lair: Magtheridon
    [548] = "Interface\\Icons\\Achievement_Boss_LadyVashj", -- Serpentshrine Cavern: Lady Vashj
    [550] = "Interface\\Icons\\Achievement_Boss_Kael'thasSunstrider_01", -- Tempest Keep: Kael'thas Sunstrider
    [534] = "Interface\\Icons\\Achievement_Boss_Archimonde", -- Hyjal Summit: Archimonde
    [564] = "Interface\\Icons\\Achievement_Boss_Illidan", -- Black Temple: Illidan Stormrage
    [568] = "Interface\\Icons\\Achievement_Boss_Zuljin", -- Zul'Aman: Zul'jin
    [580] = "Interface\\Icons\\Achievement_Boss_Kiljaedan", -- Sunwell Plateau: Kil'jaeden
    [533] = "Interface\\Icons\\achievement_boss_kelthuzad_01", -- Naxxramas: Kel'Thuzad
    [615] = "Interface\\Icons\\Achievement_Boss_Sartharion_01", -- The Obsidian Sanctum: Vesperon
    [616] = "Interface\\Icons\\Achievement_Boss_Malygos_01", -- The Eye of Eternity: Malygos
    [624] = "Interface\\Icons\\Spell_Frost_ChillingBlast", -- Vault of Archavon: Toravon the Ice Watcher
    [603] = "Interface\\Icons\\Achievement_Boss_YoggSaron_01", -- Ulduar: Algalon the Observer
    [649] = "Interface\\Icons\\Achievement_Boss_Anubarak", -- Trial of the Crusader: Anub'arak
    [631] = "Interface\\Icons\\achievement_boss_lichking", -- Icecrown Citadel: The Lich King
    [724] = "Interface\\Icons\\Spell_Shadow_Twilight", -- The Ruby Sanctum: General Zarithrian
}

-- The content's own icon: the final boss for an instance (BOSS_ICON), the zone's "Explore"
-- achievement art for a zone (content_icons.lua); the kind only when nothing is known.
function CT.IconFor(c)
    if (c.zoneId or 0) == 0 and BOSS_ICON[c.mapId or 0] then return BOSS_ICON[c.mapId] end
    local icons = ProjectEbonhold.ContentIcons
    if icons and icons.IconPath and (c.zoneId or 0) > 0 then
        return icons.IconPath({ mapId = c.mapId, zoneId = c.zoneId })
    end
    return KIND_ICON[c.kind] or KIND_ICON[1]
end

-- An instance is done when every boss is dead, in any order (2026-10-05).
function CT.ExecutionGoal()
    return "Kill every boss of "
end

-- "Kill 50 creatures in Icecrown, Torment 4 or higher"
function CT.Describe(c)
    local where = c.level80 and (c.name .. " at level 80") or c.name
    local t = (c.torment or 0) > 0 and (", Torment " .. c.torment .. " or higher") or ""
    if c.kind == 1 then return "Kill " .. c.required .. " creatures in " .. where .. t end
    if c.kind == 2 then return CT.ExecutionGoal(c) .. where .. t end
    return where
end

-- A contract is done inside its content's level window: past its max level nothing counts.
-- No label for endgame content (its window ends at the level cap).
function CT.Outgrown(c)
    return (c.levelMax or 0) > 0 and UnitLevel("player") > c.levelMax
end

function CT.LevelText(c)
    if (c.levelMax or 0) == 0 or c.levelMax >= 80 then return "" end
    return "Level " .. c.levelMax .. " max"
end

-- "[18-34] Ashenvale": the content's level window, then its name ("[72]" when the window
-- ends at the level cap); the window turns red once the character is past it
function CT.Heading(c)
    local name = c.name ~= "" and c.name or (c.title ~= "" and c.title or "Contract")
    if (c.level or 0) == 0 then return name end
    local range = tostring(c.level)
    if CT.LevelText(c) ~= "" and c.levelMax > c.level then range = range .. "-" .. c.levelMax end
    if CT.Outgrown(c) then return "|cffe23b3b[" .. range .. "]|r " .. name end
    return "[" .. range .. "] " .. name
end

-- the time a contract gives, once its first kill counts: "10 min" ("" = no hourglass; raids have one since 2026-10-22)
function CT.HasHourglass(c)
    return (c.duration or 0) > 0
end

function CT.DurationText(c)
    if not CT.HasHourglass(c) then return "" end
    return math.floor(c.duration / 60 + 0.5) .. " min"
end

-- the hourglass: running once the first kill counted, until its time is out
function CT.IsRunning(c)
    return c.state == 1 and c.endsAt ~= nil
end

function CT.TimeLeft(c)
    if not c.endsAt then return c.duration or 0 end
    return math.max(0, c.endsAt - GetTime())
end

-- 452 -> "7:32", 4210 -> "1:10:10"
function CT.FormatTime(sec)
    sec = math.max(0, math.ceil(sec))
    local h, m, s = math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- the colour of the time left: sand when it starts, sliding to red as it runs out (the bar
-- and the hourglass both take it)
function CT.TimeColor(c)
    local d = c.duration or 0
    if d <= 0 then return C_SAND end
    local f = math.min(1, math.max(0, CT.TimeLeft(c) / d))
    return {
        C_LATE[1] + (C_SAND[1] - C_LATE[1]) * f,
        C_LATE[2] + (C_SAND[2] - C_LATE[2]) * f,
        C_LATE[3] + (C_SAND[3] - C_LATE[3]) * f,
    }
end

-- the running contract with the least time left (the run frame shows that one), or nil
function CT.Running()
    local best
    for _, c in ipairs(CT.list) do
        if CT.IsRunning(c) and (not best or c.endsAt < best.endsAt) then best = c end
    end
    return best
end

-- a taken contract whose hourglass waits for its first kill (the shortest one), or nil: the
-- run frame already shows its glass, full and still
function CT.Waiting()
    local best
    for _, c in ipairs(CT.list) do
        if c.state == 1 and CT.HasHourglass(c) and not CT.IsRunning(c) and (not best or c.duration < best.duration) then best = c end
    end
    return best
end

-- one colour per state: available in the healer's blue, in progress in amber, done in green
function CT.StateText(c)
    if c.state == 2 then return "|cff80d6a0Completed - bonus added|r" end
    if c.state == 1 then
        if c.kind == 1 then return "|cffe0a040In progress - " .. c.progress .. " / " .. c.required .. "|r" end
        return "|cffe0a040In progress|r"
    end
    return "|cff9fd6ffAvailable|r"
end

function CT.ActiveCount()
    local n = 0
    for _, c in ipairs(CT.list) do if c.state == 1 then n = n + 1 end end
    return n
end

function CT.FulfilledCount()
    local n = 0
    for _, c in ipairs(CT.list) do if c.state == 2 then n = n + 1 end end
    return n
end

-- the list order: what is being done first, then what can be taken; inside each, the biggest
-- bonus first (owner, 2026-10-22). The fulfilled ones are not shown (owner, 2026-10-25): the
-- server still sends them, so they stay out of the offer for the rest of the run.
local function Sorted()
    local out = {}
    for _, c in ipairs(CT.list) do
        if c.state ~= 2 then table.insert(out, c) end
    end
    local rank = { [1] = 0, [0] = 1 }
    table.sort(out, function(a, b)
        if rank[a.state] ~= rank[b.state] then return rank[a.state] < rank[b.state] end
        if a.bonus ~= b.bonus then return a.bonus > b.bonus end
        return a.order < b.order
    end)
    return out
end

-- ------------------------------------------------------------------ parsing

local function parse(body)
    local head, list = strsplit("|", body or "")
    local gauge, used, max, price, ashes, shards, open, _, _, anchorPrice, anchorState, anchorPlace = strsplit(";", head or "")
    CT.open = (tonumber(open) or 0) == 1
    CT.gauge = tonumber(gauge) or 0
    CT.used = tonumber(used) or 0
    CT.max = tonumber(max) or 5
    CT.price = tonumber(price) or 0
    CT.ashes = tonumber(ashes) or 0
    CT.shards = tonumber(shards) or 0
    CT.anchorPrice = tonumber(anchorPrice) or 0
    CT.anchorState = tonumber(anchorState) or 0
    CT.anchorPlace = anchorPlace or ""
    CT.list = {}
    if list and list ~= "" then
        for i, item in ipairs({ strsplit(";", list) }) do
            local key, kind, state, torment, level80, required, progress, bonus, title, name, mapId, zoneId, levelMax,
                level, duration, started, remaining = strsplit("~", item)
            if key and kind then
                local c = {
                    key = key, kind = tonumber(kind) or 1, state = tonumber(state) or 0,
                    torment = tonumber(torment) or 0, level80 = (tonumber(level80) or 0) == 1,
                    required = tonumber(required) or 1, progress = tonumber(progress) or 0,
                    bonus = tonumber(bonus) or 0, title = title or "", name = name or "", order = i,
                    mapId = tonumber(mapId) or 0, zoneId = tonumber(zoneId) or 0,
                    levelMax = tonumber(levelMax) or 0,
                    level = tonumber(level) or 0, duration = tonumber(duration) or 0,
                }
                -- the server sends the seconds left, never a clock: no skew between the two
                if (tonumber(started) or 0) == 1 then c.endsAt = GetTime() + (tonumber(remaining) or 0) end
                table.insert(CT.list, c)
            end
        end
    end
    CT.received = true
end

-- ------------------------------------------------------------------ frame

-- The talent window's dress (his pick, variant B of the 2026-09-30 mock-ups): the portrait
-- frame with the Spirit Healer's face, a header strip with the bonus and the run, a marble
-- inset holding one row per contract, the addon's red buttons along the bottom edge (the
-- talent window's Apply / Cancel, his rule: every button of the interface is that one).
local FRAME_W, FRAME_H = 490, 498
local HEADER_H = 62                              -- title bar + header strip, above the inset
local BOTTOM_H = 42                              -- button bar, under the inset
local ROW_H, ROW_GAP = 48, 2
local ROW_H_TAKEN = 70                           -- a taken row: one more line for its bar and hourglass
local ICON_SIZE = 34
local C_TAKEN  = { 0.35, 0.60, 1.00 }            -- the taken row's wash and its state text
local C_STATE  = { 0.60, 0.85, 1.00 }
local ASH_ICON   = "|TInterface\\Icons\\inv_soulash:14:14:0:0|t"
local SHARD_ICON = "|TInterface\\Icons\\inv_10_jewelcrafting3_soulcage_frost:14:14:0:0|t"
local HIGHLIGHT  = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"

-- 3.3.5 has no Region:SetShown
local function Shown(region, show)
    if show then region:Show() else region:Hide() end
end

-- The addon's button (utils.CreateSimpleCustomButton) with a smaller font: the bottom ones
-- carry a price. It has no disabled text colour of its own, so SetUsable greys the text.
local function RedButton(parent, label, onClick, width, height, fontSize)
    local b = utils.CreateSimpleCustomButton(parent, label, onClick, width, height)
    if b.text then b.text:SetFont("Fonts\\FRIZQT__.TTF", fontSize or 11) end
    b.SetUsable = function(self, usable)
        if usable then
            self:Enable(); self:SetTextColor(1, 1, 1)
        else
            self:Disable(); self:SetTextColor(0.55, 0.55, 0.55)
        end
    end
    return b
end

-- One contract: a row of the inset, the content's icon in an action-slot frame, the kind in
-- gold, what to do in white, the bonus on the right. A taken row carries the blue wash and a
-- small button to give it back; clicking an available row takes it.
local function CreateCard(parent, index)
    local card = CreateFrame("Button", nil, parent)
    card:SetHeight(ROW_H)

    local stripe = card:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(card)
    stripe:SetTexture(1, 1, 1, 0.04)
    card.stripe = stripe

    local wash = card:CreateTexture(nil, "BORDER")
    wash:SetAllPoints(card)
    wash:SetTexture(HIGHLIGHT)
    wash:SetBlendMode("ADD")
    wash:SetVertexColor(C_TAKEN[1], C_TAKEN[2], C_TAKEN[3])
    wash:SetAlpha(0.35)
    card.wash = wash

    local hover = card:CreateTexture(nil, "BORDER")
    hover:SetAllPoints(card)
    hover:SetTexture(HIGHLIGHT)
    hover:SetBlendMode("ADD")
    hover:SetAlpha(0.3)
    hover:Hide()
    card.hover = hover

    -- the icon as the game draws one: trimmed of its border, framed by the action-slot art
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", card, "LEFT", 10, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.icon = icon
    local slot = card:CreateTexture(nil, "OVERLAY")
    slot:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    slot:SetSize(ICON_SIZE * 1.7, ICON_SIZE * 1.7)
    slot:SetPoint("CENTER", icon, "CENTER", 0, -1)

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 56, -8)
    title:SetJustifyH("LEFT")
    card.title = title

    -- "in progress" / "23 / 50", right after the kind
    local state = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    state:SetPoint("LEFT", title, "RIGHT", 8, 0)
    state:SetTextColor(C_STATE[1], C_STATE[2], C_STATE[3])
    card.state = state

    -- "7 min", the time the contract gives: on the title's line, right-aligned before the bonus
    local duration = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    duration:SetJustifyH("RIGHT")
    duration:SetTextColor(0.63, 0.63, 0.63)
    card.duration = duration

    local desc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    desc:SetPoint("RIGHT", card, "RIGHT", -84, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    card.desc = desc

    -- what fulfilling it is worth, in the gold the game uses for a gain
    local bonus = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bonus:SetFont("Fonts\\FRIZQT__.TTF", 14)
    bonus:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -8)
    bonus:SetJustifyH("RIGHT")
    bonus:SetTextColor(unpack(C_BONUS))
    card.bonus = bonus
    duration:SetPoint("RIGHT", bonus, "LEFT", -8, 0)

    local check = card:CreateTexture(nil, "OVERLAY")
    check:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
    check:SetSize(16, 16)
    check:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 6)
    check:Hide()
    card.check = check

    -- its own line under the description (taken rows are ROW_H_TAKEN high), never over the text
    local prog = CreateFrame("StatusBar", nil, card)
    prog:SetSize(200, 5)
    prog:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    prog:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    prog:SetStatusBarColor(C_BONUS[1], C_BONUS[2], C_BONUS[3])
    prog:SetMinMaxValues(0, 1)
    local pbg = prog:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints(prog)
    pbg:SetTexture(0, 0, 0, 0.6)
    prog:Hide()
    card.prog = prog

    -- the hourglass once the contract runs: the bar above drains, the sand glass and the time
    -- left sit at its right end
    local glass = card:CreateTexture(nil, "OVERLAY")
    glass:SetTexture(HOURGLASS)
    glass:SetSize(22, 22)
    glass:SetPoint("LEFT", prog, "RIGHT", 6, 0)
    glass:Hide()
    card.glass = glass
    local timeLeft = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeLeft:SetPoint("LEFT", glass, "RIGHT", 3, 0)
    timeLeft:Hide()
    card.timeLeft = timeLeft

    local ret = RedButton(card, "Cancel", function()
        local c = card.data
        if c and c.state == 1 then CT.ConfirmCancel(c) end
    end, 70, 25, 10)
    ret:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 4)
    ret:Hide()
    card.btnRed = ret

    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        local c = self.data
        if not c then return end
        if c.state == 0 and CT.ActiveCount() < MAX_ACTIVE then self.hover:Show() end
        -- short on purpose: the goal, then label / value pairs, then one line saying what now
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(CT.Heading(c), 1, 0.82, 0)
        local where = c.level80 and (c.name .. " at level 80") or c.name
        GameTooltip:AddLine(c.kind == 1 and ("Kill " .. c.required .. " creatures in " .. where) or (CT.ExecutionGoal(c) .. where), 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Bonus", "+" .. c.bonus .. "%", 0.7, 0.7, 0.7, 1, 0.82, 0)
        if (c.torment or 0) > 0 then
            GameTooltip:AddDoubleLine("Torment", c.torment .. " or higher", 0.7, 0.7, 0.7, 1, 1, 1)
        end
        if CT.LevelText(c) ~= "" then
            if CT.Outgrown(c) then
                GameTooltip:AddDoubleLine("Level", c.levelMax .. " max", 0.7, 0.7, 0.7, 0.89, 0.23, 0.23)
            else
                GameTooltip:AddDoubleLine("Level", c.levelMax .. " max", 0.7, 0.7, 0.7, 1, 1, 1)
            end
        end
        if c.state == 1 and c.kind == 1 then
            GameTooltip:AddDoubleLine("Progress", c.progress .. " / " .. c.required, 0.7, 0.7, 0.7, 1, 1, 1)
        end
        if CT.IsRunning(c) then
            local tc = CT.TimeColor(c)
            GameTooltip:AddDoubleLine("Time left", CT.FormatTime(CT.TimeLeft(c)), 0.7, 0.7, 0.7, tc[1], tc[2], tc[3])
        elseif c.state ~= 2 and CT.HasHourglass(c) then
            GameTooltip:AddDoubleLine("Time", CT.DurationText(c) .. " from your first kill", 0.7, 0.7, 0.7, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        if c.state == 2 then
            GameTooltip:AddLine("Fulfilled", 0.5, 0.84, 0.63)
        elseif c.state == 1 and CT.Outgrown(c) then
            GameTooltip:AddLine("You are past its level: nothing counts any more", 0.89, 0.23, 0.23, true)
        elseif c.state == 1 then
            GameTooltip:AddLine(CT.HasHourglass(c) and "Lost if you die or if the hourglass runs out" or "Lost if you die", 0.89, 0.23, 0.23, true)
        elseif CT.ActiveCount() >= MAX_ACTIVE then
            GameTooltip:AddLine("You already hold a contract: fulfil or cancel it first", 0.89, 0.23, 0.23, true)
        else
            GameTooltip:AddLine("Click to take it", 0.1, 1, 0.1)
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip:Hide() end)
    card:SetScript("OnClick", function(self)
        local c = self.data
        if c and c.state == 0 and CT.ActiveCount() < MAX_ACTIVE then CT.ConfirmTake(c) end
    end)

    return card
end

-- The portrait frame and its marble inset (ezCollectionsPortraitFrameTemplateNoCloseButton +
-- InsetFrameTemplate, the collections module's templates, as the talent window builds them).
-- The window is first built on a server push, long after every module has loaded; the plain
-- dialog border is the fallback if the templates are missing.
local function CreateChrome()
    local ok, chrome = pcall(CreateFrame, "Frame", nil, frame, "ezCollectionsPortraitFrameTemplateNoCloseButton")
    if not ok or not chrome then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32, tile = true, tileSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        head:SetPoint("TOP", frame, "TOP", 0, -16)
        head:SetText("Death Contracts")
        return
    end
    chrome:SetAllPoints(frame)
    chrome.TitleText:SetText("Death Contracts")
    frame.chrome = chrome
    local ok2, inset = pcall(CreateFrame, "Frame", nil, chrome, "InsetFrameTemplate")
    if ok2 and inset then
        inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -HEADER_H)
        inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, BOTTOM_H)
        frame.inset = inset
    end
end

-- The spirit's own face in the round portrait: the gossip unit while it lasts, else the
-- target (a right-click targets the spirit); a stock icon when neither is a creature.
local function SetPortrait()
    local chrome = frame and frame.chrome
    if not chrome or not chrome.portrait then return end
    for _, unit in ipairs({ "npc", "target" }) do
        if UnitExists(unit) and not UnitIsPlayer(unit) then
            SetPortraitTexture(chrome.portrait, unit)
            return
        end
    end
    SetPortraitToTexture(chrome.portrait, "Interface\\Icons\\Spell_Holy_Resurrection")
end

local function CreateContractsFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "EbonholdContractsFrame", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(90)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    CreateChrome()

    -- same place as the button of ezCollectionsPortraitFrameTemplate
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 4, 5)

    -- the header strip: the run and what it is worth offered now. The bonus and the contract
    -- counts are not repeated here, the run frame's bar already shows them (his call, 2026-09-30).
    local run = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    run:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -28)
    run:SetJustifyH("RIGHT")
    frame.run = run

    local total = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    total:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -46)
    total:SetJustifyH("RIGHT")
    frame.total = total

    -- the list: a scroll frame inside the inset, the rows on its child
    local scroll = CreateFrame("ScrollFrame", "EbonholdContractsScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(HEADER_H + 4))
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, BOTTOM_H + 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(FRAME_W - 40, 1)
    scroll:SetScrollChild(child)
    frame.scroll, frame.child = scroll, child
    local bar = _G["EbonholdContractsScrollScrollBar"]
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -16)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 16)
    end

    -- the placeholder of an empty list: nothing taken, nothing done, nothing offered (levels 1-2,
    -- where no content sits above the character yet, ContentCatalogueMgr::GetContentsFor)
    local empty = CreateFrame("Frame", nil, frame)
    empty:SetAllPoints(scroll)
    local emptyTitle = empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    emptyTitle:SetPoint("BOTTOM", empty, "CENTER", 0, 6)
    emptyTitle:SetText("No contract for you yet")
    local emptyHint = empty:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyHint:SetPoint("TOP", empty, "CENTER", 0, -6)
    emptyHint:SetWidth(FRAME_W - 120)
    emptyHint:SetTextColor(0.75, 0.75, 0.75)
    emptyHint:SetText("The spirit offers contracts on zones and dungeons a few levels above yours. Gain a level or two and come back.")
    empty:Hide()
    frame.empty = empty
    frame.emptyTitle = emptyTitle
    frame.emptyHint = emptyHint

    -- the button bar: offerings left on the left, the spirit's two services on the right
    local info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 18)
    info:SetJustifyH("LEFT")
    info:SetTextColor(0.75, 0.75, 0.75)
    frame.info = info

    -- placed as the talent window's Apply / Cancel: against the right edge, 8 from the bottom
    local offer = RedButton(frame, "Offer your soul", function() CT.Bank() end, 170, 33)
    offer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 8)
    frame.offer = offer

    local anchor = RedButton(frame, "Anchor your soul", function() CT.Anchor() end, 170, 33)
    anchor:SetPoint("RIGHT", offer, "LEFT", -10, 0)
    anchor:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Soul anchor", 1, 0.82, 0)
        if CT.anchorState == 1 then
            GameTooltip:AddLine("Your soul is anchored to this spirit. Releasing it is free.", 1, 1, 1, true)
        elseif CT.anchorState == 2 and CT.anchorPlace ~= "" then
            GameTooltip:AddLine("Your soul is anchored to " .. CT.anchorPlace .. ". Move it here for the run's Soul Ashes.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Pay the run's Soul Ashes and death sends you back to this spirit, wherever you die.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.anchor = anchor

    -- explicit levels as in the talent window: frame (N), inset (N+1), the rest (N+2)
    local base = frame:GetFrameLevel()
    if frame.chrome then frame.chrome:SetFrameLevel(base) end
    if frame.inset then frame.inset:SetFrameLevel(base + 1) end
    for _, c in ipairs({ frame:GetChildren() }) do
        if c ~= frame.chrome then c:SetFrameLevel(math.max(c:GetFrameLevel(), base + 2)) end
    end

    tinsert(UISpecialFrames, "EbonholdContractsFrame")
    frame:Hide()
    return frame
end

-- The row's bar: the kills done while the contract waits for its first kill, then, once it
-- runs, the hourglass: the time left draining from the right, sand then red, the time beside it.
function CT.RefreshCardBar(card, c)
    if CT.IsRunning(c) then
        local tc = CT.TimeColor(c)
        local d = c.duration or 0
        card.prog:SetStatusBarColor(tc[1], tc[2], tc[3])
        card.prog:SetValue(d > 0 and (CT.TimeLeft(c) / d) or 0)
        card.prog:Show()
        card.timeLeft:SetText(CT.FormatTime(CT.TimeLeft(c)))
        card.timeLeft:SetTextColor(tc[1], tc[2], tc[3])
        card.glass:SetVertexColor(tc[1], tc[2], tc[3])
        card.glass:Show()
        card.timeLeft:Show()
        return
    end
    -- taken, not started: the glass is already there, full, in grey, with the whole time
    if c.state == 1 and CT.HasHourglass(c) then
        card.glass:SetVertexColor(0.7, 0.7, 0.7)
        card.timeLeft:SetText(CT.FormatTime(c.duration))
        card.timeLeft:SetTextColor(0.7, 0.7, 0.7)
        card.glass:Show()
        card.timeLeft:Show()
    else
        card.glass:Hide()
        card.timeLeft:Hide()
    end
    if c.state == 1 and c.kind == 1 then
        card.prog:SetStatusBarColor(C_BONUS[1], C_BONUS[2], C_BONUS[3])
        card.prog:SetValue(c.required > 0 and (c.progress / c.required) or 0)
        card.prog:Show()
    else
        card.prog:Hide()
    end
end

function CT.Refresh()
    if not frame then return end
    local list = Sorted()
    local rowW = frame.child:GetWidth()
    local y = 0
    for i, c in ipairs(list) do
        local card = cards[i]
        if not card then
            card = CreateCard(frame.child, i)
            cards[i] = card
        end
        local h = c.state == 1 and ROW_H_TAKEN or ROW_H
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", frame.child, "TOPLEFT", 0, -y)
        card:SetWidth(rowW)
        card:SetHeight(h)
        y = y + h + ROW_GAP
        card.data = c
        local done = c.state == 2
        card.icon:SetTexture(CT.IconFor(c))
        card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        card.icon:SetDesaturated(done)
        card.icon:SetAlpha(done and 0.6 or 1)
        -- "[18-34] Ashenvale", the time it gives on the right
        card.title:SetText(CT.Heading(c))
        -- the time it gives, behind its hourglass; nothing for a raid (no hourglass)
        card.duration:SetText((done or not CT.HasHourglass(c)) and "" or ("|T" .. HOURGLASS .. ":18:18:0:0|t " .. CT.DurationText(c)))
        card.desc:SetText(CT.Describe(c))
        card.bonus:SetText("+" .. c.bonus .. "%")
        if done then
            card.title:SetTextColor(0.5, 0.5, 0.5)
            card.desc:SetTextColor(0.5, 0.5, 0.5)
            card.bonus:SetTextColor(0.5, 0.5, 0.5)
        else
            card.title:SetTextColor(1, 0.82, 0)
            card.desc:SetTextColor(1, 1, 1)
            card.bonus:SetTextColor(unpack(C_BONUS))
        end
        card.state:SetText(c.state == 1 and (c.kind == 1 and (c.progress .. " / " .. c.required) or "in progress") or "")
        Shown(card.stripe, c.state ~= 1 and i % 2 == 0)
        Shown(card.wash, c.state == 1)
        Shown(card.check, done)
        Shown(card.btnRed, c.state == 1)
        card.hover:Hide()
        CT.RefreshCardBar(card, c)
        card:Show()
    end
    for i = #list + 1, #cards do
        cards[i].data = nil
        cards[i]:Hide()
    end
    frame.child:SetHeight(math.max(1, y - ROW_GAP))
    Shown(frame.empty, #list == 0)
    if #list == 0 then
        if CT.FulfilledCount() > 0 then
            frame.emptyTitle:SetText("Every contract fulfilled")
            frame.emptyHint:SetText("You fulfilled every contract the spirit offers you on this run. Gain a level and new ones come.")
        else
            frame.emptyTitle:SetText("No contract for you yet")
            frame.emptyHint:SetText("The spirit offers contracts on zones and dungeons a few levels above yours. Gain a level or two and come back.")
        end
    end

    local mult = 1 + (CT.gauge or 0) / 100
    local ashes = math.floor(CT.ashes * mult + 0.5)
    local shards = math.floor(CT.shards * mult + 0.5)
    -- the icons say what the numbers are: ashes, then shards
    frame.run:SetText(ASH_ICON .. " " .. fmtNumber(CT.ashes) .. "   " .. SHARD_ICON .. " " .. fmtNumber(CT.shards))
    frame.total:SetText("offered now  " .. ASH_ICON .. " " .. fmtNumber(ashes) .. "   " .. SHARD_ICON .. " " .. fmtNumber(shards))
    local left = math.max(0, (CT.max or 0) - (CT.used or 0))
    frame.info:SetText(left .. " of " .. (CT.max or 0) .. " offerings left")
    -- the price rides in the button, the way a trainer or a vendor shows one
    frame.offer:SetText("Offer your soul  " .. fmtMoney(CT.price))
    frame.offer:SetUsable(left > 0 and (CT.ashes > 0 or CT.shards > 0))
    CT.RefreshAnchor()
end

-- The soul anchor: the button says what clicking does, its tooltip where death sends you
-- back. Anchoring is paid in the run's Soul Ashes; releasing is free.
function CT.RefreshAnchor()
    if not frame or not frame.anchor then return end
    local price = "|TInterface\\Icons\\inv_soulash:12:12:0:0|t " .. fmtNumber(CT.anchorPrice or 0)
    if CT.anchorState == 1 then
        frame.anchor:SetText("Release your soul")
        frame.anchor:SetUsable(true)
    else
        frame.anchor:SetText((CT.anchorState == 2 and "Move your anchor  " or "Anchor your soul  ") .. price)
        frame.anchor:SetUsable((CT.ashes or 0) >= (CT.anchorPrice or 0))
    end
end

-- The tutorial: a guided tour of the window the first time it opens (modules/guidedTour,
-- once per account). Each step lights one part of the window. dbKey "2": rewritten on
-- 2026-09-30 with the new window, so every account sees the new tour once.
local tour
local function ContractsTour()
    if tour or not (ProjectEbonhold.GuidedTour and ProjectEbonhold.GuidedTour.Create) then return tour end
    tour = ProjectEbonhold.GuidedTour.Create({
        parent = function() return frame end,
        dbKey = "seenContractsTour2",
        boxWidth = 300,
        steps = function()
            return {
                {
                    title = "Death contracts",
                    text = "Death pays for risk. Fulfil a contract and your |cffffd700contract bonus|r " ..
                        "rises: the bar on your run frame. That bonus multiplies everything your run " ..
                        "has earned when you offer your soul here.",
                    zone = function() return frame.scroll end,
                    boxAnchor = { "TOPLEFT", "TOPRIGHT", 14, 0 },
                },
                {
                    title = "Two kinds",
                    text = "|cffffd700The Cull|r: kill 50 creatures in a zone. " ..
                        "|cffffd700The Execution|r: kill every boss of a dungeon or a raid. " ..
                        "A contract pays for the time it asks: the longer its hourglass, the bigger its bonus, " ..
                        "and the newest raids pay best. At level 80 the spirit offers them at the highest " ..
                        "Torment you have unlocked: a contract only counts at that Torment or higher, once per run.",
                    zone = function() return cards[1] end,
                    boxAnchor = { "TOPLEFT", "TOPRIGHT", 14, 0 },
                },
                {
                    title = "Take one",
                    text = "Click a row to take it. You hold |cffffd700one at a time|r. " ..
                        "Each one is fulfilled once per run. Your |cffffd700first kill|r " ..
                        "turns its hourglass: each contract shows its time next to its name. " ..
                        "|cffffd700Cancel|r frees the place and puts the contract back on the list.",
                    zone = function() return cards[1] end,
                    boxAnchor = { "TOPLEFT", "TOPRIGHT", 14, 0 },
                },
                {
                    title = "Death keeps its due",
                    text = "If you |cffff4040die|r while holding contracts, they are lost. Fulfilled ones " ..
                        "are safe: their bonus is already in the bar, and it stays until you offer your " ..
                        "soul or accept death.",
                    zone = function() return cards[1] and cards[1].bonus end,
                    boxAnchor = { "TOPLEFT", "TOPRIGHT", 14, 0 },
                },
                {
                    title = "What your run is worth",
                    text = "Top line: the Soul Ashes and Soul Shards your run holds. Below: what they " ..
                        "become on your account if you offer your soul now, with the bonus applied.",
                    zone = function() return frame.run, frame.total end,
                    boxAnchor = { "TOPLEFT", "TOPRIGHT", 14, 0 },
                },
                {
                    title = "Offer your soul",
                    text = "A |cffffd70012 second|r channel toward the spirit, out of combat, without moving. " ..
                        "Your run's Ashes and Shards then go to your account with the bonus, the bonus " ..
                        "starts over, and your run goes on. |cffff4040Accepting death|r banks them " ..
                        "without the bonus.",
                    zone = function() return frame.offer end,
                    boxAnchor = { "TOPLEFT", "TOPRIGHT", 14, 0 },
                },
                {
                    title = "Anchor your soul",
                    text = "Pay the run's |cffffd700Soul Ashes|r and this spirit becomes the place death " ..
                        "sends you back to, wherever you die. It holds until you move it; releasing it is free.",
                    zone = function() return frame.anchor end,
                    boxAnchor = { "TOPLEFT", "TOPRIGHT", 14, 0 },
                },
                {
                    title = "Five a week",
                    text = "Five offerings a week; Skill Tree nodes add more. The first of the week costs " ..
                        "5 silver, the next ones 5 gold. Offerings and contracts come back on the weekly reset.",
                    zone = function() return frame.info end,
                    boxAnchor = { "BOTTOMLEFT", "TOPRIGHT", 14, 0 },
                },
            }
        end,
    })
    return tour
end

function CT.Open()
    CreateContractsFrame()
    CT.Refresh()
    SetPortrait()
    frame:Show()
    local t = ContractsTour()
    if t then C_Timer.After(0.3, function() if frame:IsShown() then t:MaybeStart() end end) end
end

function CT.Tutorial()
    CT.Open()
    local t = ContractsTour()
    if t then t:Start() end
end

function CT.OnData(body)
    parse(body)
    if CT.open or (frame and frame:IsShown()) then
        CT.Open()
    end
    if ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateBracket then
        ProjectEbonhold.PlayerRunUI.UpdateBracket()
    end
end

-- The hourglass ticks on the client: the window's bars and the run frame's bar move every
-- quarter second while a contract runs; one warning at a minute left; at zero the addon asks
-- for a fresh push and the server takes the contract back.
local ticker = CreateFrame("Frame")
local tickAcc = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    tickAcc = tickAcc + elapsed
    if tickAcc < 0.25 then return end
    tickAcc = 0
    local any = false
    for _, c in ipairs(CT.list) do
        if CT.IsRunning(c) then
            any = true
            local left = CT.TimeLeft(c)
            if left <= 60 and left > 0 and not c.warned then
                c.warned = true
                if RaidNotice_AddMessage and RaidWarningFrame then
                    RaidNotice_AddMessage(RaidWarningFrame, "|T" .. HOURGLASS .. ":26:26:0:0|t One minute left: " .. CT.Heading(c), ChatTypeInfo["RAID_WARNING"])
                end
                PlaySound("RaidWarning")
            end
            if left <= 0 and not c.expiredAsked then
                c.expiredAsked = true
                CT.Request()
            end
        end
    end
    if not any then return end
    if frame and frame:IsShown() then
        for _, card in ipairs(cards) do
            if card:IsShown() and card.data then CT.RefreshCardBar(card, card.data) end
        end
    end
    if ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateBracket then
        ProjectEbonhold.PlayerRunUI.UpdateBracket()
    end
end)

local loginWatcher = CreateFrame("Frame")
loginWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
loginWatcher:SetScript("OnEvent", function() CT.Request() end)

function CT.Request()
    if ProjectEbonhold.sendToServer and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_CONTRACTS then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_CONTRACTS, "")
    end
end

-- ------------------------------------------------------------------ confirmations
-- Taking and cancelling both ask first: the popup says what the contract costs and what it pays.

StaticPopupDialogs["EBONHOLD_CONTRACT_TAKE"] = {
    text = "%s",
    button1 = "Take it",
    button2 = "Not now",
    OnAccept = function(self, key) CT.Act(key, "accept") end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["EBONHOLD_CONTRACT_CANCEL"] = {
    text = "%s",
    button1 = "Cancel it",
    button2 = "Keep it",
    OnAccept = function(self, key) CT.Act(key, "abandon") end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Short on purpose (owner, 2026-10-17): the contract and what it pays, no explanation of the feature.
function CT.ConfirmTake(c)
    local time = CT.HasHourglass(c) and ("   |T" .. HOURGLASS .. ":16:16:0:0|t " .. CT.DurationText(c) ..
        "\n|cffa0a0a0The timer starts at your first kill.|r") or ""
    local text = "|cffffd700Take this contract?|r\n\n" .. CT.Heading(c) .. "\n" .. CT.Describe(c) .. "\n\n" ..
        "|cffffd100+" .. c.bonus .. "%|r" .. time
    local dialog = StaticPopup_Show("EBONHOLD_CONTRACT_TAKE", text)
    if dialog then dialog.data = c.key end
end

function CT.ConfirmCancel(c)
    local progress = (c.kind == 1 and c.progress > 0) and ("Your progress (" .. c.progress .. " / " .. c.required .. ") is lost. ") or ""
    local text = "|cffffd700Cancel this contract?|r\n\n" .. CT.Heading(c) .. "\n" .. CT.Describe(c) ..
        (progress ~= "" and ("\n\n" .. progress) or "")
    local dialog = StaticPopup_Show("EBONHOLD_CONTRACT_CANCEL", text)
    if dialog then dialog.data = c.key end
end

function CT.Act(key, action)
    if ProjectEbonhold.sendToServer and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_CONTRACT_ACTION then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_CONTRACT_ACTION, key .. "," .. action)
    end
end

function CT.Bank()
    if ProjectEbonhold.sendToServer and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_SOUL_BANK then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SOUL_BANK, "")
    end
    if frame then frame:Hide() end
end

-- Anchor the soul to the Spirit Healer in front of us, or release it (free). The window stays
-- open: the server answers with a fresh push.
function CT.Anchor(clear)
    if ProjectEbonhold.sendToServer and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_SOUL_ANCHOR then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SOUL_ANCHOR, CT.anchorState == 1 and "clear" or "")
    end
end

-- Lines for the run frame's bar tooltip: { text, r, g, b [, right] }.
function CT.Lines()
    local lines = {}
    for _, c in ipairs(Sorted()) do
        if c.state ~= 0 then
            local mark = c.state == 2 and "|cff80d6a0" or "|cffe6e1d3"
            local right = c.state == 2 and "|cff80d6a0done|r" or (c.kind == 1 and (c.progress .. " / " .. c.required) or "taken")
            if CT.IsRunning(c) then
                local tc = CT.TimeColor(c)
                right = right .. string.format("  |cff%02x%02x%02x%s|r", tc[1] * 255, tc[2] * 255, tc[3] * 255, CT.FormatTime(CT.TimeLeft(c)))
            end
            if c.state == 1 and CT.Outgrown(c) then right = "|cffe23b3bpast level " .. c.levelMax .. "|r" end
            table.insert(lines, { mark .. CT.Describe(c) .. "|r", 1, 1, 1, "|cffffd100+" .. c.bonus .. "%|r  " .. right })
        end
    end
    if #lines == 0 then
        table.insert(lines, { "None yet. Talk to a Spirit Healer at any graveyard to take one.", 0.6, 0.6, 0.6 })
    end
    return lines
end

SLASH_EBONHOLDCONTRACTS1 = "/contracts"
SlashCmdList["EBONHOLDCONTRACTS"] = function(msg)
    if msg and msg:match("^%s*tut") then CT.Tutorial() return end
    DEFAULT_CHAT_FRAME:AddMessage("|cff9fd6ffDeath contracts|r  bonus +" .. math.floor((CT.gauge or 0) + 0.5) .. "%")
    for _, l in ipairs(CT.Lines()) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. l[1] .. (l[5] and ("  " .. l[5]) or ""), l[2], l[3], l[4])
    end
    CT.Request()
end

if ProjectEbonhold.onEventReceived and ProjectEbonhold.SS and ProjectEbonhold.SS.SEND_CONTRACTS then
    ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_CONTRACTS, CT.OnData)
end
