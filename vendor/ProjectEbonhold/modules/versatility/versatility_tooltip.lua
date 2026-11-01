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

-- Returns the rewritten text, or nil when nothing changed.
local function ToNewStats(text)
  if not text then return nil end
  local original = text
  local hasDefense = text:find("efense [Rr]ating")
  local hasResilience = text:find("esilience")
  if not hasDefense and not hasResilience then return nil end
  if hasDefense then
    text = text:gsub("Defense Rating", "Versatility")
               :gsub("Defense rating", "Versatility")
               :gsub("defense rating", "versatility")
  end
  if hasResilience then
    text = text:gsub("Resilience Rating", "Mastery")
               :gsub("Resilience rating", "Mastery")
               :gsub("resilience rating", "mastery")
               :gsub("(%+%d+ )Resilience%f[%A]", "%1Mastery")
  end
  if text == original then return nil end
  return text
end

-- GlobalStrings: rewrite in place so the format specifiers (%d, %s) are kept as they are.
for _, key in ipairs({ "ITEM_MOD_DEFENSE_SKILL_RATING", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
                       "COMBAT_RATING_NAME2",
                       "ITEM_MOD_RESILIENCE_RATING", "ITEM_MOD_RESILIENCE_RATING_SHORT" }) do
  local rewritten = ToNewStats(_G[key])
  if rewritten then _G[key] = rewritten end
end
-- COMBAT_RATING_NAME15..17 are the three CR_CRIT_TAKEN_* ratings; their name is the bare
-- word "Resilience", which the item-line rule above leaves alone, so it is swapped whole.
for _, key in ipairs({ "COMBAT_RATING_NAME15", "COMBAT_RATING_NAME16", "COMBAT_RATING_NAME17" }) do
  local value = _G[key]
  if type(value) == "string" then
    _G[key] = ToNewStats(value) or (value == "Resilience" and "Mastery") or value
  end
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
