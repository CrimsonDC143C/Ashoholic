-- combined_bags.lua -- all the bags in one window, or not: the "combinedBags" setting, a checkbox of
-- the Project Ebonhold > General options panel. Off by default, it applies at once.
--
-- The stock code stays in charge of what opens and closes (key bindings, bag buttons, merchants,
-- mail): a backpack or bag window it shows is hidden straight away and answered here. Nothing of
-- Blizzard's is replaced, so nothing is tainted. Bank bags (id above 4) and the keyring keep their
-- stock windows.
--
-- Slots are ContainerFrameItemButtonTemplate buttons under one frame per bag (the template reads
-- the bag from its parent's ID, the slot from its own), so clicks, tooltips, splitting and the
-- modules hooked on the stock click handlers (extBank, scrap) work as in the stock bags. They are
-- made out of combat: a button made in combat could not use items.
--
-- Cost: events are only listened to while the window is open, and at most one pass per frame.
--
-- Search and Sort work like the bank's (extBank/bank_tools.lua): the echo journal's search box, what
-- does not match is dimmed; Sort moves one item at a time in the ExtBank.SortKey order, planned again
-- from the real contents after each move, and stops if a fight starts or the window closes.

local SETTING = "combinedBags"
local COLUMNS = 10
local SLOT = 37
local STEP = 39
local PAD_X, PAD_TOP, PAD_BOTTOM = 15, 40, 34
local FIRST_BAG, LAST_BAG = 0, 4
local DIM_ALPHA = 0.25
local MAX_MOVES = 400      -- safety stop for one sort
local TEX_EMPTY = "Interface\\Buttons\\UI-Slot-Background"
local TEX_QUALITY = "Interface\\Buttons\\UI-ActionButton-Border"

local bagFrames = {}    -- [bag] = the frame carrying that bag's ID
local buttons = {}      -- pool, in display order
local slotButton = {}   -- [bag][slot] = button
local dirtyBags = {}    -- [bag] = true: redraw on the next frame
local dirtyAll = false
local openPending = false   -- a stock bag window was asked for in this frame
local forceOpen = false     -- ...by a merchant, the mail, the bank: open, never toggle
local wasOpenBefore = false -- the window was already open when that happened: stays open after
local searchText = ""       -- lowercased, "" while no search is running
local searchBox, sortBtn
local sorting = { running = false, moves = 0, wait = 0, src = nil, dst = nil }

local function BagsAddonInCharge()
    if IsAddOnLoaded("Bagnon") then return true end
    if IsAddOnLoaded("ElvUI") and ElvUI then
        local E = ElvUI[1]
        return E and E.private and E.private.bags and E.private.bags.enable and true or false
    end
    return false
end

local function IsEnabled()
    local svc = ProjectEbonholdOptionsService
    return svc and svc:GetSetting(SETTING) == true and not BagsAddonInCharge()
end

-- ── The window ───────────────────────────────────────────────────────────

local frame = CreateFrame("Frame", "EbonholdCombinedBags", UIParent)
frame:Hide()
frame:SetFrameStrata("MEDIUM")
frame:SetToplevel(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 100)
frame:SetWidth(COLUMNS * STEP + PAD_X * 2)
frame:SetHeight(4 * STEP + PAD_TOP + PAD_BOTTOM)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
tinsert(UISpecialFrames, "EbonholdCombinedBags")   -- Escape closes it


local free = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
free:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 15)

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

local money = CreateFrame("Frame", "EbonholdCombinedBagsMoney", frame, "SmallMoneyFrameTemplate")
money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 7, 14)

for bag = FIRST_BAG, LAST_BAG do
    local f = CreateFrame("Frame", nil, frame)
    f:SetID(bag)
    f:SetAllPoints(frame)
    f:EnableMouse(false)
    bagFrames[bag] = f
    slotButton[bag] = {}
end

-- ── Slots ────────────────────────────────────────────────────────────────

local function NewButton(i)
    local b = CreateFrame("Button", "EbonholdCombinedBagsItem" .. i, frame, "ContainerFrameItemButtonTemplate")
    b:SetWidth(SLOT)
    b:SetHeight(SLOT)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(TEX_EMPTY)
    bg:SetTexCoord(0, 0.64, 0, 0.64)
    bg:SetAllPoints(b)
    local q = b:CreateTexture(nil, "OVERLAY")
    q:SetTexture(TEX_QUALITY)
    q:SetBlendMode("ADD")
    q:SetWidth(SLOT * 1.75)
    q:SetHeight(SLOT * 1.75)
    q:SetPoint("CENTER", b, "CENTER", 0, 0)
    q:Hide()
    b.ebhQuality = q
    b.ebhQuest = _G[b:GetName() .. "IconQuestTexture"]
    b.ebhCooldown = _G[b:GetName() .. "Cooldown"]
    return b
