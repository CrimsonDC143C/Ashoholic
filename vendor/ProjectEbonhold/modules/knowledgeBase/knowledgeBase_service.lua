local addonName, addon = ...






local savedItems = {} 



ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_ITEMS_SAVED, function(body)
    
    savedItems = {}
    
    if not body or body == "" then
        
        if UpdateItemList then
            UpdateItemList(savedItems)
        end
        return
    end
    
    
    for itemData in string.gmatch(body, "([^;]+)") do
        local guid, entryStr, countStr = itemData:match("^([^,]+),([^,]+),([^,]+)$")
        
        if guid and entryStr and countStr then
            local entry = tonumber(entryStr)
            local count = tonumber(countStr)
            
            if entry and count then
                
                local itemName, _, _, _, _, _, _, _, _, itemIcon, sellPrice = GetItemInfo(entry)
                
                table.insert(savedItems, {
                    guid = guid,
                    entry = entry,
                    count = count,
                    name = itemName or ("Item #" .. entry),
                    icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
                    sellPrice = sellPrice or 0
                })
            end
        end
    end
    
    
    if UpdateItemList then
        UpdateItemList(savedItems)
    end
end)


local function RequestSavedItems()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PLAYER_ITEMS_SAVED, "")
end


local function RecoverItem(itemGUID)
    if not itemGUID or itemGUID == "" then
        return false
    end
    
    
    for i = #savedItems, 1, -1 do
        if savedItems[i].guid == itemGUID then
            table.remove(savedItems, i)
            break
        end
    end
    
    
    if UpdateItemList then
        UpdateItemList(savedItems)
    end
    
    
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_PLAYER_ADD_ITEM_ITEM_SAVED, itemGUID)
    
    return true
end


local function GetSavedItems()
    return savedItems
end


ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.KnowledgeBaseService = ProjectEbonhold.KnowledgeBaseService or {}
ProjectEbonhold.KnowledgeBaseService.RequestSavedItems = RequestSavedItems
ProjectEbonhold.KnowledgeBaseService.RecoverItem = RecoverItem
ProjectEbonhold.KnowledgeBaseService.GetSavedItems = GetSavedItems
