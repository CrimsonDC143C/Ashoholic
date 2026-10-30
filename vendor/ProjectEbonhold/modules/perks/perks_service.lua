local addonName, addon = ...


local Perks = {}
if not addon.Perks then
    addon.Perks = Perks
else
    Perks = addon.Perks
end


Perks.currentChoice = nil
Perks.pendingRequest = false
Perks.grantedPerks = {}
Perks.lockedPerks = {}
Perks.maximumPermanentEchoes = 0
Perks.pendingBanishIndex = nil -- Track which perk index is being banished
Perks.pendingRollsCount = nil  -- Optional: if server sends "N|..." we use this; else we use level vs picksMade

local _charKey = nil
local function GetPerkPicksMadeCharKey()
    if not _charKey then
        local realm = GetNormalizedRealmName and GetNormalizedRealmName() or "Unknown"
        local name = UnitName and UnitName("player") or "Unknown"
        _charKey = realm .. "\t" .. name
    end
    return _charKey
end

local function GetPerkPicksMade()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.perkPicksMade = ProjectEbonholdDB.perkPicksMade or {}
    ProjectEbonholdDB.perkLastLevel = ProjectEbonholdDB.perkLastLevel or {}
    local key = GetPerkPicksMadeCharKey()
    local level = UnitLevel and UnitLevel("player") or 1
    -- Restart = back to level 1, keep nothing.
    if level <= 1 then
        ProjectEbonholdDB.perkPicksMade[key] = 0
        ProjectEbonholdDB.perkLastLevel[key] = 1
        return 0
    end
    -- Level dropped (respawn at 1 then leveled to 4 without us ever seeing level 1): new run, reset picks.
    local lastLevel = ProjectEbonholdDB.perkLastLevel[key] or 0
    if level < lastLevel then
        ProjectEbonholdDB.perkPicksMade[key] = 0
    end
    ProjectEbonholdDB.perkLastLevel[key] = level
    return ProjectEbonholdDB.perkPicksMade[key] or 0
end

-- Level for "rolls left": use UnitLevel("player") so it matches the level on your character sheet.
local function GetPerkLevel()
    local live = UnitLevel and UnitLevel("player")
    if live and live > 0 then return live end
    return 1
end

local function IncrementPerkPicksMade()
    local level = UnitLevel and UnitLevel("player") or 1
    if level <= 1 then return end -- don't count when level 1
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.perkPicksMade = ProjectEbonholdDB.perkPicksMade or {}
    local key = GetPerkPicksMadeCharKey()
    ProjectEbonholdDB.perkPicksMade[key] = GetPerkPicksMade() + 1
end

local function ResetPicksMade()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.perkPicksMade = ProjectEbonholdDB.perkPicksMade or {}
    local key = GetPerkPicksMadeCharKey()
    ProjectEbonholdDB.perkPicksMade[key] = 0
end

-- Auto-accept pacing: wait 180ms before each automatic pick so chained rolls
-- don't fire instantly back-to-back.
local autoAcceptTimer = CreateFrame("Frame")
autoAcceptTimer:Hide()
autoAcceptTimer:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.18 then return end
    self:Hide()
    self.t = 0
    local choice = self.choice
    self.choice = nil
    if choice and Perks.SelectPerk(choice.spellId) then
        local active = ProjectEbonhold.PerkService.GetActiveEchoLoadout
            and ProjectEbonhold.PerkService.GetActiveEchoLoadout()
        -- Clickable echo link, quality-colored (same format as the
        -- {echo:...} chat links handled by perks_browser)
        local qualityColorCodes = {
            [0] = "ffffff", [1] = "19ff19", [2] = "0066ff", [3] = "cc66ff", [4] = "ff8000",
        }
        local echoName = GetSpellInfo(choice.spellId)
        local echoLink
        if echoName then
            echoLink = "|cff" .. (qualityColorCodes[choice.quality or 0] or "ffffff")
                .. "|Hecho:" .. choice.spellId .. "|h[" .. echoName .. "]|h|r"
        else
            echoLink = tostring(choice.spellId)
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff33ff99[Echoes]|r Auto-accepted %s from your loadout%s.",
            echoLink,
            active and active.name and (" |cffffffff\"" .. active.name .. "\"|r") or ""))
    elseif Perks.currentChoice and ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.Show then
        -- Selection was refused (already pending, stale choice...): fall back
        -- to the normal selection UI so the roll is never lost.
        ProjectEbonhold.PerkUI.Show(Perks.currentChoice)
    end
