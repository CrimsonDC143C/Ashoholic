--[[----------------------------------------------------------------------------
    ProjectEbonhold — Collections visual shell : STUB DATA-SEAM
--------------------------------------------------------------------------------
    This file REPLACES the ~9,200-line ezCollections.lua core and the C_* / whisper
    emulation layer (Layer B). Its only job is to satisfy every symbol the VISUAL
    layer (Layer A) references so the Collections UI loads and renders its EMPTY
    state. It holds no real collection data and talks to no server.

    Two seams are where you will later connect the UI to the Ebonhold server:

      1. OUTBOUND  — ezCollections:SendAddonMessage / :SendAddonCommand
                     (search "SEAM: OUTBOUND"). Route these to
                     ProjectEbonhold.sendToServer(ProjectEbonhold.CS.*, body).

      2. INBOUND   — ezCollections:RaiseEvent(EVENT, ...) fired from server
                     handlers (search "SEAM: INBOUND"). Register
                     ProjectEbonhold.onEventReceived(SS.*, ...) handlers that
                     populate the data tables below and then RaiseEvent the
                     matching UI event so the painters refresh.

    Load order (see projectebonhold.toc): this file loads BEFORE the framework
    and Blizzard_Collections files, and BEFORE core/ezutil.lua (which adds the
    ezCollections:Ordered / :IterateOverTableOrValue iterators).
------------------------------------------------------------------------------]]

_G.ezCollections = _G.ezCollections or {}
local ez = _G.ezCollections

ez.Name        = "ProjectEbonholdCollections"
ez.Version     = 0
ez.IsVisualShell = true   -- flag so later wiring code can detect the stub

-- Global constants that lived at the top of the dropped ezCollections.lua core
-- and are indexed by the visual layer (e.g. transmog tooltip colouring).
TRANSMOGRIFY_FONT_COLOR      = TRANSMOGRIFY_FONT_COLOR      or { r = 1, g = 0.5, b = 1 }
TRANSMOGRIFY_FONT_COLOR_CODE = TRANSMOGRIFY_FONT_COLOR_CODE or "|cFFFF80FF"

--=============================================================================
-- Localization : every key resolves to a printable string so nothing errors on
-- concatenation / format / SetText. Replace with a real locale table later.
--=============================================================================
ez.L = setmetatable({}, { __index = function(_, k) return tostring(k) end })

