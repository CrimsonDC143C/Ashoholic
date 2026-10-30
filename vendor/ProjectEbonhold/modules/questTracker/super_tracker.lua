-- super_tracker.lua -- Dragonflight-style "super tracked" quest waypoint.
--
-- Projects the tracked quest's POI into the game world through the client
-- camera (EbonholdWorldToScreen, provided by ebonhold.dll) and draws a
-- floating pin at that spot. When the objective is outside the camera's
-- field of view (off-screen or behind the player), the pin CLAMPS to the
-- screen edge with a directional arrow pointing toward it -- the retail
-- Dragonflight SuperTrackedFrame behavior, retroported to 3.3.5.
--
-- Data flow:
--   quest POI map coords  (QuestPOIGetIconInfo, server quest_poi data)
--     -> world coords     (WorldMapArea.dbc bounds, modules/questTracker/worldmap_data.lua)
--     -> screen NDC       (EbonholdWorldToScreen: camera position/matrix/fov)
--     -> UIParent coords  (clamped into screen insets when outside the POV)
--
-- Manual waypoints (TomTom-style, exact coordinates -- unlike quest POIs,
-- which are the CENTROID of the objective area and therefore approximate):
--   /ebtwp            waypoint at your current position (calibration aid too)
--   /ebtwp 45 67      waypoint at 45%, 67% of the current zone's map
--   /ebtwp clear      remove it (it also auto-clears on arrival)
-- Projection calibration, persisted, applies live (no DLL rebuild needed):
--   /ebtcal           show current X/Y scale factors
--   /ebtcal 1.02      set X (and Y) scale     /ebtcal 1.02 0.98   set both
--   /ebtcal reset     back to 1.0 / 1.0
--
-- Without the DLL functions (vanilla client, no ebonhold.dll) the pin simply
-- never shows; the tracker UI itself keeps working.

local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
local ST = {}
ProjectEbonhold.SuperTracker = ST

-- ------------------------------------------------------------- tunables -----
local REFRESH_INTERVAL = 2.0      -- seconds between POI cache refreshes
local EDGE_INSET_X     = 60       -- clamp margins (UIParent units)
local EDGE_INSET_TOP   = 130      -- keep clear of minimap / buff rows
local EDGE_INSET_BOT   = 100      -- keep clear of action bars
local ONSCREEN_NDC     = 0.95     -- |ndc| below this counts as "inside the POV"
local HIDE_DIST_TEXT   = 15       -- yards: closer than this hides the counter
local PROX_HIDE_DIST   = 10       -- yards: closer than this hides the pin (arrived)
local PROX_SHOW_DIST   = 13       -- yards: farther than this re-shows it (hysteresis)
local PULSE_DIST       = 25       -- yards: closer than this makes the pin pulse
local ARRIVAL_DIST     = 10       -- yards: manual waypoints auto-clear here
local POI_Z_LIFT       = 2.0      -- draw the pin this far above ground height

local ASSETS = "Interface\\AddOns\\ProjectEbonhold\\assets\\"

-- ---------------------------------------------------------------- state -----
local manualQuestID  = nil        -- user-picked via the tracker's pin button
local trackingOff    = false      -- pin toggled off: no waypoint, no auto-pick
local currentQuestID = nil        -- effective target (manual or auto-nearest)
local customWaypoint = nil        -- { wx, wy, wz } -- overrides quest POIs
local poiCache       = {}         -- [questID] = { wx, wy, complete, title }
local poiOrder       = {}         -- questIDs with POIs, watch order
local sinceRefresh   = REFRESH_INTERVAL
local changedCallbacks = {}

local hasDLL = nil                -- lazily resolved (fns register in-world)

local function DLLReady()
    if hasDLL == nil then
        if type(EbonholdWorldToScreen) == "function" then hasDLL = true end
    end
    return hasDLL and true or false
end

