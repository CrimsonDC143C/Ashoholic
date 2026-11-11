local addonName = ...
local addon = _G[addonName]

-- The preview owns only session-local sample data; it never reads or writes the roster.
-- /ash preview: Settings previews themes, colors, fonts, icons, columns, tabs, accounts, alerts and profiles.
-- Account filters, collapsed groups and layout choices survive closing, but not /reload.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"
local WINDOW_WIDTH = 1320
local CONTENT_WIDTH = WINDOW_WIDTH - 48
local SCROLLBAR_WIDTH = 26
local SCROLL_WIDTH = CONTENT_WIDTH - SCROLLBAR_WIDTH
local PANEL_GAP = 20
local HALF_PANEL_WIDTH = (SCROLL_WIDTH - PANEL_GAP) / 2
local PAGE_TOP = 207
local PAGE_HEIGHT = 465
local FOCUS_PAGE_TOP = 110
local FOCUS_HEIGHT_GAIN = PAGE_TOP - FOCUS_PAGE_TOP
local TAB_TOP = 60
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
    { name = "Account Four", ash = 6400000, shards = 63000, essence = 4, artisan = 32, gold = 5100, warband = 1800, prestige = 4 },
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
    { "Fable", "HUNTER", 1 }, { "Wisp", "ROGUE", 1 }, { "Anvil", "WARRIOR", 1 },
    { "Dusk", "WARLOCK", 1 }, { "Rime", "DEATHKNIGHT", 1 },
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
    matrixOffset = 0, detail = true, rosterFocus = false, raidsFocus = false, font = FONT, fontDelta = 0, density = "comfortable",
    iconStyle = "icons", classIcons = true, statusStyle = "words", hiddenTabs = {}, defaultTab = "Roster",
    logo = "Interface\\Icons\\inv_soulash", scale = 1, opacity = 1,
    columnWidths = {}, rosterOffset = 0, encounterCollapsed = {}, fontRoles = {},
    rowGap = 3, borderSize = 1, rosterSort = {},
}
-- Mutated in place by the theme preview so every widget sharing them follows the theme.
local PANEL = { 0.075, 0.083, 0.105, 1 }
local BORDER = { 0.19, 0.21, 0.26, 1 }
local BUTTON_BG = { 0.10, 0.115, 0.145, 1 }
local BUTTON_BORDER = { 0.24, 0.26, 0.31, 1 }
local BACKGROUND = { 0.035, 0.042, 0.058, 0.99 }
local STYLE = {
    titleText = { 1, 0.79, 0.39 }, headerText = { 0.58, 0.61, 0.67 },
    rowText = { 0.88, 0.88, 0.90 }, accountText = { 0.88, 0.88, 0.90 },
    rowOdd = { 0.10, 0.115, 0.145, 1 }, rowEven = { 0.12, 0.135, 0.165, 1 },
    rowAccount = { 0.075, 0.083, 0.105, 1 }, rowHover = { 1, 0.8, 0.4, 0.09 },
    selectedBorder = { 1, 0.79, 0.39, 1 }, buttonText = { 0.88, 0.88, 0.90 },
    buttonHover = { 1, 0.8, 0.4, 0.09 }, tabBg = { 0.10, 0.115, 0.145, 1 },
    tabActiveBg = { 0.075, 0.083, 0.105, 1 }, tabText = { 0.58, 0.61, 0.67 },
    tabActiveText = { 1, 0.79, 0.39 },
}
local surfaces, buttons, labels, progressFills = {}, {}, {}, {}
local settings, accountMenu
local ShowSettings, Dialog
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

local function FontFor(role, size)
    local override = state.fontRoles[role] or {}
    return override.font or state.font, math.max(8, size + state.fontDelta + (override.delta or 0))
end