--=============================================================================
-- Static data / feature-gate fields the visual layer reads directly.
-- All chosen so the UI behaves as "nothing owned, no premium, not a dev".
--=============================================================================
ez.Developer                = false
ez.Token                    = false
ez.PrepaidOutfitsEnabled    = false
ez.SearchMaxSetsSlotMask    = 0
ez.BattlePassURL            = ""
ez.StoreURLSkinFormat       = ""
ez.UnclaimedQuests          = {}
ez.Subscriptions            = {}
ez.SubscriptionBySkin       = {}
ez.ActiveToys               = {}
ez.ItemCooldowns            = {}
ez.ItemNameDescriptions     = {}
-- Weapon preview holder (display 11686, creature entry 12999 "World Invisible
-- Trigger"). Confirmed genuinely invisible when spawned in the actual game
-- world (GM test) -- so the model/texture data is NOT broken/stripped. It still
-- renders a visible body in this addon's Model/DressUpModel UI preview widget
-- specifically; root cause unconfirmed (in-world and UI-widget rendering are
-- different code paths client-side). It still works as a hand-attachment rig
-- to hold + texture the weapon at the right scale via TryOn.
ez.CreatureWeaponPreview    = 11686
ez.Encounters               = {}
ez.Instances                = {}
ez.itemUnderCursor          = { ID = nil, Bag = nil, Slot = nil }

-- Class / race lookup tables (a few used to build filter dropdowns). Left empty:
-- the dropdowns render with no rows, which is fine for the empty shell.
ez.ClassNameToID       = {}
ez.ClassIDToName       = {}
ez.RaceNameToID        = {}
ez.RaceIDToName        = {}
ez.RaceNameToFaction   = {}
ez.RaceSortOrder       = {}
ez.TransmogrifiableSlots = {}

-- Subscription/premium display strings (always read as `field or ""`).
ez.ActiveLibrarySubscriptionInfo = ""
ez.ActiveMountPremiumInfo        = ""
ez.ActiveMountSubscriptionInfo   = ""
ez.ActivePetSubscriptionInfo     = ""
ez.ActiveToySubscriptionInfo     = ""
ez.OutfitCostHint                = ""
ez.OutfitEditCostHint            = ""

--=============================================================================
-- Cache : server-authoritative static DB in the real addon. Empty here.
--=============================================================================
ez.Cache = {
    Sets    = {},
    Cameras = {},
    Mounts  = {},
    Pets    = {},
    Books   = {},
    Toys    = {},
}

-- Live per-session ownership (empty = nothing collected).
ez.Collections = {}

--=============================================================================
-- Config : user settings + emulated CVars. Only three sub-tables are actually
-- read by the visual layer (Wardrobe, TooltipSets, Windows). Shapes matter.
--=============================================================================
ez.Config = {
    Wardrobe = {
        -- Camera.lua's CameraOptionsToCameraID is keyed by option NAME. Only
        -- "Classic" is bundled client-side (HD2017/HD2019 come from the server),
        -- so the per-race/per-slot wardrobe cameras resolve against "Classic".
        CameraOption              = "Classic",
        CameraOptionSetup         = "Classic",
        CameraPanLimit            = true,
        CameraZoomSmooth          = true,
        CameraZoomSmoothSpeed     = 1,
        CameraZoomSpeed           = 1,
        DressUpClassBackground    = false,
        DressUpDesaturateBackground = false,
        DressUpGnomeTrollBackground = false,
        DressUpSkipDressOnShow    = false,
        EtherealWindowSound       = true,
        MicroButtonsIcon          = 1,
        MountsDoubleClickIcon     = true,
        MountsDoubleClickName     = true,
        OutfitsPrepaidSheen       = false,
        OutfitsSelectLastUsed     = false,
        OutfitsSort               = 1,
        PetsDoubleClickIcon       = true,
        PetsDoubleClickName       = true,
        PortraitButton            = true,
        ShowCollectedBookSourceText   = true,
        ShowCollectedVisualSources    = true,
        ShowCollectedVisualSourceText = true,
        ShowItemID                = false,
        ShowSetID                 = false,
        ShowSetsInAppearances     = true,
        ShowWowheadSetIcon        = false,
        TooltipCycleKeyboard      = true,
        TooltipCycleMouseWheel    = true,
    },
    TooltipSets = {
        Color          = { r = 1, g = 1, b = 1 },
        Separator      = ", ",
        SlotStateStyle = 1,
    },
    -- Indexed dynamically by frame name; each entry must be a table with a
    -- .Layout field. Metatable hands back a fresh empty-ish entry per key.
    Windows = setmetatable({}, {
        __index = function(t, k)
            local v = { Layout = false, Lock = false }
            rawset(t, k, v)
            return v
        end,
    }),
}

--=============================================================================
-- Callbacks : the real core fires these when server data arrives. No-ops here.
-- (Wire the INBOUND seam to call these + RaiseEvent when you add the server.)
--=============================================================================
local function noop() end
ez.Callbacks = setmetatable({
    LibraryListUpdated = noop,
    SearchFinished     = noop,
    ToyListUpdated     = noop,
}, { __index = function() return noop end })

--=============================================================================
-- AceAddon shim : only timer scheduling is referenced. Route through C_Timer
-- (provided by modules/utils.lua, loaded earlier in projectebonhold.toc).
--=============================================================================
ez.AceAddon = {
    ScheduleRepeatingTimer = function(_, fn, interval)
        if C_Timer and C_Timer.NewTicker then return C_Timer.NewTicker(interval, fn) end
    end,
    ScheduleTimer = function(_, fn, delay)
        if C_Timer and C_Timer.After then return C_Timer.After(delay, fn) end
    end,
    CancelTimer = noop,
    CancelAllTimers = noop,
}

--=============================================================================
-- Event bus : the visual layer's pub/sub. This is REAL (the UI uses it for its
-- own internal refresh signalling), so keep it fully functional.
--=============================================================================
ez.registeredEvents = ez.registeredEvents or {}

