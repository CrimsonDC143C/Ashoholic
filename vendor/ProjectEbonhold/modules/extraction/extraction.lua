local addonName, addon = ...

ExtractionUI = ExtractionUI or {}

------------------------------------------------------------
-- Enchanted Anvil window (owner's pick, 2026-11-01: retail's Item Upgrade)
--   One slot: click it to choose an item (equipped or in the bags), or drop one
--   on it. A dropdown picks the affix to engrave, CURRENT / AFTER side by side,
--   Extract and Engrave under them. Echo Journal frame. Tabs: Anvil / Affix Book.
--   Engraving works straight on equipped items (server bag 255, slot 0-18):
--   ExtractionMgr::TryApplyAffix swaps the passive on the spot. Extraction
--   destroys the item: bag items only (the server refuses equipped ones too).
------------------------------------------------------------

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function FormatCopperSmall(copperAmount)
    if not copperAmount or copperAmount == 0 then return GetCoinTextureString(0, 10) end
    return GetCoinTextureString(copperAmount, 10)
end

-- 8th field of an item link: its random property id (ItemRandomProperties, negative for a suffix)
local function LinkRandomProperty(link)
    if not link then return 0 end
    local randomProp = select(8, strsplit(":", link))   -- one value only: tonumber(a, b) reads b as a base
    return randomProp and tonumber(randomProp) or 0
end

-- The affix carried by an item link: its random property id IS the affix's enchantId.
local function FindItemAffix(link)
    local randomProp = LinkRandomProperty(link)
    if randomProp <= 0 then return nil end
    return ExtractionService.affixByEnchant and ExtractionService.affixByEnchant[randomProp] or nil
end

-- A blizzlike random property ("...of the Bear"): the server never engraves over it
local function HasForeignRandomProperty(link)
    return LinkRandomProperty(link) ~= 0 and FindItemAffix(link) == nil
end

------------------------------------------------------------
-- Slot rules (mirror of world.affix_slot_category - the server enforces them)
------------------------------------------------------------
local CATEGORY_OFF, CATEGORY_DEF, CATEGORY_RES, CATEGORY_UTI, CATEGORY_MOB = 1, 2, 3, 4, 5
local SLOT_CATEGORIES = {
    INVTYPE_HEAD           = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_SHOULDER       = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_CHEST          = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_ROBE           = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_LEGS           = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_HAND           = { [CATEGORY_OFF] = true, [CATEGORY_UTI] = true },
    INVTYPE_TRINKET        = { [CATEGORY_OFF] = true, [CATEGORY_DEF] = true, [CATEGORY_RES] = true, [CATEGORY_UTI] = true, [CATEGORY_MOB] = true },
    INVTYPE_FINGER         = { [CATEGORY_OFF] = true, [CATEGORY_RES] = true },
    INVTYPE_NECK           = { [CATEGORY_OFF] = true, [CATEGORY_RES] = true },
    INVTYPE_CLOAK          = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_WRIST          = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_WAIST          = { [CATEGORY_DEF] = true, [CATEGORY_UTI] = true },
    INVTYPE_FEET           = { [CATEGORY_DEF] = true, [CATEGORY_MOB] = true },
    INVTYPE_WEAPON         = { [CATEGORY_OFF] = true },
    INVTYPE_WEAPONMAINHAND = { [CATEGORY_OFF] = true },
    INVTYPE_WEAPONOFFHAND  = { [CATEGORY_OFF] = true },
    INVTYPE_2HWEAPON       = { [CATEGORY_OFF] = true },
    INVTYPE_SHIELD         = { [CATEGORY_OFF] = true },
    INVTYPE_HOLDABLE       = { [CATEGORY_OFF] = true },
    -- no ranged weapon (bow, gun, crossbow, thrown, wand) carries an affix (owner, 2026-11-02)
}
local WAND_SUBTYPE = "Wands"

-- Human labels for the slot list shown in the affix tooltip; every weapon-type
-- equipLoc collapses into one "Weapons" entry so the line stays short.
local SLOT_LABELS = {
    INVTYPE_HEAD = "Head", INVTYPE_SHOULDER = "Shoulders", INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest",
    INVTYPE_LEGS = "Legs", INVTYPE_HAND = "Hands", INVTYPE_TRINKET = "Trinkets", INVTYPE_FINGER = "Rings",
    INVTYPE_NECK = "Neck", INVTYPE_CLOAK = "Back", INVTYPE_WRIST = "Wrists", INVTYPE_WAIST = "Waist",
    INVTYPE_FEET = "Feet",
    INVTYPE_WEAPON = "Weapons", INVTYPE_WEAPONMAINHAND = "Weapons", INVTYPE_WEAPONOFFHAND = "Weapons",
    INVTYPE_2HWEAPON = "Weapons", INVTYPE_SHIELD = "Weapons", INVTYPE_HOLDABLE = "Weapons",
    INVTYPE_RANGED = "Weapons", INVTYPE_RANGEDRIGHT = "Weapons", INVTYPE_THROWN = "Weapons",
}
local SLOT_LABEL_ORDER = { "Head", "Neck", "Shoulders", "Back", "Chest", "Wrists", "Hands", "Waist", "Legs", "Feet",
                           "Rings", "Trinkets", "Weapons" }

-- category -> "Head, Chest, ..." built once from SLOT_CATEGORIES
local CATEGORY_SLOT_TEXT = {}
for cat = CATEGORY_OFF, CATEGORY_MOB do
    local seen, parts = {}, {}
    for equipLoc, cats in pairs(SLOT_CATEGORIES) do
        if cats[cat] then seen[SLOT_LABELS[equipLoc]] = true end
    end
    for _, label in ipairs(SLOT_LABEL_ORDER) do
        if seen[label] then parts[#parts + 1] = label end
    end
    CATEGORY_SLOT_TEXT[cat] = table.concat(parts, ", ")
end

-- Returns the category set an item link may carry (nil = no affix on this slot)
local function GetItemAffixRules(link)
    if not link then return nil end
    local _, _, quality, _, _, _, subType, _, equipLoc = GetItemInfo(link)
    if not equipLoc or (quality or 0) <= 2 then return nil end
    if subType == WAND_SUBTYPE then return nil end
    return SLOT_CATEGORIES[equipLoc]
end

-- classMask bit of the player's class (1 << (classId - 1), as in world.affixes.class_mask)
local CLASS_IDS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}
local function IsForPlayerClass(classMask)
    if not classMask or classMask == 0 then return true end
    local classId = CLASS_IDS[select(2, UnitClass("player"))]
    return classId ~= nil and bit.band(classMask, bit.lshift(1, classId - 1)) ~= 0
end

local CATEGORY_ORDER  = { CATEGORY_OFF, CATEGORY_DEF, CATEGORY_RES, CATEGORY_UTI, CATEGORY_MOB }
local CATEGORY_COLORS = {
    [CATEGORY_OFF] = { 1.00, 0.36, 0.36, hex = "ff5c5c" },
    [CATEGORY_DEF] = { 0.36, 0.61, 1.00, hex = "5c9cff" },
    [CATEGORY_RES] = { 0.36, 1.00, 0.54, hex = "5cff8a" },
    [CATEGORY_UTI] = { 1.00, 0.83, 0.36, hex = "ffd45c" },
    [CATEGORY_MOB] = { 0.36, 0.94, 1.00, hex = "5cf0ff" },
}
local CATEGORY_ICONS = {
    [CATEGORY_OFF] = "Interface\\Icons\\Ability_Warrior_OffensiveStance",
    [CATEGORY_DEF] = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    [CATEGORY_RES] = "Interface\\Icons\\INV_Elemental_Mote_Mana",
    [CATEGORY_UTI] = "Interface\\Icons\\INV_Misc_Gear_01",
    [CATEGORY_MOB] = "Interface\\Icons\\Ability_Rogue_Sprint",
}

local function CategoryName(cat)
    return ExtractionService.CATEGORY_NAMES[cat] or "Other"
end

local function CategoryText(cat)
    local c = CATEGORY_COLORS[cat]
    return c and ("|cff" .. c.hex .. CategoryName(cat) .. "|r") or CategoryName(cat)
end

