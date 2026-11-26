local L, T = ProjectEbonhold.L, ProjectEbonhold.T
-- callboard_renewal.lua -- the raid picker of the Elixir of Renewal (owner, 2026-11-23).
--
-- The elixir is the last step of the Call Board's weekly reward rail. Right-click on it: the
-- server sends the raids the character looted this week (SEND_RAID_RENEWAL "LIST|..."); this
-- window lists them, the player picks one and presses Renew (REQUEST_RAID_RENEWAL "<mapId>").
-- The server spends the elixir only when the raid is renewed and answers "OK|<mapId>|<name>",
-- or "FAIL|<reason>" and the elixir is kept. Raid names come from the server, in the client's
-- language when its Map.dbc has it.

local FRAME_NAME = "EbonholdRaidRenewalFrame"
local MAX_ROWS   = 12
local ROW_H      = 26
local FRAME_W    = 300

local frame, selected

local FAIL_TEXT = {
    combat  = L["You cannot drink the Elixir of Renewal in combat."],
    inside  = L["Leave that raid before renewing it."],
    nothing = L["You have no raid boss looted this week: there is nothing to renew."],
    noitem  = L["You need an Elixir of Renewal."],
}

local function SelectRow(row)
    selected = row and row.mapId or nil
    for _, r in ipairs(frame.rows) do
        if r == row then r:LockHighlight() else r:UnlockHighlight() end
    end
    if selected then frame.renew:Enable() else frame.renew:Disable() end
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(FRAME_W - 40)
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOP", parent, "TOP", 0, -68 - (index - 1) * ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")
    row:GetHighlightTexture():SetVertexColor(1, 0.75, 0.2)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0, 0, 0, 0.45)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", row, "LEFT", 8, 0)
    name:SetJustifyH("LEFT")
    row.name = name

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    count:SetJustifyH("RIGHT")
    row.count = count

    row:SetScript("OnClick", function(self) SelectRow(self) end)
    row:SetScript("OnDoubleClick", function(self)
        SelectRow(self)
        frame.renew:Click()
    end)
    row:Hide()
    return row
end

local function CreateFrameOnce()
    if frame then return frame end
    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetWidth(FRAME_W)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(36)
    icon:SetHeight(36)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    icon:SetTexture("Interface\\Icons\\INV_Potion_150")
    frame.icon = icon

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetText(L["Elixir of Renewal"])

    -- a fixed width and no height: the sentence wraps on as many lines as its language needs (French and German take
    -- three), and ShowList puts the list under its last line
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    text:SetWidth(FRAME_W - 18 - 36 - 10 - 18)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetText(L["Choose the raid to renew. Its bosses can be looted again this week."])
    frame.text = text

    frame.rows = {}
    for i = 1, MAX_ROWS do
        frame.rows[i] = CreateRow(frame, i)
    end

    local renew = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    renew:SetWidth(110)
    renew:SetHeight(22)
    renew:SetText(L["Renew"])
    renew:SetScript("OnClick", function()
        if not selected then return end
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_RAID_RENEWAL, tostring(selected))
        frame:Hide()
    end)
    frame.renew = renew

    local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancel:SetWidth(110)
    cancel:SetHeight(22)
    cancel:SetText(CANCEL)
    cancel:SetScript("OnClick", function() frame:Hide() end)

    renew:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 18)
    cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 18)

    tinsert(UISpecialFrames, FRAME_NAME)
    frame:Hide()
    return frame
end

local function ShowList(raids)
    CreateFrameOnce()
    local icon = GetItemIcon(600945)
    if icon then frame.icon:SetTexture(icon) end
    local n = math.min(#raids, MAX_ROWS)
    -- the list starts under the text's last line (title 18 px + gap above it, 10 px under it), never above 68
    local top = math.max(68, math.ceil(39 + frame.text:GetStringHeight() + 10))
    for i, row in ipairs(frame.rows) do
        local raid = raids[i]
        row:ClearAllPoints()
        row:SetPoint("TOP", frame, "TOP", 0, -top - (i - 1) * ROW_H)
        if i <= n and raid then
            row.mapId = raid.mapId
            row.name:SetText(raid.name)
            local full = raid.looted >= raid.total
            row.count:SetText(T("{looted} / {total} looted", { looted = raid.looted, total = raid.total }))
            if full then row.count:SetTextColor(1, 0.82, 0) else row.count:SetTextColor(0.8, 0.8, 0.8) end
            row:Show()
        else
            row.mapId = nil
            row:Hide()
        end
    end
    frame:SetHeight(top + n * ROW_H + 52)
    -- the first raid is picked already: one click on Renew does the common case
    SelectRow(n > 0 and frame.rows[1] or nil)
    frame:Show()
end

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_RAID_RENEWAL, function(body)
    body = body or ""
    local kind, rest = string.match(body, "^(%u+)|(.*)$")
    if kind == "LIST" then
        local raids = {}
        for part in string.gmatch(rest, "[^;]+") do
            local mapId, name, looted, total = string.match(part, "^(%d+)~([^~]*)~(%d+)~(%d+)$")
            if mapId then
                table.insert(raids, { mapId = tonumber(mapId), name = name, looted = tonumber(looted), total = tonumber(total) })
            end
        end
        if #raids > 0 then ShowList(raids) end
    elseif kind == "OK" then
        local _, name = string.match(rest, "^(%d+)|(.*)$")
        PlaySound("igQuestListComplete")
        local msg = T("{raid} is renewed: its bosses can be looted again this week.", { raid = name or "" })
        UIErrorsFrame:AddMessage(msg, 0.25, 0.85, 0.76, 1.0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFF66CCFF[Call Board]|r " .. msg)
    elseif kind == "FAIL" then
        local text = FAIL_TEXT[rest]
        if text then UIErrorsFrame:AddMessage(text, 1.0, 0.3, 0.3, 1.0) end
    end
    -- anything else is our own REQUEST_RAID_RENEWAL self-whisper coming back: ignored
end)