function ez:RegisterEvent(frame, event)
    if not event then return end
    local set = self.registeredEvents[event]
    if not set then set = {}; self.registeredEvents[event] = set end
    set[frame] = true
end

function ez:UnregisterEvent(frame, event)
    local set = self.registeredEvents[event]
    if set then set[frame] = nil end
end

-- SEAM: INBOUND — server data handlers call this (after populating ez.Cache /
-- ez.Collections) to make the painters refresh.
function ez:RaiseEvent(event, ...)
    local set = self.registeredEvents[event]
    if not set then return end
    local n, a = select("#", ...), { ... }
    for frame in pairs(set) do
        local handler = frame.OnEvent or (frame.GetScript and frame:GetScript("OnEvent"))
        if handler then
            local ok, err = xpcall(
                function() return handler(frame, event, unpack(a, 1, n)) end,
                function(e) return tostring(e) .. "\n" .. debugstack(2, 12, 8) end)
            if not ok then
                local name = frame.GetName and frame:GetName() or tostring(frame)
                DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Collections] handler error on event '"
                    .. tostring(event) .. "' (frame " .. name .. "):|r\n" .. tostring(err))
            end
        end
    end
end

--=============================================================================
-- Emulated CVars : the real core stores filter/sort/tab state in Config to
-- avoid taint. In-memory here; good enough for the shell.
--=============================================================================
local cvars = {
    -- Wardrobe collected/uncollected filter defaults ON so everything shows.
    transmogrifyShowCollected   = 1,
    transmogrifyShowUncollected = 1,
}
function ez:GetCVar(name)            return cvars[name] end
function ez:SetCVar(name, value)     cvars[name] = value end
function ez:GetCVarBool(name)        return cvars[name] and cvars[name] ~= "0" and cvars[name] ~= 0 and true or false end
function ez:SetCVarBool(name, value) cvars[name] = value and 1 or 0 end
function ez:GetCVarBitfield(name, index) return false end
function ez:SetCVarBitfield(name, index, value) end

--=============================================================================
-- SEAM: OUTBOUND — every mutating UI action funnels here. No-op for now.
-- Later: translate `msg` into ProjectEbonhold.sendToServer(CS.*, body).
--=============================================================================
function ez:SendAddonMessage(msg) --[[ TODO: route to ProjectEbonhold.sendToServer ]] end
function ez:SendAddonCommand(msg) --[[ TODO: route to ProjectEbonhold.sendToServer ]] end
-- Trigger the client item cache so the wardrobe can dress its models. On 3.3.5
-- a bare GetItemInfo(id) request can be unreliable, so we also force a query via
-- a hidden tooltip SetHyperlink (the robust cache-warm method). The wardrobe
-- polls GetItemInfo and dresses each model once its item arrives.
local queryTooltip
function ez:QueryItem(itemID)
    if type(itemID) ~= "number" or itemID == 0 then return end
    if GetItemInfo(itemID) then return end            -- already cached
    if not queryTooltip then
        queryTooltip = CreateFrame("GameTooltip", "ezCollectionsItemQueryTooltip", nil, "GameTooltipTemplate")
    end
    queryTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    queryTooltip:SetHyperlink("item:" .. itemID)      -- forces a server item query
    queryTooltip:Hide()
end

--=============================================================================
-- ezCollections:* accessor methods used by the visual layer.
-- Getters return "nothing owned / no premium" shaped empties; string getters
-- return "" so concatenation never errors; actions are no-ops.
--=============================================================================
local function retNil()   return nil end
local function retFalse() return false end
local function retZero()  return 0 end
local function retEmptyStr() return "" end
local function retEmptyTbl() return {} end

