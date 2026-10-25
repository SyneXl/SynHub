-- By SyneX
local Driver = {}

function Driver.new()
    local storage = game:GetService("ReplicatedStorage")
    local folder = assert(storage:FindFirstChild("ChessClient"), "Не найден интерфейс шахмат")
    local client = require(folder:WaitForChild("App", 10))
    local chess = assert(storage:FindFirstChild("Chess"), "Не найдена доска")
    local Engine = require(assert(chess:FindFirstChild("Engine"), "Не найдены правила шахмат"))
    local driver = {client = client}

    function driver.read()
        local session = client.session
        if not session or not session.engine then return {reason = "Открой партию"} end
        if session.kind ~= "online" and session.kind ~= "bot" then return {reason = "Открой партию с игроком или ботом"} end
        local ply = #session.ucis
        if session.over then return {reason = "Партия завершена", over = true} end
        if session.viewPly ~= nil and session.viewPly ~= ply then return {reason = "Вернись к текущей позиции"} end
        if session.myColor ~= 1 and session.myColor ~= -1 then return {reason = "Режим наблюдения"} end
        return {session = session, version = session.version, fen = session.engine:getFen(),
            color = session.myColor, turn = session.engine.side, own = session:isMyTurn(),
            kind = session.kind, ply = ply, board = client.board}
    end

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
