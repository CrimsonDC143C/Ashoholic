local addon, Addon = ...

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.SpellPlacementService = ProjectEbonhold.SpellPlacementService or {}

local SpellPlacementService = ProjectEbonhold.SpellPlacementService
local BOOKTYPE_SPELL = "spell"

local requirements = {}
local requirementsByName = {}
local requirementsByNameRank = {}

local function clearTable(tbl)
    for k in pairs(tbl) do
        tbl[k] = nil
    end
end

local ACTION_BUTTON_PREFIXES = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
    "BonusActionButton",
}

local function parseSpellIdFromLink(link)
    if not link or link == "" then return nil end
    return tonumber(link:match("|Hspell:(%d+)|h"))
end

local function getSpellIdFromActionSlot(slot)
    local actionType, actionId = GetActionInfo(slot)
    if actionType ~= "spell" or not actionId or actionId <= 0 then
        return nil
    end

    local spellLink = GetSpellLink(actionId, BOOKTYPE_SPELL)
    local spellId = parseSpellIdFromLink(spellLink)
    if spellId then
        return spellId
    end

    local spellName = GetSpellName(actionId, BOOKTYPE_SPELL)
    if not spellName then return nil end
    return select(7, GetSpellInfo(spellName))
end

local function isSpellLockedByLevel(spellId)
    local required = requirements[spellId]
    if not required then
        local name = GetSpellInfo(spellId)
        if name then
            required = requirementsByName[name]
        end
    end
    if not required then return false end
    return (UnitLevel("player") or 1) < required
end

local function applyLockVisual(button)
    if not button then return end
    local name = button:GetName() or "?"

    local icon = button.icon or _G[name .. "Icon"]
    if not icon then
        return
    end

    local slot = button.action
    if not slot or slot == 0 then
        return
    end

    local actionType, actionId = GetActionInfo(slot)

    local spellId = getSpellIdFromActionSlot(slot)
    if not spellId then
        return
    end

    local locked = isSpellLockedByLevel(spellId)

    if locked then
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.4, 0.4, 0.4)
    else
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1)
    end
end

local function forEachActionButton(fn)
    for _, prefix in ipairs(ACTION_BUTTON_PREFIXES) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button then
                fn(button)
            end
        end
    end
end

local function refreshAllButtons()
    forEachActionButton(applyLockVisual)
end

local SPELLS_PER_PAGE = 12

local function applySpellBookButton(button)
    if not button then return end
    local buttonName = button:GetName() or ""
    local visualIdx = tonumber(buttonName:match("SpellButton(%d+)"))
    if not visualIdx then return end

    local iconTex = _G["SpellButton" .. visualIdx .. "IconTexture"]
    local normal = button:GetNormalTexture()
    local nameLabel = _G["SpellButton" .. visualIdx .. "SpellName"]
    local subLabel = _G["SpellButton" .. visualIdx .. "SubSpellName"]

    local spellName = nameLabel and nameLabel:GetText()
    local spellRank = subLabel and subLabel:GetText() or ""
    local hasIcon = iconTex and iconTex:GetTexture()

    local locked = false
    if button:IsShown() and hasIcon and spellName and spellName ~= "" then
        local required = requirementsByNameRank[spellName .. "||" .. spellRank]
        if not required then
            required = requirementsByName[spellName]
        end
        if required and (UnitLevel("player") or 1) < required then
            locked = true
        end
    end

    if locked then
        if iconTex then
            iconTex:SetDesaturated(true)
            iconTex:SetVertexColor(0.4, 0.4, 0.4)
        end
        if normal then normal:SetDesaturated(true) end
        if not button.__EbonholdGreyOverlay and iconTex then
            local ov = button:CreateTexture(nil, "OVERLAY")
            ov:SetTexture("Interface\\Buttons\\WHITE8X8")
            ov:SetVertexColor(0, 0, 0, 0.55)
            ov:SetAllPoints(iconTex)
            button.__EbonholdGreyOverlay = ov
        end
        if button.__EbonholdGreyOverlay then
            button.__EbonholdGreyOverlay:Show()
        end
    else
        if iconTex then
            iconTex:SetDesaturated(false)
            iconTex:SetVertexColor(1, 1, 1)
        end
        if normal then normal:SetDesaturated(false) end
        if button.__EbonholdGreyOverlay and button.__EbonholdGreyOverlay:IsShown() then
            button.__EbonholdGreyOverlay:Hide()
        end
    end
end

local function refreshSpellBook()
    for i = 1, SPELLS_PER_PAGE do
        applySpellBookButton(_G["SpellButton" .. i])
    end
end