end

local function MatchesSearch(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not link then return false end
    local byId = tonumber(searchText)
    if byId then return tonumber(link:match("item:(%d+)")) == byId end
    local name = link:match("%[(.-)%]")
    return name ~= nil and string.find(string.lower(name), searchText, 1, true) ~= nil
end

local function DrawButton(b, bag, slot, tooltipOwner)
    local texture, count, locked, quality, readable = GetContainerItemInfo(bag, slot)
    b:SetAlpha((searchText == "" or MatchesSearch(bag, slot)) and 1 or DIM_ALPHA)
    SetItemButtonTexture(b, texture)
    SetItemButtonCount(b, count)
    SetItemButtonDesaturated(b, locked, 0.5, 0.5, 0.5)
    b.hasItem = texture and 1 or nil
    b.readable = readable

    if texture and quality and quality > 1 then
        local c = ITEM_QUALITY_COLORS[quality]
        b.ebhQuality:SetVertexColor(c.r, c.g, c.b, 0.8)
        b.ebhQuality:Show()
    else
        b.ebhQuality:Hide()
    end

    if b.ebhQuest then
        local isQuestItem, questId, isActive = GetContainerItemQuestInfo(bag, slot)
        if questId and not isActive then
            b.ebhQuest:SetTexture(TEXTURE_ITEM_QUEST_BANG)
            b.ebhQuest:Show()
        elseif questId or isQuestItem then
            b.ebhQuest:SetTexture(TEXTURE_ITEM_QUEST_BORDER)
            b.ebhQuest:Show()
        else
            b.ebhQuest:Hide()
        end
    end

    if texture then
        ContainerFrame_UpdateCooldown(bag, b)
    elseif b.ebhCooldown then
        b.ebhCooldown:Hide()
    end

    if b == tooltipOwner and b.UpdateTooltip then b.UpdateTooltip(b) end
end

local function UpdateFree()
    local empty, total = 0, 0
    for bag = FIRST_BAG, LAST_BAG do
        total = total + GetContainerNumSlots(bag)
        empty = empty + (GetContainerNumFreeSlots(bag) or 0)
    end
    free:SetText(empty .. " / " .. total)
end

-- Lays the slots of all the bags out, in bag order. False when it had to wait for the end of combat.
local function Layout()
    local n = 0
    for bag = FIRST_BAG, LAST_BAG do n = n + GetContainerNumSlots(bag) end
    if n > #buttons and InCombatLockdown() then return false end

    local i = 0
    for bag = FIRST_BAG, LAST_BAG do
        wipe(slotButton[bag])
        for slot = 1, GetContainerNumSlots(bag) do
            i = i + 1
            local b = buttons[i]
            if not b then
                b = NewButton(i)
                buttons[i] = b
            end
            b:SetParent(bagFrames[bag])
            b:SetID(slot)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame, "TOPLEFT",
                PAD_X + ((i - 1) % COLUMNS) * STEP, -(PAD_TOP + math.floor((i - 1) / COLUMNS) * STEP))
            b:Show()
            slotButton[bag][slot] = b
        end
    end
    for j = i + 1, #buttons do buttons[j]:Hide() end

    local rows = math.max(1, math.ceil(i / COLUMNS))
    frame:SetHeight(rows * STEP + PAD_TOP + PAD_BOTTOM)
    frame.ebhSlots = i
    return true
end

local function DrawAll()
    local total = 0
    for bag = FIRST_BAG, LAST_BAG do total = total + GetContainerNumSlots(bag) end
    if total ~= frame.ebhSlots and not Layout() then return end
    local owner = GameTooltip:GetOwner()
    for bag = FIRST_BAG, LAST_BAG do
        for slot, b in pairs(slotButton[bag]) do DrawButton(b, bag, slot, owner) end
    end
    UpdateFree()
end

local function DrawBag(bag)
    local n = GetContainerNumSlots(bag)
    local count = 0
    for _ in pairs(slotButton[bag]) do count = count + 1 end
    if n ~= count then dirtyAll = true return end    -- a bag was changed
    local owner = GameTooltip:GetOwner()
    for slot, b in pairs(slotButton[bag]) do DrawButton(b, bag, slot, owner) end
    UpdateFree()
end

-- ── Sort ─────────────────────────────────────────────────────────────────

local runner = CreateFrame("Frame")
runner:Hide()

local function SameKey(a, b)
    return not ExtBank.KeyLess(a, b) and not ExtBank.KeyLess(b, a)
