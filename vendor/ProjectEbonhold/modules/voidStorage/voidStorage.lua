local Addon = select(2, ...)

-- Wait for BankFrame to be available
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("BANKFRAME_OPENED")
initFrame:SetScript("OnEvent", function(self, event)
    -- if event == "BANKFRAME_OPENED" and not VoidStorageButton then
    --     -- Create Void Storage button on BankFrame
    --     local btn = CreateFrame("Button", "VoidStorageButton", BankFrame, "UIPanelButtonTemplate")
    --     btn:SetWidth(120)
    --     btn:SetHeight(25)
    --     btn:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 60, -40)
    --     btn:SetText("Void Storage")
    --     btn:SetScript("OnClick", function()
    --         VoidStorageService.SetOpenTab(1)
    --         BankFrame:SetAlpha(0)
    --         local frame = _G["VoidStorageFrame"]
    --         if frame then
    --             -- Request tab 1 data from server
    --             ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_RETRIEVE_ITEMS_FROM_TAB, "1")
    --             frame.loadedTabs[1] = true -- Mark tab 1 as loaded
    --             frame:Show()
    --             DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Void Storage] Opening...|r")
    --         else
    --             DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[Void Storage] Frame not found!|r")
    --         end
    --     end)
    --     self:UnregisterEvent("BANKFRAME_OPENED")
    -- end
end)

-- Create Void Storage Frame
local VoidStorageFrame = CreateFrame("Frame", "VoidStorageFrame", UIParent)
VoidStorageFrame:SetWidth(380)
VoidStorageFrame:SetHeight(365)
VoidStorageFrame:SetPoint("CENTER")
VoidStorageFrame:SetFrameStrata("HIGH")
VoidStorageFrame:SetToplevel(true)
VoidStorageFrame:EnableMouse(true)
VoidStorageFrame:SetMovable(true)
VoidStorageFrame:RegisterForDrag("LeftButton")
VoidStorageFrame:SetScript("OnDragStart", VoidStorageFrame.StartMoving)
VoidStorageFrame:SetScript("OnDragStop", VoidStorageFrame.StopMovingOrSizing)
VoidStorageFrame:Hide()

-- Allow ESC key to close the frame
table.insert(UISpecialFrames, "VoidStorageFrame")

-- OnHide script to cleanup when frame is closed (via ESC or close button)
VoidStorageFrame:SetScript("OnHide", function()
    BankFrame:SetAlpha(1)
    VoidStorageService.SetOpenTab(0)
end)

-- Background
VoidStorageFrame.bg = VoidStorageFrame:CreateTexture(nil, "BACKGROUND")
VoidStorageFrame.bg:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\UI-Background-Rock")
VoidStorageFrame.bg:SetPoint("TOPLEFT", VoidStorageFrame, "TOPLEFT", 8, -8)
VoidStorageFrame.bg:SetPoint("BOTTOMRIGHT", VoidStorageFrame, "BOTTOMRIGHT", -8, 8)
VoidStorageFrame.bg:SetHorizTile(true)
VoidStorageFrame.bg:SetVertTile(true)

-- Border
VoidStorageFrame:SetBackdrop({
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})

-- Title
VoidStorageFrame.title = VoidStorageFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
VoidStorageFrame.title:SetPoint("TOP", 0, 30)
VoidStorageFrame.title:SetText("The Void Storage")

-- Header texture
VoidStorageFrame.header = VoidStorageFrame:CreateTexture(nil, "BACKGROUND")
VoidStorageFrame.header:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\voidstorage.blp")
VoidStorageFrame.header:SetTexCoord(-0.041016, 0.656250, 0.001953, 0.162109)
VoidStorageFrame.header:SetWidth(400)
VoidStorageFrame.header:SetHeight(80)
VoidStorageFrame.header:SetPoint("CENTER", VoidStorageFrame, "TOP", -10, 35)

-- Close button
VoidStorageFrame.closeButton = CreateFrame("Button", nil, VoidStorageFrame, "UIPanelCloseButton")
VoidStorageFrame.closeButton:SetPoint("TOPRIGHT", -5, -5)
VoidStorageFrame.closeButton:SetScript("OnClick", function()
    VoidStorageFrame:Hide()
end)

-- Tab Management System
VoidStorageFrame.tabs = {}
VoidStorageFrame.currentTab = 1
VoidStorageFrame.maxTabs = 10
VoidStorageFrame.slotsPerTab = 72
VoidStorageFrame.loadedTabs = {} -- Track which tabs have been loaded from server

