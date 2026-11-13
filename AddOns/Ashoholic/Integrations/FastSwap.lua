-- FastSwap switches characters only within the current account and realm.
-- The optional addon owns the actual logout and character-selection hook.
local addonName = ...
local addon = _G[addonName]
addon.Integrations = addon.Integrations or {}
local Integration = {}
addon.Integrations.FastSwap = Integration

function Integration.CanSwap(account, character)
    if not account.isCurrent then return false, "Characters on other accounts require a separate login." end
    local realm = GetRealmName()
    if type(realm) ~= "string" or character.realm ~= realm then
        return false, "FastSwap can only select characters on the current realm."
    end
    local current = UnitName("player")
    if type(current) ~= "string" or current == "" then return false, "The current character is not known yet." end
    if string.lower(character.name) == string.lower(current) then
        return false, "You are already playing this character."
    end
    if type(_G.FastSwap_PerformSwap) ~= "function" then
        return false, "Enable the separate FastSwap addon to swap characters."
    end
    return true, "Switch to " .. character.name .. " using FastSwap."
end

function Integration.Swap(account, character)
    local allowed, reason = Integration.CanSwap(account, character)
    if not allowed then
        print("|cffffca63Ashoholic:|r " .. reason)
        return
    end
    _G.FastSwap_PerformSwap(character.name)
end
