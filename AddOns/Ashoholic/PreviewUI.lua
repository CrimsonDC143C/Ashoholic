-- Session-local examples for /ash preview. Live data never uses these records.
local addonName = ...
local addon = _G[addonName]

function addon:CreatePreviewRecords()
    local accounts = {
        { name = "Account One", ash = 14800000, shards = 3750, essence = 16, artisan = 28, gold = 12420, warband = 4000, prestige = 12 },
        { name = "Account Two", ash = 9200000, shards = 1350, essence = 8, artisan = 14, gold = 6850, warband = 2200, prestige = 7 },
        { name = "Account Three", ash = 18200000, shards = 4500, essence = 22, artisan = 19, gold = 9600, warband = 3100, prestige = 18 },
        { name = "Account Four", ash = 6400000, shards = 63000, essence = 4, artisan = 32, gold = 5100, warband = 1800, prestige = 4 },
    }
    local characters = {
        { name = "Aster", account = 1, class = "PALADIN", level = 80, ilvl = 226, tier = 6, runAsh = "284k", runShards = 145, gold = "7,200g", seen = "Just now", location = "Dalaran", action = "2 rewards to claim", offerings = "3 / 5", bonus = "+35%", build = "Dawnkeeper", anchor = "Dalaran", progress = 7 },
        { name = "Cinder", account = 1, class = "MAGE", level = 80, ilvl = 213, tier = 4, runAsh = "96k", runShards = 60, gold = "3,480g", seen = "2 hours ago", location = "Karazhan", action = "Nightbane loot available", offerings = "4 / 5", bonus = "+15%", build = "Living Flame", anchor = "Deadwind Pass", progress = 3 },
        { name = "Thorn", account = 1, class = "DRUID", level = 64, ilvl = 118, tier = 1, runAsh = "38k", runShards = 12, gold = "1,740g", seen = "Yesterday", location = "Nagrand", action = "Continue leveling", offerings = "5 / 5", bonus = "+10%", build = "Wildheart", anchor = "Nagrand", progress = 0 },
        { name = "Vesper", account = 2, class = "WARLOCK", level = 80, ilvl = 232, tier = 8, runAsh = "410k", runShards = 210, gold = "4,900g", seen = "35 min ago", location = "Icecrown", action = "Cache nearly ready", offerings = "2 / 5", bonus = "+50%", build = "Void Chorus", anchor = "Icecrown", progress = 9 },
        { name = "Rook", account = 2, class = "WARRIOR", level = 80, ilvl = 200, tier = 2, runAsh = "Unknown", runShards = nil, gold = "1,950g", seen = "8 days ago", location = "Stormwind", action = "Refresh stale snapshot", offerings = "Unknown", bonus = "Unknown", build = "Ironbound", anchor = "Unknown", progress = 2, stale = true },
    }
    for i, sample in ipairs({
        { "Ember", "SHAMAN", 1 }, { "Lumen", "PRIEST", 1 },
        { "Flint", "HUNTER", 2 }, { "Shade", "ROGUE", 2 },
        { "Briar", "DRUID", 3 }, { "Sol", "PALADIN", 3 }, { "Nyx", "MAGE", 3 },
        { "Ashen", "DEATHKNIGHT", 3 }, { "Gale", "SHAMAN", 4 },
        { "Rune", "WARLOCK", 4 }, { "Vale", "PRIEST", 4 }, { "Steel", "WARRIOR", 4 },
        { "Fable", "HUNTER", 1 }, { "Wisp", "ROGUE", 1 }, { "Anvil", "WARRIOR", 1 },
        { "Dusk", "WARLOCK", 1 }, { "Rime", "DEATHKNIGHT", 1 },
    }) do
        characters[#characters + 1] = {
            name = sample[1], class = sample[2], account = sample[3], level = 80, ilvl = 200 + i,
            runAsh = (40 + i * 12) .. "k", runShards = 25 + i * 8, gold = "Sample",
            seen = "Today", location = "Dalaran", action = "Sample character snapshot",
            offerings = "4 / 5", bonus = "+20%", build = "Build " .. i, anchor = "Dalaran",
        }
    end
    for i, account in ipairs(accounts) do
        account.originalName = account.name
        account.tier = ({ 6, 8, 10, 3 })[i]
    end
    return accounts, characters
end

local preview
function addon:TogglePreviewUI()
    if not preview then preview = self:CreateDashboard() end
    preview.Toggle()
end
