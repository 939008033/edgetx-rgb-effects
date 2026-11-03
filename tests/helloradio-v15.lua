-- Run: fengari tests/helloradio-v15.lua <repository-root> [--layouts]
-- Host mocks are not hardware/firmware tests. No model APIs are provided.
local root=assert(arg[1],"Pass repository root")
local loadFile=loadfile
local hostIO=io
local files,leds={},{}
local now,stick,output=0,-1024,-1024
local writes,commits,reads=0,0,0
local denied={}
local noWrite,writeError,readError=false,false,false
local lastChannel
local refreshCfs
LED_STRIP_LENGTH=38
LCD_W,LCD_H=480,272
function getTime() return now end
function getValue(id) assert(id=="thr"); return stick end
function getOutputValue(id) lastChannel=id; return output end
function setRGBLedColor(id,r,g,b)
  assert(id>=0 and id<LED_STRIP_LENGTH and id==math.floor(id),"Invalid LED")
  for _,v in ipairs({r,g,b}) do assert(v==math.floor(v) and v>=0 and v<=255) end
  writes=writes+1
  if denied[id] then return false end
  leds[id]={r,g,b}; return true
end
function applyRGBLedColors() commits=commits+1; if refreshCfs then refreshCfs() end end
function loadScript(path,mode)
  assert(mode=="tx","Helpers must bypass old binary cache")
  return loadFile(root.."/HelloRadio-V15"..path)
end
io={
  open=function(p,m)
    if m=="r" and not files[p] then return nil end
    if m=="w" then if noWrite then return nil end; files[p]="" end
    return {path=p,mode=m}
  end,
  read=function(f,n)
    reads=reads+1
    if readError then error("SD read failed") end
    return string.sub(files[f.path],1,n)
  end,
  write=function(f,t) if writeError then return nil,"failure" end; files[f.path]=t end,
  close=function() end,
}
local function script(p) return assert(loadFile(root.."/"..p))() end
local core=script("HelloRadio-V15/SCRIPTS/RGBLED/v15lib/effects.lua")
local function fresh()
  denied={}; leds={}; now=0; setCFSLedColor=nil; refreshCfs=nil
  local c=core.defaults(); c.bottomA=9; c.bottomB=23; c.cwA=1; c.cwB=0; c.ready=1
  local w=core.writer(); w.probeKeys()
  return c,w
end
local function lit(id) local p=leds[id]; return p and p[1]+p[2]+p[3]>0 end
local function count(a,b)
  local n=0
  for id=a or 0,b or 31 do if lit(id) then n=n+1 end end
  return n
