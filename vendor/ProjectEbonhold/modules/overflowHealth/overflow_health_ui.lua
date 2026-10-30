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
    if TargetFrame and TargetFrame:IsShown() then
        updateHealthText(TargetFrame, "target")
    end
    if FocusFrame and FocusFrame:IsShown() then
        updateHealthText(FocusFrame, "focus")
    end
end

-- Main driver: re-apply our text right after Blizzard rewrites it (health
-- changes, target swaps, mouseover show), so the two never flicker.
hooksecurefunc("TextStatusBar_UpdateTextString", function(bar)
    if bar == getHealthBar(TargetFrame) then
        updateHealthText(TargetFrame, "target")
    elseif bar == getHealthBar(FocusFrame) then
        updateHealthText(FocusFrame, "focus")
    end
end)

-- Low-frequency fallback: catches the first application after the server
-- pushes overflow data when no health update has fired yet.
local function anyOverrideActive()
    local tb, fb = getHealthBar(TargetFrame), getHealthBar(FocusFrame)
    return (tb and tb.overflowTextActive) or (fb and fb.overflowTextActive)
end

local driver = CreateFrame("Frame")
local accum = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    accum = accum + elapsed
    if accum < 0.5 then return end
    accum = 0

    -- Idle unless there is overflow data or a leftover override to undo
    if next(OH.cache) == nil and not anyOverrideActive() then return end
    refreshAll()
end)
