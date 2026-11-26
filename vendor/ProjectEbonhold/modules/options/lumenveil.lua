local L, T = ProjectEbonhold.L, ProjectEbonhold.T
-- File: lumenveil.lua
-- "Lumenveil" in the Video options: the look and the effects of the Lumenveil graphics mod
-- (volumetric fog, light shafts, lamp and spell light, water, relief), and its on/off.
--
-- Lumenveil is a separate program next to Wow.exe (version.dll + CoAVolFog.dll). It reads
-- CoAVolFog.ini and re-reads it within a second of any change, so every control here writes
-- that file through ebonhold.dll (EbonholdLumenveilGet / Set / Status, lumenveil_client.h in
-- the client DLL source) and the picture follows. The values live in the ini, not in the
-- saved variables: the ini is what Lumenveil acts on, and its own window (Ctrl+F7) writes the
-- same file. Changes apply at once, Okay / Cancel do not touch them, like echo_visuals.lua.
--
-- Pages: the main one holds the everyday controls; one sub-page per group lists EVERY setting
-- of the file (owner, 2026-11-13), from lumenveil_settings.lua, generated from Lumenveil's own
-- source by tools/lumenveil/gen_options.py in the server repo.
--
-- Enable: off is instant (the mod's own Ctrl+F12 switch); on needs a restart when the game
-- started with it off. Without Lumenveil or with an older ebonhold.dll nothing is shown.

if not (EbonholdLumenveilStatus and EbonholdLumenveilGet and EbonholdLumenveilSet) then return end
if not (VideoOptionsFrame and VideoOptionsFramePanelContainer and OptionsFrame_AddCategory) then return end

local SETTINGS = ProjectEbonhold.LumenveilSettings or {}
local PAGES = ProjectEbonhold.LumenveilPages or {}

local DEFAULTS = {}
for _, s in ipairs(SETTINGS) do DEFAULTS[s.key] = s.default end

-- Moon shafts follow the main page's sun shafts slider, in the shipped proportion.
local MOON_PER_SUN = (tonumber(DEFAULTS.MoonShafts) or 2.64) / (tonumber(DEFAULTS.Shafts) or 0.63)

local function Raw(key)
    return EbonholdLumenveilGet(key) or DEFAULTS[key] or ""
end

local function Number(key)
    return tonumber(Raw(key)) or 0
end

local function Format(v)
    local s = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
    return s
end

-- ── Writes: gathered for a quarter of a second, then one file replace ────
--
-- The player is guided before anything can fail: text boxes only take the characters the DLL
-- accepts (letters, digits, space and . - : , * + _), number boxes only take a number. What is left
-- is the file write itself failing: then the page says so in its own notice line, and every
-- control is re-read from the file so it shows what is really saved. Nothing goes to the chat.

local pending, pendingOrder, pendingDone = {}, {}, {}
local flusher = CreateFrame("Frame")
flusher:Hide()
flusher.wait = 0

local OnSaved   -- set once the pages exist: OnSaved(ok) shows or clears the notice, re-reads on failure

local function Flush()
    local args, keys, failed = {}, {}, false
    local function Send()
        local ok = EbonholdLumenveilSet(unpack(args)) == 1
        if not ok then failed = true end
        for _, key in ipairs(keys) do
            if pendingDone[key] then pendingDone[key](ok) end
        end
        args, keys = {}, {}
    end
    for _, key in ipairs(pendingOrder) do
        args[#args + 1] = key
        args[#args + 1] = pending[key]
        keys[#keys + 1] = key
        if #args == 16 then Send() end
    end
    if #args > 0 then Send() end
    local sent = #pendingOrder > 0
    pending, pendingOrder, pendingDone = {}, {}, {}
    if sent and OnSaved then OnSaved(not failed) end
end

flusher:SetScript("OnUpdate", function(self, elapsed)
    self.wait = self.wait - elapsed
    if self.wait <= 0 then
        self:Hide()
        Flush()
    end
end)

-- done(ok), optional, is called once the value has reached the file (or failed to).
local function Write(key, value, done)
    if pending[key] == nil then pendingOrder[#pendingOrder + 1] = key end
    pending[key] = type(value) == "number" and Format(value) or value
    pendingDone[key] = done
    flusher.wait = 0.25
    flusher:Show()
end

-- Keeps only the characters matched by `allowed` while the player types, cursor kept in place.
local function KeepOnly(box, allowed)
    box:SetScript("OnTextChanged", function(self)
        if self.cleaning then return end
        local text = self:GetText()
        local clean = text:gsub(allowed, "")
        if clean ~= text then
            local cursor = self:GetCursorPosition() - (#text - #clean)
            self.cleaning = true
            self:SetText(clean)
            self.cleaning = nil
            self:SetCursorPosition(math.max(0, cursor))
        end
    end)
end

-- A short line next to a control: "Saved" in green that fades, or a reason in red that stays
-- until the next edit.
local function FeedbackLine(parent)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    local timer = CreateFrame("Frame", nil, parent)
    timer:Hide()
    timer:SetScript("OnUpdate", function(self, elapsed)
        self.left = self.left - elapsed
        if self.left <= 0 then self:Hide(); fs:SetText("") end
    end)
    function fs:Saved()
        self:SetTextColor(0.25, 1, 0.25)
        self:SetText(L["Saved"])
        timer.left = 2
        timer:Show()
    end
    function fs:Problem(text)
        timer:Hide()
        self:SetTextColor(1, 0.3, 0.3)
        self:SetText(text)
    end
    function fs:Clear() timer:Hide(); self:SetText("") end
    return fs
end

-- ── Fog amount: a factor over the whole ZoneDensity list ─────────────────
--
-- Most tuned zones set their own Density (CoAVolFog-regions.ini), so the global Density does
-- nothing there. ZoneDensity multiplies whatever the zone uses: the slider scales every entry of
-- the list the ini had (kept as the base) and adds "*:f" for the zones it does not name. If the
-- list was changed elsewhere (the Fog page, Lumenveil's own window, a new ini), that list
-- becomes the base.

local function FogState()
    local db = ProjectEbonholdDB
    if not db then return nil end
    local current = Raw("ZoneDensity")
    if db.lumenveilFogBase == nil or current ~= db.lumenveilFogWritten then
        local base = {}
        for zone, factor in string.gmatch(current, "(%d+)%s*:%s*([%d%.]+)") do
            base[#base + 1] = zone .. ":" .. factor
        end
        db.lumenveilFogBase = table.concat(base, ",")
        db.lumenveilFogWritten = current
        db.lumenveilFog = 1
    end
    return db
end

local function GetFog()
    local db = FogState()
    return db and db.lumenveilFog or 1
end

local function SetFog(f)
    local db = FogState()
    if not db then return end
    local parts = { "*:" .. Format(f) }
    for zone, factor in string.gmatch(db.lumenveilFogBase or "", "(%d+):([%d%.]+)") do
        parts[#parts + 1] = zone .. ":" .. Format(tonumber(factor) * f)
    end
    local list = table.concat(parts, ",")
    db.lumenveilFog = f
    db.lumenveilFogWritten = list
    Write("ZoneDensity", list)
end

-- ── Controls ─────────────────────────────────────────────────────────────

local function Tooltip(frame, label, text)
    if not text or text == "" then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
end

local frameCount = 0
local function NextName(prefix)
    frameCount = frameCount + 1
    return "VideoOptionsLumenveil" .. prefix .. frameCount
end

local function CheckBox(parent, list, label, tooltip, get, set)
    local cb = CreateFrame("CheckButton", NextName("Check"), parent, "InterfaceOptionsCheckButtonTemplate")
    _G[cb:GetName() .. "Text"]:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    Tooltip(cb, label, tooltip)
    cb.Refresh = function() cb:SetChecked(get()) end
    list[#list + 1] = cb
    return cb
end

local function Step(minV, maxV, int)
    if int then return 1 end
    local raw = (maxV - minV) / 200
    local p = 10 ^ math.floor(math.log10(raw))
    for _, m in ipairs({ 1, 2, 5, 10 }) do
        if raw <= m * p then return m * p end
    end
    return 10 * p
end

-- A slider with an exact-value box on its right. The box takes any value in range, finer than
-- the slider's step.
local function Slider(parent, list, label, tooltip, minV, maxV, int, get, set, width)
    local step = Step(minV, maxV, int)
    local s = CreateFrame("Slider", NextName("Slider"), parent, "OptionsSliderTemplate")
    s:SetWidth(width or 200)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    _G[s:GetName() .. "Low"]:SetText(Format(minV))
    _G[s:GetName() .. "High"]:SetText(Format(maxV))
    _G[s:GetName() .. "Text"]:SetText(label)

    local box = CreateFrame("EditBox", NextName("Box"), parent, "InputBoxTemplate")
    box:SetSize(56, 20)
    box:SetAutoFocus(false)
    box:SetPoint("LEFT", s, "RIGHT", 14, 0)
    box:SetFontObject(GameFontHighlightSmall)
    KeepOnly(box, minV < 0 and "[^%d%.%-]" or "[^%d%.]")

    local function Show(v) box:SetText(Format(v)); box:SetCursorPosition(0) end
    local function Clamp(v)
        v = math.max(minV, math.min(maxV, v))
        if int then v = math.floor(v + 0.5) end
        return v
    end

    s:SetScript("OnValueChanged", function(self, v)
        if self.refreshing then return end
        v = Clamp(math.floor(v / step + 0.5) * step)
        Show(v)
        set(v)
    end)
    box:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then
            v = Clamp(v)
            s.refreshing = true
            s:SetValue(v)
            s.refreshing = nil
            set(v)
        end
        Show(Clamp(v or get()))
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self) Show(get()); self:ClearFocus() end)
    Tooltip(s, label, tooltip)
    Tooltip(box, label, tooltip)

    s.Refresh = function()
        local v = Clamp(get())
        s.refreshing = true
        s:SetValue(v)
        s.refreshing = nil
        Show(v)
    end
    s.box = box
    list[#list + 1] = s
    return s
end

-- A free text value: hotkeys ("Ctrl+F7"), zone lists ("14,17,1637"), "zone:factor" lists.
local function TextBox(parent, list, label, tooltip, get, set, width)
    local box = CreateFrame("EditBox", NextName("Text"), parent, "InputBoxTemplate")
    box:SetSize(width or 300, 20)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlightSmall)
    local caption = box:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    caption:SetPoint("BOTTOMLEFT", box, "TOPLEFT", -4, 3)
    caption:SetText(label)
    local feedback = FeedbackLine(box)
    feedback:SetPoint("LEFT", caption, "RIGHT", 10, 0)
    -- Only what Lumenveil's file can hold can be typed, so a value is never refused for its text.
    KeepOnly(box, "[^%w%.%-:,%* %+_]")
    box:HookScript("OnEditFocusGained", function() feedback:Clear() end)
    box:SetScript("OnEnterPressed", function(self)
        set(self:GetText(), function(ok)
            if ok then
                feedback:Saved()
            else
                feedback:Problem(L["Not saved, the previous value is back."])
                box:SetText(get()); box:SetCursorPosition(0)
            end
        end)
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(get()); self:ClearFocus() end)
    Tooltip(box, label, tooltip)
    box.Refresh = function() box:SetText(get()); box:SetCursorPosition(0) end
    list[#list + 1] = box
    return box
end

local function DropDown(parent, list, label, tooltip, choices, get, set)
    local dd = CreateFrame("Frame", NextName("DropDown"), parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, 140)
    local caption = dd:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    caption:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 18, 2)
    caption:SetText(label)
    local function TextOf(v)
        for _, c in ipairs(choices) do if c.value == v then return c.text end end
        return tostring(v)
    end
    UIDropDownMenu_Initialize(dd, function(self, level)
        local current = get()
        for _, c in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = c.text
            info.value = c.value
            info.checked = (c.value == current)
            info.func = function()
                set(c.value)
                UIDropDownMenu_SetText(dd, c.text)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local button = _G[dd:GetName() .. "Button"]
    if button then Tooltip(button, label, tooltip) end
    dd.Refresh = function() UIDropDownMenu_SetText(dd, TextOf(get())) end
    list[#list + 1] = dd
    return dd
end

-- Edit boxes may lack Enable/Disable on this client: they are greyed and made deaf instead.
local function SetWidgetEnabled(w, on)
    if w.Enable and w.Disable then
        if on then w:Enable() else w:Disable() end
    end
    if w:GetObjectType() == "EditBox" then
        w:EnableMouse(on)
        w:SetAlpha(on and 1 or 0.5)
        if not on then w:ClearFocus() end
    end
end

local function SetEnabled(c, on)
    if c:GetObjectType() == "Frame" then
        if on then UIDropDownMenu_EnableDropDown(c) else UIDropDownMenu_DisableDropDown(c) end
        return
    end
    SetWidgetEnabled(c, on)
    if c.box then SetWidgetEnabled(c.box, on) end
end

-- ── Main page ────────────────────────────────────────────────────────────

local main = CreateFrame("Frame", "VideoOptionsLumenveilPanel", VideoOptionsFramePanelContainer)
main.name = L["Lumenveil"]
main:Hide()
local mainControls = {}

local title = main:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(L["Lumenveil"])

-- A fixed height lets the text wrap: without one the client keeps it on one line and cuts it.
local subText = main:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subText:SetPoint("RIGHT", main, "RIGHT", -16, 0)
subText:SetHeight(36)
subText:SetJustifyH("LEFT")
subText:SetJustifyV("TOP")
subText:SetNonSpaceWrap(true)
subText:SetText(L["Volumetric fog, light shafts, lamp and spell light, and water. Changes apply at once; every setting is in the pages under Lumenveil. Ctrl+F12 compares with the plain game."])

local status = main:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")

-- One notice per page, next to its title, for a change the file did not take.
local notices = {}
local function Notice(page, anchor)
    local fs = page:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    fs:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
    fs:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    fs:SetJustifyH("LEFT")
    notices[#notices + 1] = fs
    return fs
end
Notice(main, title)

local enable = CheckBox(main, mainControls, L["Enable Lumenveil"],
    L["Turning it off applies at once. Turning it on needs a restart of the game if it started with Lumenveil off. While Lumenveil runs, the game's anti-aliasing is off: use your graphics driver's instead. Turned off, the game's own anti-aliasing comes back after a restart."],
    function() return Number("Enable") == 1 end,
    function(on) Write("Enable", on and 1 or 0); main.RefreshStatus(on) end)
enable:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", -2, -4)
status:SetPoint("LEFT", _G[enable:GetName() .. "Text"], "RIGHT", 12, 0)

-- The Video panel is only ~410 wide and ~390 high: one column in a scroll frame, like the
-- sub-pages, so nothing spills out of the window whatever the UI scale.
local mainScroll = CreateFrame("ScrollFrame", "VideoOptionsLumenveilPanelScroll", main, "UIPanelScrollFrameTemplate")
mainScroll:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", -6, -6)
mainScroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -30, 8)
local mainChild = CreateFrame("Frame", nil, mainScroll)
mainChild:SetWidth(340)
mainScroll:SetScrollChild(mainChild)

local function Direct(key)
    return function() return Number(key) end, function(v) Write(key, v) end
end

local y = -8
local quality = DropDown(mainChild, mainControls, L["Fog quality"],
    L["Resolution and steps of the fog. Lower it if the frame rate drops."],
    { { value = 1, text = L["Low"] }, { value = 2, text = L["Medium"] }, { value = 3, text = L["High"] } },
    function() return Number("Quality") end, function(v) Write("Quality", v) end)
quality:SetPoint("TOPLEFT", mainChild, "TOPLEFT", 0, y - 14)
y = y - 50

local mainSliders = {
    { L["Fog"], L["How much fog everywhere, on top of each zone's own look. 0 = no fog."], 0, 2, GetFog, SetFog },
    { L["Sun and moon shafts"], L["Beams of sun and moon light through trees, buildings and mountains."], 0, 2,
        function() return Number("Shafts") end,
        function(v) Write("Shafts", v); Write("MoonShafts", math.min(8, v * MOON_PER_SUN)) end },
    { L["Night darkness"], L["How much darker nights are outdoors. Lit places and indoors are left alone. 0 = the game's own night."], 0, 0.9, Direct("NightDarkness") },
    { L["Brightness"], L["Brightness of the final picture."], 0.5, 1.5, Direct("Exposure") },
    { L["View distance (yards)"], L["How far the view can reach on the old continents. 0 = the game's own limit. A long view uses much more memory: lower it if the game runs out of memory. Turning it on when it was 0 at start needs a restart."], 0, 1583.33, Direct("FarClipMax") },
    { L["Lamp light"], L["How strongly lamps, torches and fires light their surroundings."], 0, 4, Direct("LampLight") },
    { L["Spell light"], L["Light cast by spells, enchants and glowing projectiles."], 0, 4, Direct("EffectLight") },
    { L["Water reflections"], L["Reflections of the sky, shores and buildings on water."], 0, 2, Direct("WaterReflect") },
    { L["Water waves"], L["Waves on water, higher in rain and snow. 0 = a still mirror."], 0, 2, Direct("WaterWaves") },
}
for _, e in ipairs(mainSliders) do
    local s = Slider(mainChild, mainControls, e[1], e[2], e[3], e[4], false, e[5], e[6], 230)
    s:SetPoint("TOPLEFT", mainChild, "TOPLEFT", 20, y - 16)
    y = y - 46
end

local wet = CheckBox(mainChild, mainControls, L["Wet surfaces in rain"], L["Wet stone and soil, and puddles, while it rains."],
    function() return Number("WetSurfaces") > 0 end,
    function(on) Write("WetSurfaces", on and 1 or 0); Write("Puddles", on and 1 or 0) end)
wet:SetPoint("TOPLEFT", mainChild, "TOPLEFT", 8, y - 4)
y = y - 30

local relief = CheckBox(mainChild, mainControls, L["Relief on models"], L["Trees, creatures and armor get relief too. Costs frame rate."],
    function() return Number("ReliefModels") == 1 end, function(on) Write("ReliefModels", on and 1 or 0) end)
relief:SetPoint("TOPLEFT", mainChild, "TOPLEFT", 8, y)
y = y - 30

local lantern = DropDown(mainChild, mainControls, L["Belt lantern"], L["A lantern at your belt that lights your way."],
    { { value = 0, text = L["Off"] }, { value = 1, text = L["In the dark"] }, { value = 2, text = L["Always"] } },
    function() return Number("Lantern") end, function(v) Write("Lantern", v) end)
lantern:SetPoint("TOPLEFT", mainChild, "TOPLEFT", 0, y - 18)
y = y - 54
mainChild:SetHeight(-y + 8)

local subPages = {}

function main.RefreshStatus(enabledNow)
    local loaded, enabledAtStart, iniFound = EbonholdLumenveilStatus()
    local installed = iniFound == 1
    if not installed then
        status:SetText(L["Lumenveil is not installed."])
    else
        if enabledNow == nil then enabledNow = Number("Enable") == 1 end
        if enabledNow and not (loaded == 1 and enabledAtStart == 1) then
            status:SetText(L["Restart the game to turn Lumenveil on."])
        else
            status:SetText("")
        end
    end
    SetEnabled(enable, installed)
    for _, c in ipairs(mainControls) do
        if c ~= enable then SetEnabled(c, installed and enabledNow) end
    end
    for _, page in ipairs(subPages) do
        for _, c in ipairs(page.controls) do SetEnabled(c, installed) end
    end
end

main.refresh = function()
    for _, c in ipairs(mainControls) do c.Refresh() end
    main.RefreshStatus()
end
main:SetScript("OnShow", main.refresh)
main.okay = function() end
main.cancel = function() end
main.default = function()
    for _, key in ipairs({ "Enable", "Quality", "Shafts", "MoonShafts", "NightDarkness", "Exposure", "FarClipMax",
                           "LampLight", "EffectLight", "WaterReflect", "WaterWaves", "WetSurfaces", "Puddles",
                           "ReliefModels", "Lantern", "ZoneDensity" }) do
        if DEFAULTS[key] then Write(key, DEFAULTS[key]) end
    end
    Flush()
    main.refresh()
end

OptionsFrame_AddCategory(VideoOptionsFrame, main)

-- ── One page per group: every setting of the file ────────────────────────

local ROW_SLIDER, ROW_CHECK, ROW_TEXT = 46, 28, 44

local function BuildPage(index, pageName)
    local page = CreateFrame("Frame", "VideoOptionsLumenveilPage" .. index, VideoOptionsFramePanelContainer)
    page.name = pageName
    page.parent = main.name
    page.controls = {}
    page:Hide()

    local head = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", 16, -16)
    head:SetText(pageName)
    Notice(page, head)
    local sub = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    sub:SetText(L["Hover a setting to see what it does. Type an exact value in a box and press Enter."])

    local scroll = CreateFrame("ScrollFrame", page:GetName() .. "Scroll", page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -58)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -30, 8)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(340)
    scroll:SetScrollChild(child)

    local y, keys = -8, {}
    for _, s in ipairs(SETTINGS) do
        if s.page == index then
            keys[#keys + 1] = s.key
            local key = s.key
            if s.kind == "bool" then
                local cb = CheckBox(child, page.controls, s.label, s.tip,
                    function() return Number(key) ~= 0 end, function(on) Write(key, on and 1 or 0) end)
                cb:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y)
                y = y - ROW_CHECK
            elseif s.kind == "float" or s.kind == "int" then
                local sl = Slider(child, page.controls, s.label, s.tip, s.min, s.max, s.kind == "int",
                    function() return Number(key) end, function(v) Write(key, v) end, 230)
                sl:SetPoint("TOPLEFT", child, "TOPLEFT", 20, y - 16)
                y = y - ROW_SLIDER
            else
                local tb = TextBox(child, page.controls, s.label, s.tip,
                    function() return Raw(key) end, function(v, done) Write(key, v, done) end, 310)
                tb:SetPoint("TOPLEFT", child, "TOPLEFT", 24, y - 18)
                y = y - ROW_TEXT
            end
        end
    end
    child:SetHeight(-y + 8)

    page.refresh = function()
        for _, c in ipairs(page.controls) do c.Refresh() end
        main.RefreshStatus()
    end
    page:SetScript("OnShow", page.refresh)
    page.okay = function() end
    page.cancel = function() end
    page.default = function()
        for _, key in ipairs(keys) do Write(key, DEFAULTS[key]) end
        Flush()
        page.refresh()
    end

    subPages[#subPages + 1] = page
    OptionsFrame_AddCategory(VideoOptionsFrame, page)
end

for index, pageName in ipairs(PAGES) do BuildPage(index, pageName) end

-- A failed write: say so on the page and put every control back to what the file really holds.
OnSaved = function(ok)
    local text = ok and "" or L["Last change not saved. Try again in a moment."]
    for _, fs in ipairs(notices) do fs:SetText(text) end
    if ok then return end
    if main:IsShown() then main.refresh() end
    for _, page in ipairs(subPages) do
        if page:IsShown() then page.refresh() end
    end
end
