-- Focused Lua 5.1 checks for the data layer: the schema version 7 migration,
-- the new Call Board fields, Warband bank gold (packet reading, saving and
-- sync merging) and the sync updater that now runs only while it has work.
-- Run from the repository root; the game client is still needed for live tests.
local environment = setmetatable({}, { __index = _G })
environment._G = environment
local frames, errors, printed, sentMessages = {}, {}, {}, {}
local clock, uptime = 1000, 0
local itemNames = {}
local bankCalls = 0
local callboardListener
local methods = {}

-- Like WoW, OnUpdate runs only on shown frames (Tick) while events also
-- reach hidden frames (Fire).
local function NewFrame()
    local frame = setmetatable({ shown = true, scripts = {}, events = {} }, { __index = methods })
    frames[#frames + 1] = frame
    return frame
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end

-- WoW's hooksecurefunc: the original runs first, then the hook receives the
-- same arguments. Hooking a missing function is a test failure.
function environment.hooksecurefunc(owner, name, hook)
    if type(owner) == "string" then owner, name, hook = environment, owner, name end
    local original = owner[name]
    assert(type(original) == "function", "Hooked a missing function: " .. tostring(name))
    owner[name] = function(...)
        local results = { original(...) }
        hook(...)
        return unpack(results)
    end
end

function environment.CreateFrame() return NewFrame() end
function environment.time() return clock end
function environment.GetTime() return uptime end
function environment.GetCVar() return "Account" end
function environment.GetRealmName() return "Realm" end
function environment.GetItemInfo(itemId) return itemNames[itemId] end
function environment.geterrorhandler() return function(problem) errors[#errors + 1] = problem end end
function environment.print(message) printed[#printed + 1] = message end
function environment.RegisterAddonMessagePrefix() return true end
function environment.SendAddonMessage(prefix, message, channel, target)
    sentMessages[#sentMessages + 1] = { prefix = prefix, message = message, channel = channel, target = target }
end
-- The companion's own bank handler; Ashoholic's hook must never stop it.
function environment.ExtBank_OnPacket() bankCalls = bankCalls + 1 end
local Noop = function() end
environment.ProjectEbonhold = {
    -- Like the companion's locale table, a missing translation returns its key.
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Callboard = { OnChanged = function(listener) callboardListener = listener end },
    SkillTree = { UpdateTotalSoulPoints = Noop, OnApplyChangesResult = Noop },
    SS = { SEND_LOADOUTS = 1 },
    RequestLoadoutFromServer = Noop,
    sendToServer = function() error("Unexpected server request") end,
}
environment.Ashoholic = {}

local function Load(path)
    setfenv(assert(loadfile(path)), environment)("Ashoholic")
end

local function Fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

local function Tick(elapsed)
    uptime = uptime + elapsed
    for _, frame in ipairs(frames) do
        if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, elapsed) end
    end
end

local function ExpectError(text, callback)
    local ok, problem = pcall(callback)
    assert(not ok, "Expected an error containing: " .. text)
    assert(string.find(tostring(problem), text, 1, true), "Unexpected error: " .. tostring(problem))
end

local function CountPrinted(text)
    local count = 0
    for _, message in ipairs(printed) do
        if string.find(message, text, 1, true) then count = count + 1 end
    end
    return count
end

Load("AddOns\\Ashoholic\\Data\\Schema.lua")
Load("AddOns\\Ashoholic\\Data\\Store.lua")
Load("AddOns\\Ashoholic\\Integrations\\ProjectEbonhold.lua")
Load("AddOns\\Ashoholic\\Collectors\\Currencies.lua")
Load("AddOns\\Ashoholic\\Sync\\Codec.lua")
local frameCount = #frames
Load("AddOns\\Ashoholic\\Sync\\Transport.lua")
assert(#frames == frameCount + 1, "Transport should create one frame")
local transportFrame = frames[#frames]
local addon = environment.Ashoholic
local Schema, Data, Codec, Sync = addon.Schema, addon.Data, addon.Sync.Codec, addon.Sync
local Integration = addon.Integrations.ProjectEbonhold

local function CurrentAccount()
    for _, account in ipairs(Data.GetRoster()) do
        if account.isCurrent then return account end
    end
    error("Current account not found")
end

local function MainCharacter()
    for _, character in ipairs(CurrentAccount().characters) do
        if character.name == "Main" then return character end
    end
    error("Main character not found")
end

-- 1. Version 7 renames the dashboard's "mock" window options to "window" in
-- the dashboard state and every saved profile, dropping malformed values.
local loginWindow = { openLogin = true, combatHide = false, lockWindow = true, escClose = true }
local keptWindow = { openLogin = false, combatHide = true, lockWindow = false, escClose = false }
environment.AshoholicDB = {
    schemaVersion = 6,
    myAccountId = "account",
    accounts = { account = { name = "Account", realms = {} } },
    settings = {
        ui = {
            dashboard = { state = { tab = "Roster", mock = loginWindow } },
            profiles = {
                saved = {
                    Moved = { options = { mock = { openLogin = false, combatHide = true, lockWindow = false, escClose = true } } },
                    Kept = { options = { mock = { openLogin = true }, window = keptWindow } },
                    Malformed = { options = { mock = "broken", window = true } },
                    Replaced = { options = { mock = { escClose = false }, window = "broken" } },
                    NoOptions = {},
                    NotATable = "broken",
                },
                characters = {},
            },
        },
    },
}
Data.Initialize()
local database = environment.AshoholicDB
assert(Schema.VERSION == 7 and database.schemaVersion == 7)
local dashboardState = database.settings.ui.dashboard.state
assert(dashboardState.mock == nil and dashboardState.window == loginWindow and dashboardState.tab == "Roster")
local profiles = database.settings.ui.profiles.saved
assert(profiles.Moved.options.mock == nil and profiles.Moved.options.window.combatHide == true)
assert(profiles.Kept.options.mock == nil and profiles.Kept.options.window == keptWindow)
assert(profiles.Malformed.options.mock == nil and profiles.Malformed.options.window == nil)
assert(profiles.Replaced.options.mock == nil and profiles.Replaced.options.window.escClose == false)
assert(next(profiles.NoOptions) == nil and profiles.NotATable == "broken")
assert(database.accounts.account.name == "Account")
-- Missing or unexpected tables on the way are normal and never an error.
for _, settings in ipairs({
    {}, { ui = {} }, { ui = "broken" }, { ui = { dashboard = {}, profiles = {} } },
    { ui = { dashboard = { state = "broken" }, profiles = { saved = "broken" } } },
}) do
    local old = { schemaVersion = 6, accounts = {}, settings = settings }
    Schema.Migrate(old)
    assert(old.schemaVersion == 7)
end
local packetShaped = { schemaVersion = 6, accounts = {} }
Schema.Migrate(packetShaped)
assert(packetShaped.schemaVersion == 7)

-- 2. Call Board observations: new optional fields, and a quest Ashoholic
-- cannot identify is skipped instead of discarding the whole board.
Data.SaveCharacterBasics("Realm", "Main", {
    guid = "main-guid", class = "MAGE", level = 80, gold = 100, location = "Dalaran",
})
local rosterChanges = 0
Data.OnRosterChanged(function() rosterChanges = rosterChanges + 1 end)

local function Quest(questId, cadence, title, changes)
    local quest = {
        questId = questId, cadence = cadence, title = title, done = 0, max = 1, state = 1,
        accountWide = false, ashes = 10, shards = 0, copper = 0, artisan = 0, orbs = 0,
        category = 0, cost = 0,
    }
    for key, value in pairs(changes or {}) do quest[key] = value end
    return quest
end

local observed = {}
Integration.WatchActivities(function(snapshot) observed[#observed + 1] = snapshot end)
assert(type(callboardListener) == "function")
itemNames[4242] = string.rep("Long", 20)
itemNames[4243] = string.rep("a", 63) .. "\195\169" -- ends in a two-byte letter
itemNames[600945] = "Cached Renewal" -- WoW's item cache wins over the fallback
environment.ProjectEbonhold.L["Elixir of Shards"] = "Translated Shards"
local board = {
    receivedAt = 0, dailyResetIn = 3600.7, weeklyResetIn = 86400,
    cacheProgress = 5, cacheRequired = 10, cachesOpened = 1, equippedIlvl = 245,
    weeklyClaims = 4,
    quests = {
        Quest(11, 0, "Frostveil daily", { category = 8 }),
        Quest(11, 1, "Duplicate of 11"),
        Quest(12, 7, "Unknown cadence"),
        Quest(13, 1, "Paid contract", { cost = 5000 }),
        "not a quest",
        Quest(0, 0, "No ID"),
    },
    rail = {
        { count = 5, entries = { 600941 } },
        { count = 1, entries = { 600940, 600944, 600945, 600941 } },
        { count = 3, entries = { 4242, 4243, 777 } },
    },
}
clock, uptime = 2000, 30
callboardListener("board", board)
assert(#observed == 1 and #errors == 0)
local snapshot = observed[1]
assert(snapshot.updatedAt == 1970 and snapshot.dailyResetAt == 1970 + 3600 and snapshot.weeklyResetAt == 1970 + 86400)
assert(snapshot.quests[11].title == "Frostveil daily" and snapshot.quests[11].category == 8 and snapshot.quests[11].cost == nil)
assert(snapshot.quests[13].cost == 5000 and snapshot.quests[13].category == nil)
assert(snapshot.quests[12] == nil and snapshot.quests[0] == nil and snapshot.weeklyClaims == 4)
local rail = snapshot.rail
assert(#rail == 3 and rail[1].count == 1 and rail[2].count == 3 and rail[3].count == 5)
local firstItems = rail[1].items
assert(#firstItems == 4 and firstItems[1].id == 600940 and firstItems[4].id == 600941)
assert(firstItems[1].name == "Elixir of Ashes" and firstItems[2].name == "Elixir of Memories")
assert(firstItems[3].name == "Cached Renewal" and firstItems[4].name == "Translated Shards")
assert(rail[2].items[1].name == string.rep("Long", 16) and rail[2].items[2].name == string.rep("a", 63))
assert(rail[2].items[3].id == 777 and rail[2].items[3].name == nil)
Data.SaveCharacterActivities("Realm", "Main", "main-guid", snapshot)
local activities = MainCharacter().activities
assert(activities.weeklyClaims == 4 and #activities.rail == 3 and activities.rail[1].items[4].name == "Translated Shards")
assert(activities.quests[11].category == 8 and activities.quests[13].cost == 5000 and MainCharacter().itemLevel == 245)

-- An oversized or malformed rail must never appear to be complete early.
-- The rest of the board is still saved and the omission is reported.
local steps = {}
for count = 12, 1, -1 do steps[#steps + 1] = { count = count, entries = { 1000 + count } } end
board.rail = steps
callboardListener("board", board)
assert(observed[2].rail == nil and observed[2].weeklyClaims == nil and observed[2].quests[11])
assert(CountPrinted("reward rail is incomplete") == 1)
board.rail = { { count = 1, entries = { 1, 2, 3, 4, 5 } } }
callboardListener("board", board)
assert(observed[3].rail == nil and CountPrinted("reward rail is incomplete") == 2)
board.rail = { { count = 1, entries = { [1] = 1, [3] = 3 } } }
callboardListener("board", board)
assert(observed[4].rail == nil and CountPrinted("reward rail is incomplete") == 3)
board.rail, board.weeklyClaims = nil, 0
callboardListener("board", board)
assert(observed[5].rail == nil and observed[5].weeklyClaims == nil)
-- A translation table that fails keeps the English fallback name.
local translations = environment.ProjectEbonhold.L
environment.ProjectEbonhold.L = setmetatable({}, { __index = function() error("locale failure") end })
board.rail = { { count = 1, entries = { 600944 } } }
callboardListener("board", board)
assert(observed[6].rail[1].items[1].name == "Elixir of Memories")
environment.ProjectEbonhold.L = translations
-- A structurally invalid board is still reported, not saved.
callboardListener("board", { quests = {}, receivedAt = 0, dailyResetIn = -1, weeklyResetIn = 0 })
assert(#observed == 6 and #errors == 1 and string.find(errors[1], "reset timers", 1, true))

-- 3. Data validates the new fields as strictly as the rest of the group.
local function Activities(changes)
    local value = {
        cacheProgress = 1, cacheRequired = 10, cachesOpened = 0,
        dailyResetAt = 5000, weeklyResetAt = 90000, updatedAt = 2000,
        quests = { [21] = { title = "Daily", cadence = "daily", done = 0, max = 1, state = 1, accountWide = false } },
    }
    for key, change in pairs(changes or {}) do value[key] = change end
    return value
end
local function WithQuest(field, value)
    local result = Activities()
    result.quests[21][field] = value
    return result
end
local function SaveActivities(value)
    Data.SaveCharacterActivities("Realm", "Main", "main-guid", value)
end
local function Step(count, ...)
    local items = {}
    for index, id in ipairs({ ... }) do items[index] = { id = id } end
    return { count = count, items = items }
end

SaveActivities(Activities()) -- snapshots without the new fields stay valid
SaveActivities(WithQuest("category", 8))
SaveActivities(WithQuest("cost", 1))
SaveActivities(Activities({ weeklyClaims = 0 }))
for _, bad in ipairs({ 0, -1, 1.5, "8", math.huge }) do
    ExpectError("invalid Call Board activity", function() SaveActivities(WithQuest("category", bad)) end)
    ExpectError("invalid Call Board activity", function() SaveActivities(WithQuest("cost", bad)) end)
end
for _, bad in ipairs({ -1, 1.5, "3", math.huge }) do
    ExpectError("weekly claim count", function() SaveActivities(Activities({ weeklyClaims = bad })) end)
end
SaveActivities(Activities({ rail = { Step(1, 600940), Step(1, 600941, 600944, 600945, 600940) } }))
local named = Step(2, 600940)
named.items[1].name = string.rep("n", 64)
SaveActivities(Activities({ rail = { named } }))
local tooManySteps = {}
for count = 1, 11 do tooManySteps[count] = Step(count, 600940) end
local holes = { Step(1, 600940) }
holes[3] = Step(3, 600940)
local itemHoles = Step(1, 600940)
itemHoles.items[3] = { id = 600941 }
local function NamedStep(name)
    local step = Step(1, 600940)
    step.items[1].name = name
    return step
end
local badRails = {
    {}, tooManySteps, holes, { Step(1, 600940), extra = true },
    { Step(2, 600940), Step(1, 600940) }, { Step(0, 600940) }, { Step(1.5, 600940) },
    { Step(1) }, { Step(1, 1, 2, 3, 4, 5) }, { itemHoles },
    { Step(1, 0) }, { Step(1, -2) }, { Step(1, 1.5) },
    { NamedStep(string.rep("n", 65)) }, { NamedStep("") }, { NamedStep(5) },
    { "not a step" }, "not a rail",
}
for index, badRail in ipairs(badRails) do
    assert(not pcall(SaveActivities, Activities({ rail = badRail })), "Invalid rail " .. index .. " was accepted")
end
assert(MainCharacter().activities.rail[1].items[1].name == string.rep("n", 64))

-- 4. Warband bank gold from the companion's bank packets.
local function Bytes(...)
    local hex = {}
    for index, byte in ipairs({ ... }) do hex[index] = string.format("%02x", byte) end
    return table.concat(hex)
end
local function Number(value, byteCount) -- little-endian, upper-case digits
    local hex = {}
    for index = 1, byteCount do
        hex[index] = string.format("%02X", value % 256)
        value = math.floor(value / 256)
    end
    return table.concat(hex)
end
local function BankPacket(kind, bagCount, cellCount, tail)
    local hex = Bytes(kind, 2, bagCount)
    if kind == 0 then hex = hex .. string.rep("ab", bagCount * 10) end
    return hex .. Number(cellCount, 2) .. string.rep("cd", cellCount * 23) .. (tail or "")
end
local function Tail(gold, open)
    local tail = Bytes(1) .. Number(gold, 8)
    if open then tail = tail .. Bytes(open) end
    return tail
end

-- The collector hooked the bank at load. Before login the packet waits.
assert(not transportFrame.shown)
environment.ExtBank_OnPacket(BankPacket(0, 2, 3, Tail(123456789012, 1)))
assert(bankCalls == 1 and CurrentAccount().warband == nil)
Fire("PLAYER_LOGIN")
local warband = CurrentAccount().warband
assert(warband.gold == 123456789012 and warband.unlocked == true and warband.updatedAt == 2000)
assert(not transportFrame.shown)

local parsed = {}
assert(Integration.WatchWarbandBank(function(value) parsed[#parsed + 1] = value end) == true)
local function Parse(hex)
    local before, calls = #parsed, bankCalls
    environment.ExtBank_OnPacket(hex)
    assert(bankCalls == calls + 1 and #parsed <= before + 1)
    return parsed[before + 1]
end
local full = Parse(BankPacket(0, 2, 3, Tail(123456789012, 1)))
assert(full.gold == 123456789012 and full.unlocked == true and full.updatedAt == 2000)
-- A delta update has no bag entries, even with a non-zero bag count.
local delta = Parse(BankPacket(1, 5, 1, Tail(5000, 0)))
assert(delta.gold == 5000 and delta.unlocked == false)
local noOpenByte = Parse(BankPacket(1, 0, 0, Tail(0)))
assert(noOpenByte.gold == 0 and noOpenByte.unlocked == nil)
assert(Parse(BankPacket(1, 0, 0, Tail(2 ^ 53 - 1, 1))).gold == 2 ^ 53 - 1)
local truncated = BankPacket(0, 2, 4, Tail(5, 1))
truncated = string.sub(truncated, 1, #truncated - 80)
local ignoredPackets = {
    BankPacket(1, 0, 2), -- no tail (older server)
    BankPacket(1, 0, 0, Bytes(1)), -- store byte without gold
    BankPacket(1, 0, 0, Bytes(1) .. Number(5, 7)), -- gold cut short
    truncated, -- the item cells run past the end
    BankPacket(1, 0, 0, Tail(5, 1)) .. "a", -- odd length
    "0001", "",
    "zz" .. string.sub(BankPacket(1, 0, 0, Tail(5, 1)), 3), -- kind
    Bytes(1, 0, 0) .. "zzzz" .. Tail(5, 1), -- cell count
    BankPacket(1, 0, 0, "zz" .. Number(5, 8) .. Bytes(1)), -- store byte
    BankPacket(1, 0, 0, Bytes(1) .. "0g" .. Number(5, 7) .. Bytes(1)), -- gold
    BankPacket(1, 0, 0, Tail(5) .. "x1"), -- open byte
    BankPacket(1, 0, 0, Tail(2 ^ 53, 1)), -- too large to count exactly
    false, 12,
}
for index, hex in ipairs(ignoredPackets) do
    assert(Parse(hex) == nil, "Bank packet " .. index .. " should be ignored")
end
assert(Parse(nil) == nil)
-- An Ashoholic failure is reported without stopping the companion's bank.
local failObserver = true
Integration.WatchWarbandBank(function() if failObserver then error("observer failure") end end)
local callsBefore = bankCalls
environment.ExtBank_OnPacket(BankPacket(1, 0, 0, Tail(42, 1)))
assert(bankCalls == callsBefore + 1 and #errors == 2 and string.find(errors[2], "observer failure", 1, true))
failObserver = false
-- Without the companion's extended bank, nothing is watched.
local companionBank = environment.ExtBank_OnPacket
environment.ExtBank_OnPacket = nil
assert(Integration.WatchWarbandBank(Noop) == false)
environment.ExtBank_OnPacket = companionBank

-- Saving: an unchanged balance only confirms the saved one, without a redraw.
rosterChanges = 0
Data.SaveAccountWarband({ gold = 100, unlocked = true, updatedAt = 3000 })
assert(rosterChanges == 1)
Data.SaveAccountWarband({ gold = 100, unlocked = true, updatedAt = 3100 })
assert(rosterChanges == 1 and CurrentAccount().warband.updatedAt == 3100)
Data.SaveAccountWarband({ gold = 150, unlocked = true, updatedAt = 3200 })
assert(rosterChanges == 2)
Data.SaveAccountWarband({ gold = 150, updatedAt = 3300 })
assert(rosterChanges == 3 and CurrentAccount().warband.unlocked == nil)
Data.SaveAccountWarband({ gold = 1, unlocked = false, updatedAt = 3250 }) -- older
local current = CurrentAccount().warband
assert(rosterChanges == 3 and current.gold == 150 and current.updatedAt == 3300)
current.gold = 999
assert(CurrentAccount().warband.gold == 150, "The roster must return a copy")
for index, bad in ipairs({
    { gold = -1, updatedAt = 3400 }, { gold = 1.5, updatedAt = 3400 },
    { gold = 2 ^ 53, updatedAt = 3400 }, { gold = 5, unlocked = "yes", updatedAt = 3400 },
    { gold = 5 }, { unlocked = true, updatedAt = 3400 }, "not a snapshot",
}) do
    assert(not pcall(Data.SaveAccountWarband, bad), "Invalid Warband gold " .. index .. " was accepted")
end
assert(CurrentAccount().warband.gold == 150 and rosterChanges == 3)

-- 5. Sync exports the new data, accepts older packets and merges the warband
-- group by observation time.
local exported = Codec.Decode(Codec.Encode(Data.ExportCurrentAccount()))
assert(exported.schemaVersion == 7 and exported.account.warband.gold == 150)
assert(exported.account.realms.Realm.Main.activities.rail[1].items[1].name == string.rep("n", 64))
local function OtherPacket(version, warbandGroup)
    return {
        schemaVersion = version,
        accountId = "other-account",
        account = {
            name = "Synced account",
            warband = warbandGroup,
            realms = { Realm = { Alt = { basics = {
                guid = "alt-guid", class = "MAGE", level = 80, gold = 5, location = "Dalaran", updatedAt = 1500,
            } } } },
        },
    }
end
local function OtherAccount()
    for _, account in ipairs(Data.GetRoster()) do
        if account.id == "other-account" then return account end
    end
end
assert(Data.ImportAccount(OtherPacket(6)) == true) -- version 6 has no warband group
assert(OtherAccount().warband == nil and OtherAccount().characters[1].name == "Alt")
assert(Data.ImportAccount(OtherPacket(7, { gold = 777, unlocked = true, updatedAt = 1500 })) == true)
assert(Data.ImportAccount(OtherPacket(7, { gold = 1, unlocked = false, updatedAt = 1400 })) == false)
assert(OtherAccount().warband.gold == 777)
assert(Data.ImportAccount(OtherPacket(7, { gold = 888, unlocked = false, updatedAt = 1600 })) == true)
local otherWarband = OtherAccount().warband
assert(otherWarband.gold == 888 and otherWarband.unlocked == false and otherWarband.updatedAt == 1600)
ExpectError("invalid Warband bank gold", function()
    Data.ImportAccount(OtherPacket(7, { gold = -5, updatedAt = 1700 }))
end)
ExpectError("different schema version", function() Data.ImportAccount(OtherPacket(8)) end)
assert(OtherAccount().warband.gold == 888)

-- 6. The sync updater runs only while it has work.
local function Whisper(sender, message)
    Fire("CHAT_MSG_ADDON", "ASHO_SYNC2", message, "WHISPER", sender)
end
local function SendUntil(text, count)
    local guard = 0
    while CountPrinted(text) < count do
        guard = guard + 1
        assert(guard < 5000, "Sending never finished")
        Tick(0.3)
    end
end

-- Untrusted senders are reported once per ten minutes; at most 50 are
-- remembered, and each is forgotten after its ten minutes.
Whisper("Stranger", "Q:1")
Whisper("Stranger", "Q:1")
assert(CountPrinted("transfer from Stranger.") == 1 and transportFrame.shown)
Tick(0.3)
assert(transportFrame.shown)
uptime = uptime + 600
Tick(0.3)
assert(not transportFrame.shown)
Whisper("Stranger", "Q:1")
assert(CountPrinted("transfer from Stranger.") == 2 and transportFrame.shown)
for index = 1, 60 do Whisper("Stranger" .. index, "D:1:1:1:x") end
assert(CountPrinted("Ignored an untrusted") == 2 + 49)
uptime = uptime + 600
Tick(0.3)
assert(not transportFrame.shown)
Whisper("Stranger55", "Q:1")
assert(CountPrinted("transfer from Stranger55.") == 1)
uptime = uptime + 600
Tick(0.3)
assert(not transportFrame.shown)

-- An exchange keeps the updater running until its reply times out.
Data.SetTrustedPeer("friend-realm", "Friend")
Sync.Start("Friend")
assert(transportFrame.shown)
SendUntil("Finished sending to Friend", 1)
assert(sentMessages[1].message == "Q:1" and sentMessages[1].target == "Friend")
local transferId = string.match(sentMessages[2].message, "^D:(%x+):1:")
assert(transferId and transportFrame.shown)
Whisper("Friend", "A:" .. transferId)
assert(CountPrinted("Friend confirmed the account import.") == 1)
Tick(0.3)
assert(transportFrame.shown) -- still waiting for Friend's own account
uptime = uptime + 901
Tick(0.3)
assert(CountPrinted("No account reply from Friend.") == 1 and not transportFrame.shown)

-- A received transfer wakes the updater, which sends the confirmation and
-- then stops. The imported account carries its Warband gold.
local wire = Codec.EncodeWire(OtherPacket(7, { gold = 999, unlocked = true, updatedAt = 1800 }))
assert(not string.find(wire, "~", 1, true))
local parts = {}
for position = 1, #wire, 150 do parts[#parts + 1] = string.sub(wire, position, position + 149) end
for index, part in ipairs(parts) do
    Whisper("Friend", "D:abc123:" .. index .. ":" .. #parts .. ":" .. part)
    assert(transportFrame.shown)
end
assert(CountPrinted("Received Friend's account.") == 1 and OtherAccount().warband.gold == 999)
Tick(0.3)
assert(sentMessages[#sentMessages].message == "A:abc123" and not transportFrame.shown)

-- A request is answered; a repeat within ten seconds is refused, and the
-- remembered request time is forgotten afterwards.
Whisper("Friend", "Q:1")
Whisper("Friend", "Q:1")
assert(CountPrinted("Sending account data to trusted peer Friend.") == 1)
assert(CountPrinted("Repeated sync request from Friend.") == 1 and transportFrame.shown)
SendUntil("Finished sending to Friend", 2)
local replyId = string.match(sentMessages[#sentMessages].message, "^D:(%x+):")
Whisper("Friend", "A:" .. replyId)
assert(CountPrinted("Friend confirmed the account import.") == 2)
uptime = uptime + 10
Tick(0.3)
assert(not transportFrame.shown)

assert(#errors == 2, "Unexpected reported errors: " .. tostring(errors[3]))
print("Data layer checks passed.")
