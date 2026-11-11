-- See before_load.lua: what existed before the backport loaded stays, tables gain what they lack.
for name, previous in pairs(EBH_CRF_SHARED) do
    local mine = _G[name]
    if mine ~= previous then
        if type(previous) == "table" and type(mine) == "table" then
            for k, v in pairs(mine) do
                if previous[k] == nil then previous[k] = v end
            end
        end
        _G[name] = previous
    end
end
EBH_CRF_SHARED = nil
