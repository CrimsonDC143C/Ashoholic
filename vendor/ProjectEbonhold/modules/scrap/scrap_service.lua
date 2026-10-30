local addonName, addon = ...

local CHAT_PREFIX = "|cff00ff00[Project Ebonhold]|r "

-- ── Saved item lists (account-wide) ──────────────────────────────────────────
-- neverSell: junk items the player protected (Alt-click)
-- alwaysSell: non-junk items the player marked for automatic sale (Alt-click)
local function GetScrapDB()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.scrap = ProjectEbonholdDB.scrap or {}
    ProjectEbonholdDB.scrap.neverSell = ProjectEbonholdDB.scrap.neverSell or {}
    ProjectEbonholdDB.scrap.alwaysSell = ProjectEbonholdDB.scrap.alwaysSell or {}
    return ProjectEbonholdDB.scrap
end

local function GetSetting(key)
    if ProjectEbonholdOptionsService then
        return ProjectEbonholdOptionsService:GetSetting(key)
    end
end

local function GetItemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function FormatMoney(copperAmount)
    local gold = math.floor(copperAmount / 10000)
    local silver = math.floor((copperAmount % 10000) / 100)
    local copper = copperAmount % 100

    local moneyString = ""
    if gold > 0 then
        moneyString = gold .. "|cffffd700g|r "
    end
    if silver > 0 or gold > 0 then
        moneyString = moneyString .. silver .. "|cffc7c7c7s|r "
    end
    moneyString = moneyString .. copper .. "|cffeda55fc|r"
    return moneyString
end

-- ── Selling rules ────────────────────────────────────────────────────────────
local QUALITY_FLAG = {
    [1] = "sellQualityCommon",
    [2] = "sellQualityUncommon",
    [3] = "sellQualityRare",
}

-- Localized item class name -> setting key, built from GetAuctionItemClasses
-- so the mapping works on any client locale.
local TYPE_FLAG = {}
do
    local weapon, armor, _, consumable, glyph, tradeGoods, _, _, recipe, gem, misc = GetAuctionItemClasses()
    TYPE_FLAG[weapon or "Weapon"]           = "sellTypeWeapon"
    TYPE_FLAG[armor or "Armor"]             = "sellTypeArmor"
    TYPE_FLAG[consumable or "Consumable"]   = "sellTypeConsumable"
    TYPE_FLAG[tradeGoods or "Trade Goods"]  = "sellTypeTradeGoods"
    TYPE_FLAG[recipe or "Recipe"]           = "sellTypeRecipe"
    TYPE_FLAG[gem or "Gem"]                 = "sellTypeGem"
    TYPE_FLAG[glyph or "Glyph"]             = "sellTypeGlyph"
    TYPE_FLAG[misc or "Miscellaneous"]      = "sellTypeMisc"
end

local function SellsPoorQuality()
    local sellPoor = GetSetting("sellQualityPoor")
    if sellPoor == nil then sellPoor = true end
    return sellPoor
end

-- Non-junk items are sold when both their quality (white/green/blue) and
-- their item type (weapon, armor, consumable, ...) are enabled.
local function MatchesSellFilters(link)
    local _, _, quality, _, _, itemType = GetItemInfo(link)

    local qualityFlag = quality and QUALITY_FLAG[quality]
    if not qualityFlag or not GetSetting(qualityFlag) then return false end

    local typeFlag = itemType and TYPE_FLAG[itemType]
    if not typeFlag or not GetSetting(typeFlag) then return false end

    return true
end

-- Returns the list of {bag, slot, link, value} the current rules would sell.
-- Items without cached item info or without a vendor price are never included,
-- so UseContainerItem can never accidentally "use" an item instead of selling it.
local function GetSellableItems()
    local db = GetScrapDB()
    local items = {}

    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            local itemID = GetItemID(link)
            if itemID and not db.neverSell[itemID] then
                local quality = select(3, GetItemInfo(link))
                local vendorPrice = select(11, GetItemInfo(link))

                if vendorPrice and vendorPrice > 0 then
                    local shouldSell = db.alwaysSell[itemID]
                        or GetSetting("sellEverything")
                        or (quality == 0 and SellsPoorQuality())
                        or MatchesSellFilters(link)

                    if shouldSell then
                        local _, count = GetContainerItemInfo(bag, slot)
                        table.insert(items, {
                            bag = bag,
                            slot = slot,
                            link = link,
                            value = vendorPrice * (count or 1),
                        })
                    end
                end
            end
        end
    end

    return items
end

local function GetSellableValue()
    local total = 0
    for _, item in ipairs(GetSellableItems()) do
        total = total + item.value
    end
    return total
end

