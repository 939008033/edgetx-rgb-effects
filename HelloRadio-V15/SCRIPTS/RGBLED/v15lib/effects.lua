-- Xu
--- V15 共用配置、灯珠输出和油门灯效。摇杆与通道只读，配置只写 layout.cfg。
-- 已分配功能的 SW1..SW6 还受固件开、关两种状态的覆盖权限限制。
-- version=5 是配置兼容标识，revision 是显示版本；改显示版本不应让已有校准失效。
local M={version=5,revision="5.2",path="/SCRIPTS/RGBLED/v15lib/layout.cfg"}
--- 将数值限制在闭区间内，用于亮度和输入归一化。
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
--- 校验配置整数及边界，同时拒绝非数值、NaN 和无穷大。
local function int(v,a,b)
  return type(v)=="number" and v==math.floor(v) and v>=a and v<=b
end
-- fields 与 ranges 按位置对应，序列化顺序固定。新增字段要同时处理旧文件缺省值。
-- bottomA/B 为各环六点钟的绝对编号；cwA/B 为编号递增是否顺时针；left 指定左环组号。
-- source=0 读取油门，1..32 读取对应通道；这些选择和 reverse 仅影响灯光。
-- brightness 为百分比，smooth 为 10 ms 时间常数，idleMinutes 只允许 0/5/10/15 分钟。
-- palette/pattern/angle 仍供 B01 和旧配置使用，工具不显示菜单也不能删掉这些字段。
local fields={"bottomA","bottomB","cwA","cwB","left","ready","source","reverse",
  "brightness","smooth","palette","pattern","angle","keys","idleMinutes"}
local ranges={{0,15},{16,31},{0,1},{0,1},{0,1},{0,1},{0,32},{0,1},
  {5,100},{0,20},{1,8},{1,5},{1,4},{0,1},{0,15}}
--- 返回一份独立的初始配置；未校准时禁止正常灯效，闲置熄灯默认关闭。
-- @return 新配置表，亮度默认 40%，不与其他实例共享可变状态。
function M.defaults()
  return {bottomA=0,bottomB=16,cwA=1,cwB=1,left=0,ready=0,source=0,
    reverse=0,brightness=40,smooth=8,palette=1,pattern=1,angle=1,keys=1,idleMinutes=0}
end
--- 检查完整配置，避免残缺文件被当成有效校准。
-- @param c 待检查的配置表，也可传 nil。
-- @return 全部字段和枚举约束满足时为 true。
function M.valid(c)
  if type(c)~="table" then return false end
  for i,k in ipairs(fields) do if not int(c[k],ranges[i][1],ranges[i][2]) then return false end end
  return c.idleMinutes%5==0
end
--- 确认 RGB 输出接口及至少 32 颗环灯可用；按键灯能力另行探测。
-- @return 当前固件具备基础灯环接口时为 true。
function M.hardware()
  return type(setRGBLedColor)=="function" and type(applyRGBLedColors)=="function"
    and type(LED_STRIP_LENGTH)=="number" and LED_STRIP_LENGTH>=32
end
--- 最多读取 1024 字节的灯效配置，并在读取异常时先关闭文件。
-- @return 配置文本；文件无法打开时返回 nil，读取异常交由调用方捕获。
local function readText()
  local f=io.open(M.path,"r")
  if not f then return nil end
  local ok,text=pcall(io.read,f,1024)
  io.close(f)
  if not ok then error(text) end
  return text
end
--- 读取配置并兼容旧格式；不在这里自动覆盖用户文件。
-- @return 有效配置或 nil。
-- @return v1 返回 legacy；失败返回 missing 或 invalid；正常 v5 无附加状态。
function M.load()
  local ok,text=pcall(readText)
  if not ok or type(text)~="string" then return nil,"missing" end
  local legacy=string.match(text,"^V15THR1\n")~=nil
  if not legacy and not string.match(text,"^V15THR5\n") then return nil,"invalid" end
  local c={}
  for k,v in string.gmatch(text,"([%a]+)=(%d+)\n") do c[k]=tonumber(v) end
  if c.idleMinutes==nil and string.find(text,"\nidleMinutes=",1,true) then return nil,"invalid" end
  if c.idleMinutes==nil then c.idleMinutes=0 end -- 旧版 v5 没有此字段，按关闭处理，避免升级后改变用户设置。
  if legacy then
    for _,k in ipairs({"bottomA","bottomB","source","reverse","brightness"}) do
      if c[k]==nil then return nil,"invalid" end
    end
    local d=M.defaults()
    for k,v in pairs(c) do d[k]=v end
    d.ready=0 -- v1 只记录底部灯珠，无法确定方向和左右归属，必须重新校准。
    c=d
  end
  if not M.valid(c) then return nil,"invalid" end
  return c,legacy and "legacy" or nil
