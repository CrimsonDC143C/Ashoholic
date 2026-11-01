local addonName, addon = ...

------------------------------------------------------------
-- Affix loot toast
--
-- A toast pops when an item the player just looted / created carries a V2 affix
-- (random property 10000+). Nothing else (plain loot, money, recipes) goes through
-- here. The toast says whether the affix is already owned, rank-aware like
-- ExtractionMgr::CanLearnAffix: an affix is "new" when the player knows no rank of
-- that family at or above the looted one. The affix list (family, rank, learned)
-- comes from ExtractionService (SEND_LEARNED_AFFIXES), the affix carried by the item
-- from the 8th field of its link, like the anvil UI does.
--
-- Visual kit: pretty_lootalert (s0h2x), trimmed to two looks - plain loot toast for
-- a known affix, legendary toast + sound for a new one. Frames are in affix_toast.xml.
--
-- Looting an affix does NOT learn it: only extracting the item at the Enchanted Anvil
-- does (ExtractionMgr::LearnAffix; the item is destroyed). Players read the old green
-- "New Affix!" as "unlocked", so the toast now says "not learned" with a hint line, the
-- first such toast runs a one-time tour, and every item tooltip carrying an affix the
-- player has not learned says so.
------------------------------------------------------------

AffixToast = AffixToast or {}

local ASSETS      = "Interface\\AddOns\\ProjectEbonhold\\assets\\loottoast\\"
local SOUND_NEW   = ASSETS .. "ui_legendary_item_toast.ogg"
local SOUND_KNOWN = ASSETS .. "ui_epicloot_toast_01.ogg"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local NUM_TOASTS    = 4      -- toasts shown at once (buttons declared in the xml)
local SHOW_INTERVAL = 0.3    -- seconds between two toasts leaving the queue
local TOAST_SPACING = 4      -- vertical gap between stacked toasts
local PLAY_SOUND    = true
local PLAY_ANIMS    = true

local LABEL_NEW   = "Affix not learned"
local HINT_NEW    = "Extract it: Enchanted Anvil, Dalaran"
local LABEL_KNOWN = "You receive"
local TOOLTIP_NOT_LEARNED = "Affix not learned: extract this item at the Enchanted Anvil in Dalaran (Northrend) to learn it."
local ROMAN = { "I", "II", "III", "IV", "V" }

-- Icon border cut from LootToastAtlas, by item quality
local LOOT_BORDER_BY_QUALITY = {
    [2] = { 0.34082, 0.397461, 0.53125, 0.644531 },     -- uncommon
    [3] = { 0.272461, 0.329102, 0.785156, 0.898438 },   -- rare
    [4] = { 0.34082, 0.397461, 0.882812, 0.996094 },    -- epic
    [5] = { 0.34082, 0.397461, 0.765625, 0.878906 },    -- legendary
    [6] = { 0.272461, 0.329102, 0.667969, 0.78125 },    -- artifact
    [7] = { 0.34082, 0.397461, 0.648438, 0.761719 },    -- heirloom
}

------------------------------------------------------------
-- Chat message parsing
------------------------------------------------------------

-- Only the messages about the player's own loot. Each global is "<prefix>%s..." ; we keep the
-- localized prefix and match on it, so no pattern building on translated text is needed.
local SELF_LOOT_GLOBALS = {
    "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
    "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
}
local selfLootPrefixes = {}
for _, name in ipairs(SELF_LOOT_GLOBALS) do
    local fmt = _G[name]
    local prefix = fmt and fmt:match("^(.-)%%s")
    -- an empty prefix would match everyone's loot lines ("%s receives loot: %s")
    if prefix and prefix ~= "" then
        selfLootPrefixes[prefix] = true
    end
end

local function IsSelfLootMessage(msg)
    for prefix in pairs(selfLootPrefixes) do
        if msg:find(prefix, 1, true) == 1 then
            return true
        end
    end
    return false
