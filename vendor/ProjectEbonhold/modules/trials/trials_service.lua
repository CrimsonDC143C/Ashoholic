-- trials_service.lua -- The Trials: transport + parsed state.
--
-- Server-authoritative (TrialMgr). This module keeps the last attempt state the server pushed
-- (SEND_TRIAL_STATE, once a second while in the arena), the last result (SEND_TRIAL_RESULT) and
-- the last leaderboard (SEND_TRIAL_LEADERBOARD), and sends the five requests. The UI never
-- computes a score or a rank itself.
--
-- Two Trials, both at the Argent Tournament (entered through Herald Beluus):
--   1  Trial of the Champion  - damage, solo, map 650, leaderboard per class
--   3  Trial of the Crusader  - survival waves, 1 to 5 players, map 649
-- (2, the old duo Trial, is retired.)
--
-- Wire (docs/tournament/CONTRACT.md section 4; new fields are only ever appended, so every
-- trailing field is optional here - an older server simply sends fewer):
--   STATE:  "<trial>|<phase>|<remainingMs>|<errors>|<maxErrors>|<score>|<elapsedMs>|<attempt>|<partnerName>
--            |<wave>|<wavesCleared>|<alive>|<teamSize>|<downed>|<startWave>"
--           startWave > 1: a Trial of the Crusader practice run from a checkpoint (not ranked).
--           phase 0 none / 1 entering / 2 prep / 3 running / 4 result. Empty body = Trials off.
--           partnerName is always empty now; the last five are 0 for trial 1.
--   RESULT: "<trial>|<score>|<rank>|<total>|<topPermilleX10>|<pb 0/1>|<previousBest>|<reason>|<elapsedMs>
--            |<classId>|<wavesCleared>|<teamSize>|<startWave>"
--           startWave > 1: practice - rank and total are 0, nothing was recorded.
--           reason 0 time / 1 death / 2 abandon. Trial 1: rank / total are within the class.
--   BOARD:  "<trial>|<classFilter>|<season>|<seasonName>|<myRank>|<myBest>|<total>"
--           then ";rank~name~class~score~teamSize" rows (classFilter 0 for trial 3).
--
-- Trial of the Crusader score: waves * 100000000 + (99999999 - elapsedDs), elapsedDs = run time
-- in tenths of a second when the last wave fell. Decoded by Trials.DecodeCrusader.

local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
local Trials = {}
ProjectEbonhold.Trials = Trials

Trials.TYPE = { NONE = 0, CHAMPION = 1, CRUSADER = 3 }
Trials.PHASE = { NONE = 0, ENTERING = 1, PREP = 2, RUNNING = 3, RESULT = 4 }
Trials.REASON = { TIME = 0, DEATH = 1, ABANDON = 2 }

Trials.NAMES = {
    [1] = "Trial of the Champion",
    [3] = "Trial of the Crusader",
}

-- Class ids as the server sends them (ChrClasses), their client tokens and English names.
Trials.CLASS_ORDER = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 11 }
Trials.CLASS_TOKEN = {
    [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
    [6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID",
}
Trials.CLASS_NAME = {
    [1] = "Warrior", [2] = "Paladin", [3] = "Hunter", [4] = "Rogue", [5] = "Priest",
    [6] = "Death Knight", [7] = "Shaman", [8] = "Mage", [9] = "Warlock", [11] = "Druid",
}

Trials.enabled = true
Trials.state = nil        -- last STATE, with receivedAt (GetTime()) so the clocks tick locally
Trials.lastResult = nil
Trials.board = nil

local listeners = {}

-- UI registers here: fn(eventName, payload). Events: "state", "result", "board".
function Trials.OnChanged(fn)
    table.insert(listeners, fn)
end

local function fire(event, payload)
    for _, fn in ipairs(listeners) do
        fn(event, payload)
    end
end

-- The player's own class id (UnitClass in 3.3.5 returns no id, only the token).
function Trials.MyClassId()
    local _, token = UnitClass("player")
    for id, t in pairs(Trials.CLASS_TOKEN) do
        if t == token then return id end
    end
    return 0
end

-- ---------------------------------------------------------------- requests --

function Trials.RequestState()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TRIAL_STATE, "")
end

function Trials.Start(trial)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TRIAL_START, tostring(trial or Trials.TYPE.CHAMPION))
end

