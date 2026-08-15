local rtu = require("rtu.rtu")
local dynamicv_rtu = {}
function dynamicv_rtu.new(dynamic_tank)
local unit = rtu.init_unit(dynamic_tank)
unit.connect_di("isFormed")
unit.connect_coil(function () dynamic_tank.incrementContainerEditMode() end, function () end)
unit.connect_coil(function () dynamic_tank.decrementContainerEditMode() end, function () end)
unit.connect_input_reg("getLength")
unit.connect_input_reg("getWidth")
unit.connect_input_reg("getHeight")
unit.connect_input_reg("getMinPos")
unit.connect_input_reg("getMaxPos")
unit.connect_input_reg("getTankCapacity")
unit.connect_input_reg("getChemicalTankCapacity")
unit.connect_input_reg("getStored")
unit.connect_input_reg("getFilledPercentage")
unit.connect_holding_reg("getContainerEditMode", "setContainerEditMode")
return unit.interface(), false
end
return dynamicv_rtu
