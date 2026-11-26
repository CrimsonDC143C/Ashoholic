--[[
    UI/Widgets.lua - shared building blocks for every Ashoholic window.

    This is the first UI file in the .toc. It creates the addon.UI namespace
    and everything the other UI files share:

      * layout sizes and theme colors (the approved preview design),
      * UI.state: the local window preferences (theme, fonts, tabs ...),
      * widget constructors (Label, Surface, Button, Scroll, Progress ...),
      * one tooltip system used by every page,
      * text formatters (numbers, gold, ages, remaining time),
      * the small popup and dialog windows used by Settings.

    Data flow reminder: Game -> Collectors -> Data -> UI. Nothing in the UI
    folder calls game data APIs or reads AshoholicDB. The UI only reads the
    display-safe copies returned by addon.Data (see UI/Dashboard.lua).

    Two rules keep the theme system simple and leak-free:

      1. Color tables (UI.GOLD, UI.PANEL, UI.STYLE.rowOdd ...) are created once
         and only ever changed IN PLACE. Widgets keep references to them, so a
         theme change only has to repaint, never to rebuild.
      2. Widgets are created once and reused (pooled). WoW never frees frames,
         so creating new frames on every refresh would grow memory forever.
         The registries below therefore stay bounded by the pool sizes.
]]

local addonName = ...
local addon = _G[addonName]
local Data = addon.Data

if not Data then
    error("Ashoholic UI/Widgets.lua loaded before Data/Store.lua.")
end

local UI = addon.UI or {}
addon.UI = UI

-------------------------------------------------------------------------------
-- Layout sizes (pixels, before the window scale is applied)
-------------------------------------------------------------------------------

UI.WHITE = "Interface\\Buttons\\WHITE8X8"
UI.FONT = "Fonts\\FRIZQT__.TTF"
UI.WINDOW_WIDTH = 1320
UI.WINDOW_HEIGHT = 720
UI.CONTENT_WIDTH = UI.WINDOW_WIDTH - 48
UI.SCROLLBAR_WIDTH = 26
UI.SCROLL_WIDTH = UI.CONTENT_WIDTH - UI.SCROLLBAR_WIDTH
UI.PANEL_GAP = 20
UI.HALF_PANEL_WIDTH = (UI.SCROLL_WIDTH - UI.PANEL_GAP) / 2
UI.PAGE_TOP = 164
UI.PAGE_HEIGHT = 508
UI.FOCUS_PAGE_TOP = 110
UI.FOCUS_HEIGHT_GAIN = UI.PAGE_TOP - UI.FOCUS_PAGE_TOP
UI.TAB_TOP = 60

-- A saved character snapshot this old is shown as stale (log in to refresh).
UI.STALE_SECONDS = 7 * 86400

-------------------------------------------------------------------------------
-- Theme colors. Remember rule 1: change these tables in place only.
-------------------------------------------------------------------------------

UI.GOLD = { 1, 0.79, 0.39, 1 }
UI.TEXT = { 0.88, 0.88, 0.90, 1 }
UI.MUTED = { 0.58, 0.61, 0.67, 1 }
UI.TEAL = { 0.40, 0.86, 0.78, 1 }
UI.PANEL = { 0.075, 0.083, 0.105, 1 }
UI.BORDER = { 0.19, 0.21, 0.26, 1 }
UI.BUTTON_BG = { 0.10, 0.115, 0.145, 1 }
UI.BUTTON_BORDER = { 0.24, 0.26, 0.31, 1 }
UI.BACKGROUND = { 0.035, 0.042, 0.058, 0.99 }

