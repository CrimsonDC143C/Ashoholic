-- quest_tracker.lua -- Dragonflight-style Objective Tracker, retroported to 3.3.5.
--
-- Replaces the default WatchFrame quest/achievement display with the retail
-- Dragonflight look: gold "Objectives" header with collapse chevron, per-module
-- sub-headers, hoverable quest blocks (gold titles, dashed grey objective
-- lines, green "Ready for turn-in"), quest item buttons, and a per-quest
-- waypoint pin button that super-tracks the quest -- the in-world pin with
-- outside-the-POV screen clamping lives in super_tracker.lua.
--
-- The Blizzard WatchFrame is neutered (events unregistered, WatchFrame_Update
-- no-oped, chrome hidden) but stays SHOWN: it is still the position anchor
-- that playerRun pins every frame, and the objectives-module reward icon is
-- parented to it.

local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
local QT = {}
ProjectEbonhold.QuestTracker = QT

-- -------------------------------------------------------------- tunables ----
local WIDTH          = 235
local MAX_HEIGHT     = 560       -- stop adding blocks past this
local BLOCK_SPACING  = 8
local LINE_SPACING   = 2
local PIN_SIZE       = 17
local ITEM_SIZE      = 26
local MAX_ACH_LINES  = 4

local FONT           = "Fonts\\FRIZQT__.TTF"
local ASSETS         = "Interface\\AddOns\\ProjectEbonhold\\assets\\"

local C_HEADER       = { 1.00, 0.82, 0.00 }
local C_MODULE       = { 0.75, 0.61, 0.00 }
local C_TITLE        = { 1.00, 0.82, 0.00 }
local C_TITLE_HOVER  = { 1.00, 1.00, 0.50 }
local C_TITLE_SUPER  = { 1.00, 0.95, 0.55 }   -- super-tracked block title
local C_LINE         = { 0.86, 0.86, 0.86 }
local C_LINE_DONE    = { 0.50, 0.50, 0.50 }
local C_COMPLETE     = { 0.40, 0.85, 0.40 }
local C_FAILED       = { 1.00, 0.30, 0.30 }

-- ----------------------------------------------------------------- state ----
local tracker                       -- root frame
local blocks = {}                   -- reusable block frames
local itemButtons = {}              -- secure quest item buttons, by block index
local dirty = true
local sinceRender = 0
local pendingSecure = false         -- item-button work deferred past combat

local function DB()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.questTracker = ProjectEbonholdDB.questTracker or {}
    return ProjectEbonholdDB.questTracker
end

function QT.MarkDirty() dirty = true end

-- Options toggle ("Quest Tracker" section of the options panel). Enabling
-- applies live; disabling hides this tracker but the stock WatchFrame stays
-- neutered until /reload (the options panel prompts for it).
local function IsEnabled()
    local svc = _G.ProjectEbonholdOptionsService
    if svc and svc.GetSetting then
        local v = svc:GetSetting("dfQuestTracker")
        if v ~= nil then return v and true or false end
    end
    return true
end
QT.IsEnabled = IsEnabled

