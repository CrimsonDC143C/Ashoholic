-- Placeholder Shop Data
local addon, Addon = ...

local SHOP_PLACEHOLDER_DATA = {
    categories = {
        { id = 1, name = "Convenience", icon = "Interface/Shop/categoryIcons/category-icon-services" },
        { id = 2,  name = "Character Services", icon = "Interface/Shop/categoryIcons/category-icon-featured" },
        { id = 4, name = "Appearance",         icon = "Interface/Shop/categoryIcons/category-icon-mounts" },
        { id = 5,  name = "Mounts",             icon = "Interface/Shop/categoryIcons/category-icon-mounts" },
        { id = 11, name = "Stones of Retreat",  icon = "Interface/Shop/categoryIcons/category-icon-enchantscroll" },
        { id = 12,  name = "Miscellaneous",      icon = "Interface/Shop/categoryIcons/category-icon-free" },
        -- { id = 8,  name = "Transmogrification", icon = "Interface/Shop/categoryIcons/category-icon-clothes" },
    },
    -- entries = {
    --     --Services
    --     { id = 101, category_id = 1, subcategory_id = 101,                 name = "Customize",          price = 10,                                        icon = { 0.14013672, 0.25146484, 0.00292969, 0.22167969 } },
    --     { id = 706, category_id = 1, subcategory_id = 102,                 name = "Time-Lost Figurine", price = 5,                                         icon = { 0.14013672, 0.25146484, 0.00292969, 0.22167969 },      extraInfo = "Experience gained from killing monsters and completing quests is increased by 100% for 1 hour. This bonus also applies beyond level 60 and includes professions. The duration can be extended up to 12 hours." },
    --     { id = 103, category_id = 1, subcategory_id = 103,                 name = "Faction Change",     price = 10,                                        icon = { 0.13916016, 0.25146484, 0.21972656, 0.44628906 } },
    --     { id = 104, category_id = 1, subcategory_id = 104,                 name = "Race Change",        price = 10,                                        icon = { 0.00048828, 0.11181641, 0.75097656, 0.97753906 } },
    --     { id = 105, category_id = 1, subcategory_id = 105,                 name = "Name Change",        price = 10,                                        icon = { 0.00048828, 0.11181641, 0.52636719, 0.75292969 } },
    --     { id = 106, category_id = 1, subcategory_id = 106,                 name = "Unlock Tabs",        price = 10,                                        icon = { 0.00048828, 0.11181641, 0.52636719, 0.75292969 } },

    --     --Mounts
    --     { id = 501, category_id = 5, name = "Swift Zulian Tiger",          price = 15,                  discount = 30,                                     creatureId = 3000 },
    --     -- { id = 502, category_id = 5, name = "Raven Lord",                  price = 15,                  isNew = true,                                      creatureId = 1000 },
    --     -- { id = 503, category_id = 5, name = "Ashes of Al'ar",              price = 15,                  isSpecial = true,                                  creatureId = 3002 },
    --     -- { id = 504, category_id = 5, name = "Frostwolf Howler",            price = 15,                  isOwned = true,                                    creatureId = 3002 },
    --     -- { id = 505, category_id = 5, name = "Spectral Tiger",              price = 15,                  isInDealPresent = true,                            creatureId = 3002 },
    --     -- { id = 506, category_id = 5, name = "Amani War Bear",              price = 15,                  creatureId = 3010 },
    --     -- { id = 507, category_id = 5, name = "Black War Bear",              price = 15,                  creatureId = 3004 },
    --     -- { id = 508, category_id = 5, name = "Red Qiraji Battle Tank",      price = 15,                  creatureId = 3005 },
    --     -- { id = 509, category_id = 5, name = "Bronze Drake",                price = 15,                  creatureId = 3006 },
    --     -- { id = 510, category_id = 5, name = "Armored Brown Bear",          price = 15,                  creatureId = 3007 },
    --     -- { id = 511, category_id = 5, name = "Green Proto-Drake",           price = 15,                  creatureId = 3008 },
    --     -- { id = 512, category_id = 5, name = "Cenarion War Hippogryph",     price = 15,                  creatureId = 3009 },

    --     --Pets
    --     { id = 601, category_id = 6, name = "Mini Diablo",                 price = 10,                  discount = 25,                                     previewModelPath = "creature\\diablo\\diablofunsized.m2" },
    --     { id = 602, category_id = 6, name = "Panda Cub",                   price = 10 },
    --     { id = 603, category_id = 6, name = "Zergling",                    price = 10 },
    --     { id = 604, category_id = 6, name = "Mechanical Chicken",          price = 10 },
    --     { id = 605, category_id = 6, name = "Sprite Darter Hatchling",     price = 10 },
    --     { id = 606, category_id = 6, name = "Lil KT",                      price = 10 },
    --     { id = 607, category_id = 6, name = "Baby Blizzard Bear",          price = 10 },
    --     { id = 608, category_id = 6, name = "Murky",                       price = 10 },
    --     { id = 609, category_id = 6, name = "Clockwork Rocket Bot",        price = 10 },
    --     { id = 610, category_id = 6, name = "Teldrassil Sproutling",       price = 10 },
    --     { id = 611, category_id = 6, name = "Phoenix Hatchling",           price = 10 },
    --     { id = 612, category_id = 6, name = "Tiny Sporebat",               price = 10 },

    --     --Toys
    --     { id = 701, category_id = 7, name = "Piccolo of the Flaming Fire", price = 5,                   icon = "INV_Misc_Flute_01",                        extraInfo = "This Piccolo makes all players start to dance!" },
    --     { id = 702, category_id = 7, name = "Orb of Deception",            price = 5,                   icon = "INV_Misc_Orb_01",                          extraInfo = "Change to a different race!" },
    --     { id = 703, category_id = 7, name = "Dark Portal",                 price = 5,                   icon = "INV_Misc_Rune_01",                         extraInfo = "A rune that does something!" },
    --     { id = 704, category_id = 7, name = "Fishing Chair",               price = 5,                   icon = "inv_fishingchair",                         extraInfo = "A nice chilling chair to uh... chill in!" },
    --     { id = 705, category_id = 7, name = "Gnomeregan Pride",            price = 5,                   icon = "inv_misc_tournaments_symbol_gnome",        extraInfo = "Something with gnomes and pride!" },
    --     { id = 706, category_id = 7, name = "Time-Lost Figurine",          price = 5,                   icon = "INV_Misc_Statue_01",                       extraInfo = "Lost figurine, now found!" },
    --     { id = 707, category_id = 7, name = "Super Simian Sphere",         price = 5,                   icon = "INV_Misc_Orb_05" },
    --     { id = 708, category_id = 7, name = "Bubbling Cauldron",           price = 5,                   icon = "INV_Alchemy_Elixir_01" },
    --     { id = 709, category_id = 7, name = "Goblin Gumbo Kettle",         price = 5,                   icon = "INV_Misc_Cauldron_Arcane" },
    --     { id = 710, category_id = 7, name = "Mini Mana Bomb",              price = 5,                   icon = "Spell_Shadow_Shadowfury" },
    --     { id = 711, category_id = 7, name = "Sandbox Tiger",               price = 5,                   icon = "Ability_Mount_JungleTiger" },
    --     { id = 712, category_id = 7, name = "Winter's Little Helper",      price = 5,                   icon = "INV_Holiday_Christmas_Present_01" },

    --     --Transmogs
    --     { id = 801, category_id = 8, name = "Tier 1",                      price = 20,                  background = "Interface/Shop/shopbundles1007y46",  texCoords = { 0.19384766, 0.34228516, 0.00097656, 0.56152344 }, previewItems = { 2709, 16799, 16795, 16800, 16801, 16796, 16797, 16798 } },
    --     { id = 802, category_id = 8, name = "Tier 2",                      price = 20,                  background = "Interface/Shop/shopbundles1002t27",  texCoords = { 0.20166016, 0.35205078, 0.04589844, 0.50683594 }, previewItems = { 2709, 16936, 16935, 16942, 16940, 16941, 16939, 16938, 16937 } },
    --     { id = 803, category_id = 8, name = "Tier 3",                      price = 20,                  background = "Interface/Shop/shopbundles1015wsg7", texCoords = { 0.30517578, 0.39501953, 0.03613281, 0.50488281 }, previewItems = { 2709, 22492, 22494, 22493, 22490, 22489, 22491, 22488, 22495 } },
    --     { id = 804, category_id = 8, name = "Tier 4",                      price = 20,                  background = "Interface/Shop/shopbundles1020mq1",  texCoords = { 0.21923828, 0.33349609, 0.01269531, 0.50683594 }, previewItems = { 2709, 28963, 28968, 28966, 28967, 28964 } },
    -- }
}

