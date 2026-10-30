local addonName, addon = ...






local specDropdown = nil
local resetButton = nil
local selectedSpecIndex = nil


SpecCustomNames = SpecCustomNames or {}


local function GetSpecName(specIndex)
    if SpecCustomNames[specIndex] and SpecCustomNames[specIndex] ~= "" then
        return SpecCustomNames[specIndex]
    end
    local defaultNames = { "Primary", "Secondary", "Third", "Fourth", "Fifth" }
    return defaultNames[specIndex] .. " Specialization"
end


local function EditSpecName(specIndex)
    local defaultNames = { "Primary", "Secondary", "Third", "Fourth", "Fifth" }
    local currentName = SpecCustomNames[specIndex] or ""

    StaticPopupDialogs["EDIT_SPEC_NAME"] = {
        text = "Edit name for " .. defaultNames[specIndex] .. " Specialization:",
        button1 = "Save",
        button2 = "Cancel",
        hasEditBox = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(self)
            self.editBox:SetText(currentName)
            self.editBox:SetFocus()
        end,
        OnAccept = function(self)
            local newName = self.editBox:GetText()
            if newName and newName ~= "" then
                SpecCustomNames[specIndex] = newName
                print("|cff00FF00Spec name updated to: " .. newName .. "|r")
            else
                SpecCustomNames[specIndex] = nil
            end

            
            if specDropdown and selectedSpecIndex == specIndex then
                UIDropDownMenu_SetText(specDropdown, GetSpecName(specIndex))
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local newName = self:GetText()
            if newName and newName ~= "" then
                SpecCustomNames[specIndex] = newName
                print("|cff00FF00Spec name updated to: " .. newName .. "|r")
            else
                SpecCustomNames[specIndex] = nil
            end

            if specDropdown and selectedSpecIndex == specIndex then
                UIDropDownMenu_SetText(specDropdown, GetSpecName(specIndex))
            end
            self:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(self)
            self:GetParent():Hide()
        end,
        preferredIndex = 3
    }
    StaticPopup_Show("EDIT_SPEC_NAME")
end

-- Per-row cog on the spec dropdown, the same one the Echo Journal hangs off its
-- loadout rows (Interface\WorldMap\GEAR_64GREY, dim until hovered). It replaces
-- the submenu arrow that used to bury "Edit Name" one level down: renaming a
-- spec is now a single click, on the row that owns the name.
--
-- The cogs are children of the shared DropDownList1 row buttons, which every
-- dropdown in the game recycles, so they are shown only by our own initialize
-- and hidden again the moment that list hides (which is also what happens right
-- before any other menu redraws into the same buttons).
local GEAR_TEXTURE = [[Interface\WorldMap\GEAR_64GREY]]
local gearButtons = {}
local gearHideHooked = false

local function HideRowGears()
    for _, gear in pairs(gearButtons) do
        gear:Hide()
    end
end

