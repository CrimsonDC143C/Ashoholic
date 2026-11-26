-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = DragonUI
-- What each window drew on its first open (measured in game), loaded with the world so slow PCs skip that stall.
local WINDOWS = {
    worldmap = {
        "CharacterPanel\\collapsebuttons", "CharacterPanel\\scrollbararrows", "CharacterPanel\\scrollbarthumb",
        "UI\\ui-background-rock", "UI\\uiframe-inner", "UI\\uiframe-inner-vertical", "UI\\uiframeinner",
        "WorldMap\\mapfilter", "WorldMap\\mappins", "WorldMap\\navbar", "WorldMap\\navbar-tile", "WorldMap\\poiicons",
        "WorldMap\\questcollapse", "WorldMap\\questlog-background", "WorldMap\\questtypeicons",
        "WorldMap\\squarebuttons", "WorldMap\\trackingborder", "WorldMap\\zoomhighlight",
    },
    bagster = {
        "Bags\\INV_Misc_Bag_08_round", "Bags\\bagsitemslot2x", "Coins\\coincopper", "Coins\\coingold",
        "Coins\\coinsilver", "Coins\\commoncoinbox", "Coins\\commoncurrencybox", "UI\\buttonhilight-square",
        "UI\\ui-background-rock", "UI\\ui-quickslot2",
    },
}

-- DragonUI's own windows, there whatever modules are on: the options panel and editor mode.
local ALWAYS = {
    "ForeverUI\\chrome-options", "ForeverUI\\controls-dropdown", "Editmode\\editmodeui",
    "Editmode\\editmodeuihighlightbackground", "Editmode\\editmodeuivertical",
}

addon:RegisterTextureWarmup(function()
    local files = {}
    local function add(rel) files[#files + 1] = addon._dir .. rel end
    for _, rel in ipairs(ALWAYS) do add(rel) end
    for module, list in pairs(WINDOWS) do
        if addon:IsModuleEnabled(module) then
            for _, rel in ipairs(list) do add(rel) end
        end
    end
    return files
end)
