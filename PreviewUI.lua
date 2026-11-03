local addonName = ...
local addon = _G[addonName]

-- The preview owns only session-local sample data; it never reads or writes the roster.
-- /ash preview: Settings previews appearance, columns and account aliases.
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
local state = { accounts = { [1] = true }, selected = 1, tab = "Roster", watched = {}, expanded = {}, collapsed = {}, matrixPage = 1, detail = true }
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
    fs:SetFont(FONT, size or 12)
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
    panel:SetBackdropColor(unpack(color or { 0.075, 0.083, 0.105, 1 }))
    panel:SetBackdropBorderColor(0.19, 0.21, 0.26, 1)
    return panel
end

local function Button(parent, text, x, y, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", x, -y)
    button:SetSize(width, height or 28)
    button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    button:SetBackdropColor(0.10, 0.115, 0.145, 1)
    button:SetBackdropBorderColor(0.24, 0.26, 0.31, 1)
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
    return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, character.name)
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
    Button(page, "Columns / layout", 548, 0, 168, 26, function() ShowSettings("Columns") end)
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
    Button(detail, "Customize columns / detail panel", 16, 317, 300, 25, function() ShowSettings("Columns") end)
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
                y = y + 28
            end
            for i, character in ipairs(CHARACTERS) do
                if character.account == accountId then
                    local row = page.rows[i]
                    SetVisible(row, show and not state.collapsed[accountId])
                    if show and not state.collapsed[accountId] then
                        row:SetWidth(width)
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", 0, -y)
                        row:SetBackdropBorderColor(unpack(i == state.selected and GOLD or { 0.19, 0.21, 0.26 }))
                        for j, fs in ipairs(row.cells) do
                            PositionCell(fs, j, 8)
                            fs:SetText(j == 1 and ClassName(character) or tostring(character[columnOrder[j - 1]] or "Unknown"))
                        end
                        row.hint:SetText(character.action)
                        y = y + 47
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
    if character.stale then return DIM .. "Unknown|r" end
    if instance.kind == "Dungeons" then return "|cff6edbc7Tracked|r" end
    if character.level < 80 then return DIM .. "Not ready|r" end
    if (boss.id + index) % 3 == 0 then return DIM .. "Looted|r" end
    return GREEN .. "Available|r"
end

