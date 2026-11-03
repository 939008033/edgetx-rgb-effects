-- Xu
-- Shared preset loader. Text mode avoids stale compiled helper libraries.
return function(preset)
  local runtime
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