-- shares the tracker's on/off option (options panel > Quest Tracker)
local function IsEnabled()
    local svc = _G.ProjectEbonholdOptionsService
    if svc and svc.GetSetting then
        local v = svc:GetSetting("dfQuestTracker")
        if v ~= nil then return v and true or false end
    end
    return true
end

local function DB()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.questTracker = ProjectEbonholdDB.questTracker or {}
    return ProjectEbonholdDB.questTracker
end

local function Msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Ebonhold:|r " .. text)
end

-- --------------------------------------------------------- world helpers ----
local function CurrentZoneBounds()
    local mapName = GetMapInfo()
    if not mapName then return nil end
    local bounds = ProjectEbonhold.WorldMapBounds and ProjectEbonhold.WorldMapBounds[mapName]
    return bounds
end

-- normalized map coords (0..1 from top-left) -> world x/y
local function MapToWorld(bounds, nx, ny)
    local left, right, top, bottom = bounds[1], bounds[2], bounds[3], bounds[4]
    local wy = left + nx * (right - left)
    local wx = top + ny * (bottom - top)
    return wx, wy
end

local function GetPlayerWorld()
    if type(EbonholdGetPlayerPosition) == "function" then
        local x, y, z, facing = EbonholdGetPlayerPosition()
        if x then return x, y, z, facing end
    end
    -- fallback: map position + zone bounds (no Z; outdoor zones only)
    local bounds = CurrentZoneBounds()
    if not bounds then return nil end
    local nx, ny = GetPlayerMapPosition("player")
    if not nx or (nx == 0 and ny == 0) then return nil end
    local wx, wy = MapToWorld(bounds, nx, ny)
    return wx, wy, nil, GetPlayerFacing and GetPlayerFacing() or 0
end

-- QuestPOIGetIconInfo return shape differs across client patches; sniff out
-- the two 0..1 map fractions defensively.
local function GetQuestPOIMapPos(questID)
    if not QuestPOIGetIconInfo then return nil end
    local a, b, c = QuestPOIGetIconInfo(questID)
    if type(a) == "number" and type(b) == "number"
       and a >= 0 and a <= 1 and b >= 0 and b <= 1 then
        return a, b                             -- 3.3.5: posX, posY, objective
    end
    if type(b) == "number" and type(c) == "number"
       and b >= 0 and b <= 1 and c >= 0 and c <= 1 then
        return b, c                             -- 4.x+: completed, posX, posY
    end
    return nil
end

-- ------------------------------------------------------------ POI cache -----
local function NotifyChanged()
    for _, cb in ipairs(changedCallbacks) do
        local ok, err = pcall(cb)
        if not ok and EbonholdLog then EbonholdLog("supertrack cb error: " .. tostring(err)) end
    end
end

