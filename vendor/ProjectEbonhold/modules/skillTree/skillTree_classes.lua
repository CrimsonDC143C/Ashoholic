-- ProjectEbonhold - the class constellations of the skill tree.
--
-- Ten small trees (90 nodes each, one per class) orbit the common tree. They do NOT
-- follow the loadout model: a class node is BOUGHT for good (real Soul Ash debit, kept
-- through prestige, active on every character of the account), and the gate is the
-- CLASS LEVEL - Soul Ashes earned while playing a class accumulate, and at level N the
-- account may own at most N nodes of that class. Server side: ClassTreeHandler.cpp.
--
-- Protocol (projectebonhold.lua):
--   CS.REQUEST_CLASS_TREE_DATA (1230) body ""        -> SS.SEND_CLASS_TREE_DATA (1230)
--       "<ashes class1>,...,<ashes class11>|<owned nodeId>,..."
--   CS.REQUEST_CLASS_NODE_BUY  (1231) body "<nodeId>" -> SS.SEND_CLASS_NODE_RESULT (1231)
--       "OK,<nodeId>,<new ash pool>" | "FAIL,<reason>,<nodeId>"
--   SS.SEND_CLASS_LEVEL_UP (1232) "<classId>,<level>,<ashes>"  (pushed the moment a level is reached)
--   SS.SEND_CLASS_TREE_PROGRESS (1233) "<classId>,<ashes>"      (current class, throttled)
--
-- skillTree.lua owns the node buttons; it branches into this module for class nodes
-- (state, tooltip, click) and asks it to draw the hubs once the canvas is laid out.
local addon, Addon = ...

ProjectEbonhold = ProjectEbonhold or {}
local CT = {}
ProjectEbonhold.ClassTree = CT

local FormatThousands = ProjectEbonhold.FormatThousands or function(n) return tostring(n) end

-- Level thresholds: mirror of ClassTreeHandler::AshesForLevel (cumulative, geometric).
CT.MAX_LEVEL   = 90
CT.LEVEL_BASE  = 250000
CT.LEVEL_RATIO = 1.05
CT.NODES_PER_CLASS = 90

CT.ashes  = {}      -- [classId] = Soul Ashes earned on that class (cumulative)
CT.owned  = {}      -- [nodeId] = true
CT.loaded = false
CT.hubs   = {}      -- [classId] = hub frame

local nodesByClass = {}   -- [classId] = { nodeId, ... }  (from TalentDatabase)
local nodeInfo = {}       -- [nodeId] = node table from TalentDatabase
local function indexNodes()
    if next(nodeInfo) then return end
    local tree = TalentDatabase and TalentDatabase[0]
    if not tree then return end
    for _, n in ipairs(tree.nodes) do
        if n.classId then
            nodeInfo[n.id] = n
            nodesByClass[n.classId] = nodesByClass[n.classId] or {}
            table.insert(nodesByClass[n.classId], n.id)
        end
    end
end

function CT.AshesForLevel(level)
    if not level or level <= 0 then return 0 end
    if level > CT.MAX_LEVEL then level = CT.MAX_LEVEL end
    return math.floor(CT.LEVEL_BASE * (CT.LEVEL_RATIO ^ level - 1) / (CT.LEVEL_RATIO - 1) + 0.5)
end

function CT.LevelForAshes(ashes)
    ashes = ashes or 0
    local level = 0
    while level < CT.MAX_LEVEL and ashes >= CT.AshesForLevel(level + 1) do
        level = level + 1
    end
    return level
end

function CT.Level(classId) return CT.LevelForAshes(CT.ashes[classId] or 0) end

-- Pending buys: a class node clicked but not applied yet, exactly like a pending rank of
-- the common tree. They leave with the Apply button (CT.FlushPending), never on the click.
CT.pending = {}

function CT.HasPending() return next(CT.pending) ~= nil end

