------------------------------------------------------------
-- SPELL UNLEARN UI
--
-- Hooks into SpellBookFrame spell buttons so that
-- right-clicking a spell in a target tab shows a
-- context menu with an "Unlearn" option.
------------------------------------------------------------

local SPELLS_PER_PAGE  = 12
local BOOKTYPE_SPELL   = "spell"

------------------------------------------------------------
-- CONFIG – Change UNLEARN_TAB_NAME to restrict unlearning
-- to a specific SpellBook tab (e.g. "General").
-- Set to nil to allow from any tab.
------------------------------------------------------------
local UNLEARN_TAB_NAME = "Echoes"
------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function GetSpellSlot(buttonID)
    if not SpellBookFrame or not SpellBookFrame.selectedSkillLine then
        return nil
    end
    local _, _, offset, numSpells = GetSpellTabInfo(SpellBookFrame.selectedSkillLine)
    local pageNum = SPELLBOOK_PAGENUMBERS
        and SPELLBOOK_PAGENUMBERS[SpellBookFrame.selectedSkillLine] or 1
    local slot = buttonID + offset + (SPELLS_PER_PAGE * (pageNum - 1))
    if slot > offset + numSpells then return nil end
    return slot
end

local function GetSpellIDFromSlot(slot)
    local link = GetSpellLink(slot, BOOKTYPE_SPELL)
    if not link then return nil end
    return tonumber(link:match("|Hspell:(%d+)|h"))
end

local function IsUnlearnableTab()
    if not UNLEARN_TAB_NAME then return true end
    if not SpellBookFrame or not SpellBookFrame.selectedSkillLine then
        return false
    end
    local tabName = GetSpellTabInfo(SpellBookFrame.selectedSkillLine)
    return tabName == UNLEARN_TAB_NAME
end

