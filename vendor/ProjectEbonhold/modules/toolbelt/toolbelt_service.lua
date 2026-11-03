local addonName, addon = ...

-- ── The Toolbelt: state + requests ───────────────────────────────────────────
-- Bank, Mailbox, Auction House, Guild Bank and the Enchanted Anvil (open them
-- anywhere), Portable Forge (a forge and an anvil set up beside you), Vendor
-- (sell / repair, no vendor creature),
-- Scavenger's Eye (loot every corpse around you, filtered) and Waystones (ten
-- checkpoint shortcuts). The server owns every setting except the two
-- "automatic" switches of the Vendor, which are addon options (they only
-- decide when the addon sends the request).

local CHAT_PREFIX = "|cff00ff00[Project Ebonhold]|r "

local State = {
    received = false,
    owned = { bank = false, vendor = false, loot = false, mail = false, auction = false, guildBank = false, callboard = false },
    loot = { on = false, minQuality = 0, classMask = 4294967295, destroy = false, destroyMaxQuality = 0, destroyClassMask = 4294967295 },
    repairCost = 0,
    waystones = {},   -- [slot 0-9] = checkpointId
}

local listeners = {}

local function Notify()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, State)
        if not ok and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[ProjectEbonhold] toolbelt listener error:|r " .. tostring(err))
        end
    end
end

local function FormatMoney(copper)
    copper = tonumber(copper) or 0
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local s = ""
    if gold > 0 then s = gold .. "|cffffd700g|r " end
    if silver > 0 or gold > 0 then s = s .. silver .. "|cffc7c7c7s|r " end
    return s .. c .. "|cffeda55fc|r"
end

local function GetSetting(key)
    if ProjectEbonholdOptionsService then
        return ProjectEbonholdOptionsService:GetSetting(key)
    end
end

local function SetSetting(key, value)
    if ProjectEbonholdOptionsService then
        ProjectEbonholdOptionsService:SetSetting(key, value)
    end
end

-- ── State parsing ────────────────────────────────────────────────────────────
local function ParseState(body)
    local fields = {}
    for part in string.gmatch(body or "", "([^|]+)") do
        local k, v = part:match("^(%w+):(.*)$")
        if k then fields[k] = v end
    end

    State.owned.bank   = fields.bank == "1"
    State.owned.vendor = fields.vendor == "1"
    State.owned.loot   = fields.loot == "1"
    State.owned.mail   = fields.mail == "1"
    State.owned.auction = fields.ah == "1"
    State.owned.guildBank = fields.gbank == "1"
    State.owned.callboard = fields.cb == "1"
    State.owned.anvil = fields.anvil == "1"
    State.owned.forge = fields.forge == "1"
    State.loot.on = fields.on == "1"
    State.loot.minQuality = tonumber(fields.q) or 0
    State.loot.classMask = tonumber(fields.t) or 4294967295
    State.loot.destroy = fields.d == "1"
    State.loot.destroyMaxQuality = tonumber(fields.dq) or 0
    State.loot.destroyClassMask = tonumber(fields.dt) or 4294967295
    State.repairCost = tonumber(fields.repair) or 0

    State.waystones = {}
    for slot, id in string.gmatch(fields.ways or "", "(%d+)=(%d+)") do
        State.waystones[tonumber(slot)] = tonumber(id)
    end
    State.received = true
end

-- ── Requests ─────────────────────────────────────────────────────────────────
local Service = {}

function Service.Request()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TOOLBELT_STATE, "")
end

function Service.OpenBank()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TOOLBELT_OPEN_BANK, "")
end

function Service.OpenMailbox()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TOOLBELT_OPEN_MAIL, "")
end

function Service.OpenAuctionHouse()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TOOLBELT_OPEN_AUCTION, "")
end

-- The client only opens the guild bank from a vault it clicks: the server
-- pushes the bank contents, then its GBANK reply makes us show the frame.
function Service.OpenGuildBank()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TOOLBELT_GUILD_BANK, "")
end