-- Per-element colors that Customize Theme can change one by one.
UI.STYLE = {
    titleText = { 1, 0.79, 0.39, 1 },
    headerText = { 0.58, 0.61, 0.67, 1 },
    rowText = { 0.88, 0.88, 0.90, 1 },
    accountText = { 0.88, 0.88, 0.90, 1 },
    rowOdd = { 0.10, 0.115, 0.145, 1 },
    rowEven = { 0.12, 0.135, 0.165, 1 },
    rowAccount = { 0.075, 0.083, 0.105, 1 },
    rowHover = { 1, 0.8, 0.4, 0.09 },
    selectedBorder = { 1, 0.79, 0.39, 1 },
    buttonText = { 0.88, 0.88, 0.90, 1 },
    buttonHover = { 1, 0.8, 0.4, 0.09 },
    tabBg = { 0.10, 0.115, 0.145, 1 },
    tabActiveBg = { 0.075, 0.083, 0.105, 1 },
    tabText = { 0.58, 0.61, 0.67, 1 },
    tabActiveText = { 1, 0.79, 0.39, 1 },
}

-- Fixed status colors used inside text with WoW color escapes (|cff...|r).
UI.GREEN = "|cff7edba0"
UI.DIM = "|cff939baa"
UI.AMBER = "|cffffca63"
UI.RED = "|cffff7366"

-- Fixed colors with a meaning that must not change with the theme.
UI.LOOTED_COLOR = { 1, 0.45, 0.40, 1 }
UI.UNLOCKED_COLOR = { 0.16, 0.36, 0.31, 1 }
UI.TRACK_COLOR = { 0.16, 0.18, 0.22, 1 }

local GOLD, TEXT, MUTED, TEAL = UI.GOLD, UI.TEXT, UI.MUTED, UI.TEAL
local PANEL, BORDER = UI.PANEL, UI.BORDER
local BUTTON_BG, BUTTON_BORDER = UI.BUTTON_BG, UI.BUTTON_BORDER
local STYLE = UI.STYLE
local WHITE = UI.WHITE

-------------------------------------------------------------------------------
-- Small table helpers
-------------------------------------------------------------------------------

-- Copy the numbered part of one table into another (used for colors).
function UI.Copy(target, source)
    for index = 1, #source do
        target[index] = source[index]
    end
end

-- Deep copy, so saved settings never share tables with the live state.
function UI.Clone(source)
    if type(source) ~= "table" then
        return source
    end
    local result = {}
    for key, value in pairs(source) do
        result[key] = UI.Clone(value)
    end
    return result
end

-------------------------------------------------------------------------------
-- UI.state: local preferences for this installation
--
-- Settings, Theme and Dashboard all read and change this one table. It is
-- never replaced, only filled, so other files may keep a local reference.
-- Optional fields that may be nil: theme, customTheme, lastPreset, profile,
-- profileScope, rowHeight and selectedKey.
-------------------------------------------------------------------------------

UI.STATE_DEFAULTS = {
    tab = "Roster",
    detail = true,
    rosterFocus = false,
    raidsFocus = false,
    font = UI.FONT,
    fontDelta = 0,
    density = "comfortable",
    iconStyle = "icons",
    classIcons = true,
    statusStyle = "words",
    hiddenTabs = {},
    logo = "Interface\\Icons\\inv_soulash",
    scale = 1,
    opacity = 1,
    columnWidths = {},
    rosterOffset = 0,
    fontRoles = {},
    rowGap = 3,
    borderSize = 1,
    rosterSort = {},
    openTab = "last",
    window = { openLogin = false, combatHide = false, lockWindow = false, escClose = true },
    alerts = { reset = true, cache = true, boss = true, prestige = false, stale = true },
    alertStyle = "chat",
}

UI.state = {}
for key, value in pairs(UI.STATE_DEFAULTS) do
    UI.state[key] = UI.Clone(value)
end

-- Every column the roster can show. Settings > Roster Columns chooses which
-- ones are visible and in which order (UI.columnOrder).
UI.COLUMNS = {
    { key = "level", title = "Level" },
    { key = "ilvl", title = "Item level" },
    { key = "runAsh", title = "Run Ash" },
    { key = "runShards", title = "Run Shards" },
    { key = "gold", title = "Gold" },
    { key = "seen", title = "Last seen" },
    { key = "bonus", title = "Offering bonus" },
    { key = "offerings", title = "Offerings left" },
    { key = "build", title = "Echo build" },
    { key = "anchor", title = "Soul anchor" },
    { key = "location", title = "Location" },
}
UI.COLUMN_TITLES = {}
for _, column in ipairs(UI.COLUMNS) do
    UI.COLUMN_TITLES[column.key] = column.title
