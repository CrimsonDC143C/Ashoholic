local addonName = ...
local addon = _G[addonName]

-- WotLK raid definitions, lockout lookup and boss-kill tracking.
local RaidData = {}
addon.RaidData = RaidData

RaidData.DifficultyVariant = { [1] = "10", [2] = "25", [3] = "10H", [4] = "25H" }
RaidData.VariantLabel = { ["10"] = "10", ["10H"] = "10HC", ["25"] = "25", ["25H"] = "25HC" }
RaidData.VariantTitle = {
    ["10"] = "10 Player", ["10H"] = "10 Player Heroic",
    ["25"] = "25 Player", ["25H"] = "25 Player Heroic",
}

local NORMAL = { "10", "25" }
local WITH_HEROIC = { "10", "10H", "25", "25H" }

-- triggers defaults to { name }. all = every listed unit must die.
-- impliedBy = killing one of these bosses also counts this boss (no unit death of its own).
RaidData.groups = {
    {
        key = "ICC", label = "Icecrown Citadel", short = "ICC", match = "Icecrown Citadel",
        variants = WITH_HEROIC,
        bosses = {
            { name = "Lord Marrowgar" },
            { name = "Lady Deathwhisper" },
            { name = "Icecrown Gunship Battle", triggers = {}, impliedBy = { "Deathbringer Saurfang" } },
            { name = "Deathbringer Saurfang" },
            { name = "Festergut" },
            { name = "Rotface" },
            { name = "Professor Putricide" },
            { name = "Blood Prince Council", all = { "Prince Valanar", "Prince Keleseth", "Prince Taldaram" } },
            { name = "Blood-Queen Lana'thel" },
            { name = "Valithria Dreamwalker", triggers = {}, impliedBy = { "Sindragosa", "The Lich King" } },
            { name = "Sindragosa" },
            { name = "The Lich King" },
        },
    },
    {
        key = "RS", label = "Ruby Sanctum", short = "RS", match = "Ruby Sanctum",
        variants = WITH_HEROIC,
        bosses = {
            { name = "Saviana Ragefire" },
            { name = "Baltharus the Warborn" },
            { name = "General Zarithrian" },
            { name = "Halion" },
        },
    },
    {
        key = "NAXX", label = "Naxxramas", short = "Naxx", match = "Naxxramas",
        variants = NORMAL,
        bosses = {
            { name = "Anub'Rekhan" },
            { name = "Grand Widow Faerlina" },
            { name = "Maexxna" },
            { name = "Noth the Plaguebringer" },
            { name = "Heigan the Unclean" },
            { name = "Loatheb" },
            { name = "Instructor Razuvious" },
            { name = "Gothik the Harvester" },
            { name = "The Four Horsemen", all = { "Thane Korth'azz", "Lady Blaumeux", "Baron Rivendare", "Sir Zeliek" } },
            { name = "Patchwerk" },
            { name = "Grobbulus" },
            { name = "Gluth" },
            { name = "Thaddius" },
            { name = "Sapphiron" },
            { name = "Kel'Thuzad" },
        },
    },
    {
        key = "OS", label = "Obsidian Sanctum", short = "OS", match = "Obsidian Sanctum",
        variants = NORMAL,
        bosses = { { name = "Sartharion" } },
    },
    {
        key = "EOE", label = "Eye of Eternity", short = "EoE", match = "Eye of Eternity",
        variants = NORMAL,
        bosses = { { name = "Malygos" } },
    },
    {
        key = "ULD", label = "Ulduar", short = "Uld", match = "Ulduar",
        variants = NORMAL,
        bosses = {
            { name = "Flame Leviathan" },
            { name = "Ignis the Furnace Master" },
            { name = "Razorscale" },
            { name = "XT-002 Deconstructor" },
            { name = "Assembly of Iron", all = { "Steelbreaker", "Runemaster Molgeim", "Stormcaller Brundir" } },
            { name = "Kologarn" },
            { name = "Auriaya" },
            { name = "Hodir" },
            { name = "Thorim" },
            { name = "Freya" },
            { name = "Mimiron", all = { "Leviathan Mk II", "VX-001", "Aerial Command Unit" }, window = 20 },
            { name = "General Vezax" },
            { name = "Yogg-Saron" },
            { name = "Algalon the Observer" },
        },
    },
    {
        key = "TOC", label = "Trial of the Crusader", short = "ToC", match = "Trial of the Crusader",
        variants = NORMAL,
        bosses = {
            { name = "Northrend Beasts", triggers = { "Icehowl" } },
            { name = "Lord Jaraxxus" },
            { name = "Faction Champions", triggers = {}, impliedBy = { "Twin Val'kyr", "Anub'arak" } },
            { name = "Twin Val'kyr", all = { "Fjola Lightbane", "Eydis Darkbane" } },
            { name = "Anub'arak" },
        },
    },
}

local groupByKey = {}
for _, group in ipairs(RaidData.groups) do
    groupByKey[group.key] = group
    for _, boss in ipairs(group.bosses) do
        local list = boss.all or boss.triggers or { boss.name }
        boss.lowerTriggers = {}
        for i, name in ipairs(list) do boss.lowerTriggers[i] = string.lower(name) end
    end
end

function RaidData:GetGroup(key) return groupByKey[key] end

function RaidData:FindGroup(instanceName)
    if type(instanceName) ~= "string" then return nil end
    for _, group in ipairs(self.groups) do
        if string.find(instanceName, group.match, 1, true) then return group end
    end
