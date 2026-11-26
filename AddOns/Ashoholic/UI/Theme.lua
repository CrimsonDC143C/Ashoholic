--[[
    UI/Theme.lua - themes, appearance, profiles and saving local preferences.

    Everything here is LOCAL to this WoW installation: themes, fonts, column
    choices and profiles are saved through Data.SaveDashboardSettings and
    Data.SaveUIProfiles. None of it is part of an account snapshot, so it is
    never sent by Sync.

    How the pieces fit together:

      UI.LoadSettings()    - once per session, after login: reads the saved
                             preferences, then applies the active profile.
      UI.ApplyPreset(t)    - recolors everything from one of UI.THEMES.
      UI.ApplyAppearance() - repaints every registered widget with the current
                             colors, fonts and border size, then redraws.
      UI.SaveSettings()    - writes preferences back to Data. It runs when a
                             window closes and on logout, never every frame.

    Profiles bundle an appearance plus some layout options. A profile applies
    to the whole WoW account, or to one character (bound by character GUID).
]]

local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local UI = addon.UI

if not Data or not UI or not UI.Label then
    error("Ashoholic UI/Theme.lua loaded before UI/Widgets.lua.")
end

local state = UI.state
local Copy, Clone = UI.Copy, UI.Clone
local GOLD, TEXT, MUTED, TEAL = UI.GOLD, UI.TEXT, UI.MUTED, UI.TEAL
local PANEL, BORDER, BACKGROUND = UI.PANEL, UI.BORDER, UI.BACKGROUND
local BUTTON_BG, BUTTON_BORDER, STYLE = UI.BUTTON_BG, UI.BUTTON_BORDER, UI.STYLE

-------------------------------------------------------------------------------
-- Built-in presets, logos and Settings sections
-------------------------------------------------------------------------------

-- Text colors used when a preset does not define its own.
local DEFAULT_TEXT = { 0.88, 0.88, 0.90, 1 }
local DEFAULT_MUTED = { 0.58, 0.61, 0.67, 1 }
local DEFAULT_TEAL = { 0.40, 0.86, 0.78, 1 }

UI.THEMES = {
    { name = "Ember & Ash", description = "Warm ember gold on soot.",
      background = { 0.035, 0.042, 0.058 }, panel = { 0.075, 0.083, 0.105 },
      border = { 0.19, 0.21, 0.26 }, accent = { 1, 0.79, 0.39 } },
    { name = "Frostbound", description = "Northrend ice and steel.",
      background = { 0.025, 0.05, 0.085 }, panel = { 0.05, 0.09, 0.14 },
      border = { 0.16, 0.27, 0.38 }, accent = { 0.45, 0.8, 1 } },
    { name = "Void Walker", description = "Deep violet shadow.",
      background = { 0.05, 0.02, 0.08 }, panel = { 0.09, 0.05, 0.13 },
      border = { 0.27, 0.17, 0.36 }, accent = { 0.8, 0.55, 1 } },
    { name = "Fel Ember", description = "Sickly green flame.",
      background = { 0.03, 0.05, 0.025 }, panel = { 0.06, 0.09, 0.05 },
      border = { 0.2, 0.32, 0.14 }, accent = { 0.55, 1, 0.3 } },
    { name = "Blood Moon", description = "Crimson Torment.",
      background = { 0.06, 0.015, 0.02 }, panel = { 0.11, 0.03, 0.04 },
      border = { 0.36, 0.1, 0.12 }, accent = { 1, 0.35, 0.35 } },
    { name = "Holy Light", description = "Bright, warm and soft.",
      background = { 0.08, 0.075, 0.06 }, panel = { 0.13, 0.12, 0.09 },
      border = { 0.5, 0.44, 0.26 }, accent = { 1, 0.92, 0.55 } },
    { name = "Old Parchment", description = "Aged leather and ink.",
      background = { 0.1, 0.078, 0.05 }, panel = { 0.15, 0.12, 0.08 },
      border = { 0.45, 0.34, 0.2 }, accent = { 0.94, 0.85, 0.63 },
      text = { 0.95, 0.91, 0.82 }, muted = { 0.63, 0.56, 0.45 } },
    { name = "Terminal", description = "Green phosphor. Flat.",
      background = { 0, 0, 0 }, panel = { 0.02, 0.05, 0.02 },
      border = { 0.12, 0.56, 0.25 }, accent = { 0.2, 1, 0.4 },
      text = { 0.67, 1, 0.73 }, muted = { 0.12, 0.56, 0.25 }, teal = { 0.4, 1, 0.67 } },
}

