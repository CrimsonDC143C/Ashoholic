-- ============================================================================
-- FastSwap GlueXML Auto-Login Hook + Live Diagnostic Monitor
-- ============================================================================
local SLOT_PREFIX = "fastSwapSlot"
local DONE_PREFIX = "fastSwapDone"
local MAX_SWAP_SLOTS = 100
local DRIVER_BRIDGE_CVAR = "Sound_VoiceChatInputDriverName"
local CVAR_NAME = "fastSwapTarget"
local FASTSWAP_POLL_INTERVAL = 0.15
local FASTSWAP_ENTER_DELAY = 0.35
local FASTSWAP_FALLBACK_DELAY = 1.50

local fastSwapGlueFrame = CreateFrame("Frame", "FastSwapGlueFrame")
local fastSwapPollElapsed = 0
local fastSwapDelayElapsed = 0
local fastSwapClock = 0
local fastSwapPendingIndex = nil
local fastSwapPrimaryEnterCalled = false
local fastSwapQueuedTarget = nil
local fastSwapConsumedSlots = {}
local fastSwapConsumedTarget = false
local fastSwapLastLoggedState = nil

-- ============================================================================
-- On-Screen GlueXML Live Diagnostic Monitor (Disabled by Default)
-- ============================================================================
local SHOW_GLUE_MONITOR = false
local monitorFrame = nil
local monitorStatusText = nil
local monitorCVarText = nil
local monitorTraceText = nil
local monitorTraces = {}
local monitorHiddenByUser = false
local monitorStatusState = "Idle (waiting for swap target)"

local function FastSwap_EnsureMonitor()
    if not SHOW_GLUE_MONITOR or monitorHiddenByUser then
        return nil
    end
    if monitorFrame then
        return monitorFrame
    end
    if not CharacterSelect or not CreateFrame then
        return nil
    end

    local ok, f = pcall(function()
        local box = CreateFrame("Frame", "FastSwapGlueMonitorFrame", CharacterSelect)
        box:SetWidth(430)
        box:SetHeight(145)
        box:SetPoint("TOPLEFT", CharacterSelect, "TOPLEFT", 16, -16)
        box:SetFrameStrata("HIGH")
        box:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })

        local title = box:CreateFontString(nil, "ARTWORK", "GlueFontNormalSmall")
        title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
        title:SetText("|cff00ccff[FastSwap Glue Monitor]|r")

        local closeBtn = CreateFrame("Button", nil, box)
        closeBtn:SetWidth(20)
        closeBtn:SetHeight(20)
        closeBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -6)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        closeBtn:SetScript("OnClick", function()
            monitorHiddenByUser = true
            box:Hide()
        end)

        local statusFs = box:CreateFontString(nil, "ARTWORK", "GlueFontHighlightSmall")
        statusFs:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        statusFs:SetWidth(406)
        statusFs:SetJustifyH("LEFT")

        local cvarFs = box:CreateFontString(nil, "ARTWORK", "GlueFontHighlightSmall")
        cvarFs:SetPoint("TOPLEFT", statusFs, "BOTTOMLEFT", 0, -3)
        cvarFs:SetWidth(406)
        cvarFs:SetJustifyH("LEFT")

        local traceFs = box:CreateFontString(nil, "ARTWORK", "GlueFontHighlightSmall")
        traceFs:SetPoint("TOPLEFT", cvarFs, "BOTTOMLEFT", 0, -5)
        traceFs:SetWidth(406)
        traceFs:SetJustifyH("LEFT")
        traceFs:SetJustifyV("TOP")

        monitorStatusText = statusFs
        monitorCVarText = cvarFs
        monitorTraceText = traceFs
        return box
    end)

    if ok and f then
        monitorFrame = f
    end
    return monitorFrame
end