-- booleans (ownership / capability / gating) -> false
for _, m in ipairs({
    "HasSkin","HasAvailableSkin","HasAvailableBook","HasBook","HasToy",
    "IsSingleSourceVisual","IsStoreItem","IsStoreOrSubscriptionExclusiveItem",
    "AreWeaponsImpossibleToDisplayInPlayerModel","CanEquipItemIntoSlot",
    "PlayerCanDualWield","IsMountScalingAllowed","CanClaimSetSlotSkin",
    "UseServersideTextSearch",
    "IsActiveLibrarySubscription","IsActiveToySubscription","IsActiveMountSubscription",
    "IsActivePetSubscription","IsActiveMountPremium","IsActiveMountAccount","IsActivePetAccount",
    "IsActiveMountAccountMount","IsActiveMountSubscriptionMount","IsActivePetAccountPet",
    "IsActivePetSubscriptionPet","IsActiveToySubscriptionToy","IsActiveLibrarySubscriptionBook",
}) do ez[m] = retFalse end

-- numbers (times / cooldown endpoints) -> 0
for _, m in ipairs({
    "GetActiveLibrarySubscriptionEndTime","GetActiveToySubscriptionEndTime",
    "GetActiveMountSubscriptionEndTime","GetActivePetSubscriptionEndTime",
    "GetActiveMountPremiumEndTime","GetMountScalingEndTime",
}) do ez[m] = retZero end

-- nil-returning lookups (info tuples / ids) -> nil
for _, m in ipairs({
    "GetSkinInfo","GetSkinIcon","GetEnchantFromScroll","GetHiddenVisualItem",
    "GetHiddenVisualItemName","GetHiddenEnchant","GetInvType","GetScrollFromEnchant",
    "GetDressableFromRecipe","GetActiveSubscriptionForSkin","GetSubscriptionForSkin",
    "GetSubscriptionForSetSource","GetStoreSetSource","GetBattlePassSetSource",
    "GetToyIDByItem","GetToyInfoByItem","GetBookInfo","GetPetInfo",
    "GetEncounterInfo","GetInstanceInfo",
}) do ez[m] = retNil end

-- table-returning lookups (iterated) -> {}
for _, m in ipairs({
    "GetGroupedVisualSources","GetVisualSources","GetScrollVariantsFromEnchant",
}) do ez[m] = retEmptyTbl end

-- string-returning (concatenated / SetText) -> ""
ez.FormatRemainingTime = retEmptyStr
ez.GetCameraOptionName = retEmptyStr
ez.TransformEnchantName = function(_, name) return name or "" end

-- cooldown tuple
function ez:GetItemCooldown(itemID) return 0, 0, 0 end

-- claim / quest actions -> no-op
for _, m in ipairs({ "BeginClaimQuest","BeginClaimSetSlotQuest","ClaimQuest" }) do ez[m] = noop end

-- colour helper
function ez:RGBPercToHex(r, g, b)
    r = math.max(0, math.min(1, r or 0)); g = math.max(0, math.min(1, g or 0)); b = math.max(0, math.min(1, b or 0))
    return string.format("%02x%02x%02x", r*255, g*255, b*255)
end

