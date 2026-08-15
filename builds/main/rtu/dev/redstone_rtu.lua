local rsio = require("scada-common.rsio")
local rtu  = require("rtu.rtu")
local redstone_rtu = {}
local IO_LVL = rsio.IO_LVL
local digital_read = rsio.digital_read
local digital_write = rsio.digital_write
function redstone_rtu.new(relay)
local unit = rtu.init_unit()
local phy = relay or rs
local interface = unit.interface()
local public = {
io_count = interface.io_count,
read_coil = interface.read_coil,
read_di = interface.read_di,
read_holding_reg = interface.read_holding_reg,
read_input_reg = interface.read_input_reg,
write_coil = interface.write_coil,
write_holding_reg = interface.write_holding_reg
}
function public.remount_phy(new_phy) phy = new_phy end
function public.link_di(side, color, invert)
local f_read
if color then
if invert then
f_read = function () return digital_read(not phy.testBundledInput(side, color)) end
else
f_read = function () return digital_read(phy.testBundledInput(side, color)) end
end
else
if invert then
f_read = function () return digital_read(not phy.getInput(side)) end
else
f_read = function () return digital_read(phy.getInput(side)) end
end
end
return unit.connect_di(f_read)
end
function public.link_do(side, color, invert)
local f_read
local f_write
if color then
if invert then
f_read = function () return digital_read(not colors.test(phy.getBundledOutput(side), color)) end
f_write = function (level)
if level ~= IO_LVL.FLOATING and level ~= IO_LVL.DISCONNECT then
local output = phy.getBundledOutput(side)
if digital_write(level) then
output = colors.subtract(output, color)
else output = colors.combine(output, color) end
phy.setBundledOutput(side, output)
end
end
else
f_read = function () return digital_read(colors.test(phy.getBundledOutput(side), color)) end
f_write = function (level)
if level ~= IO_LVL.FLOATING and level ~= IO_LVL.DISCONNECT then
local output = phy.getBundledOutput(side)
if digital_write(level) then
output = colors.combine(output, color)
else output = colors.subtract(output, color) end
phy.setBundledOutput(side, output)
end
end
end
else
if invert then
f_read = function () return digital_read(not phy.getOutput(side)) end
f_write = function (level)
if level ~= IO_LVL.FLOATING and level ~= IO_LVL.DISCONNECT then
phy.setOutput(side, not digital_write(level))
end
end
else
f_read = function () return digital_read(phy.getOutput(side)) end
f_write = function (level)
if level ~= IO_LVL.FLOATING and level ~= IO_LVL.DISCONNECT then
phy.setOutput(side, digital_write(level))
end
end
end
end
return unit.connect_coil(f_read, f_write)
end
function public.link_ai(side)
return unit.connect_input_reg(function () return phy.getAnalogInput(side) end)
end
function public.link_ao(side)
return unit.connect_holding_reg(
function () return phy.getAnalogOutput(side) end,
function (value) phy.setAnalogOutput(side, value) end
)
end
return public, false
end
return redstone_rtu
