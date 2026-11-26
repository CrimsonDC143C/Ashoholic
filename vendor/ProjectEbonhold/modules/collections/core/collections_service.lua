--[[----------------------------------------------------------------------------
    Collections data service — the SERVER SEAM, on the ProjectEbonhold protocol.

    * Fills the ezCollections helper surface the restored C_MountJournal /
      C_PetJournal shims need (favorites, fanfare, search, class/race maps,
      config flags) that used to live in the dropped core.
    * Receives the server's collection snapshots/deltas over SS.* opcodes and
      mirrors them into the data model the UI reads, then RaiseEvent()s so the
      painters refresh.
    * Sends CS.REQUEST_COLLECTIONS on login and when the journal first opens.

    Load order (projectebonhold.toc): AFTER core/stub.lua and the data catalogs
    (data/mounts*.lua, data/pets*.lua), BEFORE the restored C_* shims.

    Mounts/pets are also detected natively (GetCompanionInfo reads character_spell),
    so those tabs work even before the server replies; the server sets are stored
    for supplemental/authoritative use. Appearances + transmog have no native
    source and come entirely from the server.
------------------------------------------------------------------------------]]

local ez = _G.ezCollections
local PE = _G.ProjectEbonhold

--=============================================================================
-- 1. Helper surface required by the restored mount/pet shims
--=============================================================================

-- Class / race identity maps (were defined in the dropped ezCollections.lua).
ez.ClassIDToName = { "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT",
                     "SHAMAN","MAGE","WARLOCK","MONK","DRUID","DEMONHUNTER","ANY" }
ez.RaceIDToName  = { "HUMAN","ORC","DWARF","NIGHTELF","UNDEAD","TAUREN","GNOME",
                     "TROLL","GOBLIN","BLOODELF","DRAENEI","ANY" }
ez.ClassNameToID = {}
for id, name in ipairs(ez.ClassIDToName) do ez.ClassNameToID[name] = id end
ez.RaceNameToID  = {}
for id, name in ipairs(ez.RaceIDToName)  do ez.RaceNameToID[name]  = id end
-- 1 = Alliance, 0 = Horde (matches the mount faction flag).
ez.RaceNameToFaction = {
    HUMAN=1, DWARF=1, NIGHTELF=1, GNOME=1, DRAENEI=1,
    ORC=0, UNDEAD=0, TAUREN=0, TROLL=0, BLOODELF=0, GOBLIN=0,
}

-- Config flags the shims read (kept client-local; default off).
ez.Config.Wardrobe.MountsShowHidden    = false
ez.Config.Wardrobe.MountsUnusableInZone = false
ez.Config.Wardrobe.MountsAutoUnshift    = false
ez.Config.Wardrobe.PetsShowHidden       = false

-- Server-capability gates the shims consult (we do our own summon later).
-- rawget: the stub's catch-all __index would otherwise return a truthy no-op
-- function here, so `ez.Features or {}` must bypass the metatable.
ez.Features = rawget(ez, "Features") or {}
ez.Features.AllowMountsAutoUnshift = false

-- Favorites are client-local (SavedVariables); "new"/fanfare is session state.
local mountFavorites, petFavorites = {}, {}
local mountFanfare,  petFanfare  = {}, {}
function ez:GetMountFavoritesContainer()  return mountFavorites end
function ez:GetPetFavoritesContainer()    return petFavorites  end
function ez:GetMountNeedFanfareContainer() return mountFanfare end
function ez:GetPetNeedFanfareContainer()   return petFanfare   end

-- Search helpers (name substring, case-insensitive).
function ez:PrepareSearchQuery(search)
    if not search or search == "" then return nil end
    return string.lower(search)
end
function ez:TextMatchesSearch(text, prepared)
    if not prepared then return true end
    if not text then return false end
    return string.find(string.lower(text), prepared, 1, true) ~= nil
end