StaticPopupDialogs["EBONHOLD_QT_RELOAD"] = {
    text = "Restoring the default quest tracker requires a UI reload.",
    button1 = "Reload Now",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ------------------------------------------------- neuter the WatchFrame ----
local function DisableWatchFrame()
    if not WatchFrame then return end
    WatchFrame:UnregisterAllEvents()
    WatchFrame_Update = function() end
    for _, name in ipairs({ "WatchFrameTitle", "WatchFrameHeader",
                            "WatchFrameCollapseExpandButton", "WatchFrameLines" }) do
        local f = _G[name]
        if f and f.Hide then f:Hide() end
        if f and f.SetParent then
            -- keep them hidden even if some Blizzard path re-Shows them
            local hidden = _G["EbonholdQTHidden"] or CreateFrame("Frame", "EbonholdQTHidden")
            hidden:Hide()
            f:SetParent(hidden)
        end
    end
end

-- ------------------------------------------------------------ root frame ----
local function CreateTracker()
    if tracker then return tracker end

    tracker = CreateFrame("Frame", "EbonholdQuestTracker", UIParent)
    tracker:SetWidth(WIDTH)
    tracker:SetHeight(30)
    -- WatchFrame keeps its addon-managed position (playerRun pins it); ride it.
    tracker:SetPoint("TOPRIGHT", WatchFrame or UIParent, "TOPRIGHT", 0, 0)

    -- ---- main header: "Objectives" + gradient underline + collapse chevron
    local header = CreateFrame("Frame", nil, tracker)
    header:SetHeight(22)
    header:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, 0)
    tracker.header = header

    local headerText = header:CreateFontString(nil, "OVERLAY")
    headerText:SetFont(FONT, 16)
    headerText:SetShadowOffset(1, -1)
    headerText:SetShadowColor(0, 0, 0, 1)
    headerText:SetPoint("LEFT", header, "LEFT", 2, 0)
    headerText:SetTextColor(unpack(C_HEADER))
    headerText:SetText("Objectives")
    tracker.headerText = headerText

    local underline = header:CreateTexture(nil, "ARTWORK")
    underline:SetTexture("Interface\\Buttons\\WHITE8X8")
    underline:SetHeight(1)
    underline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -20, 0)
    underline:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.55, 1, 0.82, 0, 0)

    local collapse = CreateFrame("Button", nil, header)
    collapse:SetSize(16, 16)
    collapse:SetPoint("RIGHT", header, "RIGHT", -2, -1)
    collapse.tex = collapse:CreateTexture(nil, "ARTWORK")
    collapse.tex:SetTexture("Interface\\Buttons\\UI-Panel-QuestHideButton")
    collapse.tex:SetAllPoints(collapse)
    collapse:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    tracker.collapse = collapse

    local function UpdateChevron()
        if DB().collapsed then
            collapse.tex:SetTexCoord(0, 0.5, 0.5, 1)     -- "+" (expand)
        else
            collapse.tex:SetTexCoord(0, 0.5, 0, 0.5)     -- "-" (collapse)
        end
    end
    collapse:SetScript("OnClick", function()
        DB().collapsed = not DB().collapsed
        UpdateChevron()
        QT.MarkDirty()
    end)
    tracker.UpdateChevron = UpdateChevron

    -- ---- module sub-headers ("Quests" / "Achievements"), created on demand
    tracker.moduleHeaders = {}
    tracker.GetModuleHeader = function(i)
        local mh = tracker.moduleHeaders[i]
        if not mh then
            mh = CreateFrame("Frame", nil, tracker)
            mh:SetHeight(16)
            mh:SetWidth(WIDTH)
            mh.bg = mh:CreateTexture(nil, "BACKGROUND")
            mh.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            mh.bg:SetAllPoints(mh)
            mh.bg:SetGradientAlpha("HORIZONTAL", 0.30, 0.24, 0, 0.45, 0.30, 0.24, 0, 0)
            mh.text = mh:CreateFontString(nil, "OVERLAY")
            mh.text:SetFont(FONT, 13)
            mh.text:SetShadowOffset(1, -1)
            mh.text:SetShadowColor(0, 0, 0, 1)
            mh.text:SetPoint("LEFT", mh, "LEFT", 4, 0)
            mh.text:SetTextColor(unpack(C_MODULE))
            tracker.moduleHeaders[i] = mh
        end
        return mh
    end

    return tracker
end

-- ----------------------------------------------------------- quest blocks ---
local function OnBlockEnter(self)
    self.title:SetTextColor(unpack(C_TITLE_HOVER))
end
local function OnBlockLeave(self)
    if self.isSuper then
        self.title:SetTextColor(unpack(C_TITLE_SUPER))
    else
        self.title:SetTextColor(unpack(C_TITLE))
    end
end

