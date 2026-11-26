local L, T = ProjectEbonhold.L, ProjectEbonhold.T
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

  if label then label:SetText(format(STAT_FORMAT or "%s:", L["Versatility"])) end
  if text then text:SetText(HIGHLIGHT_FONT_COLOR_CODE .. rating .. FONT_COLOR_CODE_CLOSE) end
  statFrame.tooltip = T("{HIGHLIGHTFONTCOLORCODE}Versatility {rating}{FONTCOLORCODECLOSE}", { HIGHLIGHTFONTCOLORCODE = HIGHLIGHT_FONT_COLOR_CODE, rating = rating, FONTCOLORCODECLOSE = FONT_COLOR_CODE_CLOSE })
  statFrame.tooltip2 = T("Versatility rating {rating}: +{pct}% damage and healing done, -{pct2}% damage taken.", { rating = string.format("%d", rating), pct = string.format("%.2f", pct), pct2 = string.format("%.2f", pct / 2) })
end)
