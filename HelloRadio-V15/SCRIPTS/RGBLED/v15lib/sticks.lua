-- Xu
-- V15 physical dual-stick lights. READ ONLY: no model/mixer/output writes.
local M={version=1}
local modes={{"rud","ele","ail","thr"},{"rud","thr","ail","ele"},
  {"ail","ele","rud","thr"},{"ail","thr","rud","ele"}}
local kinds={aim=true,mix=true,spin=true,combo=true}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function wave(x) return (1-math.cos(2*math.pi*x))/2 end
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function modeValid(v) return finite(v) and v==math.floor(v) and modes[v]~=nil end
function M.mode()
  if type(getStickMode)=="function" then
    local ok,value=pcall(getStickMode)
    if ok and modeValid(value) then return value end
  end
  -- Older vendor builds may omit getStickMode. YAML stores modes zero-based.
  -- Read once on activation, not during rendering; never modify RADIO.
  local ok,text=pcall(function()
    local f=io.open("/RADIO/radio.yml","r")
    if not f then return nil end
    local good,data=pcall(io.read,f,16384); io.close(f)
    return good and data or nil
  end)
  if ok and type(text)=="string" then
    local raw=string.match("\n"..text,"\nstickMode:[ \t]*(%d+)[ \t]*\r?\n")
    local n=raw and tonumber(raw)+1 or nil
    if modeValid(n) then return n end
  end
  return nil
end
function M.inputs(mode)
  if not modes[mode] or type(getValue)~="function" then return nil end
  local v={}
  for i,name in ipairs(modes[mode]) do
    local ok,value=pcall(getValue,name)
    if not ok or not finite(value) then return nil end
    local x=clamp(value/1024,-1,1)
    v[i]=math.abs(x)<0.03 and 0 or x
  end
  return v -- LX, LY, RX, RY; right/up are positive.
end
local function atan2(y,x)
  if x>0 then return math.atan(y/x) end
  if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
  return y>0 and math.pi/2 or (y<0 and -math.pi/2 or 0)
end
function M.heading(x,y)
  return (atan2(-x,-y)/(2*math.pi))%1 -- clockwise from bottom, physical axes
end
local function hue(h)
  local p=(h%1)*6; local n=math.floor(p); local v=(p-n)*255
  if n==0 then return 255,v,0 elseif n==1 then return 255-v,255,0
  elseif n==2 then return 0,255,v elseif n==3 then return 0,255-v,255
  elseif n==4 then return v,0,255 else return 255,0,255-v end
end
local function arc(step,head,width)
  local d=math.abs((step-head+8)%16-8)
  return clamp(1-d/width,0,1)^2
end
local function resetGesture(s)
  s.armed=false; s.neutral=0; s.first=nil; s.age=0
  s.candidate=nil; s.hold=0; s.fired=false
end
function M.state()
  local s={phaseL=0,phaseR=0,effect=nil,effectAge=0}
  resetGesture(s); return s
end
local transitions={out={"in","nova"},["in"]={"out","wave"},right={"left","rainbow"}}
local function pose(v)
  if v[1]<-0.65 and v[3]>0.65 then return "out" end
  if v[1]>0.65 and v[3]<-0.65 then return "in" end
  if v[1]>0.65 and v[3]>0.65 then return "right" end
  if v[1]<-0.65 and v[3]<-0.65 then return "left" end
end
function M.advance(s,v,dt,kind)
  dt=clamp(dt,0,0.5)
  if kind=="mix" then
    s.phaseL=(s.phaseL+v[3]*0.8*dt)%1; s.phaseR=s.phaseL
  else
    s.phaseL=(s.phaseL+v[1]*0.8*dt)%1
    s.phaseR=(s.phaseR+v[3]*0.8*dt)%1
  end
  if kind~="combo" then return end
  if s.effect then
    s.effectAge=s.effectAge+dt
    if s.effectAge>=2.4 then s.effect=nil; resetGesture(s) end
    return
  end
  if not s.armed then
    s.neutral=(math.abs(v[1])<0.2 and math.abs(v[3])<0.2) and s.neutral+dt or 0
    if s.neutral>=0.15 then s.armed=true end
    return
  end
  if s.first then
    s.age=s.age+dt
    if s.age>2.5 then resetGesture(s); return end
  end
  local current=pose(v)
  if current~=s.candidate then s.candidate=current; s.hold=0; s.fired=false end
  if not current or s.fired then return end
  s.hold=s.hold+dt
  if s.hold<0.2 then return end
  s.fired=true
  if not s.first then
    if transitions[current] then s.first=current; s.age=0 end
  elseif current==transitions[s.first][1] then
    s.effect=transitions[s.first][2]; s.effectAge=0
    s.first=nil; s.armed=false
  else resetGesture(s) end
