-- When Nexus is installed, add a "Character Roster" tab on the top edge of
-- its panel. Clicking the tab opens this roster beside the panel, on the
-- side that can hold it without pushing it off the screen.

local addonName = ...
local addon = _G[addonName]

local GAP = 6
local MARGIN = 8
local TAB_OVERLAP = 3
local TAB_LABEL = "Character Roster"

local tab
local watch
local installed = false
local apiHooked = false
local docked = false
local restoreOnPanelShow = false
local anchorIsDock = false
local preferSide
local sizing = false
local suppressRosterHide = false
local freePoint
local restoreSerial = 0
local appliedSide, appliedX, appliedY
local appliedDrop

local function UIScale()
    return (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
end

-- GetLeft/GetWidth are in a frame's own scale. Compare and place frames in
-- UIParent units, then convert back when calling SetPoint.
local function UIUnits(frame, method)
    if not frame or type(frame[method]) ~= "function" then return nil end
    local value = frame[method](frame)
    if type(value) ~= "number" then return nil end
    local scale = frame:GetEffectiveScale() or 1
    return value * scale / UIScale()
end

local function PointOffset(frame, uiUnits)
    local scale = frame:GetEffectiveScale() or 1
    return uiUnits * UIScale() / scale
end

local function NexusLoaded()
    if type(IsAddOnLoaded) == "function" and IsAddOnLoaded("Nexus") then
        return type(_G.Nexus) == "table" and type(_G.Nexus.Panel) == "table"
    end
    return false
end

local function Panel()
    local panel = _G.NexusPanel
    if panel and panel.GetObjectType and panel:GetObjectType() == "Frame" then
        return panel
    end
    return nil
end

local function SetTabSelected(selected)
    if not tab then return end
    local theme = _G.Nexus and _G.Nexus.Theme
    if theme and type(theme.SetSelected) == "function" then
        pcall(theme.SetSelected, tab, selected and true or false)
    elseif selected then
        pcall(tab.LockHighlight, tab)
    else
        pcall(tab.UnlockHighlight, tab)
    end
end

local function CaptureFreePoint(roster)
    if anchorIsDock or not roster then return end
    local point, rel, relPoint, x, y = roster:GetPoint(1)
    if not point then
        freePoint = nil
        return
    end
    freePoint = {
        point = point,
        rel = rel,
        relPoint = relPoint,
        x = x or 0,
        y = y or 0,
    }
end

local function RestoreFreePoint(roster)
    anchorIsDock = false
    appliedSide, appliedX, appliedY = nil, nil, nil
    if not roster then return end
    roster:ClearAllPoints()
    local saved = freePoint
    if type(saved) == "table" and type(saved.point) == "string" then
        local rel = saved.rel
        if type(rel) ~= "table" then rel = UIParent end
        local ok = pcall(roster.SetPoint, roster, saved.point, rel, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
        if ok then return end
    end
    roster:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function ChooseSide(roomLeft, roomRight, need)
    local leftFits = roomLeft >= need
    local rightFits = roomRight >= need
    if preferSide == "LEFT" and leftFits then return "LEFT" end
    if preferSide == "RIGHT" and rightFits then return "RIGHT" end
    if leftFits and rightFits then
        if roomRight > roomLeft then return "RIGHT" end
        return "LEFT"
    end
    if rightFits then return "RIGHT" end
    if leftFits then return "LEFT" end
    -- Neither side can hold the whole roster. Stay on the current side while
    -- it is essentially tied, otherwise use the side with more room.
    if preferSide == "LEFT" and roomLeft >= roomRight - 8 then return "LEFT" end
    if preferSide == "RIGHT" and roomRight >= roomLeft - 8 then return "RIGHT" end
    if roomRight > roomLeft then return "RIGHT" end
    return "LEFT"
end

local function ApplyDock()
    local panel = Panel()
    local roster = _G.AshoholicFrame
    if not docked or sizing or not panel or not roster or not roster:IsShown() then return end
    if not panel:IsShown() then return end

    local screenW = UIParent:GetWidth() or 0
    local screenH = UIParent:GetHeight() or 0
    local panelLeft = UIUnits(panel, "GetLeft")
    local panelRight = UIUnits(panel, "GetRight")
    local panelTop = UIUnits(panel, "GetTop")
    local rosterW = UIUnits(roster, "GetWidth") or 0
    local rosterH = UIUnits(roster, "GetHeight") or 0
    if not panelLeft or not panelRight or not panelTop or screenW <= 0 or screenH <= 0 then return end

    local need = rosterW + GAP + MARGIN
    local side = ChooseSide(panelLeft, screenW - panelRight, need)
    preferSide = side

    local xOffset = GAP
    if side == "RIGHT" then
        local overflow = (panelRight + GAP + rosterW) - (screenW - MARGIN)
        if overflow > 0 then xOffset = GAP - overflow end
    else
        local overflow = MARGIN - (panelLeft - GAP - rosterW)
        if overflow > 0 then xOffset = GAP - overflow end
    end

    local top = panelTop
    if top - rosterH < MARGIN then top = MARGIN + rosterH end
    if top > screenH - MARGIN then top = screenH - MARGIN end
    local yOffset = top - panelTop

    if anchorIsDock and appliedSide == side
        and appliedX and math.abs(appliedX - xOffset) < 0.5
        and appliedY and math.abs(appliedY - yOffset) < 0.5 then
        return
    end

    -- A press on the roster (resize grip, row, button) must keep the anchor
    -- StartSizing is already using. The next idle frame catches up.
    if IsMouseButtonDown and IsMouseButtonDown("LeftButton")
        and roster.IsMouseOver and roster:IsMouseOver() then
        return
    end

    appliedSide, appliedX, appliedY = side, xOffset, yOffset
    local x = PointOffset(roster, xOffset)
    local y = PointOffset(roster, yOffset)
    roster:ClearAllPoints()
    if side == "RIGHT" then
        roster:SetPoint("TOPLEFT", panel, "TOPRIGHT", x, y)
    else
        roster:SetPoint("TOPRIGHT", panel, "TOPLEFT", -x, y)
    end
    anchorIsDock = true
end

local function ScheduleFreeRestore(roster)
    restoreSerial = restoreSerial + 1
    local serial = restoreSerial
    local function restore()
        if serial ~= restoreSerial then return end
        if not roster or roster:IsShown() or docked then return end
        RestoreFreePoint(roster)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, restore)
    else
        restore()
    end
end

local function OnRosterHide(roster)
    if suppressRosterHide then return end
    SetTabSelected(false)
    local shouldRestore = anchorIsDock
    docked = false
    restoreOnPanelShow = false
    preferSide = nil
    -- Move back to the free position after the hide paints, so the roster
    -- does not flash through the middle of the screen as it closes.
    if shouldRestore then ScheduleFreeRestore(roster) end
end

local function HookRoster(roster)
    if not roster or roster._ashNexusHooked then return end
    roster._ashNexusHooked = true
    roster:HookScript("OnDragStart", function()
        if not docked and not anchorIsDock then return end
        restoreSerial = restoreSerial + 1
        docked = false
        restoreOnPanelShow = false
        preferSide = nil
        anchorIsDock = false
        appliedSide, appliedX, appliedY = nil, nil, nil
        SetTabSelected(false)
    end)
    roster:HookScript("OnHide", OnRosterHide)
    if type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, roster, "StartSizing", function() sizing = true end)
        pcall(hooksecurefunc, roster, "StopMovingOrSizing", function()
            local wasSizing = sizing
            sizing = false
            if wasSizing and docked then ApplyDock() end
        end)
    end
