local addonName, addon = ...

-- ── The Toolbelt UI ──────────────────────────────────────────────────────────
-- A micro button on the Blizzard bar (slot owned by skillTreeMicroButton.lua's
-- getCoreMicroButtons) opening a menu upward: Waystones on top, then Bank,
-- Guild Bank, Mailbox, Auction House, Call Board, Portable Affix-Anvil, Portable
-- Forge, Vendor and Scavenger's Eye. Each entry is a panel, except the six that open
-- a window right away and the Forge, which sets one up. Locked entries stay
-- visible, greyed, with a lock.
--
-- The client's own look throughout: the menu is a dropdown list (dark dialog box,
-- quest-title highlight, closes itself once the mouse has left it), the panels are
-- the professions window's portrait frame and marble inset (ezCollections templates,
-- as talent_frame.lua and contracts.lua build them). Those templates load after this
-- file, so each panel builds its chrome and its content on first show.

local Service = ProjectEbonhold.ToolbeltService
local CHAT_PREFIX = "|cff00ff00[Project Ebonhold]|r "

local GREY = { 0.62, 0.62, 0.62 }
local RULE = { 0.72, 0.58, 0.25 }

local QUALITY_COLOR = {
    [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00", [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000",
}
local QUALITY_NAME = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }

local ICON_WAYSTONES = "Interface\\Icons\\Spell_Arcane_PortalDalaran"
local ICON_VENDOR    = "Interface\\Icons\\INV_Misc_Coin_02"
local ICON_EYE       = "Interface\\Icons\\INV_Misc_Eye_01"

local function GetSetting(key)
    if ProjectEbonholdOptionsService then return ProjectEbonholdOptionsService:GetSetting(key) end
end
local function SetSetting(key, value)
    if ProjectEbonholdOptionsService then ProjectEbonholdOptionsService:SetSetting(key, value) end
end

local function HasBit(mask, bitIndex)
    return math.floor((mask or 0) / (2 ^ bitIndex)) % 2 == 1
end
local function ToggleBit(mask, bitIndex)
    if HasBit(mask, bitIndex) then return mask - 2 ^ bitIndex end
    return mask + 2 ^ bitIndex
end

-- Coin icons as the merchant shows them; the addon's coloured g/s/c if the helper is missing.
local function Money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    return Service.FormatMoney(copper)
end

-- ── Shared widgets ───────────────────────────────────────────────────────────
local DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local function AddTooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Gold title over a thin gold rule fading out to the right (the Torment frame's header).
local function SectionHeader(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 14, y)
    fs:SetText(text)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 12, y - 16)
    rule:SetPoint("TOPRIGHT", -14, y - 16)
    rule:SetTexture(1, 1, 1, 1)
    rule:SetGradientAlpha("HORIZONTAL", RULE[1], RULE[2], RULE[3], 1, RULE[1], RULE[2], RULE[3], 0)
    return fs
end

-- A grey note that wraps inside the inset.
local function Note(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 14, y)
    fs:SetPoint("TOPRIGHT", -16, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetTextColor(unpack(GREY))
    return fs
end

-- The Interface Options check box: click sound, white label, tooltip.
local function MakeCheck(parent, name, label, x, y, onClick, tipTitle, tipText)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    cb.text = _G[name .. "Text"]
    cb.text:SetFontObject(GameFontHighlightSmall)
    cb.text:ClearAllPoints()
    cb.text:SetPoint("LEFT", cb, "RIGHT", 1, 1)
    cb.text:SetText(label)
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() == 1
        PlaySound(checked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
        onClick(checked)
    end)
    if tipTitle then AddTooltip(cb, tipTitle, tipText) end
    return cb
end

local function MakeDropDown(parent, name, x, y, width, tipTitle, tipText)
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dd, width)
    if tipTitle then AddTooltip(_G[name .. "Button"], tipTitle, tipText) end
    return dd
end

local function QualityItems(dd, from, to, current, onPick)
    for q = from, to do
        local info = UIDropDownMenu_CreateInfo()
        info.text = QUALITY_COLOR[q] .. QUALITY_NAME[q] .. "|r"
        info.value = q
        info.checked = (q == current)
        info.func = function() onPick(q) end
        UIDropDownMenu_AddButton(info)
    end
end

local function SetDropDownQuality(dd, q)
    UIDropDownMenu_SetSelectedValue(dd, q)
    UIDropDownMenu_SetText(dd, (QUALITY_COLOR[q] or "") .. (QUALITY_NAME[q] or "?") .. "|r")
end