end

local function ExtractItemLink(msg)
    local link = msg:match("|c%x%x%x%x%x%x%x%x|Hitem:[-%d:]+|h%[.-%]|h|r")
    if not link then return nil end
    local count = tonumber(msg:match("|h|rx(%d+)")) or 1
    return link, count
end

-- The affix carried by an item link: its random property id (8th link field) is the
-- ItemRandomProperties id the server sent with the affix list.
-- (one pattern instead of strsplit: this runs on every item tooltip, on 7 tooltips)
local function FindAffixInLink(link)
    -- the 7th number after "item:" = the 8th ":" field of the full link
    local randomProp = link:match("item:%-?%d+:%-?%d+:%-?%d+:%-?%d+:%-?%d+:%-?%d+:(%-?%d+)")
    randomProp = randomProp and tonumber(randomProp)
    if not randomProp or randomProp <= 0 then return nil end
    local byEnchant = ExtractionService and ExtractionService.affixByEnchant
    return byEnchant and byEnchant[randomProp] or nil
end

-- Highest rank the player knows in a family (0 = none). Reads the service list and, as a
-- fresher fallback, the spellbook itself (the learn spell is a real known spell).
local function GetKnownRank(familyId)
    local best = 0
    local list = ExtractionService and ExtractionService.learnedAffixes or {}
    for _, affix in ipairs(list) do
        if affix.familyId == familyId then
            local known = affix.learned or (IsSpellKnown and IsSpellKnown(affix.id))
            if known and (affix.rank or 0) > best then
                best = affix.rank
            end
        end
    end
    return best
end

-- Every item tooltip: an affix the player has not learned (at that rank) says so
local function AddNotLearnedLine(tooltip)
    local _, link = tooltip:GetItem()
    if not link then return end
    local affix = FindAffixInLink(link)
    if not affix or GetKnownRank(affix.familyId) >= (affix.rank or 1) then return end
    tooltip:AddLine(TOOLTIP_NOT_LEARNED, 1, 0.5, 0.25, true)
    tooltip:Show()
end

for _, n in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                     "ShoppingTooltip3", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
    local tooltip = _G[n]
    if tooltip and tooltip.HookScript then
        tooltip:HookScript("OnTooltipSetItem", AddNotLearnedLine)
    end
end

------------------------------------------------------------
-- First "not learned" toast: one-time tour
------------------------------------------------------------

-- The toast it points at stays on screen (holdForTour, see the xml) until the tour ends
local tourToast

local affixTour = ProjectEbonhold.GuidedTour.Create({
    dbKey = "seenAffixLootTour",
    steps = {
        {
            title = "Affix not learned yet",
            text = "This item carries an affix. While you wear the item, you benefit from it, " ..
                "but looting it does |cffff8040not|r teach it to you.",
            zone = function() return tourToast end,
            boxAnchor = { "RIGHT", "LEFT", -14, 0 },
        },
        {
            title = "Learn it at the Enchanted Anvil",
            text = "Go to the |cffffd700Enchanted Anvil in Dalaran|r (Northrend), or open it anywhere with " ..
                "the |cffffd700Portable Affix-Anvil|r of your Toolbelt once unlocked. Extract the item there " ..
                "to learn its affix for good, on all your characters. Extraction |cffff4040destroys the item|r: " ..
                "the anvil shows its cost first.",
            zone = function() return tourToast end,
            boxAnchor = { "RIGHT", "LEFT", -14, 0 },
        },
        {
            title = "Engrave it",
            text = "Once learned, an affix can be engraved at the anvil onto other items that " ..
                "can carry it.",
            zone = function() return tourToast end,
            boxAnchor = { "RIGHT", "LEFT", -14, 0 },
        },
    },
    onEnd = function()
        local toast = tourToast
        tourToast = nil
        if toast then
            toast.holdForTour = nil
            if toast:IsShown() then toast.waitAndAnimOut:Play() end
        end
    end,
})