local function BuildRaids()
    local page = Page("Raids", "Raid & dungeon watchlist", "Select a category, expansion, instance or individual boss. All statuses are sample data.")
    Label(page, "WATCHED ENCOUNTERS", 0, 61, 360, 10, GOLD)
    local matrixScroll, matrix = Scroll(page, "AshoholicPreviewRaidMatrix", 0, 135, 716, 240)
    local header = Surface(page, 0, 84, 690, 47)
    Label(header, "ENCOUNTER", 7, 26, 198, 10, MUTED)
    local headerCells = {}
    for i = 1, 5 do
        headerCells[i] = {
            account = Label(header, "", 210 + (i - 1) * 95, 6, 92, 9, GOLD),
            name = Label(header, "", 210 + (i - 1) * 95, 26, 92, 11),
        }
        for _, fs in pairs(headerCells[i]) do
            fs:SetHeight(14)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
        end
    end
    Button(page, "<", 442, 52, 28, 26, function()
        state.matrixPage = math.max(1, state.matrixPage - 1)
        page.Refresh()
    end)
    local pageNumber = Label(page, "", 478, 61, 190, 10, MUTED)
    Button(page, ">", 682, 52, 28, 26, function()
        state.matrixPage = math.min(math.max(1, math.ceil(#VisibleCharacters() / 5)), state.matrixPage + 1)
        page.Refresh()
    end)
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
            for j = 1, 5 do
                row.cells[j] = Label(row, "", 210 + (j - 1) * 95, 7, 92, 10)
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
        local maxPage = math.max(1, math.ceil(#allCharacters / 5))
        state.matrixPage = math.min(state.matrixPage, maxPage)
        local characters = {}
        for i = 1, 5 do
            local character = allCharacters[(state.matrixPage - 1) * 5 + i]
            characters[i] = character
            headerCells[i].account:SetText(character and ACCOUNTS[character.data.account].name or "")
            headerCells[i].name:SetText(character and ClassName(character.data) or "")
        end
        pageNumber:SetText("Characters: page " .. state.matrixPage .. " / " .. maxPage)
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
        matrix:SetHeight(math.max(240, y))
        matrixScroll:SetVerticalScroll(math.min(matrixScroll:GetVerticalScroll(), math.max(0, y - 240)))
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
    local scroll, body = Scroll(page, "AshoholicPreviewProgressionScroll", 0, 57, 1072, 345)
    local ladder = Surface(body, 0, 0, 510, 345)
    Label(ladder, "ACCOUNT TORMENT UNLOCKS", 16, 17, 478, 11, GOLD)
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
        local panel = Surface(body, 530, 0, 510, 160)
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
                panel:SetPoint("TOPLEFT", 530, -y)
                y = y + 177
            end
        end
        body:SetHeight(math.max(345, y))
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, y - 345)))
    end
end

local function BuildTrials()
    local page = Page("Trials", "Personal records", "Compare saved bests across your roster. Rankings are last-observed snapshots, not live standings.")
    local headings = { { "CHARACTER", 16 }, { "CHAMPION BEST", 205 }, { "CLASS RANK", 409 }, { "CRUSADER BEST", 575 }, { "TEAM", 797 }, { "UPDATED", 912 } }
    for _, column in ipairs(headings) do Label(page, column[1], column[2], 68, 190, 10, MUTED) end
    Button(page, "What are these Trials?", 845, 0, 227, 26, function()
        ShowSettings("Trials")
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

local function BuildSettings()
    settings = Surface(frame, 180, 95, 760, 550)
    settings:SetFrameStrata("FULLSCREEN_DIALOG")
    settings:EnableMouse(true)
    Label(settings, "Ashoholic / Settings", 20, 18, 660, 21, GOLD)
    Label(settings, "Interactive concept. Changes last until reload; no real settings are modified.", 20, 51, 720, 11, MUTED)
    Button(settings, "X", 714, 14, 28, 26, function() settings:Hide() end)
    local bodies, sectionButtons = {}, {}
    local sections = { "Appearance", "Columns", "Accounts", "Sync", "Trials" }
    for i, name in ipairs(sections) do
        local section = name
        sectionButtons[name] = Button(settings, name, 20 + (i - 1) * 144, 82, 136, 28, function() ShowSettings(section) end)
        local body = CreateFrame("Frame", nil, settings)
        body:SetPoint("TOPLEFT", 20, -127)
        body:SetSize(720, 360)
        bodies[name] = body
    end
    local appearance = bodies.Appearance
    Label(appearance, "THEME", 0, 0, 700, 12, GOLD)
    local presets = {
        { "Ember & Ash", { 0.035, 0.042, 0.058, 0.99 }, { 1, 0.79, 0.39 } },
        { "Frostbound", { 0.025, 0.07, 0.12, 0.99 }, { 0.45, 0.8, 1 } },
        { "Void Walker", { 0.075, 0.025, 0.12, 0.99 }, { 0.8, 0.55, 1 } },
    }
    for i, preset in ipairs(presets) do
        local theme = preset
        Button(appearance, preset[1], (i - 1) * 240, 32, 225, 32, function()
            frame:SetBackdropColor(unpack(theme[2]))
            frame:SetBackdropBorderColor(unpack(theme[3]))
            for _, card in ipairs(cards) do
                card:SetBackdropBorderColor(unpack(theme[3]))
                card.value:SetTextColor(unpack(theme[3]))
            end
            settings.themeName:SetText("Selected: " .. theme[1] .. " (preview frame and currency accents)")
        end)
    end
    settings.themeName = Label(appearance, "Selected: Ember & Ash", 0, 85, 700, 12)
    Label(appearance, "WINDOW OPACITY", 0, 135, 700, 12, GOLD)
    local opacity = CreateFrame("Slider", nil, appearance)
    opacity:SetPoint("TOPLEFT", 0, -170)
    opacity:SetSize(470, 18)
    opacity:SetOrientation("HORIZONTAL")
    opacity:SetMinMaxValues(0.55, 1)
    opacity:SetValueStep(0.05)
    opacity:SetBackdrop({ bgFile = WHITE })
    opacity:SetBackdropColor(0.15, 0.17, 0.21, 1)
    opacity:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    opacity:SetValue(1)
    local opacityText = Label(appearance, "100%", 490, 170, 150, 12)
    opacity:SetScript("OnValueChanged", function(_, value)
        frame:SetAlpha(value)
        opacityText:SetText(string.format("%.0f%%", value * 100))
    end)
    Label(appearance, "This concept previews presets and opacity. Full theme colors/fonts can reuse the existing theme editor when the design is settled.", 0, 225, 700, 12, MUTED)

    local columnBody = bodies.Columns
    Label(columnBody, "Choose up to six columns beside Name. Use < / > to reorder selected columns.", 0, 0, 700, 12, GOLD)
    local columnButtons = {}
    local function ColumnIndex(key)
        for i, selected in ipairs(columnOrder) do if selected == key then return i end end
    end
    local function RefreshColumns()
        for i, column in ipairs(columns) do
            local index = ColumnIndex(column.key)
            columnButtons[i].text:SetText((index and "[x] " .. index .. ". " or "[ ] ") .. column.title)
        end
        settings.detailButton.text:SetText((state.detail and "[x] " or "[ ] ") .. "Show parked-run detail panel")
        refresh()
    end
    local columnNotice = Label(columnBody, "", 0, 315, 700, 11, GOLD)
    for i, column in ipairs(columns) do
        local key = column.key
        local x, y = ((i - 1) % 2) * 360, 35 + math.floor((i - 1) / 2) * 38
        columnButtons[i] = Button(columnBody, "", x, y, 254, 28, function()
            local index = ColumnIndex(key)
            columnNotice:SetText("")
            if index then table.remove(columnOrder, index)
            elseif #columnOrder < 6 then columnOrder[#columnOrder + 1] = key
            else columnNotice:SetText("Six columns are selected. Uncheck one before adding another."); return end
            RefreshColumns()
        end)
        for direction = -1, 1, 2 do
            local step = direction
            Button(columnBody, direction == -1 and "<" or ">", x + (direction == -1 and 262 or 304), y, 34, 28, function()
                local index = ColumnIndex(key)
                if index and index + step >= 1 and index + step <= #columnOrder then
                    columnOrder[index], columnOrder[index + step] = columnOrder[index + step], columnOrder[index]
                    RefreshColumns()
                else columnNotice:SetText("Select this column first; only selected columns can move within the list.") end
            end)
        end
    end
    settings.detailButton = Button(columnBody, "", 0, 273, 420, 28, function()
        state.detail = not state.detail
        RefreshColumns()
    end)
    Label(columnBody, "Offering bonus, offerings, build and anchor can be columns too; hiding the panel gives the roster more width.", 0, 342, 700, 11, MUTED)

    local accounts = bodies.Accounts
    Label(accounts, "CURRENT ACCOUNT (sample account 1)", 0, 0, 700, 12, GOLD)
    Label(accounts, "Default: Account One. An alias is optional and does not change account identity.", 0, 30, 700, 12, MUTED)
    local input = CreateFrame("EditBox", nil, accounts, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", 8, -70)
    input:SetSize(440, 28)
    input:SetAutoFocus(false)
    input:SetMaxLetters(32)
    local notice = Label(accounts, "", 0, 152, 700, 12, TEAL)
    local function Rename(name)
        name = name:match("^%s*(.-)%s*$")
        if name == "" then notice:SetText("Enter a name, or use Restore default."); return end
        if name:find("|", 1, true) or name:find("[%c]") then notice:SetText("Use a plain-text name without control codes or |."); return end
        ACCOUNTS[1].name = name
        input:SetText(name)
        input:ClearFocus()
        notice:SetText("Preview alias updated everywhere. No real account data was changed.")
        refresh()
    end
    Button(accounts, "Rename current account", 0, 112, 225, 28, function() Rename(input:GetText()) end)
    Button(accounts, "Restore default", 240, 112, 200, 28, function() Rename(ACCOUNTS[1].originalName) end)
    input:SetScript("OnEnterPressed", function() Rename(input:GetText()) end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Label(accounts, "The live version should use the actual account name by default and store an optional alias, independently of filter selections.\n\nPreview accounts are fictional. Account 1 represents the account you are playing on. Filter choices survive switching tabs and closing this preview, but not /reload.", 0, 205, 700, 12, MUTED)
    bodies.Accounts.Refresh = function() input:SetText(ACCOUNTS[1].name) end
    bodies.Columns.Refresh = RefreshColumns
    Label(bodies.Sync, "MULTI-ACCOUNT SYNC", 0, 0, 700, 14, GOLD)
    Label(bodies.Sync, "The real addon already supports local SavedVariables merging through its launcher/scripts.\n\nThis preview demonstrates four accounts; it does not read other accounts, run scripts or modify sync configuration. Account filtering, grouping and scrollable views are not limited to two accounts.", 0, 39, 700, 13)
    local syncNotice = Label(bodies.Sync, "", 0, 205, 700, 12, TEAL)
    Button(bodies.Sync, "Simulate sync status", 0, 153, 230, 28, function()
        syncNotice:SetText("Sample sync complete: 4 accounts / " .. #CHARACTERS .. " characters. No files were accessed.")
    end)
    Label(bodies.Trials, "TWO DIFFERENT TRIALS", 0, 0, 700, 14, GOLD)
    Label(bodies.Trials, "Champion best: your best solo damage-Trial score.\nClass rank: last-observed rank among your class, not the entire roster.\n\nCrusader best: highest survival-wave result, with elapsed time.\nTeam: how many players were in that recorded attempt (1-5).\n\nPractice/checkpoint attempts should not count as ranked records. Rankings need a timestamp and season; they can become stale.\n\nThese are the special Trials, not ordinary dungeon or raid completion records.", 0, 40, 700, 13)
    Button(settings, "Done", 594, 505, 146, 28, function() settings:Hide() end)
    settings.ShowSection = function(section)
        for name, body in pairs(bodies) do
            SetVisible(body, name == section)
            sectionButtons[name]:SetBackdropBorderColor(unpack(name == section and GOLD or { 0.24, 0.26, 0.31 }))
        end
        if bodies[section].Refresh then bodies[section].Refresh() end
    end
    settings:Hide()
end

ShowSettings = function(section)
    if accountMenu then accountMenu:Hide() end
    if not settings then BuildSettings() end
    settings.ShowSection(section or "Appearance")
    settings:Show()
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
    frame:SetBackdropColor(0.035, 0.042, 0.058, 0.99)
    frame:SetBackdropBorderColor(0.40, 0.31, 0.17, 1)
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetSize(1075, 58)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    Label(titleBar, "ASHOHOLIC", 24, 15, 230, 24, GOLD)
    Label(titleBar, "A new chapter for your roster", 244, 24, 400, 12, MUTED)
    Button(frame, "Settings", 948, 14, 115, 28, function() ShowSettings("Appearance") end)
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
        state.matrixPage = 1
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
        { "|TInterface\\Icons\\inv_soulash:16|t SOUL ASH", "ash", "Banked, once per account" },
        { "|TInterface\\Icons\\inv_10_jewelcrafting3_soulcage_frost:16|t SOUL SHARDS", "shards", "Banked; run shards excluded" },
        { "|TInterface\\Icons\\inv_misc_supersoulash:16|t SOUL ESSENCE", "essence", "Persistent Prestige currency" },
        { "|TInterface\\Icons\\ability_argus_soulbombdebufflarge:16|t ARTISAN SOUL", "artisan", "Persistent profession currency" },
        { "TOTAL GOLD", "gold", "Character pockets + Warband" },
    }
    for i, definition in ipairs(definitions) do
        local card = Surface(frame, 24 + (i - 1) * 218, 153, 200, 78)
        Label(card, definition[1], 12, 11, 176, 10, MUTED)
        card.value = Label(card, "", 12, 30, 176, 22, i == 5 and GOLD or TEAL)
        Label(card, definition[3], 12, 60, 178, 9, MUTED)
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
        end
        Tip(cards[1], "Account Soul Ash", "Sample banked balance. Run earnings are shown only on characters. Banked and spendable are distinct; a future live view would show both.")
        Tip(cards[2], "Account Soul Shards", "Sample banked Shards. Do not count this shared balance again for every character.")
        Tip(cards[5], "Gold breakdown", string.format("Character pockets: %dg\nWarband bank: %dg\nTotal: %dg\nWarband gold is counted once per account.", totals.pockets, totals.warband, totals.gold))
        for name, page in pairs(pages) do
            local active = state.tab == name
            SetVisible(page, active)
            tabs[name]:SetBackdropBorderColor(unpack(active and GOLD or { 0.24, 0.26, 0.31 }))
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
        frame:SetScale(math.max(0.1, scale))
        refresh()
        frame:Show()
    end
end