-- The bottom-bar action button (UIPanelButtonTemplate, the client's own).
local function BarButton(parent, name, label, width, onClick)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

-- An item slot (ItemButtonTemplate's art: quick slot border, depress, square highlight)
-- with a gold name and two white lines on its right.
local function SlotButton(parent, name, iconPath, x, y, label, onClick, tipTitle, tipText)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(37, 37)
    b:SetPoint("TOPLEFT", x, y)
    b.icon = b:CreateTexture(nil, "BORDER")
    b.icon:SetAllPoints()
    b.icon:SetTexture(iconPath)
    b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    local normal = b:GetNormalTexture()
    normal:ClearAllPoints()
    normal:SetSize(64, 64)
    normal:SetPoint("CENTER", 0, -1)
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    b.label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("TOPLEFT", b, "TOPRIGHT", 8, 1)
    b.label:SetText(label)
    b.line1 = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.line1:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -2)
    b.line2 = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.line2:SetPoint("TOPLEFT", b.line1, "BOTTOMLEFT", 0, -2)

    b:SetScript("OnClick", onClick)
    AddTooltip(b, tipTitle, tipText)
    return b
end

-- ── Panels ───────────────────────────────────────────────────────────────────
local PANEL_W = 338   -- PortraitFrameTemplate's own width
local HEADER_H = 60   -- title bar + the portrait's band, as in ButtonFrameTemplate
local BAR_H = 26      -- ButtonFrameTemplate's button bar under the inset

local panels = {}

-- The portrait frame (rock background, round portrait, title bar, close button), the
-- button bar when asked and the marble inset. Levels as talent_frame.lua: frame N,
-- chrome N, inset N+1, content N+2 (at equal levels the client does not promise
-- which draws on top). The dialog border is the fallback if the templates are missing.
local function BuildChrome(panel)
    local template = panel.buttonBar and "ezCollectionsButtonFrameTemplate" or "ezCollectionsPortraitFrameTemplate"
    local ok, chrome = pcall(CreateFrame, "Frame", panel:GetName() .. "Chrome", panel, template)
    local base = panel:GetFrameLevel()
    if not ok or not chrome then
        panel:SetBackdrop(DIALOG_BACKDROP)
        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -16)
        title:SetText(panel.titleText)
        local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() panel:Hide() end)
        close:SetFrameLevel(base + 3)
        return
    end
    chrome:SetAllPoints(panel)
    chrome:SetFrameLevel(base)
    chrome.TitleText:SetText(panel.titleText)
    SetPortraitToTexture(chrome.portrait, panel.iconPath)
    -- the template's button hides its own parent (the chrome): close the panel instead
    chrome.CloseButton:SetScript("OnClick", function() panel:Hide() end)
    chrome.CloseButton:SetFrameLevel(base + 3)

    local inset = chrome.Inset
    if not inset then
        local ok2, made = pcall(CreateFrame, "Frame", panel:GetName() .. "Inset", chrome, "InsetFrameTemplate")
        if ok2 then inset = made end
    end
    if inset then
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -HEADER_H)
        inset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, panel.buttonBar and BAR_H or 4)
        inset:SetFrameLevel(base + 1)
    end
end

-- def: name, title, icon, height, buttonBar, subtitle, build(panel, content), refresh().
local function MakePanel(def)
    local panel = CreateFrame("Frame", def.name, UIParent)
    panel:SetSize(PANEL_W, def.height)
    -- where the client opens its own left-hand panels (UIParent's left area)
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -116)
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()
    panel.titleText, panel.iconPath, panel.buttonBar = def.title, def.icon, def.buttonBar

    panel:SetScript("OnShow", function(self)
        if not self.content then
            BuildChrome(self)
            local content = CreateFrame("Frame", nil, self)
            content:SetAllPoints(self)
            content:SetFrameLevel(self:GetFrameLevel() + 2)
            if def.subtitle then
                local sub = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                sub:SetPoint("TOPLEFT", 62, -30)
                sub:SetPoint("TOPRIGHT", def.subtitleRight or -14, -30)
                sub:SetJustifyH("LEFT")
                sub:SetText(def.subtitle)
                sub:SetTextColor(unpack(GREY))
            end
            self.content = content
            def.build(self, content)
        end
        PlaySound("igCharacterInfoOpen")
        Service.Request()
        def.refresh()
    end)
    panel:SetScript("OnHide", function()
        PlaySound("igCharacterInfoClose")
        if def.onHide then def.onHide() end
    end)

    panel.Refresh = function()
        if panel.content and panel:IsShown() then def.refresh() end
    end

    tinsert(UISpecialFrames, def.name)
    table.insert(panels, panel)
    return panel
end

local function ClosePanels(except)
    for _, p in ipairs(panels) do
        if p ~= except then p:Hide() end
    end
end

local function TogglePanel(panel)
    ClosePanels(panel)
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

-- ── Waystones panel ──────────────────────────────────────────────────────────
local MAX_WAYSTONES = 10
local WAY_ROW_H = 34

local function FindCheckpoint(id)
    if not (ProjectEbonhold.CheckpointService and ProjectEbonhold.CheckpointService.GetCheckpoints) then return nil end
    for _, cp in ipairs(ProjectEbonhold.CheckpointService.GetCheckpoints()) do
        if cp.id == id then return cp end
    end
end

local function CheckpointKindText(cp)
    if cp and cp.kind == "MEETINGSTONE" then return "Dungeon" end
    if cp and cp.kind == "MEETINGSTONE_RAID" then return "Raid" end
    return "Town"
end

local function CheckpointIcon(cp)
    if cp and cp.kind == "MEETINGSTONE" then return "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" end
    if cp and cp.kind == "MEETINGSTONE_RAID" then return "Interface\\Icons\\INV_Misc_Head_Dragon_01" end
    return "Interface\\Icons\\INV_Misc_Rune_01"
end

-- ── Waystone macros (a shortcut dragged onto an action bar) ──────────────────
-- Action bars only hold spells, items and macros, so a shortcut dragged out of the
-- panel becomes a macro "/waystone N" (N = shortcut 1-10). The macro follows its slot,
-- not one waystone: its name and icon are rewritten whenever the slot changes.
-- Character macros first (the shortcuts are this character's), account ones if full.
local MACRO_BODY = "/waystone %d"
local MAX_ACCOUNT, MAX_CHARACTER = 36, 18 -- MAX_ACCOUNT_MACROS / MAX_CHARACTER_MACROS (Blizzard_MacroUI)
local EMPTY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local macroIconIndex = {}
local macroApplied = {}   -- [slot] = "name|iconIndex" last written by SyncWaystoneMacros
local macroSyncPending = false

local function ChatMessage(text)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. text)
end

-- Macro icons are picked by index in the client's macro icon list; nil when absent.
local function FindMacroIcon(path)
    local key = string.lower(path)
    if macroIconIndex[key] == nil then
        macroIconIndex[key] = false
        for i = 1, GetNumMacroIcons() do
            if string.lower(GetMacroIconInfo(i) or "") == key then
                macroIconIndex[key] = i
                break
            end
        end
    end
    return macroIconIndex[key] or nil
end

local function MacroIcon(path)
    return FindMacroIcon(path) or FindMacroIcon(ICON_WAYSTONES) or 1