------------------------------------------------------------
-- Confirmation popup
------------------------------------------------------------
StaticPopupDialogs["EBONHOLD_CONFIRM_UNLEARN_SPELL"] = {
    text         = "Are you sure you want to unlearn |cffFFD100%s|r?\n\n|cffFF4444This is permanent.|r You will lose this Echo and will need to loot it again to relearn it.",
    button1      = "Yes",
    button2      = "No",
    OnAccept     = function()
        local spellID = ProjectEbonhold._pendingUnlearnSpellID
        if spellID then
            ProjectEbonhold.SpellUnlearnService.RequestUnlearn(spellID)
            ProjectEbonhold._pendingUnlearnSpellID = nil
        end
    end,
    OnCancel     = function()
        ProjectEbonhold._pendingUnlearnSpellID = nil
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------
-- Right-click context menu
------------------------------------------------------------
local unlearnDropdown = CreateFrame("Frame", "EbonholdUnlearnDropdown", UIParent, "UIDropDownMenuTemplate")

local function ShowUnlearnMenu(spellButton)
    local slot = GetSpellSlot(spellButton:GetID())
    if not slot then return end

    local spellName, spellRank = GetSpellName(slot, BOOKTYPE_SPELL)
    if not spellName or spellName == "" then return end

    local spellID = GetSpellIDFromSlot(slot)
    if not spellID then return end

    local displayName = spellName
    if spellRank and spellRank ~= "" then
        displayName = spellName .. " (" .. spellRank .. ")"
    end

    UIDropDownMenu_Initialize(unlearnDropdown, function(self, level)
        -- Header
        local header = UIDropDownMenu_CreateInfo()
        header.text         = displayName
        header.isTitle      = true
        header.notCheckable = true
        UIDropDownMenu_AddButton(header, level)

        -- Unlearn option
        local unlearn = UIDropDownMenu_CreateInfo()
        unlearn.text         = "|cffFF4444Unlearn|r"
        unlearn.notCheckable = true
        unlearn.func = function()
            ProjectEbonhold._pendingUnlearnSpellID = spellID
            StaticPopup_Show("EBONHOLD_CONFIRM_UNLEARN_SPELL", displayName)
        end
        UIDropDownMenu_AddButton(unlearn, level)

        -- Cancel
        local cancel = UIDropDownMenu_CreateInfo()
        cancel.text         = "Cancel"
        cancel.notCheckable = true
        cancel.func         = function() CloseDropDownMenus() end
        UIDropDownMenu_AddButton(cancel, level)
    end, "MENU")

    ToggleDropDownMenu(1, nil, unlearnDropdown, "cursor", 3, -3)
end

------------------------------------------------------------
-- Hook SpellBook buttons (taint-safe)
--
-- We do NOT touch the secure SpellButtons themselves.
-- Instead, transparent overlay frames sit on top of each
-- button and capture only right-clicks. Left-clicks pass
-- through to the original secure button underneath.
------------------------------------------------------------
local hooked   = false
local overlays = {}

local function CreateOverlay(spellButton, index)
    local overlay = CreateFrame("Button", "EbonholdSpellOverlay" .. index, spellButton)
    overlay:SetAllPoints(spellButton)
    overlay:SetFrameStrata(spellButton:GetFrameStrata())
    overlay:SetFrameLevel(spellButton:GetFrameLevel() + 5)
    overlay:RegisterForClicks("RightButtonUp")
    overlay:EnableMouse(false)          -- starts disabled

    overlay.spellButton = spellButton

    overlay:SetScript("OnClick", function(self, button)
        if button == "RightButton" and IsUnlearnableTab() then
            ShowUnlearnMenu(self.spellButton)
        end
    end)

    -- Forward tooltip behaviour to the underlying spell button
    overlay:SetScript("OnEnter", function(self)
        local btn = self.spellButton
        if btn and btn:GetScript("OnEnter") then
            btn:GetScript("OnEnter")(btn)
        end
        -- Append unlearn hint
        if IsUnlearnableTab() then
            local slot = GetSpellSlot(btn:GetID())
            if slot then
                local spellName = GetSpellName(slot, BOOKTYPE_SPELL)
                if spellName and spellName ~= "" then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff888888Right-click to unlearn|r", 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end
            end
        end
    end)

    overlay:SetScript("OnLeave", function(self)
        local btn = self.spellButton
        if btn and btn:GetScript("OnLeave") then
            btn:GetScript("OnLeave")(btn)
        end
    end)

    return overlay
end

------------------------------------------------------------
-- Banner message shown at top of SpellBook in Echoes tab
------------------------------------------------------------
local bannerFrame

local function CreateBanner()
    if bannerFrame then return end

    bannerFrame = CreateFrame("Frame", "EbonholdUnlearnBanner", SpellBookFrame)
    bannerFrame:SetSize(100, 16)
    bannerFrame:SetPoint("TOPRIGHT", SpellBookFrame, "TOPRIGHT", -50, -55)
    bannerFrame:SetFrameLevel(SpellBookFrame:GetFrameLevel() + 10)

    local text = bannerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("RIGHT")
    text:SetFont(text:GetFont(), 10)
    text:SetText("|cffFFD100Right-click an Echo to unlearn it|r")
    text:SetJustifyH("RIGHT")
    bannerFrame.text = text

    bannerFrame:Hide()
end

local function UpdateBanner()
    if not bannerFrame then return end
    if IsUnlearnableTab() and SpellBookFrame:IsShown() then
        bannerFrame:Show()
        if ShowAllSpellRanksCheckBox then
            ShowAllSpellRanksCheckBox:Hide()
        end
    else
        bannerFrame:Hide()
        if ShowAllSpellRanksCheckBox then
            ShowAllSpellRanksCheckBox:Show()
        end
    end
end

local function UpdateOverlays()
    local enabled = IsUnlearnableTab()
    for _, ov in ipairs(overlays) do
        ov:EnableMouse(enabled)
    end
    UpdateBanner()
end

local function HookSpellButtons()
    if hooked then return end
    hooked = true

    for i = 1, SPELLS_PER_PAGE do
        local btn = _G["SpellButton" .. i]
        if btn then
            overlays[i] = CreateOverlay(btn, i)
        end
    end

    -- Refresh overlay state whenever the tab changes or spells update
    for i = 1, MAX_SKILLLINE_TABS or 8 do
        local tab = _G["SpellBookSkillLineTab" .. i]
        if tab then
            tab:HookScript("OnClick", UpdateOverlays)
        end
    end

    -- Also refresh when the frame shows or spells change
    if SpellBookFrame then
        SpellBookFrame:HookScript("OnShow", UpdateOverlays)
    end

    local evtFrame = CreateFrame("Frame")
    evtFrame:RegisterEvent("SPELLS_CHANGED")
    evtFrame:SetScript("OnEvent", function()
        if SpellBookFrame and SpellBookFrame:IsShown() then
            UpdateOverlays()
        end
    end)
end

------------------------------------------------------------
-- Init – hook as soon as SpellBookFrame exists
------------------------------------------------------------
local function Init()
    CreateBanner()
    HookSpellButtons()
end

if SpellBookFrame then
    Init()
else
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_SpellBookUI" or _G["SpellBookFrame"] then
            Init()
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end
