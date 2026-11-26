-- If Nexus is installed, attach a roster tab to its panel. Docking is a
-- temporary window position: dragging or closing restores normal placement.
local addonName = ...
local addon = _G[addonName]
local Integration = {}
addon.Integrations.Nexus = Integration

local panel, tab, roster, freePoint
local hooked, docked = false, false
local watch = CreateFrame("Frame")
watch:Hide()

local function UIUnits(target, method)
    if not target or type(target[method]) ~= "function" then return nil end
    local value = target[method](target)
    if type(value) ~= "number" then return nil end
    return value * target:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function RestorePosition()
    if not roster or not freePoint then return end
    roster:ClearAllPoints()
    roster:SetPoint(freePoint.point, freePoint.relative, freePoint.relativePoint, freePoint.x, freePoint.y)
    freePoint = nil
end

function Integration.Detach()
    if docked then
        docked = false
        freePoint = nil
        if tab then tab:UnlockHighlight() end
    end
end

local function PositionRoster()
    if not docked or not roster or not panel or not panel:IsShown() then return end
    local left, right, top = UIUnits(panel, "GetLeft"), UIUnits(panel, "GetRight"), UIUnits(panel, "GetTop")
    if not left or not right or not top then return end
    local parentScale = UIParent:GetEffectiveScale()
    local scale = roster:GetEffectiveScale() / parentScale
    local width, height = roster:GetWidth() * scale, roster:GetHeight() * scale
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if screenWidth <= 0 or screenHeight <= 0 then return end
    local roomLeft, roomRight = left - 8, screenWidth - right - 8
    local useRight = roomRight >= width + 6 or roomRight >= roomLeft
    local x = useRight and right + 6 or left - width - 6
    -- Keep the window on screen when neither side has enough room.
    x = math.max(8, math.min(math.max(8, screenWidth - width - 8), x))
    local y = math.max(height + 8, math.min(screenHeight - 8, top))
    roster:ClearAllPoints()
    roster:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

local function OpenDocked()
    roster = addon:ShowRosterUI()
    if not roster._ashoholicNexusHooked then
        roster._ashoholicNexusHooked = true
        roster:HookScript("OnHide", function()
            if docked then
                docked = false
                RestorePosition()
                if tab then tab:UnlockHighlight() end
            end
        end)
    end
    if not docked then
        local point, relative, relativePoint, x, y = roster:GetPoint(1)
        if not point then error("Ashoholic could not save the roster position before docking.") end
        freePoint = { point = point, relative = relative, relativePoint = relativePoint, x = x, y = y }
    end
    docked = true
    PositionRoster()
    tab:LockHighlight()
end

local function PositionTab()
    if not tab or not panel then return end
    local top = UIUnits(panel, "GetTop")
    if not top then return end
    local roomAbove = UIParent:GetHeight() - top
    local drop = math.max(3, 20 - math.max(0, roomAbove))
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 6, -drop)
end

local function Install(candidate)
    if panel == candidate then return end
    if panel then error("Ashoholic cannot attach to a second Nexus panel in the same session.") end
    panel = candidate
    tab = CreateFrame("Button", "AshoholicNexusRosterTab", panel, "UIPanelButtonTemplate")
    tab:SetSize(160, 20)
    tab:SetText("Character Roster")
    tab:SetFrameLevel(panel:GetFrameLevel() + 40)
    tab:SetScript("OnClick", function()
        if docked and roster and roster:IsShown() then roster:Hide() else OpenDocked() end
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Character Roster", 1, 0.79, 0.39)
        GameTooltip:AddLine("Open the Ashoholic roster beside Nexus. Drag it to detach.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel:HookScript("OnShow", function() watch:Show(); PositionTab() end)
    panel:HookScript("OnHide", function()
        watch:Hide()
        if docked and roster and roster:IsShown() then roster:Hide() end
    end)
    if panel:IsShown() then watch:Show(); PositionTab() end
end

local function TryInstall()
    local candidate = _G.NexusPanel
    if candidate and candidate.GetObjectType and candidate:GetObjectType() == "Frame" then
        Install(candidate)
    end
end

local function HookNexus()
    if hooked or not IsAddOnLoaded or not IsAddOnLoaded("Nexus") then return end
    local api = _G.Nexus and _G.Nexus.Panel
    if type(api) == "table" then
        for _, name in ipairs({ "Show", "Toggle", "Render" }) do
            if type(api[name]) == "function" then hooksecurefunc(api, name, TryInstall) end
        end
    elseif not _G.NexusPanel then
        print("|cffffca63Ashoholic:|r Nexus is loaded, but its panel API is unavailable.")
    end
    hooked = true
    TryInstall()
end

local elapsed = 0
watch:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.1 then return end
    elapsed = 0
    PositionTab()
    PositionRoster()
end)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" or name == "Nexus" then HookNexus() end
end)
HookNexus()
