ProjectEbonhold = ProjectEbonhold or {}

-- Rewritten at runtime by modules/dungeonFinder (the orb count depends on the Torment picked).
LFD_RANDOM_REWARD_EXPLANATION1 = "Every dungeon you complete through the Dungeon Finder earns Orbs of Lost Memories."
LFD_RANDOM_REWARD_EXPLANATION2 = LFD_RANDOM_REWARD_EXPLANATION1
    
ProjectEbonhold.Constants = {
    MAX_SOUL_ASHES = 428303860,
    -- Committed Soul Ashes required to unlock a prestige (display value;
    -- must mirror PrestigeHandler::PRESTIGE_GATE_SOUL_ASHES server-side)
    PRESTIGE_GATE_SOUL_ASHES = 10771440,
    -- Permanent Soul Ash gain granted by a prestige. It is PROPORTIONAL to the
    -- committed pool the reset destroys, counted in "gate worths": prestiging
    -- the moment the gate opens burns one and grants the full base rate,
    -- banking ten gate worths grants ten times that. A flat rate punished
    -- banking, so a player sitting on 400M lost everything for the same +3%
    -- as one resetting at the gate.
    --
    --   gateWorths = min(destroyed, CAP) / PRESTIGE_GATE_SOUL_ASHES
    --   bonus      = PRESTIGE_SOUL_ASH_GAIN_PER_PRESTIGE
    --                * gateWorths ^ PRESTIGE_SOUL_ASH_BONUS_EXPONENT
    --
    -- The rate is the SAME at every prestige number: the milestone track ends
    -- at 75, the Soul Ash gain does not.
    --
    -- Above the gate the curve DIMINISHES: banking 37 gate worths (the 400M
    -- cap) pays about 6 times the base rate, not 37, so hoarding stays worth
    -- it without ever being the only sane play.
    --
    -- Past the cap the reset still destroys everything, it just stops buying
    -- more. Must mirror PrestigeHandler::ComputeSoulAshBonusPct EXACTLY
    -- (server side), or the preview lies about what the reset buys.
    PRESTIGE_SOUL_ASH_GAIN_PER_PRESTIGE = 0.20,
    PRESTIGE_SOUL_ASH_BONUS_MAX_DESTROYED = 400000000,
    -- Curve of the diminishing returns: 1.0 = linear, 0.5 = square root.
    -- Must equal PrestigeHandler::PRESTIGE_BONUS_EXPONENT server side.
    PRESTIGE_SOUL_ASH_BONUS_EXPONENT = 0.5,
    -- Absolute ceiling on the TOTAL Soul Ash bonus an account can hold from prestiging
    -- (15.0 = +1500%). Enforced SERVER-side in SoulPointsHandler::GetAccountSoulPointsMultiplier,
    -- which subtracts everything above PrestigeHandler::PRESTIGE_BONUS_MAX_TOTAL before any
    -- reward is computed; mirrored here only so the preview never promises past it.
    PRESTIGE_SOUL_ASH_BONUS_MAX_TOTAL = 100.0,
    ENABLE_BANISH_SYSTEM = true,
    -- Transmog
    TRANSMOG_DEBUG_ENABLED = false,
    OUTFIT_DEBUG_ENABLED = false,
}

ProjectEbonhold.SoulAshesMilestones = {
    { soulAshes = 1000000, spellID = 101259 },
    { soulAshes = 2000000, spellID = 101260 },
    { soulAshes = 25000000, spellID = 101261 },
    { soulAshes = 100000000, spellID = 101262 },
    { soulAshes = 215000000, spellID = 101263 }
}

--- Committed Soul Ashes required to run a Torment difficulty tier, keyed by difficulty tier.
--- Tier 1 is Normal and is never gated; tier N (>= 2) is Torment N-1.
---
--- NOT derived from the Soul Ashes milestones above: the two are unrelated, and reading the
--- milestones gave gates up to three times too high. Written out in full for that reason.
---
--- CLIENT-SIDE ONLY, for rendering the lock state. The rule that actually applies is the
--- server's Ashendor.Hardmode.SoulAshGates (HardmodeMgr::MeetsSoulAshGate), which is
--- re-checked on every difficulty-switch path; the two MUST be retuned together, exactly
--- like PRESTIGE_GATE_SOUL_ASHES mirrors PrestigeHandler::PRESTIGE_GATE_SOUL_ASHES.
ProjectEbonhold.HARDCORE_SOUL_ASH_GATES = {
    -- EMPTY: no tier costs Soul Ashes anymore. Torment access is gated by the "Unlocking
    -- Torment" achievements alone (HARDCORE_ACHIEVEMENT_GATES below). Kept as a table because a
    -- realm can put a floor back from config (Ashendor.Hardmode.SoulAshGates) - mirror it here
    -- if that ever happens, or the UI will advertise a tier the server refuses.
}

