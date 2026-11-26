-- Xu
--- 灯效入口：冰蓝渐变／左右镜像／正上方
-- 同一时刻只启用一个 RGB 灯效，避免多个实例争用灯珠；共用已有校准和亮度。
local f=loadScript("/SCRIPTS/RGBLED/v15lib/boot.lua","tx")
if not f then error("V15: copy all SCRIPTS (boot.lua missing)") end
return f()({palette=2,pattern=1,angle=3})