local ModernShopCurrentPage = 1
local ModernShopEntriesPerPage = 8
local ModernShopTotalPages = 1

-- Tracking tables
local CategoryButtons = {}           -- handles both main + subcategories
local ModernShopCurrentEntrySet = {} -- entries currently being paginated

-- Tracking Variables
local ModernShopSelectedEntryFrame = nil
local ModernShopLastCategoryID = nil
local ModernShopLastSubcategoryID = nil
local ModernShopSelectedCategoryButton = nil
local ModernShopSelectedSubcategoryButton = nil
local btnToggleExpandedState = false

-- Toggle Shop Frame
function ModernShop_Toggle()
    if ModernShopFrame:IsShown() then
        ModernShopFrame:Hide()
    else
        ModernShopFrame:Show()
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_ACCOUNT_DP, "")
        ModernShop_RenderCategories()
    end
end

-- Title
if not ModernShopTitle then
    ModernShopTitle = ModernShopFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ModernShopTitle:SetText("Shop")
    ModernShopTitle:SetFont("Fonts\\FRIZQT__.TTF", 14)
    ModernShopTitle:SetPoint("TOP", ModernShopFrame, "TOP", 0, -5)
end


ModernShopDP = ModernShopFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ModernShopDP:SetText("You have " .. 0 .. " DP(s)")
ModernShopDP:SetFont("Fonts\\FRIZQT__.TTF", 14)
ModernShopDP:SetPoint("CENTER", ModernShopFrame, "LEFT", 100, -250)

ModernShopDP.Link = ModernShopFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ModernShopDP.Link:SetText("Get DPs at projectebonhold.com/shop")
ModernShopDP.Link:SetFont("Fonts\\FRIZQT__.TTF", 10)
ModernShopDP.Link:SetPoint("CENTER", ModernShopFrame, "LEFT", 100, -265)

function ModernShopDPSetAmount(amount)
    ModernShopDP:SetText("You have " .. tonumber(amount) .. "  DP(s)")
end

-- Tilt Icon Top left
ModernShopPortraitIcon:SetRotation(math.rad(20))

