-- ==============================================================================
-- Raid Finder (server: Ashendor/RaidFinder, raid_finder_scripts.cpp).
--
-- A "Raids" tab under the Dungeon Finder window. The player picks the roles they can play,
-- a raid and a Torment, and is grouped with players who picked the same raid and Torment:
--   * 5 players to start: exactly 1 tank, 1 healer, and damage on every other seat (owner,
--     2026-11-02). Up to 10: once the 5 are found, each newcomer resets a 60 s wait, the extra
--     seats are damage only;
--   * an invitation popup (45 s); when everyone accepts, a new raid group is made and everyone
--     is teleported to the raid's entrance, in a fresh instance at the Torment queued for;
--   * a party is queued by its leader, every member with the roles they picked here;
--   * someone leaves a raid the finder formed: the tab shows the raid's seats, and its leader or an
--     assistant can search for replacements (players queued for the same raid and Torment join it in place).
-- The Dungeons tab is the stock frame, untouched (modules/dungeonFinder).
--
-- Wire (requests and answers never share a number: the self-whisper echoes requests back):
--   CS.REQUEST_RAID_FINDER_DATA   (1254) ""             -> SS.SEND_RAID_FINDER_DATA (1258) + STATE (1259)
--   CS.REQUEST_RAID_FINDER_ROLES  (1255) "<mask>"       -> SS.SEND_RAID_FINDER_DATA
--   CS.REQUEST_RAID_FINDER_JOIN   (1256) "<map>|<tier>" -> SS.SEND_RAID_FINDER_RESULT (1265) "OK" / "FAIL,<reason>"
--   CS.REQUEST_RAID_FINDER_LEAVE  (1257) ""
--   CS.REQUEST_RAID_FINDER_ANSWER (1266) "1" / "0"
--   CS.REQUEST_RAID_FINDER_SEARCH (1267) "1" / "0"    -- leader of a Raid Finder raid: search for replacements
--   DATA:  "<release>|<maxQueueable>|<maxTier>|<roles>|<classRoles>|<map>,<lootable>,<bosses>;..."
-- The raid list is static (owner 2026-11-02): no open / closed state from the server. The item level each
-- raid asks for is shown and pre-checked here on the player's own average (same slots as
-- Player::GetAverageItemLevel); the server checks it again for every member, and the realm's phase.
--   STATE: "0" | "1|map|tier|tank|healer|damage|players|soakLeft|inRaid|queuedSecs"
--          | "2|map|tier|tanks|healers|damage|players|secondsLeft|accepted|total|answered|myRole|refill"
--          | "3|map|tier|tank|healer|damage|players|target|searching|leader|searchSecs"  (in a Raid Finder raid)
-- ==============================================================================
local RF = {}
ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.RaidFinder = RF

local CS = ProjectEbonhold.CS
local SS = ProjectEbonhold.SS

local ROLE_TANK, ROLE_HEALER, ROLE_DAMAGE = 2, 4, 8
local MIN_LEVEL = 80
local LADDER_TOP = ProjectEbonhold.TormentLadderTop or 11
local ICON_LOCK = "Interface\\AddOns\\ProjectEbonhold\\assets\\lock"
local ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"

-- The raids, in the order of the list, with their release (docs/ai/RAID-PROGRESSION.md). The
-- server says how many bosses can still be looted; names and releases are here.
local RAIDS = {
  { map = 409, name = "Molten Core",          exp = 1, release = 1 },
  { map = 469, name = "Blackwing Lair",       exp = 1, release = 2 },
  { map = 309, name = "Zul'Gurub",            exp = 1, release = 3 },
  { map = 509, name = "Ruins of Ahn'Qiraj",   exp = 1, release = 4 },
  { map = 531, name = "Temple of Ahn'Qiraj",  exp = 1, release = 4 },
  { map = 532, name = "Karazhan",             exp = 2, release = 1 },
  { map = 565, name = "Gruul's Lair",         exp = 2, release = 1 },
  { map = 544, name = "Magtheridon's Lair",   exp = 2, release = 1 },
  { map = 548, name = "Serpentshrine Cavern", exp = 2, release = 2 },
  { map = 550, name = "Tempest Keep",         exp = 2, release = 2 },
  { map = 568, name = "Zul'Aman",             exp = 2, release = 3 },
  { map = 534, name = "Mount Hyjal",          exp = 2, release = 4 },
  { map = 564, name = "Black Temple",         exp = 2, release = 4 },
  { map = 580, name = "Sunwell Plateau",      exp = 2, release = 5 },
  { map = 533, name = "Naxxramas",            exp = 3, release = 1 },
  { map = 616, name = "The Eye of Eternity",  exp = 3, release = 1 },
  { map = 615, name = "The Obsidian Sanctum", exp = 3, release = 1 },
  { map = 603, name = "Ulduar",               exp = 3, release = 2 },
  { map = 249, name = "Onyxia's Lair",        exp = 3, release = 3 },
  { map = 631, name = "Icecrown Citadel",     exp = 3, release = 4 },
  { map = 724, name = "The Ruby Sanctum",     exp = 3, release = 5 },
}
local LAST_RELEASE = 5
local RAID_BY_MAP = {}
for _, r in ipairs(RAIDS) do RAID_BY_MAP[r.map] = r end

-- Item level asked to pick a raid: 200 for release 1 (the floor for any raid), then the loot item
-- level of the release before it (owner, 2026-11-02). The Torment does not change it.
local function RequiredItemLevel(raid)
  if raid.release <= 1 then return 200 end
  return 200 + 13 * (raid.release - 1)
end

