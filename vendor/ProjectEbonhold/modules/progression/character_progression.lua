-- Character Progression
-- Extends the NATIVE Collections window (CollectionsJournal) with more tabs
-- instead of building a separate frame: Echo Journal's own sub-tabs (merged
-- Echoes/Loadouts) and Skill Tree. Collections keeps its own
-- background/border/portrait; the other systems get reparented into it with
-- their own chrome hidden.
--
-- Tab layout on CollectionsJournal (6 total; 1-5 defined in
-- Blizzard_Collections.xml, tab 6 created below in Lua), left to right as
-- requested:
--   1 Echoes (merged My Echoes + All Echoes; loadout saving/switching lives
--   in its My Run panel footer, not a separate tab), 2 Skill Tree,
--   3 Transmogrify (embeds WardrobeFrame -- see below), 4 Mounts (native),
--   5 Companions (native), 6 Prestige (modules\prestige).
--
-- Transmogrify embeds the FULL WardrobeFrame (character model, slot buttons,
-- Apply button, cost), not just WardrobeCollectionFrame (the browsing grid
-- alone) -- the model/slots/apply UI live only in WardrobeFrame's own layout,
-- with WardrobeCollectionFrame as one piece of it. Embedding the grid alone
-- showed only the passive browse catalog, missing all the apply functionality.

local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}

-- UIParent.lua computes this from stock retail tab math (Mounts/Pets/Toys/
-- Heirlooms/Appearances = 1/2/3/4/5); several call sites in Blizzard_Wardrobe.lua
-- (chat-linked appearances, "Look Up Transmogrification" etc.) use it to jump
-- Collections to the Transmogrify tab. In this shell's 5-tab renumbering that's
-- id 3 -- override the global directly rather than patch every call site.
COLLECTIONS_JOURNAL_TAB_INDEX_APPEARANCES = 3

local HEADER_CLEARANCE = 40   -- vertical space to clear CollectionsJournal's own title/portrait
local BOTTOM_PADDING = 20
local SKILLTREE_TOP_CLEARANCE = 8    -- tighter than HEADER_CLEARANCE: less top padding, per request
local SKILLTREE_BOTTOM_PADDING = 0   -- tighter than BOTTOM_PADDING: less bottom padding, per request
local SKILLTREE_SIDE_PADDING = 6     -- tighter side margin around the widened frame
-- The merged Echoes tab (Echo Journal's internal TAB_ALL=2) is the only one
-- ever requested from here now -- Loadouts (TAB_LOADOUTS=3) is dead, its tab
-- removed; loadout saving/switching lives in the My Run panel's footer
-- instead (see UpdateLoadoutFooter in echo_journal.lua).
--
-- This is a total content budget for the window, not tied to the context
-- bar's height -- that varies internally (70-116px, slots+builder banner
-- when active) but the grid area just grows/shrinks to fill the rest, so
-- this value doesn't need to track it.
--
-- The math has to clear journalFrame's own fixed geometry: journalFrame is
-- ALWAYS 500 tall regardless of this value, anchored TOP at -HEADER_CLEARANCE,
-- so its bottom always sits at -(HEADER_CLEARANCE+500). The catalog/My Run
-- grids anchor BOTTOMRIGHT/BOTTOMLEFT to journalFrame's bottom with +18, i.e.
-- absolute y = -(HEADER_CLEARANCE+500)+18. For CollectionsJournal's own height
-- (contentH+HEADER_CLEARANCE+BOTTOM_PADDING) to actually reach that point
-- instead of cropping it, contentH must be >= 500-18-BOTTOM_PADDING = 462.
local ECHO_TAB_CONTENT_HEIGHT = { [2] = 480 }

-- CollectionsJournalPortraitButton / WardrobeFramePortraitButton exist to swap
-- between two ALTERNATIVE standalone windows (retail's old CollectionsJournal
-- <-> WardrobeFrame model). That model no longer applies now that everything
-- is one unified window with tabs -- clicking either while embedded triggers
-- HideUIPanel/ShowUIPanel calls that fight our reparenting and break the UI.
-- Permanently neutralize both regardless of which tab is active.
local function NeutralizePortraitButtons()
    for _, name in ipairs({ "CollectionsJournalPortraitButton", "WardrobeFramePortraitButton" }) do
        local btn = _G[name]
        if btn then
            btn:Hide()
            btn:EnableMouse(false)
            btn.UpdateVisibility = function() end
        end
    end
