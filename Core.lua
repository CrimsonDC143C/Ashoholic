local addonName = ...
_G[addonName] = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
local addon = _G[addonName]

local FASTSWAP_SLOT_PREFIX = "fastSwapSlot"
local FASTSWAP_DONE_PREFIX = "fastSwapDone"
local FASTSWAP_MAX_SLOTS = 100
local FASTSWAP_DRIVER_CVAR = "Sound_VoiceChatInputDriverName"
local FASTSWAP_CVAR = "fastSwapTarget"

local function EnsureSwapCVar()
    if RegisterCVar and GetCVar("fastSwapTarget") == nil then
        pcall(RegisterCVar, "fastSwapTarget", "")
    end
end

local function MarkAllSwapSlotsDone()
    if not GetCVar or not RegisterCVar then return false end
    local markedAny = false
    for i = 1, FASTSWAP_MAX_SLOTS do
        local slotName = FASTSWAP_SLOT_PREFIX .. i
        local doneName = FASTSWAP_DONE_PREFIX .. i
        local okSlot, slotVal = pcall(GetCVar, slotName)
        if not okSlot or slotVal == nil then break end
        local okDone, doneVal = pcall(GetCVar, doneName)
        if not okDone or doneVal == nil then
            pcall(RegisterCVar, doneName, "1")
            markedAny = true
        end
        if SetCVar then
            pcall(SetCVar, doneName, "1")
            pcall(SetCVar, slotName, "")
        end
    end
    return markedAny
end

local function AllocateSwapSlot(target)
    if not GetCVar or not RegisterCVar then return nil end
    MarkAllSwapSlotsDone()
    for i = 1, FASTSWAP_MAX_SLOTS do
        local slotName = FASTSWAP_SLOT_PREFIX .. i
        local okSlot, slotVal = pcall(GetCVar, slotName)
        if not okSlot or slotVal == nil then
            pcall(RegisterCVar, slotName, tostring(target))
            if SetCVar then pcall(SetCVar, slotName, tostring(target)) end
            return i
        end
    end
    return nil
end

local function GetOriginalDriverValue()
    if not GetCVar then return "System Default" end
    local ok, cur = pcall(GetCVar, FASTSWAP_DRIVER_CVAR)
    if not ok or type(cur) ~= "string" or cur == "" then return "System Default" end
    local existingTarget, existingOrig = string.match(cur, "^FASTSWAP:([^:]+):?(.*)")
    if existingTarget then return (existingOrig and existingOrig ~= "") and existingOrig or "System Default" end
    return cur
end

function addon:PerformFastSwap(target)
    if type(_G.FastSwap_PerformSwap) == "function" and _G.FastSwap_PerformSwap ~= addon._fallbackFastSwap then
        return _G.FastSwap_PerformSwap(target)
    end

    if type(target) ~= "string" then return end
    target = string.gsub(target, "^%s*(.-)%s*$", "%1")
    if target == "" then return end

    if UnitAffectingCombat and UnitAffectingCombat("player") then
        local errMsg = "Cannot fast-swap while in combat!"
        print("|cFF00FF9AAshoholic:|r |cffff4040" .. errMsg .. "|r")
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(errMsg, 1.0, 0.1, 0.1, 1.0)
        end
        return
    end

    local currentName = UnitName and UnitName("player")
    if currentName and string.lower(currentName) == string.lower(target) then
        print("|cFF00FF9AAshoholic:|r |cffffd100You are already logged into " .. currentName .. ".|r")
        return
    end

    if not SetCVar then
        print("|cFF00FF9AAshoholic:|r |cffff4040Error: SetCVar is unavailable.|r")
        return
    end

    AllocateSwapSlot(target)

    local origValue = GetOriginalDriverValue()
    pcall(SetCVar, FASTSWAP_DRIVER_CVAR, "FASTSWAP:" .. tostring(target) .. ":" .. tostring(origValue))

    if RegisterCVar and GetCVar(FASTSWAP_CVAR) == nil then
        pcall(RegisterCVar, FASTSWAP_CVAR, tostring(target))
    end
    pcall(SetCVar, FASTSWAP_CVAR, tostring(target))
    if EbonholdLog then
        pcall(EbonholdLog, "Ashoholic FastSwap: initiating Logout() -> target='" .. tostring(target) .. "'")
    end
    print("|cFF00FF9AAshoholic:|r Swapping to |cff00ff00" .. tostring(target) .. "|r...")

    if AshoholicFrame and AshoholicFrame:IsShown() then
        AshoholicFrame:Hide()
    end
    if GameMenuFrame and GameMenuFrame:IsShown() and HideUIPanel then
        HideUIPanel(GameMenuFrame)
    end
    if Logout then
        Logout()
    end
end

if type(_G.FastSwap_PerformSwap) ~= "function" then
    addon._fallbackFastSwap = function(charName)
        return addon:PerformFastSwap(charName)
    end
    _G.FastSwap_PerformSwap = addon._fallbackFastSwap
end

local version = GetAddOnMetadata(addonName, "Version") or ""
addon.VERSION = string.gsub(version, "^[vV]", "")
addon.Version = version:find("^v") and version or ("v" .. version)

local VERSION_MESSAGE_PREFIX = "ASHOHOLIC_VER"
local VERSION_BROADCAST_COOLDOWN = 600
local VERSION_BROADCAST_MIN_DELAY = 5
local VERSION_BROADCAST_MAX_DELAY = 10
local versionBroadcastScheduled = false

local function NormalizeVersionNumber(value)
    value = string.gsub(value, "^0+", "")
    return value == "" and "0" or value
end

