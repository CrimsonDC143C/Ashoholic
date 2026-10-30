local addonName, addon = ...

-- ExtBank.lua — in-game UI for the extended bank (TRUE bag-slot model).
--
-- Works like the native player bank's bag slots: you unlock extra BAG SLOTS
-- (virtually infinite), drop a container (bag) into a slot, and that bag's own
-- slots hold your items. No bag in a slot => no storage there.
--
-- Transport is NOT addon messages. ebonhold.dll exposes:
--    ExtBankOpen()                                     -> CMSG_EXTBANK_OPEN
--    ExtBankMove(sBag,sSlot,dBag,dSlot,count)          -> CMSG_EXTBANK_MOVE
--    ExtBankUnlock()                                   -> CMSG_EXTBANK_UNLOCK
--    ExtBank_OnPacket('<hex>')   <- the DLL calls THIS on SMSG_EXTBANK_UPDATE
--
-- Coordinates (see DESIGN.md):
--    0        = backpack, 1..4 = character bags     (native, live inventory)
--    19       = ext bag-slot strip (slot = bag-slot index; holds the container)
--    20+b     = contents of ext bag-slot b (slot = item slot, 0..bagSize-1)
-- dstBag sentinels: 0xFF = first free ext content slot, 0xFE = first free bags.
-- dstSlot 0xFF on bag 19 = first free (empty) bag slot.

local HDR_BAG       = 19
local CONTENT_BASE  = 20
local AUTO_EXT      = 255      -- first free content slot (dstBag)
local AUTO_INV      = 254      -- first free inventory slot (dstBag)
local AUTO_BAGSLOT  = 255      -- first free bag slot (dstSlot when dstBag==19)

-- ------------------------------------------------------------------- model ----
-- unlockedBags : number of unlocked bag slots
-- bags[b]      : { itemId, lowGuid, size } equipped container in slot b, or nil
-- cells[b][s]  : { itemId, count, lowGuid, enchant, randomProp, durability } or nil
local unlockedBags = 0
local bags  = {}
local cells = {}
local activeBag = 0
local isOpen = false
local bankOpen = false   -- true while the banker session is live (BANKFRAME_OPENED..CLOSED)
local hidBankPanel = false -- we hid the native BankFrame and owe it a restore on close

-- global search state; the box itself lives in the UI section further down
local searchText  = ""     -- lowercased needle, "" while no search is running
local matches     = {}     -- ordered { bag=, slot= } hits across EVERY bag
local matchIndex  = 0      -- which hit is focused (Enter walks through them)
local bagHasMatch = {}     -- [bagIndex] = true when that bag holds a hit
local RebuildMatches       -- defined with the UI, called from the packet handler

local function ClearModel()
    unlockedBags = 0
    for k in pairs(bags)  do bags[k]  = nil end
    for k in pairs(cells) do cells[k] = nil end
end

-- byte readers over a 1-indexed table of numbers
local function u8 (b,p) return b[p], p+1 end
local function u16(b,p) return b[p]+b[p+1]*256, p+2 end
local function u32(b,p) return b[p]+b[p+1]*256+b[p+2]*65536+b[p+3]*16777216, p+4 end
local function i32(b,p) local v; v,p=u32(b,p); if v>=2147483648 then v=v-4294967296 end return v,p end

-- --------------------------------------------------- incoming sync from DLL ---
-- Payload (see DESIGN.md SMSG_EXTBANK_UPDATE):
--   u8 kind, u8 unlockedBags, u8 nBags,
--   nBags * { u8 bagIndex, u32 itemId, u32 lowGuid, u8 size },
--   u16 nCells,
--   nCells * { u8 bag,u8 slot,u32 itemId,u32 count,u32 lowGuid,u32 enchant,i32 rnd,u8 dur }
function ExtBank_OnPacket(hex)
    if type(hex) ~= "string" or #hex < 8 then return end
    local b, n = {}, 0
    for i = 1, #hex, 2 do n = n + 1; b[n] = tonumber(string.sub(hex,i,i+1), 16) or 0 end
    local p = 1
    local kind, ub, nBags
    kind,  p = u8(b, p)
    ub,    p = u8(b, p)
    nBags, p = u8(b, p)
    if kind == 0 then            -- full snapshot
        ClearModel()
        unlockedBags = ub
        for _ = 1, nBags do
            local idx, itemId, guid, size
            idx,   p = u8 (b, p)
            itemId,p = u32(b, p)
            guid,  p = u32(b, p)
            size,  p = u8 (b, p)
            if itemId ~= 0 then bags[idx] = { itemId=itemId, lowGuid=guid, size=size }
            else bags[idx] = nil end
        end
    end
    local nCells; nCells, p = u16(b, p)
    for _ = 1, nCells do
        local bag, slot, itemId, count, guid, ench, rnd, dur
        bag,   p = u8 (b, p)
        slot,  p = u8 (b, p)
        itemId,p = u32(b, p)
        count, p = u32(b, p)
        guid,  p = u32(b, p)
        ench,  p = u32(b, p)
        rnd,   p = i32(b, p)
        dur,   p = u8 (b, p)
        local bi = bag - CONTENT_BASE
        cells[bi] = cells[bi] or {}
        if itemId == 0 then cells[bi][slot] = nil
        else cells[bi][slot] = { itemId=itemId, count=count, lowGuid=guid,
                                 enchant=ench, randomProp=rnd, durability=dur } end
    end
    if activeBag >= unlockedBags then activeBag = math.max(0, unlockedBags - 1) end
    if isOpen then
        if RebuildMatches then RebuildMatches() end   -- contents changed: re-run the search
        ExtBank_Redraw()
    end
