local __orderedIndex = { };
function ezCollections:Ordered(tbl, sorter)
    local function __genOrderedIndex(t)
        local orderedIndex = { };
        for key in pairs(t) do
            table.insert(orderedIndex, key);
        end
        if sorter then
            table.sort(orderedIndex, function(a, b)
                return sorter(t[a], t[b], a, b);
            end);
        else
            table.sort(orderedIndex);
        end
        return orderedIndex;
    end

    local function orderedNext(t, state)
        local key;
        if state == nil then
            __orderedIndex[t] = __genOrderedIndex(t)
            key = __orderedIndex[t][1];
        else
            for i = 1, table.getn(__orderedIndex[t]) do
                if __orderedIndex[t][i] == state then
                    key = __orderedIndex[t][i + 1];
                end
            end
        end

        if key then
            return key, t[key];
        end

        __orderedIndex[t] = nil;
        return
    end

    return orderedNext, tbl, nil;
end

function ezCollections:IterateOverTableOrValue(tbl)
    if type(tbl) == "table" then
        return ipairs(tbl);
    end

    local function next(t, i)
        if i == 0 then
            return 1, t;
        end
    end

    return next, tbl, tbl and 0;
end

function ezCollections:InsertIntoTableOrSetValue(container, key, value)
    local old = container[key];
    if not old then
        container[key] = value;
    elseif type(old) ~= "table" then
        container[key] = { old, value };
    else
        table.insert(old, value);
    end
end