end

-- The regular bags as one list, each special bag (herbs, enchanting...) on its own: the server
-- refuses to swap across bag families.
local function SortGroups()
    local regular, groups = {}, {}
    for bag = FIRST_BAG, LAST_BAG do
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

-- Two partial stacks of one item in a group: the later one goes onto the earlier one, which merges
-- them. Same full link only, and a few tries per link: what does not stack would just swap forever.
local function NextMerge(g)
    local first = {}
    for _, p in ipairs(g) do
        local link = GetContainerItemLink(p.bag, p.slot)
        if link then
            local _, count = GetContainerItemInfo(p.bag, p.slot)
            local maxStack = select(8, GetItemInfo(link))
            if maxStack and count and count < maxStack and (sorting.mergeTries[link] or 0) < 30 then
                if first[link] then
                    sorting.mergeTries[link] = (sorting.mergeTries[link] or 0) + 1
                    return p, first[link]
                end
                first[link] = p
            end
        end
    end
end

-- The first move toward the sorted order (source, destination), or nil when sorted.
local function NextMove()
    for _, g in ipairs(SortGroups()) do
        local src, dst = NextMerge(g)
        if src then return src, dst end
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
            if not (keys[i] and SameKey(keys[i], want)) then
                -- everything before i is in place, so the item that belongs here sits further on
                for j = i + 1, #g do
                    if keys[j] and SameKey(keys[j], want) then return g[j], g[i] end
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

local function SortStep()
    if InCombatLockdown() then StopSort("Sorting stopped: you entered combat."); return end
    if CursorHasItem() then StopSort("Put down the item on your cursor first."); return end
    if sorting.moves >= MAX_MOVES then StopSort("Some items could not be sorted."); return end
    local src, dst = NextMove()
    if not src then StopSort(); return end
    sorting.moves = sorting.moves + 1
    PickupContainerItem(src.bag, src.slot)
    PickupContainerItem(dst.bag, dst.slot)
    if CursorHasItem() then   -- the drop was refused
        ClearCursor()
        StopSort("Some items could not be sorted.")
        return
    end
    sorting.src, sorting.dst, sorting.wait = src, dst, 0
end

-- next move once the server has unlocked both slots of the last one
runner:SetScript("OnUpdate", function(_, elapsed)
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
    SortStep()
end)

local function StartSort()
    if sorting.running then return end
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage("You can't sort your bags in combat.", 1.0, 0.1, 0.1, 1.0)
        return
    end
    if CursorHasItem() then
        UIErrorsFrame:AddMessage("Put down the item on your cursor first.", 1.0, 0.1, 0.1, 1.0)
        return
    end
    sorting.running, sorting.moves, sorting.src, sorting.dst, sorting.wait = true, 0, nil, nil, 0
    sorting.mergeTries = {}
    sortBtn:SetText("Sorting...")
    sortBtn:Disable()
    runner:Show()
end

-- ── Search box and Sort button ───────────────────────────────────────────

