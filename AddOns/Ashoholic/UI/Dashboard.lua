-- Maps saved observations into the approved dashboard. The renderer never
-- reads game APIs or SavedVariables; sample characters stay in preview mode.
local addonName = ...
local addon = _G[addonName]
local UI, Data = addon.UI, addon.Data
local accounts, characters, accountIndices, characterIndices = {}, {}, {}, {}
local roster, dashboard, dirty, raidPage = {}, nil, true, nil
local settings
local adapter = {}

local function CharacterView(view, accountIndex, character)
    local contracts, build = character.contracts, character.echoBuild
    view.source, view.account = character, accountIndex
    view.name, view.class = character.name, character.class
    view.level, view.ilvl = character.level, character.itemLevel
    view.isPlayer = character.isPlayer
    view.location = character.realm .. " / " .. (character.location or "Unknown")
    view.runAsh, view.runShards = UI.FormatNumber(character.runAsh), character.runShards
    view.gold, view.seen = UI.FormatCopper(character.gold), UI.FormatLastSeen(character.lastSeen)
    local rules = Data.GetProgressionRules()
    view.selectedTier = UI.TierName(character.torment and character.torment.currentTier, rules)
    view.highestTier = UI.TierName(character.torment and character.torment.highestUnlocked, rules)
    view.bonus, view.offerings, view.anchor, view.build = "Unknown", "Unknown", "Unknown", "Unknown"
    local remaining
    if contracts then
        remaining = math.max(0, contracts.offeringsMax - contracts.offeringsUsed)
        view.bonus = "+" .. tostring(contracts.offeringBonusPct) .. "%"
        view.offerings = remaining .. " / " .. contracts.offeringsMax
        view.anchor = contracts.anchorState == 0 and "None"
            or (contracts.anchorPlace ~= "" and contracts.anchorPlace or "Set (place unknown)")
    end
    if build then
        view.build = not build.enabled and "Unavailable"
            or (build.name ~= "" and build.name or "Loadout " .. build.slot)
    end
    view.stale = character.lastSeen and time() - character.lastSeen >= 7 * 86400
    view.action = view.isPlayer and "Currently playing" or (view.stale and "Snapshot over 7 days old; log in to refresh." or "Saved character snapshot")
    view.sortValues = {
        character = string.lower(character.name), level = character.level, ilvl = character.itemLevel,
        runAsh = character.runAsh, runShards = character.runShards, gold = character.gold,
        seen = character.lastSeen and time() - character.lastSeen,
        bonus = contracts and contracts.offeringBonusPct, offerings = remaining,
        build = build and string.lower(view.build), anchor = contracts and string.lower(view.anchor),
        location = character.location and string.lower(character.location),
    }
end

function adapter.Read()
    roster = Data.GetRoster()
    table.sort(roster, function(left, right)
        if left.isCurrent ~= right.isCurrent then return left.isCurrent end
        return left.id < right.id
    end)
    for _, account in ipairs(roster) do
        local index = accountIndices[account.id]
        if not index then
            index = #accounts + 1
            accountIndices[account.id] = index
            accounts[index] = {
                id = account.id, name = account.name, originalName = account.name,
                visible = Data.IsAccountVisible(account.id),
            }
            local saved = settings or Data.GetDashboardSettings()
            local config = saved and saved.accountConfig and saved.accountConfig[account.id]
            if config then
                accounts[index].color, accounts[index].collapsed = config.color, config.collapsed
                accounts[index].originalName = config.originalName or account.name
            end
        end
        local view = accounts[index]
        view.source, view.name, view.isCurrent = account, account.name, account.isCurrent
        account.color = view.color
        for _, character in ipairs(account.characters) do
            local key = account.id .. "\031" .. character.realm .. "\031" .. character.name
            local characterIndex = characterIndices[key]
            if not characterIndex then
                characterIndex = #characters + 1
                characterIndices[key] = characterIndex
                characters[characterIndex] = {}
            end
            CharacterView(characters[characterIndex], index, character)
        end
    end
    return accounts, characters
end

