local rtu = require("rtu.rtu")
local sna_rtu = {}
function sna_rtu.new(sna)
local unit = rtu.init_unit(sna)
sna.__p_clear_fault()
sna.__p_disable_afc()
unit.connect_input_reg(sna.getInputCapacity)
unit.connect_input_reg(sna.getOutputCapacity)
unit.connect_input_reg(sna.getProductionRate)
unit.connect_input_reg(sna.getPeakProductionRate)
unit.connect_input_reg(sna.getInput)
unit.connect_input_reg(sna.getInputNeeded)
unit.connect_input_reg(sna.getInputFilledPercentage)
unit.connect_input_reg(sna.getOutput)
unit.connect_input_reg(sna.getOutputNeeded)
unit.connect_input_reg(sna.getOutputFilledPercentage)
local faulted = sna.__p_is_faulted()
sna.__p_clear_fault()
sna.__p_enable_afc()
return unit.interface(), faulted
end
return sna_rtu
