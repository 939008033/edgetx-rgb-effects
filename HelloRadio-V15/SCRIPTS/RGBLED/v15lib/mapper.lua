-- Xu
--- 校准与共用设置工具。回调只标记重建，由下一次 run 统一更新 LVGL。
-- 这里只保存灯效 layout.cfg；不写模型、通道或遥控器系统配置。
local core,c,w,idle,problem
local phase,selected,page,note=1,0,"cal",""
local dirty,rebuild,exiting=true,true,false
local lastLed,lastIdle,wasSleeping
-- 选项值与配置校验一致；新增档位时须同步 effects.lua 的边界和测试。
local brightness={20,40,60,80,100}
local smooth={0,4,8,12,20}
local idleMinutes={0,5,10,15}
--- 界面操作同时重置闲置计时，使校准灯在用户操作后唤醒。
local function touch()
  if idle then idle.touch(getTime()); lastIdle=nil end
end
--- 按四步校准流程取得当前接线组：前两步为 A，后两步为 B。
local function group() return phase<=2 and 0 or 1 end
--- 记录待进入页面；实际重建留到 run，避免销毁仍在执行回调的控件。
local function jump(name) page=name; note=""; dirty=true; rebuild=true; lastLed=nil end
--- 熄灭本工具控制的灯环并请求退出，不自动保存尚未确认的设置。
local function close()
  if w then w.reset(); w.flush(true) end
  exiting=true
end
--- 重新开始四步校准，沿用已知底部位置作为选择起点。
local function calibrate()
  phase=1; selected=c.bottomA; jump("cal")
end
--- 确认本步后进入下一步；四步结束只标记 ready，仍需用户点保存。
local function advance()
  if phase==1 then c.bottomA=selected
  elseif phase==3 then c.bottomB=selected end
  phase=phase+1
  if phase==3 then selected=c.bottomB end
  if phase==5 then c.ready=1; jump("home") else jump("cal") end
end
--- 在当前接线组内循环选择灯珠，不能跨到另一环。
local function move(delta)
  local base=group()*16
  selected=base+(selected-base+delta)%16
  dirty=true
end
--- 反转当前组的编号方向，仅修改待保存配置。
local function flip()
  local name=group()==0 and "cwA" or "cwB"
  c[name]=1-c[name]; dirty=true; lastLed=nil
end
--- 统一页面回退：油门设置回设置，子页回主页，主页退出工具。
local function back()
  touch()
  if problem then close()
  elseif page=="cal" and phase>1 then
    phase=phase-1; selected=group()==0 and c.bottomA or c.bottomB; jump("cal")
  elseif page=="input" then jump("settings")
  elseif page=="cal" or page=="home" then close()
  else jump("home") end
end
--- 仅保存完成校准的配置，并把读回校验结果显示给用户。
local function save()
  if c.ready~=1 then note="请先完成校准"; return end
  note=core.save(c) and "已保存，重开灯效生效" or "保存失败，请检查SD卡"
