-- ==============================================================================
-- Raid loot lockout (2026-10-05): raids have no ID any more. Each character may loot each raid
-- boss once a week, until Tuesday 03:00 UTC. The server pushes the bosses looted this week
-- (SS.SEND_RAID_LOOT_LOCKOUTS, "<encounter>:<seconds left>;...") at login, at every new lock and
-- on RequestRaidInfo().
--
-- Shown in the stock Raid Information window (Social, Raid, Raid Info): the 3.3.5 client can only
-- list one line per raid ID there, so this module replaces the window's list with its own: every
-- open raid with the item level of its Normal gear, highest first, "looted / total", and a click
-- opens its bosses. A raid outside the list still shows once one of its bosses is looted.
-- Boss names and order come from raid_lockout_data.lua (generated from the DBC).
-- ==============================================================================
ProjectEbonhold = ProjectEbonhold or {}
local RL = {}
ProjectEbonhold.RaidLockout = RL

local DATA = {}
for i, raid in ipairs(ProjectEbonhold.RaidLockoutData or {}) do
    DATA[i] = raid
    raid.order = i
end
table.sort(DATA, function(a, b)
    local levelA, levelB = a.ilvl or 0, b.ilvl or 0
    if levelA ~= levelB then return levelA > levelB end
    return a.order < b.order
end)

-- The realm's release, known once the server has answered (raid_finder.lua keeps it).
local function CurrentRelease()
    local finder = ProjectEbonhold.RaidFinder
    return finder and finder.GetRelease and finder.GetRelease() or nil
end

-- [encounter id] = GetTime() at which the lock ends
local locks = {}
-- [map id] = true while the raid's bosses are shown
local expanded = {}

local function SecondsLeft(encounter)
    local ends = locks[encounter]
    if not ends then return nil end
    local left = ends - GetTime()
    if left <= 0 then return nil end
    return left
end

function RL.IsLooted(encounter)
    return SecondsLeft(encounter) ~= nil
end

local function FormatLeft(left)
    if SecondsToTime then
        local ok, text = pcall(SecondsToTime, left, true, nil, 3)
        if ok and text then return text end
    end
    return math.floor(left / 3600) .. " Hours"
end

-- ------------------------------------------------------------------ window content
local ROW_RAID = 20
local ROW_BOSS = 15
local ROW_NOTE = 18
local content, scroll, child, footer, empty, note
local rows = {}

local function BuildContent()
    if content or not RaidInfoFrame then return end

    content = CreateFrame("Frame", "ProjectEbonholdRaidLockoutFrame", RaidInfoFrame)
    content:SetPoint("TOPLEFT", RaidInfoFrame, "TOPLEFT", 16, -58)
    content:SetPoint("BOTTOMRIGHT", RaidInfoFrame, "BOTTOMRIGHT", -16, 36)

    scroll = CreateFrame("ScrollFrame", "ProjectEbonholdRaidLockoutScroll", content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(280)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("TOPLEFT", 4, -8)
    empty:SetPoint("RIGHT", -4, 0)
    empty:SetJustifyH("LEFT")
    empty:SetText("You have not looted any raid boss this week.")

    note = child:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -2)
    note:SetPoint("RIGHT", child, "RIGHT", -2, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Item level of the gear on Normal difficulty.")

    footer = RaidInfoFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    footer:SetPoint("BOTTOMLEFT", RaidInfoFrame, "BOTTOMLEFT", 18, 18)
    footer:SetPoint("RIGHT", RaidInfoCancelButton, "LEFT", -8, 0)
    footer:SetJustifyH("LEFT")
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, child)
    row:SetPoint("LEFT", child, "LEFT", 0, 0)
    row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetJustifyH("LEFT")
    row.state = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.state:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.state:SetJustifyH("RIGHT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", function(self)
        if self.map then
            expanded[self.map] = not expanded[self.map] or nil
            RL.Refresh()
        end
    end)
    rows[i] = row
    return row
end

local function Place(row, height, y, indent)
    row:SetHeight(height)
    row:SetPoint("TOP", child, "TOP", 0, -y)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", indent, 0)
    row.name:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
end

local function SetRaidRow(row, raid, looted, y)
    row.map = raid.map
    Place(row, ROW_RAID, y, 2)
    row.name:SetFontObject(GameFontNormal)
    row.name:SetText((expanded[raid.map] and "- " or "+ ") .. raid.name)
    row.state:SetFontObject(GameFontHighlight)
    local count = looted .. "/" .. #raid.bosses
    row.state:SetText(raid.ilvl and ("|cffffd100ilvl " .. raid.ilvl .. "|r   " .. count) or count)
    row:EnableMouse(true)
    row:Show()
end

