ProjectEbonhold = ProjectEbonhold or {}

-- Translation layer. Write every player-facing text in English, wrapped:
--   ProjectEbonhold.L["You are dead"]                                 plain text
--   ProjectEbonhold.T("No {category} contracts ...", { category = x }) text with named {fields}
-- The English IS the key: with no translation for the player's language the English shows, never a blank.
-- Translations live in locales/<locale>.lua, GENERATED from the translation store
-- (server repo: python3 -I tools/translation/m6_emit.py addon --addon-repo <this checkout>): never edit them by hand.

local strings = {}

ProjectEbonhold.L = setmetatable({}, {
    __index = function(_, english)
        return strings[english] or english
    end
})

-- A translation may choose a word by number where English only appends a suffix: {name|one|other} gives `one` when the
-- field holds the English singular value ("" for the {s} / {es} suffixes, "it" for {them}) and `other` otherwise.
-- German "Kugel{s||n}" -> "Kugel" / "Kugeln" for the English "Orb{s}" (2026-11-11). English and French never use it.
local function choose(fields, name, one, other)
    local value = fields and fields[name]
    if value == nil then return "{" .. name .. "|" .. one .. "|" .. other .. "}" end
    return (value == "" or value == "it") and one or other
end

function ProjectEbonhold.T(english, fields)
    local text = ProjectEbonhold.L[english]:gsub("{(%w+)|([^|{}]*)|([^|{}]*)}", function(name, one, other)
        return choose(fields, name, one, other)
    end)
    return (text:gsub("{(%w+)}", function(name)
        local value = fields and fields[name]
        if value == nil then return "{" .. name .. "}" end
        return tostring(value)
    end))
end

-- Called once per locale file; only the player's own language is kept.
function ProjectEbonhold.RegisterLocale(locale, translations)
    if GetLocale() ~= locale then return end
    for english, text in pairs(translations) do
        strings[english] = text
    end
end

-- string.upper only knows ASCII: "Métiers" would come out "MéTIERS". Also upper-cases the Latin-1 letters of UTF-8
-- (é -> É, à -> À, ç -> Ç ...) and œ, so an all-caps header stays all caps in French.
function ProjectEbonhold.Upper(text)
    text = string.upper(text)
    text = text:gsub("\195([\160-\190])", function(c)
        if c == "\183" then return nil end
        return "\195" .. string.char(c:byte() - 32)
    end)
    return (text:gsub("\197\147", "\197\146"))
end
