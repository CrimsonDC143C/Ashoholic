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
-- Body: "spellId:applyCost:appliedCount:difficulty:weaponOnly:learned,..." — comma-separated entries
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_LEARNED_AFFIXES, function(body)
    ExtractionService.learnedAffixes = {}
    if not body or body == "" then
        if ExtractionUI and ExtractionUI.OnLearnedAffixesReceived then
            ExtractionUI.OnLearnedAffixesReceived()
        end
        return
    end
    for entry in string.gmatch(body, "([^,]+)") do
        local spellIdStr, applyCostStr, appliedCountStr, difficultyStr, weaponOnlyStr, learnedStr =
            entry:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
        if spellIdStr then
            local spellId = tonumber(spellIdStr)
            local applyCost = tonumber(applyCostStr)
            local appliedCount = tonumber(appliedCountStr)
            local difficulty = tonumber(difficultyStr)
            local weaponOnly = tonumber(weaponOnlyStr) == 1
            local learned = tonumber(learnedStr) == 1
            local spellName, _, spellIcon = GetSpellInfo(spellId)
            table.insert(ExtractionService.learnedAffixes, {
                id = spellId,
                name = spellName or ("Affix " .. spellId),
                icon = spellIcon,
                applyCost = applyCost,
                appliedCount = appliedCount,
                difficulty = difficulty,
                weaponOnly = weaponOnly,
                learned = learned,
            })
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

-- Fetch learned affixes once on login
local extractionInitFrame = CreateFrame("Frame")
extractionInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
extractionInitFrame:SetScript("OnEvent", function(self)
    ExtractionService.RequestLearnedAffixes()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)