end)

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_PERK_CHOICE,
    function(body)
        local wasReroll = Perks.pendingReroll and true or false
        Perks.pendingReroll = nil
        Perks.pendingRequest = false

        if not body or body == "" then
            Perks.currentChoice = nil
            Perks.pendingRollsCount = nil
            if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.Hide then
                ProjectEbonhold.PerkUI.Hide()
            end
            return
        end

        -- Optional: server can send "N|spellId,q;..." to indicate N pending rolls (including this one)
        local bodyToParse = body
        local n, rest = body:match("^(%d+)|(.+)$")
        if n and rest then
            local num = tonumber(n)
            if num and num > 0 then
                Perks.pendingRollsCount = num
                bodyToParse = rest
            end
        else
            Perks.pendingRollsCount = nil -- no server count: use level-based so (1) doesn't stick
        end

        local choices = {}
        local count = 0
        for perkPair in string.gmatch(bodyToParse, "([^;]+)") do
            local spellIdStr, qualityStr, isFrozenStr = perkPair:match("^([^,]+),([^,]+),?([^,]*)$")
            if spellIdStr and qualityStr then
                local spellId = tonumber(spellIdStr)
                local quality = tonumber(qualityStr)
                local isFrozenVal = tonumber(isFrozenStr) or 0
                local isFrozen = (isFrozenVal == 1)
                local isCarried = (isFrozenVal == 2)
                local isGuaranteed = (isFrozenVal == 3) -- injected from the active server build slot
                if spellId and spellId ~= 0 and quality then
                    table.insert(choices,
                        { spellId = spellId, quality = quality, isFrozen = isFrozen, isCarried = isCarried, isGuaranteed = isGuaranteed })
                    count = count + 1
                end
            end
        end


        if count == 0 then
            Perks.currentChoice = nil
            return
        end

        if count == 4 then
            table.remove(choices)
        end

        Perks.currentChoice = choices

        -- Auto-accept: when enabled and a choice belongs to the active echo
        -- loadout, pick it immediately (highest quality first) instead of
        -- showing the selection UI.
        local optSvc = _G["ProjectEbonholdOptionsService"]
        local autoAcceptSetting = optSvc and optSvc.GetSetting and optSvc:GetSetting("autoAcceptLoadoutEchoes")
        if optSvc and optSvc.GetSetting and autoAcceptSetting
            and ProjectEbonhold.PerkService.IsSpellInActiveEchoLoadout then
            local best
            for _, choice in ipairs(choices) do
                if ProjectEbonhold.PerkService.IsSpellInActiveEchoLoadout(choice.spellId) then
                    if not best or (choice.quality or 0) > (best.quality or 0) then
                        best = choice
                    end
                end
            end
            if best and not Perks.pendingSelectSpellId then
                -- Defer the actual pick by 100ms (see autoAcceptTimer above)
                autoAcceptTimer.choice = best
                autoAcceptTimer.t = 0
                autoAcceptTimer:Show()
                return
            end
        end

        if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.Show then
            ProjectEbonhold.PerkUI.Show(choices, wasReroll)
        else
            for i, choice in ipairs(choices) do
                local spellName = GetSpellInfo(choice.spellId)
                local qualityNames = {
                    [0] = "Common",
                    [1] = "Uncommon",
                    [2] = "Rare",
                    [3] = "Epic",
                    [4] = "Legendary"
                }
                local qualityName = qualityNames[choice.quality] or "Unknown"
            end
        end
    end)


ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_PERK_SELECTION_RESULT,
    function(body)
        Perks.pendingSelectSpellId = nil -- selection resolved, unblock picks
        -- Selection succeeded
        if body >= "1" then
            -- The pick settles a pending Orb of Lost Memories offer, which re-enables
            -- reroll/banish/freeze for every later draw. It MUST live inside this handler:
            -- onEventReceived stores one function per opcode (ServerHandlers[id] = fn), so a
            -- second registration for this same opcode would just be overwritten.
            -- Success only - a refused selection leaves the orb offer standing.
            if ProjectEbonhold.OrbService and ProjectEbonhold.OrbService.ClearOffer then
                ProjectEbonhold.OrbService.ClearOffer()
            end

            Perks.currentChoice = nil
            IncrementPerkPicksMade()
            if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.Hide then
                ProjectEbonhold.PerkUI.Hide()
            end

            if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.NotifyNewEcho then
                ProjectEbonhold.EchoJournal.NotifyNewEcho()
            end

            Perks.RequestChoice()
            Perks.RequestGrantedPerks()
        elseif body == "0" then
            -- Selection failed server-side, re-enable interaction so player can try again
            if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.ResetSelection then
                ProjectEbonhold.PerkUI.ResetSelection()
            end
        end
    end)




ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_PERK_GRANTED,
    function(body)
        Perks.grantedPerks = {}
        Perks.lockedPerks = {}

        if not body or body == "" then
            if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks then
                ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks()
            end
            return
        end


        local parts = {}
        for part in string.gmatch(body, "([^;]+)") do
            table.insert(parts, part)
        end

        if #parts == 0 then
            if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks then
                ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks()
            end
            return
        end


        local maxSlotsStr = parts[1]
        local serverMaxSlots = tonumber(maxSlotsStr)

        if serverMaxSlots and serverMaxSlots > 0 then
            Perks.maximumPermanentEchoes = serverMaxSlots
        end



        local perkCount = 0
        for i = 2, #parts do
            local perkData = parts[i]


            local spellIdStr, stackStr, maxStackStr, qualityStr, lockedStr = perkData:match(
                "^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$")

            if not spellIdStr then
                spellIdStr, stackStr, maxStackStr = perkData:match(
                    "^([^,]+),([^,]+),([^,]+)$")
                qualityStr = nil
                lockedStr = nil
            end

            if spellIdStr and stackStr and maxStackStr then
                local spellId = tonumber(spellIdStr)
                local stack = tonumber(stackStr)
                local maxStack = tonumber(maxStackStr)
                local quality = qualityStr and tonumber(qualityStr) or 0
                local isLocked = lockedStr and tonumber(lockedStr) == 1 or false

                if spellId and stack and maxStack then
                    if isLocked then
                        table.insert(Perks.lockedPerks, {
                            spellId = spellId,
                            stack = stack,
                            maxStack = maxStack,
                            quality = quality
                        })
                        perkCount = perkCount + 1
                    else
                        local spellName = GetSpellInfo(spellId)
                        if spellName then
                            if not Perks.grantedPerks[spellName] then
                                Perks.grantedPerks[spellName] = {}
                            end
                            for i = 1, stack do
                                table.insert(Perks.grantedPerks[spellName], {
                                    spellId = spellId,
                                    stack = 1,
                                    maxStack = maxStack,
                                    quality = quality
                                })
                                perkCount = perkCount + 1
                            end
                        end
                    end
                end
            end
        end

        if perkCount == 0 then end

        if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and
            ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks then
            ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks()
        end
        if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.OnDataChanged then
            ProjectEbonhold.EchoJournal.OnDataChanged()
        end
    end)