local function MaybeStartAffixTour(toast)
    if tourToast or affixTour:HasSeen() then return end
    tourToast = toast
    toast.holdForTour = true
    if not affixTour:MaybeStart() then
        tourToast = nil
        toast.holdForTour = nil
    end
end

------------------------------------------------------------
-- Queue
------------------------------------------------------------

local alertQueue  = {}
local alertButtons = {}

local function QueueToast(link, count, affix)
    local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
    if not name then
        name = link:match("%[(.-)%]")
        quality = 1
    end

    local knownRank = GetKnownRank(affix.familyId)
    local rank = affix.rank or 1
    table.insert(alertQueue, {
        link      = link,
        name      = name,
        quality   = quality or 1,
        texture   = texture or FALLBACK_ICON,
        count     = count,
        affixName = affix.name,
        rank      = rank,
        knownRank = knownRank,
        isNew     = knownRank < rank,
    })
    if EbonholdAffixToastFrame then EbonholdAffixToastFrame:Show() end
end

local function TakeFreeButton()
    if #alertQueue == 0 then return nil end
    for i = 1, NUM_TOASTS do
        local button = alertButtons[i]
        if button and not button:IsShown() then
            button.data = table.remove(alertQueue, 1)
            return button
        end
    end
    return nil
end

local function AdjustAnchors()
    local anchor = DungeonCompletionAlertFrame1
    local previous
    for i = 1, NUM_TOASTS do
        local button = alertButtons[i]
        if button then
            button:ClearAllPoints()
            if button:IsShown() then
                if not previous then
                    if anchor and anchor:IsShown() then
                        button:SetPoint("BOTTOM", anchor, "TOP", 0, TOAST_SPACING)
                    elseif anchor then
                        button:SetPoint("CENTER", anchor, "CENTER", 0, 0)
                    else
                        button:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 128)
                    end
                else
                    button:SetPoint("BOTTOM", previous, "TOP", 0, TOAST_SPACING)
                end
                previous = button
            end
        end
    end
end

------------------------------------------------------------
-- Frame handlers (referenced from affix_toast.xml)
------------------------------------------------------------

function EbonholdAffixToastFrame_OnLoad(self)
    self.updateTime = SHOW_INTERVAL
    self:RegisterEvent("CHAT_MSG_LOOT")
end

function EbonholdAffixToastFrame_OnEvent(self, event, ...)
    if event ~= "CHAT_MSG_LOOT" then return end
    local msg = ...
    if not msg or not IsSelfLootMessage(msg) then return end

    local link, count = ExtractItemLink(msg)
    if not link then return end

    local affix = FindAffixInLink(link)
    if not affix then return end

    QueueToast(link, count, affix)
end

function EbonholdAffixToastFrame_OnUpdate(self, elapsed)
    self.updateTime = self.updateTime - elapsed
    if self.updateTime > 0 then return end
    self.updateTime = SHOW_INTERVAL

    local button = TakeFreeButton()
    if button then
        button:ClearAllPoints()
        button:Show()
        button.animIn:Play()
        AdjustAnchors()
    end
    -- nothing left to show: stop ticking until QueueToast shows the frame again
    -- (the toasts are parented to UIParent, not to this frame)
    if #alertQueue == 0 then self:Hide() end
end

function EbonholdAffixToast_OnLoad(self)
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    table.insert(alertButtons, self)
end