end

local function PrepareRoster()
    if RequestRaidInfo then pcall(RequestRaidInfo) end
    if addon.UpdateCurrentCharacterData then addon:UpdateCurrentCharacterData() end
    if addon.UpdateSavedInstances then addon:UpdateSavedInstances() end
    if addon.UpdateSoulAshData then addon:UpdateSoulAshData() end
    if addon.UpdateRaidResetCost then addon:UpdateRaidResetCost() end
    if addon.Characters then
        addon.Characters:BuildList()
        if addon.Characters.ReapplySort then addon.Characters:ReapplySort() end
        addon.Characters:BuildView()
    end
    if addon.CreateUI then addon:CreateUI() end
    local roster = _G.AshoholicFrame
    if roster then
        HookRoster(roster)
        if roster.Refresh then roster:Refresh() end
    end
    return roster
end

local function ShowDocked(refresh)
    local panel = Panel()
    if not panel then return end
    restoreSerial = restoreSerial + 1
    local roster = refresh and PrepareRoster() or _G.AshoholicFrame
    if not roster and addon.CreateUI then
        addon:CreateUI()
        roster = _G.AshoholicFrame
    end
    if not roster then return end
    HookRoster(roster)
    if not anchorIsDock then CaptureFreePoint(roster) end
    docked = true
    restoreOnPanelShow = true
    if not roster:IsShown() then roster:Show() end
    ApplyDock()
    SetTabSelected(true)
end

local function CloseDocked()
    local roster = _G.AshoholicFrame
    docked = false
    restoreOnPanelShow = false
    preferSide = nil
    SetTabSelected(false)
    if roster and roster:IsShown() then
        roster:Hide()
    elseif roster and anchorIsDock then
        RestoreFreePoint(roster)
    end
end

local function FitTab(panel)
    if not tab then return end
    local fs = tab.GetFontString and tab:GetFontString()
    if fs then
        pcall(fs.SetWordWrap, fs, false)
        pcall(fs.SetJustifyH, fs, "CENTER")
    end
    local textW = fs and fs.GetStringWidth and fs:GetStringWidth() or 0
    if type(textW) ~= "number" or textW < 40 then textW = 122 end
    local maxW = (panel and panel:GetWidth() or 240) - 16
    if maxW < 80 then maxW = 80 end
    local width = math.ceil(textW + 26)
    if width > maxW then width = maxW end
    if width < 80 then width = 80 end
    if math.abs((tab:GetWidth() or 0) - width) > 0.5 then
        tab:SetWidth(width)
    end
