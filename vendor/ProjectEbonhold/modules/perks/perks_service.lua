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

-- Echoes already taken whose stack the server has not sent back yet. A pick fires
-- RequestChoice AND RequestGrantedPerks together, and the next choice can land
-- first -- without this the automatic pick would read a stale count and take a
-- second stack of something the build only asked once for.
local pendingPicks = {}

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
        -- An orb redraw counts as a reroll too: both repopulate the cards in place
        local wasReroll = (Perks.pendingReroll or Perks.pendingOrbReroll) and true or false
        Perks.pendingReroll = nil
        Perks.pendingOrbReroll = nil
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
        -- Spec draw (level 10 / 20 / ... 80): the server appends "S,<chosen spec family>".
        -- chosen = 0 is the level 10 draw (one card per spec, the spec is being chosen),
        -- otherwise the three cards are echoes of that spec. nil = an ordinary draw.
        Perks.currentSpecDraw = nil
        for perkPair in string.gmatch(bodyToParse, "([^;]+)") do
            local specChosenStr = perkPair:match("^S,(%d+)$")
            if specChosenStr then
                Perks.currentSpecDraw = { chosen = tonumber(specChosenStr) or 0 }
            end
            -- spellId,quality,flag[,memoryRemaining] - the 4th field only rides on the
            -- memory card (flag 3): souvenir stacks the climb still owes.
            local spellIdStr, qualityStr, isFrozenStr, extraStr = perkPair:match("^([^,]+),([^,]+),?([^,]*),?([^,]*)$")
            if spellIdStr and qualityStr then
                local spellId = tonumber(spellIdStr)
                local quality = tonumber(qualityStr)
                local isFrozenVal = tonumber(isFrozenStr) or 0
                local isFrozen = (isFrozenVal == 1)
                local isCarried = (isFrozenVal == 2)
                -- Flag 3 = the MEMORY card: an echo of this loadout's engraved build, offered
                -- next to the three random draws. Taking a random card instead sacrifices it
                -- for the rest of the climb. Kept under the historical `isGuaranteed` key:
                -- the styling and the banish/freeze refusals are the same.
                local isGuaranteed = (isFrozenVal == 3)
                if spellId and spellId ~= 0 and quality then
                    table.insert(choices,
                        { spellId = spellId, quality = quality, isFrozen = isFrozen, isCarried = isCarried,
                          isGuaranteed = isGuaranteed, memoryRemaining = isGuaranteed and tonumber(extraStr) or nil })
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
        -- An Orb of Lost Memories draw is deliberately exempt: the player paid an
        -- orb to forget an echo and re-pick it by hand, so swallowing that draw
        -- automatically forced them to toggle the option off before every spend
        -- and back on to keep levelling.
        local orbSvc = ProjectEbonhold.OrbService
        local orbOfferPending = orbSvc and orbSvc.IsOfferPending and orbSvc.IsOfferPending() and true or false
        local optSvc = _G["ProjectEbonholdOptionsService"]
        local autoAcceptSetting = optSvc and optSvc.GetSetting and optSvc:GetSetting("autoAcceptLoadoutEchoes")
        -- The level 10 spec draw is never auto-accepted: the card taken there picks the spec
        -- of every later spec draw of the run, so the player makes that call.
        local choosingSpec = Perks.currentSpecDraw and Perks.currentSpecDraw.chosen == 0
        if optSvc and optSvc.GetSetting and autoAcceptSetting and not orbOfferPending and not choosingSpec
            and ProjectEbonhold.PerkService.WantsMoreOfEcho then
            local best
            for _, choice in ipairs(choices) do
                -- Only a card the build still asks for, at the rarity it asked for.
                -- Refused echoes never qualify, so they need no test of their own.
                if ProjectEbonhold.PerkService.WantsMoreOfEcho(choice.spellId) then
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
        local justPicked = Perks.pendingSelectSpellId
        Perks.pendingSelectSpellId = nil -- selection resolved, unblock picks
        -- Selection succeeded
        if body >= "1" then
            if justPicked then
                pendingPicks[justPicked] = (pendingPicks[justPicked] or 0) + 1
            end
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
        -- The authoritative list is here: anything counted ahead of it is now in it
        for k in pairs(pendingPicks) do pendingPicks[k] = nil end

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
                    if data and data.isTome
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

