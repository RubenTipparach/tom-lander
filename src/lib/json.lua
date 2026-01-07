-- Minimal JSON encoder/decoder for Lua
-- Handles basic types: tables, strings, numbers, booleans, nil

local json = {}

-- Encode a Lua value to JSON string
function json.encode(value)
    local t = type(value)

    if value == nil then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        return tostring(value)
    elseif t == "string" then
        -- Escape special characters
        local escaped = value:gsub('\\', '\\\\')
                             :gsub('"', '\\"')
                             :gsub('\n', '\\n')
                             :gsub('\r', '\\r')
                             :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    elseif t == "table" then
        -- Check if it's an array (sequential integer keys starting from 1)
        local is_array = true
        local max_index = 0
        for k, v in pairs(value) do
            if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
                is_array = false
                break
            end
            if k > max_index then
                max_index = k
            end
        end
        -- Also check for holes in the array
        if is_array then
            for i = 1, max_index do
                if value[i] == nil then
                    is_array = false
                    break
                end
            end
        end

        if is_array and max_index > 0 then
            -- Encode as array
            local parts = {}
            for i = 1, max_index do
                table.insert(parts, json.encode(value[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            -- Encode as object
            local parts = {}
            for k, v in pairs(value) do
                if type(k) == "string" then
                    table.insert(parts, json.encode(k) .. ":" .. json.encode(v))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        error("Cannot encode type: " .. t)
    end
end

-- Decode a JSON string to Lua value
function json.decode(str)
    local pos = 1

    local function skip_whitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parse_value()
        skip_whitespace()

        if pos > #str then
            error("Unexpected end of JSON")
        end

        local char = str:sub(pos, pos)

        if char == '"' then
            -- String
            pos = pos + 1
            local start = pos
            local result = ""
            while pos <= #str do
                local c = str:sub(pos, pos)
                if c == '"' then
                    pos = pos + 1
                    return result
                elseif c == '\\' then
                    pos = pos + 1
                    local escape = str:sub(pos, pos)
                    if escape == 'n' then result = result .. '\n'
                    elseif escape == 'r' then result = result .. '\r'
                    elseif escape == 't' then result = result .. '\t'
                    elseif escape == '"' then result = result .. '"'
                    elseif escape == '\\' then result = result .. '\\'
                    else result = result .. escape
                    end
                    pos = pos + 1
                else
                    result = result .. c
                    pos = pos + 1
                end
            end
            error("Unterminated string")

        elseif char == '{' then
            -- Object
            pos = pos + 1
            local obj = {}
            skip_whitespace()
            if str:sub(pos, pos) == '}' then
                pos = pos + 1
                return obj
            end
            while true do
                skip_whitespace()
                local key = parse_value()
                if type(key) ~= "string" then
                    error("Object key must be string")
                end
                skip_whitespace()
                if str:sub(pos, pos) ~= ':' then
                    error("Expected ':' after object key")
                end
                pos = pos + 1
                obj[key] = parse_value()
                skip_whitespace()
                local sep = str:sub(pos, pos)
                if sep == '}' then
                    pos = pos + 1
                    return obj
                elseif sep == ',' then
                    pos = pos + 1
                else
                    error("Expected ',' or '}' in object")
                end
            end

        elseif char == '[' then
            -- Array
            pos = pos + 1
            local arr = {}
            skip_whitespace()
            if str:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            end
            while true do
                table.insert(arr, parse_value())
                skip_whitespace()
                local sep = str:sub(pos, pos)
                if sep == ']' then
                    pos = pos + 1
                    return arr
                elseif sep == ',' then
                    pos = pos + 1
                else
                    error("Expected ',' or ']' in array")
                end
            end

        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true

        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false

        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil

        elseif char:match("[%d%-]") then
            -- Number
            local start = pos
            if str:sub(pos, pos) == '-' then
                pos = pos + 1
            end
            while pos <= #str and str:sub(pos, pos):match("%d") do
                pos = pos + 1
            end
            if pos <= #str and str:sub(pos, pos) == '.' then
                pos = pos + 1
                while pos <= #str and str:sub(pos, pos):match("%d") do
                    pos = pos + 1
                end
            end
            if pos <= #str and str:sub(pos, pos):lower() == 'e' then
                pos = pos + 1
                if str:sub(pos, pos):match("[%+%-]") then
                    pos = pos + 1
                end
                while pos <= #str and str:sub(pos, pos):match("%d") do
                    pos = pos + 1
                end
            end
            return tonumber(str:sub(start, pos - 1))

        else
            error("Unexpected character: " .. char)
        end
    end

    local result = parse_value()
    skip_whitespace()
    if pos <= #str then
        error("Trailing characters after JSON")
    end
    return result
end

return json
