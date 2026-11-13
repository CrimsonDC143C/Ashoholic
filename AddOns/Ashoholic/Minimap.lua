-- The minimap button opens the live roster. Its placement and visibility are
-- local preferences saved through Data, not part of an account snapshot.
local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local MinimapButton = {}
addon.Minimap = MinimapButton

local button
local angle
local selectedIcon

function MinimapButton.SetIcon(path)
    selectedIcon = path
    if button then button.icon:SetTexture(path) end
end

local function Position()
    if not button then return end
    local radians = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(radians), 80 * math.sin(radians))
end

function MinimapButton.Refresh()
    if not button then return end
    local settings = Data.GetMinimapSettings()
    angle = settings.angle
    Position()
    if settings.hidden then button:Hide() else button:Show() end
end

local function CreateButton()
    button = CreateFrame("Button", "AshoholicMinimapButton", Minimap)
    button:SetSize(33, 33)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(10)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("RightButton")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon = icon
    local saved = Data.GetDashboardSettings()
    icon:SetTexture(selectedIcon or (saved and saved.state.logo) or "Interface\\Icons\\inv_soulash")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function() addon:ToggleRosterUI() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Ashoholic", 1, 0.79, 0.39)
        GameTooltip:AddLine("Left-click: open roster", 1, 1, 1)
        GameTooltip:AddLine("Right-drag: move icon", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local centerX, centerY = Minimap:GetCenter()
            if centerX and centerY then
                local scale = Minimap:GetEffectiveScale()
                angle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX))
                Position()
            end
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        local settings = Data.GetMinimapSettings()
        Data.SaveMinimapSettings(angle, settings.hidden)
    end)
    MinimapButton.Refresh()
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    CreateButton()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
