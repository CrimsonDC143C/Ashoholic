-- edit_mode.lua -- a retail-style Edit Mode for the 3.3.5 HUD.
--
-- Open it from the Game Menu ("Edit Mode" button) or with /editmode. Every movable
-- system gets a blue box with its name; drag a box to move the frame, click it to
-- select it (scale slider, reset). Changes are live but pending until Save; Revert
-- puts the saved layout back. Layouts are account-wide (EbonholdEditModeDB.layouts), and so
-- is the active one (accountActive, owner 2026-11-18); "Default" is the stock Blizzard placement
-- and is never written to (saving from it asks for a new layout name).
--
-- How a position sticks: positions are stored in UIParent units against the nearest
-- screen corner / edge / centre, so a layout survives a resolution or UI-scale change.
-- Blizzard code re-anchors some frames on its own (UIParent_ManageFramePositions, the
-- vehicle animation of PlayerFrame, the pet bar slide...); for those ("managed" below) a
-- hooksecurefunc on SetPoint puts our point back, the way ElvUI keeps DurabilityFrame.
-- A protected frame cannot be moved by an addon in combat: the re-anchor waits for
-- PLAYER_REGEN_ENABLED, and Edit Mode itself refuses to open in combat.
--
-- Frames that already drag and save themselves (run tracker, echoes, Details!, chat)
-- are not fought: they are placed when a layout applies, and a native drag of any frame
-- (StopMovingOrSizing) is written back into the active custom layout.
--
-- Every system can also be hidden (parked under a hidden parent), and the bottom bar is
-- split into pieces that can be taken out of it (holders, below).

local EM = {}
ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.EditMode = EM
local L, T = ProjectEbonhold.L, ProjectEbonhold.T

local DEFAULT = "Default"
local MIN_BOX_W, MIN_BOX_H = 60, 24
local SNAP_DISTANCE = 8

-- The art of the bottom bar, for when its pieces have been taken out of it. Alpha, not
-- Hide: Blizzard re-Shows those textures on vehicle exit. Without its background the
-- bar stops eating clicks.
local function ApplyMainBarArt(opts)
    local caps = opts.hideCaps and 0 or 1
    for _, n in ipairs({ "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap" }) do
        if _G[n] then _G[n]:SetAlpha(caps) end
    end
    local bg = opts.hideArt and 0 or 1
    for i = 0, 3 do
        local t = _G["MainMenuBarTexture" .. i]
        if t then t:SetAlpha(bg) end
    end
    MainMenuBar:EnableMouse(not opts.hideArt)
end

-- the order of skillTreeMicroButton.lua getCoreMicroButtons
local MICRO = {
    { "CharacterMicroButton",   "Character" },
    { "SpellbookMicroButton",   "Spellbook" },
    { "TalentMicroButton",      "Talents" },
    { "AchievementMicroButton", "Achievements" },
    { "QuestLogMicroButton",    "Quest Log" },
    { "SocialsMicroButton",     "Social" },
    { "EchoJournalMicroButton", "Progression" },
    { "LFDMicroButton",         "Dungeon Finder" },
    { "ToolbeltMicroButton",    "Toolbelt" },
    { "MainMenuMicroButton",    "Game Menu" },
    { "HelpMicroButton",        "Help" },
}
local BAGS = {
    { "MainMenuBarBackpackButton", "Backpack" },
    { "CharacterBag0Slot",         "Bag 1" },
    { "CharacterBag1Slot",         "Bag 2" },
    { "CharacterBag2Slot",         "Bag 3" },
    { "CharacterBag3Slot",         "Bag 4" },
    { "KeyRingButton",             "Key Ring" },
}

-- One "shown" box per frame of a piece of the bottom bar.
local function ShowOptions(list)
    local names, options = {}, {}
    for i, m in ipairs(list) do
        names[i] = m[1]
        options[i] = { key = "hide" .. m[1], label = L[m[2]], buttons = { m[1] }, invert = true }
    end
    return names, options
end
local MICRO_BUTTONS, MICRO_OPTIONS = ShowOptions(MICRO)
local BAG_BUTTONS, BAG_OPTIONS = ShowOptions(BAGS)

-- Frames of the bottom bar switched off in the layout. Hidden for good (Blizzard and
-- positionButtons Show them again: hooked); a collapsing piece closes up behind them
-- (Attach). None of them is protected, so this holds in combat too. While hidden, what
-- Blizzard wants (ebhWant: its own Show / Hide calls, e.g. no XP bar at max level) is
-- kept, and that is what comes back when the frame is switched on again.
local hiding = false

local function ApplyHidden(opts, e)
    e.hidden = e.hidden or {}
    for _, def in ipairs(e.options) do
        for _, n in ipairs(def.buttons) do
            local b = _G[n]
            if b then
                if not b.ebhHideHooked then
                    b.ebhHideHooked = true
                    hooksecurefunc(b, "Show", function(self)
                        if hiding or not e.hidden[self] then return end
                        self.ebhWant = true
                        hiding = true
                        self:Hide()
                        hiding = false
                    end)
                    hooksecurefunc(b, "Hide", function(self)
                        if not hiding and e.hidden[self] then self.ebhWant = false end
                    end)
                end
                if opts[def.key] then
                    if not e.hidden[b] then
                        b.ebhWant = b:IsShown()
                        e.hidden[b] = true
                        hiding = true
                        b:Hide()
                        hiding = false
                    end
                elseif e.hidden[b] then
                    e.hidden[b] = nil
                    if b.ebhWant then b:Show() end
                end
            end
        end
    end
end

local ACTION_BUTTONS = {}
for i = 1, 12 do ACTION_BUTTONS[i] = "ActionButton" .. i end

