-- Onglet Metiers du grimoire : tous les metiers, en grille de cases sur deux colonnes.
--
-- Le grimoire patche (FrameXML du client, SpellBookFrame.xml) n'a que 2 cases pour les
-- metiers principaux (PrimaryProfession1/2) et 3 pour les secondaires. Avec 3 metiers
-- principaux ou plus, PrimaryProfession_Update en montre 2 pris au hasard (pairs sur une
-- table par nom). On ne touche pas au client : on cache ces 5 cases et on pose les notres
-- dans SpellBookProfessionFrame, sur la page de parchemin nue (Spellbook-Page-1/2) au lieu
-- de la page a cases dessinees (Professions-Book-Left/Right).
--
-- Une case = un bouton securise (SecureActionButtonTemplate, type "spell") : un clic ouvre
-- la fenetre du metier, meme en combat. Shift-clic = lien dans le chat, glisser = sort sur
-- la barre d'action. Les cases et leurs attributs ne bougent que hors combat ; en combat on
-- ne met a jour que les barres et les textes, le reste attend PLAYER_REGEN_ENABLED.
--
-- Tous les metiers sont montres ; un metier pas appris est gris, "Not learned" a la place de
-- la barre, pas de clic. Herbalism et Skinning appris n'ont pas de fenetre : pas de clic. L'action liee (Disenchant, Milling, Prospecting) est une petite icone
-- en haut a droite de la case ; le pistage (Find Minerals / Herbs / Fish) en haut du livre.

local L, T = ProjectEbonhold.L, ProjectEbonhold.T
local CONTENT_X, CONTENT_Y = 105, -79   -- coin haut gauche du contenu, dans SpellBookFrame
local CONTENT_W = 396
local COL_GAP, ROW_GAP = 6, 4
local TILE_W = (CONTENT_W - COL_GAP) / 2
local TILE_H = 40
local HEADER_H = 20
local BAR_W = 95                        -- largeur du gabarit d'origine
local MAX_TILES = 16                    -- 11 principaux + 3 secondaires, avec de la marge

local INK = { 0.16, 0.10, 0.05 }        -- texte sur le parchemin
local INK_LIGHT = { 0.42, 0.28, 0.15 }  -- en-tetes
local INK_GREY = { 0.50, 0.42, 0.32 }   -- metiers pas appris