-- Create tab buttons (vertical layout on the right side)
for i = 1, VoidStorageFrame.maxTabs do
    local tab = CreateFrame("Button", "VoidStorageTab" .. i, VoidStorageFrame)
    tab:SetWidth(28)
    tab:SetHeight(28)
    tab:SetPoint("TOPRIGHT", VoidStorageFrame, "TOPRIGHT", 32, -40 - (i - 1) * 30)

    -- Tab background
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetTexture("Interface\\Buttons\\UI-EmptySlot")

    -- Tab icon (can be customized per tab)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetPoint("CENTER")
    tab.icon:SetWidth(24)
    tab.icon:SetHeight(24)
    tab.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    tab.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Selected border
    tab.selectedBorder = tab:CreateTexture(nil, "OVERLAY")
    tab.selectedBorder:SetAllPoints()
    tab.selectedBorder:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    tab.selectedBorder:SetBlendMode("ADD")
    tab.selectedBorder:Hide()
    tab.tabIndex = i

    tab:SetScript("OnClick", function(self)
        VoidStorageFrame:SwitchTab(self.tabIndex)
    end)

    VoidStorageFrame.tabs[i] = tab
end

-- Function to switch tabs
function VoidStorageFrame:SwitchTab(tabIndex)
    if tabIndex == self.currentTab then return end

    self.currentTab = tabIndex

    -- Notify backend about tab switch
    VoidStorageService.SetOpenTab(tabIndex)
    
    -- Check if this tab has been loaded before
    if not self.loadedTabs[tabIndex] then
        print("Requesting tab", tabIndex, "data from server...")
        -- Request tab data from server
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_RETRIEVE_ITEMS_FROM_TAB, tostring(tabIndex))
        -- Mark as loaded (will be populated when SEND_CONTENT_VOID_STORAGE arrives)
        self.loadedTabs[tabIndex] = true
    end

    -- Update tab visuals
    for i, tab in ipairs(self.tabs) do
        if i == tabIndex then
            tab.selectedBorder:Show()
            tab.icon:SetAlpha(1)
        else
            tab.selectedBorder:Hide()
            tab.icon:SetAlpha(0.5)
        end
    end

    -- Update display
    self:UpdateDisplay()
end

-- Initialize first tab as active
VoidStorageFrame.tabs[1].selectedBorder:Show()
VoidStorageFrame.tabs[1].icon:SetAlpha(1)
for i = 2, VoidStorageFrame.maxTabs do
    VoidStorageFrame.tabs[i].icon:SetAlpha(0.5)
end

-- Void Storage item slots (72 slots = 9x8)
VoidStorageFrame.slots = {}
local SLOTS_PER_ROW = 9
local SLOTS_PER_COLUMN = 8
local SLOT_SIZE = 36
local SLOT_SPACING = 3

