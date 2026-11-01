-- ==============================================================================
-- The Reaper's Gaze (server: ReaperMgr): the run's risk gauge, the Eye, the Reaper of this layer.
--
-- Wire:
--   CS.REQUEST_REAPER_STATE  (1235) body ""  -> SS.SEND_REAPER_STATE (1235)
--   CS.REQUEST_SUMMON_REAPER (1236) body ""  -> breaks the Eye held in the bags (refusal = chat line)
--   SS body: "<gauge>;<cap>;<pact>;<fragments>;<perEye>;<hasEye>;<reaperAlive>;<reaperTorment>;<harvested>;<enabled>"
--     gauge / cap   in percent points (the gauge multiplies every Soul Ash / Shard gain by 1 + gauge/100)
--     pact          1 = Pact of the Reaper: the gauge is sealed at its cap for the rest of the run
--     fragments     Fragments of the Reaper's Eye held (perEye of them knit into the Eye)
--     reaperAlive   1 = the Reaper walks this layer (summoned at reaperTorment)
--     harvested     1 = this soul was harvested: no resurrection, only accepting death
-- Pushed on login, every gauge change (coalesced), death, run end, and the Reaper's summon /
-- death / departure. The run frame's bar (player_run_ui.lua, UpdateBracket) draws the gauge.
-- ==============================================================================
local RP = {}
ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.Reaper = RP

RP.gauge, RP.cap, RP.pact = 0, 100, false
RP.fragments, RP.perEye, RP.hasEye = 0, 40, false
RP.reaperAlive, RP.reaperTorment, RP.harvested, RP.enabled = false, 0, false, true
RP.received = false

RP.ICON_EYE = "Interface\\Icons\\INV_Misc_Eye_01"
RP.ICON_FRAGMENT = "Interface\\Icons\\INV_Misc_Eye_02"
RP.ICON_PACT = "Interface\\Icons\\Spell_Shadow_SoulLeech_3"

function RP.OnData(body)
    RP.rawBody = body
    local gauge, cap, pact, fragments, perEye, hasEye, alive, torment, harvested, enabled = strsplit(";", body or "")
    RP.gauge = tonumber(gauge) or 0
    RP.cap = tonumber(cap) or 100
    RP.pact = (tonumber(pact) or 0) == 1
    RP.fragments = tonumber(fragments) or 0
    RP.perEye = tonumber(perEye) or 40
    RP.hasEye = (tonumber(hasEye) or 0) == 1
    RP.reaperAlive = (tonumber(alive) or 0) == 1
    RP.reaperTorment = tonumber(torment) or 0
    RP.harvested = (tonumber(harvested) or 0) == 1
    RP.enabled = (tonumber(enabled) or 1) == 1
    RP.received = true
    if ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateBracket then
        ProjectEbonhold.PlayerRunUI.UpdateBracket()
    end
end

-- "+140%" in the gauge's colour: green low, orange mid, red near the cap; purple under the Pact.
function RP.GaugeText()
    local g, cap = RP.gauge or 0, RP.cap or 100
    local color
    if RP.pact then color = "|cff9370db"
    elseif cap <= 0 or g / cap < 1 / 3 then color = "|cff40ff40"
    elseif g / cap < 2 / 3 then color = "|cffffa040"
    else color = "|cffff4040" end
    return color .. "+" .. math.floor(g + 0.5) .. "%|r"
end

function RP.CapText()
    return "+" .. math.floor((RP.cap or 100) + 0.5) .. "%"
end

-- Lines for the bar tooltip: { text, r, g, b [, right] }.
function RP.Lines()
    local lines = {}
    if not RP.enabled then
        table.insert(lines, { "The Reaper does not answer on this realm.", 0.6, 0.6, 0.6 })
        return lines
    end
    -- One line: the gauge and its cap (100% + 10% per Torment level of the account). Nothing
    -- about the next Torment here: the content list below is the only place that says where to go.
    -- the gauge against the absolute maximum (+400%, Torment 30): one figure, nothing else
    table.insert(lines, { "Contract bonus", 1, 1, 1, RP.GaugeText() .. " |cffaaaaaa/ " .. RP.CapText() .. "|r" })
    if RP.pact then
        table.insert(lines, { "|cff9370dbPact of the Reaper: sealed at the cap for this run.|r", 0.58, 0.44, 0.86 })
    end
    if RP.harvested then
        table.insert(lines, { "|cffff4040Soul harvested: only accepting death remains.|r", 1, 0.25, 0.25 })
    end
    if RP.hasEye then
        table.insert(lines, { "|T" .. RP.ICON_EYE .. ":14:14:0:0|t Eye of the Reaper", 0.58, 0.44, 0.86,
            RP.reaperAlive and "|cffaaaaaaReaper already here|r" or "|cff40ff40Click the eye to break it|r" })
    elseif (RP.fragments or 0) > 0 then
        table.insert(lines, { "|T" .. RP.ICON_FRAGMENT .. ":14:14:0:0|t Eye fragments", 0.8, 0.8, 0.8, RP.fragments .. " / " .. RP.perEye })
    end
    if RP.reaperAlive then
        table.insert(lines, { "|cffff4040The Reaper walks this layer (Torment " .. RP.reaperTorment .. ").|r", 1, 0.25, 0.25 })
    end
    return lines
end

function RP.Request()
    if ProjectEbonhold.sendToServer and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_REAPER_STATE then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_REAPER_STATE, "")
    end
end

-- Break the Eye. The server checks everything again (open sky, alive, no Reaper on the layer,
-- the Eye in the bags): this only asks.
function RP.Summon()
    if not RP.hasEye then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Ebonhold:|r you do not hold the Eye of the Reaper.")
        return
    end
    if RP.reaperAlive then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Ebonhold:|r the Reaper already walks this layer.")
        return
    end
    if ProjectEbonhold.sendToServer and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_SUMMON_REAPER then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SUMMON_REAPER, "")
    end
end

-- Confirmation before breaking the Eye: the summon is irreversible and the Reaper's touch is death.
StaticPopupDialogs["EBONHOLD_BREAK_EYE"] = {
    text = "Break the Eye of the Reaper?\n\nThe Reaper will walk this layer at your Torment. Its Harvest kills beyond any resurrection. Slay it to seal your gauge for the rest of the run.",
    button1 = "Break it",
    button2 = CANCEL,
    OnAccept = function() RP.Summon() end,
    timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
}

function RP.AskSummon()
    if not RP.hasEye then RP.Summon() return end
    StaticPopup_Show("EBONHOLD_BREAK_EYE")
end

SLASH_EBONHOLDREAPER1 = "/reaper"
SlashCmdList["EBONHOLDREAPER"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "summon" or msg == "break" then
        RP.AskSummon()
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Ebonhold Reaper:|r")
    for _, l in ipairs(RP.Lines()) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. l[1] .. (l[5] and ("  " .. l[5]) or ""), l[2], l[3], l[4])
    end
    DEFAULT_CHAT_FRAME:AddMessage("  /reaper break - break the Eye", 0.6, 0.6, 0.6)
    RP.Request()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
    RP.Request()
end)

if ProjectEbonhold.onEventReceived and ProjectEbonhold.SS and ProjectEbonhold.SS.SEND_REAPER_STATE then
    ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_REAPER_STATE, RP.OnData)
end
