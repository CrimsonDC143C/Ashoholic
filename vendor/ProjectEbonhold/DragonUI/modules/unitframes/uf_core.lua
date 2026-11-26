-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

--[[
  DragonUI - Unit Frame Shared Core (uf_core.lua)

  Shared constants, utilities, and factory helpers for all unit frame modules.
  Loaded first via unitframes.xml; other UF modules reference addon.UF.
]]

local addon = DragonUI
-- Create the shared UF namespace
addon.UF = addon.UF or {}
local UF = addon.UF


-- ============================================================================
-- TEXTURE PATH REGISTRY
-- ============================================================================

UF.TEXTURES = {
    -- Target-style frames (TargetFrame, FocusFrame)
    targetStyle = {
        BACKGROUND     = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Target\\UI-HUD-UnitFrame-Target-PortraitOn-BACKGROUND",
        BACKGROUND_FAT = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Target\\UI-HUD-UnitFrame-Target-PortraitOn-BACKGROUND-Fat",
        BORDER         = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Target\\UI-HUD-UnitFrame-Target-PortraitOn-BORDER",
        BORDER_FAT     = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Target\\UI-HUD-UnitFrame-Target-PortraitOn-BORDER-Fat",
        BAR_PREFIX     = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Target-PortraitOn-Bar-",
        NAME_BACKGROUND = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Target\\NameBackground",
        BOSS           = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\uiunitframeboss2x",
        THREAT         = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Target\\ui-hud-unitframe-target-portraiton-incombat-2x",
        THREAT_NUMERIC = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\uiunitframe",
    },

    -- Small-style frames (ToT, FoT, Pet)
    smallStyle = {
        BACKGROUND = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Small\\UI-HUD-UnitFrame-TargetofTarget-PortraitOn-BACKGROUND",
        BORDER     = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Small\\UI-HUD-UnitFrame-TargetofTarget-PortraitOn-BORDER",
        BAR_PREFIX = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-",
        BOSS       = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\uiunitframeboss2x",
    },

    -- Player frame (unique textures)
    -- NOTE: Vehicle border uses atlas 'PlayerFrame-TextureFrame-Vehicle' from UnitFrame.blp (defined in Atlas.lua)
    player = {
        BASE          = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\uiunitframe",
        BASE_FAT      = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\uiunitframe-fat",
        HEALTH_BAR    = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
        HEALTH_STATUS = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Status",
        BORDER        = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Player\\UI-HUD-UnitFrame-Player-PortraitOn-BORDER",
        BORDER_FAT    = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Player\\UI-HUD-UnitFrame-Player-PortraitOn-BORDER-Fat",
        REST_ICON     = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Player\\PlayerRestFlipbook",
        RUNE_TEXTURE  = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Player\\ClassOverlayDeathKnightRunes",
        LFG_ICONS     = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Player\\LFGRoleIcons",
        POWER_BARS = {
            MANA        = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
            RAGE        = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
            FOCUS       = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Focus",
            ENERGY      = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Energy",
            RUNIC_POWER = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-RunicPower",
        },
    },

    -- Party frames (unique textures)
    party = {
        healthBarStatus = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Party\\UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Status",
        frame           = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Party\\uipartyframe",
        border          = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Small\\UI-HUD-UnitFrame-TargetofTarget-PortraitOn-BORDER",
        healthBar       = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Party\\UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health",
        manaBar         = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Party\\UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana",
        focusBar        = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Party\\UI-HUD-UnitFrame-Party-PortraitOn-Bar-Focus",
        rageBar         = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Party\\UI-HUD-UnitFrame-Party-PortraitOn-Bar-Rage",
        energyBar       = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Party\\UI-HUD-UnitFrame-Party-PortraitOn-Bar-Energy",
        runicPowerBar   = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Party\\UI-HUD-UnitFrame-Party-PortraitOn-Bar-RunicPower",
    },

    -- Pet frame (constructs paths from prefix)
    pet = {
        SMALL_FRAME_PATH = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Small\\",
        UNITFRAME_PATH   = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\",
        TOT_BASE         = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-",
        -- Pre-computed power textures (same as smallStyle BAR_PREFIX + power name)
        POWER_TEXTURES = {
            MANA        = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Mana",
            FOCUS       = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Focus",
            RAGE        = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Rage",
            ENERGY      = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Energy",
            RUNIC_POWER = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-RunicPower",
        },
    },

    -- Shared class icon texture (used by class portrait system)
    CLASS_ICON_ALTERNATIVE_PREFIX = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\ClassIcons\\",
    CLASS_ICON_ALTERNATIVE_SUFFIX = ".blp",
    RACE_PORTRAIT_PREFIX = "Interface\\AddOns\\ProjectEbonhold\\DragonUI\\Textures\\RacePortraits\\",
    CLASS_ICON = "Interface\\TargetingFrame\\UI-Classes-Circles",
}


