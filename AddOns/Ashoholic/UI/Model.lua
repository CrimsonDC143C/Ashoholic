--[[
    UI/Model.lua - prepares saved observations for display.

    Data flow: Game -> Collectors -> Data -> this file -> the UI pages.

    Data.GetRoster() returns display-safe COPIES of every saved account and
    character. This file reads that roster only after it changed, puts the
    current account first and prepares ready-made text for every character.
    Values that were never observed are shown as "Unknown"; they are never
    turned into 0.

    Pages read UI.model instead of calling Data themselves, so one change is
    read once, no matter how many pages show it.

      UI.model.accounts    account views, current account first
      UI.model.characters  every character view, in account order
      UI.model.byKey       [character key] = character view
      UI.model.rules       Prestige/Torment display rules from the companion
                           (nil if ProjectEbonhold did not supply them)
      UI.model.stamp       grows by one on every rebuild (used by caches)

    Account view:
      id, name, isCurrent, source (the copied account from Data.GetRoster),
      visible (the account filter), collapsed and color (local preferences),
      characters (array of character views)

    Character view:
      key, name, class, realm, isPlayer, stale, account (its account view),
      source (the copied character from Data.GetRoster),
      values[column] and sortValues[column] for the roster table,
      location, seen, action, detail[1..8] and detailTimes[1..8]

    Memory: every rebuild creates fresh tables and drops the old ones, which
    Lua's garbage collector frees. Frames are never created here.
]]

local addonName = ...
local addon = _G[addonName]
local UI, Data = addon.UI, addon.Data
local state = UI.state

local model = { accounts = {}, characters = {}, byKey = {}, rules = nil, stamp = 0 }
UI.model = model

-- True when saved data changed since the last read. It starts true, so the
-- first page that needs the model reads it.
local dirty = true

-- The player's own row is selected once per session, on the first read that
-- contains it. After that, the player's clicks decide what is selected.
local playerSelected = false

-- Called by UI/Dashboard.lua whenever Data reports a change.
function UI.MarkModelDirty()
    dirty = true
end

-- One stable key per character row. Names are unique per realm and realms
-- per account, so the three together identify a row. "\031" is an invisible
-- control character that cannot appear in names.
local function CharacterKey(accountId, realm, name)
    return accountId .. "\031" .. realm .. "\031" .. name
end

-- The local preferences for one account (collapsed, color, original name).
-- Created on first use, so every account can be configured.
function UI.AccountConfig(accountId)
    local config = UI.accountConfig[accountId]
    if not config then
        config = {}
        UI.accountConfig[accountId] = config
    end
    return config
end

-------------------------------------------------------------------------------
-- Character text
-------------------------------------------------------------------------------

