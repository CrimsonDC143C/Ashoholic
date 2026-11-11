-- Guided tour factory: zone-by-zone walkthrough (next/next/got-it) built on
-- GlowBoxTemplate. Extracted from the Echo Journal's merged-Echoes-tab tour so
-- any UI (perk prompt, Run HUD, ...) can declare one from a step list.
--
--   local tour = ProjectEbonhold.GuidedTour.Create({
--       parent = function() return someFrame end, -- frame or function; default UIParent
--       dbKey  = "seenSomethingTour",             -- ProjectEbonholdDB once-flag
--       boxBeside = function() return someFrame end, -- optional: keep left boxes clear of it
--       steps  = function() return { { title, text, zone, boxAnchor }, ... } end,
--   })
--   tour:MaybeStart()   -- shows once per dbKey
--   tour:Stop(false)    -- pause without marking seen; resumes from step 1
--
-- Each step drops a gold highlight on one UI zone and a GlowBox beside it.
-- zone() returns one or two regions: the highlight stretches TOPLEFT of the
-- first to BOTTOMRIGHT of the second (or wraps just the first). Steps whose
-- zone is missing/hidden are skipped. boxAnchor = { point, relPoint, x, y }
-- places the GlowBox relative to the highlight. Finishing or closing with the
-- X marks the dbKey seen; a run where no step ever displayed (every zone
-- hidden) does NOT burn the flag.

ProjectEbonhold = ProjectEbonhold or {}
local GuidedTour = {}
ProjectEbonhold.GuidedTour = GuidedTour

-- Custom buttons ship with GameFontNormal (12px): drop 1px so labels breathe
local function ShrinkButtonFont(btn)
    if btn.text then
        local font, size, flags = btn.text:GetFont()
        btn.text:SetFont(font, (size or 12) - 1, flags)
    end
    return btn
end

local Tour = {}
Tour.__index = Tour

-- GlowBoxTemplate names its corner textures "$parentGlowTopLeft"... and hangs the edges on
-- those NAMES: an unnamed box shares them with every other unnamed one, and its border
-- stretches to another (hidden, taller) box's corners. Each box gets its own name.
local boxCount = 0

-- Frames are built lazily on the first displayed step, so a tour can be
-- declared at file load before its parent frame exists.
function Tour:EnsureFrames()
    if self.box then return end
    local parent = self.cfg.parent
    if type(parent) == "function" then parent = parent() end
    parent = parent or UIParent

    local hl = CreateFrame("Frame", nil, parent)
    hl:SetFrameStrata("FULLSCREEN_DIALOG")
    local fill = hl:CreateTexture(nil, "BACKGROUND")
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetVertexColor(1, 0.82, 0, 0.08)
    fill:SetAllPoints(hl)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local t = hl:CreateTexture(nil, "BORDER")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(1, 0.82, 0, 0.9)
        t:SetPoint(edge[1]); t:SetPoint(edge[2])
        if edge[3] then t:SetWidth(edge[3]) else t:SetHeight(edge[4]) end
    end
    self.highlight = hl

    local width = self.cfg.boxWidth or 280
    boxCount = boxCount + 1
    local box = CreateFrame("Frame", "EbonholdGuidedTourBox" .. boxCount, parent, "GlowBoxTemplate")
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:SetFrameLevel(hl:GetFrameLevel() + 10)
    box:SetWidth(width)
    box:EnableMouse(true)

    box.Title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.Title:SetPoint("TOPLEFT", 16, -14)
    box.Title:SetTextColor(1, 0.82, 0)

    box.Text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    box.Text:SetJustifyV("TOP")
    box.Text:SetWidth(width - 32)
    box.Text:SetPoint("TOPLEFT", box.Title, "BOTTOMLEFT", 0, -8)

    box.StepText = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.StepText:SetPoint("BOTTOMLEFT", 16, 16)

    box.NextBtn = ShrinkButtonFont(utils.CreateSimpleCustomButton(box, "Next", nil, 70, 20))
    box.NextBtn:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)

    -- X = skip the rest; like finishing, it never comes back
    local close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 4, 4)
    close:SetScript("OnClick", function() self:Stop(true) end)

    self.box = box
end

function Tour:GetSteps()
    local steps = self.cfg.steps
    if type(steps) == "function" then return steps() end
    return steps
end

