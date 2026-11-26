--[[
    UI/Alerts.lua - reminders and the number badges on the tabs.

    Each reminder is a condition found in the saved data (UI.model). Every
    condition has a "signature": a short text that stays the same while the
    condition lasts, for example "<character key>:<boss ID>". A reminder is
    announced once, when a new signature appears. Signatures that disappear
    are forgotten, so the same reminder may be announced again if it comes
    back later. Nothing is remembered across a /reload.

      reset     a saved raid loot lock has ended (server-reported end time)
      cache     a character's free, finished Call Board activities would
                fill its cache bar (every claimed contract counts)
      boss      a watched raid boss is available in a recent raid snapshot
      prestige  an account meets its Prestige currency requirements
      stale     a character snapshot is at least 7 days old

    Badges count the current conditions of each enabled reminder and are
    shown on the tab where the reminder can be checked. Only visible
    accounts are considered.

    Timing: UI/Dashboard.lua checks the reminders every 30 seconds, even
    while the window is closed. Announcements start with the first of those
    checks, so the reminders at login use the data collected since then.
    The window also updates its badges whenever it redraws.

    Memory: the condition tables are emptied and refilled on every check;
    the announced signatures are pruned to the current conditions.
]]

local addonName = ...
local addon = _G[addonName]
local UI = addon.UI
local state = UI.state

-- ProjectEbonhold's Callboard.STATE.COMPLETE: finished, the reward can be claimed.
local STATE_COMPLETE = 2

-- The reminder choices in Settings > Alerts, in the order they are shown.
UI.ALERT_OPTIONS = {
    { key = "reset", label = "Raid loot lock expired (server-reported time)" },
    { key = "cache", label = "Call Board cache within reach" },
    { key = "boss", label = "Watched boss available in saved snapshot" },
    { key = "prestige", label = "Account ready to Prestige" },
    { key = "stale", label = "Character snapshot is at least 7 days old" },
}

-- The tab each reminder badges and the text it announces.
local CATEGORIES = {
    reset = { tab = "Raids",
        message = "A saved raid loot lock has ended. Log in to that character to refresh its raids (Raids tab)." },
    cache = { tab = "Activities",
        message = "A character can fill its Call Board cache by claiming finished activities (Activities tab)." },
    boss = { tab = "Raids",
        message = "A watched boss is available in a saved raid snapshot (Raids tab)." },
    prestige = { tab = "Progression",
        message = "An account meets its Prestige currency requirements (Progression tab)." },
    stale = { tab = "Roster",
        message = "Some character snapshots are at least 7 days old (Roster tab)." },
}

-- conditions[key][signature] = true: what the last check found.
-- announced[key][signature] = true: what has been announced already.
local conditions, announced = {}, {}
for key in pairs(CATEGORIES) do
    conditions[key], announced[key] = {}, {}
end

-- UI.badges[tab] = number of current conditions. Refilled on every check.
UI.badges = {}

local armed = false       -- true once announcements may be made
local testBadge = false    -- Settings > Alerts > Send test alert

-------------------------------------------------------------------------------
-- Announcing
-------------------------------------------------------------------------------

-- Show a reminder in the chosen style. "silent" leaves only the tab badge.
local function Notify(text)
    local style = state.alertStyle
    if style == "center" then
        RaidNotice_AddMessage(RaidWarningFrame, "Ashoholic: " .. text, ChatTypeInfo["RAID_WARNING"])
    elseif style == "chat" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffca63Ashoholic:|r " .. text)
    end
end

-- Announce a test reminder and add a test badge to the Roster tab until
-- the next /reload. Settings refreshes the window afterwards.
function UI.TestAlert()
    testBadge = true
    Notify("Test reminder. The Roster tab shows a test badge until the next /reload.")
end

-- Allow announcements. UI/Dashboard.lua calls this at its first check.
function UI.ArmAlerts()
    armed = true
end

-------------------------------------------------------------------------------
-- Call Board: is a character's cache within reach?
-------------------------------------------------------------------------------

-- Finished, free to claim, and its reset has not passed since the board was
-- saved (after a reset the saved state no longer tells what is open).
local function IsReadyForFree(quest, board, now)
    if quest.state ~= STATE_COMPLETE or quest.cost then
        return false
    elseif quest.cadence == "daily" then
        return board.dailyResetAt > now
    elseif quest.cadence == "weekly" then
        return board.weeklyResetAt > now
    end
    return true
