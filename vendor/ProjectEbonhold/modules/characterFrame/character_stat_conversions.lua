-- Feuille de personnage : les conversions de stat de classe dans l'infobulle, comme retail.
--
-- Sur Ashendor, les talents de conversion sont des sorts de base de la classe (SpellLevelMgr,
-- niveau 1, 2026-09-15) : 30 % de l'Intelligence du mage en puissance des sorts, 100 % de
-- l'Intelligence du chasseur en puissance d'attaque a distance, etc. L'infobulle d'origine ne
-- le dit pas. On ajoute, a la suite de ce que la stat donne deja, une ligne par effet :
-- "Increases Spell Power by 470." - sans detail de provenance, comme retail.
--
-- Valeurs lues dans spells.spell (dev, 2026-11-10 ; toutes reverifiees le 2026-11-19). Le serveur prend la stat totale
-- (Unit::GetStat), on fait pareil avec la valeur effective de UnitStat.
-- Changer une valeur cote serveur = la changer ici aussi.

if type(PaperDollFrame_SetStat) ~= "function" then return end

local L = ProjectEbonhold.L
local STR, AGI, STA, INT, SPI = 1, 2, 3, 4, 5

-- Selon la classe seulement : tout ce qui est ici est un sort de base de la classe. Les
-- procs et buffs de glyphe (Expose Weakness, Life Tap, Shadowy Insight) n'y sont pas.
-- to : sp = puissance des sorts (degats et soins), heal = soins seulement, ap, rap, mp5, armor,
-- moonkin / tree = conversions du druide qui ne jouent que dans cette forme (dit dans la ligne).
local CONVERSIONS = {
    PALADIN = {
        { from = INT, pct = 30, to = "sp" },    -- 31841 Holy Guidance
        { from = STR, pct = 50, to = "sp" },    -- 53592 Touched by the Light
    },
    HUNTER = {
        { from = INT, pct = 100, to = "rap" },  -- 34484 Careful Aim
        { from = STA, pct = 50, to = "ap" },    -- 56341 Hunter vs. Wild
        { from = STA, pct = 50, to = "rap" },
    },
    PRIEST = {
        { from = INT, pct = 30, to = "sp" },    -- 15031 Spiritual Guidance (Intellect since 2026-11-20, like the mage)
        { from = INT, pct = 150, to = "armor" }, -- 54659 Arcane Fortitude (tissu, 2026-11-20)
    },
    SHAMAN = {
        { from = INT, pct = 30, to = "sp" },    -- 30869 Nature's Blessing
        { from = INT, pct = 100, to = "ap" },   -- 51885 Mental Dexterity
        { from = INT, pct = 12, to = "mp5" },   -- 30666 Unrelenting Storm
    },
    MAGE = {
        { from = INT, pct = 30, to = "sp" },    -- 31588 Mind Mastery
        { from = INT, pct = 150, to = "armor" }, -- 54659 Arcane Fortitude (tissu, 2026-11-20)
    },
    WARLOCK = {
        { from = INT, pct = 15, to = "sp" },    -- 92140 Fel Attunement (15 % Int since 2026-11-18)
        { from = INT, pct = 150, to = "armor" }, -- 54659 Arcane Fortitude (tissu, 2026-11-20)
    },
    DRUID = {
        { from = INT, pct = 30, to = "sp" },    -- 33591 Lunar Guidance
        { from = AGI, pct = 50, to = "heal" },  -- 33873 Nurturing Instinct
        { from = INT, pct = 10, to = "mp5" },   -- 33956 Dreamstate
        { from = SPI, pct = 30, to = "moonkin" },   -- 48396 Improved Moonkin Form
        { from = SPI, pct = 30, to = "tree" },      -- 48537 Improved Tree of Life
    },
}

-- 1 PA par 36 d'armure : 61222 Armored to the Teeth (guerrier), 49393 Bladed Armor (DK).
local ARMOR_PER_AP = { WARRIOR = 36, DEATHKNIGHT = 36 }

local LINE_FORMAT = {
    sp      = L["Increases Spell Power by %s."],
    heal    = L["Increases healing done by your spells by %s."],
    ap      = L["Increases Attack Power by %s."],
    rap     = L["Increases Ranged Attack Power by %s."],
    mp5     = L["Increases mana regeneration by %s every 5 seconds."],
    armor   = L["Increases Armor by %s."],
    moonkin = L["Increases spell damage by %s in Moonkin Form."],
    tree    = L["Increases healing done by your spells by %s in Tree of Life Form."],
}

-- La valeur en blanc dans la ligne doree, comme les chiffres des infobulles retail.
local function White(value)
    return (HIGHLIGHT_FONT_COLOR_CODE or "|cffffffff") .. value .. (FONT_COLOR_CODE_CLOSE or "|r")
end
local LINE_ORDER = { "sp", "heal", "ap", "rap", "mp5", "armor", "moonkin", "tree" }

local _, playerClass = UnitClass("player")

local function AppendLines(statFrame, lines)
    if #lines == 0 then return end
    local text = table.concat(lines, "\n")
    if statFrame.tooltip2 and statFrame.tooltip2 ~= "" then
        statFrame.tooltip2 = statFrame.tooltip2 .. "\n" .. text
    else
        statFrame.tooltip2 = text
    end
end

hooksecurefunc("PaperDollFrame_SetStat", function(statFrame, statIndex)
    local list = CONVERSIONS[playerClass]
    if not list or not statFrame then return end
    local _, effective = UnitStat("player", statIndex)
    if not effective or effective <= 0 then return end

    local totals = {}
    for _, c in ipairs(list) do
        if c.from == statIndex then
            totals[c.to] = (totals[c.to] or 0) + effective * c.pct / 100
        end
    end

    local lines = {}
    for _, key in ipairs(LINE_ORDER) do
        local value = totals[key] and math.floor(totals[key])
        if value and value > 0 then
            lines[#lines + 1] = format(LINE_FORMAT[key], White(value))
        end
    end
    AppendLines(statFrame, lines)
end)

if type(PaperDollFrame_SetArmor) == "function" and ARMOR_PER_AP[playerClass] then
    hooksecurefunc("PaperDollFrame_SetArmor", function(statFrame, unit)
        if not statFrame or (unit and unit ~= "player") then return end
        local _, effectiveArmor = UnitArmor("player")
        local ap = effectiveArmor and math.floor(effectiveArmor / ARMOR_PER_AP[playerClass])
        if ap and ap > 0 then
            AppendLines(statFrame, { format(LINE_FORMAT.ap, White(ap)) })
        end
    end)
end
