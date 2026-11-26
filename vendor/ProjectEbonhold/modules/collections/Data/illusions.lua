--[[----------------------------------------------------------------------------
    Weapon illusion (enchant visual) catalog.

    Enchant ids + names verified against THIS client's SpellItemEnchantment.dbc
    (only entries with ItemVisual ~= 0, i.e. a real on-weapon glow).

    carrier: a stock item id (verified present in Item.dbc) whose only jobs are
    to give each illusion a unique id in ITEM space -- the wardrobe grid runs
    GetItemInfo(visualID) as its "data ready" check and needs distinct ids for
    cell re-dressing -- and to be safely queryable from the server. The player
    NEVER sees the carrier item: illusion cells render the equipped weapon
    with the enchant applied, names/icons come from this catalog.

    Consumed by core/transmog_backing.lua (GetIllusions & co) and the
    wardrobe's TryOn preview path (GetEnchantFromScroll).
------------------------------------------------------------------------------]]
local L = ProjectEbonhold.L

local ez = _G.ezCollections
if not ez then return end

local ICONS = "Interface\\Icons\\"

local ILLUSIONS = {
    { enchant = 1900, name = L["Crusader"],        carrier = 117,  icon = ICONS .. "Spell_Holy_GreaterHeal" },
    { enchant = 803,  name = L["Fiery Weapon"],    carrier = 159,  icon = ICONS .. "Spell_Fire_FlameBlades" },
    { enchant = 1894, name = L["Icy Chill"],       carrier = 414,  icon = ICONS .. "Spell_Frost_IceStorm" },
    { enchant = 1898, name = L["Lifestealing"],    carrier = 422,  icon = ICONS .. "Spell_Shadow_LifeDrain" },
    { enchant = 1899, name = L["Unholy Weapon"],   carrier = 787,  icon = ICONS .. "Spell_Shadow_UnholyFrenzy" },
    { enchant = 1103, name = L["Agility"],         carrier = 858,  icon = ICONS .. "Spell_Holy_BlessingOfAgility" },
    { enchant = 2343, name = L["Major Spellpower"], carrier = 929, icon = ICONS .. "Spell_Holy_MagicalSentry" },
    { enchant = 2671, name = L["Sunfire"],         carrier = 1179, icon = ICONS .. "Spell_Fire_SealOfFire" },
    { enchant = 2672, name = L["Soulfrost"],       carrier = 1205, icon = ICONS .. "Spell_Frost_WizardMark" },
    { enchant = 2673, name = L["Mongoose"],        carrier = 1645, icon = ICONS .. "Ability_Hunter_SwiftStrike" },
    { enchant = 2674, name = L["Spellsurge"],      carrier = 1708, icon = ICONS .. "Spell_Arcane_ArcaneTorrent" },
    { enchant = 2675, name = L["Battlemaster"],    carrier = 1710, icon = ICONS .. "Ability_Warrior_BattleShout" },
    { enchant = 3225, name = L["Executioner"],     carrier = 2287, icon = ICONS .. "Ability_Rogue_Ambush" },
    { enchant = 3239, name = L["Icebreaker"],      carrier = 2596, icon = ICONS .. "Spell_Frost_FrostShock" },
    { enchant = 3241, name = L["Lifeward"],        carrier = 3770, icon = ICONS .. "Spell_Holy_SealOfSacrifice" },
    { enchant = 3273, name = L["Deathfrost"],      carrier = 3771, icon = ICONS .. "Spell_Frost_ChillingBlast" },
    { enchant = 3789, name = L["Berserking"],      carrier = 4536, icon = ICONS .. "Spell_Nature_AncestralGuardian" },
    { enchant = 3790, name = L["Black Magic"],     carrier = 4540, icon = ICONS .. "Spell_Shadow_ShadowBolt" },
    { enchant = 3869, name = L["Blade Ward"],      carrier = 4599, icon = ICONS .. "Ability_Parry" },
    { enchant = 3870, name = L["Blood Draining"],  carrier = 4602, icon = ICONS .. "Spell_Shadow_LifeDrain02" },
}

local byCarrier, byEnchant = {}, {}
for _, ill in ipairs(ILLUSIONS) do
    byCarrier[ill.carrier] = ill
    byEnchant[ill.enchant] = ill
end

ez.IllusionCatalog  = ILLUSIONS
ez.IllusionByCarrier = byCarrier
ez.IllusionByEnchant = byEnchant

-- carrier ("scroll") item -> enchant id. This is the seam the wardrobe's
-- model preview already calls for its TryOn("item:X:enchant") links.
function ez:GetEnchantFromScroll(itemID)
    local ill = byCarrier[itemID]
    return ill and ill.enchant or nil
end

-- enchant id -> carrier, for turning server-applied state back into UI ids.
function ez:GetScrollFromEnchant(enchantID)
    local ill = byEnchant[enchantID]
    return ill and ill.carrier or nil
end