-- Render category buttons
function ModernShop_RenderCategories()
    -- Cleanup all old buttons
    for _, b in pairs(CategoryButtons) do
        if b then
            b:Hide()
            b:SetParent(nil)
        end
    end
    CategoryButtons = {}

    local buttonIndex = 0
    local yOffset = 60

    ModernShopCurrentPage = 1

    for _, cat in ipairs(SHOP_PLACEHOLDER_DATA.categories) do
        buttonIndex = buttonIndex + 1

        local btn = CreateFrame("Button", "ModernShopCategoryButton" .. buttonIndex, ModernShopFrame)
        btn:SetSize(180, 30)
        btn:SetPoint("TOPLEFT", 10, -yOffset)

        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetTexture("Interface/Shop/store-main")
        btn.bg:SetTexCoord(0.56689453, 0.73291016, 0.42041016, 0.45263672)

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(64, 64)
        btn.icon:SetPoint("LEFT", btn, "LEFT", -16, 0)
        btn.icon:SetTexture(cat.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", -10, 0)
        btn.label:SetText(cat.name)

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface/Shop/store-main")
        highlight:SetTexCoord(0.00341797, 0.16748047, 0.93896484, 0.96826172)
        highlight:SetBlendMode("ADD")
        highlight:SetAllPoints()
        btn.highlightTexture = highlight

        local selected = btn:CreateTexture(nil, "OVERLAY")
        selected:SetTexture("Interface/Shop/store-main")
        selected:SetTexCoord(0.73681641, 0.90087891, 0.46435547, 0.49365234)
        selected:SetBlendMode("ADD")
        selected:SetAllPoints()
        selected:Hide()
        btn.selectedTexture = selected

        if cat.subcategories then
            btn.toggle = CreateFrame("Button", nil, btn)
            btn.toggle:SetSize(18, 18)
            btn.toggle:SetPoint("RIGHT", -7, 0)

            btn.toggle.background = btn:CreateTexture(nil, "OVERLAY")
            btn.toggle.background:SetTexture("Interface/Shop/perksactivities")

            if btnToggleExpandedState == false then
                btn.toggle.background:SetTexCoord(0.36987305, 0.38061523, 0.53564453, 0.55712891)
            else
                btn.toggle.background:SetTexCoord(0.36987305, 0.38061523, 0.55908203, 0.58056641)
            end

            btn.toggle.background:SetAllPoints(btn.toggle)

            btn.toggle:SetScript("OnClick", function()
                PlaySound(852)
                cat.isExpanded = not cat.isExpanded

                if btnToggleExpandedState == false then
                    btnToggleExpandedState = true
                else
                    btnToggleExpandedState = false
                end

                ModernShop_RenderCategories()
            end)
        end

        if cat.id == 1 then
            ModernShopCurrentPage = 1 -- Always reset page when clicking a category!

            -- Deselect old category
            if ModernShopSelectedCategoryButton and ModernShopSelectedCategoryButton.selectedTexture then
                ModernShopSelectedCategoryButton.selectedTexture:Hide()
            end

            -- Deselect old subcategory too
            if ModernShopSelectedSubcategoryButton and ModernShopSelectedSubcategoryButton.selectedTexture then
                ModernShopSelectedSubcategoryButton.selectedTexture:Hide()
                ModernShopSelectedSubcategoryButton = nil -- Clear tracking
            end

            -- Select new category
            ModernShopSelectedCategoryButton = btn
            if btn.selectedTexture then
                btn.selectedTexture:Show()
            end

            -- Load correct tab
            if cat.name == "Featured" then
                ModernShop_LoadFeaturedTab()
            elseif cat.name == "Special" then
                ModernShop_LoadSpecialTab()
            elseif cat.name == "Packs" then
                ModernShop_LoadPacksTab()
            else
                ModernShop_LoadEntriesTab(cat.id)
            end

            PlaySound(852)
        end

        btn:SetScript("OnClick", function(self)
            ModernShopCurrentPage = 1 -- Always reset page when clicking a category!

            -- Deselect old category
            if ModernShopSelectedCategoryButton and ModernShopSelectedCategoryButton.selectedTexture then
                ModernShopSelectedCategoryButton.selectedTexture:Hide()
            end

            -- Deselect old subcategory too
            if ModernShopSelectedSubcategoryButton and ModernShopSelectedSubcategoryButton.selectedTexture then
                ModernShopSelectedSubcategoryButton.selectedTexture:Hide()
                ModernShopSelectedSubcategoryButton = nil -- Clear tracking
            end

            -- Select new category
            ModernShopSelectedCategoryButton = self
            if self.selectedTexture then
                self.selectedTexture:Show()
            end

            -- Load correct tab
            if cat.name == "Featured" then
                ModernShop_LoadFeaturedTab()
            elseif cat.name == "Special" then
                ModernShop_LoadSpecialTab()
            elseif cat.name == "Packs" then
                ModernShop_LoadPacksTab()
            else
                ModernShop_LoadEntriesTab(cat.id)
            end

            PlaySound(852)
        end)

        CategoryButtons[cat.name] = btn -- Store reference
        btn:Show()
        yOffset = yOffset + 35

        -- Inline subcategory rendering
        if cat.isExpanded and cat.subcategories then
            for _, sub in ipairs(cat.subcategories) do
                buttonIndex = buttonIndex + 1
                local subBtn = CreateFrame("Button", "ModernShopCategoryButton" .. buttonIndex, ModernShopFrame)
                subBtn:SetSize(160, 30)
                subBtn:SetPoint("TOPLEFT", 30, -yOffset)

                subBtn.bg = subBtn:CreateTexture(nil, "BACKGROUND")
                subBtn.bg:SetTexture("Interface/Shop/store-main")
                subBtn.bg:SetTexCoord(0.56689453, 0.73291016, 0.42041016, 0.45263672)
                subBtn.bg:SetAllPoints()

                subBtn.label = subBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                subBtn.label:SetPoint("LEFT", subBtn, "LEFT", 8, 0)
                subBtn.label:SetText(sub.name)

                subBtn.highlight = subBtn:CreateTexture(nil, "HIGHLIGHT")
                subBtn.highlight:SetTexture("Interface/Shop/store-main")
                subBtn.highlight:SetTexCoord(0.00341797, 0.16748047, 0.93896484, 0.96826172)
                subBtn.highlight:SetBlendMode("ADD")
                subBtn.highlight:SetAllPoints()
                subBtn.highlightTexture = subBtn.highlight

                subBtn.selected = subBtn:CreateTexture(nil, "OVERLAY")
                subBtn.selected:SetTexture("Interface/Shop/store-main")
                subBtn.selected:SetTexCoord(0.73681641, 0.90087891, 0.46435547, 0.49365234)
                subBtn.selected:SetBlendMode("ADD")
                subBtn.selected:SetAllPoints()
                subBtn.selected:Hide()
                subBtn.selectedTexture = subBtn.selected

                subBtn:SetScript("OnClick", function(self)
                    if ModernShopSelectedSubcategoryButton and ModernShopSelectedSubcategoryButton.selectedTexture then
                        ModernShopSelectedSubcategoryButton.selectedTexture:Hide()
                    end

                    ModernShopSelectedSubcategoryButton = self
                    if self.selectedTexture then
                        self.selectedTexture:Show()
                    end

                    -- Load subcategory entries
                    ModernShop_LoadEntriesTab(cat.id, sub.id)

                    PlaySound(852)
                end)

                CategoryButtons[buttonIndex] = subBtn -- for subBtn stores by button index instead of name
                subBtn:Show()
                yOffset = yOffset + 35
            end
        end
    end
end

-- Create custom close button with texcoords
if not ModernShopCloseButton then
    ModernShopCloseButton = CreateFrame("Button", "ModernShopCloseButton", ModernShopFrame)
    ModernShopCloseButton:SetSize(22, 22)
    ModernShopCloseButton:SetPoint("TOPRIGHT", ModernShopFrame, "TOPRIGHT", -1, -1)

    -- Normal Texture
    local normal = ModernShopCloseButton:CreateTexture(nil, "ARTWORK")
    normal:SetTexture("Interface/Shop/redbutton2x")
    normal:SetTexCoord(0.15429688, 0.28320312, 0.01171875, 0.28515625)
    normal:SetAllPoints()
    ModernShopCloseButton:SetNormalTexture(normal)

    -- Pushed Texture
    local pushed = ModernShopCloseButton:CreateTexture(nil, "ARTWORK")
    pushed:SetTexture("Interface/Shop/redbutton2x")
    pushed:SetTexCoord(0.15429688, 0.28320312, 0.01171875, 0.28515625)
    pushed:SetAllPoints()
    ModernShopCloseButton:SetPushedTexture(pushed)

    -- Highlight Texture (Blizzard glow)
    ModernShopCloseButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    -- Click behavior
    ModernShopCloseButton:SetScript("OnClick", function()
        PlaySound(850) -- UI_CLOSE
        ModernShopFrame:Hide()
    end)
end

-- Buy Button
if not ModernShopBuyButton then
    ModernShopBuyButton = CreateFrame("Button", "ModernShopBuyButton", ModernShopFrame)
    ModernShopBuyButton:SetSize(100, 30)
    ModernShopBuyButton:SetPoint("BOTTOM", ModernShopFrame, "BOTTOM", 75, 20)
    ModernShopBuyButton:Hide()

    -- texCoords for buy button
    ModernShopBuyButton.texCoords = {
        normal = {
            left = { 0.59082031, 0.78417969, 0.51806641, 0.62451172 },
            middle = { 0.55761719, 0.99121094, 0.01025391, 0.11669922 },
            right = { 0.35839844, 0.55175781, 0.51806641, 0.62451172 },
        },
        disabled = {
            left = { 0.59277344, 0.78613281, 0.64501953, 0.75146484 },
            middle = { 0.55761719, 0.99121094, 0.13720703, 0.24365234 },
            right = { 0.35839844, 0.55175781, 0.64501953, 0.75146484 },
        },
        pushed = {
            left = { 0.59082031, 0.78417969, 0.77197266, 0.87841797 },
            middle = { 0.55761719, 0.99121094, 0.26416016, 0.37060547 },
            right = { 0.35839844, 0.55175781, 0.77197266, 0.87841797 },
        }
    }

    ModernShopBuyButton.currentState = "disabled"

    -- Create MIDDLE part
    ModernShopBuyButton.middleTexture = ModernShopBuyButton:CreateTexture(nil, "BACKGROUND")
    ModernShopBuyButton.middleTexture:SetSize(100, 30)
    ModernShopBuyButton.middleTexture:SetTexture("Interface/Shop/128goldredbutton")
    ModernShopBuyButton.middleTexture:SetTexCoord(0.00097656, 0.99707031, 0.01025391, 0.11669922)
    ModernShopBuyButton.middleTexture:SetPoint("BOTTOMRIGHT", ModernShopBuyButton, "BOTTOMRIGHT", -24, 0)

    -- Create LEFT part
    ModernShopBuyButton.leftTexture = ModernShopBuyButton:CreateTexture(nil, "BACKGROUND")
    ModernShopBuyButton.leftTexture:SetTexture("Interface/Shop/128goldredbutton")
    ModernShopBuyButton.leftTexture:SetTexCoord(0.59277344, 0.79785156, 0.52001953, 0.62255859)
    ModernShopBuyButton.leftTexture:SetSize(25, 30)
    ModernShopBuyButton.leftTexture:SetPoint("CENTER", ModernShopBuyButton.middleTexture, "CENTER", -50, 0)

    -- Create RIGHT part
    ModernShopBuyButton.rightTexture = ModernShopBuyButton:CreateTexture(nil, "BACKGROUND")
    ModernShopBuyButton.rightTexture:SetTexture("Interface/Shop/128goldredbutton")
    ModernShopBuyButton.rightTexture:SetTexCoord(0.34667969, 0.55175781, 0.52001953, 0.62255859)
    ModernShopBuyButton.rightTexture:SetSize(25, 30)
    ModernShopBuyButton.rightTexture:SetPoint("CENTER", ModernShopBuyButton.middleTexture, "CENTER", 50, 0)

    -- Font label
    ModernShopBuyButton.label = ModernShopBuyButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ModernShopBuyButton.label:SetText("|CFF9c9c9b Buy Now")
    ModernShopBuyButton.label:SetPoint("CENTER", ModernShopBuyButton.middleTexture, "CENTER")

    -- texCoords for Highlights
    local hlLeft   = { 0.046875, 0.890625, 0.0234375, 0.6796875 }
    local hlMiddle = { 0.015625, 0.921875, 0.0390625, 0.6640625 }
    local hlRight  = { 0.015625, 0.890625, 0.0390625, 0.6640625 }

    -- Highlight MIDDLE
    ModernShopBuyButton:SetScript("OnEnter", function(self)
        if ModernShopBuyButton.currentState ~= "disabled" then
            local hlMiddleTex = ModernShopBuyButton:CreateTexture(nil, "HIGHLIGHT")
            hlMiddleTex:SetTexture("Interface/Shop/ui-silverbuttonlg-mid-hi")
            hlMiddleTex:SetTexCoord(unpack(hlMiddle))
            hlMiddleTex:SetSize(100, 30)
            hlMiddleTex:SetPoint("BOTTOMRIGHT", ModernShopBuyButton, "BOTTOMRIGHT", -24, 0)

            -- Highlight LEFT
            local hlLeftTex = ModernShopBuyButton:CreateTexture(nil, "HIGHLIGHT")
            hlLeftTex:SetTexture("Interface/Shop/ui-silverbuttonlg-left-hi")
            hlLeftTex:SetTexCoord(unpack(hlLeft))
            hlLeftTex:SetSize(25, 30)
            hlLeftTex:SetPoint("CENTER", hlMiddleTex, "CENTER", -50, 0)

            -- Highlight RIGHT
            local hlRightTex = ModernShopBuyButton:CreateTexture(nil, "HIGHLIGHT")
            hlRightTex:SetTexture("Interface/Shop/ui-silverbuttonlg-right-hi")
            hlRightTex:SetTexCoord(unpack(hlRight))
            hlRightTex:SetSize(25, 30)
            hlRightTex:SetPoint("CENTER", hlMiddleTex, "CENTER", 50, 0)

            -- Set alpha + blend mode for Blizzard-style glow
            hlLeftTex:SetBlendMode("ADD")
            hlMiddleTex:SetBlendMode("ADD")
            hlRightTex:SetBlendMode("ADD")

            hlLeftTex:SetAlpha(0.7)
            hlMiddleTex:SetAlpha(0.7)
            hlRightTex:SetAlpha(0.7)
        end
    end)

    ModernShopBuyButton:SetScript("OnMouseDown", function(self)
        if ModernShopBuyButton.isEnabled then
            ModernShop_UpdateBuyButtonVisual("pushed")
        end
    end)

    ModernShopBuyButton:SetScript("OnMouseUp", function(self)
        if ModernShopBuyButton.isEnabled then
            ModernShop_UpdateBuyButtonVisual("normal")
        end
    end)

    ModernShopBuyButton:SetScript("OnClick", function()
        if ModernShopSelectedEntry then
            ModernShop_UpdateBuyButtonVisual("disabled")
            ModernShopFrame:Hide()
            ModernShopBuyButton:Hide()
            -- Send purchase request using new communication system
            ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SHOP_PURCHASE, tostring(ModernShopSelectedEntry.id))
            ModernShopSelectedEntry = nil
        end
    end)
