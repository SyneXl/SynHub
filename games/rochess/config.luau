-- By SyneX
local Config = {}

local function number(value, fallback, low, high)
    if type(value) ~= "number" and type(value) ~= "string" then return fallback end
    local parsed = tonumber(value)
    if not parsed or parsed ~= parsed then return fallback end
    return math.clamp(parsed, low, high)
end

local function key(value, fallback)
    if type(value) ~= "string" or value == "Unknown" or value == "Escape" then return fallback end
    local ok, code = pcall(function() return Enum.KeyCode[value] end)
    return ok and code and value or fallback
end

function Config.fromSaved(saved)
    saved = type(saved) == "table" and saved or {}
    local minimum = number(saved.minDelay, 0.8, 0, 10)
    local maximum = math.max(minimum, number(saved.maxDelay, 1.8, 0, 10))
    local menuKey = key(saved.menuKey, "RightControl")
    local autoKey = key(saved.autoKey, "F8")
    if autoKey == menuKey then menuKey, autoKey = "RightControl", "F8" end
    local modes, seen = {}, {}
    if type(saved.queueModes) == "table" then
        for _, mode in ipairs(saved.queueModes) do
            if type(mode) == "string" and #mode <= 12 and mode:match("^%d+%+%d+$") and not seen[mode] then
                seen[mode] = true; table.insert(modes, mode)
                if #modes >= 32 then break end
            end
        end
    else
        modes = {"3+2"}
    end
    return {language = saved.language == "ru" and "ru" or "en",
        enabled = saved.enabled ~= false, onlyOwn = saved.onlyOwn ~= false,
        arrows = saved.arrows ~= false, allArrows = saved.allArrows ~= false,
        depth = math.floor(number(saved.depth, 14, 10, 18)), menuKey = menuKey, autoKey = autoKey,
        minDelay = minimum, maxDelay = maximum,
        autoPlay = saved.autoPlay == true, autoQueue = saved.autoQueue == true,
        queueModes = modes, queueDelay = number(saved.queueDelay, 3, 1, 20),
        strength = saved.strength == "elo" and "elo" or "max",
        elo = math.floor(number(saved.elo, 1600, 800, 2800) / 100) * 100,
        uiScale = number(saved.uiScale, 1, 0.8, 1.2)}
end

return Config
