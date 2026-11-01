-- Onglets de la feuille de personnage.
--
-- La reputation n'a plus d'effet sur Ashendor (2026-09-15 : vendeurs en or, plus de
-- rang requis nulle part). L'onglet Reputation de la feuille de personnage disparait
-- donc, sans toucher au FrameXML : le bouton reste declare (PanelTemplates itere
-- CharacterFrameTab1..5), on le cache, et l'onglet Competences prend sa place.
--
-- Le FrameXML custom (PetPaperDollFrame_UpdateIsAvailable) cache l'onglet Familier
-- quand le joueur n'en a pas et recolle CharacterFrameTab3 sur Tab1 ; comme Tab3 est
-- desormais cache, c'est Tab4 qu'on recolle a sa place, apres lui.

local TAB_PETS, TAB_REPUTATION, TAB_SKILLS = CharacterFrameTab2, CharacterFrameTab3, CharacterFrameTab4
if not (TAB_PETS and TAB_REPUTATION and TAB_SKILLS) then return end

-- Meme decalage que l'ancre d'origine de CharacterFrame.xml (-15 entre deux onglets).
local TAB_OVERLAP = -15

local function HideReputationTab()
    TAB_REPUTATION:Hide()
end

local function AnchorSkillsTab()
    TAB_SKILLS:ClearAllPoints()
    if TAB_PETS:IsShown() then
        TAB_SKILLS:SetPoint("LEFT", TAB_PETS, "RIGHT", TAB_OVERLAP, 0)
    else
        -- sans familier Tab2 est cache mais garde sa geometrie : on prend sa place
        TAB_SKILLS:SetPoint("LEFT", TAB_PETS, "LEFT", 0, 0)
    end
end

HideReputationTab()
TAB_REPUTATION:HookScript("OnShow", HideReputationTab)
AnchorSkillsTab()
hooksecurefunc("PetPaperDollFrame_UpdateIsAvailable", AnchorSkillsTab)

-- ToggleCharacter("ReputationFrame") est le seul point d'entree du panneau : raccourci
-- TOGGLECHARACTER2 (Bindings.xml) et clic sur la barre de reputation. Il ne fait plus rien.
local ToggleCharacter_Orig = ToggleCharacter
function ToggleCharacter(tab)
    if tab == "ReputationFrame" then return end
    return ToggleCharacter_Orig(tab)
end

-- CharacterFrame_TabBoundsCheck (FrameXML, appele a l'OnShow de chaque onglet) additionne
-- la largeur des cinq onglets pour decider s'il faut retrecir les textes ; l'onglet cache
-- ne doit plus compter, sinon les autres retrecissent pour une place vide. Copie de
-- l'original avec ce seul filtre.
local NUM_TABS, MAX_WIDTH = 5, 465
local sorted = {}
function CharacterFrame_TabBoundsCheck(self)
    if string.sub(self:GetName(), 1, 17) ~= "CharacterFrameTab" then return end
    local totalSize = 60
    for i = 1, NUM_TABS do
        local tab = _G["CharacterFrameTab" .. i]
        _G["CharacterFrameTab" .. i .. "Text"]:SetWidth(0)
        PanelTemplates_TabResize(tab, 0)
        if tab:IsShown() then
            totalSize = totalSize + tab:GetWidth()
        end
    end
    local diff = totalSize - MAX_WIDTH
    if diff > 0 and CharacterFrameTab5:IsShown() and TAB_PETS:IsShown() then
        for i = 1, NUM_TABS do sorted[i] = _G["CharacterFrameTab" .. i] end
        table.sort(sorted, function(a, b) return a:GetWidth() > b:GetWidth() end)
        local i = 1
        while diff > 0 and i <= NUM_TABS do
            if sorted[i]:IsShown() then
                local text = _G[sorted[i]:GetName() .. "Text"]
                local change = math.min(10, diff)
                text:SetWidth(text:GetWidth() - change)
                diff = diff - change
                PanelTemplates_TabResize(sorted[i], 0)
            end
            i = i + 1
        end
    end
end