-- On the first show: the search box template comes from the collections module, later in the .toc.
local function BuildTools()
    if searchBox then return end
    local ok, box = pcall(CreateFrame, "EditBox", "EbonholdCombinedBagsSearch", frame, "ezCollectionsSearchBoxTemplate")
    if ok and box and box.Instructions then
        box.Instructions:SetText("Search")
    else
        box = CreateFrame("EditBox", "EbonholdCombinedBagsSearch", frame, "InputBoxTemplate")
    end
    box:SetAutoFocus(false)
    box:SetWidth(170)
    box:SetHeight(20)
    box:SetMaxLetters(50)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -12)
    searchBox = box

    -- run the search 0.2 s after the last key, like the bank's box
    local debounce = CreateFrame("Frame")
    debounce:Hide()
    local function Apply()
        debounce:Hide()
        local text = string.lower(box:GetText() or "")
        if text == searchText then return end
        searchText = text
        dirtyAll = true
    end
    debounce:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t >= 0.2 then self.t = 0; Apply() end
    end)
    -- HookScript: the template's own scripts (placeholder, clear button) keep running
    box:HookScript("OnTextChanged", function() debounce.t = 0; debounce:Show() end)
    box:HookScript("OnEscapePressed", function(self) self:SetText(""); Apply(); self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) Apply(); self:ClearFocus() end)

    sortBtn = CreateFrame("Button", "EbonholdCombinedBagsSort", frame, "UIPanelButtonTemplate")
    sortBtn:SetWidth(76)
    sortBtn:SetHeight(22)
    sortBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -11)
    sortBtn:SetText("Sort")
    sortBtn:SetScript("OnClick", StartSort)
    sortBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Sort")
        GameTooltip:AddLine("Merges your stacks and orders your bags by type, quality and name, one item at a time. Special bags are sorted on their own.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ── While open ───────────────────────────────────────────────────────────

local EVENTS = { "BAG_UPDATE", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "QUEST_ACCEPTED",
    "UNIT_QUEST_LOG_CHANGED", "PLAYER_REGEN_ENABLED" }

frame:SetScript("OnEvent", function(_, event, a, b)
    if event == "BAG_UPDATE" then
        if a and a >= FIRST_BAG and a <= LAST_BAG then dirtyBags[a] = true end
    elseif event == "ITEM_LOCK_CHANGED" then
        local button = a and b and slotButton[a] and slotButton[a][b]
        if button then
            local _, _, locked = GetContainerItemInfo(a, b)
            SetItemButtonDesaturated(button, locked, 0.5, 0.5, 0.5)
        end
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if a == "player" then dirtyAll = true end
    else
        dirtyAll = true
    end
end)

frame:SetScript("OnUpdate", function()
    if dirtyAll then
        dirtyAll = false
        wipe(dirtyBags)
        DrawAll()
    elseif next(dirtyBags) then
        for bag in pairs(dirtyBags) do DrawBag(bag) end
        wipe(dirtyBags)
    end
end)

frame:SetScript("OnShow", function(self)
    for _, e in ipairs(EVENTS) do self:RegisterEvent(e) end
    PlaySound("igBackPackOpen")
    BuildTools()
    self.ebhSlots = nil
    DrawAll()
end)

frame:SetScript("OnHide", function(self)
    for _, e in ipairs(EVENTS) do self:UnregisterEvent(e) end
    PlaySound("igBackPackClose")
    wasOpenBefore = false
    if sorting.running then StopSort() end
    if searchBox then
        searchBox:SetText("")
        searchBox:ClearFocus()
        searchText = ""
    end
end)

-- ── Answering the stock code ─────────────────────────────────────────────

-- A stock call opens up to five windows in one go: they are answered once, on the next frame.
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
    self:Hide()
    local force = forceOpen
    openPending, forceOpen = false, false
    if force or not frame:IsShown() then
        frame:Show()
    else
        frame:Hide()
    end
end)

local function StockWindowShown(self)
    if not IsEnabled() then return end
    local id = self:GetID()
    if id < FIRST_BAG or id > LAST_BAG then return end
    self:Hide()
    openPending = true
    driver:Show()
end

for i = 1, NUM_CONTAINER_FRAMES do
    local f = _G["ContainerFrame" .. i]
    if f then f:HookScript("OnShow", StockWindowShown) end
end

local function ForcedOpen()
    if not IsEnabled() then return end
    wasOpenBefore = frame:IsShown()
    forceOpen = true
end

hooksecurefunc("OpenBackpack", ForcedOpen)
hooksecurefunc("OpenAllBags", function(force)
    if force then ForcedOpen() end
end)
hooksecurefunc("CloseBackpack", function()
    if frame:IsShown() and not wasOpenBefore then frame:Hide() end
end)
hooksecurefunc("CloseAllBags", function()
    if frame:IsShown() then frame:Hide() end
end)

-- ── Option ───────────────────────────────────────────────────────────────

local function CreateOptionCheckbox()
    local panel = _G.InterfaceOptionsProjectEbonholdPanelGeneral
    if not panel then return end
    local cb = CreateFrame("CheckButton", "ProjectEbonholdCombinedBagsCheck", panel,
        "InterfaceOptionsCheckButtonTemplate")
    local last = _G.ProjectEbonholdLootBindCheck or _G[panel:GetName() .. "AutoSellJunk"]
    if last then
        cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 0)
    else
        cb:SetPoint("TOPLEFT", 16, -208)
    end
    _G[cb:GetName() .. "Text"]:SetText("Combine all bags into one window")
    cb:SetScript("OnClick", function(self)
        ProjectEbonholdOptionsService:SetSetting(SETTING, self:GetChecked() and true or false)
        frame:Hide()
    end)
    local function Refresh()
        local svc = ProjectEbonholdOptionsService
        cb:SetChecked(svc and svc:GetSetting(SETTING) == true)
    end
    panel:HookScript("OnShow", Refresh)
    if panel.refresh then hooksecurefunc(panel, "refresh", Refresh) end
    Refresh()
end

-- The slots exist before the first fight: see the top of this file.
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    CreateOptionCheckbox()
    Layout()
    frame:SetAlpha(1)
end)

-- Edit Mode shows its box as soon as the option is on, window open or not.
ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.CombinedBagsEnabled = IsEnabled