local function ParseVersion(version)
    if type(version) ~= "string" then return nil end
    version = string.gsub(version, "^%s*(.-)%s*$", "%1")
    version = string.gsub(version, "^[vV]", "")
    version = string.match(version, "^([^+]*)") or ""

    local core, prerelease = version, nil
    local dash = string.find(version, "-", 1, true)
    if dash then
        core = string.sub(version, 1, dash - 1)
        prerelease = string.sub(version, dash + 1)
        if prerelease == "" or string.find(prerelease, "%.%.") or
           string.find(prerelease, "^%.") or string.find(prerelease, "%.$") then
            return nil
        end
        for identifier in string.gmatch(prerelease, "[^%.]+") do
            if not string.match(identifier, "^[%w%-]+$") then return nil end
        end
    end

    if core == "" or string.find(core, "%.%.") or
       string.find(core, "^%.") or string.find(core, "%.$") then
        return nil
    end

    local numbers = {}
    for component in string.gmatch(core, "[^%.]+") do
        if not string.match(component, "^%d+$") then return nil end
        numbers[#numbers + 1] = NormalizeVersionNumber(component)
    end
    if #numbers < 1 or #numbers > 3 then return nil end
    while #numbers < 3 do numbers[#numbers + 1] = "0" end

    local prereleaseParts = {}
    if prerelease then
        for identifier in string.gmatch(prerelease, "[^%.]+") do
            prereleaseParts[#prereleaseParts + 1] = identifier
        end
        return numbers, prereleaseParts
    end
    return numbers, nil
end

local function CompareVersionNumbers(left, right)
    left = NormalizeVersionNumber(left)
    right = NormalizeVersionNumber(right)
    if string.len(left) ~= string.len(right) then
        return string.len(left) < string.len(right) and -1 or 1
    end
    if left == right then return 0 end
    return left < right and -1 or 1
end

local function IsVersionHigher(remoteVersion, localVersion)
    local remoteNumbers, remotePrerelease = ParseVersion(remoteVersion)
    local localNumbers, localPrerelease = ParseVersion(localVersion)
    if not remoteNumbers or not localNumbers then return false end

    for i = 1, 3 do
        local comparison = CompareVersionNumbers(remoteNumbers[i], localNumbers[i])
        if comparison ~= 0 then return comparison > 0 end
    end

    if not remotePrerelease and localPrerelease then return true end
    if remotePrerelease and not localPrerelease then return false end
    if not remotePrerelease then return false end

    local maxParts = math.max(#remotePrerelease, #localPrerelease)
    for i = 1, maxParts do
        local remotePart, localPart = remotePrerelease[i], localPrerelease[i]
        if not remotePart then return false end
        if not localPart then return true end
        if remotePart ~= localPart then
            local remoteNumeric = string.match(remotePart, "^%d+$") ~= nil
            local localNumeric = string.match(localPart, "^%d+$") ~= nil
            if remoteNumeric and localNumeric then
                return CompareVersionNumbers(remotePart, localPart) > 0
            elseif remoteNumeric ~= localNumeric then
                return not remoteNumeric
            end
            return remotePart > localPart
        end
    end
    return false
end

addon.IsVersionHigher = IsVersionHigher

function addon:LoadVersionState()
    local options = self.db.global.options
    local latestVersion = options.LatestVersionFound
    if IsVersionHigher(latestVersion, self.VERSION) then
        self.latestVersionFound = latestVersion
        self.isOutdated = true
    else
        options.LatestVersionFound = ""
        self.latestVersionFound = nil
        self.isOutdated = false
    end
end

function addon:RememberRemoteVersion(remoteVersion)
    if not IsVersionHigher(remoteVersion, self.VERSION) then return end

    local options = self.db.global.options
    local latestVersion = options.LatestVersionFound
    if latestVersion ~= "" and not IsVersionHigher(remoteVersion, latestVersion) then return end

    options.LatestVersionFound = remoteVersion
    self.latestVersionFound = remoteVersion
    self.isOutdated = true
    if AshoholicFrame and AshoholicFrame.RefreshVersionNotice then
        AshoholicFrame:RefreshVersionNotice()
    end
end

function addon:OnVersionMessage(event, prefix, message, channel, sender)
    if prefix ~= VERSION_MESSAGE_PREFIX or type(message) ~= "string" then return end
    if sender and UnitName and sender == UnitName("player") then return end
    self:RememberRemoteVersion(message)
end

function addon:BroadcastVersion()
    if not SendAddonMessage then return end

    local options = self.db.global.options
    local now = time()
    local lastBroadcast = tonumber(options.LastVersionBroadcastAt) or 0
    if lastBroadcast > 0 and now - lastBroadcast < VERSION_BROADCAST_COOLDOWN then
        return
    end

    local sent = false
    local function SendVersion(channel)
        local ok = pcall(SendAddonMessage, VERSION_MESSAGE_PREFIX, self.VERSION, channel)
        if ok then sent = true end
    end

    if IsInGuild and IsInGuild() then
        SendVersion("GUILD")
    end

    local raidMembers = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidMembers > 0 then
        SendVersion("RAID")
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        SendVersion("PARTY")
    end

    if sent then
        options.LastVersionBroadcastAt = now
    end
end

function addon:ScheduleVersionBroadcast()
    if versionBroadcastScheduled then return end
    versionBroadcastScheduled = true
    local delay = math.random(VERSION_BROADCAST_MIN_DELAY, VERSION_BROADCAST_MAX_DELAY)
    C_Timer.After(delay, function()
        versionBroadcastScheduled = false
        addon:BroadcastVersion()
    end)
end

local AddonDB_Defaults = {
    global = {
        Characters = {
            ['*'] = {
                name = "",
                level = 1,
                class = "WARRIOR",
                money = 0,
                location = "",
                SavedInstance = {},
                SoulAsh = 0,
                RunSoulAsh = 0,
                SpendableSoulAsh = 0,
                CommittedSoulAsh = 0,
                RaidResetCost = 50000,
            },
        },
        options = {
            MinimapIconAngle = 180,
            ShowMinimap = 1,
            IconStyle_OK = 1,
            IconStyle_NO = 1,
            IconStyle_Unknown = 1,
            IconStyle_Partial = 1,
            Theme = "ember",
            CustomThemes = {},
            CustomThemeOrder = {},
            columnOrder = nil,
            columnWidths = nil,
            LatestVersionFound = "",
            LastVersionBroadcastAt = 0,
            ShowHourlyWidget = 1,
        },
    },
}

function addon:OnInitialize()
    addon.db = LibStub("AceDB-3.0"):New("AshoholicDB", AddonDB_Defaults)
    addon:LoadVersionState()
    addon:RegisterChatCommand("ashoholic", "ChatCommand")
    addon:RegisterChatCommand("ash", "ChatCommand")

    if RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, VERSION_MESSAGE_PREFIX)
        addon:RegisterEvent("CHAT_MSG_ADDON", "OnVersionMessage")
    end

    addon:RegisterEvent("PARTY_MEMBERS_CHANGED", "ScheduleVersionBroadcast")
    addon:RegisterEvent("RAID_ROSTER_UPDATE", "ScheduleVersionBroadcast")
    addon:RegisterEvent("GUILD_ROSTER_UPDATE", "ScheduleVersionBroadcast")
    
    addon:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerLogin")
    addon:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnTargetedEvent")
    addon:RegisterEvent("UPDATE_INSTANCE_INFO", "OnTargetedEvent")
    
    addon:RegisterEvent("PLAYER_MONEY", "UpdateCurrentCharacterData")
    addon:RegisterEvent("CHAT_MSG_CURRENCY", "UpdateCurrentCharacterData")
    addon:RegisterEvent("CHAT_MSG_LOOT", "UpdateCurrentCharacterData")

    local hookFrame = CreateFrame("Frame")
    hookFrame.elapsed = 0
    hookFrame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed > 2 then
            if ProjectEbonhold and ProjectEbonhold.SkillTree and ProjectEbonhold.SkillTree.UpdateTotalSoulPoints and not addon.skillTreeHooked then
                hooksecurefunc(ProjectEbonhold.SkillTree, "UpdateTotalSoulPoints", function(spendable, committed)
                    local realm = GetRealmName()
                    local player = UnitName("player")
                    if not player or player == UNKNOWN then return end
                    
                    local key = format("%s.%s", realm, player)
                    local charDB = addon.db.global.Characters[key]
                    if charDB then
                        charDB.SpendableSoulAsh = spendable or 0
                        charDB.CommittedSoulAsh = committed or 0
                        charDB.SoulAsh = (charDB.RunSoulAsh or 0) + charDB.SpendableSoulAsh
                    end
                end)
                addon.skillTreeHooked = true
            end
            self.elapsed = 0
        end
    end)

    if addon.InitMinimapButton then
        addon:InitMinimapButton()
    end
    if addon.InitHourlyWidget then
        addon:InitHourlyWidget()
    end

    -- Raid entries per hour. Independent of the isLoaded gate so the first
    -- zone event after login is counted.
    local hourlyWatch = CreateFrame("Frame")
    hourlyWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
    hourlyWatch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    hourlyWatch:RegisterEvent("CHAT_MSG_SYSTEM")
    hourlyWatch:SetScript("OnEvent", function(_, event, message)
        if event == "CHAT_MSG_SYSTEM" then
            addon:NoteHourlyInstanceReset(message)
        else
            addon:TrackHourlyInstances()
        end
    end)
end

function addon:OnPlayerLogin()
    addon:ScheduleVersionBroadcast()

    if not _G.FastSwapEventFrame and SetCVar then
        MarkAllSwapSlotsDone()
        if GetCVar then
            local okDrv, drvVal = pcall(GetCVar, FASTSWAP_DRIVER_CVAR)
            if okDrv and type(drvVal) == "string" then
                local pendingTarget, origValue = string.match(drvVal, "^FASTSWAP:([^:]+):?(.*)")
                if pendingTarget and pendingTarget ~= "" then
                    pcall(SetCVar, FASTSWAP_DRIVER_CVAR, (origValue and origValue ~= "") and origValue or "System Default")
                end
            end
            local okCustom, cur = pcall(GetCVar, FASTSWAP_CVAR)
            if okCustom and cur and cur ~= "" then
                pcall(SetCVar, FASTSWAP_CVAR, "")
            end
        end
    end
    C_Timer.After(5, function()
        addon.isLoaded = true
        addon:UpdateCurrentCharacterData()
        addon:UpdateSavedInstances()
        addon:UpdateSoulAshData()
        addon:UpdateRaidResetCost()
    end)
end

function addon:OnTargetedEvent(event)
    if not addon.isLoaded then return end

    addon:UpdateCurrentCharacterData()
    addon:UpdateSavedInstances()
    addon:UpdateSoulAshData()
    -- addon:UpdateRaidResetCost()
    addon:TrackRaidCostReset(nil)

    if AshoholicFrame and AshoholicFrame:IsVisible() then
        if addon.Characters then
            addon.Characters:BuildList()
            if addon.Characters.ReapplySort then
                addon.Characters:ReapplySort()
            end
            addon.Characters:BuildView()
        end
        if AshoholicFrame.Refresh then
            AshoholicFrame:Refresh()
        end
    end
end

function addon:ChatCommand(input)
    input = string.gsub(input or "", "^%s*(.-)%s*$", "%1")
    local cmd = string.lower(input)
    if cmd == "ver check" or cmd == "version check" then
        if addon.isOutdated and addon.latestVersionFound then
            print("|cFFFFD700Ashoholic version check:|r installed v" .. addon.VERSION ..
                ", newer version v" .. addon.latestVersionFound .. " detected.")
        else
            print("|cFFFFD700Ashoholic version check:|r installed v" .. addon.VERSION ..
                "; no newer peer version detected.")
        end
    elseif cmd == "ver reset" or cmd == "version reset" then
        addon.db.global.options.LatestVersionFound = ""
        addon.latestVersionFound = nil
        addon.isOutdated = false
        if AshoholicFrame and AshoholicFrame.RefreshVersionNotice then
            AshoholicFrame:RefreshVersionNotice()
        end
        print("|cFFFFD700Ashoholic version notice cleared.|r")
    elseif cmd == "ver" or cmd == "version" then
        print("Usage: /ash ver check, /ash ver reset, or /ash ver 2.2.0")
    elseif string.match(cmd, "^ver%s+") or string.match(cmd, "^version%s+") then
        local simulatedVersion = string.match(input, "^%S+%s+(.+)$")
        if not IsVersionHigher(simulatedVersion, addon.VERSION) then
            print("|cFFFFD700Ashoholic:|r Test version must be a valid version higher than v" .. addon.VERSION .. ".")
            return
        end

        addon:RememberRemoteVersion(simulatedVersion)
        if not AshoholicFrame then addon:CreateUI() end
        if AshoholicFrame then
            if not AshoholicFrame:IsShown() then AshoholicFrame:Show() end
            if AshoholicFrame.RefreshVersionNotice then
                AshoholicFrame:RefreshVersionNotice()
            end
        end
        print("|cFFFFD700Ashoholic:|r Simulated a peer running v" .. simulatedVersion ..
            ". Use /ash ver reset when finished testing.")
    elseif cmd == "config" or cmd == "options" then
        addon:ToggleConfigUI()
    elseif cmd == "sync" then
        addon:PrintSyncHelp()
    elseif cmd == "widget" then
        addon:ToggleHourlyWidget()
    else
        addon:ToggleUI()
    end
end

function addon:UpdateCurrentCharacterData()
    local realm = GetRealmName()
    local player = UnitName("player")
    if not player or player == UNKNOWN then return end

    local key = format("%s.%s", realm, player)
    local charDB = addon.db.global.Characters[key]
    if not charDB then return end

    -- Prefer the real CVar (unique per WoW account on many servers),
    -- fall back to the user's rename, then to "Main Account".
    local accName = addon.db.global.options.MyAccountName
    if not accName or accName == "" then
        local cvarAcc = GetCVar("accountName")
        if cvarAcc and cvarAcc ~= "" then accName = cvarAcc end
    end
    if not accName or accName == "" then accName = "Main Account" end
    charDB.account = accName

    charDB.name = player
    charDB.level = UnitLevel("player") or 1
    charDB.class = select(2, UnitClass("player")) or "WARRIOR"
    charDB.money = GetMoney() or 0
    charDB.location = GetRealZoneText() or GetZoneText() or ""
    charDB.lastSeen = time()
    charDB._sourceAccount = accName
end

function addon:IsMyCharacter(charDB)
    if not charDB then return false end
    local myName = addon.db.global.options.MyAccountName
    if not myName or myName == "" then
        local cvarAcc = GetCVar("accountName")
        if cvarAcc and cvarAcc ~= "" then myName = cvarAcc end
    end
    if not myName or myName == "" then myName = "Main Account" end

    if charDB._sourceAccount then
        return charDB._sourceAccount == myName
    end
    return (charDB.account or "Main Account") == myName
end

local cachedSpendableAsh = 0
local cachedCommittedAsh = 0

local hookFrame = CreateFrame("Frame")
hookFrame.elapsed = 0
hookFrame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed > 2 then
        if ProjectEbonhold and ProjectEbonhold.SkillTree and ProjectEbonhold.SkillTree.UpdateTotalSoulPoints and not addon.skillTreeHooked then
            hooksecurefunc(ProjectEbonhold.SkillTree, "UpdateTotalSoulPoints", function(spendable, committed)
                cachedSpendableAsh = spendable or 0
                cachedCommittedAsh = committed or 0
                
                local realm = GetRealmName()
                local player = UnitName("player")
                if not player or player == UNKNOWN then return end
                
                local key = format("%s.%s", realm, player)
                local charDB = addon.db.global.Characters[key]
                if charDB then
                    charDB.SpendableSoulAsh = cachedSpendableAsh
                    charDB.CommittedSoulAsh = cachedCommittedAsh
                    charDB.SoulAsh = (charDB.RunSoulAsh or 0) + charDB.SpendableSoulAsh
                end
            end)
            addon.skillTreeHooked = true
        end
        self.elapsed = 0
    end
end)

