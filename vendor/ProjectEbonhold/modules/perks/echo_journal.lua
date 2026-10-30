-- Echo Journal
-- Unified echoes interface with three tabs:
--   My Echoes  - permanent slots + echoes active in the current run
--   All Echoes - full catalog, tome-locked echoes folded in (dimmed until the
--                tome is known, book badge, "Tomes only" filter in the dropdown)
--   Loadouts   - personal loadout library (snapshots of a run's echoes) +
--                community-shared loadouts; export/import via "EBH1:..." strings

local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
local Journal = {}
ProjectEbonhold.EchoJournal = Journal

-- ── Constants ────────────────────────────────────────────────────────────────
local PERKS_PER_ROW = 9
local BUTTON_SIZE = 46
local BUTTON_SPACING = 6
local NAME_HEIGHT = 18
local GRID_MARGIN_L = 10  -- left inset of the echo grid inside the scroll child
-- Shared, FIXED column pitch for both the catalog grid and the My Run grid
-- (My Echoes/All Echoes) -- each panel used to "justify" its own columns to
-- fill its own width, which stretched them by a different amount on each
-- side (different panel widths, different column counts) and made the
-- spacing visibly inconsistent between the two. A single fixed pitch used
-- by both guarantees they always match, at the cost of a little unused
-- margin on whichever panel doesn't perfectly divide into it.
local ECHO_GRID_HSTEP = 60

-- Merged Echoes tab only: a left column of currently-held run echoes next to
-- the full catalog, so "what do I have" and "what's out there" are both
-- visible at once instead of one undifferentiated wall of icons. Both panels
-- (and the window itself) are noticeably wider than the Loadouts tab's single
-- column -- CollectionsJournal grows past its native size to fit, the same
-- way Transmogrify already does for WardrobeFrame.
local MY_RUN_PANEL_W = 300
local MYRUN_COLS = 5
local PANEL_GAP = 30
local BASE_JOURNAL_W = 480  -- journalFrame's declared width (Loadouts tab, single column)
local ECHOES_CATALOG_W = 590  -- catalog (right column) width on the Echoes tab specifically -- wide enough for 9 columns at ECHO_GRID_HSTEP
local ECHOES_JOURNAL_W = ECHOES_CATALOG_W + MY_RUN_PANEL_W + PANEL_GAP

local TAB_MY_RUN, TAB_ALL, TAB_LOADOUTS = 1, 2, 3
local TAB_LABELS = { "My Echoes", "All Echoes", "Loadouts" }

local ASSETS = "Interface\\AddOns\\ProjectEbonhold\\assets\\"

local qualityColors = {
    [0] = { r = 1.0, g = 1.0, b = 1.0 }, -- Common
    [1] = { r = 0.1, g = 1.0, b = 0.1 }, -- Uncommon
    [2] = { r = 0.0, g = 0.4, b = 1.0 }, -- Rare
    [3] = { r = 0.8, g = 0.4, b = 1.0 }, -- Epic
    [4] = { r = 1.0, g = 0.5, b = 0.0 }, -- Legendary
}

local QUALITY_NAMES = {
    [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legendary",
}

-- Owned-per-quality badges ringing an echo icon, same size as the single count
-- badge they replace. Only three fit around a 46px icon at full size (the
-- bottom is taken by the name text), so the three rarest owned qualities win:
-- slot 1 = top, 2 = left, 3 = right. Offsets are from the icon's center.
local QUALITY_BADGE_SLOTS = 3
local QUALITY_BADGE_SIZE = 22
local QUALITY_BADGE_POS = {
    { x = 0,   y = 21 },
    { x = -22, y = 0  },
    { x = 22,  y = 0  },
}

local MAX_RUN_ECHOES = 79 -- one roll per level gained (2..80), so 79 picks per run

-- Shared "an armed selection will act on THIS echo" mauve. The Orb of Lost Memories and the
-- permanent-slot lock both hijack a click on the same grid, so they mark their target the same
-- way. Only one of the two can ever be armed (see Journal.CancelLockMode), so one colour is
-- enough - two would read as two things happening at once.
local ARMED_PICK_R, ARMED_PICK_G, ARMED_PICK_B = 0.72, 0.36, 1.0 -- == the orb bubble's glow

-- ── State ────────────────────────────────────────────────────────────────────
local journalFrame
local currentTab = TAB_MY_RUN
local currentSearchText = ""
-- Multi-select filters: sets of enabled entries; an empty set means "show all"
local selectedQualities = {} -- [quality] = true
local selectedFamilies = {}  -- [familyName] = true
local selectedTomesOnly = false -- restrict the catalog to tome-locked echoes
local selectedKnownTomesOnly = false -- restrict further to tomes the player has learned
local selectedMyClassOnly = true -- restrict the catalog to echoes usable by the player's class (ON by default)
local selectedEnabledOnly = false -- only known tome echoes that are currently ENABLED
local selectedDisabledOnly = false -- only known tome echoes the player has DISABLED

local gridButtons = {}
local slotButtons = {}
local tabButtons = {}
local scrollFrame, scrollChild
local myRunScrollFrame, myRunScrollChild
local loadoutFooter, loadoutDD, loadoutPrimaryBtn, loadoutSecondaryBtn
local myRunInset, catalogInset
local myRunButtons = {}
local myRunEmptyState
local contextBar, searchBox, filterButton

-- When active, clicking one of your echoes in the My Run grid locks it into a
-- free permanent slot instead of the normal click behavior.
local lockModeActive = false

-- Loadout builder: while active, the All Echoes grid becomes a picker
-- (left-click adds a stack, right-click removes one) with a Done/Cancel banner.
local builderDraft = nil -- { name = string, entries = { [spellId] = { quality, stacks } } }

-- Set just before showing PROJECTEBONHOLD_LOADOUT_NAME from the loadout
-- footer's dropdown (picking a specific empty slot) so the new wishlist
-- targets that slot instead of auto-picking the first free one (the
-- footer's plain "New Wishlist" button leaves this nil).
local pendingWishlistTargetSlot = nil

-- Set when the player creates their FIRST-ever build (snapshot, wishlist or
-- import): once the server's slot list comes back with exactly that one build
-- and nothing armed, it gets armed automatically (see UpdateLoadoutFooter).
-- The server's armed slot is the ONLY thing that drives highlights and
-- auto-pick, so arming has to wait for the id the server assigns.
local autoActivateFirstBuild

local function DraftCount()
    local n = 0
    if builderDraft then
        for _ in pairs(builderDraft.entries) do n = n + 1 end
    end
    return n
end

-- Total stacks across the draft: a build cannot hold more echoes than a run
-- can grant (MAX_RUN_ECHOES)
local function DraftTotalStacks()
    local n = 0
    if builderDraft then
        for _, e in pairs(builderDraft.entries) do n = n + (e.stacks or 1) end
    end
    return n
end

-- Loadouts tab: "mine" shows the local library, "community" the shared list
local loadoutView = "mine"
local loadoutRows = {}
local loadoutHeaders = {} -- class group headers, one per class in the list
local sectionHeaders = {} -- collapsible build-slot group headers (mine view)
local loadoutEmptyText
local pendingLoadout -- { loadout, index } captured for the confirm popups

-- Collapsed state of the mine-view sections, persisted account-wide
local function IsSectionCollapsed(key)
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.buildSectionCollapsed = ProjectEbonholdDB.buildSectionCollapsed or {}
    return ProjectEbonholdDB.buildSectionCollapsed[key] == true
end

local function ToggleSectionCollapsed(key)
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.buildSectionCollapsed = ProjectEbonholdDB.buildSectionCollapsed or {}
    ProjectEbonholdDB.buildSectionCollapsed[key] = (not ProjectEbonholdDB.buildSectionCollapsed[key]) or nil
end
-- Class filter, nil = all classes. Defaults to the player's own class.
local selectedLoadoutClass = select(2, UnitClass("player"))

local LOADOUT_CLASSES = {
    "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
    "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

local function ClassDisplay(token)
    token = token or "UNKNOWN"
    local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then
        return string.format("|cff%02x%02x%02x%s|r",
            math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), name)
    end
    return "|cff999999" .. name .. "|r"
end

local Refresh -- forward declaration (used by closures created before its definition)

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function GetPlayerClassMask()
    local classToMask = {
        WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
        DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
    }
    local _, class = UnitClass("player")
    return classToMask[class] or 0
end

local function GetService()
    return ProjectEbonhold.PerkService
end

-- The build driving the My Echoes overview (ghosts + "Build:" header line).
-- The armed server slot wins; otherwise the wish-list loadout being played
-- (shared/imported builds - highlight-only, same as snapshots below 80).
-- Returns loadout, isSnapshot (true = a server-verified snapshot, applied whole
-- at level 80; false = wish-list, its echoes are only highlighted when rolled).
local function GetActiveBuildOverview()
    local svc = GetService()
    if not svc then return nil, false end

    local activeSlot = svc.GetServerActiveSlot and svc.GetServerActiveSlot() or 0
    local slots = svc.GetServerBuildSlots and svc.GetServerBuildSlots()
    local server = activeSlot > 0 and slots and slots[activeSlot] or nil
    if server then
        -- Snapshot builds are applied whole at 80; designed/imported ones
        -- are highlight-only, same treatment as a wish-list loadout.
        return server, server.verified and true or false
    end

    local wish = svc.GetActiveEchoLoadout and svc.GetActiveEchoLoadout()
    if wish and wish.echoes and #wish.echoes > 0 then
        return wish, false
    end

    return nil, false
end

-- spellId -> { stacks = n, locked = bool } from the current run
local function GetOwnedInfo()
    local owned = {}
    local svc = GetService()
    if not svc then return owned end

    local granted = svc.GetGrantedPerks and svc.GetGrantedPerks() or {}
    for _, instances in pairs(granted) do
        for _, inst in ipairs(instances) do
            local entry = owned[inst.spellId] or { stacks = 0, locked = false, quality = inst.quality or 0 }
            entry.stacks = entry.stacks + (inst.stack or 1)
            owned[inst.spellId] = entry
        end
    end

    local lockedPerks = svc.GetLockedPerks and svc.GetLockedPerks() or {}
    for _, lp in ipairs(lockedPerks) do
        local entry = owned[lp.spellId] or { stacks = 0, locked = false, quality = lp.quality or 0 }
        entry.stacks = entry.stacks + (lp.stack or 1)
        entry.locked = true
        owned[lp.spellId] = entry
    end

    return owned
end

-- True if ANY server-side build exists (snapshot slots or designed pool) --
-- the player's very first build gets auto-activated on creation (see
-- CompleteBuilderSave/CompleteImport/UpdateLoadoutFooter).
local function HasAnyBuild()
    local svc = GetService()
    local slots = svc and svc.GetServerBuildSlots and svc.GetServerBuildSlots() or {}
    return next(slots) ~= nil
end

local function MatchesFamily(data)
    if not next(selectedFamilies) then return true end
    if not data.families then return false end
    for _, fam in ipairs(data.families) do
        if selectedFamilies[fam] then return true end
    end
    return false
end

-- Per-spell cache of lowercased, color-stripped tooltip text, used by the
-- search bar to match on an echo's effect and not just its name.
--
-- Each entry costs a hidden-tooltip scrape, and the catalog is ~550 echoes:
-- filling the cache lazily from the filter meant the first search scraped the
-- whole catalog inside one frame and froze the client for seconds. So the
-- filter now only ever READS the cache, and the cache is filled by a warmer
-- that runs a few echoes per frame in the background (see WarmSearchDescCache).
local searchDescCache = {}
local function GetSearchableDescription(spellId)
    return searchDescCache[spellId] or ""
end

-- Budget per frame rather than a fixed count: how slow one scrape is varies a
-- lot per client, and a time budget self-tunes (many echoes per frame on a fast
-- client, one at a time on a slow one) instead of picking a count that either
-- stutters or drags the warm-up out for no reason.
local DESC_WARM_BUDGET_MS = 8
local DESC_WARM_FALLBACK = 3 -- per frame, when no millisecond timer exists
local descWarmQueue, descWarmIndex, descWarmDone
local descWarmFrame

-- Kick off (or resume) the background fill. Cheap to call repeatedly: it is a
-- no-op once the catalog has been scraped.
local function WarmSearchDescCache()
    if descWarmDone or not ProjectEbonhold.PerkDatabase then return end
    if not utils or not utils.GetSpellSearchText then
        descWarmDone = true
        return
    end

    if not descWarmQueue then
        descWarmQueue = {}
        for spellId in pairs(ProjectEbonhold.PerkDatabase) do
            table.insert(descWarmQueue, spellId)
        end
        descWarmIndex = 1
    end

    if not descWarmFrame then
        descWarmFrame = CreateFrame("Frame")
        descWarmFrame:Hide()
        descWarmFrame:SetScript("OnUpdate", function(self, elapsed)
            if ProjectEbonhold_IsClosing then self:Hide() return end

            local clock = debugprofilestop
            local deadline = clock and (clock() + DESC_WARM_BUDGET_MS)
            local left = DESC_WARM_FALLBACK

            repeat
                local spellId = descWarmQueue[descWarmIndex]
                if not spellId then
                    self:Hide()
                    descWarmDone = true
                    descWarmQueue = nil
                    -- Echoes still uncached could not match on their effect
                    -- while the user was typing; redo the pass now they can.
                    if currentSearchText ~= "" and journalFrame and journalFrame:IsShown() then
                        Refresh()
                    end
                    return
                end
                descWarmIndex = descWarmIndex + 1

                if not searchDescCache[spellId] then
                    local text = utils.GetSpellSearchText(spellId) or ""
                    searchDescCache[spellId] =
                        string.lower(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
                end

                left = left - 1
            until (deadline and clock() >= deadline) or (not deadline and left <= 0)

            -- A search running during the warm-up matches against a cache that
            -- is still growing, so let its results fill in as we go instead of
            -- sitting on name-only matches until the very last echo.
            if currentSearchText ~= "" and journalFrame and journalFrame:IsShown() then
                self.sinceRefresh = (self.sinceRefresh or 0) + elapsed
                if self.sinceRefresh >= 0.5 then
                    self.sinceRefresh = 0
                    Refresh()
                end
            end
        end)
    end

    descWarmFrame:Show()
end

-- searchOnly: My Echoes has no filter row, only the search bar applies there
local function PassesFilters(spellId, data, forceClassFilter, searchOnly)
    local spellName = GetSpellInfo(spellId)
    if not spellName then return false end

    if currentSearchText ~= "" then
        local needle = string.lower(currentSearchText)
        local matches = string.find(string.lower(spellName), needle, 1, true) ~= nil
        if not matches and data.comment then
            matches = string.find(string.lower(data.comment), needle, 1, true) ~= nil
        end
        if not matches then
            matches = string.find(GetSearchableDescription(spellId), needle, 1, true) ~= nil
        end
        if not matches then return false end
    end

    if searchOnly then return true end

    if next(selectedQualities) and not selectedQualities[data.quality] then
        return false
    end

    if forceClassFilter and ProjectEbonhold.IsPerkAvailableForClass then
        if not ProjectEbonhold.IsPerkAvailableForClass(spellId, GetPlayerClassMask()) then
            return false
        end
    end

    return MatchesFamily(data)
end

local function SortItems(items)
    -- item.name is cached by BuildItems: the comparator runs O(n log n) times
    -- and per-call GetSpellInfo lookups made large catalogs stutter.
    table.sort(items, function(a, b)
        if (a.stacks or 0) > 0 ~= ((b.stacks or 0) > 0) then
            return (a.stacks or 0) > 0
        end
        if a.data.quality ~= b.data.quality then
            return a.data.quality > b.data.quality
        end
        return (a.name or "") < (b.name or "")
    end)
end

-- Returns the item list for a tab, plus (ownedCount, totalCount) for Collection
local function BuildItems(tab)
    local owned = GetOwnedInfo()
    local items = {}
    local ownedCount, totalCount = 0, 0

    if tab == TAB_MY_RUN then
        -- Group quality variants by echo name with per-quality counts, like
        -- the run echoes panel. The search bar only filters the catalog (All
        -- Echoes) -- this list always shows everything currently held.
        local svc = GetService()
        local granted = svc and svc.GetGrantedPerks and svc.GetGrantedPerks() or {}
        local lockedPerks = svc and svc.GetLockedPerks and svc.GetLockedPerks() or {}
        local discovered = svc and svc.GetDiscoveredEchoes and svc.GetDiscoveredEchoes() or {}

        local byName = {}
        local function AddInstance(spellId, quality, stacks, isLocked)
            local name = GetSpellInfo(spellId)
            if not name then return end
            local entry = byName[name]
            if not entry then
                entry = { counts = {}, totalStacks = 0, quality = -1 }
                byName[name] = entry
            end
            local q = quality or 0
            entry.counts[q] = (entry.counts[q] or 0) + stacks
            entry.totalStacks = entry.totalStacks + stacks
            if q > entry.quality then
                entry.quality = q
                entry.spellId = spellId
            end
            -- The orb forgets the CHEAPEST copy, not the one the card shows. A card is one echo
            -- NAME with every rarity of it folded in, and it displays the best rarity held - so
            -- targeting entry.spellId spent the rare while commons of the same echo sat there
            -- untouched. Permanent stacks are skipped rather than counted: they are not legal
            -- orb targets, so a locked common must not shadow the uncommon the orb can take.
            if not isLocked and (entry.orbQuality == nil or q < entry.orbQuality) then
                entry.orbQuality = q
                entry.orbSpellId = spellId
            end
            if isLocked then entry.locked = true end
        end

        for _, instances in pairs(granted) do
            for _, inst in ipairs(instances) do
                AddInstance(inst.spellId, inst.quality, inst.stack or 1, false)
            end
        end
        for _, lp in ipairs(lockedPerks) do
            AddInstance(lp.spellId, lp.quality, lp.stack or 1, true)
        end

        -- Active build (armed server slot, else the wish-list loadout being
        -- played): its echoes belong on this tab too. Owned ones are annotated
        -- (build target in the tooltip); ones with no stacks yet show as
        -- greyed ghosts so the whole target build stays visible.
        -- A snapshot can no longer be the active build while leveling (level-80
        -- only), so the overview always tracks a wish-list: match by name across
        -- quality variants, exactly like the draw highlight does.
        local activeBuild = GetActiveBuildOverview()

        local ghostItems = {}
        if activeBuild then
            for _, e in ipairs(activeBuild.echoes or {}) do
                local data = ProjectEbonhold.PerkDatabase[e.spellId]
                if data then
                    local name = GetSpellInfo(e.spellId)
                    local entry = name and byName[name]
                    local ownedStacks = entry and entry.totalStacks or 0

                    if ownedStacks == 0 then
                        -- Tome status carries onto build ghosts: players compare
                        -- this column against the catalog next door, so a ghost
                        -- whose tome is already learned must say so too instead
                        -- of falling back to "Requires Tome to unlock".
                        local isTome = (data.requiredSpell and data.requiredSpell ~= 0) or false
                        local tomeKnown = isTome and discovered[e.spellId] ~= nil
                        table.insert(ghostItems, {
                            spellId = e.spellId, data = data,
                            name = name,
                            stacks = 0,
                            dimmed = true,
                            buildMissing = true,
                            buildTarget = e.stacks or 1,
                            buildLocked = e.locked or false,
                            isTome = isTome,
                            tomeKnown = tomeKnown,
                            tomeDisabled = (tomeKnown and svc and svc.IsTomeEchoDisabled
                                and svc.IsTomeEchoDisabled(e.spellId)) or false,
                        })
                    else
                        local entry = name and byName[name]
                        if entry then
                            entry.buildTarget = e.stacks or 1
                            entry.buildLocked = e.locked or false
                        end
                    end
                end
            end
        end

        local totalPicks = 0
        for _, entry in pairs(byName) do
            totalPicks = totalPicks + entry.totalStacks
            local data = ProjectEbonhold.PerkDatabase[entry.spellId]
            if data then
                -- Holding stacks of a tome echo implies its tome is known (the
                -- catalog draws the same inference from ownership).
                local isTome = (data.requiredSpell and data.requiredSpell ~= 0) or false
                table.insert(items, {
                    spellId = entry.spellId, data = data,
                    name = GetSpellInfo(entry.spellId),
                    counts = entry.counts,
                    orbSpellId = entry.orbSpellId,
                    orbQuality = entry.orbQuality,
                    stacks = entry.totalStacks,
                    locked = entry.locked or false,
                    buildTarget = entry.buildTarget,
                    buildLocked = entry.buildLocked,
                    isTome = isTome,
                    tomeKnown = isTome,
                    tomeDisabled = (isTome and svc and svc.IsTomeEchoDisabled
                        and svc.IsTomeEchoDisabled(entry.spellId)) or false,
                })
            end
        end
        for _, ghost in ipairs(ghostItems) do
            table.insert(items, ghost)
        end

        SortItems(items)

        -- No empty-slot padding: the grid shows only owned echoes and the
        -- active build's ghosts; remaining picks live in the header count.

        return items, totalPicks, MAX_RUN_ECHOES
    else
        -- Single catalog: tome-locked echoes are folded in (dimmed until their
        -- tome is known, tome badge in the grid, "Tomes only" filter in the
        -- dropdown). ownedCount/totalCount carry the DB-wide tome progression.
        -- Regular echoes are never dimmed here -- see the dimmed= comment below.
        local svc = GetService()
        local discovered = svc and svc.GetDiscoveredEchoes and svc.GetDiscoveredEchoes() or {}

        -- Echoes currently held this run already sit in the My Run column
        -- right next to this catalog -- listing them here too is pure
        -- duplication, so they're hidden. Matched by NAME (like My Run's own
        -- grouping), so holding any quality variant hides every variant of
        -- that echo. Exception: while designing a build the catalog is the
        -- picker and must stay complete -- you may well want an echo you
        -- happen to be holding right now in the new build.
        local heldNames = {}
        if not builderDraft then
            for heldSpellId in pairs(owned) do
                local heldName = GetSpellInfo(heldSpellId)
                if heldName then heldNames[heldName] = true end
            end
        end

        for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
            local isTome = data.requiredSpell and data.requiredSpell ~= 0
            local info = owned[spellId]
            local isUnlocked = info ~= nil or discovered[spellId] ~= nil
            -- an unlocked (un-dimmed) tome echo = its tome is known: highlight
            -- it, count it in the tome progression and offer unlearning
            local tomeKnown = isTome and isUnlocked

            if isTome then
                totalCount = totalCount + 1
                if isUnlocked then ownedCount = ownedCount + 1 end
            end

            -- Enabled/Disabled state only exists for KNOWN tome echoes (the
            -- right-click toggle); both filters implicitly restrict to those.
            local tomeOff = (tomeKnown and svc and svc.IsTomeEchoDisabled
                and svc.IsTomeEchoDisabled(spellId)) or false

            -- While designing a build, restrict the picker to echoes YOUR class
            -- can obtain (a designed build is always for your own class). This
            -- filters by class availability, not ownership, so not-yet-farmed
            -- tome echoes of your class still show (dimmed) as valid goals.
            if (not selectedTomesOnly or isTome)
                and (not selectedKnownTomesOnly or tomeKnown)
                and (not selectedEnabledOnly or (tomeKnown and not tomeOff))
                and (not selectedDisabledOnly or tomeOff)
                and not heldNames[GetSpellInfo(spellId) or ""]
                and PassesFilters(spellId, data,
                    selectedTomesOnly or selectedKnownTomesOnly or selectedMyClassOnly
                    or selectedEnabledOnly or selectedDisabledOnly
                    or (builderDraft ~= nil)) then
                table.insert(items, {
                    spellId = spellId, data = data,
                    name = GetSpellInfo(spellId),
                    stacks = info and info.stacks or 0,
                    locked = info and info.locked or false,
                    isTome = isTome,
                    tomeKnown = tomeKnown or false,
                    tomeDisabled = tomeOff,
                    -- Tome-only dimming: discovered[] is reliable for tomes
                    -- (a real persistent unlock), but for regular echoes it
                    -- only reflects the server's discovery log, which for an
                    -- existing character can be far sparser than what they've
                    -- actually drawn across past runs (feature added later,
                    -- no retroactive backfill) -- dimming those by it made
                    -- almost the whole catalog grey out incorrectly.
                    dimmed = isTome and not isUnlocked,
                    timesObtained = discovered[spellId],
                })
            end
        end
    end

    SortItems(items)
    return items, ownedCount, totalCount
end

-- ── Chat linking (same marker format as the legacy browser) ──────────────────
local function LinkEchoInChat(spellId, quality)
    local marker = "{echo:" .. spellId .. ":" .. (quality or 0) .. "}"
    local editBox = ChatFrameEditBox
    if not editBox or not editBox:IsShown() then
        editBox = ChatFrame1EditBox
    end
    if editBox and editBox:IsShown() then
        editBox:Insert(marker)
    else
        ChatFrame_OpenChat("")
        C_Timer.After(0.1, function()
            local eb = ChatFrame1EditBox
            if eb then eb:Insert(marker) end
        end)
    end
end

-- ── Tome unlearning (right-click a learned tome in the catalog) ──────────────
StaticPopupDialogs["PROJECTEBONHOLD_UNLEARN_TOME"] = {
    text = "Are you sure you want to unlearn |cffffd700%s|r?\n\n" ..
        "|cffFF4444This is permanent.|r You will lose the tome and will need " ..
        "to loot it again to relearn it.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self)
        local d = self.data
        if d and ProjectEbonhold.SpellUnlearnService then
            ProjectEbonhold.SpellUnlearnService.RequestUnlearn(d.tomeSpellId)
            -- optimistic update: drop it from the local discovery list so the
            -- journal re-dims the echo immediately (no server round-trip)
            local svc = ProjectEbonhold.PerkService
            if svc and svc.RemoveDiscoveredEcho then
                svc.RemoveDiscoveredEcho(d.echoId)
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Right-click on a learned tome echo: enable/disable it (level 1 only, with a
-- confirmation popup). Replaces the old destructive unlearning - the tome
-- knowledge is kept, only its echo's presence in the draw pool toggles.
StaticPopupDialogs["PROJECTEBONHOLD_TOME_DISABLE"] = {
    text = "Disable |cffffd700%s|r?\n\nIts echo will no longer appear in your draws this run. You can re-enable it at level 1 anytime. The tome is never lost.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        local svc = GetService()
        if self.data and svc and svc.ToggleTomeEcho then
            svc.ToggleTomeEcho(self.data)
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_TOME_ENABLE"] = {
    text = "Enable |cffffd700%s|r?\n\nIts echo can appear in your draws again.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        local svc = GetService()
        if self.data and svc and svc.ToggleTomeEcho then
            svc.ToggleTomeEcho(self.data)
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function TryToggleTome(button)
    local data = button.perkData
    if not (button.tomeKnown and data and data.requiredSpell and data.requiredSpell ~= 0) then
        return
    end
    if (UnitLevel("player") or 1) ~= 1 then
        UIErrorsFrame:AddMessage("Tomes can be enabled or disabled at level 1 only.", 1, 0.2, 0.2)
        return
    end
    local svc = GetService()
    local name = GetSpellInfo(button.spellId) or "this echo"
    local which = (svc and svc.IsTomeEchoDisabled and svc.IsTomeEchoDisabled(button.spellId))
        and "PROJECTEBONHOLD_TOME_ENABLE" or "PROJECTEBONHOLD_TOME_DISABLE"
    local dialog = StaticPopup_Show(which, name)
    if dialog then dialog.data = button.spellId end
end

-- ── Grid buttons ─────────────────────────────────────────────────────────────
local function ShowEchoTooltip(button)
    if button.isEmptySlot then
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Empty Echo Slot", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Level up to roll more echoes this run.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
        return
    end
    if not button.spellId then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local spellName = GetSpellInfo(button.spellId)
    local data = button.perkData
    if spellName and data then
        local color = qualityColors[data.quality] or qualityColors[0]
        GameTooltip:AddLine(spellName, color.r, color.g, color.b)

        if utils and utils.GetSpellDescription then
            -- Resolve the stat formulas at everything you own (all qualities
            -- summed), matching the permanent-slot tooltip. Falls back to the
            -- per-stack base value in the catalog, where you own none.
            local descStacks = (button.ownedStacks or 0) > 0 and button.ownedStacks or 1
            GameTooltip:AddLine(utils.GetSpellDescription(button.spellId, 4000, descStacks), 1, 1, 1, true)
        else
            GameTooltip:SetHyperlink("spell:" .. button.spellId)
        end

        GameTooltip:AddLine(" ")
        local familyIcons = utils and utils.FormatPerkFamilies and utils.FormatPerkFamilies(data.families)
        if familyIcons then
            GameTooltip:AddDoubleLine("Perk Family", familyIcons, 0.6, 0.6, 0.6, 1, 1, 1)
        end
        if button.isLocked then
            GameTooltip:AddLine("Permanent echo (locked between runs)", 1, 0.82, 0)
        end
        if button.buildMissing then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(
                "From your active build: not obtained yet (0/%d)", button.buildTarget or 1), 1, 0.82, 0.1)
            GameTooltip:AddLine("It will be highlighted when it appears in your draws.", 0.9, 0.9, 0.9, true)
            if button.buildLocked then
                GameTooltip:AddLine("Saved as a locked echo in this build.", 0.5, 0.75, 1)
            end
        elseif button.buildTarget then
            GameTooltip:AddDoubleLine("Active build target",
                tostring(button.ownedStacks or 0) .. " / " .. tostring(button.buildTarget),
                1, 0.82, 0.1, 1, 1, 1)
            if button.buildLocked then
                GameTooltip:AddLine("Saved as a locked echo in this build.", 0.5, 0.75, 1)
            end
        end

        local dropSource = ProjectEbonhold.PerkDropSources and ProjectEbonhold.PerkDropSources[button.spellId]
        if not dropSource and data.groupId and ProjectEbonhold.PerkDropSourceByGroup then
            dropSource = ProjectEbonhold.PerkDropSourceByGroup[data.groupId]
        end
        if dropSource then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(dropSource, 0.5, 0.5, 0.5, true)
        end

        if data.requiredSpell and data.requiredSpell ~= 0 then
            GameTooltip:AddLine(" ")
            if button.tomeKnown then
                if button.tomeDisabled then
                    GameTooltip:AddLine("Tome learned (|cffff5050disabled|r)", 0.1, 1, 0.1)
                    GameTooltip:AddLine("This echo will not appear in your draws.", 0.9, 0.9, 0.9, true)
                    GameTooltip:AddLine("Right-click to enable it (level 1 only)", 0.5, 0.5, 0.5)
                else
                    GameTooltip:AddLine("Tome learned (|cff40ff40enabled|r)", 0.1, 1, 0.1)
                    GameTooltip:AddLine("Right-click to disable it (level 1 only)", 0.5, 0.5, 0.5)
                end
            else
                GameTooltip:AddLine("Requires Tome to unlock", 1, 0.82, 0)
            end
        end

        GameTooltip:AddLine(" ")

        -- While an Orb of Lost Memories is armed, both mouse buttons are taken over: left
        -- forgets this echo now, right queues it into a batch. The hint has to say THAT and
        -- nothing else - the usual bindings are suppressed for the duration (see the button's
        -- OnClick), so advertising them would promise something that will not happen.
        local orb = ProjectEbonhold.OrbService
        local orbArmed = orb and orb.IsArmed and orb.IsArmed()
        local orbTarget = button.orbSpellId or button.spellId
        local orbMarked = orbArmed and orb.IsMarked and orb.IsMarked(orbTarget)
        local orbBatch = (orbArmed and orb.GetMarkedCount and orb.GetMarkedCount()) or 0

        -- Mauve hover while the echo under the cursor is the one an armed selection would act
        -- on: an orb about to forget it, or a permanent slot about to lock it. The stock
        -- highlight is the blue minimap glow, which reads as "selectable" - this has to read as
        -- "this is the one the armed click takes", so it borrows the Epic purple.
        if button._highlight then
            local armedOnThis = (button.ownedStacks or 0) > 0
                and (button.orbSpellId ~= nil or not button.isLocked)
                and (orbArmed or lockModeActive)
            if armedOnThis then
                button._highlight:SetVertexColor(ARMED_PICK_R, ARMED_PICK_G, ARMED_PICK_B, 1)
            else
                button._highlight:SetVertexColor(1, 1, 1, 1)
            end
        end

        if orbArmed and button.isLocked and not button.orbSpellId then
            -- A permanent echo is not a legal target: forgetting one would silently undo a
            -- slot the player paid for, and the server refuses it anyway.
            GameTooltip:AddLine("|cffFF8080Permanent Echoes cannot be forgotten|r", 1, 0.5, 0.5, true)
            GameTooltip:AddLine("Free its permanent slot first.", 0.6, 0.6, 0.6, true)
        elseif orbArmed and (button.ownedStacks or 0) > 0 then
            if orbMarked then
                GameTooltip:AddLine("|cffCC66FFQueued to be forgotten|r", 1, 1, 1, true)
                GameTooltip:AddLine("|cffFFD100Right-click to take it back out|r", 1, 1, 1, true)
            else
                GameTooltip:AddLine("|cffFFD100Left-click to forget one stack now|r", 1, 1, 1, true)
                GameTooltip:AddLine("|cffFFD100Right-click to add it to a batch|r", 1, 1, 1, true)
                GameTooltip:AddLine("Pick as many different Echoes as you like, then confirm from the orb window. One orb each.", 0.6, 0.6, 0.6, true)
            end
            -- Which copy goes. Only worth saying on a card holding more than one rarity: with a
            -- single rarity held the badge above already says it, and the line becomes noise.
            if button.orbQuality and button.counts then
                local heldRarities = 0
                for _, count in pairs(button.counts) do
                    if count > 0 then heldRarities = heldRarities + 1 end
                end
                if heldRarities > 1 then
                    local qc = qualityColors[button.orbQuality] or qualityColors[0]
                    GameTooltip:AddLine("Takes your lowest rarity: " ..
                        (QUALITY_NAMES[button.orbQuality] or "?"), qc.r, qc.g, qc.b, true)
                end
            end
            GameTooltip:AddLine("A new Echo choice is offered for each one.", 0.6, 0.6, 0.6, true)
            if orbBatch > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Queued", orbBatch .. " / " .. tostring((orb.GetCharges and orb.GetCharges()) or 0) .. " orbs",
                    0.8, 0.5, 1, 1, 1, 1)
            end
        elseif orbArmed then
            GameTooltip:AddLine("|cffFF8080You do not own this Echo|r", 1, 0.5, 0.5, true)
        else
            GameTooltip:AddLine("Shift-click to link in chat", 0.4, 0.4, 0.4)
            if utils and utils.IsDevRealm and utils.IsDevRealm() then
                GameTooltip:AddLine("|cffFF6600Left-click to add stack (DEV)|r", 1, 1, 1, true)
            end
        end
    end

    GameTooltip:Show()
end

-- Forward declaration: the grid button's OnClick closure below calls this, and it is defined
-- further down next to the render that also uses it. Without the local existing first, that
-- closure would compile a GLOBAL lookup and blow up on the first right-click.
local ApplyOrbMark

local function CreateGridButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE + NAME_HEIGHT)

    -- Rounded icon look, same textures as the run echoes panel:
    -- quality disc behind a portrait-cropped icon, with a rounded quality ring.
    local anchor = CreateFrame("Frame", nil, button)
    anchor:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    anchor:SetPoint("TOP", button, "TOP", 0, -3)
    button.anchorFrame = anchor

    local iconBase = button:CreateTexture(nil, "BORDER")
    iconBase:SetSize(BUTTON_SIZE * 1.2, BUTTON_SIZE * 1.2)
    iconBase:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    button.iconBase = iconBase

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(BUTTON_SIZE * 0.8, BUTTON_SIZE * 0.8)
    icon:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    button.icon = icon

    local ring = button:CreateTexture(nil, "OVERLAY", nil, 2)
    ring:SetSize(110 * BUTTON_SIZE / 32, 110 * BUTTON_SIZE / 32)
    ring:SetPoint("CENTER", anchor, "CENTER", 0, 2)
    button.ring = ring

    -- Strong golden glow marking an echo locked into a permanent slot
    local lockedGlow = button:CreateTexture(nil, "BACKGROUND")
    lockedGlow:SetSize(BUTTON_SIZE * 1.8, BUTTON_SIZE * 1.8)
    lockedGlow:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    lockedGlow:SetTexture(ASSETS .. "perm_background_texture")
    lockedGlow:SetBlendMode("ADD")
    lockedGlow:SetVertexColor(1, 0.82, 0, 0.9)
    lockedGlow:Hide()
    button.lockedGlow = lockedGlow

    local nameText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    nameText:SetWidth(BUTTON_SIZE + 6)
    nameText:SetHeight(NAME_HEIGHT)
    nameText:SetJustifyH("CENTER")
    nameText:SetJustifyV("TOP")
    nameText:SetWordWrap(true)
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 8)
    button.nameText = nameText

    -- Elevated overlay: badges and locks must draw above the oversized ring
    -- textures of NEIGHBORING buttons (they overflow into adjacent cells and
    -- later-created siblings render on top). A higher frame level always wins.
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 5)
    overlay:SetAllPoints(button)
    button.overlayFrame = overlay

    -- Orb batch marker: literally the glow the orb bubble lights up with when a selection is
    -- armed (same texture, blend, size ratio and mauve), so "picked" reads the same wherever
    -- it shows. On the elevated overlay because neighbouring buttons' oversized ring textures
    -- overflow into this cell and would otherwise cover it.
    local orbGlow = overlay:CreateTexture(nil, "ARTWORK")
    orbGlow:SetTexture("Interface\\Cooldown\\star4")
    orbGlow:SetSize(BUTTON_SIZE * 1.9, BUTTON_SIZE * 1.9)
    orbGlow:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    orbGlow:SetBlendMode("ADD")
    orbGlow:SetVertexColor(ARMED_PICK_R, ARMED_PICK_G, ARMED_PICK_B, 0.95)
    orbGlow:Hide()
    button.orbGlow = orbGlow

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetSize(BUTTON_SIZE * 1.1, BUTTON_SIZE * 1.1)
    highlight:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    button._highlight = highlight

    -- Builder-mode selection marker: a corner check -- the old shared gold
    -- glow was too faint to read against the mostly-desaturated catalog,
    -- and gold already means "locked into a permanent slot" elsewhere.
    local selCheck = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
    selCheck:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    selCheck:SetSize(22, 22)
    selCheck:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 8, -4)
    selCheck:Hide()
    button.builderSelCheck = selCheck

    -- Count badge at the top of the icon, same look as the run echoes panel
    local badgeBg = overlay:CreateTexture(nil, "OVERLAY", nil, 5)
    badgeBg:SetSize(22, 22)
    badgeBg:SetPoint("TOP", anchor, "TOP", 0, 9)
    badgeBg:SetTexture(ASSETS .. "background_count")
    button.badgeBg = badgeBg

    local stackText = overlay:CreateFontString(nil, "OVERLAY")
    stackText:SetPoint("CENTER", badgeBg, "CENTER", 0, 0)
    stackText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    stackText:SetTextColor(1, 1, 1)
    button.stackText = stackText

    -- Owned-per-quality badges ringing the icon: same disc and font as the badge
    -- above, one per rarity you own, the number carrying the rarity color. Three
    -- slots (top / left / right) is all that fits at full size on a 46px icon,
    -- so only the three rarest owned qualities get one.
    button.qualityBadges = {}
    for i = 1, QUALITY_BADGE_SLOTS do
        local pos = QUALITY_BADGE_POS[i]
        local bg = overlay:CreateTexture(nil, "OVERLAY", nil, 5)
        bg:SetSize(QUALITY_BADGE_SIZE, QUALITY_BADGE_SIZE)
        bg:SetPoint("CENTER", anchor, "CENTER", pos.x, pos.y)
        bg:SetTexture(ASSETS .. "background_count")
        bg:Hide()

        local text = overlay:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER", bg, "CENTER", 0, 0)
        text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        text:Hide()

        button.qualityBadges[i] = { bg = bg, text = text }
    end

    local lockIcon = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
    lockIcon:SetTexture(ASSETS .. "lock")
    lockIcon:SetSize(22, 22)
    lockIcon:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 3, 3)
    button.lockIcon = lockIcon

    -- Small book badge marking tome-locked echoes in the catalog
    local tomeIcon = overlay:CreateTexture(nil, "OVERLAY", nil, 6)
    tomeIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    tomeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tomeIcon:SetSize(14, 14)
    tomeIcon:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    button.tomeIcon = tomeIcon

    -- Golden halo behind the book badge: highlights a LEARNED tome
    local tomeGlow = overlay:CreateTexture(nil, "OVERLAY", nil, 5)
    tomeGlow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    tomeGlow:SetBlendMode("ADD")
    tomeGlow:SetSize(24, 24)
    tomeGlow:SetPoint("CENTER", tomeIcon, "CENTER", 0, 0)
    tomeGlow:SetVertexColor(1, 0.82, 0)
    tomeGlow:Hide()
    button.tomeGlow = tomeGlow


    button:SetScript("OnEnter", ShowEchoTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self, mouseButton)
        -- Orb of Lost Memories: while an orb is armed, left-clicking an echo you OWN spends it
        -- on that echo. Checked before everything else so no other binding can steal the click.
        -- ownedStacks > 0 keeps it to echoes actually held; the server re-validates ownership,
        -- lock state and the charge anyway.
        local orb = ProjectEbonhold.OrbService
        -- orbSpellId is the LOWEST rarity of this echo the player holds unlocked - the copy the
        -- orb should eat. It only exists on the grouped My Echoes cards; everywhere else a card
        -- is already a single rarity, so spellId is the target.
        local orbTarget = self.orbSpellId or self.spellId
        if orb and orb.IsArmed() and orbTarget and (self.ownedStacks or 0) > 0 then
            -- Permanent echoes are off limits, both for the instant spend and for the batch:
            -- the server refuses them, so the click is answered here instead of round-tripping
            -- into a silent rejection. A grouped card whose stacks are not ALL permanent still
            -- has a legal target (orbSpellId), so only the no-target case is refused.
            if not self.orbSpellId and self.isLocked then
                UIErrorsFrame:AddMessage("Permanent Echoes cannot be forgotten.", 1, 0.2, 0.2)
                return
            end
            if mouseButton == "LeftButton" then
                orb.SpendOn(orbTarget)
                return
            elseif mouseButton == "RightButton" then
                -- Queue it instead of spending: the batch is confirmed from the alert box.
                -- The marker is flipped on this button directly rather than through a full
                -- journal refresh - right-clicking a dozen echoes should not re-render the
                -- whole grid a dozen times.
                orb.ToggleMark(orbTarget)
                ApplyOrbMark(self)      -- recolour just this ring, not the whole grid
                ShowEchoTooltip(self)   -- redraw the hint under the cursor
                return
            end
        end

        -- Loadout builder: the catalog grid becomes a picker while a draft is open
        if builderDraft and currentTab == TAB_ALL and self.spellId and self.perkData
            and not IsShiftKeyDown() then
            local entries = builderDraft.entries
            local e = entries[self.spellId]
            if mouseButton == "LeftButton" then
                if DraftTotalStacks() >= MAX_RUN_ECHOES then
                    UIErrorsFrame:AddMessage(
                        string.format("A wishlist cannot exceed %d echoes.", MAX_RUN_ECHOES), 1, 0.1, 0.1)
                    return
                end
                if e then
                    e.stacks = math.min(e.stacks + 1, self.perkData.maxStack or 1)
                else
                    entries[self.spellId] = { quality = self.perkData.quality or 0, stacks = 1 }
                end
            elseif mouseButton == "RightButton" and e then
                e.stacks = e.stacks - 1
                if e.stacks <= 0 then entries[self.spellId] = nil end
            end
            Refresh()
            return
        end
        if mouseButton == "RightButton" then
            TryToggleTome(self)
            return
        end
        if mouseButton ~= "LeftButton" then return end
        if IsShiftKeyDown() and self.spellId and self.perkData then
            LinkEchoInChat(self.spellId, self.perkData.quality)
        elseif lockModeActive and self.spellId then
            Journal.TryLockEcho(self)
        elseif utils and utils.IsDevRealm and utils.IsDevRealm() and self.spellId then
            if ProjectEbonhold.sendToServer and ProjectEbonhold.CS then
                ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_DEV_ADD_PERK_STACK, tostring(self.spellId))
            end
        end
    end)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    return button
