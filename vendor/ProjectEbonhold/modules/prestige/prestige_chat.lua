-- ============================================================================
-- Prestige chat badge — the client half of the chat rank icon.
--
-- HOW THE BADGE GETS HERE
--   1. Server: Player::GetChatTag() ORs the milestone rank into the four bits
--      the 3.3.5 client leaves unused in the chat packet's chatTag byte
--      (rank = ((tag & 0xE0) >> 5) | (tag & 0x08), so 1..15).
--   2. Client: ebonhold.dll rewrites the client's tag->string table so that
--      field becomes CHAT_MSG_* arg6 = "PR01" .. "PR15".
--      (see chattag_client.h in the client mod repo for the full reverse
--      engineering — the icon itself is 100% Lua, the DLL only widens the
--      vocabulary of arg6 from 5 fixed strings to 20.)
--   3. This file: turns those arg6 values into the texture escape.
--
-- WHY THE TAGS ARE FOUR CHARACTERS AND NOT "PRESTIGEnn"
-- A message from a player the client has not resolved yet is not dispatched on
-- arrival: sub_00509DD0 hands it to sub_00502D00, which copies it into a
-- pending record and replays it once the name cache answers. That record stores
-- the tag with SStrCopy(rec+0xC0, tag, 5) at 0x00502E82 — a hard-coded 5,
-- because stock tags are at most "DEV"/"DND"/"AFK". Anything longer comes back
-- out cut to four characters, so the original "PRESTIGE01" surfaced as
-- arg6 = "PRES", CHAT_FLAG_PRES was nil, and every message from that player in
-- that (very common — first line from a stranger in a public channel) case blew
-- up with
--     ChatFrame.lua:2917: attempt to concatenate local 'pflag' (a nil value)
-- Four characters survive both the immediate and the pending path byte for
-- byte. Keep any future tag <= 4 characters.
--
-- WHY JUST DEFINING GLOBALS IS ENOUGH
-- Both chat handlers in play resolve an arg6 they don't recognise the same way:
--
--   Interface\FrameXML\ChatFrame.lua      (Data\enUS\patch-enUS-3.MPQ)
--   ElvUI\Modules\Chat\Chat.lua           (CH:ChatFrame_MessageEventHandler)
--
--       else
--           pflag = _G["CHAT_FLAG_"..arg6]
--       end
--
-- so defining CHAT_FLAG_PRnn lights the badge up in BOTH, with no edit to
-- ChatFrame.lua (no MPQ repack) and no edit to ElvUI (which players install
-- themselves and we could never patch anyway).
--
-- WHY THE LOOP GOES TO 15 AND NOT MAX_RANK
-- Neither handler guards that lookup with `or ""`. If arg6 arrives as a tag
-- whose global is missing, pflag is nil and the concatenation a few lines below
-- raises a Lua error on EVERY message from that player. So we cover the full
-- range the DLL is able to emit, not just the milestones currently configured —
-- a 15th milestone added server-side must never be able to break chat for
-- everyone before the addon catches up. The legacy aliases at the bottom are
-- the same rule applied across time: a player running an older ebonhold.dll
-- must not break either.
-- ============================================================================

local addonName, addon = ...

-- The DLL's tag table (chattag_client.h) ships PR01..PR15. Keep in sync if that
-- ever changes; it is deliberately >= PrestigeData.MAX_RANK (14).
local DLL_MAX_TAG = 15

-- Fallback path, used only if prestige_data.lua did not load or a milestone has
-- no rankIcon. Mirrors RANK_ICON there.
local FALLBACK_ICON = "Interface\\AddOns\\ProjectEbonhold\\assets\\ranks\\pvprank%02d"

-- Texture escape copied verbatim from the Blizzard GM badge in ChatFrame.lua
-- ("|TInterface\\ChatFrame\\UI-ChatIcon-Blizz.blp:0:2:0:-3|t ") so the prestige
-- badge sits exactly like it:
--     0   height -> follow the chat font size instead of a fixed pixel height
--     2   width
--     0   x offset
--    -3   y offset, the baseline nudge
-- and the TRAILING SPACE separates the badge from the player name. Do not drop
-- it — the handler concatenates pflag straight onto the name link.
--
-- CALIBRATION: the rank badge BLPs are square 32x32 (verified in the file
-- headers), so height and width are given as EXPLICIT EQUAL pixel values.
-- That renders a true square no matter how the client interprets the
-- height-0 aspect form the Blizz badge uses (its texture is 32x16, which is
-- where the sideways stretching came from). 14px sits well next to 12-14px
-- chat fonts; bump BOTH numbers together to resize, keep them equal to keep
-- the badge square. The -3 is the usual baseline nudge.
local ESCAPE = "|T%s:15:15:0:-3|t "

local function IconForRank(rank)
    local data = ProjectEbonhold and ProjectEbonhold.PrestigeData
    local milestone = data and data.Milestones and data.Milestones[rank]
    if milestone and milestone.rankIcon and milestone.rankIcon ~= "" then
        return milestone.rankIcon
    end
    return string.format(FALLBACK_ICON, rank)
end

for rank = 1, DLL_MAX_TAG do
    local escape = string.format(ESCAPE, IconForRank(rank))
    _G[string.format("CHAT_FLAG_PR%02d", rank)] = escape

    -- Legacy: what ebonhold.dll emitted before the tags were shortened. Cheap
    -- to keep, and it means a player on an old DLL still gets the badge on the
    -- immediate path instead of nothing.
    _G[string.format("CHAT_FLAG_PRESTIGE%02d", rank)] = escape
end

-- Legacy: what an old DLL's "PRESTIGEnn" decays to on the pending path above.
-- The rank is unrecoverable from four characters, so show no badge — but it
-- must not be nil, or chat errors out for that player's every message.
_G.CHAT_FLAG_PRES = ""
