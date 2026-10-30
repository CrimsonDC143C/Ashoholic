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

    
    function C_Timer.After(delay, callback)
        local frame = CreateFrame("Frame")
        local elapsed = 0

        frame:SetScript("OnUpdate", function(self, delta)
            if ProjectEbonhold_IsClosing then self:SetScript("OnUpdate", nil) return end
            delta = math.min(delta, 0.1) -- Cap delta to prevent freeze after alt-tab
            elapsed = elapsed + delta
            if elapsed >= delay then
                self:SetScript("OnUpdate", nil)
                callback()
            end
        end)

        return frame
    end

    
    function C_Timer.NewTimer(delay, callback)
        return C_Timer.After(delay, callback)
    end

    
    function C_Timer.NewTicker(interval, callback, iterations)
        local frame = CreateFrame("Frame")
        local elapsed = 0
        local count = 0

        frame:SetScript("OnUpdate", function(self, delta)
            if ProjectEbonhold_IsClosing then self:SetScript("OnUpdate", nil) return end
            delta = math.min(delta, 0.1) -- Cap delta to prevent freeze after alt-tab
            elapsed = elapsed + delta
            if elapsed >= interval then
                elapsed = 0
                count = count + 1
                callback()

                if iterations and count >= iterations then
                    self:SetScript("OnUpdate", nil)
                end
            end
        end)

        
        return {
            Cancel = function()
                frame:SetScript("OnUpdate", nil)
            end
        }
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
spellTooltip:SetOwner(UIParent, "ANCHOR_NONE")

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

    return stats
end



local function EvalStatTerm(stats, statName, multiplier, stacks)
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

    multiplier = tonumber(multiplier) or 0
    statName = string.lower(statName or "")
    statName = statAliases[statName] or statName

    if statName == "flat" then
        return multiplier * stacks
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

local function CalculateStatFormula(formula, stacks)
    stacks = stacks or 1
    local stats = GetPlayerStats()
    local total = 0

    for component in formula:gmatch("[^+]+") do
        component = component:gsub("%s+", "")

        -- Handle LOWER operator: e.g. armor0.05LOWERintellect1.5 → min(armor*0.05, intellect*1.5)
        local stat1, mult1, stat2, mult2 = component:match("^(%a+)([%d%.]+)[Ll][Oo][Ww][Ee][Rr](%a+)([%d%.]+)$")
        if stat1 then
            local val1 = EvalStatTerm(stats, stat1, mult1, stacks)
            local val2 = EvalStatTerm(stats, stat2, mult2, stacks)
            total = total + math.min(val1, val2)
        else
            local statName, multiplier = component:match("^(%a+)([%d%.]+)$")
            if statName and multiplier then
                total = total + EvalStatTerm(stats, statName, multiplier, stacks)
            end
        end
    end

    return total
end


local function ExtractSpellFormulas(spellId)
    local spellName = GetSpellInfo(spellId)
    if not spellName then
        return nil, nil
    end

    spellTooltip:ClearLines()
    spellTooltip:SetHyperlink('spell:' .. spellId)

    local formulas = {}
    local description = ""
    
    for i = 2, spellTooltip:NumLines() do
        local line = _G["UtilsSpellTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text ~= "" and not text:match("^%s*$") then
                if not text:match("Instant") and
                   not text:match("Requires") and
                   not text:match("Tools:") and
                   not text:match("Reagents:") then
                    
                    
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

    spellTooltip:ClearLines()
    spellTooltip:SetHyperlink('spell:' .. spellId)

    local parts = {}
    for i = 2, spellTooltip:NumLines() do
        local line = _G["UtilsSpellTooltipTextLeft" .. i]
        local text = line and line:GetText()
        if text and text ~= "" and not text:match("^%s*$") then
            if not text:match("Instant") and
                not text:match("Requires") and
                not text:match("Tools:") and
                not text:match("Reagents:") then
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

    
    spellTooltip:ClearLines()
    spellTooltip:SetHyperlink('spell:' .. spellId)

    local description = ""
    for i = 2, spellTooltip:NumLines() do 
        local line = _G["UtilsSpellTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text ~= "" and not text:match("^%s*$") then
                
                if
                    not text:match("Instant") and
                    not text:match("Requires") and
                    not text:match("Tools:") and
                    not text:match("Reagents:") then
                    
                    text = text:gsub("@(.-)@", function(formula)
                        local calculatedValue = CalculateStatFormula(formula, stacks)
                        return "|cff2cfe32" .. calculatedValue .. "|r"
                    end)

                    description = description .. text .. " "
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
                totalsByFormula[formulaIndex] = (totalsByFormula[formulaIndex] or 0) + 
                                                CalculateStatFormula(formula, instanceStacks)
            end
        end
    end

    
    spellTooltip:ClearLines()
    spellTooltip:SetHyperlink('spell:' .. firstSpellId)

    local description = ""
    local formulaIndex = 1
    
    for i = 2, spellTooltip:NumLines() do
        local line = _G["UtilsSpellTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text ~= "" and not text:match("^%s*$") then
                if not text:match("Instant") and
                   not text:match("Requires") and
                   not text:match("Tools:") and
                   not text:match("Reagents:") then
                    
                    
                    text = text:gsub("@(.-)@", function(formula)
                        local total = totalsByFormula[formulaIndex] or 0
                        formulaIndex = formulaIndex + 1
                        return "|cff2cfe32" .. math.floor(total) .. "|r"
                    end)

                    description = description .. text .. " "
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
