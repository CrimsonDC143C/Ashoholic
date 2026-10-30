function ezCollections.PackBook(book)
    local sources = { };
    for _, source in ezCollections:IterateOverTableOrValue(book.sources) do
        if source > 0 then
            table.insert(sources, "I"..source);
        elseif source < 0 then
            table.insert(sources, "O"..-source);
        else
            error("Unhandled unpacked book source: "..source);
        end
    end
    return format("%s,%s,%s,%u,%u,%u,%s,%u,%u",
        ezCollections:Encode(book.name),
        strjoin("", unpack(sources)),
        book.icon or "",
        book.flags,
        book.expansion,
        book.sourceType,
        book.sourceText and ezCollections:Encode(book.sourceText) or "",
        book.language,
        book.material);
end

function ezCollections.UnpackBook(id, data)
    local name, sourceStrings, icon, flags, expansion, sourceType, sourceText, language, material = strsplit(",", data);
    local book =
    {
        name = ezCollections:Decode(name),
        sources = nil,
        icon = icon ~= "" and icon or nil,
        flags = tonumber(flags) or 0,
        expansion = tonumber(expansion) or 0,
        sourceType = tonumber(sourceType) or 0,
        sourceText = sourceText and ezCollections:Decode(sourceText),
        language = tonumber(language) or 0,
        material = tonumber(material) or 0,
    };
    if sourceStrings then
        for sourceType, source in sourceStrings:gmatch("([IO])(%d+)") do
            if sourceType == "I" then
                source = tonumber(source);
            elseif sourceType == "O" then
                source = -tonumber(source);
            else
                error("Unhandled book source type: "..sourceType..source);
            end
            ezCollections:InsertIntoTableOrSetValue(book, "sources", source);
        end
    end

    return book;
end
