local rtu = require("rtu.rtu")
local imatrix_rtu = {}
function imatrix_rtu.new(imatrix)
local unit = rtu.init_unit(imatrix)
unit.connect_di("isFormed")
unit.connect_input_reg("getLength")
unit.connect_input_reg("getWidth")
unit.connect_input_reg("getHeight")
unit.connect_input_reg("getMinPos")
unit.connect_input_reg("getMaxPos")
unit.connect_input_reg("getMaxEnergy")
unit.connect_input_reg("getTransferCap")
unit.connect_input_reg("getInstalledCells")
unit.connect_input_reg("getInstalledProviders")
unit.connect_input_reg("getLastInput")
unit.connect_input_reg("getLastOutput")
unit.connect_input_reg("getEnergy")
unit.connect_input_reg("getEnergyNeeded")
unit.connect_input_reg("getEnergyFilledPercentage")
return unit.interface(), false
end
return imatrix_rtu
