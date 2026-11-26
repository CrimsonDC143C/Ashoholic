--[[
    UI/SettingsAppearance.lua - the appearance sections of Settings:
    Themes, Customize Theme and Icons.

    Each section registers two functions with UI/Settings.lua:
      build(body)  creates the section's controls, once, on the first visit
      reset()      restores the section's defaults ("Reset section")

    Everything here changes the LOCAL look of Ashoholic on this WoW
    installation; it is never part of an account snapshot or Sync.

    How theme editing works:
      1. The player picks a default preset (Themes) or one of their own
         custom presets.
      2. They change colors, fonts or layout (Customize Theme). Every change
         shows at once, because the color tables (UI.GOLD, UI.STYLE ...) are
         changed in place and UI.ApplyAppearance() repaints every widget.
      3. They save the result as a custom preset, update the selected custom
         preset, or discard the edits when Settings closes (UI/Settings.lua).
]]

local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local UI = addon.UI

if not UI or not UI.Settings then
    error("Ashoholic UI/SettingsAppearance.lua loaded before UI/Settings.lua.")
end

local Settings = UI.Settings
local state = UI.state
local GOLD, MUTED, BUTTON_BORDER, STYLE = UI.GOLD, UI.MUTED, UI.BUTTON_BORDER, UI.STYLE

-- Value texts shown beside the sliders.
local function Pixels(value)
    return string.format("%d px", value)
end

local function Percent(value)
    return string.format("%.0f%%", value * 100)
end

-------------------------------------------------------------------------------
-- Themes: the default presets and the player's custom presets
-------------------------------------------------------------------------------

-- Ask for a new name for a custom preset.
local function RenameTheme(target)
    UI.Dialog("Rename preset", "Rename this saved custom preset. Default presets cannot be renamed.", {
        box = target.name,
        primary = "Rename",
        validate = function(value)
            local _, problem = Settings.CheckThemeName(value, target.id)
            return problem
        end,
        onAccept = function(value)
            local name = Settings.CheckThemeName(value, target.id)
            target.name = name
            if state.customTheme == target.id then
                state.theme = name
            end
            -- The "Discard changes" checkpoint keeps the preset's name too.
            local checkpoint = UI.themeCheckpoint
            if checkpoint and checkpoint.customTheme == target.id then
                checkpoint.name = name
            end
            Settings.ShowSection("Themes")
        end,
    })
end

-- Ask, then delete a custom preset. The current look stays applied; it
-- simply no longer belongs to a saved preset.
local function DeleteTheme(target)
    UI.Dialog("Delete custom preset", "Delete '" .. target.name .. "'? Your current appearance remains applied.", {
        primary = "Delete",
        onAccept = function()
            local _, index = UI.FindCustomTheme(target.id)
            if index then
                table.remove(UI.customThemes, index)
            end
            if state.customTheme == target.id then
                state.customTheme, state.theme = nil, "Custom"
            end
            local checkpoint = UI.themeCheckpoint
            if checkpoint and checkpoint.customTheme == target.id then
                checkpoint.customTheme, checkpoint.name = nil, "Custom"
            end
            Settings.ShowSection("Themes")
        end,
    })
end

-- Sort order of the custom preset list: starred first, then oldest first.
local function StarredFirst(left, right)
    if (left.starred == true) ~= (right.starred == true) then
        return left.starred == true
    end
    return left.id < right.id
end

