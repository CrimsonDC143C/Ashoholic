-- Focused live dashboard smoke test; run from the repository root with Lua 5.1.
local env = setmetatable({}, { __index = _G })
env._G = env
local objects, methods = {}, {}
local function Noop() end
local function NewObject(kind, name, parent)
    local object = setmetatable({
        kind = kind, name = name, parent = parent, shown = true, scripts = {},
        width = 100, height = 100, value = 0, scale = 1, font = { "font", 12 },
    }, { __index = methods })
    objects[#objects + 1] = object
    if name then env[name] = object end
    return object
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:GetScript(event) return self.scripts[event] end
function methods:HookScript(event, callback)
    local old = self.scripts[event]
    self.scripts[event] = function(...) if old then old(...) end; callback(...) end
end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:UnregisterEvent(event) if self.events then self.events[event] = nil end end
function methods:GetName() return self.name end
function methods:GetParent() return self.parent end
function methods:SetPoint(...) self.points = { ... } end
function methods:GetPoint() return unpack(self.points or { "CENTER", env.UIParent, "CENTER", 0, 0 }) end
function methods:ClearAllPoints() self.points = {} end
function methods:SetWidth(value) self.width = value end
function methods:SetHeight(value) self.height = value end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetScale(value) self.scale = value end
function methods:GetScale() return self.scale end
function methods:GetEffectiveScale() return self.scale end
function methods:GetFrameLevel() return 1 end
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
function methods:GetText() return self.textValue or "" end
function methods:GetStringWidth() return #tostring(self.textValue or "") * self.font[2] * 0.6 end
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
function methods:GetVerticalScrollRange() return 0 end
function methods:SetVerticalScroll(value) self.vertical = value end
function methods:SetHorizontalScroll(value) self.horizontal = value end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:SetOwner(owner) self.owner, self.lines = owner, {} end
function methods:IsOwned(owner) return self.owner == owner end
function methods:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = text end
function methods:AddDoubleLine(left, right) self:AddLine(left .. ": " .. right) end
function methods:NumLines() return #(self.lines or {}) end
function methods:SetFocus() self.focused = true end
function methods:ClearFocus() self.focused = false end
function methods:HasFocus() return self.focused end
for _, name in ipairs({
    "SetAllPoints", "SetTexture", "SetTexCoord", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetVertexColor", "SetTextColor", "SetJustifyH", "SetJustifyV",
    "SetWordWrap", "SetFontObject", "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen",
    "EnableMouse", "EnableMouseWheel", "SetMovable", "RegisterForDrag", "RegisterForClicks",
    "SetOrientation", "SetValueStep", "StartMoving", "StopMovingOrSizing", "SetToplevel",
    "Raise", "SetMultiLine", "SetAutoFocus", "SetMaxLetters", "HighlightText",
    "UpdateScrollChildRect", "SetHitRectInsets", "SetAlpha",
}) do methods[name] = Noop end

function env.CreateFrame(kind, name, parent, template)
    local object = NewObject(kind, name, parent)
    if template == "UIPanelScrollFrameTemplate" then NewObject("Slider", name .. "ScrollBar", object) end
    return object
end
function env.wipe(value) for key in pairs(value) do value[key] = nil end end
function env.time() return 100000 end
function env.GetTime() return 100 end
function env.GetCursorPosition() return 0, 0 end
function env.IsShiftKeyDown() return false end
function env.geterrorhandler() return function(problem) error(problem) end end
env.tinsert, env.UISpecialFrames = table.insert, {}
env.UIParent = NewObject("Frame")
env.UIParent:SetSize(1920, 1080)
env.GameTooltip = NewObject("Tooltip")
env.ChatFontNormal = {}
env.DEFAULT_CHAT_FRAME = { AddMessage = Noop }
env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })

local roster = {
    { id = "one", name = "Account one", isCurrent = true,
        currencies = { ashSpendable = 100, ashBanked = 200, updatedAt = 90000 },
        warband = { gold = 50000, updatedAt = 90000 },
        prestige = { count = 2, gateProgress = 1000, pendingShards = 50, pendingEssence = 1, updatedAt = 90000 },
        torment = { highestUnlocked = 2, unlockedTiers = { [1] = true, [2] = true }, accessUpdatedAt = 90000 },
        characters = { { name = "Hero", realm = "Realm", class = "MAGE", level = 80,
            gold = 100000, lastSeen = 90000, isPlayer = true,
            torment = { currentTier = 2, highestUnlocked = 2, updatedAt = 90000, accessUpdatedAt = 90000 },
            raids = { lockedUntil = { [123] = 110000 }, updatedAt = 90000 },
            activities = {
                cacheProgress = 1, cacheRequired = 2, cachesOpened = 1, equippedItemLevel = 200,
                updatedAt = 90000, dailyResetAt = 110000, weeklyResetAt = 120000, weeklyClaims = 1,
                rail = { { count = 2, items = { { id = 600940, name = "Elixir of Ashes" } } } },
                quests = {
                    [1] = { title = "Free quest", cadence = "daily", done = 1, max = 1,
                        state = 2, accountWide = false, rewards = { ash = 10 } },
                    [2] = { title = "Paid quest", cadence = "weekly", done = 1, max = 1,
                        state = 2, accountWide = false, category = 8, cost = 20123, rewards = { ash = 20 } },
                },
            },
            trials = { champion = { best = 1000, rank = 2, total = 20, updatedAt = 90000 },
                crusader = { best = 299999899, teamSize = 2, updatedAt = 90000 } },
        } } },
    { id = "two", name = "Account two", isCurrent = false, characters = {
        { name = "Alt", realm = "Realm", class = "WARRIOR", level = 40, gold = 20000, lastSeen = 90000 },
    } },
}
local visible, dashboard, profiles, listener = {}, nil, nil, nil
local Data = {}
function Data.GetRoster() return roster end
function Data.IsAccountVisible(id) return visible[id] ~= false end
function Data.SetAccountVisible(id, value) visible[id] = value; if listener then listener() end end
function Data.OnRosterChanged(callback) listener = callback end
function Data.GetProgressionRules() return { prestigeGate = 1000, tormentLadderTop = 2, tierNames = { "Normal", "Torment I" } } end
function Data.GetCurrentCharacterKey() return "guid" end
function Data.GetDashboardSettings() return dashboard end
function Data.SaveDashboardSettings(value) dashboard = value end
function Data.GetUIProfiles() return profiles or { saved = {}, characters = {} } end
function Data.SaveUIProfiles(value) profiles = value end
function Data.GetRosterPosition() return nil end
function Data.SaveRosterPosition() end
local raidBoss = { key = "raid:123", id = 123, name = "Test raid boss" }
local dungeonBoss = { key = "dungeon:test", name = "Test dungeon boss" }
local raidInstance = { key = "Raids:map:1", name = "Test raid", kind = "Raids", bosses = { raidBoss } }
local dungeonInstance = { key = "Dungeons:test", name = "Test dungeon", kind = "Dungeons", bosses = { dungeonBoss } }
local catalog = {
    { key = "Raids", name = "Raids", bosses = { raidBoss },
        children = { { key = "Raids:exp:3", name = "Wrath", bosses = { raidBoss }, children = { raidInstance } } } },
    { key = "Dungeons", name = "Dungeons", bosses = { dungeonBoss },
        children = { { key = "Dungeons:exp:3", name = "Wrath", bosses = { dungeonBoss }, children = { dungeonInstance } } } },
}
local watchlist = { [raidBoss.key] = true, [dungeonBoss.key] = true }
function Data.GetEncounterCatalog() return catalog end
function Data.GetEncounterWatchlist() return watchlist end
function Data.SaveEncounterWatchlist(value) watchlist = value end
function Data.GetMinimapSettings() return { angle = 225, hidden = false } end
function Data.SaveMinimapSettings() end
function Data.GetTrustedPeers() return {} end
function Data.SetTrustedPeer() end
function Data.SetAccountName(id, name)
    for _, account in ipairs(roster) do if account.id == id then account.name = name end end
    if listener then listener() end
end
local addon = {
    Data = Data,
    Collectors = { Currencies = { RequestBalancesIfNeeded = Noop } },
    Integrations = { FastSwap = { Swap = Noop } },
    Sync = { Trust = Noop, Untrust = Noop, Start = Noop, StartAll = Noop,
        GetStatus = function() return "Idle" end, Codec = { Encode = function() return "00" end } },
    Minimap = { SetIcon = Noop, Refresh = Noop },
    CloseColorPicker = Noop,
}
env.Ashoholic = addon

local function Load(name)
    setfenv(assert(loadfile("AddOns\\Ashoholic\\UI\\" .. name .. ".lua")), env)("Ashoholic")
end
for _, name in ipairs({ "Widgets", "Theme", "Model", "Alerts", "Roster", "Progression", "Raids",
    "Activities", "Trials", "Settings", "SettingsAppearance", "SettingsGeneral", "Window", "Dashboard" }) do
    Load(name)
end
local UI = addon.UI
UI.ShowWindow()
assert(UI.frame:IsShown())
for _, name in ipairs(UI.TAB_NAMES) do
    UI.state.tab = name
    UI.Refresh()
end
for _, section in ipairs(UI.SECTIONS) do UI.ShowSettings(section.name) end
local function VisibleText(fragment)
    for _, object in ipairs(objects) do
        if object.kind == "FontString" and object:IsVisible()
            and string.find(tostring(object.textValue), fragment, 1, true) then return true end
    end
    return false
