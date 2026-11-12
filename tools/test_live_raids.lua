-- Focused Lua 5.1 checks for the live raid collector, data contract and UI.
-- Run from the repository root; the game client is still needed for live tests.
local environment = setmetatable({}, { __index = _G })
environment._G = environment
local frames, errors = {}, {}
local clock, uptime, identityReady = 1000, 0, false
local methods = {}
local function Noop() end

local function NewObject(kind, name, parent)
    local object = setmetatable({
        kind = kind, parent = parent, shown = true, scripts = {}, events = {},
        width = 100, height = 400, value = 0, points = {},
    }, { __index = methods })
    if kind == "Frame" or kind == "Button" or kind == "ScrollFrame" or kind == "Slider" then
        frames[#frames + 1] = object
    end
    if name then environment[name] = object end
    return object
end

function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:SetWidth(value) self.width = value end
function methods:SetHeight(value) self.height = value end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetScale(value) self.scale = value end
function methods:Show() self.shown = true end
function methods:Hide()
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:IsVisible()
    return self.shown and (not self.parent or self.parent:IsVisible())
end
function methods:CreateTexture(name) return NewObject("Texture", name, self) end
function methods:CreateFontString(name) return NewObject("FontString", name, self) end
function methods:SetNormalTexture() self.normal = NewObject("Texture", nil, self) end
function methods:GetNormalTexture() return self.normal end
function methods:SetHighlightTexture() self.highlight = NewObject("Texture", nil, self) end
function methods:GetHighlightTexture() return self.highlight end
function methods:SetThumbTexture() self.thumb = NewObject("Texture", nil, self) end
function methods:GetThumbTexture() return self.thumb end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text end
function methods:SetScrollChild(child) self.child = child end
function methods:GetVerticalScroll() return self.vertical or 0 end
function methods:SetVerticalScroll(value) self.vertical = value end
function methods:GetVerticalScrollRange()
    return math.max(0, (self.child and self.child.height or 0) - self.height)
end
function methods:SetMinMaxValues(low, high) self.low, self.high = low, high end
function methods:SetValue(value)
    value = math.max(self.low or value, math.min(self.high or value, value))
    local changed = value ~= self.value
    self.value = value
    if changed and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:SetOwner(owner) self.owner = owner end
function methods:IsOwned(owner) return self.owner == owner end
for _, name in ipairs({
    "SetAllPoints", "SetTexture", "SetVertexColor", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetFont", "SetTextColor", "SetJustifyH", "SetJustifyV",
    "SetWordWrap", "EnableMouse", "EnableMouseWheel", "SetOrientation", "SetValueStep",
    "UpdateScrollChildRect", "SetFrameStrata", "SetClampedToScreen", "SetMovable",
    "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "AddLine", "AddDoubleLine",
}) do methods[name] = Noop end

function environment.CreateFrame(kind, name, parent) return NewObject(kind, name, parent) end
function environment.time() return clock end
function environment.GetTime() return uptime end
function environment.GetCVar() return "Account" end
function environment.IsShiftKeyDown() return false end
function environment.geterrorhandler() return function(problem) errors[#errors + 1] = problem end end
environment.tinsert, environment.UISpecialFrames = table.insert, {}
environment.UIParent = NewObject("Frame")
environment.UIParent:SetSize(1920, 1080)
environment.GameTooltip = NewObject("Frame")
environment.GameTooltip:Hide()
environment.RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.6, b = 1 } }
environment.ProjectEbonhold = { SS = { SEND_RAID_LOOT_LOCKOUTS = 1292 } }
environment.ProjectEbonhold.sendToServer = function() error("Unexpected server request") end
environment.Ashoholic = { Collectors = { Currencies = { RequestBalancesIfNeeded = Noop } } }
environment.Ashoholic.Collectors.Character = {
    Collect = function()
        if not identityReady then return end
        environment.Ashoholic.Data.SaveCharacterBasics("Realm", "Main", {
            guid = "main-guid", class = "MAGE", level = 80, gold = 100, location = "Dalaran",
        })
        return "Realm", "Main", "main-guid"
    end,
}

