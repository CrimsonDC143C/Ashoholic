function ezCollections:GetMountInfo(spellID)
    local info = ezCollections.Cache.Mounts[spellID] or ezCollections.Mounts[spellID];
    if info then
        return unpack(info, 1, 9);
    end
end

local function match(data, start, pattern, func)
    local s, e, group = data:find(pattern, start);
    if s and e and group and s == start then
        func(group);
        return e + 1;
    end
end

function ezCollections:TestRequirementsString(data)
    if not data or data == "" then
        return true;
    end
    local failed = false;
    local spells;
    local i = 1;
    while i and not failed do
        i= match(data, i, "S(%d+)", function(value) spells = spells or { }; table.insert(spells, tonumber(value)); end)
        or match(data, i, "L(%x+)", function(value) failed = bit.band(tonumber(value, 16), bit.lshift(1, (ezCollections.ClassNameToID[select(2, UnitClass("player")) or ""] or 0) - 1)) == 0; end)
        or match(data, i, "R(%x+)", function(value) failed = bit.band(tonumber(value, 16), bit.lshift(1, (ezCollections.RaceNameToID[strupper(select(2, UnitRace("player")) or "")] or 0) - 1)) == 0; end)
    end
    if not failed and spells then
        failed = true;
        for _, spell in ipairs(spells) do
            if IsSpellKnown(spell) then
                failed = false;
                break;
            end
        end
    end
    return not failed;
end

local function Set(index, value, ...)
    for i = 1, select("#", ...) do
        local info = ezCollections.Mounts[select(i, ...)];
        if info then
            info[index] = value;
        end
    end
end

Set(2, 6, 48025, 71342, 72286, 75614); -- Flying mounts that have scripted ground version
-- Set(8, 0, 23509, 32243, 32244, 32245, 32246, 32295, 32296, 32297, 34767, 34769, 55531, 59788, 59797, 60116, 60119, 61230, 61447, 61467, 61469, 61997, 64659, 66088, 66091, 68056, 68188) -- Spells with "Horde Specific Spell" attribute
Set(8, 0, 61447, 68188, 16081, 64658, 22722, 22721, 22724, 16084, 18990, 61230, 60119, 64659, 18989, 61467, 65639, 65645, 68056, 17465, 23251, 59788, 59793, 66846, 6654, 8395, 23509, 32243, 32246, 63641, 63643, 6653, 22718, 23243, 32245, 32297, 55531, 63640, 63642, 10796, 32244, 35020, 59797, 60116, 17450, 23250, 32296, 35027, 61469, 61997, 17463, 64977, 65641, 66091, 23241, 63635, 580, 17462, 18991, 23246, 32295, 35028, 65644, 18992, 23242, 23252, 33660, 35018, 35022, 66088, 23248, 23249, 34795, 64657, 65646, 10799, 16080, 17464, 23247, 35025); -- Horde mounts from Wowhead
-- Set(8, 1, 13819, 17229, 23214, 23510, 32235, 32239, 32240, 32242, 32289, 32290, 32292, 59785, 59799, 60114, 60118, 60424, 61229, 61425, 61465, 61470, 61996, 66087, 66090, 68057, 68187) -- Spells with "Alliance Specific Spell" attribute
Set(8, 1, 16055, 61425, 16056, 60424, 17229, 16083, 458, 32290, 23225, 61470, 68187, 59799, 61996, 6899, 10789, 32240, 59791, 66090, 6898, 8394, 32292, 61465, 65637, 6648, 63638, 470, 63232, 10793, 10873, 16082, 17459, 17460, 22723, 32235, 32239, 48027, 63637, 17454, 22720, 23222, 23239, 32242, 35711, 60114, 472, 10969, 23221, 23240, 23338, 35710, 35714, 66847, 68057, 6777, 17461, 23219, 23227, 32289, 59785, 15779, 22717, 23510, 61229, 63636, 63639, 65638, 65640, 17453, 22719, 23223, 23229, 23238, 34406, 35712, 35713, 65642, 65643, 66087, 23228, 60118); -- Alliance mounts from Wowhead
Set(9, function() return IsSpellKnown(51309); end, 61309, 75596); -- Tailoring 425
Set(9, function() return IsSpellKnown(51309) or IsSpellKnown(26790) or IsSpellKnown(12180); end, 61451); -- Tailoring 300
Set(9, function() return IsSpellKnown(51306) or IsSpellKnown(30350); end, 44151); -- Engineering 375
Set(9, function() return IsSpellKnown(51306) or IsSpellKnown(30350) or IsSpellKnown(12656); end, 44153); -- Engineering 300
Set(9, function() return select(2, UnitClass("player")) == "DEATHKNIGHT"; end, 48778, 54729);
Set(9, function() return select(2, UnitClass("player")) == "PALADIN"; end, 73629, 73630, 69820, 69826, 13819, 23214, 66906);
Set(9, function() return select(2, UnitClass("player")) == "PALADIN" and select(2, UnitRace("player")) == "BloodElf"; end, 34767, 34769);
Set(9, function() return select(2, UnitClass("player")) == "WARLOCK"; end, 5784, 23161);
ezCollections.Mounts[66122] = nil; -- Magic Rooster - normal version
ezCollections.Mounts[66123] = nil; -- Magic Rooster - draenei male version
ezCollections.Mounts[66124] = nil; -- Magic Rooster - tauren male version
