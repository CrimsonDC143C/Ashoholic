--[[
    UI/Roster.lua - the Roster tab.

    One row per saved character, grouped by account (current account first).
    The player chooses the columns (Settings > Roster Columns), sorts by
    clicking a column header and resizes a column by dragging its header
    edge. The panel on the right shows the selected character's parked run.

    Everything shown comes from UI.model (UI/Model.lua); this file never
    reads game data or saved variables.

    Memory: rows and account headers are pooled. They are created the first
    time they are needed and reused on every refresh, because WoW never
    frees frames. Unused pooled rows are only hidden.
]]

local addonName = ...
local addon = _G[addonName]
local UI = addon.UI
local state = UI.state

local GOLD, MUTED, TEAL = UI.GOLD, UI.MUTED, UI.TEAL
local BORDER, BUTTON_BG = UI.BORDER, UI.BUTTON_BG
local STYLE = UI.STYLE
local WINDOW_WIDTH, PAGE_HEIGHT = UI.WINDOW_WIDTH, UI.PAGE_HEIGHT

-- Height of the row list while the currency cards are shown.
local NORMAL_VIEWPORT = PAGE_HEIGHT - 130
-- One cell for the character name plus one for every optional column.
local CELL_COUNT = #UI.COLUMNS + 1
-- Saved column widths stay inside the range Theme.lua accepts on load.
local MAX_COLUMN_WIDTH = 2000

local SORT_TIP = "Click: ascending, descending, then unsorted. Add a second column to break ties. "
    .. "A third distinct column starts a new sort. Sorting stays within each account; "
    .. "^ / v show direction and 1 / 2 show priority."
local RESIZE_TIP = "Drag this header edge. Right-click to reset its default width. "
    .. "The minimum fits the widest saved value or header, including hidden accounts."
local DETAIL_TITLES = {
    "Run Soul Ash", "Run Soul Shards", "Offering bonus", "Offerings remaining",
    "Echo build", "Soul anchor", "Selected Torment", "Account access",
}

-------------------------------------------------------------------------------
-- Sorting
-------------------------------------------------------------------------------

