local addonName = ...
local addon = _G[addonName]

addon.Integrations = addon.Integrations or {}
addon.Integrations.ProjectEbonhold = addon.Integrations.ProjectEbonhold or {}

local Integration = addon.Integrations.ProjectEbonhold

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
    local function Deliver(snapshot)
        local ok, problem = pcall(onSnapshot, snapshot)
        if not ok then
            geterrorhandler()(problem)
        end
    end

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
