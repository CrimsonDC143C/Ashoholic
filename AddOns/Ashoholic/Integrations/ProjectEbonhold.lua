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