-- Owned, or selected for the next Apply: everything (chain, level gate, visuals) reads this.
function CT.Has(nodeId) return (CT.owned[nodeId] or CT.pending[nodeId]) and true or false end

local function nodeCost(btn) return btn and btn.soulPointsCosts and btn.soulPointsCosts[1] or 0 end

-- Soul Ashes held by the pending selections: the pool the tree displays is the server value
-- minus this, so a class node weighs on the budget like any unapplied rank.
function CT.PendingCost()
    indexNodes()
    local total = 0
    for id in pairs(CT.pending) do total = total + nodeCost(nodeInfo[id]) end
    return total
end

function CT.OwnedCount(classId)
    indexNodes()
    local count = 0
    for _, id in ipairs(nodesByClass[classId] or {}) do
        if CT.Has(id) then count = count + 1 end
    end
    return count
end

function CT.ClassName(classId)
    local hub = TalentDatabase and TalentDatabase[0] and TalentDatabase[0].classHubs and TalentDatabase[0].classHubs[classId]
    return hub and hub.name or ("Class " .. tostring(classId))
end

local function classColor(classId)
    local hub = TalentDatabase and TalentDatabase[0] and TalentDatabase[0].classHubs and TalentDatabase[0].classHubs[classId]
    if hub and hub.color then
        local r, g, b = hub.color:match("(%x%x)(%x%x)(%x%x)")
        if r then return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 end
    end
    return 1, 1, 1
end

-- ---------------------------------------------------------------------------
-- Node state, tooltip, click (called from skillTree.lua for nodes with classId)
-- ---------------------------------------------------------------------------

-- "active" (owned) / "ready" (buyable now) / "nopoints" (chain ok, level or ashes
-- missing) / "locked" (previous node of the series not owned).
function CT.NodeState(btn, parents, ashPool)
    if CT.Has(btn.id) then return "active" end
    local chainOk = btn.isStart
    if not chainOk and parents then
        for _, p in ipairs(parents) do
            if CT.Has(p) then chainOk = true break end
        end
    end
    if not chainOk then return "locked" end
    local cost = nodeCost(btn)
    if CT.OwnedCount(btn.classId) < CT.Level(btn.classId) and (ashPool or 0) >= cost then
        return "ready"
    end
    return "nopoints"
end

function CT.AddTooltipLines(tooltip, btn, ashPool)
    local classId = btn.classId
    local level, owned = CT.Level(classId), CT.OwnedCount(classId)
    local r, g, b = classColor(classId)
    tooltip:AddLine(" ")
    tooltip:AddLine(CT.ClassName(classId) .. " constellation", r, g, b)
    if CT.owned[btn.id] then
        tooltip:AddLine("Owned - permanent, active on every character of your account.", 0.6, 0.85, 0.6, true)
    elseif CT.pending[btn.id] then
        tooltip:AddLine("Selected - bought when you Apply your changes.", 0.6, 0.85, 0.6, true)
        tooltip:AddLine("|cffFFFF00Right-click to take it back|r", 1, 1, 1, true)
    else
        local cost = nodeCost(btn)
        local levelOk = owned < level
        tooltip:AddDoubleLine("Class level " .. level .. " - nodes owned " .. owned .. "/" .. level,
            levelOk and "slot available" or "next slot at level " .. (owned + 1),
            1, 1, 1, levelOk and 0.1 or 1, levelOk and 1 or 0.3, levelOk and 0.1 or 0.3)
        local afford = (ashPool or 0) >= cost
        tooltip:AddLine("Cost: " .. FormatThousands(cost) .. " Soul Ashes", afford and 0.1 or 1, afford and 1 or 0.3, afford and 0.1 or 0.3)
        tooltip:AddLine("Bought for good: the ashes leave your pool on Apply, the node stays through prestige and applies to every character of your account.", 0.8, 0.8, 0.8, true)
        if btn.state == "ready" then
            tooltip:AddLine("|cff00FF00Left-click to select, then Apply|r", 1, 1, 1, true)
        elseif btn.state == "locked" then
            tooltip:AddLine("|cffFF6060Take the previous node of this series first|r", 1, 1, 1, true)
        end
    end
