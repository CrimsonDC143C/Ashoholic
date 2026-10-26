-- FastSwap.lua
-- WoW 3.3.5a (build 12340) In-Game Addon for Project Ebonhold
-- Passes target character name or index to GlueXML via sequential RegisterCVar
-- default-value slots ("fastSwapSlot1".."fastSwapSlotN" / "fastSwapDone1".."fastSwapDoneN")
-- plus global Config.wtf CVar ("Sound_VoiceChatInputDriverName") fallback.

local ADDON_NAME = "FastSwap"
local SLOT_PREFIX = "fastSwapSlot"
local DONE_PREFIX = "fastSwapDone"
local MAX_SWAP_SLOTS = 100
local DRIVER_BRIDGE_CVAR = "Sound_VoiceChatInputDriverName"
local CVAR_NAME = "fastSwapTarget"
local BRIDGE_PREFIX = "FASTSWAP:"
local PREFIX = "|cff00ccff[FastSwap]|r "

local CLASS_COLORS = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {}

local activeSwapTarget = nil
local activeSwapSlot = nil

local function Log(msg)
    if EbonholdLog then
        pcall(EbonholdLog, "FastSwap Game: " .. tostring(msg))
    end
end

local function EnsureSwapCVar()
    if RegisterCVar and GetCVar("fastSwapTarget") == nil then
        pcall(RegisterCVar, "fastSwapTarget", "")
    end
end

local function GetOriginalDriverValue()
    if not GetCVar then
        return "System Default"
    end
    local ok, cur = pcall(GetCVar, DRIVER_BRIDGE_CVAR)
    if not ok or type(cur) ~= "string" or cur == "" then
        return "System Default"
    end
    local existingTarget, existingOrig = string.match(cur, "^FASTSWAP:([^:]+):?(.*)")
    if existingTarget then
        return (existingOrig and existingOrig ~= "") and existingOrig or "System Default"
    end
    return cur
end

local function MarkAllSwapSlotsDone()
    if not GetCVar or not RegisterCVar then
        return false
    end
    local markedAny = false
    for i = 1, MAX_SWAP_SLOTS do
        local slotName = SLOT_PREFIX .. i
        local doneName = DONE_PREFIX .. i
        local okSlot, slotVal = pcall(GetCVar, slotName)
        if not okSlot or slotVal == nil then
            break
        end
        local okDone, doneVal = pcall(GetCVar, doneName)
        if not okDone or doneVal == nil then
            pcall(RegisterCVar, doneName, "1")
            markedAny = true
            Log("marked " .. doneName .. "=1 (was slotVal='" .. tostring(slotVal) .. "')")
        end
        if SetCVar then
            pcall(SetCVar, doneName, "1")
            pcall(SetCVar, slotName, "")
        end
    end
    return markedAny
end

local function AllocateSwapSlot(target)
    if not GetCVar or not RegisterCVar then
        return nil
    end
    -- Mark any earlier slots as done first so only the newly allocated slot is active
    MarkAllSwapSlotsDone()

    for i = 1, MAX_SWAP_SLOTS do
        local slotName = SLOT_PREFIX .. i
        local okSlot, slotVal = pcall(GetCVar, slotName)
        if not okSlot or slotVal == nil then
            -- Register with defaultValue = target so LeaveWorld's CVar reset-to-default
            -- on Logout() preserves target into GlueXML!
            pcall(RegisterCVar, slotName, tostring(target))
            if SetCVar then
                pcall(SetCVar, slotName, tostring(target))
            end
            local okVerify, verifyVal = pcall(GetCVar, slotName)
            Log("allocated " .. slotName .. "='" .. tostring(verifyVal) .. "' for target='" .. tostring(target) .. "'")
            return i
        end
    end
    return nil
end

local function Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
    end
end

local function Trim(str)
    if type(str) ~= "string" then
        return ""
    end
    return (string.gsub(str, "^%s*(.-)%s*$", "%1"))
end

local function GetClassColorHex(classFile)
    local color = classFile and CLASS_COLORS[ string.upper(classFile) ]
    if color and color.r and color.g and color.b then
        return string.format("%02x%02x%02x", math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5)), color.r, color.g, color.b
    end
    return "ffd100", 1.0, 0.82, 0.0
end

local function EnsureDB()
    if type(FastSwapDB) ~= "table" then
        FastSwapDB = {}
    end
    local realm = (GetRealmName and GetRealmName()) or "Unknown"
    if type(FastSwapDB[realm]) ~= "table" then
        FastSwapDB[realm] = {}
    end
    return FastSwapDB[realm], realm
end