end
UI.DEFAULT_COLUMN_ORDER = { "level", "ilvl", "runAsh", "runShards", "gold", "seen" }

-- Like UI.state, this array is changed in place (wipe + refill), never replaced.
UI.columnOrder = {}
UI.Copy(UI.columnOrder, UI.DEFAULT_COLUMN_ORDER)

-- Replace the column order in place after checking every entry is a known,
-- unique column. An empty order is valid (Settings can untick every column);
-- a missing or damaged saved order falls back to the default order.
function UI.SetColumnOrder(order)
    local valid = type(order) == "table"
    local seen = {}
    if valid then
        for _, key in ipairs(order) do
            if not UI.COLUMN_TITLES[key] or seen[key] then
                valid = false
                break
            end
            seen[key] = true
        end
    end
    wipe(UI.columnOrder)
    UI.Copy(UI.columnOrder, valid and order or UI.DEFAULT_COLUMN_ORDER)
end

-------------------------------------------------------------------------------
-- Widget registries
--
-- Theme changes repaint every registered widget. Keys are the widgets
-- themselves, so registering twice cannot create duplicates, and the tables
-- stay as small as the widget pools.
-------------------------------------------------------------------------------

UI.labels = {}        -- [fontString] = { color = table, size = number, role = string }
UI.surfaces = {}      -- [frame] = background color table
UI.buttons = {}       -- [button] = true
UI.progressFills = {} -- [texture] = true
UI.popups = {}        -- [frame] = true (Settings, dialogs and prompts)

-- Tab pages. Each tab file registers a builder here:
--   UI.pageBuilders.Roster = function(parent) ... return page end
-- The returned page frame has page.Refresh(), which redraws it from
-- UI.model. UI/Window.lua builds a page the first time its tab is opened,
-- so tabs that are never visited never create their frames.
UI.pageBuilders = {}

local NO_OVERRIDE = {}
local backdrops = {}

-- One backdrop description per border size. SetBackdrop copies the values,
-- so every widget can share the same small table.
function UI.Backdrop(edgeSize)
    edgeSize = edgeSize or UI.state.borderSize or 1
    local backdrop = backdrops[edgeSize]
    if not backdrop then
        backdrop = { bgFile = WHITE, edgeFile = WHITE, edgeSize = edgeSize }
        backdrops[edgeSize] = backdrop
    end
    return backdrop
end

function UI.SetVisible(widget, visible)
    if visible then
        widget:Show()
    else
        widget:Hide()
    end
end

-- Long names must stay on one line inside table cells and buttons.
function UI.NoWrap(fontString)
    if fontString.SetWordWrap then
        fontString:SetWordWrap(false)
    end
end

-- Returns the font file and size for a text role (title, header, character,
-- account, button, hint or body). Customize Theme can override each role.
function UI.FontFor(role, size)
    local state = UI.state
    local override = state.fontRoles[role] or NO_OVERRIDE
    return override.font or state.font, math.max(8, size + state.fontDelta + (override.delta or 0))
end

-- Set a font safely. The default font is applied first, so a missing font
-- file (for example from an imported theme) leaves readable text instead of
-- a FontString without any font, which would make SetText fail.
function UI.ApplyFont(fontString, role, size)
    local font, height = UI.FontFor(role, size)
    fontString:SetFont(UI.FONT, height)
    if font ~= UI.FONT then
        fontString:SetFont(font, height)
    end
    return height
end

-------------------------------------------------------------------------------
-- Widget constructors. Positions use the preview's convention: x grows to
-- the right and y grows DOWNWARD from the parent's top-left corner.
-------------------------------------------------------------------------------

function UI.Label(parent, text, x, y, width, size, color, role)
    size = size or 12
    color = color or TEXT
    role = role or (size >= 17 and "title" or (color == MUTED and "hint" or "body"))
    if role == "title" and color == GOLD then
        color = STYLE.titleText
    end
    local fontString = parent:CreateFontString(nil, "OVERLAY")
    UI.ApplyFont(fontString, role, size)
    UI.labels[fontString] = { color = color, size = size, role = role }
    fontString:SetPoint("TOPLEFT", x, -y)
    fontString:SetWidth(width)
    fontString:SetJustifyH("LEFT")
    fontString:SetJustifyV("TOP")
    fontString:SetTextColor(unpack(color))
    fontString:SetText(text or "")
    return fontString