local function Label(parent, text, x, y, width, size, color, role)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    role = role or ((size or 12) >= 17 and "title" or (color == MUTED and "hint" or "body"))
    if role == "title" and color == GOLD then color = STYLE.titleText end
    fs:SetFont(FontFor(role, size or 12))
    labels[#labels + 1] = { fs, color or TEXT, size or 12, role }
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
    surfaces[#surfaces + 1] = { panel, color or PANEL }
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
    button:GetHighlightTexture():SetVertexColor(unpack(STYLE.buttonHover))
    button.text = Label(button, text, 9, 7, width - 18, 11, STYLE.buttonText, "button")
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
    scroll:SetSize(width - SCROLLBAR_WIDTH, height)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width - SCROLLBAR_WIDTH, height)
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
    progressFills[#progressFills + 1] = fill
    return track, fill
end

local function VisibleCharacters()
    local result = {}
    for accountId = 1, #ACCOUNTS do
        if state.accounts[accountId] then
            for i, character in ipairs(CHARACTERS) do
                if character.account == accountId then result[#result + 1] = { index = i, data = character } end
            end
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
    page:SetPoint("TOPLEFT", 24, -PAGE_TOP)
    page:SetSize(CONTENT_WIDTH, PAGE_HEIGHT)
    Label(page, heading, 0, 0, 720, 17, GOLD)
    Label(page, subtitle, 0, 27, CONTENT_WIDTH, 11, MUTED)
    pages[name] = page
    return page
end

local function DetailLine(parent, title, value, y)
    Label(parent, title, 16, y, 168, 11, MUTED)
    local fs = Label(parent, value, 184, y, parent:GetWidth() - 200, 11)
    fs:SetJustifyH("RIGHT")
    return fs
end

local function PreviewSwap(character)
    Dialog("Swap to " .. character.name, "Preview only: this fictional character cannot be selected. In the live roster, Swap uses FastSwap for characters on the current account. Other accounts require logging in separately. No logout was requested.")
end

local function RosterSortValue(character, key)
    if key == "character" then return string.lower(character.name) end
    local value = character[key]
    if type(value) == "number" then return value end
    if not value or value == "Unknown" or value == "Sample" then return nil end
    if key == "seen" then
        if value == "Just now" then return 0 end
        if value == "Today" then return 12 * 60 end
        if value == "Yesterday" then return 24 * 60 end
        local number, unit = value:match("^(%d+)%s+(%a+)")
        local minutes = { min = 1, hour = 60, hours = 60, day = 1440, days = 1440 }
        return number and minutes[unit] and tonumber(number) * minutes[unit] or nil
    end
    if key == "runAsh" or key == "gold" or key == "bonus" or key == "offerings" then
        value = value:gsub(",", "")
        local number, suffix = value:match("([%d%.]+)%s*([kKmM]?)")
        if not number then return nil end
        local multiplier = ({ k = 1000, m = 1000000 })[string.lower(suffix)] or 1
        return tonumber(number) * multiplier
    end
    return string.lower(tostring(value))
end

local function SortedAccountCharacters(accountId)
    local result = {}
    for i, character in ipairs(CHARACTERS) do
        if character.account == accountId then result[#result + 1] = i end
    end
    table.sort(result, function(left, right)
        for _, sort in ipairs(state.rosterSort) do
            local a = RosterSortValue(CHARACTERS[left], sort.key)
            local b = RosterSortValue(CHARACTERS[right], sort.key)
            if a ~= b then
                -- Unknown snapshots stay last in either direction.
                if a == nil then return false end
                if b == nil then return true end
                if sort.ascending then return a < b end
                return a > b
            end
        end
        return left < right
    end)
    return result
end

local function CycleRosterSort(key)
    for i, sort in ipairs(state.rosterSort) do
        if sort.key == key then
            if sort.ascending then sort.ascending = false
            else table.remove(state.rosterSort, i) end
            return
        end
    end
    if #state.rosterSort == 2 then state.rosterSort = {} end
    state.rosterSort[#state.rosterSort + 1] = { key = key, ascending = true }
end

local function BuildRoster()
    local page = Page("Roster", "Your next adventure", "Characters first. Shared currencies stay at account level; run earnings stay with the character.")
    local focusButton = Button(page, "Focus roster", CONTENT_WIDTH - 140, 0, 140, 26, function()
        state.rosterFocus = not state.rosterFocus
        refresh()
    end)
    Tip(focusButton, "Roster Focus view", "Preview only. Temporarily hide the currency cards and use compact rows for more characters. Exit Focus restores your normal layout and density.")
    local headerScroll = CreateFrame("ScrollFrame", nil, page)
    headerScroll:SetPoint("TOPLEFT", 0, -57)
    headerScroll:SetSize(690, 23)
    local headerBody = CreateFrame("Frame", nil, headerScroll)
    headerBody:SetSize(690, 23)
    headerScroll:SetScrollChild(headerBody)
    local measure = Label(page, "", 0, 0, 0, 11)
    measure:Hide()
    local function Measure(text, size, role)
        measure:SetFont(FontFor(role, size))
        measure:SetText(text)
        return math.ceil(measure:GetStringWidth()) + 22
    end
    page.headers, page.grips, page.headerButtons = {}, {}, {}
    for i = 1, #columns + 1 do
        local header = CreateFrame("Button", nil, headerBody)
        header:SetHeight(23)
        header:SetScript("OnClick", function(self)
            CycleRosterSort(self.columnKey)
            page.Refresh()
        end)
        Tip(header, "Sort column", "Click: ascending, descending, then unsorted. Add a second column to break ties. A third distinct column starts a new sort. Sorting stays within each account; ^ / v show direction and 1 / 2 show priority.")
        page.headerButtons[i] = header
        page.headers[i] = Label(headerBody, "", 0, 4, 100, 10, STYLE.headerText, "header")
        page.headers[i]:SetHeight(16)
        if page.headers[i].SetWordWrap then page.headers[i]:SetWordWrap(false) end
        local grip = CreateFrame("Button", nil, headerBody)
        grip:SetFrameLevel(header:GetFrameLevel() + 1)
        grip:SetSize(8, 23)
        local line = grip:CreateTexture(nil, "OVERLAY")
        line:SetTexture(WHITE)
        line:SetSize(1, 16)
        line:SetPoint("CENTER")
        line:SetVertexColor(unpack(MUTED))
        Tip(grip, "Resize column", "Drag this header edge. Right-click to reset its default width. The minimum fits the widest sample value or header, including hidden accounts.")
        grip:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                self:SetScript("OnUpdate", nil)
                state.columnWidths[self.key] = nil
                page.Refresh()
                return
            end
            if button ~= "LeftButton" then return end
            self.startX = GetCursorPosition() / self:GetEffectiveScale()
            self.startWidth = self.width
            self:SetScript("OnUpdate", function(handle)
                state.columnWidths[handle.key] = math.max(handle.minimum,
                    handle.startWidth + GetCursorPosition() / handle:GetEffectiveScale() - handle.startX)
                page.Refresh()
            end)
        end)
        local function StopResize(self) self:SetScript("OnUpdate", nil) end
        grip:SetScript("OnMouseUp", StopResize)
        grip:SetScript("OnHide", StopResize)
        page.grips[i] = grip
    end
    local normalViewportHeight = PAGE_HEIGHT - 130
    local scroll, body = Scroll(page, "AshoholicPreviewRosterScroll", 0, 84, 716, normalViewportHeight)
    local hbar = CreateFrame("Slider", nil, page)
    hbar:SetPoint("TOPLEFT", 0, -(84 + normalViewportHeight + 4))
    hbar:SetSize(690, 10)
    hbar:SetOrientation("HORIZONTAL")
    hbar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    hbar:SetBackdropColor(unpack(BUTTON_BG))
    hbar:SetThumbTexture(WHITE)
    hbar:GetThumbTexture():SetSize(70, 10)
    hbar:GetThumbTexture():SetVertexColor(unpack(GOLD))
    hbar:SetValueStep(1)
    hbar:SetMinMaxValues(0, 0)
    hbar:SetValue(0)
    hbar:SetScript("OnValueChanged", function(_, value)
        state.rosterOffset = value
        headerScroll:SetHorizontalScroll(value)
        scroll:SetHorizontalScroll(value)
    end)
    local function ScrollRoster(_, delta)
        if IsShiftKeyDown() then
            local minimum, maximum = hbar:GetMinMaxValues()
            hbar:SetValue(math.max(minimum, math.min(maximum, hbar:GetValue() - delta * 40)))
        else
            ScrollBy(scroll, delta)
        end
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", ScrollRoster)
    headerScroll:EnableMouseWheel(true)
    headerScroll:SetScript("OnMouseWheel", ScrollRoster)
    page.rows = {}
    for i, character in ipairs(CHARACTERS) do
        local index = i
        local row = Button(body, "", 0, 0, 690, 44, function()
            state.selected = index
            refresh()
        end)
        row.cells = {}
        for j = 1, #columns + 1 do
            row.cells[j] = Label(row, "", 0, 8, 85, 11, STYLE.rowText, "character")
            row.cells[j]:SetHeight(14)
            if row.cells[j].SetWordWrap then row.cells[j]:SetWordWrap(false) end
        end
        row.hint = Label(row, "", 12, 27, 680, 10, MUTED)
        row.swap = Button(row, "Swap", 620, 5, 60, 24, function() PreviewSwap(character) end)
        Tip(row.swap, "Swap (preview)", "Simulate switching to this character. Never logs out or calls FastSwap with sample names.")
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
    local detail = Surface(page, WINDOW_WIDTH - 380, 56, 332, PAGE_HEIGHT - 66)
    page.detailTitle = Label(detail, "", 16, 16, 300, 17)
    page.detailLocation = Label(detail, "", 16, 42, 300, 11, MUTED)
    Label(detail, "PARKED RUN", 16, 75, 300, 10, GOLD)
    page.detailValues = {}
    local labels = { "Run Soul Ash", "Run Soul Shards", "Offering bonus", "Offerings remaining", "Echo build", "Soul anchor" }
    for i, title in ipairs(labels) do
        page.detailValues[i] = DetailLine(detail, title, "", 101 + (i - 1) * 28)
    end
    page.detailNote = Label(detail, "", 16, detail:GetHeight() - 76, 300, 11, TEAL)
    Button(detail, "Swap (preview)", 16, detail:GetHeight() - 37, 130, 25, function() PreviewSwap(CHARACTERS[state.selected]) end)
    local note = Label(page, "No hourly-entry counter: the new realm's cap has not been established.", 0, PAGE_HEIGHT - 29, SCROLL_WIDTH, 10, MUTED)
    page.Refresh = function()
        local viewportHeight = normalViewportHeight + (state.rosterFocus and FOCUS_HEIGHT_GAIN or 0)
        local density = state.rosterFocus and "compact" or state.density
        focusButton.text:SetText(state.rosterFocus and "Exit Focus" or "Focus roster")
        scroll:SetHeight(viewportHeight)
        hbar:ClearAllPoints()
        hbar:SetPoint("TOPLEFT", 0, -(84 + viewportHeight + 4))
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", 0, -(84 + viewportHeight + 17))
        local width = WINDOW_WIDTH - (state.detail and 430 or 74)
        scroll:SetWidth(width)
        headerScroll:SetWidth(width)
        hbar:SetWidth(width)
        SetVisible(detail, state.detail and state.accounts[CHARACTERS[state.selected].account])
        local layout, contentWidth = {}, 0
        for j = 1, #columnOrder + 1 do
            local key = j == 1 and "character" or columnOrder[j - 1]
            local title = "CHARACTER"
            for _, column in ipairs(columns) do if column.key == key then title = column.title end end
            local displayTitle = title
            for priority, sort in ipairs(state.rosterSort) do
                if sort.key == key then displayTitle = title .. (sort.ascending and " ^" or " v") .. priority end
            end
            local minimum = Measure(title .. " v2", 10, "header")
            for _, character in ipairs(CHARACTERS) do
                minimum = math.max(minimum, Measure(j == 1 and ClassName(character) or tostring(character[key] or "Unknown"), 11, "character"))
            end
            local cellWidth = math.max(minimum, state.columnWidths[key] or (j == 1 and 150 or 85))
            layout[j] = { x = contentWidth, width = cellWidth, key = key, minimum = minimum, title = displayTitle }
            contentWidth = contentWidth + cellWidth
        end
        contentWidth = math.max(width, contentWidth + 76)
        body:SetWidth(contentWidth)
        headerBody:SetWidth(contentWidth)
        local maximum = math.max(0, contentWidth - width)
        state.rosterOffset = math.min(state.rosterOffset, maximum)
        hbar:SetMinMaxValues(0, maximum)
        hbar:SetValue(state.rosterOffset)
        headerScroll:SetHorizontalScroll(state.rosterOffset)
        scroll:SetHorizontalScroll(state.rosterOffset)
        SetVisible(hbar, maximum > 0)
        local function PositionCell(fs, j, y)
            local cell = layout[j]
            SetVisible(fs, cell ~= nil)
            if not cell then return end
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", cell.x + 10, -y)
            fs:SetWidth(cell.width - 16)
        end
        for j, fs in ipairs(page.headers) do
            PositionCell(fs, j, 4)
            local cell, grip, header = layout[j], page.grips[j], page.headerButtons[j]
            SetVisible(grip, cell ~= nil)
            SetVisible(header, cell ~= nil)
            fs:SetText(cell and cell.title or "")
            if cell then
                header.columnKey = cell.key
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", cell.x, 0)
                header:SetWidth(cell.width - 4)
                grip.key, grip.minimum, grip.width = cell.key, cell.minimum, cell.width
                grip:ClearAllPoints()
                grip:SetPoint("TOPLEFT", cell.x + cell.width - 4, 0)
            end
        end
        local y = 0
        for accountId, account in ipairs(ACCOUNTS) do
            local accountLabel = page.accountLabels[accountId]
            local show = state.accounts[accountId]
            SetVisible(accountLabel, show)
            if show then
                accountLabel:ClearAllPoints()
                accountLabel:SetPoint("TOPLEFT", 0, -y)
                accountLabel:SetWidth(contentWidth)
                accountLabel.text:SetWidth(contentWidth - 18)
                accountLabel.text:SetText((state.collapsed[accountId] and "+ " or "- ") .. account.name .. (accountId == 1 and "  /  Current account" or ""))
                accountLabel:SetBackdropColor(unpack(STYLE.rowAccount))
                accountLabel.text:SetFont(FontFor("account", 11))
                accountLabel.text:SetTextColor(unpack(account.color or STYLE.accountText))
                y = y + 28
            end
            local rowHeight = state.rosterFocus and 30 or state.rowHeight
                or (density == "compact" and 30 or (density == "spacious" and 54 or 44))
            local _, characterSize = FontFor("character", 11)
            rowHeight = math.max(rowHeight, characterSize + (density == "compact" and 16 or 33))
            for position, i in ipairs(SortedAccountCharacters(accountId)) do
                local character = CHARACTERS[i]
                local row = page.rows[i]
                SetVisible(row, show and not state.collapsed[accountId])
                if show and not state.collapsed[accountId] then
                    row:SetWidth(contentWidth)
                    row.swap:ClearAllPoints()
                    row.swap:SetPoint("TOPRIGHT", -8, -5)
                    row.hint:SetWidth(contentWidth - 90)
                    row:SetHeight(rowHeight)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -y)
                    row:SetBackdropColor(unpack(position % 2 == 1 and STYLE.rowOdd or STYLE.rowEven))
                    row:GetHighlightTexture():SetVertexColor(unpack(STYLE.rowHover))
                    row:SetBackdropBorderColor(unpack(i == state.selected and STYLE.selectedBorder or BORDER))
                    for j, fs in ipairs(row.cells) do
                        PositionCell(fs, j, density == "spacious" and 11 or 8)
                        fs:SetHeight(characterSize + 3)
                        fs:SetText(j == 1 and ClassName(character) or tostring(character[columnOrder[j - 1]] or "Unknown"))
                    end
                    row.hint:SetText(character.action)
                    SetVisible(row.hint, density ~= "compact")
                    y = y + rowHeight + state.rowGap
                end
            end
        end
        body:SetHeight(math.max(viewportHeight, y))
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, y - viewportHeight)))
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

