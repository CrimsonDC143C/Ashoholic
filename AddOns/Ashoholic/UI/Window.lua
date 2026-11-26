-- Live dashboard chrome, account filter and currency cards.
-- Pages and their rows are created once and reused; snapshots come from UI.model.
local addonName = ...
local addon = _G[addonName]
local UI, Data = addon.UI, addon.Data
local state = UI.state
local GOLD, MUTED, TEAL, STYLE = UI.GOLD, UI.MUTED, UI.TEAL, UI.STYLE
local WIDTH = UI.WINDOW_WIDTH
local frame, accountMenu, accountButton
local pages, tabs, cards, checks = {}, {}, {}, {}

local DEFINITIONS = {
    { title = "SOUL ASH", field = "ash", icon = "inv_soulash" },
    { title = "SOUL SHARDS", field = "shard", icon = "inv_10_jewelcrafting3_soulcage_frost" },
    { title = "SOUL ESSENCE", field = "essence", icon = "inv_misc_supersoulash" },
    { title = "ARTISAN SOUL", field = "artisan", icon = "ability_argus_soulbombdebufflarge" },
    { title = "TOTAL GOLD", icon = "INV_Misc_Coin_02" },
}

function UI.BaseScale()
    return math.max(0.1, math.min(1, (UIParent:GetWidth() - 32) / WIDTH,
        (UIParent:GetHeight() - 32) / UI.WINDOW_HEIGHT))
end

function UI.ApplyScale()
    if frame then frame:SetScale(UI.BaseScale() * state.scale) end
end

function UI.PaintWindow()
    if not frame then return end
    frame:SetBackdrop(UI.Backdrop(state.borderSize))
    frame:SetBackdropColor(unpack(UI.BACKGROUND))
    frame:SetBackdropBorderColor(GOLD[1] * 0.6, GOLD[2] * 0.6, GOLD[3] * 0.6, 1)
    frame.logo:SetTexture(state.logo)
end

function UI.HideAccountMenu()
    if accountMenu then accountMenu:Hide() end
end

-- Each card sums visible accounts once. Missing observations are never zero;
-- a sum containing only known values is explicitly labelled as partial.
local function CurrencyTotals(field)
    local spendable, banked, known, missing = 0, 0, 0, 0
    for _, account in ipairs(UI.model.accounts) do
        if account.visible then
            local balances = account.source.currencies
            local available = balances and balances[field .. "Spendable"]
            local committed = balances and balances[field .. "Banked"]
            if available ~= nil and committed ~= nil then
                known = known + 1
                spendable, banked = spendable + available, banked + committed
            else
                missing = missing + 1
            end
        end
    end
    return spendable, banked, known, missing
end

local function GoldTotals()
    local pockets, warband, pocketsKnown, banksKnown, missing = 0, 0, 0, 0, 0
    for _, account in ipairs(UI.model.accounts) do
        if account.visible then
            for _, character in ipairs(account.characters) do
                if character.source.gold ~= nil then
                    pockets, pocketsKnown = pockets + character.source.gold, pocketsKnown + 1
                else
                    missing = missing + 1
                end
            end
            local bank = account.source.warband
            if bank and bank.gold ~= nil then
                warband, banksKnown = warband + bank.gold, banksKnown + 1
            else
                missing = missing + 1
            end
        end
    end
    return pockets, warband, pocketsKnown, banksKnown, missing
end

local function CardTip(card)
    local definition = card.definition
    UI.TipTitle(definition.title)
    if definition.field then
        local spendable, banked, known, missing = CurrencyTotals(definition.field)
        UI.TipLine("Spendable total", known > 0 and UI.FormatNumber(spendable) or "Unknown")
        UI.TipLine("Banked total", known > 0 and UI.FormatNumber(banked) or "Unknown")
        for _, account in ipairs(UI.model.accounts) do
            if account.visible then
                local balances = account.source.currencies
                local available = balances and balances[definition.field .. "Spendable"]
                local committed = balances and balances[definition.field .. "Banked"]
                UI.TipLine(account.name, available ~= nil and UI.FormatNumber(available) or "Unknown", GOLD)
                if available ~= nil and committed ~= nil then
                    UI.TipLine("  Banked", UI.FormatNumber(committed))
                    UI.TipLine("  Updated", UI.FormatLastSeen(balances.updatedAt), MUTED)
                end
            end
        end
        if missing > 0 then UI.TipLine("Partial total: some account balances are unknown.", nil, MUTED) end
        UI.TipLine("Run earnings are separate from shared account balances.", nil, MUTED)
    else
        local pockets, warband, pocketsKnown, banksKnown, missing = GoldTotals()
        UI.TipLine("Character pockets", pocketsKnown > 0 and UI.FormatCopper(pockets) or "Unknown")
        UI.TipLine("Warband banks", banksKnown > 0 and UI.FormatCopper(warband) or "Unknown")
        for _, account in ipairs(UI.model.accounts) do
            if account.visible then
                local bank = account.source.warband
                UI.TipLine(account.name .. " / Warband", bank and UI.FormatCopper(bank.gold) or "Unknown")
                if bank then UI.TipLine("  Updated", UI.FormatLastSeen(bank.updatedAt), MUTED) end
            end
        end
        if missing > 0 then UI.TipLine("Partial total: some character or bank balances are unknown.", nil, MUTED) end
    end
    UI.TipLine("Only visible accounts are included.", nil, MUTED)