---@param tier number difficulty tier (1 = Normal)
---@return number committed Soul Ashes required, 0 when the tier has no requirement
ProjectEbonhold.GetHardcoreSoulAshGate = function(tier)
    tier = tonumber(tier) or 1
    if tier < 2 then return 0 end

    return ProjectEbonhold.HARDCORE_SOUL_ASH_GATES[tier] or 0
end

--- Achievement required to run a Torment difficulty tier, keyed by difficulty tier.
--- "Unlocking Torment" I-X (6478-6487): each asks for content cleared at the tier BELOW the one
--- it unlocks - EITHER any raid boss OR ten Northrend dungeons at level 80 - so access is proven by content
--- cleared rather than by a balance, and a group is never the only way up.
---
---   Torment 1 (tier 2)  : cleared on Normal
---   Torment 2 (tier 3)  : cleared on Torment 1
---   ...
---   Torment 10 (tier 11): cleared on Torment 9
---
--- Torment 11-30 have NO achievement: they are cosmetic rungs above the ladder, health and
--- damage only, and are gated by holding Torment 10 rather than by a feat of their own.
---
--- CLIENT-SIDE ONLY, like the Soul Ash table above: the server re-checks its own copy
--- (HardmodeMgr::GetAchievementGate) on every difficulty-switch path. Unlike Soul Ashes,
--- achievement state is known to the client immediately, so nothing here waits on a server push.
ProjectEbonhold.HARDCORE_ACHIEVEMENT_GATES = {
    [2]  = 6478,   -- Unlocking Torment I
    [3]  = 6479,   -- Unlocking Torment II
    [4]  = 6480,   -- Unlocking Torment III
    [5]  = 6481,   -- Unlocking Torment IV
    [6]  = 6482,   -- Unlocking Torment V
    [7]  = 6483,   -- Unlocking Torment VI
    [8]  = 6484,   -- Unlocking Torment VII
    [9]  = 6485,   -- Unlocking Torment VIII
    [10] = 6486,   -- Unlocking Torment IX
    [11] = 6487,   -- Unlocking Torment X
}

---@param tier number difficulty tier (1 = Normal)
---@return number achievement id required, 0 when the tier has no achievement requirement
ProjectEbonhold.GetHardcoreAchievementGate = function(tier)
    tier = tonumber(tier) or 1
    if tier < 2 then return 0 end

    -- Torment 11-30 are cosmetic and have no achievement of their own: they are gated by the last
    -- rung of the ladder, exactly as HardmodeMgr::GetAchievementGate does server-side.
    if tier > 11 then tier = 11 end

    return ProjectEbonhold.HARDCORE_ACHIEVEMENT_GATES[tier] or 0
end

-- 12345678 -> "12,345,678" -- shared thousands separator for UI numbers
-- (Soul Ash balances/costs get large enough to be unreadable without it)
--
-- string.format("%.0f", ...) rather than tostring(): Soul Ashes are 64-bit server-side and
-- routinely pass a billion, and tostring() switches to scientific notation ("1.2345678901235e+16")
-- past 14 significant digits, which the separator pattern below would then mangle. %.0f always
-- prints plain decimal digits. Never %d here - that truncates to a 32-bit int on this client,
-- so anything above 2,147,483,647 comes out as garbage.
ProjectEbonhold.FormatThousands = function(n)
    local s = string.format("%.0f", math.floor(tonumber(n) or 0))
    while true do
        local replaced
        s, replaced = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then break end
    end
    return s
end

