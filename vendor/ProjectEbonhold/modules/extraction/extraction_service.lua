local addonName, addon = ...

ExtractionService = ExtractionService or {}
ExtractionService.currentCost = nil   -- copper amount (extraction)
ExtractionService.applyCost = nil     -- copper amount (per-affix engraving)
ExtractionService.learnedAffixes = {} -- { { id=N, name="...", description="..." }, ... }

-- Request the current extraction cost for the item at bag,slot
function ExtractionService.RequestExtractionInfo(bag, slot)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_AFFIX_EXTRACTION_INFO, bag .. "," .. slot)
end

-- Request extraction of an item at bag,slot
function ExtractionService.RequestExtraction(bag, slot)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_AFFIX_EXTRACTION, bag .. "," .. slot)
end

-- Request the list of learned affixes
function ExtractionService.RequestLearnedAffixes()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_LEARNED_AFFIXES, "")
end

-- Request applying an affix to an item at bag,slot
-- Protocol: body = "spellId,bag,slot"
function ExtractionService.RequestApplyAffix(spellId, bag, slot)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_AFFIX_APPLY, spellId .. "," .. bag .. "," .. slot)
end

-- Request the engraving cost for a specific affix spell
function ExtractionService.RequestApplyInfo(spellId)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_AFFIX_APPLY_INFO, tostring(spellId))
end

-- Handle SEND_AFFIX_EXTRACTION_INFO (event 511)
-- Body: "<costCopper>"  e.g. "100000"
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_AFFIX_EXTRACTION_INFO, function(body)
    local cost = tonumber(body)
    ExtractionService.currentCost = cost

    if ExtractionUI and ExtractionUI.OnCostReceived then
        ExtractionUI.OnCostReceived(cost)
    end
end)

-- Handle SEND_AFFIX_EXTRACTION_RESULT (event 510)
-- Body: "OK" or "FAIL,<reason>"
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_AFFIX_EXTRACTION_RESULT, function(body)
    if body == "OK" then
        -- the affix just learned must show as known in the loot toast / side panel
        ExtractionService.RequestLearnedAffixes()
        if ExtractionUI and ExtractionUI.OnExtractionSuccess then
            ExtractionUI.OnExtractionSuccess()
        end
    else
        local _, reason = body:match("^([^,]+),(.+)$")
        if ExtractionUI and ExtractionUI.OnExtractionFail then
            ExtractionUI.OnExtractionFail(reason)
        end
    end
end)

-- Handle SEND_LEARNED_AFFIXES (event 513)
-- Body: "spellId,spellId,..." -- the learn-spell ids the player knows, nothing else.
-- Every (family, rank) of the static affixes_data.lua (generated from tools/affixes/catalog.py)
-- becomes an entry: name, icon, category, tooltip text, enchantId and cost come from there, the
-- server list only flags which are learned, and the applied count is read from the equipped
-- item links (8th field = ItemRandomProperties = enchantId). A learned id the data file does not
-- know is ignored: the data file and the server ship together.
ExtractionService.CATEGORY_NAMES = { [1] = "Offensive", [2] = "Defensive", [3] = "Resource", [4] = "Utility", [5] = "Mobility" }
ExtractionService.affixByEnchant = {}   -- enchantId (ItemRandomProperties) -> affix entry
ExtractionService.learnedAffixes = {}   -- one entry per (family, rank), static order

-- Number of equipped items carrying each enchantId
local function CountEquippedEnchants()
    local counts = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local randomProp = select(8, strsplit(":", link))   -- one value only: tonumber(a, b) reads b as a base
            randomProp = randomProp and tonumber(randomProp)
            if randomProp and randomProp > 0 then
                counts[randomProp] = (counts[randomProp] or 0) + 1
            end
        end
    end
    return counts
end

-- Recomputes appliedCount on the current list (call after an equipment change)
function ExtractionService.RefreshAppliedCounts()
    local counts = CountEquippedEnchants()
    for _, affix in ipairs(ExtractionService.learnedAffixes) do
        affix.appliedCount = counts[affix.enchantId] or 0
    end
end

local function BuildStaticEntry(db, familyId, rank, learnedSet, counts)
    local fam = db.families[familyId]
    local rankEntry = fam.ranks[rank]
    local affix = {
        id = rankEntry.spellId,
        name = fam.name .. " " .. (db.roman[rank] or tostring(rank)),
        familyName = fam.name,
        icon = fam.icon,
        text = rankEntry.text,
        applyCost = rankEntry.applyCost,
        appliedCount = counts[rankEntry.enchantId] or 0,
        category = fam.category,
        rank = rank,
        learned = learnedSet[rankEntry.spellId] == true,
        familyId = familyId,
        enchantId = rankEntry.enchantId,
    }
    return affix
