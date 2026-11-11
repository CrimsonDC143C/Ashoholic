local addonName = ...
local addon = {}
_G[addonName] = addon

SLASH_ASHOHOLICPREVIEW1 = "/ash"
SLASH_ASHOHOLICPREVIEW2 = "/ashoholic"
SlashCmdList["ASHOHOLICPREVIEW"] = function(input)
    local command = string.lower(string.gsub(input or "", "^%s*(.-)%s*$", "%1"))
    if command ~= "preview" then
        print("|cFFFFD700Ashoholic UI Preview:|r Use /ash preview.")
        return
    end
    addon:TogglePreviewUI()
end