local function CharacterView(account, character, rules, now)
    local contracts, build, torment = character.contracts, character.echoBuild, character.torment
    local view = {
        key = CharacterKey(account.id, character.realm, character.name),
        name = character.name,
        class = character.class,
        realm = character.realm,
        isPlayer = character.isPlayer,
        account = account,
        source = character,
        values = {},
        sortValues = {},
    }

    -- Text for every roster column (see UI.COLUMNS in UI/Widgets.lua).
    local values = view.values
    values.level = character.level and tostring(character.level) or "Unknown"
    values.ilvl = character.itemLevel and tostring(character.itemLevel) or "Unknown"
    values.runAsh = UI.FormatNumber(character.runAsh)
    values.runShards = UI.FormatNumber(character.runShards)
    values.gold = UI.FormatCopper(character.gold)
    values.seen = UI.FormatLastSeen(character.lastSeen)
    values.bonus, values.offerings = "Unknown", "Unknown"
    values.anchor, values.build = "Unknown", "Unknown"
    values.location = character.realm .. " / " .. (character.location or "Unknown")

    -- Offerings and the Soul Anchor come from one server reply (contracts).
    local remaining
    if contracts then
        remaining = math.max(0, contracts.offeringsMax - contracts.offeringsUsed)
        values.bonus = "+" .. tostring(contracts.offeringBonusPct) .. "%"
        values.offerings = remaining .. " / " .. contracts.offeringsMax
        if contracts.anchorState == 0 then
            values.anchor = "None"
        elseif contracts.anchorPlace ~= nil and contracts.anchorPlace ~= "" then
            values.anchor = contracts.anchorPlace
        else
            -- The anchor is set, but the reply did not say where.
            values.anchor = "Set (place unknown)"
        end
    end

    -- A disabled loadout system has no slot or name (see Data/Schema.lua).
    if build then
        if not build.enabled then
            values.build = "Unavailable"
        elseif build.name ~= "" then
            values.build = build.name
        else
            values.build = "Loadout " .. tostring(build.slot)
        end
    end

    -- Sorting uses raw numbers where possible; nil sorts last (Roster.lua).
    local sortValues = view.sortValues
    sortValues.character = string.lower(character.name)
    sortValues.level = character.level
    sortValues.ilvl = character.itemLevel
    sortValues.runAsh = character.runAsh
    sortValues.runShards = character.runShards
    sortValues.gold = character.gold
    sortValues.seen = character.lastSeen and now - character.lastSeen
    sortValues.bonus = contracts and contracts.offeringBonusPct
    sortValues.offerings = remaining
    sortValues.build = build and string.lower(values.build)
    sortValues.anchor = contracts and string.lower(values.anchor)
    sortValues.location = character.location and string.lower(character.location)

    -- The detail panel: run values, contracts, Echo build, then Torment.
    -- Selected Torment is per character; access is shared by the account.
    view.detail = {
        values.runAsh, values.runShards, values.bonus, values.offerings,
        values.build, values.anchor,
        UI.TierName(torment and torment.currentTier, rules),
        UI.TierName(torment and torment.highestUnlocked, rules),
    }
    -- When each detail value was observed (shown in its tooltip).
    view.detailTimes = {
        character.runUpdatedAt, character.runUpdatedAt,
        contracts and contracts.updatedAt, contracts and contracts.updatedAt,
        build and build.updatedAt, contracts and contracts.updatedAt,
        torment and torment.updatedAt, torment and torment.accessUpdatedAt,
    }

    view.location = values.location
    view.seen = values.seen
    view.stale = character.lastSeen ~= nil and now - character.lastSeen >= UI.STALE_SECONDS
    if view.isPlayer then
        view.action = "Currently playing"
    elseif view.stale then
        view.action = "Snapshot over 7 days old; log in to refresh."
    else
        view.action = "Saved character snapshot"
    end
    return view
end

-------------------------------------------------------------------------------
-- Reading the roster
-------------------------------------------------------------------------------

-- The current account first, then the others in a stable order. Account IDs
-- never change, so renaming an account does not move it around.
local function AccountOrder(left, right)
    if left.isCurrent ~= right.isCurrent then
        return left.isCurrent
    end
    return left.id < right.id
end