ProjectEbonhold.UITexts = {
    tooltips = {
        soulPoints = {
            title = function(sp) return "Soul Ashes: " .. ProjectEbonhold.FormatThousands(sp) end,
            line = "Earned this run. Banked when you make an offering at a Spirit Healer or accept death.",
        },
        soulShards = {
            title = function(n) return "Soul Shards: " .. ProjectEbonhold.FormatThousands(n) end,
            line = "Earned this run. Banked with your Soul Ashes.",
        },
        shardMultiplier = {
            title = function(pct) return "Soul Shard Multiplier: +" .. pct .. "%" end,
            line =
            "Raised by Endless Harvest."
        },
        multiplier = {
            title = function(mult)
                return "Soul Ash Multiplier: +" ..
                    string.format("%.0f", mult * 100) .. "%"
            end,
            line =
            "Raised by achievements and Endless Harvest."
        },
        survival = {
            title = "Resurrections",
            paidRezs = function(used, ashes, shards, affordable)
                if affordable then
                    return "Soul Ash resurrection: |cffEB0000" .. ashes .. " Ashes, " .. shards .. " Shards|r (" .. used .. " used this run)"
                end
                return "Soul Ash resurrection: |cff888888not enough Soul Ashes|r (" .. used .. " used this run)"
            end,
            friendRezs = function(left, max)
                return "Player resurrection: " .. left .. "/" .. max .. " this run"
            end,
            hint = "Each Soul Ash resurrection costs more than the last. Counters reset on accept death.",
        },
        -- The Reaper's Gaze bar (player_run_ui.lua): the explanation lives in the run tour
        bracket = {
            title = "The Reaper's Gaze",
            rules =
            "Dying loses the contracts in progress; the bonus stays. Accepting death ends the run: its ashes are banked without the bonus, and the bonus is gone.",
        }
    },
    ui = {
        echoes = function(count) return "Echoes (" .. count .. ")" end,
        stack = function(current, max)
            return "Stack: " .. current .. "/" .. max
        end
    }
}


-- Death buttons are narrow: 2515648 -> "2.5M", 314456 -> "314K", 256 -> "256".
local function ShortNumber(n)
    n = tonumber(n) or 0
    if n >= 1e6 then return (string.format("%.1fM", n / 1e6):gsub("%.0M", "M")) end
    if n >= 1e3 then return string.format("%dK", math.floor(n / 1e3)) end
    return tostring(n)
end

local DEATH_ASH_ICON   = " |TInterface\\Icons\\inv_soulash:14:14:0:0|t"
local DEATH_SHARD_ICON = " |TInterface\\Icons\\inv_10_jewelcrafting3_soulcage_frost:14:14:0:0|t"

