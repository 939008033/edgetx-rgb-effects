-- Xu
-- V15 v5.1. Only reads stick/channel values; never writes model settings.
-- Assigned SW1..SW6 need setCFSLedColor and BOTH state override permissions.
local M={version=5,revision="5.1",path="/SCRIPTS/RGBLED/v15lib/layout.cfg"}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function int(v,a,b)
  return type(v)=="number" and v==math.floor(v) and v>=a and v<=b
end
local fields={"bottomA","bottomB","cwA","cwB","left","ready","source","reverse",
  "brightness","smooth","palette","pattern","angle","keys"}
local ranges={{0,15},{16,31},{0,1},{0,1},{0,1},{0,1},{0,32},{0,1},
  {5,100},{0,20},{1,8},{1,5},{1,4},{0,1}}
function M.defaults()
  return {bottomA=0,bottomB=16,cwA=1,cwB=1,left=0,ready=0,source=0,
    reverse=0,brightness=40,smooth=8,palette=1,pattern=1,angle=1,keys=1}
end
function M.valid(c)
  if type(c)~="table" then return false end
  for i,k in ipairs(fields) do if not int(c[k],ranges[i][1],ranges[i][2]) then return false end end
  return true
end
function M.hardware()
  return type(setRGBLedColor)=="function" and type(applyRGBLedColors)=="function"
    and type(LED_STRIP_LENGTH)=="number" and LED_STRIP_LENGTH>=32
end
local function readText()
  local f=io.open(M.path,"r")
  if not f then return nil end
  local ok,text=pcall(io.read,f,1024)
  io.close(f)
  if not ok then error(text) end
  return text
end
function M.load()
  local ok,text=pcall(readText)
  if not ok or type(text)~="string" then return nil,"missing" end
  local legacy=string.match(text,"^V15THR1\n")~=nil
  if not legacy and not string.match(text,"^V15THR5\n") then return nil,"invalid" end
  local c={}
  for k,v in string.gmatch(text,"([%a]+)=(%d+)\n") do c[k]=tonumber(v) end
  if legacy then
    for _,k in ipairs({"bottomA","bottomB","source","reverse","brightness"}) do
      if c[k]==nil then return nil,"invalid" end
    end
    local d=M.defaults()
    for k,v in pairs(c) do d[k]=v end
    d.ready=0 -- Old bottom points do not establish clockwise direction or left/right.
    c=d
  end
  if not M.valid(c) then return nil,"invalid" end
  return c,legacy and "legacy" or nil