UI.LOGOS = {
    "Interface\\Icons\\inv_soulash", "Interface\\Icons\\inv_misc_supersoulash",
    "Interface\\Icons\\inv_10_jewelcrafting3_soulcage_frost", "Interface\\Icons\\ability_argus_soulbombdebufflarge",
    "Interface\\Icons\\Spell_Shadow_SoulGem", "Interface\\Icons\\Spell_Fire_Fire",
    "Interface\\Icons\\Achievement_Boss_LichKing", "Interface\\Icons\\INV_Misc_Coin_02",
    "Interface\\Icons\\INV_Misc_Bag_10", "Interface\\Icons\\Spell_Shadow_DeathCoil",
    "Interface\\Icons\\Spell_Frost_FrostShock", "Interface\\Icons\\INV_Misc_Book_09",
}

UI.SECTIONS = {
    { name = "Themes", text = "Pick a complete look. Every preset recolors the whole window instantly." },
    { name = "Customize Theme", text = "Colors, opacity, fonts and layout together. Jump to a group or scroll through every control." },
    { name = "Icons", text = "Currency icons, class icons, raid status symbols and the Ashoholic logo." },
    { name = "Roster Columns", text = "Choose which character details become columns, and in which order." },
    { name = "Tabs & Views", text = "Hide tabs you never use and choose what opens first." },
    { name = "Accounts", text = "Optional aliases, account colors and default grouping." },
    { name = "Alerts", text = "Reminders for resets, caches, Prestige and watched bosses." },
    { name = "Profiles & Sharing", text = "Keep different setups and share themes with friends." },
    { name = "Sync", text = "Combine several WoW accounts into one roster." },
    { name = "Help", text = "What the Trials, Torment and loot terms mean." },
}

