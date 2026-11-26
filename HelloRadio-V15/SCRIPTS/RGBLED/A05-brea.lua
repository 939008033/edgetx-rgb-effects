-- Xu
--- 灯效入口：青紫呼吸（持续播放）
-- 同一时刻只启用一个 RGB 灯效，避免多个实例争用灯珠；共用已有校准和亮度。
local f=loadScript("/SCRIPTS/RGBLED/v15lib/motion.lua","tx")
if not f then error("V15: copy all SCRIPTS (motion.lua missing)") end
return f().entry("breathe")