-- ============================================================================
-- POWER TYPE MAP
-- ============================================================================
-- Numeric power type ID -> texture suffix name.

UF.POWER_MAP = {
    [0] = "Mana",
    [1] = "Rage",
    [2] = "Focus",
    [3] = "Energy",
    [6] = "RunicPower",
}


-- ============================================================================
-- THREAT COLORS
-- ============================================================================
-- Indexed by threat level (1=low, 2=medium, 3=high).

UF.THREAT_COLORS = {
    {1.0, 1.0, 0.47}, -- Low threat
    {1.0, 0.6, 0.0},  -- Medium threat
    {1.0, 0.0, 0.0},  -- High threat
}


-- ============================================================================
-- FAMOUS NPCs
-- ============================================================================
-- Classification overrides for specific NPCs.

UF.FAMOUS_NPCS = {
    ["Patufet"] = true,
}

-- Legacy alias
addon.unitframe = addon.unitframe or {}
addon.unitframe.famous = UF.FAMOUS_NPCS


-- ============================================================================
-- LOCALE-AWARE DEFAULT FONT
-- ============================================================================
-- Uses centralized font system from core/fonts.lua.
-- Modules should use UF.DEFAULT_FONT instead of hardcoding FRIZQT__.

UF.DEFAULT_FONT = addon.Fonts and addon.Fonts.PRIMARY or "Fonts\\FRIZQT__.TTF"

-- Fine-tune for non-alternative class portrait apparent size.
-- 0.000 = smallest (native atlas crop), higher values zoom in slightly.
UF.CLASSIC_CLASS_ICON_INSET = 0.012


-- ============================================================================
-- CONFIG ACCESS
-- ============================================================================
-- Returns config table with database defaults as metatable fallback.

-- Called every frame by some OnUpdates, so one metatable per unit key instead of one per call.
local configMetatables = {}
local NO_DEFAULTS = {}

function UF.GetConfig(unitKey)
    local config
    if addon.GetConfigValue then
        config = addon:GetConfigValue("unitframe", unitKey)
    elseif addon.db and addon.db.profile and addon.db.profile.unitframe then
        config = addon.db.profile.unitframe[unitKey]
    end
    config = config or {}

    local defaults = addon.defaults
        and addon.defaults.profile
        and addon.defaults.profile.unitframe
        and addon.defaults.profile.unitframe[unitKey] or NO_DEFAULTS

    local mt = configMetatables[unitKey or false]
    if not mt or mt.__index ~= defaults then
        mt = { __index = defaults }
        configMetatables[unitKey or false] = mt
    end
    if getmetatable(config) ~= mt then
        setmetatable(config, mt)
    end
    return config
end

function UF.IsEnabled(unitKey)
    local config = UF.GetConfig(unitKey)
    return config.enabled ~= false
end

-- ============================================================================
-- CLASSIFICATION HELPERS
-- ============================================================================
-- Returns the effective classification string for a unit, accounting for
-- famous NPC overrides, vehicles, and skull-level bosses.