local function BuildThemes(body)
    local scroll, gallery = UI.Scroll(body, "AshoholicThemeGallery", 0, 0, 660, 350)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", UI.ScrollBy)
    UI.Label(gallery, "DEFAULT PRESETS", 0, 0, 630, 11, GOLD)

    -- One card per default preset: name, description and four color swatches.
    local cards = {}
    for index, preset in ipairs(UI.THEMES) do
        local card = UI.Button(gallery, preset.name, ((index - 1) % 2) * 320, 24 + math.floor((index - 1) / 2) * 82,
            310, 72, function()
                UI.ApplyPreset(preset)
                Settings.Persist()
            end)
        UI.Label(card, preset.description, 9, 27, 200, 10, MUTED)
        for swatchIndex, color in ipairs({ preset.background, preset.panel, preset.border, preset.accent }) do
            local swatch = card:CreateTexture(nil, "OVERLAY")
            swatch:SetTexture(UI.WHITE)
            swatch:SetVertexColor(color[1], color[2], color[3], 1)
            swatch:SetPoint("TOPLEFT", 214 + (swatchIndex - 1) * 24, -22)
            swatch:SetSize(20, 28)
        end
        card.value = preset.name
        cards[index] = card
    end
    cards.Update = function()
        local active = state.theme or "Ember & Ash"
        for _, card in ipairs(cards) do
            card:SetBackdropBorderColor(unpack(card.value == active and GOLD or BUTTON_BORDER))
        end
    end
    Settings.AddGroup(cards)

    -- Custom presets below the default ones. Rows are pooled: a row is
    -- created the first time it is needed and reused afterwards.
    local customY = 24 + math.ceil(#UI.THEMES / 2) * 82
    UI.Label(gallery, "CUSTOM PRESETS  /  Starred first", 0, customY, 630, 11, GOLD)
    local empty = UI.Label(gallery, "No custom presets yet. Customize a default preset, then save your own.",
        0, customY + 28, 630, 11, MUTED)
    local rows, sorted = {}, {}

    local function CreateRow()
        local row = CreateFrame("Frame", nil, gallery)
        row:SetSize(630, 64)
        row.apply = UI.Button(row, "", 0, 0, 272, 28, function()
            UI.ApplyCustomTheme(row.theme)
            Settings.Persist()
        end)
        row.star = UI.Button(row, "", 280, 0, 92, 28, function()
            row.theme.starred = (not row.theme.starred) or nil
            Settings.ShowSection("Themes")
        end)
        UI.Button(row, "Edit", 380, 0, 70, 28, function()
            UI.ApplyCustomTheme(row.theme)
            Settings.ShowSection("Customize Theme")
        end)
        UI.Button(row, "Rename", 458, 0, 82, 28, function()
            RenameTheme(row.theme)
        end)
        UI.Button(row, "Delete", 548, 0, 82, 28, function()
            DeleteTheme(row.theme)
        end)
        UI.Label(row, "Saved colors, fonts, icons and row layout", 9, 36, 600, 10, MUTED)
        return row
    end

    body.Refresh = function()
        wipe(sorted)
        for index, theme in ipairs(UI.customThemes) do
            sorted[index] = theme
        end
        table.sort(sorted, StarredFirst)
        for index, theme in ipairs(sorted) do
            local row = rows[index]
            if not row then
                row = CreateRow()
                rows[index] = row
            end
            row.theme = theme
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(customY + 28 + (index - 1) * 64))
            row.apply.text:SetText(theme.name)
            row.apply:SetBackdropBorderColor(unpack(state.customTheme == theme.id and GOLD or BUTTON_BORDER))
            row.star.text:SetText(theme.starred and "* Starred" or "Star")
            row:Show()
        end
        for index = #sorted + 1, #rows do
            -- Unused rows forget their preset, so a deleted preset is not kept alive.
            rows[index].theme = nil
            rows[index]:Hide()
        end
        UI.SetVisible(empty, #sorted == 0)
        local height = customY + 28 + math.max(1, #sorted) * 64
        gallery:SetHeight(height)
        UI.ClampScroll(scroll, height, 350)
    end

    UI.Button(body, "Customize...", 0, 360, 180, 30, function()
        Settings.ShowSection("Customize Theme")
    end)
    UI.Button(body, "Save as custom...", 188, 360, 210, 30, function()
        Settings.SaveCustomTheme()
    end)
    UI.Button(body, "Import...", 406, 360, 210, 30, function()
        Settings.ShowSection("Profiles & Sharing")
    end)
    UI.Label(body, "Default presets are read-only. Custom presets are saved on this installation;"
        .. " account filters are never included.", 0, 400, 660, 10, MUTED)
end

-------------------------------------------------------------------------------
-- Customize Theme: colors, fonts and layout in one scrolling editor
-------------------------------------------------------------------------------

-- Every color the player can change, in display order. The tables are the
-- live theme colors themselves, so changing one recolors the whole UI.
local COLOR_SLOTS = {
    { "Window background", UI.BACKGROUND }, { "Panels & rows", UI.PANEL }, { "Borders", UI.BORDER },
    { "Buttons", UI.BUTTON_BG }, { "Accent / headings", UI.GOLD }, { "Body text", UI.TEXT },
    { "Secondary text", UI.MUTED }, { "Highlighted values", UI.TEAL },
    { "Button borders", UI.BUTTON_BORDER }, { "Button text", STYLE.buttonText },
    { "Button hover", STYLE.buttonHover }, { "Title text", STYLE.titleText },
    { "Column header text", STYLE.headerText }, { "Character row text", STYLE.rowText },
    { "Account name text", STYLE.accountText }, { "Account row background", STYLE.rowAccount },
    { "Odd character rows", STYLE.rowOdd }, { "Even character rows", STYLE.rowEven },
    { "Character row hover", STYLE.rowHover }, { "Selected row border", STYLE.selectedBorder },
    { "Tab background", STYLE.tabBg }, { "Active tab background", STYLE.tabActiveBg },
    { "Tab text", STYLE.tabText }, { "Active tab text", STYLE.tabActiveText },
}

-- Fonts that exist in every 3.3.5 client.
local FONTS = {
    { "Fonts\\FRIZQT__.TTF", "Friz Quadrata" }, { "Fonts\\ARIALN.TTF", "Arial Narrow" },
    { "Fonts\\MORPHEUS.TTF", "Morpheus" }, { "Fonts\\skurri.ttf", "Skurri" },
}
local ROLE_FONTS = { { "inherit", "Global font" }, FONTS[1], FONTS[2], FONTS[3], FONTS[4] }
local TEXT_SIZES = { { -1, "Small" }, { 0, "Normal" }, { 1, "Large" }, { 2, "Larger" } }

-- Text roles with their own font and size adjustment (see UI.FontFor).
local FONT_ROLES = {
    { "title", "Titles" }, { "header", "Column headers" }, { "character", "Character values" },
    { "account", "Account names" }, { "button", "Buttons" }, { "hint", "Hints" },
}

local DENSITIES = { { "compact", "Compact" }, { "comfortable", "Comfortable" }, { "spacious", "Spacious" } }

-- One font-role override field ("font" or "delta"), or nil when not set.
-- state.fontRoles is read every time, because loading a profile or a reset
-- replaces that table.
local function RoleValue(role, field)
    local override = state.fontRoles[role]
    return override and override[field]
end

-- nil removes the field. An override without any field is removed too, so
-- choosing the defaults again counts as "no change" for unsaved edits.
local function SetRoleValue(role, field, value)
    local roles = state.fontRoles
    local override = roles[role] or {}
    override[field] = value
    if next(override) then
        roles[role] = override
    else
        roles[role] = nil
    end
end

-- The density's own row height, used while no exact height is chosen.
local function DensityHeight()
    if state.density == "compact" then
        return 30
    elseif state.density == "spacious" then
        return 54
    end
    return 44
end

-- The 24 color rows. Returns the height they use.
local function BuildColors(editor)
    local colorBody = CreateFrame("Frame", nil, editor)
    colorBody:SetPoint("TOPLEFT", 0, 0)
    colorBody:SetWidth(634)
    UI.Label(colorBody, "COLORS & OPACITY", 0, 0, 630, 11, GOLD)

    local swatches = {}
    for index, slot in ipairs(COLOR_SLOTS) do
        local title, target = slot[1], slot[2]
        local row = UI.Surface(colorBody, ((index - 1) % 2) * 320, 28 + math.floor((index - 1) / 2) * 52, 310, 44)
        UI.Label(row, title, 9, 15, 143, 11)
        local swatch = row:CreateTexture(nil, "OVERLAY")
        swatch:SetTexture(UI.WHITE)
        swatch:SetPoint("TOPLEFT", 158, -9)
        swatch:SetSize(24, 26)
        swatches[index] = swatch

        -- The color picker calls this many times per second while dragging,
        -- so the repaint waits for the next frame and runs once per frame.
        local function SetColor(color)
            UI.Copy(target, color)
            state.theme = "Custom"
            UI.NextFrame(UI.ApplyAppearance)
            Settings.Say(title .. " changed. Save or update your custom preset to keep this draft.")
        end
        UI.Button(row, "Change", 190, 8, 70, 28, function()
            UI.PickColor(SetColor, target)
        end)
        local hex = UI.Button(row, "Hex", 264, 8, 42, 28, function()
            UI.EditColorHex(title, SetColor, target)
        end)
        UI.Tip(hex, title .. " RGBA hex", "Enter an exact RGB color and optional alpha value.")
    end
    Settings.AddGroup({ Update = function()
        for index, slot in ipairs(COLOR_SLOTS) do
            local color = slot[2]
            swatches[index]:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
        end
    end })

    local height = 28 + math.ceil(#COLOR_SLOTS / 2) * 52
    colorBody:SetHeight(height)
    return height
end

-- Font and size choices for one text role.
local function BuildRoleFont(parent, role, title, y)
    UI.Label(parent, string.upper(title) .. " FONT", 0, y, 630, 11, GOLD)
    Settings.Choices(parent, ROLE_FONTS, 0, y + 22, 200, 3,
        function()
            return RoleValue(role, "font") or "inherit"
        end,
        function(value)
            SetRoleValue(role, "font", value ~= "inherit" and value or nil)
            UI.ApplyAppearance()
        end)
    Settings.SliderRow(parent, title .. " size adjustment", 0, y + 88, -2, 4, 1,
        function()
            return RoleValue(role, "delta") or 0
        end,
        function(value)
            SetRoleValue(role, "delta", value ~= 0 and value or nil)
            UI.NextFrame(UI.ApplyAppearance)
        end, Pixels)
end

-- Global font, text size and the six text roles. Returns the height used.
local function BuildFonts(editor, top)
    local textBody = CreateFrame("Frame", nil, editor)
    textBody:SetPoint("TOPLEFT", 0, -top)
    textBody:SetWidth(634)
    UI.Label(textBody, "GLOBAL FONT", 0, 0, 300, 11, GOLD)
    Settings.Choices(textBody, FONTS, 0, 22, 152, 4,
        function()
            return state.font
        end,
        function(value)
            state.font = value
            UI.ApplyAppearance()
        end)
    UI.Label(textBody, "TEXT SIZE", 0, 72, 300, 11, GOLD)
    Settings.Choices(textBody, TEXT_SIZES, 0, 94, 152, 4,
        function()
            return state.fontDelta
        end,
        function(value)
            state.fontDelta = value
            UI.ApplyAppearance()
        end)
    for index, entry in ipairs(FONT_ROLES) do
        BuildRoleFont(textBody, entry[1], entry[2], 156 + (index - 1) * 156)
    end
    local height = 156 + #FONT_ROLES * 156
    textBody:SetHeight(height)
    return height
end

-- Row density, window scale, opacity, row height and spacing, borders.
-- Returns the height used.
local function BuildLayout(editor, top)
    local layoutBody = CreateFrame("Frame", nil, editor)
    layoutBody:SetPoint("TOPLEFT", 0, -top)
    layoutBody:SetSize(634, 444)
    UI.Label(layoutBody, "ROSTER ROW DENSITY", 0, 0, 300, 11, GOLD)
    Settings.Choices(layoutBody, DENSITIES, 0, 22, 204, 3,
        function()
            return state.density
        end,
        function(value)
            -- A new density also uses that density's own row height again.
            state.density, state.rowHeight = value, nil
            UI.Refresh()
        end)
    Settings.SliderRow(layoutBody, "WINDOW SCALE", 0, 74, 0.7, 1.2, 0.05,
        function()
            return state.scale
        end,
        function(value)
            state.scale = value
            UI.ApplyScale()
        end, Percent)
    Settings.SliderRow(layoutBody, "BACKGROUND OPACITY", 0, 134, 0, 1, 0.01,
        function()
            return UI.BACKGROUND[4]
        end,
        function(value)
            UI.BACKGROUND[4] = value
            UI.PaintWindow()
        end, Percent)
    UI.Label(layoutBody, "Compact hides character hints. Scale and background opacity affect only the main window.",
        0, 202, 630, 10, MUTED)
    Settings.SliderRow(layoutBody, "ROSTER ROW HEIGHT (content minimum applies)", 0, 244, 30, 70, 1,
        function()
            return state.rowHeight or DensityHeight()
        end,
        function(value)
            state.rowHeight = value
            UI.NextFrame(UI.Refresh)
        end, Pixels)
    Settings.SliderRow(layoutBody, "ROSTER ROW SPACING", 0, 306, 0, 12, 1,
        function()
            return state.rowGap
        end,
        function(value)
            state.rowGap = value
            UI.NextFrame(UI.Refresh)
        end, Pixels)
    Settings.SliderRow(layoutBody, "PANEL & BUTTON BORDER THICKNESS", 0, 368, 1, 4, 1,
        function()
            return state.borderSize
        end,
        function(value)
            state.borderSize = value
            UI.NextFrame(UI.ApplyAppearance)
        end, Pixels)
    return 444
end

-- "Revert to default": the colors of the default preset this look started from.
local function RevertToPreset()
    local preset = UI.FindPreset(state.lastPreset or "Ember & Ash") or UI.THEMES[1]
    UI.ApplyPreset(preset)
    Settings.Say("Reverted to " .. preset.name .. ".")
    Settings.Persist()
end

local function BuildCustomize(body)
    local scroll, editor = UI.Scroll(body, "AshoholicThemeEditor", 0, 34, 660, 316)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", UI.ScrollBy)

    -- The three groups are stacked in one scrolling editor, 24 pixels apart.
    local colorHeight = BuildColors(editor)
    local fontTop = colorHeight + 24
    local layoutTop = fontTop + BuildFonts(editor, fontTop) + 24
    editor:SetHeight(layoutTop + BuildLayout(editor, layoutTop))

    -- Jump buttons above the editor. Moving the scroll bar moves the view,
    -- and the bar itself keeps the value inside the scrollable range.
    local bar = _G[scroll:GetName() .. "ScrollBar"]
    for index, jump in ipairs({ { "Colors", 0 }, { "Fonts", fontTop }, { "Layout", layoutTop } }) do
        local offset = jump[2]
        UI.Button(body, jump[1], (index - 1) * 218, 0, 210, 28, function()
            bar:SetValue(offset)
        end)
    end

    UI.Button(body, "Save as new...", 0, 360, 190, 30, function()
        Settings.SaveCustomTheme()
    end)
    UI.Button(body, "Update selected", 198, 360, 210, 30, function()
        Settings.UpdateCustomTheme()
    end)
    UI.Button(body, "Revert to default", 416, 360, 210, 30, RevertToPreset)
    UI.Label(body, "Colors, fonts, icons and row layout save together. Class and loot-status colors keep their meaning.",
        0, 400, 660, 10, MUTED)
end

-- The look options of this section, restored to their defaults by "Reset section".
local CUSTOMIZE_KEYS = { "font", "fontDelta", "density", "scale", "fontRoles", "rowGap", "borderSize" }

local function ResetCustomize()
    for _, key in ipairs(CUSTOMIZE_KEYS) do
        state[key] = UI.Clone(UI.STATE_DEFAULTS[key])
    end
    state.rowHeight = nil
    -- A preset keeps the background opacity, so it is reset separately.
    UI.BACKGROUND[4] = 0.99
    UI.ApplyScale()
    UI.ApplyPreset(UI.THEMES[1])
end

-------------------------------------------------------------------------------
-- Icons: currency icons, loot status style, class icons and the logo
-------------------------------------------------------------------------------

-- The logo is shown in both window titles and on the minimap button.
local function SetLogo(path, message)
    state.logo = path
    UI.ApplyAppearance()
    Settings.Say(message)
    Settings.Persist()
end

-- The minimap button's visibility is saved with its position through Data.
local function MinimapShown()
    return not Data.GetMinimapSettings().hidden
end

local function SetMinimapShown(shown)
    local minimap = Data.GetMinimapSettings()
    Data.SaveMinimapSettings(minimap.angle, not shown)
    addon.Minimap.Refresh()
end

local function AskCustomLogo()
    UI.Dialog("Custom icon", "Enter an existing game icon path, such as Interface\\Icons\\INV_Misc_QuestionMark.", {
        box = "Interface\\Icons\\INV_Misc_QuestionMark",
        primary = "Use icon",
        validate = function(value)
            local path = Settings.Trim(value)
            if path == "" or #path > 255 or path:find("[%c|]") then
                return "Enter a plain game icon path of 1-255 characters."
            end
        end,
        onAccept = function(value)
            SetLogo(Settings.Trim(value), "Custom icon applied.")
        end,
    })
end

local function BuildIcons(body)
    UI.Label(body, "CURRENCY ICONS", 0, 0, 300, 11, GOLD)
    Settings.Choices(body, { { "icons", "Ebonhold icons" }, { "large", "Large icons" }, { "text", "Text only" } },
        0, 22, 210, 3,
        function()
            return state.iconStyle
        end,
        function(value)
            state.iconStyle = value
            UI.Refresh()
        end)
    UI.Label(body, "RAID LOOT STATUS", 0, 72, 300, 11, GOLD)
    Settings.Choices(body, { { "words", "Words (Available / Looted)" }, { "icons", "Ready-check symbols" } },
        0, 94, 320, 2,
        function()
            return state.statusStyle
        end,
        function(value)
            state.statusStyle = value
            UI.Refresh()
        end)
    Settings.Toggle(body, "Show class icons beside names", 0, 140, 320,
        function()
            return state.classIcons
        end,
        function(value)
            state.classIcons = value
            UI.Refresh()
        end)

    UI.Label(body, "ASHOHOLIC LOGO & MINIMAP ICON", 0, 190, 400, 11, GOLD)
    local logoButtons = {}
    for index, path in ipairs(UI.LOGOS) do
        local button = UI.Button(body, "", (index - 1) * 54, 214, 46, 46, function()
            SetLogo(path, "Logo and minimap icon updated.")
        end)
        local texture = button:CreateTexture(nil, "ARTWORK")
        texture:SetPoint("TOPLEFT", 4, -4)
        texture:SetPoint("BOTTOMRIGHT", -4, 4)
        texture:SetTexture(path)
        -- Trim the icon's built-in border.
        texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        button.value = path
        logoButtons[index] = button
    end
    logoButtons.Update = function()
        for _, button in ipairs(logoButtons) do
            button:SetBackdropBorderColor(unpack(state.logo == button.value and GOLD or BUTTON_BORDER))
        end
    end
    Settings.AddGroup(logoButtons)
    UI.Button(body, "Use custom icon path...", 0, 276, 240, 30, AskCustomLogo)
    Settings.Toggle(body, "Show minimap icon", 0, 324, 320, MinimapShown, SetMinimapShown)
end

local ICON_KEYS = { "iconStyle", "statusStyle", "classIcons", "logo" }

local function ResetIcons()
    for _, key in ipairs(ICON_KEYS) do
        state[key] = UI.STATE_DEFAULTS[key]
    end
    SetMinimapShown(true)
    UI.ApplyAppearance()
end

-------------------------------------------------------------------------------
-- Registration
-------------------------------------------------------------------------------

Settings.sections["Themes"] = {
    build = BuildThemes,
    reset = function()
        UI.ApplyPreset(UI.THEMES[1])
    end,
}
Settings.sections["Customize Theme"] = { build = BuildCustomize, reset = ResetCustomize }
Settings.sections["Icons"] = { build = BuildIcons, reset = ResetIcons }