end

-- Tutorial hint boxes (CollectionsJournal.TransmogTabHelpBox / PortraitHelpBox)
-- are anchored to specific tab buttons by their OLD retail meaning (e.g.
-- TransmogTabHelpBox points at what USED to be the Transmogrify tab, now
-- Mounts after reordering) and render at DIALOG strata -- always on top
-- regardless of frame level, which is why one kept peeking out past the
-- window edge. Neither points at anything sensible anymore; hide both for good.
local function NeutralizeHelpBoxes()
    for _, name in ipairs({ "TransmogTabHelpBox", "PortraitHelpBox" }) do
        local box = CollectionsJournal and CollectionsJournal[name]
        if box then
            box:Hide()
            box:EnableMouse(false)
            box.Show = function() end
        end
    end
end

-- WardrobeTransmogFrame (the model/slots/apply content inside WardrobeFrame)
-- fires OnShow every time WardrobeFrame becomes visible -- and that OnShow
-- unconditionally calls HideUIPanel(CollectionsJournal), a leftover from the
-- old "two alternative windows" design. Since WardrobeFrame is now a CHILD of
-- CollectionsJournal, that call hides its own new parent (and drags the whole
-- embedded UI down with it) the instant this tab is shown -- root cause of
-- "clicking Transmogrify closes the whole frame". Replace the script handler
-- directly (not just the global function -- the XML `function=` binding may
-- have already captured the original reference at parse time) with the same
-- logic minus that one call.
if _G.WardrobeTransmogFrame then
    WardrobeTransmogFrame:SetScript("OnShow", function(self)
        ezCollections:SetCVar("petJournalTab", 3)  -- Transmogrify's id in this shell's renumbering
        CollectionsMicroButtonAlert:Hide()
        ezCollectionsMinimapHelpBox:Hide()
        ezCollections:SetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_EZCOLLECTIONS_MICRO_BUTTON, true)
        WardrobeCollectionFrame_SetContainer(WardrobeFrame)

        if ezCollections.Config.Wardrobe.EtherealWindowSound then
            PlaySoundFile([[Interface\AddOns\ProjectEbonhold\modules\collections\Sounds\UI_EtherealWindow_Open.wav]])
        else
            PlaySound("igCharacterInfoOpen")
        end
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        local hasAlternateForm, inAlternateForm = HasAlternateForm()
        if (hasAlternateForm) then
            self:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
            self.inAlternateForm = inAlternateForm
        end
        WardrobeTransmogFrame.Model:SetUnit("player")
        Model_Reset(WardrobeTransmogFrame.Model)

        WardrobeTransmogFrame_Update(self)
        UpdateMicroButtons()
    end)
end

-- Captured once at load, before any resizing ever happens.
local NATIVE_W, NATIVE_H = CollectionsJournal:GetWidth(), CollectionsJournal:GetHeight()

-- Resize CollectionsJournal to fit whichever system is now showing (nil w/h ->
-- revert to native size).
local function ResizeCollectionsJournal(w, h)
    CollectionsJournal:SetSize(w or NATIVE_W, h or NATIVE_H)
end

local ICONS = {
    echoes = [[Interface\AddOns\ProjectEbonhold\modules\collections\Interface\Icons\70_Professions_Scroll_01]],
    skilltree = [[Interface\AddOns\ProjectEbonhold\modules\collections\Interface\Icons\INV_7xp_Inscription_TalentTome01]],
    transmog = [[Interface\AddOns\ProjectEbonhold\modules\collections\Interface\Icons\INV_Arcane_Orb]],
    mounts = [[Interface\AddOns\ProjectEbonhold\modules\collections\Interface\Icons\MountJournalPortrait]],
    companions = [[Interface\AddOns\ProjectEbonhold\modules\collections\Interface\Icons\PetJournalPortrait]],
}

-- Prestige wears the Skill Tree's portrait: the two tabs are the same system
-- (a prestige is what clears the tree), and the corner medallion is 61x61, so
-- it needs a 64x64 icon like the ones above. The chat rank badge that used to
-- sit here is 32x32 art built for a chat line, and blowing it up read as
-- broken. Aliased rather than copied so the two can never drift apart.
ICONS.prestige = ICONS.skilltree

