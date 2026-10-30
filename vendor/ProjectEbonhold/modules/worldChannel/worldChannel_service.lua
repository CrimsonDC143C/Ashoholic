local addon, Addon = ...

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.WorldChannelService = {}

-- Bump this whenever the world-channel prompt changes in a way that every
-- player (including those who already dismissed an older version) should see
-- once. v1 = original single "world" prompt; v2 = multi-language prompt.
local CURRENT_PROMPT_VERSION = 2

-- The channels offered by the prompt. `default = true` rows are pre-checked;
-- any channel the player is already in is pre-checked as well (see the UI).
ProjectEbonhold.WorldChannelService.Channels = {
    { name = "world",    label = "World - English",  default = true },
    { name = "world-fr", label = "World - Français", default = false },
    { name = "world-de", label = "World - Deutsch",  default = false },
    { name = "world-es", label = "World - Español   ",  default = false },
}

-- Ensure DB is initialized
local function EnsureDBInitialized()
    if not ProjectEbonholdDB then
        ProjectEbonholdDB = {}
    end
    -- Tracks the highest prompt version each character has acknowledged.
    if not ProjectEbonholdDB.worldChannelPromptVersion then
        ProjectEbonholdDB.worldChannelPromptVersion = {}
    end
end

local function GetCharacterKey()
    local playerName = UnitName("player")
    local realmName = GetRealmName()
    return playerName .. "-" .. realmName
end

local function GetSeenVersion()
    EnsureDBInitialized()
    return ProjectEbonholdDB.worldChannelPromptVersion[GetCharacterKey()] or 0
end

local function MarkPromptSeen()
    EnsureDBInitialized()
    ProjectEbonholdDB.worldChannelPromptVersion[GetCharacterKey()] = CURRENT_PROMPT_VERSION
end

-- Returns true if the player is currently a member of the given channel.
-- GetChannelName returns a valid (>0) slot id only when joined; it returns 0
-- for a known-but-not-joined channel and nil for a name not in the list at all.
-- Note: `id ~= 0` alone is buggy because in Lua `nil ~= 0` is true, which would
-- report unjoined channels as joined and pre-check them in the popup.
function ProjectEbonhold.WorldChannelService.IsInChannel(channelName)
    local id = GetChannelName(channelName)
    return type(id) == "number" and id > 0
end

-- Reconcile channel membership to match the player's selection: join any
-- checked channel they are not in, and leave any unchecked channel they are in.
-- This lets the popup both join and leave (useful when reopened via slash).
function ProjectEbonhold.WorldChannelService.ApplySelection(channelNames)
    local wanted = {}
    for _, name in ipairs(channelNames) do
        wanted[name] = true
    end

    for _, ch in ipairs(ProjectEbonhold.WorldChannelService.Channels) do
        local joined = ProjectEbonhold.WorldChannelService.IsInChannel(ch.name)
        if wanted[ch.name] and not joined then
            SlashCmdList["JOIN"](ch.name)
        elseif not wanted[ch.name] and joined then
            LeaveChannelByName(ch.name)
        end
    end

    MarkPromptSeen()
end

function ProjectEbonhold.WorldChannelService.Decline()
    MarkPromptSeen()
end

local function CheckAndShowPrompt()
    if GetSeenVersion() < CURRENT_PROMPT_VERSION then
        if ProjectEbonhold.WorldChannelUI and ProjectEbonhold.WorldChannelUI.ShowPrompt then
            ProjectEbonhold.WorldChannelUI.ShowPrompt()
        end
    end
end

-- Slash command to (re)open the popup at any time, so players can join or
-- leave the community channels whenever they want.
SLASH_PROJECTEBONHOLDCHANNELS1 = "/worldchannel"
SLASH_PROJECTEBONHOLDCHANNELS2 = "/channels"
SLASH_PROJECTEBONHOLDCHANNELS3 = "/channel"
SlashCmdList["PROJECTEBONHOLDCHANNELS"] = function()
    if ProjectEbonhold.WorldChannelUI and ProjectEbonhold.WorldChannelUI.ShowPrompt then
        ProjectEbonhold.WorldChannelUI.ShowPrompt()
    end
end

-- Event handler for WoW 3.3.5a
local eventFrame = CreateFrame("Frame")

-- The client restores cached channel memberships on its own, several seconds
-- after entering the world. Showing the prompt before that restore completes
-- makes Apply issue /join for channels the character is about to be rejoined
-- to anyway, which registers the channel twice client-side and breaks
-- outgoing chat (bugs #2664/#2676). Poll until the player shows up in one of
-- the offered channels (restore finished) before prompting; characters with
-- no cached membership never satisfy the check, so fall back to a generous
-- timeout.
local PROMPT_POLL_INTERVAL = 2
local PROMPT_MAX_WAIT = 30
local promptWaitActive = false

local function IsInAnyOfferedChannel()
    for _, ch in ipairs(ProjectEbonhold.WorldChannelService.Channels) do
        if ProjectEbonhold.WorldChannelService.IsInChannel(ch.name) then
            return true
        end
    end
    return false
end

local function WaitForChannelRestore(elapsed)
    if IsInAnyOfferedChannel() or elapsed >= PROMPT_MAX_WAIT then
        promptWaitActive = false
        CheckAndShowPrompt()
    else
        C_Timer.After(PROMPT_POLL_INTERVAL, function()
            WaitForChannelRestore(elapsed + PROMPT_POLL_INTERVAL)
        end)
    end
end

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Nothing to wait for if this character already acknowledged the
        -- current prompt version; also keep a single poll chain across
        -- repeated zone-ins (instance transfers fire this event too).
        if promptWaitActive or GetSeenVersion() >= CURRENT_PROMPT_VERSION then
            return
        end
        promptWaitActive = true
        C_Timer.After(PROMPT_POLL_INTERVAL, function()
            WaitForChannelRestore(PROMPT_POLL_INTERVAL)
        end)
    end
end)
