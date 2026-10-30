-- File: cvar_options.lua
-- Integrates a curated subset of AwesomeCVar's options (Camera, Nameplates,
-- Font Rendering, Stance Option) directly into the ProjectEbonhold Interface
-- panel. No dependency on the AwesomeCVar addon.

ProjectEbonhold = ProjectEbonhold or {}

local CVarOptions = {}

-- ────────────────────────────────────────────────────────────────────────────
-- CVar definitions (label/desc are inlined, no locale dependency).
-- ────────────────────────────────────────────────────────────────────────────

local CAMERA_CVARS = {
    { name = "cameraFov",                 label = "Camera FoV",
      type = "slider", min = 60, max = 150, step = 1, default = 100 },
    { name = "cameraDistanceMax",         label = "Camera Distance",
      desc = "Sets the maximum distance the camera can zoom out from the player.",
      type = "slider", min = 0, max = 50, step = 1, default = 15 },
    { name = "cameraIndirectVisibility",  label = "Camera Indirect Visibility",
      desc = "When enabled, the camera can move freely through certain world objects rather than being blocked by them.",
      type = "toggle", default = 0 },
    { name = "cameraIndirectAlpha",       label = "Camera Indirect Alpha",
      desc = "Sets the transparency level of objects that come between the camera and the player character.",
      type = "slider", min = 0.6, max = 1, step = 0.05, default = 0.6 },
}

local NAMEPLATE_CVARS = {
    -- Master show/hide switches -- if these are off, the client never
    -- creates a plate object for that unit type at all, full stop. No
    -- amount of addon-side reskinning can show a nameplate the engine
    -- never built in the first place.
    { name = "nameplateShowFriends", label = "Show Friendly Nameplates",
      desc = "Master switch for friendly units (players and NPCs) getting a nameplate at all.",
      type = "toggle", default = 1 },
    { name = "nameplateShowEnemies", label = "Show Enemy Nameplates",
      desc = "Master switch for hostile units getting a nameplate at all.",
      type = "toggle", default = 1 },
    -- Mode controls (radio in source; rendered as dropdown here)
    { name = "nameplateStacking", label = "Nameplate Stacking Mode",
      desc = "'Smart' mode allows nameplates to bypass the stacking push if there is sufficient space below.",
      type = "mode", default = 0, modes = {
        { value =  0, label = "Overlapping" },
        { value =  1, label = "Stacking (All)" },
        { value =  2, label = "Stacking (Enemies)" },
        { value =  3, label = "Stacking (Friends)" },
        { value = -1, label = "Smart Stacking (All)" },
        { value = -2, label = "Smart Stacking (Enemies)" },
        { value = -3, label = "Smart Stacking (Friends)" },
    }},
    { name = "nameplateMouseMode", label = "Nameplate Mouseover Mode",
      desc = "'Raise' options elevate the mouseover nameplate's frame level above lower-level nameplates.",
      type = "mode", default = 0, modes = {
        { value = 0, label = "Default" },
        { value = 1, label = "Click-through Enemies" },
        { value = 2, label = "CT Enemy + Raise Friend" },
        { value = 3, label = "CT Enemy + Raise Friend (Combat)" },
        { value = 4, label = "Click-through Friends" },
        { value = 5, label = "CT Friend + Raise Enemy" },
        { value = 6, label = "CT Friend + Raise Enemy (Combat)" },
        { value = 7, label = "Always Raise Occluded" },
        { value = 8, label = "Raise Occluded (Combat Only)" },
    }},
    { name = "nameplateClampTop", label = "Nameplate Clamp Top Mode",
      type = "mode", default = 0, modes = {
        { value = 0, label = "Off" },
        { value = 1, label = "Clamp All" },
        { value = 2, label = "Clamp Bosses Only" },
    }},
    { name = "nameplateHitboxAnchor", label = "Nameplate Hitbox Anchor",
      desc = "Sets the vertical origin point of the nameplate's clickable area.",
      type = "mode", default = 1, modes = {
        { value = 0, label = "Top" },
        { value = 1, label = "Center" },
        { value = 2, label = "Bottom" },
    }},
    -- Sliders
    { name = "nameplatePlacement",         label = "Nameplate Placement Offset",
      desc = "A vertical offset ratio that displaces nameplates from their default anchor point.",
      type = "slider", min = -1, max = 2, step = 0.01, default = 0.66 },
    { name = "nameplateDistance",          label = "Nameplate Display Distance",
      type = "slider", min = 41, max = 100, step = 1, default = 41 },
    { name = "nameplateHysteresisDecay",   label = "Nameplate Pair Breakup Rate",
      desc = "Controls how quickly stacking pairs dissolve once nameplates are no longer overlapping.",
      type = "slider", min = 0.25, max = 30, step = 0.05, default = 1 },
    { name = "nameplateOcclusionAlpha",    label = "Nameplate Occlusion Alpha",
      desc = "Controls the opacity of nameplates when they are blocked by obstacles or terrain.",
      type = "slider", min = 0, max = 1, step = 0.01, default = 1 },
    { name = "nameplateNonTargetAlpha",    label = "Nameplate Non-Target Alpha",
      type = "slider", min = 0, max = 1, step = 0.01, default = 0.5 },
    { name = "nameplateAlphaSpeed",        label = "Nameplate Alpha Blending Speed",
      desc = "Controls how fast nameplates animate toward new opacity targets (1 = Instant).",
      type = "slider", min = 0.01, max = 1, step = 0.01, default = 1 },
    { name = "nameplateClampTopOffset",    label = "Nameplate Clamped Top Offset",
      type = "slider", min = 0, max = 0.15, step = 0.01, default = 0.1 },
    { name = "nameplateRaiseDistance",     label = "Stacking Max Vertical Push Distance",
      type = "slider", min = 1, max = 20, step = 0.25, default = 8 },
    { name = "nameplatePullDistance",      label = "Stacking Max Horizontal Pull Distance",
      type = "slider", min = 0, max = 0.75, step = 0.01, default = 0.25 },
    { name = "nameplateBandX",             label = "Nameplate X Space",
      type = "slider", min = 0.1, max = 1,   step = 0.01, default = 0.7 },
    { name = "nameplateBandY",             label = "Nameplate Y Space",
      type = "slider", min = 0.1, max = 1.5, step = 0.01, default = 1 },
    { name = "nameplateRaiseSpeed",        label = "Stacking Vertical Raise Speed",
      type = "slider", min = 1, max = 250, step = 1, default = 100 },
    { name = "nameplateLowerSpeed",        label = "Stacking Vertical Lower Speed",
      type = "slider", min = 1, max = 250, step = 1, default = 100 },
    { name = "nameplatePullSpeed",         label = "Stacking Horizontal Pull Speed",
      type = "slider", min = 1, max = 250, step = 1, default = 50 },
    { name = "nameplateInertia",           label = "Nameplate Stacking Inertia",
      desc = "Controls the physical weight of nameplate movement during stacking.",
      type = "slider", min = 0, max = 20, step = 0.1, default = 1 },
    { name = "nameplateHitboxHeightE",     label = "Enemy Nameplate Hitbox Height",
      type = "slider", min = 0, max = 1, step = 0.01, default = 1 },
    { name = "nameplateHitboxWidthE",      label = "Enemy Nameplate Hitbox Width",
      type = "slider", min = 0, max = 1, step = 0.01, default = 1 },
    { name = "nameplateHitboxHeightF",     label = "Friendly Nameplate Hitbox Height",
      type = "slider", min = 0, max = 1, step = 0.01, default = 1 },
    { name = "nameplateHitboxWidthF",      label = "Friendly Nameplate Hitbox Width",
      type = "slider", min = 0, max = 1, step = 0.01, default = 1 },
}

