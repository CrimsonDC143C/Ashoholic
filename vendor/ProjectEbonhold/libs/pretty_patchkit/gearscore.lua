-- Embedded in Project Ebonhold (libs/pretty_patchkit); the only copy that runs (see
-- localization.lua for the standalone addon).

-- GearScoreLite, author Mirrikat45;
local namespace = select(2,...);

local _G = _G;
local tonumber = tonumber;
local format = string.format;
local floor = math.floor;
local UnitName = UnitName;
local UnitIsPlayer = UnitIsPlayer;
local UnitClass = UnitClass;
local GetInventoryItemLink = GetInventoryItemLink;
local GetUnit = GetUnit;
local GetItemInfo = GetItemInfo;
local GameTooltip = GameTooltip;
local CanInspect = CanInspect;
local IsEquippableItem = IsEquippableItem;
local NotifyInspect = NotifyInspect;
local ShoppingTooltip1 = ShoppingTooltip1;
local ShoppingTooltip2 = ShoppingTooltip2;
local ItemRefTooltip = ItemRefTooltip;

-- @callback;
local gearTypes = namespace.gearTypes;
local formulaA = namespace.formula["A"];
local formulaB = namespace.formula["B"];
local gearQuality = namespace.gearQuality;
local itemUpgradeInfo = LibStub("LibItemUpgradeInfo-1.0");

-- rounded numbers;
local function formatValue(value)
    if value < 1000 then
		return string.format('%.0f', value);
    elseif value < 1000000 then
		return string.format('%.1fk', value / 1000);
    elseif value < 1000000000 then
		return string.format('%.1fm', value / 1000000);
    elseif value < 1000000000000 then
		return string.format('%.1fb', value / 1000000000);
    else
		return string.format('%.1ft', value / 1000000000000);
	end
end

-- get quality;
local function findScoreQuality(itemScore)
	if (itemScore > 5999) then itemScore = 5999; end
	
	local r, g, b = 0.1, 0.1, 0.1;
	if not (itemScore) then
		return 0, 0, 0, "Trash"
	end
	
	for i = 0, 6 do
		if (itemScore > i*1000) and (itemScore <= ((i+1)*1000)) then
			local r = gearQuality[(i+1)*1000].r["A"]+(((itemScore-gearQuality[(i+1)*1000].r["B"])*gearQuality[(i+1)*1000].r["C"])*gearQuality[(i+1)*1000].r["D"]);
			local g = gearQuality[(i+1)*1000].g["A"]+(((itemScore-gearQuality[(i+1)*1000].g["B"])*gearQuality[(i+1)*1000].g["C"])*gearQuality[(i+1)*1000].g["D"]);
			local b = gearQuality[(i+1)*1000].b["A"]+(((itemScore-gearQuality[(i+1)*1000].b["B"])*gearQuality[(i+1)*1000].b["C"])*gearQuality[(i+1)*1000].b["D"]);
			return r, g, b, gearQuality[(i+1)*1000].Description;
		end
	end
	return 0.5, 0.5, 0.5;
end

-- item enchant;
local function findeEnchantInfo(itemLink, equipLoc)
	if itemlink then
		local found, _, itemSubString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]");
		local itemSubStringTable = {};

		for v in string.gmatch(itemSubString, "[^:]+") do
			tinsert(itemSubStringTable, v);
		end
		
		itemSubString = itemSubStringTable[2]..":"..itemSubStringTable[3], itemSubStringTable[2];
		local stringStart, stringEnd = string.find(itemSubString, ":");
		itemSubString = string.sub(itemSubString, stringStart + 1);
	end
	
	if (itemSubString == "0" and gearTypes[equipLoc]["enchant"]) then
		local percent = (floor((-2 * (gearTypes[equipLoc]["slot"]))*100)/100);
		return(1+(percent/100));
	else
		return 1;
	end
end