function addon:UpdateSoulAshData()
    local realm = GetRealmName()
    local player = UnitName("player")
    if not player or player == UNKNOWN then return end
    
    local key = format("%s.%s", realm, player)
    local charDB = addon.db.global.Characters[key]
    if not charDB then return end

    local runAsh = 0
    pcall(function()
        if ProjectEbonhold and ProjectEbonhold.PlayerRunService and ProjectEbonhold.PlayerRunService.GetCurrentData then
            local data = ProjectEbonhold.PlayerRunService.GetCurrentData()
            if data and data.soulPoints then
                runAsh = data.soulPoints
            end
        end
    end)

    local spendableTreeAsh = charDB.SpendableSoulAsh or 0
    pcall(function()
        if _G["GetRemainingTalentPoints"] and type(_G["GetRemainingTalentPoints"]) == "function" then
            spendableTreeAsh = _G["GetRemainingTalentPoints"]()
        elseif _G["TALENT_POINTS_TOTAL"] and type(_G["TALENT_POINTS_TOTAL"]) == "number" then
            spendableTreeAsh = _G["TALENT_POINTS_TOTAL"]
        elseif ProjectEbonhold and ProjectEbonhold.SkillTree then
            local st = ProjectEbonhold.SkillTree
            if st.spendablePoints and type(st.spendablePoints) == "number" then
                spendableTreeAsh = st.spendablePoints
            elseif st.totalUnspentPoints and type(st.totalUnspentPoints) == "number" then
                spendableTreeAsh = st.totalUnspentPoints
            end
        end

        local stFrame = _G["skillTreeFrame"] or _G["ProjectEbonholdSkillTreeFrame"]
        if stFrame and stFrame.pointsText and stFrame.pointsText.GetText then
            local txt = stFrame.pointsText:GetText()
            if txt then
                local clean = txt:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                local digits = clean:gsub("%D", "")
                if digits ~= "" then
                    spendableTreeAsh = tonumber(digits) or spendableTreeAsh
                end
            end
        end
    end)

    -- Committed ash comes from ProjectEbonhold's account-wide counter
    local committedAsh = charDB.CommittedSoulAsh or 0
    pcall(function()
        if ProjectEbonhold and type(ProjectEbonhold.totalCommittedSoulAshes) == "number" then
            committedAsh = ProjectEbonhold.totalCommittedSoulAshes
        end
    end)

    charDB.RunSoulAsh = runAsh
    charDB.SpendableSoulAsh = spendableTreeAsh
    charDB.CommittedSoulAsh = committedAsh
    charDB.SoulAsh = charDB.RunSoulAsh + charDB.SpendableSoulAsh
