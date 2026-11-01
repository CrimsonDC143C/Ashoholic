-- Defense Rating is Versatility -- character sheet.
--
-- The "Defense" row of the Defenses stat category (PaperDollFrame_SetDefense, 3.3.5 FrameXML)
-- shows the defense skill. The server now reads the Defense Rating as Versatility, so the row
-- becomes "Versatility: <rating>", with the effect in its tooltip. Same formula as the server:
--   V = 20 * R / (R + 1060) %   ->   +V% damage and healing done, -V/2 % damage taken.

if type(PaperDollFrame_SetDefense) ~= "function" then return end

local function VersatilityPct(rating)
  if rating <= 0 then return 0 end
  return 20 * rating / (rating + 1060)
end

hooksecurefunc("PaperDollFrame_SetDefense", function(statFrame, unit)
  if not statFrame or not statFrame.GetName then return end
  local frameName = statFrame:GetName()
  local label = _G[frameName .. "Label"]
  local text = _G[frameName .. "StatText"]
  local rating = GetCombatRating(CR_DEFENSE_SKILL or 2) or 0
  local pct = VersatilityPct(rating)

  if label then label:SetText(format(STAT_FORMAT or "%s:", "Versatility")) end
  if text then text:SetText(HIGHLIGHT_FONT_COLOR_CODE .. rating .. FONT_COLOR_CODE_CLOSE) end
  statFrame.tooltip = HIGHLIGHT_FONT_COLOR_CODE .. "Versatility " .. rating .. FONT_COLOR_CODE_CLOSE
  statFrame.tooltip2 = format("Versatility rating %d: +%.2f%% damage and healing done, -%.2f%% damage taken.",
                              rating, pct, pct / 2)
end)
