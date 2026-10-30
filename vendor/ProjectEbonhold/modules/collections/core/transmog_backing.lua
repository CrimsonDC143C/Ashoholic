--[[----------------------------------------------------------------------------
    C_TransmogCollection / C_Transmog backing.

    Replaces the stub's empty transmog APIs with real ones driven by:
      * ezCollections.AppearanceCatalog  (data/appearances.lua) — every visual
        per category, identified by a representative itemID.
      * ezCollections.Collections.Appearances — collected displayIDs from the
        server (SEND_COLLECTED_APPEARANCES).
      * ezCollections.TransmogSlots — applied transmog per slot
        (SEND_TRANSMOG_SLOTS), keyed by the server's 0-based EQUIPMENT_SLOT id.

    Model of identity (see data/appearances.lua):
      visual  = representative itemID   (UI treats visualID as an item)
      source  = itemID
      A visual is collected iff its displayID is in Collections.Appearances.

    Load order: after data/appearances.lua and core/collections_service.lua.
------------------------------------------------------------------------------]]

local ez = _G.ezCollections

-- Illusion catalog handles (Data/illusions.lua loads before this file).
-- rawget + type check: the stub's __index hands out NO-OP FUNCTIONS for
-- unknown ez keys (never nil), so a plain `ez.X and ez.X[k]` would index a
-- function and error.
local ILLUSION_CATALOG = rawget(ez, "IllusionCatalog")
if type(ILLUSION_CATALOG) ~= "table" then ILLUSION_CATALOG = {} end
local ILLUSION_BY_CARRIER = rawget(ez, "IllusionByCarrier")
if type(ILLUSION_BY_CARRIER) ~= "table" then ILLUSION_BY_CARRIER = {} end

local function itemNameQualityIcon(itemID)
    local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    return name, quality, icon
end

--=============================================================================
-- C_TransmogCollection — the appearance browser
--=============================================================================
local TC = _G.C_TransmogCollection

-- "Hide this slot" — a synthetic visual whose value matches the server's
-- InvisibleEntry (UINT32_MAX), so ApplyAllPending sends it straight through as the
-- hide marker and the server maps it to "no visual".
local HIDE_VISUAL = 4294967295
function ez:GetHiddenVisualItem() return HIDE_VISUAL end
function ez:GetHiddenVisualItemName() return TRANSMOG_SLOT_HIDE_VISUAL or "Hide" end

-- Collected / Not-Collected filter, backed by the CVars FilterVisuals reads.
-- (Overrides the stub getters so the standard filter menu entries actually work.)
function TC.SetCollectedShown(v)   ez:SetCVarBool("transmogrifyShowCollected", v);   ez:RaiseEvent("TRANSMOG_COLLECTION_UPDATED") end
function TC.GetCollectedShown()    return ez:GetCVarBool("transmogrifyShowCollected") end
function TC.SetUncollectedShown(v) ez:SetCVarBool("transmogrifyShowUncollected", v); ez:RaiseEvent("TRANSMOG_COLLECTION_UPDATED") end
function TC.GetUncollectedShown()  return ez:GetCVarBool("transmogrifyShowUncollected") end

-- Armor-type filter. Menu filter index = armor subclass + 1 (0 Misc..4 Plate ->
-- 1..5), and 6 (Any) for weapons/shields/other. Default: everything shown.
local armorTypeFilter = {}
function TC.SetArmorTypeFilter(f, v)
    armorTypeFilter[f] = v and true or false
    ez:RaiseEvent("TRANSMOG_COLLECTION_UPDATED")
end
function TC.SetAllArmorTypeFilters(v)
    for f = 1, 6 do armorTypeFilter[f] = v and true or false end
    ez:RaiseEvent("TRANSMOG_COLLECTION_UPDATED")
end
function TC.IsArmorTypeFilterChecked(f)
    local v = armorTypeFilter[f]
    if v == nil then return true end
    return v
end
function TC.IsVisualArmorTypeShown(visualID)
    local row = ez:GetAppearanceSourceRow(visualID)
    if not row then return true end
    local filter = 6
    if row.class == 4 and row.subclass and row.subclass >= 0 and row.subclass <= 4 then
        filter = row.subclass + 1
    end
    return TC.IsArmorTypeFilterChecked(filter)
end