-- ── Selling ──────────────────────────────────────────────────────────────────
-- Selling is always performed by the server. The client sends its filters with
-- the request; the server evaluates them against its own item templates:
--   body = ""    -> no rules, legacy behavior (server sells all poor items)
--   body = "q:15|t:99981|all:0|never:123,456|always:789"
--     q      bitmask of qualities to sell: 1=Poor, 2=Common, 4=Uncommon, 8=Rare
--     t      bitmask of item classes to sell (1 << ITEM_CLASS id), applied to
--            non-poor qualities only
--     all    1 = sell everything sellable (except `never`), 0 = use q/t filters
--     never  itemIDs the player protected (never sell, even poor/all)
--     always itemIDs the player marked to always sell (bypasses q/t)
-- A server that does not parse the body keeps its legacy behavior.
local QUALITY_BIT = {
    sellQualityPoor     = 1,
    sellQualityCommon   = 2,
    sellQualityUncommon = 4,
    sellQualityRare     = 8,
}

-- Setting key -> ITEM_CLASS id (3.3.5): Consumable=0, Weapon=2, Gem=3, Armor=4,
-- Trade Goods=7, Recipe=9, Miscellaneous=15, Glyph=16
local TYPE_CLASS_ID = {
    sellTypeConsumable = 0,
    sellTypeWeapon     = 2,
    sellTypeGem        = 3,
    sellTypeArmor      = 4,
    sellTypeTradeGoods = 7,
    sellTypeRecipe     = 9,
    sellTypeMisc       = 15,
    sellTypeGlyph      = 16,
}

local function BuildSellRulesBody()
    if not ProjectEbonholdOptionsService then return "" end

    local q = 0
    for key, bit in pairs(QUALITY_BIT) do
        if GetSetting(key) then q = q + bit end
    end

    local t = 0
    for key, classID in pairs(TYPE_CLASS_ID) do
        if GetSetting(key) then t = t + 2 ^ classID end
    end

    local db = GetScrapDB()
    local never, always = {}, {}
    for id in pairs(db.neverSell) do table.insert(never, id) end
    for id in pairs(db.alwaysSell) do table.insert(always, id) end
    table.sort(never)
    table.sort(always)

    return string.format("q:%d|t:%d|all:%d|never:%s|always:%s",
        q, t, GetSetting("sellEverything") and 1 or 0,
        table.concat(never, ","), table.concat(always, ","))
end

local function SellJunk()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SELL_JUNK_ITEMS, BuildSellRulesBody())
end

-- ── Alt-click on bag items: toggle protect / always-sell ────────────────────
local function ToggleItemRule(link)
    local itemID = GetItemID(link)
    if not itemID then return end

    local quality = select(3, GetItemInfo(link))
    if not quality then return end

    local db = GetScrapDB()

    if quality == 0 then
        db.neverSell[itemID] = not db.neverSell[itemID] or nil
        if DEFAULT_CHAT_FRAME then
            if db.neverSell[itemID] then
                DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. link .. " is now |cff00ff00protected|r and will never be sold.")
            else
                DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. link .. " is no longer protected.")
            end
        end
    elseif quality <= 3 then
        db.alwaysSell[itemID] = not db.alwaysSell[itemID] or nil
        if DEFAULT_CHAT_FRAME then
            if db.alwaysSell[itemID] then
                DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. link .. " will now |cffff5555always be sold|r with your junk.")
            else
                DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. link .. " removed from the always-sell list.")
            end
        end
    else
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Epic and higher quality items cannot be marked for automatic sale.")
        end
    end

    if ProjectEbonholdScrapButton and MerchantFrame and MerchantFrame:IsShown() then
        ProjectEbonholdScrapButton:UpdateState()
    end
end

if type(ContainerFrameItemButton_OnModifiedClick) == "function" then
    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
        if button ~= "LeftButton" or not IsAltKeyDown() then return end
        local bag = self:GetParent():GetID()
        local slot = self:GetID()
        local link = GetContainerItemLink(bag, slot)
        if link then
            ToggleItemRule(link)
        end
    end)
end

-- ── Tooltip status line for marked items ─────────────────────────────────────
GameTooltip:HookScript("OnTooltipSetItem", function(self)
    local _, link = self:GetItem()
    local itemID = GetItemID(link)
    if not itemID then return end

    local db = GetScrapDB()
    if db.neverSell[itemID] then
        self:AddLine("Protected: never sold as junk (Alt-click to unmark)", 0.1, 1, 0.1)
        self:Show()
    elseif db.alwaysSell[itemID] then
        self:AddLine("Always sold with junk (Alt-click to unmark)", 1, 0.35, 0.35)
        self:Show()
    end
end)

SLASH_sellJunk1 = "/sell_junk"
SlashCmdList["sellJunk"] = function(msg)
    SellJunk()
end


ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_JUNK_SOLD, function(body)
    if ProjectEbonholdScrapButton then
        ProjectEbonholdScrapButton:UpdateState()
    end
end)


_G.ScrapService = {
    SellJunk = SellJunk,
    GetSellableItems = GetSellableItems,
    GetSellableValue = GetSellableValue,
    ToggleItemRule = ToggleItemRule,
}
