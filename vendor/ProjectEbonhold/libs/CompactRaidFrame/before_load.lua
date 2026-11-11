-- Compact Raid Frames (RomanSpector, a backport of Blizzard's raid frames) is part of Project
-- Ebonhold: this copy is the only one meant to run. The one still in the client's patch-D.mpq
-- would load first and fight it for the same frames, so it is switched off and, the session it
-- was found running, the player is asked to reload.
DisableAddOn("CompactRaidFrame")
if IsAddOnLoaded("CompactRaidFrame") then
    StaticPopupDialogs["EBONHOLD_CRF_RELOAD"] = {
        text = "Compact Raid Frames is now part of Project Ebonhold. Your separate copy has been disabled: reload the interface to finish.",
        button1 = "Reload Now",
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        preferredIndex = 3,
    }
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function() StaticPopup_Show("EBONHOLD_CRF_RELOAD") end)
end

-- This backport defines shared helpers the rest of the addon defines too (Mixin, CreateColor,
-- ColorMixin...), with methods of their own. It loads last here, so it would replace them for
-- everyone: after_load.lua puts them back and only adds what they lack. Standalone, it loaded
-- first and the addon's versions won the same way.
EBH_CRF_SHARED = {}
-- modules/collections (SharedXML/Util.lua) and libs/Details/compat.lua
local ADDON_FUNCTIONS = {
    Clamp = true, ClearClampedTextureRotation = true, CreateColor = true, CreateFromMixins = true,
    Mixin = true, Round = true, SetClampedTextureRotation = true,
    GetNumGroupMembers = true, GetNumSubgroupMembers = true, IsInGroup = true, IsInRaid = true,
}
for _, name in ipairs({
    "ATLAS_INFO_STORAGE", "ApplyCoordFix", "AuraUtil", "BackdropTemplateMixin", "C_IncomingSummon", "C_Map",
    "C_PartyInfo", "C_PvP", "C_Texture", "C_Timer", "CalculateAngleBetween", "CalculateDistance",
    "CalculateDistanceSq", "CanBeRaidTarget", "Clamp", "ClampDegrees", "ClampMod", "ClampedPercentageBetween",
    "ClearClampedTextureRotation", "ColorMixin", "CooldownFrame_Clear", "CreateAndInitFromMixin",
    "CreateAtlasMarkup", "CreateAtlasMarkupWithAtlasSize", "CreateColor", "CreateFromMixins",
    "CreateTextureMarkup", "DeltaLerp", "Enum", "FrameDeltaLerp", "GetDisplayedAllyFrames",
    "GetFinalNameFromTextureKit", "GetGroupMemberCountsForDisplay", "GetMaxUnitNumberBattleground",
    "GetNumGroupMembers", "GetNumSubgroupMembers", "GetSpecializationRole", "GetTexCoordsByGrid",
    "GetTexCoordsForRole", "GetTexCoordsForRoleSmallCircle", "GetTextureInfo", "InitSubFrame", "IsInGroup",
    "IsInRaid", "IsRaidMarkerActive", "LOSS_OF_CONTROL_STORAGE", "Lerp", "Mixin", "NegateIf",
    "NineSlicePanelMixin", "NineSliceUtil", "PartyUtil", "PassClickToParent", "PercentageBetween", "PixelUtil",
    "RaidOptionsFrame_UpdatePartyFrames", "RandomFloatInRange", "Round", "SOUNDKIT", "Saturate",
    "SetClampedTextureRotation", "SetupAtlasesOnRegions", "SetupTextureKitOnFrame", "SetupTextureKitOnFrames",
    "SetupTextureKitOnRegions", "SetupTextureKitsFromRegionInfo", "SpellGetVisibilityInfo",
    "SpellIsPriorityAura", "SpellIsSelfBuff", "Square", "TextureKitConstants", "UIMenuButtonStretchMixin",
    "UnitAuraBySlot", "UnitAuraSlots", "UnitDistanceSquared", "UnitGetIncomingHeals", "UnitGetTotalAbsorbs",
    "UnitGetTotalHealAbsorbs", "UnitGroupRoles", "UnitHasIncomingResurrection", "UnitInOtherParty",
    "UnitIsGroupAssistant", "UnitIsGroupLeader", "UnitNameplateShowsWidgetsOnly", "UnitPhaseReason",
    "UnitShouldDisplayName", "Wrap", "WrapTextInColorCode",
}) do
    -- A table is kept whoever made it. A function only when the addon made it: the ones the
    -- stock client has are replaced on purpose (RaidOptionsFrame_UpdatePartyFrames is what hides
    -- the old party frames), they must not come back.
    local v = _G[name]
    if type(v) == "table" or (v ~= nil and ADDON_FUNCTIONS[name]) then EBH_CRF_SHARED[name] = v end
end
