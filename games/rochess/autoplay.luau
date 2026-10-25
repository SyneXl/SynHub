-- By SyneX
local Auto = {}
Auto.__index = Auto

function Auto.new(driver, config, emit, clock, random)
    local self: any = setmetatable({driver = driver, config = config, emit = emit or function() end,
        clock = clock or os.clock, random = random or math.random, enabled = false,
        status = "autoPaused", played = 0}, Auto)
    return self
end

function Auto:state(key)
    if self.status == key then return end
    self.status = key
    self.emit("status")
end

function Auto:reset()
    if self.plan then self.plan.cancelled = true; self.plan = nil end
end

function Auto:setEnabled(value)
    self:reset()
    self.enabled = value == true
    self.lastSent = nil
    self:state(self.enabled and "autoWaiting" or "autoPaused")
    self.emit("enabled")
end

function Auto:fail(reason)
    self.enabled = false
    self:reset()
    self:state(reason)
    self.emit("enabled")
end

function Auto:update(snapshot, rows, complete, blocked)
    if not self.enabled then return end
    if blocked or not snapshot or snapshot.reason or not snapshot.own then
        self:reset()
        self:state(blocked and "paused" or snapshot and snapshot.reason or "autoWaiting")
        return
    end
    local plan = self.plan
    if not plan or plan.session ~= snapshot.session or plan.fen ~= snapshot.fen or plan.version ~= snapshot.version then
        self:reset()
        if self.lastSent and self.lastSent.session == snapshot.session and self.lastSent.fen == snapshot.fen
            and self.lastSent.ply == snapshot.ply then self:fail("autoFailed"); return end
        local delay = self.config.minDelay + self.random() * (self.config.maxDelay - self.config.minDelay)
        plan = {session = snapshot.session, version = snapshot.version, fen = snapshot.fen,
            started = self.clock(), due = self.clock() + delay, ply = snapshot.ply, cancelled = false}
        self.plan = plan
        self:state("autoThinking")
        if self.config.strength == "elo" then
            local captured = plan
            task.spawn(function()
                local function cancelled() return not self.enabled or self.plan ~= captured or captured.cancelled end
                local ok, move = pcall(self.driver.target, snapshot, self.config.elo, math.clamp(delay * 0.6, 0.05, 0.75), cancelled)
                if cancelled() then return end
                if not ok or type(move) ~= "string" then self:fail("autoLocalFailed"); return end
                captured.move = move
                self.emit("status")
            end)
        end
    end
    if plan.cancelled or plan.submitted then return end
    if self.config.strength == "max" and complete and rows[1] then
        plan.move, plan.san = rows[1].move, rows[1].san
    end
    if snapshot.left then plan.due = math.min(plan.due, self.clock() + math.max(0, snapshot.left - 0.3)) end
    if not plan.move then self:state("autoThinking"); return end
    self:state("autoReady")
    if self.clock() < plan.due then return end
    plan.submitted = true
    self.lastSent = {session = plan.session, fen = plan.fen, ply = plan.ply}
    self:state("autoSending")
    local ok, played = pcall(self.driver.play, snapshot, plan.move)
    if not ok or not played then
        local current = self.driver.read()
        if current.session ~= snapshot.session or current.fen ~= snapshot.fen or not current.own then self:reset(); return end
        self:fail("autoFailed"); return
    end
    self.played += 1
    self.lastMove = plan.san or plan.move
    self:state("autoPlayed")
end

function Auto:Destroy() self.enabled = false; self:reset() end

return Auto
