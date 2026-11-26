-- The non-appearance sections of the live Settings window.
local addonName = ...
local addon = _G[addonName]
local UI, Data, Sync = addon.UI, addon.Data, addon.Sync
local Settings, state, Profiles = UI.Settings, UI.state, UI.Profiles
local GOLD, MUTED, TEAL = UI.GOLD, UI.MUTED, UI.TEAL

local function BuildColumns(body)
    UI.Label(body, "Choose columns beside the character name. Use < / > to reorder; drag header edges to resize.",
        0, 0, 660, 11, GOLD)
    local buttons = {}
    local notice = UI.Label(body, "", 0, 315, 660, 11, GOLD)
    local function Index(key)
        for index, selected in ipairs(UI.columnOrder) do
            if selected == key then return index end
        end
    end
    local function RefreshColumns()
        for index, column in ipairs(UI.COLUMNS) do
            local selected = Index(column.key)
            buttons[index].text:SetText((selected and "[x] " .. selected .. ". " or "[ ] ") .. column.title)
        end
        UI.Refresh()
    end
    for index, column in ipairs(UI.COLUMNS) do
        local key = column.key
        local x, y = ((index - 1) % 2) * 330, 32 + math.floor((index - 1) / 2) * 38
        buttons[index] = UI.Button(body, "", x, y, 240, 28, function()
            local selected = Index(key)
            notice:SetText("")
            if selected then
                table.remove(UI.columnOrder, selected)
                for priority = #state.rosterSort, 1, -1 do
                    if state.rosterSort[priority].key == key then table.remove(state.rosterSort, priority) end
                end
            else
                UI.columnOrder[#UI.columnOrder + 1] = key
            end
            RefreshColumns()
            Settings.Persist()
        end)
        for direction = -1, 1, 2 do
            local step = direction
            UI.Button(body, step == -1 and "<" or ">", x + (step == -1 and 248 or 286), y, 34, 28, function()
                local selected = Index(key)
                if selected and selected + step >= 1 and selected + step <= #UI.columnOrder then
                    UI.columnOrder[selected], UI.columnOrder[selected + step] =
                        UI.columnOrder[selected + step], UI.columnOrder[selected]
                    RefreshColumns()
                    Settings.Persist()
                else
                    notice:SetText("Select this column first; only selected columns can move.")
                end
            end)
        end
    end
    Settings.Toggle(body, "Show parked-run detail panel", 0, 273, 420,
        function() return state.detail end, function(value) state.detail = value; UI.Refresh() end)
    UI.Label(body, "Hiding the detail panel gives the roster the full width.", 0, 342, 660, 10, MUTED)
    body.Refresh = RefreshColumns
end

local function BuildTabs(body)
    UI.Label(body, "SHOW TABS  (Roster is always shown)", 0, 0, 400, 11, GOLD)
    for index, entry in ipairs({ { "Raids", "Raids & Dungeons" }, { "Activities", "Activities" },
        { "Progression", "Progression" }, { "Trials", "Trials" } }) do
        local key = entry[1]
        Settings.Toggle(body, entry[2], ((index - 1) % 2) * 330, 22 + math.floor((index - 1) / 2) * 34, 320,
            function() return not state.hiddenTabs[key] end,
            function(value) state.hiddenTabs[key] = not value; UI.Refresh() end)
    end
    UI.Label(body, "WHEN THE WINDOW OPENS", 0, 112, 400, 11, GOLD)
    Settings.Choices(body, { { "last", "Last used tab" }, { "Roster", "Roster" },
        { "Raids", "Raids & Dungeons" }, { "Activities", "Activities" },
        { "Progression", "Progression" }, { "Trials", "Trials" } }, 0, 134, 210, 3,
        function() return state.openTab end, function(value) state.openTab = value end)
    UI.Label(body, "EXTRAS", 0, 218, 400, 11, GOLD)
    for index, entry in ipairs({ { "openLogin", "Open Ashoholic on login" },
        { "combatHide", "Hide automatically in combat" }, { "lockWindow", "Lock window position" },
        { "escClose", "Escape closes the window" } }) do
        local key = entry[1]
        Settings.Toggle(body, entry[2], ((index - 1) % 2) * 330, 240 + math.floor((index - 1) / 2) * 34, 320,
            function() return state.window[key] end,
            function(value) state.window[key] = value; UI.Refresh() end)
    end
    UI.Label(body, "Combat hiding does not reopen the window automatically.", 0, 330, 660, 10, MUTED)
end

local function BuildAccounts(body)
    UI.Label(body, "CURRENT ACCOUNT ALIAS", 0, 0, 660, 11, GOLD)
    local input = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", 8, -26)
    input:SetSize(300, 28)
    input:SetAutoFocus(false)
    input:SetMaxLetters(32)
    local function Current()
        for _, account in ipairs(UI.ReadModel().accounts) do
            if account.isCurrent then return account end
        end
    end
    local function Rename(name)
        local account = Current()
        name = Settings.Trim(name)
        if not account then Settings.Say("The current account is not available yet."); return end
        if name == "" or #name > 32 or name:find("[%c|]") then
            Settings.Say("Use a plain-text name of 1-32 characters.")
            return
        end
        UI.RenameAccount(account, name)
        input:ClearFocus()
        UI.Refresh()
        Settings.ShowSection("Accounts")
        Settings.Say("Account alias saved.")
    end
    UI.Button(body, "Rename", 322, 26, 120, 28, function() Rename(input:GetText()) end)
    UI.Button(body, "Restore default", 452, 26, 160, 28, function()
        local account = Current()
        if account then Rename(UI.AccountConfig(account.id).originalName or account.name) end
    end)
    input:SetScript("OnEnterPressed", function() Rename(input:GetText()) end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    UI.Label(body, "ALL ACCOUNTS", 0, 82, 660, 11, GOLD)
    local scroll, list = UI.Scroll(body, "AshoholicSettingsAccounts", 0, 104, 660, 270)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", UI.ScrollBy)
    local rows = {}
    local function NewRow(index)
        local row = UI.Surface(list, 0, (index - 1) * 46, 628, 40)
        row.name = UI.Label(row, "", 12, 14, 240, 12)
        row.swatch = row:CreateTexture(nil, "OVERLAY")
        row.swatch:SetTexture(UI.WHITE)
        row.swatch:SetPoint("TOPLEFT", 260, -10)
        row.swatch:SetSize(30, 20)
        UI.Button(row, "Color...", 298, 6, 92, 28, function()
            local id = row.account and row.account.id
            if not id then return end
            UI.PickColor(function(color)
                for _, account in ipairs(UI.ReadModel().accounts) do
                    if account.id == id then UI.SetAccountColor(account, UI.Clone(color)); break end
                end
                UI.Refresh()
                Settings.ShowSection("Accounts")
            end, row.account.color or UI.STYLE.accountText)
        end)
        Settings.Toggle(row, "Start collapsed", 398, 6, 234,
            function() return row.account and row.account.collapsed end,
            function(value)
                if row.account then UI.SetAccountCollapsed(row.account, value); UI.Refresh() end
            end)
        return row
    end
    body.Refresh = function()
        local accounts = UI.ReadModel().accounts
        local current = Current()
        if not input:HasFocus() then input:SetText(current and current.name or "") end
        for index, account in ipairs(accounts) do
            local row = rows[index]
            if not row then row = NewRow(index); rows[index] = row end
            row.account = account
            row.name:SetText(account.name .. (account.isCurrent and "  (current)" or ""))
            row.swatch:SetVertexColor(unpack(account.color or GOLD))
            row:Show()
        end
        for index = #accounts + 1, #rows do rows[index].account = nil; rows[index]:Hide() end
        local height = math.max(270, #accounts * 46)
        list:SetHeight(height)
        UI.ClampScroll(scroll, height, 270)
        Settings.UpdateAll()
    end
    UI.Label(body, "Aliases are local; account identity and sync data do not change.", 0, 390, 660, 10, MUTED)
end

local function BuildAlerts(body)
    UI.Label(body, "REMIND ME ABOUT", 0, 0, 400, 11, GOLD)
    for index, option in ipairs(UI.ALERT_OPTIONS) do
        local key = option.key
        Settings.Toggle(body, option.label, 0, 22 + (index - 1) * 34, 420,
            function() return state.alerts[key] end,
            function(value) state.alerts[key] = value; UI.Refresh() end)
    end
    UI.Label(body, "SHOW ALERTS AS", 0, 202, 400, 11, GOLD)
    Settings.Choices(body, { { "chat", "Chat message" }, { "center", "Center of screen" },
        { "silent", "Silent (badge only)" } }, 0, 224, 210, 3,
        function() return state.alertStyle end, function(value) state.alertStyle = value end)
    UI.Button(body, "Send test alert", 0, 274, 210, 30, function()
        UI.TestAlert()
        UI.Refresh()
        Settings.Say("Test reminder sent.")
    end)
end

local function BuildProfiles(body)
    UI.Label(body, "ACTIVE PROFILE", 0, 0, 640, 11, GOLD)
    local active = UI.Label(body, "", 0, 28, 380, 12)
    UI.Button(body, "Choose profile...", 438, 22, 210, 28, function()
        UI.Dialog("Choose profile", "Saved profiles: " .. table.concat(Profiles.Names(), ", "), {
            box = state.profile, primary = "Use",
            validate = function(name) if not Profiles.store.saved[name] then return "Enter an existing profile name." end end,
            onAccept = function(name) Profiles.Use(name); Settings.ShowSection("Profiles & Sharing") end,
        })
    end)
    UI.Label(body, "PROFILE APPLIES TO", 0, 72, 400, 11, GOLD)
    Settings.Choices(body, { { "character", "This character" }, { "account", "This account" } }, 0, 94, 210, 2,
        function() return state.profileScope end,
        function(scope) state.profileScope = scope; Profiles.Bind(state.profile) end)
    UI.Button(body, "New profile...", 0, 146, 210, 30, function()
        UI.Dialog("New profile", "Copies your current settings; changes save automatically.", {
            box = "", primary = "Create",
            validate = function(value)
                local name = Settings.Trim(value)
                if name == "" or #name > 40 or name:find("[%c|]") then return "Use a plain profile name of 1-40 characters." end
                if Profiles.store.saved[name] then return "That profile already exists." end
            end,
            onAccept = function(value)
                local name = Settings.Trim(value)
                Profiles.store.saved[name] = Profiles.Capture()
                Profiles.Use(name)
                Settings.ShowSection("Profiles & Sharing")
            end,
        })
    end)
    UI.Button(body, "Copy from...", 218, 146, 210, 30, function()
        UI.Dialog("Copy profile", "Enter an existing profile to copy into '" .. state.profile .. "'.", {
            box = "", primary = "Copy",
            validate = function(name) if not Profiles.store.saved[name] then return "Enter an existing profile name." end end,
            onAccept = function(name)
                local target = state.profile
                Profiles.store.saved[target] = UI.Clone(Profiles.store.saved[name])
                Profiles.Use(target)
                Settings.ShowSection("Profiles & Sharing")
            end,
        })
    end)
    UI.Button(body, "Delete profile", 436, 146, 210, 30, function()
        local name = state.profile
        if name == "Default" then Settings.Say("The Default profile cannot be deleted."); return end
        UI.Dialog("Delete profile", "Delete '" .. name .. "' and return its assignments to Default?", {
            primary = "Delete", onAccept = function()
                Profiles.store.saved[name] = nil
                for key, assigned in pairs(Profiles.store.characters) do
                    if assigned == name then Profiles.store.characters[key] = nil end
                end
                if Profiles.store.account == name then Profiles.store.account = "Default" end
                Profiles.Use("Default")
                Settings.ShowSection("Profiles & Sharing")
            end,
        })
    end)
    UI.Label(body, "SHARE THEMES", 0, 202, 400, 11, GOLD)
    UI.Button(body, "Export current theme...", 0, 224, 260, 30, function()
        local code = "ASHT1:" .. Sync.Codec.Encode({ name = state.theme or "Imported theme", appearance = UI.CaptureTheme() })
        UI.Dialog("Export theme", "Copy this string (Ctrl+C) and share it with friends.", { box = code })
    end)
    UI.Button(body, "Import theme...", 268, 224, 260, 30, function()
        local imported
        UI.Dialog("Import theme", "Paste a theme string (Ctrl+V).", {
            box = "", primary = "Import",
            validate = function(code)
                local ok, result = pcall(function()
                    code = code:gsub("%s+", "")
                    if code:sub(1, 6) ~= "ASHT1:" then error("Expected an ASHT1 theme string.") end
                    local packet = Sync.Codec.Decode(code:sub(7))
                    if type(packet) ~= "table" or type(packet.name) ~= "string" or packet.name == ""
                        or #packet.name > 40 or packet.name:find("[%c|]") then error("Invalid theme name.") end
                    return { name = packet.name, appearance = UI.ValidAppearance(packet.appearance) }
                end)
                if not ok then return Settings.CleanError(result) end
                imported = result
            end,
            onAccept = function()
                UI.nextThemeId = UI.nextThemeId + 1
                imported.id = UI.nextThemeId
                UI.customThemes[#UI.customThemes + 1] = imported
                UI.ApplyCustomTheme(imported)
                Settings.Persist()
                Settings.Say("Theme imported and applied.")
            end,
        })
    end)
    UI.Label(body, "Profiles and themes are local; character-data sync does not transmit settings.", 0, 274, 660, 10, MUTED)
    body.Refresh = function() active:SetText(state.profile .. " / changes save automatically") end
end

local function BuildSync(body)
    UI.Label(body, "TRUSTED CHARACTER SYNC", 0, 0, 650, 11, GOLD)
    UI.Label(body, "Both online characters must trust each other. Only account observations are exchanged; settings stay local.",
        0, 24, 650, 11, MUTED)
    local input = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
    input:SetSize(240, 28)
    input:SetPoint("TOPLEFT", 8, -72)
    input:SetAutoFocus(false)
    input:SetMaxLetters(120)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local peers = UI.Label(body, "", 0, 120, 650, 11)
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
            Settings.Say(Settings.CleanError(problem))
            print("|cffff6060Ashoholic settings:|r " .. tostring(problem))
            return
        end
        input:ClearFocus()
        RefreshPeers()
        Settings.Say("Action submitted; progress and confirmations appear in chat.")
    end
    UI.Button(body, "Trust", 250, 72, 90, 28, function() Run(Sync.Trust, input:GetText()) end)
    UI.Button(body, "Remove", 348, 72, 90, 28, function() Run(Sync.Untrust, input:GetText()) end)
    UI.Button(body, "Sync character", 446, 72, 180, 28, function() Run(Sync.Start, input:GetText()) end)
    UI.Button(body, "Sync all trusted", 0, 192, 210, 30, function() Run(Sync.StartAll) end)
    UI.Label(body, "Large snapshots take several minutes; both sides report receipt and confirmation.",
        0, 238, 650, 11, MUTED)
    UI.Label(body, "OFFLINE MERGE", 0, 298, 650, 11, GOLD)
    UI.Label(body, "Exit the game fully, run OfflineMerge.ps1, then log in to import the inbox.",
        0, 322, 650, 11, MUTED)
    local progress = UI.Label(body, "", 0, 370, 650, 10, TEAL)
    progress:SetHeight(46)
    local elapsed = 0
    body:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.5 then elapsed = 0; progress:SetText(Sync.GetStatus()) end
    end)
    body.Refresh = function() RefreshPeers(); progress:SetText(Sync.GetStatus()) end
end

local function BuildHelp(body)
    UI.Label(body, "SAVED OBSERVATIONS", 0, 0, 660, 11, GOLD)
    local text = UI.Label(body, "Unknown means no observation has been received; it is not zero.\n\n"
        .. "Torment access and Prestige are account-wide; the selected Torment is character-specific.\n\n"
        .. "Raid Available / Looted describes the last complete loot reply, not access to a raid. "
        .. "Dungeon Tracked is a planning choice, not a kill or loot record.\n\n"
        .. "Trials show last-observed personal records. Open the companion's boards to refresh them.\n\n"
        .. "Open the Call Board on each character to refresh activities and equipped item level.",
        0, 25, 650, 11)
    text:SetHeight(300)
end

Settings.sections["Roster Columns"] = { build = BuildColumns, reset = function()
    UI.SetColumnOrder(UI.DEFAULT_COLUMN_ORDER)
    state.columnWidths, state.rosterSort, state.rosterOffset = {}, {}, 0
    state.detail = UI.STATE_DEFAULTS.detail
end }
Settings.sections["Tabs & Views"] = { build = BuildTabs, reset = function()
    state.hiddenTabs, state.window = {}, UI.Clone(UI.STATE_DEFAULTS.window)
    state.openTab = "last"
end }
Settings.sections.Accounts = { build = BuildAccounts, reset = function()
    for _, account in ipairs(UI.ReadModel().accounts) do
        local config = UI.AccountConfig(account.id)
        UI.SetAccountColor(account, nil)
        UI.SetAccountCollapsed(account, false)
        if account.isCurrent and config.originalName then
            Data.SetAccountName(account.id, config.originalName)
        end
    end
end }
Settings.sections.Alerts = { build = BuildAlerts, reset = function()
    state.alerts, state.alertStyle = UI.Clone(UI.STATE_DEFAULTS.alerts), UI.STATE_DEFAULTS.alertStyle
end }
Settings.sections["Profiles & Sharing"] = { build = BuildProfiles, reset = function()
    Profiles.Use("Default")
end }
Settings.sections.Sync = { build = BuildSync, reset = function()
    for key in pairs(Data.GetTrustedPeers()) do Data.SetTrustedPeer(key, nil) end
end }
Settings.sections.Help = { build = BuildHelp }
