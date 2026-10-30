-- Echo chat links + legacy PerkBrowser compatibility shim
-- The standalone Echoes Browser has been replaced by the Echo Journal
-- (modules/perks/echo_journal.lua). This file keeps two things:
--   1. The {echo:spellId:quality} chat-link handler used by shift-click linking
--   2. The ProjectEbonhold.PerkBrowser API and /echoes command, which now
--      open the Echo Journal so existing callers keep working.

local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.PerkBrowser = {}

-- Store echo data for chat linking
ProjectEbonhold.EchoLinks = ProjectEbonhold.EchoLinks or {}

-- Register custom echo hyperlink handler and chat filter
local function SetupEchoLinkHandler()
    -- Hook the hyperlink click handler for echo links
    local oldSetHyperlink = ItemRefTooltip.SetHyperlink
    ItemRefTooltip.SetHyperlink = function(self, link, ...)
        if link and link:match("^echo:") then
            local spellId = link:match("^echo:(%d+)")
            if spellId then
                spellId = tonumber(spellId)
                if spellId then
                    ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
                    ItemRefTooltip:SetHyperlink("spell:" .. spellId)
                    ItemRefTooltip:Show()
                    return
                end
            end
        end
        return oldSetHyperlink(self, link, ...)
    end

    -- Quality color codes
    local qualityColorCodes = {
        [0] = "ffffff", -- Common
        [1] = "19ff19", -- Uncommon
        [2] = "0066ff", -- Rare
        [3] = "cc66ff", -- Epic
        [4] = "ff8000"  -- Legendary
    }

    -- Chat message filter to convert echo markers to hyperlinks
    local function EchoLinkFilter(self, event, msg, ...)
        if msg and msg:find("{echo:") then
            -- Replace {echo:spellId:quality} with colored hyperlink
            msg = msg:gsub("{echo:(%d+):(%d+)}", function(spellId, quality)
                spellId = tonumber(spellId)
                quality = tonumber(quality) or 0
                local spellName = GetSpellInfo(spellId)
                if spellName then
                    local colorCode = qualityColorCodes[quality] or "ffffff"
                    return "|cff" .. colorCode .. "|Hecho:" .. spellId .. "|h[" .. spellName .. "]|h|r"
                end
                return "{echo:" .. spellId .. ":" .. quality .. "}"
            end)
            return false, msg, ...
        end
        return false
    end

    -- Register filter for all chat types
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", EchoLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", EchoLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", EchoLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", EchoLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", EchoLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", EchoLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", EchoLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", EchoLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", EchoLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", EchoLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", EchoLinkFilter)
end

SetupEchoLinkHandler()

-- Legacy API: opens the Echo Journal on the All Echoes tab
function ProjectEbonhold.PerkBrowser.Show()
    if ProjectEbonhold.EchoJournal then
        ProjectEbonhold.EchoJournal.Show(2)
    end
end

function ProjectEbonhold.PerkBrowser.Hide()
    if ProjectEbonhold.EchoJournal then
        ProjectEbonhold.EchoJournal.Hide()
    end
end

function ProjectEbonhold.PerkBrowser.Toggle()
    if ProjectEbonhold.EchoJournal then
        ProjectEbonhold.EchoJournal.Toggle()
    end
end

-- Slash command
SLASH_PERKBROWSER1 = "/echoes"
SlashCmdList["PERKBROWSER"] = function()
    ProjectEbonhold.PerkBrowser.Toggle()
end
