-- By SyneX
local Config = {}
Config.keybindDefaults = {auto = "F8", stop = "Escape", menu = "RightControl"}

local function keybinds(value)
    value = type(value) == "table" and value or {}
    local result, used = {}, {}
    for _, name in ipairs({"auto", "stop", "menu"}) do
        local key = value[name] or Config.keybindDefaults[name]
        local ok, code = pcall(function() return Enum.KeyCode[key] end)
        if type(key) ~= "string" or not ok or not code or key == "Unknown" or used[key] then
            return table.clone(Config.keybindDefaults)
        end
        result[name], used[key] = key, true
    end
    return result
end

function Config.fromSaved(value, canonical, chars)
    value = type(value) == "table" and value or {}
    local wpm = tonumber(value.wpm)
    if not wpm or wpm ~= wpm then wpm = 85 end
    local ok, ending = pcall(canonical, type(value.ending) == "string" and value.ending or "")
    return {
        wpm = math.clamp(wpm, 30, 300),
        natural = value.natural ~= false,
        enter = value.enter ~= false,
        ending = ok and (chars(ending)[1] or "") or "",
        keybinds = keybinds(value.keybinds),
        autoClearHistory = value.autoClearHistory == true,
    }
end

return Config