local function FastSwap_UpdateMonitorDisplay(slotIndex, slotTarget, drvVal, customVal, numChars)
    pcall(function()
        local box = FastSwap_EnsureMonitor()
        if not box then
            return
        end
        if monitorStatusText then
            monitorStatusText:SetText("Status: " .. tostring(monitorStatusState))
        end
        if monitorCVarText then
            local sel = (GetCharacterSelection and GetCharacterSelection()) or "?"
            monitorCVarText:SetText(string.format(
                "CVars: slot=%s('%s') | fastSwapTarget='%s' | chars=%s (sel=%s)",
                tostring(slotIndex or "none"),
                tostring(slotTarget or ""),
                tostring(customVal or "nil"),
                tostring(numChars or 0),
                tostring(sel)
            ))
        end
        if monitorTraceText then
            monitorTraceText:SetText(table.concat(monitorTraces, "\n"))
        end
    end)
end

local function FastSwap_Trace(msg, statusOverride)
    log("FastSwap Glue: " .. tostring(msg))
    if statusOverride then
        monitorStatusState = statusOverride
    end
    local stamp = string.format("[%.2fs] %s", fastSwapClock, tostring(msg))
    table.insert(monitorTraces, stamp)
    while #monitorTraces > 5 do
        table.remove(monitorTraces, 1)
    end
    pcall(function()
        if monitorFrame then
            if monitorStatusText then
                monitorStatusText:SetText("Status: " .. tostring(monitorStatusState))
            end
            if monitorTraceText then
                monitorTraceText:SetText(table.concat(monitorTraces, "\n"))
            end
        end
    end)
end

-- ============================================================================
-- Core GlueXML Auto-Selection & EnterWorld Logic
-- ============================================================================
local function FastSwap_ApplySelection(index)
    local beforeSel = (GetCharacterSelection and GetCharacterSelection()) or "nil"
    if CharacterSelect_SelectCharacter then
        CharacterSelect_SelectCharacter(index, 1)
    end
    if SelectCharacter then
        SelectCharacter(index)
    end
    local afterSel = (GetCharacterSelection and GetCharacterSelection()) or "nil"
    FastSwap_Trace("SelectCharacter(" .. tostring(index) .. ") (selected: " .. tostring(beforeSel) .. " -> " .. tostring(afterSel) .. ")")
end

local function FastSwap_StartEnterWorldTimer(targetIndex, targetName)
    fastSwapDelayElapsed = 0
    fastSwapPendingIndex = targetIndex
    fastSwapPrimaryEnterCalled = false
    monitorStatusState = "|cff00ff00Selected #" .. tostring(targetIndex) .. " (" .. tostring(targetName) .. ") — entering in 0.35s...|r"
end

local function FastSwap_CheckSlotCVars()
    if not GetCVar then
        return nil, nil
    end
    local latestTarget = nil
    local latestSlot = nil
    for i = 1, MAX_SWAP_SLOTS do
        local slotName = SLOT_PREFIX .. i
        local okSlot, slotVal = pcall(GetCVar, slotName)
        if not okSlot or slotVal == nil then
            break
        end
        local doneName = DONE_PREFIX .. i
        local okDone, doneVal = pcall(GetCVar, doneName)
        local isDone = (okDone and doneVal == "1") or fastSwapConsumedSlots[i]
        if not isDone and type(slotVal) == "string" and slotVal ~= "" then
            latestTarget = slotVal
            latestSlot = i
        end
    end
    return latestTarget, latestSlot
end

