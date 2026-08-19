local comms    = require("scada-common.comms")
local log      = require("scada-common.log")
local mqueue   = require("scada-common.mqueue")
local types    = require("scada-common.types")
local util     = require("scada-common.util")
local databus  = require("supervisor.databus")
local svqtypes = require("supervisor.session.svqtypes")
local coordinator = {}
local PROTOCOL = comms.PROTOCOL
local MGMT_TYPE = comms.MGMT_TYPE
local CRDN_TYPE = comms.CRDN_TYPE
local UNIT_COMMAND = comms.UNIT_COMMAND
local FAC_COMMAND = comms.FAC_COMMAND
local AUTO_GROUP = types.AUTO_GROUP
local WASTE_MODE = types.WASTE_MODE
local SV_Q_DATA = svqtypes.SV_Q_DATA
local RETRY_PERIOD = 1000
local PARTIAL_RETRY_PERIOD = 2000
local CRD_S_CMDS = {
}
local CRD_S_DATA = {
CMD_ACK = 1,
RESEND_PLC_BUILD = 2,
RESEND_RTU_BUILD = 3
}
coordinator.CRD_S_CMDS = CRD_S_CMDS
coordinator.CRD_S_DATA = CRD_S_DATA
local PERIODICS = {
KEEP_ALIVE = 2000,
STATUS = 500
}
function coordinator.new_session(id, s_addr, i_seq_num, in_queue, out_queue, timeout, facility, fp_ok)
local function println(message) if not fp_ok then util.println_ts(message) end end
local log_tag = "crdn_session(" .. id .. "): "
local self = {
units = facility.get_units(),
seq_num = i_seq_num + 2,
r_seq_num = i_seq_num + 1,
connected = true,
conn_watchdog = util.new_watchdog(timeout),
establish_time = util.time_s(),
last_rtt = 0,
periodics = {
last_update = 0,
keep_alive = 0,
status_packet = 0
},
retry_times = {
builds_packet = 0,
f_builds_packet = 0,
u_builds_packet = 0
},
acks = {
builds = false,
fac_builds = false,
unit_builds = false
}
}
local function _close()
self.conn_watchdog.cancel()
self.connected = false
databus.tx_crd_disconnected()
end
local function _send(msg_type, msg)
local frame, crdn = comms.scada_frame(), comms.crdn_container()
crdn.make(msg_type, msg)
frame.make(s_addr, self.seq_num, PROTOCOL.SCADA_CRDN, crdn.raw_packet())
out_queue.push_network(frame)
self.seq_num = self.seq_num + 1
end
local function _send_mgmt(msg_type, msg)
local frame, mgmt = comms.scada_frame(), comms.mgmt_container()
mgmt.make(msg_type, msg)
frame.make(s_addr, self.seq_num, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
out_queue.push_network(frame)
self.seq_num = self.seq_num + 1
end
local function _send_all_builds()
local unit_builds = {}
for i = 1, #self.units do
local unit = self.units[i]
unit_builds[unit.get_id()] = unit.get_build()
end
_send(CRDN_TYPE.INITIAL_BUILDS, { facility.get_build(), unit_builds })
end
local function _send_fac_builds()
_send(CRDN_TYPE.FAC_BUILDS, { facility.get_build() })
end
local function _send_unit_builds()
local builds = {}
for i = 1, #self.units do
local unit = self.units[i]
builds[unit.get_id()] = unit.get_build()
end
_send(CRDN_TYPE.UNIT_BUILDS, { builds })
end
local function _send_fac_status()
local status = {
facility.get_control_status(),
facility.get_rtu_statuses(),
facility.get_alarm_tones(),
facility.get_valves()
}
_send(CRDN_TYPE.FAC_STATUS, status)
end
local function _send_unit_statuses()
local status = {}
for i = 1, #self.units do
local unit = self.units[i]
status[unit.get_id()] = {
unit.get_reactor_status(),
unit.get_rtu_statuses(),
unit.get_annunciator(),
unit.get_alarms(),
unit.get_state(),
unit.get_valves()
}
end
_send(CRDN_TYPE.UNIT_STATUSES, status)
end
local function _handle_packet(pkt)
if self.r_seq_num ~= pkt.scada_frame.seq_num() then
log.warning(log_tag .. "sequence out-of-order: next = " .. self.r_seq_num .. ", new = " .. pkt.scada_frame.seq_num())
return
else
self.r_seq_num = pkt.scada_frame.seq_num() + 1
end
self.conn_watchdog.feed()
if pkt.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
if pkt.type == MGMT_TYPE.KEEP_ALIVE then
if pkt.length == 2 then
local srv_start = pkt.data[1]
local srv_now = util.time()
self.last_rtt = srv_now - srv_start
if self.last_rtt > 750 then
log.warning(log_tag .. "COORD KEEP_ALIVE round trip time > 750ms (" .. self.last_rtt .. "ms)")
end
databus.tx_crd_rtt(self.last_rtt)
else
log.debug(log_tag .. "SCADA keep alive packet length mismatch")
end
elseif pkt.type == MGMT_TYPE.CLOSE then
_close()
elseif pkt.type == MGMT_TYPE.SWITCH_NET then
log.debug(log_tag .. "received valid connection switch request")
elseif pkt.type == MGMT_TYPE.ESTABLISH then
_close()
log.warning(log_tag .. "terminated session due to an unexpected ESTABLISH packet")
else
log.debug(log_tag .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
end
elseif pkt.scada_frame.protocol() == PROTOCOL.SCADA_CRDN then
if pkt.type == CRDN_TYPE.INITIAL_BUILDS then
self.acks.builds = true
elseif pkt.type == CRDN_TYPE.PROCESS_READY then
if pkt.length == 7 then
local config = {
mode = pkt.data[1],
burn_target = pkt.data[2],
range_start = pkt.data[3],
range_stop = pkt.data[4],
charge_target = pkt.data[5],
gen_target = pkt.data[6],
limits = pkt.data[7]
}
facility.boot_recovery_start(config)
else
log.debug(log_tag .. "CRDN process ready packet length mismatch")
end
elseif pkt.type == CRDN_TYPE.FAC_BUILDS then
self.acks.fac_builds = true
elseif pkt.type == CRDN_TYPE.FAC_CMD then
if pkt.length >= 1 then
local cmd = pkt.data[1]
if cmd == FAC_COMMAND.SCRAM_ALL then
facility.scram_all()
facility.cancel_recovery()
_send(CRDN_TYPE.FAC_CMD, { cmd, true })
elseif cmd == FAC_COMMAND.STOP then
facility.cancel_recovery()
local was_active = facility.auto_is_active()
if was_active then
facility.auto_stop()
end
_send(CRDN_TYPE.FAC_CMD, { cmd, was_active })
elseif cmd == FAC_COMMAND.START then
facility.cancel_recovery()
if pkt.length == 8 then
local config = {
mode = pkt.data[2],
burn_target = pkt.data[3],
range_start = pkt.data[4],
range_stop = pkt.data[5],
charge_target = pkt.data[6],
gen_target = pkt.data[7],
limits = pkt.data[8]
}
_send(CRDN_TYPE.FAC_CMD, { cmd, table.unpack(facility.auto_start(config)) })
else
log.debug(log_tag .. "CRDN auto start (with configuration) packet length mismatch")
end
elseif cmd == FAC_COMMAND.ACK_ALL_ALARMS then
facility.ack_all()
_send(CRDN_TYPE.FAC_CMD, { cmd, true })
elseif cmd == FAC_COMMAND.SET_WASTE_MODE then
if pkt.length == 2 then
_send(CRDN_TYPE.FAC_CMD, { cmd, facility.set_waste_product(pkt.data[2]) })
else
log.debug(log_tag .. "CRDN set waste mode packet length mismatch")
end
elseif cmd == FAC_COMMAND.SET_PU_FB then
if pkt.length == 2 then
_send(CRDN_TYPE.FAC_CMD, { cmd, facility.set_pu_fallback(pkt.data[2] == true) })
else
log.debug(log_tag .. "CRDN set pu fallback packet length mismatch")
end
elseif cmd == FAC_COMMAND.SET_SPS_LP then
if pkt.length == 2 then
_send(CRDN_TYPE.FAC_CMD, { cmd, facility.set_sps_low_power(pkt.data[2] == true) })
else
log.debug(log_tag .. "CRDN set sps low power packet length mismatch")
end
else
log.debug(log_tag .. "CRDN facility command unknown")
end
else
log.debug(log_tag .. "CRDN facility command packet length mismatch")
end
elseif pkt.type == CRDN_TYPE.UNIT_BUILDS then
self.acks.unit_builds = true
elseif pkt.type == CRDN_TYPE.UNIT_CMD then
if pkt.length >= 2 then
local cmd = pkt.data[1]
local uid = pkt.data[2]
local data = { uid, pkt.data[3] }
if util.is_int(uid) and uid > 0 and uid <= #self.units then
local unit   = self.units[uid]
local manual = facility.get_group(uid) == AUTO_GROUP.MANUAL
if cmd == UNIT_COMMAND.SCRAM then
facility.cancel_recovery()
out_queue.push_data(SV_Q_DATA.SCRAM, data)
elseif cmd == UNIT_COMMAND.START then
facility.cancel_recovery()
if manual then
out_queue.push_data(SV_Q_DATA.START, data)
else
_send(CRDN_TYPE.UNIT_CMD, { cmd, uid, false })
end
elseif cmd == UNIT_COMMAND.RESET_RPS then
out_queue.push_data(SV_Q_DATA.RESET_RPS, data)
elseif cmd == UNIT_COMMAND.SET_BURN then
facility.cancel_recovery()
if pkt.length == 3 then
if manual then
out_queue.push_data(SV_Q_DATA.SET_BURN, data)
end
else
log.debug(log_tag .. "CRDN unit command burn rate missing option")
end
elseif cmd == UNIT_COMMAND.SET_WASTE then
if (pkt.length == 3) and (type(pkt.data[3]) == "number") and
(pkt.data[3] >= WASTE_MODE.AUTO) and (pkt.data[3] <= WASTE_MODE.MANUAL_ANTI_MATTER) then
unit.set_waste_mode(pkt.data[3])
else
log.debug(log_tag .. "CRDN unit command set waste missing/invalid option")
end
elseif cmd == UNIT_COMMAND.ACK_ALL_ALARMS then
unit.ack_all()
_send(CRDN_TYPE.UNIT_CMD, { cmd, uid, true })
elseif cmd == UNIT_COMMAND.ACK_ALARM then
if pkt.length == 3 then
unit.ack_alarm(pkt.data[3])
else
log.debug(log_tag .. "CRDN unit command ack alarm missing alarm id")
end
elseif cmd == UNIT_COMMAND.RESET_ALARM then
if pkt.length == 3 then
unit.reset_alarm(pkt.data[3])
else
log.debug(log_tag .. "CRDN unit command reset alarm missing alarm id")
end
elseif cmd == UNIT_COMMAND.SET_GROUP then
facility.cancel_recovery()
if (pkt.length == 3) and (type(pkt.data[3]) == "number") and
(pkt.data[3] >= AUTO_GROUP.MANUAL) and (pkt.data[3] <= AUTO_GROUP.BACKUP) then
facility.set_group(unit.get_id(), pkt.data[3])
else
log.debug(log_tag .. "CRDN unit command set group missing group id")
end
else
log.debug(log_tag .. "CRDN unit command unknown")
end
else
log.debug(log_tag .. "CRDN unit command invalid")
end
else
log.debug(log_tag .. "CRDN unit command packet length mismatch")
end
else
log.debug(log_tag .. "handler received unexpected SCADA_CRDN packet type " .. pkt.type)
end
end
end
local public = {}
function public.get_id() return id end
function public.check_wd(timer)
return self.conn_watchdog.is_timer(timer) and self.connected
end
function public.close()
_close()
_send_mgmt(MGMT_TYPE.CLOSE, {})
println("与协调器的连接 " .. id .. " 已由服务器关闭")
log.info(log_tag .. "会话已由服务器关闭")
end
function public.iterate()
if self.connected then
local handle_start = util.time()
while in_queue.ready() and self.connected do
local message = in_queue.pop()
if message ~= nil then
if message.qtype == mqueue.TYPE.NETWORK then
_handle_packet(message.message)
elseif message.qtype == mqueue.TYPE.DATA then
local cmd = message.message
if cmd.key == CRD_S_DATA.CMD_ACK then
local ack = cmd.val
_send(CRDN_TYPE.UNIT_CMD, { ack.cmd, ack.unit, ack.ack })
elseif cmd.key == CRD_S_DATA.RESEND_PLC_BUILD then
self.retry_times.builds_packet = util.time() + PARTIAL_RETRY_PERIOD
self.acks.unit_builds = false
local unit_id = cmd.val
local builds = {}
builds[unit_id] = self.units[unit_id].get_build(-1)
_send(CRDN_TYPE.UNIT_BUILDS, { builds })
elseif cmd.key == CRD_S_DATA.RESEND_RTU_BUILD then
local unit_id = cmd.val.unit
if unit_id > 0 then
self.retry_times.u_builds_packet = util.time() + PARTIAL_RETRY_PERIOD
self.acks.unit_builds = false
local builds = {}
builds[unit_id] = self.units[unit_id].get_build(cmd.val.type)
_send(CRDN_TYPE.UNIT_BUILDS, { builds })
else
self.retry_times.f_builds_packet = util.time() + PARTIAL_RETRY_PERIOD
self.acks.fac_builds = false
_send(CRDN_TYPE.FAC_BUILDS, { facility.get_build(cmd.val.type) })
end
else
log.error(log_tag .. "unsupported data command received in in_queue (this is a bug)", true)
end
end
end
if util.time() - handle_start > 100 then
log.warning(log_tag .. "exceeded 100ms queue process limit")
break
end
end
if not self.connected then
println("与协调器的连接已由远程主机关闭")
log.info(log_tag .. "会话已由远程主机关闭")
return self.connected
end
local elapsed = util.time() - self.periodics.last_update
local periodics = self.periodics
periodics.keep_alive = periodics.keep_alive + elapsed
if periodics.keep_alive >= PERIODICS.KEEP_ALIVE then
_send_mgmt(MGMT_TYPE.KEEP_ALIVE, { util.time() })
periodics.keep_alive = 0
end
periodics.status_packet = periodics.status_packet + elapsed
if periodics.status_packet >= PERIODICS.STATUS then
_send_fac_status()
_send_unit_statuses()
periodics.status_packet = 0
end
self.periodics.last_update = util.time()
local rtimes = self.retry_times
if not self.acks.builds then
if rtimes.builds_packet - util.time() <= 0 then
_send_all_builds()
rtimes.builds_packet = util.time() + RETRY_PERIOD
end
end
if not self.acks.fac_builds then
if rtimes.f_builds_packet - util.time() <= 0 then
_send_fac_builds()
rtimes.f_builds_packet = util.time() + RETRY_PERIOD
end
end
if not self.acks.unit_builds then
if rtimes.u_builds_packet - util.time() <= 0 then
_send_unit_builds()
rtimes.u_builds_packet = util.time() + RETRY_PERIOD
end
end
end
return self.connected
end
return public
end
return coordinator