end

-- Shared (account-wide) activities appear on every character's board.
-- Like the Activities tab, use the copy from the newest board that has one.
local sharedBoard = {}
local function CountSharedReady(account, now)
    wipe(sharedBoard)
    for _, character in ipairs(account.characters) do
        local board = character.source.activities
        if board then
            for questId, quest in pairs(board.quests) do
                if quest.accountWide then
                    local kept = sharedBoard[questId]
                    if not kept or board.updatedAt > kept.updatedAt then
                        sharedBoard[questId] = board
                    end
                end
            end
        end
    end
    local count = 0
    for questId, board in pairs(sharedBoard) do
        if IsReadyForFree(board.quests[questId], board, now) then
            count = count + 1
        end
    end
    wipe(sharedBoard)
    return count
end

-- Any character may claim a shared activity, so the account's ready shared
-- activities count toward every character's bar.
local function CacheWithinReach(board, sharedReady, now)
    local ready = sharedReady
    for _, quest in pairs(board.quests) do
        if not quest.accountWide and IsReadyForFree(quest, board, now) then
            ready = ready + 1
        end
    end
    return ready > 0 and board.cacheProgress + ready >= board.cacheRequired
end

-------------------------------------------------------------------------------
-- Checking
-------------------------------------------------------------------------------

local function CheckCharacter(character, sharedReady, watchedBosses, now)
    local source, key = character.source, character.key

    if source.lastSeen and now - source.lastSeen >= UI.STALE_SECONDS then
        conditions.stale[key .. ":" .. source.lastSeen] = true
    end

    local raids = source.raids
    if raids then
        -- The latest lock that has ended. The signature changes when another
        -- lock ends later, which makes a new reminder.
        local ended
        for _, endsAt in pairs(raids.lockedUntil) do
            if endsAt <= now and (not ended or endsAt > ended) then
                ended = endsAt
            end
        end
        if ended then
            conditions.reset[key .. ":" .. ended] = true
        end
        -- Only recent snapshots: a week-old "available" may be long gone.
        if now - raids.updatedAt < UI.STALE_SECONDS then
            for _, bossId in ipairs(watchedBosses) do
                if UI.RaidStatus(source, bossId, now) == "Available" then
                    conditions.boss[key .. ":" .. bossId] = true
                end
            end
        end
    end

    local board = source.activities
    if board and CacheWithinReach(board, sharedReady, now) then
        conditions.cache[key] = true
    end
end

local function FindConditions(now)
    for _, found in pairs(conditions) do
        wipe(found)
    end
    local rules = UI.model.rules
    local watchedBosses = UI.WatchedRaidBossIds()
    for _, account in ipairs(UI.model.accounts) do
        if account.visible then
            -- Without the rules the Soul Ash gate is unknown: no reminder.
            local prestige = account.source.prestige
            if rules and prestige and prestige.gateProgress >= rules.prestigeGate
                and prestige.pendingEssence and prestige.pendingEssence > 0 then
                conditions.prestige[account.id .. ":" .. prestige.count] = true
            end
            local sharedReady = CountSharedReady(account, now)
            for _, character in ipairs(account.characters) do
                CheckCharacter(character, sharedReady, watchedBosses, now)
            end
        end
    end
end

-- Check every reminder against UI.model, announce new conditions (once
-- armed) and refill UI.badges. The caller reads the model first.
function UI.UpdateAlerts()
    FindConditions(time())
    local badges = UI.badges
    wipe(badges)
    for _, option in ipairs(UI.ALERT_OPTIONS) do
        local key = option.key
        local found, done = conditions[key], announced[key]
        if state.alerts[key] then
            local count, new = 0, false
            for signature in pairs(found) do
                count = count + 1
                if armed and not done[signature] then
                    done[signature] = true
                    new = true
                end
            end
            -- Forget conditions that ended (assigning nil while looping is
            -- allowed in Lua for keys that already exist).
            for signature in pairs(done) do
                if not found[signature] then
                    done[signature] = nil
                end
            end
            if new then
                Notify(CATEGORIES[key].message)
            end
            if count > 0 then
                local tab = CATEGORIES[key].tab
                badges[tab] = (badges[tab] or 0) + count
            end
        else
            -- Turned off: forget everything, so turning it on again
            -- announces what is pending at that moment.
            wipe(done)
        end
    end
    if testBadge then
        badges.Roster = (badges.Roster or 0) + 1
    end
    return badges
end
