-- By SyneX
local Config = {}

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
    }
end

return Config
