-- Xu
-- V15 dynamic add-on 1.0. Uses the existing v5 calibration and LED writer.
-- No model writes, random flashing, frame-time SD access or string methods.
local M={version=1}
local rates={flow=1/8,breathe=1/5,comet=1/2.8,scan=1/4,aurora=1/9,jet=1}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function wave(x) return (1-math.cos(2*math.pi*x))/2 end
local function mix(a,b,t) return a+(b-a)*t end
-- Closed hue loop: unlike a linear palette, its endpoints have no colour seam.
local function rainbow(h)
  local p=(h%1)*6
  local n=math.floor(p)
  local v=(p-n)*255
  if n==0 then return 255,v,0
  elseif n==1 then return 255-v,255,0
  elseif n==2 then return 0,255,v
  elseif n==3 then return 0,255-v,255
  elseif n==4 then return v,0,255
  else return 255,0,255-v end
end
-- Fractional head + trailing falloff; continuous across LED and ring seams.
local function tail(distance)
  local d=(distance+8)%16-8
  if d<0 then return clamp(1+d,0,1) end
  return clamp(1-d/5,0,1)^2
end
function M.render(core,w,c,kind,phase,progress)
  if not core.valid(c) or c.ready~=1 or not rates[kind] then return false end
  phase=phase%1
  local p=type(progress)=="number" and progress==progress and clamp(progress,0,1) or 0
  local keys=c.keys==1 and w.keyCount==6
  local lead=keys and 3 or 0
  local total=lead+16
  local budget=p*total
  local brightness=c.brightness/100
  w.enableKeys(keys)
  w.reset()
  local function paint(id,step,key)
    local r,g,b,level=0,0,0,1
    local pos=key and step/3 or (lead+step)/(total-1)
    if kind=="flow" then
      r,g,b=rainbow(pos-phase)
    elseif kind=="breathe" then
      local hue=wave(phase)
      r,g,b=mix(0,180,hue),mix(210,20,hue),255
      level=0.06+0.94*hue
    elseif kind=="comet" then
      r,g,b=65,200,255
      if key then level=0.06+0.7*wave(phase-step/5)
      else level=tail(phase*16-step) end
    elseif kind=="scan" then
      if key then
        r,g,b=0,190,255
        level=0.05+0.75*clamp(1-math.abs(wave(phase)*3-step)/1.5,0,1)
      else
        local height=math.min(step,16-step)
        r,g,b=core.color(2,height/8)
        level=clamp(1-math.abs(height-wave(phase)*8)/2.5,0,1)^2
      end
    elseif kind=="aurora" then
      local hue=wave(pos-phase)
      r,g,b=core.color(5,hue)
      -- A second, slower spatial band adds violet without a discontinuous reset.
      local violet=wave(pos*2+phase)*0.45
      r,g,b=mix(r,180,violet),mix(g,15,violet),mix(b,255,violet)
      level=0.2+0.8*wave(pos+phase)
    else -- jet: keep the original keys-first throttle envelope.
      local index=key and step or lead+step
      r,g,b=core.color(3,index/(total-1))
      level=clamp(budget-index,0,1)
      if not key then level=level*(0.55+0.45*tail(phase*16-step)) end
    end
    level=level*brightness
    w.set(id,r*level,g*level,b*level)
  end
  if keys then
    for k=0,2 do paint(34-k,k,true); paint(35+k,k,true) end
  end
  for step=0,15 do
    for group=0,1 do
      -- Scan moves from six to twelve and back on BOTH sides of each ring.
      -- Others start at the inner bottom corner, left clockwise/right CCW.
      paint(core.ringId(c,group,step,1,kind=="scan" and 2 or 1),step,false)
    end
  end
  w.flush()
  return true
end
function M.runtime(core,kind)
  assert(rates[kind],"V15: unknown animation")
  local w,c,s,idle,last,lastRun,active,phase
  local function reload()
    c=core.load(); s=core.smoother(); phase=0; last=nil; w.last={}
  end
  local function init()
    w=core.writer(); idle=core.idle(); c=nil; last=nil; lastRun=nil; active=false; phase=0
  end
  local function run()
    if not w or not core.hardware() then return end
    local now=getTime()
    if not active or (lastRun and (now<lastRun or now-lastRun>50)) then
      w.probeKeys(); reload(); active=true
    end
    lastRun=now
    if last and now>=last and now-last<5 then return end
    local dt=last and clamp(now-last,0,50)/100 or 0
    last=now
    if not c or c.ready~=1 then
      w.enableKeys(false); w.reset(); w.flush(); return
    end
    if idle.apply(w,c,now) then return end
    -- Exhibition effects are independent of throttle, including missing inputs.
    local p=kind=="jet" and s.update(core.progress(c),now,c.smooth) or 0
    local rate=kind=="jet" and (0.2+0.8*p) or rates[kind]
    phase=(phase+dt*rate)%1
    M.render(core,w,c,kind,phase,p)
  end
  return {init=init,run=run,background=function()
    if active then w.releaseKeys(); active=false; idle=core.idle() end
    last=nil
  end}
end
-- Dedicated loader: old boot.lua cannot accidentally treat an animation as
-- a throttle preset. Existing v5.1 entry points and UI remain untouched.
function M.entry(kind)
  local runtime
  return {init=function()
    runtime=nil
    local ok,core=pcall(function()
      local f=loadScript("/SCRIPTS/RGBLED/v15lib/effects.lua","tx")
      return f and f()
    end)
    if not ok or type(core)~="table" or core.version~=5 then
      error("V15: copy all SCRIPTS (effects.lua missing)")
    end
    if not core.hardware() then error("V15: RGB API unavailable") end
    runtime=M.runtime(core,kind); runtime.init()
  end,run=function() if runtime then runtime.run() end end,
  background=function() if runtime then runtime.background() end end}
end
return M