-- Clicking a header cycles that column: ascending -> descending -> removed.
-- Two columns can sort together; a third column starts a new sort.
local function CycleSort(key)
    local sorts = state.rosterSort
    for index, sort in ipairs(sorts) do
        if sort.key == key then
            if sort.ascending then
                sort.ascending = false
            else
                table.remove(sorts, index)
            end
            return
        end
    end
    if #sorts == 2 then
        wipe(sorts)
    end
    sorts[#sorts + 1] = { key = key, ascending = true }
end

-- Unknown values (nil) stay last in both directions. Rows that compare
-- equal keep Data's order (realm, then name), stored in character.order.
local function CompareCharacters(left, right)
    for _, sort in ipairs(state.rosterSort) do
        local a, b = left.sortValues[sort.key], right.sortValues[sort.key]
        if a ~= b then
            if a == nil then
                return false
            elseif b == nil then
                return true
            elseif sort.ascending then
                return a < b
            end
            return a > b
        end
    end
    return left.order < right.order
end

-------------------------------------------------------------------------------
-- Actions and tooltips
-------------------------------------------------------------------------------

-- FastSwap explains in chat when a swap is not possible (other account,
-- other realm, the character you are playing, or FastSwap not enabled).
local function Swap(character)
    if character then
        addon.Integrations.FastSwap.Swap(character.account.source, character.source)
    end
end

-- Row tooltip: how old each saved observation of this character is.
local function RowTip(row)
    local character = row.character
    if not character then
        return
    end
    local source = character.source
    UI.TipTitle(character.name .. " / observation ages")
    UI.TipLine("Character basics", UI.FormatLastSeen(source.lastSeen))
    UI.TipLine("Equipped item level", UI.FormatLastSeen(source.itemLevelUpdatedAt))
    UI.TipLine("Run currencies", UI.FormatLastSeen(source.runUpdatedAt))
    UI.TipLine("Offerings / Soul Anchor", UI.FormatLastSeen(source.contracts and source.contracts.updatedAt))
    UI.TipLine("Echo build", UI.FormatLastSeen(source.echoBuild and source.echoBuild.updatedAt))
    UI.TipLine("Shared Torment access", UI.FormatLastSeen(source.torment and source.torment.accessUpdatedAt))
end

-- Detail line tooltip: when that one value was observed.
local function DetailTip(widget)
    local character = widget.character
    if not character then
        return
    end
    UI.TipTitle(character.name .. " / saved detail")
    UI.TipLine("Updated", UI.FormatLastSeen(character.detailTimes[widget.index]))
    if widget.index == 8 then
        UI.TipLine("Access is shared account-wide.")
    else
        UI.TipLine("Last saved observation; offline values cannot refresh themselves.")
    end
end

-------------------------------------------------------------------------------
-- Building the page (runs once, the first time the Roster tab is shown)
-------------------------------------------------------------------------------

local function BuildRoster(parent)
    local page = UI.Page(parent, "Your next adventure",
        "Characters first. Shared currencies stay at account level; run earnings stay with the character.")

    page.focusButton = UI.Button(page, "Focus roster", UI.CONTENT_WIDTH - 140, 0, 140, 26, function()
        state.rosterFocus = not state.rosterFocus
        UI.Refresh()
    end)
    UI.Tip(page.focusButton, "Roster Focus view", "Temporarily hide the currency cards and use compact rows "
        .. "for more characters. Exit Focus restores your normal layout and density.")

    -- The header row scrolls sideways together with the rows below it.
    local headerScroll = CreateFrame("ScrollFrame", nil, page)
    headerScroll:SetPoint("TOPLEFT", 0, -57)
    headerScroll:SetSize(690, 23)
    local headerBody = CreateFrame("Frame", nil, headerScroll)
    headerBody:SetSize(690, 23)
    headerScroll:SetScrollChild(headerBody)

    -- An invisible font string used only to measure text widths.
    local measure = page:CreateFontString(nil, "OVERLAY")
    measure:Hide()
    local function MeasureText(text)
        measure:SetText(text)
        return math.ceil(measure:GetStringWidth()) + 22
    end

    -- Measuring every value is the slowest part of a refresh, so each
    -- column's minimum width is cached until the data, the fonts or the
    -- class-icon setting change.
    local minimums, minimumSignature = {}, nil
    local function ColumnMinimum(key, title)
        local signature = UI.model.stamp .. "/" .. (UI.measureStamp or 0) .. "/" .. tostring(state.classIcons)
        if signature ~= minimumSignature then
            wipe(minimums)
            minimumSignature = signature
        end
        local minimum = minimums[key]
        if not minimum then
            UI.ApplyFont(measure, "header", 10)
            minimum = MeasureText(title .. " v2")
            UI.ApplyFont(measure, "character", 11)
            for _, character in ipairs(UI.model.characters) do
                local text = key == "character" and UI.ClassName(character) or character.values[key]
                minimum = math.max(minimum, MeasureText(text))
            end
            minimums[key] = minimum
        end
        return minimum
    end

    local function HeaderClick(header)
        CycleSort(header.columnKey)
        page.Refresh()
    end

    -- Column resizing: while the left button is held, OnUpdate follows the
    -- cursor. The script is removed again on release or when hidden, so no
    -- per-frame work remains afterwards.
    local function ResizeUpdate(grip)
        local cursor = GetCursorPosition() / grip:GetEffectiveScale()
        local width = math.floor(grip.startWidth + cursor - grip.startX + 0.5)
        width = math.min(MAX_COLUMN_WIDTH, math.max(grip.minimum, width))
        if width ~= state.columnWidths[grip.key] then
            state.columnWidths[grip.key] = width
            page.Refresh()
        end
    end
    local function StopResize(grip)
        grip:SetScript("OnUpdate", nil)
    end
    local function GripDown(grip, button)
        if button == "RightButton" then
            StopResize(grip)
            state.columnWidths[grip.key] = nil
            page.Refresh()
        elseif button == "LeftButton" then
            grip.startX = GetCursorPosition() / grip:GetEffectiveScale()
            grip.startWidth = grip.width
            grip:SetScript("OnUpdate", ResizeUpdate)
        end
    end

    page.headers, page.headerButtons, page.grips = {}, {}, {}
    for index = 1, CELL_COUNT do
        local header = CreateFrame("Button", nil, headerBody)
        header:SetHeight(23)
        header:SetScript("OnClick", HeaderClick)
        UI.Tip(header, "Sort column", SORT_TIP)
        page.headerButtons[index] = header

        local label = UI.Label(headerBody, "", 0, 4, 100, 10, STYLE.headerText, "header")
        label:SetHeight(16)
        UI.NoWrap(label)
        page.headers[index] = label

        local grip = CreateFrame("Button", nil, headerBody)
        grip:SetFrameLevel(header:GetFrameLevel() + 1)
        grip:SetSize(8, 23)
        grip.line = grip:CreateTexture(nil, "OVERLAY")
        grip.line:SetTexture(UI.WHITE)
        grip.line:SetSize(1, 16)
        grip.line:SetPoint("CENTER")
        grip.line:SetVertexColor(unpack(MUTED))
        UI.Tip(grip, "Resize column", RESIZE_TIP)
        grip:SetScript("OnMouseDown", GripDown)
        grip:SetScript("OnMouseUp", StopResize)
        grip:SetScript("OnHide", StopResize)
        page.grips[index] = grip
    end

    local scroll, body = UI.Scroll(page, "AshoholicLiveRosterScroll", 0, 84, 716, NORMAL_VIEWPORT)

    -- Horizontal scroll bar, shown only when the columns are wider than the list.
    local hbar = CreateFrame("Slider", nil, page)
    hbar:SetPoint("TOPLEFT", 0, -(84 + NORMAL_VIEWPORT + 4))
    hbar:SetSize(690, 10)
    hbar:SetOrientation("HORIZONTAL")
    hbar:SetBackdrop(UI.Backdrop(1))
    hbar:SetBackdropColor(unpack(BUTTON_BG))
    hbar:SetThumbTexture(UI.WHITE)
    hbar:GetThumbTexture():SetSize(70, 10)
    hbar:GetThumbTexture():SetVertexColor(unpack(GOLD))
    hbar:SetValueStep(1)
    hbar:SetMinMaxValues(0, 0)
    hbar:SetValue(0)
    hbar:SetScript("OnValueChanged", function(_, value)
        state.rosterOffset = value
        headerScroll:SetHorizontalScroll(value)
        scroll:SetHorizontalScroll(value)
    end)

    -- Mouse wheel scrolls rows; Shift + wheel scrolls the columns sideways.
    local function Wheel(_, delta)
        if IsShiftKeyDown() then
            local minimum, maximum = hbar:GetMinMaxValues()
            hbar:SetValue(math.max(minimum, math.min(maximum, hbar:GetValue() - delta * 40)))
        else
            UI.ScrollBy(scroll, delta)
        end
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", Wheel)
    headerScroll:EnableMouseWheel(true)
    headerScroll:SetScript("OnMouseWheel", Wheel)

    -- Pools. row.character and label.account point at the view each pooled
    -- frame currently shows; the click handlers read them.
    page.rows, page.accountLabels = {}, {}

    local function RowClick(row)
        if row.character then
            state.selectedKey = row.character.key
            UI.Refresh()
        end
    end
    local function RowSwap(button)
        Swap(button:GetParent().character)
    end
    local function NewRow()
        local row = UI.Button(body, "", 0, 0, 690, 44, RowClick)
        row.cells = {}
        for index = 1, CELL_COUNT do
            local cell = UI.Label(row, "", 0, 8, 85, 11, STYLE.rowText, "character")
            cell:SetHeight(14)
            UI.NoWrap(cell)
            row.cells[index] = cell
        end
        row.hint = UI.Label(row, "", 12, 27, 680, 10, MUTED)
        row.swap = UI.Button(row, "Swap", 620, 5, 60, 24, RowSwap)
        UI.Tip(row.swap, "Swap character",
            "Switch on the current account and realm using FastSwap. Its separate selection hook must be installed.")
        UI.TipProvider(row, RowTip, "ANCHOR_BOTTOM")
        return row
    end

    local function AccountClick(label)
        if label.account then
            UI.SetAccountCollapsed(label.account, not label.account.collapsed)
            UI.Refresh()
        end
    end
    local function NewAccountLabel()
        local label = UI.Button(body, "", 0, 0, 690, 25, AccountClick)
        -- Account names use the "account" font role instead of the button role.
        UI.labels[label.text].role = "account"
        UI.ApplyFont(label.text, "account", 11)
        return label
    end

    -- Shown when there is nothing to list.
    page.empty = UI.Label(body, "", 12, 0, 660, 11, MUTED)

    -- The detail panel for the selected character.
    local detail = UI.Surface(page, WINDOW_WIDTH - 380, 56, 332, PAGE_HEIGHT - 66)
    detail.title = UI.Label(detail, "", 16, 16, 300, 17)
    detail.location = UI.Label(detail, "", 16, 42, 300, 11, MUTED)
    UI.Label(detail, "PARKED RUN", 16, 75, 300, 10, GOLD)
    detail.values, detail.tips = {}, {}
    for index, title in ipairs(DETAIL_TITLES) do
        detail.values[index] = UI.DetailLine(detail, title, "", 101 + (index - 1) * 28)
        -- An invisible frame over the line shows when the value was observed.
        local tip = CreateFrame("Frame", nil, detail)
        tip:SetPoint("TOPLEFT", 16, -(98 + (index - 1) * 28))
        tip:SetSize(300, 24)
        tip.index = index
        UI.TipProvider(tip, DetailTip, "ANCHOR_BOTTOM")
        detail.tips[index] = tip
    end
    detail.note = UI.Label(detail, "", 16, detail:GetHeight() - 76, 300, 11, TEAL)
    UI.Button(detail, "Swap", 16, detail:GetHeight() - 37, 130, 25, function()
        Swap(UI.SelectedCharacter())
    end)

    page.note = UI.Label(page, "No hourly-entry counter: the new realm's cap has not been established.",
        0, PAGE_HEIGHT - 29, UI.SCROLL_WIDTH, 10, MUTED)

    -- Reused layout tables: one per cell position.
    local layout = {}
    for index = 1, CELL_COUNT do
        layout[index] = {}
    end
    local sorted = {}

    local function PositionCell(fontString, cell, y)
        fontString:ClearAllPoints()
        fontString:SetPoint("TOPLEFT", cell.x + 10, -y)
        fontString:SetWidth(cell.width - 16)
    end

    ---------------------------------------------------------------------------
    -- Refresh: redraw everything from UI.model. Called when the tab is shown,
    -- after data changes, sorting, resizing and selection.
    ---------------------------------------------------------------------------
    page.Refresh = function()
        local model = UI.model
        local focus = state.rosterFocus
        local viewport = NORMAL_VIEWPORT + (focus and UI.FOCUS_HEIGHT_GAIN or 0)
        local density = focus and "compact" or state.density
        page.focusButton.text:SetText(focus and "Exit Focus" or "Focus roster")
        scroll:SetHeight(viewport)
        hbar:ClearAllPoints()
        hbar:SetPoint("TOPLEFT", 0, -(84 + viewport + 4))
        page.note:ClearAllPoints()
        page.note:SetPoint("TOPLEFT", 0, -(84 + viewport + 17))

        local selected = UI.SelectedCharacter()
        local width = WINDOW_WIDTH - (state.detail and 430 or 74)
        scroll:SetWidth(width)
        headerScroll:SetWidth(width)
        hbar:SetWidth(width)
        UI.SetVisible(detail, state.detail and selected ~= nil)

        -- Column positions: the character name first, then the chosen columns.
        local contentWidth = 0
        for index = 1, CELL_COUNT do
            local cell = layout[index]
            local key = index == 1 and "character" or UI.columnOrder[index - 1]
            cell.used = key ~= nil
            if key then
                local title = index == 1 and "CHARACTER" or UI.COLUMN_TITLES[key]
                local displayTitle = title
                for priority, sort in ipairs(state.rosterSort) do
                    if sort.key == key then
                        displayTitle = title .. (sort.ascending and " ^" or " v") .. priority
                    end
                end
                local minimum = ColumnMinimum(key, title)
                cell.key, cell.x, cell.minimum, cell.title = key, contentWidth, minimum, displayTitle
                cell.width = math.max(minimum, state.columnWidths[key] or (index == 1 and 150 or 85))
                contentWidth = contentWidth + cell.width
            end
        end
        contentWidth = math.max(width, contentWidth + 76)
        body:SetWidth(contentWidth)
        headerBody:SetWidth(contentWidth)

        local maximum = math.max(0, contentWidth - width)
        state.rosterOffset = math.min(state.rosterOffset, maximum)
        hbar:SetMinMaxValues(0, maximum)
        hbar:SetValue(state.rosterOffset)
        headerScroll:SetHorizontalScroll(state.rosterOffset)
        scroll:SetHorizontalScroll(state.rosterOffset)
        hbar:SetBackdropColor(unpack(BUTTON_BG))
        hbar:GetThumbTexture():SetVertexColor(unpack(GOLD))
        UI.SetVisible(hbar, maximum > 0)

        for index = 1, CELL_COUNT do
            local cell = layout[index]
            local label, header, grip = page.headers[index], page.headerButtons[index], page.grips[index]
            UI.SetVisible(label, cell.used)
            UI.SetVisible(header, cell.used)
            UI.SetVisible(grip, cell.used)
            if cell.used then
                PositionCell(label, cell, 4)
                label:SetText(cell.title)
                header.columnKey = cell.key
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", cell.x, 0)
                header:SetWidth(cell.width - 4)
                grip.key, grip.minimum, grip.width = cell.key, cell.minimum, cell.width
                grip:ClearAllPoints()
                grip:SetPoint("TOPLEFT", cell.x + cell.width - 4, 0)
                grip.line:SetVertexColor(unpack(MUTED))
            end
        end

        -- Row height follows the density, unless Customize Layout set one.
        -- It always leaves room for the character font.
        local rowHeight = focus and 30 or state.rowHeight
            or (density == "compact" and 30 or (density == "spacious" and 54 or 44))
        local _, characterSize = UI.FontFor("character", 11)
        local _, accountSize = UI.FontFor("account", 11)
        rowHeight = math.max(rowHeight, characterSize + (density == "compact" and 16 or 33))
        local cellY = density == "spacious" and 11 or 8

        local y, rowCount, labelCount, selectedY = 0, 0, 0, nil
        local hasCharacters = false
        for _, account in ipairs(model.accounts) do
            if account.visible then
                hasCharacters = hasCharacters or #account.characters > 0
                labelCount = labelCount + 1
                local label = page.accountLabels[labelCount] or NewAccountLabel()
                page.accountLabels[labelCount] = label
                label.account = account
                label:ClearAllPoints()
                label:SetPoint("TOPLEFT", 0, -y)
                label:SetWidth(contentWidth)
                label.text:SetWidth(contentWidth - 18)
                label.text:SetHeight(accountSize + 3)
                label.text:SetText((account.collapsed and "+ " or "- ") .. account.name
                    .. (account.isCurrent and "  /  Current account" or ""))
                label:SetBackdropColor(unpack(STYLE.rowAccount))
                UI.Paint(label.text, account.color or STYLE.accountText)
                label:Show()
                y = y + 28

                if not account.collapsed then
                    wipe(sorted)
                    for index, character in ipairs(account.characters) do
                        character.order = index
                        sorted[index] = character
                    end
                    table.sort(sorted, CompareCharacters)
                    for position, character in ipairs(sorted) do
                        rowCount = rowCount + 1
                        local row = page.rows[rowCount] or NewRow()
                        page.rows[rowCount] = row
                        row.character = character
                        row:SetWidth(contentWidth)
                        row:SetHeight(rowHeight)
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", 0, -y)
                        row.swap:ClearAllPoints()
                        row.swap:SetPoint("TOPRIGHT", -8, -5)
                        row.hint:SetWidth(contentWidth - 90)
                        row:SetBackdropColor(unpack(position % 2 == 1 and STYLE.rowOdd or STYLE.rowEven))
                        row:GetHighlightTexture():SetVertexColor(unpack(STYLE.rowHover))
                        row:SetBackdropBorderColor(unpack(character == selected and STYLE.selectedBorder or BORDER))
                        if character == selected then
                            selectedY = y
                        end
                        for index, cellLabel in ipairs(row.cells) do
                            local cell = layout[index]
                            UI.SetVisible(cellLabel, cell.used)
                            if cell.used then
                                PositionCell(cellLabel, cell, cellY)
                                cellLabel:SetHeight(characterSize + 3)
                                cellLabel:SetText(index == 1 and UI.ClassName(character) or character.values[cell.key])
                            end
                        end
                        row.hint:SetText(character.action)
                        UI.SetVisible(row.hint, density ~= "compact")
                        row:Show()
                        UI.RefreshTip(row)
                        y = y + rowHeight + state.rowGap
                    end
                end
            end
        end

        -- Hide pooled frames that are not needed this time.
        for index = rowCount + 1, #page.rows do
            page.rows[index]:Hide()
            page.rows[index].character = nil
        end
        for index = labelCount + 1, #page.accountLabels do
            page.accountLabels[index]:Hide()
            page.accountLabels[index].account = nil
        end

        if labelCount == 0 then
            page.empty:SetText("No visible accounts. Choose accounts with the account filter above.")
        elseif not hasCharacters then
            page.empty:SetText("No saved characters yet. A character appears after logging in once with Ashoholic enabled.")
        else
            page.empty:SetText("")
        end
        page.empty:ClearAllPoints()
        page.empty:SetPoint("TOPLEFT", 12, -(y + 8))

        body:SetHeight(math.max(viewport, y))
        scroll:UpdateScrollChildRect()
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, y - viewport)))
        -- Once per session, scroll the player's own row into view.
        if not page.scrolledToPlayer and selected and selected.isPlayer and selectedY then
            scroll:SetVerticalScroll(math.min(selectedY, math.max(0, y - viewport)))
            page.scrolledToPlayer = true
        end

        if selected then
            detail.title:SetText(UI.ClassName(selected))
            detail.location:SetText(selected.location .. "  /  " .. selected.seen)
            for index, valueLabel in ipairs(detail.values) do
                valueLabel:SetText(selected.detail[index])
                detail.tips[index].character = selected
                UI.RefreshTip(detail.tips[index])
            end
            detail.note:SetText(selected.action)
        end
    end

    return page
end

UI.pageBuilders.Roster = BuildRoster