-- Handle banish replacement perk response
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_BANISH_REPLACEMENT_PERK,
    function(body)

        -- Check if we have a pending banish
        if not Perks.pendingBanishIndex then
            return
        end

        local perkIndex = Perks.pendingBanishIndex
        Perks.pendingBanishIndex = nil -- Clear pending banish

        if not body or body == "" then
            -- Banish failed - server sent empty response
            if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.ResetSelection then
                ProjectEbonhold.PerkUI.ResetSelection()
            end
            return
        end

        -- Parse the replacement perk data: "new_spell_id,new_quality"
        local newSpellId, newQuality
        local commaPos = string.find(body, ",")
        if commaPos then
            newSpellId = tonumber(string.sub(body, 1, commaPos - 1))
            newQuality = tonumber(string.sub(body, commaPos + 1))
        else
            -- Fallback for old format (just spell ID)
            newSpellId = tonumber(body)
            newQuality = 0
        end


        if not newSpellId then
            if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.ResetSelection then
                ProjectEbonhold.PerkUI.ResetSelection()
            end
            return
        end

        if newSpellId == 0 then
            -- Banish failed (server returned 0)
            if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.ResetSelection then
                ProjectEbonhold.PerkUI.ResetSelection()
            end
            return
        end

        -- Banish succeeded - update the perk choice at the specified index
        if Perks.currentChoice and Perks.currentChoice[perkIndex + 1] then
            local oldSpellId = Perks.currentChoice[perkIndex + 1].spellId
            local oldQuality = Perks.currentChoice[perkIndex + 1].quality

            Perks.currentChoice[perkIndex + 1].spellId = newSpellId
            Perks.currentChoice[perkIndex + 1].quality = newQuality or 0


            -- Use animated single perk update instead of full refresh
            if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.UpdateSinglePerk then
                ProjectEbonhold.PerkUI.UpdateSinglePerk(perkIndex, Perks.currentChoice[perkIndex + 1])
            elseif ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.Show then
                -- Fallback to full refresh if UpdateSinglePerk not available
                ProjectEbonhold.PerkUI.Show(Perks.currentChoice)
            end

            -- Re-enable interaction after animation
            if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.ResetSelection then
                ProjectEbonhold.PerkUI.ResetSelection()
            end
        else
            if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.ResetSelection then
                ProjectEbonhold.PerkUI.ResetSelection()
            end
        end
    end)


ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_FREEZE_PERK_RESULT,
    function(body)
        local frozenIndex = Perks.pendingFreezeIndex
        Perks.pendingFreezeIndex = nil -- freeze resolved, unblock freezes

        if body == "1" then
            -- Server confirmed freeze. Mark the data so future UI rebuilds know.
            -- usedFreezes was already incremented optimistically by the UI.
            if frozenIndex and Perks.currentChoice and Perks.currentChoice[frozenIndex + 1] then
                Perks.currentChoice[frozenIndex + 1].justFrozen = true
            end
            -- No UI rebuild needed; the card already shows frozen visual.
        else
            -- Freeze failed - undo the optimistic usedFreezes increment
            local runData = ProjectEbonhold.PlayerRunService and ProjectEbonhold.PlayerRunService.GetCurrentData()
            if runData and (runData.usedFreezes or 0) > 0 then
                runData.usedFreezes = runData.usedFreezes - 1
            end
            -- Refresh UI to revert the frozen visual
            if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.Show then
                ProjectEbonhold.PerkUI.Show(Perks.currentChoice)
            end
        end
    end)


-- ── Persistent echo discovery (across runs) ─────────────────────────────────
-- Server replies to REQUEST_ECHO_DISCOVERY with "spellId[:timesObtained],..."
-- listing every echo this character has ever been granted. Cached in
-- SavedVariables so the Collection tab keeps working before the reply (or on
-- servers that do not implement the opcode yet).
Perks.discoveredEchoes = nil -- [spellId] = timesObtained, nil until first reply
Perks.disabledTomeEchoes = {} -- [echoSpellId] = true when its tome is toggled OFF (session-live, server is authoritative)

local function GetDiscoveryCache()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.echoDiscovery = ProjectEbonholdDB.echoDiscovery or {}
    local key = GetPerkPicksMadeCharKey()
    ProjectEbonholdDB.echoDiscovery[key] = ProjectEbonholdDB.echoDiscovery[key] or {}
    return ProjectEbonholdDB.echoDiscovery[key]
end

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_ECHO_DISCOVERY,
    function(body)
        -- Entries: "spellId[:timesObtained[:enabled]]" - enabled defaults to 1;
        -- ":1:0" marks a tome the player toggled OFF (echo out of the draw pool)
        local discovered = {}
        local disabled = {}
        if body and body ~= "" then
            for entry in string.gmatch(body, "([^,]+)") do
                local idStr, countStr, enabledStr = entry:match("^(%d+):?(%d*):?(%d*)$")
                local id = tonumber(idStr)
                if id then
                    discovered[id] = tonumber(countStr) or 1
                    if enabledStr == "0" then
                        disabled[id] = true
                    end
                end
            end
        end
        Perks.disabledTomeEchoes = disabled

        -- A tome echo newly present in the list = the player just unlocked a
        -- tome: point them at the journal. Baseline = previous list from this
        -- session, else the SavedVariables cache. An EMPTY baseline means
        -- first-ever sync (nothing meaningful to diff), so stay silent.
        local before = Perks.discoveredEchoes or GetDiscoveryCache()
        if next(before) ~= nil then
            for id in pairs(discovered) do
                if not before[id] then
                    local data = ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[id]
                    if data and data.requiredSpell and data.requiredSpell ~= 0
                        and ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.NotifyTomeLearned then
                        ProjectEbonhold.EchoJournal.NotifyTomeLearned(id)
                    end
                end
            end
        end

        Perks.discoveredEchoes = discovered
        ProjectEbonholdDB = ProjectEbonholdDB or {}
        ProjectEbonholdDB.echoDiscovery = ProjectEbonholdDB.echoDiscovery or {}
        ProjectEbonholdDB.echoDiscovery[GetPerkPicksMadeCharKey()] = discovered

        if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.OnDataChanged then
            ProjectEbonhold.EchoJournal.OnDataChanged()
        end
    end)

-- ── Echo loadouts (local library + community sharing) ───────────────────────
-- A loadout is { name = string, class = "WARRIOR".., author = string (community),
--                echoes = { { spellId, quality, stacks }, ... } }.
-- Local loadouts persist account-wide in ProjectEbonholdDB.echoLoadouts.
-- Export string format: "EBH1:<id.q.stacks,...>:<class>:<name>".

local function GetLoadoutStore()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.echoLoadouts = ProjectEbonholdDB.echoLoadouts or {}
    return ProjectEbonholdDB.echoLoadouts
end

local function SerializeEchoes(echoes)
    local parts = {}
    for _, e in ipairs(echoes or {}) do
        table.insert(parts, e.spellId .. "." .. (e.quality or 0) .. "." .. (e.stacks or 1))
    end
    return table.concat(parts, ",")
end

local function DeserializeEchoes(str)
    local echoes = {}
    for entry in string.gmatch(str or "", "([^,]+)") do
        local id, q, st = entry:match("^(%d+)%.(%d+)%.?(%d*)$")
        id = tonumber(id)
        if id then
            table.insert(echoes, { spellId = id, quality = tonumber(q) or 0, stacks = tonumber(st) or 1 })
        end
    end
    return echoes
end

