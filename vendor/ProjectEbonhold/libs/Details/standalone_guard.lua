-- Details! is part of Project Ebonhold: this copy is the only one meant to run. A standalone
-- Details! still in Interface\AddOns would load first and fight this one for the same globals,
-- so it is switched off (as libs/pretty_patchkit/localization.lua does for its own standalone)
-- and, the session it was found running, the player is asked to reload.
for i = 1, GetNumAddOns() do
    local name = (GetAddOnInfo(i) or ""):lower()
    if name == "details" or name:find("^details_") then
        DisableAddOn(i)
    end
end

if IsAddOnLoaded("Details") then
    StaticPopupDialogs["EBONHOLD_DETAILS_RELOAD"] = {
        text = "Details! is now part of Project Ebonhold. Your separate copy has been disabled: reload the interface to finish.",
        button1 = "Reload Now",
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        preferredIndex = 3,
    }
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function() StaticPopup_Show("EBONHOLD_DETAILS_RELOAD") end)
end