-- Portable Forge: the server sets up a forge and an anvil beside the player.
-- Opening Blacksmithing, Mining, Engineering or Jewelcrafting does it by itself.
function Service.PlaceForge()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TOOLBELT_FORGE, "")
end

-- Same steps as UIParent's GUILDBANKFRAME_OPENED handler, minus the vault.
local function ShowGuildBankFrame()
    if not GuildBankFrame then
        if GuildBankFrame_LoadUI then GuildBankFrame_LoadUI() else LoadAddOn("Blizzard_GuildBankUI") end
    end
    if GuildBankFrame then
        ShowUIPanel(GuildBankFrame)
    end
end

-- Same rules as the merchant Scrap button (scrap_service.lua): qualities, item
-- types and the Alt-click lists live in the addon options.
-- An item sent once is taken as sold: it leaves the preview and the button is
-- not offered again for it. One the server refuses (still refundable, quest...)
-- stays in the bag but is never sent twice - spamming the button for those sent
-- enough addon messages for the server's anti-flood kick.
local sentSlots = {}   -- ["bag:slot"] = the item link sent from that slot

local function GetUnsentSellable()
    if not (ScrapService and ScrapService.GetSellableItems) then return {} end
    -- a slot the item left (sold, moved) is forgotten, so what lands there later counts again
    for key, link in pairs(sentSlots) do
        local bag, slot = key:match("^(%d+):(%d+)$")
        if GetContainerItemLink(tonumber(bag), tonumber(slot)) ~= link then sentSlots[key] = nil end
    end
    local items = {}
    for _, item in ipairs(ScrapService.GetSellableItems()) do
        if sentSlots[item.bag .. ":" .. item.slot] ~= item.link then
            table.insert(items, item)
        end
    end
    return items
end

function Service.Sell()
    local items = GetUnsentSellable()
    if #items == 0 then return false end
    for _, item in ipairs(items) do
        sentSlots[item.bag .. ":" .. item.slot] = item.link
    end
    local body = ""
    if ScrapService and ScrapService.BuildSellRulesBody then
        body = ScrapService.BuildSellRulesBody()
    end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TOOLBELT_SELL, body)
    Notify()
    return true
end

function Service.Repair()
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TOOLBELT_REPAIR, "")
end

-- fields: any of on, minQuality, classMask, destroy, destroyMaxQuality, destroyClassMask.
-- Unspecified fields keep their current value (the server replies with the full state).
function Service.SetLoot(fields)
    local l = State.loot
    local on = fields.on; if on == nil then on = l.on end
    local d = fields.destroy; if d == nil then d = l.destroy end
    local body = string.format("on:%d|q:%d|t:%d|d:%d|dq:%d|dt:%d",
        on and 1 or 0,
        fields.minQuality or l.minQuality,
        fields.classMask or l.classMask,
        d and 1 or 0,
        fields.destroyMaxQuality or l.destroyMaxQuality,
        fields.destroyClassMask or l.destroyClassMask)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_TOOLBELT_LOOT_SET, body)
end

function Service.SetWaystone(slot, checkpointId)
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_WAYSTONE_SET, string.format("%d:%d", slot, checkpointId or 0))
end

function Service.ClearWaystone(slot)
    Service.SetWaystone(slot, 0)
end

-- Travels like a click on the world map (REQUEST_USE_CHECKPOINT): that handler stores
-- the destination the travel spell teleports to once cast. REQUEST_WAYSTONE_USE only
-- casts the spell, so the cast finished and nothing happened.
function Service.UseWaystone(slot)
    local id = State.waystones[slot]
    if not id then return end
    ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_USE_CHECKPOINT, tostring(id))
end

function Service.GetState()
    return State
end

function Service.OnChange(fn)
    table.insert(listeners, fn)
end

function Service.FormatMoney(copper)
    return FormatMoney(copper)
end