-- Loadout names travel in the wire/export formats: strip their separators
local function SanitizeLoadoutName(name)
    name = tostring(name or ""):gsub("[|;:,]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name:sub(1, 32)
end

-- Class token ("WARRIOR", "MAGE", ...), defaulting to the player's own class
local function SanitizeLoadoutClass(class)
    class = tostring(class or ""):upper():gsub("[^A-Z]", "")
    if class == "" then
        local _, token = UnitClass("player")
        class = token or "UNKNOWN"
    end
    return class
end

Perks.sharedLoadouts = nil -- nil until the first SEND_ECHO_LOADOUTS_SHARED reply

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_ECHO_LOADOUTS_SHARED,
    function(body)
        local list = {}
        for entry in string.gmatch(body or "", "([^;]+)") do
            local author, name, class, echoStr = entry:match("^([^|]*)|([^|]*)|([^|]*)|(.*)$")
            if not author then -- legacy 3-field entry without class
                author, name, echoStr = entry:match("^([^|]*)|([^|]*)|(.*)$")
                class = nil
            end
            if name and name ~= "" then
                local echoes = DeserializeEchoes(echoStr)
                if #echoes > 0 then
                    table.insert(list, {
                        name = name, author = author,
                        class = SanitizeLoadoutClass(class),
                        echoes = echoes,
                    })
                end
            end
        end
        Perks.sharedLoadouts = list
        if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.OnDataChanged then
            ProjectEbonhold.EchoJournal.OnDataChanged()
        end
    end)

function Perks.RequestChoice()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PLAYER_PERK_CHOICE,
        "")
end

function Perks.SelectPerk(spellId)
    if Perks.pendingSelectSpellId then return false end -- pick already in flight
    if not spellId or spellId == 0 then
        return false
    end

    -- Check if we have current choices
    if not Perks.currentChoice then
        return false
    end

    local found = false
    for _, choice in ipairs(Perks.currentChoice) do
        if choice.spellId == spellId then
            found = true
            break
        end
    end

    if not found then
        return false
    end

    Perks.pendingSelectSpellId = spellId
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PLAYER_PERK_SELECTION, tostring(spellId))
    return true
end

function Perks.RequestGrantedPerks()
    ProjectEbonhold.sendToServer(
        ProjectEbonhold.CS.REQUEST_PLAYER_GRANTED_PERKS, "")
end

function Perks.RequestReroll()
    if Perks.pendingReroll then return false end -- reroll already in flight
    Perks.pendingReroll = true
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_REROLL, "")
    return true
end

function Perks.BanishPerk(perkIndex)
    if Perks.pendingBanishIndex then return false end -- banish already in flight
    if not perkIndex or perkIndex < 0 or perkIndex > 2 then
        return false
    end

    -- The build-slot guaranteed card cannot be banished (the server refuses too)
    if Perks.currentChoice and Perks.currentChoice[perkIndex + 1]
        and Perks.currentChoice[perkIndex + 1].isGuaranteed then
        return false
    end

    -- Check if banish system is enabled
    if not ProjectEbonhold.Constants or not ProjectEbonhold.Constants.ENABLE_BANISH_SYSTEM then
        return false
    end

    -- Check if we have remaining banishes
    local runData = ProjectEbonhold.PlayerRunService and ProjectEbonhold.PlayerRunService.GetCurrentData() or {}
    local remainingBanishes = runData.remainingBanishes or 0
    if remainingBanishes <= 0 then
        return false
    end

    -- Store which perk we're trying to banish
    Perks.pendingBanishIndex = perkIndex

    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_BANISH_PERK, tostring(perkIndex))
    return true
end

function Perks.FreezePerk(perkIndex)
    if Perks.pendingFreezeIndex then return false end -- freeze already in flight
    if not perkIndex or perkIndex < 0 or perkIndex > 2 then
        return false
    end

    -- The build-slot guaranteed card re-appears every draw; freezing it is
    -- refused server-side, so don't waste a charge on the request
    if Perks.currentChoice and Perks.currentChoice[perkIndex + 1]
        and Perks.currentChoice[perkIndex + 1].isGuaranteed then
        return false
    end

    -- Check if we have remaining freezes
    local runData = ProjectEbonhold.PlayerRunService and ProjectEbonhold.PlayerRunService.GetCurrentData() or {}
    local usedFreezes = runData.usedFreezes or 0
    local totalFreezes = runData.totalFreezes or 0
    local availableFreezes = math.max(0, totalFreezes - usedFreezes)

    if availableFreezes <= 0 then
        return false
    end

    -- Store which perk we're trying to freeze
    Perks.pendingFreezeIndex = perkIndex

    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_FREEZE_PERK, tostring(perkIndex))
    return true
end

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.Perks = Perks
ProjectEbonhold.PerkService = ProjectEbonhold.PerkService or {}
ProjectEbonhold.PerkService.RequestChoice = Perks.RequestChoice
ProjectEbonhold.PerkService.SelectPerk = Perks.SelectPerk
ProjectEbonhold.PerkService.RequestGrantedPerks = Perks.RequestGrantedPerks
ProjectEbonhold.PerkService.RequestReroll = Perks.RequestReroll
ProjectEbonhold.PerkService.BanishPerk = Perks.BanishPerk
ProjectEbonhold.PerkService.FreezePerk = Perks.FreezePerk
ProjectEbonhold.PerkService.GetCurrentChoice = function()
    return Perks.currentChoice
end
-- Rolls left = (level - 1) - picksMade. Level = value from PLAYER_LEVEL_UP (stored) or UnitLevel.
ProjectEbonhold.PerkService.GetPendingRollsCount = function()
    if Perks.pendingRollsCount and Perks.pendingRollsCount > 0 then
        return Perks.pendingRollsCount
    end
    local level = GetPerkLevel()
    local rollsOffered = math.min(80, math.max(0, level - 1))
    local picksMade = GetPerkPicksMade()
    -- Cap picks at (level - 1) so bad saved data never gives negative rolls
    picksMade = math.min(picksMade, rollsOffered)
    local count = math.max(0, rollsOffered - picksMade)
    -- If we have an active perk choice being shown, there's at least 1 pending
    if Perks.currentChoice and count < 1 then
        count = 1
    end
    return count
end
-- For tooltip: level, picks made (capped), rolls left
ProjectEbonhold.PerkService.GetRollsDebugInfo = function()
    local level = GetPerkLevel()
    local rollsOffered = math.min(80, math.max(0, level - 1))
    local picksMade = math.min(GetPerkPicksMade(), rollsOffered)
    local rollsLeft = math.max(0, rollsOffered - picksMade)
    return level, picksMade, rollsLeft
end
ProjectEbonhold.PerkService.ResetPicksMade = ResetPicksMade
ProjectEbonhold.PerkService.GetGrantedPerks = function()
    return Perks.grantedPerks
end
ProjectEbonhold.PerkService.GetLockedPerks = function()
    return Perks.lockedPerks
end
ProjectEbonhold.PerkService.GetMaximumPermanentEchoes = function()
    return Perks.maximumPermanentEchoes or 0