-- Simplified font-rendering toggle: 0 = off, 1 = on (we don't expose mode 2).
local FONT_RENDERING_CVAR = {
    name = "MSDFMode",
    label = "Enable advanced font rendering",
    desc = "Enables vector-based (MSDF) font rendering, dramatically improving glyph quality. Requires a UI reload to take effect.",
    type = "toggle",
    default = 1,
    reloadRequired = true,
}

local STANCE_CVAR = {
    name = "enableStancePatch",
    label = "Enable Stance/Form Swap Patch",
    desc = "Allows you to change stance/form and cast an ability in a single click when using macros.",
    type = "toggle",
    default = 1,
}

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────

local function getCVarNumber(name)
    local raw = GetCVar(name)
    return tonumber(raw) or raw
end

local function formatNumber(value)
    return tonumber(string.format("%.2f", value or 0)) or 0
end

CVarOptions._reloadPending = false
CVarOptions._reloadLabel = nil

local function setReloadPending(state)
    CVarOptions._reloadPending = state
    if CVarOptions._reloadLabel then
        if state then
            CVarOptions._reloadLabel:Show()
        else
            CVarOptions._reloadLabel:Hide()
        end
    end
end

local function applyCVar(def, value)
    if GetCVar(def.name) == nil then
        -- CVar does not exist on this client; silently ignore so we don't
        -- break other addon panels.
        return
    end
    SetCVar(def.name, value)
    if def.reloadRequired then
        setReloadPending(true)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Widget builders
-- ────────────────────────────────────────────────────────────────────────────

local widgetCounter = 0
local function uniqueName(prefix)
    widgetCounter = widgetCounter + 1
    return "ProjectEbonholdCVar_" .. prefix .. "_" .. widgetCounter
end

local function buildLabelAndDesc(parent, def, yOffset, contentWidth)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 16, yOffset)
    label:SetWidth(contentWidth - 40)
    label:SetJustifyH("LEFT")
    label:SetText(def.label .. ":")
    yOffset = yOffset - (label:GetStringHeight() + 4)

    if def.desc then
        local d = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        d:SetPoint("TOPLEFT", 16, yOffset)
        d:SetWidth(contentWidth - 40)
        d:SetJustifyH("LEFT")
        d:SetTextColor(0.8, 0.8, 0.8)
        d:SetText(def.desc)
        yOffset = yOffset - (d:GetStringHeight() + 4)
    end
    return yOffset
