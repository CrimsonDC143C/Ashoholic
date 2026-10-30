--
-- Custom GM ticket creation channel (workaround for blocked Blizzard UI path).
--
-- The default 3.3.5 "Open Ticket" submit button calls NewGMTicket() which sends
-- CMSG_GMTICKET_CREATE. On Ashendor the help-frame state machine can wedge in a
-- "completed but not closed" state and silently refuse to submit. This module
-- routes ticket submission through our addon comm channel instead, which on
-- the server forcibly closes any stale ticket and creates a fresh one.
--
-- Public surface:
--   /ticket <text>         -- send a new ticket using <text> as the message.
--   ProjectEbonhold.CustomTicket.Submit(text)  -- programmatic submit.
--

local ADDON_NAME = "ProjectEbonhold"

local CS = ProjectEbonhold and ProjectEbonhold.CS
local SS = ProjectEbonhold and ProjectEbonhold.SS
if not CS or not SS then
    return
end

local MAX_TICKET_LEN = 1990

local function chat(msg, r, g, b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[GM Ticket]|r " .. tostring(msg), r or 1, g or 1, b or 1)
    end
end

local function Trim(s)
    if not s then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Submit(text)
    text = Trim(text or "")
    if text == "" then
        chat("Cannot submit an empty ticket.", 1, 0.4, 0.4)
        return false
    end
    if #text > MAX_TICKET_LEN then
        text = text:sub(1, MAX_TICKET_LEN)
    end

    if not ProjectEbonhold or not ProjectEbonhold.sendToServer then
        chat("Addon comms not ready yet, please retry in a moment.", 1, 0.4, 0.4)
        return false
    end

    ProjectEbonhold.sendToServer(CS.REQUEST_CREATE_GM_TICKET, text)
    chat("Ticket submitted. Waiting for server confirmation...")
    return true
end

ProjectEbonhold.CustomTicket = ProjectEbonhold.CustomTicket or {}
ProjectEbonhold.CustomTicket.Submit = Submit

-- Server reply handler: "OK,<id>" or "FAIL,<reason>"
ProjectEbonhold.onEventReceived(SS.SEND_GM_TICKET_CREATE_RESULT, function(body)
    body = body or ""
    local status, detail = body:match("^([^,]+),?(.*)$")
    status = status or ""
    if status == "OK" then
        local id = tonumber(detail) or 0
        chat(string.format("Ticket #%d created. A GM will respond as soon as possible.", id), 0.4, 1, 0.4)
        -- Refresh Blizzard-side state if the standard frame happens to be open.
        if GetGMTicket then GetGMTicket() end
    else
        local reason = detail ~= "" and detail or status
        chat("Ticket creation failed: " .. reason, 1, 0.4, 0.4)
    end
end)

-- ---------------------------------------------------------------------------
-- Slash command: /ticket <text>
-- ---------------------------------------------------------------------------
SLASH_PROJECTEBONHOLDTICKET1 = "/ticket"
SlashCmdList["PROJECTEBONHOLDTICKET"] = function(msg)
    Submit(msg)
end

-- ---------------------------------------------------------------------------
-- Hook the Blizzard "Submit" button on the Open Ticket frame so users who go
-- through the regular UI also get routed through our custom channel.
--
-- The HelpFrame and its children are created on first use, so we wait for them
-- to exist before swapping the OnClick. We poll cheaply on PLAYER_ENTERING_WORLD
-- and HELP_FRAME-related events.
-- ---------------------------------------------------------------------------

-- The Blizzard help frame has two distinct submit flows depending on whether
-- the player already has a ticket:
--   * No ticket  -> HelpFrameOpenTicket page, button HelpFrameOpenTicketSubmit,
--                   text in HelpFrameOpenTicketHelpTopEditBox.
--   * Has ticket -> HelpFrameTicket page,     button HelpFrameTicketSubmit,
--                   text in HelpFrameTicketScrollFrame's editbox child
--                   (commonly named HelpFrameTicketScrollFrameText, but the
--                   exact name varies across UI replacements).
-- Our server handler force-closes any existing ticket and creates a fresh one,
-- so we treat "update" identically to "create" — both routes call Submit().

local hookedButtons = {}

local function ReadFromEditBox(widget)
    if not widget then return nil end
    if type(widget.GetText) ~= "function" then return nil end
    local ok, t = pcall(widget.GetText, widget)
    if ok and t and t ~= "" then return t end
    return nil
end

-- Walk a frame's children depth-first looking for the first non-empty EditBox.
local function FindEditBoxText(frame, depth)
    if not frame or depth and depth > 6 then return nil end
    if frame.GetObjectType then
        local ok, otype = pcall(frame.GetObjectType, frame)
        if ok and otype == "EditBox" then
            local t = ReadFromEditBox(frame)
            if t then return t end
        end
    end
    if frame.GetNumChildren then
        local ok, n = pcall(frame.GetNumChildren, frame)
        if ok and n and n > 0 then
            for i = 1, n do
                local child = select(i, frame:GetChildren())
                local t = FindEditBoxText(child, (depth or 0) + 1)
                if t then return t end
            end
        end
    end
    return nil
end

-- Try the well-known widget names first (fast path), then fall back to a
-- recursive scan of the relevant frames for any populated EditBox.
local function GetTicketText()
    local candidates = {
        "HelpFrameOpenTicketHelpTopEditBox",
        "HelpFrameTicketScrollFrameText",
        "HelpFrameTicketScrollChildFrameText",
        "HelpFrameOpenTicketScrollFrameText",
        "GMChatStatusFrameMessage",
    }
    for _, name in ipairs(candidates) do
        local t = ReadFromEditBox(_G[name])
        if t then return t end
    end

    for _, frameName in ipairs({ "HelpFrameTicket", "HelpFrameOpenTicket" }) do
        local t = FindEditBoxText(_G[frameName])
        if t then return t end
    end
    return ""
end

local function InstallOn(buttonName)
    if hookedButtons[buttonName] then return true end
    local btn = _G[buttonName]
    if not btn or type(btn.SetScript) ~= "function" then return false end

    btn:SetScript("OnClick", function()
        local text = GetTicketText()
        if text == "" then
            chat("Please type a message before submitting.", 1, 0.4, 0.4)
            return
        end
        if Submit(text) then
            if HelpFrame and HelpFrame:IsShown() then
                HideUIPanel(HelpFrame)
            end
        end
    end)

    hookedButtons[buttonName] = true
    return true
end

local TICKET_BUTTONS = { "HelpFrameOpenTicketSubmit", "HelpFrameTicketSubmit" }

local function TryInstallHooks()
    local allDone = true
    for _, name in ipairs(TICKET_BUTTONS) do
        if not InstallOn(name) then allDone = false end
    end
    return allDone
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and (arg1 == ADDON_NAME or arg1 == "Blizzard_HelpFrame") then
        TryInstallHooks()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not TryInstallHooks() then
            -- HelpFrame may be load-on-demand; force-load once then retry.
            if LoadAddOn then LoadAddOn("Blizzard_HelpFrame") end
            TryInstallHooks()
        end
    end
end)