end
function M.render(core,w,c,kind,s,v)
  if not core.valid(c) or c.ready~=1 or not kinds[kind] or not v then return false end
  local keys=c.keys==1 and w.keyCount==6
  w.enableKeys(keys); w.reset()
  local brightness=c.brightness/100
  local function paint(id,step,side,key)
    local x,y=v[side*2+1],v[side*2+2]
    local magnitude=clamp(math.sqrt(x*x+y*y),0,1)
    local r,g,b,level=0,0,0,1
    local phase=side==0 and s.phaseL or s.phaseR
    if kind=="mix" then
      r,g,b=hue((v[1]+1)/2+step/32+side*0.16)
      level=(0.12+0.88*(v[2]+1)/2)*(key and 1 or
        (0.07+0.93*arc(step,(side==0 and 1 or -1)*phase*16,2+3.5*(v[4]+1))))
    elseif kind=="spin" then
      r,g,b=hue((y+1)/2*0.7+side*0.15+step/64)
      level=key and (0.12+0.88*math.abs(x)) or
        (0.03+0.97*math.max(arc(step,phase*16,2.5),0.5*arc(step,phase*16+8,2.5)))
    elseif kind=="combo" and s.effect then
      local t=clamp(s.effectAge/2.4,0,1)
      local fade=math.sin(math.pi*t)^0.7
      if s.effect=="nova" then
        r,g,b=255,120+135*wave(t/2),230
        level=fade*(key and 1 or (0.2+0.8*arc(step,t*32,4)))
      elseif s.effect=="wave" then
        r,g,b=40,210,255
        level=fade*(key and 1 or (0.08+0.92*wave(step/16-t*2)^3))
      else
        r,g,b=hue(step/16-t*2+side*0.1)
        level=fade
      end
    else -- aim, or combo waiting: show the physical direction of each stick.
      r,g,b=side==0 and 0 or 255,side==0 and 210 or 50,side==0 and 255 or 180
      if key then
        if kind=="combo" then
          level=s.first and (step<2 and 0.8 or 0.05) or (s.armed and 0.15 or 0.025)
        else level=clamp(magnitude*3-step,0,1) end
      else
        level=0.025+magnitude*arc(step,M.heading(x,y)*16,1.7+2*magnitude)*0.975
        if kind=="combo" then level=level*0.45 end
      end
    end
    level=clamp(level,0,1)*brightness
    w.set(id,r*level,g*level,b*level)
  end
  if keys then for k=0,2 do paint(34-k,k,0,true); paint(35+k,k,1,true) end end
  for group=0,1 do
    local side=group==c.left and 0 or 1
    for step=0,15 do paint(core.ringId(c,group,step,4,2),step,side,false) end
  end
  w.flush(); return true
end
function M.runtime(core,kind)
  assert(kinds[kind],"V15: unknown dual-stick effect")
  local w,c,mode,s,idle,filtered,last,lastRun,active
  local function init()
    w=core.writer(); idle=core.idle(); c=nil; last=nil; lastRun=nil; active=false
  end
  local function run()
    if not w or not core.hardware() then return end
    local now=getTime()
    if not active or (lastRun and (now<lastRun or now-lastRun>50)) then
      w.probeKeys(); c=core.load(); mode=M.mode(); s=M.state(); filtered=nil
      last=nil; w.last={}; active=true
    end
    lastRun=now
    if last and now>=last and now-last<5 then return end
    local ticks=last and clamp(now-last,0,50) or 0
    last=now
    if c and c.ready==1 and idle.apply(w,c,now) then
      s=M.state(); filtered=nil; return
    end
    local v=c and c.ready==1 and M.inputs(mode) or nil
    if not v then
      s=M.state(); filtered=nil; w.enableKeys(false); w.reset(); w.flush(); return
    end
    if not filtered then filtered=v
    else
      local alpha=c.smooth==0 and 1 or 1-math.exp(-ticks/c.smooth)
      for i=1,4 do
        if math.abs(filtered[i]-v[i])>=0.002 then filtered[i]=filtered[i]+(v[i]-filtered[i])*alpha end
        if math.abs(filtered[i]-v[i])<0.002 then filtered[i]=v[i] end
      end
    end
    M.advance(s,filtered,ticks/100,kind)
    M.render(core,w,c,kind,s,filtered)
  end
  return {init=init,run=run,background=function()
    if active then w.releaseKeys(); active=false; idle=core.idle() end
    last=nil
  end}
end
function M.entry(kind)
  local runtime
  return {init=function()
    runtime=nil
    local ok,core=pcall(function()
      local f=loadScript("/SCRIPTS/RGBLED/v15lib/effects.lua","tx")
      return f and f()
    end)
    if not ok or type(core)~="table" or core.version~=5 then error("V15: copy all SCRIPTS (effects.lua missing)") end
    if not core.hardware() then error("V15: RGB API unavailable") end
    runtime=M.runtime(core,kind); runtime.init()
  end,run=function() if runtime then runtime.run() end end,
  background=function() if runtime then runtime.background() end end}
end
return M
