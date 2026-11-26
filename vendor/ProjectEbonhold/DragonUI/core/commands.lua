-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

--[[
================================================================================
DragonUI - Slash Commands
================================================================================
Ashendor (2026-11-12): no /dragonui, /dui or /pi (owner: "on en veut pas"), and no
options panel. Only /rl is left. The Edit Mode is Project Ebonhold's (/editmode).
================================================================================
]]

local addon = DragonUI

local function ReloadUICommand()
    ReloadUI()
end

-- Called from core.lua's OnEnable.
function addon.LoadCommands()
    if addon.core and addon.core.RegisterChatCommand then
        addon.core:RegisterChatCommand("rl", ReloadUICommand)
    else
        SLASH_DRAGONUIRL1 = "/rl"
        SlashCmdList["DRAGONUIRL"] = ReloadUICommand
    end
end
