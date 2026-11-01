-- talent_frame.lua -- Three-tree talent window.
--
-- Replaces the stock PlayerTalentFrame for the player's own talents (validated on
-- the mock-up of 2026-09-24, then tuned in game with him the same day). Layout:
--   * title, and a search pill on the right that lights the matching talents;
--   * the unspent points top left;
--   * the five server specs as the character sheet's tabs, hanging under the window;
--   * the class's three trees side by side on their stock background art, the
--     same spacing between talents across and down;
--   * Reset Talents / Glyphs / Pet Talents (hunters) on the left, Cancel / Apply
--     Changes against the right edge.
-- The window edits a PLAN of the build (the plan section below): left click adds a
-- point, right click takes one back - an applied one too - checked here with the
-- frame's own rules, and nothing reaches the server before Apply Changes. Points only
-- added go in as the client's preview points (LearnPreviewTalents). A plan that takes
-- applied points back goes to the server whole (REQUEST_APPLY_TALENT_PLAN), which
-- checks the planned build and sets it in one go - no reset - or refuses it.
-- Specs are previewed before they are switched to: clicking another spec's tab
-- shows its saved build (read-only, asked from the server with REQUEST_SPEC_TALENTS)
-- and the Apply button becomes "Activate"; nothing changes until that is clicked.
-- Glyphs show inside this window (the stock GlyphFrame, borrowed from
-- PlayerTalentFrame and given back when the stock frame opens). Pet talents still
-- open the stock frame. Spec switching, renaming and the reset go through
-- ProjectEbonhold.Spec (spec.lua).

local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
local TF = {}
ProjectEbonhold.TalentFrame = TF

local FRAME_NAME     = "EbonholdTalentFrame"
-- As tall as the screen allows: eleven tiers have to fit with air between them.
-- The width follows from the talent spacing, see BuildTrees.
local FRAME_H        = math.max(640, math.min(780, math.floor((UIParent:GetHeight() or 768) - 40)))
local FRAME_MIN_W    = 700
-- Inside the professions-window frame: 21 px title bar, then the unspent / search
-- row beside the round portrait; the spec tabs hang below the window.
local BOARD_TOP      = 60          -- from the frame's top edge
local BOARD_BOTTOM   = 42          -- from the frame's bottom edge (the button row)
local BOARD_SIDE     = 12
local TREE_HEAD_H    = 56          -- icon, name and rule above the grid
local TREE_W         = 300         -- tree column width, as on the mock-up
local COLUMNS        = 4           -- NUM_TALENT_COLUMNS
-- One pitch for rows AND columns, so talents are as far apart across as down, with
-- 30 px icons (his calls, 2026-09-24). The four columns sit centred in the tree;
-- eleven tiers set the pitch (51 px on a 768 px high UI).
local MAX_PITCH      = 52
local ICON_SIZE      = 30
local MIN_GAP        = 10
local TALENTS_PER_TIER = 5         -- PLAYER_TALENTS_PER_TIER, what the core checks too
local ASSETS         = "Interface\\AddOns\\ProjectEbonhold\\assets\\"
local ARROWS         = "Interface\\TalentFrame\\UI-TalentArrows"
-- Rounded white shapes, tinted in code (make_rounded.py): MASK is the dark band
-- that hides the icon's square corners, RING the thin coloured line on the icon's
-- edge, FILL a plain rounded square.
local MASK           = ASSETS .. "talent_mask"
local RING           = ASSETS .. "talent_ring"
local FILL           = ASSETS .. "talent_fill"
-- Octagon twins (make_octagon.py) for the talents that teach an active spell, the
-- shape the skill tree gives its own special nodes.
local OCT_MASK       = ASSETS .. "talent_oct_mask"
local OCT_RING       = ASSETS .. "talent_oct_ring"
local OCT_FILL       = ASSETS .. "talent_oct_fill"
local RING_SCALE     = 1.25        -- mask/ring canvas = icon + a 10 % band on each side
-- Where the six glyph sockets sit inside GlyphFrame (from their anchors in
-- Blizzard_GlyphUI.xml, 90 px buttons): the rect that gets centred on the board.
local SOCKETS = { x0 = 26, y0 = 71, x1 = 328, y1 = 404 }
local GLYPH_GLOW_TEXTURE = "Interface\\Spellbook\\UI-GlyphFrame-Glow"

-- Stock tree art: four tiles whose visible part is 300 x 331 (Blizzard_TalentUI.xml).
local ART_W, ART_H = 300, 331
local ART_TILES = {
    { suffix = "TopLeft",     x = 0,   y = 0,   w = 256, h = 256, texW = 256, texH = 256 },
    { suffix = "TopRight",    x = 256, y = 0,   w = 44,  h = 256, texW = 64,  texH = 256 },
    { suffix = "BottomLeft",  x = 0,   y = 256, w = 256, h = 75,  texW = 256, texH = 128 },
    { suffix = "BottomRight", x = 256, y = 256, w = 44,  h = 75,  texW = 64,  texH = 128 },
}

-- Arrow heads of UI-TalentArrows: [true] = lit, [false] = grey (TALENT_ARROW_TEXTURECOORDS).
local ARROW_COORDS = {
    top   = { [true] = { 0, 0.5, 0, 0.5 },   [false] = { 0, 0.5, 0.5, 1.0 } },
    left  = { [true] = { 0.5, 1.0, 0, 0.5 }, [false] = { 0.5, 1.0, 0.5, 1.0 } },
    right = { [true] = { 1.0, 0.5, 0, 0.5 }, [false] = { 1.0, 0.5, 0.5, 1.0 } },
}

local C_GOLD   = { 1.00, 0.82, 0.00 }
local C_GREEN  = { 0.10, 1.00, 0.10 }
local C_GREY   = { 0.50, 0.50, 0.50 }
local C_LINE_ON  = { 1.00, 0.82, 0.00 }
local C_LINE_OFF = { 0.45, 0.45, 0.45 }
local UNAVAILABLE_ALPHA = 0.7

local DEFAULT_SPEC_LABELS = { "Primary", "Secondary", "Third", "Fourth", "Fifth" }
local TAB_TEXT_MAX_W = 90

local mainFrame
local trees = {}          -- [tab] = { frame, grid, nodes = { [index] = node }, links = {} }
local specTabs = {}
local searchText = ""
local searchCache = {}    -- ["tab:index"] = lower-case name + description
local built = false
local viewSpec            -- spec index being previewed (not the active one), or nil
local viewRanks           -- [talentId] = rank of viewSpec's saved build, nil while it loads
local glyphMode = false

-- ------------------------------------------------------------- helpers ----

local function TalentGroup()
    return GetActiveTalentGroup(false, false) or 1
end

-- ---------------------------------------------------------------- plan ----
-- The build being edited, kept here rather than in the client's preview points:
-- the client can only take back points it has not applied yet.

local plan = {}           -- ["tab:index"] = planned rank
local planBase = {}       -- ["tab:index"] = applied rank the plan was taken from
local applying            -- { deadline } while the server sets a plan that takes points back

local function Key(node) return node.tab .. ":" .. node.index end

local function AppliedRank(node)
    local _, _, _, _, rank = GetTalentInfo(node.tab, node.index, false, false, TalentGroup())
    return rank or 0
end

local function MaxRank(node)
    local _, _, _, _, _, maxRank = GetTalentInfo(node.tab, node.index, false, false, TalentGroup())
    return maxRank or 0
end

local function PlanRank(node) return plan[Key(node)] or 0 end

local function ResetPlan()
    wipe(plan)
    wipe(planBase)
    for _, tree in pairs(trees) do
        for _, node in pairs(tree.nodes) do
            local rank = AppliedRank(node)
            plan[Key(node)], planBase[Key(node)] = rank, rank
        end
    end
end

-- The applied build moved under the plan (a reset, a spec switch, Apply itself):
-- the plan starts again from it.
local function SyncPlan()
    for _, tree in pairs(trees) do
        for _, node in pairs(tree.nodes) do
            if planBase[Key(node)] ~= AppliedRank(node) then
                ResetPlan()
                return
            end
        end
    end
end

-- Points of the plan given to no talent.
local function UnspentPoints()
    local free = GetUnspentTalentPoints(false, false, TalentGroup()) or 0
    for key, rank in pairs(plan) do free = free + (planBase[key] or 0) - rank end
    return free
