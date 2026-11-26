-- Ashendor: addon.LO, the second string table core\editor_settings.lua reads (it was set by the
-- removed options panel's core.lua).
local addon = DragonUI
local activeLocale = addon.GetActiveLocale and addon.GetActiveLocale()
addon.LO = LibStub("AceLocale-3.0-DragonUI"):GetLocale("DragonUI_Options", activeLocale)