end

-- True when another PENDING node of the same series hangs on this one: taking it back would
-- leave that one without its chain, so the click is refused (same rule as the common tree).
local function pendingChildOf(nodeId)
    local ST = ProjectEbonhold.SkillTree
    if not ST or not ST.ParentsOf then return nil end
    for id in pairs(CT.pending) do
        for _, parentId in ipairs(ST.ParentsOf(id) or {}) do
            if parentId == nodeId then return id end
        end
    end
    return nil
end

-- Click = pending selection, like any other node of the tree: no dialog, no chat line. The
-- Apply button commits (and carries the first-spend warning of the common tree).
function CT.OnClick(btn, button)
    local ST = ProjectEbonhold.SkillTree
    if not ST or not ST.PoolAdd then return end

    if button == "RightButton" then
        if not CT.pending[btn.id] then return end
        if pendingChildOf(btn.id) then return end
        CT.pending[btn.id] = nil
        ST.PoolAdd("ash", nodeCost(btn))
        ST.MarkUnsavedChanges()
        ST.RefreshTree()
        return
    end

    if button ~= "LeftButton" then return end
    if btn.state ~= "ready" or CT.Has(btn.id) then return end

    CT.pending[btn.id] = true
    ST.PoolAdd("ash", -nodeCost(btn))
    ST.MarkUnsavedChanges()
    ST.RefreshTree()
end

-- Sends every pending buy, parents first (the server refuses a node whose predecessor is not
-- owned yet, and handles the packets in order). Returns how many were sent.
function CT.FlushPending()
    local ST = ProjectEbonhold.SkillTree
    if not CT.HasPending() or not ProjectEbonhold.sendToServer then return 0 end

    local remaining = {}
    for id in pairs(CT.pending) do remaining[id] = true end
    local order, guard = {}, 0
    while next(remaining) and guard < 200 do
        guard = guard + 1
        local progressed = false
        for id in pairs(remaining) do
            local ready = true
            for _, parentId in ipairs((ST and ST.ParentsOf and ST.ParentsOf(id)) or {}) do
                if remaining[parentId] then ready = false break end
            end
            if ready then
                table.insert(order, id)
                remaining[id] = nil
                progressed = true
            end
        end
        -- A cycle should be impossible (the series are strict chains); send the rest as-is
        -- rather than dropping the player's selection on the floor.
        if not progressed then
            for id in pairs(remaining) do table.insert(order, id); remaining[id] = nil end
        end
    end

    for _, id in ipairs(order) do
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_CLASS_NODE_BUY, tostring(id))
    end
    return #order
end

-- Revert button: drop the selections and give their ashes back to the displayed pool.
function CT.RevertPending()
    if not CT.HasPending() then return end
    local ST = ProjectEbonhold.SkillTree
    indexNodes()
    for id in pairs(CT.pending) do
        if ST and ST.PoolAdd then ST.PoolAdd("ash", nodeCost(nodeInfo[id])) end
    end
    CT.pending = {}
end

-- ---------------------------------------------------------------------------
-- Hubs: class icon + level bar at the centre of each constellation
-- ---------------------------------------------------------------------------
local HUB_SIZE = 96          -- canvas units at scale 1 (the icon asset is 128)
local BAR_W, BAR_H = 112, 22   -- sits over the bottom of the icon, big enough to read at tree zoom

