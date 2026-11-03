-- Xu
-- V15 v5: 自定义：读取校准工具保存的配色、走向、起点
-- Enable only ONE RGB preset at a time.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/boot.lua","tx")
if not f then error("V15: copy all SCRIPTS (boot.lua missing)") end
return f()(nil)