function adapter.Load()
    settings = settings or Data.GetDashboardSettings()
    if not settings then
        settings = { state = { tab = Data.GetDefaultTab(), openTab = "last" }, accountConfig = {} }
    end
    settings.state.collapsed = {}
    for index, account in ipairs(accounts) do
        local config = settings.accountConfig and settings.accountConfig[account.id]
        if config then
            account.color, account.originalName = config.color, config.originalName or account.originalName
            settings.state.collapsed[index] = config.collapsed
        end
    end
    return settings
end

function adapter.Save(value)
    if raidPage then
        value.raidView = {
            compact = raidPage.compact, showPicker = raidPage.showPicker,
            focused = raidPage.focused, matrixOffset = raidPage.matrixOffset,
            expanded = raidPage.expanded, collapsed = raidPage.collapsed,
        }
    end
    value.accountConfig = {}
    for index, account in ipairs(accounts) do
        value.accountConfig[account.id] = {
            color = account.color, originalName = account.originalName,
            collapsed = value.state.collapsed[index],
        }
        local visible = value.state.accounts[index] == true
        if visible ~= Data.IsAccountVisible(account.id) then Data.SetAccountVisible(account.id, visible) end
    end
    settings = value
    Data.SaveDashboardSettings(value)
end

function adapter.Rename(accountId, name)
    Data.SetAccountName(accountId, name)
end

function adapter.Swap(character)
    if not character then return end
    addon.Integrations.FastSwap.Swap(accounts[character.account].source, character.source)
end

