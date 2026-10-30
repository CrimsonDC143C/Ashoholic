local ADDON_NAME = "ProjectEbonhold"
local PREFIX = "AAM0x9"

local addonName, addon = ...
addon.version = 37;
if not addon then addon = {} end

local CS = {
    SEND_HI                                   = 0,
    REQUEST_SHOP_DATA                         = 1,
    REQUEST_SHOP_PURCHASE                     = 2,
    REQUEST_ACCOUNT_DP                        = 3,
    REQUEST_SELL_JUNK_ITEMS                   = 4,
    REQUEST_LOADOUTS                          = 5,
    REQUEST_CREATE_LOADOUT                    = 7,
    REQUEST_LOADOUT_DELETE                    = 9,
    REQUEST_LOADOUT_SELECT                    = 10,
    REQUEST_AVOID_RESET_WITH_SOUL_POINTS      = 12,
    REQUEST_AVOID_RESET_WITH_SELF_REZ         = 13,
    REQUEST_PLAYER_RUN_DATA                   = 14,
    REQUEST_PLAYER_SOUL_POINTS_ADDITIONAL_PCT = 15,
    REQUEST_PLAYER_PERK_CHOICE                = 16,
    REQUEST_PLAYER_PERK_SELECTION             = 17,
    REQUEST_PLAYER_GRANTED_PERKS              = 18,
    REQUEST_PLAYER_ADD_ITEM_ITEM_SAVED        = 19,
    REQUEST_PLAYER_ITEMS_SAVED                = 20,
    REQUEST_INTENSITY_POINTS                  = 22,
    REQUEST_APPLY_SPECS                       = 23,
    REQUEST_CURRENT_SPEC                      = 24,
    REQUEST_RESET_TALENT_TREE                 = 25,
    REQUEST_ACCEPT_DEATH                      = 26,
    REQUEST_REROLL                            = 27,
    REQUEST_LOADOUT_UPDATE                    = 28,
    REQUEST_VERSION_CHECK                     = 29,
    REQUEST_LOCK_PERK                         = 30,
    REQUEST_UNLOCK_PERK                       = 31,
    REQUEST_ACCEPT_HIGHER_INTENSITY           = 32,
    REQUEST_SET_USING_VOID_STORAGE            = 50,
    REQUEST_RETRIEVE_VOID_STORAGE_ITEM        = 51,
    REQUEST_RETRIEVE_ITEMS_FROM_TAB           = 52,
    REQUEST_OBJECTIVES_PROPOSALS              = 200,
    REQUEST_SELECT_OBJECTIVE                  = 201,
    REQUEST_UNLOCK_PLAYER                     = 202,
    REQUEST_BANISH_PERK                       = 203,
    REQUEST_DEV_ADD_PERK_STACK                = 204,
    REQUEST_DEV_REMOVE_PERK_STACK             = 205,
    REQUEST_REROLL_OBJECTIVES                 = 206,
    REQUEST_FREEZE_PERK                       = 207,

    REQUEST_HARDMODE_DATA                     = 300,
    REQUEST_HARDMODE_SET_DIFFICULTY           = 301,

    -- Extraction Events
    REQUEST_AFFIX_EXTRACTION                  = 310,
    REQUEST_AFFIX_EXTRACTION_INFO             = 311,
    REQUEST_AFFIX_APPLY                       = 312,
    REQUEST_LEARNED_AFFIXES                   = 313,
    REQUEST_AFFIX_APPLY_INFO                  = 314,

    REQUEST_UNLEARN_SPELL_ECHOES              = 315,
    -- Custom GM ticket creation (workaround for blocked Blizzard UI path)
    REQUEST_CREATE_GM_TICKET                  = 320,
    -- Persistent echo discovery across runs (Echo Journal collection tab)
    REQUEST_ECHO_DISCOVERY                    = 330,
    -- Echo loadouts, community sharing (Echo Journal "Loadouts" tab):
    -- LOADOUTS_SHARED body is an optional class token filter ("WARRIOR"; empty = all);
    -- PUBLISH body is "name|class|id.q.stacks,...";
    -- UNPUBLISH body is "name|class" (server deletes the sender's own entry)
    REQUEST_ECHO_LOADOUTS_SHARED              = 331,
    REQUEST_ECHO_LOADOUT_PUBLISH              = 332,
    REQUEST_ECHO_LOADOUT_UNPUBLISH            = 333,
    -- Perk Loadouts: server-verified snapshots of the player's own build
    -- (5 slots per character). SAVE body is "slot|name" (server snapshots the
    -- CURRENT build - content is never uploaded); RENAME is "slot|newName";
    -- DELETE is "slot"; ACTIVATE is "slot" (0 = deactivate; at level 1 it arms
    -- the run's draw guarantee, at level 80 it performs a full build swap).
    REQUEST_PERK_LOADOUTS                     = 340,
    REQUEST_PERK_LOADOUT_SAVE                 = 341,
    REQUEST_PERK_LOADOUT_RENAME               = 342,
    REQUEST_PERK_LOADOUT_DELETE               = 343,
    REQUEST_PERK_LOADOUT_ACTIVATE             = 344,
    REQUEST_PERK_LOADOUT_UNLOCK               = 345, -- body: empty; buys the next locked slot with gold (account-wide)
    REQUEST_PERK_LOADOUT_UPLOAD               = 346, -- body: slot|name|id.stack.locked,...; stores a DESIGNED build (highlight-only)
    REQUEST_TOME_TOGGLE                       = 347, -- body: tomeSpellId|enable(0/1); level 1 only, replaces tome unlearning
    -- Promotes a RECOVERABLE wishlist (a build a reset downgraded, flagged
    -- server-side) into a real build slot: body is "wishlistSlot|targetSlot",
    -- targetSlot 0 = the first free unlocked slot. The wishlist is moved, not copied.
    REQUEST_PERK_LOADOUT_RECOVER              = 348,
    REQUEST_ACTION_TRACKER_INFO               = 600,
    REQUEST_INSTANCE_RESET_ALL                = 601,
    REQUEST_CHECKPOINTS_DATA                  = 800,
    REQUEST_USE_CHECKPOINT                    = 801,

    -- Collections (mounts / pets / transmog appearances). See
    -- modules\collections\PROTOCOL.md and modules\collections\server\collections.sql.
    REQUEST_COLLECTIONS                       = 1100, -- body: "" (all) or "mounts"/"pets"/"appearances"/"transmog"
    REQUEST_SUMMON_MOUNT                      = 1110, -- body: spellId            (phase 2 action)
    REQUEST_SUMMON_PET                        = 1111, -- body: spellId            (phase 2 action)
    REQUEST_APPLY_TRANSMOG                    = 1112, -- body: "slot:item ..."     (phase 2; item 0 = hidden)
    REQUEST_CLEAR_TRANSMOG                    = 1113, -- body: slot ("" = all)    (phase 2 action)
    REQUEST_APPLY_ILLUSION                    = 1114, -- body: "slot:enchantId ..." (0 = remove; server writes PLAYER_VISIBLE_ITEM_x_ENCHANTMENT)

    -- Transmog outfits (server-side, bridged to player->presetMap)
    REQUEST_OUTFITS                           = 1120, -- body: "" - request the outfit list
    REQUEST_OUTFIT_SAVE                       = 1121, -- body: "name|slot:entry,slot:entry,..."
    REQUEST_OUTFIT_RENAME                     = 1122, -- body: "id|newName"
    REQUEST_OUTFIT_DELETE                     = 1123, -- body: "id"
    REQUEST_OUTFIT_APPLY                      = 1124, -- body: "id"

    -- Creature cache on demand. SetCreature(creatureID) draws nothing when the
    -- creature is missing from the client's local cache (creaturecache.wdb),
    -- and the client cannot query one itself. The server replies with the
    -- creature-query response, which the client caches and keeps across
    -- sessions. Asked for one model at a time, only when a preview fails to
    -- load: pushing the whole catalogue on login froze the loading screen.
    REQUEST_CREATURE_CACHE                    = 1130, -- body: "entry entry ..."

    -- Prestige (full Accept-Death-style reset + Skill Tree wipe, permanent
    -- and infinite nodes kept). See modules\prestige\.
    REQUEST_PRESTIGE_DATA                     = 1200, -- body: "" - ask for the player's prestige status
    REQUEST_DO_PRESTIGE                       = 1201, -- body: "" - perform a prestige. The server re-verifies the
                                                      -- gate (Soul Ashes committed since the last prestige >= last
                                                      -- SoulAshesMilestones entry), runs the Accept Death reset,
                                                      -- wipes the tree (permanent/infinite kept), grants newly
                                                      -- reached milestone rewards, replies SEND_PRESTIGE_RESULT.

    -- Aura experience bonuses opt-out (heirlooms / skill tree / perk XP buffs).
    -- Base experience is never affected; only SPELL_AURA_MOD_XP_PCT is suppressed.
    REQUEST_XP_AURA_BONUS_STATE               = 1210, -- body: "" - ask for the current state
    REQUEST_XP_AURA_BONUS_SET                 = 1211, -- body: "0" (bonuses on) or "1" (bonuses off)

    -- Orb of Lost Memories: forget one stack of an owned Echo, roll a fresh choice for it.
    -- The server re-derives ownership, lock state and the charge; the body is only a hint.
    REQUEST_ORB_CHARGES                       = 1220, -- body: "" - ask for the unspent count
    REQUEST_ORB_CONSUME                       = 1221, -- body: "<orbCount>|<perkSpellId>[,<perkSpellId>...]"
    REQUEST_ORB_REROLL                        = 1222, -- body: "" - spend one more orb to redraw an
                                                      -- offer an orb already paid for. Nothing to name:
                                                      -- the server holds the choice and the owed count.
}

local SS = {
    SEND_ACKNOWLEDGEMENT                      = 0,
    SEND_SHOP_DATA                            = 1,
    SEND_ACCOUNT_DP                           = 2,
    SEND_LOADOUTS                             = 3,
    SEND_CREATED_LOADOUT                      = 4,
    SEND_UPDATED_LOADOUT                      = 5,

    SEND_SKILL_TREE_UPDATE_SPELL_CAST_RESULT  = 6,
    SEND_INSTANCE_ENTERED                     = 9,
    SEND_INSTANCE_ENCOUNTERS_COMPLETED        = 10,
    SEND_INSTANCE_ENCOUNTERS_HIDE             = 11,
    SEND_JUNK_SOLD                            = 12,
    SEND_PLAYER_RUN_DATA                      = 13,
    SEND_PLAYER_SOUL_POINTS_MULTIPLIER        = 14,
    SEND_PLAYER_UPDATED_COMMITTED_SOUL_POINTS = 15,
    SEND_PLAYER_PERK_CHOICE                   = 16,
    SEND_PLAYER_PERK_SELECTION_RESULT         = 1000,
    SEND_PLAYER_PERK_GRANTED                  = 18,
    SEND_PLAYER_ITEMS_SAVED                   = 21,
    SEND_PLAYER_INTENSITY_POINTS              = 30,
    SEND_PLAYER_LEARNED_SPELL_ON_LEVEL_UP     = 31,
    SEND_PLAYER_SPEC_INDEX                    = 32,
    SEND_WRONG_PATCH                          = 33,
    SEND_CONTENT_VOID_STORAGE                 = 100,
    SEND_OBJECTIVES_PROPOSALS                 = 101,
    SEND_CURRENT_OBJECTIVE                    = 102,
    SEND_BANISH_REPLACEMENT_PERK              = 103,
    SEND_FREEZE_PERK_RESULT                   = 104,
    SEND_HARDMODE_DATA                        = 500,
    SEND_HARDMODE_SET_RESULT                  = 501,
    -- A Hardcore rank was just unlocked by crossing its committed-Soul-Ash gate.
    -- Body: comma-separated ranks, ascending, e.g. "1" or "3,4". Rank R == difficulty tier R+1.
    -- Sent only at the crossing, so it never repeats on login or on a Soul Ash update.
    SEND_HARDCORE_TIER_UNLOCKED               = 502,

    -- Extraction Events
    SEND_AFFIX_EXTRACTION_RESULT              = 510,
    SEND_AFFIX_EXTRACTION_INFO                = 511,
    SEND_AFFIX_APPLY_RESULT                   = 512,
    SEND_LEARNED_AFFIXES                      = 513,
    SEND_AFFIX_APPLY_INFO                     = 514,

    SEND_UNLEARN_SPELL_RESULT                 = 515,
    -- Result of REQUEST_CREATE_GM_TICKET: "OK,<ticketId>" or "FAIL,<reason>"
    SEND_GM_TICKET_CREATE_RESULT              = 520,
    -- Reply to REQUEST_ECHO_DISCOVERY: "spellId[:timesObtained],spellId,..."
    SEND_ECHO_DISCOVERY                       = 530,
    -- Reply to REQUEST_ECHO_LOADOUTS_SHARED: "author|name|class|id.q.stacks,...;..."
    SEND_ECHO_LOADOUTS_SHARED                 = 531,
    -- Perk Loadouts. LOADOUTS body: "activeSlot|maxSlots;slot|name|id.stack.locked,...;..."
    -- ("" when the feature is disabled server-side). RESULT body: "OK,<op>,<slot>"
    -- or "FAIL,<op>,<reason>". ACTIVE body: the active slot ("0" = none), pushed
    -- on login and whenever it changes.
    SEND_PERK_LOADOUTS                        = 540,
    SEND_PERK_LOADOUT_RESULT                  = 541,
    SEND_PERK_LOADOUT_ACTIVE                  = 542,
    SEND_ACTION_TRACKER_INFO                  = 700,
    SEND_INSTANCE_RESET_RESULT                = 701,
    SEND_CHECKPOINTS_DATA                     = 800,
    SEND_PLAYER_IS_BLOCKED                    = 900,
    SEND_RAID_BOSS_OVERFLOW_HEALTH            = 950,

    -- Collections. Snapshots replace the whole set; deltas mutate one entry.
    SEND_COLLECTED_MOUNTS                     = 1100, -- body: "spellId spellId ..."        (snapshot)
    SEND_COLLECTED_PETS                       = 1101, -- body: "spellId spellId ..."        (snapshot)
    SEND_COLLECTED_APPEARANCES                = 1102, -- body: "itemId itemId ..."          (snapshot)
    SEND_TRANSMOG_SLOTS                       = 1103, -- body: "slot:item[:illusion] ..."   (snapshot; item 0 = hidden)
    SEND_MOUNT_LEARNED                        = 1104, -- body: spellId                       (delta)
    SEND_PET_LEARNED                          = 1105, -- body: spellId                       (delta)
    SEND_APPEARANCE_LEARNED                   = 1106, -- body: itemId                        (delta)
    SEND_TRANSMOG_SLOT_UPDATE                 = 1107, -- body: "slot:item[:illusion]"        (delta; item 0 = hidden, -1 = cleared)
    SEND_TRANSMOG_OUTFITS                     = 1108, -- body: "max;id|name|slot:entry,...;..." (snapshot of outfits)

    -- Prestige. DATA body: "<totalPrestiges>;<gateProgress>" (gateProgress =
    -- Soul Ashes committed since the last prestige; reply to
    -- REQUEST_PRESTIGE_DATA, also pushed on login and after a prestige).
    -- RESULT body: "OK,<totalPrestiges>" or "FAIL,<reason>" (gate|combat|dead).
    SEND_PRESTIGE_DATA                        = 1200,
    SEND_PRESTIGE_RESULT                      = 1201,

    -- Current aura-experience-bonus opt-out state: "0" (bonuses active) or "1" (suppressed).
    -- Pushed on login and after every REQUEST_XP_AURA_BONUS_SET.
    SEND_XP_AURA_BONUS_STATE                  = 1210,

    -- Unspent Orbs of Lost Memories, as a string. Pushed on login and after every grant or
    -- spend, so the client never tracks the count itself.
    SEND_ORB_CHARGES                          = 1220,
}

local ServerHandlers = {}
local function onEventReceived(id, fn) ServerHandlers[id] = fn end

local function sendToServer(id, body)
    local me = UnitName("player")
    local payload = tostring(id)
    if body and body ~= "" then payload = payload .. "\t" .. body end

    local MAX_PAYLOAD_SIZE = 240

    if string.len(payload) <= MAX_PAYLOAD_SIZE then
        SendAddonMessage(PREFIX, payload, "WHISPER", me)
    else
        local bodyToChunk = body or ""
        local chunks = {}
        local MAX_CHUNK_SIZE = 180

        local pos = 1

        while pos <= string.len(bodyToChunk) do
            local chunk = string.sub(bodyToChunk, pos, pos + MAX_CHUNK_SIZE - 1)
            table.insert(chunks, chunk)
            pos = pos + MAX_CHUNK_SIZE
        end

        local mid = string.format("%04X", math.random(0, 65535))
        local total = #chunks

        for idx, chunk in ipairs(chunks) do
            local chunkPayload = string.format("%s\t@%s\t%03X/%03X\t%s",
                tostring(id), mid, idx, total, chunk)
            SendAddonMessage(PREFIX, chunkPayload, "WHISPER", me)
        end
    end
end

CharacterAmmoSlot:SetScript("OnShow", function() CharacterAmmoSlot:Hide() end)
SetCVar("UberTooltips", 1)

local inflight = {}

local function now() return GetTime() end
local function cleanupExpired()
    local t = now()
    for k, v in pairs(inflight) do
        if t - (v.t0 or t) > 15 then inflight[k] = nil end
    end
end

local function dispatch(prefix, payload, dist, sender)
    if prefix ~= PREFIX then return end
    local evtStr, rest = payload:match("^(%d+)\t(.*)$")
    if not evtStr then return end -- silently dropped!
    local evt = tonumber(evtStr, 10)

    local mid, idx, tot, slice = rest:match(
        "^@([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])\t([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])/([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])\t(.*)$")
    if mid then
        local key = evt .. ":" .. mid
        local rec = inflight[key]
        if not rec then
            rec = { total = tonumber(tot, 16), got = 0, parts = {}, t0 = now() }
            inflight[key] = rec
        end
        local i = tonumber(idx, 16)
        if i >= 1 and i <= rec.total and not rec.parts[i] then
            rec.parts[i] = slice
            rec.got = rec.got + 1
        end
        if rec.got == rec.total then
            local out = table.concat(rec.parts, "", 1, rec.total)
            inflight[key] = nil
            local handler = ServerHandlers[evt]
            if handler then
                local ok, err = pcall(handler, out, dist, sender, evt)
                if not ok then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cffff0000[ProjectEbonhold] handler error:|r " ..
                        tostring(err))
                end
            end
        end
        cleanupExpired()
        return
    end

    local handler = ServerHandlers[evt]
    if handler then
        local ok, err = pcall(handler, rest, dist, sender, evt)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffff0000[ProjectEbonhold] handler error:|r " .. tostring(err))
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:SetScript("OnEvent", function(_, e, ...)
    if e == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            if RegisterAddonMessagePrefix then
                RegisterAddonMessagePrefix(PREFIX)
            end
        end
    elseif e == "CHAT_MSG_ADDON" then
        local prefix, payload, dist, sender = ...

        if not payload or payload == "" then
            return
        end
        dispatch(prefix, payload, dist, sender)
    elseif e == "PLAYER_ENTERING_WORLD" then
    elseif e == "PLAYER_LEVEL_UP" then
    end
end)

ProjectEbonhold = ProjectEbonhold or {}
ProjectEbonhold.SS = SS
ProjectEbonhold.CS = CS
ProjectEbonhold.onEventReceived = onEventReceived
ProjectEbonhold.sendToServer = sendToServer

-- Ask the server to put a creature in the client's cache so SetCreature() can
-- draw its model (see REQUEST_CREATURE_CACHE above). There is no reply to wait
-- for: the answer is a plain creature-query response the client absorbs on its
-- own, so callers simply retry their model a moment later.
--
-- Deduped for the whole session: a second ask would change nothing, either the
-- first answer landed or the creature does not exist server side.
local requestedCreatures = {}
function ProjectEbonhold.RequestCreatureCache(creatureID)
    creatureID = tonumber(creatureID)
    if not creatureID or creatureID <= 0 then return false end
    if requestedCreatures[creatureID] then return false end
    requestedCreatures[creatureID] = true
    sendToServer(CS.REQUEST_CREATURE_CACHE, tostring(creatureID))
    return true
end

function TargetFrame_CheckClassification(self, forceNormalTexture)
    local texture;
    local classification = UnitClassification(self.unit);
    local intensityData = _G["EbonholdIntensityData"] or {}
    local intensityLevel = intensityData.intensity or 0
    if (classification == "worldboss" or classification == "elite") then
        texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite";
    elseif (classification == "rareelite") then
        texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite";
    elseif (classification == "rare") then
        texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare";
    end
    if (texture and not forceNormalTexture) then
        self.borderTexture:SetTexture(texture);
        self.haveElite = true;
        if (self.threatIndicator) then
            self.threatIndicator:SetTexCoord(0, 0.9453125, 0.181640625, 0.400390625);
            self.threatIndicator:SetWidth(242);
            self.threatIndicator:SetHeight(112);
            self.threatIndicator:SetPoint("TOPLEFT", self, "TOPLEFT", -22, 9);
        end
    else
        self.borderTexture:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame");
        self.haveElite = nil;
        if (self.threatIndicator) then
            self.threatIndicator:SetTexCoord(0, 0.9453125, 0, 0.181640625);
            self.threatIndicator:SetWidth(242);
            self.threatIndicator:SetHeight(93);
            self.threatIndicator:SetPoint("TOPLEFT", self, "TOPLEFT", -24, 0);
        end
    end
end