end

local function RefreshCards()
    for _, card in ipairs(cards) do
        local definition = card.definition
        local amount, known, missing
        if definition.field then
            local banked
            amount, banked, known, missing = CurrencyTotals(definition.field)
        else
            local pockets, warband, pocketsKnown, banksKnown
            pockets, warband, pocketsKnown, banksKnown, missing = GoldTotals()
            known = pocketsKnown + banksKnown
            amount = pockets + warband
        end
        local text = "Unknown"
        if known > 0 then
            text = definition.field and UI.FormatNumber(amount) or UI.FormatGold(amount)
            if missing > 0 then text = text .. " *" end
        end
        card.value:SetText(text)
        local size = state.iconStyle == "large" and 22 or 16
        card.title:SetText(state.iconStyle == "text" and definition.title
            or string.format("|TInterface\\Icons\\%s:%d|t %s", definition.icon, size, definition.title))
        UI.RefreshTip(card)
    end
end

local function EscapeSetting()
    local name, found = "AshoholicRosterFrame", false
    for index = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[index] == name then
            if state.window.escClose and not found then
                found = true
            else
                table.remove(UISpecialFrames, index)
            end
        end
    end
    if state.window.escClose and not found then tinsert(UISpecialFrames, name) end
end

local function EnsureChecks()
    for index = 0, #UI.model.accounts do
        if not checks[index] then
            local check = CreateFrame("CheckButton", nil, accountMenu, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", 10, -(35 + index * 31))
            check:SetSize(26, 26)
            check.label = UI.Label(check, "", 30, 7, 234, 11)
            check:SetScript("OnClick", function(self)
                local visible = self:GetChecked() and true or false
                if self.all then
                    for _, account in ipairs(UI.model.accounts) do UI.SetAccountVisible(account, visible) end
                elseif self.account then
                    UI.SetAccountVisible(self.account, visible)
                end
                UI.Refresh()
            end)
            check.all = index == 0
            checks[index] = check
        end
    end
end

local function RefreshFilter()
    EnsureChecks()
    local accounts, count = UI.model.accounts, UI.VisibleAccountCount()
    local label = count == #accounts and "All Accounts"
        or (count == 0 and "No accounts selected" or count .. " accounts selected")
    if count == 1 then
        for _, account in ipairs(accounts) do if account.visible then label = account.name end end
    end
    accountButton.text:SetText(label .. "  v")
    checks[0]:SetChecked(#accounts > 0 and count == #accounts)
    checks[0].label:SetText("All Accounts")
    for index, account in ipairs(accounts) do
        local check = checks[index]
        check.account = account
        check:SetChecked(account.visible)
        check.label:SetText(account.name .. (account.isCurrent and " (current)" or ""))
        check:Show()
    end
    for index = #accounts + 1, #checks do checks[index].account = nil; checks[index]:Hide() end
    accountMenu:SetHeight(98 + (#accounts + 1) * 31)
    accountMenu.done:ClearAllPoints()
    accountMenu.done:SetPoint("TOPLEFT", 178, -(45 + (#accounts + 1) * 31))
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    UI.ReadModel()
    UI.UpdateAlerts()
    RefreshFilter()
    RefreshCards()
    if state.hiddenTabs[state.tab] then state.tab = "Roster" end
    local focused = (state.tab == "Roster" and state.rosterFocus)
        or (state.tab == "Raids" and state.raidsFocus)
    for _, card in ipairs(cards) do UI.SetVisible(card, not focused) end
    local tabX = 24
    for _, name in ipairs(UI.TAB_NAMES) do
        local tab = tabs[name]
        local shown, active = not state.hiddenTabs[name], state.tab == name
        local badge = UI.badges[name] or 0
        tab.text:SetText(tab.title .. (badge > 0 and " (" .. badge .. ")" or ""))
        UI.SetVisible(tab, shown)
        if shown then
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", tabX, -UI.TAB_TOP)
            tabX = tabX + 158
        end
        tab:SetBackdropColor(unpack(active and STYLE.tabActiveBg or STYLE.tabBg))
        tab:SetBackdropBorderColor(unpack(active and GOLD or UI.BUTTON_BORDER))
        UI.Paint(tab.text, active and STYLE.tabActiveText or STYLE.tabText)
        if active and not pages[name] then
            local builder = UI.pageBuilders[name]
            if not builder then error("Ashoholic is missing the " .. name .. " page builder.") end
            pages[name] = builder(frame)
        end
    end
    for name, page in pairs(pages) do
        local active = state.tab == name
        page:ClearAllPoints()
        page:SetPoint("TOPLEFT", 24, -(focused and UI.FOCUS_PAGE_TOP or UI.PAGE_TOP))
        page:SetHeight(UI.PAGE_HEIGHT + (focused and UI.FOCUS_HEIGHT_GAIN or 0))
        UI.SetVisible(page, active)
        if active then page.Refresh() end
    end
    EscapeSetting()
end

local function BuildWindow()
    frame = CreateFrame("Frame", "AshoholicRosterFrame", UIParent)
    UI.frame = frame
    frame:SetSize(WIDTH, UI.WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop(UI.Backdrop(1))
    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT")
    title:SetSize(WIDTH - 280, 58)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function()
        if not state.window.lockWindow then
            if addon.Integrations.Nexus then addon.Integrations.Nexus.Detach() end
            frame:StartMoving()
        end
    end)
    title:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, _, x, y = frame:GetPoint()
        if point then Data.SaveRosterPosition(point, x, y) end
    end)
    frame.logo = title:CreateTexture(nil, "ARTWORK")
    frame.logo:SetPoint("TOPLEFT", 24, -12)
    frame.logo:SetSize(30, 30)
    UI.Label(title, "ASHOHOLIC", 62, 15, 230, 24, GOLD)
    UI.Label(title, "A new chapter for your roster", 282, 24, 400, 12, MUTED)
    UI.Button(frame, "Refresh", WIDTH - 265, 14, 85, 28, function()
        UI.ReadModel(true)
        UI.UpdateAlerts()
        UI.Refresh()
    end)
    UI.Button(frame, "Settings", WIDTH - 172, 14, 115, 28, function() UI.ShowSettings() end)
    UI.Button(frame, "X", WIDTH - 44, 14, 28, 28, function() frame:Hide() end)
    accountButton = UI.Button(frame, "", WIDTH - 256, UI.TAB_TOP, 232, 30, function()
        UI.SetVisible(accountMenu, not accountMenu:IsShown())
    end)
    UI.Tip(accountButton, "Accounts to display", "Choose which accounts appear in the roster, tabs and totals.")
    accountMenu = UI.Surface(frame, WIDTH - 320, UI.TAB_TOP + 34, 296, 98)
    accountMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    accountMenu:EnableMouse(true)
    UI.Label(accountMenu, "SHOW ACCOUNTS", 12, 12, 270, 11, GOLD)
    accountMenu.done = UI.Button(accountMenu, "Done", 178, 45, 106, 28, function() accountMenu:Hide() end)
    accountMenu:Hide()
    for index, name in ipairs(UI.TAB_NAMES) do
        local tabName = name
        local titleText = name == "Raids" and "Raids & Dungeons" or name
        local tab = UI.Button(frame, titleText, 24 + (index - 1) * 158, UI.TAB_TOP, 148, 30, function()
            state.tab = tabName
            UI.Refresh()
        end)
        tab.title = titleText
        tabs[name] = tab
    end
    for index, definition in ipairs(DEFINITIONS) do
        local width = (UI.CONTENT_WIDTH - (#DEFINITIONS - 1) * 18) / #DEFINITIONS
        local card = UI.Surface(frame, 24 + (index - 1) * (width + 18), UI.TAB_TOP + 48, width, 50)
        card.definition = definition
        card.title = UI.Label(card, "", 12, 5, width - 24, 9, MUTED)
        card.value = UI.Label(card, "", 12, 23, width - 24, 16, index == 5 and GOLD or TEAL)
        UI.TipProvider(card, CardTip)
        cards[index] = card
    end
    UI.Label(frame, "Saved observations / hover values for their freshness. Unknown is not zero.",
        24, 690, 800, 11, MUTED)
    UI.Label(frame, "EBONHOLD / LIVE ROSTER", WIDTH - 251, 690, 227, 10, GOLD)
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
        GameTooltip:Hide()
        accountMenu:Hide()
        UI.HideSettings()
        UI.SaveSettings()
    end)
    frame:Hide()
    UI.PaintWindow()
end

function UI.ShowWindow()
    UI.LoadSettings()
    if not frame then BuildWindow() end
    if not frame:IsShown() then
        UI.ApplyScale()
        local position = Data.GetRosterPosition()
        if position then
            frame:ClearAllPoints()
            frame:SetPoint(position.point, UIParent, position.point, position.x, position.y)
        end
        if state.openTab ~= "last" then state.tab = state.openTab end
        frame:Show()
    end
    UI.ReadModel()
    UI.UpdateAlerts()
    UI.Refresh()
    return frame
end

function UI.ToggleWindow()
    if frame and frame:IsShown() then frame:Hide() else UI.ShowWindow() end
end
