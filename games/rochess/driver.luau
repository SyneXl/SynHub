-- By SyneX
local import = ...
local Analysis = import("analysis")
local Driver = {}

function Driver.new()
    local storage = game:GetService("ReplicatedStorage")
    local folder = assert(storage:FindFirstChild("ChessClient"), "Chess client not found")
    local client = require(folder:WaitForChild("App", 10))
    local chess = assert(storage:FindFirstChild("Chess"), "Chess board not found")
    local Engine = require(assert(chess:FindFirstChild("Engine"), "Chess rules not found"))
    local botOk, Bot = pcall(require, chess:FindFirstChild("Bot"))
    local driver = {client = client}

    function driver.read()
        local session = client.session
        if not session or not session.engine then return {reason = "openGame"} end
        if session.kind ~= "online" and session.kind ~= "bot" then return {reason = "openMatch"} end
        local ply = #session.ucis
        if session.over then return {reason = "gameOver", over = true} end
        if session.viewPly ~= nil and session.viewPly ~= ply then return {reason = "historyView"} end
        if session.myColor ~= 1 and session.myColor ~= -1 then return {reason = "spectating"} end
        local left
        if session.clocks and type(session.clockFor) == "function" then
            left = session:clockFor(session.myColor, workspace:GetServerTimeNow()) / 1000
        end
        if session.deadline and ply < 2 then left = math.max(0, session.deadline - workspace:GetServerTimeNow()) end
        return {session = session, version = session.version, fen = session.engine:getFen(),
            color = session.myColor, turn = session.engine.side, own = session:isMyTurn(),
            kind = session.kind, ply = ply, board = client.board, left = left}
    end

    function driver.play(snapshot, uci)
        local now = driver.read()
        if now.reason or not now.own or now.session ~= snapshot.session or now.version ~= snapshot.version
            or now.fen ~= snapshot.fen or now.ply ~= snapshot.ply then return false end
        if type(uci) ~= "string" or not uci:match("^[a-h][1-8][a-h][1-8][qrbn]?$") then return false end
        if not now.session.engine:moveFromUci(uci) then return false end
        local promotion = {q = Engine.QUEEN, r = Engine.ROOK, b = Engine.BISHOP, n = Engine.KNIGHT}
        local ok, result = pcall(client.onBoardMove, Analysis.square(uci:sub(1, 2)), Analysis.square(uci:sub(3, 4)),
            promotion[uci:sub(5)] or 0, false)
        return ok and result == true
    end

    function driver.target(snapshot, rating, budget, cancelled)
        if not botOk or type(Bot) ~= "table" or type(Bot.think) ~= "function" or cancelled() then return nil end
        local session = snapshot.session
        return Bot.think(session.startFen or session.engine.startFen or Engine.START_FEN, table.clone(session.ucis),
            {rating = rating, time = budget, depth = 12}, {cancelled = cancelled})
    end

    function driver.flip() client.flip() end

    function driver.legal(fen)
        local board = Engine.new(fen)
        local legal = {}
        for _, move in ipairs(board:legalMoves()) do
            local uci = board:moveToUci(move)
            local piece = board.board[Engine.moveFrom(move)]
            legal[uci] = {san = board:moveToSan(move), piece = (Engine.PIECE_CHARS[math.abs(piece)] or ""):lower()}
        end
        return legal
    end

    return driver
end

return Driver
