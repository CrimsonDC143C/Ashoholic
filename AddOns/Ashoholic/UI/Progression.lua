-- The preview's two-column Torment / Prestige view with real snapshots.
-- Torment rows belong to characters; Prestige panels belong to accounts.
local addonName = ...
local UI = _G[addonName].UI
local Style = UI.Style
local PANEL_GAP = 20
local TORMENT_ROW_HEIGHT = 88
local PRESTIGE_PANEL_HEIGHT = 234
local UNLOCKED_COLOR = { 0.16, 0.36, 0.31, 1 }

function UI.CreateProgressionPage(parent, width, rules)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    UI.AddLabel(page, "Torment & Prestige", 0, 0, width, 24, 16, Style.text)
    UI.AddLabel(page, "Torment access is per character. Prestige is shared by the account.", 0, -27, width, 18, 11, Style.muted)

    local halfWidth = (width - PANEL_GAP) / 2
    local ladder = UI.CreateSurface(page, halfWidth, 1)
    ladder:SetPoint("TOPLEFT", 0, -57)
    ladder:SetPoint("BOTTOMLEFT", 0, 0)
    UI.AddLabel(ladder, "CHARACTER TORMENT UNLOCKS", 16, -13, halfWidth - 32, 20, 11, Style.gold)
    page.ladderScroll, page.ladderBody = UI.CreateScroll(ladder, nil, halfWidth - 32)
    page.ladderScroll:SetPoint("TOPLEFT", 16, -42)
    page.ladderScroll:SetPoint("BOTTOMRIGHT", -16, 12)

    page.prestigeScroll, page.prestigeBody = UI.CreateScroll(page, nil, halfWidth)
    page.prestigeScroll:SetPoint("TOPLEFT", halfWidth + PANEL_GAP, -57)
    page.prestigeScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    page.headingPool = {}
    page.characterPool = {}
    page.prestigePool = {}
    page.halfWidth = halfWidth
    page.ladderTop = rules.tormentLadderTop
    return page
end

local function CreateTormentRow(parent, width, ladderTop)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, TORMENT_ROW_HEIGHT)
    row.name = UI.AddLabel(row, "", 0, 0, width, 18, 12, Style.text)
    row.state = UI.AddLabel(row, "", 0, -19, width, 16, 10, Style.muted)
    row.updated = UI.AddLabel(row, "", 0, -64, width, 14, 9, Style.muted)
    row.pips = {}
    local count = ladderTop - 1 -- tier 1 is Normal, not Torment I
    local pipWidth = (width - (count - 1) * 6) / count
    for tier = 2, ladderTop do
        local pip = UI.CreateSurface(row, pipWidth, 18)
        pip:SetPoint("TOPLEFT", (tier - 2) * (pipWidth + 6), -40)
        pip.label = UI.AddLabel(pip, tostring(tier - 1), 0, 0, pipWidth, 18, 10, Style.text)
        pip.label:SetJustifyH("CENTER")
        UI.AttachTooltip(pip)
        row.pips[tier] = pip
    end
    return row
end

local function RefreshTormentRow(row, character, rules)
    local torment = character.torment
    row.name:SetText(character.name .. "  /  " .. character.realm)
    row.state:SetText(
        "Selected: " .. UI.TierName(torment and torment.currentTier, rules)
            .. "  |  Highest access: " .. UI.TierName(torment and torment.highestUnlocked, rules)
    )
    row.updated:SetText("Updated: " .. UI.FormatLastSeen(torment and torment.updatedAt))
    for tier, pip in pairs(row.pips) do
        local unlocked = torment and torment.unlockedTiers[tier]
        pip:SetBackdropColor(unpack(unlocked and UNLOCKED_COLOR or Style.row))
        pip.label:SetText(torment and tostring(tier - 1) or "?")
        pip.label:SetTextColor(unpack(unlocked and Style.teal or Style.muted))
        local lines = {}
        local state = "Unknown - log in to this character to collect its unlocks."
        if torment then
            state = unlocked and "Unlocked on this character." or "Locked on this character."
        end
        UI.AddTooltipLine(lines, state)
        UI.AddTooltipLine(lines, "Updated", UI.FormatLastSeen(torment and torment.updatedAt), Style.muted)
        UI.RefreshTooltip(pip, UI.TierName(tier, rules), lines)
    end
end

