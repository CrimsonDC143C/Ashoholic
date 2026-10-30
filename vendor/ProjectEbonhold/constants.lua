ProjectEbonhold = ProjectEbonhold or {}

LFD_RANDOM_REWARD_EXPLANATION1 = "The first 3 random dungeons that you complete each day will earn you:"
    
ProjectEbonhold.ActionTypes = {
    INSTANCE_RESET = 1,
}

ProjectEbonhold.InstanceResetConfig = {
    BASE_COST = 50000,
    COST_MULTIPLIER = 5,
}

ProjectEbonhold.Constants = {
    MAX_INTENSITY = 475,
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
    -- Intensity Levels
    INTENSITY_LEVEL_1 = 75,
    INTENSITY_LEVEL_2 = 200,
    INTENSITY_LEVEL_3 = 275,
    INTENSITY_LEVEL_4 = 400,
    INTENSITY_LEVEL_5 = 475,
    ENABLE_BANISH_SYSTEM = true,
    -- Transmog
    TRANSMOG_DEBUG_ENABLED = false,
    OUTFIT_DEBUG_ENABLED = false,
}

ProjectEbonhold.IntensityEffects = {
    {
        name = "Intensity I",
        icon = "Interface\\Icons\\spell_nzinsanity_chasedbyshadows",
        description =
        "Soul Ash gain increased by 20%.\n\nThe darkness grows restless. Corrupted creatures surge, their blows infused with shadow energy. These twisted beings are stronger and more resilient and are dealing shadow damage on hit.",
    },
    {
        name = "Intensity II",
        icon = "Interface\\Icons\\spell_shadow_twistedfaith",
        description =
            "Soul Ash gain increased by 30%.\n\nThe Lich King's gaze falls upon you. Periodically, a searing shadow mark scorches the ground beneath your feet, " ..
            "dealing 5% of your maximum health as damage after 3 seconds, and then detonates and dealing shadow damage and those struck suffer increased shadow damage taken.",
    },
    {
        name = "Intensity III",
        icon = "Interface\\Icons\\achievement_boss_lichking",
        description =
        "Soul Ash gain increased by 40%.\n\nThe shadow marks grow more volatile. Up to 3 more can now scorch the ground simultaneously at random location, and their dark energy seeps into nearby creatures, healing them.",
    },
    {
        name = "Intensity IV",
        icon = "Interface\\Icons\\spell_shadow_unstableaffliction_3",
        description =
        "Soul Ash gain increased by 50%.\n\nThe Lich King unleashes periodically his Champions",
    },
    {
        name = "Intensity V",
        icon = "Interface\\Icons\\spell_shadow_deathscream",
        description =
        "If you survive for 10 minutes, the Lich King will send the Reaper after you.",
    }
}

ProjectEbonhold.SoulAshesMilestones = {
    { soulAshes = 1000000, spellID = 101259 },
    { soulAshes = 2000000, spellID = 101260 },
    { soulAshes = 25000000, spellID = 101261 },
    { soulAshes = 100000000, spellID = 101262 },
    { soulAshes = 215000000, spellID = 101263 }
}

