local log          = require("scada-common.log")
local rsio         = require("scada-common.rsio")
local types        = require("scada-common.types")
local util         = require("scada-common.util")
local unit_session = require("supervisor.session.rtu.unit_session")
local redstone = {}
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local MODBUS_FCODE = types.MODBUS_FCODE
local IO_LVL = rsio.IO_LVL
local IO_MODE = rsio.IO_MODE
local TXN_READY = -1
local TXN_TYPES = {
DI_READ = 1,
COIL_WRITE = 2,
COIL_READ = 3,
INPUT_REG_READ = 4,
HOLD_REG_WRITE = 5,
HOLD_REG_READ = 6
}
local TXN_TAGS = {
"redstone.di_read",
"redstone.coil_write",
"redstone.coil_read",
"redstone.input_reg_read",
"redstone.hold_reg_write",
"redstone.hold_reg_read"
}
local PERIODICS = {
INPUT_READ = 200,
OUTPUT_SYNC = 200
}
local function new_io_block() return { [0] = {}, {}, {}, {}, {} } end
function redstone.new(session_id, unit_id, advert, out_queue)
if advert.type ~= RTU_UNIT_TYPE.REDSTONE then
log.error("attempt to instantiate redstone RTU for type " .. types.rtu_type_to_string(advert.type))
return nil
end
local log_tag = util.c("session.rtu(", session_id, ").redstone[@", unit_id, "]: ")
local self = {
session = unit_session.new(session_id, unit_id, advert, out_queue, log_tag, TXN_TAGS),
has_di = false,
has_do = false,
has_ai = false,
has_ao = false,
periodics = {
next_di_req  = 0,
next_cl_sync = 0,
next_ir_req  = 0,
next_hr_sync = 0
},
io_map = {
digital_in = {},
digital_out = {},
analog_in = {},
analog_out = {}
},
phy_trans = { coils = -1, hold_regs = -1 },
phy_io = {
digital_in = new_io_block(),
digital_out = new_io_block(),
analog_in = new_io_block(),
analog_out = new_io_block()
},
db = {
io = new_io_block()
}
}
local public = self.session.get()
for bank = 0, 4 do
for i = 1, #advert.rs_conns[bank] do
local port = advert.rs_conns[bank][i]
if rsio.is_valid_port(port) then
local mode     = rsio.get_io_mode(port)
local io_entry = { bank = bank, port = port }
if mode == IO_MODE.DIGITAL_IN then
self.has_di = true
table.insert(self.io_map.digital_in, io_entry)
self.phy_io.digital_in[bank][port] = { phy = IO_LVL.FLOATING, req = IO_LVL.FLOATING }
local io_f = {
read = function () return rsio.digital_is_active(port, self.phy_io.digital_in[bank][port].phy) end,
write = function () end
}
self.db.io[bank][port] = io_f
elseif mode == IO_MODE.DIGITAL_OUT then
self.has_do = true
table.insert(self.io_map.digital_out, io_entry)
self.phy_io.digital_out[bank][port] = { phy = IO_LVL.FLOATING, req = IO_LVL.FLOATING }
local io_f = {
read = function () return rsio.digital_is_active(port, self.phy_io.digital_out[bank][port].phy) end,
write = function (active)
local level = rsio.digital_write_active(port, active)
if level ~= nil then self.phy_io.digital_out[bank][port].req = level end
end
}
self.db.io[bank][port] = io_f
elseif mode == IO_MODE.ANALOG_IN then
self.has_ai = true
table.insert(self.io_map.analog_in, io_entry)
self.phy_io.analog_in[bank][port] = { phy = 0, req = 0 }
local io_f = {
read = function () return self.phy_io.analog_in[bank][port].phy end,
write = function () end
}
self.db.io[bank][port] = io_f
elseif mode == IO_MODE.ANALOG_OUT then
self.has_ao = true
table.insert(self.io_map.analog_out, io_entry)
self.phy_io.analog_out[bank][port] = { phy = 0, req = 0 }
local io_f = {
read = function () return self.phy_io.analog_out[bank][port].phy end,
write = function (value)
if value >= 0 and value <= 15 then
self.phy_io.analog_out[bank][port].req = value
end
end
}
self.db.io[bank][port] = io_f
else
log.error(util.c(log_tag, "failed to identify advertisement port IO mode (", bank, ":", port, ")"), true)
return nil
end
else
log.error(util.c(log_tag, "invalid advertisement port (", bank, ":", port, ")"), true)
return nil
end
end
end
local function _request_discrete_inputs()
self.session.send_request(TXN_TYPES.DI_READ, MODBUS_FCODE.READ_DISCRETE_INPUTS, { 1, #self.io_map.digital_in })
end
local function _request_input_registers()
self.session.send_request(TXN_TYPES.INPUT_REG_READ, MODBUS_FCODE.READ_INPUT_REGS, { 1, #self.io_map.analog_in })
end
local function _write_coils()
local params = { 1 }
local outputs = self.phy_io.digital_out
for i = 1, #self.io_map.digital_out do
local entry = self.io_map.digital_out[i]
table.insert(params, outputs[entry.bank][entry.port].req)
end
self.phy_trans.coils = self.session.send_request(TXN_TYPES.COIL_WRITE, MODBUS_FCODE.WRITE_MUL_COILS, params)
end
local function _read_coils()
self.session.send_request(TXN_TYPES.COIL_READ, MODBUS_FCODE.READ_COILS, { 1, #self.io_map.digital_out })
end
local function _write_holding_registers()
local params = { 1 }
local outputs = self.phy_io.analog_out
for i = 1, #self.io_map.analog_out do
local entry = self.io_map.analog_out[i]
table.insert(params, outputs[entry.bank][entry.port].req)
end
self.phy_trans.hold_regs = self.session.send_request(TXN_TYPES.HOLD_REG_WRITE, MODBUS_FCODE.WRITE_MUL_HOLD_REGS, params)
end
local function _read_holding_registers()
self.session.send_request(TXN_TYPES.HOLD_REG_READ, MODBUS_FCODE.READ_MUL_HOLD_REGS, { 1, #self.io_map.analog_out })
end
function public.handle_adu(adu)
local txn_type = self.session.try_resolve(adu)
if txn_type == false then
if adu.txn_id == self.phy_trans.coils then
self.phy_trans.coils = TXN_READY
log.debug(log_tag .. "failed to write coils, retrying soon")
elseif adu.txn_id == self.phy_trans.hold_regs then
self.phy_trans.hold_regs = TXN_READY
log.debug(log_tag .. "failed to write holding registers, retrying soon")
end
elseif txn_type == TXN_TYPES.DI_READ then
if adu.length == #self.io_map.digital_in then
for i = 1, adu.length do
local entry = self.io_map.digital_in[i]
local value = adu.data[i]
self.phy_io.digital_in[entry.bank][entry.port].phy = value
end
else self.session.log_length_mismatch(txn_type) end
elseif txn_type == TXN_TYPES.INPUT_REG_READ then
if adu.length == #self.io_map.analog_in then
for i = 1, adu.length do
local entry = self.io_map.analog_in[i]
local value = adu.data[i]
self.phy_io.analog_in[entry.bank][entry.port].phy = value
end
else self.session.log_length_mismatch(txn_type) end
elseif txn_type == TXN_TYPES.COIL_WRITE then
_read_coils()
elseif txn_type == TXN_TYPES.COIL_READ then
if adu.length == #self.io_map.digital_out then
for i = 1, adu.length do
local entry = self.io_map.digital_out[i]
local state = self.phy_io.digital_out[entry.bank][entry.port]
local value = adu.data[i]
state.phy = value
if state.req == IO_LVL.FLOATING then state.req = value end
end
self.phy_trans.coils = TXN_READY
else self.session.log_length_mismatch(txn_type) end
elseif txn_type == TXN_TYPES.HOLD_REG_WRITE then
_read_holding_registers()
elseif txn_type == TXN_TYPES.HOLD_REG_READ then
if adu.length == #self.io_map.analog_out then
for i = 1, adu.length do
local entry = self.io_map.analog_out[i]
local value = adu.data[i]
self.phy_io.analog_out[entry.bank][entry.port].phy = value
end
else self.session.log_length_mismatch(txn_type) end
self.phy_trans.hold_regs = TXN_READY
else self.session.log_resolve_fail(txn_type) end
end
function public.update(time_now)
if self.has_di then
if self.periodics.next_di_req <= time_now then
_request_discrete_inputs()
self.periodics.next_di_req = time_now + PERIODICS.INPUT_READ
end
end
if self.has_do then
if (self.periodics.next_cl_sync <= time_now) and (self.phy_trans.coils == TXN_READY) then
for bank = 0, 4 do
local changed = false
for _, entry in pairs(self.phy_io.digital_out[bank]) do
if entry.phy ~= entry.req then
changed = true
break
end
end
if changed then
_write_coils()
break
end
end
self.periodics.next_cl_sync = time_now + PERIODICS.OUTPUT_SYNC
end
end
if self.has_ai then
if self.periodics.next_ir_req <= time_now then
_request_input_registers()
self.periodics.next_ir_req = time_now + PERIODICS.INPUT_READ
end
end
if self.has_ao then
if (self.periodics.next_hr_sync <= time_now) and (self.phy_trans.hold_regs == TXN_READY) then
for bank = 0, 4 do
local changed = false
for _, entry in pairs(self.phy_io.analog_out[bank]) do
if entry.phy ~= entry.req then
changed = true
break
end
end
if changed then
_write_holding_registers()
break
end
end
self.periodics.next_hr_sync = time_now + PERIODICS.OUTPUT_SYNC
end
end
self.session.post_update()
end
function public.invalidate_cache()
_read_coils()
_read_holding_registers()
end
function public.get_db() return self.db end
return public
end
return redstone