-- skill = nom de la ligne de competence (client enUS). open = sorts qui ouvrent la fenetre
-- (tous les rangs, ceux du grimoire patche), sub = action liee, icon = icone imposee
-- (sinon celle du sort open). Le sort retenu est le plus haut rang present dans le
-- grimoire du joueur ; on le lance par son numero (SECURE_ACTIONS.spell du client accepte
-- un id -> CastSpellByID), jamais par son nom.
local PRIMARY = {
    ["Alchemy"]        = { open = { 2259, 3101, 3464, 11611, 28596, 51304 } },
    ["Blacksmithing"]  = { open = { 2018, 3100, 3538, 9785, 29844, 51300 } },
    ["Enchanting"]     = { open = { 7411, 7412, 7413, 13920, 28029, 51313 }, sub = { 13262 } },
    ["Engineering"]    = { open = { 4036, 4037, 4038, 12656, 30350, 51306 } },
    ["Herbalism"]      = { icon = "Interface\\Icons\\Trade_Herbalism",
                           names = { "Herboristerie", "Kräuterkunde", "Herboristería", "Травничество" } },
    ["Inscription"]    = { open = { 45357, 45358, 45359, 45360, 45361, 45363 }, sub = { 51005 } },
    ["Jewelcrafting"]  = { open = { 25229, 25230, 28894, 28895, 28897, 51311 }, sub = { 31252 } },
    ["Leatherworking"] = { open = { 2108, 3104, 3811, 10662, 32549, 51302 } },
    ["Mining"]         = { open = { 2656 }, icon = "Interface\\Icons\\Trade_Mining", line = 2575 },  -- Smelting
    -- esES : la competence s'appelle "Desollar", le sort 8613 "Desuello" -> deux cases sans names.
    ["Skinning"]       = { icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", line = 8613, names = { "Desollar" } },
    ["Tailoring"]      = { open = { 3908, 3909, 3910, 12180, 26790, 51309 } },
}
local SECONDARY = {
    ["Cooking"]   = { open = { 2550, 3102, 3413, 18260, 33359, 51296 }, order = 1 },
    ["First Aid"] = { open = { 3273, 3274, 7924, 10846, 27028, 45542 }, order = 2 },
    ["Fishing"]   = { open = { 7620, 7731, 7732, 18248, 33095, 51294 }, order = 3 },
}
local TRACKING = { { 2580 }, { 2383 }, { 43308 } }  -- Find Minerals, Find Herbs, Find Fish

local panel, emptyText, primaryHeader, secondaryHeader
local tiles, trackButtons = {}, {}
local pendingLayout = false
local hiddenStock = false

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

-- Sorts du grimoire du joueur : id -> case du grimoire, et nom -> id (secours pour un
-- rang dont l'id n'est pas dans nos listes). Relu a chaque mise a jour, comme le fait
-- SpellBookFrame_UpdateSpellRender. (Le test par nom, GetSpellInfo(nom), laissait
-- Cooking et Fishing gris alors qu'ils etaient appris.)
local knownByID, knownByName = {}, {}

local function ScanSpellBook()
    wipe(knownByID); wipe(knownByName)
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        for slot = offset + 1, offset + numSpells do
            local link = GetSpellLink(slot, BOOKTYPE_SPELL)
            local id = link and tonumber(link:match("|Hspell:(%d+)"))
            if id then
                knownByID[id] = slot
                local name = GetSpellInfo(id)
                if name then knownByName[name] = id end
            end
        end
    end
end

-- Plus haut rang connu d'une liste d'ids (ou, a defaut, un sort du grimoire du meme nom).
local function KnownSpell(list)
    if not list then return nil end
    for k = #list, 1, -1 do
        if knownByID[list[k]] then return list[k] end
    end
    local name = GetSpellInfo(list[1])
    return name and knownByName[name] or nil
end

local function RankTitle(maxRank)
    local title = ""
    for _, r in ipairs(PROFESSION_RANKS or {}) do
        if maxRank < r[1] then break end
        title = r[2]
    end
    return title
end

-- Pas de SetShown sur 3.3.5.
local function ShowIf(obj, cond) if cond then obj:Show() else obj:Hide() end end

local function SetInk(fs, c) fs:SetTextColor(c[1], c[2], c[3]); fs:SetShadowColor(0, 0, 0, 0) end

-- Tous les metiers, appris ou non (learned = false : case grise "Not learned"), dans
-- l'ordre d'affichage : principaux par ordre alphabetique, puis Cooking / First Aid / Fishing.
-- Un metier principal inconnu de nos tables mais appris (isAbandonable) est ajoute aussi.
local function CollectProfessions()
    -- GetSkillLineInfo renvoie le nom dans la langue du client ("Alchimie" sur un client
    -- frFR) : chaque metier est aussi range sous son nom local, lu sur un sort qui porte le
    -- meme nom que la competence (le sort du metier ; Mining / Skinning : line ; Herbalism
    -- n'en a pas, ses noms locaux sont dans names). Sans ca un client non anglais voyait
    -- chaque metier deux fois, la copie apprise sans sort a lancer (pas de clic).
    local primary, secondary, byName = {}, {}, {}
    local function index(name, def, list)
        local e = { skill = name, label = name, def = def }
        byName[name] = e; tinsert(list, e)
        local lineID = def.line or (def.open and def.open[1])
        local localName = lineID and GetSpellInfo(lineID)
        if localName then byName[localName] = e; e.label = localName end
        for _, n in ipairs(def.names or {}) do byName[n] = e end
    end
    for name, def in pairs(PRIMARY) do index(name, def, primary) end
    for name, def in pairs(SECONDARY) do index(name, def, secondary) end
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, maxRank, isAbandonable = GetSkillLineInfo(i)
        if name and not isHeader then
            local e = byName[name]
            if not e and isAbandonable then
                e = { skill = name, def = {} }
                byName[name] = e; tinsert(primary, e)
            end
            if e then e.learned = true; e.rank = rank; e.maxRank = maxRank; e.label = name end
        end
    end
    table.sort(primary, function(a, b) return a.label < b.label end)
    table.sort(secondary, function(a, b) return a.def.order < b.def.order end)
    ScanSpellBook()
    for _, list in ipairs({ primary, secondary }) do
        for _, e in ipairs(list) do
            if e.learned then
                e.openID = KnownSpell(e.def.open)
                e.subID = KnownSpell(e.def.sub)
            end
            local icon = e.def.icon
            if not icon and e.def.open then icon = select(3, GetSpellInfo(e.def.open[1])) end
            e.icon = icon or "Interface\\Icons\\INV_Scroll_04"
        end
    end
    return primary, secondary
end

local function CountLearned(list)
    local n = 0
    for _, e in ipairs(list) do if e.learned then n = n + 1 end end
    return n
end

------------------------------------------------------------
-- Tooltips, liens, glisser
------------------------------------------------------------

local function SpellTooltip(self, spellID)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local link = spellID and GetSpellLink(spellID)
    if link then GameTooltip:SetHyperlink(link) end
    return link ~= nil
end

local function Tile_OnEnter(self)
    local e = self.entry
    if not e then return end
    if not e.learned then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.label or e.skill, 1, 1, 1)
        GameTooltip:AddLine(L["Not learned"], 1, 0.25, 0.25)
        GameTooltip:AddLine(L["Visit a trainer to learn this profession."], 0.8, 0.8, 0.8, true)
        -- Metier principal seulement : les secondaires n'ont pas de limite. Les places en plus
        -- viennent des nodes Jack of All Trades (sorts 101640-101648, Player::InitPrimaryProfessions).
        if PRIMARY[e.skill] then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["The number of main professions you can learn is limited. Jack of All Trades nodes in the Skill Tree unlock more profession slots."], 0.25, 1, 0.25, true)
        end
        GameTooltip:Show()
        return
    end
    if not SpellTooltip(self, e.openID) then
        GameTooltip:AddLine(e.label or e.skill, 1, 1, 1)
    end
    GameTooltip:AddLine(string.format("%s  %d / %d", RankTitle(e.maxRank), e.rank, e.maxRank), 1, 0.82, 0)
    GameTooltip:Show()
end

local function Sub_OnEnter(self)
    if SpellTooltip(self, self.spellID) then GameTooltip:Show() end
end

local function PostClick_Link(self)
    local id = self.spellID
    if id and IsModifiedClick("CHATLINK") then
        local spellLink, tradeLink = GetSpellLink(id)
        ChatEdit_InsertLink(tradeLink or spellLink)
    end
end

-- Glisser : par la case du grimoire (PickupSpell(slot, "spell")), comme un bouton de sort.
local function OnDragStart_Pickup(self)
    local slot = self.spellID and knownByID[self.spellID]
    if slot then PickupSpell(slot, BOOKTYPE_SPELL) end
end

------------------------------------------------------------
-- Construction (une seule fois, hors combat)
------------------------------------------------------------

local function SecureSpellButton(parent, name)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetAttribute("shift-type1", "none")   -- shift-clic : lien seulement (PostClick)
    b:SetScript("PostClick", PostClick_Link)
    b:SetScript("OnDragStart", OnDragStart_Pickup)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function IconBorder(parent, tex)
    local border = parent:CreateTexture(nil, "BACKGROUND")
    border:SetTexture(0.23, 0.14, 0.06, 1)
    border:SetPoint("TOPLEFT", tex, -1, 1)
    border:SetPoint("BOTTOMRIGHT", tex, 1, -1)
end

local function CreateTile(i)
    local t = SecureSpellButton(panel, "EbonholdProfessionTile" .. i)
    t:SetSize(TILE_W, TILE_H)
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    t:SetBackdropColor(1, 0.94, 0.82, 0.22)
    t:SetBackdropBorderColor(0.35, 0.23, 0.12, 0.35)
    t:SetScript("OnEnter", Tile_OnEnter)

    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(1, 0.9, 0.6, 0.18)
    hl:SetAllPoints()

    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(28, 28)
    t.icon:SetPoint("LEFT", 6, 0)
    IconBorder(t, t.icon)

    t.name = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.name:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 7, -1)
    t.name:SetJustifyH("LEFT")

    -- La barre du grimoire d'origine (ProfessionStatusBarTemplate, SpellBookFrame.xml) :
    -- fond et embouts de ProfessionsBook, texte rankText ; l'embout droit (capRight) ne
    -- s'allume qu'au maximum, comme dans PrimaryProfession_Update.
    -- Il lui faut un nom : ses textures s'accrochent a "$parent", et sans nom "$parent"
    -- devenait la case elle-meme -> fond et embouts etires sur toute la largeur de la case.
    local bar = CreateFrame("StatusBar", "EbonholdProfessionTile" .. i .. "Bar", t, "ProfessionStatusBarTemplate")
    bar:SetWidth(BAR_W)
    bar:SetPoint("BOTTOMLEFT", t.icon, "BOTTOMRIGHT", 21, -3)
    bar:EnableMouse(false)
    bar.text = bar.rankText
    t.bar = bar

    -- A la place de la barre pour un metier pas appris.
    t.status = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.status:SetPoint("BOTTOMLEFT", t.icon, "BOTTOMRIGHT", 7, 1)
    t.status:SetText(L["Not learned"])
    t.status:SetTextColor(0.55, 0.12, 0.08)
    t.status:SetShadowColor(0, 0, 0, 0)
    t.status:Hide()

    local sub = SecureSpellButton(t, "EbonholdProfessionTile" .. i .. "Sub")
    sub:SetSize(18, 18)
    sub:SetPoint("TOPRIGHT", -5, -9)
    sub:SetFrameLevel(t:GetFrameLevel() + 2)
    sub.icon = sub:CreateTexture(nil, "ARTWORK")
    sub.icon:SetAllPoints()
    IconBorder(sub, sub.icon)
    sub:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    sub:SetScript("OnEnter", Sub_OnEnter)
    t.sub = sub

    t:Hide()
    return t
