local addonName = ...
local addon = _G[addonName]

addon.Characters = {}
local ns = addon.Characters
local characterList = {}
local view = {}
local realmCollapsed = {}
local accountCollapsed = {}

local INFO_REALM_LINE     = 0
local INFO_ACCOUNT_LINE   = 1
local INFO_CHARACTER_LINE = 2
local INFO_TOTAL_LINE     = 3

local currentSortField = "name"
local currentSortAscending = true

function ns:ToggleRealm(realm)
    realmCollapsed[realm] = not realmCollapsed[realm]
    ns:BuildView()
end
function ns:ToggleAccount(accKey)
    accountCollapsed[accKey] = not accountCollapsed[accKey]
    ns:BuildView()
end

local function computeLockouts(charDB)
    local lockedRaids10, lockedRaids25 = {}, {}
    if charDB.SavedInstance then
        for Instance, InstanceInfo in pairs(charDB.SavedInstance) do
            local reset, lastcheck = strsplit("|", InstanceInfo)
            reset = tonumber(reset) or 0
            lastcheck = tonumber(lastcheck) or 0
            if (reset - (time() - lastcheck)) > 0 then
                if Instance:find("Naxxramas") or Instance:find("Obsidian Sanctum") or Instance:find("Eye of Eternity") then
                    if Instance:find("10") then
                        table.insert(lockedRaids10, Instance)
                    elseif Instance:find("25") then
                        table.insert(lockedRaids25, Instance)
                    end
                end
            end
        end
    end
    return #lockedRaids10, #lockedRaids25, lockedRaids10, lockedRaids25
end

-- SavedInstance values are "remaining|checkedAt" from older scans, or
-- "remaining|checkedAt|difficulty|isRaid" from current ones. Keys from the
-- pre-overhaul roster were "Name (size)|id"; current keys are "Name (size)".
local function LockoutLabel(instanceKey, diff)
    local name = tostring(instanceKey or "Unknown")
    local pipe = string.find(name, "|", 1, true)
    if pipe and pipe > 1 then
        name = string.sub(name, 1, pipe - 1)
    end
    if type(diff) ~= "string" or diff == "" then return name end
    local lower = string.lower(diff)
    if lower == "normal" or lower == "10 player" or lower == "25 player" then
        return name
    end
    local nameLower = string.lower(name)
    if string.find(lower, "heroic", 1, true) and not string.find(nameLower, "heroic", 1, true) then
        return name .. " (Heroic)"
    end
    if string.find(name, diff, 1, true) or string.find(lower, "heroic", 1, true) then
        return name
    end
    return name .. " - " .. diff
end

function ns:ActiveLockouts(charDB)
    local list = {}
    if type(charDB) ~= "table" or type(charDB.SavedInstance) ~= "table" then
        return list
    end
    local now = time()
    for instanceKey, info in pairs(charDB.SavedInstance) do
        if type(info) == "string" then
            local reset, lastcheck, diff, raidFlag = strsplit("|", info)
            reset = tonumber(reset) or 0
            lastcheck = tonumber(lastcheck) or 0
            local expires = reset - (now - lastcheck)
            if expires > 0 then
                -- Older scans did not store the raid flag. A parenthesized
                -- size of 10 or more is a raid on this client.
                local isRaid = raidFlag == "1"
                if raidFlag ~= "0" and raidFlag ~= "1" then
                    local size = tonumber(string.match(tostring(instanceKey), "%((%d+)%)"))
                    isRaid = size ~= nil and size >= 10
                end
                list[#list + 1] = {
                    label = LockoutLabel(instanceKey, diff),
                    expires = expires,
                    isRaid = isRaid,
                }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.isRaid ~= b.isRaid then return a.isRaid end
        if a.label == b.label then return a.expires < b.expires end
        return a.label < b.label
    end)
    return list
end

-- Same rolling window LockoutInfo uses: 10 raid entries, each lasting an hour
-- from the last time that raid copy was entered or left.
local HOURLY_LIMIT = 10
local HOURLY_WINDOW = 3600
local HOURLY_DIFF = { [1] = "10", [2] = "25", [3] = "10H", [4] = "25H" }

function ns:HourlyLockouts(charDB)
    local result = {
        tracked = false,
        count = 0,
        limit = HOURLY_LIMIT,
        nextFree = 0,
        entries = {},
    }
    if type(charDB) ~= "table" or not charDB.hourlyTracked then return result end
    result.tracked = true
    local saved = charDB.hourlyEntries
    if type(saved) ~= "table" then return result end
    local now = time()
    for i = 1, #saved do
        local entry = saved[i]
        if type(entry) == "table" and type(entry.time) == "number" then
            local remain = entry.time + HOURLY_WINDOW - now
            if remain > 0 then
                local label = entry.name or "Unknown"
                local tag = HOURLY_DIFF[tonumber(entry.difficulty)]
                if tag and not string.find(label, tag, 1, true) then
                    label = label .. " (" .. tag .. ")"
                end
                result.entries[#result.entries + 1] = {
                    label = label,
                    expires = remain,
                    time = entry.time,
                }
            end
        end
    end
    table.sort(result.entries, function(a, b)
        if a.time == b.time then return a.label < b.label end
        return a.time < b.time
    end)
    result.count = #result.entries
    if result.count > 0 then result.nextFree = result.entries[1].expires end
    return result
end

