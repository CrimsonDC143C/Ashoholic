-- A small data-only format for trusted account snapshots. It never evaluates
-- Lua received from another player or read from an offline file.
local addonName = ...
local addon = _G[addonName]
addon.Sync = addon.Sync or {}
local Codec = {}
addon.Sync.Codec = Codec

local MAX_BYTES = 262144
local MAX_ENTRIES = 50000
local MAX_DEPTH = 16

local function EncodeValue(value, parts, stack, depth, budget)
    if depth > MAX_DEPTH then error("Ashoholic sync data is nested too deeply.") end
    local kind = type(value)
    if kind == "string" then
        parts[#parts + 1] = "S" .. #value .. ":" .. value
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("Ashoholic cannot encode a non-finite number.")
        end
        parts[#parts + 1] = "N" .. string.format("%.17g", value) .. ";"
    elseif kind == "boolean" then
        parts[#parts + 1] = value and "B1" or "B0"
    elseif kind == "table" then
        if stack[value] then error("Ashoholic cannot encode a cyclic table.") end
        stack[value] = true
        local count = 0
        for key in pairs(value) do
            if type(key) ~= "string" and type(key) ~= "number" then
                error("Ashoholic cannot encode this table key.")
            end
            count = count + 1
        end
        budget.count = budget.count + count
        if budget.count > MAX_ENTRIES then error("Ashoholic sync data has too many entries.") end
        parts[#parts + 1] = "T" .. count .. ":"
        for key, child in pairs(value) do
            EncodeValue(key, parts, stack, depth + 1, budget)
            EncodeValue(child, parts, stack, depth + 1, budget)
        end
        stack[value] = nil
    else
        error("Ashoholic cannot encode sync value of type " .. kind .. ".")
    end
end

local function EncodeRaw(packet)
    local parts = { "ASH1" }
    EncodeValue(packet, parts, {}, 0, { count = 0 })
    local raw = table.concat(parts)
    if #raw > MAX_BYTES then error("Ashoholic account snapshot is too large to synchronize.") end
    return raw
end

-- Offline exports are stored as plain hexadecimal text in SavedVariables.
function Codec.Encode(packet)
    return (string.gsub(EncodeRaw(packet), ".", function(character)
        return string.format("%02x", string.byte(character))
    end))
end

-- In-game messages use a compact "wire" text instead of hexadecimal, which
-- doubled every byte and made large accounts slow to send. Ordinary printable
-- characters are sent as-is. "~", "|" (WoW's chat escape character) and any
-- non-printable byte become "~" plus two hexadecimal digits, e.g. "|" -> "~7c".
-- A literal "~" is always escaped, so every "~" on the wire starts an escape.
function Codec.EncodeWire(packet)
    return (string.gsub(EncodeRaw(packet), "[^\32-\123\125]", function(character)
        return string.format("~%02x", string.byte(character))
    end))
end

local function ReadCount(raw, position, terminator)
    local ending = string.find(raw, terminator, position, true)
    if not ending or ending - position > 8 then error("Ashoholic received an invalid sync length.") end
    local text = string.sub(raw, position, ending - 1)
    if not string.match(text, "^%d+$") then error("Ashoholic received an invalid sync length.") end
    return tonumber(text), ending + 1
end

local function DecodeValue(raw, position, depth, budget)
    if depth > MAX_DEPTH or position > #raw then error("Ashoholic received incomplete sync data.") end
    local kind = string.sub(raw, position, position)
    position = position + 1
    if kind == "S" then
        local length
        length, position = ReadCount(raw, position, ":")
        if length > MAX_BYTES or position + length - 1 > #raw then
            error("Ashoholic received an invalid sync string.")
        end
        return string.sub(raw, position, position + length - 1), position + length
    elseif kind == "N" then
        local ending = string.find(raw, ";", position, true)
        if not ending or ending - position > 32 then error("Ashoholic received an invalid sync number.") end
        local value = tonumber(string.sub(raw, position, ending - 1))
        if not value or value ~= value or value == math.huge or value == -math.huge then
            error("Ashoholic received an invalid sync number.")
        end
        return value, ending + 1
    elseif kind == "B" then
        local value = string.sub(raw, position, position)
        if value ~= "0" and value ~= "1" then error("Ashoholic received an invalid sync boolean.") end
        return value == "1", position + 1
    elseif kind == "T" then
        local count
        count, position = ReadCount(raw, position, ":")
        budget.count = budget.count + count
        if budget.count > MAX_ENTRIES then error("Ashoholic received too many sync entries.") end
        local result = {}
        for _ = 1, count do
            local key, value
            key, position = DecodeValue(raw, position, depth + 1, budget)
            if (type(key) ~= "number" and type(key) ~= "string") or result[key] ~= nil then
                error("Ashoholic received an invalid or duplicate sync key.")
            end
            value, position = DecodeValue(raw, position, depth + 1, budget)
            result[key] = value
        end
        return result, position
    end
    error("Ashoholic received an unknown sync value.")
end

local function DecodeRaw(raw)
    if string.sub(raw, 1, 4) ~= "ASH1" then error("Ashoholic received an unsupported sync format.") end
    local value, position = DecodeValue(raw, 5, 0, { count = 0 })
    if position ~= #raw + 1 or type(value) ~= "table" then
        error("Ashoholic received trailing or invalid sync data.")
    end
    return value
end

function Codec.Decode(encoded)
    if type(encoded) ~= "string" or #encoded == 0 or #encoded > MAX_BYTES * 2
        or #encoded % 2 ~= 0 or string.find(encoded, "[^%x]") then
        error("Ashoholic received an invalid encoded snapshot.")
    end
    local raw = string.gsub(encoded, "%x%x", function(pair)
        return string.char(tonumber(pair, 16))
    end)
    return DecodeRaw(raw)
end

-- Reverses Codec.EncodeWire. Unescaped bytes must be printable, and every "~"
-- must be followed by exactly two hexadecimal digits.
function Codec.DecodeWire(wire)
    if type(wire) ~= "string" or #wire == 0 or #wire > MAX_BYTES * 3
        or string.find(wire, "[^\32-\123\125~]") then
        error("Ashoholic received an invalid encoded snapshot.")
    end
    if string.find((string.gsub(wire, "~%x%x", "")), "~", 1, true) then
        error("Ashoholic received a broken escape in a snapshot.")
    end
    local raw = string.gsub(wire, "~(%x%x)", function(pair)
        return string.char(tonumber(pair, 16))
    end)
    if #raw > MAX_BYTES then error("Ashoholic received an account snapshot that is too large.") end
    return DecodeRaw(raw)
end

-- Longest wire text a valid snapshot can produce (every byte escaped).
Codec.MAX_WIRE_BYTES = MAX_BYTES * 3