function Trials.Retry()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TRIAL_RETRY, "")
end

function Trials.Leave()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TRIAL_LEAVE, "")
end

-- Trial of the Champion standings are per class: classId picks the board (the player's own when
-- nil). The Trial of the Crusader has a single board, no class is sent.
function Trials.RequestBoard(trial, classId)
    trial = trial or Trials.TYPE.CHAMPION
    local body = tostring(trial)
    if trial == Trials.TYPE.CHAMPION then
        classId = classId or Trials.MyClassId()
        if classId and classId > 0 then
            body = body .. "|" .. classId
        end
    end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TRIAL_LEADERBOARD, body)
end

-- ----------------------------------------------------------------- helpers --

local function split(str, sep)
    local out = {}
    local pattern = "([^" .. sep .. "]*)" .. sep
    for part in string.gmatch(str .. sep, pattern) do
        table.insert(out, part)
    end
    return out
end

-- "18492351" -> "18 492 351" (thin separators read better than commas on a HUD).
function Trials.FormatNumber(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (out:gsub("^%s+", ""))
end

-- Milliseconds -> "m:ss" (countdowns) or "mm:ss.cc" (survival times).
function Trials.FormatClock(ms, centis)
    ms = math.max(0, tonumber(ms) or 0)
    local total = ms / 1000
    local m = math.floor(total / 60)
    local s = math.floor(total - m * 60)
    if centis then
        local c = math.floor((total - math.floor(total)) * 100)
        return string.format("%02d:%02d.%02d", m, s, c)
    end
    return string.format("%d:%02d", m, s)
end

-- Tenths of a second -> "m:ss.d" (the Trial of the Crusader run time).
function Trials.FormatTenths(ds)
    ds = math.max(0, math.floor(tonumber(ds) or 0))
    local secs = math.floor(ds / 10)
    return string.format("%d:%02d.%d", math.floor(secs / 60), secs % 60, ds % 10)
end

function Trials.FormatWaves(waves)
    waves = tonumber(waves) or 0
    return waves == 1 and "1 wave" or (waves .. " waves")
end

-- Trial of the Crusader score -> waves cleared, run time in tenths of a second.
function Trials.DecodeCrusader(score)
    score = tonumber(score) or 0
    if score <= 0 then return 0, 0 end
    local waves = math.floor(score / 100000000)
    local elapsedDs = 99999999 - (score % 100000000)
    return waves, elapsedDs
end

-- Score as the player reads it, by Trial.
function Trials.FormatScore(trial, score)
    if trial == Trials.TYPE.CRUSADER then
        local waves, ds = Trials.DecodeCrusader(score)
        if waves <= 0 then return Trials.FormatWaves(0) end
        return Trials.FormatWaves(waves) .. "  " .. Trials.FormatTenths(ds)
    end
    return Trials.FormatNumber(score)
end

-- Seconds left on the server's countdown, ticked from the reception time.
function Trials.GetRemainingMs()
    local st = Trials.state
    if not st then return 0 end
    local elapsed = (GetTime() - (st.receivedAt or GetTime())) * 1000
    return math.max(0, st.remainingMs - elapsed)
end

-- Run time so far, ticked from the reception time while the attempt runs.
function Trials.GetElapsedMs()
    local st = Trials.state
    if not st then return 0 end
    if st.phase ~= Trials.PHASE.RUNNING then return st.elapsedMs end
    return st.elapsedMs + (GetTime() - (st.receivedAt or GetTime())) * 1000
end

function Trials.IsInArena()
    local st = Trials.state
    return st ~= nil and st.phase >= Trials.PHASE.PREP
end

-- --------------------------------------------------------------- handlers --

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_TRIAL_STATE, function(body)
    if not body or body == "" then
        Trials.enabled = false
        Trials.state = nil
        fire("state", nil)
        return
    end
    Trials.enabled = true
    local f = split(body, "|")
    -- f[9] (partnerName) is the retired duo's field: always empty, ignored.
    Trials.state = {
        receivedAt   = GetTime(),
        trial        = tonumber(f[1]) or 0,
        phase        = tonumber(f[2]) or 0,
        remainingMs  = tonumber(f[3]) or 0,
        errors       = tonumber(f[4]) or 0,
        maxErrors    = tonumber(f[5]) or 0,
        score        = tonumber(f[6]) or 0,
        elapsedMs    = tonumber(f[7]) or 0,
        attempt      = tonumber(f[8]) or 0,
        wave         = tonumber(f[10]) or 0,
        wavesCleared = tonumber(f[11]) or 0,
        alive        = tonumber(f[12]) or 0,
        teamSize     = tonumber(f[13]) or 0,
        downed       = (tonumber(f[14]) or 0) == 1,
        startWave    = tonumber(f[15]) or 1,
    }
    fire("state", Trials.state)
end)

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_TRIAL_RESULT, function(body)
    local f = split(body or "", "|")
    local r = {
        trial        = tonumber(f[1]) or 0,
        score        = tonumber(f[2]) or 0,
        rank         = tonumber(f[3]) or 0,
        total        = tonumber(f[4]) or 0,
        topPct       = (tonumber(f[5]) or 10000) / 100, -- 1234 -> 12.34 (%)
        personalBest = (tonumber(f[6]) or 0) == 1,
        previousBest = tonumber(f[7]) or 0,
        reason       = tonumber(f[8]) or 0,
        elapsedMs    = tonumber(f[9]) or 0,
        classId      = tonumber(f[10]) or 0,
        wavesCleared = tonumber(f[11]),
        teamSize     = tonumber(f[12]) or 0,
        startWave    = tonumber(f[13]) or 1,
    }
    if r.trial == Trials.TYPE.CHAMPION and r.classId == 0 then
        r.classId = Trials.MyClassId()
    end
    if r.wavesCleared == nil then
        r.wavesCleared = (Trials.DecodeCrusader(r.score))
    end
    Trials.lastResult = r
    fire("result", r)
