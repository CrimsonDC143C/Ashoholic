local objects, methods = {}, {}
local environment = setmetatable({}, { __index = _G })
environment._G = environment
local cursor, shiftDown = 0, false
local function Noop() end
local function NewObject(kind, name, parent)
    local object = setmetatable({
        kind = kind, name = name, parent = parent, shown = true, scripts = {}, points = {},
        width = 100, height = 100, value = 0, scale = 1, font = { "font", 12 },
    }, { __index = methods })
    objects[#objects + 1] = object
    if name then environment[name] = object end
    return object
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:GetScript(event) return self.scripts[event] end
function methods:HookScript(event, callback)
    local original = self.scripts[event]
    self.scripts[event] = function(...)
        if original then original(...) end
        callback(...)
    end
end
function methods:GetName() return self.name end
function methods:SetPoint(...) self.points = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:SetWidth(value) self.width = value end
function methods:SetHeight(value) self.height = value end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetScale(value) self.scale = value end
function methods:GetScale() return self.scale end
function methods:GetEffectiveScale() return self.parent and self.parent:GetEffectiveScale() * self.scale or self.scale end
function methods:GetFrameLevel() return self.frameLevel or 1 end
function methods:SetFrameLevel(value) self.frameLevel = value end
function methods:Show()
    local changed = not self.shown
    self.shown = true
    if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    local changed = self.shown
    self.shown = false
    if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:CreateTexture(name) return NewObject("Texture", name, self) end
function methods:CreateFontString(name) return NewObject("FontString", name, self) end
function methods:SetHighlightTexture() self.highlight = NewObject("Texture", nil, self) end
function methods:GetHighlightTexture() return self.highlight end
function methods:SetThumbTexture() self.thumb = NewObject("Texture", nil, self) end
function methods:GetThumbTexture() return self.thumb end
function methods:SetFont(path, size) self.font = { path, size } end
function methods:SetText(text) self.textValue = text end
function methods:GetText() return self.textValue end
function methods:GetStringWidth()
    local text = tostring(self.textValue or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "XX")
    return #text * self.font[2] * 0.6
end
function methods:SetMinMaxValues(low, high) self.low, self.high = low, high end
function methods:SetValue(value)
    value = math.max(self.low or value, math.min(self.high or value, value))
    local changed = value ~= self.value
    self.value = value
    if changed and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:GetValue() return self.value end
function methods:GetMinMaxValues() return self.low, self.high end
function methods:SetScrollChild(child) self.child = child end
function methods:GetVerticalScroll() return self.vertical or 0 end
function methods:SetVerticalScroll(value) self.vertical = value end
function methods:SetHorizontalScroll(value) self.horizontal = value end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:SetBackdropColor(...) self.background = { ... } end
function methods:SetVertexColor(...) self.color = { ... } end
function methods:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = text end
function methods:SetOwner() self.lines = {} end
function methods:SetColorRGB(r, g, b) self.rgb = { r, g, b } end
function methods:GetColorRGB() return unpack(self.rgb) end
function methods:SetFocus() self.focused = true end
function methods:ClearFocus() self.focused = false end
function methods:HighlightText() self.highlighted = true end
for _, name in ipairs({
    "SetAllPoints", "SetTexture", "SetTexCoord", "SetBackdrop", "SetBackdropBorderColor",
    "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetFontObject",
    "SetFrameStrata", "SetClampedToScreen", "EnableMouse", "EnableMouseWheel", "SetMovable",
    "RegisterForDrag", "SetOrientation", "SetValueStep", "StartMoving", "StopMovingOrSizing",
    "SetToplevel", "Raise", "SetMultiLine", "SetAutoFocus",
    "SetMaxLetters",
}) do methods[name] = Noop end
function environment.CreateFrame(kind, name, parent) return NewObject(kind, name, parent) end
function environment.GetCursorPosition() return cursor, 0 end
function environment.IsShiftKeyDown() return shiftDown end
function environment.GetTime() return 1 end
environment.tinsert, environment.UISpecialFrames = table.insert, {}
environment.UIParent = NewObject("Frame")
environment.UIParent:SetSize(1920, 1080)
environment.GameTooltip = NewObject("Frame")
environment.ChatFontNormal = {}
environment.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
environment.ProjectEbonhold = { RaidLockoutData = {
    { map = 533, name = "Naxxramas", ilvl = 213, release = 1, bosses = { { id = 1, name = "Sapphiron" }, { id = 2, name = "Kel'Thuzad" } } },
    { map = 532, name = "Karazhan", ilvl = 213, release = 1, bosses = { { id = 3, name = "Nightbane" } } },
} }
function environment.wipe(value) for key in pairs(value) do value[key] = nil end end
local function Forbidden() error("Preview attempted a live operation") end
environment.Logout, environment.FastSwap_PerformSwap = Forbidden, Forbidden
environment.ProjectEbonhold.sendToServer = Forbidden
environment.Ashoholic = {}
environment.ColorPickerFrame = NewObject("Frame", nil, environment.UIParent)
environment.ColorPickerFrame:Hide()
environment.ColorPickerFrameOpacitySlider = NewObject("Slider", nil, environment.ColorPickerFrame)
environment.ColorPickerFrameOpacitySlider:SetMinMaxValues(0, 1)
setfenv(assert(loadfile("ColorPicker.lua")), environment)("Ashoholic")
setfenv(assert(loadfile("PreviewUI.lua")), environment)("Ashoholic")
environment.Ashoholic:TogglePreviewUI()

local function Text(value, parent)
    for _, object in ipairs(objects) do
        if object.kind == "FontString" and object.textValue == value and object:IsVisible()
            and (not parent or object.parent == parent) then return object end
    end
    error("Visible text not found: " .. value)
end
local function ClickObject(object)
    assert(object:IsVisible(), "Attempted click on a hidden widget")
    assert(object.scripts.OnClick, "Widget has no click handler")(object, "LeftButton")
end
local function Click(value, parent)
    for _, object in ipairs(objects) do
        if object.kind == "Button" and object.text and object.text:GetText() == value and object:IsVisible()
            and (not parent or object.parent == parent) then
            ClickObject(object)
            return object
        end
    end
    error("Visible button not found: " .. value)
end
local function Settings(section)
    Click("Settings")
    Click(section)
end
local function Accept(name)
    environment.AshoholicPreviewDialog.box:SetText(name or "")
    ClickObject(environment.AshoholicPreviewDialog.primary)
end
local function Check(value, checked)
    local check = Text(value).parent
    assert(check.kind == "CheckButton")
    check:SetChecked(checked)
    check.scripts.OnClick(check)
end

local essence
for _, object in ipairs(objects) do
    if object.textValue == "Persistent Prestige currency" then essence = object.parent end
end
assert(essence and essence.scripts.OnEnter)
essence.scripts.OnEnter(essence)
assert(environment.GameTooltip.lines[1] == "SOUL ESSENCE")
Click("Swap")
Text("Swap to Aster")
Click("OK")
local defaultRoster = environment.AshoholicPreviewRosterScroll
assert(environment.AshoholicPreviewFrame:GetWidth() == 1320, "Preview must use the wider default window")
local contentWidth = environment.AshoholicPreviewFrame:GetWidth() - 48
local scrollWidth = contentWidth - 26
local halfPanelWidth = (scrollWidth - 20) / 2
assert(essence.width == 240, "Currency cards must share the wider header evenly")
assert(essence.points[3] == -108, "Currency cards must move up into the removed banner space")
assert(defaultRoster.height == 335 and defaultRoster.parent.points[3] == -207,
    "The normal roster must reclaim the banner space as additional viewport height")
local defaultAccountButton = Click("Account One  v")
assert(defaultAccountButton.points[3] == -60 and defaultAccountButton.parent == environment.AshoholicPreviewFrame,
    "Account filtering must align with the raised tab row")
Click("Done")
local goldCard = Text("Character pockets + Warband").parent
assert(goldCard.points[2] + goldCard.width == environment.AshoholicPreviewFrame.width - 24,
    "Currency cards must fill the header up to the right margin")
assert(defaultRoster.child:GetWidth() <= defaultRoster:GetWidth(),
    "Default roster columns and Swap buttons must fit beside the details panel without sideways scrolling")
for _, object in ipairs(objects) do
    assert(not (object.kind == "Button" and object.text and object.text:GetText() == "Columns"),
        "Character details must not contain a Columns button")
end

Settings("Roster Columns")
for _, name in ipairs({ "Offering bonus", "Offerings left", "Echo build", "Soul anchor", "Location" }) do Click("[ ] " .. name) end
Click("Close")
local roster = environment.AshoholicPreviewRosterScroll
local rosterPage, header = roster.parent
local accountOneRows = 0
for _, row in ipairs(rosterPage.rows) do
    if row:IsVisible() then accountOneRows = accountOneRows + 1 end
end
assert(accountOneRows == 10, "Account One must contain exactly ten sample characters")
for _, object in ipairs(objects) do
    if object.kind == "ScrollFrame" and object.parent == rosterPage and object ~= roster then header = object end
end
local shown = 0
for _, object in ipairs(objects) do
    if object.kind == "FontString" and object.parent == header.child and object:IsVisible() then shown = shown + 1 end
end
assert(shown == 12, "All eleven optional columns must render beside Character")
assert(roster.child.width > roster.width, "Column overflow should preserve content width")
local grip
for _, object in ipairs(objects) do if object.parent == header.child and object.key == "location" then grip = object end end
assert(grip, "Location resize handle missing")
local defaultWidth = grip.width
cursor = 0
grip.scripts.OnMouseDown(grip, "LeftButton")
cursor = 150
grip.scripts.OnUpdate(grip)
local enlarged = grip.width
grip.scripts.OnMouseDown(grip, "RightButton")
assert(grip.width == defaultWidth and not grip.scripts.OnUpdate, "Right-click must reset the column and stop dragging")
cursor = 0
grip.scripts.OnMouseDown(grip, "LeftButton")
cursor = -10000
grip.scripts.OnUpdate(grip)
assert(grip.width == grip.minimum and enlarged > grip.minimum, "Drag must clamp to the content minimum")
grip.scripts.OnMouseUp(grip)
for _, object in ipairs(objects) do
    if object.kind == "Slider" and object.parent == rosterPage then
        object:SetValue(100)
        assert(roster.horizontal == 100 and header.horizontal == 100, "Header and rows must scroll together")
        shiftDown = true
        roster.scripts.OnMouseWheel(roster, -1)
        assert(roster.horizontal == 140 and header.horizontal == 140, "Shift-wheel must scroll headers and rows sideways")
        header.scripts.OnMouseWheel(header, 10000)
        assert(roster.horizontal == 0 and header.horizontal == 0, "Shift-wheel must clamp at the left edge")
        shiftDown = false
        roster.scripts.OnMouseWheel(roster, -1)
        assert(roster.horizontal == 0, "Normal wheel scrolling must not move horizontally")
    end
end

local function SortHeader(key)
    for _, button in ipairs(rosterPage.headerButtons) do
        if button.columnKey == key then ClickObject(button); return end
    end
    error("Sort header missing: " .. key)
end
local function Above(left, right)
    return rosterPage.rows[left].points[3] > rosterPage.rows[right].points[3]
end
SortHeader("level")
assert(Above(3, 1), "Ascending Level must put Thorn before level 80 characters")
SortHeader("runAsh")
assert(Above(2, 1) and Above(3, 2), "Secondary Run Ash must compare numeric earnings within level ties")
SortHeader("runAsh")
assert(Above(1, 2) and Above(3, 1), "Descending secondary sort must preserve the primary")
SortHeader("gold")
assert(Above(3, 2) and Above(2, 1), "Third column must replace both sorts with numeric Gold primary")
SortHeader("gold")
assert(Above(1, 2), "Second click must sort descending")
SortHeader("gold")
assert(Above(1, 2) and Above(2, 3), "Third click must restore original sample order")
SortHeader("level")
SortHeader("runAsh")
SortHeader("level")
SortHeader("level")
assert(Above(3, 2) and Above(2, 1), "Clearing primary must promote the secondary")
SortHeader("runAsh")
SortHeader("runAsh")

SortHeader("level")
local normalRowHeight = rosterPage.rows[1].height
local normalViewportHeight = roster.height
Click("Focus roster")
assert(roster.height == 432 and rosterPage.points[3] == -110, "Focus must reclaim the header's vertical space")
assert(not essence:IsVisible(), "Focus must hide the currency cards")
assert(Above(3, 1), "Focus must preserve the roster sort")
local fullyVisibleCharacters = 0
for _, row in ipairs(rosterPage.rows) do
    if row:IsVisible() then
        local top = -row.points[3]
        if top >= roster:GetVerticalScroll() and top + row.height <= roster:GetVerticalScroll() + roster.height then
            fullyVisibleCharacters = fullyVisibleCharacters + 1
        end
        assert(not row.hint:IsVisible(), "Focus must use one-line compact rows")
    end
end
assert(fullyVisibleCharacters == 10, "All ten Account One characters must fully fit in Focus without scrolling")
local focusAccount = Click("Account One  v")
assert(focusAccount.points[3] == -60, "Focus must retain accessible account filtering")
Click("Done")
Click("Swap")
Click("OK")
Click("Trials")
assert(essence:IsVisible(), "Other tabs must restore the normal header while Focus is enabled")
local trialScroll = environment.AshoholicPreviewTrialScroll
assert(trialScroll.width == scrollWidth and trialScroll.parent.rows[1].width == scrollWidth,
    "Trials must fill the available content width")
assert(trialScroll.height == 309 and trialScroll.parent.points[3] == -207,
    "Trials must use the reclaimed banner height")
local updatedHeader = Text("UPDATED")
local lastTrialValue
for _, object in ipairs(objects) do
    if object.kind == "FontString" and object.parent == trialScroll.parent.rows[1]
        and object:GetText() == "Today" then lastTrialValue = object end
end
assert(lastTrialValue and lastTrialValue.points[2] == updatedHeader.points[2]
    and lastTrialValue.points[2] > 1000
    and lastTrialValue.points[2] + lastTrialValue.width <= scrollWidth,
    "Trials headings and values must align across the wider row without overflow")
Click("Roster")
Text("Exit Focus")
assert(not essence:IsVisible() and roster.height == 432, "Returning to the roster must preserve Focus")
Click("Exit Focus")
assert(roster.height == normalViewportHeight and rosterPage.points[3] == -207,
    "Exiting Focus must restore normal geometry")
assert(essence:IsVisible() and rosterPage.rows[1].height == normalRowHeight and rosterPage.rows[1].hint:IsVisible(),
    "Exiting Focus must restore currency cards and the user's row density")
assert(Above(3, 1), "Exiting Focus must preserve sorting")
SortHeader("level")
SortHeader("level")

Click("Raids & Dungeons")
assert(environment.AshoholicPreviewRaidMatrix.width == 890, "The matrix must gain width with its picker visible")
assert(environment.AshoholicPreviewRaidPicker.points[2] == contentWidth - 332,
    "The tracking picker must align to the new right margin")
Click("Watch all")
local matrix = environment.AshoholicPreviewRaidMatrix.child
local function VisibleRows()
    local count = 0
    for _, object in ipairs(objects) do
        if object.kind == "Button" and object.parent == matrix and object:IsVisible() then count = count + 1 end
    end
    return count
end
local expandedCount = VisibleRows()
local raidScroll = environment.AshoholicPreviewRaidMatrix
local raidPicker = environment.AshoholicPreviewRaidPicker
local encounterPage = raidScroll.parent
Click("Focus encounters")
assert(raidScroll.height == 368 and raidPicker.height == 393 and encounterPage.points[3] == -110,
    "Encounter Focus must enlarge both the matrix and tracking picker")
assert(not essence:IsVisible() and VisibleRows() == expandedCount,
    "Encounter Focus must hide currencies without changing the watchlist")
Click("Roster")
Text("Focus roster")
assert(essence:IsVisible() and roster.height == normalViewportHeight,
    "Encounter Focus must not enable roster Focus")
Click("Raids & Dungeons")
Text("Exit Focus")
assert(raidScroll.height == 368 and not essence:IsVisible(),
    "Returning to encounters must restore that tab's Focus choice")
raidScroll:SetVerticalScroll(10000)
raidPicker:SetVerticalScroll(10000)
Click("Exit Focus")
assert(raidScroll.height == 271 and raidPicker.height == 296 and encounterPage.points[3] == -207,
    "Exiting encounter Focus must restore both viewports and page position")
assert(essence:IsVisible() and VisibleRows() == expandedCount,
    "Exiting encounter Focus must restore currencies and preserve the watchlist")
assert(raidScroll:GetVerticalScroll() <= math.max(0, matrix.height - raidScroll.height)
    and raidPicker:GetVerticalScroll() <= math.max(0, raidPicker.child.height - raidPicker.height),
    "Focus transitions must clamp both vertical scroll positions")
raidScroll:SetVerticalScroll(0)
raidPicker:SetVerticalScroll(0)
ClickObject(Text("- Dungeons").parent)
assert(VisibleRows() < expandedCount, "Collapsing Dungeons must hide instances and bosses")
Text("- Raids")
ClickObject(Text("+ Dungeons").parent)
assert(VisibleRows() == expandedCount, "Expanding must preserve the watchlist")
Click("Account One  v")
Check("All Accounts", true)
Click("Done")
Click("Hide selection")
assert(environment.AshoholicPreviewRaidMatrix.width == scrollWidth, "Hidden picker must release its width")
Click("Focus encounters")
assert(raidScroll.width == scrollWidth and not raidPicker:IsVisible(),
    "Encounter Focus must preserve the hidden tracking picker and full-width matrix")
Click("Activities")
assert(essence:IsVisible(), "Activities must retain its normal header when encounter Focus is enabled")
Click("Raids & Dungeons")
Click("Exit Focus")
assert(raidScroll.width == scrollWidth and not raidPicker:IsVisible(),
    "Exiting encounter Focus must preserve the picker visibility choice")
Text("Normal ilvl 213 / Release 1")
local raidPage = environment.AshoholicPreviewRaidMatrix.parent
local characterHeaders = 0
for _, object in ipairs(objects) do
    if object.kind == "Frame" and object.parent == raidPage and object.height == 47 then
        for _, child in ipairs(objects) do
            if child.kind == "FontString" and child.parent == object and child:IsVisible()
                and child.points[3] == -26 and child.font[2] == 11 and child:GetText() ~= "" then
                characterHeaders = characterHeaders + 1
            end
        end
    end
end
assert(characterHeaders == 12, "Compact full-width matrix must provide twelve character slots")
local accountHeaders = {}
for _, object in ipairs(objects) do
    if object.kind == "FontString" and object:IsVisible() and tostring(object:GetText()):match("^ACCOUNT ") then
        assert(not accountHeaders[object:GetText()], "Account characters must be grouped under one header")
        accountHeaders[object:GetText()] = true
    end
end
Click("Progression")
Text("+5 Essence (3.75k / 650 Shards)")
Text("+3 Essence (1.35k / 400 Shards)")
Text("+6 Essence (4.50k / 750 Shards)")
Text("+250 Essence (62.50k / 250 Shards)")
local progression = environment.AshoholicPreviewProgressionScroll
assert(progression.width == halfPanelWidth and progression.points[2] == halfPanelWidth + 20,
    "Progression must split the usable width between Torment and Prestige")
assert(progression.height == 390 and progression.parent.points[3] == -207,
    "Progression must use the reclaimed banner height")
assert(progression.parent.prestigePanels[1].width == halfPanelWidth,
    "Prestige cards must fill the wider progression column")
local ladderRow = progression.parent.ladderRows[1]
local lastPip = ladderRow.pips[10]
assert(math.abs(lastPip.points[2] + lastPip.width - ladderRow.width) < 0.001,
    "Torment pips must span their wider row")
Click("Activities")
local activityOne = Text("Account One").parent
local activityTwo = Text("Account Two").parent
assert(activityOne.width == halfPanelWidth and activityTwo.points[2] + activityTwo.width == scrollWidth,
    "Multi-account Activities cards must span both columns of the wider view")
assert(activityOne.height == 390 and environment.AshoholicPreviewActivityScroll.height == 390,
    "Activities cards and their viewport must use the reclaimed banner height")
Click("All Accounts  v")
Check("All Accounts", false)
Check("Account One (current)", true)
Click("Done")

Text("DAILY  /  Sample reset: 08h 42m")
Text("WEEKLY  /  Sample reset: 3d 08h")
assert(Text("Account One").parent.width == scrollWidth, "One-account activity panel should span the view")
local daily = Text("DAILY  /  Sample reset: 08h 42m")
local weekly = Text("WEEKLY  /  Sample reset: 3d 08h")
assert(daily.points[2] + daily.width < weekly.points[2]
    and weekly.points[2] + weekly.width == scrollWidth - 16,
    "Daily and Weekly sections must share the full-width card without overlap")
Click("Progression")
Text("Torment 6 unlocked")

Settings("Themes")
Click("Save as custom...")
Accept("First theme")
Click("Star")
Click("Customize...")
Click("Change")
local picker, opacity = environment.ColorPickerFrame, environment.ColorPickerFrameOpacitySlider
assert(picker:IsVisible() and picker.hasOpacity, "Change must open the shared color-and-opacity picker")
for i = 1, 8 do picker.scripts.OnUpdate(picker) end
opacity:SetValue(0.25)
picker:SetColorRGB(0.2, 0.3, 0.4)
picker.func()
local main = environment.AshoholicPreviewFrame
assert(main.background[1] == 0.2 and main.background[4] == 0.25, "Picker must apply RGB and opacity live")
picker.cancelFunc()
picker:Hide()
assert(main.background[1] == 0.035 and main.background[4] == 0.99, "Cancel must restore original RGB and alpha")
Click("Hex")
Accept("11223380")
assert(math.abs(main.background[1] - 17 / 255) < 0.001 and math.abs(main.background[4] - 128 / 255) < 0.001,
    "RGBA editor must apply RGB and alpha exactly")
Click("Fonts")
local editor = environment.AshoholicPreviewThemeEditor
assert(editor:GetVerticalScroll() > 0, "Fonts must jump within the unified theme editor")
Click("Larger")
local function SpacingSlider()
    local title = Text("ROSTER ROW SPACING")
    for _, object in ipairs(objects) do
        if object.kind == "Slider" and object.parent == title.parent and object.points[3] == title.points[3] - 24 then return object end
    end
    error("Row spacing slider missing")
end
Click("Layout")
SpacingSlider():SetValue(9)
Click("Colors")
assert(editor:GetVerticalScroll() == 0, "Colors must jump back to the same editor's top")
Click("Update selected")
Click("Themes")
Click("Save as custom...")
Accept("Second theme")
local firstRow, secondRow = Text("First theme").parent.parent, Text("Second theme").parent.parent
assert(firstRow.points[3] > secondRow.points[3], "Starred presets should precede unstarred presets")
Click("Frostbound")
Click("Customize Theme")
Click("Fonts")
Click("Normal")
Click("Layout")
SpacingSlider():SetValue(3)
Click("Themes")
Click("First theme")
assert(math.abs(main.background[1] - 17 / 255) < 0.001, "Saved colors were not restored")
Click("Customize Theme")
Click("Layout")
assert(SpacingSlider():GetValue() == 9, "Saved layout was not restored")
assert(Text("WINDOW SCALE").font[2] == 13, "Saved font size was not restored")
Click("Themes")
local rename
for _, object in ipairs(objects) do
    if object.parent == firstRow and object.text and object.text:GetText() == "Rename" then rename = object end
end
ClickObject(rename)
Accept("Renamed theme")
Text("Renamed theme")
local delete
for _, object in ipairs(objects) do
    if object.parent == secondRow and object.text and object.text:GetText() == "Delete" then delete = object end
end
ClickObject(delete)
Accept()
assert(not secondRow:IsVisible(), "Deleted custom preset row remained visible")
Click("Close")
environment.Ashoholic:TogglePreviewUI()
environment.Ashoholic:TogglePreviewUI()
Settings("Themes")
Text("Renamed theme")
Click("Close")
Click("Roster")
local before = grip.width
cursor = 0
grip.scripts.OnMouseDown(grip, "LeftButton")
cursor = 5
grip.scripts.OnUpdate(grip)
assert(grip.width == before + 5, "Dragging after a font change must start at the displayed width")
grip.scripts.OnMouseUp(grip)
Settings("Themes")
Click("Ember & Ash")
Click("Customize Theme")
Click("Fonts")
Click("Small")
Click("Close")
local unsaved = environment.AshoholicPreviewUnsavedTheme
local previewSettings = environment.AshoholicPreviewSettings
assert(unsaved:IsVisible() and not unsaved.update:IsShown(), "Default preset edits must offer Save as new, not Update")
Click("Continue editing")
assert(previewSettings:IsVisible() and not unsaved:IsShown(), "Continue editing must preserve the open editor")
Click("Close")
Click("Discard changes and close")
assert(not previewSettings:IsShown(), "Discard must close Settings")
Settings("Customize Theme")
Click("Fonts")
assert(Text("WINDOW SCALE").font[2] == 13, "Discard must restore the previous font size")
Click("Small")
Click("Close")
Click("Save as new...", unsaved)
local nameBox = environment.AshoholicPreviewDialog.box
assert(nameBox.focused and nameBox.highlighted, "New preset name must be focused and selected")
Accept("")
assert(environment.AshoholicPreviewDialog:IsVisible(), "Invalid preset names must leave the naming popup open")
Accept("Close test theme")
assert(not previewSettings:IsShown(), "Saving a new preset from the close prompt must close Settings")
Settings("Customize Theme")
Click("Fonts")
Click("Normal")
Click("Close")
assert(unsaved.update:IsVisible(), "Custom preset edits must offer Update current")
Click("Update current")
assert(not previewSettings:IsShown(), "Updating the current preset must close Settings")
Settings("Customize Theme")
Click("Fonts")
Click("Larger")
previewSettings:Hide()
assert(previewSettings:IsShown() and unsaved:IsVisible(), "Escape/hiding Settings must not bypass unsaved changes")
Click("Continue editing")
environment.Ashoholic:TogglePreviewUI()
assert(main:IsShown() and unsaved:IsVisible(), "Closing the main preview must protect an open theme draft")
Click("Save as new...", unsaved)
Click("Cancel")
assert(main:IsShown() and previewSettings:IsShown(), "Cancelling a preset name must return to the editor")
Click("Close")
Click("Discard changes and close")
assert(main:IsShown() and not previewSettings:IsShown(), "Cancelling a name must cancel the pending main-window close")
Settings("Customize Theme")
Click("Fonts")
Click("Larger")
environment.Ashoholic:TogglePreviewUI()
Click("Discard changes and close")
assert(not main:IsShown() and not previewSettings:IsShown(), "Discard must finish the requested main-window close")
environment.Ashoholic:TogglePreviewUI()
print("preview-ui: tooltips, safe Swap, eleven columns, resize minimum, scrolling, roster and encounter Focus, full-width tabs, twelve raid slots, Prestige and preset lifecycle passed")