end

local function buildToggle(parent, def, yOffset, hookWheel, contentWidth)
    yOffset = yOffset - 4
    local cb = CreateFrame("CheckButton", uniqueName("Toggle"), parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, yOffset)
    _G[cb:GetName() .. "Text"]:SetText(def.label)
    cb.cvarDef = def
    cb:SetScript("OnClick", function(self)
        local newVal = (self:GetChecked() == 1) and 1 or 0
        applyCVar(self.cvarDef, newVal)
    end)
    if hookWheel then hookWheel(cb) end

    local refresh = function()
        local v = tonumber(GetCVar(def.name))
        cb:SetChecked(v == 1)
    end

    yOffset = yOffset - 24
    if def.desc then
        local d = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        d:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 25, -2)
        d:SetWidth(contentWidth - 80)
        d:SetJustifyH("LEFT")
        d:SetTextColor(0.8, 0.8, 0.8)
        d:SetText(def.desc)
        yOffset = yOffset - (d:GetStringHeight() + 6)
    end
    yOffset = yOffset - 6
    return yOffset, refresh
end

local function buildSlider(parent, def, yOffset, hookWheel, contentWidth)
    yOffset = buildLabelAndDesc(parent, def, yOffset, contentWidth)
    yOffset = yOffset - 8

    local slider = CreateFrame("Slider", uniqueName("Slider"), parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 22, yOffset)
    slider:SetWidth(260)
    slider:SetMinMaxValues(def.min, def.max)
    slider:SetValueStep(def.step or 1)
    _G[slider:GetName() .. "Low"]:SetText(tostring(def.min))
    _G[slider:GetName() .. "High"]:SetText(tostring(def.max))

    local valueText = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    valueText:SetPoint("LEFT", slider, "RIGHT", 12, 0)

    slider.cvarDef = def
    slider:SetScript("OnValueChanged", function(self, val)
        val = formatNumber(val)
        valueText:SetText(tostring(val))
        applyCVar(self.cvarDef, val)
    end)
    if hookWheel then hookWheel(slider) end

    local refresh = function()
        local v = tonumber(GetCVar(def.name)) or def.default or def.min
        if v < def.min then v = def.min end
        if v > def.max then v = def.max end
        slider:SetValue(v)
        valueText:SetText(tostring(formatNumber(v)))
    end

    yOffset = yOffset - 40
    return yOffset, refresh
end

local function buildModeDropdown(parent, def, yOffset, hookWheel, contentWidth)
    yOffset = buildLabelAndDesc(parent, def, yOffset, contentWidth)
    yOffset = yOffset - 4

    local dropdown = CreateFrame("Frame", uniqueName("Dropdown"), parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", 6, yOffset)
    UIDropDownMenu_SetWidth(dropdown, 240)

    local function labelFor(value)
        for _, m in ipairs(def.modes) do
            if m.value == value then return m.label end
        end
        return tostring(value)
    end

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local cur = tonumber(GetCVar(def.name))
        for _, m in ipairs(def.modes) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = m.label
            info.value = m.value
            info.checked = (cur == m.value)
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dropdown, m.value)
                UIDropDownMenu_SetText(dropdown, m.label)
                applyCVar(def, m.value)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local refresh = function()
        local v = tonumber(GetCVar(def.name))
        if v == nil then v = def.default end
        UIDropDownMenu_SetSelectedValue(dropdown, v)
        UIDropDownMenu_SetText(dropdown, labelFor(v))
    end

    yOffset = yOffset - 36
    return yOffset, refresh
end

local function buildControl(parent, def, yOffset, hookWheel, contentWidth)
    if def.type == "toggle" then
        return buildToggle(parent, def, yOffset, hookWheel, contentWidth)
    elseif def.type == "slider" then
        return buildSlider(parent, def, yOffset, hookWheel, contentWidth)
    elseif def.type == "mode" then
        return buildModeDropdown(parent, def, yOffset, hookWheel, contentWidth)
    end
    return yOffset, function() end
end

