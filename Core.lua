local addonName = ...
_G[addonName] = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0")
local addon = _G[addonName]

addon.Version = "v3.3.002b"
addon.VersionNum = 303002
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

BINDING_HEADER_ALTOHOLIC = "Ashoholic";
BINDING_NAME_ALTOHOLIC_TOGGLE = "Toggle UI";

local AddonDB_Defaults = {
	global = {
		Characters = {
			['*'] = {
				SavedInstance = {},
				Calendar = {},
				Timers = {},
				SoulAsh = 0,
				RaidResetCost = 0,
			},
		},
		options = {
			TabSummaryMode = 2,
			UITransparency = 1.0,
			ClampWindowToScreen = 0,
			MinimapIconAngle = 180,
			MinimapIconRadius = 78,
			ShowMinimap = 1,
			TooltipSource = 1,
			TooltipCount = 1,
			TooltipTotal = 1,
		},
}}

LibStub:GetLibrary("LibDataBroker-1.1"):NewDataObject(addonName, {
	type = "launcher", icon = "Interface\\Icons\\INV_Drink_13",
	OnClick = function(clickedframe, button) addon:ToggleUI() end,
	text = (Broker2FuBar) and addonName or nil, label = addonName,
})

local prestigeTimeout = 0

function addon:OnInitialize()
	addon.db = LibStub("AceDB-3.0"):New("AltoholicDB", AddonDB_Defaults)

	addon:RegisterChatCommand("ashoholic", "ChatCommand")
	addon:RegisterChatCommand("ash", "ChatCommand")
	
	addon:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
	addon:RegisterEvent("UPDATE_INSTANCE_INFO", "UpdateSavedInstances")
	
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(self, elapsed)
		self.timer = (self.timer or 0) + elapsed
		if self.timer > 2 then
			if addon.pendingPrestige then
				prestigeTimeout = prestigeTimeout - 2
				if prestigeTimeout <= 0 then
					addon.pendingPrestige = false
				end
			end
			
			addon:UpdateSoulAsh()
			addon:UpdateRaidResetCost()
			addon:CheckPrestigeHook()
			self.timer = 0
		end
	end)
end

function addon:ChatCommand(input)
	addon:ToggleUI()
end

function addon:OnPlayerEnteringWorld()
	addon:UpdateSoulAsh()
	addon:UpdateRaidResetCost()
	RequestRaidInfo() 
end

function addon:UpdateSavedInstances()
	local currentCharacter = DataStore:GetCharacter()
	if not currentCharacter or not addon.db.global.Characters[currentCharacter] then return end
	
	local charDB = addon.db.global.Characters[currentCharacter]
	charDB.SavedInstance = charDB.SavedInstance or {}
	wipe(charDB.SavedInstance)
	
	for i = 1, GetNumSavedInstances() do
		local instanceName, instanceID, instanceReset, instanceDifficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName = GetSavedInstanceInfo(i)
		if locked then
			local displayName = instanceName or "Unknown"
			if maxPlayers and maxPlayers > 0 then
				displayName = displayName .. " (" .. maxPlayers .. ")"
			end
			local key = displayName .. "|" .. (instanceID or i)
			local resetTime = instanceReset or 0
			local lastCheck = time()
			charDB.SavedInstance[key] = resetTime .. "|" .. lastCheck
		end
	end
end

function addon:ResetAllSoulAsh()
	if not addon.db or not addon.db.global or not addon.db.global.Characters then return end
	
	for account in pairs(DataStore:GetAccounts()) do
		for realm in pairs(DataStore:GetRealms(account)) do
			for _, characterKey in pairs(DataStore:GetCharacters(realm, account)) do
				if addon.db.global.Characters[characterKey] then
					addon.db.global.Characters[characterKey].SoulAsh = 0
				end
			end
		end
	end
	
	if AltoholicFrame and AltoholicFrame:IsVisible() then
		if addon.Characters then addon.Characters:BuildList(); addon.Characters:BuildView() end
		if addon.Summary then addon.Summary:Update() end
	end
	
	print("|cFF00FF9AAshoholic:|r All Soul Ash balances reset to 0 (Prestige Verified).")
end

