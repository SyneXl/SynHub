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
