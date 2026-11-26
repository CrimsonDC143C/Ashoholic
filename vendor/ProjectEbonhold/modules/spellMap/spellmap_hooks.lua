-- spellmap_hooks.lua -- the Lua half of the SpellMap (a base spell shown as its override).
--
-- When an echo or a talent replaces a spell (spellmap_data.lua: base -> override while the
-- trigger is known), the server casts the override, but the action bar and the spellbook still
-- hold the base id. This file makes the client show the override:
--   * the spell tooltip is redrawn from the override spell;
--   * the cooldown swipe on action buttons and spellbook buttons follows the override.
--
-- 2026-11-10: moved here from ebonhold.dll (spellmap_client.h, chunk "spellmap_bootstrap"), so a
-- change no longer needs a DLL rebuild. The DLL keeps the native side:
--   EbonholdGetOverride(baseId)   -> override id, or 0 when no rule is active (server pushes it)
--   EbonholdSpellMapBeginRuleLoad / EbonholdSpellMapAddRule(base, trigger, override)
--   EbonholdSpellMapReady()       -> log line "bootstrap ready" in ebonhold.log
--
-- Works with an older ebonhold.dll too: that one still runs its own copy of these hooks, behind
-- the globals EBSPELLMAP_HOOKED / EBSPELLMAP_RULES_LOADED. Both sides check and set the same
-- globals, so the hooks go in exactly once, whoever comes first.
--
-- The DLL functions can be missing for a moment after a lua_State is recreated (the DLL repairs
-- it within ~1.5 s). Every hook reads them fresh and does nothing while they are missing.

-- Tooltip + cooldown hooks ---------------------------------------------------------------------

local function InstallHooks()
    if ( EBSPELLMAP_HOOKED or not GameTooltip ) then
        return;
    end
    EBSPELLMAP_HOOKED = true;

    local scratch = CreateFrame("GameTooltip", "EbonholdSpellMapScratch", nil, "GameTooltipTemplate");
    scratch:SetOwner(WorldFrame, "ANCHOR_NONE");

    -- Redraw `tooltip` with the lines of the override spell.
    local function ApplyOverride(tooltip, overrideId)
        scratch:ClearLines();
        scratch:SetHyperlink("spell:" .. overrideId);
        tooltip:ClearLines();
        for i = 1, scratch:NumLines() do
            local left = _G["EbonholdSpellMapScratchTextLeft" .. i];
            local text = left and left:GetText();
            if ( text and text ~= "" ) then
                local r, g, b = left:GetTextColor();
                -- Range and "X sec cooldown" sit in the RIGHT column of the cast-time line;
                -- copying only the left column dropped the cooldown from the tooltip.
                local right = _G["EbonholdSpellMapScratchTextRight" .. i];
                local rtext = right and right:IsShown() and right:GetText();
                if ( rtext and rtext ~= "" ) then
                    local rr, rg, rb = right:GetTextColor();
                    tooltip:AddDoubleLine(text, rtext, r, g, b, rr, rg, rb);
                else
                    tooltip:AddLine(text, r, g, b, true);
                end
            end
        end
        tooltip:Show();
    end

    -- The server sends SMSG_SPELL_COOLDOWN for the OVERRIDE id, while the button asks about the
    -- base id: no swipe. Point the swipe at the override's cooldown when a rule is active.
    local function ApplyCooldown(cooldown, baseId)
        local getOverride = EbonholdGetOverride;
        if ( not cooldown or not getOverride or type(baseId) ~= "number" ) then
            return;
        end
        local overrideId = getOverride(baseId);
        if ( not overrideId or overrideId <= 0 ) then
            return;
        end
        local start, duration, enable = GetSpellCooldown(overrideId);
        if ( start ) then
            CooldownFrame_SetTimer(cooldown, start, duration, enable);
        end
    end

    if ( ActionButton_UpdateCooldown and GetActionInfo ) then
        hooksecurefunc("ActionButton_UpdateCooldown", function(self)
            if ( not self.action ) then
                return;
            end
            local kind, id = GetActionInfo(self.action);
            if ( kind == "spell" ) then
                ApplyCooldown(self.cooldown, id);
            end
        end);
    end

    -- Ashendor's own SpellBookFrame.lua: SpellButton_UpdateButton() takes NO argument and redraws
    -- the whole page (spell id cached in button.data); one button refreshes through
    -- SpellButton_UpdateCooldown(self). Stock FrameXML has UpdateButton(self) only: both handled.
    local function SpellBookButtonId(button)
        if ( type(button.data) == "number" ) then
            return button.data;
        end
        if ( SpellBook_GetSpellID and GetSpellLink and SpellBookFrame ) then
            local link = GetSpellLink(SpellBook_GetSpellID(button:GetID()), SpellBookFrame.bookType);
            return link and tonumber(link:match("spell:(%d+)"));
        end
    end

    local function ApplySpellBookCooldown(button)
        if ( not button or not SpellBookFrame ) then
            return;
        end
        local id = SpellBookButtonId(button);
        if ( id ) then
            ApplyCooldown(button.cooldown or _G[button:GetName() .. "Cooldown"], id);
        end
    end

    if ( SpellButton_UpdateCooldown ) then
        hooksecurefunc("SpellButton_UpdateCooldown", ApplySpellBookCooldown);
    end
    if ( SpellButton_UpdateButton ) then
        hooksecurefunc("SpellButton_UpdateButton", function(self)
            if ( self ) then
                ApplySpellBookCooldown(self);
                return;
            end
            for i = 1, SPELLS_PER_PAGE or 12 do
                local button = _G["SpellButton" .. i];
                if ( button and button:IsShown() ) then
                    ApplySpellBookCooldown(button);
                end
            end
        end);
    end

    GameTooltip:HookScript("OnTooltipSetSpell", function(self)
        local getOverride = EbonholdGetOverride;
        if ( not getOverride ) then
            return;
        end
        local a, b, c = self:GetSpell();
        local id = (type(c) == "number" and c) or (type(b) == "number" and b) or (type(a) == "number" and a);
        local overrideId = id and getOverride(id);
        if ( overrideId and overrideId > 0 ) then
            ApplyOverride(self, overrideId);
        end
    end);

    if ( EbonholdSpellMapReady ) then
        EbonholdSpellMapReady();
    end
end

InstallHooks();

-- Rule table -> DLL ----------------------------------------------------------------------------
-- Sent once per lua_State, as soon as the DLL functions are there. Retries every 0.5 s until then.

local RETRY = 0.5;
local elapsed = RETRY;

local loader = CreateFrame("Frame");
loader:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt;
    if ( elapsed < RETRY ) then
        return;
    end
    elapsed = 0;

    InstallHooks(); -- no-op once done; covers a GameTooltip that was not there at load

    if ( EBSPELLMAP_RULES_LOADED ) then
        self:SetScript("OnUpdate", nil);
        return;
    end
    local rules = ProjectEbonhold and ProjectEbonhold.SpellMapRules;
    if ( not rules or #rules == 0 ) then
        self:SetScript("OnUpdate", nil);
        return;
    end
    if ( not EbonholdSpellMapBeginRuleLoad or not EbonholdSpellMapAddRule ) then
        return; -- DLL functions not (yet) in this state, or no ebonhold.dll at all
    end

    EBSPELLMAP_RULES_LOADED = true;
    EbonholdSpellMapBeginRuleLoad();
    for _, r in ipairs(rules) do
        EbonholdSpellMapAddRule(r[1], r[2], r[3]);
    end
    self:SetScript("OnUpdate", nil);
end);
