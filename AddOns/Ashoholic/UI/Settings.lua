--[[
    UI/Settings.lua - the Settings window: frame, navigation, shared controls
    and the "Unsaved theme changes" prompt.

    The window follows the approved preview design: the section list on the
    left, the chosen section on the right, and "Reset section" / "Close" at
    the bottom. The controls of each section live in their own files:

      UI/SettingsAppearance.lua  Themes, Customize Theme, Icons
      UI/SettingsGeneral.lua     Roster Columns, Tabs & Views, Accounts,
                                 Alerts, Profiles & Sharing, Sync, Help

    Those files register a section like this:

      UI.Settings.sections["Icons"] = {
          build = function(body) ... end, -- creates the controls, once
          reset = function() ... end,     -- optional, for "Reset section"
      }

    A section may also set body.Refresh = function() ... end. It runs every
    time the section is shown, to redraw lists such as the saved presets.

    Everything in Settings is a LOCAL preference of this WoW installation
    (see UI/Theme.lua). None of it is part of an account snapshot, so Sync
    never sends it.

    Memory: the window, each section body and every control are created
    once, the first time they are needed, and reused afterwards. Lists that
    can grow (custom presets, accounts) reuse pooled rows.

    Unsaved theme edits: UI.RememberTheme() stores the look before editing
    starts (the "checkpoint"). Closing Settings while the look differs from
    the checkpoint shows a prompt: save a new custom preset, update the
    selected one, or discard the edits.
]]

local addonName = ...
local addon = _G[addonName]
local UI = addon.UI

if not UI or not UI.Profiles then
    error("Ashoholic UI/Settings.lua loaded before UI/Theme.lua.")
end

local state = UI.state
local GOLD, MUTED, TEAL = UI.GOLD, UI.MUTED, UI.TEAL
local BORDER, BUTTON_BORDER, STYLE = UI.BORDER, UI.BUTTON_BORDER, UI.STYLE

local Settings = {
    sections = {}, -- [section name] = { build = function(body), reset = function() or nil }
    groups = {},   -- controls with an Update() method (see Settings.AddGroup)
    bodies = {},   -- [section name] = body frame, created on the first visit
    current = nil, -- name of the section shown now
}
UI.Settings = Settings

local frame              -- the Settings window, created on first open
local closePrompt        -- the "Unsaved theme changes" window
local closing = false    -- true while FinishClose hides the windows itself
local closeWindow = false -- also close the main window once Settings closes

-------------------------------------------------------------------------------
-- Small helpers used by every section
-------------------------------------------------------------------------------

-- Remove spaces (and line breaks) from both ends of a text.
function Settings.Trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

-- Errors raised with error("text") start with "Path\File.lua:123: ".
-- Players only need the text itself.
function Settings.CleanError(problem)
    return (tostring(problem):gsub("^.-:%d+: ", ""))
end

-- Write all local preferences now. Used after single clicks; sliders save
-- later (when the section changes or Settings closes), because a drag
-- changes the value many times per second.
function Settings.Persist()
    UI.SaveSettings()
end

-- Show a short message on the status line at the bottom of Settings.
function Settings.Say(text)
    if frame then
        frame.status:SetText(text or "")
    end
end

