-- Xu
-- V15 v5: 青粉渐变／两侧展开／正下方
-- Enable only ONE RGB preset at a time.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/boot.lua","tx")
if not f then error("V15: copy all SCRIPTS (boot.lua missing)") end
return f()({palette=4,pattern=3,angle=2})