-- Which appearance categories may be applied to the item equipped in a slot.
-- The wardrobe asks this before offering a weapon category (IsValidWeaponCategoryForSlot),
-- and the 3.3.5 client has no such API, so we mirror the server rule set here.
--
-- The server runs the wardrobe with AllowMixedArmorTypes / AllowMixedWeaponTypes /
-- AllowMixedInventoryTypes on, so the only pairings it still refuses are across the
-- "families" below (a wand can only look like a wand, a bow only like a bow or a gun
-- or a crossbow, ...), plus the off-hand exception: shields, held-in-off-hand items
-- and one-hand melee weapons all live in the same slot, so they can share a look
-- (a shield worn as a sword, an axe, a dagger...).
local FAMILY_MELEE, FAMILY_BGC, FAMILY_WAND    = 1, 2, 3
local FAMILY_THROWN, FAMILY_FISHING            = 4, 5
local FAMILY_SHIELD, FAMILY_HOLDABLE           = 6, 7
local CATEGORY_FAMILY = {
    [LE_TRANSMOG_COLLECTION_TYPE_1H_AXE]   = FAMILY_MELEE,
    [LE_TRANSMOG_COLLECTION_TYPE_1H_SWORD] = FAMILY_MELEE,
    [LE_TRANSMOG_COLLECTION_TYPE_1H_MACE]  = FAMILY_MELEE,
    [LE_TRANSMOG_COLLECTION_TYPE_DAGGER]   = FAMILY_MELEE,
    [LE_TRANSMOG_COLLECTION_TYPE_FIST]     = FAMILY_MELEE,
    [LE_TRANSMOG_COLLECTION_TYPE_2H_AXE]   = FAMILY_MELEE,
    [LE_TRANSMOG_COLLECTION_TYPE_2H_SWORD] = FAMILY_MELEE,
    [LE_TRANSMOG_COLLECTION_TYPE_2H_MACE]  = FAMILY_MELEE,
    [LE_TRANSMOG_COLLECTION_TYPE_STAFF]    = FAMILY_MELEE,
    [LE_TRANSMOG_COLLECTION_TYPE_POLEARM]  = FAMILY_MELEE,
    [LE_TRANSMOG_COLLECTION_TYPE_BOW]      = FAMILY_BGC,
    [LE_TRANSMOG_COLLECTION_TYPE_GUN]      = FAMILY_BGC,
    [LE_TRANSMOG_COLLECTION_TYPE_CROSSBOW] = FAMILY_BGC,
    [LE_TRANSMOG_COLLECTION_TYPE_WAND]     = FAMILY_WAND,
    [LE_TRANSMOG_COLLECTION_TYPE_THROWN]   = FAMILY_THROWN,
    [LE_TRANSMOG_COLLECTION_TYPE_FISHING_POLE] = FAMILY_FISHING,
    [LE_TRANSMOG_COLLECTION_TYPE_SHIELD]   = FAMILY_SHIELD,
    [LE_TRANSMOG_COLLECTION_TYPE_HOLDABLE] = FAMILY_HOLDABLE,
}
-- Families that share the off-hand slot and may therefore be mixed. The caller has
-- already checked canOffHand, and no ranged / wand / thrown category is off-hand
-- capable, so this only ever widens the off-hand. Two-handers are: the client hangs
-- a 2H display off the left hand the same way Titan's Grip does.
local OFFHAND_FAMILIES = {
    [FAMILY_MELEE] = true, [FAMILY_SHIELD] = true, [FAMILY_HOLDABLE] = true,
}
-- Fallback for items the catalog does not know (custom items, mostly): equip
-- location is the best signal the 3.3.5 GetItemInfo gives us.
local EQUIPLOC_FAMILY = {
    INVTYPE_WEAPON = FAMILY_MELEE, INVTYPE_WEAPONMAINHAND = FAMILY_MELEE,
    INVTYPE_WEAPONOFFHAND = FAMILY_MELEE, INVTYPE_2HWEAPON = FAMILY_MELEE,
    INVTYPE_SHIELD = FAMILY_SHIELD, INVTYPE_HOLDABLE = FAMILY_HOLDABLE,
    INVTYPE_RANGED = FAMILY_BGC, INVTYPE_RANGEDRIGHT = FAMILY_BGC,
    INVTYPE_THROWN = FAMILY_THROWN,
}
local function familyOfItem(itemID)
    local row = ez:GetAppearanceSourceRow(itemID)
    if row and row.category then return CATEGORY_FAMILY[row.category] end
    return EQUIPLOC_FAMILY[select(9, GetItemInfo(itemID)) or ""]
end

function TC.IsCategoryValidForItem(categoryID, itemID)
    if not itemID or itemID == 0 then return false end
    local catFamily = CATEGORY_FAMILY[categoryID]
    if not catFamily then return true end          -- armor: the slot already decided
    local itemFamily = familyOfItem(itemID)
    if not itemFamily then return true end         -- unknown item: do not block the player
    if catFamily == itemFamily then return true end
    return (OFFHAND_FAMILIES[catFamily] and OFFHAND_FAMILIES[itemFamily]) == true
end

-- name, isWeapon, canEnchant, canMainHand, canOffHand, canRanged, invType
function TC.GetCategoryInfo(categoryID)
    local m = ez:GetCategoryMeta(categoryID)
    if not m then return nil end
    return m.name, m.isWeapon, false, m.canMainHand or false, m.canOffHand or false, m.canRanged or false, m.invType
end

