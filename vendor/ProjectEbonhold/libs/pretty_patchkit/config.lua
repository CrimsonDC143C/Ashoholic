-- Embedded in Project Ebonhold (libs/pretty_patchkit); the only copy that runs (see
-- localization.lua for the standalone addon).

local namespace = select(2,...);

local _G = _G;
local tonumber = tonumber;
local GameTooltip = GameTooltip;
local GetName = GetName;
local GetText = GetText;

local iLvlColors = namespace.iLvlColors;
local variables_loaded = namespace.variables_loaded;

function namespace.itemLevelMixInGetColor(itemLevel)
	local color

	if C_InRange(itemLevel, 0, 100) then
		color = iLvlColors[1];
	elseif C_InRange(itemLevel, 100, 150) then
		color = iLvlColors[1];
	elseif C_InRange(itemLevel, 150, 185) then
		color = iLvlColors[2];
	elseif C_InRange(itemLevel, 185, 200) then
		color = iLvlColors[3];
	elseif C_InRange(itemLevel, 200, 277) then
		color = iLvlColors[4];
	elseif C_InRange(itemLevel, 277, 296) then
		color = iLvlColors[5];
	elseif itemLevel >= 297 then
		color = iLvlColors[6];
	end

	return color;
end

-- A private, never-shown tooltip for every gear scan. Scanning on GameTooltip fired
-- every OnTooltipSetItem hook of every addon once per slot, and hid the tooltip the
-- player was reading.
local scanTip = CreateFrame("GameTooltip", "PatchkitScanTooltip", nil, "GameTooltipTemplate");
namespace.scanTip = scanTip;

-- Loads a link into the scanner; true when it holds it.
local function scanLink(link)
	if (not link) then return false; end
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE");
	scanTip:SetHyperlink(link);
	return true;
end
namespace.scanLink = scanLink;

-- Reads the heirloom item level of itemLink (it used to read whatever GameTooltip
-- held at the time, a unit tooltip when called from the GearScore hover).
local function findHeirloomilvl(itemLink)
	if (not scanLink(itemLink)) then return; end
	local line = "";
	for i = 2, scanTip:NumLines() do
		line = _G["PatchkitScanTooltipTextLeft"..i];
		if (line) then
			line = line:GetText();
			if (line) then
				if (line:match(HEIRLOOMILVL)) then
					return tonumber(line:match("%d+"));
				end
			end
		end
	end
end
namespace.findHeirloomilvl = findHeirloomilvl;

-- Settings UI now lives natively in the client patch under Project
-- Ebonhold > Display (InterfaceOptionsPanels.xml/.lua in Work\interface\
-- FrameXML), writing straight through to `_data` via
-- PatchkitGetSetting/PatchkitSetSetting. This file only owns loading
-- `_data`'s defaults and the non-visual CVar/hook wiring below.
local function config_loaded()
	if (variables_loaded) then return; end
	variables_loaded = true;
	-- itemlevel.lua reads the flag through the namespace: a copy taken at file load stays false.
	namespace.variables_loaded = true;

	-- SavedVariables;
	if (_data == nil) then _data = {}; end

	-- default settings;
	if (_data.enableConfig == nil) then _data.enableConfig = true; end
	if (_data.upgrades == nil) then _data.upgrades = false; end
	if (_data.enableChar == nil) then _data.enableChar = true; end
	if (_data.enchantChar == nil) then _data.enchantChar = false; end
	if (_data.enchantCharMiss == nil) then _data.enchantCharMiss = false; end
	if (_data.gemsChar == nil) then _data.gemsChar = false; end
	-- on by default; characters that saved the old default (off) get it turned on once;
	if (_data.ilvlChar == nil or not _data.ilvlCharDefaulted) then _data.ilvlChar = true; _data.ilvlCharDefaulted = true; end
	if (_data.enableInspect == nil) then _data.enableInspect = true; end
	if (_data.iLvlScore == nil) then _data.iLvlScore = false; end
	if (_data.GearScore == nil) then _data.GearScore = true; end
	if (_data.tooltipScore == nil) then _data.tooltipScore = true; end
	if (_data.itemLvlTip == nil) then _data.itemLvlTip = true; end
	if (_data.compare == nil) then _data.compare = true; end
	if (_data.resist == nil) then _data.resist = false; end
	if (_data.GearScoreFormat == nil) then _data.GearScoreFormat = false; end
	if (_data.itemLevelColors == nil) then _data.itemLevelColors = true; end
	if (_data.UnassignedSpellBorderCheckBox == nil) then _data.UnassignedSpellBorderCheckBox = 1; end

	RegisterCVar("ShowSpellUnassignedBorder", _data.UnassignedSpellBorderCheckBox);

	ShowUnassignedSpellBorderCheckBox:HookScript("OnClick", function(self)
		local value = self:GetChecked() and 1 or 0;
		_data.UnassignedSpellBorderCheckBox = value;
	end);
	ShowUnassignedSpellBorderCheckBox:HookScript("OnShow", function(self)
		self:SetChecked(_data.UnassignedSpellBorderCheckBox);
	end);

	cleanUpiLvl();
end
namespace.config_loaded = config_loaded;