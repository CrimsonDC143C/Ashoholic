local addonName = ...
local addon = _G[addonName]
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local INFO_REALM_LINE = 0
local INFO_CHARACTER_LINE = 1
local INFO_TOTAL_LINE = 2
local THIS_ACCOUNT = "Default"

local TEAL		= "|cFF00FF9A"
local WHITE		= "|cFFFFFFFF"
local GOLD		= "|cFFFFD700"
local GREEN		= "|cFF00FF00"

local ICON_FACTION_HORDE = "Interface\\Icons\\INV_BannerPVP_01"
local ICON_FACTION_ALLIANCE = "Interface\\Icons\\INV_BannerPVP_02"
local Characters = addon.Characters

local function FormatNumber(num)
	if not num then return "0" end
	local formatted = tostring(num)
	local k
	while true do  
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if (k==0) then break end
	end
	return formatted
end

local function GetWorldTourIcon(locks, level)
	locks = tonumber(locks) or 0
	level = tonumber(level) or 1
	if locks >= 3 then 
		return "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:16|t" 
	elseif locks > 0 then 
		return "|TInterface\\RAIDFRAME\\ReadyCheck-Waiting:16|t" 
	elseif level < 80 then 
		return "|cFFFFFF00LVL|r" 
	else 
		return "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:16|t" 
	end
end

local function GetFactionTotals(f, line)
	local _, realm, account = Characters:GetInfo(line)
	local money = 0
	local DS = DataStore
	for _, character in pairs(DS:GetCharacters(realm, account)) do
		if DS:GetCharacterFaction(character) == f then
			money = money + DS:GetMoney(character)
		end
	end
	return money
end

local function DDM_Add(text, value, func, arg1)
	local info = UIDropDownMenu_CreateInfo(); 
	info.text = text; info.value = value; info.func = func; info.arg1 = arg1; info.checked = nil;
	UIDropDownMenu_AddButton(info, 1); 
end

local function DDM_AddCloseMenu()
	local info = UIDropDownMenu_CreateInfo(); 
	info.text = CLOSE; info.func = function() CloseDropDownMenus() end; info.checked = nil; info.notCheckable = 1; info.icon = nil;
	UIDropDownMenu_AddButton(info, 1)
end

addon.Summary = {}
local ns = addon.Summary

local function DeleteAlt_MsgBox_Handler(self, button, characterInfoLine)
	if not button then return end
	local name, realm, account = Characters:GetInfo(characterInfoLine)
	DataStore:DeleteCharacter(name, realm, account)
	
	Characters:BuildList()
	Characters:BuildView()
	addon.Summary:Update()
	addon:Print(format( L["Character %s successfully deleted"], name))
end

local function DeleteAlt(self, characterInfoLine)
	local name, realm, account = Characters:GetInfo(characterInfoLine)
	if (account == THIS_ACCOUNT) and (realm == GetRealmName()) and (name == UnitName("player")) then
		addon:Print(L["Cannot delete current character"])
		return
	end
	addon:SetMsgBoxHandler(DeleteAlt_MsgBox_Handler, characterInfoLine)
	AltoMsgBox_Text:SetText(L["Delete this Alt"] .. "?\n" .. name)
	AltoMsgBox:Show()
end

local function DeleteRealm_MsgBox_Handler(self, button, characterInfoLine)
	if not button then return end
	local _, realm, account = Characters:GetInfo(characterInfoLine)
	DataStore:DeleteRealm(realm, account)

	if addon:GetCurrentRealm() == realm and addon:GetCurrentAccount() == account then
		local player = UnitName("player")
		local realmName = GetRealmName()
		addon:SetCurrentCharacter(player, realmName, THIS_ACCOUNT)
		if addon.Tabs and addon.Tabs.Characters then
			addon.Tabs.Characters:SetCurrent(player, realmName, THIS_ACCOUNT)
		end
	end
	
	Characters:BuildList()
	Characters:BuildView()
	addon.Summary:Update()
	addon:Print(format( L["Realm %s successfully deleted"], realm))
end

local function DeleteRealm(self, characterInfoLine)
	local _, realm, account = Characters:GetInfo(characterInfoLine)
	if (account == THIS_ACCOUNT) and (realm == GetRealmName()) then
		addon:Print(L["Cannot delete current realm"])
		return
	end
	addon:SetMsgBoxHandler(DeleteRealm_MsgBox_Handler, characterInfoLine)
	AltoMsgBox_Text:SetText(L["Delete this Realm"] .. "?\n" .. realm)
	AltoMsgBox:Show()
end