--- Committed Soul Ashes required to run a Hardcore difficulty tier, keyed by difficulty tier.
--- Tier 1 is Normal and is never gated; tier N (>= 2) is Hardcore N-1.
---
--- NOT derived from the Soul Ashes milestones above: the two are unrelated, and reading the
--- milestones gave gates up to three times too high. Written out in full for that reason.
---
--- CLIENT-SIDE ONLY, for rendering the lock state. The rule that actually applies is the
--- server's Ashendor.Hardmode.SoulAshGates (HardmodeMgr::MeetsSoulAshGate), which is
--- re-checked on every difficulty-switch path; the two MUST be retuned together, exactly
--- like PRESTIGE_GATE_SOUL_ASHES mirrors PrestigeHandler::PRESTIGE_GATE_SOUL_ASHES.
ProjectEbonhold.HARDCORE_SOUL_ASH_GATES = {
    -- EMPTY: no tier costs Soul Ashes anymore. Hardcore access is gated by the "Ahead of the
    -- Curve" achievements alone (HARDCORE_ACHIEVEMENT_GATES below). Kept as a table because a
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

--- Achievement required to run a Hardcore difficulty tier, keyed by difficulty tier.
--- "Ahead of the Curve" I-V (6478-6482): each asks for a raid final boss killed at the tier
--- BELOW the one it unlocks, so access is proven by content cleared rather than by a balance.
---
---   Hardcore 1 (tier 2) : Kel'Thuzad on Normal
---   Hardcore 2 (tier 3) : Yogg-Saron on Hardcore 1 or higher
---   Hardcore 3 (tier 4) : Anub'arak on Hardcore 2 or higher
---   Hardcore 4 (tier 5) : the Lich King (ICC 25) on Hardcore 3 or higher
---   Hardcore 5 (tier 6) : Halion on Hardcore 4 or higher
---
--- CLIENT-SIDE ONLY, like the Soul Ash table above: the server re-checks its own copy on every
--- difficulty-switch path. Unlike Soul Ashes, achievement state is per CHARACTER and is known
--- to the client immediately, so nothing here has to wait on a server push.
ProjectEbonhold.HARDCORE_ACHIEVEMENT_GATES = {
    [2] = 6478,   -- Ahead of the Curve I
    [3] = 6479,   -- Ahead of the Curve II
    [4] = 6480,   -- Ahead of the Curve III
    [5] = 6481,   -- Ahead of the Curve IV
    [6] = 6482,   -- Ahead of the Curve V
}

---@param tier number difficulty tier (1 = Normal)
---@return number achievement id required, 0 when the tier has no achievement requirement
ProjectEbonhold.GetHardcoreAchievementGate = function(tier)
    tier = tonumber(tier) or 1
    if tier < 2 then return 0 end

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
            line = "When you die, your Soul Ashes will be added to your Skill Tree.",
        },
        multiplier = {
            title = function(mult)
                return "Soul Ash Multiplier: +" ..
                    string.format("%.0f", mult * 100) .. "%"
            end,
            line =
            "This is your Soul Ash gain multiplier. You can increase it by completing achievements and reaching higher Intensity levels."
        },
        reaper = {
            title = "The Reaper",
            spawned = function(areaName)
                return "The Reaper is in |cffFF4500" .. areaName .. "|r"
            end,
            notSpawned = "The Reaper is not spawned"
        },
        survival = {
            title = "Survival Stats",

            playerRezs = "Player-Granted Resurrections (Max Allowed): ",
            freeRezs = "Free Self-Resurrections (No Soul Ash Cost): ",
            classRezs = "Class-Based Resurrections (Reincarnate, Soulstone): ",
            cheatDeath = "Cheat Death Charges: ",
            nextRezCost = "Cost of Next Resurrection: ",
            nextCost = " Soul Ash"
        },
        intensity = {
            title = function(intensity)
                return "Intensity: " .. intensity
            end,
            description1 =
            "Defeating enemies more quickly raises your intensity faster, while killing grey enemies grants no intensity. Your intensity gradually decays while you are out of combat. Below are the effects of each intensity threshold. ",
            warning =
            "Warning: Staying alive at Intensity Level 5 for 10 minutes will unleash the Wrath of the Lich King!"
        }
    },
    ui = {
        echoes = function(count) return "Echoes (" .. count .. ")" end,
        stack = function(current, max)
            return "Stack: " .. current .. "/" .. max
        end
    }
}


