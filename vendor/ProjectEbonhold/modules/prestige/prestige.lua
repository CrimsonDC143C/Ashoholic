-- ============================================================================
-- Prestige UI: the /progression hub's Prestige tab.
--
-- Layout (per mockup): a big counter circle showing the player's total
-- prestige count, a "Start prestige to get rewards" line with the Prestige
-- button under it, and a bottom strip with the 14 milestone bubbles sitting
-- on a progress bar.
--
-- Created directly as a native child of CollectionsJournal (same pattern as
-- skillTree.lua): this file loads after the Collections shell, so the parent
-- already exists and no reparenting dance is needed. The hub tab that embeds
-- it lives in modules\progression\character_progression.lua (tab 6).
-- ============================================================================

local addonName, addon = ...

if not CollectionsJournal then return end

-- ============================================================================
-- NOTHING IN THIS FILE IS BUILT AT LOAD TIME.
--
-- BuildUI() creates the whole tab -- frame, confirmation dialog, 14 milestone
-- bubbles, the reward preview and its two 3D models, the alert glowbox and the
-- guided tour -- and it runs exactly once, on the first PLAYER_ENTERING_WORLD.
-- Until then the module holds nothing but this closure, so the Prestige tab is
-- paid for once the player is actually in the world, not during addon load
-- alongside every other module.
--
-- There is no ticker and no C_Timer chain anywhere below, and the single
-- OnUpdate is bound only while the player is physically dragging a preview
-- model round. Everything else is driven by something the player did: opening
-- the tab, hovering a bubble, clicking a pager arrow, or a push from the
-- server -- and the refresh those pushes trigger stops at the door while the
-- panel is off screen, which is what used to hitch the client mid-zone.
-- ============================================================================

local uiBuilt = false

