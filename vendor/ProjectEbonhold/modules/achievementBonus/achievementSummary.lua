-- Achievement window, Summary page.
--
-- Blizzard draws its eight "Progress Overview" bars on stock category ids (General, Quests,
-- Exploration, Player vs. Player, Dungeons & Raids, Professions, Reputation, World Events).
-- Ashendor's Achievement_Category.dbc only kept Exploration of them, so the other seven drew as
-- nameless 0/0 bars. They now show the Ashendor root tabs, and "Achievements Earned" counts the
-- same tabs plus Introduction and Exploration: Legacy (the old realm's achievements, never
-- completable), Feats of Strength and Realm First no longer swell the total.
--
-- Category ids are tools/achievements/catalog.py CAT[...] in the server repo. A category the
-- client does not know (older patch-6) is skipped, never shown as a blank bar.

local SUMMARY_CATEGORIES = {
    15100, -- The Journey
    15110, -- Torment
    15160, -- Dungeons & Raids
    15170, -- Prestige
    15180, -- Echoes
    15190, -- Trees
    15210, -- The Forge
    15220, -- Collection
}

local TOTAL_CATEGORIES = {
    15090, -- Introduction
    15100, 15110, 15160, 15170, 15180, 15190, 15210, 15220,
    97,    -- Exploration (stock tab, kept)
}

local function categoryExists(id)
    return GetCategoryInfo and GetCategoryInfo(id) ~= nil
end

-- Achievements and completed ones in a category and all its sub-categories.
local function countCategory(id)
    if AchievementFrame_GetCategoryTotalNumAchievements then
        local ok, total, completed = pcall(AchievementFrame_GetCategoryTotalNumAchievements, id, true)
        if ok and total then return total, completed or 0 end
    end
    local total, completed = GetCategoryNumAchievements(id)
    return total or 0, completed or 0
end

local function remapBars()
    local list = {}
    for _, id in ipairs(SUMMARY_CATEGORIES) do
        if categoryExists(id) then list[#list + 1] = id end
    end

    -- The table is read by the stock OnLoad; the frames already ran it, so they are fixed below too.
    if ACHIEVEMENTUI_SUMMARYCATEGORIES then
        for i = #ACHIEVEMENTUI_SUMMARYCATEGORIES, 1, -1 do ACHIEVEMENTUI_SUMMARYCATEGORIES[i] = nil end
        for i, id in ipairs(list) do ACHIEVEMENTUI_SUMMARYCATEGORIES[i] = id end
    end

    for i = 1, 8 do
        local name = "AchievementFrameSummaryCategoriesCategory" .. i
        local bar = _G[name]
        if bar then
            local id = list[i]
            if id then
                bar:SetID(id)
                local label = bar.label or _G[name .. "Label"]
                if label then label:SetText((GetCategoryInfo(id))) end
                local onShow = bar:GetScript("OnShow")
                if onShow and bar:IsVisible() then onShow(bar) end
                bar:Show()
            else
                bar:Hide()
            end
        end
    end
end

local function updateTotal()
    local bar = AchievementFrameSummaryCategoriesStatusBar
    if not bar then return end
    local total, completed = 0, 0
    for _, id in ipairs(TOTAL_CATEGORIES) do
        if categoryExists(id) then
            local t, c = countCategory(id)
            total, completed = total + t, completed + c
        end
    end
    bar:SetMinMaxValues(0, math.max(total, 1))
    bar:SetValue(completed)
    local text = _G["AchievementFrameSummaryCategoriesStatusBarText"]
    if text then text:SetText(completed .. "/" .. total) end
end

local function install()
    if not AchievementFrameSummary then return false end
    pcall(remapBars)
    if AchievementFrameSummaryCategoriesStatusBar_Update then
        AchievementFrameSummaryCategoriesStatusBar_Update = function() pcall(updateTotal) end
    end
    pcall(updateTotal)
    return true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, name)
    if name == "Blizzard_AchievementUI" and install() then
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
if IsAddOnLoaded and IsAddOnLoaded("Blizzard_AchievementUI") and install() then
    frame:UnregisterEvent("ADDON_LOADED")
end
