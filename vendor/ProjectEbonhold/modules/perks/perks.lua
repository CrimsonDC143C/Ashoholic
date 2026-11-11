local perkMainFrame = nil
-- Forward declarations: the souvenir-stage and card-entrance helpers are
-- defined further down but used by handlers registered earlier (card
-- buttons, the reveal buttons). A closure only sees a local declared above it.
local memoryDeck = {}
local memoryHint
local memoryStageShown = false
local pendingMemoryReveal = false
local ChoicesAreMemoryStage, MemoryRowOffset, GetMemoryDeckCard, HideMemoryDeck
local PlayMemoryKeepBurst, PlayMemoryGiveUp, EnsureMemoryWidgets, LayoutMemoryStage, ShowMemoryStageWidgets
local RequestMemoryDraw, SouvenirOnTableName
local PlaceCard, PlayCardEntrance, PlayCardsEntrance, CollectVisibleCards
local GetCardBody -- defined with the guided tour, used by the tour helpers below it
local perkFramePool = {}
local hideButton = nil
local rerollButton = nil
local chooseButton = nil
local perkFamilyHintFrame = nil
local ShowPerkFamilyHint
local isFading = false
local isSelecting = false
local isShowingPerkUI = false
-- The whole card is clickable and the next draw lands under the cursor: without this wait, the second
-- click of a double-click would pick an echo of the next draw. About the time the cards take to turn over.
local PERK_CARDS_GRACE_SEC = 0.45
-- The echo card: size, room between two cards, height of the row, how much lower the outer cards sit
local CARD_W, CARD_H, CARD_PITCH, CARD_ROW_Y, CARD_ARC = 216, 340, 232, 70, 14
local perkCardsGraceUntil = 0

local function IsTransparentDesign()
    return ProjectEbonholdOptionsService and ProjectEbonholdOptionsService:GetSetting("transparentDesign")
end

local function IsPerkShowSelectCountEnabled()
    return ProjectEbonholdOptionsService and ProjectEbonholdOptionsService:GetSetting("perkShowSelectCount")
end

local function GetSelectLabel(count)
    if IsPerkShowSelectCountEnabled() and count then
        return "Select (" .. count .. ")"
    end
    return "Select"
end

-- Spec draw (level 10 / 20 / ... 80). perks_service keeps the server's tag in
-- Perks.currentSpecDraw = { chosen = spec family id }, 0 = the level 10 draw where the
-- spec is chosen. The draw gets a gold banner and light rays turning behind the row;
-- the cards themselves keep the plain look.
local SPEC_GOLD = { 1, 0.82, 0 }
local specBanner, specRays

local function GetSpecDraw()
    local svc = ProjectEbonhold and ProjectEbonhold.Perks
    return svc and svc.currentSpecDraw or nil
end

-- "Mage - Fire" -> "Fire", "Mage - Fire": the spec family an echo carries in the perk database.
local function GetEchoSpecName(spellId)
    local db = ProjectEbonhold and ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[spellId]
    if db and db.families then
        for _, family in ipairs(db.families) do
            local spec = family:match("^.+ %- (.+)$")
            if spec then return spec, family end
        end
    end
    return nil
end

-- Current stat values on an echo tooltip (owner 2026-10-22). The stats an echo raises
-- come first from its spell data: ECHO_STATS_BY_SPELL is generated from the echo's own auras
-- and the self-buff its proc triggers (MOD_STAT, MOD_RESISTANCE armor, MOD_ATTACK_POWER,
-- MOD_DAMAGE_DONE / healing, MOD_RATING mask, crit / haste / hit chance, max health / mana,
-- mana regen). Echoes driven by scripts or dummies fall back to their description text.
local ECHO_STATS_BY_SPELL = {
    [200000]="STR", [200001]="AGI", [200002]="INT", [200003]="SPI", [200004]="STA", [200008]="SP",
    [200009]="AP,RAP", [200017]="ARMOR", [200035]="HEALTH", [200429]="HIT", [200430]="CRIT", [200431]="HASTE",
    [200432]="ARPEN", [200433]="EXPERTISE", [200441]="ARMOR", [200451]="STR", [200452]="AGI", [200453]="INT",
    [200454]="SPI", [200455]="STA", [200459]="SP", [200460]="AP,RAP", [200464]="ARMOR", [200480]="HIT",
    [200481]="CRIT", [200482]="HASTE", [200483]="ARPEN", [200484]="EXPERTISE", [200490]="ARMOR", [200492]="STR",
    [200493]="AGI", [200494]="INT", [200495]="SPI", [200496]="STA", [200500]="SP", [200501]="AP,RAP",
    [200505]="ARMOR", [200521]="HIT", [200522]="CRIT", [200523]="HASTE", [200524]="ARPEN", [200525]="EXPERTISE",
    [200528]="ARMOR", [200674]="HEALTH", [200736]="ARMOR", [200738]="MANA", [200886]="HEALTH",
}

-- Description fallback: a keyword counts only where the text says the echo raises it
-- ("your Haste", "Strength by", "Armor is increased", "increases Spell Power"), so damage
-- formulas such as "27% of Spell Power" add nothing.
local ECHO_STAT_KEYWORDS = {
    { "armor penetration", "ARPEN" }, { "ranged attack power", "RAP" }, { "attack power", "AP" },
    { "spell power", "SP" }, { "critical strike", "CRIT" }, { "crit chance", "CRIT" },
    { "strength", "STR" }, { "agility", "AGI" }, { "stamina", "STA" }, { "intellect", "INT" },
    { "spirit", "SPI" }, { "armor", "ARMOR" }, { "haste", "HASTE" }, { "hit chance", "HIT" },
    { "hit rating", "HIT" }, { "expertise", "EXPERTISE" }, { "defense", "DEFENSE" },
    { "dodge", "DODGE" }, { "parry", "PARRY" }, { "block chance", "BLOCK" }, { "block value", "BLOCK" },
    { "maximum health", "HEALTH" }, { "max health", "HEALTH" }, { "maximum mana", "MANA" },
    { "mana regeneration", "MP5" }, { "mana per 5", "MP5" },
}
local ECHO_STAT_ORDER = { "STR", "AGI", "STA", "INT", "SPI", "ARMOR", "AP", "RAP", "SP", "CRIT", "HASTE",
    "HIT", "EXPERTISE", "ARPEN", "DEFENSE", "DODGE", "PARRY", "BLOCK", "HEALTH", "MANA", "MP5" }

-- Best of several combat ratings (melee / ranged / spell), as "N rating (+X%)". The CR_*
-- indexes are FrameXML globals of the 3.3.5 client; the numbers are their values, as a fallback.
local function BestRating(names)
    local bestRating, bestBonus = 0, 0
    for _, n in ipairs(names) do
        local idx = _G[n[1]] or n[2]
        local rating, bonus = GetCombatRating(idx) or 0, GetCombatRatingBonus(idx) or 0
        if bonus > bestBonus or (bonus == bestBonus and rating > bestRating) then
            bestRating, bestBonus = rating, bonus
        end
    end
    return string.format("%d rating (+%.2f%%)", bestRating, bestBonus)
end

local ECHO_STAT_VALUE = {
    STR = { "Strength", function() return select(2, UnitStat("player", 1)) end },
    AGI = { "Agility", function() return select(2, UnitStat("player", 2)) end },
    STA = { "Stamina", function() return select(2, UnitStat("player", 3)) end },
    INT = { "Intellect", function() return select(2, UnitStat("player", 4)) end },
    SPI = { "Spirit", function() return select(2, UnitStat("player", 5)) end },
    ARMOR = { "Armor", function() return select(2, UnitArmor("player")) end },
    AP = { "Attack Power", function() local b, p, n = UnitAttackPower("player"); return b + p + n end },
    RAP = { "Ranged Attack Power", function() local b, p, n = UnitRangedAttackPower("player"); return b + p + n end },
    SP = { "Spell Power", function()
        local best = GetSpellBonusHealing() or 0
        for school = 2, 7 do best = math.max(best, GetSpellBonusDamage(school) or 0) end
        return best
    end },
    CRIT = { "Crit Chance", function()
        local best = math.max(GetCritChance() or 0, GetRangedCritChance() or 0)
        for school = 2, 7 do best = math.max(best, GetSpellCritChance(school) or 0) end
        return string.format("%.2f%%", best)
    end },
    HASTE = { "Haste", function() return BestRating({ { "CR_HASTE_MELEE", 18 }, { "CR_HASTE_RANGED", 19 }, { "CR_HASTE_SPELL", 20 } }) end },
    HIT = { "Hit", function() return BestRating({ { "CR_HIT_MELEE", 6 }, { "CR_HIT_RANGED", 7 }, { "CR_HIT_SPELL", 8 } }) end },
    EXPERTISE = { "Expertise", function() return (GetExpertise()) end },
    ARPEN = { "Armor Penetration", function() return BestRating({ { "CR_ARMOR_PENETRATION", 25 } }) end },
    DEFENSE = { "Defense", function() local b, m = UnitDefense("player"); return b + m end },
    DODGE = { "Dodge", function() return string.format("%.2f%%", GetDodgeChance() or 0) end },
    PARRY = { "Parry", function() return string.format("%.2f%%", GetParryChance() or 0) end },
    BLOCK = { "Block", function() return string.format("%.2f%%", GetBlockChance() or 0) end },
    HEALTH = { "Max Health", function() return UnitHealthMax("player") end },
    MANA = { "Max Mana", function() local m = UnitPowerMax("player", 0); return (m and m > 0) and m or nil end },
    MP5 = { "Mana Regen", function()
        local base = GetManaRegen()
        return base and string.format("%d per 5 sec", math.floor(base * 5 + 0.5)) or nil
    end },
}

local function GetEchoStats(spellId, description)
    local found = {}
    local fromData = spellId and ECHO_STATS_BY_SPELL[spellId]
    if fromData then
        for key in fromData:gmatch("[^,]+") do found[key] = true end
        return found
    end
    if type(description) ~= "string" or description == "" then return found end
    local d = description:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
    local dNoArpen = d:gsub("armor penetration", "")
    for _, kw in ipairs(ECHO_STAT_KEYWORDS) do
        local word, key = kw[1], kw[2]
        -- "armor" inside "armor penetration" is the other stat
        local text = (key == "ARMOR") and dNoArpen or d
        if not found[key] and (text:find("your " .. word, 1, true) or text:find(word .. " by", 1, true)
            or text:find(word .. " is increased", 1, true) or text:find("increases " .. word, 1, true)) then
            found[key] = true
        end
    end
    return found
end

-- The amount the description gives a stat ("Intellect by 39", "Armor by 10%"): number, isPercent.
local function EchoStatAmount(text, key)
    for _, kw in ipairs(ECHO_STAT_KEYWORDS) do
        if kw[2] == key then
            local n, pct = text:match(kw[1] .. " by (%d+)(%%?)")
            if n then return tonumber(n), pct == "%" end
        end
    end
end

-- One line per stat the echo raises, under its effect, roguelite style (owner 2026-10-23): the stat
-- and its value now in white, the value with the echo in green - "Intellect 20 » 59". The 3.3.5
-- font has no arrow glyph; "»" (UTF-8 C2 BB) is in it. A stat whose gain the text does not give
-- shows its value only. Never errors: an unknown echo, or a client API that returns nothing, adds no line.
local ECHO_STAT_CHEVRON = "\194\187"

-- An echo that gives a RATING ("increases expertise rating by 17") is shown in rating, current and
-- after: the stat's own value (2 expertise, 8.2% crit) does not add up with a rating. CR_* values of
-- the 3.3.5 client; the best of melee / ranged / spell where there are three.
local ECHO_RATING_STATS = {
    HIT = { { "hit" }, { 6, 7, 8 } }, CRIT = { { "critical strike", "crit" }, { 9, 10, 11 } },
    HASTE = { { "haste" }, { 18, 19, 20 } }, EXPERTISE = { { "expertise" }, { 24 } },
    ARPEN = { { "armor penetration" }, { 25 } }, DEFENSE = { { "defense" }, { 2 } },
    DODGE = { { "dodge" }, { 3 } }, PARRY = { { "parry" }, { 4 } }, BLOCK = { { "block" }, { 5 } },
}

-- An echo already owned: where its value stands now and where this card takes it, with the increase
-- in % (owner 2026-10-23) - "22.1 » 30.4 (+38%)", no copy count. Both values come from the echo's own
-- description rendered at the copies owned and at one more (utils.GetSpellDescription): its
-- formulas count the fixed "base" part once and the stat / flat parts per copy, so the base is
-- never doubled. The first number that moves is shown, its "%" kept. No line for a first copy or
-- a description that does not change with copies.
local function EchoNumbers(text)
    local list = {}
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for token in text:gmatch("%d+%.?%d*%%?") do
        -- "by 13." ends a sentence: the dot is not part of the number
        local unit = token:match("%%$") and "%" or ""
        local num = token:gsub("%%$", ""):gsub("%.$", "")
        list[#list + 1] = { tonumber(num), unit, num }
    end
    return list
end

local function AddEchoStackLine(tooltip, spellId, owned)
    if not spellId or not owned or owned < 1 then return false end
    local now = EchoNumbers(utils.GetSpellDescription(spellId, 500, owned))
    local after = EchoNumbers(utils.GetSpellDescription(spellId, 500, owned + 1))
    for i, a in ipairs(now) do
        local b = after[i]
        if b and a[1] and b[1] and b[1] ~= a[1] and a[1] > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine(a[3] .. a[2] .. " |cff40ff40" .. ECHO_STAT_CHEVRON .. " " .. b[3] .. b[2]
                .. " (+" .. math.floor((b[1] - a[1]) / a[1] * 100 + 0.5) .. "%)|r", 1, 1, 1)
            return true
        end
    end
    return false
end

-- Rating for 1 % (1 point for expertise / defense) at level 60, the WotLK combat rating table; scaled
-- by EchoRatingLevelFactor. Only used when the character has none of that rating yet: otherwise the
-- client's own ratio (GetCombatRatingBonus / GetCombatRating) is exact.
local ECHO_RATING_BASE = { [2] = 1.5, [3] = 12, [4] = 15, [5] = 5, [6] = 10, [7] = 10, [8] = 8,
    [9] = 14, [10] = 14, [11] = 14, [18] = 10, [19] = 10, [20] = 10, [24] = 2.5, [25] = 4.69512 }

local function EchoRatingLevelFactor(level)
    if level <= 10 then return 2 / 52 end
    if level <= 60 then return (level - 8) / 52 end
    if level <= 70 then return 82 / (262 - 3 * level) end
    return (82 / 52) * (131 / 63) ^ ((level - 70) / 10)
end

-- What the echo's rating is worth, as shown in green (owner 2026-10-23): expertise turns into dodge /
-- parry reduction (0.25 % a point), defense stays in skill points, everything else is a percentage.
local function EchoRatingGain(idx, gain)
    if idx == 24 then return string.format("+%.2f%%", gain * 0.25) end
    if idx == 2 then return string.format("+%d defense", math.floor(gain + 0.5)) end
    return string.format("+%.2f%%", gain)
end

local function EchoRatingLine(text, key, label)
    local def = ECHO_RATING_STATS[key]
    if not def then return nil end
    for _, word in ipairs(def[1]) do
        local n = text:match(word .. " rating by (%d+)")
        if n then
            local rating, bestIdx = -1, def[2][1]
            for _, idx in ipairs(def[2]) do
                local r = GetCombatRating(idx) or 0
                if r > rating then rating, bestIdx = r, idx end
            end
            local bonus = GetCombatRatingBonus(bestIdx) or 0
            local perRating = (rating > 0 and bonus > 0) and (bonus / rating)
                or 1 / (ECHO_RATING_BASE[bestIdx] * EchoRatingLevelFactor(UnitLevel("player") or 1))
            local gain = tonumber(n)
            if key == "CRIT" then label = "Critical Strike" end -- "Crit Chance rating" reads wrong
            return label .. " rating " .. rating .. " |cff40ff40" .. ECHO_STAT_CHEVRON .. " " .. (rating + gain)
                .. " (" .. EchoRatingGain(bestIdx, gain * perRating) .. ")|r"
        end
    end
end

local function AddEchoStatLines(tooltip, spellId, description)
    local ok, found = pcall(GetEchoStats, spellId, description)
    if not ok or not found or not next(found) or type(description) ~= "string" then return end
    local text = description:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
    local first = true
    for _, key in ipairs(ECHO_STAT_ORDER) do
        local def = found[key] and ECHO_STAT_VALUE[key]
        if def then
            local okRating, ratingLine = pcall(EchoRatingLine, text, key, def[1])
            local okValue, value = pcall(def[2])
            if okRating and ratingLine then
                if first then tooltip:AddLine(" "); first = false end
                tooltip:AddLine(ratingLine, 1, 1, 1)
            elseif okValue and value ~= nil then
                local line = def[1] .. " " .. tostring(value)
                if type(value) == "number" then
                    line = def[1] .. " " .. math.floor(value + 0.5)
                    local amount, isPercent = EchoStatAmount(text, key)
                    if amount then
                        local after = isPercent and value * (1 + amount / 100) or value + amount
                        line = line .. " |cff40ff40" .. ECHO_STAT_CHEVRON .. " " .. math.floor(after + 0.5) .. "|r"
                    end
                end
                if first then tooltip:AddLine(" "); first = false end
                tooltip:AddLine(line, 1, 1, 1)
            end
        end
    end
end

local function MakeSpin(texture, seconds, degrees)
    local ag = texture:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local rot = ag:CreateAnimation("Rotation")
    rot:SetDuration(seconds)
    rot:SetDegrees(degrees)
    rot:SetOrigin("CENTER", 0, 0)
    return ag
end

local function MakeBreath(region, change, seconds)
    local ag = region:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetChange(change)
    a:SetDuration(seconds)
    a:SetSmoothing("IN_OUT")
    return ag
end

local function EnsureSpecDrawWidgets()
    if specBanner or not perkMainFrame then return end

    -- Two four-point stars turning against each other read as eight shifting rays.
    -- On the main frame's background, so every card sits above them; centred on the
    -- card row (see CARD_ROW_Y).
    specRays = {}
    for i, spec in ipairs({ { 70, 360 }, { 95, -360 } }) do
        local t = perkMainFrame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture("Interface\\Cooldown\\star4")
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.78, 0.15, i == 1 and 0.55 or 0.4)
        t:SetSize(980, 980)
        t:SetPoint("CENTER", perkMainFrame, "CENTER", 0, CARD_ROW_Y)
        t.spin = MakeSpin(t, spec[1], spec[2])
        t:Hide()
        specRays[i] = t
    end

    specBanner = CreateFrame("Frame", nil, perkMainFrame)
    specBanner:SetSize(620, 72)
    -- Above the Reroll button (centre +310, 35 high) and the souvenir hint (+306)
    specBanner:SetPoint("BOTTOM", perkMainFrame, "CENTER", 0, 336)

    local glow = specBanner:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.75, 0.1, 0.9)
    glow:SetPoint("CENTER", specBanner, "CENTER", 0, 0)
    glow:SetSize(680, 140)
    specBanner.breath = MakeBreath(glow, -0.45, 1.4)

    local title = specBanner:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 28, "THICKOUTLINE")
    title:SetPoint("TOP", specBanner, "TOP", 0, -4)
    title:SetTextColor(unpack(SPEC_GOLD))
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(2, -2)
    specBanner.title = title

    local sub = specBanner:CreateFontString(nil, "OVERLAY")
    sub:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetTextColor(1, 0.93, 0.6)
    specBanner.sub = sub

    specBanner:Hide()
