-- By SyneX
local Queue = {}
Queue.__index = Queue

function Queue.new(driver, config, emit, clock, random)
    local self = setmetatable({driver = driver, config = config, emit = emit or function() end,
        clock = clock or os.clock, random = random or math.random, enabled = config.autoQueue,
        status = "queueOff", failures = 0}, Queue)
    self:reset()
    return self
end

function Queue:state(status)
    if self.status ~= status then self.status = status; self.emit() end
end

function Queue:reset()
    self.due, self.mode = nil, nil
end

function Queue:setEnabled(value)
    self.enabled = value == true
    self.config.autoQueue = self.enabled
    self:reset()
    if not self.enabled then self.driver.cancelQueue(self.search); self.search = nil end
    self:state(self.enabled and "queueWaiting" or "queueOff")
end

function Queue:update(blocked)
    if not self.enabled then return end
    if blocked then self:reset(); self:state("paused"); return end
    local lobby = self.driver.lobby()
    if not lobby.ready then
        self:reset()
        if lobby.search ~= self.search then self.search = nil end
        self:state(lobby.reason)
        return
    end
    self.search = nil
    local modes, allowed = {}, {}
    for _, mode in ipairs(self.driver.modes) do allowed[mode.id] = true end
    for _, mode in ipairs(self.config.queueModes) do if allowed[mode] then table.insert(modes, mode) end end
    if #modes == 0 then self:reset(); self:state("queueSelect"); return end
    local now = self.clock()
    if not self.due then
        self.mode = modes[self.random(1, #modes)]
        self.due = now + self.config.queueDelay
        self:state("queueWaiting")
    end
    if now < self.due then return end
    local ok, search = pcall(self.driver.startQueue, self.mode)
    if ok and search then
        self.search, self.failures = search, 0
        self:reset()
        self:state("queueSearching")
    else
        self.failures += 1
        self.due = now + math.min(30, 2 ^ math.min(self.failures, 5))
        self:state("queueRetry")
    end
end

function Queue:Destroy() self.enabled = false; self:reset() end

return Queue
