local addonName = ...
local addon = _G[addonName] or {}
_G[addonName] = addon

SLASH_ASHOHOLICPREVIEW1 = "/ash"
SLASH_ASHOHOLICPREVIEW2 = "/ashoholic"
SlashCmdList["ASHOHOLICPREVIEW"] = function(input)
    local text = string.gsub(input or "", "^%s*(.-)%s*$", "%1")
    local first, rest = string.match(text, "^(%S+)%s*(.-)%s*$")
    local command = first and string.lower(first) or ""
    if command == "" or command == "roster" then
        addon:ToggleRosterUI()
    elseif command == "preview" then
        addon:TogglePreviewUI()
    elseif command == "settings" then
        addon.UI.ToggleSettings()
    elseif command == "sync" then
        local subcommand, argument = string.match(rest, "^(%S+)%s*(.-)%s*$")
        local action = subcommand and string.lower(subcommand) or "all"
        local sync = addon.Sync
        local ok, problem
        if action == "trust" then
            ok, problem = pcall(sync.Trust, argument)
        elseif action == "remove" or action == "untrust" then
            ok, problem = pcall(sync.Untrust, argument)
        elseif action == "list" then
            ok, problem = pcall(sync.ListPeers)
        elseif action == "all" then
            ok, problem = pcall(sync.StartAll)
        else
            ok, problem = pcall(sync.Start, rest)
        end
        if not ok then print("|cffff6060Ashoholic sync:|r " .. tostring(problem)) end
    else
        print("|cFFFFD700Ashoholic:|r /ash, /ash preview, /ash settings, /ash sync [all|Character], /ash sync [trust|remove|list] [Character].")
    end
end
