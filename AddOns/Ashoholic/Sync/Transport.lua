-- Explicit, trusted character-to-character sharing. This uses a separate
-- addon-message prefix; it never replaces or sends Ebonhold server requests.
local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local Sync = addon.Sync
local Codec = Sync and Sync.Codec
if not Data or not Codec then error("Ashoholic sync loaded before its data or codec.") end

-- Version 2 uses the compact wire text from Codec.EncodeWire. A new prefix
-- keeps an older installation from misreading the new chunks.
local PREFIX = "ASHO_SYNC2"
-- An addon message holds 254 characters including the prefix. A data header
-- ("D:" .. id .. ":" .. index .. ":" .. total .. ":") uses at most 31.
local PART_SIZE = 200
local MAX_ENCODED = Codec.MAX_WIRE_BYTES
local MAX_PARTS = math.ceil(MAX_ENCODED / (PART_SIZE - 2))
local SEND_INTERVAL = 0.30
local TIMEOUT = 900
local outgoing, incoming, lastRequest, warned = {}, {}, {}, {}
local awaiting, requests = {}, {}
local ready, elapsed = false, 0
local nextTransferId = 0
local frame = CreateFrame("Frame")

local function Say(message)
    print("|cffffca63Ashoholic sync:|r " .. message)
end

-- A peer is identified by its character and realm, never by a supplied
-- account label. Missing realm means this character's current realm.
local function NormalizePeer(input)
    if type(input) ~= "string" then error("Enter a character name to sync.") end
    local target = string.match(input, "^%s*(.-)%s*$")
    if target == "" or #target > 120 or string.find(target, "[%c|:]") then
        error("Use a character name, optionally followed by -Realm.")
    end
    local name, realm = string.match(target, "^([^%-]+)%-(.+)$")
    if name then
        realm = string.gsub(realm, "%s+", "")
        target = name .. "-" .. realm
    else
        name, realm = target, GetRealmName()
    end
    if string.find(name, "[%s%-]") or type(realm) ~= "string" or realm == "" then
        error("Use a character name, optionally followed by -Realm.")
    end
    realm = string.gsub(realm, "%s+", "")
    local currentRealm = string.gsub(GetRealmName(), "%s+", "")
    if string.lower(realm) == string.lower(currentRealm) then
        -- WotLK whispers use bare names on this realm. Keeping an optional
        -- -Realm suffix in a saved target can make only one direction fail.
        target = name
    end
    return string.lower(name .. "-" .. realm), target
end

function Sync.Trust(name)
    local key, target = NormalizePeer(name)
    local selfKey = NormalizePeer(UnitName("player"))
    if key == selfKey then error("You cannot add your current character as a sync peer.") end
    Data.SetTrustedPeer(key, target)
    Say("Trusted " .. target .. ". Add this character on the other account too.")
end

function Sync.Untrust(name)
    local key, target = NormalizePeer(name)
    if not Data.GetTrustedPeers()[key] then error(target .. " is not a trusted peer.") end
    Data.SetTrustedPeer(key, nil)
    Say("Removed " .. target .. " from trusted peers.")
end

