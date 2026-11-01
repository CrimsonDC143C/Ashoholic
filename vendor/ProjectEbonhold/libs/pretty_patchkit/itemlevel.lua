-- Embedded in Project Ebonhold (libs/pretty_patchkit); the only copy that runs (see
-- localization.lua for the standalone addon).

-- KibsItemLevel, author Kibsgaard;
-- https://www.curseforge.com/wow/addons/kibs-item-level
local namespace = select(2,...);
LoadAddOn("LibItemUpgradeInfo-1.0");

local _G = _G;
local tonumber = tonumber;
local UIParent = UIParent;
local CreateFrame = CreateFrame;
local charFS = {};
local inspectFS = {};
local activeFS = {};
local charIcons = {};
local inspectIcons = {};
local activeIcons = {};
local enchantIcons = {};
local inspectEnchantIcons = {};
local activeEnchantIcons = {};
local iconSize = 16;
local iconOffset = 18;
local fontStyle = "SystemFont_Small";
local updateInProgress = false;
-- Set when a player scan was skipped because the paperdoll was not on screen,
-- so the numbers get refreshed the next time it is opened. Declared up here,
-- above iLevel_OnShow, so both it and eventHandler close over the same local.
local pendingPlayerUpdate = false;
local updateInProgressInspect = false;
local GetItemIcon = GetItemIcon;
local GetItemInfo = GetItemInfo;
local GetInventoryItemLink = GetInventoryItemLink;
local GetName = GetName;
local GameTooltip = GameTooltip;
local str_find = string.find;
local str_match = string.gmatch;
local str_sub = string.sub;
local format = string.format;

-- globals;
local kitsLoadFrame = CreateFrame("Frame", nil, PaperDollFrame);
local ilvlFrame = CreateFrame("Frame");
local itemUpgradeInfo = LibStub("LibItemUpgradeInfo-1.0");
local enchatIcons = "INTERFACE/ICONS/inv_misc_enchantedscroll";

local emptySockets = {
	["Meta "]    	= "INTERFACE/ITEMSOCKETINGFRAME/UI-EmptySocket-Meta",
	["Red "]     	= "INTERFACE/ITEMSOCKETINGFRAME/UI-EmptySocket-Red",
	["Blue "]    	= "INTERFACE/ITEMSOCKETINGFRAME/UI-EmptySocket-Blue",
	["Yellow "] 	= "INTERFACE/ITEMSOCKETINGFRAME/UI-EmptySocket-Yellow",
	["Prismatic "]	= "INTERFACE/ITEMSOCKETINGFRAME/UI-EmptySocket-Prismatic",
};

local enchantableItems = {
	[1]  = true,  [2]  = nil,  [3]  = true,  [15] = true, [5]  = true, [9]  = true,
	[10] = true,  [6]  = nil,  [7]  = true,  [8]  = true, [11] = nil,  [12] = nil,
	[13] = nil,   [14] = nil,  [16] = true,  [17] = true, [18] = nil
};