end
UI.state.tab = "Activities"
UI.Refresh()
assert(VisibleText("Claim costs 2g 1s 23c"), "Paid Call Board claim must show its exact cost")
UI.state.tab = "Progression"
UI.Refresh()
assert(VisibleText("Prestige 2"), "Account Prestige is missing")
UI.state.tab = "Raids"
UI.Refresh()
assert(VisibleText("Looted"), "An active raid loot lock must show Looted")
assert(VisibleText("Tracked"), "Dungeon entries must show Tracked, not a loot claim")
assert(UI.RaidStatus(roster[1].characters[1], 123, 110000) == "Available")
assert(UI.RaidStatus(roster[2].characters[1], 123, 100000) == "Unknown")
local function Card(title)
    for _, object in ipairs(objects) do
        if object.definition and object.definition.title == title then return object end
    end
    error("Card not found: " .. title)
end
assert(Card("SOUL ASH").value:GetText() == "100 *")
assert(Card("TOTAL GOLD").value:GetText() == "17g *")
UI.SetAccountVisible(UI.model.accounts[2], false)
UI.Refresh()
assert(Card("SOUL ASH").value:GetText() == "100")
assert(Card("TOTAL GOLD").value:GetText() == "15g")
UI.SetAccountVisible(UI.model.accounts[1], false)
UI.Refresh()
assert(Card("SOUL ASH").value:GetText() == "Unknown")
assert(Card("TOTAL GOLD").value:GetText() == "Unknown")
UI.SetAccountVisible(UI.model.accounts[1], true)
UI.SetAccountVisible(UI.model.accounts[2], true)
UI.Refresh()

-- Closing an edited theme prompts rather than silently discarding it.
UI.ShowSettings("Customize Theme")
local originalGold = UI.GOLD[1]
UI.GOLD[1] = originalGold / 2
UI.Settings.RequestClose()
local prompt = env.AshoholicUnsavedTheme
assert(prompt and prompt:IsShown() and UI.settingsFrame:IsShown())
local function ClickChild(parent, text)
    for _, object in ipairs(objects) do
        if object.parent == parent and object.text and object.text:GetText() == text then
            assert(object.scripts.OnClick)(object)
            return
        end
    end
    error("Button not found: " .. text)
end
ClickChild(prompt, "Continue editing")
assert(not prompt:IsShown() and UI.settingsFrame:IsShown())
UI.Settings.RequestClose()
ClickChild(prompt, "Discard changes and close")
assert(not UI.settingsFrame:IsShown() and UI.GOLD[1] == originalGold)

-- Active profiles and character bindings survive a settings reload.
UI.state.profileScope = "character"
UI.Profiles.store.saved.Alternate = UI.Profiles.Capture()
UI.Profiles.Use("Alternate")
UI.state.detail = false
UI.SaveSettings()
UI.state.detail = true
UI.loaded = false
UI.LoadSettings()
assert(UI.state.profile == "Alternate" and UI.state.profileScope == "character" and not UI.state.detail)
assert(profiles.characters.guid == "Alternate")

UI.ShowSettings("Themes")
local count = #objects
for _ = 1, 3 do
    for _, name in ipairs(UI.TAB_NAMES) do UI.state.tab = name; UI.Refresh() end
    for _, section in ipairs(UI.SECTIONS) do UI.ShowSettings(section.name) end
end
assert(#objects == count, "Refreshing existing tabs or Settings created more frames")
assert(dashboard and profiles, "Settings were not saved")

local function Tick()
    for _, object in ipairs(objects) do
        if object:IsVisible() and object.scripts.OnUpdate then object.scripts.OnUpdate(object, 0.1) end
    end
end
local function Fire(event)
    for _, object in ipairs(objects) do
        if object.events and object.events[event] and object.scripts.OnEvent then object.scripts.OnEvent(object, event) end
    end
end

-- Closing the main window with a theme draft defers the prompt until Escape
-- finishes; discarding the draft then closes both windows.
UI.ShowSettings("Customize Theme")
originalGold = UI.GOLD[1]
UI.GOLD[1] = originalGold / 2
UI.frame:Hide()
Tick()
assert(prompt:IsShown() and UI.frame:IsShown() and UI.settingsFrame:IsShown())
ClickChild(prompt, "Discard changes and close")
assert(not UI.frame:IsShown() and not UI.settingsFrame:IsShown() and UI.GOLD[1] == originalGold)

UI.ShowWindow()
Fire("PLAYER_LOGIN")
Tick()
UI.state.window.combatHide = true
UI.ShowSettings("Themes")
Fire("PLAYER_REGEN_DISABLED")
assert(not UI.frame:IsShown() and not UI.settingsFrame:IsShown() and not prompt:IsShown())
print("Live dashboard smoke checks passed.")
