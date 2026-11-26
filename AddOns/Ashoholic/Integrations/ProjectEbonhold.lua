local addonName = ...
local addon = _G[addonName]

addon.Integrations = addon.Integrations or {}
addon.Integrations.ProjectEbonhold = addon.Integrations.ProjectEbonhold or {}

local Integration = addon.Integrations.ProjectEbonhold

-- A post-hook still runs inside the companion's call. Report our errors to
-- WoW without interrupting the rest of the companion's server handling.
local function ProtectObserver(observer)
    return function(...)
        local ok, problem = pcall(observer, ...)
        if not ok then
            geterrorhandler()(problem)
        end
    end
end

local function RequireObserver(callback, description)
    if type(callback) ~= "function" then
        error("Ashoholic needs a callback to observe Ebonhold " .. description .. ".")
    end
end

-- Observe the companion's parsed state, not its server-message registrations.
-- Its parser replaces the run table before calling PlayerRunUI.UpdateData,
-- including when the HUD is hidden. Other HUD updates may reuse that table;
-- they must not make cached currency figures look newly received.
function Integration.WatchRunCurrencies(onSnapshot)
    if type(onSnapshot) ~= "function" then
        error("Ashoholic needs a callback to observe Ebonhold run currencies.")
    end

    local companion = ProjectEbonhold
    local service = companion and companion.PlayerRunService
    local runUI = companion and companion.PlayerRunUI
    if not service or type(service.GetCurrentData) ~= "function"
        or not runUI or type(runUI.UpdateData) ~= "function" then
        error("Ashoholic cannot collect run currencies: ProjectEbonhold's run API is unavailable.")
    end

    local lastRunData
    local function Observe()
        local current = service.GetCurrentData()
        if current == nil then
            return
        end
        if type(current) ~= "table" then
            error("Ashoholic received invalid run data from ProjectEbonhold.")
        end
        -- An empty table (or multiplier-only update) is normal during login.
        if current.soulPoints == nil or current.soulShards == nil then
            return
        end
        if current == lastRunData then
            return
        end

        lastRunData = current
        onSnapshot({
            soulAsh = current.soulPoints,
            soulShards = current.soulShards,
            updatedAt = time(),
        })
    end

    hooksecurefunc(runUI, "UpdateData", Observe)
    -- The server may have answered before Ashoholic registered its observer.
    Observe()
end

-- Returns one currency's spendable and banked balances, or nothing when the
-- server did not include that currency.
local function PoolBalances(pools, currency)
    local pool = type(pools) == "table" and pools[currency]
    if type(pool) ~= "table" then
        return nil, nil
    end
    return pool.spendable, pool.banked
end

-- ProjectEbonhold's server messages arrive as addon whispers with this prefix.
-- The companion keeps the prefix in a private variable
-- (vendor/ProjectEbonhold/projectebonhold.lua, line 2), so it is repeated here.
local SERVER_MESSAGE_PREFIX = "AAM0x9"

-- A loadout reply normally arrives within a second of its request. Ashoholic
-- reads loadout replies only for this many seconds after a request, so a stray
-- or late message is never mistaken for fresh balances.
local LOADOUT_REPLY_SECONDS = 30

-- GetTime() of the latest loadout request in this UI session, made by the Soul
-- Ash tree or by Ashoholic. nil means nobody has asked yet. A /reload starts a
-- new UI session for both addons, so this starts again as nil.
local lastLoadoutRequestAt
local watchingLoadoutReplies = false

-- Returns the balance header of a loadout reply, or nil for any other message.
-- ProjectEbonhold's server messages look like this (projectebonhold.lua, in
-- the dispatch function):
--   short: "<message id><TAB><body>"
--   long:  "<message id><TAB>@<4 hex digits><TAB><piece>/<pieces><TAB><part of the body>"
-- A long message is split into numbered pieces (3 hex digits each). The
-- loadout reply's body starts with the balance header, then "_" and the saved
-- loadouts. The header is short, so it is complete in the first piece.
local function ReadLoadoutHeader(message, loadoutMessageId)
    local messageId, rest = string.match(message, "^(%d+)\t(.*)$")
    if not messageId or tonumber(messageId) ~= loadoutMessageId then
        return nil
    end

    local piece, firstPart = string.match(rest, "^@%x%x%x%x\t(%x%x%x)/%x%x%x\t(.*)$")
    if piece then
        if tonumber(piece, 16) ~= 1 then
            return nil
        end
        -- Finding the "_" proves the whole header is inside this first piece.
        return string.match(firstPart, "^([^_]*)_")
    end
    -- A short reply may have no saved loadouts, and then no "_" either.
    return string.match(rest, "^([^_]*)")
end

-- Turns a loadout header into an account-currency snapshot, or returns nil
-- when the header does not have the expected layout. Its fields, in order:
--   selected loadout ID, Soul Ash spendable, Soul Ash banked, permanent Echoes,
--   then (newer servers) spendable/banked pairs for shards, essence, artisan.
-- Older servers send only the first four fields. Any other layout is ignored
-- rather than guessed, because it would mean Ebonhold changed the format.
local function ParseLoadoutBalances(header)
    local fields = {}
    -- The extra "," lets the pattern find the last field like all the others.
    for field in string.gmatch(header .. ",", "([^,]*),") do
        if not string.find(field, "^%d+$") then
            return nil
        end
        table.insert(fields, tonumber(field))
    end
    if #fields ~= 4 and #fields ~= 10 then
        return nil
    end

    local snapshot = {
        ashSpendable = fields[2],
        ashBanked = fields[3],
        updatedAt = time(),
    }
    if #fields == 10 then
        snapshot.shardSpendable, snapshot.shardBanked = fields[5], fields[6]
        snapshot.essenceSpendable, snapshot.essenceBanked = fields[7], fields[8]
        snapshot.artisanSpendable, snapshot.artisanBanked = fields[9], fields[10]
    end
    return snapshot