end

-- --------------------------------------------------------------- operations ---
local function CanSend()
    if type(ExtBankMove) ~= "function" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555ExtBank:|r client (ebonhold.dll) not loaded.")
        return false
    end
    return true
end
local function DepositFromBag(bag, slot)  if CanSend() then ExtBankMove(bag, slot, AUTO_EXT, 0, 0) end end
local function DepositToSlot(bag, slot, dstBagIdx, dstSlot) if CanSend() then ExtBankMove(bag, slot, CONTENT_BASE+dstBagIdx, dstSlot, 0) end end
local function EquipBagFromBag(bag, slot)  if CanSend() then ExtBankMove(bag, slot, HDR_BAG, AUTO_BAGSLOT, 0) end end
local function EquipBagToSlot(bag, slot, dstSlot) if CanSend() then ExtBankMove(bag, slot, HDR_BAG, dstSlot, 0) end end
local function WithdrawContent(b, s)       if CanSend() then ExtBankMove(CONTENT_BASE+b, s, AUTO_INV, 0, 0) end end
local function UnequipBag(b)               if CanSend() then ExtBankMove(HDR_BAG, b, AUTO_INV, 0, 0) end end
local function MoveContent(sb, ss, db, ds) if CanSend() then ExtBankMove(CONTENT_BASE+sb, ss, CONTENT_BASE+db, ds, 0) end end
local function Unlock()
    if type(ExtBankUnlock) == "function" then
        ExtBankUnlock()
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555ExtBank:|r ExtBankUnlock is not a function (type="
            .. type(ExtBankUnlock) .. ") -- ebonhold.dll not loaded or symbol missing.")
    end
end

-- --------------------------------------------- track the cursor's source -----
-- WoW gives no API to read which bag/slot the item on the cursor came from, so
-- we remember it: every inventory pickup routes through PickupContainerItem.
-- This lets us support drag & drop of a bag onto an ext bag slot (below).
local cursorSrc = nil   -- { bag, slot } of the item currently held on the cursor
hooksecurefunc("PickupContainerItem", function(bag, slot)
    if CursorHasItem() then cursorSrc = { bag = bag, slot = slot }
    else cursorSrc = nil end   -- this call put the item back down
end)

-- ------------------------------------------- deposit / equip via inventory ----
-- Right-click a bag item while ext bank open  -> deposit into a bag's free slot.
-- Shift+right-click a CONTAINER                -> equip it into a free bag slot.
-- Drag a bag onto an ext bag slot              -> equip it into that slot.
-- Sanctioned post-hook only (never reassign the handler; the client taints that).
--
-- NOTE: the default UI routes MODIFIED (shift/ctrl/alt) clicks through
-- ContainerFrameItemButton_OnModifiedClick, NOT ...OnClick -- so a shift+right
-- click never reaches the OnClick hook (that's why the log showed shift=nil).
-- We hook both and funnel through one helper, with a debounce so the two hooks
-- can't double-fire the same equip.
-- first empty slot in the currently open (active) ext bag, or nil if none/full
local function FirstFreeActiveSlot()
    local bag = bags[activeBag]
    if not bag then return nil end
    local page = cells[activeBag] or {}
    for s = 0, (bag.size or 0) - 1 do
        if not page[s] then return s end
    end
    return nil
end

local lastEquip = { bag = -1, slot = -1, t = 0 }
local function InvRightClick(self, button, source)
    if button ~= "RightButton" then return end
    if not isOpen then return end
    local bag  = self:GetParent():GetID()
    local slot = self:GetID()
    if bag == nil or slot == nil then return end
    -- only live inventory bags (0 = backpack, 1..4) are valid sources; Bagnon
    -- routes its BANK slots (bag -1, 5..11) through the same click handler,
    -- and those must not be sent as ext-bank deposits
    if bag < 0 or bag > 4 then return end
    if IsShiftKeyDown() then
        local now = GetTime()
        if lastEquip.bag == bag and lastEquip.slot == slot and (now - lastEquip.t) < 0.3 then
            return   -- already handled by the other hook this click
        end
        lastEquip.bag, lastEquip.slot, lastEquip.t = bag, slot, now
        EquipBagFromBag(bag, slot)   -- server validates it's a bag
    elseif not IsControlKeyDown() then
        -- Deposit into the currently OPEN bag first; only fall back to
        -- "first free slot anywhere" if the open bag is full or none is selected.
        local freeSlot = FirstFreeActiveSlot()
        if freeSlot ~= nil then
            DepositToSlot(bag, slot, activeBag, freeSlot)
        else
            DepositFromBag(bag, slot)
        end
    end
end
hooksecurefunc("ContainerFrameItemButton_OnClick", function(self, button)
    InvRightClick(self, button, "OnClick")
end)
if type(ContainerFrameItemButton_OnModifiedClick) == "function" then
    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
        InvRightClick(self, button, "OnModifiedClick")
    end)