-- Force the client's own POI query: it ONLY fires from the C-side world-map
-- open/close path -- no stock Lua call triggers it, a CMSG forged at the
-- network layer (the dll's EbonholdRequestQuestPOI) gets its response
-- ignored by the client's POI bookkeeping, and a same-frame Show()+Hide()
-- is NOT enough either (the map must actually be live for at least one
-- rendered frame before the close; the close is what commits the fetch).
-- So: show the map at ALPHA 0 (fullscreen but invisible -- children inherit
-- the alpha, including the blackout), let it live for two rendered frames
-- (~33ms, imperceptible), then hide it and restore alpha/sound. Pulsed only
-- on quest-log transitions (accept/complete), throttled.
local lastPulse = 0
local pulseSavedSfx
-- Timing around a transition: the pulse is DELAYED (~0.7s) because on quest
-- ACCEPT the first QUEST_LOG_UPDATE fires while the client is still
-- processing the new quest -- an immediate map cycle queries POIs WITHOUT
-- it (completion worked, accept didn't). After a pulse, a verify pass
-- checks whether a watched quest still lacks POI data and allows ONE extra
-- retry -- covering however late the client registers the quest. That retry
-- is scheduled like any other pulse and obeys the same throttle and cold-zone
-- window; it used to skip both, which is what made a zone change able to fire
-- back-to-back map loads.
local pendingPulseAt, pulseVerifyAt, pulseRetried
local pulseDriver = CreateFrame("Frame")
pulseDriver:Hide()
pulseDriver.ticks = 0
pulseDriver:SetScript("OnUpdate", function(self)
    self.ticks = self.ticks + 1
    -- tick 1 = one full rendered frame with the map live; close on tick 2
    if self.ticks < 2 and WorldMapFrame:IsShown() then return end
    if WorldMapFrame:IsShown() then WorldMapFrame:Hide() end
    WorldMapFrame:SetAlpha(1)
    -- restore the map button hidden for the pulse (see below)
    if WorldMapButton then WorldMapButton:Show() end
    if pulseSavedSfx then
        SetCVar("Sound_EnableSFX", pulseSavedSfx)
        pulseSavedSfx = nil
    end
    pulseVerifyAt = GetTime() + 2   -- response + refresh should be in by then
    self:Hide()
end)

-- Never while the player is in combat.
--
-- The pulse is cheap to WRITE but not cheap to RUN: WorldMapFrame:Show() makes
-- the client load the zone's map art and run the whole map/POI layout pass
-- synchronously, on the main thread. That is a multi-hundred-millisecond stall
-- on a cold zone, and the trigger for it -- a quest flipping to complete -- is
-- something that happens when you kill the last mob of an objective, i.e.
-- mid-fight. A stall exactly then is indistinguishable from "the game froze in
-- combat", and it is fully avoidable: POI data is only read by the pin, which
-- nobody is looking at while swinging, so the pulse can simply wait for
-- PLAYER_REGEN_ENABLED (wired up in the event handler further down).
local pulseBlockedByCombat = false

-- Stamped on every world/zone entry (see the event handler further down).
--
-- The stall WorldMapFrame:Show() causes is not constant: it is paid when the
-- client has to pull the zone's map art off disk, i.e. the first time the map
-- is asked for after arriving somewhere. So the single most expensive pulse
-- there is, is the one right after a loading screen -- and it is also the one
-- that lands while the player is still watching the game come back, which is
-- what "it freezes when I enter a dungeon / change map" is. Hold pulses off
-- until the zone has had time to go warm.
local zoneEnteredAt   = 0
local COLD_ZONE_GRACE = 20

local function PulseWorldMapForPOIs()
    if not WorldMapFrame or WorldMapFrame:IsShown() then return end
    if pulseDriver:IsShown() then return end        -- pulse already in flight
    if UnitAffectingCombat("player") or InCombatLockdown() then
        pulseBlockedByCombat = true                 -- replayed on leaving combat
        return
    end
    local now = GetTime()
    -- Deferred, not dropped: the POI data is still wanted, just not at the one
    -- moment where fetching it costs the most. Re-arming pendingPulseAt to the
    -- END of the window (not "now + something") also collapses a burst of
    -- quest-log transitions during the loading screen into a single pulse.
    if now - zoneEnteredAt < COLD_ZONE_GRACE then
        pendingPulseAt = zoneEnteredAt + COLD_ZONE_GRACE
        return
    end
    -- The throttle is now UNCONDITIONAL. It used to be bypassable by the
    -- verify/retry path, i.e. by exactly the path that fires when POI data
    -- looks incomplete -- which is the normal state right after a zone change.
    -- The one case that most needed the brake was the one case that removed it.
    if now - lastPulse < 3 then return end
    lastPulse = now
    pulseSavedSfx = GetCVar("Sound_EnableSFX")
    SetCVar("Sound_EnableSFX", 0)
    WorldMapFrame:SetAlpha(0)
    -- WorldMapButton's stock OnUpdate does mouse math off GetCenter(), which
    -- is nil during this unusual not-yet-laid-out open -- hiding the button
    -- for the pulse skips that OnUpdate entirely (hidden frames get none)
    -- and stops the invisible fullscreen map from swallowing clicks.
    if WorldMapButton then WorldMapButton:Hide() end
    WorldMapFrame:Show()
    pulseDriver.ticks = 0
    pulseDriver:Show()
end

-- questID -> isComplete snapshot; a difference means POIs may have changed
-- (new quest accepted, objectives finished) and the map pulse is warranted.
local lastLogState = {}
local function QuestLogPOIStateChanged()
    local changed = false
    local cur = {}
    for questIndex = 1, GetNumQuestLogEntries() do
        local _, _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(questIndex)
        if not isHeader and questID and questID > 0 then
            local state = isComplete or 0
            cur[questID] = state
            if lastLogState[questID] ~= state then changed = true end
        end
    end
    lastLogState = cur
    return changed
end

local function RefreshPOIs()
    -- don't fight the player over the world map's current zone
    if WorldMapFrame and WorldMapFrame:IsShown() then return end
    if not QuestMapUpdateAllQuests then return end

    SetMapToCurrentZone()
    QuestMapUpdateAllQuests()

    local bounds = CurrentZoneBounds()
    poiCache = {}
    poiOrder = {}
    if not bounds then return end

    -- Addon-side watched set, NOT the client's watch list: the Ebonhold
    -- client evicts the previous watch on every add (1-quest cap), so the
    -- tracker keeps its own list (see quest_tracker.lua WatchedDB) -- the
    -- waypoint candidates must come from the same source.
    local watched = ProjectEbonholdDB and ProjectEbonholdDB.questTracker
        and ProjectEbonholdDB.questTracker.watchedQuests or {}
    for questIndex = 1, GetNumQuestLogEntries() do
        local title, _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(questIndex)
        if not isHeader and questID and questID > 0 and watched[questID] then
            local nx, ny = GetQuestPOIMapPos(questID)
            if nx then
                local wx, wy = MapToWorld(bounds, nx, ny)
                poiCache[questID] = { wx = wx, wy = wy, complete = (isComplete == 1), title = title }
                table.insert(poiOrder, questID)
            end
        end
    end
end

-- A watched quest sitting in the log with no cached POI: either the client
-- hadn't registered it yet when the last pulse queried (fresh accept), or
-- its objectives are in another zone. The verify pass allows ONE retry per
-- transition, so the second case can't loop.
local function AnyWatchedPOIMissing()
    local watched = ProjectEbonholdDB and ProjectEbonholdDB.questTracker
        and ProjectEbonholdDB.questTracker.watchedQuests or {}
    for questIndex = 1, GetNumQuestLogEntries() do
        local _, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(questIndex)
        if not isHeader and questID and questID > 0 and watched[questID]
            and not poiCache[questID] then
            return true
        end
    end
    return false
end

local function PickAutoQuest()
    local px, py = GetPlayerWorld()
    local best, bestDist
    for _, questID in ipairs(poiOrder) do
        local poi = poiCache[questID]
        if px then
            local dx, dy = poi.wx - px, poi.wy - py
            local d = dx * dx + dy * dy
            if not bestDist or d < bestDist then bestDist, best = d, questID end
        elseif not best then
            best = questID                      -- no player pos: first watched POI
        end
    end
    return best
end

local function UpdateEffectiveQuest()
    local newID
    if trackingOff then
        newID = nil                             -- waypoint explicitly turned off
    elseif manualQuestID then
        newID = manualQuestID                   -- user's pick, even if POI-less here
    else
        newID = PickAutoQuest()
    end
    if newID ~= currentQuestID then
        currentQuestID = newID
        NotifyChanged()
    end
end

-- ----------------------------------------------------------- public API -----
function ST.SetQuest(questID)                   -- nil -> back to auto-nearest
    if questID then customWaypoint = nil end    -- explicit pick beats waypoint
    local wasOff = trackingOff
    trackingOff = false                         -- any pick re-enables tracking
    if manualQuestID == questID and not wasOff then return end
    manualQuestID = questID
    sinceRefresh = REFRESH_INTERVAL             -- refresh promptly
    UpdateEffectiveQuest()
    NotifyChanged()
end

-- Pin toggle on the tracked quest: waypoint fully OFF (the quest stays in the
-- objectives list -- this only silences the on-screen pin and the auto-pick
-- fallback until the player picks a quest again or accepts a new one).
function ST.Disable()
    trackingOff = true
    manualQuestID = nil
    UpdateEffectiveQuest()
    NotifyChanged()
end

function ST.IsDisabled() return trackingOff end

function ST.SetWaypoint(wx, wy, wz)
    customWaypoint = { wx = wx, wy = wy, wz = wz }
    NotifyChanged()
end

function ST.ClearWaypoint()
    customWaypoint = nil
    NotifyChanged()
end

function ST.GetQuest() return currentQuestID end
function ST.GetManualQuest() return manualQuestID end
function ST.HasPOI(questID) return poiCache[questID] ~= nil end
function ST.RegisterChanged(cb) table.insert(changedCallbacks, cb) end

-- ------------------------------------------------------------- pin frame ----
local pin = CreateFrame("Frame", "EbonholdSuperTrackPin", UIParent)
pin:SetFrameStrata("BACKGROUND")                -- above the world, under the UI
pin:SetSize(34, 34)
pin:Hide()

local plate = pin:CreateTexture(nil, "BACKGROUND")
plate:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
plate:SetAllPoints(pin)
plate:SetVertexColor(0, 0, 0, 0.65)

local ring = pin:CreateTexture(nil, "BORDER")
ring:SetTexture(ASSETS .. "roundborder")
ring:SetSize(58, 58)
ring:SetPoint("CENTER")
ring:SetVertexColor(0.95, 0.78, 0.25)

local icon = pin:CreateTexture(nil, "ARTWORK")
icon:SetSize(20, 20)
icon:SetPoint("CENTER")
icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")

local distText = pin:CreateFontString(nil, "OVERLAY")
distText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
distText:SetPoint("TOP", pin, "BOTTOM", 0, -3)
distText:SetTextColor(1, 0.92, 0.6)

local arrow = pin:CreateTexture(nil, "OVERLAY")
arrow:SetTexture("Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW")
arrow:SetSize(26, 26)
arrow:Hide()

-- rotate a square texture's displayed image by `radians` counter-clockwise
-- (3.3.5 has no Texture:SetRotation; use the 8-arg SetTexCoord affine form)
local function RotateTex(tex, radians)
    local c, s = math.cos(radians), math.sin(radians)
    local function corner(x, y)
        return 0.5 + x * c + y * s, 0.5 + x * s - y * c
    end
    local ULx, ULy = corner(-0.5,  0.5)
    local LLx, LLy = corner(-0.5, -0.5)
    local URx, URy = corner( 0.5,  0.5)
    local LRx, LRy = corner( 0.5, -0.5)
    tex:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
end
local ARROW_BASE = -math.pi / 2   -- artwork points up; rotate so 0 rad = right

local function SetPinIcon(kind, complete)
    if kind == "waypoint" then
        icon:SetTexture("Interface\\Cursor\\Crosshairs")
        icon:SetVertexColor(1, 0.85, 0.2)
    else
        icon:SetVertexColor(1, 1, 1)
        if complete then
            icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
        else
            icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        end
    end
end

local function HidePin()
    if pin:IsShown() then pin:Hide() end
end

local warnedNoDLL = false

-- "arrived" hide: pin hidden while the player stands at the target, back when
-- they walk away; keyed to the target so a quest switch resets the state
local proxHidden    = false
local proxTargetKey = nil

pin.driver = CreateFrame("Frame")
pin.driver:SetScript("OnUpdate", function(self, dt)
    if not IsEnabled() then HidePin() return end
    dt = dt or 0

    -- Deferred map pulse + one-shot verify/retry (see PulseWorldMapForPOIs)
    local nowT = GetTime()
    if pendingPulseAt and nowT >= pendingPulseAt then
        pendingPulseAt = nil
        PulseWorldMapForPOIs()          -- throttled like any other pulse
    end
    if pulseVerifyAt and nowT >= pulseVerifyAt then
        pulseVerifyAt = nil
        if not pulseRetried and AnyWatchedPOIMissing() then
            pulseRetried = true
            pendingPulseAt = nowT + 0.3
        end
    end

    sinceRefresh = sinceRefresh + dt
    if sinceRefresh >= REFRESH_INTERVAL then
        sinceRefresh = 0
        RefreshPOIs()
        UpdateEffectiveQuest()
    end

    if not DLLReady() then
        if not warnedNoDLL and EbonholdLog then
            warnedNoDLL = true
            EbonholdLog("supertrack: EbonholdWorldToScreen missing, pin disabled")
        end
        HidePin()
        return
    end

    -- target: manual waypoint (exact coords) beats the quest POI (area centroid)
    local tx, ty, tz, kind, complete
    if customWaypoint then
        tx, ty, tz, kind = customWaypoint.wx, customWaypoint.wy, customWaypoint.wz, "waypoint"
    else
        local poi = currentQuestID and poiCache[currentQuestID]
        if not poi then HidePin() return end
        tx, ty, kind, complete = poi.wx, poi.wy, "quest", poi.complete
    end
    if not tz then
        local _, _, pz = GetPlayerWorld()
        tz = pz or 0                            -- POIs have no Z: player height
    end

    local ndcX, ndcY, depth, dist = EbonholdWorldToScreen(tx, ty, tz + POI_Z_LIFT)
    if not ndcX then HidePin() return end       -- no camera (loading screen etc.)

    -- EbonholdWorldToScreen's distance is CAMERA->target: it moves with the
    -- zoom/angle (reads 15 yd zoomed out, 0 yd zoomed in on the same spot).
    -- Measure PLAYER->target instead; keep the camera figure only as a
    -- fallback when the player position is unavailable.
    local pwx, pwy = GetPlayerWorld()
    if pwx then
        local ddx, ddy = tx - pwx, ty - pwy
        dist = math.sqrt(ddx * ddx + ddy * ddy)
    end

    if kind == "waypoint" and dist and dist < ARRIVAL_DIST then
        customWaypoint = nil
        Msg("waypoint reached.")
        NotifyChanged()
        HidePin()
        return
    end

    -- arrived at the objective: no need for the pin while standing on it;
    -- bring it back once the player walks away (two thresholds = hysteresis,
    -- so it doesn't flicker right at the boundary)
    local targetKey = (kind == "waypoint") and "waypoint" or currentQuestID
    if targetKey ~= proxTargetKey then
        proxTargetKey = targetKey
        proxHidden = false
    end
    if dist then
        if proxHidden then
            if dist > PROX_SHOW_DIST then proxHidden = false end
        elseif dist < PROX_HIDE_DIST then
            proxHidden = true
        end
    end
    if proxHidden then HidePin() return end

    -- user calibration (/ebtcal), applied before any on-screen decision
    local db = DB()
    ndcX = ndcX * (db.calX or 1)
    ndcY = ndcY * (db.calY or 1)

    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local inPOV = depth > 0
        and ndcX > -ONSCREEN_NDC and ndcX < ONSCREEN_NDC
        and ndcY > -ONSCREEN_NDC and ndcY < ONSCREEN_NDC

    local sx, sy
    if inPOV then
        sx = (ndcX + 1) * 0.5 * W
        sy = (ndcY + 1) * 0.5 * H
        arrow:Hide()
    else
        -- outside the POV: clamp to the screen edge along the direction of the
        -- target (mirror the direction when it is behind the camera)
        local dx, dy = ndcX, ndcY
        if depth <= 0 then dx, dy = -dx, -dy end
        local m = math.max(math.abs(dx), math.abs(dy), 1e-6)
        dx, dy = dx / m, dy / m                 -- point on the unit square edge
        sx = (dx + 1) * 0.5 * W
        sy = (dy + 1) * 0.5 * H

        -- directional arrow on the outward side of the pin
        local pxv = dx * W * 0.5                -- direction in screen units
        local pyv = dy * H * 0.5
        local ang = math.atan2(pyv, pxv)
        arrow:ClearAllPoints()
        arrow:SetPoint("CENTER", pin, "CENTER", math.cos(ang) * 27, math.sin(ang) * 27)
        RotateTex(arrow, ang + ARROW_BASE)
        arrow:Show()
    end

    -- keep inside the usable screen area in all cases
    if sx < EDGE_INSET_X then sx = EDGE_INSET_X elseif sx > W - EDGE_INSET_X then sx = W - EDGE_INSET_X end
    if sy < EDGE_INSET_BOT then sy = EDGE_INSET_BOT elseif sy > H - EDGE_INSET_TOP then sy = H - EDGE_INSET_TOP end

    pin:ClearAllPoints()
    pin:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)

    SetPinIcon(kind, complete)

    if dist and dist >= HIDE_DIST_TEXT then
        distText:SetText(string.format("%d yd", dist))
        distText:Show()
    else
        distText:Hide()
    end

    -- proximity feedback: gentle pulse when close (the pin hides entirely
    -- below PROX_HIDE_DIST, so no near-fade is needed)
    if dist and dist < PULSE_DIST then
        pin:SetAlpha(0.8 + 0.2 * math.sin(GetTime() * 5))
    else
        pin:SetAlpha(1)
    end

    if not pin:IsShown() then pin:Show() end
end)

-- ---------------------------------------------------------------- events ----
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("ZONE_CHANGED")
ev:RegisterEvent("QUEST_LOG_UPDATE")
-- Replays a map pulse that was suppressed because it came due mid-fight (see
-- PulseWorldMapForPOIs). Small delay so it does not land on the same frame as
-- the pile of UI work every addon does the instant combat drops.
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Fresh POI data landed from the server (e.g. the turn-in blob once a quest
-- completes): refresh on the very next tick instead of waiting out the 2s
-- poll -- shaves the addon-side share of the update latency. pcall'd in case
-- this client build doesn't know the event (RegisterEvent throws on unknown
-- names).
pcall(ev.RegisterEvent, ev, "QUEST_POI_UPDATE")
-- The 3.3.5 client only SENDS its POI query when the world map is actually
-- shown (C-side; no Lua call triggers it -- verified: the /ebtpoi dump stays
-- stale through SetMapToCurrentZone+QuestMapUpdateAllQuests, yet opening the
-- map refreshes). So the freshest data always follows a map view: re-read it
-- the moment the map closes instead of waiting out the poll interval.
if WorldMapFrame then
    WorldMapFrame:HookScript("OnHide", function()
        sinceRefresh = REFRESH_INTERVAL
    end)
end
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        poiCache, poiOrder = {}, {}
        sinceRefresh = REFRESH_INTERVAL         -- refresh on next tick
        -- Map art for the new zone is cold; see COLD_ZONE_GRACE. Only these two
        -- events, not ZONE_CHANGED: a subzone step stays on the same map art
        -- and costs nothing to show.
        zoneEnteredAt = GetTime()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pulseBlockedByCombat then
            pulseBlockedByCombat = false
            pendingPulseAt = GetTime() + 0.5
            pulseRetried = false
        end
    elseif event == "QUEST_POI_UPDATE" then
        sinceRefresh = REFRESH_INTERVAL         -- new data: refresh immediately
    elseif event == "QUEST_LOG_UPDATE" then
        -- Accept/complete transitions: SCHEDULE the hidden map cycle (0.7s
        -- out -- an immediate pulse on accept queries before the client has
        -- registered the new quest and fetches nothing for it).
        if QuestLogPOIStateChanged() then
            pendingPulseAt = GetTime() + 0.7
            pulseRetried = false
        end
        if sinceRefresh < REFRESH_INTERVAL - 0.5 then
            sinceRefresh = REFRESH_INTERVAL - 0.5
        end
    elseif sinceRefresh < REFRESH_INTERVAL - 0.5 then
        sinceRefresh = REFRESH_INTERVAL - 0.5   -- coalesce bursts of updates
    end
end)

