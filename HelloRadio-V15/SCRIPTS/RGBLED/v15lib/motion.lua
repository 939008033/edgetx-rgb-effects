-- Xu
--- 动态灯效：复用 v5 校准与灯珠输出，只有 jet 使用油门值。
-- 连续运行时不读 SD；这里不调用模型写入接口，也不依赖字符串对象方法。
local M={version=1}
-- 每秒循环次数；调整会改变整套动画速度，预览时长也要同步核对。
local rates={flow=1/8,breathe=1/5,comet=1/2.8,scan=1/4,aurora=1/9,jet=1}
--- 限制灯光计算的数值范围，防止亮度或时间差越界。
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
--- 生成周期为 1、值域为 0..1 的平滑余弦波。
local function wave(x) return (1-math.cos(2*math.pi*x))/2 end
--- 按 0..1 权重插值颜色分量，避免切换色标时跳变。
local function mix(a,b,t) return a+(b-a)*t end
--- 首尾颜色相接的色相环，避免旋转一周后突然跳色。
-- @param h 色相位置，以 1 为一个周期。
-- @return RGB 三个分量，范围 0..255。
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
--- 支持小数位置的彗星亮度，跨过灯珠和环接缝时保持连续。
-- @param distance 距离头部的逻辑灯位差，一圈 16 格。
-- @return 0..1 的亮度权重。
local function tail(distance)
  local d=(distance+8)%16-8
  if d<0 then return clamp(1+d,0,1) end
  return clamp(1-d/5,0,1)^2
end
--- 绘制并提交一帧灯光，所有硬件编号都经过公共校准映射。
-- @param core 公共 effects 模块。
-- @param w 当前实例的灯珠 writer。
-- @param c 有效且已完成校准的配置。
-- @param kind 本模块支持的灯效标识。
-- @param phase 动画周期位置，按模 1 处理。
-- @param progress jet 的油门进度 0..1；其他灯效忽略此值。
-- @return 成功渲染返回 true，配置或输入不满足要求返回 false。
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
      -- 叠加第二条空间波纹引入紫色，两个波形都在周期边界连续。
      local violet=wave(pos*2+phase)*0.45
      r,g,b=mix(r,180,violet),mix(g,15,violet),mix(b,255,violet)
      level=0.2+0.8*wave(pos+phase)
    else -- jet 仍按油门先点亮按键灯，再点亮环灯。
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
      -- 扫描从六点钟沿环的两侧到顶部再返回；其余灯效从内下角开始，左右镜像。
      paint(core.ringId(c,group,step,1,kind=="scan" and 2 or 1),step,false)
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
  assert(rates[kind],"V15: unknown animation")
  local w,c,s,idle,last,lastRun,active,phase
  --- 重新激活时重读配置并重置相位、滤波和输出缓存。
  local function reload()
    c=core.load(); s=core.smoother(); phase=0; last=nil; w.last={}
  end
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
      w.probeKeys(); reload(); active=true
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
    -- 自动灯效不依赖油门读数；仅 jet 需要有效油门进度。
    local p=kind=="jet" and s.update(core.progress(c),now,c.smooth) or 0
    local rate=kind=="jet" and (0.2+0.8*p) or rates[kind]
    phase=(phase+dt*rate)%1
    M.render(core,w,c,kind,phase,p)
  end
  -- 后台只归还本实例的覆盖；不清空其他正在运行的灯效。
  return {init=init,run=run,background=function()
    if active then w.releaseKeys(); active=false; idle=core.idle() end
    last=nil
  end}
end
-- 动态灯效单独加载，避免被 boot.lua 当成静态油门预设处理。
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
