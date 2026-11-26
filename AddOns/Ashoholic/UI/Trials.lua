--[[
    UI/Trials.lua - the Trials tab (personal Trial records).

    One row per character on the visible accounts, with the saved bests of
    both Trials:

      Champion  a solo damage Trial. Its rank is within the character's class.
      Crusader  survive waves with 1 to 5 players. Its rank is across all
                classes, and Team is the size of the recorded best attempt.

    Records are passive observations. ProjectEbonhold reports them when a
    Trials leaderboard is viewed or a ranked Trial is finished, so ranks are
    last-observed snapshots, not live standings. Practice runs are never
    saved. Each Trial keeps its own "updated" time.

    Everything shown comes from UI.model (UI/Model.lua); this file never
    reads game data or saved variables.

    Memory: rows are pooled. They are made the first time they are needed
    and reused on every refresh.
]]

local addonName = ...
local addon = _G[addonName]
local UI = addon.UI

local MUTED, TEAL = UI.MUTED, UI.TEAL
local PAGE_HEIGHT, CONTENT_WIDTH, SCROLL_WIDTH = UI.PAGE_HEIGHT, UI.CONTENT_WIDTH, UI.SCROLL_WIDTH

-- Layout from the approved preview.
local VIEWPORT = PAGE_HEIGHT - 156
local ROW_HEIGHT, ROW_STEP = 44, 50
local TEAM_SIZE_LIMIT = 5

-- Column titles and their share of the table width.
local COLUMNS = {
    { title = "CHARACTER", share = 0.18 },
    { title = "CHAMPION BEST", share = 0.19 },
    { title = "CLASS RANK", share = 0.16 },
    { title = "CRUSADER BEST", share = 0.22 },
    { title = "TEAM", share = 0.11 },
    { title = "UPDATED", share = 0.14 },
}
do
    local x = 16
    for _, column in ipairs(COLUMNS) do
        column.x, column.width = x, (SCROLL_WIDTH - 32) * column.share
        x = x + column.width
    end
end

-------------------------------------------------------------------------------
-- Text helpers. Unknown records stay "Unknown"; 0 means "not recorded".
-------------------------------------------------------------------------------

local function ChampionText(record)
    if not record then
        return "Unknown"
    elseif record.best == 0 then
        return "Not recorded"
    end
    return UI.FormatNumber(record.best) .. " damage"
end

-- ProjectEbonhold packs a Crusader score as
--   waves * 100000000 + (99999999 - run time in tenths of a second)
-- so more waves always win, and a faster time wins between equal waves.
local function CrusaderText(record)
    if not record then
        return "Unknown"
    elseif record.best == 0 then
        return "Not recorded"
    end
    local waves = math.floor(record.best / 100000000)
    if waves <= 0 then
        return "0 waves"
    end
    local tenths = 99999999 - (record.best % 100000000)
    local seconds = math.floor(tenths / 10)
    return string.format("%d %s  %d:%02d.%d", waves, waves == 1 and "wave" or "waves",
        math.floor(seconds / 60), seconds % 60, tenths % 10)
end

-- "#42 / 1,280". A rank is a snapshot of a moving leaderboard, so a rank
-- seen at least a week ago is dimmed and marked as stale.
local function RankText(record, now)
    if not record then
        return "Unknown"
    elseif record.best == 0 then
        return "-"
    elseif record.rank == nil then
        return "Unknown"
    elseif record.rank == 0 then
        return "Not ranked"
    end
    local text = "#" .. UI.FormatNumber(record.rank)
    if record.total then
        text = text .. " / " .. UI.FormatNumber(record.total)
    end
    if now and now - record.updatedAt >= UI.STALE_SECONDS then
        return UI.DIM .. text .. " (stale)|r"
    end
    return text
end

local function TeamText(record)
    if not record then
        return "Unknown"
    elseif record.best == 0 then
        return "-"
    elseif record.teamSize == nil then
        return "Unknown"
    elseif record.teamSize == 1 then
        return "Solo"
    end
    return record.teamSize .. " players"
end

-- The season of a record: its name, else its number, else Unknown.
local function SeasonText(record)
    if record and record.seasonName and record.seasonName ~= "" then
        return record.seasonName
    elseif record and record.season then
        return "Season " .. record.season
    end
    return "Unknown"
end

-- The newer of a character's two records, or nil when there is none.
local function NewestUpdate(champion, crusader)
    local newest = champion and champion.updatedAt
    if crusader and (not newest or crusader.updatedAt > newest) then
        newest = crusader.updatedAt
    end
    return newest
end