ProjectEbonhold.DeathTexts = {
    frame = {
        title = "You are dead",
        description = "Choose an option:",
        arenaTitle = "Spectator Mode",
        arenaDescription = "You can spectate the arena:",
        battlegroundTitle = "Battleground Death"
    },

    buttons = {
        acceptDeath = function(soulPointsGain)
            return "Accept Death    |cff00FF00+" .. tostring(soulPointsGain) ..
                " Soul Ashes|r"
        end,
        releaseSpirit = "Release Spirit",
        useSoulstone = function(text, countCanClassRezs)
            return "Resurrect with " .. text .. " " ..
                tostring(countCanClassRezs) .. " remaining"
        end,
        selfRezAvailable = function(count)
            return "Resurrect without penalty " .. tostring(count) ..
                " remaining"
        end,
        soulPointsAffordable = function(cost)
            return "Resurrect |cffEB0000-" .. cost .. "|r Soul Ashes"
        end,
        acceptPlayerRez = function(count)
            return "Player Resurrection (" .. tostring(count) .. " remaining)"
        end
    },

    confirmations = {
        acceptDeath = {
            title = "Confirm Accept Death",
            message = function(soulPointsGain)
                return "You will gain " .. soulPointsGain ..
                    " Soul Ashes that you can spend in the Skill Tree.\n\nYour equipped gear will be sent to your inventory, and you will be reset to level 1 and teleported to your starting zone.\n\nAre you sure?"
            end
        },
        selfRez = {
            title = "Confirm Self Resurrection",
            message = function(remaining)
                return
                    "Use one of your remaining self resurrections?\n\nYou will be resurrected at the nearest graveyard.\n\n(" ..
                    remaining .. " remaining)"
            end
        },
        soulPointsRez = {
            title = "Confirm Soul Ashes Resurrection",
            message = function(cost, remaining)
                return "Use " .. cost ..
                    " Soul Ashes to resurrect?\n\nYou will have " ..
                    remaining .. " Soul Ashes remaining and will be resurrected at the nearest graveyard."
            end
        },
        soulstone = {
            title = function(text)
                return "Confirm " .. text .. " Usage"
            end,
            message = function(text, remaining)
                return "Use your " ..
                    text .. " to resurrect?\n\nYou will be resurrected at the nearest graveyard.\n\n(" ..
                    remaining .. " class resurrections remaining)"
            end
        },
        acceptPlayerRez = {
            title = "Confirm Player Resurrection",
            message = function(remaining)
                return "Accept resurrection from another player?\n\nYou will be resurrected at your friend's location.\n\n(" ..
                    remaining .. " accepted resurrections remaining)"
            end
        }
    },


    tooltips = {
        acceptDeath = {
            title = "Accept Death",
            line1 = function(soulPointsGain)
                return "You will gain " .. soulPointsGain .. " Soul Ashes."
            end,
            line2 = "Soul Ashes can be spent in the Skill Tree to unlock powerful abilities."
        },
        selfRez = {
            title = "Self Resurrection",
            line1 = "Revive without any penalty.",
            line2 = function(remaining)
                return "You have " .. remaining .. " remaining."
            end
        },
        soulPointsRez = {
            title = "Soul Ashes Resurrection",
            canAfford = {
                line1 = function(cost)
                    return "Use " .. cost .. " Soul Ashes to resurrect."
                end,
                line2 = "This will deduct Soul Ashes from your current run, not from your Skill Tree.",
                line3 = function(remaining)
                    return "You will have " .. remaining ..
                        " Soul Ashes remaining in this run."
                end
            },
            cantAfford = {
                line1 = function(cost)
                    return "You need " .. cost .. " Soul Ashes to resurrect."
                end,
                line2 = function(current)
                    return "You currently have " .. current ..
                        " Soul Ashes in this run."
                end
            }
        },
        soulstone = {
            title = function(text) return "Use " .. text end,
            line1 = function(text)
                return "Use your " .. text .. " to resurrect."
            end,
            line2 = function(remaining)
                return "You have " .. remaining ..
                    " class resurrections remaining."
            end
        },
        acceptPlayerRez = {
            title = "Accept Player Resurrection",
            line1 = "Accept resurrection from another player.",
            line2 = function(remaining)
                return "You have " .. remaining ..
                    " accepted resurrections remaining."
            end
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