function UF.GetClassification(unit, famousNpcs)
    if not UnitExists(unit) then return nil end

    local classification = UnitClassification(unit)

    -- Famous NPC override
    if famousNpcs then
        local name = UnitName(unit)
        if name and famousNpcs[name] then
            -- If value is a string, use it as classification; if true, keep current
            local override = famousNpcs[name]
            if type(override) == "string" then
                classification = override
            end
        end
    end

    -- Vehicle override — vehicles show as normal
    if UnitInVehicle and UnitInVehicle(unit) then
        classification = "normal"
    end

    -- Level -1 indicates boss
    if UnitLevel(unit) == -1 and classification ~= "worldboss" then
        if classification == "rare" then
            classification = "rareelite"
        elseif classification ~= "rareelite" then
            classification = "elite"
        end
    end

    return classification
end

function UF.GetBossCoords(classification, bossCoords)
    if not classification then return nil end
    return bossCoords[classification]
end


-- ============================================================================
-- CLASS PORTRAIT
-- ============================================================================
-- Overlays a class icon on the unit portrait when enabled.
-- Lazy-creates the background and icon textures on first call.

function UF.UseAlternativeClassIcons(unitKey)
    local config = UF.GetConfig(unitKey)
    return config and config.classPortrait and config.alternativeClassIcons or false
end

function UF.ApplyClassPortraitIcon(icon, classFileName, useAlternative)
    if not icon or not classFileName then
        return false
    end

    local function ClampInset(value)
        local inset = tonumber(value) or 0
        if inset < 0 then return 0 end
        if inset > 0.03 then return 0.03 end
        return inset
    end

    if useAlternative then
        icon:SetTexture(
            UF.TEXTURES.CLASS_ICON_ALTERNATIVE_PREFIX
            .. classFileName
            .. UF.TEXTURES.CLASS_ICON_ALTERNATIVE_SUFFIX)
        icon:SetTexCoord(0, 1, 0, 1)
        return true
    end

    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFileName]
    if not coords then
        return false
    end

    local inset = ClampInset(UF.CLASSIC_CLASS_ICON_INSET)
    icon:SetTexture(UF.TEXTURES.CLASS_ICON)
    icon:SetTexCoord(
        coords[1] + inset, coords[2] - inset,
        coords[3] + inset, coords[4] - inset)
    return true
end

function UF.ApplyClassPortraitToTexture(unit, portraitTexture, useAlternative)
    if not portraitTexture or not unit then
        return false
    end

    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        return false
    end

    local _, classFileName = UnitClass(unit)
    if not classFileName then
        return false
    end

    if UF.ApplyClassPortraitIcon(portraitTexture, classFileName, useAlternative) then
        portraitTexture:SetAlpha(1)
        return true
    end

    return false
end

-- A custom race keeps its 3D portrait. The files say Undead where the API says Scourge.
local RACE_PORTRAIT_FILES = {
    Human = "Human", Orc = "Orc", Dwarf = "Dwarf", NightElf = "NightElf", Scourge = "Undead",
    Tauren = "Tauren", Gnome = "Gnome", Troll = "Troll", BloodElf = "BloodElf", Draenei = "Draenei",
}

-- The one place that knows where race portraits come from; file is "Human_Male" and the like.
function UF.SetRacePortraitFile(texture, file)
    -- SetTexture answers nil until a client restart picks up these files after an update.
    if not texture:SetTexture(UF.TEXTURES.RACE_PORTRAIT_PREFIX .. file) then
        return false
    end
    texture:SetTexCoord(0, 1, 0, 1)
    return true
end

function UF.ApplyRacePortraitToTexture(unit, portraitTexture)
    if not portraitTexture or not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then
        return false
    end
    local _, raceFile = UnitRace(unit)
    local race = raceFile and RACE_PORTRAIT_FILES[raceFile]
    if not race or not UF.SetRacePortraitFile(portraitTexture, race .. (UnitSex(unit) == 3 and "_Female" or "_Male")) then
        return false
    end
    portraitTexture:SetAlpha(1)
    return true
