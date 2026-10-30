local addon, Addon = ...

Addon.ShopEntries = {}

-- Client-side localization data for shop items
local SHOP_ITEM_LOCALIZATION = {
    ["en"] = {
        [1] = {
            name = "Apprentice riding scroll",
            description = "Teaches you how to ride ground mounts at 60% speed. Requires level 20.",
            icon = "inv_misc_scrollrolled01b"
        },
        [2] = {
            name = "Journeyman riding scroll",
            description = "Teaches you how to ride ground mounts at 100% speed. Requires level 40 and \"Apprentice riding\".",
            icon = "inv_misc_scrollrolled01d"
        },
        [3] = {
            name = "Expert riding scroll",
            description = "Teaches you how to ride all flying mounts at 150% speed. Requires level 60 and \"Journeyman riding\".",
            icon = "inv_misc_scrollrolled02d"
        },
        [4] = {
            name = "Artisan riding scroll",
            description = "Teaches you how to ride all flying mounts at 280% speed. Requires level 70 and \"Expert riding\".",
            icon = "inv_misc_scrollrolled02b"
        },
        [5] = {
            name = "Cold weather flying scroll",
            description = "Teaches you how to ride all flying mounts in Northend. Requires level 77 and \"Expert riding\".",
            icon = "inv_misc_scrollrolled03d"
        },
        [6] = {
            name = "Scroll of customization",
            description = "Allows you to custimize your character once (change color, hair, ...).",
            icon = "inv_misc_scrollunrolled01"
        },
        [7] = {
            name = "Scroll of faction change",
            description = "Allows you to change the faction of your character.",
            icon = "inv_misc_scrollunrolled01b"
        },
        [8] = {
            name = "Scroll of race change",
            description = "Allows you to change the race of your character.",
            icon = "inv_misc_scrollunrolled02b"
        }
    },
    ["fr"] = {
        [1] = {
            name = "Parchemin d'apprenti cavalier",
            description = "Vous apprend à utiliser des montures terrestres (60%). Nécessite le niveau 20.",
            icon = "inv_misc_scrollrolled01b"
        },
        [2] = {
            name = "Parchemin de compagnon cavalier",
            description = "Vous apprend à utiliser des montures terrestres (100%). Nécessite le niveau 40 et \"Apprenti cavalier\".",
            icon = "inv_misc_scrollrolled01d"
        },
        [3] = {
            name = "Parchemin d'expert cavalier",
            description = "Vous apprend à utiliser des montures volantes (150%). Nécessite le niveau 60 et \"Compagnon cavalier\".",
            icon = "inv_misc_scrollrolled02d"
        },
        [4] = {
            name = "Parchemin d'artisan cavalier",
            description = "Vous apprend à utiliser des montures volantes (280%). Nécessite le niveau 70 et \"Expert cavalier\".",
            icon = "inv_misc_scrollrolled02b"
        },
        [5] = {
            name = "Parchemin de vol en climat froid",
            description = "Vous apprend à utiliser des montures volantes en Norfendre. Nécessite le niveau 77 et \"Expert cavalier\".",
            icon = "inv_misc_scrollrolled03d"
        },
        [6] = {
            name = "Parchemin de personnalisation",
            description = "Vous permet de personnaliser votre personnage une seule fois (changement de couleur, cheveux, ...).",
            icon = "inv_misc_scrollunrolled01"
        },
        [7] = {
            name = "Parchemin de changement de faction",
            description = "Vous permet de changer la faction de votre personnage.",
            icon = "inv_misc_scrollunrolled01b"
        },
        [8] = {
            name = "Parchemin de changement de race",
            description = "Vous permet de changer la race de votre personnage.",
            icon = "inv_misc_scrollunrolled02b"
        }
    }
}

-- Auto-detect language based on game locale
local function getGameLanguage()
    local locale = GetLocale()
    if locale == "frFR" then
        return "fr"
    else
        return "en" -- Default to English for all other locales
    end
end

-- Current language (auto-detected)
local currentLanguage = getGameLanguage()

-- Function to get localized data for a shop item
local function getLocalizedItemData(itemId, language)
    language = language or currentLanguage
    local langData = SHOP_ITEM_LOCALIZATION[language]
    if not langData then
        langData = SHOP_ITEM_LOCALIZATION["en"] -- fallback to English
    end
    
    local itemData = langData[itemId]
    if not itemData then
        -- Fallback to English if not found in current language
        if language ~= "en" then
            local enData = SHOP_ITEM_LOCALIZATION["en"]
            itemData = enData and enData[itemId]
        end
    end
    
    return itemData or {
        name = "Unknown Item #" .. tostring(itemId),
        description = "No description available for this item.",
        icon = "INV_Misc_QuestionMark"
    }
end

local function splitData(texte)
    local champs = {}
    for champ in string.gmatch(texte, "([^#]+)") do
        table.insert(champs, champ)
    end
    return champs
end

local function parseData(texte)
    local data = splitData(texte)
    local obj = {};
    
    -- Determine if it's an item or mount based on creatureId (data[4])
    local isMount = data[4] ~= "NULL"
    
    -- Get localized data for this item
    local localizedData = getLocalizedItemData(tonumber(data[1]))
    
    -- Handle NULL category_id - put in Miscellaneous (ID 12)
    local categoryId = data[2] ~= "NULL" and tonumber(data[2]) or 12
    
    -- Parse common fields (note: no icon field in data anymore)
    obj = {
        id                = tonumber(data[1]),
        category_id       = categoryId,
        item_id           = tonumber(data[3]),
        creatureId        = data[4] ~= "NULL" and tonumber(data[4]) or nil,
        price             = tonumber(data[5]),
        discountActive    = data[6] == "1",
        discount          = data[7] ~= "NULL" and tonumber(data[7]) or nil,
        end_time_discount = data[8] ~= "NULL" and tonumber(data[8]) or nil,
        
        -- Localized fields (including icon)
        name              = localizedData.name,
        extraInfo         = localizedData.description,
        icon              = localizedData.icon,
        
        -- Legacy fields for compatibility
        client_line_type  = isMount and 1 or 0,
        entry_type        = isMount and 1 or 0,
        item_count        = 1, -- Default value
        featured          = 0, -- Default value
        subcategory_id    = isMount and 0 or (categoryId ~= 12 and categoryId or 1),
    }
    
    return obj;
end

-- Register event handlers for the new communication system
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_SHOP_DATA, function(body)
    Addon.ShopEntries = {};
    
    -- Split entries by "---" separator
    local entries = {}
    for entry in string.gmatch(body, "([^%-%-%-]+)") do
        if entry and string.len(string.gsub(entry, "%s", "")) > 0 then -- Skip empty entries
            table.insert(entries, entry)
        end
    end
    
    -- Parse each entry
    for _, value in ipairs(entries) do
        local entry = parseData(value)
        tinsert(Addon.ShopEntries, entry);
    end
    
    -- Make shop entries globally accessible for debugging
    ProjectEbonhold.ShopEntries = Addon.ShopEntries
end)

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_ACCOUNT_DP, function(body)
    local dp = tonumber(body)
    if dp then
        ModernShopDPSetAmount(dp)
    end
end)

-- Language management functions (now auto-detected)
function Addon.GetShopLanguage()
    return currentLanguage
end

function Addon.GetDetectedLocale()
    return GetLocale()
end

-- Make language functions globally accessible
ProjectEbonhold.GetShopLanguage = Addon.GetShopLanguage
ProjectEbonhold.GetDetectedLocale = Addon.GetDetectedLocale
