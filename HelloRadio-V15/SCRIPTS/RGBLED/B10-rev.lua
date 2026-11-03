-- Xu
-- V15 v5: 彩虹渐变／镜像反向／内下角
-- Enable only ONE RGB preset at a time.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/boot.lua","tx")
if not f then error("V15: copy all SCRIPTS (boot.lua missing)") end
return f()({palette=1,pattern=2,angle=1})
