-- Project Ebonhold: "WoW Forever" skin for the embedded Details! (owner, 2026-11-12).
-- The same metal frame as DragonUI's WoW Forever windows (DragonUI\utils\forever_atlas_chrome.lua, layout
-- "metalframe": thin gold rails and the dark title band), gold Friz Quadrata title, flat class-coloured bars.
-- It is the default skin of new windows, and every existing window is moved onto it ONCE per profile and window
-- (flag in _detalhes_global.ebonhold_forever_skin): a player who picks another skin afterwards keeps it.
-- Cost: work only when a skin is applied (ChangeSkin / InstanceColor), never in the per-second row refresh.
-- Loaded after startup.lua (details_embed.xml): it hooks functions of janela_principal, profiles and classe_instancia.

local _detalhes = _G._detalhes
if not _detalhes or not _detalhes.InstallSkin then
	return
end

local SKIN = "WoW Forever"
-- the plain form, which tools/translation/m6_addon_keys.py recognises (ProjectEbonhold loads first)
local L = ProjectEbonhold.L

-- Chrome frame around the window, from the baseframe's corners. The metal corners carry their own margins: these
-- put the side and bottom rails just outside the bars and the title band behind the toolbar row.
local CHROME_LEFT, CHROME_TOP, CHROME_RIGHT, CHROME_BOTTOM = -10, 22, 6, -5

local GOLD = { 1, 0.82, 0, 1 }
local PANEL = { 0.1216, 0.1176, 0.1294 }

-- Stock header and side textures, drawn from the skin file: blanked under this skin, the metal frame replaces them.
local STOCK_HEADER = { "ball", "ball_r", "emenda", "top_bg" }
local STOCK_BASE = { "barra_esquerda", "barra_direita", "barra_fundo" }
local STOCK_FOOTER = { "top_bg", "esquerdo", "direita", "esquerdo_nostatusbar", "direita_nostatusbar" }

------------------------------------------------------------------------------------------------------------------------
-- The skin: Minimalistic's layout (the default until now), recoloured and refonted.

local base = _detalhes.skins["Minimalistic"]
local cprops = table_deepcopy(base.instance_cprops)

cprops.bg_r, cprops.bg_g, cprops.bg_b = PANEL[1], PANEL[2], PANEL[3]
cprops.bg_alpha = 0.85
cprops.color = { 1, 1, 1, 1 }
cprops.color_buttons = { 1, 0.92, 0.70, 1 }
cprops.show_sidebars = false
cprops.show_statusbar = false
cprops.hide_icon = true

local title = cprops.attribute_text
title.text_face = "Friz Quadrata TT"
title.text_size = 11
title.text_color = { GOLD[1], GOLD[2], GOLD[3], GOLD[4] }
title.shadow = true

local row = cprops.row_info
row.font_face = "Friz Quadrata TT"
row.font_face_file = "Fonts\\FRIZQT__.TTF"
row.font_size = 11
row.height = 18
row.textL_outline = false
row.textR_outline = false
row.textL_outline_small = true
row.textR_outline_small = true
row.texture = "Skyline"
row.texture_file = "Interface\\AddOns\\ProjectEbonhold\\libs\\Details\\images\\bar_skyline"
row.texture_background = "Details Flat"
row.texture_background_file = "Interface\\AddOns\\ProjectEbonhold\\libs\\Details\\images\\bar_background"
row.fixed_texture_background_color = { 0, 0, 0, 0.35 }
row.space = { left = 1, right = -1, between = 1 }

_detalhes:InstallSkin(SKIN, {
	-- The stock texture file still drives the resize grips, the lock and the stretch button.
	file = base.file,
	author = "Project Ebonhold",
	version = "1.0",
	site = "",
	desc = L["Metal frame of the WoW Forever interface, gold title and flat bars."],

	micro_frames = { color = { 1, 1, 1, 1 }, font = "Friz Quadrata TT", size = 10, textymod = 1 },

	can_change_alpha_head = true,
	icon_anchor_main = base.icon_anchor_main,
	icon_anchor_plugins = base.icon_anchor_plugins,
	icon_plugins_size = base.icon_plugins_size,
	icon_point_anchor = base.icon_point_anchor,
	left_corner_anchor = base.left_corner_anchor,
	right_corner_anchor = base.right_corner_anchor,
	icon_point_anchor_bottom = base.icon_point_anchor_bottom,
	left_corner_anchor_bottom = base.left_corner_anchor_bottom,
	right_corner_anchor_bottom = base.right_corner_anchor_bottom,
	icon_on_top = true,
	icon_ignore_alpha = true,
	icon_titletext_position = base.icon_titletext_position,

	instance_cprops = cprops,
	skin_options = base.skin_options,
})

