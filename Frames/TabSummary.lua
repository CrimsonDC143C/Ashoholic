local addonName = ...
local addon = _G[addonName]
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local currentMode
local childrenFrames = { "Summary" }
local childrenObjects

addon.Tabs.Summary = {}
local ns = addon.Tabs.Summary
local isInitialized = false

function ns:Init()
	if isInitialized then return end
	isInitialized = true
	childrenObjects = { addon.Summary }
	
	if addon.Characters then
		addon.Characters:BuildList()
		addon.Characters:BuildView()
	end
	ns:SetMode(1)
end

function ns:MenuItem_OnClick(id)
	if not isInitialized then ns:Init() end
	for _, v in pairs(childrenFrames) do
		local frame = _G[ "AltoholicFrame" .. v]
		if frame then frame:Hide() end
	end
	ns:SetMode(id)
	
	local f = _G[ "AltoholicFrame" .. childrenFrames[id]]
	local o = childrenObjects[id]
	if o and o.BuildView then o:BuildView() end
	if f then f:Show() end
	if o and o.Update then o:Update() end
end

function ns:SetMode(mode)
	currentMode = mode
	local Columns = addon.Tabs.Columns
	Columns:Init()
	
	if currentMode == 1 then
		Columns:Add("Name", 140, function(self) addon.Characters:Sort(self, "GetCharacterName") end, "LEFT")
		Columns:Add("Level", 45, function(self) addon.Characters:Sort(self, "GetCharacterLevel") end, "CENTER")
		Columns:Add("10m  WT  25m", 100, function(self) addon.Characters:Sort(self, "worldTourScore") end, "CENTER")
		Columns:Add("Reset Cost", 110, function(self) addon.Characters:Sort(self, "raidResetCost") end, "RIGHT")
		Columns:Add("Soul Ash", 135, function(self) addon.Characters:Sort(self, "soulAsh") end, "RIGHT")
		Columns:Add("Money", 140, function(self) addon.Characters:Sort(self, "GetMoney") end, "RIGHT")
	end
end

function ns:Refresh()
	if AltoholicFrameSummary and AltoholicFrameSummary:IsVisible() then
		if addon.Summary and addon.Summary.Update then addon.Summary:Update() end
	end
end