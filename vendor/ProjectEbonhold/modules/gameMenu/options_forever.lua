-- Module: WoW Forever look for the option windows of the game menu - Video, Sound, Interface
-- (owner, 2026-11-13: "restylise le menu des options facon DragonUI aussi").
--
-- Only the paint changes; the stock frames still show the panels and save every setting (Okay / Cancel /
-- Defaults / Apply keep their stock scripts). The art is DragonUI's Forever kit:
--   * retail's metal Settings window, title in its bar (ForeverUI.SkinWindow),
--   * boxed category list and panel area (ForeverUI.AttachBoxBorder),
--   * red three-slice buttons, minimal checkboxes and slider bars, DragonUI's slim scroll bar.
-- Only controls still wearing the STOCK art are repainted: our own panels (and anything DragonUI already
-- dressed) keep theirs. Drop-downs stay stock (the kit's drop-down skin is built for its own widgets).
-- Panels are walked when a window opens and when a category is shown (addons add panels late).
-- Cost: work only when an option window opens or changes page, never per frame.

local WINDOWS = { "VideoOptionsFrame", "AudioOptionsFrame", "InterfaceOptionsFrame" }
local CHECK_SIZE = 26       -- the stock box size: labels and rows stay where the panels put them

local function ForeverUI()
    return DragonUI and DragonUI.ForeverUI
end

local function TexturePath(texture)
    local path = texture and texture.GetTexture and texture:GetTexture()
    return type(path) == "string" and path:lower() or ""
end

local function IsStockPanelButton(button)
    local name = button:GetName()
    local left = name and _G[name .. "Left"]
    return left and TexturePath(left):find("ui%-panel%-button") ~= nil
end

local function IsStockCheck(button)
    return TexturePath(button:GetCheckedTexture()):find("ui%-checkbox%-check") ~= nil
end

local function IsStockSlider(slider)
    if slider:GetOrientation() ~= "HORIZONTAL" then return false end
    return TexturePath(slider:GetThumbTexture()):find("ui%-sliderbar%-button") ~= nil
end

-- One pass over a frame and everything under it; each control is repainted once (the kit marks it).
local function Dress(frame, ui)
    local kind = frame:GetObjectType()
    if kind == "Button" then
        if not frame._fuSkinned and IsStockPanelButton(frame) then
            ui.SkinButton(frame)
            frame:SetNormalFontObject(GameFontHighlight)   -- white, not the kit's gold (owner)
        end
    elseif kind == "CheckButton" then
        if not frame._eboForeverCheck and IsStockCheck(frame) then
            frame._eboForeverCheck = true
            ui.SkinCheckButton(frame)
            frame:SetSize(CHECK_SIZE, CHECK_SIZE)
        end
    elseif kind == "Slider" then
        if not frame._fuBar and IsStockSlider(frame) then ui.SkinSlider(frame, { steppers = false }) end
    elseif kind == "ScrollFrame" then
        local name = frame:GetName()
        local bar = name and _G[name .. "ScrollBar"]
        if bar and not bar._duiReskinned and not bar._fuScroll then utils.UseDragonScrollBar(frame) end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        Dress(child, ui)
    end
end

-- Stock boxed areas (category list, panel container): backdrop off, the kit's box rail on.
local function Box(frame, ui)
    if not frame or frame._eboForeverBox then return end
    frame._eboForeverBox = true
    frame:SetBackdrop(nil)
    ui.AttachBoxBorder(frame)
end

local function SkinWindow(name, ui)
    local frame = _G[name]
    if not frame or frame._eboForever then return end
    frame._eboForever = true

    local header = _G[name .. "HeaderText"]
    local title = header and header:GetText()
    -- stock art: dialog backdrop, header plate and its text (regions of the frame itself)
    frame:SetBackdrop(nil)
    for _, region in ipairs({ frame:GetRegions() }) do
        region:Hide()
    end
    ui.SkinWindow(frame, { title = title, closable = false, movable = false })
    if frame.TitleText then frame.TitleText:SetFontObject(GameFontHighlight) end   -- white title (owner)

    Box(_G[name .. "CategoryFrame"], ui)
    Box(_G[name .. "PanelContainer"], ui)

    local function refresh() Dress(frame, ui) end
    frame:HookScript("OnShow", refresh)
    refresh()
end

local function Skin()
    local ui = ForeverUI()
    if not (ui and ui.SkinWindow and ui.SkinButton and ui.AttachBoxBorder) then return end
    for _, name in ipairs(WINDOWS) do
        SkinWindow(name, ui)
    end
    -- a category click shows its panel without re-opening the window: dress what it brought
    local function redress()
        for _, name in ipairs(WINDOWS) do
            local frame = _G[name]
            if frame and frame._eboForever and frame:IsShown() then Dress(frame, ui) end
        end
    end
    for _, fn in ipairs({ "InterfaceOptionsList_DisplayPanel", "OptionsList_DisplayPanel" }) do
        if _G[fn] then hooksecurefunc(fn, redress) end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Skin()
end)