-- New windows and empty profiles open on it.
_detalhes.default_skin_to_use = SKIN
if _detalhes.instance_defaults then
	_detalhes.instance_defaults.skin = SKIN
end

------------------------------------------------------------------------------------------------------------------------
-- The metal frame: built once per window, shown under this skin, hidden under any other.

local function BlankStock(instance)
	local frame = instance.baseframe
	local header, footer = frame.cabecalho, frame.rodape
	for i = 1, #STOCK_HEADER do
		local t = header and header[STOCK_HEADER[i]]
		if t then t:SetTexture(nil) end
	end
	for i = 1, #STOCK_BASE do
		local t = frame[STOCK_BASE[i]]
		if t then t:SetTexture(nil) end
	end
	for i = 1, #STOCK_FOOTER do
		local t = footer and footer[STOCK_FOOTER[i]]
		if t then t:SetTexture(nil) end
	end
end

local function BuildChrome(frame)
	local ForeverUI = DragonUI and DragonUI.ForeverUI
	if not (ForeverUI and ForeverUI.ApplyNineSlice and ForeverUI.ChromeLayouts and ForeverUI.ChromeLayouts.metalframe) then
		return nil
	end
	local chrome = CreateFrame("Frame", nil, frame)
	chrome:SetPoint("TOPLEFT", frame, "TOPLEFT", CHROME_LEFT, CHROME_TOP)
	chrome:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", CHROME_RIGHT, CHROME_BOTTOM)
	-- Under the window background (level 3), the toolbar and the rows: only the rails and the band show.
	chrome:SetFrameLevel(frame:GetFrameLevel())
	chrome:EnableMouse(false)
	ForeverUI.ApplyNineSlice(chrome, "metalframe", "BORDER")
	return chrome
end

local function Style(instance)
	local frame = instance.baseframe
	if not frame then
		return
	end
	if instance.skin == SKIN then
		if frame.ebonholdForever == nil then
			frame.ebonholdForever = BuildChrome(frame) or false
		end
		if frame.ebonholdForever then
			frame.ebonholdForever:Show()
		end
		BlankStock(instance)
	elseif frame.ebonholdForever then
		-- Another skin: ChangeSkin has already put its own textures back on the stock regions.
		frame.ebonholdForever:Hide()
	end
end

hooksecurefunc(_detalhes, "ChangeSkin", Style)
-- InstanceColor re-tints the stock regions (options panel): keep them blank under this skin.
hooksecurefunc(_detalhes, "InstanceColor", function(instance)
	if instance.skin == SKIN and instance.baseframe then
		BlankStock(instance)
	end
end)

------------------------------------------------------------------------------------------------------------------------
-- One-time move of existing windows onto the skin.

local function Migrated()
	if type(_detalhes_global) ~= "table" or not _detalhes.GetCurrentProfileName then
		return nil
	end
	local profile = _detalhes:GetCurrentProfileName()
	if not profile then
		return nil
	end
	local all = _detalhes_global.ebonhold_forever_skin
	if type(all) ~= "table" then
		all = {}
		_detalhes_global.ebonhold_forever_skin = all
	end
	local done = all[profile]
	if type(done) ~= "table" then
		done = {}
		all[profile] = done
	end
	return done
end

local function Migrate(instance)
	-- A window without frames yet is moved when it is first opened (AtivarInstancia below).
	if not (instance and instance.baseframe and instance.meu_id) then
		return
	end
	local done = Migrated()
	if not done or done[instance.meu_id] then
		return
	end
	done[instance.meu_id] = true
	if instance.skin ~= SKIN then
		instance:ChangeSkin(SKIN)
	end
end

-- ApplyProfile opens windows half-loaded (AtivarInstancia, then their saved config): move them once it is done.
local applyingProfile = false
local applyProfile = _detalhes.ApplyProfile
_detalhes.ApplyProfile = function(...)
	applyingProfile = true
	local ok, result = pcall(applyProfile, ...)
	applyingProfile = false
	if not ok then
		error(result, 0)
	end
	for _, instance in _detalhes:ListInstances() do
		Migrate(instance)
	end
	return result
end

hooksecurefunc(_detalhes, "AtivarInstancia", function(instance)
	if not applyingProfile then
		Migrate(instance)
	end
end)
