-- By SyneX
local Strength = {}

function Strength.profile(rating, budget, presets)
    local low, high
    for _, preset in ipairs(presets or {}) do
        if type(preset.rating) == "number" and type(preset.depth) == "number" and type(preset.time) == "number" then
            if preset.rating <= rating and (not low or preset.rating > low.rating) then low = preset end
            if preset.rating >= rating and (not high or preset.rating < high.rating) then high = preset end
        end
    end
    low, high = low or high, high or low
    if not low or not high then return nil end
    local blend = high.rating == low.rating and 0 or math.clamp((rating - low.rating) / (high.rating - low.rating), 0, 1)
    local function interpolate(field)
        local a, b = low[field] or 0, high[field] or 0
        return a + (b - a) * blend
    end
    return {rating = rating, depth = math.max(1, math.floor(interpolate("depth") + 0.5)),
        time = math.min(math.max(0.01, budget), interpolate("time")),
        noise = interpolate("noise"), blunder = interpolate("blunder")}
end

return Strength