end

-- Change a label's theme color and remember it, so later theme changes keep it.
function UI.Paint(fontString, color)
    local entry = UI.labels[fontString]
    if entry then
        entry.color = color
    end
    fontString:SetTextColor(unpack(color))
end

function UI.Surface(parent, x, y, width, height, color)
    color = color or PANEL
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", x, -y)
    panel:SetSize(width, height)
    panel:SetBackdrop(UI.Backdrop())
    panel:SetBackdropColor(unpack(color))
    panel:SetBackdropBorderColor(unpack(BORDER))
    UI.surfaces[panel] = color
    return panel
end

-- Change a surface's background color and remember it for theme repaints.
function UI.SetSurfaceColor(panel, color)
    if UI.surfaces[panel] then
        UI.surfaces[panel] = color
    end
    panel:SetBackdropColor(unpack(color))
end

function UI.Button(parent, text, x, y, width, height, onClick)
    height = height or 28
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", x, -y)
    button:SetSize(width, height)
    button:SetBackdrop(UI.Backdrop())
    button:SetBackdropColor(unpack(BUTTON_BG))
    button:SetBackdropBorderColor(unpack(BUTTON_BORDER))
    button:SetHighlightTexture(WHITE)
    button:GetHighlightTexture():SetVertexColor(unpack(STYLE.buttonHover))
    button.text = UI.Label(button, text, 9, 7, width - 18, 11, STYLE.buttonText, "button")
    button.text:SetHeight(14)
    UI.NoWrap(button.text)
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    UI.buttons[button] = true
    return button
end

-- A scroll frame with the standard WoW scroll bar. The name is required by
-- UIPanelScrollFrameTemplate, which names its bar "<name>ScrollBar".
function UI.Scroll(parent, name, x, y, width, height)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", x, -y)
    scroll:SetSize(width - UI.SCROLLBAR_WIDTH, height)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width - UI.SCROLLBAR_WIDTH, height)
    scroll:SetScrollChild(child)
    return scroll, child
end

-- Move a named scroll frame by mouse-wheel steps (30 pixels per step).
function UI.ScrollBy(scroll, delta)
    local bar = _G[scroll:GetName() .. "ScrollBar"]
    if bar then
        bar:SetValue(bar:GetValue() - delta * 30)
    end
end

-- Keep the current scroll position valid after the content height changed.
function UI.ClampScroll(scroll, contentHeight, viewportHeight)
    local maximum = math.max(0, contentHeight - viewportHeight)
    scroll:UpdateScrollChildRect()
    if scroll:GetVerticalScroll() > maximum then
        scroll:SetVerticalScroll(maximum)
    end
end

-- A thin progress bar. Create it once, then call UI.SetProgress on refresh.
function UI.Progress(parent, x, y, width)
    local track = parent:CreateTexture(nil, "ARTWORK")
    track:SetTexture(WHITE)
    track:SetPoint("TOPLEFT", x, -y)
    track:SetSize(width, 5)
    track:SetVertexColor(unpack(UI.TRACK_COLOR))
    local fill = parent:CreateTexture(nil, "OVERLAY")
    fill:SetTexture(WHITE)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT")
    fill:SetSize(1, 5)
    fill:SetVertexColor(unpack(TEAL))
    UI.progressFills[fill] = true
    track.fill = fill
    track.fullWidth = width
    return track
end

-- Unknown progress hides the fill: an empty bar would wrongly suggest zero.
function UI.SetProgress(track, value, total)
    if type(value) ~= "number" or type(total) ~= "number" or total <= 0 then
        track.fill:Hide()
        return
    end
    local fraction = math.max(0, math.min(1, value / total))
    track.fill:SetWidth(math.max(1, track.fullWidth * fraction))
    track.fill:Show()