end

-- The tab sits on the top-left edge. Near the top of the screen it slides
-- down onto the panel so the label stays clickable.
local function UpdateTabPlacement(panel)
    if not tab or not panel then return end
    FitTab(panel)
    local screenH = UIParent:GetHeight() or 0
    local panelTop = UIUnits(panel, "GetTop")
    local tabH = UIUnits(tab, "GetHeight") or tab:GetHeight() or 20
    if not panelTop or screenH <= 0 then return end

    local roomAbove = screenH - panelTop
    local drop = TAB_OVERLAP
    if roomAbove < tabH - TAB_OVERLAP then
        drop = tabH - math.max(roomAbove, 0)
    end
    if appliedDrop and math.abs(appliedDrop - drop) < 0.5 then return end
    appliedDrop = drop

    local level = (panel:GetFrameLevel() or 0) + 40
    pcall(tab.SetFrameLevel, tab, level)
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", PointOffset(tab, 6), -PointOffset(tab, drop))
end

local function OnWatch()
    local panel = Panel()
    if not panel or not panel:IsShown() then
        if watch then watch:Hide() end
        return
    end
    UpdateTabPlacement(panel)
    if docked and not sizing then ApplyDock() end
end

local function OnPanelShow()
    if watch then watch:Show() end
    local panel = Panel()
    if panel then UpdateTabPlacement(panel) end
    if docked and restoreOnPanelShow then ShowDocked(false) end
end

local function OnPanelHide()
    local roster = _G.AshoholicFrame
    if watch then watch:Hide() end
    if docked and roster and roster:IsShown() then
        restoreOnPanelShow = true
        suppressRosterHide = true
        pcall(roster.Hide, roster)
        suppressRosterHide = false
    end
end

local function CreateTab(panel)
    local button = CreateFrame("Button", "AshoholicNexusRosterTab", panel, "UIPanelButtonTemplate")
    if not button then
        button = CreateFrame("Button", "AshoholicNexusRosterTab", panel)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetAllPoints()
        button:SetFontString(label)
    end
    button:SetText(TAB_LABEL)
    button:SetHeight(20)
    button:SetWidth(160)
    button:RegisterForClicks("LeftButtonUp")
    button:SetFrameLevel((panel:GetFrameLevel() or 0) + 40)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 6, -TAB_OVERLAP)
    appliedDrop = TAB_OVERLAP
    button:SetScript("OnClick", function()
        local roster = _G.AshoholicFrame
        if docked and roster and roster:IsShown() then
            CloseDocked()
        else
            ShowDocked(true)
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Character Roster", 1, 0.82, 0)
        GameTooltip:AddLine("Open the Ashoholic roster beside this panel.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Click again to close it. Drag the roster to detach it.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local theme = _G.Nexus and _G.Nexus.Theme
    if theme and type(theme.StyleButton) == "function" then
        pcall(theme.StyleButton, button, true)
    end
    if theme and type(theme.SetSelected) == "function" then
        pcall(theme.SetSelected, button, false)
    end
    return button
end

local function Install(panel)
    if installed or not panel or panel._ashoholicRosterHooked then return end
    local button = tab or _G.AshoholicNexusRosterTab or CreateTab(panel)
    if not button then return end
    tab = button
    panel._ashoholicRosterHooked = true
    panel:HookScript("OnShow", OnPanelShow)
    panel:HookScript("OnHide", OnPanelHide)
    installed = true
    if panel:IsShown() then OnPanelShow() end
end

local function TryInstall()
    if installed or not NexusLoaded() then return end
    local panel = Panel()
    if panel then Install(panel) end
end

local function HookNexusApi()
    if apiHooked or not NexusLoaded() then return end
    local panelApi = _G.Nexus.Panel
    if type(hooksecurefunc) ~= "function" then return end
    apiHooked = true
    local function safeInstall()
        pcall(TryInstall)
    end
    if type(panelApi.Show) == "function" then
        hooksecurefunc(panelApi, "Show", safeInstall)
    end
    if type(panelApi.Toggle) == "function" then
        hooksecurefunc(panelApi, "Toggle", safeInstall)
    end
    if type(panelApi.Render) == "function" then
        hooksecurefunc(panelApi, "Render", safeInstall)
    end
    safeInstall()
end

watch = CreateFrame("Frame")
watch:Hide()
watch:SetScript("OnUpdate", OnWatch)

local broker = CreateFrame("Frame")
broker:RegisterEvent("ADDON_LOADED")
broker:RegisterEvent("PLAYER_LOGIN")
broker:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Nexus" then return end
    HookNexusApi()
    TryInstall()
end)

HookNexusApi()