ProjectEbonhold.DeathTexts = {
    frame = {
        title = "You are dead",
        description = "Choose an option:",
        arenaTitle = "Spectator Mode",
        arenaDescription = "You can spectate the arena:",
        battlegroundTitle = "Battleground Death"
    },

    buttons = {
        acceptDeath = function(soulPointsGain, soulShardsGain)
            local text = "Accept Death  |cff00FF00+" .. ShortNumber(soulPointsGain) .. "|r" .. DEATH_ASH_ICON
            if (soulShardsGain or 0) > 0 then
                text = text .. " |cff8080ff+" .. ShortNumber(soulShardsGain) .. "|r" .. DEATH_SHARD_ICON
            end
            return text
        end,
        releaseSpirit = "Release Spirit",
        useSoulstone = function(text)
            return "Resurrect with " .. text
        end,
        soulPointsAffordable = function(ashes, shards)
            local text = "Resurrect  |cffEB0000-" .. ShortNumber(ashes) .. "|r" .. DEATH_ASH_ICON
            if (shards or 0) > 0 then
                text = text .. " |cffEB0000-" .. ShortNumber(shards) .. "|r" .. DEATH_SHARD_ICON
            end
            return text
        end,
        acceptPlayerRez = function(left, max)
            return "Player Resurrection  (" .. tostring(left) .. "/" .. tostring(max) .. ")"
        end
    },

    confirmations = {
        acceptDeath = {
            title = "Confirm Accept Death",
            message = function(soulPointsGain, soulShardsGain)
                local gains = soulPointsGain .. " Soul Ashes"
                if (soulShardsGain or 0) > 0 then
                    gains = gains .. " and " .. soulShardsGain .. " Soul Shards"
                end
                -- What PlayerRunHandler::AcceptDeath really does (checked 2026-10-22): ResetPlayer
                -- (level 1, quests, unlocked perks, start zone), CallboardMgr::OnAcceptDeath (board
                -- contracts dropped), ComputeGearToKeepEquippedAtLevelOne + TransferAndDestroyEquippedItems
                -- (wearable gear stays on, the rest to the bags), CommitAllSoulPoints (ashes + shards
                -- banked), LearnAllTreeSkills / ApplyOwnedNodes (tree and class nodes re-applied).
                return "|cffff4040You lose:|r your level, quests, contracts and unlocked echoes.\n\n" ..
                    "|cff00ff00You keep:|r " .. gains .. ", your Skill Tree, locked echoes and gear.\n\n" ..
                    "Are you sure?"
            end
        },
        soulPointsRez = {
            title = "Confirm Soul Ashes Resurrection",
            message = function(ashes, shards, ashesLeft, shardsLeft)
                return "Pay " .. ashes .. " Soul Ashes and " .. shards ..
                    " Soul Shards from your run to resurrect?\n\nYour run will keep " ..
                    ashesLeft .. " Soul Ashes and " .. shardsLeft .. " Soul Shards. You will be resurrected at the nearest graveyard."
            end
        },
        soulstone = {
            title = function(text)
                return "Confirm " .. text .. " Usage"
            end,
            message = function(text)
                return "Use your " ..
                    text .. " to resurrect?\n\nYou will be resurrected at the nearest graveyard."
            end
        },
        acceptPlayerRez = {
            title = "Confirm Player Resurrection",
            message = function()
                return "Accept resurrection from another player?\n\nYou will be resurrected at your friend's location."
            end
        }
    },


    tooltips = {
        acceptDeath = {
            title = "Accept Death",
            line1 = function(soulPointsGain, soulShardsGain)
                if (soulShardsGain or 0) > 0 then
                    return "You will gain " .. soulPointsGain .. " Soul Ashes and " .. soulShardsGain .. " Soul Shards."
                end
                return "You will gain " .. soulPointsGain .. " Soul Ashes."
            end,
            line2 = "Soul Ashes can be spent in the Skill Tree to unlock powerful abilities."
        },
        soulPointsRez = {
            title = "Soul Ashes Resurrection",
            line1 = function(ashes, shards)
                return "Pay " .. ashes .. " Soul Ashes and " .. shards .. " Soul Shards from your run to resurrect."
            end,
            line2 = "Paid from your run, not your account. Each one costs more than the last.",
            line3 = function(used)
                return used .. " used this run."
            end,
            tooPoor = "Your run does not hold enough Soul Ashes."
        },
        soulstone = {
            title = function(text) return "Use " .. text end,
            line1 = function(text)
                return "Use your " .. text .. " to resurrect."
            end,
            line2 = "Unlimited uses, no penalty."
        },
        acceptPlayerRez = {
            title = "Accept Player Resurrection",
            line1 = "Accept resurrection from another player.",
            line2 = "Free. You can accept one player resurrection per run. Any player can bring you back."
        }
    },


    messages = {
        notEnoughSoulPoints = "|cffFF0000Not enough Soul Ashes to resurrect!|r",
        arenaSpectator = function()
            return ARENA_SPECTATOR or "You are now spectating."
        end,
        confirmPrints = {
            acceptDeath = "Accept Death confirmed - Custom call to implement",
            selfRez = "Self resurrection confirmed - Custom call to implement",
            soulPointsRez = "Soul Ashes resurrection confirmed - Custom call to implement",
            acceptPlayerRez = "Accept Player Resurrection confirmed - Custom call to implement"
        }
    }
}


ProjectEbonhold.DeathRecapTexts = {
    button = "Death Recap",

    frame = {
        title = "Death Recap",
        killedBy = function(name)
            return "Killed by |cffFF4500" .. name .. "|r"
        end,
        killedByUnknown = "The killing blow was not recorded.",
        empty = "No combat damage was recorded before this death."
    },

    labels = {
        melee = "Melee",
        instakill = "Instant Kill",
        unknownSource = "Unknown",
        secondsBefore = function(seconds)
            return string.format("%.1fs before death", seconds)
        end,
        -- Row lines are narrow, so they use the short form and leave the full wording to tooltips.
        secondsShort = function(seconds)
            return string.format("%.1fs", seconds)
        end,
        hpLeft = function(current, max)
            return string.format("%s / %s", current, max)
        end
    },

    tooltip = {
        damageTaken = function(amount)
            return "Damage taken: |cffFF4040" .. amount .. "|r"
        end,
        healReceived = function(amount)
            return "Healing received: |cff40FF40" .. amount .. "|r"
        end,
        critical = "Critical",
        overkill = function(amount)
            return "Overkill: " .. amount
        end,
        absorbed = function(amount)
            return "Absorbed: " .. amount
        end,
        resisted = function(amount)
            return "Resisted: " .. amount
        end,
        blocked = function(amount)
            return "Blocked: " .. amount
        end,
        overhealing = function(amount)
            return "Overhealing: " .. amount
        end,
        healthAfter = function(current, max, percent)
            return string.format("Health: %s / %s (%d%%)", current, max, percent)
        end,
        healthNote = "Health is sampled when the event is received, so it can lag the log by a fraction of a second."
    },

    slash = {
        noRecap = "|cffFFFF00Project Ebonhold:|r no death recap recorded yet."
    }
}