end

-- [slot 0-9] = macro index, for every "/waystone N" macro found.
local function WaystoneMacros()
    local found = {}
    for i = 1, MAX_ACCOUNT + MAX_CHARACTER do
        local body = GetMacroBody(i)
        local n = body and tonumber(string.match(body, "^/waystone (%d+)%s*$"))
        if n and n >= 1 and n <= MAX_WAYSTONES and not found[n - 1] then found[n - 1] = i end
    end
    return found
end

-- Name (16 characters at most) and icon of the slot's macro; nil while the slot's
-- waystone is not in the checkpoint list yet, so a slow list never renames a button.
local function WaystoneMacroLook(slot)
    local id = Service.GetState().waystones[slot]
    if not id then return "Shortcut " .. (slot + 1), EMPTY_ICON end
    local cp = FindCheckpoint(id)
    if not cp then return nil end
    return string.sub(cp.name or ("Waystone " .. (slot + 1)), 1, 16), CheckpointIcon(cp)
end

local function SyncWaystoneMacros()
    if not Service.GetState().received then return end
    if InCombatLockdown() then
        macroSyncPending = true
        return
    end
    macroSyncPending = false
    local changed = false
    local found = WaystoneMacros()
    for slot = 0, MAX_WAYSTONES - 1 do
        local index = found[slot]
        local name, icon = WaystoneMacroLook(slot)
        if index and name then
            local iconIndex = MacroIcon(icon)
            local look = name .. "|" .. iconIndex
            local curName, curTexture = GetMacroInfo(index)
            local iconOff = string.lower(curTexture or "") ~= string.lower(GetMacroIconInfo(iconIndex) or "")
            -- macroApplied: an icon path the client reports differently never rewrites it again
            if curName ~= name or (iconOff and macroApplied[slot] ~= look) then
                EditMacro(index, name, iconIndex, string.format(MACRO_BODY, slot + 1))
                macroApplied[slot] = look
                changed = true
                -- macros are sorted by name: a rename moves the indexes
                found = WaystoneMacros()
            end
        end
    end
    if changed and MacroFrame and MacroFrame:IsShown() and MacroFrame_Update then MacroFrame_Update() end
end

-- Puts the slot's macro on the cursor, making it first if needed.
local function PickupWaystoneMacro(slot)
    if InCombatLockdown() then
        ChatMessage("You cannot make an action bar button in combat.")
        return
    end
    if not WaystoneMacros()[slot] then
        local numAccount, numCharacter = GetNumMacros()
        local perCharacter
        if numCharacter < MAX_CHARACTER then
            perCharacter = 1
        elseif numAccount >= MAX_ACCOUNT then
            ChatMessage("Your macro list is full. Delete a macro to place this waystone on an action bar.")
            return
        end
        local name, icon = WaystoneMacroLook(slot)
        CreateMacro(name or ("Waystone " .. (slot + 1)), MacroIcon(icon or ICON_WAYSTONES), string.format(MACRO_BODY, slot + 1), perCharacter)
    end
    SyncWaystoneMacros()
    local index = WaystoneMacros()[slot]
    if index then PickupMacro(index) end
    if MacroFrame and MacroFrame:IsShown() and MacroFrame_Update then MacroFrame_Update() end
end

local macroEvents = CreateFrame("Frame")
macroEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
macroEvents:SetScript("OnEvent", function()
    if macroSyncPending then SyncWaystoneMacros() end
end)

-- What the macros run. Also usable by hand: /waystone 3
SLASH_EBONHOLDWAYSTONE1 = "/waystone"
SlashCmdList["EBONHOLDWAYSTONE"] = function(msg)
    local n = tonumber(string.match(msg or "", "(%d+)"))
    if not n or n < 1 or n > MAX_WAYSTONES then
        ChatMessage("Usage: /waystone 1-" .. MAX_WAYSTONES .. " (a shortcut of the Toolbelt's Waystones).")
        return
    end
    local state = Service.GetState()
    if not state.received then
        Service.Request()
        ChatMessage("The Toolbelt is still loading. Try again in a moment.")
        return
    end
    if not state.waystones[n - 1] then
        ChatMessage("Shortcut " .. n .. " is empty. Choose a waystone for it in the Toolbelt.")
        return
    end
    Service.UseWaystone(n - 1)
end

local Waystones, Picker
local PICKER_ROWS = 11
local PICKER_ROW_H = 28

local function RefreshWaystones()
    local state = Service.GetState()
    local used = 0
    for slot = 0, MAX_WAYSTONES - 1 do
        local row = Waystones.rows[slot]
        local id = state.waystones[slot]
        if id then
            used = used + 1
            local cp = FindCheckpoint(id)
            row.icon:SetTexture(CheckpointIcon(cp))
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.name:SetText(cp and cp.name or ("Checkpoint #" .. id))
            row.name:SetFontObject(GameFontNormal)
            row.sub:SetText(CheckpointKindText(cp))
        else
            row.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
            row.icon:SetTexCoord(0, 1, 0, 1)
            row.name:SetText("Empty slot")
            row.name:SetFontObject(GameFontDisable)
            row.sub:SetText("Click to choose a waystone.")
        end
        if Picker and Picker:IsShown() and Picker.slot == slot then row:LockHighlight() else row:UnlockHighlight() end
    end
    Waystones.count:SetText(used .. " / " .. MAX_WAYSTONES)
end

local function PickerCandidates()
    local list, seen = {}, {}
    local filter = string.lower(Picker.search:GetText() or "")
    if ProjectEbonhold.CheckpointService and ProjectEbonhold.CheckpointService.GetCheckpoints then
        for _, cp in ipairs(ProjectEbonhold.CheckpointService.GetCheckpoints()) do
            if cp.unlocked and not seen[cp.id] then
                if filter == "" or string.find(string.lower(cp.name or ""), filter, 1, true) then
                    seen[cp.id] = true
                    table.insert(list, cp)
                end
            end
        end
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

