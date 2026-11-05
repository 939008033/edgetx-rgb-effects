-- Xu
-- Compact Chinese calibration. Never rebuild LVGL inside an event callback.
local core,c,w,problem
local phase,selected,preview,page,note=1,0,0.5,"cal",""
local dirty,rebuild,exiting=true,true,false
local live=false
local lastAnim,lastLed
local testMode="half"
local key=1
local brightness={20,40,60,80,100}
local smooth={0,4,8,12,20}
local function group() return phase<=2 and 0 or 1 end
local function jump(name) page=name; note=""; dirty=true; rebuild=true; lastLed=nil end
local function close()
  if w then w.reset(); w.flush(true); w.releaseKeys() end
  exiting=true
end
local function calibrate()
  phase=1; selected=c.bottomA; live=false; jump("cal")
end
local function advance()
  if phase==1 then c.bottomA=selected
  elseif phase==3 then c.bottomB=selected end
  phase=phase+1
  if phase==3 then selected=c.bottomB end
  if phase==5 then c.ready=1; jump("preview") else jump("cal") end
end
local function move(delta)
  local base=group()*16
  selected=base+(selected-base+delta)%16
  dirty=true
end
local function flip()
  local name=group()==0 and "cwA" or "cwB"
  c[name]=1-c[name]; dirty=true; lastLed=nil
end
local function back()
  if problem then close()
  elseif page=="cal" and phase>1 then
    phase=phase-1; selected=group()==0 and c.bottomA or c.bottomB; jump("cal")
  elseif page=="cal" or page=="preview" then close()
  else live=false; jump("preview") end
end
local function save()
  if c.ready~=1 then note="请先完成校准"; return end
  note=core.save(c) and "已保存，重开灯效生效" or "保存失败，请检查SD卡"
end
local function status()
  if note~="" then return note end
  if c.keys==1 and w.keyCount<6 then return "键灯受限：暂用灯环" end
  return "一次只启用一个灯效"
