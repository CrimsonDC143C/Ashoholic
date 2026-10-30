ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.ActionBarSaver = {}
local ABS = ProjectEbonhold.ActionBarSaver

-- =============================================================
-- Adapted 1:1 Logic from ActionBarSaver (Shadowed)
-- =============================================================

local spellCache, macroCache, macroNameCache = {}, {}, {}
local playerClass
local MAX_MACROS = 54
local MAX_ACTION_BUTTONS = 144
local POSSESSION_START = 121
local POSSESSION_END = 132
local BOOKTYPE_SPELL = "spell"

-- While the player is in a vehicle (or possessing a unit), the action bar is
-- overridden by the vehicle/possess bar. Saving or restoring during that state
-- captures/overwrites the wrong slots and corrupts the player's real bars on
-- exit. Mirror the guard already used by the skill-tree micro button.
local function IsBarOverridden()
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then return true end
    if UnitInVehicle and UnitInVehicle("player") then return true end
    if UnitControllingVehicle and UnitControllingVehicle("player") then return true end
    -- Possessed turrets (e.g. the ICC gunship cannons) drive the possess bar,
    -- which can be active without the full vehicle UI.
    if IsPossessBarVisible and IsPossessBarVisible() then return true end
    if PossessBarFrame and PossessBarFrame:IsShown() then return true end
    return false
end

-- Re-implement string.split for WoW 3.3.5 environment correctness if missing
local function strsplit(delimiter, text)
  local list = {}
  local pos = 1
  if string.find("", delimiter, 1) then return end
  while 1 do
    local first, last = string.find(text, delimiter, pos)
    if first then
      table.insert(list, string.sub(text, pos, first-1))
      pos = last+1
    else
      table.insert(list, string.sub(text, pos))
      break
    end
  end
  return unpack(list)
end

-- Timer System
local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
local timers = {}
timerFrame:SetScript("OnUpdate", function(self, elapsed)
    if ProjectEbonhold_IsClosing then self:Hide() return end
    elapsed = math.min(elapsed, 0.1) -- Cap elapsed to prevent freeze after alt-tab
    local i = 1
    while i <= #timers do
        local t = timers[i]
        t.delay = t.delay - elapsed
        if t.delay <= 0 then
            table.remove(timers, i)
            if t.func then 
                local success, err = pcall(t.func) 
                if not success then geterrorhandler()(err) end
            end
        else
            i = i + 1
        end
    end
    if #timers == 0 then self:Hide() end
end)
local function TimerAfter(delay, func)
    table.insert(timers, { delay = delay, func = func })
    timerFrame:Show()
end

-- Text "compression"
function ABS:CompressText(text)
	text = string.gsub(text, "\n", "/n")
	text = string.gsub(text, "/n$", "")
	text = string.gsub(text, "||", "/124")
	return string.trim(text)
end

function ABS:UncompressText(text)
	text = string.gsub(text, "/n", "\n")
	text = string.gsub(text, "/124", "|")
	return string.trim(text)
end

function ABS.Init()
    playerClass = select(2, UnitClass("player"))
    
    ActionBarSaverDB = ActionBarSaverDB or {}
    ActionBarSaverDB.sets = ActionBarSaverDB.sets or {}
    ActionBarSaverDB.sets[playerClass] = ActionBarSaverDB.sets[playerClass] or {}
    
    ABS.db = ActionBarSaverDB

    -- Initial restore attempt
    TimerAfter(2, function() ABS:RestoreProfile("AutoSave", playerClass) end)
    
    -- Start periodic saving (every 5s)
    ABS.StartPeriodicSaver()
end

function ABS.StartPeriodicSaver()
    -- Safety: Do not auto-save at Level 1. This prevents overwriting a high-level profile 
    -- with empty bars when the character is reset/prestiged.
    if UnitLevel("player") > 1 then
        ABS:SaveProfile("AutoSave")
    end
    TimerAfter(5, ABS.StartPeriodicSaver)
end

function ABS.IsEnabled()
    if ProjectEbonholdOptionsService then
        return ProjectEbonholdOptionsService:GetSetting("autoPlaceSpells")
    end
    return true
end