-- get item score;
local function findItemScore(itemLink)
	local qualityScale = 1;
	local pvpScale = 1;
	local pvpScore = 0;
	local GearScore = 0;
	
	if not (itemLink) then return 0, 0; end
	local itemName, itemLink, rarity, itemLevel, _, _, _, _, equipLoc = GetItemInfo(itemLink);
	local newtable = {};
	local scale = 1.8618;
 	
	if (rarity == 5) then
		qualityScale = 1.3;
		rarity = 4;
	elseif (rarity == 1) then
		qualityScale = 0.005;
		rarity = 2;
	elseif (rarity == 0) then
		qualityScale = 0.005;
		rarity = 2;
	end
    
	if (rarity == 7) then
		rarity = 3;
		itemLevel = 187.05;
	end
    
	if (gearTypes[equipLoc]) then
        if (itemLevel > 120) then
			newtable = formulaA;
		else
			newtable = formulaB;
		end
		if (rarity >= 2) and (rarity <= 4) then
			local r, g, b = findScoreQuality((floor(((itemLevel-newtable[rarity].A)/newtable[rarity].B) * 1 * scale)) * 11.25);
			GearScore = floor(((itemLevel-newtable[rarity].A)/newtable[rarity].B)*gearTypes[equipLoc]["slot"] * scale * qualityScale);
			
			if (itemLevel == 187.05) then
				itemLevel = 0;
			end
			if (GearScore < 0) then
				GearScore = 0;
				r, g, b = findScoreQuality(1);
			end
			if (pvpScale == 0.75) then
				pvpScore = 1;
				GearScore = GearScore * 1; 
			else
				pvpScore = GearScore * 0;
			end
			
			local percent = (findeEnchantInfo(itemLink, equipLoc) or 1);
			GearScore = floor(GearScore * percent);
			pvpScore = floor(pvpScore);
			return GearScore, itemLevel, gearTypes[equipLoc]["itemSlot"], r, g, b, pvpScore, equipLoc, percent;
		end
	end
	return -1, itemLevel, 50, 1, 1, 1, pvpScore, equipLoc, 1;
end

local function findItemLevel(who)
	local tilvl = 0;
	local numItems = 16;
	local ilvl;
	for i = 1, 18 do
		-- slot 4 = shirt, never counted (not in numItems either): same rule as the Call Board.
		local itemlink = (i ~= 4) and GetInventoryItemLink(who,i);
		if (itemlink) then
			if (i == 17) then
				numItems = numItems+1;
			end
			-- find ilvl;
			ilvl = itemUpgradeInfo:GetUpgradedItemLevel(itemlink);
			if (not ilvl) then ilvl = 0; end
			if (ilvl == 1) then
				ilvl = namespace.findHeirloomilvl(itemlink);
			end
			if (ilvl) then
				tilvl = tilvl + ilvl;
			end
		end
	end
	local itemLevel = floor((tilvl / numItems) * 100 * 0.01);
	return itemLevel;
end

-- get mouseover score;
local function findGearScore(name, who)
	if (UnitIsPlayer(who)) then
	    local _, class = UnitClass(who);
		local iLvl = findItemLevel(who);
		local gearScore = 0;
		local itemCount = 0;
		local titanGrip = 1;
		local tempScore;

		if (GetInventoryItemLink(who, 16)) and (GetInventoryItemLink(who, 17)) then
			local itemName, _, _, itemLevels, _, _, _, _, equipLoc = GetItemInfo(GetInventoryItemLink(who, 16));
            if (equipLoc == "INVTYPE_2HWEAPON") then
				titanGrip = 0.5;
			end
		end

		if (GetInventoryItemLink(who, 17)) then
			local itemName, _, _, itemLevels, _, _, _, _, equipLoc = GetItemInfo(GetInventoryItemLink(who, 17));
			if (equipLoc == "INVTYPE_2HWEAPON") then
				titanGrip = 0.5;
			end
			tempScore, itemLevels = findItemScore(GetInventoryItemLink(who, 17));
			
			if (class == "HUNTER") then
				tempScore = tempScore * 0.3164;
			end
			
			gearScore = gearScore + tempScore * titanGrip;
			itemCount = itemCount + 1;
		end
		
		for i = 1, 18 do
			if (i ~= 4) and (i ~= 17) then
				local itemLink = GetInventoryItemLink(who, i);
				if (itemLink) then
					local itemName, _, _, itemLevels, _, _, _, _, equipLoc = GetItemInfo(itemLink);
					tempScore = findItemScore(itemLink);
					
					if (i == 16 and class == "HUNTER") then
						tempScore = tempScore * 0.3164;
					end
					if (i == 18 and class == "HUNTER") then
						tempScore = tempScore * 5.3224;
					end
					if (i == 16) then
						tempScore = tempScore * titanGrip;
					end
					
					gearScore = gearScore + tempScore;
					itemCount = itemCount + 1;
				end
			end
		end

		if (gearScore <= 0) and (name ~= UnitName("player")) then
			gearScore = 0;
			return 0,0;
		elseif (name == UnitName("player")) and (gearScore <= 0) then
		    gearScore = 0;
		end
		
		if (itemCount == 0) then totalLevel = 0; end
		return floor(tonumber(gearScore)), floor(tonumber(iLvl));
	end