end

local function LockKey(group, variant) return group.key .. "#" .. variant end
RaidData.LockKey = LockKey

-- Active lockouts for one character, keyed "GROUP#variant", with the recorded kills attached.
function RaidData:GetLocks(charDB)
    local result = {}
    if type(charDB) ~= "table" then return result end
    local now = time()

    if type(charDB.RaidLockouts) == "table" then
        for key, lock in pairs(charDB.RaidLockouts) do
            local expires = (lock.resetAt or 0) - now
            if expires > 0 then
                result[key] = { id = lock.id, expires = expires }
            end
        end
    elseif type(charDB.SavedInstance) == "table" then
        -- Characters last scanned before RaidLockouts existed.
        for instanceKey, info in pairs(charDB.SavedInstance) do
            local name, size = string.match(tostring(instanceKey), "^(.-)%s*%((%d+)%)")
            local group = self:FindGroup(name)
            if group and type(info) == "string" and (size == "10" or size == "25") then
                local reset, checked, diff = strsplit("|", info)
                local expires = (tonumber(reset) or 0) - (now - (tonumber(checked) or 0))
                if expires > 0 then
                    local heroic = diff and string.find(string.lower(diff), "heroic", 1, true)
                    result[LockKey(group, size .. (heroic and "H" or ""))] = { expires = expires }
                end
            end
        end
    end

    if type(charDB.RaidKills) == "table" then
        for key, lock in pairs(result) do
            local rec = charDB.RaidKills[key]
            if rec and (rec.id == nil or rec.id == lock.id) then lock.kills = rec.bosses end
        end
    end
    return result
end

-- Called after a lockout scan. Drops kill records that belong to a lockout that no longer exists.
function RaidData:PruneKills(charDB)
    if type(charDB) ~= "table" or type(charDB.RaidKills) ~= "table" then return end
    local locks = charDB.RaidLockouts or {}
    local now = time()
    for key, rec in pairs(charDB.RaidKills) do
        local lock = locks[key]
        if lock and (lock.resetAt or 0) > now then
            if rec.id and rec.id ~= lock.id then
                charDB.RaidKills[key] = nil
            else
                rec.id = lock.id
            end
        elseif rec.id or now - (rec.last or 0) > 600 then
            -- A fresh kill can precede the lockout showing up in the scan, so unbound records get a grace period.
            charDB.RaidKills[key] = nil
        end
    end
end

local function CurrentCharDB()
    if not addon.db or not addon.db.global or not addon.db.global.Characters then return nil end
    local player = UnitName("player")
    if not player or player == "" or player == UNKNOWN then return nil end
    return addon.db.global.Characters[format("%s.%s", GetRealmName() or "", player)]
end

local function MarkKilled(charDB, group, variant, index)
    local key = LockKey(group, variant)
    charDB.RaidKills = charDB.RaidKills or {}
    local rec = charDB.RaidKills[key]
    if not rec then
        rec = { bosses = {} }
        charDB.RaidKills[key] = rec
    end
    local now = time()
    rec.last = now
    rec.bosses[index] = rec.bosses[index] or now
    local killedName = group.bosses[index].name
    for i, boss in ipairs(group.bosses) do
        if boss.impliedBy then
            for _, name in ipairs(boss.impliedBy) do
                if name == killedName then rec.bosses[i] = rec.bosses[i] or now end
            end
        end
    end
    local lock = charDB.RaidLockouts and charDB.RaidLockouts[key]
    if lock and lock.id and (lock.resetAt or 0) > now then rec.id = lock.id end
    if RequestRaidInfo and C_Timer then C_Timer.After(3, RequestRaidInfo) end
end

local partial = {}

function RaidData:OnUnitDied(destName)
    local inside, kind = IsInInstance()
    if not inside or kind ~= "raid" then return end
    local instanceName, _, difficulty = GetInstanceInfo()
    local group = self:FindGroup(instanceName)
    local variant = self.DifficultyVariant[tonumber(difficulty)]
    if not group or not variant then return end

    local lower = string.lower(destName)
    for index, boss in ipairs(group.bosses) do
        for t, trigger in ipairs(boss.lowerTriggers) do
            if trigger == lower then
                local charDB = CurrentCharDB()
                if not charDB then return end
                if boss.all then
                    local key = LockKey(group, variant) .. ":" .. index
                    local seen = partial[key]
                    if not seen then seen = {}; partial[key] = seen end
                    seen[t] = GetTime()
                    local complete, oldest, newest = true, nil, nil
                    for i = 1, #boss.lowerTriggers do
                        local at = seen[i]
                        if not at then complete = false; break end
                        oldest = (not oldest or at < oldest) and at or oldest
                        newest = (not newest or at > newest) and at or newest
                    end
                    if complete and (not boss.window or newest - oldest <= boss.window) then
                        partial[key] = nil
                        MarkKilled(charDB, group, variant, index)
                    end
                else
                    MarkKilled(charDB, group, variant, index)
                end
                return
            end
        end
    end
end

function RaidData:ClearKills(charDB)
    if type(charDB) == "table" then charDB.RaidKills = nil end
    wipe(partial)
end

local events = CreateFrame("Frame")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        wipe(partial)
        return
    end
    local _, subevent, _, _, _, _, destName = ...
    if subevent == "UNIT_DIED" and destName then
        RaidData:OnUnitDied(destName)
    end
end)
