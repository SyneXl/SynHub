-- By SyneX
local M={time=0,focused=nil,submissions={},writes={},ui={}}
local function signal()
    local s={connections={}}
    function s:Connect(callback)
        local c={Function=callback,Connected=true}
        function c:Disconnect() self.Connected=false end
        table.insert(self.connections,c)
        return c
    end
    function s:Fire(...)
        for _,c in ipairs(self.connections) do if c.Connected then c.Function(...) end end
    end
    return s
end
local function node(values)
    values=values or {}
    function values:FindFirstChild(name) return self[name] end
    function values:IsA(kind) return self.ClassName==kind end
    return values
end
local box=node({ClassName="TextBox",Text="",FocusLost=signal(),attributes={}})
function box:GetAttribute(name) return self.attributes[name] end
function box:SetAttribute(name,value) self.attributes[name]=value end
local match=node({TypingCapture=box});box.Parent=match
local playerGui=node({WordGameUI=node({Canvas=node({Match=match})})})
local state={kind="match",phase="playing",tableId=1,generation=1,round=1,turn=1,you=1,
    letter="а",deadline=10000,history={},lastWord="",choices={},chooser=1}
local function submitWord(_method)
    local requestId=(box:GetAttribute("AnalyticsSubmit") or 0)+1
    box:SetAttribute("AnalyticsSubmit",requestId)
    table.insert(M.submissions,{word=state.letter..box.Text,requestId=requestId})
end
local focusCallback=function() end
box.FocusLost:Connect(focusCallback)
local heartbeat=signal()
local remote=signal()
local services={
    Players={LocalPlayer=node({PlayerGui=playerGui,Name="Test",DisplayName="Test"})},
    ReplicatedStorage=node({WordGame=node({State={OnClientEvent=remote}})}),
    RunService={Heartbeat=heartbeat},
    UserInputService={InputBegan=signal(),GetFocusedTextBox=function() return M.focused end},
    HttpService={JSONEncode=function() return "{}" end,JSONDecode=function() return {} end},
}
local function element(config)
    if M.failInterface then error("Interface failed during creation") end
    local e={config=config,UIElements={Main={Visible=true}},ElementFrame={Visible=true}}
    function e:SetTitle(value) self.title=value end
    function e:SetDesc(value) self.description=value end
    function e:Set(value) if config.Callback then config.Callback(value) end end
    function e:Lock() self.locked=true end
    function e:Unlock() self.locked=false end
    e.ButtonFrame={UIElements={Main={Visible=true}}}
    e.InputFrame={UIElements={Main={}}}
    return e
end
local function tab()
    local t={ElementFrame={Visible=true}}
    function t:Button(config) local e=element(config);table.insert(M.ui,e);return e end
    function t:Paragraph(config) return {ParagraphFrame=element(config)} end
    function t:Input(config) local e=element(config);return e end
    function t:Toggle(config) return element(config) end
    function t:Slider(config) return element(config) end
    function t:Section(_config) return tab() end
    function t:Group(_config) return tab() end
    return t
end
local library={ScreenGui={},DropdownGui={},TooltipGui={},NotificationGui={}}
function library:SetParent(_parent) end
function library:CreateWindow(_config)
    local w={destroyed=false}
    function w:Tab(_options) return tab() end
    function w:SetToggleKey(_key) end
    function w:OnDestroy(callback) self.onDestroy=callback end
    function w:SelectTab(index) self.selected=index end
    function w:Destroy()
        if self.destroyed then return end
        self.destroyed=true
        if self.onDestroy then self.onDestroy() end
    end
    return w
end
local env=table.clone(getfenv())
env._G=env
env.__mockLibrary=library
env.game={PlaceId=71106427459865,GetService=function(_,name) return services[name] end,
    HttpGet=function() return "return getgenv().__mockLibrary" end}
env.workspace={GetServerTimeNow=function() return M.time end}
env.Enum={KeyCode={F8="F8",Escape="Escape",RightControl="RightControl"}}
env.UDim2={new=function(...) return {...} end,fromOffset=function(...) return {...} end}
env.Vector2={new=function(...) return {...} end}
env.getgenv=function() return env end
env.getfenv=function() return env end
env.setthreadidentity=function() end
env.getconnections=function(s) return s.connections end
env.readfile=function(path)
    if path:find("%.lua$") then return "return getgenv().__mockLibrary" end
    error("File absent in clean test environment")
end
env.writefile=function(path,text) table.insert(M.writes,{path=path,text=text}) end
env.warn=function(...) table.insert(M.warnings, table.concat({...}," ")) end
env.os=table.clone(os);env.os.clock=function() return M.time end
env.debug=table.clone(debug)
env.debug.info=function(f,what)
    if f==submitWord and what=="n" then return "submitWord" end
    return debug.info(f,what)
end
env.debug.getupvalues=function(f) return f==focusCallback and {submitWord} or {} end
env.debug.getupvalue=function(f,index)
    if f~=submitWord then return nil end
    if index==1 then return box elseif index==2 then return state elseif index==3 then return 0 elseif index==4 then return false end
end
env.loadstring=function(source,name)
    local chunk,err=loadstring(source,name)
    if chunk then setfenv(chunk,env) end
    return chunk,err
end

M.env,M.box,M.state=env,box,state
M.services,M.heartbeat,M.remote=services,heartbeat,remote
M.warnings,M.files,M.json,M.requests,M.failures={},{},{},{},{}
local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end
services.HttpService.JSONEncode=function(_,value)
    local key="json:"..tostring(#M.json+1)
    M.json[key]=copy(value)
    table.insert(M.json,key)
    return key
end
services.HttpService.JSONDecode=function(_,text)
    if text==M.manifestText then return copy(M.manifest) end
    return copy(assert(M.json[text],"Invalid JSON"))
end
env.readfile=function(path) return assert(M.files[path],"File missing") end
env.writefile=function(path,text)
    if M.failSave then error("Disk unavailable") end
    M.files[path]=text
    table.insert(M.writes,{path=path,text=text})
end
env.isfolder=function() return true end
env.makefolder=function() end
env.task={wait=function(duration) M.time+=duration;return duration end}
env.game.HttpGet=function(_,url)
    local prefix="https://raw.githubusercontent.com/SyneXl/SynHub/main/"
    assert(url:sub(1,#prefix)==prefix,"Unexpected host")
    local path=url:sub(#prefix+1)
    M.requests[path]=(M.requests[path] or 0)+1
    if (M.failures[path] or 0)>0 then
        M.failures[path]-=1
        error("Network unavailable")
    end
    return assert(M.http[path],"Unknown asset: "..path)
end
function M:advance(phase)
    local app=self.env.__SynHub.app
    for _=1,3000 do
        if app.bot.phase==phase then return end
        self.time+=0.01
        heartbeat:Fire(0.01)
    end
    error("Phase was not reached: "..phase.."; actual="..app.bot.phase)
end
function M:connections()
    local count=0
    for _,event in ipairs({heartbeat,remote,services.UserInputService.InputBegan}) do
        for _,connection in ipairs(event.connections) do
            if connection.Connected then count+=1 end
        end
    end
    return count
end
return M
