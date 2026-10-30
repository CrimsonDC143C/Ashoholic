-- ============================================================================
-- Prestige data: the 14 milestones and their rewards. ALL balancing lives in
-- this file; edit the tables freely, nothing else needs to change.
--
-- A "prestige" is one full skill tree reset. Milestones unlock at CUMULATIVE
-- prestige counts (the totalPrestiges column below), not one per prestige.
--
-- Each milestone grants up to 3 rewards, all optional:
--   item              an item reward, one of three forms:
--                       { type = "mount", itemID = 12345, name = "Reins of ..." }
--                       { type = "weapon", itemID = 620035, name = "..." }
--                         (previewed tried on your character, current gear kept)
--                       { type = "transmogSet", name = "Set name",
--                         items = { 111, 222, 333 } }   -- array of item IDs
--                     (name is the display name used in tooltips; when empty
--                     the UI falls back to GetItemInfo. itemID = 0 or an empty
--                     items array means "not configured yet" and is hidden.)
--                     Mounts may add creatureID = <creature_template entry>
--                     for the 3D preview when the mount is not in the
--                     collections catalog (custom server mounts). SetCreature
--                     on this client takes the CREATURE id (resolved through
--                     the local creature cache, seeded on login), NOT the
--                     CreatureDisplayInfo id. Without it and without a catalog
--                     entry the preview shows the name but no model.
--   items             OPTIONAL plural form: an ARRAY of item rewards for one
--                     milestone, each entry using the same mount/transmogSet
--                     shapes as `item`. Use it to grant several things at
--                     once (e.g. every vanilla PvP set):
--                       items = {
--                         { type = "transmogSet", name = "Set A", items = {...} },
--                         { type = "transmogSet", name = "Set B", items = {...} },
--                       }
--                     The preview panel pages through them with arrows.
--                     `item` (singular) keeps working for single rewards.
--                     Nothing is ever mailed: the server turns mount items
--                     into the learned mount (account-wide) and gear items
--                     into collected wardrobe appearances, so entries have
--                     no size limit.
--   rankIcon          chat rank icon earned at this milestone (display data
--                     for now; actual chat integration comes later).
--   title             character title earned at this milestone, e.g.
--                     { titleId = 177, name = "the Prestigious" }. titleId is
--                     the CharTitles.dbc id the server grants (must mirror
--                     world.prestige_milestone.reward_title_id); name is the
--                     display string for tooltips. nil = no title.
--   unlock            OPTIONAL free text shown as "Also unlocks: X" in the
--                     milestone tooltip (e.g. "Season 3 Gear"). Display only;
--                     the actual content gating is server-side.
--
-- The permanent Soul Ash gain bonus is NOT a milestone reward: EVERY prestige
-- grants one, PROPORTIONAL to the committed pool it destroys (20% per gate
-- worth burned, with diminishing returns, at every prestige number).
-- See PrestigeData.ComputeBonusPct at the
-- bottom of this file, which mirrors PrestigeHandler::ComputeSoulAshBonusPct.
-- ============================================================================

local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}

local RANK_ICON = "Interface\\AddOns\\ProjectEbonhold\\assets\\ranks\\pvprank%02d"

local PrestigeData = {}
ProjectEbonhold.PrestigeData = PrestigeData

PrestigeData.MAX_RANK = 14

