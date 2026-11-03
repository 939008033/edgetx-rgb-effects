-- Xu
-- V15 calibration v5; helpers always loaded as source.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/mapper.lua","tx")
if not f then error("V15: copy all SCRIPTS (mapper.lua missing)") end
return f()
