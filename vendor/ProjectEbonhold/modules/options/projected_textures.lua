-- File: projected_textures.lua
-- Keeps the "Projected Textures" video option on. Boss telegraphs (ground marks)
-- are drawn as projected textures: with the option off - which the Low graphics
-- preset does - they are invisible, and the player is hit by mechanics they cannot see.
-- Re-enabled at login, whenever a CVar changes, and when the Video options close.

local CVAR = "projectedTextures"
local warned = false

local function EnsureProjectedTextures()
    if GetCVar(CVAR) == "1" then return end
    SetCVar(CVAR, "1")
    if not warned then
        warned = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[ProjectEbonhold]|r Projected Textures re-enabled: boss telegraphs need it to be visible.")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CVAR_UPDATE")
frame:SetScript("OnEvent", EnsureProjectedTextures)

if VideoOptionsFrame then
    VideoOptionsFrame:HookScript("OnHide", EnsureProjectedTextures)
end