end
ProjectEbonhold.PerkService.RequestEchoDiscovery = function()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ECHO_DISCOVERY, "")
end
-- Sync the discovery list right after login so the new-tome diff above has a
-- live baseline even before the journal is first opened.
local discoveryInit = CreateFrame("Frame")
discoveryInit:RegisterEvent("PLAYER_ENTERING_WORLD")
discoveryInit:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    ProjectEbonhold.PerkService.RequestEchoDiscovery()
end)
-- Live server data when available, otherwise the SavedVariables cache
ProjectEbonhold.PerkService.GetDiscoveredEchoes = function()
    return Perks.discoveredEchoes or GetDiscoveryCache()
end
-- True when the echo's tome is toggled OFF (learned but out of the draw pool)
ProjectEbonhold.PerkService.IsTomeEchoDisabled = function(spellId)
    return Perks.disabledTomeEchoes and Perks.disabledTomeEchoes[spellId] == true
end
-- Flips a learned tome on/off. Level 1 only (the draw pool is fixed once the
-- run starts); the server answers with the refreshed discovery list.
ProjectEbonhold.PerkService.ToggleTomeEcho = function(spellId)
    local data = ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[spellId]
    if not data or not data.requiredSpell or data.requiredSpell == 0 then return false end
    if (UnitLevel("player") or 1) ~= 1 then
        UIErrorsFrame:AddMessage("Tomes can be enabled or disabled at level 1 only.", 1, 0.2, 0.2)
        return false
    end
    local enable = ProjectEbonhold.PerkService.IsTomeEchoDisabled(spellId) and "1" or "0"
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TOME_TOGGLE,
        tostring(data.requiredSpell) .. "|" .. enable)
    return true
end
-- Optimistic removal after an unlearn: drop the echo from the local list (live
-- + SavedVariables cache) so the UI re-dims it without a server round-trip.
ProjectEbonhold.PerkService.RemoveDiscoveredEcho = function(spellId)
    if Perks.discoveredEchoes then Perks.discoveredEchoes[spellId] = nil end
    GetDiscoveryCache()[spellId] = nil
    if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.OnDataChanged then
        ProjectEbonhold.EchoJournal.OnDataChanged()
    end
end
-- Optimistic addition when a tome is used: mark the echo discovered locally
-- (the next SEND_ECHO_DISCOVERY sync remains the source of truth).
-- Returns true when the echo was not already discovered.
ProjectEbonhold.PerkService.AddDiscoveredEcho = function(spellId)
    local cache = GetDiscoveryCache()
    local isNew = not (cache[spellId]
        or (Perks.discoveredEchoes and Perks.discoveredEchoes[spellId]))
    if Perks.discoveredEchoes then
        Perks.discoveredEchoes[spellId] = Perks.discoveredEchoes[spellId] or 1
    end
    cache[spellId] = cache[spellId] or 1
    if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.OnDataChanged then
        ProjectEbonhold.EchoJournal.OnDataChanged()
    end
    return isNew
end
ProjectEbonhold.PerkService.LockPerk = function(spellId, count)
    if not spellId or spellId == 0 then return false end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_LOCK_PERK, tostring(spellId))
    return true
end
ProjectEbonhold.PerkService.UnlockPerk = function(spellId)
    if not spellId or spellId == 0 then return false end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_UNLOCK_PERK, tostring(spellId))
    return true
end

-- ── Echo loadouts API ────────────────────────────────────────────────────────
ProjectEbonhold.PerkService.GetEchoLoadouts = function()
    return GetLoadoutStore()
end
ProjectEbonhold.PerkService.SaveEchoLoadout = function(name, echoes, class)
    name = SanitizeLoadoutName(name)
    if name == "" or not echoes or #echoes == 0 then return false end
    table.insert(GetLoadoutStore(), {
        name = name,
        class = SanitizeLoadoutClass(class),
        echoes = echoes,
    })
    return true
end
ProjectEbonhold.PerkService.DeleteEchoLoadout = function(index)
    table.remove(GetLoadoutStore(), index)
end
-- Replace an existing library entry in place (loadout editor)
ProjectEbonhold.PerkService.UpdateEchoLoadout = function(index, name, echoes, class)
    local store = GetLoadoutStore()
    local existing = store[index]
    if not existing then return false end
    name = SanitizeLoadoutName(name)
    if name == "" or not echoes or #echoes == 0 then return false end
    store[index] = {
        name = name,
        class = SanitizeLoadoutClass(class or existing.class),
        echoes = echoes,
    }
    return true
end
-- Collapse the current run (granted + locked) into loadout entries, sorted by
-- quality desc then name, one entry per spellId with total stacks.
ProjectEbonhold.PerkService.SnapshotCurrentEchoes = function()
    local bySpell, list = {}, {}
    local function add(spellId, quality, stack)
        if not spellId or spellId == 0 then return end
        local e = bySpell[spellId]
        if not e then
            e = { spellId = spellId, quality = quality or 0, stacks = 0 }
            bySpell[spellId] = e
            table.insert(list, e)
        end
        e.stacks = e.stacks + (stack or 1)
        if (quality or 0) > e.quality then e.quality = quality end
    end
    for _, instances in pairs(Perks.grantedPerks) do
        for _, inst in ipairs(instances) do add(inst.spellId, inst.quality, inst.stack or 1) end
    end
    for _, lp in ipairs(Perks.lockedPerks) do add(lp.spellId, lp.quality, lp.stack or 1) end
    table.sort(list, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return (GetSpellInfo(a.spellId) or "") < (GetSpellInfo(b.spellId) or "")
    end)
    return list
end
-- nil = no server reply yet (UI shows a loading state)
ProjectEbonhold.PerkService.GetSharedEchoLoadouts = function()
    return Perks.sharedLoadouts
end
-- ── Active echo loadout (the build the player wants to play with) ───────────
-- Stored per character as a COPY of the chosen loadout, so deleting or editing
-- the library entry never breaks it. LEGACY: builds live server side now, and
-- the armed slot drives the highlight and auto-pick (see the 540/542 handlers
-- below). This store is only read on realms with the feature turned off.

local function GetActiveLoadoutStore()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.echoActiveLoadout = ProjectEbonholdDB.echoActiveLoadout or {}
    return ProjectEbonholdDB.echoActiveLoadout
end

-- The build the player is playing with. The server's armed slot is the only
-- authority: the account-wide copy below predates server-side builds and has no
-- way to learn that its build was edited, swapped or deleted, so it is only
-- consulted on realms where the feature is off.
ProjectEbonhold.PerkService.GetActiveEchoLoadout = function()
    if Perks.serverBuildSlotsEnabled then
        local slot = Perks.serverActiveSlot or 0
        local build = slot > 0 and Perks.serverBuildSlots and Perks.serverBuildSlots[slot] or nil
        if build then
            return { name = build.name, echoes = build.echoes }
        end
        return nil
    end
    return GetActiveLoadoutStore()[GetPerkPicksMadeCharKey()]