local function RefreshPicker()
    local list = PickerCandidates()
    FauxScrollFrame_Update(Picker.scroll, #list, PICKER_ROWS, PICKER_ROW_H)
    local offset = FauxScrollFrame_GetOffset(Picker.scroll)
    for i = 1, PICKER_ROWS do
        local row = Picker.rows[i]
        local cp = list[i + offset]
        if cp then
            row.id = cp.id
            row.icon:SetTexture(CheckpointIcon(cp))
            row.icon:Show()
            row.name:SetText(cp.name)
            row.name:SetFontObject(GameFontHighlight)
            row.sub:SetText(CheckpointKindText(cp))
            row:Enable()
            row:Show()
        else
            row.id = nil
            row:Hide()
        end
    end
    if #list == 0 then
        local row = Picker.rows[1]
        row.id = nil
        row.icon:Hide()
        row.name:SetText("No discovered waystone matches.")
        row.name:SetFontObject(GameFontDisable)
        row.sub:SetText("")
        row:Disable()
        row:Show()
    end
end

-- The waystone picker: every waystone this account discovered, with a search box. A
-- dialog box (dark parchment, 32 px border, banner header) beside the panel.
local function BuildPicker(panel)
    Picker = CreateFrame("Frame", "ProjectEbonholdWaystonePicker", panel)
    Picker:SetSize(280, 400)
    Picker:SetPoint("TOPLEFT", panel, "TOPRIGHT", 2, -24)
    Picker:SetClampedToScreen(true)
    Picker:EnableMouse(true)
    Picker:SetBackdrop(DIALOG_BACKDROP)
    Picker:Hide()

    local banner = Picker:CreateTexture(nil, "ARTWORK")
    banner:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    banner:SetSize(256, 64)
    banner:SetPoint("TOP", 0, 12)
    local title = Picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", banner, "TOP", 0, -14)
    title:SetText("Choose a Waystone")

    Picker.slotText = Picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Picker.slotText:SetPoint("TOP", 0, -30)
    Picker.slotText:SetTextColor(unpack(GREY))

    local close = CreateFrame("Button", nil, Picker, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() Picker:Hide() end)

    -- the addon's search bar (his rule: every addon search bar uses this one)
    local ok, box = pcall(CreateFrame, "EditBox", "ProjectEbonholdWaystonePickerSearch", Picker, "ezCollectionsSearchBoxTemplate")
    if not ok or not box then
        box = CreateFrame("EditBox", "ProjectEbonholdWaystonePickerSearch", Picker, "InputBoxTemplate")
    end
    box:SetSize(236, 20)
    box:SetPoint("TOPLEFT", 22, -48)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    -- HookScript: the template runs its own OnTextChanged (placeholder, clear button)
    box:HookScript("OnTextChanged", function() RefreshPicker() end)
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    Picker.search = box

    Picker.scroll = CreateFrame("ScrollFrame", "ProjectEbonholdWaystonePickerScroll", Picker, "FauxScrollFrameTemplate")
    Picker.scroll:SetPoint("TOPLEFT", 14, -74)
    Picker.scroll:SetPoint("BOTTOMRIGHT", -36, 14)
    Picker.scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, PICKER_ROW_H, RefreshPicker)
    end)

    Picker.rows = {}
    for i = 1, PICKER_ROWS do
        local row = CreateFrame("Button", nil, Picker)
        row:SetSize(228, PICKER_ROW_H)
        row:SetPoint("TOPLEFT", 16, -74 - (i - 1) * PICKER_ROW_H)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 2, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", 30, -2)
        row.name:SetPoint("TOPRIGHT", -2, -2)
        row.name:SetHeight(14)
        row.name:SetJustifyH("LEFT")
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", 30, -15)
        row.sub:SetTextColor(unpack(GREY))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self)
            if self.id and Picker.slot then
                PlaySound("igMainMenuOptionCheckBoxOn")
                Service.SetWaystone(Picker.slot, self.id)
                Picker:Hide()
            end
        end)
        Picker.rows[i] = row
    end

    Picker:SetScript("OnShow", function() RefreshWaystones() end)
    Picker:SetScript("OnHide", function() RefreshWaystones() end)
end

local function OpenPicker(slot)
    Picker.slot = slot
    Picker.slotText:SetText("For shortcut " .. (slot + 1))
    Picker.search:SetText("")
    if ProjectEbonhold.CheckpointService then ProjectEbonhold.CheckpointService.RequestCheckpoints() end
    RefreshPicker()
    Picker:Show()
    RefreshWaystones()
end