-- Opportunistically backfill known characters on this realm from DataStore_CharactersDB if present
local function BackfillFromDataStore(realmTable, realm)
    if type(DataStore_CharactersDB) ~= "table" then
        return
    end
    local global = DataStore_CharactersDB.global
    local chars = global and global.Characters
    if type(chars) ~= "table" then
        return
    end
    local prefix = "Default." .. realm .. "."
    local prefixLen = string.len(prefix)
    for key, data in pairs(chars) do
        if type(key) == "string" and type(data) == "table" and string.sub(key, 1, prefixLen) == prefix then
            local charName = data.name or string.sub(key, prefixLen + 1)
            if charName and charName ~= "" and not realmTable[charName] then
                realmTable[charName] = {
                    name = charName,
                    class = data.class or data.englishClass or "Unknown",
                    classFile = data.englishClass or string.upper(tostring(data.class or "UNKNOWN")),
                    level = tonumber(data.level) or 1,
                    realm = realm,
                    lastSeen = tonumber(data.lastLogoutTimestamp) or tonumber(data.lastUpdate) or 0,
                }
            end
        end
    end
end

-- Record current character on PLAYER_ENTERING_WORLD / PLAYER_LEVEL_UP
local function BackfillFromAshoholic(realmTable, realm)
    if type(AshoholicDB) ~= "table" or type(AshoholicDB.global) ~= "table" then
        return
    end
    local chars = AshoholicDB.global.Characters
    if type(chars) ~= "table" then
        return
    end
    local prefix = realm .. "."
    local prefixLen = string.len(prefix)
    for key, data in pairs(chars) do
        if type(key) == "string" and type(data) == "table" and string.sub(key, 1, prefixLen) == prefix then
            local charName = data.name or string.sub(key, prefixLen + 1)
            if charName and charName ~= "" and not realmTable[charName] then
                local classFile = string.upper(tostring(data.class or "UNKNOWN"))
                local locClass = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or data.class or "Unknown"
                realmTable[charName] = {
                    name = charName,
                    class = locClass,
                    classFile = classFile,
                    level = tonumber(data.level) or 1,
                    realm = realm,
                    lastSeen = tonumber(data.lastSeen) or 0,
                }
            end
        end
    end
end

local function RecordCurrentCharacter(overrideLevel)
    local realmTable, realm = EnsureDB()
    BackfillFromDataStore(realmTable, realm)
    BackfillFromAshoholic(realmTable, realm)

    local charName = UnitName and UnitName("player")
    if not charName or charName == "" or charName == UNKNOWNOBJECT or charName == "Unknown" then
        return
    end

    local localizedClass, englishClass = "Unknown", "UNKNOWN"
    if UnitClass then
        local loc, eng = UnitClass("player")
        localizedClass = loc or localizedClass
        englishClass = eng or englishClass
    end

    local level = tonumber(overrideLevel) or (UnitLevel and UnitLevel("player")) or 1

    realmTable[charName] = {
        name = charName,
        class = localizedClass,
        classFile = englishClass,
        level = level,
        realm = realm,
        lastSeen = time and time() or 0,
    }
end

