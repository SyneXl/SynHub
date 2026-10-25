-- By SyneX
local require = ...
local Analysis = require("analysis")
local Engine = {}
Engine.__index = Engine

function Engine.new(api, http, clock)
    return setmetatable({api = api, http = http, clock = clock or os.clock, serial = 0}, Engine)
end

local function close(operation)
    for _, connection in ipairs(operation.connections) do connection:Disconnect() end
    table.clear(operation.connections)
    if operation.socket then pcall(operation.socket.Close, operation.socket); operation.socket = nil end
end

function Engine:cancel()
    local operation = self.operation
    if not operation then return end
    operation.alive = false
    self.operation = nil
    close(operation)
end

function Engine:tick()
    local operation = self.operation
    if operation and operation.alive and self.clock() - operation.started > 10 then
        local callback = operation.callback
        self:cancel()
        callback("error", "engineTimeout")
    end
end

function Engine:analyze(fen, legal, depth, callback)
    self:cancel()
    self.serial += 1
    local operation = {alive = true, started = self.clock(), connections = {}, callback = callback,
        model = Analysis.new(fen, legal), id = self.serial, rest = false}
    self.operation = operation
    local function current() return operation.alive and self.operation == operation end
    local function emit(kind, value)
        if current() then callback(kind, value, self.clock() - operation.started) end
    end
    local function finish(kind, value)
        if not current() then return end
        operation.alive = false
        self.operation = nil
        close(operation)
        callback(kind, value, self.clock() - operation.started)
    end

    local function rest()
        if not current() or operation.rest then return end
        operation.rest = true
        close(operation)
        local request = self.api.request
        if type(request) ~= "function" then finish("error", "engineConnect"); return end
        local rows, remaining = {}, {}
        for move in pairs(legal) do remaining[move] = true end
        for rank = 1, operation.model.count do
            if not current() then return end
            local moves = {}
            for move in pairs(remaining) do table.insert(moves, move) end
            table.sort(moves)
            local ok, response = pcall(request, {Url = "https://chess-api.com/v1", Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = self.http:JSONEncode({fen = fen, variants = 1, depth = depth,
                    maxThinkingTime = 100, searchmoves = table.concat(moves, " ")})})
            if not current() then return end
            if not ok or type(response) ~= "table" or tonumber(response.StatusCode) ~= 200 then
                finish("error", type(response) == "table" and tonumber(response.StatusCode) == 429
                    and "engineBusy" or "engineOffline"); return
            end
            local valid, message = pcall(self.http.JSONDecode, self.http, response.Body)
            local row = valid and operation.model:row(message, rank)
            if not row or not remaining[row.move] then finish("error", "engineIncomplete"); return end
            rows[rank], remaining[row.move] = row, nil
        end
        finish("done", rows)
    end

    task.spawn(function()
        if operation.model.count == 0 then finish("done", {}); return end
        local websocket = self.api.WebSocket
        if type(websocket) ~= "table" or type(websocket.connect or websocket.Connect) ~= "function" then rest(); return end
        local ok, socket = pcall(websocket.connect or websocket.Connect, "wss://chess-api.com/v1")
        if not current() then if ok and socket then pcall(socket.Close, socket) end; return end
        if not ok or not socket then rest(); return end
        operation.socket = socket
        table.insert(operation.connections, socket.OnMessage:Connect(function(text)
            if not current() then return end
            local valid, message = pcall(self.http.JSONDecode, self.http, text)
            if not valid or type(message) ~= "table" then return end
            local rows = operation.model:ingest(message)
            if rows then emit("rows", rows) end
            if message.type == "bestmove" and message.fen == fen then
                if operation.model.rows then finish("done", operation.model.rows)
                else task.defer(rest) end
            elseif message.type == "error" then
                task.defer(rest)
            end
        end))
        table.insert(operation.connections, socket.OnClose:Connect(function()
            if current() then task.defer(rest) end
        end))
        local sent = pcall(socket.Send, socket, self.http:JSONEncode({fen = fen, variants = 3,
            depth = depth, maxThinkingTime = 100}))
        if not sent then rest() end
    end)
end

return Engine
