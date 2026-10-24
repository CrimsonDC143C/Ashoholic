local addonName = ...
_G[addonName] = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
local addon = _G[addonName]

local version = GetAddOnMetadata(addonName, "Version") or ""
addon.Version = version:find("^v") and version or ("v" .. version)

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
        },
    },
}

function addon:OnInitialize()
    addon.db = LibStub("AceDB-3.0"):New("AshoholicDB", AddonDB_Defaults)
    addon:RegisterChatCommand("ashoholic", "ChatCommand")
    addon:RegisterChatCommand("ash", "ChatCommand")
    
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
end

function addon:OnPlayerLogin()
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
    local cmd = string.lower(input or "")
    if cmd == "config" or cmd == "options" then
        addon:ToggleConfigUI()
    elseif cmd == "sync" then
        addon:PrintSyncHelp()
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

local RAID_COST_BASE = 50000
local RAID_COST_WEEK = 7 * 24 * 60 * 60
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
    if not hasSeconds then
        duration = duration + 60
    end
    return duration
end

local function ExtractResetCountdown(framesTexts)
    for i, text in ipairs(framesTexts) do
        if text and string.find(string.lower(text), "cost reset") then
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

local isScrapingCost = false

function addon:UpdateRaidResetCost()
    if isScrapingCost then return end
    isScrapingCost = true

    local wasFriendsShown = FriendsFrame and FriendsFrame:IsVisible()
    local wasRaidShown = RaidFrame and RaidFrame:IsVisible()

    if FriendsFrame_LoadUI then FriendsFrame_LoadUI() end

    -- Open it once in the background
    if not wasFriendsShown and FriendsFrame then
        FriendsFrame:Show()
    end
    if not wasRaidShown and RaidFrame then
        RaidFrame:Show()
    end

    local cost = nil
    local observedResetAt = nil
    local rf1 = _G["RaidFrameNotInRaid"]
    local rf2 = _G["RaidFrame"]
    
    if (rf1 and rf1:IsVisible()) or (rf2 and rf2:IsVisible()) then
        wipe(gatheredTexts)
        GatherAllTexts(_G["FriendsFrame"])
        cost = ExtractCostFromList(gatheredTexts)
        local countdown = ExtractResetCountdown(gatheredTexts)
        if countdown then
            observedResetAt = time() + countdown
        end
    end

    -- Check the weekly reset deadline even if the countdown wasn't scraped
    -- this call, so it fires after weeks of being offline too.
    addon:TrackRaidCostReset(observedResetAt)

    -- Close it immediately back to how it was
    if not wasRaidShown and RaidFrame then
        RaidFrame:Hide()
    end
    if not wasFriendsShown and FriendsFrame then
        FriendsFrame:Hide()
    end

    if cost then
        local currentCharacter = UnitName("player")
        local realm = GetRealmName()
        local key = format("%s.%s", realm, currentCharacter)
        local charDB = addon.db.global.Characters[key]
        if charDB then
            charDB.RaidResetCost = cost
        end
    end

    isScrapingCost = false
end

function addon:UpdateSavedInstances()
    local realm = GetRealmName()
    local player = UnitName("player")
    if not player or player == UNKNOWN then return end
    
    local key = format("%s.%s", realm, player)
    local charDB = addon.db.global.Characters[key]
    if not charDB then return end

    charDB.SavedInstance = charDB.SavedInstance or {}
    wipe(charDB.SavedInstance)

    for i = 1, GetNumSavedInstances() do
        local name, id, reset, difficulty, locked, extended, _, isRaid, maxPlayers = GetSavedInstanceInfo(i)
        if locked and name then
            local keyName = name .. " (" .. (maxPlayers or 10) .. ")"
            charDB.SavedInstance[keyName] = (reset or 0) .. "|" .. time()
        end
    end
    charDB.wtScanned = true
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
        currentChar.wtScanned          = false
        currentChar.RaidResetCost      = 50000
        currentChar.SoulAsh            = 0
        currentChar.RunSoulAsh         = 0
        currentChar.SpendableSoulAsh   = 0
        currentChar.CommittedSoulAsh   = 0
        currentChar.money              = 0
        currentChar.location           = ""
        currentChar.lastSeen           = 0
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
    if draft.formatSoulAsh == nil then
        draft.formatSoulAsh = (builtForFlags and builtForFlags.formatSoulAsh) or false
    end
    if draft.formatMoney == nil then
        draft.formatMoney = (builtForFlags and builtForFlags.formatMoney) or false
    end
    if draft.moneyGoldOnly == nil then
        draft.moneyGoldOnly = (builtForFlags and builtForFlags.moneyGoldOnly) or false
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
        "formatResetCost","formatSoulAsh","formatMoney","moneyGoldOnly",
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
    print("|cFF00FF9A1.|r Copy these files into:")
    print("     |cFFFFFFFFInterface\\AddOns\\Ashoholic\\|r")
    print("       • merge_ashoholic.py")
    print("       • AshoholicSync.ps1")
    print("       • Play Ashoholic.bat")
    print(" ")
    print("|cFF00FF9A2.|r Install Python 3: |cFFFFFFFFhttps://python.org|r")
    print("     (tick \"Add Python to PATH\" during install)")
    print("     Then open a command prompt and run:")
    print("       |cFFFFFFFFpip install lupa|r")
    print(" ")
    print("|cFF00FF9A3.|r Log into each account once, play briefly, then log out.")
    print(" ")
    print("|cFF00FF9A4.|r From now on, launch WoW with |cFFFFFFFFPlay Ashoholic.bat|r")
    print("     instead of Wow.exe. Each launch merges every account's")
    print("     character data before WoW starts.")
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