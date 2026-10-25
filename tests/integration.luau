-- By SyneX
local passed, failed = 0, 0
local function test(name, callback)
    local ok, err = pcall(callback)
    if ok then passed += 1 else failed += 1; print("FAIL", name, err) end
end

test("Complete game session through public loader", function()
    local mock = newMock()
    local app = mock:load()
    assert(app.alive and not app.bot.enabled and app.window.selected == 1)
    local count = 0
    for _, list in pairs(app.bot.index) do count += #list end
    assert(count == 39920)
    assert(mock:connections() == 3)
    local candidates, total = app.bot:candidates("а", "", 0, 10)
    assert(#candidates == 10 and total > 10)
    app.speed:Set(180)
    assert(app.config.wpm == 180)
    app.setEnabled(true)
    mock:advance("result")
    assert(#mock.submissions == 1)
    local first = mock.submissions[1].word
    mock.remote:Fire({kind = "wordRejected", requestId = 1, text = "Отклонено"})
    mock:advance("result")
    assert(app.bot.enabled and #mock.submissions == 2 and mock.submissions[2].word ~= first)
    mock.remote:Fire({kind = "accepted", word = mock.submissions[2].word, tableId = 1, generation = 1, round = 1})
    assert(app.bot.metrics.accepted == 1 and app.bot.metrics.rejected == 1)
    mock.focused = {}
    assert(app.driver.read().blocked)
    app:Destroy()
    assert(not app.alive and mock:connections() == 0 and mock.env.__SynHub.app == nil)
    assert(mock.files["SynHub/slova/state.json"] and #mock.warnings == 0)
end)

test("Reload cancels old input and disconnects old listeners", function()
    local mock = newMock()
    local first = mock:load()
    first.setEnabled(true)
    mock:advance("typing")
    local second = mock:load()
    assert(second ~= first and not first.alive and not first.bot.pending)
    assert(second.alive and not second.bot.enabled and mock:connections() == 3)
    local submissions = #mock.submissions
    for _ = 1, 200 do mock.heartbeat:Fire(0.01) end
    assert(#mock.submissions == submissions)
    mock.services.UserInputService.InputBegan:Fire({KeyCode = "F8"})
    assert(second.bot.enabled)
    second:Destroy()
    assert(mock:connections() == 0)
end)

test("Download failure keeps the current session alive", function()
    local mock = newMock()
    local app = mock:load()
    mock.failures["manifest.json"] = 3
    local ok = pcall(function() mock:load() end)
    assert(not ok and app.alive and mock.env.__SynHub.app == app)
    assert(not mock.env.__SynHub.loading and mock:connections() == 3)
    assert(mock.requests["manifest.json"] == 4)
    app:Destroy()
end)

test("Transient download error retries successfully", function()
    local mock = newMock()
    mock.failures["manifest.json"] = 2
    local app = mock:load()
    assert(mock.requests["manifest.json"] == 3 and app.alive)
    app:Destroy()
end)

test("Incomplete assets fail before replacing a running session", function()
    local mock = newMock()
    local app = mock:load()
    local gameEntry = mock.manifest.games[1]
    mock.env.__SynHub.assets = {}
    mock.http[gameEntry.assets.dictionary.path] = "incomplete"
    local ok = pcall(function() mock:load() end)
    assert(not ok and app.alive and mock:connections() == 3)
    app:Destroy()
end)

test("Legacy settings migrate and survive the next reload", function()
    local mock = newMock()
    mock.files["Slova/state.json"] = mock.services.HttpService:JSONEncode({
        config = {wpm = 190, natural = false, enter = false, ending = "Р"},
        history = {"автор"}, rejected = {"арбуз"},
    })
    local app = mock:load()
    assert(app.config.wpm == 190 and not app.config.natural and not app.config.enter and app.config.ending == "р")
    assert(app.bot.used["автор"] and app.bot.rejected["арбуз"])
    app.speed:Set(230)
    app:Destroy()
    local nextApp = mock:load()
    assert(nextApp.config.wpm == 230 and nextApp.bot.used["автор"])
    nextApp:Destroy()
end)

test("Invalid saved input cannot break startup", function()
    local mock = newMock()
    mock.files["SynHub/slova/state.json"] = mock.services.HttpService:JSONEncode({
        config = {wpm = 0/0, ending = string.char(255)}, history = {string.char(255), false},
    })
    local app = mock:load()
    assert(app.config.wpm == 85 and app.config.ending == "" and app.alive)
    app:Destroy()
end)

test("Failed interface startup removes partial UI and preserves saved data", function()
    local mock = newMock()
    local state = mock.services.HttpService:JSONEncode({config = {wpm = 170}})
    mock.files["SynHub/slova/state.json"] = state
    mock.failInterface = true
    assert(not pcall(function() mock:load() end))
    assert(mock:connections() == 0 and mock.files["SynHub/slova/state.json"] == state)
    assert(not mock.env.__SynHub.loading)
    mock.failInterface = false
    local app = mock:load()
    assert(app.config.wpm == 170)
    app:Destroy()
end)

test("Missing match interface reconnects without relaunching", function()
    local mock = newMock()
    local playerGui = mock.services.Players.LocalPlayer.PlayerGui
    local gui = playerGui.WordGameUI
    playerGui.WordGameUI = nil
    local app = mock:load()
    assert(app.alive and app.bot.snapshot == nil)
    playerGui.WordGameUI = gui
    mock.time = 1
    mock.heartbeat:Fire(0.01)
    assert(app.bot.snapshot and app.bot.snapshot.letter == "а")
    app:Destroy()
end)

test("Unavailable storage still allows unloading cleanly", function()
    local mock = newMock()
    mock.failSave = true
    local app = mock:load()
    app:Destroy()
    assert(not app.alive and mock:connections() == 0 and #mock.warnings == 1)
end)

test("Unsupported place and concurrent loading create no listeners", function()
    local mock = newMock()
    mock.env.game.PlaceId = 1
    assert(not pcall(function() mock:load() end))
    assert(mock:connections() == 0 and not mock.env.__SynHub.loading)
    mock.env.__SynHub.loading = true
    assert(mock:load() == nil and mock:connections() == 0)
end)

test("Cached assets avoid downloading the dictionary and interface again", function()
    local mock = newMock()
    local app = mock:load()
    local assets = mock.manifest.games[1].assets
    app:Destroy()
    mock:load():Destroy()
    assert(mock.requests[assets.dictionary.path] == 1 and mock.requests[assets.interface.path] == 1)
end)

print("INTEGRATION", passed, failed)
assert(failed == 0, "Integration tests failed")