-- Perform the swap to target character name or 1-based slot index
local function PerformSwap(target)
    target = Trim(target)
    if target == "" then
        Print("Usage: |cffffd100/swap <charName or slotIndex>|r, |cffffd100/swap list|r, or |cffffd100/swap ui|r")
        return
    end

    if UnitAffectingCombat and UnitAffectingCombat("player") then
        local errMsg = "Cannot fast-swap while in combat!"
        Print("|cffff4040" .. errMsg .. "|r")
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(errMsg, 1.0, 0.1, 0.1, 1.0)
        end
        return
    end

    local currentName = UnitName and UnitName("player")
    if currentName and string.lower(currentName) == string.lower(target) then
        Print("|cffffd100You are already logged into " .. currentName .. ".|r")
        return
    end

    if not SetCVar then
        Print("|cffff4040Error: SetCVar is unavailable.|r")
        return
    end

    -- Resolve exact stored casing when possible for cleaner messaging
    local realmTable, realm = EnsureDB()
    BackfillFromDataStore(realmTable, realm)
    BackfillFromAshoholic(realmTable, realm)
    local displayTarget = target
    for charName in pairs(realmTable) do
        if string.lower(charName) == string.lower(target) then
            displayTarget = charName
            break
        end
    end

    -- 1. Allocate a fresh RegisterCVar slot whose defaultValue is displayTarget
    --    (survives WoW 3.3.5a's LeaveWorld reset-to-default on Logout)
    activeSwapTarget = tostring(displayTarget)
    activeSwapSlot = AllocateSwapSlot(displayTarget)

    -- 2. Also set global Config.wtf CVar Sound_VoiceChatInputDriverName as backup
    local origDriver = GetOriginalDriverValue()
    pcall(SetCVar, DRIVER_BRIDGE_CVAR, BRIDGE_PREFIX .. tostring(displayTarget) .. ":" .. tostring(origDriver))

    -- 3. Also set fastSwapTarget (if not registered yet, register with displayTarget as default)
    if RegisterCVar and GetCVar(CVAR_NAME) == nil then
        pcall(RegisterCVar, CVAR_NAME, tostring(displayTarget))
    end
    pcall(SetCVar, CVAR_NAME, tostring(displayTarget))

    Log("PerformSwap initiating Logout() -> target='" .. tostring(displayTarget) .. "' (slot=" .. tostring(activeSwapSlot) .. ")")
    Print("Swapping to |cff00ff00" .. tostring(displayTarget) .. "|r...")

    if FastSwapFrame and FastSwapFrame:IsShown() then
        FastSwapFrame:Hide()
    end
    if AshoholicFrame and AshoholicFrame:IsShown() then
        AshoholicFrame:Hide()
    end
    if GameMenuFrame and GameMenuFrame:IsShown() and HideUIPanel then
        HideUIPanel(GameMenuFrame)
    end

    if Logout then
        Logout()
    end
end

_G.FastSwap_PerformSwap = PerformSwap
_G.FastSwap_EnsureSwapCVar = EnsureSwapCVar

-- Return sorted list of characters recorded for the current realm
local function GetSortedRealmCharacters()
    local realmTable, realm = EnsureDB()
    local list = {}
    for charName, info in pairs(realmTable) do
        if type(info) == "table" then
            table.insert(list, {
                name = info.name or charName,
                class = info.class or "Unknown",
                classFile = info.classFile or string.upper(tostring(info.class or "UNKNOWN")),
                level = tonumber(info.level) or 1,
                realm = info.realm or realm,
            })
        end
    end

    table.sort(list, function(a, b)
        if a.level ~= b.level then
            return a.level > b.level
        end
        return string.lower(a.name) < string.lower(b.name)
    end)

    return list, realm
end

local function PrintCharacterList()
    local list, realm = GetSortedRealmCharacters()
    if #list == 0 then
        Print("No characters recorded yet for realm |cffffd100" .. realm .. "|r.")
        return
    end

    local currentName = UnitName and UnitName("player")
    Print("Recorded characters on |cffffd100" .. realm .. "|r (" .. #list .. "):")
    for i = 1, #list do
        local entry = list[i]
        local hex = GetClassColorHex(entry.classFile)
        local activeTag = (currentName and string.lower(currentName) == string.lower(entry.name)) and " |cff80ff80(Current)|r" or ""
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  |cffaaaaaa%d.|r |cff%s%s|r - Level %d %s%s",
            i,
            hex,
            entry.name,
            entry.level,
            entry.class,
            activeTag
        ))
    end
end

-- ============================================================================
-- Draggable 3.3.5a Alt List UI Frame
-- ============================================================================
local uiFrame = nil
local uiButtons = {}

local ROW_HEIGHT = 24
local ROW_SPACING = 3
local FRAME_WIDTH = 220