-- ── Local helpers for the panels ─────────────────────────────────────────────
-- Number of items and total value the current rules would sell (client-side
-- estimate from the bags; the server decides the real list).
function Service.GetSellPreview()
    local items = GetUnsentSellable()
    local value = 0
    for _, item in ipairs(items) do value = value + item.value end
    return #items, value
end

-- Average durability of the equipped gear, in percent (nil when nothing has durability).
function Service.GetDurabilityPct()
    local cur, max = 0, 0
    for slot = 1, 18 do
        local c, m = GetInventoryItemDurability(slot)
        if c and m and m > 0 then
            cur = cur + c
            max = max + m
        end
    end
    if max == 0 then return nil end
    return math.floor(cur * 100 / max + 0.5)
end

-- ── Server replies ───────────────────────────────────────────────────────────
ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_TOOLBELT_STATE, function(body)
    ParseState(body)
    Notify()
end)

local FAIL_TEXT = {
    locked  = "This is not unlocked on this character. It is sold in the shop.",
    dead    = "You cannot do that while dead.",
    goldcap = "You are carrying too much gold to sell anything.",
    invalid = "Invalid waystone slot.",
    empty   = "That waystone slot is empty.",
    refused = "You cannot travel right now.",
    noguild = "You are not in a guild.",
}

ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_TOOLBELT_RESULT, function(body)
    local parts = {}
    -- Each field ends with a comma: in WoW's Lua 5.1, "([^,]*)" alone also yields an empty
    -- match after every comma, which shifted the fields (FAIL reasons showed "Request refused").
    for p in string.gmatch((body or "") .. ",", "([^,]*),") do table.insert(parts, p) end
    local kind = parts[1]

    if kind == "SELL" then
        local count, copper = tonumber(parts[2]) or 0, tonumber(parts[3]) or 0
        if count > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. string.format("Sold %d item%s for %s. Any vendor's buyback tab still has them.",
                count, count > 1 and "s" or "", FormatMoney(copper)))
        elseif not Service._silentSell then
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Nothing to sell.")
        end
        Service._silentSell = false
        Notify()
    elseif kind == "REPAIR" then
        local spent, remaining = tonumber(parts[2]) or 0, tonumber(parts[3]) or 0
        State.repairCost = remaining
        if spent > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Gear repaired for " .. FormatMoney(spent) .. ".")
        elseif remaining > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Not enough money to repair (" .. FormatMoney(remaining) .. " needed).")
        elseif not Service._silentRepair then
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Nothing to repair.")
        end
        Service._silentRepair = false
        Notify()
    elseif kind == "GBANK" then
        ShowGuildBankFrame()
    elseif kind == "FORGE" then
        local minutes = math.floor((tonumber(parts[2]) or 0) / 60)
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. string.format("A forge and an anvil stand beside you for %d minutes.", minutes))
    elseif kind == "FAIL" then
        local what, reason = parts[2], parts[3]
        if what == "WAYSTONE" and reason == "locked" then
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Your account has not discovered that waystone.")
        else
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. (FAIL_TEXT[reason] or ("Request refused (" .. tostring(reason) .. ")")))
        end
    end
end)

-- ── Automatic sale / repair when combat ends ─────────────────────────────────
local auto = CreateFrame("Frame")
auto:RegisterEvent("PLAYER_REGEN_ENABLED")
auto:RegisterEvent("PLAYER_ENTERING_WORLD")
auto:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        Service.Request()
        return
    end
    if not State.received or not State.owned.vendor then return end

    if GetSetting("vendorAutoSell") then
        local count = Service.GetSellPreview()
        if count > 0 then
            Service._silentSell = true
            Service.Sell()
        end
    end
    if GetSetting("vendorAutoRepair") then
        local pct = Service.GetDurabilityPct()
        if pct and pct < 100 then
            Service._silentRepair = true
            Service.Repair()
        end
    end
end)

_G.ToolbeltService = Service
ProjectEbonhold.ToolbeltService = Service
