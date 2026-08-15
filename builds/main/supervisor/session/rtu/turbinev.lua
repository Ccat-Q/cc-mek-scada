local log          = require("scada-common.log")
local mqueue       = require("scada-common.mqueue")
local types        = require("scada-common.types")
local util         = require("scada-common.util")
local qtypes       = require("supervisor.session.rtu.qtypes")
local unit_session = require("supervisor.session.rtu.unit_session")
local turbinev = {}
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local DUMPING_MODE = types.DUMPING_MODE
local MODBUS_FCODE = types.MODBUS_FCODE
local TBV_RTU_S_CMDS = qtypes.TBV_RTU_S_CMDS
local TBV_RTU_S_DATA = qtypes.TBV_RTU_S_DATA
local TXN_TYPES = {
FORMED = 1,
BUILD = 2,
STATE = 3,
TANKS = 4,
INC_DUMP = 5,
DEC_DUMP = 6,
SET_DUMP = 7
}
local TXN_TAGS = {
"turbinev.formed",
"turbinev.build",
"turbinev.state",
"turbinev.tanks",
"turbinev.inc_dump",
"turbinev.dec_dump",
"turbinev.set_dump"
}
local PERIODICS = {
FORMED = 2000,
BUILD = 1000,
STATE = 500,
TANKS = 1000
}
local WRITE_BUSY_WAIT = 1000
function turbinev.new(session_id, unit_id, advert, out_queue)
if advert.type ~= RTU_UNIT_TYPE.TURBINE_VALVE then
log.error("attempt to instantiate turbinev RTU for type " .. types.rtu_type_to_string(advert.type))
return nil
elseif not util.is_int(advert.index) then
log.error("attempt to instantiate turbinev RTU without index")
return nil
end
local log_tag = util.c("session.rtu(", session_id, ").turbinev(", advert.index, ")[@", unit_id, "]: ")
local self = {
session = unit_session.new(session_id, unit_id, advert, out_queue, log_tag, TXN_TAGS),
has_build = false,
mode_cmd = nil,
resend_mode = false,
periodics = {
next_formed_req = 0,
next_build_req = 0,
next_state_req = 0,
next_tanks_req = 0
},
db = {
formed = false,
build = {
last_update = 0,
length = 0,
width = 0,
height = 0,
min_pos = types.new_zero_coordinate(),
max_pos = types.new_zero_coordinate(),
blades = 0,
coils = 0,
vents = 0,
dispersers = 0,
condensers = 0,
steam_cap = 0,
max_energy = 0,
max_flow_rate = 0,
max_production = 0,
max_water_output = 0
},
state = {
last_update = 0,
flow_rate = 0,
prod_rate = 0,
steam_input_rate = 0,
dumping_mode = DUMPING_MODE.IDLE
},
tanks = {
last_update = 0,
steam = types.new_empty_gas(),
steam_need = 0,
steam_fill = 0.0,
energy = 0,
energy_need = 0,
energy_fill = 0.0
}
}
}
local public = self.session.get()
local function _inc_dump_mode()
if self.mode_cmd == "IDLE" then self.mode_cmd = "DUMPING_EXCESS"
elseif self.mode_cmd == "DUMPING_EXCESS" then self.mode_cmd = "DUMPING"
elseif self.mode_cmd == "DUMPING" then self.mode_cmd = "IDLE"
end
if self.session.send_request(TXN_TYPES.INC_DUMP, MODBUS_FCODE.WRITE_SINGLE_COIL, { 1, 0 }, WRITE_BUSY_WAIT) == false then
self.resend_mode = true
end
end
local function _dec_dump_mode()
if self.mode_cmd == "IDLE" then self.mode_cmd = "DUMPING"
elseif self.mode_cmd == "DUMPING_EXCESS" then self.mode_cmd = "IDLE"
elseif self.mode_cmd == "DUMPING" then self.mode_cmd = "DUMPING_EXCESS"
end
if self.session.send_request(TXN_TYPES.DEC_DUMP, MODBUS_FCODE.WRITE_SINGLE_COIL, { 2, 0 }, WRITE_BUSY_WAIT) == false then
self.resend_mode = true
end
end
local function _set_dump_mode(mode)
self.mode_cmd = mode
if self.session.send_request(TXN_TYPES.SET_DUMP, MODBUS_FCODE.WRITE_SINGLE_HOLD_REG, { 1, mode }, WRITE_BUSY_WAIT) == false then
self.resend_mode = true
end
end
local function _request_formed(time_now)
if self.session.send_request(TXN_TYPES.FORMED, MODBUS_FCODE.READ_DISCRETE_INPUTS, { 1, 1 }) ~= false then
self.periodics.next_formed_req = time_now + PERIODICS.FORMED
end
end
local function _request_build(time_now)
if self.session.send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 15 }) ~= false then
self.periodics.next_build_req = time_now + PERIODICS.BUILD
end
end
local function _request_state(time_now)
if self.session.send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_INPUT_REGS, { 16, 4 }) ~= false then
self.periodics.next_state_req = time_now + PERIODICS.STATE
end
end
local function _request_tanks(time_now)
if self.session.send_request(TXN_TYPES.TANKS, MODBUS_FCODE.READ_INPUT_REGS, { 20, 6 }) ~= false then
self.periodics.next_tanks_req = time_now + PERIODICS.TANKS
end
end
function public.handle_adu(adu)
local txn_type = self.session.try_resolve(adu)
if txn_type == false then
elseif txn_type == TXN_TYPES.FORMED then
if adu.length == 1 then
self.db.formed = adu.data[1]
if not self.db.formed then self.has_build = false end
else self.session.log_length_mismatch(txn_type) end
elseif txn_type == TXN_TYPES.BUILD then
if adu.length == 15 then
self.db.build.last_update      = util.time_ms()
self.db.build.length           = adu.data[1]
self.db.build.width            = adu.data[2]
self.db.build.height           = adu.data[3]
self.db.build.min_pos          = adu.data[4]
self.db.build.max_pos          = adu.data[5]
self.db.build.blades           = adu.data[6]
self.db.build.coils            = adu.data[7]
self.db.build.vents            = adu.data[8]
self.db.build.dispersers       = adu.data[9]
self.db.build.condensers       = adu.data[10]
self.db.build.steam_cap        = adu.data[11]
self.db.build.max_energy       = adu.data[12]
self.db.build.max_flow_rate    = adu.data[13]
self.db.build.max_production   = adu.data[14]
self.db.build.max_water_output = adu.data[15]
self.has_build = true
out_queue.push_data(unit_session.RTU_US_DATA.BUILD_CHANGED, { unit = advert.reactor, type = advert.type })
else self.session.log_length_mismatch(txn_type) end
elseif txn_type == TXN_TYPES.STATE then
if adu.length == 4 then
self.db.state.last_update      = util.time_ms()
self.db.state.flow_rate        = adu.data[1]
self.db.state.prod_rate        = adu.data[2]
self.db.state.steam_input_rate = adu.data[3]
self.db.state.dumping_mode     = adu.data[4]
if self.mode_cmd == nil then
self.mode_cmd = self.db.state.dumping_mode
end
else self.session.log_length_mismatch(txn_type) end
elseif txn_type == TXN_TYPES.TANKS then
if adu.length == 6 then
self.db.tanks.last_update = util.time_ms()
self.db.tanks.steam       = adu.data[1]
self.db.tanks.steam_need  = adu.data[2]
self.db.tanks.steam_fill  = adu.data[3]
self.db.tanks.energy      = adu.data[4]
self.db.tanks.energy_need = adu.data[5]
self.db.tanks.energy_fill = adu.data[6]
else self.session.log_length_mismatch(txn_type) end
elseif txn_type == TXN_TYPES.INC_DUMP or txn_type == TXN_TYPES.DEC_DUMP or txn_type == TXN_TYPES.SET_DUMP then
else self.session.log_resolve_fail(txn_type) end
end
function public.update(time_now)
while self.session.in_q.ready() do
local msg = self.session.in_q.pop()
if msg ~= nil then
if msg.qtype == mqueue.TYPE.COMMAND then
local cmd = msg.message
if cmd == TBV_RTU_S_CMDS.INC_DUMP_MODE then
_inc_dump_mode()
elseif cmd == TBV_RTU_S_CMDS.DEC_DUMP_MODE then
_dec_dump_mode()
else
log.debug(util.c(log_tag, "unrecognized in-queue command ", cmd))
end
elseif msg.qtype == mqueue.TYPE.DATA then
local cmd = msg.message
if cmd.key == TBV_RTU_S_DATA.SET_DUMP_MODE then
if cmd.val == types.DUMPING_MODE.IDLE or
cmd.val == types.DUMPING_MODE.DUMPING_EXCESS or
cmd.val == types.DUMPING_MODE.DUMPING then
_set_dump_mode(cmd.val)
else
log.debug(util.c(log_tag, "unrecognized dumping mode \"", cmd.val, "\""))
end
else
log.debug(util.c(log_tag, "unrecognized in-queue data ", cmd.key))
end
end
end
if util.time() - time_now > 100 then
log.warning(log_tag .. "exceeded 100ms queue process limit")
break
end
end
if self.resend_mode then
self.resend_mode = false
_set_dump_mode(self.mode_cmd)
end
time_now = util.time()
if self.periodics.next_formed_req <= time_now then _request_formed(time_now) end
if self.db.formed then
if not self.has_build and self.periodics.next_build_req <= time_now then _request_build(time_now) end
if self.periodics.next_state_req <= time_now then _request_state(time_now) end
if self.periodics.next_tanks_req <= time_now then _request_tanks(time_now) end
end
self.session.post_update()
end
function public.invalidate_cache()
self.periodics.next_formed_req = 0
self.periodics.next_build_req = 0
self.has_build = false
end
function public.get_db() return self.db end
return public
end
return turbinev
