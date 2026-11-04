local addonName = ...
local addon = _G[addonName]

-- The preview owns only session-local sample data; it never reads or writes the roster.
-- /ash preview: Settings previews themes, colors, fonts, icons, columns, tabs, accounts, alerts and profiles.
-- Account filters, collapsed groups and layout choices survive closing, but not /reload.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"
local GOLD = { 1, 0.79, 0.39 }
local TEXT = { 0.88, 0.88, 0.90 }
local MUTED = { 0.58, 0.61, 0.67 }
local TEAL = { 0.40, 0.86, 0.78 }
local GREEN = "|cff7edba0"
local DIM = "|cff939baa"
local AMBER = "|cffffca63"
local ACCOUNTS = {
    { name = "Account One", ash = 14800000, shards = 3750, essence = 16, artisan = 28, gold = 12420, warband = 4000, prestige = 12 },
    { name = "Account Two", ash = 9200000, shards = 1350, essence = 8, artisan = 14, gold = 6850, warband = 2200, prestige = 7 },
    { name = "Account Three", ash = 18200000, shards = 4500, essence = 22, artisan = 19, gold = 9600, warband = 3100, prestige = 18 },
    { name = "Account Four", ash = 6400000, shards = 900, essence = 4, artisan = 32, gold = 5100, warband = 1800, prestige = 4 },
}
local CHARACTERS = {
    { name = "Aster", account = 1, class = "PALADIN", level = 80, ilvl = 226, tier = 6, runAsh = "284k", runShards = 145, gold = "7,200g", seen = "Just now", location = "Dalaran", action = "2 rewards to claim", offerings = "3 / 5", bonus = "+35%", build = "Dawnkeeper", anchor = "Dalaran", progress = 7 },
    { name = "Cinder", account = 1, class = "MAGE", level = 80, ilvl = 213, tier = 4, runAsh = "96k", runShards = 60, gold = "3,480g", seen = "2 hours ago", location = "Karazhan", action = "Nightbane loot available", offerings = "4 / 5", bonus = "+15%", build = "Living Flame", anchor = "Deadwind Pass", progress = 3 },
    { name = "Thorn", account = 1, class = "DRUID", level = 64, ilvl = 118, tier = 1, runAsh = "38k", runShards = 12, gold = "1,740g", seen = "Yesterday", location = "Nagrand", action = "Continue leveling", offerings = "5 / 5", bonus = "+10%", build = "Wildheart", anchor = "Nagrand", progress = 0 },
    { name = "Vesper", account = 2, class = "WARLOCK", level = 80, ilvl = 232, tier = 8, runAsh = "410k", runShards = 210, gold = "4,900g", seen = "35 min ago", location = "Icecrown", action = "Cache nearly ready", offerings = "2 / 5", bonus = "+50%", build = "Void Chorus", anchor = "Icecrown", progress = 9 },
    { name = "Rook", account = 2, class = "WARRIOR", level = 80, ilvl = 200, tier = 2, runAsh = "Unknown", runShards = nil, gold = "1,950g", seen = "8 days ago", location = "Stormwind", action = "Refresh stale snapshot", offerings = "Unknown", bonus = "Unknown", build = "Ironbound", anchor = "Unknown", progress = 2, stale = true },
}
for i, sample in ipairs({
    { "Ember", "SHAMAN", 1 }, { "Lumen", "PRIEST", 1 },
    { "Flint", "HUNTER", 2 }, { "Shade", "ROGUE", 2 },
    { "Briar", "DRUID", 3 }, { "Sol", "PALADIN", 3 }, { "Nyx", "MAGE", 3 },
    { "Ashen", "DEATHKNIGHT", 3 }, { "Gale", "SHAMAN", 4 },
    { "Rune", "WARLOCK", 4 }, { "Vale", "PRIEST", 4 }, { "Steel", "WARRIOR", 4 },
}) do
    CHARACTERS[#CHARACTERS + 1] = {
        name = sample[1], class = sample[2], account = sample[3], level = 80, ilvl = 200 + i,
        runAsh = (40 + i * 12) .. "k", runShards = 25 + i * 8, gold = "Sample",
        seen = "Today", location = "Dalaran", action = "Sample character snapshot",
        offerings = "4 / 5", bonus = "+20%", build = "Build " .. i, anchor = "Dalaran",
    }
end
for i, account in ipairs(ACCOUNTS) do
    account.originalName = account.name
    account.tier = ({ 6, 8, 10, 3 })[i]
end

local frame
local state = {
    accounts = { [1] = true }, selected = 1, tab = "Roster", watched = {}, expanded = {}, collapsed = {},
    matrixOffset = 0, detail = true, font = FONT, fontDelta = 0, density = "comfortable",
    iconStyle = "icons", classIcons = true, statusStyle = "words", hiddenTabs = {}, defaultTab = "Roster",
    logo = "Interface\\Icons\\inv_soulash", scale = 1, opacity = 1,
}
-- Mutated in place by the theme preview so every widget sharing them follows the theme.
local PANEL = { 0.075, 0.083, 0.105, 1 }
local BORDER = { 0.19, 0.21, 0.26, 1 }
local BUTTON_BG = { 0.10, 0.115, 0.145, 1 }
local BUTTON_BORDER = { 0.24, 0.26, 0.31, 1 }
local BACKGROUND = { 0.035, 0.042, 0.058, 0.99 }
local surfaces, buttons, labels = {}, {}, {}
local settings, accountMenu
local ShowSettings
local columns = {
    { key = "level", title = "Level" }, { key = "ilvl", title = "Item level" },
    { key = "runAsh", title = "Run Ash" }, { key = "runShards", title = "Run Shards" },
    { key = "gold", title = "Gold" }, { key = "seen", title = "Last seen" },
    { key = "bonus", title = "Offering bonus" }, { key = "offerings", title = "Offerings left" },
    { key = "build", title = "Echo build" }, { key = "anchor", title = "Soul anchor" },
    { key = "location", title = "Location" },
}
local columnOrder = { "level", "ilvl", "runAsh", "runShards", "gold", "seen" }
local raids = {}
local trackingTree = {}
local RAID_EXPANSIONS = {
    [409] = 1, [469] = 1, [309] = 1, [509] = 1, [531] = 1,
    [532] = 2, [565] = 2, [544] = 2, [548] = 2, [550] = 2,
    [568] = 2, [534] = 2, [564] = 2, [580] = 2,
    [533] = 3, [616] = 3, [615] = 3, [603] = 3, [649] = 3,
    [249] = 3, [631] = 3, [724] = 3, [624] = 3,
}
-- Preview-only dungeon catalogue; these keys are not server encounter IDs.
local DUNGEONS = {
    { 3, "Utgarde Keep", "Prince Keleseth;Skarvald & Dalronn;Ingvar the Plunderer" },
    { 3, "The Nexus", "Commander Stoutbeard / Commander Kolurg;Grand Magus Telestra;Anomalus;Ormorok the Tree-Shaper;Keristrasza" },
    { 3, "Azjol-Nerub", "Krik'thir the Gatewatcher;Hadronox;Anub'arak" },
    { 3, "Ahn'kahet: The Old Kingdom", "Elder Nadox;Prince Taldaram;Jedoga Shadowseeker;Amanitar;Herald Volazj" },
    { 3, "Drak'Tharon Keep", "Trollgore;Novos the Summoner;King Dred;The Prophet Tharon'ja" },
    { 3, "The Violet Hold", "Erekem;Moragg;Ichoron;Xevozz;Lavanthor;Zuramat the Obliterator;Cyanigosa" },
    { 3, "Gundrak", "Slad'ran;Drakkari Colossus;Moorabi;Eck the Ferocious;Gal'darah" },
    { 3, "Halls of Stone", "Krystallus;Maiden of Grief;Tribunal of Ages;Sjonnir the Ironshaper" },
    { 3, "Halls of Lightning", "General Bjarngrim;Volkhan;Ionar;Loken" },
    { 3, "The Oculus", "Drakos the Interrogator;Varos Cloudstrider;Mage-Lord Urom;Ley-Guardian Eregos" },
    { 3, "Utgarde Pinnacle", "Svala Sorrowgrave;Gortok Palehoof;Skadi the Ruthless;King Ymiron" },
    { 3, "The Culling of Stratholme", "Meathook;Salramm the Fleshcrafter;Chrono-Lord Epoch;Infinite Corruptor;Mal'Ganis" },
    { 3, "Trial of the Champion", "Grand Champions;Eadric the Pure / Argent Confessor Paletress;The Black Knight" },
    { 3, "The Forge of Souls", "Bronjahm;Devourer of Souls" },
    { 3, "Pit of Saron", "Forgemaster Garfrost;Ick & Krick;Scourgelord Tyrannus" },
    { 3, "Halls of Reflection", "Falric;Marwyn;Escape from the Lich King" },
    { 2, "Hellfire Ramparts", "Watchkeeper Gargolmar;Omor the Unscarred;Vazruden the Herald" },
    { 2, "The Blood Furnace", "The Maker;Broggok;Keli'dan the Breaker" },
    { 2, "The Shattered Halls", "Grand Warlock Nethekurse;Blood Guard Porung;Warbringer O'mrogg;Warchief Kargath Bladefist" },
    { 2, "The Slave Pens", "Mennu the Betrayer;Rokmar the Crackler;Quagmirran" },
    { 2, "The Underbog", "Hungarfen;Ghaz'an;Swamplord Musel'ek;The Black Stalker" },
    { 2, "The Steamvault", "Hydromancer Thespia;Mekgineer Steamrigger;Warlord Kalithresh" },
    { 2, "Mana-Tombs", "Pandemonius;Tavarok;Yor;Nexus-Prince Shaffar" },
    { 2, "Auchenai Crypts", "Shirrak the Dead Watcher;Exarch Maladaar" },
    { 2, "Sethekk Halls", "Darkweaver Syth;Anzu;Talon King Ikiss" },
    { 2, "Shadow Labyrinth", "Ambassador Hellmaw;Blackheart the Inciter;Grandmaster Vorpil;Murmur" },
    { 2, "Old Hillsbrad Foothills", "Lieutenant Drake;Captain Skarloc;Epoch Hunter" },
    { 2, "The Black Morass", "Chrono Lord Deja;Temporus;Aeonus" },
    { 2, "The Mechanar", "Gatewatcher Gyro-Kill;Gatewatcher Iron-Hand;Mechano-Lord Capacitus;Nethermancer Sepethrea;Pathaleon the Calculator" },
    { 2, "The Botanica", "Commander Sarannis;High Botanist Freywinn;Thorngrin the Tender;Laj;Warp Splinter" },
    { 2, "The Arcatraz", "Zereketh the Unbound;Dalliah the Doomsayer;Wrath-Scryer Soccothrates;Harbinger Skyriss" },
    { 2, "Magisters' Terrace", "Selin Fireheart;Vexallus;Priestess Delrissa;Kael'thas Sunstrider" },
    { 1, "Ragefire Chasm", "Oggleflint;Taragaman the Hungerer;Jergosh the Invoker;Bazzalan" },
    { 1, "The Deadmines", "Rhahk'zor;Sneed;Gilnid;Mr. Smite;Cookie;Captain Greenskin;Edwin VanCleef" },
    { 1, "Wailing Caverns", "Lady Anacondra;Lord Cobrahn;Kresh;Lord Pythas;Skum;Lord Serpentis;Verdan the Everliving;Mutanus the Devourer" },
    { 1, "Shadowfang Keep", "Rethilgore;Razorclaw the Butcher;Baron Silverlaine;Commander Springvale;Odo the Blindwatcher;Fenrus the Devourer;Wolf Master Nandos;Archmage Arugal" },
    { 1, "Blackfathom Deeps", "Ghamoo-ra;Lady Sarevess;Gelihast;Lorgus Jett;Old Serra'kis;Twilight Lord Kelris;Aku'mai" },
    { 1, "The Stockade", "Targorr the Dread;Kam Deepfury;Hamhock;Bazil Thredd" },
    { 1, "Gnomeregan", "Viscous Fallout;Grubbis;Electrocutioner 6000;Crowd Pummeler 9-60;Mekgineer Thermaplugg" },
    { 1, "Razorfen Kraul", "Roogug;Aggem Thorncurse;Death Speaker Jargba;Overlord Ramtusk;Agathelos the Raging;Charlga Razorflank" },
    { 1, "Scarlet Monastery", "Interrogator Vishas;Bloodmage Thalnos;Houndmaster Loksey;Arcanist Doan;Herod;High Inquisitor Fairbanks;High Inquisitor Whitemane" },
    { 1, "Razorfen Downs", "Tuten'kash;Mordresh Fire Eye;Glutton;Amnennar the Coldbringer" },
    { 1, "Uldaman", "Revelosh;The Lost Dwarves;Ironaya;Obsidian Sentinel;Ancient Stone Keeper;Galgann Firehammer;Grimlok;Archaedas" },
    { 1, "Zul'Farrak", "Hydromancer Velratha;Gahz'rilla;Antu'sul;Theka the Martyr;Witch Doctor Zum'rah;Nekrum & Sezz'ziz;Chief Ukorz Sandscalp" },
    { 1, "Maraudon", "Noxxion;Razorlash;Lord Vyletongue;Celebras the Cursed;Landslide;Tinkerer Gizlock;Rotgrip;Princess Theradras" },
    { 1, "The Temple of Atal'Hakkar", "Atal'alarion;Dreamscythe;Weaver;Jammal'an the Prophet;Morphaz;Hazzas;Avatar of Hakkar;Shade of Eranikus" },
    { 1, "Blackrock Depths", "High Interrogator Gerstahn;Lord Roccor;Houndmaster Grebmar;Ring of Law;Pyromancer Loregrain;Lord Incendius;Warder Stilgiss;Fineous Darkvire;Bael'Gar;General Angerforge;Golem Lord Argelmach;Hurley Blackbreath;Phalanx;Ribbly Screwspigot;Plugger Spazzring;Ambassador Flamelash;The Seven;Magmus;Emperor Dagran Thaurissan" },
    { 1, "Lower Blackrock Spire", "Highlord Omokk;Shadow Hunter Vosh'gajin;War Master Voone;Mother Smolderweb;Urok Doomhowl;Quartermaster Zigris;Gizrul the Slavener;Halycon;Overlord Wyrmthalak" },
    { 1, "Upper Blackrock Spire", "Pyroguard Emberseer;Solakar Flamewreath;Warchief Rend Blackhand;The Beast;General Drakkisath" },
    { 1, "Dire Maul", "Zevrim Thornhoof;Hydrospawn;Lethtendris;Alzzin the Wildshaper;Illyanna Ravenoak;Magister Kalendris;Immol'thar;Tendris Warpwood;Prince Tortheldrin;Guard Mol'dar;Stomper Kreeg;Guard Fengus;Guard Slip'kik;Captain Kromcrush;Cho'Rush the Observer;King Gordok" },
    { 1, "Scholomance", "Kirtonos the Herald;Jandice Barov;Rattlegore;Marduk Blackpool;Vectus;Ras Frostwhisper;Instructor Malicia;Doctor Theolen Krastinov;Lorekeeper Polkelt;The Ravenian;Lord Alexei Barov;Lady Illucia Barov;Darkmaster Gandling" },
    { 1, "Stratholme", "The Unforgiven;Hearthsinger Forresten;Timmy the Cruel;Cannon Master Willey;Malor the Zealous;Archivist Galford;Balnazzar;Baroness Anastari;Nerub'enkan;Maleki the Pallid;Magistrate Barthilas;Ramstein the Gorger;Baron Rivendare" },
}
local pages, tabs, cards = {}, {}, {}
local refresh