end

-- Points the plan changes, added or taken back.
local function PendingPoints()
    local n = 0
    for key, rank in pairs(plan) do n = n + math.abs(rank - (planBase[key] or 0)) end
    return n
end

local function PlanTakesBack()
    for key, rank in pairs(plan) do
        if rank < (planBase[key] or 0) then return true end
    end
    return false
end

-- Planned points in the tiers above `tier` of a tree.
local function PointsAbove(tab, tier)
    local n = 0
    for _, node in pairs(trees[tab].nodes) do
        if node.tier < tier then n = n + PlanRank(node) end
    end
    return n
end

local function PrereqMet(node)
    return not node.prereq or PlanRank(node.prereq) >= MaxRank(node.prereq)
end

-- Same rules as the stock frame: a point left, the tier reached ((tier - 1) * 5
-- points above it) and the prerequisite at full rank.
local function CanAdd(node)
    return UnspentPoints() > 0 and PlanRank(node) < MaxRank(node)
        and PointsAbove(node.tab, node.tier) >= (node.tier - 1) * TALENTS_PER_TIER
        and PrereqMet(node)
end

-- Why a point of this talent has to stay, or nil: a talent learned through it
-- (arrow), or a deeper talent that would lose its tier. A build already short of a
-- tier stays as it is - only the point that keeps a talent reachable is refused.
local function TakeBackBlocker(node)
    for _, other in pairs(trees[node.tab].nodes) do
        if other ~= node and PlanRank(other) > 0 then
            if other.prereq == node then return "required" end
            if other.tier > node.tier then
                local above = PointsAbove(node.tab, other.tier)
                local required = (other.tier - 1) * TALENTS_PER_TIER
                if above >= required and above - 1 < required then return "tier" end
            end
        end
    end
    return nil
end

local function SelectedSpec()
    return ProjectEbonhold.Spec and ProjectEbonhold.Spec.GetSelectedSpec and ProjectEbonhold.Spec.GetSelectedSpec()
end

local function SpecLabel(i)
    local name = ProjectEbonhold.Spec and ProjectEbonhold.Spec.GetSpecName and ProjectEbonhold.Spec.GetSpecName(i)
    if not name or name == "" then return DEFAULT_SPEC_LABELS[i] end
    -- the default names carry a " Specialization" suffix that does not fit a tab
    return (string.gsub(name, " Specialization$", ""))
end

