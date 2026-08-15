
local rsio = require("scada-common.rsio")
local rsctl = {}
function rsctl.new(redstone_rtus, bank)
local public = {}
function public.is_connected(port)
for i = 1, #redstone_rtus do
if redstone_rtus[i].get_db().io[bank][port] ~= nil then return true end
end
return false
end
function public.digital_write(port, value)
for i = 1, #redstone_rtus do
local io = redstone_rtus[i].get_db().io[bank][port]
if io ~= nil then io.write(value) end
end
end
function public.digital_read(port)
for i = 1, #redstone_rtus do
local io = redstone_rtus[i].get_db().io[bank][port]
if io ~= nil then return io.read() end
end
end
function public.analog_write(port, value, min, max)
for i = 1, #redstone_rtus do
local io = redstone_rtus[i].get_db().io[bank][port]
if io ~= nil then io.write(rsio.analog_write(value, min, max)) end
end
end
function public.as_valve(port)
local iface = {
open = function () public.digital_write(port, true) end,
close = function () public.digital_write(port, false) end,
check = function ()
if public.is_connected(port) then
if public.digital_read(port) then return 2 else return 1 end
else return 0 end
end
}
return iface
end
return public
end
return rsctl