-- list of { visualID = repItemID, isCollected, isUsable, isFavorite, isHideVisual, uiOrder }
function TC.GetCategoryAppearances(categoryID)
    local order = ez:GetCategoryVisuals(categoryID)
    if not order then return {} end
    local out = {}
    -- "Hide this slot" option, first, for armor slots (the server rejects hiding
    -- weapon slots, so don't offer it there).
    local meta = ez:GetCategoryMeta(categoryID)
    if meta and not meta.isWeapon then
        out[#out + 1] = {
            visualID    = HIDE_VISUAL,
            isCollected = true,
            isUsable    = true,
            isFavorite  = false,
            isHideVisual = true,
            uiOrder     = #order + 1,   -- sorts to the front
        }
    end
    for i = 1, #order do
        local visualID = order[i]
        out[#out + 1] = {
            visualID    = visualID,
            isCollected = ez:IsVisualCollected(visualID),
            isUsable    = true,
            isFavorite  = false,
            isHideVisual = false,
            uiOrder     = #order - i,   -- stable; higher = earlier
        }
    end
    return out
end

function TC.GetCategoryTotal(categoryID)
    local order = ez:GetCategoryVisuals(categoryID)
    return order and #order or 0
end

function TC.GetCategoryCollectedCount(categoryID)
    local order = ez:GetCategoryVisuals(categoryID)
    if not order then return 0 end
    local n = 0
    for i = 1, #order do
        if ez:IsVisualCollected(order[i]) then n = n + 1 end
    end
    return n
end

-- list of { sourceID = itemID, itemID, isCollected, useError, name, quality, sourceType, isHideVisual }
function TC.GetAppearanceSources(visualID)
    local items = ez:GetVisualSourceItems(visualID)
    if not items then return {} end
    local collected = ez:IsVisualCollected(visualID)
    local out = {}
    for i = 1, #items do
        local itemID = items[i]
        local name, quality = itemNameQualityIcon(itemID)
        out[i] = {
            sourceID    = itemID,
            itemID      = itemID,
            isCollected = collected,
            useError    = nil,
            name        = name,
            quality     = quality,
            sourceType  = 1,
            isHideVisual = false,
        }
    end
    return out
end

-- categoryID, appearanceID (visual = rep itemID), canEnchant, name, icon, isCollected
function TC.GetAppearanceSourceInfo(sourceID)
    local row = ez:GetAppearanceSourceRow(sourceID)
    if not row then return nil end
    local _, _, icon = itemNameQualityIcon(sourceID)
    -- position 6 must be the item hyperlink (callers use it for chat linking)
    local link = select(2, GetItemInfo(sourceID))
    -- position 3 (canEnchant): true for weapon sources -- gates the illusion
    -- system (WardrobeCollectionFrame_CanEnchantSource then double-checks the
    -- actual model has attachment points before offering enchants).
    local m = ez.GetCategoryMeta and ez:GetCategoryMeta(row.category)
    local canEnchant = (m and m.isWeapon) and true or false
    return row.category, row.visual, canEnchant, icon, ez:IsVisualCollected(row.visual), link
end

function TC.GetAppearanceInfoBySource(sourceID)
    local row = ez:GetAppearanceSourceRow(sourceID)
    if not row then return nil end
    local collected = ez:IsVisualCollected(row.visual)
    return {
        appearanceID           = row.visual,
        appearanceIsCollected  = collected,
        sourceID               = sourceID,
        sourceIsCollected      = collected,
        categoryID             = row.category,
    }
end

function TC.GetSourceInfo(sourceID)
    local row = ez:GetAppearanceSourceRow(sourceID)
    if not row then return nil end
    local name, quality, icon = itemNameQualityIcon(sourceID)
    return {
        visualID    = row.visual,
        itemID      = sourceID,
        isCollected = ez:IsVisualCollected(row.visual),
        quality     = quality or row.quality,
        name        = name,
        icon        = icon,
        categoryID  = row.category,
    }
end

function TC.PlayerKnowsSource(sourceID)
    local row = ez:GetAppearanceSourceRow(sourceID)
    return row ~= nil and ez:IsVisualCollected(row.visual)
end
function TC.PlayerCanCollectSource(sourceID) return ez:GetAppearanceSourceRow(sourceID) ~= nil end
function TC.AccountCanCollectSource(sourceID) return ez:GetAppearanceSourceRow(sourceID) ~= nil end

function TC.GetSourceIcon(sourceID)
    local _, _, icon = itemNameQualityIcon(sourceID)
    return icon
end

function TC.IsAppearanceHiddenVisual(id) return id == HIDE_VISUAL end
function TC.IsSearchInProgress() return false end

--=============================================================================
-- Search box backing — plain client-side name matching. The stub's SetSearch
-- was a return-true no-op, so typing in the wardrobe search box did nothing.
-- Synchronous (no progress tracking); raising TRANSMOG_COLLECTION_UPDATED
-- makes the items frame re-run RefreshVisualsList/FilterVisuals, which calls
-- IsSearchMatch below per visual.
--=============================================================================
local searchNeedle = {}   -- [searchType] = lowercased needle

function TC.SetSearch(searchType, text)
    searchNeedle[searchType or 1] = (text and text ~= "") and string.lower(text) or nil
    ez:RaiseEvent("TRANSMOG_COLLECTION_UPDATED")
    return true   -- finished immediately
end

function TC.ClearSearch(searchType)
    searchNeedle[searchType or 1] = nil
    ez:RaiseEvent("TRANSMOG_COLLECTION_UPDATED")
    return true
end

-- (match, nameMissing). nameMissing = the item's name isn't cached yet, so
-- the caller can warm the cache and re-filter once it arrives.
function TC.IsSearchMatch(visualID, searchType, fallbackName)
    local needle = searchNeedle[searchType or 1]
    if not needle then return true, false end
    local ill = ILLUSION_BY_CARRIER[visualID]
    local name = (ill and ill.name) or fallbackName or GetItemInfo(visualID)
    if not name then return false, true end
    return string.find(string.lower(name), needle, 1, true) ~= nil, false
end

--=============================================================================
-- Illusions (weapon enchant visuals) — catalog in Data/illusions.lua.
-- Ids live in "carrier item" space (each illusion is pinned to a unique
-- stock item id); ez:GetEnchantFromScroll(carrier) resolves the enchant for
-- the model preview, ez:GetScrollFromEnchant maps server state back.
--=============================================================================
-- applied illusion per 0-based EQUIPMENT_SLOT: [eqSlot] = enchantId.
-- Fed optimistically on Apply and by the (future) server push seam.
-- rawget + type check: the stub's __index hands out NO-OP FUNCTIONS for
-- unknown ez keys (never nil), so `ez.X or {}` would keep the function.
if type(rawget(ez, "TransmogIllusions")) ~= "table" then
    ez.TransmogIllusions = {}
end
function TC.GetIllusions()
    local list = {}
    for _, ill in ipairs(ILLUSION_CATALOG) do
        list[#list + 1] = {
            sourceID = ill.carrier, visualID = ill.carrier,
            isCollected = true, isUsable = true,
            name = ill.name,
        }
    end
    return list
end

-- visualID, name, hyperlink, icon
function TC.GetIllusionSourceInfo(sourceID)
    local ill = ILLUSION_BY_CARRIER[sourceID]
    if not ill then return nil end
    return ill.carrier, ill.name, nil, ill.icon
end

-- Weapon shown in illusion cells when the equipped weapon can't host
-- enchants (or nothing is equipped): a plain 1H sword that exists on any
-- 3.3.5 database.
function TC.GetIllusionFallbackWeaponSource()
    return 25 -- Worn Shortsword
end

-- Numeric inventory type of an item (the stub returned nil, which silently
-- disabled the whole weapon-model preview dance in WardrobeTransmogFrame_
-- Update -- previewing a 2H appearance with an off-hand equipped dressed
-- the off-hand LAST and knocked the 2H off the model: "no render").
local EQUIPLOC_TO_INVTYPE = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7,
    INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
    INVTYPE_TRINKET = 12, INVTYPE_WEAPON = 13, INVTYPE_SHIELD = 14,
    INVTYPE_RANGED = 15, INVTYPE_CLOAK = 16, INVTYPE_2HWEAPON = 17,
    INVTYPE_BAG = 18, INVTYPE_TABARD = 19, INVTYPE_WEAPONMAINHAND = 21,
    INVTYPE_WEAPONOFFHAND = 22, INVTYPE_HOLDABLE = 23, INVTYPE_AMMO = 24,
    INVTYPE_THROWN = 25, INVTYPE_RANGEDRIGHT = 26, INVTYPE_RELIC = 28,
}
function ez:GetInvType(itemID)
    if not itemID or itemID == 0 then return nil end
    local equipLoc = select(9, GetItemInfo(itemID))
    return equipLoc and EQUIPLOC_TO_INVTYPE[equipLoc] or nil
