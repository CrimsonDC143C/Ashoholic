local addonName = ...
local addon = _G[addonName]

addon.Integrations = addon.Integrations or {}
addon.Integrations.ProjectEbonhold = addon.Integrations.ProjectEbonhold or {}

local Integration = addon.Integrations.ProjectEbonhold

-- Observe the companion's parsed state, not its server-message registrations.
-- Its parser replaces the run table before calling PlayerRunUI.UpdateData,
-- including when the HUD is hidden. Other HUD updates may reuse that table;
-- they must not make cached currency figures look newly received.
function Integration.WatchRunCurrencies(onSnapshot)
    if type(onSnapshot) ~= "function" then
        error("Ashoholic needs a callback to observe Ebonhold run currencies.")
    end

    local companion = ProjectEbonhold
    local service = companion and companion.PlayerRunService
    local runUI = companion and companion.PlayerRunUI
    if not service or type(service.GetCurrentData) ~= "function"
        or not runUI or type(runUI.UpdateData) ~= "function" then
        error("Ashoholic cannot collect run currencies: ProjectEbonhold's run API is unavailable.")
    end

    local lastRunData
    local function Observe()
        local current = service.GetCurrentData()
        if current == nil then
            return
        end
        if type(current) ~= "table" then
            error("Ashoholic received invalid run data from ProjectEbonhold.")
        end
        -- An empty table (or multiplier-only update) is normal during login.
        if current.soulPoints == nil or current.soulShards == nil then
            return
        end
        if current == lastRunData then
            return
        end

        lastRunData = current
        onSnapshot({
            soulAsh = current.soulPoints,
            soulShards = current.soulShards,
            updatedAt = time(),
        })
    end

    hooksecurefunc(runUI, "UpdateData", Observe)
    -- The server may have answered before Ashoholic registered its observer.
    Observe()
end
