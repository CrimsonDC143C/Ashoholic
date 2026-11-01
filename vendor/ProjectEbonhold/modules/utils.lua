local base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local base64_lookup = {}
for i = 1, #base64_chars do
    base64_lookup[string.sub(base64_chars, i, i)] = i - 1
end

utils = {};

-- Global flag to stop all OnUpdate handlers when game is closing
ProjectEbonhold_IsClosing = false

-- Check if we're on a development realm (contains "(PTR)" in name)
function utils.IsDevRealm()
    local realmName = GetRealmName()
    if not realmName then
        return false
    end
    
    -- Make case-insensitive by converting to uppercase
    local upperRealmName = string.upper(realmName)
    return string.find(upperRealmName, "(PTR)", 1, true) ~= nil
end

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    ProjectEbonhold_IsClosing = true
end)


local function band(a, b)
    local result = 0
    local bit = 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return result
end

local function bor(a, b)
    local result = 0
    local bit = 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then
            result = result + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return result
end

local function rshift(a, n)
    return math.floor(a / (2 ^ n))
end


local function Base64Encode(data)
    local result = {}
    local i = 1
    while i <= #data do
        local b1 = data[i]
        local b2 = data[i + 1] or 0
        local b3 = data[i + 2] or 0

        local value = b1 * 65536 + b2 * 256 + b3

        table.insert(result, string.sub(base64_chars, rshift(value, 18) + 1, rshift(value, 18) + 1))
        table.insert(result,
            string.sub(base64_chars, band(rshift(value, 12), 0x3F) + 1, band(rshift(value, 12), 0x3F) + 1))

        if i + 1 <= #data then
            table.insert(result,
                string.sub(base64_chars, band(rshift(value, 6), 0x3F) + 1, band(rshift(value, 6), 0x3F) + 1))
        else
            table.insert(result, "=")
        end

        if i + 2 <= #data then
            table.insert(result, string.sub(base64_chars, band(value, 0x3F) + 1, band(value, 0x3F) + 1))
        else
            table.insert(result, "=")
        end

        i = i + 3
    end
    return table.concat(result)
end


local function Base64Decode(encoded)
    local result = {}
    local i = 1
    while i <= #encoded do
        local c1 = string.sub(encoded, i, i)
        local c2 = string.sub(encoded, i + 1, i + 1)
        local c3 = string.sub(encoded, i + 2, i + 2)
        local c4 = string.sub(encoded, i + 3, i + 3)

        local v1 = base64_lookup[c1] or 0
        local v2 = base64_lookup[c2] or 0
        local v3 = c3 == "=" and 0 or (base64_lookup[c3] or 0)
        local v4 = c4 == "=" and 0 or (base64_lookup[c4] or 0)

        local value = v1 * 262144 + v2 * 4096 + v3 * 64 + v4

        table.insert(result, rshift(value, 16))
        if c3 ~= "=" then
            table.insert(result, band(rshift(value, 8), 0xFF))
        end
        if c4 ~= "=" then
            table.insert(result, band(value, 0xFF))
        end

        i = i + 4
    end
    return result
end


local function EncodeVarInt(value)
    local bytes = {}
    while value >= 0x80 do
        table.insert(bytes, bor(band(value, 0x7F), 0x80))
        value = rshift(value, 7)
    end
    table.insert(bytes, value)
    return bytes
end


local function DecodeVarInt(bytes, pos)
    local result = 0
    local shift = 0
    while pos <= #bytes do
        local byte = bytes[pos]
        pos = pos + 1
        result = result + band(byte, 0x7F) * (2 ^ shift)
        if band(byte, 0x80) == 0 then
            return result, pos
        end
        shift = shift + 7
        if shift >= 32 then
            return nil, pos
        end
    end
    return nil, pos
end

utils.band = band
utils.bor = bor
utils.rshift = rshift
utils.Base64Encode = Base64Encode
utils.Base64Decode = Base64Decode
utils.EncodeVarInt = EncodeVarInt
utils.DecodeVarInt = DecodeVarInt





