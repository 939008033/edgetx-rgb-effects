-- Xu
--- 创意灯效使用固定周期和连续波形，复用校准及输出层，不写模型或通道。
local M={version=1}
-- 每秒循环次数；调整会改变整套动画速度，预览时长也要同步核对。
local rates={dual=1/4,wave=1/4,star=1/8,lava=1/8,beat=1/4,swap=1/8,nova=1/8,rotor=1/8}
--- 限制灯光计算的数值范围，防止亮度或时间差越界。
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
--- 生成周期为 1、值域为 0..1 的平滑余弦波。
local function wave(x) return (1-math.cos(2*math.pi*x))/2 end
--- 按 0..1 权重插值颜色分量，避免切换色标时跳变。
local function mix(a,b,t) return a+(b-a)*t end
--- 把环上距离映射成彗星拖尾；一圈为 16 格，头部支持小数位置。
local function tail(distance)
  local d=(distance+8)%16-8
  if d<0 then return clamp(1+d,0,1) end
  return clamp(1-d/4,0,1)^2
end
--- 在指定半宽内生成余弦脉冲，边界归零，用于两次连续心跳。
local function bump(x,width)
  if math.abs(x)>=width then return 0 end
  return (1+math.cos(math.pi*x/width))/2
end
--- 绘制并提交一帧灯光，所有硬件编号都经过公共校准映射。
-- @param core 公共 effects 模块。
-- @param w 当前实例的灯珠 writer。
-- @param c 有效且已完成校准的配置。
-- @param kind 本模块支持的灯效标识。
-- @param phase 动画周期位置，按模 1 处理。
-- @return 成功渲染返回 true，配置或输入不满足要求返回 false。
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
      -- 每个环内各有两条不同颜色的彗星，以相反方向旋转。
      r,g,b=255*b2,220*a,clamp(255*a+165*b2,0,255)
    elseif kind=="wave" then
      local front=phase*14
      local pulse=clamp(1-math.abs(height-front)/2,0,1)^2*wave(phase)
      r,g,b=mix(0,165,pulse),mix(90,235,pulse),255
      level=0.015+0.985*pulse
    elseif kind=="star" then
      -- 每颗灯固定相位偏移，复现相同节奏，避免随机开关造成突兀闪烁。
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
    else -- rotor 使用四片平滑叶片，青粉配色在周期边界闭合。
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
      -- 以校准后的六点钟为起点，左侧顺时针、右侧逆时针。
      paint(core.ringId(c,group,step,1,2),step,false,side)
    end
  end
  w.flush()
  return true
end
--- 创建独立灯效实例，按 20 Hz 更新；停用后归还自己持有的按键灯。
-- @param core 公共 effects 模块。
-- @param kind 本模块支持的灯效标识，未知值会触发断言。
-- @return EdgeTX 的 init/run/background 回调表。
function M.runtime(core,kind)
  assert(rates[kind],"V15: unknown creative effect")
  local w,c,idle,last,lastRun,active,phase
  --- 只建立本实例状态；直到真正启用时才探测灯珠和读取校准。
  local function init()
    w=core.writer(); idle=core.idle(); c=nil; last=nil; lastRun=nil; active=false; phase=0
  end
  --- 处理一次固件调度，先检查校准和闲置状态，再推进动画。
  local function run()
    if not w or not core.hardware() then return end
    local now=getTime()
    -- getTime 单位是 10 ms。中断超过半秒或时钟回退时重新加载，避免沿用旧状态。
    if not active or (lastRun and (now<lastRun or now-lastRun>50)) then
      w.probeKeys(); c=core.load(); phase=0; last=nil; w.last={}; active=true
    end
    lastRun=now
    -- 50 ms 最多刷新一次；不随固件调度频率额外增加灯效运算。
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
  -- 后台只归还本实例的覆盖；不清空其他正在运行的灯效。
  return {init=init,run=run,background=function()
    if active then w.releaseKeys(); active=false; idle=core.idle() end
    last=nil
  end}
end
--- 加载公共库并检查接口，将预设连接到对应动画引擎。
-- @param kind 本模块支持的灯效标识。
-- @return init/run/background 回调；依赖缺失在 init 时给出明确错误。
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