end

-- Banner and rays follow the cards: shown with them on a spec draw, hidden otherwise.
local function ShowSpecDrawWidgets(shown)
    local draw = GetSpecDraw()
    if not shown or not draw then
        if specBanner then
            specBanner.breath:Stop()
            specBanner:Hide()
        end
        for _, t in ipairs(specRays or {}) do
            t.spin:Stop()
            t:Hide()
        end
        return
    end

    EnsureSpecDrawWidgets()
    if not specBanner then return end

    if draw.chosen == 0 then
        specBanner.title:SetText("Choose your Echo Specialization")
        specBanner.sub:SetText("Each card is one specialization (small icon on the echo's corner). Every 10 levels of this run, you will get three echoes of the one you take")
    else
        local specName
        for _, f in ipairs(perkFramePool) do
            if f.inUse and f._perkData and not f._perkData.isGuaranteed then
                specName = GetEchoSpecName(f._spellId)
                if specName then break end
            end
        end
        specBanner.title:SetText(specName and (specName .. " Specialization") or "Specialization Echoes")
        specBanner.sub:SetText("Three echoes of the specialization you chose at level 10")
    end
    specBanner:Show()
    specBanner.breath:Play()
    for _, t in ipairs(specRays) do
        t:Show()
        t.spin:Play()
    end
end

-- "Auto Show Echoes" checkbox on the perk frame itself and the "Auto-show
-- echo choices" checkbox on the native Perks & Visual options panel both
-- drive this same setting, so either one actually works.
local function IsAutoShowEchoesEnabled()
    return ProjectEbonholdOptionsService and ProjectEbonholdOptionsService:GetSetting("autoShowEchoes")
end

-- "Keep echoes visible when leveling up" on the native Perks & Visual panel.
-- When it is off, a reveal drops the full-size "Select an Echo" prompt and
-- leaves only the small Show/Hide toggle on screen, so the cards stay one
-- click away without anything popping over the player's screen.
local function IsEchoesVisibleOnLevelUpEnabled()
    return ProjectEbonholdOptionsService and ProjectEbonholdOptionsService:GetSetting("echoesVisibleOnLevelUp")
end

local autoClickDeferred = CreateFrame("Frame")
autoClickDeferred:Hide()
autoClickDeferred:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    self:Hide()
    if chooseButton and chooseButton:IsShown() then
        chooseButton:Click()
    end
end)

-- Capped at 100%: chooseButton/hideButton are anchored below perkMainFrame
-- with fixed pixel offsets, so scaling the compound UI up risks pushing them
-- off the bottom of the screen (a stale/corrupted saved value above 1.0 did
-- exactly that). Scaling down is safe, so the slider only ever shrinks it.
local function GetPerkUIScale()
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    local scale = ProjectEbonholdDB.perkUIScale or 1.0
    return math.max(0.5, math.min(1.0, scale))
end

local function ApplyPerkUIScale(scale)
    ProjectEbonholdDB = ProjectEbonholdDB or {}
    ProjectEbonholdDB.perkUIScale = scale
    if perkMainFrame then
        perkMainFrame:SetScale(scale)
    end
    if chooseButton then
        chooseButton:SetScale(scale)
    end
end

local qualityInfo = {
    -- rim = the card's frame and glow; text = the name on the card (the plain blue and purple are too dark on it)
    [0] = { name = "Common", color = { 1, 1, 1 }, border = 0, rim = { 0.72, 0.70, 0.66 } },
    [1] = { name = "Uncommon", color = { 0.1, 1.0, 0.1 }, border = 1, rim = { 0.1, 1.0, 0.1 } },
    [2] = { name = "Rare", color = { 0.0, 0.4, 1.0 }, border = 2, rim = { 0.15, 0.5, 1.0 }, text = { 0.3, 0.59, 1.0 } },
    [3] = { name = "Epic", color = { 0.6, 0.2, 1.0 }, border = 3, rim = { 0.6, 0.2, 1.0 }, text = { 0.74, 0.49, 1.0 } },
    [4] = { name = "Legendary", color = { 1.0, 0.5, 0.0 }, border = 4, rim = { 1.0, 0.5, 0.0 } }
}


local texCoords = {
    { 0.062500, 0.476562, 0.070312, 0.492188 },
    { 0.468750, 0.898438, 0.054688, 0.515625 },
    { 0.117188, 0.484375, 0.484375, 0.898438 },
    { 0.484375, 0.960938, 0.460938, 0.898438 }
}

local _emptyTable = {} -- shared sentinel; never written to

-- An Orb of Lost Memories offer is final as far as the RUN's budget goes: the server refuses
-- the run's reroll, banish and freeze on it (PerksHandler::OnRerollRequested / BanishPerkForRun
-- / FreezePerkSlot). Reporting zero available here makes those buttons render exactly as they do
-- when the run has none left, so nothing extra had to be taught to the widgets. The Reroll button
-- is the exception: it stays live on an orb offer and spends one more orb instead - see
-- RefreshRerollButton.
local function IsOrbOfferPending()
    local orb = ProjectEbonhold.OrbService
    return orb and orb.IsOfferPending and orb.IsOfferPending() or false
end

-- Every path that reveals the Reroll button goes through this. It is revealed from half a dozen
-- places in this file, and RefreshRerollButton is what decides what it says there.
local function ShowRerollButton()
    if not rerollButton then return end
    rerollButton:Show()
end

local function GetRerollInfo()
    if IsOrbOfferPending() then return 0, 0 end
    local runData = ProjectEbonhold.PlayerRunService and ProjectEbonhold.PlayerRunService.GetCurrentData() or _emptyTable
    local usedRerolls = runData.usedRerolls or 0
    local totalRerolls = runData.totalRerolls or 0
    local availableRerolls = math.max(0, totalRerolls - usedRerolls)
    return availableRerolls, totalRerolls
end

local function GetBanishInfo()
    if IsOrbOfferPending() then return 0 end
    if not ProjectEbonhold.Constants or not ProjectEbonhold.Constants.ENABLE_BANISH_SYSTEM then
        return 0
    end
    local runData = ProjectEbonhold.PlayerRunService and ProjectEbonhold.PlayerRunService.GetCurrentData() or _emptyTable
    return runData.remainingBanishes or 0
end

local function GetFreezeInfo()
    if IsOrbOfferPending() then return 0, 0 end
    local runData = ProjectEbonhold.PlayerRunService and ProjectEbonhold.PlayerRunService.GetCurrentData() or _emptyTable
    local usedFreezes = runData.usedFreezes or 0
    local totalFreezes = runData.totalFreezes or 0
    local availableFreezes = math.max(0, totalFreezes - usedFreezes)
    return availableFreezes, totalFreezes
end

-- Reroll and Hide/Show are plates of the same stone and rim as the cards (classic design only, the
-- transparent one keeps its flat backdrop). The art is grey and painted here, so one file serves every
-- colour. Stock textures of the button are cleared: stone, rim and label lift together on hover.
local PLATE_ART = "Interface\\AddOns\\ProjectEbonhold\\assets\\echo_plate_"
local PLATE_LIFT = 2
local HIDE_PLATE, HIDE_PLATE_HOT = { 0.50, 0.47, 0.43 }, { 0.95, 0.76, 0.32 }

local function PlateLift(btn, y)
    btn._plateStock:ClearAllPoints()
    btn._plateStock:SetPoint("CENTER", btn, "CENTER", 0, y)
end

local function PaintPlate(btn, color, state)
    local stock, rim, glow = btn._plateStock, btn._plateRim, btn._plateGlow
    if state == "off" then
        stock:SetVertexColor(0.30, 0.30, 0.30)
        rim:SetVertexColor(0.42, 0.42, 0.42, 0.8)
        glow:Hide()
        PlateLift(btn, 0)
        return
    end
    local hot = state == "hover"
    local k = hot and 1 or 0.72
    stock:SetVertexColor(color[1] * k, color[2] * k, color[3] * k)
    -- The rim is the same colour pulled towards white, or it melts into the stone
    local w = hot and 0.45 or 0.25
    rim:SetVertexColor(color[1] + (1 - color[1]) * w, color[2] + (1 - color[2]) * w, color[3] + (1 - color[3]) * w,
        hot and 1 or 0.85)
    glow:SetVertexColor(color[1], color[2], color[3], 0.75)
    if hot then glow:Show() else glow:Hide() end
    PlateLift(btn, hot and PLATE_LIFT or 0)
end

local function MakePlate(btn, width, height, fontSize)
    for _, t in ipairs({ btn:GetNormalTexture(), btn:GetPushedTexture(),
                         btn:GetHighlightTexture(), btn:GetDisabledTexture() }) do
        t:Hide()
        t:SetTexture(nil)
    end
    btn:SetSize(width, height)

    local glow = btn:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
    glow:SetSize(width + 70, height + 56)
    glow:Hide()
    btn._plateGlow = glow

    local stock = btn:CreateTexture(nil, "BORDER")
    stock:SetTexture(PLATE_ART .. "stock")
    stock:SetSize(width, height)
    btn._plateStock = stock

    local rim = btn:CreateTexture(nil, "ARTWORK")
    rim:SetTexture(PLATE_ART .. "rim")
    rim:SetAllPoints(stock)
    btn._plateRim = rim

    btn.text:SetFont("Fonts\\FRIZQT__.TTF", fontSize)
    btn.text:SetShadowColor(0, 0, 0, 1)
    btn.text:SetShadowOffset(1, -1)
    btn.text:ClearAllPoints()
    btn.text:SetPoint("CENTER", stock, "CENTER", 0, 0)
    PlateLift(btn, 0)

    btn:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then PlateLift(self, -1) end
    end)
    btn:SetScript("OnMouseUp", function(self)
        PlateLift(self, (self:IsEnabled() and GetMouseFocus() == self) and PLATE_LIFT or 0)
    end)
end

-- The Reroll button has TWO modes, told apart by who pays. On an ordinary draw it spends the
-- run's reroll budget. On an Orb of Lost Memories offer that budget is refused server-side and
-- one more orb buys the redraw instead (PerksHandler::OnOrbRerollRequested), so a player who
-- likes none of the three can say so from the choice screen rather than walking back to the
-- journal, arming the bubble and picking an echo again.
--
-- Mauve rather than red, and the orb count in the label, because the button sits where the free
-- reroll normally sits: a player clicking out of habit must be able to see they are spending a
-- charge. There is no confirmation popup on purpose - the whole point is one click.
local REROLL_SKIN = {
    run = {
        base   = { 0.22, 0.06, 0.06, 0.95 },
        hover  = { 0.50, 0.12, 0.12, 0.98 },
        border = { 0.90, 0.20, 0.20, 1 },
        glow   = { 0.50, 0.14, 0.14, 0.40 },
        -- nil = the button art in its own colours, which are already red.
        tex    = nil,
        plate  = { 0.80, 0.20, 0.14 },
    },
    -- Matches the orb bubble's mauve glow in orb_of_lost_memories.lua, so the button reads as
    -- part of the same currency.
    orb = {
        base   = { 0.16, 0.07, 0.24, 0.95 },
        hover  = { 0.34, 0.14, 0.50, 0.98 },
        border = { 0.72, 0.36, 1.00, 1 },
        glow   = { 0.45, 0.20, 0.70, 0.45 },
        -- The classic design paints the button with 128redbutton9sliced and has no backdrop at
        -- all, so the colours above are a no-op there and the button stayed red in orb mode.
        -- Tinting the red art mauve directly would only darken it (a vertex colour multiplies,
        -- it cannot add the blue the source has none of), hence desaturate first.
        tex    = { 0.72, 0.42, 1.00 },
        plate  = { 0.58, 0.28, 0.92 },
    },
}

local function ApplyRerollSkin(hovered)
    if not rerollButton then return end

    local skin = rerollButton._orbMode and REROLL_SKIN.orb or REROLL_SKIN.run

    if rerollButton._plateStock then
        if rerollButton:IsEnabled() then
            PaintPlate(rerollButton, skin.plate, hovered and "hover" or "rest")
        else
            PaintPlate(rerollButton, skin.plate, "off")
        end
        return
    end

    -- Backdrop: the transparent design only. Classic has none, and the texture tint below is
    -- what carries the mode there.
    if rerollButton.SetBackdropColor then
        local fill = hovered and skin.hover or skin.base
        rerollButton:SetBackdropColor(fill[1], fill[2], fill[3], fill[4])
        if hovered then
            rerollButton:SetBackdropBorderColor(skin.border[1], skin.border[2], skin.border[3], skin.border[4])
        else
            rerollButton:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end
    if rerollButton._rerollGlow then
        rerollButton._rerollGlow:SetVertexColor(skin.glow[1], skin.glow[2], skin.glow[3], skin.glow[4])
    end

    -- Harmless under the transparent design: there the four textures are hidden and cleared.
    local tint = skin.tex
    for _, t in ipairs({ rerollButton:GetNormalTexture(), rerollButton:GetPushedTexture(),
                         rerollButton:GetHighlightTexture(), rerollButton:GetDisabledTexture() }) do
        t:SetDesaturated(tint and true or false)
        if tint then
            t:SetVertexColor(tint[1], tint[2], tint[3])
        else
            t:SetVertexColor(1, 1, 1)
        end
    end
end

local function GetOrbCharges()
    local orb = ProjectEbonhold.OrbService
    return (orb and orb.GetCharges and orb.GetCharges()) or 0
end

-- The single place the button's label, colour and enabled state are decided. Six copies of this
-- block used to live at every site that reveals the cards, and they drifted; visibility is still
-- ShowRerollButton's, because some of those sites paint the button while the cards are hidden.
local function RefreshRerollButton()
    if not rerollButton or not rerollButton.text then return end

    local count
    if IsOrbOfferPending() then
        rerollButton._orbMode = true
        count = GetOrbCharges()
        rerollButton.text:SetText("Use Orbs (" .. count .. ")")
    else
        rerollButton._orbMode = false
        count = GetRerollInfo()
        rerollButton.text:SetText("Reroll (" .. count .. ")")
    end

    if count > 0 then
        rerollButton.text:SetTextColor(1, 1, 1)
        rerollButton:Enable()
    else
        rerollButton.text:SetTextColor(0.5, 0.5, 0.5)
        rerollButton:Disable()
    end

    -- The count changes under a cursor that is still on the button
    ApplyRerollSkin(GetMouseFocus() == rerollButton)
end

local function GetCardFrameByIndex(cardIndex)
    if not cardIndex or cardIndex < 1 or cardIndex > 4 then return nil end
    for _, f in ipairs(perkFramePool) do
        if f.inUse and f.perkIndex == cardIndex - 1 then return f end
    end

    return nil
end


-- ── First-prompt guided tour ─────────────────────────────────────────────────
-- Shown once, the first time the choice cards are actually revealed (not while
-- they still sit behind the "Choose an Echo" button). Built on the shared
-- GlowBox tour factory (modules/guidedTour). Hiding the cards mid-tour pauses
-- it without marking it seen -- it resumes from step 1 on the next reveal.

