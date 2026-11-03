-- Xu
-- Compatibility path for local integrations. V5 entries use effects.lua directly.
local f=loadScript("/SCRIPTS/RGBLED/v15lib/effects.lua","tx")
if not f then error("V15: effects.lua missing") end
return f()
