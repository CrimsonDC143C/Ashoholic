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
--
-- Warband bank: a second store, shared by every character of the account, with
-- its own gold. Same opcode, control srcBag values (no item moves):
--    0xF0 = pick the store (srcSlot 1 = Warband, 0 = Extended Bank)
--    0xF1 = deposit gold (count = copper),  0xF2 = withdraw gold (count = copper)
-- Every SMSG_EXTBANK_UPDATE ends with u8 store shown + u64 Warband gold + u8
-- Warband bank open (0 = still locked: ExtBankUnlock on the Warband tab opens it
-- for WARBAND_OPEN_COST gold, once per account).
--
-- The window shows every bag at once: the bag strip on top, then the contents
-- of all bags one after the other in a scroll list (only the visible rows own
-- buttons, so 200 bags cost the same as 2).

local HDR_BAG       = 19
local CONTENT_BASE  = 20
local AUTO_EXT      = 255      -- first free content slot (dstBag)
local AUTO_INV      = 254      -- first free inventory slot (dstBag)
local AUTO_BAGSLOT  = 255      -- first free bag slot (dstSlot when dstBag==19)
local CTRL_SET_STORE     = 240 -- srcBag: pick the store (ExtBank.cpp CTRL_*)
local CTRL_GOLD_DEPOSIT  = 241
local CTRL_GOLD_WITHDRAW = 242

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
local curStore     = 0     -- store shown, from the packet tail: 0 = Extended Bank, 1 = Warband bank
local warbandMoney = 0     -- copper in the Warband bank, from the packet tail
local warbandOpen  = false -- the account has unlocked its Warband bank, from the packet tail
local WARBAND_OPEN_COST = 1000   -- gold, once per account (ExtBank.cpp WARBAND_UNLOCK_COST_GOLD)
local UpdateWarbandTabs    -- padlock on the "Warband Bank" tabs, defined with the UI

-- global search state; the box itself lives in the UI section further down
local searchText  = ""     -- lowercased needle, "" while no search is running
local matches     = {}     -- ordered { bag=, slot= } hits across EVERY bag
local matchIndex  = 0      -- which hit is focused (Enter walks through them)
local bagHasMatch = {}     -- [bagIndex] = true when that bag holds a hit
local RebuildMatches       -- defined with the UI, called from the packet handler
local OnStoreChanged       -- same: the window switched between Extended and Warband bank

-- sort run state (see the sort section)
local sorter = { running = false, queue = {}, qi = 1, pending = 0, t = 0, wait = 0, hold = 0, rounds = 0 }

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
    elseif sorter.pending > 0 then
        sorter.pending = sorter.pending - 1   -- every sort swap is answered by one delta
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
    -- tail: u8 store shown, u64 Warband gold (absent from a server without the Warband bank)
    local store = 0
    if p <= n then
        store, p = u8(b, p)
        if p + 7 <= n then
            local lo, hi
            lo, p = u32(b, p)
            hi, p = u32(b, p)
            warbandMoney = lo + hi * 4294967296
        end
        if p <= n then
            local open
            open, p = u8(b, p)
            warbandOpen = (open == 1)
        end
    end
    if UpdateWarbandTabs then UpdateWarbandTabs() end
    if store ~= curStore then
        curStore = store
        if OnStoreChanged then OnStoreChanged() end
    end
    if activeBag >= unlockedBags then activeBag = math.max(0, unlockedBags - 1) end
    if isOpen then
        if RebuildMatches then RebuildMatches() end   -- contents changed: re-run the search
        ExtBank_Redraw()
    end
end

-- --------------------------------------------------------------- operations ---
-- Blizzard-style error: red text at the top of the screen, like "Your bags are full."
local function UIError(msg)
    UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1, 1.0)
end

local function CanSend()
    if type(ExtBankMove) ~= "function" then
        UIError("The Extended Bank is not available right now.")
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
local function SelectStore(store)          if CanSend() then ExtBankMove(CTRL_SET_STORE, store, 0, 0, 0) end end
local function MoveGold(deposit, copper)
    copper = math.min(math.floor(tonumber(copper) or 0), 2147483647)   -- a character holds at most that
    if copper <= 0 or not CanSend() then return end
    ExtBankMove(deposit and CTRL_GOLD_DEPOSIT or CTRL_GOLD_WITHDRAW, 0, 0, 0, copper)
end
local function Unlock()
    if type(ExtBankUnlock) == "function" then
        ExtBankUnlock()
    else
        UIError("The Extended Bank is not available right now.")
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
-- first empty slot in the currently selected (active) ext bag, or nil if none/full
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
        -- Deposit into the currently SELECTED bag first; only fall back to
        -- "first free slot anywhere" if that bag is full or none is selected.
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
-- The window wears the personal bank's own chrome (UI-BankFrame: portrait ring,
-- title bar, stone, bottom bar), stretched to fit: the contents of every bag in a
-- scroll list on top, the bag slots below it like the bank's, then Cost / Purchase.
local COLS, CELL, PAD = 10, 37, 4
local COLW        = CELL + PAD        -- 41: horizontal/vertical pitch of the grid
local GRID_W      = COLS * COLW - PAD
local FRAME_W     = 480
local VIEW_LEFT   = 26               -- the list's left edge, inside the bank's stone border
local VIEW_TOP    = 78               -- below the search row
local BAG_PITCH   = 49               -- the bank's own bag-slot pitch
local BAG_COLS    = 8                -- bag slots per row
local PAGE_COLS   = 7                -- when the bag slots page: 2 rows of 7, arrows in the 8th column
local SECT_H      = 20               -- bag name line above each bag's grid
local SECT_GAP    = 8
local VIEW_MIN    = 3 * COLW
local VIEW_MAX    = 8 * COLW
local MAX_BAGS    = 200              -- same cap as the server (ExtBank.cpp MAX_BAGSLOTS)

local BANK_TEX  = "Interface\\BankFrame\\UI-BankFrame"
local HOLE_TC   = { 37/512, 81/512, 71/512, 113/512 }   -- one empty slot of the bank, frame included
local VOID_ICON = "Interface\\Icons\\INV_Enchant_VoidSphere"
local WARBAND_ICON = "Interface\\Icons\\INV_Misc_Bag_10_Blue"
local GOLD_ROW_H   = 26              -- the Warband gold line under Cost / Purchase
-- UI-BankFrame (512x512) cut for stretching: the portrait corner, the close-button
-- corner and the bottom bar keep their size; the plain stone between the bank's
-- bag row and its bottom bar fills the middle.
local CHROME_COLS = { { 0, 80 }, { 80, 330 }, { 330, 399 } }
local CHROME_ROWS = { { 0, 68 }, { 320, 388 }, { 388, 424 } }