local function CreatePrestigePanel(parent, width)
    local panel = UI.CreateSurface(parent, width, PRESTIGE_PANEL_HEIGHT)
    panel.title = UI.AddLabel(panel, "", 16, -13, width - 32, 22, 14, Style.gold)
    panel.state = UI.AddLabel(panel, "", 16, -43, width - 32, 22, 13, Style.text)
    panel.gate = UI.CreateDetailLine(panel, "Committed Ash / gate", 16, -77, width - 32)
    panel.shards = UI.CreateDetailLine(panel, "Shards reported for Prestige", 16, -106, width - 32)
    panel.essence = UI.CreateDetailLine(panel, "Next Prestige / Essence", 16, -135, width - 32)
    panel.updated = UI.AddLabel(panel, "", 16, -171, width - 32, 18, 10, Style.muted)
    UI.AddLabel(panel, "Informational only. Open Ebonhold's Prestige panel for a fresh server snapshot.",
        16, -196, width - 32, 28, 10, Style.muted)
    return panel
end

local function RefreshPrestigePanel(panel, account, rules)
    local prestige = account.prestige
    panel.title:SetText((account.name or "Unknown account") .. "  /  Prestige " .. UI.FormatNumber(prestige and prestige.count))
    local status, color = "Not received from Ebonhold yet.", Style.muted
    if prestige then
        if prestige.gateProgress < rules.prestigeGate then
            status, color = "Ash requirement not met", Style.gold
        elseif prestige.pendingEssence == nil then
            status = "Shard requirement unknown"
        elseif prestige.pendingEssence == 0 then
            status, color = "Shard requirement not met", Style.gold
        else
            status, color = "Currency requirements met", Style.teal
        end
    end
    panel.state:SetText(status)
    panel.state:SetTextColor(unpack(color))
    panel.gate.value:SetText(UI.FormatNumber(prestige and prestige.gateProgress) .. " / " .. UI.FormatNumber(rules.prestigeGate))
    panel.shards.value:SetText(UI.FormatNumber(prestige and prestige.pendingShards))
    local essence = prestige and prestige.pendingEssence
    panel.essence.value:SetText(essence ~= nil and ("+" .. UI.FormatNumber(essence) .. " Essence") or "Unknown")
    panel.updated:SetText("Updated: " .. UI.FormatLastSeen(prestige and prestige.updatedAt))
end

function UI.RefreshProgression(page, roster, rules)
    local y, characterIndex, prestigeY = 0, 0, 0
    for accountIndex, account in ipairs(roster) do
        local highest, known = nil, 0
        for _, character in ipairs(account.characters) do
            if character.torment then
                known = known + 1
                local tier = character.torment.highestUnlocked
                if tier and (not highest or tier > highest) then
                    highest = tier
                end
            end
        end
        local heading = page.headingPool[accountIndex]
        if not heading then
            heading = UI.AddLabel(page.ladderBody, "", 0, 0, page.halfWidth - 32, 40, 11, Style.gold)
            page.headingPool[accountIndex] = heading
        end
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", 0, -y)
        heading:SetText((account.name or "Unknown account") .. "\nHighest saved: " .. UI.TierName(highest, rules)
            .. "  (" .. known .. "/" .. #account.characters .. " characters known)")
        heading:Show()
        y = y + 46

        for _, character in ipairs(account.characters) do
            characterIndex = characterIndex + 1
            local row = page.characterPool[characterIndex]
            if not row then
                row = CreateTormentRow(page.ladderBody, page.halfWidth - 32, page.ladderTop)
                page.characterPool[characterIndex] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:Show()
            RefreshTormentRow(row, character, rules)
            y = y + TORMENT_ROW_HEIGHT
        end
        y = y + 8

        local panel = page.prestigePool[accountIndex]
        if not panel then
            panel = CreatePrestigePanel(page.prestigeBody, page.halfWidth)
            page.prestigePool[accountIndex] = panel
        end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", 0, -prestigeY)
        RefreshPrestigePanel(panel, account, rules)
        panel:Show()
        prestigeY = prestigeY + PRESTIGE_PANEL_HEIGHT + 16
    end
    -- Keep reused rows visible so a hovered tier's tooltip can update in place.
    -- Only widgets no longer needed by the read model should be hidden.
    for index = #roster + 1, #page.headingPool do
        page.headingPool[index]:Hide()
        page.prestigePool[index]:Hide()
    end
    for index = characterIndex + 1, #page.characterPool do
        page.characterPool[index]:Hide()
    end
    UI.UpdateScrollHeight(page.ladderScroll, y)
    UI.UpdateScrollHeight(page.prestigeScroll, math.max(0, prestigeY - 16))
end