end

local function HideQualityBadges(button)
    if not button.qualityBadges then return end
    for i = 1, QUALITY_BADGE_SLOTS do
        button.qualityBadges[i].bg:Hide()
        button.qualityBadges[i].text:Hide()
    end
end

-- Gold ring = queued for the orb batch. The grid already draws a quality-coloured border
-- around every echo, so a second ring on top was just clutter: this recolours the one that is
-- already there. Desaturating first strips the quality hue, otherwise gold multiplied onto a
-- blue or purple border lands on some muddy in-between colour.
-- The unmarked branch restores what the render decided (see button._ringDesat/_ringAlpha)
-- rather than assuming a default, so dimmed and empty slots come back correct.
function ApplyOrbMark(button)
    if not button or not button.ring then return end

    local orb = ProjectEbonhold.OrbService
    -- Marked by the id the click actually queued (the lowest rarity held), not the one the card
    -- displays - otherwise the ring never lights up on a grouped card.
    local orbTarget = button.orbSpellId or button.spellId
    local isMarked = orbTarget and orb and orb.IsArmed and orb.IsArmed()
        and orb.IsMarked and orb.IsMarked(orbTarget)

    if isMarked then
        button.ring:SetDesaturated(true)
        -- Mauve, not the old gold: gold already means "locked into a permanent slot" two
        -- panels over, and the mark now carries the orb's own glow underneath it.
        button.ring:SetVertexColor(ARMED_PICK_R, ARMED_PICK_G, ARMED_PICK_B)
        button.ring:SetAlpha(1)
        if button.orbGlow then button.orbGlow:Show() end
    else
        button.ring:SetDesaturated(button._ringDesat and true or false)
        button.ring:SetVertexColor(1, 1, 1)
        button.ring:SetAlpha(button._ringAlpha or 1)
        if button.orbGlow then button.orbGlow:Hide() end
    end
end

local function UpdateGridButton(button, item)
    if item.empty then
        -- Placeholder for a pick not yet made this run
        button.spellId = nil
        button.perkData = nil
        button.counts = nil
        button.ownedStacks = 0
        button.isLocked = nil
        button.orbSpellId = nil
        button.orbQuality = nil
        button.timesObtained = nil
        button.tomeKnown = nil
        button.buildMissing = nil
        button.buildTarget = nil
        button.buildLocked = nil
        button.isEmptySlot = true
        button.icon:Hide()
        button.iconBase:SetTexture(ASSETS .. "perk_quality_0")
        button.iconBase:SetDesaturated(true)
        button.iconBase:SetAlpha(0.35)
        button.ring:SetTexture(ASSETS .. "perk_border_quality_0")
        button.ring:SetDesaturated(true)
        button.ring:SetAlpha(0.35)
        button._ringDesat = true
        button._ringAlpha = 0.35
        ApplyOrbMark(button)
        button.nameText:SetText("")
        button.stackText:Hide()
        button.badgeBg:Hide()
        HideQualityBadges(button)
        button.lockIcon:Hide()
        button.tomeIcon:Hide()
        button.tomeGlow:Hide()
        button.lockedGlow:Hide()
        if button.tomeSwirl then button.tomeSwirl:Hide() end
        return
    end

    local spellId = item.spellId
    local data = item.data

    button.spellId = spellId
    button.perkData = data
    button.counts = item.counts
    button.ownedStacks = item.stacks or 0
    button.isLocked = item.locked
    -- Only the grouped "My Echoes" cards carry these; the catalog lists every rarity as its own
    -- card, where button.spellId already IS the exact variant to forget (see the OnClick fallback).
    button.orbSpellId = item.orbSpellId
    button.orbQuality = item.orbQuality
    button.timesObtained = item.timesObtained
    button.tomeKnown = item.tomeKnown
    button.isEmptySlot = nil
    button.buildMissing = item.buildMissing
    button.buildTarget = item.buildTarget
    button.buildLocked = item.buildLocked

    local spellName, _, spellIcon = GetSpellInfo(spellId)
    button.icon:Show()
    spellIcon = spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
    -- SetPortraitToTexture re-crops the texture; skip it when nothing changed
    if button._portraitTex ~= spellIcon then
        button._portraitTex = spellIcon
        SetPortraitToTexture(button.icon, spellIcon)
    end

    local color = qualityColors[data.quality] or qualityColors[0]
    local borderIdx = math.min(data.quality or 0, 3) -- rounded assets exist for 0-3
    button.iconBase:SetTexture(ASSETS .. "perk_quality_" .. borderIdx)
    button.iconBase:SetAlpha(1)
    button.ring:SetTexture(ASSETS .. "perk_border_quality_" .. borderIdx)
    button.ring:SetAlpha(1)
    button.nameText:SetText(spellName or "Unknown")

    if item.dimmed then
        button.icon:SetDesaturated(true)
        button.iconBase:SetDesaturated(true)
        button.ring:SetDesaturated(true)
        button.icon:SetVertexColor(0.6, 0.6, 0.6)
        button.nameText:SetTextColor(0.5, 0.5, 0.5)
    else
        button.icon:SetDesaturated(false)
        button.iconBase:SetDesaturated(false)
        button.ring:SetDesaturated(false)
        button.icon:SetVertexColor(1, 1, 1)
        button.nameText:SetTextColor(color.r, color.g, color.b)
    end
    -- What the ring would look like WITHOUT an orb mark. ApplyOrbMark paints over these and
    -- needs them to put the ring back exactly as the render left it.
    button._ringDesat = item.dimmed and true or false
    button._ringAlpha = 1

    ApplyOrbMark(button)

    -- Counts: on My Echoes every owned rarity gets its own badge around the icon
    -- (rarest first, three slots), so the single badge stays hidden there. The
    -- other tabs have no per-quality split and keep the plain stack count.
    local badgeCount, badgeColor
    HideQualityBadges(button)
    if item.counts then
        local slot = 0
        for q = 4, 0, -1 do
            local count = item.counts[q] or 0
            if count > 0 and slot < QUALITY_BADGE_SLOTS then
                slot = slot + 1
                local qc = qualityColors[q]
                local badge = button.qualityBadges[slot]
                badge.text:SetText(tostring(count))
                badge.text:SetTextColor(qc.r, qc.g, qc.b)
                badge.bg:Show()
                badge.text:Show()
            end
        end
    elseif (item.stacks or 0) > 0 then
        badgeCount = item.stacks
        badgeColor = color
    end
    if badgeCount then
        button.stackText:SetText(tostring(badgeCount))
        button.stackText:SetTextColor(badgeColor.r, badgeColor.g, badgeColor.b)
        button.stackText:Show()
        button.badgeBg:Show()
    elseif item.buildMissing then
        -- Ghost from the active build: show the target stack count in grey
        button.stackText:SetText(tostring(item.buildTarget or 1))
        button.stackText:SetTextColor(0.6, 0.6, 0.6)
        button.stackText:Show()
        button.badgeBg:Show()
    else
        button.stackText:Hide()
        button.badgeBg:Hide()
    end

    if item.locked then
        button.lockIcon:SetAlpha(1)
        button.lockIcon:Show()
        button.lockedGlow:Show()
        button.nameText:SetTextColor(1, 0.82, 0) -- gold name for permanent echoes
    elseif item.buildMissing and item.buildLocked then
        -- The build stores this echo as locked: show a faded lock on the ghost
        button.lockIcon:SetAlpha(0.5)
        button.lockIcon:Show()
        button.lockedGlow:Hide()
    else
        button.lockIcon:SetAlpha(1)
        button.lockIcon:Hide()
        button.lockedGlow:Hide()
    end

    if item.isTome then
        -- Grey book = tome not learned yet. Keyed off tomeKnown rather than
        -- dimmed: on My Echoes, build ghosts are dimmed for "not obtained this
        -- run", which says nothing about whether the tome itself is known.
        button.tomeIcon:SetDesaturated(not item.tomeKnown)
        button.tomeIcon:Show()
    else
        button.tomeIcon:Hide()
    end
    -- The old golden halo on the book badge is retired: the rotating swirl
    -- below is the enabled indicator
    button.tomeGlow:Hide()

    -- Rotating swirl marking an ACTIVATED tome echo (learned + enabled): its
    -- echo can appear in this run's draws. Disabled tomes show no swirl.
    if item.tomeKnown and not item.tomeDisabled then
        if not button.tomeSwirl then
            local host = button.anchorFrame or button
            local swirl = button:CreateTexture(nil, "BACKGROUND", nil, 2)
            swirl:SetTexture("Interface\\Cooldown\\star4")
            swirl:SetBlendMode("ADD")
            swirl:SetVertexColor(0.3, 0.8, 1, 0.6)
            swirl:SetSize(BUTTON_SIZE * 1.7, BUTTON_SIZE * 1.7)
            swirl:SetPoint("CENTER", host, "CENTER", 0, 0)
            local anim = swirl:CreateAnimationGroup()
            anim:SetLooping("REPEAT")
            local rot = anim:CreateAnimation("Rotation")
            rot:SetDuration(8)
            rot:SetDegrees(360)
            rot:SetOrigin("CENTER", 0, 0)
            anim:Play()
            button.tomeSwirl = swirl
        end
        button.tomeSwirl:Show()
    elseif button.tomeSwirl then
        button.tomeSwirl:Hide()
    end
    button.tomeDisabled = item.tomeDisabled

    -- Loadout builder: corner check + green stack count on echoes picked
    -- for the draft. (The gold lockedGlow is deliberately NOT reused here:
    -- gold means "locked into a permanent slot" everywhere else.)
    button.builderSelCheck:Hide()
    if builderDraft and currentTab == TAB_ALL then
        local e = builderDraft.entries[spellId]
        if e then
            button.builderSelCheck:Show()
            button.stackText:SetText(tostring(e.stacks))
            button.stackText:SetTextColor(0.1, 1, 0.1)
            button.stackText:Show()
            button.badgeBg:Show()
        end
    end
end

