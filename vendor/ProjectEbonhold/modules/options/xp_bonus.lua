-- Module: Experience Bonuses switch
-- One entry in the player portrait's right-click menu (PlayerFrame, "SELF" unit popup) that turns
-- the aura experience bonuses off or back on: heirlooms, the skill tree and echoes. Made to level
-- at a friend's pace (2026-10-26). Base experience is never touched.
--
-- The server holds the choice (Player::HasXpAuraBonusDisabled, characters.character_xp_aura_settings)
-- and enforces it on kills, gathering and quests. This file only asks (REQUEST_XP_AURA_BONUS_SET) and
-- shows what the server answered (SEND_XP_AURA_BONUS_STATE, pushed at login and after every switch).

local BUTTON = "EBONHOLD_XP_BONUS"

local bonusesOff = false

local function RefreshText()
    UnitPopupButtons[BUTTON].text = bonusesOff
        and "Experience Bonuses: |cffFF4444Off|r"
        or "Experience Bonuses: |cff00FF00On|r"
end

-- ── Unit popup entry ─────────────────────────────────────────────────────
--
-- UnitPopup.lua is FrameXML, so its tables exist by the time this file runs (same as
-- torment/raid_difficulty_lock.lua). The entry goes just above Cancel on the player's own menu.

if type(UnitPopupButtons) == "table" and type(UnitPopupMenus) == "table" and UnitPopupMenus["SELF"] then
    UnitPopupButtons[BUTTON] = { text = "", dist = 0 }
    RefreshText()

    local menu = UnitPopupMenus["SELF"]
    local at = #menu + 1
    for i, value in ipairs(menu) do
        if value == "CANCEL" then
            at = i
            break
        end
    end
    table.insert(menu, at, BUTTON)

    -- Turning them back on costs the Death contracts' gauge (the server enforces it, 2026-10-29):
    -- ask first whenever there is a gauge to lose. The Pact keeps its gauge, so no question then.
    StaticPopupDialogs["EBONHOLD_XP_BONUS_ON"] = {
        text = "Turning experience bonuses back on resets your contract bonus (%s) to zero.\n\nTurn them on?",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_XP_AURA_BONUS_SET, "0")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
    }

    hooksecurefunc("UnitPopup_OnClick", function(self)
        if self.value ~= BUTTON then return end
        local reaper = ProjectEbonhold.Reaper
        if bonusesOff and reaper and not reaper.pact and (reaper.gauge or 0) > 0 then
            StaticPopup_Show("EBONHOLD_XP_BONUS_ON", reaper.GaugeText())
            return
        end
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_XP_AURA_BONUS_SET, bonusesOff and "0" or "1")
    end)

    -- Tooltip: the stock menu only shows one when "Beginner Tooltips" is on, so the level-1 menu
    -- buttons get a hook of their own. They are shared by every dropdown: the hook only acts on ours.
    local function ShowTooltip(self)
        if self.value ~= BUTTON then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Experience Bonuses", 1, 1, 1)
        GameTooltip:AddLine("Heirlooms, the skill tree and echoes increase the experience you gain from kills, gathering and quests.", nil, nil, nil, true)
        GameTooltip:AddLine("Turn them off to level at the same pace as a friend. Your normal experience does not change.", nil, nil, nil, true)
        GameTooltip:AddLine("Turning them back on resets your contract bonus to zero.", 1, 0.5, 0.25, true)
        GameTooltip:AddLine(" ")
        if bonusesOff then
            GameTooltip:AddLine("Currently: |cffFF4444Off|r", 1, 1, 1)
            GameTooltip:AddLine("Click to turn them back on.", 0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddLine("Currently: |cff00FF00On|r", 1, 1, 1)
            GameTooltip:AddLine("Click to turn them off.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end

    local function HideTooltip(self)
        if self.value == BUTTON and GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end

    hooksecurefunc("UnitPopup_ShowMenu", function()
        for i = 1, UIDROPDOWNMENU_MAXBUTTONS do
            local button = _G["DropDownList1Button" .. i]
            if button and not button.ebonholdXpBonusHooked then
                button:HookScript("OnEnter", ShowTooltip)
                button:HookScript("OnLeave", HideTooltip)
                button.ebonholdXpBonusHooked = true
            end
        end
    end)
end

-- ── Server state ─────────────────────────────────────────────────────────

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_XP_AURA_BONUS_STATE, function(body)
    bonusesOff = body == "1"
    if UnitPopupButtons and UnitPopupButtons[BUTTON] then
        RefreshText()
    end
end)

-- The login push can arrive before this file is loaded: ask again once in the world.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_XP_AURA_BONUS_STATE, "")
end)