end

-- Camera: zoom the model to the slot (else every cell looks like the whole
-- character). Every item in a category shares the same slot, so we can use the
-- category's invType even before the item caches; prefer the item's own once
-- available. Camera.lua wants the "INVTYPE_*" STRING. pcall-guarded.
local INVTYPE_NUM_TO_NAME = {
    [1] = "INVTYPE_HEAD",  [3] = "INVTYPE_SHOULDER", [16] = "INVTYPE_CLOAK",
    [5] = "INVTYPE_CHEST", [19] = "INVTYPE_TABARD",  [4] = "INVTYPE_BODY",
    [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND",    [6] = "INVTYPE_WAIST",
    [7] = "INVTYPE_LEGS",  [8] = "INVTYPE_FEET",     [26] = "INVTYPE_RANGEDRIGHT",
    [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD", [23] = "INVTYPE_HOLDABLE",
    [17] = "INVTYPE_2HWEAPON", [15] = "INVTYPE_RANGED", [25] = "INVTYPE_THROWN",
}
function TC.GetAppearanceCameraID(visualID, fallbackCategory)
    if type(visualID) ~= "number" then return nil end
    -- Original ezCollections framing: weapons get their dedicated weapon camera
    -- (ezCollections.Cameras has real tuned entries per invType/subclass), armor
    -- gets the character camera. subType is passed as nil (ItemSubTypeToSubClassID,
    -- used by the original to resolve a weapon-subclass-specific entry, doesn't
    -- exist in this shell) -- GetWeaponCameraID falls back to the generic per-invType
    -- entry, which still has real tuned data for every weapon category.
    local _, isWeapon, _, _, _, _, catInvNum = TC.GetCategoryInfo(fallbackCategory)
    local invType = select(9, GetItemInfo(visualID)) or INVTYPE_NUM_TO_NAME[catInvNum]
    if not invType then return nil end
    local ok, cam
    if isWeapon and ez.GetWeaponCameraID then
        ok, cam = pcall(function() return ez:GetWeaponCameraID(invType, nil, nil) end)
    elseif ez.GetCharacterCameraID then
        ok, cam = pcall(function() return ez:GetCharacterCameraID(invType, nil) end)
    end
    return ok and cam or nil
end
function TC.GetAppearanceCameraIDBySource(sourceID, fallbackCategory)
    return TC.GetAppearanceCameraID(sourceID, fallbackCategory)
end

--=============================================================================
-- C_Transmog — current appearance per slot (for the Transmogrify panel)
--
-- The wardrobe calls GetSlotVisualInfo(GetInventorySlotInfo(slotName), type),
-- i.e. a 1-based client INVSLOT. The server's TransmogSlots use the 0-based
-- EQUIPMENT_SLOT id, so we map invSlot-1. (Verify against your client in-game;
-- if the numbering already matches, drop the -1.)
--=============================================================================
local TR = _G.C_Transmog
local APPEARANCE = LE_TRANSMOG_TYPE_APPEARANCE or 0

local function VisualOfItem(itemID)
    if not itemID or itemID == 0 then return 0, 0 end
    local row = ez:GetAppearanceSourceRow(itemID)
    if row then return itemID, row.visual end  -- sourceID = itemID, visualID = representative
    return itemID, itemID                        -- unknown item: fall back to itself
end

-- Client-side PENDING (preview) transmog: pending[slotID][transmogType] = sourceID.
-- This is what lets you preview ANY appearance (owned or not) on the model
-- before applying. Purely local until you press Apply.
local pending = {}
local function getPending(slotID, transmogType)
    return pending[slotID] and pending[slotID][transmogType]
end

function TR.SetPending(slotID, transmogType, sourceID)
    pending[slotID] = pending[slotID] or {}
    pending[slotID][transmogType or APPEARANCE] = sourceID
    ez:RaiseEvent("TRANSMOGRIFY_UPDATE")
end
function TR.ClearPending(slotID, transmogType)
    if pending[slotID] then pending[slotID][transmogType or APPEARANCE] = nil end
    ez:RaiseEvent("TRANSMOGRIFY_UPDATE")
end
function TR.ValidateAllPending() end
function TR.LoadSources() end

-- baseSourceID, baseVisualID, appliedSourceID, appliedVisualID, pendingSourceID, pendingVisualID, hasPendingUndo
function TR.GetSlotVisualInfo(invSlot, transmogType)
    transmogType = transmogType or APPEARANCE

    if transmogType ~= APPEARANCE then
        -- ILLUSION: everything reported in carrier-item space. base = 0 (the
        -- real permanent enchant on the weapon is not part of this system).
        local appliedSourceID = 0
        local ench = ez.TransmogIllusions[invSlot - 1]
        if ench and ench ~= 0 and ez.GetScrollFromEnchant then
            appliedSourceID = ez:GetScrollFromEnchant(ench) or 0
        end
        local p = getPending(invSlot, transmogType)
        local pendingSourceID = (p and p ~= 0) and p or 0
        local hasPendingUndo = (p == 0)
        return 0, 0, appliedSourceID, appliedSourceID, pendingSourceID, pendingSourceID, hasPendingUndo
    end

    local baseSourceID, baseVisualID =
        VisualOfItem(GetInventoryItemID and GetInventoryItemID("player", invSlot) or nil)

    local appliedSourceID, appliedVisualID = 0, 0
    local applied = ez.TransmogSlots[invSlot - 1]
    if applied and applied.item and applied.item ~= 0 then
        appliedSourceID, appliedVisualID = VisualOfItem(applied.item)
    end

    local pendingSourceID, pendingVisualID = 0, 0
    local p = getPending(invSlot, transmogType)
    if p and p ~= 0 then pendingSourceID, pendingVisualID = VisualOfItem(p) end
    -- p == 0 is a staged removal: report hasPendingUndo so the model previews the
    -- base (un-transmogged) look instead of the still-applied transmog.
    local hasPendingUndo = (p == 0)

    return baseSourceID, baseVisualID, appliedSourceID, appliedVisualID, pendingSourceID, pendingVisualID, hasPendingUndo
end

-- isTransmogrified, hasPending, isPendingCollected, canTransmogrify, cannotReason, hasUndo, isHideVisual, texture
function TR.GetSlotInfo(invSlot, transmogType)
    transmogType = transmogType or APPEARANCE

    if transmogType ~= APPEARANCE then
        -- ILLUSION slot state (enchant buttons next to the weapon slots)
        local applied = ez.TransmogIllusions[invSlot - 1]
        local isTransmogrified = applied ~= nil and applied ~= 0
        local p = getPending(invSlot, transmogType)
        local hasPending = p ~= nil
        local texture
        local carrier = (p and p ~= 0) and p
            or (isTransmogrified and ez.GetScrollFromEnchant and ez:GetScrollFromEnchant(applied))
        local ill = carrier and ILLUSION_BY_CARRIER[carrier]
        if ill then texture = ill.icon end
        local equippedID = GetInventoryItemID and GetInventoryItemID("player", invSlot) or nil
        local canTransmogrify = equippedID ~= nil
        return isTransmogrified, hasPending, true, canTransmogrify,
            canTransmogrify and nil or 1, false, false, texture
    end

    local equippedID = GetInventoryItemID and GetInventoryItemID("player", invSlot) or nil
    local applied = ez.TransmogSlots[invSlot - 1]
    local isTransmogrified = applied ~= nil and applied.item and applied.item ~= 0
    local p = getPending(invSlot, transmogType)
    local hasPending = p ~= nil

    local isHide = p ~= nil and TC.IsAppearanceHiddenVisual(p)
    local texture
    if isHide then
        texture = nil                                         -- "hidden" slot: no icon
    elseif p and p ~= 0 then
        texture = select(10, GetItemInfo(p))                  -- previewed appearance
    elseif isTransmogrified then
        texture = select(10, GetItemInfo(applied.item))       -- applied transmog
    elseif equippedID then
        texture = GetInventoryItemTexture("player", invSlot)  -- equipped item
    end

    local canTransmogrify = equippedID ~= nil
    local reason = canTransmogrify and nil or 1               -- 1 = TRANSMOG_INVALID_CODES "NO_ITEM"
    return isTransmogrified, hasPending, true, canTransmogrify, reason, false, isHide, texture
end

-- Report "at a transmogrifier" so the wardrobe enables slot selection + appearance
-- staging (WardrobeItemsCollectionMixin:SelectVisual bails out otherwise, which is
-- why clicking an appearance did nothing).
function TR.IsAtTransmogNPC() return true end

-- Per-slot gold cost, mirroring the server's Transmogrification::CalculateTransmogCost
-- so the UI shows the same price the server will charge. slotID is the 1-based
-- inventory slot; EQUIPMENT_SLOT = slotID - 1.
local GOLD = 10000
local function slotCost(slotID)
    local eq = slotID - 1
    if eq == 15 or eq == 16 or eq == 17 then return 300 * GOLD end  -- main/off/ranged hand
    if eq == 0  or eq == 2  or eq == 4  then return 200 * GOLD end  -- head/shoulders/chest
    return 50 * GOLD
end

-- A pending source can actually be applied if it's a hide, or an appearance the
-- player owns. Un-owned previews are skipped on Apply (rest still applies).
local function isApplyableSource(src)
    if not src or src == 0 then return false end
    if TC.IsAppearanceHiddenVisual(src) then return true end
    local row = ez:GetAppearanceSourceRow(src)
    return row ~= nil and ez:IsVisualCollected(row.visual)
end

-- cost, numChanges, tokens. numChanges must be > 0 for the Apply button to enable.
-- A pending only counts as a change (and costs gold) if it differs from the
-- appearance already applied on that slot — re-selecting the current look is free
-- and must not enable Apply.
function TR.GetCost()
    local cost, numChanges = 0, 0
    for slotID, byType in pairs(pending) do
        for ttype, src in pairs(byType) do
            if ttype ~= APPEARANCE then
                -- ILLUSION pending: a change when it differs from the applied
                -- illusion; free (the server owns any pricing).
                local appliedEnch = ez.TransmogIllusions[slotID - 1] or 0
                if src == 0 then
                    if appliedEnch ~= 0 then numChanges = numChanges + 1 end
                elseif src then
                    local pendEnch = ez.GetEnchantFromScroll and ez:GetEnchantFromScroll(src)
                    if pendEnch and pendEnch ~= appliedEnch then
                        numChanges = numChanges + 1
                    end
                end
            else
                local applied = ez.TransmogSlots[slotID - 1]
                local appliedItem = applied and applied.item or 0
                if src == 0 then
                    -- staged removal: a change (enables Apply) but free, only if the slot
                    -- currently has a transmog to remove
                    if appliedItem ~= 0 then numChanges = numChanges + 1 end
                elseif src ~= nil and isApplyableSource(src) then   -- un-owned previews don't count
                    local changed
                    if appliedItem ~= 0 then
                        local _, pv = VisualOfItem(src)          -- pending appearance
                        local _, av = VisualOfItem(appliedItem)  -- applied appearance
                        changed = (pv ~= av)
                    else
                        changed = true                           -- no transmog yet: applying is a change
                    end
                    if changed then
                        numChanges = numChanges + 1
                        cost = cost + slotCost(slotID)
                    end
                end
            end
        end
    end
    return cost, numChanges, 0
end
function TR.GetApplyWarnings() return {} end

-- Revert: clear all applied transmog on the character for free (server maps this
-- to "no visual" per slot without charging). Also drops any pending preview.
function TR.ClearAllTransmog()
    table.wipe(pending)
    local PE = _G.ProjectEbonhold
    if PE and PE.sendToServer and PE.CS and PE.CS.REQUEST_CLEAR_TRANSMOG then
        PE.sendToServer(PE.CS.REQUEST_CLEAR_TRANSMOG, "")   -- "" = all slots
    end
    ez:RaiseEvent("TRANSMOGRIFY_UPDATE")
end

-- Clear one slot's applied transmog for free. invSlotID is the 1-based inventory
-- slot; the server wants the 0-based EQUIPMENT_SLOT.
function TR.ClearSlotTransmog(invSlotID)
    if pending[invSlotID] then pending[invSlotID][APPEARANCE] = nil end
    local PE = _G.ProjectEbonhold
    if PE and PE.sendToServer and PE.CS and PE.CS.REQUEST_CLEAR_TRANSMOG then
        PE.sendToServer(PE.CS.REQUEST_CLEAR_TRANSMOG, tostring(invSlotID - 1))
    end
    ez:RaiseEvent("TRANSMOGRIFY_UPDATE")
end

-- true only if every staged (pending) source is a collected appearance. The Apply
-- button is disabled otherwise, so you can preview an uncollected look but not apply it.
function TR.AllPendingCollected()
    for _, byType in pairs(pending) do
        local src = byType[APPEARANCE]
        if src and src ~= 0 and not TC.IsAppearanceHiddenVisual(src) then
            local row = ez:GetAppearanceSourceRow(src)
            if not (row and ez:IsVisualCollected(row.visual)) then
                return false
            end
        end
    end
    return true
end

-- Commit: send the pending appearances to the server, then clear the preview.
function TR.ApplyAllPending()
    local parts, clears, illusions = {}, {}, {}
    for slotID, byType in pairs(pending) do
        local src = byType[APPEARANCE]
        if src == 0 then                                     -- staged removal -> clear that slot (free)
            clears[#clears + 1] = slotID - 1
        elseif isApplyableSource(src) then                   -- only apply owned appearances (+ hide); skip un-owned
            parts[#parts + 1] = (slotID - 1) .. ":" .. src   -- server wants 0-based EQUIPMENT_SLOT
        end
        -- Illusions travel as "eqSlot:enchantId" (0 = remove). Applied
        -- optimistically client-side too, so the UI reflects the pick even
        -- before the server seam exists / answers.
        for ttype, isrc in pairs(byType) do
            if ttype ~= APPEARANCE and isrc then
                local ench = 0
                if isrc ~= 0 and ez.GetEnchantFromScroll then
                    ench = ez:GetEnchantFromScroll(isrc) or 0
                end
                if isrc == 0 or ench ~= 0 then
                    illusions[#illusions + 1] = (slotID - 1) .. ":" .. ench
                    ez.TransmogIllusions[slotID - 1] = (ench ~= 0) and ench or nil
                end
            end
        end
    end
    local PE = _G.ProjectEbonhold
    local body = table.concat(parts, " ")
    if PE and PE.sendToServer and PE.CS then
        if #parts > 0 and PE.CS.REQUEST_APPLY_TRANSMOG then
            PE.sendToServer(PE.CS.REQUEST_APPLY_TRANSMOG, body)
        end
        if PE.CS.REQUEST_CLEAR_TRANSMOG then
            for _, eqSlot in ipairs(clears) do
                PE.sendToServer(PE.CS.REQUEST_CLEAR_TRANSMOG, tostring(eqSlot))
            end
        end
        -- Server seam for illusions: define CS.REQUEST_APPLY_ILLUSION
        -- server-side (body: space-separated "eqSlot:enchantId", 0 clears)
        -- and write PLAYER_VISIBLE_ITEM_x_ENCHANTMENT so everyone sees it.
        -- Until then the pick still applies locally (optimistic state above).
        if #illusions > 0 and PE.CS.REQUEST_APPLY_ILLUSION then
            PE.sendToServer(PE.CS.REQUEST_APPLY_ILLUSION, table.concat(illusions, " "))
        end
    end
    table.wipe(pending)
    ez:RaiseEvent("TRANSMOGRIFY_UPDATE")
    ez:RaiseEvent("TRANSMOGRIFY_SUCCESS")
    return true
end

--=============================================================================
-- Outfits — bridged to the server preset system (player->presetMap).
-- Data lives in ezCollections.Outfits (filled by SEND_TRANSMOG_OUTFITS);
-- mutations send CS requests and the server pushes a fresh snapshot back.
--=============================================================================
-- Returns an array of { outfitID = id, name = ... }. Callers rely on the object
-- shape (name matching after save, sorting, the outfit list) — returning bare ids
-- makes `outfit.name` nil, so a save spins forever waiting for a name that never matches.
function TC.GetOutfits()
    local ids = {}
    for id in pairs(ez.Outfits) do ids[#ids + 1] = id end
    table.sort(ids)
    local list = {}
    for _, id in ipairs(ids) do
        list[#list + 1] = { outfitID = id, name = ez.Outfits[id].name }
    end
    return list
end

function TC.GetOutfitName(outfitID)
    local o = ez.Outfits[outfitID]
    return o and o.name or nil
end

-- appearanceSources ({ [invSlot] = sourceID }), mainHandEnchant, offHandEnchant.
-- o.sources is keyed by the server's 0-based EQUIPMENT_SLOT; the client consumers
-- (SetSlots, the checkbox lookup) use 1-based inventory slots, so convert (+1).
function TC.GetOutfitSources(outfitID)
    local o = ez.Outfits[outfitID]
    if not o then return nil end
    local out = {}
    for eqSlot, entry in pairs(o.sources) do
        out[eqSlot + 1] = entry
    end
    return out, nil, nil
end

function TC.GetNumMaxOutfits()
    return ez.OutfitMax or 10
end

-- The outfit whose look matches the character's current look, or nil. An outfit
-- captures the effective look per slot (the transmog if set, else the equipped
-- item), so we compare against that — not just the transmogged slots.
function TC.GetActiveOutfitID()
    -- server-tracked intent first: the outfit the player last applied
    local aid = rawget(ez, "ActiveOutfitId")   -- rawget: unset key -> stub no-op fn, not nil
    if type(aid) ~= "number" then aid = nil end
    if aid and ez.Outfits[aid] then
        return aid
    end
    -- fallback: infer from the current look (e.g. right after login)
    local function effVisual(eqSlot)
        local applied = ez.TransmogSlots[eqSlot]
        local item = applied and applied.item
        if not item or item == 0 then
            item = (GetInventoryItemID and GetInventoryItemID("player", eqSlot + 1)) or 0
        end
        local _, v = VisualOfItem(item)
        return v
    end
    for id, o in pairs(ez.Outfits) do
        if next(o.sources) then
            local match, covered = true, {}
            for eqSlot, entry in pairs(o.sources) do
                covered[eqSlot] = true
                local _, ov = VisualOfItem(entry)
                if ov ~= effVisual(eqSlot) then match = false; break end
            end
            -- any transmog not captured by the outfit means it isn't the active one
            if match then
                for eqSlot, applied in pairs(ez.TransmogSlots) do
                    if applied.item and applied.item ~= 0 and not covered[eqSlot] then
                        match = false; break
                    end
                end
            end
            if match then return id end
        end
    end
    return nil
end

-- name, sources ({ [slot] = sourceID }), mainHandEnchant, offHandEnchant, icon
-- The save dialog shows a loading spinner and disables Save until this "async cost
-- query" calls back Update(false, ...). The shell has no server cost query and
-- saving an outfit is free, so resolve it immediately and allow the save.
function TC.QueryOutfitCost(name, sources, mainHandEnchant, offHandEnchant, _, prepaid, editedOutfitID)
    -- Directly clear the loading state and enable Save. We avoid the frame's
    -- Update(false, ...) path because its per-slot loop errors on buttons without
    -- a .Slot, which would leave Save disabled.
    local f = _G.WardrobeOutfitSaveFrame
    if not f then return end
    if f.LoadingSpinner then f.LoadingSpinner:Hide() end
    if f.ErrorText then f.ErrorText:Hide() end
    if f.AcceptButton then
        f.AcceptButton:SetEnabled(f.EditBox and f.EditBox:GetText() ~= "" or false)
    end
end

function TC.SaveOutfit(name, sources, mhEnchant, ohEnchant, icon, prepaid, editedOutfitID)
    local parts = {}
    if sources then
        for slot, srcID in pairs(sources) do
            if srcID and srcID ~= 0 then
                -- sources are keyed by 1-based inventory slot; the server wants
                -- 0-based EQUIPMENT_SLOT.
                parts[#parts + 1] = (slot - 1) .. ":" .. srcID
            end
        end
    end
    -- editedOutfitID present -> overwrite that outfit; nil -> the server creates a new one.
    ez:SaveOutfitToServer(editedOutfitID, name, table.concat(parts, ","))
    -- Server owns the id and pushes SEND_TRANSMOG_OUTFITS; the list refreshes then.
    return nil
end

-- The wardrobe calls ModifyOutfit(outfitID, newName) to rename.
function TC.ModifyOutfit(outfitID, newName)
    ez:RenameOutfitOnServer(outfitID, newName)
end

function TC.DeleteOutfit(outfitID)
    ez:DeleteOutfitOnServer(outfitID)
end

-- Apply the outfit's transmog on the character (server does the real work).
function TR.LoadOutfit(outfitID)
    ez:ApplyOutfitOnServer(outfitID)
end