-- The order of these colors is part of saved themes and shared theme
-- strings: never reorder them, only append (and then update ValidAppearance).
UI.STYLE_KEYS = {
    "titleText", "headerText", "rowText", "accountText", "rowOdd", "rowEven", "rowAccount",
    "rowHover", "selectedBorder", "buttonText", "buttonHover", "tabBg", "tabActiveBg", "tabText", "tabActiveText",
}
UI.THEME_COLORS = { BACKGROUND, PANEL, BORDER, BUTTON_BG, BUTTON_BORDER, GOLD, TEXT, MUTED, TEAL }
for _, key in ipairs(UI.STYLE_KEYS) do
    UI.THEME_COLORS[#UI.THEME_COLORS + 1] = STYLE[key]
end
local THEME_COLORS = UI.THEME_COLORS

-- UI.state fields that belong to a theme (saved with it and shared with it).
UI.THEME_OPTIONS = {
    "font", "fontDelta", "density", "opacity", "scale", "iconStyle", "classIcons", "statusStyle", "logo",
    "fontRoles", "rowHeight", "rowGap", "borderSize",
}
local THEME_OPTIONS = UI.THEME_OPTIONS

-- Tabs and the values they may take in saved preferences.
UI.TAB_NAMES = { "Roster", "Raids", "Activities", "Progression", "Trials" }
local KNOWN_TABS = { Roster = true, Raids = true, Activities = true, Progression = true, Trials = true }
local FONT_ROLES = { title = true, header = true, character = true, account = true, button = true, hint = true, body = true }

-- Saved custom themes: { id = number, name = string, appearance = table, starred = true|nil }
UI.customThemes = {}
UI.nextThemeId = 0
-- Per account display preferences: [accountId] = { color, originalName, collapsed }
UI.accountConfig = {}
-- Raids page layout. The watchlist itself is saved separately through Data.
UI.raidView = { compact = true, showPicker = true, matrixOffset = 0, expanded = { Raids = true, Dungeons = true }, collapsed = {} }

-------------------------------------------------------------------------------
-- Capturing and validating appearances
-------------------------------------------------------------------------------

-- A copy of the current colors and theme options, as saved in themes/profiles.
function UI.CaptureTheme()
    local result = { colors = {}, options = {} }
    for index, color in ipairs(THEME_COLORS) do
        result.colors[index] = { color[1], color[2], color[3], color[4] or 1 }
    end
    for _, key in ipairs(THEME_OPTIONS) do
        result.options[key] = Clone(state[key])
    end
    return result
end

local function IsNumberBetween(value, low, high)
    return type(value) == "number" and value == value and value >= low and value <= high
end

local function IsPath(value)
    return type(value) == "string" and value ~= "" and #value <= 255 and not value:find("[%c|]")
end

-- Returns a clean copy of an appearance, or raises an error describing the
-- first problem. Used for saved profiles, custom themes and imported strings,
-- because all of them may come from older versions or other players.
function UI.ValidAppearance(source)
    if type(source) ~= "table" or type(source.colors) ~= "table"
        or type(source.options) ~= "table" or #source.colors ~= #THEME_COLORS then
        error("Unsupported theme layout.")
    end
    local result = { colors = {}, options = {} }
    for index = 1, #THEME_COLORS do
        local color = source.colors[index]
        if type(color) ~= "table" then
            error("Missing theme color.")
        end
        result.colors[index] = {}
        for component = 1, 4 do
            if not IsNumberBetween(color[component], 0, 1) then
                error("Theme color components must be between 0 and 1.")
            end
            result.colors[index][component] = color[component]
        end
    end

    local options = source.options
    for _, key in ipairs({ "font", "logo" }) do
        if not IsPath(options[key]) then
            error("Invalid theme " .. key .. ".")
        end
        result.options[key] = options[key]
    end
    local ranges = {
        fontDelta = { -10, 20 }, scale = { 0.1, 3 }, opacity = { 0, 1 },
        rowHeight = { 20, 120 }, rowGap = { 0, 30 }, borderSize = { 0, 10 },
    }
    for key, range in pairs(ranges) do
        local value = options[key]
        if value ~= nil then
            if not IsNumberBetween(value, range[1], range[2]) then
                error("Invalid theme " .. key .. ".")
            end
            result.options[key] = value
        elseif key ~= "rowHeight" then
            -- rowHeight is optional: nil means "use the density's height".
            error("Missing theme " .. key .. ".")
        end
    end
    local choices = {
        density = { compact = true, comfortable = true, spacious = true },
        iconStyle = { icons = true, large = true, text = true },
        statusStyle = { words = true, icons = true },
    }
    for key, allowed in pairs(choices) do
        if type(options[key]) ~= "string" or not allowed[options[key]] then
            error("Invalid theme " .. key .. ".")
        end
        result.options[key] = options[key]
    end
    if type(options.classIcons) ~= "boolean" or type(options.fontRoles) ~= "table" then
        error("Invalid theme font or icon options.")
    end
    result.options.classIcons = options.classIcons
    result.options.fontRoles = {}
    for role, override in pairs(options.fontRoles) do
        if not FONT_ROLES[role] or type(override) ~= "table" then
            error("Invalid font role.")
        end
        local copy = {}
        if override.font ~= nil then
            if not IsPath(override.font) then
                error("Invalid role font.")
            end
            copy.font = override.font
        end
        if override.delta ~= nil then
            if not IsNumberBetween(override.delta, -10, 20) then
                error("Invalid role size.")
            end
            copy.delta = override.delta
        end
        -- An override without any field changes nothing, so it is dropped.
        if next(copy) then
            result.options.fontRoles[role] = copy
        end
    end
    return result
end

-- Load an already validated appearance into the live colors and state.
local function UseAppearance(appearance)
    for index, color in ipairs(THEME_COLORS) do
        Copy(color, appearance.colors[index])
    end
    for _, key in ipairs(THEME_OPTIONS) do
        state[key] = Clone(appearance.options[key])
    end
end

-- Remember the look before editing starts, so Settings can offer "Discard".
function UI.RememberTheme()
    UI.themeCheckpoint = {
        appearance = UI.CaptureTheme(), name = state.theme,
        customTheme = state.customTheme, lastPreset = state.lastPreset,
    }
end

-- Deep comparison of two plain values or tables.
function UI.SameTheme(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not UI.SameTheme(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

-- True when the colors or options changed since UI.RememberTheme().
function UI.ThemeChanged()
    local checkpoint = UI.themeCheckpoint
    return checkpoint ~= nil and not UI.SameTheme(checkpoint.appearance, UI.CaptureTheme())
end

-- Restore the look saved by UI.RememberTheme() (Settings > Discard changes).
-- The window scale is a theme option too, so the window is rescaled.
function UI.RestoreThemeCheckpoint()
    local checkpoint = UI.themeCheckpoint
    if not checkpoint then
        return
    end
    UseAppearance(checkpoint.appearance)
    state.theme, state.customTheme, state.lastPreset = checkpoint.name, checkpoint.customTheme, checkpoint.lastPreset
    if UI.ApplyScale then
        UI.ApplyScale()
    end
    UI.ApplyAppearance()
end

function UI.Hex(color)
    return string.format("%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

-------------------------------------------------------------------------------
-- Applying a look
-------------------------------------------------------------------------------

-- Repaint every registered widget. Safe to call before any window exists.
function UI.ApplyAppearance()
    local backdrop = UI.Backdrop(state.borderSize)
    for panel, color in pairs(UI.surfaces) do
        panel:SetBackdrop(backdrop)
        panel:SetBackdropColor(unpack(color))
        panel:SetBackdropBorderColor(unpack(BORDER))
    end
    for button in pairs(UI.buttons) do
        button:SetBackdrop(backdrop)
        button:SetBackdropColor(unpack(BUTTON_BG))
        button:SetBackdropBorderColor(unpack(BUTTON_BORDER))
        button:GetHighlightTexture():SetVertexColor(unpack(STYLE.buttonHover))
    end
    for fontString, entry in pairs(UI.labels) do
        local height = UI.ApplyFont(fontString, entry.role, entry.size)
        if entry.role == "button" or entry.role == "header" or entry.role == "character" then
            fontString:SetHeight(height + 3)
        end
        fontString:SetTextColor(unpack(entry.color))
    end
    for fill in pairs(UI.progressFills) do
        fill:SetVertexColor(unpack(TEAL))
    end
    for popup in pairs(UI.popups) do
        UI.PaintPopup(popup)
    end
    -- Fonts may have changed size, so cached column widths must be measured again.
    UI.measureStamp = (UI.measureStamp or 0) + 1
    if UI.PaintWindow then
        UI.PaintWindow()
    end
    if addon.Minimap then
        addon.Minimap.SetIcon(state.logo)
    end
    if UI.Refresh then
        UI.Refresh()
    end
    if UI.RefreshSettings then
        UI.RefreshSettings()
    end
end

-- Recolor everything from a built-in preset. Button and row colors are
-- derived from the preset's panel and border so every theme stays readable.
function UI.ApplyPreset(preset)
    Copy(BACKGROUND, preset.background)
    Copy(PANEL, preset.panel)
    Copy(BORDER, preset.border)
    Copy(GOLD, preset.accent)
    Copy(TEXT, preset.text or DEFAULT_TEXT)
    Copy(MUTED, preset.muted or DEFAULT_MUTED)
    Copy(TEAL, preset.teal or DEFAULT_TEAL)
    -- Presets are fully opaque. BACKGROUND keeps its alpha (index 4), because
    -- that is the "Background opacity" slider and a preset only has 3 numbers.
    for _, color in ipairs({ PANEL, BORDER, BUTTON_BG, BUTTON_BORDER, GOLD, TEXT, MUTED, TEAL }) do
        color[4] = 1
    end
    for index = 1, 3 do
        BUTTON_BG[index] = math.min(1, preset.panel[index] * 1.3 + 0.02)
        BUTTON_BORDER[index] = math.min(1, preset.border[index] * 1.25)
    end
    for _, key in ipairs(UI.STYLE_KEYS) do
        local source = TEXT
        if key == "titleText" or key == "selectedBorder" or key == "tabActiveText" then
            source = GOLD
        elseif key == "headerText" or key == "tabText" then
            source = MUTED
        elseif key == "rowAccount" or key == "tabActiveBg" then
            source = PANEL
        elseif key == "rowOdd" or key == "rowEven" or key == "tabBg" then
            source = BUTTON_BG
        end
        local target = STYLE[key]
        if key == "rowHover" or key == "buttonHover" then
            target[1], target[2], target[3], target[4] = GOLD[1], GOLD[2], GOLD[3], 0.09
        else
            Copy(target, source)
            target[4] = source[4] or 1
        end
        if key == "rowEven" then
            for index = 1, 3 do
                target[index] = math.min(1, target[index] + 0.02)
            end
        end
    end
    state.theme = preset.name
    state.lastPreset = preset.name
    state.customTheme = nil
    UI.RememberTheme()
    UI.ApplyAppearance()
end

function UI.FindPreset(name)
    for _, preset in ipairs(UI.THEMES) do
        if preset.name == name then
            return preset
        end
    end
    return nil
end

function UI.FindCustomTheme(id)
    for index, theme in ipairs(UI.customThemes) do
        if theme.id == id then
            return theme, index
        end
    end
    return nil
end

function UI.ApplyCustomTheme(theme)
    UseAppearance(theme.appearance)
    state.theme, state.customTheme = theme.name, theme.id
    UI.RememberTheme()
    if UI.ApplyScale then
        UI.ApplyScale()
    end
    UI.ApplyAppearance()
end

-- Opens the shared color picker. Cancel restores the original color.
function UI.PickColor(onPick, current)
    local original, originalTheme = Clone(current or TEXT), state.theme
    addon:OpenColorPicker(original, function(r, g, b, a)
        onPick({ r, g, b, a })
    end, function()
        onPick(original)
        state.theme = originalTheme
        UI.ApplyAppearance()
    end, UI.settingsFrame)
end

-- Lets the player type a color as RRGGBB or RRGGBBAA.
function UI.EditColorHex(title, onPick, current)
    addon:CloseColorPicker(UI.settingsFrame)
    UI.Dialog(title .. " / RGBA hex", "Enter RRGGBB or RRGGBBAA (00 transparent, FF opaque). Example: FFCC6680.", {
        box = UI.Hex(current) .. string.format("%02x", math.floor((current[4] or 1) * 255 + 0.5)),
        primary = "Apply",
        validate = function(value)
            value = value:match("^%s*#?(%x+)%s*$")
            if not value or (#value ~= 6 and #value ~= 8) then
                return "Invalid color. Enter six or eight hexadecimal digits."
            end
        end,
        onAccept = function(value)
            value = value:match("^%s*#?(%x+)%s*$")
            local color = {}
            for index = 1, #value / 2 do
                color[index] = tonumber(value:sub(index * 2 - 1, index * 2), 16) / 255
            end
            color[4] = color[4] or 1
            onPick(color)
        end,
    })
end

-------------------------------------------------------------------------------
-- Cleaning saved preferences
--
-- Saved settings may come from an older Ashoholic version. Each value is
-- checked; anything unexpected keeps its default instead of breaking the UI.
-------------------------------------------------------------------------------

local CHOICES = {
    density = { compact = true, comfortable = true, spacious = true },
    iconStyle = { icons = true, large = true, text = true },
    statusStyle = { words = true, icons = true },
    alertStyle = { chat = true, center = true, silent = true },
    openTab = { last = true, Roster = true, Raids = true, Activities = true, Progression = true, Trials = true },
    tab = KNOWN_TABS,
    profileScope = { character = true, account = true },
}
local NUMBER_RANGES = {
    fontDelta = { -10, 20 }, scale = { 0.1, 3 }, opacity = { 0, 1 }, rowGap = { 0, 30 },
    borderSize = { 0, 10 }, rowHeight = { 20, 120 }, rosterOffset = { 0, 100000 },
}
local OPTIONAL_STRINGS = { theme = true, lastPreset = true, profile = true, selectedKey = true }

-- Returns a clean copy of one saved state value, or nil when it is unusable.
local function CleanStateValue(key, value)
    if CHOICES[key] then
        return CHOICES[key][value] and value or nil
    elseif NUMBER_RANGES[key] then
        local range = NUMBER_RANGES[key]
        return IsNumberBetween(value, range[1], range[2]) and value or nil
    elseif OPTIONAL_STRINGS[key] then
        return type(value) == "string" and value ~= "" and value or nil
    elseif key == "customTheme" then
        return type(value) == "number" and value or nil
    elseif key == "font" or key == "logo" then
        return IsPath(value) and value or nil
    elseif key == "window" or key == "alerts" then
        if type(value) ~= "table" then
            return nil
        end
        local result = {}
        for name, default in pairs(UI.STATE_DEFAULTS[key]) do
            if type(value[name]) == "boolean" then
                result[name] = value[name]
            else
                result[name] = default
            end
        end
        return result
    elseif key == "hiddenTabs" then
        if type(value) ~= "table" then
            return nil
        end
        local result = {}
        for name, hidden in pairs(value) do
            -- The Roster tab can never be hidden.
            if KNOWN_TABS[name] and name ~= "Roster" and hidden == true then
                result[name] = true
            end
        end
        return result
    elseif key == "columnWidths" then
        if type(value) ~= "table" then
            return nil
        end
        local result = {}
        for column, width in pairs(value) do
            if (column == "character" or UI.COLUMN_TITLES[column]) and IsNumberBetween(width, 20, 2000) then
                result[column] = width
            end
        end
        return result
    elseif key == "rosterSort" then
        if type(value) ~= "table" then
            return nil
        end
        local result = {}
        for _, sort in ipairs(value) do
            if #result < 2 and type(sort) == "table" and type(sort.ascending) == "boolean"
                and (sort.key == "character" or UI.COLUMN_TITLES[sort.key]) then
                result[#result + 1] = { key = sort.key, ascending = sort.ascending }
            end
        end
        return result
    elseif key == "fontRoles" then
        if type(value) ~= "table" then
            return nil
        end
        local result = {}
        for role, override in pairs(value) do
            if FONT_ROLES[role] and type(override) == "table" then
                local copy = {}
                if IsPath(override.font) then
                    copy.font = override.font
                end
                if IsNumberBetween(override.delta, -10, 20) then
                    copy.delta = override.delta
                end
                if next(copy) then
                    result[role] = copy
                end
            end
        end
        return result
    end
    local default = UI.STATE_DEFAULTS[key]
    if default ~= nil and type(value) == type(default) and type(value) ~= "table" then
        return value
    end
    return nil
end

-- Copy a saved state table into UI.state, key by key.
local function LoadState(saved)
    if type(saved) ~= "table" then
        return
    end
    for key, value in pairs(saved) do
        local clean = CleanStateValue(key, value)
        if clean ~= nil then
            state[key] = clean
        end
    end
end

local function IsColor(value)
    if type(value) ~= "table" then
        return false
    end
    for component = 1, 4 do
        if not IsNumberBetween(value[component], 0, 1) then
            return false
        end
    end
    return true
end

local function LoadAccountConfig(saved)
    wipe(UI.accountConfig)
    if type(saved) ~= "table" then
        return
    end
    for accountId, config in pairs(saved) do
        if type(accountId) == "string" and type(config) == "table" then
            UI.accountConfig[accountId] = {
                color = IsColor(config.color) and { config.color[1], config.color[2], config.color[3], config.color[4] } or nil,
                originalName = type(config.originalName) == "string" and config.originalName ~= "" and config.originalName or nil,
                collapsed = config.collapsed == true or nil,
            }
        end
    end
end

local function LoadKeySet(source)
    local result = {}
    if type(source) == "table" then
        for key, value in pairs(source) do
            if type(key) == "string" and value == true then
                result[key] = true
            end
        end
    end
    return result
end

local function LoadRaidView(saved)
    if type(saved) ~= "table" then
        return
    end
    local view = UI.raidView
    if type(saved.compact) == "boolean" then
        view.compact = saved.compact
    end
    if type(saved.showPicker) == "boolean" then
        view.showPicker = saved.showPicker
    end
    if IsNumberBetween(saved.matrixOffset, 0, 10000) then
        view.matrixOffset = math.floor(saved.matrixOffset)
    end
    if type(saved.expanded) == "table" then
        view.expanded = LoadKeySet(saved.expanded)
    end
    view.collapsed = LoadKeySet(saved.collapsed)
end

local function LoadCustomThemes(saved, savedNextId)
    wipe(UI.customThemes)
    local highestId = 0
    if type(saved) == "table" then
        for _, theme in ipairs(saved) do
            local ok, appearance = pcall(UI.ValidAppearance, type(theme) == "table" and theme.appearance)
            if ok and type(theme.id) == "number" and type(theme.name) == "string"
                and theme.name ~= "" and #theme.name <= 40 and not UI.FindCustomTheme(theme.id) then
                UI.customThemes[#UI.customThemes + 1] = {
                    id = theme.id, name = theme.name, appearance = appearance, starred = theme.starred == true or nil,
                }
                highestId = math.max(highestId, theme.id)
            end
        end
    end
    UI.nextThemeId = math.max(highestId, type(savedNextId) == "number" and savedNextId or 0)
end

-------------------------------------------------------------------------------
-- Profiles
-------------------------------------------------------------------------------

local Profiles = { store = { saved = {}, characters = {} } }
UI.Profiles = Profiles

-- Non-theme options that also belong to a profile.
local PROFILE_OPTIONS = {
    "hiddenTabs", "openTab", "detail", "columnWidths", "rosterSort",
    "window", "alerts", "alertStyle",
}

function Profiles.Capture()
    local profile = { appearance = UI.CaptureTheme(), columnOrder = Clone(UI.columnOrder), options = {} }
    for _, key in ipairs(PROFILE_OPTIONS) do
        profile.options[key] = Clone(state[key])
    end
    profile.theme, profile.customTheme = state.theme, state.customTheme
    return profile
end

-- Record where the active profile applies: this character, or the account.
function Profiles.Bind(name)
    local characterKey = Data.GetCurrentCharacterKey()
    if state.profileScope == "character" then
        if characterKey then
            Profiles.store.characters[characterKey] = name
        end
    else
        Profiles.store.account = name
        if characterKey then
            Profiles.store.characters[characterKey] = nil
        end
    end
end

-- Switch to a saved profile. Raises an error if it is missing or invalid,
-- before anything is changed.
function Profiles.Use(name)
    local profile = Profiles.store.saved[name]
    if type(profile) ~= "table" then
        error("Unknown Ashoholic profile " .. tostring(name) .. ".")
    end
    local appearance = UI.ValidAppearance(profile.appearance)
    UseAppearance(appearance)
    local options = type(profile.options) == "table" and profile.options or {}
    for _, key in ipairs(PROFILE_OPTIONS) do
        local clean = CleanStateValue(key, options[key])
        if clean ~= nil then
            state[key] = clean
        else
            state[key] = Clone(UI.STATE_DEFAULTS[key])
        end
    end
    UI.SetColumnOrder(profile.columnOrder)
    state.profile = name
    state.theme = type(profile.theme) == "string" and profile.theme or nil
    -- A profile may still name a custom preset that was deleted later.
    local customId = profile.customTheme
    state.customTheme = type(customId) == "number" and UI.FindCustomTheme(customId) and customId or nil
    Profiles.Bind(name)
    UI.RememberTheme()
    if UI.ApplyScale then
        UI.ApplyScale()
    end
    -- Safe before any window exists; it also updates the minimap icon.
    UI.ApplyAppearance()
end

function Profiles.SaveActive()
    if not state.profile then
        return
    end
    Profiles.store.saved[state.profile] = Profiles.Capture()
    Profiles.Bind(state.profile)
    Data.SaveUIProfiles(Profiles.store)
end

function Profiles.Names()
    local names = {}
    for name in pairs(Profiles.store.saved) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-------------------------------------------------------------------------------
-- Loading and saving all local preferences
-------------------------------------------------------------------------------

UI.loaded = false

-- Reads saved preferences once per session. The active profile is chosen
-- from the current character's GUID, which is known shortly after login.
function UI.LoadSettings()
    if UI.loaded then
        return
    end
    UI.loaded = true

    local saved = Data.GetDashboardSettings()
    if type(saved) == "table" then
        LoadState(saved.state)
        UI.SetColumnOrder(saved.columnOrder)
        if saved.appearance then
            local ok, appearance = pcall(UI.ValidAppearance, saved.appearance)
            if ok then
                UseAppearance(appearance)
            end
        end
        LoadCustomThemes(saved.customThemes, saved.nextThemeId)
        LoadAccountConfig(saved.accountConfig)
        LoadRaidView(saved.raidView)
    end

    local store = Data.GetUIProfiles()
    if type(store) ~= "table" then
        -- Damaged saved profiles: start again with an empty store.
        store = {}
    end
    if type(store.saved) ~= "table" then
        store.saved = {}
    end
    if type(store.characters) ~= "table" then
        store.characters = {}
    end
    Profiles.store = store
    if type(store.saved.Default) ~= "table" then
        store.saved.Default = Profiles.Capture()
    end

    local key = Data.GetCurrentCharacterKey()
    local assigned = key and store.characters[key]
    state.profileScope = assigned and "character" or "account"
    local ok = pcall(Profiles.Use, assigned or store.account or "Default")
    if not ok then
        -- The chosen profile is missing or damaged. Fall back to Default,
        -- and rebuild Default itself from the current look if necessary.
        state.profileScope = "account"
        if not pcall(Profiles.Use, "Default") then
            store.saved.Default = Profiles.Capture()
            Profiles.Use("Default")
        end
        print("|cffffca63Ashoholic:|r A saved window profile could not be loaded, so the Default profile is used.")
    end
end

-- Writes all local preferences. Called when a window closes and on logout.
function UI.SaveSettings()
    if not UI.loaded then
        return
    end
    Data.SaveDashboardSettings({
        state = state,
        columnOrder = UI.columnOrder,
        appearance = UI.CaptureTheme(),
        customThemes = UI.customThemes,
        nextThemeId = UI.nextThemeId,
        accountConfig = UI.accountConfig,
        raidView = UI.raidView,
    })
    Profiles.SaveActive()
end
