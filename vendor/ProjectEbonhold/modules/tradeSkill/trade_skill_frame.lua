-- Fenetre des metiers agrandie + barre de recherche.
--
-- Blizzard_TradeSkillUI est charge a la demande (premiere ouverture d'un metier) : tout
-- se branche sur son ADDON_LOADED. La fenetre d'origine fait 350 x 437 utiles, liste de
-- 8 lignes au-dessus des details. Ici : liste a gauche (meme geometrie qu'a l'origine,
-- mais 22 lignes), details a droite, dans le meme cadre que le Journal des Echos (la
-- fenetre Collections : ezCollectionsPortraitFrameTemplate + InsetFrameTemplate).
--
-- Recherche : l'origine a deja un petit champ (TradeSkillFrameEditBox), mais
-- TradeSkillFrame_Update le cache tant que le metier est sous 75 ET remet le filtre de
-- nom a vide a chaque rafraichissement. On le remplace par le champ de recherche commun
-- de l'addon (Journal des Echos, arbre, banque), et TradeSkillFrame_Update par une copie
-- de l'original sans ce blocage.

local ROWS = 22                 -- lignes de recettes visibles (8 a l'origine)
local ROW_H = 16                -- TRADE_SKILL_HEIGHT
local LIST_TOP = -120           -- haut de la liste
local FRAME_W = 700
local FRAME_H = -LIST_TOP + ROWS * ROW_H + 18
local DETAIL_X = 366            -- colonne de droite
local DETAIL_TOP = -41
local BOTTOM_BAR = 50           -- place des boutons Creer / Quitter sous les details

local isSetUp = false
local searchBox
local lastSearch
local chrome                    -- le cadre Collections pose derriere la fenetre
local insets = {}               -- les deux panneaux marbres (liste, details)

-- Ordre d'affichage explicite : cadre (niveau N), panneaux (N+1), puis tous les
-- controles de Blizzard (N+2). A niveau egal le client ne garantit pas qui passe
-- devant, et les panneaux finissaient sous le fond de roche.
local function ApplyLayers()
    local base = TradeSkillFrame:GetFrameLevel()
    chrome:SetFrameLevel(base)
    for _, inset in ipairs(insets) do inset:SetFrameLevel(base + 1) end
    for _, child in ipairs({ TradeSkillFrame:GetChildren() }) do
        if child ~= chrome then child:SetFrameLevel(base + 2) end
    end
end

-- Le titre et le portrait vivent dans le cadre Collections : on y recopie le titre
-- que Blizzard ecrit dans TradeSkillFrameTitleText (cache), et l'icone du metier.
local function SyncChrome()
    if not chrome then return end
    chrome.TitleText:SetText(TradeSkillFrameTitleText:GetText())
    local skillLine = GetTradeSkillLine()
    -- GetSpellInfo par nom ne marche que pour un sort connu : metier d'un autre
    -- joueur (lien) -> portrait du joueur, comme l'origine
    local icon = skillLine and select(3, GetSpellInfo(skillLine))
    if icon then
        SetPortraitToTexture(chrome.portrait, icon)
    else
        SetPortraitTexture(chrome.portrait, "player")
    end
end

-- Meme lecture que TradeSkillFilter_OnTextChanged : "70-80" ou "~75" filtre sur le
-- niveau de l'objet, tout le reste sur le nom. Le client renvoie TRADE_SKILL_FILTER_UPDATE,
-- et c'est TradeSkillFrame_OnEvent qui rafraichit la liste et reprend la premiere recette.
local function ApplySearch(text)
    text = strtrim(text or "")
    if text == lastSearch then return end
    lastSearch = text

    local minLevel, maxLevel
    local approx = strmatch(text, "^~(%d+)$")
    if approx then
        minLevel, maxLevel = tonumber(approx) - 2, tonumber(approx) + 2
    else
        minLevel, maxLevel = strmatch(text, "^(%d+)%s*-*%s*(%d*)$")
        minLevel, maxLevel = tonumber(minLevel), tonumber(maxLevel)
    end
    if minLevel then
        if not maxLevel or maxLevel < minLevel then maxLevel = minLevel end
        SetTradeSkillItemNameFilter(nil)
        SetTradeSkillItemLevelFilter(minLevel, maxLevel)
    else
        SetTradeSkillItemLevelFilter(0, 0)
        SetTradeSkillItemNameFilter(text)
    end
end

-- Copie de TradeSkillFrame_Update (Blizzard_TradeSkillUI.lua, 3.3.5) ; seul le bloc
-- "rank < 75" change : l'ancien champ reste cache et le filtre n'est plus vide a chaque
-- rafraichissement, sinon la recherche ne marcherait pas sous 75.
local function TradeSkillFrame_Update_Ebonhold()
    local numTradeSkills = GetNumTradeSkills();
    local skillOffset = FauxScrollFrame_GetOffset(TradeSkillListScrollFrame);
    local name, rank, maxRank = GetTradeSkillLine();

    if ( CURRENT_TRADESKILL ~= name ) then
        StopTradeSkillRepeat();
        if ( CURRENT_TRADESKILL ~= "" ) then
            -- To fix problem with switching between two tradeskills
            UIDropDownMenu_Initialize(TradeSkillInvSlotDropDown, TradeSkillInvSlotDropDown_Initialize);
            UIDropDownMenu_SetSelectedID(TradeSkillInvSlotDropDown, 1);

            UIDropDownMenu_Initialize(TradeSkillSubClassDropDown, TradeSkillSubClassDropDown_Initialize);
            UIDropDownMenu_SetSelectedID(TradeSkillSubClassDropDown, 1);
        end
        CURRENT_TRADESKILL = name;
    end

    -- If no tradeskills
    if ( numTradeSkills == 0 ) then
        TradeSkillFrameTitleText:SetFormattedText(TRADE_SKILL_TITLE, GetTradeSkillLine());
        TradeSkillSkillName:Hide();
        TradeSkillSkillIcon:Hide();
        TradeSkillRequirementLabel:Hide();
        TradeSkillRequirementText:SetText("");
        TradeSkillCollapseAllButton:Disable();
        for i=1, MAX_TRADE_SKILL_REAGENTS, 1 do
            _G["TradeSkillReagent"..i]:Hide();
        end
    else
        TradeSkillSkillName:Show();
        TradeSkillSkillIcon:Show();
        TradeSkillCollapseAllButton:Enable();
    end

    TradeSkillFrameEditBox:Hide();
    SyncChrome();

    -- ScrollFrame update
    FauxScrollFrame_Update(TradeSkillListScrollFrame, numTradeSkills, TRADE_SKILLS_DISPLAYED, TRADE_SKILL_HEIGHT, nil, nil, nil, TradeSkillHighlightFrame, 293, 316 );

    TradeSkillHighlightFrame:Hide();
    local skillName, skillType, numAvailable, isExpanded, altVerb;
    local skillIndex, skillButton, skillButtonText, skillButtonCount;
    local nameWidth, countWidth;

    local skillNamePrefix = " ";
    for i=1, TRADE_SKILLS_DISPLAYED, 1 do
        skillIndex = i + skillOffset;
        skillName, skillType, numAvailable, isExpanded, altVerb = GetTradeSkillInfo(skillIndex);
        skillButton = _G["TradeSkillSkill"..i];
        skillButtonText = _G["TradeSkillSkill"..i.."Text"];
        skillButtonCount = _G["TradeSkillSkill"..i.."Count"];
        if ( skillIndex <= numTradeSkills ) then
            -- Set button widths if scrollbar is shown or hidden
            if ( TradeSkillListScrollFrame:IsShown() ) then
                skillButton:SetWidth(293);
            else
                skillButton:SetWidth(323);
            end
            local color = TradeSkillTypeColor[skillType];
            if ( color ) then
                skillButton:SetNormalFontObject(color.font);
                skillButtonCount:SetVertexColor(color.r, color.g, color.b);
                skillButton.r = color.r;
                skillButton.g = color.g;
                skillButton.b = color.b;
            end

            if ( ENABLE_COLORBLIND_MODE == "1" ) then
                skillNamePrefix = TradeSkillTypePrefix[skillType] or " ";
            end

            skillButton:SetID(skillIndex);
            skillButton:Show();
            -- Handle headers
            if ( skillType == "header" ) then
                skillButton:SetText(skillName);
                skillButtonText:SetWidth(TRADE_SKILL_TEXT_WIDTH);
                skillButtonCount:SetText("");
                if ( isExpanded ) then
                    skillButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up");
                else
                    skillButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up");
                end
                _G["TradeSkillSkill"..i.."Highlight"]:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight");
                _G["TradeSkillSkill"..i]:UnlockHighlight();
            else
                if ( not skillName ) then
                    return;
                end
                skillButton:SetNormalTexture("");
                _G["TradeSkillSkill"..i.."Highlight"]:SetTexture("");
                if ( numAvailable <= 0 ) then
                    skillButton:SetText(skillNamePrefix..skillName);
                    skillButtonText:SetWidth(TRADE_SKILL_TEXT_WIDTH);
                    skillButtonCount:SetText(skillCountPrefix);
                else
                    skillName = skillNamePrefix..skillName;
                    skillButtonCount:SetText("["..numAvailable.."]");
                    TradeSkillFrameDummyString:SetText(skillName);
                    nameWidth = TradeSkillFrameDummyString:GetWidth();
                    countWidth = skillButtonCount:GetWidth();
                    skillButtonText:SetText(skillName);
                    if ( nameWidth + 2 + countWidth > TRADE_SKILL_TEXT_WIDTH ) then
                        skillButtonText:SetWidth(TRADE_SKILL_TEXT_WIDTH-2-countWidth);
                    else
                        skillButtonText:SetWidth(0);
                    end
                end

                -- Place the highlight and lock the highlight state
                if ( GetTradeSkillSelectionIndex() == skillIndex ) then
                    TradeSkillHighlightFrame:SetPoint("TOPLEFT", "TradeSkillSkill"..i, "TOPLEFT", 0, 0);
                    TradeSkillHighlightFrame:Show();
                    skillButtonCount:SetVertexColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
                    skillButton:LockHighlight();
                    skillButton.isHighlighted = true;
                else
                    skillButton:UnlockHighlight();
                    skillButton.isHighlighted = false;
                end
            end

        else
            skillButton:Hide();
        end
    end

    -- Set the expand/collapse all button texture
    local numHeaders = 0;
    local notExpanded = 0;
    for i=1, numTradeSkills, 1 do
        local skillName, skillType, numAvailable, isExpanded, altVerb = GetTradeSkillInfo(i);
        if ( skillName and skillType == "header" ) then
            numHeaders = numHeaders + 1;
            if ( not isExpanded ) then
                notExpanded = notExpanded + 1;
            end
        end
        if ( GetTradeSkillSelectionIndex() == i ) then
            -- Set the max makeable items for the create all button
            TradeSkillFrame.numAvailable = math.abs(numAvailable);
        end
    end
    -- If all headers are not expanded then show collapse button, otherwise show the expand button
    if ( notExpanded ~= numHeaders ) then
        TradeSkillCollapseAllButton.collapsed = nil;
        TradeSkillCollapseAllButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up");
    else
        TradeSkillCollapseAllButton.collapsed = 1;
        TradeSkillCollapseAllButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up");
    end
end

-- Cache toutes les textures posees directement sur un cadre (l'habillage d'origine, fait
-- pour 384 px de large). Les enfants (boutons, barres de defilement) ne sont pas touches.
-- Bordure de qualite sur l'icone de l'objet fabrique (meme bordure fine que la
-- fenetre d'achat, item_purchase.lua). Pas d'objet (enchantement) : pas de bordure.
local itemBorder
local function UpdateItemBorder()
    if not itemBorder then return end
    local link = GetTradeSkillItemLink(GetTradeSkillSelectionIndex())
    if not (link and strfind(link, "|Hitem:")) then
        itemBorder:Hide()
        return
    end
    local r, g, b
    local _, _, quality = GetItemInfo(link)
    if quality then
        r, g, b = GetItemQualityColor(quality)
    else
        -- objet pas encore en cache : la couleur est deja dans le lien (|cffRRGGBB)
        local rh, gh, bh = strmatch(link, "|c%x%x(%x%x)(%x%x)(%x%x)")
        if not rh then itemBorder:Hide() return end
        r, g, b = tonumber(rh, 16) / 255, tonumber(gh, 16) / 255, tonumber(bh, 16) / 255
    end
    itemBorder:SetBackdropBorderColor(r, g, b, 1)
    itemBorder.glow:SetVertexColor(r, g, b)
    itemBorder:Show()
end

local function HideOwnTextures(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" then region:Hide() end
    end
end

local function BuildSearchBox(frame)
    local ok, box = pcall(CreateFrame, "EditBox", "TradeSkillFrameSearchBox", frame, "ezCollectionsSearchBoxTemplate")
    if ok and box and box.Instructions then
        box.Instructions:SetText(SEARCH)
    else
        -- gabarit introuvable : champ simple de la 3.3.5
        box = CreateFrame("EditBox", "TradeSkillFrameSearchBox", frame, "InputBoxTemplate")
        box:SetAutoFocus(false)
    end
    box:SetWidth(186)
    box:SetHeight(20)
    box:SetMaxLetters(40)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -62)

    -- HookScript : le gabarit a deja ses propres scripts (loupe, croix, texte gris).
    box:HookScript("OnTextChanged", function(self) ApplySearch(self:GetText()) end)
    box:HookScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function Setup()
    if isSetUp then return end
    local frame = TradeSkillFrame
    if not (frame and TradeSkillSkill1 and TradeSkillListScrollFrame and TradeSkillDetailScrollFrame) then return end
    isSetUp = true

    -- ---- cadre ----
    HideOwnTextures(frame)
    frame:SetWidth(FRAME_W)
    frame:SetHeight(FRAME_H)
    frame:SetHitRectInsets(0, 0, 0, 0)
    -- Couche HIGH, comme l'arbre de talents, le Call Board et le Journal. En MEDIUM elle
    -- partage la couche de la feuille de personnage, ouverte au meme endroit : les cases
    -- d'equipement et le modele, a des niveaux plus hauts que le fond, passaient au travers.
    frame:SetFrameStrata("HIGH")

    -- Fenetre libre : UIParent ne la place plus (c'est lui qui la collait a gauche a
    -- chaque ouverture). Sans entree UIPanelWindows, ShowUIPanel / HideUIPanel font un
    -- simple Show / Hide ; Echap passe par UISpecialFrames.
    UIPanelWindows["TradeSkillFrame"] = nil
    if frame:GetAttribute("UIPanelLayout-defined") then
        frame:SetAttribute("UIPanelLayout-area", nil)
    end
    tinsert(UISpecialFrames, "TradeSkillFrame")

    -- deplacable a la souris, position gardee d'une session a l'autre
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        ProjectEbonholdDB = ProjectEbonholdDB or {}
        ProjectEbonholdDB.tradeSkillFramePos = { point, relPoint, x, y }
    end)
    local pos = ProjectEbonholdDB and ProjectEbonholdDB.tradeSkillFramePos
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        -- premiere fois : a peu pres la place d'origine, portrait rond dans l'ecran
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -104)
    end

    -- Cadre du Journal des Echos (fond de roche, bordure, portrait rond, barre de
    -- titre). Les deux panneaux marbres sont ceux des colonnes du Journal. L'ordre
    -- d'affichage est pose par ApplyLayers, une fois tous les controles crees.
    chrome = CreateFrame("Frame", nil, frame, "ezCollectionsPortraitFrameTemplateNoCloseButton")
    chrome:SetAllPoints(frame)

    local listInset = CreateFrame("Frame", nil, chrome, "InsetFrameTemplate")
    listInset:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, LIST_TOP + 6)
    listInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", DETAIL_X - 12, 8)
    insets[1] = listInset

    local detailInset = CreateFrame("Frame", nil, chrome, "InsetFrameTemplate")
    detailInset:SetPoint("TOPLEFT", frame, "TOPLEFT", DETAIL_X - 6, DETAIL_TOP + 8)
    detailInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, BOTTOM_BAR - 8)
    insets[2] = detailInset

    -- le titre d'origine est recopie dans la barre de titre du cadre (SyncChrome)
    TradeSkillFrameTitleText:Hide()
    hooksecurefunc("TradeSkillFrame_SetSelection", SyncChrome)

    itemBorder = CreateFrame("Frame", nil, TradeSkillSkillIcon)
    itemBorder:SetPoint("TOPLEFT", TradeSkillSkillIcon, "TOPLEFT", -5, 5)
    itemBorder:SetPoint("BOTTOMRIGHT", TradeSkillSkillIcon, "BOTTOMRIGHT", 5, -5)
    itemBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    -- halo de la meme couleur autour de l'icone (bordure de bouton d'action en ADD,
    -- la texture n'occupe que le centre de son image, d'ou la taille x1.9)
    local glow = itemBorder:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.9)
    glow:SetWidth(TradeSkillSkillIcon:GetWidth() * 1.9)
    glow:SetHeight(TradeSkillSkillIcon:GetHeight() * 1.9)
    glow:SetPoint("CENTER", TradeSkillSkillIcon, "CENTER", 0, 0)
    itemBorder.glow = glow
    itemBorder:Hide()
    hooksecurefunc("TradeSkillFrame_SetSelection", UpdateItemBorder)

    -- meme place que le bouton du gabarit ezCollectionsPortraitFrameTemplate
    TradeSkillFrameCloseButton:ClearAllPoints()
    TradeSkillFrameCloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 4, 5)

    -- ---- colonne de gauche : niveau, recherche, filtres, liste ----
    -- a droite du portrait rond, qui deborde jusqu'a x = 55
    TradeSkillRankFrame:ClearAllPoints()
    TradeSkillRankFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -28)
    -- 10 px plus epaisse qu'a l'origine (14). Le cadre dore (256 x 32) n'occupe que les
    -- colonnes 2-254 et les lignes 6-24 de sa texture, le reste est vide : l'etirer en
    -- entier grossit surtout le vide. On le recadre sur sa partie visible et on le pose
    -- autour de la barre, 3 px de marge sur les cotes, 2 en haut et en bas.
    TradeSkillRankFrame:SetHeight(24)
    TradeSkillRankFrameBorder:SetTexCoord(2 / 256, 255 / 256, 6 / 32, 25 / 32)
    TradeSkillRankFrameBorder:ClearAllPoints()
    TradeSkillRankFrameBorder:SetPoint("TOPLEFT", TradeSkillRankFrame, "TOPLEFT", -3, 2)
    TradeSkillRankFrameBorder:SetPoint("BOTTOMRIGHT", TradeSkillRankFrame, "BOTTOMRIGHT", 3, -2)
    -- bouton "lien du metier" retire : TradeSkillFrame_SetSelection le re-affiche a
    -- chaque recette choisie, donc Show ne fait plus rien
    TradeSkillLinkButton:Hide()
    TradeSkillLinkButton.Show = TradeSkillLinkButton.Hide
    -- a l'origine le "123/450" est accroche sous le titre, qui est maintenant au centre
    TradeSkillRankFrameSkillRank:ClearAllPoints()
    TradeSkillRankFrameSkillRank:SetPoint("CENTER", TradeSkillRankFrame, "CENTER", 0, 0)

    searchBox = BuildSearchBox(frame)
    TradeSkillFrameEditBox:Hide()

    TradeSkillFrameAvailableFilterCheckButton:ClearAllPoints()
    TradeSkillFrameAvailableFilterCheckButton:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)

    TradeSkillExpandButtonFrame:ClearAllPoints()
    TradeSkillExpandButtonFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -89)
    -- memes positions horizontales qu'a l'origine (bord droit a 384 - 25)
    TradeSkillInvSlotDropDown:ClearAllPoints()
    TradeSkillInvSlotDropDown:SetPoint("TOPRIGHT", frame, "TOPLEFT", 359, -86)
    TradeSkillSubClassDropDown:ClearAllPoints()
    TradeSkillSubClassDropDown:SetPoint("RIGHT", TradeSkillInvSlotDropDown, "LEFT", 35, 0)

    TradeSkillSkill1:ClearAllPoints()
    TradeSkillSkill1:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, LIST_TOP)
    for i = 9, ROWS do
        local row = CreateFrame("Button", "TradeSkillSkill" .. i, frame, "TradeSkillSkillButtonTemplate")
        row:SetID(i)
        row:SetPoint("TOPLEFT", _G["TradeSkillSkill" .. (i - 1)], "BOTTOMLEFT", 0, 0)
        row:Hide()
    end
    TRADE_SKILLS_DISPLAYED = ROWS

    HideOwnTextures(TradeSkillListScrollFrame)
    TradeSkillListScrollFrame:ClearAllPoints()
    TradeSkillListScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 21, LIST_TOP)
    TradeSkillListScrollFrame:SetWidth(296)
    TradeSkillListScrollFrame:SetHeight(ROWS * ROW_H)

    -- ---- colonne de droite : details et boutons ----
    HideOwnTextures(TradeSkillDetailScrollFrame)
    local detailH = FRAME_H + DETAIL_TOP - BOTTOM_BAR
    TradeSkillDetailScrollFrame:ClearAllPoints()
    TradeSkillDetailScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", DETAIL_X, DETAIL_TOP)
    TradeSkillDetailScrollFrame:SetHeight(detailH)
    TradeSkillDetailScrollChildFrame:SetHeight(detailH - 10)

    -- Quitter en bas a droite ; Creer colle a sa gauche comme a l'origine (81 px
    -- d'entraxe). Creer tout / - / nombre / + suivent Creer par leurs propres ancres.
    TradeSkillCancelButton:ClearAllPoints()
    TradeSkillCancelButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 12)
    TradeSkillCreateButton:ClearAllPoints()
    TradeSkillCreateButton:SetPoint("RIGHT", TradeSkillCancelButton, "LEFT", -1, 0)

    ApplyLayers()

    -- ---- comportement ----
    TradeSkillFrame_Update = TradeSkillFrame_Update_Ebonhold

    -- Chaque ouverture repart sans filtre, comme l'ancien champ (son OnShow le vidait).
    frame:HookScript("OnShow", function()
        -- la fenetre est "toplevel" : un clic la remonte, on repose l'ordre a chaque ouverture
        ApplyLayers()
        lastSearch = nil
        searchBox:SetText("")
        ApplySearch("")
        SyncChrome()
    end)
    frame:HookScript("OnHide", function() searchBox:ClearFocus() end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, addon)
    if addon == "Blizzard_TradeSkillUI" then
        Setup()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
if IsAddOnLoaded("Blizzard_TradeSkillUI") then
    Setup()
    loader:UnregisterEvent("ADDON_LOADED")
end
