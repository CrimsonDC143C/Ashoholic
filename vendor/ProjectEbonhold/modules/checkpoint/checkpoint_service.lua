local addonName, addon = ...

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.CheckpointService = {}

local CheckpointService = ProjectEbonhold.CheckpointService

local checkpointDefinitions = {
    { id = 2, name = "Stormwind, Elwynn", mapId = 31, serverMapId = 0, x = 0.3, y = 0.38, faction = "ALLIANCE" },
    { id = 4, name = "Sentinel Hill, Westfall", mapId = 40, serverMapId = 0, x = 0.5656334, y = 0.5268393, faction = "ALLIANCE" },
    { id = 5, name = "Lakeshire, Redridge", mapId = 37, serverMapId = 0, x = 0.3042918, y = 0.5898807, faction = "ALLIANCE" },
    { id = 6, name = "Ironforge, Dun Morogh", mapId = 28, serverMapId = 0, x = 0.6, y = 0.28, faction = "ALLIANCE" },
    { id = 7, name = "Menethil Harbor, Wetlands", mapId = 41, serverMapId = 0, x = 0.0952036, y = 0.5965870, faction = "ALLIANCE" },
    { id = 8, name = "Thelsamar, Loch Modan", mapId = 36, serverMapId = 0, x = 0.3394296, y = 0.5079466, faction = "ALLIANCE" },
    { id = 10, name = "The Sepulcher, Silverpine Forest", mapId = 22, serverMapId = 0, x = 0.4555738, y = 0.4242168, faction = "HORDE" },
    { id = 11, name = "Undercity, Tirisfal", mapId = 21, serverMapId = 0, x = 0.61, y = 0.75, faction = "HORDE" },
    { id = 12, name = "Darkshire, Duskwood", mapId = 35, serverMapId = 0, x = 0.7752, y = 0.4428, faction = "ALLIANCE" },
    { id = 13, name = "Tarren Mill, Hillsbrad", mapId = 25, serverMapId = 0, x = 0.62189, y = 0.20351, faction = "HORDE" },
    { id = 14, name = "Southshore, Hillsbrad", mapId = 25, serverMapId = 0, x = 0.4944209, y = 0.5210063, faction = "ALLIANCE" },
    { id = 16, name = "Refuge Pointe, Arathi", mapId = 17, serverMapId = 0, x = 0.4579009, y = 0.4613320, faction = "ALLIANCE" },
    { id = 17, name = "Hammerfall, Arathi", mapId = 17, serverMapId = 0, x = 0.7306175, y = 0.3262320, faction = "HORDE" },
    { id = 18, name = "Booty Bay, Stranglethorn", mapId = 38, serverMapId = 0, x = 0.2681627, y = 0.7699598, faction = "HORDE" },
    { id = 19, name = "Booty Bay, Stranglethorn", mapId = 38, serverMapId = 0, x = 0.2752882, y = 0.7767203, faction = "ALLIANCE" },
    { id = 20, name = "Grom'gol, Stranglethorn", mapId = 38, serverMapId = 0, x = 0.3250998, y = 0.2927551, faction = "HORDE" },
    { id = 21, name = "Kargath, Badlands", mapId = 18, serverMapId = 0, x = 0.04056, y = 0.44889, faction = "HORDE" },
    { id = 22, name = "Thunder Bluff, Mulgore", mapId = 10, serverMapId = 1, x = 0.39, y = 0.26, faction = "HORDE" },
    { id = 23, name = "Orgrimmar, Durotar", mapId = 5, serverMapId = 1, x = 0.44, y = 0.03, faction = "HORDE" },
    { id = 25, name = "Crossroads, The Barrens", mapId = 12, serverMapId = 1, x = 0.51503, y = 0.30406, faction = "HORDE" },
    { id = 26, name = "Auberdine, Darkshore", mapId = 43, serverMapId = 1, x = 0.36397, y = 0.45617, faction = "ALLIANCE" },
    { id = 27, name = "Rut'theran Village, Teldrassil", mapId = 42, serverMapId = 1, x = 0.5840000, y = 0.9392737, faction = "ALLIANCE" },
    { id = 28, name = "Astranaar, Ashenvale", mapId = 44, serverMapId = 1, x = 0.34495, y = 0.48015, faction = "ALLIANCE" },
    { id = 29, name = "Sun Rock Retreat, Stonetalon Mountains", mapId = 82, serverMapId = 1, x = 0.4516409, y = 0.5988781, faction = "HORDE" },
    { id = 30, name = "Freewind Post, Thousand Needles", mapId = 62, serverMapId = 1, x = 0.4502197, y = 0.4912647, faction = "HORDE" },
    { id = 31, name = "Thalanaar, Feralas", mapId = 122, serverMapId = 1, x = 0.89461, y = 0.45868, faction = "ALLIANCE" },
    { id = 32, name = "Theramore, Dustwallow Marsh", mapId = 142, serverMapId = 1, x = 0.6745867, y = 0.5120106, faction = "ALLIANCE" },
    { id = 33, name = "Stonetalon Peak, Stonetalon Mountains", mapId = 82, serverMapId = 1, x = 0.3653556, y = 0.0723338, faction = "ALLIANCE" },
    { id = 37, name = "Nijel's Point, Desolace", mapId = 102, serverMapId = 1, x = 0.6467129, y = 0.1043536, faction = "ALLIANCE" },
    { id = 38, name = "Shadowprey Village, Desolace", mapId = 102, serverMapId = 1, x = 0.2156315, y = 0.7404220, faction = "HORDE" },
    { id = 39, name = "Gadgetzan, Tanaris", mapId = 162, serverMapId = 1, x = 0.5095420, y = 0.2932543, faction = "ALLIANCE" },
    { id = 40, name = "Gadgetzan, Tanaris", mapId = 162, serverMapId = 1, x = 0.5161754, y = 0.2551935, faction = "HORDE" },
    { id = 41, name = "Feathermoon, Feralas", mapId = 122, serverMapId = 1, x = 0.3025924, y = 0.4331942, faction = "ALLIANCE" },
    { id = 42, name = "Camp Mojache, Feralas", mapId = 122, serverMapId = 1, x = 0.7542960, y = 0.4431352, faction = "HORDE" },
    { id = 43, name = "Aerie Peak, The Hinterlands", mapId = 27, serverMapId = 0, x = 0.11111, y = 0.46088, faction = "ALLIANCE" },
    { id = 44, name = "Valormok, Azshara", mapId = 182, serverMapId = 1, x = 0.2195491, y = 0.4969011, faction = "HORDE" },
    { id = 45, name = "Nethergarde Keep, Blasted Lands", mapId = 20, serverMapId = 0, x = 0.65495, y = 0.24429, faction = "ALLIANCE" },
    { id = 48, name = "Bloodvenom Post, Felwood", mapId = 183, serverMapId = 1, x = 0.3441543, y = 0.5386782, faction = "HORDE" },
    { id = 49, name = "Moonglade", mapId = 242, serverMapId = 1, x = 0.4791163, y = 0.6711012, faction = "ALLIANCE" },
    { id = 52, name = "Everlook, Winterspring", mapId = 282, serverMapId = 1, x = 0.6233413, y = 0.3668732, faction = "ALLIANCE" },
    { id = 53, name = "Everlook, Winterspring", mapId = 282, serverMapId = 1, x = 0.6048526, y = 0.3634380, faction = "HORDE" },
    { id = 55, name = "Brackenwall Village, Dustwallow Marsh", mapId = 142, serverMapId = 1, x = 0.35565, y = 0.3183, faction = "HORDE" },
    { id = 56, name = "Stonard, Swamp of Sorrows", mapId = 39, serverMapId = 0, x = 0.4605266, y = 0.5467925, faction = "HORDE" },
    { id = 58, name = "Zoram'gar Outpost, Ashenvale", mapId = 44, serverMapId = 1, x = 0.12153, y = 0.33803, faction = "HORDE" },
    { id = 59, name = "Dun Baldar, Alterac Valley", mapId = 402, serverMapId = 30, x = 0.4313628, y = 0.1809582, faction = "ALLIANCE" },
    { id = 60, name = "Frostwolf Keep, Alterac Valley", mapId = 402, serverMapId = 30, x = 0.4957971, y = 0.8569405, faction = "HORDE" },
    { id = 61, name = "Splintertree Post, Ashenvale", mapId = 44, serverMapId = 1, x = 0.7325809, y = 0.6167224, faction = "HORDE" },
    { id = 64, name = "Talrendis Point, Azshara", mapId = 182, serverMapId = 1, x = 0.1190252, y = 0.7747658, faction = "ALLIANCE" },
    { id = 65, name = "Talonbranch Glade, Felwood", mapId = 183, serverMapId = 1, x = 0.6245734, y = 0.2419443, faction = "ALLIANCE" },
    { id = 66, name = "Chillwind Camp, Western Plaguelands", mapId = 23, serverMapId = 0, x = 0.42948, y = 0.84954, faction = "ALLIANCE" },
    { id = 67, name = "Light's Hope Chapel, Eastern Plaguelands", mapId = 24, serverMapId = 0, x = 0.7574078, y = 0.5332380, faction = "ALLIANCE" },
    { id = 68, name = "Light's Hope Chapel, Eastern Plaguelands", mapId = 24, serverMapId = 0, x = 0.7440347, y = 0.5122817, faction = "HORDE" },
    { id = 69, name = "Moonglade", mapId = 242, serverMapId = 1, x = 0.3215004, y = 0.6633459, faction = "HORDE" },
    { id = 70, name = "Flame Crest, Burning Steppes", mapId = 30, serverMapId = 0, x = 0.65577, y = 0.24219, faction = "HORDE" },
    { id = 71, name = "Morgan's Vigil, Burning Steppes", mapId = 30, serverMapId = 0, x = 0.8438180, y = 0.6830447, faction = "ALLIANCE" },
    { id = 72, name = "Cenarion Hold, Silithus", mapId = 262, serverMapId = 1, x = 0.4882564, y = 0.3672350, faction = "HORDE" },
    { id = 73, name = "Cenarion Hold, Silithus", mapId = 262, serverMapId = 1, x = 0.5068334, y = 0.3458997, faction = "ALLIANCE" },
    { id = 74, name = "Thorium Point, Searing Gorge", mapId = 29, serverMapId = 0, x = 0.3788698, y = 0.3042622, faction = "ALLIANCE" },
    { id = 75, name = "Thorium Point, Searing Gorge", mapId = 29, serverMapId = 0, x = 0.3482950, y = 0.3058353, faction = "HORDE" },
    { id = 76, name = "Revantusk Village, The Hinterlands", mapId = 27, serverMapId = 0, x = 0.8170130, y = 0.8189325, faction = "HORDE" },
    { id = 77, name = "Camp Taurajo, The Barrens", mapId = 12, serverMapId = 1, x = 0.44463, y = 0.59103, faction = "HORDE" },
    { id = 79, name = "Marshal's Refuge, Un'Goro Crater", mapId = 202, serverMapId = 1, x = 0.4529819, y = 0.0596566, faction = "BOTH" },
    { id = 80, name = "Ratchet, The Barrens", mapId = 12, serverMapId = 1, x = 0.63118, y = 0.37108, faction = "BOTH" },
    { id = 82, name = "Silvermoon City", mapId = 463, serverMapId = 530, x = 0.54, y = 0.5, faction = "HORDE" },
    { id = 83, name = "Tranquillien, Ghostlands", mapId = 464, serverMapId = 530, x = 0.4548355, y = 0.3055438, faction = "HORDE" },
    { id = 93, name = "Blood Watch, Bloodmyst Isle", mapId = 477, serverMapId = 530, x = 0.5761257, y = 0.5402009, faction = "ALLIANCE" },
    { id = 94, name = "The Exodar", mapId = 465, serverMapId = 530, x = 0.31, y = 0.46, faction = "ALLIANCE" },
    { id = 99, name = "Thrallmar, Hellfire Peninsula", mapId = 466, serverMapId = 530, x = 0.5626811, y = 0.3637750, faction = "HORDE" },
    { id = 100, name = "Honor Hold, Hellfire Peninsula", mapId = 466, serverMapId = 530, x = 0.5464745, y = 0.6256755, faction = "ALLIANCE" },
    { id = 101, name = "Temple of Telhamat, Hellfire Peninsula", mapId = 466, serverMapId = 530, x = 0.2513316, y = 0.3722947, faction = "ALLIANCE" },
    { id = 102, name = "Falcon Watch, Hellfire Peninsula", mapId = 466, serverMapId = 530, x = 0.2785458, y = 0.6006998, faction = "HORDE" },
    { id = 117, name = "Telredor, Zangarmarsh", mapId = 468, serverMapId = 530, x = 0.6785744, y = 0.5136109, faction = "ALLIANCE" },
    { id = 118, name = "Zabra'jin, Zangarmarsh", mapId = 468, serverMapId = 530, x = 0.33001, y = 0.51191, faction = "HORDE" },
    { id = 119, name = "Telaar, Nagrand", mapId = 478, serverMapId = 530, x = 0.5412727, y = 0.7522171, faction = "ALLIANCE" },
    { id = 120, name = "Garadar, Nagrand", mapId = 478, serverMapId = 530, x = 0.57239, y = 0.35369, faction = "HORDE" },
    { id = 121, name = "Allerian Stronghold, Terokkar Forest", mapId = 479, serverMapId = 530, x = 0.5945469, y = 0.5520111, faction = "ALLIANCE" },
    { id = 122, name = "Area 52, Netherstorm", mapId = 480, serverMapId = 530, x = 0.3385153, y = 0.6387282, faction = "BOTH" },
    { id = 123, name = "Shadowmoon Village, Shadowmoon Valley", mapId = 474, serverMapId = 530, x = 0.30326, y = 0.29201, faction = "HORDE" },
    { id = 124, name = "Wildhammer Stronghold, Shadowmoon Valley", mapId = 474, serverMapId = 530, x = 0.3761, y = 0.55477, faction = "ALLIANCE" },
    { id = 125, name = "Sylvanaar, Blade's Edge Mountains", mapId = 476, serverMapId = 530, x = 0.3781333, y = 0.6151198, faction = "ALLIANCE" },
    { id = 126, name = "Thunderlord Stronghold, Blade's Edge Mountains", mapId = 476, serverMapId = 530, x = 0.5207194, y = 0.5424783, faction = "HORDE" },
    { id = 127, name = "Stonebreaker Hold, Terokkar Forest", mapId = 479, serverMapId = 530, x = 0.4925006, y = 0.4353695, faction = "HORDE" },
    { id = 128, name = "Shattrath, Terokkar Forest", mapId = 479, serverMapId = 530, x = 0.33, y = 0.23, faction = "BOTH" },
    { id = 129, name = "Hellfire Peninsula, The Dark Portal, Alliance", mapId = 466, serverMapId = 530, x = 0.8750160, y = 0.5251833, faction = "ALLIANCE" },
    { id = 130, name = "Hellfire Peninsula, The Dark Portal, Horde", mapId = 466, serverMapId = 530, x = 0.8738098, y = 0.4818410, faction = "HORDE" },
    { id = 139, name = "The Stormspire, Netherstorm", mapId = 480, serverMapId = 530, x = 0.4526714, y = 0.3494179, faction = "BOTH" },
    { id = 140, name = "Altar of Sha'tar, Shadowmoon Valley", mapId = 474, serverMapId = 530, x = 0.6319236, y = 0.3048227, faction = "BOTH" },
    { id = 141, name = "Spinebreaker Ridge, Hellfire Peninsula", mapId = 466, serverMapId = 530, x = 0.6159187, y = 0.8125125, faction = "HORDE" },
    { id = 142, name = "Hellfire Peninsula - Reaver's Fall", mapId = 466, serverMapId = 530, x = 0.6610143, y = 0.4385946, faction = "HORDE" },
    { id = 149, name = "Shatter Point, Hellfire Peninsula", mapId = 466, serverMapId = 530, x = 0.7847048, y = 0.3499238, faction = "ALLIANCE" },
    { id = 150, name = "Cosmowrench, Netherstorm", mapId = 480, serverMapId = 530, x = 0.6520347, y = 0.6676143, faction = "BOTH" },
    { id = 151, name = "Swamprat Post, Zangarmarsh", mapId = 468, serverMapId = 530, x = 0.8474258, y = 0.5500301, faction = "HORDE" },
    { id = 156, name = "Toshley's Station, Blade's Edge Mountains", mapId = 476, serverMapId = 530, x = 0.61087, y = 0.70534, faction = "ALLIANCE" },
    { id = 159, name = "Sanctum of the Stars, Shadowmoon Valley", mapId = 474, serverMapId = 530, x = 0.5638891, y = 0.5796146, faction = "BOTH" },
    { id = 160, name = "Evergrove, Blade's Edge Mountains", mapId = 476, serverMapId = 530, x = 0.6165351, y = 0.3960340, faction = "BOTH" },
    { id = 163, name = "Mok'Nathal Village, Blade's Edge Mountains", mapId = 476, serverMapId = 530, x = 0.7632374, y = 0.6579382, faction = "HORDE" },
    { id = 164, name = "Orebor Harborage, Zangarmarsh", mapId = 468, serverMapId = 530, x = 0.41298, y = 0.289, faction = "ALLIANCE" },
    { id = 166, name = "Emerald Sanctuary, Felwood", mapId = 183, serverMapId = 1, x = 0.5144499, y = 0.8229374, faction = "BOTH" },
    { id = 167, name = "Forest Song, Ashenvale", mapId = 44, serverMapId = 1, x = 0.8501289, y = 0.4351654, faction = "ALLIANCE" },
    { id = 179, name = "Mudsprocket, Dustwallow Marsh", mapId = 142, serverMapId = 1, x = 0.42877, y = 0.72368, faction = "BOTH" },
    { id = 183, name = "Valgarde Port, Howling Fjord", mapId = 492, serverMapId = 571, x = 0.5976105, y = 0.6323738, faction = "ALLIANCE" },
    { id = 184, name = "Fort Wildervar, Howling Fjord", mapId = 492, serverMapId = 571, x = 0.60073, y = 0.16072, faction = "ALLIANCE" },
    { id = 185, name = "Westguard Keep, Howling Fjord", mapId = 492, serverMapId = 571, x = 0.3126092, y = 0.4400191, faction = "ALLIANCE" },
    { id = 190, name = "New Agamand, Howling Fjord", mapId = 492, serverMapId = 571, x = 0.5204218, y = 0.6736240, faction = "HORDE" },
    { id = 191, name = "Vengeance Landing, Howling Fjord", mapId = 492, serverMapId = 571, x = 0.7902919, y = 0.2971949, faction = "HORDE" },
    { id = 192, name = "Camp Winterhoof, Howling Fjord", mapId = 492, serverMapId = 571, x = 0.49535, y = 0.11505, faction = "HORDE" },
    { id = 195, name = "Rebel Camp, Stranglethorn Vale", mapId = 38, serverMapId = 0, x = 0.382, y = 0.04119, faction = "ALLIANCE" },
    { id = 205, name = "Zul'Aman, Ghostlands", mapId = 464, serverMapId = 530, x = 0.7467415, y = 0.6713076, faction = "BOTH" },
    { id = 213, name = "Shattered Sun Staging Area", mapId = 500, serverMapId = 530, x = 0.4827914, y = 0.2506141, faction = "BOTH" },
    { id = 226, name = "Transitus Shield, Coldarra", mapId = 487, serverMapId = 571, x = 0.3311936, y = 0.3440591, faction = "BOTH" },
    { id = 244, name = "Wintergarde Keep, Dragonblight", mapId = 489, serverMapId = 571, x = 0.7706288, y = 0.4980689, faction = "ALLIANCE" },
    { id = 245, name = "Valiance Keep, Borean Tundra", mapId = 487, serverMapId = 571, x = 0.5893129, y = 0.6838054, faction = "ALLIANCE" },
    { id = 246, name = "Fizzcrank Airstrip, Borean Tundra", mapId = 487, serverMapId = 571, x = 0.5651342, y = 0.2005039, faction = "ALLIANCE" },
    { id = 247, name = "Stars' Rest, Dragonblight", mapId = 489, serverMapId = 571, x = 0.2915399, y = 0.5537703, faction = "ALLIANCE" },
    { id = 248, name = "Apothecary Camp, Howling Fjord", mapId = 492, serverMapId = 571, x = 0.26013, y = 0.25018, faction = "HORDE" },
    { id = 249, name = "Camp Oneqwah, Grizzly Hills", mapId = 491, serverMapId = 571, x = 0.6494596, y = 0.4686649, faction = "HORDE" },
    { id = 250, name = "Conquest Hold, Grizzly Hills", mapId = 491, serverMapId = 571, x = 0.2199051, y = 0.6444866, faction = "HORDE" },
    { id = 251, name = "Fordragon Hold, Dragonblight", mapId = 489, serverMapId = 571, x = 0.39593, y = 0.25746, faction = "ALLIANCE" },
    { id = 252, name = "Wyrmrest Temple, Dragonblight", mapId = 489, serverMapId = 571, x = 0.6025860, y = 0.5139049, faction = "BOTH" },
    { id = 253, name = "Amberpine Lodge, Grizzly Hills", mapId = 491, serverMapId = 571, x = 0.3130825, y = 0.5915191, faction = "ALLIANCE" },
    { id = 254, name = "Venomspite, Dragonblight", mapId = 489, serverMapId = 571, x = 0.7655114, y = 0.6236096, faction = "HORDE" },
    { id = 255, name = "Westfall Brigade, Grizzly Hills", mapId = 491, serverMapId = 571, x = 0.59891, y = 0.2662, faction = "ALLIANCE" },
    { id = 256, name = "Agmar's Hammer, Dragonblight", mapId = 489, serverMapId = 571, x = 0.3747, y = 0.45704, faction = "HORDE" },
    { id = 257, name = "Warsong Hold, Borean Tundra", mapId = 487, serverMapId = 571, x = 0.4038424, y = 0.5145046, faction = "HORDE" },
    { id = 258, name = "Taunka'le Village, Borean Tundra", mapId = 487, serverMapId = 571, x = 0.7773872, y = 0.3768213, faction = "HORDE" },
    { id = 259, name = "Bor'gorok Outpost, Borean Tundra", mapId = 487, serverMapId = 571, x = 0.49591, y = 0.11008, faction = "HORDE" },
    { id = 260, name = "Kor'koron Vanguard, Dragonblight", mapId = 489, serverMapId = 571, x = 0.43884, y = 0.16802, faction = "HORDE" },
    { id = 289, name = "Amber Ledge, Borean Tundra", mapId = 487, serverMapId = 571, x = 0.4506021, y = 0.3408330, faction = "BOTH" },
    { id = 294, name = "Moa'ki, Dragonblight", mapId = 489, serverMapId = 571, x = 0.4846579, y = 0.7440803, faction = "BOTH" },
    { id = 295, name = "Kamagua, Howling Fjord", mapId = 492, serverMapId = 571, x = 0.2464165, y = 0.5783310, faction = "BOTH" },
    { id = 296, name = "Unu'pe, Borean Tundra", mapId = 487, serverMapId = 571, x = 0.7849211, y = 0.5147908, faction = "BOTH" },
    { id = 303, name = "Valiance Landing Camp, Wintergrasp", mapId = 502, serverMapId = 571, x = 0.7205099, y = 0.3105160, faction = "ALLIANCE" },
    { id = 304, name = "The Argent Stand, Zul'Drak", mapId = 497, serverMapId = 571, x = 0.4149687, y = 0.6449421, faction = "BOTH" },
    { id = 305, name = "Ebon Watch, Zul'Drak", mapId = 497, serverMapId = 571, x = 0.1406198, y = 0.7358748, faction = "BOTH" },
    { id = 306, name = "Light's Breach, Zul'Drak", mapId = 497, serverMapId = 571, x = 0.3216941, y = 0.7445226, faction = "BOTH" },
    { id = 307, name = "Zim'Torga, Zul'Drak", mapId = 497, serverMapId = 571, x = 0.5997377, y = 0.5681151, faction = "BOTH" },
    { id = 308, name = "River's Heart, Sholazar Basin", mapId = 494, serverMapId = 571, x = 0.5006754, y = 0.6133497, faction = "BOTH" },
    { id = 309, name = "Nesingwary Base Camp, Sholazar Basin", mapId = 494, serverMapId = 571, x = 0.2536119, y = 0.5824045, faction = "BOTH" },
    { id = 310, name = "Dalaran", mapId = 511, serverMapId = 571, x = 0.3652774, y = 0.3792568, faction = "BOTH" },
    { id = 315, name = "Acherus: The Ebon Hold", mapId = 24, serverMapId = 0, x = 0.8383, y = 0.50299, faction = "BOTH" },
    { id = 320, name = "K3, The Storm Peaks", mapId = 496, serverMapId = 571, x = 0.40697, y = 0.84594, faction = "BOTH" },
    { id = 321, name = "Frosthold, The Storm Peaks", mapId = 496, serverMapId = 571, x = 0.29531, y = 0.74465, faction = "ALLIANCE" },
    { id = 322, name = "Dun Nifflelem, The Storm Peaks", mapId = 496, serverMapId = 571, x = 0.62556, y = 0.60946, faction = "BOTH" },
    { id = 323, name = "Grom'arsh Crash-Site, The Storm Peaks", mapId = 496, serverMapId = 571, x = 0.36228, y = 0.49363, faction = "HORDE" },
    { id = 324, name = "Camp Tunka'lo, The Storm Peaks", mapId = 496, serverMapId = 571, x = 0.6540256, y = 0.5070091, faction = "HORDE" },
    { id = 325, name = "Death's Rise, Icecrown", mapId = 493, serverMapId = 571, x = 0.1944861, y = 0.4782692, faction = "BOTH" },
    { id = 326, name = "Ulduar, The Storm Peaks", mapId = 496, serverMapId = 571, x = 0.4451314, y = 0.2811625, faction = "BOTH" },
    { id = 327, name = "Bouldercrag's Refuge, The Storm Peaks", mapId = 496, serverMapId = 571, x = 0.3064109, y = 0.3633672, faction = "BOTH" },
    { id = 331, name = "Gundrak, Zul'Drak", mapId = 497, serverMapId = 571, x = 0.7045267, y = 0.2316195, faction = "BOTH" },
    { id = 332, name = "Warsong Camp, Wintergrasp", mapId = 502, serverMapId = 571, x = 0.2163418, y = 0.3487446, faction = "HORDE" },
    { id = 333, name = "The Shadow Vault, Icecrown", mapId = 493, serverMapId = 571, x = 0.43758, y = 0.24337, faction = "BOTH" },
    { id = 334, name = "The Argent Vanguard, Icecrown", mapId = 493, serverMapId = 571, x = 0.87773, y = 0.77994, faction = "BOTH" },
    { id = 340, name = "Argent Tournament Grounds, Icecrown", mapId = 493, serverMapId = 571, x = 0.72591, y = 0.22669, faction = "BOTH" },
    { id = 335, name = "Crusaders' Pinnacle, Icecrown", mapId = 493, serverMapId = 571, x = 0.7935, y = 0.72347, faction = "BOTH" },
    { id = 336, name = "Windrunner's Overlook, Crystalsong Forest", mapId = 511, serverMapId = 571, x = 0.7211788, y = 0.8081377, faction = "ALLIANCE" },
    { id = 337, name = "Sunreaver's Command, Crystalsong Forest", mapId = 511, serverMapId = 571, x = 0.7848128, y = 0.5023705, faction = "HORDE" },
    { id = 342, name = "Ulduar Raid - Iron Concourse", mapId = 530, serverMapId = 603, x = 0.5034078, y = 0.4785353, faction = "BOTH" },
    { id = 383, name = "Thondoril River, Western Plaguelands", mapId = 23, serverMapId = 0, x = 0.69206, y = 0.49679, faction = "BOTH" },
    { id = 384, name = "The Bulwark, Tirisfal", mapId = 21, serverMapId = 0, x = 0.83521, y = 0.70063, faction = "HORDE" },
    { id = 10006, name = "Ragefire Chasm", mapId = 322, serverMapId = 1, x = 0.5132, y = 0.4916, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10007, name = "The Deadmines", mapId = 40, serverMapId = 0, x = 0.4146, y = 0.7246, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10008, name = "Wailing Caverns", mapId = 12, serverMapId = 1, x = 0.4695, y = 0.3569, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10008, name = "Wailing Caverns", mapId = 5, serverMapId = 1, x = 0.0325, y = 0.7395, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10008, name = "Wailing Caverns", mapId = 10, serverMapId = 1, x = 0.8141, y = 0.1535, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10009, name = "Shadowfang Keep", mapId = 22, serverMapId = 0, x = 0.4612, y = 0.6822, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10010, name = "Blackfathom Deeps", mapId = 44, serverMapId = 1, x = 0.1531, y = 0.1540, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10010, name = "Blackfathom Deeps", mapId = 43, serverMapId = 1, x = 0.3244, y = 0.9738, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10010, name = "Blackfathom Deeps", mapId = 183, serverMapId = 1, x = 0.1434, y = 0.7962, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10011, name = "The Stockade", mapId = 302, serverMapId = 0, x = 0.5339, y = 0.7066, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10011, name = "The Stockade", mapId = 31, serverMapId = 0, x = 0.2132, y = 0.3779, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10012, name = "Gnomeregan", mapId = 28, serverMapId = 0, x = 0.2439, y = 0.4040, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10013, name = "Razorfen Downs", mapId = 12, serverMapId = 1, x = 0.4515, y = 0.8868, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10013, name = "Razorfen Downs", mapId = 142, serverMapId = 1, x = 0.1861, y = 0.6703, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10013, name = "Razorfen Downs", mapId = 62, serverMapId = 1, x = 0.3451, y = 0.1407, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10014, name = "Scarlet Monastery", mapId = 21, serverMapId = 0, x = 0.8197, y = 0.3921, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10014, name = "Scarlet Monastery", mapId = 23, serverMapId = 0, x = 0.2529, y = 0.2478, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10015, name = "Razorfen Kraul", mapId = 12, serverMapId = 1, x = 0.4375, y = 0.9004, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10015, name = "Razorfen Kraul", mapId = 142, serverMapId = 1, x = 0.1592, y = 0.6964, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10015, name = "Razorfen Kraul", mapId = 62, serverMapId = 1, x = 0.3130, y = 0.1719, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10016, name = "Uldaman", mapId = 18, serverMapId = 0, x = 0.4912, y = 0.1344, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10016, name = "Uldaman", mapId = 36, serverMapId = 0, x = 0.4740, y = 0.8833, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10017, name = "Maraudon", mapId = 102, serverMapId = 1, x = 0.3157, y = 0.6221, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10018, name = "Dire Maul", mapId = 122, serverMapId = 1, x = 0.5802, y = 0.4458, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10018, name = "Dire Maul", mapId = 12, serverMapId = 1, x = 0.1197, y = 0.8947, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10019, name = "Zul'Farrak", mapId = 162, serverMapId = 1, x = 0.3857, y = 0.2066, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10019, name = "Zul'Farrak", mapId = 202, serverMapId = 1, x = 0.9225, y = 0.3481, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10019, name = "Zul'Farrak", mapId = 62, serverMapId = 1, x = 0.5560, y = 0.9745, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10020, name = "Stratholme", mapId = 23, serverMapId = 0, x = 0.5290, y = 0.2877, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10021, name = "The Temple of Atal'Hakkar", mapId = 39, serverMapId = 0, x = 0.6928, y = 0.5452, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10022, name = "Blackrock Spire", mapId = 30, serverMapId = 0, x = 0.3265, y = 0.3018, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10022, name = "Blackrock Spire", mapId = 29, serverMapId = 0, x = 0.4034, y = 0.9900, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10023, name = "Scholomance", mapId = 23, serverMapId = 0, x = 0.6964, y = 0.7450, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10023, name = "Scholomance", mapId = 24, serverMapId = 0, x = 0.0719, y = 0.9202, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10023, name = "Scholomance", mapId = 27, serverMapId = 0, x = 0.2604, y = 0.0917, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10024, name = "Zul'Gurub", mapId = 38, serverMapId = 0, x = 0.4841, y = 0.1697, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10025, name = "Ahn'Qiraj", mapId = 262, serverMapId = 1, x = 0.2871, y = 0.9917, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10026, name = "Karazhan", mapId = 33, serverMapId = 0, x = 0.4665, y = 0.7588, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10026, name = "Karazhan", mapId = 20, serverMapId = 0, x = 0.2262, y = 0.2529, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10027, name = "Sunwell Plateau", mapId = 500, serverMapId = 530, x = 0.4511, y = 0.4376, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10028, name = "Black Temple", mapId = 474, serverMapId = 530, x = 0.6445, y = 0.4670, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10029, name = "Tempest Keep (Netherstorm)", mapId = 480, serverMapId = 530, x = 0.6613, y = 0.6523, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10030, name = "Zul'Aman", mapId = 464, serverMapId = 530, x = 0.7546, y = 0.6544, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10031, name = "Caverns of Time", mapId = 162, serverMapId = 1, x = 0.6498, y = 0.5033, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10032, name = "Serpentshrine Cavern", mapId = 468, serverMapId = 530, x = 0.5236, y = 0.3615, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10033, name = "Blade's Edge Mountains", mapId = 476, serverMapId = 530, x = 0.6758, y = 0.2367, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10033, name = "Blade's Edge Mountains", mapId = 480, serverMapId = 530, x = 0.0545, y = 0.5123, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10034, name = "Magisters' Terrace", mapId = 500, serverMapId = 530, x = 0.6004, y = 0.3059, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10035, name = "Auchindoun", mapId = 479, serverMapId = 530, x = 0.3971, y = 0.6459, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10036, name = "Utgarde Keep", mapId = 492, serverMapId = 571, x = 0.5867, y = 0.4676, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10037, name = "Utgarde Pinnacle", mapId = 492, serverMapId = 571, x = 0.5716, y = 0.4586, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10038, name = "Drak'Tharon Keep", mapId = 497, serverMapId = 571, x = 0.2894, y = 0.8680, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10038, name = "Drak'Tharon Keep", mapId = 491, serverMapId = 571, x = 0.1780, y = 0.2108, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10039, name = "The Nexus", mapId = 487, serverMapId = 571, x = 0.2827, y = 0.2902, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10040, name = "Ulduar", mapId = 496, serverMapId = 571, x = 0.4372, y = 0.2627, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10041, name = "Azjol-Nerub", mapId = 489, serverMapId = 571, x = 0.2626, y = 0.5048, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10042, name = "Gundrak", mapId = 497, serverMapId = 571, x = 0.7718, y = 0.2194, faction = "BOTH", kind = "MEETINGSTONE" },
    { id = 10043, name = "Naxxramas", mapId = 489, serverMapId = 571, x = 0.8725, y = 0.5105, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10043, name = "Naxxramas", mapId = 491, serverMapId = 571, x = 0.0296, y = 0.5287, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10044, name = "The Obsidian Sanctum", mapId = 489, serverMapId = 571, x = 0.5980, y = 0.5410, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10045, name = "Wintergrasp", mapId = 502, serverMapId = 571, x = 0.4934, y = 0.1238, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10046, name = "Onyxia's Lair", mapId = 142, serverMapId = 1, x = 0.5093, y = 0.7761, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10046, name = "Onyxia's Lair", mapId = 12, serverMapId = 1, x = 0.6189, y = 0.9417, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
    { id = 10046, name = "Onyxia's Lair", mapId = 62, serverMapId = 1, x = 0.7308, y = 0.2670, faction = "BOTH", kind = "MEETINGSTONE_RAID" },
{ id = 10047, name = "Icecrown Citadel", mapId = 493, serverMapId = 571, x = 0.5153603553772, y = 0.85606348514557, faction = "BOTH", kind = "MEETINGSTONE_RAID" }
}

local Checkpoints = {
    nodes = {},
    states = {},
    received = false,
}

local function IsFactionAllowed(faction)
    if not faction or faction == "BOTH" or faction == "ALL" then
        return true
    end

    local playerFaction = UnitFactionGroup and UnitFactionGroup("player") or nil
    if not playerFaction then
        return true
    end

    return string.upper(faction) == string.upper(playerFaction)
end

local function BuildCheckpointList()
    local checkpoints = {}

    for _, definition in ipairs(checkpointDefinitions) do
        local checkpoint = {}
        for key, value in pairs(definition) do
            checkpoint[key] = value
        end
        checkpoint.factionAllowed = IsFactionAllowed(checkpoint.faction)
        if Checkpoints.received then
            checkpoint.unlocked = Checkpoints.states[checkpoint.id] == true
        else
            checkpoint.unlocked = false
        end
        table.insert(checkpoints, checkpoint)
    end

    return checkpoints
end

local function ParseCheckpointData(body)
    local states = {}

    if not body or body == "" then
        return states
    end

    for token in string.gmatch(body, "([^;]+)") do
        local id = tonumber((token:gsub("%s+", "")))
        if id then
            states[id] = true
        end
    end

    return states
end

function CheckpointService.RequestCheckpoints()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_CHECKPOINTS_DATA, "")
end

