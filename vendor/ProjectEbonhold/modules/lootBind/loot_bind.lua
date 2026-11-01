-- Module: Loot Bind
-- Skips the "Looting X will bind it to you" confirmation (StaticPopup
-- LOOT_BIND) when the "autoConfirmLootBind" option is on: the dialog is
-- accepted for the player the frame after it appears, through the exact same
-- path as clicking Okay (StaticPopup_OnClick -> OnAccept -> ConfirmLootSlot).
--
-- Hooking StaticPopup_Show rather than LOOT_BIND_CONFIRM keeps this working
-- no matter who raises the dialog (FrameXML LootFrame, ElvUI's loot frame,
-- auto-loot) and without racing them for the event. The accept is deferred
-- one frame because the caller sets dialog.data (the loot slot) only after
-- StaticPopup_Show returns, and OnAccept needs it.
--
-- The option's checkbox is added from here into the native
-- "Project Ebonhold > General" panel (InterfaceOptionsPanels.xml, patch-8),
-- so the whole feature ships with the addon alone.

local SETTING = "autoConfirmLootBind"

local function IsEnabled()
    return ProjectEbonholdOptionsService
        and ProjectEbonholdOptionsService:GetSetting(SETTING) and true or false
end

-- ── Auto-accept ──────────────────────────────────────────────────────────

local pending = false

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(self)
    self:Hide()
    pending = false
    local name = StaticPopup_Visible("LOOT_BIND")
    local dialog = name and _G[name]
    if dialog and dialog.data then
        StaticPopup_OnClick(dialog, 1)
    end
end)

hooksecurefunc("StaticPopup_Show", function(which)
    if which ~= "LOOT_BIND" or pending or not IsEnabled() then return end
    pending = true
    ticker:Show()
end)

-- ── Options checkbox (native General panel) ──────────────────────────────

local function CreateOptionCheckbox()
    local panel = _G.InterfaceOptionsProjectEbonholdPanelGeneral
    if not panel or panel.ebonholdLootBindCheck then return end

    local cb = CreateFrame("CheckButton", "ProjectEbonholdLootBindCheck", panel,
        "InterfaceOptionsCheckButtonTemplate")
    -- Same column as the panel's own rows, right under "Auto-sell junk".
    local last = _G[panel:GetName() .. "AutoSellJunk"]
    if last then
        cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 0)
    else
        cb:SetPoint("TOPLEFT", 16, -182)
    end
    _G[cb:GetName() .. "Text"]:SetText("Skip the \"will bind it to you\" loot confirmation")
    cb:SetScript("OnClick", function(self)
        if ProjectEbonholdOptionsService then
            ProjectEbonholdOptionsService:SetSetting(SETTING, self:GetChecked() and true or false)
        end
    end)
    panel.ebonholdLootBindCheck = cb

    -- The panel refreshes its own rows from OnShow / self.refresh; ride along.
    local function Refresh() cb:SetChecked(IsEnabled()) end
    panel:HookScript("OnShow", Refresh)
    if panel.refresh then hooksecurefunc(panel, "refresh", Refresh) end
    Refresh()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    CreateOptionCheckbox()
end)