local MATRIX_FIRST, MATRIX_HEIGHT = 210, PAGE_HEIGHT - 194

local function RaidMetadata(raid)
    local details = {}
    if raid.ilvl then details[#details + 1] = "Normal ilvl " .. raid.ilvl end
    if raid.release then details[#details + 1] = "Release " .. raid.release end
    if #details == 0 then return nil end
    return table.concat(details, " / ")
end

local function BuildRaids()
    local page = Page("Raids", "Raid & dungeon watchlist", "Select a category, expansion, instance or individual boss. All statuses are sample data.")
    local pickerWidth = 332
    local pickerX = CONTENT_WIDTH - pickerWidth
    local matrixWithPicker = pickerX - 24 - SCROLLBAR_WIDTH
    local matrixColumns, matrixWidth = 5, 95
    local showPicker, compact = true, true
    local normalPickerHeight = PAGE_HEIGHT - 169
    local focusButton = Button(page, "Focus encounters", pickerX - 164, 0, 156, 26, function()
        state.raidsFocus = not state.raidsFocus
        refresh()
    end)
    Tip(focusButton, "Encounter Focus view", "Temporarily hide the currency cards to show more encounters and tracking choices. Your watchlist, column settings and account filters are kept.")
    local pickerToggle = Button(page, "Hide selection", pickerX, 0, 160, 26, function()
        showPicker = not showPicker
        page.Refresh()
    end)
    local compactToggle = Button(page, "Compact columns", pickerX + 168, 0, 164, 26, function()
        compact = not compact
        page.Refresh()
    end)
    Label(page, "WATCHED ENCOUNTERS", 0, 61, 360, 10, GOLD)
    local matrixScroll, matrix = Scroll(page, "AshoholicPreviewRaidMatrix", 0, 135, matrixWithPicker + SCROLLBAR_WIDTH, MATRIX_HEIGHT)
    local header = Surface(page, 0, 84, matrixWithPicker, 47)
    Label(header, "ENCOUNTER", 7, 26, 198, 10, MUTED)
    local headerCells = {}
    for i = 1, #CHARACTERS do
        headerCells[i] = {
            account = Label(header, "", MATRIX_FIRST + (i - 1) * matrixWidth, 6, matrixWidth - 6, 9, GOLD, "account"),
            name = Label(header, "", MATRIX_FIRST + (i - 1) * matrixWidth, 26, matrixWidth - 6, 11, STYLE.rowText, "character"),
        }
        for _, fs in pairs(headerCells[i]) do
            fs:SetHeight(14)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
        end
    end
    local separators = {}
    for i = 1, #CHARACTERS do
        local x = MATRIX_FIRST + i * matrixWidth - 6
        local head = header:CreateTexture(nil, "OVERLAY")
        head:SetTexture(WHITE)
        head:SetPoint("TOPLEFT", x, -4)
        head:SetSize(2, 39)
        separators[i] = { head }
    end
    local hint = Label(page, "Shift + mouse wheel: scroll characters", 0, PAGE_HEIGHT - 50, 205, 9, MUTED)
    local hbar = CreateFrame("Slider", nil, page)
    hbar:SetPoint("TOPLEFT", MATRIX_FIRST, -(PAGE_HEIGHT - 52))
    hbar:SetSize(matrixColumns * matrixWidth - 6, 12)
    hbar:SetOrientation("HORIZONTAL")
    hbar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    hbar:SetBackdropColor(0.10, 0.11, 0.14, 1)
    hbar:SetBackdropBorderColor(unpack(BORDER))
    hbar:SetThumbTexture(WHITE)
    hbar:GetThumbTexture():SetSize(70, 10)
    hbar:SetValueStep(1)
    hbar:SetMinMaxValues(0, 0)
    hbar:SetValue(0)
    local position = Label(page, "", matrixWithPicker - 140, 61, 140, 9, MUTED)
    local function ScrollCharacters(delta)
        local maxOffset = math.max(0, #VisibleCharacters() - matrixColumns)
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
    local pickerScroll, picker = Scroll(page, "AshoholicPreviewRaidPicker", pickerX, 127, pickerWidth, normalPickerHeight)
    page.matrixRows, page.pickerRows = {}, {}
    local function MatrixRow(i)
        local row = page.matrixRows[i]
        if not row then
            row = Button(matrix, "", 0, 0, 690, 25)
            row.name = Label(row, "", 7, 7, 198, 10)
            row.name:SetHeight(13)
            if row.name.SetWordWrap then row.name:SetWordWrap(false) end
            row.cells = {}
            for j = 1, matrixColumns do
                row.cells[j] = Label(row, "", MATRIX_FIRST + (j - 1) * matrixWidth, 7, matrixWidth - 8, 10, STYLE.rowText, "character")
            end
            page.matrixRows[i] = row
        end
        return row
    end
    local pickerTitle = Label(page, "TRACKING SELECTION", pickerX, 61, pickerWidth, 10, GOLD)
    local watchAll = Button(page, "Watch all", pickerX, 84, 105, 28, function()
        for _, raid in ipairs(raids) do
            for _, boss in ipairs(raid.bosses) do state.watched[boss.id] = true end
        end
        page.Refresh()
    end)
    local clear = Button(page, "Clear", pickerX + 112, 84, 82, 28, function()
        wipe(state.watched)
        page.Refresh()
    end)
    local pickerHint = Label(page, "+ expands groups", pickerX + 204, 92, 128, 10, MUTED)
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
    local note = Label(page, "Raids: sample weekly loot status; catalogue Normal ilvl and release shown when available. Dungeons: tracking only; no weekly loot lockout is assumed.", 0, PAGE_HEIGHT - 26, CONTENT_WIDTH, 10, MUTED)
    page.Refresh = function()
        local heightGain = state.raidsFocus and FOCUS_HEIGHT_GAIN or 0
        local matrixHeight, pickerHeight = MATRIX_HEIGHT + heightGain, normalPickerHeight + heightGain
        focusButton.text:SetText(state.raidsFocus and "Exit Focus" or "Focus encounters")
        matrixScroll:SetHeight(matrixHeight)
        pickerScroll:SetHeight(pickerHeight)
        hbar:ClearAllPoints()
        hbar:SetPoint("TOPLEFT", MATRIX_FIRST, -(PAGE_HEIGHT - 52 + heightGain))
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", 0, -(PAGE_HEIGHT - 50 + heightGain))
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", 0, -(PAGE_HEIGHT - 26 + heightGain))
        local y, rowIndex = 0, 0
        local allCharacters = VisibleCharacters()
        local width = showPicker and matrixWithPicker or SCROLL_WIDTH
        matrixColumns = math.max(1, math.min(#CHARACTERS, math.floor((width - MATRIX_FIRST) / (compact and 80 or 110))))
        matrixWidth = (width - MATRIX_FIRST) / matrixColumns
        matrixScroll:SetWidth(width)
        matrix:SetWidth(width)
        header:SetWidth(width)
        position:ClearAllPoints()
        position:SetPoint("TOPLEFT", width - 140, -61)
        hbar:SetWidth(width - MATRIX_FIRST - 6)
        pickerToggle.text:SetText(showPicker and "Hide selection" or "Show selection")
        compactToggle.text:SetText(compact and "[x] Compact columns" or "[ ] Compact columns")
        for _, widget in ipairs({ pickerScroll, pickerTitle, watchAll, clear, pickerHint }) do SetVisible(widget, showPicker) end
        local maxOffset = math.max(0, #allCharacters - matrixColumns)
        state.matrixOffset = math.min(state.matrixOffset, maxOffset)
        local characters = {}
        for i = 1, matrixColumns do characters[i] = allCharacters[state.matrixOffset + i] end
        for i = 1, #CHARACTERS do
            local character = characters[i]
            local cells = headerCells[i]
            local x = MATRIX_FIRST + (i - 1) * matrixWidth
            for _, fs in pairs(cells) do SetVisible(fs, i <= matrixColumns) end
            cells.name:ClearAllPoints()
            cells.name:SetPoint("TOPLEFT", x, -26)
            cells.name:SetWidth(matrixWidth - 6)
            cells.account:ClearAllPoints()
            cells.account:SetPoint("TOPLEFT", x, -6)
            cells.name:SetText(character and ClassName(character.data) or "")
            cells.account:SetText("")
            local previous = i > 1 and characters[i - 1] or allCharacters[state.matrixOffset]
            if character and (i == 1 or character.data.account ~= characters[i - 1].data.account) then
                local span = 1
                while characters[i + span] and characters[i + span].data.account == character.data.account do span = span + 1 end
                local account = ACCOUNTS[character.data.account]
                local continued = previous and previous.data.account == character.data.account
                cells.account:SetWidth(span * matrixWidth - 10)
                cells.account:SetText((continued and "< " or "") .. string.upper(account.name))
                cells.account:SetTextColor(unpack(account.color or GOLD))
            end
            local nextCharacter = allCharacters[state.matrixOffset + i + 1]
            local split = character and nextCharacter and nextCharacter.data.account ~= character.data.account
            for _, texture in ipairs(separators[i]) do
                texture:ClearAllPoints()
                texture:SetPoint("TOPLEFT", MATRIX_FIRST + i * matrixWidth - 6, -4)
                texture:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
                SetVisible(texture, i <= matrixColumns and split)
            end
        end
        hbar:SetMinMaxValues(0, maxOffset)
        hbar:SetValue(state.matrixOffset)
        hbar:GetThumbTexture():SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.75)
        SetVisible(hbar, maxOffset > 0)
        position:SetText(#allCharacters == 0 and "" or string.format("%d-%d of %d", state.matrixOffset + 1, math.min(#allCharacters, state.matrixOffset + matrixColumns), #allCharacters))
        hint:SetText(maxOffset > 0 and "Shift + wheel: characters" or "All selected characters fit")
        local function AddRow(name, boss, instance, category, metadata)
            rowIndex = rowIndex + 1
            local row = MatrixRow(rowIndex)
            for j = #row.cells + 1, matrixColumns do
                row.cells[j] = Label(row, "", 0, 7, matrixWidth - 8, 10, STYLE.rowText, "character")
            end
            local rowHeight = metadata and 38 or 28
            if metadata then
                if not row.metadata then row.metadata = Label(row, "", 7, 19, 198, 9, MUTED) end
                row.metadata:SetText(metadata)
                SetVisible(row.metadata, true)
            elseif row.metadata then
                row.metadata:SetText("")
                SetVisible(row.metadata, false)
            end
            row:SetWidth(width)
            row:SetHeight(rowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row.name:SetText(name)
            row:SetScript("OnClick", category and function()
                state.encounterCollapsed[category.key] = not state.encounterCollapsed[category.key]
                page.Refresh()
            end or nil)
            local tooltip = category and "Click to collapse or expand all watched " .. category.name .. ". Tracking selections are kept."
                or instance and instance.kind == "Dungeons"
                and "Dungeon watchlist only. Tracked does not imply a weekly lockout or a recorded kill."
                or "Sample raid loot eligibility. Looted does not prevent entry. Unknown needs a fresh snapshot."
            local raidMetadata = instance and instance.kind == "Raids" and RaidMetadata(instance)
            if raidMetadata then tooltip = tooltip .. "\n" .. raidMetadata end
            Tip(row, boss and boss.name or name, tooltip)
            for i, cell in ipairs(row.cells) do
                local character = characters[i]
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", MATRIX_FIRST + (i - 1) * matrixWidth, -7)
                cell:SetWidth(matrixWidth - 8)
                SetVisible(cell, i <= matrixColumns)
                cell:SetText(character and boss and LootStatus(character.data, boss, character.index, instance) or "")
            end
            row:Show()
            y = y + rowHeight
        end
        for _, category in ipairs(trackingTree) do
            if WatchedCount(category) > 0 then
                AddRow((state.encounterCollapsed[category.key] and "+ " or "- ") .. category.name, nil, nil, category)
                if not state.encounterCollapsed[category.key] then
                    for _, expansion in ipairs(category.children) do
                        if WatchedCount(expansion) > 0 then
                            for _, instance in ipairs(expansion.children) do
                                if WatchedCount(instance) > 0 then
                                    AddRow(AMBER .. instance.name .. "|r", nil, instance, nil, RaidMetadata(instance))
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
        end
        for i = rowIndex + 1, #page.matrixRows do page.matrixRows[i]:Hide() end
        SetVisible(page.empty, rowIndex == 0)
        matrix:SetHeight(math.max(matrixHeight, y))
        matrixScroll:SetVerticalScroll(math.min(matrixScroll:GetVerticalScroll(), math.max(0, y - matrixHeight)))
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
                    local tooltip = count .. " / " .. #node.bosses .. " bosses watched. Click to toggle this entire group."
                    local raidMetadata = node.kind == "Raids" and RaidMetadata(node)
                    if raidMetadata then tooltip = tooltip .. "\n" .. raidMetadata end
                    Tip(row.select, node.name, tooltip)
                end
                y = y + (entry.leaf and 25 or 28)
            end
        end
        picker:SetHeight(math.max(pickerHeight, y))
        pickerScroll:SetVerticalScroll(math.min(pickerScroll:GetVerticalScroll(), math.max(0, y - pickerHeight)))
    end
end

local function BuildActivities()
    local page = Page("Activities", "Rewards worth coming back for", "Daily and weekly Call Board activities are separate from the current run's Death contract.")
    local viewportHeight = PAGE_HEIGHT - 75
    local scroll, body = Scroll(page, "AshoholicPreviewActivityScroll", 0, 57, CONTENT_WIDTH, viewportHeight)
    local panels = {}
    for accountId, account in ipairs(ACCOUNTS) do
        local panel = Surface(body, 0, 0, HALF_PANEL_WIDTH, 345)
        panel.title = Label(panel, account.name, 16, 17, HALF_PANEL_WIDTH - 32, 16, GOLD)
        panel.cache = Label(panel, "CALL BOARD CACHE (SAMPLE)", 16, 51, HALF_PANEL_WIDTH - 32, 10, MUTED)
        panel.progress = Label(panel, accountId == 1 and "7 / 10 progress" or "9 / 10 progress", 16, 73, HALF_PANEL_WIDTH - 32, 21, TEAL)
        panel.track, panel.fill = Progress(panel, 16, 106, HALF_PANEL_WIDTH - 32, accountId == 1 and 7 or 9, 10)
        panel.heading = Label(panel, "UNCLAIMED & IN PROGRESS", 16, 132, HALF_PANEL_WIDTH - 32, 10, GOLD)
        panel.daily = Label(panel, "DAILY  /  Sample reset: 08h 42m", 16, 132, HALF_PANEL_WIDTH - 32, 11, GOLD)
        panel.weekly = Label(panel, "WEEKLY  /  Sample reset: 3d 08h", 16, 132, HALF_PANEL_WIDTH - 32, 11, GOLD)
        local rows = accountId == 1 and {
            { "Aster / Daily dungeon", GREEN .. "Ready to claim|r", "Character activity  /  Ash + Shards + gold" },
            { "Account / Crafting contract", GREEN .. "Ready to claim|r", "Shared activity  /  1 Artisan Soul" },
            { "Cinder / Example weekly", "8 / 11 sample objectives", "Illustrative progress, not a verified raid objective" },
        } or {
            { "Character / Open World daily", GREEN .. "Ready to claim|r", "Character activity  /  Ash + gold" },
            { "Account / Crafting contract", "2 / 3 objectives", "Shared activity  /  1 Artisan Soul" },
            { "Character / Weekly activities", DIM .. "Unknown|r", "Snapshot predates this reset; refresh needed" },
        }
        panel.rows = {}
        for i, row in ipairs(rows) do
            local y = 159 + (i - 1) * 56
            local title = Label(panel, row[1], 16, y, 280, 12)
            local status = Label(panel, row[2], 280, y, 214, 11, TEAL)
            status:SetJustifyH("RIGHT")
            local note = Label(panel, row[3], 16, y + 23, 478, 10, MUTED)
            panel.rows[i] = { title, status, note }
        end
        panels[accountId] = panel
    end
    Label(page, "Sample reset timers: Daily 08h 42m  /  Weekly 3d 08h. Shared activities count once per account.", 0, PAGE_HEIGHT - 9, CONTENT_WIDTH, 10, MUTED)
    page.Refresh = function()
        local selected = 0
        for _, visible in pairs(state.accounts) do if visible then selected = selected + 1 end end
        local single = selected == 1
        local count = 0
        for accountId, panel in ipairs(panels) do
            local visible = state.accounts[accountId]
            SetVisible(panel, visible)
            if visible then
                local width = single and SCROLL_WIDTH or HALF_PANEL_WIDTH
                local innerWidth = width - 32
                local columnWidth = single and (innerWidth - PANEL_GAP) / 2 or innerWidth
                local statusWidth = 214
                local titleWidth = columnWidth - statusWidth - 12
                panel:ClearAllPoints()
                panel.title:SetText(ACCOUNTS[accountId].name)
                panel:SetSize(width, viewportHeight)
                for _, label in ipairs({ panel.title, panel.cache, panel.progress, panel.heading }) do label:SetWidth(innerWidth) end
                panel.daily:SetWidth(columnWidth)
                panel.weekly:SetWidth(columnWidth)
                panel.weekly:ClearAllPoints()
                panel.weekly:SetPoint("TOPLEFT", 16 + columnWidth + PANEL_GAP, -132)
                panel.track:SetWidth(innerWidth)
                panel.fill:SetWidth(innerWidth * (accountId == 1 and 0.7 or 0.9))
                SetVisible(panel.heading, not single)
                SetVisible(panel.daily, single)
                SetVisible(panel.weekly, single)
                for i, row in ipairs(panel.rows) do
                    local x = single and i == 3 and (16 + columnWidth + PANEL_GAP) or 16
                    local y = single and (i == 2 and 251 or 170) or 159 + (i - 1) * 56
                    for j, fs in ipairs(row) do
                        fs:ClearAllPoints()
                        fs:SetPoint("TOPLEFT", x + (j == 2 and titleWidth + 12 or 0), -(y + (j == 3 and 23 or 0)))
                        fs:SetWidth(j == 1 and titleWidth or (j == 2 and statusWidth or columnWidth))
                    end
                end
                panel:SetPoint("TOPLEFT", (count % 2) * (HALF_PANEL_WIDTH + PANEL_GAP), -math.floor(count / 2) * (viewportHeight + 15))
                count = count + 1
            end
        end
        local height = math.max(viewportHeight, math.ceil(count / 2) * (viewportHeight + 15) - 15)
        body:SetHeight(height)
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), height - viewportHeight))
    end
end

local function BuildProgression()
    local page = Page("Progression", "Torment & Prestige", "Account-wide Torment access (the new Hardcore ladder), alongside account Prestige readiness.")
    local viewportHeight = PAGE_HEIGHT - 75
    local ladder = Surface(page, 0, 57, HALF_PANEL_WIDTH, viewportHeight)
    local innerWidth = HALF_PANEL_WIDTH - 32
    Label(ladder, "ACCOUNT TORMENT UNLOCKS", 16, 17, innerWidth, 11, GOLD)
    local scroll, body = Scroll(page, "AshoholicPreviewProgressionScroll", HALF_PANEL_WIDTH + PANEL_GAP, 57,
        HALF_PANEL_WIDTH + SCROLLBAR_WIDTH, viewportHeight)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", ScrollBy)
    page.ladderRows = {}
    for i = 1, #ACCOUNTS do
        local row = CreateFrame("Frame", nil, ladder)
        row:SetSize(innerWidth, 51)
        row.name = Label(row, "", 0, 0, 150, 12)
        row.note = Label(row, "", 155, 0, innerWidth - 155, 11, MUTED)
        row.pips = {}
        local pipWidth = (innerWidth - 9 * 6) / 10
        for tier = 1, 10 do
            row.pips[tier] = Surface(row, (tier - 1) * (pipWidth + 6), 23, pipWidth, 17)
            local fs = Label(row.pips[tier], tostring(tier), 0, 2, pipWidth, 10)
            fs:SetJustifyH("CENTER")
        end
        page.ladderRows[i] = row
    end
    page.prestigePanels = {}
    for accountId, account in ipairs(ACCOUNTS) do
        local shardRate = math.min(50 + 50 * account.prestige, 750)
        local shardsConsumed
        if account.prestige >= 15 then
            shardsConsumed = account.shards
        else
            shardsConsumed = math.min(account.shards, shardRate * shardRate)
        end
        local essence = math.floor(shardsConsumed / shardRate)
        local panel = Surface(body, 0, 0, HALF_PANEL_WIDTH, 160)
        panel.title = Label(panel, account.name .. "  /  Prestige " .. account.prestige, 16, 15, innerWidth, 14, GOLD)
        Label(panel, account.ash >= 10771440 and GREEN .. "Ready to Prestige|r" or AMBER .. "Ash requirement not met|r", 16, 44, innerWidth, 13)
        DetailLine(panel, "Committed Ash / gate", Short(account.ash) .. " / 10.77m", 74)
        DetailLine(panel, "Banked Shards", tostring(account.shards), 99)
        DetailLine(panel, "Next Prestige / Essence", "+" .. essence .. " Essence (" ..
            Short(shardsConsumed) .. " / " .. shardRate .. " Shards)", 124)
        page.prestigePanels[accountId] = panel
    end
    Label(page, "Prestige preview: informational only. Exact reset effects require in-game confirmation.", 0, PAGE_HEIGHT - 9, CONTENT_WIDTH, 10, MUTED)
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
                row.note:SetText("Torment " .. account.tier .. " unlocked")
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
        body:SetHeight(math.max(viewportHeight, y))
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, y - viewportHeight)))
    end
end

local function BuildTrials()
    local page = Page("Trials", "Personal records", "Compare saved bests across your roster. Rankings are last-observed snapshots, not live standings.")
    local headings = {
        { "CHARACTER", 0.18 }, { "CHAMPION BEST", 0.19 }, { "CLASS RANK", 0.16 },
        { "CRUSADER BEST", 0.22 }, { "TEAM", 0.11 }, { "UPDATED", 0.14 },
    }
    local x = 16
    for _, column in ipairs(headings) do
        column.x, column.width = x, (SCROLL_WIDTH - 32) * column[2]
        Label(page, column[1], column.x, 68, column.width - 12, 10, MUTED)
        x = x + column.width
    end
    Button(page, "What are these Trials?", CONTENT_WIDTH - 227, 0, 227, 26, function()
        ShowSettings("Help")
    end)
    local viewportHeight = PAGE_HEIGHT - 156
    local scroll, body = Scroll(page, "AshoholicPreviewTrialScroll", 0, 98, CONTENT_WIDTH, viewportHeight)
    local records = {
        { "1.42m damage", "#42 / 1,280", "Wave 18 / 14:32", "Solo", "Today" },
        { "1.18m damage", "#67 / 940", "Wave 15 / 12:08", "3 players", "Today" },
        { "Not recorded", "-", "Not recorded", "-", "-" },
        { "1.86m damage", "#18 / 1,105", "Wave 22 / 18:46", "5 players", "Today" },
        { "980k damage", DIM .. "Stale|r", "Wave 12 / 10:14", "Solo", "8 days ago" },
    }
    page.rows = {}
    for i, character in ipairs(CHARACTERS) do
        local row = Surface(body, 0, 0, SCROLL_WIDTH, 44)
        Label(row, ClassName(character), headings[1].x, 15, headings[1].width - 12, 12)
        for j, value in ipairs(records[i] or { "Not recorded", "-", "Not recorded", "-", "-" }) do
            local column = headings[j + 1]
            Label(row, value, column.x, 15, column.width - 12, 11)
        end
        Tip(row, character.name .. " / " .. ACCOUNTS[character.account].name, "Champion: solo damage Trial, ranked within your class.\nCrusader: survival waves, 1-5 players. Team is the size of that recorded attempt.\nThese are sample records, not dungeon lockouts.")
        page.rows[i] = row
    end
    Label(page, "Season: Example season  /  Practice runs excluded  /  Scores and ranks shown here are all invented.", 16, PAGE_HEIGHT - 45, CONTENT_WIDTH - 32, 11, TEAL)
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
        body:SetHeight(math.max(viewportHeight, y))
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, y - viewportHeight)))
    end