end
ProjectEbonhold.PerkService.SetActiveEchoLoadout = function(loadout)
    if not loadout or not loadout.echoes or #loadout.echoes == 0 then return false end
    local copy = { name = loadout.name, class = loadout.class, echoes = {} }
    for _, e in ipairs(loadout.echoes) do
        table.insert(copy.echoes, { spellId = e.spellId, quality = e.quality, stacks = e.stacks })
    end
    GetActiveLoadoutStore()[GetPerkPicksMadeCharKey()] = copy
    return true
end
ProjectEbonhold.PerkService.ClearActiveEchoLoadout = function()
    GetActiveLoadoutStore()[GetPerkPicksMadeCharKey()] = nil
end
-- class: optional class token filter ("WARRIOR", ...); empty body = all classes
ProjectEbonhold.PerkService.RequestSharedEchoLoadouts = function(class)
    class = tostring(class or ""):upper():gsub("[^A-Z]", "")
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ECHO_LOADOUTS_SHARED, class)
end
ProjectEbonhold.PerkService.PublishEchoLoadout = function(loadout)
    if not loadout or not loadout.echoes or #loadout.echoes == 0 then return false end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ECHO_LOADOUT_PUBLISH,
        SanitizeLoadoutName(loadout.name) .. "|" .. SanitizeLoadoutClass(loadout.class)
        .. "|" .. SerializeEchoes(loadout.echoes))
    return true
end
-- Retract one of the player's own community loadouts. The server matches the
-- entry by sender + name + class; the local shared list is trimmed
-- optimistically so the row disappears without waiting for a new reply.
ProjectEbonhold.PerkService.UnpublishEchoLoadout = function(loadout)
    if not loadout or not loadout.name or loadout.name == "" then return false end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ECHO_LOADOUT_UNPUBLISH,
        SanitizeLoadoutName(loadout.name) .. "|" .. SanitizeLoadoutClass(loadout.class))
    if Perks.sharedLoadouts then
        local me = UnitName("player")
        for i = #Perks.sharedLoadouts, 1, -1 do
            local lo = Perks.sharedLoadouts[i]
            if lo.author == me and lo.name == loadout.name
                and lo.class == SanitizeLoadoutClass(loadout.class) then
                table.remove(Perks.sharedLoadouts, i)
            end
        end
    end
    return true
end
ProjectEbonhold.PerkService.ExportEchoLoadout = function(loadout)
    if not loadout then return "" end
    return "EBH1:" .. SerializeEchoes(loadout.echoes)
        .. ":" .. SanitizeLoadoutClass(loadout.class)
        .. ":" .. SanitizeLoadoutName(loadout.name)
end
ProjectEbonhold.PerkService.ImportEchoLoadout = function(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local echoStr, class, name = text:match("^EBH1:([^:]*):([^:]*):(.+)$")
    if not echoStr then -- legacy format without the class segment
        echoStr, name = text:match("^EBH1:([^:]*):(.+)$")
        class = nil
    end
    if not echoStr then return nil end
    local echoes = DeserializeEchoes(echoStr)
    if #echoes == 0 then return nil end
    return {
        name = SanitizeLoadoutName(name),
        class = SanitizeLoadoutClass(class),
        echoes = echoes,
    }
end

-- ── Server build slots (Perk Loadouts) ───────────────────────────────────────
-- Server-verified snapshots of the player's OWN build (5 slots per character,
-- stacks + locked flags). Unlike the local library above (a free-form wish
-- list, highlight-only), a build slot is authoritative: activated at level 1
-- it makes the server GUARANTEE one of its missing echoes in every draw
-- (choice flag 3); activated at level 80 it performs a full build swap.
-- Saving never uploads content - the server snapshots what the player has.

Perks.serverBuildSlots = nil    -- nil until the first SEND_PERK_LOADOUTS reply; [slot] = { slot, name, echoes }
Perks.serverUnlockedSlots = 5   -- highest usable slot (account-wide; from the 540 header)
Perks.serverSlotCosts = {}      -- [slot] = unlock price in gold (0 = free)
Perks.serverActiveSlot = 0      -- 0 = none
Perks.serverMaxSlots = 5
Perks.serverBuildSlotsEnabled = true
Perks.pendingBuildSlotRequest = nil
Perks.pendingBuildSlotRequestAt = 0

-- One build-slot request in flight at a time - but a server-throttled request
-- never gets a reply, so the guard must expire or it deadlocks every later
-- action (switch/save/... silently doing nothing).
local function BuildSlotRequestBusy()
    if not Perks.pendingBuildSlotRequest then return false end
    if GetTime() - (Perks.pendingBuildSlotRequestAt or 0) > 3 then
        Perks.pendingBuildSlotRequest = nil
        return false
    end
    UIErrorsFrame:AddMessage("Please wait a moment before the next build action.", 1, 0.82, 0)
    return true
end

local function MarkBuildSlotRequest(kind)
    Perks.pendingBuildSlotRequest = kind
    Perks.pendingBuildSlotRequestAt = GetTime()
end

-- ids/names of the ACTIVE server build's echoes, for draw highlighting and
-- auto-accept (both snapshot and designed builds). Lazy cache, invalidated on
-- every 540/542 update.
local serverActiveSet = nil

local function RebuildServerActiveSet()
    serverActiveSet = { ids = {}, names = {} }
    local slot = Perks.serverActiveSlot or 0
    local build = slot > 0 and Perks.serverBuildSlots and Perks.serverBuildSlots[slot]
    if build then
        for _, e in ipairs(build.echoes or {}) do
            serverActiveSet.ids[e.spellId] = true
            local nm = GetSpellInfo(e.spellId)
            if nm then serverActiveSet.names[nm] = true end
        end
    end
end

local function NotifyBuildSlotsChanged()
    serverActiveSet = nil
    if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.OnDataChanged then
        ProjectEbonhold.EchoJournal.OnDataChanged()
    end
    if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.RefreshLoadoutHighlights then
        ProjectEbonhold.PerkUI.RefreshLoadoutHighlights()
    end
end