if not C_Timer then
    C_Timer = {}

    -- One driver frame runs every pending timer, and is shown only while some are
    -- pending. Each call used to create its own Frame, and the 3.3.5 client never
    -- frees a frame: dozens of dead frames piled up over a session.
    local timers = {}
    local driver = CreateFrame("Frame")
    driver:Hide()

    driver:SetScript("OnUpdate", function(self, delta)
        if ProjectEbonhold_IsClosing then
            wipe(timers)
            self:Hide()
            return
        end
        delta = math.min(delta, 0.1) -- Cap delta to prevent freeze after alt-tab
        -- timers added by a callback start on the next frame
        local n = #timers
        for i = 1, n do
            local t = timers[i]
            if not t.cancelled then
                t.elapsed = t.elapsed + delta
                if t.elapsed >= t.delay then
                    t.elapsed = 0
                    t.count = t.count + 1
                    if not t.ticker or (t.iterations and t.count >= t.iterations) then
                        t.cancelled = true
                    end
                    -- one failing callback must not stop the others
                    local ok, err = pcall(t.callback)
                    if not ok then geterrorhandler()(err) end
                end
            end
        end
        local kept = 0
        for i = 1, #timers do
            local t = timers[i]
            if not t.cancelled then
                kept = kept + 1
                timers[kept] = t
            end
        end
        for i = #timers, kept + 1, -1 do timers[i] = nil end
        if kept == 0 then self:Hide() end
    end)

    -- The handle: handle:Cancel() and handle.Cancel() both work.
    local function Schedule(delay, callback, ticker, iterations)
        local t = { delay = delay or 0, callback = callback, ticker = ticker, iterations = iterations, elapsed = 0, count = 0 }
        t.Cancel = function() t.cancelled = true end
        t.IsCancelled = function() return t.cancelled == true end
        timers[#timers + 1] = t
        driver:Show()
        return t
    end

    function C_Timer.After(delay, callback)
        return Schedule(delay, callback, false)
    end

    function C_Timer.NewTimer(delay, callback)
        return Schedule(delay, callback, false)
    end

    function C_Timer.NewTicker(interval, callback, iterations)
        return Schedule(interval, callback, true, iterations)
    end
end











function utils.CreateCustomButton(texturePath, parent, size, text, onClick)
    
    local defaultTexture = "Interface\\AddOns\\ProjectEbonhold\\assets\\128redbutton9sliced"
    texturePath = texturePath or defaultTexture

    
    local width, height
    if type(size) == "table" then
        width = size.width or size[1] or 200
        height = size.height or size[2] or 40
    else
        width = size or 200
        height = size and (size * 0.2) or 40 
    end

    
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")

    
    local textureCoords = {
        normal = { 0.006, 0.916, 0.514, 0.756 },  
        pushed = { 0.006, 0.916, 0.260, 0.502 },  
        disabled = { 0.006, 0.916, 0.006, 0.248 } 
    }

    
    local normalTexture = button:CreateTexture(nil, "BACKGROUND")
    normalTexture:SetAllPoints(button)
    normalTexture:SetTexture(texturePath)
    normalTexture:SetTexCoord(unpack(textureCoords.normal))
    button:SetNormalTexture(normalTexture)

    
    local pushedTexture = button:CreateTexture(nil, "BACKGROUND")
    pushedTexture:SetAllPoints(button)
    pushedTexture:SetTexture(texturePath)
    pushedTexture:SetTexCoord(unpack(textureCoords.pushed))
    button:SetPushedTexture(pushedTexture)

    
    local disabledTexture = button:CreateTexture(nil, "BACKGROUND")
    disabledTexture:SetAllPoints(button)
    disabledTexture:SetTexture(texturePath)
    disabledTexture:SetTexCoord(unpack(textureCoords.disabled))
    button:SetDisabledTexture(disabledTexture)

    
    local highlightTexture = button:CreateTexture(nil, "HIGHLIGHT")
    highlightTexture:SetAllPoints(button)
    highlightTexture:SetTexture(texturePath)
    highlightTexture:SetTexCoord(unpack(textureCoords.normal))
    highlightTexture:SetAlpha(0.3)
    button:SetHighlightTexture(highlightTexture)

    
    if text then
        local fontString = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fontString:SetPoint("CENTER")
        fontString:SetText(text)
        fontString:SetTextColor(1, 1, 1, 1) 
        button.text = fontString

        
        button.SetTextColor = function(self, r, g, b, a)
            if self.text then
                self.text:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            end
        end

        
        button.SetText = function(self, newText)
            if self.text then
                self.text:SetText(newText or "")
            end
        end
    end

    
    if onClick and type(onClick) == "function" then
        button:SetScript("OnClick", onClick)
    end

    
    button.SetButtonState = function(self, state)
        if state == "disabled" then
            self:Disable()
        elseif state == "normal" then
            self:Enable()
        end
    end

    
    button.GetTextureCoords = function(self, state)
        return textureCoords[state or "normal"]
    end

    return button
end




function utils.CreateSimpleCustomButton(parent, text, onClick, width, height, texturePath)
    local size = { width = width or 200, height = height or 40 }
    return utils.CreateCustomButton(texturePath, parent, size, text, onClick)
end















function utils.CreateDynamicBackground(texturePath, parent, width, height, topCoords, middleCoords, bottomCoords,
                                       topHeight, bottomHeight)
    topHeight = topHeight or 30
    bottomHeight = bottomHeight or 30
    local middleHeight = math.max(10, height - topHeight - bottomHeight)

    
    local bgFrame = CreateFrame("Frame", nil, parent)
    bgFrame:SetSize(width, height)
    bgFrame:SetFrameLevel(parent:GetFrameLevel() - 1) 

    
    local topTexture = bgFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    topTexture:SetTexture(texturePath)
    topTexture:SetTexCoord(unpack(topCoords))
    topTexture:SetPoint("TOPLEFT", bgFrame, "TOPLEFT", 0, 0)
    topTexture:SetPoint("TOPRIGHT", bgFrame, "TOPRIGHT", 0, 0)
    topTexture:SetHeight(topHeight)



    
    local bottomTexture = bgFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bottomTexture:SetTexture(texturePath)
    bottomTexture:SetTexCoord(unpack(bottomCoords))
    bottomTexture:SetPoint("BOTTOMLEFT", bgFrame, "BOTTOMLEFT", 0, -20)
    bottomTexture:SetPoint("BOTTOMRIGHT", bgFrame, "BOTTOMRIGHT", 0, 0)
    bottomTexture:SetHeight(bottomHeight)

    
    local middleTexture = bgFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    
    if middleCoords == "transparent_black" then
        middleTexture:SetTexture(1, 1, 1, 1)       
        middleTexture:SetVertexColor(0, 0, 0, 0.2) 
    else
        middleTexture:SetTexture(texturePath)
        middleTexture:SetTexCoord(unpack(middleCoords))
    end
    
    middleTexture:SetPoint("TOP", topTexture, "BOTTOM", 0, 20)
    middleTexture:SetPoint("BOTTOM", bottomTexture, "TOP", 0, -20)
    middleTexture:SetPoint("LEFT", bgFrame, "LEFT", 0, 0)
    middleTexture:SetPoint("RIGHT", bgFrame, "RIGHT", 0, 0)

    
    bgFrame.Resize = function(self, newWidth, newHeight)
        newWidth = newWidth or width
        newHeight = newHeight or height

        self:SetSize(newWidth, newHeight)

        
        
    end

    
    bgFrame.topTexture = topTexture
    bgFrame.middleTexture = middleTexture
    bgFrame.bottomTexture = bottomTexture

    return bgFrame
end



function utils.CreateDeathFrameBackground(parent, width, height)
    
    local topCoords = { 0.134766, 0.783203, 0.617188, 0.672852 }    
    local middleCoords = { 0.0332, 0.8906, 0.0322, 0.2813 }         
    local bottomCoords = { 0.126953, 0.791016, 0.556641, 0.599609 } 

    return utils.CreateDynamicBackground(
        "Interface\\AddOns\\ProjectEbonhold\\assets\\scoreboardjailerstower",
        parent,
        width,
        height,
        topCoords,
        middleCoords,
        bottomCoords,
        50, 
        50  
    )
end






local spellTooltip = CreateFrame("GameTooltip", "UtilsSpellTooltip", nil, "GameTooltipTemplate")
spellTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- A tooltip loses its owner whenever it gets hidden (Alt+Z, a cinematic), and an
-- unowned tooltip fills no lines: every scrape re-owns it first. WorldFrame, not
-- UIParent, because UIParent is the frame Alt+Z hides.
local function LoadSpellTooltip(spellId)
    spellTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    spellTooltip:ClearLines()
    spellTooltip:SetHyperlink('spell:' .. spellId)
end

-- The cast-time / requirement / reagent lines of a spell tooltip. Matched at the
-- start of the line only: a description that mentions "Instant Poison" stays.
local function IsSpellTooltipMetaLine(text)
    return text:match("^Instant") or text:match("^Requires")
        or text:match("^Tools:") or text:match("^Reagents:")
end

local function GetPlayerStats()
    local stats = {}

    
    local spellPower = 0
    local holySchool = 2
    spellPower = GetSpellBonusDamage(holySchool)
    stats.sp = spellPower

    
    local base, posBuff, negBuff = UnitAttackPower("player")
    stats.ap = base + posBuff + negBuff

    
    local stat, effectiveStat, posBuff, negBuff = UnitStat("player", 3) 
    stats.stamina = effectiveStat

    
    local baseArmor, effectiveArmor, armor, posBuff, negBuff = UnitArmor("player")
    stats.armor = effectiveArmor

    
    local str, effectiveStr = UnitStat("player", 1)
    stats.str = effectiveStr

    
    local agi, effectiveAgi = UnitStat("player", 2)
    stats.agi = effectiveAgi

    
    local int, effectiveInt = UnitStat("player", 4)
    stats.int = effectiveInt

    
    local spi, effectiveSpi = UnitStat("player", 5)
    stats.spi = effectiveSpi

    
    stats.lvl = UnitLevel("player")

    -- Highest of the three crit ratings, mirroring the server (spell_echoes_battle_rhythm)
    local critMelee = GetCombatRating(CR_CRIT_MELEE or 9) or 0
    local critRanged = GetCombatRating(CR_CRIT_RANGED or 10) or 0
    local critSpell = GetCombatRating(CR_CRIT_SPELL or 11) or 0
    stats.critrating = math.max(critMelee, critRanged, critSpell)

    -- Average weapon swing for @wepN@ / @owepN@ / @rwepN@. UnitDamage / UnitRangedDamage return the
    -- server's UNIT_FIELD_MIN/MAXDAMAGE (OFFHAND, RANGED) as is: weapon range + AP/14 x weapon speed
    -- (+ ammo for ranged), times the damage-done %. That is exactly what SPELL_EFFECT_WEAPON_PERCENT_DAMAGE
    -- multiplies (Unit::CalculateDamage, not normalized). The off-hand fields already carry the core's
    -- off-hand halving (UNIT_MOD_DAMAGE_OFFHAND TOTAL_PCT 0.5), and read 0 without an off-hand weapon.
    -- In Cat/Bear form the core swaps in paw damage and these fields follow, so @wep@ stays right in form.
    local minMain, maxMain, minOff, maxOff = UnitDamage("player")
    stats.wep = ((minMain or 0) + (maxMain or 0)) / 2
    stats.owep = ((minOff or 0) + (maxOff or 0)) / 2
    local _, minRanged, maxRanged = UnitRangedDamage("player")
    stats.rwep = ((minRanged or 0) + (maxRanged or 0)) / 2

    return stats
end



local statAliases = {
    strength = "str",
    agility = "agi",
    intellect = "int",
    spirit = "spi",
    spellpower = "sp",
    attackpower = "ap",
    attack_power = "ap",
    spell_power = "sp",
    level = "lvl",
    stam = "stamina",
    crit = "critrating",
}

local function EvalStatTerm(stats, statName, multiplier, stacks)
    multiplier = tonumber(multiplier) or 0
    statName = string.lower(statName or "")
    statName = statAliases[statName] or statName

    if statName == "flat" then
        return multiplier * stacks
    elseif statName == "base" then
        -- @base15+sp0.04@: the damage floor, counted once whatever the number
        -- of copies; CombineParts keeps max(floor, rest), like the server's std::max
        return multiplier
    elseif statName == "wep" or statName == "owep" or statName == "rwep" then
        -- @wep150@ / @owep100@ / @rwep80@: N% of the average main-hand / off-hand / ranged swing, per copy,
        -- in whole points like the server's int32 damage
        return math.floor(stats[statName] * multiplier / 100 * stacks + 0.5)
    elseif statName == "critrating" then
        -- Server grants whole steps (floor(rating / 150)), so the token multiplier is
        -- 1/step. Snap 1/multiplier to the nearest 5 to absorb truncated tokens like
        -- 0.0066 (-> 150), then floor like the server does.
        if multiplier <= 0 then return 0 end
        local perStep = math.floor((1 / multiplier) / 5 + 0.5) * 5
        if perStep <= 0 then return 0 end
        return math.floor(stats.critrating / perStep) * stacks
    elseif stats[statName] then
        return stats[statName] * multiplier * stacks
    end
    return 0
end

-- How each stat is named in the Shift breakdown. Anything not listed is
-- shown with a capital first letter (Armor, Str...).
local breakdownNames = {
    sp = "SP",
    ap = "AP",
    critrating = "Crit",
    wep = "Weapon",
    owep = "Off-hand",
    rwep = "Ranged",
}
local function BreakdownName(key)
    return breakdownNames[key] or (key:sub(1, 1):upper() .. key:sub(2))
end

-- Total of evaluated parts: "base" is a floor (max(base, everything else),
-- the script's std::max), every other part is summed.
local function CombineParts(parts)
    local floor, rest, hasFloor = 0, 0, false
    for _, p in ipairs(parts) do
        if p.key == "base" then
            floor = math.max(floor, p.value)
            hasFloor = true
        else
            rest = rest + p.value
        end
    end
    if hasFloor then
        return math.max(floor, rest)
    end
    return rest
end

-- Returns the total and the list of evaluated components
-- ({ label, value } each, in formula order) so a tooltip can show the maths.
local function CalculateStatFormula(formula, stacks)
    stacks = stacks or 1
    local stats = GetPlayerStats()
    local parts = {}

    for component in formula:gmatch("[^+]+") do
        component = component:gsub("%s+", "")

        -- Handle LOWER operator: e.g. armor0.05LOWERintellect1.5 → min(armor*0.05, intellect*1.5)
        local stat1, mult1, stat2, mult2 = component:match("^(%a+)([%d%.]+)[Ll][Oo][Ww][Ee][Rr](%a+)([%d%.]+)$")
        if stat1 then
            local val1 = EvalStatTerm(stats, stat1, mult1, stacks)
            local val2 = EvalStatTerm(stats, stat2, mult2, stacks)
            local val = math.min(val1, val2)
            table.insert(parts, { label = string.format("min(%s, %s)", BreakdownName(statAliases[string.lower(stat1)] or string.lower(stat1)), BreakdownName(statAliases[string.lower(stat2)] or string.lower(stat2))), value = val })
        elseif component:match("^[%d%.]+$") then
            -- @2+flat1@: a bare number is a constant added once, whatever the
            -- number of copies (2 + 1 per copy)
            table.insert(parts, { label = "fixed", value = tonumber(component) or 0, key = "fixed", once = true })
        else
            local statName, multiplier = component:match("^(%a+)([%d%.]+)$")
            if statName and multiplier then
                local val = EvalStatTerm(stats, statName, multiplier, stacks)
                local key = string.lower(statName)
                key = statAliases[key] or key
                local label
                if key == "flat" then
                    label = key
                elseif key == "base" then
                    label = "minimum"
                else
                    label = BreakdownName(key)
                end
                table.insert(parts, { label = label, value = val, key = key, once = (key == "base") })
            end
        end
    end

    return CombineParts(parts), parts
end

local function FormatNumber(v)
    if math.abs(v - math.floor(v + 0.5)) < 0.05 then
        return tostring(math.floor(v + 0.5))
    end
    return string.format("%.1f", v)
end

-- "(base 15 + SP 40 + AP 10)", the split of one @formula@ read as a sum,
-- shown only while Shift is held. Each term wears its stat colour, the
-- operators stay grey. `parts` is the list CalculateStatFormula returned
-- (or an aggregate built the same way).
local GREY = "|cff9d9d9d"
local breakdownColors = {
    base = "|cffff7d0a", -- orange
    flat = "|cffff7d0a",
    fixed = "|cffff7d0a",
    sp   = "|cff69ccf0", -- blue
    ap   = "|cffff3333", -- red
    wep  = "|cffc79c6e", -- tan (weapon)
    owep = "|cffc79c6e",
    rwep = "|cffc79c6e",
}

local function FormatFormulaBreakdown(total, parts)
    if not parts or #parts == 0 then return "" end
    -- the summed terms first, the floor after them: "(SP 40 + AP 10, minimum 25)"
    local chunks, floors = {}, {}
    for _, p in ipairs(parts) do
        local color = breakdownColors[p.key] or GREY
        local chunk = color .. p.label .. " " .. FormatNumber(p.value) .. "|r"
        table.insert(p.key == "base" and floors or chunks, chunk)
    end
    local text = table.concat(chunks, " " .. GREY .. "+|r ")
    if #floors > 0 then
        text = (text ~= "" and (text .. GREY .. ",|r ") or "") .. table.concat(floors, " ")
    end
    return " " .. GREY .. "(|r" .. text .. GREY .. ")|r"
end

-- Renders one @formula@ token of an echo description.
-- @ppmN@ is hidden unless Shift is held, where it reads "N PPM".
-- Stat formulas show the computed value, plus the breakdown on Shift.
-- `override` = { total, parts } when the caller aggregated several copies.
local function RenderFormulaToken(formula, stacks, override)
    local ppm = formula:match("^%s*[Pp][Pp][Mm]%s*([%d%.]+)%s*$")
    if ppm then
        if IsShiftKeyDown() then
            return "|cff2cfe32" .. ppm .. " PPM|r"
        end
        return ""
    end

    local total, parts
    if override then
        total, parts = override.total, override.parts
    else
        total, parts = CalculateStatFormula(formula, stacks)
    end
    -- the server deals whole points (int32 of AP x ratio), so a stat-scaled amount drops its
    -- decimals ("3120.4" on Last Drop, 2026-10-27); a small value stays as it was ("0.25 sec")
    local shown = total
    if override or total >= 10 then
        shown = math.floor(total)
    end
    local text = "|cff2cfe32" .. shown .. "|r"
    if IsShiftKeyDown() then
        text = text .. FormatFormulaBreakdown(total, parts)
    end
    return text
end

-- A hidden @ppm@ leaves "a chance  to" behind; collapse the gap. The final
-- gsub("%s+", " ") already does that for spaces, this handles the punctuation.
local function TidyHiddenTokens(text)
    return (text:gsub("%s+([,%.;:])", "%1"))
end


local function ExtractSpellFormulas(spellId)
    local spellName = GetSpellInfo(spellId)
    if not spellName then
        return nil, nil
    end

    LoadSpellTooltip(spellId)

    local formulas = {}
    local description = ""

    for i = 2, spellTooltip:NumLines() do
        local line = _G["UtilsSpellTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text ~= "" and not text:match("^%s*$") then
                if not IsSpellTooltipMetaLine(text) then
                    
                    
                    for formula in text:gmatch("@(.-)@") do
                        table.insert(formulas, formula)
                    end
                    
                    description = description .. text .. " "
                end
            end
        end
    end

    return formulas, description
end

-- Plain tooltip text, for searching only. Same scrape as GetSpellDescription
-- but it skips the @formula@ evaluation (which re-reads every player stat for
-- each formula) and the truncation, neither of which a text match needs.
-- Returns "" when the spell has no tooltip body.
function utils.GetSpellSearchText(spellId)
    if not spellId or not GetSpellInfo(spellId) then return "" end

    LoadSpellTooltip(spellId)

    local parts = {}
    for i = 2, spellTooltip:NumLines() do
        local line = _G["UtilsSpellTooltipTextLeft" .. i]
        local text = line and line:GetText()
        if text and text ~= "" and not text:match("^%s*$") then
            if not IsSpellTooltipMetaLine(text) then
                table.insert(parts, text)
            end
        end
    end

    return (table.concat(parts, " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1"))
end

function utils.GetSpellDescription(spellId, maxLength, stacks)
    maxLength = maxLength or 100
    stacks = stacks or 1

    
    local spellName = GetSpellInfo(spellId)
    if not spellName then
        return "Click for details"
    end

    
    LoadSpellTooltip(spellId)

    local description = ""
    for i = 2, spellTooltip:NumLines() do
        local line = _G["UtilsSpellTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text ~= "" and not text:match("^%s*$") then

                if not IsSpellTooltipMetaLine(text) then
                    
                    text = text:gsub("@(.-)@", function(formula)
                        return RenderFormulaToken(formula, stacks)
                    end)

                    description = description .. TidyHiddenTokens(text) .. " "
                end
            end
        end
    end

    
    description = description:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1") 
    if description == "" then
        description = "Click for details"
    elseif string.len(description) > maxLength then
        description = string.sub(description, 1, maxLength - 3) .. "..."
    end

    return description
end




-- Echo descriptions change with Shift (PPM + formula breakdown), so re-run the
-- hovered frame's OnEnter when a Shift key moves while a tooltip is up. The
-- owner of the tooltip is not always the frame that owns the OnEnter (perk
-- cards anchor the tooltip on their icon), so walk up from the mouse focus.
local shiftWatcher = CreateFrame("Frame")
shiftWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
shiftWatcher:SetScript("OnEvent", function(_, _, key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    if not GameTooltip:IsShown() then return end
    local frame = GetMouseFocus()
    local depth = 0
    while frame and frame ~= WorldFrame and frame ~= UIParent and depth < 4 do
        local onEnter = frame.GetScript and frame:GetScript("OnEnter")
        if onEnter then
            onEnter(frame)
            return
        end
        frame = frame:GetParent()
        depth = depth + 1
    end
end)

-- Perk family art, shared by the choice cards, the run panel and the journal.
-- Short aliases map onto the same texture as their "... DPS" spelling.
utils.PerkFamilyIcons = {
    ["Tank"]          = "Interface\\AddOns\\ProjectEbonhold\\assets\\perk_families\\tank",
    ["Survivability"] = "Interface\\AddOns\\ProjectEbonhold\\assets\\perk_families\\survivability",
    ["Healer"]        = "Interface\\AddOns\\ProjectEbonhold\\assets\\perk_families\\healer",
    ["Caster"]        = "Interface\\AddOns\\ProjectEbonhold\\assets\\perk_families\\caster_dps",
    ["Caster DPS"]    = "Interface\\AddOns\\ProjectEbonhold\\assets\\perk_families\\caster_dps",
    ["Melee"]         = "Interface\\AddOns\\ProjectEbonhold\\assets\\perk_families\\melee_dps",
    ["Melee DPS"]     = "Interface\\AddOns\\ProjectEbonhold\\assets\\perk_families\\melee_dps",
    ["Ranged"]        = "Interface\\AddOns\\ProjectEbonhold\\assets\\perk_families\\ranged_dps",
    ["Ranged DPS"]    = "Interface\\AddOns\\ProjectEbonhold\\assets\\perk_families\\ranged_dps",
}

-- Spec families ("Class - Spec") -> the icon of that spec's talent tab (TalentTab.dbc).
-- Drawn as the badge in the top-left corner of a choice card.
utils.PerkSpecIcons = {
    ["Warrior - Arms"]              = "Interface\\Icons\\Ability_Rogue_Eviscerate",
    ["Warrior - Fury"]              = "Interface\\Icons\\Ability_Warrior_InnerRage",
    ["Warrior - Protection"]        = "Interface\\Icons\\INV_Shield_06",
    ["Paladin - Holy"]              = "Interface\\Icons\\Spell_Holy_HolyBolt",
    ["Paladin - Protection"]        = "Interface\\Icons\\Spell_Holy_DevotionAura",
    ["Paladin - Retribution"]       = "Interface\\Icons\\Spell_Holy_AuraOfLight",
    ["Hunter - Beast Mastery"]      = "Interface\\Icons\\Ability_Hunter_BeastTaming",
    ["Hunter - Marksmanship"]       = "Interface\\Icons\\Ability_Marksmanship",
    ["Hunter - Survival"]           = "Interface\\Icons\\Ability_Hunter_SwiftStrike",
    ["Rogue - Assassination"]       = "Interface\\Icons\\Ability_Rogue_Eviscerate",
    ["Rogue - Combat"]              = "Interface\\Icons\\Ability_BackStab",
    ["Rogue - Subtlety"]            = "Interface\\Icons\\Ability_Stealth",
    ["Priest - Discipline"]         = "Interface\\Icons\\Spell_Holy_WordFortitude",
    ["Priest - Holy"]               = "Interface\\Icons\\Spell_Holy_GuardianSpirit",
    ["Priest - Shadow"]             = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    ["Death Knight - Blood"]        = "Interface\\Icons\\Spell_Deathknight_BloodPresence",
    ["Death Knight - Frost"]        = "Interface\\Icons\\Spell_Deathknight_FrostPresence",
    ["Death Knight - Unholy"]       = "Interface\\Icons\\Spell_Deathknight_UnholyPresence",
    ["Shaman - Elemental"]          = "Interface\\Icons\\Spell_Nature_Lightning",
    ["Shaman - Enhancement"]        = "Interface\\Icons\\Spell_Nature_LightningShield",
    ["Shaman - Restoration"]        = "Interface\\Icons\\Spell_Nature_MagicImmunity",
    ["Mage - Arcane"]               = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    ["Mage - Fire"]                 = "Interface\\Icons\\Spell_Fire_FireBolt02",
    ["Mage - Frost"]                = "Interface\\Icons\\Spell_Frost_FrostBolt02",
    ["Warlock - Affliction"]        = "Interface\\Icons\\Spell_Shadow_DeathCoil",
    ["Warlock - Demonology"]        = "Interface\\Icons\\Spell_Shadow_Metamorphosis",
    ["Warlock - Destruction"]       = "Interface\\Icons\\Spell_Shadow_RainOfFire",
    ["Druid - Balance"]             = "Interface\\Icons\\Spell_Nature_StarFall",
    ["Druid - Feral Combat"]        = "Interface\\Icons\\Ability_Racial_BearForm",
    ["Druid - Restoration"]         = "Interface\\Icons\\Spell_Nature_HealingTouch",
}

-- Families as inline tooltip icons. A family with no art falls back to its
-- name, so an unmapped one is still readable rather than invisible.
function utils.FormatPerkFamilies(families, size)
    if not families or #families == 0 then return nil end
    size = size or 22
    local parts = {}
    for _, family in ipairs(families) do
        local tex = utils.PerkFamilyIcons[family]
        if tex then
            table.insert(parts, "|T" .. tex .. ":" .. size .. ":" .. size .. ":0:-1|t")
        else
            table.insert(parts, family)
        end
    end
    return table.concat(parts, " ")
end

function utils.GetStackedSpellDescription(spellInstances, maxLength)
    maxLength = maxLength or 100
    
    if not spellInstances or #spellInstances == 0 then
        return "Click for details"
    end

    
    local firstSpellId = spellInstances[1].spellId
    local spellName = GetSpellInfo(firstSpellId)
    if not spellName then
        return "Click for details"
    end

    
    local formulas, descTemplate = ExtractSpellFormulas(firstSpellId)
    if not formulas or #formulas == 0 then
        return utils.GetSpellDescription(firstSpellId, maxLength, spellInstances[1].stacks or 1)
    end

    
    local totalsByFormula = {}
    
    for _, instance in ipairs(spellInstances) do
        local instanceFormulas = ExtractSpellFormulas(instance.spellId)
        local instanceStacks = instance.stacks or 1
        
        if instanceFormulas then
            for formulaIndex, formula in ipairs(instanceFormulas) do
                local total, parts = CalculateStatFormula(formula, instanceStacks)
                local agg = totalsByFormula[formulaIndex]
                if not agg then
                    agg = { total = 0, parts = {}, byLabel = {} }
                    totalsByFormula[formulaIndex] = agg
                end
                for _, p in ipairs(parts) do
                    local slot = agg.byLabel[p.label]
                    if not slot then
                        slot = { label = p.label, value = 0, key = p.key }
                        agg.byLabel[p.label] = slot
                        table.insert(agg.parts, slot)
                    end
                    -- "base" (floor) and bare constants count once across all copies, not per copy
                    if p.once then
                        slot.value = math.max(slot.value, p.value)
                    else
                        slot.value = slot.value + p.value
                    end
                end
                agg.total = CombineParts(agg.parts)
            end
        end
    end

    
    LoadSpellTooltip(firstSpellId)

    local description = ""
    local formulaIndex = 1

    for i = 2, spellTooltip:NumLines() do
        local line = _G["UtilsSpellTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text ~= "" and not text:match("^%s*$") then
                if not IsSpellTooltipMetaLine(text) then
                    
                    
                    text = text:gsub("@(.-)@", function(formula)
                        local agg = totalsByFormula[formulaIndex] or { total = 0, parts = {} }
                        formulaIndex = formulaIndex + 1
                        return RenderFormulaToken(formula, 1, agg)
                    end)

                    description = description .. TidyHiddenTokens(text) .. " "
                end
            end
        end
    end

    
    description = description:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    if description == "" then
        description = "Click for details"
    elseif string.len(description) > maxLength then
        description = string.sub(description, 1, maxLength - 3) .. "..."
    end

    return description
end
