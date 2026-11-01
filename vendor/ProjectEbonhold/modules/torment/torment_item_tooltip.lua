-- Torment item label -- the green line under the name.
--
-- Every Torment copy of an item (entry + 1 000 000 x bracket, tools/items/emit_sql.py) carries
-- ITEM_FLAG_HEROIC_TOOLTIP, which makes the client print a green "Heroic" line right under
-- the item name, and its description starts with the bracket mention between two '@':
--   "@Torment I, Torment II, Torment III@<original description>"
-- The client has no other hook for a coloured line under the name, so this file rides the
-- Heroic one: the "Heroic" text becomes the mention, and the mention is cut out of the
-- description (a description that was only the marker disappears entirely).
--
-- Real heroic items (no marker in their description) are left alone.

local MARKER_PATTERN = "^(\"?)@([^@]+)@(.-)(\"?)$"   -- the description line is quoted by the client

local function RelabelTormentItem(tooltip)
  local name = tooltip:GetName()
  if not name then return end
  local label, descLine = nil, nil
  for i = 2, tooltip:NumLines() do
    local left = _G[name .. "TextLeft" .. i]
    local text = left and left:GetText()
    if text then
      local q1, inner, rest, q2 = text:match(MARKER_PATTERN)
      if inner then
        label, descLine = inner, left
        rest = rest:gsub("^%s+", "")
        if rest == "" then
          -- Nothing but the marker: drop the line. Blanking keeps the line count stable
          -- for the other tooltip hooks; the empty line is collapsed at the next Show.
          left:SetText("")
          left:Hide()
        else
          left:SetText(q1 .. rest .. q2)
        end
        break
      end
    end
  end
  if not label then return end

  -- The Heroic line is always the second line (right under the name); scan a few in case a
  -- bag addon inserted one above it.
  for i = 2, math.min(tooltip:NumLines(), 4) do
    local left = _G[name .. "TextLeft" .. i]
    if left and left:GetText() == ITEM_HEROIC then
      left:SetText(label)
      left:SetTextColor(0.1, 1, 0.1)
      break
    end
  end
  tooltip:Show()   -- re-lay out after the edits so the dropped line leaves no gap
end

local function Hook(frame)
  if frame and frame.HookScript then
    frame:HookScript("OnTooltipSetItem", RelabelTormentItem)
  end
end

Hook(GameTooltip)
Hook(ItemRefTooltip)
for _, n in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3",
                     "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
  Hook(_G[n])
end