end
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
  local names={cal="校准",preview="预览",settings="设置",style="配色",test="静态测试",keys="键灯测试",about="关于"}
  local pg=lvgl.page({title="V15灯光 v5.1 - "..(problem and "错误" or names[page]),back=back})
  local function label(line,text,x,ww)
    pg:label({x=x or 8,y=8+(line-1)*row,w=ww or width-16,h=height,font=STDSIZE or 0,text=text})
  end
  local function button(line,index,total,text,fn)
    local ww=math.floor((width-16-(total-1)*8)/total)
    local x,y=8+(index-1)*(ww+8),8+(line-1)*row
    -- V15 button handles are not containers. Draw the caption on the page.
    pg:button({x=x,y=y,w=ww,h=height,
      font=STDSIZE or 0,text="",press=fn})
    local th=math.min(24,height)
    -- EdgeTX exports CENTER to Lua; CENTERED is only the C++ constant name.
    pg:label({x=x+8,y=y+math.floor((height-th)/2),w=ww-16,h=th,
      font=STDSIZE or 0,align=CENTER,text=text})
  end
  local function choice(line,title,values,get,set)
    label(line,title,8,104)
    -- EdgeTX choice does NOT accept 'font'.
    pg:choice({x=120,y=8+(line-1)*row,w=width-128,h=height,title=title,
      values=values,get=get,set=function(i) set(i); dirty=true; note="" end})
  end
  if problem then
    label(1,"无法启动"); label(2,problem); label(3,"请完整复制 SCRIPTS")
    button(5,1,1,"退出工具",close)
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
  elseif page=="preview" then
    label(1,status)
    label(2,function() return string.format("油门 %d%%  %s",math.floor(preview*100+0.5),core.paletteNames[c.palette]) end)
    for i,p in ipairs({0,0.5,1}) do
      local v=p
      button(3,i,4,string.format("%d%%",p*100),function() preview=v; live=false; dirty=true; note="" end)
    end
    button(3,4,4,"跟随",function() live=true; dirty=true end)
    button(4,1,4,"配色",function() jump("style") end)
    button(4,2,4,"设置",function() jump("settings") end)
    button(4,3,4,"测试",function() live=false; jump("test") end)
    button(4,4,4,"关于",function() live=false; jump("about") end)
    button(5,1,2,"重新校准",calibrate)
    button(5,2,2,"保存设置",save)
  elseif page=="about" then
    label(1,"V15 灯效")
    label(2,"作者：Xu")
    label(3,"GitHub: github.com/939008033")
    label(4,"邮箱: 939008033@qq.com")
    button(5,1,1,"返回预览",back)
  elseif page=="settings" then
    local sources={"油门摇杆"}
    for i=1,32 do sources[#sources+1]="CH"..i end
    choice(1,"来源",sources,function() return c.source+1 end,function(i) c.source=i-1 end)
    choice(2,"油门",{"正常","反向"},function() return c.reverse+1 end,function(i) c.reverse=i-1 end)
    choice(3,"亮度",{"20%","40%","60%","80%","100%"},function()
      for i,v in ipairs(brightness) do if c.brightness==v then return i end end; return 2
    end,function(i) c.brightness=brightness[i] end)
    choice(4,"平滑",{"关闭","快速","标准","柔和","缓慢"},function()
      for i,v in ipairs(smooth) do if c.smooth==v then return i end end; return 3
    end,function(i) c.smooth=smooth[i] end)
    button(5,1,2,"配色",function() jump("style") end)
    button(5,2,2,"返回预览",back)
  elseif page=="style" then
    choice(1,"配色",core.paletteNames,function() return c.palette end,function(i) c.palette=i end)
    choice(2,"走向",core.patternNames,function() return c.pattern end,function(i) c.pattern=i end)
    choice(3,"起点",core.angleNames,function() return c.angle end,function(i) c.angle=i end)
    choice(4,"六键",{"关闭","优先点亮"},function() return c.keys+1 end,function(i) c.keys=i-1 end)
    button(5,1,2,"测试按键灯",function() jump("keys") end)
    button(5,2,2,"返回预览",back)
  elseif page=="keys" then
    label(1,function() return string.format("接口响应 %d/6",w.keyCount) end)
    label(2,function() return string.format("SW%d  %s  第%d键",key,w.keyRoute(31+key),key) end)
    button(3,1,2,"上一按键",function() key=(key-2)%6+1; dirty=true end)
    button(3,2,2,"下一按键",function() key=key%6+1; dirty=true end)
    label(4,"关闭 / ON 均允许Lua")
    button(5,1,2,"重新检测",function() w.probeKeys(); dirty=true end)
    button(5,2,2,"返回预览",back)
  elseif page=="test" then
    label(1,"固定颜色，不随油门改变")
    label(2,"仍乱色：查固件或其它灯效")
    for i,v in ipairs({{"全部青色","cyan"},{"全部红色","red"},{"全部蓝色","blue"}}) do
      local mode=v[2]; button(3,i,3,v[1],function() testMode=mode; dirty=true end)
    end
    button(4,1,2,"半圈青色",function() testMode="half"; dirty=true end)
    button(4,2,2,"关闭灯环",function() testMode="off"; dirty=true end)
    button(5,1,2,"测试按键灯",function() jump("keys") end)
    button(5,2,2,"返回预览",back)
  end
end
local function init()
  core,c,w,problem=nil,nil,nil,nil
  phase,selected,preview,page,note=1,0,0.5,"cal",""
  dirty,rebuild,exiting,live,lastAnim,lastLed=true,false,false,false,nil,nil
  local ok,result=pcall(function()
    local f=loadScript("/SCRIPTS/RGBLED/v15lib/effects.lua","tx")
    return f and f()
  end)
  if not ok or type(result)~="table" or result.version~=5 then problem="缺少 v5 灯效库"
  elseif not result.hardware() then problem="固件不支持灯光接口"
  else
    core=result; c=core.load() or core.defaults(); selected=c.bottomA
    w=core.writer(); w.probeKeys()
    if c.ready==1 then phase=5; page="preview" end
  end
  build()
end
local function run(event)
  if exiting then return 2 end
  if not lvgl then
    if lcd and lcd.clear then lcd.clear() end
    if lcd and lcd.drawText then lcd.drawText(8,8,"Need EdgeTX LVGL",0) end
    if EVT_VIRTUAL_EXIT and event==EVT_VIRTUAL_EXIT then close(); return 2 end
    return 0
  end
  if rebuild then rebuild=false; build() end
  if problem or page=="about" then return 0 end
  local now=getTime()
  if page=="cal" and phase%2==0 then
    local step=math.floor(now/20)%16
    if step~=lastLed then lastLed=step; dirty=true end
  elseif page=="preview" and live and (not lastAnim or now<lastAnim or now-lastAnim>=5) then
    lastAnim=now; preview=core.progress(c) or 0; dirty=true
  end
  if not dirty then return 0 end
  dirty=false
  if page=="preview" or page=="settings" or page=="style" then core.render(w,c,preview)
  else
    w.enableKeys(page=="keys")
    w.reset()
    if page=="cal" then
      local id=selected
      if phase%2==0 then
        local g=group(); local bottom=g==0 and c.bottomA or c.bottomB
        local cw=(g==0 and c.cwA or c.cwB)==1 and 1 or -1
        id=g*16+(bottom-g*16+math.floor(now/20)%16*cw)%16
      end
      w.set(id,65,65,65)
    elseif page=="keys" then
      if w.keys[31+key] then w.set(31+key,65,65,65) end
    elseif page=="test" then
      for id=0,31 do
        if testMode~="off" and (testMode~="half" or id%16<8) then
          w.set(id,testMode=="red" and 100 or 0,
            (testMode=="cyan" or testMode=="half") and 70 or 0,
            testMode~="red" and 100 or 0)
        end
      end
    end
    w.flush()
  end
  return 0
end
return {init=init,run=run,useLvgl=true}