-- One solid-colour segment, horizontal or vertical, on the grid's coordinates
-- (x right, y down from the grid's top-left).
local function PlaceSegment(tex, x1, y1, x2, y2, thickness)
    tex:ClearAllPoints()
    if y1 == y2 then
        tex:SetPoint("TOPLEFT", tex:GetParent(), "TOPLEFT", math.min(x1, x2) - thickness / 2, -(y1 - thickness / 2))
        tex:SetSize(math.abs(x2 - x1) + thickness, thickness)
    else
        tex:SetPoint("TOPLEFT", tex:GetParent(), "TOPLEFT", x1 - thickness / 2, -(math.min(y1, y2) - thickness / 2))
        tex:SetSize(thickness, math.abs(y2 - y1) + thickness)
    end
    tex:Show()
end

-- Crops the four stock tiles to fill w x h without stretching ("cover"), centred.
local function LayoutTreeArt(tree, background, w, h)
    local s = math.max(w / ART_W, h / ART_H)
    local srcW, srcH = w / s, h / s
    local x0, y0 = (ART_W - srcW) / 2, (ART_H - srcH) / 2
    for i, tile in ipairs(ART_TILES) do
        local tex = tree.art[i]
        local ix0, iy0 = math.max(x0, tile.x), math.max(y0, tile.y)
        local ix1, iy1 = math.min(x0 + srcW, tile.x + tile.w), math.min(y0 + srcH, tile.y + tile.h)
        if ix1 > ix0 and iy1 > iy0 then
            tex:SetTexture("Interface\\TalentFrame\\" .. background .. "-" .. tile.suffix)
            tex:SetTexCoord((ix0 - tile.x) / tile.texW, (ix1 - tile.x) / tile.texW,
                            (iy0 - tile.y) / tile.texH, (iy1 - tile.y) / tile.texH)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", tree.frame, "TOPLEFT", (ix0 - x0) * s, -(iy0 - y0) * s)
            tex:SetSize((ix1 - ix0) * s, (iy1 - iy0) * s)
            tex:Show()
        else
            tex:Hide()
        end
    end
end

-- Left-hand lines of a talent's tooltip, read through a hidden tooltip.
local scanTip
local function TooltipLines(tab, index)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "EbonholdTalentScanTooltip", UIParent, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetTalent(tab, index, false, false, TalentGroup(), false)
    local lines = {}
    for n = 1, scanTip:NumLines() do
        local line = _G["EbonholdTalentScanTooltipTextLeft" .. n]
        local text = line and line:GetText()
        if text then table.insert(lines, text) end
    end
    scanTip:Hide()
    return lines
end

-- Name and description of a talent, read once.
local function SearchTextFor(tab, index)
    local key = tab .. ":" .. index
    if searchCache[key] then return searchCache[key] end
    searchCache[key] = string.lower(table.concat(TooltipLines(tab, index), " "))
    return searchCache[key]
end

-- Does the talent teach an active spell? Its tooltip then carries the spell's
-- cast-time line ("Instant", "1.5 sec cast", "Channeled", "Next melee"...); a
-- passive talent's never does. Read at rank 0 too, so unlearned talents get it.
local CAST_EXACT = {}
for _, s in ipairs({ SPELL_CAST_TIME_INSTANT or "Instant", SPELL_CAST_TIME_INSTANT_NO_MANA,
        SPELL_CAST_CHANNELED or "Channeled", SPELL_ON_NEXT_SWING or "Next melee",
        SPELL_ON_NEXT_RANGED or "Next ranged" }) do
    if s then CAST_EXACT[s] = true end
end
-- "%.3g sec cast" / "%.3g min cast": the plain text either side of the number
local CAST_AROUND = {}
for _, fmt in ipairs({ SPELL_CAST_TIME_SEC or "%.3g sec cast", SPELL_CAST_TIME_MIN or "%.3g min cast" }) do
    local s, e = string.find(fmt, "%.3g", 1, true)
    if s then table.insert(CAST_AROUND, { string.sub(fmt, 1, s - 1), string.sub(fmt, e + 1) }) end
end
local function IsActiveTalent(tab, index)
    for _, text in ipairs(TooltipLines(tab, index)) do
        if CAST_EXACT[text] then return true end
        for _, a in ipairs(CAST_AROUND) do
            local pre, post = a[1], a[2]
            if #text > #pre + #post and string.sub(text, 1, #pre) == pre
                    and (#post == 0 or string.sub(text, -#post) == post) then
                return true
            end
        end
    end
    return false
end

-- ------------------------------------------------------------- talents ----

-- The client's requirement lines. Singular and plural come as separate strings
-- (_PLURAL), so a line is recognised by its head ("Requires ") and what it ends
-- on - "<tree> Talents" or the prerequisite's name - not by the whole format.
local TIER_FMT   = TOOLTIP_TALENT_TIER_POINTS or "Requires %d points in %s Talents"
local PREREQ_FMT = TOOLTIP_TALENT_PREREQ or "Requires %d points in %s"
local REQ_HEAD   = string.match(TIER_FMT, "^(.-)%%") or "Requires "
local TIER_TAIL  = string.match(TIER_FMT, "%%s(.*)$") or " Talents"

local function Requirement(fmt, pluralFmt, n, name)
    return string.format((n ~= 1 and pluralFmt) or fmt, n, name or "")
end

local function IsRequirement(text, ending)
    text = string.gsub(string.gsub(text, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
    return ending ~= nil and ending ~= "" and #text > #REQ_HEAD + #ending
        and string.sub(text, 1, #REQ_HEAD) == REQ_HEAD and string.sub(text, -#ending) == ending
end

-- The client writes the "Requires N points in <tree> Talents" and "Requires N points
-- in <talent>" lines from the APPLIED build; the window unlocks from the plan, whose
-- points reach the client only at Apply. Rewrites those lines from the plan: a
-- requirement the plan meets is dropped, one it misses is shown in red.
local function PlanRequirementLines(node)
    local tip, name = GameTooltip, GameTooltip:GetName()
    local tabName = GetTalentTabInfo(node.tab, false, false, TalentGroup())
    local prereqName = node.prereq and GetTalentInfo(node.tab, node.prereq.index, false, false, TalentGroup())
    local tierEnding = tabName and (tabName .. TIER_TAIL)
    local lines, insertAt, clientHas = {}, nil, { tier = false, prereq = false }
    for n = 1, tip:NumLines() do
        local left, right = _G[name .. "TextLeft" .. n], _G[name .. "TextRight" .. n]
        local text = left and left:GetText()
        local kind = text and ((IsRequirement(text, tierEnding) and "tier")
            or (IsRequirement(text, prereqName) and "prereq"))
        if kind then
            clientHas[kind] = true
            insertAt = insertAt or #lines + 1
        else
            local line = { text = text or " ", color = { left:GetTextColor() } }
            if right and right:IsShown() and right:GetText() then
                line.right, line.rightColor = right:GetText(), { right:GetTextColor() }
            end
            table.insert(lines, line)
        end
    end

    local wanted = {}
    if PlanRank(node) < MaxRank(node) then
        if node.prereq and not PrereqMet(node) then
            table.insert(wanted, { kind = "prereq", text = Requirement(PREREQ_FMT,
                TOOLTIP_TALENT_PREREQ_PLURAL, MaxRank(node.prereq), prereqName) })
        end
        local required = (node.tier - 1) * TALENTS_PER_TIER
        if PointsAbove(node.tab, node.tier) < required then
            table.insert(wanted, { kind = "tier", text = Requirement(TIER_FMT,
                TOOLTIP_TALENT_TIER_POINTS_PLURAL, required, tabName) })
        end
    end
    local same = #wanted == (clientHas.tier and 1 or 0) + (clientHas.prereq and 1 or 0)
    for _, w in ipairs(wanted) do same = same and clientHas[w.kind] end
    if same then return end

    -- lines are rebuilt whole: a tooltip line cannot be removed on its own
    insertAt = insertAt or math.min(3, #lines + 1)   -- under the name and the rank
    for i, w in ipairs(wanted) do
        table.insert(lines, insertAt + i - 1,
            { text = w.text, color = { RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b } })
    end
    tip:ClearLines()
    for _, line in ipairs(lines) do
        local c = line.color
        if line.right then
            local rc = line.rightColor
            tip:AddDoubleLine(line.text, line.right, c[1], c[2], c[3], rc[1], rc[2], rc[3])
        else
            tip:AddLine(line.text, c[1], c[2], c[3], true)
        end
    end
end

local function ShowTalentTooltip(node)
    GameTooltip:SetOwner(node.button, "ANCHOR_RIGHT")
    if viewSpec and node.talentId then
        -- a previewed spec: the talent at that build's rank (link ranks are 0-based, -1 = none)
        local rank = viewRanks and viewRanks[node.talentId] or 0
        GameTooltip:SetHyperlink("talent:" .. node.talentId .. ":" .. (rank - 1))
    elseif node.talentId and PlanRank(node) ~= AppliedRank(node) then
        -- the plan changed it: the talent at its planned rank
        GameTooltip:SetHyperlink("talent:" .. node.talentId .. ":" .. (PlanRank(node) - 1))
    else
        GameTooltip:SetTalent(node.tab, node.index, false, false, TalentGroup(), true)
        PlanRequirementLines(node)
    end
    GameTooltip:Show()
end

-- Spellbook slot of the active spell a learned talent teaches: the talent carries
-- its spell's name, so the last non-passive entry of that name is its top rank.
-- nil for passive talents and for talents not learned (or only previewed) yet.
local function TalentSpellSlot(node)
    local name, _, _, _, rank = GetTalentInfo(node.tab, node.index, false, false, TalentGroup())
    if not name or not rank or rank == 0 then return nil end
    local slot
    local i = 1
    while true do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        if spellName == name and not IsPassiveSpell(i, BOOKTYPE_SPELL) then slot = i end
        i = i + 1
    end
    return slot
end

-- Drag an active talent's spell to the action bars, as from the spellbook.
local function OnTalentDragStart(self)
    if viewSpec then return end
    local slot = TalentSpellSlot(self.node)
    if slot then
        PickupSpell(slot, BOOKTYPE_SPELL)
        GameTooltip:Hide()
    end
end

local PLAN_ERRORS = {
    required = "Another talent requires this one.",
    tier     = "A talent deeper in this tree needs this point.",
    combat   = "You can't change applied talents in combat.",
    points   = "Not enough talent points for this build.",
    invalid  = "This build could not be applied.",
    learn    = "Some talent points could not be applied; they are free again.",
    missing  = "Some talent points could not be applied.",
    noanswer = "The server did not answer: nothing was changed.",
}

local function PlanError(reason)
    UIErrorsFrame:AddMessage(PLAN_ERRORS[reason], 1.0, 0.1, 0.1, 1.0)
end

local function OnTalentClick(self, button)
    local node = self.node
    local tg = TalentGroup()
    -- releasing a dragged spell back over its own talent must not spend a point
    if GetCursorInfo() == "spell" then return end
    if IsModifiedClick("CHATLINK") then
        local link = GetTalentLink(node.tab, node.index, false, false, tg, true)
        if link then ChatEdit_InsertLink(link) end
        return
    end
    -- a previewed spec is read-only until it is activated; nothing moves during Apply
    if viewSpec or applying then return end
    if button == "LeftButton" then
        if not CanAdd(node) then return end
        plan[Key(node)] = PlanRank(node) + 1
    elseif button == "RightButton" then
        if PlanRank(node) <= 0 then return end
        local blocker = TakeBackBlocker(node)
        if blocker then
            PlanError(blocker)
            return
        end
        plan[Key(node)] = PlanRank(node) - 1
    end
    PlaySound("igMainMenuOptionCheckBoxOn")
    TF.Refresh()
end

-- The plan as the client's preview points, then sent with LearnPreviewTalents. Talents
-- go in tier by tier, in passes, so a prerequisite on the same tier always lands
-- first. Returns the points the client refused.
local function LearnPlan(target)
    local tg = TalentGroup()
    ResetGroupPreviewTalentPoints(false, tg)
    local list = {}
    for _, tree in pairs(trees) do
        for _, node in pairs(tree.nodes) do table.insert(list, node) end
    end
    table.sort(list, function(a, b)
        if a.tab ~= b.tab then return a.tab < b.tab end
        if a.tier ~= b.tier then return a.tier < b.tier end
        return a.column < b.column
    end)
    local function Have(node)
        local _, _, _, _, rank, _, _, _, previewRank = GetTalentInfo(node.tab, node.index, false, false, tg)
        return math.max(rank or 0, previewRank or 0)
    end
    local progress = true
    while progress do
        progress = false
        for _, node in ipairs(list) do
            local want = target[Key(node)] or 0
            while Have(node) < want do
                local before = Have(node)
                AddPreviewTalentPoints(node.tab, node.index, 1, false, tg)
                if Have(node) <= before then break end
                progress = true
            end
        end
    end
    local missing = 0
    for _, node in ipairs(list) do
        missing = missing + math.max(0, (target[Key(node)] or 0) - Have(node))
    end
    if (GetGroupPreviewTalentPointsSpent(false, tg) or 0) > 0 then
        LearnPreviewTalents(false)
    end
    return missing
end

local applyWatch = CreateFrame("Frame")
applyWatch:Hide()

-- No answer: a server without REQUEST_APPLY_TALENT_PLAN drops it. The plan stays.
applyWatch:SetScript("OnUpdate", function(self)
    if applying and GetTime() > applying.deadline then
        applying = nil
        self:Hide()
        PlanError("noanswer")
        TF.Refresh()
    end
end)

-- "OK" or "FAIL,reason,talentId". On OK the new ranks have already come in (the server
-- sends them first): the plan is taken again from them.
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_TALENT_PLAN_RESULT, function(body)
    if not applying then return end
    applying = nil
    applyWatch:Hide()
    local reason = string.match(body or "", "^FAIL,(%a+)")
    if reason then
        PlanError(PLAN_ERRORS[reason] and reason or "invalid")
        -- "learn": the server took the points back but refused an addition - the build moved
        if reason ~= "learn" then
            TF.Refresh()
            return
        end
    end
    ResetPlan()
    TF.Refresh()
end)

local function ApplyPlan()
    if applying or PendingPoints() == 0 then return end
    if not PlanTakesBack() then
        local target = {}
        for key, rank in pairs(plan) do target[key] = rank end
        if LearnPlan(target) > 0 then PlanError("missing") end
        return
    end
    -- points taken back: the server sets the whole planned build in one go, or refuses it
    if UnitAffectingCombat("player") then
        PlanError("combat")
        return
    end
    local changes = {}
    for _, tree in pairs(trees) do
        for _, node in pairs(tree.nodes) do
            local key = Key(node)
            if node.talentId and plan[key] ~= planBase[key] then
                table.insert(changes, node.talentId .. ":" .. plan[key])
            end
        end
    end
    if #changes == 0 then return end
    applying = { deadline = GetTime() + 5 }
    applyWatch:Show()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_APPLY_TALENT_PLAN, table.concat(changes, ","))
    TF.Refresh()
end

-- The icon cut to a regular octagon. The client has no texture masks, and hiding a
-- square icon's corners under the band left a dark square behind the octagon, so the
-- icon itself is drawn as horizontal strips, each as wide as the octagon at its edge
-- nearer the middle: one tall strip for the straight sides, thin ones down the cut
-- corners. A strip pokes past the octagon by at most its own height, under the band.
-- Returns a stand-in that forwards SetTexture / SetDesaturated / SetVertexColor to
-- every strip.
local function CreateOctagonIcon(b, size)
    local h = size / 2
    local k = math.sqrt(2) * h                 -- |x| + |y| <= k
    local cut = 2 * h - k                      -- height of the cut corners
    local n = math.max(3, math.ceil(cut / 1.5))
    local strips = {}
    local function strip(y0, y1, halfW)
        local t = b:CreateTexture(nil, "BORDER")
        local x0, x1 = h - halfW, h + halfW
        t:SetPoint("TOPLEFT", b, "TOPLEFT", x0, -y0)
        t:SetSize(x1 - x0, y1 - y0)
        t:SetTexCoord(0.07 + 0.86 * x0 / size, 0.07 + 0.86 * x1 / size,
                      0.07 + 0.86 * y0 / size, 0.07 + 0.86 * y1 / size)
        table.insert(strips, t)
    end
    strip(cut, size - cut, h)
    for i = 0, n - 1 do
        local y0, y1 = cut * i / n, cut * (i + 1) / n
        local halfW = math.min(h, k - (h - y1))
        strip(y0, y1, halfW)                               -- top corners
        strip(size - y1, size - y0, halfW)                 -- bottom corners
    end
    return setmetatable({}, { __index = function(_, method)
        return function(_, ...)
            for _, t in ipairs(strips) do t[method](t, ...) end
        end
    end })
end

local function CreateTalentButton(tree, tab, index, size, active)
    local b = CreateFrame("Button", nil, tree.grid)
    b:SetSize(size, size)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon
    if active then
        icon = CreateOctagonIcon(b, size)
    else
        icon = b:CreateTexture(nil, "BORDER")
        icon:SetAllPoints()
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end

    -- dark band OVER the icon's edge: on the rounded border it rounds the icon's
    -- square corners; on the octagon it hides the strips' small steps
    local mask = b:CreateTexture(nil, "ARTWORK")
    mask:SetPoint("CENTER")
    mask:SetSize(size * RING_SCALE, size * RING_SCALE)
    mask:SetTexture(active and OCT_MASK or MASK)
    mask:SetVertexColor(0.03, 0.03, 0.03, active and 1 or 0.95)

    -- thin rounded line hugging the icon (green / gold / grey)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetPoint("CENTER")
    ring:SetSize(size * RING_SCALE, size * RING_SCALE)
    ring:SetTexture(active and OCT_RING or RING)

    -- green glow while the talent holds preview points not applied yet
    local glow = b:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER")
    glow:SetSize(size * 1.9, size * 1.9)
    glow:SetVertexColor(0.3, 1.0, 0.3)
    glow:Hide()

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(active and OCT_FILL or FILL)
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(1, 1, 1, 0.25)

    -- rank badge INSIDE the icon's lower-right corner (his call), on its own frame so
    -- it draws above the ring and the glow
    local badge = CreateFrame("Frame", nil, b)
    badge:SetSize(13, 12)
    badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    badge:SetFrameLevel(b:GetFrameLevel() + 2)
    -- no plate behind the digit (his call): an outlined number only. THICKOUTLINE is
    -- the thickest the client draws, so four black copies 1 px off widen the edge.
    local rankShadows = {}
    for i, off in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        local s = badge:CreateFontString(nil, "ARTWORK")
        s:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
        s:SetTextColor(0, 0, 0, 1)
        s:SetPoint("CENTER", badge, "CENTER", off[1], off[2])
        rankShadows[i] = s
    end
    local rankText = badge:CreateFontString(nil, "OVERLAY")
    rankText:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
    rankText:SetPoint("CENTER", badge, "CENTER", 0, 0)

    local node = {
        tab = tab, index = index, button = b, icon = icon, ring = ring,
        glow = glow, badge = badge, rankText = rankText, rankShadows = rankShadows,
    }
    b.node = node
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", OnTalentClick)
    b:SetScript("OnDragStart", OnTalentDragStart)
    b:SetScript("OnEnter", function(self) ShowTalentTooltip(self.node) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return node
end

-- Prerequisite link: a line (black under-stroke + colour) and an arrow head at
-- the dependent talent. Routes like the stock frame: straight when on the same
-- tier or column, otherwise along the prerequisite's tier then down.
local function CreateLink(tree, from, to, geom)
    local link = { from = from, to = to, segs = {}, under = {} }
    local fx, fy = geom.cx(from.column), geom.cy(from.tier)
    local tx, ty = geom.cx(to.column), geom.cy(to.tier)
    local half = geom.icon * RING_SCALE / 2
    local points
    local arrowSide
    if from.tier == to.tier then
        local dir = (tx > fx) and 1 or -1
        points = { { fx + dir * (half + 2), fy, tx - dir * (half + 8), ty } }
        arrowSide = (dir == 1) and "left" or "right"
    elseif from.column == to.column then
        points = { { fx, fy + half + 2, tx, ty - half - 8 } }
        arrowSide = "top"
    else
        local dir = (tx > fx) and 1 or -1
        points = { { fx + dir * (half + 2), fy, tx, fy }, { tx, fy, tx, ty - half - 8 } }
        arrowSide = "top"
    end
    for i, p in ipairs(points) do
        local under = tree.grid:CreateTexture(nil, "BACKGROUND")
        under:SetTexture(0, 0, 0, 0.9)
        PlaceSegment(under, p[1], p[2], p[3], p[4], 7)
        local seg = tree.grid:CreateTexture(nil, "BORDER")
        PlaceSegment(seg, p[1], p[2], p[3], p[4], 3)
        link.under[i], link.segs[i] = under, seg
    end
    local arrow = tree.grid:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(ARROWS)
    arrow:SetSize(22, 22)
    if arrowSide == "top" then
        arrow:SetPoint("CENTER", tree.grid, "TOPLEFT", tx, -(ty - half - 6))
    elseif arrowSide == "left" then
        arrow:SetPoint("CENTER", tree.grid, "TOPLEFT", tx - half - 6, -ty)
    else
        arrow:SetPoint("CENTER", tree.grid, "TOPLEFT", tx + half + 6, -ty)
    end
    link.arrow, link.arrowSide = arrow, arrowSide
    table.insert(tree.links, link)
end

-- ---------------------------------------------------------------- build ----

local function BuildTrees()
    local numTabs = GetNumTalentTabs(false, false) or 0
    if numTabs == 0 then return false end

    local boardH = FRAME_H - BOARD_TOP - BOARD_BOTTOM
    local gridH = boardH - TREE_HEAD_H - 10

    -- one pitch for rows and columns, from the tallest tree
    local maxTier = 1
    for tab = 1, numTabs do
        for i = 1, GetNumTalents(tab, false, false) do
            local _, _, tier = GetTalentInfo(tab, i, false, false, TalentGroup())
            if tier and tier > maxTier then maxTier = tier end
        end
    end
    local pitch = math.min(MAX_PITCH, math.floor(gridH / maxTier))
    local iconSize = math.min(ICON_SIZE, pitch - MIN_GAP)
    local treeW = math.max(TREE_W, COLUMNS * pitch + 32)
    local padX = (treeW - COLUMNS * pitch) / 2

    -- the window is as wide as the trees need, never narrower than its header row
    local frameW = math.max(FRAME_MIN_W, numTabs * treeW + (numTabs - 1) + 2 * BOARD_SIDE)
    mainFrame:SetWidth(frameW)
    local boardW = frameW - 2 * BOARD_SIDE
    local offsetX = math.floor((boardW - (numTabs * treeW + numTabs - 1)) / 2)

    local geom = {
        icon = iconSize,
        cx = function(col) return padX + (col - 0.5) * pitch end,
        cy = function(tier) return (tier - 0.5) * pitch end,
    }

    for tab = 1, numTabs do
        local name, iconPath, _, background = GetTalentTabInfo(tab, false, false, TalentGroup())
        local tf = CreateFrame("Frame", nil, mainFrame.board)
        tf:SetSize(treeW, boardH)
        tf:SetPoint("TOPLEFT", mainFrame.board, "TOPLEFT", offsetX + (tab - 1) * (treeW + 1), 0)

        local tree = { frame = tf, nodes = {}, links = {}, art = {} }
        for i = 1, #ART_TILES do
            local tex = tf:CreateTexture(nil, "BACKGROUND")
            tex:SetVertexColor(0.62, 0.62, 0.62)
            tree.art[i] = tex
        end
        LayoutTreeArt(tree, background or "MageFire", treeW, boardH)

        -- darken the top (header) and bottom edges
        local topShade = tf:CreateTexture(nil, "BORDER")
        topShade:SetTexture(1, 1, 1, 1)
        topShade:SetPoint("TOPLEFT"); topShade:SetPoint("TOPRIGHT")
        topShade:SetHeight(110)
        topShade:SetGradientAlpha("VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0.75)
        local bottomShade = tf:CreateTexture(nil, "BORDER")
        bottomShade:SetTexture(1, 1, 1, 1)
        bottomShade:SetPoint("BOTTOMLEFT"); bottomShade:SetPoint("BOTTOMRIGHT")
        bottomShade:SetHeight(90)
        bottomShade:SetGradientAlpha("VERTICAL", 0, 0, 0, 0.6, 0, 0, 0, 0)

        -- separator between two trees: the same gold rule as under the tree names,
        -- vertical, fading out at both ends (two halves: a gradient has two stops)
        if tab < numTabs then
            local sepTop = tf:CreateTexture(nil, "OVERLAY")
            sepTop:SetTexture(1, 1, 1, 1)
            sepTop:SetWidth(1)
            sepTop:SetPoint("TOPLEFT", tf, "TOPRIGHT", 0, -16)
            sepTop:SetPoint("BOTTOMLEFT", tf, "RIGHT", 0, 0)
            sepTop:SetGradientAlpha("VERTICAL", 0.79, 0.63, 0.27, 0.75, 0.79, 0.63, 0.27, 0)
            local sepBottom = tf:CreateTexture(nil, "OVERLAY")
            sepBottom:SetTexture(1, 1, 1, 1)
            sepBottom:SetWidth(1)
            sepBottom:SetPoint("TOPLEFT", tf, "RIGHT", 0, 0)
            sepBottom:SetPoint("BOTTOMLEFT", tf, "BOTTOMRIGHT", 0, 16)
            sepBottom:SetGradientAlpha("VERTICAL", 0.79, 0.63, 0.27, 0, 0.79, 0.63, 0.27, 0.75)
        end

        -- header: round icon in the node ring, points on its lower edge, the tree name
        local head = CreateFrame("Frame", nil, tf)
        head:SetSize(treeW, TREE_HEAD_H)
        head:SetPoint("TOP", tf, "TOP", 0, 0)
        tree.head = head
        local tabIcon = head:CreateTexture(nil, "ARTWORK")
        tabIcon:SetSize(28, 28)
        SetPortraitToTexture(tabIcon, iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
        local ring = head:CreateTexture(nil, "OVERLAY")
        ring:SetSize(42, 42)
        ring:SetPoint("CENTER", tabIcon, "CENTER", 0, 0)
        ring:SetTexture(ASSETS .. "progression_bar")
        ring:SetTexCoord(0.214844, 0.322266, 0.314453, 0.427734)
        local title = head:CreateFontString(nil, "OVERLAY")
        title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
        title:SetText(name or "")
        title:SetTextColor(1, 1, 1)
        -- centre icon + name as one group
        local groupW = 28 + 12 + title:GetStringWidth()
        tabIcon:SetPoint("TOPLEFT", head, "TOPLEFT", (treeW - groupW) / 2, -10)
        title:SetPoint("LEFT", tabIcon, "RIGHT", 12, 0)

        -- points box: its own frame, one level up, so it draws OVER the icon ring
        local pts = CreateFrame("Frame", nil, head)
        pts:SetSize(26, 15)
        pts:SetPoint("CENTER", tabIcon, "BOTTOM", 0, -2)
        pts:SetFrameLevel(head:GetFrameLevel() + 2)
        local ptsBg = pts:CreateTexture(nil, "BACKGROUND")
        ptsBg:SetAllPoints()
        ptsBg:SetTexture(FILL)
        ptsBg:SetVertexColor(0, 0, 0, 0.9)
        tree.points = pts:CreateFontString(nil, "OVERLAY")
        tree.points:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        tree.points:SetPoint("CENTER", pts, "CENTER", 0, 0)

        -- the rule under the name: gold in the middle, fading out at both ends.
        -- A texture gradient has only two stops, so it is two halves.
        local ruleL = head:CreateTexture(nil, "ARTWORK")
        ruleL:SetTexture(1, 1, 1, 1)
        ruleL:SetHeight(1)
        ruleL:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 22, 4)
        ruleL:SetPoint("BOTTOMRIGHT", head, "BOTTOM", 0, 4)
        ruleL:SetGradientAlpha("HORIZONTAL", 0.79, 0.63, 0.27, 0, 0.79, 0.63, 0.27, 0.75)
        local ruleR = head:CreateTexture(nil, "ARTWORK")
        ruleR:SetTexture(1, 1, 1, 1)
        ruleR:SetHeight(1)
        ruleR:SetPoint("BOTTOMLEFT", head, "BOTTOM", 0, 4)
        ruleR:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -22, 4)
        ruleR:SetGradientAlpha("HORIZONTAL", 0.79, 0.63, 0.27, 0.75, 0.79, 0.63, 0.27, 0)

        tree.grid = CreateFrame("Frame", nil, tf)
        tree.grid:SetPoint("TOPLEFT", tf, "TOPLEFT", 0, -TREE_HEAD_H - 6)
        tree.grid:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", 0, 4)

        local byCell = {}
        for i = 1, GetNumTalents(tab, false, false) do
            local tName, _, tier, column = GetTalentInfo(tab, i, false, false, TalentGroup())
            if tName then
                local node = CreateTalentButton(tree, tab, i, iconSize, IsActiveTalent(tab, i))
                node.tier, node.column = tier, column
                -- the talent id (Talent.dbc) matches the server's saved builds
                local link = GetTalentLink(tab, i, false, false, TalentGroup())
                node.talentId = link and tonumber(string.match(link, "talent:(%d+)"))
                node.button:SetPoint("CENTER", tree.grid, "TOPLEFT", geom.cx(column), -geom.cy(tier))
                tree.nodes[i] = node
                byCell[tier * 10 + column] = node
            end
        end
        for i, node in pairs(tree.nodes) do
            local pTier, pColumn = GetTalentPrereqs(tab, i, false, false, TalentGroup())
            local from = pTier and byCell[pTier * 10 + pColumn]
            if from then
                node.prereq = from
                CreateLink(tree, from, node, geom)
            end
        end

        trees[tab] = tree
    end
    return true
end

-- --------------------------------------------------------------- refresh ----

local function ApplySearch()
    local q = string.lower(searchText or "")
    for tab, tree in pairs(trees) do
        for i, node in pairs(tree.nodes) do
            -- talents out of reach sit at 70 % (his call); a search miss fades further
            local alpha = node.unavailable and UNAVAILABLE_ALPHA or 1
            if q ~= "" and not string.find(SearchTextFor(tab, i), q, 1, true) then
                alpha = 0.25
            end
            node.button:SetAlpha(alpha)
        end
    end
end

-- Blizzard tab look without PanelTemplates_SelectTab, which disables the button
-- (a selected tab must still take the right-click that renames it).
local function SetTabSelected(t, selected)
    local n = t:GetName()
    for _, part in ipairs({ "Left", "Middle", "Right" }) do
        if selected then
            _G[n .. part]:Hide(); _G[n .. part .. "Disabled"]:Show()
        else
            _G[n .. part]:Show(); _G[n .. part .. "Disabled"]:Hide()
        end
    end
    t:SetNormalFontObject(selected and GameFontHighlightSmall or GameFontNormalSmall)
end

-- Tab width from its text: 20 px caps around a middle piece (done here rather than
-- with PanelTemplates_TabResize, which the collections module replaces with its
-- retail version).
local function ResizeTab(t)
    local n = t:GetName()
    local text = _G[n .. "Text"]
    local textW = text:GetStringWidth()
    -- a long custom name is cut to the cap, like the stock resize does
    text:SetWidth(textW > TAB_TEXT_MAX_W and TAB_TEXT_MAX_W or 0)
    local w = math.max(40, math.min(TAB_TEXT_MAX_W, textW) + 20)
    _G[n .. "Middle"]:SetWidth(w)
    _G[n .. "MiddleDisabled"]:SetWidth(w)
    t:SetWidth(w + 40)
end

local function RefreshSpecTabs()
    local active = SelectedSpec()
    local shown = viewSpec or active
    for i, t in ipairs(specTabs) do
        -- the active spec carries a check, the spec on display is the raised tab
        t:SetText(SpecLabel(i) .. (i == active and " |TInterface\\Buttons\\UI-CheckBox-Check:12:12:0:0|t" or ""))
        ResizeTab(t)
        SetTabSelected(t, i == shown)
    end
end

local function SetButtonState(btn, enabled, text)
    if text then btn:SetText(text) end
    if enabled then
        btn:Enable()
        btn:SetTextColor(1, 1, 1)
    else
        btn:Disable()
        btn:SetTextColor(0.5, 0.5, 0.5)
    end
end

function TF.Refresh()
    if not mainFrame or not mainFrame:IsShown() then return end
    if not built then
        built = BuildTrees()
        if not built then return end
    end
    if not applying then SyncPlan() end

    local tg = TalentGroup()
    local unspent = UnspentPoints()
    if viewSpec then
        mainFrame.unspentBox:Hide()
    else
        mainFrame.unspentBox:Show()
        mainFrame.unspent:SetText(unspent)
        if unspent > 0 then mainFrame.unspent:SetTextColor(unpack(C_GREEN)) else mainFrame.unspent:SetTextColor(0.8, 0.8, 0.8) end
    end

    for tab, tree in pairs(trees) do
        -- ranks: the plan of the active spec, or the previewed spec's saved build
        local ranks, tabPoints = {}, 0
        for i, node in pairs(tree.nodes) do
            local _, _, _, _, rank, maxRank = GetTalentInfo(tab, i, false, false, tg)
            if viewSpec then
                local r = viewRanks and node.talentId and viewRanks[node.talentId] or 0
                ranks[i] = { shown = r, rank = r, max = maxRank }
            else
                ranks[i] = { shown = PlanRank(node), rank = rank, max = maxRank, meets = PrereqMet(node) }
            end
            tabPoints = tabPoints + ranks[i].shown
        end
        tree.points:SetText(tabPoints)

        for i, node in pairs(tree.nodes) do
            local _, iconTexture, tier = GetTalentInfo(tab, i, false, false, tg)
            local r = ranks[i]
            node.icon:SetTexture(iconTexture)
            node.rankText:SetText(r.shown)
            for _, s in ipairs(node.rankShadows) do s:SetText(r.shown) end
            local usable
            if viewSpec then
                usable = r.shown > 0
            else
                local tierUnlocked = (tier - 1) * TALENTS_PER_TIER <= PointsAbove(tab, tier)
                -- no points left: only talents that already hold points stay lit, as the stock frame
                usable = tierUnlocked and r.meets and not (unspent <= 0 and r.shown == 0)
            end
            node.unavailable = not usable
            if usable then
                node.icon:SetDesaturated(false)
                node.icon:SetVertexColor(1, 1, 1)
                local c = (r.shown < r.max) and C_GREEN or C_GOLD
                node.ring:SetVertexColor(c[1], c[2], c[3])
                node.rankText:SetTextColor(c[1], c[2], c[3])
                node.badge:Show()
            else
                node.icon:SetDesaturated(true)
                node.icon:SetVertexColor(0.65, 0.65, 0.65)
                node.ring:SetVertexColor(unpack(C_GREY))
                node.rankText:SetTextColor(unpack(C_GREY))
                if r.shown == 0 then node.badge:Hide() else node.badge:Show() end
            end
            -- glow while the plan changes the talent: green for points added, red for points taken back
            if not viewSpec and r.shown ~= r.rank then
                if r.shown > r.rank then node.glow:SetVertexColor(0.3, 1.0, 0.3) else node.glow:SetVertexColor(1.0, 0.25, 0.2) end
                node.glow:Show()
            else
                node.glow:Hide()
            end
            if GameTooltip:IsOwned(node.button) then ShowTalentTooltip(node) end
        end

        for _, link in ipairs(tree.links) do
            local from = ranks[link.from.index]
            local lit = (from.shown >= from.max) and true or false
            local c = lit and C_LINE_ON or C_LINE_OFF
            for _, seg in ipairs(link.segs) do seg:SetTexture(c[1], c[2], c[3], 1) end
            link.arrow:SetTexCoord(unpack(ARROW_COORDS[link.arrowSide][lit]))
        end
    end

    if glyphMode then
        mainFrame.applyBtn:Hide()
        mainFrame.cancelBtn:Hide()
    elseif viewSpec then
        -- previewing another spec: Apply activates it, Cancel goes back to the active one
        mainFrame.applyBtn:Show()
        mainFrame.cancelBtn:Show()
        SetButtonState(mainFrame.applyBtn, viewRanks ~= nil, "Activate " .. SpecLabel(viewSpec))
        SetButtonState(mainFrame.cancelBtn, true, "Back")
    else
        mainFrame.applyBtn:Show()
        mainFrame.cancelBtn:Show()
        local pending = PendingPoints()
        if applying then
            SetButtonState(mainFrame.applyBtn, false, "Applying...")
            SetButtonState(mainFrame.cancelBtn, false, "Cancel")
        else
            SetButtonState(mainFrame.applyBtn, pending > 0, pending > 0 and ("Apply Changes (" .. pending .. ")") or "Apply Changes")
            SetButtonState(mainFrame.cancelBtn, pending > 0, "Cancel")
        end
    end

    -- Glyphs always available, at any level; pet talents only for a talented pet.
    mainFrame.glyphBtn:Show()
    mainFrame.glyphBtn:SetText(glyphMode and (TALENTS or "Talents") or (GLYPHS or "Glyphs"))
    local _, isHunterPet = HasPetUI()
    if isHunterPet and (GetNumTalentGroups(false, true) or 0) > 0 then mainFrame.petBtn:Show() else mainFrame.petBtn:Hide() end

    RefreshSpecTabs()
    ApplySearch()
end

-- ---------------------------------------------------------- spec preview ----

local function ShowSpec(index)
    if not index or index == SelectedSpec() then
        viewSpec, viewRanks = nil, nil
    else
        viewSpec, viewRanks = index, nil
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SPEC_TALENTS, tostring(index))
    end
    TF.Refresh()
end

-- "specIndex|talentId:rank,talentId:rank,..." (rank 1-based)
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_SPEC_TALENTS, function(body)
    local spec, list = string.match(body or "", "^(%d+)|(.*)$")
    spec = tonumber(spec)
    if not spec or spec ~= viewSpec then return end
    local ranks = {}
    for id, rank in string.gmatch(list or "", "(%d+):(%d+)") do
        ranks[tonumber(id)] = tonumber(rank)
    end
    viewRanks = ranks
    TF.Refresh()
end)

local function ActivateViewedSpec()
    local spec = viewSpec
    if not spec or not viewRanks or not ProjectEbonhold.Spec then return end
    -- the plan belongs to the spec being left
    ResetGroupPreviewTalentPoints(false, TalentGroup())
    ResetPlan()
    viewSpec, viewRanks = nil, nil
    ProjectEbonhold.Spec.SelectSpec(spec)
    TF.Refresh()
end

-- --------------------------------------------------------------- glyphs ----

-- The stock GlyphFrame lives on PlayerTalentFrame; while glyphs show here it is
-- borrowed onto the board, and handed back when the stock frame opens.
-- Only the six socket circles show here (his call): the stock parchment, its title
-- and its flash go while the frame is ours (on = true), and come back for the stock
-- frame. The flash is emptied rather than hidden: its pulse animation re-shows it.
local function ShowGlyphArt(show)
    local bg, glow = GlyphFrameBackground, GlyphFrameGlow
    if bg then
        if show then bg:Show() else bg:Hide() end
    end
    if glow then
        glow:SetTexture(show and GLYPH_GLOW_TEXTURE or nil)
    end
    if GlyphFrameTitleText then
        if show then GlyphFrameTitleText:Show() else GlyphFrameTitleText:Hide() end
    end
end

local function ReturnGlyphFrame()
    if not GlyphFrame or not PlayerTalentFrame or GlyphFrame:GetParent() == PlayerTalentFrame then return end
    local onGlyphTab = PanelTemplates_GetSelectedTab(PlayerTalentFrame) == (GLYPH_TALENT_TAB or 4)
    ShowGlyphArt(true)
    GlyphFrame:SetScale(1)
    GlyphFrame:SetParent(PlayerTalentFrame)
    GlyphFrame:ClearAllPoints()
    GlyphFrame:SetAllPoints()
    GlyphFrame:SetFrameStrata(PlayerTalentFrame:GetFrameStrata())
    GlyphFrame:SetFrameLevel(PlayerTalentFrame:GetFrameLevel() + 4)
    if onGlyphTab then GlyphFrame:Show() else GlyphFrame:Hide() end
end

local function SetGlyphMode(on)
    if on then
        TalentFrame_LoadUI()
        GlyphFrame_LoadUI()
        if not GlyphFrame then return end
        -- the glyph slots read their spec off PlayerTalentFrame, shown or not
        if PlayerTalentFrame and not PlayerTalentFrame:IsShown() then
            PlayerTalentFrame.talentGroup = TalentGroup()
            PlayerTalentFrame.pet = false
        end
        viewSpec, viewRanks = nil, nil
        GlyphFrame:SetParent(mainFrame.board)
        ShowGlyphArt(false)
        -- the six circles as big as the board allows, centred on it (SetPoint offsets
        -- are in the scaled frame's own units)
        local scale = math.min(1.5, (mainFrame.board:GetHeight() - 60) / (SOCKETS.y1 - SOCKETS.y0))
        GlyphFrame:SetScale(scale)
        GlyphFrame:ClearAllPoints()
        GlyphFrame:SetPoint("TOPLEFT", mainFrame.board, "CENTER",
            -(SOCKETS.x0 + SOCKETS.x1) / 2, (SOCKETS.y0 + SOCKETS.y1) / 2)
        GlyphFrame:SetFrameStrata(mainFrame:GetFrameStrata())
        GlyphFrame:SetFrameLevel(mainFrame.board:GetFrameLevel() + 10)
        GlyphFrame:Show()
        if GlyphFrame_Update then GlyphFrame_Update() end
    elseif GlyphFrame and GlyphFrame:GetParent() == mainFrame.board then
        GlyphFrame:Hide()
    end
    glyphMode = on and true or false
    -- the parchment lies on the class art: talents and headers go, the art dims
    for _, tree in pairs(trees) do
        if glyphMode then
            tree.head:Hide(); tree.grid:Hide()
        else
            tree.head:Show(); tree.grid:Show()
        end
        local v = glyphMode and 0.3 or 0.62
        for _, tex in ipairs(tree.art) do tex:SetVertexColor(v, v, v) end
    end
    if mainFrame.search then
        if glyphMode then mainFrame.search:Hide() else mainFrame.search:Show() end
    end
    TF.Refresh()
end

-- ------------------------------------------------------------ the frame ----

local function OnStockFrameShown()
    mainFrame:Hide()
    ReturnGlyphFrame()
end

local function OpenPetTalents()
    mainFrame:Hide()
    TalentFrame_LoadUI()
    if PlayerTalentFrame_Open then PlayerTalentFrame_Open(true, GetActiveTalentGroup(false, true)) end
end

-- The professions window's look (trade_skill_frame.lua, itself the echo journal's
-- frame): ezCollectionsPortraitFrameTemplateNoCloseButton (rock background, border,
-- round portrait, title bar) and a marble InsetFrameTemplate around the board.
-- Built on first show, the templates come from the collections module. Explicit
-- levels as there: frame (N), inset (N+1), everything else (N+2) - at equal levels
-- the client does not promise which draws on top.
local function CreateChrome()
    if mainFrame.chrome then return end
    local ok, chrome = pcall(CreateFrame, "Frame", nil, mainFrame, "ezCollectionsPortraitFrameTemplateNoCloseButton")
    if not ok or not chrome then
        -- templates missing: plain dialog border so the window still reads as one
        mainFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32, tile = true, tileSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        mainFrame.chrome = mainFrame
        return
    end
    chrome:SetAllPoints(mainFrame)
    chrome.TitleText:SetText(TALENTS or "Talents")
    SetPortraitTexture(chrome.portrait, "player")
    local ok2, inset = pcall(CreateFrame, "Frame", nil, chrome, "InsetFrameTemplate")
    if ok2 and inset then
        inset:SetPoint("TOPLEFT", mainFrame.board, "TOPLEFT", -3, 3)
        inset:SetPoint("BOTTOMRIGHT", mainFrame.board, "BOTTOMRIGHT", 3, -3)
    end
    local base = mainFrame:GetFrameLevel()
    chrome:SetFrameLevel(base)
    if ok2 and inset then inset:SetFrameLevel(base + 1) end
    for _, child in ipairs({ mainFrame:GetChildren() }) do
        if child ~= chrome then child:SetFrameLevel(math.max(child:GetFrameLevel(), base + 2)) end
    end
    mainFrame.chrome = chrome
end

-- The echo journal's search box (ezCollectionsSearchBoxTemplate: magnifier, grey
-- placeholder, clear button) - his rule: every addon search bar uses this one.
-- Built on first show because the template comes from the collections module,
-- later in the TOC; the plain 3.3.5 box is the fallback if it is missing.
local function CreateSearchBox()
    if mainFrame.search then return end
    local ok, box = pcall(CreateFrame, "EditBox", "EbonholdTalentSearchBox", mainFrame, "ezCollectionsSearchBoxTemplate")
    if not ok or not box then
        box = CreateFrame("EditBox", "EbonholdTalentSearchBox", mainFrame, "InputBoxTemplate")
    end
    box:SetSize(170, 22)
    box:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -14, -30)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    -- HookScript: the template runs its own OnTextChanged (placeholder, clear button)
    box:HookScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        ApplySearch()
    end)
    box:HookScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    if glyphMode then box:Hide() end
    mainFrame.search = box
