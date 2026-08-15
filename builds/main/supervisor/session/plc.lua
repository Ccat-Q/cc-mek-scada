local comms    = require("scada-common.comms")
local const    = require("scada-common.constants")
local log      = require("scada-common.log")
local mqueue   = require("scada-common.mqueue")
local types    = require("scada-common.types")
local util     = require("scada-common.util")
local databus  = require("supervisor.databus")
local svqtypes = require("supervisor.session.svqtypes")
local plc = {}
local PROTOCOL = comms.PROTOCOL
local RPLC_TYPE = comms.RPLC_TYPE
local MGMT_TYPE = comms.MGMT_TYPE
local PLC_AUTO_ACK = comms.PLC_AUTO_ACK
local UNIT_COMMAND = comms.UNIT_COMMAND
local SV_Q_DATA = svqtypes.SV_Q_DATA
local INITIAL_WAIT      = 1500
local INITIAL_AUTO_WAIT = 1000
local RETRY_PERIOD      = 1000
local PLC_S_CMDS = {
SCRAM = 1,
ASCRAM = 2,
ENABLE = 3,
DISABLE = 4,
RPS_RESET = 5,
RPS_AUTO_RESET = 6
}
local PLC_S_DATA = {
BURN_RATE = 1,
RAMP_BURN_RATE = 2,
AUTO_BURN_RATE = 3
}
plc.PLC_S_CMDS = PLC_S_CMDS
plc.PLC_S_DATA = PLC_S_DATA
local PERIODICS = {
KEEP_ALIVE = 2000
}
function plc.new_session(id, s_addr, i_seq_num, reactor_id, in_queue, out_queue, timeout, initial_reset, fp_ok)
local function println(message) if not fp_ok then util.println_ts(message) end end
local log_tag = "plc_session(" .. id .. "): "
local self = {
commanded_burn_rate = 0.0,
auto_cmd_token = 0,
ramping_rate = false,
auto_lock = false,
seq_num = i_seq_num + 2,
r_seq_num = i_seq_num + 1,
connected = true,
received_struct = false,
received_status_cache = false,
received_rps_status = false,
conn_watchdog = util.new_watchdog(timeout),
last_rtt = 0,
periodics = {
last_update = 0,
keep_alive = 0
},
retry_times = {
struct_req = (util.time() + 500),
status_req = (util.time() + 500),
disable_req = 0,
scram_req = 0,
ascram_req = 0,
burn_rate_req = 0,
rps_reset_req = 0
},
acks = {
disable = true,
scram = true,
ascram = true,
burn_rate = true,
rps_reset = true
},
sDB = types.new_reactor_db()
}
local public = {}
local function _compute_op_temps()
local JOULES_PER_MB = const.mek.JOULES_PER_MB
local BASE_BOIL_TEMP = const.mek.BASE_BOIL_TEMP
local heat_cap = self.sDB.mek_struct.heat_cap
local max_burn = self.sDB.mek_struct.max_burn
self.sDB.max_op_temp_H2O = max_burn * 2 * (JOULES_PER_MB * heat_cap ^ -1) + BASE_BOIL_TEMP
self.sDB.max_op_temp_Na = max_burn * (JOULES_PER_MB * heat_cap ^ -1) + BASE_BOIL_TEMP
log.info(util.sprintf(log_tag .. "computed maximum operational temperatures %.3fK (H2O) and %.3fK (Na)",
self.sDB.max_op_temp_H2O, self.sDB.max_op_temp_Na))
end
local function _copy_rps_status(rps_status)
local rps = self.sDB.rps_status
self.sDB.rps_tripped    = rps_status[1]
self.sDB.rps_trip_cause = rps_status[2]
rps.high_dmg  = rps_status[3]
rps.high_temp = rps_status[4]
rps.low_cool  = rps_status[5]
rps.ex_waste  = rps_status[6]
rps.ex_hcool  = rps_status[7]
rps.fault     = rps_status[8]
rps.timeout   = rps_status[9]
rps.manual    = rps_status[10]
rps.automatic = rps_status[11]
rps.sys_fail  = rps_status[12]
rps.force_dis = rps_status[13]
end
local function _copy_status(mek_data)
local stat   = self.sDB.mek_status
local struct = self.sDB.mek_struct
stat.status        = mek_data[1]
stat.burn_rate     = mek_data[2]
stat.act_burn_rate = mek_data[3]
stat.temp          = mek_data[4]
stat.damage        = mek_data[5]
stat.boil_eff      = mek_data[6]
stat.env_loss      = mek_data[7]
stat.fuel          = mek_data[8]
stat.fuel_fill     = mek_data[9]
stat.waste         = mek_data[10]
stat.waste_fill    = mek_data[11]
stat.ccool_type    = mek_data[12]
stat.ccool_amnt    = mek_data[13]
stat.ccool_fill    = mek_data[14]
stat.hcool_type    = mek_data[15]
stat.hcool_amnt    = mek_data[16]
stat.hcool_fill    = mek_data[17]
if self.received_struct then
stat.fuel_need  = struct.fuel_cap  - stat.fuel_fill
stat.waste_need = struct.waste_cap - stat.waste_fill
stat.cool_need  = struct.ccool_cap - stat.ccool_fill
stat.hcool_need = struct.hcool_cap - stat.hcool_fill
end
end
local function _copy_struct(mek_data)
local struct = self.sDB.mek_struct
struct.length    = mek_data[1]
struct.width     = mek_data[2]
struct.height    = mek_data[3]
struct.min_pos   = mek_data[4]
struct.max_pos   = mek_data[5]
struct.heat_cap  = mek_data[6]
struct.fuel_asm  = mek_data[7]
struct.fuel_sa   = mek_data[8]
struct.fuel_cap  = mek_data[9]
struct.waste_cap = mek_data[10]
struct.ccool_cap = mek_data[11]
struct.hcool_cap = mek_data[12]
struct.max_burn  = mek_data[13]
end
local function _handle_status(pkt)
local data = pkt.data
local db   = self.sDB
local valid = (type(data[1]) == "number") and (type(data[2]) == "boolean") and
(type(data[3]) == "boolean") and (type(data[4]) == "boolean") and
(type(data[5]) == "number") and (type(data[6]) == "number" or data[6] == false)
if valid then
db.last_status_update = data[1]
db.control_state = data[2]
db.no_reactor = data[3]
db.formed = data[4]
db.auto_ack_token = data[5]
db.reportable_max_burn = data[6]
if (not db.no_reactor) and db.formed and (type(data[7]) == "number") then
db.mek_status.heating_rate = data[7] or 0.0
if type(data[8]) == "table" then
if #data[8] == 17 then
_copy_status(data[8])
self.received_status_cache = true
else
log.error(log_tag .. "RPLC status packet reactor data length mismatch")
end
end
end
else
log.debug(log_tag .. "RPLC status packet invalid")
end
end
local function _close()
self.conn_watchdog.cancel()
self.connected = false
databus.tx_plc_disconnected(reactor_id)
end
local function _send(msg_type, msg)
local frame, rplc = comms.scada_frame(), comms.rplc_container()
rplc.make(reactor_id, msg_type, msg)
frame.make(s_addr, self.seq_num, PROTOCOL.RPLC, rplc.raw_packet())
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
local function _get_ack(pkt)
if pkt.length == 1 then
return pkt.data[1]
else
log.debug(log_tag .. "RPLC ACK length mismatch")
return nil
end
end
local function _handle_packet(pkt)
if self.r_seq_num ~= pkt.scada_frame.seq_num() then
log.warning(log_tag .. "sequence out-of-order: next = " .. self.r_seq_num .. ", new = " .. pkt.scada_frame.seq_num())
return
else
self.r_seq_num = pkt.scada_frame.seq_num() + 1
end
if pkt.scada_frame.protocol() == PROTOCOL.RPLC then
if pkt.id ~= reactor_id then
log.warning(log_tag .. "discarding RPLC packet with ID not matching reactor ID: reactor " .. reactor_id .. " != " .. pkt.id)
return
end
self.conn_watchdog.feed()
if pkt.type == RPLC_TYPE.STATUS then
if pkt.length >= 7 then
_handle_status(pkt)
else
log.debug(log_tag .. "RPLC status packet length mismatch")
end
elseif pkt.type == RPLC_TYPE.MEK_STRUCT then
if pkt.length == 13 then
_copy_struct(pkt.data)
_compute_op_temps()
self.received_struct = true
out_queue.push_data(SV_Q_DATA.PLC_BUILD_CHANGED, reactor_id)
else
log.debug(log_tag .. "RPLC struct packet length mismatch")
end
elseif pkt.type == RPLC_TYPE.MEK_BURN_RATE then
local ack = _get_ack(pkt)
if ack then
self.acks.burn_rate = true
elseif ack == false then
log.debug(log_tag .. "burn rate update failed!")
end
elseif pkt.type == RPLC_TYPE.RPS_ENABLE then
local ack = _get_ack(pkt)
if ack then
self.sDB.control_state = true
elseif ack == false then
log.debug(log_tag .. "enable failed!")
end
out_queue.push_data(SV_Q_DATA.CRDN_ACK, {
unit = reactor_id,
cmd = UNIT_COMMAND.START,
ack = ack
})
elseif pkt.type == RPLC_TYPE.RPS_DISABLE then
local ack = _get_ack(pkt)
if ack then
self.acks.disable = true
self.sDB.control_state = false
elseif ack == false then
log.debug(log_tag .. "disable failed!")
end
elseif pkt.type == RPLC_TYPE.RPS_SCRAM then
local ack = _get_ack(pkt)
if ack then
self.acks.scram = true
self.sDB.control_state = false
elseif ack == false then
log.debug(log_tag .. "manual SCRAM failed!")
end
out_queue.push_data(SV_Q_DATA.CRDN_ACK, {
unit = reactor_id,
cmd = UNIT_COMMAND.SCRAM,
ack = ack
})
elseif pkt.type == RPLC_TYPE.RPS_ASCRAM then
local ack = _get_ack(pkt)
if ack then
self.acks.ascram = true
self.sDB.control_state = false
elseif ack == false then
log.debug(log_tag .. " automatic SCRAM failed!")
end
elseif pkt.type == RPLC_TYPE.RPS_STATUS then
if pkt.length == 13 then
local status = pcall(_copy_rps_status, pkt.data)
if status then
self.received_rps_status = true
if initial_reset[reactor_id] then
initial_reset[reactor_id] = false
if self.sDB.rps_trip_cause == "timeout" then
_send(RPLC_TYPE.RPS_AUTO_RESET, {})
log.debug(log_tag .. "initial RPS reset on timeout status sent")
end
end
else
log.error(log_tag .. "failed to parse RPS status packet data")
end
else
log.debug(log_tag .. "RPLC RPS status packet length mismatch")
end
elseif pkt.type == RPLC_TYPE.RPS_ALARM then
if pkt.length == 12 then
local status = pcall(_copy_rps_status, { true, table.unpack(pkt.data) })
if status then
self.received_rps_status = true
if initial_reset[reactor_id] then
initial_reset[reactor_id] = false
if self.sDB.rps_trip_cause == "timeout" then
_send(RPLC_TYPE.RPS_AUTO_RESET, {})
log.debug(log_tag .. "initial RPS reset on timeout alarm sent")
end
end
else
log.error(log_tag .. "failed to parse RPS alarm status data")
end
else
log.debug(log_tag .. "RPLC RPS alarm packet length mismatch")
end
elseif pkt.type == RPLC_TYPE.RPS_RESET then
local ack = _get_ack(pkt)
if ack then
self.acks.rps_reset = true
self.sDB.rps_tripped = false
self.sDB.rps_trip_cause = "ok"
elseif ack == false then
log.debug(log_tag .. "RPS reset failed")
end
out_queue.push_data(SV_Q_DATA.CRDN_ACK, {
unit = reactor_id,
cmd = UNIT_COMMAND.RESET_RPS,
ack = ack
})
elseif pkt.type == RPLC_TYPE.RPS_AUTO_RESET then
local ack = _get_ack(pkt)
if not ack then
log.debug(log_tag .. "RPS auto reset failed")
end
elseif pkt.type == RPLC_TYPE.AUTO_BURN_RATE then
if pkt.length == 1 then
local ack = pkt.data[1]
if ack == PLC_AUTO_ACK.FAIL then
self.acks.burn_rate = false
log.debug(log_tag .. "RPLC automatic burn rate set fail")
elseif ack == PLC_AUTO_ACK.DIRECT_SET_OK or ack == PLC_AUTO_ACK.RAMP_SET_OK or ack == PLC_AUTO_ACK.ZERO_DIS_OK then
self.acks.burn_rate = true
else
self.acks.burn_rate = false
log.debug(log_tag .. "RPLC automatic burn rate ack unknown")
end
else
log.debug(log_tag .. "RPLC automatic burn rate ack packet length mismatch")
end
else
log.debug(log_tag .. "handler received unsupported RPLC packet type " .. pkt.type)
end
elseif pkt.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
if pkt.type == MGMT_TYPE.KEEP_ALIVE then
if pkt.length == 2 then
local srv_start = pkt.data[1]
local srv_now = util.time()
self.last_rtt = srv_now - srv_start
if self.last_rtt > 750 then
log.warning(log_tag .. "PLC KEEP_ALIVE round trip time > 750ms (" .. self.last_rtt .. "ms)")
end
databus.tx_plc_rtt(reactor_id, self.last_rtt)
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
end
end
function public.get_id() return id end
function public.get_db() return self.sDB end
function public.check_received_all_data() return self.received_struct and self.received_status_cache and self.received_rps_status end
function public.is_ramp_complete()
return (self.sDB.auto_ack_token == self.auto_cmd_token) and (self.commanded_burn_rate == self.sDB.mek_status.act_burn_rate)
end
function public.get_struct()
if self.received_struct then
return self.sDB.mek_struct
else
return {}
end
end
function public.get_status()
if self.received_status_cache then
return self.sDB.mek_status
else
return {}
end
end
function public.get_rps()
return self.sDB.rps_status
end
function public.get_general_status()
return {
self.sDB.last_status_update,
self.sDB.control_state,
self.sDB.rps_tripped,
self.sDB.rps_trip_cause,
self.sDB.no_reactor,
self.sDB.formed
}
end
function public.auto_lock(engage)
self.auto_lock = engage
if engage then
self.acks.burn_rate = true
end
end
function public.is_auto_locked() return self.auto_lock end
function public.auto_set_burn(rate, ramp)
self.ramping_rate = ramp
in_queue.push_data(PLC_S_DATA.AUTO_BURN_RATE, rate)
end
function public.check_wd(timer)
return self.conn_watchdog.is_timer(timer) and self.connected
end
function public.close()
_close()
_send_mgmt(MGMT_TYPE.CLOSE, {})
println("connection to reactor " .. reactor_id .. " PLC closed by server")
log.info(log_tag .. "session closed by server")
end
function public.iterate()
if self.connected then
local handle_start = util.time()
while in_queue.ready() and self.connected do
local message = in_queue.pop()
if message ~= nil then
if message.qtype == mqueue.TYPE.NETWORK then
_handle_packet(message.message)
elseif message.qtype == mqueue.TYPE.COMMAND then
local cmd = message.message
if cmd == PLC_S_CMDS.ENABLE then
self.acks.disable = true
if not self.auto_lock then
_send(RPLC_TYPE.RPS_ENABLE, {})
end
elseif cmd == PLC_S_CMDS.DISABLE then
self.acks.disable = false
self.retry_times.disable_req = util.time() + INITIAL_WAIT
_send(RPLC_TYPE.RPS_DISABLE, {})
elseif cmd == PLC_S_CMDS.SCRAM then
self.acks.scram = false
self.retry_times.scram_req = util.time() + INITIAL_WAIT
_send(RPLC_TYPE.RPS_SCRAM, {})
elseif cmd == PLC_S_CMDS.ASCRAM then
self.acks.ascram = false
self.retry_times.ascram_req = util.time() + INITIAL_WAIT
_send(RPLC_TYPE.RPS_ASCRAM, {})
elseif cmd == PLC_S_CMDS.RPS_RESET then
self.acks.ascram = true
self.acks.rps_reset = false
self.retry_times.rps_reset_req = util.time() + INITIAL_WAIT
_send(RPLC_TYPE.RPS_RESET, {})
elseif cmd == PLC_S_CMDS.RPS_AUTO_RESET then
if self.sDB.rps_status.automatic or self.sDB.rps_status.timeout then
_send(RPLC_TYPE.RPS_AUTO_RESET, {})
end
else
log.error(log_tag .. "unsupported command received in in_queue (this is a bug)", true)
end
elseif message.qtype == mqueue.TYPE.DATA then
local cmd = message.message
if cmd.key == PLC_S_DATA.BURN_RATE then
if not self.auto_lock then
cmd.val = math.floor(cmd.val * 10) / 10
if cmd.val > 0 and cmd.val <= self.sDB.mek_struct.max_burn then
self.commanded_burn_rate = cmd.val
self.auto_cmd_token = 0
self.ramping_rate = false
self.acks.burn_rate = false
self.retry_times.burn_rate_req = util.time() + INITIAL_WAIT
_send(RPLC_TYPE.MEK_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate })
end
end
elseif cmd.key == PLC_S_DATA.RAMP_BURN_RATE then
if not self.auto_lock then
cmd.val = math.floor(cmd.val * 10) / 10
if cmd.val > 0 and cmd.val <= self.sDB.mek_struct.max_burn then
self.commanded_burn_rate = cmd.val
self.auto_cmd_token = 0
self.ramping_rate = true
self.acks.burn_rate = false
self.acks.disable = true
self.retry_times.burn_rate_req = util.time() + INITIAL_WAIT
_send(RPLC_TYPE.MEK_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate })
end
end
elseif cmd.key == PLC_S_DATA.AUTO_BURN_RATE then
if self.auto_lock then
cmd.val = math.floor(cmd.val * 100) / 100
if cmd.val >= 0 and cmd.val <= self.sDB.mek_struct.max_burn then
self.auto_cmd_token = util.time_ms()
self.commanded_burn_rate = cmd.val
self.acks.burn_rate = not self.ramping_rate
self.acks.disable = true
self.retry_times.burn_rate_req = util.time() + INITIAL_AUTO_WAIT
_send(RPLC_TYPE.AUTO_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate, self.auto_cmd_token })
end
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
println("connection to reactor " .. reactor_id .. " PLC closed by remote host")
log.info(log_tag .. "session closed by remote host")
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
local rtimes = self.retry_times
if (not self.sDB.no_reactor) and self.sDB.formed then
if not self.received_struct then
if rtimes.struct_req - util.time() <= 0 then
_send(RPLC_TYPE.MEK_STRUCT, {})
rtimes.struct_req = util.time() + RETRY_PERIOD
end
end
if not self.received_status_cache then
if rtimes.status_req - util.time() <= 0 then
_send(RPLC_TYPE.STATUS, {})
rtimes.status_req = util.time() + RETRY_PERIOD
end
end
if not self.acks.burn_rate then
if rtimes.burn_rate_req - util.time() <= 0 then
if self.auto_cmd_token > 0 then
if self.auto_lock then
_send(RPLC_TYPE.AUTO_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate, self.auto_cmd_token })
else
self.acks.burn_rate = true
end
elseif not self.auto_lock then
_send(RPLC_TYPE.MEK_BURN_RATE, { self.commanded_burn_rate, self.ramping_rate })
else
self.acks.burn_rate = true
end
rtimes.burn_rate_req = util.time() + RETRY_PERIOD
end
end
end
if not self.acks.disable then
if rtimes.disable_req - util.time() <= 0 then
_send(RPLC_TYPE.RPS_DISABLE, {})
rtimes.disable_req = util.time() + RETRY_PERIOD
end
end
if not self.acks.scram then
if rtimes.scram_req - util.time() <= 0 then
_send(RPLC_TYPE.RPS_SCRAM, {})
rtimes.scram_req = util.time() + RETRY_PERIOD
end
end
if not self.acks.ascram then
if rtimes.ascram_req - util.time() <= 0 then
_send(RPLC_TYPE.RPS_ASCRAM, {})
rtimes.ascram_req = util.time() + RETRY_PERIOD
end
end
if not self.acks.rps_reset then
if rtimes.rps_reset_req - util.time() <= 0 then
_send(RPLC_TYPE.RPS_RESET, {})
rtimes.rps_reset_req = util.time() + RETRY_PERIOD
end
end
end
return self.connected
end
return public
end
return plc
