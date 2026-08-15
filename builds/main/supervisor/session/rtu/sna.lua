local log          = require("scada-common.log")
local types        = require("scada-common.types")
local util         = require("scada-common.util")
local unit_session = require("supervisor.session.rtu.unit_session")
local sna = {}
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local MODBUS_FCODE = types.MODBUS_FCODE
local TXN_TYPES = {
BUILD = 1,
STATE = 2,
TANKS = 3
}
local TXN_TAGS = {
"sna.build",
"sna.state",
"sna.tanks"
}
local PERIODICS = {
BUILD = 1000,
STATE = 500,
TANKS = 1000
}
function sna.new(session_id, unit_id, advert, out_queue)
if advert.type ~= RTU_UNIT_TYPE.SNA then
log.error("attempt to instantiate sna RTU for type " .. types.rtu_type_to_string(advert.type))
return nil
end
local log_tag = util.c("session.rtu(", session_id, ").sna[@", unit_id, "]: ")
local self = {
session = unit_session.new(session_id, unit_id, advert, out_queue, log_tag, TXN_TAGS),
has_build = false,
periodics = {
next_build_req = 0,
next_state_req = 0,
next_tanks_req = 0
},
db = {
build = {
last_update = 0,
input_cap = 0,
output_cap = 0
},
state = {
last_update = 0,
production_rate = 0.0,
peak_production = 0.0
},
tanks = {
last_update = 0,
input = types.new_empty_gas(),
input_need = 0,
input_fill = 0.0,
output = types.new_empty_gas(),
output_need = 0,
output_fill = 0.0
}
}
}
local public = self.session.get()
local function _request_build(time_now)
if self.session.send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 2 }) ~= false then
self.periodics.next_build_req = time_now + PERIODICS.BUILD
end
end
local function _request_state(time_now)
if self.session.send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_INPUT_REGS, { 3, 2 }) ~= false then
self.periodics.next_state_req = time_now + PERIODICS.STATE
end
end
local function _request_tanks(time_now)
if self.session.send_request(TXN_TYPES.TANKS, MODBUS_FCODE.READ_INPUT_REGS, { 5, 6 }) ~= false then
self.periodics.next_tanks_req = time_now + PERIODICS.TANKS
end
end
function public.handle_adu(adu)
local txn_type = self.session.try_resolve(adu)
if txn_type == false then
elseif txn_type == TXN_TYPES.BUILD then
if adu.length == 2 then
self.db.build.last_update = util.time_ms()
self.db.build.input_cap   = adu.data[1]
self.db.build.output_cap  = adu.data[2]
self.has_build = true
out_queue.push_data(unit_session.RTU_US_DATA.BUILD_CHANGED, { unit = advert.reactor, type = advert.type })
else self.session.log_length_mismatch(txn_type) end
elseif txn_type == TXN_TYPES.STATE then
if adu.length == 2 then
self.db.state.last_update     = util.time_ms()
self.db.state.production_rate = adu.data[1]
self.db.state.peak_production = adu.data[2]
else self.session.log_length_mismatch(txn_type) end
elseif txn_type == TXN_TYPES.TANKS then
if adu.length == 6 then
self.db.tanks.last_update = util.time_ms()
self.db.tanks.input       = adu.data[1]
self.db.tanks.input_need  = adu.data[2]
self.db.tanks.input_fill  = adu.data[3]
self.db.tanks.output      = adu.data[4]
self.db.tanks.output_need = adu.data[5]
self.db.tanks.output_fill = adu.data[6]
else self.session.log_length_mismatch(txn_type) end
else self.session.log_resolve_fail(txn_type) end
end
function public.update(time_now)
if not self.has_build and self.periodics.next_build_req <= time_now then _request_build(time_now) end
if self.periodics.next_state_req <= time_now then _request_state(time_now) end
if self.periodics.next_tanks_req <= time_now then _request_tanks(time_now) end
self.session.post_update()
end
function public.invalidate_cache()
self.periodics.next_build_req = 0
self.has_build = false
end
function public.get_db() return self.db end
return public
end
return sna
