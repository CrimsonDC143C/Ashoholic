--[[
    UI/Activities.lua - the Activities tab (the Hero's Call Board).

    One panel per visible account. Two accounts sit side by side; when only
    one account is visible it gets the full width, with its Daily and Weekly
    activities in two columns (the approved preview layout).

    Every panel shows two things:

      1. The Call Board cache and the weekly reward rail, one line per
         character. Both belong to ONE character: the cache bar depends on
         the item level that character has worn, and the rail counts that
         character's claims this week. Characters are never added together.

      2. Unclaimed and in-progress activities from the saved boards.
         Character activities are listed per character. Shared (account-wide)
         activities are listed once per account, from the newest saved board.

    Saved boards are passive observations: they only change when the Call
    Board is opened in game. Once a daily or weekly reset has passed, an older
    board cannot tell what is open now, so its activities show "Unknown"
    until the Call Board is opened again. Reset times are never guessed.

    Everything shown comes from UI.model (UI/Model.lua); this file never
    reads game data or saved variables.

    Memory: panels, cache lines and activity rows are pooled. They are
    created the first time they are needed and reused on every refresh;
    unused ones are only hidden. The small entry tables are reused as well.
]]

local addonName = ...
local addon = _G[addonName]
local UI = addon.UI

local GOLD, MUTED, TEAL = UI.GOLD, UI.MUTED, UI.TEAL
local PAGE_HEIGHT, CONTENT_WIDTH = UI.PAGE_HEIGHT, UI.CONTENT_WIDTH
local SCROLL_WIDTH, HALF_PANEL_WIDTH, PANEL_GAP = UI.SCROLL_WIDTH, UI.HALF_PANEL_WIDTH, UI.PANEL_GAP

-- Layout from the approved preview.
local VIEWPORT = PAGE_HEIGHT - 75   -- scroll area height; also the smallest panel height
local GRID_GAP = 15                 -- space between two rows of panels
local LINE_FIRST = 73               -- y of the first cache line
local LINE_STEP = 34                -- one cache line: texts, then the bar below them
local ROW_STEP = 56                 -- one activity: title and status, then the note
local STATUS_WIDTH = 214
local VALUE_WIDTH = 140
local RAIL_WIDTH = 240

-- Call Board activity states (ProjectEbonhold's Callboard.STATE):
-- 0 available (not accepted yet), 1 accepted, 2 complete (the reward can be
-- claimed), 3 claimed. Only accepted and complete activities are listed.
local STATE_ACCEPTED, STATE_COMPLETE = 1, 2

-- Call Board category IDs (see Data/Schema.lua). Category 8 is the Frostveil
-- winter event: its dailies are only posted while the event runs.
local CATEGORY_NAMES = {
    [1] = "Dungeon", [2] = "Raid", [3] = "Open World", [4] = "Profession",
    [6] = "Other", [7] = "Torment", [8] = "Frostveil event",
}
local FROSTVEIL = 8
local CADENCE_NAMES = { daily = "daily", weekly = "weekly", once = "one-time" }
local CADENCE_ORDER = { daily = 1, weekly = 2, once = 3 }

-- Sort ranks and meanings of the activity statuses (see ActivityStatus).
local RANK_READY, RANK_COST, RANK_PROGRESS, RANK_UNKNOWN = 1, 2, 3, 4

-- Reward fields in display order. The short name is used in the row note,
-- the long name in the tooltip. Copper is shown as gold.
local REWARDS = {
    { field = "ash", short = "Ash", long = "Soul Ash" },
    { field = "shards", short = "Shards", long = "Soul Shards" },
    { field = "copper", long = "Gold" },
    { field = "artisan", short = "Artisan", long = "Artisan Soul" },
    { field = "orbs", short = "Orbs", long = "Orbs of Lost Memories" },
}

-- Tooltip color of reached rail steps (the same green as UI.GREEN).
local REACHED = { 0.49, 0.86, 0.63 }

-------------------------------------------------------------------------------
-- Text helpers
-------------------------------------------------------------------------------

-- "Dungeon daily", "Frostveil event daily", or just "Weekly" when the board
-- did not report a category.
local function KindText(quest)
    local category = quest.category and CATEGORY_NAMES[quest.category]
    local cadence = CADENCE_NAMES[quest.cadence]
    if category then
        return category .. " " .. cadence
    end
    return string.upper(string.sub(cadence, 1, 1)) .. string.sub(cadence, 2)
end

-- "120 Ash + 5 Shards + 2g" for the row note. Only currency rewards are
-- saved, so items or experience on the board are not listed here.
local rewardParts = {}
local function RewardText(rewards)
    if not rewards then
        return "Rewards unknown"
    end
    wipe(rewardParts)
    for _, reward in ipairs(REWARDS) do
        local amount = rewards[reward.field]
        if amount and amount > 0 then
            if reward.field == "copper" then
                rewardParts[#rewardParts + 1] = UI.FormatGold(amount)
            else
                rewardParts[#rewardParts + 1] = UI.FormatNumber(amount) .. " " .. reward.short
            end
        end
    end
    if #rewardParts == 0 then
        return "No currency rewards"
    end
    return table.concat(rewardParts, " + ")
end

-- "in 8h 42m", or a reminder that the saved time has already passed.
local function ResetText(resetAt, now)
    if resetAt > now then
        return "in " .. UI.RemainingTime(resetAt - now)
    end
    return "passed; open the Call Board"
end

-- Contracts claimed this week, or nil when unknown: the board has no rail
-- (older servers), or the weekly reset passed after the board was saved.
local function WeeklyClaims(board, now)
    if board.rail and board.weeklyClaims and board.weeklyResetAt > now then
        return board.weeklyClaims
    end
    return nil
end

-- "Weekly rail 12 / 30" on a character's cache line.
local function RailText(board, now)
    local claims = WeeklyClaims(board, now)
    if not claims then
        return UI.DIM .. "Weekly rail Unknown|r"
    end
    local last = board.rail[#board.rail].count
    if claims >= last then
        return UI.GREEN .. "Weekly rail complete (" .. claims .. ")|r"
    end
    return "Weekly rail " .. claims .. " / " .. last
end

-- "Elixir of Ashes, Elixir of Shards" for one rail step. The item names were
-- saved when the board was observed; an unknown name shows the item ID.
local itemNames = {}
local function StepItems(step)
    wipe(itemNames)
    for _, item in ipairs(step.items) do
        itemNames[#itemNames + 1] = item.name or ("Item " .. item.id)
    end
    return table.concat(itemNames, ", ")
end

-------------------------------------------------------------------------------
-- Reading the saved boards of one account
-------------------------------------------------------------------------------

-- Status of one listed activity: a sort rank and the status text.
local function ActivityStatus(quest, board, now)
    local resetAt
    if quest.cadence == "daily" then
        resetAt = board.dailyResetAt
    elseif quest.cadence == "weekly" then
        resetAt = board.weeklyResetAt
    end
    -- One-time activities have no reset, so resetAt stays nil for them.
    if resetAt and resetAt <= now then
        return RANK_UNKNOWN, UI.DIM .. "Unknown|r"
    elseif quest.state == STATE_COMPLETE and not quest.cost then
        return RANK_READY, UI.GREEN .. "Ready to claim|r"
    elseif quest.state == STATE_COMPLETE then
        -- Claiming takes gold, so this reward is not ready for free.
        return RANK_COST, UI.AMBER .. "Claim costs " .. UI.FormatCopper(quest.cost) .. "|r"
    end
    return RANK_PROGRESS, quest.done .. " / " .. quest.max .. " objectives"
end

-- Entry tables are reused between refreshes (see Memory at the top).
-- Refresh sets entriesUsed back to 0 before reading the accounts.
local entryPool, entriesUsed = {}, 0

local function AddEntry(info, character, board, questId, shared, now)
    entriesUsed = entriesUsed + 1
    local entry = entryPool[entriesUsed]
    if not entry then
        entry = {}
        entryPool[entriesUsed] = entry
    end
    local quest = board.quests[questId]
    entry.character, entry.board, entry.quest = character, board, quest
    entry.questId, entry.shared = questId, shared
    entry.rank, entry.status = ActivityStatus(quest, board, now)
    -- Shared activities ("" sorts first) come before character activities.
    entry.owner = shared and "" or string.lower(character.name)
    info.entries[#info.entries + 1] = entry
end

-- Ready first, then gold costs, in progress and unknown; then daily before
-- weekly before one-time; then by character, title and finally the ID.
local function CompareEntries(left, right)
    if left.rank ~= right.rank then
        return left.rank < right.rank
    end
    local leftCadence, rightCadence = CADENCE_ORDER[left.quest.cadence], CADENCE_ORDER[right.quest.cadence]
    if leftCadence ~= rightCadence then
        return leftCadence < rightCadence
    end
    if left.owner ~= right.owner then
        return left.owner < right.owner
    end
    if left.quest.title ~= right.quest.title then
        return left.quest.title < right.quest.title
    end
    return left.questId < right.questId
end

local function IsListed(quest)
    return quest.state == STATE_ACCEPTED or quest.state == STATE_COMPLETE
end

-- Fill info (one panel's reused tables) from an account's saved boards:
--   info.observed  characters with a saved board, in roster order
--   info.missing   characters without one
--   info.newest    the most recently saved board (used for reset times)
--   info.entries   the listed activities, sorted
local function ReadAccount(account, info, now)
    wipe(info.observed)
    wipe(info.missing)
    wipe(info.entries)
    wipe(info.sharedBoard)
    wipe(info.sharedOwner)
    info.newest = nil

    for _, character in ipairs(account.characters) do
        local board = character.source.activities
        if not board then
            info.missing[#info.missing + 1] = character
        else
            info.observed[#info.observed + 1] = character
            if not info.newest or board.updatedAt > info.newest.updatedAt then
                info.newest = board
            end
            for questId, quest in pairs(board.quests) do
                if quest.accountWide then
                    -- A shared activity appears on every character's board.
                    -- Keep the copy from the newest board, even when that copy
                    -- is already claimed: an older board must not bring back
                    -- something another character has finished since.
                    local kept = info.sharedBoard[questId]
                    if not kept or board.updatedAt > kept.updatedAt then
                        info.sharedBoard[questId] = board
                        info.sharedOwner[questId] = character
                    end
                elseif IsListed(quest) then
                    AddEntry(info, character, board, questId, false, now)
                end
            end
        end
    end

    for questId, board in pairs(info.sharedBoard) do
        if IsListed(board.quests[questId]) then
            AddEntry(info, info.sharedOwner[questId], board, questId, true, now)
        end
    end
    table.sort(info.entries, CompareEntries)
end

-------------------------------------------------------------------------------
-- Tooltips (written when the mouse enters, from the data on the widget)
-------------------------------------------------------------------------------

-- A character's cache line: the cache bar and the weekly reward rail.
local function LineTip(line)
    local character = line.character
    local board = character and character.source.activities
    if not board then
        return
    end
    local now = time()
    UI.TipTitle(character.name .. " / Hero's Call Cache")
    UI.TipLine("Contracts toward the next cache", board.cacheProgress .. " / " .. board.cacheRequired)
    UI.TipLine("Caches opened", UI.FormatNumber(board.cachesOpened))
    UI.TipLine("Equipped item level", board.equippedItemLevel and tostring(board.equippedItemLevel) or "Unknown")
    UI.TipLine("Every claimed contract fills this character's bar; a full bar hands out a Hero's Call Cache. "
        .. "The higher the item level this character has ever worn, the more contracts a cache needs.", nil, MUTED)

    if board.rail then
        local claims = WeeklyClaims(board, now)
        GameTooltip:AddLine(" ")
        UI.TipTitle("Weekly reward rail")
        UI.TipLine("Contracts claimed this week", claims and tostring(claims) or "Unknown")
        for _, step in ipairs(board.rail) do
            UI.TipLine(step.count .. " claims", StepItems(step), claims and claims >= step.count and REACHED or nil)
        end
        if board.weeklyResetAt <= now then
            UI.TipLine("The weekly reset passed after this board was saved. Open the Call Board to refresh it.",
                nil, MUTED)
        elseif not claims then
            UI.TipLine("This board did not report this week's claims.", nil, MUTED)
        end
    end
    GameTooltip:AddLine(" ")
    UI.TipLine("Board saved", UI.FormatLastSeen(board.updatedAt), MUTED)
end

-- One listed activity.
local function RowTip(row)
    local entry = row.entry
    if not entry then
        return
    end
    local quest = entry.quest
    UI.TipTitle(quest.title)
    if entry.shared then
        UI.TipLine("Shared activity", "counts once per account")
        UI.TipLine("Newest saved board", entry.character.name)
    else
        UI.TipLine("Character activity", entry.character.name)
    end
    UI.TipLine("Kind", KindText(quest))
    UI.TipLine("Objectives", quest.done .. " / " .. quest.max)
    UI.TipLine("Status", entry.status)
    if quest.cost then
        UI.TipLine("Claim cost", UI.FormatCopper(quest.cost))
    end
    if quest.rewards then
        for _, reward in ipairs(REWARDS) do
            local amount = quest.rewards[reward.field]
            if amount and amount > 0 then
                UI.TipLine(reward.long, reward.field == "copper" and UI.FormatCopper(amount) or UI.FormatNumber(amount))
            end
        end
    end
    UI.TipLine("Board saved", UI.FormatLastSeen(entry.board.updatedAt), MUTED)
    if entry.rank == RANK_UNKNOWN then
        UI.TipLine("A reset passed after this board was saved. Open the Call Board to see what is open now.",
            nil, MUTED)
    elseif entry.rank == RANK_COST then
        UI.TipLine("Claiming takes this gold, so it is not counted as ready to claim.", nil, MUTED)
    end
    if quest.category == FROSTVEIL then
        UI.TipLine("Frostveil activities are winter-event dailies, posted only while the event runs.", nil, MUTED)
    end
end

-- The names of the characters that have no saved board.
local function MissingTip(frame)
    local missing = frame.characters
    if not missing or #missing == 0 then
        return
    end
    UI.TipTitle("No saved Call Board")
    for _, character in ipairs(missing) do
        UI.TipLine(UI.ClassName(character))
    end
    UI.TipLine("A board is saved when the Call Board is opened on that character.", nil, MUTED)
end

-------------------------------------------------------------------------------
-- Pooled widgets
-------------------------------------------------------------------------------

-- Move a label and optionally change its text.
local function Place(label, x, y, width, text)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", x, -y)
    label:SetWidth(width)
    if text then
        label:SetText(text)
    end
end

-- A label that always stays on one line (long text ends with "...").
local function OneLineLabel(parent, x, y, width, size, color, height)
    local label = UI.Label(parent, "", x, y, width, size, color)
    label:SetHeight(height)
    UI.NoWrap(label)
    return label
end

-- One account panel. Its parts are moved by FillPanel on every refresh.
local function NewPanel(body)
    local inner = HALF_PANEL_WIDTH - 32
    local panel = UI.Surface(body, 0, 0, HALF_PANEL_WIDTH, VIEWPORT)
    panel.title = OneLineLabel(panel, 16, 17, inner, 16, GOLD, 20)
    panel.cache = UI.Label(panel, "CALL BOARD CACHE  /  WEEKLY REWARD RAIL", 16, 51, inner, 10, MUTED)

    -- Characters without a saved board share one line with a tooltip.
    panel.missing = CreateFrame("Frame", nil, panel)
    panel.missing:SetHeight(16)
    panel.missing.text = OneLineLabel(panel.missing, 0, 0, inner, 11, MUTED, 14)
    UI.TipProvider(panel.missing, MissingTip)

    panel.heading = UI.Label(panel, "UNCLAIMED & IN PROGRESS", 16, 0, inner, 10, GOLD)
    panel.daily = OneLineLabel(panel, 16, 0, inner, 11, GOLD, 14)
    panel.weekly = OneLineLabel(panel, 16, 0, inner, 11, GOLD, 14)
    panel.emptyDaily = UI.Label(panel, "", 16, 0, inner, 11, MUTED)
    panel.emptyWeekly = UI.Label(panel, "", 16, 0, inner, 11, MUTED)

    panel.lines, panel.rows = {}, {}
    panel.info = {
        observed = {}, missing = {}, entries = {},
        sharedBoard = {}, sharedOwner = {},
        daily = {}, weekly = {},
    }
    return panel
end

-- One character's cache line: name, cache progress, rail progress, bar.
local function PlaceLine(panel, index, character, y, width, now)
    local line = panel.lines[index]
    if not line then
        line = CreateFrame("Frame", nil, panel)
        line:SetHeight(26)
        line.name = OneLineLabel(line, 0, 0, 190, 12, nil, 14)
        line.value = OneLineLabel(line, 196, 0, VALUE_WIDTH, 12, TEAL, 14)
        line.rail = OneLineLabel(line, 0, 1, RAIL_WIDTH, 11, MUTED, 13)
        line.rail:SetJustifyH("RIGHT")
        line.track = UI.Progress(line, 0, 20, width)
        UI.TipProvider(line, LineTip)
        panel.lines[index] = line
    end
    local board = character.source.activities
    line.character = character
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", 16, -y)
    line:SetWidth(width)
    line.name:SetText(UI.ClassName(character))
    line.value:SetText(board.cacheProgress .. " / " .. board.cacheRequired .. " contracts")
    Place(line.rail, width - RAIL_WIDTH, 1, RAIL_WIDTH, RailText(board, now))
    line.track:SetWidth(width)
    line.track.fullWidth = width
    UI.SetProgress(line.track, board.cacheProgress, board.cacheRequired)
    line:Show()
    UI.RefreshTip(line)
end

-- One activity row: "Name / Title" with the status on the right, and a note.
local function PlaceRow(panel, index, entry, x, y, width)
    local row = panel.rows[index]
    if not row then
        row = CreateFrame("Frame", nil, panel)
        row:SetHeight(38)
        row.title = OneLineLabel(row, 0, 0, 280, 12, nil, 14)
        row.status = OneLineLabel(row, 280, 0, STATUS_WIDTH, 11, TEAL, 13)
        row.status:SetJustifyH("RIGHT")
        row.note = OneLineLabel(row, 0, 23, width, 10, MUTED, 12)
        UI.TipProvider(row, RowTip)
        panel.rows[index] = row
    end
    local titleWidth = width - STATUS_WIDTH - 12
    local quest = entry.quest
    row.entry = entry
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", x, -y)
    row:SetWidth(width)
    Place(row.title, 0, 0, titleWidth, (entry.shared and "Account" or entry.character.name) .. " / " .. quest.title)
    Place(row.status, titleWidth + 12, 0, STATUS_WIDTH, entry.status)
    if entry.rank == RANK_UNKNOWN then
        Place(row.note, 0, 23, width, "Snapshot predates this reset; open the Call Board")
    else
        Place(row.note, 0, 23, width, (entry.shared and "Shared activity" or "Character activity")
            .. "  /  " .. KindText(quest) .. "  /  " .. RewardText(quest.rewards))
    end
    row:Show()
    UI.RefreshTip(row)
end

-- Place a list of activities from top to bottom. Returns the y below them.
local function PlaceColumn(panel, list, firstIndex, x, y, width, emptyLabel, emptyText)
    if #list == 0 then
        Place(emptyLabel, x, y, width, emptyText)
        emptyLabel:Show()
        return y + 20
    end
    emptyLabel:Hide()
    for index, entry in ipairs(list) do
        PlaceRow(panel, firstIndex + index, entry, x, y, width)
        y = y + ROW_STEP
    end
    -- The last row's note ends 37 pixels below its top.
    return y - ROW_STEP + 37
end

-- Fill one account panel. Returns the height its content needs.
local function FillPanel(panel, account, width, single, now)
    local info = panel.info
    local inner = width - 32
    panel:SetWidth(width)
    Place(panel.title, 16, 17, inner, account.name)
    UI.Paint(panel.title, account.color or GOLD)
    panel.cache:SetWidth(inner)

    -- 1. One cache line per character with a saved board.
    local y = LINE_FIRST
    for index, character in ipairs(info.observed) do
        PlaceLine(panel, index, character, y, inner, now)
        y = y + LINE_STEP
    end
    for index = #info.observed + 1, #panel.lines do
        panel.lines[index]:Hide()
        panel.lines[index].character = nil
    end

    -- Characters without a saved board share one line.
    local missing = panel.missing
    missing.characters = info.missing
    if #info.missing > 0 then
        missing:ClearAllPoints()
        missing:SetPoint("TOPLEFT", 16, -y)
        missing:SetWidth(inner)
        if #info.observed == 0 then
            Place(missing.text, 0, 0, inner, "No saved Call Board yet. Open the Call Board on a character of this account.")
        elseif #info.missing == 1 then
            Place(missing.text, 0, 0, inner, "1 character has no saved Call Board. Hover for the name.")
        else
            Place(missing.text, 0, 0, inner, #info.missing .. " characters have no saved Call Board. Hover for names.")
        end
        missing:Show()
        y = y + 24
    else
        missing:Hide()
    end
    UI.RefreshTip(missing)

    -- 2. The activity list: one list, or Daily and Weekly columns when this
    -- is the only visible account.
    local headingY = y + 12
    local emptyText = #info.observed == 0 and "No saved activities."
        or "Nothing unclaimed or in progress on the saved boards."
    local board = info.newest
    UI.SetVisible(panel.heading, not single)
    UI.SetVisible(panel.daily, single)
    UI.SetVisible(panel.weekly, single)
    local bottom
    if single then
        local columnWidth = (inner - PANEL_GAP) / 2
        local rightX = 16 + columnWidth + PANEL_GAP
        local daily, weekly = info.daily, info.weekly
        wipe(daily)
        wipe(weekly)
        for _, entry in ipairs(info.entries) do
            if entry.quest.cadence == "daily" then
                daily[#daily + 1] = entry
            else
                weekly[#weekly + 1] = entry
            end
        end
        Place(panel.daily, 16, headingY, columnWidth, "DAILY  /  "
            .. (board and ("Reset " .. ResetText(board.dailyResetAt, now)) or "Reset time unknown"))
        Place(panel.weekly, rightX, headingY, columnWidth, "WEEKLY & ONE-TIME  /  "
            .. (board and ("Weekly reset " .. ResetText(board.weeklyResetAt, now)) or "Reset time unknown"))
        local leftBottom = PlaceColumn(panel, daily, 0, 16, headingY + 38, columnWidth,
            panel.emptyDaily, emptyText)
        local rightBottom = PlaceColumn(panel, weekly, #daily, rightX, headingY + 38, columnWidth,
            panel.emptyWeekly, emptyText)
        bottom = math.max(leftBottom, rightBottom)
    else
        Place(panel.heading, 16, headingY, inner)
        bottom = PlaceColumn(panel, info.entries, 0, 16, headingY + 27, inner, panel.emptyDaily, emptyText)
        panel.emptyWeekly:Hide()
    end
    for index = #info.entries + 1, #panel.rows do
        panel.rows[index]:Hide()
        panel.rows[index].entry = nil
    end
    return bottom + 16
end

-------------------------------------------------------------------------------
-- Building the page (runs once, the first time the Activities tab is shown)
-------------------------------------------------------------------------------

local function BuildActivities(parent)
    local page = UI.Page(parent, "Rewards worth coming back for",
        "Daily and weekly Call Board activities are separate from the current run's Death contract.")
    local scroll, body = UI.Scroll(page, "AshoholicActivityScroll", 0, 57, CONTENT_WIDTH, VIEWPORT)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", UI.ScrollBy)
    local empty = UI.Label(body, "No visible accounts. Use the account filter above to show one.",
        0, 0, SCROLL_WIDTH, 12, MUTED)
    local footer = UI.Label(page, "", 0, PAGE_HEIGHT - 9, CONTENT_WIDTH, 10, MUTED)
    local panels = {}

    page.Refresh = function()
        local now = time()
        entriesUsed = 0
        local single = UI.VisibleAccountCount() == 1
        local width = single and SCROLL_WIDTH or HALF_PANEL_WIDTH
        -- The newest board of all visible accounts gives the footer's reset
        -- times. Resets are server-wide, so any board's times apply to all.
        local newest

        -- Panels fill a grid of two columns. Both panels of a grid row get
        -- the height of the taller one, so the rows line up.
        local count, rowY, rowHeight, leftPanel = 0, 0, 0, nil
        for _, account in ipairs(UI.model.accounts) do
            if account.visible then
                count = count + 1
                local panel = panels[count]
                if not panel then
                    panel = NewPanel(body)
                    panels[count] = panel
                end
                ReadAccount(account, panel.info, now)
                local board = panel.info.newest
                if board and (not newest or board.updatedAt > newest.updatedAt) then
                    newest = board
                end
                local height = math.max(VIEWPORT, FillPanel(panel, account, width, single, now))
                local column = (count - 1) % 2
                panel:ClearAllPoints()
                if column == 0 then
                    if count > 1 then
                        rowY = rowY + rowHeight + GRID_GAP
                    end
                    rowHeight = height
                    leftPanel = panel
                    panel:SetPoint("TOPLEFT", 0, -rowY)
                else
                    rowHeight = math.max(rowHeight, height)
                    leftPanel:SetHeight(rowHeight)
                    panel:SetPoint("TOPLEFT", HALF_PANEL_WIDTH + PANEL_GAP, -rowY)
                end
                panel:SetHeight(rowHeight)
                panel:Show()
            end
        end
        for index = count + 1, #panels do
            panels[index]:Hide()
        end
        UI.SetVisible(empty, count == 0)

        if newest then
            footer:SetText("Daily reset " .. ResetText(newest.dailyResetAt, now) .. "  /  Weekly reset "
                .. ResetText(newest.weeklyResetAt, now) .. "  /  Shared activities count once per account.")
        else
            footer:SetText("Reset times appear once a Call Board has been opened. "
                .. "Shared activities count once per account.")
        end

        local contentHeight = count > 0 and rowY + rowHeight or 0
        body:SetHeight(math.max(VIEWPORT, contentHeight))
        UI.ClampScroll(scroll, contentHeight, VIEWPORT)
    end

    return page
end

UI.pageBuilders.Activities = BuildActivities