end

local dialog, closePrompt
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
    { "Customize Theme", "Colors, opacity, fonts and layout together. Jump to a group or scroll through every control." },
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

local function Clone(source)
    if type(source) ~= "table" then return source end
    local result = {}
    for key, value in pairs(source) do result[key] = Clone(value) end
    return result
end

local THEME_COLORS = { BACKGROUND, PANEL, BORDER, BUTTON_BG, BUTTON_BORDER, GOLD, TEXT, MUTED, TEAL }
local STYLE_KEYS = { "titleText", "headerText", "rowText", "accountText", "rowOdd", "rowEven", "rowAccount",
    "rowHover", "selectedBorder", "buttonText", "buttonHover", "tabBg", "tabActiveBg", "tabText", "tabActiveText" }
for _, key in ipairs(STYLE_KEYS) do THEME_COLORS[#THEME_COLORS + 1] = STYLE[key] end
local THEME_OPTIONS = { "font", "fontDelta", "density", "opacity", "scale", "iconStyle", "classIcons", "statusStyle", "logo",
    "fontRoles", "rowHeight", "rowGap", "borderSize" }
local customThemes, nextThemeId = {}, 0
local themeCheckpoint

local function CaptureTheme()
    local result = { colors = {}, options = {} }
    for i, color in ipairs(THEME_COLORS) do result.colors[i] = Clone(color) end
    for _, key in ipairs(THEME_OPTIONS) do result.options[key] = Clone(state[key]) end
    return result
end

local function RememberTheme()
    themeCheckpoint = {
        appearance = CaptureTheme(), name = state.theme, customTheme = state.customTheme,
        lastPreset = state.lastPreset,
    }
end

local function SameTheme(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not SameTheme(value, right[key]) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function Hex(color)
    return string.format("%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

local function ApplyAppearance()
    frame:SetBackdropColor(unpack(BACKGROUND))
    frame:SetBackdropBorderColor(GOLD[1] * 0.45, GOLD[2] * 0.45, GOLD[3] * 0.45, 1)
    for _, entry in ipairs(surfaces) do
        entry[1]:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = state.borderSize })
        entry[1]:SetBackdropColor(unpack(entry[2]))
        entry[1]:SetBackdropBorderColor(unpack(BORDER))
    end
    for _, button in ipairs(buttons) do
        button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = state.borderSize })
        button:SetBackdropColor(unpack(BUTTON_BG))
        button:SetBackdropBorderColor(unpack(BUTTON_BORDER))
        button:GetHighlightTexture():SetVertexColor(unpack(STYLE.buttonHover))
    end
    for _, entry in ipairs(labels) do
        local font, size = FontFor(entry[4], entry[3])
        entry[1]:SetFont(font, size)
        if entry[4] == "button" or entry[4] == "header" or entry[4] == "character" then entry[1]:SetHeight(size + 3) end
        entry[1]:SetTextColor(unpack(entry[2]))
    end
    for _, fill in ipairs(progressFills) do fill:SetVertexColor(unpack(TEAL)) end
    for _, window in pairs({ settings, dialog, closePrompt }) do
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
    for _, color in ipairs({ PANEL, BORDER, BUTTON_BG, BUTTON_BORDER, GOLD, TEXT, MUTED, TEAL }) do color[4] = 1 end
    for i = 1, 3 do
        BUTTON_BG[i] = math.min(1, preset[4][i] * 1.3 + 0.02)
        BUTTON_BORDER[i] = math.min(1, preset[5][i] * 1.25)
    end
    for _, key in ipairs(STYLE_KEYS) do
        local source = TEXT
        if key == "titleText" or key == "selectedBorder" or key == "tabActiveText" then source = GOLD
        elseif key == "headerText" or key == "tabText" then source = MUTED
        elseif key == "rowAccount" or key == "tabActiveBg" then source = PANEL
        elseif key == "rowOdd" or key == "rowEven" or key == "tabBg" then source = BUTTON_BG
        elseif key == "rowHover" or key == "buttonHover" then source = { GOLD[1], GOLD[2], GOLD[3], 0.09 } end
        Copy(STYLE[key], source)
        STYLE[key][4] = source[4] or 1
        if key == "rowEven" then for i = 1, 3 do STYLE[key][i] = math.min(1, STYLE[key][i] + 0.02) end end
    end
    state.theme = preset[1]
    state.lastPreset = preset[1]
    state.customTheme = nil
    RememberTheme()
    ApplyAppearance()