end
local function snapshot()
  local all={}
  for id=0,37 do
    local p=leds[id] or {0,0,0}; all[#all+1]=table.concat(p,",")
  end
  return table.concat(all,";")
end
local checks=0
local function test(name,fn)
  local ok,err=pcall(fn)
  assert(ok,name..": "..tostring(err))
  checks=checks+1; print("PASS "..name)
end

test("legacy config keeps existing values but requires direction calibration",function()
  files[core.path]="V15THR1\nbottomA=9\nbottomB=23\nsource=3\nreverse=1\nbrightness=60\n"
  local c,kind=core.load()
  assert(c and kind=="legacy" and c.ready==0)
  assert(c.bottomA==9 and c.bottomB==23 and c.source==3 and c.reverse==1 and c.brightness==60)
  assert(not core.save(c))
end)
test("missing truncated or future calibration is rejected",function()
  for _,text in ipairs({"","V15THR1\nbottomA=9\n","V15THR5\nbottomA=9\n","V15THR99\n"}) do
    files[core.path]=text; assert(core.load()==nil)
  end
end)
test("v5 round trip covers all settings and invalid fields",function()
  local c=fresh(); c.source=32; c.reverse=1; c.smooth=20; c.palette=8; c.pattern=5; c.angle=4
  assert(core.save(c))
  local d=assert(core.load())
  for k,v in pairs(c) do assert(d[k]==v,k) end
  for k,v in pairs(c) do c[k]=-1; assert(not core.valid(c),k); c[k]=v end
end)
test("SD open write read failures cannot report successful save",function()
  local c=fresh()
  noWrite=true; assert(not core.save(c)); noWrite=false
  writeError=true; assert(not core.save(c)); writeError=false
  readError=true; assert(not core.save(c)); assert(core.load()==nil); readError=false
  assert(core.save(c))
end)
test("six keys fill 3/4 then 2/5 then 1/6 before either ring",function()
  local c,w=fresh()
  for step,expected in ipairs({{34,35},{33,34,35,36},{32,33,34,35,36,37}}) do
    core.render(w,c,step/19)
    assert(count()==0 and count(32,37)==step*2)
    for _,id in ipairs(expected) do assert(lit(id)) end
  end
  core.render(w,c,3.5/19)
  assert(count()==2 and count(32,37)==6)
end)
test("zero/full and invalid values stay bounded",function()
  local c,w=fresh()
  for _,p in ipairs({0,-1,0/0}) do core.render(w,c,p); assert(count(0,37)==0) end
  core.render(w,c,nil); assert(count(0,37)==0)
  core.render(w,c,2); assert(count(0,37)==38)
end)
test("calibrated directions, sides and angle offsets follow physical clockwise",function()
  local c=fresh()
  -- Group A clockwise increments, B clockwise decrements.
  assert(core.ringId(c,0,0,1,1)==8) -- left ~5:15
  assert(core.ringId(c,0,1,1,1)==9) -- clockwise toward six
  assert(core.ringId(c,1,0,1,1)==22) -- right ~6:45
  assert(core.ringId(c,1,1,1,1)==23) -- counterclockwise toward six
  c.left=1
  assert(core.ringId(c,0,0,1,1)==10)
  assert(core.ringId(c,0,1,1,1)==9)
  assert(core.ringId(c,1,0,1,1)==24)
  assert(core.ringId(c,1,1,1,1)==23)
  assert(core.ringId(c,0,0,1,3)==1)
end)
test("every pattern angle side sign maps every ring LED exactly once",function()
  local c=fresh()
  for left=0,1 do for a=0,1 do for b=0,1 do
    c.left,c.cwA,c.cwB=left,a,b
    for pattern=1,5 do for angle=1,4 do for group=0,1 do
      local seen={}
      for k=0,15 do
        local id=core.ringId(c,group,k,pattern,angle)
        assert(id>=group*16 and id<group*16+16 and not seen[id])
        seen[id]=true
      end
    end end end
  end end end
end)
test("spatial gradient stays stable; no time based rainbow rotation",function()
  local c,w=fresh(); c.keys=0; c.palette=1
  core.render(w,c,0.5); local expected=snapshot(); local n=writes
  for t=1,100 do now=t*5; core.render(w,c,0.5); assert(snapshot()==expected) end
  assert(writes==n,"Steady progress should not rewrite LEDs")
  local first=leds[core.ringId(c,0,0,c.pattern,c.angle)]
  local last=leds[core.ringId(c,0,7,c.pattern,c.angle)]
  assert(table.concat(first,",")~=table.concat(last,","))
end)
test("pure blue never emits any red, including partially lit leading LEDs",function()
  local c,w=fresh(); c.palette=6
  for step=0,200 do
    core.render(w,c,step/200)
    for id=0,37 do assert(leds[id][1]==0) end
  end
end)
test("all palettes increase monotonically per LED over a throttle sweep",function()
  for palette=1,8 do
    local c,w=fresh(); c.palette=palette
    local previous={}
    for step=0,100 do
      core.render(w,c,step/100)
      for id=0,37 do for ch=1,3 do
        local index=id*3+ch; assert(leds[id][ch]>=(previous[index] or 0)); previous[index]=leds[id][ch]
      end end
    end
  end
end)
test("symmetric expansion fades each pair equally",function()
  local c,w=fresh(); c.pattern=3; c.angle=2; c.palette=6; c.keys=0
  for k=0,40 do
    core.render(w,c,k/40)
    for group=0,1 do for step=1,13,2 do
      local a=core.ringId(c,group,step,3,2)
      local b=core.ringId(c,group,step+1,3,2)
      assert(table.concat(leds[a],",")==table.concat(leds[b],","))
    end end
  end
end)
test("denied key LEDs are preserved and whole range falls back to rings",function()
  local c=fresh()
  denied[32]=true; leds[32]={12,34,56}
  local w=core.writer(); w.probeKeys(); assert(w.keyCount==5)
  core.render(w,c,0.03); assert(count()==2 and count(33,37)==0)
  assert(table.concat(leds[32],",")=="12,34,56")
end)
test("32 LED firmware and explicit key disabling work",function()
  local c=fresh(); LED_STRIP_LENGTH=32
  local w=core.writer(); w.probeKeys(); assert(w.keyCount==0)
  core.render(w,c,1); assert(count()==32)
  LED_STRIP_LENGTH=38
  c,w=fresh(); c.keys=0; core.render(w,c,0.1); assert(count()>0 and count(32,37)==0)
end)
test("input sources use zero based output channels without changing them",function()
  local c=fresh(); stick=-1024; output=1024
  assert(core.progress(c)==0); c.source=3; assert(core.progress(c)==1 and lastChannel==2)
  c.reverse=1; assert(core.progress(c)==0)
  output=nil; assert(core.progress(c)==nil)
  output=0/0; assert(core.progress(c)==nil)
  output=1024
end)
test("time based smoothing suppresses ADC jitter and promptly goes dark",function()
  local s=core.smoother()
  assert(s.update(0.5,0,8)==0.5)
  for t=1,50 do assert(s.update(0.5+(t%2==0 and 0.001 or -0.001),t*5,8)==0.5) end
  local v=s.update(1,255,8); assert(v>0.5 and v<1)
  for t=260,400,5 do v=s.update(1,t,8) end
  assert(v==1); assert(s.update(0,405,8)==0)
end)
test("smoothing handles first frame time wrap pauses and disabled setting",function()
  local s=core.smoother()
  assert(s.update(0.7,100,8)==0.7)
  assert(s.update(0.3,50,8)==0.3)
  assert(s.update(0.8,200,8)==0.8)
  assert(s.update(0.2,205,0)==0.2)
  assert(s.update(nil,210,8)==0)
end)
local presetNames={"B01-user","B02-rain","B03-ice","B04-fire","B05-pink","B06-mint","B07-blue","B08-purp","B09-gold","B10-rev","B11-both","B12-top","B13-cw","B14-ccw"}
test("all 14 entry files load and render without touching any model API",function()
  for _,name in ipairs(presetNames) do
    local c=fresh(); assert(core.save(c)); stick=1024; now=0
    local runtime=script("HelloRadio-V15/SCRIPTS/RGBLED/"..name..".lua")
    runtime.init(); runtime.run(); assert(count(0,37)==38,name)
  end
end)
test("runtime updates at 20 Hz and avoids SD reads while continuously active",function()
  local c=fresh(); c.smooth=0; assert(core.save(c)); stick=-1024; now=0
  local runtime=script("HelloRadio-V15/SCRIPTS/RGBLED/B01-user.lua")
  runtime.init(); runtime.run(); local beforeReads=reads; local beforeWrites=writes
  stick=1024; now=4; runtime.run(); assert(writes==beforeWrites)
  now=5; runtime.run(); assert(count(0,37)==38)
  for t=10,1000,5 do now=t; runtime.run() end
  assert(reads==beforeReads,"No periodic SD I/O in rendering loop")
end)
test("inactive presets do not clear active LEDs or repeatedly read SD",function()
  local c=fresh(); assert(core.save(c)); stick=1024; now=0
  local runtime=script("HelloRadio-V15/SCRIPTS/RGBLED/B02-rain.lua")
  runtime.init(); runtime.run()
  local beforeWrites,beforeReads=writes,reads
  for i=1,100 do runtime.background() end
  assert(writes==beforeWrites and reads==beforeReads)
  c.keys=0; c.palette=8; assert(core.save(c))
  now=10; runtime.run(); assert(count(32,37)==0 and count()==32)
end)
test("legacy uncalibrated state never silently runs guessed direction",function()
  files[core.path]="V15THR1\nbottomA=9\nbottomB=23\nsource=0\nreverse=0\nbrightness=40\n"
  local rt=script("HelloRadio-V15/SCRIPTS/RGBLED/B01-user.lua"); rt.init(); stick=1024; rt.run()
  assert(count(0,37)==0)
end)

local ui,closePage,title={},nil,""
lvgl={PAGE_BODY_HEIGHT=232,clear=function() ui={} end}
function lvgl.page(p)
  title,closePage=p.title,p.back
  local pg={}
  for _,kind in ipairs({"label","button","choice"}) do
    pg[kind]=function(_,v)
      local allowed={x=true,y=true,w=true,h=true}
      if kind=="choice" then allowed.title=true; allowed.values=true; allowed.get=true; allowed.set=true
      else allowed.font=true; allowed.text=true; if kind=="button" then allowed.press=true end end
      for k in pairs(v) do assert(allowed[k],kind..": invalid property "..k) end
      v.kind=kind; ui[#ui+1]=v; return v
    end
  end
  return pg
end
local function textOf(p) return type(p.text)=="function" and p.text() or p.text end
local function click(text)
  for _,p in ipairs(ui) do if p.kind=="button" and textOf(p)==text then p.press(); return end end
  error("Missing button "..text)
end
local function choose(name,i)
  for _,p in ipairs(ui) do if p.kind=="choice" and p.title==name then
    assert(i>=1 and i<=#p.values); p.set(i); return
  end end
  error("Missing choice "..name)
end
local function openTool()
  local t=script("HelloRadio-V15/SCRIPTS/TOOLS/v15map.lua"); t.init(); t.run(); return t
end
local function finish(t)
  click("确定灯位"); t.run(); click("方向正确"); t.run()
  click("确定灯位"); t.run(); click("方向正确"); t.run()
end
local captures={}
local function layout()
  local body=math.min(LCD_H-60,lvgl.PAGE_BODY_HEIGHT or LCD_H-60)
  local capture={width=LCD_W,height=LCD_H,body=body,title=title,widgets={}}
  for i,p in ipairs(ui) do
    assert(p.x>=0 and p.y>=0 and p.h>=32 and p.w>0)
    assert(p.x+p.w<=LCD_W and p.y+p.h<=body,"Outside screen")
    local text=p.kind=="choice" and p.values[p.get()] or textOf(p)
    assert(utf8.len(text),"Invalid UTF8")
    local width=p.kind=="label" and 0 or 24
    for _,code in utf8.codes(text) do width=width+(code<128 and 12 or 24) end
    assert(width<=p.w,"Caption overflow: "..text)
    for j=1,i-1 do local q=ui[j]
      assert(p.x>=q.x+q.w or q.x>=p.x+p.w or p.y>=q.y+q.h or q.y>=p.y+p.h,"Overlap")
    end
    capture.widgets[#capture.widgets+1]={kind=p.kind,x=p.x,y=p.y,w=p.w,h=p.h,text=text}
  end
  captures[#captures+1]=capture
end
test("Chinese four step calibration saves physical side and clockwise mapping",function()
  fresh(); files[core.path]=nil
  local t=openTool(); assert(count()==1)
  click("下一个"); choose("所在侧",2); click("确定灯位"); t.run()
  click("反转"); click("方向正确"); t.run()
  click("下一个"); click("确定灯位"); t.run()
  click("方向正确"); t.run()
  click("配色"); t.run(); choose("配色",8); choose("走向",5); choose("起点",4)
  click("返回"); t.run(); click("设置"); t.run()
  choose("来源",4); choose("油门",2); choose("平滑",4); choose("亮度",4)
  click("返回"); t.run(); click("保存")
  local c=assert(core.load())
  assert(c.ready==1 and c.bottomA==1 and c.bottomB==17 and c.left==1 and c.cwA==0)
  assert(c.palette==8 and c.pattern==5 and c.angle==4 and c.source==3 and c.reverse==1 and c.brightness==80 and c.smooth==12)
  closePage(); assert(t.run()==2)
end)
for _,size in ipairs({{480,272},{480,320},{800,480}}) do
  test("all UI pages fit "..size[1].."x"..size[2],function()
    fresh(); files[core.path]=nil; LCD_W,LCD_H=size[1],size[2]; lvgl.PAGE_BODY_HEIGHT=LCD_H-40
    local t=openTool(); layout()
    click("确定灯位"); t.run(); layout()
    click("方向正确"); t.run(); layout()
    click("确定灯位"); t.run(); layout()
    click("方向正确"); t.run(); layout()
    click("设置"); t.run(); choose("来源",33); choose("亮度",5); layout()
    click("返回"); t.run(); click("配色"); t.run(); choose("走向",5); layout()
    click("测键灯"); t.run(); layout()
    click("返回"); t.run(); click("测试"); t.run(); layout()
    click("全红"); t.run(); assert(count()==32); layout()
    click("返回"); t.run(); click("关于"); t.run(); layout()
    click("返回"); t.run(); click("保存"); layout()
    closePage(); assert(t.run()==2)
  end)
end
test("fallback layout and save failure status remain readable",function()
  LCD_W,LCD_H=480,272; lvgl.PAGE_BODY_HEIGHT=nil
  fresh(); files[core.path]=nil
  local t=openTool(); layout(); finish(t)
  noWrite=true; click("保存"); noWrite=false; layout()
  assert(textOf(ui[1])=="保存失败，请检查SD卡")
  closePage(); assert(t.run()==2)
  lvgl.PAGE_BODY_HEIGHT=232
end)
test("static diagnostics stay fixed and do not rewrite LEDs as time passes",function()
  local c=fresh(); assert(core.save(c)); local t=openTool()
  click("测试"); t.run(); click("半青"); t.run(); assert(count()==16)
  local n=writes; local snap=snapshot()
  for i=1,20 do stick=1024; now=i*5; t.run(); assert(snapshot()==snap) end
  assert(writes==n)
  click("全红"); t.run()
  for id=0,31 do assert(leds[id][1]==100 and leds[id][2]==0 and leds[id][3]==0) end
  click("全灭"); t.run(); assert(count(0,37)==0)
  closePage(); t.run(); closePage(); assert(t.run()==2)
end)
test("tool key tests expose blocked control without overwriting switch indicators",function()
  local c=fresh(); assert(core.save(c)); denied[32]=true; leds[32]={12,34,56}
  local t=openTool()
  assert(textOf(ui[1])=="键灯受限：暂用灯环")
  click("测试"); t.run(); click("测键灯"); t.run(); assert(textOf(ui[1])=="接口响应 5/6")
  assert(table.concat(leds[32],",")=="12,34,56")
  click("下一键"); t.run(); assert(lit(33))
  click("返回"); t.run(); closePage(); assert(t.run()==2)
end)
test("recalibration and page changes do not save until requested",function()
  local c=fresh(); assert(core.save(c)); local saved=files[core.path]
  local t=openTool(); click("重校")
  assert(title=="V15灯光 v5.1 - 预览","Rebuild must be deferred")
  t.run(); click("下一个"); finish(t)
  assert(files[core.path]==saved)
  closePage(); assert(t.run()==2)
end)
test("missing helper and unsupported layout have Chinese error pages",function()
  local old=loadScript
  loadScript=function(path,mode)
    if string.find(path,"effects.lua",1,true) then return nil end
    return old(path,mode)
  end
  local t=openTool(); layout(); click("退出"); assert(t.run()==2); loadScript=old
  LED_STRIP_LENGTH=7; t=openTool(); layout(); click("退出"); assert(t.run()==2); LED_STRIP_LENGTH=38
end)
test("saved settings, full UI, every entry work without string metatable",function()
  local c=fresh(); assert(core.save(c))
  local meta=debug.getmetatable(""); debug.setmetatable("",nil)
  local ok,err=pcall(function()
    assert(core.load().bottomA==9)
    local t=openTool(); click("设置"); t.run(); choose("亮度",3)
    click("返回"); t.run(); click("配色"); t.run(); choose("配色",6)
    click("返回"); t.run(); click("保存"); assert(core.load().brightness==60)
    closePage(); assert(t.run()==2)
    t=openTool(); click("关于"); t.run(); layout(); click("返回"); t.run(); closePage(); assert(t.run()==2)
    for _,name in ipairs(presetNames) do
      local rt=script("HelloRadio-V15/SCRIPTS/RGBLED/"..name..".lua")
      rt.init(); stick=1024; now=0; rt.run(); assert(count()==32)
    end
  end)
  debug.setmetatable("",meta); assert(ok,err)
end)
-- Model the firmware's separate per-state permission gate. API acceptance
-- does NOT mean that either gate is enabled; firmware applies it on refresh.
local function cfsMock(assigned)
  local m={overrides={},on={},allowOn={},allowOff={},calls=0,cancels=0}
  for i=1,6 do
    denied[31+i]=assigned[i] or false
    m.on[i]=false; m.allowOn[i]=true; m.allowOff[i]=true
    leds[31+i]={0,0,0}
  end
  function setCFSLedColor(name,r,g,b)
    assert(type(name)=="string","CFS API needs a switch NAME, not numeric LED id")
    local i=tonumber(string.match(name,"^SW([1-6])$"))
    if not i then return false end
    if r==nil then m.overrides[i]=nil; m.cancels=m.cancels+1; return true end
    for _,v in ipairs({r,g,b}) do assert(type(v)=="number" and v>=0 and v<=255 and v==math.floor(v)) end
    m.calls=m.calls+1; m.overrides[i]={r,g,b}; return true
  end
  refreshCfs=function()
    for i=1,6 do
      if denied[31+i] then
        local allowed=(m.on[i] and m.allowOn[i]) or (not m.on[i] and m.allowOff[i])
        local p=m.overrides[i]
        if p and allowed then leds[31+i]={p[1],p[2],p[3]}
        else leds[31+i]=m.on[i] and {0,45,0} or {35,0,0} end
      end
    end
  end
  return m
end
local allAssigned={true,true,true,true,true,true}
test("screenshot mixed SW1/SW2 active plus disabled keys uses both APIs",function()
  local c=fresh(); local m=cfsMock({true,true})
  local w=core.writer(); w.probeKeys()
  assert(w.keyCount==6 and w.routes[32]=="cfs" and w.routes[33]=="cfs")
  for id=34,37 do assert(w.routes[id]=="rgb") end
  core.render(w,c,1); assert(count(0,37)==38)
  assert(m.overrides[1] and m.overrides[2] and not m.overrides[3])
end)
test("CFS path also fills 3/4 then 2/5 then 1/6 before gimbal rings",function()
  local c=fresh(); local m=cfsMock(allAssigned)
  local w=core.writer(); w.probeKeys(); assert(w.keyCount==6)
  for step=0,3 do
    core.render(w,c,step/19)
    assert(count()==0 and count(32,37)==step*2)
    for i=1,6 do
      local expected=(i>=4-step and i<=3+step)
      assert((lit(31+i) or false)==expected,"Wrong CFS fill order")
    end
  end
  core.render(w,c,3.5/19); assert(count()==2 and count(32,37)==6)
end)
test("ON and OFF Lua gates are independent and API success cannot confirm permission",function()
  local c=fresh(); local m=cfsMock(allAssigned)
  m.allowOn[1]=false
  local w=core.writer(); w.probeKeys(); assert(w.keyCount==6)
  core.render(w,c,1); local desired=table.concat(leds[32],",")
  assert(desired~="0,45,0")
  m.on[1]=true; refreshCfs(); assert(table.concat(leds[32],",")=="0,45,0")
  local before=m.calls
  m.allowOn[1]=true; refreshCfs(); assert(table.concat(leds[32],",")==desired)
  assert(m.calls==before,"Firmware gate change should use the retained override")
  m.allowOff[1]=false; m.on[1]=false; refreshCfs(); assert(table.concat(leds[32],",")=="35,0,0")
  m.allowOff[1]=true; refreshCfs(); assert(table.concat(leds[32],",")==desired)
end)
test("CFS remains usable when LED_STRIP_LENGTH only includes 32 decorative LEDs",function()
  local c=fresh(); cfsMock(allAssigned); LED_STRIP_LENGTH=32
  local w=core.writer(); w.probeKeys(); assert(w.keyCount==6)
  core.render(w,c,1); assert(count(0,37)==38)
  LED_STRIP_LENGTH=38
end)
test("false or throwing CFS API gracefully falls back without a crash",function()
  for _,throws in ipairs({false,true}) do
    local c=fresh(); cfsMock(allAssigned)
    local setter=setCFSLedColor
    setCFSLedColor=function(name,...)
      if name=="SW4" then if throws then error("Vendor API failure") end; return false end
      return setter(name,...)
    end
    local w=core.writer(); w.probeKeys(); assert(w.keyCount==5)
    core.render(w,c,0.5); assert(count()>0)
    assert(w.keyEnabled==false)
  end
end)
test("switching six key mode off releases overrides instead of forcing indicators black",function()
  local c=fresh(); local m=cfsMock(allAssigned)
  local w=core.writer(); w.probeKeys(); core.render(w,c,1)
  for i=1,6 do assert(m.overrides[i]) end
  c.keys=0; core.render(w,c,1); refreshCfs()
  for i=1,6 do assert(not m.overrides[i] and table.concat(leds[31+i],",")=="35,0,0") end
  c.keys=1; core.render(w,c,1)
  for i=1,6 do assert(m.overrides[i]) end
end)
test("loading never-active presets does not acquire or release another preset's CFS lights",function()
  local c=fresh(); local m=cfsMock(allAssigned); assert(core.save(c)); stick=1024; now=0
  local active=script("HelloRadio-V15/SCRIPTS/RGBLED/B02-rain.lua"); active.init(); active.run()
  local beforeCalls,beforeCancels=m.calls,m.cancels
  local other=script("HelloRadio-V15/SCRIPTS/RGBLED/B07-blue.lua"); other.init()
  for i=1,100 do other.background() end
  assert(m.calls==beforeCalls and m.cancels==beforeCancels)
  for i=1,6 do assert(m.overrides[i]) end
end)
test("deactivation releases CFS once and reactivation re-probes changed button types",function()
  local c=fresh(); local m=cfsMock(allAssigned); assert(core.save(c)); stick=1024; now=0
  local rt=script("HelloRadio-V15/SCRIPTS/RGBLED/B02-rain.lua"); rt.init(); rt.run()
  local n=m.cancels
  rt.background(); assert(m.cancels==n+6)
  for i=1,20 do rt.background() end
  assert(m.cancels==n+6)
  for i=1,6 do assert(not m.overrides[i]) end
  denied[32]=false; denied[33]=false
  now=5; rt.run()
  assert(not m.overrides[1] and not m.overrides[2])
  for i=3,6 do assert(m.overrides[i]) end
  assert(count(0,37)==38)
end)
test("key diagnostic shows CFS route and tool exit releases its colour overrides",function()
  local c=fresh(); local m=cfsMock(allAssigned); assert(core.save(c))
  local t=openTool(); click("测试"); t.run(); click("测键灯"); t.run()
  assert(textOf(ui[1])=="接口响应 6/6")
  assert(string.find(textOf(ui[2]),"SW1  Lua专用",1,true)); layout()
  assert(m.overrides[1])
  click("返回"); t.run(); closePage(); assert(t.run()==2)
  for i=1,6 do assert(not m.overrides[i]) end
end)
local motion=script("HelloRadio-V15/SCRIPTS/RGBLED/v15lib/motion.lua")
local motionPresets={{"A01-flow","flow"},{"A05-brea","breathe"},{"A08-comt","comet"},
  {"A11-scan","scan"},{"A02-aura","aurora"},{"B15-jet","jet"}}
local function newMotion(name)
  local rt=script("HelloRadio-V15/SCRIPTS/RGBLED/"..name..".lua"); rt.init(); return rt
end
test("six new entries run without changing saved calibration or switch/model settings",function()
  for _,preset in ipairs(motionPresets) do
    local c=fresh(); assert(core.save(c)); local saved=files[core.path]
    stick=-1024; local rt=newMotion(preset[1]); rt.run()
    if preset[2]=="jet" then
      assert(count(0,37)==0); stick=1024; now=5; rt.run(); assert(count()>0)
    else assert(count()>0,"Exhibition effect must work at zero throttle") end
    assert(files[core.path]==saved)
  end
end)
test("exhibition effects animate with time but never read throttle or output channels",function()
  local readStick,readOutput=getValue,getOutputValue
  local ok,err=pcall(function()
    getValue=function() error("Exhibition must not read sticks") end
    getOutputValue=getValue
    for i=1,5 do
      local c=fresh(); c.source=32; assert(core.save(c))
      local rt=newMotion(motionPresets[i][1]); rt.run(); local initial=snapshot()
      for t=5,40,5 do now=t; rt.run() end
      assert(snapshot()~=initial,motionPresets[i][1])
    end
  end)
  getValue,getOutputValue=readStick,readOutput; assert(ok,err)
end)
test("every animation stays within integer RGB and user brightness bounds",function()
  for _,preset in ipairs(motionPresets) do
    for _,brightness in ipairs({5,40,100}) do
      local c,w=fresh(); c.brightness=brightness
      for phase=0,40 do
        motion.render(core,w,c,preset[2],phase/40,0.73)
        for id=0,37 do for _,v in ipairs(leds[id]) do
          assert(v>=0 and v<=math.floor(255*brightness/100+0.5))
        end end
      end
    end
  end
end)
test("all dynamic cycles are continuous at the wrap seam",function()
  for _,preset in ipairs(motionPresets) do
    local c,w=fresh(); c.brightness=100
    motion.render(core,w,c,preset[2],0.99999,1)
    local previous={}; for id=0,37 do previous[id]={table.unpack(leds[id])} end
    motion.render(core,w,c,preset[2],0.00001,1)
    for id=0,37 do for ch=1,3 do
      assert(math.abs(previous[id][ch]-leds[id][ch])<=1,preset[2].." discontinuous colour")
    end end
  end
end)
test("comet head interpolates across LEDs rather than jumping whole beads",function()
  local c,w=fresh(); c.brightness=100
  motion.render(core,w,c,"comet",0,1)
  local a,b=core.ringId(c,0,0,1,1),core.ringId(c,0,1,1,1)
  assert(leds[a][3]==255 and leds[b][3]==0)
  motion.render(core,w,c,"comet",0.5/16,1)
  assert(leds[a][3]>0 and leds[a][3]<255 and leds[b][3]>0 and leds[b][3]<255)
  motion.render(core,w,c,"comet",1/16,1); assert(leds[b][3]==255)
end)
test("scan sweeps bottom to top and back symmetrically on each ring",function()
  local c,w=fresh()
  for _,phase in ipairs({0,0.25,0.5,0.75,1}) do
    motion.render(core,w,c,"scan",phase,0)
    for group=0,1 do
      local bottom,top=core.ringId(c,group,0,1,2),core.ringId(c,group,8,1,2)
      if phase==0 or phase==1 then assert(lit(bottom) and not lit(top)) end
      if phase==0.5 then assert(lit(top) and not lit(bottom)) end
      for step=1,7 do
        local a,b=core.ringId(c,group,step,1,2),core.ringId(c,group,16-step,1,2)
        assert(table.concat(leds[a],",")==table.concat(leds[b],","))
      end
    end
  end
end)
test("dynamic rings respect swapped sides and reversed physical numbering",function()
  local c,w=fresh(); c.left=1; c.cwA=0; c.cwB=1; c.bottomA=3; c.bottomB=28
  motion.render(core,w,c,"comet",0,1)
  -- A is now RIGHT (inner bottom is one CW step from six); B is LEFT.
  assert(leds[2][3]==102 and leds[27][3]==102)
  motion.render(core,w,c,"comet",1/16,1)
  assert(leds[3][3]==102 and leds[28][3]==102)
end)
test("jet retains six keys first, fractional frontier, and zero/invalid throttle darkness",function()
  local c,w=fresh()
  for k=1,3 do
    motion.render(core,w,c,"jet",0.2,k/19)
    assert(count()==0 and count(32,37)==k*2)
  end
  motion.render(core,w,c,"jet",0.2,3.5/19); assert(count()==2 and count(32,37)==6)
  for _,p in ipairs({0,-1,0/0}) do motion.render(core,w,c,"jet",0.2,p); assert(count(0,37)==0) end
  motion.render(core,w,c,"jet",0.2,nil); assert(count(0,37)==0)
end)
test("dynamic runtime limits refresh to 20 Hz and does not poll or write SD",function()
  for _,preset in ipairs(motionPresets) do
    local c=fresh(); assert(core.save(c)); local saved=files[core.path]; stick=1024
    local rt=newMotion(preset[1]); rt.run()
    local beforeReads,beforeWrites,beforeCommits=reads,writes,commits
    for t=1,4 do now=t; rt.run() end
    assert(writes==beforeWrites and commits==beforeCommits)
    for t=5,100 do
      now=t; rt.run()
      assert(commits-beforeCommits<=math.floor(t/5))
    end
    assert(reads==beforeReads and files[core.path]==saved)
    assert(commits>beforeCommits,preset[1].." did not animate")
  end
end)
test("jet follows selected output, smoothing, reversal and immediate throttle cut",function()
  local c=fresh(); c.source=3; c.reverse=1; assert(core.save(c)); output=-1024
  local rt=newMotion("B15-jet"); rt.run(); assert(count()==32 and lastChannel==2)
  output=0; now=5; rt.run(); assert(count()>0)
  output=1024; now=10; rt.run(); assert(count(0,37)==0)
  output=nil; now=15; rt.run(); assert(count(0,37)==0); output=1024
end)
test("dynamic scripts support mixed CFS/direct keys and release only owned overrides",function()
  local c=fresh(); local m=cfsMock({true,true}); assert(core.save(c))
  local rt=newMotion("A01-flow"); rt.run()
  assert(m.overrides[1] and m.overrides[2] and not m.overrides[3] and count(32,37)==6)
  local calls,cancels=m.calls,m.cancels
  local idle=newMotion("A02-aura"); for i=1,20 do idle.background() end
  assert(m.calls==calls and m.cancels==cancels)
  rt.background(); assert(m.cancels==cancels+2)
  for i=1,20 do rt.background() end
  assert(m.cancels==cancels+2)
  denied[32]=false; now=5; rt.run()
  assert(not m.overrides[1] and m.overrides[2])
end)
test("dynamic key gates, disable setting and 32 LED firmware use existing compatibility",function()
  local c=fresh(); local m=cfsMock(allAssigned); assert(core.save(c))
  LED_STRIP_LENGTH=32
  local rt=newMotion("A01-flow"); rt.run(); assert(count(0,37)==38)
  m.on[1]=true; m.allowOn[1]=false; refreshCfs()
  assert(table.concat(leds[32],",")=="0,45,0")
  rt.background(); c.keys=0; assert(core.save(c)); now=5; rt.run()
  for i=1,6 do assert(not m.overrides[i]) end
  LED_STRIP_LENGTH=38
  c=fresh(); c.keys=0; assert(core.save(c)); rt=newMotion("A01-flow"); rt.run()
  assert(count(32,37)==0 and count()==32)
end)
test("partial button API failure leaves blocked keys alone and animates rings",function()
  local c=fresh(); denied[32]=true; leds[32]={12,34,56}; assert(core.save(c))
  local rt=newMotion("A01-flow"); rt.run()
  assert(count()==32 and table.concat(leds[32],",")=="12,34,56")
  assert(count(33,37)==0)
end)
test("pause, time wrap and reactivation restart animations without phase jumps or stale config",function()
  local c=fresh(); assert(core.save(c)); local rt=newMotion("A01-flow"); rt.run()
  local first=snapshot()
  now=5; rt.run(); assert(snapshot()~=first)
  now=100; rt.run(); assert(snapshot()==first)
  now=0; rt.run(); assert(snapshot()==first)
  c.brightness=20; assert(core.save(c)); rt.background(); now=5; rt.run()
  assert(snapshot()~=first)
  for id=0,37 do for _,v in ipairs(leds[id]) do assert(v<=51) end end
end)
test("missing or uncalibrated config does not guess animation geometry",function()
  for _,preset in ipairs(motionPresets) do
    local c,w=fresh(); core.render(w,c,1); files[core.path]=nil
    local rt=newMotion(preset[1]); rt.run(); assert(count(0,37)==0)
    files[core.path]="V15THR1\nbottomA=9\nbottomB=23\nsource=3\nreverse=1\nbrightness=60\n"
    rt.background(); now=5; rt.run(); assert(count(0,37)==0)
  end
end)
test("missing dynamic/shared libraries and unknown effects fail with actionable messages",function()
  local original=loadScript
  for _,missing in ipairs({"motion.lua","effects.lua"}) do
    loadScript=function(path,mode)
      if string.find(path,missing,1,true) then return nil end
      return original(path,mode)
    end
    local ok,err=pcall(function() newMotion("A01-flow") end)
    assert(not ok and string.find(tostring(err),missing,1,true))
  end
  loadScript=original
  local ok,err=pcall(motion.runtime,core,"not-an-effect")
  assert(not ok and string.find(tostring(err),"unknown animation",1,true))
end)
test("all six animations work in the radio's no-string-metatable environment",function()
  local c=fresh(); assert(core.save(c)); local meta=debug.getmetatable("")
  debug.setmetatable("",nil)
  local ok,err=pcall(function()
    for _,preset in ipairs(motionPresets) do
      stick=1024; now=0; local rt=newMotion(preset[1]); rt.run()
      for t=5,50,5 do now=t; rt.run() end
      rt.background()
    end
  end)
  debug.setmetatable("",meta); assert(ok,err)
end)
local creative=script("HelloRadio-V15/SCRIPTS/RGBLED/v15lib/creative.lua")
local creativePresets={{"A09-dual","dual"},{"A12-ripl","wave"},{"A04-star","star"},{"A03-lava","lava"},
  {"A07-beat","beat"},{"A06-swap","swap"},{"A13-nova","nova"},{"A10-rot","rotor"}}
test("eight creative entries animate without modifying calibration or reading control inputs",function()
  local readStick,readOutput=getValue,getOutputValue
  local ok,err=pcall(function()
    getValue=function() error("Creative lights must not read inputs") end
    getOutputValue=getValue
    for _,preset in ipairs(creativePresets) do
      local c=fresh(); c.source=32; assert(core.save(c)); local saved=files[core.path]
      local rt=newMotion(preset[1]); rt.run(); local initial=snapshot()
      for t=5,100,5 do now=t; rt.run() end
      assert(snapshot()~=initial,preset[1]); assert(files[core.path]==saved)
    end
  end)
  getValue,getOutputValue=readStick,readOutput; assert(ok,err)
end)
test("creative RGB remains integer and brightness-limited throughout every effect",function()
  for _,preset in ipairs(creativePresets) do for _,brightness in ipairs({5,40,100}) do
    local c,w=fresh(); c.brightness=brightness
    for phase=0,80 do
      creative.render(core,w,c,preset[2],phase/80)
      for id=0,37 do for _,v in ipairs(leds[id]) do
        assert(v>=0 and v<=math.floor(255*brightness/100+0.5),preset[2])
      end end
    end
  end end
end)
test("all eight creative cycles are continuous across the repeat boundary",function()
  for _,preset in ipairs(creativePresets) do
    local c,w=fresh(); c.brightness=100
    creative.render(core,w,c,preset[2],0.99999)
    local previous={}; for id=0,37 do previous[id]={table.unpack(leds[id])} end
    creative.render(core,w,c,preset[2],0.00001)
    for id=0,37 do for ch=1,3 do
      assert(math.abs(previous[id][ch]-leds[id][ch])<=1,preset[2].." seam jump")
    end end
  end
end)
test("dual comets start opposite, counter-rotate and blend colours when crossing",function()
  local c,w=fresh(); c.brightness=100
  creative.render(core,w,c,"dual",0)
  local a,b=core.ringId(c,0,0,1,2),core.ringId(c,0,8,1,2)
  assert(leds[a][1]==0 and leds[a][2]==220 and leds[a][3]==255)
  assert(leds[b][1]==255 and leds[b][2]==0 and leds[b][3]==165)
  creative.render(core,w,c,"dual",0.25)
  local cross=core.ringId(c,0,4,1,2)
  assert(leds[cross][1]==255 and leds[cross][2]==220 and leds[cross][3]==255)
end)
test("nova charges keys before rings, reaches white and fades to darkness",function()
  local c,w=fresh(); c.brightness=100
  creative.render(core,w,c,"nova",0); assert(count(0,37)==0)
  creative.render(core,w,c,"nova",0.62*3/19); assert(count()==0 and count(32,37)==6)
  creative.render(core,w,c,"nova",0.62); assert(count(0,37)==38)
  creative.render(core,w,c,"nova",0.72)
  for id=0,37 do for _,v in ipairs(leds[id]) do assert(v==255) end end
  creative.render(core,w,c,"nova",0.9)
  for id=0,37 do for _,v in ipairs(leds[id]) do assert(v>0 and v<50) end end
  creative.render(core,w,c,"nova",1); assert(count(0,37)==0)
end)
test("alternating breath follows physical left/right and the corresponding three keys",function()
  local c,w=fresh(); c.left=1; c.brightness=100
  creative.render(core,w,c,"swap",0)
  -- Group A is physical right: bright pink. Group B is physical left: dim cyan.
  for id=0,15 do assert(leds[id][1]==255 and leds[id][3]==150) end
  for id=16,31 do assert(leds[id][1]==0 and leds[id][3]<10) end
  assert(leds[32][3]<10 and leds[37][1]==255)
  creative.render(core,w,c,"swap",0.5)
  assert(leds[0][1]<10 and leds[16][3]==255)
  assert(leds[32][3]==255 and leds[37][1]<10)
end)
test("ripple and heartbeat remain symmetric around the physical bottom/top axis",function()
  for _,kind in ipairs({"wave","beat"}) do
    local c,w=fresh(); c.cwA=0; c.cwB=1; c.bottomA=2; c.bottomB=27
    for _,phase in ipairs({0.2,0.3,0.5,0.8}) do
      creative.render(core,w,c,kind,phase)
      for group=0,1 do for step=1,7 do
        local a,b=core.ringId(c,group,step,1,2),core.ringId(c,group,16-step,1,2)
        assert(table.concat(leds[a],",")==table.concat(leds[b],","))
      end end
    end
  end
end)
test("rotor has exactly four equally spaced bright blades at its starting phase",function()
  local c,w=fresh(); c.brightness=100
  creative.render(core,w,c,"rotor",0)
  for group=0,1 do for step=0,15 do
    local pixel=leds[core.ringId(c,group,step,1,2)]
    if step%4==0 then assert(pixel[3]==255) else assert(pixel[3]<30) end
  end end
end)
test("starfield is deterministic and does not rewrite a repeated frame",function()
  local c,w=fresh()
  creative.render(core,w,c,"star",0.37); local fixed=snapshot(); local before=writes
  now=50000
  creative.render(core,w,c,"star",0.37)
  assert(snapshot()==fixed and writes==before)
  local colors={}; for id=0,31 do colors[table.concat(leds[id],",")]=true end
  local n=0; for _ in pairs(colors) do n=n+1 end
  assert(n>16,"Twinkles should differ between beads and rings")
end)
test("all creative runtimes obey 20 Hz and do not read or write SD during playback",function()
  for _,preset in ipairs(creativePresets) do
    local c=fresh(); assert(core.save(c)); local saved=files[core.path]
    local rt=newMotion(preset[1]); rt.run()
    local beforeReads,beforeCommits=reads,commits
    for t=1,100 do now=t; rt.run(); assert(commits-beforeCommits<=math.floor(t/5)) end
    assert(reads==beforeReads and files[core.path]==saved)
    assert(commits>beforeCommits)
  end
end)
test("creative CFS routing releases once and never-active scripts do not steal control",function()
  for _,preset in ipairs(creativePresets) do
    local c=fresh(); local m=cfsMock({true,true}); assert(core.save(c))
    local rt=newMotion(preset[1]); rt.run()
    assert(m.overrides[1] and m.overrides[2] and not m.overrides[3])
    local calls,cancels=m.calls,m.cancels
    local idle=newMotion("A04-star"); for i=1,20 do idle.background() end
    assert(m.calls==calls and m.cancels==cancels)
    rt.background(); rt.background(); assert(m.cancels==cancels+2)
    denied[32]=false; now=5; rt.run(); assert(not m.overrides[1] and m.overrides[2])
  end
end)
test("creative lights preserve disabled-key mode and both CFS permission gates",function()
  local c=fresh(); local m=cfsMock(allAssigned); assert(core.save(c)); LED_STRIP_LENGTH=32
  local rt=newMotion("A09-dual"); rt.run(); assert(m.overrides[1])
  m.on[1]=true; m.allowOn[1]=false; refreshCfs(); assert(table.concat(leds[32],",")=="0,45,0")
  m.allowOn[1]=true; refreshCfs(); assert(table.concat(leds[32],",")~="0,45,0")
  m.on[1]=false; m.allowOff[1]=false; refreshCfs(); assert(table.concat(leds[32],",")=="35,0,0")
  rt.background(); c.keys=0; assert(core.save(c)); now=5; rt.run()
  for i=1,6 do assert(not m.overrides[i]) end
  LED_STRIP_LENGTH=38
end)
test("partial key API failure and 32-LED-only firmware leave unavailable keys alone",function()
  local c=fresh(); denied[32]=true; leds[32]={12,34,56}; assert(core.save(c))
  local rt=newMotion("A03-lava"); rt.run(); assert(count()>0 and count(33,37)==0)
  assert(table.concat(leds[32],",")=="12,34,56")
  c=fresh(); LED_STRIP_LENGTH=32; assert(core.save(c))
  rt=newMotion("A03-lava"); rt.run(); assert(count()>0 and count(32,37)==0)
  LED_STRIP_LENGTH=38
end)
test("creative scripts handle pause, clock wrap, changed brightness and missing calibration",function()
  local c=fresh(); assert(core.save(c)); local rt=newMotion("A03-lava"); rt.run(); local initial=snapshot()
  now=5; rt.run(); assert(snapshot()~=initial)
  now=100; rt.run(); assert(snapshot()==initial)
  now=0; rt.run(); assert(snapshot()==initial)
  c.brightness=20; assert(core.save(c)); rt.background(); now=5; rt.run()
  for id=0,37 do for _,v in ipairs(leds[id]) do assert(v<=51) end end
  for _,preset in ipairs(creativePresets) do
    c=fresh(); assert(core.save(c)); rt=newMotion(preset[1]); rt.run()
    rt.background(); files[core.path]=nil; now=5; rt.run(); assert(count(0,37)==0)
    files[core.path]="V15THR1\nbottomA=9\nbottomB=23\nsource=3\nreverse=1\nbrightness=60\n"
    rt.background(); now=10; rt.run(); assert(count(0,37)==0)
  end
end)
test("creative loader reports missing dependencies and rejects unknown effects",function()
  local original=loadScript
  for _,missing in ipairs({"creative.lua","effects.lua"}) do
    loadScript=function(path,mode)
      if string.find(path,missing,1,true) then return nil end
      return original(path,mode)
    end
    local ok,err=pcall(function() newMotion("A04-star") end)
    assert(not ok and string.find(tostring(err),missing,1,true))
  end
  loadScript=original
  assert(not pcall(creative.runtime,core,"unknown"))
end)
test("creative loader and all eight effects tolerate the radio's missing string metatable",function()
  local c=fresh(); assert(core.save(c)); local meta=debug.getmetatable("")
  debug.setmetatable("",nil)
  local ok,err=pcall(function()
    for _,preset in ipairs(creativePresets) do
      now=0; local rt=newMotion(preset[1]); rt.run()
      for t=5,50,5 do now=t; rt.run() end
      rt.background()
    end
  end)
  debug.setmetatable("",meta); assert(ok,err)
end)
local sticks=script("HelloRadio-V15/SCRIPTS/RGBLED/v15lib/sticks.lua")
local stickPresets={{"C01-aim","aim"},{"C02-mix","mix"},{"C03-spin","spin"},{"C04-cmb","combo"}}
local function withSticks(fn)
  local originalValue,originalMode=getValue,getStickMode
  local values={rud=0,thr=-1024,ail=0,ele=0}
  getValue=function(name) assert(values[name]~=nil,"Unexpected input source: "..name); return values[name] end
  getStickMode=function() return 2 end
  local ok,err=pcall(fn,values)
  getValue,getStickMode=originalValue,originalMode
  assert(ok,err)
end
local neutral={0,-1,0,0}
local poses={out={-1,-1,1,0},["in"]={1,-1,-1,0},right={1,-1,1,0},left={-1,-1,-1,0}}
local function hold(s,v,n) for i=1,n do sticks.advance(s,v,0.05,"combo") end end
test("stick mode prefers the API and safely falls back to zero-based radio YAML",function()
  withSticks(function()
    files['/RADIO/radio.yml']='stickMode: 0\n'; assert(sticks.mode()==2)
    getStickMode=nil
    for raw=0,3 do files['/RADIO/radio.yml']='board: v15\r\nstickMode: '..raw..'\r\n'; assert(sticks.mode()==raw+1) end
    for _,text in ipairs({'','stickMode: 5\n','  stickMode: 1\n','stickMode: broken\n'}) do
      files['/RADIO/radio.yml']=text; assert(sticks.mode()==nil)
    end
    getStickMode=function() error('missing vendor API') end
    files['/RADIO/radio.yml']='stickMode: 1\n'; assert(sticks.mode()==2)
  end)
end)
test("all four stick modes map actual left/right physical axes",function()
  withSticks(function(v)
    v.rud=128; v.ele=256; v.thr=512; v.ail=1024
    local expected={{.125,.25,1,.5},{.125,.5,1,.25},{1,.25,.125,.5},{1,.5,.125,.25}}
    for mode=1,4 do
      local out=sticks.inputs(mode)
      for i=1,4 do assert(out[i]==expected[mode][i]) end
    end
  end)
end)
test("stick sources reject missing nonfinite and throwing values while clamping endpoints",function()
  withSticks(function(v)
    v.rud=2048; v.ail=-2048; v.ele=20
    local p=sticks.inputs(2); assert(p[1]==1 and p[3]==-1 and p[4]==0)
    for _,bad in ipairs({0/0,math.huge,-math.huge,'bad'}) do v.ele=bad; assert(sticks.inputs(2)==nil) end
    v.ele=nil; assert(sticks.inputs(2)==nil)
    assert(sticks.inputs(nil)==nil)
  end)
end)
test("heading matches physical up down left right without requiring atan2 API",function()
  assert(sticks.heading(0,-1)==0)
  assert(sticks.heading(-1,0)==.25)
  assert(sticks.heading(0,1)==.5)
  assert(sticks.heading(1,0)==.75)
end)
test("four stick entries run using raw stick sources and preserve saved configuration",function()
  withSticks(function(v)
    for _,preset in ipairs(stickPresets) do
      local c=fresh(); c.source=32; assert(core.save(c)); local saved=files[core.path]
      local rt=newMotion(preset[1]); rt.run()
      for t=5,100,5 do v.ail=math.floor(1024*math.sin(t/10)); now=t; rt.run() end
      assert(count()>0 and files[core.path]==saved)
    end
  end)
end)
test("direction tracker moves only the physical right ring and right keys for right stick input",function()
  local c,w=fresh(); c.left=1
  local s=sticks.state(); sticks.render(core,w,c,"aim",s,{0,-1,0,0})
  local left={}; for id=16,31 do left[id]=table.concat(leds[id],",") end
  for id=32,34 do left[id]=table.concat(leds[id],",") end
  sticks.render(core,w,c,"aim",s,{0,-1,1,0})
  for id,color in pairs(left) do assert(table.concat(leds[id],",")==color) end
  local right=core.ringId(c,0,12,4,2); assert(leds[right][1]==102)
  assert(count(35,37)==3)
end)
test("vortex rings can turn independently in opposite directions",function()
  local s=sticks.state(); sticks.advance(s,{1,-1,0,0},.1,"spin")
  assert(s.phaseL>0 and s.phaseR==0)
  s=sticks.state(); sticks.advance(s,{1,-1,-1,0},.1,"spin")
  assert(math.abs(s.phaseL+s.phaseR-1)<.000001)
end)
test("mixing desk uses colour energy direction speed and width from four axes",function()
  local c,w=fresh(); local s=sticks.state()
  local v={0,0,0,0}; sticks.render(core,w,c,"mix",s,v); local baseline=snapshot()
  for _,i in ipairs({1,2,4}) do
    local input={0,0,0,0}; input[i]=1
    sticks.render(core,w,c,"mix",s,input); assert(snapshot()~=baseline)
  end
  sticks.advance(s,{0,0,1,0},.2,"mix")
  sticks.render(core,w,c,"mix",s,v); assert(snapshot()~=baseline)
end)
test("three two-step combos trigger their corresponding effect then require re-centering",function()
  for _,seq in ipairs({{'out','in','nova'},{'in','out','wave'},{'right','left','rainbow'}}) do
    local s=sticks.state(); hold(s,neutral,5); assert(s.armed)
    hold(s,poses[seq[1]],6); assert(s.first==seq[1] and not s.effect)
    hold(s,neutral,3); hold(s,poses[seq[2]],6); assert(s.effect==seq[3])
    hold(s,poses[seq[2]],100); assert(not s.effect and not s.armed)
    hold(s,neutral,5); assert(s.armed)
  end
end)
test("startup held sticks, short holds and subthreshold jitter cannot trigger combos",function()
  local s=sticks.state(); hold(s,poses.out,10); hold(s,poses['in'],10)
  assert(not s.effect and not s.armed)
  hold(s,neutral,5); hold(s,poses.out,3); hold(s,neutral,2); assert(not s.first)
  hold(s,{-.6,-1,.6,0},20); assert(not s.first and not s.effect)
end)
test("wrong order and expired combo windows do not fire",function()
  local s=sticks.state(); hold(s,neutral,5); hold(s,poses.out,6); hold(s,neutral,55)
  hold(s,poses['in'],6); assert(not s.effect)
  s=sticks.state(); hold(s,neutral,5); hold(s,poses.out,6); hold(s,neutral,3)
  hold(s,poses.right,6); assert(not s.effect and not s.armed)
end)
test("all stick effects and combo bursts stay within the user's brightness limit",function()
  for _,preset in ipairs(stickPresets) do
    local c,w=fresh(); c.brightness=20; local s=sticks.state()
    for frame=0,80 do
      local v={math.sin(frame),math.cos(frame),math.sin(frame/3),math.cos(frame/7)}
      sticks.advance(s,v,.05,preset[2]); sticks.render(core,w,c,preset[2],s,v)
      for id=0,37 do for _,value in ipairs(leds[id]) do assert(value<=51 and value>=0) end end
    end
    if preset[2]=='combo' then for _,effect in ipairs({'nova','wave','rainbow'}) do
      for frame=0,48 do s.effect=effect; s.effectAge=frame*.05
        sticks.render(core,w,c,'combo',s,neutral)
        for id=0,37 do for _,value in ipairs(leds[id]) do assert(value<=51 and value>=0) end end
      end
    end end
  end
end)
test("stick runtimes poll axes at most 20 Hz without repeated SD or mode reads",function()
  withSticks(function(v)
    local readsAxes,readsMode=0,0
    getValue=function(name) readsAxes=readsAxes+1; return v[name] end
    getStickMode=function() readsMode=readsMode+1; return 2 end
    for _,preset in ipairs(stickPresets) do
      local c=fresh(); assert(core.save(c)); local rt=newMotion(preset[1]); rt.run()
      local disk,axes,modeReads=reads,readsAxes,readsMode
      for t=1,100 do now=t; rt.run(); assert(readsAxes-axes<=4*math.floor(t/5)) end
      assert(reads==disk and readsMode==modeReads)
    end
  end)
end)
test("stick effects use CFS and direct keys without stealing or retaining overrides",function()
  withSticks(function()
    local c=fresh(); local m=cfsMock({true,true}); assert(core.save(c))
    local rt=newMotion('C01-aim'); rt.run(); assert(m.overrides[1] and m.overrides[2])
    local calls,cancels=m.calls,m.cancels
    local idle=newMotion('C04-cmb'); idle.background(); idle.background()
    assert(m.calls==calls and m.cancels==cancels)
    rt.background(); rt.background(); assert(m.cancels==cancels+2)
    c.keys=0; assert(core.save(c)); now=5; rt.run(); assert(not m.overrides[1])
  end)
end)
test("unavailable mode or any failed stick read blanks lights instead of inventing gestures",function()
  withSticks(function(v)
    local c=fresh(); assert(core.save(c)); getStickMode=nil; files['/RADIO/radio.yml']=nil
    local rt=newMotion('C01-aim'); rt.run(); assert(count(0,37)==0)
    getStickMode=function() return 2 end
    rt.background(); now=5; rt.run(); assert(count()>0)
    v.rud=nil; now=10; rt.run(); assert(count(0,37)==0)
  end)
end)
test("time wrap and long pause reset combo recognition and settings reload on resume",function()
  withSticks(function(v)
    local c=fresh(); c.smooth=0; assert(core.save(c))
    local rt=newMotion('C04-cmb'); rt.run()
    for t=5,30,5 do now=t; rt.run() end
    v.rud=-1024; v.ail=1024
    for t=35,70,5 do now=t; rt.run() end
    -- A long pause must discard the first gesture.
    now=200; v.rud=1024; v.ail=-1024; rt.run()
    for t=205,235,5 do now=t; rt.run() end
    -- Waiting ring is dim; it cannot be displaying a bright burst.
    for id=0,31 do for _,value in ipairs(leds[id]) do assert(value<=46) end end
    now=0; rt.run()
    rt.background(); c.brightness=5; assert(core.save(c)); now=5; rt.run()
    for id=0,37 do for _,value in ipairs(leds[id]) do assert(value<=13) end end
  end)
end)
test("stick loader and YAML fallback work without the firmware string metatable",function()
  withSticks(function()
    local c=fresh(); assert(core.save(c)); getStickMode=nil; files['/RADIO/radio.yml']='stickMode: 1\n'
    local meta=debug.getmetatable(''); debug.setmetatable('',nil)
    local ok,err=pcall(function()
      for _,preset in ipairs(stickPresets) do
        local rt=newMotion(preset[1]); now=0; rt.run(); now=5; rt.run(); rt.background()
      end
    end)
    debug.setmetatable('',meta); assert(ok,err)
  end)
end)
test("stick loader gives actionable missing-library errors and rejects invalid effects",function()
  local original=loadScript
  loadScript=function(path,mode)
    if string.find(path,'sticks.lua',1,true) then return nil end
    return original(path,mode)
  end
  local ok,err=pcall(function() newMotion('C01-aim') end)
  loadScript=original; assert(not ok and string.find(tostring(err),'sticks.lua',1,true))
  assert(not pcall(sticks.runtime,core,'invalid'))
end)
test("about page displays identity without changing calibration or LEDs",function()
  LCD_W,LCD_H=480,272; lvgl.PAGE_BODY_HEIGHT=232
  local c=fresh(); assert(core.save(c)); local saved=files[core.path]
  local t=openTool(); local before=snapshot(); local n=writes
  click("关于"); t.run(); layout()
  assert(textOf(ui[1])=="V15 灯效" and textOf(ui[2])=="作者：Xu")
  assert(#ui==3)
  assert(saved==files[core.path] and writes==n and snapshot()==before)
  click("返回"); t.run(); closePage(); assert(t.run()==2)
end)
io=hostIO
print(string.format("All %d V15 behavioral checks passed (mock hardware; no handset test).",checks))
if arg[2]=='--stick-frames' then
  local states={sticks.state(),sticks.state(),sticks.state(),sticks.state()}
  for frame=0,159 do
    local time=frame/20; local a=time*math.pi/4; local panels={}
    local inputs={{.8*math.sin(2*a),-.8*math.cos(2*a),-.8*math.sin(2*a),.8*math.cos(2*a)},
      {math.sin(a),-.8*math.cos(a),.8*math.sin(2*a),.8*math.cos(a)},
      {.8*math.sin(a),math.sin(2*a),-.8*math.sin(a),-math.sin(2*a)},neutral}
    if time>=.35 and time<1 then inputs[4]=poses.out
    elseif time>=1.2 and time<1.85 then inputs[4]=poses['in']
    elseif time>=4.1 and time<4.7 then inputs[4]=poses['in']
    elseif time>=4.9 and time<5.5 then inputs[4]=poses.out end
    for i,preset in ipairs(stickPresets) do
      local c,w=fresh(); c.brightness=65
      sticks.advance(states[i],inputs[i],frame==0 and 0 or .05,preset[2])
      sticks.render(core,w,c,preset[2],states[i],inputs[i])
      local colors={}
      for group=0,1 do for step=0,15 do
        colors[#colors+1]='['..table.concat(leds[core.ringId(c,group,step,4,2)],',')..']'
      end end
      for id=32,37 do colors[#colors+1]='['..table.concat(leds[id],',')..']' end
      colors[#colors+1]='['..table.concat(inputs[i],',')..']'
      panels[#panels+1]='['..table.concat(colors,',')..']'
    end
    print('FRAME ['..table.concat(panels,',')..']')
  end
end
if arg[2]=="--creative-frames" then
  -- Eight seconds at 20 Hz: all creative periods divide eight, so the GIF loops cleanly.
  for frame=0,159 do
    local panels={}
    for _,preset in ipairs(creativePresets) do
      local c,w=fresh(); c.brightness=65
      local time=frame/20
      local rates={dual=1/4,wave=1/4,star=1/8,lava=1/8,beat=1/4,swap=1/8,nova=1/8,rotor=1/8}
      creative.render(core,w,c,preset[2],time*rates[preset[2]])
      local colors={}
      for group=0,1 do for step=0,15 do
        colors[#colors+1]="["..table.concat(leds[core.ringId(c,group,step,4,2)],",").."]"
      end end
      for id=32,37 do colors[#colors+1]="["..table.concat(leds[id],",").."]" end
      panels[#panels+1]="["..table.concat(colors,",").."]"
    end
    print("FRAME ["..table.concat(panels,",").."]")
  end
end
if arg[2]=="--motion-frames" then
  -- Capture real Lua-rendered RGB, reordered physically clockwise from six.
  for frame=0,159 do
    local panels={}
    for _,preset in ipairs(motionPresets) do
      local c,w=fresh(); c.brightness=65
      local time=frame/20
      local rates={flow=1/8,breathe=1/5,comet=1/2.8,scan=1/4,aurora=1/9,jet=0.8}
      motion.render(core,w,c,preset[2],(time*rates[preset[2]])%1,0.75)
      local colors={}
      for group=0,1 do for step=0,15 do
        colors[#colors+1]="["..table.concat(leds[core.ringId(c,group,step,4,2)],",").."]"
      end end
      for id=32,37 do colors[#colors+1]="["..table.concat(leds[id],",").."]" end
      panels[#panels+1]="["..table.concat(colors,",").."]"
    end
    print("FRAME ["..table.concat(panels,",").."]")
  end
end
if arg[2]=="--layouts" then
  local function quote(v) return '"'..string.gsub(string.gsub(v,'\\','\\\\'),'"','\\"')..'"' end
  for _,f in ipairs(captures) do
    local items={}
    for _,p in ipairs(f.widgets) do
      items[#items+1]=string.format('{"kind":%s,"x":%d,"y":%d,"w":%d,"h":%d,"text":%s}',quote(p.kind),p.x,p.y,p.w,p.h,quote(p.text))
    end
    print(string.format('LAYOUT {"width":%d,"height":%d,"body":%d,"title":%s,"widgets":[%s]}',f.width,f.height,f.body,quote(f.title),table.concat(items,",")))
  end
end