end

-- Reads the balances in each expected loadout reply. ProjectEbonhold handles
-- that reply in a private function, so Ashoholic reads the same server message
-- with its own event frame. Listening to CHAT_MSG_ADDON does not change or
-- replace any ProjectEbonhold handler (see Rule 5 in Data/Schema.lua).
local function WatchLoadoutReplies(onSnapshot, loadoutMessageId)
    -- The Soul Ash tree calls this public function when it first opens, and
    -- Integration.RequestAccountCurrencies calls it too. Either way, a reply
    -- is now expected.
    hooksecurefunc(ProjectEbonhold, "RequestLoadoutFromServer", function()
        lastLoadoutRequestAt = GetTime()
    end)

    local listener = CreateFrame("Frame")
    listener:RegisterEvent("CHAT_MSG_ADDON")
    listener:SetScript("OnEvent", function(_, _, prefix, message)
        -- Other addons send messages too; ignore everything that is not ours.
        if prefix ~= SERVER_MESSAGE_PREFIX or type(message) ~= "string" then
            return
        end
        if not lastLoadoutRequestAt
            or GetTime() - lastLoadoutRequestAt > LOADOUT_REPLY_SECONDS then
            return
        end

        local header = ReadLoadoutHeader(message, loadoutMessageId)
        local snapshot = header and ParseLoadoutBalances(header)
        if snapshot then
            onSnapshot(snapshot)
        end
    end)
    watchingLoadoutReplies = true
end

-- The Soul Ash tree's bottom bar shows the four spendable amounts in this
-- order (CURRENCY_ORDER in vendor/ProjectEbonhold/modules/skillTree/skillTree.lua).
local TREE_BAR_CURRENCIES = { "ash", "shard", "essence", "artisan" }

-- Reads one amount from the tree's bottom bar, or returns nil when the text
-- does not look exactly as expected. ProjectEbonhold writes each amount as
-- "<icon> |cffFFFFFF12,345|r" (the poolText function in skillTree.lua):
-- an icon, then the number in white with commas between thousands.
-- A minus sign (an overspent amount) or any other layout is not accepted.
local function ReadTreeBarAmount(fontString)
    if type(fontString) ~= "table" or type(fontString.GetText) ~= "function" then
        return nil
    end
    local text = fontString:GetText()
    if type(text) ~= "string" then
        return nil
    end

    local amount = string.match(text, "^|T[^|]+|t |cffFFFFFF([%d,]+)|r$")
    -- Commas may only appear between digits, never at the start or end.
    if not amount or not string.find(amount, "^%d") or not string.find(amount, "%d$") then
        return nil
    end
    return tonumber((string.gsub(amount, ",", "")))
end

-- Builds a snapshot from the tree's bottom bar right after a successful Apply.
-- The server's Apply reply has no numbers: ProjectEbonhold already subtracted
-- the spent amounts locally, so the bar now shows the new spendable balances.
-- Spending never changes banked balances (ProjectEbonhold's own comment in
-- skillTree_service.lua), so those are copied from the latest balances the
-- server sent in this session. Returns nil if anything cannot be read.
local function ReadTreeBarSnapshot(serverSnapshot)
    local treeFrame = _G.skillTreeFrame
    local barTexts = type(treeFrame) == "table" and treeFrame.poolTexts
    if type(barTexts) ~= "table" then
        return nil
    end

    local spendable = {}
    for index, currency in ipairs(TREE_BAR_CURRENCIES) do
        spendable[currency] = ReadTreeBarAmount(barTexts[index])
        if spendable[currency] == nil then
            return nil
        end
    end

    local snapshot = {
        ashSpendable = spendable.ash,
        ashBanked = serverSnapshot.ashBanked,
        updatedAt = time(),
    }
    -- A currency whose banked balance the server did not send stays unknown,
    -- because a spendable amount without its banked pair would be incomplete.
    for index = 2, #TREE_BAR_CURRENCIES do
        local currency = TREE_BAR_CURRENCIES[index]
        local banked = serverSnapshot[currency .. "Banked"]
        if banked ~= nil then
            snapshot[currency .. "Spendable"] = spendable[currency]
            snapshot[currency .. "Banked"] = banked
        end
    end
    return snapshot
end

