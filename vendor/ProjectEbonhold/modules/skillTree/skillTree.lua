local addon, Addon = ...


local COLOR_GRAY = { 0.45, 0.45, 0.45 }
local COLOR_GREEN = { 0.10, 1.00, 0.10 }
local COLOR_ORANGE = { 1.00, 0.70, 0.20 }


local isWaitingForValidation = false
local applyButton = nil
local isGlowEnabled = true
local COLOR_APEX = { 1.00, 0.20, 1.00 }


local DebugPrint = function() end -- skillTree_Debug.DebugPrint


-- A handful of nodes are flagged permanent = true in TalentDatabase (see CreateNodes).
-- Explain the rule once, the first time the player tries to take one of those nodes, instead
-- of popping a per-node confirmation dialog every time. Asked BEFORE the rank is taken
-- (2026-10-22: shown after, it explained a choice already made): onConfirm runs only on
-- Confirm, and only a Confirm burns the flag, so a Cancel asks again next time.
local function ConfirmPermanentNode(onConfirm)
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    if ProjectEbonholdDB.seenPermanentNodeIntro then
        onConfirm()
        return
    end

    StaticPopupDialogs["SKILLTREE_PERMANENT_INTRO"] = StaticPopupDialogs["SKILLTREE_PERMANENT_INTRO"] or {
        text = "|cffFFD700Permanent node|r\n\n" ..
            "Every rank you apply in the Skill Tree is |cffFF0000permanent|r: it can never be unlearned or refunded. A |cffFF4444Prestige|r is the only thing that clears the tree, and it wipes almost all of it.\n\n" ..
            "The node you are about to take wears an |cffFFD700octagon|r frame: it is one of the few that SURVIVE a Prestige, keeping its ranks for free forever.\n\n" ..
            "Choose those points carefully!",
        button1 = "Confirm",
        button2 = CANCEL,
        OnAccept = function(self, data)
            ProjectEbonholdDB = ProjectEbonholdDB or {}
            ProjectEbonholdDB.seenPermanentNodeIntro = true
            if data then data() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
    }
    local popup = StaticPopup_Show("SKILLTREE_PERMANENT_INTRO", nil, nil, onConfirm)
    if popup then
        popup:SetFrameStrata("TOOLTIP")
    end
end


local VIEW_W, VIEW_H = 900, 600



local TALENT_POINTS_TOTAL = 0
local TALENT_POINT_TOTAL_BASE = 0
local FormatThousands -- defined further down, needed by the currency helpers below

-- The three other currencies (skill tree rework, 2026-09). The ashes keep their two
-- variables above; these hold "spendable" (banked minus what the selected build commits)
-- and "banked" for shards, essence and artisan souls. Fed by the server, never derived.
local CURRENCY_POOLS = {
    shard   = { spendable = 0, banked = 0 },
    essence = { spendable = 0, banked = 0 },
    artisan = { spendable = 0, banked = 0 },
}
-- Display data per currency. The tooltip keeps ONE colour for every cost line (green when
-- affordable, red otherwise); only the icon and the name change with the currency.
local CURRENCY_INFO = {
    ash     = { name = "Soul Ashes",   icon = "Interface\\Icons\\inv_soulash" },
    shard   = { name = "Soul Shards",  icon = "Interface\\Icons\\inv_10_jewelcrafting3_soulcage_frost" },
    essence = { name = "Soul Essence", icon = "Interface\\Icons\\inv_misc_supersoulash" },
    artisan = { name = "Artisan Soul", icon = "Interface\\Icons\\ability_argus_soulbombdebufflarge" },
}
local CURRENCY_ORDER = { "ash", "shard", "essence", "artisan" }
-- What each currency buys and where it comes from, for the bar's tooltip. Shared with the
-- Call Board's reward tooltips (ProjectEbonhold.CurrencyHelp) so both say the same thing.
local CURRENCY_HELP = {
    ash     = { buys = "The currency of the Soul Ash Tree: every ordinary node, the flat stats, the mechanics and the infinite wells.",
                earn = "Every point of experience you gain during a run turns into Soul Ashes. When the run ends, they are banked on your account for good." },
    shard   = { buys = "The Milestones of the tree: the percentage bonuses on the stats of your gear.",
                earn = "Paid when every boss of a dungeon or raid in your bracket is dead, by dungeon champions in Torment, and by some Hero's Call Board contracts. Like Soul Ashes, they accumulate during the run and are banked at an offering or when it ends. Consumed by a Prestige." },
    essence = { buys = "The Prestige sector of the tree: talents, echoes, resurrections, experience.",
                earn = "Minted when you Prestige: 50 Soul Shards consumed become 1 Soul Essence on your first Prestige, 50 Shards more each time, up to 750. Your first Prestige mints at most 50, the next 100, up to 750 on the 15th, then no limit; Shards above the limit stay banked. Never reset." },
    artisan = { buys = "The Professions sector of the tree: gathering, crafting and the Torment recipes.",
                earn = "Earned at the Hero's Call Board: every crafting contract you claim pays one. Never reset." },
}
ProjectEbonhold.CurrencyHelp = CURRENCY_HELP
local function getNodeCurrency(btn)
    return (btn and btn.currency) or "ash"
end
local function currencyIcon(currency)
    return "|T" .. (CURRENCY_INFO[currency] or CURRENCY_INFO.ash).icon .. ":16|t"
end
local function currencyName(currency)
    return (CURRENCY_INFO[currency] or CURRENCY_INFO.ash).name
end
-- Spendable amount of one currency; the ashes route to TALENT_POINTS_TOTAL.
local function poolGet(currency)
    if currency == "ash" or not CURRENCY_POOLS[currency] then return TALENT_POINTS_TOTAL end
    return CURRENCY_POOLS[currency].spendable
end
local function poolAdd(currency, delta)
    if currency == "ash" or not CURRENCY_POOLS[currency] then
        TALENT_POINTS_TOTAL = TALENT_POINTS_TOTAL + delta
    else
        CURRENCY_POOLS[currency].spendable = CURRENCY_POOLS[currency].spendable + delta
    end
end
-- Soul Ashes held by class-constellation nodes selected but not applied yet: a server pool
-- packet overwrites the pool, so it has to be taken off again (skillTree_classes.lua).
local function pendingClassCost()
    local CT = ProjectEbonhold.ClassTree
    return (CT and CT.PendingCost and CT.PendingCost()) or 0
end
-- The most overspent currency, as a negative number (0 when every pool is fine): what the
-- Apply button and its glow really need to know.
-- (defined after currencyIcon / poolGet: a local referenced before its declaration
-- silently resolves to a nil global, which is why this tooltip never showed.)
-- Tooltip of ONE currency (each column of the bar has its own): what it buys, how
-- it is earned, spendable / banked.
local function showPoolTooltip(owner, c)
    local info, help = CURRENCY_INFO[c], CURRENCY_HELP[c]
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(currencyIcon(c) .. " " .. info.name, 1, 0.82, 0)
    GameTooltip:AddLine(help.earn, 0.6, 0.85, 0.6, true)
    GameTooltip:Show()
end
local OTHER_CURRENCIES = { "shard", "essence", "artisan" }
local function worstRemaining()
    local worst = TALENT_POINTS_TOTAL
    for _, c in ipairs(OTHER_CURRENCIES) do
        if CURRENCY_POOLS[c].spendable < worst then worst = CURRENCY_POOLS[c].spendable end
    end
    return worst
end
-- One bar for the four pools, icons included.
-- One column per currency at a FIXED position: each column reserves the width of
-- its largest plausible amount, then POOL_GAP pixels before the next one, so an
-- amount growing or shrinking never shifts the columns next to it.
local POOL_GAP = 75
local POOL_COLUMN_W = { ash = 130, shard = 90, essence = 90, artisan = 90 }
local function poolText(c)
    return currencyIcon(c) .. " |cffFFFFFF" .. FormatThousands(poolGet(c)) .. "|r"
end
local function refreshPoolsBar()
    -- skillTreeFrame is declared further down; the named frame is reached through _G here
    local f = _G.skillTreeFrame
    if not f or not f.poolTexts then return end
    for i, c in ipairs(CURRENCY_ORDER) do
        f.poolTexts[i]:SetText(poolText(c))
    end
end


local savedLoadouts = {}
local currentLoadoutName = ""


local hasUnsavedChanges = false


local lastValidatedState = {}
local revertBtn = nil

-- Ranks the SERVER has already confirmed for a node (0 when none). Once a rank
-- is applied it can NEVER be unlearned or refunded: only the ranks added since
-- the last Apply can still be taken back, and only a Prestige clears what was
-- validated. The server enforces the same floor (SkillTreeHandler::
-- UpdateCurrentLoadout), this is the UI side of it.
local function getValidatedRank(nodeId)
    if not lastValidatedState or not lastValidatedState.nodeRanks then return 0 end
    return lastValidatedState.nodeRanks[nodeId] or 0
end




local validateBtn = nil


local nodesById = {}
local treeSearchBox = nil
local lines = {}
local neighbors = {}

-- Search highlight: dimming the non-matches is not enough to spot a hit on a
-- dense tree, so every match also gets a rotating halo built lazily on the node
local SEARCH_GLOW_COLOR = { 1, 0.82, 0.25 }

local function ensureSearchGlow(btn)
    if btn.searchGlow then return btn.searchGlow end

    -- Own frame above the node border so the halo is never drawn under it
    local glow = CreateFrame("Frame", nil, btn)
    glow:SetAllPoints(btn)
    glow:SetFrameLevel(btn:GetFrameLevel() + 3)
    glow:Hide()

    -- Stored size, not GetWidth: the node may be culled (hidden), and reading the
    -- geometry of a hidden frame wakes its layout up again (see the culling below)
    local w, h = btn._size or btn:GetWidth(), btn._size or btn:GetHeight()

    local halo = glow:CreateTexture(nil, "OVERLAY")
    halo:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\texture_glow")
    halo:SetBlendMode("ADD")
    halo:SetVertexColor(unpack(SEARCH_GLOW_COLOR))
    halo:SetSize(w * 2.4, h * 2.4)
    halo:SetPoint("CENTER", btn, "CENTER", 0, 0)
    halo:SetAlpha(0.35)

    local swirl = glow:CreateTexture(nil, "OVERLAY")
    swirl:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\rotating_perm_texture")
    swirl:SetBlendMode("ADD")
    swirl:SetVertexColor(unpack(SEARCH_GLOW_COLOR))
    swirl:SetSize(w * 2.1, h * 2.1)
    swirl:SetPoint("CENTER", btn, "CENTER", 0, 0)

    local spin = swirl:CreateAnimationGroup()
    spin:SetLooping("REPEAT")
    local rot = spin:CreateAnimation("Rotation")
    rot:SetDegrees(-360)
    rot:SetDuration(5)
    rot:SetOrigin("CENTER", 0, 0)

    local pulse = halo:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local pulseUp = pulse:CreateAnimation("Alpha")
    pulseUp:SetChange(0.45)
    pulseUp:SetDuration(0.7)
    pulseUp:SetOrder(1)
    pulseUp:SetSmoothing("OUT")
    local pulseDown = pulse:CreateAnimation("Alpha")
    pulseDown:SetChange(-0.45)
    pulseDown:SetDuration(0.7)
    pulseDown:SetOrder(2)
    pulseDown:SetSmoothing("IN")

    glow.spin = spin
    glow.pulse = pulse
    btn.searchGlow = glow
    return glow
end

local function setSearchGlowShown(btn, shown)
    if shown then
        local glow = ensureSearchGlow(btn)
        glow:Show()
        glow.spin:Play()
        glow.pulse:Play()
    elseif btn.searchGlow then
        btn.searchGlow.spin:Stop()
        btn.searchGlow.pulse:Stop()
        btn.searchGlow:Hide()
    end
end

-- Lower-cased names of every spell of a node, one per line, built on the first search:
-- each keystroke used to call GetSpellInfo for every rank of every node (~17 000 calls).
local function nodeSearchText(btn)
    if btn._searchText then return btn._searchText end
    local parts, complete = {}, true
    for _, spellId in ipairs(btn.spells or {}) do
        local name = GetSpellInfo(spellId)
        if name then parts[#parts + 1] = string.lower(name) else complete = false end
    end
    local text = table.concat(parts, "\n")
    if complete then btn._searchText = text end
    return text
end

local function FilterTreeNodes(searchText)
    local lowerSearch = string.lower(searchText or "")
    local isEmpty = (lowerSearch == "")
    for _, btn in pairs(nodesById) do
        if isEmpty then
            btn:SetAlpha(1.0)
            setSearchGlowShown(btn, false)
        else
            local matches = string.find(nodeSearchText(btn), lowerSearch, 1, true) ~= nil
            btn:SetAlpha(matches and 1.0 or 0.15)
            setSearchGlowShown(btn, matches)
        end
    end
end
local parentsOf = {}
local nodeChoices = {}
local nodeRanks = {}
local activeApexNodeId = nil



local function HasRealChanges()
    -- A pending class-constellation buy is a change like any pending rank.
    local CT = ProjectEbonhold.ClassTree
    if CT and CT.HasPending and CT.HasPending() then return true end

    if not lastValidatedState or not lastValidatedState.nodeRanks then
        return next(nodeRanks) ~= nil or next(nodeChoices) ~= nil
    end


    for nodeId, rank in pairs(nodeRanks) do
        if (lastValidatedState.nodeRanks[nodeId] or 0) ~= rank then
            return true
        end
    end
    for nodeId, rank in pairs(lastValidatedState.nodeRanks) do
        if (nodeRanks[nodeId] or 0) ~= rank then
            return true
        end
    end


    if lastValidatedState.nodeChoices then
        for nodeId, choice in pairs(nodeChoices) do
            if (lastValidatedState.nodeChoices[nodeId] or 0) ~= choice then
                return true
            end
        end
        for nodeId, choice in pairs(lastValidatedState.nodeChoices) do
            if (nodeChoices[nodeId] or 0) ~= choice then
                return true
            end
        end
    elseif next(nodeChoices) ~= nil then
        return true
    end

    return false
end


local function getNodeRank(nodeId) return nodeRanks[nodeId] or 0 end

-- Rank cap for infinite nodes: mirrors the server's SkillTreeNode::INFINITE_NODE_MAX_RANK
-- (std::numeric_limits<uint32>::max()). Deliberately unreachable — the only real brake on an
-- infinite node is the Soul Ash price of the next rank. This was 255 while the rank was carried
-- in the passive's uint8 aura stack amount; it is read from the loadout rank since 2026-08-26.
local INFINITE_NODE_MAX_RANK = 4294967295
-- Per-rank cost ceiling for infinite nodes (matches SkillTreeNode::INFINITE_NODE_RANK_COST_CAP)
local INFINITE_NODE_RANK_COST_CAP = 100000000

-- Max rank from a node button/definition: infinite nodes have no reachable cap, everything
-- else has one spell per rank.
local function nodeMaxRank(btn)
    if not btn or not btn.spells then return 0 end
    if btn.infinite then return INFINITE_NODE_MAX_RANK end
    return #btn.spells
end

local function getMaxRank(nodeId)
    return nodeMaxRank(nodesById[nodeId])
end


local function isNodeActive(nodeId)
    local btn = nodesById[nodeId]
    if not btn then return false end

    if btn.isMultipleChoice then
        return (nodeChoices[nodeId] or 0) ~= 0
    else
        return getNodeRank(nodeId) > 0
    end
end


local function getSpellIconSafe(spellID)
    local _, _, iconTex = GetSpellInfo(spellID)
    return iconTex or "Interface\\Icons\\INV_Misc_QuestionMark"
end


-- Infinite nodes use the same square icon style as every other node; their
-- identity comes from the golden border, the spinner and the stack badge.
-- Every node is a round medallion: the icon is cut into a circle and wrapped in the
-- gold ring (assets/class_ring.tga) tinted with its FAMILY colour (sector of the
-- builder, class colour for the constellations). Experiment of 2026-09-06.
local FAMILY_RINGS = true
-- true: every ring keeps the texture's own gold (family colours read as "locked" in
-- red/grey hues); false: ring tinted with the family colour.
local RINGS_ALL_GOLD = true
local function familyColor(btn)
    local tree = TalentDatabase and TalentDatabase[0]
    local hex
    if btn.classId then
        local hub = tree and tree.classHubs and tree.classHubs[btn.classId]
        hex = hub and hub.color
    else
        hex = tree and tree.sectorColors and btn.sector and tree.sectorColors[btn.sector]
    end
    if hex then
        local r, g, b = hex:match("(%x%x)(%x%x)(%x%x)")
        if r then return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 end
    end
    return 1, 1, 1
end
local function setNodeIconTexture(btn, path)
    -- SetPortraitToTexture builds a new round texture on every call, and every refresh
    -- (each click) used to rebuild all ~1 700 of them: only a changed icon is redrawn.
    -- Every write to btn.icon goes through here, so the cache cannot go stale.
    if btn._iconPath == path then return end
    btn._iconPath = path
    if btn.infinite or FAMILY_RINGS then
        btn.icon:SetTexCoord(0, 1, 0, 1)
        SetPortraitToTexture(btn.icon, path)
    else
        btn.icon:SetTexture(path)
    end
end


