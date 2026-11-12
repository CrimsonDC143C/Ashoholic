-- The live version of the preview's encounter matrix and selection tree.
-- Raid cells use saved observations; dungeon names are a watchlist only.
local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local UI = addon.UI

if not Data or not UI then
    error("Ashoholic UI/Raids.lua loaded before the data or UI modules.")
end

local Style = UI.Style
local PICKER_WIDTH = 332
local SCROLLBAR_WIDTH = 26
local FIRST_COLUMN = 210
local PICKER_ROW_HEIGHT = 27
local LOOTED_COLOR = { 1, 0.45, 0.40, 1 }

local function SetVisible(widget, visible)
    if visible then
        widget:Show()
    else
        widget:Hide()
    end
end

local function LeftAlign(button)
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", 8, 0)
    button.text:SetPoint("RIGHT", -8, 0)
    button.text:SetJustifyH("LEFT")
    if button.text.SetWordWrap then
        button.text:SetWordWrap(false)
    end
end

local function AddTip(widget, title, text)
    UI.AttachTooltip(widget)
    local lines = {}
    UI.AddTooltipLine(lines, text)
    UI.RefreshTooltip(widget, title, lines)
end

local function CreateScroll(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll.content = content
    scroll:EnableMouseWheel(true)
    return scroll
end

local function ScrollVertically(scroll, delta)
    local nextOffset = scroll:GetVerticalScroll() - delta * 70
    scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(), nextOffset)))
end

local function WatchedCount(node, watched)
    local count = 0
    for _, boss in ipairs(node.bosses) do
        if watched[boss.key] then
            count = count + 1
        end
    end
    return count
end

local function SaveWatchlist(page)
    Data.SaveEncounterWatchlist(page.watched)
    UI.RefreshRaids(page, page.roster)
end