local function SetVisible(widget, visible)
    if visible then widget:Show() else widget:Hide() end
end

local function Label(parent, text, x, y, width, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(state.font, math.max(8, (size or 12) + state.fontDelta))
    labels[#labels + 1] = { fs, color or TEXT, size or 12 }
    fs:SetPoint("TOPLEFT", x, -y)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetTextColor(unpack(color or TEXT))
    fs:SetText(text)
    return fs
end

local function Surface(parent, x, y, width, height, color)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", x, -y)
    panel:SetSize(width, height)
    panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    panel:SetBackdropColor(unpack(color or PANEL))
    panel:SetBackdropBorderColor(unpack(BORDER))
    surfaces[#surfaces + 1] = { panel, color == nil }
    return panel
end

local function Button(parent, text, x, y, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", x, -y)
    button:SetSize(width, height or 28)
    button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    button:SetBackdropColor(unpack(BUTTON_BG))
    button:SetBackdropBorderColor(unpack(BUTTON_BORDER))
    buttons[#buttons + 1] = button
    button:SetHighlightTexture(WHITE)
    button:GetHighlightTexture():SetVertexColor(1, 0.8, 0.4, 0.09)
    button.text = Label(button, text, 9, 7, width - 18, 11)
    button.text:SetHeight(14)
    if button.text.SetWordWrap then button.text:SetWordWrap(false) end
    button:SetScript("OnClick", onClick)
    return button
end

local function Tip(widget, title, body)
    widget:EnableMouse(true)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, unpack(GOLD))
        GameTooltip:AddLine(body, 0.85, 0.87, 0.9, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Scroll(parent, name, x, y, width, height)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", x, -y)
    scroll:SetSize(width - 26, height)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width - 26, height)
    scroll:SetScrollChild(child)
    return scroll, child
end

local function Progress(parent, x, y, width, value, total)
    local track = parent:CreateTexture(nil, "ARTWORK")
    track:SetTexture(WHITE)
    track:SetPoint("TOPLEFT", x, -y)
    track:SetSize(width, 5)
    track:SetVertexColor(0.16, 0.18, 0.22, 1)
    local fill = parent:CreateTexture(nil, "OVERLAY")
    fill:SetTexture(WHITE)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT")
    fill:SetSize(math.max(1, width * math.min(1, value / total)), 5)
    fill:SetVertexColor(unpack(TEAL))
end

local function VisibleCharacters()
    local result = {}
    for i, character in ipairs(CHARACTERS) do
        if state.accounts[character.account] then
            result[#result + 1] = { index = i, data = character }
        end
    end
    return result
end

local function ClassName(character)
    local color = RAID_CLASS_COLORS[character.class]
    local icon = ""
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[character.class]
    if state.classIcons and coords then
        icon = string.format("|TInterface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes:14:14:0:0:256:256:%d:%d:%d:%d|t ",
            coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
    end
    return string.format("%s|cff%02x%02x%02x%s|r", icon, color.r * 255, color.g * 255, color.b * 255, character.name)
end

local function ScrollBy(scroll, delta)
    local bar = _G[scroll:GetName() .. "ScrollBar"]
    if bar then bar:SetValue(bar:GetValue() - delta * 30) end
end

local function Short(n)
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 1000 then return string.format("%.2fk", n / 1000) end
    return tostring(n)
end

local function Page(name, heading, subtitle)
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", 24, -252)
    page:SetSize(1072, 420)
    Label(page, heading, 0, 0, 720, 17, GOLD)
    Label(page, subtitle, 0, 27, 1072, 11, MUTED)
    pages[name] = page
    return page
end

local function DetailLine(parent, title, value, y)
    Label(parent, title, 16, y, 168, 11, MUTED)
    local fs = Label(parent, value, 184, y, parent:GetWidth() - 200, 11)
    fs:SetJustifyH("RIGHT")
    return fs
end

local function BuildRoster()
    local page = Page("Roster", "Your next adventure", "Characters first. Shared currencies stay at account level; run earnings stay with the character.")
    page.headers = {}
    for i = 1, 7 do page.headers[i] = Label(page, "", 0, 61, 100, 10, MUTED) end
    local scroll, body = Scroll(page, "AshoholicPreviewRosterScroll", 0, 84, 716, 290)
    page.rows = {}
    for i, character in ipairs(CHARACTERS) do
        local index = i
        local row = Button(body, "", 0, 0, 690, 44, function()
            state.selected = index
            refresh()
        end)
        row.cells = {}
        for j = 1, 7 do
            row.cells[j] = Label(row, "", 0, 8, 85, 11)
            row.cells[j]:SetHeight(14)
            if row.cells[j].SetWordWrap then row.cells[j]:SetWordWrap(false) end
        end
        row.hint = Label(row, "", 12, 27, 680, 10, MUTED)
        page.rows[i] = row
    end
    page.accountLabels = {}
    for i = 1, #ACCOUNTS do
        local id = i
        page.accountLabels[i] = Button(body, "", 0, 0, 690, 25, function()
            state.collapsed[id] = not state.collapsed[id]
            refresh()
        end)
    end
    local detail = Surface(page, 740, 56, 332, 354)
    page.detailTitle = Label(detail, "", 16, 16, 300, 17)
    page.detailLocation = Label(detail, "", 16, 42, 300, 11, MUTED)
    Label(detail, "PARKED RUN", 16, 75, 300, 10, GOLD)
    page.detailValues = {}
    local labels = { "Run Soul Ash", "Run Soul Shards", "Offering bonus", "Offerings remaining", "Echo build", "Soul anchor" }
    for i, title in ipairs(labels) do
        page.detailValues[i] = DetailLine(detail, title, "", 101 + (i - 1) * 28)
    end
    page.detailNote = Label(detail, "", 16, 278, 300, 11, TEAL)
    Button(detail, "Customize columns / detail panel", 16, 317, 300, 25, function() ShowSettings("Roster Columns") end)
    Label(page, "No hourly-entry counter: the new realm's cap has not been established.", 0, 391, 716, 10, MUTED)
    page.Refresh = function()
        local width = state.detail and 690 or 1046
        scroll:SetWidth(width)
        body:SetWidth(width)
        SetVisible(detail, state.detail and state.accounts[CHARACTERS[state.selected].account])
        local cellWidth = (width - 160) / math.max(1, #columnOrder)
        local function PositionCell(fs, j, y)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", j == 1 and 10 or 160 + (j - 2) * cellWidth, -y)
            fs:SetWidth(j == 1 and 145 or cellWidth - 6)
            SetVisible(fs, j <= #columnOrder + 1)
        end
        for j, fs in ipairs(page.headers) do
            PositionCell(fs, j, 61)
            local key = columnOrder[j - 1]
            local title = "CHARACTER"
            for _, column in ipairs(columns) do if column.key == key then title = column.title end end
            fs:SetText(title)
        end
        local y = 0
        for accountId, account in ipairs(ACCOUNTS) do
            local accountLabel = page.accountLabels[accountId]
            local show = state.accounts[accountId]
            SetVisible(accountLabel, show)
            if show then
                accountLabel:ClearAllPoints()
                accountLabel:SetPoint("TOPLEFT", 0, -y)
                accountLabel:SetWidth(width)
                accountLabel.text:SetWidth(width - 18)
                accountLabel.text:SetText((state.collapsed[accountId] and "+ " or "- ") .. account.name .. (accountId == 1 and "  /  Current account" or ""))
                accountLabel.text:SetTextColor(unpack(account.color or TEXT))
                y = y + 28
            end
            local rowHeight = state.density == "compact" and 30 or (state.density == "spacious" and 54 or 44)
            for i, character in ipairs(CHARACTERS) do
                if character.account == accountId then
                    local row = page.rows[i]
                    SetVisible(row, show and not state.collapsed[accountId])
                    if show and not state.collapsed[accountId] then
                        row:SetWidth(width)
                        row:SetHeight(rowHeight)
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", 0, -y)
                        row:SetBackdropBorderColor(unpack(i == state.selected and GOLD or BORDER))
                        for j, fs in ipairs(row.cells) do
                            PositionCell(fs, j, state.density == "spacious" and 11 or 8)
                            fs:SetText(j == 1 and ClassName(character) or tostring(character[columnOrder[j - 1]] or "Unknown"))
                        end
                        row.hint:SetText(character.action)
                        SetVisible(row.hint, state.density ~= "compact")
                        y = y + rowHeight + 3
                    end
                end
            end
        end
        body:SetHeight(math.max(290, y))
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, y - 290)))
        local character = CHARACTERS[state.selected]
        page.detailTitle:SetText(ClassName(character))
        page.detailLocation:SetText(character.location .. "  /  " .. character.seen)
        local values = { character.runAsh, character.runShards and tostring(character.runShards) or "Unknown", character.bonus, character.offerings, character.build, character.anchor }
        for i, value in ipairs(values) do page.detailValues[i]:SetText(value) end
        page.detailNote:SetText(character.stale and "Stale snapshot. Unknown is not zero; log in to refresh." or "Sample reminder: bank this run at a Spirit Healer to collect its offering bonus.")
    end
end

local function WatchedCount(raid)
    local n = 0
    for _, boss in ipairs(raid.bosses) do
        if state.watched[boss.id] then n = n + 1 end
    end
    return n
end

local function LootStatus(character, boss, index, instance)
    local icons = state.statusStyle == "icons"
    if character.stale then return icons and "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t" or DIM .. "Unknown|r" end
    if instance.kind == "Dungeons" then return "|cff6edbc7Tracked|r" end
    if character.level < 80 then return DIM .. (icons and "-" or "Not ready") .. "|r" end
    if (boss.id + index) % 3 == 0 then return icons and "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t" or DIM .. "Looted|r" end
    return icons and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t" or GREEN .. "Available|r"
end

local MATRIX_COLUMNS, MATRIX_WIDTH, MATRIX_FIRST, MATRIX_HEIGHT = 5, 95, 210, 226

local function BuildRaids()
    local page = Page("Raids", "Raid & dungeon watchlist", "Select a category, expansion, instance or individual boss. All statuses are sample data.")
    Label(page, "WATCHED ENCOUNTERS", 0, 61, 360, 10, GOLD)
    local matrixScroll, matrix = Scroll(page, "AshoholicPreviewRaidMatrix", 0, 135, 716, MATRIX_HEIGHT)
    local header = Surface(page, 0, 84, 690, 47)
    Label(header, "ENCOUNTER", 7, 26, 198, 10, MUTED)
    local headerCells = {}
    for i = 1, MATRIX_COLUMNS do
        headerCells[i] = {
            account = Label(header, "", MATRIX_FIRST + (i - 1) * MATRIX_WIDTH, 6, MATRIX_WIDTH - 6, 9, GOLD),
            name = Label(header, "", MATRIX_FIRST + (i - 1) * MATRIX_WIDTH, 26, MATRIX_WIDTH - 6, 11),
        }
        for _, fs in pairs(headerCells[i]) do
            fs:SetHeight(14)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
        end
    end
    -- Separators sit on an overlay so row backgrounds cannot cover them.
    local overlay = CreateFrame("Frame", nil, matrix)
    overlay:SetAllPoints(matrix)
    overlay:SetFrameLevel(matrix:GetFrameLevel() + 10)
    local separators = {}
    for i = 1, MATRIX_COLUMNS do
        local x = MATRIX_FIRST + i * MATRIX_WIDTH - 6
        local head = header:CreateTexture(nil, "OVERLAY")
        head:SetTexture(WHITE)
        head:SetPoint("TOPLEFT", x, -4)
        head:SetSize(2, 39)
        local body = overlay:CreateTexture(nil, "OVERLAY")
        body:SetTexture(WHITE)
        body:SetPoint("TOPLEFT", x, 0)
        body:SetPoint("BOTTOMLEFT", x, 0)
        body:SetWidth(2)
        separators[i] = { head, body }
    end
    local hint = Label(page, "Shift + mouse wheel: scroll characters", 0, 370, 205, 9, MUTED)
    local hbar = CreateFrame("Slider", nil, page)
    hbar:SetPoint("TOPLEFT", MATRIX_FIRST, -368)
    hbar:SetSize(MATRIX_COLUMNS * MATRIX_WIDTH - 6, 12)
    hbar:SetOrientation("HORIZONTAL")
    hbar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    hbar:SetBackdropColor(0.10, 0.11, 0.14, 1)
    hbar:SetBackdropBorderColor(unpack(BORDER))
    hbar:SetThumbTexture(WHITE)
    hbar:GetThumbTexture():SetSize(70, 10)
    hbar:SetValueStep(1)
    hbar:SetMinMaxValues(0, 0)
    hbar:SetValue(0)
    local position = Label(page, "", MATRIX_FIRST + MATRIX_COLUMNS * MATRIX_WIDTH + 6, 370, 120, 9, MUTED)
    local function ScrollCharacters(delta)
        local maxOffset = math.max(0, #VisibleCharacters() - MATRIX_COLUMNS)
        local value = math.max(0, math.min(maxOffset, state.matrixOffset - delta))
        if value ~= state.matrixOffset then
            state.matrixOffset = value
            page.Refresh()
        end
    end
    hbar:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= state.matrixOffset then
            state.matrixOffset = value
            page.Refresh()
        end
    end)
    matrixScroll:EnableMouseWheel(true)
    matrixScroll:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown() then ScrollCharacters(delta) else ScrollBy(self, delta) end
    end)
    for _, widget in ipairs({ header, hbar }) do
        widget:EnableMouseWheel(true)
        widget:SetScript("OnMouseWheel", function(_, delta) ScrollCharacters(delta) end)
    end
    Tip(header, "Watched characters", "Shift + mouse wheel scrolls sideways. Gold lines separate accounts; the account name appears once above its first visible character.")
    local pickerScroll, picker = Scroll(page, "AshoholicPreviewRaidPicker", 740, 127, 332, 251)
    page.matrixRows, page.pickerRows = {}, {}
    local function MatrixRow(i)
        local row = page.matrixRows[i]
        if not row then
            row = Surface(matrix, 0, 0, 690, 25)
            row.name = Label(row, "", 7, 7, 198, 10)
            row.name:SetHeight(13)
            if row.name.SetWordWrap then row.name:SetWordWrap(false) end
            row.cells = {}
            for j = 1, MATRIX_COLUMNS do
                row.cells[j] = Label(row, "", MATRIX_FIRST + (j - 1) * MATRIX_WIDTH, 7, MATRIX_WIDTH - 8, 10)
            end
            page.matrixRows[i] = row
        end
        return row
    end
    Label(page, "TRACKING SELECTION", 740, 61, 332, 10, GOLD)
    Button(page, "Watch all", 740, 84, 105, 28, function()
        for _, raid in ipairs(raids) do
            for _, boss in ipairs(raid.bosses) do state.watched[boss.id] = true end
        end
        page.Refresh()
    end)
    Button(page, "Clear", 852, 84, 82, 28, function()
        wipe(state.watched)
        page.Refresh()
    end)
    Label(page, "+ expands groups", 944, 92, 128, 10, MUTED)
    page.empty = Label(matrix, "Nothing selected. Choose instances or bosses on the right.", 8, 12, 670, 12, MUTED)
    local function BuildNode(node, depth, ancestors)
        local row = CreateFrame("Frame", nil, picker)
        row:SetSize(306 - depth * 14, 28)
        row.expand = Button(row, "+", 0, 0, 26, 25, function()
            state.expanded[node.key] = not state.expanded[node.key]
            page.Refresh()
        end)
        row.select = Button(row, "", 30, 0, 276 - depth * 14, 25, function()
            local selected = WatchedCount(node) < #node.bosses
            for _, boss in ipairs(node.bosses) do state.watched[boss.id] = selected end
            page.Refresh()
        end)
        page.pickerRows[#page.pickerRows + 1] = { widget = row, data = node, depth = depth, ancestors = ancestors }
        local childAncestors = {}
        for i, key in ipairs(ancestors) do childAncestors[i] = key end
        childAncestors[#childAncestors + 1] = node.key
        if node.children then
            for _, child in ipairs(node.children) do BuildNode(child, depth + 1, childAncestors) end
        else
            for _, boss in ipairs(node.bosses) do
                local bossData = boss
                local button = Button(picker, "", 0, 0, 306 - (depth + 1) * 14, 23, function()
                    state.watched[bossData.id] = not state.watched[bossData.id]
                    page.Refresh()
                end)
                Tip(button, boss.name, "Toggle tracking this boss. Preview only; selections are not saved.")
                page.pickerRows[#page.pickerRows + 1] = { widget = button, data = boss, depth = depth + 1, ancestors = childAncestors, leaf = true }
            end
        end
    end
    for _, category in ipairs(trackingTree) do BuildNode(category, 0, {}) end
    Label(page, "Raids: sample weekly loot status. Dungeons: tracking only; no weekly loot lockout is assumed.", 0, 394, 1072, 10, MUTED)
    page.Refresh = function()
        local y, rowIndex = 0, 0
        local allCharacters = VisibleCharacters()
        local maxOffset = math.max(0, #allCharacters - MATRIX_COLUMNS)
        state.matrixOffset = math.min(state.matrixOffset, maxOffset)
        local characters = {}
        for i = 1, MATRIX_COLUMNS do characters[i] = allCharacters[state.matrixOffset + i] end
        for i = 1, MATRIX_COLUMNS do
            local character = characters[i]
            local cells = headerCells[i]
            cells.name:SetText(character and ClassName(character.data) or "")
            cells.account:SetText("")
            local previous = i > 1 and characters[i - 1] or allCharacters[state.matrixOffset]
            if character and (i == 1 or character.data.account ~= characters[i - 1].data.account) then
                local span = 1
                while characters[i + span] and characters[i + span].data.account == character.data.account do span = span + 1 end
                local account = ACCOUNTS[character.data.account]
                local continued = previous and previous.data.account == character.data.account
                cells.account:SetWidth(span * MATRIX_WIDTH - 10)
                cells.account:SetText((continued and "< " or "") .. string.upper(account.name))
                cells.account:SetTextColor(unpack(account.color or GOLD))
            end
            local nextCharacter = allCharacters[state.matrixOffset + i + 1]
            local split = character and nextCharacter and nextCharacter.data.account ~= character.data.account
            for _, texture in ipairs(separators[i]) do
                texture:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
                SetVisible(texture, split)
            end
        end
        hbar:SetMinMaxValues(0, maxOffset)
        hbar:SetValue(state.matrixOffset)
        hbar:GetThumbTexture():SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.75)
        SetVisible(hbar, maxOffset > 0)
        position:SetText(#allCharacters == 0 and "" or string.format("%d-%d of %d", state.matrixOffset + 1, math.min(#allCharacters, state.matrixOffset + MATRIX_COLUMNS), #allCharacters))
        local function AddRow(name, boss, instance)
            rowIndex = rowIndex + 1
            local row = MatrixRow(rowIndex)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row.name:SetText(name)
            Tip(row, boss and boss.name or name, instance and instance.kind == "Dungeons"
                and "Dungeon watchlist only. Tracked does not imply a weekly lockout or a recorded kill."
                or "Sample raid loot eligibility. Looted does not prevent entry. Unknown needs a fresh snapshot.")
            for i, cell in ipairs(row.cells) do
                local character = characters[i]
                cell:SetText(character and boss and LootStatus(character.data, boss, character.index, instance) or "")
            end
            row:Show()
            y = y + 28
        end
        for _, category in ipairs(trackingTree) do
            if WatchedCount(category) > 0 then
                for _, expansion in ipairs(category.children) do
                    if WatchedCount(expansion) > 0 then
                        for _, instance in ipairs(expansion.children) do
                            if WatchedCount(instance) > 0 then
                                AddRow(AMBER .. instance.name .. "|r", nil, instance)
                                for _, boss in ipairs(instance.bosses) do
                                    if state.watched[boss.id] then AddRow(boss.name, boss, instance) end
                                end
                                y = y + 8
                            end
                        end
                    end
                end
            end
        end
        for i = rowIndex + 1, #page.matrixRows do page.matrixRows[i]:Hide() end
        SetVisible(page.empty, rowIndex == 0)
        matrix:SetHeight(math.max(MATRIX_HEIGHT, y))
        matrixScroll:SetVerticalScroll(math.min(matrixScroll:GetVerticalScroll(), math.max(0, y - MATRIX_HEIGHT)))
        y = 0
        for _, entry in ipairs(page.pickerRows) do
            local row, node = entry.widget, entry.data
            local visible = true
            for _, key in ipairs(entry.ancestors) do
                if not state.expanded[key] then visible = false; break end
            end
            SetVisible(row, visible)
            if visible then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", entry.depth * 14, -y)
                if entry.leaf then
                    row.text:SetText((state.watched[node.id] and "[x] " or "[ ] ") .. node.name)
                else
                    local count = WatchedCount(node)
                    row.expand.text:SetText(state.expanded[node.key] and "-" or "+")
                    row.select.text:SetText((count == 0 and "[ ] " or (count == #node.bosses and "[x] " or "[-] ")) .. node.name)
                    Tip(row.select, node.name, count .. " / " .. #node.bosses .. " bosses watched. Click to toggle this entire group.")
                end
                y = y + (entry.leaf and 25 or 28)
            end
        end
        picker:SetHeight(math.max(251, y))
        pickerScroll:SetVerticalScroll(math.min(pickerScroll:GetVerticalScroll(), math.max(0, y - 251)))
    end
end

local function BuildActivities()
    local page = Page("Activities", "Rewards worth coming back for", "Daily and weekly Call Board activities are separate from the current run's Death contract.")
    local scroll, body = Scroll(page, "AshoholicPreviewActivityScroll", 0, 57, 1072, 345)
    local panels = {}
    for accountId, account in ipairs(ACCOUNTS) do
        local panel = Surface(body, 0, 0, 510, 345)
        panel.title = Label(panel, account.name, 16, 17, 478, 16, GOLD)
        Label(panel, "CALL BOARD CACHE", 16, 51, 490, 10, MUTED)
        Label(panel, accountId == 1 and "7 / 10 progress" or "9 / 10 progress", 16, 73, 490, 21, TEAL)
        Progress(panel, 16, 106, 490, accountId == 1 and 7 or 9, 10)
        Label(panel, "UNCLAIMED & IN PROGRESS", 16, 132, 490, 10, GOLD)
        local rows = accountId == 1 and {
            { "Aster / Daily dungeon", GREEN .. "Ready to claim|r", "Character activity  /  Ash + Shards + gold" },
            { "Account / Crafting contract", GREEN .. "Ready to claim|r", "Shared activity  /  1 Artisan Soul" },
            { "Cinder / Weekly raid", "8 / 11 bosses", "Character activity  /  Shards" },
        } or {
            { "Character / Open World daily", GREEN .. "Ready to claim|r", "Character activity  /  Ash + gold" },
            { "Account / Crafting contract", "2 / 3 objectives", "Shared activity  /  1 Artisan Soul" },
            { "Character / Weekly activities", DIM .. "Unknown|r", "Snapshot predates this reset; refresh needed" },
        }
        for i, row in ipairs(rows) do
            local y = 159 + (i - 1) * 56
            Label(panel, row[1], 16, y, 320, 12)
            local status = Label(panel, row[2], 330, y, 176, 11, TEAL)
            status:SetJustifyH("RIGHT")
            Label(panel, row[3], 16, y + 23, 490, 10, MUTED)
        end
        panels[accountId] = panel
    end
    Label(page, "Sample reset timers: Daily 08h 42m  /  Weekly 3d 08h. Shared activities count once per account.", 0, 411, 1072, 10, MUTED)
    page.Refresh = function()
        local count = 0
        for accountId, panel in ipairs(panels) do
            local visible = state.accounts[accountId]
            SetVisible(panel, visible)
            if visible then
                panel:ClearAllPoints()
                panel.title:SetText(ACCOUNTS[accountId].name)
                panel:SetPoint("TOPLEFT", (count % 2) * 530, -math.floor(count / 2) * 360)
                count = count + 1
            end
        end
        local height = math.max(345, math.ceil(count / 2) * 360)
        body:SetHeight(height)
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), height - 345))
    end
end

local function BuildProgression()
    local page = Page("Progression", "Torment & Prestige", "Account-wide Torment access (the new Hardcore ladder), alongside account Prestige readiness.")
    local ladder = Surface(page, 0, 57, 510, 345)
    Label(ladder, "ACCOUNT TORMENT UNLOCKS", 16, 17, 478, 11, GOLD)
    local scroll, body = Scroll(page, "AshoholicPreviewProgressionScroll", 530, 57, 542, 345)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", ScrollBy)
    page.ladderRows = {}
    for i = 1, #ACCOUNTS do
        local row = CreateFrame("Frame", nil, ladder)
        row:SetSize(490, 51)
        row.name = Label(row, "", 0, 0, 150, 12)
        row.note = Label(row, "", 155, 0, 323, 11, MUTED)
        row.pips = {}
        for tier = 1, 10 do
            row.pips[tier] = Surface(row, (tier - 1) * 49, 23, 43, 17)
            local fs = Label(row.pips[tier], tostring(tier), 0, 2, 43, 10)
            fs:SetJustifyH("CENTER")
        end
        page.ladderRows[i] = row
    end
    page.prestigePanels = {}
    for accountId, account in ipairs(ACCOUNTS) do
        local panel = Surface(body, 0, 0, 510, 160)
        panel.title = Label(panel, account.name .. "  /  Prestige " .. account.prestige, 16, 15, 478, 14, GOLD)
        Label(panel, account.ash >= 10771440 and GREEN .. "Ready to Prestige|r" or AMBER .. "Ash requirement not met|r", 16, 44, 478, 13)
        DetailLine(panel, "Committed Ash / gate", Short(account.ash) .. " / 10.77m", 74)
        DetailLine(panel, "Banked Shards", tostring(account.shards), 99)
        DetailLine(panel, "Sample Essence preview", "+" .. math.floor(account.shards / 750) .. " Essence", 124)
        page.prestigePanels[accountId] = panel
    end
    Label(page, "Prestige preview: informational only. Exact reset effects require in-game confirmation.", 0, 411, 1072, 10, MUTED)
    page.Refresh = function()
        local y = 52
        for i, account in ipairs(ACCOUNTS) do
            local row = page.ladderRows[i]
            local visible = state.accounts[i]
            SetVisible(row, visible)
            if visible then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 16, -y)
                row.name:SetText(account.name)
                row.note:SetText("Torment " .. account.tier .. " unlocked for all characters")
                for tier, pip in ipairs(row.pips) do
                    pip:SetBackdropColor(unpack(tier <= account.tier and { 0.16, 0.36, 0.31, 1 } or { 0.11, 0.12, 0.15, 1 }))
                end
                y = y + 54
            end
        end
        y = 0
        for accountId, panel in ipairs(page.prestigePanels) do
            local visible = state.accounts[accountId]
            SetVisible(panel, visible)
            if visible then
                panel:ClearAllPoints()
                panel.title:SetText(ACCOUNTS[accountId].name .. "  /  Prestige " .. ACCOUNTS[accountId].prestige)
                panel:SetPoint("TOPLEFT", 0, -y)
                y = y + 177
            end
        end
        y = y - 17
        body:SetHeight(math.max(345, y))
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, y - 345)))
    end
end

local function BuildTrials()
    local page = Page("Trials", "Personal records", "Compare saved bests across your roster. Rankings are last-observed snapshots, not live standings.")
    local headings = { { "CHARACTER", 16 }, { "CHAMPION BEST", 205 }, { "CLASS RANK", 409 }, { "CRUSADER BEST", 575 }, { "TEAM", 797 }, { "UPDATED", 912 } }
    for _, column in ipairs(headings) do Label(page, column[1], column[2], 68, 190, 10, MUTED) end
    Button(page, "What are these Trials?", 845, 0, 227, 26, function()
        ShowSettings("Help")
    end)
    local scroll, body = Scroll(page, "AshoholicPreviewTrialScroll", 0, 98, 1072, 264)
    local records = {
        { "1.42m damage", "#42 / 1,280", "Wave 18 / 14:32", "Solo", "Today" },
        { "1.18m damage", "#67 / 940", "Wave 15 / 12:08", "3 players", "Today" },
        { "Not recorded", "-", "Not recorded", "-", "-" },
        { "1.86m damage", "#18 / 1,105", "Wave 22 / 18:46", "5 players", "Today" },
        { "980k damage", DIM .. "Stale|r", "Wave 12 / 10:14", "Solo", "8 days ago" },
    }
    page.rows = {}
    for i, character in ipairs(CHARACTERS) do
        local row = Surface(body, 0, 0, 1046, 44)
        Label(row, ClassName(character), 16, 15, 180, 12)
        for j, value in ipairs(records[i] or { "Not recorded", "-", "Not recorded", "-", "-" }) do Label(row, value, headings[j + 1][2], 15, j == 3 and 210 or 140, 11) end
        Tip(row, character.name .. " / " .. ACCOUNTS[character.account].name, "Champion: solo damage Trial, ranked within your class.\nCrusader: survival waves, 1-5 players. Team is the size of that recorded attempt.\nThese are sample records, not dungeon lockouts.")
        page.rows[i] = row
    end
    Label(page, "Season: Example season  /  Practice runs excluded  /  Scores and ranks shown here are all invented.", 16, 375, 1030, 11, TEAL)
    page.Refresh = function()
        local y = 0
        for i, character in ipairs(CHARACTERS) do
            local visible = state.accounts[character.account]
            SetVisible(page.rows[i], visible)
            if visible then
                page.rows[i]:ClearAllPoints()
                page.rows[i]:SetPoint("TOPLEFT", 0, -y)
                y = y + 50
            end
        end
        body:SetHeight(math.max(264, y))
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, y - 264)))
    end
end

local dialog, palette
local DEFAULT_TEXT, DEFAULT_MUTED, DEFAULT_TEAL = { unpack(TEXT) }, { unpack(MUTED) }, { unpack(TEAL) }
local THEMES = {
    { "Ember & Ash", "Warm ember gold on soot.", { 0.035, 0.042, 0.058 }, { 0.075, 0.083, 0.105 }, { 0.19, 0.21, 0.26 }, { 1, 0.79, 0.39 } },
    { "Frostbound", "Northrend ice and steel.", { 0.025, 0.05, 0.085 }, { 0.05, 0.09, 0.14 }, { 0.16, 0.27, 0.38 }, { 0.45, 0.8, 1 } },
    { "Void Walker", "Deep violet shadow.", { 0.05, 0.02, 0.08 }, { 0.09, 0.05, 0.13 }, { 0.27, 0.17, 0.36 }, { 0.8, 0.55, 1 } },
    { "Fel Ember", "Sickly green flame.", { 0.03, 0.05, 0.025 }, { 0.06, 0.09, 0.05 }, { 0.2, 0.32, 0.14 }, { 0.55, 1, 0.3 } },
    { "Blood Moon", "Crimson Torment.", { 0.06, 0.015, 0.02 }, { 0.11, 0.03, 0.04 }, { 0.36, 0.1, 0.12 }, { 1, 0.35, 0.35 } },
    { "Holy Light", "Bright, warm and soft.", { 0.08, 0.075, 0.06 }, { 0.13, 0.12, 0.09 }, { 0.5, 0.44, 0.26 }, { 1, 0.92, 0.55 } },
    { "Old Parchment", "Aged leather and ink.", { 0.1, 0.078, 0.05 }, { 0.15, 0.12, 0.08 }, { 0.45, 0.34, 0.2 }, { 0.94, 0.85, 0.63 }, { 0.95, 0.91, 0.82 }, { 0.63, 0.56, 0.45 } },
    { "Terminal", "Green phosphor. Flat.", { 0, 0, 0 }, { 0.02, 0.05, 0.02 }, { 0.12, 0.56, 0.25 }, { 0.2, 1, 0.4 }, { 0.67, 1, 0.73 }, { 0.12, 0.56, 0.25 }, { 0.4, 1, 0.67 } },
}
local PALETTE = {
    { 1, 0.79, 0.39 }, { 1, 0.6, 0.2 }, { 1, 0.35, 0.35 }, { 0.85, 0.2, 0.3 }, { 1, 0.92, 0.55 }, { 0.94, 0.85, 0.63 },
    { 0.55, 1, 0.3 }, { 0.2, 1, 0.4 }, { 0.4, 0.86, 0.78 }, { 0.45, 0.8, 1 }, { 0.3, 0.5, 1 }, { 0.8, 0.55, 1 },
    { 0.88, 0.88, 0.9 }, { 0.58, 0.61, 0.67 }, { 0.35, 0.37, 0.42 }, { 0.19, 0.21, 0.26 }, { 0.12, 0.13, 0.17 }, { 0.075, 0.083, 0.105 },
    { 0.035, 0.042, 0.058 }, { 0, 0, 0 }, { 0.1, 0.078, 0.05 }, { 0.025, 0.05, 0.085 }, { 0.05, 0.02, 0.08 }, { 0.06, 0.015, 0.02 },
}
local LOGOS = {
    "Interface\\Icons\\inv_soulash", "Interface\\Icons\\inv_misc_supersoulash",
    "Interface\\Icons\\inv_10_jewelcrafting3_soulcage_frost", "Interface\\Icons\\ability_argus_soulbombdebufflarge",
    "Interface\\Icons\\Spell_Shadow_SoulGem", "Interface\\Icons\\Spell_Fire_Fire",
    "Interface\\Icons\\Achievement_Boss_LichKing", "Interface\\Icons\\INV_Misc_Coin_02",
    "Interface\\Icons\\INV_Misc_Bag_10", "Interface\\Icons\\Spell_Shadow_DeathCoil",
    "Interface\\Icons\\Spell_Frost_FrostShock", "Interface\\Icons\\INV_Misc_Book_09",
}
local SECTIONS = {
    { "Themes", "Pick a complete look. Every preset recolors the whole preview instantly." },
    { "Colors", "Build your own theme, slot by slot. Save it, export it, share it." },
    { "Text & Layout", "Fonts, text size, row density, window scale and transparency." },
    { "Icons", "Currency icons, class icons, raid status symbols and the Ashoholic logo." },
    { "Roster Columns", "Choose which character details become columns, and in which order." },
    { "Tabs & Views", "Hide tabs you never use and choose what opens first." },
    { "Accounts", "Optional aliases, account colors and default grouping." },
    { "Alerts", "Reminders for resets, caches, Prestige and watched bosses." },
    { "Profiles & Sharing", "Keep different setups and share themes with friends." },
    { "Sync", "Combine several WoW accounts into one roster." },
    { "Help", "What the Trials, Torment and loot terms mean." },
}

local function Copy(target, source)
    for i = 1, #source do target[i] = source[i] end
end

local function Hex(color)
    return string.format("%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

local function ApplyAppearance()
    frame:SetBackdropColor(unpack(BACKGROUND))
    frame:SetBackdropBorderColor(GOLD[1] * 0.45, GOLD[2] * 0.45, GOLD[3] * 0.45, 1)
    for _, entry in ipairs(surfaces) do
        if entry[2] then entry[1]:SetBackdropColor(unpack(PANEL)) end
        entry[1]:SetBackdropBorderColor(unpack(BORDER))
    end
    for _, button in ipairs(buttons) do
        button:SetBackdropColor(unpack(BUTTON_BG))
        button:SetBackdropBorderColor(unpack(BUTTON_BORDER))
    end
    for _, entry in ipairs(labels) do
        entry[1]:SetFont(state.font, math.max(8, entry[3] + state.fontDelta))
        entry[1]:SetTextColor(unpack(entry[2]))
    end
    for _, window in ipairs({ settings, dialog, palette }) do
        if window then
            window:SetBackdropColor(BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], 0.99)
            window:SetBackdropBorderColor(GOLD[1] * 0.6, GOLD[2] * 0.6, GOLD[3] * 0.6, 1)
        end
    end
    if frame.logo then frame.logo:SetTexture(state.logo) end
    if settings and settings.logo then settings.logo:SetTexture(state.logo) end
    refresh()
    if settings and settings.current then settings.ShowSection(settings.current) end
end

local function ApplyPreset(preset)
    Copy(BACKGROUND, preset[3])
    Copy(PANEL, preset[4])
    Copy(BORDER, preset[5])
    Copy(GOLD, preset[6])
    Copy(TEXT, preset[7] or DEFAULT_TEXT)
    Copy(MUTED, preset[8] or DEFAULT_MUTED)
    Copy(TEAL, preset[9] or DEFAULT_TEAL)
    for i = 1, 3 do
        BUTTON_BG[i] = math.min(1, preset[4][i] * 1.3 + 0.02)
        BUTTON_BORDER[i] = math.min(1, preset[5][i] * 1.25)
    end
    state.theme = preset[1]
    state.lastPreset = preset[1]
    ApplyAppearance()
end

local function Popup(name, width, height)
    local popup = CreateFrame("Frame", name, UIParent)
    popup:SetSize(width, height)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(120)
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    popup:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    popup:SetBackdropColor(BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], 0.99)
    popup:SetBackdropBorderColor(GOLD[1] * 0.6, GOLD[2] * 0.6, GOLD[3] * 0.6, 1)
    tinsert(UISpecialFrames, name)
    return popup
end

local function Dialog(title, text, options)
    options = options or {}
    if not dialog then
        dialog = Popup("AshoholicPreviewDialog", 460, 262)
        dialog.title = Label(dialog, "", 18, 16, 424, 15, GOLD)
        dialog.text = Label(dialog, "", 18, 46, 424, 11)
        dialog.boxBg = Surface(dialog, 14, 118, 432, 78, { 0.02, 0.025, 0.035, 1 })
        dialog.box = CreateFrame("EditBox", nil, dialog.boxBg)
        dialog.box:SetPoint("TOPLEFT", 8, -8)
        dialog.box:SetSize(416, 62)
        dialog.box:SetMultiLine(true)
        dialog.box:SetAutoFocus(false)
        dialog.box:SetFontObject(ChatFontNormal)
        dialog.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        dialog.primary = Button(dialog, "", 18, 216, 200, 28)
        dialog.secondary = Button(dialog, "Cancel", 242, 216, 200, 28, function() dialog:Hide() end)
    end
    dialog:SetScale(settings and settings:GetScale() or 1)
    dialog.title:SetText(title)
    dialog.text:SetText(text)
    SetVisible(dialog.boxBg, options.box ~= nil)
    dialog.box:SetText(options.box or "")
    dialog.primary.text:SetText(options.primary or "OK")
    dialog.primary:SetScript("OnClick", function()
        local value = dialog.box:GetText()
        dialog:Hide()
        if options.onAccept then options.onAccept(value) end
    end)
    SetVisible(dialog.secondary, options.primary ~= nil)
    dialog:Show()
    dialog:Raise()
    if options.box then
        dialog.box:SetFocus()
        dialog.box:HighlightText()
    end
end

local function PickColor(title, onPick)
    if not palette then
        palette = Popup("AshoholicPreviewPalette", 336, 256)
        palette.title = Label(palette, "", 18, 16, 300, 14, GOLD)
        for i, color in ipairs(PALETTE) do
            local swatchColor = color
            local swatch = CreateFrame("Button", nil, palette)
            swatch:SetPoint("TOPLEFT", 18 + ((i - 1) % 6) * 50, -(48 + math.floor((i - 1) / 6) * 38))
            swatch:SetSize(44, 32)
            swatch:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
            swatch:SetBackdropColor(color[1], color[2], color[3], 1)
            swatch:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
            swatch:SetHighlightTexture(WHITE)
            swatch:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.2)
            swatch:SetScript("OnClick", function()
                palette:Hide()
                if palette.onPick then palette.onPick(swatchColor) end
            end)
        end
        Button(palette, "Cancel", 216, 212, 102, 28, function() palette:Hide() end)
        Label(palette, "Preview palette", 18, 220, 190, 10, MUTED)
    end
    palette:SetScale(settings and settings:GetScale() or 1)
    palette.title:SetText(title)
    palette.onPick = onPick
    palette:Show()
    palette:Raise()