local function OnBlockMouseUp(self, button)
    if button ~= "LeftButton" then return end
    if self.kind == "quest" then
        if IsShiftKeyDown() then
            if self.questIndex then RemoveQuestWatch(self.questIndex) end
            QT.MarkDirty()
        elseif self.questIndex then
            if QuestLog_OpenToQuest then
                QuestLog_OpenToQuest(self.questIndex)
            else
                QuestLog_SetSelection(self.questIndex)
                ShowUIPanel(QuestLogFrame)
            end
        end
    elseif self.kind == "achievement" then
        if IsShiftKeyDown() then
            if RemoveTrackedAchievement and self.achievementID then
                RemoveTrackedAchievement(self.achievementID)
            end
            QT.MarkDirty()
        elseif self.achievementID then
            if not AchievementFrame then pcall(LoadAddOn, "Blizzard_AchievementUI") end
            if AchievementFrame_LoadUI then pcall(AchievementFrame_LoadUI) end
            if AchievementFrame and AchievementFrame_SelectAchievement then
                if not AchievementFrame:IsShown() then ShowUIPanel(AchievementFrame) end
                pcall(AchievementFrame_SelectAchievement, self.achievementID)
            end
        end
    end
end

local function OnPinClick(self)
    local ST = ProjectEbonhold.SuperTracker
    if not ST then return end
    local block = self:GetParent()
    -- toggle against the EFFECTIVE tracked quest (manual or auto): clicking
    -- the tracked one turns the waypoint off entirely -- SetQuest(nil) would
    -- fall back to auto-nearest and instantly re-pick the same quest
    if ST.GetQuest() == block.questID then
        ST.Disable()
    else
        ST.SetQuest(block.questID)
    end
    QT.MarkDirty()
end

local function OnPinEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local ST = ProjectEbonhold.SuperTracker
    local block = self:GetParent()
    if ST and ST.GetQuest() == block.questID then
        GameTooltip:AddLine("Stop tracking this waypoint", 1, 0.82, 0)
    else
        GameTooltip:AddLine("Track waypoint on screen", 1, 0.82, 0)
    end
    if ST and block.questID and not ST.HasPOI(block.questID) then
        GameTooltip:AddLine("No location data in this zone", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

local function GetBlock(i)
    local block = blocks[i]
    if not block then
        block = CreateFrame("Frame", nil, tracker)
        block:SetWidth(WIDTH)
        block:EnableMouse(true)
        block:SetScript("OnEnter", OnBlockEnter)
        block:SetScript("OnLeave", OnBlockLeave)
        block:SetScript("OnMouseUp", OnBlockMouseUp)

        -- waypoint pin button (quests only)
        local pin = CreateFrame("Button", nil, block)
        pin:SetSize(PIN_SIZE, PIN_SIZE)
        pin:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -1)
        pin.plate = pin:CreateTexture(nil, "BACKGROUND")
        pin.plate:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        pin.plate:SetAllPoints(pin)
        pin.plate:SetVertexColor(0, 0, 0, 0.7)
        pin.ring = pin:CreateTexture(nil, "BORDER")
        pin.ring:SetTexture(ASSETS .. "roundborder")
        pin.ring:SetSize(PIN_SIZE + 13, PIN_SIZE + 13)
        pin.ring:SetPoint("CENTER")
        pin.icon = pin:CreateTexture(nil, "ARTWORK")
        pin.icon:SetSize(11, 11)
        pin.icon:SetPoint("CENTER")
        pin:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomInButton-Highlight", "ADD")
        pin:SetScript("OnClick", OnPinClick)
        pin:SetScript("OnEnter", OnPinEnter)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        block.pin = pin

        local title = block:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 13)
        title:SetShadowOffset(1, -1)
        title:SetShadowColor(0, 0, 0, 1)
        title:SetJustifyH("LEFT")
        title:SetPoint("TOPLEFT", block, "TOPLEFT", PIN_SIZE + 5, 0)
        title:SetWidth(WIDTH - PIN_SIZE - 5)
        title:SetHeight(0)
        block.title = title

        -- super-track emphasis: gold wash over the whole block + left accent
        -- bar, shown while this block's quest drives the on-screen waypoint
        local superBg = block:CreateTexture(nil, "BACKGROUND")
        superBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        superBg:SetPoint("TOPLEFT", block, "TOPLEFT", -4, 3)
        superBg:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", 2, -3)
        superBg:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.22, 1, 0.82, 0, 0)
        superBg:Hide()
        block.superBg = superBg

        local superBar = block:CreateTexture(nil, "BORDER")
        superBar:SetTexture("Interface\\Buttons\\WHITE8X8")
        superBar:SetWidth(2)
        superBar:SetPoint("TOPLEFT", superBg, "TOPLEFT", 0, 0)
        superBar:SetPoint("BOTTOMLEFT", superBg, "BOTTOMLEFT", 0, 0)
        superBar:SetVertexColor(1, 0.82, 0, 0.9)
        superBar:Hide()
        block.superBar = superBar

        block.lines = {}
        blocks[i] = block
    end
    return block
