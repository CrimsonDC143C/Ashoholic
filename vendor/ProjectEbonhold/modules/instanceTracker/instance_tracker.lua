-- ==============================================================================
-- Instance tracker (2026-10-05): inside a dungeon or a raid, which bosses are dead and alive,
-- and what clearing the place (every boss dead, in any order) gives this character.
--
-- Sits right under the run frame (ProjectEbonholdPlayerRunFrame) and is drawn like the
-- objectives tracker (modules/questTracker/quest_tracker.lua): gold header with a gradient
-- underline and a collapse chevron, module sub-headers, dashed lines, rewards in quest-item
-- style icon buttons. The objectives tracker moves under it while it is shown
-- (quest_tracker.lua AnchorTracker).
--
-- Everything is computed by the server (Ashendor::InstanceTracker), from the rules that pay:
--   SS.SEND_INSTANCE_TRACKER (1293):
--     "<name>|<raid 0/1>|<torment>|<cleared 0/1>|<soul shards>|<orbs>|<cache item>|<cache item level>|<bosses>"
--     bosses = "<name>~<dead 0/1>~<looted this week 0/1>" joined by ';'. Empty body = hide.
--     soul shards = -1: a raid whose clear this character was already paid this week ("earned this week").
--   CS.REQUEST_INSTANCE_TRACKER (1293) "" -> resend (after a /reload, on a group change).
-- A reward the character will not get is not listed at all.
-- ==============================================================================
ProjectEbonhold = ProjectEbonhold or {}
local IT = {}
ProjectEbonhold.InstanceTracker = IT

-- same tunables as the objectives tracker, so the two read as one column
local WIDTH       = 235
local FONT        = "Fonts\\FRIZQT__.TTF"
local LINE_H      = 15
local REWARD_H    = 26
local ICON_SIZE   = 22

local C_HEADER    = { 1.00, 0.82, 0.00 }
local C_MODULE    = { 0.75, 0.61, 0.00 }
local C_LINE      = { 0.86, 0.86, 0.86 }
local C_LINE_DONE = { 0.50, 0.50, 0.50 }
local C_COMPLETE  = { 0.40, 0.85, 0.40 }
local C_TORMENT   = { 1.00, 0.32, 0.24 }
local C_LOOTED    = { 1.00, 0.60, 0.24 }
local C_SHARDS    = { 0.78, 0.48, 1.00 }
local C_ORBS      = { 0.40, 0.70, 1.00 }

local ICON_SHARDS = "Interface\\Icons\\inv_10_jewelcrafting3_soulcage_frost" -- the run frame's Soul Shard icon
local ICON_ORBS   = "Interface\\Icons\\inv_112_arcane_orb"                   -- the Echo Journal's orb
local ICON_NONE   = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame, header, title, torment, collapse, scanTip
local moduleHeaders, bossLines, rewardRows = {}, {}, {}
local state

local function DB()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.instanceTracker = ProjectEbonholdDB.instanceTracker or {}
    return ProjectEbonholdDB.instanceTracker
end

local function Thousands(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- written like the run frame's own "Torment 30"
local function TormentText(t)
    if not t or t <= 0 then return "" end
    return "Torment " .. t
end

local function Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    return fs
end

-- the objectives tracker moves under this frame while it is shown
local function NotifyQuestTracker()
    local QT = ProjectEbonhold.QuestTracker
    if QT and QT.MarkDirty then QT.MarkDirty() end
end

-- an item the client has never seen has no name yet: a hidden tooltip asks the server for it
local function QueryItem(item)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ProjectEbonholdInstanceTrackerScan", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetHyperlink("item:" .. item)
    scanTip:Hide()
end

-- ------------------------------------------------------------------ frame
local function UpdateChevron()
    if DB().collapsed then
        collapse.tex:SetTexCoord(0, 0.5, 0.5, 1)     -- "+" (expand)
    else
        collapse.tex:SetTexCoord(0, 0.5, 0, 0.5)     -- "-" (collapse)
    end
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "ProjectEbonholdInstanceTracker", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetHeight(22)
    local run = _G["ProjectEbonholdPlayerRunFrame"]
    if run then
        frame:SetPoint("TOPRIGHT", run, "BOTTOMRIGHT", 0, -6)
    else
        frame:SetPoint("TOPRIGHT", WatchFrame or UIParent, "TOPRIGHT", 0, 0)
    end

    -- header: instance name + gradient underline + Torment + collapse chevron
    header = CreateFrame("Frame", nil, frame)
    header:SetHeight(22)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    collapse = CreateFrame("Button", nil, header)
    collapse:SetWidth(16)
    collapse:SetHeight(16)
    collapse:SetPoint("RIGHT", header, "RIGHT", -2, -1)
    collapse.tex = collapse:CreateTexture(nil, "ARTWORK")
    collapse.tex:SetTexture("Interface\\Buttons\\UI-Panel-QuestHideButton")
    collapse.tex:SetAllPoints(collapse)
    collapse:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    collapse:SetScript("OnClick", function()
        DB().collapsed = not DB().collapsed
        IT.Refresh()
    end)

    torment = Text(header, 11, C_TORMENT)
    torment:SetPoint("RIGHT", collapse, "LEFT", -4, 0)
    torment:SetJustifyH("RIGHT")

    title = Text(header, 16, C_HEADER)
    title:SetPoint("LEFT", header, "LEFT", 2, 0)
    title:SetPoint("RIGHT", torment, "LEFT", -6, 0)
    title:SetHeight(20)

    local underline = header:CreateTexture(nil, "ARTWORK")
    underline:SetTexture("Interface\\Buttons\\WHITE8X8")
    underline:SetHeight(1)
    underline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -20, 0)
    underline:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.55, 1, 0.82, 0, 0)