-- The player's average item level, the server's way (Player::GetAverageItemLevel): 15 slots, every
-- slot but the shirt (4), the off hand (17), the ranged slot (18) and the tabard (19); empty = 0.
local AVERAGE_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
local function PlayerItemLevel()
  local sum = 0
  for _, slot in ipairs(AVERAGE_SLOTS) do
    local link = GetInventoryItemLink("player", slot)
    if link then
      local _, _, _, ilvl = GetItemInfo(link)
      sum = sum + (ilvl or 0)
    end
  end
  return sum / #AVERAGE_SLOTS
end

local function MeetsItemLevel(raid)
  return PlayerItemLevel() >= RequiredItemLevel(raid)
end

local state = {
  known = false,
  release = 5,
  maxQueueable = 1,
  maxTier = 11,
  roles = ROLE_DAMAGE,
  classRoles = ROLE_DAMAGE,
  raids = {},             -- [map] = { lootable, total }, from the server
  selected = {},          -- [map] = true: the raids picked (several at once)
  tier = 1,               -- tier shown on the ladder (may be locked: looked at only)
  queue = { status = 0 }, -- last SEND_RAID_FINDER_STATE, receivedAt = GetTime()
}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function Send(id, body)
  if ProjectEbonhold.sendToServer then ProjectEbonhold.sendToServer(id, body or "") end
end

local function TierName(tier)
  local DF = ProjectEbonhold.DungeonFinder
  if DF and DF.TierName then return DF.TierName(tier) end
  return tier <= 1 and "Normal" or ("Torment " .. (tier - 1))
end