end

local RAID_COST_BASE = 50000
local RAID_COST_WEEK = 7 * 24 * 60 * 60
local RAID_COST_CYCLE_SLACK = 12 * 60 * 60

local function RefreshOpenRoster()
    if AshoholicFrame and AshoholicFrame:IsVisible() then
        if addon.Characters then
            addon.Characters:BuildList()
            if addon.Characters.ReapplySort then addon.Characters:ReapplySort() end
            addon.Characters:BuildView()
        end
        if AshoholicFrame.Refresh then AshoholicFrame:Refresh() end
    end
end

local function ApplyRaidCostWeeklyReset()
    if not addon.db or not addon.db.global or not addon.db.global.Characters then return end

    local changed = false
    for _, charDB in pairs(addon.db.global.Characters) do
        if charDB.name and charDB.name ~= "" and charDB.RaidResetCost ~= RAID_COST_BASE then
            charDB.RaidResetCost = RAID_COST_BASE
            changed = true
        end
    end

    if changed then
        RefreshOpenRoster()
        print("|cFF00FF9AAshoholic:|r Weekly reset: instance ID costs set to 50,000.")
    end
end

function addon:TrackRaidCostReset(observedResetAt)
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
    local requestId = ProjectEbonhold and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_ACTION_TRACKER_INFO
    local actionId = ProjectEbonhold and ProjectEbonhold.ActionTypes and ProjectEbonhold.ActionTypes.INSTANCE_RESET
    if requestId and actionId and type(ProjectEbonhold.sendToServer) == "function" then
        ProjectEbonhold.sendToServer(requestId, tostring(actionId))
    end
end

--------------------------------------------------------------------------
-- Clear IDs. The server tracker (700) is authoritative for cost and weekly
-- reset time; result (701) confirms whether a clear actually succeeded.
--------------------------------------------------------------------------
local RESET_PROTOCOL_PREFIX = "AAM0x9"
local pendingClearIDs = false

function addon:GetCurrentCharacterDB()
    local player = UnitName("player")
    if not player or player == UNKNOWN or not addon.db then return nil end
    return addon.db.global.Characters[format("%s.%s", GetRealmName(), player)], player
end

function addon:OnIDsCleared()
    local charDB = addon:GetCurrentCharacterDB()
    if charDB then
        if addon.RaidData then addon.RaidData:ClearKills(charDB) end
        if type(charDB.hourlyGen) == "table" then
            for key, value in pairs(charDB.hourlyGen) do
                charDB.hourlyGen[key] = (value or 0) + 1
            end
        end
    end
    if RequestRaidInfo then RequestRaidInfo() end
    addon:UpdateRaidResetCost()
    C_Timer.After(1.5, function()
        RefreshOpenRoster()
    end)
end

local function ApplyRaidResetTracker(body)
    local actionId, count, nextResetTime = string.match(body, "^(%d+),(%d+),(%d+)$")
    actionId = tonumber(actionId)
    count = tonumber(count)
    nextResetTime = tonumber(nextResetTime)
    local resetType = ProjectEbonhold and ProjectEbonhold.ActionTypes and ProjectEbonhold.ActionTypes.INSTANCE_RESET
    if not resetType or actionId ~= resetType or not count or not nextResetTime then return end

    local config = ProjectEbonhold and ProjectEbonhold.InstanceResetConfig
    if not config or type(config.BASE_COST) ~= "number" or type(config.COST_MULTIPLIER) ~= "number" then return end
    local cost = config.BASE_COST
    for _ = 1, count do
        cost = cost * config.COST_MULTIPLIER
        if cost >= 2147483647 then
            cost = 2147483647
            break
        end
    end

    addon:TrackRaidCostReset(nextResetTime > 0 and nextResetTime or nil)
    local charDB = addon:GetCurrentCharacterDB()
    if charDB and charDB.RaidResetCost ~= cost then
        charDB.RaidResetCost = cost
        RefreshOpenRoster()
    end
end

function addon:ClearInstanceIDs()
    local requestId = ProjectEbonhold and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_INSTANCE_RESET_ALL
    if not requestId or type(ProjectEbonhold.sendToServer) ~= "function" then
        print("|cFF00FF9AAshoholic:|r |cffff4040Clear IDs is not available right now.|r")
        return
    end
    if pendingClearIDs then return end
    pendingClearIDs = true
    ProjectEbonhold.sendToServer(requestId, "")
    C_Timer.After(8, function()
        pendingClearIDs = false
    end)
end

local resetAckFrame = CreateFrame("Frame")
resetAckFrame:RegisterEvent("CHAT_MSG_ADDON")
resetAckFrame:SetScript("OnEvent", function(_, _, prefix, payload)
    if prefix ~= RESET_PROTOCOL_PREFIX or type(payload) ~= "string" then return end

    local eventId, body = string.match(payload, "^(%d+)\t(.*)$")
    eventId = tonumber(eventId)
    if eventId == ProjectEbonhold.SS.SEND_ACTION_TRACKER_INFO then
        ApplyRaidResetTracker(body)
    elseif eventId == ProjectEbonhold.SS.SEND_INSTANCE_RESET_RESULT then
        local resultCode = tonumber(string.match(body, "^(%d+),%d+$"))
        if not pendingClearIDs or not resultCode then return end
        pendingClearIDs = false
        if resultCode == 0 then
            addon:OnIDsCleared()
        end
    end
end)