local function FindPrestigeButton(frame)
	if not frame then return nil end
	if frame:GetObjectType() == "Button" then
		local text = frame:GetText()
		if text and string.find(string.lower(text), "prestige") then return frame end
		for i = 1, frame:GetNumRegions() do
			local reg = select(i, frame:GetRegions())
			if reg and reg:GetObjectType() == "FontString" then
				local t = reg:GetText()
				if t and string.find(string.lower(t), "prestige") then return frame end
			end
		end
	end
	for i = 1, frame:GetNumChildren() do
		local child = select(i, frame:GetChildren())
		local found = FindPrestigeButton(child)
		if found then return found end
	end
	return nil
end

function addon:CheckPrestigeHook()
	local confirmFrame = _G["EbonholdPrestigeConfirmFrame"]
	if confirmFrame and confirmFrame:IsVisible() then
		local btn = FindPrestigeButton(confirmFrame)
		if btn and not btn.ashHooked then
			btn:HookScript("OnClick", function()
				addon.pendingPrestige = true
				prestigeTimeout = 10 
			end)
			btn.ashHooked = true
		end
	end
end

local function FindSoulAshInFrame(frame)
	if not frame then return nil end
	for i = 1, frame:GetNumRegions() do
		local region = select(i, frame:GetRegions())
		if region and region:GetObjectType() == "FontString" then
			local text = region:GetText()
			if text and string.match(text, "%d") then
				if not string.find(text, "%%") and not string.find(text, "Hardcore") then
					local noTextures = string.gsub(text, "|T.-|t", "")
					local noColors = string.gsub(noTextures, "|c%x%x%x%x%x%x%x%x", "")
					noColors = string.gsub(noColors, "|r", "")
					local digitsOnly = string.gsub(noColors, "%D", "")
					if digitsOnly and digitsOnly ~= "" then return tonumber(digitsOnly) end
				end
			end
		end
	end
	for i = 1, frame:GetNumChildren() do
		local child = select(i, frame:GetChildren())
		local val = FindSoulAshInFrame(child)
		if val then return val end
	end
	return nil
end

function addon:UpdateSoulAsh()
	local ashVal = FindSoulAshInFrame(_G["ProjectEbonholdPlayerRunFrame"])
	if ashVal then
		local currentCharacter = DataStore:GetCharacter()
		if currentCharacter and addon.db.global.Characters[currentCharacter] then
			
			if addon.pendingPrestige and ashVal == 0 then
				addon.pendingPrestige = false
				addon:ResetAllSoulAsh()
				return 
			end
			
			if addon.db.global.Characters[currentCharacter].SoulAsh ~= ashVal then
				addon.db.global.Characters[currentCharacter].SoulAsh = ashVal
				if AltoholicFrame and AltoholicFrame:IsVisible() then
					if addon.Characters then addon.Characters:BuildList(); addon.Characters:BuildView() end
					if addon.Summary then addon.Summary:Update() end
				end
			end
		end
	end
end

local gatheredTexts = {}

local function GatherAllTexts(frame)
	if not frame then return end
	if frame.GetText and frame:GetObjectType() == "Button" then
		local t = frame:GetText()
		if t and t ~= "" then table.insert(gatheredTexts, t) end
	end
	if frame.GetNumRegions then
		for i = 1, frame:GetNumRegions() do
			local reg = select(i, frame:GetRegions())
			if reg and reg:GetObjectType() == "FontString" then
				local t = reg:GetText()
				if t and t ~= "" then table.insert(gatheredTexts, t) end
			end
		end
	end
	if frame.GetNumChildren then
		for i = 1, frame:GetNumChildren() do
			GatherAllTexts(select(i, frame:GetChildren()))
		end
	end
end