end

local function GetLine(block, j)
    local line = block.lines[j]
    if not line then
        line = block:CreateFontString(nil, "OVERLAY")
        line:SetFont(FONT, 12)
        line:SetShadowOffset(1, -1)
        line:SetShadowColor(0, 0, 0, 1)
        line:SetJustifyH("LEFT")
        line:SetWidth(WIDTH - PIN_SIZE - 15)
        line:SetHeight(0)
        block.lines[j] = line
    end
    return line
end

-- --------------------------------------------------- secure item buttons ----
local function GetItemButton(i)
    local btn = itemButtons[i]
    if not btn then
        btn = CreateFrame("Button", "EbonholdQTItem" .. i, tracker, "SecureActionButtonTemplate")
        btn:SetSize(ITEM_SIZE, ITEM_SIZE)
        btn:SetAttribute("type", "item")
        btn:RegisterForClicks("AnyUp")
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints(btn)
        btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        btn.border = btn:CreateTexture(nil, "OVERLAY")
        btn.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        btn.border:SetPoint("TOPLEFT", btn, "TOPLEFT", -12, 12)
        btn.border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 12, -12)
        btn.count = btn:CreateFontString(nil, "OVERLAY")
        btn.count:SetFont(FONT, 11, "OUTLINE")
        btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        btn.cooldown:SetAllPoints(btn)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        btn:Hide()
        itemButtons[i] = btn
    end
    return btn
end

local function UpdateItemCooldowns()
    for _, btn in pairs(itemButtons) do
        if btn:IsShown() and btn.questIndex then
            local start, duration, enable = GetQuestLogSpecialItemCooldown(btn.questIndex)
            if start then
                CooldownFrame_SetTimer(btn.cooldown, start, duration, enable)
            end
        end
    end
end

-- ------------------------------------------------- addon-side watch list ----
-- The Ebonhold client evicts the previous watch whenever a new one is added
-- (an effective 1-quest cap in the C implementation, unlike stock 3.3.5's
-- 10) -- so players could only ever track one quest. The tracker therefore
-- keeps its OWN watched set, keyed by questID and persisted per character;
-- the client's AddQuestWatch/RemoveQuestWatch calls (quest log shift-click,
-- auto-watch) are treated as add/remove EVENTS feeding this set, never as
-- the source of truth.
local function WatchedDB()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.questTracker = ProjectEbonholdDB.questTracker or {}
    local qt = ProjectEbonholdDB.questTracker
    qt.watchedQuests = qt.watchedQuests or {}
    return qt.watchedQuests
end

