--[[	*** Ashoholic / Altoholic ***
Original Author : Thaoky, EU-Marécages de Zangar
Modified For Ebonhold by : Crimmy
--]]

local addonName = ...
local addon = _G[addonName]
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local DS

local WHITE		= "|cFFFFFFFF"
local RED		= "|cFFFF0000"
local GREEN		= "|cFF00FF00"
local YELLOW	= "|cFFFFFF00"
local ORANGE	= "|cFFFF7F00"
local TEAL		= "|cFF00FF9A"
local GOLD		= "|cFFFFD700"

local THIS_ACCOUNT = "Default"

Altoholic.ClassInfo = {
	["MAGE"] = "|cFF69CCF0",
	["WARRIOR"] = "|cFFC79C6E",
	["HUNTER"] = "|cFFABD473",
	["ROGUE"] = "|cFFFFF569",
	["WARLOCK"] = "|cFF9482CA", 
	["DRUID"] = "|cFFFF7D0A", 
	["SHAMAN"] = "|cFF2459FF",
	["PALADIN"] = "|cFFF58CBA", 
	["PRIEST"] = WHITE,
	["DEATHKNIGHT"] = "|cFFC41F3B"
}

local function InitLocalization()
	AltoholicMinimapButton.tooltip = format("%s\n%s\n%s", "Ashoholic", WHITE..L["Left-click to |cFF00FF00open"], WHITE..L["Right-click to |cFF00FF00drag"] )
end

-- *** DB functions ***
local currentAlt
local currentRealm
local currentAccount

function addon:GetCharacterTable(name, realm, account)
	local key = format("%s.%s.%s", account or currentAccount, realm or currentRealm, name or currentAlt)
	return addon.db.global.Characters[key]
end

function addon:GetCharacterTableByLine(line)
	return addon:GetCharacterTable( addon.Characters:GetInfo(line) )
end

function addon:GetCurrentCharacter()
	return currentAlt, currentRealm, currentAccount
end

function addon:SetCurrentCharacter(name, realm, account)
	currentAlt = name
	if realm then addon:SetCurrentRealm(realm) end
	if account then addon:SetCurrentAccount(account) end
end

function addon:GetCurrentRealm()
	return currentRealm, currentAccount
end

function addon:SetCurrentRealm(name)
	currentRealm = name
end

function addon:GetCurrentAccount()
	return currentAccount
end

function addon:SetCurrentAccount(name)
	currentAccount = name
end


function addon:OnEnable()
	DS = DataStore
	InitLocalization()
	
	if addon.InitTooltip then addon:InitTooltip() end

	local realm = GetRealmName()
	local player = UnitName("player")
	local key = format("%s.%s.%s", THIS_ACCOUNT, realm, player)
	addon.ThisCharacter = addon.db.global.Characters[key]
	
	addon:SetCurrentCharacter(player, realm, THIS_ACCOUNT)

	-- Handle Minimap Icon
	if Altoholic.db and Altoholic.db.global.options.ShowMinimap == 1 then
		addon:MoveMinimapIcon()
		AltoholicMinimapButton:Show()
	else
		AltoholicMinimapButton:Hide()
	end
end

function addon:OnDisable()
end

function addon:ToggleUI()
	if (AltoholicFrame:IsVisible()) then
		AltoholicFrame:Hide();
	else
		AltoholicFrame:Show();
	end
end

function addon:OnShow()
	if addon.Characters then
		addon.Characters:BuildList()
		addon.Characters:BuildView()
	end
end

-- *** Minimap Drag Handlers ***
function addon:UpdateMinimapIconCoords()
	local xpos, ypos = GetCursorPosition()
	local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()

	xpos = xmin - xpos / UIParent:GetScale() + 70
	ypos = ypos / UIParent:GetScale() - ymin - 70

	local angle = math.deg(math.atan2(ypos, xpos))
	if addon.db and addon.db.global and addon.db.global.options then
		addon.db.global.options.MinimapIconAngle = angle
	end
	addon:MoveMinimapIcon()
end

function addon:MoveMinimapIcon()
	local angle = 180
	if addon.db and addon.db.global and addon.db.global.options then
		angle = addon.db.global.options.MinimapIconAngle or 180
	end
	local radius = 80
	AltoholicMinimapButton:SetPoint(
		"TOPLEFT",
		"Minimap",
		"TOPLEFT",
		52 - (radius * cos(angle)),
		(radius * sin(angle)) - 52
	)
end


-- *** Utility functions ***
function addon:TextureToFontstring(name, width, height)
	return format("|T%s:%s:%s|t", name, width, height)
end

function addon:GetMoneyString(copper, color, noTexture)
	color = color or "|cFFFFD700"

	local gold = floor( copper / 10000 );
	copper = mod(copper, 10000)
	local silver = floor( copper / 100 );
	copper = mod(copper, 100)
	
	if noTexture then
		copper = format("%s%s%s%s", color, copper, "|cFFEDA55F", COPPER_AMOUNT_SYMBOL)
		silver = format("%s%s%s%s", color, silver, "|cFFC7C7CF", SILVER_AMOUNT_SYMBOL)
		gold = format("%s%s%s%s", color, gold, "|cFFFFD700", GOLD_AMOUNT_SYMBOL)
	else
		copper = color..format(COPPER_AMOUNT_TEXTURE, copper, 13, 13)
		silver = color..format(SILVER_AMOUNT_TEXTURE, silver, 13, 13)
		gold = color..format(GOLD_AMOUNT_TEXTURE, gold, 13, 13)
	end
	return format("%s %s %s", gold, silver, copper)
end

function addon:GetTimeString(seconds)
	if not seconds then return "" end
	local days = floor(seconds / 86400);
	seconds = mod(seconds, 86400)
	local hours = floor(seconds / 3600);
	seconds = mod(seconds, 3600)
	local minutes = floor(seconds / 60);
	seconds = mod(seconds, 60)

	return format("%s|rd %s|rh %s|rm", WHITE..days, WHITE..hours, WHITE..minutes)
end

function Altoholic:GetClassColor(class)
	return Altoholic.ClassInfo[class] or WHITE
end

function Altoholic:ShowWidgetTooltip(frame)
	if not frame.tooltip then return end
	
	AltoTooltip:SetOwner(frame, "ANCHOR_LEFT");
	AltoTooltip:ClearLines();
	AltoTooltip:AddLine(frame.tooltip)
	AltoTooltip:Show(); 
end

function addon:SetMsgBoxHandler(func, arg1, arg2)
	local msg = AltoMsgBox
	msg.ButtonHandler = func
	msg.arg1 = arg1
	msg.arg2 = arg2
end

function addon:MsgBox_OnClick(button)
	local msg = AltoMsgBox

	if msg.ButtonHandler then
		msg:ButtonHandler(button, msg.arg1, msg.arg2)
		msg.ButtonHandler = nil
		msg.arg1 = nil
		msg.arg2 = nil
	end
	msg:Hide();
	msg:SetHeight(100)
	AltoMsgBox_Text:SetHeight(28)
end