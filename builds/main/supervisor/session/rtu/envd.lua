local log          = require("scada-common.log")
local types        = require("scada-common.types")
local util         = require("scada-common.util")
local unit_session = require("supervisor.session.rtu.unit_session")
local envd = {}
local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local MODBUS_FCODE = types.MODBUS_FCODE
local TXN_TYPES = {
RAD = 1
}
local TXN_TAGS = {
"envd.radiation"
}
local PERIODICS = {
RAD = 500
}
function envd.new(session_id, unit_id, advert, out_queue)
if advert.type ~= RTU_UNIT_TYPE.ENV_DETECTOR then
log.error("尝试为类型 " .. types.rtu_type_to_string(advert.type) .. " 实例化 envd RTU")
return nil
elseif not util.is_int(advert.index) then
log.error("尝试在没有索引的情况下实例化 envd RTU")
return nil
end
local log_tag = util.c("session.rtu(", session_id, ").envd(", advert.index, ")[@", unit_id, "]: ")
local self = {
session = unit_session.new(session_id, unit_id, advert, out_queue, log_tag, TXN_TAGS),
periodics = {
next_rad_req = 0
},
db = {
last_update = 0,
radiation = types.new_zero_radiation_reading(),
radiation_raw = 0
}
}
local public = self.session.get()
local function _request_radiation(time_now)
if self.session.send_request(TXN_TYPES.RAD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 2 }) ~= false then
self.periodics.next_rad_req = time_now + PERIODICS.RAD
end
end
function public.handle_adu(adu)
local txn_type = self.session.try_resolve(adu)
if txn_type == false then
elseif txn_type == TXN_TYPES.RAD then
if adu.length == 2 then
self.db.last_update   = util.time_ms()
self.db.radiation     = adu.data[1]
self.db.radiation_raw = adu.data[2]
else self.session.log_length_mismatch(txn_type) end
else self.session.log_resolve_fail(txn_type) end
end
function public.update(time_now)
if self.periodics.next_rad_req <= time_now then _request_radiation(time_now) end
self.session.post_update()
end
function public.invalidate_cache()
end
function public.get_db() return self.db end
return public
end
return envd