local function Load(path)
    setfenv(assert(loadfile(path)), environment)("Ashoholic")
end

local function Fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

local function Tick(elapsed)
    uptime = uptime + elapsed
    for _, frame in ipairs(frames) do
        if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, elapsed) end
    end
end

local function Send(body)
    Fire("CHAT_MSG_ADDON", "AAM0x9", "1292\t" .. body)
end

local function Character(name)
    for _, account in ipairs(environment.Ashoholic.Data.GetRoster()) do
        for _, character in ipairs(account.characters) do
            if character.name == name then return character end
        end
    end
    error("Character not found: " .. name)
end

Load("vendor\\ProjectEbonhold\\modules\\raidLockout\\raid_lockout_data.lua")
Load("AddOns\\Ashoholic\\Data\\Schema.lua")
Load("AddOns\\Ashoholic\\Data\\Encounters.lua")
Load("AddOns\\Ashoholic\\Data\\Store.lua")
Load("AddOns\\Ashoholic\\Integrations\\ProjectEbonhold.lua")
Load("AddOns\\Ashoholic\\Collectors\\Raids.lua")

-- A complete reply can arrive in pieces, out of order, before login and before
-- the character identity is ready. No partial observation should be saved.
Send("@CAFE\t002/002\t674:20")
Send("@CAFE\t001/002\t673:10;")
environment.AshoholicDB = {
    schemaVersion = 3,
    myAccountId = "account",
    accounts = {
        account = {
            name = "Account",
            realms = {
                Realm = {
                    Legacy = {
                        basics = { guid = "legacy-guid", class = "MAGE", level = 80, gold = 0, location = "Dalaran", updatedAt = 900 },
                        raids = { looted = { [673] = true }, resetAt = 1050, updatedAt = 900 },
                    },
                },
            },
        },
    },
    settings = {},
}
local Data = environment.Ashoholic.Data
Data.Initialize()
assert(environment.AshoholicDB.schemaVersion == 4)
assert(Character("Legacy").raids.lockedUntil[673] == 1050)
Fire("PLAYER_LOGIN")
assert(environment.AshoholicDB.accounts.account.realms.Realm.Main == nil)
identityReady = true
Tick(1)
assert(Character("Main").raids.lockedUntil[673] == 1010)
assert(Character("Main").raids.lockedUntil[674] == 1020)