-- Account balances reach Ashoholic in three ways:
--   1) A server balance update after a balance changes (banking a run,
--      buying a class node). The companion passes it to the public
--      SkillTree.UpdateTotalSoulPoints, which Ashoholic hooks.
--   2) The server's loadout reply that the Soul Ash tree asks for when it
--      first opens, read by WatchLoadoutReplies above.
--   3) A successful Apply in the Soul Ash tree. Its server reply only says
--      "success", so Ashoholic reads the new spendable amounts from the
--      tree's bottom bar (ReadTreeBarSnapshot above).
-- The companion stores the balances only in private variables, so Ashoholic
-- cannot read them later and must observe each one when it happens.
function Integration.WatchAccountCurrencies(onSnapshot)
    if type(onSnapshot) ~= "function" then
        error("Ashoholic needs a callback to observe Ebonhold account currencies.")
    end

    -- Check every API first, so Ashoholic never watches only part of them.
    local companion = ProjectEbonhold
    local skillTree = companion and companion.SkillTree
    if not skillTree or type(skillTree.UpdateTotalSoulPoints) ~= "function"
        or type(skillTree.OnApplyChangesResult) ~= "function" then
        error("Ashoholic cannot collect account currencies: ProjectEbonhold's Soul Ash tree API is unavailable.")
    end
    local messageIds = companion.SS
    if type(companion.RequestLoadoutFromServer) ~= "function"
        or type(messageIds) ~= "table" or type(messageIds.SEND_LOADOUTS) ~= "number" then
        error("Ashoholic cannot collect account currencies: ProjectEbonhold's loadout API is unavailable.")
    end

    -- The latest balances sent by the server in this UI session. An Apply
    -- copies its banked balances. nil until the server has sent any.
    local lastServerSnapshot

    -- These observers run inside ProjectEbonhold's server-message handling.
    -- Report an Ashoholic error normally, but never let it interrupt or look
    -- like an error in ProjectEbonhold's own code.
    local Deliver = ProtectObserver(onSnapshot)

    local function ObserveServerSnapshot(snapshot)
        lastServerSnapshot = snapshot
        Deliver(snapshot)
    end

    hooksecurefunc(skillTree, "UpdateTotalSoulPoints", function(spendable, banked, pools)
        -- Older servers send only the Soul Ash pair. The other currencies
        -- then stay unknown (nil) instead of being guessed as zero.
        local snapshot = {
            ashSpendable = spendable,
            ashBanked = banked,
            updatedAt = time(),
        }
        snapshot.shardSpendable, snapshot.shardBanked = PoolBalances(pools, "shard")
        snapshot.essenceSpendable, snapshot.essenceBanked = PoolBalances(pools, "essence")
        snapshot.artisanSpendable, snapshot.artisanBanked = PoolBalances(pools, "artisan")
        ObserveServerSnapshot(snapshot)
    end)

    WatchLoadoutReplies(ObserveServerSnapshot, messageIds.SEND_LOADOUTS)

    -- ProjectEbonhold calls this with (spellId, success) when the server
    -- answers an Apply. Only a successful Apply changes the balances, and
    -- the bar is read only after it, never while nodes are still being chosen.
    hooksecurefunc(skillTree, "OnApplyChangesResult", function(_, success)
        if success ~= true or not lastServerSnapshot then
            return
        end
        local snapshot = ReadTreeBarSnapshot(lastServerSnapshot)
        if snapshot then
            Deliver(snapshot)
        end
    end)
end

-- Asks the server for the loadout reply that the Soul Ash tree asks for when
-- it first opens, so the account cards can fill in without opening the tree.
-- Returns true when the request was sent and false when it was not needed.
--
-- Safety: besides the balances, that reply resets ProjectEbonhold's tree
-- display and clears unapplied tree choices. The tree always asks for it when
-- it first opens, so Ashoholic asks only while no loadout request has happened
-- in this UI session: the tree has then never been opened and has no
-- unapplied choices to lose. This also limits Ashoholic to one request per
-- session.
function Integration.RequestAccountCurrencies()
    if not watchingLoadoutReplies then
        error("Ashoholic must watch account currencies before requesting them.")
    end
    if lastLoadoutRequestAt then
        return false
    end

    -- The hook in WatchLoadoutReplies records this request as well.
    ProjectEbonhold.RequestLoadoutFromServer()
    return true
end

--[[
 Warband bank gold (account-wide)
 ProjectEbonhold's extended bank receives its updates from ebonhold.dll, which
 calls the global function ExtBank_OnPacket(hex) with every bank update. The
 companion keeps the Warband gold in a private variable, so Ashoholic reads it
 from the same packet with a post-hook. Packets arrive only while the bank is
 used (opening it, moving items, depositing gold), never at login.

 The packet is hexadecimal text: two hex digits per byte, numbers stored
 little-endian (lowest byte first). Its layout (extBank.lua):
     u8 kind, u8 unlockedBags, u8 bagCount
     bagCount x 10 bytes of bag entries     (only when kind == 0, a full snapshot)
     u16 cellCount
     cellCount x 23 bytes of item cells
     tail: u8 store shown
           u64 Warband gold in copper       (only when 8 bytes remain)
           u8 open                          (optional; 1 = the account has
                                             unlocked its Warband bank)
 Only the few bytes needed to find and read the tail are converted; packets
 can be several kilobytes long. Anything unexpected ignores the packet.
]]
local BAG_ENTRY_BYTES = 10
local ITEM_CELL_BYTES = 23
-- Lua numbers count whole copper exactly only below 2^53.
local LARGEST_EXACT_COPPER = 2 ^ 53

-- Read one byte (1 = the first byte) as a number from 0 to 255, or nil when
-- it is past the end or is not two hexadecimal digits.
local function ReadPacketByte(hex, byteIndex)
    local first = byteIndex * 2 - 1
    local digits = string.sub(hex, first, first + 1)
    if not string.match(digits, "^%x%x$") then
        return nil
    end
    return tonumber(digits, 16)
end

-- Read a little-endian unsigned number of byteCount bytes, or nil.
local function ReadPacketNumber(hex, byteIndex, byteCount)
    local value, scale = 0, 1
    for offset = 0, byteCount - 1 do
        local byte = ReadPacketByte(hex, byteIndex + offset)
        if not byte then
            return nil
        end
        value = value + byte * scale
        scale = scale * 256
    end
    return value
end