local function RefreshUI()
    if not uiFrame then
        return
    end

    local list, realm = GetSortedRealmCharacters()
    local currentName = UnitName and UnitName("player")
    uiFrame.realmText:SetText(realm)

    local count = #list
    for i = 1, count do
        local entry = list[i]
        local btn = uiButtons[i]
        if not btn then
            btn = CreateFrame("Button", "FastSwapAltButton" .. i, uiFrame)
            btn:SetWidth(FRAME_WIDTH - 24)
            btn:SetHeight(ROW_HEIGHT)
            btn:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })

            btn.nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.nameText:SetPoint("LEFT", btn, "LEFT", 8, 0)
            btn.nameText:SetJustifyH("LEFT")

            btn.infoText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.infoText:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
            btn.infoText:SetJustifyH("RIGHT")

            btn:SetScript("OnEnter", function(self)
                if self.isCurrent then
                    self:SetBackdropBorderColor(0.4, 0.8, 0.4, 1.0)
                else
                    self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
                    self:SetBackdropColor(self.r * 0.35, self.g * 0.35, self.b * 0.35, 0.9)
                end
            end)

            btn:SetScript("OnLeave", function(self)
                if self.isCurrent then
                    self:SetBackdropBorderColor(0.3, 0.7, 0.3, 0.9)
                    self:SetBackdropColor(0.12, 0.22, 0.12, 0.85)
                else
                    self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                    self:SetBackdropColor(self.r * 0.18, self.g * 0.18, self.b * 0.18, 0.85)
                end
            end)

            btn:SetScript("OnClick", function(self)
                if self.charName then
                    PerformSwap(self.charName)
                end
            end)

            uiButtons[i] = btn
        end

        btn:ClearAllPoints()
        btn:SetPoint("TOP", uiFrame, "TOP", 0, -48 - (i - 1) * (ROW_HEIGHT + ROW_SPACING))

        local hex, r, g, b = GetClassColorHex(entry.classFile)
        local isCurrent = (currentName and string.lower(currentName) == string.lower(entry.name)) or false

        btn.charName = entry.name
        btn.r, btn.g, btn.b = r, g, b
        btn.isCurrent = isCurrent

        btn.nameText:SetText(string.format("|cff%s%s|r", hex, entry.name))
        if isCurrent then
            btn.infoText:SetText(string.format("|cff80ff80Lv %d (You)|r", entry.level))
            btn:SetBackdropBorderColor(0.3, 0.7, 0.3, 0.9)
            btn:SetBackdropColor(0.12, 0.22, 0.12, 0.85)
        else
            btn.infoText:SetText(string.format("|cffccccccLv %d %s|r", entry.level, entry.class))
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            btn:SetBackdropColor(r * 0.18, g * 0.18, b * 0.18, 0.85)
        end

        btn:Show()
    end

    for i = count + 1, #uiButtons do
        uiButtons[i]:Hide()
    end

    local totalRows = math.max(count, 1)
    local totalHeight = 60 + totalRows * (ROW_HEIGHT + ROW_SPACING)
    uiFrame:SetHeight(totalHeight)
end

