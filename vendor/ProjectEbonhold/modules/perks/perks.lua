local perkMainFrame = nil
local perkFramePool = {}
local hideButton = nil
local rerollButton = nil
local chooseButton = nil
local perkFamilyHintFrame = nil
local ShowPerkFamilyHint
local isFading = false
local isSelecting = false
local isShowingPerkUI = false
local PERK_CARDS_GRACE_SEC = 0.1
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
    [0] = { name = "Common", color = { 1, 1, 1 }, border = 0 },
    [1] = { name = "Uncommon", color = { 0.1, 1.0, 0.1 }, border = 1 },
    [2] = { name = "Rare", color = { 0.0, 0.4, 1.0 }, border = 2 },
    [3] = { name = "Epic", color = { 0.6, 0.2, 1.0 }, border = 3 },
    [4] = { name = "Legendary", color = { 1.0, 0.5, 0.0 }, border = 4 }
}

-- Shared with the journal and the run panel (see utils.PerkFamilyIcons)
local familyIcons = utils.PerkFamilyIcons

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
    },
}

local function ApplyRerollSkin(hovered)
    if not rerollButton then return end

    local skin = rerollButton._orbMode and REROLL_SKIN.orb or REROLL_SKIN.run

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

    ApplyRerollSkin(false)
end

local function GetCardFrameByIndex(cardIndex)
    if not cardIndex or cardIndex < 1 or cardIndex > 3 then return nil end
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
local function GetCardBody(f)
    if f.backdropFrame and f.backdropFrame:IsShown() then return f.backdropFrame end
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
                    "|cffffd700Select|r to claim one; the card's color shows its " ..
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

local FREEZE_FADE_DURATION = 0.45

local function ApplyFreezeVisual(frame, smooth)
    if not frame then return end

    if frame.backdropFrame and frame.backdropFrame.SetBackdropColor then
        frame.backdropFrame:SetBackdropColor(0.06, 0.12, 0.28, 0.95)
        frame.backdropFrame:SetBackdropBorderColor(0.3, 0.55, 0.85, 1)
    end

    if frame.bg then
        if smooth and frame.freezeOverlay then
            frame.freezeOverlay:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\background_one_perk_freeze")
            frame.freezeOverlay:SetAlpha(0)
            frame.freezeOverlay:Show()
            FadeFrame(frame.freezeOverlay, FREEZE_FADE_DURATION, 0, 1, nil, function()
                frame.bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\background_one_perk_freeze")
                frame.freezeOverlay:Hide()
            end)
        else
            frame.bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\background_one_perk_freeze")
            if frame.freezeOverlay then frame.freezeOverlay:Hide() end
        end
    end
end

local function ClearFreezeVisual(frame)
    if not frame then return end
    if frame.backdropFrame and frame.backdropFrame.SetBackdropColor then
        frame.backdropFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        frame.backdropFrame:SetBackdropBorderColor(0, 0, 0, 1)
    end
    if frame.bg then
        frame.bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\background_one_perk")
    end
    if frame.freezeOverlay then
        CancelFade(frame.freezeOverlay)
        frame.freezeOverlay:Hide()
    end
end

local function IsCardFrozen(frame)
    if not frame then return false end
    if frame._locallyFrozen then return true end
    local pd = frame._perkData
    return pd and (pd.isFrozen or pd.isCarried or pd.justFrozen)
end

