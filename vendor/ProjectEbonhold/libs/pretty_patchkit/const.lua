-- Embedded in Project Ebonhold (libs/pretty_patchkit); the only copy that runs (see
-- localization.lua for the standalone addon).

local namespace = select(2,...);

local gearTypes = {
	["INVTYPE_RELIC"] = { ["slot"] = 0.3164, ["itemSlot"] = 18, ["enchant"] = false },
	["INVTYPE_TRINKET"] = { ["slot"] = 0.5625, ["itemSlot"] = 33, ["enchant"] = false },
	["INVTYPE_2HWEAPON"] = { ["slot"] = 2.000, ["itemSlot"] = 16, ["enchant"] = true },
	["INVTYPE_WEAPONMAINHAND"] = { ["slot"] = 1.0000, ["itemSlot"] = 16, ["enchant"] = true },
	["INVTYPE_WEAPONOFFHAND"] = { ["slot"] = 1.0000, ["itemSlot"] = 17, ["enchant"] = true },
	["INVTYPE_RANGED"] = { ["slot"] = 0.3164, ["itemSlot"] = 18, ["enchant"] = true },
	["INVTYPE_THROWN"] = { ["slot"] = 0.3164, ["itemSlot"] = 18, ["enchant"] = false },
	["INVTYPE_RANGEDRIGHT"] = { ["slot"] = 0.3164, ["itemSlot"] = 18, ["enchant"] = false },
	["INVTYPE_SHIELD"] = { ["slot"] = 1.0000, ["itemSlot"] = 17, ["enchant"] = true },
	["INVTYPE_WEAPON"] = { ["slot"] = 1.0000, ["itemSlot"] = 36, ["enchant"] = true },
	["INVTYPE_HOLDABLE"] = { ["slot"] = 1.0000, ["itemSlot"] = 17, ["enchant"] = false },
	["INVTYPE_HEAD"] = { ["slot"] = 1.0000, ["itemSlot"] = 1, ["enchant"] = true },
	["INVTYPE_NECK"] = { ["slot"] = 0.5625, ["itemSlot"] = 2, ["enchant"] = false },
	["INVTYPE_SHOULDER"] = { ["slot"] = 0.7500, ["itemSlot"] = 3, ["enchant"] = true },
	["INVTYPE_CHEST"] = { ["slot"] = 1.0000, ["itemSlot"] = 5, ["enchant"] = true },
	["INVTYPE_ROBE"] = { ["slot"] = 1.0000, ["itemSlot"] = 5, ["enchant"] = true },
	["INVTYPE_WAIST"] = { ["slot"] = 0.7500, ["itemSlot"] = 6, ["enchant"] = false },
	["INVTYPE_LEGS"] = { ["slot"] = 1.0000, ["itemSlot"] = 7, ["enchant"] = true },
	["INVTYPE_FEET"] = { ["slot"] = 0.75, ["itemSlot"] = 8, ["enchant"] = true },
	["INVTYPE_WRIST"] = { ["slot"] = 0.5625, ["itemSlot"] = 9, ["enchant"] = true },
	["INVTYPE_HAND"] = { ["slot"] = 0.7500, ["itemSlot"] = 10, ["enchant"] = true },
	["INVTYPE_FINGER"] = { ["slot"] = 0.5625, ["itemSlot"] = 31, ["enchant"] = false },
	["INVTYPE_CLOAK"] = { ["slot"] = 0.5625, ["itemSlot"] = 15, ["enchant"] = true },
	["INVTYPE_BODY"] = { ["slot"] = 0, ["itemSlot"] = 4, ["enchant"] = false },
};

local formula = {
	["A"] = {
		[4] = { ["A"] = 91.4500, ["B"] = 0.6500 },
		[3] = { ["A"] = 81.3750, ["B"] = 0.8125 },
		[2] = { ["A"] = 73.0000, ["B"] = 1.0000 }
	},
	["B"] = {
		[4] = { ["A"] = 26.0000, ["B"] = 1.2000 },
		[3] = { ["A"] = 0.7500, ["B"] = 1.8000 },
		[2] = { ["A"] = 8.0000, ["B"] = 2.0000 },
		[1] = { ["A"] = 0.0000, ["B"] = 2.2500 }
	}
};

local gearQuality = {
	[6000] = {
		["r"] = { ["A"] = 0.94, ["B"] = 5000, ["C"] = 0.00006, ["D"] = 1 },
		["g"] = { ["A"] = 0.47, ["B"] = 5000, ["C"] = 0.00047, ["D"] = -1 },
		["b"] = { ["A"] = 0, ["B"] = 0, ["C"] = 0, ["D"] = 0 },
		["Description"] = "Legendary"
	},
	[5000] = {
		["r"] = { ["A"] = 0.69, ["B"] = 4000, ["C"] = 0.00025, ["D"] = 1 },
		["g"] = { ["A"] = 0.28, ["B"] = 4000, ["C"] = 0.00019, ["D"] = 1 },
		["b"] = { ["A"] = 0.97, ["B"] = 4000, ["C"] = 0.00096, ["D"] = -1 },
		["Description"] = "Epic"
	},
	[4000] = {
		["r"] = { ["A"] = 0.0, ["B"] = 3000, ["C"] = 0.00069, ["D"] = 1 },
		["g"] = { ["A"] = 0.5, ["B"] = 3000, ["C"] = 0.00022, ["D"] = -1 },
		["b"] = { ["A"] = 1, ["B"] = 3000, ["C"] = 0.00003, ["D"] = -1 },
		["Description"] = "Superior"
	},
	[3000] = {
		["r"] = { ["A"] = 0.12, ["B"] = 2000, ["C"] = 0.00012, ["D"] = -1 },
		["g"] = { ["A"] = 1, ["B"] = 2000, ["C"] = 0.00050, ["D"] = -1 },
		["b"] = { ["A"] = 0, ["B"] = 2000, ["C"] = 0.001, ["D"] = 1 },
		["Description"] = "Uncommon"
	},
	[2000] = {
		["r"] = { ["A"] = 1, ["B"] = 1000, ["C"] = 0.00088, ["D"] = -1 },
		["g"] = { ["A"] = 1, ["B"] = 000, ["C"] = 0.00000, ["D"] = 0 },
		["b"] = { ["A"] = 1, ["B"] = 1000, ["C"] = 0.001, ["D"] = -1 },
		["Description"] = "Common"
	},
	[1000] = {
		["r"] = { ["A"] = 0.55, ["B"] = 0, ["C"] = 0.00045, ["D"] = 1 },
		["g"] = { ["A"] = 0.55, ["B"] = 0, ["C"] = 0.00045, ["D"] = 1 },
		["b"] = { ["A"] = 0.55, ["B"] = 0, ["C"] = 0.00045, ["D"] = 1 },
		["Description"] = "Trash"
	},
};

namespace.iLvlColors = {
	[1] = CreateColorRGB(0.65882, 0.65882, 0.65882),
	[2] = CreateColorRGB(0.08235, 0.70196, 0),
	[3] = CreateColorRGB(0, 0.56863, 0.94902),
	[4] = CreateColorRGB(0.78431, 0.27059, 0.98039),
	[5] = CreateColorRGB(1, 0.50196, 0),
	[6] = CreateColorRGB(1, 0, 0),
};
namespace.gearTypes = gearTypes;
namespace.formula = formula;
namespace.gearQuality = gearQuality;
namespace.variables_loaded = false;
namespace.activeEnchantIcons = {};