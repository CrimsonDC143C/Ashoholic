-- File: echo_visuals.lua
-- "Echoes" and "Class Spells" in Video > Effects, where "Death Effect" and "Projected Textures"
-- were. Each one is Shown / Hide others / Hide all. Lowering Spell Detail hides spell effects but
-- takes the boss telegraphs with them; these hide only players' echoes and class spells.
--
-- The server does the hiding (Player::GetHiddenSpellVisuals): it stops sending this client the
-- cast, missile and impact of those spells, and their ground effects. A creature's spell is never
-- filtered, so a telegraph always shows. "Hide all" on my own spell cast from the action bar keeps
-- its cast bar and the animation on my character, only its projectile and impact go. The setting
-- is account-wide here and the server forgets it at logout, so it is sent at every entering world
-- and on every change.

local MODE_LABELS = { [0] = "Shown", [1] = "Hide others", [2] = "Hide all" }

-- PlayerHiddenSpellVisuals: a kind is its "others" bit, its "mine" bit is the next one up.
local KIND_BITS = { echo = 1, class = 4 }

local OPTIONS = {
    {
        key = "echoVisualsMode", kind = "echo", label = "Echoes",
        tooltip = "Spell effects of echoes. Hide others: only other players' echoes. Hide all: yours too. Boss telegraphs always stay.",
    },
    {
        key = "classVisualsMode", kind = "class", label = "Class Spells",
        tooltip = "Spell effects of class spells and procs. Hide others: only other players' spells. Hide all: yours too (your cast bar and casting animation stay). Boss telegraphs always stay.",
    },
}

local function GetMode(key)
    local mode = ProjectEbonholdOptionsService and ProjectEbonholdOptionsService:GetSetting(key)
    mode = tonumber(mode) or 0
    if mode < 0 or mode > 2 then mode = 0 end
    return mode
end

local function SendState()
    if not (ProjectEbonhold and ProjectEbonhold.sendToServer and ProjectEbonhold.CS) then return end
    local mask = 0
    for _, option in ipairs(OPTIONS) do
        local mode, bit = GetMode(option.key), KIND_BITS[option.kind]
        if mode >= 1 then mask = mask + bit end
        if mode == 2 then mask = mask + bit * 2 end
    end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_HIDDEN_VISUALS_SET, tostring(mask))
end

-- ── Two drop-downs in Video > Effects ────────────────────────────────────
--
-- The Effects panel has no free room: its bottom box (Shaders) holds two columns of two boxes and
-- the sliders sit just above it. "Projected Textures" is forced on by projected_textures.lua (the
-- telegraphs need it) and "Death Effect" was given up for this (owner, 2026-10-28): both boxes are
-- hidden, their CVars keep their values, and the second column takes the two drop-downs. They
-- apply at once, Okay / Cancel do not touch them. The panel is stock FrameXML.

local panel = _G.VideoOptionsEffectsPanel
if panel then
    local name = panel:GetName()
    for _, suffix in ipairs({ "DeathEffect", "ProjectedTextures" }) do
        local box = _G[name .. suffix]
        if box then
            box:Hide()
            box:HookScript("OnShow", box.Hide)
        end
    end

    local shaders = _G[name .. "Shaders"]
    local dropDowns = {}
    local previous

    for i, option in ipairs(OPTIONS) do
        local dropDown = CreateFrame("Frame", name .. "HiddenVisuals" .. i, panel, "UIDropDownMenuTemplate")
        if previous then
            dropDown:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, 2)
        elseif shaders then
            -- Where "Death Effect" sat (Shaders + 180, -8); the template has a 16-pixel left inset.
            dropDown:SetPoint("TOPLEFT", shaders, "TOPLEFT", 164, -4)
        else
            dropDown:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 180, 44)
        end
        UIDropDownMenu_SetWidth(dropDown, 155)

        local function Refresh()
            UIDropDownMenu_SetText(dropDown, option.label .. ": " .. MODE_LABELS[GetMode(option.key)])
        end

        UIDropDownMenu_Initialize(dropDown, function(self, level)
            local current = GetMode(option.key)
            for mode = 0, 2 do
                local info = UIDropDownMenu_CreateInfo()
                info.text = MODE_LABELS[mode]
                info.value = mode
                info.checked = (mode == current)
                info.func = function()
                    ProjectEbonholdOptionsService:SetSetting(option.key, mode)
                    Refresh()
                    SendState()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)

        local button = _G[dropDown:GetName() .. "Button"]
        if button then
            button:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(option.label, 1, 1, 1)
                GameTooltip:AddLine(option.tooltip, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            button:HookScript("OnLeave", function(self)
                if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            end)
        end

        dropDown.Refresh = Refresh
        dropDowns[#dropDowns + 1] = dropDown
        previous = dropDown
    end

    panel:HookScript("OnShow", function()
        for _, dropDown in ipairs(dropDowns) do dropDown.Refresh() end
    end)
end

-- ── Server state ─────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", SendState)
