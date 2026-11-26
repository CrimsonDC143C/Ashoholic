--[[
    UI/Raids.lua - the Raids & Dungeons tab.

    Left: the watched-encounter matrix. One row per watched boss and one
    column per character of the visible accounts. Raid cells show the saved
    weekly loot status. Dungeon cells only say "Tracked": a dungeon entry is
    a planning note and never claims a kill or loot.

    Right: the tracking selection tree (category > expansion > instance >
    boss). The choices are saved through Data as the encounter watchlist.

    Everything shown comes from UI.model and the encounter helpers in
    UI/Model.lua; this file never reads game data or saved variables.

    Memory: matrix rows, header cells and selection rows are pooled and
    reused on every refresh. Cell tooltips need no frames of their own: a
    row works out which character column the mouse is over.
]]

local addonName = ...
local addon = _G[addonName]
local UI = addon.UI
local state = UI.state
-- Theme.lua changes the fields of this table in place when settings load.
local view = UI.raidView

local GOLD, MUTED, BORDER = UI.GOLD, UI.MUTED, UI.BORDER
local STYLE = UI.STYLE
local PAGE_HEIGHT, CONTENT_WIDTH = UI.PAGE_HEIGHT, UI.CONTENT_WIDTH

-- Layout from the approved preview.
local MATRIX_FIRST = 210                    -- x of the first character column
local MATRIX_HEIGHT = PAGE_HEIGHT - 194     -- matrix viewport height
local PICKER_WIDTH = 332
local PICKER_X = CONTENT_WIDTH - PICKER_WIDTH
local PICKER_HEIGHT = PAGE_HEIGHT - 169     -- selection viewport height
local PICKER_ROW_WIDTH = PICKER_WIDTH - UI.SCROLLBAR_WIDTH
local MATRIX_WITH_PICKER = PICKER_X - 24 - UI.SCROLLBAR_WIDTH

-- Cell text for every status (see UI.RaidStatus), in the two styles that
-- Settings > Icons offers. Dungeon cells read "Tracked" in both styles.
local TRACKED = "|cff6edbc7Tracked|r"
local STATUS_TEXT = {
    words = {
        Tracked = TRACKED,
        Unknown = UI.DIM .. "Unknown|r",
        Looted = UI.DIM .. "Looted|r",
        Available = UI.GREEN .. "Available|r",
    },
    icons = {
        Tracked = TRACKED,
        Unknown = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t",
        Looted = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t",
        Available = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t",
    },
}

-- "Normal ilvl 200 / Release 3" for a raid, when the catalogue has them.
local function RaidMetadata(instance)
    if instance.kind ~= "Raids" then
        return nil
    end
    local ilvl = instance.ilvl and ("Normal ilvl " .. instance.ilvl)
    local release = instance.release and ("Release " .. instance.release)
    if ilvl and release then
        return ilvl .. " / " .. release
    end
    return ilvl or release
end

-- How many bosses of a catalogue group are on the watchlist.
local function WatchedCount(node, watched)
    local count = 0
    for _, boss in ipairs(node.bosses) do
        if watched[boss.key] then
            count = count + 1
        end
    end
    return count
end

-- Tooltip for one matrix cell: one character and one boss.
local function CellTip(character, boss)
    local source, now = character.source, time()
    local status, endsAt = UI.RaidStatus(source, boss.id, now)
    UI.TipTitle(character.name .. " - " .. boss.name)
    if status == "Tracked" then
        UI.TipLine("Dungeon names are a watchlist, not recorded kills or loot.")
        UI.TipLine("Per-character dungeon status is not collected.")
    elseif status == "Unknown" then
        UI.TipLine("No complete raid loot update has been received for this character.")
        UI.TipLine("Log in on this character; opening Raid Info can request a fresh update.")
    else
        if status == "Looted" then
            UI.TipLine("Loot lock ends in", UI.RemainingTime(endsAt - now))
            UI.TipLine("Looted does not prevent entering or killing the boss.")
        else
            UI.TipLine(endsAt and "The reported loot lock has expired."
                or "No loot lock was reported in this snapshot.")
            UI.TipLine("Available does not guarantee access to this raid.")
        end
        UI.TipLine("Last received", UI.FormatLastSeen(source.raids.updatedAt), MUTED)
    end
    UI.TipLine("Saved status", status)