end

local function ApplyCustomTheme(theme)
    for i, color in ipairs(THEME_COLORS) do Copy(color, theme.appearance.colors[i]) end
    for _, key in ipairs(THEME_OPTIONS) do state[key] = Clone(theme.appearance.options[key]) end
    state.theme, state.customTheme = theme.name, theme.id
    RememberTheme()
    frame:SetScale((frame.baseScale or 1) * state.scale)
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

Dialog = function(title, text, options)
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
        dialog:SetScript("OnHide", function()
            dialog.box:ClearFocus()
            local onCancel = dialog.onCancel
            dialog.onCancel = nil
            if onCancel then onCancel() end
        end)
        dialog.primary = Button(dialog, "", 18, 216, 200, 28)
        dialog.secondary = Button(dialog, "Cancel", 242, 216, 200, 28, function() dialog:Hide() end)
    end
    dialog:SetScale(settings and settings:GetScale() or 1)
    dialog.title:SetText(title)
    dialog.text:SetText(text)
    SetVisible(dialog.boxBg, options.box ~= nil)
    dialog.box:SetText(options.box or "")
    dialog.onCancel = options.onCancel
    dialog.primary.text:SetText(options.primary or "OK")
    dialog.primary:SetScript("OnClick", function()
        local value = dialog.box:GetText()
        if options.validate then
            local errorText = options.validate(value)
            if errorText then
                dialog.text:SetText(errorText)
                dialog.box:SetFocus()
                dialog.box:HighlightText()
                return
            end
        end
        dialog.onCancel = nil
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

local function PickColor(onPick, current)
    local original, originalTheme = Clone(current or TEXT), state.theme
    addon:OpenColorPicker(original, function(r, g, b, a)
        onPick({ r, g, b, a })
    end, function()
        onPick(original)
        state.theme = originalTheme
        ApplyAppearance()
    end, settings)
end

local function EditColorHex(title, onPick, current)
    addon:CloseColorPicker(settings)
    Dialog(title .. " / RGBA hex", "Enter RRGGBB or RRGGBBAA (00 transparent, FF opaque). Example: FFCC6680.", {
        box = Hex(current) .. string.format("%02x", math.floor((current[4] or 1) * 255 + 0.5)),
        primary = "Apply",
        validate = function(value)
            value = value:match("^%s*#?(%x+)%s*$")
            if not value or (#value ~= 6 and #value ~= 8) then
                return "Invalid color. Enter six or eight hexadecimal digits."
            end
        end,
        onAccept = function(value)
            value = value:match("^%s*#?(%x+)%s*$")
            local color = {}
            for i = 1, #value / 2 do color[i] = tonumber(value:sub(i * 2 - 1, i * 2), 16) / 255 end
            color[4] = color[4] or 1
            onPick(color)
        end,
    })
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
    Button(settings, "X", 856, 14, 28, 26, function() settings.RequestClose() end)
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
        local updating = false
        slider:SetScript("OnValueChanged", function(_, value)
            if updating then return end
            value = math.floor(value / step + 0.5) * step
            text:SetText(format(value))
            set(value)
        end)
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
        settings.groups[#settings.groups + 1] = { Update = function()
            updating = true
            slider:SetValue(get())
            text:SetText(format(get()))
            slider:GetThumbTexture():SetVertexColor(unpack(GOLD))
            updating = false
        end }
        return slider
    end

    -- Themes
    local themeBody = bodies.Themes
    local themeScroll, themeGallery = Scroll(themeBody, "AshoholicPreviewThemeGallery", 0, 0, 660, 350)
    Label(themeGallery, "DEFAULT PRESETS", 0, 0, 630, 11, GOLD)
    local function ThemeName(name, exceptId)
        name = name:match("^%s*(.-)%s*$")
        if name == "" or #name > 40 or name:find("|", 1, true) or name:find("[%c]") then
            local message = "Use a plain-text name of 1-40 characters, without control codes or |."
            Say(message)
            return nil, message
        end
        for _, preset in ipairs(THEMES) do
            if string.lower(preset[1]) == string.lower(name) then
                local message = "That name belongs to a default preset."
                Say(message)
                return nil, message
            end
        end
        for _, theme in ipairs(customThemes) do
            if theme.id ~= exceptId and string.lower(theme.name) == string.lower(name) then
                local message = "A custom preset already has that name."
                Say(message)
                return nil, message
            end
        end
        return name
    end
    local closing, closePreview = false, false
    local function SaveCustomTheme(onSaved)
        Dialog("Save custom preset", "Save colors, fonts, icons and row layout in this preview session. /reload clears all preview presets.", {
            box = "My Ashoholic theme", primary = "Save",
            validate = function(value)
                local _, message = ThemeName(value)
                return message
            end,
            onCancel = function() closePreview = false end,
            onAccept = function(value)
                local name = ThemeName(value)
                if not name then return end
                nextThemeId = nextThemeId + 1
                local theme = { id = nextThemeId, name = name, appearance = CaptureTheme() }
                customThemes[#customThemes + 1] = theme
                state.theme, state.customTheme = name, theme.id
                RememberTheme()
                settings.ShowSection("Themes")
                Say("Saved '" .. name .. "' until /reload.")
                if onSaved then onSaved() end
            end,
        })
    end
    local function SelectedCustomTheme()
        for _, theme in ipairs(customThemes) do
            if theme.id == state.customTheme then return theme end
        end
    end
    local function UpdateCustomTheme()
        local theme = SelectedCustomTheme()
        if not theme then
            Say("Apply or edit a custom preset first, or use Save as new.")
            return false
        end
        theme.appearance = CaptureTheme()
        state.theme = theme.name
        RememberTheme()
        Say("Updated '" .. theme.name .. "' until /reload.")
        return true
    end
    local function FinishClose()
        local shouldClosePreview = closePreview
        closing = true
        if closePrompt then closePrompt:Hide() end
        settings:Hide()
        if shouldClosePreview then frame:Hide() end
        closePreview, closing = false, false
    end
    settings.RequestClose = function(withPreview)
        closePreview = closePreview or withPreview or false
        if not themeCheckpoint or SameTheme(CaptureTheme(), themeCheckpoint.appearance) then
            FinishClose()
            return
        end
        local shouldClosePreview = closePreview
        if not frame:IsShown() then frame:Show() end
        settings:Show()
        addon:CloseColorPicker(settings)
        if dialog then dialog:Hide() end
        closePreview = shouldClosePreview
        if not closePrompt then
            closePrompt = Popup("AshoholicPreviewUnsavedTheme", 520, 232)
            closePrompt:SetScript("OnHide", function()
                if not closing then closePreview = false end
            end)
            Label(closePrompt, "Unsaved theme changes", 18, 16, 484, 16, GOLD)
            closePrompt.text = Label(closePrompt, "", 18, 48, 484, 11)
            Button(closePrompt, "Save as new...", 18, 118, 236, 30, function()
                local withPreview = closePreview
                closePrompt:Hide()
                closePreview = withPreview
                SaveCustomTheme(FinishClose)
            end)
            closePrompt.update = Button(closePrompt, "Update current", 266, 118, 236, 30, function()
                if UpdateCustomTheme() then FinishClose() end
            end)
            Button(closePrompt, "Discard changes and close", 18, 164, 236, 30, function()
                for i, color in ipairs(THEME_COLORS) do Copy(color, themeCheckpoint.appearance.colors[i]) end
                for _, key in ipairs(THEME_OPTIONS) do state[key] = Clone(themeCheckpoint.appearance.options[key]) end
                state.theme, state.customTheme = themeCheckpoint.name, themeCheckpoint.customTheme
                state.lastPreset = themeCheckpoint.lastPreset
                frame:SetScale((frame.baseScale or 1) * state.scale)
                ApplyAppearance()
                FinishClose()
            end)
            Button(closePrompt, "Continue editing", 266, 164, 236, 30, function()
                closePreview = false
                closePrompt:Hide()
            end)
        end
        local custom = SelectedCustomTheme()
        closePrompt.text:SetText(custom and ("Save your edits as a new custom preset, update '" .. custom.name .. "', or discard them. Presets last until /reload.")
            or "Default presets are read-only. Save your edits as a new custom preset or discard them. Presets last until /reload.")
        SetVisible(closePrompt.update, custom ~= nil)
        closePrompt:SetScale(settings:GetScale())
        closePrompt:Show()
        closePrompt:Raise()
    end
    local themeGroup = {}
    for i, preset in ipairs(THEMES) do
        local theme = preset
        local card = Button(themeGallery, preset[1], ((i - 1) % 2) * 320, 24 + math.floor((i - 1) / 2) * 82, 310, 72, function() ApplyPreset(theme) end)
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
    local customY = 24 + math.ceil(#THEMES / 2) * 82
    Label(themeGallery, "CUSTOM PRESETS  /  Starred first", 0, customY, 630, 11, GOLD)
    local emptyThemes = Label(themeGallery, "No custom presets yet. Customize a default preset, then save your own.", 0, customY + 28, 630, 11, MUTED)
    local customRows = {}
    themeBody.Refresh = function()
        local sorted = {}
        for i, theme in ipairs(customThemes) do sorted[i] = theme end
        table.sort(sorted, function(a, b)
            if (a.starred or false) ~= (b.starred or false) then return a.starred or false end
            return a.id < b.id
        end)
        for i, theme in ipairs(sorted) do
            local row = customRows[i]
            if not row then
                row = CreateFrame("Frame", nil, themeGallery)
                row:SetSize(630, 64)
                row.apply = Button(row, "", 0, 0, 272, 28, function() ApplyCustomTheme(row.theme) end)
                row.star = Button(row, "", 280, 0, 92, 28, function()
                    row.theme.starred = not row.theme.starred
                    settings.ShowSection("Themes")
                end)
                Button(row, "Edit", 380, 0, 70, 28, function()
                    ApplyCustomTheme(row.theme)
                    settings.ShowSection("Customize Theme")
                end)
                Button(row, "Rename", 458, 0, 82, 28, function()
                    local target = row.theme
                    Dialog("Rename preset", "Default presets cannot be renamed. This custom preset lasts until /reload.", {
                        box = target.name, primary = "Rename", onAccept = function(value)
                            local name = ThemeName(value, target.id)
                            if not name then return end
                            target.name = name
                            if state.customTheme == target.id then state.theme = name end
                            if themeCheckpoint and themeCheckpoint.customTheme == target.id then themeCheckpoint.name = name end
                            settings.ShowSection("Themes")
                        end,
                    })
                end)
                Button(row, "Delete", 548, 0, 82, 28, function()
                    local target = row.theme
                    Dialog("Delete custom preset", "Delete '" .. target.name .. "'? Your current appearance remains applied.", {
                        primary = "Delete", onAccept = function()
                            for index, entry in ipairs(customThemes) do
                                if entry.id == target.id then table.remove(customThemes, index); break end
                            end
                            if state.customTheme == target.id then
                                state.customTheme = nil
                                state.theme = "Custom"
                                if themeCheckpoint then themeCheckpoint.customTheme, themeCheckpoint.name = nil, "Custom" end
                            end
                            settings.ShowSection("Themes")
                        end,
                    })
                end)
                Label(row, "Saved colors, fonts, icons and row layout", 9, 36, 600, 10, MUTED)
                customRows[i] = row
            end
            row.theme = theme
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(customY + 28 + (i - 1) * 64))
            row.apply.text:SetText(theme.name)
            row.apply:SetBackdropBorderColor(unpack(state.customTheme == theme.id and GOLD or BUTTON_BORDER))
            row.star.text:SetText(theme.starred and "* Starred" or "Star")
            row:Show()
        end
        for i = #sorted + 1, #customRows do customRows[i]:Hide() end
        SetVisible(emptyThemes, #sorted == 0)
        local height = customY + 28 + math.max(1, #sorted) * 64
        themeGallery:SetHeight(height)
        themeScroll:SetVerticalScroll(math.min(themeScroll:GetVerticalScroll(), math.max(0, height - 350)))
    end
    Button(themeBody, "Customize...", 0, 360, 180, 30, function() settings.ShowSection("Customize Theme") end)
    Button(themeBody, "Save as custom...", 188, 360, 210, 30, function() SaveCustomTheme() end)
    Button(themeBody, "Import...", 406, 360, 210, 30, function() settings.ShowSection("Profiles & Sharing") end)
    Label(themeBody, "Default presets are read-only. Custom presets are session-local; account filters are never included.", 0, 400, 660, 10, MUTED)

    local colorPage = bodies["Customize Theme"]
    local editorScroll, editorBody = Scroll(colorPage, "AshoholicPreviewThemeEditor", 0, 34, 660, 316)
    editorScroll:EnableMouseWheel(true)
    editorScroll:SetScript("OnMouseWheel", ScrollBy)
    local colorBody = CreateFrame("Frame", nil, editorBody)
    colorBody:SetPoint("TOPLEFT", 0, 0)
    colorBody:SetWidth(634)
    Label(colorBody, "COLORS & OPACITY", 0, 0, 630, 11, GOLD)
    local slots = {
        { "Window background", BACKGROUND }, { "Panels & rows", PANEL }, { "Borders", BORDER },
        { "Buttons", BUTTON_BG }, { "Accent / headings", GOLD }, { "Body text", TEXT },
        { "Secondary text", MUTED }, { "Highlighted values", TEAL },
        { "Button borders", BUTTON_BORDER }, { "Button text", STYLE.buttonText },
        { "Button hover", STYLE.buttonHover }, { "Title text", STYLE.titleText },
        { "Column header text", STYLE.headerText }, { "Character row text", STYLE.rowText },
        { "Account name text", STYLE.accountText }, { "Account row background", STYLE.rowAccount },
        { "Odd character rows", STYLE.rowOdd }, { "Even character rows", STYLE.rowEven },
        { "Character row hover", STYLE.rowHover }, { "Selected row border", STYLE.selectedBorder },
        { "Tab background", STYLE.tabBg }, { "Active tab background", STYLE.tabActiveBg },
        { "Tab text", STYLE.tabText }, { "Active tab text", STYLE.tabActiveText },
    }
    local swatches = {}
    for i, slot in ipairs(slots) do
        local target, title = slot[2], slot[1]
        local x, y = ((i - 1) % 2) * 320, 28 + math.floor((i - 1) / 2) * 52
        local row = Surface(colorBody, x, y, 310, 44)
        Label(row, title, 9, 15, 143, 11)
        local swatch = row:CreateTexture(nil, "OVERLAY")
        swatch:SetTexture(WHITE)
        swatch:SetPoint("TOPLEFT", 158, -9)
        swatch:SetSize(24, 26)
        swatches[i] = { swatch, target }
        local function SetColor(color)
            Copy(target, color)
            state.theme = "Custom"
            ApplyAppearance()
            Say(title .. " changed. Save or update your custom preset to keep this draft.")
        end
        Button(row, "Change", 190, 8, 70, 28, function() PickColor(SetColor, target) end)
        local hexButton = Button(row, "Hex", 264, 8, 42, 28, function() EditColorHex(title, SetColor, target) end)
        Tip(hexButton, title .. " RGBA hex", "Enter an exact RGB color and optional alpha value.")
    end
    settings.groups[#settings.groups + 1] = { Update = function()
        for _, entry in ipairs(swatches) do entry[1]:SetVertexColor(entry[2][1], entry[2][2], entry[2][3], entry[2][4] or 1) end
    end }
    local colorHeight = 28 + math.ceil(#slots / 2) * 52
    colorBody:SetHeight(colorHeight)
    Button(colorPage, "Save as new...", 0, 360, 190, 30, function() SaveCustomTheme() end)
    Button(colorPage, "Update selected", 198, 360, 210, 30, UpdateCustomTheme)
    Button(colorPage, "Revert to default", 416, 360, 210, 30, function()
        for _, preset in ipairs(THEMES) do
            if preset[1] == (state.lastPreset or "Ember & Ash") then ApplyPreset(preset) end
        end
        Say("Reverted to " .. (state.lastPreset or "Ember & Ash") .. ".")
    end)
    Label(colorPage, "Colors, fonts, icons and row layout save together. Class and loot-status colors keep their meaning.", 0, 400, 660, 10, MUTED)

    local textBody = CreateFrame("Frame", nil, editorBody)
    local textY = colorHeight + 24
    textBody:SetPoint("TOPLEFT", 0, -textY)
    textBody:SetWidth(634)
    Label(textBody, "GLOBAL FONT", 0, 0, 300, 11, GOLD)
    Choices(textBody, {
        { "Fonts\\FRIZQT__.TTF", "Friz Quadrata" }, { "Fonts\\ARIALN.TTF", "Arial Narrow" },
        { "Fonts\\MORPHEUS.TTF", "Morpheus" }, { "Fonts\\skurri.ttf", "Skurri" },
    }, 0, 22, 152, 4, function() return state.font end, function(value) state.font = value; ApplyAppearance() end)
    Label(textBody, "TEXT SIZE", 0, 72, 300, 11, GOLD)
    Choices(textBody, { { -1, "Small" }, { 0, "Normal" }, { 1, "Large" }, { 2, "Larger" } }, 0, 94, 152, 4,
        function() return state.fontDelta end, function(value) state.fontDelta = value; ApplyAppearance() end)
    local function Pixels(value) return string.format("%d px", value) end
    local fontChoices = {
        { "inherit", "Global font" }, { "Fonts\\FRIZQT__.TTF", "Friz Quadrata" },
        { "Fonts\\ARIALN.TTF", "Arial Narrow" }, { "Fonts\\MORPHEUS.TTF", "Morpheus" },
        { "Fonts\\skurri.ttf", "Skurri" },
    }
    for i, role in ipairs({ { "title", "Titles" }, { "header", "Column headers" }, { "character", "Character values" },
        { "account", "Account names" }, { "button", "Buttons" }, { "hint", "Hints" } }) do
        local key, title = role[1], role[2]
        local y = 156 + (i - 1) * 156
        Label(textBody, string.upper(title) .. " FONT", 0, y, 630, 11, GOLD)
        Choices(textBody, fontChoices, 0, y + 22, 200, 3,
            function() return (state.fontRoles[key] or {}).font or "inherit" end,
            function(value)
                state.fontRoles[key] = state.fontRoles[key] or {}
                state.fontRoles[key].font = value ~= "inherit" and value or nil
                ApplyAppearance()
            end)
        SliderRow(textBody, title .. " size adjustment", 0, y + 88, -2, 4, 1,
            function() return (state.fontRoles[key] or {}).delta or 0 end,
            function(value)
                state.fontRoles[key] = state.fontRoles[key] or {}
                state.fontRoles[key].delta = value
                ApplyAppearance()
            end, Pixels)
    end
    local textHeight = 156 + 6 * 156
    textBody:SetHeight(textHeight)
    local layoutBody = CreateFrame("Frame", nil, editorBody)
    local layoutY = textY + textHeight + 24
    layoutBody:SetPoint("TOPLEFT", 0, -layoutY)
    layoutBody:SetSize(634, 444)
    Label(layoutBody, "ROSTER ROW DENSITY", 0, 0, 300, 11, GOLD)
    Choices(layoutBody, { { "compact", "Compact" }, { "comfortable", "Comfortable" }, { "spacious", "Spacious" } }, 0, 22, 204, 3,
        function() return state.density end, function(value) state.density = value; state.rowHeight = nil; refresh() end)
    SliderRow(layoutBody, "WINDOW SCALE", 0, 74, 0.7, 1.2, 0.05, function() return state.scale end, function(value)
        state.scale = value
        frame:SetScale((frame.baseScale or 1) * value)
    end, function(value) return string.format("%.0f%%", value * 100) end)
    SliderRow(layoutBody, "BACKGROUND OPACITY", 0, 134, 0, 1, 0.01, function() return BACKGROUND[4] end, function(value)
        BACKGROUND[4] = value
        frame:SetBackdropColor(unpack(BACKGROUND))
    end, function(value) return string.format("%.0f%%", value * 100) end)
    Label(layoutBody, "Compact hides character hints. Scale and background opacity affect only the main window.", 0, 202, 630, 10, MUTED)
    SliderRow(layoutBody, "ROSTER ROW HEIGHT (content minimum applies)", 0, 244, 30, 70, 1,
        function() return state.rowHeight or (state.density == "compact" and 30 or (state.density == "spacious" and 54 or 44)) end,
        function(value) state.rowHeight = value; refresh() end, Pixels)
    SliderRow(layoutBody, "ROSTER ROW SPACING", 0, 306, 0, 12, 1,
        function() return state.rowGap end, function(value) state.rowGap = value; refresh() end, Pixels)
    SliderRow(layoutBody, "PANEL & BUTTON BORDER THICKNESS", 0, 368, 1, 4, 1,
        function() return state.borderSize end, function(value) state.borderSize = value; ApplyAppearance() end, Pixels)
    editorBody:SetHeight(layoutY + layoutBody:GetHeight())
    for i, jump in ipairs({ { "Colors", 0 }, { "Fonts", textY }, { "Layout", layoutY } }) do
        local offset = jump[2]
        Button(colorPage, jump[1], (i - 1) * 218, 0, 210, 28, function()
            editorScroll:SetVerticalScroll(math.min(offset, editorBody:GetHeight() - editorScroll:GetHeight()))
        end)
    end

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
    Label(columnBody, "Choose any columns beside the character name. Use < / > to reorder; drag header edges to resize.", 0, 0, 660, 11, GOLD)
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
            if index then
                table.remove(columnOrder, index)
                for priority = #state.rosterSort, 1, -1 do
                    if state.rosterSort[priority].key == key then table.remove(state.rosterSort, priority) end
                end
            else columnOrder[#columnOrder + 1] = key end
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
            PickColor(function(color)
                data.color = Clone(color)
                Say(data.name .. " recolored in the roster and encounter headers.")
                settings.ShowSection("Accounts")
                refresh()
            end, data.color or STYLE.accountText)
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
            row.swatch:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
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
                if section == "Themes" then ApplyPreset(THEMES[1])
                elseif section == "Customize Theme" then
                    state.font, state.fontDelta, state.density, state.scale, BACKGROUND[4] = FONT, 0, "comfortable", 1, 0.99
                    state.fontRoles, state.rowHeight, state.rowGap, state.borderSize = {}, nil, 3, 1
                    frame:SetScale(frame.baseScale or 1)
                    ApplyPreset(THEMES[1])
                elseif section == "Icons" then
                    state.iconStyle, state.statusStyle, state.classIcons, state.logo = "icons", "words", true, LOGOS[1]
                    ApplyAppearance()
                end
                Say(section .. " reset.")
            end,
        })
    end)
    Button(settings, "Close", 732, 558, 152, 30, function() settings.RequestClose() end)
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
        if not closing and themeCheckpoint and not SameTheme(CaptureTheme(), themeCheckpoint.appearance) then
            settings.RequestClose(not frame:IsShown())
            return
        end
        if closePrompt then closePrompt:Hide() end
        if dialog then dialog:Hide() end
        addon:CloseColorPicker(settings)
    end)
    settings:Hide()
end

ShowSettings = function(section)
    if accountMenu then accountMenu:Hide() end
    if not themeCheckpoint then RememberTheme() end
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
            AddInstance({
                map = raid.map, name = raid.name, bosses = raid.bosses,
                ilvl = raid.ilvl, release = raid.release,
            }, "Raids", expansion)
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
    frame:SetSize(WINDOW_WIDTH, 720)
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
    titleBar:SetSize(WINDOW_WIDTH - 220, 58)
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
    local settingsButton = Button(frame, "Settings", WINDOW_WIDTH - 172, 14, 115, 28, function() ShowSettings() end)
    settingsButton:SetFrameLevel(titleBar:GetFrameLevel() + 5)
    Button(frame, "X", WINDOW_WIDTH - 44, 14, 28, 28, function() frame:Hide() end)
    tinsert(UISpecialFrames, "AshoholicPreviewFrame")
    local accountButton = Button(frame, "", WINDOW_WIDTH - 256, TAB_TOP, 232, 30, function()
        if settings then settings:Hide() end
        SetVisible(accountMenu, not accountMenu:IsShown())
    end)
    Tip(accountButton, "Accounts to display", "Check any combination of accounts. The first view uses the current sample account. Selection lasts until reload in this UI-only preview.")
    accountMenu = Surface(frame, WINDOW_WIDTH - 320, TAB_TOP + 34, 296, 98 + (#ACCOUNTS + 1) * 31)
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
        tabs[name] = Button(frame, name == "Raids" and "Raids & Dungeons" or name, 24 + (i - 1) * 158, TAB_TOP, 148, 30, function()
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
        local cardWidth = (CONTENT_WIDTH - (#definitions - 1) * 18) / #definitions
        local card = Surface(frame, 24 + (i - 1) * (cardWidth + 18), TAB_TOP + 48, cardWidth, 78)
        card.title = Label(card, "", 12, 9, cardWidth - 24, 10, MUTED)
        card.value = Label(card, "", 12, 30, cardWidth - 24, 22, i == 5 and GOLD or TEAL)
        Label(card, definition[3], 12, 60, cardWidth - 24, 9, MUTED)
        Tip(card, definition[1], definition[3] .. ". Totals combine the selected sample accounts, counting each account once. Preview balances are invented; this does not query your currencies.")
        cards[i] = card
    end
    BuildRoster()
    BuildRaids()
    BuildActivities()
    BuildProgression()
    BuildTrials()
    Label(frame, "PREVIEW ONLY  /  /ash opens your existing roster. Escape closes this window.", 24, 690, 800, 11, MUTED)
    Label(frame, "EBONHOLD / CONCEPT 01", WINDOW_WIDTH - 251, 690, 227, 10, GOLD)
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
        local focused = (state.tab == "Roster" and state.rosterFocus)
            or (state.tab == "Raids" and state.raidsFocus)
        for _, card in ipairs(cards) do SetVisible(card, not focused) end
        accountButton:ClearAllPoints()
        accountButton:SetPoint("TOPLEFT", WINDOW_WIDTH - 256, -TAB_TOP)
        accountMenu:ClearAllPoints()
        accountMenu:SetPoint("TOPLEFT", WINDOW_WIDTH - 320, -(TAB_TOP + 34))
        local tabX = 24
        for _, name in ipairs(tabOrder) do
            local shown = not state.hiddenTabs[name]
            SetVisible(tabs[name], shown)
            if shown then
                tabs[name]:ClearAllPoints()
                tabs[name]:SetPoint("TOPLEFT", tabX, -TAB_TOP)
                tabX = tabX + 158
            end
        end
        for name, page in pairs(pages) do
            local active = state.tab == name
            page:ClearAllPoints()
            page:SetPoint("TOPLEFT", 24, -(focused and FOCUS_PAGE_TOP or PAGE_TOP))
            page:SetHeight(PAGE_HEIGHT + (focused and FOCUS_HEIGHT_GAIN or 0))
            SetVisible(page, active)
            tabs[name]:SetBackdropColor(unpack(active and STYLE.tabActiveBg or STYLE.tabBg))
            tabs[name]:SetBackdropBorderColor(unpack(active and GOLD or BUTTON_BORDER))
            tabs[name].text:SetTextColor(unpack(active and STYLE.tabActiveText or STYLE.tabText))
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
        local scale = math.min(1, (UIParent:GetWidth() - 32) / WINDOW_WIDTH, (UIParent:GetHeight() - 32) / 720)
        frame.baseScale = math.max(0.1, scale)
        frame:SetScale(frame.baseScale * state.scale)
        if state.openTab and state.openTab ~= "last" then state.tab = state.openTab end
        refresh()
        frame:Show()
    end
end