end


function ModernShop_UpdateBuyButtonVisual(state)
    local coords = ModernShopBuyButton.texCoords[state]
    if not coords then return end

    ModernShopBuyButton.currentState = state

    --Adjust label color
    if state == "disabled" then
        ModernShopBuyButton.label:SetText("|CFF9c9c9b Buy Now")
    else
        ModernShopBuyButton.label:SetText("|CFFf7d219 Buy Now")
    end

    ModernShopBuyButton.leftTexture:SetTexCoord(unpack(coords.left))
    ModernShopBuyButton.middleTexture:SetTexCoord(unpack(coords.middle))
    ModernShopBuyButton.rightTexture:SetTexCoord(unpack(coords.right))
end

-- Page Navigation Text
ModernShopPageText = ModernShopFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ModernShopPageText:SetPoint("BOTTOMRIGHT", ModernShopFrame, "BOTTOMRIGHT", -90, 20)
ModernShopPageText:Hide()

-- Previous Page Button
ModernShopPagePrev = CreateFrame("Button", nil, ModernShopFrame)
ModernShopPagePrev:SetSize(24, 24)
ModernShopPagePrev:SetPoint("CENTER", ModernShopPageText, "CENTER", 55, 0)

ModernShopPagePrevIcon = ModernShopPagePrev:CreateTexture(nil, "ARTWORK")
ModernShopPagePrevIcon:SetTexture("Interface/Shop/Buttons\\ui-spellbookicon-prevpage-up")
ModernShopPagePrevIcon:SetTexCoord(0.046875, 0.859375, 0.109375, 0.890625)
ModernShopPagePrevIcon:SetAllPoints()

ModernShopPagePrevHighlight = ModernShopPagePrev:CreateTexture(nil, "HIGHLIGHT")
ModernShopPagePrevHighlight:SetTexture("Interface/Shop/Buttons/heckbuttonhilight-blue")
ModernShopPagePrevHighlight:SetSize(40, 40)
ModernShopPagePrevHighlight:SetPoint("CENTER", ModernShopPagePrevIcon, "CENTER", 0, 0)

ModernShopPagePrev:SetScript("OnClick", function()
    if ModernShopCurrentPage > 1 then
        ModernShopCurrentPage = ModernShopCurrentPage - 1
        if ModernShopLastCategoryID == 4 then -- Packs
            ModernShop_LoadPacksTab()
        else
            ModernShop_LoadEntriesTab(ModernShopLastCategoryID, ModernShopLastSubcategoryID)
        end
    end

    PlaySound(852)
end)

ModernShopPagePrev:Hide()

-- Next Page Button
ModernShopPageNext = CreateFrame("Button", nil, ModernShopFrame)
ModernShopPageNext:SetSize(24, 24)
ModernShopPageNext:SetPoint("CENTER", ModernShopPageText, "CENTER", 80, 0)

ModernShopPageNextIcon = ModernShopPageNext:CreateTexture(nil, "ARTWORK")
ModernShopPageNextIcon:SetTexture("Interface/Shop/Buttons\\ui-spellbookicon-nextpage-up")
ModernShopPageNextIcon:SetTexCoord(0.046875, 0.859375, 0.109375, 0.890625)
ModernShopPageNextIcon:SetAllPoints()

ModernShopPageNextHighlight = ModernShopPageNext:CreateTexture(nil, "HIGHLIGHT")
ModernShopPageNextHighlight:SetTexture("Interface/Shop/Buttons/heckbuttonhilight-blue")
ModernShopPageNextHighlight:SetSize(40, 40)
ModernShopPageNextHighlight:SetPoint("CENTER", ModernShopPageNextIcon, "CENTER", 0, 0)

ModernShopPageNext:SetScript("OnClick", function()
    if ModernShopCurrentPage < ModernShopTotalPages then
        ModernShopCurrentPage = ModernShopCurrentPage + 1
        if ModernShopLastCategoryID == 4 then -- Packs
            ModernShop_LoadPacksTab()
        else
            ModernShop_LoadEntriesTab(ModernShopLastCategoryID, ModernShopLastSubcategoryID)
        end
    end

    PlaySound(852)
end)

ModernShopPageNext:Hide()

-- Preview Frame
-- Create Main Preview Frame
ModernShopPreviewFrame = CreateFrame("Frame", "ModernShopPreviewFrame", UIParent)
ModernShopPreviewFrame:SetSize(400, 500)
ModernShopPreviewFrame:SetPoint("CENTER")
ModernShopPreviewFrame:SetFrameStrata("DIALOG")
ModernShopPreviewFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})
ModernShopPreviewFrame:Hide()

ModernShopPreviewFrame.isRotatingLeft = false
ModernShopPreviewFrame.isRotatingRight = false
ModernShopPreviewFrame.rotationSpeed = 0 -- starts at 0
ModernShopPreviewFrame.rotationTimer = 0 -- used to increase speed

ModernShopPreviewFrame:SetScript("OnUpdate", function(self, elapsed)
    if ProjectEbonhold_IsClosing then return end
    if not UIParent:IsShown() then return end
    elapsed = math.min(elapsed, 0.1) -- Cap elapsed to prevent freeze after alt-tab
    if self.isRotatingLeft or self.isRotatingRight then
        self.rotationTimer = self.rotationTimer + elapsed

        -- Accelerate over time
        local speed = self.rotationSpeed + (self.rotationTimer * 2)

        if self.isRotatingLeft then
            if ModernShopPreviewFrame.CreatureModel:IsShown() then
                ModernShopPreviewFrame.CreatureModel:SetFacing(ModernShopPreviewFrame.CreatureModel:GetFacing() +
                    elapsed * speed)
            elseif ModernShopPreviewFrame.PlayerModel:IsShown() then
                ModernShopPreviewFrame.PlayerModel:SetFacing(ModernShopPreviewFrame.PlayerModel:GetFacing() +
                    elapsed * speed)
            end
        elseif self.isRotatingRight then
            if ModernShopPreviewFrame.CreatureModel:IsShown() then
                ModernShopPreviewFrame.CreatureModel:SetFacing(ModernShopPreviewFrame.CreatureModel:GetFacing() -
                    elapsed * speed)
            elseif ModernShopPreviewFrame.PlayerModel:IsShown() then
                ModernShopPreviewFrame.PlayerModel:SetFacing(ModernShopPreviewFrame.PlayerModel:GetFacing() -
                    elapsed * speed)
            end
        end
    end
end)

-- Close Button
ModernShopPreviewFrame.CloseButton = CreateFrame("Button", nil, ModernShopPreviewFrame, "UIPanelCloseButton")
ModernShopPreviewFrame.CloseButton:SetPoint("TOPRIGHT", -5, -5)
ModernShopPreviewFrame.CloseButton:SetScript("OnClick", function()
    ModernShopPreviewFrame:Hide()
    ModernShopPreviewFrame.CreatureModel:Hide()
    ModernShopPreviewFrame.PlayerModel:Hide()
    ModernShopFrame:Show()

    PlaySound(850)
end)

-- Creature Model
ModernShopPreviewFrame.CreatureModel = CreateFrame("DressUpModel", nil, ModernShopPreviewFrame)
ModernShopPreviewFrame.CreatureModel:SetSize(350, 450)
ModernShopPreviewFrame.CreatureModel:SetPoint("CENTER")
ModernShopPreviewFrame.CreatureModel:Hide()
ModernShopPreviewFrame.CreatureModel:EnableMouse(true)
ModernShopPreviewFrame.CreatureModel:EnableMouseWheel(true)
ModernShopPreviewFrame.CreatureModel.zoomScale = 1.0
ModernShopPreviewFrame.CreatureModel:SetScale(ModernShopPreviewFrame.CreatureModel.zoomScale)

ModernShopPreviewFrame.CreatureModel:SetScript("OnMouseWheel", function(self, delta)
    local step = 0.1
    self.zoomScale = self.zoomScale + (delta * step)
    self.zoomScale = math.max(0.5, math.min(2.0, self.zoomScale))

    self:SetScale(self.zoomScale)
end)

local model = ModernShopPreviewFrame.CreatureModel
model:EnableMouse(true)

-- Variables de suivi
model.isDragging = false
model.lastX = 0

model:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        self.isDragging = true
        self.lastX = GetCursorPosition()
        self:GetParent():SetFrameStrata("FULLSCREEN_DIALOG") -- pour que ça passe au-dessus pendant le drag
    end
end)

model:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        self.isDragging = false
        self:GetParent():SetFrameStrata("DIALOG")
    end
end)

model:SetScript("OnUpdate", function(self)
    if ProjectEbonhold_IsClosing then return end
    if not UIParent:IsShown() then return end
    if self.isDragging then
        local x = GetCursorPosition()
        local dx = x - self.lastX

        -- Vitesse de rotation
        local speed = 0.005
        local facing = self:GetFacing()
        self:SetFacing(facing + dx * speed)

        self.lastX = x
    end
end)


-- Player Model
ModernShopPreviewFrame.PlayerModel = CreateFrame("DressUpModel", nil, ModernShopPreviewFrame)
ModernShopPreviewFrame.PlayerModel:SetSize(350, 450)
ModernShopPreviewFrame.PlayerModel:SetPoint("CENTER")
ModernShopPreviewFrame.PlayerModel:Hide()

-- Toast Frame
-- Create Toast Frame
ModernShopToastFrame = CreateFrame("Frame", "ModernShopToastFrame", UIParent)
ModernShopToastFrame:SetSize(300, 80)
ModernShopToastFrame:SetPoint("TOP", UIParent, "TOP", 0, -200)
ModernShopToastFrame:SetFrameStrata("TOOLTIP")
ModernShopToastFrame:SetAlpha(0)
ModernShopToastFrame:Hide()

-- Background Frame with TexCoords
ModernShopToastFrame.bg = ModernShopToastFrame:CreateTexture(nil, "BACKGROUND")
ModernShopToastFrame.bg:SetTexture("Interface/Shop/store-main")
ModernShopToastFrame.bg:SetTexCoord(0.51416016, 0.78857422, 0.54736328, 0.61962891)
ModernShopToastFrame.bg:SetAllPoints()

-- Icon
ModernShopToastFrame.icon = ModernShopToastFrame:CreateTexture(nil, "ARTWORK")
ModernShopToastFrame.icon:SetSize(42, 42)
ModernShopToastFrame.icon:SetPoint("LEFT", 20, 0)

-- Name
ModernShopToastFrame.name = ModernShopToastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ModernShopToastFrame.name:SetPoint("TOPLEFT", ModernShopToastFrame.icon, "TOPRIGHT", 75, -2)
ModernShopToastFrame.name:SetTextColor(1, 0.82, 0) -- golden

-- Subtitle
ModernShopToastFrame.message = ModernShopToastFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ModernShopToastFrame.message:SetPoint("TOPLEFT", ModernShopToastFrame.name, "BOTTOMLEFT", -5, -4)
ModernShopToastFrame.message:SetText("Your item has been delivered.")


function ModernShop_EnsureCategoryFrame()
    if not ModernShopCategoryFrame then
        ModernShopCategoryFrame = CreateFrame("Frame", "ModernShopCategoryFrame", ModernShopFrame)
        ModernShopCategoryFrame:SetSize(580, 540)
        ModernShopCategoryFrame:SetPoint("TOPLEFT", ModernShopFrame, "TOPLEFT", 210, -54)
    end

    ModernShopCategoryFrame:Show()
end