local function GetRowGear(rowIndex)
    if gearButtons[rowIndex] then return gearButtons[rowIndex] end

    local row = _G["DropDownList1Button" .. rowIndex]
    if not row then return nil end

    local gear = CreateFrame("Button", nil, row)
    gear:SetSize(14, 14)
    -- Rows are sized to their text plus fixed padding, so the right edge is
    -- free space; the cog sits in it without pushing the name around.
    gear:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    gear:SetFrameLevel(row:GetFrameLevel() + 2)

    gear.tex = gear:CreateTexture(nil, "ARTWORK")
    gear.tex:SetAllPoints()
    gear.tex:SetTexture(GEAR_TEXTURE)
    gear.tex:SetAlpha(0.5)

    gear:SetScript("OnEnter", function(self)
        self.tex:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Rename", 1, 1, 1)
        GameTooltip:AddLine("Give this specialization your own name.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function(self)
        self.tex:SetAlpha(0.5)
        GameTooltip:Hide()
    end)
    gear:SetScript("OnClick", function(self)
        PlaySound("igMainMenuOptionCheckBoxOn")
        -- Read the index before closing: CloseDropDownMenus hides the cog, and
        -- the next open may hand this same row to another spec.
        local specIndex = self.specIndex
        CloseDropDownMenus()
        if specIndex then EditSpecName(specIndex) end
    end)

    gearButtons[rowIndex] = gear
    return gear
end

local function CreateSpecDropdown()
    if specDropdown then return specDropdown end

    local dropdown = CreateFrame("Frame", "SpecDropdownFrame", PlayerTalentFrame, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOP", PlayerTalentFrame, "TOP", -38, -40)
    UIDropDownMenu_SetWidth(dropdown, 140)

    
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        if level == 1 then
            for i = 1, 5 do
                local info = UIDropDownMenu_CreateInfo()
                local specName = GetSpecName(i)
                info.text = specName
                info.checked = (selectedSpecIndex == i)
                info.value = i
                info.func = function()
                    selectedSpecIndex = i
                    if ProjectEbonhold and ProjectEbonhold.SpecService and ProjectEbonhold.SpecService.ApplySpec then
                        ProjectEbonhold.SpecService.ApplySpec(i)
                        UIDropDownMenu_SetText(dropdown, specName)
                        print("|cff00FF00Switching to " .. specName .. "...|r")
                    end
                end
                UIDropDownMenu_AddButton(info, level)

                -- The row button exists now: hang this spec's cog off it. The
                -- list numbers its buttons as they are added, so that count is
                -- the row we just created.
                local gear = GetRowGear(DropDownList1.numButtons)
                if gear then
                    gear.specIndex = i
                    gear:Show()
                end
            end
        end
    end)

    -- One hook, the first time the dropdown is built: any list hide (closing
    -- our menu, or another dropdown taking these row buttons over) takes the
    -- cogs down with it.
    if DropDownList1 and not gearHideHooked then
        DropDownList1:HookScript("OnHide", HideRowGears)
        gearHideHooked = true
    end

    
    if selectedSpecIndex then
        UIDropDownMenu_SetText(dropdown, GetSpecName(selectedSpecIndex))
    else
        UIDropDownMenu_SetText(dropdown, "Select Specialization")
    end

    specDropdown = dropdown
    return dropdown
end

local function CreateResetButton()
    if resetButton then return resetButton end

    -- The shell's own button art (utils.CreateSimpleCustomButton: the red
    -- 9-sliced button the Prestige, Extraction and Objectives panels use)
    -- rather than the stock UIPanelButtonTemplate, which read as a leftover
    -- next to everything else the addon draws.
    -- Sized to the spec dropdown next to it, which is the only thing it sits
    -- beside; the art reads big at any size, so the label drops a point to keep
    -- its margins inside 100px.
    local button = utils.CreateSimpleCustomButton(PlayerTalentFrame, "Reset Talents", nil, 100, 32)
    -- Sits a few pixels below the dropdown line rather than centred on it,
    -- which is what keeps it clear of the frame header above.
    button:SetPoint("TOPRIGHT", PlayerTalentFrame, "TOPRIGHT", -40, -40)
    if button.text then
        local font, size, flags = button.text:GetFont()
        button.text:SetFont(font, (size or 12) - 1, flags)
    end

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reset Talents", 1, 1, 1)
        GameTooltip:AddLine("Resets all talent points for the selected specialization.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffFFD700This will refund all spent talent points, allowing you to redistribute them.|r", 1,
            1, 0, true)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function()
        
        if not selectedSpecIndex then
            print("|cffFF0000Please select a specialization first|r")
            return
        end
        local selectedSpec = GetSpecName(selectedSpecIndex)
        StaticPopupDialogs["RESET_TALENTS_CONFIRM"] = {
            text = "Are you sure you want to reset all your talents?\n\n|cffFFD700Current Spec: " .. selectedSpec .. "|r",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                if ProjectEbonhold and ProjectEbonhold.SpecService and ProjectEbonhold.SpecService.ResetTalents then
                    ProjectEbonhold.SpecService.ResetTalents(selectedSpecIndex)
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3
        }
        StaticPopup_Show("RESET_TALENTS_CONFIRM")
    end)

    resetButton = button
    return button
end


local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == "Blizzard_TalentUI" or PlayerTalentFrame then
        if PlayerTalentFrame then
            PlayerTalentFrame:HookScript("OnShow", function()
                CreateSpecDropdown()
                CreateResetButton()
                
                if selectedSpecIndex and specDropdown then
                    UIDropDownMenu_SetText(specDropdown, GetSpecName(selectedSpecIndex))
                end
            end)
            self:UnregisterEvent("ADDON_LOADED")
        end
    end
end)


local function UpdateSelectedSpec(specIndex)
    if not specIndex or specIndex < 1 or specIndex > 5 then
        print("|cffFF0000Invalid spec index received from server|r")
        return
    end

    selectedSpecIndex = specIndex

    
    if specDropdown then
        UIDropDownMenu_SetText(specDropdown, GetSpecName(specIndex))
        
    end
end


ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.Spec = ProjectEbonhold.Spec or {}
ProjectEbonhold.Spec.UpdateSelectedSpec = UpdateSelectedSpec
