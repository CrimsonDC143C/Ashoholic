function ezCollections.PackSkin(info)
    local data = "";
    local function write(fmt, value, transform)
        if value then
            if transform then
                data = data .. format(fmt, transform(value));
            else
                data = data .. format(fmt, value);
            end
        end
    end
    write("I%u", info.InventoryType, function(value) return value - 1; end);
    write("Q%s", info.SourceQuests, function(value) if type(value) == "string" then return value:gsub(",", "Q"); elseif type(value) == "table" then return strjoin("Q", unpack(value)); end end);
    write("B%s", info.SourceBosses, function(value) if type(value) == "string" then return value:gsub(",", "B"); elseif type(value) == "table" then return strjoin("B", unpack(value)); end end);
    write("H%u", info.Holiday);
    write("C%u", info.Camera);
    write("U", info.Unusable);
    write("O", info.Unobtainable);
    write("E", info.Weapon and info.Enchantable);
    write("W", info.Weapon and not info.Enchantable);
    write("A%u", info.Armor);
    write("S%02X", info.SourceMask and info.SourceMask > 0xFFFFFF and bit.band(bit.rshift(info.SourceMask, 24), 0xFF) or nil);
    write("S%02X", info.SourceMask and info.SourceMask > 0xFFFF and bit.band(bit.rshift(info.SourceMask, 16), 0xFF) or nil);
    write("S%02X", info.SourceMask and info.SourceMask > 0xFF and bit.band(bit.rshift(info.SourceMask, 8), 0xFF) or nil);
    write("S%02X", info.SourceMask and bit.band(info.SourceMask, 0xFF) or nil);
    write("L%X", info.ClassMask);
    write("R%X", info.RaceMask);
    write("T\"%s\"", info.Icon);
    write("x", info.Expansion == 1);
    write("X", info.Expansion == 2);
    write("V%u", info.VisualID);
    write("v%u", info.UiOrderByVisual);
    return data;
end

local function match(data, start, pattern, func)
    local s, e, group = data:find(pattern, start);
    if s and e and group and s == start then
        func(group);
        return e + 1;
    end
end

function ezCollections.UnpackSkin(data)
    local info = { };
    local i = 1;
    while i do
        i= match(data, i, "I(%d+)", function(value) info.InventoryType = tonumber(value) + 1; end)
        or match(data, i, "Q([Q%d]+)", function(value) info.SourceQuests = value:gsub("Q", ","); end)
        or match(data, i, "B([B%d]+)", function(value) info.SourceBosses = value:gsub("B", ","); end)
        or match(data, i, "H(%d+)", function(value) info.Holiday = tonumber(value); end)
        or match(data, i, "C(%d+)", function(value) info.Camera = tonumber(value); end)
        or match(data, i, "U()", function(value) info.Unusable = true; end)
        or match(data, i, "O()", function(value) info.Unobtainable = true; end)
        or match(data, i, "E()", function(value) info.Weapon = true; info.Enchantable = true; end)
        or match(data, i, "W()", function(value) info.Weapon = true; end)
        or match(data, i, "A(%d+)", function(value) info.Armor = tonumber(value); end)
        or match(data, i, "S(%x%x)", function(value) info.SourceMask = bit.bor(bit.lshift(info.SourceMask or 0, 8), tonumber(value, 16)); end)
        or match(data, i, "L(%x+)", function(value) info.ClassMask = tonumber(value, 16); end)
        or match(data, i, "R(%x+)", function(value) info.RaceMask = tonumber(value, 16); end)
        or match(data, i, "T\"(.-)\"", function(value) info.Icon = value; end)
        or match(data, i, "([xX])", function(value) info.Expansion = value == "x" and 1 or 2; end)
        or match(data, i, "V(%d+)", function(value) info.VisualID = tonumber(value); end)
        or match(data, i, "v(%d+)", function(value) info.UiOrderByVisual = tonumber(value); end)
    end
    return info;
end