local function ExtractCostFromList(framesTexts)
	for i, text in ipairs(framesTexts) do
		if text and string.find(string.lower(text), "clear ids") then
			local clean = string.gsub(text, "|T.-|t", "")
			clean = string.gsub(clean, "|c%x%x%x%x%x%x%x%x", "")
			clean = string.gsub(clean, "|r", "")
			local digits = string.gsub(clean, "%D", "")
			if digits ~= "" then return tonumber(digits) end
			
			for j = i + 1, math.min(i + 5, #framesTexts) do
				local nextText = framesTexts[j]
				if nextText then
					local nClean = string.gsub(nextText, "|T.-|t", "")
					nClean = string.gsub(nClean, "|c%x%x%x%x%x%x%x%x", "")
					nClean = string.gsub(nClean, "|r", "")
					local nDigits = string.gsub(nClean, "%D", "")
					if nDigits ~= "" then
						local noNumbers = string.gsub(nClean, "[%d%s%,%.]", "")
						if noNumbers == "" then return tonumber(nDigits) end
					end
				end
			end
		end
	end
	return nil
end

-- Base cost the server restores on the weekly "Next cost reset" timer.
local RAID_COST_BASE = 50000
local RAID_COST_WEEK = 7 * 24 * 60 * 60
-- Same-cycle readings stay within minutes of each other. A jump larger than
-- this means the panel rolled over to next week's countdown.
local RAID_COST_CYCLE_SLACK = 12 * 60 * 60

local function ParseCountdownDuration(text)
	if not text then return nil end
	local clean = string.gsub(text, "|T.-|t", "")
	clean = string.gsub(clean, "|c%x%x%x%x%x%x%x%x", "")
	clean = string.gsub(clean, "|r", "")
	local lower = string.lower(clean)
	if not string.match(lower, "%d+%s*[dhms]") then return nil end

	local days = tonumber(string.match(lower, "(%d+)%s*d")) or 0
	local hours = tonumber(string.match(lower, "(%d+)%s*h")) or 0
	local mins = tonumber(string.match(lower, "(%d+)%s*m")) or 0
	local secs = string.match(lower, "(%d+)%s*s")
	local hasSeconds = secs ~= nil
	secs = tonumber(secs) or 0

	local duration = (days * 86400) + (hours * 3600) + (mins * 60) + secs
	if duration > (8 * 86400) then return nil end
	-- The panel drops the seconds. Wait out the rest of the displayed minute
	-- so a still-running countdown is not treated as already elapsed.
	if not hasSeconds then
		duration = duration + 60
	end
	return duration
end

local function ExtractResetCountdown(framesTexts)
	for i, text in ipairs(framesTexts) do
		if text and string.find(string.lower(text), "cost reset") then
			-- The countdown can share the label line or sit on the next line.
			local combined = text
			if framesTexts[i + 1] then
				combined = combined .. " " .. framesTexts[i + 1]
			end
			local duration = ParseCountdownDuration(combined)
			if not duration and framesTexts[i + 2] then
				duration = ParseCountdownDuration(combined .. " " .. framesTexts[i + 2])
			end
			if duration then return duration end
		end
	end
	return nil
end

local function RefreshOpenRoster()
	if AltoholicFrame and AltoholicFrame:IsVisible() then
		if addon.Characters then addon.Characters:BuildList(); addon.Characters:BuildView() end
		if addon.Summary then addon.Summary:Update() end
	end
end

local function ApplyRaidCostWeeklyReset()
	if not addon.db or not addon.db.global or not addon.db.global.Characters then return end
	if not DataStore then return end

	local changed = false
	for account in pairs(DataStore:GetAccounts()) do
		for realm in pairs(DataStore:GetRealms(account)) do
			for _, characterKey in pairs(DataStore:GetCharacters(realm, account)) do
				local charDB = addon.db.global.Characters[characterKey]
				if charDB and charDB.RaidResetCost ~= RAID_COST_BASE then
					charDB.RaidResetCost = RAID_COST_BASE
					changed = true
				end
			end
		end
	end

	if changed then
		RefreshOpenRoster()
		print("|cFF00FF9AAshoholic:|r Weekly reset: instance ID costs set to 50,000.")
	end
end

-- observedResetAt is the absolute time() the open raid panel is counting
-- toward, or nil when that panel is closed. The deadline is kept once it has
-- been seen, so the reset still runs if the panel is closed or the game was
-- shut down when the timer hit.
local function TrackRaidCostReset(observedResetAt)
	if not addon.db or not addon.db.global then return end

	local stored = addon.db.global.RaidCostResetAt
	local now = time()
	local liveIsNewCycle = observedResetAt and stored and (observedResetAt > (stored + RAID_COST_CYCLE_SLACK))

	if stored and (liveIsNewCycle or (now >= stored)) then
		ApplyRaidCostWeeklyReset()
		if liveIsNewCycle then
			addon.db.global.RaidCostResetAt = observedResetAt
		else
			local nextAt = stored + RAID_COST_WEEK
			while nextAt <= now do
				nextAt = nextAt + RAID_COST_WEEK
			end
			addon.db.global.RaidCostResetAt = nextAt
		end
		return
	end

	if not observedResetAt then return end
	if (not stored) or (observedResetAt < stored and (stored - observedResetAt) <= RAID_COST_CYCLE_SLACK) then
		addon.db.global.RaidCostResetAt = observedResetAt
	end
end

function addon:UpdateRaidResetCost()
	local rf1 = _G["RaidFrameNotInRaid"]
	local rf2 = _G["RaidFrame"]
	local cost = nil
	local observedResetAt = nil
	if (rf1 and rf1:IsVisible()) or (rf2 and rf2:IsVisible()) then
		wipe(gatheredTexts)
		GatherAllTexts(_G["FriendsFrame"])
		cost = ExtractCostFromList(gatheredTexts)
		local countdown = ExtractResetCountdown(gatheredTexts)
		if countdown then
			observedResetAt = time() + countdown
		end
	end

	TrackRaidCostReset(observedResetAt)

	if cost then
		local currentCharacter = DataStore:GetCharacter()
		if currentCharacter and addon.db.global.Characters[currentCharacter] then
			if addon.db.global.Characters[currentCharacter].RaidResetCost ~= cost then
				addon.db.global.Characters[currentCharacter].RaidResetCost = cost
				if AltoholicFrame and AltoholicFrame:IsVisible() then
					if addon.Characters then addon.Characters:BuildList(); addon.Characters:BuildView() end
					if addon.Summary then addon.Summary:Update() end
				end
			end
		end
	end
end

function addon:ScanBags() return end
function addon:ScanBank() return end
function addon:ScanMail() return end
function addon:ScanAuctions() return end

local tabList = { "Summary", "Characters" }
local function ShowTab(name) local tab = _G[addonName.."Tab" .. name]; if tab then tab:Show() end end
local function HideTab(name) local tab = _G[addonName.."Tab" .. name]; if tab then tab:Hide() end end

addon.Tabs = {}
function addon.Tabs:HideAll()
	for _, tabName in pairs(tabList) do HideTab(tabName) end
end

function addon.Tabs:OnClick(index)
	PanelTemplates_SetTab(_G[addonName.."Frame"], index);
	self:HideAll()
	self.current = index
	self.Columns.prefix = addonName.."Tab"..tabList[index].."_Sort"
	ShowTab(tabList[index])
end

addon.Tabs.Columns = {}
function addon.Tabs.Columns:Init()
	local i = 1
	local prefix = self.prefix or "AltoholicTabSummary_Sort"
	local button = _G[ prefix .. i ]
	local arrow = _G[ prefix .. i .. "Arrow"]
	
	while button do
		arrow:Hide(); button.ascendingSort = nil; button:Hide()
		i = i + 1; button = _G[ prefix .. i ]; arrow = _G[ prefix .. i .. "Arrow"]
	end
	self.count = 0; self.prefix = prefix
end

function addon.Tabs.Columns:Add(title, width, func, align)
	local prefix = self.prefix
	self.count = self.count + 1
	local button = _G[ prefix..self.count ]

	if not title then button:Hide(); return end
	
	button:SetText(title)
	button:SetWidth(width)
	
	local fs = button:GetFontString()
	if fs then
		fs:ClearAllPoints()
		if align == "LEFT" then
			fs:SetPoint("LEFT", button, "LEFT", 10, 0)
			fs:SetJustifyH("LEFT")
		else
			fs:SetPoint("CENTER", button, "CENTER", 0, 0)
			fs:SetJustifyH("CENTER")
		end
	end
	
	button:SetScript("OnClick", function(self)
			local p = addon.Tabs.Columns.prefix
			local i = 1
			local arrow = _G[ p .. i .. "Arrow"]
			while arrow do arrow:Hide(); i = i + 1; arrow = _G[ p .. i .. "Arrow"] end

			arrow = _G[ p .. self:GetID() .. "Arrow"]
			
			arrow:ClearAllPoints()
			arrow:SetPoint("LEFT", self:GetFontString(), "RIGHT", 2, 0)
			arrow:Show()
			
			if not self.ascendingSort then
				self.ascendingSort = true; arrow:SetTexCoord(0, 0.5625, 1.0, 0);
			else
				self.ascendingSort = nil; arrow:SetTexCoord(0, 0.5625, 0, 1.0);
			end
			if func then func(self) end
		end)
	button:Show()
end

function addon:OnShow()
	-- Clear selection highlight when reopening window
	addon.SelectedLine = nil
	if addon.Characters then
		addon.Characters:BuildList()
		addon.Characters:BuildView()
	end
end

function addon:ToggleUI()
	if (AltoholicFrame:IsVisible()) then
		AltoholicFrame:Hide();
	else
		AltoholicFrame:Show();
	end
end

tinsert(UISpecialFrames, "AltoholicFrame");
tinsert(UISpecialFrames, "AltoMsgBox");