-- OfflineMerge.ps1 gathers data-only exports from saved files into one inbox.
-- Every account imports through Data; neither script nor this module edits
-- character records directly.
local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local Codec = addon.Sync and addon.Sync.Codec
if not Data or not Codec then error("Ashoholic offline sync loaded before its dependencies.") end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Register after the collectors, so their final logout observations
        -- are saved before this frame builds the offline export.
        frame:RegisterEvent("PLAYER_LOGOUT")
        local inbox = addon.OfflineSyncInbox
        if type(inbox) ~= "table" then error("Ashoholic offline sync inbox is invalid.") end
        local changed = 0
        for index, encoded in ipairs(inbox) do
            local ok, result = pcall(function() return Data.ImportAccount(Codec.Decode(encoded)) end)
            if not ok then
                print("|cffff6060Ashoholic offline sync:|r Import " .. index .. " failed: " .. tostring(result))
            elseif result then
                changed = changed + 1
            end
        end
        if changed > 0 then
            print("|cffffca63Ashoholic offline sync:|r Imported newer data from " .. changed .. " account(s).")
        end
        frame:UnregisterEvent("PLAYER_LOGIN")
    else
        -- WoW writes SavedVariables after PLAYER_LOGOUT. The script later
        -- reads this data-only export without executing the saved Lua file.
        local ok, result = pcall(function() return Codec.Encode(Data.ExportCurrentAccount()) end)
        if not ok then
            -- Do not let the next offline merge mistake an older export for
            -- this session's final state.
            Data.ClearOfflineExport()
            print("|cffff6060Ashoholic offline sync:|r Could not prepare the export: " .. tostring(result))
            return
        end
        Data.SetOfflineExport(result)
    end
end)
