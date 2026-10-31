local allocations, objects = 0, {}
local fontCalls = 0
local environment = setmetatable({}, { __index = _G })
environment._G = environment
local methods = {}
local function Noop() end
local function NewObject(name, parent)
    allocations = allocations + 1
    local object = setmetatable({
        parent = parent, shown = true, scripts = {}, points = {},
        width = 100, height = 100, value = 0,
        font = { "Fonts\\FRIZQT__.TTF", 12, "" },
    }, { __index = methods })
    objects[#objects + 1] = object
    if name then environment[name] = object end
    return object
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:GetScript(event) return self.scripts[event] end
function methods:HookScript(event, callback)
    local previous = self.scripts[event]
    self.scripts[event] = function(...)
        if previous then previous(...) end
        callback(...)
    end
end
function methods:SetPoint(...)
    local point = { ... }
    for index, current in ipairs(self.points) do
        if current[1] == point[1] then
            self.points[index] = point
            return
        end
    end
    self.points[#self.points + 1] = point
end
function methods:ClearAllPoints() self.points = {} end
function methods:SetWidth(value) self.width = value end
function methods:SetHeight(value) self.height = value end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetLeft() return 0 end
function methods:GetTop() return 800 end
function methods:GetRight() return self.width end
function methods:GetBottom() return 0 end
function methods:GetEffectiveScale() return 1 end
function methods:GetFrameLevel() return self.frameLevel or 1 end
function methods:SetFrameLevel(level) self.frameLevel = level end
function methods:SetParent(parent) self.parent = parent end
function methods:GetParent() return self.parent end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
methods.IsVisible = methods.IsShown
function methods:EnableMouse(enabled) self.mouseEnabled = enabled end
function methods:CreateTexture(name) return NewObject(name, self) end
function methods:CreateFontString(name) return NewObject(name, self) end
function methods:SetHighlightTexture()
    if not self.highlight then self.highlight = NewObject(nil, self) end
end
function methods:GetHighlightTexture() return self.highlight end
function methods:SetThumbTexture()
    if not self.thumb then self.thumb = NewObject(nil, self) end
end
function methods:GetThumbTexture() return self.thumb end
function methods:SetFont(path, size, flags)
    fontCalls = fontCalls + 1
    self.font = { path, size, flags or "" }
    return true
end
function methods:GetFont() return unpack(self.font) end
function methods:SetText(text) self.textValue = text end
function methods:GetText() return self.textValue end
function methods:GetStringWidth() return #(self.textValue or "") * 6 end
function methods:SetValue(value) self.value = value end
function methods:GetValue() return self.value end
function methods:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function methods:GetMinMaxValues() return self.minimum, self.maximum end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:SetVerticalScroll(value) self.scroll = value end
for _, name in ipairs({
    "SetAllPoints", "SetTexture", "SetTexCoord", "SetVertexColor", "SetBlendMode",
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetGradientAlpha",
    "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetFontObject",
    "SetFrameStrata", "SetClampedToScreen", "EnableMouseWheel", "SetMovable",
    "SetResizable", "SetMinResize", "SetMaxResize", "RegisterForDrag", "RegisterForClicks",
    "SetScrollChild", "SetOrientation", "SetValueStep", "SetHorizontalScroll", "RegisterEvent",
    "LockHighlight", "UnlockHighlight", "StartMoving", "StopMovingOrSizing", "StartSizing",
}) do methods[name] = Noop end

function environment.CreateFrame(_, name, parent) return NewObject(name, parent) end
function environment.wipe(value) for key in pairs(value) do value[key] = nil end end
environment.tinsert = table.insert
environment.UISpecialFrames, environment.StaticPopupDialogs = {}, {}
environment.YES, environment.NO, environment.CANCEL = "Yes", "No", "Cancel"
environment.UIParent = NewObject()
environment.UIParent:SetSize(1920, 1080)
environment.GameFontNormalSmall = NewObject()
environment.GameTooltip = NewObject()
function environment.MouseIsOver() return false end
function environment.FauxScrollFrame_Update() end
function environment.FauxScrollFrame_GetOffset() return 0 end
function environment.time() return 100000 end

local Ashoholic = {
    db = { global = { options = {} } },
    Characters = { BuildView = Noop, GetNum = function() return 0 end },
    GetCurrentCharacterDB = Noop,
}
environment.Ashoholic = Ashoholic
for _, path in ipairs({ "RaidData.lua", "Themes.lua", "UI.lua" }) do
    local chunk = assert(loadfile(path))
    setfenv(chunk, environment)("Ashoholic")
end
Ashoholic:CreateUI()

local frame = environment.AshoholicFrame
local options = Ashoholic.db.global.options
local row = assert(environment.AshoholicRow1)
local originalRow = row
local keys = { "level", "wt", "cost", "ash", "money", "location", "lastSeen" }
for _, group in ipairs(Ashoholic.RaidData.groups) do keys[#keys + 1] = "raid_" .. group.key end

local function SetColumns(visible)
    options.columnVisibility, options.raidColumnVisibility = {}, {}
    for _, key in ipairs(keys) do
        options.columnVisibility[key] = visible
        options.raidColumnVisibility[key] = visible
    end
    frame:Rebuild()
end

SetColumns(true)
local header
for _, object in ipairs(objects) do
    if object.col and object.col.key == "location" then header = object end
end
assert(header, "Location header was not created")
local stableAllocations = allocations
for iteration = 1, 100 do
    SetColumns(false)
    assert(not row.location:IsShown(), "Hidden column text remains visible")
    assert(not row.wtBtn[1]:IsShown(), "Hidden World Tour button remains visible")
    assert(not header:IsShown(), "Hidden column header remains visible")
    SetColumns(true)
    assert(row.location:IsShown(), "Re-added column text stays hidden")
    assert(row.wtBtn[1]:IsShown(), "Re-added World Tour button stays hidden")
    assert(header:IsShown(), "Re-added header stays hidden")
    options.RosterView = iteration % 2 == 0 and "overview" or "raids"
    options.columnWidths = { name = 220, location = 190 }
    options.raidColumnWidths = { name = 220, location = 190 }
    options.columnOrder = { "location", "name", "ash" }
    options.raidColumnOrder = { "location", "name", "ash" }
    frame:Rebuild()
    assert(row.location:GetWidth() == 174, "Text cell width was not updated")
    assert(header:GetWidth() == 190, "Header width was not updated")
    assert(row.name.points[1][4] >= 190, "Name column did not move with its header")
    assert(environment.AshoholicRow1 == originalRow, "Roster row was replaced")
    assert(allocations == stableAllocations, "Column rebuild allocated new UI objects")
end

local draft = Ashoholic.Themes.DeepCopy(Ashoholic.Themes:GetDef("ember"))
draft.key = "draft"
draft.layout = draft.layout or {}
Ashoholic.Themes.byKey.draft = draft
local fonts = { "Fonts\\MORPHEUS.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }
for iteration = 1, 100 do
    local font = fonts[iteration % #fonts + 1]
    draft.layout.characterFont = font
    draft.layout.headerFont = font
    Ashoholic.Themes:Invalidate("draft")
    Ashoholic:ApplyTheme("draft")
    assert(row.name:GetFont() == font, "Row font was not updated")
    assert(header.label:GetFont() == font, "Header font was not updated")
end
assert(allocations == stableAllocations, "Font preview allocated new UI objects")
print("PASS: 100 column/view/width/order cycles and 100 font previews reused all UI objects")

local function Upvalue(callback, wanted)
    local index = 1
    while true do
        local name, value = debug.getupvalue(callback, index)
        assert(name, "Missing UI upvalue: " .. wanted)
        if name == wanted then return value end
        index = index + 1
    end
end

local sourceFile = assert(io.open("UI.lua", "r"))
local source = sourceFile:read("*a")
sourceFile:close()
local textStart = assert(source:find("    local texts = {}", 1, true))
local textEnd = assert(source:find("    local pages, pageHeights, tabs", textStart, true))
local tabStart = assert(source:find("    local page2 = NewPage()", 1, true))
local tabEnd = assert(source:find("    -- TAB 3", tabStart, true))
environment.addon = Ashoholic
environment.T = Ashoholic.Themes:Get("ember")
environment.WHITE = "Interface\\Buttons\\WHITE8X8"
environment.FLAT_BACKDROP = {}
environment.pages, environment.pageHeights = {}, {}
environment.activeTab = 2
environment.cfg = NewObject()
environment.NewPage = function() return NewObject() end
environment.CreateFlatButton = Upvalue(Ashoholic.ToggleConfigUI, "CreateFlatButton")
environment.ApplyFont = Upvalue(Ashoholic.ToggleConfigUI, "ApplyFont")
environment.C_Timer = { After = function(_, callback) callback() end }
local selectedPopup
environment.StaticPopup_Show = function(name, _, _, key) selectedPopup = { name, key } end
local chunk = assert(loadstring(source:sub(textStart, textEnd - 1) ..
    source:sub(tabStart, tabEnd - 1) .. "\nreturn refreshCustomTab, texts"))
local refreshThemes, textCallbacks = setfenv(chunk, environment)()
local registerThemed = Upvalue(Ashoholic.ToggleConfigUI, "RegisterThemed")
local themeCallbacks = Upvalue(registerThemed, "themed")
registerThemed(refreshThemes)

for _, key in ipairs({ "custom_1", "custom_2" }) do
    local preset = Ashoholic.Themes.DeepCopy(Ashoholic.Themes:GetDef("ember"))
    preset.name = key
    Ashoholic.Themes:SaveCustom(key, preset)
end
refreshThemes()
local settingsAllocations = allocations
local themeCallbackCount, textCallbackCount = #themeCallbacks, #textCallbacks
for iteration = 1, 100 do
    draft.layout.characterFont = fonts[iteration % #fonts + 1]
    Ashoholic.Themes:Invalidate("draft")
    Ashoholic:ApplyTheme("draft")
    refreshThemes()
    assert(allocations == settingsAllocations, "Theme cards or labels were reallocated")
    assert(#themeCallbacks == themeCallbackCount, "Theme callbacks accumulated")
    assert(#textCallbacks == textCallbackCount, "Section-label callbacks accumulated")
end

Ashoholic.Themes:RenameCustom("custom_2", "Renamed preset")
Ashoholic.Themes:DeleteCustom("custom_1")
refreshThemes()
local reusedCard
for _, object in ipairs(objects) do
    if object.isCustom and object.key == "custom_2" and object:IsShown() then reusedCard = object end
end
assert(reusedCard and reusedCard.name:GetText() == "Renamed preset", "Reused card kept stale text")
for _, object in ipairs(objects) do
    if object.parent == reusedCard and object.text then
        local label = object.text:GetText()
        if label == "R" then
            object:GetScript("OnClick")(object)
            assert(selectedPopup[2] == "custom_2", "Rename targeted an old preset")
        elseif label == "X" then
            object:GetScript("OnClick")(object)
            assert(selectedPopup[2] == "custom_2", "Delete targeted an old preset")
        elseif label == "" then
            object:GetScript("OnClick")(object)
            assert(Ashoholic.Themes:GetDef("custom_2").starred, "Star targeted an old preset")
        end
    end
end
assert(allocations == settingsAllocations, "Custom preset refresh allocated new UI objects")
print("PASS: 100 settings/font refreshes reused preset cards, labels and callbacks; pooled actions target the current preset")

environment.C_Timer = nil
local starButton
for _, object in ipairs(objects) do
    if object.parent == reusedCard and object.icon then starButton = object end
end
assert(starButton, "Missing custom preset star button")
starButton:GetScript("OnClick")(starButton)
local timer = objects[#objects]
assert(allocations == settingsAllocations + 1, "Fallback should create exactly one timer frame")
local updateTimer = assert(timer:GetScript("OnUpdate"))
assert(timer:IsShown(), "Fallback timer was not scheduled")
updateTimer(timer)
assert(not timer:IsShown(), "Fallback timer stayed active after running")
for iteration = 1, 100 do
    starButton:GetScript("OnClick")(starButton)
    assert(timer:IsShown(), "Fallback timer was not reused")
    updateTimer(timer)
    assert(not timer:IsShown(), "Reused timer stayed active")
end
assert(allocations == settingsAllocations + 1, "Starring presets leaked timer frames")
print("PASS: 101 star toggles without C_Timer reused a single idle timer frame")

local populated = {
    { linetype = 0, realm = "Test Realm" },
    { linetype = 1, account = "Test Account", accKey = "test", soulAsh = 600, money = 123456 },
}
for index, state in ipairs({ "unknown", "lvl", "partial", "no", "ok" }) do
    populated[#populated + 1] = {
        linetype = 2, key = "Test Realm.Alt" .. index, name = "Alt" .. index,
        class = "MAGE", level = state == "lvl" and 70 or 80,
        wtScanned = state ~= "unknown", lockedCount10 = state == "no" and 3 or (state == "ok" and 0 or 1),
        lockedRaids10 = state == "ok" and {} or { "Naxxramas (10)" },
        lockedCount25 = 0, lockedRaids25 = {}, soulAsh = 100,
        raidResetCost = 50000, money = 12345, location = "Dalaran", lastSeen = 99990,
    }
end
populated[#populated + 1] = { linetype = 3, soulAsh = 600, money = 123456 }
function Ashoholic.Characters:GetNum() return #populated end
function Ashoholic.Characters:Get(index) return populated[index] end
SetColumns(true)
local characterRow = assert(environment.AshoholicRow3)
assert(characterRow.name:GetText() == "Alt1", "Populated character row was not painted")
local tooltipHandler = characterRow.wtBtn[1]:GetScript("OnEnter")
frame:Refresh()
assert(characterRow.wtBtn[1]:GetScript("OnEnter") == tooltipHandler,
    "Populated refresh recreated the World Tour tooltip handler")
local unchangedFontCalls = fontCalls
for iteration = 1, 10 do frame:ApplyLayout() end
assert(fontCalls == unchangedFontCalls, "Unchanged layout reassigned fonts")
print("PASS: populated refreshes reuse World Tour handlers and skip unchanged font assignments")
local nameEnter = characterRow.nameHit:GetScript("OnEnter")
local characterClick = characterRow:GetScript("OnClick")
local accountRow = environment.AshoholicRow2
local accountEnter = accountRow:GetScript("OnEnter")
local ashEnter = accountRow.ashHitbox:GetScript("OnEnter")
for iteration = 1, 100 do
    frame:Refresh()
    assert(characterRow.nameHit:GetScript("OnEnter") == nameEnter, "Name hover handler was recreated")
    assert(characterRow:GetScript("OnClick") == characterClick, "Character click handler was recreated")
    assert(accountRow:GetScript("OnEnter") == accountEnter, "Account hover handler was recreated")
    assert(accountRow.ashHitbox:GetScript("OnEnter") == ashEnter, "Soul Ash hover handler was recreated")
end
print("PASS: 100 populated refreshes reused character, account and Soul Ash handlers")

function methods:SetOwner(owner)
    self.owner, self.lines = owner, {}
end
function methods:AddLine(text) self.lines[#self.lines + 1] = text end
function methods:AddDoubleLine(left, right) self:AddLine(left .. right) end
for index, state in ipairs({ "unknown", "lvl", "partial", "no", "ok" }) do
    local button = environment["AshoholicRow" .. (index + 2)].wtBtn[1]
    environment.GameTooltip:Hide()
    button:GetScript("OnEnter")(button)
    assert(environment.GameTooltip:IsShown() == (state ~= "ok"), "Incorrect tooltip visibility: " .. state)
    if state == "unknown" then
        assert(environment.GameTooltip.lines[1] == "World Tour Status", "Unknown tooltip was lost")
    elseif state ~= "ok" then
        assert(environment.GameTooltip.lines[1]:find("Alt" .. index, 1, true), "Tooltip used stale character data")
    end
end
characterRow.nameHit:GetScript("OnEnter")(characterRow.nameHit)
assert(environment.AshoholicLockoutPanel.title:GetText() == "Alt1", "Name hover used stale character data")
populated[1], populated[3] = populated[3], populated[1]
frame:Refresh()
assert(characterRow.wtBtn[1].state == nil, "Recycled realm row kept a character tooltip")
assert(not characterRow.nameHit.mouseEnabled, "Recycled realm row kept its character hitbox active")
assert(environment.AshoholicRow1.name:GetText() == "Alt1", "Realm row did not become a character row")
populated[1], populated[3] = populated[3], populated[1]
local replacement = Ashoholic.Themes.DeepCopy(populated[3])
replacement.name, replacement.key = "Replacement", "Test Realm.Replacement"
populated[3] = replacement
frame:Refresh()
function environment.IsShiftKeyDown() return true end
characterRow:GetScript("OnClick")(characterRow, "RightButton")
assert(selectedPopup[2] == replacement.key, "Cached character click targeted stale data")
print("PASS: all World Tour tooltip states, name hover and row recycling use current data")

local function StressPopulatedRoster(iterations)
    for iteration = 1, iterations do
        SetColumns(false)
        SetColumns(true)
        options.RosterView = iteration % 2 == 0 and "overview" or "raids"
        frame:Rebuild()
        draft.layout.characterFont = fonts[iteration % #fonts + 1]
        draft.layout.headerFont = fonts[iteration % #fonts + 1]
        draft.layout.characterFontSize = 11 + iteration % 2
        draft.layout.headerFontSize = 11 + iteration % 2
        Ashoholic.Themes:Invalidate("draft")
        Ashoholic:ApplyTheme("draft")
        assert(characterRow.name:GetFont() == draft.layout.characterFont, "Populated row font did not change")
        local _, size = characterRow.name:GetFont()
        assert(size == draft.layout.characterFontSize, "Populated row font size did not change")
        assert(characterRow.wtBtn[1]:GetScript("OnEnter") == tooltipHandler, "Stress recreated tooltip functions")
    end
end
StressPopulatedRoster(12)
collectgarbage("collect")
local retainedBaseline = collectgarbage("count")
local populatedAllocations = allocations
local largestGrowth = 0
for batch = 1, 3 do
    StressPopulatedRoster(100)
    collectgarbage("collect")
    local growth = collectgarbage("count") - retainedBaseline
    largestGrowth = math.max(largestGrowth, growth)
    assert(growth < 16, "Populated cycles retained more than 16 KB after garbage collection")
    assert(allocations == populatedAllocations, "Populated stress cycles allocated new UI objects")
end
assert(#themeCallbacks == themeCallbackCount, "Populated cycles accumulated theme callbacks")
print(string.format("PASS: 300 populated column/font/size cycles; largest retained mock Lua growth %.2f KB", largestGrowth))

local coreFile = assert(io.open("Core.lua", "r"))
local coreSource = coreFile:read("*a")
coreFile:close()
local reportStart = assert(coreSource:find("function addon:PrintMemoryUsage()", 1, true))
local reportEnd = assert(coreSource:find("function addon:ChatCommand(input)", reportStart, true))
local commandEnd = assert(coreSource:find("\nend", reportEnd, true)) + 4
local memoryUpdates, collections, memoryOutput = 0, 0, ""
local diagnosticEnvironment = setmetatable({
    addon = {}, addonName = "Ashoholic",
    UpdateAddOnMemoryUsage = function() memoryUpdates = memoryUpdates + 1 end,
    GetAddOnMemoryUsage = function(name)
        assert(name == "Ashoholic", "Memory report used the wrong addon name")
        return memoryUpdates == 1 and 200 or 150
    end,
    collectgarbage = function(action)
        if action == "collect" then collections = collections + 1; return end
        assert(action == "count", "Unexpected garbage collector operation")
        return 1000
    end,
    print = function(message) memoryOutput = message end,
}, { __index = _G })
local diagnosticChunk = assert(loadstring(coreSource:sub(reportStart, commandEnd - 1)))
setfenv(diagnosticChunk, diagnosticEnvironment)()
diagnosticEnvironment.addon:ChatCommand(" memory ")
assert(memoryUpdates == 2 and collections == 1, "Memory command did not sample around one explicit collection")
assert(memoryOutput:find("200.0 KB before GC; 150.0 KB after GC", 1, true), "Memory readings were incorrect")
assert(memoryOutput:find("Total Lua: 1000.0 KB", 1, true), "Total Lua heap reading was missing")
print("PASS: /ash memory reports before/after explicit garbage collection")