end
--- 保存已完成的校准，关闭文件后逐字回读确认；只写本库的 layout.cfg。
-- @param c 通过 valid 且 ready=1 的配置。
-- @return 写入及回读都成功时为 true；失败不代表原文件仍然完整。
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
--- 只读选定输入，并把 -1024..1024 映射为灯光进度。
-- @param c 包含 source、reverse 的有效配置；通道接口使用从零起的编号。
-- @return 限制到 0..1 的进度；接口缺失、异常或无效输入返回 nil。
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
--- 在固定色标之间线性插值，保持油门灯效的空间渐变。
-- @param palette 配色编号 1..8，未知编号回退到彩虹。
-- @param t 色带位置，超出 0..1 的部分会截断。
-- @return 红、绿、蓝三个分量，取整由 writer 统一完成。
function M.color(palette,t)
  local stops=palettes[palette] or palettes[1]
  local p=clamp(t,0,1)*(#stops-1)
  local i=math.min(#stops,math.floor(p)+1)
  local a,b=stops[i],stops[math.min(#stops,i+1)]
  local f=p-math.floor(p)
  return a[1]+(b[1]-a[1])*f,a[2]+(b[2]-a[2])*f,a[3]+(b[3]-a[3])*f
end

--- 创建独立的灯珠缓冲和输出缓存；绘制整帧后统一提交，避免先熄灭再点亮。
-- @return 包含 set/reset/flush 和按键灯控制方法的写入器。
function M.writer()
  -- frame 是本帧 RGB，last 是已提交的打包色值，routes 记录直写或 CFS 路径。
  -- owned 只记录本实例成功取得的 CFS 覆盖，不能由全局按键列表代替。
  local w={frame={},last={},keys={},keyCount=0,routes={},owned={},keyEnabled=true}
  for id=0,37 do w.frame[id]={0,0,0} end
  --- 写入本帧缓冲，不立即调用固件。
  -- @param id 灯珠编号 0..37；调用方必须保证编号有效。
  -- @param r 红色分量，限制到 0..255 后四舍五入。
  -- @param g 绿色分量，处理方式同 r。
  -- @param b 蓝色分量，处理方式同 r。
  function w.set(id,r,g,b)
    local p=w.frame[id]
    p[1]=math.floor(clamp(r,0,255)+0.5)
    p[2]=math.floor(clamp(g,0,255)+0.5)
    p[3]=math.floor(clamp(b,0,255)+0.5)
  end
  --- 清空待绘制帧，保留已提交颜色缓存；硬件到 flush 才更新。
  function w.reset()
    for id=0,37 do
      local p=w.frame[id]
      p[1],p[2],p[3]=0,0,0
    end
  end
  --- 归还本实例持有的功能按键灯覆盖，不清理其他实例或固件的灯色。
  function w.releaseKeys()
    -- 只释放本实例实际设置过的覆盖。后台预设不能撤销正在运行的预设所持有的灯色。
    for id,name in pairs(w.owned) do
      if type(setCFSLedColor)=="function" then pcall(setCFSLedColor,name) end
      w.last[id]=nil
    end
    w.owned={}
  end
  --- 切换六键灯参与状态；关闭时归还覆盖并熄灭曾由本实例直写的按键灯。
  -- @param enabled 是否允许本实例继续输出按键灯。
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
  --- 激活时探测六键的输出路径；先尝试直写，失败再尝试功能开关灯接口。
  -- 不在每帧调用，以免反复申请和释放灯色覆盖。
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
          -- 返回成功只说明接口和名称有效，不代表开、关两种状态都允许覆盖。
          -- 探测后立即释放黑色覆盖，避免占住固件的功能指示灯。
          pcall(setCFSLedColor,name)
        end
      end
      w.keys[id]=accepted
      if accepted then w.keyCount=w.keyCount+1 end
    end
    if directTouched then applyRGBLedColors() end
    w.last={}
  end
  --- 返回按键灯的诊断名称，不改变控制权限。
  -- @param id 按键灯编号 32..37。
  -- @return 不可用、Lua专用或直写。
  function w.keyRoute(id)
    if not w.keys[id] then return "不可用" end
    return w.routes[id]=="cfs" and "Lua专用" or "直写"
  end
  --- 通过已探测的路径输出按键灯，并记录成功取得的覆盖归属。
  -- @param id 按键灯编号 32..37。
  -- @param c 已取整的三个 RGB 分量。
  -- @return 固件明确接受本次输出时为 true。
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
  --- 提交本帧差异；按键写入失败时停止向该键输出，防止持续争抢控制。
  -- @param force 可选；为 true 时重写当前允许控制的全部灯珠。
  -- @return 调用过 applyRGBLedColors 时为 true，整帧未变化时为 false。
  function w.flush(force)
    local changed=force
    -- 固件保留上次颜色，因此只写有变化的灯珠，最后统一 apply。
    -- 不要在这里先清空硬件灯带，否则静止油门也会出现闪烁和额外调用。
    for id=0,37 do
      if id<32 or (w.keyEnabled and w.keys[id]) then
        local c=w.frame[id]
        local packed=c[1]*65536+c[2]*256+c[3]
        if force or w.last[id]~=packed then
          changed=true
          if id<32 then setRGBLedColor(id,c[1],c[2],c[3])
          elseif not writeKey(id,c) then
            if w.owned[id] and type(setCFSLedColor)=="function" then
              pcall(setCFSLedColor,w.owned[id]); w.owned[id]=nil
            end
            w.keys[id]=false; w.keyCount=w.keyCount-1
          end
          w.last[id]=packed
        end
      end
    end
    if not changed then return false end
    applyRGBLedColors()
    return true
  end
  return w
end

-- A/B 是接线编号，不固定对应左右；六点钟位置和顺时针方向以校准结果为准。
--- 把逻辑灯位换算成校准后的硬件编号，所有灯效共用此几何映射。
-- @param c 含六点钟、左右归属和编号方向的校准配置。
-- @param group 接线组号 0 或 1。
-- @param step 逻辑位置 0..15。
-- @param pattern 走向编号 1..5，对应 patternNames。
-- @param angle 起点编号 1..4，对应 angleNames。
-- @return 所属灯环内的绝对编号 0..31。
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
    -- 两侧展开依次取底部、+1、-1、+2、-2，最后到顶部；成对亮度由 render 分配。
    local d=math.floor((step+1)/2)
    offset=offset+(step%2==1 and d or -d)
  else offset=offset+step*direction end
  return base+(bottom-base+offset*cw)%16
end
--- 绘制油门进度条：每侧先填三颗按键灯，再填十六颗环灯。
-- @param w 已探测按键灯的 writer。
-- @param c 有效配置；运行入口负责检查 ready。
-- @param progress 亮灯进度 0..1，无效输入按零处理。
-- @param override 可选预设，仅覆盖 palette/pattern/angle，不修改配置表。
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

--- 创建油门平滑器；时间差参与滤波，避免不同调用频率改变手感。
-- @return 独立的平滑状态及 update 方法。
function M.smoother()
  local s={}
  --- 按经过时间推进滤波，时钟回退或停顿超过半秒时直接接纳当前输入。
  -- @param p 目标进度 0..1，缺失或 NaN 按零处理。
  -- @param now getTime 的 10 ms 计数。
  -- @param tau 平滑时间常数，单位 10 ms；0 表示关闭平滑。
  -- @return 平滑后的灯光进度。
  function s.update(p,now,tau)
    if type(p)~="number" or p~=p then p=0 end
    p=clamp(p,0,1)
    local dt=s.time and now-s.time or 0
    if s.value==nil or dt<0 or dt>50 then s.value=p; s.target=p end
    s.time=now
    -- 小于 0.2% 的采样抖动不更新目标；零位和满量程始终响应，零位立即熄灯。
    if p==0 or p==1 or math.abs(p-s.target)>=0.002 then s.target=p end
    if p==0 or tau==0 then s.value=s.target
    elseif dt>0 then s.value=s.value+(s.target-s.value)*(1-math.exp(-dt/tau)) end
    if math.abs(s.target-s.value)<0.0002 then s.value=s.target end
    return s.value
  end
  return s
end

--- 创建闲置计时器，只监测物理输入，避免遥测或混控变化让灯一直不休眠。
-- RGB 特殊功能收不到菜单和触摸事件；校准工具通过 touch 补充自己的操作。
-- @return 带 touch/apply 方法及 sleeping 状态的计时器。
function M.idle()
  local s={sleeping=false}
  local inputs,lastActive,lastTime,minutes
  --- 判断物理输入能否参与差值计算，排除缺失、NaN 和无穷大。
  local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
  --- 首次启用闲置熄灯时收集固件支持的物理输入，避免每帧重复查询名称。
  local function discover()
    inputs={}
    --- 按来源名称解析输入；不存在的旋钮、开关或功能键直接跳过。
    -- @param name 固件输入名称。
    -- @param threshold 相对上次有效输入的最小变化量，单位为固件原始输入值。
    -- @param displayName SW1..SW6 使用显示名称接口，其余使用字段信息接口。
    local function add(name,threshold,displayName)
      local id=name
      local lookup=getFieldInfo
      if displayName then lookup=getSourceIndex end
      if type(lookup)=="function" then
        local ok,value=pcall(lookup,name)
        if displayName then id=ok and value or nil
        else id=ok and type(value)=="table" and value.desc~="" and value.id or nil end
      elseif displayName then return end
      if id~=nil and id~=false then inputs[#inputs+1]={id=id,threshold=threshold} end
    end
    -- 模拟量至少变化 16 才唤醒，过滤采样抖动；微调和开关按最小一级变化检测。
    for _,name in ipairs({"rud","ele","thr","ail","s1","s2","ls","rs"}) do add(name,16) end
    for _,name in ipairs({"trim-rud","trim-ele","trim-thr","trim-ail"}) do add(name,1) end
    for code=string.byte("a"),string.byte("z") do add("s"..string.char(code),1) end
    for i=1,6 do add("SW"..i,1,true) end
  end
  --- 记录一次用户活动并清除休眠状态；不在这里写灯或保存设置。
  -- @param now getTime 的 10 ms 计数。
  function s.touch(now)
    lastActive=now; s.sleeping=false
  end
  --- 检测活动并处理超时；休眠时提交全黑帧，调用方应跳过后续动画计算。
  -- @param w 当前灯效的 writer，只熄灭该实例可控制的灯。
  -- @param c 配置；idleMinutes 缺失或为 0 时关闭超时。
  -- @param now getTime 的 10 ms 计数，回退时重新计时。
  -- @param event 可选界面事件；非零数值视为活动。
  -- @return 是否已休眠；后续物理操作会重新计时并唤醒。
  function s.apply(w,c,now,event)
    local timeout=c.idleMinutes or 0
    if timeout==0 then
      minutes=0; lastTime=now; s.touch(now); return false
    end
    if not inputs then discover() end
    if not lastActive or timeout~=minutes or (lastTime and now<lastTime) then s.touch(now) end
    minutes=timeout; lastTime=now
    if type(event)=="number" and event~=0 then s.touch(now) end
    if type(getValue)=="function" then
      for _,input in ipairs(inputs) do
        local ok,value=pcall(getValue,input.id)
        if ok and finite(value) then
          if input.value==nil then input.value=value
          elseif math.abs(value-input.value)>=input.threshold then
            input.value=value; s.touch(now)
          end
        end
      end
    end
    -- getTime 每秒 100 个计数，因此一分钟为 6000；这里不能用毫秒直接比较。
    s.sleeping=now-lastActive>=timeout*6000
    if s.sleeping then w.reset(); w.flush() end
    return s.sleeping
  end
  return s
end

--- 创建油门灯效实例，按 20 Hz 更新，并在重新激活时读取配置。
-- @param preset 可选的配色、走向和起点覆盖表。
-- @return EdgeTX 使用的 init/run/background 回调表。
function M.runtime(preset)
  local w,c,s,idle,last,lastRun,resume,active
  --- 只在初始化或重新激活时读取 SD，并清掉旧滤波和输出缓存。
  local function reload()
    c=M.load(); s=M.smoother(); w.last={}
  end
  --- 建立实例状态；初始化不取得按键灯覆盖，避免未启用的预设抢灯。
  local function init()
    w=M.writer(); idle=M.idle(); last=nil; lastRun=nil; resume=false; active=false
    if M.hardware() then reload() end
  end
  --- 处理一次固件调度；校准无效或已休眠时停止正常渲染。
  local function run()
    if not w or not M.hardware() then return end
    local now=getTime()
    if not active or resume or (lastRun and (now<lastRun or now-lastRun>50)) then
      w.probeKeys(); reload(); resume=false; active=true
    end
    lastRun=now
    -- 5 个计数为 50 ms，限制为 20 Hz；50 个计数的调度间断视为重新激活。
    if last and now>=last and now-last<5 then return end
    last=now
    if not c or c.ready~=1 then w.enableKeys(false); w.reset(); w.flush(); return end
    if idle.apply(w,c,now) then return end
    local p=s.update(M.progress(c),now,c.smooth)
    M.render(w,c,p,preset)
  end
  -- 停用时只释放本实例的按键灯覆盖；从未启用的预设不能干预其他实例。
  return {init=init,run=run,background=function()
    if active then w.releaseKeys(); active=false; idle=M.idle() end
    resume=true; last=nil
  end}
end
return M