local function hubTooltip(self)
    local classId = self.classId
    local ashes = CT.ashes[classId] or 0
    local level = CT.LevelForAshes(ashes)
    local r, g, b = classColor(classId)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(CT.ClassName(classId), r, g, b)
    GameTooltip:AddDoubleLine("Class level", level .. " / " .. CT.MAX_LEVEL, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Nodes owned", CT.OwnedCount(classId) .. " / " .. CT.NODES_PER_CLASS, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Soul Ashes earned", FormatThousands(ashes), 1, 1, 1, 1, 1, 1)
    if level < CT.MAX_LEVEL then
        GameTooltip:AddDoubleLine("Next level at", FormatThousands(CT.AshesForLevel(level + 1)), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Every Soul Ash you earn while playing a " .. CT.ClassName(classId) .. " raises this bar. Each class level lets you own one more node of this constellation, bought for good with Soul Ashes.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

-- Class aura: a soft disc in the class colour behind each constellation, so a class tree
-- reads as one place on the map. Bright behind the player's own class, faint elsewhere.
local AURA_ALPHA_OWN, AURA_ALPHA_OTHER = 0.45, 0.16
local AURA_MARGIN = 1.25     -- disc radius / farthest node of the constellation

function CT.OwnClassId()
    local _, token = UnitClass("player")
    local tree = TalentDatabase and TalentDatabase[0]
    if not token or not tree or not tree.classHubs then return nil end
    for classId, hub in pairs(tree.classHubs) do
        if hub.token == token then return classId end
    end
end

-- Radius of a constellation in node space: farthest node from its hub.
local function constellationRadius(classId, hub)
    indexNodes()
    local r = 0
    for _, nodeId in ipairs(nodesByClass[classId] or {}) do
        local n = nodeInfo[nodeId]
        local dx, dy = n.x - hub.x, n.y - hub.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > r then r = d end
    end
    return r > 0 and r or 400
end

-- toCanvas(x, y) -> ox, oy in the canvas' TOPLEFT-anchored space (skillTree.lua's layout).
function CT.CreateHubs(canvas, toCanvas)
    local tree = TalentDatabase and TalentDatabase[0]
    if not tree or not tree.classHubs then return end
    local ownClassId = CT.OwnClassId()
    for classId, hub in pairs(tree.classHubs) do
        local f = CT.hubs[classId]
        if not f then
            f = CreateFrame("Frame", "skillTreeClassHub" .. classId, canvas)
            f:SetSize(HUB_SIZE, HUB_SIZE)
            f.classId = classId
            f:EnableMouse(true)
            f:SetScript("OnEnter", hubTooltip)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)

            local r, g, b = classColor(classId)
            local icon = f:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("CENTER", f, "CENTER", 0, 0)
            icon:SetSize(HUB_SIZE * 0.94, HUB_SIZE * 0.94)
            -- Round class icons (same atlas layout as the square ones, hence the same coords)
            icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            local coords = (CLASS_BUTTONS and CLASS_BUTTONS[hub.token]) or (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[hub.token])
            if coords then icon:SetTexCoord(unpack(coords)) end
            f.icon = icon

            -- Gold ring drawn at 256 px (assets/class_ring.tga, generated) so it stays crisp at
            -- any zoom; the ring spans 84-100% of the texture, so it hugs the medallion.
            local border = f:CreateTexture(nil, "OVERLAY")
            border:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\class_ring")
            border:SetSize(HUB_SIZE * 0.94 * 1.12, HUB_SIZE * 0.94 * 1.12)
            border:SetPoint("CENTER", icon, "CENTER", 0, 0)
            f.border = border

            local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            name:SetPoint("BOTTOM", f, "TOP", 0, 6)
            name:SetJustifyH("CENTER")
            name:SetWidth(HUB_SIZE * 2)
            name:SetText(hub.name)
            name:SetTextColor(r, g, b)
            f.name = name

            local bar = CreateFrame("StatusBar", nil, f)
            bar:SetSize(BAR_W, BAR_H)
            bar:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
            bar:SetFrameLevel(f:GetFrameLevel() + 2)
            bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            bar:SetStatusBarColor(r, g, b)
            bar:SetMinMaxValues(0, 1)
            local bg = bar:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(bar)
            bg:SetTexture(0, 0, 0, 0.75)
            local border = CreateFrame("Frame", nil, bar)
            border:SetPoint("TOPLEFT", bar, "TOPLEFT", -3, 3)
            border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 3, -3)
            border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
            border:SetBackdropBorderColor(0.6, 0.6, 0.6)
            local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("CENTER", bar, "CENTER", 0, 0)
            local fontName = text:GetFont()
            text:SetFont(fontName, 13, "OUTLINE")
            bar.text = text
            bar:EnableMouse(true)
            bar:SetScript("OnEnter", function() hubTooltip(f) end)
            bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f.bar = bar

            -- Level-up pulse (yellow), played by CT.OnLevelUp
            local glow = f:CreateTexture(nil, "OVERLAY")
            glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            glow:SetBlendMode("ADD")
            glow:SetPoint("CENTER", f, "CENTER", 0, 0)
            glow:SetSize(HUB_SIZE * 2.2, HUB_SIZE * 2.2)
            glow:SetVertexColor(1, 0.85, 0.1)
            glow:SetAlpha(0)
            f.glow = glow
            local ag = glow:CreateAnimationGroup()
            local a1 = ag:CreateAnimation("Alpha"); a1:SetChange(1); a1:SetDuration(0.4); a1:SetOrder(1)
            local a2 = ag:CreateAnimation("Alpha"); a2:SetChange(-1); a2:SetDuration(1.2); a2:SetOrder(2)
            ag:SetLooping("NONE")
            f.glowAnim = ag

            CT.hubs[classId] = f
        end
        local ox, oy = toCanvas(hub.x, hub.y)
        f:ClearAllPoints()
        f:SetPoint("CENTER", canvas, "TOPLEFT", ox, oy)

        -- On the canvas itself (not the hub frame): canvas regions draw under every node.
        if not f.aura then
            local r, g, b = classColor(classId)
            f.aura = canvas:CreateTexture(nil, "BACKGROUND")
            f.aura:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\class_aura")
            f.aura:SetVertexColor(r, g, b)
            f.aura:SetAlpha(classId == ownClassId and AURA_ALPHA_OWN or AURA_ALPHA_OTHER)
        end
        local radius = toCanvas(hub.x + constellationRadius(classId, hub) * AURA_MARGIN, hub.y) - ox
        f.aura:SetSize(radius * 2, radius * 2)
        f.aura:ClearAllPoints()
        f.aura:SetPoint("CENTER", canvas, "TOPLEFT", ox, oy)
    end
    CT.RefreshHubs()
