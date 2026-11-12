local addonName = ...
local addon = _G[addonName] or {}
_G[addonName] = addon

SLASH_ASHOHOLICPREVIEW1 = "/ash"
SLASH_ASHOHOLICPREVIEW2 = "/ashoholic"
SlashCmdList["ASHOHOLICPREVIEW"] = function(input)
    local command = string.lower(string.gsub(input or "", "^%s*(.-)%s*$", "%1"))
    if command == "" or command == "roster" then
        addon:ToggleRosterUI()
    elseif command == "preview" then
        addon:TogglePreviewUI()
    else
        print("|cFFFFD700Ashoholic:|r Use /ash for your roster or /ash preview for the sample preview.")
    end
end
