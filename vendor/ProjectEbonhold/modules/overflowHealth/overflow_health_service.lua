local addonName, addon = ...

if not addon.OverflowHealth then
    addon.OverflowHealth = {}
end

local OH = addon.OverflowHealth
OH.cache = {}        -- [lowGUID(decimal)] = overflow amount above the clamped client max

local function clearCache()
    for k in pairs(OH.cache) do
        OH.cache[k] = nil
    end
end

OH.ClearCache = clearCache

-- Convert "0xF130008F04000012" -> 0x000012 (decimal 18). Matches the
-- server-side GetCounter() of a creature low GUID (low 24 bits).
local function guidToLow(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local tail = string.sub(guid, -7)        -- 28 bits is plenty
    local n = tonumber(tail, 16)
    if not n then return nil end
    return bit.band(n, 0x00FFFFFF)           -- low 24 bits = counter
end
OH.GuidToLow = guidToLow

function OH:GetOverflow(unit)
    if not unit or not UnitExists(unit) then return nil end
    local low = guidToLow(UnitGUID(unit))
    return low and self.cache[low] or nil
end

-- Handle SEND_RAID_BOSS_OVERFLOW_HEALTH (event id 950)
-- Payload: "guid:overflow;guid:overflow;..." where overflow is the health
-- excess above the clamped client max.
--
-- Merge by GUID, do NOT clear first: the server sends a full snapshot on raid
-- entry AND a single "guid:overflow" pair as each boss enters the world
-- (summoned/late bosses are absent from the entry snapshot). Clearing on every
-- message would let each incremental pair wipe the previously-known bosses.
-- Stale entries are pruned when leaving the raid (frame handler below) and are
-- otherwise inert (GetOverflow only resolves against units that exist).
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_RAID_BOSS_OVERFLOW_HEALTH, function(body)
    if not body or body == "" then return end
    for guidStr, overflowStr in string.gmatch(body, "([^:;]+):([^:;]+)") do
        local guid = tonumber(guidStr)
        local overflow = tonumber(overflowStr)
        if guid and overflow then
            OH.cache[guid] = overflow
        end
    end
end)

-- Belt-and-suspenders: clear cache when leaving raid instances.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:SetScript("OnEvent", function()
    local _, instanceType = IsInInstance()
    if instanceType ~= "raid" then
        clearCache()
    end
end)

SLASH_OVERFLOWHP1 = "/overflowhp"
SlashCmdList["OVERFLOWHP"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "dump" then
        local n = 0
        for guid, max in pairs(OH.cache) do
            print(string.format("  %d => %s", guid, tostring(max)))
            n = n + 1
        end
        print("|cff00ffff[OverflowHP]|r " .. n .. " cached entries")
    elseif msg == "target" then
        local g = UnitGUID("target")
        local low = guidToLow(g)
        print("|cff00ffff[OverflowHP]|r target guid=" .. tostring(g) ..
            " low=" .. tostring(low) ..
            " cached=" .. tostring(low and OH.cache[low] or nil))
    else
        print("|cff00ffff[OverflowHP]|r /overflowhp dump|target")
    end
end