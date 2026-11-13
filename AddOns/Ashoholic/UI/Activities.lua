-- Live Call Board observations, grouped by account like the preview.
-- Account-wide quests appear once per account; character quests stay separate.
local addonName = ...
local UI = _G[addonName].UI
local Style = UI.Style
local GAP = 20
local ROW_HEIGHT = 52

local function CollectActivities(account)
    local shared, characterRows = {}, {}
    local latest, missing = nil, 0
    for _, character in ipairs(account.characters) do
        local snapshot = character.activities
        if not snapshot then
            missing = missing + 1
        else
            if not latest or snapshot.updatedAt > latest.updatedAt then latest = snapshot end
            for questId, quest in pairs(snapshot.quests) do
                local entry = { quest = quest, snapshot = snapshot, name = character.name, id = questId }
                if quest.accountWide then
                    if not shared[questId] or snapshot.updatedAt > shared[questId].snapshot.updatedAt then
                        shared[questId] = entry
                    end
                else
                    characterRows[#characterRows + 1] = entry
                end
            end
        end
    end
    for _, entry in pairs(shared) do
        entry.name = "Account"
        characterRows[#characterRows + 1] = entry
    end
    local daily, weekly = {}, {}
    for _, entry in ipairs(characterRows) do
        local rows = entry.quest.cadence == "daily" and daily or weekly
        rows[#rows + 1] = entry
    end
    local function Sort(left, right)
        if left.quest.cadence ~= right.quest.cadence then
            return left.quest.cadence < right.quest.cadence
        end
        if left.name ~= right.name then return left.name < right.name end
        if left.quest.title ~= right.quest.title then return left.quest.title < right.quest.title end
        return left.id < right.id
    end
    table.sort(daily, Sort)
    table.sort(weekly, Sort)
    return latest, missing, daily, weekly
end

local function TimeLeft(resetAt)
    local seconds = resetAt - time()
    if seconds <= 0 then return "Reset; refresh needed" end
    if seconds >= 86400 then return math.floor(seconds / 86400) .. "d " .. math.floor((seconds % 86400) / 3600) .. "h" end
    if seconds >= 3600 then return math.floor(seconds / 3600) .. "h " .. math.floor((seconds % 3600) / 60) .. "m" end
    return math.max(1, math.floor(seconds / 60)) .. "m"
end

local function Status(entry)
    local quest, snapshot = entry.quest, entry.snapshot
    local resetAt = quest.cadence == "daily" and snapshot.dailyResetAt
        or (quest.cadence == "weekly" and snapshot.weeklyResetAt or nil)
    if resetAt and time() >= resetAt then
        return "Reset - open Call Board", Style.muted
    end
    if quest.state == 2 then return "Ready to claim", Style.teal end
    if quest.state == 3 then return "Exhausted", Style.muted end
    if quest.state == 1 then return quest.done .. " / " .. quest.max .. " in progress", Style.text end
    return "Available", Style.text
end

local function RewardText(rewards)
    if not rewards then return "Rewards unknown" end
    local parts = {}
    if rewards.ash and rewards.ash > 0 then parts[#parts + 1] = UI.FormatNumber(rewards.ash) .. " Ash" end
    if rewards.shards and rewards.shards > 0 then parts[#parts + 1] = UI.FormatNumber(rewards.shards) .. " Shards" end
    if rewards.copper and rewards.copper > 0 then parts[#parts + 1] = UI.FormatCopper(rewards.copper) end
    if rewards.artisan and rewards.artisan > 0 then parts[#parts + 1] = UI.FormatNumber(rewards.artisan) .. " Artisan" end
    if rewards.orbs and rewards.orbs > 0 then parts[#parts + 1] = UI.FormatNumber(rewards.orbs) .. " Orbs" end
    return #parts > 0 and table.concat(parts, " / ") or "No listed currency rewards"
end

local function CreatePanel(parent, width)
    local panel = UI.CreateSurface(parent, width, 1)
    panel.title = UI.AddLabel(panel, "", 16, -12, width - 32, 22, 14, Style.gold)
    panel.cache = UI.AddLabel(panel, "", 16, -40, width - 32, 20, 12, Style.teal)
    panel.source = UI.AddLabel(panel, "", 16, -63, width - 32, 18, 10, Style.muted)
    panel.dailyHeading = UI.AddLabel(panel, "", 16, -95, width - 32, 18, 10, Style.gold)
    panel.weeklyHeading = UI.AddLabel(panel, "", 16, -95, width - 32, 18, 10, Style.gold)
    panel.rows = {}
    return panel
end

local function CreateRow(panel)
    local row = CreateFrame("Frame", nil, panel)
    row.title = UI.AddLabel(row, "", 0, 0, 100, 19, 11, Style.text)
    row.status = UI.AddLabel(row, "", 0, 0, 100, 19, 10, Style.teal)
    row.status:SetJustifyH("RIGHT")
    row.note = UI.AddLabel(row, "", 0, -22, 100, 17, 10, Style.muted)
    if row.title.SetWordWrap then row.title:SetWordWrap(false); row.note:SetWordWrap(false) end
    UI.AttachTooltip(row)
    return row
end

local function DrawRows(panel, entries, x, top, width, rowIndex)
    for index, entry in ipairs(entries) do
        rowIndex = rowIndex + 1
        local row = panel.rows[rowIndex]
        if not row then row = CreateRow(panel); panel.rows[rowIndex] = row end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", x, -(top + (index - 1) * ROW_HEIGHT))
        row:SetSize(width, ROW_HEIGHT)
        row.title:SetWidth(width * 0.60)
        row.status:ClearAllPoints()
        row.status:SetPoint("TOPRIGHT", 0, 0)
        row.status:SetWidth(width * 0.39)
        row.note:SetWidth(width)
        row.title:SetText(entry.name .. " / " .. entry.quest.title)
        local status, color = Status(entry)
        row.status:SetText(status)
        row.status:SetTextColor(unpack(color))
        row.note:SetText((entry.quest.cadence == "once" and "One-time / " or "") .. RewardText(entry.quest.rewards))
        local lines = {}
        UI.AddTooltipLine(lines, status)
        UI.AddTooltipLine(lines, entry.quest.accountWide and "Shared activity" or "Character activity")
        UI.AddTooltipLine(lines, RewardText(entry.quest.rewards))
        UI.AddTooltipLine(lines, "Updated", UI.FormatLastSeen(entry.snapshot.updatedAt), Style.muted)
        UI.RefreshTooltip(row, entry.quest.title, lines)
        row:Show()
    end
    return rowIndex
end

function UI.CreateActivitiesPage(parent, width)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    page.width = width
    UI.AddLabel(page, "Rewards worth coming back for", 0, 0, width, 24, 16, Style.text)
    UI.AddLabel(page, "Open the companion's Call Board on each character to collect its activities.", 0, -27, width, 18, 11, Style.muted)
    page.scroll, page.body = UI.CreateScroll(page, nil, width)
    page.scroll:SetPoint("TOPLEFT", 0, -57)
    page.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    page.panels = {}
    return page
end

function UI.RefreshActivities(page, roster)
    local single = #roster == 1
    local panelWidth = single and page.width or (page.width - GAP) / 2
    local nextY, rowTop, rowHeight = 0, 0, 0
    for index, account in ipairs(roster) do
        local panel = page.panels[index]
        if not panel then panel = CreatePanel(page.body, panelWidth); page.panels[index] = panel end
        local latest, missing, daily, weekly = CollectActivities(account)
        local columnWidth = single and (panelWidth - 32 - GAP) / 2 or panelWidth - 32
        local dailyHeight = math.max(1, #daily) * ROW_HEIGHT
        local weeklyHeight = math.max(1, #weekly) * ROW_HEIGHT
        local height = single and (135 + math.max(dailyHeight, weeklyHeight))
            or (155 + dailyHeight + weeklyHeight)
        height = math.max(height, 220)
        if index % 2 == 1 then rowTop, rowHeight = nextY, height end
        rowHeight = math.max(rowHeight, height)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", single and 0 or ((index - 1) % 2) * (panelWidth + GAP), -rowTop)
        panel:SetSize(panelWidth, height)
        panel.title:SetWidth(panelWidth - 32)
        panel.title:SetText(account.name or "Unknown account")
        if latest then
            panel.cache:SetText("CALL BOARD CACHE  " .. latest.cacheProgress .. " / " .. latest.cacheRequired
                .. "  |  Opened: " .. latest.cachesOpened)
            panel.source:SetText("Last received " .. UI.FormatLastSeen(latest.updatedAt)
                .. "  |  " .. missing .. " character(s) not yet observed")
        else
            panel.cache:SetText("CALL BOARD CACHE  Unknown")
            panel.source:SetText("No Call Board snapshot received for this account.")
        end
        panel.dailyHeading:SetWidth(columnWidth)
        panel.weeklyHeading:SetWidth(columnWidth)
        panel.dailyHeading:SetText("DAILY  /  " .. (latest and TimeLeft(latest.dailyResetAt) or "Unknown reset"))
        panel.weeklyHeading:ClearAllPoints()
        panel.weeklyHeading:SetPoint("TOPLEFT", single and (16 + columnWidth + GAP) or 16,
            -(single and 95 or (125 + dailyHeight)))
        panel.weeklyHeading:SetText("WEEKLY & ONE-TIME  /  " .. (latest and TimeLeft(latest.weeklyResetAt) or "Unknown reset"))
        local used = DrawRows(panel, daily, 16, 120, columnWidth, 0)
        used = DrawRows(panel, weekly, single and (16 + columnWidth + GAP) or 16,
            single and 120 or (150 + dailyHeight), columnWidth, used)
        for row = used + 1, #panel.rows do panel.rows[row]:Hide() end
        panel:Show()
        if single or index % 2 == 0 or index == #roster then
            nextY = rowTop + rowHeight + 15
        end
    end
    for index = #roster + 1, #page.panels do page.panels[index]:Hide() end
    UI.UpdateScrollHeight(page.scroll, math.max(1, nextY))
end
