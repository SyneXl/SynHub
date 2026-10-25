-- By SyneX
local ROOT = "https://raw.githubusercontent.com/SyneXl/SynHub/"
local function download(url, label)
    local lastError
    for attempt = 1, 3 do
        local success, value = pcall(game.HttpGet, game, url, false)
        if success and type(value) == "string" and #value > 0 then return value end
        lastError = value
        if attempt < 3 then task.wait(0.3 * attempt) end
    end
    error("Не удалось загрузить " .. label .. ": " .. tostring(lastError), 0)
end

local revision = ...
if type(revision) ~= "string" or #revision ~= 40 or not revision:match("^%x+$") then
    local httpService = game:GetService("HttpService")
    local send = request or http_request or (http and http.request)
    local function parse(body)
        if type(body) ~= "string" then return nil end
        local ok, ref = pcall(httpService.JSONDecode, httpService, body)
        local sha = ok and type(ref) == "table" and type(ref.object) == "table" and ref.object.sha
            or body:match("<id>tag:github.com,2008:Grit::Commit/(%x+)</id>")
        return type(sha) == "string" and #sha == 40 and sha:match("^%x+$") and sha or nil
    end
    local commit
    for _, endpoint in ipairs({"https://api.github.com/repos/SyneXl/SynHub/git/ref/heads/main",
        "https://github.com/SyneXl/SynHub/commits/main.atom"}) do
        local url = endpoint .. "?synhub=" .. os.time()
        if type(send) == "function" then
            local ok, response = pcall(send, {Url = url, Method = "GET",
                Headers = {["User-Agent"] = "SynHub", ["Cache-Control"] = "no-cache"}})
            if ok and type(response) == "table" then commit = parse(response.Body) end
        end
        if not commit then
            local ok, response = pcall(game.HttpGet, game, url, false)
            if ok then commit = parse(response) end
        end
        if commit then break end
    end
    assert(commit, "Could not resolve the latest version. Please try again.")
    local chunk, err = loadstring(download(ROOT .. commit .. "/loader.luau", "загрузчик SynHub"), "SynHubLoader")
    assert(chunk, "Не удалось прочитать загрузчик: " .. tostring(err))
    return chunk(commit)
end

local BASE = ROOT .. revision .. "/"
local games = {[71106427459865] = "slova", [139717576471404] = "rochess"}
local env = getgenv()
local hub = env.__SynHub or {}
if hub.loading then warn("[SynHub] Загрузка уже выполняется"); return end
hub.loading = true
env.__SynHub = hub

local ok, result = xpcall(function()
    local name = assert(games[game.PlaceId], "SynHub пока не поддерживает эту игру")
    local folder = "games/" .. name .. "/"
    local function fetch(path)
        return download(BASE .. path, path)
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
    local assets = {interface = fetch("vendor/WindUI.luau")}
    for key, path in pairs(module.assets or {}) do assets[key] = fetch(folder .. path) end
    local context = {
        env = env, assets = assets,
        release = {id = name, version = module.version},
        api = {loadstring = loadstring, debug = debug, getconnections = getconnections,
            setthreadidentity = setthreadidentity, readfile = readfile, writefile = writefile,
            makefolder = makefolder, isfolder = isfolder,
            request = request or http_request or (http and http.request),
            WebSocket = WebSocket or websocket, Drawing = Drawing},
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
