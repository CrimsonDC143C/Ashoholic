-- Real sync controls embedded in the shared dashboard's Settings window.
local addonName = ...
local addon = _G[addonName]
local UI, Data, Sync = addon.UI, addon.Data, addon.Sync

function UI.BuildDashboardSync(parent, Label, Button, say)
    local Style = UI.Style
    Label(parent, "TRUSTED CHARACTER SYNC", 0, 0, 650, 11, Style.gold)
    Label(parent, "Both online characters must trust each other. Only each account's own observations are exchanged; settings stay local.", 0, 24, 650, 11, Style.muted)
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetSize(240, 28)
    input:SetPoint("TOPLEFT", 8, -72)
    input:SetAutoFocus(false)
    input:SetMaxLetters(120)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local peers = Label(parent, "", 0, 120, 650, 11, Style.text)
    peers:SetHeight(60)
    local function RefreshPeers()
        local names = {}
        for _, name in pairs(Data.GetTrustedPeers()) do names[#names + 1] = name end
        table.sort(names)
        peers:SetText("Trusted: " .. (#names > 0 and table.concat(names, ", ") or "None"))
    end
    local function Run(action, argument)
        local ok, problem = pcall(action, argument)
        if not ok then
            say(tostring(problem))
            print("|cffff6060Ashoholic settings:|r " .. tostring(problem))
            return
        end
        input:ClearFocus()
        RefreshPeers()
        say("Action submitted; progress and import confirmations appear in chat.")
    end
    Button(parent, "Trust", 250, 72, 90, 28, function() Run(Sync.Trust, input:GetText()) end)
    Button(parent, "Remove", 348, 72, 90, 28, function() Run(Sync.Untrust, input:GetText()) end)
    Button(parent, "Sync character", 446, 72, 180, 28, function() Run(Sync.Start, input:GetText()) end)
    Button(parent, "Sync all trusted", 0, 192, 210, 30, function() Run(Sync.StartAll) end)
    Label(parent, "Large snapshots take several minutes. Both sides report receipt and confirmation; an unchanged snapshot is still a successful exchange.", 0, 238, 650, 11, Style.muted)
    Label(parent, "OFFLINE MERGE", 0, 298, 650, 11, Style.gold)
    Label(parent, "Exit the game fully, then run Ashoholic's OfflineMerge.ps1. Log in again to import the generated inbox. FastSwap's installer is separate.", 0, 322, 650, 11, Style.muted)
    local progress = Label(parent, "", 0, 370, 650, 10, Style.teal)
    progress:SetHeight(46)
    local elapsed = 0
    parent:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.5 then return end
        elapsed = 0
        progress:SetText(Sync.GetStatus())
    end)
    parent.Refresh = function()
        RefreshPeers()
        progress:SetText(Sync.GetStatus())
    end
    RefreshPeers()
end