for i = 1, 72 do
    local slot = CreateFrame("Button", "VoidStorageSlot" .. i, VoidStorageFrame)
    slot:SetWidth(SLOT_SIZE)
    slot:SetHeight(SLOT_SIZE)

    local row = math.floor((i - 1) / SLOTS_PER_ROW)
    local col = (i - 1) % SLOTS_PER_ROW

    slot:SetPoint("TOPLEFT", VoidStorageFrame, "TOPLEFT",
        15 + col * (SLOT_SIZE + SLOT_SPACING),
        -40 - row * (SLOT_SIZE + SLOT_SPACING))

    -- Slot background
    slot.bg = slot:CreateTexture(nil, "BACKGROUND")
    slot.bg:SetAllPoints()
    slot.bg:SetTexture("Interface\\Buttons\\UI-EmptySlot")

    -- Item icon
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 3, -3)
    slot.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -3, 3)
    slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    slot.icon:Hide()

    -- Item count
    slot.count = slot:CreateFontString(nil, "OVERLAY")
    slot.count:SetPoint("BOTTOMRIGHT", -4, 4)
    slot.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    slot.count:SetTextColor(1, 1, 1, 1) -- White color
    slot.count:Hide()

    -- Hover highlight
    slot.highlight = slot:CreateTexture(nil, "HIGHLIGHT")
    slot.highlight:SetAllPoints()
    slot.highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    slot.highlight:SetBlendMode("ADD")

    slot.slotIndex = i
    slot.itemEntry = nil

    -- Register for clicks
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Click handler to retrieve items from void storage
    slot:SetScript("OnClick", function(self, button)
        if not self.itemEntry then return end
        local tabIndex = VoidStorageFrame.currentTab
        local slotIndex = self.slotIndex - 1 -- Convert from 1-based to 0-based for server
        
        if button == "RightButton" then
            -- Check if player has bag space
            local hasSpace = false
            for bag = 0, 4 do
                local numFreeSlots = GetContainerNumFreeSlots(bag)
                if numFreeSlots and numFreeSlots > 0 then
                    hasSpace = true
                    break
                end
            end
            
            if not hasSpace then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[Void Storage] No bag space available!|r")
                return
            end
            
            -- Send request to server
            ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_RETRIEVE_VOID_STORAGE_ITEM, slotIndex)
            
            -- Remove item from local storage (optimistic update)
            if VoidStorageService.voidStorageItems[tabIndex] then
                VoidStorageService.voidStorageItems[tabIndex][self.slotIndex] = nil
                print("Removed item from tab", tabIndex, "slot", slotIndex)
                
                -- Update display immediately
                if VoidStorageFrame.UpdateDisplay then
                    VoidStorageFrame:UpdateDisplay()
                end
            end
        end
    end)

    -- Tooltip handling
    slot:SetScript("OnEnter", function(self)
        if self.itemEntry then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemEntry .. ":0:0:0:0:0:0:0")
            GameTooltip:Show()
        end
    end)

    slot:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    VoidStorageFrame.slots[i] = slot
end

-- Update display function
function VoidStorageFrame:UpdateDisplay()
    -- Each tab has its own indices 1-72
    local currentTab = self.currentTab

    -- Initialize tab table if it doesn't exist
    if not VoidStorageService.voidStorageItems[currentTab] then
        VoidStorageService.voidStorageItems[currentTab] = {}
    end

    for i = 1, 72 do
        local slot = self.slots[i]
        local item = VoidStorageService.voidStorageItems[currentTab][i]

        if item then
            local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
            itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(item.entry)

            if itemTexture then
                slot.icon:SetTexture(itemTexture)
                slot.icon:Show()
                slot.itemEntry = item.entry
                slot.globalIndex = itemIndex

                if item.count > 1 then
                    slot.count:SetText(item.count)
                    slot.count:Show()
                else
                    slot.count:Hide()
                end
            else
                slot.icon:Hide()
                slot.count:Hide()
                slot.itemEntry = nil
            end
        else
            slot.icon:Hide()
            slot.count:Hide()
            slot.itemEntry = nil
        end
    end
end

-- Hook into container item clicks
-- local originalContainerFrameItemButton_OnClick = ContainerFrameItemButton_OnClick

-- function ContainerFrameItemButton_OnClick(self, button)
--     if VoidStorageService.isUsingVoidStorage and VoidStorageFrame and VoidStorageFrame:IsShown() then
--         if button == "RightButton" then
--             local bagID = self:GetParent():GetID()
--             local slotID = self:GetID()
--             print("Storing item from bag:", bagID, "slot:", slotID)
--             local itemID = GetContainerItemID(bagID, slotID)
--             local _, itemCount = GetContainerItemInfo(bagID, slotID)
--             if itemID then
--                 local currentTab = VoidStorageFrame.currentTab
--                 if not VoidStorageService.voidStorageItems[currentTab] then
--                     VoidStorageService.voidStorageItems[currentTab] = {}
--                 end
--                 local emptySlot = nil
--                 for i = 1, VoidStorageFrame.slotsPerTab do
--                     if not VoidStorageService.voidStorageItems[currentTab][i] then
--                         emptySlot = i
--                         break
--                     end
--                 end

--                 if emptySlot then
--                     VoidStorageService.voidStorageItems[currentTab][emptySlot] = {
--                         entry = itemID,
--                         count = itemCount or 1
--                     }
--                     local relativeSlot = emptySlot - 1
--                     -- Update display immediately
--                     if VoidStorageFrame.UpdateDisplay then
--                         VoidStorageFrame:UpdateDisplay()
--                     end
--                 else
--                     print("Current tab is full!")
--                 end
--             end
--             UseContainerItem(bagID, slotID)
--             return;
--         end
--     end
--     originalContainerFrameItemButton_OnClick(self, button)
-- end