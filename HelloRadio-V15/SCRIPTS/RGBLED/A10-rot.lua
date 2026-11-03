-- Xu
-- V15 creative add-on: 霓虹旋翼（持续播放）
-- Enable only ONE RGB script; reuse existing calibration and brightness.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/creative.lua","tx")
if not f then error("V15: copy all SCRIPTS (creative.lua missing)") end
return f().entry("rotor")
