local addonName = ...
local addon = _G[addonName]
local WHITE		= "|cFFFFFFFF"

local THIS_ACCOUNT = "Default"
local INFO_REALM_LINE = 0
local INFO_CHARACTER_LINE = 1
local INFO_TOTAL_LINE = 2

addon.Characters = {}
local ns = addon.Characters
local characterList
local view

local function ProcessRealms(func)
	for realm in pairs(DataStore:GetRealms(THIS_ACCOUNT)) do
		func(THIS_ACCOUNT, realm)
	end
end

local totalMoney, totalSoulAsh, realmCount
local collapsedStates = {}

local function GetWTScore(locks, level)
	if locks == 0 then return (level == 80) and 0 or 1
	elseif locks >= 3 then return 4
	else return 2 end
end

local function AddRealm(AccountName, RealmName)
	local realmMoney, realmSoulAsh = 0, 0

	table.insert(characterList, { linetype = INFO_REALM_LINE + (realmCount*3),
		isCollapsed = collapsedStates[RealmName] or false,
		account = AccountName,
		realm = RealmName
	} )
	
	for characterName, character in pairs(DataStore:GetCharacters(RealmName, AccountName)) do
		local charDB = addon.db.global.Characters[character] or {}
		local charAsh = charDB.SoulAsh or 0
		local charCost = charDB.RaidResetCost or 0
		local charLvl = tonumber(DataStore:GetCharacterLevel(character)) or 1
		
		local locks10, locks25 = 0, 0
		if charDB.SavedInstance then
			for Instance, InstanceInfo in pairs(charDB.SavedInstance) do
				local InstanceName = strsplit("|", Instance)
				local reset, lastcheck = strsplit("|", InstanceInfo)
				reset = tonumber(reset) or 0
				lastcheck = tonumber(lastcheck) or 0
				
				if (reset - (time() - lastcheck)) > 0 then
					if InstanceName == "Naxxramas (10)" or InstanceName == "The Obsidian Sanctum (10)" or InstanceName == "The Eye of Eternity (10)" then
						locks10 = locks10 + 1
					elseif InstanceName == "Naxxramas (25)" or InstanceName == "The Obsidian Sanctum (25)" or InstanceName == "The Eye of Eternity (25)" then
						locks25 = locks25 + 1
					end
				end
			end
		end
		
		local score10 = GetWTScore(locks10, charLvl)
		local score25 = GetWTScore(locks25, charLvl)
		local wtScore = (score10 * 10) + score25
		
		table.insert(characterList, { linetype = INFO_CHARACTER_LINE + (realmCount*3),
			key = character,
			soulAsh = charAsh,
			raidResetCost = charCost,
			locks10 = locks10,
			locks25 = locks25,
			worldTourScore = wtScore,
		} )

		realmMoney = realmMoney + (DataStore:GetMoney(character) or 0)
		realmSoulAsh = realmSoulAsh + charAsh
	end

	table.insert(characterList, { linetype = INFO_TOTAL_LINE + (realmCount*3),
		level = "", 
		money = realmMoney,
		soulAsh = realmSoulAsh,
	} )

	totalMoney = totalMoney + realmMoney
	totalSoulAsh = (totalSoulAsh or 0) + realmSoulAsh
	realmCount = realmCount + 1
end

function ns:BuildList()
	if characterList then
		for _, v in ipairs(characterList) do
			if v.linetype and mod(v.linetype, 3) == INFO_REALM_LINE then
				collapsedStates[v.realm] = v.isCollapsed
			end
		end
	end

	characterList = characterList or {}
	wipe(characterList)
	
	totalMoney, totalSoulAsh, realmCount = 0, 0, 0
	ProcessRealms(AddRealm)
end

local function AddRealmView(AccountName, RealmName)
	for index, line in pairs(characterList) do
		if mod(line.linetype, 3) == INFO_REALM_LINE then
			if (line.account == AccountName) and (line.realm == RealmName) then
				table.insert(view, index)
				index = index + 1
				local linetype = mod(characterList[index].linetype, 3)
				while (linetype ~= INFO_REALM_LINE) do
					table.insert(view, index)
					index = index + 1
					if index > #characterList then return end
					linetype = mod(characterList[index].linetype, 3)
				end
				return
			end
		end
	end
end

function ns:BuildView()
	view = view or {}
	wipe(view)
	ProcessRealms(AddRealmView)
end

local function SortByFunction(a, b, func, ascending)
	if (a.linetype ~= b.linetype) then
		return a.linetype < b.linetype
	else
		if mod(a.linetype, 3) ~= INFO_CHARACTER_LINE then return false end
		local retA = DataStore[func](DataStore, a.key) or 0
		local retB = DataStore[func](DataStore, b.key) or 0
		if ascending then return retA < retB else return retA > retB end
	end
end

local function SortByCustomField(a, b, field, ascending)
	if (a.linetype ~= b.linetype) then
		return a.linetype < b.linetype
	else
		if mod(a.linetype, 3) ~= INFO_CHARACTER_LINE then return false end
		local valA = a[field] or 0
		local valB = b[field] or 0
		if ascending then return valA < valB else return valA > valB end
	end
end

function ns:Sort(frame, field)
	local ascending = frame.ascendingSort
	if (field == "soulAsh") or (field == "raidResetCost") or (field == "worldTourScore") then
		table.sort(characterList, function(a, b) return SortByCustomField(a, b, field, ascending) end)
	else
		table.sort(characterList, function(a, b) return SortByFunction(a, b, field, ascending) end)
	end
	
	ns:BuildView() 
	if addon.Tabs.Summary then addon.Tabs.Summary:Refresh() end
end

function ns:Get(index) return characterList[index] end
function ns:GetView() return view end
function ns:GetNum() return #characterList or 0 end

function ns:GetInfo(index)
	local lineType = ns:GetLineType(index)
	if lineType == INFO_REALM_LINE then
		local line = characterList[index]
		return nil, line.realm, line.account
	elseif lineType == INFO_CHARACTER_LINE then
		local account, realm, name = strsplit(".", characterList[index].key)
		return name, realm, account
	end
end

function ns:GetLineType(index)
	return mod(characterList[index].linetype, 3)
end

function ns:GetField(index, field)
	local character = characterList[index]
	if character then return character[field] end
end

function ns:ToggleHeader(frame)
	local line = frame:GetParent():GetID()
	if not line or line == 0 then return end
	local header = characterList[line]
	
	if header.isCollapsed ~= nil then
		header.isCollapsed = not header.isCollapsed
		ns:BuildView() 
	end
end