local function FastSwap_OnCharacterListUpdate(triggerSource)
    if fastSwapPendingIndex then
        return
    end
    if not GetCVar or not SetCVar or not GetNumCharacters or not GetCharacterInfo then
        return
    end

    local slotTarget, slotIndex = FastSwap_CheckSlotCVars()
    local okDrv, drvVal = pcall(GetCVar, DRIVER_BRIDGE_CVAR)
    local okCustom, customVal = pcall(GetCVar, CVAR_NAME)
    local numChars = GetNumCharacters() or 0

    local stateSnapshot = tostring(slotIndex or "none") .. ":" .. tostring(slotTarget or "")
        .. "|" .. tostring(okDrv and drvVal or "nil")
        .. "|" .. tostring(okCustom and customVal or "nil")
        .. "|" .. tostring(fastSwapQueuedTarget or "")
        .. "|" .. tostring(numChars)

    if triggerSource ~= "OnUpdate" or stateSnapshot ~= fastSwapLastLoggedState then
        fastSwapLastLoggedState = stateSnapshot
        FastSwap_Trace("checking CVars (src=" .. tostring(triggerSource or "unknown")
            .. ", slot=" .. tostring(slotIndex or "none") .. "='" .. tostring(slotTarget or "")
            .. "', drv='" .. tostring(okDrv and drvVal or nil)
            .. "', target='" .. tostring(okCustom and customVal or nil)
            .. "', chars=" .. tostring(numChars) .. ")")
    end

    -- 1. Check sequential RegisterCVar slot (survives LeaveWorld reset-to-default)
    if slotTarget and slotIndex then
        for i = 1, slotIndex do
            fastSwapConsumedSlots[i] = true
            pcall(SetCVar, SLOT_PREFIX .. i, "")
        end
        fastSwapQueuedTarget = slotTarget
        FastSwap_Trace(
            "intercepted " .. SLOT_PREFIX .. tostring(slotIndex) .. "='" .. tostring(slotTarget) .. "'",
            "|cff00ff00Intercepted " .. SLOT_PREFIX .. tostring(slotIndex) .. " -> " .. tostring(slotTarget) .. "|r"
        )
    end

    -- 2. Check global Config.wtf driver CVar bridge and restore immediately
    if okDrv and type(drvVal) == "string" then
        local matchedTarget, origValue = string.match(drvVal, "^FASTSWAP:([^:]+):?(.*)")
        if matchedTarget and matchedTarget ~= "" then
            local restoreVal = (origValue and origValue ~= "") and origValue or "System Default"
            pcall(SetCVar, DRIVER_BRIDGE_CVAR, restoreVal)
            if not fastSwapQueuedTarget then
                fastSwapQueuedTarget = matchedTarget
            end
            FastSwap_Trace(
                "intercepted driver CVar='" .. tostring(matchedTarget) .. "', restored='" .. tostring(restoreVal) .. "'",
                "|cff00ff00Intercepted driver CVar -> " .. tostring(matchedTarget) .. "|r"
            )
        end
    end

    -- 3. Check fastSwapTarget fallback
    if okCustom and type(customVal) == "string" and customVal ~= "" and not fastSwapConsumedTarget then
        fastSwapConsumedTarget = true
        pcall(SetCVar, CVAR_NAME, "")
        if not fastSwapQueuedTarget then
            fastSwapQueuedTarget = customVal
            FastSwap_Trace(
                "intercepted fastSwapTarget='" .. tostring(customVal) .. "'",
                "|cff00ff00Intercepted fastSwapTarget -> " .. tostring(customVal) .. "|r"
            )
        end
    end

    FastSwap_UpdateMonitorDisplay(slotIndex, slotTarget, okDrv and drvVal or nil, okCustom and customVal or nil, numChars)

    local target = fastSwapQueuedTarget
    if not target or target == "" then
        return
    end

    if numChars <= 0 then
        FastSwap_Trace(
            "target '" .. tostring(target) .. "' queued until character list is ready (numChars=0)",
            "|cffffd100Waiting for character list (target=" .. tostring(target) .. ")...|r"
        )
        return
    end

    -- Clear queued target immediately so it can never loop
    fastSwapQueuedTarget = nil

    local foundIndex = nil
    local matchedName = target
    local numericTarget = tonumber(target)
    local charSummary = {}
    for i = 1, numChars do
        local cname = GetCharacterInfo(i)
        table.insert(charSummary, tostring(i) .. "=" .. tostring(cname or "?"))
    end
    log("FastSwap Glue: roster (" .. tostring(numChars) .. "): " .. table.concat(charSummary, ", "))

    if numericTarget then
        local idx = math.floor(numericTarget)
        if idx >= 1 and idx <= numChars then
            foundIndex = idx
            matchedName = GetCharacterInfo(idx) or tostring(idx)
        end
    else
        local lowerTarget = string.lower((string.gsub(target, "^%s*(.-)%s*$", "%1")))
        for i = 1, numChars do
            local name = GetCharacterInfo(i)
            if name and string.lower((string.gsub(name, "^%s*(.-)%s*$", "%1"))) == lowerTarget then
                foundIndex = i
                matchedName = name
                break
            end
        end
    end

    if foundIndex then
        FastSwap_Trace(
            "resolved '" .. tostring(target) .. "' -> slot #" .. tostring(foundIndex) .. " (" .. tostring(matchedName) .. ")",
            "|cff00ff00Matched slot #" .. tostring(foundIndex) .. " (" .. tostring(matchedName) .. ")|r"
        )
        FastSwap_ApplySelection(foundIndex)
        FastSwap_StartEnterWorldTimer(foundIndex, matchedName)
    else
        FastSwap_Trace(
            "ERROR: target '" .. tostring(target) .. "' not found in " .. tostring(numChars) .. " chars",
            "|cffff4040Target '" .. tostring(target) .. "' not found on character list!|r"
        )
    end
