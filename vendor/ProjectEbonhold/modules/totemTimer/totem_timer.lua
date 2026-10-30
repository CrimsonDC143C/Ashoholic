-- totem_timer.lua -- keep the totem bar's cooldown swipe honest when the server
-- extends a totem's remaining duration (the Firekeeper echo: each Lava Burst
-- feeds the Fire Elemental's totem).
--
-- Why this exists: SMSG_TOTEM_CREATED carries NO start-time field -- the client
-- stamps "receipt = now" on every packet -- so when the server re-sends the
-- packet with the new remaining duration (Totem::SendTotemTimer), the stock
-- TotemButton_Update call restarts its CooldownFrame swipe fully dark, reading
-- as "expired" right after every extension. The numeric countdown
-- (GetTotemTimeLeft, computed C-side) is always correct; only the swipe lies.
--
-- Fix: re-issue CooldownFrame_SetTimer anchored to the LONGEST duration seen
-- for the current totem: startTime = now - (maxDuration - remaining). The
-- swipe then shows true progress across refreshes, and remaining can never
-- exceed maxDuration (the server caps extensions at the totem's base
-- duration), so the computed elapsed never goes negative. Tracked per totem
-- NAME so replacing a totem (different name, or the slot emptying) resets the
-- anchor; a same-name recast sends duration == base == maxDuration, which is
-- a correct full swipe on its own. Stock single-packet totems never take the
-- rescale branch in a visible way (maxDuration == duration -> identical call).
--
-- Shipped as an addon hook rather than a FrameXML override: the locale MPQs
-- outrank base-data patches for Interface\FrameXML files on this client, so a
-- patched TotemFrame.lua in a base patch never loads -- the addon always does.

-- Load/hook probes (kept cheap; used by /run diagnostics in the field):
--   /run print(EBH_TOTEM_TIMER_LOADED, EBH_TOTEM_TIMER_HOOKED, EBH_TOTEM_TIMER_FIRED)
EBH_TOTEM_TIMER_LOADED = true;

local function EbonholdTotemSwipeFix(button, startTime, duration, icon)
    EBH_TOTEM_TIMER_FIRED = true;
    local buttonCooldown = _G[button:GetName() .. "IconCooldown"];
    if ( not buttonCooldown ) then
        return;
    end

    if ( duration and duration > 0 ) then
        local _, totemName = GetTotemInfo(button.slot);
        if ( button.ebhMaxDuration == nil or button.ebhMaxDurationName ~= totemName
             or duration > button.ebhMaxDuration ) then
            button.ebhMaxDuration = duration;
            button.ebhMaxDurationName = totemName;
        end
        button.ebhSwipeEnd = nil; -- force the tick below to (re)program the swipe
    else
        button.ebhMaxDuration = nil;
        button.ebhMaxDurationName = nil;
        button.ebhSwipeEnd = nil;
    end
end

-- The real corrector. PLAYER_TOTEM_UPDATE does NOT fire when the server refreshes the
-- duration of an already-placed totem (verified in the field: the numeric countdown moved
-- per extension while the swipe ran its original summon-time program untouched -- the text
-- is driven by this very per-frame poll, not by the event). So the swipe must be corrected
-- from the same poll: re-program it whenever the observed end-time drifts from what the
-- swipe was last programmed with (> 1.25 s absorbs integer-second jitter of
-- GetTotemTimeLeft; successive small extensions accumulate drift and correct within a few
-- casts).
local function EbonholdTotemSwipeTick(button, elapsed)
    local slot = button.slot;
    if ( not slot or slot == 0 ) then
        return;
    end
    local timeLeft = GetTotemTimeLeft(slot);
    if ( not timeLeft or timeLeft <= 0 ) then
        return;
    end

    local maxDur = button.ebhMaxDuration;
    if ( not maxDur ) then
        local _, _, _, duration = GetTotemInfo(slot);
        maxDur = (duration and duration > 0) and duration or timeLeft;
        button.ebhMaxDuration = maxDur;
    end
    if ( timeLeft > maxDur ) then
        maxDur = timeLeft;
        button.ebhMaxDuration = maxDur;
    end

    local endTime = GetTime() + timeLeft;
    if ( not button.ebhSwipeEnd or math.abs(endTime - button.ebhSwipeEnd) > 1.25 ) then
        button.ebhSwipeEnd = endTime;
        local buttonCooldown = _G[button:GetName() .. "IconCooldown"];
        if ( buttonCooldown ) then
            buttonCooldown:SetCooldown(0, 0);
            CooldownFrame_SetTimer(buttonCooldown, GetTime() - (maxDur - timeLeft), maxDur, 1);
        end
    end
end

hooksecurefunc("TotemButton_Update", EbonholdTotemSwipeFix);
hooksecurefunc("TotemButton_OnUpdate", EbonholdTotemSwipeTick);
EBH_TOTEM_TIMER_HOOKED = true;
