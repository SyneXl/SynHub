-- By SyneX
local modules, cache, loading = {}, {}, {}
modules["games/slova/core"] = function(require)
-- By SyneX
local Core = {}
Core.__index = Core

function Core.canonical(text)
    local chars = {}
    for _, cp in utf8.codes(text or "") do
        if cp >= 1040 and cp <= 1071 then cp += 32 end
        if cp == 1025 or cp == 1105 then cp = 1077 end
        table.insert(chars, utf8.char(cp))
    end
    return (table.concat(chars):lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

function Core.chars(text)
    local result = {}
    for _, cp in utf8.codes(text) do table.insert(result, utf8.char(cp)) end
    return result
end

function Core.new(words, config, driver, emit, random)
    local self = setmetatable({}, Core)
    self.config, self.driver = config, driver
    self.emit, self.random = emit or function() end, random or math.random
    self.index, self.used, self.rejected, self.attempted = {}, {}, {}, {}
    self.history, self.log, self.metrics = {}, {}, {accepted=0, rejected=0, typed=0}
    self.enabled, self.phase, self.status = false, "watch", "Готов"
    self.elapsed, self.budget, self.page = 0, 0, 0
    for i, word in ipairs(words) do
        local key = Core.canonical(word)
        local chars = Core.chars(key)
        if #chars >= 2 and #chars <= 30 then
            local entry = {word=word, key=key, chars=chars, first=chars[1], last=chars[#chars], rank=i}
            self.index[entry.first] = self.index[entry.first] or {}
            table.insert(self.index[entry.first], entry)
        end
    end
    return self
end

function Core:report(text)
    if self.status ~= text then self.status=text; self.emit("status", text) end
end

function Core:record(kind, word)
    table.insert(self.log, 1, kind .. ": " .. word)
    if #self.log > 80 then table.remove(self.log) end
    self.emit(kind, word)
end

function Core:remember(word)
    local key = Core.canonical(word)
    if utf8.len(key) < 2 or self.used[key] then return end
    for _,cp in utf8.codes(key) do if cp<1072 or cp>1103 then return end end
    self.used[key] = true
    table.insert(self.history, 1, word)
    self.emit("history", word)
end

function Core:candidates(first, ending, offset, count)
    first, ending = Core.canonical(first), Core.canonical(ending)
    local result, found = {}, 0
    for _, entry in ipairs(self.index[first] or {}) do
        if (ending == "" or entry.last == ending) and not self.used[entry.key]
            and not self.rejected[entry.key] and not self.attempted[entry.key] then
            found += 1
            if found > (offset or 0) and #result < (count or 10) then table.insert(result, entry) end
        end
    end
    return result, found
end

function Core:setEnabled(value)
    self.enabled = value == true
    if not value then
        self.phase, self.pending, self.manual, self.manualRun = "watch", nil, nil, false
        self:report("Автобой выключен")
    else
        if not self.pending then self.phase="watch" end
        self:report("Автобой: ожидаю свой ход")
    end
    self.emit("enabled", self.enabled)
end

function Core:request(word)
    if self.phase ~= "watch" and self.phase ~= "done" then return false end
    self.manual = Core.canonical(word)
    self.manualRun = true
    self.phase = "watch"
    return true
end

function Core:pick(snapshot)
    if self.manual then
        local requested = self.manual
        self.manual = nil
        for _, entry in ipairs(self.index[snapshot.letter] or {}) do
            if entry.key == requested then return entry, true end
        end
        self:report("Выбранное слово не подходит к текущей букве")
        return nil, true
    end
    local candidates = self:candidates(snapshot.letter, self.config.ending, 0, 2500)
    local fallback
    for _, entry in ipairs(candidates) do
        local seconds = (#entry.chars-1) * 12 / self.config.wpm * 1.15 + 0.65
        if #entry.chars <= 15 and (not snapshot.left or seconds < snapshot.left) then
            fallback = fallback or entry
            if #entry.chars >= 3 and #entry.chars <= 7 then return entry, false end
        end
    end
    return fallback, false
end

function Core:matches(event, pending)
    return pending and (event.tableId == nil or event.tableId == pending.tableId)
        and (event.round == nil or event.round == pending.round)
        and (event.generation == nil or event.generation == pending.generation)
end

function Core:onResponse(event)
    if type(event) ~= "table" then return end
    local p = self.pending
    if event.kind == "accepted" then
        if not self:matches(event, self.snapshot) then return end
        self:remember(event.word or "")
        if self:matches(event, p) and Core.canonical(event.word) == p.entry.key then
            self.metrics.accepted += 1
            self:record("Принято", p.entry.word)
            self.pending, self.phase, self.manualRun = nil, "done", false
            self:report("Принято: " .. p.entry.word)
        end
        return
    end
    if self.phase ~= "result" or not self:matches(event, p) then return end
    if event.kind == "wordRejected" and event.requestId ~= p.requestId then return end
    if event.kind == "invalid" and event.actor ~= nil and event.actor ~= p.you then return end
    if event.kind == "wordRejected" or event.kind == "invalid" then
        self.attempted[p.entry.key] = true
        if event.reason == "used" then self:remember(p.entry.word)
        else self.rejected[p.entry.key] = true end
        self.metrics.rejected += 1
        self:record("Отклонено", p.entry.word .. ": " .. tostring(event.text or event.reason or ""))
        self.pending, self.phase, self.elapsed = nil, "retry", 0
        self:report("Слово отклонено: очищаю и подбираю замену")
    end
end

function Core:tick(dt)
    dt = math.min(dt, 0.1)
    local s = self.driver.read()
    self.snapshot = s
    if not s then self:report("Ожидаю интерфейс игры"); return end
    if s.matchId ~= self.matchId then
        self.matchId = s.matchId
        self.matchUsed, self.attempted = {}, {}
    end
    if s.history ~= self.historyRef or #(s.history or {}) ~= self.historySize then
        self.historyRef,self.historySize=s.history,#(s.history or {})
        for _, word in ipairs(s.history or {}) do self:remember(word) end
    end
    if s.lastWord and s.lastWord ~= "" then self:remember(s.lastWord) end
    if s.key ~= self.turnKey then
        self.turnKey, self.phase, self.pending = s.key, "watch", nil
        self.attempted, self.budget, self.manual, self.manualRun = {}, 0, nil, false
    end
    if not self.enabled and not self.manualRun then return end
    if not s.own then self:report("Ожидаю свой ход"); return end
    if self.phase == "result" then
        self.elapsed += dt
        if self.elapsed > 4.6 and not s.busy and self.pending.resends < 1 and s.ready then
            self.pending.resends += 1
            self.pending.requestId = self.driver.submit()
            self.elapsed = 0
            self:report("Ответ задержался: повторяю отправку один раз")
        elseif self.elapsed > 9 then
            self.phase, self.pending = "done", nil
            self:report("Нет ответа сервера. Ожидаю следующий ход")
        end
        return
    end
    if self.phase == "done" then return end
    if not s.ready then
        self:report(s.blocked and "Пауза: открыт ввод в меню или чате" or "Ожидаю окончание анимации")
        return
    end
    if self.phase == "retry" then
        self.elapsed += dt
        if self.elapsed < 0.15 then return end
        self.driver.write("")
        self.phase = "watch"
        return
    end
    if self.phase == "watch" then
        if self.budget >= 5 then self.phase="done"; self:report("Пять попыток: ожидаю следующий ход"); return end
        local entry, manual = self:pick(s)
        if not entry then self:report("Нет подходящего слова на «" .. s.letter .. "»"); return end
        self.pending = {entry=entry, manual=manual, tableId=s.tableId, generation=s.generation,
            round=s.round, you=s.you, resends=0}
        self.phase, self.elapsed, self.position, self.progress = "reaction", 0, 2, 0
        self.reaction = self.config.natural and (0.12 + self.random()*0.2) or 0.04
        return
    end
    if self.phase == "reaction" then
        self.elapsed += dt
        if self.elapsed < self.reaction then return end
        self.driver.write("")
        self.phase, self.progress = "typing", 0
        self.factor = self.config.natural and (0.65 + self.random()*0.7) or 1
        self:report("Печатаю: " .. self.pending.entry.word)
        return
    end
    if self.phase == "typing" then
        self.progress += dt * self.config.wpm / 12
        if self.progress < self.factor then return end
        self.progress -= self.factor
        local p = self.pending
        local suffix = table.concat(p.entry.chars, "", 2, self.position)
        self.driver.write(suffix)
        self.position += 1
        if self.position > #p.entry.chars then
            self.metrics.typed += 1
            self.attempted[p.entry.key] = true
            self.budget += 1
            self.phase, self.elapsed = "settle", 0
        else
            self.factor = self.config.natural and (0.65 + self.random()*0.7) or 1
            if self.config.natural and self.random() < 0.12 then self.factor += 0.65 end
        end
        return
    end
    if self.phase == "settle" then
        self.elapsed += dt
        if self.elapsed < 0.12 then return end
        local p = self.pending
        local expected = table.concat(p.entry.chars, "", 2)
        if Core.canonical(s.text) ~= expected then
            self.pending, self.phase = nil, "retry"
            self.elapsed = 0
            self:report("Ввод изменился: повторяю с другим словом")
            return
        end
        if p.manual and not self.config.enter then
            self:remember(p.entry.word)
            self:record("Введено", p.entry.word)
            self.pending, self.phase, self.manualRun = nil, "done", false
            self:report("Введено: " .. p.entry.word)
            return
        end
        self.phase, self.elapsed = "result", 0
        p.requestId = self.driver.submit()
        if not p.requestId then
            self.pending, self.phase = nil, "retry"
            self:report("Отправка пока недоступна: повторю попытку")
        else self:report("Проверяется: " .. p.entry.word) end
    end
end

return Core

end
modules["games/slova/config"] = function(require)
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

end
modules["games/slova/driver"] = function(require)
-- By SyneX
local Driver = {}

function Driver.new(context, canonical)
    local players = game:GetService("Players")
    local input = game:GetService("UserInputService")
    local api = context.api
    local inspect = api.debug
    assert(type(api.getconnections) == "function" and type(inspect) == "table"
        and type(inspect.getupvalue) == "function" and type(inspect.getupvalues) == "function",
        "Среда запуска не поддерживает подключение к вводу игры")
    local binding, nextBind = nil, 0

    local function findBinding()
        local player = players.LocalPlayer
        local gui = player and player:FindFirstChild("PlayerGui")
        gui = gui and gui:FindFirstChild("WordGameUI")
        local canvas = gui and gui:FindFirstChild("Canvas")
        local match = canvas and canvas:FindFirstChild("Match")
        local box = match and match:FindFirstChild("TypingCapture")
        if not box or not box:IsA("TextBox") then return nil end
        for _, connection in ipairs(api.getconnections(box.FocusLost)) do
            local callback = connection.Function
            if type(callback) == "function" then
                local ok, values = pcall(inspect.getupvalues, callback)
                if ok and type(values) == "table" then
                    for _, value in pairs(values) do
                        if type(value) == "function" and inspect.info(value, "n") == "submitWord" then
                            if inspect.getupvalue(value, 1) == box
                                and type(inspect.getupvalue(value, 3)) == "number"
                                and type(inspect.getupvalue(value, 4)) == "boolean" then
                                return {box = box, submit = value}
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    local driver = {}
    function driver.read()
        if not binding or not binding.box.Parent then
            if os.clock() < nextBind then return nil end
            nextBind = os.clock() + 0.5
            binding = findBinding()
        end
        if not binding then return nil end
        local state = inspect.getupvalue(binding.submit, 2)
        if type(state) ~= "table" or state.tableId == nil then return nil end
        local focused = input:GetFocusedTextBox()
        local blocked = binding.box:GetAttribute("ChatInputBlocked") == true
            or focused ~= nil and focused ~= binding.box
        local own = state.phase == "playing" and state.turn == state.you
        local busy = inspect.getupvalue(binding.submit, 4) == true
        local locked = os.clock() < (inspect.getupvalue(binding.submit, 3) or 0)
        local matchId = tostring(state.tableId) .. ":" .. tostring(state.generation or 0)
        local key = matchId .. ":" .. tostring(state.round) .. ":" .. tostring(state.turn) .. ":" .. tostring(state.phase)
        return {key = key, matchId = matchId, phase = state.phase, own = own,
            ready = own and not busy and not locked and not blocked and not state.acceptedWord,
            blocked = blocked, busy = busy, tableId = state.tableId, generation = state.generation or 0,
            round = state.round, you = state.you, letter = canonical(state.letter), text = binding.box.Text,
            left = state.deadline and math.max(0, state.deadline - workspace:GetServerTimeNow()) or nil,
            history = state.history, lastWord = state.lastWord, choices = state.choices, chooser = state.chooser}
    end

    function driver.write(text)
        if not binding or not binding.box.Parent then return end
        binding.box.Text = text
        binding.box.CursorPosition = #text + 1
    end

    function driver.submit()
        if not binding or not binding.box.Parent then return nil end
        local before = binding.box:GetAttribute("AnalyticsSubmit")
        binding.submit("textbox_enter")
        local after = binding.box:GetAttribute("AnalyticsSubmit")
        return after ~= before and after or nil
    end

    function driver.choose(index)
        if not binding or not binding.box.Parent then return false end
        local choices = binding.box.Parent:FindFirstChild("Choices")
        local button = choices and choices:FindFirstChild("Choice" .. index)
        if not button then return false end
        for _, connection in ipairs(api.getconnections(button.Activated)) do
            local callback = connection.Function
            if type(callback) == "function" and (inspect.info(callback, "s") or ""):find("WordGameClient", 1, true) then
                callback()
                return true
            end
        end
        return false
    end

    return driver
end

return Driver

end
modules["games/slova/storage"] = function(require)
-- By SyneX
local Storage = {}
Storage.__index = Storage

function Storage.new(http, files)
    return setmetatable({http = http, files = files, path = "SynHub/slova/state.json"}, Storage)
end

function Storage:load()
    if type(self.files.readfile) ~= "function" then return {} end
    for _, path in ipairs({self.path, "Slova/state.json"}) do
        local ok, value = pcall(function()
            return self.http:JSONDecode(self.files.readfile(path))
        end)
        if ok and type(value) == "table" then return value end
    end
    return {}
end

function Storage:save(state)
    if type(self.files.writefile) ~= "function" then return false, "Сохранение недоступно" end
    return pcall(function()
        if type(self.files.makefolder) == "function" then
            for _, path in ipairs({"SynHub", "SynHub/slova"}) do
                if type(self.files.isfolder) ~= "function" or not self.files.isfolder(path) then
                    pcall(self.files.makefolder, path)
                end
            end
        end
        self.files.writefile(self.path, self.http:JSONEncode(state))
    end)
end

return Storage

end
modules["games/slova/interface"] = function(require)
-- By SyneX
local Interface = {}

function Interface.create(app, context, Core)
    local bot, driver = app.bot, app.driver
    local player = game:GetService("Players").LocalPlayer
    local Library = assert(context.api.loadstring(context.assets.interface, "Interface"))()
    app.scope:add(function()
        for _, gui in ipairs({Library.ScreenGui,Library.DropdownGui,Library.TooltipGui,Library.NotificationGui}) do
            if gui.Destroy then pcall(gui.Destroy,gui) end
        end
    end)
    Library:SetParent(player.PlayerGui)
    for i,gui in ipairs({Library.ScreenGui,Library.DropdownGui,Library.TooltipGui,Library.NotificationGui}) do
        gui.DisplayOrder=1000+i
    end
    local window = Library:CreateWindow({Title="SynHub — Слова", Author="By SyneX", Folder="SynHub/slova/UI",
        Size=UDim2.fromOffset(650,650), MinSize=Vector2.new(580,490), SideBarWidth=130,
        Theme="Dark", Transparent=false, Resizable=true, User={Enabled=false}})
    app.window = window
    app.scope:add(function() window:Destroy() end)
    window:SetToggleKey(Enum.KeyCode.RightControl)
    window:OnDestroy(function() if app.alive then app:Destroy() end end)

    local play = window:Tab({Title="Игра",Icon="play"})
    local historyTab = window:Tab({Title="История",Icon="history"})
    local settings = window:Tab({Title="Настройки",Icon="settings"})
    local function textBlock(tab, title, description)
        return tab:Paragraph({Title=title,Desc=description}).ParagraphFrame
    end
    local syncingToggle = false
    local toggle
    local setEnabled = app.setEnabled
    toggle = play:Toggle({Title="Автобой",Value=false,
        Callback=function(value) if not syncingToggle then setEnabled(value) end end})
    app.setEnabled=setEnabled
    local status = textBlock(play,"Готов",nil)

    local page, displayed, buttons, wordRows = 0, {}, {}, {}
    app.endingInput=play:Input({Title="Последняя буква",Placeholder="Любая",Value=app.config.ending,
        Callback=function(value) app.config.ending=Core.chars(Core.canonical(value))[1] or "";page=0;app.dirty=true;app:scheduleSave(0.6) end})
    local listInfo = textBlock(play,"Подходящие слова",nil)
    local wordRow
    for i=1,10 do
        if i%2==1 then wordRow=play:Group({});table.insert(wordRows,wordRow) end
        buttons[i]=wordRow:Button({Title="—",Icon="arrow-up-right",Size=UDim2.new(1,0,0,38),Callback=function()
            local entry=displayed[i]
            local snapshot=driver.read()
            if not entry then return end
            if not snapshot or not snapshot.own then bot:report("Дождись своего хода");return end
            if snapshot.letter ~= entry.first then bot:report("Сейчас в игре другая начальная буква");return end
            if not bot:request(entry.word) then bot:report("Дождись завершения текущей попытки") end
        end})
    end
    local pagination=play:Group({})
    pagination:Button({Title="В начало",Icon="arrow-left",Callback=function() page=0;app.dirty=true end})
    pagination:Button({Title="Ещё слова",Icon="arrow-right",Callback=function() page+=10;app.dirty=true end})
    local stats = textBlock(historyTab,"За эту сессию",nil)
    local historyView = textBlock(historyTab,"Использованные слова","Пока пусто")
    local attemptsView = textBlock(historyTab,"Последние попытки","Пока пусто")
    historyTab:Button({Title="Очистить историю",Callback=function()
        bot.used,bot.history={},{};bot.historyRef=nil;app.dirty=true;app:scheduleSave(0.2)
    end})
    settings:Section({Title="Печать"})
    app.speed=settings:Slider({Title="Скорость печати",Desc="Слов в минуту",
        Value={Min=30,Max=300,Default=app.config.wpm},Step=1,Callback=function(value)
            app.config.wpm=math.clamp(tonumber(value) or 85,30,300);app:scheduleSave(0.6)
        end})
    settings:Toggle({Title="Естественный ритм",Value=app.config.natural,
        Callback=function(value) app.config.natural=value;app:scheduleSave(0.6) end})
    settings:Toggle({Title="Отправлять после ручного выбора",Desc="Автобой отправляет слова всегда",Value=app.config.enter,
        Callback=function(value) app.config.enter=value;app:scheduleSave(0.6) end})
    textBlock(settings,"Клавиши","F8 — включить или выключить автобой\nEsc — остановить\nRight Ctrl — показать или скрыть меню")
    settings:Section({Title="Обслуживание"})
    settings:Button({Title="Очистить ввод в игре",Callback=function()
        setEnabled(false)
        local snapshot=driver.read()
        if snapshot and snapshot.ready then driver.write("") end
    end})
    settings:Button({Title="Сбросить отклонённые слова",Callback=function() bot.rejected={};app.dirty=true;app:scheduleSave(0.2) end})
    settings:Button({Title="Выгрузить скрипт",Callback=function() app:Destroy() end})

    local function refresh()
        app:identity()
        status:SetTitle(bot.status)
        stats:SetDesc("Принято: "..bot.metrics.accepted.."\nЗаменено: "..bot.metrics.rejected)
        local snapshot=bot.snapshot
        local start=snapshot and snapshot.letter or ""
        local total
        displayed,total=bot:candidates(start,app.config.ending,page,10)
        if page>=total and page>0 then page=0;displayed,total=bot:candidates(start,app.config.ending,0,10) end
        listInfo:SetTitle(start~="" and "Слова на «"..start.."»" or "Ожидаю начало игры")
        listInfo:SetDesc(total>0 and tostring(math.min(page+1,total)).."–"..math.min(page+10,total).." из "..total
            or start~="" and "Подходящих слов больше нет" or nil)
        for i,button in ipairs(buttons) do
            local entry=displayed[i]
            button:SetTitle(entry and entry.word or "—")
            button.ButtonFrame.UIElements.Main.Visible=entry~=nil
        end
        for i,row in ipairs(wordRows) do row.ElementFrame.Visible=displayed[i*2-1]~=nil end
        pagination.ElementFrame.Visible=total>10
        historyView:SetTitle("Использовано: "..#bot.history)
        historyView:SetDesc(#bot.history>0 and table.concat(bot.history,", ",1,math.min(45,#bot.history)) or "Пока пусто")
        attemptsView:SetDesc(#bot.log>0 and table.concat(bot.log,"\n",1,math.min(12,#bot.log)) or "Пока пусто")
    end

    return {
        refresh = refresh,
        syncEnabled = function(_, value)
            syncingToggle = true
            if toggle then toggle:Set(value) end
            syncingToggle = false
        end,
    }

end

return Interface

end
modules["shared/scope"] = function(require)
-- By SyneX
local Scope = {}
Scope.__index = Scope

function Scope.new()
    return setmetatable({items = {}, destroyed = false}, Scope)
end

function Scope:add(cleanup)
    assert(not self.destroyed, "Scope is already closed")
    table.insert(self.items, cleanup)
    return cleanup
end

function Scope:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    for index = #self.items, 1, -1 do
        local item = self.items[index]
        local ok, err = pcall(function()
            if type(item) == "function" then item() else item:Disconnect() end
        end)
        if not ok then warn("[SynHub] Не удалось завершить обработчик: " .. tostring(err)) end
    end
    table.clear(self.items)
end

return Scope

end
modules["games/slova/init"] = function(require)
-- By SyneX
local Core = require("games/slova/core")
local Config = require("games/slova/config")
local Driver = require("games/slova/driver")
local Storage = require("games/slova/storage")
local Interface = require("games/slova/interface")
local Scope = require("shared/scope")
local App = {}

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
        local ok, err = storage:save({version = 1, config = self.config, history = self.bot.history, rejected = rejected})
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
            app:identity()
            if input.KeyCode == Enum.KeyCode.F8 then app.setEnabled(not app.bot.enabled)
            elseif input.KeyCode == Enum.KeyCode.Escape then app.setEnabled(false) end
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

end
local function import(name)
    if cache[name] ~= nil then return cache[name] end
    assert(not loading[name], "Cyclic module: " .. name)
    local factory = assert(modules[name], "Unknown module: " .. name)
    loading[name] = true
    local result = factory(import)
    loading[name] = nil
    cache[name] = result
    return result
end
return import("games/slova/init")