function ModernShop_LoadEntriesTab(categoryID, subcategoryID)
    ModernShopEntryFrames = {}

    ModernShop_ClearCategoryFrame()
    if ModernShopPacksBuyButton then ModernShopPacksBuyButton:Hide() end -- Hide packs buy button if it was visible

    ModernShop_EnsureCategoryFrame()

    ModernShopLastCategoryID = categoryID
    ModernShopLastSubcategoryID = subcategoryID
    ModernShopCurrentPage = ModernShopCurrentPage or 1

    -- Custom per-page for Transmogs
    local entriesPerPage = (categoryID == 8) and 2 or ModernShopEntriesPerPage

    ModernShopServicesFrame = CreateFrame("Frame", "ModernShopServicesFrame", ModernShopCategoryFrame)
    ModernShopServicesFrame:SetAllPoints()

    -- Reset selection
    if ModernShopSelectedEntryFrame and ModernShopSelectedEntryFrame.selectHighlight then
        ModernShopSelectedEntryFrame.selectHighlight:Hide()
    end
    ModernShopSelectedEntryFrame = nil
    ModernShopBuyButton:Show()
    ModernShopSelectedEntry = nil

    ModernShop_UpdateBuyButtonVisual("disabled")
    -- Gather entries
    wipe(ModernShopCurrentEntrySet)
    for _, entry in ipairs(Addon.ShopEntries) do
        local isMatch = entry.category_id == categoryID and (not subcategoryID or entry.subcategory_id == subcategoryID)
        if isMatch then
            -- DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[DEBUG] Adding entry " .. entry.id .. " to display (discount: " .. tostring(entry.discount) .. ", discountActive: " .. tostring(entry.discountActive) .. ")|r")
            tinsert(ModernShopCurrentEntrySet, entry)
        end
    end

    ModernShopTotalPages = math.ceil(#ModernShopCurrentEntrySet / entriesPerPage)
    ModernShopCurrentPage = math.max(1, math.min(ModernShopCurrentPage, ModernShopTotalPages))

    local startIndex = (ModernShopCurrentPage - 1) * entriesPerPage + 1
    local endIndex = math.min(startIndex + entriesPerPage - 1, #ModernShopCurrentEntrySet)

    -- Layout settings
    local xSpacing = 170
    local ySpacing = 220
    local itemsPerRow = 4
    local itemWidth = 150
    local itemHeight = 200

    local index = 0

    for i = startIndex, endIndex do
        local entry = ModernShopCurrentEntrySet[i]
        index = index + 1

        local row = math.floor((index - 1) / itemsPerRow)
        local col = (index - 1) % itemsPerRow

        local frame = CreateFrame("Button", nil, ModernShopServicesFrame)
        frame:SetSize(itemWidth, itemHeight)
        frame:SetPoint("TOPLEFT", 10 + col * xSpacing, -20 - row * ySpacing)
        tinsert(ModernShopEntryFrames, frame)
        -- Background
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface/Shop/store-main")
        bg:SetTexCoord(0.18896484, 0.32177734, 0.64990234, 0.84423828)
        bg:SetAllPoints()

        local cost;
        local discount;
        local name;
        local icon;
        local border;
        local badge;

        if categoryID == 5 or categoryID == 6 or categoryID == 7 then -- Mounts / Pets / Toys
            local safeName = entry.name:gsub(" ", "_")
            local texturePath

            local model = CreateFrame("DressUpModel", nil, frame)
            model:SetSize(100, 100)
            model:SetPoint("TOP", frame, "TOP", 0, -20)
            model:ClearModel()
            model:SetCreature(entry.creatureId) -- <-- ici tu mets le CreatureID directement

            name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            name:SetPoint("TOP", model, "BOTTOM", 0, -10)
            name:SetWidth(100)
            name:SetWordWrap(true)
            name:SetText(entry.name)

            cost = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            cost:SetPoint("BOTTOM", bg, "BOTTOM", 0, 10)
            cost:SetText(entry.price .. " DP")
        elseif categoryID == 8 then -- Transmog
            frame.TmogEntryModel = CreateFrame("DressUpModel", nil, frame)
            frame.TmogEntryModel:SetSize(100, 200)
            frame.TmogEntryModel:SetPoint("CENTER")
            frame.TmogEntryModel:SetPoint("TOP", frame, "TOP", 0, 20)
            frame.TmogEntryModel:SetFrameLevel(10000)
            frame.TmogEntryModel:SetUnit("player")

            for _, itemID in ipairs(entry.previewItems) do
                frame.TmogEntryModel:TryOn(itemID)
            end

            frame.isRotatingLeft = false
            frame.isRotatingRight = false
            frame.rotationSpeed = 0 -- starts at 0
            frame.rotationTimer = 0 -- used to increase speed

            frame:SetScript("OnUpdate", function(self, elapsed)
                if ProjectEbonhold_IsClosing then return end
                if not UIParent:IsShown() then return end
                elapsed = math.min(elapsed, 0.1) -- Cap elapsed to prevent freeze after alt-tab
                if self.isRotatingLeft or self.isRotatingRight then
                    self.rotationTimer = self.rotationTimer + elapsed

                    -- Accelerate over time
                    local speed = self.rotationSpeed + (self.rotationTimer * 2)

                    if self.isRotatingLeft then
                        if frame.TmogEntryModel:IsShown() then
                            frame.TmogEntryModel:SetFacing(frame.TmogEntryModel:GetFacing() - elapsed * speed)
                        end
                    elseif self.isRotatingRight then
                        if frame.TmogEntryModel:IsShown() then
                            frame.TmogEntryModel:SetFacing(frame.TmogEntryModel:GetFacing() + elapsed * speed)
                        end
                    end
                end
            end)

            -- Rotate Left Button
            frame.RotateLeftButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            frame.RotateLeftButton:SetSize(24, 24)
            frame.RotateLeftButton:SetText("<")
            frame.RotateLeftButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 20)

            frame.RotateLeftButton:SetScript("OnMouseDown", function()
                frame.isRotatingLeft = true
                frame.rotationSpeed = 1 -- starting speed
                frame.rotationTimer = 0
            end)

            frame.RotateLeftButton:SetScript("OnMouseUp", function()
                frame.isRotatingLeft = false
                frame.rotationSpeed = 0
            end)

            frame.RotateLeftButton:SetScript("OnClick", function()
                if frame.TmogEntryModel:IsShown() then
                    local facing = frame.TmogEntryModel:GetFacing()
                    frame.TmogEntryModel:SetFacing(facing + 0.1)
                end

                PlaySound(852)
            end)

            -- Rotate Right Button
            frame.RotateRightButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            frame.RotateRightButton:SetSize(24, 24)
            frame.RotateRightButton:SetText(">")
            frame.RotateRightButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)

            frame.RotateRightButton:SetScript("OnMouseDown", function()
                frame.isRotatingRight = true
                frame.rotationSpeed = 1
                frame.rotationTimer = 0
            end)

            frame.RotateRightButton:SetScript("OnMouseUp", function()
                frame.isRotatingRight = false
                frame.rotationSpeed = 0
            end)

            frame.RotateRightButton:SetScript("OnClick", function()
                if frame.TmogEntryModel:IsShown() then
                    local facing = frame.TmogEntryModel:GetFacing()
                    frame.TmogEntryModel:SetFacing(facing - 0.1)
                end

                PlaySound(852)
            end)

            name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            name:SetPoint("BOTTOM", frame, "BOTTOM", 0, 40)
            name:SetText(entry.name)

            cost = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            cost:SetPoint("TOP", name, "BOTTOM", 0, -6)
            cost:SetText(entry.price .. " DP")
        else -- Other (services etc)
            border = frame:CreateTexture(nil, "OVERLAY")
            border:SetTexture("Interface/Shop/store-main")
            border:SetTexCoord(0.84912109, 0.91845703, 0.37255859, 0.44189453)
            border:SetSize(64, 64)
            border:SetPoint("TOP", frame, "TOP", 0, -20)

            icon = frame:CreateTexture(nil, "ARTWORK")
            icon:SetTexture("Interface\\Icons\\" .. entry.icon)
            icon:SetSize(45, 45)
            icon:SetPoint("CENTER", border, "CENTER", 0, 0)

            name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            name:SetPoint("TOP", border, "BOTTOM", 0, -20)
            name:SetWidth(110)
            name:SetText(entry.name)
            name:SetWordWrap(true)

            cost = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            cost:SetPoint("TOP", name, "BOTTOM", 0, -6)
            cost:SetText(entry.price .. " DP")
        end

        -- Hover Highlight
        local hoverHighlight = frame:CreateTexture(nil, "HIGHLIGHT")
        hoverHighlight:SetTexture("Interface/Shop/store-main")
        hoverHighlight:SetTexCoord(0.37060547, 0.50341797, 0.54345703, 0.73779297)
        hoverHighlight:SetBlendMode("ADD")
        hoverHighlight:SetAllPoints()
        hoverHighlight:SetAlpha(0.8)

        -- Selection Highlight
        local selected = frame:CreateTexture(nil, "OVERLAY")
        selected:SetTexture("Interface/Shop/store-main")
        selected:SetTexCoord(0.37158203, 0.50439453, 0.74365234, 0.93798828)
        selected:SetBlendMode("ADD")
        selected:SetAllPoints()
        selected:SetAlpha(0.7)
        selected:Hide()
        frame.selectHighlight = selected

        -- Price formatting
        local originalPrice = entry.price
        local finalPrice = entry.discount -- This is the discountPrice from server
        local discountValue = 0

        -- Debug discount logic
        if entry.discountActive then
            -- DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[DEBUG] Item " .. entry.id .. " has discount active. Original: " .. tostring(originalPrice) .. ", Final: " .. tostring(finalPrice) .. "|r")
        end

        -- Only show discount if discountActive is true AND we have a valid discountPrice
        if entry.discountActive and finalPrice and finalPrice > 0 and originalPrice and originalPrice > finalPrice then
            -- Calcul du pourcentage de réduction
            discountValue = math.floor((1 - (finalPrice / originalPrice)) * 100)

            -- Badge graphique de réduction
            badge = frame:CreateTexture(nil, "OVERLAY")
            badge:SetTexture("Interface/Shop/discountLabel")
            badge:SetTexCoord(0.1953125, 0.7890625, 0.3046875, 0.7109375)
            badge:SetSize(50, 32)
            badge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 3, 3)

            -- Texte sur le badge : pourcentage calculé
            badge.badgeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            badge.badgeLabel:SetPoint("CENTER", badge, "CENTER", 0, 0)
            badge.badgeLabel:SetText(discountValue .. "%")

            -- Affichage des prix
            cost:SetPoint("TOP", name, "BOTTOM", -40, -6)
            cost:SetText("|cFFFF5555" .. originalPrice .. " DP|r")  -- Prix original
            cost:SetFont("Fonts\\FRIZQT__.TTF", 9)

            discount = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            discount:SetText("|cff00ff00" .. finalPrice .. " DP|r") -- Prix en promo
            discount:SetPoint("CENTER", cost, "CENTER", 50, 0)
        end

        -- Is New badge
        if entry.isNew == true then
            local newbadge = frame:CreateTexture(nil, "OVERLAY")
            newbadge:SetTexture("Interface/Shop/store-main")
            newbadge:SetTexCoord(0.33251953, 0.36376953, 0.64990234, 0.68310547)
            newbadge:SetSize(32, 32)
            newbadge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 1.5)
        end

        -- Is Special badge
        if entry.isSpecial == true then
            local isSpecialBadge = frame:CreateTexture(nil, "OVERLAY")
            isSpecialBadge:SetTexture("Interface/Shop/store-main")
            isSpecialBadge:SetTexCoord(0.93798828, 0.96923828, 0.23876953, 0.27197266)
            isSpecialBadge:SetSize(32, 32)
            isSpecialBadge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 1.5)
        end

        -- already owned badge
        if entry.isOwned == true then
            local isOwnedBadge = frame:CreateTexture(nil, "OVERLAY")
            isOwnedBadge:SetTexture("Interface/Shop/store-main")
            isOwnedBadge:SetTexCoord(0.81689453, 0.83544922, 0.42138672, 0.43798828)
            isOwnedBadge:SetSize(16, 16)
            isOwnedBadge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -7)
        end

        -- already owned badge
        if entry.isInDealPresent == true then
            local isInDealPresentBadge = frame:CreateTexture(nil, "OVERLAY")
            isInDealPresentBadge:SetTexture("Interface/Shop/store-main")
            isInDealPresentBadge:SetTexCoord(0.15966797, 0.17822266, 0.97412109, 0.99072266)
            isInDealPresentBadge:SetSize(16, 16)
            isInDealPresentBadge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -7)
        end

        -- Magnifying Glass Button / Preview
        if entry.category_id == 5 or entry.category_id == 6 then -- 5 & 6 Mounts & Pets
            local previewEntrie = CreateFrame("Button", nil, frame)
            previewEntrie:SetSize(20, 20)
            previewEntrie:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -7)

            local previewEntrieicon = previewEntrie:CreateTexture(nil, "ARTWORK")
            previewEntrieicon:SetTexture("Interface/Shop/store-main")
            previewEntrieicon:SetTexCoord(0.33154297, 0.35888672, 0.72412109, 0.75341797)
            previewEntrieicon:SetAllPoints()

            previewEntrie:SetScript("OnClick", function()
                ModernShop_OpenPreview(entry)

                PlaySound(852)
            end)
        else
            if previewEntrie then
                previewEntrie:Hide()
            end
        end

        local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        infoText:SetPoint("TOP", name, "BOTTOM", 0, -15)
        infoText:SetText("") -- Empty initially
        infoText:Hide()

        frame.infoText = infoText -- Store reference

        frame:SetScript("OnEnter", function(self)
            if entry.extraInfo then
                -- Hide Preview Button
                if self.previewButton then
                    self.previewButton:Hide()
                end

                -- Hide Icon
                if icon then
                    icon:Hide()
                end

                if border then
                    border:Hide();
                end

                -- Move Name Label Higher
                name:ClearAllPoints()
                name:SetPoint("TOP", self, "TOP", 0, -15)

                -- Show Info Text
                infoText:SetText(entry.extraInfo)
                infoText:SetFont("Fonts\\FRIZQT__.TTF", 11)
                infoText:SetWidth(130)
                infoText:SetWordWrap(true)
                infoText:Show()

                cost:Hide()
                if badge then
                    discount:Hide();
                    badge:Hide();
                    badge.badgeLabel:Hide();
                end
            end
        end)

        frame:SetScript("OnLeave", function(self)
            if entry.extraInfo then
                -- Show Preview Button again
                if self.previewButton then
                    self.previewButton:Show()
                end
                if icon then
                    icon:Show()
                end

                if border then
                    border:Show();
                end
                name:SetPoint("TOP", border, "BOTTOM", 0, -20)
                cost:Show()
                if badge then
                    badge:Show();
                    discount:Show();
                    badge.badgeLabel:Show();
                end
                -- Hide Info Text
                infoText:Hide();
            end
        end)

        frame:SetScript("OnClick", function()
            if ModernShopSelectedEntryFrame and ModernShopSelectedEntryFrame.selectHighlight then
                ModernShopSelectedEntryFrame.selectHighlight:Hide()
            end
            ModernShopSelectedEntryFrame = frame
            frame.selectHighlight:Show()
            ModernShopSelectedEntry = entry

            ModernShopBuyButton:Show()
            ModernShop_UpdateBuyButtonVisual("normal")

            PlaySound(852)
        end)

        frame:Show()
    end

    -- PAGE CONTROLS
    if ModernShopTotalPages > 1 then
        ModernShopPageText:SetText("Page " .. ModernShopCurrentPage .. " / " .. ModernShopTotalPages)
        ModernShopPageText:Show()
        ModernShopPagePrev:Show()
        ModernShopPageNext:Show()
    else
        ModernShopPageText:Hide()
        ModernShopPagePrev:Hide()
        ModernShopPageNext:Hide()
    end

    ModernShopServicesFrame:Show()
