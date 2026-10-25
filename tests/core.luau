-- Loaded with core.luau prepended by the test runner; never touches live game input.
local results = {}
local function test(name, callback)
    local ok, err = pcall(callback)
    table.insert(results,{name=name,passed=ok,error=not ok and tostring(err) or nil})
end
local function fixture(words)
    local s={key="1:1:1:1",matchId="1:1",tableId=1,generation=1,round=1,you=1,letter="а",
        own=true,ready=true,text="",left=30,history={}}
    local config={wpm=120,natural=false,enter=true,ending=""}
    local writes,submits={},0
    local d={read=function() return s end,write=function(text) s.text=text;table.insert(writes,text) end,
        submit=function() submits+=1;return submits end}
    local bot=Core.new(words or {"арбуз","автор","актер"},config,d,nil,function() return 0.5 end)
    bot:tick(0)
    local function untilPhase(phase,limit)
        for i=1,limit or 3000 do
            if bot.phase==phase then return i/100 end
            bot:tick(0.01)
        end
        error("phase not reached: "..phase.."; current="..bot.phase)
    end
    return bot,s,config,writes,untilPhase,function() return submits end
end
test("Cyrillic normalization and UTF-8 suffix",function()
    assert(Core.canonical(" ЁЖИК ")=="ежик")
    local c=Core.chars("яблоко");assert(table.concat(c,"",2)=="блоко")
end)
test("Masked history is not treated as a Russian word",function()
    local b=fixture();b:remember("#####");assert(#b.history==0)
end)
test("Frequency order, ending and exclusion",function()
    local b=fixture();b.used["автор"]=true
    local r,n=b:candidates("А","Р",0,10);assert(n==1 and r[1].word=="актер")
end)
test("Only suffix typed and submission once",function()
    local b,s,_,w,wait,submits=fixture();b:setEnabled(true);wait("result")
    assert(s.text=="рбуз" and submits()==1 and w[1]=="")
    assert(w[2]=="р" and w[3]=="рб")
end)
test("WPM meaningfully changes duration",function()
    local b,_,c,_,wait=fixture();c.wpm=30;b:setEnabled(true);wait("typing");local slow=wait("settle")
    local f,_,cfg,_,waitFast=fixture();cfg.wpm=180;f:setEnabled(true);waitFast("typing");local fast=waitFast("settle")
    assert(slow>fast*5.5,slow.." vs "..fast)
end)
test("WPM changes while current word is typing",function()
    local b,_,c,_,wait=fixture();c.wpm=30;b:setEnabled(true);wait("typing")
    for _=1,10 do b:tick(.01) end
    c.wpm=300;assert(wait("settle")<.5)
end)
test("Rejection clears and submits next word without stopping",function()
    local b,s,_,w,wait,submits=fixture();b:setEnabled(true);wait("result")
    b:onResponse({kind="wordRejected",requestId=1,text="Не подходит"})
    b:onResponse({kind="invalid",actor=1,tableId=1,generation=1,round=1})
    assert(b.metrics.rejected==1 and b.enabled)
    wait("result");assert(s.text=="втор" and submits()==2 and b.rejected["арбуз"])
    local clears=0;for _,v in ipairs(w) do if v=="" then clears+=1 end end;assert(clears>=2)
end)
test("Invalid event also triggers replacement",function()
    local b,s,_,_,wait=fixture();b:setEnabled(true);wait("result")
    b:onResponse({kind="invalid",actor=1,tableId=1,generation=1,round=1,reason="used"})
    wait("result");assert(s.text=="втор" and b.used["арбуз"] and b.enabled)
end)
test("Old request and opponent rejection ignored",function()
    local b,_,_,_,wait=fixture();b:setEnabled(true);wait("result")
    b:onResponse({kind="wordRejected",requestId=999})
    b:onResponse({kind="invalid",actor=2,tableId=1,generation=1,round=1})
    assert(b.phase=="result" and b.metrics.rejected==0)
end)
test("Acceptance recorded only from matching response",function()
    local b,_,_,_,wait=fixture();b:setEnabled(true);wait("result")
    b:onResponse({kind="accepted",word="арбуз",tableId=1,generation=0,round=1});assert(not b.used["арбуз"])
    b:onResponse({kind="accepted",word="АРБУЗ",tableId=1,generation=1,round=1})
    assert(b.phase=="done" and b.metrics.accepted==1 and b.used["арбуз"])
end)
test("Turn change aborts suffix without disabling bot",function()
    local b,s,_,w,wait=fixture();b:setEnabled(true);wait("typing");b:tick(.1)
    local n=#w;s.key="next";s.own=false
    for _=1,100 do b:tick(.01) end
    assert(#w==n and b.enabled and not b.pending)
end)
test("Focused menu or chat pauses typing",function()
    local b,s,_,w,wait=fixture();b:setEnabled(true);wait("typing")
    s.ready=false;s.blocked=true;local n=#w
    for _=1,100 do b:tick(.01) end
    assert(#w==n);s.ready=true;s.blocked=false;wait("result")
end)
test("Manual selection respects Enter toggle",function()
    local b,s,c,_,wait,submits=fixture();c.enter=false;assert(b:request("арбуз"));wait("done")
    assert(s.text=="рбуз" and submits()==0 and b.used["арбуз"])
end)
test("Network timeout remains armed for next turn",function()
    local b,_,_,_,wait,submits=fixture();b:setEnabled(true);wait("result");wait("done")
    assert(submits()==2 and b.enabled)
end)
test("Esc cancellation leaves no scheduled keystrokes",function()
    local b,_,_,w,wait=fixture();b:setEnabled(true);wait("typing");b:setEnabled(false);local n=#w
    for _=1,100 do b:tick(.01) end
    assert(#w==n and not b.pending)
end)
local failures=0
for _,r in ipairs(results) do if not r.passed then failures+=1 end end
return {tests=results,passed=#results-failures,failed=failures}
