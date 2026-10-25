-- By SyneX
local require = ...
local Config = require("config")
local Interface = {}

function Interface.create(app, context, Core)
    local bot, driver = app.bot, app.driver
    local player = game:GetService("Players").LocalPlayer
    local Library = assert(context.api.loadstring(context.assets.interface, "Interface"))()
    local window
    app.scope:add(function()
        if window then return end
        for _, gui in ipairs({Library.ScreenGui,Library.DropdownGui,Library.TooltipGui,Library.NotificationGui}) do
            if gui.Destroy then pcall(gui.Destroy,gui) end
        end
    end)
    Library:SetParent(player.PlayerGui)
    for i,gui in ipairs({Library.ScreenGui,Library.DropdownGui,Library.TooltipGui,Library.NotificationGui}) do
        gui.DisplayOrder=1000+i
    end
    window = Library:CreateWindow({Title="SynHub — Слова", Author="By SyneX", Folder="SynHub/slova/UI",
        Size=UDim2.fromOffset(650,650), MinSize=Vector2.new(580,490), SideBarWidth=130,
        Theme="Dark", Transparent=false, Resizable=true, User={Enabled=false}})
    app.window = window
    app.scope:add(function() window:Destroy() end)
    window:SetToggleKey(nil)
    window:OnDestroy(function() if app.alive then app:Destroy() end end)

    local play = window:Tab({Title="Игра",Icon="play"})
    local historyTab = window:Tab({Title="История",Icon="history"})
    local settings = window:Tab({Title="Настройки",Icon="settings"})
    local function textBlock(tab, title, description)
        return tab:Paragraph({Title=title,Desc=description}).ParagraphFrame
    end
    local syncingToggle = false
    local toggle
    local setEnabled = app.setEnabled
    toggle = play:Toggle({Title="Автобой",Value=false,
        Callback=function(value) if not syncingToggle then setEnabled(value) end end})
    app.setEnabled=setEnabled
    local status = textBlock(play,"Готов",nil)

    local page, displayed, buttons, wordRows = 0, {}, {}, {}
    app.endingInput=play:Input({Title="Последняя буква",Placeholder="Любая",Value=app.config.ending,
        Callback=function(value) app.config.ending=Core.chars(Core.canonical(value))[1] or "";page=0;app.dirty=true;app:scheduleSave(0.6) end})
    local listInfo = textBlock(play,"Подходящие слова",nil)
    local wordRow
    for i=1,10 do
        if i%2==1 then wordRow=play:Group({});table.insert(wordRows,wordRow) end
        buttons[i]=wordRow:Button({Title="—",Icon="arrow-up-right",Size=UDim2.new(1,0,0,38),Callback=function()
            local entry=displayed[i]
            local snapshot=driver.read()
            if not entry then return end
            if not snapshot or not snapshot.own then bot:report("Дождись своего хода");return end
            if snapshot.letter ~= entry.first then bot:report("Сейчас в игре другая начальная буква");return end
            if not bot:request(entry.word) then bot:report("Дождись завершения текущей попытки") end
        end})
    end
    local pagination=play:Group({})
    pagination:Button({Title="В начало",Icon="arrow-left",Callback=function() page=0;app.dirty=true end})
    pagination:Button({Title="Ещё слова",Icon="arrow-right",Callback=function() page+=10;app.dirty=true end})
    local stats = textBlock(historyTab,"За эту сессию",nil)
    local historyView = textBlock(historyTab,"Использованные слова","Пока пусто")
    local attemptsView = textBlock(historyTab,"Последние попытки","Пока пусто")
    app.autoClearHistory = historyTab:Toggle({Title="Автоочистка",Desc="Очищать историю при начале новой катки",
        Value=app.config.autoClearHistory,Callback=function(value)
            app.config.autoClearHistory=value;app:scheduleSave(0.6)
        end})
    historyTab:Button({Title="Очистить историю",Callback=function()
        bot:clearHistory();app:scheduleSave(0.2)
    end})
    settings:Section({Title="Печать"})
    app.speed=settings:Slider({Title="Скорость печати",Desc="Слов в минуту",
        Value={Min=30,Max=300,Default=app.config.wpm},Step=1,Callback=function(value)
            app.config.wpm=math.clamp(tonumber(value) or 85,30,300);app:scheduleSave(0.6)
        end})
    settings:Toggle({Title="Естественный ритм",Value=app.config.natural,
        Callback=function(value) app.config.natural=value;app:scheduleSave(0.6) end})
    settings:Toggle({Title="Отправлять после ручного выбора",Desc="Автобой отправляет слова всегда",Value=app.config.enter,
        Callback=function(value) app.config.enter=value;app:scheduleSave(0.6) end})
    settings:Section({Title="Клавиши",Desc="Нажми на поле и затем на нужную клавишу"})
    local keybinds = {}
    app.keybinds = keybinds
    for _, action in ipairs({{name="auto",title="Автобой"},{name="stop",title="Остановить"},{name="menu",title="Показать или скрыть меню"}}) do
        local name = action.name
        keybinds[name] = settings:Keybind({Title=action.title,Value=app.config.keybinds[name],
            KeyboardOnly=true,AllowEscape=true,
            OnPicking=function(picking)
                app:identity()
                if picking then
                    for other, control in pairs(keybinds) do
                        if other ~= name then control:CancelPicking() end
                    end
                end
                driver.rebinding=picking
            end,
            OnChanged=function(key)
                app:identity()
                local previous=app.config.keybinds[name]
                for other, value in pairs(app.config.keybinds) do
                    if other ~= name and value == key then
                        app.config.keybinds[other]=previous
                        keybinds[other]:Set(previous)
                    end
                end
                app.config.keybinds[name]=key;app:scheduleSave(0.2)
            end})
    end
    local function cancelPicking()
        for _, control in pairs(keybinds) do control:CancelPicking() end
        driver.rebinding=false
    end
    app.scope:add(cancelPicking)
    window:OnClose(function() app:identity();cancelPicking() end)
    settings:Button({Title="Сбросить клавиши",Callback=function()
        app:identity();cancelPicking()
        app.config.keybinds=table.clone(Config.keybindDefaults)
        for name, control in pairs(keybinds) do control:Set(app.config.keybinds[name]) end
        app:scheduleSave(0.2)
    end})
    settings:Section({Title="Обслуживание"})
    settings:Button({Title="Очистить ввод в игре",Callback=function()
        setEnabled(false)
        local snapshot=driver.read()
        if snapshot and snapshot.ready then driver.write("") end
    end})
    settings:Button({Title="Сбросить отклонённые слова",Callback=function() bot.rejected={};app.dirty=true;app:scheduleSave(0.2) end})
    settings:Button({Title="Выгрузить скрипт",Callback=function() app:Destroy() end})

    local function refresh()
        app:identity()
        status:SetTitle(bot.status)
        stats:SetDesc("Принято: "..bot.metrics.accepted.."\nЗаменено: "..bot.metrics.rejected)
        local snapshot=bot.snapshot
        local start=snapshot and snapshot.letter or ""
        local total
        displayed,total=bot:candidates(start,app.config.ending,page,10)
        if page>=total and page>0 then page=0;displayed,total=bot:candidates(start,app.config.ending,0,10) end
        listInfo:SetTitle(start~="" and "Слова на «"..start.."»" or "Ожидаю начало игры")
        listInfo:SetDesc(total>0 and tostring(math.min(page+1,total)).."–"..math.min(page+10,total).." из "..total
            or start~="" and "Подходящих слов больше нет" or nil)
        for i,button in ipairs(buttons) do
            local entry=displayed[i]
            button:SetTitle(entry and entry.word or "—")
            button.ButtonFrame.UIElements.Main.Visible=entry~=nil
        end
        for i,row in ipairs(wordRows) do row.ElementFrame.Visible=displayed[i*2-1]~=nil end
        pagination.ElementFrame.Visible=total>10
        historyView:SetTitle("Использовано: "..#bot.history)
        historyView:SetDesc(#bot.history>0 and table.concat(bot.history,", ",1,math.min(45,#bot.history)) or "Пока пусто")
        attemptsView:SetDesc(#bot.log>0 and table.concat(bot.log,"\n",1,math.min(12,#bot.log)) or "Пока пусто")
    end

    return {
        refresh = refresh,
        syncEnabled = function(_, value)
            syncingToggle = true
            if toggle then toggle:Set(value) end
            syncingToggle = false
        end,
    }

end

return Interface
