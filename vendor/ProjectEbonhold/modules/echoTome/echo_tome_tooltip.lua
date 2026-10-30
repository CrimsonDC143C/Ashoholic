local addonName, addon = ...

-- Echo Tome item tooltips
--
-- Tome items teach the spell that unlocks a tome echo. The three IDs are
-- linked by convention:
--     tomeItemId == requiredSpellId == echoSpellId + 100000
-- So from a hovered item we compute echoSpellId = itemId - 100000, and if that
-- echo exists in the perk database (and is tome-gated), we append the echo it
-- unlocks to the item tooltip: name, computed description, learned state.

local ID_OFFSET = 100000

local qualityColors = {
    [0] = { r = 1.0, g = 1.0, b = 1.0 }, -- Common
    [1] = { r = 0.1, g = 1.0, b = 0.1 }, -- Uncommon
    [2] = { r = 0.0, g = 0.4, b = 1.0 }, -- Rare
    [3] = { r = 0.8, g = 0.4, b = 1.0 }, -- Epic
    [4] = { r = 1.0, g = 0.5, b = 0.0 }, -- Legendary
}

local function GetEchoForItem(itemId)
    if not itemId then return nil end
    local echoId = itemId - ID_OFFSET
    if echoId <= 0 then return nil end
    local data = ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[echoId]
    if not data then return nil end
    -- Only real tome echoes: the item must be their unlock spell
    if not data.requiredSpell or data.requiredSpell == 0 then return nil end
    return echoId, data
end

local function AddEchoLines(tooltip)
    if not (tooltip and tooltip.GetItem) then return end
    local _, link = tooltip:GetItem()
    if not link then return end
    local itemId = tonumber(link:match("item:(%d+)"))
    local echoId, data = GetEchoForItem(itemId)
    if not echoId then return end

    local echoName = GetSpellInfo(echoId) or ("Spell " .. echoId)
    local qc = qualityColors[data.quality or 0] or qualityColors[0]

    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(
        "Unlocks Echo:",
        string.format("|cff%02x%02x%02x%s|r",
            math.floor(qc.r * 255), math.floor(qc.g * 255), math.floor(qc.b * 255),
            echoName),
        1, 0.82, 0)

    -- Embed the echo spell's full description, with stat formulas computed
    -- from the player's current stats (white, no truncation)
    if utils and utils.GetSpellDescription then
        local desc = utils.GetSpellDescription(echoId, 4000, 1)
        if desc and desc ~= "" and desc ~= "Click for details" then
            tooltip:AddLine(desc, 1, 1, 1, true)
        end
    end

    -- "Learned" = the echo is unlocked in the character's discovery list
    -- (same source as the journal's tome state)
    local svc = ProjectEbonhold.PerkService
    local discovered = svc and svc.GetDiscoveredEchoes and svc.GetDiscoveredEchoes() or {}
    if discovered[echoId] then
        tooltip:AddLine("Already learned", 0.1, 1, 0.1)
    else
        tooltip:AddLine("Use to add this echo to your collection", 0.6, 0.6, 0.6)
    end

    tooltip:Show() -- resize to fit the appended lines
end

GameTooltip:HookScript("OnTooltipSetItem", AddEchoLines)
ItemRefTooltip:HookScript("OnTooltipSetItem", AddEchoLines)

-- ── Tome use detection ───────────────────────────────────────────────────────
-- Using a tome item from the bags: optimistically mark its echo as discovered
-- and show the journal alert bubble. No server signal needed - the next
-- SEND_ECHO_DISCOVERY sync remains the source of truth either way.

-- UseContainerItem also fires when the click routes the item somewhere else:
-- selling to a merchant, depositing into the bank / ext bank, attaching to a
-- mail, adding to a trade or auction, or feeding it to a targeting spell.
-- None of those learn the tome, so the click must count as a plain "use".
local REDIRECT_FRAMES = {
    "MerchantFrame", "BankFrame", "MailFrame",
    "TradeFrame", "AuctionFrame", "ExtBankFrame",
}
local function ClickWasRedirected()
    if SpellIsTargeting() or CursorHasItem() then return true end
    for _, name in ipairs(REDIRECT_FRAMES) do
        local f = _G[name]
        if f and f:IsShown() then return true end
    end
    return false
end

hooksecurefunc("UseContainerItem", function(bag, slot)
    if ClickWasRedirected() then return end
    local link = GetContainerItemLink(bag, slot)
    local itemId = link and tonumber(link:match("item:(%d+)"))
    local echoId = GetEchoForItem(itemId)
    if not echoId then return end

    local svc = ProjectEbonhold.PerkService
    if not (svc and svc.AddDiscoveredEcho) then return end
    if svc.AddDiscoveredEcho(echoId) then
        if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.NotifyTomeLearned then
            ProjectEbonhold.EchoJournal.NotifyTomeLearned(echoId)
        end
    end
end)
