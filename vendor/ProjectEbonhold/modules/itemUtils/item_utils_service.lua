local addonName, addon = ...

-- Local reference to send junk request
local function SendSellJunkRequest()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SELL_JUNK_ITEMS, "");
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Item Utils] Sending REQUEST_SELL_JUNK_ITEMS|r")
end

-- Register slash command
SLASH_sellJunk1 = "/sell_junk"
SlashCmdList["sellJunk"] = function(msg)
    SendSellJunkRequest()
end

-- Event: Junk items sold response
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_JUNK_SOLD, function(body)
    if not body or body == "" then
        -- Sale failed
        return
    end
    
    -- Parse the response: numberOfItemsSold|totalEarnedCopper
    local itemsSold, copperEarned = body:match("^(%d+)|(%d+)$")
    
    if itemsSold and copperEarned then
        itemsSold = tonumber(itemsSold)
        copperEarned = tonumber(copperEarned)
        
        -- Convert copper to gold/silver/copper display
        local gold = math.floor(copperEarned / 10000)
        local silver = math.floor((copperEarned % 10000) / 100)
        local copper = copperEarned % 100
        
        local moneyString = ""
        if gold > 0 then
            moneyString = gold .. "|cffffd700g|r "
        end
        if silver > 0 or gold > 0 then
            moneyString = moneyString .. silver .. "|cffc7c7c7s|r "
        end
        moneyString = moneyString .. copper .. "|cffeda55fc|r"
    end
end)
