local rtu = require("rtu.rtu")
local envd_rtu = {}
function envd_rtu.new(envd)
local unit = rtu.init_unit(envd)
envd.__p_clear_fault()
envd.__p_disable_afc()
unit.connect_input_reg(envd.getRadiation)
unit.connect_input_reg(envd.getRadiationRaw)
local faulted = envd.__p_is_faulted()
envd.__p_clear_fault()
envd.__p_enable_afc()
return unit.interface(), faulted
end
return envd_rtu