end

local function CreateSpecTab(index)
    -- the character sheet's tabs (patch-D art), hanging under the window as on the
    -- character sheet (his pick, 2026-09-24, variant C of the tab previews)
    local t = CreateFrame("Button", FRAME_NAME .. "SpecTab" .. index, mainFrame, "CharacterFrameTabButtonTemplate")
    if index == 1 then
        t:SetPoint("TOPLEFT", mainFrame, "BOTTOMLEFT", 14, 6)
    else
        t:SetPoint("LEFT", specTabs[index - 1], "RIGHT", -16, 0)
    end
    t:SetHeight(32)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- the template's OnShow / OnEvent resize through CharacterFrame helpers: ours instead
    t:SetScript("OnShow", function(self) ResizeTab(self) end)
    t:SetScript("OnEvent", function(self) ResizeTab(self) end)
    t:SetScript("OnClick", function(self, button)
        local spec = ProjectEbonhold.Spec
        if not spec then return end
        if button == "RightButton" then
            spec.EditSpecName(index)
            return
        end
        PlaySound("igCharacterInfoTab")
        if glyphMode then SetGlyphMode(false) end
        ShowSpec(index)
    end)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ProjectEbonhold.Spec and ProjectEbonhold.Spec.GetSpecName(index) or SpecLabel(index), 1, 1, 1)
        if index == SelectedSpec() then
            GameTooltip:AddLine("Active specialization.", 0.1, 1, 0.1, true)
        else
            GameTooltip:AddLine("Left-click to preview it, then activate it from the bottom bar.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine("Right-click to rename it.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    specTabs[index] = t
end

local function CreateMainFrame()
    mainFrame = CreateFrame("Frame", FRAME_NAME, UIParent)
    mainFrame:SetSize(FRAME_MIN_W + 60, FRAME_H)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetFrameLevel(100)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:Hide()

    -- the frame's look (the professions window's) is built on first show, see CreateChrome
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    -- same place as the button of ezCollectionsPortraitFrameTemplate
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 4, 5)

    -- the search box is built on first show (CreateSearchBox): its template is
    -- defined by the collections module, which loads after this file

    -- the board holding the trees (a marble inset frames it, see CreateChrome)
    local board = CreateFrame("Frame", nil, mainFrame)
    board:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", BOARD_SIDE, -BOARD_TOP)
    board:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -BOARD_SIDE, BOARD_BOTTOM)
    local boardBg = board:CreateTexture(nil, "BACKGROUND")
    boardBg:SetAllPoints()
    boardBg:SetTexture(0, 0, 0, 1)
    mainFrame.board = board

    for i = 1, (ProjectEbonhold.Spec and ProjectEbonhold.Spec.MAX_SPECS or 5) do
        CreateSpecTab(i)
    end

    -- unspent points (top left, on the title row: the tab row belongs to the specs)
    local unspentBox = CreateFrame("Frame", nil, mainFrame)
    unspentBox:SetSize(150, 22)
    -- right of the round portrait, which reaches x = 55
    unspentBox:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 64, -30)
    local unspentLabel = unspentBox:CreateFontString(nil, "OVERLAY")
    unspentLabel:SetFont("Fonts\\FRIZQT__.TTF", 12)
    unspentLabel:SetPoint("LEFT", unspentBox, "LEFT", 0, 0)
    unspentLabel:SetText("Unspent Talents")
    unspentLabel:SetTextColor(0.9, 0.86, 0.75)
    local unspentBg = unspentBox:CreateTexture(nil, "ARTWORK")
    unspentBg:SetSize(36, 22)
    unspentBg:SetPoint("LEFT", unspentLabel, "RIGHT", 8, 0)
    unspentBg:SetTexture(FILL)
    unspentBg:SetVertexColor(0, 0, 0, 0.85)
    mainFrame.unspent = unspentBox:CreateFontString(nil, "OVERLAY")
    mainFrame.unspent:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    mainFrame.unspent:SetPoint("CENTER", unspentBg, "CENTER", 0, 0)
    mainFrame.unspentBox = unspentBox

    -- bottom bar
    local applyBtn = utils.CreateSimpleCustomButton(mainFrame, "Apply Changes", function()
        if viewSpec then
            ActivateViewedSpec()
        else
            ApplyPlan()
        end
    end, 170, 30)
    mainFrame.applyBtn = applyBtn

    local cancelBtn = utils.CreateSimpleCustomButton(mainFrame, "Cancel", function()
        if viewSpec then
            ShowSpec(nil)
        elseif not applying then
            ResetPlan()
            TF.Refresh()
        end
    end, 90, 30)
    -- Apply / Cancel sit against the right edge (his call, 2026-09-24); swapped on 2026-10-22
    -- after player feedback: Cancel takes the edge, Apply Changes sits on its left
    cancelBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -20, 8)
    applyBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
    mainFrame.cancelBtn = cancelBtn

    local resetBtn = utils.CreateSimpleCustomButton(mainFrame, "Reset Talents", function()
        if ProjectEbonhold.Spec and ProjectEbonhold.Spec.ConfirmResetTalents then
            ProjectEbonhold.Spec.ConfirmResetTalents()
        end
    end, 110, 30)
    resetBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 20, 8)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset Talents", 1, 1, 1)
        GameTooltip:AddLine("Refunds every talent point of the active specialization.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local glyphBtn = utils.CreateSimpleCustomButton(mainFrame, GLYPHS or "Glyphs", function()
        SetGlyphMode(not glyphMode)
    end, 90, 30)
    glyphBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
    mainFrame.glyphBtn = glyphBtn

    local petBtn = utils.CreateSimpleCustomButton(mainFrame, "Pet Talents", OpenPetTalents, 100, 30)
    petBtn:SetPoint("LEFT", glyphBtn, "RIGHT", 8, 0)
    mainFrame.petBtn = petBtn

    tinsert(UISpecialFrames, FRAME_NAME)

    mainFrame:SetScript("OnShow", function()
        PlaySound("TalentScreenOpen")
        SetButtonPulse(TalentMicroButton, 0, 1)
        -- one talent window at a time
        if PlayerTalentFrame and PlayerTalentFrame:IsShown() then HideUIPanel(PlayerTalentFrame) end
        UpdateMicroButtons()
        CreateChrome()
        CreateSearchBox()
        TF.Refresh()
    end)
    mainFrame:SetScript("OnHide", function()
        PlaySound("TalentScreenClose")
        if mainFrame.search then mainFrame.search:ClearFocus() end
        -- reopen on the active spec's talents
        viewSpec, viewRanks = nil, nil
        if glyphMode then SetGlyphMode(false) end
        UpdateMicroButtons()
    end)

    mainFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    mainFrame:RegisterEvent("PREVIEW_TALENT_POINTS_CHANGED")
    mainFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
    mainFrame:RegisterEvent("PLAYER_LEVEL_UP")
    mainFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    mainFrame:RegisterEvent("UNIT_PET")
    mainFrame:RegisterEvent("ADDON_LOADED")
    mainFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "ADDON_LOADED" then
            -- the stock frame (pet talents) and this one never show together
            if arg1 == "Blizzard_TalentUI" and PlayerTalentFrame then
                PlayerTalentFrame:HookScript("OnShow", OnStockFrameShown)
            end
            return
        end
        if event == "PLAYER_TALENT_UPDATE" then
            -- descriptions change with the rank; read them again on the next search
            wipe(searchCache)
        end
        TF.Refresh()
    end)
