local addonName, addon = ...

local OH = addon.OverflowHealth
if not OH then return end
-- Tiers are checked after rounding so boundary values promote correctly
-- (e.g. 999,950 -> "1.0M", not "1000.0K"). No G tier: billions stay in M
-- (1,713,000,000 -> "1713.0M") to match the client's native big-number
-- text. T still covers uint64-scale values.
local UNITS = {
    { 1e12, "T" },
    { 1e6,  "M" },
    { 1e3,  "K" },
}

local function formatBigNumber(n)
    n = math.floor(n + 0.5)
    for _, unit in ipairs(UNITS) do
        -- Round to one decimal inside this tier, then see if it reaches it
        local v = math.floor(n / unit[1] * 10 + 0.5) / 10
        if v >= 1 then
            return string.format("%.1f%s", v, unit[2])
        end
    end
    return tostring(n)
end

OH.FormatBigNumber = formatBigNumber

-- The cached value is the OVERFLOW: the excess above the clamped client
-- max, so real max = UnitHealthMax + overflow. The server keeps the bar's
-- proportion correct; only the textual values need to be rescaled to the
-- real (uint64) numbers.
local function computeRealHealth(unit, overflow)
    local cur = UnitHealth(unit)
    local max = UnitHealthMax(unit)
    if not max or max == 0 then return 0, 0 end
    local realMax = max + overflow
    return (cur / max) * realMax, realMax
end

-- Real current / max health of a unit, or nil when it has no hidden pool.
-- Public, for other unit frames that want the real numbers.
function OH:GetRealHealth(unit)
    local overflow = self:GetOverflow(unit)
    if not overflow then return nil end
    return computeRealHealth(unit, overflow)
end

-- Every stock unit frame that can show a capped creature: target, focus and
-- the four boss frames (encounter units).
local FRAMES = {
    { "TargetFrame", "target" },
    { "FocusFrame", "focus" },
    { "Boss1TargetFrame", "boss1" },
    { "Boss2TargetFrame", "boss2" },
    { "Boss3TargetFrame", "boss3" },
    { "Boss4TargetFrame", "boss4" },
}

local function getHealthBar(frame)
    return frame and (frame.healthbar or frame.HealthBar) or nil
end

local function updateHealthText(frame, unit)
    if not frame or not unit then return end

    local healthBar = getHealthBar(frame)
    local textString = healthBar and healthBar.TextString
    if not textString then return end

    local overflow = UnitExists(unit) and OH:GetOverflow(unit) or nil
    if not overflow then
        -- Shown at the cap with no answer yet: ask (once per unit, see service).
        OH:Request(unit)
        -- Overflow ended (cache cleared) while we were overriding the text:
        -- hand it back to Blizzard once so our last value doesn't linger.
        if healthBar.overflowTextActive then
            healthBar.overflowTextActive = nil
            TextStatusBar_UpdateTextString(healthBar)
        end
        return
    end

    healthBar.overflowTextActive = true

    -- Respect the user's status-text setting: only rewrite the text when
    -- Blizzard is currently showing it (cvar enabled or mouseover lock).
    if not textString:IsShown() then return end

    local current, realMax = computeRealHealth(unit, overflow)
    textString:SetText(
        formatBigNumber(current) .. " / " .. formatBigNumber(realMax)
    )
end

local function refreshAll()
    for _, entry in ipairs(FRAMES) do
        local frame = _G[entry[1]]
        if frame and frame:IsShown() then
            updateHealthText(frame, entry[2])
        end
    end
end
OH.Refresh = refreshAll

-- Main driver: re-apply our text right after Blizzard rewrites it (health
-- changes, target swaps, mouseover show), so the two never flicker.
hooksecurefunc("TextStatusBar_UpdateTextString", function(bar)
    for _, entry in ipairs(FRAMES) do
        local frame = _G[entry[1]]
        if frame and bar == getHealthBar(frame) then
            updateHealthText(frame, entry[2])
            return
        end
    end
end)

-- Unit tooltip (mouseover, nameplates): add the real numbers under the bar,
-- since a nameplate has no health text of its own.
GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
    local _, unit = tooltip:GetUnit()
    if not unit then return end
    local current, realMax = OH:GetRealHealth(unit)
    if not current then
        OH:Request(unit)
        return
    end
    tooltip:AddLine(HEALTH .. ": " .. formatBigNumber(current) .. " / " .. formatBigNumber(realMax), 1, 1, 1)
    tooltip:Show()
end)

-- Low-frequency fallback: applies an answer that arrived with no health
-- update since. Idle unless a shown frame holds a capped unit or a leftover
-- override to undo. Sends nothing by itself: Request dedups per unit.
local function anyFrameNeedsWork()
    for _, entry in ipairs(FRAMES) do
        local frame = _G[entry[1]]
        local bar = getHealthBar(frame)
        if bar and bar.overflowTextActive then return true end
        if frame and frame:IsShown() and (UnitHealthMax(entry[2]) or 0) >= OH.VISIBLE_HEALTH_CAP then
            return true
        end
    end
    return false
end

local driver = CreateFrame("Frame")
local accum = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    accum = accum + elapsed
    if accum < 0.5 then return end
    accum = 0

    if not anyFrameNeedsWork() then return end
    refreshAll()
end)