-- ---------------------------------------------------------------- render ----
local function CollectQuests()
    local out = {}
    local watched = WatchedDB()

    -- Merge the CLIENT's watch list in on every render: the Ebonhold client
    -- adds newly ACCEPTED quests to its own list internally (C-side, so the
    -- AddQuestWatch Lua hook never fires for them). Its list only ever holds
    -- the latest entry (eviction cap), but sampling it here turns it into a
    -- continuous feed -- an accepted quest shows up on the very next render
    -- (QUEST_LOG_UPDATE fires on accept) instead of after the next reload.
    for i = 1, GetNumQuestWatches() do
        local watchIndex = GetQuestIndexForWatch(i)
        if watchIndex then
            local _, _, _, _, _, _, _, _, watchQuestID = GetQuestLogTitle(watchIndex)
            if watchQuestID and watchQuestID > 0 then watched[watchQuestID] = true end
        end
    end

    local seen = {}
    for questIndex = 1, GetNumQuestLogEntries() do
        local title, _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(questIndex)
        if title and not isHeader and questID and watched[questID] then
            seen[questID] = true
            do
                local objectives = {}
                if isComplete and isComplete > 0 then
                    table.insert(objectives, { text = "Ready for turn-in", color = C_COMPLETE })
                elseif isComplete and isComplete < 0 then
                    table.insert(objectives, { text = "Failed", color = C_FAILED })
                else
                    for j = 1, GetNumQuestLeaderBoards(questIndex) do
                        local text, _, finished = GetQuestLogLeaderBoard(j, questIndex)
                        if text then
                            table.insert(objectives, {
                                text  = "- " .. text,
                                color = finished and C_LINE_DONE or C_LINE,
                            })
                        end
                    end
                    if #objectives == 0 then
                        table.insert(objectives, { text = "- In progress", color = C_LINE })
                    end
                end
                table.insert(out, {
                    kind = "quest", title = title, questIndex = questIndex,
                    questID = questID, objectives = objectives,
                })
            end
        end
    end
    -- Prune entries whose quest left the log (abandoned / turned in). Only
    -- once the log is REALLY loaded: right after login it can be empty or
    -- hold header/placeholder entries without questIDs yet -- pruning then
    -- wiped the whole persisted set, and the tracker stayed empty until the
    -- player re-tracked by hand. "Loaded" = at least one non-header entry
    -- resolving to a real questID.
    local logLoaded = false
    for questIndex = 1, GetNumQuestLogEntries() do
        local _, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(questIndex)
        if not isHeader and questID and questID > 0 then
            logLoaded = true
            break
        end
    end
    if logLoaded then
        for questID in pairs(watched) do
            if not seen[questID] then watched[questID] = nil end
        end
    end
    return out
end

local function CollectAchievements()
    local out = {}
    if not GetTrackedAchievements then return out end
    for _, achID in ipairs({ GetTrackedAchievements() }) do
        local ok, _, name, _, completed = pcall(GetAchievementInfo, achID)
        if ok and name and not completed then
            local objectives, shown, total = {}, 0, 0
            local num = GetAchievementNumCriteria and GetAchievementNumCriteria(achID) or 0
            for j = 1, num do
                local cOk, cText, _, cDone, qty, req = pcall(GetAchievementCriteriaInfo, achID, j)
                if cOk and cText and not cDone then
                    total = total + 1
                    if shown < MAX_ACH_LINES then
                        shown = shown + 1
                        local text = cText
                        if req and req > 1 then
                            text = string.format("%s: %d/%d", cText, qty or 0, req)
                        end
                        table.insert(objectives, { text = "- " .. text, color = C_LINE })
                    end
                end
            end
            if total > shown then
                table.insert(objectives, {
                    text = string.format("- ... and %d more", total - shown), color = C_LINE_DONE,
                })
            end
            if #objectives == 0 then
                table.insert(objectives, { text = "- In progress", color = C_LINE })
            end
            table.insert(out, {
                kind = "achievement", title = name, achievementID = achID,
                objectives = objectives,
            })
        end
    end
    return out
end