local function loadRequirementsFromConfigTable()
    clearTable(requirements)
    clearTable(requirementsByName)
    clearTable(requirementsByNameRank)

    local function record(spellIdNum, reqLevelNum)
        requirements[spellIdNum] = reqLevelNum
        local name, rank = GetSpellInfo(spellIdNum)
        if name then
            local existing = requirementsByName[name]
            if not existing or reqLevelNum < existing then
                requirementsByName[name] = reqLevelNum
            end
            local key = name .. "||" .. (rank or "")
            local existingNR = requirementsByNameRank[key]
            if not existingNR or reqLevelNum < existingNR then
                requirementsByNameRank[key] = reqLevelNum
            end
        end
    end

    local _, playerClassToken = UnitClass("player")

    local byClassByLevel = ProjectEbonhold.SpellPlacementByClassByLevel or ProjectEbonhold.SpellsByClassByLevel
    if byClassByLevel and playerClassToken then
        local levels = byClassByLevel["CLASS_" .. playerClassToken]
            or byClassByLevel[playerClassToken]
        if levels then
            for requiredLevel, spellIds in pairs(levels) do
                local reqLevelNum = tonumber(requiredLevel)
                if reqLevelNum and type(spellIds) == "table" then
                    for _, spellId in ipairs(spellIds) do
                        local spellIdNum = tonumber(spellId)
                        if spellIdNum and spellIdNum > 0 then
                            record(spellIdNum, reqLevelNum)
                        end
                    end
                end
            end
            return
        end
    end

    -- Adapter for arrays keyed by numeric class IDs (if provided by external code).
    -- Mapping follows classic WoW class ordering.
    if byClassByLevel and playerClassToken then
        local CLASS_ID_BY_TOKEN = {
            WARRIOR = 1,
            PALADIN = 2,
            HUNTER = 3,
            ROGUE = 4,
            PRIEST = 5,
            DEATHKNIGHT = 6,
            SHAMAN = 7,
            MAGE = 8,
            WARLOCK = 9,
            DRUID = 11,
        }

        local classId = CLASS_ID_BY_TOKEN[playerClassToken]
        local levels = classId and byClassByLevel[classId] or nil
        if levels then
            for requiredLevel, spellIds in pairs(levels) do
                local reqLevelNum = tonumber(requiredLevel)
                if reqLevelNum and type(spellIds) == "table" then
                    for _, spellId in ipairs(spellIds) do
                        local spellIdNum = tonumber(spellId)
                        if spellIdNum and spellIdNum > 0 then
                            record(spellIdNum, reqLevelNum)
                        end
                    end
                end
            end
            return
        end
    end

    if not ProjectEbonhold.SpellPlacementRequirements then
        return
    end

    for spellId, requiredLevel in pairs(ProjectEbonhold.SpellPlacementRequirements) do
        local id = tonumber(spellId)
        local level = tonumber(requiredLevel)
        if id and level and level > 0 then
            record(id, level)
        end
    end
end

function SpellPlacementService.SetSpellLevelRequirements(tbl)
    if type(tbl) ~= "table" then return end

    clearTable(requirements)
    for spellId, requiredLevel in pairs(tbl) do
        local id = tonumber(spellId)
        local level = tonumber(requiredLevel)
        if id and level and level > 0 then
            requirements[id] = level
        end
    end

    refreshAllButtons()
end

function SpellPlacementService.GetSpellLevelRequirement(spellId)
    return requirements[tonumber(spellId or 0)]
end

function SpellPlacementService.IsActionLocked(slot)
    local spellId = getSpellIdFromActionSlot(slot)
    if not spellId then return false end
    return isSpellLockedByLevel(spellId)
end

-- =========================================================
-- Auto-downgrade: replace locked higher-rank spells on the
-- action bar with the highest rank the player can use now.
-- =========================================================

local MAX_ACTION_BUTTONS = 144
local POSSESSION_START   = 121
local POSSESSION_END     = 132

-- While in a vehicle / possessing, the action bar is overridden; mutating slots
-- then fights the override and scrambles the player's real bars on exit.
local function isBarOverridden()
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then return true end
    if UnitInVehicle and UnitInVehicle("player") then return true end
    if UnitControllingVehicle and UnitControllingVehicle("player") then return true end
    -- Possessed turrets (e.g. the ICC gunship cannons) use the possess bar.
    if IsPossessBarVisible and IsPossessBarVisible() then return true end
    if PossessBarFrame and PossessBarFrame:IsShown() then return true end
    return false
end

local function buildSpellBookIndexById()
    local cache = {}
    for book = 1, MAX_SKILLLINE_TABS do
        local _, _, offset, numSpells = GetSpellTabInfo(book)
        if offset and numSpells then
            for i = 1, numSpells do
                local index = offset + i
                local link = GetSpellLink(index, BOOKTYPE_SPELL)
                local sid = link and tonumber(link:match("|Hspell:(%d+)|h"))
                if sid then
                    cache[sid] = index
                end
            end
        end
    end
    return cache