-- ── My Run panel (merged Echoes tab's left column) ──────────────────────────
-- Bounded by MAX_RUN_ECHOES distinct picks at most (usually far fewer once
-- grouped by name), so unlike the full catalog this never needs virtualizing
-- -- every button is just materialized directly, reusing the same
-- CreateGridButton/UpdateGridButton as the catalog so hover tooltips, the
-- lock-mode click-to-lock, and right-click behavior all stay identical.
-- Near-zero left margin (unlike the catalog's GRID_MARGIN_L=10): this panel
-- is narrow enough that 10px read as wasted padding before the first icon.
local MYRUN_MARGIN_L = 2

local function UpdateMyRunPanel(items)
    if not myRunScrollChild then return end
    -- No SetShown on this 3.3.5 client (5.x API) -- explicit Show/Hide.
    if myRunEmptyState then
        if #items == 0 then myRunEmptyState:Show() else myRunEmptyState:Hide() end
    end
    local pitch = BUTTON_SIZE + NAME_HEIGHT + BUTTON_SPACING
    -- Fixed, shared with the catalog grid (see ECHO_GRID_HSTEP) so column
    -- spacing always matches between the two panels.
    local hstep = ECHO_GRID_HSTEP

    for i, item in ipairs(items) do
        local button = myRunButtons[i]
        if not button then
            button = CreateGridButton(myRunScrollChild)
            myRunButtons[i] = button
        end
        UpdateGridButton(button, item)
        local row = math.floor((i - 1) / MYRUN_COLS)
        local col = (i - 1) % MYRUN_COLS
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", myRunScrollChild, "TOPLEFT",
            MYRUN_MARGIN_L + col * hstep, -4 - row * pitch)
        button:Show()
    end
    for i = #items + 1, #myRunButtons do
        myRunButtons[i]:Hide()
    end

    local numRows = math.ceil(#items / MYRUN_COLS)
    local contentH = 8 + numRows * pitch
    myRunScrollChild:SetHeight(math.max(contentH, myRunScrollFrame:GetHeight() or 1))
end

-- ── Virtualized grid ─────────────────────────────────────────────────────────
-- Materializing one live button per catalog entry (hundreds of frames, each
-- with ~10 regions) made scrolling stutter. Instead, only the rows inside the
-- viewport (plus one buffer row on each side) exist; scrolling rebinds this
-- small pool onto different items at their virtual positions.
local currentItems = {}
local gridItemCount = -1
local gridWindowFirst, gridWindowLast = -1, -1

local function UpdateVisibleGrid()
    if not scrollFrame then return end
    local pitch = BUTTON_SIZE + NAME_HEIGHT + BUTTON_SPACING
    local offset = scrollFrame:GetVerticalScroll() or 0
    local viewH = scrollFrame:GetHeight() or 300

    local firstRow = math.max(0, math.floor(offset / pitch) - 1)
    local lastRow = math.floor((offset + viewH) / pitch) + 1
    local firstIdx = firstRow * PERKS_PER_ROW + 1
    local lastIdx = math.min(#currentItems, (lastRow + 1) * PERKS_PER_ROW)

    -- Rebinding ~50 buttons is cheap, but skip it entirely while the visible
    -- window has not moved (the thumb drag fires every frame)
    if gridWindowFirst == firstIdx and gridWindowLast == lastIdx then return end
    gridWindowFirst, gridWindowLast = firstIdx, lastIdx

    -- Fixed, shared with the My Run grid (ECHO_GRID_HSTEP) so column spacing
    -- always matches between the two panels, instead of each justifying to
    -- fill its own (different) width.
    local hstep = ECHO_GRID_HSTEP

    local b = 0
    for i = firstIdx, lastIdx do
        b = b + 1
        local button = gridButtons[b]
        if not button then
            button = CreateGridButton(scrollChild)
            gridButtons[b] = button
        end
        UpdateGridButton(button, currentItems[i])
        local row = math.floor((i - 1) / PERKS_PER_ROW)
        local col = (i - 1) % PERKS_PER_ROW
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
            GRID_MARGIN_L + col * hstep,
            -10 - row * pitch)
        button:Show()
    end
    for j = b + 1, #gridButtons do gridButtons[j]:Hide() end
end

local function UpdateGrid(items)
    currentItems = items or {}
    local pitch = BUTTON_SIZE + NAME_HEIGHT + BUTTON_SPACING
    local numRows = math.ceil(#currentItems / PERKS_PER_ROW)
    scrollChild:SetHeight(math.max(numRows * pitch + 25, 300))

    -- Keep the scroll position when only the contents changed (builder clicks,
    -- data refreshes); jump back to the top when the list itself changed.
    if gridItemCount ~= #currentItems then
        scrollFrame:SetVerticalScroll(0)
    end
    gridItemCount = #currentItems

    gridWindowFirst, gridWindowLast = -1, -1 -- force a rebind
    UpdateVisibleGrid()
end

-- ── Loadouts tab ─────────────────────────────────────────────────────────────
-- Row layout: name line on top, echo icons in the middle, action buttons along
-- the bottom-right, delete cross pinned to the top-right corner. A +/- toggle
-- expands the row to show EVERY echo (wrapped grid) instead of the first line.
local ROW_HEIGHT, ROW_SPACING = 86, 10
local MAX_ROW_ICONS = 14   -- icons on the single collapsed line
local ICONS_PER_LINE = 14  -- expanded view wraps at the row's full width
local ROW_ICON_SIZE = 24   -- round echo icons inside build rows
local ROW_ICON_PITCH = 26  -- horizontal/vertical spacing between them
local expandedLoadouts = {} -- ["m:<index>"] / ["c:<index>"] = true

-- Custom buttons ship with GameFontNormal (12px): drop 1px so labels breathe
local function ShrinkButtonFont(btn)
    if btn.text then
        local font, size, flags = btn.text:GetFont()
        btn.text:SetFont(font, (size or 12) - 1, flags)
    end
    return btn
end

-- The active loadout is stored as a copy, so match it by name + class
local function IsActiveLoadout(loadout)
    local svc = GetService()
    local active = svc and svc.GetActiveEchoLoadout and svc.GetActiveEchoLoadout()
    return active ~= nil and loadout ~= nil
        and active.name == loadout.name and active.class == loadout.class
end

-- ── Server build slots ───────────────────────────────────────────────────────
-- Server-verified snapshots of the player's own build shown ABOVE the local
-- library in "My Loadouts". Snapshots are a level-80-only feature: save one at
-- max level, then swap between them freely at 80. They do nothing while you
-- level - the 1-80 climb is fully random by design, and a snapshot is the
-- trophy the run hands you, not a shortcut back to a build.
-- Saving snapshots the CURRENT build server-side (never an upload).
local pendingServerSlot = nil -- slot number a popup is acting on
local serverBuildSlotsRequested = false -- render-path request fired once

local function GetPlayerClassToken()
    local _, token = UnitClass("player")
    return token
end

-- Progress of a build vs the CURRENT run's echoes. Returns entryDone(e, verified):
-- true when the run already holds the entry's target stacks. Verified builds
-- match exact spell ids (what the level-80 swap applies); designed/wish-list ones
-- match any owned quality variant by name, like the draw highlight does.
local function BuildProgressChecker()
    local svc = GetService()
    local bySpell, byName = {}, {}
    local function add(spellId, stack)
        bySpell[spellId] = (bySpell[spellId] or 0) + stack
        local nm = GetSpellInfo(spellId)
        if nm then byName[nm] = (byName[nm] or 0) + stack end
    end
    local granted = svc and svc.GetGrantedPerks and svc.GetGrantedPerks() or {}
    for _, instances in pairs(granted) do
        for _, inst in ipairs(instances) do add(inst.spellId, inst.stack or 1) end
    end
    local lockedPerks = svc and svc.GetLockedPerks and svc.GetLockedPerks() or {}
    for _, lp in ipairs(lockedPerks) do add(lp.spellId, lp.stack or 1) end

    return function(e, verified)
        local target = e.stacks or 1
        if verified == false then
            local nm = GetSpellInfo(e.spellId)
            return ((nm and byName[nm]) or 0) >= target
        end
        return (bySpell[e.spellId] or 0) >= target
    end
end

-- Name of the active build when it is a SNAPSHOT (nil for none/designed): a
-- snapshot is the thing you give up by switching, so callers warn about it.
local function ActiveSnapshotName()
    local svc = GetService()
    local activeSlot = svc and svc.GetServerActiveSlot and svc.GetServerActiveSlot() or 0
    local slots = svc and svc.GetServerBuildSlots and svc.GetServerBuildSlots()
    local active = activeSlot > 0 and slots and slots[activeSlot] or nil
    if active and active.verified then
        return (active.name ~= "" and active.name) or ("Build " .. activeSlot)
    end
    return nil
end

-- What clicking/pressing Activate on a server row should do at this level.
-- Returns "none" when the click has no meaning here, so the caller stays silent.
local function ServerSlotClickAction(slot, verified)
    local svc = GetService()
    local level = UnitLevel("player") or 1
    -- A build is never turned off, only replaced: clicking the active one does
    -- nothing. Activating a different build is the only way to move off it.
    if svc.GetServerActiveSlot() == slot then return "none" end
    -- Designed builds ("in progress") only drive highlights / auto-pick - they
    -- never change what the game offers - so they stay usable at any level while
    -- leveling. At 80 there are no draws left to guide, so activating one would
    -- do nothing. Snapshots are level-80 only: below 80 they have no effect at all.
    if verified == false then
        if level >= 80 then return "designed80" end
        return "activate"
    end
    if level == 80 then return "switch" end
    return "level"
end

-- Lowest build slot this account can still fill, or nil when they are all
-- taken. Mirrors the server's own pick (PerkLoadoutHandler::FindFreeBuildSlot)
-- so a recovery that has nowhere to land is refused before it is sent.
local function FirstFreeBuildSlot()
    local svc = GetService()
    local slots = svc and svc.GetServerBuildSlots and svc.GetServerBuildSlots()
    if not slots then return nil end
    local unlocked = (svc.GetServerUnlockedSlots and svc.GetServerUnlockedSlots())
        or (svc.GetServerMaxSlots and svc.GetServerMaxSlots()) or 5
    for slot = 1, unlocked do
        if not slots[slot] then return slot end
    end
    return nil
end

-- Why Recover cannot be used right now, or nil when it can. Same gates as the
-- server's HandleRecover, so the button never offers a call that only fails.
local function RecoverBlockedReason()
    if not FirstFreeBuildSlot() then
        return "You have no free build slot. Free one up first."
    end
    return nil
end

local function GetRowIcon(row, k)
    local ib = row.icons[k]
    if ib then return ib end
    -- Round icon look, same recipe as the My Echoes grid: quality disc behind
    -- a portrait-cropped icon, with the rounded quality ring on top
    ib = CreateFrame("Button", nil, row)
    ib:SetSize(ROW_ICON_SIZE, ROW_ICON_SIZE)
    ib.base = ib:CreateTexture(nil, "BORDER")
    ib.base:SetSize(ROW_ICON_SIZE + 2, ROW_ICON_SIZE + 2)
    ib.base:SetPoint("CENTER", ib, "CENTER", 0, 0)
    ib.tex = ib:CreateTexture(nil, "ARTWORK")
    ib.tex:SetSize(ROW_ICON_SIZE - 4, ROW_ICON_SIZE - 4)
    ib.tex:SetPoint("CENTER", ib, "CENTER", 0, 0)
    ib.ring = ib:CreateTexture(nil, "OVERLAY")
    ib.ring:SetSize(110 * ROW_ICON_SIZE / 32, 110 * ROW_ICON_SIZE / 32) -- ring asset carries large transparent padding
    ib.ring:SetPoint("CENTER", ib, "CENTER", 0, 1)
    -- Small lock badge: marks echoes stored as LOCKED in a server build slot
    ib.lockTex = ib:CreateTexture(nil, "OVERLAY")
    ib.lockTex:SetTexture(ASSETS .. "lock")
    ib.lockTex:SetSize(10, 10)
    ib.lockTex:SetPoint("TOPRIGHT", ib, "TOPRIGHT", 2, 2)
    ib.lockTex:Hide()
    ib:SetScript("OnEnter", function(self)
        if not self.spellId then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local sName = GetSpellInfo(self.spellId)
        local qc = qualityColors[self.quality or 0] or qualityColors[0]
        GameTooltip:SetText(sName or ("Spell " .. tostring(self.spellId)), qc.r, qc.g, qc.b)
        if (self.stacks or 1) > 1 then
            GameTooltip:AddLine("Stacks: " .. self.stacks, 0.7, 0.7, 0.7)
        end
        if self.locked then
            GameTooltip:AddLine("Locked echo (permanent between runs)", 1, 0.82, 0)
        end
        if self.notObtained then
            GameTooltip:AddLine("Not obtained this run yet", 1, 0.4, 0.4)
        end
        if utils and utils.GetSpellDescription then
            GameTooltip:AddLine(utils.GetSpellDescription(self.spellId, 4000, self.stacks or 1), 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    ib:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.icons[k] = ib
    return ib
end

-- "Just created" pulse, driven by OnUpdate rather than an AnimationGroup: the
-- group has to live on a Frame, and animating the row itself would fade the
-- whole row (buttons and icons included) instead of just the golden wash.
local FLASH_PULSES, FLASH_PERIOD, FLASH_PEAK = 3, 0.55, 0.55
local FLASH_TOTAL = FLASH_PULSES * FLASH_PERIOD

-- The flash outlives any single render: saving fires several refreshes in a row
-- (result packet, slot data, active slot), and each one rebinds the pooled rows.
-- Keeping slot + elapsed at module scope lets the pulse resume on the new row
-- instead of being cut off a frame after it starts.
local flashSlot, flashElapsed

local function StopRowFlash(row)
    if not row.newFlash then return end
    row:SetScript("OnUpdate", nil)
    row.newFlash:SetAlpha(0)
    row.newFlash:Hide()
end

local function StartRowFlash(row)
    if not row.newFlash then return end
    row.newFlash:SetAlpha(0)
    row.newFlash:Show()
    row:SetScript("OnUpdate", function(self, elapsed)
        if ProjectEbonhold_IsClosing then StopRowFlash(self) return end
        flashElapsed = (flashElapsed or 0) + elapsed
        if flashElapsed >= FLASH_TOTAL then
            flashSlot, flashElapsed = nil, nil
            StopRowFlash(self)
            return
        end
        -- One 0..1..0 hump per period, tapering so later pulses are softer
        local phase = (flashElapsed % FLASH_PERIOD) / FLASH_PERIOD
        local hump = math.sin(phase * math.pi)
        self.newFlash:SetAlpha(hump * FLASH_PEAK * (1 - flashElapsed / FLASH_TOTAL))
    end)
end

-- Shared "..." context menu for loadout/build rows. Collapses the per-row
-- action buttons (Overwrite/Design, Rename, Share, Export, Save…) into a single
-- kebab so the row stays uncluttered. Menu items simply fire the existing
-- (now hidden) button handlers, so there is one source of truth per action.
local loadoutMenuFrame
local function RunRowBtn(btn)
    local h = btn and btn:GetScript("OnClick")
    if h then h(btn) end
end
local function ShowLoadoutMenu(row)
    if not row or not row.loadout then return end
    if not loadoutMenuFrame then
        loadoutMenuFrame = CreateFrame("Frame", "ProjectEbonholdLoadoutMenu", UIParent, "UIDropDownMenuTemplate")
    end
    local items = {}
    local title = (row.loadout.name and row.loadout.name ~= "" and row.loadout.name) or "Build"
    title = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") -- drop inline color codes
    table.insert(items, { text = title, isTitle = true, notCheckable = true })

    -- A greyed entry mirrors a disabled button: same source of truth, so an
    -- action can never look available in the menu while its button is off.
    local function add(text, btn)
        local off = btn and btn.IsEnabled and not btn:IsEnabled()
        table.insert(items, {
            text = text, notCheckable = true, disabled = off or nil,
            func = function() RunRowBtn(btn) end,
        })
    end

    if row.serverSlot then
        if row.serverFilled then
            if row.serverToRecover then
                add("Recover", row.recoverBtn)
            end
            if row.serverVerified == false then
                add("Design", row.designBtn)
            else
                add("Overwrite", row.saveBuildBtn)
            end
            add("Rename", row.renameBuildBtn)
            add("Share", row.shareBtn)
            add("Export", row.exportBtn)
            add("Delete", row.deleteBtn)
        end
    elseif row.isMine then
        add("Edit", row.editBtn)
        add("Share", row.shareBtn)
        add("Export", row.exportBtn)
        add("Delete", row.deleteBtn)
    else
        add("Save to my builds", row.saveBtn)
        add("Export", row.exportBtn)
        if row.loadout.author == UnitName("player") then
            add("Unpublish", row.deleteBtn)
        end
    end
    table.insert(items, { text = CANCEL or "Cancel", notCheckable = true })

    EasyMenu(items, loadoutMenuFrame, row.menuBtn or "cursor", 0, 0, "MENU")
end

local function GetLoadoutRow(i)
    local row = loadoutRows[i]
    if row then return row end

    row = CreateFrame("Frame", nil, scrollChild)
    row:SetSize(402, ROW_HEIGHT)
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    row:SetBackdropColor(0, 0, 0, 0.45)
    row:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Active-build highlight: a warm golden wash (lit-from-below gradient) plus
    -- a left accent stripe. Both stay hidden until UpdateLoadoutRow flags the
    -- row as the one currently being played, so the active build reads at a
    -- glance against the dimmed inactive slots.
    row.activeBg = row:CreateTexture(nil, "BORDER")
    row.activeBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.activeBg:SetPoint("TOPLEFT", 4, -4)
    row.activeBg:SetPoint("BOTTOMRIGHT", -4, 4)
    row.activeBg:SetGradientAlpha("VERTICAL", 0.85, 0.65, 0.12, 0.32, 0.30, 0.22, 0.02, 0.05)
    row.activeBg:Hide()

    row.activeStripe = row:CreateTexture(nil, "BORDER")
    row.activeStripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.activeStripe:SetPoint("TOPLEFT", 4, -4)
    row.activeStripe:SetPoint("BOTTOMLEFT", 4, 4)
    row.activeStripe:SetWidth(3)
    row.activeStripe:SetVertexColor(1, 0.82, 0, 0.9)
    row.activeStripe:Hide()

    -- "Just created" flash: a golden wash that pulses twice and fades out, so a
    -- freshly saved build is easy to spot in a list of similar rows. Purely
    -- transient - it plays once and hides itself, leaving the row's own look.
    row.newFlash = row:CreateTexture(nil, "OVERLAY")
    row.newFlash:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.newFlash:SetPoint("TOPLEFT", 4, -4)
    row.newFlash:SetPoint("BOTTOMRIGHT", -4, 4)
    row.newFlash:SetBlendMode("ADD")
    row.newFlash:SetVertexColor(1, 0.82, 0.2)
    row.newFlash:SetAlpha(0)
    row.newFlash:Hide()


    -- Empty-slot look: a faint cool wash + a blue left accent stripe so an
    -- unfilled slot reads as an intentional "available to fill" placeholder
    -- rather than a dead box. Muted so it never competes with the active build.
    row.emptyBg = row:CreateTexture(nil, "BORDER")
    row.emptyBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.emptyBg:SetPoint("TOPLEFT", 4, -4)
    row.emptyBg:SetPoint("BOTTOMRIGHT", -4, 4)
    row.emptyBg:SetGradientAlpha("VERTICAL", 0.20, 0.30, 0.45, 0.14, 0.06, 0.09, 0.14, 0.03)
    row.emptyBg:Hide()

    -- Grey accent stripe: this build exists but cannot be activated right now
    -- (wrong level for a snapshot, level 80 for a design). Same shape as the
    -- gold/blue stripes so the left edge always says what the row can do.
    row.disabledStripe = row:CreateTexture(nil, "BORDER")
    row.disabledStripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.disabledStripe:SetPoint("TOPLEFT", 4, -4)
    row.disabledStripe:SetPoint("BOTTOMLEFT", 4, 4)
    row.disabledStripe:SetWidth(3)
    row.disabledStripe:SetVertexColor(0.5, 0.5, 0.5, 0.9)
    row.disabledStripe:Hide()

    row.emptyStripe = row:CreateTexture(nil, "BORDER")
    row.emptyStripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.emptyStripe:SetPoint("TOPLEFT", 4, -4)
    row.emptyStripe:SetPoint("BOTTOMLEFT", 4, 4)
    row.emptyStripe:SetWidth(3)
    row.emptyStripe:SetVertexColor(0.35, 0.55, 0.85, 0.7)
    row.emptyStripe:Hide()

    -- Clicking the row (outside its buttons) picks it as the ACTIVE loadout:
    -- its echoes get highlighted whenever a perk choice is offered.
    -- Server build-slot rows activate the slot instead (a full swap, level 80
    -- only). A build is only ever replaced, never turned off.
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or not self.loadout then return end
        if self.serverSlot then
            if not self.serverFilled then return end
            local action = ServerSlotClickAction(self.serverSlot, self.serverVerified)
            -- "none": the click is simply inert here, with no popup and no error
            if action == "none" then return end
            pendingServerSlot = self.serverSlot
            if action == "designed80" then
                -- Designed content only guides draws while leveling, and there
                -- are none left at 80: activating it here would change nothing.
                pendingServerSlot = nil
                UIErrorsFrame:AddMessage(
                    "Designed builds only guide your draws while leveling, and there is nothing left to draw at level 80. Only snapshots can be applied here.",
                    1, 0.2, 0.2)
            elseif action == "switch" then
                StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_SWITCH", self.loadout.name or "")
            elseif action == "activate" then
                if self.serverVerified == false then
                    -- Only designed builds reach "activate": snapshots are level-80
                    -- only (see ServerSlotClickAction). Switching to a design is the
                    -- only way to drop a snapshot mid-run, so the warning lives here.
                    local level = UnitLevel("player") or 1
                    local active = (level < 80) and ActiveSnapshotName() or nil
                    local warn = ""
                    if active then
                        warn = string.format(
                            "\n\n|cffff2020WARNING:|r |cffff6060this replaces your saved build |r|cffffd700%s|r|cffff6060. A saved build can only be turned back on at level 80, so you will be without one until then.|r",
                            active)
                    end
                    StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_ACTIVATE_DESIGNED",
                        self.loadout.name or "", warn)
                end
            else
                pendingServerSlot = nil
                UIErrorsFrame:AddMessage("Saved builds can only be activated at level 80. While you level, every echo you are offered is drawn at random.", 1, 0.2, 0.2)
            end
            return
        end
        -- Community builds are not activatable directly: copy one into your own
        -- builds first (the "..." menu -> Save to my builds), then activate it
        -- from My Builds. (An already-active one can still be cleared, e.g. one
        -- activated before this restriction existed.)
        if not self.isMine and not IsActiveLoadout(self.loadout) then
            UIErrorsFrame:AddMessage(
                "Save this community build to your own builds first, then activate it from My Builds.",
                1, 0.82, 0)
            return
        end
        pendingLoadout = { loadout = self.loadout }
        if IsActiveLoadout(self.loadout) then
            StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_UNUSE", self.loadout.name or "")
        else
            StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_USE", self.loadout.name or "")
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.loadout then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.loadout.name or "Loadout", 1, 0.82, 0)
        if self.serverSlot then
            if self.serverLockedCost then
                GameTooltip:AddLine("Locked build slot.\nThe unlock applies to every character on your account.",
                    1, 1, 1, true)
                GameTooltip:AddLine(string.format("Unlock it for |cffffd700%s gold|r.",
                    tostring(self.serverLockedCost)), 0.5, 0.5, 0.5, true)
            elseif not self.serverFilled then
                GameTooltip:AddLine(
                    "Empty loadout slot.\nIt holds a snapshot of the echoes you finished a run with.",
                    1, 1, 1, true)
                GameTooltip:AddLine(
                    "At |cffffd700level 80|r, use |cffffd700Save Build|r to fill it with your current echoes (stacks and locks included).",
                    0.5, 0.5, 0.5, true)
            else
                local svc = GetService()
                local isDesigned = self.serverVerified == false
                local isEnabled = svc.GetServerActiveSlot() == self.serverSlot
                -- State first: whether this build is the one being played is the
                -- thing the row's colours encode, spelled out here
                if isEnabled then
                    GameTooltip:AddLine("Enabled", 0.25, 1, 0.25)
                else
                    GameTooltip:AddLine("Disabled", 0.5, 0.5, 0.5)
                end
                if self.serverToRecover then
                    GameTooltip:AddLine(
                        "|cffffd700Recoverable.|r This wishlist stands for a build you really played. |cffffd700Recover|r moves it back into a free build slot, as a saved build you can wear again at level 80.",
                        1, 1, 1, true)
                end
                -- What the build DOES reads the same either way: only the action
                -- hint at the end changes with the state.
                if isDesigned then
                    if (UnitLevel("player") or 1) >= 80 then
                        GameTooltip:AddLine(
                            "|cffff6060Cannot be activated at level 80.|r\nIt works by guiding your draws, and there are none left. Only snapshots can replace your echoes here.",
                            1, 1, 1, true)
                    else
                        GameTooltip:AddLine(
                            "While leveling, its echoes are |cffffd700highlighted|r in your draws, and picked for you if that option is on.\nHighlights only: it never changes what you are offered, and cannot replace your echoes at level 80.",
                            1, 1, 1, true)
                        GameTooltip:AddLine(isEnabled and "Activate another build to swap to it."
                            or "Click to activate this build.", 0.5, 0.5, 0.5, true)
                    end
                else
                    if (UnitLevel("player") or 1) < 80 then
                        GameTooltip:AddLine(
                            "|cffff6060Saved builds only work at level 80.|r\nWhile you level, every echo you are offered is drawn at random.",
                            1, 1, 1, true)
                        GameTooltip:AddLine("Reach |cffffd700level 80|r to wear it again.", 0.5, 0.5, 0.5, true)
                    else
                        GameTooltip:AddLine("Activate: replaces your echoes with this build.",
                            1, 1, 1, true)
                        GameTooltip:AddLine(isEnabled and "Activate another build to swap to it."
                            or "Click to activate this build.", 0.5, 0.5, 0.5, true)
                    end
                end
            end
        elseif not self.isMine then
            GameTooltip:AddLine("Community build.", 1, 1, 1, true)
            GameTooltip:AddLine(
                "Use the |cffffd700...|r menu, |cffffd700Save to my builds|r, then activate it from |cffffd700My Builds|r.",
                0.5, 0.5, 0.5, true)
        elseif IsActiveLoadout(self.loadout) then
            GameTooltip:AddLine("This is your active loadout.", 1, 1, 1, true)
            GameTooltip:AddLine("Click to stop playing with it.", 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine("Its echoes will be highlighted whenever you pick a new echo.", 1, 1, 1, true)
            GameTooltip:AddLine("Click to play with this loadout.", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(16, 16)
    row.classIcon:SetPoint("TOPLEFT", 12, -12) -- left-aligned with the echo icons below
    row.classIcon:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.classIcon, "TOPRIGHT", 4, -2)
    row.name:SetWidth(280)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Community author, pinned to the row's top-right corner
    row.author = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.author:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -10)
    row.author:SetJustifyH("RIGHT")
    row.author:Hide()

    -- Mini echo icons created on demand (an expanded row can show up to 80);
    -- positions are assigned per render since the wrap width changes.
    row.icons = {}

    -- Expand/collapse toggle on the name line (only shown when echoes overflow)
    row.toggleBtn = CreateFrame("Button", nil, row)
    row.toggleBtn:SetSize(16, 16)
    -- Expand toggle lives on the button line so the name line starts flush
    -- with the echo icons
    row.toggleBtn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 12)
    row.toggleBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    row.toggleBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    row.toggleBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    row.toggleBtn:SetScript("OnClick", function()
        if not row.expandKey then return end
        if expandedLoadouts[row.expandKey] then
            expandedLoadouts[row.expandKey] = nil
        else
            expandedLoadouts[row.expandKey] = true
        end
        Refresh()
    end)

    row.more = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.more:SetPoint("TOPLEFT", row, "TOPLEFT", 12 + MAX_ROW_ICONS * ROW_ICON_PITCH + 2, -39)

    local function MakeRowBtn(text, width)
        return ShrinkButtonFont(utils.CreateSimpleCustomButton(row, text, nil, width, 20))
    end

    -- Delete = a real close cross pinned to the row's top-right corner
    row.deleteBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.deleteBtn:SetSize(24, 24)
    row.deleteBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", 2, 2)
    row.deleteBtn:SetFrameLevel(row:GetFrameLevel() + 5)

    row.exportBtn = MakeRowBtn("Export", 62)
    row.exportBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 10)
    row.shareBtn = MakeRowBtn("Share", 58)
    row.shareBtn:SetPoint("RIGHT", row.exportBtn, "LEFT", -3, 0)
    row.saveBtn = MakeRowBtn("Save", 58) -- community: copy into My Loadouts
    row.saveBtn:SetPoint("RIGHT", row.exportBtn, "LEFT", -3, 0)
    row.editBtn = MakeRowBtn("Edit", 52) -- mine: reopen in the builder
    row.editBtn:SetPoint("RIGHT", row.shareBtn, "LEFT", -3, 0)

    -- "..." kebab: opens the row's action menu (see ShowLoadoutMenu). Replaces
    -- the row's cluster of action buttons on filled/library/community rows.
    row.menuBtn = utils.CreateSimpleCustomButton(row, "\226\128\162\226\128\162\226\128\162", nil, 34, 20)
    row.menuBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 10)
    row.menuBtn:SetScript("OnClick", function() ShowLoadoutMenu(row) end)
    row.menuBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("More actions", 1, 1, 1)
        GameTooltip:Show()
    end)
    row.menuBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Server build-slot rows: snapshot the current build into this slot /
    -- rename the stored build. Hidden on library and community rows.
    row.saveBuildBtn = MakeRowBtn("Save Build", 84)
    row.saveBuildBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 10)
    row.renameBuildBtn = MakeRowBtn("Rename", 64)
    row.renameBuildBtn:SetPoint("RIGHT", row.saveBuildBtn, "LEFT", -3, 0)

    row.saveBuildBtn:SetScript("OnClick", function()
        if not row.serverSlot then return end
        -- Snapshots are a max-level-only feature server-side (HandleSave). Gate
        -- the prompt here so the player never fills in a name for a save that
        -- can only be rejected.
        if (UnitLevel("player") or 1) < 80 then
            UIErrorsFrame:AddMessage("You can only save a build snapshot at level 80.", 1, 0.2, 0.2)
            return
        end
        pendingServerSlot = row.serverSlot
        if row.serverFilled then
            -- Overwriting destroys the stored build: warn before the name prompt
            StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_OVERWRITE",
                (row.loadout and row.loadout.name) or ("Build " .. row.serverSlot))
        else
            StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_SAVE", row.serverSlot)
        end
    end)
    -- Disabled below 80, so the reason has to come from a tooltip: a disabled
    -- button still fires OnEnter, but never OnClick.
    row.saveBuildBtn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Save Build", 1, 1, 1)
        GameTooltip:AddLine("You can only save a build snapshot at level 80.", 1, 0.2, 0.2, true)
        GameTooltip:Show()
    end)
    row.saveBuildBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.renameBuildBtn:SetScript("OnClick", function()
        if not row.serverSlot or not row.serverFilled then return end
        pendingServerSlot = row.serverSlot
        StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_RENAME", row.serverSlot)
    end)

    -- Recoverable wishlist only: promotes it back into a free build slot.
    -- Sits left of the "..." menu, as the row's one meaningful action.
    row.recoverBtn = MakeRowBtn("Recover", 72)
    row.recoverBtn:SetPoint("RIGHT", row.menuBtn, "LEFT", -3, 0)
    row.recoverBtn:SetScript("OnClick", function()
        if not row.serverSlot or not row.serverToRecover then return end
        if not row.recoverBtn:IsEnabled() then return end
        pendingServerSlot = row.serverSlot
        StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_RECOVER",
            (row.loadout and row.loadout.name) or "")
    end)
    -- Disabled when every build slot is taken, so the reason has to come from
    -- the tooltip: a disabled button still fires OnEnter, never OnClick.
    row.recoverBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Recover this build", 1, 1, 1)
        GameTooltip:AddLine(
            "Moves this wishlist into a free build slot and makes it a saved build again, with the level-80 swap it used to have. It leaves your Echo Wishlist.",
            0.9, 0.9, 0.9, true)
        local blocked = RecoverBlockedReason()
        if blocked then
            GameTooltip:AddLine(blocked, 1, 0.2, 0.2, true)
        else
            GameTooltip:AddLine("It lands in build slot |cffffd700"
                .. tostring(FirstFreeBuildSlot()) .. "|r.", 0.5, 0.5, 0.5, true)
        end
        GameTooltip:Show()
    end)
    row.recoverBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Design (builder) and Import (EBH1 string) into this server slot.
    -- On a filled DESIGNED row, Design reopens the build in the builder.
    row.designBtn = MakeRowBtn("Design", 58)
    row.importBtn = MakeRowBtn("Import", 56)
    row.designBtn:SetScript("OnClick", function()
        if not row.serverSlot or not row.serverFilled then return end
        -- Designs in the unlimited pool re-upload in place; a legacy design
        -- still stored in a snapshot slot re-saves as a NEW design (the old
        -- row can then be deleted to free its slot)
        local svc = GetService()
        local maxSlots = (svc.GetServerMaxSlots and svc.GetServerMaxSlots()) or 5
        Journal.EditLoadout(row.loadout, nil, row.serverSlot > maxSlots and row.serverSlot or 0)
    end)
    row.designBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Design a build", 1, 1, 1)
        GameTooltip:AddLine(
            "Compose this build echo by echo in All Echoes. Designed builds are " ..
            "|cffffd700highlighted|r in your draws and can be auto-picked. They never change what you are offered.",
            0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    row.designBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.importBtn:SetScript("OnClick", function()
        if not row.serverSlot or row.serverFilled then return end
        pendingServerSlot = row.serverSlot
        StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_IMPORT", row.serverSlot)
    end)

    -- Gold purchase of a locked slot (account-wide); only the NEXT slot is
    -- buyable. Big and centered - it is the locked row's only action.
    row.unlockBtn = utils.CreateSimpleCustomButton(row, "Unlock", nil, 180, 32)
    row.unlockBtn:SetPoint("CENTER", row, "CENTER", 0, -8)
    row.unlockBtn:SetScript("OnClick", function()
        if not row.serverSlot or not row.serverLockedCost or not row.serverPurchasable then return end
        StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_UNLOCK", row.serverSlot, tostring(row.serverLockedCost))
    end)
    row.unlockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Unlock build slot", 1, 1, 1)
        if row.serverPurchasable then
            GameTooltip:AddLine(string.format(
                "Costs |cffffd700%s gold|r. The unlock is |cffffd700account-wide|r: all your characters get this slot.",
                tostring(row.serverLockedCost or 0)), 0.9, 0.9, 0.9, true)
        else
            GameTooltip:AddLine("Unlock the previous slot first.", 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    row.unlockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.editBtn:SetScript("OnClick", function()
        if row.loadout and row.isMine then
            Journal.EditLoadout(row.loadout, row.index)
        end
    end)

    row.deleteBtn:SetScript("OnClick", function()
        if not row.loadout then return end
        if row.serverSlot then
            if not row.serverFilled then return end
            -- Deleting the build you are wearing would leave no way back to it,
            -- and a build is never turned off: switch away from it first.
            if not row.deleteBtn:IsEnabled() then return end
            pendingServerSlot = row.serverSlot
            StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_DELETE", row.loadout.name or "")
            return
        end
        pendingLoadout = { loadout = row.loadout, index = row.index }
        if row.isMine then
            StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_DELETE", row.loadout.name or "")
        else
            StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_UNPUBLISH", row.loadout.name or "")
        end
    end)
    row.exportBtn:SetScript("OnClick", function()
        local svc = GetService()
        if row.loadout and svc and svc.ExportEchoLoadout then
            StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_EXPORT", nil, nil, svc.ExportEchoLoadout(row.loadout))
        end
    end)
    row.shareBtn:SetScript("OnClick", function()
        if not row.loadout then return end
        pendingLoadout = { loadout = row.loadout }
        StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_SHARE", row.loadout.name or "")
    end)
    -- Community view: copy a shared build into a new designed build (the
    -- server assigns an id from the unlimited pool)
    row.saveBtn:SetScript("OnClick", function()
        local svc = GetService()
        if not (row.loadout and svc and svc.UploadServerBuildSlot) then return end
        svc.UploadServerBuildSlot(0, row.loadout.name, row.loadout.echoes)
    end)

    loadoutRows[i] = row
    return row
end

-- Returns the row's height (it grows when expanded to show every echo).
-- serverSlot/serverFilled mark a server build-slot row (they change the row's
-- click behavior and button set); both nil for library/community rows.
-- serverLockedCost (gold, non-nil = slot not yet purchased) + serverPurchasable
-- (true = it is the NEXT slot, so the Unlock button is clickable) drive the
-- gold-unlock presentation of locked slots.
-- serverToRecover marks a wishlist the server flagged as a build the player
-- really owned: it is the only one that can be promoted back into a build slot.
local function UpdateLoadoutRow(row, loadout, index, isMine, expandKey, serverSlot, serverFilled, serverLockedCost, serverPurchasable, serverVerified, serverToRecover)
    row.loadout, row.index, row.isMine = loadout, index, isMine
    row.serverSlot, row.serverFilled = serverSlot, serverFilled
    row.serverLockedCost, row.serverPurchasable = serverLockedCost, serverPurchasable
    row.serverVerified = serverVerified
    row.serverToRecover = serverToRecover and true or false
    row.expandKey = expandKey
    local expanded = expandedLoadouts[expandKey] and true or false

    -- Rows are pooled: a flash still playing belongs to whatever build used to
    -- live here, so drop it before this row takes on a new one. RenderLoadouts
    -- restarts it afterwards if THIS build is the freshly saved one.
    StopRowFlash(row)

    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[loadout.class]
    if coords then
        row.classIcon:SetTexCoord(unpack(coords))
        row.classIcon:Show()
    else
        row.classIcon:Hide()
    end

    local label = loadout.name or "Loadout"
    local c = RAID_CLASS_COLORS and loadout.class and RAID_CLASS_COLORS[loadout.class]
    if c then
        label = string.format("|cff%02x%02x%02x%s|r",
            math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), label)
    end
    if row.serverToRecover then
        -- Server rows have no author, so the line doubles as a status badge
        row.author:SetText("|cffffd700Recoverable|r")
        row.author:Show()
    elseif not isMine and loadout.author and loadout.author ~= "" then
        row.author:SetText("by " .. loadout.author)
        row.author:Show()
    else
        row.author:Hide()
    end

    -- Golden border + tag on the loadout currently being played
    -- (server rows: the slot the level-80 swap would apply)
    local isActive
    if serverSlot then
        isActive = serverFilled and GetService().GetServerActiveSlot() == serverSlot
    else
        isActive = IsActiveLoadout(loadout)
    end
    -- Run progress vs this build (server rows only): per-entry check used
    -- below to dim the icons of echoes not yet obtained this run
    local entryDone
    if serverSlot and serverFilled then
        entryDone = BuildProgressChecker()
    end

    -- Inactive builds that hold content are greyed out so the active one pops.
    -- Empty/locked slots keep full contrast (they're actionable, not builds).
    local hasContent = (not serverSlot) or serverFilled
    local dim = hasContent and not isActive
    local contentAlpha = dim and 0.55 or 1

    -- An empty (unfilled, unlocked) server slot gets the "available to fill" look
    local isEmptySlot = serverSlot and not serverFilled and not serverLockedCost
    -- Grey stripe = this row is not the build you are playing: every filled but
    -- inactive build, plus slots with nothing to offer (an empty one below 80,
    -- where Save Build is greyed, or a locked one that is not next to buy).
    local isUnavailable
    if serverSlot and serverFilled then
        isUnavailable = not isActive
    elseif serverLockedCost then
        isUnavailable = not serverPurchasable
    elseif serverSlot then
        isUnavailable = (UnitLevel("player") or 1) < 80
    end
    if isUnavailable and not isActive then
        row.disabledStripe:Show()
    else
        row.disabledStripe:Hide()
    end
    if isActive then
        row:SetBackdropBorderColor(1, 0.82, 0, 1)
        row:SetBackdropColor(0.16, 0.12, 0.02, 0.85) -- warm dark-gold bed
        row.activeBg:Show()
        row.activeStripe:Show()
        row.emptyBg:Hide()
        row.emptyStripe:Hide()
    elseif isEmptySlot then
        -- Blue "available to fill" only when it really can be filled; below 80
        -- the slot is inert, so it takes the grey treatment instead.
        row:SetBackdropBorderColor(isUnavailable and 0.45 or 0.35,
            isUnavailable and 0.45 or 0.55, isUnavailable and 0.45 or 0.85, 0.9)
        row:SetBackdropColor(0.03, 0.05, 0.08, 0.55) -- faint cool bed
        row.activeBg:Hide()
        row.activeStripe:Hide()
        row.emptyBg:Show()
        if isUnavailable then row.emptyStripe:Hide() else row.emptyStripe:Show() end
    else
        row:SetBackdropColor(0, 0, 0, 0.45)
        row.activeBg:Hide()
        row.activeStripe:Hide()
        row.emptyBg:Hide()
        row.emptyStripe:Hide()
        if isUnavailable then
            -- Not the build being played: grey border to match its grey stripe.
            -- Outranks the designed/snapshot colouring, which now only shows on
            -- a build you can act on.
            row:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
        elseif serverSlot and serverFilled and serverVerified == false then
            row:SetBackdropBorderColor(0.6, 0.4, 0.9, 1) -- designed builds: purple
        elseif serverSlot then
            row:SetBackdropBorderColor(0.35, 0.55, 0.85, 1) -- snapshots/empty: blue
        else
            row:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end
    end
    row.name:SetText(label)
    row.name:SetAlpha(contentAlpha)
    row.classIcon:SetAlpha(contentAlpha)
    row.author:SetAlpha(dim and 0.5 or 1)

    local echoes = loadout.echoes or {}
    local overflow = #echoes > MAX_ROW_ICONS
    local shown = expanded and #echoes or math.min(#echoes, MAX_ROW_ICONS)
    local perLine = expanded and ICONS_PER_LINE or MAX_ROW_ICONS

    if overflow then
        row.toggleBtn:SetNormalTexture(expanded
            and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        row.toggleBtn:SetPushedTexture(expanded
            and "Interface\\Buttons\\UI-MinusButton-Down" or "Interface\\Buttons\\UI-PlusButton-Down")
        row.toggleBtn:Show()
    else
        row.toggleBtn:Hide()
    end

    for k = 1, math.max(shown, #row.icons) do
        if k <= shown then
            local ib = GetRowIcon(row, k)
            local e = echoes[k]
            local _, _, tex = GetSpellInfo(e.spellId)
            tex = tex or "Interface\\Icons\\INV_Misc_QuestionMark"
            -- SetPortraitToTexture re-crops the texture; skip when unchanged
            if ib._portraitTex ~= tex then
                ib._portraitTex = tex
                SetPortraitToTexture(ib.tex, tex)
            end
            ib.spellId, ib.quality, ib.stacks = e.spellId, e.quality, e.stacks
            ib.locked = e.locked or false
            if ib.lockTex then
                if ib.locked then ib.lockTex:Show() else ib.lockTex:Hide() end
            end
            local borderIdx = math.min(e.quality or 0, 3) -- rounded assets exist for 0-3
            ib.base:SetTexture(ASSETS .. "perk_quality_" .. borderIdx)
            ib.ring:SetTexture(ASSETS .. "perk_border_quality_" .. borderIdx)
            -- Echoes not yet obtained this run render dimmed on build rows
            local done = (entryDone == nil) or entryDone(e, serverVerified)
            ib.notObtained = not done
            ib.tex:SetDesaturated(not done)
            ib.base:SetDesaturated(not done)
            ib.ring:SetDesaturated(not done)
            local alpha = (done and 1 or 0.45) * (dim and 0.6 or 1)
            ib.tex:SetAlpha(alpha)
            ib.base:SetAlpha(alpha)
            ib.ring:SetAlpha(alpha)
            local line = math.floor((k - 1) / perLine)
            local col = (k - 1) % perLine
            ib:ClearAllPoints()
            ib:SetPoint("TOPLEFT", row, "TOPLEFT", 12 + col * ROW_ICON_PITCH, -33 - line * ROW_ICON_PITCH)
            ib:Show()
        elseif row.icons[k] then
            row.icons[k].spellId = nil
            row.icons[k]:Hide()
        end
    end
    row.more:SetText((not expanded and overflow) and ("+" .. (#echoes - MAX_ROW_ICONS)) or "")

    -- The per-row action buttons all live in the "..." menu now, so hide them
    -- unconditionally here; each branch below only decides between the menu,
    -- the primary Save Build button (empty slots), or Unlock (locked slots).
    row.editBtn:Hide(); row.saveBtn:Hide(); row.shareBtn:Hide(); row.exportBtn:Hide()
    row.renameBuildBtn:Hide(); row.designBtn:Hide(); row.importBtn:Hide()
    row.recoverBtn:Hide()

    if serverSlot then
        -- Server build slots. Locked: gold Unlock button only. Empty: Save
        -- Build (snapshot). Filled: the "..." menu (Overwrite/Design, Rename,
        -- Share, Export, Delete).
        if serverLockedCost then
            row.saveBuildBtn:Hide()
            row.deleteBtn:Hide()
            row.menuBtn:Hide()
            row.unlockBtn:Show()
            row.unlockBtn.text:SetText(tostring(serverLockedCost)
                .. " |TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t")
            if serverPurchasable then
                row.unlockBtn:Enable()
                if row.unlockBtn.text then row.unlockBtn.text:SetTextColor(1, 1, 1) end
            else
                row.unlockBtn:Disable()
                if row.unlockBtn.text then row.unlockBtn.text:SetTextColor(0.5, 0.5, 0.5) end
            end
        elseif serverFilled then
            row.unlockBtn:Hide()
            row.saveBuildBtn:Hide()
            row.deleteBtn:Hide() -- Delete lives in the "..." menu
            row.menuBtn:Show()
            row.menuBtn:ClearAllPoints()
            row.menuBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 10)
            -- A recoverable wishlist gets its action out of the menu: it is the
            -- one thing the player is meant to do with it.
            if row.serverToRecover then
                row.recoverBtn:Show()
                row.recoverBtn:ClearAllPoints()
                row.recoverBtn:SetPoint("RIGHT", row.menuBtn, "LEFT", -3, 0)
                if RecoverBlockedReason() then
                    row.recoverBtn:Disable()
                    if row.recoverBtn.text then row.recoverBtn.text:SetTextColor(0.5, 0.5, 0.5) end
                else
                    row.recoverBtn:Enable()
                    if row.recoverBtn.text then row.recoverBtn.text:SetTextColor(1, 0.82, 0) end
                end
            end
        else
            row.unlockBtn:Hide()
            row.deleteBtn:Hide()
            row.menuBtn:Hide()
            -- Empty snapshot slot: snapshot-only (designs are created with the
            -- New/Import bar buttons and live in their own unlimited pool)
            row.saveBuildBtn:Show()
            row.saveBuildBtn.text:SetText("Save Build")
            row.saveBuildBtn:ClearAllPoints()
            row.saveBuildBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 10)
        end

        -- Snapshots (Save Build) are level-80-only server-side; disable the
        -- button below max level so it takes the greyed-out disabled art and
        -- stops responding, with the reason moved to its tooltip.
        -- An active saved build cannot be deleted: it is the echo set you are
        -- wearing, and builds are only ever switched, never turned off. Its
        -- Delete lives in the "..." menu, which greys off this enabled state.
        if isActive and serverVerified ~= false then
            row.deleteBtn:Disable()
        else
            row.deleteBtn:Enable()
        end

        -- Applied even while hidden: on filled rows the button lives behind the
        -- "..." menu, which greys its entry off this same enabled state.
        do
            if (UnitLevel("player") or 1) < 80 then
                row.saveBuildBtn:Disable()
                if row.saveBuildBtn.text then row.saveBuildBtn.text:SetTextColor(0.5, 0.5, 0.5) end
            else
                row.saveBuildBtn:Enable()
                if row.saveBuildBtn.text then row.saveBuildBtn.text:SetTextColor(1, 1, 1) end
            end
        end
    else
        -- Library ("mine") and community rows: everything is in the "..." menu.
        row.saveBuildBtn:Hide(); row.unlockBtn:Hide()
        row.deleteBtn:Hide() -- Delete/Unpublish lives in the "..." menu
        row.deleteBtn:Enable() -- rows are pooled: clear any build-row disable
        row.menuBtn:Show()
        row.menuBtn:ClearAllPoints()
        row.menuBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 10)
    end

    -- name line (33) + icon lines (ROW_ICON_PITCH each) + button line (33):
    -- roomier padding top/bottom so the content doesn't hug the border. Every
    -- collapsed row - Your loadouts, Echo Wishlist, empty and locked slots -
    -- reserves a single icon line, so they all share one height and the sections
    -- line up; only expanding a row to show every echo grows it.
    local lines = math.max(1, math.ceil(shown / perLine))
    local height = 33 + lines * ROW_ICON_PITCH + 33
    row:SetHeight(height)
    return height
end

local function GetLoadoutHeader(i)
    local h = loadoutHeaders[i]
    if not h then
        h = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetJustifyH("LEFT")
        loadoutHeaders[i] = h
    end
    return h
end

-- Collapsible group header for the mine view's build-slot sections:
-- a +/- toggle plus label; clicking anywhere on it folds/unfolds the group
local function GetSectionHeader(i)
    local h = sectionHeaders[i]
    if not h then
        h = CreateFrame("Button", nil, scrollChild)
        h:SetSize(390, 18)
        h.toggle = h:CreateTexture(nil, "ARTWORK")
        h.toggle:SetSize(16, 16)
        h.toggle:SetPoint("LEFT", h, "LEFT", 0, 0)
        h.label = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h.label:SetPoint("LEFT", h.toggle, "RIGHT", 4, 0)
        h.label:SetJustifyH("LEFT")
        h:SetScript("OnClick", function(self)
            if self.sectionKey then
                ToggleSectionCollapsed(self.sectionKey)
                Refresh()
            end
        end)
        sectionHeaders[i] = h
    end
    return h
end

local function HideLoadoutRows()
    for _, row in ipairs(loadoutRows) do row:Hide() end
    for _, h in ipairs(loadoutHeaders) do h:Hide() end
    for _, h in ipairs(sectionHeaders) do h:Hide() end
    if loadoutEmptyText then loadoutEmptyText:Hide() end
end

local function RenderLoadouts()
    local svc = GetService()
    local isMine = (loadoutView == "mine")
    local source
    if isMine then
        source = svc and svc.GetEchoLoadouts and svc.GetEchoLoadouts() or {}
    else
        source = svc and svc.GetSharedEchoLoadouts and svc.GetSharedEchoLoadouts()
    end

    if not loadoutEmptyText then
        loadoutEmptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        loadoutEmptyText:SetPoint("TOP", scrollChild, "TOP", 0, -40)
        loadoutEmptyText:SetWidth(370)
        loadoutEmptyText:SetJustifyH("CENTER")
        loadoutEmptyText:SetWordWrap(true)
    end

    -- The search bar filters by name; the class dropdown filters by class
    local filtered = {}
    local needle = string.lower(currentSearchText or "")
    for idx, lo in ipairs(source or {}) do
        local okSearch = needle == "" or
            string.find(string.lower(lo.name or ""), needle, 1, true) ~= nil
        local okClass = (not selectedLoadoutClass) or
            ((lo.class or "UNKNOWN") == selectedLoadoutClass)
        if okSearch and okClass then
            table.insert(filtered, { loadout = lo, index = idx })
        end
    end

    -- Split by class: stable class grouping, then by name inside a group
    table.sort(filtered, function(a, b)
        local ca, cb = a.loadout.class or "UNKNOWN", b.loadout.class or "UNKNOWN"
        if ca ~= cb then return ca < cb end
        return (a.loadout.name or "") < (b.loadout.name or "")
    end)

    -- Lay out rows top to bottom, inserting a class header whenever the class
    -- changes (headers are skipped while a single class is filtered).
    local y = -1
    local headerCount, lastClass = 0, nil
    local rowCount = 0

    -- "My Loadouts" leads with the server build slots (verified snapshots with
    -- the level-80 swap), then the local library below.
    -- Nothing renders until the server's first reply, so realms without the
    -- feature (or with it disabled) show the plain library unchanged.
    if isMine then
        local serverSlots = svc and svc.GetServerBuildSlots and svc.GetServerBuildSlots()
        local serverEnabled = svc and svc.AreServerBuildSlotsEnabled and svc.AreServerBuildSlotsEnabled()
        if serverSlots == nil and not serverBuildSlotsRequested and svc and svc.RequestServerBuildSlots then
            serverBuildSlotsRequested = true
            svc.RequestServerBuildSlots() -- re-rendered when the reply lands
        end
        for _, h in ipairs(sectionHeaders) do h:Hide() end -- re-shown per group below
        if serverEnabled and serverSlots ~= nil then
            local maxSlots = (svc and svc.GetServerMaxSlots and svc.GetServerMaxSlots()) or 5
            local unlocked = (svc and svc.GetServerUnlockedSlots and svc.GetServerUnlockedSlots()) or maxSlots
            local classToken = GetPlayerClassToken()

            -- Partition the slots into collapsible groups: snapshots you saved,
            -- designed builds you're farming, and the empty/locked slots.
            -- Designed builds (an unlimited pool) lead. Your loadouts = the
            -- snapshot slots themselves, saved or not: one list in slot order
            -- rather than splitting filled from empty.
            local DESIGN, LOADOUTS = 1, 2
            local groups = {
                [DESIGN]   = { key = "design",   label = "|cffa080e0Echo Wishlist|r", items = {} },
                [LOADOUTS] = { key = "loadouts", label = "|cff60a0e0Your loadouts|r",      items = {} },
            }
            for slot = 1, maxSlots do
                local stored = serverSlots[slot]
                local isSlotLocked = slot > unlocked
                local item = { slot = slot, stored = stored, locked = isSlotLocked }
                -- Legacy designs stored in a snapshot slot still belong below
                if stored and not stored.verified and not isSlotLocked then
                    table.insert(groups[DESIGN].items, item)
                else
                    table.insert(groups[LOADOUTS].items, item)
                end
            end

            -- Designed builds live beyond the snapshot slots (unlimited pool,
            -- ids assigned by the server)
            local designedIds = {}
            for slot in pairs(serverSlots) do
                if slot > maxSlots then table.insert(designedIds, slot) end
            end
            table.sort(designedIds)
            for _, slot in ipairs(designedIds) do
                table.insert(groups[DESIGN].items, { slot = slot, stored = serverSlots[slot], locked = false })
            end

            local sectionCount = 0
            for _, group in ipairs(groups) do
                if #group.items > 0 then
                    sectionCount = sectionCount + 1
                    local collapsed = IsSectionCollapsed(group.key)
                    local h = GetSectionHeader(sectionCount)
                    h.sectionKey = group.key
                    h.toggle:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up"
                        or "Interface\\Buttons\\UI-MinusButton-Up")
                    h.label:SetText(group.label .. " |cff808080(" .. #group.items .. ")|r")
                    h:ClearAllPoints()
                    h:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, y - 2)
                    h:Show()
                    y = y - 22

                    if not collapsed then
                        for _, item in ipairs(group.items) do
                            local slot, stored, isSlotLocked = item.slot, item.stored, item.locked
                            local loadout
                            if isSlotLocked then
                                loadout = { name = "|cff808080Locked slot " .. slot .. "|r", class = classToken, echoes = {} }
                            elseif stored then
                                loadout = { name = stored.name ~= "" and stored.name or ("Build " .. slot), class = classToken, echoes = stored.echoes }
                            else
                                loadout = { name = "|cff808080Empty slot " .. slot .. "|r", class = classToken, echoes = {} }
                            end
                            rowCount = rowCount + 1
                            local row = GetLoadoutRow(rowCount)
                            -- NB: cannot use `stored and X or nil` here - when
                            -- verified is false the and/or chain collapses to
                            -- nil and the row renders as a snapshot
                            local rowVerified = nil
                            if stored then rowVerified = (stored.verified == true) end
                            local rowHeight = UpdateLoadoutRow(row, loadout, slot, true, "s:" .. slot, slot,
                                (not isSlotLocked) and stored ~= nil,
                                isSlotLocked and (svc.GetServerSlotCostGold and svc.GetServerSlotCostGold(slot) or 0) or nil,
                                isSlotLocked and slot == unlocked + 1,
                                rowVerified,
                                stored ~= nil and stored.toRecover == true)
                            row:ClearAllPoints()
                            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, y)
                            row:Show()

                            -- Flash the build that was just saved. Cleared only
                            -- here, so a save that lands before the slot data
                            -- arrives still flashes on the render that shows it.
                            if stored and svc.GetLastSavedBuildSlot
                                and svc.GetLastSavedBuildSlot() == slot then
                                svc.ClearLastSavedBuildSlot()
                                flashSlot, flashElapsed = slot, 0
                            end
                            -- Restarted on every render so the pulse survives
                            -- the refresh storm that follows a save
                            if stored and flashSlot == slot then
                                StartRowFlash(row)
                            end

                            y = y - (rowHeight + ROW_SPACING)
                        end
                    end
                end
            end
            for i = sectionCount + 1, #sectionHeaders do sectionHeaders[i]:Hide() end
        end
    else
        for _, h in ipairs(sectionHeaders) do h:Hide() end -- community view
    end

    -- "My Loadouts" shows only the server build slots; the local library is
    -- retired (community sharing still lists below in the Community view).
    if isMine then filtered = {} end

    for i, entry in ipairs(filtered) do
        local cls = entry.loadout.class or "UNKNOWN"
        if not selectedLoadoutClass and cls ~= lastClass then
            headerCount = headerCount + 1
            local h = GetLoadoutHeader(headerCount)
            h:SetText(ClassDisplay(cls))
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, y - 2)
            h:Show()
            y = y - 20
            lastClass = cls
        end
        rowCount = rowCount + 1
        local row = GetLoadoutRow(rowCount)
        local expandKey = (isMine and "m:" or "c:") .. entry.index
        local rowHeight = UpdateLoadoutRow(row, entry.loadout, entry.index, isMine, expandKey)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, y)
        row:Show()
        y = y - (rowHeight + ROW_SPACING)
    end
    for i = rowCount + 1, #loadoutRows do loadoutRows[i]:Hide() end
    for i = headerCount + 1, #loadoutHeaders do loadoutHeaders[i]:Hide() end

    if #filtered == 0 and not isMine then
        if source == nil then
            loadoutEmptyText:SetText("Requesting community loadouts from the server...")
        elseif source and #source > 0 then
            loadoutEmptyText:SetText("No loadouts match the current filters.")
        else
            loadoutEmptyText:SetText("No community loadouts shared yet.")
        end
        -- Anchor below whatever was already laid out (the server build slots
        -- occupy the top of "My Loadouts")
        loadoutEmptyText:ClearAllPoints()
        loadoutEmptyText:SetPoint("TOP", scrollChild, "TOP", 0, y - 20)
        loadoutEmptyText:Show()
        y = y - 80
    else
        loadoutEmptyText:Hide()
    end

    scrollChild:SetHeight(math.max(math.abs(y) + 12, 300))
    scrollFrame:SetVerticalScroll(0)