end

function CT.RefreshHubs()
    for classId, f in pairs(CT.hubs) do
        local ashes = CT.ashes[classId] or 0
        local level = CT.LevelForAshes(ashes)
        local lo, hi = CT.AshesForLevel(level), CT.AshesForLevel(level + 1)
        local frac = 1
        if level < CT.MAX_LEVEL and hi > lo then frac = (ashes - lo) / (hi - lo) end
        f.bar:SetValue(frac)
        f.bar.text:SetText(level >= CT.MAX_LEVEL and ("Level " .. level) or ("Level " .. level .. "  " .. math.floor(frac * 100) .. "%"))
        f.name:SetText(CT.ClassName(classId))
    end
end

local function refreshTree()
    -- server data: the full node pass only while the tree can be seen
    local ST = ProjectEbonhold.SkillTree
    if ST and ST.RefreshTreeIfShown then
        ST.RefreshTreeIfShown()
    elseif refreshAccessibility then
        refreshAccessibility()
    end
    CT.RefreshHubs()
end

-- ---------------------------------------------------------------------------
-- Server messages
-- ---------------------------------------------------------------------------
function CT.ApplyData(body)
    local ashesPart, ownedPart = body:match("^([^|]*)|?(.*)$")
    local classId = 1
    CT.ashes = {}
    for n in (ashesPart or ""):gmatch("(%d+)") do
        CT.ashes[classId] = tonumber(n) or 0
        classId = classId + 1
    end
    CT.owned = {}
    for n in (ownedPart or ""):gmatch("(%d+)") do
        CT.owned[tonumber(n)] = true
    end
    CT.loaded = true
    refreshTree()
