local L, T = ProjectEbonhold.L, ProjectEbonhold.T
-- Module: Request to Join / Suggest Invite (retail-style group QoL, 2026-11-13)
--
-- One entry in the right-click menu of a player who is not in your group:
--   * you have no group           -> "Request to Join": asks the leader of that player's group to take you in;
--   * you are a member, no rights -> "Suggest Invite": a stock invite, which the server turns into a
--                                    suggestion for your leader instead of "you are not the leader".
-- The leader gets a popup. Accepting sends a stock invite (every invite rule still applies), and the
-- applicant accepts it by itself here, since they asked for it.
--
-- Transport: custom opcodes of ebonhold.dll (grouprequest_client.h). Client -> server through
-- EbonholdGroupRequestJoin / EbonholdGroupRequestAnswer; server -> client through
-- GroupRequest_OnPacket('<hex>') = SMSG_GROUP_REQUEST (uint8 kind, cstring text). Server side:
-- game/Ashendor/GroupRequests/GroupRequestMgr (its header documents every text).

local BUTTON = "EBONHOLD_GROUP_REQUEST"
local POPUP_JOIN = "EBONHOLD_GROUP_JOIN_REQUEST"
local POPUP_SUGGEST = "EBONHOLD_GROUP_SUGGEST_INVITE"
local POPUP_TIMEOUT = 80     -- the server forgets a request after 90 s
local AUTO_ACCEPT_WINDOW = 95