local function BuildUI()
    if uiBuilt then return end
    uiBuilt = true

    local PrestigeData = ProjectEbonhold.PrestigeData
    local FormatThousands = ProjectEbonhold.FormatThousands

    local ASSETS = "Interface\\AddOns\\ProjectEbonhold\\assets\\"

    local FRAME_W, FRAME_H = 760, 470

    local frame = CreateFrame("Frame", "EbonholdPrestigeFrame", CollectionsJournal)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("TOP", CollectionsJournal, "TOP", 0, -40)
    frame:SetFrameStrata("HIGH") -- matches CollectionsJournal (same reasoning as skillTreeFrame)
    frame:Hide()

    ------------------------------------------------------------
    -- TOP: counter circle, rank line, tagline, gate line, button
    ------------------------------------------------------------

    -- The whole counter/text/button column sits left of center; the right flank
    -- is a permanently visible reward preview panel (see below).
    local COLUMN_X = -130

    -- Counter circle art: the empty renown circle from the Dragonflight Tuskarr
    -- major-faction atlas (assets\dragonflightmajorfactionstuskarr, 1024x1024).
    -- The sub-rect was measured pixel-exact by scanning the BLP's alpha channel:
    -- the element spans x 706..859, y 285..440 (153x155 px).
    local circle = frame:CreateTexture(nil, "ARTWORK")
    circle:SetTexture(ASSETS .. "dragonflightmajorfactionstuskarr")
    circle:SetTexCoord(706 / 1024, 859 / 1024, 285 / 1024, 440 / 1024)
    circle:SetSize(120, 120)
    circle:SetPoint("TOP", frame, "TOP", COLUMN_X, -34)

    -- Big ornate number: Morpheus (the quest/title font) reads far better at
    -- display sizes than the default number font. Tweak the 40 to resize.
    local countText = frame:CreateFontString(nil, "OVERLAY")
    countText:SetFont("Fonts\\MORPHEUS.TTF", 40, "OUTLINE")
    countText:SetPoint("CENTER", circle, "CENTER", 0, 0)
    countText:SetTextColor(0.98, 0.95, 0.85)
    countText:SetText("0")

    -- Current rank line under the circle (hidden at rank 0): icon + label
    local rankText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankText:SetPoint("TOP", circle, "BOTTOM", 10, -8)

    local rankIconTex = frame:CreateTexture(nil, "OVERLAY")
    rankIconTex:SetSize(20, 20)
    rankIconTex:SetPoint("RIGHT", rankText, "LEFT", -5, 0)

    -- What prestiging actually does, spelled out under the tagline. No separate
    -- unlock-requirement line: the locked button's tooltip and the chat feedback
    -- on a locked click carry the gate numbers.


    -- La carte, en chiffres : ce que le reset brule et ce qu'il rend. Depuis le 2026-09-08 les
    -- cendres ne rendent plus rien, la recompense est l'Essence frappee par les eclats, et c'est
    -- elle qui justifie d'attendre plutot que de prestiger des l'ouverture des portes.

    local descText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    -- Anchor of the WHOLE lower column: the cap line, the deal card and the Prestige button
    -- all hang off this one, so raising it raises everything below. The circle ends at -154
    -- and the rank line just under it at about -176, which is the floor this can be pushed to.
    descText:SetPoint("TOP", frame, "TOP", COLUMN_X, -182)
    descText:SetWidth(430)
    descText:SetJustifyH("CENTER")
    -- One sentence per line instead of a single centred paragraph: this is the last thing a
    -- player reads before prestiging, and the wall of text was being skipped. Everything
    -- below (cap line, deal card, button) hangs off this font string's BOTTOM, so adding or
    -- removing a line moves the whole lower column with it.
    --
    -- A prestige resets the SKILL TREE and the Soul Ashes that paid for it, and nothing else:
    -- the character keeps its level, its run, its echoes, its gear and its quests. It used to
    -- be a full reset back to level 1; if a player still expects that, line 1 is what corrects
    -- them. The ash part is account-wide (committed ashes are the tree's currency, and ashes
    -- banked on an alt would walk straight back into a fresh tree), which is why the LOSE
    -- column says "on EVERY character". Keep all of it in agreement with
    -- PrestigeHandler::HandleDoPrestige.
    descText:SetText(
        "Resets your Skill Tree and consumes every Soul Ash on the account," .. "\n" ..
        "banked or spent, on every character. Banked Shards return as Soul Essence, up to a limit.")
    descText:SetTextColor(0.9, 0.9, 0.9)
    descText:SetSpacing(3)

    -- The ceiling gets its own gold line rather than a clause at the end of the paragraph:
    -- it is a hard rule, not a footnote, and it has to survive being skim-read.
    local capText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    capText:SetPoint("TOP", descText, "BOTTOM", 0, -8)
    capText:SetWidth(430)
    capText:SetJustifyH("CENTER")
    capText:SetText("|cffFFCC00Soul Essence|r buys the Prestige branch, and no prestige takes it back.")
    capText:SetTextColor(0.75, 0.75, 0.75)

    local dealFrame = CreateFrame("Frame", nil, frame)
    dealFrame:SetSize(420, 42)
    dealFrame:SetPoint("TOP", capText, "BOTTOM", 0, -12)
    dealFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    dealFrame:SetBackdropColor(0.05, 0.04, 0.03, 0.9)
    dealFrame:SetBackdropBorderColor(0.95, 0.78, 0.25)
    dealFrame:Hide()

    -- Left half: what the reset burns.
    local dealCost = dealFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dealCost:SetPoint("LEFT", dealFrame, "LEFT", 12, 0)
    dealCost:SetWidth(196)
    dealCost:SetJustifyH("LEFT")

    -- Hairline divider, so the two halves read as cost and reward.
    local dealSep = dealFrame:CreateTexture(nil, "ARTWORK")
    dealSep:SetTexture(1, 1, 1, 1)
    dealSep:SetSize(1, 24)
    dealSep:SetPoint("CENTER", dealFrame, "CENTER", 6, 0)
    dealSep:SetGradientAlpha("VERTICAL", 0.95, 0.78, 0.25, 0, 0.95, 0.78, 0.25, 0.5)

    -- Right half: the Soul Essence the reset mints.
    local dealGain = dealFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dealGain:SetPoint("RIGHT", dealFrame, "RIGHT", -12, 0)
    dealGain:SetWidth(196)
    dealGain:SetJustifyH("RIGHT")

    -- Second row: the Soul Shards the prestige consumes become Soul Essence, at the rate of GetShardsPerEssence.
    -- Shown only when there are shards to convert; the card grows to fit.
    local dealEssence = dealFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dealEssence:SetPoint("TOP", dealFrame, "TOP", 0, -30)
    dealEssence:SetWidth(396)
    dealEssence:SetJustifyH("CENTER")
    dealEssence:Hide()
    local SHARD_ICON = "|TInterface\\Icons\\inv_10_jewelcrafting3_soulcage_frost:14:14|t"
    local ESSENCE_ICON = "|TInterface\\Icons\\inv_misc_supersoulash:14:14|t"
    -- La carte tient sur UNE ligne : les eclats consommes et l'essence qu'ils frappent. Les
    -- cendres detruites n'y figurent plus, elles n'achetent rien et le chiffre vit deja dans
    -- le paragraphe du dessus et dans l'infobulle de la carte.
    local function ShowEssenceDeal()
        local _, essence = ProjectEbonhold.PrestigeService.GetPendingEssence()
        local shards = ProjectEbonhold.PrestigeService.GetShardsConsumed()
        dealCost:Hide()
        dealGain:Hide()
        dealSep:Hide()
        dealEssence:ClearAllPoints()
        dealEssence:SetPoint("CENTER", dealFrame, "CENTER", 0, 0)
        dealEssence:SetText(SHARD_ICON .. " |cffFF6060" .. FormatThousands(shards) ..
            "|r Soul Shards |TInterface\\CHATFRAME\\ChatFrameExpandArrow:14:14|t " ..
            ESSENCE_ICON .. " |cff33FF33+" .. FormatThousands(essence) .. "|r Soul Essence")
        dealEssence:Show()
        dealFrame:SetHeight(42)
    end

    -- The card states the deal; the tooltip explains the rule behind it, so a
    -- player wondering "why this number" gets the answer without leaving the tab.
    -- Figures come from the last Refresh (stored on the frame) so the tooltip can
    -- never disagree with the line it hangs off.
    dealFrame:EnableMouse(true)
    dealFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Prestige reward", 1, 0.82, 0)
        GameTooltip:AddLine(
            "Every Soul Ash you have committed is destroyed. Your banked Soul Shards are " ..
            "consumed and mint Soul Essence, the only currency a prestige never takes back.",
            1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Soul Ashes destroyed",
            FormatThousands(self.destroyed or 0), 0.9, 0.9, 0.9, 1, 0.4, 0.4)
        do
            local banked, essence = ProjectEbonhold.PrestigeService.GetPendingEssence()
            local shards = ProjectEbonhold.PrestigeService.GetShardsConsumed()
            GameTooltip:AddDoubleLine("Soul Shards consumed",
                FormatThousands(shards), 0.9, 0.9, 0.9, 1, 0.4, 0.4)
            if banked > shards then
                GameTooltip:AddDoubleLine("Soul Shards staying banked",
                    FormatThousands(banked - shards), 0.9, 0.9, 0.9, 0.2, 1, 0.2)
            end
            GameTooltip:AddDoubleLine("Soul Essence (" .. FormatThousands(ProjectEbonhold.PrestigeService.GetShardsPerEssence()) .. " shards each)",
                "+" .. FormatThousands(essence), 0.9, 0.9, 0.9, 0.2, 1, 0.2)
        end
        GameTooltip:Show()
        GameTooltip:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
        GameTooltip:SetBackdropBorderColor(0.95, 0.78, 0.25)
    end)
    dealFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ------------------------------------------------------------
    -- Prestige confirmation: custom dialog. StaticPopup was unfit for this
    -- content: translucent backdrop bleeding the frame behind through the text,
    -- and a narrow fixed width that turned the list into a cramped wall. This
    -- one is opaque, wide, bullet-pointed in two columns, and gated by an
    -- "I confirm" checkbox that unlocks the red button.
    ------------------------------------------------------------

    local confirm = CreateFrame("Frame", "EbonholdPrestigeConfirmFrame", UIParent)
    confirm:SetSize(470, 400)
    confirm:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    confirm:SetFrameStrata("FULLSCREEN_DIALOG")
    confirm:EnableMouse(true)
    confirm:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    confirm:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    confirm:SetBackdropBorderColor(0.95, 0.78, 0.25)
    confirm:Hide()
    tinsert(UISpecialFrames, "EbonholdPrestigeConfirmFrame") -- ESC closes it

    local cTitle = confirm:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cTitle:SetPoint("TOP", confirm, "TOP", 0, -16)
    cTitle:SetText("Prestige now?")

    -- The trade in numbers, right under the title: burning a bigger pool buys a
    -- bigger permanent bonus, so the player sees exactly what this reset is worth
    -- before ticking the box.
    local cDeal = confirm:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cDeal:SetPoint("TOP", cTitle, "BOTTOM", 0, -6)
    cDeal:SetWidth(430)
    cDeal:SetJustifyH("CENTER")

    local eraseHeader = confirm:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    eraseHeader:SetPoint("TOPLEFT", confirm, "TOPLEFT", 28, -78)
    eraseHeader:SetText("This will ERASE")
    eraseHeader:SetTextColor(1, 0.25, 0.25)

    local eraseList = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    eraseList:SetPoint("TOPLEFT", eraseHeader, "BOTTOMLEFT", 0, -8)
    eraseList:SetWidth(205)
    eraseList:SetJustifyH("LEFT")
    eraseList:SetSpacing(4)
    eraseList:SetText(
        "\226\128\162 ALL Soul Ashes, banked or spent,\n   on EVERY character\n" ..
        "\226\128\162 Your banked Soul Shards\n   (turned into Soul Essence)\n" ..
        "\226\128\162 Skill Tree nodes without\n   Carry over Prestige")

    local keepHeader = confirm:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keepHeader:SetPoint("TOPLEFT", confirm, "TOPLEFT", 258, -78)
    keepHeader:SetText("You KEEP")
    keepHeader:SetTextColor(0.3, 1, 0.3)

    local keepList = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    keepList:SetPoint("TOPLEFT", keepHeader, "BOTTOMLEFT", 0, -8)
    keepList:SetWidth(190)
    keepList:SetJustifyH("LEFT")
    keepList:SetSpacing(4)
    keepList:SetText(
        "\226\128\162 Your level and your current run\n" ..
        "\226\128\162 Your gear, talents and professions\n" ..
        "\226\128\162 ALL your Echoes,\n   permanent or not\n" ..
        "\226\128\162 Your learned Tomes of Echo\n" ..
        "\226\128\162 Carry over Prestige nodes,\n   kept and permanently free\n" ..
        "\226\128\162 Endless nodes and all their ranks\n" ..
        "\226\128\162 Your Echo builds, untouched\n" ..
        "\226\128\162 Your Soul Essence and Artisan Souls\n" ..
        "\226\128\162 Milestone rewards earned")

    -- "I confirm" gate: the red button stays locked until the box is ticked,
    -- re-armed unchecked every time the dialog opens.
    local cCheck = CreateFrame("CheckButton", "EbonholdPrestigeConfirmCheck", confirm, "UICheckButtonTemplate")
    cCheck:SetSize(28, 28)
    cCheck:SetPoint("BOTTOM", confirm, "BOTTOM", -52, 54)
    local cCheckLabel = _G["EbonholdPrestigeConfirmCheckText"]
    cCheckLabel:SetFontObject(GameFontNormalLarge)
    cCheckLabel:SetText("I confirm")

    local cConfirmBtn = utils.CreateSimpleCustomButton(confirm, "Prestige",
        function()
            EbonholdPrestigeConfirmFrame:Hide()
            ProjectEbonhold.PrestigeService.DoPrestige()
        end, 170, 34)
    cConfirmBtn:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -10, 14)

    local cCancelBtn = utils.CreateSimpleCustomButton(confirm, "Cancel",
        function() EbonholdPrestigeConfirmFrame:Hide() end, 130, 34,
        "Interface\\AddOns\\ProjectEbonhold\\assets\\128redbutton9sliced_blue")
    cCancelBtn:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 10, 14)

    local function UpdateConfirmGate()
        if cCheck:GetChecked() then
            cConfirmBtn:Enable()
            cConfirmBtn:SetTextColor(1, 1, 1)
        else
            cConfirmBtn:Disable()
            cConfirmBtn:SetTextColor(0.55, 0.55, 0.55)
        end
    end
    cCheck:SetScript("OnClick", UpdateConfirmGate)
    confirm:SetScript("OnShow", function()
        cCheck:SetChecked(false)
        UpdateConfirmGate()

        local destroyed = ProjectEbonhold.PrestigeService.GetPendingPrestigeGain()
        if destroyed > 0 then
            local _, essence = ProjectEbonhold.PrestigeService.GetPendingEssence()
            local shards = ProjectEbonhold.PrestigeService.GetShardsConsumed()
            cDeal:SetText("|cffFF4444" .. FormatThousands(destroyed) .. "|r Soul Ashes destroyed" ..
                (shards > 0 and ("\n|cffFF4444" .. FormatThousands(shards) ..
                    "|r Soul Shards consumed, |cff33FF33+" .. FormatThousands(essence) ..
                    "|r Soul Essence") or ""))
        else
            cDeal:SetText("")
        end
    end)

    -- The addon's 9-sliced red button (normal/pushed/disabled states baked into
    -- the texture), same as the perks/shop buttons.
    local prestigeButton = utils.CreateSimpleCustomButton(frame, "Prestige",
        function() confirm:Show() end, 170, 34)
    prestigeButton:SetPoint("TOP", capText, "BOTTOM", 0, -14)

    -- Gold pulse while a prestige is actually available. The tab is often left
    -- open on a locked button, so this is what says something can be done now;
    -- it stops the instant the gate closes again.
    --
    -- The button BREATHES instead of wearing anything: its own 9-sliced art,
    -- drawn a second time additively over itself. Nothing is added around the
    -- shape, so there is no halo to smear and no frame to box it in, and the
    -- ARTWORK layer keeps it under the label.
    local prestigeGlow = prestigeButton:CreateTexture(nil, "ARTWORK")
    prestigeGlow:SetAllPoints(prestigeButton)
    prestigeGlow:SetTexture(ASSETS .. "128redbutton9sliced")
    prestigeGlow:SetTexCoord(0.006, 0.916, 0.514, 0.756)
    prestigeGlow:SetBlendMode("ADD")
    prestigeGlow:SetVertexColor(1, 0.5, 0.15)
    prestigeGlow:SetAlpha(0)
    prestigeGlow:Hide()

    local prestigeGlowPulse = prestigeGlow:CreateAnimationGroup()
    prestigeGlowPulse:SetLooping("REPEAT")
    local glowUp = prestigeGlowPulse:CreateAnimation("Alpha")
    glowUp:SetChange(0.4)
    glowUp:SetDuration(0.9)
    glowUp:SetOrder(1)
    glowUp:SetSmoothing("OUT")
    local glowDown = prestigeGlowPulse:CreateAnimation("Alpha")
    glowDown:SetChange(-0.4)
    glowDown:SetDuration(0.9)
    glowDown:SetOrder(2)
    glowDown:SetSmoothing("IN")

    -- Disabled buttons receive no mouse events on 3.3.5, so the "why is this
    -- locked" tooltip lives on an invisible overlay shown only while disabled.
    local buttonOverlay = CreateFrame("Frame", nil, frame)
    buttonOverlay:SetAllPoints(prestigeButton)
    buttonOverlay:SetFrameLevel(prestigeButton:GetFrameLevel() + 5)
    buttonOverlay:EnableMouse(true)
    buttonOverlay:SetScript("OnEnter", function(self)
        local svc = ProjectEbonhold.PrestigeService
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Prestige locked", 1, 0.2, 0.2)
        -- Deux portes : les cendres engagees, et de quoi frapper une Soul Essence. On nomme
        -- celle qui manque, et on montre les deux compteurs pour situer l'autre.
        local missingShards = svc.GetMissingShards and svc.GetMissingShards() or 0
        if svc.GetGateProgress() < svc.GetGateThreshold() then
            GameTooltip:AddLine(
                "Commit enough Soul Ashes to your Skill Tree to unlock prestige.",
                1, 1, 1, true)
        else
            GameTooltip:AddLine(
                "Bank enough Soul Shards first: a prestige has to mint at least one " ..
                "Soul Essence, or it would give you nothing at all.", 1, 1, 1, true)
        end
        GameTooltip:AddLine(
            "Committed Soul Ashes: " ..
            FormatThousands(svc.GetGateProgress()) ..
            " / " .. FormatThousands(svc.GetGateThreshold()),
            0.8, 0.8, 0.8)
        GameTooltip:AddLine(
            "Banked Soul Shards: " ..
            FormatThousands(select(1, svc.GetPendingEssence())) ..
            " / " .. FormatThousands(svc.GetShardsPerEssence()),
            0.8, 0.8, 0.8)
        GameTooltip:Show()
        GameTooltip:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
        GameTooltip:SetBackdropBorderColor(0.95, 0.78, 0.25)
    end)
    buttonOverlay:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Clicking the locked button gives chat feedback instead of doing nothing
    -- (the overlay eats the click), and re-requests fresh gate data in case the
    -- lock comes from a stale progress value.
    buttonOverlay:SetScript("OnMouseDown", function()
        local svc = ProjectEbonhold.PrestigeService
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffFF9900[Prestige] Locked: " ..
            FormatThousands(svc.GetGateProgress()) .. " / " ..
            FormatThousands(svc.GetGateThreshold()) ..
            " Soul Ashes committed to the Skill Tree.|r")
        svc.RequestPrestigeData()
    end)

    ------------------------------------------------------------
    -- "Prestige available" alert: the tutorial-style glowbox (arrow + close
    -- button, same template as the micro-button alerts), parked beside the
    -- hub's Prestige tab so the callout sits on the very thing it is asking
    -- the player to click. Shown once per gate crossing: dismissed by the
    -- close button or by opening the Prestige tab, re-armed when the gate
    -- closes again (after a prestige).
    ------------------------------------------------------------

    -- Parented to the journal, not UIParent: the tab it points at is only on
    -- screen while the journal is open, so the parent's own visibility carries
    -- the alert and there is no journal show/hide to track separately.
    local alert = CreateFrame("Frame", "EbonholdPrestigeAlert", CollectionsJournal,
        "MicroButtonAlertTemplate")
    alert:SetFrameStrata("DIALOG") -- over the journal (HIGH), like the shell's own help boxes
    alert.label = "You have enough Soul Ashes to Prestige! Open the Prestige tab to claim it."
    -- The template's OnLoad already ran inside CreateFrame (before .label was
    -- set), so the text must be applied explicitly.
    MicroButtonAlert_SetText(alert, alert.label)

    -- The template's arrow points DOWN: it was drawn for an alert floating above
    -- a micro button. Sitting to the right of a tab it has to point LEFT, which
    -- is the same 90 degree texture rotation (and the same offsets) that
    -- CollectionsJournal's own TransmogTabHelpBox applies to this exact arrow
    -- template in Blizzard_Collections.xml.
    alert.Arrow:ClearAllPoints()
    alert.Arrow:SetPoint("RIGHT", alert, "LEFT", 36, 16)
    SetClampedTextureRotation(alert.Arrow.Arrow, 90)
    SetClampedTextureRotation(alert.Arrow.Glow, 90)
    alert.Arrow.Glow:ClearAllPoints()
    alert.Arrow.Glow:SetPoint("CENTER", alert.Arrow.Arrow, "CENTER", -4, 0)

    local alertDismissed = false
    -- The template's stock OnHide belongs to the micro-button alert priority
    -- system: it walks other alerts and indexes their .MicroButton field, which
    -- the shell's alerts never set (nil-index error). It is REPLACED, not
    -- hooked, and replaced with a no-op rather than with the dismissal memo:
    -- now that the journal is the parent, OnHide also fires every time the
    -- player merely closes the window, which is not an acknowledgement. Only
    -- the two real dismissals below set the flag.
    alert:SetScript("OnHide", function() end)
    alert.CloseButton:HookScript("OnClick", function() alertDismissed = true end)

    -- Opening the Prestige tab is the other acknowledgement. This is hooked onto
    -- the frame further down, AFTER its OnShow handler is installed: a
    -- HookScript here would be wiped by the SetScript that binds Refresh.
    local function DismissPrestigeAlert()
        alertDismissed = true
        alert:Hide()
    end

    local function MaybeShowPrestigeAlert(canPrestige)
        if not canPrestige then
            alert:Hide()
            alertDismissed = false -- re-arm for the next gate crossing
            return
        end
        if alertDismissed or alert:IsShown() or frame:IsShown() then return end
        -- Tab 6 is created by character_progression.lua, which loads after this
        -- file. Anything that can reach here runs long after both, but the
        -- lookup stays late and guarded like every other cross-file reference.
        local tab = _G.CollectionsJournalTab6
        if not tab or not CollectionsJournal:IsShown() then return end
        alert:ClearAllPoints()
        alert:SetPoint("LEFT", tab, "RIGHT", 12, 0)
        alert:Show()
    end

    ------------------------------------------------------------
    -- BOTTOM STRIP: separator, milestone bubbles, progress bar
    ------------------------------------------------------------

    -- Separator: thin gold line fading out toward both edges (two mirrored
    -- gradient halves; 3.3.5 solid-color SetTexture + SetGradientAlpha)
    local sepLeft = frame:CreateTexture(nil, "ARTWORK")
    sepLeft:SetTexture(1, 1, 1, 1)
    sepLeft:SetSize((FRAME_W - 40) / 2, 1)
    sepLeft:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", 0, 118)
    sepLeft:SetGradientAlpha("HORIZONTAL", 0.95, 0.78, 0.25, 0, 0.95, 0.78, 0.25, 0.45)

    local sepRight = frame:CreateTexture(nil, "ARTWORK")
    sepRight:SetTexture(1, 1, 1, 1)
    sepRight:SetSize((FRAME_W - 40) / 2, 1)
    sepRight:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 0, 118)
    sepRight:SetGradientAlpha("HORIZONTAL", 0.95, 0.78, 0.25, 0.45, 0.95, 0.78, 0.25, 0)

    local BAR_W, BAR_H = 690, 42
    -- Same source texture + inner-channel insets as the skill tree progress bar
    -- (assets\progression_bar; asymmetric caps, see skillTree.lua)
    local barTexHeight = 512 * (0.113281 - 0.031250)
    local fillInsetLeft = 18
    local fillInsetRight = 38
    local maxFillWidth = BAR_W - fillInsetLeft - fillInsetRight

    local barFrame = CreateFrame("Frame", nil, frame)
    barFrame:SetSize(BAR_W, BAR_H)
    barFrame:SetPoint("BOTTOM", frame, "BOTTOM", 0, 18)

    local barBg = barFrame:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture(ASSETS .. "progression_bar")
    barBg:SetTexCoord(0.015625, 0.978516, 0.031250, 0.113281)
    barBg:SetSize(BAR_W, barTexHeight)
    barBg:SetPoint("CENTER", barFrame, "CENTER", 0, 0)

    local fillBar = barFrame:CreateTexture(nil, "ARTWORK")
    fillBar:SetTexture(ASSETS .. "progression_bar")
    fillBar:SetTexCoord(0.021484, 0.435547, 0.201172, 0.230469)
    fillBar:SetPoint("LEFT", barBg, "LEFT", fillInsetLeft, 2)
    fillBar:SetHeight(barTexHeight - 25)

    local barText = barFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    barText:SetPoint("CENTER", barFrame, "CENTER", 0, 0)
    barText:SetTextColor(1, 1, 1)

    ------------------------------------------------------------
    -- Milestone bubbles (one per milestone, sitting above the bar)
    ------------------------------------------------------------

    local BUBBLE_SIZE = 30

    -- Compact reward lines: one line per reward with its icon in front. The
    -- 8-piece set contents are deliberately NOT enumerated; the set name plus
    -- the 3D preview carry that information without the wall of text.
    local function AddRewardLinesToTooltip(ms)
        local hasAny = false

        -- One line per item reward, capped so a many-set milestone (e.g. every
        -- vanilla PvP set) does not turn the tooltip into a wall again; the
        -- preview panel's pager is the place to browse them all.
        local rewards = PrestigeData.GetRewardItems(ms)
        local MAX_REWARD_LINES = 6
        for i, item in ipairs(rewards) do
            if i > MAX_REWARD_LINES then
                GameTooltip:AddLine(
                    "...and " .. (#rewards - MAX_REWARD_LINES) ..
                    " more (browse them in the preview)", 0.6, 0.6, 0.6)
                break
            end
            if item.type == "mount" and (item.itemID or 0) > 0 then
                local name = item.name
                if not name or name == "" then
                    name = GetItemInfo(item.itemID) or ("Item #" .. item.itemID)
                end
                local icon = GetItemIcon and GetItemIcon(item.itemID)
                GameTooltip:AddLine(
                    (icon and ("|T" .. icon .. ":16:16|t ") or "") ..
                    "Mount: " .. name, 0.4, 0.8, 1)
                hasAny = true
            elseif item.type == "weapon" and (item.itemID or 0) > 0 then
                local name = item.name
                if not name or name == "" then
                    name = GetItemInfo(item.itemID) or ("Item #" .. item.itemID)
                end
                local icon = GetItemIcon and GetItemIcon(item.itemID)
                GameTooltip:AddLine(
                    (icon and ("|T" .. icon .. ":16:16|t ") or "") ..
                    "Weapon: " .. name, 1, 0.6, 0.2)
                hasAny = true
            elseif item.type == "transmogSet" and item.items and #item.items > 0 then
                local name = item.name
                if not name or name == "" then name = "Transmog set" end
                local icon = GetItemIcon and GetItemIcon(item.items[1])
                GameTooltip:AddLine(
                    (icon and ("|T" .. icon .. ":16:16|t ") or "") ..
                    "Full set: " .. name ..
                    " |cffaaaaaa(" .. #item.items .. " pieces)|r", 0.4, 0.8, 1)
                hasAny = true
            end
        end

        if ms.title and ms.title.name and ms.title.name ~= "" then
            GameTooltip:AddLine("Title: " .. ms.title.name, 0.9, 0.6, 1)
            hasAny = true
        end

        if ms.rankIcon then
            GameTooltip:AddLine(
                "|T" .. ms.rankIcon .. ":16:16|t Chat rank icon", 1, 0.82, 0)
            hasAny = true
        end

        if ms.unlock then
            GameTooltip:AddLine("Also unlocks: " .. ms.unlock, 1, 0.82, 0)
            hasAny = true
        end

        if not hasAny then
            GameTooltip:AddLine("Rewards to be announced.", 0.6, 0.6, 0.6)
        end
    end

    ------------------------------------------------------------
    -- Reward preview: a FIXED panel on the right flank (never floats over the
    -- content). It always shows a reward: the next milestone's by default, the
    -- hovered bubble's while hovering. Mounts render on a PlayerModel via the
    -- same Hide/SetPosition/Show/SetCreature(creatureID) sequence the Mount
    -- Journal uses on this client; transmog sets are tried on a DressUpModel
    -- of the player.
    ------------------------------------------------------------

    local PREVIEW_W, PREVIEW_H = 240, 310

    local preview = CreateFrame("Frame", nil, frame)
    preview:SetSize(PREVIEW_W, PREVIEW_H)
    preview:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -26)
    preview:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    preview:SetBackdropColor(0.03, 0.03, 0.05, 0.95)
    preview:SetBackdropBorderColor(0.95, 0.78, 0.25)

    preview.header = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    preview.header:SetPoint("TOP", preview, "TOP", 0, -10)

    preview.title = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview.title:SetPoint("TOP", preview.header, "BOTTOM", 0, -2)
    preview.title:SetWidth(PREVIEW_W - 20)

    local mountModel = CreateFrame("PlayerModel", nil, preview)
    mountModel:SetPoint("TOPLEFT", preview, "TOPLEFT", 6, -44)
    mountModel:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -6, 28)

    local dressModel = CreateFrame("DressUpModel", nil, preview)
    dressModel:SetPoint("TOPLEFT", preview, "TOPLEFT", 6, -44)
    dressModel:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -6, 28)

    -- Drag-rotation: hold left click on the model and move the mouse sideways,
    -- same feel as the Mount Journal / dressing room models. The scroll wheel
    -- zooms (up = closer, down = further back) by sliding the model along the
    -- camera axis with SetPosition; each render resets to the default framing
    -- (SetPosition(0, 0, 0) + self.zoom = 0).
    --
    -- The rotation handler is BOUND ON MOUSE DOWN AND UNBOUND ON MOUSE UP, not
    -- left installed with an early return inside it. Dragging a model is the
    -- only thing in this whole module that genuinely needs a per-frame script,
    -- and this way it is the only thing that has one, for exactly as long as
    -- the button is held.
    local ROTATION_PER_PIXEL = 0.015
    local ZOOM_STEP = 0.5
    local function DragRotate(self)
        local x = GetCursorPosition()
        self:SetFacing((self:GetFacing() or 0) +
            (x - (self.prevCursorX or x)) * ROTATION_PER_PIXEL)
        self.prevCursorX = x
    end
    local function StopDragRotate(self)
        self:SetScript("OnUpdate", nil)
    end
    local function EnableDragRotation(model, zoomMin, zoomMax)
        model.zoomMin, model.zoomMax = zoomMin, zoomMax
        model:EnableMouse(true)
        model:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                self.prevCursorX = GetCursorPosition()
                self:SetScript("OnUpdate", DragRotate)
            end
        end)
        model:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then StopDragRotate(self) end
        end)
        -- Releasing the button off the model (or the panel closing mid-drag)
        -- never delivers OnMouseUp, so the hide is a second way out.
        model:SetScript("OnHide", StopDragRotate)
        model:EnableMouseWheel(true)
        model:SetScript("OnMouseWheel", function(self, delta)
            self.zoom = math.max(self.zoomMin, math.min(self.zoomMax,
                (self.zoom or 0) + delta * ZOOM_STEP))
            self:SetPosition(self.zoom, 0, 0)
        end)
    end
    -- A mount fills the pane slower than a humanoid, so the character view
    -- (transmog sets / weapons) gets tighter bounds than the mount view.
    EnableDragRotation(mountModel, -2.5, 1)
    EnableDragRotation(dressModel, -1.5, 0.5)

    -- Pager: a milestone can grant SEVERAL item rewards (items = { ... } in
    -- prestige_data.lua, e.g. every vanilla PvP set); the arrows page the
    -- preview through them, with a "current / total" readout between them.
    preview.pagerText = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    preview.pagerText:SetPoint("BOTTOM", preview, "BOTTOM", 0, 13)

    preview.prevBtn = CreateFrame("Button", nil, preview)
    preview.prevBtn:SetSize(26, 26)
    preview.prevBtn:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 10, 7)
    preview.prevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    preview.prevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    preview.prevBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    preview.nextBtn = CreateFrame("Button", nil, preview)
    preview.nextBtn:SetSize(26, 26)
    preview.nextBtn:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -10, 7)
    preview.nextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    preview.nextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    preview.nextBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    -- Mount models depend on the client's local creature cache on this build:
    -- SetCreature(creatureID) renders nothing when the creature has never been
    -- cached, and the client cannot query one itself -- the server has to push it
    -- (REQUEST_CREATURE_CACHE, answered with a creature-query response the client
    -- then keeps for good).
    --
    -- NO RETRY LOOP. This used to chain up to six C_Timer.After calls per preview
    -- to poll GetModel() until the answer landed, and on this client every
    -- C_Timer.After allocates a brand-new Frame with its own OnUpdate (see the
    -- polyfill in modules\utils.lua) -- frames a WoW client never frees. Sweeping
    -- the mouse along the milestone bar leaked dozens of them per pass, each
    -- running a script every frame for the rest of the session.
    --
    -- Instead the creature is asked for ONCE, unconditionally: the ask is deduped
    -- for the whole session by RequestCreatureCache, so it costs at most one tiny
    -- packet per milestone mount, ever. A creature that was missing simply draws
    -- the next time this reward is rendered -- hovering the bubble again, paging,
    -- or reopening the tab -- which needs no timer and no polling.
    --
    -- Returns true when the creature had to be asked for just now, i.e. when this
    -- render is probably still empty -- see shownIncomplete below.
    local function SetMountModel(creatureID)
        mountModel:Hide()
        mountModel.zoom = 0
        mountModel:SetPosition(0, 0, 0)
        -- CLEARED FIRST: SetCreature is a no-op when the creature is missing from
        -- the local cache, so without this the pane would keep showing the
        -- PREVIOUS mount and quietly pass it off as this milestone's reward.
        mountModel:ClearModel()
        mountModel:Show()
        mountModel:SetCreature(creatureID)
        mountModel:SetFacing(0.6)

        return ProjectEbonhold.RequestCreatureCache
            and ProjectEbonhold.RequestCreatureCache(creatureID) or false
    end

    -- Item models have the same cache dependency: DressUpModel:TryOn(itemID)
    -- renders nothing until the item is in the client's local item cache, and
    -- custom items never are on a fresh cache (GetItemInfo does NOT trigger the
    -- query itself on this client). Setting an item hyperlink on a hidden tooltip
    -- is what fires the server's item query.
    --
    -- NO POLLING, for the same reason as SetMountModel above: the chained
    -- C_Timer.After calls this used to run leaked one permanent Frame each, and a
    -- transmog-set milestone re-checked every missing piece on every tick. The
    -- query is fired once and the answer lands on its own; a piece that was not
    -- cached yet simply dresses up the next time this reward is rendered.
    local cacheTip = CreateFrame("GameTooltip", "EbonholdPrestigeCacheTip",
        UIParent, "GameTooltipTemplate")
    local function EnsureItemsCached(ids)
        local complete = true
        for _, id in ipairs(ids) do
            if not GetItemInfo(id) then
                cacheTip:SetOwner(UIParent, "ANCHOR_NONE")
                cacheTip:SetHyperlink("item:" .. id)
                complete = false
            end
        end
        if not complete then cacheTip:Hide() end
        return complete
    end

    -- Displayed state: the preview STICKS to the last hovered milestone (it no
    -- longer reverts on mouse-leave) so the pager arrows can be clicked.
    --
    -- shownIncomplete records that the last render was missing a creature or an
    -- item the client had not cached yet. It is what makes the preview self-heal
    -- without a single timer: an incomplete render is exempt from the "same
    -- reward, don't redraw" shortcut, so the next hover on that bubble draws it
    -- again -- by which time the server's answer has landed and it fills in.
    local shownMilestoneIndex, shownRewards, shownPage, shownIncomplete

    -- The unused model is ClearModel()ed AND hidden on every switch; leaving it
    -- merely hidden was enough, but clearing too guarantees a stale transmog
    -- preview can never bleed through over a mount preview (or vice versa).
    local function RenderPreviewReward()
        -- Loading a model costs the same whether or not anyone can see it, so the
        -- panel never renders off-screen. Every caller is a visible-tab action
        -- (hover, pager, OnShow) except the data push, which Refresh already
        -- stops; this is the backstop that keeps it that way.
        if not frame:IsVisible() then return end

        local n = shownRewards and #shownRewards or 0
        local item = (n > 0) and shownRewards[shownPage] or nil
        local isMount = item and item.type == "mount" and (item.itemID or 0) > 0
        local isWeapon = item and item.type == "weapon" and (item.itemID or 0) > 0
        local isSet = item and item.type == "transmogSet" and item.items and
            #item.items > 0

        shownIncomplete = false

        if isMount then
            preview.title:SetText(item.name ~= "" and item.name or "Mount")
            dressModel:ClearModel()
            dressModel:Hide()
            -- SetCreature on this client takes the CREATURE id (resolved through
            -- the local creature cache), NOT the display id. creatureID in the
            -- data table wins (custom mounts absent from the collections
            -- catalog); otherwise resolve item -> mount through the collections
            -- data like the mount journal does.
            local creatureID = item.creatureID
            if not creatureID or creatureID == 0 then
                local mountID = ezCollections and ezCollections.ItemIDXMountID and
                    ezCollections.ItemIDXMountID[item.itemID]
                local mountData = mountID and ezCollections.Mounts and
                    ezCollections.Mounts[mountID]
                creatureID = mountData and mountData[1]
            end
            if creatureID and creatureID > 0 then
                shownIncomplete = SetMountModel(creatureID)
            else
                mountModel:Hide()
            end
        elseif isWeapon then
            preview.title:SetText(item.name ~= "" and item.name or "Weapon")
            mountModel:ClearModel()
            mountModel:Hide()
            dressModel:Show()
            -- Current gear kept (no Undress): the weapon is tried on top, on the
            -- visible body (this client has no working invisible weapon holder)
            dressModel.zoom = 0
            dressModel:SetPosition(0, 0, 0)
            dressModel:SetUnit("player")
            if EnsureItemsCached({ item.itemID }) then
                dressModel:TryOn(item.itemID)
            else
                shownIncomplete = true
            end
            dressModel:SetFacing(0.4)
        elseif isSet then
            preview.title:SetText(item.name ~= "" and item.name or "Transmog set")
            mountModel:ClearModel()
            mountModel:Hide()
            dressModel:Show()
            dressModel.zoom = 0
            dressModel:SetPosition(0, 0, 0)
            dressModel:SetUnit("player")
            dressModel:Undress()
            -- Prime any uncached pieces; the ones already cached dress up right
            -- away, and a set that was still missing pieces is marked incomplete
            -- so the next hover redraws it with the answers in hand.
            shownIncomplete = not EnsureItemsCached(item.items)
            for _, pieceID in ipairs(item.items) do
                dressModel:TryOn(pieceID)
            end
            dressModel:SetFacing(0.4)
        else
            preview.title:SetText("Rewards to be announced")
            mountModel:ClearModel()
            mountModel:Hide()
            dressModel:ClearModel()
            dressModel:Hide()
        end

        if n > 1 then
            preview.pagerText:SetText(shownPage .. " / " .. n)
            preview.pagerText:Show()
            preview.prevBtn:Show()
            preview.nextBtn:Show()
        else
            preview.pagerText:Hide()
            preview.prevBtn:Hide()
            preview.nextBtn:Hide()
        end
    end

    local function ShowRewardPreview(index, ms, page)
        page = page or 1
        -- Re-rendering what is already on screen costs a full model reload
        -- (ClearModel + SetCreature, or Undress + one TryOn per set piece), and
        -- OnEnter fires again every time the cursor re-enters the same bubble --
        -- crossing the tooltip, leaving and coming back, jitter on the edge. Bail
        -- out when nothing actually changed, UNLESS the last render came up short
        -- on a creature or an item: that one is exactly the redraw worth doing.
        if shownMilestoneIndex == index and shownPage == page
           and not shownIncomplete then
            return
        end

        shownMilestoneIndex = index
        shownRewards = PrestigeData.GetRewardItems(ms)
        shownPage = page
        preview.header:SetText("Prestige " .. index .. " reward")
        RenderPreviewReward()
    end

    preview.prevBtn:SetScript("OnClick", function()
        local n = shownRewards and #shownRewards or 0
        if n < 2 then return end
        shownPage = (shownPage - 2) % n + 1
        RenderPreviewReward()
    end)
    preview.nextBtn:SetScript("OnClick", function()
        local n = shownRewards and #shownRewards or 0
        if n < 2 then return end
        shownPage = (shownPage % n) + 1
        RenderPreviewReward()
    end)

    -- Default content until something is hovered: the next milestone ahead (or
    -- the final one once everything is completed).
    local function ShowDefaultPreview()
        local total = ProjectEbonhold.PrestigeService and
            ProjectEbonhold.PrestigeService.GetTotalPrestiges() or 0
        local index, ms = PrestigeData.GetNextMilestone(total)
        if not index then
            index = #PrestigeData.Milestones
            ms = PrestigeData.Milestones[index]
        end
        ShowRewardPreview(index, ms)
    end

    -- Bubbles are spread symmetrically across the bar (equal margins both sides);
    -- the fill interpolates between bubble centers so it touches bubble i exactly
    -- when milestone i completes.
    local BUBBLE_MARGIN = 42
    local bubbleXs = {}
    for i = 1, #PrestigeData.Milestones do
        bubbleXs[i] = BUBBLE_MARGIN +
            (BAR_W - 2 * BUBBLE_MARGIN) * (i - 1) / (#PrestigeData.Milestones - 1)
    end

    local function ComputeFillWidth(total)
        local ms = PrestigeData.Milestones
        local count = #ms
        local rank = PrestigeData.GetRank(total)
        if rank >= count then return maxFillWidth end

        local function posOf(i)
            if i == 0 then return fillInsetLeft end
            return bubbleXs[i]
        end

        local prevTotal = (rank == 0) and 0 or ms[rank].totalPrestiges
        local nextTotal = ms[rank + 1].totalPrestiges
        local partial = 0
        if nextTotal > prevTotal then
            partial = (total - prevTotal) / (nextTotal - prevTotal)
        end
        partial = math.max(0, math.min(partial, 1))

        local x = posOf(rank) + (posOf(rank + 1) - posOf(rank)) * partial
        return math.max(0, math.min(x - fillInsetLeft, maxFillWidth))
    end

    local bubbles = {}

    -- Gold glow on the bubble whose milestone the preview panel is currently
    -- showing: hovering moves it, and it STICKS like the preview itself, so it
    -- is always obvious at a glance which prestige you are looking at.
    local function UpdateBubbleGlow()
        for i, bubble in ipairs(bubbles) do
            if i == shownMilestoneIndex then
                bubble.glow:Show()
            else
                bubble.glow:Hide()
            end
        end
    end

    for i, ms in ipairs(PrestigeData.Milestones) do
        local x = bubbleXs[i]

        local bubble = CreateFrame("Button", nil, barFrame)
        bubble:SetSize(BUBBLE_SIZE, BUBBLE_SIZE)
        bubble:SetPoint("CENTER", barBg, "LEFT", x, 48)

        local icon = bubble:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BUBBLE_SIZE - 8, BUBBLE_SIZE - 8)
        icon:SetPoint("CENTER", bubble, "CENTER", 0, 0)
        if ms.rankIcon then
            icon:SetTexture(ms.rankIcon)
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        bubble.icon = icon

        local label = bubble:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", bubble, "BOTTOM", 0, -1)
        label:SetText(ms.totalPrestiges)
        bubble.label = label

        -- Green check on milestones already passed (renown-track style)
        local check = bubble:CreateTexture(nil, "OVERLAY", nil, 7)
        check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        check:SetSize(14, 14)
        check:SetPoint("BOTTOMRIGHT", bubble, "BOTTOMRIGHT", 4, -3)
        check:Hide()
        bubble.check = check

        -- Hover/selection glow (sublevel 6: below the check, above the icon)
        local glow = bubble:CreateTexture(nil, "OVERLAY", nil, 6)
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        glow:SetSize(BUBBLE_SIZE * 1.9, BUBBLE_SIZE * 1.9)
        glow:SetPoint("CENTER", bubble, "CENTER", 0, 0)
        glow:Hide()
        bubble.glow = glow

        bubble:SetScript("OnEnter", function(self)
            local total = ProjectEbonhold.PrestigeService.GetTotalPrestiges()
            -- Docked left of the preview panel (not floating at the cursor), so
            -- the translucent tooltip never sits on top of the preview models.
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPRIGHT", preview, "TOPLEFT", -8, 0)
            GameTooltip:AddLine("Prestige " .. i, 1, 0.82, 0)
            if total >= ms.totalPrestiges then
                GameTooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t Unlocked", 0.2, 1, 0.2)
            else
                GameTooltip:AddLine("Progress: " .. total .. " / " .. ms.totalPrestiges .. " prestiges", 0.9, 0.9, 0.9)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Rewards", 1, 0.82, 0)
            AddRewardLinesToTooltip(ms)
            GameTooltip:Show()
            -- Opaque dark backdrop + gold border, matching the preview panel
            -- (the default translucent tooltip let the frame's text bleed
            -- through). GameTooltip_OnHide restores the stock colors, so every
            -- other tooltip in the game keeps its normal look.
            GameTooltip:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
            GameTooltip:SetBackdropBorderColor(0.95, 0.78, 0.25)
            ShowRewardPreview(i, ms)
            UpdateBubbleGlow()
        end)
        bubble:SetScript("OnLeave", function()
            GameTooltip:Hide()
            -- The preview deliberately keeps showing this milestone (sticky), so
            -- the player can reach the pager arrows to browse its rewards.
        end)

        bubbles[i] = bubble
    end

    ------------------------------------------------------------
    -- REFRESH
    ------------------------------------------------------------

    local function Refresh()
        if not ProjectEbonhold.PrestigeService then return end
        local svc = ProjectEbonhold.PrestigeService

        -- OFF-SCREEN WORK IS THE EXPENSIVE KIND, and this is where the client used
        -- to hitch. SEND_PRESTIGE_DATA reaches here through the service's NotifyUI
        -- whether or not the tab has ever been opened, and the refresh below
        -- retextures 14 bubbles and -- via ShowDefaultPreview -- loads a mount or
        -- an 8-piece transmog set into a 3D model. Doing that while the panel is
        -- not on screen buys nothing and used to land right in the middle of a
        -- loading screen. The alert is the one piece that is meant to work with
        -- the tab closed (it lives beside the tab button, so it is exactly this
        -- branch that puts it up), and it is a Show/Hide.
        --
        -- Nothing is lost by skipping: the tab's OnShow calls Refresh, so whatever
        -- arrived while it was closed is picked up the moment it opens.
        if not frame:IsVisible() then
            MaybeShowPrestigeAlert(svc.CanPrestige())
            return
        end

        local total = svc.GetTotalPrestiges()
        local rank = svc.GetRank()
        local maxTotal =
            PrestigeData.Milestones[#PrestigeData.Milestones].totalPrestiges

        countText:SetText(total)

        if rank > 0 then
            rankText:SetText("Prestige Rank " .. rank)
            rankIconTex:SetTexture(PrestigeData.GetRankIcon(rank))
            rankText:Show()
            rankIconTex:Show()
        else
            rankText:Hide()
            rankIconTex:Hide()
        end

        -- The offer on the table, once the gate is open. The button hangs off
        -- whichever line ends the column, so it never lands on top of this one.
        -- Since 2026-09-08 the ashes buy nothing: they are destroyed, and the reward is the
        -- Soul Essence the banked Soul Shards mint. The card says exactly that.
        local destroyed = svc.GetPendingPrestigeGain()
        prestigeButton:ClearAllPoints()
        if destroyed > 0 then
            dealFrame.destroyed = destroyed
            ShowEssenceDeal()
            dealFrame:Show()
            prestigeButton:SetPoint("TOP", dealFrame, "BOTTOM", 0, -14)
        else
            dealFrame:Hide()
            prestigeButton:SetPoint("TOP", capText, "BOTTOM", 0, -14)
        end

        local canPrestige = svc.CanPrestige()
        if canPrestige then
            prestigeButton:Enable()
            prestigeButton:SetTextColor(1, 1, 1)
            buttonOverlay:Hide()
            prestigeGlow:SetAlpha(0)
            prestigeGlow:Show()
            prestigeGlowPulse:Play()
        else
            prestigeButton:Disable()
            prestigeButton:SetTextColor(0.55, 0.55, 0.55)
            buttonOverlay:Show()
            prestigeGlowPulse:Stop()
            prestigeGlow:Hide()
        end
        MaybeShowPrestigeAlert(canPrestige)

        local fillWidth = ComputeFillWidth(total)
        if fillWidth > 0 then
            fillBar:SetWidth(fillWidth)
            fillBar:Show()
        else
            fillBar:Hide()
        end
        barText:SetText(total .. " / " .. maxTotal)

        -- Renown-track style: completed milestones are in full color with a
        -- green check, the one currently being farmed is in full color, and
        -- everything further ahead is greyed out (desaturated + dimmed).
        for i, bubble in ipairs(bubbles) do
            local ms = PrestigeData.Milestones[i]
            local completed = total >= ms.totalPrestiges
            local isNext = (not completed) and (i == rank + 1)
            if completed then
                bubble.icon:SetDesaturated(false)
                bubble.icon:SetAlpha(1)
                bubble.label:SetTextColor(1, 0.82, 0)
                bubble.check:Show()
            elseif isNext then
                bubble.icon:SetDesaturated(false)
                bubble.icon:SetAlpha(1)
                bubble.label:SetTextColor(1, 1, 1)
                bubble.check:Hide()
            else
                bubble.icon:SetDesaturated(true)
                bubble.icon:SetAlpha(0.5)
                bubble.label:SetTextColor(0.5, 0.5, 0.5)
                bubble.check:Hide()
            end
        end

        -- Only take over the preview when nothing is displayed yet: data pushes
        -- must not yank the panel away while the player is browsing rewards.
        if not shownMilestoneIndex then
            ShowDefaultPreview()
        end
        UpdateBubbleGlow()
    end

    frame:SetScript("OnShow", function()
        ProjectEbonhold.PrestigeService.RequestPrestigeData()
        Refresh()
    end)
    -- Must come after the SetScript above, which would otherwise discard it.
    frame:HookScript("OnShow", DismissPrestigeAlert)

    -- Reopening CollectionsJournal on the Prestige tab makes this panel visible
    -- again without necessarily firing its own OnShow -- the frame's own shown
    -- flag never changed, only an ancestor's -- so a data push that landed while
    -- the journal was closed would sit unapplied. Refresh returns immediately
    -- unless the Prestige tab is the visible one, so this costs one comparison
    -- per journal open and closes the gap.
    CollectionsJournal:HookScript("OnShow", function() Refresh() end)

    ------------------------------------------------------------
    -- Guided tour: first open of the Prestige tab (shared GlowBox tour factory,
    -- gated by a ProjectEbonholdDB once-flag)
    ------------------------------------------------------------

    local tour = ProjectEbonhold.GuidedTour.Create({
        parent = function() return frame end,
        -- Bumped when prestige stopped being a full character reset: players who saw the
        -- old tour were taught rules that no longer exist, so they get the tour once more.
        dbKey = "seenPrestigeTour2",
        boxWidth = 300,
        steps = function()
            return {
                {
                    title = "Prestige",
                    text = "This counter shows how many times you have prestiged. A prestige " ..
                        "is a trade: you give up everything your Skill Tree was built on, and " ..
                        "you keep one thing forever.",
                    zone = function() return circle end,
                    boxAnchor = { "LEFT", "RIGHT", 16, 0 },
                },
                {
                    title = "What it costs",
                    text = "Your Skill Tree is reset, and every Soul Ash on the account is " ..
                        "destroyed: the ones you banked and the ones already spent, on every " ..
                        "character. The Ashes buy nothing back. Only |cff00FF00Carry over " ..
                        "Prestige|r nodes survive the reset, and they become free for good. " ..
                        "Every |cff00FF00Endless|r node is one of them: all its ranks stay.",
                    zone = function() return dealFrame end,
                    boxAnchor = { "LEFT", "RIGHT", 16, 0 },
                },
                {
                    title = "What it pays",
                    text = "Your banked Soul Shards are consumed with the Ashes and come back " ..
                        "as |cffFFCC00Soul Essence|r: one for every 50 Shards on your first Prestige, " ..
                        "50 Shards more each time, up to 750. Your first Prestige mints at most 50 " ..
                        "Soul Essence, the next 100, up to 750 on the 15th, then there is no limit. " ..
                        "Shards above the limit stay banked. This card " ..
                        "shows the exchange you would make right now." .. "\n\n" ..
                        "Soul Essence buys the Prestige branch of the Skill Tree, and it is the " ..
                        "only currency a prestige never takes back: it only ever grows.",
                    zone = function() return dealFrame end,
                    boxAnchor = { "LEFT", "RIGHT", 16, 0 },
                },
                {
                    title = "What you keep",
                    text = "Everything else is untouched. Your level and your current run, your " ..
                        "Echoes, permanent or not, your saved builds, your gear, your talents " ..
                        "and professions, your Tomes, and every milestone reward you have earned.",
                    zone = function() return preview end,
                    boxAnchor = { "RIGHT", "LEFT", -16, 0 },
                },
                {
                    title = "Two locks",
                    text = "The button opens when both are met: enough Soul Ashes committed to " ..
                        "your Skill Tree, and enough banked Soul Shards for one Soul Essence, so the " ..
                        "reset always pays at least one Soul Essence." .. "\n\n" ..
                        "Hover the locked button to see which one is still missing.",
                    zone = function() return prestigeButton end,
                    boxAnchor = { "LEFT", "RIGHT", 16, 0 },
                },
                {
                    title = "When to do it",
                    text = "Nothing forces you the moment the locks open. Shards keep piling up " ..
                        "from the dungeons, raids and Call Board contracts you clear, and what one " ..
                        "Prestige cannot convert waits in your bank for the next.",
                    zone = function() return prestigeButton end,
                    boxAnchor = { "LEFT", "RIGHT", 16, 0 },
                },
                {
                    title = "Milestones",
                    text = "Each prestige fills this bar. Milestones grant rewards: mounts, full " ..
                        "transmog sets, titles and an exclusive chat rank icon. Hover a milestone " ..
                        "for its details.",
                    zone = function() return bubbles[1], barFrame end,
                    boxAnchor = { "BOTTOM", "TOP", 0, 14 },
                },
                {
                    title = "Reward Preview",
                    text = "Your next milestone reward is previewed here. Hover any milestone to " ..
                        "preview its mount or transmog set.",
                    zone = function() return preview end,
                    boxAnchor = { "RIGHT", "LEFT", -16, 0 },
                },
            }
        end,
    })

    frame:HookScript("OnShow", function() tour:MaybeStart() end)
    frame:HookScript("OnHide", function()
        tour:Stop(false)
        -- A looping animation on a hidden frame is invisible work; the next
        -- Refresh restarts it if the gate is still open.
        prestigeGlowPulse:Stop()
    end)

    ProjectEbonhold.PrestigeUI = {
        frame = frame,
        Refresh = Refresh,
    }

end

-- The one entry point. PLAYER_ENTERING_WORLD fires again on every zone change,
-- so the listener drops itself after the first one: a one-shot, not a hook that
-- keeps running.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    self:SetScript("OnEvent", nil)
    BuildUI()
end)
