local addonName, addon = ...

-- ── Guild bank: 16 tabs, pages, search ───────────────────────────────────────
-- A guild owns up to 16 bank tabs on Ashendor; the 3.3.5 client only knows 6.
-- The server shows one page of 6 tabs at a time and numbers every tab on that
-- page (Guild::HandleSetBankPage), so the stock guild bank frame keeps working
-- untouched. This module adds, on the frame's title band, the page turning
-- (top right, the spellbook's "Page N" and arrows) and a search box (top left,
-- the echo journal's), shows the real price and count on the purchase screen,
-- and hides the "buy" tab past the last tab of the last page.
-- The search runs on the server (Guild::HandleBankSearch): only it knows the
-- contents of the tabs the client has not opened.
-- Transport: custom opcodes through ebonhold.dll (guildbank_client.h):
-- GuildBankSetPage(page) / GuildBankSearch(serial, text) out, GuildBank_OnPacket(hex)
-- in. A client without that DLL keeps the stock bank (first page, no search).

local PAGE_TABS = 6
local SLOTS = MAX_GUILDBANK_SLOTS_PER_TAB or 98
local DIM_ALPHA = 0.25          -- items and tabs without a match while searching

local State = {
    received = false,
    page = 0,          -- 0-based
    purchased = 0,
    maxTabs = 16,
    nextCost = 0,      -- copper, 0 = every tab bought
}

local Search = {
    text = "",         -- what the box holds (trimmed)
    serial = 0,        -- id of the last query sent; an answer with another id is stale
    matches = {},      -- [guild tab 0-15] = { [slot 1-98] = true }
    counts = {},       -- [guild tab 0-15] = number of matching slots
}

local function NumPages()
    return math.ceil(State.maxTabs / PAGE_TABS)
end

local function FirstTab(page)
    return page * PAGE_TABS
end

-- A page can be shown when it has tabs, or when the guild master buys its first tab there.
local function PageUsable(page)
    local first = FirstTab(page)
    if State.purchased > first then return true end
    return IsGuildLeader() and State.purchased == first and first < State.maxTabs
end

-- The next tab is bought on the page that will hold it.
local function NextTabOnShownPage()
    local first = FirstTab(State.page)
    return State.nextCost > 0 and State.purchased >= first and State.purchased < first + PAGE_TABS
end

-- ── Purchase screen: real price and count ────────────────────────────────────
-- The client prices the next tab from its own 6-tab table: past the first page
-- it would ask 100 gold for tab 7. The stock code calls these at run time.
local stockGetGuildBankTabCost = GetGuildBankTabCost
GetGuildBankTabCost = function(...)
    if not State.received then
        return stockGetGuildBankTabCost(...)
    end
    if NextTabOnShownPage() then
        return State.nextCost
    end
    return nil
end

local function FixPurchasedText()
    if State.received and GuildBankFrameBuyInfoNumTabsPurchasedText then
        GuildBankFrameBuyInfoNumTabsPurchasedText:SetText(format(NUM_GUILDBANK_TABS_PURCHASED, State.purchased, State.maxTabs))
    end
end

-- On the last page the stock frame offers a "buy" tab after the last real one.
local function HideBuyTabPastMax()
    if not State.received then return end
    local numTabs = GetNumGuildBankTabs()
    if numTabs < PAGE_TABS and FirstTab(State.page) + numTabs >= State.maxTabs then
        local tab = _G["GuildBankTab" .. (numTabs + 1)]
        if tab then tab:Hide() end
    end
end

-- ── Page navigation ──────────────────────────────────────────────────────────
-- The spellbook's own paging, at the right end of the title band:
-- "Page 2" then its round previous / next buttons.
local nav

local function LastUsablePage()
    local last = 0
    for page = 0, NumPages() - 1 do
        if PageUsable(page) then last = page end
    end
    return last
end

-- Matches on the pages before / after the shown one, for the arrows.
local function MatchesBeyond(step)
    local total = 0
    for tab, count in pairs(Search.counts) do
        local page = math.floor(tab / PAGE_TABS)
        if (step < 0 and page < State.page) or (step > 0 and page > State.page) then
            total = total + count
        end
    end
    return total
end

local function UpdatePageButtons()
    if not nav then return end
    if not GuildBankSetPage then
        nav:Hide()   -- client without the guild bank part of ebonhold.dll
        return
    end

    local last = LastUsablePage()
    if last == 0 and State.page == 0 then
        nav:Hide()   -- a single page: nothing to turn
        return
    end

    nav:Show()
    nav.text:SetFormattedText(PAGE_NUMBER, State.page + 1)
    for _, arrow in ipairs({ nav.prev, nav.next }) do
        local target = State.page + arrow.step
        if target >= 0 and target <= last then arrow:Enable() else arrow:Disable() end
        -- searching: the arrow towards matches on other pages glows
        if Search.text ~= "" and MatchesBeyond(arrow.step) > 0 then arrow:LockHighlight() else arrow:UnlockHighlight() end
    end
end

local function RequestPage(page)
    if page == State.page or page < 0 or not PageUsable(page) then return end
    -- Same as a stock tab click: an open tab-info text is saved first.
    if GuildBankInfo and GuildBankInfo:IsShown() and GuildBankInfoSaveButton then
        GuildBankInfoSaveButton:Click()
    end
    if GuildBankPopupFrame then GuildBankPopupFrame:Hide() end
    if GuildBankSetPage then GuildBankSetPage(page) end
end

local function PageTooltip(self)
    local page = State.page + self.step
    local first = FirstTab(page) + 1
    local last = math.min(FirstTab(page) + PAGE_TABS, State.maxTabs)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(string.format(PAGE_NUMBER, page + 1), 1, 1, 1)
    if State.purchased > FirstTab(page) then
        GameTooltip:AddLine(string.format("Tabs %d - %d", first, math.min(last, State.purchased)), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    else
        GameTooltip:AddLine(string.format("Buy tab %d here.", first), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    end
    local found = Search.text ~= "" and MatchesBeyond(self.step) or 0
    if found > 0 then
        GameTooltip:AddLine(string.format("%d search result%s that way.", found, found > 1 and "s" or ""), GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
    end
    GameTooltip:Show()
end

local function CreatePageArrow(name, direction, step)
    local button = CreateFrame("Button", name, nav)
    button:SetSize(26, 26)
    button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Down")
    button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button.step = step
    button:SetScript("OnClick", function(self)
        PlaySound("igAbiliityPageTurn")
        RequestPage(State.page + self.step)
    end)
    button:SetScript("OnEnter", PageTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

-- ── Search ───────────────────────────────────────────────────────────────────
local searchBox
local searchTimer = CreateFrame("Frame")
searchTimer:Hide()

local function CurrentGuildTab()
    return FirstTab(State.page) + GetCurrentGuildBankTab() - 1
end

-- Dims what does not match: the items of the shown tab, the tabs with no result.
local function ApplySearch()
    if not GuildBankFrame then return end
    local searching = Search.text ~= ""
    local bankMode = GuildBankFrame.mode == "bank"

    if searchBox then
        if bankMode and GuildBankSearch then searchBox:Show() else searchBox:Hide() end
    end

    local shown = Search.matches[CurrentGuildTab()]
    for i = 1, SLOTS do
        local column = math.ceil((i - 0.5) / NUM_SLOTS_PER_GUILDBANK_GROUP)
        local index = i % NUM_SLOTS_PER_GUILDBANK_GROUP
        if index == 0 then index = NUM_SLOTS_PER_GUILDBANK_GROUP end
        local button = _G["GuildBankColumn" .. column .. "Button" .. index]
        if button then
            button:SetAlpha((searching and bankMode and not (shown and shown[i])) and DIM_ALPHA or 1)
        end
    end

    for i = 1, PAGE_TABS do
        local tab = _G["GuildBankTab" .. i]
        local tabButton = _G["GuildBankTab" .. i .. "Button"]
        if tab and tabButton then
            if not tabButton.searchCount then
                tabButton.searchCount = tabButton:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
                tabButton.searchCount:SetPoint("BOTTOMRIGHT", tabButton, "BOTTOMRIGHT", -2, 2)
            end
            local count = Search.counts[FirstTab(State.page) + i - 1] or 0
            if searching and count > 0 then
                tabButton.searchCount:SetText(count)
                tabButton.searchCount:Show()
            else
                tabButton.searchCount:Hide()
            end
            tab:SetAlpha((searching and count == 0) and DIM_ALPHA + 0.2 or 1)
        end
    end

    UpdatePageButtons()
end

local function SendSearch()
    if Search.text == "" then return end
    if not GuildBankSearch then return end
    Search.serial = Search.serial + 1
    GuildBankSearch(Search.serial, Search.text)
end

-- Typing and bank changes ask again after a short pause, not once per key.
local function ScheduleSearch(delay)
    searchTimer.left = delay
    searchTimer:Show()
end

searchTimer:SetScript("OnUpdate", function(self, elapsed)
    self.left = self.left - elapsed
    if self.left <= 0 then
        self:Hide()
        SendSearch()
    end
end)

local function OnSearchText(text)
    text = strtrim(text or "")
    if text == Search.text then return end
    Search.text = text
    if text == "" then
        searchTimer:Hide()
        Search.serial = Search.serial + 1   -- an answer still on its way is dropped
        Search.matches, Search.counts = {}, {}
        ApplySearch()
    else
        ScheduleSearch(0.3)
    end
end

-- The echo journal's search box, like every search bar of the addon.
local function CreateSearchBox()
    local ok, box = pcall(CreateFrame, "EditBox", "ProjectEbonholdGuildBankSearchBox", GuildBankFrame, "ezCollectionsSearchBoxTemplate")
    if ok and box then
        if box.Instructions then box.Instructions:SetText(SEARCH) end
    else
        box = CreateFrame("EditBox", "ProjectEbonholdGuildBankSearchBox", GuildBankFrame, "InputBoxTemplate")
    end
    box:SetSize(160, 20)
    -- Left end of the title band, level with the tab title, below the frame's top border.
    box:SetPoint("TOPLEFT", GuildBankFrame, "TOPLEFT", 32, -36)
    box:SetAutoFocus(false)
    box:SetMaxLetters(50)
    box:SetFrameLevel(GuildBankFrame:GetFrameLevel() + 5)
    -- HookScript: the template binds its own OnTextChanged (placeholder, clear button).
    box:HookScript("OnTextChanged", function(self) OnSearchText(self:GetText()) end)
    box:HookScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

-- ── Frame setup ──────────────────────────────────────────────────────────────
local function CreatePageButtons()
    if nav or not GuildBankFrame then return end

    -- Right end of the title band, before the close button.
    nav = CreateFrame("Frame", "ProjectEbonholdGuildBankPages", GuildBankFrame)
    nav:SetSize(110, 26)
    nav:SetPoint("TOPRIGHT", GuildBankFrame, "TOPRIGHT", -16, -25)
    nav:SetFrameLevel(GuildBankFrame:GetFrameLevel() + 5)

    nav.next = CreatePageArrow("ProjectEbonholdGuildBankNextPage", "Next", 1)
    nav.next:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
    nav.prev = CreatePageArrow("ProjectEbonholdGuildBankPrevPage", "Prev", -1)
    nav.prev:SetPoint("RIGHT", nav.next, "LEFT", -1, 0)
    nav.text = nav:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    nav.text:SetPoint("RIGHT", nav.prev, "LEFT", -5, 0)
    nav:Hide()

    searchBox = CreateSearchBox()

    hooksecurefunc("GuildBankFrame_UpdateTabs", HideBuyTabPastMax)
    hooksecurefunc("GuildBankFrame_UpdateTabBuyingInfo", FixPurchasedText)
    hooksecurefunc("GuildBankFrame_Update", ApplySearch)
    -- The buy screen's OnShow holds the stock function itself, not the hooked global.
    if GuildBankFrameBuyInfo then
        GuildBankFrameBuyInfo:HookScript("OnShow", FixPurchasedText)
    end
    GuildBankFrame:HookScript("OnShow", function()
        UpdatePageButtons()
        if Search.text ~= "" then ScheduleSearch(0) end
    end)
    -- Items moved by anyone: the results follow.
    GuildBankFrame:HookScript("OnEvent", function(self, event)
        if event == "GUILDBANKBAGSLOTS_CHANGED" and Search.text ~= "" then ScheduleSearch(0.5) end
    end)

    UpdatePageButtons()
end

-- ── Server ───────────────────────────────────────────────────────────────────
local function OnPageInfo(page, purchased, maxTabs, nextCost)
    local previousPage = State.page
    State.page = page
    State.purchased = purchased
    State.maxTabs = maxTabs
    State.nextCost = nextCost
    State.received = true

    UpdatePageButtons()

    if not (GuildBankFrame and GuildBankFrame:IsShown()) then return end

    if State.page ~= previousPage then
        -- The server sent the page's rights. Its tab list (names, icons) comes with tab 1's
        -- contents, which the client must ASK for: sent unasked, it reads as a vault opening
        -- and closes the frame. Then reselect a tab, which queries its items (or log / text).
        QueryGuildBankTab(1)
        local numTabs = GetNumGuildBankTabs()
        local tab = GetCurrentGuildBankTab()
        local buyTab = IsGuildLeader() and NextTabOnShownPage() and numTabs + 1 or numTabs
        if tab < 1 or tab > buyTab then tab = 1 end
        GuildBankTab_OnClick(_G["GuildBankTab" .. tab], "LeftButton", tab)
    else
        GuildBankFrame_UpdateTabs()
        if GuildBankFrameBuyInfo and GuildBankFrameBuyInfo:IsShown() then
            GuildBankFrame_UpdateTabBuyingInfo()
        end
    end
    ApplySearch()
end

-- SMSG_GUILD_BANK_UPDATE, handed over by ebonhold.dll as hex. Little-endian.
--   kind 1: uint8 page, uint8 purchased, uint8 maxTabs, uint32 nextCost
--   kind 2: uint32 serial, uint16 count, count x (uint8 guild tab 0-15, uint8 slot 0-97)
function GuildBank_OnPacket(hex)
    local bytes, pos = {}, 1
    for i = 1, #hex - 1, 2 do
        bytes[#bytes + 1] = tonumber(hex:sub(i, i + 1), 16)
    end
    local function u8()
        local v = bytes[pos] or 0
        pos = pos + 1
        return v
    end
    local function u16() return u8() + u8() * 256 end
    local function u32() return u16() + u16() * 65536 end

    local kind = u8()
    if kind == 1 then
        local page, purchased, maxTabs = u8(), u8(), u8()
        OnPageInfo(page, purchased, maxTabs, u32())
    elseif kind == 2 then
        local serial, count = u32(), u16()
        if serial ~= Search.serial or Search.text == "" then return end   -- an older query
        Search.matches, Search.counts = {}, {}
        for _ = 1, count do
            local tab, slot = u8(), u8()
            Search.matches[tab] = Search.matches[tab] or {}
            Search.matches[tab][slot + 1] = true
            Search.counts[tab] = (Search.counts[tab] or 0) + 1
        end
        ApplySearch()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_GuildBankUI" then CreatePageButtons() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if IsAddOnLoaded("Blizzard_GuildBankUI") then CreatePageButtons() end
        -- After a /reload the server may still show another page: ask which one.
        if IsInGuild() and GuildBankSetPage then
            GuildBankSetPage(-1)
        end
    end
end)
