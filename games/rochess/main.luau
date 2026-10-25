-- By SyneX
local require = ...
local Scope = require("scope")
local Driver = require("driver")
local Engine = require("engine")
local Overlay = require("overlay")
local Interface = require("interface")
local App = {version = "1.0.0"}

function App.start(context)
    local app: any = {alive = true, dirty = true, scope = Scope.new(), context = context, rows = {}, selected = 1,
        status = "Открой партию", cache = {}, cacheOrder = {}, retries = 0}
    local http = game:GetService("HttpService")
    local saveAt, warnedSave
    local path = "SynHub/rochess/state.json"

    function app:identity()
        if type(context.api.setthreadidentity) == "function" then context.api.setthreadidentity(8) end
    end

    function app:scheduleSave() saveAt = os.clock() + 0.6 end

    function app:save()
        if not self.config or type(context.api.writefile) ~= "function" then return end
        local ok = pcall(function()
            if type(context.api.makefolder) == "function" then
                for _, folder in ipairs({"SynHub", "SynHub/rochess"}) do
                    if not context.api.isfolder or not context.api.isfolder(folder) then pcall(context.api.makefolder, folder) end
                end
            end
            context.api.writefile(path, http:JSONEncode(self.config))
        end)
        if not ok and not warnedSave then warnedSave = true; warn("[SynHub] Не удалось сохранить настройки шахмат") end
    end

    function app:invalidate(force)
        if force and self.analysisKey then
            self.cache[self.analysisKey] = nil
            local index = table.find(self.cacheOrder, self.analysisKey)
            if index then table.remove(self.cacheOrder, index) end
        end
        if self.engine then self.engine:cancel() end
        self.analysisKey, self.requested, self.rows = nil, false, {}
        self.due, self.retries, self.dirty = os.clock() + 0.25, 0, true
    end

    function app:Destroy()
        if not self.alive then return end
        self.alive = false
        self:identity()
        self:save()
        self.scope:Destroy()
        if context.onDestroy then context.onDestroy(self) end
    end

    local success, failure = xpcall(function()
        app:identity()
        local saved: {[string]: any} = {}
        if type(context.api.readfile) == "function" then
            local ok, value = pcall(function() return http:JSONDecode(context.api.readfile(path)) end)
            if ok and type(value) == "table" then saved = value end
        end
        local depth = (type(saved.depth) == "number" or type(saved.depth) == "string") and tonumber(saved.depth) or nil
        if not depth or depth ~= depth then depth = 14 end
        local keyOk, keyCode = pcall(function() return Enum.KeyCode[saved.menuKey or "RightControl"] end)
        app.config = {enabled = saved.enabled ~= false, onlyOwn = saved.onlyOwn ~= false,
            arrows = saved.arrows ~= false, allArrows = saved.allArrows ~= false,
            depth = math.clamp(math.floor(depth), 10, 18),
            menuKey = keyOk and keyCode and type(saved.menuKey) == "string" and saved.menuKey ~= "Unknown"
                and saved.menuKey ~= "Escape" and saved.menuKey or "RightControl"}
        app.driver = Driver.new()
        app.engine = Engine.new(context.api, http)
        app.scope:add(function() app.engine:cancel() end)
        app.overlay = Overlay.new(context.api.Drawing)
        app.scope:add(function() app.overlay:Destroy() end)
        app.view = Interface.create(app, context)

        function app:step()
            local snapshot = self.driver.read()
            self.snapshot = snapshot
            local reason = not self.config.enabled and "Подсказки выключены" or snapshot.reason
                or self.config.onlyOwn and not snapshot.own and "Ожидаю твой ход" or nil
            if reason then
                if self.analysisKey then self.engine:cancel(); self.analysisKey = nil end
                if #self.rows > 0 then self.rows = {}; self.dirty = true end
                if self.status ~= reason then self.status = reason; self.dirty = true end
                self.requested = false
                return
            end
            local key = snapshot.fen .. "|" .. self.config.depth .. "|" .. snapshot.color
            if key ~= self.analysisKey or snapshot.session ~= self.lastSession then
                self.engine:cancel()
                self.analysisKey, self.lastSession = key, snapshot.session
                self.rows, self.selected, self.requested, self.retries = {}, 1, false, 0
                self.due = math.max(self.due or 0, os.clock() + 0.12)
                self.status, self.dirty = "Анализирую позицию", true
            end
            if self.requested or os.clock() < (self.due or 0) then return end
            self.requested, self.status, self.dirty = true, "Анализирую позицию", true
            local cached = self.cache[key]
            if cached then self.rows, self.seconds, self.status = cached.rows, cached.seconds, snapshot.own and "Твой ход" or "Ход соперника"; return end
            local legal = self.driver.legal(snapshot.fen)
            self.engine:analyze(snapshot.fen, legal, self.config.depth, function(kind, value, seconds)
                if not self.alive or self.analysisKey ~= key then return end
                local now = self.driver.read()
                if now.session ~= snapshot.session or now.fen ~= snapshot.fen or now.reason
                    or self.config.onlyOwn and not now.own then return end
                self.dirty, self.seconds = true, seconds or self.seconds
                if kind == "rows" or kind == "done" then
                    self.rows = value
                    if not value[self.selected] then self.selected = 1 end
                    self.status = kind == "done" and (now.own and "Твой ход" or "Ход соперника") or "Уточняю варианты"
                    if kind == "done" and #value > 0 then
                        if not self.cache[key] then table.insert(self.cacheOrder, key) end
                        self.cache[key] = {rows = value, seconds = seconds}
                        if #self.cacheOrder > 32 then self.cache[table.remove(self.cacheOrder, 1)] = nil end
                    elseif kind == "done" then
                        self.status = "Нет доступных ходов"
                    end
                elseif kind == "error" then
                    self.retries += 1
                    self.requested, self.due = false, os.clock() + math.min(30, 2 ^ self.retries)
                    self.status = value
                end
            end)
        end

        local poll, paint = 0, 0
        app.scope:add(game:GetService("RunService").Heartbeat:Connect(function(dt)
            if not app.alive then return end
            app:identity()
            local ok, err = xpcall(function()
                app.engine:tick()
                poll += dt; paint += dt
                if poll >= 0.1 then poll = 0; app:step() end
                if paint >= 0.1 and app.dirty then paint = 0; app.dirty = false; app.view.refresh() end
                if saveAt and os.clock() >= saveAt then saveAt = nil; app:save() end
            end, debug.traceback)
            if not ok then
                app.engine:cancel()
                app.rows, app.status, app.dirty = {}, "Не удалось прочитать позицию", true
                warn("[SynHub] " .. tostring(err))
            end
        end))
        app.scope:add(game:GetService("RunService").RenderStepped:Connect(function()
            if app.alive then app.overlay:draw(app.snapshot, app.rows, app.config, app.selected) end
        end))
        app:step()
        app.view.refresh()
        app.window:SelectTab(1)
    end, debug.traceback)
    if not success then app.alive = false; app.scope:Destroy(); error(failure, 0) end
    return app
end

return App