end

function CT.OnProgress(body)
    local classId, ashes = body:match("^(%d+),(%d+)")
    if not classId then return end
    CT.ashes[tonumber(classId)] = tonumber(ashes) or 0
    CT.RefreshHubs()
end

function CT.OnLevelUp(body)
    local classId, level, ashes = body:match("^(%d+),(%d+),(%d+)")
    if not classId then return end
    classId, level = tonumber(classId), tonumber(level)
    CT.ashes[classId] = tonumber(ashes) or CT.ashes[classId] or 0
    local r, g, b = classColor(classId)
    -- Shown in the yellow bubble over the Character Progression button, not in the chat:
    -- nobody reads a chat line.
    local name = CT.ClassName(classId)
    local msg = string.format("|cffffd100%s - class level %d!|r\n\nYou can now own %d node%s in the %s constellation. Open Character Progression to choose one.",
        name, level, level, level > 1 and "s" or "", name)
    PlaySound("LEVELUP")
    if SkillTreeMicroButton_StartFlashing then SkillTreeMicroButton_StartFlashing() end
    if SkillTreeMicroButton_ShowAlert then SkillTreeMicroButton_ShowAlert(msg) end
    local f = CT.hubs[classId]
    if f and f.glowAnim then f.glowAnim:Stop(); f.glowAnim:Play() end
    refreshTree()
end

function CT.OnBuyResult(body)
    local status, a, b = body:match("^(%u+),([^,]*),?(.*)$")
    -- sendToServer whispers the player himself, so our own REQUEST_CLASS_NODE_BUY (same
    -- number 1231 in the client-sent space) comes back through this very handler with the
    -- node id as its body. Anything that is not a server verdict is that echo.
    if status ~= "OK" and status ~= "FAIL" then return end

    local ST = ProjectEbonhold.SkillTree
    if status == "OK" then
        local nodeId = tonumber(a)
        if nodeId then
            CT.owned[nodeId] = true
            -- The pending cost stops being deducted here; the pool packet that follows
            -- (SEND_PLAYER_UPDATED_COMMITTED_SOUL_POINTS) carries the real balance.
            CT.pending[nodeId] = nil
        end
        PlaySound("igCharacterInfoTab")
        if ST and ST.MarkUnsavedChanges then ST.MarkUnsavedChanges() end
        refreshTree()
    else
        -- A refusal is the only thing worth a message: the node goes back to unselected and
        -- its ashes return to the displayed pool.
        local nodeId = tonumber(b)
        if nodeId and CT.pending[nodeId] then
            CT.pending[nodeId] = nil
            indexNodes()
            if ST and ST.PoolAdd then ST.PoolAdd("ash", nodeCost(nodeInfo[nodeId])) end
            if ST and ST.MarkUnsavedChanges then ST.MarkUnsavedChanges() end
        end
        local reasons = {
            invalid = "Unknown node.", notloaded = "Your class progress is not loaded yet, try again.",
            owned = "You already own this node.", chain = "Buy the previous node of this series first.",
            level = "Your class level does not allow another node yet.", ashes = "Not enough Soul Ashes.",
        }
        UIErrorsFrame:AddMessage(reasons[a] or ("Purchase refused (" .. tostring(a) .. ")."), 1, 0.3, 0.3)
        refreshTree()
    end
end

function CT.Request()
    if ProjectEbonhold.sendToServer then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_CLASS_TREE_DATA, "")
    end
end

if ProjectEbonhold.onEventReceived and ProjectEbonhold.SS then
    ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_CLASS_TREE_DATA, CT.ApplyData)
    ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_CLASS_NODE_RESULT, CT.OnBuyResult)
    ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_CLASS_LEVEL_UP, CT.OnLevelUp)
    ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_CLASS_TREE_PROGRESS, CT.OnProgress)
end