-- Returns gold (copper) and unlocked (true, false, or nil when the packet has
-- no open byte), or nil when the packet has no readable Warband gold.
local function ReadWarbandTail(hex)
    if type(hex) ~= "string" or #hex % 2 ~= 0 then
        return nil
    end
    local packetBytes = #hex / 2
    if packetBytes < 3 then
        return nil
    end
    local kind = ReadPacketByte(hex, 1)
    local bagCount = ReadPacketByte(hex, 3)
    if not kind or not ReadPacketByte(hex, 2) or not bagCount then
        return nil
    end

    -- Skip the bag entries (full snapshots only) and the item cells. Their
    -- contents are not needed, only their size.
    local position = 4
    if kind == 0 then
        position = position + bagCount * BAG_ENTRY_BYTES
    end
    local cellCount = ReadPacketNumber(hex, position, 2)
    if not cellCount then
        return nil
    end
    position = position + 2 + cellCount * ITEM_CELL_BYTES

    -- The tail starts with the store byte. Without it, or without the eight
    -- gold bytes after it (an older server), the packet has no gold to read.
    if not ReadPacketByte(hex, position) then
        return nil
    end
    position = position + 1
    if position + 7 > packetBytes then
        return nil
    end
    local low = ReadPacketNumber(hex, position, 4)
    local high = ReadPacketNumber(hex, position + 4, 4)
    if not low or not high then
        return nil
    end
    local gold = low + high * 4294967296
    if gold >= LARGEST_EXACT_COPPER then
        return nil
    end
    position = position + 8

    local unlocked
    if position <= packetBytes then
        local open = ReadPacketByte(hex, position)
        if not open then
            return nil
        end
        unlocked = open == 1
    end
    return gold, unlocked
end

-- Calls onSnapshot({ gold, unlocked, updatedAt }) for each bank packet that
-- carries Warband gold. Returns false (and watches nothing) when the
-- companion has no extended bank: the Warband group is optional.
function Integration.WatchWarbandBank(onSnapshot)
    RequireObserver(onSnapshot, "Warband bank gold")
    if type(_G.ExtBank_OnPacket) ~= "function" then
        return false
    end

    -- ProtectObserver keeps an Ashoholic error from interrupting the bank
    -- update that ebonhold.dll is delivering to the companion.
    hooksecurefunc("ExtBank_OnPacket", ProtectObserver(function(hex)
        local gold, unlocked = ReadWarbandTail(hex)
        if not gold then
            return
        end
        onSnapshot({ gold = gold, unlocked = unlocked, updatedAt = time() })
    end))
    return true
end

-- These constants describe the companion's current display rules. Collectors
-- pass a copy to Data; no UI file needs to read ProjectEbonhold itself.
function Integration.GetProgressionRules()
    local companion = ProjectEbonhold
    local prestige = companion and companion.PrestigeService
    local tiers = companion and companion.TormentTierData
    if not prestige or type(prestige.GetGateThreshold) ~= "function"
        or type(tiers) ~= "table" then
        error("Ashoholic cannot read ProjectEbonhold's progression rules.")
    end

    local names = {}
    for tier, definition in ipairs(tiers) do
        names[tier] = definition.name
    end
    return {
        prestigeGate = prestige.GetGateThreshold(),
        tormentLadderTop = companion.TormentLadderTop,
        tierNames = names,
    }
end

-- The companion owns the raid names, real encounter IDs and loot metadata.
-- Data/Encounters.lua builds its own tree from these values without changing
-- the companion's catalogue.
function Integration.GetRaidCatalog()
    local catalog = ProjectEbonhold and ProjectEbonhold.RaidLockoutData
    if type(catalog) ~= "table" or #catalog == 0 then
        error("Ashoholic cannot read ProjectEbonhold's raid catalogue.")
    end
    return catalog
end

-- True for whole numbers 1, 2, 3, ... (never 0, negative, fractional or
-- infinite). Server counts and IDs must pass this before they are saved.
local function IsPositiveInteger(value)
    return type(value) == "number" and value > 0 and value < math.huge
        and value == math.floor(value)
end

-- True for whole numbers 0, 1, 2, ... A count of zero is a real value here.
local function IsNonNegativeInteger(value)
    return value == 0 or IsPositiveInteger(value)
end

-- The weekly reward rail on the Call Board. Every contract claimed this board
-- week moves the rail up; each step pays its elixirs when it is reached. The
-- server sends the steps, so they are its numbers, not Ashoholic's.
local RAIL_MAX_STEPS = 10 -- the companion's board shows at most 10 steps
local RAIL_MAX_ITEMS = 4 -- items kept per step; more never fit the display
local RAIL_NAME_BYTES = 64 -- longest item name Data/Store.lua accepts

-- English names of the rail's current elixirs, matching the companion's own
-- fallback list (callboard_ui.lua). WoW's item cache can be empty for a new
-- item until something asks the server about it, so these names fill the gap.
local RAIL_ITEM_NAMES = {
    [600940] = "Elixir of Ashes",
    [600941] = "Elixir of Shards",
    [600944] = "Elixir of Memories",
    [600945] = "Elixir of Renewal",
}

-- Shorten text to at most maxBytes bytes without cutting a multi-byte
-- (UTF-8) letter in half, such as an accented letter in a translated name.
local function ShortenText(text, maxBytes)
    if #text <= maxBytes then
        return text
    end
    local cut = maxBytes
    -- Bytes 128-191 continue the letter before them. Step back until the
    -- next kept byte would start a new letter.
    while cut > 0 do
        local nextByte = string.byte(text, cut + 1)
        if nextByte < 128 or nextByte >= 192 then
            break
        end
        cut = cut - 1
    end
    return string.sub(text, 1, cut)
end

