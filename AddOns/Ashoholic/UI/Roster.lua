-- Live account-card aggregation. The shared dashboard owns roster rendering;
-- totals below include each visible account exactly once and keep unknowns.
local addonName = ...
local UI = _G[addonName].UI
local Style = UI.Style

local function AccountName(account)
    return (account.name or "Unknown account") .. (account.isCurrent and " (this account)" or "")
end

function UI.RefreshCurrencyCard(card, definition, roster)
    local spendableTotal, bankedTotal, known, unknown = 0, 0, 0, 0
    local lines, details = {}, {}
    for _, account in ipairs(roster) do
        local currencies = account.currencies
        local banked = currencies and currencies[definition.field .. "Banked"]
        local spendable = currencies and currencies[definition.field .. "Spendable"]
        if type(banked) == "number" and type(spendable) == "number" then
            known = known + 1
            spendableTotal, bankedTotal = spendableTotal + spendable, bankedTotal + banked
            UI.AddTooltipLine(details, AccountName(account), nil, Style.gold)
            UI.AddTooltipLine(details, "  Spendable", UI.FormatNumber(spendable))
            UI.AddTooltipLine(details, "  Banked", UI.FormatNumber(banked))
            UI.AddTooltipLine(details, "  Updated", UI.FormatLastSeen(currencies.updatedAt), Style.muted)
        else
            unknown = unknown + 1
            UI.AddTooltipLine(details, AccountName(account), "Unknown", Style.muted)
        end
    end
    card.value:SetText(known > 0 and UI.FormatNumber(spendableTotal) or "Unknown")
    UI.AddTooltipLine(lines, "Spendable total", known > 0 and UI.FormatNumber(spendableTotal) or "Unknown")
    UI.AddTooltipLine(lines, "Banked total", known > 0 and UI.FormatNumber(bankedTotal) or "Unknown")
    UI.AddTooltipLine(lines, " ")
    for _, line in ipairs(details) do lines[#lines + 1] = line end
    if known > 0 and unknown > 0 then
        UI.AddTooltipLine(lines, "Partial total: some visible accounts have unknown balances.", nil, Style.muted)
    elseif #roster == 0 then
        UI.AddTooltipLine(lines, "No visible accounts. Use the account filter to show accounts.", nil, Style.muted)
    elseif known == 0 then
        UI.AddTooltipLine(lines, "Not received from Ebonhold yet. Unknown is not zero.", nil, Style.muted)
    end
    UI.AddTooltipLine(lines, "Only visible accounts are included.", nil, Style.muted)
    UI.AddTooltipLine(lines, definition.note, nil, Style.muted)
    UI.RefreshTooltip(card, definition.tooltipTitle, lines)
end

function UI.RefreshGoldCard(card, roster)
    local total, known, unknown, lines = 0, 0, 0, {}
    local details = {}
    for _, account in ipairs(roster) do
        local accountGold, accountKnown = 0, 0
        for _, character in ipairs(account.characters) do
            if type(character.gold) == "number" then
                accountGold, accountKnown = accountGold + character.gold, accountKnown + 1
            else unknown = unknown + 1 end
        end
        total, known = total + accountGold, known + accountKnown
        UI.AddTooltipLine(details, AccountName(account), accountKnown > 0 and UI.FormatCopper(accountGold) or "Unknown")
    end
    card.value:SetText(known > 0 and (UI.FormatNumber(math.floor(total / 10000)) .. "g") or "Unknown")
    UI.AddTooltipLine(lines, "Character pockets", known > 0 and UI.FormatCopper(total) or "Unknown")
    UI.AddTooltipLine(lines, "Warband bank", "Unknown", Style.muted)
    UI.AddTooltipLine(lines, " ")
    for _, line in ipairs(details) do lines[#lines + 1] = line end
    if unknown > 0 then UI.AddTooltipLine(lines, unknown .. " characters with unknown gold are not counted.", nil, Style.muted) end
    if #roster == 0 then UI.AddTooltipLine(lines, "No visible accounts.", nil, Style.muted) end
    UI.AddTooltipLine(lines, "Only visible accounts are included.", nil, Style.muted)
    UI.AddTooltipLine(lines, "Warband gold is not included: ProjectEbonhold does not share it with other addons.", nil, Style.muted)
    UI.RefreshTooltip(card, "Gold breakdown", lines)
end
