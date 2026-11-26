--[[
    UI/Progression.lua - the Progression tab (Torment and Prestige).

    Left: the Torment ladder. One row per visible account, because Torment
    access is ACCOUNT-WIDE: every character on an account shares it. A pip
    is filled only for a tier with saved unlock evidence; lower tiers are
    never assumed from a higher one. The difficulty each character has
    SELECTED stays per character and is shown in the Roster details instead.

    Right: one Prestige panel per visible account. Prestige is also
    account-wide. The values come from the last complete Prestige reply the
    server sent (on login, or when Ebonhold's Prestige panel opens), so the
    panel tooltip shows how old they are.

    Tier names, the ladder size and the Prestige gate are companion display
    rules (UI.model.rules). When they could not be read, the pips are hidden
    and the gate shows as Unknown instead of guessing.

    Everything shown comes from UI.model (UI/Model.lua); this file never
    reads game data or saved variables.

    Memory: ladder rows, pips and Prestige panels are pooled. They are made
    the first time they are needed and reused on every refresh.
]]

local addonName = ...
local addon = _G[addonName]
local UI = addon.UI

local GOLD, TEXT, MUTED = UI.GOLD, UI.TEXT, UI.MUTED
local PAGE_HEIGHT, CONTENT_WIDTH = UI.PAGE_HEIGHT, UI.CONTENT_WIDTH
local HALF_PANEL_WIDTH, PANEL_GAP = UI.HALF_PANEL_WIDTH, UI.PANEL_GAP

-- Layout from the approved preview.
local VIEWPORT = PAGE_HEIGHT - 75     -- height of both columns
local INNER = HALF_PANEL_WIDTH - 32   -- width inside a panel's 16 px margins
local LADDER_TOP = 46                 -- top of the clipped ladder area in its panel
local LADDER_FIRST = 6                -- first row inside it (52 from the panel top)
local LADDER_STEP = 54
local ROW_HEIGHT = 40                 -- name line, then the pips from y 23 to 40
local PIP_Y, PIP_HEIGHT, PIP_GAP = 23, 17, 6
local PRESTIGE_HEIGHT = 160
local PRESTIGE_STEP = 177

-- Pip colors from the preview: unlocked (shared teal) or no evidence.
local UNLOCKED_COLOR = UI.UNLOCKED_COLOR
local LOCKED_COLOR = { 0.11, 0.12, 0.15, 1 }

local LADDER_TITLE = "ACCOUNT TORMENT UNLOCKS"

-------------------------------------------------------------------------------
-- Tooltips (written when the mouse enters, from the data on the widget)
-------------------------------------------------------------------------------

-- One Torment tier pip. Its row remembers the account being shown.
local function PipTip(pip)
    local account = pip:GetParent().account
    if not account then
        return
    end
    local torment = account.source.torment
    UI.TipTitle(UI.TierName(pip.tier, UI.model.rules))
    if not torment then
        UI.TipLine("Unknown. Log in to a character on this account to collect its Torment access.", nil, MUTED)
    elseif torment.unlockedTiers[pip.tier] then
        UI.TipLine("Unlocked account-wide.")
    else
        UI.TipLine("No saved unlock evidence on this account.")
    end
    UI.TipLine("Updated", UI.FormatLastSeen(torment and torment.accessUpdatedAt), MUTED)
end

-- One account's ladder row (outside the pips).
local function LadderTip(row)
    local account = row.account
    if not account then
        return
    end
    local torment = account.source.torment
    UI.TipTitle(account.name .. " / Torment access")
    UI.TipLine("Highest access", UI.TierName(torment and torment.highestUnlocked, UI.model.rules))
    UI.TipLine("Updated", UI.FormatLastSeen(torment and torment.accessUpdatedAt))
    UI.TipLine("Access is shared by every character on this account. The difficulty each character "
        .. "has selected is shown in that character's Roster details.", nil, MUTED)
end

-- One account's Prestige panel: exact values and their age.
local function PrestigeTip(panel)
    local account = panel.account
    if not account then
        return
    end
    local prestige = account.source.prestige
    local rules = UI.model.rules
    UI.TipTitle(account.name .. " / Prestige")
    if not prestige then
        UI.TipLine("Ebonhold sends Prestige data when you log in or open its Prestige panel. "
            .. "Log in to a character on this account to collect it.", nil, MUTED)
        return
    end
    UI.TipLine("Prestiges done", UI.FormatNumber(prestige.count))
    UI.TipLine("Committed Soul Ash", UI.FormatNumber(prestige.gateProgress))
    UI.TipLine("Soul Ash gate", UI.FormatNumber(rules and rules.prestigeGate))
    UI.TipLine("Banked Soul Shards", UI.FormatNumber(prestige.pendingShards))
    UI.TipLine("Soul Essence on next Prestige", UI.FormatNumber(prestige.pendingEssence))
    UI.TipLine("Updated", UI.FormatLastSeen(prestige.updatedAt), MUTED)
    UI.TipLine("Prestige is shared by every character on this account. The banked Shards are the "
        .. "amount in the last Prestige reply, so the Soul Shards card may be newer.", nil, MUTED)
    UI.TipLine("Only the currency requirements are shown. The server can still refuse a Prestige, "
        .. "for example while dead or in combat.", nil, MUTED)
end

-------------------------------------------------------------------------------
-- Pooled widgets
-------------------------------------------------------------------------------

-- A label that always stays on one line (long text ends with "...").
local function OneLineLabel(parent, x, y, width, size, color, height)
    local label = UI.Label(parent, "", x, y, width, size, color)
    label:SetHeight(height)
    UI.NoWrap(label)
    return label
end

local function NewLadderRow(body)
    local row = CreateFrame("Frame", nil, body)
    row:SetSize(INNER, ROW_HEIGHT)
    row.name = OneLineLabel(row, 0, 0, 150, 12, TEXT, 14)
    row.note = OneLineLabel(row, 155, 0, INNER - 155, 11, MUTED, 13)
    row.pips = {}
    UI.TipProvider(row, LadderTip)
    return row
end

-- Torment I is tier 2 (tier 1 is Normal), so the ladder has one pip per
-- tier from 2 up to the ladder top, labelled 1, 2, 3 and so on. The count
-- comes from the companion's rules, so pips are laid out again if it changes.
local function LayoutPips(row, count)
    if row.pipCount == count then
        return
    end
    row.pipCount = count
    local pipWidth = count > 0 and (INNER - (count - 1) * PIP_GAP) / count or 0
    for index = 1, count do
        local pip = row.pips[index]
        if not pip then
            pip = UI.Surface(row, 0, PIP_Y, pipWidth, PIP_HEIGHT, LOCKED_COLOR)
            pip.label = UI.Label(pip, "", 0, 2, pipWidth, 10)
            pip.label:SetJustifyH("CENTER")
            UI.TipProvider(pip, PipTip)
            row.pips[index] = pip
        end
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", (index - 1) * (pipWidth + PIP_GAP), -PIP_Y)
        pip:SetWidth(pipWidth)
        pip.label:SetWidth(pipWidth)
        pip.label:SetText(tostring(index))
        pip.tier = index + 1
        pip:Show()
    end
    for index = count + 1, #row.pips do
        row.pips[index]:Hide()
    end
end

local function FillLadderRow(row, account, rules, pipCount)
    local torment = account.source.torment
    row.account = account
    row.name:SetText(account.name)
    UI.Paint(row.name, account.color or TEXT)
    if not torment then
        row.note:SetText("Not observed yet")
    elseif not torment.highestUnlocked then
        row.note:SetText("No unlock evidence saved")
    else
        row.note:SetText("Highest access: " .. UI.TierName(torment.highestUnlocked, rules))
    end
    LayoutPips(row, pipCount)
    for index = 1, pipCount do
        local pip = row.pips[index]
        local unlocked = torment and torment.unlockedTiers[pip.tier]
        UI.SetSurfaceColor(pip, unlocked and UNLOCKED_COLOR or LOCKED_COLOR)
        UI.RefreshTip(pip)
    end
    UI.RefreshTip(row)
end

local function NewPrestigePanel(body)
    local panel = UI.Surface(body, 0, 0, HALF_PANEL_WIDTH, PRESTIGE_HEIGHT)
    panel.title = OneLineLabel(panel, 16, 15, INNER, 14, GOLD, 17)
    panel.status = OneLineLabel(panel, 16, 44, INNER, 13, TEXT, 16)
    panel.gate = UI.DetailLine(panel, "Committed Ash / gate", "", 74)
    panel.shards = UI.DetailLine(panel, "Banked Shards", "", 99)
    panel.essence = UI.DetailLine(panel, "Next Prestige / Essence", "", 124)
    UI.TipProvider(panel, PrestigeTip)
    return panel
end

-- Whether the currency requirements are met, from the last Prestige reply.
local function PrestigeStatus(prestige, rules)
    if not prestige then
        return UI.DIM .. "Not received from Ebonhold yet.|r"
    elseif not rules then
        return UI.DIM .. "Soul Ash gate unknown|r"
    elseif prestige.gateProgress < rules.prestigeGate then
        return UI.AMBER .. "Ash requirement not met|r"
    elseif prestige.pendingEssence == nil then
        -- Older replies do not report the Shard reward.
        return "Shard requirement unknown"
    elseif prestige.pendingEssence == 0 then
        return UI.AMBER .. "Shard requirement not met|r"
    end
    return UI.GREEN .. "Currency requirements met|r"
end

local function FillPrestigePanel(panel, account, rules)
    local prestige = account.source.prestige
    panel.account = account
    panel.title:SetText(account.name .. "  /  Prestige " .. UI.FormatNumber(prestige and prestige.count))
    UI.Paint(panel.title, account.color or GOLD)
    panel.status:SetText(PrestigeStatus(prestige, rules))
    panel.gate:SetText(UI.FormatNumber(prestige and prestige.gateProgress) .. " / "
        .. UI.FormatNumber(rules and rules.prestigeGate))
    panel.shards:SetText(UI.FormatNumber(prestige and prestige.pendingShards))
    local essence = prestige and prestige.pendingEssence
    panel.essence:SetText(essence and ("+" .. UI.FormatNumber(essence) .. " Essence") or "Unknown")
    UI.RefreshTip(panel)
end

-- The ladder has no scroll bar in the approved design. With more accounts
-- than fit, the mouse wheel scrolls it and the title says so.
local function LadderWheel(scroll, delta)
    local maximum = scroll:GetVerticalScrollRange()
    scroll:SetVerticalScroll(math.max(0, math.min(maximum, scroll:GetVerticalScroll() - delta * 30)))
end

-------------------------------------------------------------------------------
-- Building the page (runs once, the first time the Progression tab is shown)
-------------------------------------------------------------------------------

local function BuildProgression(parent)
    local page = UI.Page(parent, "Torment & Prestige",
        "Account-wide Torment access (the new Hardcore ladder), alongside account Prestige readiness.")

    -- Left column: the ladder panel. Its rows sit in a scroll frame without
    -- a bar, which clips rows that do not fit.
    local ladder = UI.Surface(page, 0, 57, HALF_PANEL_WIDTH, VIEWPORT)
    local ladderTitle = UI.Label(ladder, LADDER_TITLE, 16, 17, INNER, 11, GOLD)
    local ladderScroll = CreateFrame("ScrollFrame", nil, ladder)
    ladderScroll:SetPoint("TOPLEFT", 16, -LADDER_TOP)
    ladderScroll:SetPoint("BOTTOMRIGHT", -16, 8)
    local ladderBody = CreateFrame("Frame", nil, ladderScroll)
    ladderBody:SetSize(INNER, 1)
    ladderScroll:SetScrollChild(ladderBody)
    ladderScroll:EnableMouseWheel(true)
    ladderScroll:SetScript("OnMouseWheel", LadderWheel)
    local ladderViewport = VIEWPORT - LADDER_TOP - 8
    local ladderEmpty = UI.Label(ladderBody, "No visible accounts.", 0, LADDER_FIRST, INNER, 11, MUTED)

    -- Right column: Prestige panels in a normal scroll frame.
    local scroll, body = UI.Scroll(page, "AshoholicProgressionScroll", HALF_PANEL_WIDTH + PANEL_GAP, 57,
        HALF_PANEL_WIDTH + UI.SCROLLBAR_WIDTH, VIEWPORT)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", UI.ScrollBy)
    UI.Label(page, "Informational only. Open Ebonhold's Prestige panel for a fresh server snapshot.",
        0, PAGE_HEIGHT - 9, CONTENT_WIDTH, 10, MUTED)

    local rows, panels = {}, {}

    page.Refresh = function()
        local rules = UI.model.rules
        -- Without the rules the ladder size is unknown, so no pips are shown.
        local pipCount = rules and (rules.tormentLadderTop - 1) or 0
        local count = 0
        for _, account in ipairs(UI.model.accounts) do
            if account.visible then
                count = count + 1
                local row = rows[count]
                if not row then
                    row = NewLadderRow(ladderBody)
                    rows[count] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(LADDER_FIRST + (count - 1) * LADDER_STEP))
                row:Show()
                FillLadderRow(row, account, rules, pipCount)

                local panel = panels[count]
                if not panel then
                    panel = NewPrestigePanel(body)
                    panels[count] = panel
                end
                panel:ClearAllPoints()
                panel:SetPoint("TOPLEFT", 0, -((count - 1) * PRESTIGE_STEP))
                panel:Show()
                FillPrestigePanel(panel, account, rules)
            end
        end
        -- Hide what is no longer needed and forget its account.
        for index = count + 1, #rows do
            rows[index]:Hide()
            rows[index].account = nil
            panels[index]:Hide()
            panels[index].account = nil
        end
        UI.SetVisible(ladderEmpty, count == 0)

        local ladderHeight = count > 0 and LADDER_FIRST + (count - 1) * LADDER_STEP + ROW_HEIGHT or 0
        ladderBody:SetHeight(math.max(1, ladderHeight))
        ladderScroll:UpdateScrollChildRect()
        local maximum = math.max(0, ladderHeight - ladderViewport)
        if ladderScroll:GetVerticalScroll() > maximum then
            ladderScroll:SetVerticalScroll(maximum)
        end
        ladderTitle:SetText(maximum > 0 and (LADDER_TITLE .. UI.DIM .. "  /  scroll for more|r") or LADDER_TITLE)

        local prestigeHeight = count > 0 and (count - 1) * PRESTIGE_STEP + PRESTIGE_HEIGHT or 0
        body:SetHeight(math.max(VIEWPORT, prestigeHeight))
        UI.ClampScroll(scroll, prestigeHeight, VIEWPORT)
    end

    return page
end

UI.pageBuilders.Progression = BuildProgression