local function BuildWaystones(panel, c)
    panel.count = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.count:SetPoint("TOPRIGHT", -14, -30)

    panel.rows = {}
    for slot = 0, MAX_WAYSTONES - 1 do
        local row = CreateFrame("Button", "ProjectEbonholdWaystoneRow" .. slot, c)
        row:SetSize(312, WAY_ROW_H)
        row:SetPoint("TOPLEFT", 10, -65 - slot * WAY_ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:RegisterForDrag("LeftButton")
        row.slot = slot

        -- striped like the character sheet's stat lines
        if slot % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints()
            stripe:SetTexture(1, 1, 1, 0.05)
        end

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 4, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 40, -4)
        row.name:SetPoint("TOPRIGHT", -28, -4)
        row.name:SetHeight(14)
        row.name:SetJustifyH("LEFT")

        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", 40, -19)
        row.sub:SetTextColor(unpack(GREY))

        row.num = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.num:SetPoint("RIGHT", -8, 0)
        row.num:SetText(tostring(slot + 1))

        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        row:SetScript("OnClick", function(self, button)
            -- a drag released back over the row: not a click
            if GetCursorInfo() then return end
            local id = Service.GetState().waystones[self.slot]
            if button == "RightButton" then
                if id then
                    PlaySound("igMainMenuOptionCheckBoxOff")
                    Service.ClearWaystone(self.slot)
                end
                return
            end
            if id then
                Service.UseWaystone(self.slot)
                panel:Hide()
            else
                OpenPicker(self.slot)
            end
        end)
        -- onto an action bar: the slot's "/waystone N" macro (see Waystone macros above)
        row:SetScript("OnDragStart", function(self)
            if Service.GetState().waystones[self.slot] then PickupWaystoneMacro(self.slot) end
        end)
        row:SetScript("OnEnter", function(self)
            local id = Service.GetState().waystones[self.slot]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if id then
                local cp = FindCheckpoint(id)
                GameTooltip:SetText(cp and cp.name or ("Checkpoint #" .. id), 1, 1, 1)
                GameTooltip:AddLine(CheckpointKindText(cp), nil, nil, nil)
                GameTooltip:AddLine("Click to travel there.", 0.1, 1, 0.1)
                GameTooltip:AddLine("Right-click to free this slot.", 0.1, 1, 0.1)
                GameTooltip:AddLine("Drag onto an action bar to make a button.", 0.1, 1, 0.1)
                GameTooltip:AddLine("Not in combat, not in flight.", GREY[1], GREY[2], GREY[3])
            else
                GameTooltip:SetText("Shortcut " .. (self.slot + 1), 1, 1, 1)
                GameTooltip:AddLine("Click to choose one of the waystones you discovered.", 0.1, 1, 0.1, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.rows[slot] = row
    end

    BuildPicker(panel)
end

Waystones = MakePanel({
    name = "ProjectEbonholdWaystonesPanel",
    title = "Waystones",
    icon = ICON_WAYSTONES,
    height = 414,
    subtitle = "Click to travel. Right-click to free a slot.",
    subtitleRight = -60,
    build = BuildWaystones,
    refresh = RefreshWaystones,
    onHide = function() if Picker then Picker:Hide() end end,
})

-- ── Vendor panel ─────────────────────────────────────────────────────────────
local Peddler

local weapon, armor, _, consumable, glyph, tradeGoods, _, _, recipe, gem, misc = GetAuctionItemClasses()

local SELL_QUALITIES = {
    { key = "sellQualityPoor",     label = QUALITY_COLOR[0] .. "Poor|r",     tip = "All poor quality (junk) items, whatever their type." },
    { key = "sellQualityCommon",   label = QUALITY_COLOR[1] .. "Common|r",   tip = "Common items whose type is also ticked." },
    { key = "sellQualityUncommon", label = QUALITY_COLOR[2] .. "Uncommon|r", tip = "Uncommon items whose type is also ticked." },
    { key = "sellQualityRare",     label = QUALITY_COLOR[3] .. "Rare|r",     tip = "Rare items whose type is also ticked." },
}

local SELL_TYPES = {
    { key = "sellTypeWeapon",     label = weapon or "Weapon" },
    { key = "sellTypeArmor",      label = armor or "Armor" },
    { key = "sellTypeConsumable", label = consumable or "Consumable" },
    { key = "sellTypeTradeGoods", label = tradeGoods or "Trade Goods" },
    { key = "sellTypeRecipe",     label = recipe or "Recipe" },
    { key = "sellTypeGem",        label = gem or "Gem" },
    { key = "sellTypeGlyph",      label = glyph or "Glyph" },
    { key = "sellTypeMisc",       label = misc or "Miscellaneous" },
}

local function BuildPeddler(panel, c)
    local function Sell() if Service.Sell() then PlaySound("LOOTWINDOWCOINSOUND") end end
    local function Repair() PlaySound("ITEM_REPAIR"); Service.Repair() end

    panel.sell = SlotButton(c, "ProjectEbonholdPeddlerSell", "Interface\\Icons\\INV_Misc_Coin_01", 16, -70, "Sell", Sell,
        "Sell", "Sells everything matching the rules below. Nothing to open, no vendor needed. Sold items sit in any vendor's buyback tab.")
    panel.repair = SlotButton(c, "ProjectEbonholdPeddlerRepair", "Interface\\Icons\\Trade_BlackSmithing", 174, -70, "Repair", Repair,
        "Repair", "Repairs everything you carry at full price.")

    SectionHeader(c, "Automatic", -120)
    panel.autoSell = MakeCheck(c, "ProjectEbonholdPeddlerAutoSell", "Sell when combat ends", 12, -142,
        function(checked) SetSetting("vendorAutoSell", checked) end,
        "Automatic sale", "Each time you leave combat, everything matching the rules below is sold.")
    panel.autoRepair = MakeCheck(c, "ProjectEbonholdPeddlerAutoRepair", "Repair when combat ends", 12, -164,
        function(checked) SetSetting("vendorAutoRepair", checked) end,
        "Automatic repair", "Each time you leave combat, your gear is repaired if it took damage.")

    SectionHeader(c, "What Gets Sold", -196)
    panel.qualityChecks = {}
    for i, q in ipairs(SELL_QUALITIES) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        panel.qualityChecks[q.key] = MakeCheck(c, "ProjectEbonholdPeddlerQuality" .. i, q.label, 12 + col * 158, -218 - row * 22,
            function(checked) SetSetting(q.key, checked); panel.Refresh() end, "Sell " .. q.label, q.tip)
    end
    panel.typeChecks = {}
    for i, t in ipairs(SELL_TYPES) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        panel.typeChecks[t.key] = MakeCheck(c, "ProjectEbonholdPeddlerType" .. i, t.label, 12 + col * 158, -268 - row * 22,
            function(checked) SetSetting(t.key, checked); panel.Refresh() end,
            "Sell " .. t.label, "Items of this type are sold when their quality is ticked above.")
    end

    Note(c, "Alt-click a bag item to always sell it, or never. Epic and better is never sold.", -364)

    -- the button bar: your money on the left, the two actions against the right edge
    local ok, money = pcall(CreateFrame, "Frame", "ProjectEbonholdPeddlerMoney", c, "SmallMoneyFrameTemplate")
    if ok and money then
        money:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 14, 9)
    end
    panel.repairButton = BarButton(c, "ProjectEbonholdPeddlerRepairButton", "Repair", 90, Repair)
    panel.repairButton:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -6, 4)
    panel.sellButton = BarButton(c, "ProjectEbonholdPeddlerSellButton", "Sell", 90, Sell)
    panel.sellButton:SetPoint("RIGHT", panel.repairButton, "LEFT", 0, 0)
