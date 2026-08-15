local rtu = require("rtu.rtu")
local ecore_rtu = {}
function ecore_rtu.new(ecore)
local unit = rtu.init_unit(ecore)
unit.connect_input_reg("getMaxEnergyStored")
unit.connect_input_reg("getInputPerTick")
unit.connect_input_reg("getOutputPerTick")
unit.connect_input_reg("getTransferPerTick")
unit.connect_input_reg("getEnergyStored")
return unit.interface(), false
end
return ecore_rtu
