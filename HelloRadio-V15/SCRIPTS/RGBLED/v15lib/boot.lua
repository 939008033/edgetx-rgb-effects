-- Xu
--- 油门预设的公共加载器。优先加载文本，避免旧 .luac 与新源码混用。
-- @param preset 配色、走向和起点覆盖表；空表沿用用户配置。
-- @return EdgeTX 的 init/run/background 回调表。
return function(preset)
  local runtime
  --- 检查公共库版本和 RGB 接口，初始化独立的油门灯效实例。
  local function init()
    runtime=nil
    local ok,core=pcall(function()
      local f=loadScript("/SCRIPTS/RGBLED/v15lib/effects.lua","tx")
      return f and f()
    end)
    if not ok or type(core)~="table" or core.version~=5 then error("V15: copy all SCRIPTS (effects.lua missing)") end
    if not core.hardware() then error("V15: RGB API unavailable") end
    runtime=core.runtime(preset); runtime.init()
  end
  return {init=init,run=function() if runtime then runtime.run() end end,
    background=function() if runtime then runtime.background() end end}
end
