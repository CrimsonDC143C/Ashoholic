local Addon = select(2, ...)

-- Module: Cooldown Text
-- Displays countdown numbers on action bar cooldowns with color coding

local GCD_THRESHOLD = 2 

local YELLOW_THRESHOLD = 40  -- <= 40% restant -> jaune
local RED_THRESHOLD = 20     -- <= 20% restant -> rouge

local function EnableNumbers(frame)
    if not frame.cdText then
        frame.cdText = frame:CreateFontString(nil, "OVERLAY")
        frame.cdText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
        frame.cdText:SetPoint("CENTER")
    end
end

local activeCooldowns = {}

hooksecurefunc("CooldownFrame_SetTimer", function(cooldown, start, duration, enable)
    if not enable or duration <= 0 or duration <= GCD_THRESHOLD then
        if cooldown.cdText then cooldown.cdText:Hide() end
        activeCooldowns[cooldown] = nil
        return
    end

    EnableNumbers(cooldown)

    activeCooldowns[cooldown] = {
        start = start,
        duration = duration,
    }

    cooldown.cdText:Show()
end)

-- Throttled to 10Hz instead of once per rendered frame.
--
-- The displayed value is whole seconds, so 60 recomputes a second produced the
-- same text 6 times out of 6 -- while running string.format/tostring (a fresh
-- Lua string every time, for every cooldown currently ticking) plus a
-- SetText/SetTextColor pair on each. Combat is exactly when the most cooldowns
-- are running at once, so that garbage rate peaked in the fights where the
-- client can least afford a GC pause. 10Hz is still well above what the eye
-- resolves on a one-second-granularity countdown.
local UPDATE_INTERVAL = 0.1
local sinceUpdate = 0
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(_, elapsed)
    sinceUpdate = sinceUpdate + (elapsed or 0)
    if sinceUpdate < UPDATE_INTERVAL then return end
    sinceUpdate = 0

    local now = GetTime()

    for cooldown, data in pairs(activeCooldowns) do
        local remaining = data.duration - (now - data.start)

        if remaining <= 0 then
            if cooldown.cdText then cooldown.cdText:Hide() end
            activeCooldowns[cooldown] = nil
        else
            -- Format du TEMPS (ce que tu vois)
            local text
            if remaining >= 60 then
                local m = math.floor(remaining / 60)
                local s = math.floor(remaining % 60)
                text = string.format("%d:%02d", m, s)
            else
                text = tostring(math.ceil(remaining))
            end

            -- Calcul du % restant (UNIQUEMENT pour la couleur)
            local percent = (remaining / data.duration) * 100

            -- Couleurs basées sur le POURCENTAGE restant
            if percent <= RED_THRESHOLD then
                cooldown.cdText:SetTextColor(1, 0.2, 0.2) -- rouge
            elseif percent <= YELLOW_THRESHOLD then
                cooldown.cdText:SetTextColor(1, 0.9, 0.2) -- jaune
            else
                cooldown.cdText:SetTextColor(1, 1, 1) -- blanc
            end

            cooldown.cdText:SetText(text)
        end
    end

    -- Garder le swipe visible sur toutes les barres
    local bars = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
    }

    for _, prefix in ipairs(bars) do
        for i = 1, 12 do
            local btn = _G[prefix..i]
            if btn and btn.cooldown then
                btn.cooldown:SetDrawEdge(true)
                btn.cooldown:SetDrawSwipe(true)
            end
        end
    end
end)
