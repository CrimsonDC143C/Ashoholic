local addonName, addon = ...

-- bank_tools.lua — search box and Sort on the personal bank (the stock BankFrame),
-- at the same place as on the Extended Bank window, which wears the same chrome.
--
-- Search: what does not match is dimmed in the bank's 28 slots and in the open
-- bank bags, and the bag slots holding a match get a gold ring.
-- Sort: the server has no bank sort, so items move one at a time with
-- PickupContainerItem, waiting for the server to unlock both slots before the
-- next move. The next move is planned again from the real contents each time:
-- a drop onto the same item merges the stacks instead of swapping them.
-- Same order as the Extended Bank sort (ExtBank.SortKey, from extBank.lua).
-- Bagnon replaces the BankFrame and has its own search: nothing is added there.

local BANK_BAG_FIRST = NUM_BAG_SLOTS + 1
local BANK_BAG_LAST  = NUM_BAG_SLOTS + NUM_BANKBAGSLOTS
local DIM_ALPHA      = 0.25
local MAX_MOVES      = 400      -- safety stop for one sort

local searchText = ""           -- lowercased needle, "" while no search is running
local touched = {}              -- [button] = true once dimmed or ringed, to undo it
local rings = {}                -- [button] = gold ring texture
local box, status, sortBtn, usage
local sorting = { running = false, moves = 0, wait = 0, src = nil, dst = nil }
local runner = CreateFrame("Frame")
runner:Hide()

-- ------------------------------------------------------------------ search ----
-- true = an item that matches, false = an item that does not, nil = empty slot
local function Matches(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not link then return nil end
    local byId = tonumber(searchText)
    if byId then return tonumber(link:match("item:(%d+)")) == byId end
    local name = link:match("%[(.-)%]")
    return name ~= nil and string.find(string.lower(name), searchText, 1, true) ~= nil
end

local function Ring(btn, on)
    local r = rings[btn]
    if on and not r then
        r = btn:CreateTexture(nil, "OVERLAY")
        r:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        r:SetBlendMode("ADD")
        r:SetVertexColor(1, 0.82, 0.2)
        r:SetPoint("TOPLEFT", btn, "TOPLEFT", -10, 10)
        r:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 10, -10)
        rings[btn] = r
    end
    if r then if on then r:Show() else r:Hide() end end
end

local function Reset(btn)
    if touched[btn] then
        btn:SetAlpha(1); Ring(btn, false)
        touched[btn] = nil
    end
end

-- dim / ring one item button; returns true on a hit
local function Paint(btn, bag, slot)
    if searchText == "" then Reset(btn); return false end
    local m = Matches(bag, slot)
    touched[btn] = true
    btn:SetAlpha(m and 1 or DIM_ALPHA)
    Ring(btn, m == true)
    return m == true
end

local function IsBankBag(bag)
    return bag >= BANK_BAG_FIRST and bag <= BANK_BAG_LAST
end

-- the item buttons of an open bag window, with the slot each one shows
local function PaintContainerFrame(f)
    local bag = f:GetID()
    for j = 1, (f.size or 0) do
        local btn = _G[f:GetName() .. "Item" .. j]
        if btn then
            if IsBankBag(bag) then Paint(btn, bag, btn:GetID()) else Reset(btn) end
        end
    end
end

local function Refresh()
    if not box or not BankFrame:IsShown() then return end
    local hits = 0
    for s = 1, NUM_BANKGENERIC_SLOTS do
        local btn = _G["BankFrameItem" .. s]
        if btn and Paint(btn, BANK_CONTAINER, s) then hits = hits + 1 end
    end
    for i = 1, NUM_BANKBAGSLOTS do
        local bag, any = NUM_BAG_SLOTS + i, false
        if searchText ~= "" then
            for s = 1, GetContainerNumSlots(bag) do
                if Matches(bag, s) then any = true; hits = hits + 1 end
            end
        end
        local bagBtn = _G["BankFrameBag" .. i]
        if bagBtn then
            if any then touched[bagBtn] = true; Ring(bagBtn, true) else Reset(bagBtn) end
        end
    end
    for i = 1, NUM_CONTAINER_FRAMES do
        local f = _G["ContainerFrame" .. i]
        if f and f:IsShown() then PaintContainerFrame(f) end
    end

    if searchText == "" then status:SetText("")
    elseif hits == 0 then status:SetText("|cffff5555none|r")
    else status:SetText(("|cffffd100%d|r"):format(hits)) end

    local used, total = 0, 0
    for _, bag in ipairs({ BANK_CONTAINER, 5, 6, 7, 8, 9, 10, 11 }) do
        local n = GetContainerNumSlots(bag)
        total = total + n
        used = used + n - (GetContainerNumFreeSlots(bag) or 0)
    end
    usage:SetText(("|cffa8a8a8Slots used:|r |cffffd100%d|r / %d"):format(used, total))
end

-- -------------------------------------------------------------------- sort ----
local function Equal(a, b)
    return not ExtBank.KeyLess(a, b) and not ExtBank.KeyLess(b, a)
end

