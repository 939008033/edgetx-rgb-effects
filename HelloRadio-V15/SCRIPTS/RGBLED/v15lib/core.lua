-- Xu
--- 保留旧集成使用的加载路径；v5 入口直接使用 effects.lua。
-- 这里只转发公共模块，不维护第二份配置或状态。
local f=loadScript("/SCRIPTS/RGBLED/v15lib/effects.lua","tx")
if not f then error("V15: effects.lua missing") end
return f()