function adapter.Cards(cards, selected)
    local visible = {}
    for index, account in ipairs(accounts) do
        if selected[index] then visible[#visible + 1] = account.source end
    end
    for index, field in ipairs({ "ash", "shard", "essence", "artisan" }) do
        local card = cards[index]
        UI.AttachTooltip(card)
        UI.RefreshCurrencyCard(card, {
            field = field, tooltipTitle = card.title:GetText(),
            note = index <= 2 and "Run earnings are separate from these shared account balances." or "Shared account currency.",
        }, visible)
        if GameTooltip:IsOwned(card) then UI.ShowTooltip(card) end
    end
    UI.AttachTooltip(cards[5])
    UI.RefreshGoldCard(cards[5], visible)
    if GameTooltip:IsOwned(cards[5]) then UI.ShowTooltip(cards[5]) end
end

function adapter.CreatePage(name, parent, width, refresh)
    local rules = Data.GetProgressionRules()
    local page
    if name == "Raids" then
        page = UI.CreateRaidsPage(parent, width, refresh)
        raidPage = page
        local view = settings and settings.raidView
        if view then
            page.compact, page.showPicker, page.focused = view.compact, view.showPicker, view.focused
            page.matrixOffset, page.expanded, page.collapsed = view.matrixOffset, view.expanded, view.collapsed
        end
    elseif name == "Progression" then
        page = UI.CreateProgressionPage(parent, width, rules)
    elseif name == "Activities" then
        page = UI.CreateActivitiesPage(parent, width)
    else
        page = UI.CreateTrialsPage(parent, width)
    end

    page:ClearAllPoints()
    page:SetSize(width, 508)
    page.Refresh = function()
        local visible = {}
        for _, account in ipairs(roster) do
            if Data.IsAccountVisible(account.id) then visible[#visible + 1] = account end
        end
        UI["Refresh" .. name](page, visible, rules)
    end
    return page
end

function adapter.ConfigurePage(page, state)
    if page.catalog then
        state.raidsFocus = page.focused
        page.statusStyle, page.classIcons = state.statusStyle, state.classIcons
    end
end

function adapter.SavePosition(frame)
    local point, _, _, x, y = frame:GetPoint()
    Data.SaveRosterPosition(point, x, y)
end

function adapter.Detach()
    if addon.Integrations.Nexus then addon.Integrations.Nexus.Detach() end
end

function adapter.RestorePosition(frame)
    local position = Data.GetRosterPosition()
    if position then
        frame:ClearAllPoints()
        frame:SetPoint(position.point, UIParent, position.point, position.x, position.y)
    end
end

function adapter.Appearance(colors, state)
    UI.ApplyDashboardAppearance(colors, state)
    if addon.Minimap then addon.Minimap.SetIcon(state.logo) end
end

adapter.BuildSync = UI.BuildDashboardSync
adapter.Profiles = Data.GetUIProfiles
adapter.SaveProfiles = Data.SaveUIProfiles
adapter.CharacterKey = Data.GetCurrentCharacterKey

function adapter.Alerts(state)
    return UI.GetDashboardAlerts(state, roster)
end

adapter.TestAlert = UI.TestDashboardAlert

function adapter.DetailTooltip(widget, character, index)
    local source = character.source
    local timestamps = {
        source.runUpdatedAt, source.runUpdatedAt,
        source.contracts and source.contracts.updatedAt, source.contracts and source.contracts.updatedAt,
        source.echoBuild and source.echoBuild.updatedAt, source.contracts and source.contracts.updatedAt,
        source.torment and source.torment.updatedAt, source.torment and source.torment.accessUpdatedAt,
    }
    local lines = {}
    UI.AddTooltipLine(lines, "Updated", UI.FormatLastSeen(timestamps[index]))
    UI.AddTooltipLine(lines, index == 8 and "Access is shared account-wide." or "Last saved observation; offline values cannot refresh themselves.")
    UI.AttachTooltip(widget)
    UI.RefreshTooltip(widget, character.name .. " / saved detail", lines)
end

function adapter.RowTooltip(widget, character)
    local source, lines = character.source, {}
    UI.AddTooltipLine(lines, "Character basics", UI.FormatLastSeen(source.lastSeen))
    UI.AddTooltipLine(lines, "Equipped item level", UI.FormatLastSeen(source.itemLevelUpdatedAt))
    UI.AddTooltipLine(lines, "Run currencies", UI.FormatLastSeen(source.runUpdatedAt))
    UI.AddTooltipLine(lines, "Offerings / Soul Anchor", UI.FormatLastSeen(source.contracts and source.contracts.updatedAt))
    UI.AddTooltipLine(lines, "Echo build", UI.FormatLastSeen(source.echoBuild and source.echoBuild.updatedAt))
    UI.AddTooltipLine(lines, "Shared Torment access", UI.FormatLastSeen(source.torment and source.torment.accessUpdatedAt))
    UI.AttachTooltip(widget)
    UI.RefreshTooltip(widget, character.name .. " / observation ages", lines)
end

function adapter.ResetSync()
    for key in pairs(Data.GetTrustedPeers()) do Data.SetTrustedPeer(key, nil) end
end

function adapter.MinimapHidden(value)
    local current = Data.GetMinimapSettings()
    if value ~= nil then
        Data.SaveMinimapSettings(current.angle, value)
        addon.Minimap.Refresh()
    end
    return current.hidden
end

local function Dashboard()
    if not dashboard then dashboard = addon:CreateDashboard(adapter) end
    return dashboard
end

function addon:ToggleRosterUI()
    addon.Collectors.Currencies.RequestBalancesIfNeeded()
    Dashboard().Toggle()
end

function addon:ShowRosterUI()
    addon.Collectors.Currencies.RequestBalancesIfNeeded()
    return Dashboard().Show()
end

function UI.ToggleSettings()
    Dashboard().Settings()
end

function UI.RefreshRoster()
    if dashboard then dashboard.Refresh() end
end

Data.OnRosterChanged(function() dirty = true end)
local function CurrentPreferences()
    local saved = Data.GetDashboardSettings()
    local profiles = Data.GetUIProfiles()
    local key = Data.GetCurrentCharacterKey()
    local name = (key and profiles.characters[key]) or profiles.account
    local profile = name and profiles.saved[name]
    return profile and profile.options or (saved and saved.state or {})
end

local events, elapsed, ready = CreateFrame("Frame"), 0, false
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then ready = true end
    if event == "PLAYER_LOGOUT" then
        if dashboard then dashboard.Save() end
        return
    end
    local extras = CurrentPreferences().mock or {}
    if event == "PLAYER_LOGIN" and extras.openLogin then addon:ShowRosterUI() end
    if event == "PLAYER_REGEN_DISABLED" and extras.combatHide and _G.AshoholicRosterFrame then
        _G.AshoholicRosterFrame:Hide()
    end
end)
events:SetScript("OnUpdate", function(_, delta)
    if not ready then return end
    elapsed = elapsed + delta
    if not dirty and elapsed < 30 then return end
    dirty, elapsed = false, 0
    UI.GetDashboardAlerts(CurrentPreferences(), Data.GetRoster())
    UI.RefreshRoster()
end)
