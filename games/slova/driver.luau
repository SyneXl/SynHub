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
        local blocked = driver.rebinding == true or binding.box:GetAttribute("ChatInputBlocked") == true
            or focused ~= nil and focused ~= binding.box
        local own = state.phase == "playing" and state.turn == state.you
        local busy = inspect.getupvalue(binding.submit, 4) == true
        local locked = os.clock() < (inspect.getupvalue(binding.submit, 3) or 0)
        local matchId = tostring(game.JobId or "") .. ":" .. tostring(state.tableId) .. ":" .. tostring(state.generation or 0)
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