function CheckpointService.UseCheckpoint(checkpointId)
    if not checkpointId or checkpointId <= 0 then
        return
    end

    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_USE_CHECKPOINT, tostring(checkpointId))
end

function CheckpointService.GetCheckpoints()
    return Checkpoints.nodes
end

local function FindCheckpointDefinition(id)
    for _, def in ipairs(checkpointDefinitions) do
        if def.id == id then
            return def
        end
    end
end

local function AnnounceNewlyUnlocked(newlyUnlockedIds)
    if #newlyUnlockedIds == 0 then return end
    if RaidNotice_AddMessage and RaidBossEmoteFrame then
        for _, id in ipairs(newlyUnlockedIds) do
            local def = FindCheckpointDefinition(id)
            local name = def and def.name or ("Checkpoint #" .. id)
            RaidNotice_AddMessage(RaidBossEmoteFrame, "New Checkpoint Unlocked: " .. name, ChatTypeInfo["RAID_WARNING"])
        end
    end
    if DEFAULT_CHAT_FRAME then
        for _, id in ipairs(newlyUnlockedIds) do
            local def = FindCheckpointDefinition(id)
            local name = def and def.name or ("Checkpoint #" .. id)
            DEFAULT_CHAT_FRAME:AddMessage("New checkpoint unlocked: |cffffd200" .. name .. "|r", 1, 1, 1)
        end
        DEFAULT_CHAT_FRAME:AddMessage("Open your world map to view and travel between unlocked checkpoints.", 1, 1, 1)
    end
end

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_CHECKPOINTS_DATA, function(body)
    local previousStates = Checkpoints.states or {}
    local hadPrevious = Checkpoints.received
    Checkpoints.states = ParseCheckpointData(body)
    Checkpoints.received = true

    if hadPrevious then
        local newlyUnlocked = {}
        for id in pairs(Checkpoints.states) do
            if not previousStates[id] then
                table.insert(newlyUnlocked, id)
            end
        end
        AnnounceNewlyUnlocked(newlyUnlocked)
    end

    Checkpoints.nodes = BuildCheckpointList()

    if ProjectEbonhold.CheckpointUI and ProjectEbonhold.CheckpointUI.RefreshPins then
        ProjectEbonhold.CheckpointUI.RefreshPins()
    end
end)

Checkpoints.nodes = BuildCheckpointList()

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        CheckpointService.RequestCheckpoints()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)
