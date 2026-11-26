-- Core/Commands.lua
-- The /ash and /ashoholic chat commands.
--
-- Data flow: this file only forwards a typed command to the module that owns
-- it. The dashboard (UI/Dashboard.lua) opens windows; Sync/Transport.lua owns
-- trusted sharing. Nothing here reads game data or AshoholicDB directly.
--
-- Timing: the command table is registered while the addon loads, but WoW only
-- runs a command after the player types it, which is always after login. By
-- then every UI and Sync file listed later in Ashoholic.toc has loaded too.
local addonName = ...
local addon = _G[addonName]

local USAGE = "|cFFFFD700Ashoholic:|r /ash (open or close the roster), /ash settings, "
    .. "/ash sync [all|Character], /ash sync [trust|remove|list] [Character], /ash help."

-- Runs one sync action and reports a problem in chat instead of raising a Lua
-- error, because a typo in a character name is an ordinary mistake.
local function RunSync(action, argument)
    local ok, problem = pcall(action, argument)
    if not ok then
        print("|cffff6060Ashoholic sync:|r " .. tostring(problem))
    end
end

local function HandleSync(rest)
    local sync = addon.Sync
    local subcommand, argument = string.match(rest, "^(%S+)%s*(.-)%s*$")
    local action = subcommand and string.lower(subcommand) or "all"
    if action == "trust" then
        RunSync(sync.Trust, argument)
    elseif action == "remove" or action == "untrust" then
        RunSync(sync.Untrust, argument)
    elseif action == "list" then
        RunSync(sync.ListPeers)
    elseif action == "all" then
        RunSync(sync.StartAll)
    else
        -- Anything else is treated as a character name: "/ash sync Name".
        RunSync(sync.Start, rest)
    end
end

SLASH_ASHOHOLIC1 = "/ash"
SLASH_ASHOHOLIC2 = "/ashoholic"
SlashCmdList["ASHOHOLIC"] = function(input)
    -- Trim spaces, then split "first rest of the line".
    local text = string.gsub(input or "", "^%s*(.-)%s*$", "%1")
    local first, rest = string.match(text, "^(%S+)%s*(.-)%s*$")
    local command = first and string.lower(first) or ""

    if command == "" or command == "roster" then
        addon:ToggleRosterUI()
    elseif command == "settings" then
        addon.UI.ToggleSettings()
    elseif command == "sync" then
        HandleSync(rest)
    else
        print(USAGE)
    end
end
