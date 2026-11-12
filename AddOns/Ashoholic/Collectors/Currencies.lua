--[[
================================================================================
 Collectors/Currencies.lua - COLLECT ACCOUNT-WIDE EBONHOLD CURRENCIES
================================================================================

 Soul Ash, Soul Shards, Soul Essence and Artisan Soul each have a spendable
 and a banked balance that belongs to the whole WoW account, not one
 character. ProjectEbonhold receives them from the server; this collector
 passes each update to addon.Data. Run currencies are handled separately by
 Collectors/Run.lua and are never added to these balances.

 The server sends no balances at login. They arrive when a balance changes,
 when the Soul Ash tree first opens, after a successful Apply in the tree, or
 when the roster asks for them through RequestBalancesIfNeeded below.
]]

local addonName = ...
local addon = _G[addonName]
local Data = addon.Data
local Integration = addon.Integrations and addon.Integrations.ProjectEbonhold

if not Data or not Integration then
    error("Ashoholic Collectors/Currencies.lua loaded before Data/Store.lua or Integrations/ProjectEbonhold.lua.")
end

local CurrencyCollector = {}
addon.Collectors = addon.Collectors or {}
addon.Collectors.Currencies = CurrencyCollector

local pendingSnapshot
local databaseReady = false
-- Becomes true when any balance message arrives in this UI session.
local receivedThisSession = false

local function SavePendingSnapshot()
    if not databaseReady or not pendingSnapshot then
        return
    end

    -- Clear it first, so an invalid snapshot is reported once, not retried.
    local snapshot = pendingSnapshot
    pendingSnapshot = nil
    Data.SaveAccountCurrencies(snapshot)
end

-- ProjectEbonhold keeps these balances private and only passes them along when
-- an update arrives, so start watching as soon as this file loads. Ashoholic
-- depends on ProjectEbonhold, so the companion has already loaded by now.
-- An update that arrives before the database is ready waits as pending.
Integration.WatchAccountCurrencies(function(snapshot)
    receivedThisSession = true
    pendingSnapshot = snapshot
    SavePendingSnapshot()
end)

-- The roster calls this when it opens. If no balances have arrived in this UI
-- session, it asks the server once; the integration sends the request only
-- when it is safe for the Soul Ash tree. The reply arrives a moment later and
-- updates the open roster through Data's normal change listeners.
function CurrencyCollector.RequestBalancesIfNeeded()
    if receivedThisSession then
        return
    end
    Integration.RequestAccountCurrencies()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    -- All ADDON_LOADED handlers, including database initialization, have
    -- completed by PLAYER_LOGIN.
    frame:UnregisterEvent("PLAYER_LOGIN")
    databaseReady = true
    SavePendingSnapshot()
end)
