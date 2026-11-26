-- Feuille de personnage : toutes les categories de stats, l'une sous l'autre, dans une liste
-- qui defile.
--
-- Le FrameXML custom (PaperDollFrame_EnhancedStatsFrame, patch-D) ne montre que deux
-- categories a la fois, chacune choisie dans un menu deroulant (PaperDollFrameStatsFrame
-- Left/RightCategory). Ici les deux menus disparaissent : sous le niveau d'objet, les cinq
-- categories de PLAYERSTAT_DROPDOWN_OPTIONS s'empilent, chacune sous son titre, dans une zone
-- a barre de defilement laterale. La fenetre garde sa taille.
--
-- Les lignes sont des StatFrameTemplate remplies par UpdatePaperdollStats(prefixe, categorie),
-- la fonction du FrameXML : memes valeurs, memes infobulles, et les crochets de
-- versatility_paperdoll.lua / mastery_paperdoll.lua s'appliquent aussi.

local statsFrame = PaperDollFrameStatsFrame
local leftCategory = PaperDollFrameStatsFrameLeftCategory
local rightCategory = PaperDollFrameStatsFrameRightCategory
if not (statsFrame and leftCategory and rightCategory
        and type(UpdatePaperdollStats) == "function"
        and type(PLAYERSTAT_DROPDOWN_OPTIONS) == "table") then
    return
end

-- Meme pas que le FrameXML : titre de 40, lignes a 8 sous le titre, lignes de 15.
local HEADER_HEIGHT = 40
local HEADER_TO_ROWS = 8
local ROW_WIDTH, ROW_HEIGHT = 167, 15
local ROWS_PER_CATEGORY = 6
local CATEGORY_GAP = 2
-- Bloc du niveau d'objet en tete de liste : titre de 40 + CharacterItemLevelFrame (29), meme
-- place que dans le FrameXML (le premier menu etait 71 px sous le haut du titre).
local ITEM_LEVEL_BLOCK = 71
-- Zone de defilement : tout le panneau, du haut (y = -4, l'ancien titre du niveau d'objet)
-- jusqu'en bas, la barre a droite (UIPanelScrollFrameTemplate la pose hors du cadre, sur sa droite).
local SCROLL_TOP, SCROLL_LEFT, SCROLL_RIGHT, SCROLL_BOTTOM = -4, 6, -28, 6

-- Les deux menus deroulants et leurs 12 lignes (enfants des boutons) disparaissent.
leftCategory:Hide()
rightCategory:Hide()
leftCategory:HookScript("OnShow", leftCategory.Hide)
rightCategory:HookScript("OnShow", rightCategory.Hide)