-- id.quality.stacks, plus a trailing ".1" ONLY on an echo the build refuses.
-- Kept optional on purpose: a build with no refusals exports byte for byte the
-- string it always did, and an older client reading a newer string just drops
-- the refused entries instead of choking on the whole build.
local function SerializeEchoes(echoes)
    local parts = {}
    for _, e in ipairs(echoes or {}) do
        local part = e.spellId .. "." .. (e.quality or 0) .. "." .. (e.stacks or 1)
        if e.avoid then part = part .. ".1" end
        table.insert(parts, part)
    end
    return table.concat(parts, ",")
end

local function DeserializeEchoes(str)
    local echoes = {}
    for entry in string.gmatch(str or "", "([^,]+)") do
        local id, q, st, av = entry:match("^(%d+)%.(%d+)%.?(%d*)%.?(%d*)$")
        id = tonumber(id)
        if id then
            table.insert(echoes, { spellId = id, quality = tonumber(q) or 0,
                stacks = tonumber(st) or 1, avoid = (tonumber(av) == 1) or nil })
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

-- The orb's "Use Orbs" redraw goes through its own opcode; this flags its answer as a
-- reroll. Not used as an in-flight lock: a dropped orb request only leaves the next
-- reveal auto-shown.
function Perks.MarkOrbReroll()
    Perks.pendingOrbReroll = true
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
ProjectEbonhold.PerkService.MarkOrbReroll = Perks.MarkOrbReroll
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
    if not (data and data.isTome) then return false end
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
-- A link to the website's Echo Builder (".../tools/echo-builder?c=mage&b=200001.3-200020!200001"):
-- "id" or "id.stacks" pairs joined by "-", no quality and no name. The locked slots after
-- the "!" are a site-only planning aid and are dropped.
local function ParseEchoBuilderLink(text)
    if not text:find("echo%-builder") then return nil end
    local query = text:match("%?(.*)$")
    if not query then return nil end
    query = query:gsub("#.*$", ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    local build, slug
    for key, value in query:gmatch("([^&=]+)=([^&]*)") do
        if key == "b" then build = value elseif key == "c" then slug = value end
    end
    build = build and build:match("^([^!]*)")
    if not build or build == "" then return nil end
    local echoes = {}
    local db = ProjectEbonhold.PerkDatabase or {}
    for part in build:gmatch("[^%-]+") do
        local id, st = part:match("^(%d+)%.?(%d*)$")
        id = tonumber(id)
        if id then
            local perk = db[id]
            table.insert(echoes, { spellId = id, quality = perk and perk.quality or 0,
                stacks = tonumber(st) or 1 })
        end
    end
    if #echoes == 0 then return nil end
    -- "death-knight" -> "DEATHKNIGHT"; no class in the link = the player's own
    return { name = "Website build", class = SanitizeLoadoutClass(slug), echoes = echoes }
end

ProjectEbonhold.PerkService.ImportEchoLoadout = function(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local fromLink = ParseEchoBuilderLink(text)
    if fromLink then return fromLink end
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
-- stacks + locked flags).
--
-- Since the 2026-09 rework a build slot (1..maxSlots) is a LIVE loadout: an
-- independent echo build with its own echoes, locks, banishes, rerolls,
-- freezes and pending draws. Switching (any level, alive, out of combat,
-- behind a short cast) swaps the whole state; the target is handed the draws
-- its level owes it. Slot 1 always exists. Wishlists (ids > maxSlots) are
-- designed content, highlight-only.

Perks.serverBuildSlots = nil    -- nil until the first SEND_PERK_LOADOUTS reply; [slot] = { slot, name, echoes, verified (true = live loadout), missing }
Perks.serverUnlockedSlots = 1   -- highest usable slot (account-wide; from the 540 header)
Perks.serverSlotCosts = {}      -- [slot] = unlock price in gold (0 = free)
Perks.serverActiveSlot = 1      -- the live loadout being played (never 0)
Perks.serverActiveDesign = 0    -- highlighted wishlist id, 0 = none
Perks.serverMaxSlots = 10
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

-- ids/names of the highlighted WISHLIST's echoes, for draw highlighting and
-- auto-accept. The live loadout is what the player already owns, so it never
-- drives highlights. Lazy cache, invalidated on every 540/542 update.
local serverActiveSet = nil

-- want[spellId] = stacks asked for, avoid[spellId] = true. Keyed on the EXACT
-- spell id, never on the echo's name: every rarity of an echo is its own spell,
-- so "I want Immolation Aura, but only the rare one" needs nothing more than
-- reading the id the player actually put in the build. (Matching by name is
-- what used to make a common in the list highlight the rare too.)
local function RebuildServerActiveSet()
    serverActiveSet = { want = {}, avoid = {} }
    local slot = Perks.serverActiveDesign or 0
    local build = slot > 0 and Perks.serverBuildSlots and Perks.serverBuildSlots[slot]
    if build then
        for _, e in ipairs(build.echoes or {}) do
            if e.avoid then
                serverActiveSet.avoid[e.spellId] = true
            else
                serverActiveSet.want[e.spellId] = math.max(
                    serverActiveSet.want[e.spellId] or 0, e.stacks or 1)
            end
        end
    end
end

-- Stacks of this exact echo already held this run (granted + permanent)
local function OwnedStacksOf(spellId)
    local n = 0
    local granted = Perks.grantedPerks
    if granted then
        for _, instances in pairs(granted) do
            for _, inst in ipairs(instances) do
                if inst.spellId == spellId then n = n + (inst.stack or 1) end
            end
        end
    end
    for _, lp in ipairs(Perks.lockedPerks or {}) do
        if lp.spellId == spellId then n = n + (lp.stack or 1) end
    end
    return n + (pendingPicks[spellId] or 0)
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

-- Body: activeSlot|activeDesign|maxSlots|unlockedSlots|costG1.costG2...costGmax
--       ;slot|name|1|missingDraws|id.stack.locked,...   (live loadout)
--       ;slot|name|0|0|id.stack.locked,...              (wishlist)
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PERK_LOADOUTS,
    function(body)
        Perks.serverBuildSlots = {}

        if not body or body == "" then
            Perks.serverBuildSlotsEnabled = false
            Perks.serverActiveSlot = 1
            Perks.serverActiveDesign = 0
            NotifyBuildSlotsChanged()
            return
        end
        Perks.serverBuildSlotsEnabled = true

        local records = {}
        for record in string.gmatch(body, "([^;]+)") do
            table.insert(records, record)
        end

        local header = records[1] or ""
        local activeStr, designStr, maxStr, unlockedStr, costsStr = header:match("^(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
        Perks.serverActiveSlot = tonumber(activeStr) or 1
        Perks.serverActiveDesign = tonumber(designStr) or 0
        Perks.serverMaxSlots = tonumber(maxStr) or 10
        Perks.serverUnlockedSlots = tonumber(unlockedStr) or 1
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
            -- Row: slot|name|kind|missing|entries. kind 1 = live loadout (kept
            -- under the historical `verified` key), 0 = wishlist. `missing` =
            -- draws a switch to that loadout would grant right now.
            local slotStr, name, verifiedStr, infoStr, entriesStr, memoryStr =
                records[i]:match("^(%d+)|([^|]*)|([01])|([%d%.]+)|([^|]*)|?(.*)$")
            -- Live rows: missing.memoryRemaining.memoryTotal (draws a switch grants now,
            -- souvenir stacks the climb still owes, size of the engraved build)
            local missingStr, memRemStr, memTotStr = tostring(infoStr or ""):match("^(%d+)%.?(%d*)%.?(%d*)$")
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
                            local flag = tonumber(lockedStr) == 1
                            -- Live row: the flag is a permanent echo. Wishlist row
                            -- (kind 0): the same flag means the build refuses it.
                            local isLive = verifiedStr == "1"
                            table.insert(echoes, {
                                spellId = spellId,
                                quality = perkDb and perkDb.quality or 0,
                                stacks = tonumber(stackStr) or 1,
                                locked = flag and isLive or false,
                                avoid = (flag and not isLive) or nil,
                            })
                        end
                    end
                end
                -- Memory of a live loadout: the engraved build ({spellId, stacks,
                -- remaining}); `remaining` = stacks the current climb may still
                -- reclaim, which the Journal ghosts next to the owned echoes
                local memory = {}
                if memoryStr and memoryStr ~= "" then
                    for entry in string.gmatch(memoryStr, "([^,]+)") do
                        local idStr, stacksStr, remStr = entry:match("^(%d+)%.(%d+)%.(%d+)$")
                        local spellId = tonumber(idStr)
                        if spellId then
                            local perkDb = db[spellId]
                            table.insert(memory, { spellId = spellId, quality = perkDb and perkDb.quality or 0,
                                stacks = tonumber(stacksStr) or 1, remaining = tonumber(remStr) or 0 })
                        end
                    end
                end
                -- Wishes first, refusals last, each block by rarity: the row shows
                -- its first few icons, and those should be what the build wants.
                table.sort(echoes, function(a, b)
                    local aa, ba = a.avoid and 1 or 0, b.avoid and 1 or 0
                    if aa ~= ba then return aa < ba end
                    if (a.quality or 0) ~= (b.quality or 0) then
                        return (a.quality or 0) > (b.quality or 0)
                    end
                    return a.spellId < b.spellId
                end)

                Perks.serverBuildSlots[slot] = { slot = slot, name = name or "",
                    verified = verifiedStr == "1", missing = tonumber(missingStr) or 0,
                    memoryRemaining = tonumber(memRemStr) or 0, memoryTotal = tonumber(memTotStr) or 0,
                    echoes = echoes, memory = memory }
            end
        end

        NotifyBuildSlotsChanged()
    end)

-- Body: "OK,<op>,<slot>" or "FAIL,<op>,<reason>"
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PERK_LOADOUT_RESULT,
    function(body)
        Perks.pendingBuildSlotRequest = nil

        local status, op, detail = body:match("^([^,]+),([^,]+),(.*)$")

        -- Remembered so the journal can flash the row once it renders: "upload"
        -- is a designed build (the server picks the id).
        if status == "OK" and op == "upload" then
            local saved = tostring(detail):match("^(%d+)")
            if saved then Perks.lastSavedBuildSlot = tonumber(saved) end
        end

        if status == "FAIL" then
            local reasons = {
                disabled = "Echo loadouts are disabled on this realm.",
                slot = (op == "delete") and "A loadout cannot be deleted - only wishlists can." or "Invalid loadout slot.",
                empty = "This slot is empty.",
                same = "You are already playing this loadout.",
                combat = "You cannot switch loadouts in combat.",
                dead = "You cannot switch loadouts while dead.",
                locked = "This loadout slot is locked - unlock it with gold first.",
                max = "All loadout slots are already unlocked.",
                money = "You don't have enough gold to unlock this slot.",
                invalid = (op == "switch") and "Your echoes are not loaded yet. Try again in a moment."
                    or "This build contains no echoes usable by your class.",
                full = "You have too many wishlists. Delete one first.",
            }
            UIErrorsFrame:AddMessage(reasons[detail]
                or ("Loadout " .. tostring(op) .. " failed (" .. tostring(detail) .. ")."), 1, 0.2, 0.2)
        elseif status == "OK" and op == "switch" then
            local slots = Perks.serverBuildSlots or {}
            local build = slots[tonumber(detail) or 0]
            local name = build and build.name ~= "" and build.name or ("Loadout " .. tostring(detail))
            UIErrorsFrame:AddMessage("Now playing loadout " .. name .. ".", 0.1, 1, 0.1)
        elseif status == "OK" and op == "unlock" then
            UIErrorsFrame:AddMessage("Loadout slot " .. tostring(detail) .. " unlocked (account-wide).", 0.1, 1, 0.1)
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

-- Body: activeSlot|activeDesign (design 0 = none); pushed on login and on every change
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PERK_LOADOUT_ACTIVE,
    function(body)
        local slotStr, designStr = tostring(body or ""):match("^(%d+)|(%d+)$")
        Perks.serverActiveSlot = tonumber(slotStr) or tonumber(body) or 1
        Perks.serverActiveDesign = tonumber(designStr) or 0
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
-- The third field of an entry is the `locked` bit. On a LIVE loadout it means
-- "permanent echo"; a wishlist has no permanents, so there it carries the one
-- thing a wishlist needs and never had: this echo is refused. Same byte, same
-- wire, same column -- nothing server-side had to learn a new word.
ProjectEbonhold.PerkService.UploadServerBuildSlot = function(slot, name, echoes)
    if not slot or slot < 0 or not echoes or #echoes == 0 then return false end
    if BuildSlotRequestBusy() then return false end
    local parts = {}
    for _, e in ipairs(echoes) do
        local flag = (e.avoid or e.locked) and 1 or 0
        table.insert(parts,
            tostring(e.spellId) .. "." .. tostring(e.stacks or 1) .. "." .. flag)
    end
    MarkBuildSlotRequest("upload")
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_LOADOUT_UPLOAD,
        tostring(slot) .. "|" .. SanitizeLoadoutName(name or "") .. "|" .. table.concat(parts, ","))
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
-- Live slot (1..maxSlots): switch to that loadout (any level, alive, out of
-- combat; the server casts a short attunement first). Wishlist id: highlight
-- it. 0 = clear the highlighted wishlist.
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
-- The live loadout being played (1..maxSlots, never 0)
ProjectEbonhold.PerkService.GetServerActiveSlot = function()
    return Perks.serverActiveSlot or 1