local function EmbedEchoJournal()
    local f = _G.ProjectEbonholdEchoJournal
    if not f then return nil end
    -- journalFrame no longer creates its own bgTexture at all (removed at the
    -- source in echo_journal.lua) -- it relied on CollectionsJournal's own Bg
    -- underneath, and having both was a visible doubled-up background.
    if f.headerTex then f.headerTex:Hide() end
    if f.titleText then f.titleText:Hide() end
    if f.closeButton then f.closeButton:Hide() end
    if f.ownTabButtons then
        for _, t in ipairs(f.ownTabButtons) do t:Hide() end
    end
    f:SetBackdrop(nil)
    if f:GetParent() ~= CollectionsJournal then
        f:SetParent(CollectionsJournal)
        f:SetFrameLevel(CollectionsJournal:GetFrameLevel() + 5)
    end
    -- Re-anchored EVERY embed, not just the first: anything that knocks the
    -- frame off its spot (the old drag handlers did, by accident -- the
    -- "content pushed right" bug) self-heals on the next tab switch.
    f:ClearAllPoints()
    f:SetPoint("TOP", CollectionsJournal, "TOP", 0, -HEADER_CLEARANCE)
    return f
end

-- skillTreeFrame is now created directly as a native child of CollectionsJournal
-- (see skillTree.lua), already correctly sized/positioned/parented from the
-- start -- nothing to reparent, scale, or strip chrome from here anymore.
local function EmbedSkillTree()
    return _G.skillTreeFrame
end

-- WardrobeFrame's own chrome uses the same ezCollectionsPortraitFrameTemplate
-- as CollectionsJournal (same parentKey elements), so it's hideable the same way.
local WARDROBE_CHROME_KEYS = {
    "Bg", "TitleBg", "portrait", "PortraitFrame", "TopRightCorner", "TopLeftCorner",
    "TopBorder", "TitleText", "TopTileStreaks", "BotLeftCorner", "BotRightCorner",
    "BottomBorder", "LeftBorder", "RightBorder", "CloseButton",
}

local function EmbedWardrobeFrame()
    local f = _G.WardrobeFrame
    if not f then return nil end
    for _, key in ipairs(WARDROBE_CHROME_KEYS) do
        if f[key] then f[key]:Hide() end
    end
    -- WardrobeFrame also has its OWN Mounts/Companions/Transmogrify tab row
    -- (for when it's used standalone, at an actual NPC) -- duplicates our 5-tab
    -- row once embedded. Permanently neutralized, not just hidden once: same
    -- reasoning as the portrait buttons/help boxes -- something else in the
    -- stock code could call :Show() on these again later (e.g. WardrobeFrame's
    -- own tab-click handling), so :Show() itself is disabled, not just called
    -- once at embed time.
    for i = 1, 3 do
        local ownTab = _G["WardrobeFrameTab" .. i]
        if ownTab then
            ownTab:Hide()
            ownTab:EnableMouse(false)
            ownTab.Show = function() end
        end
    end
    if f:GetParent() ~= CollectionsJournal then
        f:SetParent(CollectionsJournal)
        f:SetFrameLevel(CollectionsJournal:GetFrameLevel() + 5)
    end
    -- WardrobeFrame ships an (anonymous) ezCollectionsMovingHeaderTemplate
    -- strip along its top that calls StartMoving() -- fine standalone at an
    -- NPC, but embedded it let the player drag the CONTENT out of its spot
    -- inside CollectionsJournal. On 3.3.5 StartMoving() ERRORS on a
    -- non-movable frame (it does not no-op), so the method itself is
    -- shadowed with a no-op on the instance -- the unnamed header strip
    -- then calls into nothing. StopMovingOrSizing stays; it is harmless.
    f:SetMovable(false)
    f.StartMoving = function() end
    -- WardrobeFrame's own internal layout (Items tab, grid, slot buttons) already
    -- accounts for its own top spacing -- unlike Echo Journal, it doesn't need
    -- HEADER_CLEARANCE's full 55px on top of that, which was pushing its content
    -- down further than necessary.
    f:ClearAllPoints()
    f:SetPoint("TOP", CollectionsJournal, "TOP", 0, 2)
    -- Ensures WardrobeCollectionFrame (grid+model+slots+apply) is parented and
    -- laid out inside WardrobeFrame, matching the real at-an-NPC experience --
    -- not just the passive browse-only grid.
    WardrobeCollectionFrame_SetContainer(f)
    return f
end

-- Whichever system's content is embedded can end up with a higher frame level
-- than CollectionsJournal's own tab row after reparenting (reparenting resets
-- frame levels/stratas of a frame's own children, and can leave the reparented
-- frame itself above sibling tab buttons) -- force the 5 tabs back on top every
-- time so they never get visually covered by embedded content.
local function RaiseOwnTabs()
    local maxLevel = CollectionsJournal:GetFrameLevel()
    if WardrobeFrame:IsShown() then
        maxLevel = math.max(maxLevel, WardrobeFrame:GetFrameLevel())
    end
    if _G.ProjectEbonholdEchoJournal and _G.ProjectEbonholdEchoJournal:IsShown() then
        maxLevel = math.max(maxLevel, _G.ProjectEbonholdEchoJournal:GetFrameLevel())
    end
    if _G.skillTreeFrame and _G.skillTreeFrame:IsShown() then
        maxLevel = math.max(maxLevel, _G.skillTreeFrame:GetFrameLevel())
    end
    if _G.EbonholdPrestigeFrame and _G.EbonholdPrestigeFrame:IsShown() then
        maxLevel = math.max(maxLevel, _G.EbonholdPrestigeFrame:GetFrameLevel())
    end
    for i = 1, 6 do
        local tab = _G["CollectionsJournalTab" .. i]
        if tab then tab:SetFrameLevel(maxLevel + 10) end
    end