end

-------------------------------------------------------------------------------
-- Building the page (runs once, the first time the Raids tab is shown)
-------------------------------------------------------------------------------

local function BuildRaids(parent)
    local page = UI.Page(parent, "Raid & dungeon watchlist",
        "Select a category, expansion, instance or individual boss. Raid statuses are saved observations.")
    -- nil when ProjectEbonhold did not supply its raid list (see UI/Model.lua).
    local catalog = UI.EncounterCatalog()

    -- Worked out by Refresh; the tooltips and the mouse wheel use them too.
    local matrixWidth = MATRIX_WITH_PICKER
    local columnCount, columnWidth = 1, 95
    local visible = {}        -- character views of the visible accounts
    local shown = {}          -- the characters in the columns right now
    local refreshing = false  -- true while Refresh moves the slider itself

    local focusButton = UI.Button(page, "Focus encounters", PICKER_X - 164, 0, 156, 26, function()
        state.raidsFocus = not state.raidsFocus
        UI.Refresh()
    end)
    UI.Tip(focusButton, "Encounter Focus view", "Temporarily hide the currency cards to show more encounters "
        .. "and tracking choices. Your watchlist, column settings and account filters are kept.")
    local pickerToggle = UI.Button(page, "Hide selection", PICKER_X, 0, 160, 26, function()
        view.showPicker = not view.showPicker
        page.Refresh()
    end)
    local compactToggle = UI.Button(page, "Compact columns", PICKER_X + 168, 0, 164, 26, function()
        view.compact = not view.compact
        page.Refresh()
    end)
    UI.Tip(compactToggle, "Character columns", "Switch between compact and wider character columns.")

    UI.Label(page, "WATCHED ENCOUNTERS", 0, 61, 360, 10, GOLD)
    local position = UI.Label(page, "", MATRIX_WITH_PICKER - 140, 61, 140, 9, MUTED)
    local matrixScroll, matrix = UI.Scroll(page, "AshoholicLiveRaidMatrix", 0, 135,
        MATRIX_WITH_PICKER + UI.SCROLLBAR_WIDTH, MATRIX_HEIGHT)
    local header = UI.Surface(page, 0, 84, MATRIX_WITH_PICKER, 47)
    UI.Label(header, "ENCOUNTER", 7, 26, 198, 10, MUTED)
    local hint = UI.Label(page, "", 0, PAGE_HEIGHT - 50, 205, 9, MUTED)
    local empty = UI.Label(matrix, "", 8, 12, 670, 12, MUTED)
    local note = UI.Label(page, "Raids: saved weekly loot status; catalogue Normal ilvl and release shown "
        .. "when available. Dungeons: tracking only; no weekly loot lockout is assumed.",
        0, PAGE_HEIGHT - 26, CONTENT_WIDTH, 10, MUTED)

    ---------------------------------------------------------------------------
    -- Scrolling through characters (Shift + wheel or the slider)
    ---------------------------------------------------------------------------

    local hbar = CreateFrame("Slider", nil, page)
    hbar:SetPoint("TOPLEFT", MATRIX_FIRST, -(PAGE_HEIGHT - 52))
    hbar:SetSize(MATRIX_WITH_PICKER - MATRIX_FIRST - 6, 12)
    hbar:SetOrientation("HORIZONTAL")
    hbar:SetBackdrop(UI.Backdrop(1))
    hbar:SetBackdropColor(0.10, 0.11, 0.14, 1)
    hbar:SetBackdropBorderColor(unpack(BORDER))
    hbar:SetThumbTexture(UI.WHITE)
    hbar:GetThumbTexture():SetSize(70, 10)
    hbar:SetValueStep(1)
    hbar:SetMinMaxValues(0, 0)
    hbar:SetValue(0)

    local function ScrollCharacters(delta)
        local maximum = math.max(0, #visible - columnCount)
        local offset = math.max(0, math.min(maximum, view.matrixOffset - delta))
        if offset ~= view.matrixOffset then
            view.matrixOffset = offset
            page.Refresh()
        end
    end
    hbar:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if not refreshing and value ~= view.matrixOffset then
            view.matrixOffset = value
            page.Refresh()
        end
    end)
    local function CharacterWheel(_, delta)
        ScrollCharacters(delta)
    end
    hbar:EnableMouseWheel(true)
    hbar:SetScript("OnMouseWheel", CharacterWheel)
    header:EnableMouseWheel(true)
    header:SetScript("OnMouseWheel", CharacterWheel)
    matrixScroll:EnableMouseWheel(true)
    matrixScroll:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown() then
            ScrollCharacters(delta)
        else
            UI.ScrollBy(self, delta)
        end
    end)

    ---------------------------------------------------------------------------
    -- Tooltips that depend on the character column under the mouse
    ---------------------------------------------------------------------------

    -- Which character column (1 to columnCount) the mouse is over, or nil.
    -- GetCursorPosition uses screen pixels, so it is divided by the frame's
    -- scale to compare it with the frame's own position.
    local function HoveredColumn(frame)
        local left = frame:GetLeft()
        if not left then
            return nil
        end
        local x = GetCursorPosition() / frame:GetEffectiveScale() - left - MATRIX_FIRST
        if x < 0 then
            return nil
        end
        local column = math.floor(x / columnWidth) + 1
        if column > columnCount or not shown[column] then
            return nil
        end
        return column
    end

    -- While the mouse is over a row or the header, follow its column and
    -- redraw the tooltip when the column changes. The OnUpdate script only
    -- exists while the mouse is over that frame.
    local function FollowColumn(frame)
        local column = HoveredColumn(frame)
        if column ~= frame.hoverColumn then
            frame.hoverColumn = column
            UI.RefreshTip(frame)
        end
    end
    local function StartFollowing(frame)
        frame.hoverColumn = HoveredColumn(frame)
        frame:SetScript("OnUpdate", FollowColumn)
    end
    local function StopFollowing(frame)
        frame:SetScript("OnUpdate", nil)
        frame.hoverColumn = nil
    end
    -- Call after UI.TipProvider, which sets the OnEnter and OnLeave scripts.
    local function FollowColumns(frame)
        frame:HookScript("OnEnter", StartFollowing)
        frame:HookScript("OnLeave", StopFollowing)
        frame:HookScript("OnHide", StopFollowing)
    end

    UI.TipProvider(header, function(frame)
        local column = HoveredColumn(frame)
        local character = column and shown[column]
        if character then
            local raids = character.source.raids
            UI.TipTitle(character.name)
            UI.TipLine("Realm", character.realm)
            UI.TipLine("Account", character.account.name)
            UI.TipLine("Raid snapshot", UI.FormatLastSeen(raids and raids.updatedAt))
        else
            UI.TipTitle("Watched characters")
            UI.TipLine("Shift + mouse wheel scrolls sideways. Gold lines separate accounts; "
                .. "the account name appears once above its first visible character.")
        end
    end, "ANCHOR_CURSOR")
    FollowColumns(header)

    local function RowTip(row)
        local column = row.boss and HoveredColumn(row)
        if column then
            CellTip(shown[column], row.boss)
            return
        end
        UI.TipTitle(row.title)
        if row.category then
            UI.TipLine("Click to collapse or expand all watched " .. row.category.name
                .. ". Tracking selections are kept.")
        elseif row.instance.kind == "Dungeons" then
            UI.TipLine("Dungeon watchlist only. Tracked does not imply a weekly lockout or a recorded kill.")
        else
            UI.TipLine("Raid loot status is per character. Looted does not prevent entry. "
                .. "Unknown needs a fresh snapshot.")
            local metadata = RaidMetadata(row.instance)
            if metadata then
                UI.TipLine(metadata, nil, MUTED)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Pools
    ---------------------------------------------------------------------------

    local headerCells = {}
    local function HeaderCell(index)
        local cell = headerCells[index]
        if not cell then
            cell = {
                account = UI.Label(header, "", 0, 6, 80, 9, GOLD, "account"),
                name = UI.Label(header, "", 0, 26, 80, 11, STYLE.rowText, "character"),
                separator = header:CreateTexture(nil, "OVERLAY"),
            }
            cell.account:SetHeight(14)
            cell.name:SetHeight(14)
            UI.NoWrap(cell.account)
            UI.NoWrap(cell.name)
            cell.separator:SetTexture(UI.WHITE)
            cell.separator:SetSize(2, 39)
            headerCells[index] = cell
        end
        return cell
    end

    -- Clicking a category row folds it; the watchlist itself is unchanged.
    local function RowClick(row)
        local category = row.category
        if category then
            view.collapsed[category.key] = not view.collapsed[category.key] or nil
            page.Refresh()
        end
    end

    local matrixRows = {}
    local function MatrixRow(index)
        local row = matrixRows[index]
        if not row then
            row = UI.Button(matrix, "", 0, 0, 690, 25, RowClick)
            row.name = UI.Label(row, "", 7, 7, 198, 10)
            row.name:SetHeight(13)
            UI.NoWrap(row.name)
            row.metadata = UI.Label(row, "", 7, 19, 198, 9, MUTED)
            UI.NoWrap(row.metadata)
            row.cells = {}
            UI.TipProvider(row, RowTip, "ANCHOR_CURSOR")
            FollowColumns(row)
            matrixRows[index] = row
        end
        return row
    end

    ---------------------------------------------------------------------------
    -- Tracking selection (the tree on the right)
    ---------------------------------------------------------------------------

    local pickerTitle = UI.Label(page, "TRACKING SELECTION", PICKER_X, 61, PICKER_WIDTH, 10, GOLD)
    local watchAll = UI.Button(page, "Watch all", PICKER_X, 84, 105, 28, function()
        local watched = UI.Watchlist()
        for _, category in ipairs(catalog) do
            for _, boss in ipairs(category.bosses) do
                watched[boss.key] = true
            end
        end
        UI.SaveWatchlist()
        page.Refresh()
    end)
    local clear = UI.Button(page, "Clear", PICKER_X + 112, 84, 82, 28, function()
        wipe(UI.Watchlist())
        UI.SaveWatchlist()
        page.Refresh()
    end)
    local pickerHint = UI.Label(page, "+ expands groups", PICKER_X + 204, 92, 128, 10, MUTED)
    local pickerScroll, picker = UI.Scroll(page, "AshoholicLiveRaidPicker", PICKER_X, 127, PICKER_WIDTH, PICKER_HEIGHT)
    local pickerWidgets = { pickerTitle, watchAll, clear, pickerHint, pickerScroll }

    local function ExpandClick(button)
        local key = button:GetParent().node.key
        view.expanded[key] = not view.expanded[key] or nil
        page.Refresh()
    end
    local function SelectClick(button)
        local row = button:GetParent()
        local watched = UI.Watchlist()
        if row.boss then
            watched[row.boss.key] = not watched[row.boss.key] or nil
        else
            -- An unwatched or partly watched group becomes fully watched;
            -- a fully watched group is cleared.
            local selected = WatchedCount(row.node, watched) < #row.node.bosses
            for _, boss in ipairs(row.node.bosses) do
                watched[boss.key] = selected or nil
            end
        end
        UI.SaveWatchlist()
        page.Refresh()
    end
    local function PickerTip(button)
        local row = button:GetParent()
        if row.boss then
            UI.TipTitle(row.boss.name)
            if row.boss.id then
                UI.TipLine("Toggle tracking this raid boss in the encounter matrix.")
            else
                UI.TipLine("Toggle tracking this dungeon boss. Tracked catalogue entry only; "
                    .. "no dungeon kill or loot state is recorded.")
            end
        else
            local node = row.node
            UI.TipTitle(node.name)
            UI.TipLine(WatchedCount(node, UI.Watchlist()) .. " / " .. #node.bosses
                .. " bosses watched. Click to toggle this entire group.")
            local metadata = RaidMetadata(node)
            if metadata then
                UI.TipLine(metadata, nil, MUTED)
            end
        end
    end

    local pickerRows = {}
    local function PickerRow(index)
        local row = pickerRows[index]
        if not row then
            row = CreateFrame("Frame", nil, picker)
            row.expand = UI.Button(row, "+", 0, 0, 26, 25, ExpandClick)
            row.select = UI.Button(row, "", 30, 0, 276, 25, SelectClick)
            UI.TipProvider(row.select, PickerTip)
            pickerRows[index] = row
        end
        return row
    end

    -- Refresh places the visible tree entries one below the other.
    local pickerY, pickerCount = 0, 0
    local function PlacePickerRow(node, boss, depth)
        pickerCount = pickerCount + 1
        local row = PickerRow(pickerCount)
        local watched = UI.Watchlist()
        local width = PICKER_ROW_WIDTH - depth * 14
        row.node, row.boss = node, boss
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", depth * 14, -pickerY)
        row.select:ClearAllPoints()
        if boss then
            -- A boss: one button that toggles it.
            row:SetSize(width, 23)
            row.expand:Hide()
            row.select:SetPoint("TOPLEFT", 0, 0)
            row.select:SetSize(width, 23)
            row.select.text:SetText((watched[boss.key] and "[x] " or "[ ] ") .. boss.name)
            pickerY = pickerY + 25
        else
            -- A group: + or - folds it, the name selects all of its bosses.
            local count = WatchedCount(node, watched)
            row:SetSize(width, 28)
            row.expand:Show()
            row.expand.text:SetText(view.expanded[node.key] and "-" or "+")
            row.select:SetPoint("TOPLEFT", 30, 0)
            row.select:SetSize(width - 30, 25)
            row.select.text:SetText((count == 0 and "[ ] " or (count == #node.bosses and "[x] " or "[-] "))
                .. node.name)
            pickerY = pickerY + 28
        end
        row.select.text:SetWidth(row.select:GetWidth() - 18)
        row:Show()
        UI.RefreshTip(row.select)
    end

    -- Groups without bosses (for example an expansion without raids) are skipped.
    local function PlacePickerNode(node, depth)
        if #node.bosses == 0 then
            return
        end
        PlacePickerRow(node, nil, depth)
        if not view.expanded[node.key] then
            return
        end
        if node.children then
            for _, child in ipairs(node.children) do
                PlacePickerNode(child, depth + 1)
            end
        else
            for _, boss in ipairs(node.bosses) do
                PlacePickerRow(node, boss, depth + 1)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Matrix rows
    ---------------------------------------------------------------------------

    local matrixY, matrixCount = 0, 0
    local statusTexts, now = STATUS_TEXT.words, 0

    -- text is what the row shows; title is the plain name for its tooltip.
    local function AddMatrixRow(text, title, category, instance, boss)
        matrixCount = matrixCount + 1
        local row = MatrixRow(matrixCount)
        local metadata = instance and not boss and RaidMetadata(instance)
        local height = metadata and 38 or 28
        row.category, row.instance, row.boss, row.title = category, instance, boss, title
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -matrixY)
        row:SetSize(matrixWidth, height)
        row.name:SetText(text)
        row.metadata:SetText(metadata or "")
        UI.SetVisible(row.metadata, metadata)

        -- Character cells exist only on boss rows. Cell labels are created
        -- the first time a row needs that many columns, then reused.
        local cellCount = boss and columnCount or 0
        for index = 1, cellCount do
            local cell = row.cells[index]
            if not cell then
                cell = UI.Label(row, "", 0, 7, 80, 10, STYLE.rowText, "character")
                UI.NoWrap(cell)
                row.cells[index] = cell
            end
            local character = shown[index]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", MATRIX_FIRST + (index - 1) * columnWidth, -7)
            cell:SetWidth(columnWidth - 8)
            cell:SetText(character and statusTexts[UI.RaidStatus(character.source, boss.id, now)] or "")
            cell:Show()
        end
        for index = cellCount + 1, #row.cells do
            row.cells[index]:Hide()
        end
        row:Show()
        UI.RefreshTip(row)
        matrixY = matrixY + height
    end

    ---------------------------------------------------------------------------
    -- Refresh: redraw everything from UI.model and the watchlist.
    ---------------------------------------------------------------------------

    page.Refresh = function()
        local watched = UI.Watchlist()
        local gain = state.raidsFocus and UI.FOCUS_HEIGHT_GAIN or 0
        local matrixHeight, pickerHeight = MATRIX_HEIGHT + gain, PICKER_HEIGHT + gain
        local showPicker = view.showPicker and catalog ~= nil
        statusTexts = STATUS_TEXT[state.statusStyle] or STATUS_TEXT.words
        now = time()

        focusButton.text:SetText(state.raidsFocus and "Exit Focus" or "Focus encounters")
        pickerToggle.text:SetText(view.showPicker and "Hide selection" or "Show selection")
        compactToggle.text:SetText(view.compact and "[x] Compact columns" or "[ ] Compact columns")
        matrixScroll:SetHeight(matrixHeight)
        pickerScroll:SetHeight(pickerHeight)
        hbar:ClearAllPoints()
        hbar:SetPoint("TOPLEFT", MATRIX_FIRST, -(PAGE_HEIGHT - 52 + gain))
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", 0, -(PAGE_HEIGHT - 50 + gain))
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", 0, -(PAGE_HEIGHT - 26 + gain))
        for _, widget in ipairs(pickerWidgets) do
            UI.SetVisible(widget, showPicker)
        end

        -- The matrix fills the space the selection tree leaves free. Columns
        -- keep a compact (80) or wide (110) minimum width.
        matrixWidth = showPicker and MATRIX_WITH_PICKER or UI.SCROLL_WIDTH
        columnCount = math.max(1, math.floor((matrixWidth - MATRIX_FIRST) / (view.compact and 80 or 110)))
        columnWidth = (matrixWidth - MATRIX_FIRST) / columnCount
        matrixScroll:SetWidth(matrixWidth)
        matrix:SetWidth(matrixWidth)
        header:SetWidth(matrixWidth)
        position:ClearAllPoints()
        position:SetPoint("TOPLEFT", matrixWidth - 140, -61)
        hbar:SetWidth(matrixWidth - MATRIX_FIRST - 6)

        -- Characters of the visible accounts, then the ones in the columns.
        wipe(visible)
        for _, character in ipairs(UI.model.characters) do
            if character.account.visible then
                visible[#visible + 1] = character
            end
        end
        local maxOffset = math.max(0, #visible - columnCount)
        view.matrixOffset = math.min(view.matrixOffset, maxOffset)
        local offset = view.matrixOffset
        wipe(shown)
        for index = 1, columnCount do
            shown[index] = visible[offset + index]
        end

        -- Character names, with each account name once above its characters.
        for index = 1, columnCount do
            local cell = HeaderCell(index)
            local character = shown[index]
            local x = MATRIX_FIRST + (index - 1) * columnWidth
            cell.name:ClearAllPoints()
            cell.name:SetPoint("TOPLEFT", x, -26)
            cell.name:SetWidth(columnWidth - 6)
            cell.name:SetText(character and UI.ClassName(character) or "")
            cell.name:Show()
            cell.account:ClearAllPoints()
            cell.account:SetPoint("TOPLEFT", x, -6)
            cell.account:SetText("")
            cell.account:Show()
            if character then
                local previous = visible[offset + index - 1]
                if index == 1 or previous.account ~= character.account then
                    local span = 1
                    while shown[index + span] and shown[index + span].account == character.account do
                        span = span + 1
                    end
                    -- "<" shows that earlier characters of this account are scrolled away.
                    local continued = previous and previous.account == character.account
                    cell.account:SetWidth(span * columnWidth - 10)
                    cell.account:SetText((continued and "< " or "") .. string.upper(character.account.name))
                    UI.Paint(cell.account, character.account.color or GOLD)
                end
            end
            -- A gold line after the last character of an account.
            local nextCharacter = visible[offset + index + 1]
            cell.separator:ClearAllPoints()
            cell.separator:SetPoint("TOPLEFT", MATRIX_FIRST + index * columnWidth - 6, -4)
            cell.separator:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
            UI.SetVisible(cell.separator, character and nextCharacter and nextCharacter.account ~= character.account)
        end
        for index = columnCount + 1, #headerCells do
            local cell = headerCells[index]
            cell.account:Hide()
            cell.name:Hide()
            cell.separator:Hide()
        end
        UI.RefreshTip(header)

        refreshing = true
        hbar:SetMinMaxValues(0, maxOffset)
        hbar:SetValue(offset)
        refreshing = false
        hbar:SetBackdropBorderColor(unpack(BORDER))
        hbar:GetThumbTexture():SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.75)
        UI.SetVisible(hbar, maxOffset > 0)
        if #visible == 0 then
            position:SetText("No visible characters")
        else
            position:SetText(string.format("%d-%d of %d", offset + 1, math.min(#visible, offset + columnCount), #visible))
        end
        hint:SetText(maxOffset > 0 and "Shift + wheel: characters" or "All selected characters fit")

        -- Matrix: category > instance > watched bosses.
        matrixY, matrixCount = 0, 0
        if catalog then
            for _, category in ipairs(catalog) do
                if WatchedCount(category, watched) > 0 then
                    local collapsed = view.collapsed[category.key]
                    AddMatrixRow((collapsed and "+ " or "- ") .. category.name, category.name, category)
                    if not collapsed then
                        for _, group in ipairs(category.children) do
                            if WatchedCount(group, watched) > 0 then
                                for _, instance in ipairs(group.children) do
                                    if WatchedCount(instance, watched) > 0 then
                                        AddMatrixRow(UI.AMBER .. instance.name .. "|r", instance.name, nil, instance)
                                        for _, boss in ipairs(instance.bosses) do
                                            if watched[boss.key] then
                                                AddMatrixRow(boss.name, boss.name, nil, instance, boss)
                                            end
                                        end
                                        matrixY = matrixY + 8
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        for index = matrixCount + 1, #matrixRows do
            local row = matrixRows[index]
            row:Hide()
            row.category, row.instance, row.boss = nil, nil, nil
        end
        if not catalog then
            empty:SetText("The encounter catalogue is unavailable: ProjectEbonhold did not supply its raid list. "
                .. "Update or enable it, then reload.")
        elseif view.showPicker then
            empty:SetText("Nothing selected. Choose instances or bosses on the right.")
        else
            empty:SetText("Nothing selected. Show selection to choose encounters.")
        end
        UI.SetVisible(empty, matrixCount == 0)
        matrix:SetHeight(math.max(matrixHeight, matrixY))
        UI.ClampScroll(matrixScroll, matrixY, matrixHeight)

        if showPicker then
            pickerY, pickerCount = 0, 0
            for _, category in ipairs(catalog) do
                PlacePickerNode(category, 0)
            end
            for index = pickerCount + 1, #pickerRows do
                pickerRows[index]:Hide()
            end
            picker:SetHeight(math.max(pickerHeight, pickerY))
            UI.ClampScroll(pickerScroll, pickerY, pickerHeight)
        end
    end

    return page
end

UI.pageBuilders.Raids = BuildRaids