local function findSockets(who,slot)
	local itemLink = GetInventoryItemLink(who,slot);
	local _, _, _, _, itemID = str_find(itemLink, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?");

	if (itemID) then
		-- SOCKETS;
		local _,cleanItemLink = GetItemInfo(itemID);
		if (cleanItemLink) then
			local scanTip = namespace.scanTip;
			namespace.scanLink(cleanItemLink);

			local line;
			local texturePath;
			local GemSocketID = (slot - 1) * 3 + 1;
			local sockets = GemSocketID;
			
			for i = 1, 3 do
				activeIcons[i+GemSocketID-1].texture:SetAlpha(0.0);						
			end
			
			for i = 2, scanTip:NumLines() do
				line = _G["PatchkitScanTooltipTextLeft"..i];
				if (line) then
					line = line:GetText();
					if (line) then
						if(line:find("Socket")) then
							texturePath = emptySockets[line:sub(1, line:find("Socket") - 1)];
							if (texturePath) then
								activeIcons[sockets].texture:SetTexture(""..texturePath);
								activeIcons[sockets].texture:SetAlpha(1.0);
								sockets = sockets + 1;
							end
						end
					end
				end
			end
			
			-- GEMS;
			for i = 1, 3 do
				local _, itemLink = GetItemGem(GetInventoryItemLink(who,slot),i);
				if (itemLink) then
					activeIcons[i+GemSocketID-1].texture:SetTexture(GetItemIcon(itemLink));
					activeIcons[i+GemSocketID-1].texture:SetAlpha(1.0);
					activeIcons[i+GemSocketID-1]:SetScript("OnEnter",function(s,m)
						GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR");
						GameTooltip:SetHyperlink(itemLink);
						GameTooltip:Show(); 
					end);
					activeIcons[i+GemSocketID-1]:SetScript("OnLeave",function(s,m)
						GameTooltip:Hide(); 
					end);
				end
			end
		end
	end
end

local function getEnchant(itemlink,i)
	if itemlink then
		local found, _, itemSubString = str_find(itemlink, "^|c%x+|H(.+)|h%[.*%]");
		local itemSubStringTable = {};

		for v in str_match(itemSubString, "[^:]+") do
			tinsert(itemSubStringTable, v);
		end
		
		itemSubString = itemSubStringTable[2]..":"..itemSubStringTable[3], itemSubStringTable[2];
		local stringStart, stringEnd = str_find(itemSubString, ":");
		itemSubString = str_sub(itemSubString, stringStart + 1);
		hasEnchant = itemSubString ~= "0"
	end
	
	-- did we find any enchants?;
	if hasEnchant then
		activeEnchantIcons[i].texture:SetTexture(enchatIcons);
		activeEnchantIcons[i].texture:SetVertexColor(1.0, 1.0, 1.0, 1);
	else
		if _data.enchantCharMiss then
			activeEnchantIcons[i].texture:SetVertexColor(1.0, 0.2, 0.2, 1);
		else
			activeEnchantIcons[i].texture:SetVertexColor(0, 0, 0, 0);
		end
	end
end

local function findItemInfo(who)
	if not (who) then
		return
	end
	
	if (who == "player") then
		activeFS = charFS;
		activeIcons = charIcons;
		activeEnchantIcons = enchantIcons;
		-- updateInProgress is cleared at the END of this function, not here.
		-- Clearing it on the first line meant the "is an update already running"
		-- guard in eventHandler was false again before the scan had done any
		-- work, so it never actually coalesced anything.
	else
		activeFS = inspectFS;
		activeIcons = inspectIcons;
		activeEnchantIcons = inspectEnchantIcons;
		updateInProgressInspect = false;
	end
	
	local tilvl = 0;
	local numItems = 16;

	for i = 1, 18 do
		if (activeFS[i]) then
			local itemlink = GetInventoryItemLink(who,i);
			if (itemlink) then
				if (i == 17) then numItems = numItems+1; end

				-- find enchants;
				if (enchantableItems[i] and _data.enchantChar) then
					getEnchant(itemlink, i);
				end
				
				-- find gems;
				if (_data.gemsChar) then
					findSockets(who,i);
				end
				
				-- find ilvl;
				local upgrade, max, delta = itemUpgradeInfo:GetItemUpgradeInfo(itemlink);
				local ilvl = itemUpgradeInfo:GetUpgradedItemLevel(itemlink);
				
				if not(ilvl) then ilvl = 0; end
				
				if (ilvl == 1) then
					ilvl = namespace.findHeirloomilvl(itemlink);
				end
				
				if (upgrade and _data.upgrades) then
					activeFS[i]:SetText(ilvl .." ("..upgrade.."/"..max..")");
				else
					if (_data.ilvlChar) then
						activeFS[i]:SetText(ilvl);
					else
						activeFS[i]:SetText("");
					end
				end
				
				if (ilvl) then
					local color = namespace.itemLevelMixInGetColor(ilvl);
					if (_data.itemLevelColors) then
						activeFS[i]:SetTextColor(color.r, color.g, color.b, 1);
					else
						activeFS[i]:SetTextColor(1, 1, 1, 1);
					end
					-- shirt (slot 4) is shown but not averaged: same rule as the Call Board.
					if (i ~= 4) then tilvl = tilvl + ilvl; end
				end
			else
				if (charFS[i]) then
					activeFS[i]:SetText("");
					if (enchantableItems[i]) then
						activeEnchantIcons[i].texture:SetAlpha(0.0);
						activeEnchantIcons[i]:SetScript("OnEnter", nil);
					end
					local slotID = (i - 1) * 3 + 1;
					for j = slotID, slotID + 2 do
						activeIcons[j].texture:SetAlpha(0.0);
						activeIcons[j]:SetScript("OnEnter", nil);
					end
				end
			end
		end
	end
	
	local unitGS, GSr, GSg, GSb = namespace.formatGearScore(who);
	if (not unitGS) then
		unitGS = 0;
		GSr, GSg, GSb = 1, 1, 1;
	end

	local itemLevel = math.floor((tilvl/numItems) * 100 * 0.01);
	local ilvlColor = namespace.itemLevelMixInGetColor(itemLevel);
	if (not itemLevel) then
		itemLevel = 0;
		ilvlColor = 1, 1, 1;
	end
	if (_data.GearScore and _data.iLvlScore) then
		if (who ~= "player") then
			InspectItemLevelFrame.ilvltext:SetFormattedText("%s/%d", unitGS, itemLevel);
			InspectItemLevelFrame.ilvltext:SetTextColor(GSr, GSg, GSb);
		else
			CharacterItemLevelFrame.ilvltext:SetFormattedText("%s/%d", unitGS, itemLevel);
			CharacterItemLevelFrame.ilvltext:SetTextColor(GSr, GSg, GSb);
		end
	else
		-- The box sits under the "Item Level" title and its tooltip gives the item level, so it
		-- shows the item level. The old GearScore-only branch (the default) put the GearScore
		-- there instead, 0 for low-level or white gear, next to a tooltip saying otherwise.
		if (who ~= "player") then
			InspectItemLevelFrame.ilvltext:SetFormattedText("%d", itemLevel);
			InspectItemLevelFrame.ilvltext:SetTextColor(ilvlColor.r, ilvlColor.g, ilvlColor.b);
		else
			CharacterItemLevelFrame.ilvltext:SetFormattedText("%d", itemLevel);
			CharacterItemLevelFrame.ilvltext:SetTextColor(ilvlColor.r, ilvlColor.g, ilvlColor.b);
		end
	end

	if (who == "player") then
		updateInProgress = false;
	else
		updateInProgressInspect = false;
	end
end

local function updatePlayer()
	if (_data.enableChar) then
		findItemInfo("player");
	end
end

local function iLevel_OnShow(self,...)
	-- Read live: a local copy of namespace.variables_loaded was taken while it was still false
	-- and never changed, so this refresh never ran and the box kept its login-time value.
	if (namespace.variables_loaded) then
		if (_data.enableChar) then
			-- Whatever was skipped while the pane was closed is picked up here;
			-- this fires on PaperDollFrame's OnShow (kitsLoadFrame is its child).
			pendingPlayerUpdate = false;
			updateInProgress = true;
			updatePlayer();
		end
	end
end

-- One gear swap raises PLAYER_EQUIPMENT_CHANGED and UNIT_INVENTORY_CHANGED in the
-- same frame: the scan runs once, on the next frame, for both.
local scanSoon = CreateFrame("Frame");
scanSoon:Hide();
scanSoon:SetScript("OnUpdate", function(self)
	self:Hide();
	updatePlayer();
	updateInProgress = false;
end);

local function updateInspect()
	findItemInfo(InspectFrame.unit);
end

local function eventHandler(self,event,...)
	if (_data.enableConfig) then
		if (event == "PLAYER_TARGET_CHANGED" and ilvlFrame.inspectVisible and _data.enableInspect) then
			if (InspectFrame.unit and InspectFrame.unit == "target") then
				updateInspect();
			end
		elseif (event ~= "PLAYER_TARGET_CHANGED") then
			-- UNIT_INVENTORY_CHANGED fires for ANY unit, not just the player:
			-- every nearby player whose equipment data arrives raises one. This
			-- handler ignored arg1 entirely and ran a full player scan for each
			-- of them, so walking into a crowd -- a capital right after a
			-- teleport, or any fight with a lot of units around -- turned into
			-- one 18-slot scan per unit, back to back, in a single frame.
			if (event == "UNIT_INVENTORY_CHANGED") then
				local unit = ...;
				if (unit ~= "player") then return; end
			end

			-- Everything findItemInfo draws lives on the paperdoll
			-- (CharacterItemLevelFrame and the per-slot font strings). With the
			-- character pane closed the scan is 18 GameTooltip:SetHyperlink
			-- calls -- each one builds a complete tooltip: query the item,
			-- format every line, lay out the font strings, resize the frame --
			-- plus a socket pass that does it a second time per slot, plus a
			-- full GearScore pass, all to update text nobody can see. Defer.
			if (not PaperDollFrame or not PaperDollFrame:IsVisible()) then
				pendingPlayerUpdate = true;
				return;
			end

			if (updateInProgress == false) then
				updateInProgress = true;
				scanSoon:Show();
			end
		elseif (event == "PLAYER_EQUIPMENT_CHANGED") then
			updatePlayer();
		end
	end
end

-- layout helpers;
local slotID = { 1, 2, 3, 15, 5, 4, 18, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 };
local slotAlign1 = { "TOPLEFT","TOPLEFT","TOPLEFT","TOPLEFT","TOPLEFT","TOPRIGHT","TOPRIGHT","TOPRIGHT",
			"TOPLEFT","TOPRIGHT","TOPRIGHT","TOPRIGHT","TOPRIGHT","TOPRIGHT","TOPLEFT","BOTTOMRIGHT",
			"BOTTOMRIGHT","BOTTOMLEFT" };
local slotAlign2 = { "TOPRIGHT","TOPRIGHT","TOPRIGHT","TOPRIGHT","TOPRIGHT","TOPLEFT","TOPLEFT","TOPLEFT",
			"TOPRIGHT","TOPLEFT","TOPLEFT","TOPLEFT","TOPLEFT","TOPLEFT","TOPRIGHT","BOTTOMLEFT",
			"BOTTOMLEFT","BOTTOMRIGHT" };
local slotOffsetx = { 10, 10, 10, 10, 10, -10, -10, -10, 10, -10, -10, -10, -10, -10, 10, 33, 33, -33 };
local slotOffsety = { -5, -5, -5, -5, -5, -5, -5, -5, -5, -5, -5, -5, -5, -5, -5, 40, 40, 40 };
local iconAlign1 = { "TOPLEFT","TOPLEFT","TOPLEFT","TOPLEFT","TOPLEFT","TOPRIGHT","TOPRIGHT","TOPRIGHT",
			"TOPLEFT","TOPRIGHT","TOPRIGHT","TOPRIGHT","TOPRIGHT","TOPRIGHT","TOPLEFT","BOTTOMRIGHT",
			"BOTTOMRIGHT","BOTTOMRIGHT" };
local iconAlign2 = { "BOTTOMLEFT","BOTTOMLEFT","BOTTOMLEFT","BOTTOMLEFT","BOTTOMLEFT","BOTTOMRIGHT","BOTTOMRIGHT","BOTTOMRIGHT",
			"BOTTOMLEFT","BOTTOMRIGHT","BOTTOMRIGHT","BOTTOMRIGHT","BOTTOMRIGHT","BOTTOMRIGHT","BOTTOMLEFT","TOPRIGHT",
			"TOPRIGHT","TOPRIGHT" };
local iconOffsetx = { iconOffset, iconOffset, iconOffset, iconOffset, iconOffset, -iconOffset, -iconOffset, -iconOffset, 
			iconOffset, -iconOffset, -iconOffset, -iconOffset, -iconOffset, -iconOffset, iconOffset, -iconOffset, 
			-iconOffset, iconOffset };
local iconOffsety = { -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, iconOffset, iconOffset, iconOffset };

-- create font strings;
local charkids = { CharacterHeadSlot, CharacterNeckSlot, CharacterShoulderSlot, CharacterShirtSlot, CharacterChestSlot, CharacterWaistSlot, CharacterLegsSlot, CharacterFeetSlot, CharacterWristSlot, CharacterHandsSlot,
 CharacterFinger0Slot, CharacterFinger1Slot, CharacterTrinket0Slot, CharacterTrinket1Slot, CharacterBackSlot, CharacterMainHandSlot, CharacterSecondaryHandSlot, CharacterRangedSlot };
local function createCharKits()
	for i = 1, 18 do
		if not (i == 4) then -- exclude 4, shirt;
			local offset;
			local offsety;
			if (_data.enchantChar or _data.enchantCharMiss) then
				offset = iconOffsetx[i];
				offsety = iconOffsety[i]/7;
			else
				offset = 0;
				offsety = -iconOffset;
			end
			
			charFS[i] = charkids[i]:CreateFontString("iLvl_"..slotID[i], "OVERLAY", fontStyle);
			charFS[i]:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE");
			charFS[i]:SetText("");
			charFS[i]:SetPoint(slotAlign1[i], charkids[i], slotAlign2[i], slotOffsetx[i], slotOffsety[i]);
			
			if (enchantableItems[i]) then
				enchantIcons[i] = CreateFrame("Frame", "EnchantIcon"..i, charkids[i]);
				if (i ~= 16) and (i ~= 17) and (i ~= 18) then
					enchantIcons[i]:SetPoint(iconAlign1[i], charFS[i], iconAlign2[i], 0, iconOffsety[i]);
				else
					enchantIcons[i]:SetPoint(iconAlign1[i], charFS[i], iconAlign2[i], -5, offsety);
				end
				enchantIcons[i]:SetSize(iconSize,iconSize);

				local texture = enchantIcons[i]:CreateTexture("EnchantIconTex"..i, "OVERLAY");
				texture:SetAllPoints();
				enchantIcons[i].texture = texture;
				enchantIcons[i].texture:SetTexture(enchatIcons);
				enchantIcons[i].texture:SetAlpha(0.0);
				
				offsety = offsety + iconOffsety[i];
			end
			
			local iconSlotID = (i-1) * 3 + 1;
			for j = iconSlotID, iconSlotID + 2 do
				charIcons[j] = CreateFrame("Frame", "GemIcon"..j, charkids[i]);
				if (i ~= 16) and (i ~= 17) and (i ~= 18) then
					charIcons[j]:SetPoint(iconAlign1[i], charFS[i], iconAlign2[i], offset, iconOffsety[i]);
				else
					charIcons[j]:SetPoint(iconAlign1[i], charFS[i], iconAlign2[i], -5, offsety);
				end
				charIcons[j]:SetSize(iconSize,iconSize);
				
				local texture = charIcons[j]:CreateTexture("GemIconTex"..j, "OVERLAY");
				texture:SetAllPoints();
				charIcons[j].texture = texture;
				charIcons[j].texture:SetTexture(emptySockets["Prismatic "]);
				charIcons[j].texture:SetAlpha(0.0);
				
				offset = offset + iconOffsetx[i];
				offsety = offsety + iconOffsety[i];
			end
		end
	end
end

-- create font strings for the inspection window;
local inspkids = { InspectHeadSlot, InspectNeckSlot, InspectShoulderSlot, InspectShirtSlot, InspectChestSlot, InspectWaistSlot, InspectLegsSlot, InspectFeetSlot, InspectWristSlot, InspectHandsSlot,
 InspectFinger0Slot, InspectFinger1Slot, InspectTrinket0Slot, InspectTrinket1Slot, InspectBackSlot, InspectMainHandSlot, InspectSecondaryHandSlot, InspectRangedSlot };
local function createInspectKits()
	for i = 1, 18 do
		if not (i == 4) then -- exclude 4, shirt;
			local offset;
			local offsety;
			if (_data.enchantInsp or _data.enchantInspMiss) then
				offset = iconOffsetx[i];
				offsety = iconOffsety[i];
			else
				offset = 0;
				offsety = iconOffset;
			end
			
			inspectFS[i] = inspkids[i]:CreateFontString("iLvl_"..slotID[i], "ARTWORK", fontStyle);
			inspectFS[i]:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE");
			inspectFS[i]:SetText("");
			inspectFS[i]:SetPoint(slotAlign1[i], inspkids[i], slotAlign2[i] , slotOffsetx[i], slotOffsety[i]);
			
			if (enchantableItems[i]) then
				inspectEnchantIcons[i] = CreateFrame("Frame", "EnchantIcon"..i, inspkids[i]);
				if (i ~= 16) and (i ~= 17) and (i ~= 18) then
					inspectEnchantIcons[i]:SetPoint(iconAlign1[i], inspectFS[i], iconAlign2[i], 0, iconOffsety[i]);
				else
					inspectEnchantIcons[i]:SetPoint(iconAlign1[i], inspectFS[i], iconAlign2[i], -5, offsety + 2);
				end
				inspectEnchantIcons[i]:SetSize(iconSize,iconSize);

				local texture = inspectEnchantIcons[i]:CreateTexture("EnchantIconTex"..i, "ARTWORK");
				texture:SetAllPoints();
				inspectEnchantIcons[i].texture = texture;
				inspectEnchantIcons[i].texture:SetTexture(enchatIcons);
				inspectEnchantIcons[i].texture:SetAlpha(0.0);
				
				offsety = offsety + iconOffsety[i];
			end
			
			local iconSlotID = (i-1) * 3 + 1;
			for j = iconSlotID, iconSlotID + 2 do
				inspectIcons[j] = CreateFrame("Frame", "GemIcon"..j, inspkids[i]);
				if (i ~= 16) and (i ~= 17) and (i ~= 18) then
					inspectIcons[j]:SetPoint(iconAlign1[i], inspectFS[i], iconAlign2[i], offset, iconOffsety[i]);
				else
					inspectIcons[j]:SetPoint(iconAlign1[i], inspectFS[i], iconAlign2[i], -5, offsety);
				end
				inspectIcons[j]:SetSize(iconSize,iconSize);
				
				local texture = inspectIcons[j]:CreateTexture("GemIconTex"..j, "ARTWORK");
				texture:SetAllPoints();
				inspectIcons[j].texture = texture;
				inspectIcons[j].texture:SetTexture(emptySockets["Prismatic "]);
				inspectIcons[j].texture:SetAlpha(0.0);
				
				offset = offset + iconOffsetx[i];
				offsety = offsety + iconOffsety[i];
			end
		end
	end	
end

-- register event handler;
local function setupEventHandler(self,event)
	if (event == "VARIABLES_LOADED" or event == "PLAYER_LOGIN") then
		namespace.config_loaded();
		
		ilvlFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
		ilvlFrame:RegisterEvent("UNIT_INVENTORY_CHANGED");
		ilvlFrame:RegisterEvent("SOCKET_INFO_CLOSE");
		ilvlFrame:RegisterEvent("SOCKET_INFO_SUCCESS");
		ilvlFrame:RegisterEvent("SOCKET_INFO_UPDATE");
		ilvlFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
		ilvlFrame:RegisterEvent("PLAYER_TARGET_CHANGED");
		
		InspectFrame:SetScript("OnShow", function(self)
			ilvlFrame.inspectVisible = true;
			updateInspect();
		end);
		InspectFrame:SetScript("OnHide", function(self)
			ilvlFrame.inspectVisible = false;
		end);
		
		ilvlFrame:SetScript("OnEvent", eventHandler);
		kitsLoadFrame:SetScript("OnShow", iLevel_OnShow);
		
		if (_data.resist) then
			CharacterResistanceFrame:Hide();
		else
			CharacterResistanceFrame:Show();
		end

		createCharKits();
		createInspectKits();
		-- After the kits: findItemInfo only counts the slots that have a font string, so a scan
		-- run before createCharKits averaged nothing and wrote 0.
		if (_data.enableChar) then updatePlayer(); end
	end
end
ilvlFrame:RegisterEvent("VARIABLES_LOADED");
ilvlFrame:RegisterEvent("PLAYER_LOGIN");
ilvlFrame:SetScript("OnEvent", setupEventHandler);

function cleanUpiLvl()
	eventHandler(self, "PLAYER_EQUIPMENT_CHANGED");
end