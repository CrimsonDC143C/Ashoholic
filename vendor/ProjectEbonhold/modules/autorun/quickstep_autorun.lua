-- quickstep_autorun.lua -- auto-run keeps going after Quickstep (101770).
--
-- Why this exists: Quickstep moves the player with a server spline (it follows the
-- ground step by step), and the client drops auto-run whenever the server moves its
-- player that way. Auto-run is client input state only: no packet can give it back.
--
-- Fix: the client DLL (ebonhold.dll, autorun_client.h) exposes the auto-run bit of
-- CGInputControl. The bit is sampled every frame; when a Quickstep goes off while
-- auto-run was on, the dash is watched for a short window and auto-run is started
-- again as soon as the player stands still.
--
-- 2026-10-22: the first version resumed once, 0.35 s after the cast. With some latency
-- the spline was still running at that moment and dropped auto-run a second time, so
-- auto-run still stopped. Now the resume waits for the player to really stop (speed 0),
-- and tries again if the end of the dash clears it once more.
--
-- Without the DLL functions (older ebonhold.dll) this does nothing.
--   /run print(EbonholdIsAutoRunning and EbonholdIsAutoRunning())

local QUICKSTEP_SPELL = 101770;
local FIRST_CHECK = 0.15;   -- the dash itself lasts ~0.2 s (25 yd at 126 yd/s)
local WATCH_WINDOW = 1.2;   -- covers the dash plus a laggy spline packet
local MAX_RESUMES = 3;

local quickstepName;
local wasAutoRunning = false;
local watchStart, watchEnd;
local resumes = 0;

local frame = CreateFrame("Frame");

local function StopWatching()
    watchStart = nil;
    watchEnd = nil;
    resumes = 0;
end

frame:SetScript("OnUpdate", function()
    if ( not EbonholdIsAutoRunning ) then
        return;
    end

    if ( watchEnd ) then
        local now = GetTime();
        if ( now >= watchEnd or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") ) then
            StopWatching();
        elseif ( now >= watchStart and GetUnitSpeed("player") == 0 ) then
            -- Standing still inside the window: the dash is over and auto-run was lost
            -- (or its bit is left set on a stopped player, which Resume also handles).
            if ( resumes < MAX_RESUMES ) then
                resumes = resumes + 1;
                EbonholdResumeAutoRun();
                watchStart = now + FIRST_CHECK; -- let the restart take effect before checking again
            else
                StopWatching();
            end
        end
        return;
    end

    wasAutoRunning = EbonholdIsAutoRunning() ~= nil;
end);

-- 3.3.5 args: unit, spell name, rank (the spell id only came later), so the name is
-- what is compared.
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED");
frame:SetScript("OnEvent", function(self, event, unit, spellName)
    if ( unit ~= "player" or not EbonholdIsAutoRunning ) then
        return;
    end
    quickstepName = quickstepName or GetSpellInfo(QUICKSTEP_SPELL);
    if ( spellName ~= quickstepName ) then
        return;
    end
    if ( wasAutoRunning or EbonholdIsAutoRunning() ) then
        local now = GetTime();
        watchStart = now + FIRST_CHECK;
        watchEnd = now + WATCH_WINDOW;
        resumes = 0;
    end
end);