-- The visible card body differs by skin: the transparent design shows
-- backdropFrame (the card frame's top 80px are invisible), while the classic
-- design HIDES backdropFrame and paints the whole frame with the bg texture --
-- so backdropFrame alone fails the tour's IsShown zone check there.
function GetCardBody(f)
    if f.backdropFrame and f.backdropFrame:IsShown() then return f.backdropFrame end
    if f.body then return f.body end -- face-down placeholder of the souvenir stage
    return f
end

-- Leftmost-to-rightmost visible card, so the highlight spans the whole draw
local function GetCardsZone()
    local first, last
    for _, f in ipairs(perkFramePool) do
        if f.inUse and f:IsShown() then
            if not first or f.perkIndex < first.perkIndex then first = f end
            if not last or f.perkIndex > last.perkIndex then last = f end
        end
    end
    if not first then return nil end
    return GetCardBody(first), GetCardBody(last)
end

-- Prefer a card actually wearing the golden wishlist glow; fall back to the
-- whole draw (on the very first prompt no wishlist is active yet)
local function GetWishlistZone()
    for _, f in ipairs(perkFramePool) do
        if f.inUse and f:IsShown() and f.loadoutOverlay and f.loadoutOverlay:IsShown() then
            return GetCardBody(f)
        end
    end
    return GetCardsZone()
end

local perkTour = ProjectEbonhold.GuidedTour.Create({
    parent = function() return perkMainFrame end,
    dbKey = "seenPerkPromptTour",
    steps = function()
        return {
            {
                title = "Echo Choices",
                text = "Every level up during a run offers a draw of echoes: " ..
                    "temporary powers that last until the run ends. Click " ..
                    "a |cffffd700card|r to claim it; the card's color shows its " ..
                    "quality.\n\n|cffffd700Freeze|r holds a card for your next " ..
                    "draw, |cffffd700Banish|r removes it from this run's pool.",
                zone = GetCardsZone,
                boxAnchor = { "CENTER", "CENTER", 0, 0 },
            },
            {
                title = "Reroll",
                text = "Not happy with the draw? |cffffd700Reroll|r swaps every " ..
                    "card for a fresh set. The number shows how many rerolls " ..
                    "you have left this run.",
                zone = function() return rerollButton end,
                boxAnchor = { "LEFT", "RIGHT", 14, 0 },
            },
            {
                title = "Wishlist Highlights",
                text = "Playing toward a |cffa080e0wishlist|r or a " ..
                    "|cff60a0e0build|r (Echo Journal, Loadouts menu)? Cards " ..
                    "that belong to it wear a |cffffd700golden glow and " ..
                    "star|r. Pick those to grow into your dream build.",
                zone = GetWishlistZone,
                boxAnchor = { "CENTER", "CENTER", 0, 0 },
            },
        }
    end,
})

local function ApplyRankGlows()
    for _, f in ipairs(perkFramePool) do
        if f.inUse and f.backdropFrame and f.backdropFrame.SetBackdropBorderColor then
            f.backdropFrame:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end
end
local function _FUGAZI_WAS_HERE_deprecated() end

local FadeFrame, CancelFade
do
    local fadingFrames = {}
    local fadeFrame = CreateFrame("Frame")
    fadeFrame:Hide()

    function CancelFade(frame)
        if frame and fadingFrames[frame] then
            fadingFrames[frame] = nil
        end
    end

    fadeFrame:SetScript("OnUpdate", function(self, elapsed)
        if not UIParent:IsShown() then return end
        elapsed = math.min(elapsed, 0.1)
        local hasFades = false
        for frame, fadeInfo in pairs(fadingFrames) do
            hasFades = true
            fadeInfo.timer = fadeInfo.timer + elapsed

            if fadeInfo.timer < 0 then
                frame:SetAlpha(fadeInfo.startAlpha)
            elseif fadeInfo.timer >= fadeInfo.duration then
                frame:SetAlpha(fadeInfo.endAlpha)
                if fadeInfo.finishedFunc then
                    fadeInfo.finishedFunc(frame)
                end
                fadingFrames[frame] = nil
            else
                local progress = fadeInfo.timer / fadeInfo.duration
                local alpha = fadeInfo.startAlpha + (fadeInfo.endAlpha - fadeInfo.startAlpha) * progress
                frame:SetAlpha(alpha)
            end
        end
        if not hasFades then
            self:Hide()
        end
    end)

    function FadeFrame(frame, duration, startAlpha, endAlpha, delay, onFinished)
        if not frame then return end
        if delay and delay > 0 then
            fadingFrames[frame] = {
                duration = duration,
                startAlpha = startAlpha,
                endAlpha = endAlpha,
                timer = -delay,
                finishedFunc = onFinished
            }
        else
            fadingFrames[frame] = {
                duration = duration,
                startAlpha = startAlpha,
                endAlpha = endAlpha,
                timer = 0,
                finishedFunc = onFinished
            }
            frame:SetAlpha(startAlpha)
        end
        frame:Show()
        fadeFrame:Show()
    end
end

-- ── Tarot cards: hover, deal, turn over, pick ──────────────────────────────
-- The choice cards, design picked by the owner on a mock-up (2026-11-04). All of it runs from one
-- OnUpdate (CardFx.Update, on the main frame), only while the choice is on screen.
-- The 3.3.5 client can't tilt a frame or turn text, so nothing here does: a card rises, grows, glows and
-- fades, and "turning over" is the back narrowing, the face widening, then the text fading in.
local CARD_FADE_DURATION = 0.2 -- the face-down cards of the souvenir stage still just fade in

local CardFx = {
    ICON_SIZE = 72,
    ICON_Y = -64, -- centre of the icon, from the top of the card
}
do
    local ASSETS = "Interface\\AddOns\\ProjectEbonhold\\assets\\"
    local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"

    local HOVER_SEC, LIFT_Y, LIFT_SCALE, DIM_ALPHA, ICON_GROW = 0.13, 28, 0.08, 0.55, 6
    local GLOW_REST, GLOW_HOT = 0.12, 0.9
    -- The light on the card's edge, in front of it: at rest a card above Common breathes between these
    -- two strengths, by rarity. Under the mouse it is on full for all of them.
    local EDGE_BREATH = {
        [1] = { 0.30, 0.65 },
        [2] = { 0.40, 0.80 },
        [3] = { 0.55, 1.00 },
        [4] = { 0.55, 1.00 },
    }
    local EDGE_BREATH_RATE = 2 * math.pi / 2.4 -- one breath every 2.4 s
    local TIP_DELAY = 0.45
    local DEAL_SEC, DEAL_DROP, DEAL_STAGGER = 0.32, 330, 0.11
    local FLIP_START, FLIP_MID, FLIP_END, TEXT_END = 0.2, 0.33, 0.46, 0.64
    local SHINE_SEC = 0.5
    local EMBER_COUNT, EMBER_REST_COUNT, EMBER_RISE = 10, 5, 230
    local EMBER_LIFE_REST, EMBER_LIFE_HOT = 2.4, 1.5
    local PICK_SEC, PICK_RISE, PICK_SCALE, BURN_SEC, BURN_DROP = 0.5, 60, 1.16, 0.36, 46
    local PICK_SAFETY_SEC = 1.5

    -- The art window: the part of the rarity smoke and ring textures kept on the card. Textures are not
    -- clipped by their frame in 3.3.5, so the window is cut with texture coordinates. At this scale
    -- (360 px for the whole texture) the ring goes around a 72 px icon.
    local ART_W, ART_H = 210, 130
    local ART_L, ART_R, ART_T, ART_B = 0.2083, 0.7917, 0.3528, 0.7139

    function CardFx.PlaceArt(tex, card)
        tex:SetSize(ART_W, ART_H)
        tex:SetPoint("TOP", card, "TOP", 0, -3)
        tex:SetTexCoord(ART_L, ART_R, ART_T, ART_B)
    end

    -- The colour around the icon turns: two layers of their own, over the rarity smoke and under the icon.
    -- The smoke itself can't turn, it is cut by the art window and would swing out of the card. These stay
    -- inside the window at any angle (122 px wide, icon centre 64 px from the top of the card).
    local SWIRL_SIZE, SWIRL_REST, SWIRL_HOT = 122, 0.6, 1
    local function SwirlLayer(iconFrame, art, level, seconds, degrees)
        local t = iconFrame:CreateTexture(nil, "BACKGROUND", nil, level)
        t:SetTexture(ASSETS .. art)
        t:SetBlendMode("ADD")
        t:SetSize(SWIRL_SIZE, SWIRL_SIZE)
        t:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        t:SetAlpha(SWIRL_REST)
        t.spin = MakeSpin(t, seconds, degrees)
        return t
    end

    function CardFx.BuildSwirl(frame, iconFrame)
        frame.swirl = SwirlLayer(iconFrame, "echo_card_swirl", 1, 16, -360)
        frame.sparks = SwirlLayer(iconFrame, "echo_card_sparks", 2, 26, 360)
    end

    function CardFx.BuildBody(frame, visual)
        local glow = visual:CreateTexture(nil, "BACKGROUND", nil, -2)
        glow:SetTexture(GLOW_TEX)
        glow:SetBlendMode("ADD")
        glow:SetSize(CARD_W + 104, CARD_H + 104)
        glow:SetPoint("CENTER", visual, "CENTER", 0, 0)
        glow:SetAlpha(GLOW_REST)
        frame.cardGlow = glow
        frame._fxBreathPhase = math.random() * 2.4 -- or the whole row would breathe as one

        local bg = visual:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(ASSETS .. "echo_card_stock")
        bg:SetSize(CARD_W, CARD_H)
        bg:SetPoint("CENTER", visual, "CENTER", 0, 0)
        frame.bg = bg

        local rim = visual:CreateTexture(nil, "BORDER")
        rim:SetTexture(ASSETS .. "echo_card_rim")
        rim:SetSize(CARD_W, CARD_H)
        rim:SetPoint("CENTER", visual, "CENTER", 0, 0)
        frame.cardRim = rim

        local back = visual:CreateTexture(nil, "BORDER", nil, 2)
        back:SetTexture(ASSETS .. "echo_card_back")
        back:SetSize(CARD_W, CARD_H)
        back:SetPoint("CENTER", visual, "CENTER", 0, 0)
        back:Hide()
        frame.cardBack = back

        -- The back lets the rarity show through, a small promise before the card turns over
        local backSmoke = visual:CreateTexture(nil, "BORDER", nil, 3)
        backSmoke:SetSize(CARD_W, CARD_W)
        backSmoke:SetPoint("CENTER", visual, "CENTER", 0, 0)
        backSmoke:SetTexCoord(0.14, 0.86, 0.14, 0.86)
        backSmoke:SetBlendMode("ADD")
        backSmoke:Hide()
        frame.cardBackSmoke = backSmoke
    end

    function CardFx.BuildOverlay(frame, visual, content)
        -- On the content, so it stays off until the card has turned over; on the rim, so it grows with the face
        local edge = content:CreateTexture(nil, "OVERLAY")
        edge:SetTexture(ASSETS .. "echo_card_edge")
        edge:SetBlendMode("ADD")
        edge:SetAllPoints(frame.cardRim)
        edge:SetAlpha(0)
        frame.cardEdge = edge

        local flag = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        flag:SetFont("Fonts\\FRIZQT__.TTF", 11)
        flag:SetPoint("TOPLEFT", visual, "TOPLEFT", 12, -10)
        flag:SetTextColor(0.56, 0.82, 1)
        flag:SetText("Frozen")
        flag:Hide()
        frame.frozenFlag = flag

        local shine = content:CreateTexture(nil, "OVERLAY")
        shine:SetTexture(ASSETS .. "echo_card_shine")
        shine:SetBlendMode("ADD")
        shine:SetAllPoints(frame.cardRim) -- the face, which grows on hover; `visual` does not
        shine:Hide()
        frame.cardShine = shine

        frame.embers = {}
        for i = 1, EMBER_COUNT do
            local e = content:CreateTexture(nil, "OVERLAY")
            e:SetTexture(GLOW_TEX)
            e:SetBlendMode("ADD")
            e:SetSize(9, 9)
            e:Hide()
            e.x = 12 + ((i * 37) % 84) / 100 * (CARD_W - 24)
            e.t = (i * 0.37) % 1
            frame.embers[i] = e
        end
    end

    -- Paints the frame, glow and embers with the rarity, or everything in ice for a frozen card
    function CardFx.Paint(f, frozen)
        local qd = f._qualityData or qualityInfo[0]
        local rim = qd.rim or qd.color
        local r, g, b = rim[1], rim[2], rim[3]
        if frozen then r, g, b = 0.44, 0.77, 1 end
        if f.cardRim then f.cardRim:SetVertexColor(r, g, b) end
        if f.cardGlow then f.cardGlow:SetVertexColor(r, g, b) end
        if f.cardEdge then f.cardEdge:SetVertexColor(r, g, b) end
        if f.swirl then
            f.swirl:SetVertexColor(r, g, b)
            f.sparks:SetVertexColor(r, g, b)
        end
        if f.bg then
            if frozen then f.bg:SetVertexColor(0.55, 0.78, 1) else f.bg:SetVertexColor(1, 1, 1) end
        end
        if f.frozenFlag then
            if frozen then f.frozenFlag:Show() else f.frozenFlag:Hide() end
        end
        for _, e in ipairs(f.embers or _emptyTable) do e:SetVertexColor(r, g, b) end
        if f.cardBackSmoke then
            f.cardBackSmoke:SetTexture(ASSETS .. "perk_quality_" .. qd.border)
        end
    end

    function CardFx.SetSelectHint(f, label)
        if not f.selectHint then return end
        if label then
            f.selectHint:SetText(label)
            f.selectHint:Show()
        else
            f.selectHint:Hide()
        end
    end

    local function SetFrontWidth(f, w)
        f._fxFace = nil -- the flip owns the width, Step gives the face its size back afterwards
        f.bg:SetWidth(w)
        f.cardRim:SetWidth(w)
    end

    local function SetBack(f, w)
        if w then
            f.cardBack:SetWidth(w)
            f.cardBackSmoke:SetWidth(w)
            f.cardBack:Show()
            f.cardBackSmoke:Show()
        else
            f.cardBack:Hide()
            f.cardBackSmoke:Hide()
        end
    end

    local function FinishEntrance(f)
        f._fxT, f._fxFlipOnly = nil, nil
        SetBack(f, nil)
        SetFrontWidth(f, CARD_W)
        f.content:SetAlpha(1)
    end

    -- Deals the card from the bottom of the row, face down, and turns it over
    function CardFx.Start(f, delay)
        if not f.visual then return end
        f._fxT = -(delay or 0)
        f._fxFlipOnly = nil
        f._fxDX = -(f._cardX or 0)
        f._fxHiddenUntil = nil
        f.visual:SetAlpha(0)
    end

    -- Only turns over, in place: the card that replaces a banished one
    function CardFx.StartFlip(f)
        if not f.visual or f._fxNoFlip then return end
        f._fxT = FLIP_START
        f._fxFlipOnly = true
        f._fxDX = 0
    end

    function CardFx.Stagger(k)
        return k * DEAL_STAGGER
    end

    -- The tooltip opens after a short wait and on the outer side of the card, so that it doesn't cover
    -- the card the player is reading; the card in the middle opens to the right.
    function CardFx.ShowTooltip(self)
        local qd = self._qualityData or qualityInfo[0]
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        if (self._cardX or 0) < 0 then
            GameTooltip:SetPoint("RIGHT", self, "LEFT", -16, 0)
        else
            GameTooltip:SetPoint("LEFT", self, "RIGHT", 16, 0)
        end
        GameTooltip:ClearLines()
        local sName = GetSpellInfo(self._spellId or 0)
        GameTooltip:AddLine(sName or ("Spell " .. tostring(self._spellId)), qd.color[1], qd.color[2], qd.color[3])
        GameTooltip:AddLine(qd.name, 0.5, 0.5, 0.5)
        if self._perkData and self._perkData.isGuaranteed then
            -- The choice itself is spelled out under the cards (memoryHint)
            GameTooltip:AddLine("Souvenir from your previous build", 1, 0.82, 0.1)
        end
        local svcRule = ProjectEbonhold.PerkService
            and ProjectEbonhold.PerkService.GetActiveEchoLoadoutRule
        local rule = svcRule and svcRule(self._spellId)
        if rule == "avoid" then
            GameTooltip:AddLine("Your build refuses this echo", 1, 0.25, 0.25)
            GameTooltip:AddLine("It is never taken for you. Take it yourself if you changed your mind.", 0.8, 0.6, 0.6, true)
        elseif rule == "want" then
            GameTooltip:AddLine("Wanted by your build", 0.1, 1, 0.1)
        end
        local st = self._stacks or 1
        local ms = self._maxStacks or 1
        if st > 1 then
            GameTooltip:AddLine("Stacks: " .. st .. "/" .. ms, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        local description = utils.GetSpellDescription(self._spellId, 500, st)
        GameTooltip:AddLine(description, 1, 0.82, 0, true)
        -- stat echoes have their stat line instead (owner 2026-10-23)
        local okStats, stats = pcall(GetEchoStats, self._spellId, description)
        if (self._ownedCount or 0) >= 1 and not (okStats and stats and next(stats)) then
            pcall(AddEchoStackLine, GameTooltip, self._spellId, self._ownedCount)
        end
        AddEchoStatLines(GameTooltip, self._spellId, description)
        GameTooltip:Show()
    end

    local function StepEmbers(f, dt, isHot, shown)
        local active = 0
        if shown then
            if isHot then active = EMBER_COUNT
            elseif f._fxQuality == 3 then active = EMBER_REST_COUNT end
        end
        if active == 0 and not f._fxEmbersOn then return end
        f._fxEmbersOn = active > 0
        local life = isHot and EMBER_LIFE_HOT or EMBER_LIFE_REST
        for i, e in ipairs(f.embers) do
            if i <= active then
                e.t = (e.t + dt / life) % 1
                local a = e.t < 0.15 and (e.t / 0.15) or ((1 - e.t) / 0.85)
                e:SetPoint("CENTER", f.visual, "BOTTOMLEFT", e.x, 40 + e.t * EMBER_RISE)
                e:SetAlpha(a * 0.9)
                e:Show()
            else
                e:Hide()
            end
        end
    end

    local function Step(f, dt, hot, now)
        local isHot = f == hot

        -- Hover: rises and grows, the others step back
        local lift = f._fxLift or 0
        local target = isHot and 1 or 0
        if lift ~= target then
            if target == 1 and lift == 0 and not f._fxT then
                f._fxShineT = 0
                f.cardShine:Show()
            end
            if lift < target then lift = math.min(target, lift + dt / HOVER_SEC)
            else lift = math.max(target, lift - dt / HOVER_SEC) end
            f._fxLift = lift
        end
        local ease = lift * (2 - lift)

        local dim = f._fxDim or 1
        local dimTarget = (hot and not isHot) and DIM_ALPHA or 1
        if dim ~= dimTarget then
            local step = (1 - DIM_ALPHA) * dt / HOVER_SEC
            if dim < dimTarget then dim = math.min(dimTarget, dim + step)
            else dim = math.max(dimTarget, dim - step) end
            f._fxDim = dim
        end

        -- Entrance
        local ox, oy, alpha = 0, 0, 1
        local t = f._fxT
        if t then
            t = t + dt
            f._fxT = t
            if t < 0 then
                alpha = 0
                if not f._fxNoFlip then
                    SetFrontWidth(f, 1)
                    SetBack(f, CARD_W)
                    f.content:SetAlpha(0)
                end
            else
                if not f._fxFlipOnly then
                    local p = math.min(t / DEAL_SEC, 1)
                    local inv = 1 - p
                    local e = inv * inv * inv
                    ox, oy = (f._fxDX or 0) * e, -DEAL_DROP * e
                    alpha = math.min(t / 0.1, 1)
                end
                if f._fxNoFlip then
                    if t >= DEAL_SEC then FinishEntrance(f) end
                elseif t >= TEXT_END then
                    FinishEntrance(f)
                else
                    if t < FLIP_START then
                        SetBack(f, CARD_W)
                        SetFrontWidth(f, 1)
                    elseif t < FLIP_MID then
                        SetBack(f, math.max(1, CARD_W * (1 - (t - FLIP_START) / (FLIP_MID - FLIP_START))))
                        SetFrontWidth(f, 1)
                    else
                        SetBack(f, nil)
                        SetFrontWidth(f, math.max(1, CARD_W * math.min(1, (t - FLIP_MID) / (FLIP_END - FLIP_MID))))
                    end
                    f.content:SetAlpha(t < FLIP_END and 0 or ((t - FLIP_END) / (TEXT_END - FLIP_END)))
                end
            end
        end

        -- A picked card has been handed over to its ghost (CardFx.PlayPick)
        if f._fxHiddenUntil then
            if now < f._fxHiddenUntil then alpha = 0 else f._fxHiddenUntil = nil end
        end

        -- Only the card's face grows, never a frame holding text: under SetScale the client lays a font
        -- string out again at each step, so the description changes size and breaks its lines elsewhere.
        -- Whole pixels for the same reason, text on a fractional position shimmers as it moves.
        local x, y = math.floor(ox + 0.5), math.floor(oy + LIFT_Y * ease + 0.5)
        if x ~= f._fxX or y ~= f._fxY then
            f._fxX, f._fxY = x, y
            f.visual:SetPoint("CENTER", f, "CENTER", x, y)
        end
        if not f._fxT and ease ~= f._fxFace then
            f._fxFace = ease
            local scale = 1 + LIFT_SCALE * ease
            f.bg:SetSize(CARD_W * scale, CARD_H * scale)
            f.cardRim:SetSize(CARD_W * scale, CARD_H * scale)
            if f._fxNoFlip then f.backdropFrame:SetSize(CARD_W * scale, CARD_H * scale) end
        end
        f.visual:SetAlpha(alpha * dim)
        -- An animation stops when its frame is hidden, and a card is hidden between two draws
        if not f.swirl.spin:IsPlaying() then
            f.swirl.spin:Play()
            f.sparks.spin:Play()
        end

        if ease ~= f._fxEase then
            f._fxEase = ease
            f.cardGlow:SetAlpha(GLOW_REST + (GLOW_HOT - GLOW_REST) * ease)
            f.swirl:SetAlpha(SWIRL_REST + (SWIRL_HOT - SWIRL_REST) * ease)
            f.sparks:SetAlpha(SWIRL_REST + (SWIRL_HOT - SWIRL_REST) * ease)
            local size = CardFx.ICON_SIZE + ICON_GROW * ease
            f.icon:SetSize(size, size)
            -- Alpha, not Show: the Update*Buttons polls own Show and Hide
            f.freezeCardButton:SetAlpha(ease)
            f.banishCardButton:SetAlpha(ease)
            if f.selectHint then f.selectHint:SetAlpha(1 - ease) end
        end

        local edgeRest = 0
        local breath = EDGE_BREATH[f._fxQuality]
        if breath then
            local wave = 0.5 + 0.5 * math.sin((now + f._fxBreathPhase) * EDGE_BREATH_RATE)
            edgeRest = breath[1] + (breath[2] - breath[1]) * wave
        end
        local edgeAlpha = edgeRest + (1 - edgeRest) * ease
        if edgeAlpha ~= f._fxEdgeAlpha then
            f._fxEdgeAlpha = edgeAlpha
            f.cardEdge:SetAlpha(edgeAlpha)
        end

        -- The reflection crosses the card once per hover
        local s = f._fxShineT
        if s then
            s = s + dt / SHINE_SEC
            if s >= 1 then
                f._fxShineT = nil
                f.cardShine:Hide()
            else
                f._fxShineT = s
                local l = s * 0.6
                f.cardShine:SetTexCoord(l, l + 0.4, 0, 1)
            end
        end

        StepEmbers(f, dt, isHot, not f._fxT and alpha > 0)
    end

    local tipFocus, tipCard, tipWait = nil, nil, 0

    function CardFx.Update(elapsed)
        local dt = math.min(elapsed, 0.1)

        -- Hover comes from the mouse focus and not from OnEnter / OnLeave: moving onto Freeze or Banish
        -- fires the card's OnLeave though the cursor is still on the card. `_card` is set on the card's
        -- frame, its Select cover, its two buttons and its spec badge.
        local focus = GetMouseFocus()
        local hot = focus and focus._card or nil
        if hot and (isSelecting or not hot.inUse or not hot:IsShown()) then hot = nil end

        if focus ~= tipFocus then
            if tipCard and GameTooltip:IsOwned(tipCard) then GameTooltip:Hide() end
            tipFocus, tipCard, tipWait = focus, nil, 0
        end
        if hot and not tipCard and (focus == hot or focus == hot.selectButton) then
            tipWait = tipWait + dt
            if tipWait >= TIP_DELAY then
                tipCard = hot
                CardFx.ShowTooltip(hot)
            end
        end

        local now = GetTime()
        for _, f in ipairs(perkFramePool) do
            if f.inUse and f.visual and f:IsShown() then
                Step(f, dt, hot, now)
            end
        end
    end

    -- ── The pick ────────────────────────────────────────────────────────────
    -- The server's answer hides the row (or brings the next draw) at once, so the animation can't live on
    -- the cards: they hand over to ghosts, plain copies parented to UIParent. The chosen one rises, the
    -- others burn away. Nothing waits for it: the next draw can land while it plays.
    local ghosts = {}
    local ghostTime = 0
    local ghostDriver = CreateFrame("Frame")
    ghostDriver:Hide()

    local function GetGhost(i)
        if ghosts[i] then return ghosts[i] end
        local g = CreateFrame("Frame", nil, UIParent)
        g:SetFrameStrata("DIALOG")
        g:SetFrameLevel(90)
        g:SetSize(CARD_W, CARD_H)
        g:Hide()

        g.glow = g:CreateTexture(nil, "BACKGROUND", nil, -2)
        g.glow:SetTexture(GLOW_TEX)
        g.glow:SetBlendMode("ADD")
        g.glow:SetSize(CARD_W + 104, CARD_H + 104)
        g.glow:SetPoint("CENTER", g, "CENTER", 0, 0)

        g.bg = g:CreateTexture(nil, "BACKGROUND")
        g.bg:SetTexture(ASSETS .. "echo_card_stock")
        g.bg:SetAllPoints(g)

        g.rim = g:CreateTexture(nil, "BORDER")
        g.rim:SetTexture(ASSETS .. "echo_card_rim")
        g.rim:SetAllPoints(g)

        g.smoke = g:CreateTexture(nil, "ARTWORK")
        CardFx.PlaceArt(g.smoke, g)

        g.icon = g:CreateTexture(nil, "ARTWORK", nil, 1)
        g.icon:SetSize(CardFx.ICON_SIZE, CardFx.ICON_SIZE)
        g.icon:SetPoint("CENTER", g, "TOP", 0, CardFx.ICON_Y)

        g.ring = g:CreateTexture(nil, "ARTWORK", nil, 2)
        CardFx.PlaceArt(g.ring, g)

        g.name = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        g.name:SetFont("Fonts\\MORPHEUS.ttf", 20)
        g.name:SetPoint("TOP", g, "TOP", 0, -147)
        g.name:SetWidth(192)
        g.name:SetShadowColor(0, 0, 0, 1)
        g.name:SetShadowOffset(1, -1)

        g.desc = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        g.desc:SetFont("Fonts\\ARIALN.TTF", 13)
        g.desc:SetPoint("TOP", g.name, "BOTTOM", 0, -24)
        g.desc:SetWidth(188)
        g.desc:SetHeight(96)
        g.desc:SetJustifyV("TOP")
        g.desc:SetTextColor(0.87, 0.83, 0.76)

        ghosts[i] = g
        return g
    end

    local function PlaceGhost(g, rise, scale)
        g:SetScale(g.baseScale * scale)
        g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", g.x / scale, (g.y + rise) / scale)
    end

    ghostDriver:SetScript("OnUpdate", function(self, elapsed)
        ghostTime = ghostTime + math.min(elapsed, 0.1)
        local running = false
        for _, g in ipairs(ghosts) do
            if g:IsShown() then
                if g.chosen then
                    local p = math.min(ghostTime / PICK_SEC, 1)
                    local up = 1 - (1 - math.min(p * 2.5, 1)) ^ 3
                    PlaceGhost(g, g.startRise + (PICK_RISE - g.startRise) * up,
                        g.startScale + (PICK_SCALE - g.startScale) * up)
                    g:SetAlpha(p < 0.45 and 1 or (1 - (p - 0.45) / 0.55))
                    g.glow:SetAlpha(1)
                    if p >= 1 then g:Hide() else running = true end
                else
                    local p = math.min(ghostTime / BURN_SEC, 1)
                    PlaceGhost(g, g.startRise * (1 - p) - BURN_DROP * p, g.startScale + (0.95 - g.startScale) * p)
                    g:SetAlpha(g.startAlpha * (1 - p))
                    -- Burns: everything goes from its own colour to embers
                    g.bg:SetVertexColor(1, 1 - 0.55 * p, 1 - 0.85 * p)
                    g.rim:SetVertexColor(g.r + (1 - g.r) * p, g.g + (0.42 - g.g) * p, g.b + (0.08 - g.b) * p)
                    g.glow:SetVertexColor(1, 0.42, 0.08)
                    g.glow:SetAlpha(p)
                    if p >= 1 then g:Hide() else running = true end
                end
            end
        end
        if not running then self:Hide() end
    end)

    function CardFx.PlayPick(chosen)
        local n = 0
        local now = GetTime()
        local baseScale = perkMainFrame:GetScale()
        for _, f in ipairs(perkFramePool) do
            if f.inUse and f.visual and f:IsShown() and f._qualityData then
                n = n + 1
                local g = GetGhost(n)
                local qd = f._qualityData
                local rim = qd.rim or qd.color
                g.chosen = f == chosen
                g.r, g.g, g.b = rim[1], rim[2], rim[3]
                g.bg:SetVertexColor(1, 1, 1)
                g.rim:SetVertexColor(g.r, g.g, g.b)
                g.glow:SetVertexColor(g.r, g.g, g.b)
                g.glow:SetAlpha(0)
                g.smoke:SetTexture(ASSETS .. "perk_quality_" .. qd.border)
                g.ring:SetTexture(ASSETS .. "perk_border_quality_" .. qd.border)
                local _, _, spellIcon = GetSpellInfo(f._spellId or 0)
                SetPortraitToTexture(g.icon, spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
                g.name:SetText(f.nameText:GetText())
                g.name:SetTextColor(unpack(qd.text or qd.color))
                g.desc:SetText(f.descText:GetText())

                local ease = f._fxEase or 0
                g.baseScale = baseScale
                g.startRise, g.startScale = LIFT_Y * ease, 1
                g.startAlpha = f._fxDim or 1
                g.x, g.y = f:GetCenter()
                g:ClearAllPoints()
                PlaceGhost(g, g.startRise, g.startScale)
                g:SetAlpha(g.startAlpha)
                g:Show()

                -- If the answer never comes the card comes back by itself, it is not lost
                f._fxHiddenUntil = now + PICK_SAFETY_SEC
            end
        end
        if n > 0 then
            for i = n + 1, #ghosts do ghosts[i]:Hide() end
            ghostTime = 0
            ghostDriver:Show()
        end
    end
end

-- Remembers where a card belongs so a reveal can put it back there
function PlaceCard(f, x, y)
    f._cardX, f._cardY = x, y
    f:ClearAllPoints()
    f:SetPoint("CENTER", perkMainFrame, "CENTER", x, y)
end

function PlayCardEntrance(f, onDone, delay)
    if not f._cardX then return end
    CancelFade(f)
    f:ClearAllPoints()
    f:SetPoint("CENTER", perkMainFrame, "CENTER", f._cardX, f._cardY)
    if f.visual then
        f:SetAlpha(1)
        f:Show()
        CardFx.Start(f, delay)
        if onDone then onDone(f) end
    else
        FadeFrame(f, CARD_FADE_DURATION, 0, 1, 0, onDone)
    end
end

function PlayCardsEntrance(frames)
    for k, f in ipairs(frames) do
        PlayCardEntrance(f, nil, CardFx.Stagger(k - 1))
    end
end

-- Every card on the table right now: choice frames and face-down placeholders
function CollectVisibleCards()
    local list = {}
    for _, f in ipairs(perkFramePool) do
        if f.inUse and f:IsShown() then table.insert(list, f) end
    end
    return list
end

local function ApplyFreezeVisual(frame)
    if not frame then return end

    if frame.backdropFrame and frame.backdropFrame.SetBackdropColor then
        frame.backdropFrame:SetBackdropColor(0.06, 0.12, 0.28, 0.95)
        frame.backdropFrame:SetBackdropBorderColor(0.3, 0.55, 0.85, 1)
    end
    CardFx.Paint(frame, true)
end

local function ClearFreezeVisual(frame)
    if not frame then return end
    if frame.backdropFrame and frame.backdropFrame.SetBackdropColor then
        frame.backdropFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        frame.backdropFrame:SetBackdropBorderColor(0, 0, 0, 1)
    end
    CardFx.Paint(frame, false)
end

local function IsCardFrozen(frame)
    if not frame then return false end
    if frame._locallyFrozen then return true end
    local pd = frame._perkData
    return pd and (pd.isFrozen or pd.isCarried or pd.justFrozen)
end

-- The MEMORY card (choice flag 3, 4th slot): an echo of the loadout's engraved
-- build, offered next to the random draws. Cannot be banished or frozen, and a
-- reroll leaves it in place; picking a random card instead sacrifices it.
local function IsCardGuaranteed(frame)
    if not frame then return false end
    local pd = frame._perkData
    return pd and pd.isGuaranteed or false
end

local _lastBanishRem = nil
local function UpdateBanishButtons()
    local rem = GetBanishInfo()
    local remChanged = (rem ~= _lastBanishRem)
    _lastBanishRem = rem
    local banishLabel = remChanged and ("Banish (" .. rem .. ")") or nil
    for _, frame in ipairs(perkFramePool) do
        if frame.inUse and frame.banishCardButton then
            local btn = frame.banishCardButton
            -- Orb offer: banish is refused server-side, so the button is not shown at all.
            if (perkMainFrame and perkMainFrame.perksHidden) or IsOrbOfferPending() then
                btn:Hide()
            elseif IsCardGuaranteed(frame) then
                btn:Hide() -- the souvenir card carries no run action at all
            elseif IsCardFrozen(frame) then
                btn:Show()
                btn:Disable()
                btn:EnableMouse(true) -- swallows the click: the card under it is a button too
                if btn.text then
                    btn.text:SetText("Banish")
                    btn.text:SetTextColor(0.5, 0.5, 0.5)
                end
            elseif rem > 0 then
                btn:Show()
                btn:EnableMouse(true)
                btn:Enable()
                if btn.text then
                    if banishLabel then btn.text:SetText(banishLabel) end
                    btn.text:SetTextColor(1, 1, 1)
                end
            else
                btn:Show()
                btn:EnableMouse(true)
                btn:Disable()
                if btn.text then
                    if banishLabel then btn.text:SetText("Banish (0)") end
                    btn.text:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end
    end
end

local function UpdateFreezeButtons()
    local availFreezes = GetFreezeInfo()
    local freezeLabel = "Freeze (" .. availFreezes .. ")"
    for _, frame in ipairs(perkFramePool) do
        if frame.inUse and frame.freezeCardButton then
            local btn = frame.freezeCardButton
            -- Orb offer: freeze is refused server-side, so the button is not shown at all.
            if (perkMainFrame and perkMainFrame.perksHidden) or IsOrbOfferPending() then
                btn:Hide()
            elseif IsCardGuaranteed(frame) then
                btn:Hide() -- the souvenir card carries no run action at all
            elseif false then
                btn:Show()
                btn:Disable()
                btn:EnableMouse(true) -- swallows the click: the card under it is a button too
                if btn.text then
                    btn.text:SetText("Freeze")
                    btn.text:SetTextColor(0.5, 0.5, 0.5)
                end
                if btn.SetBackdropColor then
                    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
                    btn:SetBackdropBorderColor(0, 0, 0, 1)
                end
            elseif IsCardFrozen(frame) then
                btn:Show()
                btn:Disable()
                btn:EnableMouse(true) -- swallows the click: the card under it is a button too
                ApplyFreezeVisual(frame)
                if btn.text then
                    btn.text:SetText("Freeze")
                    btn.text:SetTextColor(0.5, 0.5, 0.5)
                end
                if btn.SetBackdropColor then
                    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
                    btn:SetBackdropBorderColor(0, 0, 0, 1)
                end
            elseif availFreezes > 0 then
                btn:Show()
                btn:EnableMouse(true)
                btn:Enable()
                if btn.text then
                    btn.text:SetText(freezeLabel)
                    btn.text:SetTextColor(1, 1, 1)
                end
                if btn.SetBackdropColor then
                    btn:SetBackdropColor(0.06, 0.12, 0.28, 0.95)
                    btn:SetBackdropBorderColor(0, 0, 0, 1)
                end
            else
                btn:Show()
                btn:EnableMouse(true)
                btn:Disable()
                if btn.text then
                    btn.text:SetText("Freeze (0)")
                    btn.text:SetTextColor(0.5, 0.5, 0.5)
                end
                if btn.SetBackdropColor then
                    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
                    btn:SetBackdropBorderColor(0, 0, 0, 1)
                end
            end
        end
    end
end

local MAX_PERK_FRAME_POOL = 6

local function AcquirePerkFrame(parent)
    for _, frame in ipairs(perkFramePool) do
        if not frame.inUse then
            frame:SetParent(parent)
            frame:SetAlpha(1)
            frame:ClearAllPoints()
            frame.inUse = true
            return frame
        end
    end

    if #perkFramePool >= MAX_PERK_FRAME_POOL then
        return nil
    end

    local index = #perkFramePool + 1
    local frame = CreateFrame("Frame", "PerkChoice" .. index, parent)
    frame:SetSize(CARD_W, CARD_H)
    frame._card = frame

    -- The frame never moves and keeps the hit area; everything that shows sits on `visual`, which lifts
    -- and grows on hover. A card that moved its own hit area would run away from a cursor coming from below.
    local visual = CreateFrame("Frame", nil, frame)
    visual:SetSize(CARD_W, CARD_H)
    visual:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.visual = visual
    CardFx.BuildBody(frame, visual)

    -- Flat dark face of the transparent design, in place of the stone
    local backdropFrame = CreateFrame("Frame", nil, visual)
    backdropFrame:SetSize(CARD_W, CARD_H) -- sized, not stuck to `visual`: it grows on hover with the rim
    backdropFrame:SetPoint("CENTER", visual, "CENTER", 0, 0)
    frame.backdropFrame = backdropFrame

    if IsTransparentDesign() then
        frame.bg:Hide()
        frame._fxNoFlip = true
        if backdropFrame.SetBackdrop then
            backdropFrame:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                tile = true,
                tileSize = 16,
                edgeSize = 4,
                insets = { left = 4, right = 4, top = 4, bottom = 4 }
            })
            backdropFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
            backdropFrame:SetBackdropBorderColor(0, 0, 0, 1)
        end
    else
        backdropFrame:Hide()
    end

    -- All the card's content; fades in once the card has turned over
    local topPerkFrame = CreateFrame("Frame", nil, visual)
    topPerkFrame:SetAllPoints(visual)
    topPerkFrame:SetFrameLevel(visual:GetFrameLevel() + 3)
    frame.content = topPerkFrame

    local iconFrame = CreateFrame("Frame", nil, topPerkFrame)
    iconFrame:SetSize(CardFx.ICON_SIZE, CardFx.ICON_SIZE)
    iconFrame:SetPoint("CENTER", visual, "TOP", 0, CardFx.ICON_Y)
    frame.iconFrame = iconFrame

    local iconBase = iconFrame:CreateTexture(nil, "BACKGROUND")
    CardFx.PlaceArt(iconBase, visual)
    frame.iconBase = iconBase

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    icon:SetSize(CardFx.ICON_SIZE, CardFx.ICON_SIZE)
    frame.icon = icon

    local border = iconFrame:CreateTexture(nil, "OVERLAY")
    CardFx.PlaceArt(border, visual)
    frame.border = border

    CardFx.BuildSwirl(frame, iconFrame)

    -- Freeze indicator (ice overlay texture)
    local freezeIndicator = iconFrame:CreateTexture(nil, "OVERLAY")
    freezeIndicator:SetSize(50, 50)
    freezeIndicator:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 20, 20)
    freezeIndicator:SetTexture("Interface\\Icons\\Spell_Frost_FrostShock")
    freezeIndicator:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    freezeIndicator:Hide()
    frame.freezeIndicator = freezeIndicator

    -- Status line at the top of the card (the souvenir says what it is)
    local freezeStatusText = topPerkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    freezeStatusText:SetFont("Fonts\\ARIALN.TTF", 12)
    freezeStatusText:SetPoint("TOP", visual, "TOP", 0, -9)
    freezeStatusText:SetWidth(170)
    freezeStatusText:SetJustifyH("CENTER")
    freezeStatusText:SetTextColor(0.4, 0.7, 1.0)
    freezeStatusText:Hide()
    frame.freezeStatusText = freezeStatusText

    local nameText = topPerkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetFont("Fonts\\MORPHEUS.ttf", 20)
    nameText:SetPoint("TOP", visual, "TOP", 0, -147)
    nameText:SetWidth(192)
    nameText:SetJustifyH("CENTER")
    nameText:SetShadowColor(0, 0, 0, 1)
    nameText:SetShadowOffset(1, -1)
    frame.nameText = nameText

    local rarityText = topPerkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rarityText:SetFont("Fonts\\FRIZQT__.TTF", 10)
    rarityText:SetPoint("TOP", nameText, "BOTTOM", 0, -3)
    rarityText:SetTextColor(0.65, 0.61, 0.56)
    frame.rarityText = rarityText

    -- Owned counter, hidden since the owner removed it (2026-10-23): the tooltip's stack line says it
    local ownedFrame = CreateFrame("Frame", nil, topPerkFrame)
    ownedFrame:SetSize(50, 24)
    ownedFrame:SetPoint("BOTTOM", iconFrame, "TOP", 0, 18)
    frame.ownedCountFrame = ownedFrame
    local ownedCountText = ownedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ownedCountText:SetPoint("CENTER", ownedFrame, "CENTER", 0, 0)
    ownedCountText:SetFont("Fonts\\FRIZQT__.TTF", 16)
    ownedCountText:SetTextColor(0.9, 0.85, 0.5)
    frame.ownedCountText = ownedCountText

    local descText = topPerkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descText:SetFont("Fonts\\ARIALN.TTF", 13)
    descText:SetPoint("TOP", rarityText, "BOTTOM", 0, -7)
    descText:SetWidth(188)
    descText:SetHeight(96)
    descText:SetJustifyH("CENTER")
    descText:SetJustifyV("TOP")
    descText:SetTextColor(0.87, 0.83, 0.76)
    frame.descText = descText

    -- "Select (3)" when the option asks for the count of picks left
    local selectHint = topPerkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selectHint:SetFont("Fonts\\FRIZQT__.TTF", 11)
    selectHint:SetPoint("BOTTOM", visual, "BOTTOM", 0, 14)
    selectHint:SetTextColor(0.87, 0.83, 0.76)
    selectHint:Hide()
    frame.selectHint = selectHint

    CardFx.BuildOverlay(frame, visual, topPerkFrame)

    -- Spec badge: the echo's specialization as its talent-tab icon, round, in the skill
    -- tree's gold ring (assets/class_ring, 1.16 x the icon like a tree node), centred above
    -- on the top right of the echo's icon, anchored to the icon so it follows it when it grows on hover.
    -- Hidden on echoes without a spec.
    local specBadge = CreateFrame("Frame", nil, visual)
    specBadge:SetSize(28, 28)
    specBadge:SetPoint("CENTER", frame.icon, "TOPRIGHT", -6, -6)
    specBadge:SetFrameLevel(visual:GetFrameLevel() + 6)
    specBadge._card = frame
    local specGlow = specBadge:CreateTexture(nil, "BACKGROUND")
    specGlow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
    specGlow:SetBlendMode("ADD")
    specGlow:SetVertexColor(1, 0.75, 0.1, 0.6)
    specGlow:SetPoint("CENTER", specBadge, "CENTER", 0, 0)
    specGlow:SetSize(60, 60)
    local specIcon = specBadge:CreateTexture(nil, "ARTWORK")
    specIcon:SetAllPoints(specBadge)
    specBadge.icon = specIcon
    local specRing = specBadge:CreateTexture(nil, "OVERLAY")
    specRing:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\class_ring")
    specRing:SetPoint("CENTER", specBadge, "CENTER", 0, 0)
    specRing:SetSize(28 * 1.16, 28 * 1.16)
    specBadge:EnableMouse(true)
    specBadge:SetScript("OnEnter", function(self)
        if not self.specName then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(self.specName .. " Specialization", unpack(SPEC_GOLD))
        GameTooltip:AddLine("This echo belongs to the " .. self.specName .. " specialization.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    specBadge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    specBadge:Hide()
    frame.specBadge = specBadge

    -- The whole card is the Select button: invisible and stretched over the card, so every rule of a pick
    -- (the grace time, the spec question, the EnableMouse switches below) stays where it was. Its mouse
    -- also covers the frame, so the frame's right-click (chat link) has to be passed down.
    local selectButton = utils.CreateSimpleCustomButton(frame, "Select", nil, CARD_W, CARD_H)
    selectButton:ClearAllPoints()
    selectButton:SetAllPoints(frame)
    selectButton:SetFrameLevel(frame:GetFrameLevel() + 3)
    selectButton:SetAlpha(0)
    selectButton._card = frame
    selectButton:SetScript("OnMouseDown", function(_, button)
        local handler = frame:GetScript("OnMouseDown")
        if handler then handler(frame, button) end
    end)
    frame.selectButton = selectButton

    -- Freeze and Banish: side by side at the bottom of the card, shown on hover (CardFx sets their alpha)
    local freezeCardButton = utils.CreateSimpleCustomButton(visual, "Freeze", nil, 96, 24,
        "Interface\\AddOns\\ProjectEbonhold\\assets\\128redbutton9sliced_blue")
    freezeCardButton:SetPoint("BOTTOMRIGHT", visual, "BOTTOM", -2, 9)
    freezeCardButton:SetFrameLevel(visual:GetFrameLevel() + 8)
    freezeCardButton:SetAlpha(0)
    freezeCardButton._card = frame
    freezeCardButton:Hide()
    freezeCardButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Freeze", 1, 1, 1)
        GameTooltip:AddLine("Freeze this perk so it carries over to your next selection.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    freezeCardButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if not freezeCardButton.text then
        freezeCardButton.text = freezeCardButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        freezeCardButton.text:SetPoint("CENTER", freezeCardButton, "CENTER", 0, 0)
    end
    freezeCardButton.text:SetText("Freeze")
    freezeCardButton.text:SetTextColor(1, 1, 1)

    freezeCardButton:SetScript("OnClick", function()
        if GetTime() < perkCardsGraceUntil then return end
        if IsCardFrozen(frame) or IsCardGuaranteed(frame) then return end

        local success = ProjectEbonhold.PerkService.FreezePerk(frame._perkIndex)
        if success then
            frame._locallyFrozen = true
            local runData = ProjectEbonhold.PlayerRunService and ProjectEbonhold.PlayerRunService.GetCurrentData()
            if runData then
                runData.usedFreezes = (runData.usedFreezes or 0) + 1
            end
            ApplyFreezeVisual(frame)
            UpdateFreezeButtons()
            UpdateBanishButtons()
        end
    end)

    frame.freezeCardButton = freezeCardButton

    -- Per-card Banish button (next to freeze, purple texture)
    local banishCardButton = utils.CreateSimpleCustomButton(visual, "Banish", nil, 96, 24,
        "Interface\\AddOns\\ProjectEbonhold\\assets\\128redbutton9sliced_purple")
    banishCardButton:SetPoint("BOTTOMLEFT", visual, "BOTTOM", 2, 9)
    banishCardButton:SetFrameLevel(visual:GetFrameLevel() + 8)
    banishCardButton:SetAlpha(0)
    banishCardButton._card = frame
    banishCardButton:Hide()
    banishCardButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Banish", 1, 1, 1)
        GameTooltip:AddLine("Banish this perk so it won't appear again this run.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    banishCardButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if not banishCardButton.text then
        banishCardButton.text = banishCardButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        banishCardButton.text:SetPoint("CENTER", banishCardButton, "CENTER", 0, 0)
    end
    banishCardButton.text:SetText("Banish")
    banishCardButton.text:SetTextColor(1, 1, 1)

    frame.banishCardButton = banishCardButton


    if IsTransparentDesign() then
        local function skinCardButton(btn)
            if not btn then return end
            local function hideTex(t)
                if t then
                    t:Hide()
                    t:SetTexture(nil)
                end
            end
            hideTex(btn:GetNormalTexture())
            hideTex(btn:GetPushedTexture())
            hideTex(btn:GetHighlightTexture())
            hideTex(btn:GetDisabledTexture())
            if btn.SetBackdrop then
                btn:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    tile = true,
                    tileSize = 16,
                    edgeSize = 2,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 }
                })
                if btn.text then btn.text:SetFontObject("GameFontNormalSmall") end
            end
        end
        skinCardButton(selectButton)
        skinCardButton(banishCardButton)
        skinCardButton(freezeCardButton)

        selectButton:SetBackdropColor(0.08, 0.28, 0.1, 0.95)
        selectButton:SetBackdropBorderColor(0, 0, 0, 1)
        selectButton:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.15, 0.5, 0.2, 1)
            self:SetBackdropColor(0.18, 0.42, 0.2, 0.98)
        end)
        selectButton:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0, 0, 0, 1)
            self:SetBackdropColor(0.08, 0.28, 0.1, 0.95)
        end)

        -- Banish: red only on hover when enabled; black border always
        banishCardButton:SetScript("OnEnter", function(self)
            if self:IsEnabled() and self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0, 0, 0, 1)
                self:SetBackdropColor(0.48, 0.16, 0.14, 0.98)
            end
        end)
        banishCardButton:SetScript("OnLeave", function(self)
            if self.SetBackdropBorderColor then
                local rem = GetBanishInfo()
                if rem > 0 then
                    self:SetBackdropBorderColor(0, 0, 0, 1)
                    self:SetBackdropColor(0.32, 0.1, 0.1, 0.95)
                else
                    self:SetBackdropBorderColor(0, 0, 0, 1)
                    self:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
                end
            end
        end)

        -- Freeze: blue tint, blue hover
        freezeCardButton:SetBackdropColor(0.06, 0.12, 0.28, 0.95)
        freezeCardButton:SetBackdropBorderColor(0, 0, 0, 1)
        freezeCardButton:SetScript("OnEnter", function(self)
            if self:IsEnabled() and self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0, 0, 0, 1)
                self:SetBackdropColor(0.14, 0.28, 0.5, 0.98)
            end
        end)
        freezeCardButton:SetScript("OnLeave", function(self)
            if self.SetBackdropBorderColor then
                local avail = GetFreezeInfo()
                if avail > 0 then
                    self:SetBackdropBorderColor(0, 0, 0, 1)
                    self:SetBackdropColor(0.06, 0.12, 0.28, 0.95)
                else
                    self:SetBackdropBorderColor(0, 0, 0, 1)
                    self:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
                end
            end
        end)
    end

    -- Ctrl+drag from any of the 3 cards moves the whole perk UI (avoids accidental reroll)
    -- Shift+right-click on card inserts echo spell link into chat
    frame:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" and IsShiftKeyDown() and self._spellId then
            local link = GetSpellLink(self._spellId)
            if not link or link == "" then
                local name = GetSpellInfo(self._spellId) or ("Spell " .. self._spellId)
                link = ("|cff71d5ff|Hspell:%d|h[%s]|h|r"):format(self._spellId, name)
            end
            local edit = ChatEdit_ChooseBoxForSend()
            if not edit:HasFocus() then
                ChatEdit_ActivateChat(edit)
            end
            ChatEdit_InsertLink(link)
            return
        end
    end)

    -- These four handlers are registered ONCE per frame (here in AcquirePerkFrame, not in
    -- UpdatePerkFrame). They read dynamic data from frame properties (_spellId, _perkIndex,
    -- _qualityData, _stacks, _maxStacks) which UpdatePerkFrame sets on each reuse.
    -- This prevents 4 new closures × 3 cards × 79 ShowPerkUI calls per level-up from
    -- accumulating as upvalue garbage in the 3.3.5 Lua runtime.

    selectButton:SetScript("OnClick", function()
        if GetTime() < perkCardsGraceUntil then return end
        if isSelecting then
            return
        end
        -- Choosing the spec is for the whole run: ask first (PROJECTEBONHOLD_SPEC_CONFIRM).
        local draw = GetSpecDraw()
        if draw and draw.chosen == 0 and not (frame._perkData and frame._perkData.isGuaranteed) then
            local specName = GetEchoSpecName(frame._spellId)
            if specName then
                local dialog = StaticPopup_Show("PROJECTEBONHOLD_SPEC_CONFIRM", specName, GetSpellInfo(frame._spellId) or "this echo")
                if dialog then
                    dialog.data = { frame = frame, spellId = frame._spellId }
                    -- Same lift as the souvenir popup: the cards and the gold banner sit on the
                    -- DIALOG strata at a high level and would otherwise draw over the question.
                    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
                    dialog:SetFrameLevel(600)
                end
                return
            end
        end
        frame.DoSelect()
    end)

    frame.DoSelect = function()
        if isSelecting then return end
        isSelecting = true
        for _, f in ipairs(perkFramePool) do
            if f.inUse then
                f.selectButton:EnableMouse(false)
                f:EnableMouse(false)
                if f.banishCardButton then f.banishCardButton:EnableMouse(false) end
                if f.freezeCardButton then f.freezeCardButton:EnableMouse(false) end
            end
        end
        if frame._perkData and frame._perkData.isGuaranteed then
            PlayMemoryKeepBurst(frame)
            for _, d in ipairs(memoryDeck) do d:EnableMouse(false) end
        end
        local success = ProjectEbonhold.PerkService.SelectPerk(frame._spellId)
        if success and not (frame._perkData and frame._perkData.isGuaranteed) then
            CardFx.PlayPick(frame)
        end
        if not success then
            isSelecting = false
            for _, f in ipairs(perkFramePool) do
                if f.inUse then
                    f.selectButton:EnableMouse(true)
                    f:EnableMouse(true)
                    if f.banishCardButton then f.banishCardButton:EnableMouse(true) end
                    if f.freezeCardButton then f.freezeCardButton:EnableMouse(true) end
                end
            end
        end
    end

    banishCardButton:SetScript("OnClick", function()
        if GetTime() < perkCardsGraceUntil then return end
        if isSelecting then return end
        if frame._perkData and (frame._perkData.isFrozen or frame._perkData.isCarried or frame._perkData.isGuaranteed) then return end
        isSelecting = true
        for _, f in ipairs(perkFramePool) do
            if f.inUse then
                f.selectButton:EnableMouse(false)
                f:EnableMouse(false)
                if f.banishCardButton then f.banishCardButton:EnableMouse(false) end
                if f.freezeCardButton then f.freezeCardButton:EnableMouse(false) end
            end
        end
        local success = ProjectEbonhold.PerkService.BanishPerk(frame._perkIndex)
        isSelecting = false
        for _, f in ipairs(perkFramePool) do
            if f.inUse then
                f.selectButton:EnableMouse(true)
                f:EnableMouse(true)
                if f.banishCardButton then f.banishCardButton:EnableMouse(true) end
                if f.freezeCardButton then f.freezeCardButton:EnableMouse(true) end
            end
        end
        if success then
            frame.banishCardButton:Hide()
            UpdateBanishButtons()
            UpdateFreezeButtons()
        else
            UpdateBanishButtons()
            UpdateFreezeButtons()
        end
    end)

    frame.inUse = true
    table.insert(perkFramePool, frame)
    return frame