function ns:Update()
	local VisibleLines = 14
	local frame = "AltoholicFrameSummary"
	local entry = frame.."Entry"
	
	local offset = FauxScrollFrame_GetOffset( _G[ frame.."ScrollFrame" ] );
	local DisplayedCount = 0
	local VisibleCount = 0
	local DrawRealm
	local i=1
	
	local DS = DataStore
	local view = Characters:GetView()
	if not view then return end
	
	for _, line in pairs(view) do
		local lineType = Characters:GetLineType(line)
		
		if (offset > 0) or (DisplayedCount >= VisibleLines) then
			if lineType == INFO_REALM_LINE then
				if Characters:GetField(line, "isCollapsed") == false then DrawRealm = true else DrawRealm = false end
				VisibleCount = VisibleCount + 1
				offset = offset - 1
			elseif DrawRealm then
				VisibleCount = VisibleCount + 1
				offset = offset - 1
			end
		else
			_G[entry..i.."Line"]:Hide()
			_G[entry..i.."LineBottom"]:Hide()

			if lineType == INFO_REALM_LINE then
				local _, realm, account = Characters:GetInfo(line)
				
				if Characters:GetField(line, "isCollapsed") == false then
					_G[ entry..i.."Collapse" ]:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up"); 
					DrawRealm = true
				else
					_G[ entry..i.."Collapse" ]:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up");
					DrawRealm = false
				end
				
				_G[entry..i.."Selection"]:Hide()
				_G[entry..i.."Collapse"]:Show()
				_G[entry..i.."NameNormalText"]:SetWidth(500)
				_G[entry..i.."NameNormalText"]:SetText(format("%s", realm))
				
				_G[entry..i.."Level"]:SetText("")
				_G[entry..i.."WT10"]:SetText("")
				_G[entry..i.."WT25"]:SetText("")
				_G[entry..i.."Money"]:SetText("")
				_G[entry..i.."SoulAsh"]:SetText("")
				_G[entry..i.."ResetCost"]:SetText("")

				_G[ entry..i ]:SetID(line)
				_G[ entry..i ]:Show()
				i = i + 1
				VisibleCount = VisibleCount + 1
				DisplayedCount = DisplayedCount + 1
			elseif DrawRealm then
				if (lineType == INFO_CHARACTER_LINE) then
					-- FIX: Bypassed the broken DS:GetCharacter() lookup. character is now the exact DataStore Key string!
					local character = Characters:GetField(line, "key")
					local icon = (DS:GetCharacterFaction(character) == "Alliance") and addon:TextureToFontstring(ICON_FACTION_ALLIANCE, 18, 18) .. " " or addon:TextureToFontstring(ICON_FACTION_HORDE, 18, 18) .. " "
					
					-- SAFENET: Fallback 'or 1' added inside tonumber() to guarantee it never errors out
					local charLvl = tonumber(DS:GetCharacterLevel(character) or 1)
					
					if addon.SelectedLine == character then _G[entry..i.."Selection"]:Show() else _G[entry..i.."Selection"]:Hide() end
					
					_G[entry..i.."Collapse"]:Hide()
					_G[entry..i.."NameNormalText"]:SetWidth(120)
					_G[entry..i.."NameNormalText"]:SetText(icon .. format("%s", DS:GetColoredCharacterName(character) or "Unknown"))
					_G[entry..i.."Level"]:SetText(GREEN .. charLvl)
					_G[entry..i.."Money"]:SetText(addon:GetMoneyString(DS:GetMoney(character)))
					
					local l10 = Characters:GetField(line, "locks10") or 0
					local l25 = Characters:GetField(line, "locks25") or 0
					_G[entry..i.."WT10"]:SetText(GetWorldTourIcon(l10, charLvl))
					_G[entry..i.."WT25"]:SetText(GetWorldTourIcon(l25, charLvl))
					
					local ash = Characters:GetField(line, "soulAsh") or 0
					local cost = Characters:GetField(line, "raidResetCost") or 0
					_G[entry..i.."SoulAsh"]:SetText(TEAL .. FormatNumber(ash))
					if cost > 0 then _G[entry..i.."ResetCost"]:SetText(GOLD .. FormatNumber(cost)) else _G[entry..i.."ResetCost"]:SetText(WHITE .. "0") end
					
				elseif (lineType == INFO_TOTAL_LINE) then
					_G[entry..i.."Collapse"]:Hide()
					_G[entry..i.."Selection"]:Hide()
					_G[entry..i.."Line"]:Show() 
					_G[entry..i.."LineBottom"]:Show() 
					
					_G[entry..i.."NameNormalText"]:SetWidth(120)
					_G[entry..i.."NameNormalText"]:SetText(L["Totals"])
					
					_G[entry..i.."Level"]:SetText("")
					_G[entry..i.."WT10"]:SetText("")
					_G[entry..i.."WT25"]:SetText("")
					_G[entry..i.."Money"]:SetText(addon:GetMoneyString(Characters:GetField(line, "money") or 0, WHITE))
					_G[entry..i.."Money"]:SetTextColor(1.0, 1.0, 1.0)
					
					local totalAsh = Characters:GetField(line, "soulAsh") or 0
					_G[entry..i.."SoulAsh"]:SetText(TEAL .. FormatNumber(totalAsh))
					_G[entry..i.."ResetCost"]:SetText("")
				end
				_G[ entry..i ]:SetID(line)
				_G[ entry..i ]:Show()
				i = i + 1
				VisibleCount = VisibleCount + 1
				DisplayedCount = DisplayedCount + 1
			end
		end
	end
	
	while i <= VisibleLines do
		_G[ entry..i ]:SetID(0)
		_G[ entry..i ]:Hide()
		i = i + 1
	end
	FauxScrollFrame_Update( _G[ frame.."ScrollFrame" ], VisibleCount, VisibleLines, 18);
