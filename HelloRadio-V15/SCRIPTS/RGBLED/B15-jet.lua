-- Xu
-- V15 dynamic add-on: 油门加力（跟随油门）
-- Enable only ONE RGB script. Keep your existing v15lib/layout.cfg.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/motion.lua","tx")
if not f then error("V15: copy all SCRIPTS (motion.lua missing)") end
return f().entry("jet")