end

local function CreateHeader()
    local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetJustifyH("LEFT")
    SetInk(h, INK_LIGHT)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetTexture(0.35, 0.23, 0.12, 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2)
    line:SetWidth(CONTENT_W)
    h.line = line
    return h
end

local function Build()
    panel = CreateFrame("Frame", "EbonholdProfessionBook", SpellBookProfessionFrame)
    panel:SetPoint("TOPLEFT", SpellBookFrame, "TOPLEFT", CONTENT_X, CONTENT_Y)
    panel:SetSize(CONTENT_W, 400)
    panel:SetFrameLevel(SpellBookProfessionFrame:GetFrameLevel() + 5)

    primaryHeader = CreateHeader()
    secondaryHeader = CreateHeader()

    emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("TOP", panel, "TOP", 0, -60)
    emptyText:SetText(L["Visit a trainer to learn a profession."])
    SetInk(emptyText, INK)
    emptyText:Hide()

    for i = 1, MAX_TILES do tiles[i] = CreateTile(i) end

    for i, list in ipairs(TRACKING) do
        local b = SecureSpellButton(panel, "EbonholdProfessionTrack" .. i)
        b:SetSize(20, 20)
        b:SetPoint("TOPRIGHT", SpellBookFrame, "TOPRIGHT", -52 - (#TRACKING - i) * 24, -51)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        IconBorder(b, b.icon)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.active = b:CreateTexture(nil, "OVERLAY")
        b.active:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b.active:SetBlendMode("ADD")
        b.active:SetAllPoints()
        b:SetScript("OnEnter", Sub_OnEnter)
        b.candidates = list
        b:Hide()
        trackButtons[i] = b
    end

    panel:SetScript("OnShow", function() ProjectEbonhold.ProfessionBook.Refresh() end)
end

------------------------------------------------------------
-- Mise a jour
------------------------------------------------------------

local function FillVisuals(t, e)
    -- Gris = pas appris. Un metier de recolte appris (Herbalism, Skinning) garde ses
    -- couleurs ; il n'a juste pas de fenetre a ouvrir.
    local learned = e.learned == true
    t.icon:SetTexture(e.icon)
    t.icon:SetDesaturated(not learned)
    t.icon:SetAlpha(learned and 1 or 0.6)
    t.name:SetText(e.label or e.skill)
    SetInk(t.name, learned and INK or INK_GREY)
    ShowIf(t.bar, learned)
    ShowIf(t.status, not learned)
    if not learned then return end
    t.bar:SetMinMaxValues(0, math.max(e.maxRank, 1))
    t.bar:SetValue(e.rank)
    t.bar.text:SetFormattedText("%d/%d", e.rank, e.maxRank)
    t.bar.text:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
    ShowIf(t.bar.capRight, e.rank >= e.maxRank)
    if e.subID then t.sub.icon:SetTexture(select(3, GetSpellInfo(e.subID))) end
end

local function UpdateTrackingState()
    local active = {}
    for i = 1, GetNumTrackingTypes() do
        local name, _, isActive = GetTrackingInfo(i)
        if name and isActive then active[name] = true end
    end
    for _, b in ipairs(trackButtons) do
        local name = b.spellID and GetSpellInfo(b.spellID)
        ShowIf(b.active, name ~= nil and active[name] == true)
    end
end

-- Placement complet : seulement hors combat (Show/Hide et attributs de boutons securises).
local function Layout(primary, secondary)
    local y = 0
    local n = 0
    local function place(list, header, label)
        if #list == 0 then header:Hide(); header.line:Hide(); return end
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
        header:SetText(ProjectEbonhold.Upper(label) .. "  |cff806a52" .. CountLearned(list) .. " / " .. #list .. "|r")
        header:Show(); header.line:Show()
        y = y + HEADER_H
        for k, e in ipairs(list) do
            n = n + 1
            local t = tiles[n]
            if not t then return end
            local col = (k - 1) % 2
            local row = math.floor((k - 1) / 2)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", panel, "TOPLEFT", col * (TILE_W + COL_GAP), -(y + row * (TILE_H + ROW_GAP)))
            t.entry = e
            t.spellID = e.openID
            t:SetAttribute("type", e.openID and "spell" or nil)
            t:SetAttribute("spell", e.openID)
            t.sub.spellID = e.subID
            t.sub:SetAttribute("type", e.subID and "spell" or nil)
            t.sub:SetAttribute("spell", e.subID)
            ShowIf(t.sub, e.subID ~= nil)
            FillVisuals(t, e)
            t:Show()
        end
        y = y + math.ceil(#list / 2) * (TILE_H + ROW_GAP) + 4
    end
    place(primary, primaryHeader, L["Main Professions"])
    place(secondary, secondaryHeader, L["Secondary Skills"])
    for i = n + 1, MAX_TILES do
        tiles[i].entry = nil
        tiles[i]:Hide()
    end
    ShowIf(emptyText, n == 0)

    for _, b in ipairs(trackButtons) do
        local id = KnownSpell(b.candidates)
        b.spellID = id
        b:SetAttribute("type", id and "spell" or nil)
        b:SetAttribute("spell", id)
        if id then b.icon:SetTexture(select(3, GetSpellInfo(id))) end
        ShowIf(b, id ~= nil)
    end
    UpdateTrackingState()
end

local function HideStockSlots()
    if hiddenStock or InCombatLockdown() then return end
    for _, name in ipairs({ "PrimaryProfession1", "PrimaryProfession2",
                            "SecondaryProfession1", "SecondaryProfession2", "SecondaryProfession3" }) do
        local f = _G[name]
        if f then f:Hide() end
    end
    hiddenStock = true
end

-- force : placer meme si l'onglet est ferme (connexion), pour que la premiere ouverture
-- en combat ait deja ses cases.
local function Refresh(force)
    if not panel then return end
    if not force and not panel:IsVisible() then pendingLayout = true; return end
    local primary, secondary = CollectProfessions()
    if InCombatLockdown() then
        -- Barres et textes seulement, sur les cases deja en place pour le meme metier.
        local byName = {}
        for _, e in ipairs(primary) do byName[e.skill] = e end
        for _, e in ipairs(secondary) do byName[e.skill] = e end
        for _, t in ipairs(tiles) do
            local e = t.entry and byName[t.entry.skill]
            if e then t.entry = e; FillVisuals(t, e) end
        end
        UpdateTrackingState()
        pendingLayout = true
        return
    end
    HideStockSlots()
    Layout(primary, secondary)
    pendingLayout = false
end

-- Page de parchemin nue sur l'onglet Metiers : la page d'origine dessine 2 grandes cases
-- et 3 petites qui ne correspondent plus a rien.
local function ApplyPageTextures()
    if SpellBookFrame.bookType == BOOKTYPE_PROFESSION then
        SpellBookPage1:SetTexture("Interface\\Spellbook\\Spellbook-Page-1")
        SpellBookPage2:SetTexture("Interface\\Spellbook\\Spellbook-Page-2")
    end
end

------------------------------------------------------------
-- Init
------------------------------------------------------------

-- Metiers appris qui ouvrent une fenetre de metier, pour les onglets de la fenetre des
-- metiers (tradeSkill/trade_skill_frame.lua). Lu par les ids du grimoire, pas par les noms
-- de competence : marche sur tout client, quelle que soit sa langue. Fishing lance la peche
-- (pas de fenetre), Herbalism / Skinning n'en ont pas. line = sort dont le nom est celui
-- que GetTradeSkillLine() renvoie (Smelting ouvre la fenetre "Mining").
local RUNEFORGING = { 53428 }
local MINING_LINE = 2575
local function OpenableProfessions()
    ScanSpellBook()
    local out = {}
    local function add(skill, def, order)
        if not def.open or skill == "Fishing" then return end
        local id = KnownSpell(def.open)
        if not id then return end
        local icon = def.icon or select(3, GetSpellInfo(id))
        local line = GetSpellInfo(skill == "Mining" and MINING_LINE or id)
        tinsert(out, { skill = skill, spellID = id, icon = icon, line = line, order = order })
    end
    for skill, def in pairs(PRIMARY) do add(skill, def, 0) end
    for skill, def in pairs(SECONDARY) do add(skill, def, def.order) end
    add("Runeforging", { open = RUNEFORGING }, 9)
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.skill < b.skill
    end)
    return out
end

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.ProfessionBook = { Refresh = Refresh, OpenableProfessions = OpenableProfessions }

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if not (SpellBookProfessionFrame and SpellBookFrame and BOOKTYPE_PROFESSION) then return end
        Build()
        HideStockSlots()
        Refresh(true)
        hooksecurefunc("SpellBookFrame_Update", ApplyPageTextures)
        self:RegisterEvent("SKILL_LINES_CHANGED")
        self:RegisterEvent("LEARNED_SPELL_IN_TAB")
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterEvent("MINIMAP_UPDATE_TRACKING")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if event == "MINIMAP_UPDATE_TRACKING" then
        if panel:IsVisible() then UpdateTrackingState() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        HideStockSlots()
        if not pendingLayout then return end
    end
    Refresh()
end)
