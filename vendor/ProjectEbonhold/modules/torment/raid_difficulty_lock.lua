-- Module: Raid Difficulty Lock
-- Takes the raid difficulty choice out of the client entirely.
--
-- Every raid on this realm is a 10-player instance and its difficulty comes from
-- Torment, not from Blizzard's 10/25 and normal/heroic axes: content_bracket holds
-- no heroic variant for any raid map, and the server clamps the value in
-- Player::SetRaidDifficulty / Group::SetRaidDifficulty and refuses
-- MSG_SET_RAID_DIFFICULTY outright.
--
-- Leaving the menu in place would therefore show a control that silently does
-- nothing, so the entries are removed from the unit popup and the API is stubbed.
-- SetDungeonDifficulty is not stubbed here, yet 5-man Heroic is gone too (2026-10-04): every
-- dungeon runs in Normal, the server clamps Player::SetDungeonDifficulty and refuses
-- MSG_SET_DUNGEON_DIFFICULTY with a notice, and the Dungeon Finder never offers a Heroic.

-- ── Unit popup entries ───────────────────────────────────────────────────
--
-- UnitPopup.lua is FrameXML, so it has already built its tables by the time an
-- addon file runs. Every menu is swept rather than the handful known to carry the
-- entry, so a menu added by a patch or another addon cannot leave a stray one.

local function StripRaidDifficulty()
    if type(UnitPopupMenus) ~= "table" then
        return
    end

    for _, menu in pairs(UnitPopupMenus) do
        if type(menu) == "table" then
            for i = #menu, 1, -1 do
                if menu[i] == "RAID_DIFFICULTY" then
                    table.remove(menu, i)
                end
            end
        end
    end

    -- The nested list the removed button used to open, plus its four options.
    UnitPopupMenus["RAID_DIFFICULTY"] = nil
end

StripRaidDifficulty()

-- ── API stub ─────────────────────────────────────────────────────────────
--
-- A macro, a keybind or another addon can still call this. The server would refuse
-- it and answer with the real value, which makes the UI flicker for no reason, so
-- the call is dropped here instead.

if type(SetRaidDifficulty) == "function" then
    local blizzardSetRaidDifficulty = SetRaidDifficulty

    SetRaidDifficulty = function(difficulty)
        -- 1 is RAID_DIFFICULTY_10MAN_NORMAL on the client scale (Lua is 1-based here).
        if difficulty == 1 then
            return blizzardSetRaidDifficulty(difficulty)
        end
    end
end