-- Resolve a rail item's name now, while the game client is available. The UI
-- may not call game APIs, so it can only show a name saved here. Returns nil
-- when no name is known; the item ID is still saved.
local function RailItemName(itemId)
    -- GetItemInfo returns nil while the item is not in WoW's item cache.
    local name = GetItemInfo(itemId)
    if type(name) ~= "string" or name == "" then
        name = RAIL_ITEM_NAMES[itemId]
        -- The companion translates its fallback names with ProjectEbonhold.L.
        -- That table returns the English text for a missing translation, but
        -- an unexpected result must still never break the Call Board.
        local translations = ProjectEbonhold and ProjectEbonhold.L
        if name and type(translations) == "table" then
            local ok, translated = pcall(function() return translations[name] end)
            if ok and type(translated) == "string" and translated ~= "" then
                name = translated
            end
        end
    end
    if not name then
        return nil
    end
    name = ShortenText(name, RAIL_NAME_BYTES)
    if name == "" then
        return nil
    end
    return name
end

-- Copy the companion's parsed rail, { { count = n, entries = { itemId, ... } }, ... },
-- into Ashoholic's saved shape, { { count = n, items = { { id, name }, ... } }, ... }.
-- Never save a partial rail: its last step is used to decide completion.
-- A second return value reports a rail that cannot fit the saved contract.
local function IsDenseArray(values, length)
    for key in pairs(values) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
            return false
        end
    end
    for index = 1, length do
        if values[index] == nil then return false end
    end
    return true
end