end

-- Request the shared list, filtered server-side by the active class filter
-- (empty body = all classes; the client filters again locally anyway)
local function RequestCommunityLoadouts()
    local svc = GetService()
    if svc and svc.RequestSharedEchoLoadouts then
        svc.RequestSharedEchoLoadouts(selectedLoadoutClass)
    end
end

-- Parsed import waiting for its name: { slot, name, echoes }
local pendingImport

local function CompleteImport(finalName)
    if not pendingImport then return end
    local svc = GetService()
    -- A blank name keeps the one embedded in the string
    if not finalName or finalName:gsub("%s", "") == "" then
        finalName = pendingImport.name
    end
    local isFirstBuild = not HasAnyBuild()
    if svc and svc.UploadServerBuildSlot
        and svc.UploadServerBuildSlot(pendingImport.slot, finalName, pendingImport.echoes) then
        -- The very first build gets armed as soon as the server hands back the
        -- id it assigned, instead of leaving the dropdown on "Select a
        -- loadout". Armed server side, so deleting it disarms it too.
        if isFirstBuild and pendingImport.slot == 0 then
            autoActivateFirstBuild = true
        end
        loadoutView = "mine"
        Refresh()
    end
    pendingImport = nil
end

-- Imports an EBH1 string into a server build slot (persistent, designed).
-- The string is parsed right away, but the upload waits for the naming
-- popup: the embedded name is only a default the player may replace.
function Journal.ImportBuildToSlot(text, slot)
    local svc = GetService()
    if not svc or not svc.ImportEchoLoadout or not svc.UploadServerBuildSlot then return end
    if not slot then
        UIErrorsFrame:AddMessage("No free build slot. Delete a build or unlock another slot first.", 1, 0.2, 0.2)
        return
    end
    local lo = svc.ImportEchoLoadout(text)
    if not lo then
        UIErrorsFrame:AddMessage("Invalid loadout string.", 1, 0.2, 0.2)
        return
    end
    pendingImport = { slot = slot, name = lo.name, echoes = lo.echoes }
    StaticPopup_Show("PROJECTEBONHOLD_IMPORT_NAME")
