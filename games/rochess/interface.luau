-- By SyneX
local require = ...
local Analysis = require("analysis")
local Interface = {}

function Interface.create(app, context)
    local Library = assert(context.api.loadstring(context.assets.interface, "Interface"))()
    local window
    app.scope:add(function()
        if window then return end
        for _, gui in ipairs({Library.ScreenGui, Library.DropdownGui, Library.TooltipGui, Library.NotificationGui}) do
            if gui.Destroy then pcall(gui.Destroy, gui) end
        end
    end)
    Library:SetParent(game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"))
    for index, gui in ipairs({Library.ScreenGui, Library.DropdownGui, Library.TooltipGui, Library.NotificationGui}) do
        gui.DisplayOrder = 1000 + index
    end
    window = Library:CreateWindow({Title = "Шахматы", Author = "By SyneX", Icon = "crown",
        Folder = "SynHub/rochess/UI", Size = UDim2.fromOffset(470, 545), MinSize = Vector2.new(420, 460),
        SideBarWidth = 128, Theme = "Dark", Transparent = false, Resizable = true, AutoScale = false,
        User = {Enabled = false}})
    app.window = window
    app.scope:add(function() window:Destroy() end)
    window:SetToggleKey(nil)
    window:OnDestroy(function() if app.alive then app:Destroy() end end)
    window.UIElements.Main.Position = UDim2.new(1, -255, 0.5, 0)
    local moves = window:Tab({Title = "Ходы", Icon = "compass"})
    local settings = window:Tab({Title = "Настройки", Icon = "settings"})
    local status = moves:Paragraph({Title = "Подключаюсь к доске", Desc = "Stockfish 18"})
    moves:Toggle({Title = "Подсказки", Value = app.config.enabled, Callback = function(value)
        app.config.enabled = value; app:invalidate(); app:scheduleSave()
    end})
    local cards = {}
    local colors = {Color3.fromRGB(116, 235, 171), Color3.fromRGB(119, 182, 255), Color3.fromRGB(255, 202, 113)}
    for rank = 1, 3 do
        cards[rank] = moves:Button({Title = rank .. ". Ожидание позиции", Desc = "—", Icon = "arrow-up-right",
            IconColor = colors[rank], Callback = function()
                if app.rows[rank] then app.selected = rank; app.dirty = true end
            end})
    end
    local details = moves:Paragraph({Title = "Stockfish 18", Desc = "Три лучших хода для текущей позиции"})
    moves:Button({Title = "Обновить анализ", Icon = "refresh-cw", Callback = function() app:invalidate(true) end})
    settings:Section({Title = "Анализ"})
    settings:Slider({Title = "Глубина", Desc = "Больше глубина — дольше расчёт", Step = 1,
        Value = {Min = 10, Max = 18, Default = app.config.depth}, Callback = function(value)
            app.config.depth = math.clamp(math.floor(tonumber(value) or 14), 10, 18)
            app:invalidate(); app:scheduleSave()
        end})
    settings:Toggle({Title = "Только мой ход", Value = app.config.onlyOwn, Callback = function(value)
        app.config.onlyOwn = value; app:invalidate(); app:scheduleSave()
    end})
    settings:Section({Title = "Доска"})
    settings:Toggle({Title = "Стрелки ходов", Value = app.config.arrows, Callback = function(value)
        app.config.arrows = value; app:scheduleSave()
    end})
    settings:Toggle({Title = "Все три варианта", Desc = "Иначе показывается выбранный вариант", Value = app.config.allArrows,
        Callback = function(value) app.config.allArrows = value; app:scheduleSave() end})
    local menuKey
    menuKey = settings:Keybind({Title = "Показать или скрыть меню", Value = app.config.menuKey,
        KeyboardOnly = true, AllowEscape = false,
        Callback = function() if app.alive then app:identity(); window:Toggle() end end,
        OnChanged = function(key) app.config.menuKey = key; app:scheduleSave() end,
        OnPicking = function() app:identity() end})
    app.scope:add(function() menuKey:CancelPicking() end)
    window:OnClose(function() app:identity(); menuKey:CancelPicking() end)
    settings:Paragraph({Title = "Онлайн-анализ", Desc = "Оценки показаны с твоей стороны. Расчёт требует соединения с интернетом."})
    settings:Button({Title = "Выгрузить скрипт", Icon = "power", Callback = function() app:Destroy() end})

    local lastStatus, lastDetails, lastTitles, lastDescriptions = nil, nil, {}, {}
    return {refresh = function()
        local snapshot, rows = app.snapshot, app.rows
        local title = app.status
        local subtitle = snapshot and snapshot.color and (snapshot.color == 1 and "Ты играешь белыми" or "Ты играешь чёрными") or "Stockfish 18"
        local statusKey = title .. subtitle
        if statusKey ~= lastStatus then status:SetTitle(title); status:SetDesc(subtitle); lastStatus = statusKey end
        for rank, card in ipairs(cards) do
            local row = rows[rank]
            local label = row and rank .. ". " .. row.san .. "   " .. Analysis.score(row, snapshot.color) or rank .. ". —"
            local description = row and Analysis.coordinates(row) or "Ожидаю твой ход"
            if row and app.selected == rank then description ..= "\nВыбран на доске" end
            if lastTitles[rank] ~= label then card:SetTitle(label); lastTitles[rank] = label end
            if lastDescriptions[rank] ~= description then card:SetDesc(description); lastDescriptions[rank] = description end
        end
        local depth = #rows > 0 and rows[1].depth or 0
        local info = depth > 0 and "Глубина " .. depth .. " / " .. app.config.depth .. "\n"
            .. string.format("Расчёт %.1f с", app.seconds or 0) or "Три лучших хода для текущей позиции"
        if #rows > 0 and #rows < 3 then info ..= "\nДоступно ходов: " .. #rows end
        if lastDetails ~= info then details:SetDesc(info); lastDetails = info end
    end}
end

return Interface