-- -------------------------------------------------------- slash commands ----
-- DIAGNOSTIC (temporary): /ebtpoi dumps, for every watched quest, its log
-- state and the RAW QuestPOIGetIconInfo returns -- to find out what the
-- server/client actually provide once a quest is complete (the pin can only
-- point at the turn-in if the POI data switches to it).
SLASH_EBTPOI1 = "/ebtpoi"
SlashCmdList["EBTPOI"] = function()
    SetMapToCurrentZone()
    if QuestMapUpdateAllQuests then QuestMapUpdateAllQuests() end
    Msg("POI dump for zone: " .. tostring(GetMapInfo()))
    local watched = ProjectEbonholdDB and ProjectEbonholdDB.questTracker
        and ProjectEbonholdDB.questTracker.watchedQuests or {}
    for questIndex = 1, GetNumQuestLogEntries() do
        local title, _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(questIndex)
        if not isHeader and questID and questID > 0 and watched[questID] then
            local a, b, c, d, e = QuestPOIGetIconInfo(questID)
            Msg(string.format("q%d '%s' complete=%s poi=[%s, %s, %s, %s, %s]",
                questID, tostring(title), tostring(isComplete),
                tostring(a), tostring(b), tostring(c), tostring(d), tostring(e)))
        end
    end