-- Register a control (or a list of controls) that has an Update() method.
-- Update() redraws it from UI.state. Settings calls every Update() when a
-- section is shown and after any choice, so related controls stay in step
-- (for example the row-height slider after choosing another density).
function Settings.AddGroup(group)
    Settings.groups[#Settings.groups + 1] = group
    return group
end

function Settings.UpdateAll()
    for _, group in ipairs(Settings.groups) do
        group.Update()
    end
end

-------------------------------------------------------------------------------
-- Shared controls
-------------------------------------------------------------------------------

-- A "[x] text" button that switches one true/false preference.
--   get()      returns the current value
--   set(value) stores the new value and redraws whatever it affects
function Settings.Toggle(parent, text, x, y, width, get, set)
    local button = UI.Button(parent, "", x, y, width, 28)
    button:SetScript("OnClick", function()
        set(not get())
        Settings.UpdateAll()
        Settings.Persist()
    end)
    button.Update = function()
        button.text:SetText((get() and "[x] " or "[ ] ") .. text)
    end
    button.Update()
    return Settings.AddGroup(button)
end

-- A set of buttons where exactly one is selected (gold border and text).
--   options   { { value, label }, ... }
--   perRow    buttons per row; rows are 34 pixels apart
function Settings.Choices(parent, options, x, y, width, perRow, get, set)
    local group = {}
    for index, option in ipairs(options) do
        local value = option[1]
        local column, row = (index - 1) % perRow, math.floor((index - 1) / perRow)
        local button = UI.Button(parent, option[2], x + column * (width + 8), y + row * 34, width, 28, function()
            set(value)
            Settings.UpdateAll()
            Settings.Persist()
        end)
        button.value = value
        group[index] = button
    end
    group.Update = function()
        local current = get()
        for _, button in ipairs(group) do
            local selected = current == button.value
            button:SetBackdropBorderColor(unpack(selected and GOLD or BUTTON_BORDER))
            UI.Paint(button.text, selected and GOLD or STYLE.buttonText)
        end
    end
    group.Update()
    return Settings.AddGroup(group)
end

-- A titled slider with its value shown on the right.
--   low, high, step  the range; values are rounded to whole steps
--   format(value)    returns the text shown beside the slider
-- set(value) runs only when the rounded value really changed. Expensive
-- setters should use UI.NextFrame, so a fast drag redraws once per frame.
function Settings.SliderRow(parent, title, x, y, low, high, step, get, set, format)
    UI.Label(parent, title, x, y, 300, 11, GOLD)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetPoint("TOPLEFT", x, -(y + 24))
    slider:SetSize(400, 14)
    slider:SetOrientation("HORIZONTAL")
    slider:SetBackdrop(UI.Backdrop(1))
    slider:SetBackdropColor(0.10, 0.11, 0.14, 1)
    slider:SetThumbTexture(UI.WHITE)
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(14, 14)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    local valueText = UI.Label(parent, "", x + 416, y + 24, 120, 11)

    -- True while Update() moves the slider, so that move is not treated
    -- as the player changing the value.
    local updating = false

    -- Round to the nearest step. string.format removes tiny floating point
    -- errors, so 0.7 + 3 * 0.05 is stored as 0.85, not 0.85000000000001.
    local function Round(value)
        local steps = math.floor((value - low) / step + 0.5)
        return tonumber(string.format("%.4f", steps * step + low))
    end

    slider:SetScript("OnValueChanged", function(_, value)
        if updating then
            return
        end
        value = Round(value)
        valueText:SetText(format(value))
        if value ~= get() then
            set(value)
        end
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.max(low, math.min(high, self:GetValue() + delta * step)))
    end)

    Settings.AddGroup({ Update = function()
        local value = get()
        updating = true
        slider:SetValue(value)
        updating = false
        valueText:SetText(format(value))
        thumb:SetVertexColor(unpack(GOLD))
        slider:SetBackdropBorderColor(unpack(BORDER))
    end })
    return slider
end

-------------------------------------------------------------------------------
-- Custom presets (used by Themes, Customize Theme and the close prompt)
-------------------------------------------------------------------------------

-- Checks a custom preset name. Returns the trimmed name, or nil and the
-- reason it cannot be used. exceptId skips the preset being renamed.
function Settings.CheckThemeName(name, exceptId)
    name = Settings.Trim(name)
    if name == "" or #name > 40 or name:find("[%c|]") then
        return nil, "Use a plain-text name of 1-40 characters, without control codes or |."
    end
    local lower = string.lower(name)
    for _, preset in ipairs(UI.THEMES) do
        if string.lower(preset.name) == lower then
            return nil, "That name belongs to a default preset."
        end
    end
    for _, theme in ipairs(UI.customThemes) do
        if theme.id ~= exceptId and string.lower(theme.name) == lower then
            return nil, "A custom preset already has that name."
        end
    end
    return name
end

