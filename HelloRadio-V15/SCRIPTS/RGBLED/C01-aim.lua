-- Xu
--- 灯效入口：双杆方向追光
-- 只读取物理摇杆，输出仅用于灯光；不修改模型或通道。
local f=loadScript("/SCRIPTS/RGBLED/v15lib/sticks.lua","tx")
if not f then error("V15: copy all SCRIPTS (sticks.lua missing)") end
return f().entry("aim")