end

-- "Bosses" / "Rewards" bands, as the objectives tracker's "Quests" / "Achievements"
local function ModuleHeader(i)
    local mh = moduleHeaders[i]
    if mh then return mh end
    mh = CreateFrame("Frame", nil, frame)
    mh:SetHeight(16)
    mh:SetWidth(WIDTH)
    mh.bg = mh:CreateTexture(nil, "BACKGROUND")
    mh.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    mh.bg:SetAllPoints(mh)
    mh.bg:SetGradientAlpha("HORIZONTAL", 0.30, 0.24, 0, 0.45, 0.30, 0.24, 0, 0)
    mh.text = Text(mh, 13, C_MODULE)
    mh.text:SetPoint("LEFT", mh, "LEFT", 4, 0)
    mh.right = Text(mh, 12, C_LINE_DONE)
    mh.right:SetPoint("RIGHT", mh, "RIGHT", -4, 0)
    mh.right:SetJustifyH("RIGHT")
    moduleHeaders[i] = mh
    return mh
end

local function BossLine(i)
    local line = bossLines[i]
    if line then return line end
    line = CreateFrame("Frame", nil, frame)
    line:SetHeight(LINE_H)
    line:SetWidth(WIDTH - 10)
    line.lock = Text(line, 11, C_LOOTED)
    line.lock:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.lock:SetJustifyH("RIGHT")
    line.lock:SetText("looted")
    line.name = Text(line, 12)
    line.name:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.name:SetPoint("RIGHT", line.lock, "LEFT", -4, 0)
    line.name:SetHeight(LINE_H) -- one line: a long name ends in "..."
    bossLines[i] = line
    return line
end