-------------------------------------------------------------------------------
-- Tooltip (written when the mouse enters, from the row's character)
-------------------------------------------------------------------------------

local function TrialTip(row)
    local character = row.character
    if not character then
        return
    end
    local trials = character.source.trials
    local champion = trials and trials.champion
    local crusader = trials and trials.crusader
    UI.TipTitle(character.name .. " / " .. character.account.name)

    UI.TipLine("Trial of the Champion: solo damage, ranked within your class.", nil, MUTED)
    UI.TipLine("Best", ChampionText(champion))
    UI.TipLine("Class rank", RankText(champion))
    UI.TipLine("Season", SeasonText(champion))
    UI.TipLine("Updated", UI.FormatLastSeen(champion and champion.updatedAt))

    GameTooltip:AddLine(" ")
    UI.TipLine("Trial of the Crusader: survive waves with 1 to " .. TEAM_SIZE_LIMIT .. " players.", nil, MUTED)
    UI.TipLine("Best", CrusaderText(crusader))
    UI.TipLine("Team of the best attempt", TeamText(crusader))
    UI.TipLine("Rank (all classes)", RankText(crusader))
    UI.TipLine("Season", SeasonText(crusader))
    UI.TipLine("Updated", UI.FormatLastSeen(crusader and crusader.updatedAt))

    GameTooltip:AddLine(" ")
    if not champion or not crusader then
        UI.TipLine("A record is saved when that Trial's leaderboard is viewed or a ranked Trial is finished "
            .. "on this character.", nil, MUTED)
    end
    UI.TipLine("Practice runs are not saved. Ranks are the last observed snapshot, not live standings.",
        nil, MUTED)
end

-------------------------------------------------------------------------------
-- Building the page (runs once, the first time the Trials tab is shown)
-------------------------------------------------------------------------------

-- A label that always stays on one line (long text ends with "...").
local function OneLineLabel(parent, x, y, width, size, height)
    local label = UI.Label(parent, "", x, y, width, size)
    label:SetHeight(height)
    UI.NoWrap(label)
    return label
end

local function NewRow(body)
    local row = UI.Surface(body, 0, 0, SCROLL_WIDTH, ROW_HEIGHT)
    row.cells = {}
    for index, column in ipairs(COLUMNS) do
        -- The character name is a little larger, as in the preview.
        local size = index == 1 and 12 or 11
        row.cells[index] = OneLineLabel(row, column.x, 15, column.width - 12, size, size + 2)
    end
    UI.TipProvider(row, TrialTip)
    return row
end

local function FillRow(row, character, now)
    local trials = character.source.trials
    local champion = trials and trials.champion
    local crusader = trials and trials.crusader
    local cells = row.cells
    row.character = character
    cells[1]:SetText(UI.ClassName(character))
    cells[2]:SetText(ChampionText(champion))
    cells[3]:SetText(RankText(champion, now))
    cells[4]:SetText(CrusaderText(crusader))
    cells[5]:SetText(TeamText(crusader))
    cells[6]:SetText(UI.FormatLastSeen(NewestUpdate(champion, crusader)))
    UI.RefreshTip(row)
end

-- The footer names the season of the newest saved record of each Trial.
-- When both Trials report the same season it is named once.
local function SeasonFooter(champion, crusader)
    local suffix = "  /  Practice runs excluded  /  Ranks are last-observed snapshots."
    if not champion and not crusader then
        return "Season: Unknown until a Trials leaderboard is viewed" .. suffix
    end
    local championSeason, crusaderSeason = SeasonText(champion), SeasonText(crusader)
    if not crusader or championSeason == crusaderSeason then
        return "Season: " .. championSeason .. suffix
    elseif not champion then
        return "Season: " .. crusaderSeason .. suffix
    end
    return "Champion season: " .. championSeason .. "  /  Crusader season: " .. crusaderSeason .. suffix
end

local function BuildTrials(parent)
    local page = UI.Page(parent, "Personal records",
        "Compare saved bests across your roster. Rankings are last-observed snapshots, not live standings.")
    for _, column in ipairs(COLUMNS) do
        UI.Label(page, column.title, column.x, 68, column.width - 12, 10, MUTED)
    end
    UI.Button(page, "What are these Trials?", CONTENT_WIDTH - 227, 0, 227, 26, function()
        UI.ShowSettings("Help")
    end)

    local scroll, body = UI.Scroll(page, "AshoholicTrialScroll", 0, 98, CONTENT_WIDTH, VIEWPORT)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", UI.ScrollBy)
    local empty = UI.Label(body, "", 16, 15, SCROLL_WIDTH - 32, 12, MUTED)
    local footer = UI.Label(page, "", 16, PAGE_HEIGHT - 45, CONTENT_WIDTH - 32, 11, TEAL)
    local rows = {}

    page.Refresh = function()
        local now = time()
        local count = 0
        -- The newest record of each Trial on the visible accounts (footer).
        local newestChampion, newestCrusader
        for _, account in ipairs(UI.model.accounts) do
            if account.visible then
                for _, character in ipairs(account.characters) do
                    count = count + 1
                    local row = rows[count]
                    if not row then
                        row = NewRow(body)
                        rows[count] = row
                    end
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -((count - 1) * ROW_STEP))
                    row:Show()
                    FillRow(row, character, now)

                    local trials = character.source.trials
                    local champion = trials and trials.champion
                    local crusader = trials and trials.crusader
                    if champion and (not newestChampion or champion.updatedAt > newestChampion.updatedAt) then
                        newestChampion = champion
                    end
                    if crusader and (not newestCrusader or crusader.updatedAt > newestCrusader.updatedAt) then
                        newestCrusader = crusader
                    end
                end
            end
        end
        for index = count + 1, #rows do
            rows[index]:Hide()
            rows[index].character = nil
        end

        if count == 0 then
            empty:SetText(UI.VisibleAccountCount() == 0
                and "No visible accounts. Use the account filter above to show one."
                or "No characters saved on the visible accounts yet.")
            empty:Show()
        else
            empty:Hide()
        end
        footer:SetText(SeasonFooter(newestChampion, newestCrusader))

        local contentHeight = count > 0 and (count - 1) * ROW_STEP + ROW_HEIGHT or 0
        body:SetHeight(math.max(VIEWPORT, contentHeight))
        UI.ClampScroll(scroll, contentHeight, VIEWPORT)
    end

    return page
end

UI.pageBuilders.Trials = BuildTrials