end

local function BuildSettings()
    settings = Popup("AshoholicPreviewSettings", 900, 600)
    settings:SetFrameLevel(40)
    settings.groups = {}
    settings.logo = settings:CreateTexture(nil, "ARTWORK")
    settings.logo:SetPoint("TOPLEFT", 18, -14)
    settings.logo:SetSize(32, 32)
    settings.logo:SetTexture(state.logo)
    Label(settings, "ASHOHOLIC SETTINGS", 60, 15, 500, 18, GOLD)
    Label(settings, "Design preview  /  every choice applies to this preview immediately and is forgotten on /reload.", 60, 38, 760, 10, MUTED)
    Button(settings, "X", 856, 14, 28, 26, function() settings:Hide() end)
    local nav = Surface(settings, 16, 70, 186, 476)
    local bodies, navButtons = {}, {}
    settings.sectionTitle = Label(settings, "", 222, 74, 660, 16, GOLD)
    settings.sectionText = Label(settings, "", 222, 98, 660, 10, MUTED)
    for i, section in ipairs(SECTIONS) do
        local name = section[1]
        navButtons[name] = Button(nav, name, 8, 8 + (i - 1) * 42, 170, 34, function() settings.ShowSection(name) end)
        local body = CreateFrame("Frame", nil, settings)
        body:SetPoint("TOPLEFT", 222, -126)
        body:SetSize(664, 420)
        bodies[name] = body
    end
    local status = Label(settings, "", 222, 567, 340, 10, TEAL)
    local function Say(text) status:SetText(text) end
    local function Toggle(parent, text, x, y, width, get, set)
        local button
        button = Button(parent, "", x, y, width, 28, function()
            set(not get())
            button.Update()
        end)
        button.Update = function() button.text:SetText((get() and "[x] " or "[ ] ") .. text) end
        button.Update()
        settings.groups[#settings.groups + 1] = button
        return button
    end
    local function Choices(parent, options, x, y, width, perRow, get, set)
        local group = {}
        for i, option in ipairs(options) do
            local value = option[1]
            local button = Button(parent, option[2], x + ((i - 1) % perRow) * (width + 8), y + math.floor((i - 1) / perRow) * 34, width, 28, function()
                set(value)
                group.Update()
            end)
            button.value = value
            group[i] = button
        end
        group.Update = function()
            for _, button in ipairs(group) do
                button:SetBackdropBorderColor(unpack(get() == button.value and GOLD or BUTTON_BORDER))
                button.text:SetTextColor(unpack(get() == button.value and GOLD or TEXT))
            end
        end
        group.Update()
        settings.groups[#settings.groups + 1] = group
        return group
    end
    local function SliderRow(parent, title, x, y, low, high, step, get, set, format)
        Label(parent, title, x, y, 300, 11, GOLD)
        local slider = CreateFrame("Slider", nil, parent)
        slider:SetPoint("TOPLEFT", x, -(y + 24))
        slider:SetSize(400, 14)
        slider:SetOrientation("HORIZONTAL")
        slider:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        slider:SetBackdropColor(0.10, 0.11, 0.14, 1)
        slider:SetBackdropBorderColor(unpack(BORDER))
        slider:SetThumbTexture(WHITE)
        slider:GetThumbTexture():SetSize(14, 14)
        slider:GetThumbTexture():SetVertexColor(unpack(GOLD))
        slider:SetMinMaxValues(low, high)
        slider:SetValueStep(step)
        slider:SetValue(get())
        local text = Label(parent, format(get()), x + 416, y + 24, 120, 11)
        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / step + 0.5) * step
            text:SetText(format(value))
            set(value)
        end)
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
        settings.groups[#settings.groups + 1] = { Update = function() slider:GetThumbTexture():SetVertexColor(unpack(GOLD)) end }
        return slider
    end

    -- Themes
    local themeBody = bodies.Themes
    local themeGroup = {}
    for i, preset in ipairs(THEMES) do
        local theme = preset
        local card = Button(themeBody, preset[1], ((i - 1) % 2) * 330, math.floor((i - 1) / 2) * 82, 320, 72, function() ApplyPreset(theme) end)
        Label(card, preset[2], 9, 27, 200, 10, MUTED)
        for j, color in ipairs({ preset[3], preset[4], preset[5], preset[6] }) do
            local swatch = card:CreateTexture(nil, "OVERLAY")
            swatch:SetTexture(WHITE)
            swatch:SetVertexColor(color[1], color[2], color[3], 1)
            swatch:SetPoint("TOPLEFT", 214 + (j - 1) * 24, -22)
            swatch:SetSize(20, 28)
        end
        card.value = preset[1]
        themeGroup[i] = card
    end
    themeGroup.Update = function()
        for _, card in ipairs(themeGroup) do
            card:SetBackdropBorderColor(unpack((state.theme or "Ember & Ash") == card.value and GOLD or BUTTON_BORDER))
        end
    end
    settings.groups[#settings.groups + 1] = themeGroup
    Button(themeBody, "Customize this theme...", 0, 340, 240, 30, function() settings.ShowSection("Colors") end)
    Button(themeBody, "Import a theme...", 250, 340, 200, 30, function() settings.ShowSection("Profiles & Sharing") end)
    Label(themeBody, "Themes affect colors only. Fonts, icons and layout live in their own sections, so you can mix them freely.", 0, 386, 660, 10, MUTED)

    -- Colors (custom theme editor)
    local colorBody = bodies.Colors
    local slots = {
        { "Window background", BACKGROUND }, { "Panels & rows", PANEL }, { "Borders", BORDER },
        { "Buttons", BUTTON_BG }, { "Accent / headings", GOLD }, { "Body text", TEXT },
        { "Secondary text", MUTED }, { "Highlighted values", TEAL },
    }
    local swatches = {}
    for i, slot in ipairs(slots) do
        local target, title = slot[2], slot[1]
        local x, y = ((i - 1) % 2) * 330, math.floor((i - 1) / 2) * 52
        local row = Surface(colorBody, x, y, 320, 44)
        Label(row, title, 12, 15, 160, 11)
        local swatch = row:CreateTexture(nil, "OVERLAY")
        swatch:SetTexture(WHITE)
        swatch:SetPoint("TOPLEFT", 176, -9)
        swatch:SetSize(42, 26)
        swatches[i] = { swatch, target }
        Button(row, "Change", 228, 8, 82, 28, function()
            PickColor(title, function(color)
                Copy(target, color)
                state.theme = "Custom"
                ApplyAppearance()
                Say(title .. " changed. Theme is now 'Custom'.")
            end)
        end)
    end
    settings.groups[#settings.groups + 1] = { Update = function()
        for _, entry in ipairs(swatches) do entry[1]:SetVertexColor(entry[2][1], entry[2][2], entry[2][3], 1) end
    end }
    Button(colorBody, "Save as custom theme...", 0, 222, 240, 30, function()
        Dialog("Save custom theme", "Name your theme. In the live addon it would join the theme gallery and could be exported.", {
            box = "My Ashoholic theme", primary = "Save",
            onAccept = function(name) Say("Saved '" .. name .. "' (preview only).") end,
        })
    end)
    Button(colorBody, "Revert to preset", 250, 222, 200, 30, function()
        for _, preset in ipairs(THEMES) do
            if preset[1] == (state.lastPreset or "Ember & Ash") then ApplyPreset(preset) end
        end
        Say("Reverted to " .. (state.lastPreset or "Ember & Ash") .. ".")
    end)
    Label(colorBody, "IDEAS TO EXPAND", 0, 282, 660, 11, GOLD)
    Label(colorBody, "Per-tab accent colors, gradient headers, background art (Icecrown, Karazhan, Torment), class-colored row tints, and a 'Torment glow' that intensifies with your highest unlocked tier.", 0, 304, 660, 11, MUTED)

    -- Text & Layout
    local textBody = bodies["Text & Layout"]
    Label(textBody, "FONT", 0, 0, 300, 11, GOLD)
    Choices(textBody, {
        { "Fonts\\FRIZQT__.TTF", "Friz Quadrata" }, { "Fonts\\ARIALN.TTF", "Arial Narrow" },
        { "Fonts\\MORPHEUS.TTF", "Morpheus" }, { "Fonts\\skurri.ttf", "Skurri" },
    }, 0, 22, 154, 4, function() return state.font end, function(value) state.font = value; ApplyAppearance() end)
    Label(textBody, "TEXT SIZE", 0, 72, 300, 11, GOLD)
    Choices(textBody, { { -1, "Small" }, { 0, "Normal" }, { 1, "Large" }, { 2, "Larger" } }, 0, 94, 154, 4,
        function() return state.fontDelta end, function(value) state.fontDelta = value; ApplyAppearance() end)
    Label(textBody, "ROSTER ROW DENSITY", 0, 144, 300, 11, GOLD)
    Choices(textBody, { { "compact", "Compact" }, { "comfortable", "Comfortable" }, { "spacious", "Spacious" } }, 0, 166, 210, 3,
        function() return state.density end, function(value) state.density = value; refresh() end)
    SliderRow(textBody, "WINDOW SCALE", 0, 218, 0.7, 1.2, 0.05, function() return state.scale end, function(value)
        state.scale = value
        frame:SetScale((frame.baseScale or 1) * value)
    end, function(value) return string.format("%.0f%%", value * 100) end)
    SliderRow(textBody, "BACKGROUND OPACITY", 0, 278, 0.4, 1, 0.05, function() return BACKGROUND[4] end, function(value)
        BACKGROUND[4] = value
        frame:SetBackdropColor(unpack(BACKGROUND))
    end, function(value) return string.format("%.0f%%", value * 100) end)
    Label(textBody, "Compact hides the hint line under each character. Scale and opacity affect only the main window.", 0, 346, 660, 10, MUTED)

    -- Icons
    local iconBody = bodies.Icons
    Label(iconBody, "CURRENCY ICONS", 0, 0, 300, 11, GOLD)
    Choices(iconBody, { { "icons", "Ebonhold icons" }, { "large", "Large icons" }, { "text", "Text only" } }, 0, 22, 210, 3,
        function() return state.iconStyle end, function(value) state.iconStyle = value; refresh() end)
    Label(iconBody, "RAID LOOT STATUS", 0, 72, 300, 11, GOLD)
    Choices(iconBody, { { "words", "Words (Available / Looted)" }, { "icons", "Ready-check symbols" } }, 0, 94, 320, 2,
        function() return state.statusStyle end, function(value) state.statusStyle = value; refresh() end)
    Toggle(iconBody, "Show class icons beside names", 0, 140, 320, function() return state.classIcons end,
        function(value) state.classIcons = value; refresh() end)
    Label(iconBody, "ASHOHOLIC LOGO & MINIMAP ICON", 0, 190, 400, 11, GOLD)
    local logoButtons = {}
    for i, path in ipairs(LOGOS) do
        local logo = path
        local button = Button(iconBody, "", (i - 1) * 54, 214, 46, 46, function()
            state.logo = logo
            ApplyAppearance()
            Say("Logo changed. The live addon would update the minimap button too.")
        end)
        local texture = button:CreateTexture(nil, "ARTWORK")
        texture:SetPoint("TOPLEFT", 4, -4)
        texture:SetPoint("BOTTOMRIGHT", -4, 4)
        texture:SetTexture(path)
        texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        button.value = path
        logoButtons[i] = button
    end
    logoButtons.Update = function()
        for _, button in ipairs(logoButtons) do
            button:SetBackdropBorderColor(unpack(state.logo == button.value and GOLD or BUTTON_BORDER))
        end
    end
    settings.groups[#settings.groups + 1] = logoButtons
    Button(iconBody, "Use custom icon path...", 0, 276, 240, 30, function()
        Dialog("Custom icon", "Enter any game icon path. The live addon would validate it before use.", {
            box = "Interface\\Icons\\INV_Misc_QuestionMark", primary = "Use icon",
            onAccept = function(path)
                state.logo = path
                ApplyAppearance()
                Say("Custom icon applied to the preview.")
            end,
        })
    end)
    Label(iconBody, "Later ideas: role icons, Torment tier badges, Prestige emblems and per-account icons.", 0, 326, 660, 10, MUTED)

    -- Roster Columns
    local columnBody = bodies["Roster Columns"]
    Label(columnBody, "Choose up to six columns beside the character name. Use < / > to reorder selected columns.", 0, 0, 660, 11, GOLD)
    local columnButtons = {}
    local function ColumnIndex(key)
        for i, selected in ipairs(columnOrder) do if selected == key then return i end end
    end
    local columnNotice = Label(columnBody, "", 0, 315, 660, 11, GOLD)
    local detailButton
    local function RefreshColumns()
        for i, column in ipairs(columns) do
            local index = ColumnIndex(column.key)
            columnButtons[i].text:SetText((index and "[x] " .. index .. ". " or "[ ] ") .. column.title)
        end
        detailButton.text:SetText((state.detail and "[x] " or "[ ] ") .. "Show parked-run detail panel")
        refresh()
    end
    for i, column in ipairs(columns) do
        local key = column.key
        local x, y = ((i - 1) % 2) * 330, 32 + math.floor((i - 1) / 2) * 38
        columnButtons[i] = Button(columnBody, "", x, y, 240, 28, function()
            local index = ColumnIndex(key)
            columnNotice:SetText("")
            if index then table.remove(columnOrder, index)
            elseif #columnOrder < 6 then columnOrder[#columnOrder + 1] = key
            else columnNotice:SetText("Six columns are selected. Uncheck one before adding another."); return end
            RefreshColumns()
        end)
        for direction = -1, 1, 2 do
            local step = direction
            Button(columnBody, direction == -1 and "<" or ">", x + (direction == -1 and 248 or 286), y, 34, 28, function()
                local index = ColumnIndex(key)
                if index and index + step >= 1 and index + step <= #columnOrder then
                    columnOrder[index], columnOrder[index + step] = columnOrder[index + step], columnOrder[index]
                    RefreshColumns()
                else columnNotice:SetText("Select this column first; only selected columns can move.") end
            end)
        end
    end
    detailButton = Button(columnBody, "", 0, 273, 420, 28, function()
        state.detail = not state.detail
        RefreshColumns()
    end)
    Label(columnBody, "Any parked-run detail can become a column. Hiding the detail panel gives the roster the full width.", 0, 342, 660, 10, MUTED)
    bodies["Roster Columns"].Refresh = RefreshColumns

    -- Tabs & Views
    local tabBody = bodies["Tabs & Views"]
    Label(tabBody, "SHOW TABS  (Roster is always shown)", 0, 0, 400, 11, GOLD)
    for i, tab in ipairs({ { "Raids", "Raids & Dungeons" }, { "Activities", "Activities" }, { "Progression", "Progression" }, { "Trials", "Trials" } }) do
        local key = tab[1]
        Toggle(tabBody, tab[2], ((i - 1) % 2) * 330, 22 + math.floor((i - 1) / 2) * 34, 320,
            function() return not state.hiddenTabs[key] end,
            function(value) state.hiddenTabs[key] = not value; refresh() end)
    end
    Label(tabBody, "WHEN THE WINDOW OPENS", 0, 112, 400, 11, GOLD)
    Choices(tabBody, { { "last", "Last used tab" }, { "Roster", "Roster" }, { "Raids", "Raids & Dungeons" }, { "Activities", "Activities" }, { "Progression", "Progression" }, { "Trials", "Trials" } },
        0, 134, 210, 3, function() return state.openTab or "last" end, function(value) state.openTab = value end)
    Label(tabBody, "EXTRAS", 0, 218, 400, 11, GOLD)
    state.mock = state.mock or {}
    for i, option in ipairs({ { "openLogin", "Open Ashoholic on login" }, { "combatHide", "Hide automatically in combat" }, { "lockWindow", "Lock window position" }, { "escClose", "Escape closes the window", true } }) do
        local key = option[1]
        if state.mock[key] == nil then state.mock[key] = option[3] or false end
        Toggle(tabBody, option[2], ((i - 1) % 2) * 330, 240 + math.floor((i - 1) / 2) * 34, 320,
            function() return state.mock[key] end, function(value) state.mock[key] = value end)
    end
    Label(tabBody, "Hidden tabs disappear immediately. 'Extras' are mock switches only.", 0, 330, 660, 10, MUTED)

    -- Accounts
    local accountBody = bodies.Accounts
    Label(accountBody, "CURRENT ACCOUNT ALIAS  (optional; default is the real account name)", 0, 0, 660, 11, GOLD)
    local input = CreateFrame("EditBox", nil, accountBody, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", 8, -26)
    input:SetSize(300, 28)
    input:SetAutoFocus(false)
    input:SetMaxLetters(32)
    local function Rename(name)
        name = name:match("^%s*(.-)%s*$")
        if name == "" then Say("Enter a name, or use Restore default."); return end
        if name:find("|", 1, true) or name:find("[%c]") then Say("Use a plain-text name without control codes or |."); return end
        ACCOUNTS[1].name = name
        input:SetText(name)
        input:ClearFocus()
        Say("Alias updated everywhere in the preview.")
        settings.ShowSection("Accounts")
        refresh()
    end
    Button(accountBody, "Rename", 322, 26, 120, 28, function() Rename(input:GetText()) end)
    Button(accountBody, "Restore default", 452, 26, 160, 28, function() Rename(ACCOUNTS[1].originalName) end)
    input:SetScript("OnEnterPressed", function() Rename(input:GetText()) end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Label(accountBody, "ALL ACCOUNTS", 0, 82, 660, 11, GOLD)
    local accountRows = {}
    for i, account in ipairs(ACCOUNTS) do
        local id, data = i, account
        local row = Surface(accountBody, 0, 104 + (i - 1) * 46, 640, 40)
        row.name = Label(row, "", 12, 14, 240, 12)
        row.swatch = row:CreateTexture(nil, "OVERLAY")
        row.swatch:SetTexture(WHITE)
        row.swatch:SetPoint("TOPLEFT", 260, -10)
        row.swatch:SetSize(30, 20)
        Button(row, "Color...", 298, 6, 92, 28, function()
            PickColor(data.name .. " color", function(color)
                data.color = { color[1], color[2], color[3] }
                Say(data.name .. " recolored in the roster and encounter headers.")
                settings.ShowSection("Accounts")
                refresh()
            end)
        end)
        Toggle(row, "Start collapsed", 398, 6, 234, function() return state.collapsed[id] end,
            function(value) state.collapsed[id] = value; refresh() end)
        accountRows[i] = row
    end
    Label(accountBody, "Account 1 is the account you are playing on. Aliases never change account identity; filters are separate.", 0, 300, 660, 10, MUTED)
    bodies.Accounts.Refresh = function()
        input:SetText(ACCOUNTS[1].name)
        for i, row in ipairs(accountRows) do
            local account = ACCOUNTS[i]
            row.name:SetText(account.name .. (i == 1 and "  (current)" or ""))
            local color = account.color or GOLD
            row.swatch:SetVertexColor(color[1], color[2], color[3], 1)
        end
    end

    -- Alerts
    local alertBody = bodies.Alerts
    Label(alertBody, "REMIND ME ABOUT", 0, 0, 400, 11, GOLD)
    state.alerts = state.alerts or { reset = true, cache = true, boss = true, prestige = false, stale = true }
    for i, option in ipairs({ { "reset", "Weekly raid reset (Tuesday 03:00 UTC)" }, { "cache", "Call Board cache ready" }, { "boss", "Watched boss available on login" }, { "prestige", "Account ready to Prestige" }, { "stale", "Character snapshot is stale" } }) do
        local key = option[1]
        Toggle(alertBody, option[2], 0, 22 + (i - 1) * 34, 420, function() return state.alerts[key] end,
            function(value) state.alerts[key] = value end)
    end
    Label(alertBody, "SHOW ALERTS AS", 0, 202, 400, 11, GOLD)
    Choices(alertBody, { { "chat", "Chat message" }, { "center", "Center of screen" }, { "silent", "Silent (badge only)" } }, 0, 224, 210, 3,
        function() return state.alertStyle or "chat" end, function(value) state.alertStyle = value end)
    Button(alertBody, "Send test alert", 0, 274, 210, 30, function()
        local text = "Ashoholic preview: Nightbane loot is available on Cinder."
        local style = state.alertStyle or "chat"
        if style == "chat" then print("|cffffca63" .. text .. "|r")
        elseif style == "center" and RaidNotice_AddMessage then RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"]) end
        Say(style == "silent" and "Silent: the live addon would show a badge on the tab instead." or "Test alert sent.")
    end)

    -- Profiles & Sharing
    local profileBody = bodies["Profiles & Sharing"]
    Label(profileBody, "ACTIVE PROFILE", 0, 0, 400, 11, GOLD)
    Choices(profileBody, { { "Default", "Default" }, { "Raid Night", "Raid Night" }, { "Transmog Hunter", "Transmog Hunter" } }, 0, 22, 210, 3,
        function() return state.profile or "Default" end, function(value) state.profile = value; Say("Switched to profile '" .. value .. "'.") end)
    Label(profileBody, "PROFILE APPLIES TO", 0, 72, 400, 11, GOLD)
    Choices(profileBody, { { "character", "This character" }, { "account", "This account" }, { "all", "All synced accounts" } }, 0, 94, 210, 3,
        function() return state.profileScope or "account" end, function(value) state.profileScope = value end)
    Button(profileBody, "New profile...", 0, 146, 210, 30, function()
        Dialog("New profile", "Name the new profile. It starts as a copy of the current settings.", {
            box = "My profile", primary = "Create", onAccept = function(name) Say("Created '" .. name .. "' (preview only).") end,
        })
    end)
    Button(profileBody, "Copy from...", 218, 146, 210, 30, function()
        Dialog("Copy profile", "Copy every setting from 'Raid Night' into '" .. (state.profile or "Default") .. "'?", {
            primary = "Copy", onAccept = function() Say("Copied (preview only).") end,
        })
    end)
    Button(profileBody, "Delete profile", 436, 146, 210, 30, function()
        Dialog("Delete profile", "Delete '" .. (state.profile or "Default") .. "'? This cannot be undone.", {
            primary = "Delete", onAccept = function() Say("Nothing was deleted; this is a preview.") end,
        })
    end)
    Label(profileBody, "SHARE THEMES", 0, 202, 400, 11, GOLD)
    Button(profileBody, "Export current theme...", 0, 224, 260, 30, function()
        local code = "ASH2:" .. (state.theme or "Ember & Ash") .. ":" .. Hex(BACKGROUND) .. ":" .. Hex(PANEL) .. ":" .. Hex(BORDER) .. ":" .. Hex(GOLD) .. ":" .. Hex(TEXT)
        Dialog("Export theme", "Copy this string (Ctrl+C) and share it with friends.", { box = code })
    end)
    Button(profileBody, "Import theme...", 268, 224, 260, 30, function()
        Dialog("Import theme", "Paste a theme string (Ctrl+V).", {
            box = "", primary = "Import", onAccept = function(code)
                Say(code == "" and "Nothing pasted." or "String received; import is not applied in the preview.")
            end,
        })
    end)
    Label(profileBody, "Idea: a community theme gallery in-game, filled from strings shared on Discord.", 0, 274, 660, 10, MUTED)

    -- Sync
    local syncBody = bodies.Sync
    Label(syncBody, "MULTI-ACCOUNT SYNC", 0, 0, 660, 11, GOLD)
    Label(syncBody, "The real addon merges SavedVariables from several WoW accounts with its sync scripts. This preview shows four sample accounts; nothing is read or written.", 0, 24, 660, 11)
    local rows = { { "Account One", "This account", "Live" }, { "Account Two", "Synced 2 hours ago", "OK" }, { "Account Three", "Synced yesterday", "OK" }, { "Account Four", "Synced 8 days ago", "Stale" } }
    for i, row in ipairs(rows) do
        local panel = Surface(syncBody, 0, 76 + (i - 1) * 40, 640, 34)
        Label(panel, row[1], 12, 11, 220, 11)
        Label(panel, row[2], 240, 11, 260, 11, MUTED)
        Label(panel, row[3], 540, 11, 90, 11, row[3] == "Stale" and GOLD or TEAL)
    end
    Button(syncBody, "Simulate sync", 0, 246, 210, 30, function()
        Say("Sample sync complete: 4 accounts / " .. #CHARACTERS .. " characters.")
    end)
    Button(syncBody, "How does sync work?", 218, 246, 210, 30, function()
        Dialog("How sync works", "1. Log out of WoW.\n2. Run the Ashoholic sync launcher.\n3. It merges each account's roster into the others.\n4. Log in; every account sees every character.\n\nShared balances are counted once per account.")
    end)

    -- Help
    Label(bodies.Help, "TRIALS", 0, 0, 660, 11, GOLD)
    Label(bodies.Help, "Champion best: your best solo damage-Trial score.\nClass rank: last-observed rank among your class, not the entire roster.\nCrusader best: highest survival wave reached, with elapsed time.\nTeam: how many players were in that recorded attempt (1-5).", 0, 22, 660, 11)
    Label(bodies.Help, "TORMENT & LOOT", 0, 130, 660, 11, GOLD)
    Label(bodies.Help, "Torment is the new Hardcore ladder. Unlocks are account-wide.\nAvailable: this character can still loot the boss this week.\nLooted: loot already received; entering and killing are still allowed.\nUnknown: the snapshot is stale; log in on that character to refresh.\nTracked (dungeons): on your watchlist; no weekly lockout is assumed.", 0, 152, 660, 11)

    Button(settings, "Reset section", 582, 558, 140, 30, function()
        local section = settings.current
        Dialog("Reset " .. section, "Restore the default settings for '" .. section .. "'?", {
            primary = "Reset", onAccept = function()
                if section == "Themes" or section == "Colors" then ApplyPreset(THEMES[1])
                elseif section == "Text & Layout" then
                    state.font, state.fontDelta, state.density, state.scale, BACKGROUND[4] = FONT, 0, "comfortable", 1, 0.99
                    frame:SetScale(frame.baseScale or 1)
                    ApplyAppearance()
                elseif section == "Icons" then
                    state.iconStyle, state.statusStyle, state.classIcons, state.logo = "icons", "words", true, LOGOS[1]
                    ApplyAppearance()
                end
                Say(section .. " reset.")
            end,
        })
    end)
    Button(settings, "Close", 732, 558, 152, 30, function() settings:Hide() end)
    settings.ShowSection = function(section)
        if not bodies[section] then section = "Themes" end
        settings.current = section
        for _, entry in ipairs(SECTIONS) do
            local name = entry[1]
            SetVisible(bodies[name], name == section)
            navButtons[name]:SetBackdropBorderColor(unpack(name == section and GOLD or BUTTON_BORDER))
            navButtons[name].text:SetTextColor(unpack(name == section and GOLD or TEXT))
            if name == section then
                settings.sectionTitle:SetText(string.upper(name))
                settings.sectionText:SetText(entry[2])
            end
        end
        for _, group in ipairs(settings.groups) do group.Update() end
        if bodies[section].Refresh then bodies[section].Refresh() end
    end
    settings:SetScript("OnHide", function()
        if dialog then dialog:Hide() end
        if palette then palette:Hide() end
    end)
    settings:Hide()
end

ShowSettings = function(section)
    if accountMenu then accountMenu:Hide() end
    if not settings then BuildSettings() end
    settings:SetScale(frame.baseScale or frame:GetScale())
    settings.ShowSection(section or settings.current or "Themes")
    settings:Show()
    settings:Raise()
end

local function BuildPreview()
    local catalog = ProjectEbonhold and ProjectEbonhold.RaidLockoutData
    if not catalog or #catalog == 0 then
        print("|cffff6060Ashoholic:|r UI preview needs ProjectEbonhold's raid catalogue. Update/enable the companion addon.")
        return
    end
    local expansionNames = { "Vanilla", "The Burning Crusade", "Wrath of the Lich King" }
    local categories = {}
    for _, name in ipairs({ "Raids", "Dungeons" }) do
        local category = { name = name, key = name, children = {}, bosses = {} }
        categories[name] = category
        trackingTree[#trackingTree + 1] = category
        state.expanded[name] = true
        for expansion = 3, 1, -1 do
            category.children[#category.children + 1] = {
                name = expansionNames[expansion], key = name .. ":" .. expansion,
                expansion = expansion, children = {}, bosses = {},
            }
        end
    end
    local function AddInstance(instance, kind, expansion)
        instance.kind = kind
        instance.key = kind .. ":" .. instance.map
        raids[#raids + 1] = instance
        local category = categories[kind]
        for _, group in ipairs(category.children) do
            if group.expansion == expansion then
                group.children[#group.children + 1] = instance
                for _, boss in ipairs(instance.bosses) do
                    group.bosses[#group.bosses + 1] = boss
                    category.bosses[#category.bosses + 1] = boss
                end
                return
            end
        end
    end
    for _, raid in ipairs(catalog) do
        local expansion = RAID_EXPANSIONS[raid.map]
        if not expansion then
            print("|cffff6060Ashoholic preview:|r No expansion mapping for " .. raid.name .. "; not included in the sample tree.")
        else
            AddInstance({ map = raid.map, name = raid.name, bosses = raid.bosses }, "Raids", expansion)
        end
        if raid.map == 533 or raid.map == 532 then
            for _, boss in ipairs(raid.bosses) do
                if boss.name == "Kel'Thuzad" or boss.name == "Sapphiron" or boss.name == "Nightbane" then
                    state.watched[boss.id] = true
                end
            end
            state.expanded["Raids:" .. raid.map] = true
            state.expanded["Raids:" .. expansion] = true
        end
    end
    for index, dungeon in ipairs(DUNGEONS) do
        local instance = { map = index, name = dungeon[2], bosses = {} }
        local bossIndex = 0
        for name in string.gmatch(dungeon[3], "[^;]+") do
            bossIndex = bossIndex + 1
            instance.bosses[#instance.bosses + 1] = { id = -(index * 100 + bossIndex), name = name }
        end
        AddInstance(instance, "Dungeons", dungeon[1])
    end
    for _, category in ipairs(trackingTree) do
        for _, expansion in ipairs(category.children) do
            table.sort(expansion.children, function(a, b) return a.name < b.name end)
        end
    end
    frame = CreateFrame("Frame", "AshoholicPreviewFrame", UIParent)
    frame:SetSize(1120, 720)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpack(BACKGROUND))
    frame:SetBackdropBorderColor(0.40, 0.31, 0.17, 1)
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetSize(900, 58)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() if not (state.mock and state.mock.lockWindow) then frame:StartMoving() end end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame.logo = titleBar:CreateTexture(nil, "ARTWORK")
    frame.logo:SetPoint("TOPLEFT", 24, -12)
    frame.logo:SetSize(30, 30)
    frame.logo:SetTexture(state.logo)
    Label(titleBar, "ASHOHOLIC", 62, 15, 230, 24, GOLD)
    Label(titleBar, "A new chapter for your roster", 282, 24, 400, 12, MUTED)
    local settingsButton = Button(frame, "Settings", 948, 14, 115, 28, function() ShowSettings() end)
    settingsButton:SetFrameLevel(titleBar:GetFrameLevel() + 5)
    Button(frame, "X", 1076, 14, 28, 28, function() frame:Hide() end)
    tinsert(UISpecialFrames, "AshoholicPreviewFrame")
    local banner = Surface(frame, 24, 60, 1072, 33, { 0.18, 0.13, 0.065, 1 })
    Label(banner, "DESIGN PREVIEW  /  All balances, characters, timers and eligibility are sample data. Nothing is sent or saved.", 12, 10, 1048, 11, GOLD)
    local accountButton = Button(frame, "", 864, 105, 232, 30, function()
        if settings then settings:Hide() end
        SetVisible(accountMenu, not accountMenu:IsShown())
    end)
    Tip(accountButton, "Accounts to display", "Check any combination of accounts. The first view uses the current sample account. Selection lasts until reload in this UI-only preview.")
    accountMenu = Surface(frame, 800, 139, 296, 98 + (#ACCOUNTS + 1) * 31)
    accountMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    accountMenu:EnableMouse(true)
    Label(accountMenu, "SHOW ACCOUNTS", 12, 12, 270, 11, GOLD)
    local checks = {}
    local function CheckedCount()
        local count = 0
        for i = 1, #ACCOUNTS do if state.accounts[i] then count = count + 1 end end
        return count
    end
    local function FilterChanged()
        local characters = VisibleCharacters()
        if not state.accounts[CHARACTERS[state.selected].account] and characters[1] then state.selected = characters[1].index end
        state.matrixOffset = 0
        refresh()
    end
    for i = 0, #ACCOUNTS do
        local id = i
        local check = CreateFrame("CheckButton", nil, accountMenu, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 10, -(35 + i * 31))
        check:SetSize(26, 26)
        check.label = Label(check, "", 30, 7, 234, 11)
        check:SetScript("OnClick", function(self)
            if id == 0 then
                local all = self:GetChecked() and true or false
                for accountId = 1, #ACCOUNTS do state.accounts[accountId] = all end
            else state.accounts[id] = self:GetChecked() and true or false end
            FilterChanged()
        end)
        checks[i] = check
    end
    Button(accountMenu, "Done", 178, 45 + (#ACCOUNTS + 1) * 31, 106, 28, function() accountMenu:Hide() end)
    accountMenu:Hide()
    local tabOrder = { "Roster", "Raids", "Activities", "Progression", "Trials" }
    for i, name in ipairs(tabOrder) do
        local tabName = name
        tabs[name] = Button(frame, name == "Raids" and "Raids & Dungeons" or name, 24 + (i - 1) * 158, 105, 148, 30, function()
            state.tab = tabName
            refresh()
        end)
    end
    local definitions = {
        { "SOUL ASH", "ash", "Banked, once per account", "inv_soulash" },
        { "SOUL SHARDS", "shards", "Banked; run shards excluded", "inv_10_jewelcrafting3_soulcage_frost" },
        { "SOUL ESSENCE", "essence", "Persistent Prestige currency", "inv_misc_supersoulash" },
        { "ARTISAN SOUL", "artisan", "Persistent profession currency", "ability_argus_soulbombdebufflarge" },
        { "TOTAL GOLD", "gold", "Character pockets + Warband", "INV_Misc_Coin_02" },
    }
    for i, definition in ipairs(definitions) do
        local card = Surface(frame, 24 + (i - 1) * 218, 153, 200, 78)
        card.title = Label(card, "", 12, 9, 176, 10, MUTED)
        card.value = Label(card, "", 12, 30, 176, 22, i == 5 and GOLD or TEAL)
        Label(card, definition[3], 12, 60, 178, 9, MUTED)
        Tip(card, definition[1], definition[3] .. ". Totals combine the selected sample accounts, counting each account once. Preview balances are invented; this does not query your currencies.")
        cards[i] = card
    end
    BuildRoster()
    BuildRaids()
    BuildActivities()
    BuildProgression()
    BuildTrials()
    Label(frame, "PREVIEW ONLY  /  /ash opens your existing roster. Escape closes this window.", 24, 690, 800, 11, MUTED)
    Label(frame, "EBONHOLD / CONCEPT 01", 869, 690, 227, 10, GOLD)
    refresh = function()
        local count = CheckedCount()
        local filterText = count == #ACCOUNTS and "All Accounts" or (count == 0 and "No accounts selected" or count .. " accounts selected")
        if count == 1 then
            for i, account in ipairs(ACCOUNTS) do if state.accounts[i] then filterText = account.name end end
        end
        accountButton.text:SetText(filterText .. "  v")
        checks[0]:SetChecked(count == #ACCOUNTS)
        checks[0].label:SetText("All Accounts")
        for i, account in ipairs(ACCOUNTS) do
            checks[i]:SetChecked(state.accounts[i])
            checks[i].label:SetText(account.name .. (i == 1 and " (current)" or ""))
        end
        local totals = { ash = 0, shards = 0, essence = 0, artisan = 0, gold = 0, pockets = 0, warband = 0 }
        for accountId, account in ipairs(ACCOUNTS) do
            if state.accounts[accountId] then
                for _, key in ipairs({ "ash", "shards", "essence", "artisan" }) do totals[key] = totals[key] + account[key] end
                totals.pockets = totals.pockets + account.gold
                totals.warband = totals.warband + account.warband
            end
        end
        totals.gold = totals.pockets + totals.warband
        for i, definition in ipairs(definitions) do
            local amount = totals[definition[2]]
            cards[i].value:SetText(i == 5 and string.format("%dg", amount) or Short(amount))
            local size = state.iconStyle == "large" and 22 or 16
            cards[i].title:SetText(state.iconStyle == "text" and definition[1]
                or string.format("|TInterface\\Icons\\%s:%d|t %s", definition[4], size, definition[1]))
        end
        Tip(cards[1], "Account Soul Ash", "Sample banked balance. Run earnings are shown only on characters. Banked and spendable are distinct; a future live view would show both.")
        Tip(cards[2], "Account Soul Shards", "Sample banked Shards. Do not count this shared balance again for every character.")
        Tip(cards[5], "Gold breakdown", string.format("Character pockets: %dg\nWarband bank: %dg\nTotal: %dg\nWarband gold is counted once per account.", totals.pockets, totals.warband, totals.gold))
        if state.hiddenTabs[state.tab] then state.tab = "Roster" end
        local tabX = 24
        for _, name in ipairs(tabOrder) do
            local shown = not state.hiddenTabs[name]
            SetVisible(tabs[name], shown)
            if shown then
                tabs[name]:ClearAllPoints()
                tabs[name]:SetPoint("TOPLEFT", tabX, -105)
                tabX = tabX + 158
            end
        end
        for name, page in pairs(pages) do
            local active = state.tab == name
            SetVisible(page, active)
            tabs[name]:SetBackdropBorderColor(unpack(active and GOLD or BUTTON_BORDER))
            tabs[name].text:SetTextColor(unpack(active and GOLD or MUTED))
            if active then page.Refresh() end
        end
    end
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
        GameTooltip:Hide()
        if settings then settings:Hide() end
        accountMenu:Hide()
    end)
end

function addon:TogglePreviewUI()
    if not frame then
        BuildPreview()
        if not frame then return end
        frame:Hide()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        local scale = math.min(1, (UIParent:GetWidth() - 32) / 1120, (UIParent:GetHeight() - 32) / 720)
        frame.baseScale = math.max(0.1, scale)
        frame:SetScale(frame.baseScale * state.scale)
        if state.openTab and state.openTab ~= "last" then state.tab = state.openTab end
        refresh()
        frame:Show()
    end
end
