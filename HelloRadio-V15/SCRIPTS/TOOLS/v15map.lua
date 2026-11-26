-- Xu
--- 校准工具入口；文本优先加载，确保更新源码后不会继续使用旧字节码缓存。
local f=loadScript("/SCRIPTS/RGBLED/v15lib/mapper.lua","tx")
if not f then error("V15: copy all SCRIPTS (mapper.lua missing)") end
return f()
