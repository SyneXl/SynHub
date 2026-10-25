-- By SyneX
local I18n = {}
I18n.translations = {
    en = {
        play = "Play", autoTab = "Auto Play", settings = "Settings", hints = "Hints", autoPlay = "Auto play",
        connecting = "Connecting to the board", openGame = "Start a game", openMatch = "Start a game against a player or bot",
        gameOver = "Game over", historyView = "Return to the live position", spectating = "Spectating",
        hintsOff = "Hints are off", waitingTurn = "Waiting for your turn", yourTurn = "Your turn", opponentTurn = "Opponent's turn",
        analyzing = "Analyzing position", refining = "Refining the best moves", noMoves = "No legal moves",
        engineTimeout = "Analysis timed out. Retrying", engineConnect = "Could not connect to the engine",
        engineBusy = "Engine busy. Retrying shortly", engineOffline = "Engine connection unavailable",
        engineIncomplete = "Incomplete analysis. Retrying", readError = "Could not read the position",
        white = "White", black = "Black", playingAs = "Playing as %s",
        depthTime = "Depth %d / %d | %.1f s", refresh = "Refresh", flip = "Flip board",
        analysis = "Analysis", depth = "Search depth",
        onlyOwn = "Only my turn", board = "Board", arrows = "Move arrows", allArrows = "Show all three moves",
        interface = "Interface", language = "Language",
        uiScale = "UI scale", menuKey = "Toggle menu", autoKey = "Toggle auto play", unload = "Unload script",
        autoPaused = "Auto play is off", autoWaiting = "Waiting for your turn", autoThinking = "Choosing a move",
        autoReady = "Move ready", autoSending = "Playing move", autoPlayed = "Played %s", autoFailed = "Move was not accepted",
        autoLocalFailed = "Target-strength engine unavailable", autoTiming = "Decision timing",
        minDelay = "Minimum time (s)", maxDelay = "Maximum time (s)", nextMove = "Next move",
        waitingAnalysis = "Waiting for analysis", seconds = "%.1f s", strength = "Playing strength", mode = "Mode",
        maximum = "Maximum", targetElo = "Target ELO", elo = "Target ELO (approx.)",
        autoSummary = "Auto play", paused = "Paused", ready = "Ready", enabled = "Enabled",
        p = "Pawn", n = "Knight", b = "Bishop", r = "Rook", q = "Queen", k = "King", move = "Move",
    },
    ru = {
        play = "Игра", autoTab = "Автоигра", settings = "Настройки", hints = "Подсказки", autoPlay = "Автоигра",
        connecting = "Подключаюсь к доске", openGame = "Начни партию", openMatch = "Начни партию с игроком или ботом",
        gameOver = "Партия завершена", historyView = "Вернись к текущей позиции", spectating = "Режим наблюдения",
        hintsOff = "Подсказки выключены", waitingTurn = "Ожидаю твой ход", yourTurn = "Твой ход", opponentTurn = "Ход соперника",
        analyzing = "Анализирую позицию", refining = "Уточняю лучшие ходы", noMoves = "Нет доступных ходов",
        engineTimeout = "Анализ задержался. Повторяю", engineConnect = "Не удалось подключиться к движку",
        engineBusy = "Движок занят. Скоро повторю", engineOffline = "Нет соединения с движком",
        engineIncomplete = "Неполный анализ. Повторяю", readError = "Не удалось прочитать позицию",
        white = "Белые", black = "Чёрные", playingAs = "Твоя сторона: %s",
        depthTime = "Глубина %d / %d | %.1f с", refresh = "Обновить", flip = "Перевернуть",
        analysis = "Анализ", depth = "Глубина поиска",
        onlyOwn = "Только мой ход", board = "Доска", arrows = "Стрелки ходов", allArrows = "Все три варианта",
        interface = "Интерфейс", language = "Язык",
        uiScale = "Масштаб интерфейса", menuKey = "Показать или скрыть меню", autoKey = "Включить или выключить автоигру", unload = "Выгрузить скрипт",
        autoPaused = "Автоигра выключена", autoWaiting = "Ожидаю твой ход", autoThinking = "Выбираю ход",
        autoReady = "Ход готов", autoSending = "Делаю ход", autoPlayed = "Сыграно %s", autoFailed = "Ход не принят",
        autoLocalFailed = "Движок заданной силы недоступен", autoTiming = "Время на решение",
        minDelay = "Минимум (с)", maxDelay = "Максимум (с)", nextMove = "Следующий ход",
        waitingAnalysis = "Ожидаю анализ", seconds = "%.1f с", strength = "Сила игры", mode = "Режим",
        maximum = "Максимальная", targetElo = "Заданный ELO", elo = "Целевой ELO (примерно)",
        autoSummary = "Автоигра", paused = "Пауза", ready = "Готово", enabled = "Включена",
        p = "Пешка", n = "Конь", b = "Слон", r = "Ладья", q = "Ферзь", k = "Король", move = "Ход",
    },
}

function I18n.text(language, key, ...)
    local dictionary = I18n.translations[language] or I18n.translations.en
    local text = dictionary[key] or I18n.translations.en[key] or key
    if select("#", ...) > 0 then return string.format(text, ...) end
    return text
end

return I18n