end

-- Phase 0..1 -> (x, y) on card rectangle (top -> right -> bottom -> left)
local function phaseToXY(p)
    local x, y
    if p < 0.25 then
        x = -100 + (p / 0.25) * 200
        y = 160
    elseif p < 0.5 then
        x = 100
        y = 160 - ((p - 0.25) / 0.25) * 320
    elseif p < 0.75 then
        x = 100 - ((p - 0.5) / 0.25) * 200
        y = -160
    else
        x = -100
        y = -160 + ((p - 0.75) / 0.25) * 320
    end
    return x, y
end

local function wrapPhase(z)
    local w = z % 1
    if w < 0 then w = w + 1 end
    return w
end

-- Golden glow + star marking a choice that belongs to the active echo loadout.
-- The card's icon lives inside frame.iconFrame, whose regions draw above any
-- texture created on the card itself — so the highlight needs its own child
-- frame with a raised frame level, or it gets buried under the icon art.
local function ApplyLoadoutHighlight(frame, spellId)
    local svc = ProjectEbonhold.PerkService
    -- Server-guaranteed cards (active build slot, flag 3) get the same golden
    -- treatment as wish-list loadout echoes - one visual language for "this is
    -- part of the build I'm playing".
    local inLoadout = IsCardGuaranteed(frame)
        or (svc and svc.IsSpellInActiveEchoLoadout
            and svc.IsSpellInActiveEchoLoadout(spellId))

    -- The other end of the same build: an echo it refuses. Greyed with a red
    -- cross, never picked automatically - but still clickable, because the
    -- build is a preference, not a rule the game enforces on its owner.
    -- A souvenir card is exempt: it is the player's own finished build coming
    -- back, and it can only ever be taken by hand.
    local refused = (not IsCardGuaranteed(frame)) and svc and svc.GetActiveEchoLoadoutRule
        and svc.GetActiveEchoLoadoutRule(spellId) == "avoid"
    if refused then
        if not frame.avoidMark then
            local host = frame.iconFrame or frame
            local ov = CreateFrame("Frame", nil, host)
            ov:SetFrameLevel(host:GetFrameLevel() + 6)
            ov:SetAllPoints(host)
            local x = ov:CreateTexture(nil, "OVERLAY")
            x:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
            x:SetSize(22, 22)
            x:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -6, 6)
            ov.mark = x
            frame.avoidMark = ov
        end
        frame.avoidMark:Show()
        frame.icon:SetDesaturated(true)
        frame.icon:SetVertexColor(0.7, 0.45, 0.45)
    else
        if frame.avoidMark then frame.avoidMark:Hide() end
        frame.icon:SetDesaturated(false)
        frame.icon:SetVertexColor(1, 1, 1)
    end

    if inLoadout then
        if not frame.loadoutOverlay then
            local host = frame.iconFrame or frame
            local ov = CreateFrame("Frame", nil, host)
            ov:SetFrameLevel(host:GetFrameLevel() + 5)
            ov:SetAllPoints(host)
            frame.loadoutOverlay = ov

            local g = ov:CreateTexture(nil, "BACKGROUND")
            g:SetTexture("Interface\\Cooldown\\star4")
            g:SetBlendMode("ADD")
            g:SetVertexColor(1, 0.85, 0.1, 0.7)
            g:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
            frame.loadoutGlow = g

            -- Slow spin, same recipe as the permanent slot swirls
            local anim = g:CreateAnimationGroup()
            anim:SetLooping("REPEAT")
            local rot = anim:CreateAnimation("Rotation")
            rot:SetDuration(6)
            rot:SetDegrees(360)
            rot:SetOrigin("CENTER", 0, 0)
            anim:Play()

            local star = ov:CreateTexture(nil, "OVERLAY")
            star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
            star:SetSize(16, 16)
            star:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -8, 8) -- top right is the spec badge
            frame.loadoutStar = star
        end
        local iw = frame.icon and frame.icon:GetWidth() or 0
        if iw < 1 then iw = 40 end
        frame.loadoutGlow:SetSize(iw * 2.2, iw * 2.2)
        frame.loadoutOverlay:Show()
        -- The star is the wishlist mark; a souvenir keeps only the glow
        if IsCardGuaranteed(frame) then frame.loadoutStar:Hide() else frame.loadoutStar:Show() end
        -- Souvenir: the glow breathes so the card reads as "alive" next to the
        -- face-down draws
        if IsCardGuaranteed(frame) then
            if not frame.loadoutBreath then
                local ag = frame.loadoutGlow:CreateAnimationGroup()
                ag:SetLooping("BOUNCE")
                local a = ag:CreateAnimation("Alpha")
                a:SetChange(-0.45)
                a:SetDuration(1.3)
                a:SetSmoothing("IN_OUT")
                frame.loadoutBreath = ag
            end
            frame.loadoutBreath:Play()
        elseif frame.loadoutBreath then
            frame.loadoutBreath:Stop()
        end
    elseif frame.loadoutOverlay then
        frame.loadoutOverlay:Hide()
        if frame.loadoutBreath then frame.loadoutBreath:Stop() end
    end
