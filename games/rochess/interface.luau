-- By SyneX
local require = ...
local Analysis = require("analysis")
local I18n = require("i18n")
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
    Library:Localization({Enabled = true, DefaultLanguage = "en", Prefix = "loc:", Translations = I18n.translations})
    Library:SetLanguage(app.config.language)
    Library:SetParent(game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"))
    for index, gui in ipairs({Library.ScreenGui, Library.DropdownGui, Library.TooltipGui, Library.NotificationGui}) do
        gui.DisplayOrder = 1000 + index
    end
    local palette = context.theme
    local accent = palette.accent
    Library:AddTheme(palette.windui)
    window = Library:CreateWindow({Title = "RoChess", Author = "By SyneX", Icon = "crown", Theme = palette.windui.Name,
        Folder = "SynHub/rochess/UI", Size = UDim2.fromOffset(530, 570), MinSize = Vector2.new(490, 460),
        SideBarWidth = 136, NewElements = true, Radius = 16, ElementsRadius = 12,
        Transparent = false, Resizable = true, AutoScale = false, User = {Enabled = false},
        Topbar = {Height = 46, ButtonsType = "Default"}})
    app.window = window
    app.scope:add(function() window:Destroy() end)
    window:SetToggleKey(nil)
    window:SetUIScale(app.config.uiScale)
    window:OnDestroy(function() if app.alive then app:Destroy() end end)
    window.UIElements.Main.Position = UDim2.new(1, -285, 0.5, 0)
    window:Tag({Title = "Stockfish 18", Icon = "cpu", Color = accent, Border = true})

    local play = window:Tab({Title = "loc:play", Icon = "compass", IconColor = accent})
    local autoTab = window:Tab({Title = "loc:autoTab", Icon = "play", IconColor = accent})
    local settings = window:Tab({Title = "loc:settings", Icon = "settings", IconColor = accent})
    local status = play:Paragraph({Title = "", Desc = ""})
    play:Toggle({Title = "loc:hints", Value = app.config.enabled, Callback = function(value)
        app.config.enabled = value; app:invalidate(); app:scheduleSave()
    end})
    local syncingAuto = false
    local autoToggle = autoTab:Toggle({Title = "loc:autoPlay", Value = app.auto.enabled, Callback = function(value)
        if not syncingAuto then app:setAuto(value) end
    end})
    app.autoToggle = autoToggle
    local colors = palette.moves
    local cards = {}
    for rank = 1, 3 do
        cards[rank] = play:Button({Title = "", Icon = "arrow-up-right", IconColor = colors[rank],
            Callback = function() if app.rows[rank] then app.selected = rank; app.dirty = true end end})
        cards[rank].ElementFrame.Visible = false
    end
    local autoStatus = autoTab:Paragraph({Title = "", Desc = ""})
    autoStatus.ElementFrame.Visible = false
    local countdown = autoTab:ProgressBar({Title = "loc:nextMove", Animate = false, Width = 160,
        Value = {Min = 0, Max = 1, Default = 0}, ShowValue = true, ValueWidth = 64,
        Format = function()
            local plan = app.auto.plan
            return plan and plan.move and app:t("seconds", math.max(0, plan.due - os.clock())) or app:t("waitingAnalysis")
        end})
    countdown.ElementFrame.Visible = false
    local actions = play:Group({})
    actions:Button({Title = "loc:refresh", Icon = "refresh-cw", Callback = function() app:invalidate(true) end})
    actions:Button({Title = "loc:flip", Icon = "repeat", Callback = function() app.driver.flip() end})

    local matchmaking = autoTab:Section({Title = "loc:matchmaking", Icon = "users", Box = true, BoxBorder = false, Opened = true})
    local syncingQueue = false
    app.queueToggle = matchmaking:Toggle({Title = "loc:autoQueue", Value = app.config.autoQueue,
        Callback = function(value) if not syncingQueue then app:setQueue(value) end end})
    local syncingModes = false
    local function modeLabel(mode) return app:t(mode.class) .. " " .. mode.id end
    local function modeOptions()
        local values, selected = {}, {}
        for _, mode in ipairs(app.driver.modes) do
            local label = modeLabel(mode)
            table.insert(values, label)
            if table.find(app.config.queueModes, mode.id) then table.insert(selected, label) end
        end
        return values, selected
    end
    local modeValues, selectedModes = modeOptions()
    local modesControl = matchmaking:Dropdown({Title = "loc:queueModes", Multi = true, AllowNone = true,
        Values = modeValues, Value = selectedModes, Callback = function(values)
            if syncingModes then return end
            local selected = {}
            if type(values) == "table" then
                for _, mode in ipairs(app.driver.modes) do
                    if table.find(values, modeLabel(mode)) then table.insert(selected, mode.id) end
                end
            end
            app.config.queueModes = selected
            app.queue:reset(); app.dirty = true; app:scheduleSave()
        end})
    app.modesControl = modesControl
    app.queueDelayControl = matchmaking:Slider({Title = "loc:queueDelay", Step = 0.5,
        Value = {Min = 1, Max = 20, Default = app.config.queueDelay}, Callback = function(value)
            app.config.queueDelay = math.clamp(tonumber(value) or 3, 1, 20)
            app.queue:reset(); app.dirty = true; app:scheduleSave()
        end})
    local queueStatus = matchmaking:Paragraph({Title = "", Desc = ""})
    queueStatus.ElementFrame.Visible = false

    local timing = autoTab:Section({Title = "loc:autoTiming", Icon = "timer",
        Box = true, BoxBorder = false, Opened = false})
    local minimum, maximum
    local syncingTiming = false
    minimum = timing:Slider({Title = "loc:minDelay", Step = 0.1,
        Value = {Min = 0, Max = 10, Default = app.config.minDelay}, Callback = function(value)
            if syncingTiming then return end
            app.config.minDelay = math.clamp(tonumber(value) or 0.8, 0, 10)
            if app.config.maxDelay < app.config.minDelay then
                app.config.maxDelay = app.config.minDelay
                if maximum then syncingTiming = true; maximum:Set(app.config.maxDelay); syncingTiming = false end
            end
            app.auto:reset(); app.dirty = true; app:scheduleSave()
        end})
    maximum = timing:Slider({Title = "loc:maxDelay", Step = 0.1,
        Value = {Min = 0, Max = 10, Default = app.config.maxDelay}, Callback = function(value)
            if syncingTiming then return end
            app.config.maxDelay = math.clamp(tonumber(value) or 1.8, 0, 10)
            if app.config.minDelay > app.config.maxDelay then
                app.config.minDelay = app.config.maxDelay
                if minimum then syncingTiming = true; minimum:Set(app.config.minDelay); syncingTiming = false end
            end
            app.auto:reset(); app.dirty = true; app:scheduleSave()
        end})
    app.minDelayControl, app.maxDelayControl = minimum, maximum
    local strength = autoTab:Section({Title = "loc:strength", Icon = "gauge", Box = true, BoxBorder = false, Opened = false})
    local eloControl
    local syncingMode = false
    local strengthControl = strength:Dropdown({Title = "loc:mode", Values = {app:t("maximum"), app:t("targetElo")},
        Value = app:t(app.config.strength == "elo" and "targetElo" or "maximum"), Callback = function(value)
            if syncingMode then return end
            app.config.strength = (value == I18n.translations.en.targetElo or value == I18n.translations.ru.targetElo) and "elo" or "max"
            app.auto:reset(); app.dirty = true; app:scheduleSave()
        end})
    app.strengthControl = strengthControl
    eloControl = strength:Slider({Title = "loc:elo", Step = 100,
        Value = {Min = 800, Max = 2800, Default = app.config.elo}, Callback = function(value)
            app.config.elo = math.clamp(math.floor((tonumber(value) or 1600) / 100) * 100, 800, 2800)
            app.auto:reset(); app:scheduleSave()
        end})

    local interface = settings:Section({Title = "loc:interface", Icon = "palette", Box = true, BoxBorder = false, Opened = true})
    local languageControl = interface:Dropdown({Title = "loc:language", Values = {"English", "Русский"},
        Value = app.config.language == "ru" and "Русский" or "English", Callback = function(value)
            app:setLanguage(value == "Русский" and "ru" or "en")
        end})
    app.languageControl = languageControl
    interface:Slider({Title = "loc:uiScale", Step = 0.05,
        Value = {Min = 0.8, Max = 1.2, Default = app.config.uiScale}, Callback = function(value)
            app.config.uiScale = math.clamp(tonumber(value) or 1, 0.8, 1.2)
            window:SetUIScale(app.config.uiScale); app:scheduleSave()
        end})
    local bindings = {}
    local function anyPicking()
        for _, control in pairs(bindings) do if control.Picking then return true end end
        return false
    end
    for _, action in ipairs({{name = "menuKey", title = "menuKey"}, {name = "autoKey", title = "autoKey"}}) do
        local name = action.name
        bindings[name] = interface:Keybind({Title = "loc:" .. action.title, Value = app.config[name],
            KeyboardOnly = true, AllowEscape = false, Callback = function()
                if not app.alive or anyPicking() then return end
                app:identity()
                if name == "menuKey" then window:Toggle() else app:setAuto(not app.auto.enabled) end
            end,
            OnPicking = function(picking)
                app:identity()
                if picking then
                    for other, control in pairs(bindings) do if other ~= name then control:CancelPicking() end end
                end
                app.rebinding = picking
            end,
            OnChanged = function(key)
                app:identity()
                local other = name == "menuKey" and "autoKey" or "menuKey"
                if app.config[other] == key then bindings[other]:Set(app.config[name]); app.config[other] = app.config[name] end
                app.config[name] = key; app:scheduleSave()
            end})
    end
    app.keybinds = bindings
    local function cancelPicking()
        app:identity()
        for _, control in pairs(bindings) do control:CancelPicking() end
        app.rebinding = false
    end
    app.scope:add(cancelPicking)
    window:OnClose(cancelPicking)
    local analysis = settings:Section({Title = "loc:analysis", Icon = "cpu", Box = true, BoxBorder = false, Opened = false})
    analysis:Slider({Title = "loc:depth", Step = 1,
        Value = {Min = 10, Max = 18, Default = app.config.depth}, Callback = function(value)
            app.config.depth = math.clamp(math.floor(tonumber(value) or 14), 10, 18)
            app:invalidate(); app:scheduleSave()
        end})
    analysis:Toggle({Title = "loc:onlyOwn", Value = app.config.onlyOwn, Callback = function(value)
        app.config.onlyOwn = value; app:invalidate(); app:scheduleSave()
    end})
    local board = settings:Section({Title = "loc:board", Icon = "grid-2x2", Box = true, BoxBorder = false, Opened = false})
    board:Toggle({Title = "loc:arrows", Value = app.config.arrows, Callback = function(value)
        app.config.arrows = value; app.dirty = true; app:scheduleSave()
    end})
    board:Toggle({Title = "loc:allArrows", Value = app.config.allArrows,
        Callback = function(value) app.config.allArrows = value; app:scheduleSave() end})
    settings:Button({Title = "loc:unload", Icon = "power", Callback = function() app:Destroy() end})

    local lastStatus, lastAuto, lastStrength, lastQueue, lastLanguage = nil, nil, nil, nil, app.config.language
    local titles, descriptions = {}, {}
    local view = {}
    function view:syncAuto(value)
        syncingAuto = true; autoToggle:Set(value); syncingAuto = false
    end
    function view:syncQueue(value)
        syncingQueue = true; app.queueToggle:Set(value); syncingQueue = false
    end
    function view:setLanguage(language)
        Library:SetLanguage(language)
        syncingMode = true
        strengthControl:Refresh({app:t("maximum"), app:t("targetElo")})
        strengthControl:Select(app:t(app.config.strength == "elo" and "targetElo" or "maximum"))
        syncingMode = false
        syncingModes = true
        local values, selected = modeOptions()
        modesControl:Refresh(values)
        modesControl:Select(selected)
        syncingModes = false
        lastStatus, lastAuto, lastStrength, titles, descriptions = nil, nil, nil, {}, {}
        lastLanguage = language
        app.dirty = true
        self.refresh()
    end
    function view.refresh()
        if lastLanguage ~= app.config.language then view:setLanguage(app.config.language); return end
        local snapshot, rows = app.snapshot, app.rows
        local subtitle = snapshot and snapshot.color and app:t("playingAs", app:t(snapshot.color == 1 and "white" or "black")) or ""
        if #rows > 0 then subtitle ..= (subtitle ~= "" and "\n" or "") .. app:t("depthTime", rows[1].depth, app.config.depth, app.seconds or 0) end
        status.ElementFrame.Visible = app.status ~= "openGame" and app.status ~= "openMatch" and app.status ~= "connecting"
        local statusKey = app.status .. subtitle
        if lastStatus ~= statusKey then status:SetTitle(app:t(app.status)); status:SetDesc(subtitle); lastStatus = statusKey end
        for rank, card in ipairs(cards) do
            local row = app.config.enabled and rows[rank] or nil
            card.ElementFrame.Visible = row ~= nil
            if row then
                local color = palette.moveHex[rank]
                local title = string.format('<font color="%s">%02d</font>   <b>%s</b>   %s', color, rank, row.san, Analysis.score(row, snapshot.color))
                local description = Analysis.coordinates(row, app.config.language)
                if titles[rank] ~= title then card:SetTitle(title); titles[rank] = title end
                if descriptions[rank] ~= description then card:SetDesc(description); descriptions[rank] = description end
            end
        end
        local plan = app.auto.plan
        countdown.ElementFrame.Visible = app.auto.enabled and plan ~= nil and not plan.submitted
        if countdown.ElementFrame.Visible then
            countdown:Set(math.clamp((os.clock() - plan.started) / math.max(0.01, plan.due - plan.started), 0, 1))
        end
        local autoText = app.auto.status == "autoPlayed" and app:t("autoPlayed", app.auto.lastMove or "") or app:t(app.auto.status)
        autoStatus.ElementFrame.Visible = (app.auto.enabled or app.auto.status ~= "autoPaused")
            and app.auto.status ~= "openGame" and app.auto.status ~= "openMatch"
        local autoDesc = ""
        local autoKey = autoText .. autoDesc
        if lastAuto ~= autoKey then autoStatus:SetTitle(autoText); autoStatus:SetDesc(autoDesc); lastAuto = autoKey end
        queueStatus.ElementFrame.Visible = app.queue.enabled
        if app.queue.enabled then
            local text = app.queue.status == "queueWaiting" and app:t("queueWaiting", math.max(0, (app.queue.due or os.clock()) - os.clock()))
                or app:t(app.queue.status)
            local detail = app.queue.mode or ""
            if lastQueue ~= text .. detail then
                queueStatus:SetTitle(text); queueStatus:SetDesc(detail); lastQueue = text .. detail
            end
        end
        if lastStrength ~= app.config.strength then
            eloControl.ElementFrame.Visible = app.config.strength == "elo"
            lastStrength = app.config.strength
        end
    end
    return view
end

return Interface
