local comms = require("scada-common.comms")
local types = require("scada-common.types")
local modbus = {}
local MODBUS_FCODE = types.MODBUS_FCODE
local MODBUS_EXCODE = types.MODBUS_EXCODE
function modbus.new(rtu_dev, use_parallel_read)
local insert = table.insert
local function _1_read_coils(c_addr_start, count)
local tasks = {}
local readings = {}
local access_fault = false
local _, coils, _, _ = rtu_dev.io_count()
local return_ok = ((c_addr_start + count) <= (coils + 1)) and (count > 0)
if return_ok then
for i = 1, count do
local addr = c_addr_start + i - 1
if use_parallel_read then
insert(tasks, function ()
local reading, fault = rtu_dev.read_coil(addr)
if fault then access_fault = true else readings[i] = reading end
end)
else
readings[i], access_fault = rtu_dev.read_coil(addr)
if access_fault then break end
end
end
if use_parallel_read then
parallel.waitForAll(table.unpack(tasks))
end
if access_fault or #readings ~= count then
return_ok = false
readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
end
else
readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
end
return return_ok, readings
end
local function _2_read_discrete_inputs(di_addr_start, count)
local tasks = {}
local readings = {}
local access_fault = false
local discrete_inputs, _, _, _ = rtu_dev.io_count()
local return_ok = ((di_addr_start + count) <= (discrete_inputs + 1)) and (count > 0)
if return_ok then
for i = 1, count do
local addr = di_addr_start + i - 1
if use_parallel_read then
insert(tasks, function ()
local reading, fault = rtu_dev.read_di(addr)
if fault then access_fault = true else readings[i] = reading end
end)
else
readings[i], access_fault = rtu_dev.read_di(addr)
if access_fault then break end
end
end
if use_parallel_read then
parallel.waitForAll(table.unpack(tasks))
end
if access_fault or #readings ~= count then
return_ok = false
readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
end
else
readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
end
return return_ok, readings
end
local function _3_read_multiple_holding_registers(hr_addr_start, count)
local tasks = {}
local readings = {}
local access_fault = false
local _, _, _, hold_regs = rtu_dev.io_count()
local return_ok = ((hr_addr_start + count) <= (hold_regs + 1)) and (count > 0)
if return_ok then
for i = 1, count do
local addr = hr_addr_start + i - 1
if use_parallel_read then
insert(tasks, function ()
local reading, fault = rtu_dev.read_holding_reg(addr)
if fault then access_fault = true else readings[i] = reading end
end)
else
readings[i], access_fault = rtu_dev.read_holding_reg(addr)
if access_fault then break end
end
end
if use_parallel_read then
parallel.waitForAll(table.unpack(tasks))
end
if access_fault or #readings ~= count then
return_ok = false
readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
end
else
readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
end
return return_ok, readings
end
local function _4_read_input_registers(ir_addr_start, count)
local tasks = {}
local readings = {}
local access_fault = false
local _, _, input_regs, _ = rtu_dev.io_count()
local return_ok = ((ir_addr_start + count) <= (input_regs + 1)) and (count > 0)
if return_ok then
for i = 1, count do
local addr = ir_addr_start + i - 1
if use_parallel_read then
insert(tasks, function ()
local reading, fault = rtu_dev.read_input_reg(addr)
if fault then access_fault = true else readings[i] = reading end
end)
else
readings[i], access_fault = rtu_dev.read_input_reg(addr)
if access_fault then break end
end
end
if use_parallel_read then
parallel.waitForAll(table.unpack(tasks))
end
if access_fault or #readings ~= count then
return_ok = false
readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
end
else
readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
end
return return_ok, readings
end
local function _5_write_single_coil(c_addr, value)
local response = MODBUS_EXCODE.OK
local _, coils, _, _ = rtu_dev.io_count()
local return_ok = c_addr <= coils
if return_ok then
local access_fault = rtu_dev.write_coil(c_addr, value)
if access_fault then
return_ok = false
response = MODBUS_EXCODE.SERVER_DEVICE_FAIL
end
else
response = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
end
return return_ok, response
end
local function _6_write_single_holding_register(hr_addr, value)
local response = MODBUS_EXCODE.OK
local _, _, _, hold_regs = rtu_dev.io_count()
local return_ok = hr_addr <= hold_regs
if return_ok then
local access_fault = rtu_dev.write_holding_reg(hr_addr, value)
if access_fault then
return_ok = false
response = MODBUS_EXCODE.SERVER_DEVICE_FAIL
end
else
response = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
end
return return_ok, response
end
local function _15_write_multiple_coils(c_addr_start, values)
local response = MODBUS_EXCODE.OK
local _, coils, _, _ = rtu_dev.io_count()
local count = #values
local return_ok = ((c_addr_start + count) <= (coils + 1)) and (count > 0)
if return_ok then
for i = 1, count do
local addr = c_addr_start + i - 1
local access_fault = rtu_dev.write_coil(addr, values[i])
if access_fault then
return_ok = false
response = MODBUS_EXCODE.SERVER_DEVICE_FAIL
break
end
end
else
response = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
end
return return_ok, response
end
local function _16_write_multiple_holding_registers(hr_addr_start, values)
local response = MODBUS_EXCODE.OK
local _, _, _, hold_regs = rtu_dev.io_count()
local count = #values
local return_ok = ((hr_addr_start + count) <= (hold_regs + 1)) and (count > 0)
if return_ok then
for i = 1, count do
local addr = hr_addr_start + i - 1
local access_fault = rtu_dev.write_holding_reg(addr, values[i])
if access_fault then
return_ok = false
response = MODBUS_EXCODE.SERVER_DEVICE_FAIL
break
end
end
else
response = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
end
return return_ok, response
end
local public = {}
function public.check_request(adu)
local return_code = true
local response = { MODBUS_EXCODE.ACKNOWLEDGE }
if adu.length == 2 then
if adu.func_code == MODBUS_FCODE.READ_COILS then
elseif adu.func_code == MODBUS_FCODE.READ_DISCRETE_INPUTS then
elseif adu.func_code == MODBUS_FCODE.READ_MUL_HOLD_REGS then
elseif adu.func_code == MODBUS_FCODE.READ_INPUT_REGS then
elseif adu.func_code == MODBUS_FCODE.WRITE_SINGLE_COIL then
elseif adu.func_code == MODBUS_FCODE.WRITE_SINGLE_HOLD_REG then
elseif adu.func_code == MODBUS_FCODE.WRITE_MUL_COILS then
elseif adu.func_code == MODBUS_FCODE.WRITE_MUL_HOLD_REGS then
else
return_code = false
response = { MODBUS_EXCODE.ILLEGAL_FUNCTION }
end
else
return_code = false
response = { MODBUS_EXCODE.NEG_ACKNOWLEDGE }
end
local func_code = bit.bor(adu.func_code, MODBUS_FCODE.ERROR_FLAG)
local reply = comms.modbus_container()
reply.make(adu.txn_id, adu.unit_id, func_code, response)
return return_code, reply
end
function public.handle_adu(adu)
local return_code
local response
if adu.length >= 2 then
if adu.func_code == MODBUS_FCODE.READ_COILS then
return_code, response = _1_read_coils(adu.data[1], adu.data[2])
elseif adu.func_code == MODBUS_FCODE.READ_DISCRETE_INPUTS then
return_code, response = _2_read_discrete_inputs(adu.data[1], adu.data[2])
elseif adu.func_code == MODBUS_FCODE.READ_MUL_HOLD_REGS then
return_code, response = _3_read_multiple_holding_registers(adu.data[1], adu.data[2])
elseif adu.func_code == MODBUS_FCODE.READ_INPUT_REGS then
return_code, response = _4_read_input_registers(adu.data[1], adu.data[2])
elseif adu.func_code == MODBUS_FCODE.WRITE_SINGLE_COIL then
return_code, response = _5_write_single_coil(adu.data[1], adu.data[2])
elseif adu.func_code == MODBUS_FCODE.WRITE_SINGLE_HOLD_REG then
return_code, response = _6_write_single_holding_register(adu.data[1], adu.data[2])
elseif adu.func_code == MODBUS_FCODE.WRITE_MUL_COILS then
return_code, response = _15_write_multiple_coils(adu.data[1], { table.unpack(adu.data, 2, adu.length) })
elseif adu.func_code == MODBUS_FCODE.WRITE_MUL_HOLD_REGS then
return_code, response = _16_write_multiple_holding_registers(adu.data[1], { table.unpack(adu.data, 2, adu.length) })
else
return_code = false
response = MODBUS_EXCODE.ILLEGAL_FUNCTION
end
else
return_code = false
response = MODBUS_EXCODE.NEG_ACKNOWLEDGE
end
local func_code = adu.func_code
if not return_code then
func_code = bit.bor(adu.func_code, MODBUS_FCODE.ERROR_FLAG)
end
if type(response) == "table" then
elseif response == MODBUS_EXCODE.OK then
response = {}
else
response = { response }
end
local reply = comms.modbus_container()
reply.make(adu.txn_id, adu.unit_id, func_code, response)
return return_code, reply
end
return public
end
local function excode_reply(adu, code)
local reply = comms.modbus_container()
local fcode = bit.bor(adu.func_code, MODBUS_FCODE.ERROR_FLAG)
reply.make(adu.txn_id, adu.unit_id, fcode, { code })
return reply
end
function modbus.reply__srv_device_fail(adu) return excode_reply(adu, MODBUS_EXCODE.SERVER_DEVICE_FAIL) end
function modbus.reply__srv_device_busy(adu) return excode_reply(adu, MODBUS_EXCODE.SERVER_DEVICE_BUSY) end
function modbus.reply__neg_ack(adu) return excode_reply(adu, MODBUS_EXCODE.NEG_ACKNOWLEDGE) end
function modbus.reply__gw_unavailable(adu) return excode_reply(adu, MODBUS_EXCODE.GATEWAY_PATH_UNAVAILABLE) end
return modbus