function Tour:ShowStep(i)
    local steps = self:GetSteps()
    local step = steps[i]
    if not step then
        self:Stop(true)
        return
    end

    local zoneA, zoneB = step.zone()
    if not zoneA or not zoneA:IsShown() then
        -- zone unavailable (frame hidden, nothing to point at) -- move on
        return self:ShowStep(i + 1)
    end
    zoneB = zoneB or zoneA
     
    self:EnsureFrames()
    self.step = i
    self.shownAny = true

    local pad = step.highlightPad or 5
    self.highlight:ClearAllPoints()
    self.highlight:SetPoint("TOPLEFT", zoneA, "TOPLEFT", -pad, pad)
    self.highlight:SetPoint("BOTTOMRIGHT", zoneB, "BOTTOMRIGHT", pad, -pad)
    self.highlight:Show()

    local box = self.box
    box.Title:SetText(step.title)
    box.Text:SetText(step.text)
    -- a one-step tip (the Run HUD's) needs no "1/1"
    box.StepText:SetText(#steps > 1 and (i .. "/" .. #steps) or "")
    local last = (i == #steps)
    box.NextBtn:SetText(last and "Got it" or "Next")
    box.NextBtn:SetScript("OnClick", function()
        if last then self:Stop(true) else self:ShowStep(i + 1) end
    end)

    box:SetHeight(14 + box.Title:GetStringHeight() + 8
        + box.Text:GetStringHeight() + 12 + 20 + 12)
    box:ClearAllPoints()
    local a = step.boxAnchor
    local x = a[3]
    -- cfg.boxBeside (frame or function): a box hung on the LEFT of a highlight is pushed
    -- further left, past that frame's left edge, so it never covers the frame when the
    -- highlighted zone sits on its right (the Run HUD's shard and resurrection counters).
    local beside = self.cfg.boxBeside
    if type(beside) == "function" then beside = beside() end
    if beside and a[2]:find("LEFT") then
        local hlLeft, frameLeft = self.highlight:GetLeft(), beside:GetLeft()
        if hlLeft and frameLeft and hlLeft > frameLeft then
            x = x - (hlLeft - frameLeft)
        end
    end
    box:SetPoint(a[1], self.highlight, a[2], x, a[4])
    box:Show()
end

function Tour:Start()
    if self.step then return end -- already mid-tour, don't restart on refresh
    self.shownAny = false
    self:ShowStep(1)
end

function Tour:Stop(markSeen)
    self.waiting = nil
    local wasActive = self.step ~= nil
    self.step = nil
    if self.box then self.box:Hide() end
    if self.highlight then self.highlight:Hide() end
    if wasActive and markSeen and self.shownAny and self.cfg.dbKey then
        ProjectEbonholdDB = ProjectEbonholdDB or {}
        ProjectEbonholdDB[self.cfg.dbKey] = true
    end
    if wasActive and self.cfg.onEnd then self.cfg.onEnd(markSeen) end
    if wasActive then
        for _, tour in ipairs(GuidedTour.all) do
            if tour.waiting then
                tour.waiting = nil
                tour:Start()
                if tour.step then break end
            end
        end
        for _, fn in ipairs(GuidedTour.endListeners) do fn(self) end
    end
end

function Tour:IsActive()
    return self.step ~= nil
end

function Tour:HasSeen()
    return (ProjectEbonholdDB and ProjectEbonholdDB[self.cfg.dbKey]) and true or false
end

-- Start once per dbKey: no-op if already seen. One tour on screen at a time: with another
-- one up, this one waits and starts when that one closes (a tour whose zone is gone by then
-- simply does not show, and is not burnt). Returns true while a step is on screen or waiting,
-- so callers can suppress competing hints for the showing.
function Tour:MaybeStart()
    if not self.step and not self:HasSeen() then
        if GuidedTour.AnyActive() then
            self.waiting = true
            return true
        end
        self:Start()
    end
    return self.step ~= nil
end

-- Every tour made here, so a UI that shows tips on its own (the Run HUD's) can wait while
-- another tour is on screen instead of stacking a second GlowBox over it.
GuidedTour.all = {}
GuidedTour.endListeners = {}

function GuidedTour.Create(cfg)
    local tour = setmetatable({ cfg = cfg }, Tour)
    table.insert(GuidedTour.all, tour)
    return tour
end

function GuidedTour.AnyActive()
    for _, tour in ipairs(GuidedTour.all) do
        if tour:IsActive() then return true end
    end
    return false
end

-- -- Bubbles of the bottom bar ---------------------------------------------------
-- 220 wide on buttons 24 apart: any two of them overlap. Only the first one wanted (lowest
-- rank) is on screen, and none while an echo choice is up (the talent bubble covered its
-- button). Their owners keep calling Show and Hide as if alone: a bubble that waits is
-- parked under a hidden frame, so it still says IsShown and comes back by itself.
local barAlerts = {}
local barAlertBlocker
local barAlertHold = CreateFrame("Frame")
barAlertHold:Hide()

local function ArbitrateBarAlerts()
    local active
    if not (barAlertBlocker and barAlertBlocker:IsShown()) then
        for _, a in ipairs(barAlerts) do
            if a.frame:IsShown() then
                active = a.frame
                break
            end
        end
    end
    for _, a in ipairs(barAlerts) do
        local parent = (a.frame == active) and UIParent or barAlertHold
        if a.frame:GetParent() ~= parent then
            a.frame:SetParent(parent)
            a.frame:SetFrameStrata(a.strata)
            a.frame:SetFrameLevel(a.level)
        end
    end
end

GuidedTour.BarAlerts = {}

-- rank: 1 goes first. Echo 1, Talents 2, Skill Tree 3, Dungeons 4.
function GuidedTour.BarAlerts.Add(frame, rank)
    table.insert(barAlerts, { frame = frame, rank = rank,
        strata = frame:GetFrameStrata(), level = frame:GetFrameLevel() })
    table.sort(barAlerts, function(a, b) return a.rank < b.rank end)
    hooksecurefunc(frame, "Show", ArbitrateBarAlerts)
    hooksecurefunc(frame, "Hide", ArbitrateBarAlerts)
    ArbitrateBarAlerts()
end

-- The echo choice. Its frame is created at PLAYER_ENTERING_WORLD.
function GuidedTour.BarAlerts.SetBlocker(frame)
    barAlertBlocker = frame
    hooksecurefunc(frame, "Show", ArbitrateBarAlerts)
    hooksecurefunc(frame, "Hide", ArbitrateBarAlerts)
    ArbitrateBarAlerts()
end

-- fn(tour) runs each time a tour that was on screen closes (finished, X, or paused)
function GuidedTour.OnAnyEnd(fn)
    table.insert(GuidedTour.endListeners, fn)
end
