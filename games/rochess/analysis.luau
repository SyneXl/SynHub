-- By SyneX
local Analysis = {}
Analysis.__index = Analysis

local function finite(value)
    if type(value) ~= "number" and type(value) ~= "string" then return nil end
    local number = tonumber(value)
    return number and number == number and math.abs(number) < math.huge and number or nil
end

function Analysis.square(name)
    if type(name) ~= "string" or not name:match("^[a-h][1-8]$") then return nil end
    local rank = assert(tonumber(name:sub(2, 2)))
    return (rank - 1) * 8 + name:byte(1) - 96
end

function Analysis.new(fen, legal)
    local count = 0
    for _ in pairs(legal) do count += 1 end
    return setmetatable({fen = fen, legal = legal, count = math.min(3, count), batches = {}, depth = 0}, Analysis)
end

function Analysis:row(message, rank)
    if type(message) ~= "table" or message.fen ~= self.fen then return nil end
    local move = message.move
    if type(move) ~= "string" or not self.legal[move] then return nil end
    local depth, score, mate = finite(message.depth), finite(message.eval), finite(message.mate)
    if not depth or depth < 1 or depth > 128 or depth % 1 ~= 0 or not (score or mate) then return nil end
    return {move = move, san = self.legal[move].san, piece = self.legal[move].piece,
        from = move:sub(1, 2), to = move:sub(3, 4), promotion = move:sub(5),
        rank = rank, depth = depth, score = score, mate = mate}
end

function Analysis:ingest(message)
    if type(message) ~= "table" or (message.type ~= "move" and message.type ~= "bestmove") then return nil end
    local rank = finite(type(message.debug) == "string" and message.debug:match("multipv%s+(%d+)"))
        or finite(message.multipv) or (message.type == "bestmove" and 1)
    if not rank or rank % 1 ~= 0 or rank < 1 or rank > self.count then return nil end
    local row = self:row(message, rank)
    if not row or row.depth < self.depth then return nil end
    local batch = self.batches[row.depth] or {}
    self.batches[row.depth] = batch
    batch[rank] = row
    local seen, result = {}, {}
    for index = 1, self.count do
        local candidate = batch[index]
        if not candidate or seen[candidate.move] then return nil end
        seen[candidate.move] = true
        result[index] = candidate
    end
    self.depth, self.rows = row.depth, result
    for depth in pairs(self.batches) do if depth < self.depth then self.batches[depth] = nil end end
    return result
end

function Analysis.score(row, color)
    if row.mate ~= nil then
        local mate = row.mate * (color or 1)
        return (mate < 0 and "−M" or "M") .. tostring(math.abs(mate))
    end
    local score = (row.score or 0) * (color or 1)
    if math.abs(score) < 0.005 then return "0.00" end
    return string.format("%+.2f", score)
end

function Analysis.coordinates(row)
    local pieces = {p = "Пешка", n = "Конь", b = "Слон", r = "Ладья", q = "Ферзь", k = "Король"}
    local text = (pieces[row.piece] or "Ход") .. " " .. row.from .. " → " .. row.to
    if row.promotion ~= "" then text ..= " = " .. row.promotion:upper() end
    return text
end

return Analysis