end

local function UpdatePerkFrame(frame, perkData, perkIndex)
    if not frame or not perkData then return end

    local spellId = perkData.spellId
    local quality = perkData.quality
    local stacks = perkData.stack or 1
    local maxStacks = perkData.maxStack or 1
    local qualityData = qualityInfo[quality] or qualityInfo[0]

    frame.perkIndex = perkIndex
    frame.iconBase:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perk_quality_" .. qualityData.border)
    frame.border:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perk_border_quality_" .. qualityData.border)

    local spellName, _, spellIcon = GetSpellInfo(spellId)
    if spellIcon then
        SetPortraitToTexture(frame.icon, spellIcon)
    else
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    frame.nameText:SetText(spellName or ("Spell " .. spellId))
    frame.nameText:SetTextColor(unpack(qualityData.text or qualityData.color))
    frame.rarityText:SetText(string.upper(qualityData.name))
    frame._fxHiddenUntil = nil
    -- Reset locally-frozen flag; will be re-applied below if still frozen
    frame._locallyFrozen = false
    local isFrozenCard = perkData.justFrozen or perkData.isFrozen or perkData.isCarried
    if isFrozenCard then
        frame._locallyFrozen = true
    end
    if frame.backdropFrame and frame.backdropFrame.SetBackdropColor then
        if isFrozenCard then
            ApplyFreezeVisual(frame)
        else
            ClearFreezeVisual(frame)
        end
    end
    local description = utils.GetSpellDescription(spellId, 200)
    frame.descText:SetText(description)

    if frame.specBadge then
        local specName, specFamily = GetEchoSpecName(spellId)
        local specTex = specFamily and utils.PerkSpecIcons and utils.PerkSpecIcons[specFamily]
        if specTex then
            -- SetPortraitToTexture builds a new round texture each call: only on a change.
            if frame.specBadge.iconPath ~= specTex then
                frame.specBadge.iconPath = specTex
                SetPortraitToTexture(frame.specBadge.icon, specTex)
            end
            frame.specBadge.specName = specName
            frame.specBadge:Show()
        else
            frame.specBadge.specName = nil
            frame.specBadge:Hide()
        end
    end

    -- Show how many of this echo you already have (text only, below main icon)
    local granted = (ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetGrantedPerks) and
        ProjectEbonhold.PerkService.GetGrantedPerks() or {}
    local count = 0
    if spellName and granted[spellName] then count = #granted[spellName] end
    if count == 0 and spellId and granted then
        for name, arr in pairs(granted) do
            if arr and #arr > 0 and arr[1].spellId == spellId then
                count = #arr
                break
            end
        end
    end
    frame._ownedCount = count
    frame._spellId = spellId
    -- The "x2" badge is gone (owner 2026-10-23): the tooltip's stack line says it, with the values.
    if frame.ownedCountFrame then
        frame.ownedCountFrame:Hide()
    end

    local rollsCount = (ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetPendingRollsCount and ProjectEbonhold.PerkService.GetPendingRollsCount()) or
        0
    frame.selectButton.text:SetText(GetSelectLabel(rollsCount))
    frame.selectButton.text:SetTextColor(1, 1, 1)
    CardFx.SetSelectHint(frame, IsPerkShowSelectCountEnabled() and GetSelectLabel(rollsCount) or nil)

    -- Dynamic data stored as frame properties; handlers registered once in AcquirePerkFrame read these.
    frame._spellId = spellId
    frame._perkIndex = perkIndex
    frame._qualityData = qualityData
    frame._fxQuality = quality
    CardFx.Paint(frame, isFrozenCard)
    frame._stacks = stacks
    frame._maxStacks = maxStacks
    frame._perkData = perkData
    frame._isCarried = perkData and perkData.isCarried or false

    do
        local rem = GetBanishInfo()
        if frame.banishCardButton.text then
            frame.banishCardButton.text:SetText("Banish (" .. rem .. ")")
            if rem > 0 then
                frame.banishCardButton.text:SetTextColor(1, 1, 1)
            else
                frame.banishCardButton.text:SetTextColor(0.5, 0.5, 0.5)
            end
        end
        if rem > 0 then
            frame.banishCardButton:Enable()
        else
            frame.banishCardButton:Disable()
        end
        if frame.banishCardButton.SetBackdropColor then
            if rem > 0 then
                frame.banishCardButton:SetBackdropColor(0.32, 0.1, 0.1, 0.95)
                frame.banishCardButton:SetBackdropBorderColor(0, 0, 0, 1)
            else
                frame.banishCardButton:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
                frame.banishCardButton:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
    end

    -- Status line: the memory card says what it is; the frozen/carried states
    -- keep it hidden as before.
    if frame.freezeStatusText then
        if perkData.isGuaranteed then
            frame.freezeStatusText:SetText("|cffffd700Souvenir|r")
            frame.freezeStatusText:Show()
        else
            frame.freezeStatusText:Hide()
        end
    end
    -- hide legacy indicator if still present
    if frame.freezeIndicator then frame.freezeIndicator:Hide() end

    ApplyLoadoutHighlight(frame, spellId)

    frame:EnableMouse(true)
    frame:Show()
    frame.iconFrame:Show()
    frame.icon:Show()
    frame.iconBase:Show()
    frame.border:Show()
    frame.nameText:Show()
    frame.descText:Show()
    frame.selectButton:Show()
