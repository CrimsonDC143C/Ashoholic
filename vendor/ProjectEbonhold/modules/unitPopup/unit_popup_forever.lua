-- Module: WoW Forever look for the right-click menu of a unit (player, party, raid, chat name, friend)
-- (owner, 2026-11-13: "refaire la popup de clique droit sur les joueurs comme le design de wow Forever").
--
-- Only the paint changes; the stock UIDropDownMenu still builds, sizes and runs the menu, so every
-- protected entry (Set Focus, Target...) keeps working. The art is DragonUI's Forever kit
-- (DragonUI\utils\forever_ui_controls.lua, the same 9-slice as its "forever" menus):
--   * dark rounded panel instead of the tooltip border,
--   * soft mouse-over bar, yellow check mark, retail "next" arrow,
--   * no Cancel row: a press anywhere else closes the menu, as on retail.
-- Any other dropdown (options, minimap tracking, addons) is put back to the stock paint on its next open.
-- Cost: work only when a menu opens, never per frame.

local SKIN = "bg"
local HIGHLIGHT_ALPHA = 0.15

local STOCK_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local STOCK_ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local STOCK_CHECK = "Interface\\Buttons\\UI-CheckBox-Check"

local function ForeverUI()
    return DragonUI and DragonUI.ForeverUI
end

local function IsUnitMenu(owner)
    if type(owner) == "string" then owner = _G[owner] end
    return type(owner) == "table" and owner.which ~= nil
        and type(UnitPopupMenus) == "table" and UnitPopupMenus[owner.which] ~= nil
end

-- Stock size of each check texture, taken before the first change.
local checkSize = {}

local function PaintButton(button, name, forever)
    local ui = ForeverUI()
    local highlight = _G[name .. "Highlight"]
    if highlight then
        if forever then
            -- A plain white soft-edged bar in the atlas: drawn faint, as retail's row highlight.
            ui.SetAtlas(highlight, "common-dropdown-customize-mouseover", false)
            highlight:SetBlendMode("BLEND")
            highlight:SetVertexColor(1, 1, 1, HIGHLIGHT_ALPHA)
        else
            highlight:SetTexture(STOCK_HIGHLIGHT)
            highlight:SetTexCoord(0, 1, 0, 1)
            highlight:SetBlendMode("ADD")
            highlight:SetVertexColor(1, 1, 1, 1)
        end
    end

    local arrow = _G[name .. "ExpandArrow"]
    local arrowTexture = arrow and arrow:GetNormalTexture()
    if arrowTexture then
        if forever then
            ui.SetAtlas(arrowTexture, "common-dropdown-icon-next", false)
        else
            arrowTexture:SetTexture(STOCK_ARROW)
            arrowTexture:SetTexCoord(0, 1, 0, 1)
        end
    end

    -- The add button hook of CompactRaidFrame sets the check texture on every row (radio or tick),
    -- so only the tick is replaced, and the size is the only thing to put back.
    local check = _G[name .. "Check"]
    if check then
        if not checkSize[check] then
            checkSize[check] = { check:GetWidth(), check:GetHeight() }
        end
        if forever and check:GetTexture() and check:GetTexture():lower() == STOCK_CHECK:lower() then
            ui.SetAtlas(check, "common-dropdown-icon-checkmark-yellow", true)
        else
            check:SetSize(checkSize[check][1], checkSize[check][2])
        end
    end
end

local function PaintList(level, forever)
    local list = _G["DropDownList" .. level]
    if not list then return end
    local ui = ForeverUI()
    if not ui or not ui.SkinMenuBackground or not ui.SetAtlas then return end -- DragonUI off: stock look
    if not forever and not list._ebhForever then return end

    local name = list:GetName()
    local backdrop, menuBackdrop = _G[name .. "Backdrop"], _G[name .. "MenuBackdrop"]
    if forever then
        ui.SkinMenuBackground(list, SKIN)
        if backdrop then backdrop:Hide() end
        if menuBackdrop then menuBackdrop:Hide() end
    elseif ui.HideMenuBackground then
        -- ToggleDropDownMenu has already shown the backdrop this menu asks for.
        ui.HideMenuBackground(list)
    end
    list._ebhForever = forever or nil

    for index = 1, (list.numButtons or 0) do
        local buttonName = name .. "Button" .. index
        if _G[buttonName] then
            PaintButton(_G[buttonName], buttonName, forever)
        end
    end
end

hooksecurefunc("ToggleDropDownMenu", function(level, value, dropDownFrame)
    level = level or 1
    local list = _G["DropDownList" .. level]
    if not list or not list:IsShown() then return end
    PaintList(level, IsUnitMenu(dropDownFrame or UIDROPDOWNMENU_OPEN_MENU))
end)

-- No Cancel row in a unit menu (retail has none).
if type(UnitPopupMenus) == "table" then
    hooksecurefunc("UnitPopup_HideButtons", function()
        if UIDROPDOWNMENU_MENU_LEVEL ~= 1 then return end
        local dropdownMenu = UIDROPDOWNMENU_INIT_MENU
        local menu = dropdownMenu and UnitPopupMenus[dropdownMenu.which]
        local shown = UnitPopupShown and UnitPopupShown[1]
        if not menu or not shown then return end
        for index, value in ipairs(menu) do
            if value == "CANCEL" then
                shown[index] = 0
            end
        end
    end)
end