--=============================================================================
-- 2. Collection data model (mirrors the server truth)
--=============================================================================
ez.Collections = rawget(ez, "Collections") or {}   -- rawget: bypass the __index net
ez.Collections.Mounts       = {}   -- [spellID]    = true   (server-known mounts)
ez.Collections.Pets         = {}   -- [spellID]    = true
ez.Collections.Appearances  = {}   -- [displayID]  = true   (collected item visuals, from custom_account_transmog)
ez.TransmogSlots            = {}   -- [slotID]     = { item = itemEntry, illusion = id }
ez.Outfits                  = {}   -- [outfitID]   = { name = "...", sources = { [slot] = sourceID } }
ez.OutfitMax                = 10   -- max outfits (from the server; Transmogrification.MaxSets)

-- ez:IsVisualCollected(visualID) is defined in data/appearances.lua (it maps
-- the visual's representative itemID -> displayID -> this set).
function ez:GetTransmogForSlot(slotID)
    local s = ez.TransmogSlots[slotID]
    if s then return s.item, s.illusion end
end

--=============================================================================
-- 3. Parsing helpers
--=============================================================================
local function eachNumber(body, fn)          -- "12 34 56" -> fn(12) fn(34) fn(56)
    if not body then return end
    for tok in string.gmatch(body, "%-?%d+") do fn(tonumber(tok)) end
end
local function replaceSet(setTable, body)    -- snapshot: wipe then fill
    table.wipe(setTable)
    eachNumber(body, function(id) if id then setTable[id] = true end end)
end

--=============================================================================
-- 4. Inbound server messages  (SEAM: INBOUND)
--=============================================================================
if PE and PE.onEventReceived and PE.SS then
    local SS = PE.SS

    -- Snapshots ------------------------------------------------------------
    PE.onEventReceived(SS.SEND_COLLECTED_MOUNTS, function(body)
        replaceSet(ez.Collections.Mounts, body)
        if C_MountJournal and C_MountJournal.RefreshMounts then C_MountJournal.RefreshMounts() end
        ez:RaiseEvent("COMPANION_UPDATE", "MOUNT")
    end)

    PE.onEventReceived(SS.SEND_COLLECTED_PETS, function(body)
        replaceSet(ez.Collections.Pets, body)
        if C_PetJournal and C_PetJournal.RefreshPets then C_PetJournal.RefreshPets() end
        ez:RaiseEvent("COMPANION_UPDATE", "CRITTER")
    end)

    PE.onEventReceived(SS.SEND_COLLECTED_APPEARANCES, function(body)
        replaceSet(ez.Collections.Appearances, body)
        ez:RaiseEvent("TRANSMOG_COLLECTION_UPDATED")
    end)

    PE.onEventReceived(SS.SEND_TRANSMOG_SLOTS, function(body)
        table.wipe(ez.TransmogSlots)
        -- server illusion state replaces the optimistic client picks wholesale
        local ill = rawget(ez, "TransmogIllusions")
        if type(ill) == "table" then table.wipe(ill) end
        for slot, item, illusion in string.gmatch(body or "", "(%d+):(%-?%d+):?(%d*)") do
            local s = tonumber(slot)
            local e = tonumber(illusion) or 0
            ez.TransmogSlots[s] = { item = tonumber(item), illusion = e }
            if type(ill) == "table" and e ~= 0 then ill[s] = e end
        end
        ez:RaiseEvent("TRANSMOGRIFY_UPDATE")
    end)

    -- Deltas ---------------------------------------------------------------
    PE.onEventReceived(SS.SEND_MOUNT_LEARNED, function(body)
        local id = tonumber(body); if not id then return end
        ez.Collections.Mounts[id] = true
        mountFanfare[id] = true
        if C_MountJournal and C_MountJournal.RefreshMounts then C_MountJournal.RefreshMounts() end
        ez:RaiseEvent("COMPANION_LEARNED", "MOUNT")
    end)

    PE.onEventReceived(SS.SEND_PET_LEARNED, function(body)
        local id = tonumber(body); if not id then return end
        ez.Collections.Pets[id] = true
        petFanfare[id] = true
        if C_PetJournal and C_PetJournal.RefreshPets then C_PetJournal.RefreshPets() end
        ez:RaiseEvent("COMPANION_LEARNED", "CRITTER")
    end)

    PE.onEventReceived(SS.SEND_APPEARANCE_LEARNED, function(body)
        local id = tonumber(body); if not id then return end
        ez.Collections.Appearances[id] = true
        ez:RaiseEvent("TRANSMOG_COLLECTION_UPDATED")
    end)

    PE.onEventReceived(SS.SEND_TRANSMOG_SLOT_UPDATE, function(body)
        local slot, item, illusion = string.match(body or "", "(%d+):(%-?%d+):?(%d*)")
        slot, item = tonumber(slot), tonumber(item)
        if not slot then return end
        local ill = rawget(ez, "TransmogIllusions")
        if item == -1 then
            ez.TransmogSlots[slot] = nil          -- cleared -> show equipped
            if type(ill) == "table" then ill[slot] = nil end
        else
            local e = tonumber(illusion) or 0
            ez.TransmogSlots[slot] = { item = item, illusion = e }
            if type(ill) == "table" then ill[slot] = (e ~= 0) and e or nil end
        end
        ez:RaiseEvent("TRANSMOGRIFY_UPDATE")
        ez:RaiseEvent("TRANSMOGRIFY_SUCCESS")
    end)

    -- Outfits snapshot: "max;id|name|slot:entry,slot:entry;id2|name2|..."
    PE.onEventReceived(SS.SEND_TRANSMOG_OUTFITS, function(body)
        table.wipe(ez.Outfits)
        body = body or ""
        -- "activeId;maxOutfits;id|name|slot:entry,...;id2|..."  (activeId 255 = none)
        local activeStr, maxStr, rest = string.match(body, "^(%d+);(%d+);?(.*)$")
        if activeStr then
            local active = tonumber(activeStr)
            ez.ActiveOutfitId = (active and active ~= 255) and active or nil
            ez.OutfitMax = tonumber(maxStr) or ez.OutfitMax
            for chunk in string.gmatch(rest or "", "[^;]+") do
                local id, name, srcs = string.match(chunk, "^(%d+)|([^|]*)|(.*)$")
                id = tonumber(id)
                if id then
                    local sources = {}
                    for slot, entry in string.gmatch(srcs or "", "(%d+):(%d+)") do
                        sources[tonumber(slot)] = tonumber(entry)
                    end
                    ez.Outfits[id] = { name = name or "", sources = sources }
                end
            end
        end
        ez:RaiseEvent("TRANSMOG_OUTFITS_CHANGED")
    end)

    -- Transmog option "show transmog in Shadowform / druid forms": "1" or "0".
    -- The server's word only - the checkbox never trusts its own click.
    PE.onEventReceived(SS.SEND_FORM_LOOK_STATE, function(body)
        ez.FormLookHidden = (body == "1")
        ez:RaiseEvent("TRANSMOG_FORM_LOOK_CHANGED")
    end)
end

--=============================================================================
-- Outbound outfit actions (SEAM: OUTBOUND) — used by the C_* outfit backing.
--=============================================================================
local function send(op, body)
    if PE and PE.sendToServer and PE.CS and PE.CS[op] then PE.sendToServer(PE.CS[op], body or "") end
end
function ez:SetFormLookHiddenOnServer(hidden) send("REQUEST_FORM_LOOK_SET", hidden and "1" or "0") end

--=============================================================================
-- Wardrobe unlocks: a look of Data/transmog_unlock_data.lua (the server's
-- world.transmog_unlock) can be added to the collection without the item:
-- for Coins of Forgotten Appearances (taken), or, for the Archive's Torment
-- pieces, with the raid's Tormented Trophy in the bags (asked, never taken -
-- the vendor's rule). The server checks everything again and answers with
-- SEND_APPEARANCE_LEARNED (or a chat line saying why not).
--=============================================================================
ez.UnlockCoinItem = 190225
local unlockPrice, collectors, torment
local function BuildUnlock()
    if unlockPrice then return end
    unlockPrice, collectors, torment = {}, {}, {}
    local E = _G.Ebonhold or {}
    local flat = E.TransmogUnlockFlat or {}
    for i = 1, #flat - 2, 3 do unlockPrice[flat[i]] = { coins = flat[i + 1], req = flat[i + 2] } end
    for _, item in ipairs(E.TransmogCollectorsFlat or {}) do collectors[item] = true end
    for _, item in ipairs(E.TransmogTormentFlat or {}) do torment[item] = true end
    E.TransmogUnlockFlat, E.TransmogCollectorsFlat, E.TransmogTormentFlat = nil, nil, nil
end

-- coins, itemID, reqItem of the unlock offered for this visual (the cheapest coin
-- price first, else an item-gated one); nil when collected or not unlockable.
-- coins is 0 for an item-gated unlock (reqItem asked, not taken).
function ez:GetVisualUnlock(visualID)
    BuildUnlock()
    if not visualID or ez:IsVisualCollected(visualID) then return nil end
    local best, bestItem
    for _, item in ipairs(ez:GetVisualSourceItems(visualID) or { visualID }) do
        local p = unlockPrice[item]
        if p and (not best or (p.req == 0 and (best.req ~= 0 or p.coins < best.coins))) then best, bestItem = p, item end
    end
    if best then return best.coins, bestItem, best.req end
end

local function sourcesIn(set, visualID)
    BuildUnlock()
    for _, item in ipairs(ez:GetVisualSourceItems(visualID) or { visualID }) do
        if set[item] then return true end
    end
    return false
end
-- "Collector's": the Archive's coin cosmetics. "Torment": the Archive's Torment pieces.
function ez:IsCollectorsVisual(visualID) return sourcesIn(collectors, visualID) end
function ez:IsTormentVisual(visualID) return sourcesIn(torment, visualID) end

-- Name (or link) of the item an unlock asks for; queries the item cache when it is unknown.
function ez:GetUnlockReqName(reqItem, asLink)
    local name, link = GetItemInfo(reqItem)
    if not name then ez:QueryItem(reqItem) end
    return (asLink and link) or name or ProjectEbonhold.L["Tormented Trophy"]
end

-- Short price text: "12 Coins" or "Tormented Trophy of Ragnaros (kept)".
function ez:GetUnlockPriceText(coins, reqItem)
    if reqItem and reqItem ~= 0 then
        return ProjectEbonhold.T("{item} (kept)", { item = ez:GetUnlockReqName(reqItem) })
    end
    return format(ProjectEbonhold.L["%d |4Coin:Coins;"], coins)
end

function ez:UnlockAppearanceOnServer(itemID) send("REQUEST_UNLOCK_APPEARANCE", tostring(itemID)) end

StaticPopupDialogs["EBONHOLD_UNLOCK_APPEARANCE"] = {
    text = ProjectEbonhold.L["Unlock this appearance?|n|n%s|n|nCost: %s"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, itemID) ez:UnlockAppearanceOnServer(itemID) end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

-- Confirm, then ask the server. Refuses early (chat line) when the bags lack the price.
function ez:PromptUnlockAppearance(visualID)
    local coins, itemID, reqItem = ez:GetVisualUnlock(visualID)
    if not coins then return end
    if reqItem ~= 0 then
        if (GetItemCount(reqItem) or 0) < 1 then
            DEFAULT_CHAT_FRAME:AddMessage(ProjectEbonhold.T("|cffff2020You need {item} in your bags to unlock this appearance.|r", { item = ez:GetUnlockReqName(reqItem, true) }))
            return
        end
    else
        local have = GetItemCount(ez.UnlockCoinItem) or 0
        if have < coins then
            DEFAULT_CHAT_FRAME:AddMessage(ProjectEbonhold.T("|cffff2020You need {cost} Coins of Forgotten Appearances to unlock this appearance (you have {have}).|r", { cost = coins, have = have }))
            return
        end
    end
    local name, link = GetItemInfo(itemID)
    local price = reqItem ~= 0 and ProjectEbonhold.T("{item} in your bags (kept)", { item = ez:GetUnlockReqName(reqItem, true) })
        or format(ProjectEbonhold.L["%d |4Coin:Coins; of Forgotten Appearances"], coins)
    local dialog = StaticPopup_Show("EBONHOLD_UNLOCK_APPEARANCE", link or name or ProjectEbonhold.T("item {id}", { id = itemID }), price)
    if dialog then dialog.data = itemID end
end
-- id present -> overwrite that outfit; 255 -> new. Body: "id|name|slot:entry,..."
function ez:SaveOutfitToServer(id, name, sourcesCsv) send("REQUEST_OUTFIT_SAVE", tostring(id or 255) .. "|" .. (name or ProjectEbonhold.L["Outfit"]) .. "|" .. (sourcesCsv or "")) end
function ez:RenameOutfitOnServer(id, name)       send("REQUEST_OUTFIT_RENAME", tostring(id) .. "|" .. (name or "")) end
function ez:DeleteOutfitOnServer(id)             send("REQUEST_OUTFIT_DELETE", tostring(id)) end
function ez:ApplyOutfitOnServer(id)              send("REQUEST_OUTFIT_APPLY", tostring(id)) end

--=============================================================================
-- 5. Outbound request  (SEAM: OUTBOUND)
--=============================================================================
function ez:RequestCollections(which)
    if PE and PE.sendToServer and PE.CS and PE.CS.REQUEST_COLLECTIONS then
        PE.sendToServer(PE.CS.REQUEST_COLLECTIONS, which or "")
    end
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        ez:RequestCollections("")   -- full pull on login
        -- Original ezCollections keeps the weapon-preview creature's model warm with
        -- a recurring ticker (ezCollections.lua PREVIEWCREATURE handler); without it
        -- the model can get unloaded and shows the fallback body instead of invisible.
        --
        -- THE TICKER IS GONE. ezCollectionsModelPreloader is a <DressUpModel>
        -- (Blizzard_Wardrobe.xml), and :Refresh() makes the client re-stream that
        -- model. ClientExt.dll hooks DressUpModel and keeps its own map of models,
        -- and that map is the one whose bucket chain goes circular and hangs the
        -- client (a worker thread then spins at 100% of a core while the main
        -- thread waits on it forever). Re-streaming a model every 5 seconds for
        -- the whole session, with no collections UI on screen and nobody looking
        -- at the preview, was free pressure on exactly that code path.
        --
        -- The model only has to be warm when the preview can actually be SEEN, so
        -- it is refreshed from CollectionsJournal's OnShow below instead.
        if ezCollectionsModelPreloader and ezCollectionsModelPreloader.Refresh then
            ezCollectionsModelPreloader:Refresh()
        end
    end)
end

-- Also refresh the first time the journal is shown (cheap; server can dedupe),
-- and re-warm the preview model here -- this is the moment it starts mattering,
-- and it replaces the permanent 5s ticker removed above.
if CollectionsJournal then
    CollectionsJournal:HookScript("OnShow", function()
        if not CollectionsJournal.__ebRequested then
            CollectionsJournal.__ebRequested = true
            ez:RequestCollections("")
        end
        if ezCollectionsModelPreloader and ezCollectionsModelPreloader.Refresh then
            ezCollectionsModelPreloader:Refresh()
        end
    end)
end
