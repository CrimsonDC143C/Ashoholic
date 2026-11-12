-- The live and preview watchlists share these dungeon names and expansion
-- mappings. Dungeon entries are names only: their keys are not server IDs.
local addonName = ...
local addon = _G[addonName]

local Encounters = {}
addon.EncounterCatalog = Encounters

Encounters.raidExpansions = {
    [409] = 1, [469] = 1, [309] = 1, [509] = 1, [531] = 1,
    [532] = 2, [565] = 2, [544] = 2, [548] = 2, [550] = 2,
    [568] = 2, [534] = 2, [564] = 2, [580] = 2,
    [533] = 3, [616] = 3, [615] = 3, [603] = 3, [649] = 3,
    [249] = 3, [631] = 3, [724] = 3, [624] = 3,
}

Encounters.dungeons = {
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

local EXPANSION_NAMES = {
    [1] = "Vanilla",
    [2] = "The Burning Crusade",
    [3] = "Wrath of the Lich King",
    [0] = "Other",
}

local function IsPositiveInteger(value)
    return type(value) == "number" and value > 0
        and value < math.huge and value == math.floor(value)
end

local function NewCategory(name)
    local category = { name = name, key = name, children = {}, bosses = {}, groups = {} }
    for expansion = 3, 1, -1 do
        local group = {
            name = EXPANSION_NAMES[expansion],
            key = name .. ":exp:" .. expansion,
            children = {},
            bosses = {},
        }
        category.children[#category.children + 1] = group
        category.groups[expansion] = group
    end
    return category
end

local function AddInstance(category, expansion, instance)
    local group = category.groups[expansion]
    if not group then
        group = category.groups[0]
        if not group then
            group = { name = EXPANSION_NAMES[0], key = category.key .. ":exp:other", children = {}, bosses = {} }
            category.groups[0] = group
            category.children[#category.children + 1] = group
        end
    end
    group.children[#group.children + 1] = instance
    for _, boss in ipairs(instance.bosses) do
        group.bosses[#group.bosses + 1] = boss
        category.bosses[#category.bosses + 1] = boss
    end
end

-- Build a display tree from the companion's real raid IDs and the local
-- dungeon names. Stable watchlist keys do not depend on the order of either list.
function Encounters.Build(raidCatalog)
    if type(raidCatalog) ~= "table" or #raidCatalog == 0 then
        error("Ashoholic cannot build the watchlist without Ebonhold's raid catalogue.")
    end
    local raids, dungeons = NewCategory("Raids"), NewCategory("Dungeons")
    local maps, keys = {}, {}

    for _, raid in ipairs(raidCatalog) do
        if type(raid) ~= "table" or not IsPositiveInteger(raid.map)
            or type(raid.name) ~= "string" or raid.name == ""
            or type(raid.bosses) ~= "table" or #raid.bosses == 0
            or (raid.ilvl ~= nil and not IsPositiveInteger(raid.ilvl))
            or (raid.release ~= nil and not IsPositiveInteger(raid.release))
            or maps[raid.map] then
            error("Ashoholic received an invalid raid catalogue entry.")
        end
        maps[raid.map] = true
        local instance = {
            kind = "Raids", key = "Raids:map:" .. raid.map, name = raid.name,
            ilvl = raid.ilvl, release = raid.release, bosses = {},
        }
        for _, boss in ipairs(raid.bosses) do
            if type(boss) ~= "table" or not IsPositiveInteger(boss.id)
                or type(boss.name) ~= "string" or boss.name == "" then
                error("Ashoholic received an invalid raid encounter.")
            end
            local key = "raid:" .. boss.id
            if keys[key] then
                error("Ashoholic received a duplicate raid encounter ID: " .. boss.id)
            end
            keys[key] = true
            instance.bosses[#instance.bosses + 1] = { key = key, id = boss.id, name = boss.name }
        end
        local expansion = Encounters.raidExpansions[raid.map]
        if not expansion then
            print("|cffffca63Ashoholic:|r No expansion mapping for " .. raid.name .. "; shown under Other.")
        end
        AddInstance(raids, expansion or 0, instance)
    end

    for _, dungeon in ipairs(Encounters.dungeons) do
        local name = dungeon[2]
        local instance = { kind = "Dungeons", key = "Dungeons:name:" .. name, name = name, bosses = {} }
        for bossName in string.gmatch(dungeon[3], "[^;]+") do
            local key = "dungeon:" .. #name .. ":" .. name .. ":" .. bossName
            if keys[key] then
                error("Ashoholic has a duplicate dungeon encounter: " .. bossName)
            end
            keys[key] = true
            instance.bosses[#instance.bosses + 1] = { key = key, name = bossName }
        end
        AddInstance(dungeons, dungeon[1], instance)
    end

    for _, category in ipairs({ raids, dungeons }) do
        category.groups = nil
        for _, group in ipairs(category.children) do
            table.sort(group.children, function(left, right) return left.name < right.name end)
        end
    end
    return { raids, dungeons }
end