end

-- The menus keep the two exclusive; race goes first if an old profile somehow holds both.
function UF.ApplyPortraitStyle(unit, portraitTexture, config)
    if config.racePortrait and UF.ApplyRacePortraitToTexture(unit, portraitTexture) then
        return true
    end
    if config.classPortrait then
        return UF.ApplyClassPortraitToTexture(unit, portraitTexture, config.alternativeClassIcons)
    end
    return false
end

function UF.UpdateClassPortrait(unit, portrait, parentFrame, elements, enabled, useAlternative)
    -- Legacy cleanup: old implementations used dedicated overlay frames.
    if elements then
        if elements.classPortraitFrame then elements.classPortraitFrame:Hide() end
        if elements.classPortraitBg then elements.classPortraitBg:Hide() end
        if elements.classPortraitIcon then elements.classPortraitIcon:Hide() end
    end

    if not enabled then
        return false
    end

    if useAlternative == nil and parentFrame and parentFrame.unitKey then
        useAlternative = UF.UseAlternativeClassIcons(parentFrame.unitKey)
    end

    return UF.ApplyClassPortraitToTexture(unit, portrait, useAlternative)
end


-- ============================================================================
-- BAR HOOK HELPERS
-- ============================================================================

-- Hooks SetValue on healthBar to clip the texture and optionally apply class color.

function UF.SetupHealthBarHook(healthBar, statusTexture, useClassColor)
    if not healthBar then return end

    hooksecurefunc(healthBar, "SetValue", function(self)
        local _, max = self:GetMinMaxValues()
        local val = self:GetValue()
        if max > 0 and val > 0 then
            local pct = val / max
            -- Clip texture to show only filled portion
            if statusTexture then
                statusTexture:SetTexCoord(0, pct, 0, 1)
                statusTexture:SetWidth(self:GetWidth() * pct)
            end
            -- Apply class color if enabled
            if useClassColor then
                local unit = self.unit or (self:GetParent() and self:GetParent().unit)
                if unit and UnitExists(unit) and UnitIsPlayer(unit) then
                    local _, class = UnitClass(unit)
                    if class then
                        local color = RAID_CLASS_COLORS[class]
                        if color and statusTexture then
                            statusTexture:SetVertexColor(color.r, color.g, color.b)
                        end
                    end
                end
            end
        end
    end)
end

-- Returns the texture suffix string for a given power type ID.

function UF.GetPowerBarTextureSuffix(powerType)
    return UF.POWER_MAP[powerType] or "Mana"
end

-- Returns the full party power bar texture path for a unit.

function UF.GetPartyPowerBarTexture(unit)
    if not unit or not UnitExists(unit) then
        return UF.TEXTURES.party.manaBar
    end
    local powerType = UnitPowerType(unit)
    if powerType == 1 then
        return UF.TEXTURES.party.rageBar
    elseif powerType == 2 then
        return UF.TEXTURES.party.focusBar
    elseif powerType == 3 then
        return UF.TEXTURES.party.energyBar
    elseif powerType == 6 then
        return UF.TEXTURES.party.runicPowerBar
    else
        return UF.TEXTURES.party.manaBar
    end
end

-- Returns the full pet power bar texture path for a power type string.

function UF.GetPetPowerTexture(powerTypeString)
    return UF.TEXTURES.pet.POWER_TEXTURES[powerTypeString]
        or UF.TEXTURES.pet.POWER_TEXTURES.MANA
end


-- ============================================================================
-- MODULE TEMPLATE
-- ============================================================================

function UF.CreateModule(name)
    return {
        name = name,
        overlay = nil,          -- Editor overlay frame (CreateUIFrame)
        textSystem = nil,       -- TextSystem reference
        initialized = false,    -- ADDON_LOADED has fired
        configured = false,     -- Frame setup is complete
        eventsFrame = nil,      -- Event handler frame
        elements = {},          -- Created textures/regions (for cleanup and reference)
    }
end