function addon:UpdateSavedInstances()
    local realm = GetRealmName()
    local player = UnitName("player")
    if not player or player == UNKNOWN then return end
    
    local key = format("%s.%s", realm, player)
    local charDB = addon.db.global.Characters[key]
    if not charDB then return end

    charDB.SavedInstance = charDB.SavedInstance or {}
    wipe(charDB.SavedInstance)
    charDB.RaidLockouts = charDB.RaidLockouts or {}
    wipe(charDB.RaidLockouts)
    local scanTime = time()

    for i = 1, GetNumSavedInstances() do
        -- reset is seconds remaining at this moment, not an absolute timestamp.
        -- Value fields: remaining|checkedAt|difficulty|isRaid. The key stays
        -- "Name (size)" so world-tour detection can keep matching 10 and 25.
        local name, id, reset, difficulty, locked, extended, _, isRaid, maxPlayers, difficultyName = GetSavedInstanceInfo(i)
        if locked and name then
            local keyName = name .. " (" .. (maxPlayers or 10) .. ")"
            local diff = ""
            if type(difficultyName) == "string" and difficultyName ~= "" then
                diff = difficultyName:gsub("|", "/")
            elseif difficulty == 3 or difficulty == 4
                or (difficulty == 2 and (maxPlayers or 5) <= 5) then
                diff = "Heroic"
            end
            charDB.SavedInstance[keyName] =
                (reset or 0) .. "|" .. time() .. "|" .. diff .. "|" .. (isRaid and "1" or "0")

            local raidData = addon.RaidData
            local group = isRaid and raidData and raidData:FindGroup(name)
            local variant = group and raidData.DifficultyVariant[tonumber(difficulty)]
            if variant then
                charDB.RaidLockouts[raidData.LockKey(group, variant)] =
                    { id = id, resetAt = scanTime + (reset or 0) }
            end
        end
    end
    charDB.wtScanned = true
    if addon.RaidData then addon.RaidData:PruneKills(charDB) end
end

--------------------------------------------------------------------------
-- Raids per hour. Ebonhold allows 10 raid entries in a rolling hour.
-- A raid copy is name + difficulty + leader (or solo) + reset generation,
-- matching LockoutInfo: re-entering the same copy does not take a new slot,
-- and the hour restarts when that copy is entered or left.
--------------------------------------------------------------------------
local HOURLY_WINDOW = 3600

local hourlyWasInRaid = false
local hourlySig = nil
local hourlyVisit = nil
local hourlyReady = false

function addon:ClearHourlyVisit()
    hourlyVisit = nil
    hourlyWasInRaid = false
    hourlySig = nil
end

local function HourlyCharDB()
    if not addon.db or not addon.db.global or not addon.db.global.Characters then return nil end
    local realm = GetRealmName()
    local player = UnitName("player")
    if not player or player == "" or player == UNKNOWN then return nil end
    local key = format("%s.%s", realm, player)
    local charDB = addon.db.global.Characters[key]
    if not charDB then return nil end
    if rawget(charDB, "hourlyEntries") == nil then charDB.hourlyEntries = {} end
    if rawget(charDB, "hourlyGen") == nil then charDB.hourlyGen = {} end
    charDB.hourlyTracked = true
    return charDB
end

local function HourlyPrune(charDB, now)
    local entries = charDB.hourlyEntries
    if type(entries) ~= "table" then return end
    for i = #entries, 1, -1 do
        local entry = entries[i]
        local stamp = (type(entry) == "table" and entry.time) or 0
        if now - stamp >= HOURLY_WINDOW then table.remove(entries, i) end
    end
    while #entries > 30 do table.remove(entries) end
end

local function HourlyLeader()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 then
                local unit = "raid" .. i
                local guid = UnitGUID and UnitGUID(unit)
                return "LEADER:" .. tostring(guid or name or "UNKNOWN")
            end
        end
        return "LEADER:UNKNOWN"
    end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        local index = GetPartyLeaderIndex and GetPartyLeaderIndex() or nil
        if index == 0 then
            local guid = UnitGUID and UnitGUID("player")
            return "LEADER:" .. tostring(guid or UnitName("player") or "PLAYER")
        end
        if index and index > 0 then
            local unit = "party" .. index
            local guid = UnitGUID and UnitGUID(unit)
            return "LEADER:" .. tostring(guid or UnitName(unit) or ("PARTY" .. index))
        end
        return "LEADER:UNKNOWN"
    end
    return "SOLO"
end

local function HourlyIdentity(charDB, name, diff, leader)
    local key = tostring(name or "?") .. "#" .. tostring(diff or 0)
    if charDB.hourlyGen[key] == nil then charDB.hourlyGen[key] = 0 end
    return "copy:" .. key .. ":" .. tostring(leader or "SOLO") .. ":gen:" .. tostring(charDB.hourlyGen[key])
end

local function HourlyFind(charDB, identity)
    local entries = charDB.hourlyEntries
    for i = 1, #entries do
        if entries[i] and entries[i].identity == identity then return entries[i] end
    end
end

local function HourlyRead()
    local inside, kind = IsInInstance()
    if not (inside and kind == "raid") then return false end
    local name, _, diff = GetInstanceInfo()
    return true, name, diff
end

local function HourlyEnter(name, diff, leader)
    local charDB = HourlyCharDB()
    if not charDB or not name or name == "" then return end
    leader = leader or HourlyLeader()
    local now = time()
    local identity = HourlyIdentity(charDB, name, diff, leader)
    local row = HourlyFind(charDB, identity)
    if row then
        row.time = now
        row.name = name
        row.difficulty = diff or row.difficulty or 0
        row.leader = leader
    else
        table.insert(charDB.hourlyEntries, 1, {
            time = now,
            name = name,
            difficulty = diff or 0,
            identity = identity,
            leader = leader,
        })
    end
    HourlyPrune(charDB, now)
    hourlyVisit = {
        name = name,
        difficulty = diff or 0,
        identity = identity,
        leader = leader,
    }
end

local function HourlyLeave()
    local visit = hourlyVisit
    hourlyVisit = nil
    if not visit then return end
    local charDB = HourlyCharDB()
    if not charDB then return end
    local now = time()
    local row = HourlyFind(charDB, visit.identity)
    if not row then
        row = {
            identity = visit.identity,
            name = visit.name,
            difficulty = visit.difficulty,
            leader = visit.leader,
        }
        table.insert(charDB.hourlyEntries, 1, row)
    end
    row.time = now
    row.name = visit.name or row.name
    row.difficulty = visit.difficulty or row.difficulty or 0
    HourlyPrune(charDB, now)
end

