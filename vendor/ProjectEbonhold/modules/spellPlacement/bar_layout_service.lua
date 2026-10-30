-- =============================================================
-- Bar Layout Management
-- Save / load / delete named action bar layouts.
-- Storage piggybacks on ActionBarSaverDB (per-character SavedVariable)
-- under a separate "layouts" namespace so it does not collide with
-- the AutoSave profile used by ActionBarSaver. Layouts are stored
-- per character (ActionBarSaverDB is SavedVariablesPerCharacter).
-- =============================================================

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.BarLayoutService = ProjectEbonhold.BarLayoutService or {}

local Service = ProjectEbonhold.BarLayoutService

local MAX_ACTION_BUTTONS = 144
local POSSESSION_START   = 121
local POSSESSION_END     = 132
local BOOKTYPE_SPELL     = "spell"

-- Vehicle/possess bar active => the action slots are overridden; saving or
-- loading a layout in that state captures/writes the wrong slots.
local function isBarOverridden()
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then return true end
    if UnitInVehicle and UnitInVehicle("player") then return true end
    if UnitControllingVehicle and UnitControllingVehicle("player") then return true end
    -- Possessed turrets (e.g. the ICC gunship cannons) use the possess bar.
    if IsPossessBarVisible and IsPossessBarVisible() then return true end
    if PossessBarFrame and PossessBarFrame:IsShown() then return true end
    return false
end

local function compress(text)
    text = string.gsub(text or "", "\n", "/n")
    text = string.gsub(text, "/n$", "")
    text = string.gsub(text, "||", "/124")
    return string.trim(text)
end

local function strsplitPipe(text)
    local out = {}
    local pos = 1
    while true do
        local s, e = string.find(text, "|", pos, true)
        if s then
            table.insert(out, string.sub(text, pos, s - 1))
            pos = e + 1
        else
            table.insert(out, string.sub(text, pos))
            break
        end
    end
    return out
end

local function ensureDB()
    ActionBarSaverDB = ActionBarSaverDB or {}
    ActionBarSaverDB.layouts = ActionBarSaverDB.layouts or {}
    return ActionBarSaverDB.layouts
end

-- Returns a sorted array of layout names for the current class.
function Service:GetLayoutNames()
    local store = ensureDB()
    local names = {}
    for name in pairs(store) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end

function Service:HasLayout(name)
    if not name or name == "" then return false end
    local store = ensureDB()
    return store[name] ~= nil
end

-- Snapshot every action button into a serialized string table.
function Service:SaveLayout(name)
    if type(name) ~= "string" or name == "" then return false, "Invalid name" end
    if isBarOverridden() then return false, "Cannot save layout while in a vehicle" end
    local store = ensureDB()
    local set = {}

    for actionID = 1, MAX_ACTION_BUTTONS do
        if actionID < POSSESSION_START or actionID > POSSESSION_END then
            local actionType, id, subType, extraID = GetActionInfo(actionID)
            if actionType and id then
                if actionType == "companion" then
                    set[actionID] = string.format("%s|%s|%s|%s|%s|%s",
                        actionType, id, "", name, tostring(subType or ""), tostring(extraID or ""))
                elseif actionType == "equipmentset" then
                    set[actionID] = string.format("%s|%s|%s", actionType, id, "")
                elseif actionType == "item" then
                    set[actionID] = string.format("%s|%d|%s|%s",
                        actionType, id, "", (GetItemInfo(id)) or "")
                elseif actionType == "spell" and id > 0 then
                    local spell, rank = GetSpellName(id, BOOKTYPE_SPELL)
                    if spell then
                        set[actionID] = string.format("%s|%d|%s|%s|%s|%s",
                            actionType, id, "", spell, rank or "", tostring(extraID or ""))
                    end
                elseif actionType == "macro" then
                    local mname, micon, mbody = GetMacroInfo(id)
                    if mname and micon and mbody then
                        set[actionID] = string.format("%s|%d|%s|%s|%s|%s",
                            actionType, actionID, "", compress(mname), micon, compress(mbody))
                    end
                end
            end
        end
    end

    store[name] = set
    return true
end

local function clearAllSlots()
    ClearCursor()
    for i = 1, MAX_ACTION_BUTTONS do
        if i < POSSESSION_START or i > POSSESSION_END then
            local t = GetActionInfo(i)
            if t then
                PickupAction(i)
                ClearCursor()
            end
        end
    end
end

local function buildSpellCache()
    local cache = {}
    for book = 1, MAX_SKILLLINE_TABS do
        local _, _, offset, numSpells = GetSpellTabInfo(book)
        for i = 1, numSpells do
            local index = offset + i
            local spell, rank = GetSpellName(index, BOOKTYPE_SPELL)
            if spell then
                cache[spell]                = index
                cache[string.lower(spell)]  = index
                if rank and rank ~= "" then
                    cache[spell .. rank]    = index
                end
            end
        end
    end
    return cache
end

local function placeOne(slot, fields, spellCache)
    local actionType = fields[1]
    local actionID   = fields[2]

    if actionType == "spell" then
        local spellName = fields[4] or ""
        local spellRank = fields[5] or ""
        local idx
        if spellRank ~= "" and spellCache[spellName .. spellRank] then
            idx = spellCache[spellName .. spellRank]
        elseif spellCache[spellName] then
            idx = spellCache[spellName]
        end
        if idx then
            PickupSpell(idx, BOOKTYPE_SPELL)
            if GetCursorInfo() == "spell" then
                PlaceAction(slot)
            end
        end
        ClearCursor()
    elseif actionType == "item" then
        local itemId = tonumber(actionID)
        if itemId then
            PickupItem(itemId)
            if GetCursorInfo() == "item" then
                PlaceAction(slot)
            end
        end
        ClearCursor()
    elseif actionType == "macro" then
        local macroId = tonumber(actionID)
        if macroId then
            PickupMacro(macroId)
            if GetCursorInfo() == "macro" then
                PlaceAction(slot)
            end
        end
        ClearCursor()
    elseif actionType == "equipmentset" then
        if type(PickupEquipmentSetByName) == "function" then
            PickupEquipmentSetByName(actionID)
            if GetCursorInfo() == "equipmentset" then
                PlaceAction(slot)
            end
        end
        ClearCursor()
    end
end

-- Fully replace the current action bar contents with the named layout.
function Service:LoadLayout(name)
    if InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Project Ebonhold]|r Cannot switch bar layout while in combat.")
        end
        return false
    end

    if isBarOverridden() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Project Ebonhold]|r Cannot switch bar layout while in a vehicle.")
        end
        return false
    end

    local store = ensureDB()
    local set = store[name]
    if not set then return false end

    clearAllSlots()
    local spellCache = buildSpellCache()

    for slot = 1, MAX_ACTION_BUTTONS do
        if (slot < POSSESSION_START or slot > POSSESSION_END) and set[slot] then
            local fields = strsplitPipe(set[slot])
            placeOne(slot, fields, spellCache)
        end
    end

    ClearCursor()
    return true
end

function Service:DeleteLayout(name)
    local store = ensureDB()
    if store[name] then
        store[name] = nil
        return true
    end
    return false
end

function Service:RenameLayout(oldName, newName)
    if not newName or newName == "" then return false end
    local store = ensureDB()
    if not store[oldName] or store[newName] then return false end
    store[newName] = store[oldName]
    store[oldName] = nil
    return true
end