end

-- Page frame with the gold heading and muted subtitle from the preview.
function UI.Page(parent, heading, subtitle)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", 24, -UI.PAGE_TOP)
    page:SetSize(UI.CONTENT_WIDTH, UI.PAGE_HEIGHT)
    page.heading = UI.Label(page, heading, 0, 0, 720, 17, GOLD)
    page.subtitle = UI.Label(page, subtitle, 0, 27, UI.CONTENT_WIDTH, 11, MUTED)
    return page
end

-- A "title ......... value" line inside a panel. Returns the value label.
function UI.DetailLine(parent, title, value, y)
    local titleLabel = UI.Label(parent, title, 16, y, 168, 11, MUTED)
    local valueLabel = UI.Label(parent, value, 184, y, parent:GetWidth() - 200, 11)
    valueLabel:SetJustifyH("RIGHT")
    valueLabel.title = titleLabel
    return valueLabel
end

-- Character name in class color, optionally with the class icon.
function UI.ClassName(character)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[character.class]
    local r, g, b = 0.88, 0.88, 0.90
    if color then
        r, g, b = color.r, color.g, color.b
    end
    local icon = ""
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[character.class]
    if UI.state.classIcons and coords then
        icon = string.format(
            "|TInterface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes:14:14:0:0:256:256:%d:%d:%d:%d|t ",
            coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
    end
    return string.format("%s|cff%02x%02x%02x%s|r", icon, r * 255, g * 255, b * 255, character.name)
end

-------------------------------------------------------------------------------
-- Tooltips
--
-- Every widget uses the same two scripts, set only once. A widget either has
-- fixed text (UI.Tip) or a provider function (UI.TipProvider) that writes
-- fresh lines when the mouse enters. Providers read the data stored on the
-- widget at that moment, so refreshes never have to build tooltip tables.
-------------------------------------------------------------------------------

function UI.TipTitle(text)
    GameTooltip:AddLine(text, GOLD[1], GOLD[2], GOLD[3])
end

-- Adds "left .... right" when right is given, otherwise a wrapped line.
function UI.TipLine(left, right, color)
    local r, g, b = 0.85, 0.87, 0.9
    if color then
        r, g, b = color[1], color[2], color[3]
    end
    if right ~= nil then
        GameTooltip:AddDoubleLine(left, right, r, g, b, r, g, b)
    else
        GameTooltip:AddLine(left, r, g, b, true)
    end
end

local function ShowTip(owner)
    GameTooltip:SetOwner(owner, owner.tipAnchor or "ANCHOR_RIGHT")
    if owner.tipProvider then
        owner.tipProvider(owner)
    elseif owner.tipTitle then
        UI.TipTitle(owner.tipTitle)
        if owner.tipBody then
            UI.TipLine(owner.tipBody)
        end
    end
    if GameTooltip:NumLines() > 0 then
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

local function HideTip(owner)
    if GameTooltip:IsOwned(owner) then
        GameTooltip:Hide()
    end
end

local function HookTip(widget)
    if not widget.ashoholicTip then
        widget.ashoholicTip = true
        widget:EnableMouse(true)
        widget:SetScript("OnEnter", ShowTip)
        widget:SetScript("OnLeave", HideTip)
    end
end

-- Fixed tooltip text.
function UI.Tip(widget, title, body, anchor)
    widget.tipTitle, widget.tipBody, widget.tipAnchor = title, body, anchor
    HookTip(widget)
end

-- Tooltip written on hover by provider(widget).
function UI.TipProvider(widget, provider, anchor)
    widget.tipProvider, widget.tipAnchor = provider, anchor
    HookTip(widget)
end

-- Redraw an open tooltip after its widget's data changed.
function UI.RefreshTip(widget)
    if GameTooltip:IsOwned(widget) and widget:IsVisible() then
        ShowTip(widget)
    end
end

-------------------------------------------------------------------------------
-- Text formatters. Unknown values stay "Unknown"; they are never shown as 0.
-------------------------------------------------------------------------------

function UI.FormatNumber(value)
    if type(value) ~= "number" then
        return "Unknown"
    end
    local text = tostring(math.floor(value))
    local sign = ""
    if string.sub(text, 1, 1) == "-" then
        sign, text = "-", string.sub(text, 2)
    end
    local groups = {}
    while #text > 3 do
        table.insert(groups, 1, string.sub(text, -3))
        text = string.sub(text, 1, -4)
    end
    table.insert(groups, 1, text)
    return sign .. table.concat(groups, ",")
end

function UI.FormatCopper(copper)
    if type(copper) ~= "number" then
        return "Unknown"
    end
    local gold = UI.FormatNumber(math.floor(copper / 10000))
    local silver = math.floor((copper % 10000) / 100)
    return gold .. "g " .. silver .. "s " .. (copper % 100) .. "c"
end

-- Whole gold only, for small spaces such as a quest cost.
function UI.FormatGold(copper)
    if type(copper) ~= "number" then
        return "Unknown"
    end
    local gold = math.floor(copper / 10000)
    if gold > 0 then
        return UI.FormatNumber(gold) .. "g"
    end
    local silver = math.floor((copper % 10000) / 100)
    if silver > 0 then
        return silver .. "s"
    end
    return (copper % 100) .. "c"
end

-- Ages use time() (seconds since 1970), the same clock as every saved updatedAt.
function UI.FormatLastSeen(timestamp)
    if type(timestamp) ~= "number" then
        return "Unknown"
    end
    local elapsed = time() - timestamp
    if elapsed < 60 then
        return "Just now"
    elseif elapsed < 3600 then
        return math.floor(elapsed / 60) .. " min ago"
    elseif elapsed < 86400 then
        return math.floor(elapsed / 3600) .. " hr ago"
    end
    return math.floor(elapsed / 86400) .. " days ago"
end

function UI.RemainingTime(seconds)
    if seconds >= 86400 then
        return math.floor(seconds / 86400) .. "d " .. math.floor((seconds % 86400) / 3600) .. "h"
    elseif seconds >= 3600 then
        return math.floor(seconds / 3600) .. "h " .. math.floor((seconds % 3600) / 60) .. "m"
    elseif seconds >= 60 then
        return math.floor(seconds / 60) .. "m"
    end
    return "< 1m"
end

-- Torment tier names come from the companion's display rules (nil when the
-- rules could not be read).
function UI.TierName(tier, rules)
    if tier == nil then
        return "Unknown"
    end
    return rules and rules.tierNames[tier] or ("Unknown tier " .. tostring(tier))
