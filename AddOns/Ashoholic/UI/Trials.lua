-- Saved Champion and Crusader records; each Trial keeps its own freshness.
local addonName = ...
local UI = _G[addonName].UI
local Style = UI.Style
local ROW_HEIGHT = 44

local function Champion(record)
    if not record then return "Unknown" end
    if record.best == 0 then return "Not recorded" end
    return UI.FormatNumber(record.best) .. " damage"
end

local function Rank(record)
    if not record or record.rank == nil then return "Unknown" end
    if record.rank == 0 then return "Not ranked" end
    return "#" .. UI.FormatNumber(record.rank)
        .. (record.total and (" / " .. UI.FormatNumber(record.total)) or "")
end

local function Crusader(record)
    if not record then return "Unknown" end
    if record.best == 0 then return "Not recorded" end
    local waves = math.floor(record.best / 100000000)
    if waves <= 0 then return "0 waves" end
    local tenths = 99999999 - (record.best % 100000000)
    local seconds = math.floor(tenths / 10)
    return string.format("%d wave%s / %d:%02d.%d",
        waves, waves == 1 and "" or "s", math.floor(seconds / 60), seconds % 60, tenths % 10)
end

local function CreateRow(page)
    local row = UI.CreateSurface(page.body, page.width, ROW_HEIGHT)
    local x = { 12, 240, 475, 660, 920, 1050 }
    local widths = { 215, 220, 170, 245, 115, page.width - 1062 }
    row.cells = {}
    for index = 1, #x do
        row.cells[index] = UI.AddLabel(row, "", x[index], -5, widths[index], 34, 11, Style.text)
        if row.cells[index].SetWordWrap then row.cells[index]:SetWordWrap(false) end
    end
    UI.AttachTooltip(row)
    return row
end

function UI.CreateTrialsPage(parent, width)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    page.width = width
    UI.AddLabel(page, "Trials", 0, 0, width, 24, 16, Style.text)
    UI.AddLabel(page, "Open your own class leaderboard or finish a ranked Trial to collect records.", 0, -27, width, 18, 11, Style.muted)
    local x = { 12, 240, 475, 660, 920, 1050 }
    local labels = { "CHARACTER", "CHAMPION BEST", "CLASS RANK", "CRUSADER BEST", "TEAM", "UPDATED" }
    for index, label in ipairs(labels) do
        UI.AddLabel(page, label, x[index], -61, 190, 18, 10, Style.gold)
    end
    page.scroll, page.body = UI.CreateScroll(page, nil, width)
    page.scroll:SetPoint("TOPLEFT", 0, -87)
    page.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    page.rows = {}
    return page
end

function UI.RefreshTrials(page, roster)
    local y, index = 0, 0
    for _, account in ipairs(roster) do
        for _, character in ipairs(account.characters) do
            index = index + 1
            local row = page.rows[index]
            if not row then row = CreateRow(page); page.rows[index] = row end
            local trials = character.trials
            local champion = trials and trials.champion
            local crusader = trials and trials.crusader
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row.cells[1]:SetText(character.name .. " / " .. (account.name or "Unknown account"))
            row.cells[2]:SetText(Champion(champion))
            row.cells[3]:SetText(Rank(champion))
            row.cells[4]:SetText(Crusader(crusader))
            row.cells[5]:SetText(crusader and crusader.teamSize
                and (crusader.teamSize == 1 and "Solo" or crusader.teamSize .. " players") or "Unknown")
            local latest = math.max(champion and champion.updatedAt or 0, crusader and crusader.updatedAt or 0)
            row.cells[6]:SetText(latest > 0 and UI.FormatLastSeen(latest) or "Unknown")
            local lines = {}
            UI.AddTooltipLine(lines, "Champion updated", UI.FormatLastSeen(champion and champion.updatedAt))
            UI.AddTooltipLine(lines, "Crusader updated", UI.FormatLastSeen(crusader and crusader.updatedAt))
            if champion and champion.seasonName and champion.seasonName ~= "" then
                UI.AddTooltipLine(lines, "Champion season", champion.seasonName)
            end
            if crusader and crusader.seasonName and crusader.seasonName ~= "" then
                UI.AddTooltipLine(lines, "Crusader season", crusader.seasonName)
            end
            UI.AddTooltipLine(lines, "Practice runs are not saved.", nil, Style.muted)
            UI.RefreshTooltip(row, character.name .. " / " .. character.realm, lines)
            row:Show()
            y = y + ROW_HEIGHT + 6
        end
    end
    for old = index + 1, #page.rows do page.rows[old]:Hide() end
    UI.UpdateScrollHeight(page.scroll, math.max(1, y))
end
