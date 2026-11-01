-- Resilience is Mastery -- character sheet.
--
-- The "Resilience" row of the Defenses stat category (PaperDollFrame_SetResilience, 3.3.5
-- FrameXML). The server now reads the Resilience rating as Mastery, the stat of echoes:
-- +M% to everything the player's echoes do. Same formula as the server, from the spell
-- crit-taken rating (resilience items fill the three CR_CRIT_TAKEN_* ratings equally):
--   M = 25 * R / (R + 1060) %

if type(PaperDollFrame_SetResilience) ~= "function" then return end

local function MasteryPct(rating)
  if rating <= 0 then return 0 end
  return 25 * rating / (rating + 1060)
end

hooksecurefunc("PaperDollFrame_SetResilience", function(statFrame, unit)
  if not statFrame or not statFrame.GetName then return end
  local frameName = statFrame:GetName()
  local label = _G[frameName .. "Label"]
  local text = _G[frameName .. "StatText"]
  local rating = GetCombatRating(CR_CRIT_TAKEN_SPELL or 17) or 0

  if label then label:SetText(format(STAT_FORMAT or "%s:", "Mastery")) end
  if text then text:SetText(HIGHLIGHT_FONT_COLOR_CODE .. rating .. FONT_COLOR_CODE_CLOSE) end
  statFrame.tooltip = HIGHLIGHT_FONT_COLOR_CODE .. "Mastery " .. rating .. FONT_COLOR_CODE_CLOSE
  statFrame.tooltip2 = format("Mastery rating %d: +%.2f%% to the power of your echoes (damage, healing, absorbs and their passive effects).",
                              rating, MasteryPct(rating))
end)