end

StaticPopupDialogs["PROJECTEBONHOLD_IMPORT_NAME"] = {
    text = "Name the imported |cffa080e0Echo Wishlist|r:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnShow = function(self)
        self.editBox:SetWidth(260)
        self.editBox:SetText(pendingImport and pendingImport.name or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        CompleteImport(self.editBox:GetText())
    end,
    OnCancel = function() pendingImport = nil end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        CompleteImport(dialog.editBox:GetText())
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Context-bar Import: creates a new designed build (server assigns the id)
function Journal.ImportLoadoutString(text)
    Journal.ImportBuildToSlot(text, 0)
end

StaticPopupDialogs["PROJECTEBONHOLD_LOADOUT_NAME"] = {
    text = "Name your new |cffa080e0Echo Wishlist|r, then pick its echoes in All Echoes:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnShow = function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        Journal.StartLoadoutBuilder(self.editBox:GetText(), pendingWishlistTargetSlot)
        pendingWishlistTargetSlot = nil
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        Journal.StartLoadoutBuilder(dialog.editBox:GetText(), pendingWishlistTargetSlot)
        pendingWishlistTargetSlot = nil
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    OnCancel = function() pendingWishlistTargetSlot = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Closes the export popup one instant AFTER a Ctrl+C, so the client has
-- already performed the OS copy by the time the editbox goes away
local exportCloser = CreateFrame("Frame")
exportCloser:Hide()
exportCloser:SetScript("OnUpdate", function(self, elapsed)
    self.delay = (self.delay or 0) - elapsed
    if self.delay > 0 then return end
    self:Hide()
    if self.dialog and self.dialog:IsShown() then self.dialog:Hide() end
    self.dialog = nil
    UIErrorsFrame:AddMessage("Build string copied.", 0.1, 1, 0.1)
end)

StaticPopupDialogs["PROJECTEBONHOLD_LOADOUT_EXPORT"] = {
    text = "Press |cffffd700Ctrl+C|r to copy the build string:",
    button1 = CLOSE,
    hasEditBox = 1,
    maxLetters = 0, -- the popup editbox is shared and maxLetters is sticky
    OnShow = function(self)
        local data = self.data
        local eb = self.editBox
        eb:SetWidth(260)
        eb:SetText(data or "")
        eb:HighlightText()
        eb:SetFocus()
        -- The shared popup editbox gets temporary scripts (restored in OnHide):
        -- typing can never mangle the string, and Ctrl+C confirms and closes
        self._exportOldChar = eb:GetScript("OnChar")
        self._exportOldKeyDown = eb:GetScript("OnKeyDown")
        eb:SetScript("OnChar", function(box)
            box:SetText(data or "")
            box:HighlightText()
        end)
        eb:SetScript("OnKeyDown", function(box, key)
            if key == "C" and IsControlKeyDown() then
                exportCloser.dialog = box:GetParent()
                exportCloser.delay = 0.1
                exportCloser:Show()
            end
        end)
    end,
    OnHide = function(self)
        local eb = self.editBox
        eb:SetScript("OnChar", self._exportOldChar)
        eb:SetScript("OnKeyDown", self._exportOldKeyDown)
        self._exportOldChar, self._exportOldKeyDown = nil, nil
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_LOADOUT_IMPORT"] = {
    text = "Paste a loadout string:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 0, -- the popup editbox is shared and maxLetters is sticky
    OnShow = function(self)
        self.editBox:SetWidth(260)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        Journal.ImportLoadoutString(self.editBox:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        Journal.ImportLoadoutString(dialog.editBox:GetText())
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_LOADOUT_DELETE"] = {
    text = "Delete loadout |cffffd700%s|r?\n\n|cffff5050This is permanent.|r The loadout will be gone for good and |cffff5050cannot be recovered.|r",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local svc = GetService()
        if pendingLoadout and svc and svc.DeleteEchoLoadout then
            svc.DeleteEchoLoadout(pendingLoadout.index)
            Refresh()
        end
        pendingLoadout = nil
    end,
    OnCancel = function() pendingLoadout = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_LOADOUT_UNPUBLISH"] = {
    text = "Remove \"%s\" from the community loadouts?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local svc = GetService()
        if pendingLoadout and svc and svc.UnpublishEchoLoadout then
            svc.UnpublishEchoLoadout(pendingLoadout.loadout)
            UIErrorsFrame:AddMessage("Loadout removed from the community.", 0.1, 1, 0.1)
            Refresh()
        end
        pendingLoadout = nil
    end,
    OnCancel = function() pendingLoadout = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function RefreshChoiceHighlights()
    if ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.RefreshLoadoutHighlights then
        ProjectEbonhold.PerkUI.RefreshLoadoutHighlights()
    end
end

StaticPopupDialogs["PROJECTEBONHOLD_LOADOUT_USE"] = {
    text = "Play with \"%s\"?\n\nIts echoes will be |cffffd700highlighted|r whenever you pick a new echo.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local svc = GetService()
        if pendingLoadout and svc and svc.SetActiveEchoLoadout then
            svc.SetActiveEchoLoadout(pendingLoadout.loadout)
            RefreshChoiceHighlights()
            Refresh()
        end
        pendingLoadout = nil
    end,
    OnCancel = function() pendingLoadout = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_LOADOUT_UNUSE"] = {
    text = "Stop playing with \"%s\"?\n\nEcho choices will no longer be highlighted.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local svc = GetService()
        if svc and svc.ClearActiveEchoLoadout then
            svc.ClearActiveEchoLoadout()
            RefreshChoiceHighlights()
            Refresh()
        end
        pendingLoadout = nil
    end,
    OnCancel = function() pendingLoadout = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_LOADOUT_SHARE"] = {
    text = "Share \"%s\" with the community?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local svc = GetService()
        if pendingLoadout and svc and svc.PublishEchoLoadout then
            svc.PublishEchoLoadout(pendingLoadout.loadout)
            UIErrorsFrame:AddMessage("Loadout shared with the community.", 0.1, 1, 0.1)
        end
        pendingLoadout = nil
    end,
    OnCancel = function() pendingLoadout = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ── Server build-slot popups ─────────────────────────────────────────────────

StaticPopupDialogs["PROJECTEBONHOLD_BUILDSLOT_SAVE"] = {
    text = "Save your current echoes (stacks and locks included) to build slot %d?\n\nName:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnShow = function(self)
        local svc = GetService()
        local slots = svc.GetServerBuildSlots and svc.GetServerBuildSlots()
        local existing = slots and pendingServerSlot and slots[pendingServerSlot]
        self.editBox:SetText(existing and existing.name or "")
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        if pendingServerSlot then
            GetService().SaveServerBuildSlot(pendingServerSlot, self.editBox:GetText())
        end
        pendingServerSlot = nil
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        if pendingServerSlot then
            GetService().SaveServerBuildSlot(pendingServerSlot, self:GetText())
        end
        pendingServerSlot = nil
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    OnCancel = function() pendingServerSlot = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Overwrite variant of the save popup: the slot already holds a build, so make
-- the destruction explicit before asking for the new name
StaticPopupDialogs["PROJECTEBONHOLD_BUILDSLOT_OVERWRITE"] = {
    text = "Overwrite |cffffd700%s|r?\n\n|cffff5050Its saved echoes will be lost|r and replaced by a snapshot of your current ones.\n\nName:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnShow = function(self)
        local svc = GetService()
        local slots = svc.GetServerBuildSlots and svc.GetServerBuildSlots()
        local existing = slots and pendingServerSlot and slots[pendingServerSlot]
        self.editBox:SetText(existing and existing.name or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        if pendingServerSlot then
            GetService().SaveServerBuildSlot(pendingServerSlot, self.editBox:GetText())
        end
        pendingServerSlot = nil
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        if pendingServerSlot then
            GetService().SaveServerBuildSlot(pendingServerSlot, self:GetText())
        end
        pendingServerSlot = nil
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    OnCancel = function() pendingServerSlot = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_BUILDSLOT_RENAME"] = {
    text = "New name for build slot %d:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnShow = function(self)
        local svc = GetService()
        local slots = svc.GetServerBuildSlots and svc.GetServerBuildSlots()
        local existing = slots and pendingServerSlot and slots[pendingServerSlot]
        self.editBox:SetText(existing and existing.name or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        local name = self.editBox:GetText()
        if pendingServerSlot and name and name ~= "" then
            GetService().RenameServerBuildSlot(pendingServerSlot, name)
        end
        pendingServerSlot = nil
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        local name = self:GetText()
        if pendingServerSlot and name and name ~= "" then
            GetService().RenameServerBuildSlot(pendingServerSlot, name)
        end
        pendingServerSlot = nil
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    OnCancel = function() pendingServerSlot = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_BUILDSLOT_DELETE"] = {
    text = "Delete build |cffffd700%s|r?\n\n|cffff5050This is permanent.|r The saved build will be gone for good and |cffff5050cannot be recovered.|r",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if pendingServerSlot then
            GetService().DeleteServerBuildSlot(pendingServerSlot)
        end
        pendingServerSlot = nil
    end,
    OnCancel = function() pendingServerSlot = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_BUILDSLOT_RECOVER"] = {
    text = "Recover build |cffffd700%s|r?\n\nIt leaves your Echo Wishlist and becomes a saved build again, in the first free build slot. You can wear it at level 80 like any other saved build.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if pendingServerSlot then
            -- Target 0: the server picks the free slot, so its answer is the
            -- authority even if a slot filled up while the popup was open.
            GetService().RecoverServerBuildSlot(pendingServerSlot, 0)
        end
        pendingServerSlot = nil
    end,
    OnCancel = function() pendingServerSlot = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Designed builds: same action, honest wording (highlight, not guarantee)
StaticPopupDialogs["PROJECTEBONHOLD_BUILDSLOT_ACTIVATE_DESIGNED"] = {
    text = "Follow build \"%s\" this run?\n\nIts echoes will be |cffffd700highlighted|r in your draws (and auto-picked if that option is enabled). They are not guaranteed to appear.%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if pendingServerSlot then
            GetService().ActivateServerBuildSlot(pendingServerSlot)
        end
        pendingServerSlot = nil
    end,
    OnCancel = function() pendingServerSlot = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_BUILDSLOT_SWITCH"] = {
    text = "Switch to build \"%s\"?\n\n|cffff5050All your current echoes will be replaced|r by this build (including its locked echoes).\n\nYou will |cffffd700cast a short attunement|r, and the switch happens when it completes.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if pendingServerSlot then
            GetService().ActivateServerBuildSlot(pendingServerSlot)
        end
        pendingServerSlot = nil
    end,
    OnCancel = function() pendingServerSlot = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_BUILDSLOT_DESIGN"] = {
    text = "Name the build for slot %d, then pick its echoes in All Echoes:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnShow = function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        Journal.StartLoadoutBuilder(self.editBox:GetText(), pendingServerSlot)
        pendingServerSlot = nil
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        Journal.StartLoadoutBuilder(self:GetText(), pendingServerSlot)
        pendingServerSlot = nil
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    OnCancel = function() pendingServerSlot = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_BUILDSLOT_IMPORT"] = {
    text = "Paste a loadout string to import into build slot %d:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 0, -- the popup editbox is shared and maxLetters is sticky
    OnShow = function(self)
        self.editBox:SetWidth(260)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        Journal.ImportBuildToSlot(self.editBox:GetText(), pendingServerSlot)
        pendingServerSlot = nil
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        Journal.ImportBuildToSlot(self:GetText(), pendingServerSlot)
        pendingServerSlot = nil
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    OnCancel = function() pendingServerSlot = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PROJECTEBONHOLD_BUILDSLOT_UNLOCK"] = {
    text = "Unlock build slot %d for |cffffd700%s gold|r?\n\nThe unlock is account-wide: all your characters get this slot.",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function()
        local svc = GetService()
        if svc and svc.UnlockServerBuildSlot then
            svc.UnlockServerBuildSlot()
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ── Context bar (per-tab header above the grid) ──────────────────────────────
-- All slot layers scale off one size so the row can shrink when many slots
-- must share the bar's width
local function ApplyPermanentSlotSize(slot, size)
    if slot._size == size then return end
    slot._size = size
    slot:SetSize(size, size)
    slot._bg:SetSize(size * 1.6, size * 1.6)
    slot._swirl:SetSize(size * 2.0, size * 2.0)
    slot._swirl2:SetSize(size * 1.75, size * 1.75)
    slot._rotatingTex:SetSize(size * 1.9, size * 1.9)
    if slot._armedGlow then slot._armedGlow:SetSize(size * 1.9, size * 1.9) end
    slot._iconBase:SetSize(size * 1.2, size * 1.2)
    slot.icon:SetSize(size * 0.8, size * 0.8)
    slot._border:SetSize(110 * size / 32, 110 * size / 32)
end

local function UpdatePermanentSlots()
    local svc = GetService()
    local unlockedSlots = svc and svc.GetMaximumPermanentEchoes and svc.GetMaximumPermanentEchoes() or 0
    local lockedPerks = svc and svc.GetLockedPerks and svc.GetLockedPerks() or {}

    -- One default slot plus one per Soul Ash milestone: that is the absolute
    -- total (6), shown even before the player has unlocked them all.
    local totalSlots = math.max(unlockedSlots,
        1 + (ProjectEbonhold.SoulAshesMilestones and #ProjectEbonhold.SoulAshesMilestones or 0))

    -- Left-align the slot row (the merged Echoes tab's window is wide enough
    -- now that centering left it floating disconnected from the My Run panel
    -- below); shrink the discs only if it still doesn't fit.
    local slotSize, slotGap = 42, 8
    local barWidth = contextBar:GetWidth()
    if not barWidth or barWidth <= 0 then barWidth = 350 end
    local rowWidth = totalSlots * slotSize + math.max(0, totalSlots - 1) * slotGap
    if totalSlots > 0 and rowWidth > barWidth then
        -- Too many slots for the bar: tighten the gap, then shrink the discs
        slotGap = 6
        slotSize = math.floor((barWidth - math.max(0, totalSlots - 1) * slotGap) / totalSlots)
        rowWidth = totalSlots * slotSize + math.max(0, totalSlots - 1) * slotGap
    end
    local startX = 0

    for i = 1, math.max(totalSlots, #slotButtons) do
        local slot = slotButtons[i]
        if i <= totalSlots then
            if not slot then
                -- Same visual recipe as the run panel's permanent slots:
                -- background disc, two counter-rotating star swirls, rotating
                -- ring overlay, quality disc + rounded quality border.
                -- Sizes come from ApplyPermanentSlotSize below.
                slot = CreateFrame("Button", nil, contextBar)
                slot._animGroups = {}

                local bg = slot:CreateTexture(nil, "BACKGROUND")
                bg:SetPoint("CENTER", slot, "CENTER", 0, -1)
                bg:SetTexture(ASSETS .. "perm_background_texture")
                slot._bg = bg

                local swirl = slot:CreateTexture(nil, "BACKGROUND", nil, 1)
                swirl:SetPoint("CENTER", slot, "CENTER", 0, 0)
                swirl:SetTexture("Interface\\Cooldown\\star4")
                swirl:SetBlendMode("ADD")
                slot._swirl = swirl
                local swirlAnim = swirl:CreateAnimationGroup()
                swirlAnim:SetLooping("REPEAT")
                local rotS = swirlAnim:CreateAnimation("Rotation")
                rotS:SetDuration(4)
                rotS:SetDegrees(360)
                rotS:SetOrigin("CENTER", 0, 0)
                swirlAnim:Play()
                table.insert(slot._animGroups, swirlAnim)

                local swirl2 = slot:CreateTexture(nil, "BACKGROUND", nil, 2)
                swirl2:SetPoint("CENTER", slot, "CENTER", 0, 0)
                swirl2:SetTexture("Interface\\Cooldown\\star4")
                swirl2:SetVertexColor(1, 1, 1, 0.4)
                swirl2:SetBlendMode("ADD")
                slot._swirl2 = swirl2
                local swirl2Anim = swirl2:CreateAnimationGroup()
                swirl2Anim:SetLooping("REPEAT")
                local rotS2 = swirl2Anim:CreateAnimation("Rotation")
                rotS2:SetDuration(5)
                rotS2:SetDegrees(-360)
                rotS2:SetOrigin("CENTER", 0, 0)
                swirl2Anim:Play()
                table.insert(slot._animGroups, swirl2Anim)

                local rotatingTex = slot:CreateTexture(nil, "OVERLAY", nil, 1)
                rotatingTex:SetPoint("CENTER", slot, "CENTER", 0, 0)
                rotatingTex:SetTexture(ASSETS .. "rotating_perm_texture")
                rotatingTex:SetBlendMode("ADD")
                slot._rotatingTex = rotatingTex
                local rotAnim = rotatingTex:CreateAnimationGroup()
                rotAnim:SetLooping("REPEAT")
                local rot = rotAnim:CreateAnimation("Rotation")
                rot:SetDegrees(-360)
                rot:SetDuration(6)
                rot:SetOrigin("CENTER", 0, 0)
                rotAnim:Play()
                table.insert(slot._animGroups, rotAnim)

                slot._iconBase = slot:CreateTexture(nil, "BORDER")
                slot._iconBase:SetPoint("CENTER", slot, "CENTER", 0, 0)

                slot.icon = slot:CreateTexture(nil, "ARTWORK")
                slot.icon:SetPoint("CENTER", slot, "CENTER", 0, 0)

                slot._border = slot:CreateTexture(nil, "OVERLAY", nil, 7)
                slot._border:SetPoint("CENTER", slot, "CENTER", 0, 2)

                -- Elevated child frame so the padlock draws above neighboring
                -- slots' oversized swirl/ring textures
                local lockOverlay = CreateFrame("Frame", nil, slot)
                lockOverlay:SetFrameLevel(slot:GetFrameLevel() + 5)
                lockOverlay:SetAllPoints(slot)

                -- "A pick is armed" glow, same recipe as the orb bubble's. Its own frame,
                -- ABOVE the padlock overlay: the slot's background swirl sits under the
                -- quality disc and its border, so tinting that only lit the outer edges.
                local armedOverlay = CreateFrame("Frame", nil, slot)
                armedOverlay:SetFrameLevel(slot:GetFrameLevel() + 8)
                armedOverlay:SetAllPoints(slot)
                local armedGlow = armedOverlay:CreateTexture(nil, "OVERLAY")
                armedGlow:SetPoint("CENTER", slot, "CENTER", 0, 0)
                armedGlow:SetTexture("Interface\\Cooldown\\star4")
                armedGlow:SetBlendMode("ADD")
                armedGlow:SetVertexColor(ARMED_PICK_R, ARMED_PICK_G, ARMED_PICK_B, 0.95)
                armedGlow:Hide()
                slot._armedGlow = armedGlow

                slot._lockTex = lockOverlay:CreateTexture(nil, "OVERLAY")
                slot._lockTex:SetSize(24, 24)
                slot._lockTex:SetPoint("CENTER", slot, "CENTER", 0, 0)
                slot._lockTex:SetTexture(ASSETS .. "lock")
                slot._lockTex:Hide()

                slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                slotButtons[i] = slot
            end
            ApplyPermanentSlotSize(slot, slotSize)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", contextBar, "TOPLEFT", startX + (i - 1) * (slotSize + slotGap), -18)

            local lp = lockedPerks[i]
            local quality = lp and (lp.quality or 0) or 0
            local qc = qualityColors[quality] or qualityColors[0]
            local borderIdx = math.min(quality, 3)
            slot._iconBase:SetTexture(ASSETS .. "perk_quality_" .. borderIdx)
            slot._border:SetTexture(ASSETS .. "perk_border_quality_" .. borderIdx)

            if i > unlockedSlots then
                -- Not unlocked yet: dimmed placeholder with a padlock
                slot._iconBase:SetDesaturated(true)
                slot._iconBase:SetAlpha(0.4)
                slot._border:SetDesaturated(true)
                slot._border:SetAlpha(0.4)
                slot._swirl:SetVertexColor(0.4, 0.4, 0.4, 0.15)
                slot._armedGlow:Hide()
                slot.icon:Hide()
                slot._lockTex:Show()
                slot.lockedSpellId = nil
                slot:SetScript("OnClick", nil)
                slot:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Locked Permanent Slot", 0.6, 0.6, 0.6)
                    GameTooltip:AddLine("Reach the next Soul Ash milestone to unlock this slot.",
                        0.9, 0.9, 0.9, true)
                    GameTooltip:Show()
                end)
            elseif lp then
                slot._iconBase:SetDesaturated(false)
                slot._iconBase:SetAlpha(1)
                slot._border:SetDesaturated(false)
                slot._border:SetAlpha(1)
                slot._lockTex:Hide()
                slot._armedGlow:Hide()
                slot._swirl:SetVertexColor(qc.r, qc.g, qc.b, 0.55)
                local _, _, spellIcon = GetSpellInfo(lp.spellId)
                SetPortraitToTexture(slot.icon, spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
                slot.icon:Show()
                slot.lockedSpellId = lp.spellId

                slot:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if utils and utils.GetSpellDescription then
                        -- Computed description (stat formulas resolved), like the grid tooltips
                        GameTooltip:ClearLines()
                        local name = GetSpellInfo(lp.spellId)
                        GameTooltip:AddLine(name or ("Spell " .. lp.spellId), qc.r, qc.g, qc.b)
                        GameTooltip:AddLine(utils.GetSpellDescription(lp.spellId, 4000, lp.stack or 1), 1, 1, 1, true)
                    else
                        GameTooltip:SetHyperlink("spell:" .. lp.spellId)
                    end
                    GameTooltip:AddLine("Permanent echo", 1, 0.82, 0)
                    GameTooltip:AddLine("Right-click to unlock it.", 0.5, 0.5, 0.5)
                    GameTooltip:Show()
                end)
                slot:SetScript("OnClick", function(self, mouseButton)
                    if mouseButton == "RightButton" and self.lockedSpellId then
                        StaticPopupDialogs["PROJECTEBONHOLD_JOURNAL_UNLOCK_ECHO"] = {
                            text = "Unlock this echo from the permanent slot?",
                            button1 = YES,
                            button2 = NO,
                            OnAccept = function()
                                local service = GetService()
                                if service and service.UnlockPerk then
                                    service.UnlockPerk(self.lockedSpellId)
                                    if service.RequestGrantedPerks then
                                        service.RequestGrantedPerks()
                                    end
                                end
                            end,
                            timeout = 0,
                            whileDead = true,
                            hideOnEscape = true,
                            preferredIndex = 3,
                        }
                        StaticPopup_Show("PROJECTEBONHOLD_JOURNAL_UNLOCK_ECHO")
                    end
                end)
            else
                slot._iconBase:SetDesaturated(false)
                slot._iconBase:SetAlpha(1)
                slot._border:SetDesaturated(false)
                slot._border:SetAlpha(1)
                slot._lockTex:Hide()
                slot.icon:Hide()
                slot.lockedSpellId = nil
                if lockModeActive then
                    -- Same mauve the orb arms with: one "a pick is armed" colour across both.
                    slot._swirl:SetVertexColor(ARMED_PICK_R, ARMED_PICK_G, ARMED_PICK_B, 0.7)
                    slot._armedGlow:Show()
                else
                    slot._swirl:SetVertexColor(1, 1, 1, 0.35)
                    slot._armedGlow:Hide()
                end
                slot:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Permanent Echo Slot", 1, 0.82, 0)
                    GameTooltip:AddLine("Keeps one echo between runs.", 0.9, 0.9, 0.9, true)
                    GameTooltip:AddLine("Click, then pick one of your echoes on the left.", 0.5, 0.5, 0.5, true)
                    GameTooltip:Show()
                end)
                slot:SetScript("OnClick", function(self, mouseButton)
                    if mouseButton == "LeftButton" then
                        lockModeActive = not lockModeActive
                        -- An armed Orb claims the SAME left-click on the same grid,
                        -- so the two selection modes cancel each other: whichever is
                        -- armed last wins instead of leaving one click ambiguous.
                        if lockModeActive and ProjectEbonhold.OrbService then
                            ProjectEbonhold.OrbService.Disarm()
                        end
                        Refresh()
                    end
                end)
            end
            slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
            slot:Show()
        elseif slot then
            slot:Hide()
        end
    end

    -- The Orb of Lost Memories counter sits just past the last permanent slot. Published here
    -- rather than hardcoded on the orb side because the row is rebuilt on every refresh and
    -- both the disc size and the slot count shrink to fit the bar.
    Journal.lastPermanentSlot = slotButtons[totalSlots]
    if ProjectEbonhold.OrbService and ProjectEbonhold.OrbService.EnsureUI then
        ProjectEbonhold.OrbService.EnsureUI()
    end

    return unlockedSlots, totalSlots
end

-- Lock-mode helper bubble: after clicking an empty permanent slot, a
-- GlowBox hugs the RIGHT edge of the My Echoes inset (where the pick
-- happens), floating above the catalog's first column.
local lockAlert
local lockZoneHighlight

-- Gold outline around the My Echoes column, shown for as long as lock mode is
-- armed. The pick can ONLY be made there -- the catalog never repeats echoes
-- you already hold -- so the eye has to be sent left instead of to the much
-- larger catalog the bubble sits over. Same recipe as the guided tour's zone
-- highlight (modules/guidedTour) so both read as the same "look here" marker.
local function EnsureLockZoneHighlight()
    if lockZoneHighlight then return lockZoneHighlight end
    local hl = CreateFrame("Frame", nil, journalFrame)
    hl:SetFrameStrata("HIGH")
    -- Under lockAlert's +60 so the bubble always draws over the outline
    hl:SetFrameLevel(journalFrame:GetFrameLevel() + 50)
    hl:EnableMouse(false)

    local fill = hl:CreateTexture(nil, "BACKGROUND")
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetVertexColor(ARMED_PICK_R, ARMED_PICK_G, ARMED_PICK_B, 0.10)
    fill:SetAllPoints(hl)

    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local t = hl:CreateTexture(nil, "BORDER")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(ARMED_PICK_R, ARMED_PICK_G, ARMED_PICK_B, 0.9)
        t:SetPoint(edge[1]); t:SetPoint(edge[2])
        if edge[3] then t:SetWidth(edge[3]) else t:SetHeight(edge[4]) end
    end

    lockZoneHighlight = hl
    return hl
end

local function UpdateLockAlert()
    if not lockModeActive or currentTab ~= TAB_ALL then
        if lockAlert then lockAlert:Hide() end
        if lockZoneHighlight then lockZoneHighlight:Hide() end
        return
    end

    if not lockAlert then
        lockAlert = CreateFrame("Frame", nil, journalFrame, "GlowBoxTemplate")
        lockAlert:SetWidth(220)
        lockAlert:SetFrameStrata("HIGH")
        lockAlert:SetFrameLevel(journalFrame:GetFrameLevel() + 60)
        lockAlert:EnableMouse(false)
        lockAlert:SetPoint("TOPLEFT", myRunInset or journalFrame, "TOPRIGHT", 8, -4)

        lockAlert.Title = lockAlert:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockAlert.Title:SetPoint("TOPLEFT", 16, -14)
        lockAlert.Title:SetPoint("TOPRIGHT", -16, -14)
        lockAlert.Title:SetJustifyH("LEFT")
        lockAlert.Title:SetTextColor(1, 0.82, 0)
        lockAlert.Title:SetText("Lock an Echo")

        lockAlert.Text = lockAlert:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
        lockAlert.Text:SetJustifyV("TOP")
        lockAlert.Text:SetPoint("TOPLEFT", lockAlert.Title, "BOTTOMLEFT", 0, -8)
        lockAlert.Text:SetWidth(188)
        lockAlert.Text:SetText(
            "Pick one of your echoes from the |cffffd700left|r to lock it into " ..
            "the slot. It becomes |cffffd700permanent|r and stays across " ..
            "runs.\n\nClick the slot again to cancel.")

        lockAlert:SetHeight(14 + lockAlert.Title:GetStringHeight() + 8
            + lockAlert.Text:GetStringHeight() + 16)
    end

    -- Outline the panel the pick has to come from. Anchored to the inset (not
    -- the scroll frame) so it wraps the whole column, borders included.
    if myRunInset and myRunInset:IsShown() then
        local hl = EnsureLockZoneHighlight()
        -- Reasserted here, like the insets do: reparenting journalFrame into
        -- CollectionsJournal resets its children's frame levels.
        hl:SetFrameLevel(journalFrame:GetFrameLevel() + 50)
        hl:ClearAllPoints()
        hl:SetPoint("TOPLEFT", myRunInset, "TOPLEFT", -4, 4)
        hl:SetPoint("BOTTOMRIGHT", myRunInset, "BOTTOMRIGHT", 4, -4)
        hl:Show()
    elseif lockZoneHighlight then
        lockZoneHighlight:Hide()
    end

    lockAlert:Show()
end

-- Builder-mode helper bubble: while a wishlist draft is open, a GlowBox
-- alert floats at the window's right side (next to the catalog, which is
-- the picker) with the how-to and a live echo/stack count -- instead of the
-- old plain text line squeezed into the context bar.
local builderAlert

local function UpdateBuilderAlert()
    if not builderDraft or currentTab ~= TAB_ALL then
        if builderAlert then builderAlert:Hide() end
        return
    end

    if not builderAlert then
        builderAlert = CreateFrame("Frame", nil, journalFrame, "GlowBoxTemplate")
        builderAlert:SetWidth(220)
        builderAlert:SetFrameStrata("HIGH")
        builderAlert:SetFrameLevel(journalFrame:GetFrameLevel() + 60)
        builderAlert:EnableMouse(false)
        builderAlert:SetPoint("TOPLEFT", journalFrame, "TOPRIGHT", 18, -140)

        builderAlert.Title = builderAlert:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        builderAlert.Title:SetPoint("TOPLEFT", 16, -14)
        builderAlert.Title:SetPoint("TOPRIGHT", -16, -14)
        builderAlert.Title:SetJustifyH("LEFT")
        builderAlert.Title:SetTextColor(1, 0.82, 0)

        builderAlert.Text = builderAlert:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
        builderAlert.Text:SetJustifyV("TOP")
        builderAlert.Text:SetPoint("TOPLEFT", builderAlert.Title, "BOTTOMLEFT", 0, -8)
        builderAlert.Text:SetWidth(188)
        builderAlert.Text:SetText(
            "Click echoes in the catalog to add them to this wishlist.\n\n" ..
            "|cffffd700Left-click|r adds a stack.\n|cffffd700Right-click|r removes one.\n\n" ..
            "Hit |cffffd700Done|r up top when you are finished.")

        builderAlert.Count = builderAlert:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        builderAlert.Count:SetPoint("TOPLEFT", builderAlert.Text, "BOTTOMLEFT", 0, -10)
    end

    builderAlert.Title:SetText((builderDraft.editIndex and "Editing \"" or "Building \"")
        .. builderDraft.name .. "\"")
    builderAlert.Count:SetText(string.format("|cffffffff%d|r echo(es), |cffffffff%d/%d|r stacks",
        DraftCount(), DraftTotalStacks(), MAX_RUN_ECHOES))
    -- both helper bubbles live on the right edge; stack below the lock-mode
    -- bubble when it is showing (UpdateLockAlert always runs first in Refresh)
    builderAlert:ClearAllPoints()
    if lockAlert and lockAlert:IsShown() then
        builderAlert:SetPoint("TOPLEFT", lockAlert, "BOTTOMLEFT", 0, -12)
    else
        builderAlert:SetPoint("TOPLEFT", journalFrame, "TOPRIGHT", 18, -140)
    end
    builderAlert:SetHeight(14 + builderAlert.Title:GetStringHeight() + 8
        + builderAlert.Text:GetStringHeight() + 10 + builderAlert.Count:GetStringHeight() + 16)
    builderAlert:Show()
end

local function UpdateContextBar(ownedCount, totalCount, itemCount)
    if contextBar.loadoutControls then
        if currentTab == TAB_LOADOUTS then
            contextBar.loadoutControls:Show()
            local lc = contextBar.loadoutControls
            if loadoutView == "mine" then
                PanelTemplates_SelectTab(lc.mineBtn); PanelTemplates_DeselectTab(lc.commBtn)
            else
                PanelTemplates_SelectTab(lc.commBtn); PanelTemplates_DeselectTab(lc.mineBtn)
            end
        else
            contextBar.loadoutControls:Hide()
        end
    end
    if currentTab == TAB_LOADOUTS then
        contextBar:SetHeight(26) -- single button row; the class filter sits by the search bar
        contextBar.statsText:Hide()
        contextBar.slotsLabel:Hide()
        contextBar.buildText:Hide() -- the build line/slots only belong on the merged Echoes tab
        for _, slot in ipairs(slotButtons) do slot:Hide() end
        return
    end

    -- Merged Echoes tab: permanent-slots row up top; the active-build line
    -- that used to live here moved down to the My Run panel's loadout
    -- footer (see UpdateLoadoutFooter) alongside the slot switcher/create/
    -- import controls.
    contextBar.buildText:Hide()

    -- Height must clear whichever needs more room: the slots themselves, the
    -- lock-mode hint below them, OR the loadout row + search/filter row
    -- stacked to their right (now living in this same zone -- see Refresh),
    -- top-aligned with the slots instead of centered lower. The builder
    -- how-to no longer reserves extra height here -- it lives in its own
    -- side bubble (UpdateBuilderAlert).
    contextBar:SetHeight(85)
    contextBar.slotsLabel:Hide()

    UpdatePermanentSlots()

    -- Lock-mode and builder instructions both live in side GlowBox bubbles
    -- now, not in this bar's stats line.
    contextBar.statsText:Hide()

    UpdateLockAlert()
    UpdateBuilderAlert()
end

-- ── First-visit intro overlays (one per tab, acknowledged with "Got it") ─────
local function BuildIntroOverlay(dbKey, iconPath, titleText, bodyText)
    local o = CreateFrame("Frame", nil, journalFrame)
    -- Leave the title bar and close button reachable above the overlay
    o:SetPoint("TOPLEFT", journalFrame, "TOPLEFT", 8, -30)
    o:SetPoint("BOTTOMRIGHT", journalFrame, "BOTTOMRIGHT", -8, 8)
    o:SetFrameLevel(journalFrame:GetFrameLevel() + 50)
    o:EnableMouse(true)
    o:EnableMouseWheel(true)
    o:SetScript("OnMouseWheel", function() end)
    -- Solid black fill: the dialog-box texture is grey-ish even tinted black
    o:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    o:SetBackdropColor(0, 0, 0, 0.97)

    local icon = o:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(iconPath)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetSize(48, 48)
    icon:SetPoint("TOP", o, "TOP", 0, -36)

    local title = o:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -10)
    title:SetTextColor(1, 0.82, 0)
    title:SetText(titleText)

    local msg = o:CreateFontString(nil, "OVERLAY")
    msg:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    msg:SetPoint("TOP", title, "BOTTOM", 0, -18)
    msg:SetWidth(400)
    msg:SetJustifyH("CENTER")
    msg:SetWordWrap(true)
    msg:SetSpacing(3)
    msg:SetTextColor(1, 1, 1)
    msg:SetText(bodyText)

    local okBtn = utils.CreateSimpleCustomButton(o, "Got it", function()
        ProjectEbonholdDB = ProjectEbonholdDB or {}
        ProjectEbonholdDB[dbKey] = true
        o:Hide()
    end, 120, 28)
    okBtn:SetPoint("BOTTOM", o, "BOTTOM", 0, 24)

    return o
end

local MY_ECHOES_INTRO =
    "Every level up during a |cffffd700run|r offers you a new echo. These powers " ..
    "are temporary: they fade when the run ends.\n\n" ..
    "The slots above are |cffffd700Permanent Echo Slots|r. Lock one of your echoes " ..
    "into a slot and it stays with you |cffffd700across runs|r, even through death. " ..
    "You unlock more slots by reaching |cffffd700Soul Ash milestones|r in your Skill Tree.\n\n" ..
    "Click an empty slot, then pick one of your echoes below to make it permanent.\n" ..
    "Right-click a locked echo to free the slot.\n\n" ..
    "Playing with a |cffffd700build|r (see the Loadouts tab)? Its missing echoes " ..
    "appear |cff808080greyed out|r below until you collect them."

-- ── Guided tour (merged Echoes tab) ──────────────────────────────────────────
-- Zone-by-zone walkthrough (next/next/got-it) instead of one wall-of-text
-- overlay, built on the shared GlowBox tour factory (modules/guidedTour):
-- each step drops a gold highlight on one UI zone and a GlowBox beside it.
-- Closing with the X or finishing both mark it seen.
-- (MY_ECHOES_INTRO above and LOADOUTS_INTRO below belong to the dead
-- TAB_MY_RUN/TAB_LOADOUTS paths and never show.)
local echoesTour = ProjectEbonhold.GuidedTour.Create({
    parent = function() return journalFrame end,
    dbKey = "seenEchoesTabIntro",
    steps = function()
        return {
            {
                title = "Permanent Echo Slots",
                text = "Lock an echo into one of these slots and it stays with you " ..
                    "|cffffd700across runs|r, even through death. More slots unlock at " ..
                    "Soul Ash milestones in your Skill Tree.",
                zone = function() return slotButtons[1], slotButtons[#slotButtons] end,
                boxAnchor = { "TOPLEFT", "BOTTOMLEFT", 0, -12 },
            },
            {
                title = "Orb of Lost Memories",
                text = "An |cffffd700Orb of Lost Memories|r lets you forget an echo you " ..
                    "already own and draw a new choice in its place. Click the orb, then " ..
                    "click the echo to forget: one stack of it is removed and a fresh " ..
                    "draw opens." ..
                    "\n\n" ..
                    "Your run's |cffff8080reroll, freeze and banish|r do not apply to that " ..
                    "draw: spending |cffffd700one more orb|r on the choice screen is what " ..
                    "redraws it. Permanent echoes cannot be forgotten." ..
                    "\n\n" ..
                    "Spend |cffffd700more than one orb|r on the same echo to raise the " ..
                    "chance the replacement comes back at a higher quality." ..
                    "\n\n" ..
                    -- The bubble is on screen from the very first orb, long before the player
                    -- has a build worth refining, so the "what is this for" answer lives here
                    -- rather than in its tooltip: it is read once, at the right moment.
                    "|cff9ec8ffWorth keeping for level 80|r: on a build you are refining, " ..
                    "each orb trades an echo that no longer fits for a fresh draw." ..
                    "\n\n" ..
                    "Earned from |cffffd700Prestige|r, |cffffd700Daily Dungeons|r, " ..
                    "|cffffd700Weekly Raids|r, |cffffd700Daily Runs (1-80)|r and " ..
                    "|cffffd700Callboard Quests|r - the dailies and weeklies are taken " ..
                    "from |cffffd700Maerys, the Ashen Archivist|r.",
                -- Anchored on the bubble itself, which sits just right of the last permanent
                -- slot. Nil until the orb module has built it, and a step whose zone resolves
                -- to nil is skipped by the tour rather than stranding the highlight.
                zone = function() return _G["EbonholdOrbBubble"] end,
                boxAnchor = { "TOPLEFT", "BOTTOMLEFT", 0, -12 },
            },
            {
                title = "My Echoes",
                text = "Every echo you are holding in the |cffffd700current run|r. " ..
                    "Echoes are temporary powers picked as you level up; they fade " ..
                    "when the run ends.\n\nRight-click a locked echo to free its slot.",
                zone = function() return myRunInset end,
                boxAnchor = { "CENTER", "CENTER", 0, 0 },
            },
            {
                title = "All Echoes",
                text = "The complete catalog. Echoes you currently hold are not " ..
                    "repeated here: they already sit on the left.\n\nEchoes with a " ..
                    "|cffffd700book badge|r are sealed inside Tomes: greyed until you " ..
                    "loot and learn their tome, then permanently yours.",
                zone = function() return catalogInset end,
                boxAnchor = { "CENTER", "CENTER", 0, 0 },
            },
            {
                title = "Loadouts",
                text = "This menu manages your builds. |cff60a0e0Saved Builds|r are " ..
                    "snapshots, and they are a |cffffd700level 80|r feature: activate " ..
                    "one there to swap to it outright. While you level, every echo you " ..
                    "are offered is drawn at random. A saved build does nothing " ..
                    "until you reach 80.\n\n|cffa080e0Wishlists|r are for |cffffd700designing|r: " ..
                    "the echoes you wish to collect, assembled into your dream build. " ..
                    "Create one with |cffffd700New Wishlist|r, pick its echoes in the " ..
                    "catalog, then |cffffd700Done|r. While it is active, its echoes " ..
                    "are highlighted in your draws to guide you toward it.",
                zone = function() return loadoutDD end,
                boxAnchor = { "TOPRIGHT", "BOTTOMRIGHT", 0, -12 },
            },
            {
                title = "Search & Filters",
                text = "Search the catalog by name or effect. Filter it by " ..
                    "|cffffd700quality|r or |cffffd700family|r; the " ..
                    "|cffffd700Tomes|r submenu narrows it to tome echoes: all " ..
                    "of them, only the ones you know, or those you have enabled " ..
                    "or disabled.\n\n|cffffd700My class only|r is on by default. " ..
                    "Untick it to browse every class's echoes.",
                zone = function() return searchBox, filterButton end,
                boxAnchor = { "TOPRIGHT", "BOTTOMRIGHT", 0, -12 },
            },
        }
    end,
})

local LOADOUTS_INTRO =
    "Builds come in two kinds:\n\n" ..
    "|cff60a0e0Saved Builds|r are |cffffd700snapshots|r of echoes you actually had: " ..
    "at |cffffd700level 80|r, hit |cffffd700Save Build|r on a slot to freeze your " ..
    "current echoes (stacks and locks included). They are a |cffffd700level 80|r " ..
    "feature through and through: activating one there replaces all your echoes " ..
    "with it, so you can swap freely between the builds you have finished. They " ..
    "do nothing while you level: the climb to 80 is a fresh run every time, and " ..
    "every echo you are offered is drawn at random. 3 slots are free; 7 more can " ..
    "be unlocked with gold, account-wide.\n\n" ..
    "|cffa080e0Echo Wishlist|r builds are |cffffd700goals|r you design yourself with " ..
    "|cffffd700New Wishlist|r, paste with |cffffd700Import|r, or copy from the " ..
    "|cffffd700Community|r view (unlimited). While one is active, its echoes are " ..
    "|cffffd700highlighted|r in your draws (and can be auto-picked), and the " ..
    "missing ones show greyed out in My Echoes.\n\n" ..
    "Watch the |cffaaaaaa(X/Y)|r counter fill up; once you finish a design at " ..
    "|cffffd700level 80|r, save it as a snapshot to keep it and swap to it whenever " ..
    "you like."

local myEchoesIntro, loadoutsIntro

local function UpdateIntroOverlays()
    ProjectEbonholdDB = ProjectEbonholdDB or {}

    if currentTab == TAB_MY_RUN and not ProjectEbonholdDB.seenMyEchoesIntro then
        myEchoesIntro = myEchoesIntro or BuildIntroOverlay("seenMyEchoesIntro",
            "Interface\\Icons\\Spell_Shadow_SoulGem", "Your Echoes", MY_ECHOES_INTRO)
        myEchoesIntro:Show()
    elseif myEchoesIntro then
        myEchoesIntro:Hide()
    end

    -- Fresh db key ("seenEchoesTabIntro"): the merged two-column tab with
    -- the loadout dropdown replaced the old All Echoes view, so players who
    -- dismissed the old intro get the new guided tour once. Leaving the tab
    -- mid-tour hides it WITHOUT marking it seen -- it resumes from step 1
    -- next time the tab opens. Never shown alongside the wishlist builder or
    -- lock mode: their layouts move/hide the tour's anchor zones, leaving
    -- the gold highlight stranded over whatever ended up underneath.
    if currentTab == TAB_ALL and not ProjectEbonholdDB.seenEchoesTabIntro
        and not builderDraft and not lockModeActive then
        echoesTour:Start()
    else
        -- Unconditional, NOT "elseif echoesTour:IsActive()": if the tour's step
        -- state ever desyncs from its frames (an error thrown mid-step, a Stop
        -- that never ran), IsActive() reports false and the gold zone highlight
        -- is left stranded over the catalog -- exactly where lock mode must NOT
        -- point. Stop(false) is idempotent and never burns the once-flag.
        echoesTour:Stop(false)
    end

    -- Fresh db key ("seenBuildSlotsIntro"): the build-slot rework replaced the
    -- old library, so players who dismissed the old intro see the new one once
    if currentTab == TAB_LOADOUTS and not ProjectEbonholdDB.seenBuildSlotsIntro then
        loadoutsIntro = loadoutsIntro or BuildIntroOverlay("seenBuildSlotsIntro",
            "Interface\\Icons\\INV_Scroll_03", "Echo Builds", LOADOUTS_INTRO)
        loadoutsIntro:Show()
    elseif loadoutsIntro then
        loadoutsIntro:Hide()
    end
end

-- ── Loadout footer (My Run panel) ────────────────────────────────────────────
-- Custom list menu modeled on the Transmogrify outfit dropdown
-- (WardrobeOutfitFrame): the dropdown's button toggles this frame instead of
-- a generic UIDropDownMenu. Two visually distinct sections -- Saved Builds
-- (server snapshot slots: filled = activate, empty = start a wishlist
-- there, locked = buy) and Wishlists (designed builds, unlimited pool
-- beyond the snapshot slots) -- plus, like the outfit list's green "New
-- Outfit" row, New Wishlist and Import live INSIDE the menu (the footer's
-- physical buttons only exist as Done/Cancel while a draft is open).
local loadoutMenu

local LOADOUT_MENU_ROW_H = 24
local LOADOUT_MENU_HIDE_DELAY = 2 -- seconds without the mouse before auto-close

-- Per-row gear flyout (same idea as the outfit manager's little cog):
-- Save / Export / Delete for an existing build.
local gearMenuHolder
local function OpenLoadoutRowMenu(opts)
    gearMenuHolder = gearMenuHolder
        or CreateFrame("Frame", "ProjectEbonholdLoadoutRowGearMenu", UIParent, "UIDropDownMenuTemplate")
    local items = {
        { text = opts.name, isTitle = true, notCheckable = true },
    }
    if opts.edit then
        table.insert(items, { text = "Edit", notCheckable = true, func = opts.edit })
    end
    if opts.save then
        table.insert(items, { text = "Save current run here", notCheckable = true, func = opts.save })
    end
    -- Recoverable wishlist: the one action it exists for. Greyed with its
    -- reason when there is nowhere to put it, rather than failing on click.
    if opts.recover then
        if FirstFreeBuildSlot() then
            table.insert(items, { text = "|cffffd700Recover build|r",
                notCheckable = true, func = opts.recover })
        else
            table.insert(items, { text = "|cff808080Recover (no free build slot)|r",
                notCheckable = true, disabled = true })
        end
    end
    table.insert(items, { text = "Export", notCheckable = true, func = opts.export })
    if opts.deactivate then
        table.insert(items, { text = "Deactivate", notCheckable = true, func = opts.deactivate })
    end
    if opts.delete then
        table.insert(items, { text = "|cffff4040Delete|r", notCheckable = true, func = opts.delete })
    else
        -- The server refuses deleting the ACTIVE build -- surface the rule
        -- instead of a click that silently fails (Deactivate first).
        table.insert(items, { text = "|cff808080Delete (deactivate first)|r",
            notCheckable = true, disabled = true })
    end
    EasyMenu(items, gearMenuHolder, "cursor", 0, 0, "MENU")
end

local function GetLoadoutMenuRow(i)
    local row = loadoutMenu.rows[i]
    if row then return row end

    row = CreateFrame("Button", nil, loadoutMenu)
    row:SetHeight(LOADOUT_MENU_ROW_H)
    if i == 1 then
        row:SetPoint("TOPLEFT", loadoutMenu, "TOPLEFT", 12, -12)
        row:SetPoint("TOPRIGHT", loadoutMenu, "TOPRIGHT", -12, -12)
    else
        row:SetPoint("TOPLEFT", loadoutMenu.rows[i - 1], "BOTTOMLEFT", 0, 0)
        row:SetPoint("TOPRIGHT", loadoutMenu.rows[i - 1], "BOTTOMRIGHT", 0, 0)
    end

    row.Check = row:CreateTexture(nil, "ARTWORK")
    row.Check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.Check:SetSize(16, 16)
    row.Check:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT", row, "LEFT", 16, 0)

    row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Text:SetPoint("LEFT", row, "LEFT", 34, 0)
    row.Text:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    row.Text:SetJustifyH("LEFT")
    row.Text:SetWordWrap(false)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(row)

    -- Gear icon (same cog texture the outfit manager's rows use); dim until
    -- hovered, shown by the menu's OnUpdate for rows that carry an onGear
    -- action so it's discoverable without needing to find the row first.
    row.EditButton = CreateFrame("Button", nil, row)
    row.EditButton:SetSize(16, 16)
    row.EditButton:SetPoint("RIGHT", row, "RIGHT", -1, 0)
    row.EditButton.tex = row.EditButton:CreateTexture(nil, "ARTWORK")
    row.EditButton.tex:SetAllPoints()
    row.EditButton.tex:SetTexture("Interface\\WorldMap\\GEAR_64GREY")
    row.EditButton.tex:SetAlpha(0.5)
    row.EditButton:SetScript("OnEnter", function(self) self.tex:SetAlpha(1) end)
    row.EditButton:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.5) end)
    row.EditButton:SetScript("OnClick", function(self)
        PlaySound("igMainMenuOptionCheckBoxOn")
        local r = self:GetParent()
        if r.onGear then r.onGear() end
    end)
    row.EditButton:Hide()

    row:SetScript("OnClick", function(self)
        if not self.onClick then return end
        PlaySound("igMainMenuOptionCheckBoxOn")
        loadoutMenu:Hide()
        self.onClick()
    end)

    loadoutMenu.rows[i] = row
    return row
end

local function CreateLoadoutMenu()
    -- Parented to journalFrame so it dies with the window, but on a higher
    -- strata so it floats over both panels like a dropdown list would.
    -- NOT "ProjectEbonholdLoadoutMenu" -- the dead Loadouts-tab path already
    -- owns that global name for its EasyMenu holder.
    loadoutMenu = CreateFrame("Frame", "ProjectEbonholdLoadoutListMenu", journalFrame)
    loadoutMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    loadoutMenu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    loadoutMenu:EnableMouse(true)
    loadoutMenu:Hide()
    loadoutMenu.rows = {}

    -- Same auto-close idea as WardrobeOutfitFrame's hide countdown: linger
    -- while hovered (or while a row's gear flyout is open), fade away a
    -- moment after the mouse wanders off. Also drives the per-row gear
    -- buttons (visible whenever a row carries an onGear action).
    loadoutMenu:SetScript("OnUpdate", function(self, elapsed)
        local gearFlyoutOpen = DropDownList1 and DropDownList1:IsShown()
        if self:IsMouseOver(10, -10, -10, 10) or gearFlyoutOpen then
            self.timer = LOADOUT_MENU_HIDE_DELAY
        else
            self.timer = (self.timer or LOADOUT_MENU_HIDE_DELAY) - elapsed
            if self.timer <= 0 then self:Hide() end
        end
        for _, row in ipairs(self.rows) do
            if row:IsShown() and row.onGear then
                row.EditButton:Show()
            else
                row.EditButton:Hide()
            end
        end
    end)
    loadoutMenu:SetScript("OnShow", function(self) self.timer = LOADOUT_MENU_HIDE_DELAY end)
end

local function UpdateLoadoutMenu()
    local svc = GetService()
    if not svc or not loadoutMenu then return end
    local serverSlots = (svc.GetServerBuildSlots and svc.GetServerBuildSlots()) or {}
    local maxSlots = (svc.GetServerMaxSlots and svc.GetServerMaxSlots()) or 5
    local unlocked = (svc.GetServerUnlockedSlots and svc.GetServerUnlockedSlots()) or maxSlots
    local activeSlot = (svc.GetServerActiveSlot and svc.GetServerActiveSlot()) or 0

    local idx, maxTextW = 0, 0
    -- cfg: text, [icon], [checked], [grey], [header], [onClick]
    local function AddRow(cfg)
        idx = idx + 1
        local row = GetLoadoutMenuRow(idx)
        row.Text:SetText(cfg.text)
        if cfg.header then
            row.Text:SetPoint("LEFT", row, "LEFT", 0, 0)
            row:EnableMouse(false)
        else
            row.Text:SetPoint("LEFT", row, "LEFT", 34, 0)
            row:EnableMouse(true)
        end
        if cfg.grey then
            row.Text:SetTextColor(0.5, 0.5, 0.5)
        elseif cfg.header then
            row.Text:SetTextColor(1, 0.82, 0)
        else
            row.Text:SetTextColor(1, 1, 1)
        end
        if cfg.icon then
            row.Icon:SetTexture(cfg.icon)
            row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.Icon:Show()
        else
            row.Icon:Hide()
        end
        if cfg.checked then row.Check:Show() else row.Check:Hide() end
        row.onClick = cfg.onClick
        row.onGear = cfg.gear
        row.EditButton:Hide() -- (re)shown by the menu's OnUpdate once cfg.gear is set
        row:Show()
        maxTextW = math.max(maxTextW, row.Text:GetStringWidth() + (cfg.header and 0 or 34))
    end

    -- Same decision logic + confirmation popups as the old Loadouts rows
    -- (ServerSlotClickAction): wishlists/designed builds (verified == false)
    -- activate at ANY level while leveling -- only at 80 is there nothing
    -- left for them to guide; snapshots stay gated to levels 1 (arm) and 80
    -- (full swap, with its confirm popup).
    local function AddActivateRow(text, slot, icon, gear, verified)
        AddRow({
            text = text, icon = icon, checked = (activeSlot == slot), gear = gear,
            onClick = function()
                local action = ServerSlotClickAction(slot, verified)
                if action == "none" then return end
                pendingServerSlot = slot
                if action == "designed80" then
                    pendingServerSlot = nil
                    UIErrorsFrame:AddMessage(
                        "Designed builds only guide your draws while leveling, and there is nothing left to draw at level 80. Only snapshots can be applied here.",
                        1, 0.2, 0.2)
                elseif action == "switch" then
                    StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_SWITCH", text)
                elseif action == "activate" then
                    if verified == false then
                        -- Only designed builds reach "activate": snapshots are
                        -- level-80 only. Dropping one mid-run lasts until 80.
                        local level = UnitLevel("player") or 1
                        local active = (level < 80) and ActiveSnapshotName() or nil
                        local warn = ""
                        if active then
                            warn = string.format(
                                "\n\n|cffff2020WARNING:|r |cffff6060this replaces your saved build |r|cffffd700%s|r|cffff6060. A saved build can only be turned back on at level 80, so you will be without one until then.|r",
                                active)
                        end
                        StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_ACTIVATE_DESIGNED", text, warn)
                    end
                else
                    pendingServerSlot = nil
                    UIErrorsFrame:AddMessage("Saved builds can only be activated at level 80. While you level, every echo you are offered is drawn at random.", 1, 0.2, 0.2)
                end
            end,
        })
    end

    -- Gear flyout actions for an existing build row. Save (overwrite with
    -- the current run) only applies to snapshot slots and shares the old
    -- Save Build button's level-80 server gate. Edit (reopen in the builder,
    -- the old Design button's path) only applies to designed content
    -- (verified == false), wherever it is stored. The ACTIVE build offers
    -- Deactivate instead of Delete -- the server refuses deleting it.
    local function GearFor(slot, stored, name, isSnapshot, verified)
        local isActive = (activeSlot == slot)
        return function()
            OpenLoadoutRowMenu({
                name = name,
                edit = (verified == false) and function()
                    -- Designs in the unlimited pool re-upload in place; a
                    -- legacy design stored in a snapshot slot re-saves as a
                    -- NEW design (the old row can then be deleted).
                    Journal.EditLoadout(stored, nil, slot > maxSlots and slot or 0)
                end or nil,
                save = isSnapshot and function()
                    if (UnitLevel("player") or 1) < 80 then
                        UIErrorsFrame:AddMessage("You can only save a build snapshot at level 80.", 1, 0.2, 0.2)
                        return
                    end
                    pendingServerSlot = slot
                    StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_OVERWRITE", name)
                end or nil,
                -- Flagged server side: this wishlist stands for a build the
                -- player really owned, so it can move back into a build slot.
                recover = (stored.toRecover == true) and function()
                    pendingServerSlot = slot
                    StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_RECOVER", name)
                end or nil,
                export = function()
                    if svc.ExportEchoLoadout then
                        StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_EXPORT", nil, nil,
                            svc.ExportEchoLoadout(stored))
                    end
                end,
                deactivate = isActive and function()
                    svc.ActivateServerBuildSlot(0) -- slot 0 = deactivate, any level
                end or nil,
                delete = (not isActive) and function()
                    pendingServerSlot = slot
                    StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_DELETE", name)
                end or nil,
            })
        end
    end

    -- ── Saved Builds: the gold-purchasable server snapshot slots ──
    AddRow({ text = "Saved Builds", header = true })
    for slot = 1, maxSlots do
        local stored = serverSlots[slot]
        local isLocked = slot > unlocked
        if isLocked then
            local cost = (svc.GetServerSlotCostGold and svc.GetServerSlotCostGold(slot)) or 0
            local purchasable = slot == unlocked + 1
            AddRow({
                text = purchasable and string.format("Unlock slot %d (%dg)", slot, cost)
                    or ("Locked slot " .. slot),
                icon = ASSETS .. "lock",
                grey = not purchasable,
                onClick = purchasable and function()
                    StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_UNLOCK", slot, tostring(cost))
                end or nil,
            })
        elseif stored then
            local name = stored.name ~= "" and stored.name or ("Build " .. slot)
            -- verified normalized to a real boolean: an imported/designed
            -- build CAN sit in a snapshot slot, and ServerSlotClickAction
            -- tests `verified == false` (nil would slip through as snapshot)
            local verified = stored.verified and true or false
            AddActivateRow(name, slot, "Interface\\Icons\\Spell_Shadow_SoulGem",
                GearFor(slot, stored, name, true, verified), verified)
        else
            -- Empty snapshot slot: SAVE the current run's echoes into it
            -- (name prompt -> SaveServerBuildSlot; level-80-only feature
            -- server-side, same gate the old Save Build button had).
            -- Wishlist creation is a different thing and lives on the New
            -- Wishlist row below.
            AddRow({
                text = string.format("Empty slot %d |cff808080(save your run)|r", slot),
                onClick = function()
                    if (UnitLevel("player") or 1) < 80 then
                        UIErrorsFrame:AddMessage("You can only save a build snapshot at level 80.", 1, 0.2, 0.2)
                        return
                    end
                    -- First build ever: arm it automatically once it lands
                    -- (see UpdateLoadoutFooter)
                    autoActivateFirstBuild = autoActivateFirstBuild or not HasAnyBuild()
                    pendingServerSlot = slot
                    StaticPopup_Show("PROJECTEBONHOLD_BUILDSLOT_SAVE", slot)
                end,
            })
        end
    end

    -- ── Wishlists: designed builds beyond the snapshot slots (unlimited
    -- pool, ids assigned by the server on upload/import) ──
    AddRow({ text = "Wishlists", header = true })
    local designedIds = {}
    for slot in pairs(serverSlots) do
        if slot > maxSlots then table.insert(designedIds, slot) end
    end
    table.sort(designedIds)
    for _, slot in ipairs(designedIds) do
        local stored = serverSlots[slot]
        local name = stored.name ~= "" and stored.name or ("Wishlist " .. slot)
        -- The gear menu and the popups keep the bare name; only the row
        -- label carries the badge.
        local label = name
        if stored.toRecover then label = name .. " |cffffd700(recoverable)|r" end
        AddActivateRow(label, slot, "Interface\\Icons\\INV_Scroll_03",
            GearFor(slot, stored, name, false, false), false)
    end

    AddRow({
        text = "|cff20ff20New Wishlist|r",
        icon = "Interface\\AddOns\\ProjectEbonhold\\modules\\collections\\Interface\\PaperDollInfoFrame\\Character-Plus",
        onClick = function()
            pendingWishlistTargetSlot = nil
            StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_NAME")
        end,
    })
    AddRow({
        text = "Import",
        icon = "Interface\\Icons\\INV_Letter_15",
        onClick = function()
            StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_IMPORT")
        end,
    })

    for i = idx + 1, #loadoutMenu.rows do
        loadoutMenu.rows[i]:Hide()
    end

    -- maxTextW already carries the 34px icon indent; the row's own gutters
    -- (12px frame padding each side, 18px reserved on the right for the gear
    -- button) have to be added on top or the longest label clips -- which is
    -- exactly what the old 280px ceiling did to "Empty slot N (save your run)".
    loadoutMenu:SetWidth(math.max(210, math.min(430, maxTextW + 44)) + 24)
    loadoutMenu:SetHeight(idx * LOADOUT_MENU_ROW_H + 24)
end

local function ToggleLoadoutMenu()
    if loadoutMenu and loadoutMenu:IsShown() then
        loadoutMenu:Hide()
        return
    end
    if not loadoutMenu then CreateLoadoutMenu() end
    UpdateLoadoutMenu()
    loadoutMenu:ClearAllPoints()
    -- Right-aligned under the dropdown (whose visible right edge sits ~14px
    -- inside its frame because of the template's transparent wing art).
    loadoutMenu:SetPoint("TOPRIGHT", loadoutDD, "BOTTOMRIGHT", -8, 8)
    loadoutMenu:Show()
end

local function UpdateLoadoutFooter()
    if not loadoutFooter then return end

    if builderDraft then
        -- A wishlist draft is open: the (otherwise hidden) footer buttons
        -- appear as Done/Cancel -- everything else (New Wishlist, Import,
        -- switching) lives inside the dropdown's menu and stays unreachable
        -- while building.
        loadoutDD:Hide()
        if loadoutMenu then loadoutMenu:Hide() end
        loadoutPrimaryBtn:SetText("Done")
        loadoutPrimaryBtn:SetScript("OnClick", function() Journal.FinishLoadoutBuilder() end)
        loadoutPrimaryBtn:Show()
        loadoutSecondaryBtn:SetText("Cancel")
        loadoutSecondaryBtn:SetScript("OnClick", function() Journal.CancelLoadoutBuilder() end)
        loadoutSecondaryBtn:Show()
        return
    end

    loadoutDD:Show()
    loadoutPrimaryBtn:Hide()
    loadoutSecondaryBtn:Hide()

    -- First-ever build was just created (snapshot, wishlist or import): arm it
    -- as soon as the server's slot list confirms it, instead of leaving the
    -- dropdown on "Select a loadout". Wishlists go through the same path, since
    -- their slot id only exists once the server has assigned it.
    if autoActivateFirstBuild then
        local svc = GetService()
        local slots = svc and svc.GetServerBuildSlots and svc.GetServerBuildSlots() or {}
        local only, count = nil, 0
        for s in pairs(slots) do count = count + 1; only = s end
        if count > 1 then
            autoActivateFirstBuild = nil -- not their first build after all
        elseif count == 1 and (svc.GetServerActiveSlot and svc.GetServerActiveSlot() or 0) == 0 then
            if not svc.CanActivateServerBuildSlot or svc.CanActivateServerBuildSlot() then
                svc.ActivateServerBuildSlot(only)
            end
            autoActivateFirstBuild = nil
        end
    end

    local activeBuild = GetActiveBuildOverview()
    if activeBuild then
        local name = (activeBuild.name and activeBuild.name ~= "") and activeBuild.name or "Unnamed"
        UIDropDownMenu_SetText(loadoutDD, name)
    else
        UIDropDownMenu_SetText(loadoutDD, "Select a loadout")
    end

    -- Live refresh if the list is open while slot data changes under it
    if loadoutMenu and loadoutMenu:IsShown() then
        UpdateLoadoutMenu()
    end
end

-- ── Refresh / tab switching ──────────────────────────────────────────────────
function Refresh()
    if not journalFrame or not journalFrame:IsShown() then return end

    -- Only the merged Echoes tab gets the wider split layout below; Loadouts
    -- and the dead standalone TAB_MY_RUN entrypoint (player_run_ui.lua) keep
    -- the original single-column width.
    local isEchoesTab = currentTab == TAB_ALL
    journalFrame:SetWidth(isEchoesTab and ECHOES_JOURNAL_W or BASE_JOURNAL_W)

    -- On the Echoes tab the slots row is left-aligned and the search+filter
    -- column is stacked on the right (see below) -- since they occupy
    -- different horizontal space, the slots can start much higher without
    -- colliding with either. Loadouts keeps the original lower position
    -- (its loadoutControls/class filter live in that same row).
    contextBar:ClearAllPoints()
    local barTop = isEchoesTab and -12 or -71
    -- Tighter side margins on Echoes specifically: the old 25/42 (still used
    -- by the dead Loadouts layout below) left visible dead space on both
    -- edges of the now much wider window that didn't exist on the narrower
    -- single-column layout they were tuned for.
    local sideMarginL = isEchoesTab and 10 or 25
    -- +15 right-side padding for the CATALOG PANEL only: keeps its inset off
    -- the window's own right border instead of nearly touching it.
    local sideMarginR = isEchoesTab and 35 or 25
    -- The top controls row (slots/loadout/filters) is NOT pushed in with it:
    -- it keeps the old tighter margin so the buttons stay flush right.
    local barMarginR = isEchoesTab and 20 or 25
    contextBar:SetPoint("TOPLEFT", journalFrame, "TOPLEFT", sideMarginL, barTop)
    contextBar:SetPoint("TOPRIGHT", journalFrame, "TOPRIGHT", -barMarginR, barTop)

    if currentTab == TAB_LOADOUTS then
        myRunScrollFrame:Hide()
        loadoutFooter:Hide()
        myRunInset:Hide()
        catalogInset:Hide()
        -- Search stays at its plain top position here (Loadouts has no
        -- catalog column of its own to live inside); filter is hidden
        -- entirely for this tab (see SelectTab).
        searchBox:ClearAllPoints()
        searchBox:SetPoint("TOPRIGHT", journalFrame, "TOPRIGHT", -25, -45)
        UpdateContextBar(0, 0, 0)
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", journalFrame, "TOPLEFT", 25, -112)
        scrollFrame:SetPoint("BOTTOMRIGHT", journalFrame, "BOTTOMRIGHT", -42, 18)
        if journalFrame.scrollBg then journalFrame.scrollBg:Show() end
        UpdateGrid({}) -- hide the echo grid buttons
        RenderLoadouts()
        UpdateIntroOverlays()
        return
    end

    if journalFrame.scrollBg then journalFrame.scrollBg:Hide() end

    HideLoadoutRows()
    local items, ownedCount, totalCount = BuildItems(currentTab)

    UpdateContextBar(ownedCount, totalCount, #items)

    -- Context bar height varies (70/90/116 -- see UpdateContextBar) -- read
    -- the real height back rather than assume one, so the grids always start
    -- right after it with no dead space.
    local topOffset = barTop - contextBar:GetHeight() - 6
    -- Echoes tab only: the two columns start 15px higher than the context
    -- bar's reserved height would put them, swallowing the dead gap between
    -- the slots/loadout/filter row and the panels below it.
    local columnsTop = topOffset + 15

    if isEchoesTab then
        -- Loadout controls (active build + slot switcher + create/import)
        -- live in the slots row now, to the right of the permanent slot
        -- discs -- frees the whole My Run column below for just the echo
        -- grid, using its full vertical height. Right column is the full
        -- catalog.
        loadoutFooter:ClearAllPoints()
        -- Top-aligned with the slot discs (which start at -8, see
        -- UpdatePermanentSlots) instead of vertically centered lower in the
        -- now-taller slots zone, which read as too much empty space above it.
        -- Flush against the slots row's own right edge instead of a fixed
        -- offset from the left (which left a growing gap as the slots
        -- shrank/moved left).
        loadoutFooter:SetPoint("TOPRIGHT", contextBar, "TOPRIGHT", 0, -8)
        loadoutFooter:Show()
        UpdateLoadoutFooter()

        myRunScrollFrame:ClearAllPoints()
        myRunScrollFrame:SetPoint("TOPLEFT", journalFrame, "TOPLEFT", sideMarginL, columnsTop)
        -- +28, not +18: the bottom row was getting cropped by the window's
        -- own bottom border -- more clearance needed here.
        myRunScrollFrame:SetPoint("BOTTOMLEFT", journalFrame, "BOTTOMLEFT", sideMarginL, 20)
        myRunScrollFrame:Show()
        UpdateMyRunPanel(BuildItems(TAB_MY_RUN))

        -- Search + filter sit right below the loadout row (same slots-row
        -- zone), not above the catalog -- right-aligned under it.
        filterButton:ClearAllPoints()
        -- loadoutSecondaryBtn is pinned to the footer's right edge (visible
        -- or not -- it's the draft-only Cancel), so anchoring to it lines
        -- the filter up with the row above in both modes.
        filterButton:SetPoint("TOPRIGHT", loadoutSecondaryBtn, "BOTTOMRIGHT", 0, -6)
        filterButton:Show()

        searchBox:ClearAllPoints()
        searchBox:SetPoint("TOPRIGHT", filterButton, "TOPLEFT", -8, 0)
        searchBox:Show()

        -- Catalog grid starts level with the top of the left column now that
        -- search/filter no longer reserve a header row above it.
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", journalFrame, "TOPLEFT",
            sideMarginL + MY_RUN_PANEL_W + PANEL_GAP, columnsTop)
        scrollFrame:SetPoint("BOTTOMRIGHT", journalFrame, "BOTTOMRIGHT", -sideMarginR, 20)

        -- Sunken InsetFrameTemplate panels (same look Mounts/Pets use for
        -- their list pane) instead of plain divider lines: one per column --
        -- real background + border for each, not just a line between them.
        -- The slots/loadout row deliberately has NO inset of its own; its
        -- content sits directly on journalFrame's backdrop.
        -- Anchored directly to the actual content frames (not recomputed
        -- offsets from journalFrame) so they can never drift out of sync
        -- with them. A wider +24 right-side wrap (to fully clear the
        -- scrollbar) turned out to need a much bigger PANEL_GAP to avoid
        -- touching catalogInset, which read as excess dead space on both
        -- sides of the whole window -- back to a modest, even wrap on the
        -- sides; taller vertically (20, not 6) because the scrollbar's own
        -- Modest, even wrap -- the scrollbar's up/down buttons are moved to
        -- fit inside this instead of resizing the panel around wherever
        -- they happen to sit (see SkinScrollBar).
        myRunInset:ClearAllPoints()
        myRunInset:SetPoint("TOPLEFT", myRunScrollFrame, "TOPLEFT", -6, 6)
        myRunInset:SetPoint("BOTTOMRIGHT", myRunScrollFrame, "BOTTOMRIGHT", 6, -6)
        myRunInset:Show()

        catalogInset:ClearAllPoints()
        catalogInset:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", -6, 6)
        catalogInset:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 6, -6)
        catalogInset:Show()

        -- Reasserted every refresh: reparenting journalFrame into
        -- CollectionsJournal (on first embed) resets its children's frame
        -- levels, so a one-time SetFrameLevel at creation wouldn't stick.
        -- Keep both insets just below journalFrame's own content level so
        -- their marble background sits behind whatever's drawn on them.
        local insetLevel = journalFrame:GetFrameLevel()
        myRunInset:SetFrameLevel(insetLevel)
        catalogInset:SetFrameLevel(insetLevel)
    else
        myRunScrollFrame:Hide()
        loadoutFooter:Hide()
        myRunInset:Hide()
        catalogInset:Hide()
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", journalFrame, "TOPLEFT", 25, topOffset)
        scrollFrame:SetPoint("BOTTOMRIGHT", journalFrame, "BOTTOMRIGHT", -42, 18)
    end

    -- scrollChild's width is otherwise fixed at creation time -- the catalog
    -- area is wider on the Echoes tab than on Loadouts, so the icon grid's
    -- justified column spacing (in UpdateVisibleGrid) needs the real current
    -- width to actually fill it instead of leaving the extra space unused.
    scrollChild:SetWidth(scrollFrame:GetWidth() or 410)

    UpdateGrid(items)
    UpdateIntroOverlays()
end

--- Leaves lock mode and repaints. Public because arming an Orb of Lost Memories has to
--- end it: both modes hijack the same left-click on the echo grid (lock the echo vs.
--- forget a stack of it), so only one may ever be armed at a time.
function Journal.CancelLockMode()
    if not lockModeActive then return end
    lockModeActive = false
    Refresh()
end

-- Lock-mode click on a My Run grid echo: confirm, then lock it permanently
function Journal.TryLockEcho(button)
    local svc = GetService()
    if not svc then return end
    -- Merged Echoes tab always runs as TAB_ALL now (TAB_MY_RUN is dead); the
    -- permanent-slot lock feature lives on that tab.
    if currentTab ~= TAB_ALL then return end
    if (button.ownedStacks or 0) <= 0 or button.isLocked then return end
    local maxSlots = svc.GetMaximumPermanentEchoes and svc.GetMaximumPermanentEchoes() or 0
    local lockedPerks = svc.GetLockedPerks and svc.GetLockedPerks() or {}
    if #lockedPerks >= maxSlots then
        lockModeActive = false
        Refresh()
        return
    end
    local spellId = button.spellId
    local spellName = GetSpellInfo(spellId) or "this echo"
    StaticPopupDialogs["PROJECTEBONHOLD_JOURNAL_LOCK_ECHO"] = {
        text = "Make " .. spellName .. " permanent? It will be kept between runs.",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            local service = GetService()
            if service and service.LockPerk then
                service.LockPerk(spellId)
                if service.RequestGrantedPerks then
                    service.RequestGrantedPerks()
                end
            end
            lockModeActive = false
            Refresh()
        end,
        OnCancel = function()
            lockModeActive = false
            Refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("PROJECTEBONHOLD_JOURNAL_LOCK_ECHO")
end

local function SelectTab(tab)
    currentTab = tab
    lockModeActive = false

    if journalFrame then
        PanelTemplates_SetTab(journalFrame, tab)

        -- The filter dropdown only makes sense on the catalog tab; the search
        -- bar stays everywhere (it filters loadouts by name on Loadouts).
        if journalFrame.filterDropdown then
            if tab == TAB_ALL then
                journalFrame.filterDropdown:Show()
            else
                journalFrame.filterDropdown:Hide()
            end
        end
    end

    -- Refresh the community list every time it becomes visible
    if tab == TAB_LOADOUTS and loadoutView == "community" then
        RequestCommunityLoadouts()
    end

    Refresh()
end

-- ── Loadout builder flow ─────────────────────────────────────────────────────
-- targetSlot: server build slot the finished design will be uploaded to.
-- nil = pick the first free slot when the builder completes.
function Journal.StartLoadoutBuilder(name, targetSlot)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        UIErrorsFrame:AddMessage("Invalid wishlist name.", 1, 0.2, 0.2)
        return
    end
    builderDraft = { name = name, entries = {}, targetSlot = targetSlot }
    SelectTab(TAB_ALL)
end

-- Reopen an existing build in the builder; Done then replaces it in targetSlot
function Journal.EditLoadout(loadout, index, targetSlot)
    if not loadout then return end
    local entries = {}
    for _, e in ipairs(loadout.echoes or {}) do
        entries[e.spellId] = { quality = e.quality or 0, stacks = e.stacks or 1 }
    end
    builderDraft = {
        name = loadout.name, entries = entries,
        editIndex = index, class = loadout.class,
        targetSlot = targetSlot,
    }
    SelectTab(TAB_ALL)
end

-- Final step of the builder: upload the design into a server build slot
-- (persistent, account character's own). Edits may rename here.
local function CompleteBuilderSave(finalName)
    if not builderDraft or not builderDraft.pendingList then return end
    local svc = GetService()
    if not svc or not svc.UploadServerBuildSlot then return end
    if not finalName or finalName:gsub("%s", "") == "" then
        finalName = builderDraft.name
    end

    -- targetSlot = editing an existing design; 0 = new (server assigns the id)
    local slot = builderDraft.targetSlot or 0
    local isFirstBuild = not HasAnyBuild()
    local savedList = builderDraft.pendingList

    if svc.UploadServerBuildSlot(slot, finalName, savedList) then
        -- The very first build gets armed as soon as the server hands back the
        -- id it assigned, instead of leaving the dropdown on "Select a
        -- loadout". Armed server side, so deleting it disarms it too.
        if isFirstBuild and slot == 0 then
            autoActivateFirstBuild = true
        end
        builderDraft = nil
        loadoutView = "mine"
        -- Loadouts is no longer a separate reachable tab -- stay on the
        -- merged Echoes view instead of switching to that dead internal state.
        SelectTab(TAB_ALL)
    end
end

-- Offered when finishing an EDIT: tweak the name before saving, or keep it
StaticPopupDialogs["PROJECTEBONHOLD_LOADOUT_RENAME"] = {
    text = "Update the wishlist's name before saving?",
    button1 = ACCEPT,
    button2 = "Keep Name",
    hasEditBox = 1,
    maxLetters = 32,
    OnShow = function(self)
        self.editBox:SetText(builderDraft and builderDraft.name or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        CompleteBuilderSave(self.editBox:GetText())
    end,
    OnCancel = function()
        if builderDraft then CompleteBuilderSave(builderDraft.name) end
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        CompleteBuilderSave(dialog.editBox:GetText())
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function Journal.FinishLoadoutBuilder()
    if not builderDraft then return end
    local list = {}
    for spellId, e in pairs(builderDraft.entries) do
        table.insert(list, { spellId = spellId, quality = e.quality, stacks = e.stacks })
    end
    if #list == 0 then
        UIErrorsFrame:AddMessage("Pick at least one echo before saving.", 1, 0.2, 0.2)
        return
    end
    table.sort(list, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return (GetSpellInfo(a.spellId) or "") < (GetSpellInfo(b.spellId) or "")
    end)
    builderDraft.pendingList = list

    if builderDraft.editIndex then
        -- Editing an existing loadout: offer a rename before saving
        StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_RENAME")
    else
        CompleteBuilderSave(builderDraft.name)
    end
end

function Journal.CancelLoadoutBuilder()
    builderDraft = nil
    -- Loadouts is no longer a separate reachable tab -- stay on the merged
    -- Echoes view instead of switching to that dead internal state.
    SelectTab(TAB_ALL)
end

-- Re-skins a UIPanelScrollFrameTemplate's scrollbar with the same ornate
-- knob + top/middle/bottom track pieces ezCollections' own
-- HybridScrollBarTrimTemplate uses (Mounts/Pets list panes), instead of the
-- plain grey default scrollbar (just a thin groove, no track art at all).
local function SkinScrollBar(scrollFrameToSkin)
    local name = scrollFrameToSkin:GetName()
    local bar = name and _G[name .. "ScrollBar"]
    if not bar then return end

    local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
        thumb:SetSize(18, 24)
    end

    -- Nudge the up/down buttons themselves to sit inside the panel's modest
    -- 6px wrap, rather than resizing the wrap to fit wherever they default
    -- to (that read as extra dead space once the panel had a visible
    -- border). AdjustPointsOffset doesn't exist on this 3.3.5 client --
    -- read the button's existing (single) anchor and re-set it with an
    -- adjusted y offset instead.
    local function NudgeVertically(btn, dy)
        if not btn then return end
        local point, relativeTo, relativePoint, x, y = btn:GetPoint(1)
        if not point then return end
        btn:SetPoint(point, relativeTo, relativePoint, x or 0, (y or 0) + dy)
    end
    local upBtn = _G[name .. "ScrollBarScrollUpButton"]
    local downBtn = _G[name .. "ScrollBarScrollDownButton"]
    local upDy, downDy = 6, -6
    NudgeVertically(upBtn, upDy)
    NudgeVertically(downBtn, downDy)

    -- Track pieces follow the SAME nudge as their button, instead of being
    -- anchored to the (unmoved) bar -- otherwise the buttons slide but the
    -- track art they sit inside stays put and visibly stops matching them.
    local track = "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar"
    local top = bar:CreateTexture(nil, "ARTWORK")
    top:SetTexture(track)
    top:SetSize(24, 48)
    top:SetPoint("TOPLEFT", bar, "TOPLEFT", -4, 17 + upDy)
    top:SetTexCoord(0, 0.45, 0, 0.20)

    local bottom = bar:CreateTexture(nil, "ARTWORK")
    bottom:SetTexture(track)
    bottom:SetSize(24, 64)
    bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -4, -15 + downDy)
    bottom:SetTexCoord(0.515625, 0.97, 0.1440625, 0.4140625)

    local middle = bar:CreateTexture(nil, "ARTWORK")
    middle:SetTexture(track)
    middle:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    middle:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
    middle:SetTexCoord(0, 0.45, 0.1640625, 1)
end

-- ── Frame construction ───────────────────────────────────────────────────────
local function CreateJournalFrame()
    journalFrame = CreateFrame("Frame", "ProjectEbonholdEchoJournal", UIParent)
    journalFrame:SetSize(480, 500)
    -- Pre-embed position only; EmbedEchoJournal re-anchors it into
    -- CollectionsJournal. NOT movable/draggable: it always lives embedded in
    -- that window now, and dragging it out of its anchored spot was possible
    -- by accident (content "pushed right" bug).
    journalFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -140)
    journalFrame:SetFrameStrata("HIGH")
    journalFrame:EnableMouse(true)
    journalFrame:Hide()
    table.insert(UISpecialFrames, "ProjectEbonholdEchoJournal")

    -- No own background texture: this frame is always embedded inside
    -- CollectionsJournal now, which already provides one -- a second rock
    -- texture layered on top of it just looked like a doubled-up background.
    journalFrame:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    -- Blizzlike header banner on top of the dialog border
    local headerTex = journalFrame:CreateTexture(nil, "ARTWORK")
    headerTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    headerTex:SetSize(300, 64)
    headerTex:SetPoint("TOP", journalFrame, "TOP", 0, 12)

    local title = journalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", headerTex, "TOP", 0, -14)
    title:SetText("Echo Journal")

    local closeButton = CreateFrame("Button", nil, journalFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", journalFrame, "TOPRIGHT", -5, -5)
    closeButton:SetFrameLevel(journalFrame:GetFrameLevel() + 10)

    -- Exposed so Character Progression can hide this frame's own chrome when
    -- embedding it (its own border/title/close button would otherwise
    -- duplicate the hub's).
    journalFrame.headerTex = headerTex
    journalFrame.titleText = title
    journalFrame.closeButton = closeButton

    -- ── Blizzlike bottom tabs ──
    for i, label in ipairs(TAB_LABELS) do
        local tab = CreateFrame("Button", "ProjectEbonholdEchoJournalTab" .. i, journalFrame,
            "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(label)
        if i == 1 then
            tab:SetPoint("CENTER", journalFrame, "BOTTOMLEFT", 70, -12)
        else
            tab:SetPoint("LEFT", tabButtons[i - 1], "RIGHT", -16, 0)
        end
        tab:SetScript("OnClick", function(self)
            PlaySound("igCharacterInfoTab")
            SelectTab(self:GetID())
        end)
        PanelTemplates_TabResize(tab, 0)
        tabButtons[i] = tab
    end
    journalFrame.ownTabButtons = tabButtons  -- exposed: hub hides these when embedding (own tabs replace them)
    PanelTemplates_SetNumTabs(journalFrame, #TAB_LABELS)
    PanelTemplates_SetTab(journalFrame, currentTab)

    -- ── Search box (same component Wardrobe's collection search uses, for
    -- visual consistency: icon, native placeholder, clear button all built in) ──
    -- Positioned right before (left of) the filter button once it exists, see below.
    searchBox = CreateFrame("EditBox", "ProjectEbonholdEchoJournalSearchBox", journalFrame,
        "ezCollectionsSearchBoxTemplate")
    searchBox:SetSize(170, 22)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)

    -- Debounce: rebuilding the full grid on every keystroke made typing lag,
    -- so refresh 0.25s after the last change instead.
    local searchDebounce = CreateFrame("Frame")
    searchDebounce:Hide()
    searchDebounce:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t >= 0.25 then
            self.t = 0
            self:Hide()
            Refresh()
        end
    end)

    -- HookScript, not SetScript: the template already binds its own
    -- OnTextChanged via XML (icon tint, clear button, placeholder) and that
    -- must keep running alongside this.
    searchBox:HookScript("OnTextChanged", function(self)
        currentSearchText = self:GetText()
        WarmSearchDescCache() -- searching by effect needs the cache filled
        searchDebounce.t = 0
        searchDebounce:Show()
    end)

    -- ── Single filter dropdown: qualities + families ──
    -- Same component Mounts uses for its own "Filter" button (a proper
    -- button graphic + dropdown arrow + reset-x, vs the plain combo-box
    -- look of a bare UIDropDownMenuTemplate) -- the actual menu is a
    -- separate invisible UIDropDownMenuTemplate frame toggled open by it.
    local QUALITY_HEX = { [0] = "ffffff", [1] = "19ff19", [2] = "0066ff", [3] = "cc66ff" }
    local QUALITY_NAMES = { [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic" }

    -- Position (both this and searchBox) is set dynamically in Refresh() --
    -- on the Echoes tab they live inside the catalog column's own header,
    -- on Loadouts search falls back to a plain top position.
    filterButton = CreateFrame("Button", "ProjectEbonholdEchoJournalFilterButton", journalFrame,
        "UIResettableDropdownButtonTemplate")
    filterButton:SetSize(150, 22)
    journalFrame.filterDropdown = filterButton

    local filterDropdown = CreateFrame("Frame", "ProjectEbonholdEchoJournalFilterDD", journalFrame,
        "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(filterDropdown, 130)

    filterButton:SetScript("OnClick", function(self)
        PlaySound("igMainMenuOptionCheckBoxOn")
        ToggleDropDownMenu(1, nil, filterDropdown, self:GetName(), 0, 0)
    end)

    local function GetFilterSummary()
        local parts = {}
        if selectedTomesOnly then
            table.insert(parts, "Tomes")
        end
        if selectedKnownTomesOnly then
            table.insert(parts, "Known tomes")
        end
        if selectedMyClassOnly then
            table.insert(parts, "My class")
        end
        if selectedEnabledOnly then
            table.insert(parts, "Enabled")
        end
        if selectedDisabledOnly then
            table.insert(parts, "Disabled")
        end
        for quality = 0, 3 do
            if selectedQualities[quality] then
                table.insert(parts, "|cff" .. QUALITY_HEX[quality] .. QUALITY_NAMES[quality] .. "|r")
            end
        end
        local fams = {}
        for fam in pairs(selectedFamilies) do table.insert(fams, fam) end
        table.sort(fams)
        for _, fam in ipairs(fams) do table.insert(parts, fam) end

        if #parts == 0 then return "All Filters" end
        if #parts > 2 then return #parts .. " filters" end
        return table.concat(parts, ", ")
    end

    local function UpdateFilterText()
        filterButton:SetText(GetFilterSummary())
    end

    local function CollectFamilies()
        local seen, families = {}, {}
        for _, data in pairs(ProjectEbonhold.PerkDatabase) do
            if data.families then
                for _, fam in ipairs(data.families) do
                    if not seen[fam] then
                        seen[fam] = true
                        table.insert(families, fam)
                    end
                end
            end
        end
        table.sort(families)
        return families
    end

    UIDropDownMenu_Initialize(filterDropdown, function(self, level)
        level = level or 1
        local info

        if level == 1 then
            info = UIDropDownMenu_CreateInfo()
            info.text = "Quality"
            info.hasArrow = true
            info.notCheckable = true
            info.value = "QUALITY"
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "Family"
            info.hasArrow = true
            info.notCheckable = true
            info.value = "FAMILY"
            UIDropDownMenu_AddButton(info, level)

            -- All tome-related filters grouped under one submenu (see the
            -- level-2 "TOMES" branch below)
            info = UIDropDownMenu_CreateInfo()
            info.text = "Tomes"
            info.hasArrow = true
            info.notCheckable = true
            info.value = "TOMES"
            UIDropDownMenu_AddButton(info, level)

            -- Echoes the player's own class can actually obtain (same
            -- predicate the builder/tome views already force)
            info = UIDropDownMenu_CreateInfo()
            info.text = "My class only"
            info.keepShownOnClick = true
            info.checked = selectedMyClassOnly
            info.func = function()
                selectedMyClassOnly = not selectedMyClassOnly
                UpdateFilterText()
                Refresh()
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "Reset filters"
            info.notCheckable = true
            info.func = function()
                selectedQualities = {}
                selectedFamilies = {}
                selectedTomesOnly = false
                selectedKnownTomesOnly = false
                selectedMyClassOnly = false
                selectedEnabledOnly = false
                selectedDisabledOnly = false
                UpdateFilterText()
                Refresh()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "TOMES" then
            -- Replaces the former Tomes tab: restricts the catalog to
            -- tome-locked echoes (class-filtered, like the old tab).
            info = UIDropDownMenu_CreateInfo()
            info.text = "Tomes only"
            info.keepShownOnClick = true
            info.checked = selectedTomesOnly
            info.func = function()
                selectedTomesOnly = not selectedTomesOnly
                UpdateFilterText()
                Refresh()
            end
            UIDropDownMenu_AddButton(info, level)

            -- Learned tomes only (golden-halo entries of the catalog)
            info = UIDropDownMenu_CreateInfo()
            info.text = "Known tomes only"
            info.keepShownOnClick = true
            info.checked = selectedKnownTomesOnly
            info.func = function()
                selectedKnownTomesOnly = not selectedKnownTomesOnly
                UpdateFilterText()
                Refresh()
            end
            UIDropDownMenu_AddButton(info, level)

            -- Enabled/Disabled tome echoes (the right-click toggle state);
            -- mutually exclusive, so picking one clears the other.
            info = UIDropDownMenu_CreateInfo()
            info.text = "Enabled only"
            info.keepShownOnClick = true
            info.checked = selectedEnabledOnly
            info.func = function()
                selectedEnabledOnly = not selectedEnabledOnly
                if selectedEnabledOnly then selectedDisabledOnly = false end
                UpdateFilterText()
                Refresh()
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "Disabled only"
            info.keepShownOnClick = true
            info.checked = selectedDisabledOnly
            info.func = function()
                selectedDisabledOnly = not selectedDisabledOnly
                if selectedDisabledOnly then selectedEnabledOnly = false end
                UpdateFilterText()
                Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "QUALITY" then
            -- Multi-select: entries toggle and the menu stays open
            info = UIDropDownMenu_CreateInfo()
            info.text = "All Qualities"
            info.checked = (next(selectedQualities) == nil)
            info.func = function()
                selectedQualities = {}
                UpdateFilterText()
                Refresh()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)

            for quality = 0, 3 do
                info = UIDropDownMenu_CreateInfo()
                info.text = "|cff" .. QUALITY_HEX[quality] .. QUALITY_NAMES[quality] .. "|r"
                info.keepShownOnClick = true
                info.checked = selectedQualities[quality] and true or false
                info.func = function()
                    if selectedQualities[quality] then
                        selectedQualities[quality] = nil
                    else
                        selectedQualities[quality] = true
                    end
                    UpdateFilterText()
                    Refresh()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "FAMILY" then
            info = UIDropDownMenu_CreateInfo()
            info.text = "All Families"
            info.checked = (next(selectedFamilies) == nil)
            info.func = function()
                selectedFamilies = {}
                UpdateFilterText()
                Refresh()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)

            for _, fam in ipairs(CollectFamilies()) do
                info = UIDropDownMenu_CreateInfo()
                info.text = fam
                info.keepShownOnClick = true
                info.checked = selectedFamilies[fam] and true or false
                info.func = function()
                    if selectedFamilies[fam] then
                        selectedFamilies[fam] = nil
                    else
                        selectedFamilies[fam] = true
                    end
                    UpdateFilterText()
                    Refresh()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
    UpdateFilterText()

    -- ── Context bar (height varies per tab, see Refresh) ──
    contextBar = CreateFrame("Frame", nil, journalFrame)
    contextBar:SetPoint("TOPLEFT", journalFrame, "TOPLEFT", 25, -71)
    contextBar:SetPoint("TOPRIGHT", journalFrame, "TOPRIGHT", -25, -71)
    contextBar:SetHeight(98)

    local slotsLabel = contextBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slotsLabel:SetPoint("TOPLEFT", 0, -2)
    slotsLabel:SetTextColor(1, 0.82, 0)
    contextBar.slotsLabel = slotsLabel

    local statsText = contextBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsText:SetPoint("BOTTOMLEFT", 0, 2)
    statsText:SetPoint("BOTTOMRIGHT", 0, 2)
    statsText:SetJustifyH("LEFT")
    statsText:SetWordWrap(true)
    statsText:SetTextColor(0.7, 0.7, 0.7)
    contextBar.statsText = statsText

    -- Active build line on My Echoes: "Build: <name>". Anchored just below the
    -- permanent slot discs (slots span y -8..-64): the bar's bottom edge would
    -- collide with the grid's first badge row. No Clear button here: stop
    -- tracking a build by clicking its row (or deleting the slot) in Loadouts.
    local buildText = contextBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    buildText:SetPoint("TOPLEFT", contextBar, "TOPLEFT", 2, -68)
    buildText:SetJustifyH("LEFT")
    buildText:Hide()
    contextBar.buildText = buildText

    -- ── Loadouts tab controls: view toggle + create/import actions ──
    local lc = CreateFrame("Frame", nil, contextBar)
    lc:SetAllPoints(contextBar)
    lc:Hide()
    contextBar.loadoutControls = lc

    local function MakeBarBtn(text, width)
        return ShrinkButtonFont(utils.CreateSimpleCustomButton(lc, text, nil, width, 22))
    end

    -- Standard WoW top-tabs (same template family as PetPaperDollFrameTab):
    -- TabButtonTemplate needs GLOBAL names, its textures resolve via $parent
    local mineBtn = CreateFrame("Button", "ProjectEbonholdLoadoutTabMine", lc, "TabButtonTemplate")
    mineBtn:SetText("My Builds")
    mineBtn:SetPoint("TOPLEFT", lc, "TOPLEFT", 0, 6)
    PanelTemplates_TabResize(mineBtn, 0)
    local commBtn = CreateFrame("Button", "ProjectEbonholdLoadoutTabCommunity", lc, "TabButtonTemplate")
    commBtn:SetText("Community")
    commBtn:SetPoint("LEFT", mineBtn, "RIGHT", 6, 0)
    PanelTemplates_TabResize(commBtn, 0)

    -- New/Import: bigger than the row buttons, full-size font
    local importBtn = utils.CreateSimpleCustomButton(lc, "Import", nil, 94, 31)
    importBtn:SetPoint("TOPRIGHT", lc, "TOPRIGHT", 0, 4)
    local newBtn = utils.CreateSimpleCustomButton(lc, "New Wishlist", nil, 116, 31)
    newBtn:SetPoint("RIGHT", importBtn, "LEFT", -4, 0)
    lc.mineBtn, lc.commBtn = mineBtn, commBtn

    -- Class filter lives on the search row, right-aligned like the All Echoes
    -- filter dropdown (only one of the two is visible at a time)
    local classDD = CreateFrame("Frame", "ProjectEbonholdEchoLoadoutClassDD", lc, "UIDropDownMenuTemplate")
    classDD:SetPoint("TOPRIGHT", journalFrame, "TOPRIGHT", -9, -35)
    UIDropDownMenu_SetWidth(classDD, 120)
    local function SetClassFilter(token)
        selectedLoadoutClass = token
        UIDropDownMenu_SetText(classDD, token and ClassDisplay(token) or "All Classes")
        if loadoutView == "community" then
            RequestCommunityLoadouts() -- re-query the server with the new class
        end
        Refresh()
        CloseDropDownMenus()
    end

    UIDropDownMenu_Initialize(classDD, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All Classes"
        info.checked = (selectedLoadoutClass == nil)
        info.func = function() SetClassFilter(nil) end
        UIDropDownMenu_AddButton(info, level)

        for _, token in ipairs(LOADOUT_CLASSES) do
            info = UIDropDownMenu_CreateInfo()
            info.text = ClassDisplay(token)
            info.checked = (selectedLoadoutClass == token)
            info.func = function() SetClassFilter(token) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    -- Default filter: the player's own class
    UIDropDownMenu_SetText(classDD,
        selectedLoadoutClass and ClassDisplay(selectedLoadoutClass) or "All Classes")

    -- The loadout builder's Done/Cancel now live on the loadout footer's
    -- New Wishlist/Import buttons instead of a separate banner here (see
    -- UpdateLoadoutFooter).

    mineBtn:SetScript("OnClick", function()
        loadoutView = "mine"
        Refresh()
    end)
    commBtn:SetScript("OnClick", function()
        loadoutView = "community"
        RequestCommunityLoadouts()
        Refresh()
    end)
    newBtn:SetScript("OnClick", function()
        StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_NAME")
    end)
    newBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("New Wishlist", 1, 1, 1)
        GameTooltip:AddLine(
            "Creates an |cffa080e0Echo Wishlist|r build: pick its echoes in the catalog, then save it.\nWhile active, its echoes are highlighted in your draws.",
            0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    newBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    importBtn:SetScript("OnClick", function()
        StaticPopup_Show("PROJECTEBONHOLD_LOADOUT_IMPORT")
    end)

    -- ── Grid scroll area ──
    scrollFrame = CreateFrame("ScrollFrame", "ProjectEbonholdEchoJournalScroll", journalFrame,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", journalFrame, "TOPLEFT", 25, -222)
    scrollFrame:SetPoint("BOTTOMRIGHT", journalFrame, "BOTTOMRIGHT", -42, 15)

    -- Dark backdrop behind the whole scroll area (the builds list). Anchored to
    -- the scroll frame so it follows its per-tab repositioning; shown on the
    -- Loadouts tab only (see Refresh)
    local scrollBg = journalFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    scrollBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    scrollBg:SetVertexColor(0, 0, 0, 0.4)
    scrollBg:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", -8, 13)
    scrollBg:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 26, -8)
    scrollBg:Hide()
    journalFrame.scrollBg = scrollBg

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(410, 300)
    scrollFrame:SetScrollChild(scrollChild)
    -- Virtualized grid: rebind the button pool as the viewport moves
    scrollFrame:HookScript("OnVerticalScroll", UpdateVisibleGrid)
    SkinScrollBar(scrollFrame)

    -- ── My Run + catalog panels (merged Echoes tab's two columns) ──
    -- Both are plain InsetFrameTemplates with the marble hidden and a
    -- dedicated art texture from assets/ cropped via texcoords (regions
    -- measured from the decoded BLP pixels): titan console on My Run,
    -- Journeys slate on the catalog.
    --
    -- MUST be given unique names: InsetFrameTemplate's corner textures anchor
    -- via relativeTo="$parentBg", which resolves by GLOBAL NAME. On unnamed
    -- frames every inset's Bg gets the same fallback name, so all corner
    -- textures end up anchored to the FIRST inset's Bg -- the catalog's
    -- border was being drawn stacked on top of the My Run panel, leaving the
    -- catalog a bare background with no border at all.
    --
    -- Frame level is reasserted every Refresh() (below journalFrame's own
    -- content) rather than set once here -- reparenting journalFrame into
    -- CollectionsJournal on first embed resets its children's frame levels,
    -- which would undo a one-time SetFrameLevel done before that reparent.
    -- My Run: titan-console art (bundled in assets/). The template's marble
    -- Bg is hidden; the corner border pieces (BORDER layer) still draw
    -- above the art.
    myRunInset = CreateFrame("Frame", "ProjectEbonholdEchoJournalMyRunInset", journalFrame, "InsetFrameTemplate")
    myRunInset:Hide()
    if myRunInset.Bg then myRunInset.Bg:Hide() end
    local bgArt = myRunInset:CreateTexture(nil, "BACKGROUND")
    bgArt:SetTexture(ASSETS .. "talenttreetitanconsole")
    -- 1024x1024 atlas; crop to just the stone panel with the titan disc
    -- (x 0-582, y 100-942 measured from the decoded pixels) -- skips the
    -- runic metal bar above it, the loose icon below it, and the
    -- transparent right half.
    bgArt:SetTexCoord(0, 582 / 1024, 100 / 1024, 942 / 1024)
    bgArt:SetPoint("TOPLEFT", myRunInset, "TOPLEFT", 2, -2)
    bgArt:SetPoint("BOTTOMRIGHT", myRunInset, "BOTTOMRIGHT", -2, 2)

    -- Catalog: the Journeys dark-slate art (bundled in assets/), same
    -- pattern as My Run's titan console above -- plain InsetFrameTemplate,
    -- marble hidden, art cropped to the opaque region of the file
    -- (x 0-794, y 0-434 of 1024x512; the rest is transparent padding).
    catalogInset = CreateFrame("Frame", "ProjectEbonholdEchoJournalCatalogInset", journalFrame, "InsetFrameTemplate")
    catalogInset:Hide()
    if catalogInset.Bg then catalogInset.Bg:Hide() end
    local catalogArt = catalogInset:CreateTexture(nil, "BACKGROUND")
    catalogArt:SetTexture(ASSETS .. "journeysframebackground")
    catalogArt:SetTexCoord(0, 794 / 1024, 0, 434 / 512)
    catalogArt:SetPoint("TOPLEFT", catalogInset, "TOPLEFT", 2, -2)
    catalogArt:SetPoint("BOTTOMRIGHT", catalogInset, "BOTTOMRIGHT", -2, 2)

    myRunScrollFrame = CreateFrame("ScrollFrame", "ProjectEbonholdEchoJournalMyRunScroll", journalFrame,
        "UIPanelScrollFrameTemplate")
    myRunScrollFrame:SetWidth(MY_RUN_PANEL_W)
    myRunScrollFrame:Hide()

    myRunScrollChild = CreateFrame("Frame", nil, myRunScrollFrame)
    myRunScrollChild:SetSize(MY_RUN_PANEL_W, 300)
    myRunScrollFrame:SetScrollChild(myRunScrollChild)
    SkinScrollBar(myRunScrollFrame)

    -- Empty state: a fresh character (or a fresh run) holds no echoes at all
    -- -- instead of a bare panel, show a desaturated icon + hint that echoes
    -- come from leveling during a run. Regions live on the scroll FRAME (not
    -- the scroll child), so they stay centered in the visible panel;
    -- UpdateMyRunPanel toggles it on the item count.
    myRunEmptyState = CreateFrame("Frame", nil, myRunScrollFrame)
    myRunEmptyState:SetAllPoints(myRunScrollFrame)
    myRunEmptyState:Hide()

    local emptyIcon = myRunEmptyState:CreateTexture(nil, "ARTWORK")
    emptyIcon:SetTexture("Interface\\Icons\\Spell_Shadow_SoulGem")
    emptyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    emptyIcon:SetDesaturated(true)
    emptyIcon:SetAlpha(0.55)
    emptyIcon:SetSize(40, 40)
    emptyIcon:SetPoint("CENTER", myRunEmptyState, "CENTER", 0, 32)

    local emptyText = myRunEmptyState:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    emptyText:SetPoint("TOP", emptyIcon, "BOTTOM", 0, -10)
    emptyText:SetWidth(MY_RUN_PANEL_W - 40)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetTextColor(0.55, 0.55, 0.55)
    emptyText:SetText("You have no echoes yet.\n\nLevel up during a run to earn new echoes.")

    -- ── Loadout controls: active loadout + slot switcher + create/import ──
    -- Consolidates what used to be the separate Loadouts tab (server save
    -- slots, designed builds; community browsing dropped from this compact
    -- view for now). Lives in the slots row now (to the right of the
    -- permanent slot discs), a single wide row instead of a stacked column,
    -- freeing the whole My Run column below for just the echo grid.
    -- Position set dynamically in Refresh().
    loadoutFooter = CreateFrame("Frame", nil, journalFrame)
    loadoutFooter:SetSize(340, 30)

    loadoutDD = CreateFrame("Frame", "ProjectEbonholdEchoJournalLoadoutDD", loadoutFooter, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(loadoutDD, 130)
    -- Outfit-dropdown style: the arrow button toggles our own custom list
    -- (ToggleLoadoutMenu) instead of a generic UIDropDownMenu -- no
    -- UIDropDownMenu_Initialize; SetText alone drives the label.
    local ddButton = _G["ProjectEbonholdEchoJournalLoadoutDDButton"]
    if ddButton then
        ddButton:SetScript("OnClick", function()
            PlaySound("igMainMenuOptionCheckBoxOn")
            ToggleLoadoutMenu()
        end)
    end
    -- Alone in the footer now (the buttons only appear as draft Done/Cancel)
    -- -- pinned to the footer's right edge, +14 eating the template's
    -- transparent right wing so the visible edge lands flush.
    loadoutDD:SetPoint("RIGHT", loadoutFooter, "RIGHT", 14, -2)

    -- Draft-only Done/Cancel pair (see UpdateLoadoutFooter): hidden in
    -- normal use -- creating/importing wishlists now happens from rows
    -- inside the dropdown's menu, not from standing buttons.
    loadoutPrimaryBtn = ShrinkButtonFont(utils.CreateSimpleCustomButton(loadoutFooter, "Done",
        nil, 90, 22))
    loadoutPrimaryBtn:Hide()

    loadoutSecondaryBtn = ShrinkButtonFont(utils.CreateSimpleCustomButton(loadoutFooter, "Cancel",
        nil, 80, 22))
    loadoutSecondaryBtn:Hide()

    -- Right-aligned chain (Import pinned to the footer's right edge, the
    -- rest hanging off it leftwards) so the buttons' right edge always sits
    -- flush with the content zone's right margin, instead of ending wherever
    -- the summed widths of a left-to-right chain happened to land.
    loadoutSecondaryBtn:SetPoint("RIGHT", loadoutFooter, "RIGHT", 0, 0)
    loadoutPrimaryBtn:SetPoint("RIGHT", loadoutSecondaryBtn, "LEFT", -6, 0)

    journalFrame:SetScript("OnShow", function()
        -- Fill the search-text cache in the background while the player reads
        -- the grid, so the first search does not have to scrape it inline.
        WarmSearchDescCache()

        local svc = GetService()
        if svc and svc.RequestGrantedPerks then
            svc.RequestGrantedPerks()
        end
        if svc and svc.RequestEchoDiscovery then
            svc.RequestEchoDiscovery()
        end
        if svc and svc.RequestServerBuildSlots then
            svc.RequestServerBuildSlots()
        end
        Refresh()
        if UpdateMicroButtons then UpdateMicroButtons() end
    end)

    journalFrame:SetScript("OnHide", function()
        lockModeActive = false
        if UpdateMicroButtons then UpdateMicroButtons() end
    end)
end

-- ── Public API ───────────────────────────────────────────────────────────────
function Journal.Show(tab)
    if not journalFrame then
        CreateJournalFrame()
    end
    journalFrame:Show()
    SelectTab(tab or currentTab)
end

function Journal.Hide()
    if journalFrame then
        journalFrame:Hide()
    end
end

function Journal.Toggle(tab)
    if journalFrame and journalFrame:IsShown() then
        Journal.Hide()
    else
        Journal.Show(tab)
    end
end

-- Called by the perk service whenever granted/locked perks change
function Journal.OnDataChanged()
    Refresh()
end

-- The journal shell and its overlays (loadout list menu, guided tour) sit on
-- HIGH/FULLSCREEN_DIALOG strata, which covered UIErrorsFrame's top-of-screen
-- messages ("Builds can only be activated at level 1 or 80", etc.) -- the
-- player acted, saw nothing, and thought the click did nothing. Error text
-- is transient and mouse-transparent, so keeping it above everything is
-- harmless.
UIErrorsFrame:SetFrameStrata("FULLSCREEN_DIALOG")
UIErrorsFrame:SetFrameLevel(500)

-- ── Micro button (takes the removed PvP micro button's slot) ─────────────────
-- The bar order is owned by skillTreeMicroButton.lua (getCoreMicroButtons).
local microButton = CreateFrame("Button", "EchoJournalMicroButton", MainMenuBarArtFrame, "MainMenuBarMicroButton")
LoadMicroButtonTextures(microButton, "Help")
microButton:SetNormalTexture([[Interface\AddOns\ProjectEbonhold\assets\ui-microbuttonstreamdl-up]])
microButton:SetPushedTexture([[Interface\AddOns\ProjectEbonhold\assets\ui-microbuttonstreamdl-down]])
microButton:SetHighlightTexture([[Interface\Buttons\UI-MicroButton-Hilight]])

-- This button now fronts the whole unified Character Progression window
-- (Echoes, Skill Tree, Transmogrify, Mounts, Companions), not just the Echo
-- Journal -- the separate Skill Tree micro button is gone (see
-- skillTreeMicroButton.lua, which now only redirects its alerts here).
local microIcon = microButton:CreateTexture(nil, "OVERLAY")
microIcon:SetTexture([[Interface\AddOns\ProjectEbonhold\assets\spell_holy_guardianspirit]])
microIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
microIcon:SetSize(18, 18)
microIcon:SetPoint("BOTTOM", microButton, "BOTTOM", 0, 9)

microButton.tooltipText = "Character Progression"
microButton.newbieText = "Your echoes, skill tree, transmogrify, mounts and companions."

-- "New echo" alert bubble above the micro button (same recipe as the skill
-- tree alert). Closing it with the X disables it permanently.
microButton.Alert = CreateFrame("Frame", "EchoJournalMicroButtonAlert", UIParent, "GlowBoxTemplate")
microButton.Alert:SetSize(220, 70)
microButton.Alert:SetPoint("BOTTOM", microButton, "TOP", 0, 10)
microButton.Alert:SetFrameStrata("DIALOG")
microButton.Alert:SetFrameLevel(10)
microButton.Alert:EnableMouse(true)
microButton.Alert:Hide()

microButton.Alert.Text = microButton.Alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
microButton.Alert.Text:SetJustifyV("TOP")
microButton.Alert.Text:SetSize(188, 0)
microButton.Alert.Text:SetPoint("TOPLEFT", 16, -18)
microButton.Alert.Text:SetText("You gained a new echo! Open your Echo Journal to see it.")

microButton.Alert.CloseButton = CreateFrame("Button", nil, microButton.Alert, "UIPanelCloseButton")
microButton.Alert.CloseButton:SetPoint("TOPRIGHT", 6, 6)
microButton.Alert.CloseButton:SetScript("OnClick", function()
    microButton.Alert:Hide()
    -- Closed by hand: never show THIS KIND of alert again. The key is per-kind
    -- (set by ShowJournalAlert) because the bubble is shared: one flag for all
    -- of them meant dismissing a "new echo" bubble - which fires several times
    -- per run - also silenced the far rarer orb alert forever.
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB[microButton.Alert.dismissKey or "hideNewEchoAlert"] = true
end)

microButton.Alert.Arrow = CreateFrame("Frame", nil, microButton.Alert, "GlowBoxArrowTemplate")
microButton.Alert.Arrow:SetPoint("TOP", microButton.Alert, "BOTTOM", 0, 4)

-- The alert text is shared between the "new echo", "new tome" and "orbs
-- gained" messages, so every caller sets it (and the box height follows the
-- wrapped text). dismissKey is the ProjectEbonholdDB flag the X sets: it must
-- be the one the calling notifier tests, or the X silences the wrong alert.
local function ShowJournalAlert(text, dismissKey)
    microButton.Alert.dismissKey = dismissKey or "hideNewEchoAlert"
    microButton.Alert.Text:SetText(text)
    microButton.Alert:SetHeight(microButton.Alert.Text:GetStringHeight() + 36)
    microButton.Alert:Show()
end

-- Called by the perk service when an echo selection succeeds
function Journal.NotifyNewEcho()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    if ProjectEbonholdDB.hideNewEchoAlert then return end
    if journalFrame and journalFrame:IsShown() then return end
    ShowJournalAlert("You gained a new echo! Open your Echo Journal to see it.")
end

-- Called by the perk service when the discovery list gains a tome echo (the
-- player just used a tome). Same alert bubble; the journal highlights the
-- learned tome with a golden halo.
function Journal.NotifyTomeLearned(echoSpellId)
    -- Optional alert: the options toggle and the bubble's X (permanent
    -- dismissal, shared with the "new echo" alert) both silence it
    if ProjectEbonholdOptionsService
        and ProjectEbonholdOptionsService:GetSetting("hideTomeLearnedAlert") then
        return
    end
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    if ProjectEbonholdDB.hideNewEchoAlert then return end
    if journalFrame and journalFrame:IsShown() then return end
    local name = GetSpellInfo(echoSpellId)
    ShowJournalAlert(name
        and ("You unlocked a new Tome Echo: |cffffd700" .. name .. "|r! Open your Echo Journal to see it.")
        or "You unlocked a new Tome Echo! Open your Echo Journal to see it.")
end

-- Called by the orb service when the server reports a POSITIVE applied delta on
-- SEND_ORB_CHARGES (a quest turn-in, a prestige, a GM grant). Same bubble and same
-- permanent X as the echo/tome alerts on purpose: it is one "something landed in your
-- Echo Journal" channel, so a player who silenced it stays silenced.
-- Orbs are rare and come from cleared content, so this alert has its OWN
-- dismissal flag: it used to share hideNewEchoAlert with the new-echo bubble,
-- which fires several times per run, so one X on that bubble silenced every
-- orb gain from then on.
function Journal.NotifyOrbsGained(count)
    count = tonumber(count) or 0
    if count <= 0 then return end
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    if ProjectEbonholdDB.hideOrbAlert then return end
    if journalFrame and journalFrame:IsShown() then return end
    ShowJournalAlert(count == 1
        and "You gained an |cffffd700Orb of Lost Memories|r! Open your Echo Journal to spend it."
        or ("You gained |cffffd700" .. count .. " Orbs of Lost Memories|r! Open your Echo Journal to spend them."),
        "hideOrbAlert")
end

-- The journal always lives inside CollectionsJournal's Echoes tab (id 1)
-- now, so the micro button opens/closes the unified Collections window on
-- that tab -- same pattern as SkillTreeMicroButton with tab 2 -- instead of
-- toggling the bare journalFrame outside its shell.
local function IsCollectionsOpenOnEchoes()
    return CollectionsJournal and CollectionsJournal:IsShown()
        and PanelTemplates_GetSelectedTab(CollectionsJournal) == 1
end

microButton:SetScript("OnClick", function()
    microButton.Alert:Hide()
    if SetCollectionsJournalShown then
        SetCollectionsJournalShown(not IsCollectionsOpenOnEchoes(), 1)
    else
        Journal.Toggle() -- collections shell not loaded; old standalone toggle
    end
end)
microButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltipText, 1, 1, 1)
    GameTooltip:AddLine(self.newbieText, nil, nil, nil, true)
    GameTooltip:Show()
end)
microButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

hooksecurefunc("UpdateMicroButtons", function()
    if IsCollectionsOpenOnEchoes() or (journalFrame and journalFrame:IsShown()) then
        microButton:SetButtonState("PUSHED", 1)
    else
        microButton:SetButtonState("NORMAL")
    end
end)