Send("673:40;674:0;")
assert(Character("Main").raids.lockedUntil[673] == 1040)
assert(Character("Main").raids.lockedUntil[674] == nil)
Send("673:40;invalid")
assert(#errors == 1 and Character("Main").raids.lockedUntil[673] == 1040)
Send("@BEEF\t001/002\t673:")
Send("@BEEF\t002/003\t40")
assert(#errors == 2 and Character("Main").raids.lockedUntil[673] == 1040)
Send("@FACE\t001/002\t673:")
Send("673:50")
Send("@FACE\t002/002\t10")
assert(Character("Main").raids.lockedUntil[673] == 1050)
Send("")
assert(next(Character("Main").raids.lockedUntil) == nil)
Send("673:40")

Data.SaveCharacterBasics("Realm", "Available", {
    guid = "available-guid", class = "MAGE", level = 80, gold = 0, location = "Dalaran",
})
Data.SaveCharacterRaids("Realm", "Available", "available-guid", { lockedUntil = {}, updatedAt = clock })
Data.SaveCharacterBasics("Realm", "Unknown", {
    guid = "unknown-guid", class = "MAGE", level = 80, gold = 0, location = "Dalaran",
})
local copy = Character("Main")
copy.raids.lockedUntil[673] = 9999
assert(Character("Main").raids.lockedUntil[673] == 1040)

Data.SetProgressionRules({ prestigeGate = 1, tormentLadderTop = 2, tierNames = { "Normal", "Torment I" } })
Load("AddOns\\Ashoholic\\UI.lua")
Load("AddOns\\Ashoholic\\UI\\CharacterDetails.lua")
Load("AddOns\\Ashoholic\\UI\\Progression.lua")
Load("AddOns\\Ashoholic\\UI\\Raids.lua")
Load("AddOns\\Ashoholic\\UI\\Roster.lua")
local UI = environment.Ashoholic.UI
environment.Ashoholic:ToggleRosterUI()
UI.ShowLiveTab("Raids")
local window = environment.AshoholicRosterFrame
local page = window.raidsPage

local function Click(button)
    assert(button.scripts.OnClick, "Button has no click handler")(button)
end

local function PickerBoss(key)
    for _, row in ipairs(page.pickerRows) do
        if row.shown and row.boss and row.boss.key == key then return row end
    end
    error("Picker boss not found: " .. key)
end

local function MatrixRow(name)
    for _, row in ipairs(page.matrixRows) do
        if row.shown and row.name:GetText() == name then return row end
    end
    error("Matrix row not found: " .. name)
end

local function Column(name)
    for index, entry in ipairs(page.characters) do
        if entry.character.name == name then return index - page.matrixOffset end
    end
    error("Character column not found: " .. name)
end

page.expanded["Raids:exp:3"] = true
page.expanded["Raids:map:533"] = true
page.expanded["Dungeons:exp:3"] = true
page.expanded["Dungeons:name:Utgarde Keep"] = true
UI.RefreshRoster()
local raidKey = "raid:673"
Click(PickerBoss(raidKey).select)
assert(Data.GetEncounterWatchlist()[raidKey])
Click(PickerBoss(raidKey).select)
assert(not Data.GetEncounterWatchlist()[raidKey])
Click(PickerBoss(raidKey).select)

local dungeonKey = "dungeon:12:Utgarde Keep:Prince Keleseth"
Click(PickerBoss(dungeonKey).select)
local watched = Data.GetEncounterWatchlist()
watched[raidKey] = nil
assert(Data.GetEncounterWatchlist()[raidKey])
Data.Initialize()
assert(Data.GetEncounterWatchlist()[raidKey] and Data.GetEncounterWatchlist()[dungeonKey])

local raidRow = MatrixRow("Anub'Rekhan")
assert(raidRow.cells[Column("Main")].label:GetText() == "Looted")
assert(raidRow.cells[Column("Available")].label:GetText() == "Available")
assert(raidRow.cells[Column("Unknown")].label:GetText() == "Unknown")
local dungeonRow = MatrixRow("Prince Keleseth")
assert(dungeonRow.cells[Column("Main")].label:GetText() == "Unknown")
clock = 1041
UI.RefreshRoster()
raidRow = MatrixRow("Anub'Rekhan")
assert(raidRow.cells[Column("Main")].label:GetText() == "Available")
assert(raidRow.cells[Column("Legacy")].label:GetText() == "Looted")

Click(page.focusButton)
assert(page.focused and not window.goldCard:IsShown())
UI.ShowLiveTab("Roster")
assert(window.goldCard:IsShown())
UI.ShowLiveTab("Raids")
assert(not window.goldCard:IsShown())
Click(page.focusButton)
assert(window.goldCard:IsShown())
local narrowWidth = page.matrixWidth
Click(page.pickerToggle)
assert(page.matrixWidth > narrowWidth)
Click(page.pickerToggle)

local largeRoster = Data.GetRoster()
for index = 1, 20 do
    largeRoster[1].characters[#largeRoster[1].characters + 1] = {
        name = "Alt" .. index, realm = "Realm", class = "MAGE",
    }
end
UI.RefreshRaids(page, largeRoster)
assert(#page.characters > page.columnCount and page.horizontal:IsShown())
page.horizontal:SetValue(#page.characters - page.columnCount)
assert(page.matrixOffset == #page.characters - page.columnCount)

UI.RefreshRoster()
Click(page.watchAll)
assert(Data.GetEncounterWatchlist()[raidKey] and Data.GetEncounterWatchlist()[dungeonKey])
Click(page.clear)
assert(next(Data.GetEncounterWatchlist()) == nil and page.empty:IsShown())
print("Live raid collector, watchlist and UI checks passed.")