-- cost (in gold) of each successive bag slot; capped at the last entry
-- (same table as ExtBank.cpp UNLOCK_COST_GOLD)
local SLOT_COSTS = { 50, 125, 250, 500, 1250, 2500, 5000, 10000 }
local GOLD_ICON  = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t"
local function NextSlotCost()
    return SLOT_COSTS[math.min(unlockedBags + 1, #SLOT_COSTS)]
end
local function FormatGold(n)
    local s = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (s:gsub("^,", ""))
end
local function MoneyString(copper)
    local g = math.floor(copper / 10000)
    local sv = math.floor(copper / 100) % 100
    local c = copper % 100
    return ("%s %s  %d |TInterface\\MoneyFrame\\UI-SilverIcon:14:14:2:0|t  %d |TInterface\\MoneyFrame\\UI-CopperIcon:14:14:2:0|t")
        :format(FormatGold(g), GOLD_ICON, sv, c)
end

-- Gold in / out of the Warband bank, typed in the stock money input (as the guild bank's).
local function PopupCopper(dialog)
    local m = dialog.moneyInputFrame or _G[dialog:GetName() .. "MoneyInputFrame"]
    return m and MoneyInputFrame_GetCopper(m) or 0
end
local function WarbandGoldPopup(deposit)
    return {
        text = deposit and "Deposit how much gold into the Warband bank?" or "Withdraw how much gold from the Warband bank?",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasMoneyInputFrame = 1,
        OnAccept = function(self) MoveGold(deposit, PopupCopper(self)) end,
        EditBoxOnEnterPressed = function(self)
            local dialog = self:GetParent():GetParent()
            MoveGold(deposit, PopupCopper(dialog))
            dialog:Hide()
        end,
        OnHide = function(self)
            local m = self.moneyInputFrame or _G[self:GetName() .. "MoneyInputFrame"]
            if m then MoneyInputFrame_ResetMoney(m) end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end
StaticPopupDialogs["EXTBANK_WARBAND_DEPOSIT"]  = WarbandGoldPopup(true)
StaticPopupDialogs["EXTBANK_WARBAND_WITHDRAW"] = WarbandGoldPopup(false)

-- confirmation before actually sending CMSG_EXTBANK_UNLOCK
StaticPopupDialogs["EXTBANK_WARBAND_OPEN_CONFIRM"] = {
    text = "Unlock the Warband Bank for %s?\n\nEvery character of your account will share its bags and gold.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() Unlock() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}
StaticPopupDialogs["EXTBANK_UNLOCK_CONFIRM"] = {
    text = "Unlock bag slot %s for %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() Unlock() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}
local frame, view, child, scrollBar, sortBtn, purchaseBtn, searchBox
local titleText, portraitTex       -- "Extended Bank" / "Warband Bank" and its portrait
local goldText, depositBtn, withdrawBtn   -- the Warband gold line
local searchStatus, searchMarker   -- "3 / 12" hit counter + the pulse on the focused hit
local usageText, costText, footText, hintText, emptyText, pageUp, pageDown
local frameTabs, bankTabs          -- "Bank" / "Extended Bank" tabs under our window and under the bank's
local chromeTex  = {}              -- the stretched bank chrome pieces
local stripBtns  = {}              -- bag-slot buttons, reused across pages
local cellPool   = {}              -- content cells, only for the rows on screen
local hdrPool    = {}              -- bag name lines, same
local lines      = {}              -- layout of the scroll list: { hdr=, bag=, row=, y= }
local sectionTop = {}              -- [bag] = y of that bag's name line in the list
local contentH   = 0
local stripPage  = 0
local hitKey, focusKey = {}, nil   -- search hits by bag*256+slot, and the focused one
local ExtBank_ScrollToBag, ExtBank_ScrollToCell

-- ------------------------------------------------------------ global search ---
-- The box looks through EVERY unlocked bag: bags holding a hit get a gold ring
-- in the strip, hits stay lit while the rest dims, the list scrolls to the first
-- hit, and Enter walks through the remaining ones.

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

-- Select the bag holding hit #i and scroll it into view (wraps around both ways).
local function FocusMatch(i)
    if #matches == 0 then ExtBank_Redraw(); return end
    if i < 1 then i = #matches elseif i > #matches then i = 1 end
    matchIndex = i
    activeBag  = matches[i].bag
    stripPage  = math.floor(activeBag / (PAGE_COLS * 2))
    ExtBank_Redraw()
    ExtBank_ScrollToCell(matches[i].bag, matches[i].slot)
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

-- -------------------------------------------------------------------- sort ----
-- The server has no sort command, but a content move onto an occupied slot is a
-- swap. So the sort is planned here as a list of swaps, sent at 40 per second
-- (the server kicks past 100 packets of one opcode per second), and re-planned
-- from the real contents once the server has answered, until nothing moves.
-- Regular bags are sorted as one long list; a special bag (herb, enchanting...)
-- is sorted on its own, since the server refuses to swap across bag families.
-- Stacks are reordered, never merged.
local TYPE_ORDER = { Weapon = 1, Armor = 2, Gem = 3, Glyph = 4, Consumable = 5, Recipe = 6,
    ["Trade Goods"] = 7, Container = 8, Quiver = 9, Projectile = 10, Key = 11, Quest = 12, Miscellaneous = 13 }

local function SortKey(d)
    local name, _, quality, ilvl, _, itype, isub = GetItemInfo(d.itemId)
    if not name then ItemName(d.itemId) end   -- ask the server; the next round sorts it properly
    return { TYPE_ORDER[itype or ""] or (name and 14 or 99), isub or "", -(quality or 0), -(ilvl or 0),
             name or "", d.itemId, -(d.count or 1), d.lowGuid or 0 }
end
local function KeyLess(a, b)
    for i = 1, #a do
        if a[i] ~= b[i] then return a[i] < b[i] end
    end
    return false
end

-- Slot lists to sort, regular bags first as one group; nil while a bag's item
-- info is not cached yet (we can't tell a regular bag from a special one).
local function SortGroups()
    local groups, regular = {}, {}
    for b = 0, unlockedBags - 1 do
        local bag = bags[b]
        if bag then
            local sub = select(7, GetItemInfo(bag.itemId))
            if not sub then ItemName(bag.itemId); return nil end
            local g = regular
            if sub ~= "Bag" then g = {}; groups[#groups + 1] = g end
            for s = 0, (bag.size or 0) - 1 do g[#g + 1] = { bag = b, slot = s } end
        end
    end
    if #regular > 0 then table.insert(groups, 1, regular) end
    return groups
end

-- Swaps that turn the current contents into the sorted order, applied to a
-- copy as they are planned so each one is valid after the ones before it.
local function PlanSort()
    local groups = SortGroups()
    if not groups then return nil end
    local sim, moves = {}, {}
    for b, page in pairs(cells) do
        for s, d in pairs(page) do sim[b * 256 + s] = d end
    end
    for _, g in ipairs(groups) do
        local items, where = {}, {}
        for _, pos in ipairs(g) do
            local d = sim[pos.bag * 256 + pos.slot]
            if d then items[#items + 1] = { d = d, key = SortKey(d) }; where[d] = pos end
        end
        table.sort(items, function(x, y) return KeyLess(x.key, y.key) end)
        for i, it in ipairs(items) do
            local dst, src = g[i], where[it.d]
            if src ~= dst then
                local other = sim[dst.bag * 256 + dst.slot]
                moves[#moves + 1] = { src.bag, src.slot, dst.bag, dst.slot }
                sim[dst.bag * 256 + dst.slot], sim[src.bag * 256 + src.slot] = it.d, other
                where[it.d] = dst
                if other then where[other] = src end
            end
        end
    end
    return moves
end

local sortFrame = CreateFrame("Frame")
sortFrame:Hide()

local function StopSort(msg)
    sorter.running, sorter.queue, sorter.qi, sorter.pending = false, {}, 1, 0
    sortFrame:Hide()
    if msg then UIError(msg) end
    if isOpen then ExtBank_Redraw() end
end

local function NextRound()
    sorter.rounds = sorter.rounds + 1
    if sorter.rounds > 8 then
        StopSort("Some items could not be sorted.")
        return
    end
    local moves = PlanSort()
    if not moves then                      -- bag info still loading: look again shortly
        sorter.queue, sorter.qi, sorter.hold = {}, 1, 0.5
        return
    end
    if #moves == 0 then StopSort(); return end
    sorter.queue, sorter.qi, sorter.t, sorter.wait = moves, 1, 0, 0
end

sortFrame:SetScript("OnUpdate", function(self, elapsed)
    if sorter.hold > 0 then sorter.hold = sorter.hold - elapsed; return end
    if sorter.qi <= #sorter.queue then
        sorter.t = sorter.t + elapsed
        if sorter.t < 0.1 then return end
        sorter.t = 0
        for _ = 1, 4 do
            local m = sorter.queue[sorter.qi]
            if not m then break end
            sorter.pending = sorter.pending + 1
            sorter.qi = sorter.qi + 1
            MoveContent(m[1], m[2], m[3], m[4])
        end
        sorter.wait = 0
    else
        -- everything sent: wait for the server's answers, then check again from
        -- the real contents (a refused swap sends no answer, hence the timeout)
        sorter.wait = sorter.wait + elapsed
        if sorter.pending <= 0 or sorter.wait > 2 then
            sorter.pending, sorter.wait = 0, 0
            NextRound()
        end
    end
end)

local function StartSort()
    if sorter.running or not CanSend() then return end
    ExtBank.pickSrc = nil
    sorter.running, sorter.rounds, sorter.pending, sorter.hold = true, 0, 0, 0
    NextRound()
    if sorter.running then sortFrame:Show() end
    ExtBank_Redraw()
end

-- --------------------------------------------------------------- UI build ----
-- The bank's empty slot (black hole in its metal frame) behind the button; the
-- template's quickslot border is dropped.
local function StyleBankSlot(btn)
    local nt = btn:GetNormalTexture()
    if nt then nt:SetTexture(nil) end
    btn.slotBg = btn:CreateTexture(nil, "BACKGROUND")
    btn.slotBg:SetTexture(BANK_TEX)
    btn.slotBg:SetTexCoord(unpack(HOLE_TC))
    btn.slotBg:SetWidth(44); btn.slotBg:SetHeight(42)
    btn.slotBg:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local icon = _G[btn:GetName() .. "IconTexture"]
    if icon then icon:SetAllPoints(btn) end
    return icon
end

local function NewOverlay(btn, texture, inset, r, g, b)
    local t = btn:CreateTexture(nil, "OVERLAY")
    t:SetTexture(texture)
    t:SetBlendMode("ADD")
    if r then t:SetVertexColor(r, g, b) end
    t:SetPoint("TOPLEFT", btn, "TOPLEFT", -inset, inset)
    t:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", inset, -inset)
    t:Hide()
    return t
end

-- One content cell of the scroll list. Which (bag, slot) it shows is set by the
-- layout pass: self.bag / self.slot.
local function NewCell(c)
    local btn = CreateFrame("Button", "ExtBankCell"..c, child, "ContainerFrameItemButtonTemplate")
    btn:SetWidth(CELL); btn:SetHeight(CELL)
    btn.icon = StyleBankSlot(btn)
    btn.count = _G[btn:GetName().."Count"]
    btn.quality = NewOverlay(btn, "Interface\\Buttons\\UI-ActionButton-Border", 10)
    btn.hit     = NewOverlay(btn, "Interface\\Buttons\\CheckButtonHilight", 0, 1, 0.85, 0.3)
    btn.picked  = NewOverlay(btn, "Interface\\Buttons\\CheckButtonHilight", 0, 0.75, 0.5, 1)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")   -- right-click = withdraw
    btn:RegisterForDrag("LeftButton")
    -- Drop whatever is being carried onto this cell:
    --  * a real inventory item on the cursor  -> DEPOSIT into this slot
    --  * an ext-internal virtual pick (pickSrc) -> MOVE within the bank
    local function DropIntoCell(self)
        if not bags[self.bag] then return false end   -- no bag equipped here
        if CursorHasItem() then
            if cursorSrc and cursorSrc.bag >= 0 and cursorSrc.bag <= 4 then
                DepositToSlot(cursorSrc.bag, cursorSrc.slot, self.bag, self.slot)
            elseif cursorSrc then
                UIError("You can only store items from your bags.")
            else
                UIError("Right-click an item in your bags to store it.")
            end
            ClearCursor(); cursorSrc = nil
            return true
        elseif ExtBank.pickSrc then
            local src = ExtBank.pickSrc
            ExtBank.pickSrc = nil
            if src.bag ~= self.bag or src.slot ~= self.slot then   -- same cell = cancel the pick
                MoveContent(src.bag, src.slot, self.bag, self.slot)
            end
            ExtBank_Redraw()
            return true
        end
        return false
    end
    btn:SetScript("OnClick", function(self, button)
        if sorter.running then return end
        if DropIntoCell(self) then return end
        local d = cells[self.bag] and cells[self.bag][self.slot]
        if not d then return end
        if button == "RightButton" or IsShiftKeyDown() then WithdrawContent(self.bag, self.slot)
        else ExtBank.pickSrc = { bag = self.bag, slot = self.slot }; ExtBank_Redraw() end
    end)
    btn:SetScript("OnDragStart", function(self)
        if sorter.running then return end
        local d = cells[self.bag] and cells[self.bag][self.slot]
        if d then ExtBank.pickSrc = { bag = self.bag, slot = self.slot }; ExtBank_Redraw() end
    end)
    btn:SetScript("OnReceiveDrag", function(self) if not sorter.running then DropIntoCell(self) end end)
    -- Own tooltip: the default ContainerFrameItemButton_OnEnter reads a real
    -- bag slot, which these virtual cells aren't -- so drive it from our data.
    btn:SetScript("OnUpdate", nil)
    -- The template's OnLoad also set btn.UpdateTooltip; GameTooltip_OnUpdate
    -- re-invokes it every 0.2s while the tooltip is shown, which would rewrite
    -- our tooltip from SetBagItem(0,0) (same wrong tooltip on every cell).
    btn.UpdateTooltip = nil
    btn:SetScript("OnEnter", function(self)
        local d = cells[self.bag] and cells[self.bag][self.slot]
        if not d then GameTooltip:Hide(); return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- full link so enchant / random suffix show, not just the base item
        GameTooltip:SetHyperlink(("item:%d:%d:0:0:0:0:%d"):format(
            d.itemId, d.enchant or 0, d.randomProp or 0))
        if d.count and d.count > 1 then GameTooltip:AddLine("Stack: " .. d.count, 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

local function NewHeader()
    local h = {}
    h.name = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.name:SetJustifyH("LEFT")
    h.count = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.count:SetJustifyH("RIGHT")
    return h
end

local function GetStripButton(i)
    if not stripBtns[i] then
        local btn = CreateFrame("Button", "ExtBankBagSlot"..i, frame, "ItemButtonTemplate")
        btn:SetWidth(CELL); btn:SetHeight(CELL)
        btn.icon = StyleBankSlot(btn)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")   -- right-click = unequip
        btn:RegisterForDrag("LeftButton")
        -- golden overlay marking the currently selected bag
        btn.sel = NewOverlay(btn, "Interface\\Buttons\\CheckButtonHilight", 0)
        -- gold ring marking a bag that holds a global-search hit
        btn.searchGlow = NewOverlay(btn, "Interface\\Buttons\\UI-ActionButton-Border", 10, 1, 0.82, 0.2)
        local function DropBagHere(self)
            -- Dropping a picked-up bag onto this slot: use the source we tracked
            -- via the PickupContainerItem hook. Server validates it's a container.
            if not CursorHasItem() then return false end
            if cursorSrc and cursorSrc.bag >= 0 and cursorSrc.bag <= 4 then
                EquipBagToSlot(cursorSrc.bag, cursorSrc.slot, self.bagIndex)
            elseif cursorSrc then
                UIError("You can only place a bag here from your inventory.")
            else
                UIError("Shift-right-click a bag in your inventory to place it here.")
            end
            ClearCursor(); cursorSrc = nil
            return true
        end
        btn:SetScript("OnClick", function(self, button)
            if DropBagHere(self) then return end
            if button == "RightButton" and bags[self.bagIndex] then UnequipBag(self.bagIndex)
            else
                activeBag = self.bagIndex
                ExtBank_Redraw()
                ExtBank_ScrollToBag(self.bagIndex)
            end
        end)
        btn:SetScript("OnReceiveDrag", function(self) DropBagHere(self) end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local d = bags[self.bagIndex]
            if d then GameTooltip:SetHyperlink("item:"..d.itemId)
                     GameTooltip:AddLine("Click to show it in the list", 0.6,0.6,0.6)
                     GameTooltip:AddLine("Right-click to unequip (must be empty)", 0.6,0.6,0.6)
            else GameTooltip:SetText("Empty bag slot\nDrag a bag here, or Shift+right-click a bag in your inventory") end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        stripBtns[i] = btn
    end
    return stripBtns[i]
end

local function NewArrow(dir, onClick)
    local b = CreateFrame("Button", nil, frame)
    b:SetWidth(24); b:SetHeight(24)
    local base = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. dir .. "Button-"
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    b:SetDisabledTexture(base .. "Disabled")
    b:SetHighlightTexture(base .. "Highlight", "ADD")
    b:SetScript("OnClick", onClick)
    return b
end

-- Lay the bank chrome over w x h. The middle column and row are filled with
-- copies of the source piece, every other copy mirrored so the seams match.
local function LayoutChrome(w, h)
    local wl, wr = CHROME_COLS[1][2] - CHROME_COLS[1][1], CHROME_COLS[3][2] - CHROME_COLS[3][1]
    local ht, hb = CHROME_ROWS[1][2] - CHROME_ROWS[1][1], CHROME_ROWS[3][2] - CHROME_ROWS[3][1]
    local xs = { { 0, wl }, { wl, w - wr }, { w - wr, w } }
    local ys = { { 0, ht }, { ht, h - hb }, { h - hb, h } }
    local n = 0
    for ri, rs in ipairs(CHROME_ROWS) do
        local sh, y, j = rs[2] - rs[1], ys[ri][1], 0
        while y < ys[ri][2] do
            local th = math.min(sh, ys[ri][2] - y)
            local top, bottom = rs[1], rs[1] + th
            if j % 2 == 1 then top, bottom = rs[2], rs[2] - th end
            for ci, cs in ipairs(CHROME_COLS) do
                local sw, x, i = cs[2] - cs[1], xs[ci][1], 0
                while x < xs[ci][2] do
                    local tw = math.min(sw, xs[ci][2] - x)
                    local left, right = cs[1], cs[1] + tw
                    if i % 2 == 1 then left, right = cs[2], cs[2] - tw end
                    n = n + 1
                    local t = chromeTex[n]
                    if not t then
                        t = frame:CreateTexture(nil, "BORDER")
                        t:SetTexture(BANK_TEX)
                        chromeTex[n] = t
                    end
                    t:SetTexCoord(left / 512, right / 512, top / 512, bottom / 512)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
                    t:SetWidth(tw); t:SetHeight(th)
                    t:Show()
                    x, i = x + tw, i + 1
                end
            end
            y, j = y + th, j + 1
        end
    end
    for k = n + 1, #chromeTex do chromeTex[k]:Hide() end
end

-- "Bank" / "Extended Bank" / "Warband Bank" tabs, Blizzard look without
-- PanelTemplates_SelectTab (same as the Call Board's tabs).
local function SetTabSelected(t, selected)
    local n = t:GetName()
    for _, part in ipairs({ "Left", "Middle", "Right" }) do
        if selected then
            _G[n .. part]:Hide(); _G[n .. part .. "Disabled"]:Show()
        else
            _G[n .. part]:Show(); _G[n .. part .. "Disabled"]:Hide()
        end
    end
    t:SetNormalFontObject(selected and GameFontHighlightSmall or GameFontNormalSmall)
end
local function ResizeTab(t)
    local n = t:GetName()
    local w = math.max(40, _G[n .. "Text"]:GetStringWidth() + 20)
    _G[n .. "Middle"]:SetWidth(w)
    _G[n .. "MiddleDisabled"]:SetWidth(w)
    t:SetWidth(w + 40)
end
-- "Warband Bank" carries a padlock until the account has unlocked it.
local LOCK_ICON = "|TInterface\\LFGFrame\\UI-LFG-ICON-LOCK:14:14:0:0|t "
UpdateWarbandTabs = function()
    for _, tabs in ipairs({ frameTabs or {}, bankTabs or {} }) do
        local t = tabs[3]
        if t then
            t:SetText((warbandOpen and "" or LOCK_ICON) .. "Warband Bank")
            ResizeTab(t)
        end
    end
end

-- tab 1 = the native bank, 2 = Extended Bank (store 0), 3 = Warband Bank (store 1)
local function CreateBankTabs(parent, prefix, selected)
    local tabs = {}
    for i, label in ipairs({ "Bank", "Extended Bank", "Warband Bank" }) do
        local t = CreateFrame("Button", prefix .. i, parent, "CharacterFrameTabButtonTemplate")
        t:SetHeight(32)
        t:SetText(label)
        if i > 1 then t:SetPoint("LEFT", tabs[i - 1], "RIGHT", -16, 0) end
        -- the template's OnShow / OnEvent resize through CharacterFrame helpers: ours instead
        t:SetScript("OnShow", ResizeTab)
        t:SetScript("OnEvent", ResizeTab)
        t:SetScript("OnClick", function()
            PlaySound("igCharacterInfoTab")
            if i == 1 then
                if isOpen then ExtBank_Close() end
            else
                ExtBank_Open(i - 2)
                -- a locked Warband Bank: offer to pay for it at once (the store is picked above)
                if i == 3 and not warbandOpen then
                    StaticPopup_Show("EXTBANK_WARBAND_OPEN_CONFIRM", FormatGold(WARBAND_OPEN_COST) .. " " .. GOLD_ICON)
                end
            end
        end)
        if i == 3 then
            t:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Warband Bank")
                GameTooltip:AddLine("Bags and gold shared by every character of your account.", 1, 1, 1, true)
                GameTooltip:AddLine("Only items you could mail to an alt can be stored: no soulbound, conjured or temporary items.", 0.8, 0.8, 0.8, true)
                if warbandOpen then
                    GameTooltip:AddLine("Bag slots are bought with gold, or all at once with a Warband Bank Voucher.", 0.8, 0.8, 0.8, true)
                else
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Locked", 1, 0.3, 0.3)
                    GameTooltip:AddLine(("Click to unlock it for your account for %s %s."):format(FormatGold(WARBAND_OPEN_COST), GOLD_ICON), 1, 0.82, 0, true)
                end
                GameTooltip:Show()
            end)
            t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        SetTabSelected(t, i == selected)
        ResizeTab(t)
        tabs[i] = t
    end
    return tabs
end

local function BuildUI()
    frame = CreateFrame("Frame", "ExtBankFrame", UIParent)
    frame:SetWidth(FRAME_W)
    frame:SetHeight(520)
    frame:SetPoint("TOP", UIParent, "TOP", 220, -60)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    -- Escape closes it like any Blizzard window: UISpecialFrames hides it, OnHide
    -- does the rest. IsShown tells a real Hide() from the UI being hidden (Alt+Z).
    tinsert(UISpecialFrames, "ExtBankFrame")
    frame:SetScript("OnHide", function(self)
        if isOpen and not self:IsShown() then ExtBank_Close(true) end
    end)

    -- portrait under the chrome: the ring of the bank frame is a hole
    portraitTex = frame:CreateTexture(nil, "BACKGROUND")
    portraitTex:SetWidth(60); portraitTex:SetHeight(60)
    portraitTex:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
    SetPortraitToTexture(portraitTex, curStore == 1 and WARBAND_ICON or VOID_ICON)
    LayoutChrome(FRAME_W, 520)

    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", frame, "TOP", 22, -17)   -- centred on the title bar, right of the portrait
    titleText:SetText(curStore == 1 and "Warband Bank" or "Extended Bank")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, -7)   -- on the bank's close-button corner
    close:SetScript("OnClick", function() ExtBank_Close() end)

    -- Search row: box, hit counter, Sort, space used.
    -- Same search component the Echo Journal and Skill Tree use (magnifier
    -- icon, native placeholder, clear button all built in).
    searchBox = CreateFrame("EditBox", "ExtBankSearchBox", frame, "ezCollectionsSearchBoxTemplate")
    searchBox:SetWidth(170)
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -44)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    searchBox.Instructions:SetText("Search")
    searchStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchStatus:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    searchStatus:SetText("")

    sortBtn = CreateFrame("Button", "ExtBankSortButton", frame, "UIPanelButtonTemplate")
    sortBtn:SetWidth(72); sortBtn:SetHeight(22)
    sortBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 300, -43)
    sortBtn:SetText("Sort")
    sortBtn:SetScript("OnClick", function() StartSort() end)
    sortBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sort")
        GameTooltip:AddLine("Orders the items of every bag by type, quality and name. Stacks are not merged.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    usageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    usageText:SetPoint("LEFT", sortBtn, "RIGHT", 10, 0)
    usageText:SetJustifyH("LEFT")

    -- Debounce: scanning every bag on each keystroke both costs work and makes
    -- the list jump mid-word, so run the search 0.2s after the last change.
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
    -- Enter walks to the next hit, Shift+Enter back one; both scroll as
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

    -- the contents of every bag, one after the other
    view = CreateFrame("ScrollFrame", "ExtBankScrollFrame", frame, "UIPanelScrollFrameTemplate")
    view.scrollBarHideable = 1
    child = CreateFrame("Frame", nil, view)
    child:SetWidth(GRID_W); child:SetHeight(1)
    view:SetScrollChild(child)
    scrollBar = _G["ExtBankScrollFrameScrollBar"]
    -- one wheel notch = two rows
    view:SetScript("OnMouseWheel", function(self, delta)
        scrollBar:SetValue(scrollBar:GetValue() - delta * 2 * COLW)
    end)
    local function OnScroll() ExtBank_LayoutVisible() end
    view:HookScript("OnVerticalScroll", OnScroll)
    scrollBar:HookScript("OnValueChanged", OnScroll)

    emptyText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyText:SetPoint("TOPLEFT", view, "TOPLEFT", 10, -20)
    emptyText:SetPoint("TOPRIGHT", view, "TOPRIGHT", -10, -20)

    -- Pulsing marker parked on the focused hit, above the cell it marks.
    searchMarker = CreateFrame("Frame", nil, child)
    searchMarker:SetFrameLevel(child:GetFrameLevel() + 10)
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

    -- bag-slot page arrows, shown only when the slots fill more than two rows
    pageUp = NewArrow("Up", function() stripPage = stripPage - 1; ExtBank_Redraw() end)
    pageDown = NewArrow("Down", function() stripPage = stripPage + 1; ExtBank_Redraw() end)

    -- Cost / Purchase under the bag slots, as on the bank
    costText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    costText:SetJustifyH("LEFT")
    purchaseBtn = CreateFrame("Button", "ExtBankPurchaseButton", frame, "UIPanelButtonTemplate")
    purchaseBtn:SetWidth(96); purchaseBtn:SetHeight(22)
    purchaseBtn:SetText("Purchase")
    purchaseBtn:SetScript("OnClick", function()
        if curStore == 1 and not warbandOpen then
            StaticPopup_Show("EXTBANK_WARBAND_OPEN_CONFIRM", FormatGold(WARBAND_OPEN_COST) .. " " .. GOLD_ICON)
            return
        end
        if unlockedBags >= MAX_BAGS then return end
        StaticPopup_Show("EXTBANK_UNLOCK_CONFIRM",
            tostring(unlockedBags + 1),
            FormatGold(NextSlotCost()) .. " " .. GOLD_ICON)
    end)

    -- bottom bar: bag-slot count (and page) left, the deposit hint right
    footText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footText:SetJustifyH("LEFT")
    hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintText:SetJustifyH("RIGHT")

    -- Warband gold under Cost / Purchase, Warband tab only
    goldText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    goldText:SetJustifyH("LEFT")
    withdrawBtn = CreateFrame("Button", "ExtBankWarbandWithdrawButton", frame, "UIPanelButtonTemplate")
    withdrawBtn:SetWidth(80); withdrawBtn:SetHeight(22)
    withdrawBtn:SetText("Withdraw")
    withdrawBtn:SetScript("OnClick", function() StaticPopup_Show("EXTBANK_WARBAND_WITHDRAW") end)
    depositBtn = CreateFrame("Button", "ExtBankWarbandDepositButton", frame, "UIPanelButtonTemplate")
    depositBtn:SetWidth(80); depositBtn:SetHeight(22)
    depositBtn:SetText("Deposit")
    depositBtn:SetPoint("RIGHT", withdrawBtn, "LEFT", -4, 0)
    depositBtn:SetScript("OnClick", function() StaticPopup_Show("EXTBANK_WARBAND_DEPOSIT") end)

    -- Bank / Extended Bank / Warband Bank tabs under the window, shown while a banker session is live
    frameTabs = CreateBankTabs(frame, "ExtBankFrameTab", curStore + 2)
    frameTabs[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 6)
    UpdateWarbandTabs()
end

-- The packet says the window now shows the other store: start it clean.
OnStoreChanged = function()
    activeBag, stripPage = 0, 0
    ExtBank.pickSrc = nil
    if sorter.running then StopSort() end
    if searchBox then
        searchBox:SetText(""); searchBox:ClearFocus()
        if searchBox.debounce then searchBox.debounce:Hide() end
    end
    searchText, matches, bagHasMatch, matchIndex = "", {}, {}, 0
    if searchMarker then searchMarker:Hide() end
    if titleText then titleText:SetText(curStore == 1 and "Warband Bank" or "Extended Bank") end
    if portraitTex then SetPortraitToTexture(portraitTex, curStore == 1 and WARBAND_ICON or VOID_ICON) end
    if curStore ~= 1 then
        StaticPopup_Hide("EXTBANK_WARBAND_DEPOSIT")
        StaticPopup_Hide("EXTBANK_WARBAND_WITHDRAW")
    end
end

-- ------------------------------------------------------------- list layout ---
-- Rebuild the line list: per equipped bag, its name line then its rows of cells.
local function BuildLines()
    for k in pairs(lines) do lines[k] = nil end
    for k in pairs(sectionTop) do sectionTop[k] = nil end
    local y = 0
    for b = 0, unlockedBags - 1 do
        local bag = bags[b]
        if bag then
            sectionTop[b] = y
            lines[#lines + 1] = { hdr = true, bag = b, y = y }
            y = y + SECT_H
            for r = 0, math.max(1, math.ceil((bag.size or 0) / COLS)) - 1 do
                lines[#lines + 1] = { bag = b, row = r, y = y }
                y = y + COLW
            end
            y = y + SECT_GAP
        end
    end
    contentH = math.max(y - SECT_GAP, 1)
end

local function PaintCell(btn, b, s)
    btn.bag, btn.slot = b, s
    local d = cells[b] and cells[b][s]
    local key = b * 256 + s
    btn.hit:Hide(); btn.quality:Hide()
    if d then
        btn.icon:SetTexture(GetItemIcon(d.itemId) or "Interface/Icons/INV_Misc_QuestionMark"); btn.icon:Show()
        if d.count and d.count > 1 then btn.count:SetText(d.count); btn.count:Show() else btn.count:Hide() end
        local searching, isHit = searchText ~= "", hitKey[key]
        -- global search: light the hits, dim everything else
        if searching and not isHit then btn.icon:SetVertexColor(0.3, 0.3, 0.3)
        else btn.icon:SetVertexColor(1, 1, 1) end
        if searching and isHit then btn.hit:Show() end
        local quality = select(3, GetItemInfo(d.itemId))
        if quality and quality >= 2 and not (searching and not isHit) then
            local c = ITEM_QUALITY_COLORS[quality]
            if c then btn.quality:SetVertexColor(c.r, c.g, c.b); btn.quality:Show() end
        end
    else
        btn.icon:Hide(); btn.count:Hide()
    end
    local pick = ExtBank.pickSrc
    if pick and pick.bag == b and pick.slot == s then btn.picked:Show() else btn.picked:Hide() end
    if focusKey == key then
        searchMarker:ClearAllPoints()
        searchMarker:SetAllPoints(btn)
        searchMarker:Show()
    end
end

-- Hand the pooled cells and name lines to whatever is on screen right now.
function ExtBank_LayoutVisible()
    if not view then return end
    local off = view:GetVerticalScroll() or 0
    local lo, hi = off - COLW, off + view:GetHeight() + COLW
    local nc, nh = 0, 0
    searchMarker:Hide()
    for _, ln in ipairs(lines) do
        if ln.y > hi then break end
        if ln.y + COLW >= lo then
            local bag = bags[ln.bag]
            if ln.hdr then
                nh = nh + 1
                local h = hdrPool[nh] or NewHeader()
                hdrPool[nh] = h
                local used, page = 0, cells[ln.bag]
                if page then for _ in pairs(page) do used = used + 1 end end
                h.name:ClearAllPoints(); h.name:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -ln.y - 4)
                h.count:ClearAllPoints(); h.count:SetPoint("TOPRIGHT", child, "TOPRIGHT", -2, -ln.y - 5)
                h.name:SetText((GetItemInfo(bag.itemId)) or ("Bag " .. (ln.bag + 1)))
                h.count:SetText(used .. " / " .. (bag.size or 0))
                h.name:Show(); h.count:Show()
            else
                for c = 0, COLS - 1 do
                    local s = ln.row * COLS + c
                    if s >= (bag.size or 0) then break end
                    nc = nc + 1
                    local btn = cellPool[nc] or NewCell(nc)
                    cellPool[nc] = btn
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", child, "TOPLEFT", c * COLW, -ln.y)
                    PaintCell(btn, ln.bag, s)
                    btn:Show()
                end
            end
        end
    end
    for i = nc + 1, #cellPool do cellPool[i]:Hide() end
    for i = nh + 1, #hdrPool do hdrPool[i].name:Hide(); hdrPool[i].count:Hide() end
end

local function ScrollTo(y)
    if not view then return end
    local maxY = math.max(0, contentH - view:GetHeight())
    scrollBar:SetValue(math.max(0, math.min(maxY, y)))
    ExtBank_LayoutVisible()
end
function ExtBank_ScrollToBag(b)
    if sectionTop[b] then ScrollTo(sectionTop[b]) end
end
-- Scroll just enough to show the cell, a third down the view when it was off screen.
function ExtBank_ScrollToCell(b, s)
    if not view or not sectionTop[b] then return end
    local y = sectionTop[b] + SECT_H + math.floor(s / COLS) * COLW
    local off, h = view:GetVerticalScroll() or 0, view:GetHeight()
    if y < off or y + COLW > off + h then ScrollTo(y - math.floor(h / 3)) end
end

-- ------------------------------------------------------------------ redraw ---
function ExtBank_Redraw()
    if not frame then return end

    -- space used, over every equipped bag
    local used, total = 0, 0
    for b = 0, unlockedBags - 1 do
        local bag = bags[b]
        if bag then
            local page = cells[b]
            if page then for _ in pairs(page) do used = used + 1 end end
            total = total + (bag.size or 0)
        end
    end
    usageText:SetText(("|cffffd100%d|r / %d"):format(used, total))
    local warband = (curStore == 1)
    local locked  = warband and not warbandOpen   -- Warband tab of an account that has not paid yet
    if sorter.running then sortBtn:SetText("Sorting..."); sortBtn:Disable()
    elseif locked then sortBtn:SetText("Sort"); sortBtn:Disable()
    else sortBtn:SetText("Sort"); sortBtn:Enable() end

    -- hit counter beside the search box, and the hit lookup for the cells
    if searchText == "" then searchStatus:SetText("")
    elseif #matches == 0 then searchStatus:SetText("|cffff5555none|r")
    else searchStatus:SetText(("|cffffd100%d / %d|r"):format(matchIndex, #matches)) end
    hitKey, focusKey = {}, nil
    for i, m in ipairs(matches) do
        hitKey[m.bag * 256 + m.slot] = true
        if i == matchIndex then focusKey = m.bag * 256 + m.slot end
    end

    -- --- the list of every bag's contents ---
    BuildLines()
    local viewH = math.max(VIEW_MIN, math.min(VIEW_MAX, contentH))
    view:ClearAllPoints()
    view:SetPoint("TOPLEFT", frame, "TOPLEFT", VIEW_LEFT, -VIEW_TOP)
    view:SetWidth(GRID_W); view:SetHeight(viewH)
    child:SetHeight(contentH)
    view:UpdateScrollChildRect()
    if locked then
        emptyText:SetText("The Warband Bank is locked.\n\nUnlock it once and every character of your account\nshares its bags and its gold.")
        emptyText:Show()
    elseif #lines == 0 then
        emptyText:SetText(unlockedBags == 0
            and "No bag slot yet.\n\nPurchase one below, then drag a bag into it."
            or  "No bag here yet.\n\nDrag a bag onto an empty bag slot below,\nor Shift+right-click a bag in your inventory.")
        emptyText:Show()
    else
        emptyText:Hide()
    end
    ScrollTo(view:GetVerticalScroll() or 0)   -- clamps after a bag left, and lays out

    -- --- bag slots under the list: rows of 8, or pages of 2x7 with arrows ---
    local bagTop  = VIEW_TOP + viewH + 8
    local entries = locked and 0 or unlockedBags
    local paged   = entries > BAG_COLS * 2
    local perRow  = paged and PAGE_COLS or BAG_COLS
    local perPage = paged and PAGE_COLS * 2 or math.max(entries, 1)
    local pages   = paged and math.ceil(entries / perPage) or 1
    stripPage = math.max(0, math.min(stripPage, pages - 1))
    local first = stripPage * perPage
    local shown = math.max(0, math.min(perPage, entries - first))
    local stripRows = locked and 0 or (paged and 2 or math.max(1, math.ceil(shown / perRow)))
    for k = 0, shown - 1 do
        local e = first + k
        local btn = GetStripButton(k + 1)
        btn.bagIndex = e
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
            VIEW_LEFT + (k % perRow) * BAG_PITCH, -bagTop - math.floor(k / perRow) * BAG_PITCH)
        local d = bags[e]
        if d then
            btn.icon:SetTexture(GetItemIcon(d.itemId) or "Interface/Icons/INV_Misc_QuestionMark")
            btn.icon:SetAlpha(1)
        else
            btn.icon:SetTexture("Interface/PaperDoll/UI-PaperDoll-Slot-Bag")
            btn.icon:SetAlpha(0.6)
        end
        btn.icon:Show()
        if e == activeBag and d then btn.sel:Show() else btn.sel:Hide() end
        if searchText ~= "" and bagHasMatch[e] then btn.searchGlow:Show() else btn.searchGlow:Hide() end
        btn:Show()
    end
    for i = shown + 1, #stripBtns do stripBtns[i]:Hide() end
    if paged then
        local ax = VIEW_LEFT + PAGE_COLS * BAG_PITCH + 6
        pageUp:ClearAllPoints(); pageUp:SetPoint("TOPLEFT", frame, "TOPLEFT", ax, -bagTop - 6)
        pageDown:ClearAllPoints(); pageDown:SetPoint("TOPLEFT", frame, "TOPLEFT", ax, -bagTop - BAG_PITCH - 6)
        if stripPage > 0 then pageUp:Enable() else pageUp:Disable() end
        if stripPage < pages - 1 then pageDown:Enable() else pageDown:Disable() end
        pageUp:Show(); pageDown:Show()
    else
        pageUp:Hide(); pageDown:Hide()
    end

    -- Cost / Purchase
    local costY = bagTop + stripRows * BAG_PITCH - 6
    costText:ClearAllPoints(); costText:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -costY - 5)
    purchaseBtn:ClearAllPoints(); purchaseBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -costY)
    if locked then
        costText:SetText(("|cffffd100Unlock the Warband Bank:|r %s %s"):format(FormatGold(WARBAND_OPEN_COST), GOLD_ICON))
        purchaseBtn:SetText("Unlock")
        purchaseBtn:Enable()
    elseif unlockedBags < MAX_BAGS then
        costText:SetText(("|cffffd100Cost:|r %s %s"):format(FormatGold(NextSlotCost()), GOLD_ICON))
        purchaseBtn:SetText("Purchase")
        purchaseBtn:Enable()
    else
        purchaseBtn:SetText("Purchase")
        costText:SetText("|cffffd100All bag slots unlocked|r")
        purchaseBtn:Disable()
    end

    -- Warband gold line (once the Warband bank is unlocked)
    if warband and not locked then
        local goldY = costY + GOLD_ROW_H
        goldText:ClearAllPoints(); goldText:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -goldY - 5)
        goldText:SetText("|cffffd100Warband gold:|r " .. MoneyString(warbandMoney))
        withdrawBtn:ClearAllPoints(); withdrawBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -goldY)
        if warbandMoney > 0 then withdrawBtn:Enable() else withdrawBtn:Disable() end
        goldText:Show(); depositBtn:Show(); withdrawBtn:Show()
    else
        goldText:Hide(); depositBtn:Hide(); withdrawBtn:Hide()
    end
    hintText:SetText(locked and "Shared by every character of your account"
        or warband and "Right-click to store anything you could mail to an alt"
        or "Right-click an item in your bags to store it")

    -- the chrome follows the height; the bottom bar holds the bag-slot count
    local h = costY + 63 + ((warband and not locked) and GOLD_ROW_H or 0)
    frame:SetHeight(h)
    LayoutChrome(FRAME_W, h)
    footText:ClearAllPoints(); footText:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -(h - 27))
    footText:SetText(("|cffa8a8a8Bag slots:|r %d"):format(unlockedBags)
        .. (paged and ("   |cffa8a8a8Page|r %d / %d"):format(stripPage + 1, pages) or ""))
    hintText:ClearAllPoints(); hintText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -(h - 27))

    -- tabs only while a banker session is live: they swap the windows / stores
    for i, t in ipairs(frameTabs) do
        SetTabSelected(t, i == curStore + 2)
        if bankOpen then t:Show() else t:Hide() end
    end
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

-- store: 0 = Extended Bank (default), 1 = Warband bank. Already open: switch store.
function ExtBank_Open(store)
    store = store or 0
    if not frame then BuildUI() end
    if isOpen then
        if store ~= curStore then SelectStore(store) end   -- the answer redraws the window
        return
    end
    isOpen = true

    -- Open in place of the personal bank so the swap feels seamless: both
    -- windows share the bank chrome, so the portraits line up. With Bagnon the
    -- bank window can't be hidden (its OnHide ends the banker session), so dock
    -- the extended bank to its right instead of replacing it.
    if bankOpen and BankFrame and BankFrame:IsShown() then
        local l, t = BankFrame:GetLeft(), BankFrame:GetTop()
        if l and t then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
        end
    elseif bankOpen and BagnonBankPanel() then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", BagnonBankPanel(), "TOPRIGHT", 6, 0)
    end

    frame:Show()
    HideBankPanel()   -- swap: extended bank replaces the native personal bank on screen
    -- pick the store first: the server answers with its snapshot (ExtBankOpen then repeats it)
    if type(ExtBankMove) == "function" then SelectStore(store) end
    if type(ExtBankOpen) == "function" then ExtBankOpen() end   -- request snapshot
    -- Turn on native-bank deposit suppression so right-clicks land in the ext
    -- bank. ExtBankOpen already covers this; kept explicit for clarity.
    if ExtBankSetActive then ExtBankSetActive(1) end
    ExtBank_Redraw()
end
-- endSession: Escape. Bank and Extended Bank are two tabs of one window, so it
-- closes both, as Escape closes the character frame whatever its tab.
function ExtBank_Close(endSession)
    isOpen = false; if frame then frame:Hide() end; ExtBank.pickSrc = nil
    if sorter.running then StopSort() end
    StaticPopup_Hide("EXTBANK_UNLOCK_CONFIRM")
    StaticPopup_Hide("EXTBANK_WARBAND_OPEN_CONFIRM")
    StaticPopup_Hide("EXTBANK_WARBAND_DEPOSIT")
    StaticPopup_Hide("EXTBANK_WARBAND_WITHDRAW")
    if endSession and bankOpen then
        hidBankPanel = false
        CloseBankFrame()     -- BANKFRAME_CLOSED follows; the bank stays hidden
    else
        RestoreBankPanel()   -- swap back to the personal bank if the session is live
    end
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
-- shared with bank_tools.lua, so both banks sort in the same order
ExtBank.SortKey, ExtBank.KeyLess = SortKey, KeyLess

-- The bank window gets the same "Bank" / "Extended Bank" / "Warband Bank" tabs
-- under it, "Bank" selected. They are parented to that window so they appear/disappear with the
-- bank itself. "The bank window" is the native BankFrame OR a bag addon's
-- replacement (Bagnon), and the replacement may be created/shown AFTER our
-- BANKFRAME_OPENED handler runs, so we poll for a moment until one of the two
-- is actually on screen.
local function AttachBankTabs(panel)
    if not bankTabs then bankTabs = CreateBankTabs(panel, "ExtBankBankTab", 1); UpdateWarbandTabs() end
    for _, t in ipairs(bankTabs) do
        t:SetParent(panel)
        t:SetFrameStrata(panel:GetFrameStrata())
        t:SetFrameLevel(panel:GetFrameLevel() + 4)
        t:Show()
    end
    bankTabs[1]:ClearAllPoints()
    if panel == BankFrame then
        -- the bank's art ends 424 px down its 512 px frame
        bankTabs[1]:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -418)
    else
        bankTabs[1]:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 12, 6)
    end
end

local ev = CreateFrame("Frame")
local tabWait = nil   -- seconds spent looking for the bank window, nil = idle
ev:SetScript("OnUpdate", function(self, elapsed)
    if not tabWait then return end
    tabWait = tabWait + elapsed
    local panel = VisibleBankPanel()
    if panel then
        AttachBankTabs(panel)
        tabWait = nil
    elseif tabWait > 2 then
        tabWait = nil   -- no bank window ever showed; give up quietly
    end
end)
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("BANKFRAME_CLOSED")
ev:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        tabWait = 0    -- find whichever bank window shows and pin the tabs to it
        -- the snapshot's tail says whether the Warband bank is unlocked (padlock on its tab)
        if type(ExtBankMove) == "function" then SelectStore(0) end
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false   -- clear FIRST so ExtBank_Close doesn't re-show the bank
        tabWait = nil
        ExtBank_Close()
    end
end)