-- 1:1 Logic: Save Profile (adapted for automation)
function ABS:SaveProfile(name)
    if not ABS.IsEnabled() or not ABS.db then return end
    if IsBarOverridden() then return end

	self.db.sets[playerClass][name] = self.db.sets[playerClass][name] or {}
	local set = self.db.sets[playerClass][name]
	
	for actionID=1, MAX_ACTION_BUTTONS do
		set[actionID] = nil
		
		local type, id, subType, extraID = GetActionInfo(actionID)
		if( type and id and ( actionID < POSSESSION_START or actionID > POSSESSION_END ) ) then
			if( type == "companion" ) then
				set[actionID] = string.format("%s|%s|%s|%s|%s|%s", type, id, "", name, subType, extraID)
			elseif( type == "equipmentset" ) then
				set[actionID] = string.format("%s|%s|%s", type, id, "")
			elseif( type == "item" ) then
				set[actionID] = string.format("%s|%d|%s|%s", type, id, "", (GetItemInfo(id)) or "")
			elseif( type == "spell" and id > 0 ) then
				local spell, rank = GetSpellName(id, BOOKTYPE_SPELL)
				if( spell ) then
					set[actionID] = string.format("%s|%d|%s|%s|%s|%s", type, id, "", spell, rank or "", extraID or "")
				end
			elseif( type == "macro" ) then
				local name, icon, macro = GetMacroInfo(id)
				if( name and icon and macro ) then
					set[actionID] = string.format("%s|%d|%s|%s|%s|%s", type, actionID, "", self:CompressText(name), icon, self:CompressText(macro))
				end
			end
		end
	end
end

-- 1:1 Logic: Restore Profile
function ABS:RestoreProfile(name, overrideClass)
    if not ABS.IsEnabled() then return end
    
	local set = self.db.sets[overrideClass or playerClass][name]
	if( not set ) then return end
	if( InCombatLockdown() ) then return end
	if( IsBarOverridden() ) then return end
	
	table.wipe(spellCache)
	
	-- Cache spells
	for book=1, MAX_SKILLLINE_TABS do
		local _, _, offset, numSpells = GetSpellTabInfo(book)
		for i=1, numSpells do
			local index = offset + i
			local spell, rank = GetSpellName(index, BOOKTYPE_SPELL)
			spellCache[spell] = index
			spellCache[string.lower(spell)] = index
			if( rank and rank ~= "" ) then
				spellCache[spell .. rank] = index
			end
		end
	end
	
	ClearCursor()

	for i=1, MAX_ACTION_BUTTONS do
		if( i < POSSESSION_START or i > POSSESSION_END ) then
			local type, id = GetActionInfo(i)
		
            -- MODIFICATION: Only restore if slot is empty to adhere to "don't mess up my bars"
			if not (id or type) then
                if( set[i] ) then
                    self:RestoreAction(i, strsplit("|", set[i]))
                end
            end
		end
	end
end

function ABS:RestoreAction(i, type, actionID, binding, ...)
	if( type == "spell" ) then
		local spellName, spellRank = ...
        -- Logic: Try explicit rank first if exists, else generic
		if( spellRank ~= "" and spellCache[spellName .. spellRank] ) then
			PickupSpell(spellCache[spellName .. spellRank], BOOKTYPE_SPELL)
		elseif( spellCache[spellName] ) then
			PickupSpell(spellCache[spellName], BOOKTYPE_SPELL)
		end
		
		if( GetCursorInfo() == type ) then
    		PlaceAction(i)
        end
        ClearCursor()
	elseif( type == "item" ) then
		PickupItem(actionID)
		if( GetCursorInfo() == type ) then
    		PlaceAction(i)
        end
        ClearCursor()
	elseif( type == "macro" ) then
        -- Macro restoration skipped for simplicity in auto-mode to avoid spamming creates
        -- unless specifically requested, but basic pickup works if macro exists
        PickupMacro(actionID) 
        if( GetCursorInfo() == type ) then
            PlaceAction(i)
        end
        ClearCursor()
	end
end


local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, arg1)  
    if event == "ADDON_LOADED" and arg1 == "ProjectEbonhold" then
        ABS.Init()
    elseif event == "PLAYER_LEVEL_UP" or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        TimerAfter(0.5, function() ABS:RestoreProfile("AutoSave", playerClass) end)
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("LEARNED_SPELL_IN_TAB")