local CLASS_TOKENS = {
    [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
    [6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID",
}

-- Leader name -> GetTime() deadline: the invite of a leader we asked to join is accepted by itself.
local awaitingInvite = {}

-- "Is that player in a group?" A client cannot see it for a player outside its own group, so the
-- server is asked (EbonholdGroupRequestJoin("?name"), answer = packet kind 3) on target and mouseover,
-- and "Request to Join" is only offered once it said yes (2026-11-15).
local PROBE_FRESH = 30      -- an answer is trusted this long
local PROBE_RESEND = 3      -- the same name is not asked again sooner
local probes = {}           -- name -> { grouped = bool|nil, at = answer time, asked = ask time }
local reopenFor             -- a menu opened before the answer came: its name, its dropdown frame
local reopenFrame

local function Print(msg)
    local info = ChatTypeInfo and ChatTypeInfo["SYSTEM"]
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(msg, info and info.r or 1, info and info.g or 1, info and info.b or 0)
    end
end

local function ClassText(classId)
    local token = CLASS_TOKENS[tonumber(classId) or 0]
    if not token then return "" end
    local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if color then
        return string.format("|cff%02x%02x%02x%s|r", math.floor(color.r * 255), math.floor(color.g * 255), math.floor(color.b * 255), name)
    end
    return name
end

local function InMyGroup(name)
    if not name then return false end
    for i = 1, GetNumRaidMembers() do
        if UnitName("raid" .. i) == name then return true end
    end
    for i = 1, GetNumPartyMembers() do
        if UnitName("party" .. i) == name then return true end
    end
    return false
end

local function CanInvite()
    return IsPartyLeader() or IsRaidLeader() or IsRaidOfficer()
end

local function HaveGroup()
    return GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0
end

-- true / false when a fresh answer is known, nil otherwise.
local function KnownGrouped(name)
    local p = probes[name]
    if p and p.grouped ~= nil and GetTime() - p.at < PROBE_FRESH then
        return p.grouped
    end
    return nil
end

local function Probe(name)
    if not name or name == "" or not EbonholdGroupRequestJoin or HaveGroup() then return end
    if name == UnitName("player") or InMyGroup(name) then return end
    local now = GetTime()
    local p = probes[name]
    if p and now - p.asked < PROBE_RESEND then return end
    if not p then
        p = {}
        probes[name] = p
    end
    p.asked = now
    EbonholdGroupRequestJoin("?" .. name)
end

local function ProbeUnit(unit)
    if UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
        Probe(UnitName(unit))
    end
end

local function OnProbeAnswer(name, grouped)
    if not name then return end
    local p = probes[name] or { asked = 0 }
    probes[name] = p
    p.grouped = grouped == "1"
    p.at = GetTime()

    -- The menu was built before the answer: rebuild it at the cursor so the entry appears.
    if reopenFor == name then
        local frame = reopenFor and reopenFrame
        reopenFor, reopenFrame = nil, nil
        if p.grouped and frame and DropDownList1 and DropDownList1:IsShown() and (UIDROPDOWNMENU_OPEN_MENU == frame or UIDROPDOWNMENU_OPEN_MENU == frame:GetName()) then
            HideDropDownMenu(1)
            ToggleDropDownMenu(1, nil, frame, "cursor")
        end
    end
end

-- ── Leader popups ────────────────────────────────────────────────────────

local function Answer(code, data)
    if data and EbonholdGroupRequestAnswer then
        EbonholdGroupRequestAnswer(code, data.requester, data.subject)
    end
end

local function MakePopup()
    return {
        text = "%s",
        button1 = ACCEPT,
        button2 = DECLINE,
        OnAccept = function(self, data)
            Answer(1, data)
            if data and data.subject then
                InviteUnit(data.subject)
            end
        end,
        OnCancel = function(self, data, reason)
            Answer(reason == "timeout" and 2 or 0, data)
        end,
        timeout = POPUP_TIMEOUT,
        whileDead = 1,
        multiple = 1,
        showAlert = 1,
    }
end

StaticPopupDialogs[POPUP_JOIN] = MakePopup()
StaticPopupDialogs[POPUP_SUGGEST] = MakePopup()

local function ShowRequest(kind, requester, subject, classId, level)
    local who = T("{name} (level {level} {class})", { name = subject, level = level or "?", class = ClassText(classId) })
    local dialog
    if kind == "join" then
        dialog = StaticPopup_Show(POPUP_JOIN, T("{who} asks to join your group.", { who = who }))
    else
        dialog = StaticPopup_Show(POPUP_SUGGEST, T("{member} suggests inviting {who}.", { member = requester, who = who }))
    end
    if dialog then
        dialog.data = { requester = requester, subject = subject }
        PlaySound("igPlayerInvite")
    else
        Answer(2, { requester = requester, subject = subject }) -- no room for another popup
    end
end

-- ── Results for the requester ────────────────────────────────────────────

local function FailText(kind, target, reason)
    if reason == "notfound" then return T("{name} could not be found.", { name = target }) end
    if reason == "ingroup" then return L["Leave your group before asking to join another one."] end
    if reason == "notgrouped" then return T("{name} is not in a group.", { name = target }) end
    if reason == "noleader" then return L["The leader of that group is offline."] end
    if reason == "lfg" then return L["Dungeon Finder groups cannot be joined this way."] end
    if reason == "full" then return L["That group is full."] end
    if reason == "faction" then return T("You cannot group with {name}.", { name = target }) end
    if reason == "restricted" then return L["Nobody can join or leave a group during the Trials."] end
    if reason == "torment" then return T("{name} plays at another Torment level.", { name = target }) end
    if reason == "wait" then return L["Wait a few seconds before sending another request."] end
    if reason == "pending" then return T("A request for {name} is already waiting for the leader.", { name = target }) end
    return T("Your request could not be sent ({reason}).", { reason = tostring(reason) })
end

local function ShowResult(status, kind, name, extra)
    if status == "SENT" then
        if kind == "join" then
            awaitingInvite[extra] = GetTime() + AUTO_ACCEPT_WINDOW
            Print(T("You asked to join {name}'s group. Waiting for {leader}...", { name = name, leader = extra }))
        else
            Print(T("You suggested inviting {name}. Waiting for {leader}...", { name = name, leader = extra }))
        end
    elseif status == "FAIL" then
        if name and name:sub(1, 1) == "?" then return end -- a probe an older server took for a request
        Print(FailText(kind, name, extra))
    elseif status == "ACCEPTED" then
        if kind == "join" then
            awaitingInvite[extra] = GetTime() + AUTO_ACCEPT_WINDOW
        else
            Print(T("{leader} invited {name}.", { leader = extra, name = name }))
        end
    elseif status == "DECLINED" then
        awaitingInvite[extra] = nil
        if kind == "join" then
            Print(T("{leader} declined your request to join the group.", { leader = extra }))
        else
            Print(T("{leader} declined to invite {name}.", { leader = extra, name = name }))
        end
    elseif status == "EXPIRED" then
        awaitingInvite[extra] = nil
        if kind == "join" then
            Print(T("{leader} did not answer your request to join the group.", { leader = extra }))
        else
            Print(T("{leader} did not answer your suggestion to invite {name}.", { leader = extra, name = name }))
        end
    end
end

-- ── Packet entry (called by ebonhold.dll) ────────────────────────────────

local function Split(text)
    local parts = {}
    for field in string.gmatch(text .. "|", "([^|]*)|") do
        parts[#parts + 1] = field
    end
    return parts
end

function GroupRequest_OnPacket(hex)
    if type(hex) ~= "string" or #hex < 2 then return end
    local data = hex:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end)
    local kind = data:byte(1)
    local text = data:sub(2):match("^[^%z]*") or ""
    local f = Split(text)

    if kind == 1 then
        -- "<join|suggest>|<requester>|<subject>|<class id>|<level>"
        ShowRequest(f[1], f[2], f[3], f[4], f[5])
    elseif kind == 2 then
        -- "<status>|<kind>|<name>|<leader or reason>"
        ShowResult(f[1], f[2], f[3], f[4])
    elseif kind == 3 then
        -- "<name as asked>|<0|1>"
        OnProbeAnswer(f[1], f[2])
    end
end

-- The invite we asked for: accept it without a second click.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:SetScript("OnEvent", function(self, event, leader)
    if event == "PLAYER_TARGET_CHANGED" then return ProbeUnit("target") end
    if event == "UPDATE_MOUSEOVER_UNIT" then return ProbeUnit("mouseover") end
    local deadline = leader and awaitingInvite[leader]
    if not deadline then return end
    awaitingInvite[leader] = nil
    if GetTime() > deadline then return end
    AcceptGroup()
    StaticPopup_Hide("PARTY_INVITE")
end)

-- ── Unit popup entry ─────────────────────────────────────────────────────
--
-- Same approach as options/xp_bonus.lua: the entry goes just above Cancel, so no stock entry
-- (Set Focus...) is read after it in the same pass. PLAYER = a player outside your group
-- (target / portrait), FRIEND = a name clicked in the chat or the friends list.

local menuMode, menuName -- set while the menu is built, read by the click

if type(UnitPopupButtons) == "table" and type(UnitPopupMenus) == "table" then
    UnitPopupButtons[BUTTON] = { text = L["Request to Join"], dist = 0 }

    for _, which in ipairs({ "PLAYER", "FRIEND" }) do
        local menu = UnitPopupMenus[which]
        if menu then
            local at = #menu + 1
            for i, value in ipairs(menu) do
                if value == "CANCEL" then
                    at = i
                    break
                end
            end
            table.insert(menu, at, BUTTON)
        end
    end

    hooksecurefunc("UnitPopup_HideButtons", function()
        if UIDROPDOWNMENU_MENU_LEVEL ~= 1 then return end -- a sub-menu: its own list, not ours
        local dropdownMenu = UIDROPDOWNMENU_INIT_MENU
        local menu = dropdownMenu and UnitPopupMenus[dropdownMenu.which]
        local shown = UnitPopupShown and UnitPopupShown[UIDROPDOWNMENU_MENU_LEVEL]
        if not menu or not shown then return end

        local index
        for i, value in ipairs(menu) do
            if value == BUTTON then
                index = i
                break
            end
        end
        if not index then return end

        local unit, name = dropdownMenu.unit, dropdownMenu.name
        if unit and UnitExists(unit) then
            name = UnitName(unit)
        end

        menuMode, menuName = nil, name
        if name and name ~= UnitName("player") and not InMyGroup(name)
            and (not unit or not UnitExists(unit) or UnitIsPlayer(unit)) then
            if not HaveGroup() then
                -- Only for a player the server says is grouped; unknown -> ask now, and the
                -- answer reopens this menu with the entry if it is yes.
                local grouped = KnownGrouped(name)
                if grouped then
                    menuMode = "join"
                    UnitPopupButtons[BUTTON].text = L["Request to Join"]
                elseif grouped == nil then
                    reopenFor, reopenFrame = name, dropdownMenu
                    Probe(name)
                end
            elseif not CanInvite() then
                menuMode = "suggest"
                UnitPopupButtons[BUTTON].text = L["Suggest Invite"]
            end
        end

        if not menuMode then
            shown[index] = 0
        end
    end)

    hooksecurefunc("UnitPopup_OnClick", function(self)
        if self.value ~= BUTTON or not menuName then return end
        if menuMode == "join" then
            if EbonholdGroupRequestJoin then
                EbonholdGroupRequestJoin(menuName)
            else
                Print(L["Your game client is out of date: restart the launcher to update it."])
            end
        elseif menuMode == "suggest" then
            InviteUnit(menuName)
        end
    end)
end