-- Rebuilds UI.model when saved data changed (or when force is true, for
-- example to update "5 min ago" texts). Returns the model.
function UI.ReadModel(force)
    if not dirty and not force then
        return model
    end

    -- If Data raises an error (damaged saved data), dirty stays true, so the
    -- next refresh tries again instead of showing half-updated rows.
    local roster = Data.GetRoster()
    table.sort(roster, AccountOrder)
    -- The collector supplies these session-only rules before the UI loads.
    local rules = Data.GetProgressionRules()
    local now = time()

    local accounts, characters, byKey = {}, {}, {}
    for _, account in ipairs(roster) do
        local config = UI.accountConfig[account.id]
        local accountView = {
            id = account.id,
            name = account.name,
            isCurrent = account.isCurrent,
            source = account,
            visible = Data.IsAccountVisible(account.id),
            collapsed = config and config.collapsed or false,
            color = config and config.color or nil,
            characters = {},
        }
        accounts[#accounts + 1] = accountView
        for _, character in ipairs(account.characters) do
            local view = CharacterView(accountView, character, rules, now)
            accountView.characters[#accountView.characters + 1] = view
            characters[#characters + 1] = view
            byKey[view.key] = view
            if view.isPlayer and not playerSelected then
                playerSelected = true
                state.selectedKey = view.key
            end
        end
    end

    model.accounts, model.characters, model.byKey = accounts, characters, byKey
    model.rules = rules
    model.stamp = model.stamp + 1
    dirty = false
    return model
end

-------------------------------------------------------------------------------
-- Selection and account preferences
-------------------------------------------------------------------------------

-- The selected character, or the best visible replacement: the player, then
-- the first character of the first visible account. Nil when none is shown.
function UI.SelectedCharacter()
    local selected = state.selectedKey and model.byKey[state.selectedKey]
    if selected and selected.account.visible then
        return selected
    end
    local fallback
    for _, character in ipairs(model.characters) do
        if character.account.visible then
            if character.isPlayer then
                fallback = character
                break
            end
            fallback = fallback or character
        end
    end
    if fallback then
        state.selectedKey = fallback.key
    end
    return fallback
end

-- How many accounts the filter shows.
function UI.VisibleAccountCount()
    local count = 0
    for _, account in ipairs(model.accounts) do
        if account.visible then
            count = count + 1
        end
    end
    return count
end

-- Collapse or expand one account's rows. A local preference, so it is
-- saved with the window settings, not in the account data.
function UI.SetAccountCollapsed(account, collapsed)
    account.collapsed = collapsed and true or false
    UI.AccountConfig(account.id).collapsed = collapsed and true or nil
end

-- Change the color of one account's name (nil returns to the theme color).
function UI.SetAccountColor(account, color)
    account.color = color
    UI.AccountConfig(account.id).color = color
end

-- Show or hide accounts. Data saves the choice and reports the change,
-- which marks the model dirty; the caller then refreshes the window.
function UI.SetAccountVisible(account, visible)
    if account.visible ~= visible then
        Data.SetAccountVisible(account.id, visible)
    end
end

-- Rename an account. The first local name is remembered, so Settings can
-- offer to restore it.
function UI.RenameAccount(account, name)
    local config = UI.AccountConfig(account.id)
    config.originalName = config.originalName or account.name
    Data.SetAccountName(account.id, name)
end

-------------------------------------------------------------------------------
-- Encounters (shared by the Raids page and the reminders in UI/Alerts.lua)
-------------------------------------------------------------------------------

-- The catalogue is a tree: category (Raids, Dungeons) > expansion >
-- instance > boss. The collector supplies it before the UI loads, and it
-- cannot change during a session, so one copy is read and kept.
local catalog

function UI.EncounterCatalog()
    if catalog == nil then
        catalog = Data.GetEncounterCatalog()
    end
    return catalog
end

-- The watchlist: [boss key] = true. It is read from Data once, changed in
-- place by the Raids page, and saved again with UI.SaveWatchlist(). A damaged
-- watchlist must be reported rather than silently replaced with an empty one.
local watchlist, watchedRaidIds

function UI.Watchlist()
    if not watchlist then
        watchlist = Data.GetEncounterWatchlist()
    end
    return watchlist
end

function UI.SaveWatchlist()
    watchedRaidIds = nil
    Data.SaveEncounterWatchlist(UI.Watchlist())
end

-- Server boss IDs of every watched raid encounter. Dungeon entries have no
-- ID because they are names only. Cached until the watchlist is saved.
function UI.WatchedRaidBossIds()
    if not watchedRaidIds then
        watchedRaidIds = {}
        local tree, watched = UI.EncounterCatalog(), UI.Watchlist()
        if tree then
            for _, category in ipairs(tree) do
                for _, boss in ipairs(category.bosses) do
                    if boss.id and watched[boss.key] then
                        watchedRaidIds[#watchedRaidIds + 1] = boss.id
                    end
                end
            end
        end
    end
    return watchedRaidIds
end

-- Weekly loot status of one boss for one character. character is the copy
-- from Data.GetRoster (a character view's .source). Returns the status and,
-- when the server reported one, the time the loot lock ends.
--   "Tracked"   a dungeon entry (no boss ID): never a kill or loot claim
--   "Unknown"   no complete raid reply has been saved for this character
--   "Looted"    the saved loot lock has not ended yet
--   "Available" no lock was reported, or the reported lock has ended
function UI.RaidStatus(character, bossId, now)
    if not bossId then
        return "Tracked"
    end
    local raids = character.raids
    if not raids then
        return "Unknown"
    end
    local endsAt = raids.lockedUntil[bossId]
    if endsAt and endsAt > now then
        return "Looted", endsAt
    end
    return "Available", endsAt
end