end
function M.save(c)
  if not M.valid(c) or c.ready~=1 then return false end
  local lines={"V15THR5"}
  for _,k in ipairs(fields) do lines[#lines+1]=k.."="..c[k] end
  local text=table.concat(lines,"\n").."\n"
  local ok=pcall(function()
    local f=io.open(M.path,"w")
    if not f then error("SD open failed") end
    local wrote,err=pcall(io.write,f,text)
    io.close(f)
    if not wrote then error(err) end
    if readText()~=text then error("SD read-back failed") end
  end)
  return ok
end
function M.progress(c)
  local reader=c.source==0 and getValue or getOutputValue
  if type(reader)~="function" then return nil end
  local ok,v=pcall(reader,c.source==0 and "thr" or c.source-1)
  if not ok or type(v)~="number" or v~=v then return nil end
  local p=clamp((v+1024)/2048,0,1)
  return c.reverse==1 and 1-p or p
end

M.paletteNames={"彩虹渐变","冰蓝渐变","橙金渐变","青粉渐变","绿蓝渐变","纯青蓝","纯紫色","纯金色"}
M.patternNames={"左右镜像","镜像反向","两侧展开","双环顺时针","双环逆时针"}
M.angleNames={"内下角","正下方","正上方","外下角"}
local palettes={
  {{255,55,0},{255,190,0},{45,255,35},{0,215,255},{50,50,255},{200,0,255}},
  {{0,65,255},{0,200,255},{180,245,255}},
  {{255,30,0},{255,125,0},{255,230,60}},
  {{0,210,255},{160,210,255},{255,45,170}},
  {{40,255,70},{0,220,200},{30,80,255}},
  {{0,180,255}},{{190,0,255}},{{255,170,0}}
}
function M.color(palette,t)
  local stops=palettes[palette] or palettes[1]
  local p=clamp(t,0,1)*(#stops-1)
  local i=math.min(#stops,math.floor(p)+1)
  local a,b=stops[i],stops[math.min(#stops,i+1)]
  local f=p-math.floor(p)
  return a[1]+(b[1]-a[1])*f,a[2]+(b[2]-a[2])*f,a[3]+(b[3]-a[3])*f
end

-- One writer per frame; no clear/apply/paint sequence. Cache integer output
-- so steady throttle causes no repeated Lua writes or SD reads.
function M.writer()
  local w={frame={},last={},keys={},keyCount=0,routes={},owned={},keyEnabled=true}
  for id=0,37 do w.frame[id]={0,0,0} end
  function w.set(id,r,g,b)
    local p=w.frame[id]
    p[1]=math.floor(clamp(r,0,255)+0.5)
    p[2]=math.floor(clamp(g,0,255)+0.5)
    p[3]=math.floor(clamp(b,0,255)+0.5)
  end
  function w.reset()
    for id=0,37 do w.set(id,0,0,0) end
  end
  function w.releaseKeys()
    -- Only release overrides this writer has actually set. Inactive presets
    -- must not cancel the currently selected preset's overrides.
    for id,name in pairs(w.owned) do
      if type(setCFSLedColor)=="function" then pcall(setCFSLedColor,name) end
      w.last[id]=nil
    end
    w.owned={}
  end
  function w.enableKeys(enabled)
    if not enabled and w.keyEnabled then
      w.releaseKeys()
      local changed=false
      for id=32,37 do
        if w.routes[id]=="rgb" and w.last[id] and w.last[id]~=0 then
          setRGBLedColor(id,0,0,0); changed=true
        end
      end
      if changed then applyRGBLedColors() end
    end
    if enabled~=w.keyEnabled then
      for id=32,37 do w.last[id]=nil end
    end
    w.keyEnabled=enabled
  end
  function w.probeKeys()
    w.releaseKeys()
    w.keys={}; w.routes={}; w.keyCount=0
    local directTouched=false
    for id=32,37 do
      local accepted=false
      if LED_STRIP_LENGTH>=38 then
        local ok,result=pcall(setRGBLedColor,id,0,0,0)
        accepted=ok and result==true
        if accepted then w.routes[id]="rgb"; directTouched=true end
      end
      if not accepted and type(setCFSLedColor)=="function" then
        local name="SW"..(id-31)
        local ok,result=pcall(setCFSLedColor,name,0,0,0)
        accepted=ok and result==true
        if accepted then
          w.routes[id]="cfs"
          -- A successful call confirms the API/name, NOT the user's two
          -- ON/OFF permission flags. Release the zero-valued probe immediately.
          pcall(setCFSLedColor,name)
        end
      end
      w.keys[id]=accepted
      if accepted then w.keyCount=w.keyCount+1 end
    end
    if directTouched then applyRGBLedColors() end
    w.last={}
  end
  function w.keyRoute(id)
    if not w.keys[id] then return "不可用" end
    return w.routes[id]=="cfs" and "Lua专用" or "直写"
  end
  local function writeKey(id,c)
    if w.routes[id]=="cfs" then
      if type(setCFSLedColor)~="function" then return false end
      local name="SW"..(id-31)
      local ok,result=pcall(setCFSLedColor,name,c[1],c[2],c[3])
      if ok and result==true then w.owned[id]=name; return true end
      return false
    end
    local ok,result=pcall(setRGBLedColor,id,c[1],c[2],c[3])
    return ok and result==true
  end
  function w.flush(force)
    local changed=force
    for id=0,37 do
      if id<32 or (w.keyEnabled and w.keys[id]) then
        local c=w.frame[id]
        local packed=c[1]*65536+c[2]*256+c[3]
        if w.last[id]~=packed then changed=true end
      end
    end
    if not changed then return false end
    for id=0,37 do
      if id<32 or (w.keyEnabled and w.keys[id]) then
        local c=w.frame[id]
        if id<32 then setRGBLedColor(id,c[1],c[2],c[3])
        elseif not writeKey(id,c) then
          if w.owned[id] and type(setCFSLedColor)=="function" then
            pcall(setCFSLedColor,w.owned[id]); w.owned[id]=nil
          end
          w.keys[id]=false; w.keyCount=w.keyCount-1
        end
        w.last[id]=c[1]*65536+c[2]*256+c[3]
      end
    end
    applyRGBLedColors()
    return true
  end
  return w
end

-- Calibration stores each group's six-o'clock LED and numeric clockwise sign.
-- A/B groups need not correspond to left/right hardware.
function M.ringId(c,group,step,pattern,angle)
  local base=group*16
  local bottom=group==0 and c.bottomA or c.bottomB
  local cw=(group==0 and c.cwA or c.cwB)==1 and 1 or -1
  local left=group==c.left
  local offset=0
  if angle==1 then offset=left and -1 or 1
  elseif angle==3 then offset=8
  elseif angle==4 then offset=left and 1 or -1 end
  local direction=left and 1 or -1
  if pattern==2 then direction=-direction
  elseif pattern==4 then direction=1
  elseif pattern==5 then direction=-1 end
  if pattern==3 then
    -- bottom, +1, -1, +2, -2, ..., opposite. Paired levels handled in render.
    local d=math.floor((step+1)/2)
    offset=offset+(step%2==1 and d or -d)
  else offset=offset+step*direction end
  return base+(bottom-base+offset*cw)%16
end
function M.render(w,c,progress,override)
  if not M.valid(c) then return end
  local o=override or {}
  local palette=o.palette or c.palette
  local pattern=o.pattern or c.pattern
  local angle=o.angle or c.angle
  local p=type(progress)=="number" and progress==progress and clamp(progress,0,1) or 0
  local keys=c.keys==1 and w.keyCount==6
  w.enableKeys(keys)
  local total=keys and 19 or 16
  local budget=p*total
  local light=c.brightness/100
  w.reset()
  local function paint(id,level,t)
    local r,g,b=M.color(palette,t)
    level=clamp(level,0,1)*light
    w.set(id,r*level,g*level,b*level)
  end
  if keys then
    for k=0,2 do
      local a,b=34-k,35+k
      paint(a,budget-k,k/(total-1)); paint(b,budget-k,k/(total-1))
    end
  end
  local lead=keys and 3 or 0
  for step=0,15 do
    local level=budget-lead-step
    local colorStep=step
    if pattern==3 and step>0 and step<15 then
      local first=1+2*math.floor((step-1)/2)
      level=(budget-lead-first)/2
      colorStep=first+0.5
    end
    for group=0,1 do
      paint(M.ringId(c,group,step,pattern,angle),level,(lead+colorStep)/(total-1))
    end
  end
  w.flush()
end

function M.smoother()
  local s={}
  function s.update(p,now,tau)
    if type(p)~="number" or p~=p then p=0 end
    p=clamp(p,0,1)
    local dt=s.time and now-s.time or 0
    if s.value==nil or dt<0 or dt>50 then s.value=p; s.target=p end
    s.time=now
    -- Hold the target through small ADC jitter, but always honour endpoints.
    if p==0 or p==1 or math.abs(p-s.target)>=0.002 then s.target=p end
    if p==0 or tau==0 then s.value=s.target
    elseif dt>0 then s.value=s.value+(s.target-s.value)*(1-math.exp(-dt/tau)) end
    if math.abs(s.target-s.value)<0.0002 then s.value=s.target end
    return s.value
  end
  return s
end
function M.runtime(preset)
  local w,c,s,last,lastRun,resume,active
  local function reload()
    c=M.load(); s=M.smoother(); w.last={}
  end
  local function init()
    w=M.writer(); last=nil; lastRun=nil; resume=false; active=false
    if M.hardware() then reload() end
  end
  local function run()
    if not w or not M.hardware() then return end
    local now=getTime()
    if not active or resume or (lastRun and (now<lastRun or now-lastRun>50)) then
      w.probeKeys(); reload(); resume=false; active=true
    end
    lastRun=now
    if last and now>=last and now-last<5 then return end
    last=now
    if not c or c.ready~=1 then w.enableKeys(false); w.reset(); w.flush(); return end
    local p=s.update(M.progress(c),now,c.smooth)
    M.render(w,c,p,preset)
  end
  -- Release assigned-switch colour overrides once on deactivation. Merely
  -- loading an inactive preset never acquires or releases anyone else's LEDs.
  return {init=init,run=run,background=function()
    if active then w.releaseKeys(); active=false end
    resume=true; last=nil
  end}
end
return M