local function QualityHex(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    return c and c.hex or "|cffffffff"
end

------------------------------------------------------------
-- Confirmation dialogs
------------------------------------------------------------

StaticPopupDialogs["EBONHOLD_CONFIRM_LEGENDARY_UPGRADE"] = {
    text = "Raise this item to %s?\n\nIt will consume %d Marks of Torment. Enchantments and gems are kept.",
    button1 = "Upgrade",
    button2 = "Cancel",
    OnAccept = function()
        if ExtractionUI.pendingBag and ExtractionUI.pendingSlot then
            ExtractionService.RequestLegendaryUpgrade(ExtractionUI.pendingBag, ExtractionUI.pendingSlot)
        end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EBONHOLD_CONFIRM_EXTRACTION"]  = {
    text = "Destroy %s and learn %s?",
    button1 = "Extract",
    button2 = "Cancel",
    OnAccept = function()
        if ExtractionUI.pendingBag and ExtractionUI.pendingSlot then
            ExtractionService.RequestExtraction(ExtractionUI.pendingBag, ExtractionUI.pendingSlot)
        end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- text is set before each show (it names the affix it replaces)
StaticPopupDialogs["EBONHOLD_CONFIRM_APPLY_AFFIX"] = {
    text = "Engrave %s on %s?",
    button1 = "Engrave",
    button2 = "Cancel",
    OnAccept = function()
        if ExtractionUI.pendingBag and ExtractionUI.pendingSlot and ExtractionUI.selectedAffixId then
            ExtractionService.RequestApplyAffix(ExtractionUI.selectedAffixId, ExtractionUI.pendingBag,
                ExtractionUI.pendingSlot)
        end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------
-- Layout
------------------------------------------------------------

local FRAME_NAME          = "EbonholdExtractionFrame"
local FRAME_W, FRAME_H    = 360, 520
local COL_W               = 167
local BOOK_CARD_W         = 300
local CARD_H, CARD_GAP    = 40, 4
local MENU_MAX            = 30      -- UIDropDownMenu holds 32 buttons per level
local TAB_TEXT_MAX_W      = 120
local ICON_ANVIL          = "Interface\\Icons\\Trade_BlackSmithing"
local EMPTY_SLOT          = "Interface\\Buttons\\UI-EmptySlot"
local ROUND_BORDER        = "Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder"

local TAB_ANVIL, TAB_BOOK = 1, 2
local TAB_NAMES = { "Anvil", "Affix Book" }

-- Paper-doll order of the inventory slots that can carry an affix (no shirt, no tabard)
local EQUIP_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

local frame                = CreateFrame("Frame", FRAME_NAME, UIParent)
local W                    = {}   -- widgets
-- key / itemId: the item on the anvil (server bag:slot, and its item id so another item
-- landing in that slot is not taken for it); bookCategory 0 = every category
local S                    = { tab = TAB_ANVIL, key = nil, itemId = nil, bookCategory = 0, entries = {} }
local isInExtractionGossip = false

ExtractionUI.pendingBag      = nil
ExtractionUI.pendingSlot     = nil
ExtractionUI.pendingLink     = nil
ExtractionUI.selectedAffixId = nil

------------------------------------------------------------
-- Small pieces
------------------------------------------------------------

-- A rectangle of 1 px lines, inset px inside parent.
local function Outline(parent, inset, r, g, b, a, layer)
    local lines = {}
    for i = 1, 4 do
        local t = parent:CreateTexture(nil, layer or "BORDER")
        t:SetTexture(r, g, b, a)
        lines[i] = t
    end
    lines[1]:SetHeight(1)
    lines[1]:SetPoint("TOPLEFT", inset, -inset); lines[1]:SetPoint("TOPRIGHT", -inset, -inset)
    lines[2]:SetHeight(1)
    lines[2]:SetPoint("BOTTOMLEFT", inset, inset); lines[2]:SetPoint("BOTTOMRIGHT", -inset, inset)
    lines[3]:SetWidth(1)
    lines[3]:SetPoint("TOPLEFT", inset, -inset); lines[3]:SetPoint("BOTTOMLEFT", inset, inset)
    lines[4]:SetWidth(1)
    lines[4]:SetPoint("TOPRIGHT", -inset, -inset); lines[4]:SetPoint("BOTTOMRIGHT", -inset, inset)
    return lines
end

-- Blizzard tab look without PanelTemplates_SelectTab (same as the Call Board's tabs).
local function SetTabSelected(t, selected)
    local n = t:GetName()
    for _, part in ipairs({ "Left", "Middle", "Right" }) do
        if selected then
            _G[n .. part]:Hide(); _G[n .. part .. "Disabled"]:Show()
        else
            _G[n .. part]:Show(); _G[n .. part .. "Disabled"]:Hide()
        end
    end
    t:SetNormalFontObject(selected and GameFontHighlightSmall or GameFontNormalSmall)
end

local function ResizeTab(t)
    local n = t:GetName()
    local text = _G[n .. "Text"]
    local textW = text:GetStringWidth()
    text:SetWidth(textW > TAB_TEXT_MAX_W and TAB_TEXT_MAX_W or 0)
    local w = math.max(40, math.min(TAB_TEXT_MAX_W, textW) + 20)
    _G[n .. "Middle"]:SetWidth(w)
    _G[n .. "MiddleDisabled"]:SetWidth(w)
    t:SetWidth(w + 40)
end

-- SetPortraitToTexture builds a new round texture on every call: only a changed icon is redrawn.
local function SetRoundIcon(tex, path)
    path = path or "Interface\\Icons\\INV_Misc_QuestionMark"
    if tex._path == path then return end
    tex._path = path
    SetPortraitToTexture(tex, path)
end

local function IconText(path, size)
    return "|T" .. (path or "Interface\\Icons\\INV_Misc_QuestionMark") .. ":" .. (size or 16) .. ":" .. (size or 16) .. ":0:0|t "
end

local function CoinText(copper)
    return GetCoinTextureString(copper or 0, 12)
end

------------------------------------------------------------
-- Data: the items that can go on the anvil, the affixes
------------------------------------------------------------

-- Lua bag/slot -> TrinityCore GetItemByPos(bag, slot):
-- backpack: bag 0 -> 255, slot -> INVENTORY_SLOT_ITEM_START (23) + slot - 1 ; bags 1-4: 18 + N, slot - 1
local function ServerPos(luaBag, luaSlot)
    if luaBag == 0 then return 255, 22 + luaSlot end
    return 18 + luaBag, luaSlot - 1
end

local function ItemIdOf(link)
    return link and tonumber(link:match("item:(%d+)")) or nil
end

local function MakeEntry(link, texture, serverBag, serverSlot, setTooltip)
    local name, _, quality, itemLevel, _, _, _, _, equipLoc = GetItemInfo(link)
    if not name then return nil end
    return {
        key = serverBag .. ":" .. serverSlot, bag = serverBag, slot = serverSlot,
        link = link, texture = texture, name = name, quality = quality or 1, itemLevel = itemLevel or 0,
        equipLoc = equipLoc, affix = FindItemAffix(link), foreign = HasForeignRandomProperty(link),
        allowedCats = GetItemAffixRules(link), setTooltip = setTooltip,
    }
end

-- Equipped, then bag items, that take an affix or carry one (to extract it)
local function ScanItems()
    local out = {}
    for _, inv in ipairs(EQUIP_ORDER) do
        local link = GetInventoryItemLink("player", inv)
        if link then
            local e = MakeEntry(link, GetInventoryItemTexture("player", inv), 255, inv - 1,
                function(tip) tip:SetInventoryItem("player", inv) end)
            if e and (e.allowedCats or e.affix) then
                e.equipped = true
                out[#out + 1] = e
            end
        end
    end
    for b = 0, 4 do
        for s = 1, GetContainerNumSlots(b) do
            local link = GetContainerItemLink(b, s)
            if link then
                local serverBag, serverSlot = ServerPos(b, s)
                local e = MakeEntry(link, (GetContainerItemInfo(b, s)), serverBag, serverSlot,
                    function(tip) tip:SetBagItem(b, s) end)
                if e and (e.allowedCats or e.affix) then out[#out + 1] = e end
            end
        end
    end
    return out
end

local function SortAffixes(list)
    table.sort(list, function(a, b)
        if a.category ~= b.category then return (a.category or 9) < (b.category or 9) end
        return (a.familyName or "") < (b.familyName or "")
    end)
end

local function MatchesSearch(affix)
    local text = W.search and W.search:GetText() or ""
    text = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return text == "" or (affix.familyName or ""):lower():find(text, 1, true) ~= nil
end

-- One entry per family: its best learned rank (fallback: rank I, for the Affix Book)
local function FamilyEntries(includeUnlearned)
    local best, order = {}, {}
    for _, a in ipairs(ExtractionService.learnedAffixes or {}) do
        local cur = best[a.familyId]
        if not cur then order[#order + 1] = a.familyId end
        if a.learned then
            if not cur or not cur.learned or a.rank > cur.rank then best[a.familyId] = a end
        elseif not cur or (not cur.learned and a.rank < cur.rank) then
            best[a.familyId] = a
        end
    end
    local out = {}
    for _, f in ipairs(order) do
        if includeUnlearned or best[f].learned then out[#out + 1] = best[f] end
    end
    return out
end

-- The server refuses the extraction when this rank, or a higher one, is already known
local function KnowsRankOrHigher(affix)
    for _, a in ipairs(ExtractionService.learnedAffixes or {}) do
        if a.learned and a.familyId == affix.familyId and a.rank >= affix.rank then return true end
    end
    return false
end

-- The item on the anvil, nil once it left its slot (sold, extracted, moved)
local function SelectedEntry()
    if not S.key then return nil end
    for _, e in ipairs(S.entries) do
        if e.key == S.key and (not S.itemId or ItemIdOf(e.link) == S.itemId) then return e end
    end
    return nil
end

-- Learned affixes the item can take, own class only (the server refuses the others)
local function AffixOptions(entry)
    local list = {}
    if not entry or entry.foreign or not entry.allowedCats then return list end
    for _, a in ipairs(FamilyEntries(false)) do
        if entry.allowedCats[a.category] and IsForPlayerClass(a.classMask) then list[#list + 1] = a end
    end
    SortAffixes(list)
    return list
end

local function FindAffix(id)
    if not id then return nil end
    for _, a in ipairs(ExtractionService.learnedAffixes or {}) do
        if a.id == id then return a end
    end
    return nil
end

local function AffixText(affix, twoHanded)
    if not affix or not affix.text then return "" end
    return ExtractionUI.RenderAffixText(affix.text, twoHanded) or affix.text
end

local function AffixTooltip(owner, affix, twoHanded)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(affix.name, 1, 1, 1)
    GameTooltip:AddLine(AffixText(affix, twoHanded), 1, 0.5, 0, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(CategoryText(affix.category) .. ((affix.spec and affix.spec ~= "") and (" - " .. affix.spec) or ""))
    local slotText = CATEGORY_SLOT_TEXT[affix.category or 0]
    if slotText and slotText ~= "" then
        GameTooltip:AddLine("Slots: " .. slotText, 0.7, 0.7, 0.7, true)
    end
    if affix.appliedCount and affix.appliedCount > 0 then
        GameTooltip:AddLine("Worn: " .. affix.appliedCount .. " time(s)", 0.7, 0.7, 0.7)
    end
    if not affix.learned then
        GameTooltip:AddLine("Not learned yet: extract it from a piece of gear.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

------------------------------------------------------------
-- Frame
------------------------------------------------------------

frame:SetSize(FRAME_W, FRAME_H)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
frame:SetFrameStrata("HIGH")
frame:SetToplevel(true)
frame:SetFrameLevel(100)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()
table.insert(UISpecialFrames, FRAME_NAME)

-- What just happened at the anvil goes to the chat (the window has no status line)
local function SetStatus(text)
    S.status = (text and text ~= "") and text or nil
    if S.status then
        DEFAULT_CHAT_FRAME:AddMessage(S.status, 1, 1, 1)
    end
end

local function HideAffixList()
    if W.pick then
        W.pick:Hide()
        W.pickSearch:ClearFocus()
    end
end

------------------------------------------------------------
-- Selection
------------------------------------------------------------

local function ClearItem()
    HideAffixList()
    S.key, S.itemId, S.reselect = nil, nil, nil
    ExtractionUI.pendingBag, ExtractionUI.pendingSlot, ExtractionUI.pendingLink = nil, nil, nil
    ExtractionUI.selectedAffixId = nil
    ExtractionService.upgradeInfo = nil
    ExtractionService.currentCost = nil
end

-- Puts an item on the anvil and asks the server what it costs / what it can become
local function SelectEntry(e)
    ClearItem()
    if not e then return end
    S.key, S.itemId = e.key, ItemIdOf(e.link)
    ExtractionUI.pendingBag, ExtractionUI.pendingSlot, ExtractionUI.pendingLink = e.bag, e.slot, e.link
    ExtractionService.RequestLegendaryUpgradeInfo(e.bag, e.slot)
    if e.affix and not e.equipped then
        ExtractionService.RequestExtractionInfo(e.bag, e.slot)
    end
end

-- The item held on the cursor (dragged from the bags or the character sheet) goes on the anvil
local function PlaceFromCursor()
    if not CursorHasItem() then return end
    local infoType, _, link = GetCursorInfo()
    ClearCursor()
    if infoType ~= "item" or not link then return end
    if not (GetItemAffixRules(link) or FindItemAffix(link)) then
        SetStatus("|cffff8040Only rare or better gear can carry an affix.|r")
        ExtractionUI.Refresh()
        return
    end
    for _, e in ipairs(ScanItems()) do
        if e.link == link then
            SetStatus(nil)
            SelectEntry(e)
            ExtractionUI.Refresh()
            return
        end
    end
    SetStatus("|cffff0000Only items from your bags or your character can go on the anvil.|r")
    ExtractionUI.Refresh()
end

------------------------------------------------------------
-- Menus (UIDropDownMenu): the items for the slot, the affixes for the dropdown
------------------------------------------------------------

local function ItemMenuButton(e)
    local info = UIDropDownMenu_CreateInfo()
    local affix = e.affix and ("  |cff1eff00" .. e.affix.name .. "|r") or ""
    info.text = IconText(e.texture) .. QualityHex(e.quality) .. e.name .. "|r" .. affix
    info.notCheckable = true
    info.func = function()
        SetStatus(nil)
        SelectEntry(e)
        CloseDropDownMenus()
        ExtractionUI.Refresh()
    end
    UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
end

local function MenuTitle(text, level)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
end

local function InitItemMenu(self, level)
    local equipped, bags = {}, {}
    for _, e in ipairs(ScanItems()) do
        if e.equipped then equipped[#equipped + 1] = e else bags[#bags + 1] = e end
    end
    if level == 1 then
        if #equipped + #bags == 0 then
            MenuTitle("None of your items can carry an affix", 1)
            return
        end
        if #equipped + #bags + 2 <= MENU_MAX then
            if #equipped > 0 then MenuTitle("Equipped", 1) end
            for _, e in ipairs(equipped) do ItemMenuButton(e) end
            if #bags > 0 then MenuTitle("In your bags", 1) end
            for _, e in ipairs(bags) do ItemMenuButton(e) end
        else
            -- too many for one level: one sub-menu per place
            for _, group in ipairs({ { "Equipped", "eq", #equipped }, { "In your bags", "bag", #bags } }) do
                if group[3] > 0 then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = group[1] .. "  |cff9d9d9d(" .. group[3] .. ")|r"
                    info.value = group[2]
                    info.hasArrow = true
                    info.notCheckable = true
                    UIDropDownMenu_AddButton(info, 1)
                end
            end
        end
    elseif level == 2 then
        local list = UIDROPDOWNMENU_MENU_VALUE == "eq" and equipped or bags
        for i = 1, math.min(#list, MENU_MAX) do ItemMenuButton(list[i]) end
    end
end

local function InitBookCategoryMenu(self, level)
    local function Add(cat, text)
        local info = UIDropDownMenu_CreateInfo()
        info.text = text
        info.checked = S.bookCategory == cat
        info.func = function()
            S.bookCategory = cat
            CloseDropDownMenus()
            ExtractionUI.Refresh()
        end
        UIDropDownMenu_AddButton(info, level)
    end
    Add(0, "All categories")
    for _, cat in ipairs(CATEGORY_ORDER) do Add(cat, CategoryText(cat)) end
end

------------------------------------------------------------
-- Building the window (first show: the frame templates come from the
-- collections module, later in the TOC). Explicit frame levels, as the talent
-- window: chrome N, pages N+1, their marble insets N+2, the content N+3.
------------------------------------------------------------

local function Inset(page, x0, y0, x1, y1)
    local ok, inset = pcall(CreateFrame, "Frame", nil, page, "InsetFrameTemplate")
    if not ok or not inset then
        inset = CreateFrame("Frame", nil, page)
        local bg = inset:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0, 0, 0, 0.45)
        Outline(inset, 0, 0.42, 0.32, 0.20, 1)
    end
    inset:SetPoint("TOPLEFT", frame, "TOPLEFT", x0, -y0)
    inset:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", x1, -y1)
    return inset
end

-- A page (Anvil or Affix Book): insets under, content frame above
local function Page(base, insets)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints(frame)
    page:SetFrameLevel(base + 1)
    for _, r in ipairs(insets) do
        Inset(page, r[1], r[2], r[3], r[4]):SetFrameLevel(base + 2)
    end
    local c = CreateFrame("Frame", nil, page)
    c:SetAllPoints(frame)
    c:SetFrameLevel(base + 3)
    page.c = c
    return page
end

local function Text(parent, template, x, y, width, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    if justify == "CENTER" then
        fs:SetPoint("TOP", parent, "TOPLEFT", x, -y)
    else
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    end
    if width then fs:SetWidth(width) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- CURRENT / AFTER column of the anvil page
local function Column(c, x, head)
    local col = {}
    col.head = Text(c, "GameFontNormalSmall", x + 8, 280)
    col.head:SetText(head)
    col.icon = c:CreateTexture(nil, "ARTWORK")
    col.icon:SetSize(30, 30)
    col.icon:SetPoint("TOPLEFT", c, "TOPLEFT", x + 10, -298)
    col.ring = c:CreateTexture(nil, "OVERLAY")
    col.ring:SetSize(68, 68)
    col.ring:SetPoint("CENTER", col.icon, "CENTER")
    col.ring:SetTexture(ROUND_BORDER)
    col.name = Text(c, "GameFontHighlight", x + 48, 306, COL_W - 54)
    col.name:SetWordWrap(false)
    col.text = Text(c, "GameFontHighlightSmall", x + 10, 338, COL_W - 18)
    col.text:SetHeight(126)
    col.text:SetJustifyV("TOP")
    -- "No affix" / "Pick an affix above": centred in the column, wraps on its full width
    col.empty = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    col.empty:SetPoint("CENTER", c, "TOPLEFT", x + COL_W / 2, -375)
    col.empty:SetWidth(COL_W - 20)
    col.empty:SetJustifyH("CENTER")
    col.empty:SetTextColor(0.62, 0.62, 0.62)
    return col
end

local function SetColumn(col, affix, twoHanded, placeholder)
    if affix then
        SetRoundIcon(col.icon, affix.icon)
        col.icon:Show(); col.ring:Show()
        col.name:SetText("|cff1eff00" .. affix.name .. "|r")
        col.text:SetText(AffixText(affix, twoHanded))
        col.empty:SetText("")
    else
        col.icon:Hide(); col.ring:Hide()
        col.name:SetText("")
        col.text:SetText("")
        col.empty:SetText(placeholder or "-")
    end
end

local function CreateFilterCheck(parent, name, label, x, y)
    local cb = CreateFrame("CheckButton", name, parent, "ChatConfigCheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    cb:SetChecked(true)
    local text = _G[name .. "Text"]
    text:SetText(label)
    text:SetFontObject("GameFontNormalSmall")
    -- the template's click area runs far to the right of the box and covered the next
    -- filter: keep it to the box and its label
    cb:SetHitRectInsets(0, -math.ceil(text:GetStringWidth()), 0, 0)
    cb:SetScript("OnClick", function() ExtractionUI.Refresh() end)
    return cb
end

-- A card of the Affix Book list (one column)
local function CreateCard(index)
    local c = CreateFrame("Button", nil, W.bookContent)
    c:SetSize(BOOK_CARD_W, CARD_H)
    c:SetPoint("TOPLEFT", W.bookContent, "TOPLEFT", 0, -(index - 1) * (CARD_H + CARD_GAP))
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0, 0, 0, 0.35)
    Outline(c, 0, 0.42, 0.32, 0.20, 1)
    c.glow = c:CreateTexture(nil, "BORDER")
    c.glow:SetAllPoints()
    c.glow:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    c.glow:SetBlendMode("ADD")
    c.glow:SetVertexColor(1, 0.75, 0.2)
    c.glow:SetAlpha(0.4)
    c.glow:Hide()
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(28, 28)
    c.icon:SetPoint("LEFT", c, "LEFT", 7, 0)
    c.ring = c:CreateTexture(nil, "OVERLAY")
    c.ring:SetSize(60, 60)
    c.ring:SetPoint("CENTER", c.icon, "CENTER")
    c.ring:SetTexture(ROUND_BORDER)
    c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.name:SetPoint("TOPLEFT", c, "TOPLEFT", 42, -7)
    c.name:SetPoint("RIGHT", c, "RIGHT", -6, 0)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.sub:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -3)
    c.sub:SetPoint("RIGHT", c, "RIGHT", -6, 0)
    c.sub:SetJustifyH("LEFT")
    c.sub:SetWordWrap(false)
    c:SetScript("OnEnter", function(self)
        if not self.affix then return end
        self.glow:Show()
        AffixTooltip(self, self.affix, false)
    end)
    c:SetScript("OnLeave", function(self)
        self.glow:Hide()
        GameTooltip:Hide()
    end)
    W.cards[index] = c
    return c
end

-- Token label (Mark of Torment) for the upgrade button
-- A token the client has never held has no name yet: a hidden tooltip asks the server for it,
-- and tokenRetry re-draws until the answer lands (3.3.5 has no event for it).
local tokenScanTip
local tokenRetry = CreateFrame("Frame")
tokenRetry:Hide()

local function TokenLabel(tokenId)
    local name = GetItemInfo(tokenId)
    if not name then
        if not tokenScanTip then
            tokenScanTip = CreateFrame("GameTooltip", "ProjectEbonholdExtractionScan", nil, "GameTooltipTemplate")
        end
        tokenScanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        tokenScanTip:SetHyperlink("item:" .. tokenId)
        tokenScanTip:Hide()
        if not tokenRetry:IsShown() then
            tokenRetry.elapsed, tokenRetry.total = 0, 0
            tokenRetry:Show()
        end
        name = GetItemInfo(tokenId)
    end
    local icon = GetItemIcon(tokenId)
    local label = name or "Mark of Torment"
    if icon then label = "|T" .. icon .. ":16:16:0:0|t " .. label end
    return label
end

tokenRetry:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    self.total = self.total + dt
    if self.elapsed < 0.25 then return end
    self.elapsed = 0
    local up = ExtractionService.upgradeInfo
    if not up or not frame:IsShown() or self.total > 5 then
        self:Hide()
        return
    end
    if GetItemInfo(up.tokenId) then
        self:Hide()
        ExtractionUI.Refresh()
    end
end)

-- The affix picker: our own list under the dropdown, rows big enough to read (UIDropDownMenu's
-- 16 px small-font lines were not, owner 2026-11-01). Only what can be engraved on this item is
-- listed (the affix it already carries is left out). Hovering a row shows its tooltip; AFTER
-- stays empty until a row is clicked (owner: nothing behind the list before a choice).
local PICK_ROW_H, PICK_ROWS, PICK_W = 28, 11, 330

-- Affixes the picker offers: AffixOptions minus the one already on the item
local function EngravableAffixes(e)
    local out = {}
    for _, a in ipairs(AffixOptions(e)) do
        if not (e.affix and e.affix.id == a.id) then out[#out + 1] = a end
    end
    return out
end

-- Affix families already worn on the OTHER equipped pieces: familyId -> their item links
local function WornFamilies(e)
    local worn = {}
    for _, o in ipairs(S.entries) do
        if o.equipped and o.affix and not (e and o.key == e.key) then
            local f = worn[o.affix.familyId] or {}
            f[#f + 1] = o.link
            worn[o.affix.familyId] = f
        end
    end
    return worn
end

local function PickRow(i)
    local r = W.pickRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, W.pickContent)
    r:SetSize(PICK_W - 40, PICK_ROW_H)
    r:SetPoint("TOPLEFT", W.pickContent, "TOPLEFT", 0, -(i - 1) * PICK_ROW_H)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    r.hl:SetBlendMode("ADD")
    r.hl:SetVertexColor(1, 0.75, 0.2)
    r.hl:Hide()
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(18, 18)
    r.check:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", r, "LEFT", 22, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 7, 0)
    r.name:SetJustifyH("LEFT")
    r.cat = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.cat:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.head = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.head:SetPoint("LEFT", r, "LEFT", 6, -2)
    r:SetScript("OnEnter", function(self)
        if not self.affix then return end
        self.hl:Show()
        local e = SelectedEntry()
        AffixTooltip(self, self.affix, e and e.equipLoc == "INVTYPE_2HWEAPON")
        if self.wornOn then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Already on your equipped gear:", 1, 0.5, 0.25)
            for _, link in ipairs(self.wornOn) do GameTooltip:AddLine("  " .. link) end
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
        if not self.affix then return end
        PlaySound("igMainMenuOptionCheckBoxOn")
        ExtractionUI.selectedAffixId = self.affix.id
        ExtractionService.applyCost = self.affix.applyCost
        SetStatus(nil)
        HideAffixList()
        ExtractionUI.Refresh()
    end)
    W.pickRows[i] = r
    return r
end

-- opening = true: a fresh list (search emptied, focus in the box); false: re-filter while typing
local function ShowAffixList(opening)
    local e = SelectedEntry()
    local all = e and EngravableAffixes(e) or {}
    if #all == 0 then return end
    if opening then
        W.pickSearch:SetText("")
    end
    local query = (W.pickSearch:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local list = {}
    for _, a in ipairs(all) do
        if query == "" or (a.name or ""):lower():find(query, 1, true) then list[#list + 1] = a end
    end
    local cats, catCount = {}, 0
    for _, a in ipairs(list) do
        if not cats[a.category] then cats[a.category] = true; catCount = catCount + 1 end
    end
    local worn = WornFamilies(e)
    for _, r in ipairs(W.pickRows) do r:Hide() end
    local n, last = 0, nil
    for _, a in ipairs(list) do
        if catCount > 1 and a.category ~= last then
            n = n + 1
            local r = PickRow(n)
            r.affix, r.wornOn = nil, nil
            r.check:Hide(); r.icon:Hide(); r.name:SetText(""); r.cat:SetText("")
            r.head:SetText(CategoryText(a.category))
            r:Show()
        end
        last = a.category
        n = n + 1
        local r = PickRow(n)
        r.affix, r.wornOn = a, worn[a.familyId]
        r.head:SetText("")
        r.icon:SetTexture(a.icon)
        r.icon:Show()
        -- already worn elsewhere: greyed name and an orange tag (the tooltip names the pieces)
        if r.wornOn then
            r.name:SetText("|cff9d9d9d" .. a.name .. "|r |cffff8040(worn)|r")
        else
            r.name:SetText("|cffffffff" .. a.name .. "|r")
        end
        r.cat:SetText("|cff" .. ((CATEGORY_COLORS[a.category] or {}).hex or "ffffff") .. CategoryName(a.category) .. "|r")
        if ExtractionUI.selectedAffixId == a.id then r.check:Show() else r.check:Hide() end
        r:Show()
    end
    if n == 0 then
        n = 1
        local r = PickRow(1)
        r.affix, r.wornOn = nil, nil
        r.check:Hide(); r.icon:Hide(); r.cat:SetText(""); r.name:SetText("")
        r.head:SetText("|cff9d9d9dNo affix matches this search.|r")
        r:Show()
    end
    W.pickContent:SetHeight(n * PICK_ROW_H)
    W.pick:SetHeight(math.min(n, PICK_ROWS) * PICK_ROW_H + 14 + 30)
    W.pickScroll:SetVerticalScroll(0)
    if opening then
        W.pick:Show()
        W.pickSearch:SetFocus()
    end
end

local function BuildAffixList(c)
    local pick = CreateFrame("Frame", nil, c)
    pick:SetWidth(PICK_W)
    pick:SetPoint("TOPLEFT", c, "TOPLEFT", 15, -262)
    pick:SetFrameLevel(c:GetFrameLevel() + 10)
    pick:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    pick:SetBackdropColor(0, 0, 0, 1)
    pick:SetBackdropBorderColor(0.7, 0.6, 0.4)
    -- the tooltip texture stays see-through even at full alpha: a solid fill under the list
    local fill = pick:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", pick, "TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMRIGHT", pick, "BOTTOMRIGHT", -4, 4)
    fill:SetTexture(0.03, 0.025, 0.02, 1)
    pick:EnableMouse(true)
    pick:Hide()
    -- search on top of the list: the echo journal's box, like every search bar of the addon
    local ok, box = pcall(CreateFrame, "EditBox", "EbonholdAnvilPickSearch", pick, "ezCollectionsSearchBoxTemplate")
    if ok and box and box.Instructions then
        box.Instructions:SetText("Search affixes")
    else
        box = CreateFrame("EditBox", "EbonholdAnvilPickSearch", pick, "InputBoxTemplate")
    end
    box:SetAutoFocus(false)
    box:SetHeight(20)
    box:SetPoint("TOPLEFT", pick, "TOPLEFT", 14, -9)
    box:SetPoint("TOPRIGHT", pick, "TOPRIGHT", -12, -9)
    box:SetMaxLetters(40)
    -- HookScript: the template keeps its own scripts (magnifier, clear button, grey text)
    box:HookScript("OnTextChanged", function() if W.pick:IsShown() then ShowAffixList(false) end end)
    box:HookScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        HideAffixList()
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    W.pickSearch = box

    local scroll = CreateFrame("ScrollFrame", FRAME_NAME .. "AffixPickScroll", pick, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", pick, "TOPLEFT", 8, -7 - 30)
    scroll:SetPoint("BOTTOMRIGHT", pick, "BOTTOMRIGHT", -30, 7)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PICK_W - 40, 1)
    scroll:SetScrollChild(content)
    W.pick, W.pickScroll, W.pickContent, W.pickRows = pick, scroll, content, {}
end

local function BuildAnvilPage(base)
    local page = Page(base, { { 10, 60, 350, 212 }, { 10, 272, 177, 470 }, { 183, 272, 350, 470 } })
    local c = page.c
    W.anvil = page

    -- the anvil slot: click = choose an item, drop = place it, right-click = empty it
    local slot = CreateFrame("Button", nil, c)
    slot:SetSize(56, 56)
    slot:SetPoint("TOPLEFT", c, "TOPLEFT", 152, -72)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot.empty = slot:CreateTexture(nil, "BACKGROUND")
    slot.empty:SetSize(88, 88)
    slot.empty:SetPoint("CENTER")
    slot.empty:SetTexture(EMPTY_SLOT)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints()
    slot.glow = slot:CreateTexture(nil, "OVERLAY")
    slot.glow:SetSize(104, 104)
    slot.glow:SetPoint("CENTER")
    slot.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    slot.glow:SetBlendMode("ADD")
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot:SetScript("OnReceiveDrag", PlaceFromCursor)
    slot:SetScript("OnClick", function(self, button)
        if CursorHasItem() then PlaceFromCursor() return end
        if button == "RightButton" then
            ClearItem()
            SetStatus(nil)
            ExtractionUI.Refresh()
            return
        end
        ToggleDropDownMenu(1, nil, W.itemMenu, self, 0, 0)
    end)
    slot:SetScript("OnEnter", function(self)
        local e = SelectedEntry()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e and e.setTooltip then
            e.setTooltip(GameTooltip)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to choose another item, right-click to take it off.", 0.6, 0.6, 0.6, true)
        else
            GameTooltip:SetText("Enchanted Anvil", 1, 1, 1)
            GameTooltip:AddLine("Click to choose an item, or drag one here.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    W.slot = slot
    W.itemMenu = CreateFrame("Frame", "EbonholdAnvilItemMenu", frame, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(W.itemMenu, InitItemMenu, "MENU")

    W.itemName = Text(c, "GameFontNormal", 180, 136, 330, "CENTER")
    W.itemSub = Text(c, "GameFontHighlightSmall", 180, 154, 330, "CENTER")
    W.itemSub:SetTextColor(0.73, 0.68, 0.56)

    -- Legendary Torment upgrade: shown only when the server quotes a recipe for the item
    W.upgrade = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    W.upgrade:SetSize(230, 22)
    W.upgrade:SetNormalFontObject("GameFontHighlight")   -- white label, grey when disabled
    W.upgrade:SetPoint("TOP", c, "TOPLEFT", 180, -182)
    W.upgrade:SetMotionScriptsWhileDisabled(true)   -- tooltip must work while the button is greyed out
    W.upgrade:Hide()
    W.upgrade:SetScript("OnEnter", function(self)
        local up = ExtractionService.upgradeInfo
        if not up then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Upgrade to " .. up.label)
        GameTooltip:AddLine(string.format("%d/%d %s", up.held, up.needed, TokenLabel(up.tokenId)), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    W.upgrade:SetScript("OnLeave", function() GameTooltip:Hide() end)
    W.upgrade:SetScript("OnClick", function()
        local up = ExtractionService.upgradeInfo
        if not up or not ExtractionUI.pendingBag or not ExtractionUI.pendingSlot then return end
        local e = SelectedEntry()
        S.pending = { link = e and e.link, label = up.label }
        StaticPopup_Show("EBONHOLD_CONFIRM_LEGENDARY_UPGRADE", up.label, up.needed)
    end)

    local label = Text(c, "GameFontNormalSmall", 20, 220)
    label:SetText("ENGRAVE")
    -- the dropdown's look, our own list behind its button (BuildAffixList)
    W.affixDD = CreateFrame("Frame", "EbonholdAnvilAffixDropDown", c, "UIDropDownMenuTemplate")
    W.affixDD:SetPoint("TOPLEFT", c, "TOPLEFT", -4, -232)
    UIDropDownMenu_SetWidth(W.affixDD, 318)
    UIDropDownMenu_JustifyText(W.affixDD, "LEFT")
    _G["EbonholdAnvilAffixDropDownText"]:SetFontObject("GameFontHighlight")   -- the template's small font reads too tiny
    _G["EbonholdAnvilAffixDropDownButton"]:SetScript("OnClick", function()
        PlaySound("igMainMenuOptionCheckBoxOn")
        if W.pick:IsShown() then HideAffixList() else ShowAffixList(true) end
    end)

    W.cur = Column(c, 10, "CURRENT")
    W.aft = Column(c, 183, "AFTER")
    BuildAffixList(c)   -- after the columns, drawn above them
    local arrow = c:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(26, 26)
    arrow:SetPoint("TOPLEFT", c, "TOPLEFT", 167, -357)
    arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")

    W.extractBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    W.extractBtn:SetSize(152, 26)
    W.extractBtn:SetNormalFontObject("GameFontHighlight")   -- white label, grey when disabled
    W.extractBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 18, -478)
    W.extractBtn:SetMotionScriptsWhileDisabled(true)
    W.extractBtn:SetScript("OnClick", function()
        local e = SelectedEntry()
        if not e or not e.affix or e.equipped then return end
        S.pending = { link = e.link, old = e.affix }
        StaticPopup_Show("EBONHOLD_CONFIRM_EXTRACTION", e.link, "|cff1eff00" .. e.affix.name .. "|r")
    end)
    W.extractBtn:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Extract", 1, 1, 1)
        GameTooltip:AddLine(self.tip, 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    W.extractBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    W.engraveBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    W.engraveBtn:SetSize(152, 26)
    W.engraveBtn:SetNormalFontObject("GameFontHighlight")   -- white label, grey when disabled
    W.engraveBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 191, -478)
    W.engraveBtn:SetScript("OnClick", function()
        local e = SelectedEntry()
        local affix = FindAffix(ExtractionUI.selectedAffixId)
        if not e or not affix then return end
        local d = StaticPopupDialogs["EBONHOLD_CONFIRM_APPLY_AFFIX"]
        d.text = "Engrave %s on %s?"
            .. (e.affix and ("\n\nIt replaces " .. e.affix.name .. ".") or "")
            .. "\n\nCost: " .. FormatCopperSmall(affix.applyCost or 0)
        S.pending = { link = e.link, old = e.affix, new = affix }
        StaticPopup_Show("EBONHOLD_CONFIRM_APPLY_AFFIX", "|cff1eff00" .. affix.name .. "|r", e.link)
    end)
end

-- The echo journal's search box (magnifier, grey placeholder, clear button), like every
-- search bar of the addon; plain 3.3.5 box if the template is missing
local function BuildSearchBox(parent)
    local ok, box = pcall(CreateFrame, "EditBox", "EbonholdAffixSearchBox", parent, "ezCollectionsSearchBoxTemplate")
    if ok and box and box.Instructions then
        box.Instructions:SetText("Search affixes")
    else
        box = CreateFrame("EditBox", "EbonholdAffixSearchBox", parent, "InputBoxTemplate")
        box:SetAutoFocus(false)
    end
    box:SetSize(150, 20)
    box:SetPoint("TOPRIGHT", parent, "TOPLEFT", 340, -94)
    box:SetMaxLetters(40)
    -- HookScript: the template keeps its own scripts (magnifier, clear button, grey text)
    box:HookScript("OnTextChanged", function() ExtractionUI.Refresh() end)
    box:HookScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function BuildBookPage(base)
    local page = Page(base, { { 10, 60, 350, 510 } })
    local c = page.c
    W.book = page

    -- the learned count lives here only (owner, 2026-11-01)
    W.bookCount = Text(c, "GameFontNormal", 20, 70)
    W.catDD = CreateFrame("Frame", "EbonholdAffixBookCategory", c, "UIDropDownMenuTemplate")
    W.catDD:SetPoint("TOPLEFT", c, "TOPLEFT", 2, -88)
    UIDropDownMenu_SetWidth(W.catDD, 130)
    UIDropDownMenu_Initialize(W.catDD, InitBookCategoryMenu)
    W.search = BuildSearchBox(c)
    W.learnedCB = CreateFilterCheck(c, "EbonholdAffixLearnedCheck", "Learned only", 20, 122)
    W.classCB = CreateFilterCheck(c, "EbonholdAffixClassCheck", "My class only", 160, 122)

    local scroll = CreateFrame("ScrollFrame", FRAME_NAME .. "BookScroll", c, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", c, "TOPLEFT", 18, -152)
    scroll:SetPoint("BOTTOMRIGHT", c, "TOPLEFT", 320, -504)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(BOOK_CARD_W, 1)
    scroll:SetScrollChild(content)
    W.bookContent, W.cards = content, {}
    W.bookEmpty = Text(c, "GameFontNormal", 180, 300, 300, "CENTER")
    W.bookEmpty:SetTextColor(0.62, 0.62, 0.62)
end

local function EnsureBuilt()
    if W.built then return end
    W.built = true
    local base = frame:GetFrameLevel()
    local ok, chrome = pcall(CreateFrame, "Frame", nil, frame, "ezCollectionsPortraitFrameTemplateNoCloseButton")
    if ok and chrome then
        chrome:SetAllPoints(frame)
        chrome:SetFrameLevel(base)
        chrome.TitleText:SetText("Enchanted Anvil")
        SetPortraitToTexture(chrome.portrait, ICON_ANVIL)
    else
        -- templates missing: plain dialog border so the window still reads as one
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32, tile = true, tileSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", frame, "TOP", 0, -14)
        title:SetText("Enchanted Anvil")
    end
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 4, 5)
    closeBtn:SetFrameLevel(base + 4)

    BuildAnvilPage(base)
    BuildBookPage(base)
end

------------------------------------------------------------
-- Refresh
------------------------------------------------------------

local function RefreshUpgrade(entry)
    local up = entry and ExtractionService.upgradeInfo
    if not up then
        W.upgrade:Hide()
        return
    end
    local color = (up.held >= up.needed) and "|cff00ff00" or "|cffff4040"
    W.upgrade:SetText(string.format("Upgrade  %s%d/%d|r %s", color, up.held, up.needed, TokenLabel(up.tokenId)))
    W.upgrade:Show()
    if up.held >= up.needed then W.upgrade:Enable() else W.upgrade:Disable() end
end

local function RefreshAnvil()
    S.entries = ScanItems()
    local e = SelectedEntry()
    if S.key and not e then ClearItem() end
    if e and S.reselect then
        -- after a Torment upgrade the item is a new object: quote its next bracket
        S.reselect = nil
        SelectEntry(e)
    end

    if not e then
        W.slot.icon:Hide()
        W.slot.glow:Hide()
        W.itemName:SetText("Place an item on the anvil")
        W.itemSub:SetText("Click the slot to choose an item,\nor drag one here.")
        W.upgrade:Hide()
        UIDropDownMenu_SetText(W.affixDD, "|cff808080Choose an affix|r")
        UIDropDownMenu_DisableDropDown(W.affixDD)
        SetColumn(W.cur, nil, false)
        SetColumn(W.aft, nil, false)
        W.extractBtn:SetText("Extract")
        W.extractBtn.tip = nil
        W.extractBtn:Disable()
        W.engraveBtn:SetText("Engrave")
        W.engraveBtn:Disable()
        return
    end

    local twoHanded = e.equipLoc == "INVTYPE_2HWEAPON"
    W.slot.icon:SetTexture(e.texture)
    W.slot.icon:Show()
    local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
    if q and e.quality >= 2 then
        W.slot.glow:SetVertexColor(q.r, q.g, q.b)
        W.slot.glow:Show()
    else
        W.slot.glow:Hide()
    end
    local cats = {}
    for _, cat in ipairs(CATEGORY_ORDER) do
        if e.allowedCats and e.allowedCats[cat] then cats[#cats + 1] = CategoryText(cat) end
    end
    W.itemName:SetText(QualityHex(e.quality) .. e.name .. "|r")
    W.itemSub:SetText(#cats > 0 and table.concat(cats, ", ") or "None")
    RefreshUpgrade(e)

    -- the dropdown: learned affixes this item takes
    local options = AffixOptions(e)
    local current = e.affix
    local selected = FindAffix(ExtractionUI.selectedAffixId)
    local listed = false
    for _, a in ipairs(options) do
        if selected and a.id == selected.id and not (current and current.id == a.id) then listed = true end
    end
    if not listed then
        selected = nil
        ExtractionUI.selectedAffixId = nil
    end
    if e.foreign or #EngravableAffixes(e) == 0 then
        HideAffixList()
        UIDropDownMenu_SetText(W.affixDD, "|cff808080" .. (e.foreign and "Random enchantment: cannot be engraved"
            or "You know no affix for this slot yet") .. "|r")
        UIDropDownMenu_DisableDropDown(W.affixDD)
    else
        UIDropDownMenu_EnableDropDown(W.affixDD)
        UIDropDownMenu_SetText(W.affixDD, selected and (IconText(selected.icon) .. "|cff1eff00" .. selected.name .. "|r")
            or "Choose an affix")
    end

    SetColumn(W.cur, current, twoHanded, "No affix")
    SetColumn(W.aft, selected, twoHanded, "")   -- empty until an affix is chosen

    -- Extract: destroys the item, so bag items only; the server checks again
    local money = GetMoney()
    local known = current and KnowsRankOrHigher(current)
    if current then
        local cost = current.extractCost or ExtractionService.currentCost or 0
        W.extractBtn:SetText("Extract  " .. CoinText(cost))
        local tip
        if e.equipped then
            tip = "|cffff8040Unequip it first.|r Extracting destroys the item."
        elseif known then
            tip = "|cffff8040You already know this affix at this rank or higher.|r Extracting it would teach you nothing."
        elseif money < cost then
            tip = "|cffff4040Not enough gold.|r"
        end
        W.extractBtn.tip = tip or ("Destroys the item and teaches you " .. current.name ..
            ". You can then engrave it on any item that takes " .. CategoryName(current.category) .. " affixes.")
        if tip then W.extractBtn:Disable() else W.extractBtn:Enable() end
    else
        W.extractBtn:SetText("Extract")
        W.extractBtn.tip = "This item carries no affix."
        W.extractBtn:Disable()
    end

    if selected then
        local cost = selected.applyCost or 0
        W.engraveBtn:SetText("Engrave  " .. CoinText(cost))
        if money >= cost then W.engraveBtn:Enable() else W.engraveBtn:Disable() end
    else
        W.engraveBtn:SetText("Engrave")
        W.engraveBtn:Disable()
    end
end

local function RefreshBook()
    local families, learnedCount = 0, 0
    for _, a in ipairs(FamilyEntries(true)) do
        if IsForPlayerClass(a.classMask) then
            families = families + 1
            if a.learned then learnedCount = learnedCount + 1 end
        end
    end
    W.bookCount:SetText(string.format("Affixes learned  |cffffffff%d / %d|r", learnedCount, families))
    UIDropDownMenu_SetText(W.catDD, S.bookCategory == 0 and "All categories" or CategoryText(S.bookCategory))

    local learnedOnly, classOnly = W.learnedCB:GetChecked(), W.classCB:GetChecked()
    local list = {}
    for _, a in ipairs(FamilyEntries(true)) do
        if (S.bookCategory == 0 or a.category == S.bookCategory)
            and (not classOnly or IsForPlayerClass(a.classMask))
            and (not learnedOnly or a.learned) and MatchesSearch(a) then
            list[#list + 1] = a
        end
    end
    SortAffixes(list)
    for _, c in ipairs(W.cards) do c:Hide(); c.affix = nil end
    for i, affix in ipairs(list) do
        local c = W.cards[i] or CreateCard(i)
        c.affix = affix
        SetRoundIcon(c.icon, affix.icon)
        c.name:SetText((affix.learned and "|cffffffff" or "|cff9d9d9d") .. affix.name .. "|r")
        local sub = CategoryText(affix.category)
        if affix.spec and affix.spec ~= "" then sub = sub .. "|cffa69a83 - " .. affix.spec .. "|r" end
        if not IsForPlayerClass(affix.classMask) then sub = sub .. "  |cffff6060Other class|r" end
        c.sub:SetText(sub)
        -- a card not learned is greyed out, no label needed
        c.icon:SetDesaturated(not affix.learned)
        c:SetAlpha((affix.learned and IsForPlayerClass(affix.classMask)) and 1 or 0.6)
        c:Show()
    end
    W.bookContent:SetHeight(math.max(1, #list * (CARD_H + CARD_GAP)))
    if #list == 0 then
        W.bookEmpty:SetText(learnedOnly and "You have not learned any affix of this kind yet." or "No affix matches these filters.")
        W.bookEmpty:Show()
    else
        W.bookEmpty:Hide()
    end
end

local function RefreshTabs()
    for i, t in ipairs(W.tabs) do
        ResizeTab(t)
        SetTabSelected(t, i == S.tab)
    end
end

function ExtractionUI.Refresh()
    if not frame:IsShown() or not W.built then return end
    RefreshTabs()
    if S.tab == TAB_BOOK then
        W.anvil:Hide()
        W.book:Show()
        RefreshBook()
    else
        W.book:Hide()
        W.anvil:Show()
        RefreshAnvil()
    end
end

-- Item links change a moment after an engraving / extraction lands: redraw now and once more later
local delayed = CreateFrame("Frame")
delayed:Hide()
delayed:SetScript("OnUpdate", function(self, dt)
    self.left = self.left - dt
    if self.left > 0 then return end
    self:Hide()
    ExtractionUI.Refresh()
end)
local function RefreshSoon(delay)
    delayed.left = math.max(delayed:IsShown() and delayed.left or 0, delay)
    delayed:Show()
end

------------------------------------------------------------
-- Tabs, drag and drop
------------------------------------------------------------

W.tabs = {}
for i, label in ipairs(TAB_NAMES) do
    local t = CreateFrame("Button", FRAME_NAME .. "Tab" .. i, frame, "CharacterFrameTabButtonTemplate")
    if i == 1 then
        t:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 14, 2)
    else
        t:SetPoint("LEFT", W.tabs[i - 1], "RIGHT", -16, 0)
    end
    t:SetHeight(32)
    t:SetText(label)
    -- the template's OnShow / OnEvent resize through CharacterFrame helpers: ours instead
    t:SetScript("OnShow", function(self) ResizeTab(self) end)
    t:SetScript("OnEvent", function(self) ResizeTab(self) end)
    t:SetScript("OnClick", function()
        PlaySound("igCharacterInfoTab")
        S.tab = i
        SetStatus(nil)
        HideAffixList()
        CloseDropDownMenus()
        ExtractionUI.Refresh()
    end)
    W.tabs[i] = t
end

-- Dropping an item anywhere on the window puts it on the anvil
local function OnWindowDrop()
    if not CursorHasItem() then return end
    S.tab = TAB_ANVIL
    PlaceFromCursor()
end
frame:SetScript("OnReceiveDrag", OnWindowDrop)
frame:SetScript("OnMouseUp", function() if CursorHasItem() then OnWindowDrop() end end)

------------------------------------------------------------
-- Server callbacks (ExtractionService)
------------------------------------------------------------

function ExtractionUI.OnUpgradeInfoReceived(info)
    if frame:IsShown() then ExtractionUI.Refresh() end
end

function ExtractionUI.OnUpgradeSuccess(newEntry)
    if not frame:IsShown() then return end
    local p = S.pending or {}
    local after = newEntry and select(2, GetItemInfo(newEntry))
    SetStatus((p.link or "Your item") .. " -> " .. (after or p.label or "its next version") .. ".")
    -- the item is a new object now: take what lands in its slot and quote the next bracket
    S.itemId, S.reselect = nil, true
    RefreshSoon(0.5)
end

function ExtractionUI.OnUpgradeFail(reason)
    if not frame:IsShown() then return end
    SetStatus("|cffff0000" .. (reason or "Upgrade failed.") .. "|r")
    ExtractionUI.Refresh()
end

function ExtractionUI.OnCostReceived(cost)
    if frame:IsShown() then ExtractionUI.Refresh() end
end

function ExtractionUI.OnExtractionSuccess()
    if not frame:IsShown() then return end
    ClearItem()   -- the item is destroyed
    local p = S.pending or {}
    SetStatus((p.old and p.old.name or "Affix") .. " extracted from " .. (p.link or "your item")
        .. " (item destroyed). You can now engrave it.")
    RefreshSoon(0.5)
end

function ExtractionUI.OnExtractionFail(reason)
    if not frame:IsShown() then return end
    SetStatus("|cffff0000" .. (reason or "Extraction failed.") .. "|r")
    ExtractionUI.Refresh()
end

function ExtractionUI.OnApplySuccess()
    if not frame:IsShown() then return end
    local p = S.pending or {}
    SetStatus((p.link or "Your item") .. ": " .. (p.old and p.old.name or "no affix") .. " -> "
        .. (p.new and p.new.name or "new affix") .. ".")
    ExtractionUI.selectedAffixId = nil
    ExtractionService.RefreshAppliedCounts()
    RefreshSoon(0.5)
end

function ExtractionUI.OnApplyFail(reason)
    if not frame:IsShown() then return end
    SetStatus("|cffff0000" .. (reason or "Engraving failed.") .. "|r")
    ExtractionUI.Refresh()
end

function ExtractionUI.OnApplyCostReceived(cost)
    if frame:IsShown() then ExtractionUI.Refresh() end
end

function ExtractionUI.OnLearnedAffixesReceived()
    if frame:IsShown() then ExtractionUI.Refresh() end
end

------------------------------------------------------------
-- Show / hide, live updates
------------------------------------------------------------

local liveEvents = CreateFrame("Frame")
liveEvents:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
    RefreshSoon(0.1)
end)

frame:SetScript("OnShow", function()
    EnsureBuilt()
    SetStatus(nil)
    ExtractionUI.selectedAffixId = nil
    liveEvents:RegisterEvent("BAG_UPDATE")
    liveEvents:RegisterEvent("UNIT_INVENTORY_CHANGED")
    liveEvents:RegisterEvent("PLAYER_MONEY")
    ExtractionService.RequestLearnedAffixes()
    ExtractionUI.Refresh()
end)

frame:SetScript("OnHide", function()
    liveEvents:UnregisterAllEvents()
    ClearItem()
    SetStatus(nil)
    HideAffixList()
    CloseDropDownMenus()
    StaticPopup_Hide("EBONHOLD_CONFIRM_APPLY_AFFIX")
    StaticPopup_Hide("EBONHOLD_CONFIRM_EXTRACTION")
    StaticPopup_Hide("EBONHOLD_CONFIRM_LEGENDARY_UPGRADE")
    if isInExtractionGossip then
        isInExtractionGossip = false
        if GossipFrame then
            GossipFrame:SetAlpha(1)
            GossipFrame:EnableMouse(true)
            GossipFrame:ClearAllPoints()
            GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
        if GossipFrameCloseButton then
            GossipFrameCloseButton:Click()
        end
    end
end)

------------------------------------------------------------
-- Portable Affix-Anvil (the Toolbelt): the same window with no anvil gossip
-- behind it. The server accepts extraction, engraving and the Torment upgrade
-- anywhere for its owners (ToolbeltMgr::IsNearAffixAnvil).
------------------------------------------------------------

function ExtractionUI.Toggle()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

------------------------------------------------------------
-- Gossip-based open/close
------------------------------------------------------------

local gossipEventFrame = CreateFrame("Frame")
gossipEventFrame:RegisterEvent("GOSSIP_SHOW")
gossipEventFrame:RegisterEvent("GOSSIP_CLOSED")
gossipEventFrame:SetScript("OnEvent", function(self, event)
    if event == "GOSSIP_SHOW" then
        -- Only process if GossipFrame is actually visible (real gossip interaction)
        if not GossipFrame or not GossipFrame:IsShown() then
            return
        end

        local npcName = GossipFrameNpcNameText and GossipFrameNpcNameText:GetText()
        if npcName == "Enchanted Anvil" then
            isInExtractionGossip = true
            if GossipFrame then
                GossipFrame:SetAlpha(0)
                GossipFrame:EnableMouse(false)
                GossipFrame:ClearAllPoints()
                GossipFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 1000, -1000)
            end
            frame:Show()
        else
            if isInExtractionGossip then
                isInExtractionGossip = false
                frame:Hide()
            end
        end
    elseif event == "GOSSIP_CLOSED" then
        local wasInExtractionGossip = isInExtractionGossip
        isInExtractionGossip = false
        if wasInExtractionGossip and GossipFrame then
            GossipFrame:SetAlpha(1)
            GossipFrame:EnableMouse(true)
            GossipFrame:ClearAllPoints()
            GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
        if wasInExtractionGossip then
            frame:Hide()
        end
    end
end)

-- Close extraction when other UI panels open
local function CloseExtractionIfOpen()
    if frame and frame:IsShown() then
        -- Reset GossipFrame properly
        if GossipFrame then
            GossipFrame:SetAlpha(1)
            GossipFrame:EnableMouse(true)
            GossipFrame:ClearAllPoints()
            GossipFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
        isInExtractionGossip = false
        if GossipFrameCloseButton then
            GossipFrameCloseButton:Click()
        end
        frame:Hide()
    end
end

local framesToWatch = {
    "CharacterFrame",
    "TalentFrame",
    "SpellBookFrame",
    "QuestLogFrame",
    "QuestLogDetailFrame",
    "FriendsFrame",
    "PVPFrame",
    "AchievementFrame",
    "GuildFrame",
    "LFGParentFrame",
    "PlayerTalentFrame",
    "EbonholdTalentFrame",
    "LFDParentFrame",
    "WorldMapFrame",
    "GameMenuFrame",
}

for _, frameName in ipairs(framesToWatch) do
    local f = _G[frameName]
    if f then
        f:HookScript("OnShow", function(self)
            -- the quest tracker's invisible map pulse (alpha 0, two frames, after every quest
            -- accept / finished objective) is no panel opening: same fix as the Call Board
            if self:GetAlpha() < 0.05 then return end
            CloseExtractionIfOpen()
        end)
    end
end

------------------------------------------------------------
-- Global tooltip hook: affix lines
--   legacy  : @affix@ ... @affix@                      -> purple line
--   affix   : ... @value@3%@value@ @range@[1%-5%]@range@ -> orange line, blue value, grey range
-- On a two-handed weapon the numbers shown are doubled (x2 compensation), unless the
-- viewer has Titan Grip.
------------------------------------------------------------

local AFFIX_TAG = "@affix@"
local AFFIX_COLOR = "|cffb048f8" -- purple
local AFFIX_LINE  = "|cffff8000"    -- orange
local AFFIX_VALUE = "|cff4aa3ff"    -- blue  : the value this item rolled
local AFFIX_RANGE = "|cff9d9d9d"    -- grey  : the family's full range
local TITAN_GRIP_SPELL = 46917

local function ViewerHasTitanGrip()
    return IsSpellKnown and IsSpellKnown(TITAN_GRIP_SPELL) or false
end

local function DoubleNumbers(text)
    return (text:gsub("(%d+)([,%.]?)(%d*)", function(intPart, sep, frac)
        local v = tonumber(intPart .. (frac ~= "" and ("." .. frac) or ""))
        if not v then return intPart .. sep .. frac end
        v = v * 2
        if v == math.floor(v) then return tostring(math.floor(v)) end
        return (tostring(v):gsub("%.", sep ~= "" and sep or ","))
    end))
end

-- Renders one raw affix line. twoHanded doubles the numbers inside the markers.
function ExtractionUI.RenderAffixText(text, twoHanded)
    if not text or not text:find("@value@", 1, true) then return nil end
    -- Any colour code the client (or another addon) already put in the line would override
    -- ours from that point on: strip them, the whole line is repainted below.
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local doubled = twoHanded and not ViewerHasTitanGrip()
    text = text:gsub("@value@(.-)@value@", function(v)
        if doubled then v = DoubleNumbers(v) end
        return AFFIX_VALUE .. v .. "|r" .. AFFIX_LINE
    end)
    text = text:gsub("@range@(.-)@range@", function(r)
        if doubled then r = DoubleNumbers(r) end
        return AFFIX_RANGE .. r .. "|r" .. AFFIX_LINE
    end)
    return AFFIX_LINE .. text .. "|r"
end

local function ScanAndRecolorAffixLines(tooltip, twoHanded)
    local name = tooltip:GetName()
    for i = 1, tooltip:NumLines() do
        local leftLine = _G[name .. "TextLeft" .. i]
        if leftLine then
            local text = leftLine:GetText()
            if text and text:find("@value@", 1, true) then
                local rendered = ExtractionUI.RenderAffixText(text, twoHanded)
                if rendered then
                    leftLine:SetText(rendered)
                    leftLine:SetTextColor(1, 0.5, 0)
                    leftLine:SetWordWrap(true)
                    leftLine:SetWidth(300)
                end
            elseif text and text:find(AFFIX_TAG, 1, true) then
                local before, inner, after = text:match("^(.-)@affix@(.-)@affix@(.*)$")
                if inner then
                    local trimmed = inner:gsub("^%s+", ""):gsub("%s+$", "")
                    leftLine:SetText((before or "") .. AFFIX_COLOR .. trimmed .. "|r" .. (after or ""))
                    leftLine:SetTextColor(0.69, 0.28, 0.97)
                    leftLine:SetWordWrap(true)
                    leftLine:SetWidth(300)
                end
            end
        end
    end
end

local function OnItemTooltip(self)
    local _, link = self:GetItem()
    local twoHanded = false
    if link then
        local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
        twoHanded = equipLoc == "INVTYPE_2HWEAPON"
    end
    ScanAndRecolorAffixLines(self, twoHanded)
end

GameTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
ItemRefTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
-- Shift comparison ("currently equipped") tooltips are separate frames
for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
  local tip = _G[name]
  if tip then tip:HookScript("OnTooltipSetItem", OnItemTooltip) end
end
-- Anvil list and spellbook: the learn spell's description carries the same markers
GameTooltip:HookScript("OnTooltipSetSpell", function(self) ScanAndRecolorAffixLines(self, false) end)
ItemRefTooltip:HookScript("OnTooltipSetSpell", function(self) ScanAndRecolorAffixLines(self, false) end)
