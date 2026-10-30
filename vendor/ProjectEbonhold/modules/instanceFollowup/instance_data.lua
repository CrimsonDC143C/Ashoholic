-- Instance Followup Data
-- Maps dungeon IDs to their boss encounters in order
-- Structure: [dungeonId][encounterEntry] = "Boss Name"
local addonName, addon = ...

addon.INSTANCE_FOLLOWUP_DATA = {
    -- ========================================
    -- VANILLA DUNGEONS
    -- ========================================
    
    -- Wailing Caverns (Dungeon ID: 1)
    [1] = {
        [585] = "Lady Anacondra",
        [586] = "Lord Cobrahn",
        [587] = "Kresh",
        [588] = "Lord Pythas",
        [589] = "Skum",
        [590] = "Lord Serpentis",
        [591] = "Verdan the Everliving",
        [592] = "Mutanus the Devourer"
    },
    
    -- Scholomance (Dungeon ID: 2)
    [2] = {
        [451] = "Kirtonos the Herald",
        [452] = "Jandice Barov",
        [453] = "Rattlegore",
        [454] = "Marduk Blackpool",
        [455] = "Vectus",
        [456] = "Ras Frostwhisper",
        [457] = "Instructor Malicia",
        [458] = "Doctor Theolen Krastinov",
        [459] = "Lorekeeper Polkelt",
        [460] = "The Ravenian",
        [461] = "Lord Alexei Barov",
        [462] = "Lady Illucia Barov",
        [463] = "Darkmaster Gandling"
    },
    
    -- Ragefire Chasm (Dungeon ID: 4)
    [4] = {
        [430] = "Oggleflint",
        [431] = "Taragaman the Hungerer"
    },
    
    -- The Deadmines (Dungeon ID: 6)
    [6] = {
        [161] = "Rhahk'zor",
        [162] = "Sneed",
        [163] = "Gilnid",
        [164] = "Mr. Smite",
        [165] = "Cookie",
        [166] = "Captain Greenskin",
        [167] = "Edwin VanCleef"
    },
    
    -- Shadowfang Keep (Dungeon ID: 8)
    [8] = {
        [464] = "Rethilgore",
        [465] = "Razorclaw the Butcher",
        [466] = "Baron Silverlaine",
        [467] = "Commander Springvale",
        [468] = "Odo the Blindwatcher",
        [469] = "Fenrus the Devourer",
        [470] = "Wolf Master Nandos",
        [471] = "Archmage Arugal"
    },
    
    -- Blackfathom Deeps (Dungeon ID: 10)
    [10] = {
        [219] = "Ghamoo-ra",
        [220] = "Lady Sarevess",
        [221] = "Gelihast",
        [222] = "Lorgus Jett",
        [224] = "Old Serra'kis",
        [225] = "Twilight Lord Kelris",
        [226] = "Aku'mai"
    },
    
    -- The Stockade (Dungeon ID: 12)
    [12] = {
        [536] = "Targorr the Dread",
        [537] = "Kam Deepfury",
        [538] = "Hamhock",
        [539] = "Bazil Thredd"
    },
    
    -- Gnomeregan (Dungeon ID: 14)
    [14] = {
        [378] = "Viscous Fallout",
        [379] = "Grubbis",
        [380] = "Electrocutioner 6000",
        [381] = "Crowd Pummeler 9-60",
        [382] = "Mekgineer Thermaplugg"
    },
    
    -- Razorfen Kraul (Dungeon ID: 16)
    [16] = {
        [438] = "Roogug",
        [439] = "Aggem Thorncurse",
        [440] = "Death Speaker Jargba",
        [441] = "Overlord Ramtusk",
        [443] = "Charlga Razorflank"
    },
    
    -- Scarlet Monastery (Dungeon ID: 18, 163, 164, 165)
    [18] = {
        [444] = "Interrogator Vishas",
        [445] = "Bloodmage Thalnos"
    },
    [163] = {
        [448] = "Herod"
    },
    [164] = {
        [449] = "High Inquisitor Fairbanks",
        [450] = "High Inquisitor Whitemane"
    },
    [165] = {
        [446] = "Houndmaster Loksey",
        [447] = "Arcanist Doan"
    },
    
    -- Razorfen Downs (Dungeon ID: 20)
    [20] = {
        [432] = "Jergosh the Invoker",
        [433] = "Bazzalan",
        [434] = "Tuten'kash",
        [435] = "Mordresh Fire Eye",
        [436] = "Glutton",
        [437] = "Amnennar the Coldbringer"
    },
    
    -- Uldaman (Dungeon ID: 22)
    [22] = {
        [547] = "Revelosh",
        [548] = "The Lost Dwarves",
        [549] = "Ironaya",
        [551] = "Ancient Stone Keeper",
        [552] = "Galgann Firehammer",
        [553] = "Grimlok",
        [554] = "Archaedas"
    },
    
    -- Zul'Farrak (Dungeon ID: 24)
    [24] = {
        [593] = "Hydromancer Velratha",
        [594] = "Ghaz'rilla",
        [595] = "Antu'sul",
        [596] = "Theka the Martyr",
        [597] = "Witch Doctor Zum'rah",
        [598] = "Nekrum Gutchewer",
        [599] = "Shadowpriest Sezz'ziz",
        [600] = "Chief Ukorz Sandscalp"
    },
    
    -- Maraudon (Dungeon ID: 26, 272, 273)
    [26] = {
        [422] = "Noxxion",
        [423] = "Razorlash"
    },
    [272] = {
        [424] = "Lord Vyletongue"
    },
    [273] = {
        [425] = "Celebras the Cursed",
        [426] = "Landslide",
        [427] = "Tinkerer Gizlock",
        [428] = "Rotgrip",
        [429] = "Princess Theradras"
    },
    
    -- The Temple of Atal'Hakkar (Dungeon ID: 28)
    [28] = {
        [485] = "Atal'alarion",
        [486] = "Dreamscythe",
        [487] = "Weaver",
        [488] = "Jammal'an the Prophet",
        [490] = "Morphaz",
        [491] = "Hazzas",
        [492] = "Avatar of Hakkar",
        [493] = "Shade of Eranikus"
    },
    
    -- Blackrock Depths (Dungeon ID: 30, 276)
    [30] = {
        [227] = "High Interrogator Gerstahn"
    },
    [276] = {
        [228] = "Lord Roccor",
        [229] = "Houndmaster Grebmar",
        [230] = "Ring of Law",
        [231] = "Pyromancer Loregrain",
        [232] = "Lord Incendius",
        [233] = "Warder Stilgiss",
        [234] = "Fineous Darkvire",
        [235] = "Bael'Gar",
        [236] = "General Angerforge",
        [237] = "Golem Lord Argelmach",
        [238] = "Hurley Blackbreath",
        [239] = "Phalanx",
        [240] = "Ribbly Screwspigot",
        [241] = "Plugger Spazzring",
        [242] = "Ambassador Flamelash",
        [243] = "The Seven",
        [244] = "Magmus",
        [245] = "Emperor Dagran Thaurissan"
    },
    
    -- Lower Blackrock Spire (Dungeon ID: 32)
    [32] = {
        [267] = "Highlord Omokk",
        [268] = "Shadow Hunter Vosh'gajin",
        [269] = "War Master Voone",
        [270] = "Mother Smolderweb",
        [271] = "Urok Doomhowl",
        [272] = "Quartermaster Zigris",
        [273] = "Gizrul the Slavener",
        [274] = "Halycon",
        [275] = "Overlord Wyrmthalak"
    },
    
    -- Dire Maul (Dungeon ID: 34, 36, 38)
    [34] = {
        [343] = "Zevrim Thornhoof",
        [344] = "Hydrospawn",
        [345] = "Lethtendris",
        [346] = "Alzzin the Wildshaper"
    },
    [36] = {
        [347] = "Illyanna Ravenoak",
        [348] = "Magister Kalendris",
        [349] = "Immol'thar",
        [350] = "Tendris Warpwood",
        [361] = "Prince Tortheldrin"
    },
    [38] = {
        [362] = "Guard Mol'dar",
        [363] = "Stomper Kreeg",
        [364] = "Guard Fengus",
        [365] = "Guard Slip'kik",
        [366] = "Captain Kromcrush",
        [367] = "Cho'Rush the Observer",
        [368] = "King Gordok"
    },
    
    -- Stratholme (Dungeon ID: 40, 274)
    [40] = {
        [472] = "The Unforgiven",
        [473] = "Hearthsinger Forresten",
        [474] = "Timmy the Cruel",
        [475] = "Cannon Master Willey",
        [476] = "Malor the Zealous",
        [477] = "Archivist Galford",
        [478] = "Balnazzar"
    },
    [274] = {
        [479] = "Baroness Anastari",
        [480] = "Nerub'enkan",
        [481] = "Maleki the Pallid",
        [482] = "Magistrate Barthilas",
        [483] = "Ramnstein the Gorger",
        [484] = "Baron Rivendare"
    },
    
    -- Upper Blackrock Spire (Dungeon ID: 44)
    [44] = {
        [276] = "Pyroguard Emberseer",
        [277] = "Solakar Flamewreath",
        [278] = "Warchief Rend Blackhand",
        [279] = "The Beast",
        [280] = "General Drakkisath"
    },
    
    -- ========================================
    -- VANILLA RAIDS
    -- ========================================
    
    -- Zul'Gurub (Raid ID: 42)
    [42] = {
        [784] = "High Priest Venoxis",
        [785] = "High Priestess Jeklik",
        [786] = "High Priestess Mar'li",
        [787] = "Bloodlord Mandokir",
        [788] = "Edge of Madness",
        [789] = "High Priest Thekal",
        [790] = "Gahz'ranka",
        [791] = "High Priestess Arlokk",
        [792] = "Jin'do the Hexxer",
        [793] = "Hakkar"
    },
    
    -- Onyxia's Lair (Raid ID: 46, 257)
    [46] = {
        [707] = "Onyxia"
    },
    [257] = {
        [708] = "Onyxia"
    },
    
    -- Molten Core (Raid ID: 48)
    [48] = {
        [663] = "Lucifron",
        [664] = "Magmadar",
        [665] = "Gehennas",
        [666] = "Garr",
        [667] = "Shazzrah",
        [668] = "Baron Geddon",
        [669] = "Sulfuron Harbinger",
        [670] = "Golemagg the Incinerator",
        [671] = "Majordomo Executus",
        [672] = "Ragnaros"
    },
    
    -- Blackwing Lair (Raid ID: 50)
    [50] = {
        [610] = "Razorgore the Untamed",
        [611] = "Vaelastrasz the Corrupt",
        [612] = "Broodlord Lashlayer",
        [613] = "Firemaw",
        [614] = "Ebonroc",
        [615] = "Flamegor",
        [616] = "Chromaggus",
        [617] = "Nefarian"
    },
    
    -- Ruins of Ahn'Qiraj (Raid ID: 160)
    [160] = {
        [718] = "Kurinnaxx",
        [719] = "General Rajaxx",
        [720] = "Moam",
        [721] = "Buru the Gorger",
        [722] = "Ayamiss the Hunter",
        [723] = "Ossirian the Unscarred"
    },
    
    -- Temple of Ahn'Qiraj (Raid ID: 161)
    [161] = {
        [709] = "The Prophet Skeram",
        [710] = "Silithid Royalty",
        [711] = "Battleguard Sartura",
        [712] = "Fankriss the Unyielding",
        [713] = "Viscidus",
        [714] = "Princess Huhuran",
        [715] = "Twin Emperors",
        [716] = "Ouro",
        [717] = "C'thun"
    },
    
    -- Naxxramas (Raid ID: 159, 227)
    [159] = {
        [673] = "Anub'Rekhan",
        [677] = "Grand Widow Faerlina",
        [679] = "Maexxna",
        [681] = "Noth the Plaguebringer",
        [683] = "Heigan the Unclean",
        [685] = "Loatheb",
        [687] = "Instructor Razuvious",
        [690] = "Gothik the Harvester",
        [692] = "The Four Horsemen",
        [694] = "Patchwerk",
        [696] = "Grobbulus",
        [698] = "Gluth",
        [700] = "Thaddius",
        [702] = "Sapphiron",
        [704] = "Kel'Thuzad"
    },
    [227] = {
        [706] = "Kel'Thuzad"
    },
    
    -- ========================================
    -- THE BURNING CRUSADE DUNGEONS
    -- ========================================
    
    -- Hellfire Ramparts (Dungeon ID: 136, 188)
    [136] = {
        [392] = "Watchkeeper Gargolmar",
        [394] = "Omor the Unscarred",
        [396] = "Vazruden the Herald"
    },
    [188] = {
        [397] = "Vazruden the Herald"
    },
    
    -- The Blood Furnace (Dungeon ID: 137, 187)
    [137] = {
        [401] = "The Maker",
        [403] = "Broggok",
        [405] = "Keli'dan the Breaker"
    },
    [187] = {
        [406] = "Keli'dan the Breaker"
    },
    
    -- The Shattered Halls (Dungeon ID: 138, 189)
    [138] = {
        [407] = "Grand Warlock Nethekurse",
        [409] = "Blood Guard Porung",
        [410] = "Warbringer O'mrogg",
        [412] = "Warchief Kargath Bladefist"
    },
    [189] = {
        [413] = "Warchief Kargath Bladefist"
    },
    
    -- The Slave Pens (Dungeon ID: 140, 184)
    [140] = {
        [301] = "Mennu the Betrayer",
        [302] = "Rokmar the Crackler",
        [303] = "Quagmirran"
    },
    [184] = {
        [304] = "Mennu the Betrayer",
        [305] = "Rokmar the Crackler",
        [306] = "Quagmirran"
    },
    
    -- The Underbog (Dungeon ID: 146, 186)
    [146] = {
        [320] = "Hungarfen",
        [322] = "Ghaz'an",
        [329] = "Swamplord Musel'ek",
        [331] = "The Black Stalker"
    },
    [186] = {
        [332] = "The Black Stalker"
    },
    
    -- The Steamvault (Dungeon ID: 147, 185)
    [147] = {
        [314] = "Hydromancer Thespia",
        [316] = "Mekgineer Steamrigger",
        [318] = "Warlord Kalithresh"
    },
    [185] = {
        [319] = "Warlord Kalithresh"
    },
    
    -- Mana-Tombs (Dungeon ID: 148, 179)
    [148] = {
        [203] = "Pandemonius",
        [204] = "Tavarok",
        [205] = "Nexus-Prince Shaffar"
    },
    [179] = {
        [248] = "Pandemonius",
        [249] = "Tavarok",
        [250] = "Yor",
        [251] = "Nexus-Prince Shaffar"
    },
    
    -- Auchenai Crypts (Dungeon ID: 149, 178)
    [149] = {
        [201] = "Shirrak the Dead Watcher",
        [202] = "Exarch Maladaar"
    },
    [178] = {
        [246] = "Shirrak the Dead Watcher",
        [247] = "Exarch Maladaar"
    },
    
    -- Sethekk Halls (Dungeon ID: 150, 180)
    [150] = {
        [206] = "Darkweaver Syth",
        [207] = "Talon King Ikiss"
    },
    [180] = {
        [252] = "Darkweaver Syth",
        [253] = "Anzu",
        [254] = "Talon King Ikiss"
    },
    
    -- Shadow Labyrinth (Dungeon ID: 151, 181)
    [151] = {
        [208] = "Ambassador Hellmaw",
        [209] = "Blackheart the Inciter",
        [210] = "Grandmaster Vorpil",
        [211] = "Murmur"
    },
    [181] = {
        [255] = "Ambassador Hellmaw",
        [256] = "Blackheart the Inciter",
        [257] = "Grandmaster Vorpil",
        [258] = "Murmur"
    },
    
    -- Old Hillsbrad Foothills (Dungeon ID: 170, 171, 183)
    [170] = {
        [281] = "Epoch Hunter"
    },
    [171] = {
        [283] = "Captain Skarloc",
        [285] = "Lieutenant Drake",
        [287] = "Chrono Lord Deja",
        [289] = "Temporus",
        [291] = "Aeonus"
    },
    [183] = {
        [282] = "Epoch Hunter"
    },
    
    -- The Black Morass (Dungeon ID: 182)
    [182] = {
        [292] = "Aeonus"
    },
    
    -- The Mechanar (Dungeon ID: 172, 192)
    [172] = {
        [513] = "Mechano-Lord Capacitus",
        [515] = "Nethermancer Sepethrea",
        [517] = "Pathaleon the Calculator"
    },
    [192] = {
        [518] = "Pathaleon the Calculator"
    },
    
    -- The Botanica (Dungeon ID: 173, 191)
    [173] = {
        [502] = "Commander Sarannis",
        [505] = "High Botanist Freywinn",
        [507] = "Thorngrin the Tender",
        [509] = "Laj",
        [511] = "Warp Splinter"
    },
    [191] = {
        [512] = "Warp Splinter"
    },
    
    -- The Arcatraz (Dungeon ID: 174, 190)
    [174] = {
        [494] = "Zereketh the Unbound",
        [496] = "Dalliah the Doomsayer",
        [498] = "Wrath-Scryer Soccothrates",
        [500] = "Harbinger Skyriss"
    },
    [190] = {
        [501] = "Harbinger Skyriss"
    },
    
    -- Magisters' Terrace (Dungeon ID: 198, 201)
    [198] = {
        [414] = "Selin Fireheart",
        [416] = "Vexallus",
        [418] = "Priestess Delrissa",
        [420] = "Kael'thas Sunstrider"
    },
    [201] = {
        [421] = "Kael'thas Sunstrider"
    },
    
    -- ========================================
    -- THE BURNING CRUSADE RAIDS
    -- ========================================
    
    -- Karazhan (Raid ID: 175)
    [175] = {
        [652] = "Attumen the Huntsman",
        [653] = "Moroes",
        [654] = "Maiden of the Virtue",
        [655] = "Opera Event",
        [656] = "The Curator",
        [657] = "Terestian Illhoof",
        [658] = "Shade of Aran",
        [659] = "Netherspite",
        [660] = "Chess Event",
        [661] = "Prince Malchezaar"
    },
    
    -- Karazhan - Nightbane (Raid ID: 48) - Note: shares with MC
    -- [662] = "Nightbane" - handled separately
    
    -- Magtheridon's Lair (Raid ID: 176)
    [176] = {
        [651] = "Magtheridon"
    },
    
    -- Gruul's Lair (Raid ID: 177)
    [177] = {
        [649] = "High King Maulgar",
        [650] = "Gruul the Dragonkiller"
    },
    
    -- Serpentshrine Cavern (Raid ID: 194)
    [194] = {
        [623] = "Hydross the Unstable",
        [624] = "The Lurker Below",
        [625] = "Leotheras the Blind",
        [626] = "Fathom-Lord Karathress",
        [627] = "Morogrim Tidewalker",
        [628] = "Lady Vashj"
    },
    
    -- Tempest Keep (The Eye) (Raid ID: 193)
    [193] = {
        [730] = "Al'ar",
        [731] = "Void Reaver",
        [732] = "High Astromancer Solarian",
        [733] = "Kael'thas Sunstrider"
    },
    
    -- Battle for Mount Hyjal (Raid ID: 195)
    [195] = {
        [618] = "Rage Winterchill",
        [619] = "Anetheron",
        [620] = "Kaz'rogal",
        [621] = "Azgalor",
        [622] = "Archimonde"
    },
    
    -- Black Temple (Raid ID: 196)
    [196] = {
        [601] = "High Warlord Naj'entus",
        [602] = "Supremus",
        [603] = "Shade of Akama",
        [604] = "Teron Gorefiend",
        [605] = "Gurtogg Bloodboil",
        [606] = "Reliquary of Souls",
        [607] = "Mother Shahraz",
        [608] = "The Illidari Council",
        [609] = "Illidan Stormrage"
    },
    
    -- Zul'Aman (Raid ID: 197)
    [197] = {
        [772] = "Archavon the Stone Watcher",
        [774] = "Emalon the Storm Watcher",
        [776] = "Koralon the Flame Watcher",
        [778] = "Akil'zon",
        [779] = "Nalorakk",
        [780] = "Jan'alai",
        [781] = "Halazzi",
        [782] = "Hex Lord Malacrass",
        [783] = "Zul'jin"
    },
    
    -- Sunwell Plateau (Raid ID: 199)
    [199] = {
        [724] = "Kalecgos",
        [725] = "Brutallus",
        [726] = "Felmyst",
        [727] = "Eredar Twins",
        [728] = "M'uru",
        [729] = "Kil'jaeden"
    },
    
    -- ========================================
    -- WRATH OF THE LICH KING DUNGEONS
    -- ========================================
    
    -- Utgarde Keep (Dungeon ID: 202, 242)
    [202] = {
        [571] = "Prince Keleseth",
        [573] = "Skarvold & Dalronn",
        [575] = "Ingvar the Plunderer"
    },
    [242] = {
        [576] = "Ingvar the Plunderer"
    },
    
    -- Utgarde Pinnacle (Dungeon ID: 203, 205)
    [203] = {
        [577] = "Svala Sorrowgrave",
        [579] = "Gortok Palehoof",
        [581] = "Skadi the Ruthless",
        [583] = "King Ymiron"
    },
    [205] = {
        [584] = "King Ymiron"
    },
    
    -- Azjol-Nerub (Dungeon ID: 204, 241)
    [204] = {
        [216] = "Krik'thir the Gatewatcher",
        [217] = "Hadronox",
        [218] = "Anub'arak"
    },
    [241] = {
        [264] = "Krik'thir the Gatewatcher",
        [265] = "Hadronox",
        [266] = "Anub'arak"
    },
    
    -- The Oculus (Dungeon ID: 206, 211)
    [206] = {
        [528] = "Drakos the Interrogator",
        [530] = "Varos Cloudstrider",
        [532] = "Mage-Lord Urom",
        [534] = "Ley-Guardian Eregos"
    },
    [211] = {
        [535] = "Ley-Guardian Eregos"
    },
    
    -- Halls of Lightning (Dungeon ID: 207, 212)
    [207] = {
        [555] = "General Bjarngrim",
        [557] = "Volkhan",
        [559] = "Ionar",
        [561] = "Loken"
    },
    [212] = {
        [562] = "Loken"
    },
    
    -- Halls of Stone (Dungeon ID: 208, 213)
    [208] = {
        [563] = "Krystallus",
        [565] = "Maiden of Grief",
        [567] = "Tribunal of Ages",
        [569] = "Sjonnir the Ironshaper"
    },
    [213] = {
        [570] = "Sjonnir the Ironshaper"
    },
    
    -- The Culling of Stratholme (Dungeon ID: 209, 210)
    [209] = {
        [293] = "Meathook",
        [294] = "Salram the Fleshcrafter",
        [295] = "Chrono-Lord Epoch",
        [296] = "Mal'ganis"
    },
    [210] = {
        [297] = "Meathook",
        [298] = "Salram the Fleshcrafter",
        [299] = "Chrono-Lord Epoch",
        [300] = "Mal'ganis"
    },
    
    -- Drak'Tharon Keep (Dungeon ID: 214, 215)
    [214] = {
        [369] = "Trollgore",
        [371] = "Novos the Summoner",
        [373] = "King Dred",
        [375] = "The Prophet Tharon'ja"
    },
    [215] = {
        [376] = "The Prophet Tharon'ja"
    },
    
    -- Gundrak (Dungeon ID: 216, 217)
    [216] = {
        [383] = "Slad'ran",
        [385] = "Drakkari Colossus",
        [387] = "Moorabi",
        [389] = "Eck the Ferocious",
        [390] = "Gal'darah"
    },
    [217] = {
        [391] = "Gal'darah"
    },
    
    -- Ahn'kahet: The Old Kingdom (Dungeon ID: 218, 219)
    [218] = {
        [212] = "Elder Nadox",
        [213] = "Prince Taldaram",
        [214] = "Jedoga Shadowseeker",
        [215] = "Herald Volazj"
    },
    [219] = {
        [259] = "Elder Nadox",
        [260] = "Prince Taldaram",
        [261] = "Jedoga Shadowseeker",
        [262] = "Amanitar",
        [263] = "Herald Volazj"
    },
    
    -- The Violet Hold (Dungeon ID: 220, 221)
    [220] = {
        [540] = "Dextren Ward",
        [541] = "First Prisoner",
        [543] = "Second Prisoner",
        [545] = "Cyanigosa"
    },
    [221] = {
        [546] = "Cyanigosa"
    },
    
    -- The Nexus (Dungeon ID: 225, 226)
    [225] = {
        [519] = "Frozen Commander",
        [520] = "Grand Magus Telestra",
        [522] = "Anomalus",
        [524] = "Ormorok the Tree-Shaper",
        [526] = "Keristrasza"
    },
    [226] = {
        [527] = "Keristrasza"
    },
    
    -- Trial of the Champion (Dungeon ID: 245, 249)
    [245] = {
        [334] = "Grand Champions",
        [338] = "Argent Champion",
        [340] = "The Black Knight"
    },
    [249] = {
        [341] = "The Black Knight"
    },
    
    -- The Forge of Souls (Dungeon ID: 251, 252)
    [251] = {
        [829] = "Bronjahm",
        [831] = "Devourer of Souls"
    },
    [252] = {
        [832] = "Devourer of Souls"
    },
    
    -- Pit of Saron (Dungeon ID: 253, 254)
    [253] = {
        [833] = "Forgemaster Garfrost",
        [835] = "Krick",
        [837] = "Overlord Tyrannus"
    },
    [254] = {
        [838] = "Overlord Tyrannus"
    },
    
    -- Halls of Reflection (Dungeon ID: 255, 256)
    [255] = {
        [839] = "Marwyn",
        [841] = "Falric",
        [843] = "Escaped from Arthas"
    },
    [256] = {
        [844] = "Escaped from Arthas"
    },
    
    -- ========================================
    -- WRATH OF THE LICH KING RAIDS
    -- ========================================
    
    -- The Eye of Eternity (Raid ID: 223, 237)
    [223] = {
        [734] = "Malygos"
    },
    [237] = {
        [735] = "Malygos"
    },
    
    -- The Obsidian Sanctum (Raid ID: 224, 238)
    [224] = {
        [736] = "Tenebron",
        [738] = "Shadron",
        [740] = "Vesperon",
        [742] = "Sartharion"
    },
    [238] = {
        [743] = "Sartharion"
    },
    
    -- Vault of Archavon (Raid ID: 239, 240)
    [239] = {
        [883] = "Agathelos the Raging",
        [885] = "Toravon the Ice Watcher"
    },
    [240] = {
        [886] = "Toravon the Ice Watcher"
    },
    
    -- Ulduar (Raid ID: 243, 244)
    [243] = {
        [744] = "Flame Leviathan",
        [745] = "Ignis the Furnace Master",
        [746] = "Razorscale",
        [747] = "XT-002 Deconstructor",
        [748] = "The Iron Council",
        [749] = "Kologarn",
        [750] = "Auriaya",
        [751] = "Hodir",
        [752] = "Thorim",
        [753] = "Freya",
        [754] = "Mimiron",
        [755] = "General Vezax",
        [756] = "Yogg-Saron",
        [757] = "Algalon the Observer"
    },
    [244] = {
        [758] = "Flame Leviathan",
        [759] = "Ignis the Furnace Master",
        [760] = "Razorscale",
        [761] = "XT-002 Deconstructor",
        [762] = "The Iron Council",
        [763] = "Kologarn",
        [764] = "Auriaya",
        [765] = "Hodir",
        [766] = "Thorim",
        [767] = "Freya",
        [768] = "Mimiron",
        [769] = "General Vezax",
        [770] = "Yogg-Saron",
        [771] = "Algalon the Observer"
    },
    
    -- Trial of the Crusader (Raid ID: 246, 247, 248, 250)
    [246] = {
        [629] = "Northrend Beasts",
        [633] = "Lord Jaraxxus",
        [637] = "Faction Champions",
        [641] = "Val'kyr Twins",
        [645] = "Anub'arak"
    },
    [247] = {
        [647] = "Anub'arak"
    },
    [248] = {
        [646] = "Anub'arak"
    },
    [250] = {
        [648] = "Anub'arak"
    },
    
    -- Icecrown Citadel (Raid ID: 279, 280)
    [279] = {
        [845] = "Lord Marrowgar",
        [846] = "Lady Deathwhisper",
        [847] = "Icecrown Gunship Battle",
        [848] = "Deathbringer Saurfang",
        [849] = "Festergut",
        [850] = "Rotface",
        [851] = "Professor Putricide",
        [852] = "Blood Council",
        [853] = "Queen Lana'thel",
        [854] = "Valithria Dreamwalker",
        [855] = "Sindragosa",
        [856] = "The Lich King"
    },
    [280] = {
        [857] = "Lord Marrowgar",
        [858] = "Lady Deathwhisper",
        [859] = "Icecrown Gunship Battle",
        [860] = "Deathbringer Saurfang",
        [861] = "Festergut",
        [862] = "Rotface",
        [863] = "Professor Putricide",
        [864] = "Blood Council",
        [865] = "Queen Lana'thel",
        [866] = "Valithria Dreamwalker",
        [867] = "Sindragosa",
        [868] = "The Lich King"
    },
    
    -- The Ruby Sanctum (Raid ID: 293, 294)
    [293] = {
        [887] = "Halion"
    },
    [294] = {
        [888] = "Halion"
    }
};