end

function ModernShop_LoadFeaturedTab()
    ModernShop_ClearCategoryFrame()
    if ModernShopPacksBuyButton then ModernShopPacksBuyButton:Hide() end -- Hide packs buy button if it was visible

    ModernShop_EnsureCategoryFrame()

    -- Cleanup
    if ModernShopFeaturedFrame then
        ModernShopFeaturedFrame:Hide()
        ModernShopFeaturedFrame:SetParent(nil)
    end

    ModernShopFeaturedFrame = CreateFrame("Frame", "ModernShopFeaturedFrame", ModernShopCategoryFrame)
    ModernShopFeaturedFrame:SetSize(692, 541)
    ModernShopFeaturedFrame:SetPoint("CENTER", ModernShopFrame, "CENTER", 100, -24)

    -- Background Texture
    local bg = ModernShopFeaturedFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface/Shop/shopbundles1107cnpandateleportpet")
    bg:SetTexCoord(0.00048828, 0.55517578, 0.00097656, 0.90527344)
    bg:SetAllPoints()

    -- Magnifying Glass Button / Preview
    local magnify = CreateFrame("Button", nil, ModernShopFeaturedFrame)
    magnify:SetSize(32, 32)
    magnify:SetPoint("TOPLEFT", ModernShopFeaturedFrame, "TOPLEFT", 10, -10)

    local icon = magnify:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface/Shop/store-main")
    icon:SetTexCoord(0.33154297, 0.35888672, 0.72412109, 0.75341797)
    icon:SetAllPoints()
    magnify:SetNormalTexture(icon)

    magnify:SetScript("OnClick", function()
        DEFAULT_CHAT_FRAME:AddMessage("Previewing Guardian Pack...")

        PlaySound(852)
    end)

    -- Title
    local title = ModernShopFeaturedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetText("The Panda Pet")
    title:SetFont("Fonts\\FRIZQT__.TTF", 24)
    title:SetPoint("CENTER", ModernShopFeaturedFrame, "CENTER", 0, -50)

    -- Subtitle
    local subtitle = ModernShopFeaturedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetText("Get this unique pet now !")
    subtitle:SetFont("Fonts\\FRIZQT__.TTF", 16)
    subtitle:SetPoint("CENTER", title, "CENTER", 0, -40)

    -- Limited time text
    local limitedTimeText = ModernShopFeaturedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    limitedTimeText:SetText("|cFF00fff7 This pet will only be available from now till then !!")
    limitedTimeText:SetFont("Fonts\\FRIZQT__.TTF", 12)
    limitedTimeText:SetPoint("CENTER", subtitle, "CENTER", 0, -60)

    ModernShopBuyButton:Show()
    ModernShopBuyButton:SetFrameLevel(10000)
    ModernShopBuyButton:ClearAllPoints()
    ModernShopBuyButton:SetPoint("CENTER", title, "CENTER", 25, -180)
    ModernShop_UpdateBuyButtonVisual("normal")

    ModernShopFeaturedFrame:Show()
end

function ModernShop_LoadSpecialTab()
    ModernShop_ClearCategoryFrame()
    if ModernShopPacksBuyButton then ModernShopPacksBuyButton:Hide() end -- Hide packs buy button if it was visible

    ModernShop_EnsureCategoryFrame()

    -- Cleanup
    if ModernShopSpecialFrame then
        ModernShopSpecialFrame:Hide()
        ModernShopSpecialFrame:SetParent(nil)
    end

    ModernShopSpecialFrame = CreateFrame("Frame", "ModernShopSpecialFrame", ModernShopCategoryFrame)
    ModernShopSpecialFrame:SetSize(692, 541)
    ModernShopSpecialFrame:SetPoint("CENTER", ModernShopFrame, "CENTER", 100, -24)

    -- Background Texture
    local bg = ModernShopSpecialFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface/Shop/store-main")
    bg:SetTexCoord(0.00537109, 0.55810547, 0.00537109, 0.45556641)
    bg:SetAllPoints()

    -- Wow Token Circle border
    local iconborder = ModernShopSpecialFrame:CreateTexture(nil, "ARTWORK")
    iconborder:SetTexture("Interface/Shop/store-splash")
    iconborder:SetTexCoord(0.56689453, 0.78173828, 0.52001953, 0.74365234)
    iconborder:SetSize(150, 150)
    iconborder:SetPoint("CENTER", ModernShopSpecialFrame, "CENTER", -230, 80)

    -- Wow Token Icon
    local tokenicon = ModernShopSpecialFrame:CreateTexture(nil, "OVERLAY")
    tokenicon:SetTexture("Interface/Shop/uitokens2x")
    tokenicon:SetTexCoord(0.46240234, 0.55419922, 0.20019531, 0.38964844)
    tokenicon:SetSize(50, 50)
    tokenicon:SetPoint("CENTER", iconborder, "CENTER", 0, 2)

    -- Title
    local title = ModernShopSpecialFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetText("The WoW Token")
    title:SetFont("Fonts\\FRIZQT__.TTF", 36)
    title:SetPoint("TOP", ModernShopSpecialFrame, "TOP", 0, -50)

    -- Token Explanation
    local label = ModernShopSpecialFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", title, "TOP", 0, -100)
    label:SetWidth(300) -- limit width
    label:SetWordWrap(true)
    label:SetFont("Fonts\\FRIZQT__.TTF", 20)
    label:SetText(
        "|CFFf3dba1 The WoW Token can be sold on the auction house for gold. The auction buyer can then redeem it for 30 days of game time. This Token may not be traded or redeemed; it may only be listed for sale on the Auction House.")

    -- Auction Value
    local auctionValue = ModernShopSpecialFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    auctionValue:SetText("|CFFd3b05b Current Auction Value:")
    auctionValue:SetFont("Fonts\\FRIZQT__.TTF", 18)
    auctionValue:SetPoint("CENTER", label, "CENTER", -50, -150)

    -- Current Value
    local currentValue = ModernShopSpecialFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    currentValue:SetText("241563")
    currentValue:SetFont("Fonts\\FRIZQT__.TTF", 18)
    currentValue:SetPoint("LEFT", auctionValue, "RIGHT", 25, 0)

    local goldIcon = ModernShopSpecialFrame:CreateTexture(nil, "OVERLAY")
    goldIcon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    goldIcon:SetSize(16, 16)
    goldIcon:SetPoint("LEFT", currentValue, "RIGHT", 5, 0)

    -- Subject to change
    local subjectToChange = ModernShopSpecialFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subjectToChange:SetText("|CFFd3b05b (subject to change)")
    subjectToChange:SetFont("Fonts\\FRIZQT__.TTF", 18)
    subjectToChange:SetPoint("CENTER", auctionValue, "CENTER", 50, -20)

    ModernShopBuyButton:Show()
    ModernShopBuyButton:SetFrameLevel(10000)
    ModernShopBuyButton:ClearAllPoints()
    ModernShopBuyButton:SetPoint("CENTER", subjectToChange, "CENTER", 25, -100)
    ModernShop_UpdateBuyButtonVisual("normal")

    ModernShopSpecialFrame:Show()