function addon:TrackHourlyInstances()
    local charDB = HourlyCharDB()
    if not charDB then return end

    local inside, name, diff = HourlyRead()
    local leader = inside and HourlyLeader() or nil
    local sig = nil
    if inside and name and name ~= "" then
        sig = HourlyIdentity(charDB, name, diff, leader)
    end

    if not hourlyReady then
        hourlyReady = true
        if inside and name and name ~= "" then HourlyEnter(name, diff, leader) end
    elseif inside then
        if not hourlyWasInRaid then
            if name and name ~= "" then HourlyEnter(name, diff, leader) end
        elseif sig ~= hourlySig then
            HourlyLeave()
            if name and name ~= "" then HourlyEnter(name, diff, leader) end
        elseif not hourlyVisit and name and name ~= "" then
            HourlyEnter(name, diff, leader)
        end
    elseif hourlyWasInRaid then
        HourlyLeave()
    end

    hourlyWasInRaid = inside and true or false
    hourlySig = sig
    if addon.RefreshHourlyWidget then addon:RefreshHourlyWidget() end
end

function addon:NoteHourlyInstanceReset(message)
    if type(message) ~= "string" or type(INSTANCE_RESET_SUCCESS) ~= "string" then return end
    local pattern = string.gsub(INSTANCE_RESET_SUCCESS, "%%s", "(.+)")
    local inst = string.match(message, pattern)
    if not inst or inst == "" then return end
    local charDB = HourlyCharDB()
    if not charDB or type(charDB.hourlyGen) ~= "table" then return end
    for key, value in pairs(charDB.hourlyGen) do
        if string.find(key, inst, 1, true) == 1 then
            charDB.hourlyGen[key] = (value or 0) + 1
        end
    end
end

function addon:ResetAllSoulAsh(chatMsg)
    if not addon.db or not addon.db.global or not addon.db.global.Characters then return end

    local didReset = false
    for key, charDB in pairs(addon.db.global.Characters) do
        if addon:IsMyCharacter(charDB) then
            if (charDB.SoulAsh or 0) ~= 0 or (charDB.RunSoulAsh or 0) ~= 0 or
               (charDB.SpendableSoulAsh or 0) ~= 0 or (charDB.CommittedSoulAsh or 0) ~= 0 then
                didReset = true
            end
            charDB.SoulAsh = 0
            charDB.RunSoulAsh = 0
            charDB.SpendableSoulAsh = 0
            charDB.CommittedSoulAsh = 0
        end
    end

    if AshoholicFrame and AshoholicFrame:IsVisible() then
        if addon.Characters then
            addon.Characters:BuildList()
            if addon.Characters.ReapplySort then addon.Characters:ReapplySort() end
            addon.Characters:BuildView()
        end
        if AshoholicFrame.Refresh then
            AshoholicFrame:Refresh()
        end
    end

    if chatMsg and didReset then
        print("|cFF00FF9AAshoholic:|r " .. chatMsg)
    end
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

-- Watch the confirm dialog (fires if the dialog appears, e.g. manual prestige)
local prestigeFrame = CreateFrame("Frame")
prestigeFrame.timer = 0
prestigeFrame:SetScript("OnUpdate", function(self, elapsed)
    self.timer = self.timer + elapsed
    if self.timer > 1.0 then
        self.timer = 0
        local confirmFrame = _G["EbonholdPrestigeConfirmFrame"]
        if confirmFrame and confirmFrame:IsVisible() then
            local btn = FindPrestigeButton(confirmFrame)
            if btn and not btn.ashHooked then
                btn:HookScript("OnClick", function()
                    addon:ResetAllSoulAsh("Prestige complete — this account's Soul Ash has been reset.")
                end)
                btn.ashHooked = true
            end
        end
    end
end)

-- Primary hook: watch for ProjectEbonhold.PrestigeService.DoPrestige() itself.
-- This is what CherryPicker calls directly, so it fires for both manual and
-- auto-prestige without depending on the confirm dialog.
--
-- Do not treat a level drop as a prestige. Accepting death (Release Spirit)
-- also sends the character back to level 1 and banks that run's Soul Ash into
-- the tree. Prestige is the only path that burns the account wallet, and it
-- does not change level.
local prestigeHookFrame = CreateFrame("Frame")
prestigeHookFrame.elapsed = 0
prestigeHookFrame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 2 then return end
    self.elapsed = 0
    if addon.prestigeHooked then return end
    if ProjectEbonhold
       and ProjectEbonhold.PrestigeService
       and type(ProjectEbonhold.PrestigeService.DoPrestige) == "function" then
        hooksecurefunc(ProjectEbonhold.PrestigeService, "DoPrestige", function()
            addon:ResetAllSoulAsh("Prestige complete — this account's Soul Ash has been reset.")
        end)
        addon.prestigeHooked = true
    end
end)