local function CopyRail(rail)
    if rail == nil then
        return nil
    end
    if type(rail) ~= "table" or #rail < 1 or #rail > RAIL_MAX_STEPS
        or not IsDenseArray(rail, #rail) then
        return nil, true
    end
    local steps = {}
    for position, step in ipairs(rail) do
        if type(step) ~= "table" or not IsPositiveInteger(step.count)
            or type(step.entries) ~= "table" or #step.entries < 1
            or #step.entries > RAIL_MAX_ITEMS or not IsDenseArray(step.entries, #step.entries) then
            return nil, true
        end
        local items = {}
        for _, itemId in ipairs(step.entries) do
            if not IsPositiveInteger(itemId) then
                return nil, true
            end
            items[#items + 1] = { id = itemId, name = RailItemName(itemId) }
        end
        steps[#steps + 1] = { count = step.count, items = items, position = position }
    end

    -- The companion already sorts by count. Sort again so the saved rail
    -- always climbs; equal counts keep the companion's order.
    table.sort(steps, function(left, right)
        if left.count ~= right.count then
            return left.count < right.count
        end
        return left.position < right.position
    end)
    local saved = {}
    for index = 1, #steps do
        saved[index] = { count = steps[index].count, items = steps[index].items }
    end
    return saved
end

-- Call Board replies are observed through the companion's listener. The
-- countdowns are converted immediately to real-clock times; GetTime() is
-- never saved and a disabled board is not mistaken for an empty board.
--
-- The companion turns a missing number into 0. Ashoholic therefore saves a
-- quest's category and claim cost only when they are positive, and saves the
-- weekly claim count only together with a rail from a server that sends one.
function Integration.WatchActivities(onSnapshot)
    RequireObserver(onSnapshot, "Call Board")
    local boardService = ProjectEbonhold and ProjectEbonhold.Callboard
    if not boardService or type(boardService.OnChanged) ~= "function" then
        error("Ashoholic cannot collect activities: ProjectEbonhold's Call Board API is unavailable.")
    end
    local cadenceNames = { [0] = "daily", [1] = "weekly", [2] = "once" }

    local function Observe(board)
        if board == nil then
            return
        end
        if type(board) ~= "table" or type(board.quests) ~= "table" then
            error("Ashoholic received an invalid Call Board.")
        end
        if type(board.receivedAt) ~= "number"
            or type(board.dailyResetIn) ~= "number" or board.dailyResetIn < 0
            or type(board.weeklyResetIn) ~= "number" or board.weeklyResetIn < 0 then
            error("Ashoholic received invalid Call Board reset timers.")
        end
        local now, elapsed = time(), GetTime() - board.receivedAt
        if elapsed < 0 then error("Ashoholic received an invalid Call Board observation time.") end
        -- Callboard.board can predate our listener. Convert its session clock
        -- back to an approximate wall-clock observation instead of making an
        -- old cached board look freshly received.
        local observedAt = now - math.floor(elapsed)
        local snapshot = {
            cacheProgress = board.cacheProgress,
            cacheRequired = board.cacheRequired,
            cachesOpened = board.cachesOpened,
            dailyResetAt = observedAt + math.floor(board.dailyResetIn),
            weeklyResetAt = observedAt + math.floor(board.weeklyResetIn),
            quests = {},
            updatedAt = observedAt,
        }
        -- Zero is the companion's placeholder when this header field is not
        -- present. A positive value is an actual Call Board observation.
        if type(board.equippedIlvl) == "number" and board.equippedIlvl > 0 then
            snapshot.equippedItemLevel = board.equippedIlvl
        end
        local skipped = 0
        for _, quest in ipairs(board.quests) do
            -- Skip only an activity Ashoholic cannot identify: a missing ID,
            -- an unknown cadence (perhaps from a newer server) or a repeated
            -- ID, where the first copy is kept. The rest of the board is
            -- still a valid observation.
            if type(quest) == "table" and IsPositiveInteger(quest.questId)
                and cadenceNames[quest.cadence] and not snapshot.quests[quest.questId] then
                local saved = {
                    title = quest.title,
                    cadence = cadenceNames[quest.cadence],
                    done = quest.done,
                    max = quest.max,
                    state = quest.state,
                    accountWide = quest.accountWide,
                    rewards = {
                        ash = quest.ashes,
                        shards = quest.shards,
                        copper = quest.copper,
                        artisan = quest.artisan,
                        orbs = quest.orbs,
                    },
                }
                -- The category ID (for example 8 = Frostveil, the seasonal
                -- winter-event dailies). 0 means the server sent none.
                if IsPositiveInteger(quest.category) then
                    saved.category = quest.category
                end
                -- Copper that claiming TAKES. 0 means the claim is free,
                -- so only a real price is saved.
                if IsPositiveInteger(quest.cost) then
                    saved.cost = quest.cost
                end
                snapshot.quests[quest.questId] = saved
            else
                skipped = skipped + 1
            end
        end
        if skipped > 0 then
            print("|cffffca63Ashoholic:|r Skipped " .. skipped
                .. " unrecognized or duplicate Call Board activities.")
        end
        -- The rail and its claim count belong to this character's board.
        -- Older servers send no rail; their claim count is the companion's
        -- placeholder 0, so it is saved only together with a rail.
        local invalidRail
        snapshot.rail, invalidRail = CopyRail(board.rail)
        if invalidRail then
            print("|cffffca63Ashoholic:|r The Call Board reward rail is incomplete or exceeds supported limits; it was not saved.")
        end
        if snapshot.rail and IsNonNegativeInteger(board.weeklyClaims) then
            snapshot.weeklyClaims = board.weeklyClaims
        end
        onSnapshot(snapshot)
    end

    boardService.OnChanged(ProtectObserver(function(event, board)
        if event == "board" then Observe(board) end
    end))
    if boardService.board then Observe(boardService.board) end
end

-- A Champion leaderboard for another class does not describe this character.
-- Practice results never update the saved record. A result does not carry a
-- season, so do not combine it with an older leaderboard's season or rank.
function Integration.WatchTrials(onSnapshot)
    RequireObserver(onSnapshot, "Trials")
    local trials = ProjectEbonhold and ProjectEbonhold.Trials
    if not trials or type(trials.OnChanged) ~= "function"
        or type(trials.MyClassId) ~= "function" or type(trials.TYPE) ~= "table" then
        error("Ashoholic cannot collect Trials: ProjectEbonhold's Trials API is unavailable.")
    end
    local function Group(trial)
        if trial == trials.TYPE.CHAMPION then return "champion" end
        if trial == trials.TYPE.CRUSADER then return "crusader" end
        return nil
    end
    local function ObserveBoard(board)
        if type(board) ~= "table" then return end
        local group = Group(board.trial)
        if not group then return end
        if group == "champion" then
            local classId = trials.MyClassId()
            if classId == 0 or board.classFilter ~= classId then return end
        end
        local snapshot = {
            best = board.myBest,
            rank = board.myRank,
            total = board.total,
            season = board.season,
            seasonName = board.seasonName,
            updatedAt = time(),
        }
        if group == "crusader" and type(board.rows) == "table" and board.myRank > 0 then
            for _, row in ipairs(board.rows) do
                -- The companion defaults a missing board team size to 1, so
                -- only larger values are certain here. A result reply has a
                -- different default and can also establish a solo run.
                if row.rank == board.myRank and row.score == board.myBest
                    and type(row.teamSize) == "number" and row.teamSize > 1 and row.teamSize <= 5 then
                    snapshot.teamSize = row.teamSize
                    break
                end
            end
        end
        onSnapshot(group, snapshot)
    end
    local function ObserveResult(result)
        if type(result) ~= "table" or result.startWave > 1 then return end
        local group = Group(result.trial)
        if not group then return end
        local best = result.personalBest and result.score or result.previousBest
        local snapshot = { best = best, updatedAt = time() }
        if result.personalBest then
            snapshot.rank, snapshot.total = result.rank, result.total
            if group == "crusader" and type(result.teamSize) == "number"
                and result.teamSize >= 1 and result.teamSize <= 5 then
                snapshot.teamSize = result.teamSize
            end
        end
        onSnapshot(group, snapshot)
    end

    trials.OnChanged(ProtectObserver(function(event, payload)
        if event == "board" then
            ObserveBoard(payload)
        elseif event == "result" then
            ObserveResult(payload)
        end
    end))
    -- Cached Trial boards have no reception time; wait for a new event rather
    -- than assigning an old board a fresh timestamp.
end

local function ParseRaidLoot(body)
    local observedAt = time()
    local lockedUntil, seen = {}, {}

    -- Both an empty body and one trailing semicolon are valid complete replies.
    if string.sub(body, 1, 1) == ";" or string.find(body, ";;", 1, true) then
        error("Ashoholic received an invalid raid loot reply.")
    end
    if string.sub(body, -1) == ";" then
        body = string.sub(body, 1, -2)
    end
    if body ~= "" then
        for entry in string.gmatch(body, "[^;]+") do
            local rawId, rawSeconds = string.match(entry, "^(%d+):(%d+)$")
            if not rawId or not rawSeconds then
                error("Ashoholic received an invalid raid loot entry.")
            end
            local bossId, seconds = tonumber(rawId), tonumber(rawSeconds)
            if not bossId or bossId <= 0 or bossId >= math.huge
                or not seconds or seconds >= math.huge or seen[bossId] then
                error("Ashoholic received an invalid raid loot entry.")
            end
            seen[bossId] = true
            if seconds > 0 then
                local endsAt = observedAt + seconds
                if endsAt >= math.huge then
                    error("Ashoholic received an invalid raid loot reset time.")
                end
                lockedUntil[bossId] = endsAt
            end
        end
    end
    return { lockedUntil = lockedUntil, updatedAt = observedAt }
end

-- A raid reply can exceed one addon message. Assemble every numbered piece
-- before replacing a saved snapshot, just as the companion's dispatcher does.
-- Incomplete or unrecognized replies never turn Unknown into Available.
function Integration.WatchRaidLoot(onSnapshot)
    RequireObserver(onSnapshot, "raid loot")
    local messageIds = ProjectEbonhold and ProjectEbonhold.SS
    if type(messageIds) ~= "table" or type(messageIds.SEND_RAID_LOOT_LOCKOUTS) ~= "number" then
        error("Ashoholic cannot collect raid loot: ProjectEbonhold's message ID is unavailable.")
    end

    local inflight = {}
    local nextSequence, latestAppliedSequence = 0, 0
    local function ApplyReply(body, sequence)
        -- An older multi-part update can finish after a newer complete one.
        -- It must not replace the newer character snapshot.
        if sequence <= latestAppliedSequence then
            return
        end
        local snapshot = ParseRaidLoot(body)
        latestAppliedSequence = sequence
        onSnapshot(snapshot)
    end
    local listener = CreateFrame("Frame")
    listener:RegisterEvent("CHAT_MSG_ADDON")
    listener:SetScript("OnEvent", ProtectObserver(function(_, _, prefix, message)
        if prefix ~= SERVER_MESSAGE_PREFIX or type(message) ~= "string" then
            return
        end
        local rawId, body = string.match(message, "^(%d+)\t(.*)$")
        if not rawId or tonumber(rawId) ~= messageIds.SEND_RAID_LOOT_LOCKOUTS then
            return
        end

        local now = GetTime()
        for key, record in pairs(inflight) do
            if now - record.startedAt > 15 then
                inflight[key] = nil
                print("|cffffca63Ashoholic:|r An incomplete raid loot update expired; waiting for another update.")
            end
        end

        if string.sub(body, 1, 1) ~= "@" then
            nextSequence = nextSequence + 1
            ApplyReply(body, nextSequence)
            return
        end

        local messageKey, rawIndex, rawTotal, part = string.match(
            body, "^@(%x%x%x%x)\t(%x%x%x)/(%x%x%x)\t(.*)$"
        )
        if not messageKey then
            error("Ashoholic received an invalid chunked raid loot reply.")
        end
        local index, total = tonumber(rawIndex, 16), tonumber(rawTotal, 16)
        if total < 1 or index < 1 or index > total then
            error("Ashoholic received an invalid raid loot chunk number.")
        end
        messageKey = string.upper(messageKey)
        local record = inflight[messageKey]
        if not record then
            nextSequence = nextSequence + 1
            record = { total = total, received = 0, parts = {}, startedAt = now, sequence = nextSequence }
            inflight[messageKey] = record
        elseif record.total ~= total then
            inflight[messageKey] = nil
            error("Ashoholic received conflicting raid loot chunks.")
        end
        if record.parts[index] and record.parts[index] ~= part then
            inflight[messageKey] = nil
            error("Ashoholic received conflicting copies of a raid loot chunk.")
        end
        if not record.parts[index] then
            record.parts[index] = part
            record.received = record.received + 1
        end
        if record.received == record.total then
            inflight[messageKey] = nil
            ApplyReply(table.concat(record.parts, "", 1, record.total), record.sequence)
        end
    end))
end

-- SEND_PRESTIGE_DATA is a small, unchunked reply:
-- count;gateProgress[;oldBonus[;pendingShards;pendingEssence]].
-- Read complete replies only. A Prestige result updates the companion's count
-- before its gate/reward, and old replies leave GetPendingEssence at a default
-- zero; neither case is a complete, known reward snapshot.
local function ReadPrestigeReply(message, expectedId)
    local messageId, body = string.match(message, "^(%d+)\t(.*)$")
    if tonumber(messageId) ~= expectedId then
        return nil
    end
    local fields = {}
    for field in string.gmatch(body .. ";", "([^;]*);") do
        table.insert(fields, field)
    end
    if #fields ~= 2 and #fields ~= 3 and #fields ~= 5 then
        return nil
    end
    if not string.match(fields[1], "^%d+$") or not string.match(fields[2], "^%d+$") then
        return nil
    end
    if #fields >= 3 and not string.match(fields[3], "^%-?%d+%.?%d*$") then
        return nil
    end
    local snapshot = {
        count = tonumber(fields[1]),
        gateProgress = tonumber(fields[2]),
        updatedAt = time(),
    }
    if #fields == 5 then
        if not string.match(fields[4], "^%d+$") or not string.match(fields[5], "^%d+$") then
            return nil
        end
        snapshot.pendingShards = tonumber(fields[4])
        snapshot.pendingEssence = tonumber(fields[5])
    end
    return snapshot
end

function Integration.WatchPrestige(onSnapshot)
    RequireObserver(onSnapshot, "Prestige")
    local messageIds = ProjectEbonhold and ProjectEbonhold.SS
    if type(messageIds) ~= "table" or type(messageIds.SEND_PRESTIGE_DATA) ~= "number" then
        error("Ashoholic cannot collect Prestige: ProjectEbonhold's message ID is unavailable.")
    end

    -- Install during addon loading, before the companion's login request.
    -- This separate listener never registers or replaces a companion handler.
    local listener = CreateFrame("Frame")
    listener:RegisterEvent("CHAT_MSG_ADDON")
    listener:SetScript("OnEvent", ProtectObserver(function(_, _, prefix, message)
        if prefix ~= SERVER_MESSAGE_PREFIX or type(message) ~= "string" then
            return
        end
        local snapshot = ReadPrestigeReply(message, messageIds.SEND_PRESTIGE_DATA)
        if snapshot then
            onSnapshot(snapshot)
        end
    end))
end

function Integration.WatchTorment(onSnapshot)
    RequireObserver(onSnapshot, "Torment")
    local companion = ProjectEbonhold
    local service = companion and companion.HardmodeService
    local hardmodeUI = companion and companion.HardmodeUI
    if not service or not hardmodeUI or type(hardmodeUI.Refresh) ~= "function"
        or type(companion.TormentTierData) ~= "table" then
        error("Ashoholic cannot collect Torment: ProjectEbonhold's Torment API is unavailable.")
    end
    for _, name in ipairs({
        "IsDifficultyKnown", "GetCurrentDifficulty", "IsTierUnlocked",
        "GetSoulAshRequirement", "IsCommittedSoulAshesKnown",
    }) do
        if type(service[name]) ~= "function" then
            error("Ashoholic cannot collect Torment: missing HardmodeService." .. name .. ".")
        end
    end

    local loggedIn = false
    local previous
    local function Observe(force)
        if not loggedIn or not service.IsDifficultyKnown() then
            return
        end

        local unlocked = {}
        for tier = 1, #companion.TormentTierData do
            -- Current realms use achievements only. If an Ash gate returns,
            -- do not mistake the login placeholder pool for a real zero.
            if service.GetSoulAshRequirement(tier) > 0
                and not service.IsCommittedSoulAshesKnown() then
                return
            end
            if service.IsTierUnlocked(tier) then
                unlocked[tier] = true
            end
        end

        local currentTier = service.GetCurrentDifficulty()
        local changed = not previous or currentTier ~= previous.currentTier
        if previous then
            for tier = 1, #companion.TormentTierData do
                if unlocked[tier] ~= previous.unlockedTiers[tier] then
                    changed = true
                end
            end
        end
        if not changed and not force then
            return
        end

        previous = { currentTier = currentTier, unlockedTiers = unlocked, updatedAt = time() }
        onSnapshot(previous)
    end

    hooksecurefunc(hardmodeUI, "Refresh", ProtectObserver(function()
        Observe(false)
    end))
    local listener = CreateFrame("Frame")
    listener:RegisterEvent("PLAYER_LOGIN")
    listener:RegisterEvent("ACHIEVEMENT_EARNED")
    listener:SetScript("OnEvent", ProtectObserver(function(self, event)
        if event == "PLAYER_LOGIN" then
            loggedIn = true
            self:UnregisterEvent("PLAYER_LOGIN")
        end
        Observe(event == "ACHIEVEMENT_EARNED")
    end))
end

function Integration.WatchContracts(onSnapshot)
    RequireObserver(onSnapshot, "offerings and Soul Anchor")
    local companion = ProjectEbonhold
    local contracts = companion and companion.Contracts
    local runUI = companion and companion.PlayerRunUI
    if not contracts or not runUI or type(runUI.UpdateBracket) ~= "function" then
        error("Ashoholic cannot collect offerings: ProjectEbonhold's Contracts API is unavailable.")
    end

    local lastList
    local Observe = ProtectObserver(function()
        if not contracts.received then
            return
        end
        if type(contracts.list) ~= "table" then
            error("Ashoholic received an invalid contract list from ProjectEbonhold.")
        end
        if contracts.list == lastList then
            return
        end
        lastList = contracts.list
        onSnapshot({
            offeringBonusPct = contracts.gauge,
            offeringsUsed = contracts.used,
            offeringsMax = contracts.max,
            anchorState = contracts.anchorState,
            anchorPlace = contracts.anchorPlace,
            updatedAt = time(),
        })
    end)

    -- CT.OnData was registered as a function value, so hooking that table
    -- field would miss the stored handler. The handler always calls the public
    -- UpdateBracket after parsing; the timer calls it too, with the same list.
    hooksecurefunc(runUI, "UpdateBracket", Observe)
    Observe()
end

function Integration.WatchEchoBuild(onSnapshot)
    RequireObserver(onSnapshot, "the active Echo build")
    local companion = ProjectEbonhold
    local service = companion and companion.PerkService
    local perkUI = companion and companion.PerkUI
    if not service or type(service.GetServerBuildSlots) ~= "function"
        or type(service.GetServerActiveSlot) ~= "function"
        or type(service.AreServerBuildSlotsEnabled) ~= "function"
        or not perkUI or type(perkUI.RefreshLoadoutHighlights) ~= "function" then
        error("Ashoholic cannot collect Echo builds: ProjectEbonhold's loadout API is unavailable.")
    end

    local lastSlots, lastSlot, lastEnabled
    local Observe = ProtectObserver(function()
        local slots = service.GetServerBuildSlots()
        -- nil is the loading state, including the active-slot login push that
        -- causes the companion to request the full slots for the first time.
        if slots == nil then
            return
        end
        if type(slots) ~= "table" then
            error("Ashoholic received invalid Echo loadouts from ProjectEbonhold.")
        end
        local enabled = service.AreServerBuildSlotsEnabled()
        local activeSlot = service.GetServerActiveSlot()
        if slots == lastSlots and activeSlot == lastSlot and enabled == lastEnabled then
            return
        end

        local snapshot = { enabled = enabled, updatedAt = time() }
        if enabled then
            local build = slots[activeSlot]
            if not build or not build.verified then
                return
            end
            snapshot.slot = activeSlot
            snapshot.name = build.name
        end
        lastSlots, lastSlot, lastEnabled = slots, activeSlot, enabled
        onSnapshot(snapshot)
    end)

    hooksecurefunc(perkUI, "RefreshLoadoutHighlights", Observe)
    Observe()
end