end

pcall(fastSwapGlueFrame.RegisterEvent, fastSwapGlueFrame, "CHARACTER_LIST_UPDATE")
pcall(fastSwapGlueFrame.RegisterEvent, fastSwapGlueFrame, "ADDON_LOADED")
pcall(fastSwapGlueFrame.RegisterEvent, fastSwapGlueFrame, "GLUE_SCREEN_CHANGE")

fastSwapGlueFrame:SetScript("OnEvent", function(self, event)
    FastSwap_OnCharacterListUpdate(event)
end)

fastSwapGlueFrame:SetScript("OnUpdate", function(self, elapsed)
    local dt = elapsed or 0
    fastSwapClock = fastSwapClock + dt

    if fastSwapPendingIndex then
        fastSwapDelayElapsed = fastSwapDelayElapsed + dt
        if not fastSwapPrimaryEnterCalled and fastSwapDelayElapsed >= FASTSWAP_ENTER_DELAY then
            fastSwapPrimaryEnterCalled = true
            local idx = fastSwapPendingIndex
            FastSwap_ApplySelection(idx)
            if CharacterSelect_EnterWorld then
                FastSwap_Trace(
                    "calling CharacterSelect_EnterWorld() for slot #" .. tostring(idx),
                    "|cff00ff00Calling CharacterSelect_EnterWorld() (slot #" .. tostring(idx) .. ")...|r"
                )
                CharacterSelect_EnterWorld()
            elseif EnterWorld then
                FastSwap_Trace(
                    "calling EnterWorld() for slot #" .. tostring(idx),
                    "|cff00ff00Calling EnterWorld() (slot #" .. tostring(idx) .. ")...|r"
                )
                EnterWorld()
            end
        elseif fastSwapPrimaryEnterCalled and fastSwapDelayElapsed >= FASTSWAP_FALLBACK_DELAY then
            local idx = fastSwapPendingIndex
            fastSwapPendingIndex = nil
            fastSwapDelayElapsed = 0
            fastSwapPrimaryEnterCalled = false
            if CharacterSelect and CharacterSelect:IsShown() and EnterWorld then
                FastSwap_ApplySelection(idx)
                FastSwap_Trace(
                    "fallback calling EnterWorld() for slot #" .. tostring(idx),
                    "|cff00ff00Fallback EnterWorld() (slot #" .. tostring(idx) .. ")...|r"
                )
                EnterWorld()
            end
        end
        return
    end

    fastSwapPollElapsed = fastSwapPollElapsed + dt
    if fastSwapPollElapsed < FASTSWAP_POLL_INTERVAL then
        return
    end
    fastSwapPollElapsed = 0

    if CharacterSelect and CharacterSelect:IsShown() and GetNumCharacters and (GetNumCharacters() or 0) > 0 then
        FastSwap_OnCharacterListUpdate("OnUpdate")
    end
end)

FastSwap_Trace("hook armed")