end

local function RefreshPeddler()
    local state = Service.GetState()
    local count, value = Service.GetSellPreview()
    Peddler.sell.line1:SetText(string.format("%d item%s", count, count == 1 and "" or "s"))
    Peddler.sell.line2:SetText(Money(value))
    local pct = Service.GetDurabilityPct()
    Peddler.repair.line1:SetText("Durability " .. (pct and (pct .. "%") or "n/a"))
    Peddler.repair.line2:SetText(Money(state.repairCost))

    if count > 0 then Peddler.sellButton:Enable() else Peddler.sellButton:Disable() end
    if (state.repairCost or 0) > 0 or (pct and pct < 100) then Peddler.repairButton:Enable() else Peddler.repairButton:Disable() end

    Peddler.autoSell:SetChecked(GetSetting("vendorAutoSell") and 1 or nil)
    Peddler.autoRepair:SetChecked(GetSetting("vendorAutoRepair") and 1 or nil)
    for key, cb in pairs(Peddler.qualityChecks) do cb:SetChecked(GetSetting(key) and 1 or nil) end
    for key, cb in pairs(Peddler.typeChecks) do cb:SetChecked(GetSetting(key) and 1 or nil) end
end

Peddler = MakePanel({
    name = "ProjectEbonholdPeddlerPanel",
    title = "Vendor",
    icon = ICON_VENDOR,
    height = 424,
    buttonBar = true,
    subtitle = "Sell your loot and repair your gear from anywhere.",
    build = BuildPeddler,
    refresh = RefreshPeddler,
})
-- BAG_UPDATE comes once per bag, in bursts: one refresh (one bag scan) on the next frame.
local peddlerSoon = CreateFrame("Frame")
peddlerSoon:Hide()
peddlerSoon:SetScript("OnUpdate", function(self)
    self:Hide()
    Peddler.Refresh()
end)
Peddler:RegisterEvent("BAG_UPDATE")
Peddler:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
Peddler:SetScript("OnEvent", function(self)
    if self:IsShown() then peddlerSoon:Show() end
end)

-- ── Scavenger's Eye panel ────────────────────────────────────────────────────
local Eye

-- ITEM_CLASS ids (3.3.5): Consumable 0, Container 1, Weapon 2, Gem 3, Armor 4, Reagent 5,
-- Projectile 6, Trade Goods 7, Recipe 9, Quiver 11, Miscellaneous 15, Glyph 16.
local LOOT_TYPES = {
    { class = 2,  label = weapon or "Weapon" },
    { class = 4,  label = armor or "Armor" },
    { class = 0,  label = consumable or "Consumable" },
    { class = 7,  label = tradeGoods or "Trade Goods" },
    { class = 3,  label = gem or "Gem" },
    { class = 9,  label = recipe or "Recipe" },
    { class = 16, label = glyph or "Glyph" },
    { class = 1,  label = "Container" },
    { class = 6,  label = "Projectile" },
    { class = 11, label = "Quiver" },
    { class = 5,  label = "Reagent" },
    { class = 15, label = misc or "Miscellaneous" },
}

local function BuildEye(panel, c)
    panel.master = MakeCheck(c, "ProjectEbonholdEyeMasterCheck", "Enable remote looting", 12, -68,
        function(checked) Service.SetLoot({ on = checked }) end,
        "Remote looting", "The loot of everything that dies near you is picked up for you, filtered by the rules below.")
    panel.master.text:SetFontObject(GameFontNormal)

    SectionHeader(c, "What Gets Picked Up", -98)
    local minQLabel = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    minQLabel:SetPoint("TOPLEFT", 16, -128)
    minQLabel:SetText("Minimum quality")
    panel.qualityDropDown = MakeDropDown(c, "ProjectEbonholdEyeQualityDropDown", 136, -118, 120,
        "Minimum quality", "Items below this quality stay on the corpse. Quest items are always picked up.")
    UIDropDownMenu_Initialize(panel.qualityDropDown, function(self)
        QualityItems(self, 0, 4, Service.GetState().loot.minQuality, function(q) Service.SetLoot({ minQuality = q }) end)
    end)

    panel.typeChecks = {}
    for i, t in ipairs(LOOT_TYPES) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        panel.typeChecks[t.class] = MakeCheck(c, "ProjectEbonholdEyeType" .. i, t.label, 12 + col * 158, -152 - row * 22,
            function() Service.SetLoot({ classMask = ToggleBit(Service.GetState().loot.classMask, t.class) }) end,
            "Pick up " .. t.label, "Untick to leave this type on the corpse for manual looting.")
    end
    Note(c, "Quest items and gold are always picked up.", -288)

    SectionHeader(c, "Destroy on Pickup", -312)
    panel.destroy = MakeCheck(c, "ProjectEbonholdEyeDestroy", "Destroy junk instead of keeping it", 12, -334,
        function(checked) Service.SetLoot({ destroy = checked }) end,
        "Destroy on pickup", "Matching drops are removed from the corpse without ever entering your bags. Never quest items, bind-on-pickup items or items that cannot be destroyed.")
    panel.destroyLabel = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.destroyLabel:SetPoint("TOPLEFT", 16, -368)
    panel.destroyLabel:SetText("Up to quality")
    panel.destroyDropDown = MakeDropDown(c, "ProjectEbonholdEyeDestroyDropDown", 136, -358, 120,
        "Destroy up to", "Drops of this quality or lower are destroyed.")
    UIDropDownMenu_Initialize(panel.destroyDropDown, function(self)
        QualityItems(self, 0, 1, Service.GetState().loot.destroyMaxQuality, function(q) Service.SetLoot({ destroyMaxQuality = q }) end)
    end)

    Note(c, "In a group, only loot that is yours is picked up. Master loot is left to the loot window.", -398)