local function MaxTier()
  local data = ProjectEbonhold.TormentTierData
  return math.min(state.maxTier, LADDER_TOP, data and #data or LADDER_TOP)
end

local function IsLocked(tier) return tier > state.maxQueueable end

local function TierColor(tier)
  if tier <= 1 then return 1, 1, 1 end
  local p = (tier - 1) / math.max(1, MaxTier() - 1)
  return 1.0, 1.0 - p * 0.8, 1.0 - p * 0.8
end

local function LockReason(tier)
  local svc = ProjectEbonhold.HardmodeService
  if svc and svc.GetAchievementName then
    local link = (svc.GetAchievementLink and svc.GetAchievementLink(tier)) or ""
    if link ~= "" then return "Requires " .. link end
    local name = svc.GetAchievementName(tier)
    if name and name ~= "" then return "Requires the achievement |cffFFD100" .. name .. "|r" end
  end
  return "Locked"
end

-- Roles each class can take, same table as RaidFinder::RolesOfClass: drawn without waiting for the
-- server, whose DATA has the last word when it comes.
local CLASS_ROLES = {
  WARRIOR = ROLE_TANK + ROLE_DAMAGE, DEATHKNIGHT = ROLE_TANK + ROLE_DAMAGE,
  PALADIN = ROLE_TANK + ROLE_HEALER + ROLE_DAMAGE, DRUID = ROLE_TANK + ROLE_HEALER + ROLE_DAMAGE,
  PRIEST = ROLE_HEALER + ROLE_DAMAGE, SHAMAN = ROLE_HEALER + ROLE_DAMAGE,
}
local function ClassRoles()
  local _, class = UnitClass("player")
  return CLASS_ROLES[class or ""] or ROLE_DAMAGE
end

local function IsBusy() local s = state.queue.status or 0 return s == 1 or s == 2 end
local function InFinderRaid() return state.queue.status == 3 end
local function IsSearching() return InFinderRaid() and state.queue.searching == 1 end
-- Queued, invited or searching for replacements: the roles, the raid and the Torment cannot change.
-- A formed raid that is not searching can pick its next raid and queue again, as any party.
local function IsFrozen() return IsBusy() or IsSearching() end

--- Seats a formed raid misses: tank 0/1, healer 0/1, damage count.
local function RaidMissing()
  local q = state.queue
  local tank = (q.tank or 0) == 0 and 1 or 0
  local healer = (q.healer or 0) == 0 and 1 or 0
  local damage = math.max(0, (q.target or 5) - (q.players or 0) - tank - healer)
  return tank, healer, damage
end

--- The button searches for replacements (rather than queueing a new raid): the raid is searching, or it
--- misses seats and its own raid and Torment are the ones picked.
local function ReplaceMode()
  if not InFinderRaid() then return false end
  if IsSearching() then return true end
  local tank, healer, dmg = RaidMissing()
  local only = true
  for map in pairs(state.selected) do if map ~= state.queue.map then only = false end end
  return tank + healer + dmg > 0 and only and state.selected[state.queue.map] and state.tier == state.queue.tier
end

local function InParty() return (GetNumPartyMembers() or 0) > 0 or (GetNumRaidMembers() or 0) > 0 end

local function SecondsLeft(field)
  local q = state.queue
  local v = tonumber(q[field]) or -1
  if v < 0 then return -1 end
  return math.max(0, v - math.floor(GetTime() - (q.receivedAt or GetTime())))
end

local function FormatTime(s)
  s = math.max(0, math.floor(s))
  if s >= 60 then return string.format("%d min %02d s", math.floor(s / 60), s % 60) end
  return s .. " s"
end

local function RoleCoords(role)
  if GetTexCoordsForRole then return GetTexCoordsForRole(role) end
  return 0, 1, 0, 1
end

local ROLE_INFO = {
  [ROLE_TANK]   = { key = "TANK",    name = "Tank",   r = 0.56, g = 0.78, b = 1.0 },
  [ROLE_HEALER] = { key = "HEALER",  name = "Healer", r = 0.62, g = 1.0,  b = 0.48 },
  [ROLE_DAMAGE] = { key = "DAMAGER", name = "DPS",    r = 1.0,  g = 0.6,  b = 0.54 },
}

------------------------------------------------------------
-- Panel
------------------------------------------------------------

local panel, tabs, popup, status

--- The raids picked, in the order of the list.
local function SelectedRaids()
  local list = {}
  for _, raid in ipairs(RAIDS) do
    if state.selected[raid.map] then list[#list + 1] = raid end
  end
  return list
end

local function SelectOnly(map)
  state.selected = {}
  if map then state.selected[map] = true end
end


--- The most advanced raid the player's gear allows, first of the list on a tie.
local function DefaultRaid()
  local best
  for _, raid in ipairs(RAIDS) do
    if MeetsItemLevel(raid) and (not best or raid.release > best.release) then best = raid end
  end
  return best and best.map or RAIDS[1].map
end

local RefreshPanel

local function JoinReason()
  local raids = SelectedRaids()
  if UnitLevel("player") < MIN_LEVEL then return "The Raid Finder opens at level 80." end
  if #raids == 0 then return "Pick at least one raid." end
  for _, raid in ipairs(raids) do
    if not MeetsItemLevel(raid) then
      return string.format("%s requires an average item level of %d (yours: %d).", raid.name, RequiredItemLevel(raid), math.floor(PlayerItemLevel()))
    end
  end
  if IsLocked(state.tier) then return "This difficulty is locked." end
  if InParty() and not IsPartyLeader() and not IsRaidLeader() then return "Only your group leader can queue the group." end
  if bit.band(state.roles, state.classRoles) == 0 then return "Pick at least one role." end
  return nil
end

local function OnFindClicked()
  if ReplaceMode() then
    Send(CS.REQUEST_RAID_FINDER_SEARCH, IsSearching() and "0" or "1")
    return
  end
  if IsBusy() then
    Send(CS.REQUEST_RAID_FINDER_LEAVE, "")
    return
  end
  local reason = JoinReason()
  if reason then
    UIErrorsFrame:AddMessage(reason, 1.0, 0.1, 0.1, 1.0)
    return
  end
  local maps = {}
  for _, raid in ipairs(SelectedRaids()) do maps[#maps + 1] = raid.map end
  Send(CS.REQUEST_RAID_FINDER_JOIN, table.concat(maps, ",") .. "|" .. state.tier)
end

local function ToggleRole(role)
  if IsFrozen() then
    UIErrorsFrame:AddMessage("Leave the queue before changing your roles.", 1.0, 0.1, 0.1, 1.0)
    return
  end
  if bit.band(state.classRoles, role) == 0 then return end
  local roles = bit.bxor(state.roles, role)
  state.roles = roles   -- drawn at once; the server's answer (DATA) has the last word
  Send(CS.REQUEST_RAID_FINDER_ROLES, tostring(roles))
  RefreshPanel()
end

local function CreateRoleButton(parent, role)
  local info = ROLE_INFO[role]
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(58, 58)
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetAllPoints()
  btn.icon:SetTexture(ROLE_TEX)
  btn.icon:SetTexCoord(RoleCoords(info.key))
  btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  btn.check = CreateFrame("CheckButton", nil, btn, "UICheckButtonTemplate")
  btn.check:SetSize(24, 24)
  btn.check:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -6, -6)
  btn.check:SetScript("OnClick", function(self)
    self:SetChecked(bit.band(state.roles, role) ~= 0)
    ToggleRole(role)
  end)
  btn:SetScript("OnClick", function() ToggleRole(role) end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(info.name, info.r, info.g, info.b)
    if bit.band(state.classRoles, role) == 0 then
      GameTooltip:AddLine("Your class cannot take this role.", 1, 0.3, 0.3, true)
    else
      GameTooltip:AddLine("Tick every role you can play: you get the seat the raid is missing.", 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", GameTooltip_Hide)
  btn.role = role
  return btn
end

local SEATS = { ROLE_TANK, ROLE_HEALER, ROLE_DAMAGE, ROLE_DAMAGE, ROLE_DAMAGE }

local function CreateSeat(parent, role, index)
  local info = ROLE_INFO[role]
  local seat = CreateFrame("Frame", nil, parent)
  seat:SetSize(58, 62)
  seat.ring = seat:CreateTexture(nil, "BACKGROUND")
  seat.ring:SetSize(40, 40)
  seat.ring:SetPoint("TOP", seat, "TOP", 0, 0)
  seat.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  seat.ring:SetTexCoord(0, 0.6, 0, 0.6)
  seat.icon = seat:CreateTexture(nil, "ARTWORK")
  seat.icon:SetSize(30, 30)
  seat.icon:SetPoint("TOP", seat, "TOP", 0, -4)
  seat.icon:SetTexture(ROLE_TEX)
  seat.icon:SetTexCoord(RoleCoords(info.key))
  seat.label = seat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  seat.label:SetPoint("TOP", seat.icon, "BOTTOM", 0, -4)
  seat.label:SetText(info.name)
  seat.state = seat:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  seat.state:SetPoint("TOP", seat.label, "BOTTOM", 0, -1)
  -- A seat still searched for shows the stock Dungeon Finder eye, turning, in its corner.
  seat.eye = seat:CreateTexture(nil, "OVERLAY")
  seat.eye:SetSize(22, 22)
  seat.eye:SetPoint("CENTER", seat.ring, "BOTTOMRIGHT", -6, 6)
  seat.eye:SetTexture("Interface\\LFGFrame\\LFG-Eye")
  seat.eye:SetTexCoord(0, 1 / 8, 0, 1 / 4)
  seat.eye:Hide()
  seat.frame = (index or 1) * 5   -- the seats do not all blink at the same moment
  seat:SetScript("OnUpdate", function(self, elapsed)
    if not self.searching then return end
    self.clock = (self.clock or 0) + elapsed
    if self.clock < 0.1 then return end
    self.clock = 0
    self.frame = (self.frame + 1) % 29   -- LFG-Eye: 29 frames of 64 px, 8 per row, 512 x 256
    local col, row = self.frame % 8, math.floor(self.frame / 8)
    self.eye:SetTexCoord(col / 8, (col + 1) / 8, row / 4, (row + 1) / 4)
  end)
  function seat:SetFound(found, searching)
    self.icon:SetDesaturated(not found)
    self.icon:SetAlpha(found and 1 or 0.45)
    self.searching = searching and not found
    if self.searching then self.eye:Show() else self.eye:Hide() end
    if found then
      self.state:SetText("found")
      self.state:SetTextColor(0.1, 1, 0.1)
    elseif searching then
      self.state:SetText("")   -- the eye says it
    else
      self.state:SetText("open")
      self.state:SetTextColor(0.6, 0.6, 0.6)
    end
  end
  return seat
end

local function RaidDropdown_Initialize(self, level)
  -- One section per patch (release), its item level on the header; the raids of the three expansions inside.
  for release = 1, LAST_RELEASE do
    local req = RequiredItemLevel({ release = release })
    local info = UIDropDownMenu_CreateInfo()
    info.text = "Patch " .. release .. (PlayerItemLevel() >= req and " |cff808080" or " |cffff4040") .. "(item level " .. req .. ")|r"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
    for _, raid in ipairs(RAIDS) do
      if raid.release == release then
        info = UIDropDownMenu_CreateInfo()
        info.text = raid.name
        info.value = raid.map
        info.checked = state.selected[raid.map] and true or false
        info.disabled = not MeetsItemLevel(raid)
        info.keepShownOnClick = true   -- several raids can be ticked: the list stays open
        info.func = function(btn)
          state.selected[btn.value] = not state.selected[btn.value] or nil
          RefreshPanel()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end
  end
end

local function CreatePanel()
  if panel or not LFDParentFrame or not LFDQueueFrame then return end
  local W = ProjectEbonhold.TormentWidgets
  local TS = ProjectEbonhold.TierSelector

  panel = CreateFrame("Frame", "ProjectEbonholdRaidFinderPanel", LFDParentFrame)
  panel:SetAllPoints(LFDQueueFrame)
  panel:Hide()

  -- The window's art belongs to LFDQueueFrame (LFDFrame.xml: the frame layout, the quest-paper
  -- background, the title), which this tab hides: the panel carries the same pieces.
  local function CopyArt(name, layer, w, h, point, x, y)
    local src = _G[name]
    local tex = panel:CreateTexture(nil, layer)
    tex:SetTexture(src and src:GetTexture() or nil)
    tex:SetSize(w, h)
    tex:SetPoint(point, panel, point, x, y)
    return tex
  end
  CopyArt("LFDQueueFrameLayout", "BACKGROUND", 512, 512, "TOPLEFT", 0, 0)
  CopyArt("LFDQueueFrameBackground", "BORDER", 512, 256, "LEFT", 21, -64)
  panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  panel.title:SetPoint("TOP", panel, "TOP", 12, -17)
  panel.title:SetText("Raid Finder")

  local X, WIDTH = 32, 300

  -- Roles, one big button each, as the stock role row.
  panel.roles = {}
  local roleOrder = { ROLE_TANK, ROLE_HEALER, ROLE_DAMAGE }
  for i, role in ipairs(roleOrder) do
    local btn = CreateRoleButton(panel, role)
    btn:SetPoint("TOPLEFT", panel, "TOPLEFT", X + 42 + (i - 1) * 96, -54)
    panel.roles[role] = btn
  end

  -- Raid picker
  panel.raidLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.raidLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", X, -132)
  panel.raidLabel:SetText("Raid:")
  panel.dropdown = CreateFrame("Frame", "ProjectEbonholdRaidFinderDropDown", panel, "UIDropDownMenuTemplate")
  panel.dropdown:SetPoint("LEFT", panel.raidLabel, "RIGHT", -8, -2)
  UIDropDownMenu_SetWidth(panel.dropdown, 200)
  UIDropDownMenu_Initialize(panel.dropdown, RaidDropdown_Initialize)

  -- Torment: the same stepper and ladder as the Dungeons tab.
  panel.selector = TS.Create(panel, {
    width      = WIDTH,
    rungs      = LADDER_TOP,
    cosmetic   = false,
    GetMax     = MaxTier,
    GetName    = function(tier)
      local name = TierName(tier)
      if IsLocked(tier) then name = name .. " |T" .. ICON_LOCK .. ":16:16:0:-1|t" end
      return name
    end,
    GetColor   = TierColor,
    IsLocked   = IsLocked,
    GetCurrent = function() return state.tier end,
    CanStep    = function() return state.known and not IsFrozen() end,
    ShiftMax   = function() return state.maxQueueable end,
    OnSelect   = function(tier)
      state.tier = math.max(1, math.min(MaxTier(), tier))
      RefreshPanel()
    end,
    OnRungEnter = function(btn, tier)
      GameTooltip:SetOwner(btn, "ANCHOR_TOP")
      GameTooltip:SetText(TierName(tier), TierColor(tier))
      if IsLocked(tier) then GameTooltip:AddLine(LockReason(tier), 1, 0.3, 0.3, true) end
      GameTooltip:Show()
    end,
  })
  panel.selector:SetPoint("TOPLEFT", panel, "TOPLEFT", X, -166)

  -- The group: five seats, then the extra damage seats as a count.
  local header = W.CreateSectionHeader(panel, WIDTH, "The group", "5 to start, up to 10")
  header:SetPoint("TOPLEFT", panel, "TOPLEFT", X, -258)
  panel.seats = {}
  for i, role in ipairs(SEATS) do
    local seat = CreateSeat(panel, role, i)
    seat:SetPoint("TOPLEFT", header, "BOTTOMLEFT", (i - 1) * 60, -2)
    panel.seats[i] = seat
  end
  panel.groupLine = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.groupLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -68)
  panel.groupLine:SetWidth(WIDTH)
  panel.groupLine:SetJustifyH("CENTER")
  -- Why Find Raid is greyed out, centred under the seats (shown only while not queued).
  panel.reason = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.reason:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -78)
  panel.reason:SetWidth(WIDTH)
  panel.reason:SetJustifyH("CENTER")
  panel.reason:SetTextColor(1, 0.25, 0.25)

  -- Find Raid / Leave Queue and Close, where the Dungeons tab has its two buttons.
  panel.find = W.CreateBlizzardButton(panel, "ProjectEbonholdRaidFinderFind", 135, 22, "Find Raid")
  if LFDQueueFrameFindGroupButton then
    panel.find:SetAllPoints(LFDQueueFrameFindGroupButton)   -- same size and place as the stock buttons
  else
    panel.find:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 85)
  end
  panel.find:SetScript("OnClick", OnFindClicked)
  panel.find:SetScript("OnEnter", function(self)
    local reason
    if ReplaceMode() then
      if state.queue.leader ~= 1 then reason = "Only your raid leader or an assistant can search for replacements." end
    elseif not IsBusy() then
      reason = JoinReason()
    end
    if reason then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(reason, 1, 0.3, 0.3, true)
      GameTooltip:Show()
    end
  end)
  panel.find:SetScript("OnLeave", GameTooltip_Hide)
  panel.close = W.CreateBlizzardButton(panel, "ProjectEbonholdRaidFinderClose", 135, 22, CLOSE or "Close")
  if LFDQueueFrameCancelButton then
    panel.close:SetAllPoints(LFDQueueFrameCancelButton)
  else
    panel.close:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 85)
  end
  panel.close:SetScript("OnClick", function() HideUIPanel(LFDParentFrame) end)