end

function UI.Short(number)
    if number >= 1000000 then
        return string.format("%.1fm", number / 1000000)
    elseif number >= 1000 then
        return string.format("%.2fk", number / 1000)
    end
    return tostring(number)
end

-------------------------------------------------------------------------------
-- Popups and the shared dialog
-------------------------------------------------------------------------------

-- A movable top-level window. Adding its name to UISpecialFrames lets the
-- Escape key close it, which also runs its OnHide clean-up.
function UI.Popup(name, width, height)
    local popup = CreateFrame("Frame", name, UIParent)
    popup:SetSize(width, height)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(120)
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    popup:SetBackdrop(UI.Backdrop(1))
    UI.PaintPopup(popup)
    popup:Hide()
    tinsert(UISpecialFrames, name)
    UI.popups[popup] = true
    return popup
end

function UI.PaintPopup(popup)
    local background = UI.BACKGROUND
    popup:SetBackdropColor(background[1], background[2], background[3], 0.99)
    popup:SetBackdropBorderColor(GOLD[1] * 0.6, GOLD[2] * 0.6, GOLD[3] * 0.6, 1)
end

local dialog

local function DialogAccept()
    local options = dialog.options or NO_OVERRIDE
    local value = dialog.box:GetText()
    if options.validate then
        local errorText = options.validate(value)
        if errorText then
            dialog.text:SetText(errorText)
            dialog.box:SetFocus()
            dialog.box:HighlightText()
            return
        end
    end
    -- Accepted: clear the options first so OnHide does not run onCancel.
    dialog.options = nil
    dialog:Hide()
    if options.onAccept then
        options.onAccept(value)
    end
