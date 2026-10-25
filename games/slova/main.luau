-- By SyneX
local require = ...
local Core = require("core")
local Config = require("config")
local Driver = require("driver")
local Storage = require("storage")
local Interface = require("interface")
local Scope = require("scope")
local App = {version = "1.0.6"}
App.assets = {dictionary = "words.txt"}

function App.start(context)
    local app = {alive = true, dirty = true, scope = Scope.new(), context = context}
    local saveAt, warnedSave
    local storage = Storage.new(game:GetService("HttpService"), context.api)

    function app:identity()
        if type(context.api.setthreadidentity) == "function" then context.api.setthreadidentity(8) end
    end

    function app:scheduleSave(delay)
        saveAt = os.clock() + (delay or 0.6)
    end

    function app:save()
        if not self.bot then return end
        local rejected = {}
        for word in pairs(self.bot.rejected) do table.insert(rejected, word) end
        table.sort(rejected)
        local ok, err = storage:save({version = 1, config = self.config, history = self.bot.history,
            historyMatchId = self.bot.historyMatchId, rejected = rejected})
        if not ok and not warnedSave then
            warnedSave = true
            warn("[SynHub] Настройки не сохранены: " .. tostring(err))
        end
    end

    function app:Destroy()
        if not self.alive then return end
        self.alive = false
        self:identity()
        if self.bot then self.bot:setEnabled(false) end
        self:save()
        self.scope:Destroy()
        if context.onDestroy then context.onDestroy(self) end
    end

    function app.setEnabled(value)
        if not app.alive then return end
        app:identity()
        app.bot:setEnabled(value)
        if app.view then app.view:syncEnabled(value) end
    end

    local ok, err = xpcall(function()
        app:identity()
        local saved = storage:load()
        app.config = Config.fromSaved(saved.config, Core.canonical, Core.chars)
        app.driver = Driver.new(context, Core.canonical)
        local words = {}
        for word in context.assets.dictionary:gmatch("[^\r\n]+") do table.insert(words, word) end
        app.bot = Core.new(words, app.config, app.driver, function(kind)
            app.dirty = true
            if kind ~= "status" and kind ~= "enabled" then app:scheduleSave(0.8) end
        end)
        app.bot.historyMatchId = type(saved.historyMatchId) == "string" and saved.historyMatchId or nil
        local history = type(saved.history) == "table" and saved.history or {}
        for index = #history, 1, -1 do
            if type(history[index]) == "string" then pcall(app.bot.remember, app.bot, history[index]) end
        end
        for _, word in ipairs(type(saved.rejected) == "table" and saved.rejected or {}) do
            if type(word) == "string" then
                local valid, canonical = pcall(Core.canonical, word)
                if valid then app.bot.rejected[canonical] = true end
            end
        end
        app.view = Interface.create(app, context, Core)

        local remote, responseConnection
        local function connectResponse()
            local wordGame = game:GetService("ReplicatedStorage"):FindFirstChild("WordGame")
            local current = wordGame and wordGame:FindFirstChild("State")
            if current == remote then return end
            if responseConnection then responseConnection:Disconnect(); responseConnection = nil end
            remote = current
            if remote then
                responseConnection = remote.OnClientEvent:Connect(function(event)
                    if not app.alive then return end
                    app:identity()
                    app.bot:onResponse(event)
                end)
            end
        end
        app.scope:add(function() if responseConnection then responseConnection:Disconnect() end end)
        connectResponse()
        app.scope:add(game:GetService("UserInputService").InputBegan:Connect(function(input)
            if not app.alive or app.driver.rebinding then return end
            app:identity()
            local focused = game:GetService("UserInputService"):GetFocusedTextBox()
            local snapshot = focused and app.driver.read()
            if focused and (not snapshot or snapshot.blocked) then return end
            local keys = app.config.keybinds
            if input.KeyCode == Enum.KeyCode[keys.auto] then app.setEnabled(not app.bot.enabled)
            elseif input.KeyCode == Enum.KeyCode[keys.stop] then app.setEnabled(false)
            elseif input.KeyCode == Enum.KeyCode[keys.menu] then app.window:Toggle() end
        end))
        local uiElapsed, remoteElapsed, lastKey, choiceAt = 0, 0, nil, 0
        app.scope:add(game:GetService("RunService").Heartbeat:Connect(function(dt)
            if not app.alive then return end
            app:identity()
            local success, failure = xpcall(function()
                remoteElapsed += dt
                if remoteElapsed >= 0.5 then remoteElapsed = 0; connectResponse() end
                app.bot:tick(dt)
                local snapshot = app.bot.snapshot
                if app.bot.enabled and snapshot and snapshot.phase == "choosing"
                    and snapshot.chooser == snapshot.you and os.clock() >= choiceAt then
                    local bestIndex, bestCount = 1, -1
                    for index, letter in ipairs(snapshot.choices or {}) do
                        local _, count = app.bot:candidates(letter, app.config.ending, 0, 0)
                        if count > bestCount then bestIndex, bestCount = index, count end
                    end
                    app.driver.choose(bestIndex)
                    choiceAt = os.clock() + 1
                end
                uiElapsed += dt
                if app.bot.turnKey ~= lastKey then lastKey = app.bot.turnKey; app.dirty = true end
                if uiElapsed >= 0.25 and app.dirty then
                    uiElapsed = 0
                    app.dirty = false
                    app.view:refresh()
                end
                if saveAt and os.clock() >= saveAt then saveAt = nil; app:save() end
            end, debug.traceback)
            if not success then
                app.setEnabled(false)
                app.bot:report("Ошибка: " .. tostring(failure):sub(1, 200))
                warn("[SynHub] " .. tostring(failure))
                if type(context.api.writefile) == "function" then
                    pcall(context.api.writefile, "SynHub/slova/error.log", tostring(failure))
                end
            end
        end))
        app.bot:tick(0)
        app.view:refresh()
        app.window:SelectTab(1)
    end, debug.traceback)
    if not ok then
        -- A failed startup must not replace saved data with a partial session.
        app.alive = false
        app.scope:Destroy()
        error(err, 0)
    end
    return app
end

return App