end

local function InitializePerkUI()
    if perkMainFrame then return end

    perkMainFrame = CreateFrame("Frame", "ProjectEbonholdPerkFrame", UIParent)
    ProjectEbonhold.GuidedTour.BarAlerts.SetBlocker(perkMainFrame)
    perkMainFrame:SetFrameStrata("DIALOG")
    perkMainFrame:SetFrameLevel(100)
    perkMainFrame:SetSize(800, 280)
    perkMainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
    perkMainFrame:SetScale(GetPerkUIScale())
    perkMainFrame:Hide()

    perkMainFrame:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end

        CardFx.Update(elapsed)

        self.banishPollElapsed = (self.banishPollElapsed or 0) + elapsed
        if self.banishPollElapsed >= 0.2 then
            self.banishPollElapsed = 0
            UpdateBanishButtons()
            UpdateFreezeButtons()
            local n = (ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetPendingRollsCount and ProjectEbonhold.PerkService.GetPendingRollsCount()) or
                0
            if n ~= self._lastPendingRolls then
                self._lastPendingRolls = n
                local label = GetSelectLabel(n)
                for _, f in ipairs(perkFramePool) do
                    if f.inUse and f.selectButton and f.selectButton.text then
                        f.selectButton.text:SetText(label)
                        CardFx.SetSelectHint(f, IsPerkShowSelectCountEnabled() and label or nil)
                    end
                end
            end
            if memoryStageShown and rerollButton and rerollButton:IsShown() then
                rerollButton:Hide()
            end
            if not self.perksHidden and rerollButton and not memoryStageShown then
                -- Mode-aware: on an orb offer the number on the button is the orb count, so
                -- that is what has to be watched. The mode itself is watched too - an orb
                -- offer arriving on the same count would otherwise leave the label stale.
                local orbMode = IsOrbOfferPending()
                local avail = orbMode and GetOrbCharges() or GetRerollInfo()
                if avail ~= self._lastRerollAvail or orbMode ~= self._lastRerollOrbMode then
                    self._lastRerollAvail = avail
                    self._lastRerollOrbMode = orbMode
                    RefreshRerollButton()
                end
            end
        end
    end)

    perkMainFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            ProjectEbonhold.PerkUI.Hide()
        end
    end)

    rerollButton = utils.CreateSimpleCustomButton(perkMainFrame, "Reroll", nil, 160, 35)
    rerollButton:SetPoint("CENTER", perkMainFrame, "CENTER", 0, 310)
    if IsTransparentDesign() then
        -- Red hover glow (manual overlay so it never gets lost; match banish darkness)
        local rerollGlow = rerollButton:CreateTexture(nil, "OVERLAY")
        rerollGlow:SetAllPoints(rerollButton)
        rerollGlow:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        rerollGlow:SetBlendMode("ADD")
        -- Tinted by ApplyRerollSkin: red for the run's reroll, mauve for an orb reroll.
        rerollGlow:SetVertexColor(0.5, 0.14, 0.14, 0.4)
        rerollGlow:Hide()
        rerollButton._rerollGlow = rerollGlow
        local function hideTex(t)
            if t then
                t:Hide()
                t:SetTexture(nil)
            end
        end
        hideTex(rerollButton:GetNormalTexture())
        hideTex(rerollButton:GetPushedTexture())
        hideTex(rerollButton:GetHighlightTexture())
        hideTex(rerollButton:GetDisabledTexture())
        if rerollButton.SetBackdrop then
            rerollButton:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                tile = true,
                tileSize = 16,
                edgeSize = 2,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            rerollButton:SetBackdropColor(0.22, 0.06, 0.06, 0.95)
            rerollButton:SetBackdropBorderColor(0, 0, 0, 1)
        end
        if rerollButton.text then rerollButton.text:SetFontObject("GameFontNormalSmall") end
    else
        MakePlate(rerollButton, 160, 36, 13)
    end
    rerollButton:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            ApplyRerollSkin(true)
            if self._rerollGlow then self._rerollGlow:Show() end
        end
        -- No tooltip in orb mode: the label already carries the whole statement ("Use Orbs" and
        -- how many are left), and the Echo Journal is where the mechanic is explained.
        if self._orbMode then
            GameTooltip:Hide()
            return
        end

        local availableRerolls, totalRerolls = GetRerollInfo()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Reroll Echoes", 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            "Reroll current echoes. These echoes won't appear in your next choice, but may return in future selections. Decreases the odds of drawing echoes in the families of your current selection",
            1, 1, 1, true)
        GameTooltip:AddLine(" ")
        if availableRerolls > 0 then
            GameTooltip:AddLine("Rerolls remaining: " .. availableRerolls .. "/" .. totalRerolls, 0, 1, 0)
        else
            GameTooltip:AddLine("No rerolls remaining", 1, 0, 0)
        end
        GameTooltip:Show()
    end)
    rerollButton:SetScript("OnLeave", function(self)
        ApplyRerollSkin(false)
        if self._rerollGlow then self._rerollGlow:Hide() end
        GameTooltip:Hide()
    end)
    rerollButton:SetFrameLevel(perkMainFrame:GetFrameLevel() + 20)
    rerollButton:SetScript("OnClick", function()
        if IsOrbOfferPending() then
            -- No client-side throttle here: the 100ms minimum between two orb spends is a
            -- Comms.ThrottleRules entry on 1221/1222, so it holds for a forged packet too.
            local orb = ProjectEbonhold.OrbService
            if not (orb and orb.CanRerollOffer and orb.CanRerollOffer()) then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000No Orb of Lost Memories left to spend.|r")
                return
            end
            orb.RerollOffer()
            -- Repaint now rather than waiting on the 0.2s poll: the count the button advertises
            -- is already spent, and a second click on a stale number is a second orb.
            RefreshRerollButton()
            return
        end

        local availableRerolls = GetRerollInfo()
        if availableRerolls <= 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000No rerolls remaining! Rerolls are restored upon death.|r")
            return
        end
        ProjectEbonhold.PerkService.RequestReroll()
    end)
    rerollButton:Hide()

    hideButton = CreateFrame("Button", "PerkHideButton", perkMainFrame)
    hideButton:SetSize(120, 27)
    -- Under the middle card, just clear of its bottom edge (-100) and level with the outer cards' (-114)
    hideButton:SetPoint("TOP", perkMainFrame, "BOTTOM", 0, 22)
    hideButton:RegisterForClicks("LeftButtonUp")
    hideButton:Hide()

    local hideButtonText = hideButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideButtonText:SetPoint("CENTER", hideButton, "CENTER", 0, 0)
    hideButtonText:SetTextColor(0.7, 0.7, 0.7)
    hideButton.text = hideButtonText

    if IsTransparentDesign() then
        hideButton:SetSize(120, 25)
        if hideButton.SetBackdrop then
            hideButton:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                tile = true,
                tileSize = 16,
                edgeSize = 2,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            hideButton:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
            hideButton:SetBackdropBorderColor(0, 0, 0, 1)
        end
    else
        -- The Button has no stock textures: MakePlate's clearing loop must not trip on them
        hideButton:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
        hideButton:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
        hideButton:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        hideButton:SetDisabledTexture("Interface\\Buttons\\WHITE8X8")
        MakePlate(hideButton, 120, 27, 12)
        PaintPlate(hideButton, HIDE_PLATE, "rest")
    end
    hideButton:SetFrameLevel(perkMainFrame:GetFrameLevel() + 20)


    local autoShowCB = CreateFrame("CheckButton", "EbonholdAutoShowCheck", perkMainFrame, "ChatConfigCheckButtonTemplate")
    -- Positioned on right card bottom in ShowPerkUI when cards exist
    _G[autoShowCB:GetName() .. 'Text']:SetText("Auto Show Echoes")
    autoShowCB:SetChecked(IsAutoShowEchoesEnabled())
    autoShowCB:SetScript("OnClick", function(self)
        if ProjectEbonholdOptionsService then
            ProjectEbonholdOptionsService:SetSetting("autoShowEchoes", self:GetChecked() and true or false)
        end
    end)
    autoShowCB:Hide()

    chooseButton = CreateFrame("Button", "PerkChooseButton", UIParent)
    chooseButton:SetPoint("TOP", perkMainFrame, "BOTTOM", 0, -10)
    chooseButton:SetFrameStrata("DIALOG")
    chooseButton:SetFrameLevel(perkMainFrame:GetFrameLevel() + 10)
    chooseButton:EnableMouse(true)
    chooseButton:RegisterForClicks("LeftButtonUp")


    if IsTransparentDesign() then
        chooseButton:SetSize(140, 25)

        local chooseButtonText = chooseButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        chooseButtonText:SetPoint("CENTER", chooseButton, "CENTER", 0, 0)
        chooseButtonText:SetText("Select an Echo")
        chooseButtonText:SetTextColor(0.9, 0.9, 0.9)
        chooseButton.text = chooseButtonText

        if chooseButton.SetBackdrop then
            chooseButton:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                tile = true,
                tileSize = 16,
                edgeSize = 2,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            chooseButton:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
            chooseButton:SetBackdropBorderColor(0, 0, 0, 1)
        end

        chooseButton:SetScript("OnEnter", function(self)
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0.4, 0.7, 1.0, 1)
            end
            chooseButtonText:SetTextColor(1, 1, 1)
        end)
        chooseButton:SetScript("OnLeave", function(self)
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0, 0, 0, 1)
            end
            if GetSpecDraw() then chooseButtonText:SetTextColor(unpack(SPEC_GOLD)) else chooseButtonText:SetTextColor(0.9, 0.9, 0.9) end
        end)
    else
        chooseButton:SetSize(250, 120)

        local chooseButtonTexture = chooseButton:CreateTexture(nil, "BACKGROUND")
        chooseButtonTexture:SetAllPoints(chooseButton)
        chooseButtonTexture:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\button_hide_perk")
        chooseButtonTexture:SetTexCoord(0, 1, 0.30, 0.80)

        local chooseButtonText = chooseButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        chooseButtonText:SetPoint("CENTER", chooseButton, "CENTER", 0, 10)
        chooseButtonText:SetText("Select an Echo")
        chooseButtonText:SetTextColor(1, 1, 1)
        chooseButton.text = chooseButtonText

        local chooseGlow = chooseButton:CreateTexture(nil, "ARTWORK")
        chooseGlow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
        chooseGlow:SetBlendMode("ADD")
        chooseGlow:SetPoint("CENTER", chooseButton, "CENTER", 0, 0)
        chooseGlow:SetSize(270, 135)
        chooseGlow:SetVertexColor(0.3, 0.3, 0.3)
        chooseButton.glow = chooseGlow

        local chooseHighlight = chooseButton:CreateTexture(nil, "OVERLAY")
        chooseHighlight:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
        chooseHighlight:SetBlendMode("ADD")
        chooseHighlight:SetPoint("CENTER", chooseButton, "CENTER", 0, 0)
        chooseHighlight:SetSize(300, 150)
        chooseHighlight:SetVertexColor(1, 1, 1)
        chooseHighlight:SetAlpha(0)
        chooseButton.highlight = chooseHighlight

        chooseButton.flameParticles = {}
        local texCoords = {
            { 0.062500, 0.476562, 0.070312, 0.492188 },
            { 0.468750, 0.898438, 0.054688, 0.515625 },
            { 0.117188, 0.484375, 0.484375, 0.898438 },
            { 0.484375, 0.960938, 0.460938, 0.898438 }
        }
        for i = 1, 30 do
            local particle = chooseButton:CreateTexture(nil, "OVERLAY")
            particle:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\texture_glow")
            particle:SetBlendMode("ADD")
            particle:SetSize(40, 40)
            local coordIndex = ((i - 1) % 4) + 1
            local coords = texCoords[coordIndex]
            particle:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            particle:SetVertexColor(0.85, 0.85, 0.85, 0)
            table.insert(chooseButton.flameParticles, {
                texture = particle,
                life = (i - 1) * (2 / 30) + math.random() * 0.05,
                xOffset = (math.random() - 0.5) * 140,
                speed = 30 + math.random() * 20,
                coordIndex = coordIndex
            })
        end

        chooseButton:SetScript("OnUpdate", function(self, elapsed)
            if ProjectEbonhold_IsClosing then return end
            if not self:IsVisible() or not UIParent:IsShown() then return end
            elapsed = math.min(elapsed, 0.1)
            local time = GetTime()
            local basePulse = 0.2 + 0.25 * math.abs(math.sin(time * 0.8))
            if self.isHovering then
                chooseGlow:SetAlpha(basePulse + 0.4)
            else
                chooseGlow:SetAlpha(basePulse)
            end
            local textPulse = 0.7 + 0.3 * math.abs(math.sin(time * 0.8))
            chooseButtonText:SetAlpha(textPulse)

            local particles = self.flameParticles
            for i = 1, #particles do
                local p = particles[i]
                p.life = p.life + elapsed
                if p.life >= 2 then
                    p.life = 0
                    p.xOffset = (math.random() - 0.5) * 140
                    p.speed = 30 + math.random() * 20
                    p.coordIndex = (p.coordIndex % 4) + 1
                    local coords = texCoords[p.coordIndex]
                    p.texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                end
                local progress = p.life / 2
                local yOffset = -25 + progress * 80
                local wave = math.sin(p.life * 4 + i) * 15 * (1 - progress)
                local x = p.xOffset + wave
                -- no ClearAllPoints: CENTER is the particle's only anchor, and setting
                -- the same point again replaces it (30 re-anchors a frame saved)
                p.texture:SetPoint("CENTER", self, "CENTER", x, yOffset)
                local alpha
                if progress < 0.2 then
                    alpha = progress / 0.2
                elseif progress < 0.7 then
                    alpha = 1
                else
                    alpha = 1 - (progress - 0.7) / 0.3
                end
                p.texture:SetAlpha(alpha * 1.3)
                local size = 40 * (1 - progress * 0.5)
                p.texture:SetSize(size, size)
            end
        end)

        chooseButton:SetScript("OnEnter", function(self)
            self.isHovering = true
            chooseHighlight:SetAlpha(0.6)
            chooseGlow:SetVertexColor(0.9, 0.9, 0.9)
        end)
        chooseButton:SetScript("OnLeave", function(self)
            self.isHovering = false
            chooseHighlight:SetAlpha(0)
            -- Back to gold on a spec draw, grey otherwise
            if GetSpecDraw() then chooseGlow:SetVertexColor(1, 0.75, 0.1) else chooseGlow:SetVertexColor(0.3, 0.3, 0.3) end
        end)
    end

    chooseButton:Hide()

    chooseButton:SetScript("OnClick", function()
        local activePerks = {}
        for _, frame in ipairs(perkFramePool) do
            if frame.inUse then table.insert(activePerks, frame) end
        end

        for _, frame in ipairs(activePerks) do
            frame:SetAlpha(1)
            frame:Show()
            frame:EnableMouse(true)
            frame.selectButton:EnableMouse(true)
        end

        ApplyRankGlows()
        RefreshRerollButton()
        ShowRerollButton()
        perkMainFrame.perksHidden = false
        _lastBanishRem = nil
        UpdateFreezeButtons()
        UpdateBanishButtons()
        hideButton.text:SetText("Hide")
        hideButton.text:SetTextColor(0.7, 0.7, 0.7)
        if _G.EbonholdAutoShowCheck then _G.EbonholdAutoShowCheck:Show() end

        chooseButton:Hide()

        ShowMemoryStageWidgets(true)
        ShowSpecDrawWidgets(true)
        if memoryStageShown then rerollButton:Hide() end
        pendingMemoryReveal = false
        -- Every reveal fades the cards in (a carried card that was already on
        -- the table fades along with the others: the row is rebuilt as a whole)
        PlayCardsEntrance(CollectVisibleCards())

        -- First reveal ever: run the guided tour and keep the family hint for
        -- a later prompt (both at once fight over the same screen space)
        if not perkTour:MaybeStart() then
            ShowPerkFamilyHint()
        end

        perkCardsGraceUntil = GetTime() + PERK_CARDS_GRACE_SEC
        FadeFrame(hideButton, 0.3, 0, 1, 0)
    end)

    hideButton:SetScript("OnClick", function()
        perkMainFrame.perksHidden = not perkMainFrame.perksHidden

        local activePerks = {}
        for _, frame in ipairs(perkFramePool) do
            if frame.inUse then table.insert(activePerks, frame) end
        end

        if perkMainFrame.perksHidden then
            for _, frame in ipairs(activePerks) do
                frame:EnableMouse(false)
                frame.selectButton:EnableMouse(false)
                if frame.banishCardButton then frame.banishCardButton:EnableMouse(false) end
                if frame.freezeCardButton then
                    frame.freezeCardButton:Hide(); frame.freezeCardButton:EnableMouse(false)
                end
                frame:SetScript("OnUpdate", nil)
                CancelFade(frame)
                if frame._cardX then
                    frame:ClearAllPoints()
                    frame:SetPoint("CENTER", perkMainFrame, "CENTER", frame._cardX, frame._cardY)
                end
                frame:SetAlpha(0)
                frame:Hide()
            end
            hideButton.text:SetText("Show")
            hideButton.text:SetTextColor(0.7, 0.7, 0.7)
            if _G.EbonholdAutoShowCheck then _G.EbonholdAutoShowCheck:Hide() end
            rerollButton:Hide()
            ShowMemoryStageWidgets(false)
            ShowSpecDrawWidgets(false)
            if perkFamilyHintFrame and perkFamilyHintFrame:IsShown() then
                perkMainFrame._hintWasShown = true
                perkFamilyHintFrame:Hide()
            else
                perkMainFrame._hintWasShown = false
            end
            perkTour:Stop(false)
        else
            for _, frame in ipairs(activePerks) do
                frame:SetAlpha(1)
                frame:Show()
                frame:EnableMouse(true)
                frame.selectButton:EnableMouse(true)
            end

            perkMainFrame.perksHidden = false
            RefreshRerollButton()
            ShowRerollButton()
            ShowMemoryStageWidgets(true)
            ShowSpecDrawWidgets(true)
            if memoryStageShown then rerollButton:Hide() end
            PlayCardsEntrance(CollectVisibleCards())
            _lastBanishRem = nil
            UpdateFreezeButtons()
            UpdateBanishButtons()
            hideButton.text:SetText("Hide")
            hideButton.text:SetTextColor(0.7, 0.7, 0.7)
            if _G.EbonholdAutoShowCheck then _G.EbonholdAutoShowCheck:Show() end
            perkCardsGraceUntil = GetTime() + PERK_CARDS_GRACE_SEC
            if perkTour:MaybeStart() then
                perkMainFrame._hintWasShown = false
            elseif perkMainFrame._hintWasShown and perkFamilyHintFrame then
                perkFamilyHintFrame:Show()
                perkMainFrame._hintWasShown = false
            end
        end
        hideButton.text:SetTextColor(1, 1, 1) -- the cursor is still on it
    end)

    hideButton:SetScript("OnEnter", function()
        hideButton.text:SetTextColor(1, 1, 1)
        if hideButton._plateStock then PaintPlate(hideButton, HIDE_PLATE_HOT, "hover") end
    end)
    hideButton:SetScript("OnLeave", function()
        hideButton.text:SetTextColor(0.7, 0.7, 0.7)
        if hideButton._plateStock then PaintPlate(hideButton, HIDE_PLATE, "rest") end
    end)
