-- Xu
-- V15 v5: 冰蓝渐变／左右镜像／正上方
-- Enable only ONE RGB preset at a time.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/boot.lua","tx")
if not f then error("V15: copy all SCRIPTS (boot.lua missing)") end
return f()({palette=2,pattern=1,angle=3})