end

SLASH_EBTWP1 = "/ebtwp"
SlashCmdList["EBTWP"] = function(msg)
    if not IsEnabled() then
        Msg("the quest tracker is disabled in the options (Quest Tracker section).")
        return
    end
    msg = string.lower(string.gsub(msg or "", "^%s*(.-)%s*$", "%1"))
    if msg == "clear" or msg == "off" then
        ST.ClearWaypoint()
        Msg("waypoint cleared.")
        return
    end
    local a, b = string.match(msg, "^([%d%.]+)[%s,]+([%d%.]+)$")
    if a then
        if not (WorldMapFrame and WorldMapFrame:IsShown()) then SetMapToCurrentZone() end
        local bounds = CurrentZoneBounds()
        if not bounds then
            Msg("no map bounds for this zone; cannot place a map waypoint here.")
            return
        end
        local wx, wy = MapToWorld(bounds, tonumber(a) / 100, tonumber(b) / 100)
        local _, _, pz = GetPlayerWorld()
        ST.SetWaypoint(wx, wy, pz)
        Msg(string.format("waypoint set at %s %.1f, %.1f.", GetMapInfo() or "?", tonumber(a), tonumber(b)))
    elseif msg == "" then
        local px, py, pz = GetPlayerWorld()
        if not px then
            Msg("player position unavailable (is ebonhold.dll loaded?).")
            return
        end
        ST.SetWaypoint(px, py, pz)
        Msg("waypoint set at your current position. Walk away to test the pin; /ebtwp clear to remove.")
    else
        Msg("usage: /ebtwp  |  /ebtwp 45 67  |  /ebtwp clear")
    end
end

SLASH_EBTCAL1 = "/ebtcal"
SlashCmdList["EBTCAL"] = function(msg)
    msg = string.lower(string.gsub(msg or "", "^%s*(.-)%s*$", "%1"))
    local db = DB()
    if msg == "reset" then
        db.calX, db.calY = nil, nil
        Msg("projection calibration reset (1.0 / 1.0).")
        return
    end
    local a, b = string.match(msg, "^([%d%.]+)%s*([%d%.]*)$")
    local x = tonumber(a)
    if x then
        db.calX = x
        db.calY = tonumber(b) or x
        Msg(string.format("projection calibration set: X=%.3f Y=%.3f.", db.calX, db.calY))
    else
        Msg(string.format("projection calibration: X=%.3f Y=%.3f  (/ebtcal <x> [y] | reset)",
            db.calX or 1, db.calY or 1))
    end
end