end

-- Build a map of spellId -> best replacement spellId for the current player level.
-- Includes both downgrades (locked higher ranks) and upgrades (lower ranks
-- that should be bumped to the highest now-usable rank).
local function buildDowngradeMap()
    local groups = {}
    for id, lvl in pairs(requirements) do
        local name = GetSpellInfo(id)
        if name then
            groups[name] = groups[name] or {}
            table.insert(groups[name], { id = id, lvl = lvl })
        end
    end

    local playerLevel = UnitLevel("player") or 1
    local map = {}
    for _, list in pairs(groups) do
        table.sort(list, function(a, b) return a.lvl < b.lvl end)
        local best
        for _, e in ipairs(list) do
            if e.lvl <= playerLevel then
                best = e.id
            end
        end
        if best then
            for _, e in ipairs(list) do
                if e.id ~= best then
                    map[e.id] = best
                end
            end
        end
    end
    return map
end

local pendingDowngrade = false

local function downgradeLockedActions()
    if InCombatLockdown() then
        pendingDowngrade = true
        return
    end

    -- Don't reshuffle ranks while the vehicle/possess bar is active. SPELLS_CHANGED
    -- fires again on vehicle exit, which re-triggers this safely.
    if isBarOverridden() then
        pendingDowngrade = true
        return
    end

    local replacements = buildDowngradeMap()
    if not next(replacements) then return end

    local bookIndex = buildSpellBookIndexById()
    local changed = false

    ClearCursor()
    for slot = 1, MAX_ACTION_BUTTONS do
        if slot < POSSESSION_START or slot > POSSESSION_END then
            local spellId = getSpellIdFromActionSlot(slot)
            if spellId then
                local target = replacements[spellId]
                if target then
                    local bIdx = bookIndex[target]
                    if bIdx then
                        PickupSpell(bIdx, BOOKTYPE_SPELL)
                        if GetCursorInfo() == "spell" then
                            PlaceAction(slot)
                            changed = true
                        end
                        ClearCursor()
                    end
                end
            end
        end
    end
    ClearCursor()

    if changed then
        refreshAllButtons()
    end
end

SpellPlacementService.DowngradeLockedActions = downgradeLockedActions

if SpellBookFrame then
    SpellBookFrame:HookScript("OnShow", refreshSpellBook)
    SpellBookFrame:HookScript("OnEvent", function(self, event)
        refreshSpellBook()
    end)
end

if type(SpellButton_UpdateButton) == "function" and type(hooksecurefunc) == "function" then
    hooksecurefunc("SpellButton_UpdateButton", applySpellBookButton)
end

if SpellBookPrevPageButton then
    SpellBookPrevPageButton:HookScript("OnClick", function() refreshSpellBook() end)
end
if SpellBookNextPageButton then
    SpellBookNextPageButton:HookScript("OnClick", function() refreshSpellBook() end)
end
for i = 1, 8 do
    local tab = _G["SpellBookSkillLineTab" .. i]
    if tab then
        tab:HookScript("OnClick", function()
            for j = 1, SPELLS_PER_PAGE do
                local b = _G["SpellButton" .. j]
                if b then b.__EbonholdLogged = nil end
            end
            refreshSpellBook()
        end)
    end
end

local function appendTooltipRequirement(tooltip)
    local _, link = tooltip:GetItem()
    local spellId
    local name, _, id = tooltip:GetSpell()
    if id then
        spellId = id
    elseif name then
        spellId = select(7, GetSpellInfo(name))
    end
    if not spellId then return end

    local required = requirements[spellId]
    if not required and name then
        required = requirementsByName[name]
    end
    if not required then return end

    local playerLevel = UnitLevel("player") or 1
    if playerLevel >= required then return end

    tooltip:AddLine("Requires level " .. required, 1, 0.1, 0.1)
    tooltip:Show()
end

if GameTooltip then
    GameTooltip:HookScript("OnTooltipSetSpell", appendTooltipRequirement)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
frame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
frame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LEVEL_UP" or event == "SPELLS_CHANGED" then
        loadRequirementsFromConfigTable()
        downgradeLockedActions()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "UPDATE_BONUS_ACTIONBAR" then
        -- Combat ended or the vehicle/possess bar was dismissed: retry a deferred
        -- downgrade now that mutating the bars is safe again.
        if pendingDowngrade and not InCombatLockdown() and not isBarOverridden() then
            pendingDowngrade = false
            downgradeLockedActions()
        end
    end
    refreshAllButtons()
    refreshSpellBook()
end)

loadRequirementsFromConfigTable()
downgradeLockedActions()
refreshAllButtons()
refreshSpellBook()