end

-- ----------------------------------------------------------------- UI ----------
-- One shared column grid (pitch = COLW) is used by BOTH the bag-slot strip and
-- the content cells, so everything lines up and wraps neatly inside the frame.
local COLS, CELL, PAD = 7, 37, 4
local COLW      = CELL + PAD        -- 41: horizontal/vertical pitch of the grid
local BAG_COLS  = COLS              -- bag slots per row before wrapping
local BAG_SIZE  = 32               -- bag-slot button size
local LEFT      = 16               -- left inset for the grids
local SEARCH_TOP = 40              -- global search box, pinned under the banner
local SEARCH_H   = 22
local UNLOCK_TOP = SEARCH_TOP + SEARCH_H + 10  -- purchase button sits below the search box
local UNLOCK_H   = 38
local STRIP_TOP = UNLOCK_TOP + UNLOCK_H + 12   -- strip starts below the fixed button
local SIDE_TOP  = 52               -- content start inside the side popup (below its banner)
local FRAME_W   = LEFT * 2 + COLS * COLW - PAD    -- main panel fits 7 bag slots
local MAX_BAGS  = 70               -- hard cap (10 rows of 7); locked slots stay visible but disabled

-- cost (in gold) of each successive bag slot; capped at the last entry
local SLOT_COSTS = { 50, 125, 250, 500, 1250, 2500, 5000, 10000 }
local GOLD_ICON  = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t"
local function NextSlotCost()
    return SLOT_COSTS[math.min(unlockedBags + 1, #SLOT_COSTS)]
end
local function FormatGold(n)
    local s = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (s:gsub("^,", ""))
end
-- gold coin icon inlined in the button label (refreshed with the real cost in Redraw)
local UNLOCK_LABEL = "Purchase"

-- confirmation before actually sending CMSG_EXTBANK_UNLOCK
StaticPopupDialogs["EXTBANK_UNLOCK_CONFIRM"] = {
    text = "Unlock bag slot %s for %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() Unlock() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}
local frame, sideFrame, bagBtns, contentBtns, unlockBtn, bankBtn, sideTitle, searchBox
local searchStatus, searchMarker   -- "3 / 12" hit counter + the pulse on the focused hit
local sideHidden = false           -- user closed the bag popup via its X

-- bag popups are always 4 columns wide; the row count grows with the bag size
local BAG_POPUP_COLS = 4
local function ColsFor(size)
    return BAG_POPUP_COLS
end

-- ------------------------------------------------------------ global search ---
-- The box on the main panel looks through EVERY unlocked bag, not just the open
-- one: bags holding a hit get a gold ring in the strip, the first hit's bag is
-- opened and the item is marked, and Enter walks through the remaining hits.

-- GetItemInfo only answers for items already in the client cache. Touching an
-- unknown one with a hidden tooltip makes the client ask the server for it; the
-- ticker below re-runs the search once those answers land.
local scanTip, namesPending
local function ItemName(itemId)
    local name = GetItemInfo(itemId)
    if name then return name end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ExtBankScanTooltip", UIParent, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    scanTip:SetHyperlink("item:" .. itemId)
    namesPending = true
    return nil
end

-- Walk every bag and collect the hits, in (bag, slot) order. A purely numeric
-- needle also matches an item id, so one can be pasted straight in.
function RebuildMatches()
    matches, bagHasMatch, namesPending = {}, {}, false
    if searchText == "" then matchIndex = 0; return end
    local byId = tonumber(searchText)
    for b = 0, MAX_BAGS - 1 do
        local bag, page = bags[b], cells[b]
        if bag and page then
            for s = 0, (bag.size or 0) - 1 do
                local d = page[s]
                if d then
                    local name = ItemName(d.itemId)
                    if (byId and d.itemId == byId)
                        or (name and string.find(string.lower(name), searchText, 1, true)) then
                        matches[#matches + 1] = { bag = b, slot = s }
                        bagHasMatch[b] = true
                    end
                end
            end
        end
    end
    if #matches == 0 then matchIndex = 0
    elseif matchIndex < 1 or matchIndex > #matches then matchIndex = 1 end
end

-- Open the bag holding hit #i and focus it (wraps around both ways).
local function FocusMatch(i)
    if #matches == 0 then ExtBank_Redraw(); return end
    if i < 1 then i = #matches elseif i > #matches then i = 1 end
    matchIndex = i
    activeBag  = matches[i].bag
    sideHidden = false
    ExtBank_Redraw()
end

-- Re-run the search a few times while item names are still on their way in.
local nameTicker = CreateFrame("Frame")
nameTicker:Hide()
nameTicker:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.3 then return end
    self.t, self.tries = 0, (self.tries or 0) + 1
    local had = #matches
    RebuildMatches()
    if #matches ~= had then
        if had == 0 then FocusMatch(1) else ExtBank_Redraw() end
    end
    if not namesPending or searchText == "" or self.tries >= 10 then self:Hide() end
end)
local function StartNameTicker()
    if namesPending and searchText ~= "" then
        nameTicker.t, nameTicker.tries = 0, 0
        nameTicker:Show()
    else
        nameTicker:Hide()
    end
end

local function BuildUI()
    frame = CreateFrame("Frame", "ExtBankFrame", UIParent)
    frame:SetWidth(FRAME_W)
    frame:SetHeight(430)
    -- Rest near the top, right of centre; the bag popup opens to its LEFT so the
    -- two sit side by side (see reference layout). Movable, so this is just a default.
    frame:SetPoint("TOP", UIParent, "TOP", 220, -60)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile="Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/DialogFrame/UI-DialogBox-Border", tile=true, tileSize=32,
        edgeSize=32, insets={left=11,right=12,top=12,bottom=11} })
    frame:Hide()

    -- Void Storage header artwork (cropped from voidstorage.blp), with title on top
    local hdr = frame:CreateTexture(nil, "ARTWORK")
    hdr:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\voidstorage.blp")
    -- crop exactly the header art (texture x 8..334): the vortex sits at x~175,
    -- the midpoint, so centering this crop centers the vortex under the title.
    -- (the old -0.041 left coord added a 21px empty band that pushed the art
    -- ~14px right of the frame's center, so the title looked off-center)
    hdr:SetTexCoord(0.015625, 0.652344, 0.001953, 0.162109)
    hdr:SetWidth(280); hdr:SetHeight(56)
    hdr:SetPoint("CENTER", frame, "TOP", 0, 18)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER", frame, "TOP", 0, 20); title:SetText("Void Storage")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() ExtBank_Close() end)

    -- ---- side popup: the selected bag's contents. Opens to the LEFT of the main
    -- panel so it grows into open space instead of over the right-side inventory,
    -- and is independently draggable by its header if you want it elsewhere. ----
    sideFrame = CreateFrame("Frame", "ExtBankBagFrame", frame)
    sideFrame:SetPoint("TOPRIGHT", frame, "TOPLEFT", -6, 0)
    sideFrame:SetBackdrop({ bgFile="Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/DialogFrame/UI-DialogBox-Border", tile=true, tileSize=32,
        edgeSize=32, insets={left=11,right=12,top=12,bottom=11} })
    sideFrame:SetMovable(true); sideFrame:EnableMouse(true)
    sideFrame:RegisterForDrag("LeftButton")
    sideFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    sideFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    sideFrame:Hide()
    local shdr = sideFrame:CreateTexture(nil, "ARTWORK")
    shdr:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    shdr:SetWidth(220); shdr:SetHeight(64)
    shdr:SetPoint("TOP", 0, 12)
    sideTitle = sideFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sideTitle:SetPoint("TOP", shdr, "TOP", 0, -14); sideTitle:SetText("Bag")
    local sclose = CreateFrame("Button", nil, sideFrame, "UIPanelCloseButton")
    sclose:SetPoint("TOPRIGHT", -8, -8)
    sclose:SetScript("OnClick", function() sideHidden = true; sideFrame:Hide() end)

    -- Global search box, on the MAIN panel: searches every unlocked bag, rings
    -- the bags that hold a hit, opens the first one and marks the item.
    -- Same component the Echo Journal and Skill Tree searches use (magnifier
    -- icon, native placeholder, clear button all built in).
    searchBox = CreateFrame("EditBox", "ExtBankSearchBox", frame, "ezCollectionsSearchBoxTemplate")
    searchBox:SetWidth(FRAME_W - LEFT * 2 - 50)
    searchBox:SetHeight(SEARCH_H)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT, -SEARCH_TOP)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    searchBox.Instructions:SetText("Search all bags")
    -- hit counter ("3 / 12") parked to the right of the box
    searchStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchStatus:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    searchStatus:SetText("")

    -- Debounce: scanning every bag on each keystroke both costs work and makes
    -- the popup hop bags mid-word, so run the search 0.2s after the last change.
    local searchDebounce = CreateFrame("Frame")
    searchDebounce:Hide()
    searchBox.debounce = searchDebounce
    local function ApplySearch()
        searchDebounce:Hide()
        local text = string.lower(searchBox:GetText() or "")
        if text == searchText then return end
        searchText = text
        RebuildMatches()
        StartNameTicker()
        if #matches > 0 then FocusMatch(1) else ExtBank_Redraw() end
    end
    searchDebounce:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t >= 0.2 then self.t = 0; ApplySearch() end
    end)

    -- HookScript, not SetScript: the template already binds its own
    -- OnTextChanged / focus scripts via XML (icon tint, clear button,
    -- placeholder) and those must keep running alongside ours.
    searchBox:HookScript("OnTextChanged", function(self)
        searchDebounce.t = 0
        searchDebounce:Show()
    end)
    searchBox:HookScript("OnEscapePressed", function(self)
        self:SetText("")   -- the template's own handler already dropped focus
        ApplySearch()
    end)
    -- Enter walks to the next hit, Shift+Enter back one; both jump bags as
    -- needed, and keep the focus so you can keep stepping through.
    searchBox:SetScript("OnEnterPressed", function(self)
        ApplySearch()
        if #matches == 0 then return end
        FocusMatch(matchIndex + (IsShiftKeyDown() and -1 or 1))
    end)
    searchBox:SetScript("OnTabPressed", function(self)
        ApplySearch()
        if #matches > 0 then FocusMatch(matchIndex + 1) end
    end)

    bagBtns = {}          -- built lazily in Redraw (count varies with unlockedBags)
    contentBtns = {}
    for idx = 0, 35 do    -- pool of up to 36 content cells (largest bag size)
        local c = idx + 1
        local btn = CreateFrame("Button", "ExtBankCell"..c, sideFrame, "ContainerFrameItemButtonTemplate")
        btn:SetWidth(CELL); btn:SetHeight(CELL)   -- positioned in ExtBank_Redraw
        btn.slot = idx
        -- gold ring drawn on cells matching the global search
        btn.searchGlow = btn:CreateTexture(nil, "OVERLAY")
        btn.searchGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        btn.searchGlow:SetBlendMode("ADD")
        btn.searchGlow:SetVertexColor(1, 0.82, 0.2)
        btn.searchGlow:SetPoint("TOPLEFT", btn, "TOPLEFT", -10, 10)
        btn.searchGlow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 10, -10)
        btn.searchGlow:Hide()
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")   -- right-click = withdraw
        btn:RegisterForDrag("LeftButton")
        -- Drop whatever is being carried onto this cell:
        --  * a real inventory item on the cursor  -> DEPOSIT into this slot
        --  * an ext-internal virtual pick (pickSrc) -> MOVE within the bank
        local function DropIntoCell(self)
            if not bags[activeBag] then return false end   -- no bag equipped here
            if CursorHasItem() then
                if cursorSrc and cursorSrc.bag >= 0 and cursorSrc.bag <= 4 then
                    DepositToSlot(cursorSrc.bag, cursorSrc.slot, activeBag, self.slot)
                elseif cursorSrc then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555ExtBank:|r items can only be deposited from your bags -- move it to your inventory first.")
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555ExtBank:|r held item's source unknown -- right-click it in your bags to deposit.")
                end
                ClearCursor(); cursorSrc = nil
                return true
            elseif ExtBank.pickSrc then
                MoveContent(ExtBank.pickSrc.bag, ExtBank.pickSrc.slot, activeBag, self.slot)
                ExtBank.pickSrc = nil
                return true
            end
            return false
        end
        btn:SetScript("OnClick", function(self, button)
            if DropIntoCell(self) then return end
            local d = cells[activeBag] and cells[activeBag][self.slot]
            if not d then return end
            if button == "RightButton" or IsShiftKeyDown() then WithdrawContent(activeBag, self.slot)
            else ExtBank.pickSrc = { bag = activeBag, slot = self.slot } end
        end)
        btn:SetScript("OnDragStart", function(self)
            local d = cells[activeBag] and cells[activeBag][self.slot]
            if d then ExtBank.pickSrc = { bag = activeBag, slot = self.slot } end
        end)
        btn:SetScript("OnReceiveDrag", function(self) DropIntoCell(self) end)
        -- Own tooltip: the default ContainerFrameItemButton_OnEnter reads a real
        -- bag slot, which these virtual cells aren't -- so drive it from our data.
        btn:SetScript("OnUpdate", nil)
        -- The template's OnLoad also set btn.UpdateTooltip; GameTooltip_OnUpdate
        -- re-invokes it every 0.2s while the tooltip is shown, which would rewrite
        -- our tooltip from SetBagItem(0,0) (same wrong tooltip on every cell).
        btn.UpdateTooltip = nil
        btn:SetScript("OnEnter", function(self)
            local d = cells[activeBag] and cells[activeBag][self.slot]
            if not d then GameTooltip:Hide(); return end
            -- anchor to the LEFT so the tooltip clears the main panel on the right
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            -- full link so enchant / random suffix show, not just the base item
            GameTooltip:SetHyperlink(("item:%d:%d:0:0:0:0:%d"):format(
                d.itemId, d.enchant or 0, d.randomProp or 0))
            if d.count and d.count > 1 then GameTooltip:AddLine("Stack: " .. d.count, 0.7, 0.7, 0.7) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        contentBtns[c] = btn
    end

    -- Pulsing marker parked on the focused hit, above the cell it marks.
    searchMarker = CreateFrame("Frame", nil, sideFrame)
    searchMarker:SetFrameLevel(sideFrame:GetFrameLevel() + 10)
    searchMarker.tex = searchMarker:CreateTexture(nil, "OVERLAY")
    searchMarker.tex:SetAllPoints()
    searchMarker.tex:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    searchMarker.tex:SetBlendMode("ADD")
    searchMarker.tex:SetVertexColor(1, 0.9, 0.4)
    searchMarker:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        self.tex:SetAlpha(0.45 + 0.55 * math.abs(math.sin(self.t * 2.2)))
    end)
    searchMarker:Hide()

    -- full-width purchase button, fixed near the TOP so it never moves as the
    -- bag strip grows below it.
    unlockBtn = utils.CreateCustomButton(nil, frame,
        { width = FRAME_W - 2 * LEFT, height = UNLOCK_H }, UNLOCK_LABEL,
        function()
            if unlockedBags >= MAX_BAGS then return end
            StaticPopup_Show("EXTBANK_UNLOCK_CONFIRM",
                tostring(unlockedBags + 1),
                FormatGold(NextSlotCost()) .. " " .. GOLD_ICON)
        end)
    unlockBtn:SetPoint("TOP", frame, "TOP", 0, -UNLOCK_TOP)

    -- "back to the personal bank" button along the bottom; only shown while a
    -- banker session is live (bankOpen), since it swaps the two windows.
    bankBtn = utils.CreateSimpleCustomButton(frame,
        "|TInterface\\Icons\\INV_Misc_Coin_02:16:16:0:-1|t Personal Bank",
        function() ExtBank_Close() end,   -- Close restores the bank when the session is live
        170, 32)
    bankBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
    bankBtn:Hide()
