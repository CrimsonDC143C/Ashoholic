local addonName = ...
local addon = _G[addonName]

addon.UI = addon.UI or {}
local UI = addon.UI

-- Shared presentation for the live pages. These helpers format supplied
-- snapshots; they never read game state, SavedVariables or the preview.
UI.Style = {
    whiteTexture = "Interface\\Buttons\\WHITE8X8",
    gold = { 1, 0.79, 0.39, 1 },
    teal = { 0.40, 0.86, 0.78, 1 },
    text = { 0.88, 0.88, 0.90, 1 },
    muted = { 0.58, 0.61, 0.67, 1 },
    panel = { 0.075, 0.083, 0.105, 0.99 },
    border = { 0.19, 0.21, 0.26, 1 },
    row = { 0.10, 0.115, 0.145, 1 },
    alternateRow = { 0.12, 0.135, 0.165, 1 },
}
local Style = UI.Style

function UI.SetFontString(fontString, size, color)
    fontString:SetFont("Fonts\\FRIZQT__.TTF", size)
    fontString:SetTextColor(unpack(color))
    fontString:SetJustifyV("MIDDLE")
end

function UI.AddLabel(parent, text, x, y, width, height, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetHeight(height)
    label:SetJustifyH("LEFT")
    UI.SetFontString(label, size, color)
    label:SetText(text or "")
    return label
end

function UI.AddTextButton(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button:SetNormalTexture(Style.whiteTexture)
    button:SetHighlightTexture(Style.whiteTexture, "ADD")
    button:GetNormalTexture():SetVertexColor(unpack(Style.row))
    button:GetHighlightTexture():SetVertexColor(0.10, 0.10, 0.10, 0.3)

    button.text = button:CreateFontString(nil, "OVERLAY")
    button.text:SetPoint("CENTER")
    UI.SetFontString(button.text, 11, Style.text)
    button.text:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

function UI.CreateSurface(parent, width, height)
    local surface = CreateFrame("Frame", nil, parent)
    surface:SetSize(width, height)
    surface:SetBackdrop({
        bgFile = Style.whiteTexture,
        edgeFile = Style.whiteTexture,
        edgeSize = 1,
    })
    surface:SetBackdropColor(unpack(Style.row))
    surface:SetBackdropBorderColor(unpack(Style.border))
    return surface
end

function UI.CreateDetailLine(parent, title, x, y, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", x, y)
    row:SetSize(width, 24)
    local labelWidth = width * 0.49
    row.label = UI.AddLabel(row, title, 0, 0, labelWidth, 24, 11, Style.muted)
    row.value = UI.AddLabel(row, "", labelWidth + 6, 0, width - labelWidth - 6, 24, 11, Style.text)
    row.value:SetJustifyH("RIGHT")
    return row
end

function UI.CreateScroll(parent, name, width)
    local scroll = CreateFrame("ScrollFrame", name, parent)
    scroll:SetSize(width, 1)
    scroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    scroll.content = content
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maximum = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maximum, self:GetVerticalScroll() - delta * 70)))
    end)
    return scroll, content
end

function UI.UpdateScrollHeight(scroll, height)
    local offset = scroll:GetVerticalScroll()
    scroll.content:SetHeight(math.max(1, height))
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(offset, scroll:GetVerticalScrollRange()))
end

function UI.FormatNumber(value)
    if type(value) ~= "number" then
        return "Unknown"
    end
    local text = tostring(math.floor(value))
    local groups = {}
    while #text > 3 do
        table.insert(groups, 1, string.sub(text, -3))
        text = string.sub(text, 1, -4)
    end
    table.insert(groups, 1, text)
    return table.concat(groups, ",")
end

function UI.FormatCopper(copper)
    if type(copper) ~= "number" then
        return "Unknown"
    end
    local gold = UI.FormatNumber(math.floor(copper / 10000))
    local silver = math.floor((copper % 10000) / 100)
    return gold .. "g " .. silver .. "s " .. (copper % 100) .. "c"
end

function UI.FormatLastSeen(timestamp)
    if type(timestamp) ~= "number" then
        return "Unknown"
    end
    local elapsed = time() - timestamp
    if elapsed < 60 then
        return "Just now"
    elseif elapsed < 3600 then
        return math.floor(elapsed / 60) .. " min ago"
    elseif elapsed < 86400 then
        return math.floor(elapsed / 3600) .. " hr ago"
    end
    return math.floor(elapsed / 86400) .. " days ago"
end

function UI.TierName(tier, rules)
    if tier == nil then
        return "Unknown"
    end
    return rules.tierNames[tier] or ("Unknown tier " .. tostring(tier))
end

function UI.AddTooltipLine(lines, left, right, color)
    table.insert(lines, { left = left, right = right, color = color or Style.text })
end

function UI.ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(owner.tooltipTitle, Style.gold[1], Style.gold[2], Style.gold[3])
    for _, line in ipairs(owner.tooltipLines) do
        local r, g, b = line.color[1], line.color[2], line.color[3]
        if line.right then
            GameTooltip:AddDoubleLine(line.left, line.right, r, g, b, r, g, b)
        else
            GameTooltip:AddLine(line.left, r, g, b, true)
        end
    end
    GameTooltip:Show()
end

function UI.AttachTooltip(owner)
    owner.tooltipTitle = ""
    owner.tooltipLines = {}
    owner:EnableMouse(true)
    owner:SetScript("OnEnter", UI.ShowTooltip)
    local function Hide()
        if GameTooltip:IsOwned(owner) then
            GameTooltip:Hide()
        end
    end
    owner:SetScript("OnLeave", Hide)
    owner:SetScript("OnHide", Hide)
end

function UI.RefreshTooltip(owner, title, lines)
    owner.tooltipTitle = title
    owner.tooltipLines = lines
    if GameTooltip:IsOwned(owner) and owner:IsVisible() then
        UI.ShowTooltip(owner)
    end
end