end

-- CharacterFrameTabButtonTemplate declares its Left/Middle/Right (and
-- Disabled) tab-art pieces at 32px tall, and SpellBookFrameTabButton (same
-- base template) renders at that height fine. CollectionsJournalTab measures
-- 20px tall live instead -- squashed, whatever is doing it isn't in this
-- addon's own code -- so force the declared height back on every piece.
local TAB_TEXTURE_HEIGHT = 32
local TAB_PIECE_KEYS = { "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }
local function FixTabHeights()
    for i = 1, 6 do
        local tab = _G["CollectionsJournalTab" .. i]
        if tab then
            for _, key in ipairs(TAB_PIECE_KEYS) do
                local tex = tab[key]
                if tex then tex:SetHeight(TAB_TEXTURE_HEIGHT) end
            end
        end
    end
end

-- Full replacement of Blizzard_Collections.lua's CollectionsJournal_UpdateSelectedTab
-- (this file loads last, so this definition wins).
function CollectionsJournal_UpdateSelectedTab(self)
    local selected = PanelTemplates_GetSelectedTab(self)

    if (not CollectionsJournal_ValidateTab(selected)) then
        PanelTemplates_SetTab(self, 1)
        selected = 1
    end

    MountJournal:SetShown(selected == 4)
    PetJournal:SetShown(selected == 5)

    if (selected == 3) then
        local f = EmbedWardrobeFrame()
        if f then f:Show() end
        ResizeCollectionsJournal(f and (f:GetWidth() + 20) or nil, nil)
    elseif _G.WardrobeFrame then
        _G.WardrobeFrame:Hide()
    end

    -- Tab 1 = merged "Echoes": always requests Echo Journal's internal TAB_ALL
    -- (2), never TAB_MY_RUN (1) -- My Echoes and All Echoes are now one view,
    -- and Loadouts (3) is dead -- loadout saving/switching lives in Echo
    -- Journal's My Run panel footer now, not a separate CollectionsJournal tab.
    if (selected == 1) then
        if ProjectEbonhold.EchoJournal and ProjectEbonhold.EchoJournal.Show then
            ProjectEbonhold.EchoJournal.Show(2)
        end
        local f = EmbedEchoJournal()
        -- f:GetHeight() (480x500 declared) doesn't match actual content height
        -- -- the merged Echoes view needs a specific visible height.
        local contentH = ECHO_TAB_CONTENT_HEIGHT[2]
        -- The merged Echoes tab is now wider than CollectionsJournal's native
        -- size (split into a My Run column + a wider catalog) -- grow the
        -- window to match, same as Transmogrify does for WardrobeFrame.
        local w = f and (f:GetWidth() + 20) or nil
        ResizeCollectionsJournal(w, f and (contentH + HEADER_CLEARANCE + BOTTOM_PADDING) or nil)
    elseif _G.ProjectEbonholdEchoJournal then
        _G.ProjectEbonholdEchoJournal:Hide()
    end

    if (selected == 2) then
        local f = EmbedSkillTree()
        if f then
            f:Show()
            ResizeCollectionsJournal(f:GetWidth() + SKILLTREE_SIDE_PADDING, f:GetHeight() + SKILLTREE_TOP_CLEARANCE + SKILLTREE_BOTTOM_PADDING)
        end
    elseif _G.skillTreeFrame then
        _G.skillTreeFrame:Hide()
    end

    if (selected == 6) then
        local f = _G.EbonholdPrestigeFrame
        if f then
            f:Show()
            ResizeCollectionsJournal(f:GetWidth() + 20,
                f:GetHeight() + HEADER_CLEARANCE + BOTTOM_PADDING)
        end
    elseif _G.EbonholdPrestigeFrame then
        _G.EbonholdPrestigeFrame:Hide()
    end

    if (selected == 4 or selected == 5) then
        ResizeCollectionsJournal(nil, nil)
    end

    local icon, title
    if (selected == 1) then icon, title = ICONS.echoes, "Echoes"
    elseif (selected == 2) then icon, title = ICONS.skilltree, "Skill Tree"
    elseif (selected == 3) then icon, title = ICONS.transmog, "Transmogrify"
    elseif (selected == 4) then icon, title = ICONS.mounts, MOUNTS
    elseif (selected == 5) then icon, title = ICONS.companions, COMPANIONS
    elseif (selected == 6) then icon, title = ICONS.prestige, "Prestige"
    end
    if title then CollectionsJournalTitleText:SetText(title) end
    if icon then SetPortraitToTexture(CollectionsJournalPortrait, icon) end

    RaiseOwnTabs()
    FixTabHeights()
    NeutralizePortraitButtons()
    NeutralizeHelpBoxes()
end

-- Also neutralize once immediately at load (covers the state before the first
-- tab switch, e.g. if CollectionsJournal opens directly to a stale-CVar tab).
NeutralizePortraitButtons()
NeutralizeHelpBoxes()
FixTabHeights()

-- Tab 6 = Prestige. The XML tab row stops at 5, so the extra tab is created
-- here from the same virtual template and CollectionsJournal's tab count
-- (set to 5 in Blizzard_Collections.xml's OnLoad) is bumped to 6. The frame
-- it embeds is EbonholdPrestigeFrame (modules\prestige\prestige.lua), a native
-- child of CollectionsJournal like skillTreeFrame -- but built on the first
-- PLAYER_ENTERING_WORLD rather than at load, which is why every reference to
-- it in this file is nil-guarded. The tab itself exists from the start.
local prestigeTab = CreateFrame("Button", "CollectionsJournalTab6",
    CollectionsJournal, "CollectionsJournalTabCutoff")
prestigeTab:SetID(6)
prestigeTab:SetText("Prestige")
prestigeTab:SetPoint("LEFT", CollectionsJournalTab5, "RIGHT", -16, 0)
PanelTemplates_SetNumTabs(CollectionsJournal, 6)
PanelTemplates_TabResize(prestigeTab, 0)
PanelTemplates_DeselectTab(prestigeTab)

-- The shared CollectionsJournalTab template's OnClick has a hardcoded special
-- case for id==3 (pops the standalone WardrobeFrame out instead of switching
-- tabs in place) -- a leftover from when Transmogrify used to be id 3, which
-- (coincidentally) it is again now, but embedded inline rather than popped
-- out. All 6 tabs here embed inline, so replace each one's OnClick with the
-- plain switch-tab behavior, bypassing that special case entirely.
for i = 1, 6 do
    local tabButton = _G["CollectionsJournalTab" .. i]
    if tabButton then
        tabButton:SetScript("OnClick", function(self)
            CollectionsJournal_SetTab(self:GetParent(), self:GetID())
            PlaySound("igCharacterInfoTab")
        end)
    end
end

SLASH_PECHARPROGRESSION1 = "/progression"
SLASH_PECHARPROGRESSION2 = "/charprogression"
SlashCmdList["PECHARPROGRESSION"] = function()
    ToggleCollectionsJournal()
end

ProjectEbonhold.CharacterProgression = {
    EmbedEchoJournal = EmbedEchoJournal,
    EmbedSkillTree = EmbedSkillTree,
    EmbedWardrobeFrame = EmbedWardrobeFrame,
}
