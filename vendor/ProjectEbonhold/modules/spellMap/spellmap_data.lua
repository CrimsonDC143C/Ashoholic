ProjectEbonhold = ProjectEbonhold or {}

-- Ashendor SpellMap rule table: mirrors the server's `spellmap_rules` DB table
-- (base_spell_id, trigger_spell_id, override_spell_id). Shipped through the addon (and
-- therefore through the normal patch-4.MPQ delivery pipeline) so a rule change ships like
-- any other content patch -- no ebonhold.dll rebuild needed.
--
-- Read once by ebonhold.dll (spellmap_client.h) as soon as this table is available, via
-- EbonholdSpellMapBeginRuleLoad()/EbonholdSpellMapAddRule(base, trigger, override). The DLL
-- keeps a small built-in default as a fallback for as long as this table isn't loaded yet.
ProjectEbonhold.SpellMapRules = { };