end)

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_TRIAL_LEADERBOARD, function(body)
    local sections = split(body or "", ";")
    local h = split(sections[1] or "", "|")
    local board
    if #h >= 7 then
        board = {
            trial       = tonumber(h[1]) or 0,
            classFilter = tonumber(h[2]) or 0,
            season      = tonumber(h[3]) or 0,
            seasonName  = h[4] or "",
            myRank      = tonumber(h[5]) or 0,
            myBest      = tonumber(h[6]) or 0,
            total       = tonumber(h[7]) or 0,
        }
    else
        -- Older server: no class filter in the header.
        board = {
            trial       = tonumber(h[1]) or 0,
            classFilter = 0,
            season      = tonumber(h[2]) or 0,
            seasonName  = h[3] or "",
            myRank      = tonumber(h[4]) or 0,
            myBest      = tonumber(h[5]) or 0,
            total       = tonumber(h[6]) or 0,
        }
    end
    if board.trial == Trials.TYPE.CHAMPION and board.classFilter == 0 then
        board.classFilter = Trials.MyClassId()
    end
    board.rows = {}
    for i = 2, #sections do
        local r = split(sections[i], "~")
        if #r >= 4 then
            table.insert(board.rows, {
                rank     = tonumber(r[1]) or 0,
                name     = r[2] or "",
                class    = tonumber(r[3]) or 0,
                score    = tonumber(r[4]) or 0,
                teamSize = tonumber(r[5]) or 1,
            })
        end
    end
    Trials.board = board
    fire("board", board)
end)

-- Ask for the state once the world is up, so a /reload inside the arena redraws the HUD.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    Trials.RequestState()
end)