local function Render()
    if not IsEnabled() then
        if tracker then tracker:Hide() end
        return
    end
    CreateTracker()
    if not tracker:IsShown() then tracker:Show() end

    local db = DB()
    local quests = CollectQuests()
    local achievements = CollectAchievements()
    local ST = ProjectEbonhold.SuperTracker
    local canSecure = not InCombatLockdown()
    if not canSecure then pendingSecure = true end

    -- re-anchor the objectives-module reward icon (parented to WatchFrame,
    -- originally anchored to WatchFrame's TOPLEFT which we now overlap)
    local ebIcon = _G["ObjectiveTrackerFrame"]
    if ebIcon and not ebIcon.__qtAnchored then
        ebIcon.__qtAnchored = true
        ebIcon:ClearAllPoints()
        ebIcon:SetPoint("RIGHT", tracker, "TOPLEFT", -4, -10)
    end

    tracker.UpdateChevron()

    local total = #quests + #achievements
    if total == 0 then
        tracker.headerText:SetText("Objectives")
        for _, b in pairs(blocks) do b:Hide() end
        for _, m in pairs(tracker.moduleHeaders) do m:Hide() end
        if canSecure then for _, ib in pairs(itemButtons) do ib:Hide() end end
        tracker:SetHeight(tracker.header:GetHeight())
        tracker.header:Hide()                    -- nothing tracked: fully hidden
        return
    end
    tracker.header:Show()

    if db.collapsed then
        tracker.headerText:SetText(string.format("Objectives (%d)", total))
        for _, b in pairs(blocks) do b:Hide() end
        for _, m in pairs(tracker.moduleHeaders) do m:Hide() end
        if canSecure then for _, ib in pairs(itemButtons) do ib:Hide() end end
        tracker:SetHeight(tracker.header:GetHeight())
        return
    end
    tracker.headerText:SetText("Objectives")

    local yOff = -(tracker.header:GetHeight() + 4)
    local blockIdx, moduleIdx = 0, 0
    local overflow = 0

    local function LayoutModule(headerLabel, entries)
        if #entries == 0 then return end
        moduleIdx = moduleIdx + 1
        local mh = tracker.GetModuleHeader(moduleIdx)
        mh.text:SetText(headerLabel)
        mh:ClearAllPoints()
        mh:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, yOff)
        mh:Show()
        yOff = yOff - mh:GetHeight() - 4

        for _, entry in ipairs(entries) do
            if -yOff > MAX_HEIGHT then
                overflow = overflow + 1
            else
                blockIdx = blockIdx + 1
                local block = GetBlock(blockIdx)
                block.kind = entry.kind
                block.questIndex = entry.questIndex
                block.questID = entry.questID
                block.achievementID = entry.achievementID

                block.title:SetText(entry.title)
                block.title:SetTextColor(unpack(C_TITLE))
                local h = block.title:GetStringHeight() or 13

                -- waypoint pin: quests only; gold ring when super-tracked
                if entry.kind == "quest" then
                    block.pin:Show()
                    local isSuper = ST and ST.GetQuest() == entry.questID
                    local isManual = ST and ST.GetManualQuest() == entry.questID
                    block.isSuper = (isSuper or isManual) and true or false
                    if entry.objectives[1] and entry.objectives[1].color == C_COMPLETE then
                        block.pin.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
                    else
                        block.pin.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
                    end
                    if isManual then
                        block.pin.ring:SetVertexColor(0.95, 0.78, 0.25, 1)
                    elseif isSuper then
                        block.pin.ring:SetVertexColor(0.80, 0.66, 0.25, 0.8)
                    else
                        block.pin.ring:SetVertexColor(0.35, 0.35, 0.35, 0.8)
                    end
                else
                    block.isSuper = false
                    block.pin:Hide()
                end

                -- tracked quest stands out: gold wash + accent + brighter title
                if block.isSuper then
                    block.superBg:Show()
                    block.superBar:Show()
                    block.title:SetTextColor(unpack(C_TITLE_SUPER))
                else
                    block.superBg:Hide()
                    block.superBar:Hide()
                end

                for j, obj in ipairs(entry.objectives) do
                    local line = GetLine(block, j)
                    line:SetText(obj.text)
                    line:SetTextColor(unpack(obj.color))
                    line:ClearAllPoints()
                    line:SetPoint("TOPLEFT", block, "TOPLEFT", PIN_SIZE + 10, -(h + LINE_SPACING))
                    line:Show()
                    h = h + LINE_SPACING + (line:GetStringHeight() or 12)
                end
                for j = #entry.objectives + 1, #block.lines do
                    block.lines[j]:Hide()
                end

                block:SetHeight(h + 2)
                block:ClearAllPoints()
                block:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, yOff)
                block:Show()

                -- quest item button, left of the block (secure: skip in combat)
                if canSecure then
                    local btn = GetItemButton(blockIdx)
                    local link, item
                    if entry.kind == "quest" and GetQuestLogSpecialItemInfo then
                        link, item = GetQuestLogSpecialItemInfo(entry.questIndex)
                    end
                    if link then
                        btn.questIndex = entry.questIndex
                        btn:SetAttribute("item", link)
                        btn.icon:SetTexture(item)
                        local _, _, charges = GetQuestLogSpecialItemInfo(entry.questIndex)
                        btn.count:SetText((charges and charges > 1) and charges or "")
                        btn:ClearAllPoints()
                        btn:SetPoint("TOPRIGHT", block, "TOPLEFT", -6, -1)
                        btn:Show()
                    else
                        btn.questIndex = nil
                        btn:Hide()
                    end
                end

                yOff = yOff - block:GetHeight() - BLOCK_SPACING
            end
        end
        yOff = yOff - 2
    end

    LayoutModule("Quests", quests)
    LayoutModule("Achievements", achievements)

    for i = blockIdx + 1, #blocks do blocks[i]:Hide() end
    for i = moduleIdx + 1, #tracker.moduleHeaders do tracker.moduleHeaders[i]:Hide() end
    if canSecure then
        for i = blockIdx + 1, #itemButtons do
            if itemButtons[i] then itemButtons[i].questIndex = nil; itemButtons[i]:Hide() end
        end
    end

    if overflow > 0 then
        blockIdx = blockIdx + 1
        local block = GetBlock(blockIdx)
        block.kind = nil
        block.isSuper = false
        block.pin:Hide()
        block.superBg:Hide()
        block.superBar:Hide()
        block.title:SetText(string.format("+ %d more objectives", overflow))
        block.title:SetTextColor(unpack(C_LINE_DONE))
        for _, l in ipairs(block.lines) do l:Hide() end
        block:SetHeight(14)
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, yOff)
        block:Show()
        yOff = yOff - 16
    end

    tracker:SetHeight(-yOff)
    UpdateItemCooldowns()
