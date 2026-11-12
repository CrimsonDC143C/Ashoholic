-- The approved preview's parked-run panel, fed only by Data.GetRoster copies.
-- Each row carries the age of its own source, not the character's last login.
local addonName = ...
local UI = _G[addonName].UI
local Style = UI.Style

local DETAIL_ROWS = {
    { key = "ash", title = "Run Soul Ash" },
    { key = "shards", title = "Run Soul Shards" },
    { key = "bonus", title = "Offering bonus" },
    { key = "offerings", title = "Offerings remaining" },
    { key = "echoBuild", title = "Echo build" },
    { key = "anchor", title = "Soul anchor" },
    { key = "currentTier", title = "Selected Torment" },
    { key = "unlockedTier", title = "Highest access" },
}

function UI.CreateCharacterDetails(parent, width)
    local panel = UI.CreateSurface(parent, width, 1)
    panel:SetPoint("TOPRIGHT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.title = UI.AddLabel(panel, "", 16, -14, width - 32, 24, 16, Style.text)
    panel.location = UI.AddLabel(panel, "", 16, -41, width - 32, 34, 10, Style.muted)
    UI.AddLabel(panel, "PARKED RUN", 16, -81, width - 32, 16, 10, Style.gold)
    panel.rows = {}
    for index, definition in ipairs(DETAIL_ROWS) do
        local row = UI.CreateDetailLine(panel, definition.title, 16, -103 - (index - 1) * 32, width - 32)
        UI.AttachTooltip(row)
        panel.rows[definition.key] = row
    end

    local note = UI.AddLabel(panel, "Saved snapshots. Hover a row for its source and update time.", 16, 0, width - 32, 38, 10, Style.muted)
    note:ClearAllPoints()
    note:SetPoint("BOTTOMLEFT", 16, 12)
    return panel
end

local function SetDetail(panel, key, value, updatedAt, explanation)
    local row = panel.rows[key]
    row.value:SetText(value)
    local lines = {}
    UI.AddTooltipLine(lines, value)
    UI.AddTooltipLine(lines, "Updated", UI.FormatLastSeen(updatedAt), Style.muted)
    UI.AddTooltipLine(lines, " ")
    UI.AddTooltipLine(lines, explanation, nil, Style.muted)
    UI.RefreshTooltip(row, row.label:GetText(), lines)
end

function UI.RefreshCharacterDetails(panel, character, rules)
    if not character then
        panel.title:SetText("No saved character")
        panel.location:SetText("Log in to a character to collect a snapshot.")
        for _, definition in ipairs(DETAIL_ROWS) do
            SetDetail(panel, definition.key, "Unknown", nil, "No character snapshot has been collected.")
        end
        return
    end

    panel.title:SetText(character.name)
    panel.location:SetText(
        character.realm .. " / " .. (character.location or "Unknown")
            .. "\nLevel " .. UI.FormatNumber(character.level) .. " | " .. UI.FormatCopper(character.gold)
    )
    SetDetail(panel, "ash", UI.FormatNumber(character.runAsh), character.runUpdatedAt,
        "Current run only; not part of the account's banked balance.")
    SetDetail(panel, "shards", UI.FormatNumber(character.runShards), character.runUpdatedAt,
        "Current run only; not part of the account's banked balance.")

    local contracts = character.contracts
    local bonus, remaining, anchor = "Unknown", "Unknown", "Unknown"
    if contracts then
        local value = contracts.offeringBonusPct
        bonus = "+" .. (value == math.floor(value) and UI.FormatNumber(value) or string.format("%.1f", value)) .. "%"
        remaining = UI.FormatNumber(math.max(0, contracts.offeringsMax - contracts.offeringsUsed))
            .. " / " .. UI.FormatNumber(contracts.offeringsMax)
        if contracts.anchorState == 0 then
            anchor = "None"
        elseif contracts.anchorPlace ~= "" then
            anchor = contracts.anchorPlace
        else
            anchor = "Set (place unknown)"
        end
    end
    local contractsUpdatedAt = contracts and contracts.updatedAt
    SetDetail(panel, "bonus", bonus, contractsUpdatedAt,
        "Offering bonus reported by Spirit Healer contracts. Open the Spirit Healer window to compare.")
    SetDetail(panel, "offerings", remaining, contractsUpdatedAt,
        "Remaining / allowed offerings for this run, not a weekly allowance.")
    SetDetail(panel, "anchor", anchor, contractsUpdatedAt,
        "The saved Soul Anchor location. The healer's 'here/elsewhere' state is not your current position.")

    local build = character.echoBuild
    local buildName = "Unknown"
    if build then
        if not build.enabled then
            buildName = "Unavailable"
        elseif build.name ~= "" then
            buildName = build.name
        else
            buildName = "Loadout " .. build.slot
        end
    end
    SetDetail(panel, "echoBuild", buildName, build and build.updatedAt,
        "The active live Echo loadout, not the highlighted wishlist. Unnamed slots use their slot number.")

    local torment = character.torment
    SetDetail(panel, "currentTier", UI.TierName(torment and torment.currentTier, rules),
        torment and torment.updatedAt, "This character's selected difficulty, not a party leader's instance difficulty.")
    SetDetail(panel, "unlockedTier", UI.TierName(torment and torment.highestUnlocked, rules),
        torment and torment.updatedAt, "Highest access observed on this character. Tiers above "
            .. UI.TierName(rules.tormentLadderTop, rules)
            .. " are instance-only. The Progression tab shows each actual ladder unlock.")
end
