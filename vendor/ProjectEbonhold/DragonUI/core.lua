-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = DragonUI
--[[
================================================================================
DragonUI - Core Initialization
================================================================================
This file handles the main addon initialization using AceAddon-3.0.
Utility functions have been moved to core/api.lua

Embedded in ProjectEbonhold, without its options panel (removed 2026-11-12).
================================================================================
]]

-- Expose addon globally (the options files read it)
_G.DragonUI = addon

-- Localization (initialized early in config.lua so core/ files can use it)
local L = addon.L

-- Create addon object using AceAddon
addon.core = LibStub("AceAddon-3.0"):NewAddon("DragonUI", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0");



-- Profile switches of the pieces ElvUI replaces (dragonui_ns.lua sets addon.elvui). Kept on: the
-- windows ElvUI leaves alone and our addon builds on (merchant, quest dialog, mail, flight map,
-- item level / quality, low-health alert, world map): ElvUI skins those (its Ebonhold_*.lua skins).
local ELVUI_YIELD_PATHS = {
    "modules.noop.enabled", "modules.mainbars.enabled", "modules.buttons.enabled", "modules.cooldowns.enabled",
    "modules.rage_indicator.enabled", "modules.vehicle.enabled", "modules.stance.enabled",
    "modules.petbar.enabled", "modules.multicast.enabled", "modules.extrabar1.enabled",
    "modules.micromenu.enabled", "modules.minimap.enabled", "modules.MinimapDecorations.enabled",
    "modules.buffs.enabled", "buffs.enabled", "modules.auraborders.enabled", "modules.auracooldowns.enabled",
    "modules.keybinding.enabled", "modules.personalresource.enabled", "modules.combopoints.enabled",
    "modules.totemframe.enabled", "modules.swingtimer.enabled", "modules.nameplates.enabled",
    "modules.tooltip.enabled", "modules.chatmods.enabled", "modules.bagster.enabled",
    "modules.bags_skin.enabled", "modules.bagsort.enabled", "modules.loot_skin.enabled",
    "modules.unitframe_layers.enabled", "castbar.enabled",
    "unitframe.player.enabled", "unitframe.target.enabled", "unitframe.focus.enabled",
    "unitframe.pet.enabled", "unitframe.party.enabled", "unitframe.tot.enabled",
    "unitframe.fot.enabled", "unitframe.boss.enabled",
}

-- "Old (Blizzard)" for the whole interface, picked in our Edit Mode (owner, 2026-11-18: a way to turn
-- DragonUI off entirely): global.playerOff. Same mechanism as ElvUI's, on every switch this time,
-- the windows ElvUI leaves to DragonUI included: every modules.<name>.enabled of the profile on top of
-- the list above. The player's values are kept and come back when New is picked again.
local function AllOffPaths()
    local paths, seen = {}, {}
    local function Add(path)
        if not seen[path] then seen[path] = true; paths[#paths + 1] = path end
    end
    for _, path in ipairs(ELVUI_YIELD_PATHS) do Add(path) end
    for _, source in ipairs({ addon.defaults and addon.defaults.profile and addon.defaults.profile.modules,
                              rawget(addon.db.profile, "modules") }) do
        if type(source) == "table" then
            for name, node in pairs(source) do
                if type(name) == "string" and type(node) == "table" and type(node.enabled) == "boolean" then
                    Add("modules." .. name .. ".enabled")
                end
            end
        end
    end
    return paths
end

local function ProfileNode(path)
    local node = addon.db.profile
    local keys = { strsplit(".", path) }
    for i = 1, #keys - 1 do
        node = type(node) == "table" and node[keys[i]] or nil
    end
    if type(node) == "table" then return node, keys[#keys] end
end

-- With ElvUI on (or the whole interface on Old, AllOffPaths): the player's values are kept in
-- global.elvuiYield[profile], then switched off. Without either: whatever was kept goes back.
-- Restored at the next login without them, so a crash or a disabled ElvUI never leaves DragonUI
-- half off.
function addon:ApplyElvUIYield()
    local global = addon.db.global
    local key = addon.db:GetCurrentProfile()
    local kept = global.elvuiYield and global.elvuiYield[key]
    if not addon.elvui and not addon.playerOff then
        if kept then
            for path, value in pairs(kept) do
                local node, leaf = ProfileNode(path)
                if node then node[leaf] = value end
            end
            global.elvuiYield[key] = nil
            if not next(global.elvuiYield) then global.elvuiYield = nil end
        end
        return
    end
    if not kept then
        kept = {}
        global.elvuiYield = global.elvuiYield or {}
        global.elvuiYield[key] = kept
    end
    -- Every path, not only on the first run: one added to the list later is kept and switched off
    -- for a profile that already stepped aside before it existed; one taken off the list (the world
    -- map, 2026-11-16) gets its value back.
    local listed = {}
    for _, path in ipairs(addon.playerOff and AllOffPaths() or ELVUI_YIELD_PATHS) do
        listed[path] = true
        if kept[path] == nil then
            local node, leaf = ProfileNode(path)
            if node and node[leaf] ~= nil then kept[path] = node[leaf] end
        end
    end
    for path, value in pairs(kept) do
        if not listed[path] then
            local node, leaf = ProfileNode(path)
            if node then node[leaf] = value end
            kept[path] = nil
        end
    end
    for path in pairs(kept) do
        local node, leaf = ProfileNode(path)
        if node then node[leaf] = false end
    end
end

-- Frame positions shared by every character of the account (owner, 2026-11-18: "layouts saved at
-- the account level"). What our Edit Mode moves through DragonUI's movers lives in the profile, which
-- is per character: widgets (frames) and additional (stance / pet / totem / extra bars). A copy of
-- both sits in global.sharedLayout, written when a character leaves Edit Mode with positions changed
-- (modules\editMode\edit_mode.lua, DUIHideMovers), and laid over the profile at every load. The other
-- DragonUI settings (New / Old per frame, bar options...) stay per character.
local SHARED_LAYOUT_KEYS = { "widgets", "additional" }

function addon:LoadSharedLayout()
    local shared = addon.db.global.sharedLayout
    if type(shared) ~= "table" then return end
    local profile = addon.db.profile
    for _, key in ipairs(SHARED_LAYOUT_KEYS) do
        if type(shared[key]) == "table" then
            if type(profile[key]) ~= "table" then profile[key] = {} end
            addon.DeepCopy(shared[key], profile[key])   -- the account's values win, new keys keep their default
        end
    end
end

function addon:SaveSharedLayout()
    local shared = {}
    for _, key in ipairs(SHARED_LAYOUT_KEYS) do
        local t = addon.db.profile[key]
        if type(t) == "table" then shared[key] = addon.DeepCopy(t, {}) end
    end
    addon.db.global.sharedLayout = shared
end

function addon.core:OnInitialize()
    -- SavedVariables are loaded but AceDB is not, so read the account-wide setting
    -- straight off the table the way addon.GetActiveLocale does. AceDB consults this
    -- only for characters that have no profile yet, and New() errors on anything but
    -- a string or true - hence the type guard.
    local sv = _G.DragonUIDB
    local defaultProfile = sv and sv.global and sv.global.defaultProfile
    if type(defaultProfile) ~= "string" or defaultProfile == "" then
        defaultProfile = nil
    end

    -- Replace the temporary addon.db with the real AceDB
    addon.db = LibStub("AceDB-3.0"):New("DragonUIDB", addon.defaults, defaultProfile);

    -- First point where the stored language override is readable; UI is built later (PLAYER_LOGIN).
    addon.RefreshLocale()

    addon:ApplyDatabaseMigrations()

    -- Force defaults to be written to profile (check for specific key that should always exist)
    if not addon.db.profile.mainbars or not addon.db.profile.mainbars.scale_actionbar then
        -- Copy all defaults to profile to ensure they exist in SavedVariables
        addon.DeepCopy(addon.defaults.profile, addon.db.profile);
        addon:ApplyDatabaseMigrations()
    end

    addon.playerOff = addon.db.global.playerOff == true
    addon:ApplyElvUIYield()
    addon:LoadSharedLayout()

    -- Register callbacks for configuration changes
    addon.db.RegisterCallback(addon, "OnProfileChanged", "RefreshConfig");
    addon.db.RegisterCallback(addon, "OnProfileCopied", "RefreshConfig");
    addon.db.RegisterCallback(addon, "OnProfileReset", "RefreshConfig");

    -- Apply current profile configuration immediately
    -- This ensures the profile is loaded when the addon starts
    addon:RefreshConfig();
end

-- Account-wide default profile for characters that have never run DragonUI.
-- Lives in global rather than a profile so it survives profile switch/copy/reset;
-- the raw fallback mirrors addon.GetActiveLocale for calls made before AceDB exists.
function addon:GetDefaultProfileKey()
    local key
    if addon.db and addon.db.global then
        key = addon.db.global.defaultProfile
    else
        local sv = _G.DragonUIDB
        key = sv and sv.global and sv.global.defaultProfile
    end
    if type(key) == "string" and key ~= "" then
        return key
    end
    return nil
end

-- Pass nil or an empty string to go back to per-character profiles.
function addon:SetDefaultProfileKey(key)
    if not (addon.db and addon.db.global) then return end
    if type(key) == "string" and key ~= "" then
        addon.db.global.defaultProfile = key
    else
        addon.db.global.defaultProfile = nil
    end
end

function addon.core:OnEnable()
    -- /rl only (core\commands.lua)
    if addon.LoadCommands then addon.LoadCommands() end

    -- Fire custom event to signal that DragonUI is fully initialized
    -- This ensures modules get the correct config values
    self:SendMessage("DRAGONUI_READY");
end

-- Owner 2026-11-16: no Forever, only "New or Old" everywhere. A profile saved with a Forever look or a
-- variant the settings no longer offer is brought back to New, or it would keep drawing a look nobody can
-- pick again. (Unit frame art, level and dragon styles are forced in uf_skins.lua.)
local function NormalizeNewOld()
    local p = addon.db and addon.db.profile
    if not p then return end
    if type(p.minimap) == "table" and p.minimap.style ~= nil and p.minimap.style ~= "dragonui" then
        p.minimap.style = "dragonui"
    end
    if type(p.style) == "table" and p.style.gryphons ~= nil
        and p.style.gryphons ~= "new" and p.style.gryphons ~= "old" then
        p.style.gryphons = "new"
    end
    local np = type(p.modules) == "table" and p.modules.nameplates
    if type(np) == "table" and (np.plateStyle == "legacy" or np.plateStyle == "classic") then
        np.plateStyle, np.barWidth, np.barHeight = "modern", 148, 16   -- Modern's own bar size
    end
    local player = type(p.unitframe) == "table" and p.unitframe.player
    if type(player) == "table" and player.dragon_decoration ~= nil
        and player.dragon_decoration ~= "none" and player.dragon_decoration ~= "elite" then
        player.dragon_decoration = "elite"
    end
end

-- Callback function that refreshes all modules when configuration changes
function addon:RefreshConfig()
    -- Also runs on profile switch: the newly-activated profile may be older than the current schema.
    addon:ApplyDatabaseMigrations()
    NormalizeNewOld()

    -- Initialize cooldown system if it hasn't been already
    if addon.InitializeCooldowns then
        addon.InitializeCooldowns()
    end

    local failed = addon:RefreshRegisteredSystems() or {}

    -- If some configurations failed, retry them after 2 seconds
    if #failed > 0 then
        addon.core:ScheduleTimer(function()
            addon:RefreshRegisteredSystems()
        end, 2);
    end
end