local function CreateUIFrame()
    if uiFrame then
        return uiFrame
    end

    local f = CreateFrame("Frame", "FastSwapFrame", UIParent)
    f:SetWidth(FRAME_WIDTH)
    f:SetHeight(120)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("|cff00ccffFastSwap|r")

    local realmText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    realmText:SetPoint("TOP", title, "BOTTOM", 0, -2)
    realmText:SetTextColor(0.75, 0.75, 0.75)
    f.realmText = realmText

    local closeBtn = CreateFrame("Button", "FastSwapFrameCloseButton", f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    f:SetScript("OnShow", function()
        RefreshUI()
    end)

    if UISpecialFrames then
        table.insert(UISpecialFrames, "FastSwapFrame")
    end

    f:Hide()
    uiFrame = f
    return f
end

local function ToggleUI()
    local f = CreateUIFrame()
    if f:IsShown() then
        f:Hide()
    else
        RefreshUI()
        f:Show()
    end
end

-- ============================================================================
-- Game Menu (Escape Menu) Cleanup
-- ============================================================================
-- Game Menu button intentionally removed so FastSwap buttons live cleanly inside
-- the Ashoholic UI (and /swap command). If a button was created earlier in the
-- session before a /reload, hide it.
local function RemoveGameMenuButton()
    if _G.GameMenuButtonFastSwap then
        _G.GameMenuButtonFastSwap:Hide()
    end
end

local function PrintDebugStatus()
    Print("Diagnostic Status:")
    if GetCVar then
        local okTarget, valTarget = pcall(GetCVar, CVAR_NAME)
        local okDrv, valDrv = pcall(GetCVar, DRIVER_BRIDGE_CVAR)
        Print("  fastSwapTarget = |cffffd100" .. tostring(okTarget and valTarget or "nil") .. "|r")
        Print("  " .. DRIVER_BRIDGE_CVAR .. " = |cffffd100" .. tostring(okDrv and valDrv or "nil") .. "|r")
        for i = 1, MAX_SWAP_SLOTS do
            local slotName = SLOT_PREFIX .. i
            local doneName = DONE_PREFIX .. i
            local okS, sVal = pcall(GetCVar, slotName)
            if not okS or sVal == nil then
                if i == 1 then
                    Print("  No fastSwapSlot* CVars allocated yet in this session.")
                end
                break
            end
            local okD, dVal = pcall(GetCVar, doneName)
            Print(string.format("  %s = '|cff00ff00%s|r' (%s = %s)", slotName, tostring(sVal), doneName, tostring(okD and dVal or "nil")))
        end
    end
    Print("  Live log file: |cff00ccff%LOCALAPPDATA%\\ebonhold\\ebonhold.log|r")
end

-- ============================================================================
-- Slash Commands (/swap)
-- ============================================================================
SLASH_FASTSWAP1 = "/swap"
SLASH_FASTSWAP2 = "/fastswap"
SlashCmdList["FASTSWAP"] = function(msg)
    local input = Trim(msg)
    local lower = string.lower(input)

    if input == "" or lower == "ui" then
        ToggleUI()
        return
    end

    if lower == "list" then
        PrintCharacterList()
        return
    end

    if lower == "debug" or lower == "status" then
        PrintDebugStatus()
        return
    end

    PerformSwap(input)
end

-- Clear any pending fast-swap CVar (e.g. when a 20s logout is canceled or on /reload)
local function ClearPendingSwap(announce)
    activeSwapTarget = nil
    activeSwapSlot = nil
    if not SetCVar then
        return
    end
    local hadPending = MarkAllSwapSlotsDone()

    if GetCVar then
        local okDrv, drvVal = pcall(GetCVar, DRIVER_BRIDGE_CVAR)
        if okDrv and type(drvVal) == "string" then
            local pendingTarget, origValue = string.match(drvVal, "^FASTSWAP:([^:]+):?(.*)")
            if pendingTarget and pendingTarget ~= "" then
                hadPending = true
                pcall(SetCVar, DRIVER_BRIDGE_CVAR, (origValue and origValue ~= "") and origValue or "System Default")
            end
        end

        local okCustom, current = pcall(GetCVar, CVAR_NAME)
        if okCustom and current and current ~= "" then
            hadPending = true
            pcall(SetCVar, CVAR_NAME, "")
        end
    end

    if announce and hadPending then
        Log("Logout canceled (verified still in-world) — cleared pending character swap")
        Print("|cffffd100Logout canceled — cleared pending character swap.|r")
    end
end

-- ============================================================================
-- Event Handling
-- ============================================================================
-- IMPORTANT: On Project Ebonhold, the server/client fires LOGOUT_CANCEL during
-- the final milliseconds of a successful logout right before transitioning to
-- GlueXML! Clearing the CVar synchronously inside LOGOUT_CANCEL wipes the swap
-- target right before GlueXML loads. Instead, we wait 1.5s on an OnUpdate
-- verification timer: if the player actually logged out, FrameXML unloads
-- immediately and the timer never runs; if the player genuinely canceled a 20s
-- logout countdown and stayed in the world, the timer fires 1.5s later and
-- clears the pending swap.
local cancelVerifyFrame = CreateFrame("Frame", "FastSwapCancelVerifyFrame")
cancelVerifyFrame:Hide()
local cancelVerifyElapsed = 0

cancelVerifyFrame:SetScript("OnUpdate", function(self, elapsed)
    cancelVerifyElapsed = cancelVerifyElapsed + (elapsed or 0)
    if cancelVerifyElapsed >= 1.5 then
        self:Hide()
        cancelVerifyElapsed = 0
        ClearPendingSwap(true)
    end
end)

local function ReassertActiveSwapCVars(reason)
    if not activeSwapTarget or activeSwapTarget == "" then
        return
    end
    cancelVerifyFrame:Hide()
    cancelVerifyElapsed = 0
    if SetCVar then
        if activeSwapSlot then
            pcall(SetCVar, SLOT_PREFIX .. activeSwapSlot, activeSwapTarget)
        end
        local origDriver = GetOriginalDriverValue()
        pcall(SetCVar, DRIVER_BRIDGE_CVAR, BRIDGE_PREFIX .. activeSwapTarget .. ":" .. tostring(origDriver))
        EnsureSwapCVar()
        pcall(SetCVar, CVAR_NAME, activeSwapTarget)
    end
    Log("re-asserted swap CVars on " .. tostring(reason) .. " for target='" .. tostring(activeSwapTarget) .. "'")
end

local eventFrame = CreateFrame("Frame", "FastSwapEventFrame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("LOGOUT_CANCEL")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        cancelVerifyFrame:Hide()
        cancelVerifyElapsed = 0
        ClearPendingSwap(false)
        RecordCurrentCharacter()
        RemoveGameMenuButton()
        if uiFrame and uiFrame:IsShown() then
            RefreshUI()
        end
    elseif event == "PLAYER_LEVEL_UP" then
        RecordCurrentCharacter(arg1)
        if uiFrame and uiFrame:IsShown() then
            RefreshUI()
        end
    elseif event == "LOGOUT_CANCEL" then
        Log("LOGOUT_CANCEL event fired (activeSwapTarget='" .. tostring(activeSwapTarget or "") .. "') — deferring 1.5s to verify if still in-world")
        cancelVerifyElapsed = 0
        cancelVerifyFrame:Show()
    elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
        ReassertActiveSwapCVars(event)
    end
end)