local function updateNodeIcon(btn)
    if not btn or not btn.spells or not btn.icon or not btn.id then return end

    local nodeId = btn.id
    local spellID
    if btn.isMultipleChoice then
        local selectedChoice = nodeChoices[nodeId] or 1
        spellID = btn.spells[selectedChoice]
    else
        local currentRank = getNodeRank(nodeId)
        -- Clamp to the spell list: infinite nodes have one spell for every rank
        spellID = btn.spells[math.min(#btn.spells, math.max(1, currentRank))]
    end

    if spellID then
        setNodeIconTexture(btn, getSpellIconSafe(spellID))
    end
end


local function updateAllNodeVisuals()
    for _, btn in pairs(nodesById) do
        if btn.choiceButtons then
            for _, choiceBtn in ipairs(btn.choiceButtons) do
                choiceBtn:Hide()
            end
            btn.choiceButtons = {}
        end


        updateNodeIcon(btn)
    end
end


local function getNodeCost(btn, rank)
    if not btn or not btn.soulPointsCosts then return 0 end
    if btn.infinite then
        -- Must mirror the server formula exactly (SkillTreeNode::GetSoulPointsCostForRank):
        -- ceil(base * growth^(rank-1) - 1e-6), capped, min 1 — or the local budget preview
        -- desyncs from server-side validation.
        local base = math.max(btn.soulPointsCosts[1] or 1, 1)
        local cost = math.ceil(base * (btn.infiniteGrowth or 1.15) ^ (rank - 1) - 0.000001)
        if cost >= INFINITE_NODE_RANK_COST_CAP then return INFINITE_NODE_RANK_COST_CAP end
        return math.max(cost, 1)
    end
    local costs = btn.soulPointsCosts
    return costs[rank] or costs[#costs] or 0
end


-- What the ranks selected since the last Apply cost, per currency. The server's spendable
-- figures only know the applied build, so every pool packet has to take these off again:
-- a death or a loot banks ashes and sends one while unapplied ranks are on screen.
local function pendingTreeCost()
    local cost = {}
    for nodeId, rank in pairs(nodeRanks) do
        local btn = nodesById[nodeId]
        local validated = getValidatedRank(nodeId)
        if btn and rank > validated then
            local currency = getNodeCurrency(btn)
            local sum = cost[currency] or 0
            if btn.isMultipleChoice then
                sum = sum + getNodeCost(btn, 1)
            else
                for r = validated + 1, rank do sum = sum + getNodeCost(btn, r) end
            end
            cost[currency] = sum
        end
    end
    return cost
end

-- 12345678 -> "12,345,678": large Soul Ash numbers (infinite-node costs,
-- late-game balances) are unreadable without separators.
--
-- Same rule as ProjectEbonhold.FormatThousands: %.0f, never tostring() (scientific notation
-- past 14 significant digits) and never %d (truncated to 32 bits on this client).
FormatThousands = function(n)
    local s = string.format("%.0f", math.floor(tonumber(n) or 0))
    while true do
        local replaced
        s, replaced = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then break end
    end
    return s
end

local function addCostToTooltip(tooltip, label, cost, canAfford, currency)
    local costColor = canAfford and "|cff00FF00" or "|cffFF0000"
    currency = currency or "ash"
    tooltip:AddLine(costColor .. label .. currencyIcon(currency) .. " " .. FormatThousands(cost) .. " " .. currencyName(currency) .. "|r", 1, 1, 1)
end


-- Ramping gains (Endless Growth): +1 per rank for ranks 1-4, then +2, +3, ...
-- (one step every 3 ranks) capped at +20 per rank. Must mirror the server's
-- spell_skilltree_general_endless_growth::TotalForRank exactly.
local function infiniteRampTotal(rank)
    local total = 0
    for r = 1, rank do
        if r <= 4 then
            total = total + 1
        else
            total = total + math.min(20, 2 + math.floor((r - 5) / 3))
        end
    end
    return total
end


-- Infinite nodes only: spell name + description computed from the current rank
-- (rank 0 previews what the first stack grants). Replaces SetHyperlink, whose
-- static DBC text cannot scale with the rank. computedDesc/gainsPerRank come
-- from TalentDatabase.lua; %s placeholders are filled in gainsPerRank order
-- (gain.amount x rank, or the ramp total when gain.ramp is set).
-- White text, green numbers.
local function addInfiniteSpellTooltip(tooltip, btn, spellName, rank)
    tooltip:AddLine(spellName, 1, 0.82, 0)

    if not btn.computedDesc or not btn.gainsPerRank then return end

    -- gain.lin: +lin per rank, times gain.bump at every 10th rank, shown as a percentage
    -- (Endless Harvest) - mirrors SoulPointsHandler::HarvestMultiplier. gain.geo: multiplicative
    -- per rank, same bump (kept for any older data file). FormatThousands, not %d: the doubling
    -- passes the client's 32-bit %d within reach of the uncapped ranks.
    local function pctMult(gain, r)
        local bump = (gain.bump or 1) ^ math.floor(r / 10)
        if gain.lin then return (1 + gain.lin * r) * bump end
        return (gain.geo ^ r) * bump
    end
    local function pctText(gain, r)
        return "+" .. FormatThousands((pctMult(gain, r) - 1) * 100 + 0.5) .. "%"
    end
    local effRank = math.max(rank, 1)
    local values = {}
    for _, gain in ipairs(btn.gainsPerRank) do
        local value
        if gain.lin or gain.geo then value = pctText(gain, effRank)
        elseif gain.ramp then value = infiniteRampTotal(effRank)
        else value = gain.amount * effRank end
        table.insert(values, "|cff00FF00" .. value .. "|r")
    end

    tooltip:AddLine(string.format(btn.computedDesc, unpack(values)), 1, 1, 1, true)

    -- What the next stack grants — only for RAMPING gains, where it actually varies
    -- (fixed-gain nodes would just repeat their per-rank value). At rank 0 the
    -- description above already previews the first stack.
    if rank >= 1 and rank < INFINITE_NODE_MAX_RANK then
        local deltas = {}
        for _, gain in ipairs(btn.gainsPerRank) do
            if gain.lin or gain.geo then
                table.insert(deltas, "|cff00FF00" .. pctText(gain, rank + 1) .. "|r " .. (gain.label or ""))
            elseif gain.ramp then
                local delta = infiniteRampTotal(rank + 1) - infiniteRampTotal(rank)
                table.insert(deltas, "|cff00FF00+" .. delta .. "|r " .. (gain.label or ""))
            end
        end
        if #deltas > 0 then
            local sep = btn.gainsExclusive and " or " or ", "
            tooltip:AddLine("Next rank: " .. table.concat(deltas, sep), 0.8, 0.8, 0.8, true)
        end
    end
end


local function resetAllNodeRanks()
    for nodeId, _ in pairs(nodesById) do
        nodeRanks[nodeId] = 0
    end
end


local getConnectedNodes, isStartingNode



local function hasPrerequisites(nodeId)
    if isStartingNode(nodeId) then
        return true
    end


    local parents = parentsOf[nodeId]
    if not parents or #parents == 0 then
        return false
    end

    for _, parentId in ipairs(parents) do
        local parentBtn = nodesById[parentId]
        local parentRank = getNodeRank(parentId)
        local parentMaxRank = getMaxRank(parentId)


        if not parentBtn or not isNodeActive(parentId) or parentRank < parentMaxRank then
            return false
        end
    end

    return true
end

-- Everything a locked node needs before it can be learned: every unbought / unmaxed ancestor
-- (the server wants ALL prerequisites at max rank, recursively) plus the node's next rank.
-- Returns { nodes = { {id, fromRank, toRank}, ... } (parents first), cost = { [currency] = n },
-- count = number of ranks bought on the way } or nil, reason when the path cannot be bought
-- blind (a choice node or a second apex on the way).
local function computeUnlockPath(nodeId)
    local target = nodesById[nodeId]
    if not target or target.classId then return nil, "not an ash node" end
    local order, seen, cost, count = {}, {}, {}, 0
    local function add(btn, fromRank, toRank)
        local cur = getNodeCurrency(btn)
        for r = fromRank + 1, toRank do
            cost[cur] = (cost[cur] or 0) + getNodeCost(btn, r)
            count = count + 1
        end
        table.insert(order, { id = btn.id, fromRank = fromRank, toRank = toRank })
    end
    local function visit(id, depth)
        if seen[id] or depth > 200 then return true end
        seen[id] = true
        for _, parentId in ipairs(parentsOf[id] or {}) do
            local ok, why = visit(parentId, depth + 1)
            if not ok then return false, why end
        end
        local btn = nodesById[id]
        if not btn then return false, "unknown node " .. id end
        local rank, maxRank = getNodeRank(id), getMaxRank(id)
        if btn.isMultipleChoice then
            -- a choice cannot be made for the player: it has to be picked by hand first
            if not isNodeActive(id) then return false, "choose an option on the way first" end
        elseif btn.infinite then
            if rank < 1 then add(btn, 0, 1) end
        elseif rank < maxRank then
            if btn.isApex and activeApexNodeId and activeApexNodeId ~= id then
                return false, "another Apex talent is already active"
            end
            add(btn, rank, maxRank)
        end
        return true
    end
    for _, parentId in ipairs(parentsOf[nodeId] or {}) do
        local ok, why = visit(parentId, 1)
        if not ok then return nil, why end
    end
    -- the node itself: one rank, like a normal click
    if target.isMultipleChoice then return nil, "choose an option first" end
    if target.isApex and activeApexNodeId and activeApexNodeId ~= nodeId then
        return nil, "another Apex talent is already active"
    end
    add(target, getNodeRank(nodeId), getNodeRank(nodeId) + 1)
    return { nodes = order, cost = cost, count = count }
end

-- True when every currency of the path fits in its pool.
local function canAffordPath(path)
    if not path then return false end
    for cur, n in pairs(path.cost) do
        if poolGet(cur) < n then return false end
    end
    return true
end

-- Locked node tooltip: which previous node(s) still need their max rank, with the
-- (no longer shown: the "Unlock the path" line replaced it, kept for /debug use)
-- rank they are at ("Requires Essence of Might (3/5)"), like Blizzard's talent prereqs.
local function addPrereqLines(tooltip, nodeId)
    local parts = {}
    for _, parentId in ipairs(parentsOf[nodeId] or {}) do
        local parentBtn = nodesById[parentId]
        local rank, maxRank = getNodeRank(parentId), getMaxRank(parentId)
        if parentBtn and rank < maxRank then
            local name = parentBtn.spells and parentBtn.spells[1] and GetSpellInfo(parentBtn.spells[math.min(#parentBtn.spells, math.max(1, rank))]) or ("node " .. parentId)
            table.insert(parts, name .. " (" .. rank .. "/" .. maxRank .. ")")
        end
    end
    if #parts > 0 then
        tooltip:AddLine("Requires " .. table.concat(parts, ", "), 1, 0.3, 0.3)
    end
end


-- Locked node tooltip: the whole path to it, its price, and the click hint when affordable.
local function addUnlockPathLines(tooltip, nodeId)
    local path, why = computeUnlockPath(nodeId)
    if not path then
        if why then tooltip:AddLine("Path: " .. why, 0.6, 0.6, 0.6, false) end
        return
    end
    local parts = {}
    for _, cur in ipairs(CURRENCY_ORDER) do
        if path.cost[cur] then
            local ok = poolGet(cur) >= path.cost[cur]
            table.insert(parts, (ok and "|cff00FF00" or "|cffFF4040") .. FormatThousands(path.cost[cur]) .. "|r " .. currencyIcon(cur))
        end
    end
    -- no wrapping: the tooltip widens instead of breaking the price onto its own line
    tooltip:AddLine("Unlock path (" .. path.count .. (path.count > 1 and " ranks" or " rank") .. "): " .. table.concat(parts, "  "), 1, 1, 1, false)
    if canAffordPath(path) then
        tooltip:AddLine("|cff00FF00Left-click to unlock the whole path|r", 1, 1, 1, false)
    end
end

local function GetRemainingTalentPoints()
    return TALENT_POINTS_TOTAL
end


local function HasAnyTalents()
    for nodeId, rank in pairs(nodeRanks) do if rank > 0 then return true end end
    for nodeId, choice in pairs(nodeChoices) do
        if choice > 0 then return true end
    end
    return false
end


local function CopyCurrentBuildToLoadout(loadout)
    loadout.nodeRanks = {}
    loadout.nodeChoices = {}


    for nodeId, rank in pairs(nodeRanks) do
        if rank > 0 then loadout.nodeRanks[nodeId] = rank end
    end


    for nodeId, choice in pairs(nodeChoices) do
        if choice ~= 0 then loadout.nodeChoices[nodeId] = choice end
    end


    loadout.spendablePoints = TALENT_POINTS_TOTAL
end


local function UpdateGlowEffect()
    if validateBtn and validateBtn.glowTexture and hasUnsavedChanges and
        isGlowEnabled then
        local remainingPoints = worstRemaining()

        if remainingPoints >= 0 then
            validateBtn.glowTimer = validateBtn.glowTimer + 0.05
            local alpha = (math.sin(validateBtn.glowTimer * 1.5) + 1) * 0.4
            validateBtn.glowTexture:SetAlpha(alpha)
        elseif validateBtn.glowTexture:GetAlpha() > 0 then
            validateBtn.glowTexture:SetAlpha(0)
        end
    elseif validateBtn and validateBtn.glowTexture and validateBtn.glowTexture:GetAlpha() > 0 then
        -- only when it changes: this runs 20 times a second while the tree is open
        validateBtn.glowTexture:SetAlpha(0)
    end
end


local function MarkUnsavedChanges()
    if not HasRealChanges() then
        hasUnsavedChanges = false
        if validateBtn then
            validateBtn:Disable()
            validateBtn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
            if validateBtn.glowTexture then
                validateBtn.glowTexture:SetAlpha(0)
            end
        end
        DebugPrint("No real changes detected - Apply Changes disabled")
        return
    end

    hasUnsavedChanges = true

    DebugPrint("MarkUnsavedChanges called")
    DebugPrint("validateBtn exists: %s", tostring(validateBtn ~= nil))


    local remainingPoints = worstRemaining()



    if validateBtn then
        if not hasUnsavedChanges then
            validateBtn:Disable()
            validateBtn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
            if validateBtn.glowTexture then
                validateBtn.glowTexture:SetAlpha(0)
            end
            DebugPrint("validateBtn disabled - no unsaved changes")
        else
            if remainingPoints < 0 then
                validateBtn:Disable()
                validateBtn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
                if validateBtn.glowTexture then
                    validateBtn.glowTexture:SetAlpha(0)
                end
                DebugPrint("validateBtn disabled - overspent by %s",
                    FormatThousands(-remainingPoints))
            else
                validateBtn:Enable()
                validateBtn:GetFontString():SetTextColor(1, 1, 1)
                if validateBtn.glowTexture then
                    validateBtn.glowTimer = 0
                end
                DebugPrint("Enabled validateBtn (build affordable)")
            end
        end
    else
        DebugPrint("Could not enable validateBtn - element missing")
    end


    if revertBtn and lastValidatedState and lastValidatedState.nodeRanks then
        revertBtn:Enable()

        if revertBtn.icon then
            revertBtn.icon:SetDesaturated(false)
            revertBtn.icon:SetAlpha(1.0)
        end
        DebugPrint("Enabled revertBtn")
    end

    DebugPrint("Marked as needing validation")
end


local function MarkAsValidated()
    hasUnsavedChanges = false


    if validateBtn then
        validateBtn:Disable()
        validateBtn:GetFontString():SetTextColor(0.5, 0.5, 0.5)

        if validateBtn.glowTexture then
            validateBtn.glowTexture:SetAlpha(0)
        end
    end


    if revertBtn then
        revertBtn:Disable()

        if revertBtn.icon then
            revertBtn.icon:SetDesaturated(true)
            revertBtn.icon:SetAlpha(0.5)
        end
    end


    lastValidatedState = {
        nodeRanks = {},
        nodeChoices = {},
        class = currentClass
    }


    for nodeId, rank in pairs(nodeRanks) do
        lastValidatedState.nodeRanks[nodeId] = rank
    end


    for nodeId, choice in pairs(nodeChoices) do
        lastValidatedState.nodeChoices[nodeId] = choice
    end

    DebugPrint("Validated state saved with %d node ranks and %d choices",
        table.getn(lastValidatedState.nodeRanks or {}),
        table.getn(lastValidatedState.nodeChoices or {}))
end


local function RevertToValidatedState()
    if not lastValidatedState or not lastValidatedState.nodeRanks then
        DebugPrint("|cffFF0000No validated state to revert to!|r")
        return false
    end


    if lastValidatedState.class and lastValidatedState.class ~= currentClass then
        DebugPrint(
            "|cffFFFF00Warning: Validated state is for a different class!|r")
    end


    for currency, cost in pairs(pendingTreeCost()) do poolAdd(currency, cost) end

    nodeRanks = {}
    resetAllNodeRanks()
    for nodeId, rank in pairs(lastValidatedState.nodeRanks) do
        nodeRanks[nodeId] = rank
    end


    nodeChoices = {}
    for nodeId, choice in pairs(lastValidatedState.nodeChoices) do
        nodeChoices[nodeId] = choice
    end


    if ProjectEbonhold.ClassTree and ProjectEbonhold.ClassTree.RevertPending then
        ProjectEbonhold.ClassTree.RevertPending()
    end


    for _, btn in pairs(nodesById) do
        local nodeId = btn.id


        updateNodeIcon(btn)


        if btn.isMultipleChoice then
            local selectedChoice = nodeChoices[nodeId]
            if selectedChoice and selectedChoice ~= 0 then
                btn.selectedSpell = selectedChoice
            else
                btn.selectedSpell = nil
            end
        end
    end


    MarkAsValidated()


    refreshAccessibility()

    DebugPrint("|cff00FF00Reverted to last validated state!|r")
    return true
end


local TreeNodes = {}
local Links = {}
currentClass = "Mage"


local function DetectPlayerClass()
    local _, playerClass = UnitClass("player")


    local classMapping = {
        ["WARRIOR"] = "Warrior",
        ["PALADIN"] = "Paladin",
        ["HUNTER"] = "Hunter",
        ["ROGUE"] = "Rogue",
        ["PRIEST"] = "Priest",
        ["DEATHKNIGHT"] = "Death Knight",
        ["SHAMAN"] = "Shaman",
        ["MAGE"] = "Mage",
        ["WARLOCK"] = "Warlock",
        ["DRUID"] = "Druid"
    }
    local detectedClass = classMapping[playerClass] or "Mage"
    DebugPrint("Player class detected: %s (API: %s)", detectedClass,
        playerClass or "unknown")
    return detectedClass
end


nodeChoices = {}
nodeRanks = {}



function getConnectedNodes(nodeId)
    return neighbors[nodeId] or {}
end

function isStartingNode(nodeId)
    local btn = nodesById[nodeId]
    if btn then return btn.isStart == true end


    for _, node in ipairs(TreeNodes) do
        if node.id == nodeId then return node.isStart == true end
    end

    return false
end

local NextRankTooltip = nil
local CurrentRankTooltip = nil
local InfoTooltip = nil


local function SendCreateLoadoutToServer(name, nodeRanks)
    if not ProjectEbonhold or not ProjectEbonhold.sendToServer then
        DebugPrint(
            "|cffFF0000Cannot send create loadout request: ProjectEbonhold not available|r")
        return false
    end


    local nodeParts = {}
    for nodeId, rank in pairs(nodeRanks) do
        if rank > 0 then table.insert(nodeParts, nodeId .. ":" .. rank) end
    end


    local spendablePoints = TALENT_POINTS_TOTAL

    local nodesString = table.concat(nodeParts, ",")

    local dataString = name .. "," .. spendablePoints .. "," .. nodesString

    DebugPrint("|cff00FF00Sending CREATE_LOADOUT request to server...|r")
    DebugPrint("|cffFFFF00Name: " .. name .. ", Available Points: " ..
        spendablePoints .. ", Nodes: " .. #nodeParts .. "|r")

    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_CREATE_LOADOUT,
        dataString)
    return true
end


local function saveCurrentLoadout(name)
    local loadout = {
        nodeRanks = {},
        nodeChoices = {},
        id = 0,
        spendablePoints = 0,
        class = currentClass
    }


    CopyCurrentBuildToLoadout(loadout)

    savedLoadouts[name] = loadout
    currentLoadoutName = name


    SendCreateLoadoutToServer(name, loadout.nodeRanks)

    DebugPrint("|cff00FF00Loadout saved locally: " .. name .. " (" ..
        FormatThousands(TALENT_POINTS_TOTAL) .. " Soul Ashes available)|r")
end

local function loadLoadout(name, forceReload)
    if currentLoadoutName == name and not forceReload then
        DebugPrint("|cffFFFF00Loadout already loaded: " .. name .. "|r")
        return
    end

    local loadout = savedLoadouts[name]
    if not loadout then
        DebugPrint("|cffFF0000Loadout not found: " .. name .. "|r")
        return
    end

    DebugPrint("|cff00FF00Loading loadout: " .. name .. "...|r")


    nodeRanks = {}
    nodeChoices = {}


    resetAllNodeRanks()
    for nodeId, _ in pairs(nodesById) do
        nodeChoices[nodeId] = 0
    end


    if loadout.nodeRanks then
        for id, rank in pairs(loadout.nodeRanks) do nodeRanks[id] = rank end
    end


    if loadout.nodeChoices then
        for id, choice in pairs(loadout.nodeChoices) do
            nodeChoices[id] = choice
        end
    end


    updateAllNodeVisuals()

    currentLoadoutName = name
    refreshAccessibility()
    DebugPrint("|cff00FF00Loadout loaded: " .. name .. " (nodes applied)|r")
end

local function clearCurrentBuild()
    resetAllNodeRanks()


    nodeChoices = {}


    activeApexNodeId = nil


    updateAllNodeVisuals()

    currentLoadoutName = ""
    refreshAccessibility()
    MarkUnsavedChanges()
    DebugPrint("|cff00FF00All talents cleared!|r")
end

local function getLoadoutsList()
    local list = {}
    for name, _ in pairs(savedLoadouts) do table.insert(list, name) end
    table.sort(list)
    return list
end


local function CreateLoadoutPackage()
    local loadoutId = 0
    local loadoutName = currentLoadoutName or "Unnamed"

    if currentLoadoutName and currentLoadoutName ~= "" and
        savedLoadouts[currentLoadoutName] then
        loadoutId = savedLoadouts[currentLoadoutName].id or 0
    end

    local package = { id = loadoutId, name = loadoutName, nodeRanks = {} }


    DebugPrint("=== Creating Loadout Package ===")
    local totalNodes = 0
    for nodeId, rank in pairs(nodeRanks) do
        DebugPrint("Node %d: rank = %d", nodeId, rank)
        if rank > 0 then
            package.nodeRanks[nodeId] = rank
            totalNodes = totalNodes + 1
        end
    end
    DebugPrint("Total nodes with rank > 0: %d", totalNodes)

    return package
end


local function SendLoadoutToServer(loadoutData)
    DebugPrint("=== SENDING LOADOUT TO SERVER ===")
    DebugPrint("Loadout ID: %s, Name: %s", tostring(loadoutData.id),
        loadoutData.name)

    local nodeCount = 0
    for _ in pairs(loadoutData.nodeRanks) do nodeCount = nodeCount + 1 end
    DebugPrint("Total Nodes: %d", nodeCount)


    if ProjectEbonhold and ProjectEbonhold.SendLoadoutToServer then
        return ProjectEbonhold.SendLoadoutToServer(loadoutData)
    end

    return false
end




local function ExportLoadoutToCode()
    local buffer = {}


    local activeNodes = {}
    for nodeId, rank in pairs(nodeRanks) do
        if rank > 0 then
            table.insert(activeNodes, { id = nodeId, rank = rank })
        end
    end


    for nodeId, choice in pairs(nodeChoices) do
        if choice > 0 then
            local found = false
            for _, node in ipairs(activeNodes) do
                if node.id == nodeId then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(activeNodes, { id = nodeId, rank = 1 })
            end
        end
    end


    table.sort(activeNodes, function(a, b) return a.id < b.id end)


    for _, byte in ipairs(utils.EncodeVarInt(#activeNodes)) do
        table.insert(buffer, byte)
    end


    for _, node in ipairs(activeNodes) do
        for _, byte in ipairs(utils.EncodeVarInt(node.id)) do
            table.insert(buffer, byte)
        end

        table.insert(buffer, node.rank)
    end

    return utils.Base64Encode(buffer)
end


local function ImportLoadoutFromCode(encodedData)
    local buffer = utils.Base64Decode(encodedData)
    if not buffer or #buffer == 0 then return nil, "Invalid Base64 data" end

    local pos = 1


    local nodeCount
    nodeCount, pos = utils.DecodeVarInt(buffer, pos)
    if not nodeCount then return nil, "Failed to decode node count" end


    local nodes = {}
    for i = 1, nodeCount do
        local nodeId
        nodeId, pos = utils.DecodeVarInt(buffer, pos)
        if not nodeId then return nil, "Failed to decode node ID" end

        if pos > #buffer then
            return nil, "Missing rank for node " .. nodeId
        end
        local rank = buffer[pos]
        pos = pos + 1

        table.insert(nodes, { id = nodeId, rank = rank })
    end

    return nodes
end


local function ApplyImportedLoadout(nodes)
    if not nodes then return false end


    local totalPointsRequired = 0
    for _, node in ipairs(nodes) do
        local btn = nodesById[node.id]
        if btn then
            if btn.isMultipleChoice then
                totalPointsRequired = totalPointsRequired + 1
            else
                totalPointsRequired = totalPointsRequired + node.rank
            end
        end
    end


    if totalPointsRequired > TALENT_POINTS_TOTAL then
        return false,
            "You tried to import a build without enough Soul Ashes (Required: " ..
            FormatThousands(totalPointsRequired) .. ", Available: " ..
            FormatThousands(TALENT_POINTS_TOTAL) .. ")"
    end


    clearCurrentBuild()


    for _, node in ipairs(nodes) do
        local btn = nodesById[node.id]
        if btn then
            if btn.isMultipleChoice then
                nodeChoices[node.id] = 1
                nodeRanks[node.id] = 1
                btn.selectedSpell = 1
                updateNodeIcon(btn)
            else
                nodeRanks[node.id] = node.rank
            end
        end
    end


    updateAllNodeVisuals()
    refreshAccessibility()
    MarkUnsavedChanges()

    return true
end


function ValidateAndSendLoadout()
    DebugPrint("Validating current loadout...")

    -- Class constellations first: the server debits them one node at a time, so the loadout
    -- that follows is validated against the pool they leave behind - exactly the budget the
    -- player was shown while selecting.
    local CT = ProjectEbonhold.ClassTree
    local classNodesSent = (CT and CT.FlushPending and CT.FlushPending()) or 0
    if classNodesSent > 0 then
        DebugPrint("|cffFFFF00%d class node(s) sent to server|r", classNodesSent)
    end

    if not HasAnyTalents() then
        DebugPrint("|cffFF0000Validation failed: No talents selected|r")
        return classNodesSent > 0
    end


    if currentLoadoutName and savedLoadouts[currentLoadoutName] then
        local loadout = savedLoadouts[currentLoadoutName]
        CopyCurrentBuildToLoadout(loadout)
        DebugPrint("|cff00FF00Saved current state to loadout: " ..
            currentLoadoutName .. "|r")
    end


    local loadoutData = CreateLoadoutPackage()


    if SendLoadoutToServer(loadoutData) then
        DebugPrint("|cffFFFF00Loadout sent to server...|r")
        return true
    else
        DebugPrint("|cffFF0000Failed to send loadout to server|r")
        return false
    end
end

function OnApplyChangesResult(spellId, success)
    isWaitingForValidation = false

    if success then
        MarkAsValidated()
        DebugPrint("|cff00FF00Skill tree changes applied successfully!|r")
        -- DEFAULT_CHAT_FRAME:AddMessage(
        --     "|cff00FF00[ProjectEbonhold] Skill tree changes applied successfully!|r")

        if applyButton then
            applyButton:SetText("Apply Changes")


            isGlowEnabled = false
            if applyButton.glowTexture then
                applyButton.glowTexture:SetAlpha(0)
            end
        end
    else
        DebugPrint("|cffFF0000Skill tree validation failed!|r")

        if spellId then
            -- DEFAULT_CHAT_FRAME:AddMessage(
            --     "|cffFF0000[ProjectEbonhold] Skill tree validation failed for spell " ..
            --     spellId .. "!|r")
        else
            -- DEFAULT_CHAT_FRAME:AddMessage(
            --     "|cffFF0000[ProjectEbonhold] Skill tree validation failed or timed out!|r")
        end


        RevertToValidatedState()
        hasUnsavedChanges = false

        -- DEFAULT_CHAT_FRAME:AddMessage(
        --     "|cffFFFF00[ProjectEbonhold] Changes reverted to last validated state.|r")
    end
end

local function LoadClassData(className)
    local treeData = TalentDatabase[0]

    if not treeData then
        DebugPrint(
            "|cffFF0000Error: Default tree 0 not found in TalentDatabase!|r")
        return false
    end

    currentClass = className or DetectPlayerClass()
    DebugPrint("Loading default soul tree 0 for class: %s", currentClass)


    TreeNodes = {}
    Links = {}

    for i, node in ipairs(treeData.nodes) do
        TreeNodes[i] = {}
        for key, value in pairs(node) do TreeNodes[i][key] = value end
    end

    for i, link in ipairs(treeData.links) do Links[i] = { link[1], link[2] } end


    nodeRanks = {}
    for _, node in ipairs(TreeNodes) do
        nodeRanks[node.id] = 0
    end

    return true
end


LoadClassData()


-- Refreshes the loadout dropdown on the next frame (RefreshLoadoutDropdown is the
-- global defined below, resolved at call time).
local loadoutDropdownSoon = CreateFrame("Frame")
loadoutDropdownSoon:Hide()
loadoutDropdownSoon:SetScript("OnUpdate", function(self)
    self:Hide()
    RefreshLoadoutDropdown()
end)

function Addon.ApplyLoadoutsFromServer(parsedData)
    if not parsedData then
        DebugPrint("|cffFF0000Invalid loadout data received from server|r")
        return false
    end


    TALENT_POINTS_TOTAL = (parsedData.spendableSoulPoints or 0) - pendingClassCost()
    TALENT_POINT_TOTAL_BASE = parsedData.totalCommitedSoulPoints or 0
    if parsedData.pools then
        for c, v in pairs(parsedData.pools) do
            if CURRENCY_POOLS[c] then
                CURRENCY_POOLS[c].spendable = v.spendable or 0
                CURRENCY_POOLS[c].banked = v.banked or 0
            end
        end
    end

    -- Committed total exposed for the Prestige module (modules\prestige).
    -- The committed pool just changed server-side, so the prestige gate
    -- progress (committed since last prestige) is re-requested too; the
    -- reply refreshes the Prestige UI with fresh numbers.
    ProjectEbonhold.totalCommittedSoulAshes = TALENT_POINT_TOTAL_BASE
    if ProjectEbonhold.PrestigeService and ProjectEbonhold.PrestigeService.RequestPrestigeData then
        ProjectEbonhold.PrestigeService.RequestPrestigeData()
    end
    if ProjectEbonhold.PrestigeUI and ProjectEbonhold.PrestigeUI.Refresh then
        ProjectEbonhold.PrestigeUI.Refresh()
    end

    if skillTreeFrame and skillTreeFrame.progressBar and skillTreeFrame.progressBar.UpdateProgressBar then
        skillTreeFrame.progressBar.UpdateProgressBar()
    end


    savedLoadouts = {}


    for _, loadout in ipairs(parsedData.loadouts) do
        savedLoadouts[loadout.name] = {
            nodeRanks = loadout.nodeRanks,
            nodeChoices = {},
            class = currentClass,
            spendablePoints = loadout.spendablePoints,
            id = loadout.id
        }
    end


    local selectedLoadout = nil
    if parsedData.selectedLoadoutId then
        for _, loadout in ipairs(parsedData.loadouts) do
            if loadout.id == parsedData.selectedLoadoutId then
                selectedLoadout = loadout
                break
            end
        end
    end


    if not selectedLoadout then
        for _, loadout in ipairs(parsedData.loadouts) do
            if loadout.id == 0 then
                selectedLoadout = loadout
                DebugPrint("|cffFFD700Loading default loadout 0 (tree 0)|r")
                break
            end
        end
    end


    if selectedLoadout then
        resetAllNodeRanks()
        nodeChoices = {}


        for nodeId, rank in pairs(selectedLoadout.nodeRanks) do
            nodeRanks[nodeId] = rank
        end

        currentLoadoutName = selectedLoadout.name


        updateAllNodeVisuals()
    else
        resetAllNodeRanks()
        nodeChoices = {}
        currentLoadoutName = ""
    end


    MarkAsValidated()
    -- defined further down (after refreshAccessibility); resolved at call time
    ProjectEbonhold.SkillTree.RefreshTreeIfShown()


    -- next frame (one shared frame: this used to create a new one per packet)
    loadoutDropdownSoon:Show()

    DebugPrint("|cff00FF00Loadouts received from server!|r")
    DebugPrint("|cffFFFF00Total spendable points: " ..
        FormatThousands(TALENT_POINTS_TOTAL) .. "|r")
    DebugPrint("|cffFFFF00Loaded " .. #parsedData.loadouts .. " loadout(s)|r")
    if selectedLoadout then
        DebugPrint("|cff00FF00Selected loadout: " .. selectedLoadout.name ..
            "|r")
    end

    return true
end

function RefreshLoadoutDropdown()
    if not loadoutDropdown then
        DebugPrint(
            "|cffFFFF00RefreshLoadoutDropdown: dropdown not initialized yet, will update on creation|r")
        return
    end

    DebugPrint("|cff00FF00Refreshing loadout dropdown...|r")
    DebugPrint("|cffFFFF00Current loadout name: " ..
        (currentLoadoutName or "nil") .. "|r")


    if currentLoadoutName and currentLoadoutName ~= "" then
        UIDropDownMenu_SetText(loadoutDropdown, currentLoadoutName)
        DebugPrint("|cff00FF00Dropdown text set to: " .. currentLoadoutName ..
            "|r")
    else
        UIDropDownMenu_SetText(loadoutDropdown, "Select Build")
        DebugPrint("|cffFFFF00Dropdown text set to: Select Build|r")
    end
end

function Addon.ApplyLoadoutFromServer(loadoutData)
    DebugPrint(
        "|cffFFFF00Warning: Using deprecated ApplyLoadoutFromServer function|r")
    return false
end

local function CheckInitialState()
    local hasAnyTalents = false
    for nodeId, rank in pairs(nodeRanks) do
        if rank > 0 then
            hasAnyTalents = true
            break
        end
    end

    if hasAnyTalents then
        MarkUnsavedChanges()
    else
        MarkAsValidated()
    end
end




-- Created directly as a native child of CollectionsJournal's Skill Tree tab
-- (this file now loads after Blizzard_Collections.xml, so CollectionsJournal
-- already exists) rather than a standalone UIParent-anchored window that gets
-- reparented later -- same rendering primitives either way, but this avoids
-- the reparenting dance (frame-level resets, scale/position translation)
-- entirely by never being anything other than embedded.
local SKILLTREE_EXTRA_WIDTH = 200  -- 100px more on each side than the original standalone VIEW_W
local skillTreeFrame = CreateFrame("Frame", "skillTreeFrame", CollectionsJournal)
skillTreeFrame:SetSize(VIEW_W + SKILLTREE_EXTRA_WIDTH, VIEW_H)
skillTreeFrame:SetPoint("TOP", CollectionsJournal, "TOP", 0, -8)
skillTreeFrame:SetFrameStrata("HIGH")  -- matches CollectionsJournal's own strata (not FULLSCREEN_DIALOG,
                                        -- which would always render above CollectionsJournal's tab row
                                        -- regardless of frame level)


-- Set when a server push skipped the full node pass because the tree could not be
-- seen (see refreshTreeIfShown); cleared by refreshAccessibility.
local treeStale = false

local glowUpdateTimer = 0
local GLOW_UPDATE_INTERVAL = 0.05
skillTreeFrame:SetScript("OnUpdate",
    function(self, elapsed)
        if ProjectEbonhold_IsClosing then return end
        if not UIParent:IsShown() then return end
        -- OnShow already refreshes; this only catches a skipped pass if the tree
        -- became visible some other way
        if treeStale then refreshAccessibility() end
        elapsed = math.min(elapsed, 0.1) -- Cap elapsed to prevent freeze after alt-tab
        glowUpdateTimer = glowUpdateTimer + elapsed
        if glowUpdateTimer >= GLOW_UPDATE_INTERVAL then
            UpdateGlowEffect()
            glowUpdateTimer = 0
        end
    end)


-- No own background texture (CollectionsJournal's own background shows through)
-- and no SetBackdrop/close-button/UISpecialFrames registration: this frame is now
-- always a native child of CollectionsJournal's Skill Tree tab, never a
-- standalone popup, so it never needs its own border/close chrome (Collections
-- provides that once, for all 7 tabs) or an ESC-close binding of its own.

skillTreeFrame:SetScript("OnHide", function()
    if treeSearchBox then
        treeSearchBox:SetText("")
        treeSearchBox:ClearFocus()
        FilterTreeNodes("")
    end
end)


NextRankTooltip = CreateFrame("GameTooltip", "skillTreeNextRankTooltip", nil,
    "GameTooltipTemplate")
NextRankTooltip:SetOwner(skillTreeFrame, "ANCHOR_NONE")


CurrentRankTooltip = CreateFrame("GameTooltip", "skillTreeCurrentRankTooltip",
    nil, "GameTooltipTemplate")
CurrentRankTooltip:SetOwner(skillTreeFrame, "ANCHOR_NONE")


InfoTooltip = CreateFrame("GameTooltip", "skillTreeInfoTooltip", nil,
    "GameTooltipTemplate")
InfoTooltip:SetOwner(skillTreeFrame, "ANCHOR_NONE")
skillTreeFrame:EnableMouse(true)
skillTreeFrame:Hide()


loadoutDropdown = nil


local function CreateBottomBar()
    local bottomBar = CreateFrame("Frame", "skillTreeBottomBar", skillTreeFrame)
    bottomBar:SetPoint("BOTTOMLEFT", skillTreeFrame, "BOTTOMLEFT", 8, 5)
    bottomBar:SetPoint("BOTTOMRIGHT", skillTreeFrame, "BOTTOMRIGHT", -8, 5)
    bottomBar:SetHeight(35)
    bottomBar:SetFrameLevel(skillTreeFrame:GetFrameLevel() + 10)


    local bottomBarWidth = bottomBar:GetWidth() or (VIEW_W - 16)
    local textureWidth = 126 * 0.664062
    local numTextures = math.ceil(bottomBarWidth / textureWidth)


    local adjustedTextureWidth = bottomBarWidth / numTextures


    for i = 1, numTextures do
        local tex = bottomBar:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\texture_bottom")
        tex:SetTexCoord(0.000000, 0.664062, 0.000000, 0.242188)
        tex:SetSize(adjustedTextureWidth, 40)
        tex:SetPoint("LEFT", bottomBar, "LEFT", (i - 1) * adjustedTextureWidth, 0)
    end


    -- The four pools in one line, POOL_GAP apart (icon + amount), each with its own
    -- hover tooltip saying what it buys and how it is earned.
    skillTreeFrame.poolTexts = {}
    local prev
    for i, c in ipairs(CURRENCY_ORDER) do
        local hover = CreateFrame("Frame", nil, bottomBar)
        hover:SetHeight(20)
        if prev then
            hover:SetPoint("LEFT", prev, "RIGHT", POOL_GAP, 0)
        else
            hover:SetPoint("LEFT", bottomBar, "LEFT", 10, 0)
        end
        local t = hover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("LEFT", hover, "LEFT", 0, 0)
        t:SetJustifyH("LEFT")
        t:SetText(poolText(c))
        hover:SetWidth(POOL_COLUMN_W[c] or 90)
        t.hover = hover
        hover:EnableMouse(true)
        hover:SetScript("OnEnter", function(self) showPoolTooltip(self, c) end)
        hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        skillTreeFrame.poolTexts[i] = t
        prev = hover
    end
    -- Anchor for what follows the pools (dropdown, Apply button): ends with the last column
    local pointsText = CreateFrame("Frame", nil, bottomBar)
    pointsText:SetPoint("LEFT", bottomBar, "LEFT", 10, 0)
    pointsText:SetPoint("RIGHT", prev, "RIGHT", 0, 0)
    pointsText:SetHeight(20)
    skillTreeFrame.pointsText = pointsText


    local dropdown = CreateFrame("Frame", "skillTreeLoadoutDropdown", bottomBar,
        "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", pointsText, "RIGHT", 20, -2)
    UIDropDownMenu_SetWidth(dropdown, 150)
    dropdown:Hide()


    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()


        info.text = "|cff00FF00+ New Build...|r"
        info.func = function()
            StaticPopupDialogs["SKILLTREE_NEW_BUILD"] = {
                text = "Enter build name:",
                button1 = "Create",
                button2 = "Cancel",
                hasEditBox = true,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                OnAccept = function(self)
                    local name = self.editBox:GetText()
                    if name and name ~= "" then
                        saveCurrentLoadout(name)
                        UIDropDownMenu_SetText(dropdown, name)
                    end
                end,
                EditBoxOnEnterPressed = function(self)
                    local name = self:GetText()
                    if name and name ~= "" then
                        saveCurrentLoadout(name)
                        UIDropDownMenu_SetText(dropdown, name)
                    end
                    self:GetParent():Hide()
                end,
                EditBoxOnEscapePressed = function(self)
                    self:GetParent():Hide()
                end
            }
            StaticPopup_Show("SKILLTREE_NEW_BUILD")
        end
        UIDropDownMenu_AddButton(info)


        info = UIDropDownMenu_CreateInfo()
        info.text = ""
        info.disabled = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)


        local loadouts = getLoadoutsList()
        if #loadouts > 0 then
            for _, name in ipairs(loadouts) do
                info = UIDropDownMenu_CreateInfo()
                info.text = name
                info.func = function()
                    loadLoadout(name, true)
                    UIDropDownMenu_SetText(dropdown, name)
                end
                info.checked = (currentLoadoutName == name)
                UIDropDownMenu_AddButton(info)
            end
        else
            info = UIDropDownMenu_CreateInfo()
            info.text = "|cff888888No saved builds|r"
            info.disabled = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info)
        end
    end)


    if currentLoadoutName and currentLoadoutName ~= "" then
        UIDropDownMenu_SetText(dropdown, currentLoadoutName)
        DebugPrint("|cff00FF00Dropdown initialized with loadout: " ..
            currentLoadoutName .. "|r")
    else
        UIDropDownMenu_SetText(dropdown, "Select Build")
    end

    loadoutDropdown = dropdown


    -- Same red sliced button as the Prestige / Echo dialogs (utils.CreateCustomButton),
    -- glued to the search box on the right of the bar. The custom button exposes
    -- SetText/SetTextColor but no GetFontString: aliased so the existing enable /
    -- disable code keeps working unchanged.
    applyButton = utils.CreateSimpleCustomButton(bottomBar, "Apply Changes", nil, 130, 26)
    applyButton.GetFontString = function(self) return self.text end
    applyButton:SetPoint("RIGHT", treeSearchBox or pointsText, treeSearchBox and "LEFT" or "RIGHT", treeSearchBox and -20 or 22, 0)
    applyButton.__anchorToSearch = true

    -- First-spend warning (shown ONCE per account): applying commits the spent
    -- Soul Ashes for good (nothing can be unlearned afterwards), so the very
    -- first Apply asks for an explicit confirmation before proceeding.
    StaticPopupDialogs["EBONHOLD_SKILLTREE_FIRST_SPEND"] = {
        text = "You are about to spend Soul Ashes on your Skill Tree.\n\n" ..
            "This is |cffFF0000final|r: once applied, a rank can never be unlearned and its " ..
            "Soul Ashes are never refunded. Only a |cffFF4444Prestige|r resets the tree, and " ..
            "the octagon-framed nodes survive even that.",
        button1 = "Apply",
        button2 = CANCEL,
        OnAccept = function()
            ValidateAndSendLoadout()
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }

    applyButton:SetScript("OnClick", function()
        -- Strictly the FIRST apply ever: the flag burns on showing, so even
        -- a cancel means the warning never comes back.
        if not (ProjectEbonholdDB and ProjectEbonholdDB.seenSkillTreeSpendWarning) then
            ProjectEbonholdDB = ProjectEbonholdDB or {}
            ProjectEbonholdDB.seenSkillTreeSpendWarning = true
            StaticPopup_Show("EBONHOLD_SKILLTREE_FIRST_SPEND")
            return
        end
        ValidateAndSendLoadout()
    end)
    applyButton:Disable()
    applyButton:GetFontString():SetTextColor(0.5, 0.5, 0.5)


    applyButton.glowTexture = applyButton:CreateTexture(nil, "OVERLAY")
    applyButton.glowTexture:SetTexture(
        "Interface\\Buttons\\UI-Panel-Button-Glow")
    applyButton.glowTexture:SetPoint("CENTER", applyButton, "CENTER", 25, -10)
    applyButton.glowTexture:SetSize(200, 50)
    applyButton.glowTexture:SetAlpha(0)
    applyButton.glowTexture:SetBlendMode("ADD")
    applyButton.glowTexture:SetVertexColor(1, 1, 0.5)


    applyButton.glowTimer = 0
    applyButton.glowDirection = 1



    validateBtn = applyButton


    local progressBarWidth = 550
    local progressBarHeight = 42
    local progressFrame = CreateFrame("Frame", nil, skillTreeFrame)
    progressFrame:SetSize(progressBarWidth, progressBarHeight)
    progressFrame:SetPoint("TOP", skillTreeFrame, "TOP", 0, -20)
    progressFrame:SetFrameLevel(skillTreeFrame:GetFrameLevel() + 15)


    local milestoneData = ProjectEbonhold.SoulAshesMilestones or {}


    local milestones = {}
    local milestoneSpellIDs = {}
    for i, data in ipairs(milestoneData) do
        if type(data) == "table" then
            -- Format: { soulAshes = 1000000, spellID = 101260 }
            milestones[i] = data.soulAshes
            milestoneSpellIDs[i] = data.spellID
        elseif type(data) == "number" then
            -- Format simple: 1000000
            milestones[i] = data
            -- Pas de spellID pour le format simple
        end
    end

    local barTexWidth = 512 * (0.978516 - 0.015625)
    local barTexHeight = 512 * (0.113281 - 0.031250)

    local barBg = progressFrame:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\progression_bar")
    barBg:SetTexCoord(0.015625, 0.978516, 0.031250, 0.113281)
    barBg:SetSize(progressBarWidth, barTexHeight)
    barBg:SetPoint("CENTER", progressFrame, "CENTER", 0, 0)

    -- Insets defining the fillable inner channel of the background bar
    -- (the rounded end caps in the bg texture take up space on each side).
    -- The right cap is visually wider than the left one, so the insets are
    -- asymmetric to keep the fill flush with the inner channel and prevent
    -- it from overflowing past the right cap at 100%.
    local fillInsetLeft = 18
    local fillInsetRight = 38
    local maxFillWidth = progressBarWidth - fillInsetLeft - fillInsetRight

    local fillBar = progressFrame:CreateTexture(nil, "ARTWORK")
    fillBar:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\progression_bar")
    fillBar:SetTexCoord(0.021484, 0.435547, 0.201172, 0.230469)
    fillBar:SetPoint("LEFT", barBg, "LEFT", fillInsetLeft, 2)
    fillBar:SetHeight(barTexHeight - 25)
    progressFrame.fillBar = fillBar


    local progressText = progressFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressText:SetPoint("CENTER", progressFrame, "CENTER", 0, 0)
    progressText:SetTextColor(1, 1, 1)
    progressFrame.progressText = progressText


    local iconSize = 28
    local spellButton = CreateFrame("Button", nil, progressFrame)
    spellButton:SetSize(iconSize, iconSize)
    spellButton:SetPoint("LEFT", progressFrame, "RIGHT", -40, 0)


    local spellIcon = spellButton:CreateTexture(nil, "BACKGROUND")
    spellIcon:SetAllPoints(spellButton)
    progressFrame.spellIcon = spellIcon


    local lightTexture = spellButton:CreateTexture(nil, "ARTWORK")
    lightTexture:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\progression_bar")
    lightTexture:SetTexCoord(0.023438, 0.210938, 0.283203, 0.478516)
    lightTexture:SetSize(iconSize + 32, iconSize + 32)
    lightTexture:SetPoint("CENTER", spellButton, "CENTER", 0, 0)
    lightTexture:SetBlendMode("ADD")


    local borderRound = spellButton:CreateTexture(nil, "OVERLAY")
    borderRound:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\progression_bar")
    borderRound:SetTexCoord(0.214844, 0.322266, 0.314453, 0.427734)
    borderRound:SetSize(iconSize + 16, iconSize + 16)
    borderRound:SetPoint("CENTER", spellButton, "CENTER", 0, 0)


    local animGroup = lightTexture:CreateAnimationGroup()
    local rotation = animGroup:CreateAnimation("Rotation")
    rotation:SetDegrees(360)
    rotation:SetDuration(8)
    animGroup:SetLooping("REPEAT")
    animGroup:Play()


    progressFrame.currentSpellID = 71


    spellButton:SetScript("OnEnter", function(self)
        -- print(progressFrame.currentSpellID);
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink('spell:' .. progressFrame.currentSpellID)
        GameTooltip:Show()
    end)

    spellButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)


    local function UpdateProgressBar()
        local currentTotal = TALENT_POINT_TOTAL_BASE
        local currentMilestoneIndex = 0
        local previousMilestone = 0
        local nextMilestone = milestones[1] or ProjectEbonhold.Constants.MAX_SOUL_ASHES
        local hasReachedLastMilestone = false

        -- print("|cff00ff00[ProgressBar Debug]|r Total Soul Ashes:", currentTotal)
        -- print("|cff00ff00[ProgressBar Debug]|r Milestones count:", #milestones)
        -- print("|cff00ff00[ProgressBar Debug]|r First milestone:", milestones[1])

        for i, milestone in ipairs(milestones) do
            if currentTotal >= milestone then
                currentMilestoneIndex = i
                previousMilestone = milestone
                if milestones[i + 1] then
                    nextMilestone = milestones[i + 1]
                else
                    -- Dernier milestone atteint, progresser vers le maximum
                    nextMilestone = ProjectEbonhold.Constants.MAX_SOUL_ASHES
                    hasReachedLastMilestone = true
                end
            else
                -- On a trouvé le prochain milestone, on s'arrête
                break
            end
        end

        -- print("|cff00ff00[ProgressBar Debug]|r Previous:", previousMilestone, "Next:", nextMilestone, "Last reached:",
        --    hasReachedLastMilestone)




        local spellIDIndex = currentMilestoneIndex + 1
        if spellIDIndex > #milestoneSpellIDs then
            spellIDIndex = #milestoneSpellIDs
        end
        local currentSpellID = milestoneSpellIDs[spellIDIndex] or 71
        progressFrame.currentSpellID = currentSpellID


        if hasReachedLastMilestone then
            spellButton:Hide()
        else
            spellButton:Show()
            local _, _, iconTexture = GetSpellInfo(currentSpellID)
            spellIcon:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        end


        local milestoneProgress = 0
        if hasReachedLastMilestone then
            -- No commit cap anymore: past the last milestone the bar just stays full
            milestoneProgress = 1
        elseif nextMilestone > previousMilestone then
            -- Entre deux milestones, afficher la progression entre eux
            milestoneProgress = (currentTotal - previousMilestone) / (nextMilestone - previousMilestone)
        end

        -- print("|cff00ff00[ProgressBar Debug]|r Progress:", milestoneProgress)


        local fillWidth = maxFillWidth * math.min(milestoneProgress, 1)

        -- print("|cff00ff00[ProgressBar Debug]|r FillWidth calculated:", fillWidth)


        if fillWidth > 0 then
            fillBar:SetWidth(fillWidth)
            fillBar:Show()
        else
            fillBar:Hide()
        end


        if hasReachedLastMilestone then
            progressText:SetText(FormatThousands(currentTotal))
        else
            progressText:SetText(FormatThousands(currentTotal) .. "/" .. FormatThousands(nextMilestone))
        end


        progressFrame.currentMilestoneIndex = currentMilestoneIndex
        progressFrame.nextMilestone = nextMilestone
        progressFrame.currentTotal = currentTotal
        progressFrame.previousMilestone = previousMilestone
    end
    progressFrame.UpdateProgressBar = UpdateProgressBar


    progressFrame:EnableMouse(true)
    progressFrame:SetScript("OnEnter", function(self)
        local maxSoulAshes = ProjectEbonhold.Constants.MAX_SOUL_ASHES
        local currentTotal = self.currentTotal or TALENT_POINT_TOTAL_BASE
        local nextMilestone = self.nextMilestone or maxSoulAshes
        local previousMilestone = self.previousMilestone or 0
        local currentMilestoneIndex = self.currentMilestoneIndex or 0

        InfoTooltip:SetOwner(self, "ANCHOR_TOP")
        InfoTooltip:SetText("Soul Ashes Progression", 1, 0.82, 0)


        -- Afficher la progression du milestone seulement si on n'a pas atteint le dernier
        if currentMilestoneIndex < #milestones then
            InfoTooltip:AddLine("Earn Soul Ashes to advance toward your next milestone.", 0.9, 0.9, 0.9, true)
            InfoTooltip:AddLine(" ", 1, 1, 1)

            InfoTooltip:AddLine(
                "Current Milestone: " .. FormatThousands(currentTotal) .. " / " .. FormatThousands(nextMilestone),
                1, 1, 1
            )
            InfoTooltip:AddLine(" ", 1, 1, 1)
        else
            InfoTooltip:AddLine("All milestones completed!", 0, 1, 0, true)
            InfoTooltip:AddLine(" ", 1, 1, 1)
        end


        InfoTooltip:AddLine(
            "Soul Ashes have no cap: keep committing them to push your infinite nodes ever further.",
            0.7, 0.7, 0.7, true
        )

        InfoTooltip:Show()
    end)

    progressFrame:SetScript("OnLeave", function(self)
        InfoTooltip:Hide()
    end)


    UpdateProgressBar()


    skillTreeFrame.progressBar = progressFrame


    local castMonitorFrame = CreateFrame("Frame")
    castMonitorFrame:RegisterEvent("UNIT_SPELLCAST_START")
    castMonitorFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    castMonitorFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
    castMonitorFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    castMonitorFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    castMonitorFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

    castMonitorFrame:SetScript("OnEvent", function(self, event, unit)
        if unit ~= "player" or not applyButton then return end

        local isCasting = UnitCastingInfo("player") or UnitChannelInfo("player")

        if isCasting then
            applyButton:Disable()
            applyButton:GetFontString():SetTextColor(0.5, 0.5, 0.5)
        else
            if hasUnsavedChanges and HasRealChanges() then
                local remainingPoints = GetRemainingTalentPoints()
                if remainingPoints >= 0 then
                    applyButton:Enable()
                    applyButton:GetFontString():SetTextColor(1, 1, 1)
                end
            end
        end
    end)


    local applyBtnTooltipFrame = CreateFrame("Frame", nil, applyButton)
    applyBtnTooltipFrame:SetAllPoints(applyButton)
    applyBtnTooltipFrame:SetFrameLevel(applyButton:GetFrameLevel() + 1)
    applyBtnTooltipFrame:EnableMouse(true)


    applyBtnTooltipFrame:SetScript("OnEnter", function(self)
        local remainingPoints = GetRemainingTalentPoints()
        InfoTooltip:SetOwner(self, "ANCHOR_TOP")

        if remainingPoints < 0 then
            InfoTooltip:SetText("Apply Changes", 1, 1, 1)
            InfoTooltip:AddLine(
                "You don't have enough Soul Ashes to apply this build", 1, 0.3,
                0.3, true)
            InfoTooltip:AddLine("Overspent by: " .. math.abs(remainingPoints),
                0.8, 0.8, 0.8)
        else
            if hasUnsavedChanges then
                InfoTooltip:SetText("Apply Changes", 1, 1, 1)
                InfoTooltip:AddLine("Send your soul build to the server", 0.8,
                    0.8, 0.8, true)
                InfoTooltip:AddLine(
                    "Remaining Soul Ashes: " .. FormatThousands(remainingPoints), 0.8, 0.8, 0.8)
            else
                InfoTooltip:SetText("Apply Changes", 0.5, 0.5, 0.5)
                InfoTooltip:AddLine("No changes to apply", 0.6, 0.6, 0.6, true)
            end
        end

        InfoTooltip:Show()
    end)

    applyBtnTooltipFrame:SetScript("OnLeave",
        function(self) InfoTooltip:Hide() end)


    applyBtnTooltipFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and applyButton:IsEnabled() then
            applyButton:Click()
        end
    end)


    local exportBtn = CreateFrame("Button", "skillTreeExportButton", bottomBar,
        "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 25)
    exportBtn:SetPoint("LEFT", applyButton, "RIGHT", 5, 0)
    exportBtn:SetText("Export")
    exportBtn:Hide()
    exportBtn:SetScript("OnClick", function()
        if not HasAnyTalents() then
            StaticPopupDialogs["SKILLTREE_EXPORT_EMPTY"] = {
                text = "No talents selected to export!",
                button1 = "OK",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true
            }
            StaticPopup_Show("SKILLTREE_EXPORT_EMPTY")
            return
        end


        local exportCode = ExportLoadoutToCode()


        StaticPopupDialogs["SKILLTREE_EXPORT_CODE"] = {
            text = "Build Export Code:\n\n|cffFFD700Copy the code below:|r",
            button1 = "Close",
            hasEditBox = true,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            editBoxWidth = 350,
            OnShow = function(self)
                self.editBox:SetText(exportCode)
                self.editBox:HighlightText()
                self.editBox:SetFocus()
            end,
            EditBoxOnEnterPressed = function(self)
                self:GetParent():Hide()
            end,
            EditBoxOnEscapePressed = function(self)
                self:GetParent():Hide()
            end
        }
        StaticPopup_Show("SKILLTREE_EXPORT_CODE")
    end)


    local importBtn = CreateFrame("Button", "skillTreeImportButton", bottomBar,
        "UIPanelButtonTemplate")
    importBtn:SetSize(80, 25)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 5, 0)
    importBtn:SetText("Import")
    importBtn:Hide()
    importBtn:SetScript("OnClick", function()
        StaticPopupDialogs["SKILLTREE_IMPORT_CODE"] = {
            text = "Import Build Code:\n\n|cffFFD700Paste your build code below:|r",
            button1 = "Import",
            button2 = "Cancel",
            hasEditBox = true,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            editBoxWidth = 350,
            OnAccept = function(self)
                local code = self.editBox:GetText()
                if code and code ~= "" then
                    local nodes, error = ImportLoadoutFromCode(code)
                    if nodes then
                        local success, applyError = ApplyImportedLoadout(nodes)
                        if success then
                            DebugPrint(
                                "|cff00FF00Build imported successfully! (" ..
                                #nodes .. " talents)|r")
                        else
                            StaticPopupDialogs["SKILLTREE_IMPORT_ERROR"] = {
                                text = "Import failed:\n\n|cffFF0000" ..
                                    (applyError or "Failed to apply build") ..
                                    "|r",
                                button1 = "OK",
                                timeout = 0,
                                whileDead = true,
                                hideOnEscape = true
                            }
                            StaticPopup_Show("SKILLTREE_IMPORT_ERROR")
                        end
                    else
                        StaticPopupDialogs["SKILLTREE_IMPORT_ERROR"] = {
                            text = "Import failed:\n\n|cffFF0000" ..
                                (error or "Unknown error") .. "|r",
                            button1 = "OK",
                            timeout = 0,
                            whileDead = true,
                            hideOnEscape = true
                        }
                        StaticPopup_Show("SKILLTREE_IMPORT_ERROR")
                    end
                end
            end,
            EditBoxOnEnterPressed = function(self)
                local code = self:GetText()
                if code and code ~= "" then
                    local nodes, error = ImportLoadoutFromCode(code)
                    if nodes then
                        local success, applyError = ApplyImportedLoadout(nodes)
                        if success then
                            DebugPrint(
                                "|cff00FF00Build imported successfully! (" ..
                                #nodes .. " talents)|r")
                        else
                            StaticPopupDialogs["SKILLTREE_IMPORT_ERROR"] = {
                                text = "Import failed:\n\n|cffFF0000" ..
                                    (applyError or "Failed to apply build") ..
                                    "|r",
                                button1 = "OK",
                                timeout = 0,
                                whileDead = true,
                                hideOnEscape = true
                            }
                            StaticPopup_Show("SKILLTREE_IMPORT_ERROR")
                        end
                    else
                        StaticPopupDialogs["SKILLTREE_IMPORT_ERROR"] = {
                            text = "Import failed:\n\n|cffFF0000" ..
                                (error or "Unknown error") .. "|r",
                            button1 = "OK",
                            timeout = 0,
                            whileDead = true,
                            hideOnEscape = true
                        }
                        StaticPopup_Show("SKILLTREE_IMPORT_ERROR")
                    end
                end
                self:GetParent():Hide()
            end,
            EditBoxOnEscapePressed = function(self)
                self:GetParent():Hide()
            end
        }
        StaticPopup_Show("SKILLTREE_IMPORT_CODE")
    end)


    local revertBtn = CreateFrame("Button", nil, bottomBar)
    revertBtn:SetSize(25, 25)
    revertBtn:SetPoint("RIGHT", bottomBar, "RIGHT", -10, 0)
    revertBtn:SetScript("OnClick", function() RevertToValidatedState() end)


    local revertIcon = revertBtn:CreateTexture(nil, "ARTWORK")
    revertIcon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    revertIcon:SetSize(20, 20)
    revertIcon:SetPoint("CENTER", revertBtn, "CENTER", 0, 0)

    revertBtn:Disable()
    revertIcon:SetDesaturated(true)
    revertIcon:SetAlpha(0.5)


    revertBtn.icon = revertIcon


    revertBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Revert Changes", 1, 1, 1)
        GameTooltip:AddLine("Undo all changes since last validation", 0.8, 0.8,
            0.8, true)
        GameTooltip:Show()
    end)
    revertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)


    _G.revertBtn = revertBtn


    local levelRestrictionFrame = CreateFrame("Frame", nil, bottomBar)
    levelRestrictionFrame:SetPoint("TOPLEFT", bottomBar, "TOPLEFT", 0, 0)
    levelRestrictionFrame:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", 0, 0)
    levelRestrictionFrame:SetFrameLevel(bottomBar:GetFrameLevel() + 20)
    levelRestrictionFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        tile = true,
        tileSize = 32,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    levelRestrictionFrame:SetBackdropColor(0, 0, 0, 1)
    levelRestrictionFrame:EnableMouse(true)
    levelRestrictionFrame:Hide()

    local levelRestrictionText = levelRestrictionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    levelRestrictionText:SetPoint("CENTER", levelRestrictionFrame, "CENTER", 0, 0)
    levelRestrictionText:SetText("|cffFF0000You cannot modify your skill tree while in combat|r")


    local function UpdateCombatRestriction()
        local inCombat = UnitAffectingCombat("player")

        if inCombat then
            levelRestrictionFrame:Show()
        else
            levelRestrictionFrame:Hide()
        end
    end


    local combatCheckFrame = CreateFrame("Frame")
    combatCheckFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatCheckFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatCheckFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    combatCheckFrame:SetScript("OnEvent", function(self, event)
        UpdateCombatRestriction()
    end)


    bottomBar.levelRestrictionFrame = levelRestrictionFrame
    bottomBar.updateCombatRestriction = UpdateCombatRestriction

    -- Search box on the right side of the bottom bar (before the revert button);
    -- same component the Echo Journal's catalog search uses (icon, native
    -- placeholder, clear button all built in) for visual consistency.
    if not treeSearchBox then
        treeSearchBox = CreateFrame("EditBox", "skillTreeSearchBox", bottomBar, "ezCollectionsSearchBoxTemplate")
        treeSearchBox:SetSize(170, 22)
        treeSearchBox:SetPoint("RIGHT", revertBtn, "LEFT", -10, 0)
        if applyButton and applyButton.__anchorToSearch then
            applyButton:ClearAllPoints()
            applyButton:SetPoint("RIGHT", treeSearchBox, "LEFT", -20, 0)
        end
        treeSearchBox:SetAutoFocus(false)
        treeSearchBox:SetMaxLetters(50)
        treeSearchBox:SetFrameLevel(bottomBar:GetFrameLevel() + 5)

        -- HookScript, not SetScript: the template already binds its own
        -- OnTextChanged via XML (icon tint, clear button, placeholder) and
        -- that must keep running alongside this.
        treeSearchBox:HookScript("OnTextChanged", function(self)
            FilterTreeNodes(self:GetText())
        end)
        treeSearchBox:HookScript("OnEscapePressed", function(self)
            self:SetText("")
            FilterTreeNodes("")
        end)
    end

    hasUnsavedChanges = false
end


-- Sunken inset around the tree, same InsetFrameTemplate as the Echo Journal's
-- panels: the marble Bg is hidden and the Journeys paper (bundled in assets/,
-- cropped to its opaque region x 0-794, y 0-434 of 1024x512) fills it. The
-- viewport sits inside it, below the Soul Ashes progress bar and above the pools
-- bar, so nodes never spill over the window's frame any more.
local treeInset = CreateFrame("Frame", "skillTreeInset", skillTreeFrame, "InsetFrameTemplate")
-- Fills the whole tab below the journal's title strip; the progress bar and the
-- pools bar float over the paper (they carry their own frame levels).
treeInset:SetPoint("TOPLEFT", skillTreeFrame, "TOPLEFT", 0, -16)
treeInset:SetPoint("BOTTOMRIGHT", skillTreeFrame, "BOTTOMRIGHT", 0, 0)
if treeInset.Bg then treeInset.Bg:Hide() end
local treePaper = treeInset:CreateTexture(nil, "BACKGROUND")
treePaper:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\journeysframebackground")
treePaper:SetTexCoord(0, 794 / 1024, 0, 434 / 512)
treePaper:SetPoint("TOPLEFT", treeInset, "TOPLEFT", 2, -2)
treePaper:SetPoint("BOTTOMRIGHT", treeInset, "BOTTOMRIGHT", -2, 2)

-- The paper now reaches the journal's top-left corner, where CollectionsJournal
-- draws its portrait medallion - a texture of the PARENT, so any child frame paints
-- over it. The medallion and its ring are redrawn here, above the paper, at the
-- template's exact geometry (ezCollectionsPortraitFrameTemplate: portrait 61 px at
-- (-6, 8), ring 78 px at (-14, 11), UI-Frame atlas coords 0.0078-0.6172).
local portraitCover = CreateFrame("Frame", nil, skillTreeFrame)
portraitCover:SetFrameLevel(skillTreeFrame:GetFrameLevel() + 30)
portraitCover:SetSize(1, 1)
portraitCover:SetPoint("TOPLEFT", CollectionsJournal, "TOPLEFT", 0, 0)
local portraitIcon = portraitCover:CreateTexture(nil, "ARTWORK")
portraitIcon:SetSize(61, 61)
portraitIcon:SetPoint("TOPLEFT", CollectionsJournal, "TOPLEFT", -6, 8)
SetPortraitToTexture(portraitIcon, "Interface\\AddOns\\ProjectEbonhold\\modules\\collections\\Interface\\Icons\\INV_7xp_Inscription_TalentTome01")
local portraitRing = portraitCover:CreateTexture(nil, "OVERLAY")
portraitRing:SetTexture("Interface\\AddOns\\ProjectEbonhold\\modules\\collections\\Interface\\FrameGeneral\\UI-Frame")
portraitRing:SetTexCoord(0.0078125, 0.6171875, 0.0078125, 0.6171875)
portraitRing:SetSize(78, 78)
portraitRing:SetPoint("TOPLEFT", CollectionsJournal, "TOPLEFT", -14, 11)

local Scroll = CreateFrame("ScrollFrame", "skillTreeScroll", skillTreeFrame)
-- The viewport itself stays clear of the progress bar (top) and the pools bar (bottom)
Scroll:SetPoint("TOPLEFT", treeInset, "TOPLEFT", 4, -50)
Scroll:SetPoint("BOTTOMRIGHT", treeInset, "BOTTOMRIGHT", -4, 44)
Scroll:SetFrameLevel(treeInset:GetFrameLevel() + 1)
Scroll:EnableMouse(true)
Scroll:EnableMouseWheel(true)


local Canvas = CreateFrame("Frame", "skillTreeCanvas", Scroll)
Scroll:SetScrollChild(Canvas)


-- Canvas (holding the actual node positions) is sized from the tree's own data
-- (ComputeLayout, below) independent of the outer frame's width, so it's often
-- much wider/taller than any reasonable window -- a pannable/zoomable surface
-- by design (mouse wheel = zoom), not something a wider window alone fixes.
-- Starting more zoomed out shows more of the tree without needing to scroll first.
local zoomLevel = 0.6
local MIN_ZOOM = 0.09         -- low enough to see the whole tree with its ten constellations (~5900 canvas units tall)
local MAX_ZOOM = 2.0
local ZOOM_STEP = 1.12        -- multiplicative: even steps at every zoom level
-- Empty canvas kept around the tree so that any node can be brought to the centre
-- of the viewport at every zoom level (sized once from the viewport, see ComputeLayout).
local layoutPad


local ComputeLayout


-- Viewport culling --------------------------------------------------------------------
-- A ScrollFrame draws and re-lays out EVERY shown descendant of its scroll child, in view
-- or not: with ~1 700 nodes and ~1 650 links the whole tree was paid for on every frame
-- and every drag step, whatever the zoom. Only what touches the viewport (plus a margin
-- for the halos) stays shown; a hidden region costs nothing on scroll or render, and
-- Show / Hide themselves are cheap.
--
-- The test runs on canvas coordinates kept here, NEVER on frame geometry: GetLeft /
-- GetRect / GetWidth on a hidden node wakes its layout up until its next Show + Hide.
-- Nodes and links sit in a grid of CULL_CELL canvas units; a move only touches the
-- columns and rows of cells that enter or leave the view.
-- Measured on the live TalentDatabase (1 689 nodes, 1 659 links), default view at 60 %:
-- 177 nodes in view, 234 shown with these values (289 with 160 / 64), 1 689 before.
local CULL_CELL = 96       -- canvas units per cell (one step of the node grid is 48)
local CULL_MARGIN = 48     -- kept around the viewport: start halo (26), search glow (36), badge
local CULL_KEY = 4096      -- cell key = column * CULL_KEY + row
local cullBuckets = {}     -- key -> node buttons and link textures touching that cell
local cullX0, cullX1, cullY0, cullY1 = 1, 0, 1, 0   -- cells shown now (empty range)
local cullEnabled = false

-- Box in canvas units: x0..x1 across, d0..d1 DEPTH (downwards, = -offsetY). Starts hidden.
local function cullRegister(obj, x0, d0, x1, d1)
    for ix = math.max(0, math.floor(x0 / CULL_CELL)), math.max(0, math.floor(x1 / CULL_CELL)) do
        for iy = math.max(0, math.floor(d0 / CULL_CELL)), math.max(0, math.floor(d1 / CULL_CELL)) do
            local key = ix * CULL_KEY + iy
            local bucket = cullBuckets[key]
            if not bucket then
                bucket = {}
                cullBuckets[key] = bucket
            end
            bucket[#bucket + 1] = obj
        end
    end
    obj._cullN = 0
    obj:Hide()
end

-- delta +1: the cell enters the view, -1: it leaves. An object stays shown while at
-- least one of its cells is in view.
local function cullTouch(bucket, delta)
    if not bucket then return end
    for i = 1, #bucket do
        local obj = bucket[i]
        local n = obj._cullN + delta
        obj._cullN = n
        if delta > 0 then
            if n == 1 then obj:Show() end
        elseif n == 0 then
            obj:Hide()
        end
    end
end

-- Every cell of [x0..x1] x [y0..y1] that is NOT in [ox0..ox1] x [oy0..oy1].
local function cullWalk(x0, x1, y0, y1, ox0, ox1, oy0, oy1, delta)
    for ix = x0, x1 do
        local base = ix * CULL_KEY
        if ix < ox0 or ix > ox1 then
            for iy = y0, y1 do cullTouch(cullBuckets[base + iy], delta) end
        else
            for iy = y0, math.min(y1, oy0 - 1) do cullTouch(cullBuckets[base + iy], delta) end
            for iy = math.max(y0, oy1 + 1), y1 do cullTouch(cullBuckets[base + iy], delta) end
        end
    end
end

-- Shows what the viewport touches at canvas scroll (h, v) and the current zoom, hides the
-- rest. h, v default to the scroll frame's own offsets (canvas units, see below).
local function UpdateCulling(h, v)
    if not cullEnabled then return end
    if not h then h, v = Scroll:GetHorizontalScroll(), Scroll:GetVerticalScroll() end
    local w, d = (Scroll:GetWidth() or 0) / zoomLevel, (Scroll:GetHeight() or 0) / zoomLevel
    local x0 = math.max(0, math.floor((h - CULL_MARGIN) / CULL_CELL))
    local x1 = math.max(0, math.floor((h + w + CULL_MARGIN) / CULL_CELL))
    local y0 = math.max(0, math.floor((v - CULL_MARGIN) / CULL_CELL))
    local y1 = math.max(0, math.floor((v + d + CULL_MARGIN) / CULL_CELL))
    if x0 == cullX0 and x1 == cullX1 and y0 == cullY0 and y1 == cullY1 then return end
    -- entering cells first: an object on both sides of the edge is never hidden then shown
    cullWalk(x0, x1, y0, y1, cullX0, cullX1, cullY0, cullY1, 1)
    cullWalk(cullX0, cullX1, cullY0, cullY1, x0, x1, y0, y1, -1)
    cullX0, cullX1, cullY0, cullY1 = x0, x1, y0, y1
end

local function EnableCulling()
    cullEnabled = true
    cullX0, cullX1, cullY0, cullY1 = 1, 0, 1, 0
    UpdateCulling()
end

-- Rank texts ("3/5") are hidden when zoomed out so far they cannot be read: below
-- RANK_TEXT_MIN_ZOOM a 9 pt string is under 4 px tall. Every shown font string is laid
-- out again in full on each zoom step, and each one is a draw call of its own.
local RANK_TEXT_MIN_ZOOM = 0.45
local rankTextShown = zoomLevel >= RANK_TEXT_MIN_ZOOM
local function applyRankTextLOD()
    local want = zoomLevel >= RANK_TEXT_MIN_ZOOM
    if want == rankTextShown then return end
    rankTextShown = want
    for _, btn in pairs(nodesById) do
        if btn.rankText then
            if want then btn.rankText:Show() else btn.rankText:Hide() end
        end
    end
end


-- Zoom around an anchor point of the viewport (ax, ay in Scroll units from its
-- TOPLEFT, y downwards): the canvas point under the anchor stays under it. Zooming
-- in anchors on the mouse, zooming out on the centre of the view, so the picture
-- never jumps. Without an anchor the view is left where it is.
--
-- Every camera computation here is done in CANVAS units (the node offsets).
-- Measured in game (3.3.5, scaled scroll child): the ScrollFrame's OFFSETS are in the
-- child's units (canvas units) while its RANGES are in screen units - so the range
-- is divided by the zoom before clamping. Do not "fix" one without the other.
local function GetScrollCanvas()
    return Scroll:GetHorizontalScroll(), Scroll:GetVerticalScroll()
end
local pendingScroll = CreateFrame("Frame")
pendingScroll:Hide()
-- refreshRange: re-read the child rect first. Only a zoom changes the range, so a drag
-- step skips it (the refresh walks the bounds of the whole shown subtree).
local function SetScrollEngine(h, v, refreshRange)
    if refreshRange then Scroll:UpdateScrollChildRect() end
    local hMax = (Scroll:GetHorizontalScrollRange() or 0) / zoomLevel
    local vMax = (Scroll:GetVerticalScrollRange() or 0) / zoomLevel
    Scroll:SetHorizontalScroll(math.max(0, math.min(hMax, h)))
    Scroll:SetVerticalScroll(math.max(0, math.min(vMax, v)))
    UpdateCulling()
end
pendingScroll:SetScript("OnUpdate", function(self)
    self:Hide()
    if self.h then SetScrollEngine(self.h, self.v, true) end
end)
-- Camera to (h, v) canvas units, clamped. The engine refreshes its range one frame
-- after a rescale and clamps every SetScroll against the range it currently holds:
-- applied now AND once more next frame, so the view lands where it was computed.
local function SetScrollClamped(h, v)
    SetScrollEngine(h, v, true)
    pendingScroll.h, pendingScroll.v = h, v
    pendingScroll:Show()
end

-- /stcam : dumps the camera state to the chat (diagnostic, harmless to leave in).
SLASH_EBONHOLDSTCAM1 = "/stcam"
SlashCmdList["EBONHOLDSTCAM"] = function()
    Scroll:UpdateScrollChildRect()
    local es, ce = Scroll:GetEffectiveScale(), Canvas:GetEffectiveScale()
    local function p(fmt, ...) DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[stcam]|r " .. string.format(fmt, ...)) end
    p("zoom=%.3f pad=%s", zoomLevel, tostring(layoutPad))
    p("scroll frame: %.0fx%.0f effscale=%.3f left=%.0f top=%.0f", Scroll:GetWidth() or -1, Scroll:GetHeight() or -1, es, Scroll:GetLeft() or -1, Scroll:GetTop() or -1)
    p("canvas: %.0fx%.0f scale=%.3f effscale=%.3f left=%.0f top=%.0f", Canvas:GetWidth() or -1, Canvas:GetHeight() or -1, Canvas:GetScale(), ce, Canvas:GetLeft() or -1, Canvas:GetTop() or -1)
    p("scroll: h=%.0f v=%.0f range h=%.0f v=%.0f", Scroll:GetHorizontalScroll(), Scroll:GetVerticalScroll(), Scroll:GetHorizontalScrollRange(), Scroll:GetVerticalScrollRange())
    local n = 0
    for _, nd in ipairs(TreeNodes) do if nd.isStart and not nd.classId then n = n + 1 if n <= 2 then p("start %d ox=%.0f oy=%.0f", nd.id, nd._ox or -1, nd._oy or -1) end end end
end

local zoomTextTimer = CreateFrame("Frame")
zoomTextTimer:Hide()
zoomTextTimer:SetScript("OnUpdate", function(self, elapsed)
    self.left = self.left - elapsed
    if self.left <= 0 then
        self:Hide()
        if skillTreeFrame.zoomText then skillTreeFrame.zoomText:SetText("") end
    end
end)

local function ApplyZoom(scale, ax, ay)
    local oldZoom = zoomLevel
    zoomLevel = math.max(MIN_ZOOM, math.min(MAX_ZOOM, scale))
    if zoomLevel == oldZoom then return end

    -- Canvas point under the anchor, before the scale changes
    local cx, cy
    if ax and ay then
        local h, v = GetScrollCanvas()
        cx = h + ax / oldZoom
        cy = v + ay / oldZoom
    end

    -- Cull for the view this zoom is about to show BEFORE rescaling: SetScale lays out
    -- again every shown descendant (font strings in full), hidden ones are skipped.
    -- (ComputeLayout used to run here too: it only re-derived the same canvas size and
    -- node offsets, layoutPad being fixed once.)
    if cx then
        UpdateCulling(math.max(0, cx - ax / zoomLevel), math.max(0, cy - ay / zoomLevel))
    end
    applyRankTextLOD()
    Canvas:SetScale(zoomLevel)

    if cx then
        -- The engine refreshes the scroll range one frame after a rescale and clamps
        -- every SetScroll against the range it currently holds: apply now AND once more
        -- next frame, so the view lands where it was computed whichever range was stale.
        SetScrollClamped(cx - ax / zoomLevel, cy - ay / zoomLevel)
    else
        Scroll:UpdateScrollChildRect()
        UpdateCulling()
    end


    if not skillTreeFrame.zoomText then
        skillTreeFrame.zoomText = skillTreeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        skillTreeFrame.zoomText:SetPoint("TOP", skillTreeFrame, "TOP", 0, -10)
    end
    skillTreeFrame.zoomText:SetText(string.format("Zoom: %d%%", zoomLevel * 100))

    -- Cleared one second after the LAST step. One reused frame: C_Timer.After makes a
    -- new permanent Frame per call, one per wheel notch.
    zoomTextTimer.left = 1
    zoomTextTimer:Show()
end


Scroll:SetScript("OnMouseWheel", function(self, delta)
    local wanted = delta > 0 and zoomLevel * ZOOM_STEP or zoomLevel / ZOOM_STEP
    local ax, ay
    if delta > 0 then
        -- zoom in: towards the mouse
        local mx, my = GetCursorPosition()
        local es = self:GetEffectiveScale()
        ax = mx / es - self:GetLeft()
        ay = self:GetTop() - my / es
    else
        -- zoom out: around the centre of what is on screen
        ax, ay = self:GetWidth() / 2, self:GetHeight() / 2
    end
    ApplyZoom(wanted, ax, ay)
end)




ComputeLayout = function(keepScroll)
    local NODE_SIZE = 1

    local minX, maxX, minY, maxY
    for _, n in ipairs(TreeNodes) do
        if not minX or n.x < minX then minX = n.x end
        if not maxX or n.x > maxX then maxX = n.x end
        if not minY or n.y < minY then minY = n.y end
        if not maxY or n.y > maxY then maxY = n.y end
    end

    local SPACING_SCALE = 0.8
    -- Padding = one viewport at the smallest zoom, on every side: at any zoom the
    -- canvas is at least as big as the viewport and the tree can be centred, and the
    -- scroll range shrinks naturally as one zooms out (the canvas is NOT inflated by
    -- 1/zoom any more - that pinned the tree to the top-left corner when zoomed out).
    -- Computed once so node offsets never move after the buttons are placed.
    if not layoutPad then
        local vw, vh = Scroll:GetWidth() or 0, Scroll:GetHeight() or 0
        if vw < 10 then vw = 1200 end
        if vh < 10 then vh = 800 end
        -- Half a viewport at the smallest zoom is exactly what centring an edge node needs.
        layoutPad = math.max(vw, vh) / (2 * MIN_ZOOM)
    end
    local margin = layoutPad
    local scaledWidth = (maxX - minX) * SPACING_SCALE
    local scaledHeight = (maxY - minY) * SPACING_SCALE
    Canvas:SetSize(scaledWidth + NODE_SIZE + margin * 2, scaledHeight + NODE_SIZE + margin * 2)

    for _, n in ipairs(TreeNodes) do
        n._ox = margin + (n.x - minX) * SPACING_SCALE
        n._oy = -(margin + (maxY - n.y) * SPACING_SCALE)
    end
    -- Same transform for anything else placed in node space (the class hubs).
    ProjectEbonhold.SkillTree = ProjectEbonhold.SkillTree or {}
    ProjectEbonhold.SkillTree.ToCanvas = function(x, y)
        return margin + (x - minX) * SPACING_SCALE, -(margin + (maxY - y) * SPACING_SCALE)
    end

    Scroll:UpdateScrollChildRect()
    if not keepScroll then
        Scroll:SetHorizontalScroll(Scroll:GetHorizontalScrollRange() / (2 * zoomLevel))
        Scroll:SetVerticalScroll(Scroll:GetVerticalScrollRange() / (2 * zoomLevel))
    end
end


-- Move the viewport onto the starting nodes (the tree's entry cluster) instead
-- of leaving it at the top-left. Used when the tree is first opened.
-- The scroll range is only populated after the ScrollFrame has rendered a
-- frame, so this retries until the range is available (or gives up).
local function CenterOnStartNodes(attempt)
    attempt = attempt or 1

    local sumX, sumY, count = 0, 0, 0
    for _, n in ipairs(TreeNodes) do
        if n.isStart and not n.classId and n._ox and n._oy then
            sumX = sumX + n._ox
            sumY = sumY + n._oy
            count = count + 1
        end
    end

    if count == 0 then return end

    -- Force the range to reflect the canvas' current size/scale instead of waiting
    -- for the next layout pass (otherwise a fresh canvas reports 0 for a frame or two).
    Scroll:UpdateScrollChildRect()
    local hMax = Scroll:GetHorizontalScrollRange()
    local vMax = Scroll:GetVerticalScrollRange()

    -- The scroll range isn't ready yet: try again shortly (up to a limit). With the
    -- padded canvas, scroll (0,0) shows empty space, so giving up is not an option.
    if hMax == 0 and vMax == 0 and attempt < 100 then
        C_Timer.After(0.05, function() CenterOnStartNodes(attempt + 1) end)
        return
    end

    -- Scroll offsets are in canvas units (see ApplyZoom): the viewport's half size is
    -- converted from screen units (_oy is negative, hence the sign flip).
    local centerX = sumX / count
    local centerY = -sumY / count

    SetScrollClamped(centerX - Scroll:GetWidth() / (2 * zoomLevel), centerY - Scroll:GetHeight() / (2 * zoomLevel))
end


local introFrame = CreateFrame("Frame")
introFrame:Hide()

-- One-time intro shown the first time the tree is built: every node fades in
-- with a smooth, staggered cascade radiating outward from the starting nodes,
-- while the camera settles on the starting cluster.
local function PlayIntroAnimation()
    -- Centroid of the starting nodes, in canvas offset coordinates.
    local sx, sy, sc = 0, 0, 0
    for _, n in ipairs(TreeNodes) do
        if n.isStart and n._ox and n._oy then
            sx, sy, sc = sx + n._ox, sy + n._oy, sc + 1
        end
    end
    local cx = (sc > 0) and (sx / sc) or 0
    local cy = (sc > 0) and (sy / sc) or 0

    -- Build the animation list; record the largest distance for normalization.
    local items = {}
    local maxDist = 1
    for _, n in ipairs(TreeNodes) do
        local btn = nodesById[n.id]
        if btn and n._ox and n._oy then
            local ddx, ddy = n._ox - cx, n._oy - cy
            local dist = math.sqrt(ddx * ddx + ddy * ddy)
            if dist > maxDist then maxDist = dist end
            btn:SetAlpha(0)
            items[#items + 1] = { btn = btn, dist = dist }
        end
    end

    if #items == 0 then return end

    local SPREAD = 0.9 -- time for the cascade to reach the outermost node
    local FADE = 0.45  -- per-node fade-in duration
    for _, it in ipairs(items) do
        it.delay = (it.dist / maxDist) * SPREAD
    end

    -- Smoothstep easing for a soft start/stop on each node's fade.
    local function smooth(x)
        if x <= 0 then return 0 end
        if x >= 1 then return 1 end
        return x * x * (3 - 2 * x)
    end

    local elapsed = 0
    local total = SPREAD + FADE
    introFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + math.min(dt, 0.1)
        for _, it in ipairs(items) do
            -- culled nodes are skipped (they get their final alpha below)
            if it.btn._cullN ~= 0 then
                it.btn:SetAlpha(smooth((elapsed - it.delay) / FADE))
            end
        end
        if elapsed >= total then
            for _, it in ipairs(items) do it.btn:SetAlpha(1) end
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)
    introFrame:Show()

    -- Position the camera on the starting cluster while the cascade plays.
    CenterOnStartNodes()
end


local function applyNodeVisual(btn)
    if btn.isApex then
        if not btn.apexBorderTexture then
            btn.apexBorderTexture = btn:CreateTexture(nil, "OVERLAY")
            btn.apexBorderTexture:SetTexture(
                "Interface\\Buttons\\UI-ActionButton-Border")
            btn.apexBorderTexture:SetBlendMode("ADD")
            btn.apexBorderTexture:SetPoint("TOPLEFT", btn, "TOPLEFT", -16, 16)
            btn.apexBorderTexture:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",
                16, -16)
            btn.apexBorderTexture:SetVertexColor(1.0, 0.2, 1.0, 0.8)
        end


        btn.apexBorderTexture:Show()
        btn.borderFrame:SetBackdropBorderColor(unpack(COLOR_APEX))
    end

    if btn.infinite or FAMILY_RINGS then
        if not btn.infiniteRing then
            -- Round medallion: same gold ring as the class hubs (assets/class_ring.tga).
            -- Replaces the square backdrop.
            btn.borderFrame:SetBackdrop(nil)
            local ring = btn:CreateTexture(nil, "OVERLAY")
            ring:SetPoint("CENTER", btn, "CENTER", 0, 0)
            -- Permanent nodes (kept through prestige) wear an octagon instead of the
            -- ring; sized so its inscribed circle still clears the round icon.
            btn.ringShape = btn.permanent and "class_octagon" or "class_ring"
            local k = btn.permanent and 1.26 or 1.16
            ring:SetSize(btn._size * k, btn._size * k)
            btn.infiniteRing = ring
        end
        btn.infiniteRing:Show()
    end

    if btn.state == "active" then
        local currentRank = nodeRanks[btn.id] or 0
        local maxRank = nodeMaxRank(btn)

        if btn.classId or currentRank >= maxRank then
            btn.borderFrame:SetBackdropBorderColor(unpack(COLOR_ORANGE))
        else
            btn.borderFrame:SetBackdropBorderColor(unpack(COLOR_GREEN))
        end
        btn.icon:SetDesaturated(false)
        btn.icon:SetAlpha(1.0)
    elseif btn.state == "ready" then
        btn.borderFrame:SetBackdropBorderColor(unpack(COLOR_GREEN))
        btn.icon:SetDesaturated(false)
        btn.icon:SetAlpha(1.0)
    elseif btn.state == "nopoints" then
        btn.borderFrame:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
        btn.icon:SetDesaturated(true)
        btn.icon:SetAlpha(0.85)
    else
        btn.borderFrame:SetBackdropBorderColor(unpack(COLOR_GRAY))
        btn.icon:SetDesaturated(true)
        btn.icon:SetAlpha(0.7)
    end

    -- Infinite nodes: high ranks are priced in the millions, so "nopoints" is their
    -- normal resting state — a permanently grey medallion reads as broken. Keep the
    -- icon colored unless the node is actually locked; the border color and dimmed
    -- spinner still signal that the next stack is unaffordable.
    if btn.infinite and btn.state ~= "locked" then
        btn.icon:SetDesaturated(false)
        btn.icon:SetAlpha(1.0)
    end

    -- Learned below max rank (1/3) with the next rank unaffordable: still a learned node,
    -- so it keeps its colors like a 1/1 - only the rank text tells it is not maxed.
    local learnedNoPoints = btn.state == "nopoints" and not btn.classId and not btn.infinite
        and (nodeRanks[btn.id] or 0) > 0
    if learnedNoPoints then
        btn.borderFrame:SetBackdropBorderColor(unpack(COLOR_ORANGE))
        btn.icon:SetDesaturated(false)
        btn.icon:SetAlpha(1.0)
    end

    -- Starting nodes: a soft static halo, always on, the shape of the node's frame
    -- (assets/*_glow.tga: blurred ring / octagon).
    if btn.isStart then
        if not btn.startGlow then
            local glow = btn:CreateTexture(nil, "BACKGROUND")
            glow:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\" .. (btn.permanent and "class_octagon_glow" or "class_ring_glow"))
            glow:SetBlendMode("ADD")
            glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
            local k = (btn.permanent and 1.26 or 1.16) * 1.5
            glow:SetSize(btn._size * k, btn._size * k)
            glow:SetAlpha(0.7)
            btn.startGlow = glow
        end
        btn.startGlow:Show()
    end

    if btn.infiniteRing then
        -- Ring = state: the gold ring tinted orange once learned at max rank, tinted
        -- green while it can still be taken (unlocked, or learned below max); a plain
        -- grey ring (assets/class_ring_grey.tga - a tint on gold only made it dark gold)
        -- when locked or unaffordable.
        local currentRank, maxRank = nodeRanks[btn.id] or 0, nodeMaxRank(btn)
        local ringFile, r, g, b = btn.ringShape, 1, 1, 1
        if (btn.state == "active" and (btn.classId or btn.infinite or currentRank >= maxRank))
            or learnedNoPoints then
            r, g, b = unpack(COLOR_ORANGE)
        elseif btn.state == "active" or btn.state == "ready" then
            r, g, b = unpack(COLOR_GREEN)
        else
            ringFile = btn.ringShape .. "_grey"
        end
        if btn.ringFile ~= ringFile then
            btn.ringFile = ringFile
            btn.infiniteRing:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\" .. ringFile)
        end
        btn.infiniteRing:SetVertexColor(r, g, b)
    end


    if not btn.rankText then
        btn.rankText = btn:CreateFontString(nil, "OVERLAY",
            "GameFontNormalSmall")
        btn.rankText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)

        local fontName, fontSize = btn.rankText:GetFont()
        btn.rankText:SetFont(fontName, 9, "OUTLINE")
    end

    local currentRank = nodeRanks[btn.id] or 0


    -- Ranks are always shown, locked nodes included (in grey there) - unless zoomed out
    -- past reading them (applyRankTextLOD).
    do
        if rankTextShown then btn.rankText:Show() else btn.rankText:Hide() end


        if btn.classId then
            -- owned OR selected for the next Apply: a pending class node reads like a pending rank
            local owned = ProjectEbonhold.ClassTree and ProjectEbonhold.ClassTree.Has(btn.id)
            btn.rankText:SetText(owned and "1/1" or "0/1")
            if owned then
                btn.rankText:SetTextColor(unpack(COLOR_ORANGE))
            elseif btn.state == "ready" then
                btn.rankText:SetTextColor(unpack(COLOR_GREEN))
            else
                btn.rankText:SetTextColor(0.6, 0.6, 0.6, 1.0)
            end
        elseif btn.isMultipleChoice then
            if nodeChoices[btn.id] and nodeChoices[btn.id] ~= 0 then
                btn.rankText:SetText("✓")
                btn.rankText:SetTextColor(unpack(COLOR_ORANGE))
            else
                btn.rankText:SetText("")
            end
        elseif btn.infinite then
            -- Stack count lives in the corner badge; no "N/max" clutter
            btn.rankText:SetText("")
        else
            local maxRank = nodeMaxRank(btn)
            btn.rankText:SetText(currentRank .. "/" .. maxRank)

            -- Same code as the ring: orange at max rank, green while it can be taken
            -- (or learned below max), grey when locked or unaffordable.
            if (currentRank > 0 and currentRank >= maxRank) or learnedNoPoints then
                btn.rankText:SetTextColor(unpack(COLOR_ORANGE))
            elseif btn.state == "locked" or btn.state == "nopoints" then
                btn.rankText:SetTextColor(0.6, 0.6, 0.6, 1.0)
            else
                btn.rankText:SetTextColor(unpack(COLOR_GREEN))
            end
        end
    end

    -- Infinite nodes: round badge at the top-right corner showing the purchased stack count
    if btn.infinite then
        if not btn.stackBadge then
            local badge = CreateFrame("Frame", nil, btn)
            badge:SetSize(24, 24)
            badge:SetPoint("CENTER", btn, "TOPRIGHT", 1, 1)
            badge:SetFrameLevel(btn:GetFrameLevel() + 2)

            badge.bg = badge:CreateTexture(nil, "BACKGROUND")
            badge.bg:SetAllPoints(badge)
            badge.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
            badge.bg:SetVertexColor(0, 0, 0, 0.85)

            badge.count = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            badge.count:SetPoint("CENTER", badge, "CENTER", 0, 0)
            local fontName = badge.count:GetFont()
            badge.count:SetFont(fontName, 11, "OUTLINE")
            badge.count:SetTextColor(1.0, 0.82, 0.0)

            btn.stackBadge = badge
        end

        if currentRank > 0 then
            btn.stackBadge.count:SetText(currentRank)
            btn.stackBadge:Show()
        else
            btn.stackBadge:Hide()
        end
    end
end

-- Centre of a node in canvas offsets, from the values stored at creation (CreateNodes):
-- never from GetPoint / GetWidth, the node may be culled.
local function NodeCenterOffsets(btn)
    return btn._cx, btn._cy
end

-- One link = one static texture. Straight links are a plain WHITE8x8 bar. Tilted links
-- keep their quad axis-aligned (the bounding box of the segment) and the 8-value
-- SetTexCoord maps link_line.tga onto the tilted bar inside it: the texture is white with
-- a 1-texel transparent border, so the rest of the box samples the clamped border and
-- stays invisible (32 texels, 30 opaque, hence the factor). Same geometry as before.
--
-- This replaces one Rotation animation group per link (~1 650): the animation was what
-- tilted the quad, so it had to stay alive (paused) for the life of the link. (An older
-- version kept it PLAYING with SetEndDelay(999999): past 2048 s on screen the float32
-- animation clock stopped advancing and CSimpleAnimGroup::OnUpdate hung the client.)
local LINK_TEX_TILTED = "Interface\\AddOns\\ProjectEbonhold\\assets\\link_line"
local LINK_TEX_FACTOR = 32 / 30
local function MakeLinkTexture(x1, y1, x2, y2, thickness)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return nil end
    local w = thickness or 2

    local tex = Canvas:CreateTexture(nil, "BACKGROUND")
    tex:SetBlendMode("BLEND")
    tex:SetPoint("CENTER", Canvas, "TOPLEFT", (x1 + x2) / 2, (y1 + y2) / 2)

    if math.abs(dy) < 0.5 or math.abs(dx) < 0.5 then
        tex:SetTexture("Interface\\Buttons\\WHITE8x8")
        if math.abs(dy) < 0.5 then tex:SetSize(len, w) else tex:SetSize(w, len) end
        return tex
    end

    -- c, s: direction of the link (canvas offsets, y up). u runs along the link, v across
    -- it (downwards on the texture); a box corner at (qx, qy) from the centre samples:
    local c, s = dx / len, dy / len
    local hw = (len * math.abs(c) + w * math.abs(s)) / 2
    local hh = (len * math.abs(s) + w * math.abs(c)) / 2
    local ku, kv = 1 / (len * LINK_TEX_FACTOR), 1 / (w * LINK_TEX_FACTOR)
    local function uv(qx, qy)
        return 0.5 + (qx * c + qy * s) * ku, 0.5 - (qy * c - qx * s) * kv
    end
    local ulx, uly = uv(-hw, hh)
    local llx, lly = uv(-hw, -hh)
    local urx, ury = uv(hw, hh)
    local lrx, lry = uv(hw, -hh)
    tex:SetTexture(LINK_TEX_TILTED)
    tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
    tex:SetSize(hw * 2, hh * 2)
    return tex
end

local function BuildNeighborsAndParents()
    neighbors, parentsOf = {}, {}
    DebugPrint("|cff00FFFFBuilding neighbors from " .. #Links .. " links|r")
    for _, e in ipairs(Links) do
        local a, b = e[1], e[2]
        neighbors[a] = neighbors[a] or {}
        neighbors[b] = neighbors[b] or {}
        table.insert(neighbors[a], b)
        table.insert(neighbors[b], a)


        parentsOf[b] = parentsOf[b] or {}
        table.insert(parentsOf[b], a)
    end
    DebugPrint("|cff00FFFFNeighbors table built successfully|r")
end

local function displayTalentPoints()
    if skillTreeFrame.poolTexts then
        refreshPoolsBar()
    end
end

function updateTalentPoints()
    displayTalentPoints()
end

local function canAffordTalent(nodeId)
    local btn = nodesById[nodeId]
    if not btn then return false end

    local currentRank = getNodeRank(nodeId)
    local nextRank = currentRank + 1
    local nodeCost = getNodeCost(btn, nextRank)

    return poolGet(getNodeCurrency(btn)) >= nodeCost
end

local function canUpgradeNode(nodeId)
    local btn = nodesById[nodeId]
    if not btn then return false end


    if not hasPrerequisites(nodeId) then
        DebugPrint("Node %d cannot be upgraded - prerequisites not met", nodeId)
        return false
    end


    if btn.isMultipleChoice then
        return (nodeChoices[nodeId] or 0) == 0 and canAffordTalent(nodeId)
    end


    local currentRank = getNodeRank(nodeId)
    local maxRank = getMaxRank(nodeId)
    return currentRank < maxRank and canAffordTalent(nodeId)
end

local function canDowngradeNode(nodeId)
    local btn = nodesById[nodeId]
    if not btn then return false end

    -- Applied ranks are locked in forever: only what was added since the last
    -- Apply can still be taken back (a Prestige is the only full reset).
    local validatedRank = getValidatedRank(nodeId)
    if btn.isMultipleChoice then
        if validatedRank > 0 then return false end
    elseif (getNodeRank(nodeId) or 0) <= validatedRank then
        return false
    end

    if btn.isMultipleChoice then
        local hasChoice = (nodeChoices[nodeId] or 0) ~= 0
        if not hasChoice then return false end
    else
        local currentRank = getNodeRank(nodeId)
        if currentRank <= 0 then return false end
    end

    local currentRank = getNodeRank(nodeId)
    local maxRank = getMaxRank(nodeId)
    -- Check if any child node has progress and depends on this node
    -- Since hasPrerequisites requires ALL parents to be maxed,
    -- we cannot downgrade if ANY active child has this node as a parent
    if not btn.isMultipleChoice and currentRank >= maxRank then
        for otherId, otherBtn in pairs(nodesById) do
            if otherId ~= nodeId then
                local otherHasProgress = false

                if otherBtn.isMultipleChoice then
                    otherHasProgress = (nodeChoices[otherId] or 0) ~= 0
                else
                    otherHasProgress = getNodeRank(otherId) > 0
                end

                if otherHasProgress then
                    local parents = parentsOf[otherId]
                    if parents then
                        -- Check if this node is a parent of the active child
                        for _, parentId in ipairs(parents) do
                            if parentId == nodeId then
                                -- This node is a required parent of an active child
                                -- Since ALL parents must be maxed, we cannot downgrade
                                return false
                            end
                        end
                    end
                end
            end
        end
    end

    return true
end

local function upgradeNodeRank(nodeId)
    local btn = nodesById[nodeId]
    if not btn or not canUpgradeNode(nodeId) then return false end


    if btn.isApex then
        if activeApexNodeId and activeApexNodeId ~= nodeId then
            DebugPrint(
                "|cffFF0000You can only have one APEX talent active at a time!|r")
            DebugPrint("|cffFFFF00Deactivate your current APEX talent first.|r")
            return false
        end
        activeApexNodeId = nodeId
    end


    if btn.isMultipleChoice then
        if (nodeChoices[nodeId] or 0) == 0 then
            ShowChoiceButtons(btn)
            return false
        end
        return false
    end


    local currentRank = nodeRanks[nodeId] or 0
    local nextRank = currentRank + 1
    local nodeCost = getNodeCost(btn, nextRank)

    nodeRanks[nodeId] = nextRank
    poolAdd(getNodeCurrency(btn), -nodeCost)

    DebugPrint("Node %d upgraded to rank %d (cost: %s, remaining: %s)",
        nodeId, nextRank, FormatThousands(nodeCost), FormatThousands(TALENT_POINTS_TOTAL))
    MarkUnsavedChanges()
    return true
end

-- Buys a locked node and everything leading to it in one go, when the pools cover the
-- whole path. Same bookkeeping as upgradeNodeRank, node by node, parents first, so the
-- pending loadout is exactly what the server would accept (all prerequisites maxed).
local function unlockPath(nodeId)
    local path, why = computeUnlockPath(nodeId)
    if not path then
        DebugPrint("|cffFF0000Cannot unlock the path: " .. (why or "?") .. "|r")
        return false
    end
    if not canAffordPath(path) then
        DebugPrint("|cffFF0000Not enough to unlock the whole path!|r")
        return false
    end
    for _, step in ipairs(path.nodes) do
        local btn = nodesById[step.id]
        for r = step.fromRank + 1, step.toRank do
            poolAdd(getNodeCurrency(btn), -getNodeCost(btn, r))
        end
        nodeRanks[step.id] = step.toRank
        if btn.isApex then activeApexNodeId = step.id end
    end
    DebugPrint("|cff00FF00Path unlocked: " .. #path.nodes .. " nodes, " .. path.count .. " ranks.|r")
    MarkUnsavedChanges()
    return true
end

local function downgradeNodeRank(nodeId)
    local btn = nodesById[nodeId]
    if not btn or not canDowngradeNode(nodeId) then return false end


    if btn.isApex and activeApexNodeId == nodeId then activeApexNodeId = nil end


    if btn.isMultipleChoice then
        local refund = getNodeCost(btn, 1)
        poolAdd(getNodeCurrency(btn), refund)

        nodeChoices[nodeId] = 0
        nodeRanks[nodeId] = 0
        btn.selectedSpell = nil


        if btn.spells and #btn.spells > 0 then
            setNodeIconTexture(btn, getSpellIconSafe(btn.spells[1]))
        end

        DebugPrint("Node %d choice removed (refund: %s, remaining: %s)",
            nodeId, FormatThousands(refund), FormatThousands(TALENT_POINTS_TOTAL))
        MarkUnsavedChanges()
        return true
    end


    local currentRank = nodeRanks[nodeId] or 0
    if currentRank > 0 then
        local refund = getNodeCost(btn, currentRank)
        poolAdd(getNodeCurrency(btn), refund)

        nodeRanks[nodeId] = currentRank - 1

        DebugPrint("Node %d downgraded to rank %d (refund: %s, remaining: %s)",
            nodeId, currentRank - 1, FormatThousands(refund), FormatThousands(TALENT_POINTS_TOTAL))
    end

    MarkUnsavedChanges()
    return true
end

-- Ranks of a node bought since the last Apply (0 when none): the only ones a revert may take.
local function pendingRanks(btn)
    local validated = getValidatedRank(btn.id)
    if btn.isMultipleChoice then
        return ((nodeChoices[btn.id] or 0) ~= 0 and validated == 0) and 1 or 0
    end
    return math.max(0, getNodeRank(btn.id) - validated)
end

-- Reverse of unlockPath: the node goes back to its applied rank, and every talent after it
-- that no longer has its prerequisites (ALL parents maxed) goes back to nothing. Returns
-- { nodes = { {id, toRank}, ... }, refund = { [currency] = n } } or nil, reason. Read only.
local function computeRevertLine(nodeId)
    local root = nodesById[nodeId]
    if not root or root.classId then return nil, "not an ash node" end
    if pendingRanks(root) == 0 then return nil, "nothing to take back since the last Apply" end

    local children = {}
    for id in pairs(nodesById) do
        for _, parentId in ipairs(parentsOf[id] or {}) do
            children[parentId] = children[parentId] or {}
            table.insert(children[parentId], id)
        end
    end

    local newRank = { [nodeId] = getValidatedRank(nodeId) }
    local order = { nodeId }
    local function rankOf(id) return newRank[id] or getNodeRank(id) end
    local function activeAfter(id)
        local btn = nodesById[id]
        if not btn then return false end
        if btn.isMultipleChoice then return newRank[id] == nil and (nodeChoices[id] or 0) ~= 0 end
        return rankOf(id) > 0
    end

    local queue, head = { nodeId }, 1
    while queue[head] do
        local id = queue[head]
        head = head + 1
        for _, childId in ipairs(children[id] or {}) do
            local child = nodesById[childId]
            if child and not newRank[childId] and not child.classId and activeAfter(childId)
                and not isStartingNode(childId) then
                local ok = true
                for _, parentId in ipairs(parentsOf[childId] or {}) do
                    if not activeAfter(parentId) or rankOf(parentId) < getMaxRank(parentId) then
                        ok = false
                        break
                    end
                end
                if not ok then
                    if getValidatedRank(childId) > 0 then
                        return nil, "an applied talent depends on it"
                    end
                    newRank[childId] = 0
                    table.insert(order, childId)
                    table.insert(queue, childId)
                end
            end
        end
    end

    local nodes, refund = {}, {}
    for _, id in ipairs(order) do
        local btn = nodesById[id]
        local cur = getNodeCurrency(btn)
        if btn.isMultipleChoice then
            refund[cur] = (refund[cur] or 0) + getNodeCost(btn, 1)
        else
            for r = newRank[id] + 1, getNodeRank(id) do
                refund[cur] = (refund[cur] or 0) + getNodeCost(btn, r)
            end
        end
        table.insert(nodes, { id = id, toRank = newRank[id] })
    end
    return { nodes = nodes, refund = refund }
end

local function revertLine(nodeId)
    local plan, why = computeRevertLine(nodeId)
    if not plan then
        DebugPrint("|cffFF0000Cannot take the line back: " .. (why or "?") .. "|r")
        return false
    end
    for cur, n in pairs(plan.refund) do poolAdd(cur, n) end
    for _, step in ipairs(plan.nodes) do
        local btn = nodesById[step.id]
        if btn.isApex and activeApexNodeId == step.id and step.toRank == 0 then activeApexNodeId = nil end
        nodeRanks[step.id] = step.toRank
        if btn.isMultipleChoice then
            nodeChoices[step.id] = 0
            btn.selectedSpell = nil
            if btn.spells and #btn.spells > 0 then
                setNodeIconTexture(btn, getSpellIconSafe(btn.spells[1]))
            end
        end
    end
    DebugPrint("|cffFFFF00Line taken back: " .. #plan.nodes .. " talents.|r")
    MarkUnsavedChanges()
    return true
end

-- Shift + right-click: confirm, then take back the node and the whole line after it.
local function ConfirmRevertLine(btn, onDone)
    local plan, why = computeRevertLine(btn.id)
    if not plan then
        DebugPrint("|cffFF0000Cannot take the line back: " .. (why or "?") .. "|r")
        return
    end
    local parts = {}
    for _, cur in ipairs(CURRENCY_ORDER) do
        if plan.refund[cur] then
            table.insert(parts, FormatThousands(plan.refund[cur]) .. " " .. currencyIcon(cur))
        end
    end
    local name = btn.spells and btn.spells[1] and GetSpellInfo(btn.spells[1]) or ("node " .. btn.id)
    local others = #plan.nodes - 1
    local text = "Take back |cffFFD700" .. name .. "|r"
    if others > 0 then
        text = text .. " and the " .. others .. (others > 1 and " talents" or " talent") .. " after it"
    end
    text = text .. "?\n\nOnly what was added since the last Apply is undone.\nRefund: " ..
        (#parts > 0 and table.concat(parts, "  ") or "nothing")

    StaticPopupDialogs["SKILLTREE_REVERT_LINE"] = StaticPopupDialogs["SKILLTREE_REVERT_LINE"] or {
        text = "%s",
        button1 = "Take back",
        button2 = CANCEL,
        OnAccept = function(self, data)
            if data and not UnitAffectingCombat("player") and revertLine(data.id) then
                data.onDone()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    local popup = StaticPopup_Show("SKILLTREE_REVERT_LINE", text, nil, { id = btn.id, onDone = onDone })
    if popup then
        popup:SetFrameStrata("TOOLTIP")
    end
end

-- "active", or learned below max with the next rank unaffordable (same rule as applyNodeVisual):
-- a 1/3 node that cannot buy its 2nd rank is still learned, its links stay lit.
local function linkLearned(n)
    return n.state == "active" or (n.state == "nopoints" and not n.classId and not n.infinite
        and (nodeRanks[n.id] or 0) > 0)
end

local function updateLinkColors()
    for _, L in ipairs(lines) do
        local a, b = L.a, L.b
        local color
        if linkLearned(a) and linkLearned(b) then
            color = COLOR_ORANGE
        elseif (linkLearned(a) and b.state == "ready") or
            (linkLearned(b) and a.state == "ready") then
            color = COLOR_GREEN
        else
            color = COLOR_GRAY
        end


        if not L.lastColor or L.lastColor ~= color then
            L.lastColor = color

            if L.tex then L.tex:SetVertexColor(unpack(color)) end
        end
    end
end




local function ShowChoiceButtons(btn)
    if not btn.spells or #btn.spells <= 1 then return end
    if #btn.choiceButtons > 0 then return end


    local numChoices = #btn.spells

    for i, spellID in ipairs(btn.spells) do
        local offsetX, offsetY = 0, 0
        if numChoices == 2 then
            offsetX = (i == 1) and -18 or 18
            offsetY = 25
        else
            local angle = (i - 1) * (2 * math.pi / numChoices) - math.pi / 2
            offsetX = 35 * math.cos(angle)
            offsetY = 35 * math.sin(angle)
        end


        local choiceBtn = CreateFrame("Button", nil, Canvas)
        choiceBtn:SetSize(30, 30)
        choiceBtn:SetPoint("CENTER", btn, "CENTER", offsetX, offsetY)
        choiceBtn:SetFrameLevel(btn:GetFrameLevel() + 10)


        choiceBtn.borderFrame = CreateFrame("Frame", nil, choiceBtn)
        choiceBtn.borderFrame:SetPoint("TOPLEFT", choiceBtn, "TOPLEFT", -3, 3)
        choiceBtn.borderFrame:SetPoint("BOTTOMRIGHT", choiceBtn, "BOTTOMRIGHT",
            3, -3)
        choiceBtn.borderFrame:SetFrameLevel(choiceBtn:GetFrameLevel())


        local spellName, _, iconTex = GetSpellInfo(spellID)
        if not spellName then
            iconTex = "Interface\\Icons\\INV_Misc_QuestionMark"
            DebugPrint("Warning: Invalid spell ID %s in talent database",
                spellID)
        end
        local icon = choiceBtn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(choiceBtn)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
        choiceBtn.icon = icon


        choiceBtn.borderFrame:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })

        if btn.state == "locked" then
            choiceBtn.borderFrame:SetBackdropBorderColor(0.3, 0.3, 0.3)
            choiceBtn:SetAlpha(0.5)
            choiceBtn.icon:SetDesaturated(true)
        elseif i == btn.selectedSpell then
            choiceBtn.borderFrame:SetBackdropBorderColor(0, 1, 0)
            choiceBtn:SetAlpha(1.0)
            choiceBtn.icon:SetDesaturated(false)
        else
            choiceBtn.borderFrame:SetBackdropBorderColor(1, 1, 1)
            choiceBtn:SetAlpha(0.8)
            choiceBtn.icon:SetDesaturated(false)
        end


        choiceBtn:SetScript("OnEnter", function()
            if btn.hideFrame then
                btn.hideFrame:SetScript("OnUpdate", nil)
                btn.hideFrame.timer = nil
            end

            GameTooltip:SetOwner(choiceBtn, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink('spell:' .. spellID)

            if btn.state == "locked" then
                GameTooltip:AddLine("|cffFF0000Node is locked|r", 1, 1, 1)
            elseif i == btn.selectedSpell then
                GameTooltip:AddLine("|cff00FF00Currently Selected|r", 1, 1, 1)
            else
                GameTooltip:AddLine("|cffFFFFFFClick to select this option|r",
                    1, 1, 1)
            end
            GameTooltip:Show()
        end)
        choiceBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)


        choiceBtn:SetScript("OnClick", function()
            if btn.state ~= "locked" and canAffordTalent(btn.id) then
                local nodeCost = getNodeCost(btn, 1)
                poolAdd(getNodeCurrency(btn), -nodeCost)

                btn.selectedSpell = i
                nodeChoices[btn.id] = i
                nodeRanks[btn.id] = 1

                DebugPrint("Node %d choice %d selected (cost: %s, remaining: %s)",
                    btn.id, i, FormatThousands(nodeCost), FormatThousands(TALENT_POINTS_TOTAL))
                MarkUnsavedChanges()


                setNodeIconTexture(btn, getSpellIconSafe(spellID))


                for j, otherBtn in ipairs(btn.choiceButtons) do
                    if btn.state == "locked" then
                        otherBtn.borderFrame:SetBackdropBorderColor(0.3, 0.3,
                            0.3)
                        otherBtn:SetAlpha(0.5)
                        otherBtn.icon:SetDesaturated(true)
                    elseif j == i then
                        otherBtn.borderFrame:SetBackdropBorderColor(0, 1, 0)
                        otherBtn:SetAlpha(1.0)
                        otherBtn.icon:SetDesaturated(false)
                    else
                        otherBtn.borderFrame:SetBackdropBorderColor(1, 1, 1)
                        otherBtn:SetAlpha(0.8)
                        otherBtn.icon:SetDesaturated(false)
                    end
                end


                refreshAccessibility()


                local spellName = GetSpellInfo(spellID)
                if not spellName then
                    spellName = "Invalid Spell (" .. spellID .. ")"
                end
                DebugPrint("|cff00FF00Choice selected: " ..
                    (spellName or "Unknown") .. "|r")


                HideChoiceButtons(btn)
            elseif btn.state == "locked" then
                DebugPrint(
                    "|cffFF0000Prerequisites not met! You cannot select this option yet.|r")
            elseif not canAffordTalent(btn.id) then
                DebugPrint("|cffFF0000Not enough Soul Ashes!|r")
            end
        end)

        choiceBtn.spellID = spellID
        table.insert(btn.choiceButtons, choiceBtn)
    end
end

function HideChoiceButtons(btn)
    if btn.choiceButtons then
        for _, choiceBtn in ipairs(btn.choiceButtons) do
            choiceBtn:Hide()
            choiceBtn:SetParent(nil)
        end
    end
    btn.choiceButtons = {}
end

local function updateNodeDisplay(btn, nodeId)
    if not btn or not btn.spells then return end

    local currentRank = getNodeRank(nodeId)
    local maxRank = getMaxRank(nodeId)


    local currentSpellID
    if btn.isMultipleChoice then
        local selectedChoice = nodeChoices[nodeId] or 1
        currentSpellID = btn.spells[selectedChoice]
    elseif currentRank > 0 then
        -- Clamp: infinite nodes have a single spell for every rank
        currentSpellID = btn.spells[math.min(#btn.spells, currentRank)]
    else
        currentSpellID = btn.spells[1]
    end

    if currentSpellID then
        local _, _, iconTex = GetSpellInfo(currentSpellID)
        if not iconTex then
            iconTex = "Interface\\Icons\\INV_Misc_QuestionMark"
            DebugPrint("Warning: Invalid spell ID %s in updateNodeDisplay",
                currentSpellID)
        end
        setNodeIconTexture(btn, iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
    end


    if not btn.rankText then
        btn.rankText = btn:CreateFontString(nil, "OVERLAY",
            "GameFontNormalSmall")
        btn.rankText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
        btn.rankText:SetTextColor(1, 1, 0)

        btn.rankText:SetShadowOffset(1, -1)
        btn.rankText:SetShadowColor(0, 0, 0, 1)
    end

    if btn.classId then
        btn.rankText:SetText(ProjectEbonhold.ClassTree and ProjectEbonhold.ClassTree.Has(nodeId) and "1/1" or "0/1")
    elseif btn.isMultipleChoice then
        btn.rankText:SetText(currentRank > 0 and "✓" or "")
    elseif btn.infinite then
        -- Current stack count lives in the corner badge, never "N/max"
        btn.rankText:SetText("")
    else
        btn.rankText:SetText(currentRank .. "/" .. maxRank)
    end
end

-- Bridge for skillTree_classes.lua: the class constellations are edited with the SAME
-- pending model as the rest of the tree (pool, unsaved-changes flag, chain lookup), so
-- they need the locals this file owns.
ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.SkillTree = ProjectEbonhold.SkillTree or {}
ProjectEbonhold.SkillTree.PoolAdd = function(currency, delta) poolAdd(currency, delta) end
ProjectEbonhold.SkillTree.MarkUnsavedChanges = function() MarkUnsavedChanges() end
ProjectEbonhold.SkillTree.ParentsOf = function(nodeId) return parentsOf[nodeId] end
ProjectEbonhold.SkillTree.RefreshTree = function() refreshAccessibility() end

function refreshAccessibility()
    treeStale = false
    updateTalentPoints()


    local classTree = ProjectEbonhold.ClassTree
    for nid, btn in pairs(nodesById) do
        local hasProgress = isNodeActive(nid)

        if btn.classId then
            -- Class constellation: ownership + class level, never the loadout
            btn.state = classTree and classTree.NodeState(btn, parentsOf[nid], poolGet("ash")) or "locked"
        elseif hasProgress then
            local currentRank = getNodeRank(nid)
            local maxRank = getMaxRank(nid)

            if currentRank >= maxRank then
                btn.state = "active"
            else
                if canAffordTalent(nid) then
                    btn.state = "ready"
                else
                    btn.state = "nopoints"
                end
            end
        elseif btn.isStart then
            if canAffordTalent(nid) then
                btn.state = "ready"
            else
                btn.state = "nopoints"
            end
        else
            local hasPrereqs = hasPrerequisites(nid)

            if hasPrereqs and canAffordTalent(nid) then
                btn.state = "ready"
            elseif hasPrereqs and not canAffordTalent(nid) then
                btn.state = "nopoints"
            else
                btn.state = "locked"
            end
        end
    end


    displayTalentPoints()


    -- Only the nodes whose look can have changed: state, rank, choice, class ownership
    -- are everything applyNodeVisual / updateNodeDisplay read that is not fixed at
    -- creation. Each visual call dirties the node's draw batches, and this runs on every
    -- click and every pool packet, for ~1 700 nodes.
    for nid, btn in pairs(nodesById) do
        local rank, choice = nodeRanks[nid] or 0, nodeChoices[nid] or 0
        local owned = (btn.classId and classTree and classTree.Has(nid)) and true or false
        if btn._vState ~= btn.state or btn._vRank ~= rank or btn._vChoice ~= choice or btn._vOwned ~= owned then
            btn._vState, btn._vRank, btn._vChoice, btn._vOwned = btn.state, rank, choice, owned
            applyNodeVisual(btn)
            updateNodeDisplay(btn, nid)
        end
    end
    updateLinkColors()
    if ProjectEbonhold.ClassTree then ProjectEbonhold.ClassTree.RefreshHubs() end
end

-- For server pushes (soul points, loadouts, class tree data): the full pass above
-- walks ~1 700 nodes and ~1 650 links, and nothing outside the tree reads node
-- states. While the tree cannot be seen only the pool bar is updated; the tree's
-- OnShow runs the full pass when it opens.
local function refreshTreeIfShown()
    if skillTreeFrame:IsVisible() then
        refreshAccessibility()
    else
        treeStale = true
        displayTalentPoints()
    end
end
ProjectEbonhold.SkillTree.RefreshTreeIfShown = refreshTreeIfShown

-- Cooperative chunking for the deferred first-open build (see InitTree):
-- when running inside the init coroutine, yields every `stride` calls so
-- frame/texture creation is spread across game frames instead of freezing
-- the client for the whole build. Outside a coroutine it is a no-op, so
-- the functions calling it stay safe to run synchronously too.
local initYieldCounter = 0
local function MaybeYield(stride)
    if not coroutine.running() then return end
    initYieldCounter = initYieldCounter + 1
    if initYieldCounter % (stride or 20) == 0 then
        coroutine.yield()
    end
end

-- The square backdrop border of a node is replaced by the round ring (applyNodeVisual)
-- whenever FAMILY_RINGS is on, which it always is. Such a node used to build a whole
-- backdrop (9 textures, 16 anchors) on an extra frame, only for applyNodeVisual to drop
-- it: it gets this stub instead, so the colour calls spread over the file stay valid.
local function noBorderOp() end
local NO_BORDER_FRAME = { SetBackdrop = noBorderOp, SetBackdropBorderColor = noBorderOp }

local function CreateNodes()
    wipe(nodesById)
    wipe(cullBuckets)
    cullEnabled = false
    for _, n in ipairs(TreeNodes) do
        local btn = CreateFrame("Button", "skillTreeNode" .. n.id, Canvas)
        -- Infinite nodes render bigger than normal nodes, re-centered on the same grid point
        if n.infinite then
            btn:SetSize(40, 40)
            btn:SetPoint("TOPLEFT", Canvas, "TOPLEFT", n._ox - 6, n._oy + 11)
            btn._size, btn._cx, btn._cy = 40, n._ox + 14, n._oy - 9
        else
            -- 30 px button + the icon's 1 px overhang = a 32 x 32 icon, re-centred on
            -- the 28 px grid point the layout was drawn for
            btn:SetSize(30, 30)
            btn:SetPoint("TOPLEFT", Canvas, "TOPLEFT", n._ox - 1, n._oy + 1)
            btn._size, btn._cx, btn._cy = 30, n._ox + 14, n._oy - 14
        end
        btn.id = n.id
        btn.isStart = n.isStart and true or false
        btn.state = btn.isStart and "ready" or "locked"


        btn.choiceButtons = {}


        local ringed = n.infinite or FAMILY_RINGS
        if ringed then
            btn.borderFrame = NO_BORDER_FRAME
        else
            btn.borderFrame = CreateFrame("Frame", nil, btn)
            btn.borderFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", -4, 4)
            btn.borderFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 4, -4)
            btn.borderFrame:SetFrameLevel(btn:GetFrameLevel())
        end


        btn.spells = n.spells
        btn.isMultipleChoice = n.isMultipleChoice or false
        btn.isApex = n.isApex or false
        btn.infinite = n.infinite or false
        btn.permanent = n.permanent or false
        btn.infiniteGrowth = n.infiniteGrowth
        btn.gainsPerRank = n.gainsPerRank
        btn.gainsExclusive = n.gainsExclusive
        btn.computedDesc = n.computedDesc

        btn.soulPointsCosts = n.soulPointsCosts
        btn.sector = n.sector
        -- Class constellation node: bought for good, gated by the class level (skillTree_classes.lua)
        btn.classId = n.classId
        btn.currency = n.currency or "ash"

        btn.soulPointsCost = btn.soulPointsCosts and btn.soulPointsCosts[1] or 0


        if btn.isMultipleChoice then
            btn.selectedSpell = nodeChoices[n.id] or 0
        end




        local currentSpellID
        if btn.isMultipleChoice and nodeChoices[n.id] then
            currentSpellID = btn.spells[nodeChoices[n.id]]
        elseif btn.spells then
            local currentRank = getNodeRank(n.id)
            -- Clamp to the spell list: infinite nodes have one spell for every rank
            currentSpellID = btn.spells[math.min(#btn.spells, math.max(1, currentRank))]
        end

        if currentSpellID then
            local _, _, iconTex = GetSpellInfo(currentSpellID)
            if not iconTex then
                iconTex = "Interface\\Icons\\INV_Misc_QuestionMark"
                DebugPrint("Warning: Invalid spell ID %s in CreateNodes",
                    currentSpellID)
            end
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            -- 1 px larger than the button on every side, so the medallion fills its ring
            btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
            btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
            btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            setNodeIconTexture(btn, iconTex or
                "Interface\\Icons\\INV_Misc_QuestionMark")
        end
        if not ringed then
            btn.borderFrame:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 16,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            btn.borderFrame:SetBackdropBorderColor(1, 1, 1, 1)
        end

        local function refreshNodeTooltip(node)
            if not node:IsMouseOver() then return end


            if NextRankTooltip then NextRankTooltip:Hide() end
            if CurrentRankTooltip then CurrentRankTooltip:Hide() end

            -- Un noeud de classe a sa PROPRE infobulle, construite dans OnEnter (niveau de
            -- classe, noeud precedent, prix). La reconstruire ici avec le chemin de l'arbre
            -- commun la remplacait par une infobulle generique : le rang et le prix restaient,
            -- la ligne rouge du niveau de classe disparaissait. On rejoue OnEnter, une seule
            -- source pour les deux chemins.
            if node.classId then
                local onEnter = node:GetScript("OnEnter")
                if onEnter then onEnter(node) end
                return
            end


            if node.spells and not node.isMultipleChoice then
                local currentRank = nodeRanks[node.id] or 0
                local maxRank = nodeMaxRank(node)


                if currentRank > 0 then
                    -- Clamp: infinite nodes have a single spell for every rank
                    local currentSpellID = node.spells[math.min(#node.spells, currentRank)]
                    if currentSpellID then
                        local spellName, _, spellIcon, castTime, minRange,
                        maxRange, _, _, _ = GetSpellInfo(currentSpellID)
                        if spellName then
                            CurrentRankTooltip:SetOwner(node, "ANCHOR_RIGHT")
                            if node.infinite then
                                -- Computed tooltip: values scale with the rank
                                addInfiniteSpellTooltip(CurrentRankTooltip, node, spellName, currentRank)
                            else
                                CurrentRankTooltip:SetHyperlink('spell:' ..
                                    currentSpellID)
                            end

                            CurrentRankTooltip:AddLine(
                                node.infinite
                                and ("\n|cff00FF00Stacks: " .. currentRank .. "|r")
                                or ("\n|cff00FF00Rank: " .. currentRank .. "/" .. maxRank .. "|r"),
                                1, 1, 1)

                            if currentRank < maxRank then
                                local nextRank = currentRank + 1
                                local soulCost = getNodeCost(node, nextRank)
                                local canAfford = poolGet(getNodeCurrency(node)) >= soulCost
                                addCostToTooltip(CurrentRankTooltip, "", soulCost, canAfford, getNodeCurrency(node))
                            end

                            CurrentRankTooltip:Show()
                        end
                    end
                else
                    local firstSpellID = node.spells[1]
                    if firstSpellID then
                        local spellName, _, spellIcon, castTime, minRange,
                        maxRange, _, _, _ = GetSpellInfo(firstSpellID)
                        if spellName then
                            CurrentRankTooltip:SetOwner(node, "ANCHOR_RIGHT")
                            if node.infinite then
                                addInfiniteSpellTooltip(CurrentRankTooltip, node, spellName, 0)
                            else
                                CurrentRankTooltip:SetHyperlink('spell:' ..
                                    firstSpellID)
                            end

                            CurrentRankTooltip:AddLine(
                                node.infinite
                                and "\n|cffFFFFFFStacks: 0|r"
                                or ("\n|cffFFFFFFRank: 0/" .. maxRank .. "|r"),
                                1, 1, 1)

                            local soulCost = getNodeCost(node, 1)
                            local canAfford = poolGet(getNodeCurrency(node)) >= soulCost
                            addCostToTooltip(CurrentRankTooltip, "", soulCost, canAfford, getNodeCurrency(node))

                            CurrentRankTooltip:Show()
                        end
                    end
                end


                if node.state == "active" then
                    if node.infinite then
                        -- Infinite nodes: no unlearn hint, but say they survive a Prestige
                        -- (SkillTreeHandler::RemoveAllExceptInfiniteAndPermanent keeps every rank).
                        CurrentRankTooltip:AddLine(
                            "|cffFFD700Kept through Prestige, with every rank.|r", 1, 1, 1, true)
                    elseif (getNodeRank(node.id) or 0) <= getValidatedRank(node.id) then
                        -- Every rank held is applied: locked in for good, so no
                        -- unlearn hint (and no need to state the obvious)
                    else
                        CurrentRankTooltip:AddLine(
                            "|cffAAAAAARight-click to unlearn|r", 1, 1, 1, true)
                        CurrentRankTooltip:AddLine(
                            "|cffAAAAAAShift + right-click to take back the whole line|r", 1, 1, 1, true)
                    end
                    CurrentRankTooltip:Show();
                elseif node.state == "ready" then
                    if node.infinite then
                        CurrentRankTooltip:AddLine(
                            "|cffFFD700Kept through Prestige, with every rank.|r", 1, 1, 1, true)
                    end
                    CurrentRankTooltip:AddLine(
                        "|cff00FF00Left-click to learn|r", 1, 1, 1, true)
                    CurrentRankTooltip:Show();
                elseif node.state == "locked" then
                    addUnlockPathLines(CurrentRankTooltip, node.id)
                    CurrentRankTooltip:Show();
                end
            end
        end
        btn:SetScript("OnEnter", function(self)
            if self.classId and self.spells and self.spells[1] and ProjectEbonhold.ClassTree then
                -- Same shape as every other node: spell, rank line, cost line, click hint.
                local CT = ProjectEbonhold.ClassTree
                local owned = CT.Has(self.id) and 1 or 0
                CurrentRankTooltip:SetOwner(self, "ANCHOR_RIGHT")
                CurrentRankTooltip:SetHyperlink('spell:' .. self.spells[1])
                CurrentRankTooltip:AddLine((owned > 0 and "\n|cff00FF00Rank: 1/1|r" or "\n|cffFFFFFFRank: 0/1|r"), 1, 1, 1)
                if owned == 0 then
                    local soulCost = self.soulPointsCosts and self.soulPointsCosts[1] or 0
                    addCostToTooltip(CurrentRankTooltip, "", soulCost, poolGet("ash") >= soulCost, "ash")
                    -- Everything that blocks the purchase, red, on ONE line:
                    -- previous node of the series and/or the class level.
                    -- Calcule sans regarder self.state : l'etat passe a "active" des qu'un
                    -- noeud de la serie est SELECTIONNE, et la ligne disparaissait alors du
                    -- noeud suivant alors qu'il etait toujours bloque. Un parent selectionne
                    -- compte comme pris (CT.Has), un parent absent reste affiche.
                    local reqs = {}
                    for _, parentId in ipairs(parentsOf[self.id] or {}) do
                        local pb = nodesById[parentId]
                        if pb and not CT.Has(parentId) then
                            table.insert(reqs, pb.spells and pb.spells[1] and GetSpellInfo(pb.spells[1]) or ("node " .. parentId))
                        end
                    end
                    -- Class level actually needed for THIS node: at least its position in the
                    -- series (every previous node must be owned, one slot each), and at least
                    -- one more than what is owned now if the slots are all used.
                    local level, count = CT.Level(self.classId), CT.OwnedCount(self.classId)
                    local depth, cur, guard = 0, self.id, 0
                    while parentsOf[cur] and parentsOf[cur][1] and guard < 100 do
                        depth, cur, guard = depth + 1, parentsOf[cur][1], guard + 1
                    end
                    local needed = math.max(depth + 1, (count >= level) and (count + 1) or 0)
                    if needed > level then
                        table.insert(reqs, CT.ClassName(self.classId) .. " class level " .. needed)
                    end
                    if #reqs > 0 then
                        CurrentRankTooltip:AddLine("Requires " .. table.concat(reqs, ", "), 1, 0.3, 0.3)
                    end
                    if self.state == "ready" then
                        CurrentRankTooltip:AddLine("|cff00FF00Left-click to learn|r", 1, 1, 1, true)
                    end
                end
                CurrentRankTooltip:Show()
                return
            end
            if self.spells then
                if self.isMultipleChoice and #self.spells > 1 then
                    ShowChoiceButtons(self)
                else
                    local currentRank = nodeRanks[self.id] or 0
                    local maxRank = nodeMaxRank(self)


                    if currentRank > 0 then
                        -- Clamp: infinite nodes have a single spell for every rank
                        local currentSpellID = self.spells[math.min(#self.spells, currentRank)]
                        if currentSpellID then
                            local spellName, _, spellIcon, castTime, minRange,
                            maxRange, _, _, _ = GetSpellInfo(
                                currentSpellID)
                            if spellName then
                                CurrentRankTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                if self.infinite then
                                    -- Computed tooltip: values scale with the rank
                                    addInfiniteSpellTooltip(CurrentRankTooltip, self, spellName, currentRank)
                                else
                                    CurrentRankTooltip:SetHyperlink('spell:' ..
                                        currentSpellID)
                                end

                                CurrentRankTooltip:AddLine(
                                    self.infinite
                                    and ("\n|cff00FF00Stacks: " .. currentRank .. "|r")
                                    or ("\n|cff00FF00Rank: " .. currentRank .. "/" .. maxRank .. "|r"),
                                    1, 1, 1)

                                if maxRank > 1 and currentRank < maxRank then
                                    local nextRank = currentRank + 1
                                    local soulCost = getNodeCost(self, nextRank)
                                    local canAfford = poolGet(getNodeCurrency(self)) >= soulCost
                                    addCostToTooltip(CurrentRankTooltip, "", soulCost, canAfford, getNodeCurrency(self))
                                elseif maxRank == 1 then
                                    local soulCost = getNodeCost(self, 1)
                                    local canAfford = poolGet(getNodeCurrency(self)) >= soulCost
                                    addCostToTooltip(CurrentRankTooltip, "", soulCost, canAfford, getNodeCurrency(self))
                                end

                                CurrentRankTooltip:Show()
                            end
                        end
                    else
                        local firstSpellID = self.spells[1]
                        if firstSpellID then
                            local spellName, _, spellIcon, castTime, minRange,
                            maxRange, _, _, _ = GetSpellInfo(firstSpellID)
                            if spellName then
                                CurrentRankTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                if self.infinite then
                                    addInfiniteSpellTooltip(CurrentRankTooltip, self, spellName, 0)
                                else
                                    CurrentRankTooltip:SetHyperlink('spell:' ..
                                        firstSpellID)
                                end

                                CurrentRankTooltip:AddLine(
                                    self.infinite
                                    and "\n|cffFFFFFFStacks: 0|r"
                                    or ("\n|cffFFFFFFRank: 0/" .. maxRank .. "|r"),
                                    1, 1, 1)

                                local soulCost = getNodeCost(self, 1)
                                local canAfford = poolGet(getNodeCurrency(self)) >= soulCost
                                addCostToTooltip(CurrentRankTooltip, "", soulCost, canAfford, getNodeCurrency(self))

                                CurrentRankTooltip:Show()
                            end
                        end
                    end




                    if self.state == "active" then
                        if self.infinite then
                            -- Infinite nodes: no unlearn hint, but say they survive a Prestige
                            -- (SkillTreeHandler::RemoveAllExceptInfiniteAndPermanent keeps every rank).
                            CurrentRankTooltip:AddLine(
                                "|cffFFD700Kept through Prestige, with every rank.|r", 1, 1, 1, true)
                            CurrentRankTooltip:AddLine(
                                "|cff00FF00Shift-click to learn 10 stacks|r", 1, 1, 1, true)
                        elseif (getNodeRank(self.id) or 0) <= getValidatedRank(self.id) then
                            -- Every rank held is applied: locked in for good, so
                            -- no unlearn hint (and no need to state the obvious)
                        else
                            CurrentRankTooltip:AddLine(
                                "|cffAAAAAARight-click to unlearn|r", 1, 1, 1, true)
                            CurrentRankTooltip:AddLine(
                                "|cffAAAAAAShift + right-click to take back the whole line|r", 1, 1, 1, true)
                        end
                        CurrentRankTooltip:Show();
                    elseif self.state == "ready" then
                        if self.infinite then
                            CurrentRankTooltip:AddLine(
                                "|cffFFD700Kept through Prestige, with every rank.|r", 1, 1, 1, true)
                        end
                        CurrentRankTooltip:AddLine(
                            "|cff00FF00Left-click to learn|r", 1, 1, 1, true)
                        if self.infinite then
                            CurrentRankTooltip:AddLine(
                                "|cff00FF00Shift-click to learn 10 stacks|r", 1, 1, 1, true)
                        end
                        CurrentRankTooltip:Show();
                    elseif self.state == "locked" then
                        addUnlockPathLines(CurrentRankTooltip, self.id)
                        CurrentRankTooltip:Show();
                    end
                end

                if self.isApex then
                    CurrentRankTooltip:AddLine(
                        "|cffFFAAAAOnly one Apex Talent can be active at a time.|r",
                        1, 1, 1, true)
                    CurrentRankTooltip:Show()
                end
            end
        end)
        btn:SetScript("OnLeave", function(self)
            -- The delayed close below only concerns the choice buttons of a choice
            -- node: no frame (kept forever) for each of the other nodes hovered.
            if #self.choiceButtons == 0 then
                NextRankTooltip:Hide()
                CurrentRankTooltip:Hide()
                return
            end
            if not self.hideFrame then
                self.hideFrame = CreateFrame("Frame")
            end

            self.hideFrame:SetScript("OnUpdate", function(frame, elapsed)
                elapsed = math.min(elapsed, 0.1) -- Cap elapsed to prevent freeze after alt-tab
                frame.timer = (frame.timer or 0) + elapsed
                if frame.timer > 0.1 then
                    frame:SetScript("OnUpdate", nil)
                    frame.timer = nil


                    local mouseOverChoice = false
                    for _, choiceBtn in ipairs(self.choiceButtons) do
                        if choiceBtn:IsMouseOver() then
                            mouseOverChoice = true
                            break
                        end
                    end

                    if not self:IsMouseOver() and not mouseOverChoice then
                        HideChoiceButtons(self)
                    end
                end
            end)


            NextRankTooltip:Hide()
            CurrentRankTooltip:Hide()
        end)




        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(self, button)
            local nodeId = self.id


            if UnitAffectingCombat("player") then
                DebugPrint("|cffFF0000You cannot modify your skill tree while in combat!|r")
                return
            end

            if self.classId then
                if ProjectEbonhold.ClassTree then
                    ProjectEbonhold.ClassTree.OnClick(self, button)
                    refreshNodeTooltip(self)
                end
                return
            end

            if button == "LeftButton" then
                if self.isMultipleChoice then
                    if #self.choiceButtons == 0 then
                        DebugPrint(
                            "|cffFFFF00Hover over this node to see available choices|r")
                    end
                    return
                end


                local btnSelf = self
                -- Shift-click on an infinite node buys up to 10 stacks, as many as the pool covers
                local count = (self.infinite and IsShiftKeyDown()) and 10 or 1
                -- Run now, or after the permanent-node confirmation: the state is read again
                -- at that moment, in case the pools moved while the popup was open.
                local function learn()
                    if UnitAffectingCombat("player") then return end
                    if canUpgradeNode(nodeId) then
                        local success = upgradeNodeRank(nodeId)
                        for _ = 2, count do
                            if not success or not canUpgradeNode(nodeId) then break end
                            upgradeNodeRank(nodeId)
                        end
                        if success then
                            refreshAccessibility()
                            local currentRank = nodeRanks[nodeId] or 0
                            local maxRank = nodeMaxRank(btnSelf)
                            DebugPrint("|cff00FF00Talent upgraded to rank " ..
                                currentRank .. "/" .. maxRank .. "!|r")

                            refreshNodeTooltip(btnSelf)
                        end
                    else
                        local currentRank = nodeRanks[nodeId] or 0
                        local maxRank = nodeMaxRank(btnSelf)

                        if currentRank >= maxRank then
                            DebugPrint(
                                "|cffFF0000Talent is already at maximum rank (" ..
                                maxRank .. ")!|r")
                        elseif btnSelf.state == "locked" then
                            -- deep node: buy everything leading to it, if the pools allow it
                            if unlockPath(nodeId) then
                                refreshAccessibility()
                                refreshNodeTooltip(btnSelf)
                            end
                        elseif not canAffordTalent(nodeId) then
                            DebugPrint("|cffFF0000Not enough Soul Ashes!|r")
                        end
                    end
                end

                if self.permanent and not self.infinite
                    and (canUpgradeNode(nodeId) or self.state == "locked") then
                    ConfirmPermanentNode(learn)
                else
                    learn()
                end
            elseif button == "RightButton" then
                if self.isMultipleChoice and #self.choiceButtons > 0 then
                    HideChoiceButtons(self)
                    if not IsShiftKeyDown() then return end
                end

                -- Shift + right-click: take back this node and the whole line after it
                if IsShiftKeyDown() then
                    local btnSelf = self
                    ConfirmRevertLine(self, function()
                        refreshAccessibility()
                        refreshNodeTooltip(btnSelf)
                    end)
                    return
                end


                if not self.isMultipleChoice then
                    -- Block unlearning anything already applied on the server
                    if (getNodeRank(nodeId) or 0) <= getValidatedRank(nodeId) then
                        DebugPrint("|cffFF0000This rank is applied and can never be unlearned!|r")
                        return
                    end

                    if canDowngradeNode(nodeId) then
                        local success = downgradeNodeRank(nodeId)
                        if success then
                            refreshAccessibility()
                            local currentRank = getNodeRank(nodeId)
                            local maxRank = getMaxRank(nodeId)
                            DebugPrint("|cffFFFF00Talent downgraded to rank " ..
                                currentRank .. "/" .. maxRank ..
                                ".|r")

                            refreshNodeTooltip(self)
                        end
                    else
                        local currentRank = getNodeRank(nodeId)
                        if currentRank <= 0 then
                            DebugPrint("|cffFF0000Talent is not learned yet!|r")
                        else
                            DebugPrint(
                                "|cffFF0000Cannot downgrade: Other talents depend on this one!|r")
                        end
                    end
                end
            end
        end)




        btn:SetScript("OnMouseDown", function(self, button)
            if (button == "LeftButton" and self.state == "ready") or
                (button == "RightButton" and self.state == "active") then
                return
            end


            if Scroll:GetScript("OnMouseDown") then
                Scroll:GetScript("OnMouseDown")(Scroll, button)
            end
        end)
        btn:SetScript("OnMouseUp", function(_, button)
            if Scroll:GetScript("OnMouseUp") then
                Scroll:GetScript("OnMouseUp")(Scroll, button)
            end
        end)

        nodesById[n.id] = btn
        applyNodeVisual(btn)
        -- hidden until the viewport reaches it (EnableCulling, end of the build)
        cullRegister(btn, btn._cx, -btn._cy, btn._cx, -btn._cy)
        MaybeYield(15) -- node buttons are the heaviest single pieces
    end
end

local function CreateLinks()
    for _, L in ipairs(lines) do
        if L.animGroup then
            L.animGroup:Stop()
        end

        if L.driver then
            L.driver:SetScript("OnUpdate", nil)
            L.driver:Hide()
        end

        if L.tex then L.tex:Hide() end

        if L.segments then
            for _, segment in ipairs(L.segments) do segment:Hide() end
        end
    end
    wipe(lines)

    for _, e in ipairs(Links) do
        local a, b = nodesById[e[1]], nodesById[e[2]]
        if a and b then
            local ax, ay = NodeCenterOffsets(a)
            local bx, by = NodeCenterOffsets(b)


            local tex = MakeLinkTexture(ax, ay, bx, by, 3)
            if tex then
                lines[#lines + 1] = { tex = tex, a = a, b = b }
                cullRegister(tex, math.min(ax, bx), math.min(-ay, -by), math.max(ax, bx), math.max(-ay, -by))
            end
        end
        MaybeYield(40) -- one plain texture per link
    end
    updateLinkColors()
end




local dragging = false
local startX, startY, startH, startV

local function GetCursorScaled()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

local scrollUpdateTimer = 0
local SCROLL_UPDATE_INTERVAL = 0.016
local lastDragX, lastDragY
local function DragUpdate(self, elapsed)
    if ProjectEbonhold_IsClosing then return end
    if not dragging or not UIParent:IsShown() then return end
    elapsed = math.min(elapsed, 0.1) -- Cap elapsed to prevent freeze after alt-tab

    scrollUpdateTimer = scrollUpdateTimer + elapsed
    if scrollUpdateTimer < SCROLL_UPDATE_INTERVAL then return end
    scrollUpdateTimer = 0

    local x, y = GetCursorScaled()
    local dx, dy = x - startX, y - startY


    if math.abs(dx) < 2 and math.abs(dy) < 2 then return end
    -- A held but still mouse sets nothing: each SetScroll re-anchors the canvas, which
    -- lays out every shown node again, even to the same place.
    if x == lastDragX and y == lastDragY then return end
    lastDragX, lastDragY = x, y

    -- Screen drag -> canvas units, so the tree follows the mouse 1:1 at every zoom
    SetScrollEngine(startH - dx / zoomLevel, startV + dy / zoomLevel)
end

-- The OnUpdate only exists while a button is held: it no longer runs (to return at
-- once) on every frame the tree is open.
Scroll:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" or button == "RightButton" then
        dragging = true
        startX, startY = GetCursorScaled()
        startH, startV = GetScrollCanvas()
        lastDragX, lastDragY = nil, nil
        self:SetScript("OnUpdate", DragUpdate)
    end
end)

Scroll:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" or button == "RightButton" then
        dragging = false
        self:SetScript("OnUpdate", nil)
    end
end)

-- Closing the window mid-drag ends the drag (the mouse-up may never reach us)
Scroll:SetScript("OnHide", function(self)
    dragging = false
    self:SetScript("OnUpdate", nil)
end)


local isTreeInitialized = false
local isTreeInitializing = false
local pendingIntroAnimation = false

-- Deferred first-open build: the whole tree construction runs inside a
-- coroutine resumed once per game frame (CreateNodes/CreateLinks yield
-- every few items via MaybeYield, the cheap steps yield between phases).
-- The client keeps rendering and the tree is revealed with the usual intro
-- animation once everything exists -- instead of one multi-second freeze on
-- the first click of the Skill Tree tab.
local function InitTree()
    if isTreeInitialized or isTreeInitializing then
        DebugPrint("Tree already initialized/initializing, skipping...")
        return
    end
    isTreeInitializing = true

    DebugPrint("Initializing tree (deferred)...", ProjectEbonhold)

    if ProjectEbonhold and ProjectEbonhold.RequestLoadoutFromServer then
        DebugPrint("Requesting loadout from server...")
        ProjectEbonhold.RequestLoadoutFromServer()
    end
    if ProjectEbonhold.ClassTree then ProjectEbonhold.ClassTree.Request() end

    local co = coroutine.create(function()
        Canvas:SetScale(zoomLevel)  -- match the starting zoomLevel; ComputeLayout only sizes the canvas, doesn't apply the render scale
        ComputeLayout()
        coroutine.yield()
        BuildNeighborsAndParents()
        coroutine.yield()
        CreateNodes()
        CreateLinks()
        if ProjectEbonhold.ClassTree then
            ProjectEbonhold.ClassTree.CreateHubs(Canvas, ProjectEbonhold.SkillTree.ToCanvas)
        end
        CreateBottomBar()
        coroutine.yield()
        refreshAccessibility()
        CheckInitialState()
        RefreshLoadoutDropdown()
        -- everything was registered hidden: show what the starting view touches
        EnableCulling()
    end)

    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(self)
        local ok, err = coroutine.resume(co)
        if ok and coroutine.status(co) ~= "dead" then return end

        self:SetScript("OnUpdate", nil)
        isTreeInitializing = false

        if not ok then
            -- Same net state as the old synchronous version erroring midway
            -- (isTreeInitialized stays false, next OnShow retries) -- but
            -- surfaced instead of swallowed.
            geterrorhandler()(err)
            return
        end

        isTreeInitialized = true
        DebugPrint("Tree initialization complete")

        -- First-time-only reveal: smoothly fade the nodes in and center the
        -- camera -- deferred to the next OnShow if the frame was closed
        -- while the build was still running.
        if skillTreeFrame:IsShown() then
            PlayIntroAnimation()
            refreshAccessibility()
            if _G.skillTreeBottomBar and _G.skillTreeBottomBar.updateLevelRestriction then
                _G.skillTreeBottomBar.updateLevelRestriction()
            end
        else
            pendingIntroAnimation = true
        end
    end)
end

-- ── First-open tour ──────────────────────────────────────────────────────────
-- Two steps, once per account, the first time the tree is opened with Soul Ashes to spend
-- (2026-10-22): what the tree spends, that every rank is for good. Built on the shared GlowBox
-- tour factory (modules/guidedTour). Waits while another tour is on screen.
local treeTour = ProjectEbonhold.GuidedTour.Create({
    parent = function() return skillTreeFrame end,
    dbKey = "seenSkillTreeTour",
    steps = {
        {
            title = "Your Skill Tree",
            text = "The tree spends the |cffffd700Soul Ashes|r kept on your account. They arrive " ..
                "when you make an |cffffd700offering|r at a Spirit Healer, or when a run ends. " ..
                "This is what you have to spend; hover it to see what it buys.",
            zone = function()
                local t = skillTreeFrame.poolTexts and skillTreeFrame.poolTexts[1]
                return t and t.hover
            end,
            boxAnchor = { "BOTTOMLEFT", "TOPLEFT", 0, 14 },
        },
        {
            title = "Every rank is for good",
            text = "Click a node to take a rank, then |cffffd700Apply Changes|r. Once applied, a " ..
                "rank is |cffff4040permanent|r: it can never be unlearned or refunded. Only a " ..
                "|cffff4444Prestige|r clears the tree.",
            zone = function() return Scroll end,
            boxAnchor = { "TOPRIGHT", "TOPRIGHT", -20, -20 },
        },
    },
})

local function MaybeStartTreeTour()
    if treeTour:HasSeen() or treeTour:IsActive() then return end
    C_Timer.After(1.0, function()
        -- after the camera has settled on the starting nodes
        if not skillTreeFrame:IsShown() or not isTreeInitialized then return end
        if (TALENT_POINTS_TOTAL or 0) <= 0 then return end
        if ProjectEbonhold.GuidedTour.AnyActive() then return end
        treeTour:MaybeStart()
    end)
end

skillTreeFrame:HookScript("OnHide", function()
    -- closed mid-tour: pause it, the next opening with points starts it again
    if treeTour:IsActive() then treeTour:Stop(false) end
end)

skillTreeFrame:SetScript("OnShow", function()
    MaybeStartTreeTour()
    if not isTreeInitialized then
        -- Deferred build (or already in progress): the completion handler
        -- above takes care of the intro animation and refreshes.
        InitTree()
        return
    end

    if pendingIntroAnimation then
        pendingIntroAnimation = false
        PlayIntroAnimation()
    else
        -- Every opening lands on the starting nodes, whatever the last view was.
        CenterOnStartNodes()
    end

    refreshAccessibility()

    -- (was a C_Timer.After(0.1): one new permanent Frame per opening of the tree)
    if _G.skillTreeBottomBar and _G.skillTreeBottomBar.updateLevelRestriction then
        _G.skillTreeBottomBar.updateLevelRestriction()
    end
end)


ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.SkillTree = ProjectEbonhold.SkillTree or {}
ProjectEbonhold.SkillTree.OnApplyChangesResult = OnApplyChangesResult


ProjectEbonhold.SkillTree.UpdateTotalSoulPoints =
    function(spendablePoints, committedPoints, pools)
        -- The server value is the truth for what is BANKED; the class nodes still waiting
        -- for an Apply stay deducted, like the unapplied ranks of the tree.
        TALENT_POINTS_TOTAL = spendablePoints - pendingClassCost()
        TALENT_POINT_TOTAL_BASE = committedPoints
        if pools then
            for c, v in pairs(pools) do
                if CURRENCY_POOLS[c] then
                    CURRENCY_POOLS[c].spendable = v.spendable or 0
                    CURRENCY_POOLS[c].banked = v.banked or 0
                end
            end
        end
        for currency, cost in pairs(pendingTreeCost()) do poolAdd(currency, -cost) end

        if skillTreeFrame and skillTreeFrame.poolTexts then
            refreshPoolsBar()
        end
        if skillTreeFrame and skillTreeFrame.progressBar and skillTreeFrame.progressBar.UpdateProgressBar then
            skillTreeFrame.progressBar.UpdateProgressBar()
        end

        refreshTreeIfShown()
        -- the points can land after the window opened
        if skillTreeFrame and skillTreeFrame:IsShown() then MaybeStartTreeTour() end
    end
