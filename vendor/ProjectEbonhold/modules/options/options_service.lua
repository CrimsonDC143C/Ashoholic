


local OptionsService = {}


local defaultSettings = {
    autoEquipItems = true,
    autoLearnTalents = true,
    autoPlaceSpells = true,
    showFloatingText = true,
    hideLevelUpFrame = false,
    -- Perk Selection UI options
    noPerkFadeAnimations = false,
    noRerollConfirm = false,
    rerollAutoRepopulate = false,
    echoesVisibleOnLevelUp = true,
    -- One-time stamp for echoesVisibleOnLevelUp, see Initialize below.
    echoesLevelUpOptionMigrated = false,
    autoShowEchoes = false,
    autoAcceptLoadoutEchoes = false,
    perkDirectBanish = false,
    perkShowSelectCount = false,
    hideTomeLearnedAlert = false,
    perkUIScale = 1.0,
    transparentDesign = false,
    -- Dragonflight-style quest tracker (modules/questTracker)
    dfQuestTracker = true,
    -- WoW-style nameplate reskin (modules/nameplates). Off by default while the
    -- in-combat freeze reports are being worked through -- note the module also
    -- carries its own MODULE_DISABLED kill switch, which is what actually takes
    -- effect on accounts that already have this persisted as true.
    nameplatesEnabled = false,
    nameplatesClassColor = true,
    nameplatesShowLevel = false,
    nameplatesCastBar = true,
    nameplatesHealthFormat = "BOTH",   -- OFF | VALUE | PERCENT | BOTH
    nameplatesBarWidth = 130,
    nameplatesBarHeight = 14,
    nameplatesFontSize = 12,
    -- Merchant / junk selling options
    autoSellJunk = false,
    sellEverything = false,
    -- Only Poor is sold out of the box; every other filter is opt-in
    sellQualityPoor = true,
    sellQualityCommon = false,
    sellQualityUncommon = false,
    sellQualityRare = false,
    sellTypeWeapon = false,
    sellTypeArmor = false,
    sellTypeConsumable = false,
    sellTypeTradeGoods = false,
    sellTypeRecipe = false,
    sellTypeGem = false,
    sellTypeGlyph = false,
    sellTypeMisc = false,
    -- Tracks whether we've performed the one-time CVar defaults application
    -- (Font Rendering enabled, Stance Patch enabled). See cvar_options.lua.
    cvarInitialDefaultsApplied = false,
}

function OptionsService:Initialize()
    if not ProjectEbonholdDB then
        ProjectEbonholdDB = {}
    end
    
    if not ProjectEbonholdDB.settings then
        ProjectEbonholdDB.settings = {}
        for k, v in pairs(defaultSettings) do
            ProjectEbonholdDB.settings[k] = v
        end
    else
        
        for k, v in pairs(defaultSettings) do
            if ProjectEbonholdDB.settings[k] == nil then
                ProjectEbonholdDB.settings[k] = v
            end
        end
    end

    -- "Keep echoes visible when leveling up" shipped as a stored-but-unread
    -- setting, so the value every existing profile carries never meant
    -- anything. Stamp it once to the behaviour those players actually had
    -- (the full "Select an Echo" prompt) now that the option is wired up;
    -- from here on their own toggling is what sticks.
    if not ProjectEbonholdDB.settings.echoesLevelUpOptionMigrated then
        ProjectEbonholdDB.settings.echoesVisibleOnLevelUp = true
        ProjectEbonholdDB.settings.echoesLevelUpOptionMigrated = true
    end

    return ProjectEbonholdDB.settings
end


function OptionsService:GetSetting(key)
    if not ProjectEbonholdDB or not ProjectEbonholdDB.settings then
        return defaultSettings[key]
    end
    return ProjectEbonholdDB.settings[key]
end


function OptionsService:SetSetting(key, value)
    if not ProjectEbonholdDB or not ProjectEbonholdDB.settings then
        self:Initialize()
    end
    ProjectEbonholdDB.settings[key] = value
end


function OptionsService:ResetToDefaults()
    ProjectEbonholdDB.settings = {}
    for k, v in pairs(defaultSettings) do
        ProjectEbonholdDB.settings[k] = v
    end
end


function OptionsService:GetSettingsForServer()
    local settings = ProjectEbonholdDB.settings or defaultSettings
    
    
    local data = {}
    table.insert(data, "autoEquipItems:" .. (settings.autoEquipItems and "1" or "0"))
    table.insert(data, "autoLearnTalents:" .. (settings.autoLearnTalents and "1" or "0"))
    table.insert(data, "autoPlaceSpells:" .. (settings.autoPlaceSpells and "1" or "0"))
    
    return table.concat(data, ",")
end


function OptionsService:SendToServer()
    if not ProjectEbonhold or not ProjectEbonhold.sendToServer or not ProjectEbonhold.CS then
        return
    end
    
    local data = self:GetSettingsForServer()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ADDON_PREFERENCE, data)
end


function OptionsService:ApplySettingsFromServer(data)
    if not data or data == "" then return end
    
    
    for setting in string.gmatch(data, "[^,]+") do
        local key, value = string.match(setting, "([^:]+):([^:]+)")
        if key and value then
            if key == "autoEquipItems" or key == "autoLearnTalents" or key == "autoPlaceSpells" then
                self:SetSetting(key, value == "1")
            end
        end
    end
end


_G.ProjectEbonholdOptionsService = OptionsService