end

function ModernShop_LoadPacksTab()
    ModernShop_ClearCategoryFrame()

    ModernShop_EnsureCategoryFrame()

    -- Important: update LastCategory!
    ModernShopLastCategoryID = 4
    ModernShopLastSubcategoryID = nil

    -- Cleanup previous frame
    if ModernShopPacksFrame then
        ModernShopPacksFrame:Hide()
        ModernShopPacksFrame:SetParent(nil)
    end

    ModernShopPacksFrame = CreateFrame("Frame", "ModernShopPacksFrame", ModernShopCategoryFrame)
    ModernShopPacksFrame:SetSize(692, 521)
    ModernShopPacksFrame:SetPoint("CENTER", ModernShopFrame, "CENTER", 100, -24)

    -- Reset
    if ModernShopSelectedEntryFrame and ModernShopSelectedEntryFrame.selectHighlight then
        ModernShopSelectedEntryFrame.selectHighlight:Hide()
    end
    ModernShopSelectedEntryFrame = nil
    ModernShopSelectedEntry = nil

    ModernShopBuyButton:Show()
    ModernShop_UpdateBuyButtonVisual("normal")

    -- Get pack data
    local pack = SHOP_PLACEHOLDER_DATA.packs[ModernShopCurrentPage] -- use current page

    if not pack then
        print("No pack found for page:", ModernShopCurrentPage)
        return
    end

    -- Background
    local background = ModernShopPacksFrame:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(pack.background)
    background:SetTexCoord(unpack(pack.texCoords))
    background:SetSize(692, 480)
    background:SetPoint("CENTER", ModernShopPacksFrame, "CENTER", 0, 30)

    -- Title
    local title = ModernShopPacksFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", ModernShopPacksFrame, "TOP", 0, -300)
    title:SetFont("Fonts\\FRIZQT__.TTF", 34)
    title:SetText(pack.name)

    -- Label (word wrapping)
    local label = ModernShopPacksFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetSize(400, 0) -- Width capped for wrapping
    label:SetPoint("TOP", title, "BOTTOM", 0, -20)
    label:SetFont("Fonts\\FRIZQT__.TTF", 16)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("TOP")
    label:SetText(pack.label)

    -- Add label with cost
    local costLabel = ModernShopPacksFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    costLabel:SetSize(100, 0) -- Width capped for wrapping
    costLabel:SetPoint("TOP", label, "BOTTOM", 0, -50)
    costLabel:SetFont("Fonts\\FRIZQT__.TTF", 16)
    costLabel:SetText(pack.price .. "$")

    -- Reposition buy button to look better
    ModernShopBuyButton:ClearAllPoints()
    ModernShopBuyButton:SetPoint("CENTER", title, "CENTER", 25, -190)
    --ModernShopBuyButton:SetFrameLevel(10000)

    -- Page controls
    ModernShopTotalPages = #SHOP_PLACEHOLDER_DATA.packs or 1
    if ModernShopTotalPages > 1 then
        ModernShopPageText:SetText("Page " .. ModernShopCurrentPage .. " / " .. ModernShopTotalPages)
        ModernShopPageText:Show()
        ModernShopPagePrev:Show()
        ModernShopPageNext:Show()
    else
        ModernShopPageText:Hide()
        ModernShopPagePrev:Hide()
        ModernShopPageNext:Hide()
    end

    ModernShopPacksFrame:Show()
end

function ModernShop_ShowToast(entry)
    if not entry then return end


    if entry.category_id == 1 then -- Services
        local texturePath = "Interface\\Icons\\spell_holy_devineaegis"
        ModernShopToastFrame.icon:SetTexture(texturePath)
        ModernShopToastFrame.name:SetPoint("TOPLEFT", ModernShopToastFrame.icon, "TOPRIGHT", 90, -2)
        ModernShopToastFrame.message:SetPoint("TOPLEFT", ModernShopToastFrame.name, "BOTTOMLEFT", -20, -4)
    elseif entry.category_id == 2 then -- Featured
        local texturePath = "Interface\\Icons\\inv_jewelcrafting_starofelune_01"
        ModernShopToastFrame.icon:SetTexture(texturePath)
    elseif entry.category_id == 3 then -- WoW Token
        local texturePath = "Interface\\Icons\\wow_token01"
        ModernShopToastFrame.icon:SetTexture(texturePath)
    elseif entry.category_id == 4 then -- Packs
        local texturePath = "Interface\\Icons\\inv_misc_bag_14"
        ModernShopToastFrame.icon:SetTexture(texturePath)
    elseif entry.category_id == 5 then -- Mounts
        local safeName = entry.name:gsub(" ", "_")
        local texturePath = "Interface/Shop/Mounts\\" .. safeName
        ModernShopToastFrame.icon:SetTexture(texturePath)
    elseif entry.category_id == 6 then -- Pets
        local safeName = entry.name:gsub(" ", "_")
        local texturePath = "Interface/Shop/Pets\\" .. safeName
        ModernShopToastFrame.icon:SetTexture(texturePath)
    elseif entry.category_id == 7 then -- Toys
        local texturePath = "Interface\\Icons\\inv_misc_toy_10"
        ModernShopToastFrame.icon:SetTexture(texturePath)
    elseif entry.category_id == 8 then -- Transmogs
        local texturePath = "Interface\\Icons\\inv_misc_toy_07"
        ModernShopToastFrame.icon:SetTexture(texturePath)
    end

    ModernShopToastFrame.name:SetText(entry.name or "Unknown Item")
    ModernShopToastFrame.message:SetText("Your item has been delivered.")

    ModernShopToastFrame:Show()
    ModernShopToastFrame:SetAlpha(1)
    PlaySound(18019)

    -- Setup fade timer
    ModernShopToastFrame.fadeTime = GetTime() + 3 -- show for 3 seconds
    ModernShopToastFrame:SetScript("OnUpdate", function(self)
        if ProjectEbonhold_IsClosing then self:SetScript("OnUpdate", nil) return end
        if not UIParent:IsShown() then return end
        if GetTime() >= self.fadeTime then
            local alpha = self:GetAlpha()
            if alpha > 0 then
                self:SetAlpha(alpha - 0.02)
            else
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end
    end)
end

function ModernShop_OpenPreview(entry)
    if not ModernShopPreviewFrame then return end
    ModernShopPreviewFrame:Show()
    ModernShopFrame:Hide() -- HIDE the shop!

    -- Hide models first
    ModernShopPreviewFrame.CreatureModel:Hide()
    ModernShopPreviewFrame.PlayerModel:Hide()

    if entry.creatureId then
        -- Mounts & Pets Preview
        ModernShopPreviewFrame.CreatureModel:Show()
        ModernShopPreviewFrame.CreatureModel:SetCreature(entry.creatureId)
    elseif entry.previewItems then
        -- Transmog Preview
        ModernShopPreviewFrame.PlayerModel:Show()
        ModernShopPreviewFrame.PlayerModel:SetUnit("player")
        for _, itemID in ipairs(entry.previewItems) do
            ModernShopPreviewFrame.PlayerModel:TryOn(itemID)
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("No preview available for this item.")
        ModernShopPreviewFrame:Hide()
        ModernShopFrame:Show() -- if error, reopen shop
    end
end

function ModernShop_ClearCategoryFrame()
    if ModernShopServicesFrame then
        ModernShopServicesFrame:Hide()
    end
    if ModernShopFeaturedFrame then
        ModernShopFeaturedFrame:Hide()
    end
    if ModernShopSpecialFrame then
        ModernShopSpecialFrame:Hide()
    end
    if ModernShopTransmogModel then
        ModernShopTransmogModel:Hide()
    end
    if ModernShopTransmogModel2 then
        ModernShopTransmogModel2:Hide()
    end
    if ModernShopPacksFrame then
        ModernShopPacksFrame:Hide()
    end
    if ModernShopEntryFrames then
        for _, frame in ipairs(ModernShopEntryFrames) do
            frame:Hide()
            frame:SetParent(nil)
        end
        wipe(ModernShopEntryFrames)
    end
end