local function buildSection(parent, headerText, defs, yOffset, hookWheel, contentWidth, refreshList)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", 12, yOffset)
    header:SetText(headerText)
    yOffset = yOffset - 22

    -- Subtle separator
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 12, yOffset)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, yOffset)
    yOffset = yOffset - 10

    for _, def in ipairs(defs) do
        local refresh
        yOffset, refresh = buildControl(parent, def, yOffset, hookWheel, contentWidth)
        if refresh then table.insert(refreshList, refresh) end
    end
    yOffset = yOffset - 6
    return yOffset
end

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

-- Refresh functions accumulate here across BOTH Build() and
-- BuildNameplatesOnly() -- CVarOptions.Refresh() walks this one list
-- regardless of which panel a given control ended up in.
CVarOptions._refreshList = CVarOptions._refreshList or {}

-- Build JUST the native Nameplate CVars (stacking, distance, hitbox,
-- mouseover mode, show friends/enemies, ...) -- pulled out of Build() so the
-- Nameplates options panel can show this addon's reskin controls and the
-- client's own native nameplate CVars together in ONE place instead of the
-- CVars living buried under a separate "Advanced (CVars)" panel.
function CVarOptions.BuildNameplatesOnly(parent, yOffset, hookWheel, contentWidth)
    contentWidth = contentWidth or 580
    return buildSection(parent, "Native Client Settings", NAMEPLATE_CVARS, yOffset, hookWheel, contentWidth, CVarOptions._refreshList)
end

-- Build the CVar UI under `parent` starting at `yOffset` (negative number,
-- relative to the top of the scroll child). Returns the new yOffset.
-- `hookWheel` is an optional function applied to each interactive widget so
-- that mouse-wheel scrolling continues to forward to the parent scroll frame.
-- Nameplates CVars are NOT built here -- see BuildNameplatesOnly, used by the
-- dedicated Nameplates options panel instead.
function CVarOptions.Build(parent, yOffset, hookWheel, contentWidth)
    contentWidth = contentWidth or 580
    local refreshList = CVarOptions._refreshList

    -- Top-level header
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 12, yOffset)
    header:SetText("Advanced (CVars)")
    yOffset = yOffset - 22

    local subtitle = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 12, yOffset)
    subtitle:SetWidth(contentWidth - 24)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.85, 0.85, 0.85)
    subtitle:SetText("These settings change in-game console variables (CVars). They persist between sessions.")
    yOffset = yOffset - (subtitle:GetStringHeight() + 10)

    -- Reload-required notice (hidden until needed)
    local reloadNotice = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    reloadNotice:SetPoint("TOPLEFT", 12, yOffset)
    reloadNotice:SetWidth(contentWidth - 24)
    reloadNotice:SetJustifyH("LEFT")
    reloadNotice:SetTextColor(1.0, 0.82, 0.0)
    reloadNotice:SetText("Some changes require a UI reload (/reload) to take effect.")
    reloadNotice:Hide()
    CVarOptions._reloadLabel = reloadNotice
    yOffset = yOffset - 18

    yOffset = buildSection(parent, "Camera",         CAMERA_CVARS,    yOffset, hookWheel, contentWidth, refreshList)
    yOffset = buildSection(parent, "Font Rendering", { FONT_RENDERING_CVAR }, yOffset, hookWheel, contentWidth, refreshList)
    yOffset = buildSection(parent, "Stance Option",  { STANCE_CVAR },  yOffset, hookWheel, contentWidth, refreshList)

    CVarOptions._refreshList = refreshList
    return yOffset
end

-- Refresh every CVar widget to mirror the current live CVar value.
function CVarOptions.Refresh()
    if not CVarOptions._refreshList then return end
    for _, fn in ipairs(CVarOptions._refreshList) do
        local ok, err = pcall(fn)
        if not ok and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[ProjectEbonhold]|r CVar refresh error: " .. tostring(err))
        end
    end
end

-- Apply the one-time defaults the user asked for: Font Rendering enabled (1),
-- Stance Patch enabled (1). Stored via ProjectEbonholdOptionsService so we
-- only do this on first install.
function CVarOptions.ApplyInitialDefaults()
    local svc = _G.ProjectEbonholdOptionsService
    if not svc then return end
    if svc:GetSetting("cvarInitialDefaultsApplied") then return end

    if GetCVar("MSDFMode") ~= nil then
        SetCVar("MSDFMode", 1)
    end
    if GetCVar("enableStancePatch") ~= nil then
        SetCVar("enableStancePatch", 1)
    end
    -- Disable the base game's tutorial popups by default.
    SetCVar("showTutorials", 0)

    svc:SetSetting("cvarInitialDefaultsApplied", true)
end

ProjectEbonhold.CVarOptions = CVarOptions
