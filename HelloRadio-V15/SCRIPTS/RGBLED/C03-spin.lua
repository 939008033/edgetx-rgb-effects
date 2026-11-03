-- Xu
-- V15 dual-stick add-on: 双杆旋涡
-- Reads physical stick sources; never changes model outputs.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/sticks.lua","tx")
if not f then error("V15: copy all SCRIPTS (sticks.lua missing)") end
return f().entry("spin")
