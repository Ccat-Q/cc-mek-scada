local comms   = require("scada-common.comms")
local log     = require("scada-common.log")
local mqueue  = require("scada-common.mqueue")
local types   = require("scada-common.types")
local util    = require("scada-common.util")
local txnctrl = require("supervisor.session.rtu.txnctrl")
local unit_session = {}
local PROTOCOL = comms.PROTOCOL
local MODBUS_FCODE = types.MODBUS_FCODE
local MODBUS_EXCODE = types.MODBUS_EXCODE
local RTU_US_CMDS = {
}
local RTU_US_DATA = {
BUILD_CHANGED = 1
}
unit_session.RTU_US_CMDS = RTU_US_CMDS
unit_session.RTU_US_DATA = RTU_US_DATA
local DEFAULT_BUSY_WAIT = 3000
function unit_session.new(session_id, unit_id, advert, out_queue, log_tag, txn_tags)
local self = {
device_index = advert.index,
reactor = advert.reactor,
transaction_controller = txnctrl.new(),
connected = true,
device_fail = false,
last_busy = 0
}
local protected = {
in_q = mqueue.new()
}
local public = {}
function protected.send_request(txn_type, f_code, register_param, busy_wait)
local txn_id = false
busy_wait = busy_wait or DEFAULT_BUSY_WAIT
if (util.time_ms() - self.last_busy) >= busy_wait then
local modbus = comms.modbus_container()
txn_id = self.transaction_controller.create(txn_type)
modbus.make(txn_id, unit_id, f_code, register_param)
out_queue.push_network(modbus)
end
return txn_id
end
function protected.try_resolve(adu)
if adu.scada_frame.protocol() == PROTOCOL.MODBUS_TCP then
if adu.unit_id == unit_id then
local txn_type = self.transaction_controller.resolve(adu.txn_id)
local txn_tag = util.c(" (", txn_tags[txn_type], ")")
if txn_type == nil then
log.debug(log_tag .. "MODBUS: expired or spurious transaction reply (txn_id " .. adu.txn_id .. ")")
return false, adu.txn_id
end
if bit.band(adu.func_code, MODBUS_FCODE.ERROR_FLAG) ~= 0 then
local ex = adu.data[1]
if ex == MODBUS_EXCODE.ILLEGAL_FUNCTION then
log.error(log_tag .. "MODBUS: illegal function" .. txn_tag)
elseif ex == MODBUS_EXCODE.ILLEGAL_DATA_ADDR then
log.error(log_tag .. "MODBUS: illegal data address" .. txn_tag)
elseif ex == MODBUS_EXCODE.SERVER_DEVICE_FAIL then
if self.device_fail then
log.debug(log_tag .. "MODBUS: repeated device failure" .. txn_tag)
else
self.device_fail = true
log.warning(log_tag .. "MODBUS: device failure" .. txn_tag)
end
elseif ex == MODBUS_EXCODE.ACKNOWLEDGE then
self.transaction_controller.renew(adu.txn_id, txn_type)
elseif ex == MODBUS_EXCODE.SERVER_DEVICE_BUSY then
self.last_busy = util.time_ms()
log.warning(log_tag .. "MODBUS: device busy" .. txn_tag)
elseif ex == MODBUS_EXCODE.NEG_ACKNOWLEDGE then
log.error(log_tag .. "MODBUS: negative acknowledge (bad request)" .. txn_tag)
elseif ex == MODBUS_EXCODE.GATEWAY_PATH_UNAVAILABLE then
log.error(log_tag .. "MODBUS: gateway path unavailable (unknown unit)" .. txn_tag)
elseif ex ~= nil then
log.debug(log_tag .. "MODBUS: unsupported error " .. ex .. txn_tag)
else
log.debug(log_tag .. "MODBUS: nil exception code" .. txn_tag)
end
else
self.device_fail = false
return txn_type, adu.txn_id
end
else
log.error(log_tag .. "wrong unit ID: " .. adu.unit_id, true)
end
else
log.error(log_tag .. "illegal packet type " .. adu.scada_frame.protocol(), true)
end
return false, adu.txn_id
end
function protected.post_update()
self.transaction_controller.cleanup()
end
function protected.log_length_mismatch(txn_type)
log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. txn_tags[txn_type] .. ")")
end
function protected.log_resolve_fail(txn_type)
log.error(log_tag .. "unknown transaction " .. util.trinary(txn_type == nil, "reply", util.c("type ", txn_type)))
end
function protected.get() return public end
function public.get_session_id() return session_id end
function public.get_unit_id() return unit_id end
function public.get_unit_type() return advert.type end
function public.get_device_idx() return self.device_index or 0 end
function public.get_reactor() return self.reactor end
function public.get_cmd_queue() return protected.in_q end
function public.close() self.connected = false end
function public.is_connected() return self.connected end
function public.is_faulted() return self.device_fail end
function public.handle_adu(adu)
log.debug("template unit_session.handle_adu() called", true)
end
function public.update(time_now)
log.debug("template unit_session.update() called", true)
end
function public.invalidate_cache()
log.debug("template unit_session.invalidate_cache() called", true)
end
function public.get_db()
log.debug("template unit_session.get_db() called", true)
return {}
end
return protected
end
return unit_session
