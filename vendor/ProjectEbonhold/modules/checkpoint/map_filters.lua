-- ==============================================================================
-- World map filters for Project Ebonhold's own pins (2026-11-15, owner: the DragonUI map's filter
-- button must list OUR icons, with our logic).
--
-- Four switches, account-wide in ProjectEbonholdDB.mapFilters, all on by default:
--   waystones     - checkpoint pins (modules\checkpoint, kind DEFAULT)
--   meetingStones - dungeon and raid meeting stones (modules\checkpoint, kind MEETINGSTONE*)
--   spiritHealers - Spirit Healer graveyards (modules\graveyards)
--   demonicPortals - Demonic Portals the character has found (modules\torment\portal_pins, 2026-11-20)
-- Opened from a flight master, the map is the travel window: the waystones and meeting stones show
-- whatever the filter says, or the player could not pick where to go (checkpoint.lua sets that).
-- The DragonUI filter menu lists them (DragonUI\modules\worldmap\pins.lua, filterEntries).
-- ==============================================================================
ProjectEbonhold = ProjectEbonhold or {}
local L = ProjectEbonhold.L

local MF = { travelOpen = false }
ProjectEbonhold.MapFilters = MF

local refreshers = {}

local function Store()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.mapFilters = ProjectEbonholdDB.mapFilters or {}
    return ProjectEbonholdDB.mapFilters
end

-- Filter value alone, as the menu shows it.
function MF.IsChecked(key)
    return Store()[key] ~= false
end

-- What the pins read: the travel window ignores the checkpoint filters.
function MF.IsShown(key)
    if MF.travelOpen and (key == "waystones" or key == "meetingStones") then return true end
    return MF.IsChecked(key)
end

function MF.Toggle(key)
    Store()[key] = not MF.IsChecked(key)
    for _, refresh in ipairs(refreshers) do refresh() end
end

function MF.OnChanged(refresh)
    refreshers[#refreshers + 1] = refresh
end

-- Menu entries, in the order the filter button lists them.
function MF.Entries()
    return {
        { key = "waystones", text = L["Show Waystones"] },
        { key = "meetingStones", text = L["Show Dungeon and Raid Stones"] },
        { key = "spiritHealers", text = L["Show Spirit Healers"] },
        { key = "demonicPortals", text = L["Show Demonic Portals"] },
    }
end
