-- Module: WoW Forever look for the game menu (Escape)
-- (owner, 2026-11-13: "refais le menu esc facon wow forever avec les model de DragonUI").
--
-- Only the paint changes; the stock GameMenuFrame still opens, closes and runs every button (Log Out,
-- Exit Game, the protected ones). The art is DragonUI's Forever kit (DragonUI\utils\forever_ui_chrome.lua):
--   * retail's dialog: dark fill, diamond-metal border, title inside the frame (ForeverUI.SkinDialog),
--   * retail's red three-slice buttons with gold text (ForeverUI.SkinButton).
-- Buttons added by other modules (Edit Mode, at PLAYER_LOGIN) are skinned on the next open.
-- Listed after edit_mode.lua in the toc: our OnShow hook runs after its re-chain, so the height we set
-- counts its button. Cost: work only when the menu opens, never per frame.

local TITLE_ROOM = 46       -- frame top to the first shown button: the title sits at -21, 20 px high
local BOTTOM_PAD = 22       -- from the last button to the bottom edge, inside the border

local function ForeverUI()
    return DragonUI and DragonUI.ForeverUI
end

local skinned = false

-- Measured, not assumed: the topmost SHOWN button must start TITLE_ROOM under the frame's top. The
-- buttons hang from each other (the patched client hides some, the chain still starts at a hidden one),
-- so we walk up from that button to the one anchored on the frame and lower that one.
local function ClearTitle(frame)
    local top = frame:GetTop()
    if not top then return end
    local first, firstTop
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == "Button" and child:IsShown() and child._fuSkinned then
            local t = child:GetTop()
            if t and (not firstTop or t > firstTop) then first, firstTop = child, t end
        end
    end
    if not first then return end
    local delta = TITLE_ROOM - (top - firstTop)
    if delta <= 0.5 then return end
    local node = first
    for _ = 1, 30 do
        if node:GetNumPoints() == 0 then return end
        local point, rel, relPoint, x, y = node:GetPoint(1)
        if rel == frame then
            node:SetPoint(point, rel, relPoint, x, y - delta)
            return
        end
        if not (rel and rel.GetParent and rel:GetParent() == frame) then return end
        node = rel
    end
end

-- Height from what really shows: top of the frame down to the lowest shown button, plus the padding.
local function FitHeight(frame)
    local top = frame:GetTop()
    if not top then return end
    local lowest
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == "Button" and child:IsShown() and child._fuSkinned then
            local bottom = child:GetBottom()
            if bottom and (not lowest or bottom < lowest) then lowest = bottom end
        end
    end
    if lowest then frame:SetHeight(top - lowest + BOTTOM_PAD) end
end

local function SkinButtons(frame)
    local ui = ForeverUI()
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == "Button" and child ~= frame.CloseButton then
            ui.SkinButton(child)
            child:SetNormalFontObject(GameFontHighlight)   -- white, not the kit's gold (owner)
        end
    end
end

-- LibBetterBlizzOptions (shipped inside CompactRaidFrame and Details) makes the menu draggable from a
-- strip at its top, at PLAYER_LOGIN. This look is built for a fixed, centred menu: dragged, part of it
-- moved and part stayed. The strip is switched off, and a menu dragged earlier (the position the client
-- remembers) is centred again.
local function Pin(frame)
    local mover = _G.GameMenuFrameMover
    if mover then mover:EnableMouse(false) end
    if frame:IsMovable() then
        frame:StopMovingOrSizing()
        if frame:IsUserPlaced() then frame:SetUserPlaced(false) end
        frame:SetMovable(false)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function OnShow(frame)
    if not skinned then return end
    Pin(frame)
    SkinButtons(frame)
    ClearTitle(frame)
    FitHeight(frame)
end

local function Skin()
    local frame = GameMenuFrame
    local ui = ForeverUI()
    if skinned or not (frame and ui and ui.SkinDialog and ui.SkinButton) then return end
    skinned = true

    -- stock art: dialog backdrop, header plate and its text (all regions of the frame itself)
    frame:SetBackdrop(nil)
    for _, region in ipairs({ frame:GetRegions() }) do
        region:Hide()
    end

    ui.SkinDialog(frame, { title = MAINMENU_BUTTON, closable = false, movable = false })
    frame:HookScript("OnShow", OnShow)
    OnShow(frame)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Skin()
end)