function EbonholdAffixToast_OnShow(self)
    local data = self.data
    if not data then
        self:Hide()
        return
    end

    local isNew = data.isNew
    local qualityColor = ITEM_QUALITY_COLORS[data.quality]

    self.Icon:SetTexture(data.texture)
    self.Count:SetText(data.count > 1 and data.count or " ")
    self.ItemName:SetText(data.name)
    if qualityColor then
        self.ItemName:SetTextColor(qualityColor.r, qualityColor.g, qualityColor.b)
    else
        self.ItemName:SetTextColor(1, 1, 1)
    end
    local border = LOOT_BORDER_BY_QUALITY[data.quality] or LOOT_BORDER_BY_QUALITY[2]
    self.IconBorder:SetTexCoord(unpack(border))

    if isNew then
        self.Label:SetText(LABEL_NEW)
        self.Label:SetTextColor(1, 0.5, 0.25)
        if data.knownRank > 0 then
            self.AffixName:SetFormattedText("%s |cff9d9d9d(you know rank %s)|r", data.affixName, ROMAN[data.knownRank] or data.knownRank)
        else
            self.AffixName:SetText(data.affixName)
        end
        self.AffixName:SetTextColor(1, 0.82, 0)
    else
        self.Label:SetText(LABEL_KNOWN)
        self.Label:SetTextColor(1, 0.82, 0)
        if data.knownRank > data.rank then
            self.AffixName:SetFormattedText("%s - rank %s known", data.affixName, ROMAN[data.knownRank] or data.knownRank)
        else
            self.AffixName:SetFormattedText("%s - already known", data.affixName)
        end
        self.AffixName:SetTextColor(0.62, 0.62, 0.62)
    end

    -- textures have no SetShown on 3.3.5
    if isNew then
        self.Background:Hide()
        self.LegendaryBackground:Show()
        self.Hint:SetText(HINT_NEW)
        self.Hint:SetTextColor(0.9, 0.9, 0.9)
        self.Hint:Show()
    else
        self.Background:Show()
        self.LegendaryBackground:Hide()
        self.Hint:Hide()
    end

    if PLAY_SOUND then
        PlaySoundFile(isNew and SOUND_NEW or SOUND_KNOWN)
    end
    if PLAY_ANIMS then
        if isNew then
            self.legendaryGlow.animIn:Play()
            self.legendaryShine.animIn:Play()
        else
            self.glow.animIn:Play()
            self.shine.animIn:Play()
        end
    end

    if isNew then
        MaybeStartAffixTour(self)
    end
end

function EbonholdAffixToast_OnHide(self)
    -- dismissed mid-tour (right click): pause it, it comes back with the next one
    if tourToast == self and affixTour:IsActive() then
        affixTour:Stop(false)
    end
    self.holdForTour = nil
    self.animIn:Stop()
    self.waitAndAnimOut:Stop()
    self.legendaryGlow.animIn:Stop()
    self.legendaryShine.animIn:Stop()
    self.glow.animIn:Stop()
    self.shine.animIn:Stop()
    self.data = nil
    AdjustAnchors()
end

function EbonholdAffixToast_OnClick(self, button)
    if button == "RightButton" then
        self:Hide()
    elseif self.data and self.data.link then
        HandleModifiedItemClick(self.data.link)
    end
end

function EbonholdAffixToast_OnEnter(self)
    local data = self.data
    if not data then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -14, -6)
    -- the "not learned" line comes from the OnTooltipSetItem hook above
    GameTooltip:SetHyperlink(data.link)
    if not data.isNew then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Affix already known.", 0.62, 0.62, 0.62, true)
    end
    GameTooltip:Show()
end

-- Manual check without waiting for a drop: /affixtoast <itemlink>
SLASH_EBONHOLDAFFIXTOAST1 = "/affixtoast"
SlashCmdList["EBONHOLDAFFIXTOAST"] = function(text)
    local link = text and text:match("|c%x%x%x%x%x%x%x%x|Hitem:[-%d:]+|h%[.-%]|h|r")
    if not link then
        DEFAULT_CHAT_FRAME:AddMessage("Usage: /affixtoast <item link>")
        return
    end
    local affix = FindAffixInLink(link)
    if not affix then
        DEFAULT_CHAT_FRAME:AddMessage("No affix on " .. link)
        return
    end
    QueueToast(link, 1, affix)
end