end
-- The highlighted wishlist (0 = none)
ProjectEbonhold.PerkService.GetServerActiveDesign = function()
    return Perks.serverActiveDesign or 0
end
ProjectEbonhold.PerkService.GetServerMaxSlots = function()
    return Perks.serverMaxSlots or 10
end
ProjectEbonhold.PerkService.AreServerBuildSlotsEnabled = function()
    return Perks.serverBuildSlotsEnabled
end
-- Loadouts switch at any level since the 2026-09 rework; kept for callers.
ProjectEbonhold.PerkService.CanActivateServerBuildSlot = function()
    return true
end

-- The highlighted WISHLIST feeds the highlight + auto-accept pipeline, and it
-- is the ONLY source: this used to fall back on the account-wide copy above as
-- well, which nothing ever cleared, so a deleted or swapped build kept
-- auto-picking its echoes for the rest of the run.
ProjectEbonhold.PerkService.IsSpellInActiveEchoLoadout = function(spellId)
    if not serverActiveSet then RebuildServerActiveSet() end
    return serverActiveSet.want[spellId] ~= nil
end

-- "want", "avoid" or nil, from the highlighted wishlist
ProjectEbonhold.PerkService.GetActiveEchoLoadoutRule = function(spellId)
    if not serverActiveSet then RebuildServerActiveSet() end
    if serverActiveSet.avoid[spellId] then return "avoid" end
    if serverActiveSet.want[spellId] then return "want" end
    return nil
end

-- True while the build still asks for stacks of this echo. A wish for 3 stacks
-- stops being a wish at the third one, so the automatic pick hands the card back
-- instead of spending the rest of the climb topping up something already done.
ProjectEbonhold.PerkService.WantsMoreOfEcho = function(spellId)
    if not serverActiveSet then RebuildServerActiveSet() end
    local target = serverActiveSet.want[spellId]
    if not target then return false end
    return OwnedStacksOf(spellId) < target
end