end

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_LEARNED_AFFIXES, function(body)
    ExtractionService.learnedAffixes = {}
    ExtractionService.affixByEnchant = {}
    local db = ProjectEbonhold.AffixDatabase
    if not db then
        if ExtractionUI and ExtractionUI.OnLearnedAffixesReceived then
            ExtractionUI.OnLearnedAffixesReceived()
        end
        return
    end

    local learnedSet = {}
    for idStr in string.gmatch(body or "", "(%d+)") do
        learnedSet[tonumber(idStr)] = true
    end
    local counts = CountEquippedEnchants()

    for familyId = 0, db.familyCount - 1 do
        if db.families[familyId] then
            for rank = 1, db.ranks do
                if db.families[familyId].ranks[rank] then
                    local affix = BuildStaticEntry(db, familyId, rank, learnedSet, counts)
                    table.insert(ExtractionService.learnedAffixes, affix)
                    ExtractionService.affixByEnchant[affix.enchantId] = affix
                    learnedSet[affix.id] = nil
                end
            end
        end
    end

    if ExtractionUI and ExtractionUI.OnLearnedAffixesReceived then
        ExtractionUI.OnLearnedAffixesReceived()
    end
end)

-- Handle SEND_AFFIX_APPLY_RESULT (event 512)
-- Body: "OK" or "FAIL,<reason>"
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_AFFIX_APPLY_RESULT, function(body)
    if body == "OK" then
        if ExtractionUI and ExtractionUI.OnApplySuccess then
            ExtractionUI.OnApplySuccess()
        end
    else
        local _, reason = body:match("^([^,]+),(.+)$")
        if ExtractionUI and ExtractionUI.OnApplyFail then
            ExtractionUI.OnApplyFail(reason)
        end
    end
end)

-- Handle SEND_AFFIX_APPLY_INFO (event 514)
-- Body: "<cost>" — engraving cost in copper for the requested affix
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_AFFIX_APPLY_INFO, function(body)
    local cost = tonumber(body)
    ExtractionService.applyCost = cost
    if ExtractionUI and ExtractionUI.OnApplyCostReceived then
        ExtractionUI.OnApplyCostReceived(cost)
    end
end)

------------------------------------------------------------
-- Legendary Torment upgrade (Enchanted Anvil)
------------------------------------------------------------
ExtractionService.upgradeInfo = nil   -- { tokenId, needed, held, nextEntry, label } or nil

function ExtractionService.RequestLegendaryUpgradeInfo(bag, slot)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_LEGENDARY_UPGRADE_INFO, bag .. "," .. slot)
end

function ExtractionService.RequestLegendaryUpgrade(bag, slot)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_LEGENDARY_UPGRADE, bag .. "," .. slot)
end

-- SEND_LEGENDARY_UPGRADE_INFO (516): "NONE" or "tokenId,needed,held,nextEntry,label"
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_LEGENDARY_UPGRADE_INFO, function(body)
    ExtractionService.upgradeInfo = nil
    if body and body ~= "NONE" then
        local tokenStr, neededStr, heldStr, nextStr, label = body:match("^(%d+),(%d+),(%d+),(%d+),(.+)$")
        if tokenStr then
            ExtractionService.upgradeInfo = {
                tokenId    = tonumber(tokenStr),
                needed     = tonumber(neededStr),
                held       = tonumber(heldStr),
                nextEntry  = tonumber(nextStr),
                label      = label,
            }
        end
    end
    if ExtractionUI and ExtractionUI.OnUpgradeInfoReceived then
        ExtractionUI.OnUpgradeInfoReceived(ExtractionService.upgradeInfo)
    end
end)

-- SEND_LEGENDARY_UPGRADE_RESULT (517): "OK,<newEntry>" or "FAIL,<reason>"
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_LEGENDARY_UPGRADE_RESULT, function(body)
    local status, rest = body:match("^([^,]+),?(.*)$")
    if status == "OK" then
        if ExtractionUI and ExtractionUI.OnUpgradeSuccess then
            ExtractionUI.OnUpgradeSuccess(tonumber(rest))
        end
    else
        if ExtractionUI and ExtractionUI.OnUpgradeFail then
            ExtractionUI.OnUpgradeFail(rest)
        end
    end
end)

-- Fetch learned affixes once on login
local extractionInitFrame = CreateFrame("Frame")
extractionInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
extractionInitFrame:SetScript("OnEvent", function(self)
    ExtractionService.RequestLearnedAffixes()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)
