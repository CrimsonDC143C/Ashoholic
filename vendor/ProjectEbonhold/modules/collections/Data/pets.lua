function ezCollections:GetPetInfo(spellID)
    local info = ezCollections.Cache.Pets[spellID] or ezCollections.Pets[spellID];
    if info then
        return unpack(info, 1, 7);
    end
end

for _, pet in ipairs({ 10699, 75613, 66175, 10708, 30152 }) do
    ezCollections.Pets[pet][6] = 11;
    ezCollections.Pets[pet][7] = "";
end
for _, pet in ipairs({ 10699, 66175, 10708 }) do
    ezCollections.Pets[pet][3] = bit.bor(ezCollections.Pets[pet][3], 0x20);
end
for _, pet in ipairs({ 75936 }) do
    ezCollections.Pets[pet][3] = bit.band(ezCollections.Pets[pet][3], bit.bnot(0x20));
end