end

local function BuildDialog()
    dialog = UI.Popup("AshoholicLiveDialog", 460, 262)
    dialog.title = UI.Label(dialog, "", 18, 16, 424, 15, GOLD)
    dialog.text = UI.Label(dialog, "", 18, 46, 424, 11)
    dialog.boxBg = UI.Surface(dialog, 14, 118, 432, 78, { 0.02, 0.025, 0.035, 1 })
    dialog.box = CreateFrame("EditBox", nil, dialog.boxBg)
    dialog.box:SetPoint("TOPLEFT", 8, -8)
    dialog.box:SetSize(416, 62)
    dialog.box:SetMultiLine(true)
    -- No length limit: exported theme strings are much longer than a name.
    dialog.box:SetMaxLetters(0)
    dialog.box:SetAutoFocus(false)
    dialog.box:SetFontObject(ChatFontNormal)
    dialog.box:SetScript("OnEscapePressed", dialog.box.ClearFocus)
    dialog:SetScript("OnHide", function(self)
        self.box:ClearFocus()
        local options = self.options
        self.options = nil
        if options and options.onCancel then
            options.onCancel()
        end
    end)
    dialog.primary = UI.Button(dialog, "", 18, 216, 200, 28, DialogAccept)
    dialog.secondary = UI.Button(dialog, "Cancel", 242, 216, 200, 28, function()
        dialog:Hide()
    end)
end

--[[
    UI.Dialog(title, text, options) shows a message, optionally with a text box.
    options (all optional):
      box       - starting text; shows the text box when not nil
      primary   - main button text; also shows a Cancel button
      validate  - function(value) returning an error text, or nil when valid
      onAccept  - function(value) called after a valid accept
      onCancel  - function() called when the dialog closes without accepting
]]
function UI.Dialog(title, text, options)
    if not dialog then
        BuildDialog()
    end
    -- Closing an older dialog first runs its onCancel, so its clean-up
    -- (for example restoring a color) is never skipped.
    if dialog:IsShown() then
        dialog:Hide()
    end
    options = options or {}
    dialog:SetScale(UI.settingsFrame and UI.settingsFrame:GetScale() or 1)
    dialog.title:SetText(title)
    dialog.text:SetText(text)
    UI.SetVisible(dialog.boxBg, options.box ~= nil)
    dialog.box:SetText(options.box or "")
    dialog.primary.text:SetText(options.primary or "OK")
    UI.SetVisible(dialog.secondary, options.primary ~= nil)
    dialog.options = options
    dialog:Show()
    dialog:Raise()
    if options.box then
        dialog.box:SetFocus()
        dialog.box:HighlightText()
    end
end

function UI.HideDialog()
    if dialog then
        dialog:Hide()
    end
end

-------------------------------------------------------------------------------
-- Work for the next screen frame
--
-- UI.NextFrame(fn) runs fn once, on the next frame WoW draws. It is used to
--   * redraw once after many saved-data changes arrive together, and
--   * react to a window closing only after WoW's Escape handler has
--     finished closing the other windows in UISpecialFrames.
-- Asking twice for the same function before it runs queues it only once.
-- The helper frame is hidden while the queue is empty, so it costs nothing
-- when there is no work.
-------------------------------------------------------------------------------

local pending, spare, queued = {}, {}, {}
local runner = CreateFrame("Frame")
runner:Hide()
runner:SetScript("OnUpdate", function(self)
    self:Hide()
    -- Swap the lists first: work queued while these functions run goes to
    -- the other list and runs on the following frame.
    local list = pending
    pending, spare = spare, list
    for index = 1, #list do
        local work = list[index]
        list[index] = nil
        queued[work] = nil
        -- An error in one function must not drop the rest of the queue, so
        -- it is reported through WoW's error handler instead of stopping here.
        local ok, problem = pcall(work)
        if not ok then
            geterrorhandler()(problem)
        end
    end
end)

function UI.NextFrame(work)
    if not queued[work] then
        queued[work] = true
        pending[#pending + 1] = work
        runner:Show()
    end
end