end

function ns:Row_OnEnter(frame)
	local line = frame:GetID()
	if not line or line == 0 then return end
	
	local lineType = Characters:GetLineType(line)
	if not lineType then return end
	
	if lineType == INFO_REALM_LINE then return
	elseif lineType == INFO_TOTAL_LINE then		
		AltoTooltip:ClearLines();
		AltoTooltip:SetOwner(frame, "ANCHOR_TOP");
		AltoTooltip:AddLine(L["Totals"]);
		
		local aMoney = GetFactionTotals("Alliance", line)
		local hMoney = GetFactionTotals("Horde", line)
		
		AltoTooltip:AddLine(" ",1,1,1);
		AltoTooltip:AddDoubleLine(WHITE..MONEY, format("%s|r (%s %s|r, %s %s|r)", addon:GetMoneyString(Characters:GetField(line, "money") or 0, WHITE, true), addon:TextureToFontstring(ICON_FACTION_ALLIANCE, 18, 18), addon:GetMoneyString(aMoney, WHITE, true), addon:TextureToFontstring(ICON_FACTION_HORDE, 18, 18), addon:GetMoneyString(hMoney, WHITE, true)))
		AltoTooltip:Show();
		return
	end
	
	local DS = DataStore
	local characterKey = Characters:GetField(line, "key")
	if not characterKey then return end
	
	AltoTooltip:ClearLines();
	AltoTooltip:SetOwner(frame, "ANCHOR_RIGHT");
	AltoTooltip:AddDoubleLine(DS:GetColoredCharacterName(characterKey), DS:GetColoredCharacterFaction(characterKey))
	AltoTooltip:AddLine(format("%s %s |r%s %s", L["Level"], GREEN..DS:GetCharacterLevel(characterKey), DS:GetCharacterRace(characterKey), DS:GetCharacterClass(characterKey)),1,1,1)
	local zone, subZone = DS:GetLocation(characterKey)
	AltoTooltip:AddLine(format("%s: %s |r(%s|r)", L["Zone"], GOLD..zone, GOLD..subZone),1,1,1)
	local guildName = DS:GetGuildInfo(characterKey)
	if guildName then AltoTooltip:AddLine(format("%s: %s", GUILD, GREEN..guildName),1,1,1) end
	
	local charDB = addon.db.global.Characters[characterKey]
	if charDB and charDB.SavedInstance then
		local hasLockouts = false
		for Instance, InstanceInfo in pairs(charDB.SavedInstance) do
			local InstanceName, InstanceID = strsplit("|", Instance)
			local reset, lastcheck = strsplit("|", InstanceInfo)
			reset = tonumber(reset)
			lastcheck = tonumber(lastcheck)

			if reset and lastcheck then
				local expiresIn = reset - (time() - lastcheck)
				if expiresIn > 0 then
					if not hasLockouts then
						AltoTooltip:AddLine(" ",1,1,1)
						AltoTooltip:AddLine(WHITE .. "Active Raid Lockouts:")
						hasLockouts = true
					end
					AltoTooltip:AddDoubleLine("  " .. GOLD .. InstanceName, addon:GetTimeString(expiresIn))
				else
					charDB.SavedInstance[Instance] = nil
				end
			end
		end
	end
	
	AltoTooltip:AddLine(" ",1,1,1);
	AltoTooltip:AddLine(GREEN .. L["Right-Click for options"]);
	AltoTooltip:Show();
end

function ns:Row_OnClick(frame, button)
	local line = frame:GetID()
	if not line or line == 0 then return end
	local lineType = Characters:GetLineType(line)
	
	if not lineType or lineType == INFO_TOTAL_LINE or lineType == INFO_REALM_LINE then 
		addon.SelectedLine = nil
		ns:Update()
		return 
	end
	
	local character = Characters:GetField(line, "key")
	
	if button == "LeftButton" then
		addon.SelectedLine = character
		ns:Update()
	elseif button == "RightButton" then
		ns.CharInfoLine = line
		ToggleDropDownMenu(1, nil, AltoholicFrameSummaryRightClickMenu, frame:GetName(), 0, -5);
	end
end

function ns:RightClickMenu_OnLoad()
	local characterInfoLine = ns.CharInfoLine
	if not characterInfoLine then return end
	local lineType = Characters:GetLineType(characterInfoLine)
	if not lineType then return end

	if lineType == INFO_REALM_LINE then
		DDM_Add(L["Delete this Realm"], nil, DeleteRealm, characterInfoLine)
		return
	end

	DDM_Add(L["Delete this Alt"], nil, DeleteAlt, characterInfoLine)
	DDM_AddCloseMenu()
end