-- Ask for a name and save the current look as a new custom preset.
-- onSaved (optional) runs after a successful save; the close prompt uses it
-- to finish closing.
function Settings.SaveCustomTheme(onSaved)
    UI.Dialog("Save custom preset", "Save colors, fonts, icons and row layout as a custom preset on this installation.", {
        box = "My Ashoholic theme",
        primary = "Save",
        validate = function(value)
            local _, problem = Settings.CheckThemeName(value)
            return problem
        end,
        onCancel = function()
            -- Not saved: Settings stays open, so the main window stays too.
            closeWindow = false
        end,
        onAccept = function(value)
            local name = Settings.CheckThemeName(value)
            UI.nextThemeId = UI.nextThemeId + 1
            local theme = { id = UI.nextThemeId, name = name, appearance = UI.CaptureTheme() }
            UI.customThemes[#UI.customThemes + 1] = theme
            state.theme, state.customTheme = name, theme.id
            UI.RememberTheme()
            Settings.ShowSection("Themes")
            Settings.Say("Saved '" .. name .. "' on this installation.")
            if onSaved then
                onSaved()
            end
        end,
    })
end

-- Overwrite the selected custom preset with the current look.
-- Returns true when a preset was updated.
function Settings.UpdateCustomTheme()
    local theme = state.customTheme and UI.FindCustomTheme(state.customTheme)
    if not theme then
        Settings.Say("Apply or edit a custom preset first, or use Save as new.")
        return false
    end
    theme.appearance = UI.CaptureTheme()
    state.theme = theme.name
    UI.RememberTheme()
    Settings.Say("Updated '" .. theme.name .. "' on this installation.")
    Settings.Persist()
    UI.RefreshSettings()
    return true
end

-------------------------------------------------------------------------------
-- Showing a section
-------------------------------------------------------------------------------

-- Gold border and text for the section shown now.
local function PaintNav()
    for _, entry in ipairs(UI.SECTIONS) do
        local button = frame.nav[entry.name]
        local active = entry.name == Settings.current
        button:SetBackdropBorderColor(unpack(active and GOLD or BUTTON_BORDER))
        UI.Paint(button.text, active and GOLD or STYLE.buttonText)
    end
end

function Settings.ShowSection(name)
    if not Settings.sections[name] then
        name = "Themes"
    end
    Settings.current = name

    -- Build the section the first time it is shown. The body is stored
    -- before building, so a building error is reported once instead of
    -- creating new frames on every click.
    local body = Settings.bodies[name]
    if not body then
        body = CreateFrame("Frame", nil, frame)
        body:SetPoint("TOPLEFT", 222, -126)
        body:SetSize(664, 420)
        Settings.bodies[name] = body
        Settings.sections[name].build(body)
    end
    for sectionName, sectionBody in pairs(Settings.bodies) do
        UI.SetVisible(sectionBody, sectionName == name)
    end

    PaintNav()
    for _, entry in ipairs(UI.SECTIONS) do
        if entry.name == name then
            frame.sectionTitle:SetText(string.upper(name))
            frame.sectionText:SetText(entry.text)
        end
    end
    Settings.UpdateAll()
    if body.Refresh then
        body.Refresh()
    end
    Settings.Persist()
end

-- "Reset section": ask first, then restore the section's defaults.
local function ResetSection()
    local name = Settings.current
    local section = name and Settings.sections[name]
    if not section or not section.reset then
        Settings.Say("This section has no resettable preferences.")
        return
    end
    UI.Dialog("Reset " .. name, "Restore the default settings for '" .. name .. "'?", {
        primary = "Reset",
        onAccept = function()
            section.reset()
            UI.Refresh()
            Settings.ShowSection(name)
            Settings.Say(name .. " reset.")
        end,
    })
end

-------------------------------------------------------------------------------
-- Closing, with the "Unsaved theme changes" prompt
-------------------------------------------------------------------------------

-- Hide Settings (and the main window when that was asked for) without
-- asking again.
local function FinishClose()
    closing = true
    if closePrompt then
        closePrompt:Hide()
    end
    frame:Hide()
    if closeWindow and UI.frame then
        UI.frame:Hide()
    end
    closing, closeWindow = false, false
end

local function BuildClosePrompt()
    closePrompt = UI.Popup("AshoholicUnsavedTheme", 520, 232)
    closePrompt:SetScript("OnHide", function()
        -- Closed without a choice (for example with Escape): keep editing,
        -- and forget any request to close the main window too.
        if not closing then
            closeWindow = false
        end
    end)
    UI.Label(closePrompt, "Unsaved theme changes", 18, 16, 484, 16, GOLD)
    closePrompt.text = UI.Label(closePrompt, "", 18, 48, 484, 11)
    UI.Button(closePrompt, "Save as new...", 18, 118, 236, 30, function()
        -- Hiding the prompt clears closeWindow (see OnHide above), so the
        -- request is kept in a local and restored for after the save.
        local alsoWindow = closeWindow
        closePrompt:Hide()
        closeWindow = alsoWindow
        Settings.SaveCustomTheme(FinishClose)
    end)
    closePrompt.update = UI.Button(closePrompt, "Update current", 266, 118, 236, 30, function()
        if Settings.UpdateCustomTheme() then
            FinishClose()
        end
    end)
    UI.Button(closePrompt, "Discard changes and close", 18, 164, 236, 30, function()
        UI.RestoreThemeCheckpoint()
        FinishClose()
    end)
    UI.Button(closePrompt, "Continue editing", 266, 164, 236, 30, function()
        closeWindow = false
        closePrompt:Hide()
    end)
end

-- Close Settings, but first offer to keep unsaved theme edits.
-- withWindow: also close the main window afterwards.
function Settings.RequestClose(withWindow)
    closeWindow = closeWindow or withWindow or false
    if not UI.ThemeChanged() then
        FinishClose()
        return
    end

    -- Keep the windows on screen while the player decides, so the edited
    -- look stays visible. A main window that was closed is shown again and
    -- closed once more after the choice.
    local alsoWindow = closeWindow
    if UI.frame and not UI.frame:IsShown() then
        alsoWindow = true
        UI.frame:Show()
    end
    frame:Show()
    addon:CloseColorPicker(frame)
    UI.HideDialog()
    closeWindow = alsoWindow

    if not closePrompt then
        BuildClosePrompt()
    end
    local custom = state.customTheme and UI.FindCustomTheme(state.customTheme)
    if custom then
        closePrompt.text:SetText("Save your edits as a new custom preset, update '" .. custom.name
            .. "', or discard them. Presets are saved on this installation.")
    else
        closePrompt.text:SetText("Default presets are read-only. Save your edits as a new custom preset"
            .. " or discard them. Presets are saved on this installation.")
    end
    UI.SetVisible(closePrompt.update, custom ~= nil)
    closePrompt:SetScale(frame:GetScale())
    closePrompt:Show()
    closePrompt:Raise()
end

-- Runs one frame after Settings was hidden by Escape or by the main window
-- closing. Waiting a frame matters: WoW's Escape handler is still closing
-- every window in UISpecialFrames, and would close the prompt again at once.
local function DeferredRequestClose()
    Settings.RequestClose(not (UI.frame and UI.frame:IsShown()))
end

local function OnHide()
    if not closing and not UI.hidingForCombat and UI.ThemeChanged() then
        UI.NextFrame(DeferredRequestClose)
        return
    end
    if closePrompt then
        closePrompt:Hide()
    end
    UI.HideDialog()
    addon:CloseColorPicker(frame)
    UI.SaveSettings()
end

-------------------------------------------------------------------------------
-- Building the window
-------------------------------------------------------------------------------

local function BuildWindow()
    frame = UI.Popup("AshoholicLiveSettings", 900, 600)
    frame:SetFrameLevel(40)
    UI.settingsFrame = frame

    frame.logo = frame:CreateTexture(nil, "ARTWORK")
    frame.logo:SetPoint("TOPLEFT", 18, -14)
    frame.logo:SetSize(32, 32)
    frame.logo:SetTexture(state.logo)
    UI.Label(frame, "ASHOHOLIC SETTINGS", 60, 15, 500, 18, GOLD)
    UI.Label(frame, "Live dashboard / appearance and preferences are saved locally, not shared with account snapshots.",
        60, 38, 760, 10, MUTED)
    UI.Button(frame, "X", 856, 14, 28, 26, function()
        Settings.RequestClose()
    end)

    -- Section list on the left.
    local nav = UI.Surface(frame, 16, 70, 186, 476)
    frame.nav = {}
    for index, entry in ipairs(UI.SECTIONS) do
        local name = entry.name
        frame.nav[name] = UI.Button(nav, name, 8, 8 + (index - 1) * 42, 170, 34, function()
            Settings.Say("")
            Settings.ShowSection(name)
        end)
    end

    frame.sectionTitle = UI.Label(frame, "", 222, 74, 660, 16, GOLD)
    frame.sectionText = UI.Label(frame, "", 222, 98, 660, 10, MUTED)
    frame.status = UI.Label(frame, "", 222, 567, 340, 10, TEAL)
    UI.Button(frame, "Reset section", 582, 558, 140, 30, ResetSection)
    UI.Button(frame, "Close", 732, 558, 152, 30, function()
        Settings.RequestClose()
    end)
    frame:SetScript("OnHide", OnHide)
end

-------------------------------------------------------------------------------
-- Public functions
-------------------------------------------------------------------------------

-- Open Settings, optionally on a given section.
function UI.ShowSettings(section)
    UI.LoadSettings()
    if UI.HideAccountMenu then
        UI.HideAccountMenu()
    end
    if not UI.themeCheckpoint then
        UI.RememberTheme()
    end
    if not frame then
        BuildWindow()
    end
    -- Settings fits the screen like the main window, but ignores the
    -- window-scale slider so its own controls never move while dragging it.
    frame:SetScale(UI.BaseScale and UI.BaseScale() or 1)
    if not frame:IsShown() then
        Settings.Say("")
    end
    Settings.ShowSection(section or Settings.current or "Themes")
    frame:Show()
    frame:Raise()
end

function UI.ToggleSettings(section)
    if frame and frame:IsShown() then
        Settings.RequestClose()
    else
        UI.ShowSettings(section)
    end
end

-- Close Settings at once (the OnHide handler still checks for unsaved edits).
function UI.HideSettings()
    if frame and frame:IsShown() then
        frame:Hide()
    end
end

-- Redraw Settings after the look or the data changed. Does not save.
function UI.RefreshSettings()
    if not frame then
        return
    end
    frame.logo:SetTexture(state.logo)
    if frame:IsShown() then
        PaintNav()
        Settings.UpdateAll()
        local body = Settings.current and Settings.bodies[Settings.current]
        if body and body.Refresh then
            body.Refresh()
        end
    end
end