-- Card injected by the server from the active build slot (choice flag 3):
-- guaranteed to be offered until taken, cannot be banished or frozen.
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
            elseif IsCardFrozen(frame) or IsCardGuaranteed(frame) then
                btn:Show()
                btn:Disable()
                btn:EnableMouse(false)
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
                btn:Show()
                btn:Disable()
                btn:EnableMouse(false)
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
                btn:EnableMouse(false)
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
    frame:SetSize(200, 400)

    -- Original texture (hidden when transparent); visual backdrop is on a separate frame
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\background_one_perk")
    bg:SetTexCoord(0.226562, 0.746094, 0.009766, 0.958984)
    frame.bg = bg

    -- Overlay for smooth freeze crossfade (sits just above bg)
    local freezeOverlay = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    freezeOverlay:SetAllPoints(frame)
    freezeOverlay:SetTexCoord(0.226562, 0.746094, 0.009766, 0.958984)
    freezeOverlay:SetAlpha(0)
    freezeOverlay:Hide()
    frame.freezeOverlay = freezeOverlay

    -- Backdrop frame: only this controls how tall the dark rectangle looks. Frame was 400 so content doesn't overlap.
    local backdropHeight = 320 -- change this to crop the visible backdrop (e.g. 320 = shorter, 360 = taller)
    local backdropFrame = CreateFrame("Frame", nil, frame)
    backdropFrame:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    backdropFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
    backdropFrame:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    backdropFrame:SetHeight(backdropHeight)
    backdropFrame:SetFrameLevel(frame:GetFrameLevel() - 1)
    frame.backdropFrame = backdropFrame

    if IsTransparentDesign() then
        bg:Hide()
        freezeOverlay:Hide()
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
        -- Shrink hit area to match visible backdrop so the invisible top doesn't block Reroll/Hide/checkbox
        local frameHeight = 400
        frame:SetHitRectInsets(0, 0, frameHeight - backdropHeight, 0)
    else
        backdropFrame:Hide()
    end


    local topPerkFrame = CreateFrame("Frame", nil, frame)
    topPerkFrame:SetSize(200, 200)
    topPerkFrame:SetPoint("TOP", frame, "TOP", -5, -140)

    local iconFrame = CreateFrame("Frame", nil, topPerkFrame)
    iconFrame:SetSize(26, 26)
    iconFrame:SetPoint("TOP", topPerkFrame, "TOP", 0, -20)
    frame.iconFrame = iconFrame

    local iconBase = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBase:SetSize(124, 124)
    iconBase:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    frame.iconBase = iconBase

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", iconFrame, "CENTER", 0, -3)
    icon:SetSize(26, 26)
    frame.icon = icon

    local border = iconFrame:CreateTexture(nil, "OVERLAY")
    border:SetSize(124, 124)
    border:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    frame.border = border

    -- Freeze indicator (ice overlay texture)
    local freezeIndicator = iconFrame:CreateTexture(nil, "OVERLAY")
    freezeIndicator:SetSize(50, 50)
    freezeIndicator:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 20, 20)
    freezeIndicator:SetTexture("Interface\\Icons\\Spell_Frost_FrostShock")
    freezeIndicator:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    freezeIndicator:Hide()
    frame.freezeIndicator = freezeIndicator

    -- Freeze status text (shown below name for frozen/carried cards)
    local freezeStatusText = topPerkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    freezeStatusText:SetFont("Fonts\\ARIALN.TTF", 11)
    freezeStatusText:SetPoint("TOP", frame, "TOP", -5, -116)
    freezeStatusText:SetWidth(170)
    freezeStatusText:SetJustifyH("CENTER")
    freezeStatusText:SetTextColor(0.4, 0.7, 1.0)
    freezeStatusText:Hide()
    frame.freezeStatusText = freezeStatusText

    -- ElvUI-style fonts: Friz for titles, Arial Narrow for body
    local nameText = topPerkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 14)
    nameText:SetPoint("TOP", frame, "TOP", -5, -100)
    nameText:SetWidth(170)
    nameText:SetJustifyH("CENTER")
    frame.nameText = nameText

    -- Owned counter: "xN" centered in the gap between title and icon
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
    descText:SetFont("Fonts\\ARIALN.TTF", 12)
    descText:SetPoint("TOP", topPerkFrame, "CENTER", 0, 20)
    descText:SetWidth(140)
    descText:SetHeight(90)
    descText:SetJustifyH("CENTER")
    descText:SetJustifyV("TOP")
    frame.descText = descText

    local familyIconSlots = {}
    for i = 1, 5 do
        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetSize(20, 20)
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        tex:Hide()
        familyIconSlots[i] = tex
    end
    frame.familyIconSlots = familyIconSlots

    -- Invisible blocker behind buttons to prevent card tooltip when moving between them
    local buttonBlocker = CreateFrame("Frame", nil, frame)
    buttonBlocker:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    buttonBlocker:SetSize(140, 100)
    buttonBlocker:SetFrameLevel(frame:GetFrameLevel() + 5)
    buttonBlocker:EnableMouse(true)
    buttonBlocker:SetScript("OnEnter", function() GameTooltip:Hide() end)
    frame.buttonBlocker = buttonBlocker

    local selectButton = utils.CreateSimpleCustomButton(frame, "Select", nil, 130, 29)
    selectButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 90)
    selectButton:SetFrameLevel(buttonBlocker:GetFrameLevel() + 5)
    selectButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Select", 1, 1, 1)
        GameTooltip:AddLine("Choose this perk for your current run.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    selectButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.selectButton = selectButton

    -- Per-card Freeze button (text button below select, mirrors banish style)
    local freezeCardButton = utils.CreateSimpleCustomButton(frame, "Freeze", nil, 130, 29,
        "Interface\\AddOns\\ProjectEbonhold\\assets\\128redbutton9sliced_blue")
    freezeCardButton:SetPoint("TOP", selectButton, "BOTTOM", 0, -5)
    freezeCardButton:SetFrameLevel(buttonBlocker:GetFrameLevel() + 5)
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
            ApplyFreezeVisual(frame, true)
            freezeCardButton:Hide()
            freezeCardButton:EnableMouse(false)
            UpdateFreezeButtons()
            UpdateBanishButtons()
        end
    end)

    frame.freezeCardButton = freezeCardButton

    -- Per-card Banish button (below freeze, purple texture)
    local banishCardButton = utils.CreateSimpleCustomButton(frame, "Banish", nil, 130, 29,
        "Interface\\AddOns\\ProjectEbonhold\\assets\\128redbutton9sliced_purple")
    banishCardButton:SetPoint("TOP", freezeCardButton, "BOTTOM", 0, -5)
    banishCardButton:SetFrameLevel(buttonBlocker:GetFrameLevel() + 5)
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
        isSelecting = true
        for _, f in ipairs(perkFramePool) do
            if f.inUse then
                f.selectButton:EnableMouse(false)
                f:EnableMouse(false)
                if f.banishCardButton then f.banishCardButton:EnableMouse(false) end
                if f.freezeCardButton then f.freezeCardButton:EnableMouse(false) end
            end
        end
        local success = ProjectEbonhold.PerkService.SelectPerk(frame._spellId)
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
    end)

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

    frame:SetScript("OnEnter", function(self)
        local qd = self._qualityData or qualityInfo[0]
        GameTooltip:SetOwner(self.iconFrame, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local sName = GetSpellInfo(self._spellId or 0)
        GameTooltip:AddLine(sName or ("Spell " .. tostring(self._spellId)), qd.color[1], qd.color[2], qd.color[3])
        GameTooltip:AddLine(qd.name, 0.5, 0.5, 0.5)
        if self._perkData and self._perkData.isGuaranteed then
            GameTooltip:AddLine("Guaranteed by your active build slot", 1, 0.82, 0.1)
        end
        local perkDb = ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[self._spellId]
        local familyLine = perkDb and utils.FormatPerkFamilies(perkDb.families)
        if familyLine then
            GameTooltip:AddLine(familyLine, 1, 1, 1)
        end
        local st = self._stacks or 1
        local ms = self._maxStacks or 1
        if st > 1 then
            GameTooltip:AddLine("Stacks: " .. st .. "/" .. ms, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        local description = utils.GetSpellDescription(self._spellId, 500, st)
        GameTooltip:AddLine(description, 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

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
            star:SetPoint("TOPRIGHT", frame.icon, "TOPRIGHT", 8, 8)
            frame.loadoutStar = star
        end
        local iw = frame.icon and frame.icon:GetWidth() or 0
        if iw < 1 then iw = 40 end
        frame.loadoutGlow:SetSize(iw * 2.2, iw * 2.2)
        frame.loadoutOverlay:Show()
    elseif frame.loadoutOverlay then
        frame.loadoutOverlay:Hide()
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
    frame.nameText:SetTextColor(unpack(qualityData.color))
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
    -- Swap card background texture for frozen cards
    if frame.bg then
        if isFrozenCard then
            frame.bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\background_one_perk_freeze")
        else
            frame.bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\background_one_perk")
        end
    end
    local description = utils.GetSpellDescription(spellId, 120)
    frame.descText:SetText(description)

    if frame.familyIconSlots then
        local ICON_SIZE = 20
        local ICON_SPACING = 4
        local perkDb = ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[spellId]
        local familiesToShow = {}
        if perkDb and perkDb.families then
            for _, familyName in ipairs(perkDb.families) do
                if familyIcons[familyName] then
                    table.insert(familiesToShow, familyName)
                end
            end
        end
        local n = #familiesToShow
        local totalWidth = n * ICON_SIZE + math.max(0, n - 1) * ICON_SPACING
        local startX = -(totalWidth / 2) + (ICON_SIZE / 2)
        for i, slot in ipairs(frame.familyIconSlots) do
            if i <= n then
                local xOffset = startX + (i - 1) * (ICON_SIZE + ICON_SPACING)
                slot:ClearAllPoints()
                slot:SetPoint("TOP", frame, "TOP", xOffset, -60)
                slot:SetTexture(familyIcons[familiesToShow[i]])
                slot:Show()
            else
                slot:Hide()
            end
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
    if frame.ownedCountFrame and frame.ownedCountText then
        if count >= 1 then
            frame.ownedCountText:SetText("x" .. tostring(count))
            frame.ownedCountFrame:Show()
        else
            frame.ownedCountFrame:Hide()
        end
    end

    local rollsCount = (ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetPendingRollsCount and ProjectEbonhold.PerkService.GetPendingRollsCount()) or
        0
    frame.selectButton.text:SetText(GetSelectLabel(rollsCount))
    frame.selectButton.text:SetTextColor(1, 1, 1)

    -- Dynamic data stored as frame properties; handlers registered once in AcquirePerkFrame read these.
    frame._spellId = spellId
    frame._perkIndex = perkIndex
    frame._qualityData = qualityData
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

    -- Update freeze status text
    if frame.freezeStatusText then
        frame.freezeStatusText:Hide()
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
    perkMainFrame:SetFrameStrata("DIALOG")
    perkMainFrame:SetFrameLevel(100)
    perkMainFrame:SetSize(800, 280)
    perkMainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    perkMainFrame:SetScale(GetPerkUIScale())
    perkMainFrame:Hide()

    perkMainFrame:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end

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
                    end
                end
            end
            if not self.perksHidden and rerollButton then
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
    -- Red hover glow (manual overlay so it never gets lost; match banish darkness)
    local rerollGlow = rerollButton:CreateTexture(nil, "OVERLAY")
    rerollGlow:SetAllPoints(rerollButton)
    rerollGlow:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    rerollGlow:SetBlendMode("ADD")
    -- Tinted by ApplyRerollSkin: red for the run's reroll, mauve for an orb reroll.
    rerollGlow:SetVertexColor(0.5, 0.14, 0.14, 0.4)
    rerollGlow:Hide()
    rerollButton._rerollGlow = rerollGlow
    if IsTransparentDesign() then
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
    hideButton:SetSize(200, 100)
    hideButton:SetPoint("TOP", perkMainFrame, "BOTTOM", 0, -65)
    hideButton:RegisterForClicks("LeftButtonUp")
    hideButton:Hide()

    if IsTransparentDesign() then
        hideButton:SetSize(120, 25)
        local hideButtonText = hideButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hideButtonText:SetPoint("CENTER", hideButton, "CENTER", 0, 0)
        hideButton.text = hideButtonText
        hideButtonText:SetTextColor(0.7, 0.7, 0.7)
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
        local hideButtonTexture = hideButton:CreateTexture(nil, "BACKGROUND")
        hideButtonTexture:SetAllPoints(hideButton)
        hideButtonTexture:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\button_hide_perk")
        hideButtonTexture:SetTexCoord(0, 1, 0.30, 0.80)

        local glowTexture = hideButton:CreateTexture(nil, "ARTWORK")
        glowTexture:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
        glowTexture:SetBlendMode("ADD")
        glowTexture:SetPoint("CENTER", hideButton, "CENTER", 0, 0)
        glowTexture:SetSize(220, 110)
        glowTexture:SetVertexColor(0.3, 0.3, 0.3, 0.4)
        hideButton.glowTexture = glowTexture

        hideButton.flameParticles = {}
        for i = 1, 12 do
            local particle = hideButton:CreateTexture(nil, "OVERLAY")
            particle:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
            particle:SetBlendMode("ADD")
            particle:SetSize(18, 18)
            particle:SetVertexColor(0.6, 0.6, 0.6, 0)
            table.insert(hideButton.flameParticles, {
                texture = particle,
                life = math.random() * 2,
                xOffset = (math.random() - 0.5) * 80,
                speed = 30 + math.random() * 20
            })
        end

        local hideButtonText = hideButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hideButtonText:SetPoint("CENTER", hideButton, "CENTER", 0, 10)
        hideButton.text = hideButtonText
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
    chooseButton:SetPoint("TOP", perkMainFrame, "BOTTOM", 0, -50)
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
            chooseButtonText:SetTextColor(0.9, 0.9, 0.9)
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
                p.texture:ClearAllPoints()
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
            chooseGlow:SetVertexColor(0.3, 0.3, 0.3)
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
                frame:SetAlpha(0)
                frame:Hide()
            end
            hideButton.text:SetText("Show")
            hideButton.text:SetTextColor(0.7, 0.7, 0.7)
            if _G.EbonholdAutoShowCheck then _G.EbonholdAutoShowCheck:Hide() end
            rerollButton:Hide()
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
    end)

    hideButton:SetScript("OnEnter", function() hideButton.text:SetTextColor(0.7, 0.7, 0.7) end)
    hideButton:SetScript("OnLeave", function() hideButton.text:SetTextColor(1, 1, 1) end)
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
        local frameWidth = (perkCount * 180) + ((perkCount - 1) * 22) + 40
        perkMainFrame:SetWidth(frameWidth)

        local remainingBanishes = GetBanishInfo()

        for i, perkData in ipairs(choices) do
            local perkFrame = AcquirePerkFrame(perkMainFrame)
            if not perkFrame then break end
            UpdatePerkFrame(perkFrame, perkData, i - 1)

            local xOffset = ((i - 1) - ((perkCount - 1) / 2)) * 202
            perkFrame:SetPoint("CENTER", perkMainFrame, "CENTER", xOffset, 100)

            if autoReveal then
                perkFrame:SetAlpha(1)
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

        -- Attach "Auto Show Echoes" to bottom of rightmost card (only shown when cards are visible)
        local autoShowCB = _G.EbonholdAutoShowCheck
        local middleCardIndex = math.min(2, perkCount)
        local middleCard = GetCardFrameByIndex(middleCardIndex)
        if autoShowCB and middleCard then
            local anchor = middleCard.backdropFrame or middleCard
            autoShowCB:ClearAllPoints()
            autoShowCB:SetParent(anchor)
            autoShowCB:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -5)
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
            UpdatePerkFrame(f, perkData, perkIndex)
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