end
--- 根据当前页面重建五行布局，按钮统一使用原生字体、主题颜色和边框。
local function build()
  if not lvgl then return end
  lvgl.clear()
  local width=LCD_W or 480
  local body=(LCD_H or 272)-60
  if type(lvgl.PAGE_BODY_HEIGHT)=="number" and lvgl.PAGE_BODY_HEIGHT>0 then
    body=math.min(body,lvgl.PAGE_BODY_HEIGHT)
  end
  local row=math.floor((body-16)/5)
  local height=math.min(40,row-6)
  local names={cal="校准",home="主页",settings="设置",input="油门设置",about="关于"}
  local pg=lvgl.page({title="V15灯光 v5.2 - "..(problem and "错误" or names[page]),back=back})
  --- 在逻辑行内放置文字，支持字符串或固件动态文字回调。
  local function label(line,text,x,ww)
    pg:label({x=x or 8,y=8+(line-1)*row,w=ww or width-16,h=height,font=STDSIZE or 0,text=text})
  end
  --- 把按钮区域与文字作为一组布局，横向分栏并按实测字高垂直居中。
  local function button(line,index,total,text,fn)
    local ww=math.floor((width-16-(total-1)*8)/total)
    local x,y=8+(index-1)*(ww+8),8+(line-1)*row
    -- V15 返回的按钮句柄不能承载子控件，因此文字放在同一页面上。
    pg:button({x=x,y=y,w=ww,h=height,
      font=STDSIZE or 0,text="",press=function() touch(); fn() end})
    local th=24
    if lcd and type(lcd.sizeText)=="function" then
      local _,measured=lcd.sizeText(text,STDSIZE or 0)
      if type(measured)=="number" and measured>0 then th=measured end
    end
    -- 按固件实测字高居中，避免小号中文字体在按钮内偏上。
    th=math.min(th,height)
    -- Lua 对齐常量是 CENTER；CENTERED 只存在于固件 C++ 层。
    pg:label({x=x+8,y=y+math.floor((height-th)/2),w=ww-16,h=th,
      font=STDSIZE or 0,align=CENTER,text=text})
  end
  --- 创建原生选择框；选择变化只更新内存并唤醒校准灯，不立即写卡。
  local function choice(line,title,values,get,set)
    label(line,title,8,104)
    -- 固件的 choice 不接受 font 属性，沿用原生字体。
    pg:choice({x=120,y=8+(line-1)*row,w=width-128,h=height,title=title,
      values=values,get=get,set=function(i) touch(); set(i); dirty=true; note="" end})
  end
  if problem then
    label(1,"无法启动"); label(2,problem); label(3,"请完整复制 SCRIPTS")
    button(5,1,1,"回退",close)
  elseif page=="cal" then
    local g=group()
    label(1,"第 "..phase.."/4 步：灯组 "..(g+1))
    if phase%2==1 then
      label(2,function() return string.format("选正下方灯珠：编号 %02d",selected) end)
      button(3,1,2,"上一颗灯",function() move(-1) end)
      button(3,2,2,"下一颗灯",function() move(1) end)
      if phase==1 then
        choice(4,"所在侧",{"左摇杆","右摇杆"},function() return c.left+1 end,
          function(i) c.left=i-1 end)
      else label(4,"位置按正面 6 点钟选") end
      button(5,1,1,"确定灯位",advance)
    else
      label(2,"看白灯：应当顺时针转")
      label(3,"方向不对就点反转")
      button(4,1,1,"反转方向",flip)
      button(5,1,1,"方向正确",advance)
    end
  elseif page=="home" then
    label(1,function() return note~="" and note or "校准已完成" end)
    label(2,"灯效在模型特殊功能中选择")
    button(3,1,2,"设置",function() jump("settings") end)
    button(3,2,2,"关于",function() jump("about") end)
    button(4,1,2,"重新校准",calibrate)
    button(4,2,2,"保存设置",save)
    -- 精简中文字库有“回、退”，但缺“返”；不要再用自绘字形破坏统一样式。
    button(5,1,1,"回退",back)
  elseif page=="about" then
    label(1,"V15 灯效")
    label(2,"作者：Xu")
    label(3,"GitHub: github.com/939008033")
    label(4,"邮箱: 939008033@qq.com")
    button(5,1,1,"回退",back)
  elseif page=="settings" then
    choice(1,"亮度",{"20%","40%","60%","80%","100%"},function()
      for i,v in ipairs(brightness) do if c.brightness==v then return i end end; return 2
    end,function(i) c.brightness=brightness[i] end)
    choice(2,"六键",{"关闭","开启"},function() return c.keys+1 end,function(i) c.keys=i-1 end)
    choice(3,"低功耗",{"关闭","5分钟","10分钟","15分钟"},function()
      for i,v in ipairs(idleMinutes) do if c.idleMinutes==v then return i end end; return 1
    end,function(i) c.idleMinutes=idleMinutes[i] end)
    button(4,1,1,"油门设置",function() jump("input") end)
    button(5,1,1,"回退",back)
  elseif page=="input" then
    local sources={"油门摇杆"}
    for i=1,32 do sources[#sources+1]="CH"..i end
    choice(1,"来源",sources,function() return c.source+1 end,function(i) c.source=i-1 end)
    choice(2,"油门",{"正常","反向"},function() return c.reverse+1 end,function(i) c.reverse=i-1 end)
    choice(3,"平滑",{"关闭","快速","标准","柔和","缓慢"},function()
      for i,v in ipairs(smooth) do if c.smooth==v then return i end end; return 3
    end,function(i) c.smooth=smooth[i] end)
    label(4,"来源和反向仅用于油门灯效")
    button(5,1,1,"回退",back)
  end
end
--- 加载依赖和校准，缺失或固件不支持时显示可退出的错误页面。
local function init()
  core,c,w,idle,problem=nil,nil,nil,nil,nil
  phase,selected,page,note=1,0,"cal",""
  dirty,rebuild,exiting,lastLed=true,false,false,nil
  lastIdle,wasSleeping=nil,false
  local ok,result=pcall(function()
    local f=loadScript("/SCRIPTS/RGBLED/v15lib/effects.lua","tx")
    return f and f()
  end)
  if not ok or type(result)~="table" or result.version~=5 then problem="缺少 v5 灯效库"
  elseif not result.hardware() then problem="固件不支持灯光接口"
  else
    core=result; c=core.load() or core.defaults(); selected=c.bottomA
    -- 校准只控制两个灯环，不探测或占用功能按键灯。
    w=core.writer(); w.enableKeys(false); idle=core.idle()
    if c.ready==1 then phase=5; page="home" end
  end
  build()
end
--- 处理延后重建和定位灯刷新；设置、关于及主页保持工具灯环熄灭。
-- @param event 固件界面事件；有效操作用于重置闲置计时。
-- @return 继续运行返回 0，退出返回 2。
local function run(event)
  if exiting then return 2 end
  if not lvgl then
    if lcd and lcd.clear then lcd.clear() end
    if lcd and lcd.drawText then lcd.drawText(8,8,"Need EdgeTX LVGL",0) end
    if EVT_VIRTUAL_EXIT and event==EVT_VIRTUAL_EXIT then close(); return 2 end
    return 0
  end
  if rebuild then rebuild=false; build() end
  if problem then return 0 end
  local now=getTime()
  if type(event)=="number" and event~=0 then touch() end
  if not lastIdle or now<lastIdle or now-lastIdle>=5 then
    lastIdle=now
    local sleeping=idle.apply(w,c,now,event)
    if wasSleeping and not sleeping then dirty=true end
    wasSleeping=sleeping
  end
  if wasSleeping then return 0 end
  if page=="cal" and phase%2==0 then
    local step=math.floor(now/20)%16
    if step~=lastLed then lastLed=step; dirty=true end
  end
  if not dirty then return 0 end
  dirty=false
  w.reset()
  if page=="cal" then
    local id=selected
    if phase%2==0 then
      local g=group(); local bottom=g==0 and c.bottomA or c.bottomB
      local cw=(g==0 and c.cwA or c.cwB)==1 and 1 or -1
      id=g*16+(bottom-g*16+math.floor(now/20)%16*cw)%16
    end
    w.set(id,65,65,65)
  end
  w.flush()
  return 0
end
return {init=init,run=run,useLvgl=true}