end

local function RefreshEye()
    local l = Service.GetState().loot
    Eye.master:SetChecked(l.on and 1 or nil)
    SetDropDownQuality(Eye.qualityDropDown, l.minQuality)
    for class, cb in pairs(Eye.typeChecks) do cb:SetChecked(HasBit(l.classMask, class) and 1 or nil) end
    Eye.destroy:SetChecked(l.destroy and 1 or nil)
    SetDropDownQuality(Eye.destroyDropDown, l.destroyMaxQuality)
    if l.destroy then
        UIDropDownMenu_EnableDropDown(Eye.destroyDropDown)
        Eye.destroyLabel:SetFontObject(GameFontHighlightSmall)
    else
        UIDropDownMenu_DisableDropDown(Eye.destroyDropDown)
        Eye.destroyLabel:SetFontObject(GameFontDisableSmall)
    end
end

Eye = MakePanel({
    name = "ProjectEbonholdScavengersEyePanel",
    title = "Scavenger's Eye",
    icon = ICON_EYE,
    height = 440,
    subtitle = "The loot of everything that dies near you, picked up for you.",
    build = BuildEye,
    refresh = RefreshEye,
})

-- ── The menu (a dropdown list opening upward from the micro button) ──────────
local MENU_W = 210
local MENU_BORDER = 15   -- UIDROPDOWNMENU_BORDER_HEIGHT
local ROW_H = 18

local Menu = CreateFrame("Frame", "ProjectEbonholdToolbeltMenu", UIParent)
Menu:SetSize(MENU_W, 10)
Menu:SetFrameStrata("DIALOG")
Menu:EnableMouse(true)
Menu:SetClampedToScreen(true)
Menu:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 9 },
})
Menu:Hide()
tinsert(UISpecialFrames, "ProjectEbonholdToolbeltMenu")

local menuRows = {}
local y = -MENU_BORDER

local function MenuHeader(text)
    local fs = Menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", MENU_BORDER + 2, y - 3)
    fs:SetText(text)
    y = y - ROW_H
end

local function MenuSpacer()
    y = y - 6
end

local function MenuRow(key, label, iconPath, onClick, tipText)
    local row = CreateFrame("Button", "ProjectEbonholdToolbeltMenu" .. key, Menu)
    row:SetSize(MENU_W - 2 * MENU_BORDER, ROW_H)
    row:SetPoint("TOPLEFT", MENU_BORDER, y)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexture(iconPath)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetText(label)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -2, 0)
    row.right:SetTextColor(unpack(GREY))
    row.dot = row:CreateTexture(nil, "OVERLAY")
    row.dot:SetSize(8, 8)
    row.dot:SetPoint("RIGHT", -4, 0)
    row.dot:SetTexture("Interface\\COMMON\\Indicator-Green")
    row.dot:Hide()
    row.lock = row:CreateTexture(nil, "OVERLAY")
    row.lock:SetSize(14, 14)
    row.lock:SetPoint("RIGHT", -1, 0)
    row.lock:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
    row.lock:SetTexCoord(0, 0.72, 0, 0.72)
    row.lock:Hide()
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        if tipText then GameTooltip:AddLine(tipText, nil, nil, nil, true) end
        if self.locked then GameTooltip:AddLine("Not unlocked on this character. Sold in the shop.", 1, 0.125, 0.125, true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        PlaySound("UChatScrollButton")
        if self.locked then
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. label .. " is not unlocked on this character. It is sold in the shop.")
            return
        end
        Menu:Hide()
        onClick()
    end)
    menuRows[key] = row
    y = y - ROW_H
    return row
end

MenuHeader("Travel")
MenuRow("Waystones", "Waystones", ICON_WAYSTONES, function()
    TogglePanel(Waystones)
end, "Ten shortcuts to waystones you already discovered. Click one to travel there.")
MenuSpacer()
MenuHeader("Conveniences")
MenuRow("Vault", "Bank", "Interface\\MINIMAP\\TRACKING\\Banker", function()
    ClosePanels()
    Service.OpenBank()
end, "Opens your personal bank right here, wherever you are.")
MenuRow("GuildBank", "Guild Bank", "Interface\\Icons\\INV_Misc_Bag_EnchantedMageweave", function()
    ClosePanels()
    Service.OpenGuildBank()
end, "Opens your guild's bank right here, wherever you are.")
MenuRow("Mailbox", "Mailbox", "Interface\\Icons\\INV_Letter_15", function()
    ClosePanels()
    Service.OpenMailbox()
end, "Opens your mailbox right here: read, take and send mail.")
MenuRow("Auction", "Auction House", "Interface\\MINIMAP\\TRACKING\\Auctioneer", function()
    ClosePanels()
    Service.OpenAuctionHouse()
end, "Opens the auction house right here: browse, bid and sell.")
MenuRow("Callboard", "Hero's Call Board", "Interface\\Icons\\INV_Misc_Note_02", function()
    ClosePanels()
    -- callboard_ui.lua loads after this file: resolve it at click time.
    local board = ProjectEbonhold.CallboardUI
    if board then board.Show() end
end, "Opens the Hero's Call Board right here: take contracts and claim their rewards.")
MenuRow("AffixAnvil", "Portable Affix-Anvil", "Interface\\Icons\\Trade_Engraving", function()
    ClosePanels()
    -- extraction.lua loads after this file: resolve it at click time.
    if ExtractionUI and ExtractionUI.Toggle then ExtractionUI.Toggle() end
end, "Opens the Enchanted Anvil right here: extract affixes, engrave them and upgrade to Torment.")
MenuRow("Forge", "Portable Forge", "Interface\\Icons\\Trade_BlackSmithing", function()
    ClosePanels()
    Service.PlaceForge()
end, "Sets up a forge and an anvil beside you for five minutes. Opening Blacksmithing, Mining, Engineering or Jewelcrafting does it by itself.")
MenuRow("Peddler", "Vendor", ICON_VENDOR, function()
    TogglePanel(Peddler)
end, "Sell your loot and repair your gear from anywhere, by hand or automatically when combat ends.")
MenuRow("Eye", "Scavenger's Eye", ICON_EYE, function()
    TogglePanel(Eye)
end, "The loot of everything that dies near you is picked up for you. Filter what you keep.")