-- Rank icons: assets\ranks\pvprank01..15 exist; milestone i uses pvprank(i)
-- by default, leaving pvprank15 spare. Override any rankIcon field to remap.
--
-- Item rewards alternate mount / full transmog set: iconic 3.3.5 mounts of
-- increasing prestige, and the classic Tier 2 sets (verified 3.3.5 item IDs).
-- This table must mirror the server's world.prestige_milestone rows (the
-- server grants the rewards; this copy only drives the UI display).
PrestigeData.Milestones = {
    [1] = {
        totalPrestiges    = 1,
        rankIcon          = RANK_ICON:format(1),
        title             = nil,
        item              = { type = "mount", itemID = 610261, name = "Kor'kron Juggernaut",
            creatureID = 610261 },
    },
    [2] = {
        totalPrestiges    = 3,
        rankIcon          = RANK_ICON:format(2),
        title             = nil,
        -- Display name from the reward table; the item itself is
        -- "Fire Chimera Mount Red" (620073)
        item              = { type = "mount", itemID = 620073, name = "Molten Cormaera",
            creatureID = 610324 },
    },
    [3] = {
        totalPrestiges    = 5,
        rankIcon          = RANK_ICON:format(3),
        title             = nil,
        -- Display name from the reward table; the mount itself is
        -- "Fire Raven God Mount Red1" (610223 Green / 610224 Purple also exist)
        item              = { type = "mount", itemID = 610225, name = "Flametalon of Alysrazor",
            creatureID = 610225 },
        unlock            = "Tier 3",
    },
    [4] = {
        totalPrestiges    = 8,
        rankIcon          = RANK_ICON:format(4),
        title             = nil,
        -- Display name from the reward table; the mount itself is
        -- "Firehawk Mount" (610000)
        item              = { type = "mount", itemID = 610000, name = "Pureblood Fire Hawk",
            creatureID = 610000 },
        unlock            = "PvP Tier Set (Vanilla)",
    },
    [5] = {
        totalPrestiges    = 12,
        rankIcon          = RANK_ICON:format(5),
        title             = nil,
        -- Display name from the reward table; the mount itself is
        -- "Lava Horse Mount" (620055)
        item              = { type = "mount", itemID = 620055, name = "Cindermane Charger",
            creatureID = 610306 },
        unlock            = "Season 1 Gear",
    },
    [6] = {
        totalPrestiges    = 16,
        rankIcon          = RANK_ICON:format(6),
        title             = nil,
        -- Display name from the reward table; the item itself is
        -- "Ragnaros Mount" (610159)
        item              = { type = "mount", itemID = 610159, name = "Runebound Firelord",
            creatureID = 610159 },
        unlock            = "Season 2 Gear",
    },
    [7] = {
        totalPrestiges    = 21,
        rankIcon          = RANK_ICON:format(7),
        title             = nil,
        item              = { type = "weapon", itemID = 620035, name = "Vigfus Sword" },
        unlock            = "Season 3 Gear",
    },
    [8] = {
        totalPrestiges    = 27,
        rankIcon          = RANK_ICON:format(8),
        title             = nil,
        item              = { type = "weapon", itemID = 620025, name = "Blackhand's Mace" },
        unlock            = "Season 4 Gear",
    },
    [9] = {
        totalPrestiges    = 33,
        rankIcon          = RANK_ICON:format(9),
        title             = nil,
        -- Aggramar Sword II, the 2H version (620034 = 1H variant)
        item              = { type = "weapon", itemID = 620036, name = "Aggramar's Sword" },
        unlock            = "Season 5 Gear",
    },
    [10] = {
        totalPrestiges    = 39,
        rankIcon          = RANK_ICON:format(10),
        title             = nil,
        item              = { type = "weapon", itemID = 247711, name = "The Horseman's Burning Greatblade" },
        unlock            = "Season 6 Gear",
    },
    [11] = {
        totalPrestiges    = 46,
        rankIcon          = RANK_ICON:format(11),
        title             = nil,
        item              = { type = "weapon", itemID = 155880, name = "Scythe of the Unmaker" },
        unlock            = "Season 7 Gear",
    },
    [12] = {
        totalPrestiges    = 54,
        rankIcon          = RANK_ICON:format(12),
        title             = nil,
        item              = { type = "weapon", itemID = 620005, name = "Fyr'alath, the Dreamrender" },
        unlock            = "Season 8 Gear",
    },
    [13] = {
        totalPrestiges    = 62,
        rankIcon          = RANK_ICON:format(13),
        title             = nil,
        -- Full outfit, head to feet: Devoted Warden's Gaze, Shoulderplates of
        -- Planar Isolation, Heartfire Sentinel's Pelerine / Brigandine,
        -- Manacles of Cruel Progress, Heartfire Sentinel's Protectors,
        -- Recycled Golemskin Waistguard, Heartfire Sentinel's Faulds,
        -- Sanctum Guard's Forgewalkers
        item              = { type = "transmogSet", name = "Heartfire Sentinel's Authority",
            items = { 190042, 190040, 190037, 190038, 190039, 190050,
                190041, 190051, 190043 } },
    },
    [14] = {
        totalPrestiges    = 75,
        rankIcon          = RANK_ICON:format(14),
        title             = nil,
        -- Display name from the reward table; the item itself is
        -- "Riding Phoenix Mount" (620072)
        item              = { type = "mount", itemID = 620072, name = "Golden Ashes of Al'ar",
            creatureID = 610323 },
    },
}