-- Hiding the chat hides every chat window and tab: the docked ones share its spot.
local CHAT_FRAMES = { "GeneralDockManager", "ChatFrameMenuButton", "FriendsMicroButton" }
for i = 1, (NUM_CHAT_WINDOWS or 10) do
    for _, suffix in ipairs({ "", "Tab", "ButtonFrame" }) do
        CHAT_FRAMES[#CHAT_FRAMES + 1] = "ChatFrame" .. i .. suffix
    end
end

-- ------------------------------------------------------------- systems ----
-- key = global frame name. always = show its box even while the frame is hidden
-- (unit frames without a unit, the cast bar...); otherwise a hidden frame (a
-- disabled action bar) gets no box, as on retail. union = draw the box around
-- these frames (the first one is the one moved, the others hang from it).
--
-- holder = a piece of the bottom bar that can be taken out of it. key is then the name
-- of an invisible frame of ours, laid over the piece (the shown `rect` frames) at login;
-- once the piece has a position in the layout, each of its `children` (default: the
-- rect frames) is hung from that holder at the offset it had in the bar, and put back
-- on its stock anchor when the position is reset. Until then the stock bar is untouched.
-- The debuffs have no frame of their own: Blizzard hangs DebuffButton1 under the buffs. This
-- frame is the width of a row of 8. Until it is placed it follows the spot Blizzard uses (only
-- so that its box shows there) and the stock anchors are left alone; once placed, the first
-- button hangs from it and the others from that button.
local debuffAnchor = CreateFrame("Frame", "EbonholdEditModeDebuffs", UIParent)
debuffAnchor:SetSize(275, 30)
debuffAnchor:SetFrameStrata(BuffFrame:GetFrameStrata())
debuffAnchor:SetPoint("TOPRIGHT", ConsolidatedBuffs, "BOTTOMRIGHT", 0, -60)

local function DebuffAnchor()
    if not debuffAnchor.ebhEditModePlaced then
        local rows = math.ceil(BUFF_ACTUAL_DISPLAY / BUFFS_PER_ROW)
        local h = TempEnchant1:GetHeight()
        local y = rows < 2 and -(2 * BUFF_ROW_SPACING + h) or -rows * (BUFF_ROW_SPACING + h)
        local _, _, _, _, cur = debuffAnchor:GetPoint(1)
        if cur ~= y then
            debuffAnchor:ClearAllPoints()
            debuffAnchor:SetPoint("TOPRIGHT", ConsolidatedBuffs, "BOTTOMRIGHT", 0, y)
        end
    end
    return debuffAnchor
end

hooksecurefunc("DebuffButton_UpdateAnchors", function(name, index)
    if name ~= "DebuffButton" then return end
    local b = _G[name .. index]
    -- children of this frame, not of BuffFrame: scale and Hide are their own
    if b:GetParent() ~= debuffAnchor then b:SetParent(debuffAnchor) end
    if index == 1 and debuffAnchor.ebhEditModePlaced then
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", debuffAnchor, "TOPRIGHT", 0, 0)
    end
end)

local RAID_BOX = "CompactRaidFrameManagerContainerResizeFrame"

-- With ElvUI on, ElvUI holds WatchFrame on its own holder and puts it back after any other SetPoint
-- (ElvUI Modules\Blizzard\WatchFrame.lua MoveWatchFrame): the Objective Tracker box moves ElvUI's
-- mover instead and saves it ElvUI's way (2026-11-19, the box "could not be moved").
local function ElvWatchMover()
    local m = _G.WatchFrameMover
    if m and _G.WatchFrameHolder then return m end
end

local SYSTEMS = {
    { key = "PlayerFrame",          label = L["Player Frame"],      always = true },
    { key = "TargetFrame",          label = L["Target Frame"],      always = true },
    { key = "FocusFrame",           label = L["Focus Frame"],       always = true },
    -- Party and raid frames are one element, only one of the two shows at a time. The box is the
    -- resize frame the raid container hangs from: moving it moves the raid buttons, never in combat.
    -- Placed, it stops following the manager, the raid profile keeps the same spot (its own drag reads
    -- and writes there too) and the party frames hang from its corner, where the raid buttons start.
    -- Key kept: the layouts already hold it. MergePartyIntoRaid folds the old party entry into it.
    { key = RAID_BOX, label = L["Party & Raid Frames"], always = true, combatLocked = true,
      union = { RAID_BOX, "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3",
                "PartyMemberFrame4" },
      scaleFrames = { "CompactRaidFrameContainer", "PartyMemberFrame1", "PartyMemberFrame2",
                      "PartyMemberFrame3", "PartyMemberFrame4" },
      hideFrames = { "CompactRaidFrameContainer", "PartyMemberFrame1", "PartyMemberFrame2",
                     "PartyMemberFrame3", "PartyMemberFrame4" },
      onMoved = function(f)
          local m = _G.CompactRaidFrameManager
          if not m then return end
          if f.ebhEditModePlaced then
              PartyMemberFrame1:ClearAllPoints()
              PartyMemberFrame1:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -7)
          else
              CompactRaidFrameManager_AttachPartyFrames(m)
          end
          if not GetActiveRaidProfile or not GetActiveRaidProfile() then return end
          if f.ebhEditModePlaced then
              m.dynamicContainerPosition = false
              CompactRaidFrameManager_ResizeFrame_SavePosition(m)
          else
              CompactRaidFrameManager_ResetContainerPosition()
          end
      end },
    -- The raid manager is a drawer docked on the left edge: only its height moves, the dock puts
    -- it back on the edge (drawn out or tucked away) and keeps that height afterwards.
    { key = "CompactRaidFrameManager", label = L["Raid Manager"], always = true, unmanaged = true,
      noScale = true, combatLocked = true,
      onMoved = function(f)
          f.ebhY = f.ebhEditModePlaced and (f:GetTop() - UIParent:GetTop()) or nil
          if CompactRaidFrameManager_Dock then CompactRaidFrameManager_Dock(f) end
      end },
    { key = "Boss1TargetFrame",     label = L["Boss Frames"],       always = true,
      union = { "Boss1TargetFrame", "Boss2TargetFrame", "Boss3TargetFrame", "Boss4TargetFrame" } },
    -- user-placed once we place it, as a drag would: GetMaxUIPanelsWidth (UIParent.lua)
    -- ends the room for side-by-side windows at the left of a minimap that is NOT
    -- user-placed, so a minimap moved to the left left no room and a second window (the
    -- Dressing Room over a vendor) took the first one's slot
    { key = "MinimapCluster",       label = L["Minimap"],           always = true,
      onMoved = function(f)
          f:SetMovable(true)
          f:SetUserPlaced(f.ebhEditModePlaced and true or false)
      end },
    { key = "BuffFrame",            label = L["Buffs"],             always = true,
      hideFrames = { "BuffFrame", "ConsolidatedBuffs" } },
    -- The box is an invisible frame of ours, and the parent of the debuff buttons.
    { key = "EbonholdEditModeDebuffs", label = L["Debuffs"], always = true, unmanaged = true,
      getFrame = DebuffAnchor,
      onMoved = function()
          if DebuffButton1 then DebuffButton_UpdateAnchors("DebuffButton", 1) end
      end },
    { key = "TemporaryEnchantFrame", label = L["Weapon Enchants"] },
    { key = "CastingBarFrame",      label = L["Cast Bar"],          always = true },
    -- no Hide: the pieces taken out of it are still its children (art options instead)
    -- rehang: its scale carries the pieces taken out of it (still its children)
    { key = "MainMenuBar",          label = L["Main Menu Bar"], noHide = true, rehang = true,
      options = { { key = "hideCaps", label = L["Hide Gryphons"] },
                  { key = "hideArt",  label = L["Hide Bar Background"] } },
      applyOptions = ApplyMainBarArt },
    -- always / rectAll: in a form or a stance the bonus bar covers it and the buttons
    -- themselves may be hidden; the piece is still there to place
    { key = "EbonholdEditModeActionBar1", label = L["Action Bar 1"], holder = true, noScale = true,
      rect = ACTION_BUTTONS, always = true, rectAll = true,
      hideFrames = { "ActionButton1", "ActionButton2", "ActionButton3", "ActionButton4",
                     "ActionButton5", "ActionButton6", "ActionButton7", "ActionButton8",
                     "ActionButton9", "ActionButton10", "ActionButton11", "ActionButton12",
                     "BonusActionBarFrame", "ActionBarUpButton", "ActionBarDownButton",
                     "MainMenuBarPageNumber" },
      -- the bonus bar (stances, forms, stealth) takes the place of bar 1
      children = { "ActionButton1", "BonusActionBarFrame", "ActionBarUpButton",
                   "ActionBarDownButton", "MainMenuBarPageNumber" },
      optionsTitle = L["Shown"], applyOptions = ApplyHidden,
      options = { { key = "hidePaging", label = L["Page Arrows"], invert = true,
                    buttons = { "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber" } } } },
    { key = "EbonholdEditModeMicroMenu", label = L["Micro Menu"], holder = true, noScale = true,
      rect = MICRO_BUTTONS, skipInVehicle = true, collapse = true,
      optionsTitle = L["Shown buttons"], options = MICRO_OPTIONS, applyOptions = ApplyHidden },
    { key = "EbonholdEditModeBags",  label = L["Bags"], holder = true, noScale = true,
      rect = BAG_BUTTONS, collapse = true,
      optionsTitle = L["Shown bags"], options = BAG_OPTIONS, applyOptions = ApplyHidden },
    { key = "EbonholdEditModeXPBar", label = L["Experience Bar"], holder = true, noScale = true,
      rect = { "MainMenuExpBar", "MainMenuBarMaxLevelBar" },
      optionsTitle = L["Shown"], applyOptions = ApplyHidden,
      options = { { key = "hideXP", label = L["Experience Bar"], invert = true,
                    buttons = { "MainMenuExpBar", "MainMenuBarMaxLevelBar" } } } },
    { key = "MultiBarBottomLeft",   label = L["Action Bar 2"] },
    { key = "MultiBarBottomRight",  label = L["Action Bar 3"] },
    { key = "MultiBarRight",        label = L["Action Bar 4"] },
    { key = "MultiBarLeft",         label = L["Action Bar 5"] },
    { key = "PetActionBarFrame",    label = L["Pet Bar"] },
    { key = "ShapeshiftBarFrame",   label = L["Stance Bar"] },
    { key = "PossessBarFrame",      label = L["Possess Bar"] },
    { key = "MultiCastActionBarFrame", label = L["Totem Bar"] },
    { key = "VehicleSeatIndicator", label = L["Vehicle Seats"] },
    { key = "DurabilityFrame",      label = L["Durability"] },
    -- WatchFrame is only the anchor of Ebonhold's quest / instance trackers; the box
    -- is drawn around the visible tracker. player_run_ui.lua stops pinning it while
    -- ebhEditModePlaced is set.
    -- The size scales the whole column: the stock lines live in WatchFrame, our two trackers sit
    -- on UIParent (they take WatchFrame's scale when they are created).
    { key = "WatchFrame",           label = L["Objective Tracker"], always = true,
      sizeFrom = "EbonholdQuestTracker",
      scaleList = { "WatchFrame", "EbonholdQuestTracker", "ProjectEbonholdInstanceTracker" },
      getFrame = function() return ElvWatchMover() or _G.WatchFrame end,
      relativeTo = function(f) return (f == ElvWatchMover() and _G.ElvUIParent) or UIParent end,
      onMoved = function(f)
          local E = type(_G.ElvUI) == "table" and _G.ElvUI[1]
          if f == ElvWatchMover() and E and E.SaveMoverPosition then E:SaveMoverPosition("WatchFrameMover") end
      end,
      hideFrames = { "WatchFrame", "EbonholdQuestTracker", "ProjectEbonholdInstanceTracker" } },
    { key = "ChatFrame1",           label = L["Chat Frame"],        always = true, unmanaged = true,
      hideFrames = CHAT_FRAMES,
      onMoved = function(f)
          f:SetUserPlaced(true)
          if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(f) end
      end },
    { key = "EbonholdEditModeTooltipAnchor", label = L["Tooltip"], always = true, unmanaged = true,
      noScale = true, noHide = true },
    -- No Run Tracker entry (owner 2026-11-16): it is dragged freely, any time, and keeps its own
    -- position (player_run_ui.lua, ProjectEbonholdDB.playerRunUIPosition); Edit Mode leaves it alone.
    { key = "ProjectEbonholdEmpowermentFrame", label = L["Echoes"],        unmanaged = true },
    { key = "ProjectEbonholdTrialHUD",         label = L["Trial Tracker"], unmanaged = true },
    -- the echo choice (perks.lua, created at PLAYER_ENTERING_WORLD); its buttons hang
    -- under it. Scaled by its own option (perkUIScale, capped at 100%), not here.
    -- no Hide: hidden, the echoes could no longer be chosen
    { key = "ProjectEbonholdPerkFrame", label = L["Echo Selection"], always = true, unmanaged = true,
      noScale = true, noHide = true, union = { "ProjectEbonholdPerkFrame", "PerkChooseButton" } },
    -- its Show / Hide toggle: a child of the echo choice (shown with it, scaled with it),
    -- hanging under it until it is given a place of its own
    { key = "PerkHideButton", label = L["Echo Show/Hide"], always = true, unmanaged = true, noScale = true },
}

local entries = {}          -- SYSTEMS + one entry per Details! window, by order
local entryByKey = {}
local current = {}          -- overrides in effect: [key] = { p =, x =, y =, s = }
local dirty = false         -- current differs from the saved active layout
local editing = false
local selected = nil        -- selected entry
local applying = false      -- re-entrancy guard for the SetPoint hooks
local queued = {}           -- protected frames to re-place once out of combat

local panel, sysDialog, grid

-- ----------------------------------------------------------------- db ----
local function DB()
    EbonholdEditModeDB = EbonholdEditModeDB or {}
    local db = EbonholdEditModeDB
    db.layouts = db.layouts or {}
    db.active = db.active or {}
    db.grid = db.grid or { show = true, snap = true, spacing = 40 }
    return db
end

local function CharKey()
    return (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
end

-- One active layout for the whole account (owner, 2026-11-18). accountActive = a layout name, or
-- false for Default. The first character to load after the change hands over its own choice
-- (the per-character `active` table it was kept in before).
local function ActiveName()
    local db = DB()
    if db.accountActive == nil then db.accountActive = db.active[CharKey()] or false end
    local name = db.accountActive
    if name and db.layouts[name] then return name end
    return DEFAULT
end

local function SetActiveName(name)
    DB().accountActive = (name ~= DEFAULT) and name or false
end

local function Copy(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then out[k] = Copy(v) else out[k] = v end
    end
    return out
end

local function SavedFrames()
    local name = ActiveName()
    if name == DEFAULT then return {} end
    local layout = DB().layouts[name]
    if type(layout.frames) ~= "table" then layout.frames = {} end
    return layout.frames
end

local function Notify(msg)
    DEFAULT_CHAT_FRAME:AddMessage(L["|cff33bbffEdit Mode:|r "] .. msg)
end

-- ------------------------------------------------------------ geometry ----
-- Some pieces are FontStrings (MainMenuBarPageNumber): on 3.3.5 a region has no scale
-- and no protection of its own, it has its parent's.
local function EffScale(f)
    if f.GetEffectiveScale then return f:GetEffectiveScale() end
    local p = f:GetParent()
    return p and p:GetEffectiveScale() or UIParent:GetEffectiveScale()
end

local function IsProt(f)
    if f.IsProtected then return f:IsProtected() end
    local p = f:GetParent()
    return p and p.IsProtected and p:IsProtected() or false
end

-- frame units -> UIParent units
local function Ratio(f)
    return EffScale(f) / UIParent:GetEffectiveScale()
end

local function FrameRect(f)
    local l, b = f:GetLeft(), f:GetBottom()
    if not l or not b then return nil end
    local r = Ratio(f)
    return l * r, b * r, f:GetWidth() * r, f:GetHeight() * r
end

-- The holder of a bar piece, created over the piece the first time it is laid out.
local function EnsureHolder(e)
    if e.holderFrame then return e.holderFrame end
    -- inside a vehicle the micro buttons sit in the vehicle bar: measure them later
    if e.skipInVehicle and UnitHasVehicleUI("player") then return nil end
    local L, B, R, T
    for _, n in ipairs(e.rect) do
        local g = _G[n]
        if g and (e.rectAll or g:IsShown()) then
            local l, b, w, h = FrameRect(g)
            if l then
                L = L and math.min(L, l) or l
                B = B and math.min(B, b) or b
                R = R and math.max(R, l + w) or (l + w)
                T = T and math.max(T, b + h) or (b + h)
            end
        end
    end
    if not L then return nil end
    local holder = CreateFrame("Frame", e.key, UIParent)
    holder:SetSize(R - L, T - B)
    holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", L, B)
    e.members = {}
    for _, n in ipairs(e.children or e.rect) do
        local g = _G[n]
        local l, b
        if g and (e.children or g:IsShown()) then l, b = FrameRect(g) end
        if l then
            local pts = {}
            for i = 1, g:GetNumPoints() do pts[i] = { g:GetPoint(i) } end
            e.members[#e.members + 1] = { frame = g, x = l - L, y = b - B,
                w = g:GetWidth(), h = g:GetHeight(), points = pts }
            if IsProt(g) then e.hasProtected = true end
        end
    end
    e.holderFrame = holder
    return holder
end

local function Resolve(e)
    if e.holder then return EnsureHolder(e) end
    if e.getFrame then return e.getFrame() end
    return _G[e.key]
end

local function Visible(e, f)
    if e.holder and not e.always then
        -- a piece hidden by the layout keeps its box, or it could not be shown again
        for _, n in ipairs(e.rect) do
            local g = _G[n]
            if g and (g:IsShown() or (e.hidden and e.hidden[g])) then return true end
        end
        return false
    end
    return e.always or (e.alwaysIf and e.alwaysIf()) or f:IsShown()
end

-- The rect the box is drawn on: the frame, the union of its group, or the frame it carries.
local function BoxRect(e, f)
    local names = e.union
    if e.sizeFrom then
        -- the quest tracker hangs under the instance tracker while that one is
        -- shown (quest_tracker.lua AnchorTracker): only then is it not ours to draw
        local s = _G[e.sizeFrom]
        if s and s:IsShown() and not s.anchoredBelow then names = { e.sizeFrom } end
        -- in a dungeon or raid: the instance tracker, and the quest tracker hanging under it
        local inst = _G.ProjectEbonholdInstanceTracker
        if inst and inst:IsShown() then
            names = { "ProjectEbonholdInstanceTracker" }
            if s and s:IsShown() then names[2] = e.sizeFrom end
        end
    end
    if not names then return FrameRect(f) end
    local L, B, R, T
    for _, n in ipairs(names) do
        local g = _G[n]
        if g then
            local l, b, w, h = FrameRect(g)
            if l then
                L = L and math.min(L, l) or l
                B = B and math.min(B, b) or b
                R = R and math.max(R, l + w) or (l + w)
                T = T and math.max(T, b + h) or (b + h)
            end
        end
    end
    if not L then return FrameRect(f) end
    return L, B, R - L, T - B
end

-- Anchor a rect (UIParent units) to the nearest third of the screen on each axis.
local function ComputeAnchor(l, b, w, h)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = l + w / 2, b + h / 2
    local hp, x, vp, y
    if cx < W / 3 then hp, x = "LEFT", l
    elseif cx > W * 2 / 3 then hp, x = "RIGHT", l + w - W
    else hp, x = "", cx - W / 2 end
    if cy > H * 2 / 3 then vp, y = "TOP", b + h - H
    elseif cy < H / 3 then vp, y = "BOTTOM", b
    else vp, y = "", cy - H / 2 end
    local p = vp .. hp
    if p == "" then p = "CENTER" end
    return p, math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10
end

-- Party Frames used to be an entry of their own, placed by the first frame's rect. Its position
-- moves to the shared box (same top-left corner) unless the raid frames had one; both must have
-- been hidden for the shared box to stay hidden.
local function MergePartyIntoRaid()
    local box = _G[RAID_BOX]
    local party = PartyMemberFrame1
    if not box or not party then return end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    for _, layout in pairs(DB().layouts) do
        local old = type(layout.frames) == "table" and layout.frames.PartyMemberFrame1
        if old then
            local new = layout.frames[RAID_BOX] or {}
            if old.p and not new.p then
                local w, h = party:GetWidth() * (old.s or 1), party:GetHeight() * (old.s or 1)
                local l = old.x + (old.p:find("LEFT") and 0 or old.p:find("RIGHT") and W - w or (W - w) / 2)
                local b = old.y + (old.p:find("BOTTOM") and 0 or old.p:find("TOP") and H - h or (H - h) / 2)
                local bw, bh = box:GetWidth(), box:GetHeight()
                new.p, new.x, new.y = ComputeAnchor(l - 4, b + h + 7 - bh, bw, bh)
            end
            new.s = new.s or old.s
            local hide = old.opts and old.opts.hideAll and new.opts and new.opts.hideAll
            new.opts = hide and { hideAll = true } or nil
            layout.frames[RAID_BOX] = (new.p or new.s or new.opts) and new or nil
            layout.frames.PartyMemberFrame1 = nil
        end
    end
end

-- ------------------------------------------------------- apply / restore ----
local function CaptureDefaults(e, f)
    -- per frame: an entry can change frame (the Objective Tracker once ElvUI has made its mover)
    if e.defaults and e.defaultsOf == f then return end
    e.defaults, e.defaultsOf = {}, f
    for i = 1, f:GetNumPoints() do
        e.defaults[i] = { f:GetPoint(i) }
    end
    local s = e.scaleList and _G[e.scaleList[1]] or f
    e.defaultScale = s:GetScale()
end

-- A holder carries action buttons: moving it in combat is as refused as moving them.
local function Blocked(e, f)
    return InCombatLockdown() and (e.holder or e.combatLocked or IsProt(f))
end

-- The frames a scale applies to: a group (party, bosses) scales as one.
local function ScaleFrames(e, f)
    if not e.union and not e.scaleList then return { f } end
    local list = {}
    for _, n in ipairs(e.scaleList or e.scaleFrames or e.union) do
        if _G[n] then list[#list + 1] = _G[n] end
    end
    return list
end

local Attach

-- Hang the pieces of a holder entry from it. A piece Blizzard (or skillTreeMicroButton's
-- positionButtons) re-anchors is hung back; the micro buttons are left to the vehicle
-- bar while it is up, and come back with the positionButtons that follows it.
Attach = function(e)
    if e.skipInVehicle and UnitHasVehicleUI("player") then return end
    local holder = e.holderFrame
    -- collapse: a hidden member gives its slot to the next one (each member advances
    -- the row by the gap it had to the next one in the stock bar)
    local members = e.members
    local x = members[1] and members[1].x
    applying = true
    for i, m in ipairs(members) do
        local g = m.frame
        local r = Ratio(g)
        local mx = m.x
        if e.collapse then
            mx = x
            if not (e.hidden and e.hidden[g]) then
                local nxt = members[i + 1]
                x = x + (nxt and (nxt.x - m.x) or m.w)
            end
        end
        g:ClearAllPoints()
        g:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", mx / r, m.y / r)
        g:SetWidth(m.w)
        g:SetHeight(m.h)
        if not m.hooked then
            m.hooked = true
            -- re-hanging moves every member: with action buttons among them, never in
            -- combat, whichever member Blizzard moved
            hooksecurefunc(g, "SetPoint", function()
                if applying or not e.attached then return end
                if InCombatLockdown() and e.hasProtected then queued[e.key] = true return end
                Attach(e)
            end)
        end
    end
    applying = false
    e.attached = true
end

local function Detach(e)
    if not e.attached then return end
    e.attached = nil
    applying = true
    for _, m in ipairs(e.members) do
        if #m.points > 0 then
            m.frame:ClearAllPoints()
            for _, pt in ipairs(m.points) do m.frame:SetPoint(unpack(pt)) end
        end
    end
    applying = false
end

-- Hide (the generic switch every system has, opts.hideAll): the frames are parked under
-- a hidden parent, the way ElvUI kills Blizzard frames. They keep working (and keep
-- their rect, so the box still shows), Blizzard's Show calls cannot bring them back, and
-- a re-parent (micro buttons into the vehicle bar) is sent back to the hider.
local hider = CreateFrame("Frame", "EbonholdEditModeHider", UIParent)
hider:Hide()

local function HideFramesOf(e)
    if e.getHideFrames then return e.getHideFrames() end
    if e.hideFrames then return e.hideFrames end
    if e.holder then
        local list, seen = {}, {}
        for _, n in ipairs(e.rect) do list[#list + 1] = n seen[n] = true end
        for _, n in ipairs(e.children or {}) do
            if not seen[n] then list[#list + 1] = n end
        end
        return list
    end
    return e.union or { e.key }
end

local function ApplyHideAll(e, on)
    for _, n in ipairs(HideFramesOf(e)) do
        local g = _G[n]
        if g and g.SetParent then
            if on then
                if not g.ebhParked then
                    g.ebhParked = g:GetParent() or UIParent
                    if not g.ebhParkHooked then
                        g.ebhParkHooked = true
                        hooksecurefunc(g, "SetParent", function(self, p)
                            if not self.ebhParked or p == hider then return end
                            if InCombatLockdown() and IsProt(self) then
                                queued[e.key] = true
                                return
                            end
                            self.ebhParked = p
                            self:SetParent(hider)
                        end)
                    end
                    g:SetParent(hider)
                end
            elseif g.ebhParked then
                local p = g.ebhParked
                g.ebhParked = nil
                g:SetParent(p)
            end
        end
    end
    e.isHidden = on or nil
end

local function ApplyEntry(e, o)
    local f = Resolve(e)
    if not f then return end
    if Blocked(e, f) then queued[e.key] = true return end
    CaptureDefaults(e, f)
    -- options first: Attach lays out what they leave shown
    if e.applyOptions then e.applyOptions(o.opts or {}, e) end
    if not e.noHide and (o.opts and o.opts.hideAll or e.isHidden) then
        ApplyHideAll(e, o.opts and o.opts.hideAll)
    end
    if not e.noScale and (o.s or e.scaled) then
        local s = (e.defaultScale or 1) * (o.s or 1)
        for _, g in ipairs(ScaleFrames(e, f)) do g:SetScale(s) end
        e.scaled = o.s and true or nil
    end
    if o.p then
        applying = true
        local r = Ratio(f)
        local rel = e.relativeTo and e.relativeTo(f) or UIParent
        f:ClearAllPoints()
        f:SetPoint(o.p, rel, o.p, o.x / r, o.y / r)
        applying = false
        f.ebhEditModePlaced = true
    end
    -- a collapsing piece is taken over as soon as it hides something, even unmoved
    -- (its holder then still sits on the stock spot)
    if e.holder and (o.p or (e.collapse and o.opts)) then Attach(e) end
    e.placed = true
    if e.rehang then EM.RehangPieces() end
    if e.onMoved then e.onMoved(f) end
end

local function RestoreEntry(e)
    local f = Resolve(e)
    if not f or not e.placed then return end
    if Blocked(e, f) then queued[e.key] = true return end
    applying = true
    if e.defaults and #e.defaults > 0 then
        f:ClearAllPoints()
        for _, pt in ipairs(e.defaults) do f:SetPoint(unpack(pt)) end
    end
    if e.scaled and e.defaultScale then
        for _, g in ipairs(ScaleFrames(e, f)) do g:SetScale(e.defaultScale) end
    end
    e.scaled = nil
    applying = false
    if e.holder then Detach(e) end
    if e.applyOptions then e.applyOptions({}, e) end
    if e.isHidden then ApplyHideAll(e, false) end
    f.ebhEditModePlaced = nil
    e.placed = nil
    if e.rehang then EM.RehangPieces() end
    if e.onMoved then e.onMoved(f) end
end

-- The pieces taken out of the bottom bar are still its children: when its scale
-- changes, hang them again at their place (offsets are kept in UIParent units).
function EM.RehangPieces()
    for _, h in ipairs(entries) do
        if h.attached and not (InCombatLockdown() and h.hasProtected) then Attach(h) end
    end
end

-- Managed frames: Blizzard moved it, put ours back. Native drags of unmanaged frames
-- are written into the active custom layout instead.
local captureFrame = CreateFrame("Frame")
local captureList = {}
captureFrame:Hide()
captureFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    for e in pairs(captureList) do
        captureList[e] = nil
        local f = Resolve(e)
        local l, b, w, h
        if f then l, b, w, h = FrameRect(f) end
        if l and ActiveName() ~= DEFAULT and not editing then
            local o = current[e.key] or {}
            o.p, o.x, o.y = ComputeAnchor(l, b, w, h)
            current[e.key] = o
            SavedFrames()[e.key] = Copy(o)
            f.ebhEditModePlaced = true
            e.placed = true
        end
    end
end)

local function InstallHooks(e, f)
    if e.holder or e.hooked == f then return end
    e.hooked = f
    -- any native drag (the run tracker, Details!, chat, an unlocked player frame) goes
    -- into the layout; read the rect a frame later: the owner may snap it after the drag
    hooksecurefunc(f, "StopMovingOrSizing", function()
        captureList[e] = true
        captureFrame:Show()
    end)
    if not e.unmanaged then
        hooksecurefunc(f, "SetPoint", function()
            if applying then return end
            local o = current[e.key]
            if o then ApplyEntry(e, o) end
        end)
    end
end

-- Details! windows are dynamic: one entry per enabled window.
local function RefreshDetailsEntries()
    local D = _G._detalhes
    if not D or not D.tabela_instancias then return end
    for i, inst in ipairs(D.tabela_instancias) do
        local key = "Details" .. i
        local e = entryByKey[key]
        if not e then
            -- Hide parks the window's two top-level frames (the base frame, and the row
            -- frame that is a sibling of it on UIParent); Details! keeps running and
            -- counting behind it, and its own close button is left alone
            e = { key = key, label = L["Details! Window "] .. i, unmanaged = true, noScale = true,
                  details = i }
            e.getFrame = function()
                local d = _G._detalhes
                local ins = d and d.tabela_instancias and d.tabela_instancias[i]
                if ins and ins.ativa and ins.baseframe then return ins.baseframe end
            end
            e.getHideFrames = function()
                local d = _G._detalhes
                local ins = d and d.tabela_instancias and d.tabela_instancias[i]
                local list = {}
                if ins and ins.baseframe then list[#list + 1] = ins.baseframe:GetName() end
                if ins and ins.rowframe then list[#list + 1] = ins.rowframe:GetName() end
                return list
            end
            e.onMoved = function()
                local d = _G._detalhes
                local ins = d and d.tabela_instancias and d.tabela_instancias[i]
                if ins and ins.SaveMainWindowPosition then ins:SaveMainWindowPosition() end
            end
            -- closed with its own X button: it keeps a box here, shown as hidden, so that
            -- unticking Hide opens it again (a window closed at logout has no frame at all)
            e.closed = function()
                local d = _G._detalhes
                local ins = d and d.tabela_instancias and d.tabela_instancias[i]
                return ins and not ins.ativa and true or false
            end
            e.open = function()
                local d = _G._detalhes
                local ins = d and d.tabela_instancias and d.tabela_instancias[i]
                if ins and not ins.ativa and ins.AtivarInstancia then ins:AtivarInstancia() end
            end
            entries[#entries + 1] = e
            entryByKey[key] = e
        end
    end
end

-- onlyMissing: place only the frames not placed yet (the login retry).
-- UIParent_ManageFramePositions is never called from here: run from addon code it
-- would taint the globals it writes, which the action bars read in combat. A frame
-- given back to Blizzard gets its captured points now and is re-managed on the next
-- event that moves it.
local function ApplyAll(onlyMissing)
    RefreshDetailsEntries()
    local missing = false
    for _, e in ipairs(entries) do
        local f = Resolve(e)
        local o = current[e.key]
        if f then
            CaptureDefaults(e, f)
            InstallHooks(e, f)
            if o then
                if not (onlyMissing and e.placed) then ApplyEntry(e, o) end
            elseif e.placed then
                RestoreEntry(e)
            end
        elseif o then
            missing = true
        end
    end
    return missing
end

-- Frames created late (run tracker on the first server packet, Details! windows):
-- retry a few times after login.
-- Owner 2026-11-16: an element moves only through Edit Mode. A frame listed here that can be dragged
-- on its own (run tracker, echoes, trial tracker, echo choice, Blizzard's focus frame on Old...) is
-- stopped as soon as a drag starts outside Edit Mode; Edit Mode itself moves them while `editing`.
local dragLocked = {}
local function LockDragging(e)
    if e.holder then return end   -- our own holders never take a drag
    local f = Resolve(e)
    if not f or dragLocked[f] or not f.StartMoving then return end
    dragLocked[f] = true
    hooksecurefunc(f, "StartMoving", function(self)
        if not editing then self:StopMovingOrSizing() end
    end)
end

-- The raid frames move through their manager's Unlock button, and Blizzard snaps a raid group onto
-- the cursor BEFORE it starts moving, so stopping the move would leave the group there: the button
-- goes instead, and frames left unlocked are locked again (lockMode = the button would lock).
local function LockRaidManager()
    local toggle = _G.CompactRaidFrameManagerDisplayFrameLockedModeToggle
    if not toggle or toggle.ebhLocked then return end
    toggle.ebhLocked = true
    if toggle.lockMode then toggle:Click() end
    toggle:Hide()
    hooksecurefunc(toggle, "Show", function(self) self:Hide() end)
end

local function LockAllDragging()
    for _, e in ipairs(entries) do LockDragging(e) end
    LockRaidManager()
end

local retry = CreateFrame("Frame")
retry:Hide()
retry:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    self.total = (self.total or 0) + elapsed
    if self.t < 2 then return end
    self.t = 0
    -- frames created late (the echo choice, the trial tracker) are locked as they appear
    LockAllDragging()
    if not ApplyAll(true) or self.total > 30 then self:Hide() end
end)

function EM.ApplyLayout()
    current = Copy(SavedFrames())
    dirty = false
    ApplyAll()
end

-- ------------------------------------------------------------- DragonUI ----
-- DragonUI (embedded, DragonUI\) rebuilds most of the stock HUD and places it from movers of
-- its own, saved in its profile (DragonUIDB). Moving the stock frames from here as well would
-- fight it (both re-anchor on SetPoint), so an entry DragonUI covers is dropped while the
-- DragonUI module behind it is on; its movers show in this Edit Mode instead
-- (DragonUI.EditorMode:ShowMovers / HideMovers: drag, arrow keys, its settings beside the frame).
-- They save as they move, in DragonUI's profile, not in the layouts here: Revert puts back the
-- positions they had when Edit Mode opened, Reset All resets them too.
local DUI_COVER = {
    PlayerFrame = { uf = "player" }, TargetFrame = { uf = "target" }, FocusFrame = { uf = "focus" },
    Boss1TargetFrame = { uf = "boss" },
    MinimapCluster = { mod = "minimap" }, DurabilityFrame = { mod = "minimap" },
    BuffFrame = { mod = "buffs" }, EbonholdEditModeDebuffs = { mod = "buffs" },
    TemporaryEnchantFrame = { mod = "buffs" },
    CastingBarFrame = { mod = "castbar" },
    MainMenuBar = { mod = "mainbars" }, EbonholdEditModeActionBar1 = { mod = "mainbars" },
    EbonholdEditModeXPBar = { mod = "mainbars" },
    MultiBarBottomLeft = { mod = "mainbars" }, MultiBarBottomRight = { mod = "mainbars" },
    MultiBarRight = { mod = "mainbars" }, MultiBarLeft = { mod = "mainbars" },
    EbonholdEditModeMicroMenu = { mod = "micromenu" }, EbonholdEditModeBags = { mod = "micromenu" },
    PetActionBarFrame = { mod = "petbar" }, ShapeshiftBarFrame = { mod = "stance" },
    MultiCastActionBarFrame = { mod = "multicast" },
    EbonholdEditModeTooltipAnchor = { mod = "tooltip" },
}

local function DUI()
    local d = _G.DragonUI
    if d and d.db and d.ModuleRegistry then return d end
end

-- With ElvUI on, DragonUI steps aside (DragonUI\core.lua) and ElvUI moves every one of these
-- frames from its own movers (/moveui): they are dropped from here all the same.
local function DUICovers(c)
    local d = DUI()
    if not d or not c then return false end
    if d.elvui then return true end
    if d.playerOff then return false end   -- the whole interface on Old: every frame is Blizzard's
    if c.uf then return d.UF and d.UF.IsEnabled and d.UF.IsEnabled(c.uf) and true or false end
    return d.ModuleRegistry:IsEnabled(c.mod) and true or false
end

-- Once, before the first layout applies: what DragonUI does not cover stays an entry here.
local function ApplyDragonUICoverage()
    if not DUI() then return end
    -- An element just switched from New (DragonUI) to Old (Blizzard's default) comes back at
    -- Blizzard's default place: a position saved here while DragonUI drew it (or before) pulled the
    -- stock pieces apart (the action buttons hung 67 px above the stock bar, its slots left empty).
    -- Per character, the last login's covered set; no record yet = everything on Old just switched.
    local db = DB()
    db.duiCovered = db.duiCovered or {}
    local who = CharKey()
    local was, now = db.duiCovered[who], {}
    for key, c in pairs(DUI_COVER) do
        if DUICovers(c) then now[key] = true end
    end
    for key in pairs(DUI_COVER) do
        if not now[key] and (was == nil or was[key]) then
            for _, layout in pairs(db.layouts) do
                if type(layout) == "table" and type(layout.frames) == "table" then layout.frames[key] = nil end
            end
        end
    end
    db.duiCovered[who] = now
    local kept = {}
    for _, e in ipairs(entries) do
        if DUICovers(DUI_COVER[e.key]) then
            entryByKey[e.key] = nil
        else
            kept[#kept + 1] = e
        end
    end
    entries = kept
    -- DragonUI's party frames have a mover of their own: the shared box keeps the raid frames.
    local raid = entryByKey[RAID_BOX]
    if raid and DUICovers({ uf = "party" }) then
        raid.label = L["Raid Frames"]
        raid.union, raid.scaleFrames, raid.hideFrames = nil, { "CompactRaidFrameContainer" },
            { "CompactRaidFrameContainer" }
        raid.onMoved = function(f)
            local m = _G.CompactRaidFrameManager
            if not m or not GetActiveRaidProfile or not GetActiveRaidProfile() then return end
            if f.ebhEditModePlaced then
                m.dynamicContainerPosition = false
                CompactRaidFrameManager_ResizeFrame_SavePosition(m)
            else
                CompactRaidFrameManager_ResetContainerPosition()
            end
        end
    end
end

local duiSnapshot
local function DUIDeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = DUIDeepCopy(v) end
    return c
end

-- With ElvUI on, the frames dropped from here (bars, unit frames, minimap, bags, chat...) are placed
-- by ElvUI's own movers: this Edit Mode opens them with ours, so one Edit Mode moves everything.
-- Only the movers: ElvUI's grid and its lock window stay closed (ours are on screen). ElvUI saves
-- their positions itself as they are dropped, so Revert / Reset All do not cover them.
local function ElvUIMovers(show)
    local engine = _G.ElvUI
    local E = type(engine) == "table" and engine[1]
    if not (E and E.ToggleMovers and E.CreatedMovers) or InCombatLockdown() then return end
    if (E.ConfigurationMode and true or false) == show then return end
    -- Clicking a mover fills ElvUI's nudge window, which E:CreateMoverPopup makes (with the lock
    -- window) inside its own /moveui path: create them first, keep the lock window closed.
    if show and not _G.ElvUIMoverPopupWindow and E.CreateMoverPopup then E:CreateMoverPopup() end
    if _G.ElvUIMoverPopupWindow then _G.ElvUIMoverPopupWindow:Hide() end
    -- A mover held when combat closes Edit Mode: ElvUI's drop handler gives up in combat without
    -- ending the move, and the hidden mover would keep the mouse until /reload. Drop it now,
    -- still out of lockdown, with ElvUI's own handler (ends the drag, saves where it is).
    if not show and IsMouseButtonDown("LeftButton") then
        for name in pairs(E.CreatedMovers) do
            local m = _G[name]
            local drop = m and m:IsShown() and m:IsMouseOver() and m:GetScript("OnDragStop")
            if drop then drop(m) end
        end
    end
    E.ConfigurationMode = show
    E:ToggleMovers(show, "ALL")
    -- ElvUI's Objective Frame mover is moved through our Objective Tracker box: one box, not two
    if show and _G.WatchFrameMover then _G.WatchFrameMover:Hide() end
    if not show and _G.ElvUIMoverNudgeWindow then _G.ElvUIMoverNudgeWindow:Hide() end
end

local function DUIShowMovers()
    ElvUIMovers(true)
    local d = DUI()
    if not d or d.playerOff or not d.EditorMode or not d.EditorMode.ShowMovers then return end
    local p = d.db.profile
    duiSnapshot = { widgets = DUIDeepCopy(p.widgets), additional = DUIDeepCopy(p.additional) }
    d.EditorMode:ShowMovers()
end

-- equal up to the float noise DragonUI's save adds (10 comes back as 10.0000001)
local function SameTable(a, b)
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 0.01 end
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not SameTable(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function DUIHideMovers()
    ElvUIMovers(false)
    local d = DUI()
    if d and not d.playerOff and d.EditorMode and d.EditorMode.HideMovers then d.EditorMode:HideMovers() end
    -- DragonUI's positions are shared by the account (DragonUI\core.lua SaveSharedLayout): what this
    -- character moved becomes every character's at their next load.
    if d and not d.playerOff and duiSnapshot and d.SaveSharedLayout then
        local p = d.db.profile
        if not (SameTable(duiSnapshot.widgets, p.widgets) and SameTable(duiSnapshot.additional, p.additional)) then
            d:SaveSharedLayout()
        end
    end
end

-- Revert: the DragonUI positions as they were when Edit Mode opened.
local function DUIRevert()
    local d = DUI()
    if not d or not duiSnapshot or InCombatLockdown() then return end
    local editingMovers = d.EditorMode and d.EditorMode:IsActive()
    if editingMovers then d.EditorMode:HideMovers() end
    d.db.profile.widgets = DUIDeepCopy(duiSnapshot.widgets)
    d.db.profile.additional = DUIDeepCopy(duiSnapshot.additional)
    if d.RefreshConfig then d:RefreshConfig() end
    if editingMovers then d.EditorMode:ShowMovers() end
end

local function DUIResetAll()
    local d = DUI()
    if not d or not d.EditorMode or not d.EditorMode.ResetAllPositions then return end
    d.EditorMode:ResetAllPositions()
end

-- --------------------------------------------------------------- tooltip ----
local tipAnchor = CreateFrame("Frame", "EbonholdEditModeTooltipAnchor", UIParent)
tipAnchor:SetSize(180, 64)
tipAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT",
    -(CONTAINER_OFFSET_X or 0) - 13, CONTAINER_OFFSET_Y or 70)

hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
    -- no entry: DragonUI's tooltip module places it (ApplyDragonUICoverage)
    local o = entryByKey["EbonholdEditModeTooltipAnchor"] and current["EbonholdEditModeTooltipAnchor"]
    if not o then return end
    tooltip:ClearAllPoints()
    tooltip:SetPoint(o.p, tipAnchor, o.p, 0, 0)
end)

-- ------------------------------------------------------------------ grid ----
local function BuildGrid()
    if not grid then
        grid = CreateFrame("Frame", nil, UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid.lines = {}
    end
    for _, t in ipairs(grid.lines) do t:Hide() end
    local spacing = DB().grid.spacing
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local n = 0
    local function Line(vertical, offset, center)
        n = n + 1
        local t = grid.lines[n]
        if not t then
            t = grid:CreateTexture(nil, "BACKGROUND")
            grid.lines[n] = t
        end
        if center then t:SetTexture(1, 0.82, 0, 0.35) else t:SetTexture(1, 1, 1, 0.12) end
        t:ClearAllPoints()
        if vertical then
            t:SetWidth(1)
            t:SetPoint("TOP", grid, "TOP", offset, 0)
            t:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
        else
            t:SetHeight(1)
            t:SetPoint("LEFT", grid, "LEFT", 0, offset)
            t:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
        end
        t:Show()
    end
    Line(true, 0, true)
    Line(false, 0, true)
    for k = 1, math.floor(W / 2 / spacing) do
        Line(true, k * spacing) Line(true, -k * spacing)
    end
    for k = 1, math.floor(H / 2 / spacing) do
        Line(false, k * spacing) Line(false, -k * spacing)
    end
end

local function UpdateGridShown()
    if editing and DB().grid.show then
        BuildGrid()
        grid:Show()
    elseif grid then
        grid:Hide()
    end
end

-- Offset that brings the nearest edge or centre of [lo, lo + size] onto a grid line.
local function SnapAxis(lo, size, total)
    local spacing = DB().grid.spacing
    local mid = total / 2
    local best
    for _, v in ipairs({ lo, lo + size / 2, lo + size }) do
        local line = mid + math.floor((v - mid) / spacing + 0.5) * spacing
        local d = line - v
        if math.abs(d) <= SNAP_DISTANCE and (not best or math.abs(d) < math.abs(best)) then best = d end
    end
    return best or 0
end

-- -------------------------------------------------------------- overlays ----
local UpdatePanel, ShowSystemDialog

local function PaintOverlay(ov)
    local sel = selected and selected.overlay == ov
    local a = ov.hover and 0.4 or 0.25
    if sel then
        ov.fill:SetTexture(1, 0.82, 0, a)
        for _, t in ipairs(ov.edges) do t:SetTexture(1, 0.82, 0, 1) end
    else
        ov.fill:SetTexture(0, 0.55, 1, a)
        for _, t in ipairs(ov.edges) do t:SetTexture(0.3, 0.7, 1, 0.9) end
    end
end

local function PlaceOverlay(e)
    local ov = e.overlay
    local f = Resolve(e)
    local l, b, w, h
    if f and Visible(e, f) then l, b, w, h = BoxRect(e, f) end
    if l then
        e.lastBox = { l, b, w, h }
    elseif (f and e.isHidden) or (not f and e.closed and e.closed()) then
        -- a parked frame may not report a rect, and a closed Details! window has none:
        -- its box must stay, or Hide could not be undone
        local lb = e.lastBox or { UIParent:GetWidth() / 2 - 80, UIParent:GetHeight() / 2 - 20, 160, 40 }
        l, b, w, h = lb[1], lb[2], lb[3], lb[4]
    end
    if not l then ov:Hide() return end
    if w < MIN_BOX_W then l = l - (MIN_BOX_W - w) / 2 w = MIN_BOX_W end
    if h < MIN_BOX_H then b = b - (MIN_BOX_H - h) / 2 h = MIN_BOX_H end
    local shownHidden = e.isHidden or (e.closed and e.closed())
    ov.label:SetText(shownHidden and (e.label .. L[" |cff999999(Hidden)|r"]) or e.label)
    ov:ClearAllPoints()
    ov:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    ov:SetSize(w, h)
    -- smaller boxes on top: the pieces of the bottom bar sit inside its own box
    ov:SetFrameLevel(UIParent:GetFrameLevel() + 1 + math.max(0, 60 - math.floor(w * h / 2000)))
    ov:Show()
end

local function Select(e)
    local prev = selected
    selected = e
    if prev and prev.overlay then PaintOverlay(prev.overlay) end
    if e and e.overlay then PaintOverlay(e.overlay) end
    ShowSystemDialog()
end

-- Move a frame so that its own rect starts at (l, b), into `current`.
local function MoveFrameTo(e, l, b, w, h)
    local o = current[e.key] or {}
    o.p, o.x, o.y = ComputeAnchor(l, b, w, h)
    current[e.key] = o
    ApplyEntry(e, o)
    dirty = true
end

local function DragUpdate(ov)
    local e = ov.entry
    local dx, dy = ov:GetLeft() - ov.startL, ov:GetBottom() - ov.startB
    if DB().grid.snap then
        dx = dx + SnapAxis(ov.startL + dx, ov:GetWidth(), UIParent:GetWidth())
        dy = dy + SnapAxis(ov.startB + dy, ov:GetHeight(), UIParent:GetHeight())
    end
    local r = ov.frameRect
    MoveFrameTo(e, r[1] + dx, r[2] + dy, r[3], r[4])
end

local function CreateOverlay(e)
    local ov = CreateFrame("Button", nil, UIParent)
    -- above DIALOG: the echo choice sits there at level 100 and would take the drag
    ov:SetFrameStrata("FULLSCREEN")
    ov:SetMovable(true)
    ov:SetClampedToScreen(true)
    ov:EnableMouse(true)
    ov:RegisterForDrag("LeftButton")
    ov:RegisterForClicks("LeftButtonUp")
    ov.entry = e
    ov.fill = ov:CreateTexture(nil, "BACKGROUND")
    ov.fill:SetAllPoints()
    ov.edges = {}
    for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = ov:CreateTexture(nil, "BORDER")
        t:SetPoint(spec[1]) t:SetPoint(spec[2])
        if i <= 2 then t:SetHeight(2) else t:SetWidth(2) end
        ov.edges[i] = t
    end
    ov.label = ov:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ov.label:SetPoint("CENTER")
    ov.label:SetText(e.label)
    ov:SetScript("OnEnter", function(self) self.hover = true PaintOverlay(self) end)
    ov:SetScript("OnLeave", function(self) self.hover = nil PaintOverlay(self) end)
    ov:SetScript("OnClick", function(self) Select(self.entry) end)
    ov:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local f = Resolve(self.entry)
        local l, b, w, h
        if f then l, b, w, h = FrameRect(f) end
        if not l then return end
        Select(self.entry)
        self.frameRect = { l, b, w, h }
        self.startL, self.startB = self:GetLeft(), self:GetBottom()
        self:StartMoving()
        self:SetScript("OnUpdate", DragUpdate)
    end)
    ov:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        if self.frameRect then DragUpdate(self) end
        self.frameRect = nil
        PlaceOverlay(self.entry)
        UpdatePanel()
    end)
    e.overlay = ov
    PaintOverlay(ov)
    return ov
end

local function ShowOverlays()
    RefreshDetailsEntries()
    for _, e in ipairs(entries) do
        local f = Resolve(e)
        if f then
            CaptureDefaults(e, f)
            InstallHooks(e, f)
            if not e.overlay then CreateOverlay(e) end
            PlaceOverlay(e)
        elseif e.closed and e.closed() then
            if not e.overlay then CreateOverlay(e) end
            PlaceOverlay(e)
        elseif e.overlay then
            e.overlay:Hide()
        end
    end
end

-- also ends a drag cut short (combat closes Edit Mode mid-drag): a box left moving
-- would stick to the cursor when Edit Mode opens again
local function HideOverlays()
    for _, e in ipairs(entries) do
        local ov = e.overlay
        if ov then
            if ov.frameRect then
                ov:StopMovingOrSizing()
                ov:SetScript("OnUpdate", nil)
                ov.frameRect = nil
            end
            ov:Hide()
        end
    end
end

local function RefreshOverlays()
    if not editing then return end
    for _, e in ipairs(entries) do
        if e.overlay and Resolve(e) then PlaceOverlay(e) end
    end
end

-- ---------------------------------------------------------------- actions ----
local function CreateLayout(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" or name == DEFAULT then
        UIErrorsFrame:AddMessage(L["Choose another layout name."], 1, 0.1, 0.1)
        return
    end
    if DB().layouts[name] then
        UIErrorsFrame:AddMessage(T("A layout named \"{name}\" already exists.", { name = name }), 1, 0.1, 0.1)
        return
    end
    DB().layouts[name] = { frames = Copy(current) }
    SetActiveName(name)
    dirty = false
    Notify(T("layout \"{name}\" saved.", { name = name }))
    UpdatePanel()
end

function EM.Save()
    if ActiveName() == DEFAULT then
        StaticPopup_Show("EBONHOLD_EDITMODE_NEWLAYOUT")
        return
    end
    DB().layouts[ActiveName()].frames = Copy(current)
    dirty = false
    Notify(T("layout \"{name}\" saved.", { name = ActiveName() }))
    UpdatePanel()
end

function EM.Revert()
    DUIRevert()
    EM.ApplyLayout()
    RefreshOverlays()
    ShowSystemDialog()
    UpdatePanel()
end

local function SwitchLayout(name)
    SetActiveName(name)
    EM.ApplyLayout()
    RefreshOverlays()
    ShowSystemDialog()
    UpdatePanel()
end

function EM.ResetSelected()
    if not selected then return end
    current[selected.key] = nil
    RestoreEntry(selected)
    ApplyAll()
    dirty = true
    RefreshOverlays()
    ShowSystemDialog()
    UpdatePanel()
end

function EM.ResetAll()
    DUIResetAll()
    current = {}
    for _, e in ipairs(entries) do RestoreEntry(e) end
    ApplyAll()
    dirty = true
    RefreshOverlays()
    ShowSystemDialog()
    UpdatePanel()
end

-- -------------------------------------------------------------- popups ----
-- StaticPopups live in DIALOG, under the panel (FULLSCREEN_DIALOG): lift ours above
-- it while shown, and hand the shared popup frame back as it was.
local function RaisePopup(self)
    self.ebhStrata = self:GetFrameStrata()
    self:SetFrameStrata("TOOLTIP")
end

local function LowerPopup(self)
    if self.ebhStrata then self:SetFrameStrata(self.ebhStrata) self.ebhStrata = nil end
end

StaticPopupDialogs["EBONHOLD_EDITMODE_NEWLAYOUT"] = {
    text = L["Name the new layout:"],
    button1 = SAVE,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnHide = LowerPopup,
    OnShow = function(self)
        RaisePopup(self)
        local eb = _G[self:GetName() .. "EditBox"]
        eb:SetText("")
        eb:SetFocus()
    end,
    OnAccept = function(self)
        CreateLayout(_G[self:GetName() .. "EditBox"]:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        CreateLayout(self:GetText())
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EBONHOLD_EDITMODE_UNSAVED"] = {
    text = L["You have unsaved changes to your layout."],
    OnShow = RaisePopup,
    OnHide = LowerPopup,
    button1 = SAVE,
    button2 = L["Discard"],
    OnAccept = function() EM.Save() EM.Exit(true) end,
    OnCancel = function(_, _, reason)
        if reason ~= "timeout" and reason ~= "override" then EM.Revert() EM.Exit(true) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    preferredIndex = 3,
}

StaticPopupDialogs["EBONHOLD_EDITMODE_SWITCH"] = {
    text = L["Discard your unsaved changes and switch layout?"],
    OnShow = RaisePopup,
    OnHide = LowerPopup,
    button1 = YES,
    button2 = NO or "No",
    OnAccept = function(_, data) SwitchLayout(data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EBONHOLD_EDITMODE_DELETE"] = {
    text = L["Delete the layout \"%s\"?"],
    OnShow = RaisePopup,
    OnHide = LowerPopup,
    button1 = DELETE,
    button2 = CANCEL,
    OnAccept = function(_, data)
        DB().layouts[data] = nil
        SwitchLayout(DEFAULT)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ----------------------------------------------------------------- panel ----
local function MakeButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

local function MakeCheck(parent, name, text, onClick)
    local c = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    _G[name .. "Text"]:SetText(text)
    c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return c
end

local function MakeDialog(name, width, height, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(math.max(256, width * 0.6), 64)
    header:SetPoint("TOP", 0, 12)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", header, "TOP", 0, -14)
    f.title:SetText(title)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    f.close = close
    f:Hide()
    return f
end

-- The dropdown list shares FULLSCREEN_DIALOG with the panel and can open under it:
-- lift it while it is ours, hand it back when it closes.
local function RaiseDropDownList()
    local list = DropDownList1
    if not list or list.ebhStrata then return end
    list.ebhStrata = list:GetFrameStrata()
    list:SetFrameStrata("TOOLTIP")
    if not list.ebhHooked then
        list.ebhHooked = true
        list:HookScript("OnHide", function(self)
            if self.ebhStrata then self:SetFrameStrata(self.ebhStrata) self.ebhStrata = nil end
        end)
    end
end

local function LayoutDropDownInit()
    RaiseDropDownList()
    local info
    local names = {}
    for n in pairs(DB().layouts) do names[#names + 1] = n end
    table.sort(names)
    table.insert(names, 1, DEFAULT)
    for _, n in ipairs(names) do
        info = UIDropDownMenu_CreateInfo()
        info.text = (n == DEFAULT) and L["Default (Blizzard)"] or n
        info.checked = (n == ActiveName())
        info.func = function()
            if n == ActiveName() then return end
            if dirty then
                StaticPopup_Show("EBONHOLD_EDITMODE_SWITCH", nil, nil, n)
            else
                SwitchLayout(n)
            end
        end
        UIDropDownMenu_AddButton(info)
    end
    info = UIDropDownMenu_CreateInfo()
    info.text = L["|cff33ff33New Layout...|r"]
    info.notCheckable = 1
    info.func = function() StaticPopup_Show("EBONHOLD_EDITMODE_NEWLAYOUT") end
    UIDropDownMenu_AddButton(info)
end

-- ------------------------------------------------------ nameplates dialog ----
-- DragonUI's nameplates have no box to drag, so their few player-facing switches live in a
-- dialog of their own, opened from the panel: the art (Modern / Heritage / Blizzard's own
-- plates) and the size. Labels are DragonUI's own option strings, already translated in
-- its locale files. A style change needs a reload (DragonUI's Reload popup stages it); the
-- sizes apply live.
local npDialog
local PANEL_H = 196        -- the Edit Mode panel without the interface row and the nameplates section
local UI_SECTION_H = 52    -- the whole interface New / Old row (CreateWholeInterfaceRow)
local NP_SECTION_H = 165   -- title, New / Old, two rows of sliders, room above the bottom buttons

local function NPDragon()
    local d = _G.DragonUI
    if d and d.db and d.db.profile and d.Reload and d.EditorSettings and not d.elvui and not d.playerOff
        and not d.nameplateAddon then return d end
end

local function NPLabel(key)
    local d = NPDragon()
    return d and d.EditorSettings.Label(key) or key
end

local NP_PATH = "modules.nameplates."
-- each art comes with the bar size its textures are cut for (database.lua barWidth)
-- New / Old like every other element (owner 2026-11-16): DragonUI's plates or Blizzard's.
local NP_STYLES = {
    { key = "modern",   label = "New (DragonUI)",         w = 148, h = 16 },
    { key = "blizzard", label = "Old (Blizzard Default)" },
}
local NP_SLIDERS = {
    { field = "barWidth",  label = "Bar Width",  min = 60, max = 200, step = 2, def = 148 },
    { field = "barHeight", label = "Bar Height", min = 4,  max = 24,  step = 1, def = 16 },
    { field = "fontSize",  label = "Font Size",  min = 1,  max = 10,  step = 1, def = 2 },
}

-- What the dialog shows: the staged choice if a reload is pending, else what runs.
local function NPStyle(d)
    if not d.Reload.ModuleState("nameplates") then return "blizzard" end
    return "modern"   -- an older profile's Heritage art is DragonUI's too (DragonUI\core.lua moves it to Modern)
end

local function NPPending(d)
    return d.Reload.IsStaged(NP_PATH .. "plateStyle")
        or d.Reload.ModuleState("nameplates") ~= (d.ModuleRegistry and d.ModuleRegistry:IsEnabled("nameplates") and true or false)
end

local RefreshNPDialog

local function PickNPStyle(key)
    local d = NPDragon()
    if not d or InCombatLockdown() then RefreshNPDialog() return end
    if key == "blizzard" then
        d:SetModuleEnabled("nameplates", false)
    else
        d:SetModuleEnabled("nameplates", true)
        local cur = d.db.profile.modules.nameplates and d.db.profile.modules.nameplates.plateStyle
        local same = (key == "legacy") == (cur == "legacy" or cur == "classic")
        if same then
            -- back to the running art: drop what a previous pick staged
            d.Reload.Stage(NP_PATH .. "plateStyle", cur)
            d.Reload.Stage(NP_PATH .. "barWidth", d.EditorSettings.GetDB(NP_PATH .. "barWidth"))
            d.Reload.Stage(NP_PATH .. "barHeight", d.EditorSettings.GetDB(NP_PATH .. "barHeight"))
        else
            for _, s in ipairs(NP_STYLES) do
                if s.key == key then
                    d.Reload.Stage(NP_PATH .. "plateStyle", key)
                    d.Reload.Stage(NP_PATH .. "barWidth", s.w)
                    d.Reload.Stage(NP_PATH .. "barHeight", s.h)
                end
            end
        end
    end
    RefreshNPDialog()
end

RefreshNPDialog = function()
    if not npDialog or not npDialog:IsShown() then return end
    local d = NPDragon()
    if not d then npDialog:Hide() return end
    local style = NPStyle(d)
    for _, c in ipairs(npDialog.styles) do c:SetChecked(c.styleKey == style) end
    -- sizes are frozen while Blizzard's plates are picked or an art change waits for a reload
    local frozen = style == "blizzard" or NPPending(d)
    for _, s in ipairs(npDialog.sliders) do
        local def = s.def
        local v = tonumber(d.Reload.Get(NP_PATH .. def.field)) or def.def
        s.silent = true
        s:SetValue(v)
        s.silent = nil
        _G[s:GetName() .. "Text"]:SetText(NPLabel(def.label) .. ": " .. v)
        if frozen then s:Disable() s:SetAlpha(0.5) else s:Enable() s:SetAlpha(1) end
    end
end

local function CreateNPDialog()
    -- A section of the panel itself, under its own title (owner 2026-11-16: no button, the options
    -- in plain view). Below the grid spacing; UpdatePanel shows it and grows the panel.
    npDialog = CreateFrame("Frame", nil, panel)
    local top = -158 - (panel.wholeUI and UI_SECTION_H or 0)
    npDialog:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, top)
    npDialog:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, top)
    npDialog:SetHeight(NP_SECTION_H)
    npDialog:SetScript("OnShow", function() RefreshNPDialog() end)
    local title = npDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 22, -6)
    title:SetText(NPLabel("Nameplates"))
    -- Cancel on the reload popup drops what was staged: show the running state again
    local d = NPDragon()
    if d and d.Reload.OnDiscard then d.Reload.OnDiscard(function() RefreshNPDialog() end) end

    npDialog.styles = {}
    for i, s in ipairs(NP_STYLES) do
        local c = MakeCheck(npDialog, "EbonholdEditModeNPStyle" .. i, NPLabel(s.label), function()
            PickNPStyle(s.key)
        end)
        c.styleKey = s.key
        c:SetPoint("TOPLEFT", 20 + (i - 1) * 200, -26)   -- New and Old side by side
        npDialog.styles[i] = c
    end

    npDialog.sliders = {}
    for i, def in ipairs(NP_SLIDERS) do
        local name = "EbonholdEditModeNPSlider" .. i
        local s = CreateFrame("Slider", name, npDialog, "OptionsSliderTemplate")
        -- two per row: Bar Width and Bar Height, then Font Size
        s:SetPoint("TOPLEFT", 26 + ((i - 1) % 2) * 200, -72 - math.floor((i - 1) / 2) * 46)
        s:SetWidth(180)
        s:SetMinMaxValues(def.min, def.max)
        s:SetValueStep(def.step)
        _G[name .. "Low"]:SetText(def.min)
        _G[name .. "High"]:SetText(def.max)
        s.def = def
        s:SetScript("OnValueChanged", function(self, v)
            v = math.floor(v / def.step + 0.5) * def.step
            _G[name .. "Text"]:SetText(NPLabel(def.label) .. ": " .. v)
            if self.silent then return end
            local d = NPDragon()
            if not d or InCombatLockdown() then return end
            local path = NP_PATH .. def.field
            if tonumber(d.EditorSettings.GetDB(path)) == v then return end
            d.EditorSettings.SetDB(path, v)
            d:RefreshNameplates()
        end)
        npDialog.sliders[i] = s
    end
end

-- ---------------------------------------------------- whole interface row ----
-- New (DragonUI) / Old (Blizzard) for the WHOLE interface (owner, 2026-11-18: a way to turn DragonUI
-- off entirely). Old = DragonUI global.playerOff: at the next load DragonUI\core.lua keeps the
-- player's switches and turns every one of them off (as with ElvUI), so New brings back exactly
-- what the player had. Our quest tracker in DragonUI's design follows, its setting kept the same
-- way. It takes a reload, asked for in a popup.
local function WholeDragon()
    local d = _G.DragonUI
    if d and d.db and d.db.global then return d end
end

local function SetWholeInterface(old)
    local d = WholeDragon()
    if not d or InCombatLockdown() then return end
    local g = d.db.global
    local svc = _G.ProjectEbonholdOptionsService
    if old then
        g.playerOff = true
        if svc and svc.GetSetting and svc.SetSetting and g.playerOffQuestTracker == nil then
            g.playerOffQuestTracker = svc:GetSetting("dfQuestTracker") and true or false
            svc:SetSetting("dfQuestTracker", false)
        end
    else
        g.playerOff = nil
        if svc and svc.SetSetting and g.playerOffQuestTracker ~= nil then
            svc:SetSetting("dfQuestTracker", g.playerOffQuestTracker)
        end
        g.playerOffQuestTracker = nil
    end
    ReloadUI()
end

StaticPopupDialogs["EBONHOLD_EDITMODE_WHOLE_UI"] = {
    text = "%s",
    button1 = L["Reload Now"],
    button2 = CANCEL,
    OnAccept = function(self, old) SetWholeInterface(old) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateWholeInterfaceRow()
    local row = CreateFrame("Frame", nil, panel)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -158)
    row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -158)
    row:SetHeight(UI_SECTION_H)
    local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 22, -6)
    title:SetText(L["Whole Interface"])
    -- the boxes show what runs; a pick only asks, the reload makes it true
    local function Pick(old)
        local d = WholeDragon()
        UpdatePanel()
        if not d or (d.playerOff and true or false) == old then return end
        local text = old
            and L["Turn DragonUI off and use Blizzard's interface everywhere? Your DragonUI settings are kept for when you switch back. The interface reloads; unsaved Edit Mode changes are lost."]
            or L["Turn DragonUI back on, with the settings you had? The interface reloads; unsaved Edit Mode changes are lost."]
        local popup = StaticPopup_Show("EBONHOLD_EDITMODE_WHOLE_UI", text)
        if popup then popup.data = old end
    end
    row.new = MakeCheck(row, "EbonholdEditModeWholeUINew", L["New (DragonUI)"], function() Pick(false) end)
    row.new:SetPoint("TOPLEFT", 20, -24)
    row.old = MakeCheck(row, "EbonholdEditModeWholeUIOld", L["Old (Blizzard)"], function() Pick(true) end)
    row.old:SetPoint("TOPLEFT", 220, -24)
    return row
end

local function CreatePanel()
    panel = MakeDialog("EbonholdEditModePanel", 430, PANEL_H, L["Edit Mode"])
    panel:SetPoint("TOP", UIParent, "TOP", 0, -60)
    panel.close:SetScript("OnClick", function() EM.Exit() end)
    -- Escape closes it (and does not open the game menu); OnHide routes to Exit.
    tinsert(UISpecialFrames, "EbonholdEditModePanel")
    panel:SetScript("OnHide", function() if editing then EM.Exit() end end)

    local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 22, -34)
    lbl:SetText(L["Layout"])
    local dd = CreateFrame("Frame", "EbonholdEditModeLayoutDropDown", panel, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", 4, -46)
    UIDropDownMenu_SetWidth(dd, 190)
    UIDropDownMenu_Initialize(dd, LayoutDropDownInit)
    panel.dropdown = dd

    panel.delete = MakeButton(panel, DELETE, 90)
    panel.delete:SetPoint("LEFT", dd, "RIGHT", -6, 2)
    panel.delete:SetScript("OnClick", function()
        local n = ActiveName()
        if n ~= DEFAULT then StaticPopup_Show("EBONHOLD_EDITMODE_DELETE", n, nil, n) end
    end)

    panel.showGrid = MakeCheck(panel, "EbonholdEditModeShowGrid", L["Show Grid"], function(v)
        DB().grid.show = v
        UpdateGridShown()
    end)
    panel.showGrid:SetPoint("TOPLEFT", 20, -82)
    panel.snap = MakeCheck(panel, "EbonholdEditModeSnap", L["Snap to Grid"], function(v)
        DB().grid.snap = v
    end)
    panel.snap:SetPoint("TOPLEFT", 140, -82)


    local s = CreateFrame("Slider", "EbonholdEditModeGridSpacing", panel, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 26, -128)
    s:SetWidth(200)
    s:SetMinMaxValues(10, 100)
    s:SetValueStep(5)
    _G["EbonholdEditModeGridSpacingLow"]:SetText("10")
    _G["EbonholdEditModeGridSpacingHigh"]:SetText("100")
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / 5 + 0.5) * 5
        _G["EbonholdEditModeGridSpacingText"]:SetText(T("Grid Spacing: {v}", { v = v }))
        if DB().grid.spacing ~= v then
            DB().grid.spacing = v
            UpdateGridShown()
        end
    end)
    panel.spacing = s

    if WholeDragon() then panel.wholeUI = CreateWholeInterfaceRow() end

    panel.resetAll = MakeButton(panel, L["Reset All"], 110)
    panel.resetAll:SetPoint("BOTTOMLEFT", 18, 18)
    panel.resetAll:SetScript("OnClick", function() EM.ResetAll() end)
    panel.save = MakeButton(panel, SAVE, 110)
    panel.save:SetPoint("BOTTOMRIGHT", -18, 18)
    panel.save:SetScript("OnClick", function() EM.Save() end)
    panel.revert = MakeButton(panel, L["Revert Changes"], 120)
    panel.revert:SetPoint("RIGHT", panel.save, "LEFT", -6, 0)
    panel.revert:SetScript("OnClick", function() EM.Revert() end)
end

UpdatePanel = function()
    if not panel then return end
    local n = ActiveName()
    UIDropDownMenu_SetText(panel.dropdown, ((n == DEFAULT) and L["Default (Blizzard)"] or n) .. (dirty and " *" or ""))
    if n == DEFAULT then panel.delete:Disable() else panel.delete:Enable() end
    if dirty then panel.save:Enable() panel.revert:Enable() else panel.save:Disable() panel.revert:Disable() end
    panel.showGrid:SetChecked(DB().grid.show)
    panel.snap:SetChecked(DB().grid.snap)
    panel.spacing:SetValue(DB().grid.spacing)
    local height = PANEL_H
    if panel.wholeUI then
        local d = WholeDragon()
        local old = d and d.playerOff and true or false
        panel.wholeUI.new:SetChecked(not old)
        panel.wholeUI.old:SetChecked(old)
        height = height + UI_SECTION_H
    end
    -- DragonUI's nameplates section (gone with ElvUI on: its plates are ElvUI's; gone with the
    -- whole interface on Old)
    if NPDragon() then
        if not npDialog then CreateNPDialog() end
        npDialog:Show()
        RefreshNPDialog()
        height = height + NP_SECTION_H
    elseif npDialog then
        npDialog:Hide()
    end
    panel:SetHeight(height)
end

-- ------------------------------------------------- selected-system dialog ----
local function CreateSystemDialog()
    sysDialog = MakeDialog("EbonholdEditModeSystemDialog", 280, 140, "")
    sysDialog:SetPoint("TOP", panel, "BOTTOM", 0, -6)
    sysDialog.close:SetScript("OnClick", function() Select(nil) end)

    local s = CreateFrame("Slider", "EbonholdEditModeScale", sysDialog, "OptionsSliderTemplate")
    s:SetPoint("TOP", 0, -50)
    s:SetWidth(200)
    s:SetMinMaxValues(50, 200)
    s:SetValueStep(5)
    _G["EbonholdEditModeScaleLow"]:SetText("50%")
    _G["EbonholdEditModeScaleHigh"]:SetText("200%")
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / 5 + 0.5) * 5
        _G["EbonholdEditModeScaleText"]:SetText(T("Scale: {v}%", { v = v }))
        if self.silent or not selected or InCombatLockdown() then return end
        local f = Resolve(selected)
        local l, b, w, h
        if f then l, b, w, h = FrameRect(f) end
        if not l then return end
        local o = current[selected.key] or {}
        if not o.p then
            o.p, o.x, o.y = ComputeAnchor(l, b, w, h)
            current[selected.key] = o
        end
        local scale = v / 100
        if (o.s or 1) == scale then return end
        o.s = (scale ~= 1) and scale or nil
        ApplyEntry(selected, o)
        dirty = true
        PlaceOverlay(selected)
        UpdatePanel()
    end)
    sysDialog.scale = s

    -- per-system switches (entry.options), stored in the override's opts; created as
    -- needed, laid out by ShowSystemDialog
    sysDialog.opts = {}
    sysDialog.optHeader = sysDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    -- position, scale and switches all go back to stock
    sysDialog.reset = MakeButton(sysDialog, L["Reset To Default"], 200)
    sysDialog.reset:SetPoint("BOTTOM", 0, 20)
    sysDialog.reset:SetScript("OnClick", function() EM.ResetSelected() end)

    -- A frame set to Old (Blizzard's default) has no DragonUI mover, so no DragonUI dialog either:
    -- this box is the one place it can be put back to New. Staging it opens DragonUI's "Reload Now".
    sysDialog.dragon = MakeButton(sysDialog, L["Switch to New (DragonUI)"], 200)
    sysDialog.dragon:SetPoint("BOTTOM", 0, 48)
    sysDialog.dragon:SetScript("OnClick", function()
        local c = selected and DUI_COVER[selected.key]
        local d = DUI()
        if not (c and d and d.Reload) or InCombatLockdown() then return end
        if c.uf then
            d.Reload.Stage("unitframe." .. c.uf .. ".enabled", true)
        else
            d:SetModuleEnabled(c.mod, true)
        end
    end)
end

-- Every system gets Hide first, then its own switches.
local HIDE_OPTION = { key = "hideAll", label = L["Hide"] }

local function OptionsOf(e)
    if not e.allOptions then
        local list = {}
        if not e.noHide then list[1] = HIDE_OPTION end
        for _, opt in ipairs(e.options or {}) do list[#list + 1] = opt end
        e.allOptions = list
    end
    return e.allOptions
end

-- invert: the box reads "shown" while the stored switch says "hidden"
local function OptionCheck(i)
    local c = sysDialog.opts[i]
    if c then return c end
    c = MakeCheck(sysDialog, "EbonholdEditModeOption" .. i, "", function(v)
        local opt = selected and OptionsOf(selected)[i]
        if not opt or InCombatLockdown() then return end
        if opt.invert then v = not v end
        -- a closed Details! window reads hidden: unticking Hide opens it
        if opt == HIDE_OPTION and not v and selected.closed and selected.closed() then
            selected.open()
            local f = Resolve(selected)
            if f then
                CaptureDefaults(selected, f)
                InstallHooks(selected, f)
            end
        end
        local o = current[selected.key] or {}
        o.opts = o.opts or {}
        o.opts[opt.key] = v or nil
        if not next(o.opts) then o.opts = nil end
        if o.p or o.s or o.opts then
            current[selected.key] = o
            ApplyEntry(selected, o)
        else
            current[selected.key] = nil
            RestoreEntry(selected)
        end
        dirty = true
        PlaceOverlay(selected)
        ShowSystemDialog()
        UpdatePanel()
    end)
    sysDialog.opts[i] = c
    return c
end

ShowSystemDialog = function()
    if not sysDialog then return end
    if not editing or not selected then sysDialog:Hide() return end
    sysDialog.title:SetText(selected.label)
    local o = current[selected.key]
    sysDialog.scale.silent = true
    sysDialog.scale:SetValue(((o and o.s) or 1) * 100)
    sysDialog.scale.silent = nil
    if selected.noScale then sysDialog.scale:Hide() else sysDialog.scale:Show() end
    local options = OptionsOf(selected)
    local top = selected.noScale and -40 or -80
    local function Fill(c, opt)
        local on = o and o.opts and o.opts[opt.key] and true or false
        if opt == HIDE_OPTION and selected.closed and selected.closed() then on = true end
        if opt.invert then on = not on end
        _G[c:GetName() .. "Text"]:SetText(opt.label)
        c:SetChecked(on)
        c:ClearAllPoints()
        c:Show()
    end
    -- Hide on its own line, then the system's own switches under their title
    local first = 1
    if options[1] == HIDE_OPTION then
        local c = OptionCheck(1)
        Fill(c, HIDE_OPTION)
        c:SetPoint("TOPLEFT", 24, top)
        top = top - 28
        first = 2
    end
    local count = #options - first + 1
    if selected.optionsTitle and count > 0 then
        sysDialog.optHeader:ClearAllPoints()
        sysDialog.optHeader:SetPoint("TOPLEFT", 26, top)
        sysDialog.optHeader:SetText(selected.optionsTitle)
        sysDialog.optHeader:Show()
        top = top - 16
    else
        sysDialog.optHeader:Hide()
    end
    local cols = (count > 4) and 2 or 1
    for i = first, #options do
        local c = OptionCheck(i)
        local j = i - first
        Fill(c, options[i])
        c:SetPoint("TOPLEFT", 24 + (j % cols) * 124, top - math.floor(j / cols) * 24)
    end
    for i = #options + 1, #sysDialog.opts do sysDialog.opts[i]:Hide() end
    local rows = math.ceil(count / cols)
    -- an element DragonUI draws on New, currently left to Blizzard (Old): offer the way back
    local cover, d = DUI_COVER[selected.key], DUI()
    local canNew = cover and d and d.Reload and not d.elvui and not d.playerOff and not DUICovers(cover)
    if canNew then sysDialog.dragon:Show() else sysDialog.dragon:Hide() end
    sysDialog:SetHeight(math.max(110, -top + rows * 24 + 60) + (canNew and 30 or 0))
    if o then sysDialog.reset:Enable() else sysDialog.reset:Disable() end
    sysDialog:Show()
end

-- ------------------------------------------------------------ enter / exit ----
function EM.Enter()
    if editing then return end
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
        return
    end
    if not panel then CreatePanel() CreateSystemDialog() end
    LockAllDragging()
    editing = true
    if not dirty then current = Copy(SavedFrames()) end
    ShowOverlays()
    DUIShowMovers()
    UpdateGridShown()
    panel:Show()
    UpdatePanel()
    ShowSystemDialog()
end

-- force: leave without asking (after the unsaved-changes popup, or on combat)
function EM.Exit(force)
    if not editing then return end
    if dirty and not force then
        if panel and not panel:IsShown() then panel:Show() end
        StaticPopup_Show("EBONHOLD_EDITMODE_UNSAVED")
        return
    end
    editing = false
    selected = nil
    HideOverlays()
    DUIHideMovers()
    UpdateGridShown()
    -- a window dragged when combat closes it would keep the mouse once hidden: end the move first
    CloseDropDownMenus()
    if sysDialog then sysDialog:StopMovingOrSizing() sysDialog:Hide() end
    if panel then panel:StopMovingOrSizing() end
    if panel and panel:IsShown() then panel:Hide() end
end

function EM.Toggle()
    if editing then EM.Exit() else EM.Enter() end
end

SLASH_EBONHOLDEDITMODE1 = "/editmode"
SlashCmdList["EBONHOLDEDITMODE"] = function() EM.Toggle() end

-- -------------------------------------------------------- game menu button ----
-- Inserted above "Log Out", at the end of the settings group: it hangs 1px under the
-- button Log Out hung from, and Log Out keeps its gap under ours. The game menu can
-- re-anchor Log Out (and size itself) when it opens: chained again on every show.
-- true when f hangs from target, directly or through other buttons
local function HangsFrom(f, target)
    for _ = 1, 20 do
        if not f then return false end
        if f == target then return true end
        local _, rel = f:GetPoint(1)
        f = rel
    end
    return false
end

local function ChainGameMenuButton()
    local b, logout = GameMenuButtonEditMode, GameMenuButtonLogout
    local point, rel, relPoint, x, y = logout:GetPoint(1)
    -- Already chained. ElvUI slots its own button above Log Out the same way, under
    -- ours: Log Out then hangs from ElvUI's button, which hangs from ours, and
    -- re-anchoring ours on it would close the loop (SetPoint error).
    if HangsFrom(rel, b) then return end
    b:ClearAllPoints()
    b:SetPoint("TOP", rel, "BOTTOM", 0, -1)
    logout:ClearAllPoints()
    logout:SetPoint(point, b, relPoint, x, y)
    GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + b:GetHeight() + 1)
end

local function AddGameMenuButton()
    local logout = GameMenuButtonLogout
    if not logout or GameMenuButtonEditMode then return end
    local b = CreateFrame("Button", "GameMenuButtonEditMode", GameMenuFrame, "GameMenuButtonTemplate")
    b:SetText(L["Edit Mode"])
    ChainGameMenuButton()
    GameMenuFrame:HookScript("OnShow", ChainGameMenuButton)
    b:SetScript("OnClick", function()
        PlaySound("igMainMenuOption")
        HideUIPanel(GameMenuFrame)
        EM.Enter()
    end)
end

-- ------------------------------------------------------------------ events ----
for _, s in ipairs(SYSTEMS) do
    entries[#entries + 1] = s
    entryByKey[s.key] = s
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UNIT_EXITED_VEHICLE")
ev:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        DB()
        AddGameMenuButton()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not self.loaded then
            self.loaded = true
            ApplyDragonUICoverage()
            MergePartyIntoRaid()
            EM.ApplyLayout()
            LockAllDragging()
            retry.total, retry.t = 0, 0
            retry:Show()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if editing then
            Notify(L["closed for combat. Your unsaved changes are kept until you save or revert them."])
            EM.Exit(true)
        end
    elseif event == "UNIT_EXITED_VEHICLE" then
        -- the micro menu was left to the vehicle bar (or not measured yet): take it back
        if unit ~= "player" then return end
        for _, e in ipairs(entries) do
            local o = current[e.key]
            if e.skipInVehicle and o then ApplyEntry(e, o) end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if next(queued) then
            local keys = queued
            queued = {}
            for key in pairs(keys) do
                local e = entryByKey[key]
                if e then
                    local o = current[key]
                    if o then ApplyEntry(e, o) else RestoreEntry(e) end
                end
            end
        end
    end
end)
