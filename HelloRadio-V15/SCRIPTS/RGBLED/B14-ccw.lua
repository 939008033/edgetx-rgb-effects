-- Xu
-- V15 v5: 绿蓝渐变／双环逆时针／外下角
-- Enable only ONE RGB preset at a time.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/boot.lua","tx")
if not f then error("V15: copy all SCRIPTS (boot.lua missing)") end
return f()({palette=5,pattern=5,angle=4})