end

-- ---------------------------------------------------------------- events ----
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_WATCH_UPDATE")
ev:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
ev:RegisterEvent("TRACKED_ACHIEVEMENT_UPDATE")
ev:RegisterEvent("ACHIEVEMENT_EARNED")
ev:RegisterEvent("CRITERIA_UPDATE")
ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(self, event)
    if event == "BAG_UPDATE_COOLDOWN" then
        UpdateItemCooldowns()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        QT.ApplyEnabled()                        -- saved vars are available here
        -- Render NOW, not on the coalescing timer: after a /reload the quest
        -- log is already client-cached, so the tracker can be visible the
        -- same frame the world appears. (At a fresh login the log data
        -- arrives from the server a moment later -- QUEST_LOG_UPDATE
        -- triggers the fill-in then; that delay is server-side. Seeding from
        -- the client's own watch list happens inside CollectQuests, which
        -- merges it on every render.)
        dirty = false
        Render()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and not pendingSecure then return end
    if event == "PLAYER_REGEN_ENABLED" then pendingSecure = false end
    dirty = true
end)

-- watch-list changes have no dedicated event in 3.3.5; hook the C functions.
-- These feed the addon-side watched set (see WatchedDB): the client's own
-- list evicts on every add, so it is only used as a click-event source.
if hooksecurefunc then
    hooksecurefunc("AddQuestWatch", function(questIndex)
        dirty = true
        local _, _, _, _, _, _, _, _, questID = GetQuestLogTitle(questIndex or 0)
        if questID and questID > 0 then
            WatchedDB()[questID] = true
            -- Dragonflight behavior: freshly tracked quest becomes the waypoint
            local ST = ProjectEbonhold.SuperTracker
            if ST then ST.SetQuest(questID) end
        end
    end)
    hooksecurefunc("RemoveQuestWatch", function(questIndex)
        dirty = true
        local _, _, _, _, _, _, _, _, questID = GetQuestLogTitle(questIndex or 0)
        if questID and questID > 0 then
            WatchedDB()[questID] = nil
            local ST = ProjectEbonhold.SuperTracker
            if ST and ST.GetManualQuest() == questID then ST.SetQuest(nil) end
        end
    end)