-- Body: activeSlot|maxSlots;slot|name|id.stack.locked,id.stack.locked,...;...
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PERK_LOADOUTS,
    function(body)
        Perks.serverBuildSlots = {}

        if not body or body == "" then
            Perks.serverBuildSlotsEnabled = false
            Perks.serverActiveSlot = 0
            NotifyBuildSlotsChanged()
            return
        end
        Perks.serverBuildSlotsEnabled = true

        local records = {}
        for record in string.gmatch(body, "([^;]+)") do
            table.insert(records, record)
        end

        -- Header: activeSlot|maxSlots|unlockedSlots|costG1.costG2...costGmax
        -- (unlocked/costs are absent on older servers - fall back gracefully)
        local header = records[1] or ""
        local activeStr, maxStr, unlockedStr, costsStr = header:match("^(%d+)|(%d+)|(%d+)|(.*)$")
        if not activeStr then
            activeStr, maxStr = header:match("^(%d+)|(%d+)$")
        end
        Perks.serverActiveSlot = tonumber(activeStr) or 0
        Perks.serverMaxSlots = tonumber(maxStr) or 5
        Perks.serverUnlockedSlots = tonumber(unlockedStr) or Perks.serverMaxSlots
        Perks.serverSlotCosts = {}
        if costsStr and costsStr ~= "" then
            local slot = 1
            for cost in string.gmatch(costsStr, "([^%.]+)") do
                Perks.serverSlotCosts[slot] = tonumber(cost) or 0
                slot = slot + 1
            end
        end

        local db = ProjectEbonhold.PerkDatabase or {}
        for i = 2, #records do
            -- Row: slot|name|verified|toRecover|entries. Older servers drop the
            -- toRecover field (4 fields), older still the verified one (3).
            local slotStr, name, verifiedStr, recoverStr, entriesStr =
                records[i]:match("^(%d+)|([^|]*)|([01])|([01])|(.*)$")
            if not slotStr then
                slotStr, name, verifiedStr, entriesStr = records[i]:match("^(%d+)|([^|]*)|([01])|(.*)$")
                recoverStr = "0"
            end
            if not slotStr then
                slotStr, name, entriesStr = records[i]:match("^(%d+)|([^|]*)|(.*)$")
                verifiedStr, recoverStr = "1", "0"
            end
            local slot = tonumber(slotStr)
            if slot then
                -- Entries reuse the library's echo shape ({spellId, quality,
                -- stacks}) so the journal rows can render them unchanged.
                local echoes = {}
                if entriesStr and entriesStr ~= "" then
                    for entry in string.gmatch(entriesStr, "([^,]+)") do
                        local idStr, stackStr, lockedStr = entry:match("^(%d+)%.(%d+)%.(%d+)$")
                        local spellId = tonumber(idStr)
                        if spellId then
                            local perkDb = db[spellId]
                            table.insert(echoes, {
                                spellId = spellId,
                                quality = perkDb and perkDb.quality or 0,
                                stacks = tonumber(stackStr) or 1,
                                locked = tonumber(lockedStr) == 1,
                            })
                        end
                    end
                end
                -- toRecover: this wishlist stands for a build the player really
                -- owned and can be turned back into one (RecoverServerBuildSlot)
                Perks.serverBuildSlots[slot] = { slot = slot, name = name or "",
                    verified = verifiedStr == "1", toRecover = recoverStr == "1", echoes = echoes }
            end
        end

        NotifyBuildSlotsChanged()
    end)

-- Body: "OK,<op>,<slot>" or "FAIL,<op>,<reason>"
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PERK_LOADOUT_RESULT,
    function(body)
        Perks.pendingBuildSlotRequest = nil

        local status, op, detail = body:match("^([^,]+),([^,]+),(.*)$")

        -- Remembered so the journal can flash the row once it renders. Both ops
        -- lead with the slot id: "upload" is a designed build (the server picks
        -- the id), "save" a snapshot into a slot you chose.
        if status == "OK" and (op == "save" or op == "upload") then
            local saved = tostring(detail):match("^(%d+)")
            if saved then Perks.lastSavedBuildSlot = tonumber(saved) end
        elseif status == "OK" and op == "recover" then
            -- "<wishlistSlot>,<targetSlot>": the build slot is the one to flash
            local target = tostring(detail):match("^%d+,(%d+)$")
            if target then Perks.lastSavedBuildSlot = tonumber(target) end
        end

        if status == "FAIL" then
            local reasons = {
                disabled = "Build slots are disabled on this realm.",
                slot = "Invalid build slot.",
                empty = (op == "save") and "You have no echoes to save." or "This build slot is empty.",
                level = (op == "save") and "You can only save a build snapshot at level 80."
                    or "Saved builds can only be activated at level 80. While you level, every echo you are offered is drawn at random.",
                combat = "You cannot switch builds in combat.",
                dead = "You cannot switch builds while dead.",
                rolls = "Spend your remaining echo rolls before switching builds.",
                locked = "This build slot is locked - unlock it with gold first.",
                max = "All build slots are already unlocked.",
                money = "You don't have enough gold to unlock this slot.",
                designed = "Designed builds cannot be applied at level 80. Only snapshots of a build you actually played can.",
                invalid = "This build contains no echoes usable by your class.",
                full = (op == "recover") and "You have no free build slot. Free one up first."
                    or "You have too many designed builds. Delete one first.",
                norecover = "This wishlist cannot be recovered.",
                occupied = "That build slot already holds a build.",
                overbudget = (op == "recover")
                    and "This wishlist holds more echoes than a run can grant, so it cannot be recovered."
                    or "This build holds more echoes than a run can grant and cannot be applied.",
                recoverable = "This wishlist is waiting to be recovered, so its content is locked. Recover it or delete it.",
            }
            UIErrorsFrame:AddMessage(reasons[detail]
                or ("Build " .. tostring(op) .. " failed (" .. tostring(detail) .. ")."), 1, 0.2, 0.2)
        elseif status == "OK" and op == "switch" then
            UIErrorsFrame:AddMessage("Build applied: your echoes were replaced.", 0.1, 1, 0.1)
        elseif status == "OK" and op == "recover" then
            UIErrorsFrame:AddMessage("Wishlist recovered: it is one of your builds again.", 0.1, 1, 0.1)
        elseif status == "OK" and op == "unlock" then
            UIErrorsFrame:AddMessage("Build slot " .. tostring(detail) .. " unlocked (account-wide).", 0.1, 1, 0.1)
        elseif status == "OK" and op == "upload" then
            -- detail: "<slot>" or "<slot>,<skipped>" when echoes were dropped
            local slot, skipped = tostring(detail):match("^(%d+),?(%d*)$")
            skipped = tonumber(skipped)
            if skipped and skipped > 0 then
                UIErrorsFrame:AddMessage(string.format(
                    "Build saved (%d echo%s not usable by your class skipped).",
                    skipped, skipped > 1 and "es" or ""), 1, 0.82, 0)
            else
                UIErrorsFrame:AddMessage("Build saved.", 0.1, 1, 0.1)
            end
        end

        NotifyBuildSlotsChanged()
    end)

