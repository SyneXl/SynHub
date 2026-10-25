-- By SyneX
local Resume = {}
local flag = "SynHub/rochess/resume.txt"
local source = [[
if not game:IsLoaded() then game.Loaded:Wait() end
if game.GameId ~= 10768845402 then return end
local env = getgenv()
if env.__SynHubResumeRunning or env.__SynHub and env.__SynHub.app and env.__SynHub.app.alive then return end
local ok, active = pcall(readfile, "SynHub/rochess/resume.txt")
if not ok or active ~= "on" then return end
env.__SynHubResumeRunning = true
if not game:GetService("ReplicatedStorage"):WaitForChild("ChessClient", 30) then
    env.__SynHubResumeRunning = nil
    return
end
for attempt = 1, 3 do
    local loaded, err = pcall(function()
        return assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/SyneXl/SynHub/refs/tags/bootstrap-v1/loader.luau", false)))()
    end)
    if loaded and env.__SynHub and env.__SynHub.app and env.__SynHub.app.alive then break end
    if attempt == 3 then warn("[SynHub] Could not resume after teleport: " .. tostring(err))
    else task.wait(attempt * 2) end
end
env.__SynHubResumeRunning = nil
]]

function Resume.start(app, context)
    local api = context.api
    if type(api.readfile) ~= "function" or type(api.writefile) ~= "function" then return end
    local function activate(value) return pcall(api.writefile, flag, value and "on" or "off") end
    app:save()
    if not activate(true) then return end
    app.scope:add(function() activate(false) end)
    local queued = context.env.__SynHubChessResumeJob
    if type(api.queue_on_teleport) == "function" and queued ~= game.JobId then
        local ok = pcall(api.queue_on_teleport, source)
        if ok then context.env.__SynHubChessResumeJob = game.JobId end
    end
    local player = game:GetService("Players").LocalPlayer
    app.scope:add(player.OnTeleport:Connect(function(state)
        if not app.alive then return end
        app:identity()
        app:invalidate()
        if state == Enum.TeleportState.Failed then
            app.teleporting = false
        else
            app.teleporting = true
            app:save()
        end
    end))
end

return Resume
