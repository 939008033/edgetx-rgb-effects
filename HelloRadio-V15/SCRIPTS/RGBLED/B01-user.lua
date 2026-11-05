-- Xu
-- V15 v5: 自定义：保留历史配色、走向、起点；新装使用默认彩虹镜像
-- Enable only ONE RGB preset at a time.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/boot.lua","tx")
if not f then error("V15: copy all SCRIPTS (boot.lua missing)") end
return f()(nil)