Menu:SetHeight(-y + MENU_BORDER - 3)

local function SetRowLocked(row, locked)
    row.locked = locked
    if locked then
        row.label:SetFontObject(GameFontDisableSmall)
        row.icon:SetDesaturated(true)
        row.icon:SetAlpha(0.6)
        row.lock:Show()
        row.dot:Hide()
    else
        row.label:SetFontObject(GameFontHighlightSmall)
        row.icon:SetDesaturated(false)
        row.icon:SetAlpha(1)
        row.lock:Hide()
    end
end

local function RefreshMenu()
    local state = Service.GetState()
    local used = 0
    for _ in pairs(state.waystones) do used = used + 1 end
    menuRows.Waystones.right:SetText(used .. " / " .. MAX_WAYSTONES)

    SetRowLocked(menuRows.Vault, not state.owned.bank)
    SetRowLocked(menuRows.Peddler, not state.owned.vendor)
    SetRowLocked(menuRows.Eye, not state.owned.loot)
    SetRowLocked(menuRows.GuildBank, not state.owned.guildBank)
    SetRowLocked(menuRows.Mailbox, not state.owned.mail)
    SetRowLocked(menuRows.Auction, not state.owned.auction)
    SetRowLocked(menuRows.Callboard, not state.owned.callboard)
    SetRowLocked(menuRows.AffixAnvil, not state.owned.anvil)
    SetRowLocked(menuRows.Forge, not state.owned.forge)

    local autoOn = state.owned.vendor and (GetSetting("vendorAutoSell") or GetSetting("vendorAutoRepair"))
    if autoOn then menuRows.Peddler.dot:Show() else menuRows.Peddler.dot:Hide() end
    if state.owned.loot and state.loot.on then menuRows.Eye.dot:Show() else menuRows.Eye.dot:Hide() end
end

Menu:SetScript("OnShow", function(self)
    self.wasOver, self.idle = false, 0
    PlaySound("igMainMenuOptionCheckBoxOn")
    Service.Request()
    RefreshMenu()
end)

-- As a dropdown list: once the mouse has been over it and left, it closes itself after
-- UIDROPDOWNMENU_SHOW_TIME; a click in the world closes it at once.
Menu:SetScript("OnUpdate", function(self, elapsed)
    if MouseIsOver(self) then
        self.wasOver, self.idle = true, 0
        return
    end
    if not self.wasOver then return end
    self.idle = self.idle + elapsed
    if self.idle >= (UIDROPDOWNMENU_SHOW_TIME or 2) then self:Hide() end
end)
WorldFrame:HookScript("OnMouseDown", function() Menu:Hide() end)

-- ── The micro button ─────────────────────────────────────────────────────────
local microButton = CreateFrame("Button", "ToolbeltMicroButton", MainMenuBarArtFrame, "MainMenuBarMicroButton")
LoadMicroButtonTextures(microButton, "Help")
microButton:SetNormalTexture([[Interface\AddOns\ProjectEbonhold\assets\ui-microbuttonstreamdl-up]])
microButton:SetPushedTexture([[Interface\AddOns\ProjectEbonhold\assets\ui-microbuttonstreamdl-down]])
microButton:SetHighlightTexture([[Interface\Buttons\UI-MicroButton-Hilight]])

local microIcon = microButton:CreateTexture(nil, "OVERLAY")
microIcon:SetTexture("Interface\\Icons\\INV_Misc_EngGizmos_30")
microIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
microIcon:SetSize(18, 18)
microIcon:SetPoint("BOTTOM", microButton, "BOTTOM", 0, 9)

microButton.tooltipText = "Toolbelt"
microButton.newbieText = "Waystones, Bank, Guild Bank, Mailbox, Auction House, Call Board, Affix-Anvil, Forge, Vendor and Scavenger's Eye."

Menu:SetPoint("BOTTOM", microButton, "TOP", 0, 4)

microButton:SetScript("OnClick", function(self, button)
    if button ~= "LeftButton" then return end
    if Menu:IsShown() then Menu:Hide() else Menu:Show() end
end)
microButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltipText, 1, 1, 1)
    GameTooltip:AddLine(self.newbieText, nil, nil, nil, true)
    GameTooltip:Show()
end)
microButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Any state push refreshes whatever is open, and the action bar macros of the shortcuts.
Service.OnChange(function()
    SyncWaystoneMacros()
    if Menu:IsShown() then RefreshMenu() end
    Waystones.Refresh()
    Peddler.Refresh()
    Eye.Refresh()
end)

-- The checkpoint list is answered asynchronously (SEND_CHECKPOINTS_DATA has one
-- handler, owned by checkpoint_service.lua), so while the Waystones panel is
-- open it re-reads names and the picker list once a second.
Waystones:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 1 then return end
    self.t = 0
    Waystones.Refresh()
    SyncWaystoneMacros()
    if Picker and Picker:IsShown() then RefreshPicker() end
end)

SLASH_EBONHOLDTOOLBELT1 = "/toolbelt"
SlashCmdList["EBONHOLDTOOLBELT"] = function()
    if Menu:IsShown() then Menu:Hide() else Menu:Show() end
end
