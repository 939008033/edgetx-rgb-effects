-- Xu
-- V15 creative add-on 1.0. Independent of the original throttle/motion engines.
-- Fixed, continuous animations; no random frames or model/channel writes.
local M={version=1}
local rates={dual=1/4,wave=1/4,star=1/8,lava=1/8,beat=1/4,swap=1/8,nova=1/8,rotor=1/8}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function wave(x) return (1-math.cos(2*math.pi*x))/2 end
local function mix(a,b,t) return a+(b-a)*t end
local function tail(distance)
  local d=(distance+8)%16-8
  if d<0 then return clamp(1+d,0,1) end
  return clamp(1-d/4,0,1)^2
end
local function bump(x,width)
  if math.abs(x)>=width then return 0 end
  return (1+math.cos(math.pi*x/width))/2
end
function M.render(core,w,c,kind,phase)
  if not core.valid(c) or c.ready~=1 or not rates[kind] then return false end
  phase=phase%1
  local keys=c.keys==1 and w.keyCount==6
  local lead=keys and 3 or 0
  local total=lead+16
  local brightness=c.brightness/100
  w.enableKeys(keys); w.reset()
  local function paint(id,step,key,side)
    local r,g,b,level=0,0,0,1
    local pos=key and step/3 or step/16
    local height=key and step or 3+math.min(step,16-step)
    if kind=="dual" then
      local a,b2
      if key then a=wave(phase-step/6); b2=wave(-phase-step/6+0.5)
      else a=tail(phase*16-step); b2=tail(-phase*16-step+8) end
      -- Two differently coloured comets counter-rotate within EACH ring.
      r,g,b=255*b2,220*a,clamp(255*a+165*b2,0,255)
    elseif kind=="wave" then
      local front=phase*14
      local pulse=clamp(1-math.abs(height-front)/2,0,1)^2*wave(phase)
      r,g,b=mix(0,165,pulse),mix(90,235,pulse),255
      level=0.015+0.985*pulse
    elseif kind=="star" then
      -- Stable per-bead offsets replace random on/off flashes.
      local seed=(step*0.61803398875+side*0.37+(key and 0.19 or 0))%1
      local twinkle=wave(phase*(1+step%2)+seed)^7
      local hue=wave(phase+seed)
      r,g,b=mix(50,200,hue),mix(130,210,twinkle),255
      level=0.02+0.98*twinkle
    elseif kind=="lava" then
      local heat=0.65*wave(pos-phase)+0.35*wave(pos*3+phase)
      r,g,b=220+35*heat,5+185*heat^2,25*heat^5
      level=0.1+0.9*heat^2
    elseif kind=="beat" then
      local delay=key and step*0.012 or math.min(step,16-step)*0.006
      local t=(phase-delay)%1
      local pulse=math.max(bump(t-0.25,0.10),0.7*bump(t-0.48,0.12))
      r,g,b=255,25+45*pulse,65+55*pulse
      level=0.015+0.985*pulse
    elseif kind=="swap" then
      local amount=wave(phase)
      if side==0 then r,g,b=0,210,255; level=0.025+0.975*amount
      else r,g,b=255,25,150; level=0.025+0.975*(1-amount) end
    elseif kind=="nova" then
      local index=key and step or lead+step
      r,g,b=core.color(4,index/(total-1))
      if phase<0.62 then
        level=clamp(phase/0.62*total-index,0,1)
      else
        local burst=clamp((phase-0.62)/0.10,0,1)
        r,g,b=mix(r,255,burst),mix(g,255,burst),mix(b,255,burst)
        level=phase<0.72 and 1 or clamp((1-phase)/0.28,0,1)^2
      end
    else -- rotor: four softly shaped blades, with a closed cyan/pink cycle.
      local hue=wave(pos+phase)
      r,g,b=mix(0,230,hue),mix(215,20,hue),255
      level=0.025+0.975*(1-wave((pos-phase)*4))^4
    end
    level=level*brightness
    w.set(id,r*level,g*level,b*level)
  end
  if keys then
    for k=0,2 do paint(34-k,k,true,0); paint(35+k,k,true,1) end
  end
  for group=0,1 do
    local side=group==c.left and 0 or 1
    for step=0,15 do
      -- Geometry is physically calibrated: bottom origin, left CW/right CCW.
      paint(core.ringId(c,group,step,1,2),step,false,side)
    end
  end
  w.flush()
  return true
end
function M.runtime(core,kind)
  assert(rates[kind],"V15: unknown creative effect")
  local w,c,idle,last,lastRun,active,phase
  local function init()
    w=core.writer(); idle=core.idle(); c=nil; last=nil; lastRun=nil; active=false; phase=0
  end
  local function run()
    if not w or not core.hardware() then return end
    local now=getTime()
    if not active or (lastRun and (now<lastRun or now-lastRun>50)) then
      w.probeKeys(); c=core.load(); phase=0; last=nil; w.last={}; active=true
    end
    lastRun=now
    if last and now>=last and now-last<5 then return end
    local dt=last and clamp(now-last,0,50)/100 or 0
    last=now
    if not c or c.ready~=1 then
      w.enableKeys(false); w.reset(); w.flush(); return
    end
    if idle.apply(w,c,now) then return end
    phase=(phase+dt*rates[kind])%1
    M.render(core,w,c,kind,phase)
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
    if not ok or type(core)~="table" or core.version~=5 then
      error("V15: copy all SCRIPTS (effects.lua missing)")
    end
    if not core.hardware() then error("V15: RGB API unavailable") end
    runtime=M.runtime(core,kind); runtime.init()
  end,run=function() if runtime then runtime.run() end end,
  background=function() if runtime then runtime.background() end end}
end
return M