function addon:ResetAllCharacterData()
    if not addon.db or not addon.db.global or not addon.db.global.Characters then return end

    local realm  = GetRealmName()
    local player = UnitName("player")
    if not player or player == UNKNOWN then return end
    local currentKey = format("%s.%s", realm, player)

    -- 1. Reset every tracked field on the character currently being played
    local currentChar = addon.db.global.Characters[currentKey]
    if currentChar then
        currentChar.SavedInstance      = {}
        currentChar.RaidLockouts       = {}
        currentChar.RaidKills          = nil
        currentChar.wtScanned          = false
        currentChar.RaidResetCost      = 50000
        currentChar.SoulAsh            = 0
        currentChar.RunSoulAsh         = 0
        currentChar.SpendableSoulAsh   = 0
        currentChar.CommittedSoulAsh   = 0
        currentChar.money              = 0
        currentChar.location           = ""
        currentChar.lastSeen           = 0
        currentChar.hourlyEntries      = {}
        currentChar.hourlyGen          = {}
        currentChar.hourlyTracked      = true
        if addon.ClearHourlyVisit then addon:ClearHourlyVisit() end
        if addon.TrackHourlyInstances then addon:TrackHourlyInstances() end
    end

    -- 2. Delete every OTHER character on this account
    local toDelete = {}
    for key, charDB in pairs(addon.db.global.Characters) do
        if key ~= currentKey and addon:IsMyCharacter(charDB) then
            toDelete[#toDelete + 1] = key
        end
    end
    for _, key in ipairs(toDelete) do
        addon.db.global.Characters[key] = nil
    end

    if AshoholicFrame and AshoholicFrame:IsVisible() then
        if addon.Characters then
            addon.Characters:BuildList()
            if addon.Characters.ReapplySort then addon.Characters:ReapplySort() end
            addon.Characters:BuildView()
        end
        if AshoholicFrame.Refresh then AshoholicFrame:Refresh() end
    end
end

--------------------------------------------------------------------------
-- Custom theme draft lifecycle
--------------------------------------------------------------------------
local function HexFromRGB(c)
    return string.format("%02X%02X%02X",
        math.floor(c[1]*255+0.5), math.floor(c[2]*255+0.5), math.floor(c[3]*255+0.5))
end
local function CodeToHex(code)
    return code:match("|c%x%x(%x%x%x%x%x%x)")
end

function addon:BeginDraft(fromKey)
    addon.customizeDirty = false
    fromKey = fromKey or addon.db.global.options.Theme
    addon.previousTheme = fromKey
    addon.db.global.options.Theme = fromKey
    local base = addon.Themes:GetDef(fromKey)
    local draft = addon.Themes:DeepCopy(base)
    -- Refresh source def in case byKey was mutated (e.g. theme cards were rebuilt)
    if addon.Themes.byKey[fromKey] then
        base = addon.Themes.byKey[fromKey]
        draft = addon.Themes:DeepCopy(base)
    end
    draft.key = "draft"
    draft.isCustom = true
    draft.originalKey = fromKey

    if draft.layout and draft.layout.fontDelta and not draft.layout.fontSize then
        draft.layout.fontSize = 12 + draft.layout.fontDelta
    end

    -- Backwards compat: if fontSize is set but per-type sizes aren't,
    -- propagate fontSize to all four — matches what Build() does at runtime,
    -- so the draft shows the SAME values as the applied theme.
    if draft.layout and draft.layout.fontSize and
       not (draft.layout.realmFontSize or draft.layout.accountFontSize or
            draft.layout.characterFontSize or draft.layout.totalsFontSize) then
        draft.layout.realmFontSize     = draft.layout.fontSize
        draft.layout.accountFontSize   = draft.layout.fontSize
        draft.layout.characterFontSize = draft.layout.fontSize
        draft.layout.totalsFontSize    = draft.layout.fontSize
    end

    -- Only copy fields the SOURCE DEF explicitly sets. Every other colour
    -- stays nil in the draft so it re-derives from bg / accent / accent2.
    local explicitColorFields = {
        "bg", "accent", "accent2", "body", "gold", "ember", "muted", "soul", "loc", "dim",
        "border", "bronze",
        "titleLo", "titleHi", "accentDim", "accentBright",
        "rowA", "rowB", "rowRealm", "rowAccount", "rowTotal", "rowHover", "rowTopLine",
        "currentCharacterLine",
        "sortArrow", "realmAccentBar", "accountAccentBar", "totalsAccentBar", "characterAccentBar",
        "tabBg", "tabBorder", "tabActiveBg", "tabActiveBorder", "tabHoverBg", "tabHoverBorder",
        "dangerBg", "dangerBorder", "dangerHoverBg", "dangerHoverBorder",
        "sliderBg", "sliderBorder",
        "btnBg", "btnBorder", "btnHoverBg", "btnHoverBorder", "btnText",
        "dangerText",
        "titleText", "settingsTitleText", "headerText", "sectionHeaderText", "totalsText",
        "nameColor", "levelColor", "costColor", "moneyColor", "wtLabel", "accountName",
        "wtLvlLocked", "wtLvlUnlocked",
        "tabText", "tabActiveText", "tabHoverText",
    }
    for _, f in ipairs(explicitColorFields) do
        if draft[f] == nil and base[f] ~= nil then
            draft[f] = base[f]  -- keep the string from the def, don't re-derive
        end
    end

    -- Booleans + percentages. Use the LIVE palette (Get) for fallback values
    -- rather than hardcoded defaults, so a custom theme that stores `false`
    -- for any of these fields never appears to "revert to default" in edit
    -- mode. Only convert values that are genuinely in fraction form
    -- (0 < v < 1), so a real percentage of 1% or 0% is not multiplied.
    local builtForFlags = addon.Themes:Get(fromKey)
    -- panelAlpha is legacy (pre-per-color-opacity). Force it to 100 so it
    -- never compounds down the bg color's own alpha across edit cycles.
    draft.panelAlpha = 100
    if draft.glow == nil then
        draft.glow = (builtForFlags and builtForFlags.glow and builtForFlags.glow[4] or 0.13) * 100
    elseif draft.glow > 0 and draft.glow < 1 then
        draft.glow = draft.glow * 100
    end
    -- NB: use explicit if/else here. Lua's `and ... or true` idiom is broken
    -- when the middle operand can be `false` — it always yields `true`.
    if draft.classColoredNames == nil then
        if builtForFlags and builtForFlags.classColoredNames == false then
            draft.classColoredNames = false
        else
            draft.classColoredNames = true
        end
    end
    if draft.showClassIcons == nil then
        if builtForFlags and builtForFlags.showClassIcons == false then
            draft.showClassIcons = false
        else
            draft.showClassIcons = true
        end
    end
    if draft.classColoredAccent == nil then
        if builtForFlags and builtForFlags.classColoredAccent == false then
            draft.classColoredAccent = false
        else
            draft.classColoredAccent = true
        end
    end
    if draft.outerBorder == nil then
        if builtForFlags and builtForFlags.outerBorder == false then
            draft.outerBorder = false
        else
            draft.outerBorder = true
        end
    end
    if draft.formatResetCost == nil then
        draft.formatResetCost = (builtForFlags and builtForFlags.formatResetCost) or false
    end
    if draft.formatClearIDs == nil then
        draft.formatClearIDs = (builtForFlags and builtForFlags.formatClearIDs) or false
    end
    if draft.formatSoulAsh == nil then
        draft.formatSoulAsh = (builtForFlags and builtForFlags.formatSoulAsh) or false
    end
    if draft.formatMoney == nil then
        draft.formatMoney = (builtForFlags and builtForFlags.formatMoney) or false
    end
    if draft.moneyGoldOnly == nil then
        draft.moneyGoldOnly = (builtForFlags and builtForFlags.moneyGoldOnly) or false
    end
    if draft.costResetWeekday == nil then
        draft.costResetWeekday = (builtForFlags and builtForFlags.costResetWeekday) or false
    end

    addon.Themes:EnsureLayout(draft)

    -- If the source theme has no explicit column widths, inherit the current
    -- (user-adjusted) ones so entering Customize doesn't reset the columns.
    if draft.columnWidths == nil then
        local o = addon.db.global.options
        if o.columnWidths and next(o.columnWidths) then
            draft.columnWidths = {}
            for k, v in pairs(o.columnWidths) do draft.columnWidths[k] = v end
        end
    end

    -- Sanity-clamp layout values so a corrupted custom theme can't hide the whole roster
    local L = draft.layout
    -- Guarantee a valid title font even for themes that lost it
    if not L.titleFont or L.titleFont == "" then
        L.titleFont = "Fonts\\MORPHEUS.TTF"
    end
    L.rowHeight          = math.max(16, math.min(44, L.rowHeight or 24))
    L.rowStep            = math.max(L.rowHeight + 1, math.min(52, L.rowStep or 26))
    L.fontSize           = math.max(8,  math.min(22, L.fontSize or 12))
    L.realmFontSize      = math.max(8,  math.min(22, L.realmFontSize or 12))
    L.accountFontSize    = math.max(8,  math.min(22, L.accountFontSize or 12))
    L.characterFontSize  = math.max(8,  math.min(22, L.characterFontSize or 12))
    L.totalsFontSize     = math.max(8,  math.min(22, L.totalsFontSize or 12))
    L.headerFontSize     = math.max(8,  math.min(22, L.headerFontSize or 12))
    L.titleSize          = math.max(10, math.min(32, L.titleSize or 20))
    L.classIconSize      = math.max(10, math.min(24, L.classIconSize or 14))
    L.wtIconSize         = math.max(14, math.min(32, L.wtIconSize or 22))

    -- Synchronise the draft's layout with the APPLIED palette's layout.
    -- This picks up any values Build() derives (e.g. fontSize propagation),
    -- so the Customize widgets show exactly what the menu shows.
    local built = addon.Themes:Get(fromKey)
    if built and built.layout then
        for k, v in pairs(built.layout) do
            L[k] = v
        end
    end

    addon.customDraft = draft
    addon.Themes.byKey["draft"] = draft
    addon.Themes:Invalidate("draft")
    addon:ApplyTheme("draft")
end

function addon:ApplyDraft()
    if not addon.customDraft then return end
    addon.customizeDirty = true
    addon.Themes.byKey["draft"] = addon.customDraft
    addon.Themes:Invalidate("draft")
    addon:ApplyTheme("draft")
end

function addon:CancelDraft()
    if not addon.customDraft then return end
    addon.Themes.byKey["draft"] = nil
    addon.Themes:Invalidate("draft")
    local prev = addon.previousTheme or addon.Themes.default
    addon.customDraft = nil
    addon.previousTheme = nil
    addon.customizeDirty = false
    addon:ApplyTheme(prev)
end

function addon:SaveDraftAsNew(name)
    if not addon.customDraft then return end
    local key = addon.Themes:GenerateKey()
    local def = addon.Themes.DeepCopy(addon.customDraft)
    def.key = key; def.name = name
    addon.Themes:SaveCustom(key, def)
    addon.Themes.byKey["draft"] = nil
    addon.Themes:Invalidate("draft")
    addon.customDraft = nil
    addon.previousTheme = nil
    addon.customizeDirty = false
    addon:ApplyTheme(key)
end

function addon:SaveDraftToExisting(key)
    if not key then return end
    if not addon.customDraft then
        addon:ApplyTheme(key)
        return
    end

    local existing = addon.Themes:GetDef(key)
    local def = addon.Themes.DeepCopy(addon.customDraft)
    def.key          = key
    def.isCustom     = true
    def.originalKey  = nil                       -- draft-only field

    -- Preserve the name from the existing preset
    if not def.name or def.name == "" then
        def.name = (existing and existing.name) or key
    end

    -- === Guarantee every layout key is present ===
    -- Compare the draft's layout against the palette currently applied to the
    -- menu. If a key is missing on the draft, take it from the LIVE palette
    -- (which is what the user is actually looking at right now).
    addon.Themes:EnsureLayout(def)
    local live = addon.Themes:Get(addon.db.global.options.Theme)
    if live and live.layout then
        for k, v in pairs(live.layout) do
            if def.layout[k] == nil then
                def.layout[k] = v
            end
        end
    end

    -- Same for top-level colour/flag overrides that the draft may have
    -- dropped. Only fill in if the current live theme has them set explicitly
    -- (i.e. don't overwrite the user's intentional "use default" choices).
    local keepFields = {
        "bg","accent","accent2","body","gold","ember","muted","soul","loc","dim",
        "border","bronze","titleLo","titleHi","accentDim","accentBright",
        "rowA","rowB","rowRealm","rowAccount","rowTotal","rowHover","rowTopLine",
        "currentCharacterLine",
        "sortArrow","realmAccentBar","accountAccentBar","totalsAccentBar","characterAccentBar",
        "tabBg","tabBorder","tabActiveBg","tabActiveBorder","tabHoverBg","tabHoverBorder",
        "dangerBg","dangerBorder","dangerHoverBg","dangerHoverBorder",
        "sliderBg","sliderBorder",
        "btnBg","btnBorder","btnHoverBg","btnHoverBorder","btnText","dangerText",
        "titleText","settingsTitleText","headerText","sectionHeaderText","totalsText",
        "nameColor","levelColor","costColor","moneyColor","wtLabel","accountName",
        "wtLvlLocked","wtLvlUnlocked",
        "tabText","tabActiveText","tabHoverText",
    }
    for _, f in ipairs(keepFields) do
        if def[f] == nil and existing and existing[f] ~= nil then
            def[f] = existing[f]
        end
    end

    -- Boolean/number flags: fall back to the existing def if the draft
    -- somehow dropped them. Prevents a stray "revert to default" on save.
    for _, f in ipairs({
        "classColoredNames","showClassIcons","classColoredAccent","outerBorder",
        "formatResetCost","formatClearIDs","formatSoulAsh","formatMoney","moneyGoldOnly",
        "costResetWeekday",
        "panelAlpha","glow",
    }) do
        if def[f] == nil and existing and existing[f] ~= nil then
            def[f] = existing[f]
        end
    end

    addon.Themes:SaveCustom(key, def)

    -- Clear draft state, force cache invalidation, reapply
    addon.Themes.byKey["draft"] = nil
    addon.Themes:Invalidate("draft")
    addon.customDraft = nil
    addon.previousTheme = nil
    addon.Themes:Invalidate(key)   -- belt & braces (SaveCustom already does this)

    addon.customizeDirty = false
    addon:ApplyTheme(key)
end

function addon:ShowAccountRename(accKey, currentName)
    StaticPopupDialogs["ASH_RENAME_ACCOUNT"] = StaticPopupDialogs["ASH_RENAME_ACCOUNT"] or {
        text = "Rename this account group:",
        button1 = OKAY, button2 = CANCEL, hasEditBox = true,
        OnShow = function(self)
            self.editBox:SetText(currentName or "")
            self.editBox:HighlightText(); self.editBox:SetFocus()
        end,
        OnAccept = function(self)
            local newName = self.editBox:GetText()
            if not newName or newName == "" then return end

            -- Rename only characters that currently say (currentName) AND
            -- were created/updated on THIS account. The `_sourceAccount`
            -- marker is set by UpdateCurrentCharacterData; if it's missing
            -- we assume the character belongs to this account (legacy data).
            local myTag = addon.db.global.options.MyAccountName or "Main Account"
            for _, charDB in pairs(addon.db.global.Characters) do
                local acc = charDB.account or "Main Account"
                local src = charDB._sourceAccount
                if acc == currentName and (src == nil or src == myTag or src == currentName) then
                    charDB.account = newName
                    charDB._sourceAccount = myTag
                end
            end

            addon.db.global.options.MyAccountName = newName
            if addon.Characters and AshoholicFrame then
                addon.Characters:BuildList()
                if addon.Characters.ReapplySort then addon.Characters:ReapplySort() end
                addon.Characters:BuildView()
                AshoholicFrame:Refresh()
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("ASH_RENAME_ACCOUNT")
end

function addon:PrintSyncHelp()
    print("|cFFFFD700Ashoholic — Multi-Account Sync|r")
    print(" ")
    print("To see characters from |cFFFFFFFFmultiple WoW accounts|r in one roster:")
    print(" ")
    print("|cFF00FF9A1.|r Log into each account once, play briefly, then log out.")
    print(" ")
    print("|cFF00FF9A2.|r Launch the game with |cFFFFFFFFAshoholic.bat|r")
    print("     in this addon folder (Interface\\AddOns\\Ashoholic\\).")
    print("     Each launch merges every account's character data,")
    print("     then starts the client.")
    print(" ")
    print("You only need to do this |cFFFFFFFFonce per computer|r.")
    print("Deletions: right-click a character row to remove it from the roster.")
end

function addon:ToggleUI()
    if pcall then pcall(RequestRaidInfo) end
    addon:UpdateCurrentCharacterData()
    addon:UpdateSavedInstances()
    addon:UpdateSoulAshData()
    addon:UpdateRaidResetCost()

    if addon.Characters then
        addon.Characters:BuildList()
        if addon.Characters.ReapplySort then
            addon.Characters:ReapplySort()
        end
        addon.Characters:BuildView()
    end

    if addon.CreateUI then
        addon:CreateUI()
    end

    if AshoholicFrame then
        if AshoholicFrame:IsVisible() then
            AshoholicFrame:Hide()
        else
            if AshoholicFrame.Refresh then
                AshoholicFrame:Refresh()
            end
            AshoholicFrame:Show()
        end
    end
end