end

local function ForceResetPerkUI()
    isFading = false
    isSelecting = false
    isShowingPerkUI = false

    -- FIX: cancel any pending deferred auto-click so a stale click can't fire
    -- into a freshly-reset UI after ForceResetPerkUI is called mid-show.
    autoClickDeferred:SetScript("OnUpdate", nil)
    autoClickDeferred:Hide()

    if perkMainFrame then
        CancelFade(perkMainFrame)
        perkMainFrame:SetAlpha(0)
        perkMainFrame:Hide()
        perkMainFrame.banishPollElapsed = 0
    end

    for _, f in ipairs(perkFramePool) do
        CancelFade(f)
        if f.selectButton then CancelFade(f.selectButton) end
        if f.banishCardButton then CancelFade(f.banishCardButton) end
        if f.freezeCardButton then f.freezeCardButton:Hide() end
        f:SetScript("OnUpdate", nil)
        f:Hide()
        f:SetAlpha(1)
        f:EnableMouse(true)
        f.inUse = false
    end

    if chooseButton then CancelFade(chooseButton) end
    if hideButton then
        CancelFade(hideButton)
    end
    if rerollButton then
        CancelFade(rerollButton)
        rerollButton:Hide()
        rerollButton:SetAlpha(1)
    end
    if perkFamilyHintFrame then perkFamilyHintFrame:Hide() end
    ShowSpecDrawWidgets(false)
    perkTour:Stop(false)
end

ShowPerkFamilyHint = function()
    if ProjectEbonholdDB and ProjectEbonholdDB.perkFamilyHintDismissed then return end

    if not perkFamilyHintFrame then
        perkFamilyHintFrame = CreateFrame("Frame", "PerkFamilyHintFrame", UIParent, "GlowBoxTemplate")
        perkFamilyHintFrame:SetSize(260, 110)
        perkFamilyHintFrame:SetFrameStrata("DIALOG")
        perkFamilyHintFrame:SetFrameLevel(200)
        perkFamilyHintFrame:EnableMouse(true)

        local closeBtn = CreateFrame("Button", nil, perkFamilyHintFrame, "UIPanelCloseButton")
        closeBtn:SetSize(26, 26)
        closeBtn:SetPoint("TOPRIGHT", perkFamilyHintFrame, "TOPRIGHT", -4, -4)
        closeBtn:SetFrameLevel(201)
        closeBtn:SetScript("OnClick", function()
            if ProjectEbonholdDB then ProjectEbonholdDB.perkFamilyHintDismissed = true end
            perkFamilyHintFrame:Hide()
        end)

        local hintText = perkFamilyHintFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
        hintText:SetJustifyV("TOP")
        hintText:SetSize(210, 0)
        hintText:SetPoint("TOPLEFT", perkFamilyHintFrame, "TOPLEFT", 18, -36)
        hintText:SetText("Picking an echo from a family boosts chances of more from that same family.")
        perkFamilyHintFrame.hintText = hintText
    end

    -- Anchor to upper-left of the leftmost perk card
    local card1 = GetCardFrameByIndex(1)
    if card1 then
        local anchor = card1.backdropFrame or card1
        perkFamilyHintFrame:ClearAllPoints()
        perkFamilyHintFrame:SetPoint("BOTTOMRIGHT", anchor, "TOPLEFT", 40, 10)
    else
        perkFamilyHintFrame:ClearAllPoints()
        perkFamilyHintFrame:SetPoint("CENTER", UIParent, "CENTER", -320, 160)
    end

    perkFamilyHintFrame:Show()
end


-- ── Memory stage: the souvenir card ──────────────────────────────────────────
-- A draw on a loadout that remembers a finished build opens with ONE card: a
-- souvenir of that build (choice flag 3). The three random cards are already
-- rolled server-side but hidden. The player either keeps the souvenir (the
-- card's Select button) or gives it up - "Draw" - which sends
-- REQUEST_PERK_MEMORY_DRAW: the souvenir is lost for the climb and the server
-- answers with the three random cards revealed. Three face-down cards stand
-- where those will land, so the choice reads as "this echo, or those three".
local MEMORY_CARD_PITCH = CARD_PITCH
local MEMORY_GAP = 30
-- (memoryDeck / memoryHint / memoryStageShown /
--  pendingMemoryReveal are declared at the top of the file)

function ChoicesAreMemoryStage(choices)
    for _, c in ipairs(choices or {}) do
        if c.isGuaranteed then return true end
    end
    return false
end

-- Card offsets of a full four-slot row (three draws, a gap, the souvenir)
function MemoryRowOffset(slot)
    local x = (slot - 1.5) * MEMORY_CARD_PITCH
    if slot == 3 then x = x + MEMORY_GAP / 2 else x = x - MEMORY_GAP / 2 end
    return x
end

function GetMemoryDeckCard(i)
    if memoryDeck[i] then return memoryDeck[i] end
    local f = CreateFrame("Frame", nil, perkMainFrame)
    f:SetSize(CARD_W, CARD_H)
    f:SetFrameLevel(perkMainFrame:GetFrameLevel() + 1)

    local body = CreateFrame("Frame", nil, f)
    body:SetAllPoints(f)
    f.body = body
    -- The dark backdrop of the transparent design, or the back of a card
    if IsTransparentDesign() then
        body:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            tile = true,
            tileSize = 16,
            edgeSize = 4,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        body:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        body:SetBackdropBorderColor(0, 0, 0, 1)
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\echo_card_back")
        f.bg = bg
    end

    -- A faint swirl and a question mark: an echo not yet revealed
    local swirl = body:CreateTexture(nil, "ARTWORK")
    swirl:SetTexture("Interface\\Cooldown\\star4")
    swirl:SetBlendMode("ADD")
    swirl:SetVertexColor(0.45, 0.55, 0.9, 0.35)
    swirl:SetSize(150, 150)
    swirl:SetPoint("CENTER", f, "CENTER", 0, 0)
    local spin = swirl:CreateAnimationGroup()
    spin:SetLooping("REPEAT")
    local rot = spin:CreateAnimation("Rotation")
    rot:SetDuration(9 + i * 1.5)
    rot:SetDegrees(i % 2 == 0 and 360 or -360)
    rot:SetOrigin("CENTER", 0, 0)
    spin:Play()

    -- The hidden echo: a question-mark icon dressed like a card icon (same
    -- base + ring assets as the real cards, quality 0). MEMORY_DECK_ICON is the
    -- one path to change for another picture.
    local MEMORY_DECK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
    local iconBase = body:CreateTexture(nil, "BACKGROUND", nil, 2)
    iconBase:SetSize(200, 200)
    iconBase:SetPoint("CENTER", f, "CENTER", 0, 0)
    iconBase:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perk_quality_0")
    local mark = body:CreateTexture(nil, "ARTWORK", nil, 1)
    mark:SetSize(42, 42)
    mark:SetPoint("CENTER", f, "CENTER", 0, -4)
    SetPortraitToTexture(mark, MEMORY_DECK_ICON)
    mark:SetDesaturated(true)
    mark:SetVertexColor(0.75, 0.8, 1)
    local ring = body:CreateTexture(nil, "OVERLAY")
    ring:SetSize(200, 200)
    ring:SetPoint("CENTER", f, "CENTER", 0, 0)
    ring:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\perk_border_quality_0")
    f.mark = mark

    -- Click to reveal (after confirmation); hover brightens the halo and explains
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        swirl:SetVertexColor(0.7, 0.8, 1, 0.7)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Hidden echo", 1, 1, 1)
        GameTooltip:AddLine("Click to draw 3 random echoes and pick one.", 1, 1, 1, true)
        GameTooltip:AddLine("|cffff6060You lose the souvenir until you finish the build again.|r", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
        swirl:SetVertexColor(0.45, 0.55, 0.9, 0.35)
        GameTooltip:Hide()
    end)
    f:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        if GetTime() < perkCardsGraceUntil then return end
        if isSelecting or not memoryStageShown then return end
        -- The card row sits on the DIALOG strata at a high level: lift the popup
        -- above it, or the question opens behind the cards it is about
        local dialog = StaticPopup_Show("PROJECTEBONHOLD_MEMORY_DRAW", SouvenirOnTableName())
        if dialog then
            dialog:SetFrameStrata("FULLSCREEN_DIALOG")
            dialog:SetFrameLevel(600)
        end
    end)

    -- Gentle float, each card on its own beat
    local floatGroup = f:CreateAnimationGroup()
    floatGroup:SetLooping("BOUNCE")
    local up = floatGroup:CreateAnimation("Translation")
    up:SetOffset(0, 7)
    up:SetDuration(1.1 + i * 0.2)
    up:SetSmoothing("IN_OUT")
    f.floatGroup = floatGroup

    -- Pulse of the question mark
    local pulse = mark:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local pa = pulse:CreateAnimation("Alpha")
    pa:SetChange(-0.5)
    pa:SetDuration(0.9 + i * 0.15)
    pa:SetSmoothing("IN_OUT")
    pulse:Play()

    memoryDeck[i] = f
    return f
