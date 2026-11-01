ProjectEbonhold = ProjectEbonhold or {}

-- Ashendor SpellMap rule table: mirrors the server's `spellmap_rules` DB table
-- (base_spell_id, trigger_spell_id, override_spell_id). Shipped through the addon (and
-- therefore through the normal patch-4.MPQ delivery pipeline) so a rule change ships like
-- any other content patch -- no ebonhold.dll rebuild needed.
--
-- Read once by ebonhold.dll (spellmap_client.h) as soon as this table is available, via
-- EbonholdSpellMapBeginRuleLoad()/EbonholdSpellMapAddRule(base, trigger, override). The DLL
-- keeps a small built-in default as a fallback for as long as this table isn't loaded yet.
ProjectEbonhold.SpellMapRules = {
    { 20230, 1000048, 1000049 }, -- Retaliation -> Retaliation (Wall of Blades, warrior arms 2)
    { 8122, 1046049, 1046050 }, -- Psychic Scream r1 -> horror (Paralyzing Scream, priest shadow 2)
    { 8124, 1046049, 1046051 }, -- Psychic Scream r2 -> horror (Paralyzing Scream, priest shadow 2)
    { 10888, 1046049, 1046052 }, -- Psychic Scream r3 -> horror (Paralyzing Scream, priest shadow 2)
    { 10890, 1046049, 1046053 }, -- Psychic Scream r4 -> horror (Paralyzing Scream, priest shadow 2)
    { 55198, 1066050, 1066051 }, -- Tidal Force -> Tidal Force (Unbroken Tide, shaman resto 2)
    { 47864, 1080042, 1080043 }, -- Curse of Agony r9 -> front loaded (Cresting Agony, warlock affliction 2)
    { 47820, 1086030, 1086031 }, -- Rain of Fire r7 -> non-channeled Rain of Fire (Hellrain, warlock destruction 2)
    { 48467, 1090036, 1090037 }, -- Hurricane r5 -> walking non-channeled Hurricane (Stormcrown, druid balance 2)
    { 22812, 1096054, 1096055 }, -- Barkskin -> Barkskin cast on an ally (Lend Bark, druid resto 2)
    { 48579, 1093061, 1093062 }, -- Ravage r7 -> usable while not prowling (Fresh Kill, druid feral cat 2)
    { 48707, 1050026, 1050037 }, -- Anti-Magic Shell -> red shell look, same mechanics (Grave Bargain, dk blood 2)
    { 1719, 1003082, 1003083 }, -- Recklessness -> Recklessness without the damage taken penalty (Heedless, warrior fury 3)
    { 12292, 1003082, 1003084 }, -- Death Wish -> Death Wish without the damage taken penalty (Heedless, warrior fury 3)
    { 20252, 1003078, 1003079 }, -- Intercept -> Intercept with no minimum range, 0-25 yd (Point Blank, warrior fury 3)
    { 48806, 1010076, 1010077 }, -- Hammer of Wrath -> also castable on allies below 35% health, heals them (Merciful Hammer, paladin holy 3)
    { 31789, 1013074, 1013075 }, -- Righteous Defense -> also castable on an enemy, taunts it + 2 nearby (Righteous Summons, paladin prot 3)
    { 49050, 1023082, 1023083 }, -- Aimed Shot -> no shared cooldown with Multi-Shot (Split Quiver, hunter mm 3)
    { 61006, 1023068, 1023069 }, -- Kill Shot -> usable below 35% health (Dead Reckoning, hunter mm 3)
    { 58434, 1023078, 1023079 }, -- Volley -> not channeled, 6 sec cooldown (Loosed Sky, hunter mm 3)
    { 63672, 1026066, 1026067 }, -- Black Arrow -> no shared cooldown with traps (Spare Fuse, hunter sv 3)
    { 5938, 1030078, 1030079 }, -- Shiv -> can crit, its poison too (Keen Shiv, rogue assassination 3)
    { 36554, 1036058, 1036059 }, -- Shadowstep -> empowers the next 2 abilities (Twice Over, rogue subtlety 3)
    { 12051, 1070086, 1070087 }, -- Evocation -> non-channeled Evocation (Open Channel, mage arcane 3)
    { 42945, 1073082, 1073083 }, -- Blast Wave -> no knockback, daze kept (Heatwave, mage fire 3)
    { 42950, 1073084, 1073085 }, -- Dragon's Breath -> 10 yd circle around the mage instead of a cone (Dragon's Coil, mage fire 3)
    { 42940, 1076064, 1076065 }, -- Blizzard r9 -> non-channeled Blizzard, 6 sec cooldown (Whiteout, mage frost 3)
    { 50581, 1083084, 1083085 }, -- Shadow Cleave -> all enemies within 8 yd of its target at full Demonic Frenzy (Borrowed Frenzy, warlock demonology 3)
    { 61290, 1086070, 1086071 }, -- Shadowflame -> all enemies within 10 yd around the warlock instead of a cone (Shadowflame Wreath, warlock destruction 3)
    { 47823, 1086072, 1086073 }, -- Hellfire -> no damage to the caster (Hellwalker, warlock destruction 3)
};
