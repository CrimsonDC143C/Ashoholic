local objects, methods = {}, {}
local environment = setmetatable({}, { __index = _G })
environment._G = environment
local cursor, shiftDown = 0, false
local function Noop() end
local function NewObject(kind, name, parent)
    local object = setmetatable({
        kind = kind, parent = parent, shown = true, scripts = {}, points = {},
        width = 100, height = 100, value = 0, scale = 1, font = { "font", 12 },
    }, { __index = methods })
    objects[#objects + 1] = object
    if name then environment[name] = object end
    return object
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:GetScript(event) return self.scripts[event] end
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
function methods:Show() self.shown = true end
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
for _, name in ipairs({
    "SetAllPoints", "SetTexture", "SetTexCoord", "SetBackdrop", "SetBackdropBorderColor",
    "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetFontObject",
    "SetFrameStrata", "SetClampedToScreen", "EnableMouse", "EnableMouseWheel", "SetMovable",
    "RegisterForDrag", "SetOrientation", "SetValueStep", "StartMoving", "StopMovingOrSizing",
    "SetToplevel", "Raise", "SetMultiLine", "SetAutoFocus", "SetFocus", "ClearFocus", "HighlightText",
    "SetMaxLetters",
}) do methods[name] = Noop end
function environment.CreateFrame(kind, name, parent) return NewObject(kind, name, parent) end
function environment.GetCursorPosition() return cursor, 0 end
function environment.IsShiftKeyDown() return shiftDown end
environment.tinsert, environment.UISpecialFrames = table.insert, {}
environment.UIParent = NewObject("Frame")
environment.UIParent:SetSize(1920, 1080)
environment.GameTooltip = NewObject("Frame")
environment.ChatFontNormal = {}
environment.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
environment.ProjectEbonhold = { RaidLockoutData = {
    { map = 533, name = "Naxxramas", bosses = { { id = 1, name = "Sapphiron" }, { id = 2, name = "Kel'Thuzad" } } },
    { map = 532, name = "Karazhan", bosses = { { id = 3, name = "Nightbane" } } },
} }
function environment.wipe(value) for key in pairs(value) do value[key] = nil end end
local function Forbidden() error("Preview attempted a live operation") end
environment.Logout, environment.FastSwap_PerformSwap = Forbidden, Forbidden
environment.ProjectEbonhold.sendToServer = Forbidden
environment.Ashoholic = {}
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
local function Click(value)
    for _, object in ipairs(objects) do
        if object.kind == "Button" and object.text and object.text:GetText() == value and object:IsVisible() then
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
for _, object in ipairs(objects) do
    assert(not (object.kind == "Button" and object.text and object.text:GetText() == "Columns"),
        "Character details must not contain a Columns button")
end

Settings("Roster Columns")
for _, name in ipairs({ "Offering bonus", "Offerings left", "Echo build", "Soul anchor", "Location" }) do Click("[ ] " .. name) end
Click("Close")
local roster = environment.AshoholicPreviewRosterScroll
local rosterPage, header = roster.parent
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

Click("Raids & Dungeons")
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
ClickObject(Text("- Dungeons").parent)
assert(VisibleRows() < expandedCount, "Collapsing Dungeons must hide instances and bosses")
Text("- Raids")
ClickObject(Text("+ Dungeons").parent)
assert(VisibleRows() == expandedCount, "Expanding must preserve the watchlist")
Click("Account One  v")
Check("All Accounts", true)
Click("Done")
Click("Hide selection")
assert(environment.AshoholicPreviewRaidMatrix.width == 1046, "Hidden picker must release its width")
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
assert(characterHeaders == 10, "Compact full-width matrix must provide ten character slots")
local accountHeaders = {}
for _, object in ipairs(objects) do
    if object.kind == "FontString" and object:IsVisible() and tostring(object:GetText()):match("^ACCOUNT ") then
        assert(not accountHeaders[object:GetText()], "Account characters must be grouped under one header")
        accountHeaders[object:GetText()] = true
    end
end
Click("Activities")
assert(Text("Account One").parent.width == 510, "Multi-account overview should retain compact cards")
Click("All Accounts  v")
Check("All Accounts", false)
Check("Account One (current)", true)
Click("Done")

Text("DAILY  /  Sample reset: 08h 42m")
Text("WEEKLY  /  Sample reset: 3d 08h")
assert(Text("Account One").parent.width == 1046, "One-account activity panel should span the view")
Click("Progression")
Text("Torment 6 unlocked")

Settings("Themes")
Click("Save as custom...")
Accept("First theme")
Click("Star")
Click("Customize...")
Click("Change")
Click("RGBA hex...")
Accept("11223380")
local main = environment.AshoholicPreviewFrame
assert(math.abs(main.background[1] - 17 / 255) < 0.001 and math.abs(main.background[4] - 128 / 255) < 0.001,
    "RGBA editor must apply RGB and alpha exactly")
Click("Text & Layout")
Click("Larger")
local function SpacingSlider()
    local title = Text("ROSTER ROW SPACING")
    for _, object in ipairs(objects) do
        if object.kind == "Slider" and object.parent == title.parent and object.points[3] == -474 then return object end
    end
    error("Row spacing slider missing")
end
SpacingSlider():SetValue(9)
Click("Colors")
Click("Update selected")
Click("Themes")
Click("Save as custom...")
Accept("Second theme")
local firstRow, secondRow = Text("First theme").parent.parent, Text("Second theme").parent.parent
assert(firstRow.points[3] > secondRow.points[3], "Starred presets should precede unstarred presets")
Click("Frostbound")
Click("Text & Layout")
Click("Normal")
SpacingSlider():SetValue(3)
Click("Themes")
Click("First theme")
assert(math.abs(main.background[1] - 17 / 255) < 0.001, "Saved colors were not restored")
Click("Text & Layout")
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
print("preview-ui: tooltips, safe Swap, eleven columns, resize minimum, scrolling, encounter groups, ten slots, activities and preset lifecycle passed")