end

-- ---------------------------------------------------------------- public ----

function TF.Toggle()
    if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
end

function TF.IsShown()
    return mainFrame and mainFrame:IsShown()
end

--- Opens the window on the glyphs, or closes it when they already show.
function TF.ToggleGlyphs()
    if mainFrame:IsShown() and glyphMode then
        mainFrame:Hide()
        return
    end
    if not mainFrame:IsShown() then mainFrame:Show() end
    if not glyphMode then SetGlyphMode(true) end
end

CreateMainFrame()

-- Blizzard_TalentUI is load-on-demand; if something loaded it already, hook it now.
if PlayerTalentFrame then
    PlayerTalentFrame:HookScript("OnShow", OnStockFrameShown)
end

if ProjectEbonhold.Spec and ProjectEbonhold.Spec.AddListener then
    ProjectEbonhold.Spec.AddListener(function()
        if mainFrame:IsShown() then TF.Refresh() end
    end)
end

-- The talent key binding and anything else calling ToggleTalentFrame() open this
-- window, at any level (the stock one returns below SHOW_TALENT_LEVEL). The glyph
-- binding and a glyph being used (USE_GLYPH -> OpenGlyphFrame) open it on the glyphs.
ToggleTalentFrame = TF.Toggle
ToggleGlyphFrame = TF.ToggleGlyphs
OpenGlyphFrame = function()
    if not (mainFrame:IsShown() and glyphMode) then TF.ToggleGlyphs() end
end

-- UpdateMicroButtons only knows PlayerTalentFrame: keep the talent button pushed
-- while this window is open.
hooksecurefunc("UpdateMicroButtons", function()
    if TalentMicroButton and mainFrame:IsShown() then
        TalentMicroButton:SetButtonState("PUSHED", 1)
    end
end)
