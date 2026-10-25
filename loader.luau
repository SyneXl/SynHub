-- By SyneX
local BASE = "https://raw.githubusercontent.com/SyneXl/SynHub/refs/heads/main/"
local games = {[71106427459865] = "slova"}
local env = getgenv()
local hub = env.__SynHub or {}
if hub.loading then warn("[SynHub] Загрузка уже выполняется"); return end
hub.loading = true
env.__SynHub = hub

local ok, result = xpcall(function()
    local name = assert(games[game.PlaceId], "SynHub пока не поддерживает эту игру")
    local folder = "games/" .. name .. "/"
    local requestId = tostring(os.time()) .. "-" .. tostring(math.floor(os.clock() * 1000))
    local function fetch(path)
        local lastError
        for attempt = 1, 3 do
            local success, value = pcall(game.HttpGet, game, BASE .. path .. "?synhub=" .. requestId, false)
            if success and type(value) == "string" and #value > 0 then return value end
            lastError = value
            if attempt < 3 then task.wait(0.3 * attempt) end
        end
        error("Не удалось загрузить " .. path .. ": " .. tostring(lastError), 0)
    end
    local modules, loading = {}, {}
    local function import(moduleName)
        assert(type(moduleName) == "string" and moduleName:match("^[%w_-]+$"), "Некорректное имя модуля")
        if modules[moduleName] ~= nil then return modules[moduleName] end
        assert(not loading[moduleName], "Циклическая зависимость: " .. moduleName)
        loading[moduleName] = true
        local chunk, err = loadstring(fetch(folder .. moduleName .. ".luau"), "SynHub/" .. name .. "/" .. moduleName)
        assert(chunk, "Не удалось прочитать модуль " .. moduleName .. ": " .. tostring(err))
        local value = chunk(import)
        assert(value ~= nil, "Пустой модуль: " .. moduleName)
        modules[moduleName], loading[moduleName] = value, nil
        return value
    end
    local module = import("main")
    assert(type(module) == "table" and type(module.start) == "function", "Не найден модуль игры")
    local context = {
        env = env, assets = {dictionary = fetch(folder .. "words.txt"), interface = fetch("vendor/WindUI.luau")},
        release = {id = name, version = module.version},
        api = {loadstring = loadstring, debug = debug, getconnections = getconnections,
            setthreadidentity = setthreadidentity, readfile = readfile, writefile = writefile,
            makefolder = makefolder, isfolder = isfolder},
        onDestroy = function(app) if hub.app == app then hub.app = nil end end,
    }
    if hub.app then hub.app:Destroy(); hub.app = nil end
    if env.__Slova then env.__Slova:Destroy(); env.__Slova = nil end
    local app = module.start(context)
    assert(app and app.alive and type(app.Destroy) == "function", "Игра не завершила запуск")
    hub.app, hub.game, hub.version, hub.assets = app, name, module.version, nil
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