end

-- hook set unit;
-- local mouseOver, average;
local function GearScore_HookSetUnit()
	if (unitInCombat) then return; end
	
	local name = GameTooltip:GetUnit();
	local mouseOver, average = 0, 0;
	if (CanInspect("mouseover")) and (UnitName("mouseover") == name) and (not unitInCombat) then
		NotifyInspect("mouseover");
		mouseOver, average = findGearScore(name, "mouseover");
	end
 	
	local FORMAT_GEAR_SCORE = "("..GS_ITEM_LEVEL_TIP.."%d)"
	local FORMAT_GEAR_SCORE_OVER = "GearScore: "..mouseOver;
	if (mouseOver and mouseOver > 0 and _data.tooltipScore) then 
		local r, g, b = findScoreQuality(mouseOver);
		if (_data.itemLvlTip) then 
			GameTooltip:AddDoubleLine(FORMAT_GEAR_SCORE_OVER,(FORMAT_GEAR_SCORE):format(average), r, g, b, r, g, b);
		else
			GameTooltip:AddLine(FORMAT_GEAR_SCORE_OVER, r, g, b);
		end
		if (_data.compare) then
			local myGearScore = findGearScore(UnitName("player"), "player");
			local curscore = GS_YOUR_SCORE..myGearScore;
			local theirGearScore = mouseOver;
			if (myGearScore > theirGearScore) then
				GameTooltip:AddDoubleLine(curscore,("(+%d)"):format(myGearScore-theirGearScore), 0,1,0,0,1,0);
			end
			if (myGearScore < theirGearScore) then
				GameTooltip:AddDoubleLine(curscore,("(-%d)"):format(theirGearScore-myGearScore), 1,0,0,1,0,0);
			end	
			if (myGearScore == theirGearScore) then
				GameTooltip:AddDoubleLine(curscore, "(+0)", 0,1,1,0,1,1);
			end	
		end
	end
end

-- Item tooltips: the GearScore line (and its "iLevel" twin) was removed, the client already
-- prints "Item Level N" on every item. Only the player tooltip keeps a score.

-- create paperdoll font string;
function namespace.formatGearScore(who)
	if not (who) then
		return;
	end
	
	if (unitInCombat or not _data.GearScore) then
		return;
	end
	
	local unitGS = findGearScore(UnitName(who), who) or 0;
	local r, g, b = findScoreQuality(unitGS);
	
	if (_data.GearScoreFormat) then
		unitGS = formatValue(unitGS);
	else
		unitGS = unitGS;
	end

	return unitGS, r, g, b;
end

-- onload;
local function GearScore_OnEvent(self, event)
	if (event == "PLAYER_REGEN_ENABLED") then
		unitInCombat = false;
		return
	end
	if (event == "PLAYER_REGEN_DISABLED") then
		unitInCombat = true;
		return
	end
end

-- namespace.findItemLevel = findItemLevel

-- events;
local f = CreateFrame("Frame");
f:SetScript("OnEvent", GearScore_OnEvent);
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
f:RegisterEvent("PLAYER_REGEN_ENABLED");
f:RegisterEvent("PLAYER_REGEN_DISABLED");

GameTooltip:HookScript("OnTooltipSetUnit", GearScore_HookSetUnit);

-- The stock GearScoreLite replaced GameTooltip.SetInventoryItem here to fire NotifyInspect on
-- every paperdoll hover, through the global origSetInventoryItem. Removed: it inspected the
-- target for nothing, and with a second copy loaded the two wrappers called each other.

CharacterItemLevelFrame:HookScript("OnEnter", function(self)
	self.ilevel = findItemLevel("player");
	if self.ilevel then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(format(PAPERDOLLFRAME_ILEVEL_TOOLTIP_1, self.ilevel), 1.0, 1.0, 1.0);
		GameTooltip:AddLine(STAT_AVERAGE_ITEM_LEVEL_TOOLTIP, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1);
		GameTooltip:Show();
	end
end);