function ns:BuildList()
    wipe(characterList)

    local realm = GetRealmName()
    local realmMoney, realmRunAsh, realmSpendableAsh = 0, 0, 0

    -- Realm header
    table.insert(characterList, {
        linetype = INFO_REALM_LINE,
        realm = realm,
        isCollapsed = realmCollapsed[realm] or false,
    })

    -- Group by account
    local accounts = {}
    for key, charDB in pairs(addon.db.global.Characters) do
        if charDB.name and charDB.name ~= "" then
            local accName = charDB.account or "Main Account"
            accounts[accName] = accounts[accName] or {}
            table.insert(accounts[accName], { key = key, db = charDB })
        end
    end

    -- Stable ordering of accounts
    local accountOrder = {}
    for name in pairs(accounts) do table.insert(accountOrder, name) end
    table.sort(accountOrder, function(a,b) return a:lower() < b:lower() end)

    local realmCommittedAsh = 0

    for _, accName in ipairs(accountOrder) do
        local accKey = realm .. "." .. accName
        local accChars = accounts[accName]
        local accMoney, accRunAsh = 0, 0
        local accSpendable, accCommitted, latestSeen = 0, 0, -1

        for _, entry in ipairs(accChars) do
            local db = entry.db
            accMoney = accMoney + (db.money or 0)

            -- Per-character run soul ash (own contribution)
            local runAsh = db.RunSoulAsh
            if runAsh == nil then
                runAsh = math.max(0, (db.SoulAsh or 0) - (db.SpendableSoulAsh or 0))
            end
            accRunAsh = accRunAsh + runAsh

            -- Both pools are account-wide; use freshest character's snapshot
            local seen = db.lastSeen or 0
            if seen > latestSeen then
                latestSeen = seen
                accSpendable = db.SpendableSoulAsh or 0
                accCommitted = db.CommittedSoulAsh or 0
            end
        end

        table.insert(characterList, {
            linetype = INFO_ACCOUNT_LINE,
            realm = realm,
            account = accName,
            accKey = accKey,
            isCollapsed = accountCollapsed[accKey] or false,
            money = accMoney,
            soulAsh = accRunAsh + accSpendable + accCommitted,
            spendableAsh = accSpendable,
            committedAsh = accCommitted,
        })

        realmCommittedAsh = realmCommittedAsh + accCommitted

        for _, entry in ipairs(accChars) do
            local charDB = entry.db
            local charRunAsh = charDB.RunSoulAsh
            if charRunAsh == nil then
                charRunAsh = math.max(0, (charDB.SoulAsh or 0) - (charDB.SpendableSoulAsh or 0))
            end
            local money = charDB.money or 0
            local count10, count25, r10, r25 = computeLockouts(charDB)

            table.insert(characterList, {
                linetype = INFO_CHARACTER_LINE,
                key = entry.key,
                account = accName,
                accKey = accKey,
                name = charDB.name,
                level = charDB.level or 1,
                class = charDB.class or "WARRIOR",
                soulAsh = charRunAsh,           -- per-character share only
                spendableAsh = accSpendable,     -- shared pool, for tooltip
                raidResetCost = charDB.RaidResetCost or 50000,
                money = money,
                location = charDB.location or "",
                lastSeen = charDB.lastSeen or 0,
                isLocked10 = count10 > 0, isLocked25 = count25 > 0,
                lockedCount10 = count10, lockedCount25 = count25,
                lockedRaids10 = r10, lockedRaids25 = r25,
                wtScanned = charDB.wtScanned or false,
            })

            realmMoney = realmMoney + money
            realmRunAsh = realmRunAsh + charRunAsh
        end

        realmSpendableAsh = realmSpendableAsh + accSpendable
    end

    table.insert(characterList, {
        linetype = INFO_TOTAL_LINE,
        money = realmMoney,
        soulAsh = realmRunAsh + realmSpendableAsh + realmCommittedAsh,
        runAsh = realmRunAsh,
        spendableAsh = realmSpendableAsh,
        committedAsh = realmCommittedAsh,
    })
end

function ns:BuildView()
    wipe(view)

    local isRealmCollapsed = false
    local isAccCollapsed = false

    for index = 1, #characterList do
        local item = characterList[index]
        if item.linetype == INFO_REALM_LINE then
            isRealmCollapsed = realmCollapsed[item.realm] or false
            isAccCollapsed = false
            table.insert(view, index)
        elseif item.linetype == INFO_ACCOUNT_LINE then
            isAccCollapsed = accountCollapsed[item.accKey] or false
            if not isRealmCollapsed then table.insert(view, index) end
        elseif item.linetype == INFO_TOTAL_LINE then
            table.insert(view, index)
        else
            if not isRealmCollapsed and not isAccCollapsed then
                table.insert(view, index)
            end
        end
    end
end

function ns:Get(index) return characterList[view[index]] end
function ns:GetNum() return #view end

function ns:Sort(field)
    if currentSortField == field then
        currentSortAscending = not currentSortAscending
    else
        currentSortField = field
        currentSortAscending = true
    end
    ns:ReapplySort()
    ns:BuildView()
end

-- Sort ONLY the characters within each account group.
-- Realm, account, and total lines stay exactly where they are.
function ns:ReapplySort()
    if not currentSortField then return end

    local function sortFn(a, b)
        local valA, valB = a[currentSortField], b[currentSortField]
        if valA == nil then valA = (currentSortField == "name" or currentSortField == "location") and "" or 0 end
        if valB == nil then valB = (currentSortField == "name" or currentSortField == "location") and "" or 0 end
        if currentSortAscending then return valA < valB else return valA > valB end
    end

    local newList = {}
    local pending = {}
    local function flush()
        if #pending > 0 then
            table.sort(pending, sortFn)
            for _, c in ipairs(pending) do table.insert(newList, c) end
            wipe(pending)
        end
    end

    for _, item in ipairs(characterList) do
        if item.linetype == INFO_CHARACTER_LINE then
            table.insert(pending, item)
        else
            flush()
            table.insert(newList, item)
        end
    end
    flush()

    wipe(characterList)
    for _, item in ipairs(newList) do table.insert(characterList, item) end
end