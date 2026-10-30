local addonName, addon = ...

VoidStorageService = VoidStorageService or {}
VoidStorageService.isUsingVoidStorage = false
VoidStorageService.voidStorageItems = {}
VoidStorageService.currentOpenTab = 0

function VoidStorageService.SetOpenTab(tabIndex)
    VoidStorageService.currentOpenTab = tabIndex
    VoidStorageService.isUsingVoidStorage = (tabIndex > 0)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SET_USING_VOID_STORAGE, tabIndex)
end

-- Handle void storage content from server
-- Body format: tabIndex;itemEntry;ItemCount;itemEntry;ItemCount;...
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_CONTENT_VOID_STORAGE, function(body)
    if not body or body == "" then
        -- Clear current tab
        if VoidStorageService.currentOpenTab > 0 then
            VoidStorageService.voidStorageItems[VoidStorageService.currentOpenTab] = {}
        end
        if VoidStorageFrame and VoidStorageFrame.UpdateDisplay then
            VoidStorageFrame:UpdateDisplay()
        end
        return
    end
    
    local parts = {strsplit(";", body)}
    local tabIndex = tonumber(parts[1])
    
    if not tabIndex or tabIndex < 1 then
        print("Invalid tab index received from server")
        return
    end
    
    -- Initialize tab table if it doesn't exist
    if not VoidStorageService.voidStorageItems[tabIndex] then
        VoidStorageService.voidStorageItems[tabIndex] = {}
    else
        -- Clear existing items in this tab
        VoidStorageService.voidStorageItems[tabIndex] = {}
    end
    
    -- Parse items starting from index 2 (after tabIndex)
    for i = 2, #parts, 2 do
        local itemEntry = tonumber(parts[i])
        local itemCount = tonumber(parts[i + 1])
        
        if itemEntry and itemCount then
            -- Calculate slot index (1-based)
            local slotIndex = ((i - 2) / 2) + 1
            VoidStorageService.voidStorageItems[tabIndex][slotIndex] = {
                entry = itemEntry,
                count = itemCount
            }
        end
    end
    
    print("Loaded", ((#parts - 1) / 2), "items for tab", tabIndex)
    
    if VoidStorageFrame and VoidStorageFrame.UpdateDisplay then
        VoidStorageFrame:UpdateDisplay()
    end
end)