-- a reward: its item icon in a quest-item style button, its name, the amount on the right
local function RewardRow(i)
    local row = rewardRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, frame)
    row:SetHeight(REWARD_H)
    row:SetWidth(WIDTH - 10)
    row:EnableMouse(true)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(ICON_SIZE)
    row.icon:SetHeight(ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.border = row:CreateTexture(nil, "OVERLAY")
    row.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    row.border:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -10, 10)
    row.border:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 10, -10)

    row.value = Text(row, 12)
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.value:SetJustifyH("RIGHT")
    row.label = Text(row, 12, C_LINE)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.label:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    row.label:SetHeight(LINE_H)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if self.item then
            GameTooltip:SetHyperlink("item:" .. self.item)
        else
            GameTooltip:AddLine(self.label:GetText() or "", 1, 0.82, 0)
            if self.hint then GameTooltip:AddLine(self.hint, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rewardRows[i] = row
    return row
end

-- ------------------------------------------------------------------ layout
local function HideFrom(list, first)
    for i = first, #list do list[i]:Hide() end
end

local itemRetry, itemTries = 0, 0
local events -- created below; drives the item-cache redraw

function IT.Refresh()
    if not state then
        if frame and frame:IsShown() then
            frame:Hide()
            NotifyQuestTracker()
        end
        return
    end
    Build()
    UpdateChevron()

    title:SetText(state.name)
    torment:SetText(TormentText(state.torment))

    local wasShown = frame:IsShown()
    local oldHeight = frame:GetHeight()
    local y = -(header:GetHeight() + 4)

    if DB().collapsed then
        HideFrom(moduleHeaders, 1)
        HideFrom(bossLines, 1)
        HideFrom(rewardRows, 1)
        y = -header:GetHeight()
    else
        -- bosses
        local dead = 0
        for _, boss in ipairs(state.bosses) do
            if boss.dead then dead = dead + 1 end
        end
        local mh = ModuleHeader(1)
        mh.text:SetText("Bosses")
        mh.right:SetText(dead .. " / " .. #state.bosses)
        mh:ClearAllPoints()
        mh:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
        mh:Show()
        y = y - mh:GetHeight() - 4

        for i, boss in ipairs(state.bosses) do
            local line = BossLine(i)
            line.name:SetText("- " .. boss.name)
            line.name:SetTextColor(unpack(boss.dead and C_LINE_DONE or C_LINE))
            if boss.locked then line.lock:Show() else line.lock:Hide() end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
            line:Show()
            y = y - LINE_H
        end
        HideFrom(bossLines, #state.bosses + 1)

        -- what the clear gives; once everything is dead, one green line instead
        local rewards = {}
        if state.cleared then
            local line = BossLine(#state.bosses + 1)
            line.name:SetText("All bosses defeated")
            line.name:SetTextColor(unpack(C_COMPLETE))
            line.lock:Hide()
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y - 2)
            line:Show()
            y = y - 2 - LINE_H
        else
            if state.shards > 0 then
                table.insert(rewards, { icon = ICON_SHARDS, label = "Soul Shards", value = Thousands(state.shards),
                    color = C_SHARDS, hint = "Added to your run when every boss is dead." })
            elseif state.shards < 0 then
                -- -1: this raid's clear was already paid to this character this week (server clear lock)
                table.insert(rewards, { icon = ICON_SHARDS, label = "Soul Shards", value = "earned this week",
                    color = C_LOOTED, hint = "You already cleared this raid this week. Its Soul Shards come back after the weekly reset (Tuesday 03:00 UTC)." })
            end
            if state.orbs > 0 then
                table.insert(rewards, { icon = ICON_ORBS, label = "Orbs of Lost Memories", value = Thousands(state.orbs),
                    color = C_ORBS, hint = "Reroll an echo in the Echo Journal." })
            end
            if state.cacheItem > 0 then
                local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(state.cacheItem)
                local r, g, b = 1, 0.6, 0.24
                if quality and GetItemQualityColor then r, g, b = GetItemQualityColor(quality) end
                if not name and itemTries < 5 then
                    QueryItem(state.cacheItem)
                    if itemRetry <= 0 then
                        itemTries = itemTries + 1
                        itemRetry = 1.5
                        events:Show()
                    end
                end
                table.insert(rewards, { icon = texture or GetItemIcon(state.cacheItem) or ICON_NONE,
                    label = name or "Reward cache", value = "ilvl " .. state.cacheItemLevel,
                    color = { r, g, b }, labelColor = { r, g, b }, item = state.cacheItem })
            end
        end

        if #rewards > 0 then
            y = y - 6
            local rh = ModuleHeader(2)
            rh.text:SetText("Rewards")
            rh.right:SetText("")
            rh:ClearAllPoints()
            rh:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
            rh:Show()
            y = y - rh:GetHeight() - 4
            for i, reward in ipairs(rewards) do
                local row = RewardRow(i)
                row.icon:SetTexture(reward.icon)
                row.label:SetText(reward.label)
                row.label:SetTextColor(unpack(reward.labelColor or C_LINE))
                row.value:SetText(reward.value)
                row.value:SetTextColor(unpack(reward.color))
                row.item, row.hint = reward.item, reward.hint
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
                row:Show()
                y = y - REWARD_H - 2
            end
        else
            HideFrom(moduleHeaders, 2)
        end
        HideFrom(rewardRows, #rewards + 1)
    end

    frame:SetHeight(-y + 4)
    frame:Show()
    if not wasShown or math.abs(oldHeight - frame:GetHeight()) > 0.5 then
        NotifyQuestTracker()
    end
end

-- ------------------------------------------------------------------ wire
local function Parse(body)
    if not body or body == "" then return nil end
    local name, raid, tor, cleared, shards, orbs, cacheItem, cacheItemLevel, list = strsplit("|", body)
    local s = {
        name = name or "", raid = raid == "1", torment = tonumber(tor) or 0, cleared = cleared == "1",
        shards = tonumber(shards) or 0, orbs = tonumber(orbs) or 0,
        cacheItem = tonumber(cacheItem) or 0, cacheItemLevel = tonumber(cacheItemLevel) or 0,
        bosses = {},
    }
    if list and list ~= "" then
        for _, item in ipairs({ strsplit(";", list) }) do
            local bossName, dead, locked = strsplit("~", item)
            if bossName and bossName ~= "" then
                table.insert(s.bosses, { name = bossName, dead = dead == "1", locked = locked == "1" })
            end
        end
    end
    if #s.bosses == 0 then return nil end
    return s
end

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_INSTANCE_TRACKER, function(body)
    state = Parse(body)
    itemTries = 0
    IT.Refresh()
end)

IT.GetFrame = function() return frame end

-- ask again after a /reload or a group change (the Dungeon Finder rewards depend on the group);
-- roster events come in bursts, so one request half a second after the last one. Also redraws
-- once the cache item's name has come back from the server.
local pending = 0
events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
events:RegisterEvent("RAID_ROSTER_UPDATE")
events:SetScript("OnEvent", function(self)
    pending = 0.5
    self:Show()
end)
events:SetScript("OnUpdate", function(self, elapsed)
    if itemRetry > 0 then
        itemRetry = itemRetry - elapsed
        if itemRetry <= 0 then IT.Refresh() end
    end
    if pending > 0 then
        pending = pending - elapsed
        if pending <= 0 then
            if IsInInstance() then
                ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_INSTANCE_TRACKER, "")
            elseif state then
                state = nil
                IT.Refresh()
            end
        end
    end
    if pending <= 0 and itemRetry <= 0 then self:Hide() end
end)
events:Hide()
