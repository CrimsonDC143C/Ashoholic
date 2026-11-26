-- Defense Rating is Versatility -- tooltip text.
--
-- The server turned the Defense Rating combat rating (CR_DEFENSE_SKILL) into Versatility:
-- +V% damage and healing done, -V/2 % damage taken. The client still prints the old name,
-- from two sources:
--   * GlobalStrings (item green stat lines: "Increases defense rating by %d.",
--     "+%d Defense Rating", the combat rating name) -- rewritten once, at load;
--   * DBC text (enchant and gem names, socket bonuses, equip spell descriptions) -- rewritten
--     on every item / spell tooltip, line by line.
-- Only the words change: the line colour and any "@...@" marker other hooks look for
-- (torment_item_tooltip.lua, extraction.lua) are left untouched, so hook order does not matter.

--
-- Same for Resilience, which the server reads as Mastery (the stat of echoes): "Resilience
-- Rating" / "resilience rating" and the stand-alone stat word of "+20 Resilience" become
-- Mastery; any other "Resilience" (a spell or item name) is left alone.

--
-- Other client languages (2026-11-13): a French / German / Spanish client prints its own words
-- ("score de défense", "Abhärtungswertung", "índice de temple"), which the English rules never
-- matched, so those players saw Defense and Resilience everywhere. The client's own words get
-- their own pairs below; the English pairs run on every client, since custom DBC text can be
-- English whatever the language. Plain find + gsub pairs: { find, pattern, replacement }.

local L = ProjectEbonhold.L

local ENGLISH = {
  { "efense Rating",    "Defense Rating",    "Versatility" },
  { "efense rating",    "Defense rating",    "Versatility" },
  { "efense rating",    "defense rating",    "versatility" },
  { "esilience Rating", "Resilience Rating", "Mastery" },
  { "esilience rating", "Resilience rating", "Mastery" },
  { "esilience rating", "resilience rating", "mastery" },
  { "Resilience",       "(%+%d+ )Resilience%f[%A]", "%1Mastery" },
}

local NATIVE = {
  frFR = {
    { "core de défense",    "score de défense",    "score de polyvalence" },
    { "core de défense",    "Score de défense",    "Score de polyvalence" },
    { "core de résilience", "score de résilience", "score de maîtrise" },
    { "core de résilience", "Score de résilience", "Score de maîtrise" },
    { "ésilience",          "(%+%d+ )[Rr]ésilience", "%1maîtrise" },
    { "ésilience",          "(%+%d+ à la )résilience", "%1maîtrise" },
    { "ésilience",          "(%+%d+ en )résilience", "%1maîtrise" },
  },
  deDE = {
    { "Verteidigungswertung", "Verteidigungswertung", "Vielseitigkeitswertung" },
    { "Abhärtungswertung",    "Abhärtungswertung",    "Meisterschaftswertung" },
    { "Abhärtung",            "(%+%d+ )Abhärtung",    "%1Meisterschaft" },
  },
  esES = {
    { "ndice de defensa", "índice de defensa", "índice de versatilidad" },
    { "ndice de defensa", "Índice de defensa", "Índice de versatilidad" },
    { "ndice de temple",  "índice de temple",  "índice de maestría" },
    { "ndice de temple",  "Índice de temple",  "Índice de maestría" },
    { "emple",            "(%+%d+ )[Tt]emple", "%1maestría" },
    { "emple",            "(%+%d+ de )temple", "%1maestría" },
  },
}
NATIVE.esMX = NATIVE.esES

local RULES = {}
for _, rule in ipairs(NATIVE[GetLocale()] or {}) do table.insert(RULES, rule) end
for _, rule in ipairs(ENGLISH) do table.insert(RULES, rule) end

-- Returns the rewritten text, or nil when nothing changed.
local function ToNewStats(text)
  if not text then return nil end
  local original = text
  for _, rule in ipairs(RULES) do
    if text:find(rule[1], 1, true) then
      text = text:gsub(rule[2], rule[3])
    end
  end
  if text == original then return nil end
  return text
end

-- GlobalStrings: rewrite in place so the format specifiers (%d, %s) are kept as they are.
for _, key in ipairs({ "ITEM_MOD_DEFENSE_SKILL_RATING", "ITEM_MOD_RESILIENCE_RATING" }) do
  local rewritten = ToNewStats(_G[key])
  if rewritten then _G[key] = rewritten end
end
-- The bare stat names (the short item-mod names, the combat rating names: COMBAT_RATING_NAME2 =
-- CR_DEFENSE_SKILL, 15..17 = the three CR_CRIT_TAKEN_* resilience ratings) are swapped whole for
-- the add-on's own translated name, so they follow the client's language without a word list.
for key, name in pairs({
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = L["Versatility"],
  COMBAT_RATING_NAME2                 = L["Versatility"],
  ITEM_MOD_RESILIENCE_RATING_SHORT    = L["Mastery"],
  COMBAT_RATING_NAME15                = L["Mastery"],
  COMBAT_RATING_NAME16                = L["Mastery"],
  COMBAT_RATING_NAME17                = L["Mastery"],
}) do
  if type(_G[key]) == "string" then _G[key] = name end
end

local function RewriteTooltip(tooltip)
  local name = tooltip:GetName()
  if not name then return end
  local changed = false
  for i = 1, tooltip:NumLines() do
    for _, side in ipairs({ "TextLeft", "TextRight" }) do
      local line = _G[name .. side .. i]
      local rewritten = line and ToNewStats(line:GetText())
      if rewritten then
        line:SetText(rewritten)   -- SetText keeps the line's colour
        changed = true
      end
    end
  end
  if changed then tooltip:Show() end   -- re-lay out: the lines got shorter
end

local function Hook(frame, script)
  if frame and frame.HookScript then
    frame:HookScript(script, RewriteTooltip)
  end
end

for _, n in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                     "ShoppingTooltip3", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
  Hook(_G[n], "OnTooltipSetItem")
end
Hook(GameTooltip, "OnTooltipSetSpell")
Hook(ItemRefTooltip, "OnTooltipSetSpell")
