-- Host-only preview capture. Executes unchanged RGBLED entry scripts with mock hardware.
local root,catalogFile,configFile=arg[1],arg[2],arg[3]
assert(root and catalogFile and configFile,'root catalog.lua config.lua required')
local hostIO,hostLoad=io,loadfile
local catalog=assert(hostLoad(catalogFile))()
assert(#catalog==32)
local cfgText=assert(hostLoad(configFile))()
local ticks,axes,buffer=0,{0,-1,0,0},{}
LED_STRIP_LENGTH=38
function getTime() return ticks end
function getStickMode() return 2 end
function getValue(id)
 local n=({rud=1,thr=2,ail=3,ele=4})[id]
 assert(n,'Unexpected input source: '..tostring(id)); return axes[n]*1024
end
function getOutputValue() return axes[2]*1024 end
function setRGBLedColor(id,r,g,b)
 assert(id>=0 and id<38 and id==math.floor(id))
 for _,v in ipairs({r,g,b}) do assert(v>=0 and v<=255 and v==math.floor(v)) end
 buffer[id]={r,g,b}; return true
end
function applyRGBLedColors() end
function loadScript(p,mode)
 assert(mode=='tx'); assert(string.find(p,'/SCRIPTS/RGBLED/v15lib/',1,true)==1)
 return hostLoad(root..'/HelloRadio-V15'..p)
end
io={
 open=function(p,mode)
  assert(mode=='r','Preview must never write radio data')
  assert(p=='/SCRIPTS/RGBLED/v15lib/layout.cfg'); return {text=cfgText}
 end,
 read=function(f,n) return string.sub(f.text,1,n) end,
 close=function() end
}
local core=assert(hostLoad(root..'/HelloRadio-V15/SCRIPTS/RGBLED/v15lib/effects.lua'))()
local c=assert(core.load()); assert(c.ready==1)
local states={}
for i,entry in ipairs(catalog) do
 buffer={}; for j=0,37 do buffer[j]={0,0,0} end
 local rt=assert(hostLoad(root..'/HelloRadio-V15/SCRIPTS/RGBLED/'..entry..'.lua'))()
 rt.init(); states[i]={rt=rt,leds=buffer,activeFrames=0}
end
local function throttle(t)
 if t<.6 then return 0 elseif t<4.6 then return (t-.6)/4
 elseif t<6.2 then return 1 elseif t<10.2 then return 1-(t-6.2)/4 else return 0 end
end
local neutral={0,-1,0,0}
local poses={out={-.9,-1,.9,0},inside={.9,-1,-.9,0},right={.9,-1,.9,0},left={-.9,-1,-.9,0}}
local function stickInput(name,t)
 local a=t*math.pi/6
 if name=='C01-aim' then return {.85*math.sin(2*a),-.85*math.cos(2*a),-.85*math.sin(2*a),.85*math.cos(2*a)}
 elseif name=='C02-mix' then return {math.sin(a),-.8*math.cos(a),.8*math.sin(2*a),.8*math.cos(a)}
 elseif name=='C03-spin' then return {.8*math.sin(a),math.sin(2*a),-.8*math.sin(a),-math.sin(2*a)} end
 if t>=.4 and t<1.2 then return poses.out elseif t>=1.4 and t<2.2 then return poses.inside
 elseif t>=4.3 and t<5.1 then return poses.inside elseif t>=5.3 and t<6.1 then return poses.out
 elseif t>=8.3 and t<9.1 then return poses.right elseif t>=9.3 and t<10.1 then return poses.left end
 return neutral
end
for frame=0,239 do
 ticks=frame*5; local t=frame/20; local panels={}
 for i,entry in ipairs(catalog) do
  local s=states[i]; buffer=s.leds
  axes=string.sub(entry,1,1)=='C' and stickInput(entry,t) or {0,2*throttle(t)-1,0,0}
  s.rt.run()
  local values={}; local total=0
  for side=0,1 do
   local group=side==0 and c.left or 1-c.left
   for step=0,15 do
    local rgb=assert(buffer[core.ringId(c,group,step,4,2)])
    values[#values+1]='['..table.concat(rgb,',')..']'; total=total+rgb[1]+rgb[2]+rgb[3]
   end
  end
  for id=32,37 do values[#values+1]='['..table.concat(buffer[id],',')..']' end
  values[#values+1]='['..table.concat(axes,',')..']'
  values[#values+1]=string.format('%.4f',throttle(t))
  panels[#panels+1]='['..table.concat(values,',')..']'
  if total>0 then s.activeFrames=s.activeFrames+1 end
 end
 print('FRAME ['..table.concat(panels,',')..']')
end
io=hostIO
for i,s in ipairs(states) do assert(s.activeFrames>20,'No animation captured: '..catalog[i]) end
print('CAPTURE OK: 32 unchanged entry scripts, 240 frames, 20 Hz, 12 seconds, all entries lit.')