local function SetBossRow(row, boss, y)
    row.map = nil
    Place(row, ROW_BOSS, y, 16)
    row.name:SetFontObject(GameFontHighlightSmall)
    row.state:SetFontObject(GameFontHighlightSmall)
    if RL.IsLooted(boss.id) then
        row.name:SetText("|cff808080" .. boss.name .. "|r")
        row.state:SetText("|cffff4040Looted|r")
    else
        row.name:SetText(boss.name)
        row.state:SetText("|cff1eff00Available|r")
    end
    row:EnableMouse(false)
    row:Show()
end

function RL.Refresh()
    BuildContent()
    if not content then return end

    local release = CurrentRelease()
    local n, y, soonest = 0, ROW_NOTE, nil
    for _, raid in ipairs(DATA) do
        local looted = 0
        for _, boss in ipairs(raid.bosses) do
            local left = SecondsLeft(boss.id)
            if left then
                looted = looted + 1
                if not soonest or left < soonest then soonest = left end
            end
        end
        if looted > 0 or (release and raid.release and raid.release <= release) then
            n = n + 1
            SetRaidRow(Row(n), raid, looted, y)
            y = y + ROW_RAID
            if expanded[raid.map] then
                for _, boss in ipairs(raid.bosses) do
                    n = n + 1
                    SetBossRow(Row(n), boss, y)
                    y = y + ROW_BOSS
                end
                y = y + 4
            end
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end

    child:SetHeight(math.max(y, 1))
    if n == 0 then
        empty:Show()
        note:Hide()
    else
        empty:Hide()
        note:Show()
    end

    if soonest then
        footer:SetText("Each boss can be looted once a week. Resets in " .. FormatLeft(soonest) .. ".")
    else
        footer:SetText("Each boss can be looted once a week (Tuesday 03:00 UTC).")
    end
end

-- The stock list only knows raid IDs, which no longer exist: hide it and show ours instead.
local function OnRaidInfoShow()
    for _, name in ipairs({ "RaidInfoScrollFrame", "RaidInfoExtendButton" }) do
        local frame = _G[name]
        if frame then frame:Hide() end
    end
    if RaidInfoInstanceLabel and RaidInfoInstanceLabel.text then RaidInfoInstanceLabel.text:SetText("Raid") end
    if RaidInfoIDLabel and RaidInfoIDLabel.text then RaidInfoIDLabel.text:SetText("Item level, looted") end
    RL.Refresh()
    if RequestRaidInfo then RequestRaidInfo() end
    -- The answer carries the realm's release, which opens the raid list (raid_finder.lua calls Refresh).
    if not CurrentRelease() and ProjectEbonhold.sendToServer and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_RAID_FINDER_DATA then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_RAID_FINDER_DATA, "")
    end
end

-- Raid Info is greyed out when the character has no raid ID, which is now always: keep it usable.
local function EnableRaidInfoButton()
    if RaidFrameRaidInfoButton then RaidFrameRaidInfoButton:Enable() end
end

-- The "not in a raid" page kept the Raid Browser hidden when it carried the Clear IDs button;
-- it now says how raid loot works instead.
local notInRaidDone = false
local function SetUpNotInRaid()
    if notInRaidDone or not RaidFrameNotInRaid then return end
    notInRaidDone = true
    if RaidFrameNotInRaidRaidBrowserButton then RaidFrameNotInRaidRaidBrowserButton:Hide() end
    for i = 1, RaidFrameNotInRaid:GetNumRegions() do
        local region = select(i, RaidFrameNotInRaid:GetRegions())
        if region and region:GetObjectType() == "FontString" then
            local text = region:GetText()
            if text and text:match("Find a Raid") then region:Hide() end
        end
    end
    local note = RaidFrameNotInRaid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("CENTER", RaidFrameNotInRaid, "CENTER", -15, -80)
    note:SetWidth(320)
    note:SetJustifyH("CENTER")
    note:SetText("|cffFFCC00Raids have no ID: join any group, any time.\nEach boss can be looted once a week.\nRaid Info lists the bosses you looted.|r")
end

if RaidInfoFrame then
    RaidInfoFrame:HookScript("OnShow", OnRaidInfoShow)
end
if RaidFrame then
    RaidFrame:HookScript("OnShow", EnableRaidInfoButton)
    RaidFrame:HookScript("OnShow", SetUpNotInRaid)
    RaidFrame:HookScript("OnEvent", EnableRaidInfoButton)
end

-- ------------------------------------------------------------------ server
if ProjectEbonhold.onEventReceived and ProjectEbonhold.SS and ProjectEbonhold.SS.SEND_RAID_LOOT_LOCKOUTS then
    ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_RAID_LOOT_LOCKOUTS, function(body)
        wipe(locks)
        local now = GetTime()
        for encounter, secs in string.gmatch(body or "", "(%d+):(%d+)") do
            locks[tonumber(encounter)] = now + tonumber(secs)
        end
        if RaidInfoFrame and RaidInfoFrame:IsShown() then RL.Refresh() end
    end)
end