-- ============================================================================
-- Accessors (derived from the table above; no balancing below this line)
-- ============================================================================

--- Highest milestone index reached for a given total prestige count (0..14).
function PrestigeData.GetRank(totalPrestiges)
    totalPrestiges = totalPrestiges or 0
    local rank = 0
    for i, ms in ipairs(PrestigeData.Milestones) do
        if totalPrestiges >= ms.totalPrestiges then
            rank = i
        else
            break
        end
    end
    return rank
end

--- Next milestone still ahead of the given count: index, milestone (nil, nil
--- once all 14 are done).
function PrestigeData.GetNextMilestone(totalPrestiges)
    local rank = PrestigeData.GetRank(totalPrestiges)
    if rank >= #PrestigeData.Milestones then return nil, nil end
    return rank + 1, PrestigeData.Milestones[rank + 1]
end

--- Progress across the milestone bar as 0..1. The bar is divided into 14
--- equal visual segments (one per milestone); within the active segment the
--- fill interpolates between the two surrounding cumulative thresholds, so
--- the fill touches bubble i exactly when milestone i completes.
function PrestigeData.GetProgressFraction(totalPrestiges)
    totalPrestiges = totalPrestiges or 0
    local count = #PrestigeData.Milestones
    local rank = PrestigeData.GetRank(totalPrestiges)
    if rank >= count then return 1 end
    local prev = (rank == 0) and 0 or PrestigeData.Milestones[rank].totalPrestiges
    local nextTotal = PrestigeData.Milestones[rank + 1].totalPrestiges
    local partial = 0
    if nextTotal > prev then
        partial = (totalPrestiges - prev) / (nextTotal - prev)
    end
    return (rank + math.max(0, math.min(partial, 1))) / count
end

--- Rank icon path for a rank (1..14), nil for rank 0 or missing config.
function PrestigeData.GetRankIcon(rank)
    local ms = PrestigeData.Milestones[rank]
    return ms and ms.rankIcon or nil
end

--- Every item reward of a milestone as an array: normalizes the plural
--- `items` form and the singular `item` form (empty array when none).
function PrestigeData.GetRewardItems(ms)
    if not ms then return {} end
    if ms.items and #ms.items > 0 then return ms.items end
    if ms.item then return { ms.item } end
    return {}
end

--- Permanent Soul Ash bonus a prestige would grant, as a fraction (0.20 = +20%).
--- PROPORTIONAL to the committed pool it destroys, counted in gate worths:
--- burning the gate exactly grants the base rate, burning ten gates grants ten
--- times that. Mirrors PrestigeHandler::ComputeSoulAshBonusPct server-side;
--- the two MUST stay identical or the preview lies about what the reset buys.
---@param destroyedSoulAshes number committed pool the prestige would consume
function PrestigeData.ComputeBonusPct(destroyedSoulAshes)
    local C = ProjectEbonhold.Constants
    local gate = C.PRESTIGE_GATE_SOUL_ASHES or 0
    local cap = C.PRESTIGE_SOUL_ASH_BONUS_MAX_DESTROYED or 0
    destroyedSoulAshes = destroyedSoulAshes or 0
    if gate <= 0 or destroyedSoulAshes <= 0 then return 0 end

    -- Past the cap the extra ashes still burn, they just stop buying bonus.
    local counted = (cap > 0) and math.min(destroyedSoulAshes, cap) or destroyedSoulAshes
    local gateWorths = counted / gate

    -- Diminishing returns above the gate: each further gate worth is worth
    -- less than the one before. At exactly one gate worth this is a no-op, so
    -- the floor stays the advertised base rate.
    local pct = C.PRESTIGE_SOUL_ASH_GAIN_PER_PRESTIGE * (gateWorths ^ (C.PRESTIGE_SOUL_ASH_BONUS_EXPONENT or 1))

    -- Rounded UP to a whole percent, exactly as the server grants it
    -- (PrestigeHandler::ComputeSoulAshBonusPct), so the preview shows the
    -- number the player will actually receive.
    return math.ceil(pct * 100) / 100
end
