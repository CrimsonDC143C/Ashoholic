local ADDON_NAME = "ProjectEbonhold"

-- All of Project Ebonhold's settings UI is hand-written directly into the
-- client's native Interface Options (InterfaceOptionsPanels.xml/.lua,
-- packed into patch-8.MPQ): the nameplate reskin's on/off toggle lives in
-- the native "Names" panel, and everything else lives under its own native
-- "Project Ebonhold" category (Game tab) as a real expandable sidebar entry
-- with 4 sub-categories (General / Perks & Visual / Nameplates / Actionbar
-- Management), the same parent/child mechanism any Blizzard category with
-- sub-items uses. Those native controls read and write
-- ProjectEbonholdOptionsService directly -- this file only owns
-- initialization, nothing UI-related.
local function Initialize()
    ProjectEbonholdOptionsService:Initialize()

    -- One-time CVar defaults (Font Rendering on, Stance Patch on, tutorials
    -- off). Safe to call unconditionally; it only touches CVars + saved vars.
    if ProjectEbonhold and ProjectEbonhold.CVarOptions and ProjectEbonhold.CVarOptions.ApplyInitialDefaults then
        ProjectEbonhold.CVarOptions.ApplyInitialDefaults()
    end

    SLASH_PROJECTEBONHOLD1 = "/projectebonhold"
    SLASH_PROJECTEBONHOLD2 = "/peb"
    SlashCmdList["PROJECTEBONHOLD"] = function(msg)
        local panel = _G.InterfaceOptionsProjectEbonholdPanel
        if panel then
            InterfaceOptionsFrame_OpenToCategory(panel)
            InterfaceOptionsFrame_OpenToCategory(panel)
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == ADDON_NAME then
        Initialize()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