local function ScrollCharacters(page, delta)
    local maximum = math.max(0, #page.characters - page.columnCount)
    local offset = math.max(0, math.min(maximum, page.matrixOffset - delta))
    if offset ~= page.matrixOffset then
        page.matrixOffset = offset
        UI.RefreshRaids(page, page.roster)
    end
end

local function MatrixWheel(page, scroll, delta)
    if IsShiftKeyDown() then
        ScrollCharacters(page, delta)
    else
        ScrollVertically(scroll, delta)
    end
end

local function CreatePickerRow(page)
    local row = CreateFrame("Frame", nil, page.pickerScroll.content)
    row:SetHeight(PICKER_ROW_HEIGHT)
    row.expand = UI.AddTextButton(row, "+", 26, 25, function()
        page.expanded[row.node.key] = not page.expanded[row.node.key]
        UI.RefreshRaids(page, page.roster)
    end)
    row.expand:SetPoint("TOPLEFT", 0, 0)
    row.select = UI.AddTextButton(row, "", 200, 25, function()
        if row.boss then
            local key = row.boss.key
            if page.watched[key] then
                page.watched[key] = nil
            else
                page.watched[key] = true
            end
        else
            local selectAll = WatchedCount(row.node, page.watched) < #row.node.bosses
            for _, boss in ipairs(row.node.bosses) do
                page.watched[boss.key] = selectAll and true or nil
            end
        end
        SaveWatchlist(page)
    end)
    row.select:SetPoint("TOPLEFT", 30, 0)
    LeftAlign(row.select)
    UI.AttachTooltip(row.select)
    for _, widget in ipairs({ row, row.expand, row.select }) do
        widget:EnableMouseWheel(true)
        widget:SetScript("OnMouseWheel", function(_, delta)
            ScrollVertically(page.pickerScroll, delta)
        end)
    end
    return row
end

local function PickerEntries(page)
    local entries = {}
    local function AddNode(node, depth)
        entries[#entries + 1] = { node = node, depth = depth }
        if not page.expanded[node.key] then
            return
        end
        if node.children then
            for _, child in ipairs(node.children) do
                AddNode(child, depth + 1)
            end
        else
            for _, boss in ipairs(node.bosses) do
                entries[#entries + 1] = { node = node, boss = boss, depth = depth + 1 }
            end
        end
    end
    for _, category in ipairs(page.catalog) do
        AddNode(category, 0)
    end
    return entries
end

local function RefreshPicker(page)
    local entries = PickerEntries(page)
    local y = 0
    for index, entry in ipairs(entries) do
        local row = page.pickerRows[index]
        if not row then
            row = CreatePickerRow(page)
            page.pickerRows[index] = row
        end
        row.node, row.boss = entry.node, entry.boss
        local indent = entry.depth * 14
        local width = PICKER_WIDTH - SCROLLBAR_WIDTH - indent
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", indent, -y)
        row:SetWidth(width)
        row.select:SetWidth(width - 30)

        local lines = {}
        if entry.boss then
            SetVisible(row.expand, false)
            row.select.text:SetText((page.watched[entry.boss.key] and "[x] " or "[ ] ") .. entry.boss.name)
            if entry.node.kind == "Dungeons" then
                UI.AddTooltipLine(lines, "Watchlist name only; per-character dungeon status is Unknown.")
            else
                UI.AddTooltipLine(lines, "Select this raid encounter for the character matrix.")
            end
            UI.RefreshTooltip(row.select, entry.boss.name, lines)
        else
            SetVisible(row.expand, true)
            row.expand.text:SetText(page.expanded[entry.node.key] and "-" or "+")
            local count = WatchedCount(entry.node, page.watched)
            local mark = count == 0 and "[ ] " or (count == #entry.node.bosses and "[x] " or "[-] ")
            row.select.text:SetText(mark .. entry.node.name)
            UI.AddTooltipLine(lines, count .. " / " .. #entry.node.bosses .. " encounters watched.")
            UI.AddTooltipLine(lines, "Click the name to select the group; use + or - to expand it.")
            UI.RefreshTooltip(row.select, entry.node.name, lines)
        end
        row:Show()
        y = y + PICKER_ROW_HEIGHT
    end
    for index = #entries + 1, #page.pickerRows do
        page.pickerRows[index]:Hide()
    end
    UI.UpdateScrollHeight(page.pickerScroll, math.max(PICKER_ROW_HEIGHT, y))
end

local function CharacterName(character)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[character.class]
    if not color then
        return character.name
    end
    return string.format(
        "|cff%02x%02x%02x%s|r",
        math.floor(color.r * 255 + 0.5),
        math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5),
        character.name
    )
end

local function RemainingTime(seconds)
    if seconds >= 86400 then
        return math.floor(seconds / 86400) .. "d " .. math.floor((seconds % 86400) / 3600) .. "h"
    elseif seconds >= 3600 then
        return math.floor(seconds / 3600) .. "h " .. math.floor((seconds % 3600) / 60) .. "m"
    elseif seconds >= 60 then
        return math.floor(seconds / 60) .. "m"
    end
    return "< 1m"
end

local function CellStatus(character, instance, boss)
    local lines = {}
    if instance.kind == "Dungeons" then
        UI.AddTooltipLine(lines, "Dungeon names are a watchlist, not recorded kills or loot.")
        UI.AddTooltipLine(lines, "Per-character dungeon status is not collected.")
        return "Unknown", Style.muted, lines
    end

    local raids = character.raids
    if not raids then
        UI.AddTooltipLine(lines, "No complete raid loot update has been received for this character.")
        UI.AddTooltipLine(lines, "Log in on this character; opening Raid Info can request a fresh update.")
        return "Unknown", Style.muted, lines
    end

    local endsAt = raids.lockedUntil[boss.id]
    local remaining = endsAt and endsAt - time()
    local status, color
    if remaining and remaining > 0 then
        status, color = "Looted", LOOTED_COLOR
        UI.AddTooltipLine(lines, "Loot lock ends in", RemainingTime(remaining))
        UI.AddTooltipLine(lines, "Looted does not prevent entering or killing the boss.")
    else
        status, color = "Available", Style.teal
        if endsAt then
            UI.AddTooltipLine(lines, "The reported loot lock has expired.")
        else
            UI.AddTooltipLine(lines, "No loot lock was reported in this snapshot.")
        end
        UI.AddTooltipLine(lines, "Available does not guarantee access to this raid.")
    end
    UI.AddTooltipLine(lines, "Last received", UI.FormatLastSeen(raids.updatedAt), Style.muted)
    return status, color, lines
end

local function CreateHeaderCell(page)
    local cell = CreateFrame("Frame", nil, page.matrixHeader)
    cell:SetHeight(47)
    cell.account = UI.AddLabel(cell, "", 0, -3, 80, 14, 9, Style.gold)
    cell.name = UI.AddLabel(cell, "", 0, -22, 80, 16, 11, Style.text)
    if cell.account.SetWordWrap then
        cell.account:SetWordWrap(false)
        cell.name:SetWordWrap(false)
    end
    cell.separator = page.matrixHeader:CreateTexture(nil, "OVERLAY")
    cell.separator:SetTexture(Style.whiteTexture)
    cell.separator:SetVertexColor(Style.gold[1], Style.gold[2], Style.gold[3], 0.7)
    cell.separator:SetSize(2, 39)
    UI.AttachTooltip(cell)
    cell:EnableMouseWheel(true)
    cell:SetScript("OnMouseWheel", function(_, delta) ScrollCharacters(page, delta) end)
    return cell
end

local function RefreshHeader(page)
    for index = 1, page.columnCount do
        local cell = page.headerCells[index]
        if not cell then
            cell = CreateHeaderCell(page)
            page.headerCells[index] = cell
        end
        local position = page.matrixOffset + index
        local entry = page.characters[position]
        local x = FIRST_COLUMN + (index - 1) * page.columnWidth
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", x, 0)
        cell:SetWidth(page.columnWidth - 4)
        cell.name:SetWidth(page.columnWidth - 8)
        cell.name:SetText(entry and CharacterName(entry.character) or "")
        cell.account:SetText("")
        cell.separator:ClearAllPoints()
        cell.separator:SetPoint("TOPLEFT", FIRST_COLUMN + index * page.columnWidth - 6, -4)
        SetVisible(cell, entry ~= nil)

        if entry then
            local previous = page.characters[position - 1]
            if index == 1 or not previous or previous.account.id ~= entry.account.id then
                local span = 1
                while index + span <= page.columnCount do
                    local nextEntry = page.characters[position + span]
                    if not nextEntry or nextEntry.account.id ~= entry.account.id then
                        break
                    end
                    span = span + 1
                end
                local continued = previous and previous.account.id == entry.account.id
                cell.account:SetWidth(span * page.columnWidth - 10)
                cell.account:SetText((continued and "< " or "") .. string.upper(entry.account.name or "Unknown account"))
            end
            local nextEntry = page.characters[position + 1]
            SetVisible(cell.separator, nextEntry ~= nil and nextEntry.account.id ~= entry.account.id)
            local lines = {}
            UI.AddTooltipLine(lines, "Realm", entry.character.realm)
            UI.AddTooltipLine(lines, "Account", entry.account.name or "Unknown account")
            UI.AddTooltipLine(lines, "Raid snapshot", UI.FormatLastSeen(entry.character.raids and entry.character.raids.updatedAt))
            UI.RefreshTooltip(cell, entry.character.name, lines)
        else
            SetVisible(cell.separator, false)
        end
    end
    for index = page.columnCount + 1, #page.headerCells do
        page.headerCells[index]:Hide()
        page.headerCells[index].separator:Hide()
    end
end

local function CreateMatrixRow(page)
    local row = CreateFrame("Button", nil, page.matrixScroll.content)
    row:SetHighlightTexture(Style.whiteTexture, "ADD")
    row:GetHighlightTexture():SetVertexColor(0.10, 0.10, 0.10, 0.3)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetTexture(Style.whiteTexture)
    row.background:SetAllPoints()
    row.name = UI.AddLabel(row, "", 7, -3, FIRST_COLUMN - 16, 18, 11, Style.text)
    row.metadata = UI.AddLabel(row, "", 7, -19, FIRST_COLUMN - 16, 14, 9, Style.muted)
    if row.name.SetWordWrap then
        row.name:SetWordWrap(false)
        row.metadata:SetWordWrap(false)
    end
    row.cells = {}
    row:SetScript("OnClick", function(self)
        if self.category then
            page.collapsed[self.category.key] = not page.collapsed[self.category.key]
            UI.RefreshRaids(page, page.roster)
        end
    end)
    UI.AttachTooltip(row)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) MatrixWheel(page, page.matrixScroll, delta) end)
    return row
end

local function CreateMatrixCell(page, row)
    local cell = CreateFrame("Frame", nil, row)
    cell:SetHeight(25)
    cell.label = UI.AddLabel(cell, "", 0, -3, 80, 18, 10, Style.text)
    if cell.label.SetWordWrap then
        cell.label:SetWordWrap(false)
    end
    UI.AttachTooltip(cell)
    cell:EnableMouseWheel(true)
    cell:SetScript("OnMouseWheel", function(_, delta) MatrixWheel(page, page.matrixScroll, delta) end)
    return cell
end

local function RaidMetadata(instance)
    local details = {}
    if instance.ilvl then details[#details + 1] = "Normal ilvl " .. instance.ilvl end
    if instance.release then details[#details + 1] = "Release " .. instance.release end
    return #details > 0 and table.concat(details, " / ") or nil
end

local function RefreshMatrix(page)
    local rowIndex, y = 0, 0
    local visibleCharacters = math.min(page.columnCount, #page.characters - page.matrixOffset)
    local function AddRow(name, category, instance, boss)
        rowIndex = rowIndex + 1
        local row = page.matrixRows[rowIndex]
        if not row then
            row = CreateMatrixRow(page)
            page.matrixRows[rowIndex] = row
        end
        local metadata = instance and not boss and RaidMetadata(instance) or nil
        local height = metadata and 38 or 27
        row.category = category
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetSize(page.matrixWidth, height)
        row.name:SetText(name)
        row.name:SetTextColor(unpack((category or (instance and not boss)) and Style.gold or Style.text))
        row.metadata:SetText(metadata or "")
        SetVisible(row.metadata, metadata ~= nil)
        row.background:SetVertexColor(unpack(category and Style.panel or (rowIndex % 2 == 0 and Style.alternateRow or Style.row)))
        local rowLines = {}
        if category then
            UI.AddTooltipLine(rowLines, "Click to collapse or expand this section without changing the watchlist.")
        elseif instance and instance.kind == "Dungeons" then
            UI.AddTooltipLine(rowLines, "Watchlist only; dungeon progress is Unknown.")
        else
            UI.AddTooltipLine(rowLines, "Raid loot status is per character; a loot lock does not prevent entry.")
        end
        if metadata then UI.AddTooltipLine(rowLines, metadata, nil, Style.muted) end
        UI.RefreshTooltip(row, boss and boss.name or name, rowLines)

        local cellCount = boss and visibleCharacters or 0
        for index = 1, cellCount do
            local cell = row.cells[index]
            if not cell then
                cell = CreateMatrixCell(page, row)
                row.cells[index] = cell
            end
            local entry = page.characters[page.matrixOffset + index]
            local status, color, lines = CellStatus(entry.character, instance, boss)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", FIRST_COLUMN + (index - 1) * page.columnWidth, 0)
            cell:SetWidth(page.columnWidth - 6)
            cell.label:SetWidth(page.columnWidth - 8)
            cell.label:SetText(status)
            cell.label:SetTextColor(unpack(color))
            UI.RefreshTooltip(cell, entry.character.name .. " - " .. boss.name, lines)
            cell:Show()
        end
        for index = cellCount + 1, #row.cells do
            row.cells[index]:Hide()
        end
        row:Show()
        y = y + height
    end

    for _, category in ipairs(page.catalog) do
        if WatchedCount(category, page.watched) > 0 then
            AddRow((page.collapsed[category.key] and "+ " or "- ") .. category.name, category)
            if not page.collapsed[category.key] then
                for _, group in ipairs(category.children) do
                    for _, instance in ipairs(group.children) do
                        if WatchedCount(instance, page.watched) > 0 then
                            AddRow(instance.name, nil, instance)
                            for _, boss in ipairs(instance.bosses) do
                                if page.watched[boss.key] then
                                    AddRow(boss.name, nil, instance, boss)
                                end
                            end
                            y = y + 8
                        end
                    end
                end
            end
        end
    end
    for index = rowIndex + 1, #page.matrixRows do
        page.matrixRows[index]:Hide()
    end
    SetVisible(page.empty, rowIndex == 0)
    UI.UpdateScrollHeight(page.matrixScroll, math.max(40, y))
end

function UI.CreateRaidsPage(parent, width, onFocusChanged)
    local catalog = Data.GetEncounterCatalog()
    local watched = Data.GetEncounterWatchlist()
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    page.width = width
    page.catalog = catalog
    page.watched = watched
    page.expanded = { Raids = true, Dungeons = true }
    page.collapsed = {}
    page.roster, page.characters = {}, {}
    page.matrixOffset, page.columnCount = 0, 1
    page.showPicker, page.compact, page.focused = true, true, false
    page.pickerRows, page.matrixRows, page.headerCells = {}, {}, {}

    local pickerX = width - PICKER_WIDTH
    UI.AddLabel(page, "Raid & dungeon watchlist", 0, 0, 620, 24, 16, Style.text)
    UI.AddLabel(page, "Select categories, instances or individual encounters.", 0, -27, 700, 18, 11, Style.muted)

    page.focusButton = UI.AddTextButton(page, "Focus encounters", 156, 26, function()
        page.focused = not page.focused
        onFocusChanged()
    end)
    page.focusButton:SetPoint("TOPLEFT", pickerX - 164, 0)
    AddTip(page.focusButton, "Encounter Focus", "Hide currency cards temporarily to make the encounter lists taller.")

    page.pickerToggle = UI.AddTextButton(page, "Hide selection", 160, 26, function()
        page.showPicker = not page.showPicker
        UI.RefreshRaids(page, page.roster)
    end)
    page.pickerToggle:SetPoint("TOPLEFT", pickerX, 0)
    page.compactToggle = UI.AddTextButton(page, "", 164, 26, function()
        page.compact = not page.compact
        UI.RefreshRaids(page, page.roster)
    end)
    page.compactToggle:SetPoint("TOPLEFT", pickerX + 168, 0)
    AddTip(page.compactToggle, "Character columns", "Switch between compact and wider character columns.")

    UI.AddLabel(page, "WATCHED ENCOUNTERS", 0, -61, 360, 16, 10, Style.gold)
    page.position = UI.AddLabel(page, "", 0, -61, 140, 16, 9, Style.muted)
    page.position:SetJustifyH("RIGHT")
    page.matrixHeader = UI.CreateSurface(page, 1, 47)
    page.matrixHeader:SetPoint("TOPLEFT", 0, -84)
    UI.AddLabel(page.matrixHeader, "ENCOUNTER", 7, -23, FIRST_COLUMN - 16, 18, 10, Style.muted)
    page.matrixHeader:EnableMouseWheel(true)
    page.matrixHeader:SetScript("OnMouseWheel", function(_, delta) ScrollCharacters(page, delta) end)

    page.matrixScroll = CreateScroll(page, "AshoholicRaidMatrixScroll")
    page.matrixScroll:SetPoint("TOPLEFT", 0, -135)
    page.matrixScroll:SetPoint("BOTTOMLEFT", 0, 42)
    page.matrixScroll:SetScript("OnMouseWheel", function(self, delta) MatrixWheel(page, self, delta) end)
    page.empty = UI.AddLabel(page.matrixScroll.content, "Nothing selected. Choose instances or bosses on the right.",
        8, -8, 650, 24, 11, Style.muted)

    page.horizontal = CreateFrame("Slider", nil, page)
    page.horizontal:SetPoint("BOTTOMLEFT", FIRST_COLUMN, 16)
    page.horizontal:SetSize(400, 12)
    page.horizontal:SetOrientation("HORIZONTAL")
    page.horizontal:SetBackdrop({ bgFile = Style.whiteTexture, edgeFile = Style.whiteTexture, edgeSize = 1 })
    page.horizontal:SetBackdropColor(unpack(Style.row))
    page.horizontal:SetBackdropBorderColor(unpack(Style.border))
    page.horizontal:SetThumbTexture(Style.whiteTexture)
    page.horizontal:GetThumbTexture():SetSize(70, 10)
    page.horizontal:GetThumbTexture():SetVertexColor(Style.gold[1], Style.gold[2], Style.gold[3], 0.75)
    page.horizontal:SetValueStep(1)
    page.horizontal:SetMinMaxValues(0, 0)
    page.horizontal:SetScript("OnValueChanged", function(_, value)
        if page.settingSlider then return end
        local offset = math.floor(value + 0.5)
        if offset ~= page.matrixOffset then
            page.matrixOffset = offset
            UI.RefreshRaids(page, page.roster)
        end
    end)
    page.horizontal:EnableMouseWheel(true)
    page.horizontal:SetScript("OnMouseWheel", function(_, delta) ScrollCharacters(page, delta) end)
    page.hint = UI.AddLabel(page, "", 0, 0, 205, 15, 9, Style.muted)
    page.hint:ClearAllPoints()
    page.hint:SetPoint("BOTTOMLEFT", 0, 12)

    page.pickerTitle = UI.AddLabel(page, "TRACKING SELECTION", pickerX, -61, PICKER_WIDTH, 16, 10, Style.gold)
    page.watchAll = UI.AddTextButton(page, "Watch all", 105, 28, function()
        for _, category in ipairs(page.catalog) do
            for _, boss in ipairs(category.bosses) do
                page.watched[boss.key] = true
            end
        end
        SaveWatchlist(page)
    end)
    page.watchAll:SetPoint("TOPLEFT", pickerX, -84)
    page.clear = UI.AddTextButton(page, "Clear", 82, 28, function()
        page.watched = {}
        SaveWatchlist(page)
    end)
    page.clear:SetPoint("TOPLEFT", pickerX + 112, -84)
    page.pickerHint = UI.AddLabel(page, "+ expands groups", pickerX + 204, -90, 128, 16, 10, Style.muted)
    page.pickerScroll = CreateScroll(page, "AshoholicRaidPickerScroll")
    page.pickerScroll:SetPoint("TOPLEFT", pickerX, -127)
    page.pickerScroll:SetPoint("BOTTOMLEFT", pickerX, 8)
    page.pickerScroll:SetWidth(PICKER_WIDTH - SCROLLBAR_WIDTH)
    page.pickerScroll.content:SetWidth(PICKER_WIDTH - SCROLLBAR_WIDTH)
    page.pickerScroll:SetScript("OnMouseWheel", function(self, delta) ScrollVertically(self, delta) end)
    return page
end

function UI.RefreshRaids(page, roster)
    page.roster = roster
    page.characters = {}
    for _, account in ipairs(roster) do
        for _, character in ipairs(account.characters) do
            page.characters[#page.characters + 1] = { account = account, character = character }
        end
    end

    local pickerX = page.width - PICKER_WIDTH
    page.matrixWidth = (page.showPicker and pickerX - 24 or page.width) - SCROLLBAR_WIDTH
    page.columnCount = math.max(1, math.floor((page.matrixWidth - FIRST_COLUMN) / (page.compact and 80 or 110)))
    page.columnWidth = (page.matrixWidth - FIRST_COLUMN) / page.columnCount
    page.matrixOffset = math.min(page.matrixOffset, math.max(0, #page.characters - page.columnCount))
    page.matrixHeader:SetWidth(page.matrixWidth)
    page.matrixScroll:SetWidth(page.matrixWidth)
    page.matrixScroll.content:SetWidth(page.matrixWidth)
    page.horizontal:SetWidth(page.matrixWidth - FIRST_COLUMN - 6)
    page.position:ClearAllPoints()
    page.position:SetPoint("TOPRIGHT", page, "TOPLEFT", page.matrixWidth, -61)
    page.focusButton.text:SetText(page.focused and "Exit Focus" or "Focus encounters")
    page.pickerToggle.text:SetText(page.showPicker and "Hide selection" or "Show selection")
    page.compactToggle.text:SetText(page.compact and "[x] Compact columns" or "[ ] Compact columns")
    page.empty:SetText(page.showPicker
        and "Nothing selected. Choose instances or bosses on the right."
        or "Nothing selected. Show selection to choose encounters.")
    for _, widget in ipairs({ page.pickerTitle, page.watchAll, page.clear, page.pickerHint, page.pickerScroll }) do
        SetVisible(widget, page.showPicker)
    end

    local maximum = math.max(0, #page.characters - page.columnCount)
    page.settingSlider = true
    page.horizontal:SetMinMaxValues(0, maximum)
    page.horizontal:SetValue(page.matrixOffset)
    page.settingSlider = false
    SetVisible(page.horizontal, maximum > 0)
    page.hint:SetText(maximum > 0 and "Shift + wheel: characters" or "All characters fit")
    if #page.characters == 0 then
        page.position:SetText("No saved characters")
    else
        page.position:SetText(string.format(
            "%d-%d of %d",
            page.matrixOffset + 1,
            math.min(#page.characters, page.matrixOffset + page.columnCount),
            #page.characters
        ))
    end
    RefreshHeader(page)
    RefreshMatrix(page)
    if page.showPicker then
        RefreshPicker(page)
    end
end