end

local function RefreshSeats()
  local q = state.queue
  local hasTank, hasHealer, damage = 0, 0, 0
  if q.status == 1 then
    hasTank, hasHealer, damage = q.tank, q.healer, q.damage
  elseif q.status == 2 then
    hasTank, hasHealer, damage = math.min(1, q.tank), math.min(1, q.healer), q.damage
  elseif q.status == 3 then
    hasTank, hasHealer, damage = q.tank, q.healer, q.damage
  end
  local searching = q.status == 1 or IsSearching()
  panel.seats[1]:SetFound(hasTank > 0, searching)
  panel.seats[2]:SetFound(hasHealer > 0, searching)
  for i = 3, 5 do panel.seats[i]:SetFound(damage >= i - 2, searching) end

  if q.status == 1 then
    local missing = {}
    if hasTank == 0 then missing[#missing + 1] = "1 Tank" end
    if hasHealer == 0 then missing[#missing + 1] = "1 Healer" end
    local dmgNeeded = math.max(0, 5 - 2 - damage)
    if dmgNeeded > 0 then missing[#missing + 1] = dmgNeeded .. " DPS" end
    local line
    if SecondsLeft("soakLeft") >= 0 then
      line = string.format("|cff1eff00Raid found (%d players).|r Invitations in %s; more DPS can still join, up to 10.",
        q.players, FormatTime(SecondsLeft("soakLeft")))
    else
      line = "|cffffb000Missing: " .. table.concat(missing, ", ") .. ".|r"
    end
    if q.inRaid == 0 then line = line .. " The raid being built has no seat for your roles yet: you are next." end
    panel.groupLine:SetText(line .. "\nIn queue for " .. FormatTime((q.queuedSecs or 0) + (GetTime() - (q.receivedAt or GetTime()))) .. ".")
  elseif q.status == 2 then
    panel.groupLine:SetText(q.refill == 1 and "|cff1eff00A raid under way needs you.|r Answer the invitation."
      or "|cff1eff00Your raid is ready.|r Answer the invitation.")
  elseif q.status == 3 then
    local tank, healer, dmg = RaidMissing()
    local missing = {}
    if tank > 0 then missing[#missing + 1] = "1 Tank" end
    if healer > 0 then missing[#missing + 1] = "1 Healer" end
    if dmg > 0 then missing[#missing + 1] = dmg .. " DPS" end
    local line = string.format("Your Raid Finder raid: %d / %d players.", q.players or 0, q.target or 5)
    if #missing == 0 then
      line = line .. " |cff1eff00Every seat is filled.|r"
    elseif IsSearching() then
      line = line .. " |cffffb000Searching for " .. table.concat(missing, ", ") .. "|r for "
        .. FormatTime((q.searchSecs or 0) + (GetTime() - (q.receivedAt or GetTime()))) .. "."
    elseif q.leader == 1 then
      line = line .. " |cffffb000Missing: " .. table.concat(missing, ", ") .. ".|r Find Replacements to fill the seats."
    else
      line = line .. " |cffffb000Missing: " .. table.concat(missing, ", ") .. ".|r Your leader or an assistant can search for replacements."
    end
    panel.groupLine:SetText(line)
  else
    panel.groupLine:SetText("")
  end
  -- Not queued: why Find Raid is greyed out, without having to hover it.
  panel.reason:SetText((q.status or 0) == 0 and JoinReason() or "")
end

RefreshPanel = function()
  if not panel then return end
  local busy = IsFrozen()

  for role, btn in pairs(panel.roles) do
    local allowed = bit.band(state.classRoles, role) ~= 0
    local on = allowed and bit.band(state.roles, role) ~= 0
    btn.check:SetChecked(on)
    btn.icon:SetDesaturated(not allowed)
    btn.icon:SetAlpha(allowed and (on and 1 or 0.6) or 0.25)
    if allowed and not busy then btn.check:Enable() btn:Enable() else btn.check:Disable() btn:Disable() end
  end

  -- Queued: the panel shows the raids of the queue entry (all of them while waiting, the one invited to after).
  if busy and state.queue.maps then
    state.selected = {}
    for _, map in ipairs(state.queue.maps) do state.selected[map] = true end
  elseif busy and state.queue.map then
    SelectOnly(state.queue.map)
  end
  if busy and state.queue.tier then state.tier = state.queue.tier end
  if not next(state.selected) and not state.pickedOnce then
    SelectOnly(DefaultRaid())
    state.pickedOnce = true
  end
  local raids = SelectedRaids()
  UIDropDownMenu_SetText(panel.dropdown, #raids == 1 and raids[1].name or #raids > 1 and (#raids .. " raids") or "Pick raids")
  if busy then UIDropDownMenu_DisableDropDown(panel.dropdown) else UIDropDownMenu_EnableDropDown(panel.dropdown) end

  state.tier = math.max(1, math.min(MaxTier(), state.tier))
  panel.selector:SetValue(state.tier)
  panel.selector:Redraw()

  RefreshSeats()

  if ReplaceMode() then
    panel.find:SetText(IsSearching() and "Stop Searching" or "Find Replacements")
    if state.queue.leader == 1 then panel.find:Enable() else panel.find:Disable() end
  else
    panel.find:SetText(IsBusy() and "Leave Queue" or "Find Raid")
    if IsBusy() or not JoinReason() then panel.find:Enable() else panel.find:Disable() end
  end
end
RF.Refresh = function() RefreshPanel() end
-- The realm's release, nil until the server has answered.
RF.GetRelease = function() return state.known and state.release or nil end

------------------------------------------------------------
-- Tabs under the Dungeon Finder window
------------------------------------------------------------

local function ShowTab(index)
  if not tabs then return end
  PanelTemplates_SetTab(LFDParentFrame, index)
  if index == 2 then
    LFDQueueFrame:Hide()
    panel:Show()
    Send(CS.REQUEST_RAID_FINDER_DATA, "")
    RefreshPanel()
  else
    panel:Hide()
    LFDQueueFrame:Show()
  end
end

local function CreateTabs()
  if tabs or not LFDParentFrame then return end
  tabs = {}
  local names = { "Dungeons", "Raids" }
  for i, text in ipairs(names) do
    local tab = CreateFrame("Button", "LFDParentFrameTab" .. i, LFDParentFrame, "CharacterFrameTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(text)
    -- Same place as the stock Raid Browser's tabs (LFRFrame.xml), whose window has this size.
    if i == 1 then
      tab:SetPoint("BOTTOMLEFT", LFDParentFrame, "BOTTOMLEFT", 20, -25)
    else
      tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -15, 0)
    end
    tab:SetScript("OnClick", function(self)
      PlaySound("igCharacterInfoTab")
      ShowTab(self:GetID())
    end)
    PanelTemplates_TabResize(tab, 0)
    tabs[i] = tab
  end
  PanelTemplates_SetNumTabs(LFDParentFrame, #names)
  PanelTemplates_SetTab(LFDParentFrame, 1)
  -- The Dungeons tab comes back each time the window opens, unless a raid queue is running.
  LFDParentFrame:HookScript("OnShow", function() ShowTab((IsBusy() or IsSearching()) and 2 or 1) end)
  -- The stock frame may show its queue panel again on an LFG event: not over the Raids tab.
  LFDQueueFrame:HookScript("OnShow", function(self)
    if PanelTemplates_GetSelectedTab(LFDParentFrame) == 2 then self:Hide() end
  end)
end

------------------------------------------------------------
-- Status button (the stock eye only follows the Dungeon Finder) and invitation popup
------------------------------------------------------------

-- The eye's hover frame, drawn like the stock Dungeon Finder's "Assembling Group..." (LFDSearchStatus):
-- the title, the five seats as role circles (lit once found), the time in queue, then what happens now.
local searchStatus

local function CreateSearchStatus()
  local f = CreateFrame("Frame", "ProjectEbonholdRaidFinderSearchStatus", UIParent)
  f:SetSize(300, 150)
  f:SetFrameStrata("TOOLTIP")
  f:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  -- A plain fill: the tooltip texture is see-through and the world showed behind the text.
  f:SetBackdropColor(0.05, 0.05, 0.12, 0.96)
  f:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", f, "TOP", 0, -14)
  f.raid = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.raid:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
  f.raid:SetTextColor(0.7, 0.7, 0.7)
  f.slots = {}
  for i, role in ipairs(SEATS) do
    local slot = f:CreateTexture(nil, "ARTWORK")
    slot:SetSize(42, 42)
    slot:SetPoint("TOP", f, "TOP", (i - 3) * 48, -48)
    slot:SetTexture(ROLE_TEX)
    slot:SetTexCoord(RoleCoords(ROLE_INFO[role].key))
    f.slots[i] = slot
  end
  f.time = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.time:SetPoint("TOP", f, "TOP", 0, -98)
  f.line = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.line:SetPoint("TOP", f.time, "BOTTOM", 0, -10)
  f.line:SetWidth(280)
  f:Hide()
  return f
end

local function SetSlot(slot, found)
  slot:SetDesaturated(not found)
  if found then slot:SetVertexColor(1, 1, 1) else slot:SetVertexColor(0.35, 0.35, 0.35) end
end

local function StatusTooltip(owner)
  if not searchStatus then
    searchStatus = CreateSearchStatus()
    -- The times move every second while the frame is up; the server only sends a new state on a change.
    searchStatus:SetScript("OnUpdate", function(self, elapsed)
      self.tick = (self.tick or 0) + elapsed
      if self.tick < 1 then return end
      self.tick = 0
      StatusTooltip(status)
    end)
  end
  local f, q = searchStatus, state.queue
  local raid = RAID_BY_MAP[q.map]
  f:ClearAllPoints()
  f:SetPoint("TOPRIGHT", owner, "TOPLEFT", 0, 0)
  f.raid:SetText((raid and raid.name or "?") .. " · " .. TierName(q.tier or 1))

  local tank, healer, damage
  if q.status == 3 then
    local missTank, missHealer, missDamage = RaidMissing()
    tank, healer, damage = 1 - missTank, 1 - missHealer, 3 - math.min(3, missDamage)
  else
    tank, healer, damage = q.tank or 0, q.healer or 0, q.damage or 0
  end
  if q.status == 2 then tank, healer, damage = 1, 1, 3 end
  SetSlot(f.slots[1], tank > 0)
  SetSlot(f.slots[2], healer > 0)
  for i = 3, 5 do SetSlot(f.slots[i], damage >= i - 2) end

  local since = GetTime() - (q.receivedAt or GetTime())
  if q.status == 1 then
    f.title:SetText("Assembling Raid...")
    f.time:SetText("Time in Queue: " .. FormatTime((q.queuedSecs or 0) + since))
    local soak = SecondsLeft("soakLeft")
    if soak >= 0 then
      f.line:SetText(string.format("%d players found. Invitations in %s...", q.players or 0, FormatTime(soak)))
    else
      f.line:SetText("Looking for players...")
    end
  elseif q.status == 3 then
    f.title:SetText("Finding Replacements...")
    f.time:SetText("Time Searching: " .. FormatTime((q.searchSecs or 0) + since))
    f.line:SetText(string.format("Looking for players... (%d / %d)", q.players or 0, q.target or 5))
  else
    f.title:SetText(q.refill == 1 and "A Raid Needs You" or "Your Raid Is Ready")
    f.time:SetText("")
    f.line:SetText("Accept the invitation to join.")
  end
  f:Show()
end

local function StatusTooltipHide()
  if searchStatus then searchStatus:Hide() end
end

local function CreateStatus()
  if status then return end
  status = CreateFrame("Button", "ProjectEbonholdRaidFinderStatus", Minimap)
  status:SetSize(32, 32)
  status:SetFrameStrata("MEDIUM")
  status:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", -8, 24)
  status.icon = status:CreateTexture(nil, "ARTWORK")
  status.icon:SetAllPoints()
  status.icon:SetTexture("Interface\\LFGFrame\\LFG-Eye")
  status.icon:SetTexCoord(0, 0.125, 0, 0.25)
  status.border = status:CreateTexture(nil, "OVERLAY")
  status.border:SetSize(54, 54)
  status.border:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 0)
  status.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  status:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  status:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      if InFinderRaid() then
        if state.queue.leader == 1 then Send(CS.REQUEST_RAID_FINDER_SEARCH, "0") end
        return
      end
      Send(CS.REQUEST_RAID_FINDER_LEAVE, "")
    else
      ShowUIPanel(LFDParentFrame)
      ShowTab(2)
    end
  end)
  status:SetScript("OnEnter", StatusTooltip)
  status:SetScript("OnLeave", StatusTooltipHide)
  status:Hide()
end

local function CreatePopup()
  if popup then return end
  popup = CreateFrame("Frame", "ProjectEbonholdRaidFinderPopup", UIParent)
  popup:SetSize(300, 190)
  popup:SetPoint("TOP", UIParent, "TOP", 0, -135)
  popup:SetFrameStrata("DIALOG")
  popup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  popup.title:SetPoint("TOP", popup, "TOP", 0, -20)
  popup.title:SetText("Your raid is ready!")
  popup.raid = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  popup.raid:SetPoint("TOP", popup.title, "BOTTOM", 0, -6)
  popup.info = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  popup.info:SetPoint("TOP", popup.raid, "BOTTOM", 0, -8)
  popup.info:SetWidth(260)
  popup.role = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  popup.role:SetPoint("TOP", popup.info, "BOTTOM", 0, -8)
  popup.timer = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  popup.timer:SetPoint("TOP", popup.role, "BOTTOM", 0, -6)
  local W = ProjectEbonhold.TormentWidgets
  popup.accept = W.CreateBlizzardButton(popup, "ProjectEbonholdRaidFinderAccept", 115, 22, "Enter Raid")
  popup.accept:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -6, 18)
  popup.accept:SetScript("OnClick", function() Send(CS.REQUEST_RAID_FINDER_ANSWER, "1") end)
  popup.decline = W.CreateBlizzardButton(popup, "ProjectEbonholdRaidFinderDecline", 115, 22, "Leave Queue")
  popup.decline:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 6, 18)
  popup.decline:SetScript("OnClick", function() Send(CS.REQUEST_RAID_FINDER_ANSWER, "0") end)
  popup:SetScript("OnUpdate", function(self, elapsed)
    self.tick = (self.tick or 0) + elapsed
    if self.tick < 0.25 then return end
    self.tick = 0
    self.timer:SetText(FormatTime(SecondsLeft("secondsLeft")) .. " left")
  end)
  popup:Hide()
end

local function RefreshPopup()
  local q = state.queue
  if q.status ~= 2 then
    popup:Hide()
    return
  end
  local raid = RAID_BY_MAP[q.map]
  popup.title:SetText(q.refill == 1 and "A raid under way needs you!" or "Your raid is ready!")
  popup.raid:SetText(raid and raid.name or "?")
  popup.info:SetText(string.format("%s · %d players · %d / %d accepted", TierName(q.tier or 1), q.players or 0, q.accepted or 0, q.total or 0))
  local role = ROLE_INFO[q.myRole or 0]
  popup.role:SetText(role and ("Your seat: " .. role.name) or "")
  if role then popup.role:SetTextColor(role.r, role.g, role.b) end
  if q.answered == 1 then
    popup.accept:Disable()
    popup.accept:SetText("Waiting...")
  else
    popup.accept:Enable()
    popup.accept:SetText("Enter Raid")
  end
  if not popup:IsShown() then PlaySound("ReadyCheck") end
  popup:Show()
end

local function RefreshStatus()
  if IsBusy() or IsSearching() then status:Show() else status:Hide(); StatusTooltipHide() end
  if status:IsShown() and searchStatus and searchStatus:IsShown() then StatusTooltip(status) end
end

------------------------------------------------------------
-- Server messages
------------------------------------------------------------

-- Plain find loop: gmatch with "([^|]*)" yields extra empty fields on the client's Lua 5.1.
local function Split(s, sep)
  local out, pos = {}, 1
  s = s or ""
  while true do
    local i = string.find(s, sep, pos, true)
    if not i then
      out[#out + 1] = string.sub(s, pos)
      return out
    end
    out[#out + 1] = string.sub(s, pos, i - 1)
    pos = i + 1
  end
end

local function OnData(body)
  local f = Split(body, "|")
  state.known = true
  state.release = tonumber(f[1]) or state.release
  state.maxQueueable = tonumber(f[2]) or 1
  state.maxTier = tonumber(f[3]) or state.maxTier
  state.roles = tonumber(f[4]) or state.roles
  state.classRoles = tonumber(f[5]) or state.classRoles
  state.raids = {}
  for entry in string.gmatch(f[6] or "", "([^;]+)") do
    local map, lootable, total = string.match(entry, "^(%d+),(%d+),(%d+)$")
    if map then
      state.raids[tonumber(map)] = { lootable = tonumber(lootable), total = tonumber(total) }
    end
  end
  RefreshPanel()
  -- Raid Info lists the open raids: it waits for this answer to know the release.
  local lockout = ProjectEbonhold.RaidLockout
  if lockout and lockout.Refresh and RaidInfoFrame and RaidInfoFrame:IsShown() then lockout.Refresh() end
end

local function OnState(body)
  local f = Split(body, "|")
  local q = { status = tonumber(f[1]) or 0, receivedAt = GetTime() }
  if q.status == 1 then
    q.map, q.tier, q.tank, q.healer, q.damage, q.players = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
    q.soakLeft, q.inRaid, q.queuedSecs = tonumber(f[8]), tonumber(f[9]), tonumber(f[10])
    q.maps = {}
    for map in string.gmatch(f[11] or "", "(%d+)") do q.maps[#q.maps + 1] = tonumber(map) end
    if #q.maps == 0 then q.maps = nil end
  elseif q.status == 2 then
    q.map, q.tier, q.tank, q.healer, q.damage, q.players = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
    q.secondsLeft, q.accepted, q.total, q.answered, q.myRole = tonumber(f[8]), tonumber(f[9]), tonumber(f[10]), tonumber(f[11]), tonumber(f[12])
    q.refill = tonumber(f[13]) or 0
  elseif q.status == 3 then
    q.map, q.tier, q.tank, q.healer, q.damage, q.players = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
    q.target, q.searching, q.leader, q.searchSecs = tonumber(f[8]), tonumber(f[9]), tonumber(f[10]), tonumber(f[11])
    -- Just in a formed raid: the panel shows that raid and Torment, until the player picks another.
    if state.queue.status ~= 3 then SelectOnly(q.map) state.tier = q.tier or state.tier end
  end
  state.queue = q
  RefreshPanel()
  RefreshPopup()
  RefreshStatus()
end

local function OnResult(body)
  local ok, reason = string.match(body or "", "^(%u+),?(.*)$")
  if ok == "FAIL" and reason and reason ~= "" then
    UIErrorsFrame:AddMessage(reason, 1.0, 0.1, 0.1, 1.0)
  end
end

local function Install()
  if RF.installed or not LFDParentFrame then return end
  RF.installed = true
  CreatePanel()
  CreateTabs()
  CreateStatus()
  CreatePopup()
  -- The panel's countdowns move between two server ticks.
  panel:SetScript("OnUpdate", function(self, elapsed)
    self.tick = (self.tick or 0) + elapsed
    if self.tick < 1 then return end
    self.tick = 0
    if IsBusy() or IsSearching() then RefreshSeats() end
  end)
end

ProjectEbonhold.onEventReceived(SS.SEND_RAID_FINDER_DATA, OnData)
ProjectEbonhold.onEventReceived(SS.SEND_RAID_FINDER_STATE, OnState)
ProjectEbonhold.onEventReceived(SS.SEND_RAID_FINDER_RESULT, OnResult)

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" then
    if not state.known then state.classRoles = ClassRoles() end
    Install()
    Send(CS.REQUEST_RAID_FINDER_DATA, "")
  end
  RefreshPanel()
end)
