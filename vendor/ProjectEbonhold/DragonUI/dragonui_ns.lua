-- DragonUI's own namespace (upstream: the addon's private vararg table). Embedded in
-- ProjectEbonhold, it must not share ProjectEbonhold's table, so every DragonUI file
-- reads this global instead (rewritten by embed_dragonui.py). DragonUI_Options reads
-- _G.DragonUI too.
--
-- A standalone DragonUI still in Interface\AddOns would load first and fight this copy for
-- the same frames: it is switched off and, the session it was found running, the player is
-- asked to reload (as libs/Details/standalone_guard.lua does for Details!).
local standalone = IsAddOnLoaded("DragonUI")
for i = 1, GetNumAddOns() do
    local name = (GetAddOnInfo(i) or ""):lower()
    if name == "dragonui" or name == "dragonui_options" then
        DisableAddOn(i)
    end
end
if standalone then
    local L = ProjectEbonhold.L
    StaticPopupDialogs["EBONHOLD_DRAGONUI_RELOAD"] = {
        text = L["A separate copy of this interface addon was found and has been disabled: reload the interface to finish."],
        button1 = L["Reload Now"],
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        preferredIndex = 3,
    }
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function() StaticPopup_Show("EBONHOLD_DRAGONUI_RELOAD") end)
end

DragonUI = {}

-- ElvUI (offered on the website) replaces the same pieces as DragonUI: bars, unit frames, minimap,
-- micro menu, bags, chat, tooltip, nameplates, buffs. With both on, the two draw over each other.
-- When it runs, DragonUI steps aside from those pieces (core.lua, ApplyElvUIYield) and our Edit Mode
-- leaves them to ElvUI's movers. The client does not load addons in name order (ElvUI came
-- after us in a test), so "enabled and loadable" is asked, not "loaded".
do
    local ok, name, _, _, enabled, loadable = pcall(GetAddOnInfo, "ElvUI")
    DragonUI.elvui = IsAddOnLoaded("ElvUI") or (ok and name and enabled and loadable) and true or false
end

-- A bag addon (Bagnon and the like) opens its own bag and bank windows: Bagster opened its own on top
-- and the player got two sets of bags (PTR feedback 2026-11-18). While one runs, Bagster and the bag
-- skin stand down for the session (core\api.lua YieldedModule); nothing saved changes, so they come
-- back by themselves once the bag addon is off. Same "enabled and loadable" test as ElvUI above.
do
    for _, candidate in ipairs({ "Bagnon", "AdiBags", "ArkInventory", "OneBag3", "Baggins", "BaudBag",
                                 "Combuctor", "cargBags_Nivaya", "Inventorian" }) do
        local ok, name, _, _, enabled, loadable = pcall(GetAddOnInfo, candidate)
        if IsAddOnLoaded(candidate) or (ok and name and enabled and loadable) then
            DragonUI.bagAddon = candidate
            break
        end
    end
end

-- Same for a nameplate addon (Kui, TidyPlates...): it draws its own plates, and DragonUI's were drawn
-- on top of them (bug 4574). While one runs, DragonUI's nameplates stand down for the session
-- (core\api.lua YieldedModule, nameplates\core\config.lua IsModuleEnabled); nothing saved changes.
-- Addons that only add to the plates (PlateBuffs, Icicle...) are not listed: compatibility.lua has them.
do
    for _, candidate in ipairs({ "Kui_Nameplates", "TidyPlates", "NeatPlates", "Aloft", "ShaguPlates",
                                 "caelNamePlates", "dNamePlates", "rNamePlates" }) do
        local ok, name, _, _, enabled, loadable = pcall(GetAddOnInfo, candidate)
        if IsAddOnLoaded(candidate) or (ok and name and enabled and loadable) then
            DragonUI.nameplateAddon = candidate
            break
        end
    end
end