end

local function GetBagButton(i)
    if not bagBtns[i] then
        local btn = CreateFrame("Button", "ExtBankBagSlot"..i, frame, "ItemButtonTemplate")
        btn:SetWidth(BAG_SIZE); btn:SetHeight(BAG_SIZE)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")   -- right-click = unequip
        btn:RegisterForDrag("LeftButton")
        btn.bagIndex = i - 1
        -- golden overlay marking the currently selected bag
        btn.sel = btn:CreateTexture(nil, "OVERLAY")
        btn.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        btn.sel:SetBlendMode("ADD")
        btn.sel:SetAllPoints(btn)
        btn.sel:Hide()
        -- gold ring marking a bag that holds a global-search hit
        btn.searchGlow = btn:CreateTexture(nil, "OVERLAY")
        btn.searchGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        btn.searchGlow:SetBlendMode("ADD")
        btn.searchGlow:SetVertexColor(1, 0.82, 0.2)
        btn.searchGlow:SetPoint("TOPLEFT", btn, "TOPLEFT", -9, 9)
        btn.searchGlow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 9, -9)
        btn.searchGlow:Hide()
        local function DropBagHere(self)
            -- Dropping a picked-up bag onto this slot: use the source we tracked
            -- via the PickupContainerItem hook. Server validates it's a container.
            if not CursorHasItem() then return false end
            if cursorSrc and cursorSrc.bag >= 0 and cursorSrc.bag <= 4 then
                EquipBagToSlot(cursorSrc.bag, cursorSrc.slot, self.bagIndex)
            elseif cursorSrc then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff5555ExtBank:|r bags can only be equipped from your inventory -- move it there first.")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff5555ExtBank:|r cursor holds an item but its source is unknown -- use Shift+right-click instead.")
            end
            ClearCursor(); cursorSrc = nil
            return true
        end
        btn:SetScript("OnClick", function(self, button)
            if self.locked then return end
            if DropBagHere(self) then return end
            if button == "RightButton" and bags[self.bagIndex] then UnequipBag(self.bagIndex)
            else activeBag = self.bagIndex; sideHidden = false; ExtBank_Redraw() end
        end)
        btn:SetScript("OnReceiveDrag", function(self)
            if self.locked then return end
            DropBagHere(self)
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.locked then
                GameTooltip:SetText("Locked bag slot")
                GameTooltip:AddLine("Use the Purchase button above to unlock more bag slots.", 0.6, 0.6, 0.6, true)
                GameTooltip:Show()
                return
            end
            local d = bags[self.bagIndex]
            if d then GameTooltip:SetHyperlink("item:"..d.itemId)
                     GameTooltip:AddLine("Right-click to unequip (must be empty)", 0.6,0.6,0.6)
            else GameTooltip:SetText("Empty bag slot\nDrag a bag here, or Shift+right-click a bag in your inventory") end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bagBtns[i] = btn
    end
    return bagBtns[i]
end

function ExtBank_Redraw()
    if not frame then return end

    -- --- bag-slot strip: wraps into rows of BAG_COLS, aligned to the grid ---
    local function place(idx0)      -- top-left of grid cell for flow index idx0
        local col, row = idx0 % BAG_COLS, math.floor(idx0 / BAG_COLS)
        return LEFT + col * COLW, -STRIP_TOP - row * COLW, row
    end

    for i = 1, MAX_BAGS do
        local btn = GetBagButton(i)
        local x, y = place(i - 1)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", x, y)
        local icon = _G[btn:GetName().."IconTexture"] or _G[btn:GetName().."Icon"]
        if i <= unlockedBags then
            btn.locked = false
            local d = bags[i-1]
            if icon then
                if d then icon:SetTexture(GetItemIcon(d.itemId) or "Interface/Icons/INV_Misc_QuestionMark")
                else icon:SetTexture("Interface/PaperDoll/UI-PaperDoll-Slot-Bag") end
                icon:SetDesaturated(false)
                icon:SetVertexColor(1, 1, 1)
                icon:SetAlpha(1)
                icon:Show()
            end
            btn:SetAlpha(1)
            if i - 1 == activeBag then btn.sel:Show() else btn.sel:Hide() end
            if searchText ~= "" and bagHasMatch[i - 1] then btn.searchGlow:Show()
            else btn.searchGlow:Hide() end
        else
            btn.locked = true
            if icon then
                icon:SetTexture("Interface/PaperDoll/UI-PaperDoll-Slot-Bag")
                icon:SetDesaturated(true)
                icon:SetVertexColor(0.3, 0.3, 0.3)
                icon:SetAlpha(0.6)
                icon:Show()
            end
            btn:SetAlpha(0.55)
            btn.sel:Hide()
            btn.searchGlow:Hide()
        end
        btn:Show()
    end

    -- strip always shows the full grid; unlock button is fixed above it, and the
    -- bottom reserves room for the "Personal Bank" button while we've swapped the
    -- native bank away (with Bagnon the bank stays on screen, so no button needed)
    local bagRows = math.ceil(MAX_BAGS / BAG_COLS)                    -- rows the strip occupies
    local showBankBtn = bankOpen and hidBankPanel
    if bankBtn then
        if showBankBtn then bankBtn:Show() else bankBtn:Hide() end
    end
    frame:SetHeight(STRIP_TOP + bagRows * COLW + 16 + (showBankBtn and 46 or 0))

    -- purchase button reflects the next slot's price (capped), or disables at 64
    if unlockBtn then
        if unlockedBags >= MAX_BAGS then
            unlockBtn:SetText("All bag slots unlocked")
            unlockBtn:Disable()
        else
            unlockBtn:SetText(("Purchase %s %s"):format(FormatGold(NextSlotCost()), GOLD_ICON))
            unlockBtn:Enable()
        end
    end

    -- hit counter beside the search box
    if searchStatus then
        if searchText == "" then searchStatus:SetText("")
        elseif #matches == 0 then searchStatus:SetText("|cffff5555none|r")
        else searchStatus:SetText(("|cffffd100%d / %d|r"):format(matchIndex, #matches)) end
    end

    -- --- side popup: the selected bag's contents, opening on the right ---
    local bag  = bags[activeBag]
    local size = bag and bag.size or 0
    if not bag or sideHidden then
        if searchMarker then searchMarker:Hide() end
        sideFrame:Hide()
        return
    end

    local page = cells[activeBag] or {}
    -- which slots of the OPEN bag are search hits, and which one is focused
    local isHit, focusSlot = {}, nil
    for i, m in ipairs(matches) do
        if m.bag == activeBag then
            isHit[m.slot] = true
            if i == matchIndex then focusSlot = m.slot end
        end
    end
    local cols = ColsFor(size)
    local rows = math.max(math.ceil(size / cols), 1)
    sideTitle:SetText((GetItemInfo(bag.itemId)) or ("Bag " .. (activeBag + 1)))
    sideFrame:SetWidth(LEFT * 2 + cols * COLW - PAD)
    sideFrame:SetHeight(SIDE_TOP + rows * COLW + 14)
    for idx = 0, 35 do
        local btn = contentBtns[idx + 1]
        if idx < size then
            local col, row = idx % cols, math.floor(idx / cols)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", LEFT + col * COLW, -SIDE_TOP - row * COLW)
            local d = page[idx]
            local icon = _G[btn:GetName().."IconTexture"]
            local cnt  = _G[btn:GetName().."Count"]
            if d then
                icon:SetTexture(GetItemIcon(d.itemId) or "Interface/Icons/INV_Misc_QuestionMark"); icon:Show()
                if d.count and d.count > 1 then cnt:SetText(d.count); cnt:Show() else cnt:Hide() end
                -- global search: ring the hits in this bag, dim everything else
                if searchText == "" or isHit[idx] then icon:SetVertexColor(1, 1, 1)
                else icon:SetVertexColor(0.3, 0.3, 0.3) end
                if searchText ~= "" and isHit[idx] then btn.searchGlow:Show()
                else btn.searchGlow:Hide() end
            else icon:Hide(); cnt:Hide(); btn.searchGlow:Hide() end
            btn:Show()
        else btn:Hide() end
    end

    -- park the pulsing marker on the focused hit
    if focusSlot ~= nil and focusSlot < size then
        searchMarker:ClearAllPoints()
        searchMarker:SetAllPoints(contentBtns[focusSlot + 1])
        searchMarker:Show()
    else
        searchMarker:Hide()
    end
    sideFrame:Show()
end

-- ------------------------------------------------------------- open / close ---
-- Bag addons (Bagnon) replace the native BankFrame with their own window, so
-- "the bank panel" is whichever of the two is actually shown.
local function BagnonBankPanel()
    local f = _G["BagnonFramebank"]
    if f and f:IsShown() then return f end
    return nil
end
local function VisibleBankPanel()
    if BankFrame and BankFrame:IsShown() then return BankFrame end
    return BagnonBankPanel()
end

-- Hide the native bank WITHOUT ending the banker session: BankFrame's OnHide
-- normally calls CloseBankFrame() (server closes the session and we'd get
-- BANKFRAME_CLOSED), so suspend the script around the hide. Only the native
-- frame can be swapped away like this -- hiding Bagnon's bank frame runs its
-- OnHide, which calls CloseBankFrame() unconditionally and kills the session,
-- so with Bagnon the ext bank docks BESIDE the bank window instead.
local function HideBankPanel()
    if not (BankFrame and BankFrame:IsShown()) then return end
    local onHide = BankFrame:GetScript("OnHide")
    BankFrame:SetScript("OnHide", nil)
    HideUIPanel(BankFrame)
    BankFrame:SetScript("OnHide", onHide)
    hidBankPanel = true
end
local function RestoreBankPanel()
    if hidBankPanel and bankOpen and BankFrame and not BankFrame:IsShown() then
        ShowUIPanel(BankFrame)
    end
    hidBankPanel = false
end

function ExtBank_Open()
    if not frame then BuildUI() end
    isOpen = true; sideHidden = false

    -- Open in place of the personal bank so the swap feels seamless. The bank
    -- sits at the left edge, so the bag popup must open to the RIGHT there
    -- (its default is to the left of the panel). With Bagnon the bank window
    -- can't be hidden (its OnHide ends the banker session), so dock the void
    -- storage to its right instead of replacing it.
    local atBank = false
    if bankOpen and BankFrame and BankFrame:IsShown() then
        local l, t = BankFrame:GetLeft(), BankFrame:GetTop()
        if l and t then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
            atBank = true
        end
    elseif bankOpen and BagnonBankPanel() then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", BagnonBankPanel(), "TOPRIGHT", 6, 0)
        atBank = true
    end
    sideFrame:ClearAllPoints()
    if atBank then
        sideFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
    else
        sideFrame:SetPoint("TOPRIGHT", frame, "TOPLEFT", -6, 0)
    end

    frame:Show()
    HideBankPanel()   -- swap: void storage replaces the native personal bank on screen
    if type(ExtBankOpen) == "function" then ExtBankOpen() end   -- request snapshot
    -- Turn on native-bank deposit suppression so right-clicks land in the ext
    -- bank. ExtBankOpen already covers this; kept explicit for clarity.
    if ExtBankSetActive then ExtBankSetActive(1) end
    ExtBank_Redraw()
end
function ExtBank_Close()
    isOpen = false; if frame then frame:Hide() end; ExtBank.pickSrc = nil
    StaticPopup_Hide("EXTBANK_UNLOCK_CONFIRM")
    RestoreBankPanel()   -- swap back to the personal bank if the session is live
    if searchBox then
        searchBox:SetText(""); searchBox:ClearFocus()
        if searchBox.debounce then searchBox.debounce:Hide() end
    end
    searchText, matches, bagHasMatch, matchIndex = "", {}, {}, 0
    if searchMarker then searchMarker:Hide() end
    -- Turn suppression back off so native-bank deposits work once you walk away.
    if ExtBankSetActive then ExtBankSetActive(0) end
end

ExtBank = { pickSrc = nil }

-- The extended bank stays hidden by default: opening the personal bank only
-- shows a toggle button pinned to the top of the bank window. It is parented
-- to that window so it appears/disappears with the bank itself. "The bank
-- window" is the native BankFrame OR a bag addon's replacement (Bagnon), and
-- the replacement may be created/shown AFTER our BANKFRAME_OPENED handler
-- runs, so we poll for a moment until one of the two is actually on screen.
local bankToggleBtn
local function AttachBankToggleButton(panel)
    if not bankToggleBtn then
        bankToggleBtn = utils.CreateSimpleCustomButton(panel,
            "|TInterface\\Icons\\INV_Enchant_VoidSphere:16:16:0:-1|t Void Storage",
            function() if isOpen then ExtBank_Close() else ExtBank_Open() end end,
            170, 32)
    end
    bankToggleBtn:SetParent(panel)
    bankToggleBtn:ClearAllPoints()
    bankToggleBtn:SetPoint("BOTTOM", panel, "TOP", 0, -12)
    bankToggleBtn:SetFrameStrata(panel:GetFrameStrata())
    bankToggleBtn:SetFrameLevel(panel:GetFrameLevel() + 10)
    bankToggleBtn:Show()
end

local ev = CreateFrame("Frame")
local toggleWait = nil   -- seconds spent looking for the bank window, nil = idle
ev:SetScript("OnUpdate", function(self, elapsed)
    if not toggleWait then return end
    toggleWait = toggleWait + elapsed
    local panel = VisibleBankPanel()
    if panel then
        AttachBankToggleButton(panel)
        toggleWait = nil
    elseif toggleWait > 2 then
        toggleWait = nil   -- no bank window ever showed; give up quietly
    end
end)
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("BANKFRAME_CLOSED")
ev:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        toggleWait = 0    -- find whichever bank window shows and pin the button to it
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false   -- clear FIRST so ExtBank_Close doesn't re-show the bank
        toggleWait = nil
        ExtBank_Close()
    end
end)

SLASH_EXTBANK1 = "/voidstorage"
SLASH_EXTBANK2 = "/extbank"
SlashCmdList["EXTBANK"] = function() if isOpen then ExtBank_Close() else ExtBank_Open() end end