end

function HideMemoryDeck()
    for _, f in ipairs(memoryDeck) do
        if f.floatGroup then f.floatGroup:Stop() end
        f:Hide()
    end
    if memoryHint then memoryHint:Hide() end
end

-- Golden burst played on the souvenir when it is kept
function PlayMemoryKeepBurst(frame)
    if not frame or not frame.iconFrame then return end
    if not frame.memoryBurst then
        local t = frame.iconFrame:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Cooldown\\star4")
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.85, 0.2, 1)
        t:SetPoint("CENTER", frame.iconFrame, "CENTER", 0, 0)
        t:SetSize(60, 60)
        t:Hide()
        local ag = t:CreateAnimationGroup()
        local sc = ag:CreateAnimation("Scale")
        sc:SetScale(4, 4)
        sc:SetDuration(0.45)
        sc:SetOrigin("CENTER", 0, 0)
        local al = ag:CreateAnimation("Alpha")
        al:SetChange(-1)
        al:SetDuration(0.45)
        al:SetSmoothing("OUT")
        ag:SetScript("OnFinished", function() t:Hide() end)
        t.burst = ag
        frame.memoryBurst = t
    end
    frame.memoryBurst:SetAlpha(1)
    frame.memoryBurst:Show()
    frame.memoryBurst.burst:Play()
end

-- The souvenir dissolves (rises, shrinks, tilts, fades) and the draw is
-- requested when the dissolve ends - the reply repaints the row with the
-- random cards, which then flip in.
function PlayMemoryGiveUp(frame)
    if not frame then return end
    if not frame.memoryDissolve then
        local ag = frame:CreateAnimationGroup()
        local tr = ag:CreateAnimation("Translation")
        tr:SetOffset(0, 60)
        tr:SetDuration(0.5)
        tr:SetSmoothing("IN")
        local sc = ag:CreateAnimation("Scale")
        sc:SetScale(0.6, 0.6)
        sc:SetDuration(0.5)
        sc:SetOrigin("CENTER", 0, 0)
        local ro = ag:CreateAnimation("Rotation")
        ro:SetDegrees(-14)
        ro:SetDuration(0.5)
        ro:SetOrigin("CENTER", 0, 0)
        frame.memoryDissolve = ag
    end
    -- Alpha through the OnUpdate fader: an animated alpha would snap back to 1
    -- when the group ends and the card would flash back until the reply lands
    CancelFade(frame)
    FadeFrame(frame, 0.5, 1, 0)
    frame.memoryDissolve:SetScript("OnFinished", function()
        frame:SetAlpha(0)
        pendingMemoryReveal = true
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_MEMORY_DRAW, "")
    end)
    frame.memoryDissolve:Play()
end

-- Gives the souvenir up: the souvenir card dissolves, and the draw request
-- leaves when the dissolve ends (the reply repaints the row with the random
-- cards, which fade in). Called by the confirmation popup.
function RequestMemoryDraw()
    if isSelecting then return end
    isSelecting = true
    local souvenir
    for _, f in ipairs(perkFramePool) do
        if f.inUse then
            f.selectButton:EnableMouse(false)
            f:EnableMouse(false)
            if f._perkData and f._perkData.isGuaranteed then souvenir = f end
        end
    end
    for _, d in ipairs(memoryDeck) do
        d:EnableMouse(false)
        if d:IsShown() and d.floatGroup then d.floatGroup:Stop() end
    end
    if souvenir then
        PlayMemoryGiveUp(souvenir)
    else
        pendingMemoryReveal = true
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PERK_MEMORY_DRAW, "")
    end
end

-- Name of the souvenir on the table, for the confirmation popup
function SouvenirOnTableName()
    for _, f in ipairs(perkFramePool) do
        if f.inUse and f._perkData and f._perkData.isGuaranteed then
            return GetSpellInfo(f._spellId or 0) or "your souvenir"
        end
    end
    return "your souvenir"
end

-- The spec choice holds for the whole run: confirm it. data = { frame, spellId }; a card
-- rerolled while the popup was open is not selected.
StaticPopupDialogs["PROJECTEBONHOLD_SPEC_CONFIRM"] = {
    text = "You are choosing your |cffffd100echo specialization|r.\n\nPick |cffffd100%s|r with |cffffd100%s|r?\n\nThen, every 10 levels, you will be offered three echoes of this specialization. Your talents are not changed.\n\nThis cannot be changed until you accept death.",
    button1 = ACCEPT,
    button2 = CANCEL,
    -- The popup's own background lets the gold banner and rays show through: dim the whole
    -- screen under it (top of DIALOG strata, the popup itself is lifted to FULLSCREEN_DIALOG).
    -- The shade also takes the clicks, so no card is picked while the question is open.
    OnShow = function()
        local info = StaticPopupDialogs["PROJECTEBONHOLD_SPEC_CONFIRM"]
        if not info.shade then
            local shade = CreateFrame("Frame", nil, UIParent)
            shade:SetAllPoints(UIParent)
            shade:SetFrameStrata("DIALOG")
            shade:SetFrameLevel(500)
            shade:EnableMouse(true)
            local tex = shade:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(shade)
            tex:SetTexture(0, 0, 0, 0.85)
            info.shade = shade
        end
        info.shade:Show()
    end,
    OnHide = function()
        local shade = StaticPopupDialogs["PROJECTEBONHOLD_SPEC_CONFIRM"].shade
        if shade then shade:Hide() end
    end,
    OnAccept = function(self, data)
        local f = data and data.frame
        if f and f.inUse and f._spellId == data.spellId and f.DoSelect then f.DoSelect() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Clicking a face-down card asks before revealing: the player has to know the
-- souvenir is the price.
StaticPopupDialogs["PROJECTEBONHOLD_MEMORY_DRAW"] = {
    text = "Reveal the three random echoes?\n\nYour souvenir |cffffd700%s|r is |cffff6060lost for this climb|r: it only comes back once this build is finished again.\n\nYou will then pick one of the three revealed echoes.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() RequestMemoryDraw() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function EnsureMemoryWidgets()
    if memoryHint then return end
    memoryHint = perkMainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    memoryHint:SetPoint("BOTTOM", perkMainFrame, "CENTER", 0, 306)
    memoryHint:SetTextColor(1, 0.82, 0.2)
    memoryHint:SetJustifyH("CENTER")
    memoryHint:SetWidth(760)
end

-- Lays the souvenir stage out: carried cards (if any) and face-down placeholders
-- on the three draw slots, the souvenir on the fourth. Called by ShowPerkUI
-- after the choice frames were acquired.
function LayoutMemoryStage(choices)
    EnsureMemoryWidgets()
    local souvenir, carried = nil, {}
    for _, f in ipairs(perkFramePool) do
        if f.inUse and f._perkData then
            if f._perkData.isGuaranteed then souvenir = f else table.insert(carried, f) end
        end
    end

    for i, f in ipairs(carried) do
        if i <= 3 then PlaceCard(f, MemoryRowOffset(i - 1), CARD_ROW_Y) end
    end
    local deckCount = 0
    for slot = #carried, 2 do
        deckCount = deckCount + 1
        local d = GetMemoryDeckCard(deckCount)
        PlaceCard(d, MemoryRowOffset(slot), CARD_ROW_Y)
        d:SetAlpha(1)
        d:EnableMouse(true)
        d:Show()
    end
    for i = deckCount + 1, #memoryDeck do memoryDeck[i]:Hide() end

    if souvenir then
        PlaceCard(souvenir, MemoryRowOffset(3), CARD_ROW_Y)
    end

    -- Always visible, no hover needed: what the fourth card is and what the choice costs
    memoryHint:SetText("Souvenir from your previous build" ..
        "\n|cffffffffTake it, or give it up to draw 3 random echoes.|r")
end

function ShowMemoryStageWidgets(shown)
    if not memoryStageShown then return end
    if shown then
        -- The placeholders fade in with the cards; their float starts once shown
        for _, d in ipairs(memoryDeck) do
            if d.inStage then
                d:Show()
                if d.floatGroup then d.floatGroup:Stop() end
                PlayCardEntrance(d, function()
                    if d.floatGroup then d.floatGroup:Play() end
                end)
            end
        end
        if memoryHint then memoryHint:Show() end
    else
        for _, d in ipairs(memoryDeck) do
            if d.floatGroup then d.floatGroup:Stop() end
            d:Hide()
        end
        if memoryHint then memoryHint:Hide() end
    end
end

local function ShowPerkUI(choices, isRerollRepopulate)
    if not choices or #choices == 0 then
        return
    end
    if isShowingPerkUI then
        return
    end
    isShowingPerkUI = true
    -- When a reroll comes back and "Reroll auto-repopulates choices" is on,
    -- treat this reveal exactly like Auto Show Echoes: skip the collapsed
    -- "Choose an Echo" step so the new cards replace the old ones in place.
    local repopulateAfterReroll = isRerollRepopulate and ProjectEbonholdOptionsService
        and ProjectEbonholdOptionsService:GetSetting("rerollAutoRepopulate") and true or false
    -- Cards come up expanded straight away.
    local autoReveal = IsAutoShowEchoesEnabled() or repopulateAfterReroll
    -- Nothing comes up but the Show/Hide toggle.
    local quietReveal = (not autoReveal) and not IsEchoesVisibleOnLevelUpEnabled()
    local ok, err = pcall(function()
        ForceResetPerkUI()
        InitializePerkUI()

        perkMainFrame:Show()
        perkMainFrame:SetAlpha(1)

        for _, f in ipairs(perkFramePool) do
            f:Hide()
            f:SetAlpha(1)
            f.inUse = false
        end

        local perkCount = #choices
        -- Souvenir stage: the row is laid out as four slots (three draws + the
        -- souvenir) whatever the number of real cards, see LayoutMemoryStage.
        memoryStageShown = ChoicesAreMemoryStage(choices)
        HideMemoryDeck()
        local layoutCount = memoryStageShown and 4 or perkCount
        local frameWidth = (layoutCount * CARD_PITCH) + 40 + (memoryStageShown and MEMORY_GAP or 0)
        perkMainFrame:SetWidth(frameWidth)

        local remainingBanishes = GetBanishInfo()

        for i, perkData in ipairs(choices) do
            local perkFrame = AcquirePerkFrame(perkMainFrame)
            if not perkFrame then break end
            UpdatePerkFrame(perkFrame, perkData, i - 1)

            -- A slight arc: the further from the middle, the lower. Nothing leans, the client can't turn text.
            local fromMiddle = (i - 1) - ((perkCount - 1) / 2)
            PlaceCard(perkFrame, fromMiddle * CARD_PITCH, CARD_ROW_Y - math.abs(fromMiddle) * CARD_ARC)

            if autoReveal then
                perkFrame:SetAlpha(1)
                CardFx.Start(perkFrame, 0) -- or the finished card shows for one frame before the deal
                perkFrame:Show()
                perkFrame:EnableMouse(true)
                perkFrame.selectButton:EnableMouse(true)
                RefreshRerollButton()
                ShowRerollButton()
                _lastBanishRem = nil
                UpdateFreezeButtons()
                UpdateBanishButtons()
            else
                perkFrame:SetAlpha(0)
                perkFrame:Hide()
                perkFrame:EnableMouse(false)
                perkFrame.selectButton:EnableMouse(false)
            end
        end

        if memoryStageShown then
            LayoutMemoryStage(choices)
            for _, d in ipairs(memoryDeck) do d.inStage = d:IsShown() end
            HideMemoryDeck() -- shown with the cards by the reveal below
        end

        -- Attach "Auto Show Echoes" to bottom of rightmost card (only shown when cards are visible)
        local autoShowCB = _G.EbonholdAutoShowCheck
        local middleCardIndex = math.min(2, perkCount)
        local middleCard = GetCardFrameByIndex(middleCardIndex)
        if autoShowCB and middleCard then
            local anchor = middleCard.backdropFrame or middleCard
            autoShowCB:ClearAllPoints()
            autoShowCB:SetParent(anchor)
            autoShowCB:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -18) -- on the Hide/Show row, below the outer cards
        end

        RefreshRerollButton()
        if not perkMainFrame.perksHidden then
            ShowRerollButton()
        else
            rerollButton:Hide()
        end

        UpdateBanishButtons()
        UpdateFreezeButtons()
        ApplyRankGlows()

        hideButton.text:SetText("Show")
        hideButton.text:SetTextColor(0.7, 0.7, 0.7)
        perkMainFrame.perksHidden = true

        -- The button that opens the draw already says it is the spec draw, in gold
        local specDraw = GetSpecDraw()
        if chooseButton.text then
            if specDraw then
                chooseButton.text:SetText(specDraw.chosen == 0 and "Choose Echo Spec" or "Specialization Echoes")
                chooseButton.text:SetTextColor(unpack(SPEC_GOLD))
            else
                chooseButton.text:SetText("Select an Echo")
                chooseButton.text:SetTextColor(IsTransparentDesign() and 0.9 or 1, IsTransparentDesign() and 0.9 or 1, IsTransparentDesign() and 0.9 or 1)
            end
        end
        if chooseButton.glow then
            if specDraw then chooseButton.glow:SetVertexColor(1, 0.75, 0.1) else chooseButton.glow:SetVertexColor(0.3, 0.3, 0.3) end
        end
        rerollButton:Hide()
        if _G.EbonholdAutoShowCheck then _G.EbonholdAutoShowCheck:Hide() end

        if quietReveal then
            -- Popup suppressed: the Show/Hide toggle stands in for it, and
            -- clicking "Show" runs the exact same reveal path as "Select an
            -- Echo" would have.
            CancelFade(chooseButton)
            chooseButton:Hide()
            CancelFade(hideButton)
            hideButton:SetAlpha(1)
            hideButton:Show()
        else
            -- "Select an Echo" owns the reveal; the Show/Hide toggle only
            -- appears once that button has been clicked.
            hideButton:Hide()
            CancelFade(chooseButton)
            chooseButton:EnableMouse(true)
            chooseButton:SetAlpha(1)
            chooseButton:Show()
        end
    end) -- end pcall

    -- Always release the guard before doing anything else, even if pcall errored.
    isShowingPerkUI = false

    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[Ebonhold] PerkUI error: " .. tostring(err) .. "|r")
        return
    end

    if autoReveal then
        autoClickDeferred:SetScript("OnUpdate", function(self)
            self:SetScript("OnUpdate", nil)
            self:Hide()
            if chooseButton and chooseButton:IsShown() then
                chooseButton:Click()
            end
        end)
        autoClickDeferred:Show()
    end
end

local function HidePerkUI()
    isSelecting = false

    if perkMainFrame and perkMainFrame:IsShown() then
        perkMainFrame:Hide()
        perkMainFrame.banishPollElapsed = 0

        for _, f in ipairs(perkFramePool) do
            if f.inUse then
                f:Hide()
                f:EnableMouse(true)
                if f.banishCardButton then f.banishCardButton:Hide() end
                if f.freezeCardButton then f.freezeCardButton:Hide() end
            end
        end

        if rerollButton then rerollButton:Hide() end
        if hideButton then hideButton:Hide() end
        if chooseButton then chooseButton:Hide() end
        if perkFamilyHintFrame then perkFamilyHintFrame:Hide() end
        HideMemoryDeck()
        memoryStageShown = false
        ShowSpecDrawWidgets(false)
        perkTour:Stop(false)

        isFading = false
    end
end

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.PerkUI = ProjectEbonhold.PerkUI or {}
ProjectEbonhold.PerkUI.Show = ShowPerkUI
ProjectEbonhold.PerkUI.Hide = HidePerkUI
ProjectEbonhold.PerkUI.UpdateSinglePerk = function(perkIndex, perkData)
    if not perkData then return end
    for _, f in ipairs(perkFramePool) do
        if f.inUse and f.perkIndex == perkIndex then
            local newEcho = f._spellId ~= perkData.spellId
            UpdatePerkFrame(f, perkData, perkIndex)
            if newEcho then CardFx.StartFlip(f) end
            UpdateBanishButtons()
            UpdateFreezeButtons()
            return
        end
    end
end
ProjectEbonhold.PerkUI.ApplyRankGlows = ApplyRankGlows
-- Re-evaluate the loadout highlight on visible cards (called by the Echo
-- Journal when the active loadout changes while a choice is on screen)
ProjectEbonhold.PerkUI.RefreshLoadoutHighlights = function()
    for _, f in ipairs(perkFramePool) do
        if f.inUse and f._spellId then
            ApplyLoadoutHighlight(f, f._spellId)
        end
    end
end
ProjectEbonhold.PerkUI.ApplyScale = ApplyPerkUIScale
ProjectEbonhold.PerkUI.ResetSelection = function()
    isSelecting = false
    for _, f in ipairs(perkFramePool) do
        if f.inUse then
            f._fxHiddenUntil = nil -- the pick was refused: the card comes back
            f:EnableMouse(true)
            f.selectButton:EnableMouse(true)
            if f.banishCardButton then f.banishCardButton:EnableMouse(true) end
            if f.freezeCardButton then f.freezeCardButton:EnableMouse(true) end
        end
    end
end

local function PrewarmPool()
    InitializePerkUI()
    for i = 1, 3 do
        local f = AcquirePerkFrame(perkMainFrame)
        f:Hide()
        f.inUse = false
    end
end


local function AddScaleSliderToOptionsPanel()
    -- Scale slider is now handled inside the options scroll frame (options.lua)
end

-- Called by the Orb service whenever the server corrects the owed-offer count, so the three
-- run buttons AND the Reroll button (which switches to the orb on exactly that signal) are
-- repainted together.
local function RefreshBanishText()
    UpdateBanishButtons()
    UpdateFreezeButtons()
    RefreshRerollButton()
end
ProjectEbonhold.PerkUI.RefreshBanishText = RefreshBanishText

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        PrewarmPool()
        ApplyPerkUIScale(GetPerkUIScale())
        AddScaleSliderToOptionsPanel()
        ProjectEbonhold.PerkService.RequestChoice()
    elseif event == "PLAYER_LEVEL_UP" then
        ProjectEbonhold.PerkService.RequestChoice()
    end
end)
