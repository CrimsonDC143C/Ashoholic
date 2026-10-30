--[[----------------------------------------------------------------------------
    Collections visual shell — slash opener

    /collections        -> Echoes tab (1)
    /collections <n>    -> open tab n  (see character_progression.lua's 5-tab
    layout: 1 Echoes, 2 Skill Tree, 3 Transmogrify, 4 Mounts, 5 Companions.
    Loadouts is no longer a separate tab -- saving/switching loadouts lives
    in Echo Journal's My Run panel footer.)

    Toy Box and Library/Heirloom are removed from the XML/Lua directly (not
    hidden at runtime) and never occupy a tab id here. All 5 remaining ids are
    live tabs -- none are "removed" anymore, unlike the earlier bare-collections
    version of this shell (before the Character Progression merge).
------------------------------------------------------------------------------]]

-- Health check: /colldiag prints whether each piece loaded and how much data is present.
SLASH_PECOLLDIAG1 = "/colldiag"
SlashCmdList["PECOLLDIAG"] = function()
    local ez = _G.ezCollections
    local function line(s) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[colldiag]|r " .. s) end
    if not ez then line("ezCollections MISSING (stub failed to load)"); return end
    line("stub: ok  |  service helper GetMountFavoritesContainer: " .. tostring(type(ez.GetMountFavoritesContainer)))
    local cats, visuals = 0, 0
    if ez.AppearanceCatalog then
        for _, c in pairs(ez.AppearanceCatalog) do cats = cats + 1; visuals = visuals + #c.order end
    end
    line(("appearance catalog: %d categories, %d visuals (catalog %s)"):format(cats, visuals, ez.AppearanceCatalog and "loaded" or "MISSING"))
    local collected = 0; if ez.Collections and ez.Collections.Appearances then for _ in pairs(ez.Collections.Appearances) do collected = collected + 1 end end
    local slots = 0; if ez.TransmogSlots then for _ in pairs(ez.TransmogSlots) do slots = slots + 1 end end
    local outfits = 0; if ez.Outfits then for _ in pairs(ez.Outfits) do outfits = outfits + 1 end end
    line(("server data: %d collected visuals, %d transmog slots, %d outfits"):format(collected, slots, outfits))
    line("C_TransmogCollection.GetCategoryAppearances: " .. tostring(type(C_TransmogCollection and C_TransmogCollection.GetCategoryAppearances)))
    line("C_MountJournal.GetNumMounts: " .. tostring(C_MountJournal and C_MountJournal.GetNumMounts and C_MountJournal.GetNumMounts()))

    -- Trace the appearance pipeline for a category (default HEAD=1, or /colldiag <catID>)
    local catID = LE_TRANSMOG_COLLECTION_TYPE_HEAD or 1
    local apps = C_TransmogCollection.GetCategoryAppearances(catID)
    line(("category %d: GetCategoryAppearances -> %d visuals"):format(catID, apps and #apps or 0))
    if apps and apps[1] then
        local vid = apps[1].visualID
        local name = GetItemInfo(vid)
        local srcs = C_TransmogCollection.GetAppearanceSources(vid)
        local srcID = srcs and srcs[1] and srcs[1].sourceID
        local srcName = srcID and GetItemInfo(srcID)
        line(("  visual[1]=%s  GetItemInfo(visual)=%s"):format(tostring(vid), tostring(name)))
        line(("  sources=%d  source[1]=%s  GetItemInfo(source)=%s"):format(srcs and #srcs or 0, tostring(srcID), tostring(srcName)))
        local ok, cam = pcall(function() return C_TransmogCollection.GetAppearanceCameraID(vid, catID) end)
        line(("  camera pcall ok=%s value=%s"):format(tostring(ok), tostring(cam)))
        line("  (re-run /colldiag after a few seconds; GetItemInfo should turn from nil to a name)")
    end
end
SLASH_PECOLLDIAG2 = "/cd"

-- Live-tune the weapon rig's scale (bumps camera distance proportionally too,
-- via Model_ApplyUICamera's ratio*GetModelScale()) and, optionally, a fixed
-- override position/facing for fine-tuning on top of that:
-- /wrigtune <scale> <zoom> <side> <height> <facing>  (any omitted value keeps its current setting)
SLASH_PEWRIGTUNE1 = "/wrigtune"
SlashCmdList["PEWRIGTUNE"] = function(msg)
    local ez = _G.ezCollections
    local sc, z, s, h, f = msg:match("([%-%d%.]*)%s*([%-%d%.]*)%s*([%-%d%.]*)%s*([%-%d%.]*)%s*([%-%d%.]*)")
    if tonumber(sc) then ez.WeaponRigScale  = tonumber(sc) end
    if tonumber(z)  then ez.WeaponRigZoom   = tonumber(z) end
    if tonumber(s)  then ez.WeaponRigSide   = tonumber(s) end
    if tonumber(h)  then ez.WeaponRigHeight = tonumber(h) end
    if tonumber(f)  then ez.WeaponRigFacing = tonumber(f) end
    local scale, zoom, side, height, facing =
        rawget(ez, "WeaponRigScale") or 1, rawget(ez, "WeaponRigZoom") or 0,
        rawget(ez, "WeaponRigSide") or 0, rawget(ez, "WeaponRigHeight") or 0,
        rawget(ez, "WeaponRigFacing") or 0
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff66ccff[wrigtune]|r scale=%.2f zoom=%.2f side=%.2f height=%.2f facing=%.2f", scale, zoom, side, height, facing))
    -- Re-apply in place (avoid UpdateItems: needs filteredVisualsList, unsafe to call bare).
    local f2 = WardrobeCollectionFrame and WardrobeCollectionFrame.ItemsCollectionFrame
    if f2 and f2.Models then
        for _, m in ipairs(f2.Models) do
            if m.type == "main" or m.type == "off" then
                m:SetModelScale(scale)
                if z ~= "" or s ~= "" or h ~= "" or f ~= "" then
                    m:SetPosition(zoom, side, height)
                    m:SetFacing(facing)
                else
                    Model_ApplyUICamera(m, m.cameraID)  -- keep the real tuned weapon camera, just re-scaled
                end
            end
        end
    end
end

-- DIAGNOSTIC: swap the weapon-holder creature id and force the EXACT same reset
-- path (RefreshType -> SetType force -> ClearModel+SetCreature+SetAutoDress) that
-- weapon cells use, then re-apply the weapon. Use with a KNOWN VISIBLE creature id
-- (e.g. /wpcheck 17519, a plain human male NPC) to test whether SetCreature even
-- takes effect after ClearModel() on this client, independent of which id is used.
SLASH_PEWPCHECK1 = "/wpcheck"
SlashCmdList["PEWPCHECK"] = function(msg)
    local ez = _G.ezCollections
    local id = tonumber(msg and msg:match("%d+"))
    if id then ez.CreatureWeaponPreview = id end
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[wpcheck]|r CreatureWeaponPreview="..tostring(rawget(ez, "CreatureWeaponPreview")))
    local f = WardrobeCollectionFrame and WardrobeCollectionFrame.ItemsCollectionFrame
    if not f or not f.Models then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[wpcheck]|r no grid open"); return end
    local n = 0
    for _, m in ipairs(f.Models) do
        if m.type == "main" or m.type == "off" then
            n = n + 1
            m:RefreshType()  -- forces SetType(self.type, true); SetCreature() is now DEFERRED a frame
            local source = m.previewedSource
            C_Timer.After(0.05, function()  -- wait for the deferred SetCreature() before dressing
                if m.previewedSource == source and m:IsShown() then
                    if m.Undress then m:Undress() end
                    if m.SetItemAppearance then m:SetItemAppearance(source) end
                end
            end)
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[wpcheck]|r refreshed "..n.." weapon-typed model(s)")
end

-- Clear all applied transmog on the character, for free (also un-hides slots).
SLASH_PECLEARTMOG1 = "/cleartransmog"
SLASH_PECLEARTMOG2 = "/revert"
SlashCmdList["PECLEARTMOG"] = function()
    if C_Transmog and C_Transmog.ClearAllTransmog then
        C_Transmog.ClearAllTransmog()
    end
end

SLASH_PECOLLECTIONS1 = "/collections"
SLASH_PECOLLECTIONS2 = "/coll"
SlashCmdList["PECOLLECTIONS"] = function(msg)
    local tab = tonumber(msg and msg:match("%d+"))
    if tab and (tab < 1 or tab > 5) then tab = nil end
    if ToggleCollectionsJournal then
        ToggleCollectionsJournal(tab or 1)   -- default to Echoes
    elseif CollectionsJournal and CollectionsJournal.SetShown then
        CollectionsJournal:SetShown(not CollectionsJournal:IsShown())
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Collections]|r shell not loaded.")
    end
end