-- Tooltip-builder helpers referenced by Emulation.lua's GameTooltip:SetToyByItemID
-- (only fire on a real toy tooltip; defined so a stray hover can't error).
ez.Holidays = {}
function ez.IsSameColor() return false end
function ez.FormatToPattern() return "%z%z%z" end   -- never-match pattern; keeps :match() safe
function ez:SetPendingTooltipInfo() end
function ez:ClearPendingTooltipInfo() end
function ez:FormatItemCooldown() return "" end   -- tooltip helper
function ez:IsHolidayActive() return false end
function ez:GetToyInfo() return nil end          -- ToyBox removed; used by SetToyByItemID guard

-- Dropdown engine: delegate to the client's stock UIDropDownMenu_Initialize.
function ez:UIDropDownMenu_Initialize(frame, initFn, displayMode, level, menuList)
    if UIDropDownMenu_Initialize then
        return UIDropDownMenu_Initialize(frame, initFn, displayMode, level, menuList)
    end
end

-- Safety net: any ezCollections:Method we did not enumerate becomes a tolerant
-- no-op returning nil, so a missed reference cannot crash a whole tab.
-- CAUTION: this returns a *function* (truthy), so `ez.X or default` / `if ez.X`
-- on an undefined FIELD captures the no-op instead of the default. Read fields
-- that might be absent with rawget(ez, "X") to avoid that (see collections_service).
setmetatable(ez, { __index = function(_, k)
    return function() return nil end
end })

--=============================================================================
-- C_* collection namespaces. These do not exist on the 3.3.5 client, so we
-- define them wholesale. A metatable makes every un-enumerated function a
-- no-op (prevents "attempt to call a nil value"); we then explicitly define the
-- getters whose RETURN shape must be sane for the empty state to render:
--   counts -> 0, lists -> {}, filter/shown flags -> true, favorites -> false.
--=============================================================================
local function defineNamespace(name, sane)
    local ns = _G[name] or {}
    for k, v in pairs(sane) do ns[k] = v end
    setmetatable(ns, { __index = function() return noop end })
    _G[name] = ns
    return ns
end

local T = true
local function tbl() return {} end

defineNamespace("C_ToyBox", {
    GetNumToys = retZero, GetNumFilteredToys = retZero,
    GetNumTotalDisplayedToys = retZero, GetNumLearnedDisplayedToys = retZero,
    GetToys = tbl, GetToyFromIndex = retNil, GetToyInfo = retNil, GetToyLink = retNil,
    GetIsFavorite = retFalse, HasFavorites = retFalse,
    GetCollectedShown = function() return T end, GetUncollectedShown = function() return T end,
    GetUnusableShown = function() return T end, GetSubscriptionShown = function() return T end,
    IsSourceTypeFilterChecked = function() return T end,
    IsExpansionTypeFilterChecked = function() return T end,
    IsUsingDefaultFilters = function() return T end,
})

defineNamespace("C_MountJournal", {
    GetNumMounts = retZero, GetNumDisplayedMounts = retZero,
    GetMountIDs = tbl, GetDisplayedMountInfo = retNil,
    GetMountInfoByID = retNil, GetMountInfoExtraByID = retNil,
    GetIsFavorite = retFalse, GetFavoriteMacro = retNil,
    IsMountUsable = retFalse, NeedsFanfare = retFalse,
    GetCollectedFilterSetting = function() return T end,
    IsSourceChecked = function() return T end, IsTypeChecked = function() return T end,
    IsUsingDefaultFilters = function() return T end,
})

defineNamespace("C_PetJournal", {
    GetNumPets = retZero, GetNumDisplayedPets = retZero, GetNumPetSources = retZero,
    GetNumPetTypes = retZero, GetPetIDs = tbl,
    GetPetInfoByIndex = retNil, GetPetInfoBySpeciesID = retNil,
    GetSummonedPetGUID = retNil, GetFavoriteMacro = retNil,
    PetIsFavorite = retFalse, PetIsUsable = retFalse, PetNeedsFanfare = retFalse,
    GetPetSortParameter = retZero,
    IsFilterChecked = function() return T end, IsPetSourceChecked = function() return T end,
    IsPetTypeChecked = function() return T end, IsUsingDefaultFilters = function() return T end,
})

defineNamespace("C_Library", {
    GetNumFilteredBooks = retZero, GetNumTotalDisplayedBooks = retZero,
    GetNumLearnedDisplayedBooks = retZero, GetBooks = tbl,
    GetBookFromIndex = retNil, GetBookInfo = retNil, GetBookLink = retNil,
    GetIsFavorite = retFalse,
    GetCollectedShown = function() return T end, GetUncollectedShown = function() return T end,
    GetItemsShown = function() return T end, GetObjectsShown = function() return T end,
    GetSubscriptionShown = function() return T end,
    IsSourceTypeFilterChecked = function() return T end,
    IsExpansionTypeFilterChecked = function() return T end,
    IsUsingDefaultFilters = function() return T end,
})

defineNamespace("C_Heirloom", {  -- referenced but never defined anywhere in ezCollections
    GetNumDisplayedHeirlooms = retZero,
    GetHeirloomInfo = retNil, GetHeirloomItemIDFromDisplayedIndex = retNil,
    GetHeirloomLink = retNil, GetHeirloomMaxUpgradeLevel = retZero,
    GetClassAndSpecFilters = tbl, GetHeirloomSourceFilter = tbl,
    GetCollectedHeirloomFilter = function() return T end,
    GetUncollectedHeirloomFilter = function() return T end,
    PlayerHasHeirloom = retFalse, IsHeirloomSourceValid = retFalse,
    IsPendingHeirloomUpgrade = retFalse, CanHeirloomUpgradeFromPending = retFalse,
    ShouldShowHeirloomHelp = retFalse,
})

defineNamespace("C_Transmog", {
    GetCost = function() return 0, 0 end,
    GetSlotInfo = retNil, GetSlotVisualInfo = retNil,
    GetSlotForInventoryType = retNil, GetSlotFailReason = retNil, GetSlotUseError = retNil,
    GetApplyWarnings = tbl, IsAtTransmogNPC = retFalse,
    ApplyAllPending = retFalse,   -- return value consumed (success flag)
})

defineNamespace("C_TransmogCollection", {
    GetCategoryAppearances = tbl, GetAllAppearanceSources = tbl,
    GetAppearanceSources = tbl, GetOutfits = tbl, GetOutfitSources = tbl,
    GetIllusions = tbl, GetArtifactAppearanceStrings = tbl,
    GetCategoryInfo = retNil, GetCategoryTotal = retZero, GetCategoryCollectedCount = retZero,
    GetAppearanceInfoBySource = retNil, GetAppearanceSourceInfo = retNil,
    GetSourceInfo = retNil, GetSourceIcon = retNil, GetSourceItemID = retNil,
    GetOutfitName = retNil, GetNumMaxOutfits = function() return 20 end,
    GetLatestAppearance = retNil, GetSort = retZero,
    GetCollectedShown = function() return T end, GetUncollectedShown = function() return T end,
    GetSortCollected = function() return T end, GetSortFavorites = function() return T end,
    GetIsAppearanceFavorite = retFalse, HasFavorites = retFalse,
    IsNewAppearance = retFalse, IsSearchInProgress = retFalse, IsSearchDBLoading = retFalse,
    IsUsingDefaultFilters = function() return T end,
    IsArmorTypeFilterChecked = function() return T end, IsClassFilterChecked = function() return T end,
    IsRaceFilterChecked = function() return T end, IsFactionFilterChecked = function() return T end,
    IsExpansionFilterChecked = function() return T end, IsSourceTypeFilterChecked = function() return T end,
    IsBossFilterChecked = function() return T end,
    PlayerKnowsSource = retFalse, PlayerCanCollectSource = retFalse, AccountCanCollectSource = retFalse,
    IsAppearanceHiddenVisual = retFalse, CanSetFavoriteInCategory = retFalse,
    SearchProgress = retZero, SearchSize = retZero,
    GetNumTransmogSources = retZero, GetNumMaxOutfitsID = retZero,
    SaveOutfit = retNil,          -- return value consumed (outfitID)
    SetSearch = function() return true end,  -- returns "finished"
})

defineNamespace("C_TransmogSets", {
    GetAllSets = tbl, GetBaseSets = tbl, GetVariantSets = tbl, GetUsableSets = tbl,
    GetSetSources = tbl, GetUsableSetSources = tbl, GetSourcesForSlot = tbl,
    GetSourceIDsForSlot = tbl, GetCameraIDs = tbl, GetSetNewSources = tbl,
    GetSetsContainingSourceID = tbl, GetBaseSetsCounts = retZero,
    GetBaseSetID = retNil, GetSetInfo = retNil, GetSetHyperlink = retNil,
    GetLatestSource = retNil, GetCollectionStats = retNil,
    GetBaseSetsFilter = function() return T end, GetIsFavorite = retFalse,
    HasUsableSets = retFalse, IsBaseSetCollected = retFalse,
    IsUsingDefaultBaseSetsFilters = function() return T end,
    SetHasNewSources = retFalse,          -- return value consumed
    SetHasNewSourcesForSlot = retFalse,   -- return value consumed
})

--=============================================================================
-- Shell chrome placeholders. Named frames that the ported UI hides/queries but
-- that this data-decoupled build never instantiates (micro-button alerts,
-- tutorial popups). Hidden dummies keep OnShow handlers and the micro-button
-- alert plumbing from indexing a nil global.
--=============================================================================
if not CollectionsMicroButtonAlert then
    CollectionsMicroButtonAlert = CreateFrame("Frame", "CollectionsMicroButtonAlert", UIParent)
    CollectionsMicroButtonAlert:Hide()
end