-- Slot lists to sort: the bank's own slots and its regular bags as one list,
-- each special bag (herbs, enchanting...) on its own.
local function Groups()
    local regular, groups = {}, {}
    for s = 1, GetContainerNumSlots(BANK_CONTAINER) do regular[#regular + 1] = { bag = BANK_CONTAINER, slot = s } end
    for bag = BANK_BAG_FIRST, BANK_BAG_LAST do
        local n = GetContainerNumSlots(bag)
        if n > 0 then
            local _, family = GetContainerNumFreeSlots(bag)
            local g = regular
            if family and family ~= 0 then g = {}; groups[#groups + 1] = g end
            for s = 1, n do g[#g + 1] = { bag = bag, slot = s } end
        end
    end
    table.insert(groups, 1, regular)
    return groups
end

-- The first move toward the sorted order (source, destination), or nil when sorted.
local function NextMove()
    for _, g in ipairs(Groups()) do
        local keys, sorted = {}, {}
        for i, p in ipairs(g) do
            local link = GetContainerItemLink(p.bag, p.slot)
            if link then
                local _, count = GetContainerItemInfo(p.bag, p.slot)
                keys[i] = ExtBank.SortKey({ itemId = tonumber(link:match("item:(%d+)")), count = count or 1, lowGuid = 0 })
                sorted[#sorted + 1] = keys[i]
            end
        end
        table.sort(sorted, ExtBank.KeyLess)
        for i, want in ipairs(sorted) do
            if not (keys[i] and Equal(keys[i], want)) then
                -- everything before i is in place, so the item that belongs here sits further on
                for j = i + 1, #g do
                    if keys[j] and Equal(keys[j], want) then return g[j], g[i] end
                end
                return nil
            end
        end
    end
    return nil
end

local function StopSort(msg)
    sorting.running, sorting.src, sorting.dst = false, nil, nil
    runner:Hide()
    if sortBtn then sortBtn:SetText("Sort"); sortBtn:Enable() end
    if msg then UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1, 1.0) end   -- red, like the client's own errors
end

local function Step()
    if CursorHasItem() then StopSort("Put down the item on your cursor first."); return end
    if sorting.moves >= MAX_MOVES then StopSort("Some items could not be sorted."); return end
    local src, dst = NextMove()
    if not src then StopSort(); return end
    sorting.moves = sorting.moves + 1
    PickupContainerItem(src.bag, src.slot)
    PickupContainerItem(dst.bag, dst.slot)
    if CursorHasItem() then   -- the drop was refused (bag type)
        ClearCursor()
        StopSort("Some items could not be sorted.")
        return
    end
    sorting.src, sorting.dst, sorting.wait = src, dst, 0
end

-- next move once the server has unlocked both slots of the last one
runner:SetScript("OnUpdate", function(self, elapsed)
    sorting.wait = sorting.wait + elapsed
    if sorting.src then
        local _, _, lockedA = GetContainerItemInfo(sorting.src.bag, sorting.src.slot)
        local _, _, lockedB = GetContainerItemInfo(sorting.dst.bag, sorting.dst.slot)
        if lockedA or lockedB then
            if sorting.wait > 3 then StopSort("Some items could not be sorted.") end
            return
        end
    end
    if sorting.wait < 0.05 then return end
    Step()
end)

local function StartSort()
    if sorting.running or not BankFrame:IsShown() then return end
    if CursorHasItem() then return end
    sorting.running, sorting.moves, sorting.src, sorting.wait = true, 0, nil, 0
    sortBtn:SetText("Sorting..."); sortBtn:Disable()
    runner:Show()
end

-- ---------------------------------------------------------------------- UI ----
-- Same places as on the Extended Bank window (both wear UI-BankFrame), narrowed
-- to the bank's 399 px.
local function Build()
    box = CreateFrame("EditBox", "ExtBankBankSearchBox", BankFrame, "ezCollectionsSearchBoxTemplate")
    box:SetWidth(150); box:SetHeight(20)
    box:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 80, -44)
    box:SetAutoFocus(false)
    box:SetMaxLetters(50)
    box.Instructions:SetText("Search")
    status = BankFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("LEFT", box, "RIGHT", 6, 0)

    -- run the search 0.2 s after the last key, like the Extended Bank box
    local debounce = CreateFrame("Frame")
    debounce:Hide()
    local function Apply()
        debounce:Hide()
        local text = string.lower(box:GetText() or "")
        if text == searchText then return end
        searchText = text
        Refresh()
    end
    debounce:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t >= 0.2 then self.t = 0; Apply() end
    end)
    -- HookScript: the template's own scripts (placeholder, clear button) keep running
    box:HookScript("OnTextChanged", function() debounce.t = 0; debounce:Show() end)
    box:HookScript("OnEscapePressed", function(self) self:SetText(""); Apply() end)
    box:SetScript("OnEnterPressed", function(self) Apply(); self:ClearFocus() end)

    sortBtn = CreateFrame("Button", "ExtBankBankSortButton", BankFrame, "UIPanelButtonTemplate")
    sortBtn:SetWidth(64); sortBtn:SetHeight(22)
    sortBtn:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 288, -43)
    sortBtn:SetText("Sort")
    sortBtn:SetScript("OnClick", StartSort)
    sortBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sort")
        GameTooltip:AddLine("Orders the bank and its bags by type, quality and name, one item at a time.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- space used, in the bank's bottom bar
    usage = BankFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    usage:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 28, -398)
end

hooksecurefunc("ContainerFrame_Update", function(f)
    if box and (searchText ~= "" or next(touched)) then PaintContainerFrame(f) end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("BANKFRAME_CLOSED")
ev:RegisterEvent("BAG_UPDATE")
ev:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
ev:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        if not BankFrame then return end
        if not box then Build() end
        Refresh()
    elseif event == "BANKFRAME_CLOSED" then
        if sorting.running then StopSort() end
        if box then box:SetText(""); box:ClearFocus() end
        searchText = ""
        for btn in pairs(touched) do Reset(btn) end
    elseif box and BankFrame:IsShown() then
        Refresh()
    end
end)
