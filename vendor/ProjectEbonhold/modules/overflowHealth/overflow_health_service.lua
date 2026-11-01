local addonName, addon = ...

if not addon.OverflowHealth then
    addon.OverflowHealth = {}
end

local OH = addon.OverflowHealth

-- The server caps a creature's visible max health at VISIBLE_HEALTH_CAP (the
-- 3.3.5 client reads it as a signed int32) and keeps the rest in a hidden pool.
-- Bar proportion is kept exact server side (visible % == pool %), so only the
-- numbers need the pool: real max = UnitHealthMax + pool.
OH.VISIBLE_HEALTH_CAP = 2000000000

-- The addon channel is shared by every feature, so this module stays quiet:
-- the server never pushes pools, the addon asks ONCE per unit it actually
-- shows at the cap and keeps the answer (a "no pool" answer included) until
-- the server sends "*" (map or Torment change). A continent has no "*" on a
-- Torment change, so there an answer is trusted for CONTINENT_TTL seconds.
OH.cache = {}        -- [GUID hex, upper case, no "0x"] = hidden pool above the cap
local none = {}      -- [GUID hex] = true: the server said this unit has no pool
local answeredAt = {} -- [GUID hex] = GetTime() of the answer
local lastAsked = {} -- [GUID hex] = GetTime() of the last REQUEST_OVERFLOW_HEALTH

local ASK_RETRY = 10      -- seconds before asking again for an unanswered unit
local CONTINENT_TTL = 120 -- seconds an answer is kept outside instances

local function clearCache()
    wipe(OH.cache)
    wipe(none)
    wipe(answeredAt)
    wipe(lastAsked)
end
OH.ClearCache = clearCache

-- "0xF130008F04000012" -> "F130008F04000012", the key the server sends.
local function guidKey(guid)
    if not guid or type(guid) ~= "string" then return nil end
    guid = guid:upper()
    if guid:sub(1, 2) == "0X" then guid = guid:sub(3) end
    return guid
end
OH.GuidKey = guidKey

function OH:GetOverflow(unit)
    if not unit or not UnitExists(unit) then return nil end
    local key = guidKey(UnitGUID(unit))
    return key and self.cache[key] or nil
end

-- Ask the server for the pool of a unit shown at the cap - at most once per
-- unit (see the header above). Safe to call from any refresh path.
function OH:Request(unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    if (UnitHealthMax(unit) or 0) < self.VISIBLE_HEALTH_CAP then return end
    local key = guidKey(UnitGUID(unit))
    if not key then return end
    local now = GetTime()
    if answeredAt[key] then
        if IsInInstance() or now - answeredAt[key] < CONTINENT_TTL then return end
    end
    if lastAsked[key] and now - lastAsked[key] < ASK_RETRY then return end
    lastAsked[key] = now
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_OVERFLOW_HEALTH, key)
end

-- SEND_RAID_BOSS_OVERFLOW_HEALTH (event id 950)
-- Payload: "GUIDHEX:pool" (answer to a Request; pool 0 = the unit has none),
-- or "*": forget everything (map change, Torment change).
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_RAID_BOSS_OVERFLOW_HEALTH, function(body)
    if not body then return end
    if body:sub(1, 1) == "*" then
        clearCache()
        body = body:sub(2)
    end
    local now = GetTime()
    for key, poolStr in string.gmatch(body, "([^:;]+):(%d+)") do
        local pool = tonumber(poolStr)
        answeredAt[key] = now
        if pool and pool > 0 then
            OH.cache[key] = pool
            none[key] = nil
        else
            OH.cache[key] = nil
            none[key] = true
        end
    end
    if OH.Refresh then OH.Refresh() end
end)

SLASH_OVERFLOWHP1 = "/overflowhp"
SlashCmdList["OVERFLOWHP"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "dump" then
        local n = 0
        for key, pool in pairs(OH.cache) do
            print(string.format("  %s => %s", key, tostring(pool)))
            n = n + 1
        end
        print("|cff00ffff[OverflowHP]|r " .. n .. " cached entries")
    elseif msg == "target" then
        local key = guidKey(UnitGUID("target"))
        print("|cff00ffff[OverflowHP]|r target guid=" .. tostring(key) ..
            " max=" .. tostring(UnitHealthMax("target")) ..
            " pool=" .. tostring(key and OH.cache[key] or nil) ..
            " none=" .. tostring(key and none[key] or nil))
    else
        print("|cff00ffff[OverflowHP]|r /overflowhp dump|target")
    end
end