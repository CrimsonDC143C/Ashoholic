local addonName = ...
local addon = _G[addonName]

local function FormatNumber(num)
    if not num then return "0" end
    local s = string.format("%.0f", math.floor(num))
    while true do
        local k
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local ICON_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"
local ICON_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0|t"
local ICON_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0|t"

local function CompactGold(g)
    if g >= 1e9 then return string.format("%.2fb", g / 1e9)   end
    if g >= 1e6 then return string.format("%.2f mil", g / 1e6) end
    if g >= 1e3 then
        if g == math.floor(g) then return string.format("%.0fk", g / 1e3) end
        return string.format("%.2fk", g / 1e3)
    end
    return FormatNumber(g)
end

local function FormatMoney(copper, theme)
    copper = copper or 0
    local g = math.floor(copper / 10000)
    local s = math.floor(math.fmod(copper, 10000) / 100)
    local c = math.fmod(copper, 100)

    local gStr = (theme and theme.formatMoney) and CompactGold(g) or FormatNumber(g)

    if theme and theme.moneyGoldOnly then
        return gStr .. ICON_GOLD
    end
    return gStr .. ICON_GOLD .. " " .. s .. ICON_SILVER .. " " .. c .. ICON_COPPER
end

-- Soul Ash formatter that honours the active theme's Compact toggle.
local function FormatAsh(value, theme)
    value = value or 0
    if theme and theme.formatSoulAsh then
        if value >= 1e9 then return string.format("%.2fb", value / 1e9) end
        if value >= 1e6 then return string.format("%.2f mil", value / 1e6) end
        if value >= 1e3 then
            if value == math.floor(value) then return string.format("%.0fk", value / 1e3) end
            return string.format("%.2fk", value / 1e3)
        end
    end
    return FormatNumber(value)
end

function addon:InitMinimapButton()
    if AshoholicMinimapButton then return end

    local btn = CreateFrame("Button", "AshoholicMinimapButton", Minimap)
    btn:SetSize(33, 33)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(10)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("RightButton")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\inv_soulash")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local function UpdatePosition()
        local angle = addon.db.global.options.MinimapIconAngle or 180
        local radius = 80
        btn:SetPoint(
            "TOPLEFT",
            Minimap,
            "TOPLEFT",
            52 - (radius * cos(angle)),
            (radius * sin(angle)) - 52
        )
    end

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local xpos, ypos = GetCursorPosition()
            local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
            xpos = xmin - xpos / UIParent:GetScale() + 70
            ypos = ypos / UIParent:GetScale() - ymin - 70

            local angle = math.deg(math.atan2(ypos, xpos))
            addon.db.global.options.MinimapIconAngle = angle
            UpdatePosition()
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            addon:ToggleUI()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local theme = addon:GetTheme()
        local gold = theme.goldRGB
        GameTooltip:AddLine("Ashoholic", gold[1], gold[2], gold[3])
        GameTooltip:AddLine("Ebonhold Roster Summary", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ", 1, 1, 1)

        -- Calculate roster totals
        local totalGold = 0
        local totalRunAsh = 0
        local totalSpendable = 0
        local totalCommitted = 0
        local lockedCount = 0

        if addon.db and addon.db.global and addon.db.global.Characters then
            -- Track freshest snapshot per account for the account-wide pools
            local accountPools = {}
            for _, charDB in pairs(addon.db.global.Characters) do
                if charDB.name and charDB.name ~= "" then
                    totalGold = totalGold + (charDB.money or 0)

                    -- Per-character run ash
                    local run = charDB.RunSoulAsh
                    if run == nil then
                        run = math.max(0, (charDB.SoulAsh or 0) - (charDB.SpendableSoulAsh or 0))
                    end
                    totalRunAsh = totalRunAsh + run

                    -- Account-wide pools: snapshot from freshest character
                    local acc = charDB.account or "Main Account"
                    local seen = charDB.lastSeen or 0
                    if not accountPools[acc] or seen > accountPools[acc].lastSeen then
                        accountPools[acc] = {
                            lastSeen  = seen,
                            spendable = charDB.SpendableSoulAsh or 0,
                            committed = charDB.CommittedSoulAsh or 0,
                        }
                    end

                    local hasLockout = false
                    if charDB.SavedInstance then
                        for _, InstanceInfo in pairs(charDB.SavedInstance) do
                            local reset, lastcheck = strsplit("|", InstanceInfo)
                            reset = tonumber(reset) or 0
                            lastcheck = tonumber(lastcheck) or 0
                            if (reset - (time() - lastcheck)) > 0 then
                                hasLockout = true
                                break
                            end
                        end
                    end
                    if hasLockout then
                        lockedCount = lockedCount + 1
                    end
                end
            end

            for _, pool in pairs(accountPools) do
                totalSpendable = totalSpendable + pool.spendable
                totalCommitted = totalCommitted + pool.committed
            end
        end

        local totalSoulAsh = totalRunAsh + totalSpendable + totalCommitted

        GameTooltip:AddDoubleLine("Total Gold:", FormatMoney(totalGold, theme), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Total Soul Ash:", theme.text.soul .. FormatAsh(totalSoulAsh, theme) .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Active Lockouts:", theme.text.gold .. lockedCount .. " characters|r", 0.8, 0.8, 0.8, 1, 1, 1)

        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("|cFFFFFFFFLeft-Click|r to toggle Roster Window")
        GameTooltip:AddLine("|cFFFFFFFFRight-Click + Drag|r to move icon")
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    btn:Show()
end