local scroll = CreateFrame("ScrollFrame", "ProjectEbonholdStatsScroll", statsFrame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", SCROLL_LEFT, SCROLL_TOP)
scroll:SetPoint("BOTTOMRIGHT", statsFrame, "BOTTOMRIGHT", SCROLL_RIGHT, SCROLL_BOTTOM)

-- La barre de DragonUI (utils.UseDragonScrollBar, owner 2026-11-12), dans la colonne de l'ancienne.
utils.UseDragonScrollBar(scroll)

local child = CreateFrame("Frame", "ProjectEbonholdStatsScrollChild", scroll)
scroll:SetScrollChild(child)

-- Le niveau d'objet defile avec le reste : son titre passe dans la liste, en tete.
-- CharacterItemLevelFrame lui est deja accroche (PaperDollFrame_EnhancedStatsFrame) et suit.
-- Il est en strate HIGH dans le FrameXML : ramene a celle du panneau pour rester sous
-- les menus et etre coupe comme le reste par la zone de defilement.
local itemLevelCategory = PaperDollFrameStatsFrameItemLevelCategory
if itemLevelCategory then
    itemLevelCategory:SetParent(child)
    itemLevelCategory:ClearAllPoints()
    itemLevelCategory:SetPoint("TOP", child, "TOP", 0, 0)
    if CharacterItemLevelFrame then
        CharacterItemLevelFrame:SetFrameStrata(statsFrame:GetFrameStrata())
    end
end

-- Une categorie = un titre + ses lignes. Les cinq du FrameXML (6 lignes, remplies par
-- UpdatePaperdollStats), puis les resistances (5 lignes, copiees des MagicResFrame).
local categories = {}
local previous
local function AddCategory(prefix, titleText, rowCount)
    local header = CreateFrame("Frame", prefix .. "Header", child)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("LEFT", child, "LEFT")
    header:SetPoint("RIGHT", child, "RIGHT")
    if previous then
        header:SetPoint("TOP", previous, "BOTTOM", 0, -CATEGORY_GAP)
    else
        header:SetPoint("TOP", child, "TOP", 0, itemLevelCategory and -ITEM_LEVEL_BLOCK or 0)
    end
    local background = header:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOP")
    if background.SetAtlasTex then
        background:SetAtlasTex("UI-Character-Info-Title", true)
    else
        background:SetTexture(0, 0, 0, 0.5)
        background:SetHeight(HEADER_HEIGHT)
    end
    header.background = background
    local title = header:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("CENTER", 0, 1)
    title:SetText(titleText)

    local rows = {}
    for i = 1, rowCount do
        local row = CreateFrame("Frame", prefix .. i, child, "StatFrameTemplate")
        row:SetSize(ROW_WIDTH, ROW_HEIGHT)
        if i == 1 then
            row:SetPoint("TOP", header, "BOTTOM", 0, -HEADER_TO_ROWS)
        else
            row:SetPoint("TOP", rows[i - 1], "BOTTOM", 0, 0)
        end
        if row.Background and i % 2 == 0 then row.Background:Show() end
        rows[i] = row
    end

    local category = { prefix = prefix, header = header, rows = rows }
    categories[#categories + 1] = category
    previous = rows[rowCount]
    return category
end

for index, key in ipairs(PLAYERSTAT_DROPDOWN_OPTIONS) do
    AddCategory("ProjectEbonholdStat" .. index .. "_", _G[key] or key, ROWS_PER_CATEGORY).key = key
end

-- Resistances : les cinq MagicResFrame du FrameXML (ordre Arcane, Feu, Nature, Givre, Ombre,
-- id = ecole) restent la source ; PaperDollFrame_SetResistances les remplit, on recopie leur
-- valeur (deja coloree) et leur infobulle dans nos lignes.
local NUM_RESISTANCES = 5
local resistances = AddCategory("ProjectEbonholdStatRes_", "Resistances", NUM_RESISTANCES)

-- Icone de l'ecole devant chaque ligne : meme texture et memes coordonnees que les
-- MagicResFrame1..5 du FrameXML (Arcane, Feu, Nature, Givre, Ombre).
local RESISTANCE_ICONS = "Interface\\PaperDollInfoFrame\\UI-Character-ResistanceIcons"
local RESISTANCE_TEXCOORDS = {
    { 0.2265625, 0.33984375 },
    { 0, 0.11328125 },
    { 0.11328125, 0.2265625 },
    { 0.33984375, 0.453125 },
    { 0.453125, 0.56640625 },
}
for i, row in ipairs(resistances.rows) do
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(RESISTANCE_ICONS)
    icon:SetTexCoord(0, 1, RESISTANCE_TEXCOORDS[i][1], RESISTANCE_TEXCOORDS[i][2])
    icon:SetSize(ROW_HEIGHT - 1, ROW_HEIGHT - 1)
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    local label = _G[row:GetName() .. "Label"]
    label:ClearAllPoints()
    label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
end

local function RefreshResistances()
    for i = 1, NUM_RESISTANCES do
        local source = _G["MagicResFrame" .. i]
        local sourceText = _G["MagicResText" .. i]
        local row = resistances.rows[i]
        if source and sourceText then
            -- "Arcane Resistance" -> "Arcane" : l'icone et le titre de la categorie le disent deja.
            local name = (_G["RESISTANCE" .. source:GetID() .. "_NAME"] or ""):gsub("%s*[Rr]esistance%s*", "")
            _G[row:GetName() .. "Label"]:SetText(format(STAT_FORMAT, name))
            _G[row:GetName() .. "StatText"]:SetText(sourceText:GetText() or "0")
            row.tooltip = source.tooltip and (HIGHLIGHT_FONT_COLOR_CODE .. source.tooltip .. FONT_COLOR_CODE_CLOSE)
            row.tooltip2 = source.tooltipSubtext
            row:Show()
        else
            row:Hide()
        end
    end
end

local CONTENT_HEIGHT = 4 + (#categories - 1) * CATEGORY_GAP + (itemLevelCategory and ITEM_LEVEL_BLOCK or 0)
for _, category in ipairs(categories) do
    CONTENT_HEIGHT = CONTENT_HEIGHT + HEADER_HEIGHT + HEADER_TO_ROWS + #category.rows * ROW_HEIGHT
end

-- La largeur de la zone n'est connue qu'une fois le panneau dispose : le contenu la suit.
local function Layout()
    local width = scroll:GetWidth()
    if not width or width <= 0 then return end
    child:SetSize(width, CONTENT_HEIGHT)
    for _, category in ipairs(categories) do
        category.header.background:SetWidth(width)
    end
    if itemLevelCategory then
        itemLevelCategory:SetWidth(width)
        if itemLevelCategory.Background then itemLevelCategory.Background:SetWidth(width) end
    end
    scroll:UpdateScrollChildRect()
end
scroll:SetScript("OnSizeChanged", Layout)

local function RefreshStats()
    if not scroll:IsVisible() then return end
    for _, category in ipairs(categories) do
        if category.key then
            UpdatePaperdollStats(category.prefix, category.key)
        end
    end
    RefreshResistances()
end

hooksecurefunc("PaperDollFrame_UpdateStats", RefreshStats)
if type(PaperDollFrame_SetResistances) == "function" then
    hooksecurefunc("PaperDollFrame_SetResistances", RefreshResistances)
end
scroll:HookScript("OnShow", function()
    Layout()
    RefreshStats()
end)
