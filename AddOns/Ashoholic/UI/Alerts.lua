-- Reminders are derived from saved evidence, not from invented reset times.
-- Deduplication is session-local: observing the same ready reward repeatedly
-- must not print a notification for every collector callback.
local addonName = ...
local addon = _G[addonName]
local UI, Data = addon.UI, addon.Data
local seen, testBadge = {}, false
local defaults = { reset = true, cache = true, boss = true, prestige = false, stale = true }
local categories = {
    reset = { tab = "Raids", message = "Saved raid loot locks have expired; refresh the affected characters." },
    cache = { tab = "Activities", message = "A saved Call Board observation shows a cache ready." },
    boss = { tab = "Raids", message = "A saved snapshot shows watched raid loot available." },
    prestige = { tab = "Progression", message = "An account's saved Prestige currency requirements are met." },
    stale = { tab = "Roster", message = "Some character snapshots are at least 7 days old." },
}

function UI.NotifyDashboard(text, style)
    if style == "silent" then return end
    if style == "center" then
        RaidNotice_AddMessage(RaidWarningFrame, "Ashoholic: " .. text, ChatTypeInfo.RAID_WARNING)
    else
        print("|cffffca63Ashoholic:|r " .. text)
    end
end

function UI.TestDashboardAlert(style)
    testBadge = true
    UI.NotifyDashboard("Test reminder. The Roster tab has a test badge until reload.", style)
end

function UI.GetDashboardAlerts(state, roster)
    local now, conditions = time(), {}
    for key in pairs(categories) do conditions[key] = {} end
    local watched = Data.GetEncounterWatchlist()
    local watchedRaids = {}
    for _, category in ipairs(Data.GetEncounterCatalog()) do
        for _, boss in ipairs(category.bosses) do
            if boss.id and boss.id > 0 and watched[boss.key] then watchedRaids[#watchedRaids + 1] = boss.id end
        end
    end
    local rules = Data.GetProgressionRules()
    for _, account in ipairs(roster) do
        if Data.IsAccountVisible(account.id) then
            local prestige = account.prestige
            if prestige and prestige.gateProgress >= rules.prestigeGate
                and prestige.pendingEssence and prestige.pendingEssence > 0 then
                conditions.prestige[account.id .. ":" .. prestige.count] = true
            end
            local latestBoard
            for _, character in ipairs(account.characters) do
                local identity = account.id .. ":" .. character.realm .. ":" .. character.name
                if character.lastSeen and now - character.lastSeen >= 7 * 86400 then
                    conditions.stale[identity .. ":" .. character.lastSeen] = true
                end
                local activities = character.activities
                if activities and (not latestBoard or activities.updatedAt > latestBoard.updatedAt) then
                    latestBoard = activities
                end
                local raids = character.raids
                if raids then
                    local expired
                    for _, endsAt in pairs(raids.lockedUntil) do
                        if endsAt <= now then expired = math.max(expired or endsAt, endsAt) end
                    end
                    if expired then conditions.reset[identity .. ":" .. expired] = true end
                    if now - raids.updatedAt < 7 * 86400 then
                        for _, bossId in ipairs(watchedRaids) do
                            local endsAt = raids.lockedUntil[bossId]
                            if not endsAt or endsAt <= now then
                                conditions.boss[identity .. ":" .. bossId] = true
                            end
                        end
                    end
                end
            end
            if latestBoard and latestBoard.cacheRequired > 0
                and latestBoard.cacheProgress >= latestBoard.cacheRequired
                and now < latestBoard.dailyResetAt and now < latestBoard.weeklyResetAt then
                conditions.cache[account.id .. ":" .. latestBoard.cachesOpened] = true
            end
        end
    end
    local badges = {}
    for key, definition in pairs(categories) do
        local enabled = state.alerts and state.alerts[key]
        if not state.alerts then enabled = defaults[key] end
        local new, count = false, 0
        seen[key] = seen[key] or {}
        if enabled then
            for signature in pairs(conditions[key]) do
                count = count + 1
                if not seen[key][signature] then new = true; seen[key][signature] = true end
            end
            for signature in pairs(seen[key]) do
                if not conditions[key][signature] then seen[key][signature] = nil end
            end
        end
        if new then UI.NotifyDashboard(definition.message, state.alertStyle or "chat") end
        badges[definition.tab] = (badges[definition.tab] or 0) + count
    end
    if testBadge then badges.Roster = (badges.Roster or 0) + 1 end
    return badges
end