-- Body: the active slot ("0" = none); pushed on login and on every change
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PERK_LOADOUT_ACTIVE,
    function(body)
        Perks.serverActiveSlot = tonumber(body) or 0
        -- Highlights and auto-pick need the build's CONTENT, not just its slot,
        -- and only the journal used to ask for it - so a player who never
        -- opened it got neither. The login push is the trigger; 540 fills
        -- serverBuildSlots, so this asks once.
        if Perks.serverBuildSlots == nil then
            ProjectEbonhold.PerkService.RequestServerBuildSlots()
        end
        NotifyBuildSlotsChanged()
    end)

-- Slot of the build most recently saved, or nil. Peeked (not consumed) so the
-- journal can clear it only once the matching row actually exists to flash.
ProjectEbonhold.PerkService.GetLastSavedBuildSlot = function()
    return Perks.lastSavedBuildSlot
end
ProjectEbonhold.PerkService.ClearLastSavedBuildSlot = function()
    Perks.lastSavedBuildSlot = nil
end

ProjectEbonhold.PerkService.RequestServerBuildSlots = function()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_LOADOUTS, "")
end
ProjectEbonhold.PerkService.SaveServerBuildSlot = function(slot, name)
    if not slot or slot < 1 then return false end
    if BuildSlotRequestBusy() then return false end
    MarkBuildSlotRequest("save")
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_LOADOUT_SAVE,
        tostring(slot) .. "|" .. SanitizeLoadoutName(name or ""))
    return true
end
ProjectEbonhold.PerkService.RenameServerBuildSlot = function(slot, name)
    if not slot or slot < 1 or not name or name == "" then return false end
    if BuildSlotRequestBusy() then return false end
    MarkBuildSlotRequest("rename")
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_LOADOUT_RENAME,
        tostring(slot) .. "|" .. SanitizeLoadoutName(name))
    return true
end
-- Stores a DESIGNED build (builder/import). slot 0 = new design (the server
-- assigns an id from the unlimited designed pool), an existing designed id =
-- overwrite. echoes: { {spellId, stacks(, locked)}, ... }. Persistent
-- server-side; drives the grey-out overview + draw highlight + auto-accept,
-- but never the guarantee.
ProjectEbonhold.PerkService.UploadServerBuildSlot = function(slot, name, echoes)
    if not slot or slot < 0 or not echoes or #echoes == 0 then return false end
    if BuildSlotRequestBusy() then return false end
    local parts = {}
    for _, e in ipairs(echoes) do
        table.insert(parts,
            tostring(e.spellId) .. "." .. tostring(e.stacks or 1) .. "." .. (e.locked and 1 or 0))
    end
    MarkBuildSlotRequest("upload")
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_LOADOUT_UPLOAD,
        tostring(slot) .. "|" .. SanitizeLoadoutName(name or "") .. "|" .. table.concat(parts, ","))
    return true
end
-- Turns a RECOVERABLE wishlist (a build a reset downgraded, flagged server
-- side) back into a real build: the server moves it into a free build slot and
-- marks it verified again. targetSlot nil/0 = the first free unlocked slot.
-- Alive and out of combat; no level gate, since wearing it still goes through
-- the level-80 swap.
ProjectEbonhold.PerkService.RecoverServerBuildSlot = function(slot, targetSlot)
    if not slot or slot < 1 then return false end
    if BuildSlotRequestBusy() then return false end
    MarkBuildSlotRequest("recover")
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_LOADOUT_RECOVER,
        tostring(slot) .. "|" .. tostring(targetSlot or 0))
    return true
end
-- Buys the NEXT locked slot with gold; the unlock is account-wide.
ProjectEbonhold.PerkService.UnlockServerBuildSlot = function()
    if BuildSlotRequestBusy() then return false end
    MarkBuildSlotRequest("unlock")
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_LOADOUT_UNLOCK, "")
    return true
end
ProjectEbonhold.PerkService.GetServerUnlockedSlots = function()
    return Perks.serverUnlockedSlots or (Perks.serverMaxSlots or 5)
end
ProjectEbonhold.PerkService.GetServerSlotCostGold = function(slot)
    return Perks.serverSlotCosts and Perks.serverSlotCosts[slot] or 0
end
ProjectEbonhold.PerkService.DeleteServerBuildSlot = function(slot)
    if not slot or slot < 1 then return false end
    if BuildSlotRequestBusy() then return false end
    MarkBuildSlotRequest("delete")
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_LOADOUT_DELETE, tostring(slot))
    return true
end
-- slot 0 = deactivate (any level). Level 1 arms the run; level 80 = full swap.
ProjectEbonhold.PerkService.ActivateServerBuildSlot = function(slot)
    if not slot or slot < 0 then return false end
    if BuildSlotRequestBusy() then return false end
    MarkBuildSlotRequest("activate")
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_LOADOUT_ACTIVATE, tostring(slot))
    return true
end
ProjectEbonhold.PerkService.GetServerBuildSlots = function()
    return Perks.serverBuildSlots
end
ProjectEbonhold.PerkService.GetServerActiveSlot = function()
    return Perks.serverActiveSlot or 0
end
ProjectEbonhold.PerkService.GetServerMaxSlots = function()
    return Perks.serverMaxSlots or 5
end
ProjectEbonhold.PerkService.AreServerBuildSlotsEnabled = function()
    return Perks.serverBuildSlotsEnabled
end
-- Activation is only meaningful at the run's endpoints
ProjectEbonhold.PerkService.CanActivateServerBuildSlot = function()
    local level = UnitLevel("player") or 1
    return level == 1 or level == 80
end

-- The ACTIVE server build (snapshot or designed) feeds the highlight +
-- auto-accept pipeline, and it is the ONLY source: this used to fall back on
-- the account-wide copy above as well, which nothing ever cleared, so a
-- deleted or swapped build kept auto-picking its echoes for the rest of the run.
ProjectEbonhold.PerkService.IsSpellInActiveEchoLoadout = function(spellId)
    if not serverActiveSet then RebuildServerActiveSet() end
    if serverActiveSet.ids[spellId] then return true end
    local nm = GetSpellInfo(spellId)
    return (nm and serverActiveSet.names[nm]) == true
end