end

-- Quest-log shift-click: a DETERMINISTIC track/untrack toggle against the
-- addon-side set. The stock handler toggles against the client's 1-slot
-- watch list, which (with quests auto-tracked on accept) made "I want to
-- track this" clicks silently UNTRACK-or-mistoggle depending on hidden
-- client state. Now: in our set -> untrack (leaves the objectives bar);
-- not in it -> track (appears). The stock Add/RemoveQuestWatch are still
-- called for client-state sync and for our own hooks (supertrack pin).
if QuestLogTitleButton_OnClick then
    local origQuestLogTitleButton_OnClick = QuestLogTitleButton_OnClick
    function QuestLogTitleButton_OnClick(self, button)
        local chatLinking = IsModifiedClick and IsModifiedClick("CHATLINK")
            and ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if IsShiftKeyDown() and not chatLinking and button == "LeftButton" then
            -- 3.3.5 quest-log buttons carry the ABSOLUTE log index in their id
            local questIndex = self:GetID()
            local title, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(questIndex)
            if title and not isHeader and questID and questID > 0 then
                if WatchedDB()[questID] then
                    WatchedDB()[questID] = nil
                    RemoveQuestWatch(questIndex)  -- client sync (may be a no-op)
                else
                    WatchedDB()[questID] = true
                    AddQuestWatch(questIndex)     -- client sync + supertrack hook
                end
                if QuestLog_Update then QuestLog_Update() end -- refresh check marks
                QT.MarkDirty()
                return
            end
        end
        return origQuestLogTitleButton_OnClick(self, button)
    end
end

-- The quest log's little check marks reflect the CLIENT's watch list (max 1
-- entry), which made tracked state unreadable -- show them from the
-- addon-side set instead, so what has a check is exactly what sits in the
-- objectives bar.
if QuestLog_Update and hooksecurefunc then
    hooksecurefunc("QuestLog_Update", function()
        local watched = WatchedDB()
        for i = 1, (QUESTS_DISPLAYED or 25) do
            local btn = _G["QuestLogTitle" .. i]
            local check = _G["QuestLogTitle" .. i .. "Check"]
            if btn and check and btn:IsShown() then
                local questIndex = btn:GetID()
                local _, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(questIndex)
                if not isHeader and questID and questID > 0 then
                    if watched[questID] then check:Show() else check:Hide() end
                end
            end
        end
    end)
end

-- coalesced re-render (CRITERIA_UPDATE and QUEST_LOG_UPDATE fire in bursts)
ev:SetScript("OnUpdate", function(self, dt)
    sinceRender = sinceRender + (dt or 0)
    if dirty and sinceRender >= 0.1 then
        sinceRender = 0
        dirty = false
        Render()
    end
end)

-- super-track selection changes re-color the pin buttons
local function HookSuperTracker()
    if ProjectEbonhold.SuperTracker then
        ProjectEbonhold.SuperTracker.RegisterChanged(QT.MarkDirty)
    end
end
HookSuperTracker()

-- Apply the enabled/disabled state. Called at PLAYER_ENTERING_WORLD (saved
-- variables loaded) and live from the options checkbox. NOT called at file
-- load: the setting isn't readable yet, and neutering the WatchFrame must
-- only happen when the feature is actually on.
function QT.ApplyEnabled()
    if IsEnabled() then
        DisableWatchFrame()                      -- idempotent
        dirty = true
    else
        if tracker then tracker:Hide() end
        -- stock WatchFrame stays neutered until /reload if it was disabled
        -- mid-session; the options panel shows the reload prompt.
    end
end

QT.GetFrame = function() return tracker end
