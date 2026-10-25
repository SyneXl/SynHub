-- By SyneX
local BASE = "https://raw.githubusercontent.com/SyneXl/SynHub/refs/heads/main/"
local env = getgenv()
local hub = env.__SynHub or {}
if hub.loading then warn("[SynHub] Загрузка уже выполняется"); return end
hub.loading = true
env.__SynHub = hub

local ok, result = xpcall(function()
    local function fetch(path)
        assert(type(path) == "string" and path:match("^[%w_/%-%.]+$") and not path:find("..", 1, true),
            "Некорректный путь обновления")
        local lastError
        for attempt = 1, 3 do
            local success, value = pcall(game.HttpGet, game, BASE .. path)
            if success and type(value) == "string" and #value > 0 then return value end
            lastError = value
            if attempt < 3 then task.wait(0.3 * attempt) end
        end
        error("Не удалось загрузить " .. path .. ": " .. tostring(lastError), 0)
    end
    local manifest = game:GetService("HttpService"):JSONDecode(fetch("manifest.json"))
    assert(type(manifest) == "table" and manifest.schema == 1 and type(manifest.games) == "table",
        "Не поддерживается формат обновления SynHub")
    local selected
    for _, entry in ipairs(manifest.games) do
        for _, placeId in ipairs(entry.placeIds or {}) do
            if game.PlaceId == placeId then selected = entry; break end
        end
        if selected then break end
    end
    assert(selected, "SynHub пока не поддерживает эту игру")
    local function artifact(info)
        assert(type(info) == "table" and type(info.bytes) == "number" and info.bytes > 0,
            "Некорректное описание обновления")
        local cached = hub.assets and hub.assets[info.path]
        local value = cached or fetch(info.path)
        assert(#value == info.bytes, "Файл обновления получен не полностью: " .. info.path)
        return value
    end
    local source = artifact(selected.script)
    local chunk, compileError = loadstring(source, "SynHub/" .. selected.id)
    assert(chunk, "Ошибка загрузки игры: " .. tostring(compileError))
    local module = chunk()
    assert(type(module) == "table" and type(module.start) == "function", "Не найден модуль игры")
    local assets, cachedAssets = {}, {}
    for name, info in pairs(selected.assets or {}) do
        assets[name] = artifact(info)
        cachedAssets[info.path] = assets[name]
    end
    local context = {
        env = env, assets = assets, release = selected,
        api = {loadstring = loadstring, debug = debug, getconnections = getconnections,
            setthreadidentity = setthreadidentity, readfile = readfile, writefile = writefile,
            makefolder = makefolder, isfolder = isfolder},
        onDestroy = function(app) if hub.app == app then hub.app = nil end end,
    }
    -- Download and compile the entire release before replacing the running session.
    if hub.app then hub.app:Destroy(); hub.app = nil end
    if env.__Slova then env.__Slova:Destroy(); env.__Slova = nil end
    local app = module.start(context)
    assert(app and app.alive and type(app.Destroy) == "function", "Игра не завершила запуск")
    hub.app, hub.assets, hub.game, hub.version = app, cachedAssets, selected.id, selected.version
    function hub:Destroy()
        if self.app then self.app:Destroy(); self.app = nil end
    end
    return app
end, debug.traceback)

hub.loading = false
if not ok then
    warn("[SynHub] " .. tostring(result))
    error(result, 0)
end
return result