function Sync.ListPeers()
    local names = {}
    for _, name in pairs(Data.GetTrustedPeers()) do names[#names + 1] = name end
    table.sort(names)
    Say(#names > 0 and ("Trusted peers: " .. table.concat(names, ", ")) or "No trusted peers yet.")
end

-- Split wire text into message-sized parts. An escape such as "~7c" is three
-- characters, so a part never ends in the middle of one.
local function SplitWire(wire)
    local parts, position = {}, 1
    while position <= #wire do
        local finish = math.min(position + PART_SIZE - 1, #wire)
        if string.sub(wire, finish, finish) == "~" then
            finish = finish - 1
        elseif string.sub(wire, finish - 1, finish - 1) == "~" then
            finish = finish - 2
        end
        parts[#parts + 1] = string.sub(wire, position, finish)
        position = finish + 1
    end
    return parts
end

local function EnqueueData(target)
    if #outgoing >= 32 then error("Too many account transfers are already queued.") end
    local parts = SplitWire(Codec.EncodeWire(Data.ExportCurrentAccount()))
    if #parts > MAX_PARTS then error("This account snapshot is too large to send.") end
    nextTransferId = nextTransferId + 1
    local id = tostring(time()) .. string.format("%08x", nextTransferId)
    outgoing[#outgoing + 1] = { target = target, parts = parts, id = id, total = #parts, index = 1 }
end

function Sync.GetStatus()
    local lines = {}
    for _, record in pairs(incoming) do
        lines[#lines + 1] = "Receiving " .. record.sender .. ": " .. record.count .. "/" .. record.total .. " chunks"
    end
    local job = outgoing[1]
    if job then
        lines[#lines + 1] = job.parts and ("Sending to " .. job.target .. ": " .. (job.index - 1) .. "/" .. job.total .. " chunks")
            or ("Queued message to " .. job.target)
    end
    for _, request in pairs(requests) do lines[#lines + 1] = "Waiting for " .. request.target end
    for _, transfer in pairs(awaiting) do lines[#lines + 1] = "Waiting for confirmation from " .. transfer.target end
    if #lines == 0 then return "Idle. Receipt and import confirmations are reported in chat." end
    return table.concat(lines, "\n", 1, math.min(3, #lines))
end

function Sync.Start(name)
    if not ready then error("Sync is not ready until login finishes.") end
    local key, target = NormalizePeer(name)
    local trusted = Data.GetTrustedPeers()[key]
    if not trusted then error(target .. " is not trusted. Add it first with /ash sync trust " .. target .. ".") end
    local _, destination = NormalizePeer(trusted)
    if requests[key] then
        Say("Already waiting for " .. destination .. ". Transfers can take several minutes.")
        return
    end
    for _, job in ipairs(outgoing) do
        if NormalizePeer(job.target) == key and (job.request or job.parts) then
            Say("An exchange with " .. destination .. " is already queued.")
            return
        end
    end
    if #outgoing > 30 then error("Too many account transfers are already queued.") end
    -- Prepare the snapshot before queuing the request, so an encoding error
    -- cannot start a one-sided transfer.
    EnqueueData(destination)
    table.insert(outgoing, 1, { target = destination, request = true })
    Say("Exchanging snapshots with " .. destination .. ". Both characters must trust each other; larger accounts take several minutes.")
end

function Sync.StartAll()
    local names = {}
    for _, name in pairs(Data.GetTrustedPeers()) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then error("No trusted peers. Use /ash sync trust Character first.") end
    for _, name in ipairs(names) do Sync.Start(name) end
end

local function SendNext()
    local job = outgoing[1]
    if not job then return end
    if not Data.GetTrustedPeers()[NormalizePeer(job.target)] then
        Say("Cancelled queued transfer to " .. job.target .. ": trust was removed.")
        table.remove(outgoing, 1)
        return
    end
    local message
    if job.message then
        message = job.message
    elseif job.request then
        message = "Q:1"
    else
        message = "D:" .. job.id .. ":" .. job.index .. ":" .. job.total .. ":" .. job.parts[job.index]
    end
    local ok, result = pcall(SendAddonMessage, PREFIX, message, "WHISPER", job.target)
    if not ok or result == false then
        Say("Could not send to " .. job.target .. ": " .. tostring(result))
        table.remove(outgoing, 1)
        return
    end
    if job.request then
        local key = NormalizePeer(job.target)
        requests[key] = { target = job.target, startedAt = GetTime() }
        table.remove(outgoing, 1)
    elseif job.message then
        table.remove(outgoing, 1)
    else
        job.index = job.index + 1
        if job.index > job.total then
            table.remove(outgoing, 1)
            awaiting[job.id] = { key = NormalizePeer(job.target), target = job.target, startedAt = GetTime() }
            Say("Finished sending to " .. job.target .. "; waiting for confirmation.")
        end
    end
end

local function ReceiveData(senderKey, sender, message)
    local id, rawIndex, rawTotal, part = string.match(message, "^D:(%x+):(%d+):(%d+):(.+)$")
    if not id or #id > 24 or #part > PART_SIZE then error("Invalid sync chunk.") end
    local index, total = tonumber(rawIndex), tonumber(rawTotal)
    if not index or not total or total < 1 or total > MAX_PARTS or index < 1 or index > total then
        error("Invalid sync chunk count.")
    end
    local key = senderKey .. ":" .. id
    local record = incoming[key]
    if not record then
        local active = 0
        for _ in pairs(incoming) do active = active + 1 end
        if active >= 8 then error("Too many incomplete account transfers.") end
        record = { sender = sender, total = total, parts = {}, count = 0, bytes = 0, startedAt = GetTime() }
        incoming[key] = record
        Say("Receiving " .. total .. " chunks from " .. sender .. ".")
    elseif record.total ~= total then
        incoming[key] = nil
        error("Conflicting sync chunk counts.")
    end
    if record.parts[index] and record.parts[index] ~= part then
        incoming[key] = nil
        error("Conflicting copies of a sync chunk.")
    end
    if not record.parts[index] then
        record.parts[index] = part
        record.count = record.count + 1
        record.bytes = record.bytes + #part
    end
    if record.bytes > MAX_ENCODED then
        incoming[key] = nil
        error("Incoming account snapshot is too large.")
    end
    if record.count == record.total then
        incoming[key] = nil
        requests[senderKey] = nil
        local ok, changed = pcall(function()
            local packet = Codec.DecodeWire(table.concat(record.parts, "", 1, record.total))
            if packet.accountId == Data.GetLocalAccountId() then
                error("The other client has the same saved account ID. Copied SavedVariables cannot identify two separate accounts; keep separate account identities before syncing.")
            end
            return Data.ImportAccount(packet)
        end)
        table.insert(outgoing, 1, { target = sender, message = (ok and "A:" or "E:") .. id })
        if not ok then error("Could not import " .. sender .. "'s account: " .. tostring(changed)) end
        Say("Received " .. sender .. "'s account" .. (changed and "." or "; it was already up to date."))
    end
end

local function Receive(prefix, message, distribution, sender)
    if not ready or prefix ~= PREFIX or distribution ~= "WHISPER"
        or type(message) ~= "string" or type(sender) ~= "string" then return end
    local key = NormalizePeer(sender)
    local trusted = Data.GetTrustedPeers()[key]
    if not trusted then
        if not warned[key] then
            warned[key] = true
            Say("Ignored an untrusted request or transfer from " .. sender .. ".")
        end
        return
    end
    if message == "Q:1" then
        local now = GetTime()
        if lastRequest[key] and now - lastRequest[key] < 10 then
            error("Repeated sync request from " .. sender .. ".")
        end
        lastRequest[key] = now
        -- Reply to the actual sender, not a possibly outdated saved whisper
        -- spelling. Reuse an exchange already queued in this direction.
        local queued = false
        for _, job in ipairs(outgoing) do
            if job.parts and NormalizePeer(job.target) == key then queued = true; break end
        end
        if not queued then
            -- If this character cannot build its snapshot, tell the requester.
            -- Otherwise the error appears only here and the other side waits
            -- silently until its request times out.
            local built, problem = pcall(EnqueueData, sender)
            if not built then
                table.insert(outgoing, 1, { target = sender, message = "F:1" })
                error("Could not prepare this account for " .. sender .. ": " .. tostring(problem))
            end
        end
        Say("Sending account data to trusted peer " .. sender .. ".")
    elseif message == "F:1" then
        requests[key] = nil
        Say(sender .. " could not prepare its account snapshot. The reason is shown in that character's chat.")
    elseif string.sub(message, 1, 2) == "D:" then
        ReceiveData(key, sender, message)
    else
        local status, id = string.match(message, "^([AE]):(%x+)$")
        local transfer = id and awaiting[id]
        if not transfer or transfer.key ~= key then error("Unrecognized sync confirmation from " .. sender .. ".") end
        awaiting[id] = nil
        if status == "A" then
            Say(sender .. " confirmed the account import.")
        else
            Say(sender .. " rejected the account import; check the other character's error message.")
        end
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if RegisterAddonMessagePrefix and RegisterAddonMessagePrefix(PREFIX) == false then
            error("Ashoholic could not register its sync message prefix.")
        end
        ready = true
        frame:UnregisterEvent("PLAYER_LOGIN")
        return
    end
    -- Incoming packets are untrusted input even when the sender is approved.
    -- Report a bad packet without interrupting WoW's other message handlers.
    local ok, problem = pcall(Receive, ...)
    if not ok then Say("Transfer rejected: " .. tostring(problem)) end
end)
frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < SEND_INTERVAL then return end
    elapsed = 0
    if ready then SendNext() end
    local now = GetTime()
    for key, record in pairs(incoming) do
        if now - record.startedAt > TIMEOUT then
            incoming[key] = nil
            Say("An incomplete account transfer timed out.")
        end
    end
    for id, transfer in pairs(awaiting) do
        if now - transfer.startedAt > TIMEOUT then
            awaiting[id] = nil
            Say("No import confirmation from " .. transfer.target .. ".")
        end
    end
    for key, request in pairs(requests) do
        if now - request.startedAt > TIMEOUT then
            requests[key] = nil
            Say("No account reply from " .. request.target .. ". Check that both characters are online and trusted.")
        end
    end
end)
