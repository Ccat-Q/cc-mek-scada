local comms   = require("scada-common.comms")
local log     = require("scada-common.log")
local mqueue  = require("scada-common.mqueue")
local util    = require("scada-common.util")
local databus = require("supervisor.databus")
local pocket = {}
local DEV_TYPE = comms.DEVICE_TYPE
local PROTOCOL = comms.PROTOCOL
local MGMT_TYPE = comms.MGMT_TYPE
local POCKET_S_CMDS = {
}
local POCKET_S_DATA = {
}
pocket.POCKET_S_CMDS = POCKET_S_CMDS
pocket.POCKET_S_DATA = POCKET_S_DATA
local PERIODICS = {
KEEP_ALIVE = 2000
}
function pocket.new_session(id, s_addr, i_seq_num, in_queue, out_queue, timeout, sessions, facility, fp_ok, allow_test)
local function println(message) if not fp_ok then util.println_ts(message) end end
local log_tag = "pdg_session(" .. id .. "): "
local self = {
seq_num = i_seq_num + 2,
r_seq_num = i_seq_num + 1,
connected = true,
conn_watchdog = util.new_watchdog(timeout),
last_rtt = 0,
periodics = {
last_update = 0,
keep_alive = 0
},
retry_times = {
},
acks = {
},
sDB = {
}
}
local public = {}
local function _close()
self.conn_watchdog.cancel()
self.connected = false
databus.tx_pdg_disconnected(id)
end
local function _send_mgmt(msg_type, msg)
local frame, mgmt = comms.scada_frame(), comms.mgmt_container()
mgmt.make(msg_type, msg)
frame.make(s_addr, self.seq_num, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
out_queue.push_network(frame)
self.seq_num = self.seq_num + 1
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
log.warning(log_tag .. "PDG KEEP_ALIVE round trip time > 750ms (" .. self.last_rtt .. "ms)")
end
databus.tx_pdg_rtt(id, self.last_rtt)
else
log.debug(log_tag .. "SCADA keep alive packet length mismatch")
end
elseif pkt.type == MGMT_TYPE.CLOSE then
_close()
elseif pkt.type == MGMT_TYPE.ESTABLISH then
_close()
log.warning(log_tag .. "terminated session due to an unexpected ESTABLISH packet")
elseif pkt.type == MGMT_TYPE.DIAG_TONE_GET then
_send_mgmt(MGMT_TYPE.DIAG_TONE_GET, facility.get_alarm_tones())
elseif pkt.type == MGMT_TYPE.DIAG_TONE_SET then
local valid = false
if allow_test then
if pkt.length == 2 then
if type(pkt.data[1]) == "number" and type(pkt.data[2]) == "boolean" then
valid = true
local allow_testing, test_tone_states = facility.diag_set_test_tone(pkt.data[1], pkt.data[2])
_send_mgmt(MGMT_TYPE.DIAG_TONE_SET, { allow_testing, test_tone_states })
else log.debug(log_tag .. "SCADA diag tone set packet data type mismatch") end
else log.debug(log_tag .. "SCADA diag tone set packet length mismatch") end
else log.warning(log_tag .. "DIAG_TONE_SET is blocked without pocket test commands enabled") end
if not valid then _send_mgmt(MGMT_TYPE.DIAG_TONE_SET, { false }) end
elseif pkt.type == MGMT_TYPE.DIAG_ALARM_SET then
local valid = false
if allow_test then
if pkt.length == 2 then
if type(pkt.data[1]) == "number" and type(pkt.data[2]) == "boolean" then
valid = true
local allow_testing, test_alarm_states = facility.diag_set_test_alarm(pkt.data[1], pkt.data[2])
_send_mgmt(MGMT_TYPE.DIAG_ALARM_SET, { allow_testing, test_alarm_states })
else log.debug(log_tag .. "SCADA diag alarm set packet data type mismatch") end
else log.debug(log_tag .. "SCADA diag alarm set packet length mismatch") end
else log.warning(log_tag .. "DIAG_ALARM_SET is blocked without pocket test commands enabled") end
if not valid then _send_mgmt(MGMT_TYPE.DIAG_ALARM_SET, { false }) end
elseif pkt.type == MGMT_TYPE.INFO_LIST_CMP then
local get = databus.ps.get
local devices = { { DEV_TYPE.SVR, os.getComputerID(), get("version"), 0 } }
if get("crd_conn") then
table.insert(devices, { DEV_TYPE.CRD, get("crd_addr"), get("crd_fw"), get("crd_rtt") })
end
for i = 1, #facility.get_units() do
local tag = "plc_" .. i
local addr = -1
for _, s in ipairs(sessions.plc) do
if s.reactor == i then
addr = s.s_addr
break
end
end
if get(tag .. "_conn") then
table.insert(devices, { DEV_TYPE.PLC, addr, get(tag .. "_fw"), get(tag .. "_rtt"), i })
end
end
for i = 1, #sessions.rtu do
local s = sessions.rtu[i]
table.insert(devices, { DEV_TYPE.RTU, s.s_addr, s.version, get("rtu_" .. s.instance.get_id() .. "_rtt") })
end
for i = 1, #sessions.pdg do
local s = sessions.pdg[i]
table.insert(devices, { DEV_TYPE.PKT, s.s_addr, s.version, get("pdg_" .. s.instance.get_id() .. "_rtt") })
end
_send_mgmt(MGMT_TYPE.INFO_LIST_CMP, devices)
else
log.debug(log_tag .. "handler received unsupported SCADA_MGMT packet type " .. pkt.type)
end
end
end
function public.get_id() return id end
function public.get_db() return self.sDB end
function public.check_wd(timer)
return self.conn_watchdog.is_timer(timer) and self.connected
end
function public.close()
_close()
_send_mgmt(MGMT_TYPE.CLOSE, {})
println("与口袋诊断会话 " .. id .. " 的连接已由服务器关闭")
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
end
end
if util.time() - handle_start > 100 then
log.warning(log_tag .. "exceeded 100ms queue process limit")
break
end
end
if not self.connected then
println("与口袋诊断会话 " .. id .. " 的连接已由远程主机关闭")
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
self.periodics.last_update = util.time()
end
return self.connected
end
return public
end
return pocket
